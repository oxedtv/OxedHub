local addonName, OxedHub = ...
local L = OxedHub.L
-- Sounds Module - Custom sound management and preview
local Sounds = {}
OxedHub.Sounds = Sounds

-- Local references
local PlaySoundFile = PlaySoundFile
local GetTime = GetTime

-- Sound cooldown
local lastSoundTime = 0
local SOUND_COOLDOWN = 0.1

-- Currently playing sound tracking
local currentPlayingHandle = nil
local currentPlayingBtn = nil

local function TrimString(value)
    if type(value) ~= "string" then
        return value
    end
    return value:match("^%s*(.-)%s*$")
end

local function BuildSoundFilePath(filename)
    filename = TrimString(filename or "")
    if filename == "" then
        return nil
    end

    local baseName, ext = filename:match("^(.-)%.([^.]+)$")
    if baseName and ext then
        local lowerExt = ext:lower()
        if lowerExt == "ogg" or lowerExt == "mp3" then
            return string.format("Interface\\AddOns\\OxedHub_CustomMedia\\%s.%s", baseName, lowerExt)
        end
    end

    return string.format("Interface\\AddOns\\OxedHub_CustomMedia\\%s.mp3", filename)
end

-- Initialize
function Sounds:Init()
    -- Nothing special needed on init
end

