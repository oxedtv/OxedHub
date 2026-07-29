local addonName, OxedHub = ...

-- Triggers Module - Trigger rule logic and event dispatcher
local Triggers = {}
OxedHub.Triggers = Triggers
local L = OxedHub.L
Triggers.registeredTypes = {}
function Triggers:RegisterEventType(eventType, data)
    self.registeredTypes[eventType] = data
end

function Triggers:GetEventTypeHandler(eventType)
    return self.registeredTypes[eventType]
end

-- Local references
local C_Timer = C_Timer
local IsInInstance = IsInInstance
local GetTime = GetTime
local enabledEventCache = {}
local enabledEventCacheDirty = true

-- Deep-copy a table (recursively copies nested tables)
local function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Helper: Chat/Emote is ONLY allowed for UNIT_SPELLCAST_SUCCEEDED when the setting is on.
-- Interrupts, Boss Kill, Player Died, Control Lost, etc. never allow it.
function Triggers:IsChatAllowedForEvent(eventType)
    -- Chat is only safe from a hardware event (ActionHub/OxedRing button click).
    -- Automatic events (Summon, etc.) get blocked by Blizzard (ADDON_ACTION_BLOCKED)
    -- when they try to SendChatMessage, so chat is disabled for them.
    if eventType == "UNIT_SPELLCAST_SUCCEEDED" or eventType == "EAT_BUFF" then
        return OxedHub.db.profile.settings.allowChatOnSpellCast == true
    end
    if eventType == "MOUNT" then
        return true
    end
    -- M+ completion: safe to announce once the run has ended. Blizzard's
    -- ChallengeMode addon restriction is checked at send time (see
    -- OxedHub:CanSendAutomatedChat), and SAY/YELL are still filtered out by the
    -- chat dispatcher because they need a hardware event.
    if eventType == "CHALLENGE_MODE_COMPLETED" then
        return true
    end
    return false
end

-- Helper: Extract spell ID from hyperlink (e.g., |Hspell:783|h[Sprint]|h|r)
local function ExtractSpellIDFromLink(link)
    if not link then return nil end
    -- Match spell:12345 pattern
    local spellID = link:match("spell:(%d+)")
    return spellID and tonumber(spellID)
end

-- Helper: Search for spells by name in player's spellbook (modern API)
function Triggers:SearchPlayerSpells(searchText, maxResults, allClasses)
    if not searchText or searchText == "" then return {} end
    maxResults = maxResults or 10
    local results = {}

    -- Dedup: the same spell can appear in LibPlayerSpells, the local spellbook,
    -- and flyouts (sometimes under multiple spell IDs with the same name). Collapse
    -- by lower-cased name so the dropdown never lists a spell twice.
    local seen = {}
    local function addResult(name, id, icon)
        if not name then return false end
        local key = name:lower()
        if seen[key] then return false end
        seen[key] = true
        table.insert(results, { name = name, id = id, icon = icon })
        return true
    end

    -- SAFETY: Direct ID lookup
    local numericId = tonumber(searchText)
    if numericId then
        local spellInfo = C_Spell.GetSpellInfo(numericId)
        if spellInfo and spellInfo.name then
            addResult(spellInfo.name, numericId, spellInfo.iconID)
        end
    end
    
    searchText = searchText:lower()
    
    -- Expanded Global Database (cross-class buffs). On by default; only skipped
    -- when "All Classes" is explicitly unchecked (allClasses == false).
    if allClasses ~= false then
        local LibPlayerSpells = LibStub and LibStub:GetLibrary("LibPlayerSpells-1.0", true)
        if LibPlayerSpells then
            -- Use LibPlayerSpells for comprehensive spell search across all classes
            for id in LibPlayerSpells:IterateSpells() do
                local spellInfo = C_Spell.GetSpellInfo(id)
                if spellInfo and spellInfo.name and spellInfo.name:lower():find(searchText, 1, true) then
                    addResult(spellInfo.name, id, spellInfo.iconID)
                    if #results >= maxResults then return results end
                end
            end
        else
            -- Fallback to the hardcoded list if LibPlayerSpells is missing
            local globalSpellIDs = {
                2825,   -- Bloodlust (Horde Shaman)
                32182,  -- Heroism (Alliance Shaman)
                80353,  -- Time Warp (Mage)
                390386, -- Fury of the Aspects (Evoker)
                264667, -- Primal Rage (Hunter)
                1243972,-- Void-touched Drums
                90355,  -- Ancient Hysteria (Hunter pet - Core Hound)
                10060,  -- Power Infusion
                29166,  -- Innervate
                1022,   -- Blessing of Protection
                1044,   -- Blessing of Freedom
                33206,  -- Pain Suppression
                47788,  -- Guardian Spirit
                431952, -- Tempered Potion
            }
            for _, id in ipairs(globalSpellIDs) do
                local spellInfo = C_Spell.GetSpellInfo(id)
                if spellInfo and spellInfo.name and spellInfo.name:lower():find(searchText, 1, true) then
                    addResult(spellInfo.name, id, spellInfo.iconID)
                    if #results >= maxResults then return results end
                end
            end
        end
    end
    
    -- Local Spellbook Search
    local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
    for skillLineIndex = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if skillLineInfo then
            local numSpells = skillLineInfo.numSpellBookItems or 0
            for spellIndex = skillLineInfo.itemIndexOffset, skillLineInfo.itemIndexOffset + numSpells - 1 do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(spellIndex, Enum.SpellBookSpellBank.Player)
                if spellInfo then
                    if spellInfo.itemType == Enum.SpellBookItemType.Flyout and spellInfo.actionID then
                        local flyoutID = spellInfo.actionID
                        local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutID)
                        if isKnown and numSlots and numSlots > 0 then
                            for i = 1, numSlots do
                                local flyoutSpellID, _, isKnownSlot = GetFlyoutSlotInfo(flyoutID, i)
                                if isKnownSlot and flyoutSpellID then
                                    local flyoutSpellInfo = C_Spell.GetSpellInfo(flyoutSpellID)
                                    if flyoutSpellInfo and flyoutSpellInfo.name and flyoutSpellInfo.name:lower():find(searchText, 1, true) then
                                        addResult(flyoutSpellInfo.name, flyoutSpellID, flyoutSpellInfo.iconID)
                                        if #results >= maxResults then return results end
                                    end
                                end
                            end
                        end
                    elseif spellInfo.spellID then
                        local spellName = C_SpellBook.GetSpellBookItemName(spellIndex, Enum.SpellBookSpellBank.Player)
                        if spellName and spellName:lower():find(searchText, 1, true) then
                            addResult(spellName, spellInfo.spellID, C_SpellBook.GetSpellBookItemTexture(spellIndex, Enum.SpellBookSpellBank.Player))
                            if #results >= maxResults then return results end
                        end
                    end
                end
            end
        end
    end
    return results
