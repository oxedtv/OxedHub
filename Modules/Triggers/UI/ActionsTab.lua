local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

function Triggers:CreateActionsUI(frame, trigger)
    local actions = trigger.actions or {}
    local yOffset = 0
    
    local function CreateActionIcon(parent, texturePath)
        local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        iconFrame:SetSize(28, 28)
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

        -- Compatibility with RepositionVisibleActions which expects border Show/Hide
        iconFrame.border = CreateFrame("Frame", nil, iconFrame)
        iconFrame.icon = icon
        return iconFrame
    end

    -- Sound picker button
    local soundIcon = CreateActionIcon(frame, "Interface\\Icons\\INV_Misc_Horn_01")
    frame.soundIcon = soundIcon
    local soundLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundLabel:SetPoint("LEFT", soundIcon, "RIGHT", 8, 0)
    soundLabel:SetText((L["LBL_SOUND"] or "Sound") .. ":")
    
    local soundButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    soundButton:SetSize(150, 22)
    soundButton:SetPoint("LEFT", soundLabel, "RIGHT", 10, 0)
    soundButton:SetNormalFontObject("GameFontNormalSmall")

    -- Manual text truncation function
    local function TruncateText(text, maxLength)
        if not text or text == "None" or text == L["NONE"] then return L["NONE"] or "None" end
        if string.len(text) <= maxLength then return text end
        return string.sub(text, 1, maxLength - 3) .. "..."
    end

    local function UpdateSoundButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.sound and actions.sound ~= "" then
            local soundData = OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[actions.sound]
            fullName = soundData and soundData.name or actions.sound
            text = TruncateText(fullName, 20)
        end
        soundButton:SetText(text)
        soundButton.fullText = fullName
    end
    UpdateSoundButton()

    -- Tooltip to show full name on hover
    soundButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    soundButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    soundButton:SetScript("OnClick", function() Triggers:ShowSoundPicker(trigger) end)
    frame.soundButton = soundButton
    yOffset = yOffset - 28
    
    -- Animation picker button
    local animIcon = CreateActionIcon(frame, "Interface\\Icons\\Ability_Rogue_Sprint")
    frame.animIcon = animIcon
    local animLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    animLabel:SetPoint("LEFT", animIcon, "RIGHT", 8, 0)
    animLabel:SetText((L["LBL_ANIMATION"] or "Animation") .. ":")

    local animButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    animButton:SetPoint("LEFT", animLabel, "RIGHT", 10, 0)
    animButton:SetSize(150, 22)
    animButton:SetNormalFontObject("GameFontNormalSmall")

    local function UpdateAnimButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.animation then
            local data = OxedHub.db.profile.animations and OxedHub.db.profile.animations[actions.animation]
            fullName = data and data.name or actions.animation
            text = TruncateText(fullName, 20)
        end
        animButton:SetText(text)
        animButton.fullText = fullName
    end
    UpdateAnimButton()

    -- Tooltip to show full name on hover
    animButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    animButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    animButton:SetScript("OnClick", function() Triggers:ShowAnimationPicker(trigger) end)
    frame.animButton = animButton
    yOffset = yOffset - 28
    -- Combat warning for emote and chat
    local combatWarningLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    combatWarningLabel:SetText(L["LBL_COMBAT_WARNING"] or "* Emote and chat templates cannot be triggered automatically in combat (use Action Hub or macros).")
    combatWarningLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    combatWarningLabel:SetWidth(400)
    combatWarningLabel:SetJustifyH("LEFT")
    frame.combatWarningLabel = combatWarningLabel
    yOffset = yOffset - 20

    -- Emote picker button
    local emoteIcon = CreateActionIcon(frame, "Interface\\Icons\\UI_Chat")
    frame.emoteIcon = emoteIcon
    local emoteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emoteLabel:SetPoint("LEFT", emoteIcon, "RIGHT", 8, 0)
    emoteLabel:SetText((L["LBL_EMOTE"] or "Emote") .. ":")

    local emoteButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    emoteButton:SetPoint("LEFT", emoteLabel, "RIGHT", 10, 0)
    emoteButton:SetSize(150, 22)
    emoteButton:SetNormalFontObject("GameFontNormalSmall")

    local function UpdateEmoteButton()
        local text = actions.emote or "None"
        if text == "None" then text = L["NONE"] or "None" end
        local fullName = text
        text = TruncateText(text, 20)
        emoteButton:SetText(text)
        emoteButton.fullText = fullName
    end
    UpdateEmoteButton()

    -- Tooltip to show full name on hover
    emoteButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    emoteButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    emoteButton:SetScript("OnClick", function() Triggers:ShowEmotePicker(trigger) end)
    frame.emoteButton = emoteButton
    yOffset = yOffset - 28
    
    -- Chat Template picker button
    local chatIcon = CreateActionIcon(frame, "Interface\\Icons\\INV_Misc_Note_01")
    frame.chatIcon = chatIcon
    local chatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatLabel:SetPoint("LEFT", chatIcon, "RIGHT", 8, 0)
    chatLabel:SetText((L["LBL_CHAT_TEMPLATE"] or "Chat Template") .. ":")
    frame.chatLabel = chatLabel

    local chatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    chatButton:SetPoint("LEFT", chatLabel, "RIGHT", 10, 0)
    chatButton:SetSize(150, 22)
    chatButton:SetNormalFontObject("GameFontNormalSmall")
    frame.chatButton = chatButton

    local function UpdateChatButtonText()
        local chatID = actions.chatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        local fullName = chatName
        chatName = TruncateText(chatName, 20)
        chatButton:SetText(chatName)
        chatButton.fullText = fullName
    end
    UpdateChatButtonText()

    -- Tooltip to show full name on hover
    chatButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    chatButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    chatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger) end)
    yOffset = yOffset - 28

    -- Toy Mix picker button (Spell Cast Success only)
    local toyIcon = CreateActionIcon(frame, "Interface\\Icons\\INV_Misc_Toy_09")
    frame.toyIcon = toyIcon
    local toyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyLabel:SetPoint("LEFT", toyIcon, "RIGHT", 8, 0)
    toyLabel:SetText((L["LBL_TOY"] or "Toy") .. ":")
    frame.toyLabel = toyLabel

    local toyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    toyButton:SetPoint("LEFT", toyLabel, "RIGHT", 10, 0)
    toyButton:SetSize(150, 22)
    toyButton:SetNormalFontObject("GameFontNormalSmall")
    frame.toyButton = toyButton

    local function UpdateToyButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.toy and actions.toy ~= "" then
            local toyStr = tostring(actions.toy)
            local directID = toyStr:match("^toyid:(%d+)$")
            if directID then
                local itemID = tonumber(directID)
                if itemID then
                    local _, toyName = C_ToyBox.GetToyInfo(itemID)
                    fullName = toyName or ("Toy #" .. itemID)
                end
            else
                local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[actions.toy]
                fullName = mixData and mixData.name or actions.toy
            end
            text = TruncateText(fullName, 20)
        end
        toyButton:SetText(text)
        toyButton.fullText = fullName
    end
    UpdateToyButton()

    toyButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    toyButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    toyButton:SetScript("OnClick", function() Triggers:ShowToyPicker(trigger) end)
    toyLabel:Hide(); toyButton:Hide(); toyIcon:Hide()
    yOffset = yOffset - 28

    -- Success Sound picker (interrupt events only)
    local successSoundLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    successSoundLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    successSoundLabel:SetText("|cff00ff00" .. (L["LBL_SUCCESS_SOUND"] or "Success Sound") .. ":|r")
    successSoundLabel:Hide()

    local successSoundButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    successSoundButton:SetSize(150, 22)
    successSoundButton:SetPoint("LEFT", successSoundLabel, "RIGHT", 10, 0)
    successSoundButton:SetNormalFontObject("GameFontNormalSmall")
    successSoundButton:Hide()

    local function UpdateSuccessSoundButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.successSound and actions.successSound ~= "" then
            local soundData = OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[actions.successSound]
            fullName = soundData and soundData.name or actions.successSound
            text = TruncateText(fullName, 20)
        end
        successSoundButton:SetText(text)
        successSoundButton.fullText = fullName
    end
    UpdateSuccessSoundButton()

    -- Tooltip to show full name on hover
    successSoundButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    successSoundButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    successSoundButton:SetScript("OnClick", function() Triggers:ShowSoundPicker(trigger, "successSound") end)
    frame.successSoundButton = successSoundButton
    frame.successSoundLabel = successSoundLabel
    yOffset = yOffset - 28

    -- Success Animation picker (interrupt events only)
    local successAnimLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    successAnimLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    successAnimLabel:SetText("|cff00ff00" .. (L["LBL_SUCCESS_ANIMATION"] or "Success Animation") .. ":|r")
    successAnimLabel:Hide()

    local successAnimButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    successAnimButton:SetSize(150, 22)
    successAnimButton:SetPoint("LEFT", successAnimLabel, "RIGHT", 10, 0)
    successAnimButton:SetNormalFontObject("GameFontNormalSmall")
    successAnimButton:Hide()

    local function UpdateSuccessAnimButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.successAnimation then
            local data = OxedHub.db.profile.animations and OxedHub.db.profile.animations[actions.successAnimation]
            fullName = data and data.name or actions.successAnimation
            text = TruncateText(fullName, 20)
        end
        successAnimButton:SetText(text)
        successAnimButton.fullText = fullName
    end
    UpdateSuccessAnimButton()

    -- Tooltip to show full name on hover
    successAnimButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    successAnimButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    successAnimButton:SetScript("OnClick", function() Triggers:ShowAnimationPicker(trigger, "successAnimation") end)
    frame.successAnimButton = successAnimButton
    frame.successAnimLabel = successAnimLabel
    yOffset = yOffset - 28
    
    -- EAT_BUFF specific: Start/Stop chat messages
    local startChatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    startChatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 3)
    startChatLabel:SetText("|cff00ff00" .. (L["LBL_START_CHAT"] or "Start Chat") .. ":|r")
    startChatLabel:Hide()
    frame.startChatLabel = startChatLabel

    local startChatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    startChatButton:SetPoint("LEFT", startChatLabel, "RIGHT", 10, 0)
    startChatButton:SetSize(150, 22)
    startChatButton:SetNormalFontObject("GameFontNormalSmall")
    startChatButton:Hide()
    frame.startChatButton = startChatButton

    local function UpdateStartChatButtonText()
        local chatID = actions.startChatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        startChatButton:SetText(TruncateText(chatName, 20))
    end
    UpdateStartChatButtonText()
    startChatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger, "startChatMessage") end)

    yOffset = yOffset - 28

    local stopChatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stopChatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 3)
    stopChatLabel:SetText("|cffff0000" .. (L["LBL_STOP_CHAT"] or "Stop Chat") .. ":|r")
    stopChatLabel:Hide()
    frame.stopChatLabel = stopChatLabel

    local stopChatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    stopChatButton:SetPoint("LEFT", stopChatLabel, "RIGHT", 10, 0)
    stopChatButton:SetSize(150, 22)
    stopChatButton:SetNormalFontObject("GameFontNormalSmall")
    stopChatButton:Hide()
    frame.stopChatButton = stopChatButton

    local function UpdateStopChatButtonText()
        local chatID = actions.stopChatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        stopChatButton:SetText(TruncateText(chatName, 20))
    end
    UpdateStopChatButtonText()
    stopChatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger, "stopChatMessage") end)

    yOffset = yOffset - 28

    local summonIncomingChatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summonIncomingChatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 3)
    summonIncomingChatLabel:SetText("|cffffff00" .. (L["LBL_SUMMON_CHAT"] or "Summon Chat") .. ":|r")
    summonIncomingChatLabel:Hide()

    local summonIncomingChatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    summonIncomingChatButton:SetPoint("LEFT", summonIncomingChatLabel, "RIGHT", 10, 0)
    summonIncomingChatButton:SetSize(150, 22)
    summonIncomingChatButton:SetNormalFontObject("GameFontNormalSmall")
    summonIncomingChatButton:Hide()

    local function UpdateSummonIncomingChatButtonText()
        local chatID = actions.summonIncomingChatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        summonIncomingChatButton:SetText(TruncateText(chatName, 20))
    end
    UpdateSummonIncomingChatButtonText()
    summonIncomingChatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger, "summonIncomingChatMessage") end)

    yOffset = yOffset - 28

    local summonAcceptedChatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summonAcceptedChatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 3)
    summonAcceptedChatLabel:SetText("|cff00ff00" .. (L["LBL_ACCEPT_CHAT"] or "Accept Chat") .. ":|r")
    summonAcceptedChatLabel:Hide()

    local summonAcceptedChatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    summonAcceptedChatButton:SetPoint("LEFT", summonAcceptedChatLabel, "RIGHT", 10, 0)
    summonAcceptedChatButton:SetSize(150, 22)
    summonAcceptedChatButton:SetNormalFontObject("GameFontNormalSmall")
    summonAcceptedChatButton:Hide()

    local function UpdateSummonAcceptedChatButtonText()
        local chatID = actions.summonAcceptedChatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        summonAcceptedChatButton:SetText(TruncateText(chatName, 20))
    end
    UpdateSummonAcceptedChatButtonText()
    summonAcceptedChatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger, "summonAcceptedChatMessage") end)

    yOffset = yOffset - 28

    local summonDeclinedChatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summonDeclinedChatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 3)
    summonDeclinedChatLabel:SetText("|cffff0000" .. (L["LBL_DECLINE_CHAT"] or "Decline Chat") .. ":|r")
    summonDeclinedChatLabel:Hide()

    local summonDeclinedChatButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    summonDeclinedChatButton:SetPoint("LEFT", summonDeclinedChatLabel, "RIGHT", 10, 0)
    summonDeclinedChatButton:SetSize(150, 22)
    summonDeclinedChatButton:SetNormalFontObject("GameFontNormalSmall")
    summonDeclinedChatButton:Hide()

    local function UpdateSummonDeclinedChatButtonText()
        local chatID = actions.summonDeclinedChatMessage
        local chatName = L["NONE"] or "None"
        if chatID and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[chatID] then
            chatName = OxedHub.db.profile.chatTemplates[chatID].name or chatID
        end
        summonDeclinedChatButton:SetText(TruncateText(chatName, 20))
    end
    UpdateSummonDeclinedChatButtonText()
    summonDeclinedChatButton:SetScript("OnClick", function() Triggers:ShowChatPicker(trigger, "summonDeclinedChatMessage") end)

    yOffset = yOffset - 28

    -- Fail Sound picker (interrupt events only)
    local failSoundLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    failSoundLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    failSoundLabel:SetText("|cffff0000" .. (L["LBL_FAIL_SOUND"] or "Fail Sound") .. ":|r")
    failSoundLabel:Hide()

    local failSoundButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    failSoundButton:SetSize(150, 22)
    failSoundButton:SetPoint("LEFT", failSoundLabel, "RIGHT", 10, 0)
    failSoundButton:SetNormalFontObject("GameFontNormalSmall")
    failSoundButton:Hide()

    local function UpdateFailSoundButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.failSound and actions.failSound ~= "" then
            local soundData = OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[actions.failSound]
            fullName = soundData and soundData.name or actions.failSound
            text = TruncateText(fullName, 20)
        end
        failSoundButton:SetText(text)
        failSoundButton.fullText = fullName
    end
    UpdateFailSoundButton()

    -- Tooltip to show full name on hover
    failSoundButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    failSoundButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    failSoundButton:SetScript("OnClick", function() Triggers:ShowSoundPicker(trigger, "failSound") end)
    frame.failSoundButton = failSoundButton
    frame.failSoundLabel = failSoundLabel
    yOffset = yOffset - 28

    -- Fail Animation picker (interrupt events only)
    local failAnimLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    failAnimLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    failAnimLabel:SetText("|cffff0000" .. (L["LBL_FAIL_ANIMATION"] or "Fail Animation") .. ":|r")
    failAnimLabel:Hide()

    local failAnimButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    failAnimButton:SetSize(150, 22)
    failAnimButton:SetPoint("LEFT", failAnimLabel, "RIGHT", 10, 0)
    failAnimButton:SetNormalFontObject("GameFontNormalSmall")
    failAnimButton:Hide()

    local function UpdateFailAnimButton()
        local text = L["NONE"] or "None"
        local fullName = L["NONE"] or "None"
        if actions.failAnimation then
            local data = OxedHub.db.profile.animations and OxedHub.db.profile.animations[actions.failAnimation]
            fullName = data and data.name or actions.failAnimation
            text = TruncateText(fullName, 20)
        end
        failAnimButton:SetText(text)
        failAnimButton.fullText = fullName
    end
    UpdateFailAnimButton()

    -- Tooltip to show full name on hover
    failAnimButton:SetScript("OnEnter", function(self)
        if self.fullText and self.fullText ~= "None" and self.fullText ~= L["NONE"] then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.fullText)
            GameTooltip:Show()
        end
    end)
    failAnimButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    failAnimButton:SetScript("OnClick", function() Triggers:ShowAnimationPicker(trigger, "failAnimation") end)
    frame.failAnimButton = failAnimButton
    frame.failAnimLabel = failAnimLabel
    yOffset = yOffset - 28

    -- Cooldown Animation toggle (interrupt events only)
    local cdAnimCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cdAnimCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    cdAnimCheck:SetSize(20, 20)
    cdAnimCheck:SetChecked(actions.cooldownAnimation or false)
    cdAnimCheck.text:SetText(L["LBL_SHOW_COOLDOWN_PROGRESS"] or "Show Cooldown Progress")
    cdAnimCheck.text:ClearAllPoints()
    cdAnimCheck.text:SetPoint("LEFT", cdAnimCheck, "RIGHT", 4, 0)
    cdAnimCheck:SetScript("OnClick", function(self)
        actions.cooldownAnimation = self:GetChecked()
        ShowAutoSaved(frame:GetParent())
    end)
    frame.cdAnimCheck = cdAnimCheck

    -- Position button for cooldown progress
    local cdPosBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cdPosBtn:SetSize(70, 20)
    cdPosBtn:SetPoint("LEFT", cdAnimCheck.text, "RIGHT", 10, 0)
    cdPosBtn:SetText(L["BTN_POSITION"] or "Position")
    cdPosBtn:SetScript("OnClick", function()
        if OxedHub.Animations and OxedHub.Animations.ShowCooldownPositionFrame then
            local spellID = trigger.conditions and trigger.conditions.spellID
            OxedHub.Animations:ShowCooldownPositionFrame(spellID)
        end
    end)
    frame.cdPosBtn = cdPosBtn
    yOffset = yOffset - 28
    
    -- Macro draggable icon and warning
    local macroWarning = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroWarning:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, 6)
    macroWarning:SetWidth(220)
    macroWarning:SetJustifyH("CENTER")
    macroWarning:SetText(L["LBL_DRAG_DROP_ICON"] or "Drag and drop this icon to your action bar:")
    macroWarning:SetTextColor(0, 1, 0)
    macroWarning:Hide()
    frame.macroWarning = macroWarning

    local macroIcon = CreateFrame("Button", nil, frame)
    macroIcon:SetSize(64, 64)
    macroIcon:SetPoint("TOP", macroWarning, "BOTTOM", 0, -8)
    macroIcon:Hide()
    macroIcon:EnableMouse(true)
    macroIcon:RegisterForDrag("LeftButton")

    macroIcon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local macroAttention = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroAttention:SetPoint("TOP", macroIcon, "BOTTOM", 0, -8)
    macroAttention:SetWidth(320)
    macroAttention:SetText("|cffffd100ActionHub:|r " .. (L["LBL_ACTIONHUB_ASSIGN"] or "assign to a button — no macro slot used (OxedEngine internal)") .. ".\n" .. (L["LBL_ACTIONHUB_DRAG"] or "Or drag the icon to your action bar — uses 1 slot in your general or class macros."))
    macroAttention:SetTextColor(1, 1, 1)
    macroAttention:SetJustifyH("CENTER")
    macroAttention:Hide()
    frame.macroAttention = macroAttention
    
    macroIcon:SetScript("OnMouseDown", function()
        Triggers:CreateMacroForTrigger(trigger)
    end)
    
    macroIcon:SetScript("OnDragStart", function()
        local macroName = Triggers:CreateMacroForTrigger(trigger)
        if macroName then
            local index = GetMacroIndexByName(macroName)
            if index > 0 then
                PickupMacro(index)
            end
        end
    end)
    
    macroIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TLT_TRIGGER_MACRO"] or "Trigger Macro")
        GameTooltip:AddLine(L["TLT_DRAG_ACTION_BAR"] or "Drag this to your action bar to use this trigger in combat.", 1, 1, 1, true)
        GameTooltip:AddLine(L["TLT_USED_SPELL_CAST_SUCCESS"] or "Used for Spell Cast Success when chat or emote template is set.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    macroIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Animated glow border around macro icon (sits OUTSIDE the icon edges)
    local glowFrame = CreateFrame("Frame", nil, macroIcon)
    glowFrame:SetPoint("TOPLEFT", macroIcon, "TOPLEFT", -12, 12)
    glowFrame:SetPoint("BOTTOMRIGHT", macroIcon, "BOTTOMRIGHT", 12, -12)
    glowFrame:SetFrameLevel(macroIcon:GetFrameLevel() - 1)

    -- Use 4 edge textures for a proper outer glow border
    local glowTex = glowFrame:CreateTexture(nil, "BACKGROUND")
    glowTex:SetAllPoints()
    glowTex:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    glowTex:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
    glowTex:SetBlendMode("ADD")
    glowTex:SetVertexColor(1, 0.75, 0, 1) -- golden glow

    local pulseAG = glowFrame:CreateAnimationGroup()
    pulseAG:SetLooping("BOUNCE")
    local fadeOut = pulseAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(0.9)
    fadeOut:SetSmoothing("IN_OUT")
    pulseAG:Play()

    glowFrame:Hide()
    macroIcon.glowFrame = glowFrame

    -- Show/hide glow with the macro icon
    macroIcon:HookScript("OnShow", function() glowFrame:Show(); pulseAG:Play() end)
    macroIcon:HookScript("OnHide", function() glowFrame:Hide(); pulseAG:Stop() end)

    frame.macroIcon = macroIcon
    
    -- Function to update the macro icon visibility and texture
    local function UpdateMacroIconInternal()
        if not frame or not trigger or not frame.macroWarning then return end
        local isChatAllowed = Triggers:IsChatAllowedForEvent(trigger.event)
        local hasChat = trigger.actions.chatMessage ~= nil
        local hasEmote = trigger.actions.emote ~= nil
        local hasSpell = trigger.conditions.spellID ~= nil

        if not isChatAllowed or trigger.event == "INTERRUPT_USED" then
            frame.macroWarning:Hide()
            frame.macroAttention:Hide()
            frame.macroIcon:Hide()
        elseif (hasChat or hasEmote) and hasSpell then
            frame.macroWarning:Show()
            frame.macroAttention:Show()
            frame.macroIcon:Show()
            local customIcon = Triggers:ResolveCustomMacroIcon(trigger.customMacroIcon)
            if customIcon then
                frame.macroIcon:SetNormalTexture(customIcon)
            else
                local spellInfo = C_Spell.GetSpellInfo(trigger.conditions.spellID)
                if spellInfo and spellInfo.iconID then
                    frame.macroIcon:SetNormalTexture(spellInfo.iconID)
                else
                    frame.macroIcon:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
            end
        else
            frame.macroWarning:Hide()
            frame.macroAttention:Hide()
            frame.macroIcon:Hide()
        end
    end
    
    local function RecalculateNaturalHeight()
        local rows = {
            soundLabel, animLabel, emoteLabel, chatLabel, toyLabel,
            successSoundLabel, successAnimLabel, failSoundLabel, failAnimLabel,
            startChatLabel, stopChatLabel,
            summonIncomingChatLabel, summonAcceptedChatLabel, summonDeclinedChatLabel,
        }
        local visibleCount = 0
        for _, label in ipairs(rows) do
            if label and label:IsShown() then visibleCount = visibleCount + 1 end
        end
        if cdAnimCheck and cdAnimCheck:IsShown() then visibleCount = visibleCount + 1 end
        if combatWarningLabel and combatWarningLabel:IsShown() then visibleCount = visibleCount + 1 end
        local height = visibleCount * 32 + 20
        if macroWarning and macroWarning:IsShown() then
            height = math.max(height, 150)
        end
        frame.naturalHeight = math.max(height, 90)
    end

    local function RepositionVisibleActions()
        local items = {
            {label = soundLabel, btn = soundButton, icon = soundIcon},
            {label = animLabel, btn = animButton, icon = animIcon},
            {label = nil, btn = combatWarningLabel},
            {label = emoteLabel, btn = emoteButton, icon = emoteIcon},
            {label = chatLabel, btn = chatButton, icon = chatIcon},
            {label = toyLabel, btn = toyButton, icon = toyIcon},
            {label = successSoundLabel, btn = successSoundButton},
            {label = successAnimLabel, btn = successAnimButton},
            {label = failSoundLabel, btn = failSoundButton},
            {label = failAnimLabel, btn = failAnimButton},
            {label = startChatLabel, btn = startChatButton},
            {label = stopChatLabel, btn = stopChatButton},
            {label = summonIncomingChatLabel, btn = summonIncomingChatButton},
            {label = summonAcceptedChatLabel, btn = summonAcceptedChatButton},
            {label = summonDeclinedChatLabel, btn = summonDeclinedChatButton},
            {label = nil, btn = cdAnimCheck},
        }
        local y = 0
        local spacing = 32
        
        -- Align buttons at a fixed x offset to make them tabular
        local buttonXOffset = 100
        
        for _, item in ipairs(items) do
            local visible = item.label and item.label:IsShown() or item.btn:IsShown()
            if visible then
                if item.icon then
                    item.icon:Show()
                    item.icon.border:Show()
                    item.icon:ClearAllPoints()
                    item.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, y)
                    item.label:ClearAllPoints()
                    item.label:SetPoint("LEFT", item.icon, "RIGHT", 8, 0)
                    item.btn:ClearAllPoints()
                    item.btn:SetPoint("LEFT", item.icon, "RIGHT", buttonXOffset, 0)
                elseif item.label then
                    item.label:ClearAllPoints()
                    item.label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
                    item.btn:ClearAllPoints()
                    item.btn:SetPoint("LEFT", item.label, "RIGHT", 10, 0)
                else
                    item.btn:ClearAllPoints()
                    item.btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
                end
                
                y = y - spacing
            else
                if item.icon then
                    item.icon:Hide()
                    item.icon.border:Hide()
                end
            end
        end
    end

    -- Conditional visibility for Chat and Emotes
    local function RefreshActionVisibility()
        local isChatAllowed = Triggers:IsChatAllowedForEvent(trigger.event)
        local isInterrupt = (trigger.event == "INTERRUPT_USED")
        local isFood = (trigger.event == "EAT_BUFF")
        local isSummon = (trigger.event == "SUMMON")

        if isInterrupt then
            -- Hide basic sound/animation for interrupt events
            soundLabel:Hide(); soundButton:Hide()
            animLabel:Hide(); animButton:Hide()
            -- Show interrupt-specific options
            if frame.cdAnimCheck then frame.cdAnimCheck:Show() end
            if frame.cdPosBtn then 
                frame.cdPosBtn:Show()
                local hasSpell = trigger.conditions and trigger.conditions.spellID and trigger.conditions.spellID ~= ""
                if hasSpell then
                    frame.cdPosBtn:Enable()
                    frame.cdPosBtn:SetAlpha(1)
                else
                    frame.cdPosBtn:Disable()
                    frame.cdPosBtn:SetAlpha(0.5)
                end
            end
            if frame.successSoundLabel then frame.successSoundLabel:Show(); frame.successSoundButton:Show() end
            if frame.successAnimLabel then frame.successAnimLabel:Show(); frame.successAnimButton:Show() end
            if frame.failSoundLabel then frame.failSoundLabel:Show(); frame.failSoundButton:Show() end
            if frame.failAnimLabel then frame.failAnimLabel:Show(); frame.failAnimButton:Show() end
            
            startChatLabel:Hide(); startChatButton:Hide()
            stopChatLabel:Hide(); stopChatButton:Hide()
            summonIncomingChatLabel:Hide(); summonIncomingChatButton:Hide()
            summonAcceptedChatLabel:Hide(); summonAcceptedChatButton:Hide()
            summonDeclinedChatLabel:Hide(); summonDeclinedChatButton:Hide()
            if frame.toyLabel then frame.toyLabel:Hide(); frame.toyButton:Hide() end

            -- Chat and Emote for interrupt
            if isChatAllowed then
                emoteLabel:Show(); emoteButton:Show()
                chatLabel:Show(); chatButton:Show()
                if frame.combatWarningLabel then frame.combatWarningLabel:Show() end
                UpdateMacroIconInternal()
            else
                emoteLabel:Hide(); emoteButton:Hide()
                chatLabel:Hide(); chatButton:Hide()
                if frame.combatWarningLabel then frame.combatWarningLabel:Hide() end
                frame.macroWarning:Hide()
                frame.macroAttention:Hide()
                frame.macroIcon:Hide()
            end
        elseif isFood then
            -- For EAT_BUFF: only Sound + Animation for now.
            -- TODO(beta): Emote and Chat disabled to avoid ADDON_ACTION_BLOCKED taint.
            -- Re-enable once a clean chat bridge addon is implemented.
            soundLabel:Show(); soundButton:Show()
            animLabel:Show(); animButton:Show()
            emoteLabel:Hide(); emoteButton:Hide()         -- disabled for beta
            
            chatLabel:Hide(); chatButton:Hide()
            startChatLabel:Hide(); startChatButton:Hide() -- disabled for beta
            stopChatLabel:Hide(); stopChatButton:Hide()   -- disabled for beta
            if frame.combatWarningLabel then frame.combatWarningLabel:Hide() end
            
            -- Hide interrupt-specific options
            if frame.cdAnimCheck then frame.cdAnimCheck:Hide() end
            if frame.cdPosBtn then frame.cdPosBtn:Hide() end
            if frame.successSoundLabel then frame.successSoundLabel:Hide(); frame.successSoundButton:Hide() end
            if frame.successAnimLabel then frame.successAnimLabel:Hide(); frame.successAnimButton:Hide() end
            if frame.failSoundLabel then frame.failSoundLabel:Hide(); frame.failSoundButton:Hide() end
            if frame.failAnimLabel then frame.failAnimLabel:Hide(); frame.failAnimButton:Hide() end
            summonIncomingChatLabel:Hide(); summonIncomingChatButton:Hide()
            summonAcceptedChatLabel:Hide(); summonAcceptedChatButton:Hide()
            summonDeclinedChatLabel:Hide(); summonDeclinedChatButton:Hide()
            frame.macroWarning:Hide(); frame.macroAttention:Hide(); frame.macroIcon:Hide()
            if frame.toyLabel then frame.toyLabel:Hide(); frame.toyButton:Hide() end
        elseif isSummon then
            soundLabel:Show(); soundButton:Show()
            animLabel:Show(); animButton:Show()
            emoteLabel:Hide(); emoteButton:Hide()
            chatLabel:Hide(); chatButton:Hide()
            if frame.combatWarningLabel then frame.combatWarningLabel:Hide() end
            startChatLabel:Hide(); startChatButton:Hide()
            stopChatLabel:Hide(); stopChatButton:Hide()
            summonIncomingChatLabel:Show(); summonIncomingChatButton:Show()
            summonAcceptedChatLabel:Show(); summonAcceptedChatButton:Show()
            summonDeclinedChatLabel:Show(); summonDeclinedChatButton:Show()
            if frame.cdAnimCheck then frame.cdAnimCheck:Hide() end
            if frame.cdPosBtn then frame.cdPosBtn:Hide() end
            if frame.successSoundLabel then frame.successSoundLabel:Hide(); frame.successSoundButton:Hide() end
            if frame.successAnimLabel then frame.successAnimLabel:Hide(); frame.successAnimButton:Hide() end
            if frame.failSoundLabel then frame.failSoundLabel:Hide(); frame.failSoundButton:Hide() end
            if frame.failAnimLabel then frame.failAnimLabel:Hide(); frame.failAnimButton:Hide() end
            frame.macroWarning:Hide(); frame.macroAttention:Hide(); frame.macroIcon:Hide()
            if frame.toyLabel then frame.toyLabel:Hide(); frame.toyButton:Hide() end
        else
            -- Show basic actions for other events
            soundLabel:Show(); soundButton:Show()
            animLabel:Show(); animButton:Show()
            
            startChatLabel:Hide(); startChatButton:Hide()
            stopChatLabel:Hide(); stopChatButton:Hide()
            summonIncomingChatLabel:Hide(); summonIncomingChatButton:Hide()
            summonAcceptedChatLabel:Hide(); summonAcceptedChatButton:Hide()
            summonDeclinedChatLabel:Hide(); summonDeclinedChatButton:Hide()

            -- Hide interrupt-specific options
            if frame.cdAnimCheck then frame.cdAnimCheck:Hide() end
            if frame.cdPosBtn then frame.cdPosBtn:Hide() end
            if frame.successSoundLabel then frame.successSoundLabel:Hide(); frame.successSoundButton:Hide() end
            if frame.successAnimLabel then frame.successAnimLabel:Hide(); frame.successAnimButton:Hide() end
            if frame.failSoundLabel then frame.failSoundLabel:Hide(); frame.failSoundButton:Hide() end
            if frame.failAnimLabel then frame.failAnimLabel:Hide(); frame.failAnimButton:Hide() end

            -- Toy picker: only shown for Spell Cast Success
            if trigger.event == "UNIT_SPELLCAST_SUCCEEDED" then
                if frame.toyLabel then frame.toyLabel:Show(); frame.toyButton:Show() end
            else
                if frame.toyLabel then frame.toyLabel:Hide(); frame.toyButton:Hide() end
            end

            -- Emote and Chat gated by IsChatAllowedForEvent
            if isChatAllowed then
                emoteLabel:Show(); emoteButton:Show()
                chatLabel:Show(); chatButton:Show()
                if frame.combatWarningLabel then frame.combatWarningLabel:Show() end
                UpdateMacroIconInternal()
            else
                emoteLabel:Hide(); emoteButton:Hide()
                chatLabel:Hide(); chatButton:Hide()
                if frame.combatWarningLabel then frame.combatWarningLabel:Hide() end
                frame.macroWarning:Hide()
                frame.macroAttention:Hide()
                frame.macroIcon:Hide()
            end
        end

        RepositionVisibleActions()
        RecalculateNaturalHeight()
        local card = frame:GetParent()
        if card and card.actionsLabel then
            Triggers:LayoutTriggerCard(card)
        end
    end

    RefreshActionVisibility()

    yOffset = yOffset - 28

    -- Whisper target checkbox
    local whisperCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    whisperCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    whisperCheck:SetSize(20, 20)
    whisperCheck:SetChecked(actions.whisperTarget or false)
    whisperCheck.text:SetText("Whisper target")
    whisperCheck.text:ClearAllPoints()
    whisperCheck.text:SetPoint("LEFT", whisperCheck, "RIGHT", 4, 0)
    whisperCheck:SetScript("OnClick", function(self)
        actions.whisperTarget = self:GetChecked()
    end)
    whisperCheck:Hide() -- Hidden for now per user request

    frame.RefreshActionVisibility = RefreshActionVisibility
    frame.UpdateMacroIconInternal = UpdateMacroIconInternal
    frame.UpdateChatButtonText = UpdateChatButtonText
    frame.UpdateSoundButton = UpdateSoundButton
    frame.UpdateAnimButton = UpdateAnimButton
    frame.UpdateEmoteButton = UpdateEmoteButton
    frame.UpdateSuccessSoundButton = UpdateSuccessSoundButton
    frame.UpdateSuccessAnimButton = UpdateSuccessAnimButton
    frame.UpdateFailSoundButton = UpdateFailSoundButton
    frame.UpdateFailAnimButton = UpdateFailAnimButton
    frame.UpdateStartChatButtonText = UpdateStartChatButtonText
    frame.UpdateStopChatButtonText = UpdateStopChatButtonText
    frame.UpdateSummonIncomingChatButtonText = UpdateSummonIncomingChatButtonText
    frame.UpdateSummonAcceptedChatButtonText = UpdateSummonAcceptedChatButtonText
    frame.UpdateSummonDeclinedChatButtonText = UpdateSummonDeclinedChatButtonText
    frame.UpdateToyButton = UpdateToyButton
end