function Sounds:BuildLegacyMap()
    if self.legacyIdMap then return end
    self.legacyIdMap = {}
    self.legacyToNewIdMap = {}
    
    local catalog = OxedHub.GENERATED_SOUND_CATALOG
    if not catalog then return end
    
    local categories = {
        "dh_pack", "monk_pack", "worrier_pack", 
        "anime", "arabic", "death", "effects", 
        "legions", "meme", "quote"
    }
    
    for newId, soundData in pairs(catalog) do
        local coreName = newId:gsub("^oxedhub_", "")
        for _, cat in ipairs(categories) do
            if coreName:sub(1, #cat + 1) == cat .. "_" then
                coreName = coreName:sub(#cat + 2)
                break
            end
        end
        -- Clean up special characters to match clean IDs/filenames
        coreName = coreName:lower():gsub("[^a-z0-9_]", "_")
        self.legacyIdMap[coreName] = soundData.filePath
        self.legacyToNewIdMap[coreName] = newId
    end
end

function Sounds:ResolvePathOrId(pathOrId)
    if not pathOrId or type(pathOrId) ~= "string" or pathOrId == "" or pathOrId == "None" then
        return pathOrId
    end

    self:BuildLegacyMap()

    -- 1. Try to resolve as a legacy ID (starts with oxedhub_ and ends with extension suffix, or is just a legacy ID)
    local cleanKey = nil
    if pathOrId:find("^oxedhub_") then
        cleanKey = pathOrId:gsub("^oxedhub_", ""):gsub("_ogg$", ""):gsub("_mp3$", ""):gsub("_wav$", "")
        cleanKey = cleanKey:lower():gsub("[^a-z0-9_]", "_")
    else
        -- 2. Try to resolve as a flat path
        local filename = pathOrId:match("([^\\/]+)%.%w+$")
        if filename then
            cleanKey = filename:lower():gsub("^oxedhub_", ""):gsub("[^a-z0-9_]", "_")
        end
    end

    if cleanKey and self.legacyToNewIdMap[cleanKey] then
        return self.legacyToNewIdMap[cleanKey]
    end

    -- If it's a flat path that wasn't in catalog (maybe custom media),
    -- check if it has the old "Interface\AddOns\OxedHub\Media\Sound\" prefix and translate it to CustomMedia
    if pathOrId:find("Interface\\AddOns\\OxedHub\\Media\\Sound\\") then
        local customPath = pathOrId:gsub("Interface\\AddOns\\OxedHub\\Media\\Sound\\", "Interface\\AddOns\\OxedHub_CustomMedia\\")
        return customPath
    end

    return pathOrId
end

function Sounds:CancelPendingRefresh()
    self.refreshGeneration = (self.refreshGeneration or 0) + 1
    self.refreshTicker = nil
end

function Sounds:SyncGeneratedCatalog()
    local catalog = OxedHub.GENERATED_SOUND_CATALOG
    if not catalog then
        return
    end

    local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds)
    if type(sounds) ~= "table" then
        return
    end

    if OxedHub.SyncSharedCustomSounds then
        OxedHub:SyncSharedCustomSounds(OxedHub.db and OxedHub.db.profile)
    end

    -- Migrate old custom sounds to the new persistent directory
    for id, sound in pairs(sounds) do
        if not sound.autoImported and sound.filePath and sound.filePath:find("OxedHub\\Media\\Sound\\") then
            sound.filePath = sound.filePath:gsub("OxedHub\\Media\\Sound\\", "OxedHub_CustomMedia\\")
        end
    end

    for id, sound in pairs(sounds) do
        if sound.autoImported and not catalog[id] then
            sounds[id] = nil
        end
    end

    for id, sound in pairs(catalog) do
        local existing = sounds[id]
        if not existing then
            sounds[id] = {
                name = sound.name,
                filePath = sound.filePath,
                category = sound.category,
                autoImported = true,
            }
        elseif existing.autoImported then
            -- Update category and filePath in case files moved to subfolders
            existing.category = sound.category
            existing.filePath = sound.filePath
            existing.name = sound.name
        end
    end
end

-- Show Sounds UI
Sounds.expandedCategories = Sounds.expandedCategories or {}
Sounds.currentFilter = "All" -- "All", "Built-in", "Favorites", "Custom"
Sounds.headerPool = Sounds.headerPool or {}
Sounds.itemPool = Sounds.itemPool or {}

local CATEGORY_ORDER = {
    "Custom Sounds",
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

local function GetSoundCategory(sound)
    if not sound.autoImported then return "Custom Sounds" end
    -- Use the category field set directly from the folder name in the catalog
    if sound.category and sound.category ~= "" then return sound.category end
    return "Other"
end

local function GetDisplaySoundName(name)
    name = name or ""
    return name:gsub("^OxedHub%s+", "")
end

function Sounds:ShowUI(parent)
    self:CancelPendingRefresh()

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
    title:SetText(L["SOUNDS_CUSTOM_LIBRARY"] or "Custom Sounds Library")

    -- Instructions
    local instructions = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    instructions:SetTextColor(0.86, 0.82, 0.72, 1)
    instructions:SetText(L["SOUNDS_LIBRARY_DESC"] or "Manage your audio library here. Sounds can be used in reactions and toy macros.")

    -- Add Sound button
    local addBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 25)
    addBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    addBtn:SetText(L["SOUNDS_ADD_SOUND"] or "Add Sound")
    addBtn:SetScript("OnClick", function()
        self:ShowAddSoundDialog()
    end)

    -- Bottom Filter Bar
    local filterBar = CreateFrame("Frame", nil, parent)
    filterBar:SetSize(parent:GetWidth() - 20, 30)
    filterBar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 10, 10)

    local totalText = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("LEFT", filterBar, "LEFT", 0, 0)
    totalText:SetTextColor(0.5, 0.5, 0.5)
    self.totalText = totalText

    -- Quick Filters
    local function CreateFilterBtn(label, filterName, width, rightAnchor)
        local btn = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
        btn:SetSize(width, 22)
        btn:SetPoint("RIGHT", rightAnchor, "LEFT", -5, 0)
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            Sounds.currentFilter = filterName
            Sounds:RefreshSoundList(Sounds.currentScrollChild)
        end)
        return btn
    end

    local customBtn = CreateFrame("Button", nil, filterBar, "UIPanelButtonTemplate")
    customBtn:SetSize(100, 22)
    customBtn:SetPoint("RIGHT", filterBar, "RIGHT", 0, 0)
    customBtn:SetText(L["SOUNDS_FILTER_CUSTOM"] or "Custom")
    customBtn:SetScript("OnClick", function() Sounds.currentFilter = "Custom"; Sounds:RefreshSoundList(Sounds.currentScrollChild) end)

    local favBtn = CreateFilterBtn(L["SOUNDS_FILTER_FAV"] or "Favorites", "Favorites", 80, customBtn)
    local builtInBtn = CreateFilterBtn(L["SOUNDS_FILTER_BUILTIN"] or "Built-in", "Built-in", 80, favBtn)
    local allBtn = CreateFilterBtn(L["SOUNDS_FILTER_ALL"] or "All", "All", 60, builtInBtn)

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubSoundsScrollFrame" .. tostring(GetTime()), parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", filterBar, "TOPRIGHT", -20, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.currentScrollFrame = scrollFrame
    self.currentScrollChild = scrollChild

    self:RefreshSoundList(scrollChild)
