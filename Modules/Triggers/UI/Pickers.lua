local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

local function normalizeSearchText(text)
    if not text then return "" end
    return text:lower():gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
end

-- =========================================================================
-- Live Animated Hover Preview for Animations
-- =========================================================================
function Triggers:GetOrCreateAnimationHoverPreview()
    if self.animHoverPreview then return self.animHoverPreview end

    local frame = CreateFrame("Frame", "OxedHubAnimHoverPreview", UIParent, "BackdropTemplate")
    frame:SetSize(180, 215)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(260)
    frame:SetClampedToScreen(true)

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    frame:SetBackdropColor(0.06, 0.06, 0.09, 0.96)
    frame:SetBackdropBorderColor(1, 0.82, 0, 0.90)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -10)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -10)
    title:SetJustifyH("CENTER")
    title:SetTextColor(1, 0.85, 0.2)
    frame.title = title

    local previewBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBox:SetSize(140, 140)
    previewBox:SetPoint("TOP", title, "BOTTOM", 0, -6)
    previewBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    previewBox:SetBackdropColor(0.02, 0.02, 0.03, 0.9)
    previewBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    frame.previewBox = previewBox

    local animTex = previewBox:CreateTexture(nil, "ARTWORK")
    animTex:SetPoint("TOPLEFT", previewBox, "TOPLEFT", 2, -2)
    animTex:SetPoint("BOTTOMRIGHT", previewBox, "BOTTOMRIGHT", -2, 2)
    frame.animTex = animTex

    local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOP", previewBox, "BOTTOM", 0, -6)
    info:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6)
    info:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
    info:SetJustifyH("CENTER")
    info:SetTextColor(0.8, 0.8, 0.8)
    frame.info = info

    function frame:ShowStep(s)
        local frameNum = s
        if self.seq and #self.seq > 0 then
            frameNum = self.seq[s + 1] or s
        end
        local cCount = self.cols or 1
        local rCount = self.rows or 1
        local r = math.floor(frameNum / cCount)
        local c = frameNum % cCount
        self.animTex:SetTexCoord(c / cCount, (c + 1) / cCount, r / rCount, (r + 1) / rCount)
    end

    frame:SetScript("OnUpdate", function(self, dt)
        if not self.isPlaying or not self.animData then return end
        self.elapsed = (self.elapsed or 0) + dt
        local dur = self.frameDuration or (1 / 24)
        if self.elapsed >= dur then
            local advance = math.floor(self.elapsed / dur)
            self.elapsed = self.elapsed % dur
            self.currentStep = ((self.currentStep or 0) + advance) % (self.maxFrames or 1)
            self:ShowStep(self.currentStep)
        end
    end)

    self.animHoverPreview = frame
    return frame
end

function Triggers:ShowAnimationHoverPreview(anchorFrame, animId, animData)
    if self.animHideTimer then
        self.animHideTimer:Cancel()
        self.animHideTimer = nil
    end

    if not animId then return end
    if not animData then
        animData = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.animations and OxedHub.db.profile.animations[animId]
    end
    if not animData or not animData.tgaPath or animData.tgaPath == "" then
        return
    end

    local preview = self:GetOrCreateAnimationHoverPreview()

    -- Avoid flickering if already showing this exact animation
    if preview.currentAnimId == animId and preview:IsShown() then
        return
    end
    preview.currentAnimId = animId

    preview.title:SetText(animData.name or animId)

    local cols = animData.columns or math.ceil(math.sqrt(animData.frameCount or 1))
    local rows = animData.rows or cols
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end
    local seq = animData.playSequence
    local maxFrames = (seq and #seq > 0) and #seq or (animData.frameCount or (cols * rows))
    if maxFrames < 1 then maxFrames = 1 end
    local fps = tonumber(animData.fps) or 24
    if fps < 1 then fps = 24 end

    -- Dynamic Box sizing based on real Aspect Ratio
    local aspect = animData.aspectRatio or "1:1"
    local boxW = 170
    local boxH = 170

    if aspect == "9:16" or aspect == "9/16" then
        boxH = 210
        boxW = math.floor(210 * 9 / 16 + 0.5)
    elseif aspect == "16:9" or aspect == "16/9" then
        boxW = 210
        boxH = math.floor(210 * 9 / 16 + 0.5)
    elseif aspect == "4:3" or aspect == "4/3" then
        boxW = 195
        boxH = math.floor(195 * 3 / 4 + 0.5)
    elseif aspect == "3:4" or aspect == "3/4" then
        boxH = 195
        boxW = math.floor(195 * 3 / 4 + 0.5)
    elseif animData.width and animData.height and animData.width > 0 and animData.height > 0 then
        local ratio = animData.width / animData.height
        if ratio > 1 then
            boxW = 195
            boxH = math.max(60, math.floor(195 / ratio + 0.5))
        else
            boxH = 195
            boxW = math.max(60, math.floor(195 * ratio + 0.5))
        end
    end

    preview.previewBox:SetSize(boxW, boxH)
    preview:SetWidth(math.max(215, boxW + 40))
    preview:SetHeight(boxH + 82)

    preview.info:SetText(string.format("%d FPS • %d frames • %s", fps, maxFrames, aspect))
    preview.animTex:SetTexture(animData.tgaPath)

    preview.animData = animData
    preview.cols = cols
    preview.rows = rows
    preview.seq = seq
    preview.maxFrames = maxFrames
    preview.fps = fps
    preview.frameDuration = 1 / fps
    preview.elapsed = 0
    preview.currentStep = 0
    preview.isPlaying = true
    preview:ShowStep(0)

    preview:ClearAllPoints()
    if anchorFrame and anchorFrame:IsShown() then
        preview:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 6, 0)
    else
        preview:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    end
    preview:Show()
