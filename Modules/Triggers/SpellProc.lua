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
        local finalRightY = 0

        if Triggers.CreateAuraSpellSearchUI then
            yOffset = Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end

        local smartSpells = {}
        local seenSpells = {}
        
        -- 1. Scan action bars for current spells
        for slot = 1, 120 do
            local actionType, id = GetActionInfo(slot)
            local sid = nil
            if actionType == "spell" then
                sid = id
            elseif actionType == "macro" then
                sid = GetMacroSpell(id)
            end
            if sid and not seenSpells[sid] then
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                local spellName = spellInfo and spellInfo.name or (GetSpellInfo and GetSpellInfo(sid))
                local ignore = false
                if spellName then
                    local lowerName = string.lower(spellName)
                    if lowerName:find("fishing") or lowerName:find("leatherworking") or lowerName:find("skinning") 
                       or lowerName:find("herbalism") or lowerName:find("mining") or lowerName:find("cooking")
                       or lowerName:find("tailoring") or lowerName:find("enchanting") or lowerName:find("engineering")
                       or lowerName:find("inscription") or lowerName:find("alchemy") or lowerName:find("jewelcrafting")
                       or lowerName:find("blacksmithing") or lowerName:find("archaeology") or lowerName:find("campfire")
                       or lowerName:find("play dead") or lowerName:find("fetch") or lowerName:find("call pet")
                       or lowerName:find("revive pet") then
                        ignore = true
                    end
                end
                if not ignore then
                    table.insert(smartSpells, sid)
                    seenSpells[sid] = true
                end
            end
        end
        
        -- 2. Add class-specific suggestions if they are known/valid for current spec
        local _, classToken = UnitClass("player")
        if not classToken and OxedHub.GetPlayerClassToken then classToken = OxedHub:GetPlayerClassToken() end
        local classSpells = Triggers.ClassGlowSpells and Triggers.ClassGlowSpells[classToken]
        
        if classSpells then
            for _, sid in ipairs(classSpells) do
                if not seenSpells[sid] then
                    -- Filter out spells they don't actually have (e.g. wrong spec)
                    if IsPlayerSpell(sid) or IsSpellKnown(sid) or IsSpellKnown(sid, true) then
                        table.insert(smartSpells, sid)
                        seenSpells[sid] = true
                    end
                end
            end
        end
        local suggestedSpells = smartSpells
        
        if suggestedSpells and #suggestedSpells > 0 then
            local gridLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local startY = 15 -- Moved up by 15 pixels
            gridLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 445, startY)
            gridLabel:SetText("|cffffd100Class Glow Suggestions|r")
            local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
            scrollFrame:SetSize(450, 132)
            scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 445, startY - 20)
            
            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetSize(450, 1)
            scrollFrame:SetScrollChild(scrollChild)
            
            if OxedHub.UIComponents and OxedHub.UIComponents.Scroll and OxedHub.UIComponents.Scroll.StyleFrame then
                OxedHub.UIComponents.Scroll.StyleFrame(scrollFrame)
                scrollFrame:HookScript("OnShow", function(self)
                    if self.oxedMinimalScrollBar then
                        if (math.ceil(#suggestedSpells / 3) * 44) <= 132 then
                            self.oxedMinimalScrollBar:Hide()
                        else
                            self.oxedMinimalScrollBar:Show()
                        end
                    end
                end)
                if scrollFrame.oxedMinimalScrollBar and (math.ceil(#suggestedSpells / 3) * 44) <= 132 then
                    scrollFrame.oxedMinimalScrollBar:Hide()
                end
            end
            
            local function CreateSuggestionIcon(parent, spellID, x, y)
                local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
                btn:SetSize(145, 42) -- 3-column Wide button
                btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
                
                local sidStr = tostring(spellID)
                local isSelected = false
                if conditions.spellID == sidStr then
                    isSelected = true
                elseif conditions.extraSpellIDs then
                    for _, sid in ipairs(conditions.extraSpellIDs) do
                        if tostring(sid) == sidStr then isSelected = true; break end
                    end
                end

                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 }
                })
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                
                if isSelected then
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
                end
                
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(38, 38)
                btn.icon:SetPoint("LEFT", 3, 0)
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                
                -- Removed icon border, relying solely on button backdrop border
                
                local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
                highlight:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", 0, 0)
                highlight:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", 0, 0)
                highlight:SetBlendMode("ADD")
                
                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
                btn.text:SetPoint("RIGHT", -4, 0)
                btn.text:SetJustifyH("LEFT")
                btn.text:SetWordWrap(true)
                
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                if spellInfo and spellInfo.iconID then
                    btn.icon:SetTexture(spellInfo.iconID)
                    btn.text:SetText(spellInfo.name)
                else
                    btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.text:SetText("ID: " .. sidStr)
                end
                
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if spellInfo then
                        GameTooltip:SetText(spellInfo.name, 1, 0.82, 0)
                        GameTooltip:AddLine("Spell ID: " .. tostring(spellID), 0.6, 0.6, 0.6)
                    else
                        GameTooltip:SetText("Spell ID: " .. tostring(spellID), 1, 0.82, 0)
                    end
                    GameTooltip:AddLine(" ")
                    if isSelected then
                        GameTooltip:AddLine("This spell is currently selected.", 1, 0.82, 0)
                        GameTooltip:AddLine("Click again to remove it from the trigger.", 0.8, 0.8, 0.8, true)
                    else
                        GameTooltip:AddLine("Click to automatically add this spell to your trigger.", 0.2, 1, 0.2, true)
                        GameTooltip:AddLine("When this proc glows on your action bars, the trigger will activate and play your chosen Actions (Sounds, Animations, etc).", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                btn:SetScript("OnClick", function()
                    if isSelected then
                        -- Remove it
                        if conditions.spellID == sidStr then
                            conditions.spellID = ""
                            if conditions.extraSpellIDs and #conditions.extraSpellIDs > 0 then
                                conditions.spellID = table.remove(conditions.extraSpellIDs, 1)
                            end
                        elseif conditions.extraSpellIDs then
                            for idx, sid in ipairs(conditions.extraSpellIDs) do
                                if tostring(sid) == sidStr then
                                    table.remove(conditions.extraSpellIDs, idx)
                                    break
                                end
                            end
                        end
                    else
                        -- Add it
                        if not conditions.spellID or conditions.spellID == "" then
                            conditions.spellID = sidStr
                        else
                            conditions.extraSpellIDs = conditions.extraSpellIDs or {}
                            local found = false
                            if tostring(conditions.spellID) == sidStr then found = true end
                            for _, sid in ipairs(conditions.extraSpellIDs) do
                                if tostring(sid) == sidStr then found = true; break end
                            end
                            if not found then
                                table.insert(conditions.extraSpellIDs, sidStr)
                            end
                        end
                    end
                    if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
                    local card = Triggers.triggerCards[trigger.id]
                    if card then
                        Triggers:RefreshTriggerCardConditions(card, trigger)
                    end
                end)
                return btn
            end
            
            -- Adjust cols and spacing for wide buttons
            local cols = 3
            for i, spellID in ipairs(suggestedSpells) do
                local row = math.floor((i - 1) / cols)
                local col = (i - 1) % cols
                CreateSuggestionIcon(scrollChild, spellID, col * 150, row * 44)
            end
            local rows = math.ceil(#suggestedSpells / 3)
            scrollChild:SetHeight(rows * 44)
            finalRightY = startY - 20 - math.min(132, rows * 44)
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
        return math.min(yOffset, finalRightY)
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
