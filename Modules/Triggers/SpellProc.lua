local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────────
-- SPELL_PROC event type
--
-- Fires from the game's proc/activation-glow system (SPELL_ACTIVATION_OVERLAY_SHOW
-- / _HIDE) — the same thing that makes an ability light up when a proc is ready
-- (e.g. Sudden Doom lighting up Death Coil). The event carries a PLAIN spell ID
-- (it's a UI event, not aura data), so it works IN COMBAT and is immune to the
-- aura "secret value" privacy that blocks aura scanning.
--
-- Only spells that HAVE an activation glow trigger this. For proc buffs that's
-- exactly what you want; for non-glow buffs use "My Buff/Proc (by Spell ID)".
-- ─────────────────────────────────────────────────────────────────────────────

local function GetConfiguredSpellIDs(trigger)
    local ids = {}
    local c = trigger.conditions or {}
    local primary = tonumber(c.spellID)
    if primary then table.insert(ids, primary) end
    if c.extraSpellIDs then
        for _, s in ipairs(c.extraSpellIDs) do
            local n = tonumber(s)
            if n then table.insert(ids, n) end
        end
    end
    return ids
end

Triggers:RegisterEventType("SPELL_PROC", {
    name = "Spell Proc Glow (by Spell ID)",
    CheckCondition = function(trigger, eventData) return true end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}

        if Triggers.CreateAuraSpellSearchUI then
            yOffset = Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end

        local loopCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        loopCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        loopCheck:SetSize(20, 20)
        loopCheck:SetChecked(conditions.loopSound or false)
        loopCheck.text:SetText("Loop sound while glowing")

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
        lostCheck.text:SetText("Trigger when glow ends")

        local bothCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        bothCheck:SetPoint("LEFT", lostCheck.text, "RIGHT", 10, 0)
        bothCheck:SetSize(20, 20)
        bothCheck:SetChecked(conditions.onBoth or false)
        bothCheck.text:SetText("Trigger on Both")

        lostCheck:SetScript("OnClick", function(self)
            conditions.onLost = self:GetChecked()
            if self:GetChecked() then bothCheck:SetChecked(false); conditions.onBoth = false end
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        bothCheck:SetScript("OnClick", function(self)
            conditions.onBoth = self:GetChecked()
            if self:GetChecked() then lostCheck:SetChecked(false); conditions.onLost = false end
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)

        yOffset = yOffset - 28

        -- Info note: this event only catches action-bar proc glows, not buffs.
        local infoIcon = CreateFrame("Button", nil, frame)
        infoIcon:SetSize(16, 16)
        infoIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        infoIcon:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
        local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        infoText:SetPoint("LEFT", infoIcon, "RIGHT", 5, 0)
        infoText:SetText("Proc / glow spells only (e.g. Sudden Doom) — not normal buffs.")
        infoText:SetTextColor(1, 0.82, 0)
        local function ShowProcInfo(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:SetText("Spell Proc Glow", 1, 0.82, 0)
            GameTooltip:AddLine("Fires when a spell lights up (procs) on your action bar — e.g. Sudden Doom, Hot Streak, Sudden Death.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("It does NOT detect normal buffs (like Power Infusion). Buffs need aura detection, which WoW blocks in combat — so there is no reliable in-combat trigger for them yet.", 0.9, 0.8, 0.4, true)
            GameTooltip:Show()
        end
        infoIcon:SetScript("OnEnter", function(self) ShowProcInfo(self) end)
        infoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

        yOffset = yOffset - 24
        return yOffset
    end
})

-- ── Monitor ──────────────────────────────────────────────────────────────────
local procActive = {} -- [triggerId] = true while the glow is showing

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

local function ForEachMatch(spellID, fn)
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end
    for id, trigger in pairs(profile.triggers) do
        if trigger.event == "SPELL_PROC" and trigger.enabled then
            for _, sid in ipairs(GetConfiguredSpellIDs(trigger)) do
                if sid == spellID then
                    fn(id, trigger, sid)
                    break
                end
            end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
f:SetScript("OnEvent", function(_, event, spellID)
    spellID = tonumber(spellID)
    if not spellID then return end

    -- Discovery aid: print every glow spell ID so you can find the exact one to
    -- configure (a proc's glow ID sometimes differs from the buff's spell ID).
    if OxedHub.debug then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        print(("|cffffcc00[OxedHub-Debug]|r %s spellID=%d (%s)"):format(
            event == "SPELL_ACTIVATION_OVERLAY_SHOW" and "GLOW ON" or "GLOW OFF",
            spellID, info and info.name or "?"))
    end

    if event == "SPELL_ACTIVATION_OVERLAY_SHOW" then
        ForEachMatch(spellID, function(id, trigger, sid)
            if procActive[id] then return end -- de-dupe repeated SHOW while active
            procActive[id] = true
            if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SPELL_PROC glow ON:", trigger.name or id, "spell", tostring(sid)) end
            local c = trigger.conditions or {}
            local fireOnGained = c.onBoth or not c.onLost
            if fireOnGained and Triggers:CheckZoneRestrictions(trigger.zones) then
                Triggers:ExecuteTrigger(trigger, { spellID = sid, isLost = false })
            end
        end)
    else -- SPELL_ACTIVATION_OVERLAY_HIDE
        ForEachMatch(spellID, function(id, trigger, sid)
            if not procActive[id] then return end
            procActive[id] = nil
            CancelLoop(id, trigger)
            if OxedHub.debug then print("|cff00ffff[OxedHub-Debug]|r SPELL_PROC glow OFF:", trigger.name or id) end
            local c = trigger.conditions or {}
            if (c.onLost or c.onBoth) and Triggers:CheckZoneRestrictions(trigger.zones) then
                Triggers:ExecuteTrigger(trigger, { spellID = sid, isLost = true })
            end
        end)
    end
end)

Triggers._spellProcMonitor = f
