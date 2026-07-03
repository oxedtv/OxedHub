local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

local function normalizeSearchText(text)
    if not text then return "" end
    return text:lower():gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
end

function Triggers:GetSoundOptions()
    local options = {}
    table.insert(options, { label = "None", value = nil })
    for name, data in pairs(OxedHub.db.profile.customSounds or {}) do
        table.insert(options, { label = data.name or name, value = name })
    end
    return options
end

function Triggers:GetFilteredSoundOptions(searchText)
    local options = self:GetSoundOptions()
    local filtered = {}
    local query = normalizeSearchText(searchText)

    for _, option in ipairs(options) do
        if option.value == nil or query == "" or string.find(normalizeSearchText(option.label), query, 1, true) then
            table.insert(filtered, option)
        end
    end
    return filtered
end

function Triggers:CreateSoundPickerRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(28)
    -- No background for every row as requested

    local useButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    useButton:SetSize(235, 22)
    useButton:SetPoint("LEFT", row, "LEFT", 4, 0)
    useButton:SetNormalFontObject("GameFontNormalSmall")

    local playButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    playButton:SetSize(48, 22)
    playButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    playButton:SetText("Play")

    useButton:SetScript("OnClick", function(self)
        if Triggers.currentTriggerForPicker then
            Triggers.currentTriggerForPicker.actions = Triggers.currentTriggerForPicker.actions or {}
            local key = Triggers.currentSoundActionType or "sound"
            Triggers.currentTriggerForPicker.actions[key] = self.optionValue
            if Triggers.soundPicker then
                Triggers.soundPicker:Hide()
            end
            Triggers:RefreshTriggersList()
        end
    end)

    playButton:SetScript("OnClick", function(self)
        if self.optionValue and OxedHub.Sounds then
            OxedHub.Sounds:Play(self.optionValue)
        end
    end)

    row.useButton = useButton
    row.playButton = playButton
    return row
end

