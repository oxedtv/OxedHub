local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────────
-- TEST_ICON_AURA event type
-- ─────────────────────────────────────────────────────────────────────────────

-- Helper to get configured spell icon IDs
local function GetConfiguredIconIDs(trigger)
    local icons = {}
    local seen = {}
    local c = trigger.conditions or {}

    local function addIconFromSpellID(val)
        if not val then return end
        local n = tonumber(val)
        if not n and type(val) == "string" and val ~= "" and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(val)
            if info and info.spellID then n = info.spellID end
        end
        if n then
            local info = C_Spell.GetSpellInfo(n)
            if info and info.iconID and not seen[info.iconID] then
                seen[info.iconID] = true
                table.insert(icons, info.iconID)
            end
        end
    end

    addIconFromSpellID(c.spellID)
    addIconFromSpellID(c.spellName)
    addIconFromSpellID(c.auraName)

    if c.extraSpellIDs then
        for _, s in ipairs(c.extraSpellIDs) do
            addIconFromSpellID(s)
        end
    end

    return icons
end

-- A hidden FontString used to launder secret strings into plain strings
local launderFrame = CreateFrame("Frame")
local launderText = launderFrame:CreateFontString(nil, "BACKGROUND", "GameFontNormal")

-- Advanced comparison that safely handles WoW's secret value protections.
-- If an aura is "secret" (like Survival Instincts), this will return false
-- because WoW physically prevents addon code from comparing secret values.
-- If an aura is NOT secret (like many trinket procs or food), this returns true on match.
local function SafeIconEquals(auraIcon, targetIconStr)
    if auraIcon == nil then return false end
    
    local okStr, iconStr = pcall(tostring, auraIcon)
    if not okStr or not iconStr then return false end

    -- Just a direct pcall comparison. If it's secret, ok is false. If not, it compares normally.
    local ok, res = pcall(function(a, b) return a == b end, iconStr, targetIconStr)
    return ok and res or false
end

local function HasConfiguredAuraIcon(trigger)
    local targetIcons = GetConfiguredIconIDs(trigger)
    if #targetIcons == 0 then return false, nil, nil end

    local targetIconStrs = {}
    for idx, iconID in ipairs(targetIcons) do
        targetIconStrs[idx] = tostring(iconID)
    end

    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return false, nil, nil
    end

    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if ok and not aura then break end

        if ok and aura then
            -- Try to safely read the aura's icon
            local okIcon, auraIcon = pcall(function() return aura.icon end)
            
            if okIcon and auraIcon then
                for idx, targetStr in ipairs(targetIconStrs) do
                    if SafeIconEquals(auraIcon, targetStr) then
                        -- Matched!
                        local resolvedSid = nil
                        local okSid, sid = pcall(function() return aura.spellId end)
                        if okSid and sid then
                            local okNum, num = pcall(tonumber, tostring(sid))
                            if okNum and num then resolvedSid = num end
                        end
                        return true, targetIcons[idx], resolvedSid
                    end
                end
            end
        end
    end

    return false, nil, nil
end

