local addonName, OxedHub = ...

-- UI Module - Main window and interface
local UI = {}
OxedHub.UI = UI

-- Local references
local CONFIG = OxedHub.CONFIG
local L = OxedHub.L
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown

-- UI Frames
local mainFrame = nil
local sidebar = nil
local contentArea = nil
local currentTab = "Dashboard"
local searchBox = nil

local NAV_ICONS = {
    Dashboard = "Interface\\Icons\\Inv_misc_map02",
    Triggers = "Interface\\Icons\\Spell_arcane_blast",
    Reactions = "Interface\\Icons\\UI_Chat",
    Toys = "Interface\\Icons\\INV_Misc_Dice_01",
    OxedRing = 133402,
    ActionHub = "Interface\\Icons\\INV_Sword_04",
    Settings = "Interface\\Icons\\Trade_engineering",
    About = "Interface\\Icons\\INV_Misc_QuestionMark",
    Experimental = "Interface\\Icons\\Trade_engineering",
}

local function ApplyStoneBackdrop(frame, alpha)
    if OxedHub.UIComponents and OxedHub.UIComponents.Panel then
        OxedHub.UIComponents.Panel.ApplyStoneBackdrop(frame, alpha)
    end
end

local function ApplyBlackWorkBackdrop(frame, alpha)
    if OxedHub.UIComponents and OxedHub.UIComponents.Panel then
        OxedHub.UIComponents.Panel.ApplyBlackWorkBackdrop(frame, alpha)
    end
end

local TOYS_BACKGROUND_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg.png"
local THEMED_FRAME_INSETS = {
    left = 42,
    right = 56,
    top = 66,
    bottom = 54,
}

local function ApplyToysBackground(frame, alpha)
    if not frame then
        return
    end

    local bg = frame.backgroundTexture
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.backgroundTexture = bg
    end

    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 1)
    bg:SetTexture(TOYS_BACKGROUND_TEXTURE)
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetAlpha(alpha or 0.95)

    return bg
end

UI.ApplyToysBackground = ApplyToysBackground
UI.StyleScrollFrame = StyleScrollFrame

function UI:GetThemedFrameInsets()
    return THEMED_FRAME_INSETS.left, THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.top, THEMED_FRAME_INSETS.bottom
end

local function ApplyOrnateFrame(frame, title, alpha)
    if OxedHub.UIComponents and OxedHub.UIComponents.Panel then
        OxedHub.UIComponents.Panel.ApplyOrnateFrame(frame, title, alpha)
    end
end

local function StyleScrollFrame(scrollFrame)
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll then
        OxedHub.UIComponents.Scroll.StyleFrame(scrollFrame)
    end
end

local function ApplyGoldButtonStyle(button)
    if OxedHub.UIComponents and OxedHub.UIComponents.Button then
        OxedHub.UIComponents.Button.ApplyGoldStyle(button)
    end
end

local function ApplyRedButtonStyle(button)
    if OxedHub.UIComponents and OxedHub.UIComponents.Button then
        OxedHub.UIComponents.Button.ApplyRedStyle(button)
    end
end

local function ApplySearchFrameStyle(searchBox)
    if OxedHub.UIComponents and OxedHub.UIComponents.Search then
        OxedHub.UIComponents.Search.ApplyFrameStyle(searchBox)
    end
end

local function CreateNavButton(parent, tabName, label)
    return OxedHub.UIComponents.Navigation.CreateButton(parent, tabName, label, CONFIG, NAV_ICONS)
end

local function SetupClassDropdown(dropdown, getSelectedToken, onSelectToken)
    if not dropdown then
        return
    end

    local selectedName = OxedHub:GetClassDisplayName(getSelectedToken and getSelectedToken() or false) or L["DASHBOARD_NO_CLASS"]
    dropdown:OverrideText(selectedName)
    dropdown:SetupMenu(function(_, rootDescription)
        for _, classInfo in ipairs(OxedHub:GetSupportedClassProfiles()) do
            local token = classInfo.token
            local label = classInfo.name
            rootDescription:CreateRadio(
                label,
                function()
                    return (getSelectedToken and getSelectedToken() or false) == token
                end,
                function()
                    if onSelectToken then
                        onSelectToken(token)
                    end
                    dropdown:OverrideText(label)
                end,
                label
            )
        end
    end)
end

local function ClampWindowPosition(x, y, frameWidth, frameHeight)
    local parentWidth = UIParent and UIParent:GetWidth() or 0
    local parentHeight = UIParent and UIParent:GetHeight() or 0

    if parentWidth <= 0 or parentHeight <= 0 then
        return x, y
    end

    local minX = 0
    local maxX = math.max(0, parentWidth - frameWidth)
    local minY = frameHeight
    local maxY = parentHeight

    return math.min(math.max(x, minX), maxX), math.min(math.max(y, minY), maxY)
end

local function UpdateSearchPlaceholderVisibility(editBox)
    if not editBox then
        return
    end

    local text = editBox:GetText()
    local isEmpty = not text or text == ""

    local instructions = editBox.Instructions or editBox.instructions
    if not instructions and editBox.GetName then
        local name = editBox:GetName()
        if name then
            instructions = _G[name .. "Instructions"] or _G[name .. "SearchInstructions"]
        end
    end
    if instructions and instructions.SetShown then
        instructions:SetShown(isEmpty)
    end

    local regions = { editBox:GetRegions() }
    for _, region in ipairs(regions) do
        if region and region.GetObjectType and region:GetObjectType() == "FontString" and region.SetShown then
            local regionText = region.GetText and region:GetText()
            if regionText == "Search" then
                region:SetShown(isEmpty)
            end
        end
    end
end

local function ApplyDashboardCardBackdrop(frame, backgroundAlpha)
    frame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.04, 0.05, backgroundAlpha or 0.65)
    frame:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)
end

local function CreateDashboardStatCard(parent, labelText, width)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(width or 150, 58)
    ApplyDashboardCardBackdrop(card, 0.9)

    local value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    value:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    value:SetTextColor(1, 0.82, 0, 1)
    value:SetText("0")

    local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -4)
    label:SetTextColor(0.8, 0.8, 0.8, 1)
    label:SetText(labelText)

    card.value = value
    card.label = label
    return card
end

local function CreateSettingsSectionHeader(parent, relativeTo, relativePoint, xOffset, yOffset, text)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24)
    local relativeVertical = "BOTTOM"
    if relativePoint == "TOPLEFT" or relativePoint == "TOP" then
        relativeVertical = "TOP"
    end
    header:SetPoint("TOP", relativeTo, relativeVertical, 0, yOffset or 0)
    header:SetPoint("LEFT", parent, "LEFT", 15, 0)
    header:SetPoint("RIGHT", parent, "RIGHT", -15, 0)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", header, "LEFT", 0, 0)
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetText(text)

    local line = header:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetColorTexture(0.72, 0.55, 0, 0.65)
    line:SetPoint("LEFT", title, "RIGHT", 12, -1)
    line:SetPoint("RIGHT", header, "RIGHT", 0, -1)

    header.title = title
    header.line = line
    return header
end

local function TraverseAndApplyTextSize(frame, delta)
    if not frame then return end
    
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            if not region.origFontFile then
                local fontFile, fontSize, fontFlags = region:GetFont()
                if fontFile then
                    region.origFontFile = fontFile
                    region.origFontSize = fontSize
                    region.origFontFlags = fontFlags
                end
            end
            
            if region.origFontSize then
                local newSize = region.origFontSize + delta
                newSize = math.max(6, newSize)
                local fontFile = OxedHub:GetFont(region.origFontFile)
                region:SetFont(fontFile, newSize, region.origFontFlags)
            end
        end
    end

    if frame:IsObjectType("Button") then
        local fs = frame:GetFontString()
        if fs then
            if not fs.origFontFile then
                local fontFile, fontSize, fontFlags = fs:GetFont()
                if fontFile then
                    fs.origFontFile = fontFile
                    fs.origFontSize = fontSize
                    fs.origFontFlags = fontFlags
                end
            end
            if fs.origFontSize then
                local newSize = fs.origFontSize + delta
                newSize = math.max(6, newSize)
                local fontFile = OxedHub:GetFont(fs.origFontFile)
                fs:SetFont(fontFile, newSize, fs.origFontFlags)
            end
        end
    elseif frame:IsObjectType("EditBox") then
        if not frame.origFontFile then
            local fontFile, fontSize, fontFlags = frame:GetFont()
            if fontFile then
                frame.origFontFile = fontFile
                frame.origFontSize = fontSize
                frame.origFontFlags = fontFlags
            end
        end
        if frame.origFontSize then
            local newSize = frame.origFontSize + delta
            newSize = math.max(6, newSize)
            local fontFile = OxedHub:GetFont(frame.origFontFile)
            frame:SetFont(fontFile, newSize, frame.origFontFlags)
        end
    end
    
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
        TraverseAndApplyTextSize(child, delta)
    end

    if frame:IsObjectType("ScrollFrame") then
        local scrollChild = frame:GetScrollChild()
        if scrollChild then
            TraverseAndApplyTextSize(scrollChild, delta)
        end
    end
end

function UI:ApplyGlobalTextSize()
    local offset = (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.textSizeOffset) or 0
    offset = tonumber(offset) or 0

    local function TryApplyToFrame(frame)
        if frame then
            if frame.SetScale then
                frame:SetScale(1.0)
            end
            TraverseAndApplyTextSize(frame, offset)
        end
    end

    if OxedHub.mainFrame then TryApplyToFrame(OxedHub.mainFrame) end
    if mainFrame then TryApplyToFrame(mainFrame) end

    local children = { UIParent:GetChildren() }
    for _, child in ipairs(children) do
        if child and type(child) == "table" and (not child.IsForbidden or not child:IsForbidden()) then
            local success, name = pcall(function() return child.GetName and child:GetName() end)
            if success and name and (string.find(name, "^OxedHub") or string.find(name, "^OxedRing")) then
                TryApplyToFrame(child)
            end
        end
    end
end

-- Initialize UI
function UI:Init()
    self:CreateMainFrame()
    self:CreateSidebar()
    self:CreateContentArea()
    self:CreateSearchBar()
    self:CreateToysTab()
    self:CreateOxedRingTab()
    self:CreateActionHubTab()
    self:CreateSettingsTab()
    self:CreateAboutTab()
    self:CreateExperimentalTab()
    self:ShowTab("Dashboard")
    
    self:ApplyGlobalTextSize()
end

-- Create main frame
function UI:CreateMainFrame()
    local frame = CreateFrame("Frame", "OxedHubMainFrame", UIParent, "ButtonFrameTemplate")
    frame:SetSize(CONFIG.MAIN_FRAME_WIDTH, CONFIG.MAIN_FRAME_HEIGHT)
    frame:SetFrameStrata("DIALOG")  -- Above ActionHub (HIGH) but below fullscreen dialogs
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    
    -- Set position
    local settings = OxedHub.db.profile.settings
    if settings and settings.hasCustomWindowPosition and settings.windowPosition then
        local x, y = ClampWindowPosition(
            settings.windowPosition.x or 0,
            settings.windowPosition.y or 0,
            CONFIG.MAIN_FRAME_WIDTH,
            CONFIG.MAIN_FRAME_HEIGHT
        )
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    
    if frame.SetTitle then
        frame:SetTitle(L["MINIMAP_TOOLTIP_TITLE"])
    end
    if frame.portrait then
        frame.portrait:SetTexture(nil)
        frame.portrait:Hide()
    end
    if frame.portraitFrame then
        frame.portraitFrame:SetTexture(nil)
        frame.portraitFrame:Hide()
    end
    if frame.PortraitContainer then
        frame.PortraitContainer:Hide()
    end
    if frame.TitleContainer then
        frame.TitleContainer:Hide()
        frame.TitleContainer.Show = frame.TitleContainer.Hide
    end
    if frame.Bg then
        frame.Bg:Hide()
        frame.Bg.Show = frame.Bg.Hide
    end

    -- Recursive cleaner to find and hide any leftover portrait textures/borders
    local function CleanPortraits(obj)
        if not obj then return end
        if obj.IsObjectType and obj:IsObjectType("Texture") then
            local tex = obj:GetTexture()
            local atlas = obj:GetAtlas()
            if (tex and tostring(tex):lower():find("portrait")) or 
               (atlas and tostring(atlas):lower():find("portrait")) then
                obj:SetTexture(nil)
                obj:Hide()
            end
        end
        local name = obj.GetName and obj:GetName() or ""
        if name:lower():find("portrait") then
            obj:Hide()
        end
        if obj.GetChildren then
            for _, child in ipairs({obj:GetChildren()}) do
                CleanPortraits(child)
            end
        end
        if obj.GetRegions then
            for _, region in ipairs({obj:GetRegions()}) do
                CleanPortraits(region)
            end
        end
    end
    CleanPortraits(frame)

    -- Intercept SetPoint on TitleContainer to prevent Blizzard from resetting the portrait offset
    if frame.TitleContainer then
        local origSetPoint = frame.TitleContainer.SetPoint
        frame.TitleContainer.SetPoint = function(self, point, relativeTo, relativePoint, xOfs, yOfs, ...)
            if point == "TOPLEFT" and xOfs and xOfs >= 40 and xOfs <= 70 then
                xOfs = 2
            end
            origSetPoint(self, point, relativeTo, relativePoint, xOfs, yOfs, ...)
        end
        -- Apply it immediately
        for i = 1, frame.TitleContainer:GetNumPoints() do
            local point, relativeTo, relativePoint, xOfs, yOfs = frame.TitleContainer:GetPoint(i)
            if point == "TOPLEFT" and xOfs and xOfs >= 40 and xOfs <= 70 then
                frame.TitleContainer:SetPoint(point, relativeTo, relativePoint, 2, yOfs)
            end
        end
    end

    -- Completely strip all default NineSlice textures to remove default Blizzard borders, backgrounds, and underlays
    if frame.NineSlice then
        for _, r in ipairs({ frame.NineSlice:GetRegions() }) do
            if r:IsObjectType("Texture") then
                r:SetTexture(nil)
                r:Hide()
                r.Show = r.Hide
            end
        end
    end

    -- Hide all other default textures directly on the frame
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:IsObjectType("Texture") then
            r:SetTexture(nil)
            r:Hide()
            r.Show = r.Hide
        end
    end
    if frame.CloseButton then
        frame.CloseButton:ClearAllPoints()
        frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -30) -- Moved 35px down and 5px left from default
        frame.CloseButton:SetScript("OnClick", function()
            UI:HideMainWindow()
        end)
    end
    tinsert(UISpecialFrames, frame:GetName())

    -- Drag functionality
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetLeft(), self:GetTop()
        OxedHub.db.profile.settings.windowPosition = { x = x, y = y }
        OxedHub.db.profile.settings.hasCustomWindowPosition = true
    end)
    frame:SetScript("OnHide", function()
        OxedHub.db.profile.settings.mainWindowVisible = false
    end)
    
    -- OLD LOGO (Commented out)
    --[[
    local portraitTex = frame:CreateTexture(nil, "ARTWORK")
    portraitTex:SetSize(72, 72)
    portraitTex:SetPoint("TOP", frame, "TOP", 40, 15)
    portraitTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\main-logo.tga")
    ]]

    -- NEW BANNER LOGO (Commented out)
    --[[
    local logoFrame = CreateFrame("Frame", nil, frame)
    logoFrame:SetSize(250, 113)
    logoFrame:SetPoint("TOP", frame, "TOP", 35, 30)
    logoFrame:SetFrameStrata("DIALOG")
    logoFrame:SetFrameLevel(500) -- Very high level to stay on top
    
    local mainLogo = logoFrame:CreateTexture(nil, "OVERLAY")
    mainLogo:SetAllPoints()
    mainLogo:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\main-logo2.tga")
    ]]

    -- CIRCULAR LOGO 1 ON THE LEFT
    local logoContainer = CreateFrame("Frame", nil, frame)
    logoContainer:SetSize(72, 72)
    logoContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", -18, 22)
    logoContainer:SetFrameLevel(frame:GetFrameLevel() + 20)
    logoContainer:Hide()
    
    -- Mask for circle
    local mask = logoContainer:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    
    -- Black Background (20% Transparent / 80% Opaque)
    local bg = logoContainer:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints()
    bg:SetVertexColor(0, 0, 0, 0.8)
    bg:AddMaskTexture(mask)
    
    -- Logo Texture
    local logoTex = logoContainer:CreateTexture(nil, "ARTWORK")
    logoTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")
    logoTex:SetSize(60, 60)
    logoTex:SetPoint("CENTER")
    logoTex:AddMaskTexture(mask)
    
    -- Ring Border
    local ring = logoContainer:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\ring")
    ring:SetAllPoints()
    ring:SetVertexColor(1, 0.9, 0.6) -- Golden glow style

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    titleBar:SetHeight(30)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
    closeBtn:SetSize(24, 24)
    closeBtn:SetScript("OnClick", function()
        UI:HideMainWindow()
    end)
    closeBtn:Hide()
    
    local mainTitle = frame:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    mainTitle:SetPoint("TOP", frame, "TOP", 3, -15)
    mainTitle:SetText(L["MINIMAP_TOOLTIP_TITLE"])
    mainTitle:SetTextColor(1, 0.82, 0) -- Classic WoW gold
    mainTitle:Hide()
    
    frame.titleBar = titleBar
    mainFrame = frame
    OxedHub.mainFrame = frame
    
    -- Main overlay
    local mainOverlay = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    mainOverlay:SetPoint("TOPLEFT", frame, "TOPLEFT", -11, 17)
    mainOverlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, -1)
    mainOverlay:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\main-overlay.tga")
    
    -- Hide by default - will be shown based on settings
    frame:Hide()
end

-- Create sidebar
function UI:CreateSidebar()
    if not mainFrame then return end
    
    sidebar = CreateFrame("Frame", nil, mainFrame)
    sidebar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -65)
    sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 10, 30)
    sidebar:SetWidth(CONFIG.SIDEBAR_WIDTH)
    sidebar:SetFrameStrata("DIALOG")
    sidebar:SetFrameLevel(mainFrame:GetFrameLevel() + 50)

    
    local tabs = { "Dashboard", "Triggers", "Reactions", "Toys", "OxedRing", "ActionHub", "Settings", "About" } -- , "Experimental"
    local yOffset = 0
    
    for i, tabName in ipairs(tabs) do
        local btn = CreateNavButton(sidebar, tabName, L["TAB_" .. tabName:upper()] or tabName)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, -yOffset)
        btn:SetFrameLevel(sidebar:GetFrameLevel() + 3)
        btn:SetScript("OnClick", function()
            UI:ShowTab(tabName)
        end)
        btn.tabName = tabName
        sidebar[tabName .. "Btn"] = btn
        
        -- Activate Dashboard button by default since it starts selected
        if tabName == "Dashboard" then
            btn:LockHighlight()
        end
        
        yOffset = yOffset + 34
    end
    
    -- Sidebar Logo (drawn in OVERLAY layer, sublevel 7 to stay on top of the animation)
    local sidebarLogo = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
    sidebarLogo:SetSize(115, 115)  -- 10% smaller than original 128x128
    sidebarLogo:SetPoint("BOTTOM", sidebar, "BOTTOM", -3, 80)
    sidebarLogo:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")

    -- Runes Animation under the logo (drawn in ARTWORK layer, sublevel -7 to stay under the logo)
    local runesAnim = sidebar:CreateTexture(nil, "ARTWORK", nil, -7)
    runesAnim:SetPoint("TOP", sidebarLogo, "BOTTOM", 3, 355)  -- +3 compensates for logo's -3 shift
    runesAnim:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\RunesAnimation\\main-overlay-without-dragon-_00000.png")
    runesAnim:SetSize(223.6, 444.7)
    runesAnim:SetAlpha(1)

    -- Preload all animation frames to prevent flickering (VRAM resident, parented to UIParent so textures stay in memory)
    local preload = CreateFrame("Frame", "OxedHubPreloader", UIParent)
    preload:SetSize(1, 1)
    preload:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
    preload:SetAlpha(0.001)
    preload:Show()
    
    UI.preloader = {}
    for i = 0, 62 do
        local preloadTex = preload:CreateTexture(nil, "OVERLAY")
        preloadTex:SetSize(1, 1)
        preloadTex:SetAllPoints(preload)
        preloadTex:SetTexture(string.format(
            "Interface\\AddOns\\OxedHub\\Media\\Textures\\RunesAnimation\\main-overlay-without-dragon-_%05d.png", i))
        preloadTex:Show()
        table.insert(UI.preloader, preloadTex)
    end

    -- Preload big static background and UI button textures to prevent flickering/blinking
    local staticTextures = {
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\assignments.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\dashboard-bg.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\main-overlay.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg-low.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\main-logo.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\main-logo2.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\ring",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\dashboard.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\triggers.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\actions.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\toys.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\oxedring.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\actionhub.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\settings.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\about.png",
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\Minimap\\o-oxed-minimap.tga",
        "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorial-1.png",
        "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorila-2.png",
    }
    for _, path in ipairs(staticTextures) do
        local preloadTex = preload:CreateTexture(nil, "OVERLAY")
        preloadTex:SetSize(1, 1)
        preloadTex:SetAllPoints(preload)
        preloadTex:SetTexture(path)
        preloadTex:Show()
        table.insert(UI.preloader, preloadTex)
    end

    -- Preload RingAnimation frames (VRAM resident)
    for i = 1, 18 do
        local preloadTex = preload:CreateTexture(nil, "OVERLAY")
        preloadTex:SetSize(1, 1)
        preloadTex:SetAllPoints(preload)
        preloadTex:SetTexture(string.format(
            "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_%05d.png", i))
        preloadTex:Show()
        table.insert(UI.preloader, preloadTex)
    end

    -- Animate the runes under the logo
    sidebar.animFrame = 0
    sidebar.animTime = 0
    sidebar.pauseTime = 0
    sidebar:SetScript("OnUpdate", function(self, elapsed)
        if self.pauseTime and self.pauseTime > 0 then
            self.pauseTime = self.pauseTime - elapsed
            return
        end

        self.animTime = (self.animTime or 0) + elapsed
        local fps = 24 -- 24 frames per second
        local frameDuration = 1 / fps
        
        if self.animTime >= frameDuration then
            self.animTime = self.animTime - frameDuration
            self.animFrame = (self.animFrame or 0) + 1
            if self.animFrame > 62 then
                self.animFrame = 0
                self.pauseTime = 5 -- Pause for 5 seconds when animation completes
            end
            runesAnim:SetTexture(string.format(
                "Interface\\AddOns\\OxedHub\\Media\\Textures\\RunesAnimation\\main-overlay-without-dragon-_%05d.png", self.animFrame))
        end
    end)

    -- Status text at bottom
    local statusText = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", runesAnim, "BOTTOM", -7, 0)  -- 7px left total
    statusText:SetText("|cff888888v" .. CONFIG.VERSION .. "|r")
end

-- Create content area
function UI:CreateContentArea()
    if not mainFrame then return end
    
    contentArea = CreateFrame("Frame", nil, mainFrame, "InsetFrameTemplate")
    contentArea:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", CONFIG.SIDEBAR_WIDTH + 20, -60)
    contentArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 30)
    contentArea:SetFrameLevel(mainFrame:GetFrameLevel() + 2)
    contentArea:SetFrameStrata("DIALOG")
    
    -- Create tab contents (initially hidden)
    self:CreateDashboardTab()
    self:CreateTriggersTab()
    self:CreateReactionsTab()
end

-- Create search bar
function UI:CreateSearchBar()
    if not mainFrame then return end
    
    local searchContainer = CreateFrame("Frame", nil, mainFrame)
    searchContainer:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -86, -110)
    searchContainer:SetSize(280, 25)
    
    -- Search input
    searchBox = CreateFrame("EditBox", "OxedHubSearchBox", searchContainer, "SearchBoxTemplate")
    self.searchBox = searchBox
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("RIGHT", searchContainer, "RIGHT", 0, 0)
    searchBox:SetAutoFocus(false)

    local searchTimer
    searchBox:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        if searchTimer then searchTimer:Cancel() end

        local text = self:GetText()
        local lowerText = text and text:lower() or ""
        UpdateSearchPlaceholderVisibility(self)

        OxedHub.globalSearchText = lowerText

        if self.customSearchHandler then
            self.customSearchHandler(self, text)
            return
        end

        -- Debounce search updates with a timer
        searchTimer = C_Timer.NewTimer(0.15, function()
            local handled = false
            if currentTab == "Reactions" then
                if contentArea.Reactions.currentSubTab == "Sounds" and OxedHub.Sounds and OxedHub.Sounds.currentScrollChild then
                    OxedHub.Sounds:RefreshSoundList(OxedHub.Sounds.currentScrollChild)
                    handled = true
                elseif contentArea.Reactions.currentSubTab == "Chat" and OxedHub.ChatMessages and OxedHub.ChatMessages.currentScrollChild then
                    OxedHub.ChatMessages:RefreshChatList(OxedHub.ChatMessages.currentScrollChild)
                    handled = true
                elseif contentArea.Reactions.currentSubTab == "Animations" and OxedHub.Animations and OxedHub.Animations.currentScrollChild then
                    OxedHub.Animations:RefreshAnimationList(OxedHub.Animations.currentScrollChild)
                    handled = true
                end
            elseif currentTab == "Triggers" then
                if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then
                    OxedHub.Triggers:RefreshTriggersList()
                    handled = true
                end
            end

            if not handled then
                if text and #text > 0 then
                    if OxedHub.Search then
                        OxedHub.Search:Search(text)
                    end
                else
                    if OxedHub.Search then
                        OxedHub.Search:ClearResults()
                    end
                end
            else
                if OxedHub.Search then
                    OxedHub.Search:ClearResults()
                end
            end
        end)
    end)
    ApplySearchFrameStyle(searchBox)
    UpdateSearchPlaceholderVisibility(searchBox)
end

-- Create Dashboard tab
function UI:CreateDashboardTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(1)
    ApplyToysBackground(tab)

    local scrollFrame = CreateFrame("ScrollFrame", nil, tab)
    scrollFrame:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -THEMED_FRAME_INSETS.top)
    scrollFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(992, 586)
    scrollFrame:SetScrollChild(scrollChild)

    local hero = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    hero:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
    hero:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -5, -5)
    hero:SetHeight(118)
    ApplyDashboardCardBackdrop(hero, 0.95)

    local heroTitle = hero:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    heroTitle:SetPoint("TOPLEFT", hero, "TOPLEFT", 16, -14)
    heroTitle:SetTextColor(1, 0.82, 0, 1)
    heroTitle:SetText(L["DASHBOARD_TITLE"])

    local heroSubtitle = hero:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    heroSubtitle:SetPoint("TOPLEFT", heroTitle, "BOTTOMLEFT", 0, -8)
    heroSubtitle:SetPoint("RIGHT", hero, "RIGHT", -16, 0)
    heroSubtitle:SetJustifyH("LEFT")
    heroSubtitle:SetTextColor(0.82, 0.82, 0.82, 1)
    heroSubtitle:SetText(L["DASHBOARD_SUBTITLE"])

    local heroMeta = hero:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroMeta:SetPoint("TOPLEFT", heroSubtitle, "BOTTOMLEFT", 0, -10)
    heroMeta:SetPoint("RIGHT", hero, "RIGHT", -16, 0)
    heroMeta:SetJustifyH("LEFT")
    heroMeta:SetTextColor(0.65, 0.65, 0.65, 1)
    heroMeta:SetText("")

    -- Profile switcher on the right side of the hero card
    local profileLabel = hero:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    profileLabel:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -16, -14)
    profileLabel:SetJustifyH("RIGHT")
    profileLabel:SetTextColor(1, 0.82, 0, 1)
    profileLabel:SetText(L["DASHBOARD_PROFILE_LABEL"])

    local profileDropdown = CreateFrame("DropdownButton", nil, hero, "WowStyle1DropdownTemplate")
    if not profileDropdown then
        profileDropdown = CreateFrame("Button", nil, hero, "UIDropDownMenuTemplate")
    end
    profileDropdown:SetPoint("TOPRIGHT", profileLabel, "BOTTOMRIGHT", 6, -4)
    profileDropdown:SetWidth(160)

    local function RefreshProfileDropdown()
        if not profileDropdown then return end
        local activeName = OxedHub and OxedHub.GetActiveProfileName and OxedHub:GetActiveProfileName() or "Default"
        if profileDropdown.SetupMenu then
            -- WowStyle1DropdownTemplate (modern)
            profileDropdown:SetupMenu(function(_, rootDescription)
                if OxedHub and OxedHub.GetProfileList then
                    for _, name in ipairs(OxedHub:GetProfileList()) do
                        local displayName = OxedHub.GetProfileColoredName and OxedHub:GetProfileColoredName(name)
                            or (OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(name))
                            or name
                        local radio = rootDescription:CreateRadio(
                            displayName,
                            function() return OxedHub:GetActiveProfileName() == name end,
                            function()
                                OxedHub:SwitchProfile(name)
                                RefreshProfileDropdown()
                            end
                        )
                        -- Hover tooltip: show where this profile's content was imported from.
                        local pdb = OxedHubDB and OxedHubDB.profiles and OxedHubDB.profiles[name]
                        local origin = pdb and UI.GetProfileOriginText and UI:GetProfileOriginText(pdb)
                        if origin and radio and radio.SetTooltip then
                            radio:SetTooltip(function(tooltip)
                                if tooltip and tooltip.AddLine then
                                    for line in origin:gmatch("[^\n]+") do tooltip:AddLine(line, 1, 1, 1, true) end
                                end
                            end)
                        end
                    end
                end
            end)
            -- Set button label to active profile name
            if profileDropdown.SetText then
                local displayName = OxedHub.GetProfileColoredName and OxedHub:GetProfileColoredName(activeName)
                    or (OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(activeName))
                    or activeName
                profileDropdown:SetText(displayName)
            end
        else
            -- Legacy UIDropDownMenuTemplate fallback
            local function ColoredProfileName(name)
                return (OxedHub.GetProfileColoredName and OxedHub:GetProfileColoredName(name))
                    or (OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(name))
                    or name
            end
            UIDropDownMenu_SetWidth(profileDropdown, 150)
            UIDropDownMenu_SetText(profileDropdown, ColoredProfileName(activeName))
            UIDropDownMenu_Initialize(profileDropdown, function(self, level)
                if OxedHub and OxedHub.GetProfileList then
                    for _, name in ipairs(OxedHub:GetProfileList()) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = ColoredProfileName(name)
                        info.checked = (name == activeName)
                        info.func = function()
                            OxedHub:SwitchProfile(name)
                            UIDropDownMenu_SetText(profileDropdown, ColoredProfileName(name))
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end)
        end
    end

    RefreshProfileDropdown()
    -- Expose so SwitchProfile can call it
    UI.RefreshProfileDropdown = RefreshProfileDropdown

    local triggersBtn = CreateFrame("Button", nil, hero, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(triggersBtn)
    triggersBtn:SetSize(120, 24)
    triggersBtn:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 14, 12)
    triggersBtn:SetText(L["DASHBOARD_BTN_TRIGGERS"])
    triggersBtn:SetScript("OnClick", function()
        UI:ShowTab("Triggers")
    end)

    local reactionsBtn = CreateFrame("Button", nil, hero, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(reactionsBtn)
    reactionsBtn:SetSize(110, 24)
    reactionsBtn:SetPoint("LEFT", triggersBtn, "RIGHT", 8, 0)
    reactionsBtn:SetText(L["DASHBOARD_BTN_ACTIONS"])
    reactionsBtn:SetScript("OnClick", function()
        UI:ShowTab("Reactions")
    end)

    local toysBtn = CreateFrame("Button", nil, hero, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(toysBtn)
    toysBtn:SetSize(90, 24)
    toysBtn:SetPoint("LEFT", reactionsBtn, "RIGHT", 8, 0)
    toysBtn:SetText(L["DASHBOARD_BTN_TOYS"])
    toysBtn:SetScript("OnClick", function()
        UI:ShowTab("Toys")
    end)

    local settingsBtn = CreateFrame("Button", nil, hero, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(settingsBtn)
    settingsBtn:SetSize(90, 24)
    settingsBtn:SetPoint("LEFT", toysBtn, "RIGHT", 8, 0)
    settingsBtn:SetText(L["DASHBOARD_BTN_SETTINGS"])
    settingsBtn:SetScript("OnClick", function()
        UI:ShowTab("Settings")
    end)

    local animSwitch = CreateFrame("CheckButton", nil, hero, "UICheckButtonTemplate")
    animSwitch:SetPoint("LEFT", settingsBtn, "RIGHT", 15, 0)
    animSwitch:SetSize(26, 26)
    
    local animSwitchText = animSwitch:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    animSwitchText:SetPoint("LEFT", animSwitch, "RIGHT", 4, 1)
    
    animSwitch:SetScript("OnShow", function(self)
        if OxedHub.db.profile.animationsEnabled == nil then
            OxedHub.db.profile.animationsEnabled = true
        end
        self:SetChecked(OxedHub.db.profile.animationsEnabled)
        if self:GetChecked() then
            animSwitchText:SetText("|cff00ff00Animations: On|r")
        else
            animSwitchText:SetText("|cff888888Animations: Off|r")
        end
    end)
    
    animSwitch:SetScript("OnClick", function(self)
        local isEnabled = self:GetChecked()
        OxedHub.db.profile.animationsEnabled = isEnabled
        if isEnabled then
            animSwitchText:SetText("|cff00ff00Animations: On|r")
            print("|cffffd100OxedHub:|r Animations have been turned |cff00ff00ON|r")
        else
            animSwitchText:SetText("|cff888888Animations: Off|r")
            print("|cffffd100OxedHub:|r Animations have been turned |cffff0000OFF|r")
        end
    end)

    local soundSwitch = CreateFrame("CheckButton", nil, hero, "UICheckButtonTemplate")
    soundSwitch:SetPoint("LEFT", animSwitchText, "RIGHT", 15, -1)
    soundSwitch:SetSize(26, 26)
    
    local soundSwitchText = soundSwitch:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    soundSwitchText:SetPoint("LEFT", soundSwitch, "RIGHT", 4, 1)
    
    soundSwitch:SetScript("OnShow", function(self)
        if OxedHub.db.profile.soundsEnabled == nil then
            OxedHub.db.profile.soundsEnabled = true
        end
        self:SetChecked(OxedHub.db.profile.soundsEnabled)
        if self:GetChecked() then
            soundSwitchText:SetText("|cff00ff00Sounds: On|r")
        else
            soundSwitchText:SetText("|cff888888Sounds: Off|r")
        end
    end)
    
    soundSwitch:SetScript("OnClick", function(self)
        local isEnabled = self:GetChecked()
        OxedHub.db.profile.soundsEnabled = isEnabled
        if isEnabled then
            soundSwitchText:SetText("|cff00ff00Sounds: On|r")
            print("|cffffd100OxedHub:|r Sounds have been turned |cff00ff00ON|r")
        else
            soundSwitchText:SetText("|cff888888Sounds: Off|r")
            print("|cffffd100OxedHub:|r Sounds have been turned |cffff0000OFF|r")
        end
    end)

    local statsRow = CreateFrame("Frame", nil, scrollChild)
    statsRow:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -12)
    statsRow:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, -12)
    statsRow:SetHeight(58)

    local stat1 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_ACTIVE_TRIGGERS"], 160)
    stat1:SetPoint("TOPLEFT", statsRow, "TOPLEFT", 0, 0)

    local stat2 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_DISABLED_TRIGGERS"], 160)
    stat2:SetPoint("LEFT", stat1, "RIGHT", 8, 0)

    local stat3 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_EVENTS"], 160)
    stat3:SetPoint("LEFT", stat2, "RIGHT", 8, 0)

    local stat4 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_PROFILES"], 160)
    stat4:SetPoint("LEFT", stat3, "RIGHT", 8, 0)

    local stat5 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_SOUNDS"] or "Custom Sounds", 160)
    stat5:SetPoint("LEFT", stat4, "RIGHT", 8, 0)

    local stat6 = CreateDashboardStatCard(statsRow, L["DASHBOARD_STAT_ANIMATIONS"] or "Animations", 160)
    stat6:SetPoint("LEFT", stat5, "RIGHT", 8, 0)

    local summaryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    summaryText:SetPoint("TOPLEFT", statsRow, "BOTTOMLEFT", 0, -22)
    summaryText:SetPoint("RIGHT", scrollChild, "RIGHT", -5, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetTextColor(0.72, 0.72, 0.72, 1)
    summaryText:SetText(L["DASHBOARD_SUMMARY_TEXT"])

    -- ═══════════════════════════════════════════════════════════════
    -- ═══════════════════════════════════════════════════════════════
    -- Player Model Showcase Slider Section
    -- ═══════════════════════════════════════════════════════════════
    local showcaseContainer = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    showcaseContainer:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 5, -15)
    showcaseContainer:SetPoint("RIGHT", scrollChild, "RIGHT", -5, 0)
    showcaseContainer:SetHeight(330)

    local showcaseBg = showcaseContainer:CreateTexture(nil, "BACKGROUND")
    showcaseBg:SetAllPoints()
    showcaseBg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\dashboard-bg.tga")

    -- Horizontal ScrollFrame for sliding
    local sliderScroll = CreateFrame("ScrollFrame", nil, showcaseContainer)
    sliderScroll:SetPoint("TOPLEFT", showcaseContainer, "TOPLEFT", 10, -10)
    sliderScroll:SetPoint("BOTTOMRIGHT", showcaseContainer, "BOTTOMRIGHT", -10, 30)
    sliderScroll:EnableMouse(true)
    sliderScroll:SetClipsChildren(true)

    local sliderContent = CreateFrame("Frame", nil, sliderScroll)
    sliderScroll:SetScrollChild(sliderContent)

    local cards = {}
    local numCards = 5
    local activeCardIndex = 1

    -- Default inner dimensions (updated dynamically by OnSizeChanged)
    local defaultInnerW = 962
    local defaultInnerH = 290
    sliderContent:SetSize(defaultInnerW * numCards, defaultInnerH)

    -- Left Navigation Arrow Button
    local prevBtn = CreateFrame("Button", nil, showcaseContainer)
    prevBtn:SetSize(32, 32)
    prevBtn:SetPoint("LEFT", showcaseContainer, "LEFT", 12, -10)
    prevBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    prevBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
    prevBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled")
    prevBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    prevBtn:SetFrameLevel(showcaseContainer:GetFrameLevel() + 20)

    -- Right Navigation Arrow Button
    local nextBtn = CreateFrame("Button", nil, showcaseContainer)
    nextBtn:SetSize(32, 32)
    nextBtn:SetPoint("RIGHT", showcaseContainer, "RIGHT", -12, -10)
    nextBtn:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    nextBtn:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    nextBtn:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    nextBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    nextBtn:SetFrameLevel(showcaseContainer:GetFrameLevel() + 20)

    -- Pagination Dots Container
    local dotsContainer = CreateFrame("Frame", nil, showcaseContainer)
    dotsContainer:SetSize(100, 20)
    dotsContainer:SetPoint("BOTTOM", showcaseContainer, "BOTTOM", 0, 8)
    dotsContainer:SetFrameLevel(showcaseContainer:GetFrameLevel() + 20)

    local dots = {}
    for idx = 1, numCards do
        local dot = CreateFrame("Button", nil, dotsContainer)
        dot:SetSize(14, 14)
        dot:SetPoint("CENTER", dotsContainer, "CENTER", (idx - (numCards + 1) / 2) * 20, 0)
        
        local dotTex = dot:CreateTexture(nil, "BACKGROUND")
        dotTex:SetAllPoints()
        dotTex:SetTexture("Interface\\Buttons\\UI-RadioButton")
        dotTex:SetTexCoord(0, 0.25, 0, 1) -- default unselected
        dot.tex = dotTex
        
        dot:SetScript("OnClick", function()
            UI:SetDashboardCard(idx, true)
        end)
        dots[idx] = dot
    end

    -- Create individual card frames with initial default sizes
    for i = 1, numCards do
        local card = CreateFrame("Frame", nil, sliderContent)
        card:SetFrameLevel(sliderScroll:GetFrameLevel() + 1)
        card:SetSize(defaultInnerW, defaultInnerH)
        card:SetPoint("TOPLEFT", sliderContent, "TOPLEFT", (i - 1) * defaultInnerW, 0)
        table.insert(cards, card)
    end

    local card1 = cards[1]
    local card2 = cards[2]
    local card3 = cards[3]
    local card4 = cards[4]
    local card5 = cards[5]

    -- Responsive resizing of cards and content
    showcaseContainer:SetScript("OnSizeChanged", function(self, width, height)
        if not width or width <= 0 then return end
        
        local innerWidth = width - 20
        local innerHeight = height - 40
        
        sliderContent:SetSize(innerWidth * numCards, innerHeight)
        
        for idx, card in ipairs(cards) do
            card:ClearAllPoints()
            card:SetSize(innerWidth, innerHeight)
            card:SetPoint("TOPLEFT", sliderContent, "TOPLEFT", (idx - 1) * innerWidth, 0)
        end
        
        sliderScroll:SetHorizontalScroll((activeCardIndex - 1) * innerWidth)
    end)

    -- ───────────────────────────────────────────────────────────────
    -- CARD 1: RELEASE NOTES (RELEASE 2.3.39)
    -- ───────────────────────────────────────────────────────────────
    local relTitle = card1:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    relTitle:SetPoint("TOP", card1, "TOP", 0, -12)
    relTitle:SetTextColor(1, 0.82, 0, 1)
    relTitle:SetText(L["RELEASE_TITLE"] or "Release 2.3.39")
    local rName, rHeight, rFlags = relTitle:GetFont()
    if rName then relTitle:SetFont(rName, rHeight * 1.1, rFlags) end

    local relSubtitle = card1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    relSubtitle:SetPoint("TOP", relTitle, "BOTTOM", 0, -4)
    relSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    relSubtitle:SetText(L["RELEASE_SUBTITLE"] or "What's New in this Update")

    local relLines = {
        "•  Chat Share: share anything in chat - triggers, rings, toy mixes, hubs & profiles.",
        "•  Prey Hunt Tracker (Beta / Test Mode): on-screen HUD bar & Blizzard widget mover.",
        "•  Anti-AFK Tracker (Beta / Test Mode): on-screen timers & customizable sound alerts.",
        "•  Disenchant Insight (Basic Trigger): Tooltip advice, expected value vs vendor & AH prices!",
        "•  ToyBoxes: Custom boxes, on-screen floating dock, random hearthstones & quick mixer.",
        "•  Click buttons to quickly setup triggers, copy Meme Pack link, or open ToyBoxes:",
    }

    local listPanel = CreateFrame("Frame", nil, card1)
    listPanel:SetSize(620, 200)
    listPanel:SetPoint("TOPLEFT", card1, "TOPLEFT", 45, -70)

    for idx, lineText in ipairs(relLines) do
        local lineFS = listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lineFS:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 10, -((idx - 1) * 32))
        lineFS:SetPoint("RIGHT", listPanel, "RIGHT", -10, 0)
        lineFS:SetJustifyH("LEFT")
        lineFS:SetText(lineText)
        lineFS:SetTextColor(0.1, 0.1, 0.1, 1) -- Dark/Black color for readability
        lineFS:SetShadowOffset(0, 0) -- Remove default shadow to prevent blurry/double text effect
        
        if idx == 6 then
            -- Setup Disenchant Insight Trigger Button
            local setupInsightBtn = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")
            setupInsightBtn:SetSize(115, 22)
            setupInsightBtn:SetPoint("LEFT", listPanel, "TOPLEFT", 14, -((idx) * 32) + 2)
            setupInsightBtn:SetText("Setup Disenchant")
            setupInsightBtn:SetNormalFontObject("GameFontNormalSmall")
            setupInsightBtn:SetScript("OnClick", function()
                local trigger = OxedHub.Triggers:CreateNewTrigger()
                trigger.name = "Disenchant Insight"
                trigger.event = "SHATTERSIGHT"
                trigger.conditions = { enableTooltip = true, showBreakdown = true, autoScan = true }
                OxedHub.Triggers.selectedTriggerId = trigger.id
                OxedHub.Triggers:RefreshTriggersList()
                OxedHub.UI:ShowTab("Triggers")
            end)

            -- Meme Pack Link Button
            local memeLinkBtn = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")
            memeLinkBtn:SetSize(115, 22)
            memeLinkBtn:SetPoint("LEFT", setupInsightBtn, "RIGHT", 8, 0)
            memeLinkBtn:SetText("Meme Pack Link")
            memeLinkBtn:SetNormalFontObject("GameFontNormalSmall")
            memeLinkBtn:SetScript("OnClick", function()
                if not StaticPopupDialogs["OXEDHUB_MEMEPACK_URL"] then
                    StaticPopupDialogs["OXEDHUB_MEMEPACK_URL"] = {
                        text = "Copy CurseForge Meme Pack link (Ctrl+C):",
                        button1 = "Done",
                        hasEditBox = true,
                        OnShow = function(dialog)
                            dialog.EditBox:SetText("https://www.curseforge.com/wow/addons/oxed-hub-meme-pack")
                            dialog.EditBox:HighlightText()
                            dialog.EditBox:SetFocus()
                        end,
                        EditBoxOnEscapePressed = function(dialog)
                            dialog:GetParent():Hide()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                        preferredIndex = 3,
                    }
                end
                StaticPopup_Show("OXEDHUB_MEMEPACK_URL")
            end)

            -- Open ToyBox Button
            local toyBoxBtn = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")
            toyBoxBtn:SetSize(105, 22)
            toyBoxBtn:SetPoint("LEFT", memeLinkBtn, "RIGHT", 8, 0)
            toyBoxBtn:SetText("Open ToyBox")
            toyBoxBtn:SetNormalFontObject("GameFontNormalSmall")
            toyBoxBtn:SetScript("OnClick", function()
                OxedHub.UI:ShowTab("Toys")
                -- Was calling Toys:SwitchSubTab, which does not exist -- the
                -- guard made it a silent no-op, so this only ever opened the
                -- Toys tab on whatever sub-tab happened to be active.
                OxedHub.UI:ShowToysSubTab("ToyBoxes")
            end)
        end
    end

    local memePackBtn = CreateFrame("Button", nil, card1)
    memePackBtn:SetSize(220, 220)
    memePackBtn:SetPoint("RIGHT", card1, "RIGHT", -60, -10)
    
    local memePackImg = memePackBtn:CreateTexture(nil, "ARTWORK")
    memePackImg:SetAllPoints()
    memePackImg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\OxedHubMemePack.png")
    
    memePackBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("OxedHub Meme Pack", 1, 0.82, 0)
        GameTooltip:AddLine("Click to copy CurseForge link", 1, 1, 1)
        GameTooltip:Show()
    end)
    memePackBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    memePackBtn:SetScript("OnClick", function()
        if not StaticPopupDialogs["OXEDHUB_MEMEPACK_URL"] then
            StaticPopupDialogs["OXEDHUB_MEMEPACK_URL"] = {
                text = "Copy CurseForge Meme Pack link (Ctrl+C):",
                button1 = "Done",
                hasEditBox = true,
                OnShow = function(dialog)
                    dialog.EditBox:SetText("https://www.curseforge.com/wow/addons/oxed-hub-meme-pack")
                    dialog.EditBox:HighlightText()
                    dialog.EditBox:SetFocus()
                end,
                EditBoxOnEscapePressed = function(dialog)
                    dialog:GetParent():Hide()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        StaticPopup_Show("OXEDHUB_MEMEPACK_URL")
    end)

    -- ───────────────────────────────────────────────────────────────
    -- CARD 2: CHARACTER SHOWCASE
    -- ───────────────────────────────────────────────────────────────
    local showcaseTitle = card2:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    showcaseTitle:SetPoint("TOP", card2, "TOP", 0, -12)
    showcaseTitle:SetTextColor(1, 0.82, 0, 1)
    showcaseTitle:SetText(L["SHOWCASE_TITLE"])
    local fName, fHeight, fFlags = showcaseTitle:GetFont()
    if fName then showcaseTitle:SetFont(fName, fHeight * 1.1, fFlags) end

    local showcaseSubtitle = card2:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    showcaseSubtitle:SetPoint("TOP", showcaseTitle, "BOTTOM", 0, -4)
    showcaseSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    showcaseSubtitle:SetText(L["SHOWCASE_SUBTITLE"])

    -- 3D Player Model
    local modelFrame = CreateFrame("PlayerModel", nil, card2)
    modelFrame:SetSize(200, 250)
    modelFrame:SetPoint("CENTER", card2, "CENTER", -230, -15)
    modelFrame:SetUnit("player")
    modelFrame:SetRotation(math.rad(-15))
    modelFrame:SetPortraitZoom(0)
    modelFrame:SetCamDistanceScale(1.2)
    modelFrame:SetFrameLevel(card2:GetFrameLevel() + 2)

    -- Ensure showcase state is persisted
    if not OxedHub.db.profile.showcaseSlots then
        OxedHub.db.profile.showcaseSlots = { tl = nil, tr = nil, bl = nil, br = nil }
    end
    local showcaseSlots = OxedHub.db.profile.showcaseSlots

    if not OxedHub.db.profile.showcaseIndices then
        OxedHub.db.profile.showcaseIndices = { tl = 1, tr = 1, bl = 1, br = 1 }
    end
    local showcaseIndices = OxedHub.db.profile.showcaseIndices

    -- Slot types and labels with predefined values
    local SLOT_DEFS = {
        {
            key = "tl",
            label = L["TAB_SOUND"] or "Sound",
            defaultIcon = "Interface\\Icons\\INV_Misc_Horn_01",
            options = {
                { value = "Dance", icon = "Interface\\Icons\\INV_Misc_Horn_01", sound = "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorial-1.mp3" },
                { value = "Eat",   icon = "Interface\\Icons\\INV_Misc_Food_15", sound = "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorial-2.mp3" }
            }
        },
        {
            key = "tr",
            label = L["TAB_ANIMATION"] or "Animation",
            defaultIcon = "Interface\\Icons\\Ability_Rogue_Sprint",
            options = {
                { value = "Piggie",  icon = "Interface\\Icons\\Ability_Rogue_Sprint", texture = "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorial-1.png", cols = 20, rows = 19, totalFrames = 368 },
                { value = "Goat",    icon = "Interface\\Icons\\INV_Pet_GnomereganHarvester", texture = "Interface\\AddOns\\OxedHub\\Media\\Tutorial\\tutorila-2.png", cols = 13, rows = 13, totalFrames = 160 }
            }
        },
        {
            key = "bl",
            label = L["TAB_EMOTE"] or "Emote",
            defaultIcon = "Interface\\Icons\\UI_Chat",
            options = {
                { value = "Dance", icon = "Interface\\Icons\\UI_Chat", emote = "DANCE", anim = 69 },
                { value = "Eat",   icon = "Interface\\Icons\\INV_Misc_Food_15", emote = "EAT", anim = 61, duration = 2.0 }
            }
        },
        {
            key = "br",
            label = L["TAB_CHAT"] or "Text",
            defaultIcon = "Interface\\Icons\\INV_Misc_Note_01",
            options = {
                { value = "OxedHub Banger", icon = "Interface\\Icons\\INV_Misc_Note_01", text = "OxedHub is A Banger!" },
                { value = "Eat Text",       icon = "Interface\\Icons\\INV_Misc_Note_02", text = "Nom Nom Nom!" }
            }
        }
    }

    local slotFrames = {}
    local launchBtn -- forward declare
    local UpdateFirstAnimFrame -- forward declare
    local launchPlaying = false
    local currentSoundHandle
    local emoteTimer

    local function UpdateLaunchState()
        if not launchBtn then return end

        local cycleEnabled = not launchPlaying
        for _, slot in pairs(slotFrames) do
            if slot.prevBtn then slot.prevBtn:SetEnabled(cycleEnabled) end
            if slot.nextBtn then slot.nextBtn:SetEnabled(cycleEnabled) end
        end

        if launchPlaying then
            launchBtn:SetEnabled(true)
            launchBtn:SetText(L["SHOWCASE_BTN_STOP"])
            return
        end
        local allActive = true
        for _, def in ipairs(SLOT_DEFS) do
            if not showcaseSlots[def.key] then
                allActive = false
                break
            end
        end
        if allActive then
            launchBtn:SetEnabled(true)
            launchBtn:SetText(L["SHOWCASE_BTN_LAUNCH"])
        else
            launchBtn:SetEnabled(false)
            launchBtn:SetText(L["SHOWCASE_BTN_LAUNCH"])
        end
    end

    local function CreateSlotButton(parent, def, anchor, xOff, yOff)
        local slot = CreateFrame("Button", nil, parent, "BackdropTemplate")
        slot:SetSize(140, 54)
        slot:SetPoint(anchor, modelFrame, anchor, xOff, yOff)
        slot:SetFrameLevel(parent:GetFrameLevel() + 5)
        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })

        local iconTex = slot:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(36, 36)
        iconTex:SetPoint("LEFT", slot, "LEFT", 10, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.iconTex = iconTex

        local slotLabel = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slotLabel:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, -4)
        slotLabel:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetTextColor(0.7, 0.7, 0.7, 1)
        slotLabel:SetText(def.label)
        slot.slotLabel = slotLabel

        local slotValue = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        slotValue:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -2)
        slotValue:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
        slotValue:SetJustifyH("LEFT")
        slot.slotValue = slotValue

        -- Flanking Left/Right cycle buttons
        local prevBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        prevBtn:SetSize(18, 30)
        prevBtn:SetPoint("RIGHT", slot, "LEFT", -4, 0)
        prevBtn:SetText("<")
        prevBtn:SetFrameLevel(slot:GetFrameLevel() + 5)
        slot.prevBtn = prevBtn

        local nextBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        nextBtn:SetSize(18, 30)
        nextBtn:SetPoint("LEFT", slot, "RIGHT", 4, 0)
        nextBtn:SetText(">")
        nextBtn:SetFrameLevel(slot:GetFrameLevel() + 5)
        slot.nextBtn = nextBtn

        -- Floating status message above the slot
        local statusText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusText:SetPoint("BOTTOM", slot, "TOP", 0, 4)
        statusText:Hide()
        slot.statusText = statusText

        -- Hover highlight
        slot:SetScript("OnEnter", function(self)
            local idx = showcaseIndices[def.key] or 1
            local opt = def.options[idx]
            self:SetBackdropBorderColor(1, 0.82, 0, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(def.label, 1, 0.82, 0)
            GameTooltip:AddLine(L["SHOWCASE_TOOLTIP_VALUE"] .. opt.value, 1, 1, 1)
            if showcaseSlots[def.key] then
                GameTooltip:AddLine(L["SHOWCASE_TOOLTIP_STATUS"] .. "|cff00ff00" .. L["SHOWCASE_STATUS_ACTIVATED"] .. "|r", 1, 1, 1)
                GameTooltip:AddLine(L["SHOWCASE_TOOLTIP_CLICK_DEACTIVATE"], 0.6, 0.6, 0.6)
            else
                GameTooltip:AddLine(L["SHOWCASE_TOOLTIP_STATUS"] .. "|cffff0000" .. L["SHOWCASE_STATUS_DEACTIVATED"] .. "|r", 1, 1, 1)
                GameTooltip:AddLine(L["SHOWCASE_TOOLTIP_CLICK_ACTIVATE"], 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function(self)
            if showcaseSlots[def.key] then
                self:SetBackdropBorderColor(0.3, 1, 0.3, 0.8)
            else
                self:SetBackdropBorderColor(0.5, 0.43, 0.25, 0.7)
            end
            GameTooltip:Hide()
        end)

        -- Refresh visual from saved state
        local function RefreshSlotVisual()
            local isActive = showcaseSlots[def.key]
            local idx = showcaseIndices[def.key] or 1
            local opt = def.options[idx]

            iconTex:SetTexture(def.defaultIcon)

            if isActive then
                slotValue:SetText("|cff00ff00" .. opt.value .. "|r")
                slot:SetBackdropColor(0.04, 0.04, 0.05, 0.75)
                slot:SetBackdropBorderColor(0.3, 1, 0.3, 0.8)
            else
                slotValue:SetText("|cff888888" .. opt.value .. "|r")
                slot:SetBackdropColor(0.04, 0.04, 0.05, 0.75)
                slot:SetBackdropBorderColor(0.5, 0.43, 0.25, 0.7)
            end
            if def.key == "tr" then
                UpdateFirstAnimFrame()
            end
            UpdateLaunchState()
        end
        slot.RefreshVisual = RefreshSlotVisual

        slot:SetScript("OnClick", function(self)
            if launchPlaying then return end
            local isActive = not showcaseSlots[def.key]
            showcaseSlots[def.key] = isActive or nil

            if isActive then
                statusText:SetText("|cff00ff00" .. L["SHOWCASE_STATUS_ACTIVATED"] .. "|r")
            else
                statusText:SetText("|cffff0000" .. L["SHOWCASE_STATUS_DEACTIVATED"] .. "|r")
            end
            statusText:Show()

            if slot.statusTimer then
                slot.statusTimer:Cancel()
            end
            slot.statusTimer = C_Timer.NewTimer(2, function()
                statusText:Hide()
            end)

            RefreshSlotVisual()
        end)

        prevBtn:SetScript("OnClick", function()
            local idx = showcaseIndices[def.key] or 1
            idx = idx - 1
            if idx < 1 then
                idx = #def.options
            end
            showcaseIndices[def.key] = idx
            RefreshSlotVisual()
        end)

        nextBtn:SetScript("OnClick", function()
            local idx = showcaseIndices[def.key] or 1
            idx = idx + 1
            if idx > #def.options then
                idx = 1
            end
            showcaseIndices[def.key] = idx
            RefreshSlotVisual()
        end)

        slotFrames[def.key] = slot
        RefreshSlotVisual()
        return slot
    end

    -- Inline animation container on the right side of the card
    local animContainer = CreateFrame("Frame", nil, card2)
    animContainer:SetSize(220, 260)
    animContainer:SetPoint("CENTER", card2, "CENTER", 320, -10)
    animContainer:SetFrameLevel(card2:GetFrameLevel() + 3)
    animContainer:SetClipsChildren(true)

    local animTex = animContainer:CreateTexture(nil, "ARTWORK")
    animTex:SetSize(220, 260)
    animTex:SetPoint("CENTER", animContainer, "CENTER", 0, 0)
    animTex:Hide()

    UpdateFirstAnimFrame = function()
        if not animTex then return end
        local animIdx = showcaseIndices["tr"] or 1
        local animOpt = SLOT_DEFS[2].options[animIdx]
        animTex:SetTexture(animOpt.texture)
        animTex:SetTexCoord(0, 1 / animOpt.cols, 0, 1 / animOpt.rows)
    end
    UpdateFirstAnimFrame()

    -- Create the 4 slot buttons around the character model
    local slotTL = CreateSlotButton(card2, SLOT_DEFS[1], "TOPRIGHT",    -170, -40)   -- Top-Left of model
    local slotTR = CreateSlotButton(card2, SLOT_DEFS[2], "TOPLEFT",      170, -40)   -- Top-Right of model
    local slotBL = CreateSlotButton(card2, SLOT_DEFS[3], "BOTTOMRIGHT", -170,  40)   -- Bottom-Left of model
    local slotBR = CreateSlotButton(card2, SLOT_DEFS[4], "BOTTOMLEFT",   170,  40)   -- Bottom-Right of model

    -- Launch Button (centered in the card between model and animation area)
    launchBtn = CreateFrame("Button", nil, card2, "UIPanelButtonTemplate")
    launchBtn:SetSize(140, 36)
    launchBtn:SetPoint("CENTER", card2, "CENTER", 125, -15)
    launchBtn:SetFrameLevel(card2:GetFrameLevel() + 5)
    launchBtn:SetText(L["SHOWCASE_BTN_LAUNCH"])
    launchBtn:SetEnabled(false)

    launchPlaying = false
    local launchStep = 0

    launchBtn:SetScript("OnClick", function(self)
        if launchPlaying then
            -- Stop the animation and play effects
            launchPlaying = false
            animTex:Hide()
            animContainer:SetScript("OnUpdate", nil)
            modelFrame:SetAnimation(0)
            if currentSoundHandle then
                StopSound(currentSoundHandle)
                currentSoundHandle = nil
            end
            if emoteTimer then
                emoteTimer:Cancel()
                emoteTimer = nil
            end
            UpdateLaunchState()
            UpdateFirstAnimFrame()
            return
        end

        launchPlaying = true
        UpdateLaunchState()

        -- Get current active choices from indices
        local soundIdx = showcaseIndices["tl"] or 1
        local animIdx = showcaseIndices["tr"] or 1
        local emoteIdx = showcaseIndices["bl"] or 1
        local textIdx = showcaseIndices["br"] or 1

        local soundOpt = SLOT_DEFS[1].options[soundIdx]
        local animOpt = SLOT_DEFS[2].options[animIdx]
        local emoteOpt = SLOT_DEFS[3].options[emoteIdx]
        local textOpt = SLOT_DEFS[4].options[textIdx]

        -- Show the animation texture
        animTex:SetTexture(animOpt.texture)
        animTex:Show()

        -- Make character model perform animation
        modelFrame:SetAnimation(emoteOpt.anim)
        if emoteTimer then
            emoteTimer:Cancel()
            emoteTimer = nil
        end
        if emoteOpt.duration then
            emoteTimer = C_Timer.NewTimer(emoteOpt.duration, function()
                modelFrame:SetAnimation(0)
            end)
        end

        -- Play sound and store handle
        if currentSoundHandle then
            StopSound(currentSoundHandle)
        end
        local _, soundHandle = PlaySoundFile(soundOpt.sound, "Master")
        currentSoundHandle = soundHandle

        -- Play emote in game
        DoEmote(emoteOpt.emote)

        -- Send chat message
        SendChatMessage(textOpt.text, "SAY")

        -- Animate the spritesheet inline (runs 3 loops)
        local cols, rows, totalFrames, fps = animOpt.cols, animOpt.rows, animOpt.totalFrames, 24
        launchStep = 0
        local loopCount = 0

        animContainer:SetScript("OnUpdate", function(containerSelf, elapsed)
            if not launchPlaying then return end
            launchStep = launchStep + elapsed * fps
            local frameIdx = math.floor(launchStep)
            if frameIdx >= totalFrames then
                loopCount = loopCount + 1
                if loopCount >= 3 then
                    -- Animation done, reset
                    launchPlaying = false
                    animTex:Hide()
                    containerSelf:SetScript("OnUpdate", nil)
                    modelFrame:SetAnimation(0) -- Reset character animation to idle
                    if currentSoundHandle then
                        StopSound(currentSoundHandle)
                        currentSoundHandle = nil
                    end
                    if emoteTimer then
                        emoteTimer:Cancel()
                        emoteTimer = nil
                    end
                    UpdateLaunchState()
                    UpdateFirstAnimFrame()
                    return
                else
                    launchStep = 0
                    frameIdx = 0
                    if currentSoundHandle then
                        StopSound(currentSoundHandle)
                    end
                    local _, soundHandle = PlaySoundFile(soundOpt.sound, "Master")
                    currentSoundHandle = soundHandle

                    -- Replay emote animation and restart timer for the new loop iteration
                    modelFrame:SetAnimation(emoteOpt.anim)
                    if emoteTimer then
                        emoteTimer:Cancel()
                        emoteTimer = nil
                    end
                    if emoteOpt.duration then
                        emoteTimer = C_Timer.NewTimer(emoteOpt.duration, function()
                            modelFrame:SetAnimation(0)
                        end)
                    end
                end
            end
            local col = frameIdx % cols
            local row = math.floor(frameIdx / cols)
            animTex:SetTexCoord(col / cols, (col + 1) / cols, row / rows, (row + 1) / rows)
        end)
    end)

    UpdateLaunchState()

    -- ───────────────────────────────────────────────────────────────
    -- CARD 3: QUICK START GUIDE
    -- ───────────────────────────────────────────────────────────────
    local guideTitle = card3:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    guideTitle:SetPoint("TOP", card3, "TOP", 0, -12)
    guideTitle:SetTextColor(1, 0.82, 0, 1)
    guideTitle:SetText(L["GUIDE_TITLE"])
    local gName, gHeight, gFlags = guideTitle:GetFont()
    if gName then guideTitle:SetFont(gName, gHeight * 1.1, gFlags) end

    local guideSubtitle = card3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    guideSubtitle:SetPoint("TOP", guideTitle, "BOTTOM", 0, -4)
    guideSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    guideSubtitle:SetText(L["GUIDE_SUBTITLE"])

    local function StyleCardSubPanel(panel)
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        panel:SetBackdropColor(0.02, 0.02, 0.03, 0.6)
        panel:SetBackdropBorderColor(0.5, 0.43, 0.25, 0.5)
    end

    -- Create Step Columns
    local steps = {
        {
            icon = "Interface\\Icons\\INV_Misc_Book_09",
            title = L["GUIDE_STEP1_TITLE"],
            desc = L["GUIDE_STEP1_DESC"]
        },
        {
            icon = "Interface\\Icons\\UI_Chat",
            title = L["GUIDE_STEP2_TITLE"],
            desc = L["GUIDE_STEP2_DESC"]
        },
        {
            icon = "Interface\\Icons\\INV_Misc_Toy_07",
            title = L["GUIDE_STEP3_TITLE"],
            desc = L["GUIDE_STEP3_DESC"]
        }
    }

    for idx, step in ipairs(steps) do
        local col = CreateFrame("Frame", nil, card3, "BackdropTemplate")
        col:SetSize(280, 215)
        col:SetPoint("CENTER", card3, "CENTER", (idx - 2) * 310, -15)
        StyleCardSubPanel(col)

        local icon = col:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("TOP", col, "TOP", 0, -18)
        icon:SetTexture(step.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local title = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", icon, "BOTTOM", 0, -12)
        title:SetText(step.title)
        title:SetTextColor(1, 0.82, 0, 1)

        local desc = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", col, "TOPLEFT", 14, -90)
        desc:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -14, 10)
        desc:SetJustifyH("CENTER")
        desc:SetJustifyV("TOP")
        desc:SetSpacing(3)
        desc:SetText(step.desc)
    end

    -- ───────────────────────────────────────────────────────────────
    -- CARD 4: ACTIONHUB GUIDE
    -- ───────────────────────────────────────────────────────────────
    local ahTitle = card4:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    ahTitle:SetPoint("TOP", card4, "TOP", 0, -12)
    ahTitle:SetTextColor(1, 0.82, 0, 1)
    ahTitle:SetText(L["AH_GUIDE_TITLE"])
    local aName, aHeight, aFlags = ahTitle:GetFont()
    if aName then ahTitle:SetFont(aName, aHeight * 1.1, aFlags) end

    local ahSubtitle = card4:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ahSubtitle:SetPoint("TOP", ahTitle, "BOTTOM", 0, -4)
    ahSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    ahSubtitle:SetText(L["AH_GUIDE_SUBTITLE"])

    -- Left panel: Explanations
    local ahLeftPanel = CreateFrame("Frame", nil, card4, "BackdropTemplate")
    ahLeftPanel:SetSize(510, 190)
    ahLeftPanel:SetPoint("TOPLEFT", card4, "TOPLEFT", 30, -70)
    StyleCardSubPanel(ahLeftPanel)

    local ahLeftHeader = ahLeftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ahLeftHeader:SetPoint("TOPLEFT", ahLeftPanel, "TOPLEFT", 20, -16)
    ahLeftHeader:SetText(L["AH_GUIDE_HOW_IT_WORKS"])
    ahLeftHeader:SetTextColor(1, 0.82, 0, 1)

    local ahExplanation = ahLeftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ahExplanation:SetPoint("TOPLEFT", ahLeftPanel, "TOPLEFT", 20, -50)
    ahExplanation:SetPoint("BOTTOMRIGHT", ahLeftPanel, "BOTTOMRIGHT", -20, 10)
    ahExplanation:SetJustifyH("LEFT")
    ahExplanation:SetJustifyV("TOP")
    ahExplanation:SetSpacing(6)
    ahExplanation:SetText(L["AH_GUIDE_EXPLANATION"])

    -- Right panel: Interactive Preview Ring
    local previewRing = CreateFrame("Frame", nil, card4)
    previewRing:SetSize(300, 300)
    previewRing:SetPoint("CENTER", card4, "TOPLEFT", 810, -155)

    local cx, cy = 150, -150
    local baseRadius = 65
    local radiusStep = 48

    -- Center Logo Icon without square backdrop
    local logoFrame = CreateFrame("Frame", nil, previewRing)
    logoFrame:SetSize(44, 44)
    logoFrame:SetPoint("CENTER", previewRing, "TOPLEFT", cx, cy)

    local ringLogo = logoFrame:CreateTexture(nil, "ARTWORK")
    ringLogo:SetPoint("CENTER")
    ringLogo:SetSize(36, 36)
    ringLogo:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")

    -- Simulated Primary (bottom-left) and Secondary (top-left) slot setups
    local primarySlots = {
        { icon = "Interface\\Icons\\INV_Misc_Rune_06", title = L["AH_GUIDE_HEARTHSTONES_TITLE"] or "Hearthstones Mix", desc = L["AH_GUIDE_HEARTHSTONES_DESC"] or "Tip: Group all your teleportation toys and hearthstones into a single slot. ActionHub dynamically selects the best one depending on cooldowns." },
        { icon = "Interface\\Icons\\INV_Potion_51", title = L["AH_GUIDE_POTIONS_TITLE"] or "Automated Potions", desc = L["AH_GUIDE_POTIONS_DESC"] or "Tip: Assign health and mana potions here. You can set them to auto-cast when your health falls below a certain threshold using Triggers." },
        { icon = "Interface\\Icons\\INV_Misc_Wrench_01", title = L["AH_GUIDE_ENGINEERING_TITLE"] or "Engineering Gadgets", desc = L["AH_GUIDE_ENGINEERING_DESC"] or "Tip: Keep loot-a-rang, glider kits, and portable mailboxes handy. Unlock the ring in Settings to drag slots anywhere on your screen." },
        { icon = "Interface\\Icons\\Ability_Mount_Charger", title = L["AH_GUIDE_MOUNTS_TITLE"] or "Smart Mount Mix", desc = L["AH_GUIDE_MOUNTS_DESC"] or "Tip: Get your favorite mount without wasting your action bar. Creates a smart slot for a flying mount in flyable zones, a ground mount elsewhere, or a water mount." },
        { icon = "Interface\\Icons\\INV_Sword_04", title = L["AH_GUIDE_MACROS_TITLE"] or "Secure Macros", desc = L["AH_GUIDE_MACROS_DESC"] or "Tip: Write advanced custom macros that execute multiple actions without using up your character's standard Blizzard macro slot limit." },
        { icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", title = L["AH_GUIDE_SELF_BUFF_TITLE"] or "Self-Buff Tracker", desc = L["AH_GUIDE_SELF_BUFF_DESC"] or "Tip: Link defensive buffs or flasks here. Combined with a custom trigger, ActionHub provides sound notifications and highlights them when they expire." },
        { icon = "Interface\\Icons\\INV_Misc_Gift_01", title = L["AH_GUIDE_REACTION_TRIGGERS_TITLE"] or "Reaction Triggers", desc = L["AH_GUIDE_REACTION_TRIGGERS_DESC"] or "Tip: Set up triggers to provide sound notifications and alerts when you score a killing blow, interrupt successfully, or start a boss fight." },
        { icon = "Interface\\Icons\\INV_Misc_Key_04", title = L["AH_GUIDE_KEYBINDS_TITLE"] or "Dynamic Keybinds", desc = L["AH_GUIDE_KEYBINDS_DESC"] or "Tip: Each node can be bound to a unique key combination, allowing you to use ActionHub as an extension of your standard action bars." },
    }

    local secondarySlots = {
        { icon = "Interface\\Icons\\INV_Sword_04", title = L["AH_GUIDE_MACRO_VM_TITLE"] or "Internal Macro VM", desc = L["AH_GUIDE_MACRO_VM_DESC"] or "Runs secure key sequences and spells directly inside the game without macro slot cost." },
        nil,
        { icon = "Interface\\Icons\\INV_Misc_Rune_09", title = L["AH_GUIDE_REACTION_EMOTES_TITLE"] or "Reaction Emotes", desc = L["AH_GUIDE_REACTION_EMOTES_DESC"] or "Triggers localized text and visual spell emotes seamlessly on combat achievements." },
        nil,
        { icon = "Interface\\Icons\\INV_Misc_Wrench_01", title = L["AH_GUIDE_MOVABLE_NODE_TITLE"] or "Movable Node Button", desc = L["AH_GUIDE_MOVABLE_NODE_DESC"] or "Click 'Unlock' in settings to drag, scale, and place each slot individually on your screen." },
        nil,
    }

    local function GetArcCoordinates(i, maxSlots, quadrant, cx, cy, baseRadius, radiusStep, skipEdge)
        local angleStart, angleEnd
        if quadrant == "bottom-right" then
            angleStart, angleEnd = 0, math.pi / 2
        elseif quadrant == "bottom-left" then
            angleStart, angleEnd = math.pi / 2, math.pi
        elseif quadrant == "top-left" then
            angleStart, angleEnd = math.pi, 3 * math.pi / 2
        elseif quadrant == "left-crescent" then
            angleStart, angleEnd = math.pi * 0.6, math.pi * 1.4
        else
            angleStart, angleEnd = 3 * math.pi / 2, 2 * math.pi
        end
        local span = angleEnd - angleStart

        local baseSlots = 3
        local ringIndex = 0
        local ringCapacity = skipEdge and (baseSlots - 1) or baseSlots
        local countBeforeRing = 0

        while i > countBeforeRing + ringCapacity do
            countBeforeRing = countBeforeRing + ringCapacity
            ringIndex = ringIndex + 1
            local rawRingCapacity = baseSlots + (ringIndex * 2)
            ringCapacity = skipEdge and (rawRingCapacity - 1) or rawRingCapacity
        end

        local indexInRing = i - countBeforeRing
        local slotsInThisRing = math.min(maxSlots - countBeforeRing, ringCapacity)
        local t
        if skipEdge == "start" then
            t = indexInRing / slotsInThisRing
        elseif skipEdge == "finish" then
            t = (indexInRing - 1) / slotsInThisRing
        else
            t = (slotsInThisRing > 1) and ((indexInRing - 1) / (slotsInThisRing - 1)) or 0.5
        end
        local angle = angleStart + span * t
        local currentRadius = baseRadius + ringIndex * radiusStep

        local x = cx + currentRadius * math.cos(angle)
        local y = cy - currentRadius * math.sin(angle)

        return x, y
    end

    local function StylePreviewButtonToRing(btn, size)
        local innerSize = size - 2
        btn.icon:SetSize(innerSize, innerSize)
        btn:SetBackdrop(nil)
        
        -- Thin border matching the circular style
        if not btn.ringBg then
            btn.ringBg = btn:CreateTexture(nil, "BACKGROUND")
            btn.ringBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            
            btn.ringBgMask = btn:CreateMaskTexture()
            btn.ringBgMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringBgMask:SetAllPoints(btn.ringBg)
            btn.ringBg:AddMaskTexture(btn.ringBgMask)

            -- Dark inner fill
            btn.ringFill = btn:CreateTexture(nil, "BORDER")
            btn.ringFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringFill:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.ringFill:SetVertexColor(0.04, 0.04, 0.05, 0.85)

            btn.ringFillMask = btn:CreateMaskTexture()
            btn.ringFillMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringFillMask:SetAllPoints(btn.ringFill)
            btn.ringFill:AddMaskTexture(btn.ringFillMask)
        end
        
        if not btn.ringMask then
            btn.ringMask = btn:CreateMaskTexture()
            btn.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringMask:SetAllPoints(btn.icon)
        end
        btn.icon:AddMaskTexture(btn.ringMask)

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
    end

    local function RenderSide(sideSlots, sideKey, sideQuadrant)
        local sideCount = (sideKey == "secondary") and 6 or 8
        local skipEdge = (sideKey == "secondary") and "start" or nil
        for i = 1, sideCount do
            local slot = sideSlots[i]
            local x, y = GetArcCoordinates(i, sideCount, sideQuadrant, cx, cy, baseRadius, radiusStep, skipEdge)

            local btn = CreateFrame("Button", nil, previewRing, "BackdropTemplate")
            btn:SetSize(44, 44)
            btn:SetPoint("CENTER", previewRing, "TOPLEFT", x, y)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(32, 32)
            icon:SetPoint("CENTER")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = icon

            local plus = btn:CreateTexture(nil, "OVERLAY")
            plus:SetPoint("CENTER")
            plus:SetSize(24, 24)
            plus:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\add.tga")
            btn.plus = plus

            StylePreviewButtonToRing(btn, 44)

            if slot then
                btn.icon:SetTexture(slot.icon)
                btn.icon:Show()
                btn.plus:Hide()
                
                btn:SetScript("OnEnter", function(self)
                    if self.ringBg then
                        self.ringBg:SetVertexColor(1, 0.82, 0, 1)
                    end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("|cffffd100ActionHub:|r " .. slot.title)
                    GameTooltip:AddLine(slot.desc, 1, 1, 1, true)
                    GameTooltip:Show()
                end)

                btn:SetScript("OnLeave", function(self)
                    if self.ringBg then
                        self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
                    end
                    GameTooltip:Hide()
                end)
            else
                btn.icon:Hide()
                btn.plus:Show()
                if btn.ringBg then
                    btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.1)
                end
                if btn.ringFill then
                    btn.ringFill:SetVertexColor(0.04, 0.04, 0.05, 0.4)
                end

                btn:SetScript("OnEnter", function(self)
                    if self.ringBg then
                        self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.3)
                    end
                    if not OxedHub.ActionHub or OxedHub.ActionHub:GetActiveHubDB().showTooltip ~= false then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("|cffffd100" .. (L["AH_GUIDE_EMPTY_TITLE"] or "ActionHub Slot") .. "|r")
                        GameTooltip:AddLine(L["AH_GUIDE_EMPTY_DESC"] or "Click 'Unlock' in ActionHub settings to drag items/spells onto empty nodes.", 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
            end

            btn:SetScript("OnLeave", function(self)
                if slot then
                    if self.ringBg then
                        self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
                    end
                else
                    if self.ringBg then
                        self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.1)
                    end
                end
                GameTooltip:Hide()
            end)
        end
    end

    RenderSide(primarySlots, "primary", "left-crescent")

    function UI:UpdateActionHubCardState()
        -- No-op placeholder since controls panel was replaced by the static preview ring
    end

    -- ───────────────────────────────────────────────────────────────
    -- CARD 5: OXEDRING GUIDE
    -- ───────────────────────────────────────────────────────────────
    local oxedRingTitle = card5:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    oxedRingTitle:SetPoint("TOP", card5, "TOP", 0, -12)
    oxedRingTitle:SetTextColor(1, 0.82, 0, 1)
    oxedRingTitle:SetText(L["OR_GUIDE_TITLE"])
    local oName, oHeight, oFlags = oxedRingTitle:GetFont()
    if oName then oxedRingTitle:SetFont(oName, oHeight * 1.1, oFlags) end

    local oxedRingSubtitle = card5:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    oxedRingSubtitle:SetPoint("TOP", oxedRingTitle, "BOTTOM", 0, -4)
    oxedRingSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    oxedRingSubtitle:SetText(L["OR_GUIDE_SUBTITLE"])

    -- Left panel: Explanations
    local orLeftPanel = CreateFrame("Frame", nil, card5, "BackdropTemplate")
    orLeftPanel:SetSize(510, 190)
    orLeftPanel:SetPoint("TOPLEFT", card5, "TOPLEFT", 30, -70)
    StyleCardSubPanel(orLeftPanel)

    local orLeftHeader = orLeftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    orLeftHeader:SetPoint("TOPLEFT", orLeftPanel, "TOPLEFT", 20, -16)
    orLeftHeader:SetText(L["OR_GUIDE_HOW_IT_WORKS"])
    orLeftHeader:SetTextColor(1, 0.82, 0, 1)

    local orExplanation = orLeftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    orExplanation:SetPoint("TOPLEFT", orLeftPanel, "TOPLEFT", 20, -50)
    orExplanation:SetPoint("BOTTOMRIGHT", orLeftPanel, "BOTTOMRIGHT", -20, 10)
    orExplanation:SetJustifyH("LEFT")
    orExplanation:SetJustifyV("TOP")
    orExplanation:SetSpacing(6)
    orExplanation:SetText(L["OR_GUIDE_EXPLANATION"])

    -- Right panel: Interactive Preview Ring
    local previewRing2 = CreateFrame("Frame", nil, card5)
    previewRing2:SetSize(240, 240)
    previewRing2:SetPoint("CENTER", card5, "TOPLEFT", 740, -155)

    -- Ring background line
    local ringBg2 = previewRing2:CreateTexture(nil, "BACKGROUND")
    ringBg2:SetSize(170, 170)
    ringBg2:SetPoint("CENTER")
    ringBg2:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\ring")
    ringBg2:SetVertexColor(0.8, 0.6, 0.2, 0.35)

    -- Center Logo Icon
    local ringLogo2 = previewRing2:CreateTexture(nil, "ARTWORK")
    ringLogo2:SetSize(44, 44)
    ringLogo2:SetPoint("CENTER")
    ringLogo2:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")

    -- 6 Node buttons placed in a circle around the center representing OxedRing actions
    local previewNodes2 = {
        { icon = "Interface\\Icons\\Ability_Mount_Charger", title = L["OR_GUIDE_N1_TITLE"] or "Mounts Mix", desc = L["OR_GUIDE_N1_DESC"] or "Summons appropriate ground or flying mount dynamically based on zone capabilities." },
        { icon = "Interface\\Icons\\INV_Misc_Rune_06", title = L["OR_GUIDE_N2_TITLE"] or "Hearthstones", desc = L["OR_GUIDE_N2_DESC"] or "Cast home or localized teleport toys from a nested utility ring." },
        { icon = "Interface\\Icons\\INV_Misc_Wrench_01", title = L["OR_GUIDE_N3_TITLE"] or "Utility Items", desc = L["OR_GUIDE_N3_DESC"] or "Deploy gliders, drums, potions, or lockpicks instantly during active encounters." },
        { icon = "Interface\\Icons\\INV_Misc_Toy_07", title = L["OR_GUIDE_N4_TITLE"] or "Fun Toys", desc = L["OR_GUIDE_N4_DESC"] or "Triggers visual and audio toy effects like Sylvanas Music Box on release." },
        { icon = "Interface\\Icons\\INV_Misc_Food_15", title = L["OR_GUIDE_N5_TITLE"] or "Quick Emotes", desc = L["OR_GUIDE_N5_DESC"] or "Performs custom emotes like Cheer, Eat, or Wave seamlessly." },
        { icon = "Interface\\Icons\\INV_Scroll_03", title = L["OR_GUIDE_N6_TITLE"] or "Custom Macros", desc = L["OR_GUIDE_N6_DESC"] or "Executes advanced macro scripts, spells, or equip sets mapped to slices." },
    }

    local radius = 85
    for idx, node in ipairs(previewNodes2) do
        local angle = (idx - 1) * (math.pi * 2 / #previewNodes2)
        local posX = radius * math.cos(angle)
        local posY = radius * math.sin(angle)

        local btn = CreateFrame("Button", nil, previewRing2, "BackdropTemplate")
        btn:SetSize(46, 46)
        btn:SetPoint("CENTER", previewRing2, "CENTER", posX, posY)

        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(0.04, 0.04, 0.05, 0.75)
        btn:SetBackdropBorderColor(0.5, 0.43, 0.25, 0.7)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(34, 34)
        icon:SetPoint("CENTER")
        icon:SetTexture(node.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        btn.icon = icon

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("|cffffd100OxedRing:|r " .. node.title)
            GameTooltip:AddLine(node.desc, 1, 1, 1, true)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.5, 0.43, 0.25, 0.7)
            GameTooltip:Hide()
        end)
    end

    -- Keep UpdateDashboardSliderStats as a no-op placeholder to prevent interface errors
    function UI:UpdateDashboardSliderStats()
        -- No-op
    end

    -- ───────────────────────────────────────────────────────────────
    -- TRANSITION LOGIC
    -- ───────────────────────────────────────────────────────────────
    local targetScroll = 0
    local scrollSpeed = 10

    function UI:SetDashboardCard(idx, smooth)
        if idx < 1 or idx > numCards then return end
        activeCardIndex = idx

        if idx == 4 and UI.UpdateActionHubCardState then
            UI:UpdateActionHubCardState()
        end
        
        -- Update Arrows visibility/state
        if idx == 1 then
            prevBtn:Disable()
            prevBtn:SetAlpha(0.2)
        else
            prevBtn:Enable()
            prevBtn:SetAlpha(1.0)
        end
        
        if idx == numCards then
            nextBtn:Disable()
            nextBtn:SetAlpha(0.2)
        else
            nextBtn:Enable()
            nextBtn:SetAlpha(1.0)
        end
        
        -- Update Pagination Dots
        for dIdx, dot in ipairs(dots) do
            if dIdx == idx then
                dot.tex:SetTexCoord(0.25, 0.5, 0, 1) -- Golden selected dot
            else
                dot.tex:SetTexCoord(0, 0.25, 0, 1) -- Grey unselected dot
            end
        end
        
        -- Set Target Horizontal Scroll
        local innerWidth = sliderScroll:GetWidth() or 0
        if innerWidth <= 0 then
            innerWidth = (showcaseContainer:GetWidth() or 760) - 20
        end
        targetScroll = (idx - 1) * innerWidth
        
        -- If sliding back to Card 2 (Character Showcase), show model immediately so it slides in nicely
        if idx == 2 then
            modelFrame:Show()
        end

        if smooth then
            sliderScroll:SetScript("OnUpdate", function(self, elapsed)
                local cur = self:GetHorizontalScroll()
                local diff = targetScroll - cur
                if math.abs(diff) < 1 then
                    self:SetHorizontalScroll(targetScroll)
                    self:SetScript("OnUpdate", nil)
                    -- If we completed slide away from Card 2, hide the 3D model frame to prevent clipping issues
                    if activeCardIndex ~= 2 then
                        modelFrame:Hide()
                    end
                else
                    self:SetHorizontalScroll(cur + diff * scrollSpeed * elapsed)
                end
            end)
        else
            sliderScroll:SetScript("OnUpdate", nil)
            sliderScroll:SetHorizontalScroll(targetScroll)
            if idx ~= 2 then
                modelFrame:Hide()
            end
        end
    end

    -- Hook arrow buttons
    prevBtn:SetScript("OnClick", function()
        UI:SetDashboardCard(activeCardIndex - 1, true)
    end)
    nextBtn:SetScript("OnClick", function()
        UI:SetDashboardCard(activeCardIndex + 1, true)
    end)

    -- Initialize Slider State
    UI:SetDashboardCard(1, false)
    UI:UpdateDashboardSliderStats()

    -- Update scroll child height to fit the new showcase card
    scrollChild:SetHeight(586)

    tab.heroTitle = heroTitle
    tab.heroSubtitle = heroSubtitle
    tab.heroMeta = heroMeta
    tab.stats = { stat1, stat2, stat3, stat4, stat5, stat6 }
    tab.summaryText = summaryText
    tab.showcaseContainer = showcaseContainer
    tab.scrollFrame = scrollFrame
    tab.scrollChild = scrollChild
    tab:Hide()

    contentArea.Dashboard = tab
end

-- Create Triggers tab
function UI:CreateTriggersTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(2)
    ApplyToysBackground(tab)
    
    -- Title with gold color
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", 15, -15)
    title:SetText(L["TRIGGERS_TITLE"])
    title:Hide()
    tab.title = title
    
    -- Scroll frame using standard UIPanelScrollFrameTemplate
    local scrollFrame = CreateFrame("ScrollFrame", nil, tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -THEMED_FRAME_INSETS.top)
    scrollFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom + 6)
    StyleScrollFrame(scrollFrame)
    
    local scrollChild = CreateFrame("Frame")
    local scrollWidth = scrollFrame:GetWidth()
    if not scrollWidth or scrollWidth <= 0 then
        scrollWidth = 970
    else
        scrollWidth = scrollWidth - 20
    end
    scrollChild:SetSize(scrollWidth, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    tab.scrollFrame = scrollFrame
    tab.scrollChild = scrollChild

    if CreateScrollBoxListLinearView and ScrollUtil and CreateDataProvider then
        local view = CreateScrollBoxListLinearView()
        if view.SetElementExtent then
            view:SetElementExtent(32)
        end
        view:SetElementInitializer("BackdropTemplate", function(row, elementData)
            row:SetHeight(elementData.isHeader and 30 or 32)
            row:EnableMouse(true)

            if not row.bg then
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")

                row.topLine = row:CreateTexture(nil, "BORDER")
                row.topLine:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
                row.topLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
                row.topLine:SetHeight(1)
                row.topLine:SetTexture("Interface\\Buttons\\WHITE8X8")

                row.bottomLine = row:CreateTexture(nil, "BORDER")
                row.bottomLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
                row.bottomLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
                row.bottomLine:SetHeight(1)
                row.bottomLine:SetTexture("Interface\\Buttons\\WHITE8X8")

                row.leftAccent = row:CreateTexture(nil, "BORDER")
                row.leftAccent:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
                row.leftAccent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
                row.leftAccent:SetWidth(2)
                row.leftAccent:SetTexture("Interface\\Buttons\\WHITE8X8")

                row.hoverHighlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.hoverHighlight:SetAllPoints()
                row.hoverHighlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                row.hoverHighlight:SetBlendMode("ADD")
                row.hoverHighlight:SetAlpha(0.35)
                row.hoverHighlight:Hide()

                row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameText:SetPoint("LEFT", row, "LEFT", 12, 0)
                row.nameText:SetWidth(190)
                row.nameText:SetJustifyH("LEFT")

                row.eventText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.eventText:SetPoint("LEFT", row.nameText, "RIGHT", 12, 0)
                row.eventText:SetWidth(130)
                row.eventText:SetJustifyH("LEFT")

                row.actionsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.actionsText:SetPoint("LEFT", row.eventText, "RIGHT", 12, 0)
                row.actionsText:SetWidth(180)
                row.actionsText:SetJustifyH("LEFT")

                -- Spell column: icon + id of the spell this trigger watches, so
                -- the list can be scanned without opening each trigger.
                row.spellAnchor = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.spellAnchor:SetPoint("LEFT", row.actionsText, "RIGHT", 12, 0)
                row.spellAnchor:SetWidth(90)
                row.spellAnchor:SetJustifyH("LEFT")

                -- Plain frame, mouse disabled: the row handles clicks to open
                -- the trigger, and a mouse-enabled child would swallow them.
                row.spellIconFrame = CreateFrame("Frame", nil, row)
                row.spellIconFrame:SetSize(20, 20)
                row.spellIconFrame:SetPoint("LEFT", row.spellAnchor, "LEFT", 0, 0)
                row.spellIconFrame:EnableMouse(false)
                row.spellIcon = row.spellIconFrame:CreateTexture(nil, "ARTWORK")
                row.spellIcon:SetAllPoints()
                row.spellIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                row.spellIdText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.spellIdText:SetPoint("LEFT", row.spellIconFrame, "RIGHT", 5, 0)
                row.spellIdText:SetWidth(64)
                row.spellIdText:SetJustifyH("LEFT")

                row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.zoneText:SetPoint("LEFT", row.spellAnchor, "RIGHT", 12, 0)
                row.zoneText:SetWidth(170)
                row.zoneText:SetJustifyH("LEFT")

                local function CreateColumnLine(anchor)
                    local line = row:CreateTexture(nil, "BORDER")
                    line:SetPoint("TOPLEFT", anchor, "TOPLEFT", -7, -5)
                    line:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", -7, 5)
                    line:SetWidth(1)
                    line:SetTexture("Interface\\Buttons\\WHITE8X8")
                    return line
                end

                row.eventDivider = CreateColumnLine(row.eventText)
                row.actionsDivider = CreateColumnLine(row.actionsText)
                row.spellDivider = CreateColumnLine(row.spellAnchor)
                row.zoneDivider = CreateColumnLine(row.zoneText)

                if not row.eventHoverFrame then
                    local ehf = CreateFrame("Frame", nil, row)
                    ehf:SetPoint("TOPLEFT", row.eventText, "TOPLEFT", -2, 4)
                    ehf:SetPoint("BOTTOMRIGHT", row.eventText, "BOTTOMRIGHT", 2, -4)
                    ehf:EnableMouse(true)
                    ehf:SetScript("OnEnter", function()
                        if row.hoverHighlight and row.elementData and not row.elementData.isHeader then
                            row.hoverHighlight:Show()
                        end
                        if row.elementData and row.elementData.event and not row.elementData.isHeader then
                            GameTooltip:SetOwner(ehf, "ANCHOR_RIGHT")
                            GameTooltip:SetText(row.elementData.eventLabel or row.elementData.event, 1, 0.82, 0)
                            GameTooltip:AddLine("|cff888888Event:|r " .. tostring(row.elementData.event), 0.8, 0.8, 0.8, false)
                            if row.elementData.eventDesc and row.elementData.eventDesc ~= "" then
                                GameTooltip:AddLine(row.elementData.eventDesc, 1, 1, 1, true)
                            end
                            GameTooltip:Show()
                        end
                    end)
                    ehf:SetScript("OnLeave", function()
                        if row.hoverHighlight then row.hoverHighlight:Hide() end
                        GameTooltip:Hide()
                    end)
                    ehf:SetScript("OnMouseUp", function(_, button)
                        local script = row:GetScript("OnMouseUp")
                        if script then script(row, button) end
                    end)
                    row.eventHoverFrame = ehf
                end

                if not row.actionsHoverFrame then
                    local ahf = CreateFrame("Frame", nil, row)
                    ahf:SetPoint("TOPLEFT", row.actionsText, "TOPLEFT", -2, 4)
                    ahf:SetPoint("BOTTOMRIGHT", row.actionsText, "BOTTOMRIGHT", 2, -4)
                    ahf:EnableMouse(true)
                    ahf:SetScript("OnEnter", function()
                        if row.hoverHighlight and row.elementData and not row.elementData.isHeader then
                            row.hoverHighlight:Show()
                        end
                        if row.elementData and row.elementData.actionDetails and not row.elementData.isHeader then
                            GameTooltip:SetOwner(ahf, "ANCHOR_RIGHT")
                            GameTooltip:SetText(L["LBL_ACTIONS"] or "Actions", 1, 0.82, 0)
                            GameTooltip:AddLine(row.elementData.actionDetails, 1, 1, 1, false)
                            GameTooltip:Show()
                        end
                    end)
                    ahf:SetScript("OnLeave", function()
                        if row.hoverHighlight then row.hoverHighlight:Hide() end
                        GameTooltip:Hide()
                    end)
                    ahf:SetScript("OnMouseUp", function(_, button)
                        local script = row:GetScript("OnMouseUp")
                        if script then script(row, button) end
                    end)
                    row.actionsHoverFrame = ahf
                end

                if not row.spellHoverFrame then
                    local shf = CreateFrame("Frame", nil, row)
                    shf:SetPoint("TOPLEFT", row.spellAnchor, "TOPLEFT", -2, 4)
                    shf:SetPoint("BOTTOMRIGHT", row.spellAnchor, "BOTTOMRIGHT", 2, -4)
                    shf:EnableMouse(true)
                    shf:SetScript("OnEnter", function()
                        if row.hoverHighlight and row.elementData and not row.elementData.isHeader then
                            row.hoverHighlight:Show()
                        end
                        local spellID = row.elementData and tonumber(row.elementData.spellID)
                        if spellID then
                            GameTooltip:SetOwner(shf, "ANCHOR_RIGHT")
                            GameTooltip:SetSpellByID(spellID)
                            GameTooltip:Show()
                        end
                    end)
                    shf:SetScript("OnLeave", function()
                        if row.hoverHighlight then row.hoverHighlight:Hide() end
                        GameTooltip:Hide()
                    end)
                    shf:SetScript("OnMouseUp", function(_, button)
                        local script = row:GetScript("OnMouseUp")
                        if script then script(row, button) end
                    end)
                    row.spellHoverFrame = shf
                end

                if not row.zoneHoverFrame then
                    local zhf = CreateFrame("Frame", nil, row)
                    zhf:SetPoint("TOPLEFT", row.zoneText, "TOPLEFT", -2, 4)
                    zhf:SetPoint("BOTTOMRIGHT", row.zoneText, "BOTTOMRIGHT", 2, -4)
                    zhf:EnableMouse(true)
                    zhf:SetScript("OnEnter", function()
                        if row.hoverHighlight and row.elementData and not row.elementData.isHeader then
                            row.hoverHighlight:Show()
                        end
                        if row.elementData and row.elementData.zoneDetails and not row.elementData.isHeader then
                            GameTooltip:SetOwner(zhf, "ANCHOR_RIGHT")
                            GameTooltip:SetText(L["LBL_ZONE"] or "Zone", 1, 0.82, 0)
                            GameTooltip:AddLine(row.elementData.zoneDetails, 1, 1, 1, false)
                            GameTooltip:Show()
                        end
                    end)
                    zhf:SetScript("OnLeave", function()
                        if row.hoverHighlight then row.hoverHighlight:Hide() end
                        GameTooltip:Hide()
                    end)
                    zhf:SetScript("OnMouseUp", function(_, button)
                        local script = row:GetScript("OnMouseUp")
                        if script then script(row, button) end
                    end)
                    row.zoneHoverFrame = zhf
                end

                row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.deleteBtn:SetSize(24, 24)

                row.enabledCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.enabledCheck:SetPoint("RIGHT", row.deleteBtn, "LEFT", -20, 0)
                row.enabledCheck:SetSize(22, 22)

                -- Share this single trigger as a chat link.
                row.shareBtn = CreateFrame("Button", nil, row)
                row.shareBtn:SetPoint("RIGHT", row.enabledCheck, "LEFT", -22, 0)
                row.shareBtn:SetSize(18, 18)
                row.shareBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
                row.shareBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
                row.shareBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(L["BTN_SHARE"] or "Share", 1, 0.82, 0)
                    GameTooltip:AddLine("Share just this trigger in chat.", 1, 1, 1, true)
                    GameTooltip:AddLine("Others with Oxed Hub can click to import it.", 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
                row.shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row.shareHeaderText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.shareHeaderText:SetPoint("CENTER", row, "RIGHT", -107, 0)
                row.shareHeaderText:SetText(L["BTN_SHARE"] or "Share")

                row.enabledHeaderText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.enabledHeaderText:SetPoint("CENTER", row, "RIGHT", -63, 0)
                row.enabledHeaderText:SetText(L["TRIGGERS_HEADER_ENABLE"])

                row.deleteHeaderText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.deleteHeaderText:SetPoint("CENTER", row, "RIGHT", -20, 0)
                row.deleteHeaderText:SetText(L["TRIGGERS_HEADER_DELETE"])
            end

            row.elementData = elementData
            local rowHeight = elementData.isHeader and 30 or 32
            if elementData.isHeader then
                row.bg:SetColorTexture(0, 0, 0, 0)
                row.topLine:SetColorTexture(0, 0, 0, 0)
                row.bottomLine:SetColorTexture(0.95, 0.74, 0.22, 0.65)
                row.leftAccent:SetColorTexture(0, 0, 0, 0)
            else
                if (elementData.index or 0) % 2 == 0 then
                    row.bg:SetColorTexture(0.055, 0.052, 0.048, 0.72)
                else
                    row.bg:SetColorTexture(0.075, 0.070, 0.062, 0.68)
                end
                row.topLine:SetColorTexture(0.58, 0.48, 0.34, 0.12)
                row.bottomLine:SetColorTexture(0.58, 0.48, 0.34, 0.22)
                row.leftAccent:SetColorTexture(0, 0, 0, 0)
            end
            row.eventDivider:SetColorTexture(0.58, 0.48, 0.34, elementData.isHeader and 0 or 0.18)
            row.actionsDivider:SetColorTexture(0.58, 0.48, 0.34, elementData.isHeader and 0 or 0.18)
            row.spellDivider:SetColorTexture(0.58, 0.48, 0.34, elementData.isHeader and 0 or 0.18)
            row.zoneDivider:SetColorTexture(0.58, 0.48, 0.34, elementData.isHeader and 0 or 0.18)
            row.nameText:SetText(elementData.name or "")

            if elementData.isHeader then
                row.eventText:SetText(elementData.event or "")
                row.actionsText:SetText(elementData.actions or "")
                row.zoneText:SetText(elementData.zone or "")
            else
                local cat = elementData.eventCategory or "custom"
                local colorHex = "ffffff"
                if cat == "advanced" then colorHex = "66ccff"
                elseif cat == "combat" then colorHex = "ff9933"
                elseif cat == "pvp" then colorHex = "ff5555"
                elseif cat == "basic" then colorHex = "55ff55"
                end
                row.eventText:SetText("|cff" .. colorHex .. (elementData.eventLabel or elementData.event or "") .. "|r")
                row.actionsText:SetText(elementData.formattedActions or elementData.actions or "")
                row.zoneText:SetText(elementData.formattedZone or elementData.zone or "")
            end

            -- Spell column
            if elementData.isHeader then
                row.spellAnchor:SetText(L["LBL_SPELL"] or "Spell")
                row.spellIconFrame:Hide()
                row.spellIdText:SetText("")
            else
                row.spellAnchor:SetText("")
                local spellID = tonumber(elementData.spellID)
                if spellID then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                    row.spellIcon:SetTexture((info and info.iconID)
                        or "Interface\\Icons\\INV_Misc_QuestionMark")
                    row.spellIconFrame:Show()
                    row.spellIdText:SetText(tostring(spellID))
                else
                    row.spellIconFrame:Hide()
                    row.spellIdText:SetText("")
                end
            end
            
            row.deleteBtn:SetShown((not elementData.isHeader) and elementData.id ~= nil)
            row.deleteBtn:SetScript("OnClick", function()
                if elementData.id then
                    OxedHub.Triggers:DeleteTrigger(elementData.id)
                end
            end)
            
            row.shareBtn:SetShown((not elementData.isHeader) and elementData.id ~= nil)
            row.shareBtn:SetScript("OnClick", function()
                local Share = OxedHub.Share
                if not Share then
                    print("|cffff0000Oxed Hub:|r Sharing module unavailable.")
                    return
                end
                if not elementData.id then return end
                local label = elementData.name
                if not label or label == "" then label = "Trigger" end
                Share:ShowChannelPicker("triggers", { triggerIDs = { elementData.id } }, label)
            end)

            row.enabledCheck:SetShown((not elementData.isHeader) and elementData.id ~= nil)
            row.enabledCheck:SetChecked(elementData.enabled == true)
            row.enabledCheck:SetScript("OnClick", function(check)
                local trigger = elementData.id and OxedHub.db.profile.triggers[elementData.id]
                if trigger then
                    trigger.enabled = check:GetChecked()
                    OxedHub.Triggers:InvalidateEnabledEventCache()
                end
            end)

            if elementData.isHeader then
                row.nameText:SetTextColor(1, 0.86, 0.28, 1)
                row.eventText:SetTextColor(1, 0.86, 0.28, 1)
                row.actionsText:SetTextColor(1, 0.86, 0.28, 1)
                row.zoneText:SetTextColor(1, 0.86, 0.28, 1)
                if row.enabledHeaderText then
                    row.enabledHeaderText:Show()
                    row.enabledHeaderText:SetTextColor(1, 0.86, 0.28, 1)
                end
                if row.deleteHeaderText then
                    row.deleteHeaderText:Show()
                    row.deleteHeaderText:SetTextColor(1, 0.86, 0.28, 1)
                end
                if row.shareHeaderText then
                    row.shareHeaderText:Show()
                    row.shareHeaderText:SetTextColor(1, 0.86, 0.28, 1)
                end
            else
                row.nameText:SetTextColor(1, 0.82, 0.12, 1)
                row.actionsText:SetTextColor(0.92, 0.92, 0.92, 1)
                row.zoneText:SetTextColor(0.90, 0.76, 0.36, 1)
                if row.enabledHeaderText then
                    row.enabledHeaderText:Hide()
                end
                if row.deleteHeaderText then
                    row.deleteHeaderText:Hide()
                end
                if row.shareHeaderText then
                    row.shareHeaderText:Hide()
                end
            end
            if row.hoverHighlight then
                row.hoverHighlight:Hide()
            end
            row:SetScript("OnMouseUp", function(_, button)
                if button ~= "LeftButton" then return end
                if elementData.id then
                    OxedHub.Triggers:OpenTriggerDetails(elementData.id)
                end
            end)
            row:SetScript("OnEnter", function(self)
                if self.hoverHighlight and self.elementData and not self.elementData.isHeader then
                    self.hoverHighlight:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if self.hoverHighlight then
                    self.hoverHighlight:Hide()
                end
            end)

            local offset = (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.textSizeOffset) or 0
            offset = tonumber(offset) or 0
            TraverseAndApplyTextSize(row, offset)
        end)

        tab.scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
        tab.scrollBox:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -145)
        tab.scrollBox:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom + 6)

        tab.scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
        tab.scrollBar:SetPoint("TOPLEFT", tab.scrollBox, "TOPRIGHT", 10, 2)
        tab.scrollBar:SetPoint("BOTTOMLEFT", tab.scrollBox, "BOTTOMRIGHT", 10, -1)
        ScrollUtil.InitScrollBoxListWithScrollBar(tab.scrollBox, tab.scrollBar, view)
        tab.scrollBox:Hide()
        tab.scrollBar:Hide()
    end
    
    -- Add New button at top-right using UIPanelButtonTemplate (dark red WoW style)
    local addBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    -- Use natural UIPanelButtonTemplate dark-red look (no gold override)
    addBtn:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -THEMED_FRAME_INSETS.right - 4, -THEMED_FRAME_INSETS.top - 8)
    addBtn:SetSize(160, 28)
    addBtn:SetText(L["TRIGGERS_BTN_ADD_NEW"])
    addBtn:SetScript("OnClick", function()
        OxedHub.Triggers:CreateNewTrigger()
    end)
    tab.addBtn = addBtn
    
    tab:Hide()
    contentArea.Triggers = tab
end

-- Create Reactions tab
function UI:CreateReactionsTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(3)
    tab.subPanels = {}
    ApplyToysBackground(tab)
    
    -- Title with gold color
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", 15, -15)
    title:SetText(L["ACTIONS_TITLE"])
    title:Hide()
    
    -- Sub-tabs container
    local subTabs = CreateFrame("Frame", nil, tab)
    subTabs:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -50)
    subTabs:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -THEMED_FRAME_INSETS.right, -50)
    subTabs:SetHeight(30)
    
    -- Sub-tab buttons using UIPanelButtonTemplate (natural dark-red WoW style, matching Triggers)
    local subTabNames = { "Sounds", "Chat", "Animations", "Advanced" }
    local xOffset = 0
    
    for i, name in ipairs(subTabNames) do
        local btn = CreateFrame("Button", nil, subTabs, "UIPanelButtonTemplate")
        btn:SetSize(name == "Animations" and 95 or (name == "Advanced" and 137 or 80), 25)
        btn:SetPoint("TOPLEFT", subTabs, "TOPLEFT", xOffset, 0)
        local label = name
        if name == "Advanced" then label = L["ACTIONS_SUBTAB_ADD_ANIMATIONS"]
        elseif name == "Sounds" then label = L["ACTIONS_SUBTAB_SOUNDS"]
        elseif name == "Chat" then label = L["ACTIONS_SUBTAB_CHAT"]
        elseif name == "Animations" then label = L["ACTIONS_SUBTAB_ANIMATIONS"] end
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            UI:ShowSubTab(name)
        end)
        btn.subTabName = name
        subTabs[name .. "Btn"] = btn

        local panel = CreateFrame("Frame", nil, tab)
        panel:SetPoint("TOPLEFT", subTabs, "BOTTOMLEFT", 0, -10)
        panel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
        panel:Hide()
        tab.subPanels[name] = panel

        xOffset = xOffset + btn:GetWidth() + 5
    end

    tab.subTabs = subTabs
    tab.currentSubTab = nil
    
    tab:Hide()
    contentArea.Reactions = tab
end

-- Create Toys tab
function UI:CreateToysTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(7)
    tab.subPanels = {}
    ApplyToysBackground(tab)
    
    -- Title
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", 15, -15)
    title:SetText(L["TOYS_TITLE"])
    title:Hide()
    
    -- Sub-tabs container
    local subTabs = CreateFrame("Frame", nil, tab)
    subTabs:SetPoint("TOPLEFT", tab, "TOPLEFT", 15, -50)
    subTabs:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -15, -50)
    subTabs:SetHeight(30)
    
    -- Sub-tab buttons (natural dark-red WoW style, matching Triggers)
    local subTabNames = { "Mixer", "Library", "ToyBoxes" }
    local xOffset = 25

    for i, name in ipairs(subTabNames) do
        local btn = CreateFrame("Button", nil, subTabs, "UIPanelButtonTemplate")
        local btnWidth = (name == "ToyBoxes") and 90 or (name == "Library" and 85 or 80)
        btn:SetSize(btnWidth, 25)
        btn:SetPoint("TOPLEFT", subTabs, "TOPLEFT", xOffset, 0)
        local label
        if name == "Mixer" then label = L["TOYS_SUBTAB_MIXER"] or "Mixer"
        elseif name == "Library" then label = L["TOYS_SUBTAB_LIBRARY"] or "My Mixes"
        elseif name == "ToyBoxes" then label = "ToyBoxes"
        else label = name end
        btn:SetText(label)
        btn:SetScript("OnClick", function()
            UI:ShowToysSubTab(name)
        end)
        btn.subTabName = name
        subTabs[name .. "Btn"] = btn

        local panel = CreateFrame("Frame", nil, tab)
        panel:SetPoint("TOPLEFT", subTabs, "BOTTOMLEFT", 0, -10)
        panel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -15, 15)
        ApplyBlackWorkBackdrop(panel, 0.25)
        panel:Hide()
        tab.subPanels[name] = panel

        xOffset = xOffset + 85
    end

    tab.subTabs = subTabs
    tab.currentSubTab = nil
    
    tab:Hide()
    contentArea.Toys = tab
end

-- Create OxedRing tab
function UI:CreateOxedRingTab()
    if OxedHub.OxedRingEditor then
        local tab = OxedHub.OxedRingEditor:CreateTab(contentArea)
        if tab then
            tab:Hide()
            contentArea.OxedRing = tab
        end
    end
end

-- Create Settings tab
function UI:CreateSettingsTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(4)
    ApplyToysBackground(tab)

    -- Page switcher + sub-tabs live on the tab frame itself (not inside the
    -- scroll child) so they stay pinned while the content scrolls underneath.
    -- Row 1: red Main / Profiles buttons, styled like the Toys Mixer buttons.
    local pageButtonRow = CreateFrame("Frame", nil, tab)
    pageButtonRow:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left + 10, -THEMED_FRAME_INSETS.top - 4)
    pageButtonRow:SetPoint("RIGHT", tab, "RIGHT", -THEMED_FRAME_INSETS.right, 0)
    pageButtonRow:SetHeight(25)
    tab.pageButtonRow = pageButtonRow

    -- Row 2: sub-tabs for the Profiles page.
    local pageTabStrip = CreateFrame("Frame", nil, tab)
    pageTabStrip:SetPoint("TOPLEFT", pageButtonRow, "BOTTOMLEFT", 0, -8)
    pageTabStrip:SetPoint("RIGHT", tab, "RIGHT", -THEMED_FRAME_INSETS.right, 0)
    pageTabStrip:SetHeight(26)
    tab.pageTabStrip = pageTabStrip

    -- Same subtle gold separator as the Toys category tabs: extends 12px past
    -- the strip on the left and 20px on the right.
    local pageTabLine = pageTabStrip:CreateTexture(nil, "ARTWORK")
    pageTabLine:SetPoint("TOPLEFT", pageTabStrip, "BOTTOMLEFT", -12, 0)
    pageTabLine:SetPoint("TOPRIGHT", pageTabStrip, "BOTTOMRIGHT", 20, 0)
    pageTabLine:SetHeight(2)
    pageTabLine:SetColorTexture(1, 0.82, 0, 0.05)

    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubSettingsScrollFrame", tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", pageTabStrip, "BOTTOMLEFT", -10, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
    StyleScrollFrame(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    local scrollWidth = scrollFrame:GetWidth()
    if scrollWidth <= 0 then scrollWidth = 600 end -- Fallback for initial load
    scrollChild:SetWidth(scrollWidth)
    scrollChild:SetHeight(1060) 
    scrollFrame:SetScrollChild(scrollChild)
    tab.scrollChild = scrollChild

    -- Title with gold color
    local title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, -15)
    title:SetText(L["SETTINGS_TITLE"])
    title:Hide()

    -- Page split (Main / Profiles): everything created after the Profiles
    -- section header belongs to the Profiles page, everything before it to
    -- Main. The two sets come from snapshotting scrollChild at that point.
    local audioSection = CreateSettingsSectionHeader(scrollChild, scrollChild, "TOPLEFT", 15, -8, L["SETTINGS_SECTION_AUDIO"])

    -- Sound Channel label
    local channelLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    channelLabel:SetPoint("TOPLEFT", audioSection, "BOTTOMLEFT", 18, -12)
    channelLabel:SetText(L["SETTINGS_AUDIO_CHANNEL"])
    channelLabel:SetTextColor(1, 0.82, 0, 1)

    -- Modern dropdown button using WowStyle1DropdownTemplate (BugSack approach)
    local channels = {
        { key = "Master",  name = "Master" },
        { key = "SFX",     name = "Sound Effects" },
        { key = "Music",   name = "Music" },
        { key = "Ambience",name = "Ambience" },
        { key = "Dialog",  name = "Dialog" },
    }

    local dropdownBtn = CreateFrame("DropdownButton", "OxedHubSettingsChannelBtn", scrollChild, "WowStyle1DropdownTemplate")
    dropdownBtn:SetPoint("TOPLEFT", channelLabel, "BOTTOMLEFT", 0, -8)
    dropdownBtn:SetSize(200, 26)

    local function IsChannelSelected(channel)
        return (OxedHub.db.profile.settings.soundChannel or "Master") == channel
    end

    dropdownBtn:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(channels) do
            rootDescription:CreateRadio(
                entry.name,
                IsChannelSelected,
                function()
                    OxedHub.db.profile.settings.soundChannel = entry.key
                    dropdownBtn:OverrideText(entry.name)
                end,
                entry.key
            )
        end
    end)

    local savedChannel = OxedHub.db.profile.settings.soundChannel or "Master"
    for _, entry in ipairs(channels) do
        if entry.key == savedChannel then
            dropdownBtn:OverrideText(entry.name)
            break
        end
    end

    local triggerSection = CreateSettingsSectionHeader(scrollChild, dropdownBtn, "BOTTOMLEFT", -18, -34, L["SETTINGS_SECTION_TRIGGER"])

    -- Trigger Effects Delay
    local effectsDelayLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    effectsDelayLabel:SetPoint("TOPLEFT", triggerSection, "BOTTOMLEFT", 18, -12)
    effectsDelayLabel:SetText(L["SETTINGS_TRIGGER_DELAY"])
    effectsDelayLabel:SetTextColor(1, 0.82, 0, 1)

    local function SetEffectsDelayValue(value)
        value = math.floor((tonumber(value) or 5) + 0.5)
        value = math.max(1, math.min(20, value))
        OxedHub.db.profile.settings.triggerEffectsDelay = value
        return value
    end

    local savedEffectsDelay = SetEffectsDelayValue(OxedHub.db.profile.settings.triggerEffectsDelay or 5)
    local effectsDelaySlider

    if MinimalSliderWithSteppersMixin and CreateMinimalSliderFormatter then
        effectsDelaySlider = CreateFrame("Slider", "OxedHubTriggerEffectsDelaySlider", scrollChild, "MinimalSliderWithSteppersTemplate")
        effectsDelaySlider:SetPoint("TOPLEFT", effectsDelayLabel, "BOTTOMLEFT", 0, -10)
        effectsDelaySlider:SetSize(260, 20)
        effectsDelaySlider:Init(savedEffectsDelay, 1, 20, 19, {
            [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(value)
                    value = math.floor((tonumber(value) or 5) + 0.5)
                    return WHITE_FONT_COLOR:WrapTextInColorCode(value .. " sec")
                end
            ),
        })
        effectsDelaySlider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            SetEffectsDelayValue(value)
        end)
    else
        effectsDelaySlider = CreateFrame("Slider", "OxedHubTriggerEffectsDelaySlider", scrollChild, "OptionsSliderTemplate")
        effectsDelaySlider:SetPoint("TOPLEFT", effectsDelayLabel, "BOTTOMLEFT", 4, -16)
        effectsDelaySlider:SetWidth(220)
        effectsDelaySlider:SetMinMaxValues(1, 20)
        effectsDelaySlider:SetValueStep(1)
        effectsDelaySlider:SetObeyStepOnDrag(true)
        local effectsDelayLow = _G[effectsDelaySlider:GetName() .. "Low"]
        local effectsDelayHigh = _G[effectsDelaySlider:GetName() .. "High"]
        local effectsDelayText = _G[effectsDelaySlider:GetName() .. "Text"]
        if effectsDelayLow then effectsDelayLow:SetText("1s") end
        if effectsDelayHigh then effectsDelayHigh:SetText("20s") end
        if effectsDelayText then effectsDelayText:SetText("") end

        local effectsDelayValue = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        effectsDelayValue:SetPoint("LEFT", effectsDelaySlider, "RIGHT", 18, 0)
        effectsDelayValue:SetText(savedEffectsDelay .. " sec")

        effectsDelaySlider:SetScript("OnValueChanged", function(_, value)
            effectsDelayValue:SetText(SetEffectsDelayValue(value) .. " sec")
        end)
        effectsDelaySlider:SetValue(savedEffectsDelay)
    end

    local effectsDelayDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    effectsDelayDesc:SetPoint("TOPLEFT", effectsDelaySlider, "BOTTOMLEFT", -4, -8)
    effectsDelayDesc:SetWidth(520)
    effectsDelayDesc:SetJustifyH("LEFT")
    effectsDelayDesc:SetText(L["SETTINGS_TRIGGER_DELAY_DESC"])

    local ringSection = CreateSettingsSectionHeader(scrollChild, effectsDelayDesc, "BOTTOMLEFT", 4, -26, L["SETTINGS_SECTION_RING"])

    -- Show Ring Tooltip Toggle
    local showTooltipsToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    showTooltipsToggle:SetPoint("TOPLEFT", ringSection, "BOTTOMLEFT", 14, -10)
    showTooltipsToggle:SetSize(26, 26)
    
    local tooltipsSetting = true
    if OxedHub.db.profile.settings and OxedHub.db.profile.settings.ringTooltips ~= nil then
        tooltipsSetting = OxedHub.db.profile.settings.ringTooltips
    end
    showTooltipsToggle:SetChecked(tooltipsSetting)
    showTooltipsToggle:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.ringTooltips = self:GetChecked()
    end)
    
    local showTooltipsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showTooltipsLabel:SetPoint("LEFT", showTooltipsToggle, "RIGHT", 4, 0)
    showTooltipsLabel:SetText(L["SETTINGS_RING_TOOLTIP"])
    showTooltipsLabel:SetTextColor(1, 1, 1, 1)

    -- Show Minimap Button Toggle
    local minimapToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    minimapToggle:SetPoint("TOPLEFT", showTooltipsToggle, "BOTTOMLEFT", 0, -12)
    minimapToggle:SetSize(26, 26)
    
    local minimapSetting = true
    local mmp = OxedHub.db.profile.settings.minimapPosition
    if type(mmp) == "table" and mmp.hide ~= nil then
        minimapSetting = not mmp.hide
    end
    minimapToggle:SetChecked(minimapSetting)
    minimapToggle:SetScript("OnClick", function(self)
        local shown = self:GetChecked()
        if type(OxedHub.db.profile.settings.minimapPosition) ~= "table" then
            OxedHub.db.profile.settings.minimapPosition = { hide = not shown, minimapPos = 225 }
        else
            OxedHub.db.profile.settings.minimapPosition.hide = not shown
        end
        if OxedHub.MinimapButton then
            OxedHub.MinimapButton:SetShown(shown)
        end
    end)
    
    local minimapLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    minimapLabel:SetPoint("LEFT", minimapToggle, "RIGHT", 4, 0)
    minimapLabel:SetText(L["SETTINGS_RING_MINIMAP"])
    minimapLabel:SetTextColor(1, 1, 1, 1)

    local accessibilitySection = CreateSettingsSectionHeader(scrollChild, minimapToggle, "BOTTOMLEFT", -14, -28, L["SETTINGS_SECTION_ACCESSIBILITY"])

    -- Text Size Offset
    local textSizeLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    textSizeLabel:SetPoint("TOPLEFT", accessibilitySection, "BOTTOMLEFT", 18, -12)
    textSizeLabel:SetText(L["SETTINGS_TEXT_SIZE"])
    textSizeLabel:SetTextColor(1, 0.82, 0, 1)

    local textSizeInfoBtn = CreateFrame("Button", nil, scrollChild)
    textSizeInfoBtn:SetSize(18, 18)
    textSizeInfoBtn:SetPoint("LEFT", textSizeLabel, "RIGHT", 6, 0)
    
    local textSizeInfoTex = textSizeInfoBtn:CreateTexture(nil, "ARTWORK")
    textSizeInfoTex:SetAllPoints(textSizeInfoBtn)
    textSizeInfoTex:SetTexture("Interface\\Common\\Help-i")
    textSizeInfoBtn.texture = textSizeInfoTex
    
    textSizeInfoBtn:SetHighlightTexture("Interface\\Common\\Help-i")
    local highlight = textSizeInfoBtn:GetHighlightTexture()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    
    textSizeInfoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["SETTINGS_TEXT_SIZE"], 1, 0.82, 0)
        GameTooltip:AddLine(L["SETTINGS_TEXT_SIZE_DESC"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    textSizeInfoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function SetTextSizeValue(value)
        value = math.floor((tonumber(value) or 0) + 0.5)
        value = math.max(-3, math.min(6, value))
        OxedHub.db.profile.settings.textSizeOffset = value
        
        UI:ApplyGlobalTextSize()
        return value
    end

    local savedTextSize = (OxedHub.db.profile.settings and OxedHub.db.profile.settings.textSizeOffset) or 0
    local textSizeSlider

    if MinimalSliderWithSteppersMixin and CreateMinimalSliderFormatter then
        textSizeSlider = CreateFrame("Slider", "OxedHubSettingsTextSizeSlider", scrollChild, "MinimalSliderWithSteppersTemplate")
        textSizeSlider:SetPoint("TOPLEFT", textSizeLabel, "BOTTOMLEFT", 0, -10)
        textSizeSlider:SetSize(200, 20)
        local minVal, maxVal = -3, 6
        local step = 1
        local stepsCount = (maxVal - minVal) / step
        textSizeSlider:Init(savedTextSize, minVal, maxVal, stepsCount, {
            [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(val)
                    val = math.floor((tonumber(val) or 0) + 0.5)
                    if val == 0 then
                        return WHITE_FONT_COLOR:WrapTextInColorCode("Normal")
                    elseif val > 0 then
                        return WHITE_FONT_COLOR:WrapTextInColorCode("+" .. val .. " px")
                    else
                        return WHITE_FONT_COLOR:WrapTextInColorCode(val .. " px")
                    end
                end
            ),
        })
        textSizeSlider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
            SetTextSizeValue(value)
        end)
    else
        textSizeSlider = CreateFrame("Slider", "OxedHubSettingsTextSizeSlider", scrollChild, "OptionsSliderTemplate")
        textSizeSlider:SetPoint("TOPLEFT", textSizeLabel, "BOTTOMLEFT", 4, -16)
        textSizeSlider:SetWidth(180)
        textSizeSlider:SetMinMaxValues(-3, 6)
        textSizeSlider:SetValueStep(1)
        textSizeSlider:SetObeyStepOnDrag(true)
        local textSizeLow = _G[textSizeSlider:GetName() .. "Low"]
        local textSizeHigh = _G[textSizeSlider:GetName() .. "High"]
        local textSizeText = _G[textSizeSlider:GetName() .. "Text"]
        if textSizeLow then textSizeLow:SetText("-3") end
        if textSizeHigh then textSizeHigh:SetText("+6") end
        if textSizeText then textSizeText:SetText("") end

        local textSizeValue = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        textSizeValue:SetPoint("LEFT", textSizeSlider, "RIGHT", 14, 0)
        
        local function UpdateValueText(val)
            val = math.floor(val + 0.5)
            if val == 0 then
                textSizeValue:SetText("Normal")
            elseif val > 0 then
                textSizeValue:SetText("+" .. val .. " px")
            else
                textSizeValue:SetText(val .. " px")
            end
        end

        textSizeSlider:SetScript("OnValueChanged", function(_, value)
            local finalVal = SetTextSizeValue(value)
            UpdateValueText(finalVal)
        end)
        textSizeSlider:SetValue(savedTextSize)
        UpdateValueText(savedTextSize)
    end

    -- Language Selector label
    local langLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    langLabel:SetPoint("TOP", textSizeSlider, "BOTTOM", 0, -16)
    langLabel:SetPoint("LEFT", textSizeLabel, "LEFT", 0, 0)
    langLabel:SetText(L["SETTINGS_LANGUAGE"])
    langLabel:SetTextColor(1, 0.82, 0, 1)



    -- Modern dropdown button using WowStyle1DropdownTemplate / legacy fallback
    local languages = {
        { key = "enUS", name = "English (US)" },
        { key = "esES", name = "Español" },
        -- { key = "arAR", name = "Arabaci" },
    }

    local langDropdownBtn = CreateFrame("DropdownButton", "OxedHubSettingsLangBtn", scrollChild, "WowStyle1DropdownTemplate")
    if not langDropdownBtn then
        langDropdownBtn = CreateFrame("Button", "OxedHubSettingsLangBtn", scrollChild, "UIDropDownMenuTemplate")
    end
    langDropdownBtn:SetPoint("TOPLEFT", langLabel, "BOTTOMLEFT", 0, -8)
    
    local function IsLangSelected(langKey)
        return (OxedHub.db.profile.settings.language or "enUS") == langKey
    end

    local function SetSelectedLanguage(langKey, langName)
        OxedHub.db.profile.settings.language = langKey
        if langDropdownBtn.OverrideText then
            langDropdownBtn:OverrideText(langName)
        elseif UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(langDropdownBtn, langName)
        end

        OxedHub:ApplyLanguage(langKey)

        StaticPopupDialogs["OXEDHUB_RELOAD_UI"] = {
            text = OxedHub.L["LANGUAGE_RELOAD_PROMPT"] or "A reload of the UI is required to fully apply the language change. Reload now?",
            button1 = OxedHub.L["BTN_OK"] or "OK",
            button2 = OxedHub.L["BTN_CANCEL"] or "Cancel",
            OnAccept = function()
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("OXEDHUB_RELOAD_UI")
    end

    if langDropdownBtn.SetupMenu then
        -- Modern setup
        langDropdownBtn:SetSize(200, 26)
        langDropdownBtn:SetupMenu(function(dropdown, rootDescription)
            for _, entry in ipairs(languages) do
                rootDescription:CreateRadio(
                    entry.name,
                    IsLangSelected,
                    function()
                        SetSelectedLanguage(entry.key, entry.name)
                    end,
                    entry.key
                )
            end
        end)
    else
        -- Classic fallback setup
        UIDropDownMenu_SetWidth(langDropdownBtn, 180)
        UIDropDownMenu_Initialize(langDropdownBtn, function(self, level)
            for _, entry in ipairs(languages) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = entry.name
                info.value = entry.key
                info.checked = IsLangSelected(entry.key)
                info.func = function()
                    SetSelectedLanguage(entry.key, entry.name)
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)
    end

    local savedLang = OxedHub.db.profile.settings.language or "enUS"
    local activeLangName = "English (US)"
    for _, entry in ipairs(languages) do
        if entry.key == savedLang then
            activeLangName = entry.name
            break
        end
    end

    if langDropdownBtn.OverrideText then
        langDropdownBtn:OverrideText(activeLangName)
    elseif UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(langDropdownBtn, activeLangName)
    end

    local automationSection = CreateSettingsSectionHeader(scrollChild, langDropdownBtn, "BOTTOMLEFT", 0, -30, L["SETTINGS_SECTION_AUTO"])

    -- Allow Chat Message on Spell Cast Toggle
    local spellChatToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    spellChatToggle:SetPoint("TOPLEFT", automationSection, "BOTTOMLEFT", 14, -10)
    spellChatToggle:SetSize(26, 26)
    
    local spellChatSetting = false
    if OxedHub.db.profile.settings.allowChatOnSpellCast ~= nil then
        spellChatSetting = OxedHub.db.profile.settings.allowChatOnSpellCast
    end
    spellChatToggle:SetChecked(spellChatSetting)
    spellChatToggle:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.allowChatOnSpellCast = self:GetChecked()
        if OxedHub.Triggers and OxedHub.Triggers.RefreshAllCards then
            OxedHub.Triggers:RefreshAllCards()
        end
    end)
    
    local spellChatLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellChatLabel:SetPoint("LEFT", spellChatToggle, "RIGHT", 4, 0)
    spellChatLabel:SetText(L["SETTINGS_AUTO_CHAT"])
    spellChatLabel:SetTextColor(1, 1, 1, 1)

    local spellChatDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    spellChatDesc:SetPoint("TOPLEFT", spellChatToggle, "BOTTOMLEFT", 28, -2)
    spellChatDesc:SetText(L["SETTINGS_AUTO_CHAT_DESC"])

    -- Allow Toy Macros in the ring Toggle
    local toyMacroToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    toyMacroToggle:SetPoint("TOPLEFT", spellChatToggle, "BOTTOMLEFT", 0, -28)
    toyMacroToggle:SetSize(26, 26)
    
    local toyMacroSetting = false
    if OxedHub.db.profile.settings.allowToyMacrosInRing ~= nil then
        toyMacroSetting = OxedHub.db.profile.settings.allowToyMacrosInRing
    end
    toyMacroToggle:SetChecked(toyMacroSetting)
    toyMacroToggle:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.allowToyMacrosInRing = self:GetChecked()
    end)
    
    local toyMacroLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    toyMacroLabel:SetPoint("LEFT", toyMacroToggle, "RIGHT", 4, 0)
    toyMacroLabel:SetText(L["SETTINGS_AUTO_TOY"])
    toyMacroLabel:SetTextColor(1, 1, 1, 1)

    local toyMacroDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    toyMacroDesc:SetPoint("TOPLEFT", toyMacroToggle, "BOTTOMLEFT", 28, -2)
    toyMacroDesc:SetText(L["SETTINGS_AUTO_TOY_DESC"])

    -- Filter by Class Toggle
    local classFilterToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    classFilterToggle:SetPoint("TOP", toyMacroDesc, "BOTTOM", 0, -10)
    classFilterToggle:SetPoint("LEFT", spellChatToggle, "LEFT", 0, 0)
    classFilterToggle:SetSize(26, 26)
    
    local classFilterSetting = false
    if OxedHub.db.profile.settings.filterByClass ~= nil then
        classFilterSetting = OxedHub.db.profile.settings.filterByClass
    end
    classFilterToggle:SetChecked(classFilterSetting)
    classFilterToggle:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.filterByClass = self:GetChecked()
        -- Refresh UI if ActionHub or Triggers is open
        if OxedHub.ActionHub and OxedHub.ActionHub.RefreshPickerList then
            OxedHub.ActionHub:RefreshPickerList()
        end
        if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then
            OxedHub.Triggers:RefreshTriggersList()
        end
    end)
    
    local classFilterLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classFilterLabel:SetPoint("LEFT", classFilterToggle, "RIGHT", 4, 0)
    classFilterLabel:SetText(L["SETTINGS_AUTO_FILTER"])
    classFilterLabel:SetTextColor(1, 1, 1, 1)

    local classFilterDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    classFilterDesc:SetPoint("TOPLEFT", classFilterToggle, "BOTTOMLEFT", 28, -2)
    classFilterDesc:SetText(L["SETTINGS_AUTO_FILTER_DESC"])

    -- Skip Delete Confirmation Toggle
    local skipDelConfirmToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    skipDelConfirmToggle:SetPoint("TOP", classFilterDesc, "BOTTOM", 0, -10)
    skipDelConfirmToggle:SetPoint("LEFT", spellChatToggle, "LEFT", 0, 0)
    skipDelConfirmToggle:SetSize(26, 26)

    local skipDelConfirmSetting = false
    if OxedHub.db.profile.settings.skipDeleteConfirmation ~= nil then
        skipDelConfirmSetting = OxedHub.db.profile.settings.skipDeleteConfirmation
    end
    skipDelConfirmToggle:SetChecked(skipDelConfirmSetting)
    skipDelConfirmToggle:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.skipDeleteConfirmation = self:GetChecked()
    end)

    local skipDelConfirmLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    skipDelConfirmLabel:SetPoint("LEFT", skipDelConfirmToggle, "RIGHT", 4, 0)
    skipDelConfirmLabel:SetText(L["SETTINGS_AUTO_SKIP_DEL"])
    skipDelConfirmLabel:SetTextColor(1, 1, 1, 1)

    local skipDelConfirmDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    skipDelConfirmDesc:SetPoint("TOPLEFT", skipDelConfirmToggle, "BOTTOMLEFT", 28, -2)
    skipDelConfirmDesc:SetText(L["SETTINGS_AUTO_SKIP_DEL_DESC"])

    local testerModeToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    testerModeToggle:SetPoint("TOP", skipDelConfirmDesc, "BOTTOM", 0, -10)
    testerModeToggle:SetPoint("LEFT", spellChatToggle, "LEFT", 0, 0)
    testerModeToggle:SetSize(26, 26)

    local testerModeSetting = false
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.testerMode ~= nil then
        testerModeSetting = OxedHub.db.profile.settings.testerMode
    end
    testerModeToggle:SetChecked(testerModeSetting)

    local testerModeLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    testerModeLabel:SetPoint("LEFT", testerModeToggle, "RIGHT", 4, 0)
    testerModeLabel:SetText(L["SETTINGS_TESTER_MODE"] or "Tester Mode")
    testerModeLabel:SetTextColor(1, 1, 1, 1)

    local testerModeDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    testerModeDesc:SetPoint("TOPLEFT", testerModeToggle, "BOTTOMLEFT", 28, -2)
    testerModeDesc:SetText(L["SETTINGS_TESTER_MODE_DESC"] or "*Provides access to experimental functions and triggers that are currently under test.")

    -- Tester Features Information Card (Shown when Tester Mode is enabled)
    local testerFeaturesCard = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    testerFeaturesCard:SetSize(620, 94)
    testerFeaturesCard:SetPoint("TOPLEFT", testerModeDesc, "BOTTOMLEFT", -2, -14)
    testerFeaturesCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    testerFeaturesCard:SetBackdropColor(0.04, 0.05, 0.07, 0.90)
    testerFeaturesCard:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.8)

    -- Prey Hunt and Anti-AFK graduated out of tester mode: both are on for
    -- everyone now, so this card no longer lists them as test features.
    local cardHeader = testerFeaturesCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cardHeader:SetPoint("TOPLEFT", testerFeaturesCard, "TOPLEFT", 16, -10)
    cardHeader:SetText("|cFFFFD900Everything is live!|r")

    local f1Title = testerFeaturesCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f1Title:SetPoint("TOPLEFT", cardHeader, "BOTTOMLEFT", 0, -6)
    f1Title:SetPoint("RIGHT", testerFeaturesCard, "RIGHT", -16, 0)
    f1Title:SetJustifyH("LEFT")
    f1Title:SetText("Thanks for testing the previous features — they have all shipped.")

    local f2Title = testerFeaturesCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f2Title:SetPoint("TOPLEFT", f1Title, "BOTTOMLEFT", 0, -6)
    f2Title:SetPoint("RIGHT", testerFeaturesCard, "RIGHT", -16, 0)
    f2Title:SetJustifyH("LEFT")
    f2Title:SetText("|cFFFFDD00Anti-AFK BG Guard|r and |cFFFFDD00Prey Hunt Tracker|r are now available to everyone.")

    local hintText = testerFeaturesCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hintText:SetPoint("TOPLEFT", f2Title, "BOTTOMLEFT", 0, -8)
    hintText:SetPoint("RIGHT", testerFeaturesCard, "RIGHT", -16, 0)
    hintText:SetJustifyH("LEFT")
    hintText:SetText("|cff00ff00* Nothing is gated behind this toggle right now. New test features will appear here.|r")

    local function UpdateTesterCardVisibility()
        local isChecked = testerModeToggle:GetChecked()
        testerFeaturesCard:SetShown(isChecked)
    end
    UpdateTesterCardVisibility()

    testerModeToggle:SetScript("OnClick", function(self)
        local isEnabled = self:GetChecked()
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
            OxedHub.db.profile.settings.testerMode = isEnabled
        end
        UpdateTesterCardVisibility()
        if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then
            OxedHub.Triggers:RefreshTriggersList()
        end
        if OxedHub.Triggers and OxedHub.Triggers.selectedTriggerId then
            OxedHub.Triggers:RefreshTriggerCard(OxedHub.Triggers.selectedTriggerId)
        end
        if OxedHub.Prey and OxedHub.Prey.Engine and OxedHub.Prey.Engine.UpdateActiveHunt then
            OxedHub.Prey.Engine:UpdateActiveHunt()
        end
        if not isEnabled and OxedHub.AntiAFK and OxedHub.AntiAFK.HUD then
            OxedHub.AntiAFK.HUD:Hide()
        end
    end)

    -- Defaults & Reset Section
    local defaultsSection = CreateSettingsSectionHeader(scrollChild, testerFeaturesCard, "BOTTOMLEFT", 2, -26, L["SETTINGS_SECTION_DEFAULTS"] or "Defaults & Reset")

    local resetDefaultsBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    resetDefaultsBtn:SetSize(210, 26)
    resetDefaultsBtn:SetPoint("TOPLEFT", defaultsSection, "BOTTOMLEFT", 18, -12)
    resetDefaultsBtn:SetText(L["SETTINGS_RESET_DEFAULTS"] or "Reset to Default Settings")
    resetDefaultsBtn:SetNormalFontObject("GameFontNormalSmall")

    local resetDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resetDesc:SetPoint("TOPLEFT", resetDefaultsBtn, "BOTTOMLEFT", 0, -8)
    resetDesc:SetWidth(560)
    resetDesc:SetJustifyH("LEFT")
    resetDesc:SetText(L["SETTINGS_RESET_DEFAULTS_DESC"] or "*Restores all addon settings in this profile back to their default values. Your triggers, sounds, and animations are not affected.")

    resetDefaultsBtn:SetScript("OnClick", function()
        if not StaticPopupDialogs["OXEDHUB_RESET_SETTINGS"] then
            StaticPopupDialogs["OXEDHUB_RESET_SETTINGS"] = {
                text = L["SETTINGS_RESET_CONFIRM_PROMPT"] or "Are you sure you want to reset all settings in this profile to their defaults?\n\n(Your triggers, custom sounds, and animations will NOT be deleted. The UI will reload to apply defaults).",
                button1 = L["SETTINGS_BTN_RESET"] or L["BTN_RESET"] or "Reset",
                button2 = L["SETTINGS_BTN_CANCEL"] or L["BTN_CANCEL"] or "Cancel",
                OnAccept = function()
                    if OxedHub.DEFAULTS and OxedHub.DEFAULTS.settings and OxedHub.db and OxedHub.db.profile then
                        OxedHub.db.profile.settings = CopyTable(OxedHub.DEFAULTS.settings)
                    end
                    ReloadUI()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
        end
        StaticPopup_Show("OXEDHUB_RESET_SETTINGS")
    end)

    -- Boundary between the two pages: everything built so far is "Main".
    local function SnapshotWidgets(parent)
        local set = {}
        for _, child in ipairs({ parent:GetChildren() }) do set[child] = true end
        for _, region in ipairs({ parent:GetRegions() }) do set[region] = true end
        return set
    end
    local mainPageSet = SnapshotWidgets(scrollChild)

    -- ── Profile Switcher & Hero Card ─────────────────────────────────────
    local profilesSection = CreateSettingsSectionHeader(scrollChild, scrollChild, "TOPLEFT", 15, -8, L["SETTINGS_SECTION_PROFILES"])

    -- Active Profile Hero Banner
    local activeHeroCard = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    activeHeroCard:SetSize(480, 115)
    activeHeroCard:SetPoint("TOPLEFT", profilesSection, "BOTTOMLEFT", 10, -12)
    activeHeroCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    activeHeroCard:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
    activeHeroCard:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.75)

    local heroAccent = activeHeroCard:CreateTexture(nil, "OVERLAY")
    heroAccent:SetPoint("TOPLEFT", 4, -4)
    heroAccent:SetPoint("BOTTOMLEFT", 4, 4)
    heroAccent:SetWidth(4)
    heroAccent:SetColorTexture(1, 0.82, 0, 0.9)

    local heroIconFrame = CreateFrame("Frame", nil, activeHeroCard, "BackdropTemplate")
    heroIconFrame:SetSize(46, 46)
    heroIconFrame:SetPoint("TOPLEFT", activeHeroCard, "TOPLEFT", 18, -14)
    heroIconFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    heroIconFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    heroIconFrame:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.85)

    local heroClassIcon = heroIconFrame:CreateTexture(nil, "ARTWORK")
    heroClassIcon:SetPoint("TOPLEFT", heroIconFrame, "TOPLEFT", 2, -2)
    heroClassIcon:SetPoint("BOTTOMRIGHT", heroIconFrame, "BOTTOMRIGHT", -2, 2)
    heroClassIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    heroClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local heroTitle = activeHeroCard:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    heroTitle:SetPoint("TOPLEFT", heroIconFrame, "TOPRIGHT", 14, -2)
    heroTitle:SetPoint("RIGHT", activeHeroCard, "RIGHT", -16, 0)
    heroTitle:SetJustifyH("LEFT")
    heroTitle:SetText("Profile Name")

    local heroSubtitle = activeHeroCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    heroSubtitle:SetPoint("TOPLEFT", heroTitle, "BOTTOMLEFT", 0, -4)
    heroSubtitle:SetText("|cff00ff00• Active Profile|r")

    local switchLabel = activeHeroCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    switchLabel:SetPoint("BOTTOMLEFT", activeHeroCard, "BOTTOMLEFT", 18, 14)
    switchLabel:SetText(L["SETTINGS_PROFILE_SWITCH_LABEL"] or "Switch Profile:")
    switchLabel:SetTextColor(1, 0.82, 0, 1)

    local profileDropdown = CreateFrame("DropdownButton", "OxedHubProfileDropdown", activeHeroCard, "WowStyle1DropdownTemplate")
    profileDropdown:SetPoint("LEFT", switchLabel, "RIGHT", 8, 0)
    profileDropdown:SetSize(230, 24)

    local profileColorBtn = CreateFrame("Button", nil, activeHeroCard, "BackdropTemplate")
    profileColorBtn:SetSize(24, 24)
    profileColorBtn:SetPoint("LEFT", profileDropdown, "RIGHT", 8, 0)
    profileColorBtn:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    profileColorBtn:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    local profileColorTex = profileColorBtn:CreateTexture(nil, "ARTWORK")
    profileColorTex:SetPoint("TOPLEFT", 2, -2)
    profileColorTex:SetPoint("BOTTOMRIGHT", -2, 2)
    profileColorTex:SetColorTexture(1, 1, 1, 1)
    profileColorBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Profile Color", 1, 0.82, 0)
        GameTooltip:AddLine("Click to change this profile's name color.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    profileColorBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
        GameTooltip:Hide()
    end)

    profileColorBtn:SetScript("OnClick", function()
        local activeName = OxedHub:GetActiveProfileName()
        local r, g, b = profileColorTex:GetVertexColor()
        if not r then r, g, b = 1, 1, 1 end
        
        local function UpdateColor(nr, ng, nb)
            OxedHub.db.profile.metadata = OxedHub.db.profile.metadata or {}
            OxedHub.db.profile.metadata.customColor = {r = nr, g = ng, b = nb}
            UI.RefreshProfileDropdown()
            if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
        end
        
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({
                r = r, g = g, b = b, opacity = 1, hasOpacity = false,
                swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    UpdateColor(nr, ng, nb)
                end,
                cancelFunc = function(prev)
                    UpdateColor(prev.r, prev.g, prev.b)
                end
            })
        else
            ColorPickerFrame.func = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                UpdateColor(nr, ng, nb)
            end
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.cancelFunc = function(prev)
                UpdateColor(prev.r, prev.g, prev.b)
            end
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()
        end
    end)

    -- Auto-Switch Checkbox
    local autoSwitchToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    autoSwitchToggle:SetPoint("TOPLEFT", activeHeroCard, "BOTTOMLEFT", 0, -10)
    autoSwitchToggle:SetSize(24, 24)
    autoSwitchToggle:SetChecked(OxedHubDB and OxedHubDB.globalSettings and OxedHubDB.globalSettings.autoSwitchClassProfile == true)
    autoSwitchToggle:SetScript("OnClick", function(self)
        OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
        OxedHubDB.globalSettings.autoSwitchClassProfile = self:GetChecked()
    end)

    local autoSwitchLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoSwitchLabel:SetPoint("LEFT", autoSwitchToggle, "RIGHT", 4, 0)
    autoSwitchLabel:SetText(L["SETTINGS_PROFILES_AUTO"])
    autoSwitchLabel:SetTextColor(1, 1, 1, 1)

    local autoSwitchDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    autoSwitchDesc:SetPoint("TOPLEFT", autoSwitchToggle, "BOTTOMLEFT", 28, -2)
    autoSwitchDesc:SetWidth(440)
    autoSwitchDesc:SetJustifyH("LEFT")
    autoSwitchDesc:SetText(L["SETTINGS_PROFILES_AUTO_DESC"])

    -- Divider 1
    local divider1 = scrollChild:CreateTexture(nil, "BORDER")
    divider1:SetPoint("TOPLEFT", autoSwitchDesc, "BOTTOMLEFT", -20, -14)
    divider1:SetSize(480, 1)
    divider1:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    -- ── Create New Profile Section ────────────────────────────────────────
    local createHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    createHeader:SetPoint("TOPLEFT", divider1, "BOTTOMLEFT", 4, -14)
    createHeader:SetText(L["SETTINGS_PROFILE_CREATE_HEADER"] or "Create New Profile")
    createHeader:SetTextColor(1, 0.82, 0, 1)

    local newProfileInput = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    newProfileInput:SetSize(160, 24)
    newProfileInput:SetPoint("TOPLEFT", createHeader, "BOTTOMLEFT", 6, -10)
    newProfileInput:SetAutoFocus(false)
    newProfileInput:SetMaxLetters(30)
    newProfileInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local activeProfileName = OxedHub:GetActiveProfileName()
    local selectedCreateClassToken = OxedHub:GetProfileClassToken(activeProfileName) or false

    local createClassDropdown = CreateFrame("DropdownButton", "OxedHubCreateClassDropdown", scrollChild, "WowStyle1DropdownTemplate")
    createClassDropdown:SetPoint("LEFT", newProfileInput, "RIGHT", 8, 0)
    createClassDropdown:SetSize(140, 24)
    SetupClassDropdown(
        createClassDropdown,
        function()
            return selectedCreateClassToken
        end,
        function(token)
            selectedCreateClassToken = token
            local activeName = OxedHub:GetActiveProfileName()
            if activeName then
                OxedHub:SetProfileClassToken(activeName, token)
                UI.RefreshProfileDropdown()
                if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
            end
        end
    )

    local createBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(createBtn)
    createBtn:SetSize(110, 24)
    createBtn:SetPoint("LEFT", createClassDropdown, "RIGHT", 8, 0)
    createBtn:SetText(L["SETTINGS_BTN_CREATE"] or "Create Profile")
    createBtn:SetNormalFontObject("GameFontNormalSmall")

    local infoBtn = CreateFrame("Button", nil, scrollChild)
    infoBtn:SetSize(18, 18)
    infoBtn:SetPoint("LEFT", createBtn, "RIGHT", 6, 0)
    local infoTex = infoBtn:CreateTexture(nil, "ARTWORK")
    infoTex:SetAllPoints(infoBtn)
    infoTex:SetTexture("Interface\\Common\\Help-i")
    infoBtn.texture = infoTex
    infoBtn:SetHighlightTexture("Interface\\Common\\Help-i")
    local highlight = infoBtn:GetHighlightTexture()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.3)
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["SETTINGS_PROFILES_INFO_TITLE"], 1, 0.82, 0)
        GameTooltip:AddLine(L["SETTINGS_PROFILES_INFO_DESC"], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    createBtn:SetScript("OnClick", function()
        local name = newProfileInput:GetText():match("^%s*(.-)%s*$")
        if name == "" then return end
        local ok, reason = OxedHub:CreateProfile(name, selectedCreateClassToken)
        if ok then
            print("|cff00ff00Oxed Hub:|r Profile |cffffff00" .. name .. "|r created.")
            newProfileInput:SetText("")
            newProfileInput:ClearFocus()
            UI.RefreshProfileDropdown()
            if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
        elseif reason == "max_profiles" then
            print("|cffff0000Oxed Hub:|r Maximum of |cffffff00" .. OxedHub:GetMaxProfileCount() .. "|r profiles reached.")
        else
            print("|cffff0000Oxed Hub:|r Profile name already exists or is invalid.")
        end
    end)
    newProfileInput:SetScript("OnEnterPressed", function(self)
        createBtn:Click()
    end)

    -- Divider 2
    local divider2 = scrollChild:CreateTexture(nil, "BORDER")
    divider2:SetPoint("TOPLEFT", newProfileInput, "BOTTOMLEFT", -6, -16)
    divider2:SetSize(480, 1)
    divider2:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    -- ── Manage Active Profile Section ─────────────────────────────────────
    local manageHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    manageHeader:SetPoint("TOPLEFT", divider2, "BOTTOMLEFT", 4, -14)
    manageHeader:SetText(L["SETTINGS_PROFILE_ACTIONS_HEADER"] or "Manage Active Profile")
    manageHeader:SetTextColor(1, 0.82, 0, 1)

    local copyBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(copyBtn)
    copyBtn:SetSize(110, 24)
    copyBtn:SetPoint("TOPLEFT", manageHeader, "BOTTOMLEFT", 6, -10)
    copyBtn:SetText(L["SETTINGS_BTN_COPY"] or "Duplicate")
    copyBtn:SetNormalFontObject("GameFontNormalSmall")
    copyBtn:SetScript("OnClick", function()
        local src = OxedHub:GetActiveProfileName()
        local dest = newProfileInput:GetText():match("^%s*(.-)%s*$")
        if dest == "" then
            dest = src .. " (Copy)"
        end
        local ok, reason = OxedHub:CopyProfile(src, dest, selectedCreateClassToken)
        if ok then
            print("|cff00ff00Oxed Hub:|r Copied |cffffff00" .. src .. "|r to |cffffff00" .. dest .. "|r.")
            newProfileInput:SetText("")
            newProfileInput:ClearFocus()
            UI.RefreshProfileDropdown()
            if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
        elseif reason == "max_profiles" then
            print("|cffff0000Oxed Hub:|r Maximum of |cffffff00" .. OxedHub:GetMaxProfileCount() .. "|r profiles reached.")
        else
            print("|cffff0000Oxed Hub:|r Could not copy. Name already exists or is invalid.")
        end
    end)

    local renameBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(renameBtn)
    renameBtn:SetSize(100, 24)
    renameBtn:SetPoint("LEFT", copyBtn, "RIGHT", 10, 0)
    renameBtn:SetText(L["SETTINGS_BTN_RENAME"] or "Rename")
    renameBtn:SetNormalFontObject("GameFontNormalSmall")
    renameBtn:SetScript("OnClick", function()
        local newName = newProfileInput:GetText():match("^%s*(.-)%s*$")
        if newName == "" then
            print("|cffff0000Oxed Hub:|r Type a new name in the text field first, then click Rename.")
            return
        end
        local oldName = OxedHub:GetActiveProfileName()
        if OxedHub:RenameProfile(oldName, newName) then
            print("|cff00ff00Oxed Hub:|r Renamed |cffffff00" .. oldName .. "|r to |cffffff00" .. newName .. "|r.")
            newProfileInput:SetText("")
            newProfileInput:ClearFocus()
            UI.RefreshProfileDropdown()
            if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
        else
            print("|cffff0000Oxed Hub:|r Could not rename. Name already exists or is invalid.")
        end
    end)

    local deleteBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(deleteBtn)
    deleteBtn:SetSize(100, 24)
    deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 10, 0)
    deleteBtn:SetText(L["SETTINGS_BTN_DELETE"] or "Delete")
    deleteBtn:SetNormalFontObject("GameFontNormalSmall")
    deleteBtn:SetScript("OnClick", function()
        local activeName = OxedHub:GetActiveProfileName()
        local profiles = OxedHub:GetProfileList()
        if #profiles <= 1 then
            print("|cffff0000Oxed Hub:|r Can't delete the only profile.")
            return
        end
        StaticPopupDialogs["OXEDHUB_DELETE_PROFILE"] = {
            text = "Delete profile |cffffff00" .. activeName .. "|r?\nThis cannot be undone.",
            button1 = "Delete",
            button2 = "Cancel",
            OnAccept = function()
                for _, name in ipairs(profiles) do
                    if name ~= activeName then
                        OxedHub:SwitchProfile(name)
                        C_Timer.After(0.05, function()
                            OxedHub:DeleteProfile(activeName)
                            UI.RefreshProfileDropdown()
                            if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
                        end)
                        return
                    end
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("OXEDHUB_DELETE_PROFILE")
    end)

    local function RefreshProfileDropdown()
        local activeName = OxedHub:GetActiveProfileName()
        profileDropdown:OverrideText(OxedHub:GetProfileColoredName(activeName))
        
        -- Update hero card header
        heroTitle:SetText(OxedHub:GetProfileColoredName(activeName))
        local classToken = OxedHub:GetProfileClassToken(activeName)
        local className = classToken and (OxedHub:GetClassDisplayName(classToken) or classToken) or "Any Class"
        heroSubtitle:SetText("|cff00ff00• " .. (L["SETTINGS_PROFILE_STATUS_ACTIVE"] or "Active") .. "|r  |  |cffffd100Class:|r " .. className)

        -- Update class crest on hero card
        if classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken:upper()] then
            heroClassIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS[classToken:upper()]
            heroClassIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            heroClassIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            heroClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        
        local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local clsColor = classToken and classColors and classColors[classToken]
        if clsColor then
            heroIconFrame:SetBackdropBorderColor(clsColor.r, clsColor.g, clsColor.b, 0.9)
        else
            heroIconFrame:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.85)
        end
        
        -- Update color swatch button color
        local metadata = OxedHub:GetProfileMetadata(activeName)
        if metadata and metadata.customColor then
            profileColorTex:SetColorTexture(metadata.customColor.r, metadata.customColor.g, metadata.customColor.b, 1)
        else
            local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
            local color = classToken and classColors and classColors[classToken]
            if color then
                profileColorTex:SetColorTexture(color.r, color.g, color.b, 1)
            else
                profileColorTex:SetColorTexture(1, 1, 1, 1)
            end
        end

        profileDropdown:SetupMenu(function(dropdown, rootDescription)
            local profiles = OxedHub:GetProfileList()
            for _, name in ipairs(profiles) do
                rootDescription:CreateRadio(
                    OxedHub:GetProfileColoredName(name),
                    function() return name == OxedHub:GetActiveProfileName() end,
                    function()
                        OxedHub:SwitchProfile(name)
                        UI.RefreshProfileDropdown()
                        if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
                    end,
                    name
                )
            end
        end)
    end
    UI.RefreshProfileDropdown = RefreshProfileDropdown
    RefreshProfileDropdown()

    -- Second boundary: everything from here on is the Export/Import sub-page.
    local profileManageSet = SnapshotWidgets(scrollChild)

    -- ── Export / Import section ───────────────────────────────────────────
    local exportSection = CreateSettingsSectionHeader(scrollChild, scrollChild, "TOPLEFT", 15, -8, L["SETTINGS_SECTION_EXPORT"])

    -- Left Card: Export Hub
    local exportCard = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    exportCard:SetSize(470, 420)
    exportCard:SetPoint("TOPLEFT", exportSection, "BOTTOMLEFT", 10, -12)
    exportCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    exportCard:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
    exportCard:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.75)

    local expAccent = exportCard:CreateTexture(nil, "OVERLAY")
    expAccent:SetPoint("TOPLEFT", 4, -4)
    expAccent:SetPoint("BOTTOMLEFT", 4, 4)
    expAccent:SetWidth(4)
    expAccent:SetColorTexture(1, 0.82, 0, 0.9)

    local expTitle = exportCard:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    expTitle:SetPoint("TOPLEFT", exportCard, "TOPLEFT", 18, -14)
    expTitle:SetText(L["SETTINGS_EXPORT_CARD_TITLE"] or "Export Configuration")

    local expDesc = exportCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    expDesc:SetPoint("TOPLEFT", expTitle, "BOTTOMLEFT", 0, -4)
    expDesc:SetPoint("RIGHT", exportCard, "RIGHT", -16, 0)
    expDesc:SetJustifyH("LEFT")
    expDesc:SetText(L["SETTINGS_EXPORT_CARD_DESC"] or "Generate a shareable text string to export profiles, triggers, rings, or action hubs.")

    local expDivider1 = exportCard:CreateTexture(nil, "BORDER")
    expDivider1:SetPoint("TOPLEFT", expDesc, "BOTTOMLEFT", -2, -10)
    expDivider1:SetPoint("RIGHT", exportCard, "RIGHT", -16, 0)
    expDivider1:SetHeight(1)
    expDivider1:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    -- Export Buttons
    local exportBtn = CreateFrame("Button", nil, exportCard, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(exportBtn)
    exportBtn:SetPoint("TOPLEFT", expDivider1, "BOTTOMLEFT", 0, -12)
    exportBtn:SetSize(210, 26)
    exportBtn:SetText(L["SETTINGS_EXPORT_ACTIVE_BTN"] or "Export Active Profile")
    exportBtn:SetNormalFontObject("GameFontNormalSmall")
    exportBtn:SetScript("OnClick", function()
        UI:ShowExportFrame()
    end)
    exportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Export Active Profile", 1, 0.82, 0)
        GameTooltip:AddLine("Generate a compressed export string for your active profile and all its components.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    exportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local scopedExportBtn = CreateFrame("Button", nil, exportCard, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(scopedExportBtn)
    scopedExportBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    scopedExportBtn:SetSize(210, 26)
    scopedExportBtn:SetText(L["SETTINGS_EXPORT_DETAILED_BTN"] or "Detailed / Custom Export")
    scopedExportBtn:SetNormalFontObject("GameFontNormalSmall")
    scopedExportBtn:SetScript("OnClick", function()
        UI:ShowScopedExportFrame()
    end)
    scopedExportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Detailed / Custom Export", 1, 0.82, 0)
        GameTooltip:AddLine("Choose specific content to export: individual triggers, ActionHubs, OxedRing, or toy mixes.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    scopedExportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Share the active profile as a clickable chat link.  The data is not put
    -- in the chat message; the link only carries a share ID, and the payload
    -- transfers over the addon channel when someone clicks it.
    local shareLinkBtn = CreateFrame("Button", nil, exportCard, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(shareLinkBtn)
    shareLinkBtn:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -10)
    shareLinkBtn:SetSize(430, 26)
    shareLinkBtn:SetText(L["SETTINGS_SHARE_LINK_BTN"] or "Share to Chat (Link)")
    shareLinkBtn:SetNormalFontObject("GameFontNormalSmall")
    shareLinkBtn:SetScript("OnClick", function()
        local Share = OxedHub.Share
        if not Share then
            print("|cffff0000Oxed Hub:|r Sharing module unavailable.")
            return
        end
        local profileName = OxedHub:GetActiveProfileName() or "Profile"
        Share:ShowChannelPicker("profile", nil, profileName)
    end)
    shareLinkBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["SETTINGS_SHARE_LINK_BTN"] or "Share to Chat (Link)")
        GameTooltip:AddLine("Puts a clickable link in your chat box for the active profile.", 1, 1, 1, true)
        GameTooltip:AddLine("Pick a channel and send it. Anyone with Oxed Hub can click to import.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    shareLinkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The transfer is peer-to-peer over the addon channel, so it only runs
    -- while both players are logged in.  Say so plainly next to the button.
    local shareNote = exportCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shareNote:SetPoint("TOPLEFT", shareLinkBtn, "BOTTOMLEFT", 2, -8)
    shareNote:SetWidth(430)
    shareNote:SetJustifyH("LEFT")
    shareNote:SetSpacing(2)
    shareNote:SetText(L["SETTINGS_SHARE_LINK_NOTE"]
        or "|cffffd100Both players must stay logged in until the transfer finishes.|r\n"
        .. "|cff888888A large profile can take around 30 seconds to send.|r")

    local expDivider2 = exportCard:CreateTexture(nil, "BORDER")
    expDivider2:SetPoint("TOPLEFT", shareNote, "BOTTOMLEFT", -2, -14)
    expDivider2:SetPoint("RIGHT", exportCard, "RIGHT", -16, 0)
    expDivider2:SetHeight(1)
    expDivider2:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    -- Author Nickname
    local exportNicknameLabel = exportCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportNicknameLabel:SetPoint("TOPLEFT", expDivider2, "BOTTOMLEFT", 0, -12)
    exportNicknameLabel:SetText(L["SETTINGS_EXPORT_NICKNAME"] or "Author Nickname (optional):")
    exportNicknameLabel:SetTextColor(1, 0.82, 0, 1)

    local exportNicknameBox = CreateFrame("EditBox", nil, exportCard, "InputBoxTemplate")
    exportNicknameBox:SetPoint("TOPLEFT", exportNicknameLabel, "BOTTOMLEFT", 6, -6)
    exportNicknameBox:SetSize(320, 22)
    exportNicknameBox:SetAutoFocus(false)
    exportNicknameBox:SetMaxLetters(50)
    exportNicknameBox:SetText(UI:GetExportNickname() or "")
    exportNicknameBox:SetScript("OnEnterPressed", function(self)
        UI:SetExportNickname(self:GetText())
        self:ClearFocus()
    end)
    exportNicknameBox:SetScript("OnEditFocusLost", function(self)
        UI:SetExportNickname(self:GetText())
    end)

    -- Export Note
    local exportNoteLabel = exportCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportNoteLabel:SetPoint("TOPLEFT", exportNicknameBox, "BOTTOMLEFT", -6, -14)
    exportNoteLabel:SetText(L["SETTINGS_EXPORT_NOTE"] or "Export Note (optional):")
    exportNoteLabel:SetTextColor(1, 0.82, 0, 1)

    local exportNoteBox = CreateFrame("EditBox", nil, exportCard, "InputBoxTemplate")
    exportNoteBox:SetPoint("TOPLEFT", exportNoteLabel, "BOTTOMLEFT", 6, -6)
    exportNoteBox:SetSize(420, 22)
    exportNoteBox:SetAutoFocus(false)
    exportNoteBox:SetMaxLetters(120)
    exportNoteBox:SetText(UI:GetExportNote() or "")
    exportNoteBox:SetScript("OnEnterPressed", function(self)
        UI:SetExportNote(self:GetText())
        self:ClearFocus()
    end)
    exportNoteBox:SetScript("OnEditFocusLost", function(self)
        UI:SetExportNote(self:GetText())
    end)

    local expInfoText = exportCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    expInfoText:SetPoint("TOPLEFT", exportNoteBox, "BOTTOMLEFT", -6, -16)
    expInfoText:SetPoint("RIGHT", exportCard, "RIGHT", -16, 0)
    expInfoText:SetJustifyH("LEFT")
    expInfoText:SetSpacing(3)
    expInfoText:SetText("|cff888888• Exports are compressed base64 strings safe for sharing.\n• Large configurations are automatically split into manageable parts.\n• Author metadata and notes are bundled with the export.|r")

    -- Right Card: Import Hub
    local importCard = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    importCard:SetSize(470, 420)
    importCard:SetPoint("TOPLEFT", exportCard, "TOPRIGHT", 15, 0)
    importCard:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    importCard:SetBackdropColor(0.06, 0.06, 0.08, 0.90)
    importCard:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.75)

    local impAccent = importCard:CreateTexture(nil, "OVERLAY")
    impAccent:SetPoint("TOPLEFT", 4, -4)
    impAccent:SetPoint("BOTTOMLEFT", 4, 4)
    impAccent:SetWidth(4)
    impAccent:SetColorTexture(1, 0.82, 0, 0.9)

    local impTitle = importCard:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    impTitle:SetPoint("TOPLEFT", importCard, "TOPLEFT", 18, -14)
    impTitle:SetText(L["SETTINGS_IMPORT_CARD_TITLE"] or "Import Configuration")

    local impDesc = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    impDesc:SetPoint("TOPLEFT", impTitle, "BOTTOMLEFT", 0, -4)
    impDesc:SetPoint("RIGHT", importCard, "RIGHT", -16, 0)
    impDesc:SetJustifyH("LEFT")
    impDesc:SetText(L["SETTINGS_IMPORT_CARD_DESC"] or "Import a full profile, trigger collection, or action hub from a string.")

    local impDivider1 = importCard:CreateTexture(nil, "BORDER")
    impDivider1:SetPoint("TOPLEFT", impDesc, "BOTTOMLEFT", -2, -10)
    impDivider1:SetPoint("RIGHT", importCard, "RIGHT", -16, 0)
    impDivider1:SetHeight(1)
    impDivider1:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    local importBtn = CreateFrame("Button", nil, importCard, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(importBtn)
    importBtn:SetPoint("TOPLEFT", impDivider1, "BOTTOMLEFT", 0, -12)
    importBtn:SetSize(220, 26)
    importBtn:SetText(L["SETTINGS_IMPORT_OPEN_BTN"] or "Open Import Dialog")
    importBtn:SetNormalFontObject("GameFontNormalSmall")
    importBtn:SetScript("OnClick", function()
        UI:ShowImportFrame()
    end)
    importBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open Import Dialog", 1, 0.82, 0)
        GameTooltip:AddLine("Paste any export string to preview and import triggers, profiles, or hubs.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    importBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local impDivider2 = importCard:CreateTexture(nil, "BORDER")
    impDivider2:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -14)
    impDivider2:SetPoint("RIGHT", importCard, "RIGHT", -16, 0)
    impDivider2:SetHeight(1)
    impDivider2:SetColorTexture(0.58, 0.48, 0.34, 0.35)

    local impFeaturesHeader = importCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    impFeaturesHeader:SetPoint("TOPLEFT", impDivider2, "BOTTOMLEFT", 0, -12)
    impFeaturesHeader:SetText("Smart Import Features:")
    impFeaturesHeader:SetTextColor(1, 0.82, 0, 1)

    local impFeaturesList = importCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    impFeaturesList:SetPoint("TOPLEFT", impFeaturesHeader, "BOTTOMLEFT", 0, -8)
    impFeaturesList:SetPoint("RIGHT", importCard, "RIGHT", -16, 0)
    impFeaturesList:SetJustifyH("LEFT")
    impFeaturesList:SetSpacing(6)
    impFeaturesList:SetText(table.concat({
        "• |cffffd100Auto-Scope Detection:|r Automatically detects full profiles, triggers, rings, or action hubs.",
        "• |cffffd100Safe Confirmation:|r Previews authors, notes, and full content tables before applying.",
        "• |cffffd100Non-Destructive:|r Partial imports merge safely into your active profile without data loss.",
        "• |cffffd100Multi-Part Paste:|r Paste chunked multi-part strings in any order without confusion.",
    }, "\n"))

    local importStatus = importCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    importStatus:SetPoint("BOTTOMLEFT", importCard, "BOTTOMLEFT", 18, 14)
    importStatus:SetPoint("RIGHT", importCard, "RIGHT", -16, 0)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetText("")
    UI.importStatus = importStatus

    -- ── Live info panel (Details + Credits) ───────────────────────────────
    local infoPanel = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
    infoPanel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 520, -32)
    infoPanel:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
    infoPanel:SetHeight(420)
    infoPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    infoPanel:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    infoPanel:SetBackdropBorderColor(0.58, 0.48, 0.34, 0.6)
    infoPanel:Hide()

    local panelClassIcon = infoPanel:CreateTexture(nil, "ARTWORK")
    panelClassIcon:SetSize(32, 32)
    panelClassIcon:SetPoint("TOPLEFT", infoPanel, "TOPLEFT", 14, -14)
    panelClassIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    panelClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local detailsName = infoPanel:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    detailsName:SetPoint("TOPLEFT", panelClassIcon, "TOPRIGHT", 10, 0)
    detailsName:SetPoint("RIGHT", infoPanel, "RIGHT", -14, 0)
    detailsName:SetJustifyH("LEFT")

    local detailsMeta = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    detailsMeta:SetPoint("TOPLEFT", detailsName, "BOTTOMLEFT", 0, -3)

    local panelDivider1 = infoPanel:CreateTexture(nil, "BORDER")
    panelDivider1:SetPoint("TOPLEFT", panelClassIcon, "BOTTOMLEFT", 0, -10)
    panelDivider1:SetPoint("RIGHT", infoPanel, "RIGHT", -14, 0)
    panelDivider1:SetHeight(1)
    panelDivider1:SetColorTexture(0.58, 0.48, 0.34, 0.3)

    local detailsHeader = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailsHeader:SetPoint("TOPLEFT", panelDivider1, "BOTTOMLEFT", 0, -8)
    detailsHeader:SetText(L["SETTINGS_SECTION_DETAILS"] or "Profile Details")
    detailsHeader:SetTextColor(1, 0.82, 0, 1)

    local detailsCol1 = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailsCol1:SetPoint("TOPLEFT", detailsHeader, "BOTTOMLEFT", 0, -6)
    detailsCol1:SetWidth(190)
    detailsCol1:SetJustifyH("LEFT")
    detailsCol1:SetJustifyV("TOP")
    detailsCol1:SetSpacing(4)

    local detailsCol2 = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detailsCol2:SetPoint("LEFT", detailsCol1, "RIGHT", 14, 0)
    detailsCol2:SetPoint("TOP", detailsCol1, "TOP", 0, 0)
    detailsCol2:SetWidth(190)
    detailsCol2:SetJustifyH("LEFT")
    detailsCol2:SetJustifyV("TOP")
    detailsCol2:SetSpacing(4)

    local panelDivider2 = infoPanel:CreateTexture(nil, "BORDER")
    panelDivider2:SetPoint("TOPLEFT", detailsCol1, "BOTTOMLEFT", 0, -12)
    panelDivider2:SetPoint("RIGHT", infoPanel, "RIGHT", -14, 0)
    panelDivider2:SetHeight(1)
    panelDivider2:SetColorTexture(0.58, 0.48, 0.34, 0.3)

    local creditsHeader = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    creditsHeader:SetPoint("TOPLEFT", panelDivider2, "BOTTOMLEFT", 0, -8)
    creditsHeader:SetText(L["SETTINGS_SECTION_CREDITS"] or "Credits")
    creditsHeader:SetTextColor(1, 0.82, 0, 1)

    local creditsBody = infoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    creditsBody:SetPoint("TOPLEFT", creditsHeader, "BOTTOMLEFT", 0, -6)
    creditsBody:SetPoint("RIGHT", infoPanel, "RIGHT", -14, 0)
    creditsBody:SetJustifyH("LEFT")
    creditsBody:SetJustifyV("TOP")
    creditsBody:SetSpacing(3)

    local clearCreditsBtn = CreateFrame("Button", nil, infoPanel, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(clearCreditsBtn)
    clearCreditsBtn:SetSize(120, 22)
    clearCreditsBtn:SetPoint("BOTTOMLEFT", infoPanel, "BOTTOMLEFT", 14, 10)
    clearCreditsBtn:SetText(L["SETTINGS_BTN_CLEAR_CREDITS"] or "Clear Credits")
    clearCreditsBtn:SetNormalFontObject("GameFontNormalSmall")
    clearCreditsBtn:SetScript("OnClick", function()
        StaticPopupDialogs["OXEDHUB_CLEAR_CREDITS"] = {
            text = "Clear the import history for the active profile?\nThis only removes the credits list, not the imported content.",
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function()
                local db = OxedHubDB.profiles and OxedHubDB.profiles[OxedHubDB.activeProfile]
                if db then
                    db.importSources = nil
                    db.lastImport = nil
                end
                UI:RefreshProfileDetails()
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("OXEDHUB_CLEAR_CREDITS")
    end)

    function UI:RefreshProfileDetails()
        local name = OxedHubDB and OxedHubDB.activeProfile
        local db = name and OxedHubDB.profiles and OxedHubDB.profiles[name]
        if not db then
            detailsName:SetText("|cffff5555No active profile|r")
            detailsMeta:SetText("")
            detailsCol1:SetText("")
            detailsCol2:SetText("")
            creditsBody:SetText("")
            return
        end

        detailsName:SetText(OxedHub:GetProfileColoredName(name))

        local classToken = OxedHub:GetProfileClassToken(name)
        if classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken:upper()] then
            panelClassIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
            local coords = CLASS_ICON_TCOORDS[classToken:upper()]
            panelClassIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            panelClassIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            panelClassIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        local meta = OxedHub:GetProfileMetadata(name) or {}
        local metaBits = {}
        if classToken then
            table.insert(metaBits, "Class: " .. (OxedHub:GetClassDisplayName(classToken) or classToken))
        end
        if meta.addonVersion then table.insert(metaBits, "v" .. meta.addonVersion) end
        if db.lastImport and db.lastImport.date then
            table.insert(metaBits, "Imported: " .. date("%Y-%m-%d", db.lastImport.date))
        end
        detailsMeta:SetText(table.concat(metaBits, "  |  "))

        local s = UI:GetProfileStats(db)
        local function Row(label, value, extra)
            return string.format("|cffffd100• %s:|r %s%s", label, tostring(value), extra or "")
        end

        detailsCol1:SetText(table.concat({
            Row("Triggers", s.triggers, s.triggers > 0 and string.format(" |cff888888(%d on)|r", s.triggersEnabled) or ""),
            Row("Action Hubs", s.hubs),
            Row("Ring Nodes", s.ringNodes),
            Row("Toy Mixes", s.toyMixes),
        }, "\n"))

        detailsCol2:SetText(table.concat({
            Row("Custom Sounds", s.customSounds),
            Row("Animations", s.animations),
            Row("Chat Templates", s.chatTemplates),
            Row("Toy Tabs", s.toyCategories),
        }, "\n"))

        local credits = UI:GetProfileCredits(db)
        if #credits == 0 then
            creditsBody:SetText("|cff888888Nothing has been imported into this profile yet.|r")
            clearCreditsBtn:Hide()
        else
            local lines = {}
            for _, entry in ipairs(credits) do
                local scopeBits = {}
                for scope, count in pairs(entry.scopes) do
                    table.insert(scopeBits, count > 1 and (scope .. " x" .. count) or scope)
                end
                table.sort(scopeBits)
                table.insert(lines, string.format("%s  |cff888888%s|r",
                    UI:FormatAuthorName(entry.author, true),
                    entry.lastDate > 0 and date("%Y-%m-%d", entry.lastDate) or ""))
                table.insert(lines, "   |cff88ff88" .. table.concat(scopeBits, ", ") .. "|r")
                for _, note in ipairs(entry.notes) do
                    table.insert(lines, "   |cffffd100Note:|r |cffaaaaaa" .. note .. "|r")
                end
            end
            creditsBody:SetText(table.concat(lines, "\n"))
            clearCreditsBtn:Show()
        end
    end

    -- ── Wire up the Main / Profiles pages ─────────────────────────────────
    -- Anything created after the boundary snapshot belongs to the Profiles page.
    -- Three groups, split by the two snapshots: Main, profile management, and
    -- export/import. Details and Credits are their own frames, so they're
    -- excluded here and toggled directly.
    local mainWidgets, manageWidgets, exportWidgets = {}, {}, {}
    local function Classify(widget)
        if widget == infoPanel then return end
        if mainPageSet[widget] then
            table.insert(mainWidgets, widget)
        elseif profileManageSet[widget] then
            table.insert(manageWidgets, widget)
        else
            table.insert(exportWidgets, widget)
        end
    end
    for _, child in ipairs({ scrollChild:GetChildren() }) do Classify(child) end
    for _, region in ipairs({ scrollChild:GetRegions() }) do Classify(region) end

    -- ── Debug page ────────────────────────────────────────────────────────
    -- Sits on the tab frame rather than in the scroll child: it has its own
    -- scrolling list, and keeping it out of the Main/Profiles widget snapshot
    -- means the page split above does not have to know it exists.
    local debugPage = CreateFrame("Frame", nil, tab)
    debugPage:SetPoint("TOPLEFT", pageTabStrip, "BOTTOMLEFT", 0, -8)
    debugPage:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
    debugPage:Hide()

    local debugSummary = debugPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugSummary:SetPoint("TOPLEFT", debugPage, "TOPLEFT", 15, -10)
    debugSummary:SetTextColor(1, 0.82, 0, 1)

    local debugHint = debugPage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    debugHint:SetPoint("TOPLEFT", debugSummary, "BOTTOMLEFT", 0, -4)
    debugHint:SetText(L["DEBUG_HINT"] or "Only OxedHub's own problems are listed, newest first. Repeats are counted, not duplicated.")

    local copyBtn = CreateFrame("Button", nil, debugPage, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(copyBtn)
    copyBtn:SetSize(90, 24)
    copyBtn:SetPoint("TOPRIGHT", debugPage, "TOPRIGHT", -30, -8)
    copyBtn:SetText(L["DEBUG_COPY_ALL"] or "Copy All")

    local clearBtn = CreateFrame("Button", nil, debugPage, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(clearBtn)
    clearBtn:SetSize(90, 24)
    clearBtn:SetPoint("RIGHT", copyBtn, "LEFT", -6, 0)
    clearBtn:SetText(L["DEBUG_CLEAR"] or "Clear")

    local debugScroll = CreateFrame("ScrollFrame", "OxedHubDebugScrollFrame", debugPage, "UIPanelScrollFrameTemplate")
    debugScroll:SetPoint("TOPLEFT", debugHint, "BOTTOMLEFT", 0, -10)
    debugScroll:SetPoint("BOTTOMRIGHT", debugPage, "BOTTOMRIGHT", -30, 10)
    StyleScrollFrame(debugScroll)

    local debugList = CreateFrame("Frame", nil, debugScroll)
    debugList:SetSize(940, 1)
    debugScroll:SetScrollChild(debugList)

    -- Rows are pooled: the list is rebuilt on every visit to the page, and
    -- recreating frames each time would leak them for the session.
    local debugRows = {}

    local function AcquireDebugRow(index)
        local row = debugRows[index]
        if row then return row end

        row = CreateFrame("Frame", nil, debugList, "BackdropTemplate")
        row:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        row:SetBackdropColor(0.04, 0.04, 0.05, 0.65)
        row:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)
        row:SetWidth(920)

        row.head = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.head:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)
        row.head:SetPoint("RIGHT", row, "RIGHT", -70, 0)
        row.head:SetJustifyH("LEFT")

        row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.body:SetPoint("TOPLEFT", row.head, "BOTTOMLEFT", 0, -4)
        row.body:SetWidth(820)
        row.body:SetJustifyH("LEFT")

        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.meta:SetPoint("TOPLEFT", row.body, "BOTTOMLEFT", 0, -4)
        row.meta:SetJustifyH("LEFT")

        -- Per-row copy: pasting one problem into a report is far more common
        -- than pasting the whole journal.
        row.copyBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(row.copyBtn)
        row.copyBtn:SetSize(52, 20)
        row.copyBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -8)
        row.copyBtn:SetText(L["DEBUG_COPY"] or "Copy")
        row.copyBtn:SetNormalFontObject("GameFontNormalSmall")
        row.copyBtn:SetScript("OnClick", function(self)
            if self.entry and OxedHub.ErrorJournal then
                UI:ShowCopyDialog(OxedHub.ErrorJournal:FormatEntry(self.entry))
            end
        end)

        debugRows[index] = row
        return row
    end

    local function RefreshDebugPage()
        local journal = OxedHub.ErrorJournal
        if not journal then return end

        local entries = journal:GetEntries()
        local count, occurrences = journal:GetSummary()

        -- Read before the rows are drawn and updated after, so the visit that
        -- reveals a new problem still shows it marked.
        local lastViewed = journal:GetLastViewed()

        if count == 0 then
            debugSummary:SetText(L["DEBUG_NONE"] or "No problems recorded.")
        else
            debugSummary:SetText((L["DEBUG_SUMMARY"] or "%d problem(s), %d occurrence(s)"):format(count, occurrences))
        end

        local y = 0
        for i, entry in ipairs(entries) do
            local row = AcquireDebugRow(i)

            -- Blocked calls and Lua errors need telling apart at a glance: one
            -- means a protected API, the other a genuine fault in the addon.
            local kindColor = (entry.kind == "Blocked") and "ffff8000" or "ffff4040"
            local repeats = (entry.count or 1) > 1 and (" x%d"):format(entry.count) or ""

            -- Feature first, then the specific thing inside it. The feature is
            -- always known; the specific name only when that path is instrumented.
            local where = entry.area or (L["DEBUG_UNKNOWN_AREA"] or "Unknown")
            if entry.context then
                where = ("%s |cff888888>|r %s"):format(where, entry.context)
            end

            local isNew = (entry.lastSeen or 0) > lastViewed
            local newTag = isNew and ("|cff40ff40" .. (L["DEBUG_NEW"] or "NEW") .. "|r  ") or ""

            row.head:SetText(("%s|c%s[%s%s]|r  |cffffd100%s|r"):format(
                newTag, kindColor, entry.kind or "?", repeats, where))

            -- A brighter border rather than only a word, so a fresh problem is
            -- visible while scanning the list instead of needing to be read.
            if isNew then
                row:SetBackdropBorderColor(0.25, 0.9, 0.25, 0.9)
            else
                row:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)
            end

            row.copyBtn.entry = entry

            row.body:SetText(entry.message or "")

            local meta = {}
            if entry.source then meta[#meta + 1] = entry.source end
            meta[#meta + 1] = (L["DEBUG_LAST_SEEN"] or "last %s"):format(date("%d.%m %H:%M:%S", entry.lastSeen or time()))
            if (entry.count or 1) > 1 and entry.firstSeen then
                meta[#meta + 1] = (L["DEBUG_FIRST_SEEN"] or "first %s"):format(date("%d.%m %H:%M:%S", entry.firstSeen))
            end
            row.meta:SetText(table.concat(meta, "   |cff555555|||r   "))

            row:SetHeight(row.body:GetStringHeight() + 46)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", debugList, "TOPLEFT", 8, -y)
            row:Show()
            y = y + row:GetHeight() + 6
        end

        for i = #entries + 1, #debugRows do
            debugRows[i]:Hide()
        end

        debugList:SetHeight(math.max(y, 1))
        debugScroll:SetVerticalScroll(0)

        journal:MarkViewed()
    end
    tab.RefreshDebugPage = RefreshDebugPage

    clearBtn:SetScript("OnClick", function()
        if OxedHub.ErrorJournal then
            OxedHub.ErrorJournal:Clear()
            RefreshDebugPage()
        end
    end)

    copyBtn:SetScript("OnClick", function()
        if OxedHub.ErrorJournal then
            UI:ShowCopyDialog(OxedHub.ErrorJournal:BuildReport())
        end
    end)

    tab.activePage = tab.activePage or "main"
    tab.activeProfileSubPage = tab.activeProfileSubPage or "manage"

    local pageTabs, subTabs = {}, {}

    local function ApplyVisibility()
        local onProfiles = (tab.activePage == "profiles")
        local onDebug = (tab.activePage == "debug")
        local sub = tab.activeProfileSubPage

        -- Debug replaces the scrolling settings area outright, so the Main and
        -- Profiles widgets need no special handling here: hiding their scroll
        -- frame takes all of them off screen at once.
        scrollFrame:SetShown(not onDebug)
        debugPage:SetShown(onDebug)
        if onDebug then
            RefreshDebugPage()
        end

        for _, w in ipairs(mainWidgets) do w:SetShown(not onProfiles) end
        for _, w in ipairs(manageWidgets) do w:SetShown(onProfiles and sub == "manage") end
        for _, w in ipairs(exportWidgets) do w:SetShown(onProfiles and sub == "share") end
        infoPanel:SetShown(onProfiles and sub == "manage")
        -- The unused "title" fontstring must stay hidden on every page.
        title:Hide()

        for _, t in ipairs(subTabs) do
            t:SetShown(onProfiles)
            if t.subKey == sub then
                PanelTemplates_SelectTab(t)
                t:Enable()
            else
                PanelTemplates_DeselectTab(t)
            end
        end
        -- Red buttons show their active state via a locked highlight, the same
        -- way the Toys Mixer / My Mixes buttons do.
        for _, b in ipairs(pageTabs) do
            if b.pageKey == tab.activePage then
                b:LockHighlight()
            else
                b:UnlockHighlight()
            end
        end

        -- Collapse the sub-tab row on Main so the content moves up to meet it.
        pageTabStrip:SetHeight(onProfiles and 26 or 1)
        pageTabLine:SetShown(onProfiles)

        if onProfiles and sub == "manage" then
            UI:RefreshProfileDetails()
        end

        -- Size the scroll area to whichever page is showing.
        local height = 1060
        if onProfiles then
            height = (sub == "share") and 560 or 620
        end
        scrollChild:SetHeight(height)
        scrollFrame:SetVerticalScroll(0)
    end

    local function ShowSettingsPage(pageKey)
        tab.activePage = pageKey
        ApplyVisibility()
    end
    tab.ShowSettingsPage = ShowSettingsPage

    -- Sub-tabs on the second row, shown only while Profiles is active.
    local prevSubTab
    for _, sub in ipairs({
        { key = "manage", label = L["SETTINGS_SUB_MANAGE"] or "Profiles" },
        { key = "share",  label = L["SETTINGS_SUB_SHARE"] or "Export / Import" },
    }) do
        local subTab = CreateFrame("Button", nil, pageTabStrip, "PanelTopTabButtonTemplate")
        subTab:SetText(sub.label)
        subTab.subKey = sub.key
        PanelTemplates_TabResize(subTab, 15, nil, 70)
        if prevSubTab then
            subTab:SetPoint("BOTTOMLEFT", prevSubTab, "BOTTOMRIGHT", 4, 0)
        else
            subTab:SetPoint("BOTTOMLEFT", pageTabStrip, "BOTTOMLEFT", 0, 0)
        end
        subTab:SetScript("OnClick", function(self)
            tab.activeProfileSubPage = self.subKey
            ApplyVisibility()
        end)
        table.insert(subTabs, subTab)
        prevSubTab = subTab
    end

    -- Red page buttons, same style as the Toys "Mixer / My Mixes" pair.
    local pageBtnX = 0
    for _, page in ipairs({
        { key = "main", label = L["SETTINGS_PAGE_MAIN"] or "Main" },
        { key = "profiles", label = L["SETTINGS_PAGE_PROFILES"] or "Profiles" },
        { key = "debug", label = L["SETTINGS_PAGE_DEBUG"] or "Debug" },
    }) do
        local pageBtn = CreateFrame("Button", nil, pageButtonRow, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(pageBtn)
        pageBtn:SetSize(90, 25)
        pageBtn:SetPoint("TOPLEFT", pageButtonRow, "TOPLEFT", pageBtnX, 0)
        pageBtn:SetText(page.label)
        pageBtn.pageKey = page.key
        pageBtn:SetScript("OnClick", function(self) ShowSettingsPage(self.pageKey) end)
        table.insert(pageTabs, pageBtn)
        pageBtnX = pageBtnX + 95
    end

    ShowSettingsPage(tab.activePage)

    tab:Hide()
    contentArea.Settings = tab
end

-- Create About tab
function UI:CreateAboutTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(5)
    ApplyToysBackground(tab)

    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubAboutScrollFrame", tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -THEMED_FRAME_INSETS.top)
    scrollFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
    StyleScrollFrame(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    local scrollWidth = scrollFrame:GetWidth()
    if not scrollWidth or scrollWidth <= 0 then
        scrollWidth = 992
    else
        scrollWidth = scrollWidth - 20
    end
    scrollChild:SetSize(scrollWidth, 1)
    scrollFrame:SetScrollChild(scrollChild)
    tab.scrollFrame = scrollFrame
    tab.scrollChild = scrollChild
    
    -- Centered Title
    local welcomeTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    welcomeTitle:SetPoint("TOP", scrollChild, "TOP", 0, -15)
    welcomeTitle:SetText(L["ABOUT_WELCOME_TITLE"])
    welcomeTitle:SetTextColor(1, 0.82, 0, 1) -- Gold/yellow
    
    -- Centered Subtitle
    local welcomeSub = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    welcomeSub:SetPoint("TOP", welcomeTitle, "BOTTOM", 0, -6)
    welcomeSub:SetWidth(800)
    welcomeSub:SetJustifyH("CENTER")
    welcomeSub:SetText(L["ABOUT_WELCOME_SUB"])

    -- Card factory
    local function CreateCategoryCard(parent, titleText, iconTexture, width)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        card:SetWidth(width)
        
        -- Card styling: dark semi-transparent panel with thin border
        card:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        card:SetBackdropColor(0.04, 0.04, 0.05, 0.65)
        card:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)
        
        -- Header Icon
        local icon = card:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -12)
        icon:SetTexture(iconTexture)
        
        -- Header Title
        local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetText(titleText)
        title:SetTextColor(1, 0.82, 0, 1)
        
        -- Content FontString
        local content = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        content:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
        content:SetWidth(width - 24)
        content:SetJustifyH("LEFT")
        content:SetJustifyV("TOP")
        content:SetIndentedWordWrap(false)
        
        return card, content
    end

    -- 1. Features Card
    local featuresCard, featuresContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_FEATURES"], "Interface\\Icons\\Spell_Holy_DivinePurpose", 475)
    featuresContent:SetText(L["ABOUT_FEATURES_DESC"])
    
    -- 2. How to Use Card
    local howToUseCard, howToUseContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_HOW"], "Interface\\Icons\\INV_Misc_Book_09", 475)
    howToUseContent:SetText(L["ABOUT_HOW_DESC"])
    
    -- 3. Settings & Profiles Card
    local settingsCard, settingsContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_SETTINGS"], "Interface\\Icons\\Trade_engineering", 475)
    settingsContent:SetText(L["ABOUT_SETTINGS_DESC"])
    
    -- 4. Tips Card
    local tipsCard, tipsContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_TIPS"], "Interface\\Icons\\Spell_holy_auramastery", 475)
    tipsContent:SetText(L["ABOUT_TIPS_DESC"])
    
    -- 5. Recent Enhancements Card
    local updatesCard, updatesContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_UPDATES"], "Interface\\Icons\\INV_Misc_Gift_01", 475)
    updatesContent:SetText(L["ABOUT_UPDATES_DESC"])

    -- URL copy dialog for Discord
    local discordDialog = CreateFrame("Frame", "OxedHubDiscordDialog", UIParent, "BackdropTemplate")
    discordDialog:SetSize(460, 100)
    discordDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    discordDialog:SetFrameStrata("DIALOG")
    discordDialog:SetFrameLevel(500)
    discordDialog:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    discordDialog:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    discordDialog:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
    discordDialog:EnableMouse(true)
    discordDialog:SetMovable(true)
    discordDialog:RegisterForDrag("LeftButton")
    discordDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    discordDialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    discordDialog:Hide()

    local dlgLabel = discordDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlgLabel:SetPoint("TOPLEFT", discordDialog, "TOPLEFT", 12, -15)
    dlgLabel:SetText(L["ABOUT_DISCORD_LABEL"])
    dlgLabel:SetTextColor(1, 0.9, 0.4, 1)

    local urlBox = CreateFrame("EditBox", nil, discordDialog, "InputBoxTemplate")
    urlBox:SetSize(420, 22)
    urlBox:SetPoint("TOPLEFT", dlgLabel, "BOTTOMLEFT", 4, -10)
    urlBox:SetAutoFocus(false)
    urlBox:SetText("https://discord.gg/eJgvQUVxdR")
    urlBox:SetScript("OnShow",        function(self) self:SetFocus(); self:HighlightText() end)
    urlBox:SetScript("OnEscapePressed", function() discordDialog:Hide() end)

    local closeBtn = CreateFrame("Button", nil, discordDialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", discordDialog, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() discordDialog:Hide() end)

    -- 6. Discord & Community Card (Row 3 Right)
    local discordCard, discordContent = CreateCategoryCard(scrollChild, L["ABOUT_CARD_COMMUNITY"], "Interface\\Icons\\UI_Chat", 475)
    discordContent:SetText(L["ABOUT_COMMUNITY_DESC"])

    -- Discord Button
    local discordBtn = CreateFrame("Button", nil, discordCard, "UIPanelButtonTemplate")
    discordBtn:SetSize(110, 24)
    discordBtn:SetPoint("TOPLEFT", discordContent, "BOTTOMLEFT", 0, -10)
    discordBtn:SetText(L["ABOUT_BTN_DISCORD"])
    discordBtn:SetNormalFontObject("GameFontNormalSmall")
    discordBtn:SetScript("OnClick", function()
        if discordDialog:IsShown() then
            discordDialog:Hide()
        else
            discordDialog:Show()
            urlBox:SetFocus()
            urlBox:HighlightText()
        end
    end)

    -- Muted Credits String
    local thanksText = discordCard:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    thanksText:SetPoint("TOPLEFT", discordBtn, "BOTTOMLEFT", 0, -15)
    thanksText:SetWidth(451)
    thanksText:SetJustifyH("LEFT")
    thanksText:SetText(L["ABOUT_THANKS"])

    local createdText = discordCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    createdText:SetPoint("BOTTOMLEFT", discordCard, "BOTTOMLEFT", 12, 12)
    createdText:SetText("|cffff8000" .. (L["ABOUT_CREATED_BY"] or "Created by Oxed and The Lav Forge.") .. "|r")

    -- Position all cards
    featuresCard:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, -90)
    howToUseCard:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 497, -90)

    tab:SetScript("OnShow", function()
        -- Brief delay to ensure WoW engine completes font measuring pass
        C_Timer.After(0.05, function()
            if not tab:IsShown() then return end
            
            -- Row 1: Features & How to Use
            local featuresHeight = featuresContent:GetStringHeight() + 12 + 16 + 10 + 12
            local howToUseHeight = howToUseContent:GetStringHeight() + 12 + 16 + 10 + 12
            local row1Height = math.max(featuresHeight, howToUseHeight)
            
            featuresCard:SetHeight(row1Height)
            howToUseCard:SetHeight(row1Height)
            
            -- Row 2: Settings & Profiles & Tips
            settingsCard:ClearAllPoints()
            settingsCard:SetPoint("TOPLEFT", featuresCard, "BOTTOMLEFT", 0, -14)
            
            tipsCard:ClearAllPoints()
            tipsCard:SetPoint("TOPLEFT", howToUseCard, "BOTTOMLEFT", 0, -14)
            
            local settingsHeight = settingsContent:GetStringHeight() + 12 + 16 + 10 + 12
            local tipsHeight = tipsContent:GetStringHeight() + 12 + 16 + 10 + 12
            local row2Height = math.max(settingsHeight, tipsHeight)
            
            settingsCard:SetHeight(row2Height)
            tipsCard:SetHeight(row2Height)
            
            -- Row 3: Recent Enhancements & Discord Card
            updatesCard:ClearAllPoints()
            updatesCard:SetPoint("TOPLEFT", settingsCard, "BOTTOMLEFT", 0, -14)
            
            discordCard:ClearAllPoints()
            discordCard:SetPoint("TOPLEFT", tipsCard, "BOTTOMLEFT", 0, -14)
            
            local updatesHeight = updatesContent:GetStringHeight() + 12 + 16 + 10 + 12
            local thanksHeight = thanksText:GetStringHeight()
            local createdHeight = createdText:GetStringHeight() or 12
            local discordHeight = discordContent:GetStringHeight() + thanksHeight + 99 + createdHeight + 15
            local row3Height = math.max(updatesHeight, discordHeight)
            
            updatesCard:SetHeight(row3Height)
            discordCard:SetHeight(row3Height)

            -- Set scroll child height dynamically
            local totalHeight = 90 + row1Height + 14 + row2Height + 14 + row3Height + 40
            scrollChild:SetHeight(totalHeight)
        end)
    end)
    
    tab:Hide()
    contentArea.About = tab
end

-- ActionHub Tab - Re-routed to Module
function UI:CreateActionHubTab()
    if OxedHub.ActionHub then
        OxedHub.ActionHub:CreateTab(contentArea)
    end
end

function UI:RefreshActionHubTab()
    if OxedHub.ActionHub then
        OxedHub.ActionHub:RefreshTab()
    end
end

-- Experimental Tab - visual graph builder prototype
function UI:CreateExperimentalTab()
    if OxedHub.Experimental then
        OxedHub.Experimental:CreateTab(contentArea)
    end
end

function UI:RefreshExperimentalTab()
    if OxedHub.Experimental then
        OxedHub.Experimental:RefreshTab()
    end
end



-- Show tab
function UI:ShowTab(tabName)

    currentTab = tabName

    if not contentArea or not sidebar then
        return
    end
    
    -- Hide all tabs and reset button states
    for _, name in ipairs({"Dashboard", "Triggers", "Reactions", "Toys", "OxedRing", "ActionHub", "Settings", "About", "Experimental"}) do
        if contentArea[name] then
            contentArea[name]:Hide()
        end
        if sidebar[name .. "Btn"] then
            sidebar[name .. "Btn"]:UnlockHighlight()
        end
    end
    
    -- Show selected tab and lock its button
    if contentArea[tabName] then
        contentArea[tabName]:Show()
    end
    if sidebar[tabName .. "Btn"] then
        sidebar[tabName .. "Btn"]:LockHighlight()
    end
    
    if searchBox then
        searchBox.customSearchHandler = nil
        searchBox:SetText("")
        searchBox:ClearFocus()
        if tabName == "Settings" or tabName == "About" or tabName == "Toys" or tabName == "ActionHub" or tabName == "Experimental" or tabName == "OxedRing" or tabName == "Dashboard" then
            searchBox:GetParent():Hide()
        elseif tabName == "Reactions" then
            local subTab = (contentArea.Reactions and contentArea.Reactions.currentSubTab) or "Sounds"
            if subTab == "Advanced" then
                searchBox:GetParent():Hide()
            else
                searchBox:GetParent():Show()
            end
        else
            searchBox:GetParent():Show()
        end
    end
    
    -- Refresh content
    if tabName == "Dashboard" then
        if OxedHub.Triggers and OxedHub.Triggers.RefreshDashboard then
            OxedHub.Triggers:RefreshDashboard()
        end
    elseif tabName == "Triggers" then
        if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then
            OxedHub.Triggers:RefreshTriggersList()
        end
    elseif tabName == "Reactions" then
        self:ShowSubTab("Sounds")
    elseif tabName == "Categories" then
        local categoriesTab = contentArea.Categories
        UI:ShowSubTab((categoriesTab and categoriesTab.currentSubTab) or "Sounds")
    elseif tabName == "Toys" then
        self:ShowToysSubTab("Mixer")
    elseif tabName == "ActionHub" then
        self:RefreshActionHubTab()
    elseif tabName == "Experimental" then
        self:RefreshExperimentalTab()
    end
    self:ApplyGlobalTextSize()
end

-- Show sub-tab for Toys
function UI:ShowToysSubTab(subTabName)
    local tab = contentArea.Toys
    if not tab then return end
    
    tab.currentSubTab = subTabName

    for _, name in ipairs({"Mixer", "Library", "ToyBoxes"}) do
        local panel = tab.subPanels and tab.subPanels[name]
        if panel then
            panel:Hide()
        end

        local button = tab.subTabs and tab.subTabs[name .. "Btn"]
        if button then
            if name == subTabName then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end
    end

    local panel = tab.subPanels and tab.subPanels[subTabName]
    if not panel then
        return
    end

    panel:Show()
    
    if searchBox then
        searchBox.customSearchHandler = nil
        searchBox:SetText("")
        searchBox:ClearFocus()
        if subTabName == "Mixer" or subTabName == "ToyBoxes" then
            searchBox:GetParent():Show()
        else
            searchBox:GetParent():Hide()
        end
    end

    if subTabName == "Mixer" then
        if OxedHub.Toys and OxedHub.Toys.ShowMixerTab then
            OxedHub.Toys:ShowMixerTab(panel)
        end
    elseif subTabName == "Library" then
        if OxedHub.Toys and OxedHub.Toys.ShowLibraryTab then
            OxedHub.Toys:ShowLibraryTab(panel)
        end
    elseif subTabName == "ToyBoxes" then
        if OxedHub.Toys and OxedHub.Toys.ShowToyBoxesTab then
            OxedHub.Toys:ShowToyBoxesTab(panel)
        end
    end
end

-- Show sub-tab (for Reactions)
function UI:ShowSubTab(subTabName)
    local tab = contentArea.Reactions
    if not tab then return end
    
    tab.currentSubTab = subTabName

    for _, name in ipairs({"Sounds", "Chat", "Animations", "Advanced"}) do
        local panel = tab.subPanels and tab.subPanels[name]
        if panel then
            panel:Hide()
        end

        local button = tab.subTabs and tab.subTabs[name .. "Btn"]
        if button then
            if name == subTabName then
                button:LockHighlight()
            else
                button:UnlockHighlight()
            end
        end
    end

    if searchBox then
        searchBox.customSearchHandler = nil
        searchBox:SetText("")
        searchBox:ClearFocus()
        if subTabName == "Advanced" then
            searchBox:GetParent():Hide()
        else
            searchBox:GetParent():Show()
        end
    end

    local panel = tab.subPanels and tab.subPanels[subTabName]
    if not panel then
        return
    end

    panel:Show()

    -- Show appropriate content in the dedicated panel for this category.
    if subTabName == "Sounds" and OxedHub.Sounds then
        OxedHub.Sounds:ShowUI(panel)
    elseif subTabName == "Chat" and OxedHub.ChatMessages then
        OxedHub.ChatMessages:ShowUI(panel)
    elseif subTabName == "Animations" and OxedHub.Animations then
        OxedHub.Animations:ShowUI(panel)
    elseif subTabName == "Advanced" and OxedHub.Animations then
        OxedHub.Animations:ShowAdvancedUI(panel)
    end
end

-- Create Animations tab
function UI:CreateAnimationsTab()
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(8)
    tab.subPanels = {}
    ApplyToysBackground(tab)
    
    -- Title
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", 15, -15)
    title:SetText("Animations Engine")
    title:Hide()
    
    -- Sub-tabs container
    local subTabs = CreateFrame("Frame", nil, tab)
    subTabs:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -THEMED_FRAME_INSETS.top)
    subTabs:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -THEMED_FRAME_INSETS.right, -THEMED_FRAME_INSETS.top)
    subTabs:SetHeight(30)
    
    -- Sub-tab buttons
    local subTabNames = { "Classic", "Advanced" }
    local xOffset = 0

    for i, name in ipairs(subTabNames) do
        local btn = CreateFrame("Button", nil, subTabs, "UIPanelButtonTemplate")
        btn:SetSize(120, 25)
        btn:SetPoint("TOPLEFT", subTabs, "TOPLEFT", xOffset, 0)
        btn:SetText(name == "Classic" and "Classic Engine" or "Advanced Engine")
        btn:SetScript("OnClick", function()
            UI:ShowAnimationsSubTab(name)
        end)
        btn.subTabName = name
        subTabs[name .. "Btn"] = btn

        local panel = CreateFrame("Frame", nil, tab)
        panel:SetPoint("TOPLEFT", subTabs, "BOTTOMLEFT", 0, -10)
        panel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
        panel:Hide()
        tab.subPanels[name] = panel

        xOffset = xOffset + 125
    end

    tab.subTabs = subTabs
    tab.currentSubTab = nil
    
    tab:Hide()
    contentArea.Animations = tab
end

-- Show sub-tab for Animations
function UI:ShowAnimationsSubTab(subTabName)
    self:ShowTab("Reactions")
    self:ShowSubTab(subTabName == "Advanced" and "Advanced" or "Animations")
end

-- The main window contains secure children (mixer SecureActionButton etc.), so
-- Hide()/Show() on it are protected in combat. In combat we "soft hide" (alpha 0
-- + mouse off) and perform the real Hide() when combat ends.
--
-- We also remove the frame from UISpecialFrames while in combat so that WoW's
-- built-in Escape handler doesn't call the protected Hide() directly.

-- Helper: hide/show all PlayerModel children (SetAlpha doesn't affect 3D models).
local function SetModelFramesShown(frame, shown)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsObjectType("PlayerModel") or child:IsObjectType("DressUpModel") or child:IsObjectType("CinematicModel") or child:IsObjectType("Model") then
            if shown then
                if child._oxedWasShown then
                    child:Show()
                    child._oxedWasShown = nil
                end
            else
                if child:IsShown() then
                    child._oxedWasShown = true
                    child:Hide()
                end
            end
        end
        -- Recurse into children
        SetModelFramesShown(child, shown)
    end
end

-- Forward-declare; created after the combat handler below.
local escapeHelper

local combatHideFrame = CreateFrame("Frame")
combatHideFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatHideFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatHideFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: remove from UISpecialFrames to prevent the
        -- protected Hide() call when pressing Escape.
        if mainFrame then
            local frameName = mainFrame:GetName()
            for i = #UISpecialFrames, 1, -1 do
                if UISpecialFrames[i] == frameName then
                    tremove(UISpecialFrames, i)
                    break
                end
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Leaving combat: re-add to UISpecialFrames.
        if mainFrame then
            local frameName = mainFrame:GetName()
            local found = false
            for _, name in ipairs(UISpecialFrames) do
                if name == frameName then found = true; break end
            end
            if not found then
                tinsert(UISpecialFrames, frameName)
            end
        end
        -- Perform the deferred real Hide() if it was soft-hidden.
        if UI._pendingCombatHide and mainFrame then
            UI._pendingCombatHide = nil
            mainFrame:Hide()
            mainFrame:SetAlpha(1)
            mainFrame:EnableMouse(true)
            SetModelFramesShown(mainFrame, true)
        end
    end
end)

-- Separate non-secure frame to intercept Escape during combat.
-- It stays active at all times but only acts when the main frame is visible
-- in combat. We never call SetPropagateKeyboardInput during combat to avoid
-- taint; propagation stays true so all keys pass through normally.
escapeHelper = CreateFrame("Frame", "OxedHubEscapeHelper", UIParent)
escapeHelper:EnableKeyboard(true)
escapeHelper:SetPropagateKeyboardInput(true)
escapeHelper:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" and InCombatLockdown() and mainFrame
       and mainFrame:IsShown() and not UI._pendingCombatHide then
        UI:HideMainWindow()
    end
    -- Propagation stays true (set at creation), so all keys pass through.
end)

-- Show main window
function UI:ShowMainWindow()
    if mainFrame then
        self._pendingCombatHide = nil
        mainFrame:SetAlpha(1)
        mainFrame:EnableMouse(true)
        SetModelFramesShown(mainFrame, true)
        if InCombatLockdown() then
            -- Show() is equally protected; only possible if the frame is already
            -- shown-but-soft-hidden. If it's truly hidden, we can't open in combat.
            if not mainFrame:IsShown() then
                print("|cffff0000[OxedHub]|r Cannot open the window during combat.")
                return
            end
        else
            mainFrame:Show()
        end
        OxedHub.db.profile.settings.mainWindowVisible = true
    end
end

-- Hide main window
function UI:HideMainWindow()
    if mainFrame then
        if InCombatLockdown() then
            -- Protected in combat: hide visually now, really hide after combat.
            mainFrame:SetAlpha(0)
            mainFrame:EnableMouse(false)
            SetModelFramesShown(mainFrame, false)
            self._pendingCombatHide = true
        else
            mainFrame:Hide()
        end
        OxedHub.db.profile.settings.mainWindowVisible = false
    end
end

-- Toggle main window
function UI:ToggleMainWindow()
    if mainFrame and mainFrame:IsShown() then
        self:HideMainWindow()
    else
        self:ShowMainWindow()
    end
end

-- Flash border for search results
function UI:FlashBorder(frame)
    if not frame then return end
    
    local originalBorder = { 1, 1, 1, 1 }
    if frame.GetBackdropBorderColor then
        originalBorder = { frame:GetBackdropBorderColor() }
    end
    
    frame:SetBackdropBorderColor(1, 1, 0, 1)
    
    C_Timer.After(0.3, function()
        frame:SetBackdropBorderColor(1, 0, 0, 1)
    end)
    C_Timer.After(0.6, function()
        frame:SetBackdropBorderColor(1, 1, 0, 1)
    end)
    C_Timer.After(0.9, function()
        if originalBorder then
            frame:SetBackdropBorderColor(unpack(originalBorder))
        else
            frame:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end)
end

-- Get main frame
function UI:GetMainFrame()
    return mainFrame
end

-- Get content area
function UI:GetContentArea()
    return contentArea
end

-- Get current tab
function UI:GetCurrentTab()
    return currentTab
end

function UI:StyleScrollFrame(scrollFrame)
    StyleScrollFrame(scrollFrame)
end

function UI:ApplyGoldButtonStyle(button)
    ApplyGoldButtonStyle(button)
end

function UI:ApplyRedButtonStyle(button)
    ApplyRedButtonStyle(button)
end

-- ------------------------------------------------------------------------
-- Export / Import
-- ------------------------------------------------------------------------
local AceSerializer = LibStub("AceSerializer-3.0")
local EXPORT_EDITBOX_MAX_CHARS = 500000
local EXPORT_MAX_CHARS = 500000
local EXPORT_CHUNK_PREFIX = "OHUBCHUNK1"
local EXPORT_CHUNK_PAYLOAD_CHARS = EXPORT_MAX_CHARS
local EXPORT_COMPRESSED_PREFIX = "OHUBX1:"

-- Profile keys that must NOT travel with an export. Everything else in a profile
-- is exported generically, so new features (OxedRing nodes, reactions, keybinds,
-- etc.) are included automatically instead of being silently dropped by a
-- hand-maintained allow-list that drifts out of date.
-- Profile keys that make up the OxedRing configuration.
local OXEDRING_KEYS = {
    "oxedRingNodes", "oxedRingBackupNodes", "oxedRingRadius", "oxedRingAutoRadius", "oxedRingStyle",
    "oxedRingBinding", "oxedRingShowNodeTitles", "oxedRingNodeTitleSize",
    "oxedRingGlobalNodeSize", "oxedRingVisibleTabs",
}

local EXPORT_SKIP_KEYS = {
    toyCollectionCache = true, -- character-specific toy-box scan cache; regenerated locally
    testRing = true,           -- legacy pre-migration remnant
}

-- Reserved payload-envelope keys (added by the exporter, not part of profile data).
local EXPORT_ENVELOPE_KEYS = {
    version = true,
    profileName = true,
}

local function BuildProfileExportPayload(profileName, db)
    local payload = {
        version = 1,
        profileName = profileName,
        -- Author stamp so plain profile exports are credited too, not just the
        -- v3 scoped envelopes. Filled by UI.CaptureAuthorMeta, which is declared
        -- further down this file. Nickname, character-realm, class and region
        -- are always captured; the note comes from the Export/Import page.
        _author = UI.CaptureAuthorMeta and UI.CaptureAuthorMeta(UI:GetExportNote()),
    }
    for key, value in pairs(db) do
        if not EXPORT_SKIP_KEYS[key] and not EXPORT_ENVELOPE_KEYS[key] then
            payload[key] = value
        end
    end

    -- A shared (non-unique) ring is stored in globalSettings, not on the
    -- profile, so copying profile keys alone exports a profile with no ring at
    -- all.  Pull the ring the player is actually using -- but only for the
    -- active profile, since that is the only one GetRingDB can speak for.
    local isActive = OxedHubDB and profileName == OxedHubDB.activeProfile
    if isActive and not (payload.oxedRingNodes and next(payload.oxedRingNodes)) then
        local ringDB = OxedHub.GetRingDB and OxedHub.GetRingDB()
        if type(ringDB) == "table" then
            for _, k in ipairs(OXEDRING_KEYS) do
                -- The profile usually holds an EMPTY table here rather than nil,
                -- so a plain nil-check would never overwrite it.  Treat empty
                -- tables as absent too.
                local existing = payload[k]
                local isEmpty = existing == nil
                    or (type(existing) == "table" and next(existing) == nil)
                if isEmpty and ringDB[k] ~= nil then
                    payload[k] = ringDB[k]
                end
            end
        end
    end

    return payload
end

function UI:SerializeProfile(activeOnly)
    local activeProfile = OxedHubDB.activeProfile

    if activeOnly then
        local activeDB = activeProfile and OxedHubDB.profiles and OxedHubDB.profiles[activeProfile]
        if not activeDB then
            return nil, "Active profile not found."
        end

        return AceSerializer:Serialize(BuildProfileExportPayload(activeProfile, activeDB))
    end

    local export = {
        version = 2, -- Increment version for multi-profile support
        profiles = {},
        activeProfile = activeProfile
    }
    
    for name, db in pairs(OxedHubDB.profiles) do
        export.profiles[name] = BuildProfileExportPayload(name, db)
    end
    
    return AceSerializer:Serialize(export)
end

function UI:SerializeSelectedProfiles(profileNames)
    if type(profileNames) ~= "table" or #profileNames == 0 then
        return nil, "No profiles selected."
    end

    local export = {
        version = 2,
        profiles = {},
        activeProfile = OxedHubDB.activeProfile
    }

    for _, name in ipairs(profileNames) do
        local db = OxedHubDB.profiles and OxedHubDB.profiles[name]
        if db then
            export.profiles[name] = BuildProfileExportPayload(name, db)
        end
    end

    if not next(export.profiles) then
        return nil, "Selected profiles were not found."
    end

    return AceSerializer:Serialize(export)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- Scoped export/import (format v3). A typed envelope lets us export/import
-- specific slices (triggers, OxedRing, toy mixes, hubs) and carry author info
-- for attribution. v1/v2 profile strings still import via UI:ApplyImport below.
-- ═══════════════════════════════════════════════════════════════════════════

-- Snapshot of who/where produced an export, embedded in every v3 envelope.
-- Optional display name attached to exports, so shared content can be credited
-- to a handle rather than just character-realm. Stored globally (not per-profile)
-- because it describes the player, not the profile.
function UI:GetExportNickname()
    local gs = OxedHubDB and OxedHubDB.globalSettings
    local nick = gs and gs.exportNickname
    if type(nick) == "string" and nick:gsub("%s", "") ~= "" then
        return nick
    end
    return nil
end

function UI:SetExportNickname(nick)
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    nick = type(nick) == "string" and nick:gsub("^%s*(.-)%s*$", "%1") or ""
    OxedHubDB.globalSettings.exportNickname = (nick ~= "") and nick or nil
end

-- Default note attached to exports made from the Export/Import page.
function UI:GetExportNote()
    local gs = OxedHubDB and OxedHubDB.globalSettings
    local note = gs and gs.exportNote
    if type(note) == "string" and note:gsub("%s", "") ~= "" then
        return note
    end
    return nil
end

function UI:SetExportNote(note)
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    note = type(note) == "string" and note:gsub("^%s*(.-)%s*$", "%1") or ""
    OxedHubDB.globalSettings.exportNote = (note ~= "") and note or nil
end

local function CaptureAuthorMeta(note)
    local name = UnitName("player")
    local realm = GetRealmName()
    local _, classToken = UnitClass("player")
    local faction = UnitFactionGroup("player")
    local region
    if GetCurrentRegionName then
        local ok, r = pcall(GetCurrentRegionName)
        if ok then region = r end
    end
    note = note and note:gsub("^%s*(.-)%s*$", "%1") or ""
    return {
        character = name,
        realm = realm,
        region = region,
        class = classToken,
        faction = faction,
        nickname = UI:GetExportNickname(),
        date = time(),
        dateStr = date("%Y-%m-%d"),
        addonVersion = (OxedHub.CONFIG and OxedHub.CONFIG.VERSION) or "?",
        note = (note ~= "") and note or nil,
    }
end

-- Exposed so code declared earlier in the file (BuildProfileExportPayload) can
-- reach it at call time.
UI.CaptureAuthorMeta = CaptureAuthorMeta

-- Display name for a recorded author: nickname when they set one, otherwise
-- character-realm. Used by the credits list and import preview.
function UI:FormatAuthorName(author, colorize)
    if type(author) ~= "table" then return "unknown" end
    local base = author.nickname
    if not base then
        base = author.character and (author.character .. "-" .. tostring(author.realm or "?")) or "unknown"
    elseif author.character then
        base = base .. " |cff888888(" .. author.character .. "-" .. tostring(author.realm or "?") .. ")|r"
    end
    if colorize and author.class then
        local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
        local c = colors and colors[author.class]
        if c then
            local hex = c.GenerateHexColor and c:GenerateHexColor()
                or (c.colorStr and "ff" .. c.colorStr:sub(-6))
                or string.format("ff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
            return "|c" .. hex .. base .. "|r"
        end
    end
    return base
end

-- What a profile actually contains, for the Details panel.
function UI:GetProfileStats(db)
    local stats = {
        triggers = 0, triggersEnabled = 0,
        ringNodes = 0, hubs = 0, toyMixes = 0,
        customSounds = 0, animations = 0, chatTemplates = 0,
        toyCategories = 0,
    }
    if type(db) ~= "table" then return stats end

    for _, trig in pairs(db.triggers or {}) do
        stats.triggers = stats.triggers + 1
        if trig.enabled ~= false then
            stats.triggersEnabled = stats.triggersEnabled + 1
        end
    end
    for _, node in pairs(db.oxedRingNodes or {}) do
        if type(node) == "table" and node.type then
            stats.ringNodes = stats.ringNodes + 1
        end
    end
    stats.hubs = #((db.actionHub and db.actionHub.hubs) or {})
    for _ in pairs(db.toyMixes or {}) do stats.toyMixes = stats.toyMixes + 1 end
    for _ in pairs(db.customSounds or {}) do stats.customSounds = stats.customSounds + 1 end
    for _ in pairs(db.animations or {}) do stats.animations = stats.animations + 1 end
    for _ in pairs(db.chatTemplates or {}) do stats.chatTemplates = stats.chatTemplates + 1 end
    stats.toyCategories = #(db.toyCategories or {})

    return stats
end

-- Collapse importSources into one entry per contributor, listing everything
-- they contributed. Newest contribution first.
function UI:GetProfileCredits(db)
    if type(db) ~= "table" or type(db.importSources) ~= "table" then return {} end

    local byAuthor, order = {}, {}
    for _, src in ipairs(db.importSources) do
        local a = src.author or {}
        local key = (a.nickname or "?") .. "|" .. tostring(a.character) .. "-" .. tostring(a.realm)
        local entry = byAuthor[key]
        if not entry then
            entry = { author = a, scopes = {}, count = 0, lastDate = 0, notes = {}, noteSeen = {} }
            byAuthor[key] = entry
            table.insert(order, entry)
        end
        entry.count = entry.count + 1
        entry.scopes[src.scope or "?"] = (entry.scopes[src.scope or "?"] or 0) + 1
        local when = src.date or a.date or 0
        if when > entry.lastDate then entry.lastDate = when end
        if a.note and not entry.noteSeen[a.note] then
            entry.noteSeen[a.note] = true
            table.insert(entry.notes, a.note)
        end
    end

    table.sort(order, function(x, y) return (x.lastDate or 0) > (y.lastDate or 0) end)
    return order
end

-- All scopes the export dropdown offers. `needs` names the extra target the UI
-- must collect (a profile / a trigger set / a hub); nil = no target needed.
UI.EXPORT_SCOPES = {
    { key = "profile_current", scope = "profile", label = "Current Profile", desc = "Exports your active profile with all triggers, action hubs, rings, and toy mixes.", needs = nil },
    { key = "profile_specific", scope = "profiles", label = "Specific Profile", desc = "Choose any saved profile from your library to export.", needs = "profile" },
    { key = "triggers_all", scope = "triggers", label = "All Triggers", desc = "Exports all triggers belonging to the active profile.", needs = nil },
    { key = "triggers_selected", scope = "triggers", label = "Selected Triggers", desc = "Pick individual triggers from your active profile with checkboxes.", needs = "triggers" },
    { key = "oxedring", scope = "oxedring", label = "OxedRing", desc = "Exports OxedRing radial menu assignments and node configurations.", needs = nil },
    { key = "toymixes", scope = "toymixes", label = "Toy Mixer", desc = "Exports toy macro mixes and animation assignments.", needs = nil },
    { key = "hubs_all", scope = "hubs", label = "All Hubs", desc = "Exports all Action Hub quadrants and configured widgets.", needs = nil },
    { key = "hub_specific", scope = "hubs", label = "Specific Hub", desc = "Exports a single Action Hub widget by number.", needs = "hub" },
}

-- Human-readable summary of what an envelope contains (for the import preview).
function UI:DescribeEnvelope(env)
    if type(env) ~= "table" then return "Unknown data" end
    local scope = env.scope
    local p = env.payload or {}
    if scope == "profiles" then
        local n = 0
        for _ in pairs(p.profiles or {}) do n = n + 1 end
        return string.format("%d profile(s)", n)
    elseif scope == "profile" then
        return "1 profile (" .. tostring(p.profileName or "?") .. ")"
    elseif scope == "triggers" then
        local n = 0
        for _ in pairs(p.triggers or {}) do n = n + 1 end
        return string.format("%d trigger(s)", n)
    elseif scope == "oxedring" then
        -- Count with pairs rather than '#': the node table is not guaranteed to
        -- be a gapless array, and '#' silently reports 0 on a hashed table.
        local n = 0
        for _ in pairs(p.oxedRingNodes or {}) do n = n + 1 end
        return string.format("OxedRing config (%d nodes)", n)
    elseif scope == "toymixes" then
        local n = 0
        for _ in pairs(p.toyMixes or {}) do n = n + 1 end
        return string.format("%d toy mix(es)", n)
    elseif scope == "hubs" then
        local hubs = p.hubs or {}
        if #hubs == 1 and type(hubs[1]) == "table" then
            return "ActionHub: |cff88ff88" .. tostring(hubs[1].name or "Hub") .. "|r"
        end
        return string.format("%d ActionHub(s)", #hubs)
    end
    return "Unknown scope"
end

-- Everything the confirmation popup needs to describe an incoming import:
-- what it contains, who made it, and where it will land.
function UI:BuildImportSummary(data)
    if type(data) ~= "table" then
        return "Unknown import data.", false
    end

    -- One "Triggers 12  •  Ring nodes 8  •  ..." line describing a profile
    -- payload. Payloads carry the same keys as a live profile db, so the
    -- Details-panel stats function works on them directly.
    local function ProfileContents(payloadDB, indent)
        local s = self:GetProfileStats(payloadDB)
        local bits = {}
        local function Add(label, n)
            if n and n > 0 then table.insert(bits, label .. " |cffffffff" .. n .. "|r") end
        end
        Add("Triggers", s.triggers)
        Add("Ring nodes", s.ringNodes)
        Add("Hubs", s.hubs)
        Add("Toy mixes", s.toyMixes)
        Add("Sounds", s.customSounds)
        Add("Animations", s.animations)
        Add("Chat", s.chatTemplates)
        if #bits == 0 then return (indent or "") .. "|cff888888(empty)|r" end
        return (indent or "") .. "|cffaaaaaa" .. table.concat(bits, "  •  ") .. "|r"
    end

    local function DescribeProfileSet(profiles)
        local out, count = {}, 0
        for name, pdb in pairs(profiles or {}) do
            count = count + 1
            if count <= 5 then
                table.insert(out, "|cff88ff88" .. tostring(name) .. "|r")
                table.insert(out, ProfileContents(pdb, "   "))
            end
        end
        if count > 5 then
            table.insert(out, "|cff888888…and " .. (count - 5) .. " more|r")
        end
        return out, count
    end

    local lines = {}
    local isPartial = false

    if data.formatVersion == 3 and data.scope then
        local scope = data.scope
        local p = data.payload or {}
        isPartial = not (scope == "profile" or scope == "profiles")

        if scope == "profile" then
            table.insert(lines, "|cffffd100Profile:|r |cff88ff88"
                .. tostring(p.profileName or "?") .. "|r")
            table.insert(lines, ProfileContents(p, "   "))
        elseif scope == "profiles" then
            local rows, count = DescribeProfileSet(p.profiles)
            table.insert(lines, string.format("|cffffd100Contains:|r %d profile(s)", count))
            for _, row in ipairs(rows) do table.insert(lines, row) end
        else
            table.insert(lines, "|cffffd100Contains:|r " .. self:DescribeEnvelope(data))
        end

        local author = data.author
        if author then
            table.insert(lines, "|cffffd100From:|r " .. self:FormatAuthorName(author))
            local bits = {}
            if author.class then table.insert(bits, author.class) end
            if author.region then table.insert(bits, author.region) end
            if author.dateStr then table.insert(bits, author.dateStr) end
            if author.addonVersion then table.insert(bits, "v" .. author.addonVersion) end
            if #bits > 0 then
                table.insert(lines, "|cff888888" .. table.concat(bits, ", ") .. "|r")
            end
            if author.note then
                table.insert(lines, "|cffaaaaaa\"" .. author.note .. "\"|r")
            end
        end
    else
        -- v1 (single profile) / v2 (multi-profile) legacy payloads.
        if data.profiles then
            local rows, count = DescribeProfileSet(data.profiles)
            table.insert(lines, string.format("|cffffd100Contains:|r %d profile(s)", count))
            for _, row in ipairs(rows) do table.insert(lines, row) end
        else
            table.insert(lines, "|cffffd100Profile:|r |cff88ff88"
                .. tostring(data.profileName or "?") .. "|r")
            table.insert(lines, ProfileContents(data, "   "))
        end
    end

    if isPartial then
        local target = UI.importTargetProfile or (OxedHubDB and OxedHubDB.activeProfile) or "?"
        table.insert(lines, "|cffffd100Imports into:|r " .. target)
        table.insert(lines, "|cffff8800Existing items with the same name or ID will be overwritten.|r")
    else
        table.insert(lines, "|cffffd100Imports into:|r new profile(s)")
    end

    return table.concat(lines, "\n"), isPartial
end

-- Structured breakdown of an import, used by the confirmation dialog's table.
-- Returns: headerText, rows { {label, value} }, authorLines, isPartial, scopeText
-- Resolve a stored action value into something a human can read.  Imported
-- data may reference sounds/animations that only exist in the sender's profile,
-- so fall back to the raw id rather than showing nothing.
function UI:DescribeActionValue(kind, value, payload)
    if value == nil or value == "" or value == "None" then return nil end

    if kind == "sound" then
        -- Custom sounds bundled with the import take priority, then our own.
        local bundled = payload and payload.customSounds and payload.customSounds[value]
        if bundled and bundled.name then return bundled.name end
        local mine = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds
            and OxedHub.db.profile.customSounds[value]
        if mine and mine.name then return mine.name end
    end

    return tostring(value)
end

-- Resolve a toy id into an inline-icon label, an ownership note, and the id so
-- the row can show the real game tooltip on hover.
function UI:DescribeToySlot(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end

    local toyName, toyIcon
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, _, name, icon = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok then toyName, toyIcon = name, icon end
    end

    -- Toy data is not always cached; fall back to item info, then to the id.
    if not toyName and C_Item and C_Item.GetItemInfo then
        local ok, name, _, _, _, _, _, _, _, icon = pcall(C_Item.GetItemInfo, itemID)
        if ok then toyName = toyName or name; toyIcon = toyIcon or icon end
    end

    -- Still nothing means the client has not cached this item yet.  Ask for it
    -- and flag the dialog to redraw once, so names fill in instead of showing
    -- raw ids forever.
    if not toyName then
        UI._importPendingItemLoad = true
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end
    end

    local label = "   "
    if toyIcon then label = label .. "|T" .. toyIcon .. ":16:16:0:0:64:64:5:59:5:59|t " end
    label = label .. (toyName or ("Toy #" .. itemID))

    local owned
    if PlayerHasToy then
        local ok, has = pcall(PlayerHasToy, itemID)
        if ok then owned = has end
    end

    local note
    if owned == true then
        note = "|cff88ff88you have it|r"
    elseif owned == false then
        note = "|cffff6666not collected|r"
    else
        note = "|cff888888unknown|r"
    end

    return label, note, itemID
end

-- One readable line for an ActionHub / ring slot: icon, name, and a note.
-- Returns label, note, tooltipItemID (nil when there is nothing to hover).
function UI:DescribeHubSlot(slot)
    if type(slot) ~= "table" or not slot.type then return nil end

    local kind = slot.type
    local id = tonumber(slot.id)

    -- Toys get the full treatment: real name plus whether the viewer owns it.
    if kind == "toy" and id then
        return self:DescribeToySlot(id)
    end

    local name, icon = slot.label, slot.icon
    local note = kind

    if kind == "spell" and id then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
        if info then
            name = info.name or name
            icon = icon or info.iconID
        end
    elseif kind == "item" and id then
        if not name and C_Item and C_Item.GetItemInfo then
            local ok, itemName, _, _, _, _, _, _, _, itemIcon = pcall(C_Item.GetItemInfo, id)
            if ok then
                name = name or itemName
                icon = icon or itemIcon
            end
            if not name then
                UI._importPendingItemLoad = true
                if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            end
        end
    elseif kind == "macro" then
        -- The macro body travels inside the slot, so it works on any account.
        note = slot.body and "macro |cff88ff88(included)|r" or "macro |cffff6666(empty)|r"
    end

    local label = "   "
    if icon then label = label .. "|T" .. tostring(icon) .. ":16:16:0:0:64:64:5:59:5:59|t " end
    label = label .. tostring(name or (kind .. " #" .. tostring(slot.id or "?")))

    -- Only items and spells have a tooltip we can show by id.
    local tooltipID = (kind == "item") and id or nil
    return label, note, tooltipID
end

-- One readable line for a single OxedRing node.
-- Ring nodes reference other things by id: a toy mix by name, a trigger by id.
-- Resolve those against the incoming payload so the preview shows real names.
function UI:DescribeRingNode(node, payload)
    if type(node) ~= "table" or not node.type then return nil end

    local kind = node.type
    local name, icon, note = node.label, node.icon, kind

    if kind == "toy" then
        if node.assignmentMode == "direct" then
            return self:DescribeToySlot(node.id)
        end
        -- Otherwise the node points at a toy mix by name.
        name = name or tostring(node.id)
        local bundled = payload and payload.toyMixes and payload.toyMixes[node.id]
        note = bundled and "toy mix |cff88ff88(included)|r" or "toy mix |cffff8800(not included)|r"

    elseif kind == "trigger" then
        local trig = payload and payload.triggers and payload.triggers[node.id]
        name = (trig and trig.name) or name or tostring(node.id)
        note = trig and "trigger |cff88ff88(included)|r" or "trigger |cffff8800(not included)|r"

    elseif kind == "marker" or kind == "targetmarker" then
        local markerID = tonumber(node.id)
        if markerID and markerID > 0 then
            icon = icon or ("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. markerID)
            name = name or ("Marker " .. markerID)
        else
            name = name or "Clear marker"
        end

    elseif kind == "emote" then
        name = name or tostring(node.id)
    end

    local label = "   "
    if icon then label = label .. "|T" .. tostring(icon) .. ":16:16:0:0:64:64:5:59:5:59|t " end
    label = label .. tostring(name or kind)
    return label, note, nil
end

-- Detail rows for a ring payload, shared by the ring-only import preview and
-- the OxedRing section of a whole-profile import.
function UI:GetRingDetailRows(p)
    local out = {}
    local nodes = {}
    for _, node in pairs(p.oxedRingNodes or {}) do
        if type(node) == "table" then table.insert(nodes, node) end
    end

    local filled, byType = 0, {}
    for _, node in ipairs(nodes) do
        if node.type then
            filled = filled + 1
            byType[node.type] = (byType[node.type] or 0) + 1
        end
    end

    table.insert(out, { "   Slices", #nodes })
    table.insert(out, { "   Assigned", string.format("%d |cff888888of %d|r", filled, #nodes) })
    for kind, count in pairs(byType) do
        table.insert(out, { "      |cff888888" .. kind .. "|r", count })
    end

    for _, node in ipairs(nodes) do
        local nLabel, nNote, nID = self:DescribeRingNode(node, p)
        if nLabel then
            table.insert(out, { "   " .. nLabel, nNote, nID })
        end
    end

    table.insert(out, { "   Radius", p.oxedRingRadius or "default" })
    table.insert(out, { "   Keybind", p.oxedRingBinding or "none" })
    if p.oxedRingStyle then
        table.insert(out, { "   Style", tostring(p.oxedRingStyle) })
    end

    return out, #nodes
end

-- Detail rows for one ActionHub, shared by the hub-only import preview and the
-- Action Hubs section of a whole-profile import.
function UI:GetHubDetailRows(hub, index)
    local out = {}

    local function CollectSide(source)
        local list = {}
        for _, s in pairs(source or {}) do
            if type(s) == "table" and s.type then table.insert(list, s) end
        end
        return list
    end

    local mainSlots = CollectSide(hub.slots)
    local dualSlots = CollectSide(hub.secondarySlots)

    local summary = #mainSlots .. " main"
    if hub.dualSideEnabled or #dualSlots > 0 then
        summary = summary .. ", " .. #dualSlots .. " dual"
    end
    table.insert(out, { "   |cffffd100" .. tostring(hub.name or ("Hub " .. tostring(index))) .. "|r", summary })

    local function AddSide(title, list)
        if #list == 0 then return end
        table.insert(out, { "    |cffaaaaaa" .. title .. "|r", "" })
        for _, slot in ipairs(list) do
            local sLabel, sNote, sID = self:DescribeHubSlot(slot)
            if sLabel then
                table.insert(out, { "   " .. sLabel, sNote, sID })
            end
        end
    end

    AddSide("Main side", mainSlots)
    AddSide("Dual side", dualSlots)

    if hub.style then
        table.insert(out, { "    |cff888888Style|r", tostring(hub.style) })
    end

    return out
end

-- Compact one-line summary of a trigger's actions, for the whole-profile view
-- where a full breakdown per trigger would run to hundreds of rows.
function UI:CompactActionSummary(actions)
    if type(actions) ~= "table" then return nil end
    local bits = {}
    if actions.sound or actions.successSound or actions.failSound then table.insert(bits, "sound") end
    if actions.animation or actions.successAnimation or actions.failAnimation
        or actions.cooldownAnimation then table.insert(bits, "animation") end
    if actions.emote then table.insert(bits, "emote") end
    if actions.chatMessage then table.insert(bits, "chat") end
    if actions.toy then table.insert(bits, "toy") end
    if #bits == 0 then return nil end
    return table.concat(bits, ", ")
end

-- Whole profiles can hold hundreds of items, so each listed section is capped
-- and the remainder is summarised on one line.
local PROFILE_SECTION_LIMIT = 25

-- Append "Header (n)" plus up to PROFILE_SECTION_LIMIT entries built by makeRow.
-- The header is tagged as a collapsible section and every entry is tagged as
-- belonging to it, so the dialog can fold sections away.
function UI:AppendProfileSection(rows, title, items, makeRow)
    local count = #items
    if count == 0 then return end

    table.insert(rows, { " ", "" })

    local header = { title .. " (" .. count .. ")", "" }
    header.sectionHeader = title
    table.insert(rows, header)

    for i = 1, math.min(count, PROFILE_SECTION_LIMIT) do
        for _, row in ipairs(makeRow(items[i]) or {}) do
            row.section = title
            table.insert(rows, row)
        end
    end

    if count > PROFILE_SECTION_LIMIT then
        local more = { "   |cff888888... and " .. (count - PROFILE_SECTION_LIMIT) .. " more|r", "" }
        more.section = title
        table.insert(rows, more)
    end
end

-- The detailed breakdown shown under the stat table for a full profile import.
function UI:AppendProfileDetails(rows, p)
    if type(p) ~= "table" then return end

    -- Triggers: name, event, and a compact list of what each one does.
    local triggers = {}
    for id, trig in pairs(p.triggers or {}) do
        if type(trig) == "table" then
            table.insert(triggers, { id = id, trig = trig })
        end
    end
    table.sort(triggers, function(a, b)
        return tostring(a.trig.name or a.id) < tostring(b.trig.name or b.id)
    end)

    self:AppendProfileSection(rows, "Triggers", triggers, function(entry)
        local trig = entry.trig
        local out = { { "   " .. tostring(trig.name or entry.id),
            (trig.event or "?") .. (trig.enabled == false and " |cff888888(off)|r" or "") } }
        local summary = self:CompactActionSummary(trig.actions)
        if summary then
            table.insert(out, { "      |cff888888" .. summary .. "|r", "" })
        end
        return out
    end)

    -- Toy mixes: name and how many toys each pulls in.
    local mixes = {}
    for name, mix in pairs(p.toyMixes or {}) do
        table.insert(mixes, { name = name, mix = mix })
    end
    table.sort(mixes, function(a, b) return tostring(a.name) < tostring(b.name) end)

    self:AppendProfileSection(rows, "Toy mixes", mixes, function(entry)
        local toyIDs = {}
        for _, s in ipairs(type(entry.mix) == "table" and entry.mix.slots or {}) do
            if type(s) == "table" and s.type == "toy" and s.id then
                table.insert(toyIDs, s.id)
            end
        end

        local out = { { "   " .. tostring(entry.name),
            #toyIDs .. " toy" .. (#toyIDs == 1 and "" or "s") } }

        -- Name the toys here too, so a profile import shows the same detail as
        -- sharing a single mix does.
        for _, toyID in ipairs(toyIDs) do
            local tLabel, tNote, tID = self:DescribeToySlot(toyID)
            if tLabel then
                table.insert(out, { "   " .. tLabel, tNote, tID })
            end
        end
        return out
    end)

    -- Action hubs: both sides, same counting the scoped view uses.
    local hubs = {}
    for _, hub in ipairs((p.actionHub and p.actionHub.hubs) or {}) do
        if type(hub) == "table" then table.insert(hubs, hub) end
    end

    -- Same detail the hub-only share shows.
    self:AppendProfileSection(rows, "Action Hubs", hubs, function(hub)
        return self:GetHubDetailRows(hub)
    end)

    -- Ring: only worth a section when it actually has slices.
    local ringRows, ringTotal = self:GetRingDetailRows(p)
    if ringTotal > 0 then
        table.insert(rows, { " ", "" })

        local header = { "OxedRing (" .. ringTotal .. ")", "" }
        header.sectionHeader = "OxedRing"
        table.insert(rows, header)

        -- Same detail the ring-only share shows.
        for _, row in ipairs(ringRows) do
            row.section = "OxedRing"
            table.insert(rows, row)
        end
    end
end

-- Every action slot a trigger can carry, in the order we want to show them.
local IMPORT_ACTION_FIELDS = {
    { key = "sound",             kind = "sound", label = "Sound" },
    { key = "successSound",      kind = "sound", label = "Sound (success)" },
    { key = "failSound",         kind = "sound", label = "Sound (fail)" },
    { key = "animation",         kind = "anim",  label = "Animation" },
    { key = "successAnimation",  kind = "anim",  label = "Animation (success)" },
    { key = "failAnimation",     kind = "anim",  label = "Animation (fail)" },
    { key = "cooldownAnimation", kind = "anim",  label = "Animation (cooldown)" },
    { key = "emote",             kind = "emote", label = "Emote" },
    { key = "chatMessage",       kind = "chat",  label = "Chat message" },
    { key = "toy",               kind = "toy",   label = "Toy" },
}

-- Detail lines for one trigger: what it will actually do once imported.
function UI:GetTriggerActionRows(trig, payload)
    local out = {}
    local actions = trig and trig.actions or {}

    for _, field in ipairs(IMPORT_ACTION_FIELDS) do
        local shown = self:DescribeActionValue(field.kind, actions[field.key], payload)
        if shown then
            table.insert(out, { "   |cff888888" .. field.label .. ":|r", shown })
        end
    end

    -- Call out the actions that act on the player's behalf, since an imported
    -- trigger can talk in chat or write macros without being asked twice.
    local warnings = {}
    if actions.chatMessage then table.insert(warnings, "sends chat") end
    if actions.emote then table.insert(warnings, "emotes") end
    if actions.toy then table.insert(warnings, "uses toy") end
    if #warnings > 0 then
        table.insert(out, { "   |cffff8800! Will act for you|r",
            "|cffff8800" .. table.concat(warnings, ", ") .. "|r" })
    end

    if #out == 0 then
        table.insert(out, { "   |cff888888No actions|r", "" })
    end

    return out
end

function UI:GetImportDetails(data)
    local rows, authorLines = {}, {}
    local header, scopeText = "Unknown data", nil
    local isPartial = false

    local function StatRows(payloadDB)
        local s = self:GetProfileStats(payloadDB)
        local out = {
            { "Triggers", s.triggers > 0
                and string.format("%d |cff888888(%d enabled)|r", s.triggers, s.triggersEnabled)
                or "0" },
            { "OxedRing nodes", s.ringNodes },
            { "Action Hubs", s.hubs },
            { "Toy mixes", s.toyMixes },
            { "Toy tabs", s.toyCategories },
            { "Custom sounds", s.customSounds },
            { "Animations", s.animations },
            { "Chat templates", s.chatTemplates },
        }

        -- Count the triggers that will act on the player's behalf.  A profile
        -- can hold dozens of triggers, so summarise instead of listing them.
        local chats, emotes, toys = 0, 0, 0
        for _, trig in pairs(payloadDB and payloadDB.triggers or {}) do
            local a = type(trig) == "table" and trig.actions or nil
            if type(a) == "table" then
                if a.chatMessage then chats = chats + 1 end
                if a.emote then emotes = emotes + 1 end
                if a.toy then toys = toys + 1 end
            end
        end

        if chats > 0 or emotes > 0 or toys > 0 then
            local bits = {}
            if chats > 0 then table.insert(bits, chats .. " send chat") end
            if emotes > 0 then table.insert(bits, emotes .. " emote") end
            if toys > 0 then table.insert(bits, toys .. " use toys") end
            table.insert(out, { "|cffff8800! Acts for you|r",
                "|cffff8800" .. table.concat(bits, ", ") .. "|r" })
        end

        return out
    end

    if type(data) ~= "table" then
        return header, rows, authorLines, false, nil
    end

    if data.formatVersion == 3 and data.scope then
        local scope, p = data.scope, data.payload or {}
        isPartial = not (scope == "profile" or scope == "profiles")

        if scope == "profile" then
            header = "Profile: |cff88ff88" .. tostring(p.profileName or "?") .. "|r"
            rows = StatRows(p)
            self:AppendProfileDetails(rows, p)
        elseif scope == "profiles" then
            local count = 0
            for name, pdb in pairs(p.profiles or {}) do
                count = count + 1
                local s = self:GetProfileStats(pdb)
                table.insert(rows, { "|cff88ff88" .. tostring(name) .. "|r",
                    string.format("%d triggers, %d ring, %d hubs, %d mixes",
                        s.triggers, s.ringNodes, s.hubs, s.toyMixes) })
            end
            header = string.format("%d profile(s)", count)
        else
            header = self:DescribeEnvelope(data)
            scopeText = scope
            if scope == "triggers" then
                for id, trig in pairs(p.triggers or {}) do
                    table.insert(rows, { "|cffffd100" .. tostring(trig.name or id) .. "|r",
                        (trig.event or "?") .. (trig.enabled == false and " |cff888888(off)|r" or "") })
                    -- Show what the trigger actually does, not just its name.
                    for _, detail in ipairs(self:GetTriggerActionRows(trig, p)) do
                        table.insert(rows, detail)
                    end
                end
            elseif scope == "toymixes" then
                for name, mix in pairs(p.toyMixes or {}) do
                    local toySlots = {}
                    for _, s in ipairs(type(mix) == "table" and mix.slots or {}) do
                        if type(s) == "table" and s.type == "toy" and s.id then
                            table.insert(toySlots, s.id)
                        end
                    end
                    local slots = #toySlots
                    table.insert(rows, { "|cffffd100" .. tostring(name) .. "|r",
                        slots .. " toy" .. (slots == 1 and "" or "s") })

                    -- List the actual toys with icon, name and whether the
                    -- viewer owns them; the id drives a real game tooltip.
                    for _, toyID in ipairs(toySlots) do
                        local tLabel, tNote, tID = self:DescribeToySlot(toyID)
                        if tLabel then
                            table.insert(rows, { tLabel, tNote, tID })
                        end
                    end

                    -- Same action breakdown the trigger rows get, so the
                    -- recipient sees what the mix will actually do.
                    local acts = type(mix) == "table" and mix.actions or nil
                    if type(acts) == "table" then
                        for _, field in ipairs({
                            { key = "sound",     kind = "sound", label = "Sound" },
                            { key = "animation", kind = "anim",  label = "Animation" },
                            { key = "emote",     kind = "emote", label = "Emote" },
                            { key = "chat",      kind = "chat",  label = "Chat" },
                        }) do
                            local shown = self:DescribeActionValue(field.kind, acts[field.key], p)
                            if shown then
                                table.insert(rows, { "   |cff888888" .. field.label .. ":|r", shown })
                            end
                        end
                        if acts.chat or acts.emote then
                            local bits = {}
                            if acts.chat then table.insert(bits, "sends chat") end
                            if acts.emote then table.insert(bits, "emotes") end
                            table.insert(rows, { "   |cffff8800! Will act for you|r",
                                "|cffff8800" .. table.concat(bits, ", ") .. "|r" })
                        end
                    end
                end
            elseif scope == "oxedring" then
                rows = self:GetRingDetailRows(p)
            elseif scope == "hubs" then
                for i, hub in ipairs(p.hubs or {}) do
                    for _, row in ipairs(self:GetHubDetailRows(hub, i)) do
                        table.insert(rows, row)
                    end
                end
            end
        end

        local a = data.author
        if a then
            table.insert(authorLines, "|cffffd100From:|r " .. self:FormatAuthorName(a, true))
            local bits = {}
            if a.class then table.insert(bits, a.class) end
            if a.region then table.insert(bits, a.region) end
            if a.dateStr then table.insert(bits, a.dateStr) end
            if a.addonVersion then table.insert(bits, "OxedHub v" .. a.addonVersion) end
            if #bits > 0 then
                table.insert(authorLines, "|cff888888" .. table.concat(bits, "  •  ") .. "|r")
            end
            if a.note then
                table.insert(authorLines, "|cffaaaaaa\"" .. a.note .. "\"|r")
            end
        end
    else
        -- Legacy v1 / v2 payloads.
        if data.profiles then
            local count = 0
            for name, pdb in pairs(data.profiles) do
                count = count + 1
                local s = self:GetProfileStats(pdb)
                table.insert(rows, { "|cff88ff88" .. tostring(name) .. "|r",
                    string.format("%d triggers, %d ring, %d hubs, %d mixes",
                        s.triggers, s.ringNodes, s.hubs, s.toyMixes) })
            end
            header = string.format("%d profile(s)", count)
        else
            header = "Profile: |cff88ff88" .. tostring(data.profileName or "?") .. "|r"
            rows = StatRows(data)
            self:AppendProfileDetails(rows, data)
        end

        -- v1/v2 exports carry the author on _author rather than in an envelope.
        local a = data._author
        if a then
            table.insert(authorLines, "|cffffd100From:|r " .. self:FormatAuthorName(a, true))
            local bits = {}
            if a.class then table.insert(bits, a.class) end
            if a.region then table.insert(bits, a.region) end
            if a.dateStr then table.insert(bits, a.dateStr) end
            if a.addonVersion then table.insert(bits, "OxedHub v" .. a.addonVersion) end
            if #bits > 0 then
                table.insert(authorLines, "|cff888888" .. table.concat(bits, "  •  ") .. "|r")
            end
            if a.note then
                table.insert(authorLines, "|cffaaaaaa\"" .. a.note .. "\"|r")
            end
        end
    end

    if #authorLines == 0 then
        table.insert(authorLines, "|cff888888From: unknown (export has no author info)|r")
    end

    return header, rows, authorLines, isPartial, scopeText
end

-- Roomy confirmation dialog: shows the contents as a scrollable table, who sent
-- Render f.allRows into the pooled row frames, honouring collapsed sections.
-- Split out from ShowImportConfirm so folding a section only re-lays-out rows
-- instead of rebuilding the whole dialog (which would reset scroll position).
function UI:LayoutImportRows(f)
    UI.importCollapsed = UI.importCollapsed or {}
    local rows = f.allRows or {}

    for _, row in ipairs(f.rowPool) do row:Hide() end

    local y, shown = 0, 0
    for _, entry in ipairs(rows) do
        -- Skip members of a folded section; headers always stay visible.
        local hidden = entry.section and UI.importCollapsed[entry.section]
        if not hidden then
            shown = shown + 1
            local row = f.rowPool[shown]
            if not row then
                row = CreateFrame("Frame", nil, f.tableChild)
                row:SetHeight(20)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.label:SetJustifyH("LEFT")
                row.label:SetWidth(280)
                row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.value:SetPoint("LEFT", row, "LEFT", 292, 0)
                row.value:SetJustifyH("LEFT")
                row.value:SetWidth(190)

                row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
                row.highlight:SetAllPoints()
                row.highlight:SetColorTexture(1, 0.82, 0, 0.10)
                row.highlight:Hide()

                row:SetScript("OnEnter", function(self)
                    if self.sectionKey then self.highlight:Show() end
                    if not self.tooltipItemID then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local ok = false
                    if GameTooltip.SetToyByItemID then
                        ok = pcall(GameTooltip.SetToyByItemID, GameTooltip, self.tooltipItemID)
                    end
                    if not ok then
                        pcall(GameTooltip.SetItemByID, GameTooltip, self.tooltipItemID)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function(self)
                    self.highlight:Hide()
                    GameTooltip:Hide()
                end)
                row:SetScript("OnMouseDown", function(self)
                    if not self.sectionKey then return end
                    UI.importCollapsed[self.sectionKey] = not UI.importCollapsed[self.sectionKey]
                    UI:LayoutImportRows(f)
                end)

                f.rowPool[shown] = row
            end

            row:SetParent(f.tableChild)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.tableChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", f.tableChild, "RIGHT", 0, 0)
            row.bg:SetColorTexture(1, 1, 1, (shown % 2 == 0) and 0.03 or 0)

            row.sectionKey = entry.sectionHeader
            if row.sectionKey then
                -- Headers get an arrow and act as the fold control.
                local arrow = UI.importCollapsed[row.sectionKey] and "|cff888888[+]|r" or "|cff888888[-]|r"
                row.label:SetText(arrow .. " |cffffd100" .. tostring(entry[1]) .. "|r")
            else
                row.label:SetText(tostring(entry[1]))
            end

            row.value:SetText(tostring(entry[2] or ""))
            row.tooltipItemID = entry[3]
            row.highlight:Hide()
            row:EnableMouse(entry[3] ~= nil or row.sectionKey ~= nil)
            row:Show()
            y = y + 20
        end
    end

    f.tableChild:SetHeight(math.max(y, 1))
end

-- it, and where it lands, with Import / New Profile / Cancel.
function UI:ShowImportConfirm(data, onImported)
    local f = UI.importConfirmFrame
    if not f then
        f = CreateFrame("Frame", "OxedHubImportConfirmFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(560, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "OxedHubImportConfirmFrame")
        if f.TitleText then f.TitleText:SetText("Confirm Import") end
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

        f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.header:SetPoint("TOPLEFT", 16, -34)
        f.header:SetTextColor(1, 0.82, 0, 1)

        f.author = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.author:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -6)
        f.author:SetWidth(510)
        f.author:SetJustifyH("LEFT")
        f.author:SetSpacing(2)

        -- Scrollable contents table.
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f.author, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 84)
        StyleScrollFrame(scroll)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(490, 1)
        scroll:SetScrollChild(child)
        f.scroll, f.tableChild = scroll, child
        f.rowPool = {}

        f.targetLine = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.targetLine:SetPoint("BOTTOMLEFT", 16, 50)
        f.targetLine:SetWidth(510)
        f.targetLine:SetJustifyH("LEFT")
        f.targetLine:SetJustifyV("BOTTOM")
        f.targetLine:SetSpacing(2)

        f.cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(f.cancelBtn)
        f.cancelBtn:SetSize(100, 26)
        f.cancelBtn:SetPoint("BOTTOMRIGHT", -14, 16)
        f.cancelBtn:SetText(CANCEL or "Cancel")
        f.cancelBtn:SetScript("OnClick", function() f:Hide() end)

        f.newProfileBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(f.newProfileBtn)
        f.newProfileBtn:SetSize(140, 26)
        f.newProfileBtn:SetPoint("RIGHT", f.cancelBtn, "LEFT", -8, 0)
        f.newProfileBtn:SetText("New Profile")

        f.importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(f.importBtn)
        f.importBtn:SetSize(100, 26)
        f.importBtn:SetPoint("RIGHT", f.newProfileBtn, "LEFT", -8, 0)
        f.importBtn:SetText("Import")

        UI.importConfirmFrame = f
    end

    UI._importPendingItemLoad = false
    local header, rows, authorLines, isPartial = self:GetImportDetails(data)
    f.header:SetText(header)

    -- Some toy/item names were not cached yet. Redraw shortly after the client
    -- has had a chance to load them.  Capped, because an id the client can
    -- never resolve would otherwise redraw forever.
    if data ~= UI._importRedrawData then
        UI._importRedrawData = data
        UI._importRedrawTries = 0
    end
    if UI._importPendingItemLoad
        and not UI._importRedrawQueued
        and (UI._importRedrawTries or 0) < 3
    then
        UI._importRedrawQueued = true
        UI._importRedrawTries = (UI._importRedrawTries or 0) + 1
        C_Timer.After(0.7, function()
            UI._importRedrawQueued = nil
            if f:IsShown() then
                UI:ShowImportConfirm(data, onImported)
            end
        end)
    end
    f.author:SetText(table.concat(authorLines, "\n"))

    f.allRows = rows
    UI:LayoutImportRows(f)
    f.scroll:SetVerticalScroll(0)

    local target = UI.importTargetProfile or (OxedHubDB and OxedHubDB.activeProfile) or "?"
    local targetText
    if isPartial then
        -- Partial data merges into a profile you pick, so overwriting is real.
        targetText = "|cffffd100Imports into:|r " .. target
            .. "\n|cffff8800Items with the same name or ID will be overwritten.|r"
        f.newProfileBtn:Show()
    else
        -- Full profiles always land in a new profile; a clashing name gets a
        -- suffix rather than replacing what you already have.
        local incoming = "?"
        local p = (data.formatVersion == 3 and data.payload) or data
        if p and p.profileName then incoming = p.profileName end

        if OxedHubDB.profiles and OxedHubDB.profiles[incoming] then
            targetText = "|cffffd100Creates profile:|r " .. incoming .. " (Imported)"
                .. "\n|cff888888You already have a profile called '" .. incoming
                .. "' — it will not be touched.|r"
        else
            targetText = "|cffffd100Creates profile:|r " .. incoming
        end
        -- Nothing for the button to do here: the import is already non-destructive.
        f.newProfileBtn:Hide()
    end

    -- Warn about sounds/animations this client doesn't have.
    local missingSounds, missingAnimations = self:ValidateImport(data)
    local missing = {}
    if #missingSounds > 0 then
        table.insert(missing, #missingSounds .. " sound(s)")
    end
    if #missingAnimations > 0 then
        table.insert(missing, #missingAnimations .. " animation(s)")
    end
    if #missing > 0 then
        targetText = targetText .. "\n|cffffcc00Missing on this client: "
            .. table.concat(missing, ", ") .. "|r"
    end
    f.targetLine:SetText(targetText)

    f.importBtn:SetScript("OnClick", function()
        f:Hide()
        UI:ApplyImport(data)
        if onImported then onImported() end
        UI:ReportMissingSoundsAfterImport(data)
    end)

    -- Partial data into a fresh empty profile, leaving existing ones untouched.
    -- (Only offered for partial scopes; full profiles already create their own.)
    f.newProfileBtn:SetScript("OnClick", function()
        local base, name, n = "Imported", "Imported", 1
        while OxedHubDB.profiles[name] do
            n = n + 1
            name = base .. " " .. n
        end

        local ok, err = OxedHub:CreateProfile(name, false)
        if not ok then
            print("|cffff0000Oxed Hub:|r Could not create a profile"
                .. (err == "max_profiles" and " — profile limit reached." or "."))
            return
        end

        UI.importTargetProfile = name
        f:Hide()
        UI:ApplyImport(data)
        if onImported then onImported() end
        print("|cff00ff00Oxed Hub:|r Imported into new profile |cffffff00" .. name .. "|r.")
        UI:ReportMissingSoundsAfterImport(data)
    end)

    f:Show()
    f:Raise()
end

-- Build a v3 envelope (serialized). opts: { note, profileNames, triggerIDs, hubIndex }
function UI:SerializeScoped(scope, opts)
    opts = opts or {}
    local activeName = OxedHubDB.activeProfile
    local profile = OxedHubDB.profiles and OxedHubDB.profiles[activeName]
    if not profile then return nil, "No active profile." end

    local envelope = {
        oxedhub = true,
        formatVersion = 3,
        scope = scope,
        author = CaptureAuthorMeta(opts.note),
        payload = {},
    }

    if scope == "profile" then
        envelope.payload = BuildProfileExportPayload(activeName, profile)
    elseif scope == "profiles" then
        local out = { profiles = {}, activeProfile = activeName }
        local names = opts.profileNames
        if names and #names > 0 then
            for _, n in ipairs(names) do
                if OxedHubDB.profiles[n] then out.profiles[n] = BuildProfileExportPayload(n, OxedHubDB.profiles[n]) end
            end
        else
            for n, db in pairs(OxedHubDB.profiles) do out.profiles[n] = BuildProfileExportPayload(n, db) end
        end
        if not next(out.profiles) then return nil, "No profiles to export." end
        envelope.payload = out
    elseif scope == "triggers" then
        local out = {}
        local src = profile.triggers or {}
        if opts.triggerIDs and #opts.triggerIDs > 0 then
            for _, id in ipairs(opts.triggerIDs) do if src[id] then out[id] = src[id] end end
        else
            for id, t in pairs(src) do out[id] = t end
        end
        if not next(out) then return nil, "No triggers to export." end
        envelope.payload = { triggers = out }

        -- Bundle the custom sound definitions these triggers reference, so the
        -- recipient sees real names instead of raw ids (and can play them if
        -- they have the matching media addon).
        local srcSounds = (OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds())
            or profile.customSounds or {}
        local usedSounds = nil
        for _, trig in pairs(out) do
            local a = type(trig) == "table" and trig.actions or nil
            if type(a) == "table" then
                for _, key in ipairs({ "sound", "successSound", "failSound" }) do
                    local id = a[key]
                    if id and srcSounds[id] then
                        usedSounds = usedSounds or {}
                        usedSounds[id] = srcSounds[id]
                    end
                end
            end
        end
        if usedSounds then envelope.payload.customSounds = usedSounds end
    elseif scope == "oxedring" then
        -- The ring lives in the profile only when it is set to "unique";
        -- a shared ring is stored in globalSettings.  Read whichever the user
        -- is actually on, otherwise a shared ring exports as empty.
        local ringDB = (OxedHub.GetRingDB and OxedHub.GetRingDB()) or profile
        local out = {}
        for _, k in ipairs(OXEDRING_KEYS) do
            out[k] = ringDB[k]
            if out[k] == nil then out[k] = profile[k] end
        end
        if not (out.oxedRingNodes and next(out.oxedRingNodes)) then
            return nil, "No ring nodes to export."
        end
        envelope.payload = out
    elseif scope == "toymixes" then
        if not (profile.toyMixes and next(profile.toyMixes)) then return nil, "No toy mixes to export." end
        -- opts.mixNames narrows the export to specific mixes; without it the
        -- whole collection goes, which is what the bulk export button wants.
        if opts.mixNames and #opts.mixNames > 0 then
            local picked = {}
            for _, mixName in ipairs(opts.mixNames) do
                if profile.toyMixes[mixName] then picked[mixName] = profile.toyMixes[mixName] end
            end
            if not next(picked) then return nil, "Toy mix not found." end
            envelope.payload = { toyMixes = picked }
        else
            envelope.payload = { toyMixes = profile.toyMixes }
        end
    elseif scope == "hubs" then
        local ah = profile.actionHub or {}
        local hubs = ah.hubs or {}
        if opts.hubIndex then
            local one = hubs[opts.hubIndex]
            if not one then return nil, "Hub not found." end
            envelope.payload = { hubs = { one } }
        else
            if #hubs == 0 then return nil, "No hubs to export." end
            envelope.payload = { hubs = hubs }
        end
    else
        return nil, "Unknown export scope: " .. tostring(scope)
    end

    return AceSerializer:Serialize(envelope)
end

-- Build a human-readable "imported from…" summary for a profile's hover tooltip.
-- Returns nil if the profile has no recorded import sources.
function UI:GetProfileOriginText(db)
    if type(db) ~= "table" or type(db.importSources) ~= "table" or #db.importSources == 0 then
        return nil
    end
    local lines = { "|cffffd100Imported content:|r" }
    for _, src in ipairs(db.importSources) do
        local a = src.author or {}
        local who = a.character and (a.character .. "-" .. tostring(a.realm or "?")) or "unknown"
        local extra = {}
        if a.class then table.insert(extra, a.class) end
        if a.region then table.insert(extra, a.region) end
        if a.dateStr then table.insert(extra, a.dateStr) end
        local suffix = (#extra > 0) and (" (" .. table.concat(extra, ", ") .. ")") or ""
        table.insert(lines, string.format("|cff88ff88%s|r: %s%s", tostring(src.scope), who, suffix))
        if a.note then
            table.insert(lines, "   |cffaaaaaa\"" .. a.note .. "\"|r")
        end
    end
    return table.concat(lines, "\n")
end

-- Record where a piece of imported data came from (for the hover tooltip).
function UI:StampImportSource(db, author, scope)
    if not db or not author then return end
    db.importSources = db.importSources or {}
    table.insert(db.importSources, { author = author, scope = scope, date = time() })
    db.lastImport = { author = author, scope = scope, date = time() }
end

local function CompressExportString(serialized)
    if not serialized or serialized == "" then
        return nil, "No export data generated."
    end

    if not C_EncodingUtil or not C_EncodingUtil.CompressString or not C_EncodingUtil.EncodeBase64 then
        return nil, "Compression API unavailable."
    end

    local compressionMethod = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
    local compressionLevel = Enum and Enum.CompressionLevel and Enum.CompressionLevel.OptimizeForSize or 2
    local base64Variant = Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1

    local okCompress, compressed = pcall(C_EncodingUtil.CompressString, serialized, compressionMethod, compressionLevel)
    if not okCompress or not compressed or compressed == "" then
        return nil, "Compression failed."
    end

    local okEncode, encoded = pcall(C_EncodingUtil.EncodeBase64, compressed, base64Variant)
    if not okEncode or not encoded or encoded == "" then
        return nil, "Base64 encoding failed."
    end

    return EXPORT_COMPRESSED_PREFIX .. encoded
end

local function DecompressExportString(encodedText)
    if not encodedText or encodedText == "" then
        return nil, "Empty import string."
    end

    if encodedText:sub(1, #EXPORT_COMPRESSED_PREFIX) ~= EXPORT_COMPRESSED_PREFIX then
        return nil
    end

    if not C_EncodingUtil or not C_EncodingUtil.DecodeBase64 or not C_EncodingUtil.DecompressString then
        return false, "This export uses compressed format, but the WoW client cannot decode it."
    end

    local payload = encodedText:sub(#EXPORT_COMPRESSED_PREFIX + 1)
    local base64Variant = Enum and Enum.Base64Variant and Enum.Base64Variant.StandardUrlSafe or 1
    local compressionMethod = Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0

    local okDecode, decoded = pcall(C_EncodingUtil.DecodeBase64, payload, base64Variant)
    if not okDecode or not decoded or decoded == "" then
        return false, "Failed to decode compressed export string."
    end

    local okDecompress, serialized = pcall(C_EncodingUtil.DecompressString, decoded, compressionMethod)
    if not okDecompress or not serialized or serialized == "" then
        return false, "Failed to decompress export string."
    end

    return serialized
end

-- Decode a full export string (compressed or raw) into an import envelope.
-- Shared by the paste-in-a-box import flow and by chat link sharing.
-- Returns data, or nil plus an error message.
function UI:DecodeExportString(text)
    if type(text) ~= "string" or text == "" then
        return nil, "Empty import string."
    end

    local decompressed, err = DecompressExportString(text)
    if decompressed == false then
        return nil, err or "Compressed import failed."
    elseif decompressed then
        text = decompressed
    end

    local ok, deserialized = AceSerializer:Deserialize(text)
    local looksValid = ok and type(deserialized) == "table"
        and (deserialized.version or deserialized.formatVersion == 3
            or deserialized.profiles or deserialized.profileName)
    if not looksValid then
        return nil, "Invalid import string."
    end

    return deserialized
end

local function SplitExportString(str)
    if not str or str == "" then
        return {}
    end

    if #str <= EXPORT_EDITBOX_MAX_CHARS then
        return { str }
    end

    local chunks = {}
    local totalParts = math.ceil(#str / EXPORT_CHUNK_PAYLOAD_CHARS)
    for part = 1, totalParts do
        local startIndex = ((part - 1) * EXPORT_CHUNK_PAYLOAD_CHARS) + 1
        local payload = str:sub(startIndex, startIndex + EXPORT_CHUNK_PAYLOAD_CHARS - 1)
        chunks[part] = string.format("%s:%d:%d:%s", EXPORT_CHUNK_PREFIX, part, totalParts, payload)
    end

    return chunks
end

local function BuildCompressedOrRawExport(serialized)
    if not serialized then
        return nil, "No export data generated."
    end

    local compressed, compressErr = CompressExportString(serialized)
    if compressed then
        return compressed, "compressed"
    end

    return serialized, compressErr and "raw" or "raw"
end

function UI:BuildExportStringUnbounded(profileNames, forceMultiProfile)
    local serialized, serializeErr

    if forceMultiProfile then
        serialized, serializeErr = self:SerializeSelectedProfiles(profileNames)
    else
        serialized, serializeErr = self:SerializeProfile(true)
    end

    if not serialized then
        return nil, serializeErr or "Failed to serialize export data."
    end

    local exportString = BuildCompressedOrRawExport(serialized)
    if not exportString then
        return nil, "Failed to build export string."
    end

    return exportString
end

function UI:BuildExportString(profileNames, forceMultiProfile)
    local exportString, err = self:BuildExportStringUnbounded(profileNames, forceMultiProfile)
    if not exportString then
        return nil, err
    end

    if #exportString > EXPORT_MAX_CHARS then
        return nil, string.format("Export is too large: %d / %d characters.", #exportString, EXPORT_MAX_CHARS)
    end

    return exportString
end

-- Build the final (compressed, size-checked) export string for a scoped export.
function UI:BuildScopedExportString(scope, opts)
    local serialized, err = self:SerializeScoped(scope, opts)
    if not serialized then return nil, err end
    local exportString = BuildCompressedOrRawExport(serialized)
    if not exportString then return nil, "Failed to build export string." end
    if #exportString > EXPORT_MAX_CHARS then
        return nil, string.format("Export is too large: %d / %d characters.", #exportString, EXPORT_MAX_CHARS)
    end
    return exportString
end

function UI:GetExportEstimate(profileNames, forceMultiProfile)
    local exportString, err = self:BuildExportStringUnbounded(profileNames, forceMultiProfile)
    if not exportString then
        return nil, err
    end

    return #exportString, nil, exportString
end

local function ParseChunkedImport(text)
    local prefix, part, total, payload = text:match("^(.-):(%d+):(%d+):(.+)$")
    if prefix ~= EXPORT_CHUNK_PREFIX then
        return nil
    end

    part = tonumber(part)
    total = tonumber(total)
    if not part or not total or part < 1 or total < 1 or part > total or not payload or payload == "" then
        return false, "Invalid OxedHub chunk header."
    end

    return {
        part = part,
        total = total,
        payload = payload,
    }
end

function UI:ResetImportChunks()
    self.importChunkState = nil
end

function UI:UpdateChunkStatus(frame, message, color)
    if not frame or not frame.chunkStatus then
        return
    end

    frame.chunkStatus:SetText(message or "")
    if color == "error" then
        frame.chunkStatus:SetTextColor(1, 0.2, 0.2, 1)
    else
        frame.chunkStatus:SetTextColor(1, 0.82, 0, 1)
    end
end

function UI:HandleChunkedImport(frame, chunkInfo)
    local state = self.importChunkState
    if not state or state.total ~= chunkInfo.total then
        state = {
            total = chunkInfo.total,
            parts = {},
            received = 0,
        }
        self.importChunkState = state
    end

    if not state.parts[chunkInfo.part] then
        state.parts[chunkInfo.part] = chunkInfo.payload
        state.received = state.received + 1
    else
        state.parts[chunkInfo.part] = chunkInfo.payload
    end

    if state.received < state.total then
        self:UpdateChunkStatus(frame, string.format("Imported part %d/%d. Paste the next part.", chunkInfo.part, chunkInfo.total))
        return nil, "pending"
    end

    local combined = {}
    for index = 1, state.total do
        if not state.parts[index] then
            self:UpdateChunkStatus(frame, string.format("Missing part %d of %d.", index, state.total), "error")
            return nil, "pending"
        end
        combined[index] = state.parts[index]
    end

    self.importChunkState = nil
    self:UpdateChunkStatus(frame, "")
    return table.concat(combined)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Missing-sound handling for imports.
--
-- Addons can't download files, so a sound whose audio file the importer doesn't
-- have can never be "fetched". What we can do is detect it properly, say what
-- uses it, and offer the closest sound the player does have.
-- ─────────────────────────────────────────────────────────────────────────

-- Every sound id referenced by a payload, mapped to a readable list of the
-- things using it. Covers far more than the old triggers+emotes check.
function UI:CollectSoundReferences(data)
    local refs = {}

    local function Note(id, usedBy)
        if not id or id == "" or id == "None" then return end
        refs[id] = refs[id] or {}
        if usedBy and #refs[id] < 6 then
            table.insert(refs[id], usedBy)
        end
    end

    for id, trigger in pairs(data.triggers or {}) do
        local label = (trigger.name and trigger.name ~= "" and trigger.name) or tostring(id)
        local a = trigger.actions or {}
        -- Every sound key a trigger can carry, including the per-state ones.
        for _, key in ipairs({ "sound", "successSound", "failSound",
            "groundSound", "flyingSound", "aquaticSound",
            "enterSound", "exitSound" }) do
            Note(a[key], "Trigger: " .. label)
        end
    end

    for id, mapping in pairs(data.emotionMappings or {}) do
        Note(mapping.sound, "Reaction: " .. tostring(id))
    end

    for name, mix in pairs(data.toyMixes or {}) do
        if type(mix) == "table" then
            for _, act in ipairs(mix.actions or {}) do
                if type(act) == "table" then
                    Note(act.sound or (act.type == "sound" and act.id), "Toy mix: " .. tostring(name))
                end
            end
            Note(mix.sound, "Toy mix: " .. tostring(name))
        end
    end

    local hubs = (data.actionHub and data.actionHub.hubs) or data.hubs or {}
    for hubIndex, hub in ipairs(hubs) do
        for _, slot in pairs(hub.slots or {}) do
            if type(slot) == "table" and slot.type == "sound" then
                Note(slot.id, "Action Hub " .. hubIndex)
            end
        end
    end

    for _, node in pairs(data.oxedRingNodes or {}) do
        if type(node) == "table" then
            Note(node.sound, "OxedRing node")
        end
    end

    return refs
end

-- Is the audio file actually on disk? PlaySoundFile returns willPlay=false for a
-- missing file without producing sound; when it does play we stop the handle
-- immediately, which is why this is only used on sounds worth checking.
function UI:SoundFileExists(soundId, payload)
    local path
    if OxedHub.Sounds and OxedHub.Sounds.GetFilePath then
        path = OxedHub.Sounds:GetFilePath(soundId)
    end
    -- Fall back to the definition travelling inside the import itself.
    if not path and payload and payload.customSounds and payload.customSounds[soundId] then
        path = payload.customSounds[soundId].filePath
    end
    if not path or path == "" then return false, nil end

    -- Sounds that ship with the addon are always present, so don't probe them —
    -- probing plays the file for an instant, and there's no reason to risk that
    -- blip on files we know exist.
    if OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[soundId] then
        return true, path
    end
    if path:find("OxedHub\\Media\\Sound", 1, true) then
        return true, path
    end

    local ok, willPlay, handle = pcall(PlaySoundFile, path, "Master")
    if not ok then return true, path end   -- can't tell; assume present
    if willPlay and handle then
        pcall(StopSound, handle)
    end
    return willPlay and true or false, path
end

-- Closest available sound for a missing one: prefer the same category, then
-- score on shared words in the name.
function UI:FindReplacementSound(soundId, definition)
    local wanted = (definition and definition.name) or tostring(soundId)
    local wantedCat = definition and definition.category
    local wantedLower = wanted:lower()

    local function Score(name, category)
        local score = 0
        if category and wantedCat and category == wantedCat then score = score + 5 end
        local lower = (name or ""):lower()
        if lower == wantedLower then return score + 100 end
        -- Shared words, ignoring very short ones.
        for word in wantedLower:gmatch("[%w]+") do
            if #word > 2 and lower:find(word, 1, true) then
                score = score + 3
            end
        end
        return score
    end

    local bestId, bestScore
    local function Consider(id, def)
        if id == soundId or type(def) ~= "table" then return end
        local s = Score(def.name, def.category)
        if s > 0 and (not bestScore or s > bestScore) then
            bestId, bestScore = id, s
        end
    end

    for id, def in pairs(OxedHub.GENERATED_SOUND_CATALOG or {}) do Consider(id, def) end
    local shared = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds()
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
    for id, def in pairs(shared) do Consider(id, def) end

    return bestId
end

-- After an import: which referenced sounds can't actually be played here.
-- Returns { {id, name, path, usedBy, suggestion}, ... }
function UI:FindUnplayableSounds(payload)
    if type(payload) ~= "table" then return {} end
    if payload.formatVersion == 3 and payload.payload then payload = payload.payload end

    local refs = self:CollectSoundReferences(payload)
    local shared = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds()
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}

    local problems = {}
    for id, usedBy in pairs(refs) do
        local definition = shared[id]
            or (payload.customSounds and payload.customSounds[id])
            or (OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[id])

        local playable, path = self:SoundFileExists(id, payload)
        if not playable then
            table.insert(problems, {
                id = id,
                name = (definition and definition.name) or id,
                path = path,
                usedBy = usedBy,
                suggestion = self:FindReplacementSound(id, definition),
            })
        end
    end

    table.sort(problems, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return problems
end

-- Swap every reference to oldId for newId across the active profile.
function UI:ReplaceSoundEverywhere(oldId, newId)
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return 0 end
    local changed = 0

    local SOUND_KEYS = { "sound", "successSound", "failSound",
        "groundSound", "flyingSound", "aquaticSound", "enterSound", "exitSound" }

    for _, trigger in pairs(p.triggers or {}) do
        local a = trigger.actions
        if a then
            for _, key in ipairs(SOUND_KEYS) do
                if a[key] == oldId then a[key] = newId; changed = changed + 1 end
            end
        end
    end
    for _, mapping in pairs(p.emotionMappings or {}) do
        if mapping.sound == oldId then mapping.sound = newId; changed = changed + 1 end
    end
    for _, mix in pairs(p.toyMixes or {}) do
        if type(mix) == "table" then
            if mix.sound == oldId then mix.sound = newId; changed = changed + 1 end
            for _, act in ipairs(mix.actions or {}) do
                if type(act) == "table" then
                    if act.sound == oldId then act.sound = newId; changed = changed + 1 end
                    if act.type == "sound" and act.id == oldId then act.id = newId; changed = changed + 1 end
                end
            end
        end
    end
    for _, hub in ipairs((p.actionHub and p.actionHub.hubs) or {}) do
        for _, slot in pairs(hub.slots or {}) do
            if type(slot) == "table" and slot.type == "sound" and slot.id == oldId then
                slot.id = newId
                changed = changed + 1
            end
        end
    end
    for _, node in pairs(p.oxedRingNodes or {}) do
        if type(node) == "table" and node.sound == oldId then
            node.sound = newId
            changed = changed + 1
        end
    end

    return changed
end

-- Runs after an import lands. Deferred a moment so the profile switch and
-- sound-cache sync have finished before anything is probed.
function UI:ReportMissingSoundsAfterImport(data)
    C_Timer.After(0.5, function()
        local problems = UI:FindUnplayableSounds(data)
        if #problems == 0 then return end

        print(("|cffffcc00Oxed Hub:|r %d imported sound(s) are missing on your PC.")
            :format(#problems))
        UI:ShowMissingSoundsDialog(problems)
    end)
end

-- Report missing sounds and offer to swap each for one the player has.
function UI:ShowMissingSoundsDialog(problems)
    if not problems or #problems == 0 then return end

    local f = UI.missingSoundsFrame
    if not f then
        f = CreateFrame("Frame", "OxedHubMissingSoundsFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(600, 460)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "OxedHubMissingSoundsFrame")
        if f.TitleText then f.TitleText:SetText("Missing Sounds") end
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

        f.intro = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.intro:SetPoint("TOPLEFT", 16, -32)
        f.intro:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        f.intro:SetJustifyH("LEFT")
        f.intro:SetSpacing(2)

        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f.intro, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 52)
        StyleScrollFrame(scroll)
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(520, 1)
        scroll:SetScrollChild(child)
        f.scroll, f.listChild, f.rows = scroll, child, {}

        f.replaceAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(f.replaceAllBtn)
        f.replaceAllBtn:SetSize(190, 26)
        f.replaceAllBtn:SetPoint("BOTTOMLEFT", 16, 16)
        f.replaceAllBtn:SetText("Replace All With Suggested")

        f.closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(f.closeBtn)
        f.closeBtn:SetSize(110, 26)
        f.closeBtn:SetPoint("BOTTOMRIGHT", -16, 16)
        f.closeBtn:SetText(CLOSE or "Close")
        f.closeBtn:SetScript("OnClick", function() f:Hide() end)

        UI.missingSoundsFrame = f
    end

    local function FullSoundName(id)
        local shared = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds()
            or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
        local def = shared[id] or (OxedHub.GENERATED_SOUND_CATALOG or {})[id]
        return (def and def.name) or tostring(id)
    end

    local Render
    Render = function()
        f.intro:SetText(("|cffff8800%d sound(s) used by this profile can't be played on your PC.|r\n"
            .. "The audio files live on the sender's computer and can't be transferred. "
            .. "Pick a replacement you already have, or leave them silent until you add the files.")
            :format(#problems))

        for _, row in ipairs(f.rows) do row:Hide() end

        local y = 0
        for i, problem in ipairs(problems) do
            local row = f.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, f.listChild)
                row:SetHeight(64)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
                row.name:SetJustifyH("LEFT")
                row.name:SetWidth(300)
                row.used = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.used:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
                row.used:SetJustifyH("LEFT")
                row.used:SetWidth(300)
                -- What the Replace button will actually swap in.
                row.suggested = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.suggested:SetPoint("TOPLEFT", row.used, "BOTTOMLEFT", 0, -2)
                row.suggested:SetJustifyH("LEFT")
                row.suggested:SetWidth(460)
                row.replaceBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                ApplyRedButtonStyle(row.replaceBtn)
                row.replaceBtn:SetSize(100, 22)
                row.replaceBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -110, -6)
                row.clearBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                ApplyRedButtonStyle(row.clearBtn)
                row.clearBtn:SetSize(100, 22)
                row.clearBtn:SetPoint("LEFT", row.replaceBtn, "RIGHT", 6, 0)
                row.clearBtn:SetText("Remove")
                f.rows[i] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.listChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", f.listChild, "RIGHT", 0, 0)
            row:Show()

            -- When the export carried no definition all we have is the id, so
            -- say so rather than showing a meaningless string as a "name".
            local label = tostring(problem.name)
            if label == tostring(problem.id) then
                label = "|cffff5555Unknown sound|r |cff888888(" .. tostring(problem.id) .. ")|r"
            else
                label = "|cffffd100" .. label .. "|r |cff888888(" .. tostring(problem.id) .. ")|r"
            end
            row.name:SetText(label)

            local used = table.concat(problem.usedBy or {}, ", ")
            if used == "" then used = "not referenced" end
            row.used:SetText("Used by: " .. used)

            if problem.suggestion then
                row.suggested:SetText("|cff888888Will use:|r |cff00ff00"
                    .. FullSoundName(problem.suggestion) .. "|r")
                row.replaceBtn:SetText("Replace")
                row.replaceBtn:Enable()
                row.replaceBtn:SetScript("OnClick", function()
                    UI:ReplaceSoundEverywhere(problem.id, problem.suggestion)
                    table.remove(problems, i)
                    if #problems == 0 then f:Hide() else Render() end
                end)
            else
                row.suggested:SetText("|cff888888No similar sound found — use Remove.|r")
                row.replaceBtn:SetText("No match")
                row.replaceBtn:Disable()
            end

            -- Clears the dead reference so nothing keeps pointing at a file that
            -- isn't there; the trigger simply plays no sound.
            row.clearBtn:SetScript("OnClick", function()
                UI:ReplaceSoundEverywhere(problem.id, nil)
                table.remove(problems, i)
                if #problems == 0 then f:Hide() else Render() end
            end)

            y = y + 68
        end
        f.listChild:SetHeight(math.max(y, 1))
        f.scroll:SetVerticalScroll(0)
    end

    f.replaceAllBtn:SetScript("OnClick", function()
        -- Report every swap: the dialog closes on success, so without this the
        -- player never finds out which sounds were substituted.
        local swaps = {}
        for i = #problems, 1, -1 do
            local problem = problems[i]
            if problem.suggestion then
                UI:ReplaceSoundEverywhere(problem.id, problem.suggestion)
                table.insert(swaps, 1, string.format("|cffff8800%s|r -> |cff00ff00%s|r",
                    tostring(problem.name), FullSoundName(problem.suggestion)))
                table.remove(problems, i)
            end
        end

        if #swaps > 0 then
            print(("|cff00ff00Oxed Hub:|r Replaced %d missing sound(s):"):format(#swaps))
            for _, line in ipairs(swaps) do print("   " .. line) end
        end

        if #problems == 0 then f:Hide() else Render() end
    end)

    Render()
    f:Show()
    f:Raise()
end

function UI:ValidateImport(data)
    -- Unwrap v3 envelopes so sound/animation checks see the actual payload.
    if type(data) == "table" and data.formatVersion == 3 and data.payload then
        data = data.payload
    end
    local missingSounds = {}
    local missingAnimations = {}
    local localSounds = OxedHub.db.profile.customSounds or {}
    local localAnimations = OxedHub.db.profile.animations or {}

    local function checkSound(id)
        if id and id ~= "" and id ~= "None" then
            -- A sound is only "missing" if it's NOT in local DB AND NOT in the bundle AND NOT in catalog
            if not localSounds[id] and not (data.customSounds and data.customSounds[id]) and not OxedHub.GENERATED_SOUND_CATALOG[id] then
                missingSounds[id] = true
            end
        end
    end
    local function checkAnimation(id)
        if id and id ~= "" and id ~= "None" then
            -- An animation is only "missing" if it's NOT in local DB AND NOT in the bundle
            if not localAnimations[id] and not (data.animations and data.animations[id]) then
                missingAnimations[id] = true
            end
        end
    end

    -- Check triggers
    for _, trigger in pairs(data.triggers or {}) do
        if trigger.actions then
            checkSound(trigger.actions.sound)
            checkAnimation(trigger.actions.animation)
        end
    end
    -- Check emotion mappings
    for _, mapping in pairs(data.emotionMappings or {}) do
        checkSound(mapping.sound)
        checkAnimation(mapping.animation)
    end

    local soundList, animList = {}, {}
    for k in pairs(missingSounds) do table.insert(soundList, k) end
    for k in pairs(missingAnimations) do table.insert(animList, k) end
    return soundList, animList
end

-- Keys the block below handles explicitly (special merge logic), plus the payload
-- envelope and volatile caches. The generic pass at the end applies everything
-- NOT in this set, so newly-added profile sections import without code changes.
local IMPORT_HANDLED_KEYS = {
    -- payload envelope (not profile data)
    version = true, profileName = true,
    -- volatile / character-specific — do not import
    toyCollectionCache = true, testRing = true,
    -- handled by dedicated blocks below
    metadata = true, customSounds = true, animations = true, chatTemplates = true,
    emotionMappings = true, triggers = true, settings = true, actionHub = true,
    toyMixes = true,
}

function UI:_ApplySingleProfileData(db, data)
    -- The exporter may have had a shared ring, in which case their profile
    -- carries oxedRingUnique = false.  Copying that flag verbatim would make
    -- the importer read its OWN globalSettings ring and quietly ignore the ring
    -- that just arrived, so pin an incoming ring to this profile instead.
    if data.oxedRingNodes and next(data.oxedRingNodes) then
        data.oxedRingUnique = true
    end

    if data.metadata then
        db.metadata = db.metadata or {}
        for key, value in pairs(data.metadata) do
            db.metadata[key] = value
        end
    end
    if data.customSounds then
        local sharedSounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or db.customSounds or {}
        db.customSounds = sharedSounds
        for id, sound in pairs(data.customSounds) do
            sharedSounds[id] = sound
        end
        if OxedHub.SyncSharedCustomSounds then
            OxedHub:SyncSharedCustomSounds(db)
        end
    end
    if data.animations then
        db.animations = db.animations or {}
        for id, anim in pairs(data.animations) do
            db.animations[id] = anim
        end
    end
    if data.chatTemplates then
        db.chatTemplates = db.chatTemplates or {}
        for id, tmpl in pairs(data.chatTemplates) do
            db.chatTemplates[id] = tmpl
        end
    end
    if data.emotionMappings then
        db.emotionMappings = db.emotionMappings or {}
        for emotion, mapping in pairs(data.emotionMappings) do
            db.emotionMappings[emotion] = mapping
        end
    end
    if data.triggers then
        db.triggers = db.triggers or {}
        for id, trigger in pairs(data.triggers) do
            trigger.minimized = true -- Force minimized by default on import
            if type(id) == "number" then
                local newId = string.gsub(string.format('%x', math.random(0, 0xFFFFFFFF)), '.(..)', '%1') .. tostring(GetTime()):gsub("%.", "")
                db.triggers[newId] = trigger
            else
                db.triggers[id] = trigger
            end
        end
    end
    if data.settings then
        db.settings = db.settings or {}
        for k, v in pairs(data.settings) do
            if k ~= "windowPosition" and k ~= "minimapPosition" then
                db.settings[k] = v
            end
        end
    end
    if data.actionHub then
        db.actionHub = data.actionHub
    end
    if data.toyMixes then
        db.toyMixes = db.toyMixes or {}
        for id, mix in pairs(data.toyMixes) do
            db.toyMixes[id] = mix
        end
    end

    -- Generic apply for every other profile field the special cases above don't
    -- cover (OxedRing nodes/style/radius/bindings, customReactions, keybinds,
    -- emoteMerges, showcase*, internalMacros, toyRingMappings, experimental, ...).
    -- Without this, those sections were silently lost on import.
    for key, value in pairs(data) do
        if not IMPORT_HANDLED_KEYS[key] then
            if type(value) == "table" then
                db[key] = CopyTable(value)
            else
                db[key] = value
            end
        end
    end

    if OxedHub.Core and OxedHub.Core.MigrateLegacySoundPathsAndIds then
        OxedHub.Core:MigrateLegacySoundPathsAndIds()
    end
end

-- Apply a v3 scoped envelope. Partial scopes REPLACE-by-key into the ACTIVE
-- profile (imported item overwrites the same-keyed existing one; other items are
-- left alone). Whole-section scopes (oxedring) replace the section entirely.
function UI:ApplyScopedImport(env)
    local scope = env.scope
    local payload = env.payload or {}
    local author = env.author

    -- profile / profiles → create new profiles (delegate to the classic path).
    -- The payload already carries version/profileName (or a profiles table), so it
    -- imports through the existing v1/v2 logic; _author flows to the source stamp.
    if scope == "profile" or scope == "profiles" then
        payload._author = author
        self:ApplyImport(payload)
        return
    end

    -- Partial scopes go into the chosen target profile, defaulting to the active
    -- one (which is what every earlier version did).
    local targetName = UI.importTargetProfile
    if not targetName or not (OxedHubDB.profiles and OxedHubDB.profiles[targetName]) then
        targetName = OxedHubDB.activeProfile
    end
    local db = OxedHubDB.profiles and OxedHubDB.profiles[targetName]
    if not db then
        print("|cffff0000Oxed Hub:|r No profile to import into.")
        return
    end

    local summary
    if scope == "triggers" then
        db.triggers = db.triggers or {}
        local n = 0
        for id, trig in pairs(payload.triggers or {}) do
            trig.minimized = true
            db.triggers[id] = trig      -- replace-by-id
            n = n + 1
        end
        summary = n .. " trigger(s)"
        if OxedHub.Triggers then
            if OxedHub.Triggers.InvalidateEnabledEventCache then OxedHub.Triggers:InvalidateEnabledEventCache() end
            if OxedHub.Triggers.RefreshTriggersList then OxedHub.Triggers:RefreshTriggersList() end
        end

    elseif scope == "oxedring" then
        for _, k in ipairs(OXEDRING_KEYS) do
            local v = payload[k]
            -- Ring config is a mix of tables (nodes) and scalars (radius, style,
            -- sizes, booleans). Only deep-copy tables; CopyTable errors on scalars.
            if type(v) == "table" then
                db[k] = CopyTable(v)
            else
                db[k] = v
            end
        end
        -- The ring is only read from the profile when it is marked unique; on a
        -- shared ring the reader looks at globalSettings and the import would be
        -- invisible.  Pin the imported ring to this profile rather than
        -- overwriting the ring every other profile shares.
        db.oxedRingUnique = true
        summary = "OxedRing config"
        if OxedHub.OxedRing and OxedHub.OxedRing.UpdateSecureAttributes then
            OxedHub.OxedRing:UpdateSecureAttributes()
        end
        -- Re-render the ring preview nodes from the freshly imported config so the
        -- ring appears immediately (previously only the picker grid was refreshed,
        -- so nodes stayed blank until the user nudged +/- Slice Count).
        if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshFromProfile then
            pcall(function() OxedHub.OxedRingEditor:RefreshFromProfile() end)
        elseif OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshPickerList then
            pcall(function() OxedHub.OxedRingEditor:RefreshPickerList() end)
        end
        if OxedHub.OxedRing and OxedHub.OxedRing.RebuildSlices then
            pcall(function() OxedHub.OxedRing:RebuildSlices() end)
        end

    elseif scope == "toymixes" then
        db.toyMixes = db.toyMixes or {}
        local n = 0
        for name, mix in pairs(payload.toyMixes or {}) do
            db.toyMixes[name] = mix      -- replace-by-name
            n = n + 1
        end
        summary = n .. " toy mix(es)"
        if OxedHub.MacroRegistry and OxedHub.MacroRegistry.SaveMacro then
            for name, mix in pairs(payload.toyMixes or {}) do
                pcall(function() OxedHub.MacroRegistry:SaveMacro(name, mix) end)
            end
        end
        if OxedHub.Toys and OxedHub.Toys.RefreshSavedMixesList then OxedHub.Toys:RefreshSavedMixesList() end

    elseif scope == "hubs" then
        db.actionHub = db.actionHub or { activeHub = 1, hubs = {} }
        db.actionHub.hubs = db.actionHub.hubs or {}
        local n = 0
        for _, hub in ipairs(payload.hubs or {}) do
            table.insert(db.actionHub.hubs, CopyTable(hub))   -- hubs always append
            n = n + 1
        end
        summary = n .. " hub(s)"
        if OxedHub.ActionHub then
            if OxedHub.ActionHub.RefreshAllWidgets then OxedHub.ActionHub:RefreshAllWidgets() end
            if OxedHub.ActionHub.RefreshTab then OxedHub.ActionHub:RefreshTab() end
        end
    else
        print("|cffff0000Oxed Hub:|r Unknown import scope: " .. tostring(scope))
        return
    end

    self:StampImportSource(db, author, scope)
    local who = self:FormatAuthorName(author)
    print(string.format("|cff00ff00Oxed Hub:|r Imported %s from |cffffff00%s|r into profile |cffffff00%s|r.",
        summary or "data", who, targetName))
    if UI.importStatus then
        UI.importStatus:SetText(string.format("|cff00ff00Imported %s|r\nfrom %s into '%s'. Type /reload to apply.",
            summary or "data", who, targetName))
    end
    if UI.RefreshProfileDetails then UI:RefreshProfileDetails() end
end

function UI:ApplyImport(data)
    -- Route v3 scoped envelopes to the scoped importer (v1/v2 fall through).
    if type(data) == "table" and data.formatVersion == 3 and data.scope then
        return self:ApplyScopedImport(data)
    end

    local importedCount = 0
    local lastProfileName = ""
    local skippedCount = 0
    local maxProfiles = OxedHub:GetMaxProfileCount()
    local _author = data._author

    -- Character names are only unique per realm, so two people called "Paladin"
    -- on different servers would both import as "Paladin (Imported)".  Tag the
    -- copy with who it came from instead.
    local function ImportSuffix()
        local a = _author
        if type(a) == "table" and a.character and a.character ~= "" then
            local realm = a.realm and tostring(a.realm):gsub("%s+", "") or ""
            if realm ~= "" then
                return " (" .. a.character .. "-" .. realm .. ")"
            end
            return " (" .. a.character .. ")"
        end
        return " (Imported)"
    end

    -- Version 2+ supports multiple profiles
    if data.profiles then
        for name, profileData in pairs(data.profiles) do
            if OxedHub:GetProfileCount() >= maxProfiles then
                skippedCount = skippedCount + 1
            else
            local finalName = name
            -- Handle existing profile names
            if OxedHubDB.profiles[finalName] then
                local suffix = ImportSuffix()
                finalName = name .. suffix
                local counter = 1
                while OxedHubDB.profiles[finalName] do
                    finalName = name .. suffix .. " " .. counter
                    counter = counter + 1
                end
            end
            
                local ok = OxedHub:CreateProfile(finalName)
                if ok then
                    OxedHub:SwitchProfile(finalName)
                    self:_ApplySingleProfileData(OxedHub.db.profile, profileData)
                    self:StampImportSource(OxedHub.db.profile, _author, "profile")
                    importedCount = importedCount + 1
                    lastProfileName = finalName
                else
                    skippedCount = skippedCount + 1
                end
            end
        end
    else
        -- Fallback for old version 1 single-profile imports
        local profileName = data.profileName or "Imported Profile"
        local finalName = profileName
        -- Never overwrite an existing profile: keep suffixing until the name is
        -- free (the multi-profile path above does the same).
        if OxedHubDB.profiles[finalName] then
            local suffix = ImportSuffix()
            finalName = profileName .. suffix
            local counter = 1
            while OxedHubDB.profiles[finalName] do
                finalName = profileName .. suffix .. " " .. counter
                counter = counter + 1
            end
        end
        if OxedHub:GetProfileCount() >= maxProfiles then
            skippedCount = 1
        else
            local ok = OxedHub:CreateProfile(finalName)
            if ok then
                OxedHub:SwitchProfile(finalName)
                self:_ApplySingleProfileData(OxedHub.db.profile, data)
                self:StampImportSource(OxedHub.db.profile, _author, "profile")
                importedCount = 1
                lastProfileName = finalName
            else
                skippedCount = 1
            end
        end
    end

    print("|cff00ff00Oxed Hub:|r Import complete. Processed |cffffff00" .. importedCount .. "|r profiles.")
    if skippedCount > 0 then
        print("|cffffcc00Oxed Hub:|r Skipped |cffffff00" .. skippedCount .. "|r profile(s) because the maximum of |cffffff00" .. maxProfiles .. "|r profiles was reached.")
    end
    
    -- Force switch back to the last imported profile to show changes
    if lastProfileName ~= "" then
        OxedHub:SwitchProfile(lastProfileName)
    end
    
    -- Force refresh of UI components
    if UI.RefreshProfileDropdown then UI.RefreshProfileDropdown() end
    if OxedHub.ActionHub then
        if OxedHub.ActionHub.RefreshTab then OxedHub.ActionHub:RefreshTab() end
        if OxedHub.ActionHub.RefreshAllWidgets then OxedHub.ActionHub:RefreshAllWidgets() end
    end
    if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then OxedHub.Triggers:RefreshTriggersList() end
    if OxedHub.Toys then
        if OxedHub.Toys.RefreshSavedMixesList then OxedHub.Toys:RefreshSavedMixesList() end
        if OxedHub.Toys.RefreshQuickMixesGrid then OxedHub.Toys:RefreshQuickMixesGrid() end
    end
    if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshFromProfile then
        pcall(function() OxedHub.OxedRingEditor:RefreshFromProfile() end)
    end
    if OxedHub.OxedRing and OxedHub.OxedRing.RebuildSlices then
        pcall(function() OxedHub.OxedRing:RebuildSlices() end)
    end

    if UI.importStatus then
        local statusText = "|cff00ff00Import completed successfully!|r\nImported |cffffff00" .. importedCount .. "|r profiles."
        if skippedCount > 0 then
            statusText = statusText .. "\nSkipped |cffffff00" .. skippedCount .. "|r because the maximum of |cffffff00" .. maxProfiles .. "|r profiles was reached."
        end
        statusText = statusText .. "\nPlease type /reload to apply all changes."
        UI.importStatus:SetText(statusText)
    end
end

function UI:CreateImportExportPopup(titleText, isImport)
    local frameName = isImport and "OxedHubImportFrame" or "OxedHubExportFrame"
    -- Clean themed dialog (same style as the export picker / Pick Sound).
    local f = CreateFrame("Frame", frameName, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(600, 550)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScale(1.0)
    C_Timer.After(0.05, function() UI:ApplyGlobalTextSize() end)
    -- Avoid duplicate UISpecialFrames entries
    local alreadyRegistered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == frameName then alreadyRegistered = true; break end
    end
    if not alreadyRegistered then
        tinsert(UISpecialFrames, frameName)
    end

    if f.TitleText then f.TitleText:SetText(titleText) end
    f.title = f.TitleText  -- back-compat for callers that set f.title
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

    local edit
    if isImport then
        -- Import: direct EditBox filling the popup, tall and clickable
        -- Bordered container: the ScrollFrame inside it clips the EditBox, which
        -- would otherwise grow past the dialog and draw over the whole screen.
        local importBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
        importBox:SetPoint("TOPLEFT", 12, -40)
        -- Leaves room below for the target-profile row, status line and buttons.
        importBox:SetPoint("BOTTOMRIGHT", -12, 86)
        importBox:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 6, right = 6, top = 6, bottom = 6 }
        })
        importBox:SetBackdropColor(0.06, 0.06, 0.06, 1)
        importBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        importBox:SetClipsChildren(true)

        local importScroll = CreateFrame("ScrollFrame", nil, importBox)
        importScroll:SetPoint("TOPLEFT", 8, -8)
        importScroll:SetPoint("BOTTOMRIGHT", -8, 8)
        importScroll:EnableMouseWheel(true)
        importScroll:SetScript("OnMouseWheel", function(self, delta)
            self:SetVerticalScroll(math.max(0, self:GetVerticalScroll() - delta * 30))
        end)

        edit = CreateFrame("EditBox", "OxedHubImportEdit", importScroll)
        edit:SetPoint("TOPLEFT", 0, 0)
        edit:SetWidth(548)
        edit:SetHeight(3000)

        -- Clicking anywhere in the black area focuses the edit box, so pasting
        -- works even where the (fixed-width) EditBox itself isn't under the cursor.
        importBox:EnableMouse(true)
        importBox:SetScript("OnMouseDown", function()
            edit:SetFocus()
        end)
        importScroll:EnableMouse(true)
        importScroll:SetScript("OnMouseDown", function()
            edit:SetFocus()
        end)
        -- Keep the text area as wide as the container so nothing is unreachable.
        importScroll:SetScript("OnSizeChanged", function(self, width)
            if width and width > 0 then edit:SetWidth(width) end
        end)
        edit:SetTextColor(1, 1, 1, 1)
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetMaxLetters(0) -- Unlimited
        edit:SetMaxBytes(0)   -- Unlimited
        edit:SetMaxLetters(999999) -- Very high limit for modern WoW client compatibility
        edit:EnableMouse(true)
        edit:EnableKeyboard(true)
        importScroll:SetScrollChild(edit)
        edit:SetTextInsets(8, 8, 8, 8)
        edit:SetScript("OnMouseDown", function(self)
            self:SetPropagateKeyboardInput(false)
            self:SetFocus()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            self:SetPropagateKeyboardInput(true)
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            self:SetPropagateKeyboardInput(true)
        end)
    else
        -- Export: ScrollFrame + tall EditBox for scrolling long text
        local scroll = CreateFrame("ScrollFrame", nil, f)
        scroll:SetPoint("TOPLEFT", 12, -40)
        scroll:SetPoint("BOTTOMRIGHT", -12, 12)
        scroll:EnableMouseWheel(true)

        edit = CreateFrame("EditBox", "OxedHubExportEdit", scroll, "BackdropTemplate")
        edit:SetPoint("TOPLEFT", 0, 0)
        edit:SetWidth(560)
        edit:SetHeight(3000)
        edit:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        edit:SetBackdropColor(0.06, 0.06, 0.06, 1)
        edit:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        edit:SetTextColor(1, 1, 1, 1)
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetMaxLetters(0)
        edit:SetMaxBytes(0)
        edit:SetMaxLetters(EXPORT_EDITBOX_MAX_CHARS)
        edit:EnableMouse(true)
        edit:EnableKeyboard(true)
        edit:SetTextInsets(6, 6, 6, 6)
        edit:SetScript("OnMouseDown", function(self)
            self:SetPropagateKeyboardInput(false)
            self:SetFocus()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            self:SetPropagateKeyboardInput(true)
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            self:SetPropagateKeyboardInput(true)
        end)
        scroll:SetScrollChild(edit)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local newScroll = self:GetVerticalScroll() - delta * 30
            self:SetVerticalScroll(math.max(0, newScroll))
        end)
    end
    f.editBox = edit

    if isImport then
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hint:SetPoint("TOPLEFT", 12, -28)
        hint:SetText("Paste export string here — you'll see what it contains before it's applied")
        hint:SetTextColor(1, 0.82, 0, 1)

        -- Target profile for partial imports (ring / triggers / mixes / hubs).
        -- Full-profile imports create their own profiles and ignore this.
        local targetLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        targetLabel:SetPoint("BOTTOMLEFT", 14, 58)
        targetLabel:SetText("Import into:")
        targetLabel:SetTextColor(1, 0.82, 0, 1)

        local targetDropdown = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
        targetDropdown:SetPoint("LEFT", targetLabel, "RIGHT", 10, 0)
        targetDropdown:SetSize(240, 26)
        f.targetDropdown = targetDropdown

        local chunkStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chunkStatus:SetPoint("BOTTOMLEFT", 14, 20)
        chunkStatus:SetWidth(430)   -- stops short of the Import button
        chunkStatus:SetJustifyH("LEFT")
        chunkStatus:SetText("")
        f.chunkStatus = chunkStatus

        -- Default to the active profile, matching the previous behaviour.
        UI.importTargetProfile = OxedHubDB and OxedHubDB.activeProfile

        local function RefreshTargetText()
            local name = UI.importTargetProfile or (OxedHubDB and OxedHubDB.activeProfile) or "?"
            targetDropdown:OverrideText(OxedHub:GetProfileColoredName(name))
        end
        RefreshTargetText()

        targetDropdown:SetupMenu(function(_, rootDescription)
            for _, name in ipairs(OxedHub:GetProfileList()) do
                local isActive = (name == OxedHubDB.activeProfile)
                rootDescription:CreateRadio(
                    OxedHub:GetProfileColoredName(name) .. (isActive and " |cff888888(active)|r" or ""),
                    function() return UI.importTargetProfile == name end,
                    function()
                        UI.importTargetProfile = name
                        RefreshTargetText()
                    end,
                    name
                )
            end
        end)

        targetDropdown:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Where partial data goes")
            GameTooltip:AddLine("Rings, triggers, toy mixes and hubs are imported into this profile.", 1, 1, 1, true)
            GameTooltip:AddLine("Full-profile imports always create their own profile and ignore this.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        targetDropdown:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local function DoImport(importedData)
            local data = importedData
            if not data then
                local text = (edit:GetText() or ""):gsub("%s", "")
                local decompressedText, decompressErr = DecompressExportString(text)
                if decompressedText == false then
                    UI:UpdateChunkStatus(f, decompressErr or "Compressed import failed.", "error")
                    return
                elseif decompressedText then
                    text = decompressedText
                    UI:ResetImportChunks()
                    UI:UpdateChunkStatus(f, "")
                end

                local chunkInfo, chunkErr = ParseChunkedImport(text)
                if chunkInfo == false then
                    UI:UpdateChunkStatus(f, chunkErr or "Invalid import chunk.", "error")
                    return
                elseif chunkInfo then
                    local combinedText, status = UI:HandleChunkedImport(f, chunkInfo)
                    if not combinedText and status == "pending" then
                        edit:SetText("")
                        return
                    end
                    text = combinedText

                    local decompressedCombined, combinedErr = DecompressExportString(text)
                    if decompressedCombined == false then
                        UI:UpdateChunkStatus(f, combinedErr or "Compressed import failed.", "error")
                        return
                    elseif decompressedCombined then
                        text = decompressedCombined
                    end
                else
                    UI:ResetImportChunks()
                    UI:UpdateChunkStatus(f, "")
                end

                local ok, deserialized = AceSerializer:Deserialize(text)
                -- Accept v1/v2 (has .version/.profiles) AND v3 scoped envelopes (formatVersion==3).
                local looksValid = ok and type(deserialized) == "table"
                    and (deserialized.version or deserialized.formatVersion == 3 or deserialized.profiles or deserialized.profileName)
                if not looksValid then
                    print("|cffff0000Oxed Hub:|r Invalid import string. Please ensure you copied the entire string.")
                    UI:UpdateChunkStatus(f, "Import failed. Check that all parts were pasted.", "error")
                    return
                end
                data = deserialized
            end

            -- Always confirm before applying, in a dialog roomy enough to list
            -- the contents as a table.
            UI:ShowImportConfirm(data, function() f:Hide() end)
        end

        local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(importBtn)
        importBtn:SetPoint("BOTTOMRIGHT", -12, 14)
        importBtn:SetSize(120, 26)
        importBtn:SetText("Import")
        importBtn:SetScript("OnClick", DoImport)

        -- Auto-import on paste: detect text change, validate after short delay
        local importPending = false
        edit:SetScript("OnTextChanged", function(self)
            if importPending then return end
            local text = (self:GetText() or ""):gsub("%s", "")
            if #text < 20 then return end

            local decompressedText = DecompressExportString(text)
            if decompressedText then
                importPending = true
                C_Timer.After(0.3, function()
                    importPending = false
                    local currentText = (self:GetText() or ""):gsub("%s", "")
                    if #currentText >= 20 then
                        DoImport()
                    end
                end)
                return
            end

            local chunkInfo = ParseChunkedImport(text)
            if chunkInfo then
                importPending = true
                C_Timer.After(0.3, function()
                    importPending = false
                    local currentText = (self:GetText() or ""):gsub("%s", "")
                    if #currentText >= 20 then
                        DoImport()
                    end
                end)
                return
            end
            
            -- Quick validation: try to deserialize (accept v1/v2 and v3 envelopes)
            local ok, data = AceSerializer:Deserialize(text)
            if ok and type(data) == "table" and (data.version or data.formatVersion == 3 or data.profiles or data.profileName) then
                importPending = true
                -- Brief delay to ensure user finished pasting
                C_Timer.After(0.3, function()
                    importPending = false
                    -- Re-verify text hasn't changed drastically or been cleared
                    local currentText = (self:GetText() or ""):gsub("%s", "")
                    if #currentText >= 20 then
                        DoImport(data) -- Pass the data we already deserialized
                    end
                end)
            end
        end)
    else
        local prevBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(prevBtn)
        prevBtn:SetPoint("BOTTOMLEFT", 12, 14)
        prevBtn:SetSize(80, 26)
        prevBtn:SetText("Prev")
        prevBtn:Hide()
        f.prevChunkButton = prevBtn

        local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        ApplyRedButtonStyle(nextBtn)
        nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
        nextBtn:SetSize(80, 26)
        nextBtn:SetText("Next")
        nextBtn:Hide()
        f.nextChunkButton = nextBtn

        local chunkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chunkLabel:SetPoint("LEFT", nextBtn, "RIGHT", 12, 0)
        chunkLabel:SetText("")
        chunkLabel:SetTextColor(1, 0.82, 0, 1)
        chunkLabel:Hide()
        f.chunkLabel = chunkLabel

        local chunkHint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chunkHint:SetPoint("BOTTOMLEFT", 12, 44)
        chunkHint:SetWidth(450)
        chunkHint:SetJustifyH("LEFT")
        chunkHint:SetText("")
        chunkHint:SetTextColor(1, 0.82, 0, 1)
        chunkHint:Hide()
        f.chunkHint = chunkHint

        prevBtn:SetScript("OnClick", function()
            if f.currentChunkIndex and f.currentChunkIndex > 1 then
                f.currentChunkIndex = f.currentChunkIndex - 1
                UI:UpdateExportChunkDisplay()
            end
        end)

        nextBtn:SetScript("OnClick", function()
            if f.exportChunks and f.currentChunkIndex and f.currentChunkIndex < #f.exportChunks then
                f.currentChunkIndex = f.currentChunkIndex + 1
                UI:UpdateExportChunkDisplay()
            end
        end)
    end

    return f
end

local function ChunkString(str, size)
    if #str <= size then return str end
    local t = {}
    local len = #str
    for i = 1, len, size do
        t[#t + 1] = str:sub(i, i + size - 1)
    end
    return table.concat(t, "\n")
end

function UI:UpdateExportChunkDisplay()
    local frame = self.exportFrame
    if not frame or not frame.exportChunks or not frame.editBox then
        return
    end

    local index = frame.currentChunkIndex or 1
    local total = #frame.exportChunks
    frame.editBox:SetText(frame.exportChunks[index] or "")
    frame.editBox:HighlightText()
    frame.editBox:SetFocus()
    frame.editBox:SetHeight(1500)

    if total > 1 then
        frame.prevChunkButton:Show()
        frame.nextChunkButton:Show()
        frame.chunkLabel:Show()
        frame.chunkHint:Show()
        frame.chunkLabel:SetText(string.format("Part %d/%d", index, total))
        frame.chunkHint:SetText("Copy and share each part. On import, paste the parts one by one in any order.")
        frame.prevChunkButton:SetEnabled(index > 1)
        frame.nextChunkButton:SetEnabled(index < total)
    else
        frame.prevChunkButton:Hide()
        frame.nextChunkButton:Hide()
        frame.chunkLabel:Hide()
        frame.chunkHint:Hide()
        frame.chunkLabel:SetText("")
        frame.chunkHint:SetText("")
    end
end

function UI:PopulateExportFrame(exportString, titleText)
    if UI.importFrame and UI.importFrame:IsShown() then
        UI.importFrame:Hide()
    end
    if not UI.exportFrame then
        UI.exportFrame = UI:CreateImportExportPopup(titleText or "Export Profile", false)
    end

    if UI.exportFrame.title then
        UI.exportFrame.title:SetText(titleText or "Export Profile")
    end

    UI.exportFrame:Show()
    UI.exportFrame:Raise()
    local chunks = SplitExportString(exportString)
    UI.exportFrame.exportChunks = chunks
    UI.exportFrame.currentChunkIndex = 1
    UI:UpdateExportChunkDisplay()

    if #chunks > 1 then
        print("|cffffcc00Oxed Hub:|r Export was split into " .. #chunks .. " parts. Share all parts and paste them one by one when importing.")
    else
        print("|cff00ff00Oxed Hub:|r Export is ready for sharing.")
    end
end

-- Scoped export dialog: pick WHAT to export (scope), an optional target, and a
-- note, then generate the shareable string. Import uses the normal Import button
-- (ApplyImport auto-detects the scope).
function UI:ShowScopedExportFrame()
    local f = UI.scopedExportFrame
    if not f then
        f = CreateFrame("Frame", "OxedHubScopedExportFrame", UIParent, "BackdropTemplate")
        f:SetSize(460, 540)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(220)
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "OxedHubScopedExportFrame")
        f:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        f:SetBackdropBorderColor(0.95, 0.74, 0.22, 0.85)

        local title = f:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
        title:SetPoint("TOPLEFT", 18, -14)
        title:SetText("Detailed Export")
        title:SetTextColor(1, 0.82, 0, 1)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -4, -4)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local divider1 = f:CreateTexture(nil, "BORDER")
        divider1:SetPoint("TOPLEFT", 14, -38)
        divider1:SetPoint("RIGHT", -14, 0)
        divider1:SetHeight(1)
        divider1:SetColorTexture(0.58, 0.48, 0.34, 0.4)

        local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        subtitle:SetPoint("TOPLEFT", 18, -46)
        subtitle:SetText("Choose What to Export:")
        subtitle:SetTextColor(1, 0.82, 0, 1)

        -- Scrollable list of export scopes
        local scopeScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scopeScroll:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
        scopeScroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, -64)
        scopeScroll:SetHeight(180)
        if UI.StyleScrollFrame then UI:StyleScrollFrame(scopeScroll) end
        local scopeChild = CreateFrame("Frame", nil, scopeScroll)
        scopeChild:SetSize(400, 1)
        scopeScroll:SetScrollChild(scopeChild)

        f.selectedScope = f.selectedScope or UI.EXPORT_SCOPES[1]
        f.scopeRows = {}
        local rowH = 26
        for i, sc in ipairs(UI.EXPORT_SCOPES) do
            local row = CreateFrame("Button", nil, scopeChild)
            row:SetHeight(rowH)
            row:SetPoint("TOPLEFT", scopeChild, "TOPLEFT", 2, -(i - 1) * rowH)
            row:SetPoint("RIGHT", scopeChild, "RIGHT", -2, 0)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

            local sel = row:CreateTexture(nil, "BACKGROUND")
            sel:SetAllPoints()
            sel:SetColorTexture(1, 0.82, 0, 0.20)
            sel:Hide()
            row.sel = sel

            local txt = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            txt:SetPoint("LEFT", 10, 0)
            txt:SetText("|cffffd100•|r " .. sc.label)
            row.txt = txt

            row:SetScript("OnClick", function()
                f.selectedScope = sc
                UI:RefreshScopedExportRows(f)
                UI:RefreshScopedExportTarget(f)
            end)
            f.scopeRows[i] = row
        end
        scopeChild:SetHeight(#UI.EXPORT_SCOPES * rowH + 2)

        -- Scope Description Box
        local descBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
        descBox:SetPoint("TOPLEFT", scopeScroll, "BOTTOMLEFT", 0, -8)
        descBox:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        descBox:SetHeight(38)
        descBox:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        descBox:SetBackdropColor(0, 0, 0, 0.45)
        descBox:SetBackdropBorderColor(0.58, 0.48, 0.34, 0.4)

        local scopeDescText = descBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        scopeDescText:SetPoint("TOPLEFT", 8, -6)
        scopeDescText:SetPoint("BOTTOMRIGHT", -8, 6)
        scopeDescText:SetJustifyH("LEFT")
        scopeDescText:SetJustifyV("TOP")
        scopeDescText:SetText("")
        f.scopeDescText = scopeDescText

        -- Contextual target area (profile/hub dropdown or trigger checklist)
        local targetArea = CreateFrame("Frame", nil, f)
        targetArea:SetPoint("TOPLEFT", descBox, "BOTTOMLEFT", 0, -8)
        targetArea:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        targetArea:SetHeight(85)
        f.targetArea = targetArea

        -- Note field
        local noteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteLabel:SetPoint("TOPLEFT", targetArea, "BOTTOMLEFT", 0, -4)
        noteLabel:SetText("Export Note (optional):")
        noteLabel:SetTextColor(1, 0.82, 0, 1)

        local noteBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 6, -6)
        noteBox:SetSize(380, 22)
        noteBox:SetAutoFocus(false)
        noteBox:SetMaxLetters(120)
        noteBox:SetText(UI:GetExportNote() or "")
        f.noteBox = noteBox

        -- Generate button
        local genBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        if ApplyRedButtonStyle then ApplyRedButtonStyle(genBtn) end
        genBtn:SetSize(200, 26)
        genBtn:SetPoint("BOTTOM", 0, 14)
        genBtn:SetText("Generate Export String")
        genBtn:SetNormalFontObject("GameFontNormalSmall")
        genBtn:SetScript("OnClick", function() UI:GenerateScopedExport(f) end)

        UI.scopedExportFrame = f
    end

    f:Show()
    f:Raise()
    UI:RefreshScopedExportRows(f)
    UI:RefreshScopedExportTarget(f)
end

-- Highlight the selected scope row and update description.
function UI:RefreshScopedExportRows(f)
    for i, row in ipairs(f.scopeRows or {}) do
        local sc = UI.EXPORT_SCOPES[i]
        local isSel = (sc == f.selectedScope)
        row.sel:SetShown(isSel)
        if isSel then
            row.txt:SetText("|cff00ff00►|r |cffffffff" .. sc.label .. "|r")
            if f.scopeDescText then
                f.scopeDescText:SetText("|cffffd100" .. (sc.desc or "") .. "|r")
            end
        else
            row.txt:SetText("|cffffd100•|r |cffcccccc" .. sc.label .. "|r")
        end
    end
end

-- Rebuild the contextual target picker for the chosen scope.
function UI:RefreshScopedExportTarget(f)
    local area = f.targetArea
    if area._children then
        for _, c in ipairs(area._children) do c:Hide(); c:SetParent(nil) end
    end
    area._children = {}
    local function track(c) table.insert(area._children, c); return c end
    f.targetValue = nil

    local needs = f.selectedScope and f.selectedScope.needs
    if needs == "profile" then
        local lbl = track(area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
        lbl:SetPoint("TOPLEFT", 0, 0); lbl:SetText("Select Profile:")
        lbl:SetTextColor(1, 0.82, 0, 1)
        local names = {}
        for n in pairs(OxedHubDB.profiles or {}) do table.insert(names, n) end
        table.sort(names)
        f.targetValue = f.targetValue or names[1]
        local pdd = track(CreateFrame("DropdownButton", nil, area, "WowStyle1DropdownTemplate"))
        pdd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4); pdd:SetWidth(280)
        local function upd() pdd:OverrideText(OxedHub:GetProfileColoredName(f.targetValue or "—")) end
        pdd:SetupMenu(function(_, root)
            for _, n in ipairs(names) do
                root:CreateRadio(OxedHub:GetProfileColoredName(n), function() return f.targetValue == n end, function() f.targetValue = n; upd() end)
            end
        end)
        upd()
    elseif needs == "hub" then
        local lbl = track(area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
        lbl:SetPoint("TOPLEFT", 0, 0); lbl:SetText("Select Action Hub:")
        lbl:SetTextColor(1, 0.82, 0, 1)
        local profile = OxedHubDB.profiles[OxedHubDB.activeProfile]
        local hubs = (profile.actionHub and profile.actionHub.hubs) or {}
        f.targetValue = f.targetValue or (#hubs > 0 and 1 or nil)
        local hdd = track(CreateFrame("DropdownButton", nil, area, "WowStyle1DropdownTemplate"))
        hdd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4); hdd:SetWidth(280)
        local function hubName(i) local h = hubs[i]; return (h and h.name) or ("Hub " .. i) end
        local function upd() hdd:OverrideText(f.targetValue and hubName(f.targetValue) or "—") end
        hdd:SetupMenu(function(_, root)
            for i = 1, #hubs do
                root:CreateRadio(hubName(i), function() return f.targetValue == i end, function() f.targetValue = i; upd() end)
            end
        end)
        upd()
    elseif needs == "triggers" then
        local lbl = track(area:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
        lbl:SetPoint("TOPLEFT", 0, 0); lbl:SetText("Tick triggers to include in export:")
        lbl:SetTextColor(1, 0.82, 0, 1)
        local scroll = track(CreateFrame("ScrollFrame", nil, area, "UIPanelScrollFrameTemplate"))
        scroll:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -26, 0)
        if UI.StyleScrollFrame then UI:StyleScrollFrame(scroll) end
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(320, 1)
        scroll:SetScrollChild(child)
        f.triggerChecks = {}
        local profile = OxedHubDB.profiles[OxedHubDB.activeProfile]
        local ids = {}
        for id in pairs(profile.triggers or {}) do table.insert(ids, id) end
        table.sort(ids, function(a, b)
            return (profile.triggers[a].name or a) < (profile.triggers[b].name or b)
        end)
        local y = 0
        for _, id in ipairs(ids) do
            local cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 0, -y)
            cb:SetSize(20, 20)
            cb:SetChecked(true)
            local t = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            t:SetText(profile.triggers[id].name or id)
            f.triggerChecks[id] = cb
            y = y + 22
        end
        child:SetHeight(math.max(y, 1))
    end
end

-- Build the string for the current scope selection and show it.
function UI:GenerateScopedExport(f)
    local sc = f.selectedScope
    local opts = { note = f.noteBox and f.noteBox:GetText() }
    if sc.needs == "profile" then
        opts.profileNames = f.targetValue and { f.targetValue } or nil
    elseif sc.needs == "hub" then
        opts.hubIndex = f.targetValue
    elseif sc.needs == "triggers" then
        local ids = {}
        for id, cb in pairs(f.triggerChecks or {}) do if cb:GetChecked() then table.insert(ids, id) end end
        opts.triggerIDs = ids
    end

    local str, err = UI:BuildScopedExportString(sc.scope, opts)
    if str then
        f:Hide()
        -- reuse the standard export-string window (handles copy + chunking)
        UI:PopulateExportFrame(str, "Export: " .. sc.label)
    else
        print("|cffff0000Oxed Hub:|r " .. (err or "Export failed."))
    end
end

-- Read-only text dialog used by the Debug page. Deliberately not
-- CreateImportExportPopup: that helper hardcodes its global frame name, so a
-- third caller would clobber the export frame's global.
function UI:ShowCopyDialog(text)
    if not UI.copyDialog then
        local f = CreateFrame("Frame", "OxedHubCopyDialog", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(620, 520)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.TitleText then f.TitleText:SetText(L["DEBUG_REPORT_TITLE"] or "OxedHub Debug Report") end
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
        tinsert(UISpecialFrames, "OxedHubCopyDialog")

        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
        hint:SetText(L["DEBUG_COPY_HINT"] or "Press Ctrl+C to copy.")

        local scroll = CreateFrame("ScrollFrame", "OxedHubCopyDialogScroll", f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
        scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 16)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(560)
        edit:SetAutoFocus(false)
        -- 0 means unlimited: a long session's report easily passes the default cap.
        edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        -- Keep it read-only without disabling it, or Ctrl+C would stop working.
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self.sourceText or "") end
        end)
        scroll:SetScrollChild(edit)

        f.editBox = edit
        UI.copyDialog = f
    end

    local f = UI.copyDialog
    f.editBox.sourceText = text
    f.editBox:SetText(text)
    f:Show()
    f:Raise()
    f.editBox:HighlightText()
    f.editBox:SetFocus()
end

function UI:ShowExportFrame()
    if UI.exportSelectionFrame and UI.exportSelectionFrame:IsShown() then
        UI.exportSelectionFrame:Hide()
    end

    if UI.importFrame and UI.importFrame:IsShown() then
        UI.importFrame:Hide()
    end

    if not UI.exportFrame then
        UI.exportFrame = UI:CreateImportExportPopup("Export Active Profile", false)
    elseif UI.exportFrame.title then
        UI.exportFrame.title:SetText("Export Active Profile")
    end

    UI.exportFrame:Show()
    UI.exportFrame:Raise()
    UI.exportFrame.editBox:SetText("Generating export string... please wait.")
    UI.exportFrame.exportChunks = nil
    UI.exportFrame.currentChunkIndex = 1

    C_Timer.After(0.1, function()
        local exportString, err = UI:BuildExportString(nil, false)
        if exportString then
            UI:PopulateExportFrame(exportString, "Export Active Profile")
            UI:WarnAboutUntransferableSounds()
        else
            UI.exportFrame.editBox:SetText(err or "Error generating export string. Data may be too large or corrupted.")
        end
    end)
end

-- Sounds whose audio lives in the player's own OxedHub_CustomMedia folder can't
-- travel inside an export string — only the definition does. Tell the exporter
-- so they can swap to bundled sounds or send the files alongside.
function UI:WarnAboutUntransferableSounds()
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return end

    local refs = self:CollectSoundReferences(p)
    local shared = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds()
        or p.customSounds or {}

    local names = {}
    for id in pairs(refs) do
        local def = shared[id]
        local path = def and def.filePath
        -- Anything outside the addon's own Media folder won't exist for others.
        if type(path) == "string" and path:find("OxedHub_CustomMedia", 1, true) then
            table.insert(names, def.name or id)
        end
    end

    if #names == 0 then return end
    table.sort(names)

    local shown = {}
    for i = 1, math.min(#names, 5) do table.insert(shown, names[i]) end
    local extra = (#names > 5) and (" and " .. (#names - 5) .. " more") or ""

    print(("|cffffcc00Oxed Hub:|r %d sound(s) in this export use your own files "
        .. "(%s%s). Whoever imports it won't have those audio files — send them the "
        .. "files too, or swap to built-in sounds."):format(#names, table.concat(shown, ", "), extra))
end

function UI:CreateExportSelectionFrame()
    local frameName = "OxedHubExportSelectionFrame"
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    f:SetSize(420, 460)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    ApplyOrnateFrame(f, nil, 0.96)
    f:SetScale(1.0)
    C_Timer.After(0.05, function() UI:ApplyGlobalTextSize() end)
    -- Avoid duplicate UISpecialFrames entries
    local alreadyRegistered = false
    for _, name in ipairs(UISpecialFrames) do
        if name == frameName then alreadyRegistered = true; break end
    end
    if not alreadyRegistered then
        tinsert(UISpecialFrames, frameName)
    end

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("Select Profiles to Export")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOPLEFT", 16, -42)
    hint:SetWidth(388)
    hint:SetJustifyH("LEFT")
    hint:SetText("Select the profiles you want to include. The final export must stay within 500000 characters.")
    hint:SetTextColor(1, 0.82, 0, 1)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -76)
    scroll:SetPoint("BOTTOMRIGHT", -34, 110)
    StyleScrollFrame(scroll)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(360, 1)
    scroll:SetScrollChild(content)
    f.profileListContent = content

    local estimateLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    estimateLabel:SetPoint("BOTTOMLEFT", 16, 74)
    estimateLabel:SetText("")
    f.estimateLabel = estimateLabel

    local statusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", estimateLabel, "BOTTOMLEFT", 0, -6)
    statusLabel:SetWidth(388)
    statusLabel:SetJustifyH("LEFT")
    statusLabel:SetText("")
    f.statusLabel = statusLabel

    local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(exportBtn)
    exportBtn:SetPoint("BOTTOMRIGHT", -16, 16)
    exportBtn:SetSize(130, 26)
    exportBtn:SetText("Export Selected")
    exportBtn:SetEnabled(false)
    f.exportSelectedButton = exportBtn

    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(cancelBtn)
    cancelBtn:SetPoint("RIGHT", exportBtn, "LEFT", -8, 0)
    cancelBtn:SetSize(90, 26)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() f:Hide() end)

    f.profileCheckboxes = {}
    f.selectedProfiles = {}

    return f
end

function UI:GetSelectedProfileNames()
    local selected = {}
    if not self.exportSelectionFrame or not self.exportSelectionFrame.selectedProfiles then
        return selected
    end

    for _, name in ipairs(OxedHub:GetProfileList()) do
        if self.exportSelectionFrame.selectedProfiles[name] then
            selected[#selected + 1] = name
        end
    end

    return selected
end

function UI:RefreshExportSelectionEstimate()
    local frame = self.exportSelectionFrame
    if not frame then
        return
    end

    local selectedProfiles = self:GetSelectedProfileNames()
    if #selectedProfiles == 0 then
        frame.pendingExportString = nil
        frame.estimateLabel:SetText("Estimated export size: 0 / " .. EXPORT_MAX_CHARS)
        frame.statusLabel:SetText("|cffffcc00Select at least one profile to export.|r")
        frame.exportSelectedButton:SetEnabled(false)
        return
    end

    frame.estimateLabel:SetText("Calculating export size...")
    frame.statusLabel:SetText("")
    local size, estimateErr = self:GetExportEstimate(selectedProfiles, true)
    if not size then
        frame.pendingExportString = nil
        frame.estimateLabel:SetText("Estimated export size: unavailable")
        frame.statusLabel:SetText("|cffff0000" .. (estimateErr or "Failed to calculate export size.") .. "|r")
        frame.exportSelectedButton:SetEnabled(false)
        return
    end

    frame.estimateLabel:SetText(string.format("Estimated export size: %d / %d", size, EXPORT_MAX_CHARS))
    if size <= EXPORT_MAX_CHARS then
        local exportString, err = self:BuildExportString(selectedProfiles, true)
        if exportString then
            frame.pendingExportString = exportString
            frame.statusLabel:SetText(string.format("|cff00ff00Ready to export %d profile(s).|r", #selectedProfiles))
            frame.exportSelectedButton:SetEnabled(true)
            return
        end

        frame.pendingExportString = nil
        frame.statusLabel:SetText("|cffff0000" .. (err or "Export is too large.") .. "|r")
        frame.exportSelectedButton:SetEnabled(false)
    else
        frame.pendingExportString = nil
        frame.statusLabel:SetText("|cffff0000Export is too large. Deselect some profiles before exporting.|r")
        frame.exportSelectedButton:SetEnabled(false)
    end
end

function UI:RefreshExportSelectionList()
    local frame = self.exportSelectionFrame
    if not frame then
        return
    end

    local profiles = OxedHub:GetProfileList()
    local previous = frame.profileCheckboxes or {}
    for _, checkbox in ipairs(previous) do
        checkbox:Hide()
    end
    frame.profileCheckboxes = {}

    local anchor
    for index, name in ipairs(profiles) do
        local checkbox = previous[index]
        if not checkbox then
            checkbox = CreateFrame("CheckButton", nil, frame.profileListContent, "UICheckButtonTemplate")
            previous[index] = checkbox
        end

        checkbox:SetParent(frame.profileListContent)
        checkbox:ClearAllPoints()
        if anchor then
            checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
        else
            checkbox:SetPoint("TOPLEFT", 0, -4)
        end
        if checkbox.text then
            checkbox.text:SetText(name)
            checkbox.text:SetTextColor(1, 1, 1, 1)
        end
        checkbox:SetChecked(frame.selectedProfiles[name] == true)
        checkbox:SetScript("OnClick", function(self)
            frame.selectedProfiles[name] = self:GetChecked() == true
            UI:RefreshExportSelectionEstimate()
        end)
        checkbox:Show()

        frame.profileCheckboxes[#frame.profileCheckboxes + 1] = checkbox
        anchor = checkbox
    end

    local height = math.max(1, (#profiles * 28) + 12)
    frame.profileListContent:SetHeight(height)
end

function UI:ShowExportSelectionFrame()
    if self.importFrame and self.importFrame:IsShown() then
        self.importFrame:Hide()
    end
    if self.exportFrame and self.exportFrame:IsShown() then
        self.exportFrame:Hide()
    end
    if not self.exportSelectionFrame then
        self.exportSelectionFrame = self:CreateExportSelectionFrame()
        self.exportSelectionFrame.exportSelectedButton:SetScript("OnClick", function()
            local exportString = self.exportSelectionFrame.pendingExportString
            if not exportString then
                return
            end
            self.exportSelectionFrame:Hide()
            self:PopulateExportFrame(exportString, "Export Selected Profiles")
        end)
    end

    local frame = self.exportSelectionFrame
    frame.selectedProfiles = {}
    frame.pendingExportString = nil
    local activeProfile = OxedHubDB.activeProfile
    if activeProfile and OxedHubDB.profiles and OxedHubDB.profiles[activeProfile] then
        frame.selectedProfiles[activeProfile] = true
    end

    self:RefreshExportSelectionList()
    self:RefreshExportSelectionEstimate()
    frame:Show()
    frame:Raise()
end

function UI:ShowImportFrame()
    if UI.exportFrame and UI.exportFrame:IsShown() then
        UI.exportFrame:Hide()
    end
    if UI.exportSelectionFrame and UI.exportSelectionFrame:IsShown() then
        UI.exportSelectionFrame:Hide()
    end
    UI:ResetImportChunks()
    -- Always recreate Import frame to avoid cached state issues
    if UI.importFrame then
        UI.importFrame:Hide()
        UI.importFrame = nil
    end
    UI.importFrame = UI:CreateImportExportPopup("Import Profile", true)
    UI.importFrame.editBox:SetText("")
    UI.importFrame:Show()
    UI.importFrame:Raise()
    -- Focus the paste area so Ctrl+V works without clicking first.
    C_Timer.After(0.05, function()
        if UI.importFrame and UI.importFrame:IsShown() and UI.importFrame.editBox then
            UI.importFrame.editBox:SetFocus()
        end
    end)
end

-- Global key listener for ring keybinds
local keyListener = nil
local heldKeys = {}

function UI:UpdateKeybindListener()
    if not keyListener then
        keyListener = CreateFrame("Frame", "OxedHubKeyListener", UIParent)
        keyListener:SetSize(1, 1)
        keyListener:SetPoint("TOPLEFT", 0, 0)
        keyListener:Show()
        keyListener:EnableKeyboard(true)
        if not InCombatLockdown() then
            keyListener:SetPropagateKeyboardInput(true)
        end

        keyListener:SetScript("OnKeyDown", function(self, key)
            local focus = GetCurrentKeyBoardFocus()
            if focus and (type(focus.IsVisible) == "function" and focus:IsVisible() or focus.IsShown and focus:IsShown()) then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(true)
                end
                return
            end

            if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.settings then
                if not InCombatLockdown() then
                    self:SetPropagateKeyboardInput(true)
                end
                return
            end

            local binds = OxedHub.db.profile.settings.keybinds or {}
            local matched = false

            for ringKey, cfg in pairs(binds) do
                if cfg and cfg.key == key then
                    matched = true
                end
            end

            if not InCombatLockdown() then
                if matched then
                    self:SetPropagateKeyboardInput(false)
                else
                    self:SetPropagateKeyboardInput(true)
                end
            end
        end)

        keyListener:SetScript("OnKeyUp", function(self, key)
            if heldKeys[key] then
                heldKeys[key] = nil
            end
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(true)
            end
        end)
    end
end

-- Initialize key listener on load
C_Timer.After(1, function()
    UI:UpdateKeybindListener()
end)