end

function Sounds:GetOrCreateHeader(parent, index)
    if not self.headerPool[index] then
        local header = CreateFrame("Button", nil, parent)
        header:SetHeight(25)
        
        local bg = header:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        
        local icon = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        icon:SetPoint("LEFT", header, "LEFT", 5, 0)
        icon:SetTextColor(1, 0.82, 0)
        
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        label:SetTextColor(1, 0.82, 0)
        
        header.icon = icon
        header.label = label
        
        header:SetScript("OnEnter", function() bg:SetColorTexture(0.2, 0.2, 0.2, 0.6) end)
        header:SetScript("OnLeave", function() bg:SetColorTexture(0.1, 0.1, 0.1, 0.5) end)
        
        self.headerPool[index] = header
    end
    
    local header = self.headerPool[index]
    header:SetParent(parent)
    header:Show()
    return header
end

function Sounds:GetOrCreateGridItem(parent, index)
    if not self.itemPool[index] then
        local item = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        item:SetHeight(26)
        item:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
        item:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
        
        -- Play button
        local playBtn = CreateFrame("Button", nil, item)
        playBtn:SetSize(20, 20)
        playBtn:SetPoint("LEFT", item, "LEFT", 5, 0)
        local playIcon = playBtn:CreateTexture(nil, "ARTWORK")
        playIcon:SetAllPoints()
        playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        playIcon:SetVertexColor(0.9, 0.1, 0.1) -- Red play arrow
        playBtn.playIcon = playIcon
        
        -- Favorite button (anchored to the far right)
        local favBtn = CreateFrame("Button", nil, item)
        favBtn:SetSize(16, 16)
        favBtn:SetPoint("RIGHT", item, "RIGHT", -5, 0)
        local favIcon = favBtn:CreateTexture(nil, "ARTWORK")
        favIcon:SetAllPoints()
        
        -- Delete button (anchored to the left of the favorite button)
        local delBtn = CreateFrame("Button", nil, item)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("RIGHT", favBtn, "LEFT", -4, 0)
        local delIcon = delBtn:CreateTexture(nil, "ARTWORK")
        delIcon:SetAllPoints()
        delIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        delBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        delBtn:Hide()
        
        -- Name
        local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", playBtn, "RIGHT", 2, 0)
        nameText:SetPoint("RIGHT", delBtn, "LEFT", -2, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        
        item:SetScript("OnEnter", function()
            item:SetBackdropColor(0.25, 0.25, 0.25, 0.8)
            if item.isCustom then delBtn:Show() end
            if currentPlayingBtn ~= playBtn then
                playIcon:SetVertexColor(1, 0.3, 0.3) -- Brighter red on hover
            end
        end)
        item:SetScript("OnLeave", function()
            item:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
            if not delBtn:IsMouseOver() then
                delBtn:Hide()
            end
            if currentPlayingBtn ~= playBtn then
                playIcon:SetVertexColor(0.9, 0.1, 0.1)
            end
        end)
        
        item.nameText = nameText
        item.playBtn = playBtn
        item.delBtn = delBtn
        item.favBtn = favBtn
        item.favIcon = favIcon
        
        self.itemPool[index] = item
    end
    
    local item = self.itemPool[index]
    item:SetParent(parent)
    item:Show()
    return item
end

function Sounds:RefreshSoundList(parent)
    self:CancelPendingRefresh()

    for _, header in pairs(self.headerPool) do header:Hide() end
    for _, item in pairs(self.itemPool) do item:Hide() end
    if self.emptyText then self.emptyText:Hide() end

    local sounds = OxedHub.db.profile.customSounds or {}
    local searchText = (OxedHub.globalSearchText or ""):lower()
    
    local grouped = {}
    local matchCount = 0
    
    for id, sound in pairs(sounds) do
        local isFav = sound.isFavorite
        local isCustom = not sound.autoImported
        local passFilter = true
        
        if self.currentFilter == "Favorites" and not isFav then passFilter = false end
        if self.currentFilter == "Built-in" and isCustom then passFilter = false end
        if self.currentFilter == "Custom" and not isCustom then passFilter = false end
        
        local soundName = (sound.name or id):lower()
        if passFilter and (searchText == "" or string.find(soundName, searchText, 1, true)) then
            local cat = GetSoundCategory(sound)
            grouped[cat] = grouped[cat] or {}
            table.insert(grouped[cat], {id = id, sound = sound, isFav = isFav, isCustom = isCustom})
            matchCount = matchCount + 1
        end
    end
    
    if self.totalText then
        self.totalText:SetText(string.format(L["SOUNDS_SHOWING_TOTAL"] or "Showing %d sounds in total", matchCount))
    end
    
    if matchCount == 0 then
        if not self.emptyText then
            self.emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.emptyText:SetPoint("CENTER", parent, "CENTER", 0, 0)
        end
        self.emptyText:SetText("No sounds match your filters.")
        self.emptyText:Show()
        parent:SetHeight(50)
        return
    end

    for _, cat in pairs(grouped) do
        table.sort(cat, function(a, b)
            local aName = (a.sound.name or a.id):lower()
            local bName = (b.sound.name or b.id):lower()
            return aName < bName
        end)
    end

    local orderedCats = {}
    for _, catName in ipairs(CATEGORY_ORDER) do
        if grouped[catName] then
            table.insert(orderedCats, catName)
            grouped[catName].processed = true
        end
    end
    local otherCats = {}
    for catName in pairs(grouped) do
        if catName ~= "processed" and not grouped[catName].processed then
            table.insert(otherCats, catName)
        end
    end
    table.sort(otherCats)
    for _, catName in ipairs(otherCats) do
        table.insert(orderedCats, catName)
    end

    local yOffset = -5
    local headerIndex = 1
    local itemIndex = 1
    
    local containerWidth = parent:GetWidth()
    local cols = 3
    local itemWidth = (containerWidth - 10 - ((cols-1) * 5)) / cols
    if itemWidth < 180 then
        cols = 2
        itemWidth = (containerWidth - 10 - ((cols-1) * 5)) / cols
    end

    for _, catName in ipairs(orderedCats) do
        local catItems = grouped[catName]
        
        if searchText ~= "" then
            self.expandedCategories[catName] = true
        end
        if catName == "Custom Sounds" and self.expandedCategories[catName] == nil then
            self.expandedCategories[catName] = true
        end
        
        local isExpanded = self.expandedCategories[catName]

        local header = self:GetOrCreateHeader(parent, headerIndex)
        headerIndex = headerIndex + 1
        
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, yOffset)
        
        header.icon:SetText(isExpanded and "v" or ">")
        header.label:SetText(string.format("%s (%d)", catName, #catItems))
        
        header:SetScript("OnClick", function()
            self.expandedCategories[catName] = not self.expandedCategories[catName]
            self:RefreshSoundList(parent)
        end)
        
        yOffset = yOffset - 30
        
        if isExpanded then
            local col = 0
            
            for _, data in ipairs(catItems) do
                local item = self:GetOrCreateGridItem(parent, itemIndex)
                itemIndex = itemIndex + 1
                
                item.isCustom = data.isCustom
                if not data.isCustom then
                    item.delBtn:Hide()
                end
                
                item.nameText:SetText(GetDisplaySoundName(data.sound.name or data.id))
                
                item.favIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
                if data.isFav then
                    item.favIcon:SetVertexColor(1, 1, 1, 1)
                else
                    item.favIcon:SetVertexColor(0.5, 0.5, 0.5, 0.4)
                end
                
                item.playBtn:SetScript("OnClick", function(btn)
                    if currentPlayingBtn == btn and currentPlayingHandle then
                        -- Stop the currently playing sound
                        StopSound(currentPlayingHandle)
                        btn.playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                        btn.playIcon:SetVertexColor(0.9, 0.1, 0.1)
                        currentPlayingHandle = nil
                        currentPlayingBtn = nil
                    else
                        -- Stop previous sound if any
                        if currentPlayingHandle then
                            StopSound(currentPlayingHandle)
                            if currentPlayingBtn and currentPlayingBtn.playIcon then
                                currentPlayingBtn.playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                                currentPlayingBtn.playIcon:SetVertexColor(0.9, 0.1, 0.1)
                            end
                        end
                        -- Play new sound
                        local handle = self:Play(data.sound.filePath, data.sound.name)
                        if handle then
                            currentPlayingHandle = handle
                            currentPlayingBtn = btn
                            btn.playIcon:SetTexture("Interface\\Buttons\\UI-StopButton")
                            btn.playIcon:SetVertexColor(1, 0.3, 0.3)
                        end
                    end
                end)
                item.delBtn:SetScript("OnClick", function()
                    self:DeleteSound(data.id)
                end)
                item.favBtn:SetScript("OnClick", function()
                    data.sound.isFavorite = not data.sound.isFavorite
                    self:RefreshSoundList(parent)
                end)
                
                local xOffset = 5 + (col * (itemWidth + 5))
                item:ClearAllPoints()
                item:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
                item:SetSize(itemWidth, 26)
                
                col = col + 1
                if col >= cols then
                    col = 0
                    yOffset = yOffset - 31
                end
            end
            if col > 0 then
                yOffset = yOffset - 31
            end
            yOffset = yOffset - 5
        end
    end
    
    parent:SetHeight(-yOffset + 10)
    
    if self.currentScrollFrame then
        self.currentScrollFrame:UpdateScrollChildRect()
    end
end

-- Show add sound dialog
function Sounds:ShowAddSoundDialog()
    -- If the dialog already exists, just show it
    if OxedHubAddSoundDialog then
        OxedHubAddSoundDialog:Show()
        return
    end

    -- Create the main modal dialog frame
    local dialog = CreateFrame("Frame", "OxedHubAddSoundDialog", UIParent, "BackdropTemplate")
    dialog:SetSize(450, 360) -- increased size for more text space
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(200)
    
    -- Setup the modern, semi-transparent backdrop
    dialog:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    dialog:SetBackdropColor(0, 0, 0, 0.85)
    dialog:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", dialog.StartMoving)
    dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

    -- Create an overlay blocker behind the dialog to dim the background section
    local blocker = CreateFrame("Button", nil, dialog)
    blocker:SetFrameLevel(dialog:GetFrameLevel() - 1)
    if OxedHub.UI and OxedHub.UI.mainFrame then
        blocker:SetAllPoints(OxedHub.UI.mainFrame)
    else
        blocker:SetAllPoints(UIParent)
    end
    local blockerTex = blocker:CreateTexture(nil, "BACKGROUND")
    blockerTex:SetAllPoints()
    blockerTex:SetColorTexture(0, 0, 0, 0.6) -- 60% opacity black underlay
    -- Clicking the blocker closes the dialog
    blocker:SetScript("OnClick", function() dialog:Hide() end)

    -- Header background for the title text
    local headerBg = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
    headerBg:SetColorTexture(0, 0, 0, 0.5)
    headerBg:SetPoint("TOPLEFT", dialog, "TOPLEFT", 4, -4)
    headerBg:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)
    headerBg:SetHeight(24)
    
    -- Title Text
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", headerBg, "CENTER", 0, 0)
    title:SetText(L["SOUNDS_ADD_TITLE"] or "Add Custom Sound")
    title:SetTextColor(1, 0.82, 0, 1)

    -- X Close Button in top right
    local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() dialog:Hide() end)

    -- Sound Name Input Label
    local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 30, -45)
    nameLabel:SetText(L["SOUNDS_ADD_NAME_LBL"] or "Sound Name:")
    nameLabel:SetTextColor(1, 0.82, 0, 1)

    -- Sound Name Input Box
    local nameInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    nameInput:SetSize(390, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 6, -5)
    nameInput:SetAutoFocus(true)

    -- Filename Input Label
    local fileLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fileLabel:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", -6, -15)
    fileLabel:SetText(L["SOUNDS_ADD_FILE_LBL"] or "Filename (e.g., 'cry3', 'cry3.mp3', or 'cry3.OGG'):")
    fileLabel:SetTextColor(1, 0.82, 0, 1)

    -- Filename Input Box
    local fileInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    fileInput:SetSize(390, 20)
    fileInput:SetPoint("TOPLEFT", fileLabel, "BOTTOMLEFT", 6, -5)

    -- Instructions Header
    local instHeader = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instHeader:SetPoint("TOPLEFT", fileInput, "BOTTOMLEFT", -6, -25)
    instHeader:SetText(L["SOUNDS_ADD_INST_HDR"] or "How to add custom audio files:")
    instHeader:SetTextColor(1, 0.82, 0, 1)

    -- Instruction step 1
    local instText1 = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instText1:SetPoint("TOPLEFT", instHeader, "BOTTOMLEFT", 0, -8)
    instText1:SetWidth(390)
    instText1:SetJustifyH("LEFT")
    instText1:SetText(L["SOUNDS_ADD_INST_1"] or "1. Create a new folder inside your WoW AddOns directory named:")

    -- Folder Name Copy Box (Read Only)
    local folderBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
    folderBox:SetSize(160, 20)
    folderBox:SetPoint("TOPLEFT", instText1, "BOTTOMLEFT", 6, -5)
    folderBox:SetText("OxedHub_CustomMedia")
    folderBox:SetCursorPosition(0)
    -- Select all text when clicked to make copying easy
    folderBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    folderBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Prevent user from changing the text
    folderBox:SetScript("OnTextChanged", function(self, isUserInput)
        if isUserInput then
            self:SetText("OxedHub_CustomMedia")
            self:HighlightText()
        end
    end)
    
    local copyHint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyHint:SetPoint("LEFT", folderBox, "RIGHT", 10, 0)
    copyHint:SetText(L["SOUNDS_ADD_INST_COPY"] or "(Click and press CTRL+C to copy)")

    -- Instruction steps 2, 3, 4
    local instText2 = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    instText2:SetPoint("TOPLEFT", folderBox, "BOTTOMLEFT", -6, -10)
    instText2:SetWidth(390)
    instText2:SetJustifyH("LEFT")
    instText2:SetText(L["SOUNDS_ADD_INST_2"] or "2. The full path should look like this:\n   |cffaaaaaaInterface\\AddOns\\OxedHub_CustomMedia\\|r\n\n3. Place your audio files (.mp3 or .ogg) into this folder.\n4. You MUST fully restart World of Warcraft to load new files.")

    -- Cancel button (bottom right)
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetSize(100, 25)
    cancelBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -10, 20)
    cancelBtn:SetText(L["SETTINGS_BTN_CANCEL"] or "Cancel")
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    -- Save button (bottom left)
    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetSize(100, 25)
    saveBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 10, 20)
    saveBtn:SetText(L["SETTINGS_BTN_SAVE"] or "Save")
    saveBtn:SetScript("OnClick", function()
        local name = nameInput:GetText()
        local filename = fileInput:GetText()
        if name ~= "" and filename ~= "" then
            Sounds:AddSound(name, filename)
            dialog:Hide()
            -- Clear inputs for next time
            nameInput:SetText("")
            fileInput:SetText("")
        end
    end)
