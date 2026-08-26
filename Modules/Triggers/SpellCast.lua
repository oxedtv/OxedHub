local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("UNIT_SPELLCAST_SUCCEEDED", {
    name = "Spell Cast Success",
    CheckCondition = function(trigger, eventData)
        -- Handled by general spellID check in Triggers:ShouldTrigger
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        if OxedHub.Triggers.CreateAuraSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end

        local conditions = trigger.conditions or {}

        local finalRightY = 0
        
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
        local classSpells = OxedHub.Triggers.ClassCasts and OxedHub.Triggers.ClassCasts[classToken]
        
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
            local startY = 30 -- Moved up by 15 pixels
            gridLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 445, startY)
            gridLabel:SetText("|cffffd100Class Spell Suggestions|r  |cff888888(click several — the trigger fires for any of them)|r")
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
                    -- Clearly "in use": gold border, warm fill and a tick, rather
                    -- than a subtle border change that read as the tile greying out.
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                    btn:SetBackdropColor(0.25, 0.20, 0.05, 0.95)
                else
                    btn:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
                end

                if isSelected then
                    btn.tick = btn:CreateTexture(nil, "OVERLAY")
                    btn.tick:SetSize(16, 16)
                    btn.tick:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
                    btn.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
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
                        GameTooltip:AddLine("When you cast this spell, the trigger will activate and play your chosen Actions (Sounds, Animations, etc).", 0.8, 0.8, 0.8, true)
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
                    if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
                    local card = OxedHub.Triggers.triggerCards[trigger.id]
                    if card then
                        OxedHub.Triggers:RefreshTriggerCardConditions(card, trigger)
                    end
                end)
                return btn
            end
            
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
        return math.min(yOffset, finalRightY)
    end
})
