local addonName, OxedHub = ...

local IconPicker = {}
local L = OxedHub.L
OxedHub.IconPicker = IconPicker

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local STORED_TEXTURE_PREFIX = "texture:"
local ICONS_PER_PAGE = 72
local EMOJI_TEXTURE_PATH = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\"
local CUSTOM_RING_ICONS = {
    EMOJI_TEXTURE_PATH .. "Affectionate smile.png",
    EMOJI_TEXTURE_PATH .. "Angelic smile.png",
    EMOJI_TEXTURE_PATH .. "Angry cold.png",
    EMOJI_TEXTURE_PATH .. "Angry.png",
    EMOJI_TEXTURE_PATH .. "Anime Tongue.png",
    EMOJI_TEXTURE_PATH .. "Bat Face.png",
    EMOJI_TEXTURE_PATH .. "Big grin.png",
    EMOJI_TEXTURE_PATH .. "Blank face.png",
    EMOJI_TEXTURE_PATH .. "Blowing kiss.png",
    EMOJI_TEXTURE_PATH .. "Blushing kiss.png",
    EMOJI_TEXTURE_PATH .. "Blushing smile.png",
    EMOJI_TEXTURE_PATH .. "Brainddead.png",
    EMOJI_TEXTURE_PATH .. "Closed-eye grin.png",
    EMOJI_TEXTURE_PATH .. "Cold face.png",
    EMOJI_TEXTURE_PATH .. "Confused.png",
    EMOJI_TEXTURE_PATH .. "Crazy tongue-1.png",
    EMOJI_TEXTURE_PATH .. "Crazy tongue.png",
    EMOJI_TEXTURE_PATH .. "crying face.png",
    EMOJI_TEXTURE_PATH .. "Crying.png",
    EMOJI_TEXTURE_PATH .. "Cursing angry.png",
    EMOJI_TEXTURE_PATH .. "Devil angry.png",
    EMOJI_TEXTURE_PATH .. "Devil smirk.png",
    EMOJI_TEXTURE_PATH .. "Dizzy sick.png",
    EMOJI_TEXTURE_PATH .. "Excited laugh.png",
    EMOJI_TEXTURE_PATH .. "Gamer face.png",
    EMOJI_TEXTURE_PATH .. "Happy smile.png",
    EMOJI_TEXTURE_PATH .. "Heart eyes.png",
    EMOJI_TEXTURE_PATH .. "Hugging.png",
    EMOJI_TEXTURE_PATH .. "Just sad.png",
    EMOJI_TEXTURE_PATH .. "Kiss.png",
    EMOJI_TEXTURE_PATH .. "Liar.png",
    EMOJI_TEXTURE_PATH .. "Masked face.png",
    EMOJI_TEXTURE_PATH .. "Money face.png",
    EMOJI_TEXTURE_PATH .. "Monocle face.png",
    EMOJI_TEXTURE_PATH .. "Mouthless.png",
    EMOJI_TEXTURE_PATH .. "Nauseated.png",
    EMOJI_TEXTURE_PATH .. "Nerd toothy.png",
    EMOJI_TEXTURE_PATH .. "Nerdy disapointment.png",
    EMOJI_TEXTURE_PATH .. "Neutral face.png",
    EMOJI_TEXTURE_PATH .. "old face.png",
    EMOJI_TEXTURE_PATH .. "Oward Face.png",
    EMOJI_TEXTURE_PATH .. "Party.png",
    EMOJI_TEXTURE_PATH .. "Pickup face.png",
    EMOJI_TEXTURE_PATH .. "Playful tongue.png",
    EMOJI_TEXTURE_PATH .. "Pouting angry.png",
    EMOJI_TEXTURE_PATH .. "Raised eyebrow.png",
    EMOJI_TEXTURE_PATH .. "Rolling-on-floor laughing.png",
    EMOJI_TEXTURE_PATH .. "Sad and Sweat.png",
    EMOJI_TEXTURE_PATH .. "Sad cry.png",
    EMOJI_TEXTURE_PATH .. "Sad sweat.png",
    EMOJI_TEXTURE_PATH .. "Sad.png",
    EMOJI_TEXTURE_PATH .. "Sadly Crying.png",
    EMOJI_TEXTURE_PATH .. "Shocked.png",
    EMOJI_TEXTURE_PATH .. "Shushing.png",
    EMOJI_TEXTURE_PATH .. "Shy smile.png",
    EMOJI_TEXTURE_PATH .. "Sick face.png",
    EMOJI_TEXTURE_PATH .. "Skull and crossbones.png",
    EMOJI_TEXTURE_PATH .. "Skull.png",
    EMOJI_TEXTURE_PATH .. "Sleeping.png",
    EMOJI_TEXTURE_PATH .. "Smirk.png",
    EMOJI_TEXTURE_PATH .. "Star eyes.png",
    EMOJI_TEXTURE_PATH .. "Stupid smile.png",
    EMOJI_TEXTURE_PATH .. "Sunglasses cool.png",
    EMOJI_TEXTURE_PATH .. "surrounded by hearts.png",
    EMOJI_TEXTURE_PATH .. "Sweating laugh.png",
    EMOJI_TEXTURE_PATH .. "Sweating laugh2.png",
    EMOJI_TEXTURE_PATH .. "Tears of joy.png",
    EMOJI_TEXTURE_PATH .. "Thermometer sick.png",
    EMOJI_TEXTURE_PATH .. "Thinking.png",
    EMOJI_TEXTURE_PATH .. "tile011 1.png",
    EMOJI_TEXTURE_PATH .. "tile025 1.png",
    EMOJI_TEXTURE_PATH .. "tile026 1.png",
    EMOJI_TEXTURE_PATH .. "tile084 1.png",
    EMOJI_TEXTURE_PATH .. "tile086 1.png",
    EMOJI_TEXTURE_PATH .. "tile099 1.png",
    EMOJI_TEXTURE_PATH .. "tile100 1.png",
    EMOJI_TEXTURE_PATH .. "tile101 1.png",
    EMOJI_TEXTURE_PATH .. "tile110 1.png",
    EMOJI_TEXTURE_PATH .. "tile114 1.png",
    EMOJI_TEXTURE_PATH .. "Tongue out.png",
    EMOJI_TEXTURE_PATH .. "Vomiting.png",
    EMOJI_TEXTURE_PATH .. "What face.png",
    EMOJI_TEXTURE_PATH .. "Whistling kiss.png",
    EMOJI_TEXTURE_PATH .. "wipe face.png",
    EMOJI_TEXTURE_PATH .. "XX face.png",
    EMOJI_TEXTURE_PATH .. "Zipper mouth.png",
}