function Triggers:RefreshPickerList(picker, actionType)
    if not picker then return end
    
    local query = normalizeSearchText(picker.searchInput:GetText())
    local options = {}
    local selectedValue = nil
    
    if self.currentTriggerForPicker and self.currentTriggerForPicker.actions then
        selectedValue = self.currentTriggerForPicker.actions[actionType]
    end

    -- Get options based on type (handle success/fail variants)
    local baseType = actionType
    if actionType == "sound" or actionType == "successSound" or actionType == "failSound" then 
        baseType = "sound" 
    elseif actionType == "animation" or actionType == "successAnimation" or actionType == "failAnimation" then 
        baseType = "animation" 
    elseif actionType == "chatMessage" or actionType == "startChatMessage" or actionType == "stopChatMessage"
        or actionType == "summonIncomingChatMessage" or actionType == "summonAcceptedChatMessage" or actionType == "summonDeclinedChatMessage" then 
        baseType = "chatMessage" 
    end
    
    if baseType == "sound" then
        local matchedOptions = self:GetFilteredSoundOptions(picker.searchInput:GetText())
        
        local noneOpt = nil
        local favorites = {}
        local customs = {}
        local others = {}

        for _, opt in ipairs(matchedOptions) do
            if opt.value == nil then
                noneOpt = opt
            else
                local sound = OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[opt.value]
                if sound then
                    if sound.isFavorite then
                        table.insert(favorites, opt)
                    end
                    if not sound.autoImported then
                        table.insert(customs, opt)
                    else
                        local cat = (sound.category and sound.category ~= "") and sound.category or "Other"
                        others[cat] = others[cat] or {}
                        table.insert(others[cat], opt)
                    end
                else
                    local cat = "Other"
                    others[cat] = others[cat] or {}
                    table.insert(others[cat], opt)
                end
            end
        end

        local function sortFunc(a, b)
            return (a.label or ""):lower() < (b.label or ""):lower()
        end
        table.sort(favorites, sortFunc)
        table.sort(customs, sortFunc)
        for cat, list in pairs(others) do
            table.sort(list, sortFunc)
        end

        if noneOpt then
            table.insert(options, noneOpt)
        end

        -- Collapsed state tracking on picker
        picker.collapsedCategories = picker.collapsedCategories or {}
        
        local function insertCategory(catName, list, defaultCollapsed)
            if #list > 0 then
                local isCollapsed = defaultCollapsed
                if picker.collapsedCategories[catName] ~= nil then
                    isCollapsed = picker.collapsedCategories[catName]
                end
                
                -- If searching, force expand
                if query ~= "" then
                    isCollapsed = false
                end
                
                -- Save current state
                picker.collapsedCategories[catName] = isCollapsed

                table.insert(options, {
                    isHeader = true,
                    label = (isCollapsed and "> " or "v ") .. catName .. " (" .. #list .. ")",
                    catName = catName,
                    isCollapsed = isCollapsed
                })

                if not isCollapsed then
                    for _, opt in ipairs(list) do
                        table.insert(options, opt)
                    end
                end
            end
        end

        insertCategory("Favorites", favorites, false)
        insertCategory("Custom Sounds", customs, false)

        local CATEGORY_ORDER = {
            "DH Pack",
            "Monk Pack",
            "Worrier Pack",
            "Death",
            "Effects",
            "Meme",
            "Legions",
            "Quote",
            "Anime",
            "Arabic",
            "Other"
        }

        for _, cat in ipairs(CATEGORY_ORDER) do
            if others[cat] then
                insertCategory(cat, others[cat], true)
                others[cat] = nil
            end
        end

        -- Any other categories not in CATEGORY_ORDER
        local remainingCats = {}
        for cat, _ in pairs(others) do
            table.insert(remainingCats, cat)
        end
        table.sort(remainingCats)
        for _, cat in ipairs(remainingCats) do
            insertCategory(cat, others[cat], true)
        end
    elseif baseType == "animation" then
        for id, data in pairs(OxedHub.db.profile.animations or {}) do
            local label = data.name or id
            if query == "" or string.find(normalizeSearchText(label), query, 1, true) then
                table.insert(options, { value = id, label = label, data = data })
            end
        end
        table.sort(options, function(a, b) return a.label < b.label end)
    elseif baseType == "emote" then
        for _, emote in ipairs(OxedHub.EMOTE_LIST or {}) do
            if query == "" or string.find(normalizeSearchText(emote), query, 1, true) then
                table.insert(options, { value = emote, label = emote })
            end
        end
    elseif baseType == "chatMessage" then
        for id, data in pairs(OxedHub.db.profile.chatTemplates or {}) do
            local label = data.name or id
            if query == "" or string.find(normalizeSearchText(label), query, 1, true) then
                table.insert(options, { value = id, label = label })
            end
        end
        table.sort(options, function(a, b) return a.label < b.label end)
    elseif baseType == "toy" then
        picker.collapsedCategories = picker.collapsedCategories or {}

        -- Toy Mixes category
        local mixes = {}
        for id, data in pairs(OxedHub.db.profile.toyMixes or {}) do
            local label = data.name or id
            if query == "" or string.find(normalizeSearchText(label), query, 1, true) then
                local icon1, icon2
                if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                    icon1, icon2 = OxedHub.Toys:GetMixSlotIcons(id)
                end
                table.insert(mixes, { value = id, label = label, isMix = true, mixIcon1 = icon1, mixIcon2 = icon2 })
            end
        end
        table.sort(mixes, function(a, b) return a.label < b.label end)

        local mixCollapsed = picker.collapsedCategories["Toy Mixes"]
        if mixCollapsed == nil then mixCollapsed = false end
        if query ~= "" then mixCollapsed = false end
        picker.collapsedCategories["Toy Mixes"] = mixCollapsed

        if #mixes > 0 then
            table.insert(options, {
                isHeader = true,
                label = (mixCollapsed and "> " or "v ") .. "Toy Mixes (" .. #mixes .. ")",
                catName = "Toy Mixes",
                isCollapsed = mixCollapsed,
            })
            if not mixCollapsed then
                for _, opt in ipairs(mixes) do
                    table.insert(options, opt)
                end
            end
        end

        -- Individual Owned Toys category
        local toys = {}
        local numToys = C_ToyBox.GetNumTotalDisplayedToys and C_ToyBox.GetNumTotalDisplayedToys() or 0
        for i = 1, numToys do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and PlayerHasToy(itemID) then
                local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
                if toyName and toyName ~= "" then
                    if query == "" or string.find(normalizeSearchText(toyName), query, 1, true) then
                        table.insert(toys, { value = "toyid:" .. itemID, label = toyName, itemID = itemID, toyIcon = toyIcon })
                    end
                end
            end
        end
        table.sort(toys, function(a, b) return a.label < b.label end)

        local toysCollapsed = picker.collapsedCategories["Owned Toys"]
        if toysCollapsed == nil then toysCollapsed = true end
        if query ~= "" then toysCollapsed = false end
        picker.collapsedCategories["Owned Toys"] = toysCollapsed

        if #toys > 0 then
            table.insert(options, {
                isHeader = true,
                label = (toysCollapsed and "> " or "v ") .. "Owned Toys (" .. #toys .. ")",
                catName = "Owned Toys",
                isCollapsed = toysCollapsed,
            })
            if not toysCollapsed then
                for _, opt in ipairs(toys) do
                    table.insert(options, opt)
                end
            end
        end
    end

    for index, option in ipairs(options) do
        local row = picker.rows[index]
        if not row then
            row = self:CreatePickerRow(picker, actionType)
            picker.rows[index] = row
        end
        row.actionType = actionType

        row:Show()
        row:SetPoint("TOPLEFT", picker.scrollChild, "TOPLEFT", 0, -((index - 1) * 30))
        row:SetPoint("TOPRIGHT", picker.scrollChild, "TOPRIGHT", -4, -((index - 1) * 30))

        -- Clean up any split icon from previous use of this row
        if row.splitIcon then row.splitIcon:Hide() end

        if option.isHeader then
            row.useButton:SetText(option.label)
            row.useButton:SetSize(330, 22)
            row.useButton:SetPoint("LEFT", row, "LEFT", 10, 0)
            row.useButton.optionValue = nil
            row.useButton.isHeader = true
            row.useButton.catName = option.catName
            row.useButton.actionType = actionType
            row.playButton:Hide()
            row.icon:Hide()
            row.useButton:SetNormalFontObject("GameFontNormal")
            
            row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
            row:SetBackdropColor(0.2, 0.2, 0.2, 0.4)
        else
            row.useButton:SetText(option.label)
            local hasPlay = (baseType == "sound" or baseType == "animation" or baseType == "emote" or baseType == "chatMessage") and option.value ~= nil
            if hasPlay then
                row.useButton:SetSize(280, 22)
                row.playButton:Show()
            else
                row.useButton:SetSize(310, 22)
                row.playButton:Hide()
            end
            
            local indent = 12
            if baseType == "sound" and option.value ~= nil then
                indent = 28
            end
            row.useButton:SetPoint("LEFT", row, "LEFT", indent, 0)
            row.useButton.optionValue = option.value
            row.useButton.actionType = actionType
            row.useButton.isHeader = false
            row.useButton.catName = nil
            row.playButton.optionValue = option.value
            row.playButton.actionType = actionType
            
            row.useButton:SetNormalFontObject("GameFontHighlightSmall")

            if baseType == "animation" and option.data and option.data.tgaPath then
                row.icon:Show()
                row.icon:SetTexture(option.data.tgaPath)
                local grid = math.ceil(math.sqrt(option.data.frameCount or 25))
                if grid < 1 then grid = 1 end
                local coord = 1 / grid
                row.icon:SetTexCoord(0, coord, 0, coord)
                row.useButton:SetPoint("LEFT", row, "LEFT", 36, 0)
            elseif baseType == "toy" and option.isMix and option.mixIcon1 then
                -- Split icon for toy mixes
                row.icon:Hide()
                if not row.splitIcon then
                    row.splitIcon = OxedHub.Toys:CreateSplitIcon(row, 22, option.mixIcon1, option.mixIcon2)
                end
                row.splitIcon.leftTexture:SetTexture(option.mixIcon1)
                row.splitIcon.leftTexture:SetTexCoord(0, 0.5, 0, 1)
                row.splitIcon.rightTexture:SetTexture(option.mixIcon2 or option.mixIcon1)
                row.splitIcon.rightTexture:SetTexCoord(0.5, 1, 0, 1)
                row.splitIcon:ClearAllPoints()
                row.splitIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.splitIcon:Show()
                row.useButton:SetPoint("LEFT", row, "LEFT", 30, 0)
            elseif baseType == "toy" and option.toyIcon then
                -- Single icon for individual toys
                row.icon:Show()
                row.icon:SetTexture(option.toyIcon)
                row.icon:SetTexCoord(0, 1, 0, 1)
                row.useButton:SetPoint("LEFT", row, "LEFT", 30, 0)
            else
                row.icon:Hide()
                row.icon:SetTexture(nil)
            end

            if option.value == selectedValue and selectedValue ~= nil then
                row:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
                row:SetBackdropColor(1, 0.84, 0, 0.15)
            else
                row:SetBackdrop(nil)
            end
        end
    end

    for index = #options + 1, #picker.rows do
        local row = picker.rows[index]
        row:Hide()
        row.actionType = actionType
        if row.useButton then row.useButton.actionType = actionType end
        if row.playButton then row.playButton.actionType = actionType end
    end

    if #options == 0 then
        if not picker.emptyText then
            picker.emptyText = picker.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            picker.emptyText:SetPoint("TOP", picker.scrollChild, "TOP", 0, -10)
        end
        picker.emptyText:SetText("No items match your search.")
        picker.emptyText:Show()
    elseif picker.emptyText then
        picker.emptyText:Hide()
    end

    picker.scrollChild:SetHeight(math.max(#options * 30, 1))
end

function Triggers:CreatePickerRow(picker, actionType)
    local row = CreateFrame("Frame", nil, picker.scrollChild, "BackdropTemplate")
    row:SetHeight(28)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:Hide()
    row.icon = icon

    local useButton = CreateFrame("Button", nil, row)
    useButton:SetHeight(22)
    useButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    useButton:SetText("")
    local fs = useButton:GetFontString()
    if fs then
        fs:SetJustifyH("LEFT")
    end

    local playButton = CreateFrame("Button", nil, row)
    playButton:SetSize(18, 18)
    playButton:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    
    local playIcon = playButton:CreateTexture(nil, "ARTWORK")
    playIcon:SetAllPoints()
    playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    playIcon:SetVertexColor(0.9, 0.1, 0.1)
    playButton.icon = playIcon

    playButton:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 0.3, 0.3)
    end)
    playButton:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.9, 0.1, 0.1)
    end)

    useButton:SetScript("OnClick", function(self)
        local parentRow = self:GetParent()
        local at = self.actionType or parentRow.actionType
        if self.isHeader then
            picker.collapsedCategories = picker.collapsedCategories or {}
            picker.collapsedCategories[self.catName] = not picker.collapsedCategories[self.catName]
            Triggers:RefreshPickerList(picker, at)
            return
        end

        if Triggers.currentTriggerForPicker then
            Triggers.currentTriggerForPicker.actions = Triggers.currentTriggerForPicker.actions or {}
            Triggers.currentTriggerForPicker.actions[at] = self.optionValue
            -- If emote, chat, or toy changed, rewrite the existing macro so it stays in sync
            if (at == "toy" or at == "emote" or at == "chatMessage" or at == "startChatMessage" or at == "stopChatMessage"
                or at == "summonIncomingChatMessage" or at == "summonAcceptedChatMessage" or at == "summonDeclinedChatMessage") and Triggers.currentTriggerForPicker.id then
                local t = Triggers.currentTriggerForPicker
                local macroName = Triggers:GetTriggerMacroName(t)
                local index = GetMacroIndexByName(macroName)
                if index > 0 then
                    Triggers:CreateMacroForTrigger(t)
                end
            end
            picker:Hide()
            Triggers:RefreshTriggersList()
        end
    end)

    playButton:SetScript("OnClick", function(self)
        if not self.optionValue then return end
        local at = self.actionType or self:GetParent().actionType
        local baseType = at
        if at == "sound" or at == "successSound" or at == "failSound" then 
            baseType = "sound" 
        elseif at == "animation" then 
            baseType = "animation" 
        elseif at == "chatMessage" or at == "startChatMessage" or at == "stopChatMessage"
            or at == "summonIncomingChatMessage" or at == "summonAcceptedChatMessage" or at == "summonDeclinedChatMessage" then 
            baseType = "chatMessage" 
        end
        if baseType == "sound" and OxedHub.Sounds then
            OxedHub.Sounds:Play(self.optionValue)
        elseif baseType == "animation" and OxedHub.Animations then
            OxedHub.Animations:Play(self.optionValue)
        elseif baseType == "emote" then
            DoEmote(self.optionValue)
        elseif baseType == "chatMessage" and OxedHub.ChatMessages then
            OxedHub.ChatMessages:Send(self.optionValue)
        end
    end)

    row.useButton = useButton
    row.playButton = playButton
    return row
