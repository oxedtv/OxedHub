local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

function Triggers.TrimText(text)
    if text == nil then
        return ""
    end
    return tostring(text):match("^%s*(.-)%s*$") or ""
end

local function NormalizeExtraMacroText(text)
    if not text or text == "" then
        return nil
    end

    local lines = {}
    for line in tostring(text):gmatch("[^\r\n]+") do
        local trimmed = Triggers.TrimText(line)
        if trimmed ~= "" then
            lines[#lines + 1] = trimmed
        end
    end

    if #lines == 0 then
        return nil
    end

    return table.concat(lines, "\n")
end

function Triggers.NormalizeMacroBodyText(text)
    if text == nil then
        return nil
    end

    text = tostring(text):gsub("\r\n", "\n"):gsub("\r", "\n")
    if Triggers.TrimText(text) == "" then
        return nil
    end

    return text
end

local function ResolveMacroSpellID(identifier)
    local raw = Triggers.TrimText(identifier)
    if raw == "" then
        return nil
    end

    local linkId = raw:match("spell:(%d+)")
    local numericId = tonumber(linkId or raw)
    local spellInfo = C_Spell.GetSpellInfo(numericId or raw)
    if spellInfo and spellInfo.spellID then
        return spellInfo.spellID
    end

    if not numericId then
        local exactMatches = Triggers:SearchPlayerSpells(raw, 50, true)
        local wanted = raw:lower()
        for _, match in ipairs(exactMatches) do
            if match and match.id and match.name and match.name:lower() == wanted then
                return match.id
            end
        end
        if exactMatches[1] and exactMatches[1].id then
            return exactMatches[1].id
        end
    end

    return numericId
end

local function StripMacroConditionPrefixes(text)
    local value = Triggers.TrimText(text)
    while value:match("^%b[]") do
        value = Triggers.TrimText((value:gsub("^%b[]%s*", "", 1)))
    end
    return value
end

local function FindSpellIDInMacroClauses(text, isSequence)
    local clauses = {}
    for clause in tostring(text or ""):gmatch("[^;]+") do
        clauses[#clauses + 1] = clause
    end
    if #clauses == 0 then
        clauses[1] = text
    end

    for _, clause in ipairs(clauses) do
        local candidate = StripMacroConditionPrefixes(clause)
        candidate = candidate:gsub("^!+", "")
        if isSequence then
            candidate = Triggers.TrimText((candidate:gsub("^reset=[^%s]+%s*", "", 1)))
            candidate = Triggers.TrimText((candidate:match("^([^,]+)") or candidate))
        end

        local spellID = ResolveMacroSpellID(candidate)
        if spellID then
            return spellID
        end
    end

    return nil
end

local function ExtractCooldownSpellIDFromMacroBody(body)
    body = Triggers.NormalizeMacroBodyText(body)
    if not body then
        return nil
    end

    local showTooltipCandidate = nil

    for rawLine in body:gmatch("[^\n]+") do
        local line = Triggers.TrimText(rawLine)
        if line ~= "" then
            local command, rest = line:match("^([#/]%S+)%s*(.-)%s*$")
            local lowerCommand = command and string.lower(command)

            if lowerCommand == "#showtooltip" and rest and rest ~= "" then
                local spellID = FindSpellIDInMacroClauses(rest, false)
                if spellID then
                    return spellID
                end
                showTooltipCandidate = showTooltipCandidate or rest
            elseif lowerCommand == "/castsequence" then
                local spellID = FindSpellIDInMacroClauses(rest, true)
                if spellID then
                    return spellID
                end
            elseif lowerCommand == "/cast" or lowerCommand == "/use" then
                local spellID = FindSpellIDInMacroClauses(rest, false)
                if spellID then
                    return spellID
                end
            end
        end
    end

    if showTooltipCandidate then
        return FindSpellIDInMacroClauses(showTooltipCandidate, false)
    end

    return nil
end

function Triggers:SupportsAdvancedMacros(trigger)
    return trigger and trigger.event == "UNIT_SPELLCAST_SUCCEEDED"
end

function Triggers:GetTriggerMacroName(trigger)
    return "OH_" .. trigger.id
end

function Triggers:ResolveCustomMacroIcon(iconValue)
    if OxedHub.IconPicker and OxedHub.IconPicker.ResolveTexture then
        return OxedHub.IconPicker:ResolveTexture(iconValue)
    end

    local raw = Triggers.TrimText(iconValue)
    return raw ~= "" and raw or nil
end

function Triggers:GetTriggerDisplayIcon(trigger)
    if not trigger then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local customIcon = self:ResolveCustomMacroIcon(trigger.customMacroIcon)
    if customIcon then
        return customIcon
    end

    local spellID = trigger.conditions and trigger.conditions.spellID
    if spellID then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.iconID then
            return spellInfo.iconID
        end
    end

    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Triggers:BuildDefaultTriggerMacroBody(trigger)
    local conditions = trigger.conditions or {}
    local spellID = conditions.spellID
    if not spellID then return nil end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return nil end

    local body = string.format("#showtooltip %s\n/cast %s", spellInfo.name, spellInfo.name)

    -- Inject toy /use lines if a toy is assigned
    local actions = trigger.actions or {}
    if actions.toy and actions.toy ~= "" then
        local toyStr = tostring(actions.toy)
        local directID = toyStr:match("^toyid:(%d+)$")
        if directID then
            local itemID = tonumber(directID)
            if itemID then
                local _, toyName = C_ToyBox.GetToyInfo(itemID)
                if toyName and PlayerHasToy(itemID) then
                    body = body .. "\n/use " .. toyName
                end
            end
        else
            local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[actions.toy]
            if type(mixData) == "table" and mixData.slots then
                for _, slot in ipairs(mixData.slots) do
                    if slot and slot.type == "toy" then
                        local _, toyName = C_ToyBox.GetToyInfo(slot.id)
                        if toyName and PlayerHasToy(slot.id) then
                            body = body .. "\n/use " .. toyName
                        end
                    end
                end
            end
        end
    end

    body = body .. string.format("\n/run OxedHub.Triggers:ExecuteTriggerByID(\"%s\", false)", trigger.id)
    return body
end

function Triggers:SyncGeneratedTriggerMacros()
    if InCombatLockdown() then
        return
    end

    local triggers = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers
    if type(triggers) ~= "table" then
        return
    end

    for _, trigger in pairs(triggers) do
        if trigger and trigger.id and not Triggers.NormalizeMacroBodyText(trigger.customMacroBody) then
            local macroName = self:GetTriggerMacroName(trigger)
            local index = GetMacroIndexByName(macroName)
            if index and index > 0 then
                local _, icon, body = GetMacroInfo(index)
                local legacyCall = string.format('ExecuteTriggerByID("%s", true)', trigger.id)
                if body and body:find(legacyCall, 1, true) then
                    local nextBody = self:BuildDefaultTriggerMacroBody(trigger)
                    if nextBody and nextBody ~= body then
                        pcall(EditMacro, index, macroName, icon, nextBody, 1, 1)
                    end
                end
            end
        end
    end
end

function Triggers:BuildTriggerMacroBody(trigger)
    local customBody = Triggers.NormalizeMacroBodyText(trigger and trigger.customMacroBody)
    if customBody then
        return customBody
    end

    return self:BuildDefaultTriggerMacroBody(trigger)
end

function Triggers:GetTriggerCooldownSpellID(trigger)
    if not trigger then
        return nil
    end

    local bodySpellID = ExtractCooldownSpellIDFromMacroBody(self:BuildTriggerMacroBody(trigger))
    if bodySpellID then
        return bodySpellID
    end

    local spellID = trigger.conditions and trigger.conditions.spellID
    return spellID and ResolveMacroSpellID(spellID) or nil
end

function Triggers:ExecuteTriggerByID(id, skipChat)
    local trigger = OxedHub.db.profile.triggers[id]
    if trigger and trigger.enabled then
        -- Mark spell as manually triggered so UNIT_SPELLCAST_SUCCEEDED doesn't double-fire
        if trigger.conditions and trigger.conditions.spellID then
            local sid = tonumber(trigger.conditions.spellID)
            if sid then
                OxedHub._manualSpellTrigger = { spellID = sid, time = GetTime() }
            end
        end
        self:ExecuteTrigger(trigger, { sourceName = UnitName("player"), isManual = true }, skipChat)
    end
end


function Triggers:CreateMacroForTrigger(trigger)
    if InCombatLockdown() then
        print("|cffff0000[OxedHub]|r Cannot create macros in combat.")
        return
    end

    local body = self:BuildTriggerMacroBody(trigger)
    if not body then
        print("|cffff0000[OxedHub]|r No spell selected for this trigger.")
        return
    end

    local macroName = self:GetTriggerMacroName(trigger)
    local macroIcon = self:ResolveCustomMacroIcon(trigger.customMacroIcon) or "INV_MISC_QUESTIONMARK"

    local index = GetMacroIndexByName(macroName)
    if index > 0 then
        EditMacro(index, macroName, macroIcon, body)
        print("|cff00ff00[OxedHub]|r Trigger macro updated. Drag the icon to your bar.")
    else
        local numGlobal, numChar = GetNumMacros()
        if numChar >= 18 then
            print("|cffff0000[OxedHub]|r Your Character Macro slots are full (18/18). Please delete one.")
            return
        end
        CreateMacro(macroName, macroIcon, body, 1)
        print("|cff00ff00[OxedHub]|r Trigger macro created. Drag the icon to your bar!")
    end
    return macroName
end


