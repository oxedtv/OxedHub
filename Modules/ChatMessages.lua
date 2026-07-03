local addonName, OxedHub = ...

-- ChatMessages Module - Chat templates and message handling
local ChatMessages = {}
OxedHub.ChatMessages = ChatMessages

-- Local references
local SendChatMessage = SendChatMessage
local GetTime = GetTime
local UnitName = UnitName
local UnitGUID = UnitGUID

-- Chat cooldown
local lastChatTime = 0
local CHAT_COOLDOWN = 1.0

-- Initialize
function ChatMessages:Init()
    -- Nothing special needed
end

-- Show Chat UI
function ChatMessages:ShowUI(parent)
    -- Hide and cleanup existing scroll frame safely
    if self.currentScrollFrame then
        self.currentScrollFrame:Hide()
        self.currentScrollFrame:SetParent(nil)
        self.currentScrollFrame = nil
    end
    if self.currentScrollChild then
        self.currentScrollChild:Hide()
        self.currentScrollChild:SetParent(nil)
        self.currentScrollChild = nil
    end
    
    -- Clear parent completely - hide first, then remove
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({parent:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    title:SetText(L["CHAT_MSG_TITLE"] or "Chat Message Templates")
    
    -- Instructions
    local instructions = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    instructions:SetTextColor(0.86, 0.82, 0.72, 1)
    instructions:SetText(L["CHAT_MSG_DESC"] or "Create messages for reaction and toy macros. Spell-cast chat is controlled in Settings.")
    
    -- Add button
    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    addBtn:SetSize(120, 25)
    addBtn:SetText(L["CHAT_MSG_ADD_BTN"] or "Add Chat Text")
    addBtn:SetScript("OnClick", function()
        self:ShowAddChatDialog()
    end)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubChatScrollFrame" .. tostring(GetTime()), parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store references for cleanup
    self.currentScrollFrame = scrollFrame
    self.currentScrollChild = scrollChild
    
    self:RefreshChatList(scrollChild)
end

-- Refresh chat template list
function ChatMessages:RefreshChatList(parent)
    -- Clear existing
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -5
    local chats = OxedHub.db.profile.chatTemplates or {}
    local searchText = OxedHub.globalSearchText or ""
    local matchCount = 0
    
    for id, chat in pairs(chats) do
        local chatName = (chat.name or id):lower()
        if searchText == "" or string.find(chatName, searchText, 1, true) then
            local row = self:CreateChatRow(parent, id, chat)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, yOffset)
            yOffset = yOffset - 70
            matchCount = matchCount + 1
        end
    end
    
    if matchCount == 0 then
        local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("CENTER", parent, "CENTER", 0, 0)
        if next(chats) == nil then
            empty:SetText(L["CHAT_MSG_EMPTY"] or "No chat templates. Click 'Add Chat Text' to create one.")
        else
            empty:SetText(L["CHAT_MSG_NO_MATCH"] or "No chat templates match your search.")
        end
    end
    
    parent:SetHeight(math.abs(yOffset) + 50)
    
    -- Reset scroll position using stored reference
    if self.currentScrollFrame then
        self.currentScrollFrame:SetVerticalScroll(0)
        self.currentScrollFrame:UpdateScrollChildRect()
        -- Reset scrollbar thumb
        for _, child in ipairs({self.currentScrollFrame:GetChildren()}) do
            if child.SetValue and child.GetMinMaxValues then
                child:SetValue(0)
            end
        end
    end
end

-- Create chat row
function ChatMessages:CreateChatRow(parent, id, chat)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(65)
    
    row:SetBackdrop({
        bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 256,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    row:SetBackdropColor(0.035, 0.032, 0.028, 0.78)
    row:SetBackdropBorderColor(0.46, 0.37, 0.24, 0.75)

    local topLine = row:CreateTexture(nil, "BORDER")
    topLine:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -2)
    topLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -2)
    topLine:SetHeight(1)
    topLine:SetColorTexture(0.95, 0.74, 0.22, 0.22)

    local leftAccent = row:CreateTexture(nil, "BORDER")
    leftAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -5)
    leftAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 5)
    leftAccent:SetWidth(2)
    leftAccent:SetColorTexture(0.95, 0.74, 0.22, 0.45)

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -4)
    hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 4)
    hover:SetColorTexture(1, 0.82, 0, 0.10)
    
    -- Enable checkbox (no text, just the checkmark)
    local enableCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    enableCheck:SetPoint("LEFT", row, "LEFT", 12, 0)
    enableCheck:SetSize(24, 24)
    enableCheck:SetChecked(chat.enabled or false)
    enableCheck:SetScript("OnClick", function(self)
        chat.enabled = self:GetChecked()
    end)

    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 44, -8)
    nameText:SetWidth(150)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(chat.name or id)
    nameText:SetTextColor(1, 0.82, 0.12, 1)
    
    -- Channel badges
    local badgeColors = {
        SAY = {0.8, 0.8, 0.8},
        YELL = {1, 0.2, 0.2},
        PARTY = {0.62, 0.84, 1},
        GUILD = {0.25, 0.9, 0.25},
        OFFICER = {0.25, 0.75, 0.25},
        RAID = {1, 0.5, 0},
        INSTANCE_CHAT = {1, 0.5, 0.2},
        WHISPER = {1, 0.5, 1},
    }
    
    local selectedChannels = {}
    if chat.channels and next(chat.channels) then
        for chName, active in pairs(chat.channels) do
            if active then table.insert(selectedChannels, chName) end
        end
    else
        table.insert(selectedChannels, chat.channel or "SAY")
    end
    table.sort(selectedChannels)
    
    local lastBadge = nameText
    for bi, ch in ipairs(selectedChannels) do
        local channelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if bi == 1 then
            channelText:SetPoint("LEFT", lastBadge, "RIGHT", 10, 0)
        else
            channelText:SetPoint("LEFT", lastBadge, "RIGHT", 4, 0)
        end
        channelText:SetText("[" .. ch .. "]")
        local color = badgeColors[ch] or {0.62, 0.84, 1}
        channelText:SetTextColor(color[1], color[2], color[3], 1)
        lastBadge = channelText
    end
    
    -- Message text
    local msgText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
    msgText:SetPoint("RIGHT", row, "RIGHT", -80, 0)
    msgText:SetJustifyH("LEFT")
    msgText:SetText(chat.text or "")
    msgText:SetTextColor(0.86, 0.84, 0.78, 1)
    
    -- Edit button
    local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    editBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -8)
    editBtn:SetSize(60, 22)
    editBtn:SetText(L["SETTINGS_BTN_EDIT"] or "Edit")
    editBtn:SetScript("OnClick", function()
        self:ShowAddChatDialog(id)
    end)
    
    -- Delete button
    local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    delBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 8)
    delBtn:SetSize(60, 22)
    delBtn:SetText(L["SETTINGS_BTN_DELETE"] or "Delete")
    delBtn:SetScript("OnClick", function()
        self:DeleteChat(id)
    end)
    
    return row