end

function Triggers:CreateGenericPicker(name, titleText, actionType)
    local picker = CreateFrame("Frame", "OxedHubPicker_" .. name, UIParent, "BasicFrameTemplate")
    picker:SetSize(420, 460)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:Hide()
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)

    if picker.TitleText then
        picker.TitleText:SetText(titleText)
    end
    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function() picker:Hide() end)
    end

    local searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -65)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    searchInput:SetSize(210, 22)
    searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -6)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function()
        self:RefreshPickerList(picker, picker.currentActionType or actionType)
    end)

    local clearSearch = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    clearSearch:SetSize(60, 22)
    clearSearch:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
    clearSearch:SetText(L["PICKER_CLEAR"] or "Clear")
    clearSearch:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(350)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local closeButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 24)
    closeButton:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -18, 16)
    closeButton:SetText(L["BTN_CLOSE"] or "Close")
    closeButton:SetScript("OnClick", function() picker:Hide() end)

    local noneButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    noneButton:SetSize(80, 24)
    noneButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    noneButton:SetText(L["PICKER_USE_NONE"] or "Use None")
    noneButton:SetScript("OnClick", function()
        if self.currentTriggerForPicker then
            local at = picker.currentActionType
            self.currentTriggerForPicker.actions[at] = nil
            -- If emote or chat cleared, rewrite the existing macro so it stays in sync
            if (at == "emote" or at == "chatMessage" or at == "startChatMessage" or at == "stopChatMessage"
                or at == "summonIncomingChatMessage" or at == "summonAcceptedChatMessage" or at == "summonDeclinedChatMessage") and self.currentTriggerForPicker.id then
                local t = self.currentTriggerForPicker
                local macroName = self:GetTriggerMacroName(t)
                local index = GetMacroIndexByName(macroName)
                if index > 0 then
                    self:CreateMacroForTrigger(t)
                end
            end
            self:RefreshTriggersList()
        end
        picker:Hide()
    end)

    picker.searchInput = searchInput
    picker.scrollFrame = scrollFrame
    picker.scrollChild = scrollChild
    picker.rows = {}
    return picker