local LEGACY_RING_ICON_ALIASES = {
    ["Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons-png\\holy.png"] = EMOJI_TEXTURE_PATH .. "Angelic smile.png",
    ["Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons-png\\smile.png"] = EMOJI_TEXTURE_PATH .. "Happy smile.png",
    ["Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons-png\\smile-1.png"] = EMOJI_TEXTURE_PATH .. "Big grin.png",
    ["Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons-png\\smile hearts.png"] = EMOJI_TEXTURE_PATH .. "surrounded by hearts.png",
}

local function TrimText(text)
    if text == nil then
        return ""
    end
    return tostring(text):match("^%s*(.-)%s*$") or ""
end

local function NormalizeTexturePath(texture)
    if type(texture) ~= "string" then
        return texture
    end

    return LEGACY_RING_ICON_ALIASES[texture] or texture
end

function IconPicker:MakeStoredTextureValue(texture)
    if texture == nil or texture == "" then
        return nil
    end
    return STORED_TEXTURE_PREFIX .. tostring(NormalizeTexturePath(texture))
end

function IconPicker:IsStoredTextureValue(value)
    return type(value) == "string" and value:sub(1, #STORED_TEXTURE_PREFIX) == STORED_TEXTURE_PREFIX
end

function IconPicker:GetDisplayValue(value)
    local raw = TrimText(value)
    if raw == "" then
        return ""
    end

    if self:IsStoredTextureValue(raw) then
        return NormalizeTexturePath(raw:sub(#STORED_TEXTURE_PREFIX + 1))
    end

    return NormalizeTexturePath(raw)
end

function IconPicker:GetQuestionMarkIcon()
    return QUESTION_MARK_ICON
end

function IconPicker:ResolveTexture(value)
    local raw = TrimText(value)
    if raw == "" then
        return nil
    end

    if self:IsStoredTextureValue(raw) then
        local token = raw:sub(#STORED_TEXTURE_PREFIX + 1)
        token = NormalizeTexturePath(token)
        local numeric = tonumber(token)
        return numeric or token
    end

    raw = NormalizeTexturePath(raw)

    local numeric = tonumber(raw)
    if numeric then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(numeric)
        if spellInfo and spellInfo.iconID then
            return spellInfo.iconID
        end

        if C_Item and C_Item.GetItemIconByID then
            local itemIcon = C_Item.GetItemIconByID(numeric)
            if itemIcon then
                return itemIcon
            end
        end
    end

    local namedSpell = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(raw)
    if namedSpell and namedSpell.iconID then
        return namedSpell.iconID
    end

    return raw
end

function IconPicker:GetMacroIcons()
    if self.cachedIcons then
        return self.cachedIcons
    end

    local icons = {}
    local seen = {}

    local function AddTexture(texture)
        if not texture or texture == 0 or texture == "" then
            return
        end

        local key = tostring(texture)
        if seen[key] then
            return
        end

        seen[key] = true
        icons[#icons + 1] = texture
    end

    local function HarvestIntoTable(apiFunc)
        if not apiFunc then
            return
        end

        local buffer = {}
        apiFunc(buffer)
        for index = 1, #buffer do
            AddTexture(buffer[index])
        end
    end

    HarvestIntoTable(GetMacroIcons)
    HarvestIntoTable(GetMacroItemIcons)

    if #icons < 40 then
        HarvestIntoTable(GetLooseMacroIcons)
        HarvestIntoTable(GetLooseMacroItemIcons)
    end

    if #icons == 0 and GetNumMacroIcons and GetMacroIconInfo then
        local count = GetNumMacroIcons() or 0
        for index = 1, count do
            local texture = GetMacroIconInfo(index)
            if texture and texture ~= 0 and texture ~= "" then
                AddTexture(texture)
            end
        end
    end

    self.cachedIcons = icons
    return icons
end

function IconPicker:GetFilteredIcons(searchText)
    local icons = self:GetMacroIcons()
    local query = TrimText(searchText):lower()
    if query == "" then
        return icons
    end

    local searchableTextByTexture = self.searchableTextByTexture
    if not searchableTextByTexture then
        searchableTextByTexture = {}

        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
            local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
            for skillLineIndex = 1, numSkillLines do
                local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
                if skillLineInfo then
                    local numSpells = skillLineInfo.numSpellBookItems or 0
                    for spellIndex = skillLineInfo.itemIndexOffset, skillLineInfo.itemIndexOffset + numSpells - 1 do
                        local bookInfo = C_SpellBook.GetSpellBookItemInfo(spellIndex, Enum.SpellBookSpellBank.Player)
                        if bookInfo then
                            if bookInfo.itemType == Enum.SpellBookItemType.Flyout and bookInfo.actionID then
                                local _, _, numSlots, isKnown = GetFlyoutInfo(bookInfo.actionID)
                                if isKnown and numSlots and numSlots > 0 then
                                    for slotIndex = 1, numSlots do
                                        local flyoutSpellID, _, isKnownSlot = GetFlyoutSlotInfo(bookInfo.actionID, slotIndex)
                                        if isKnownSlot and flyoutSpellID then
                                            local flyoutSpellInfo = C_Spell.GetSpellInfo(flyoutSpellID)
                                            if flyoutSpellInfo and flyoutSpellInfo.iconID and flyoutSpellInfo.name then
                                                local key = tostring(flyoutSpellInfo.iconID)
                                                local existing = searchableTextByTexture[key] or ""
                                                searchableTextByTexture[key] = existing .. "\n" .. flyoutSpellInfo.name:lower()
                                            end
                                        end
                                    end
                                end
                            elseif bookInfo.spellID then
                                local spellName = C_SpellBook.GetSpellBookItemName(spellIndex, Enum.SpellBookSpellBank.Player)
                                local texture = C_SpellBook.GetSpellBookItemTexture(spellIndex, Enum.SpellBookSpellBank.Player)
                                if spellName and texture then
                                    local key = tostring(texture)
                                    local existing = searchableTextByTexture[key] or ""
                                    searchableTextByTexture[key] = existing .. "\n" .. spellName:lower()
                                end
                            end
                        end
                    end
                end
            end
        end

        self.searchableTextByTexture = searchableTextByTexture
    end

    local filtered = {}
    for index = 1, #icons do
        local texture = icons[index]
        local haystack = tostring(texture):lower()
        local searchableText = searchableTextByTexture[tostring(texture)]
        if haystack:find(query, 1, true) or (searchableText and searchableText:find(query, 1, true)) then
            filtered[#filtered + 1] = texture
        end
    end

    return filtered
end

function IconPicker:GetCustomRingIcons()
    return CUSTOM_RING_ICONS
end

function IconPicker:GetFilteredCustomRingIcons(searchText)
    local query = TrimText(searchText):lower()
    if query == "" then
        return CUSTOM_RING_ICONS
    end

    local filtered = {}
    for index = 1, #CUSTOM_RING_ICONS do
        local texture = CUSTOM_RING_ICONS[index]
        if texture:lower():find(query, 1, true) then
            filtered[#filtered + 1] = texture
        end
    end

    return filtered
end

function IconPicker:EnsureFrame()
    if self.frame then
        return self.frame
    end

    local frame = CreateFrame("Frame", "OxedHubIconPickerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(450, 755)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(200)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetText(L["PICKER_CHOOSE_ICON"] or "Choose an Icon")
    frame.title = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)

    local previewBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBorder:SetSize(44, 44)
    previewBorder:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -38)
    previewBorder:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 8,
    })
    previewBorder:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    previewBorder:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local previewTexture = previewBorder:CreateTexture(nil, "ARTWORK")
    previewTexture:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", 3, -3)
    previewTexture:SetPoint("BOTTOMRIGHT", previewBorder, "BOTTOMRIGHT", -3, 3)
    previewTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.previewTexture = previewTexture

    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPRIGHT", previewBorder, "BOTTOMRIGHT", 0, -6)
    previewLabel:SetJustifyH("RIGHT")
    previewLabel:SetText(L["PICKER_CURRENTLY_SELECTED"] or "Currently Selected")

    local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -48)
    infoText:SetWidth(260)
    infoText:SetJustifyH("LEFT")
    infoText:SetText(L["PICKER_INFO_TEXT"] or "Uses the same macro icon list as Blizzard, so this picker can be reused across OxedHub.")
    frame.infoText = infoText

    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -87)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    searchInput:SetSize(180, 22)
    searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    frame.searchInput = searchInput

    local allIconsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allIconsCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -117)
    allIconsCheck:SetSize(24, 24)
    frame.allIconsCheck = allIconsCheck

    local allIconsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allIconsLabel:SetPoint("LEFT", allIconsCheck, "RIGHT", 6, 0)
    allIconsLabel:SetText(L["PICKER_SHOW_ALL_ICONS"] or "Show All WoW Icons")
    
    allIconsCheck:SetScript("OnClick", function(self)
        frame.customRingIconsOnly = not self:GetChecked()
        frame.currentPage = 1
        frame:RefreshIcons()
    end)

    local gridFrame = CreateFrame("Frame", nil, frame)
    gridFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -151)
    gridFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 150)
    gridFrame:EnableMouse(true)
    gridFrame:EnableMouseWheel(true)
    frame.gridFrame = gridFrame
    frame.iconButtons = {}

    local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pageText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 86)
    pageText:SetText("")
    frame.pageText = pageText

    local okayButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okayButton:SetSize(120, 24)
    okayButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 36)
    okayButton:SetText(L["BTN_OK"] or "Okay")
    frame.okayButton = okayButton

    local cancelButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelButton:SetSize(120, 24)
    cancelButton:SetPoint("RIGHT", okayButton, "LEFT", -8, 0)
    cancelButton:SetText(L["BTN_CANCEL"] or "Cancel")

    local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearButton:SetSize(90, 24)
    clearButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 36)
    clearButton:SetText(L["PICKER_CLEAR"] or "Clear")
    frame.clearButton = clearButton

    cancelButton:ClearAllPoints()
    cancelButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 36)

    local function RefreshSelection()
        for _, button in ipairs(frame.iconButtons) do
            local isSelected = button.textureToken == frame.pendingTexture
            if isSelected then
                button:SetBackdropBorderColor(1, 0.82, 0, 1)
                button:SetBackdropColor(0.22, 0.16, 0.02, 0.95)
            else
                button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
                button:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
            end
        end

        frame.previewTexture:SetTexture(frame.pendingTexture or QUESTION_MARK_ICON)
    end

    local function SelectTexture(texture)
        frame.pendingTexture = texture
        frame.pendingValue = texture and IconPicker:MakeStoredTextureValue(texture) or nil
        RefreshSelection()
    end

    local function CreateIconButton(index)
        local button = CreateFrame("Button", nil, gridFrame, "BackdropTemplate")
        button:SetSize(45, 45)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })

        local texture = button:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
        texture:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        button.texture = texture

        button:SetScript("OnClick", function(self)
            SelectTexture(self.textureToken)
            if IsShiftKeyDown() then
                okayButton:Click()
            end
        end)

        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((L["PICKER_ICON_PREFIX"] or "Icon ") .. (self.tooltipIndex or index))
            GameTooltip:AddLine(L["PICKER_SHIFT_CLICK_TOOLTIP"] or "Shift-click to choose this icon immediately.", 1, 1, 1, true)
            GameTooltip:Show()
        end)

        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        return button
    end

    function frame:RefreshIcons()
        local icons = self.customRingIconsOnly
            and IconPicker:GetFilteredCustomRingIcons(self.searchInput and self.searchInput:GetText() or nil)
            or IconPicker:GetFilteredIcons(self.searchInput and self.searchInput:GetText() or nil)
        local columns = 8
        local spacing = 6
        local size = 45
        local totalPages = math.max(math.ceil(#icons / ICONS_PER_PAGE), 1)

        if not self.currentPage or self.currentPage < 1 then
            self.currentPage = 1
        elseif self.currentPage > totalPages then
            self.currentPage = totalPages
        end

        local startIndex = ((self.currentPage - 1) * ICONS_PER_PAGE) + 1
        local endIndex = math.min(startIndex + ICONS_PER_PAGE - 1, #icons)
        local visibleCount = math.max(endIndex - startIndex + 1, 0)

        for slotIndex = 1, ICONS_PER_PAGE do
            local dataIndex = startIndex + slotIndex - 1
            local textureToken = icons[dataIndex]
            local button = self.iconButtons[slotIndex]
            if not button then
                button = CreateIconButton(slotIndex)
                self.iconButtons[slotIndex] = button
            end

            if textureToken then
                local row = math.floor((slotIndex - 1) / columns)
                local column = (slotIndex - 1) % columns
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", self.gridFrame, "TOPLEFT", column * (size + spacing), -(row * (size + spacing)))
                button.texture:SetTexture(textureToken)
                button.textureToken = textureToken
                button.tooltipIndex = dataIndex
                button:Show()
            else
                button:Hide()
            end
        end

        local totalRows = math.max(math.ceil(visibleCount / columns), 1)
        local totalHeight = totalRows * (size + spacing)
        self.gridFrame:SetHeight(totalHeight)
        self.pageText:SetText(string.format(L["PICKER_PAGE_FORMAT"] or "Page %d / %d", self.currentPage, totalPages))
        RefreshSelection()
    end

    local function HandleMouseWheel(_, delta)
        if delta > 0 then
            frame.currentPage = math.max((frame.currentPage or 1) - 1, 1)
            frame:RefreshIcons()
        elseif delta < 0 then
            local filteredIcons = frame.customRingIconsOnly
                and IconPicker:GetFilteredCustomRingIcons(frame.searchInput and frame.searchInput:GetText() or nil)
                or IconPicker:GetFilteredIcons(frame.searchInput and frame.searchInput:GetText() or nil)
            local totalPages = math.max(math.ceil(#filteredIcons / ICONS_PER_PAGE), 1)
            frame.currentPage = math.min((frame.currentPage or 1) + 1, totalPages)
            frame:RefreshIcons()
        end
    end

    frame:SetScript("OnMouseWheel", HandleMouseWheel)
    gridFrame:SetScript("OnMouseWheel", HandleMouseWheel)

    searchInput:SetScript("OnTextChanged", function()
        frame.currentPage = 1
        frame:RefreshIcons()
    end)

    okayButton:SetScript("OnClick", function()
        if frame.onSelect then
            frame.onSelect(frame.pendingValue, frame.pendingTexture)
        end
        frame:Hide()
    end)

    cancelButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    clearButton:SetScript("OnClick", function()
        frame.pendingValue = nil
        frame.pendingTexture = nil
        RefreshSelection()
        if frame.onSelect then
            frame.onSelect(nil, nil)
        end
        frame:Hide()
    end)

    frame:SetScript("OnShow", function(self)
        self.currentPage = 1
        if self.searchInput then
            self.searchInput:SetText("")
        end
        self:RefreshIcons()
        RefreshSelection()
    end)

    frame.RefreshSelection = RefreshSelection
    frame.SelectTexture = SelectTexture

    self.frame = frame
    return frame
end

function IconPicker:Open(options)
    options = options or {}

    local frame = self:EnsureFrame()
    frame.onSelect = options.onSelect
    frame.customRingIconsOnly = not not options.customRingIconsOnly
    frame.pendingValue = options.initialValue
    frame.pendingTexture = self:ResolveTexture(options.initialValue)
    frame.title:SetText(options.title or L["PICKER_CHOOSE_ICON"] or "Choose an Icon")
    frame.infoText:SetText(options.infoText or L["PICKER_INFO_TEXT"] or "Uses the same macro icon list as Blizzard, so this picker can be reused across OxedHub.")
    frame.clearButton:SetShown(options.allowClear ~= false)
    frame.previewTexture:SetTexture(frame.pendingTexture or QUESTION_MARK_ICON)
    
    if frame.allIconsCheck then
        frame.allIconsCheck:SetChecked(not frame.customRingIconsOnly)
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER")

    frame:Show()
    frame:Raise()
    frame:RefreshSelection()
end
