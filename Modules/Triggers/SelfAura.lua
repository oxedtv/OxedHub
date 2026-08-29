local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────────
-- SELF_AURA event type
--
-- Reliable detection of ONE of the player's OWN buffs/procs by spell ID, using
-- C_UnitAuras.GetPlayerAuraBySpellID (an EXISTENCE check — it never reads the
-- aura's "secret" numeric fields, so it is immune to the WoW aura-privacy taint
-- that breaks the general "Aura Gained/Lost" scanner). Supports gained, lost,
-- "both", and "loop sound until lost", exactly like the scanning aura event.
-- ─────────────────────────────────────────────────────────────────────────────

-- Specific mapping from each haste burst spell to its corresponding debuff ID
-- so a trigger for Heroism ONLY triggers on Heroism, Bloodlust ONLY on Bloodlust, etc.
local LUST_TO_DEBUFF_MAP = {
    [2825]   = 57724,  -- Bloodlust -> Sated
    [32182]  = 57723,  -- Heroism -> Exhaustion
    [80353]  = 80354,  -- Time Warp -> Temporal Displacement
    [390386] = 390435, -- Fury of the Aspects -> Exhaustion
    [264667] = 264689, -- Primal Rage -> Fatigued
    [90355]  = 264689, -- Ancient Hysteria -> Fatigued
    [160452] = 264689, -- Netherwinds -> Fatigued
    [381301] = 57724,  -- Feral Hide Drums -> Sated
    [230935] = 57724,  -- Drums of the Mountain -> Sated
    [256740] = 57724,  -- Drums of the Maelstrom -> Sated
    [309658] = 57724,  -- Drums of Deathly Ferocity -> Sated
    [466904] = 57724,  -- Drums of War -> Sated
}

-- Collect the configured spell IDs (primary + extras) as plain numbers.
local function GetConfiguredSpellIDs(trigger)
    local ids = {}
    local seen = {}
    local c = trigger.conditions or {}

    local function addID(val)
        if not val then return end
        local n = tonumber(val)
        if not n and type(val) == "string" and val ~= "" and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(val)
            if info and info.spellID then
                n = info.spellID
            end
        end
        if n and not seen[n] then
            seen[n] = true
            table.insert(ids, n)
            
            -- If this specific spell has a matching debuff (e.g. Heroism -> Exhaustion),
            -- include its debuff ID for 12.1 combat existence tracking
            local debuffID = LUST_TO_DEBUFF_MAP[n]
            if debuffID and not seen[debuffID] then
                seen[debuffID] = true
                table.insert(ids, debuffID)
            end
        end
    end

    addID(c.spellID)
    addID(c.spellName)
    addID(c.auraName)

    if c.extraSpellIDs then
        for _, s in ipairs(c.extraSpellIDs) do
            addID(s)
        end
    end

    return ids
end

-- Returns (present, matchedSpellID). Existence-only, so no secret-value reads.
local function HasConfiguredAura(trigger)
    if not C_UnitAuras then
        return false, nil
    end
    for _, sid in ipairs(GetConfiguredSpellIDs(trigger)) do
        if C_UnitAuras.GetAuraDataBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", sid)
            if ok and aura then
                return true, sid
            end
        end
        if C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
            if ok and aura then
                return true, sid
            end
        end

        -- Fallback: use the taint-free spell ID presence set built by Core's
        -- aura scanner.  This works even in combat where all aura data is
        -- secret and the native WoW APIs above return nil.
        local Core = OxedHub.Core
        if Core and Core.activeSpellIDs and Core.activeSpellIDs[sid] then
            return true, sid
        end
    end
    return false, nil
end