end

function Triggers:CreateSoundPicker()
    if self.soundPicker then return self.soundPicker end

    local picker = CreateFrame("Frame", "OxedHubTriggersSoundPicker", UIParent, "BasicFrameTemplate")
    picker:SetSize(420, 460)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:Hide()
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)

    if picker.TitleText then
        picker.TitleText:SetText(L["TITLE_PICK_SOUND"] or "Pick Sound")
    end
    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function() picker:Hide() end)
    end

    local subtitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -48)
    subtitle:SetWidth(380)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L["DESC_SOUND_PICKER"] or "Search your custom sounds, preview them, then click Use.")
    subtitle:SetTextColor(0.8, 0.8, 0.8, 1)

    local searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -14)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    searchInput:SetSize(210, 22)
    searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -6)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function() self:RefreshSoundPickerList() end)

    local clearSearch = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    clearSearch:SetSize(60, 22)
    clearSearch:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
    clearSearch:SetText(L["PICKER_CLEAR"] or "Clear")
    clearSearch:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(350)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local closeButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    closeButton:SetSize(80, 24)
    closeButton:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -18, 16)
    closeButton:SetText(L["BTN_CLOSE"] or "Close")
    closeButton:SetScript("OnClick", function() picker:Hide() end)

    local noneButton = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    noneButton:SetSize(80, 24)
    noneButton:SetPoint("RIGHT", closeButton, "LEFT", -10, 0)
    noneButton:SetText(L["PICKER_USE_NONE"] or "Use None")
    noneButton:SetScript("OnClick", function()
        if self.currentTriggerForPicker then
            self.currentTriggerForPicker.actions.sound = nil
            self:RefreshTriggerCard(self.currentTriggerForPicker.id)
        end
        picker:Hide()
    end)

    picker.searchInput = searchInput
    picker.scrollFrame = scrollFrame
    picker.scrollChild = scrollChild
    picker.rows = {}
    self.soundPicker = picker
    return picker
