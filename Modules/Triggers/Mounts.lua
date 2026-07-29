local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("MOUNT", {
    name = OxedHub.L["TR_MOUNTS_NAME"] or "Mount Up / Dismount",
    CheckCondition = function(trigger, eventData)
        local conditions = trigger.conditions or {}
        local onUp = conditions.onUp ~= false
        local onDown = conditions.onDown == true
        local isUp = eventData.actionType == "up"
        
        if isUp and not onUp then return false end
        if not isUp and not onDown then return false end
        
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}
        trigger.actions = trigger.actions or {}
        local actions = trigger.actions
        
        -- Add Info Icon to the end of the gray description line
        local card = frame:GetParent() and frame:GetParent():GetParent()
        if card and card.conditionsDescLabel then
            local infoIcon = CreateFrame("Frame", nil, frame)
            infoIcon:SetSize(16, 16)
            infoIcon:SetPoint("LEFT", card.conditionsDescLabel, "RIGHT", 4, 0)
            
            local tex = infoIcon:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetTexture("Interface\\FriendsFrame\\InformationIcon")
            
            infoIcon:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(OxedHub.L["TR_MOUNTS_EMOTE_NOTE"] or "Note: Not every emote animation can be played while mounted up, so experiment!", nil, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            infoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        
        if conditions.onUp == nil then conditions.onUp = true end
        
        local function saveConditions()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end
        
        -- Trigger On
        local actionLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        actionLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        actionLabel:SetText(OxedHub.L["TR_MOUNTS_TRIGGER_ON"] or "Trigger On:")
        yOffset = yOffset - 25
        
        local upCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        upCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        upCheck:SetSize(20, 20)
        upCheck:SetChecked(conditions.onUp)
        upCheck.text:SetText(OxedHub.L["TR_MOUNTS_MOUNT_UP"] or "Mount Up")
        
        local downCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        downCheck:SetPoint("LEFT", upCheck.text, "RIGHT", 80, 0)
        downCheck:SetSize(20, 20)
        downCheck:SetChecked(conditions.onDown)
        downCheck.text:SetText(OxedHub.L["TR_MOUNTS_DISMOUNT"] or "Dismount")
        
        upCheck:SetScript("OnClick", function(self)
            conditions.onUp = self:GetChecked()
            saveConditions()
        end)
        downCheck:SetScript("OnClick", function(self)
            conditions.onDown = self:GetChecked()
            saveConditions()
        end)
        
        yOffset = yOffset - 40
        
        local function CreateIcon(parent, texturePath)
            local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            iconFrame:SetSize(24, 24)
            iconFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            iconFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            iconFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
            icon:SetTexture(texturePath)
            iconFrame.border = CreateFrame("Frame", nil, iconFrame)
            iconFrame.icon = icon
            return iconFrame
        end
        
        local function TruncateText(text, maxLength)
            if not text or text == "None" or text == "None" then return "None" end
            if string.len(text) <= maxLength then return text end
            return string.sub(text, 1, maxLength - 3) .. "..."
        end

        local function CreateColumn(title, xOffset, prefix)
            local titleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            titleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", xOffset, yOffset)
            titleLabel:SetText(title)
            
            local colY = -20
            
            -- Sound Picker
            local soundIcon = CreateIcon(frame, "Interface\\Icons\\INV_Misc_Horn_01")
            soundIcon:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, colY)
            
            local soundLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            soundLabel:SetPoint("BOTTOMLEFT", soundIcon, "TOPLEFT", 0, 2)
            soundLabel:SetText(OxedHub.L["TR_MOUNTS_SOUND"] or "Sound:")
            
            local soundBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            soundBtn:SetPoint("LEFT", soundIcon, "RIGHT", 4, 0)
            soundBtn:SetSize(110, 22)
            soundBtn:SetNormalFontObject("GameFontNormalSmall")
            
            local function UpdateSoundBtn()
                local val = actions[prefix.."Sound"]
                local fullName = val or "None"
                local text = fullName
                if val and val ~= "None" then
                    local data = OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[val]
                    if data then fullName = data.name end
                    text = TruncateText(fullName, 14)
                end
                soundBtn:SetText(text)
            end
            UpdateSoundBtn()
            
            soundBtn:SetScript("OnClick", function()
                OxedHub.Triggers:ShowSoundPicker(trigger, prefix.."Sound")
            end)
            soundBtn:SetScript("OnUpdate", function(self)
                local val = actions[prefix.."Sound"]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateSoundBtn()
                end
            end)
            
            colY = colY - 38
            
            -- Animation Picker
            local animIcon = CreateIcon(frame, "Interface\\Icons\\Ability_Rogue_Sprint")
            animIcon:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, colY)
            
            local animLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            animLabel:SetPoint("BOTTOMLEFT", animIcon, "TOPLEFT", 0, 2)
            animLabel:SetText(OxedHub.L["TR_MOUNTS_ANIMATION"] or "Animation:")
            
            local animBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            animBtn:SetPoint("LEFT", animIcon, "RIGHT", 4, 0)
            animBtn:SetSize(110, 22)
            animBtn:SetNormalFontObject("GameFontNormalSmall")
            
            local function UpdateAnimBtn()
                local val = actions[prefix.."Anim"]
                local fullName = val or "None"
                local text = fullName
                if val and val ~= "None" then
                    local data = OxedHub.db.profile.animations and OxedHub.db.profile.animations[val]
                    if data then fullName = data.name end
                    text = TruncateText(fullName, 14)
                end
                animBtn:SetText(text)
            end
            UpdateAnimBtn()
            
            animBtn:SetScript("OnClick", function()
                OxedHub.Triggers:ShowAnimationPicker(trigger, prefix.."Anim")
            end)
            animBtn:SetScript("OnUpdate", function(self)
                local val = actions[prefix.."Anim"]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateAnimBtn()
                end
            end)
            
            colY = colY - 38
            
            -- Emote Picker
            local emoteIcon = CreateIcon(frame, "Interface\\Icons\\UI_Chat")
            emoteIcon:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, colY)
            
            local emoteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            emoteLabel:SetPoint("BOTTOMLEFT", emoteIcon, "TOPLEFT", 0, 2)
            emoteLabel:SetText(OxedHub.L["TR_MOUNTS_EMOTE"] or "Emote:")
            
            local emoteBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            emoteBtn:SetPoint("LEFT", emoteIcon, "RIGHT", 4, 0)
            emoteBtn:SetSize(110, 22)
            emoteBtn:SetNormalFontObject("GameFontNormalSmall")
            
            local function UpdateEmoteBtn()
                local val = actions[prefix.."Emote"]
                local text = val or "None"
                text = TruncateText(text, 14)
                emoteBtn:SetText(text)
            end
            UpdateEmoteBtn()
            
            emoteBtn:SetScript("OnClick", function()
                OxedHub.Triggers.currentEmoteActionType = prefix.."Emote"
                -- Actually ShowEmotePicker doesn't take actionType as a second arg like the others?
                -- Wait, let's verify if ShowEmotePicker does support it. If not, I can just patch it here!
                OxedHub.Triggers.currentTriggerForPicker = trigger
                if not OxedHub.Triggers.emotePicker then
                    OxedHub.Triggers.emotePicker = OxedHub.Triggers:CreateGenericPicker("Emote", "Pick Emote", prefix.."Emote")
                end
                OxedHub.Triggers.emotePicker.currentActionType = prefix.."Emote"
                OxedHub.Triggers:HideAllPickers()
                OxedHub.Triggers.emotePicker:Show()
                OxedHub.Triggers:RefreshPickerList(OxedHub.Triggers.emotePicker, prefix.."Emote")
            end)
            emoteBtn:SetScript("OnUpdate", function(self)
                local val = actions[prefix.."Emote"]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateEmoteBtn()
                end
            end)
            
            colY = colY - 38
        end
        
        CreateColumn(OxedHub.L["TR_MOUNTS_GROUND"] or "Ground Mount", 0, "ground")
        CreateColumn(OxedHub.L["TR_MOUNTS_FLYING"] or "Flying Mount", 155, "flying")
        CreateColumn(OxedHub.L["TR_MOUNTS_AQUATIC"] or "Aquatic Mount", 310, "aquatic")
        
        yOffset = yOffset - 152
        return yOffset
    end
})