end

-- Show add/edit chat dialog
function ChatMessages:ShowAddChatDialog(chatId)
    local chat = chatId and OxedHub.db.profile.chatTemplates[chatId]
    
    local dialog = CreateFrame("Frame", "OxedHubAddChatDialog", UIParent, "BasicFrameTemplate")
    dialog:SetSize(400, 350)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(200)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
    
    if dialog.TitleText then
        dialog.TitleText:SetText(chat and (L["CHAT_MSG_EDIT_TITLE"] or "Edit Chat Template") or (L["CHAT_MSG_ADD_TITLE"] or "Add Chat Template"))
    end
    if dialog.CloseButton then
        dialog.CloseButton:SetScript("OnClick", function()
            dialog:Hide()
            dialog:SetParent(nil)
        end)
    end
    
    -- Name input
    local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -50)
    nameLabel:SetText(L["CHAT_MSG_NAME_LBL"] or "Template Name:")
    
    local nameInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    nameInput:SetSize(200, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -5)
    nameInput:SetAutoFocus(true)
    if chat then nameInput:SetText(chat.name or "") end
    
    -- Message input
    local msgLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgLabel:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -15)
    msgLabel:SetText(L["CHAT_MSG_MSG_LBL"] or "Message:")
    
    -- Taller multi-line message box with a grey border backdrop
    local msgBackdrop = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
    msgBackdrop:SetSize(350, 60)
    msgBackdrop:SetPoint("TOPLEFT", msgLabel, "BOTTOMLEFT", 0, -5)
    msgBackdrop:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    msgBackdrop:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    msgBackdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
    
    local msgInput = CreateFrame("EditBox", nil, msgBackdrop)
    msgInput:SetMultiLine(true)
    msgInput:SetMaxLetters(255)
    msgInput:SetAutoFocus(false)
    msgInput:SetPoint("TOPLEFT", msgBackdrop, "TOPLEFT", 8, -6)
    msgInput:SetPoint("BOTTOMRIGHT", msgBackdrop, "BOTTOMRIGHT", -8, 6)
    msgInput:SetFontObject("GameFontHighlight")
    msgInput:SetTextInsets(0, 0, 0, 0)
    if chat then msgInput:SetText(chat.text or "") end
    
    -- Enable click-to-focus on backdrop
    msgBackdrop:SetScript("OnMouseDown", function()
        msgInput:SetFocus()
    end)
    
    -- Tab navigation between fields
    nameInput:SetScript("OnTabPressed", function()
        msgInput:SetFocus()
    end)
    msgInput:SetScript("OnTabPressed", function()
        nameInput:SetFocus()
    end)
    msgInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    
    -- Channels selection
    local channelLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("TOPLEFT", msgBackdrop, "BOTTOMLEFT", 0, -15)
    channelLabel:SetText(L["CHAT_MSG_CHANNELS_LBL"] or "Channels:")
    
    local radioButtons = {}
    local channelItems = OxedHub.CONFIG.CHAT_CHANNELS
    
    for i, ch in ipairs(channelItems) do
        local col = (i - 1) % 4
        local rowIdx = math.floor((i - 1) / 4)
        
        local rb = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
        rb:SetSize(16, 16)
        rb:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", col * 90 + 4, -7 - (rowIdx * 24))
        
        local isChecked = false
        if chat and chat.channel then
            isChecked = (chat.channel == ch)
        elseif chat and chat.channels then
            local foundActive = false
            for _, c in ipairs(channelItems) do
                if chat.channels[c] then
                    if c == ch then isChecked = true end
                    foundActive = true
                    break
                end
            end
            if not foundActive and ch == "SAY" then isChecked = true end
        else
            isChecked = (ch == "SAY")
        end
        rb:SetChecked(isChecked)
        rb.channelName = ch
        table.insert(radioButtons, rb)
        
        local text = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", rb, "RIGHT", 4, 0)
        local displayName = ch == "INSTANCE_CHAT" and "INSTANCE" or ch
        text:SetText(displayName)
        
        rb:SetScript("OnClick", function(self)
            for _, btn in ipairs(radioButtons) do
                btn:SetChecked(btn == self)
            end
        end)
    end
    
    -- Save button (natural dark-red WoW style)
    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 20)
    saveBtn:SetSize(100, 25)
    saveBtn:SetText(L["SETTINGS_BTN_SAVE"] or "Save")
    saveBtn:SetScript("OnClick", function()
        local name = nameInput:GetText()
        local msg = msgInput:GetText()
        if name ~= "" and msg ~= "" then
            local primaryChannel = "SAY"
            local newSelectedChannels = {}
            for _, rb in ipairs(radioButtons) do
                if rb:GetChecked() then
                    primaryChannel = rb.channelName
                    newSelectedChannels[rb.channelName] = true
                end
            end
            
            if chatId then
                -- Update existing
                local chatData = OxedHub.db.profile.chatTemplates[chatId]
                chatData.name = name
                chatData.text = msg
                chatData.channel = primaryChannel
                chatData.channels = newSelectedChannels
                
                -- Refresh UI
                if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
                    OxedHub.UI:ShowSubTab("Chat")
                end
            else
                -- Add new
                self:AddChat(name, msg, primaryChannel, newSelectedChannels)
            end
            dialog:Hide()
            dialog:SetParent(nil)
        end
    end)

    -- Cancel button (natural dark-red WoW style)
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetText(L["SETTINGS_BTN_CANCEL"] or "Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
        dialog:SetParent(nil)
    end)