end

function Triggers:HideAllPickers()
    if self.soundPicker then self.soundPicker:Hide() end
    if self.animationPicker then self.animationPicker:Hide() end
    if self.emotePicker then self.emotePicker:Hide() end
    if self.chatPicker then self.chatPicker:Hide() end
    if self.toyPicker then self.toyPicker:Hide() end
end

function Triggers:ShowSoundPicker(trigger, actionType)
    self:HideAllPickers()
    self.currentTriggerForPicker = trigger
    self.currentSoundActionType = actionType or "sound"
    if not self.soundPicker then
        self.soundPicker = self:CreateGenericPicker("Sound", L["TITLE_PICK_SOUND"] or "Pick Sound", self.currentSoundActionType)
    end
    self.soundPicker.currentActionType = self.currentSoundActionType
    self.soundPicker.searchInput:SetText("")
    self.soundPicker:Show()
    self:RefreshPickerList(self.soundPicker, self.currentSoundActionType)
end

function Triggers:ShowAnimationPicker(trigger, actionType)
    self:HideAllPickers()
    self.currentTriggerForPicker = trigger
    self.currentAnimActionType = actionType or "animation"
    if not self.animationPicker then
        self.animationPicker = self:CreateGenericPicker("Animation", L["TITLE_PICK_ANIMATION"] or "Pick Animation", self.currentAnimActionType)
    end
    self.animationPicker.currentActionType = self.currentAnimActionType
    self.animationPicker.searchInput:SetText("")
    self.animationPicker:Show()
    self:RefreshPickerList(self.animationPicker, self.currentAnimActionType)