Triggers:RegisterEventType("SELF_AURA", {
    name = "My Buff/Proc (by Spell ID)",
    -- The monitor below drives these triggers directly via ExecuteTrigger, so this
    -- is only a defensive pass-through if something ever routes through ProcessEvent.
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}

        if Triggers.CreateAuraSpellSearchUI then
            yOffset = Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end

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
-- Per-trigger present/absent memory; a transition drives the effects.
local selfAuraPresent = {}

local function CancelLoop(triggerId, trigger)
    if not Triggers.activeAuraLoops then return end
    for _, sid in ipairs(GetConfiguredSpellIDs(trigger)) do
        local key = Triggers:BuildAuraLoopKey(triggerId, sid)
        local ticker = Triggers.activeAuraLoops[key]
        if ticker then
            ticker:Cancel()
            Triggers.activeAuraLoops[key] = nil
        end
    end
end

local function IsLustTrigger(trigger)
    if not trigger then return false end
    local ids = GetConfiguredSpellIDs(trigger)
    for _, sid in ipairs(ids) do
        if LUST_TO_DEBUFF_MAP[sid] then
            return true
        end
    end
    local c = trigger.conditions or {}
    local namesToCheck = { c.spellName, c.auraName, c.spellID }
    for _, nameVal in ipairs(namesToCheck) do
        if type(nameVal) == "string" and nameVal ~= "" then
            local lowerName = nameVal:lower()
            if lowerName:find("bloodlust") or lowerName:find("heroism") or lowerName:find("time warp")
               or lowerName:find("fury of the aspects") or lowerName:find("primal rage")
               or lowerName:find("sated") or lowerName:find("exhaustion") or lowerName:find("temporal displacement") then
                return true
            end
        end
    end
    return false
end

-- initial=true seeds state on login without firing (so a buff already up when you
-- log in doesn't spam), matching the DiGua BloodlustDetector pattern.
local function EvaluateSelfAuraTriggers(initial)
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end

    for id, trigger in pairs(profile.triggers) do
        local isSelfAura = (trigger.event == "SELF_AURA")
        local isUnitAuraLust = (trigger.event == "UNIT_AURA" and IsLustTrigger(trigger))
        if (isSelfAura or isUnitAuraLust) and trigger.enabled then
            local present, matchedSid = HasConfiguredAura(trigger)
            local was = selfAuraPresent[id]

            local c = trigger.conditions or {}
            if initial then
                selfAuraPresent[id] = present or nil
            elseif present and not was then
                -- gained. Fire unless the trigger is in "lost only" mode.
                selfAuraPresent[id] = true
                local fireOnGained = c.onBoth or not c.onLost
                if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SELF_AURA GAINED:", trigger.name or id, "spell", tostring(matchedSid), "fire:", tostring(fireOnGained)) end
                if fireOnGained and Triggers:CheckZoneRestrictions(trigger.zones) then
                    Triggers:ExecuteTrigger(trigger, { spellID = matchedSid, isLost = false })
                end
            elseif not present and was then
                -- lost
                selfAuraPresent[id] = nil
                CancelLoop(id, trigger)
                if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SELF_AURA LOST:", trigger.name or id) end
                if (c.onLost or c.onBoth) and Triggers:CheckZoneRestrictions(trigger.zones) then
                    local sid = GetConfiguredSpellIDs(trigger)[1]
                    Triggers:ExecuteTrigger(trigger, { spellID = sid, isLost = true })
                end
            end
        end
    end
end

local selfAuraTicker = nil
local function StartSelfAuraPolling()
    if selfAuraTicker then return end
    selfAuraTicker = C_Timer.NewTicker(0.25, function()
        EvaluateSelfAuraTriggers(false)
    end)
end

local function StopSelfAuraPolling()
    if selfAuraTicker then
        selfAuraTicker:Cancel()
        selfAuraTicker = nil
    end
end

-- ── Native aura sound (works IN COMBAT) ──────────────────────────────────────
-- In combat WoW makes aura data "secret", so GetPlayerAuraBySpellID can't detect
-- the buff and the monitor above won't fire. C_UnitAuras.AddAuraAppliedSound lets
-- us pre-register spellID -> sound file so WoW ITSELF plays the sound when the aura
-- is applied, even in combat. Sound-only (no animation/loop), but reliable.
local nativeSoundHandles = {}

-- Set once the client refuses the registration call. C_UnitAuras.AddAuraSound
-- exists but stays protected for addons, so every call raises
-- ADDON_ACTION_BLOCKED and returns nothing. The old code only guarded against
-- combat, which is why it kept firing outside combat too: one blocked action per
-- configured spell ID, on every zone-in and every exit from combat.
--
-- Presence of the function therefore proves nothing; only trying it does. One
-- probe is enough to learn the answer, after which the aura monitor above
-- handles these triggers on its own -- it needs no protected call.
local nativeSoundUnavailable = false

-- Hard ceiling on registration attempts for the whole session, independent of
-- how the refusal is detected. The blocked-action count is the accurate signal,
-- but if it is ever unavailable this still bounds the damage: the previous
-- version had no ceiling at all and logged ten thousand blocked calls in an
-- hour and a half.
local MAX_NATIVE_ATTEMPTS = 40
local nativeAttempts = 0


local function UnregisterNativeEffects()
    for i = #nativeSoundHandles, 1, -1 do
        local entry = nativeSoundHandles[i]
        if type(entry) == "table" and entry.type == "normal" and C_UnitAuras then
            -- Direct calls for the same reason as the registration above.
            if C_UnitAuras.RemoveAuraSound then
                C_UnitAuras.RemoveAuraSound(entry.handle)
            elseif C_UnitAuras.RemoveAuraAppliedSound then
                C_UnitAuras.RemoveAuraAppliedSound(entry.handle)
            end
        end
    end
    wipe(nativeSoundHandles)
end

function Triggers:RefreshSelfAuraNativeEffects()
    -- Registration APIs are protected during combat; defer if locked down.
    if InCombatLockdown() then
        Triggers._selfAuraNativePendingAfterCombat = true
        if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SELF_AURA native: deferred (in combat)") end
        return
    end
    local hasNormal = C_UnitAuras and (C_UnitAuras.AddAuraSound or C_UnitAuras.AddAuraAppliedSound) and true or false
    if OxedHub.debug then
        print(("|cff00ffff[OxedHub-Debug]|r SELF_AURA native: native sound API=%s"):format(tostring(hasNormal)))
    end
    if not hasNormal then
        return -- client missing native aura sound API; fallback to runtime aura monitoring
    end
    if nativeSoundUnavailable then
        return -- the client refused it earlier this session; the monitor covers it
    end

    UnregisterNativeEffects()

    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end
    local channel = (profile.settings and profile.settings.soundChannel) or "Master"

    for id, trigger in pairs(profile.triggers) do
        local isSelfAura = (trigger.event == "SELF_AURA")
        local isUnitAuraLust = (trigger.event == "UNIT_AURA" and IsLustTrigger(trigger))
        if (isSelfAura or isUnitAuraLust) and trigger.enabled then
            local c = trigger.conditions or {}
            local configuredSpellIDs = GetConfiguredSpellIDs(trigger)
            local spellIDMap = {}
            
            for _, sid in ipairs(configuredSpellIDs) do
                spellIDMap[sid] = true
                
                -- Sound logic operates per spell ID natively
                local soundVal = trigger.actions and trigger.actions.sound
                local filePath = OxedHub.Sounds and OxedHub.Sounds.GetFilePath
                    and OxedHub.Sounds:GetFilePath(soundVal)
                    
                if filePath then
                    local soundInfo = {
                        unitToken = "player",
                        spellID = sid,
                        soundFileName = filePath,
                        outputChannel = channel,
                    }
                    
                    -- Name the culprit for the error journal: a blocked call
                    -- here reports only the file and line, which says nothing
                    -- about which of the user's triggers was being registered.
                    local journal = OxedHub.ErrorJournal
                    if journal then
                        journal:SetContext("Triggers",
                            trigger.name or trigger.id or "unnamed trigger",
                            ("%s, spell %s"):format(tostring(trigger.event), tostring(sid)))
                    end

                    -- Called directly, not through pcall. pcall puts a C
                    -- boundary between us and the protected function, and the
                    -- engine's caller check sees that boundary rather than our
                    -- own code -- which is what the blocked-action traceback
                    -- pointed at ("[C]: in function 'pcall'"). The availability
                    -- checks above are what keep this safe on older clients.
                    -- Blocked calls cannot be spotted from the return value --
                    -- the client refuses the action but the function still
                    -- returns a handle. Watching the addon's blocked-action
                    -- count across the call is the only reliable answer.
                    local blocksBefore = (journal and journal.blockedCount) or 0

                    nativeAttempts = nativeAttempts + 1
                    if nativeAttempts > MAX_NATIVE_ATTEMPTS then
                        nativeSoundUnavailable = true
                        if journal then journal:ClearContext() end
                        UnregisterNativeEffects()
                        return
                    end

                    local handle
                    if C_UnitAuras.AddAuraSound then
                        local triggerEnum = Enum.UnitAuraSoundTrigger.Added
                        if c.onLost and not c.onBoth then
                            triggerEnum = Enum.UnitAuraSoundTrigger.Removed
                        end
                        if c.onBoth then
                            handle = C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Added, soundInfo)
                            -- Only ask for the second registration once the
                            -- first has actually been granted.
                            local refused = journal
                                and (journal.blockedCount or 0) > blocksBefore
                            if handle and not refused then
                                C_UnitAuras.AddAuraSound(Enum.UnitAuraSoundTrigger.Removed, soundInfo)
                            end
                        else
                            handle = C_UnitAuras.AddAuraSound(triggerEnum, soundInfo)
                        end
                    else
                        soundInfo.playOnAdd = c.onBoth or not c.onLost
                        soundInfo.playOnGainApplication = c.onBoth or not c.onLost
                        soundInfo.playOnRemove = c.onLost or c.onBoth
                        handle = C_UnitAuras.AddAuraAppliedSound(soundInfo)
                    end
                    
                    if journal then journal:ClearContext() end

                    -- The client refusing the call is what counts, not what the
                    -- call returned.
                    local wasBlocked = journal and (journal.blockedCount or 0) > blocksBefore

                    if handle and not wasBlocked then
                        table.insert(nativeSoundHandles, { type = "normal", handle = handle })
                    else
                        -- The first refusal is decisive. Carrying on would just
                        -- repeat the same blocked call for every remaining spell
                        -- ID, which is exactly the error storm this replaces.
                        nativeSoundUnavailable = true
                        UnregisterNativeEffects()
                        if OxedHub.debug then
                            print("|cff00ffff[OxedHub-Debug]|r SELF_AURA native: registration refused by the client, using the aura monitor instead")
                        end
                        return
                    end
                end
            end
        end
    end
end

local monitor = CreateFrame("Frame")
monitor:RegisterUnitEvent("UNIT_AURA", "player")
monitor:RegisterEvent("PLAYER_ENTERING_WORLD")
monitor:RegisterEvent("PLAYER_REGEN_ENABLED")
monitor:RegisterEvent("PLAYER_REGEN_DISABLED")
monitor:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- reseed state; don't fire for auras already present at load
        wipe(selfAuraPresent)
        EvaluateSelfAuraTriggers(true)
        Triggers:RefreshSelfAuraNativeEffects()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- entering combat: start ticker & reseed state
        StartSelfAuraPolling()
        EvaluateSelfAuraTriggers(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- left combat: stop ticker, apply any registration that was deferred, and re-sync edits
        StopSelfAuraPolling()
        if Triggers._selfAuraNativePendingAfterCombat then
            Triggers._selfAuraNativePendingAfterCombat = nil
        end
        Triggers:RefreshSelfAuraNativeEffects()
        EvaluateSelfAuraTriggers(false)
    else
        -- Defer evaluation to the next frame tick to guarantee that Core.lua
        -- has finished its ScanUnitAuras and updated Core.activeSpellIDs.
        C_Timer.After(0, function()
            EvaluateSelfAuraTriggers(false)
        end)
    end
end)

Triggers._selfAuraMonitor = monitor