end

-- Add chat template
function ChatMessages:AddChat(name, text, channel, channels)
    local id = OxedHub:GenerateID("chat")
    
    OxedHub.db.profile.chatTemplates[id] = {
        name = name,
        text = text,
        channel = channel or "SAY",
        channels = channels or { [channel or "SAY"] = true },
        enabled = true,
    }
    
    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Chat")
    end
end

-- Delete chat template
function ChatMessages:_PerformDeleteChat(id)
    OxedHub.db.profile.chatTemplates[id] = nil
    
    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Chat")
    end
end

function ChatMessages:DeleteChat(id)
    local chat = OxedHub.db.profile.chatTemplates[id]
    if not chat then return end

    -- Check if skip confirmation is enabled
    if OxedHub.db.profile.settings and OxedHub.db.profile.settings.skipDeleteConfirmation then
        self:_PerformDeleteChat(id)
        return
    end

    -- Show confirmation dialog
    local chatName = chat.name or tostring(id)
    StaticPopupDialogs["OXEDHUB_CONFIRM_DELETE_CHAT"] = {
        text = L["CHAT_MSG_CONFIRM_DELETE"] or "Are you sure you wish to delete the chat template '%s'?",
        button1 = L["SETTINGS_BTN_YES"] or "Yes",
        button2 = L["SETTINGS_BTN_NO"] or "No",
        OnAccept = function(dialogFrame, data)
            ChatMessages:_PerformDeleteChat(data)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_CONFIRM_DELETE_CHAT", chatName, nil, id)
end

-- Process macros in message
function ChatMessages:ProcessMacros(text, eventData)
    if not text then return "" end
    
    local result = text
    
    -- Use function replacements to avoid any issues with % characters in the replacement string
    local casterName = UnitName("player") or "Player"
    result = result:gsub("%%caster", function() return casterName end)
    
    if eventData then
        -- Process %spellid BEFORE %spell so that %spell doesn't partially match %spellid
        if eventData.spellID then
            local sid = tostring(eventData.spellID)
            result = result:gsub("%%spellid", function() return sid end)
        end
        
        -- %spell - spell name from event data
        if eventData.spellName then
            local sname = eventData.spellName
            result = result:gsub("%%spell", function() return sname end)
        end
        
        -- %target - target name from event data
        if eventData.targetName then
            local tname = eventData.targetName
            result = result:gsub("%%target", function() return tname end)
        end

        if eventData.summoner then
            local summoner = eventData.summoner
            result = result:gsub("%%summoner", function() return summoner end)
        end

        if eventData.areaName then
            local areaName = eventData.areaName
            result = result:gsub("%%area", function() return areaName end)
        end
    end
    
    -- Remove unprocessed macros
    result = result:gsub("%%target", "target")
    result = result:gsub("%%spellid", "0")
    result = result:gsub("%%spell", "spell")
    result = result:gsub("%%summoner", "summoner")
    result = result:gsub("%%area", "area")
    
    return result
end

-- Send chat message
function ChatMessages:Send(templateIdOrName, channel, eventData)
    local now = GetTime()
    if now - lastChatTime < CHAT_COOLDOWN then
        return -- On cooldown
    end
    lastChatTime = now
    
    local template = nil
    
    -- Look up by ID
    if OxedHub.db.profile.chatTemplates[templateIdOrName] then
        template = OxedHub.db.profile.chatTemplates[templateIdOrName]
    else
        -- Look up by name
        for id, data in pairs(OxedHub.db.profile.chatTemplates or {}) do
            if data.name == templateIdOrName then
                template = data
                break
            end
        end
    end
    
    if not template or not template.enabled then
        return
    end
    
    local msg = self:ProcessMacros(template.text, eventData)
    
    local targetChannels = {}
    if channel then
        table.insert(targetChannels, channel)
    elseif template.channels and next(template.channels) then
        for chName, active in pairs(template.channels) do
            if active then
                table.insert(targetChannels, chName)
            end
        end
    else
        table.insert(targetChannels, template.channel or "SAY")
    end
    
    for _, ch in ipairs(targetChannels) do
        -- Validate channel
        local validChannel = false
        for _, vc in ipairs(OxedHub.CONFIG.CHAT_CHANNELS) do
            if vc == ch then
                validChannel = true
                break
            end
        end
        
        if validChannel then
            -- Safety Check: Blizzard blocks ALL automated SendChatMessage during combat.
            -- pcall cannot catch ADDON_ACTION_BLOCKED taint errors, so we must bail out early.
            if InCombatLockdown() and not (eventData and eventData.isManual) then
                print("|cff00ff00[OxedHub-Combat]|r (" .. ch .. ") " .. msg)
            else
                -- Route through the clean, untainted dispatcher (loaded before libraries).
                -- This avoids the ADDON_ACTION_BLOCKED taint from AceDB/library code.
                OxedHub_DispatchChat(msg, ch)
            end
        end
    end
end