end

function Triggers:ShowEmotePicker(trigger)
    self:HideAllPickers()
    self.currentTriggerForPicker = trigger
    if not self.emotePicker then
        self.emotePicker = self:CreateGenericPicker("Emote", L["TITLE_PICK_EMOTE"] or "Pick Emote", "emote")
    end
    self.emotePicker.currentActionType = "emote"
    self.emotePicker.searchInput:SetText("")
    self.emotePicker:Show()
    self:RefreshPickerList(self.emotePicker, "emote")
end

function Triggers:ShowChatPicker(trigger, actionType)
    actionType = actionType or "chatMessage"
    self:HideAllPickers()
    self.currentTriggerForPicker = trigger
    if not self.chatPicker then
        self.chatPicker = self:CreateGenericPicker("Chat", L["TITLE_PICK_CHAT"] or "Pick Chat Template", actionType)
    end
    self.chatPicker.currentActionType = actionType
    self.chatPicker.searchInput:SetText("")
    self.chatPicker:Show()
    self:RefreshPickerList(self.chatPicker, actionType)
end

function Triggers:ShowToyPicker(trigger)
    self:HideAllPickers()
    self.currentTriggerForPicker = trigger
    if not self.toyPicker then
        self.toyPicker = self:CreateGenericPicker("Toy", L["TITLE_PICK_TOY"] or "Pick Toy", "toy")
    end
    self.toyPicker.currentActionType = "toy"
    self.toyPicker.searchInput:SetText("")
    self.toyPicker:Show()
    self:RefreshPickerList(self.toyPicker, "toy")
end


function Triggers:ScrollToTrigger(triggerId)
    self:OpenTriggerDetails(triggerId)
end

function Triggers:GetTrigger(id)
    return OxedHub.db.profile.triggers[id]
end