end

-- Add sound
function Sounds:AddSound(name, filename)
    name = TrimString(name or "")
    filename = TrimString(filename or "")
    if name == "" or filename == "" then
        return
    end

    local id = OxedHub:GenerateID("sound")
    local filePath = BuildSoundFilePath(filename)
    if not filePath then
        return
    end

    local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or OxedHub.db.profile.customSounds
    sounds[id] = {
        name = name,
        filePath = filePath,
    }

    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Sounds")
    end
end

-- Delete sound
function Sounds:DeleteSound(id)
    local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or OxedHub.db.profile.customSounds
    sounds[id] = nil

    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Sounds")
    end
end

-- Play sound
function Sounds:Play(soundIdOrPath, soundName)
    local now = GetTime()
    if now - lastSoundTime < SOUND_COOLDOWN then
        return -- On cooldown
    end
    lastSoundTime = now

    local resolvedIdOrPath = self:ResolvePathOrId(soundIdOrPath)
    local filePath = resolvedIdOrPath

    -- If it's an ID, look up the path
    local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or OxedHub.db.profile.customSounds
    if sounds and sounds[resolvedIdOrPath] then
        local sound = sounds[resolvedIdOrPath]
        filePath = sound.filePath
        soundName = sound.name
    end

    if not filePath or filePath == "" then
        print("|cffff0000Oxed Hub:|r No sound file specified")
        return
    end

    -- Attempt to play
    local willPlay, handle = PlaySoundFile(filePath, OxedHub.db.profile.settings.soundChannel or "Master")

    if not willPlay then
        print("|cffff0000Oxed Hub:|r " .. OxedHub:GetString("ERR_SOUND_NOT_FOUND", soundName or filePath))
        return nil
    end

    return handle
end

-- Play by ID
function Sounds:PlayByID(soundId)
    self:Play(soundId)
end