end

-- Trigger cards cache
Triggers.triggerCards = {}













local TRIGGER_ACTIONS_HEIGHT = 150
local TRIGGER_ZONE_HEIGHT = 35
local TRIGGER_BUTTONS_HEIGHT = 24
local TRIGGER_SECTION_SPACING = 10
local TRIGGER_CARD_BOTTOM_PADDING = 8


-- Helper to show auto-saved text
local function ShowAutoSaved(card)
    if not card then return end
    if not card.autoSaveText then
        local text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPRIGHT", card, "TOPRIGHT", -40, -40)
        text:SetText("|cff00ff00Auto-saved|r")
        text:SetAlpha(0)
        
        local ag = text:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.1)
        fadeIn:SetOrder(1)
        
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(1.0)
        hold:SetOrder(2)
        
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.5)
        fadeOut:SetOrder(3)
        
        card.autoSaveText = text
        card.autoSaveAnim = ag
    end
    card.autoSaveAnim:Stop()
    card.autoSaveAnim:Play()

    -- Any trigger edit may have changed a SELF_AURA spell/sound — re-sync the
    -- native aura-sound registrations (debounced; skipped in combat).
    if Triggers.RefreshSelfAuraNativeSounds then
        Triggers._selfAuraRefreshPending = true
        C_Timer.After(0.4, function()
            if Triggers._selfAuraRefreshPending then
                Triggers._selfAuraRefreshPending = nil
                Triggers:RefreshSelfAuraNativeSounds()
            end
        end)
    end
end

Triggers.ShowAutoSaved = ShowAutoSaved

-- Initialize
function Triggers:Init()
    local triggers = OxedHub.db.profile.triggers or {}

    -- Clean up old space-based macros from previous versions
    for id, trigger in pairs(triggers) do
        if trigger.macroName then
            local oldIndex = GetMacroIndexByName(trigger.macroName)
            if oldIndex > 0 then
                DeleteMacro(oldIndex)
            end
            trigger.macroName = nil
        end
    end

    -- Fix triggers that share conditions/actions/zones due to old shallow CopyTable bug
    local seenTables = {}
    for id, trigger in pairs(triggers) do
        for _, key in ipairs({"conditions", "actions", "zones"}) do
            local t = trigger[key]
            if type(t) == "table" then
                if seenTables[t] then
                    -- This table is shared with another trigger; deep-copy it
                    trigger[key] = DeepCopy(t)
                else
                    seenTables[t] = true
                end
            end
        end
    end

    self:SyncGeneratedTriggerMacros()
    self:InvalidateEnabledEventCache()
    if self.RefreshSelfAuraNativeSounds then
        self:RefreshSelfAuraNativeSounds()
    end
end

function Triggers:InvalidateEnabledEventCache()
    enabledEventCacheDirty = true
end

function Triggers:RebuildEnabledEventCache()
    enabledEventCache = {}

    local profile = OxedHub.db and OxedHub.db.profile
    local triggers = profile and profile.triggers
    if triggers then
        for _, trigger in pairs(triggers) do
            if trigger.enabled and trigger.event then
                enabledEventCache[trigger.event] = true
            end
        end
    end

    enabledEventCacheDirty = false
end

function Triggers:HasEnabledTriggerForEvent(eventType)
    if enabledEventCacheDirty then
        self:RebuildEnabledEventCache()
    end

    return enabledEventCache[eventType] == true
end

function Triggers:RefreshAllCards()
    for id, _ in pairs(Triggers.triggerCards) do
        self:RefreshTriggerCard(id)
    end
end




-- Create a new trigger
function Triggers:CreateNewTrigger()
    local id = OxedHub:GenerateID("trigger")
    local trigger = {
        id = id,
        name = "New Trigger",
        event = "UNIT_SPELLCAST_SUCCEEDED",
        conditions = {},
        actions = {},
        zones = {
            OPEN_WORLD = true,
            PARTY = true,
            DELVE = true,
            RAID = true,
            PVP = true,
            BATTLEGROUND = true,
        },
        enabled = true,
        customMacroIcon = nil,
        extraMacroText = nil,
        customMacroBody = nil,
    }
    
    OxedHub.db.profile.triggers[id] = trigger
    self:InvalidateEnabledEventCache()
    self.selectedTriggerId = id
    self:RefreshTriggersList()
    
    return trigger
end