Triggers:RegisterEventType("TEST_ICON_AURA", {
    name = "Test Trigger (by Icon ID)",
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}

        if Triggers.CreateAuraSpellSearchUI then
            yOffset = Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end

        local iconInfoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconInfoText:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 5)
        
        local lastState = ""
        frame:HookScript("OnUpdate", function()
            local c = trigger.conditions or {}
            local currentState = tostring(c.spellID) .. (c.extraSpellIDs and #c.extraSpellIDs or 0)
            if currentState ~= lastState then
                lastState = currentState
                local icons = GetConfiguredIconIDs(trigger)
                if #icons > 0 then
                    iconInfoText:SetText("|cffff8800Monitoring Icon ID(s): " .. table.concat(icons, ", ") .. "|r")
                else
                    iconInfoText:SetText("")
                end
            end
        end)

        yOffset = yOffset - 25

        local loopCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        loopCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        loopCheck:SetSize(20, 20)
        loopCheck:SetChecked(conditions.loopSound or false)
        loopCheck.text:SetText("Loop sound until lost")

        local loopIntervalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        loopIntervalLabel:SetPoint("LEFT", loopCheck.text, "RIGHT", 10, 0)
        loopIntervalLabel:SetText("Interval (s):")

        local loopIntervalEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        loopIntervalEdit:SetPoint("LEFT", loopIntervalLabel, "RIGHT", 5, 0)
        loopIntervalEdit:SetSize(30, 20)
        loopIntervalEdit:SetAutoFocus(false)
        loopIntervalEdit:SetNumeric(true)
        loopIntervalEdit:SetText(tostring(conditions.loopInterval or 2))

        loopCheck:SetScript("OnClick", function(self)
            conditions.loopSound = self:GetChecked()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)

        loopIntervalEdit:SetScript("OnTextChanged", function(self)
            local val = tonumber(self:GetText())
            if val and val > 0 then
                conditions.loopInterval = val
                if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
            end
        end)

        yOffset = yOffset - 25

        local lostCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        lostCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        lostCheck:SetSize(20, 20)
        lostCheck:SetChecked(conditions.onLost or false)
        lostCheck.text:SetText("Trigger on Lost")

        local bothCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        bothCheck:SetPoint("LEFT", lostCheck.text, "RIGHT", 10, 0)
        bothCheck:SetSize(20, 20)
        bothCheck:SetChecked(conditions.onBoth or false)
        bothCheck.text:SetText("Trigger on Both")

        lostCheck:SetScript("OnClick", function(self)
            conditions.onLost = self:GetChecked()
            if self:GetChecked() then
                bothCheck:SetChecked(false)
                conditions.onBoth = false
            end
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)

        bothCheck:SetScript("OnClick", function(self)
            conditions.onBoth = self:GetChecked()
            if self:GetChecked() then
                lostCheck:SetChecked(false)
                conditions.onLost = false
            end
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)

        yOffset = yOffset - 25
        return yOffset
    end
})

-- ── Monitor ──────────────────────────────────────────────────────────────────
local testAuraPresent = {}

local function CancelLoop(triggerId, trigger)
    if not Triggers.activeAuraLoops then return end
    local targetIcons = GetConfiguredIconIDs(trigger)
    for _, iconID in ipairs(targetIcons) do
        local key = Triggers:BuildAuraLoopKey(triggerId, iconID)
        local ticker = Triggers.activeAuraLoops[key]
        if ticker then
            ticker:Cancel()
            Triggers.activeAuraLoops[key] = nil
        end
    end
end

local function EvaluateTestAuraTriggers(initial)
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end

    for id, trigger in pairs(profile.triggers) do
        if trigger.event == "TEST_ICON_AURA" and trigger.enabled then
            local present, matchedIcon, matchedSpellId = HasConfiguredAuraIcon(trigger)
            local was = testAuraPresent[id]

            local c = trigger.conditions or {}
            if initial then
                testAuraPresent[id] = present or nil
            elseif present and not was then
                testAuraPresent[id] = true
                local fireOnGained = c.onBoth or not c.onLost
                if fireOnGained and Triggers:CheckZoneRestrictions(trigger.zones) then
                    Triggers:ExecuteTrigger(trigger, { spellID = matchedSpellId, iconID = matchedIcon, isLost = false })
                end
            elseif not present and was then
                testAuraPresent[id] = nil
                CancelLoop(id, trigger)
                if (c.onLost or c.onBoth) and Triggers:CheckZoneRestrictions(trigger.zones) then
                    local targetIcons = GetConfiguredIconIDs(trigger)
                    Triggers:ExecuteTrigger(trigger, { iconID = targetIcons[1], isLost = true })
                end
            end
        end
    end
end

local monitor = CreateFrame("Frame")
monitor:RegisterUnitEvent("UNIT_AURA", "player")
monitor:RegisterEvent("PLAYER_ENTERING_WORLD")
monitor:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        wipe(testAuraPresent)
        EvaluateTestAuraTriggers(true)
    else
        EvaluateTestAuraTriggers(false)
    end
end)