end

function Triggers:StopAnimationHoverTicker()
    if self.animHoverPreview then
        self.animHoverPreview.isPlaying = false
        self.animHoverPreview.animData = nil
    end
end

function Triggers:HideAnimationHoverPreview(force)
    if not force then
        if self.animHideTimer then
            self.animHideTimer:Cancel()
        end
        self.animHideTimer = C_Timer.After(0.3, function()
            Triggers:HideAnimationHoverPreview(true)
        end)
        return
    end

    if self.animHideTimer then
        self.animHideTimer:Cancel()
        self.animHideTimer = nil
    end

    self:StopAnimationHoverTicker()
    if self.animHoverPreview then
        self.animHoverPreview.currentAnimId = nil
        self.animHoverPreview:Hide()
    end
end

-- =========================================================================
-- Sound Options
-- =========================================================================
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
    if type(actionType) ~= "string" then
        actionType = "sound"
    end
    local baseType = actionType
    if actionType:match("Sound$") or actionType == "sound" then 
        baseType = "sound" 
    elseif actionType:match("Animation$") or actionType:match("Anim$") or actionType == "animation" then 
        baseType = "animation" 
    elseif actionType:match("Emote$") or actionType == "emote" then
        baseType = "emote"
    elseif actionType:match("ChatMessage$") or actionType:match("Chat$") or actionType == "chatMessage" then 
        baseType = "chatMessage" 
    elseif actionType:match("Toy$") or actionType == "toy" then
        baseType = "toy"
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
        local filter = picker.selectedCategory or "all"
        for id, data in pairs(OxedHub.db.profile.animations or {}) do
            local label = data.name or id
            local passesSearch = (query == "" or string.find(normalizeSearchText(label), query, 1, true))
            local passesFilter = true
            if filter ~= "all" then
                local cat = OxedHub.Animations and OxedHub.Animations:GetAnimationCategory(id, data) or "users"
                if filter == "oxed" then
                    passesFilter = (cat == "oxed" or cat == "male" or cat == "female")
                else
                    passesFilter = (cat == filter)
                end
            end
            if passesSearch and passesFilter then
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
        -- Individual Owned Toys directly
        local numToys = C_ToyBox.GetNumTotalDisplayedToys and C_ToyBox.GetNumTotalDisplayedToys() or 0
        for i = 1, numToys do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and PlayerHasToy(itemID) then
                local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
                if toyName and toyName ~= "" then
                    if query == "" or string.find(normalizeSearchText(toyName), query, 1, true) then
                        table.insert(options, { value = "toyid:" .. itemID, label = toyName, itemID = itemID, toyIcon = toyIcon })
                    end
                end
            end
        end
        table.sort(options, function(a, b) return a.label < b.label end)
    end

    local ROW_HEIGHT = 20

    for index, option in ipairs(options) do
        local row = picker.rows[index]
        if not row then
            row = self:CreatePickerRow(picker, actionType)
            picker.rows[index] = row
        end
        row.actionType = actionType
        row.optionData = option.data
        row.optionValue = option.value

        row:Show()
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", picker.scrollChild, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", picker.scrollChild, "TOPRIGHT", 0, -((index - 1) * ROW_HEIGHT))

        -- Clean up any split icon from previous use of this row
        if row.splitIcon then row.splitIcon:Hide() end

        if option.isHeader then
            row.useButton:ClearAllPoints()
            row.useButton:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.useButton:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row.useButton:SetText(option.label)
            row.useButton.optionValue = nil
            row.useButton.optionData = nil
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
            row.useButton:ClearAllPoints()
            
            if baseType == "animation" then
                row.playButton:Hide()
                local indent = (option.data and option.data.tgaPath) and 24 or 8
                row.useButton:SetPoint("LEFT", row, "LEFT", indent, 0)
                row.useButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            else
                local hasPlay = (baseType == "sound" or baseType == "emote" or baseType == "chatMessage") and option.value ~= nil
                if hasPlay then
                    row.playButton:Show()
                    local indent = (baseType == "sound" and option.value ~= nil) and 24 or 8
                    row.useButton:SetPoint("LEFT", row, "LEFT", indent, 0)
                    row.useButton:SetPoint("RIGHT", row.playButton, "LEFT", -4, 0)
                else
                    row.playButton:Hide()
                    local indent = 8
                    if baseType == "toy" and (option.isMix or option.toyIcon) then
                        indent = 24
                    end
                    row.useButton:SetPoint("LEFT", row, "LEFT", indent, 0)
                    row.useButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                end
            end
            
            row.useButton.optionValue = option.value
            row.useButton.optionData = option.data
            row.useButton.actionType = actionType
            row.useButton.itemID = option.itemID
            row.useButton.isHeader = false
            row.useButton.catName = nil
            row.playButton.optionValue = option.value
            row.playButton.optionData = option.data
            row.playButton.actionType = actionType
            
            row.useButton:SetNormalFontObject("GameFontHighlightSmall")

            if baseType == "animation" and option.data and option.data.tgaPath then
                row.icon:Show()
                row.icon:SetSize(16, 16)
                row.icon:SetTexture(option.data.tgaPath)
                local cols = option.data.columns or math.ceil(math.sqrt(option.data.frameCount or 1))
                local rows = option.data.rows or cols
                if cols < 1 then cols = 1 end
                if rows < 1 then rows = 1 end
                row.icon:SetTexCoord(0, 1 / cols, 0, 1 / rows)
            elseif baseType == "toy" and option.isMix then
                if option.customIcon then
                    row.icon:Show()
                    row.icon:SetSize(16, 16)
                    row.icon:SetTexture(option.customIcon)
                    row.icon:SetTexCoord(0, 1, 0, 1)
                    row.useButton:SetPoint("LEFT", row, "LEFT", 24, 0)
                elseif option.mixIcon1 then
                    -- Split icon for toy mixes
                    row.icon:Hide()
                    if not row.splitIcon then
                        row.splitIcon = OxedHub.Toys:CreateSplitIcon(row, 18, option.mixIcon1, option.mixIcon2)
                    end
                    row.splitIcon.leftTexture:SetTexture(option.mixIcon1)
                    row.splitIcon.leftTexture:SetTexCoord(0, 0.5, 0, 1)
                    row.splitIcon.rightTexture:SetTexture(option.mixIcon2 or option.mixIcon1)
                    row.splitIcon.rightTexture:SetTexCoord(0.5, 1, 0, 1)
                    row.splitIcon:ClearAllPoints()
                    row.splitIcon:SetPoint("LEFT", row, "LEFT", 4, 0)
                    row.splitIcon:Show()
                    row.useButton:SetPoint("LEFT", row, "LEFT", 24, 0)
                end
            elseif baseType == "toy" and option.toyIcon then
                -- Single icon for individual toys
                row.icon:Show()
                row.icon:SetSize(16, 16)
                row.icon:SetTexture(option.toyIcon)
                row.icon:SetTexCoord(0, 1, 0, 1)
                row.useButton:SetPoint("LEFT", row, "LEFT", 24, 0)
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
        row.optionData = nil
        row.optionValue = nil
        if row.useButton then
            row.useButton.actionType = actionType
            row.useButton.optionData = nil
            row.useButton.optionValue = nil
        end
        if row.playButton then
            row.playButton.actionType = actionType
            row.playButton.optionData = nil
            row.playButton.optionValue = nil
        end
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

    picker.scrollChild:SetHeight(math.max(#options * ROW_HEIGHT, 1))
end

function Triggers:CreatePickerRow(picker, actionType)
    local row = CreateFrame("Frame", nil, picker.scrollChild, "BackdropTemplate")
    row:SetHeight(20)
    row:EnableMouse(true)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:Hide()
    row.icon = icon

    local useButton = CreateFrame("Button", nil, row)
    useButton:SetHeight(20)
    useButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    useButton:SetText("")
    local fs = useButton:GetFontString()
    if fs then
        fs:SetJustifyH("LEFT")
    end

    useButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    useButton:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetToyByItemID then
                GameTooltip:SetToyByItemID(self.itemID)
            else
                GameTooltip:SetItemByID(self.itemID)
            end
            GameTooltip:AddLine("|cff00ccffRight-Click: Copy Wowhead URL|r")
            GameTooltip:Show()
        elseif self.actionType and (self.actionType:match("Animation$") or self.actionType:match("Anim$") or self.actionType == "animation") and self.optionValue then
            Triggers:ShowAnimationHoverPreview(picker, self.optionValue, self.optionData)
        end
    end)
    useButton:SetScript("OnLeave", function(self)
        if self.itemID then
            GameTooltip:Hide()
        end
        Triggers:HideAnimationHoverPreview()
    end)

    local playButton = CreateFrame("Button", nil, row)
    playButton:SetSize(16, 16)
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

    useButton:SetScript("OnClick", function(self, button)
        if button == "RightButton" and self.itemID then
            local _, toyName = C_ToyBox.GetToyInfo(self.itemID)
            OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.itemID), toyName or ("Toy #" .. self.itemID))
            return
        end
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
        if at:match("Sound$") or at == "sound" then 
            baseType = "sound" 
        elseif at:match("Animation$") or at:match("Anim$") or at == "animation" then 
            baseType = "animation" 
        elseif at:match("Emote$") or at == "emote" then
            baseType = "emote"
        elseif at:match("ChatMessage$") or at:match("Chat$") or at == "chatMessage" then 
            baseType = "chatMessage" 
        elseif at:match("Toy$") or at == "toy" then
            baseType = "toy"
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
    picker:SetSize(440, 480)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:Hide()
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker:SetScript("OnHide", function()
        Triggers:HideAnimationHoverPreview(true)
    end)

    if picker.TitleText then
        picker.TitleText:SetText(titleText)
    end
    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function() picker:Hide() end)
    end

    local searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -42)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    local clearSearch = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")

    if name == "Animation" then
        searchInput:SetSize(150, 22)
        searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -4)

        clearSearch:SetSize(48, 22)
        clearSearch:SetPoint("LEFT", searchInput, "RIGHT", 4, 0)
        clearSearch:SetText(L["PICKER_CLEAR"] or "Clear")
        clearSearch:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

        local categoryDropdown = CreateFrame("DropdownButton", nil, picker, "WowStyle1DropdownTemplate")
        categoryDropdown:SetSize(160, 22)
        categoryDropdown:SetPoint("LEFT", clearSearch, "RIGHT", 6, 0)

        local filterOptions = {
            { key = "all",   name = L["ANIM_FILTER_ALL"] or "Show All" },
            { key = "oxed",  name = L["ANIM_FILTER_GEN"] or "General" },
            { key = "male",  name = L["ANIM_FILTER_MALE"] or "Male" },
            { key = "female",name = L["ANIM_FILTER_FEMALE"] or "Female" },
        }
        if type(_G["OxedHubMemePack"]) == "table" or type(_G["OxedHubTikTokPack"]) == "table" then
            table.insert(filterOptions, { key = "meme", name = L["ANIM_FILTER_MEME"] or "Meme Pack" })
        end
        table.insert(filterOptions, { key = "users", name = L["ANIM_FILTER_USERS"] or "Users" })

        picker.selectedCategory = "all"
        categoryDropdown:OverrideText(L["ANIM_FILTER_ALL"] or "Show All")

        categoryDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, opt in ipairs(filterOptions) do
                rootDescription:CreateRadio(
                    opt.name,
                    function() return (picker.selectedCategory or "all") == opt.key end,
                    function()
                        picker.selectedCategory = opt.key
                        categoryDropdown:OverrideText(opt.name)
                        self:RefreshPickerList(picker, picker.currentActionType or actionType)
                    end,
                    opt.key
                )
            end
        end)
        picker.categoryDropdown = categoryDropdown
    else
        searchInput:SetSize(210, 22)
        searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -4)

        clearSearch:SetSize(60, 22)
        clearSearch:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
        clearSearch:SetText(L["PICKER_CLEAR"] or "Clear")
        clearSearch:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)
    end

    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function()
        self:RefreshPickerList(picker, picker.currentActionType or actionType)
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(370)
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
    picker:SetSize(440, 480)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:Hide()
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker:SetScript("OnHide", function()
        Triggers:HideAnimationHoverPreview(true)
    end)

    if picker.TitleText then
        picker.TitleText:SetText(L["TITLE_PICK_SOUND"] or "Pick Sound")
    end
    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function() picker:Hide() end)
    end

    local subtitle = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -42)
    subtitle:SetWidth(380)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(L["DESC_SOUND_PICKER"] or "Search your custom sounds, preview them, then click Use.")
    subtitle:SetTextColor(0.8, 0.8, 0.8, 1)

    local searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -8)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    searchInput:SetSize(210, 22)
    searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -4)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function() self:RefreshSoundPickerList() end)

    local clearSearch = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    clearSearch:SetSize(60, 22)
    clearSearch:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
    clearSearch:SetText(L["PICKER_CLEAR"] or "Clear")
    clearSearch:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(370)
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
    self:HideAnimationHoverPreview()
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