-- Deep-copy a table (recursively copies nested tables)

-- Duplicate a trigger
function Triggers:DuplicateTrigger(id)
    local source = OxedHub.db.profile.triggers[id]
    if not source then return end

    local newId = OxedHub:GenerateID("trigger")
    local copy = DeepCopy(source)
    copy.id = newId
    copy.name = source.name .. " (Copy)"
    copy.enabled = false -- Disable by default

    OxedHub.db.profile.triggers[newId] = copy
    self:InvalidateEnabledEventCache()
    self.selectedTriggerId = newId
    self:RefreshTriggersList()
end

-- Delete a trigger
function Triggers:_PerformDeleteTrigger(id)
    local trigger = OxedHub.db.profile.triggers[id]
    if trigger then
        -- Delete associated WoW macro if it exists
        local macroName = self:GetTriggerMacroName(trigger)
        local index = GetMacroIndexByName(macroName)
        if index > 0 then
            DeleteMacro(index)
        end
        -- Also clean up old space-based macro if present
        if trigger.macroName then
            local oldIndex = GetMacroIndexByName(trigger.macroName)
            if oldIndex > 0 then
                DeleteMacro(oldIndex)
            end
            trigger.macroName = nil
        end
    end
    OxedHub.db.profile.triggers[id] = nil
    self:InvalidateEnabledEventCache()
    if Triggers.triggerCards[id] then
        Triggers.triggerCards[id]:Hide()
        Triggers.triggerCards[id] = nil
    end
    if self.selectedTriggerId == id then
        self.selectedTriggerId = nil
    end
    self:RefreshTriggersList()
end

