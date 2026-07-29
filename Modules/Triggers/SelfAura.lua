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

-- initial=true seeds state on login without firing (so a buff already up when you
-- log in doesn't spam), matching the DiGua BloodlustDetector pattern.
local function EvaluateSelfAuraTriggers(initial)
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end

    for id, trigger in pairs(profile.triggers) do
        if trigger.event == "SELF_AURA" and trigger.enabled then
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

-- ── Native aura sound (works IN COMBAT) ──────────────────────────────────────
-- In combat WoW makes aura data "secret", so GetPlayerAuraBySpellID can't detect
-- the buff and the monitor above won't fire. C_UnitAuras.AddAuraAppliedSound lets
-- us pre-register spellID -> sound file so WoW ITSELF plays the sound when the aura
-- is applied, even in combat. Sound-only (no animation/loop), but reliable.
local nativeSoundHandles = {}

local function UnregisterNativeSounds()
    for i = #nativeSoundHandles, 1, -1 do
        local entry = nativeSoundHandles[i]
        if type(entry) == "table" then
            if entry.type == "private" and C_UnitAuras and C_UnitAuras.RemovePrivateAuraAppliedSound then
                pcall(C_UnitAuras.RemovePrivateAuraAppliedSound, entry.handle)
            elseif entry.type == "normal" and C_UnitAuras and C_UnitAuras.RemoveAuraAppliedSound then
                pcall(C_UnitAuras.RemoveAuraAppliedSound, entry.handle)
            end
        else
            if C_UnitAuras and C_UnitAuras.RemoveAuraAppliedSound then
                pcall(C_UnitAuras.RemoveAuraAppliedSound, entry)
            end
        end
        nativeSoundHandles[i] = nil
    end
    wipe(nativeSoundHandles)
end

function Triggers:RefreshSelfAuraNativeSounds()
    -- Registration APIs are protected during combat; defer if locked down.
    if InCombatLockdown() then
        Triggers._selfAuraNativePendingAfterCombat = true
        if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SELF_AURA native: deferred (in combat)") end
        return
    end
    local hasNormal = C_UnitAuras and C_UnitAuras.AddAuraAppliedSound and true or false
    local hasPrivate = C_UnitAuras and C_UnitAuras.AddPrivateAuraAppliedSound and true or false
    if OxedHub.debug then
        print(("|cff00ffff[OxedHub-Debug]|r SELF_AURA native: AddAuraAppliedSound=%s AddPrivateAuraAppliedSound=%s"):format(
            tostring(hasNormal), tostring(hasPrivate)))
    end
    if not hasNormal and not hasPrivate then
        return -- client too old or missing native aura APIs; monitor-only (works out of combat)
    end

    UnregisterNativeSounds()

    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end
    local channel = (profile.settings and profile.settings.soundChannel) or "Master"

    for id, trigger in pairs(profile.triggers) do
        if (trigger.event == "SELF_AURA" or trigger.event == "UNIT_AURA") and trigger.enabled then
            local soundVal = trigger.actions and trigger.actions.sound
            local filePath = OxedHub.Sounds and OxedHub.Sounds.GetFilePath
                and OxedHub.Sounds:GetFilePath(soundVal)
            if filePath then
                for _, sid in ipairs(GetConfiguredSpellIDs(trigger)) do
                    local soundInfo = {
                        unitToken = "player",
                        spellID = sid,
                        soundFileName = filePath,
                        outputChannel = channel,
                    }
                    if hasPrivate then
                        local ok, handle = pcall(C_UnitAuras.AddPrivateAuraAppliedSound, soundInfo)
                        if ok then
                            table.insert(nativeSoundHandles, { type = "private", handle = handle })
                            if OxedHub.debug then
                                print(("|cff00ff00[OxedHub]|r Registered native aura sound for spell %s"):format(tostring(sid)))
                            end
                        end
                        if OxedHub.debug then
                            print(("|cff00ffff[OxedHub-Debug]|r SELF_AURA private native register spell=%s ok=%s file=%s"):format(
                                tostring(sid), tostring(ok), tostring(filePath)))
                        end
                    end
                    if hasNormal then
                        local ok, handle = pcall(C_UnitAuras.AddAuraAppliedSound, soundInfo)
                        if ok then
                            table.insert(nativeSoundHandles, { type = "normal", handle = handle })
                        end
                        if OxedHub.debug then
                            print(("|cff00ffff[OxedHub-Debug]|r SELF_AURA normal native register spell=%s ok=%s file=%s"):format(
                                tostring(sid), tostring(ok), tostring(filePath)))
                        end
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
        Triggers:RefreshSelfAuraNativeSounds()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- entering combat: reseed state so procs during combat trigger gained transition
        EvaluateSelfAuraTriggers(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- left combat: apply any registration that was deferred, and re-sync edits
        if Triggers._selfAuraNativePendingAfterCombat then
            Triggers._selfAuraNativePendingAfterCombat = nil
        end
        Triggers:RefreshSelfAuraNativeSounds()
    else
        EvaluateSelfAuraTriggers(false)
    end
end)

Triggers._selfAuraMonitor = monitor