function Triggers:DeleteTrigger(id)
    local trigger = OxedHub.db.profile.triggers[id]
    if not trigger then return end

    -- Check if skip confirmation is enabled
    if OxedHub.db.profile.settings and OxedHub.db.profile.settings.skipDeleteConfirmation then
        self:_PerformDeleteTrigger(id)
        return
    end

    -- Show confirmation dialog
    local triggerName = trigger.name or tostring(id)
    StaticPopupDialogs["OXEDHUB_CONFIRM_DELETE_TRIGGER"] = {
        text = L["TR_CONFIRM_DELETE_TRIGGER"] or "Are you sure you wish to delete the trigger '%s'?",
        button1 = L["SETTINGS_BTN_YES"] or "Yes",
        button2 = L["SETTINGS_BTN_NO"] or "No",
        OnAccept = function(self, data)
            Triggers:_PerformDeleteTrigger(data)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_CONFIRM_DELETE_TRIGGER", triggerName, nil, id)
end

-- Build a table-safe key for aura loop tracking. Aura spellIDs can be "secret"
-- values (WoW aura-privacy taint) that cannot be concatenated or used as table
-- keys; secret ids bucket to a constant marker so the create side and the cancel
-- side still produce a matching key. Used by both ProcessEvent (cancel) and
-- Execution (create).
local auraLoopKeyTest = {}
function Triggers:BuildAuraLoopKey(triggerId, spellID)
    local part = "secret"
    if spellID ~= nil then
        local ok = pcall(function() auraLoopKeyTest[spellID] = true end)
        if ok then
            auraLoopKeyTest[spellID] = nil
            part = tostring(spellID)
        end
    end
    return tostring(triggerId) .. "_" .. part
end

-- Process event and execute matching triggers
function Triggers:ProcessEvent(eventType, eventData)
    local profile = OxedHub.db.profile
    
    if eventType == "UNIT_AURA" and eventData and eventData.isLost and self.activeAuraLoops then
        for id, trigger in pairs(profile.triggers) do
            if trigger.event == "UNIT_AURA" or trigger.event == "SELF_AURA" then
                local spellID = eventData.spellID or eventData.spellName
                if spellID then
                    local loopKey = self:BuildAuraLoopKey(id, spellID)
                    if self.activeAuraLoops[loopKey] then
                        self.activeAuraLoops[loopKey]:Cancel()
                        self.activeAuraLoops[loopKey] = nil
                    end
                end
            end
        end
    end
    
    for id, trigger in pairs(profile.triggers) do
        if trigger.enabled and self:ShouldTrigger(trigger, eventType, eventData) then
            self:ExecuteTrigger(trigger, eventData)
        end
    end
end

-- Check if trigger should fire
function Triggers:ShouldTrigger(trigger, eventType, eventData)
    -- Check event type match (allow SELF_AURA triggers to match UNIT_AURA events)
    local isTypeMatch = (trigger.event == eventType) or (eventType == "UNIT_AURA" and trigger.event == "SELF_AURA")
    if not isTypeMatch then
        return false
    end
    
    -- Check zone restrictions
    if not self:CheckZoneRestrictions(trigger.zones) then
        return false
    end
    
    -- Check conditions
    local conditions = trigger.conditions or {}
    
    -- Spell/Aura specific conditions (only evaluate if eventData has related fields)
    if eventData.spellID or eventData.spellName or eventType == "UNIT_AURA" or eventType == "UNIT_SPELLCAST_SUCCEEDED" or eventType == "CD_READY" or eventType:find("INTERRUPT") or eventType == "SPELL_INTERRUPTED" or eventType == "CONTROL_LOST" then
        
        -- Prevent unconfigured triggers from firing on every single spell/aura event
        -- NOTE: SPELL_INTERRUPTED is deliberately NOT in this list. It only fires
        -- when the player's own cast is actually interrupted (rare, not spammy),
        -- so leaving the spell field empty means "any interrupted cast".
        local requiresSpell = (eventType == "UNIT_SPELLCAST_SUCCEEDED" or eventType == "UNIT_AURA" or eventType == "CD_READY" or eventType == "INTERRUPT_SUCCESS")
        local hasSpellCond = (conditions.spellID and conditions.spellID ~= "")
        local hasAuraCond = (conditions.auraName and conditions.auraName ~= "")
        if requiresSpell and not hasSpellCond and not hasAuraCond then
            return false
        end

        -- Spell ID condition (matches the primary OR any extra spell)
        if conditions.spellID and conditions.spellID ~= "" then
            local targetID = tonumber(conditions.spellID)
            local matched = false
            
            -- 1. Try numeric/string equality comparison
            if eventData.spellID and targetID then
                local expectedStr = tostring(targetID)
                local actualStr = tostring(eventData.spellID)
                local ok, res = pcall(function() return expectedStr == actualStr end)
                if ok and res then matched = true end
            end
            
            -- 2. Match by spell name via C_Spell.GetSpellInfo(targetID) (safe against secret strings)
            if not matched and targetID and eventData.spellName then
                local expectedInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(targetID)
                if expectedInfo and expectedInfo.name then
                    local okEq, resEq = pcall(function() return expectedInfo.name == eventData.spellName end)
                    if okEq and resEq then
                        matched = true
                    else
                        local okLower, resLower = pcall(function() 
                            return string.lower(tostring(expectedInfo.name)) == string.lower(tostring(eventData.spellName)) 
                        end)
                        if okLower and resLower then
                            matched = true
                        end
                    end
                end
            end

            -- 3. Match by checking player aura via Blizzard C_UnitAuras APIs (for aura gain events)
            if not matched and targetID and C_UnitAuras and not (eventData and eventData.isLost) then
                if C_UnitAuras.GetAuraDataBySpellID then
                    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", targetID)
                    if ok and aura then matched = true end
                end
                if not matched and C_UnitAuras.GetPlayerAuraBySpellID then
                    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, targetID)
                    if ok and aura then matched = true end
                end
            end

            -- 4. Check extra spell IDs if configured
            if not matched and conditions.extraSpellIDs then
                for _, sid in ipairs(conditions.extraSpellIDs) do
                    local extraID = tonumber(sid)
                    if extraID and eventData.spellID then
                        local okEx, resEx = pcall(function() return tostring(extraID) == tostring(eventData.spellID) end)
                        if okEx and resEx then
                            matched = true
                            break
                        end
                    end
                    if extraID and eventData.spellName then
                        local extraInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(extraID)
                        if extraInfo and extraInfo.name then
                            local okEq, resEq = pcall(function() return extraInfo.name == eventData.spellName end)
                            if okEq and resEq then
                                matched = true
                                break
                            else
                                local okLower, resLower = pcall(function() 
                                    return string.lower(tostring(extraInfo.name)) == string.lower(tostring(eventData.spellName)) 
                                end)
                                if okLower and resLower then
                                    matched = true
                                    break
                                end
                            end
                        end
                    end
                    if extraID and C_UnitAuras and not (eventData and eventData.isLost) then
                        if C_UnitAuras.GetAuraDataBySpellID then
                            local okEx, auraEx = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", extraID)
                            if okEx and auraEx then matched = true; break end
                        end
                        if C_UnitAuras.GetPlayerAuraBySpellID then
                            local okEx, auraEx = pcall(C_UnitAuras.GetPlayerAuraBySpellID, extraID)
                            if okEx and auraEx then matched = true; break end
                        end
                    end
                end
            end
            
            if not matched then
                return false
            end
        end
        
        -- Aura name condition. eventData.spellName may be a "secret" string that
        -- throws on :lower()/:find(); pcall-guard and treat any failure as no-match.
        if conditions.auraName and conditions.auraName ~= "" then
            local needle = conditions.auraName:lower()
            local ok, found = pcall(function()
                return eventData.spellName and eventData.spellName:lower():find(needle, 1, true) ~= nil
            end)
            if not ok or not found then
                return false
            end
        end
        
        -- Aura type condition
        if conditions.auraType and eventData.auraType ~= conditions.auraType then
            return false
        end
    end
    
    local handler = self:GetEventTypeHandler(eventType)
    if handler and handler.CheckCondition then
        if not handler.CheckCondition(trigger, eventData) then
            return false
        end
    end
    -- Critical condition
    if conditions.critical ~= nil then
        if conditions.critical ~= (eventData.critical == true) then
            return false
        end
    end
    
    -- Custom Lua condition
    if conditions.customLua and conditions.customLua ~= "" then
        local func, err = loadstring("return " .. conditions.customLua)
        if func then
            local success, result = pcall(func)
            if not success or not result then
                return false
            end
        else
            -- Invalid Lua, skip this condition
            return false
        end
    end
    
    return true
end

-- Check zone restrictions
function Triggers:CheckZoneRestrictions(zones)
    if not zones or next(zones) == nil then return true end
    
    local inInstance, instanceType = IsInInstance()
    
    -- Check each zone type - only allow if explicitly checked (true)
    if zones.OPEN_WORLD and not inInstance then
        return true
    end
    if zones.PARTY and instanceType == "party" then
        return true
    end
    if zones.DELVE then
        -- Primary: use C_Delves API if available (Midnight+)
        if C_Delves and C_Delves.IsInDelve and C_Delves.IsInDelve() then
            return true
        end
        -- Fallback: check instanceType == "scenario"
        if instanceType == "scenario" then
            return true
        end
    end
    if zones.RAID and instanceType == "raid" then
        return true
    end
    if zones.PVP and (instanceType == "pvp" or C_PvP.IsActiveBattlefield()) then
        return true
    end
    if zones.BATTLEGROUND and (instanceType == "arena" or (instanceType == "pvp" and C_PvP.IsBattleground())) then
        return true
    end
    
    -- If any zones were set but current one didn't match, block it
    return false
end

-- Execute trigger actions

-- Refresh dashboard list

-- Create dashboard row (WoW-style using PetList atlases)

-- Get actions summary string

-- Get zone summary string

-- Refresh triggers list

-- Create trigger card

-- Single-spell search UI — used by all event types EXCEPT Aura Gained/Lost.
function Triggers:CreateSpellSearchUI(frame, trigger, yOffset, isAura)
    local conditions = trigger.conditions or {}

    local spellLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
    spellLabel:SetText("Spell:")

    local searchInput = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    searchInput:SetSize(220, 20)
    searchInput:SetPoint("LEFT", spellLabel, "RIGHT", 5, 0)
    searchInput:SetAutoFocus(false)
    searchInput:SetText("")

    -- The large spell display frame
    local spellDisplay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    spellDisplay:SetSize(220, 42)
    spellDisplay:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", -5, -4)
    spellDisplay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    spellDisplay:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
    spellDisplay:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

    spellDisplay.icon = spellDisplay:CreateTexture(nil, "ARTWORK")
    spellDisplay.icon:SetSize(28, 28)
    spellDisplay.icon:SetPoint("TOPLEFT", spellDisplay, "TOPLEFT", 7, -7)

    local iconBorder = spellDisplay:CreateTexture(nil, "OVERLAY")
    iconBorder:SetSize(50, 50)
    iconBorder:SetPoint("CENTER", spellDisplay.icon, "CENTER", 0, 0)
    iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")

    spellDisplay.nameText = spellDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellDisplay.nameText:SetPoint("TOPLEFT", spellDisplay.icon, "TOPRIGHT", 8, 0)
    spellDisplay.nameText:SetText("-")

    spellDisplay.idText = spellDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellDisplay.idText:SetPoint("TOPLEFT", spellDisplay.nameText, "BOTTOMLEFT", 0, -2)
    spellDisplay.idText:SetTextColor(0.6, 0.6, 0.6, 1)
    spellDisplay.idText:SetText("ID: -")

    -- Populate initial spell data
    if conditions.spellID and conditions.spellID ~= "" then
        local spellInfo = C_Spell.GetSpellInfo(tonumber(conditions.spellID) or conditions.spellID)
        if spellInfo then
            spellDisplay.icon:SetTexture(spellInfo.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
            spellDisplay.nameText:SetText(spellInfo.name or "-")
            spellDisplay.idText:SetText("ID: " .. conditions.spellID)
        else
            spellDisplay.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            spellDisplay.idText:SetText("ID: " .. conditions.spellID)
        end
    else
        spellDisplay.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- All Classes checkbox underneath the spell display (on by default)
    local allClassesCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allClassesCheck:SetPoint("TOPLEFT", spellDisplay, "BOTTOMLEFT", -2, -2)
    allClassesCheck:SetSize(20, 20)
    allClassesCheck:SetChecked(conditions.allClasses ~= false)
    allClassesCheck.text:SetText("All Classes")
    allClassesCheck.text:SetFontObject("GameFontNormalSmall")
    allClassesCheck:SetScript("OnClick", function(self)
        conditions.allClasses = self:GetChecked()
        if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
    end)
    allClassesCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search All Classes")
        GameTooltip:AddLine("Include common spells from other classes (e.g. Bloodlust, Power Infusion) in the search results.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    allClassesCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local helpIcon = CreateFrame("Button", nil, frame)
    helpIcon:SetSize(16, 16)
    helpIcon:SetPoint("LEFT", allClassesCheck.text, "RIGHT", 4, 0)
    helpIcon:SetNormalTexture("Interface\\Common\\help-i")
    helpIcon:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    helpIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("All Classes")
        GameTooltip:AddLine("On by default. The search includes common cross-class spells (Bloodlust, Heroism, Time Warp, Primal Rage, Power Infusion, etc.) so you can react to spells that aren't from your class.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Uncheck to limit the search to only your own class's spells.", 0.9, 0.82, 0.4, true)
        GameTooltip:Show()
    end)
    helpIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local resultsFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    resultsFrame:SetSize(220, 120)
    resultsFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", -5, -2)
    resultsFrame:SetFrameStrata("TOOLTIP")
    resultsFrame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10})
    resultsFrame:SetBackdropColor(0, 0, 0, 0.95)
    resultsFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    resultsFrame:Hide()

    local resultButtons = {}
    local function UpdateResults(searchText)
        for _, btn in ipairs(resultButtons) do btn:Hide() end
        if searchText == "" then resultsFrame:Hide(); return end
        local results = OxedHub.Triggers:SearchPlayerSpells(searchText, 5, conditions.allClasses)
        if #results == 0 then resultsFrame:Hide(); return end
        for i, spell in ipairs(results) do
            local btn = resultButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, resultsFrame)
                btn:SetSize(210, 22)
                btn:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 5, -5 - (i-1)*23)
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(16, 16)
                btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                resultButtons[i] = btn
            end
            btn.icon:SetTexture(spell.icon)
            btn.text:SetText(spell.name)
            btn.spellID = spell.id
            btn.spellName = spell.name
            btn.iconPath = spell.icon
            btn:SetScript("OnClick", function(self)
                conditions.spellID = tostring(self.spellID)
                spellDisplay.nameText:SetText(self.spellName)
                spellDisplay.nameText:SetTextColor(0, 1, 0, 1)
                spellDisplay.idText:SetText("ID: " .. self.spellID)
                if self.iconPath then spellDisplay.icon:SetTexture(self.iconPath) end
                C_Timer.After(0.5, function() spellDisplay.nameText:SetTextColor(1, 1, 1, 1) end)
                searchInput:SetText(self.spellName)
                searchInput:ClearFocus()
                resultsFrame:Hide()
                if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
                -- Keep any already-created action-bar macro in sync with the new spell.
                OxedHub.Triggers:RefreshExistingTriggerMacro(trigger)
                -- `frame` is the conditions inner frame; the card (which owns
                -- actionsFrame) is a couple levels up, so walk up to find it.
                local card = frame:GetParent()
                while card and not card.actionsFrame and card:GetParent() do
                    card = card:GetParent()
                end
                if card and card.actionsFrame then
                    if card.actionsFrame.RefreshActionVisibility then card.actionsFrame.RefreshActionVisibility() end
                    if card.actionsFrame.UpdateMacroIconInternal then card.actionsFrame.UpdateMacroIconInternal() end
                end
            end)
            btn:Show()
        end
        for i = #results + 1, #resultButtons do resultButtons[i]:Hide() end
        resultsFrame:SetHeight(math.min(#results * 23 + 10, 120))
        resultsFrame:Show()
    end

    local searchTimer
    local hideTimer
    searchInput:SetScript("OnTextChanged", function(self, isUserInput)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        if not isUserInput then return end
        if searchTimer then searchTimer:Cancel() end
        local text = self:GetText()
        if text and text ~= "" then
            searchTimer = C_Timer.NewTimer(0.1, function() if self:GetText() == text then UpdateResults(text) end end)
        else
            resultsFrame:Hide()
        end
    end)
    searchInput:SetScript("OnEscapePressed", function(self) resultsFrame:Hide(); self:ClearFocus() end)
    searchInput:SetScript("OnEditFocusLost", function() if searchTimer then searchTimer:Cancel() end; hideTimer = C_Timer.NewTimer(0.2, function() resultsFrame:Hide() end) end)
    searchInput:SetScript("OnEditFocusGained", function(this) if hideTimer then hideTimer:Cancel() end; if searchTimer then searchTimer:Cancel() end; if this:GetText() ~= "" then UpdateResults(this:GetText()) end end)
    searchInput:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Type spell name to search your spellbook"); GameTooltip:Show() end)
    searchInput:SetScript("OnLeave", function() GameTooltip:Hide() end)

    yOffset = yOffset - 90
    return yOffset
end

-- Multi-spell (OR) chip search UI — used ONLY by the Aura Gained/Lost event.
function Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
    local conditions = trigger.conditions or {}
    local isAura = true

    local spellLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
    spellLabel:SetText("Spell:")

    local searchInput = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
    searchInput:SetSize(220, 20)
    searchInput:SetPoint("LEFT", spellLabel, "RIGHT", 5, 0)
    searchInput:SetAutoFocus(false)
    searchInput:SetText("")

    -- Multi-spell hint (to the right of the search box)
    local multiHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    multiHint:SetPoint("LEFT", searchInput, "RIGHT", 14, 0)
    multiHint:SetWidth(300)
    multiHint:SetJustifyH("LEFT")
    multiHint:SetText("|cffffd100Tip:|r |cffb0b0b0you can add more than one spell — search and pick each. The trigger fires if ANY of them is gained/lost.|r")

    -- Compact icon chip for the primary spell (sits left of the extra chips / +)
    local spellDisplay = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    spellDisplay:SetSize(36, 36)
    spellDisplay:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", -5, -6)
    spellDisplay:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    spellDisplay:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
    spellDisplay:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    
    spellDisplay.icon = spellDisplay:CreateTexture(nil, "ARTWORK")
    spellDisplay.icon:SetPoint("TOPLEFT", 4, -4)
    spellDisplay.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    spellDisplay.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Kept for refreshSpellDisplay but hidden; the chip shows only the icon,
    -- with the spell name shown on hover.
    local iconBorder = spellDisplay:CreateTexture(nil, "OVERLAY")
    iconBorder:Hide()
    spellDisplay.nameText = spellDisplay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellDisplay.nameText:Hide()
    spellDisplay.idText = spellDisplay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellDisplay.idText:Hide()

    spellDisplay:EnableMouse(true)
    spellDisplay:SetScript("OnEnter", function(self)
        if not (conditions.spellID and conditions.spellID ~= "") then return end
        local info = C_Spell.GetSpellInfo(tonumber(conditions.spellID) or conditions.spellID)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((info and info.name) or ("ID " .. tostring(conditions.spellID)))
        GameTooltip:AddLine("ID: " .. tostring(conditions.spellID), 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    spellDisplay:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Additional OR-spells (the trigger matches if ANY listed spell is seen)
    conditions.extraSpellIDs = conditions.extraSpellIDs or {}

    -- Forward declarations (closures below reference these)
    local refreshSpellDisplay, renderExtras, restoreSearch

    -- Populate the main spell display from conditions.spellID
    refreshSpellDisplay = function()
        if conditions.spellID and conditions.spellID ~= "" then
            local spellInfo = C_Spell.GetSpellInfo(tonumber(conditions.spellID) or conditions.spellID)
            spellDisplay.icon:SetTexture((spellInfo and spellInfo.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark")
            spellDisplay.nameText:SetText((spellInfo and spellInfo.name) or "-")
            spellDisplay.idText:SetText("ID: " .. conditions.spellID)
        else
            spellDisplay.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            spellDisplay.nameText:SetText("-")
            spellDisplay.idText:SetText("ID: -")
        end
    end
    refreshSpellDisplay()

    -- Keep the search box as a plain search box (always empty when not typing).
    -- The selected spell lives in the icon display, so clearing the search never
    -- looks like you lost the spell.
    restoreSearch = function()
        searchInput:SetText("")
    end
    restoreSearch()
    
    -- All Classes checkbox underneath the spell display
    local allClassesCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allClassesCheck:SetPoint("TOPLEFT", spellDisplay, "BOTTOMLEFT", -2, -2)
    allClassesCheck:SetSize(20, 20)
    allClassesCheck:SetChecked(conditions.allClasses ~= false)
    allClassesCheck.text:SetText("All Classes")
    allClassesCheck.text:SetFontObject("GameFontNormalSmall")
    allClassesCheck:SetScript("OnClick", function(self)
        conditions.allClasses = self:GetChecked()
        if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
    end)
    allClassesCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search All Classes")
        GameTooltip:AddLine("Include common spells from other classes (e.g. Bloodlust, Power Infusion) in the search results.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    allClassesCheck:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Visible (?) help icon next to the "All Classes" label
    local helpIcon = CreateFrame("Button", nil, frame)
    helpIcon:SetSize(16, 16)
    helpIcon:SetPoint("LEFT", allClassesCheck.text, "RIGHT", 4, 0)
    helpIcon:SetNormalTexture("Interface\\Common\\help-i")
    helpIcon:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    helpIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("All Classes")
        GameTooltip:AddLine("On by default. The search includes common cross-class buffs (Bloodlust, Heroism, Time Warp, Primal Rage, Power Infusion, etc.) so you can react to spells that aren't from your class.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Uncheck to limit the search to only your own class's spells.", 0.9, 0.82, 0.4, true)
        GameTooltip:Show()
    end)
    helpIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- ── Additional OR-spells (chips + "+" button to the right of the display) ──
    local extraContainer = CreateFrame("Frame", nil, frame)
    extraContainer:SetPoint("TOPLEFT", spellDisplay, "TOPRIGHT", 4, 0)
    extraContainer:SetSize(360, 36)

    local addSpellBtn  -- forward decl (renderExtras repositions it)
    local extraChips = {}

    renderExtras = function()
        for _, chip in ipairs(extraChips) do chip:Hide() end
        local x = 0
        for idx, sid in ipairs(conditions.extraSpellIDs or {}) do
            local chip = extraChips[idx]
            if not chip then
                chip = CreateFrame("Button", nil, extraContainer, "BackdropTemplate")
                chip:SetSize(36, 36)
                chip:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
                chip:SetBackdropColor(0.08, 0.08, 0.12, 0.9)
                chip:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                chip.icon = chip:CreateTexture(nil, "ARTWORK")
                chip.icon:SetPoint("TOPLEFT", 3, -3)
                chip.icon:SetPoint("BOTTOMRIGHT", -3, 3)
                chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                chip.xmark = chip:CreateTexture(nil, "OVERLAY")
                chip.xmark:SetSize(14, 14)
                chip.xmark:SetPoint("TOPRIGHT", chip, "TOPRIGHT", 5, 5)
                chip.xmark:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                extraChips[idx] = chip
            end
            local info = C_Spell.GetSpellInfo(tonumber(sid) or sid)
            chip.icon:SetTexture((info and info.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark")
            chip.sid = sid
            chip.spellName = (info and info.name) or ("ID " .. tostring(sid))
            chip:ClearAllPoints()
            chip:SetPoint("LEFT", extraContainer, "LEFT", x, 0)
            chip:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.spellName)
                GameTooltip:AddLine("ID: " .. tostring(self.sid), 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Click to remove", 1, 0.3, 0.3)
                GameTooltip:Show()
            end)
            chip:SetScript("OnLeave", function() GameTooltip:Hide() end)
            chip:SetScript("OnClick", function(self)
                for i, v in ipairs(conditions.extraSpellIDs) do
                    if v == self.sid then table.remove(conditions.extraSpellIDs, i) break end
                end
                renderExtras()
                if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
            end)
            chip:Show()
            x = x + 40
        end
        if addSpellBtn then
            addSpellBtn:ClearAllPoints()
            addSpellBtn:SetPoint("LEFT", extraContainer, "LEFT", x + 2, 0)
        end
    end

    -- (No "+" button: just type in the Spell search to add another OR-spell.)

    -- Remove-X on the main spell display (promotes the next OR-spell to primary)
    local clearPrimary = CreateFrame("Button", nil, spellDisplay)
    clearPrimary:SetSize(14, 14)
    clearPrimary:SetPoint("TOPRIGHT", spellDisplay, "TOPRIGHT", 5, 5)
    clearPrimary:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clearPrimary:SetFrameLevel(spellDisplay:GetFrameLevel() + 5)
    clearPrimary:SetScript("OnClick", function()
        conditions.spellID = table.remove(conditions.extraSpellIDs, 1) or ""
        refreshSpellDisplay()
        renderExtras()
        if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
    end)

    renderExtras()

    local resultsFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    resultsFrame:SetSize(220, 120)
    resultsFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", -5, -2)
    resultsFrame:SetFrameStrata("TOOLTIP")
    resultsFrame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10})
    resultsFrame:SetBackdropColor(0, 0, 0, 0.95)
    resultsFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    resultsFrame:Hide()
    
    local resultButtons = {}
    local function UpdateResults(searchText)
        for _, btn in ipairs(resultButtons) do btn:Hide() end
        if searchText == "" then resultsFrame:Hide(); return end
        local results = OxedHub.Triggers:SearchPlayerSpells(searchText, 5, conditions.allClasses)
        if #results == 0 then resultsFrame:Hide(); return end
        for i, spell in ipairs(results) do
            local btn = resultButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, resultsFrame)
                btn:SetSize(210, 22)
                btn:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 5, -5 - (i-1)*23)
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(16, 16)
                btn.icon:SetPoint("LEFT", btn, "LEFT", 0, 0)
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 5, 0)
                btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                resultButtons[i] = btn
            end
            btn.icon:SetTexture(spell.icon)
            btn.text:SetText(spell.name)
            btn.spellID = spell.id
            btn.spellName = spell.name
            btn.iconPath = spell.icon
            btn:SetScript("OnClick", function(self)
                local idStr = tostring(self.spellID)
                if conditions.spellID == nil or conditions.spellID == "" then
                    -- First pick → main display
                    conditions.spellID = idStr
                    refreshSpellDisplay()
                    spellDisplay.nameText:SetTextColor(0, 1, 0, 1)
                    C_Timer.After(0.5, function() spellDisplay.nameText:SetTextColor(1, 1, 1, 1) end)
                else
                    -- Subsequent picks → add as an OR-spell (dedupe vs primary + extras)
                    local dup = (tostring(conditions.spellID) == idStr)
                    for _, v in ipairs(conditions.extraSpellIDs) do
                        if v == idStr then dup = true break end
                    end
                    if not dup then table.insert(conditions.extraSpellIDs, idStr) end
                    renderExtras()
                end
                -- Blur restores the search box to the current primary spell name
                searchInput:ClearFocus()
                resultsFrame:Hide()
                restoreSearch()
                if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
                -- Keep any already-created action-bar macro in sync with the new spell.
                OxedHub.Triggers:RefreshExistingTriggerMacro(trigger)
                -- `frame` is the conditions inner frame; the card (which owns
                -- actionsFrame) is a couple levels up, so walk up to find it.
                local card = frame:GetParent()
                while card and not card.actionsFrame and card:GetParent() do
                    card = card:GetParent()
                end
                if card and card.actionsFrame then
                    if card.actionsFrame.RefreshActionVisibility then card.actionsFrame.RefreshActionVisibility() end
                    if card.actionsFrame.UpdateMacroIconInternal then card.actionsFrame.UpdateMacroIconInternal() end
                end
            end)
            btn:Show()
        end
        for i = #results + 1, #resultButtons do resultButtons[i]:Hide() end
        resultsFrame:SetHeight(math.min(#results * 23 + 10, 120))
        resultsFrame:Show()
    end
    
    local searchTimer
    local hideTimer
    searchInput:SetScript("OnTextChanged", function(self, isUserInput)
        -- Hide the "Search" placeholder / toggle the clear button as you type.
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        if not isUserInput then return end
        if searchTimer then searchTimer:Cancel() end
        local text = self:GetText()
        if text and text ~= "" then
            searchTimer = C_Timer.NewTimer(0.1, function() if self:GetText() == text then UpdateResults(text) end end)
        else
            resultsFrame:Hide()
        end
    end)
    searchInput:SetScript("OnEscapePressed", function(self) resultsFrame:Hide(); self:ClearFocus() end)
    searchInput:SetScript("OnEditFocusLost", function()
        if searchTimer then searchTimer:Cancel() end
        hideTimer = C_Timer.NewTimer(0.2, function()
            resultsFrame:Hide()
            -- Clicked away without picking → show the current spell again (cancel add)
            restoreSearch()
        end)
    end)
    searchInput:SetScript("OnEditFocusGained", function(this)
        if hideTimer then hideTimer:Cancel() end
        if searchTimer then searchTimer:Cancel() end
        -- Clear so the user can type a fresh spell (the display still shows current)
        this:SetText("")
        resultsFrame:Hide()
    end)
    searchInput:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Type spell name to search your spellbook"); GameTooltip:Show() end)
    searchInput:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    yOffset = yOffset - 90
    return yOffset
end

function Triggers:RefreshTriggerCardConditions(card, trigger)
    local frame = card.conditionsFrame
    
    -- Clear existing children and regions (font strings, textures)
    for _, child in ipairs({frame:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({frame:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    local conditions = trigger.conditions or {}
    local yOffset = 0
    
    local handler = self:GetEventTypeHandler(trigger.event)
    if handler and handler.CreateConditionUI then
        yOffset = handler.CreateConditionUI(frame, trigger, yOffset)
    end
    -- In combat checkbox (Hidden globally for now as requested)
    if false then
        local combatCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        combatCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        combatCheck:SetSize(20, 20)
        combatCheck:SetChecked(conditions.inCombat or false)
        combatCheck.text:SetText("In Combat Only")
        combatCheck:SetScript("OnClick", function(self)
            conditions.inCombat = self:GetChecked()
            ShowAutoSaved(frame:GetParent())
        end)
        yOffset = yOffset - 25
    end

    frame.naturalHeight = math.abs(yOffset) + 5
    frame:SetHeight(frame.naturalHeight)
    
    -- Refresh actions and macro visibility
    self:RefreshTriggerCard(card.triggerId)
    
    self:LayoutTriggerCard(card)
end








-- Create zone restrictions UI

-- Scroll to trigger

-- Get trigger by ID

-- Sound Picker (adapted from EmotionRing)
local function normalizeSearchText(text)
    if not text then return "" end
    return text:lower():gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
end













-- Get the macro name for a trigger (clean prefix, no spaces)





-- Build macro body from trigger data (internal -> WoW macro text)




-- Function called by macros to execute trigger actions


