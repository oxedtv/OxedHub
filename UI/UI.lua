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
                        local displayName = OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(name) or name
                        rootDescription:CreateRadio(
                            displayName,
                            function() return OxedHub:GetActiveProfileName() == name end,
                            function()
                                OxedHub:SwitchProfile(name)
                                RefreshProfileDropdown()
                            end
                        )
                    end
                end
            end)
            -- Set button label to active profile name
            if profileDropdown.SetText then
                local displayName = OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(activeName) or activeName
                profileDropdown:SetText(displayName)
            end
        else
            -- Legacy UIDropDownMenuTemplate fallback
            UIDropDownMenu_SetWidth(profileDropdown, 150)
            UIDropDownMenu_SetText(profileDropdown, activeName)
            UIDropDownMenu_Initialize(profileDropdown, function(self, level)
                if OxedHub and OxedHub.GetProfileList then
                    for _, name in ipairs(OxedHub:GetProfileList()) do
                        local info = UIDropDownMenu_CreateInfo()
                        info.text = OxedHub.GetProfileDisplayName and OxedHub:GetProfileDisplayName(name) or name
                        info.checked = (name == activeName)
                        info.func = function()
                            OxedHub:SwitchProfile(name)
                            UIDropDownMenu_SetText(profileDropdown, name)
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
    local numCards = 4
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
    -- CARD 1: CHARACTER SHOWCASE
    -- ───────────────────────────────────────────────────────────────
    local showcaseTitle = card1:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    showcaseTitle:SetPoint("TOP", card1, "TOP", 0, -12)
    showcaseTitle:SetTextColor(1, 0.82, 0, 1)
    showcaseTitle:SetText(L["SHOWCASE_TITLE"])
    local fName, fHeight, fFlags = showcaseTitle:GetFont()
    if fName then showcaseTitle:SetFont(fName, fHeight * 1.1, fFlags) end

    local showcaseSubtitle = card1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    showcaseSubtitle:SetPoint("TOP", showcaseTitle, "BOTTOM", 0, -4)
    showcaseSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    showcaseSubtitle:SetText(L["SHOWCASE_SUBTITLE"])

    -- 3D Player Model
    local modelFrame = CreateFrame("PlayerModel", nil, card1)
    modelFrame:SetSize(200, 250)
    modelFrame:SetPoint("CENTER", card1, "CENTER", -230, -15)
    modelFrame:SetUnit("player")
    modelFrame:SetRotation(math.rad(-15))
    modelFrame:SetPortraitZoom(0)
    modelFrame:SetCamDistanceScale(1.2)
    modelFrame:SetFrameLevel(card1:GetFrameLevel() + 2)

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
        slot:SetFrameLevel(card1:GetFrameLevel() + 5)
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
    local animContainer = CreateFrame("Frame", nil, card1)
    animContainer:SetSize(220, 260)
    animContainer:SetPoint("CENTER", card1, "CENTER", 320, -10)
    animContainer:SetFrameLevel(card1:GetFrameLevel() + 3)
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
    local slotTL = CreateSlotButton(card1, SLOT_DEFS[1], "TOPRIGHT",    -170, -40)   -- Top-Left of model
    local slotTR = CreateSlotButton(card1, SLOT_DEFS[2], "TOPLEFT",      170, -40)   -- Top-Right of model
    local slotBL = CreateSlotButton(card1, SLOT_DEFS[3], "BOTTOMRIGHT", -170,  40)   -- Bottom-Left of model
    local slotBR = CreateSlotButton(card1, SLOT_DEFS[4], "BOTTOMLEFT",   170,  40)   -- Bottom-Right of model

    -- Launch Button (centered in the card between model and animation area)
    launchBtn = CreateFrame("Button", nil, card1, "UIPanelButtonTemplate")
    launchBtn:SetSize(140, 36)
    launchBtn:SetPoint("CENTER", card1, "CENTER", 125, -15)
    launchBtn:SetFrameLevel(card1:GetFrameLevel() + 5)
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
    -- CARD 2: QUICK START GUIDE
    -- ───────────────────────────────────────────────────────────────
    local guideTitle = card2:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    guideTitle:SetPoint("TOP", card2, "TOP", 0, -12)
    guideTitle:SetTextColor(1, 0.82, 0, 1)
    guideTitle:SetText(L["GUIDE_TITLE"])
    local gName, gHeight, gFlags = guideTitle:GetFont()
    if gName then guideTitle:SetFont(gName, gHeight * 1.1, gFlags) end

    local guideSubtitle = card2:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
        local col = CreateFrame("Frame", nil, card2, "BackdropTemplate")
        col:SetSize(280, 215)
        col:SetPoint("CENTER", card2, "CENTER", (idx - 2) * 310, -15)
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
    -- CARD 3: ACTIONHUB GUIDE
    -- ───────────────────────────────────────────────────────────────
    local ahTitle = card3:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    ahTitle:SetPoint("TOP", card3, "TOP", 0, -12)
    ahTitle:SetTextColor(1, 0.82, 0, 1)
    ahTitle:SetText(L["AH_GUIDE_TITLE"])
    local aName, aHeight, aFlags = ahTitle:GetFont()
    if aName then ahTitle:SetFont(aName, aHeight * 1.1, aFlags) end

    local ahSubtitle = card3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ahSubtitle:SetPoint("TOP", ahTitle, "BOTTOM", 0, -4)
    ahSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    ahSubtitle:SetText(L["AH_GUIDE_SUBTITLE"])

    -- Left panel: Explanations
    local ahLeftPanel = CreateFrame("Frame", nil, card3, "BackdropTemplate")
    ahLeftPanel:SetSize(510, 190)
    ahLeftPanel:SetPoint("TOPLEFT", card3, "TOPLEFT", 30, -70)
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
    local previewRing = CreateFrame("Frame", nil, card3)
    previewRing:SetSize(300, 300)
    previewRing:SetPoint("CENTER", card3, "TOPLEFT", 810, -155)

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
    -- CARD 4: STATUS & QUICK COMMANDS
    -- ───────────────────────────────────────────────────────────────
    -- ───────────────────────────────────────────────────────────────
    -- CARD 4: OXEDRING GUIDE
    -- ───────────────────────────────────────────────────────────────
    local oxedRingTitle = card4:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    oxedRingTitle:SetPoint("TOP", card4, "TOP", 0, -12)
    oxedRingTitle:SetTextColor(1, 0.82, 0, 1)
    oxedRingTitle:SetText(L["OR_GUIDE_TITLE"])
    local oName, oHeight, oFlags = oxedRingTitle:GetFont()
    if oName then oxedRingTitle:SetFont(oName, oHeight * 1.1, oFlags) end

    local oxedRingSubtitle = card4:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    oxedRingSubtitle:SetPoint("TOP", oxedRingTitle, "BOTTOM", 0, -4)
    oxedRingSubtitle:SetTextColor(0.22, 0.18, 0.17, 1)
    oxedRingSubtitle:SetText(L["OR_GUIDE_SUBTITLE"])

    -- Left panel: Explanations
    local orLeftPanel = CreateFrame("Frame", nil, card4, "BackdropTemplate")
    orLeftPanel:SetSize(510, 190)
    orLeftPanel:SetPoint("TOPLEFT", card4, "TOPLEFT", 30, -70)
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
    local previewRing2 = CreateFrame("Frame", nil, card4)
    previewRing2:SetSize(240, 240)
    previewRing2:SetPoint("CENTER", card4, "TOPLEFT", 740, -155)

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

        if idx == 3 and UI.UpdateActionHubCardState then
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
        
        -- If sliding back to Card 1, show model immediately so it slides in nicely
        if idx == 1 then
            modelFrame:Show()
        end

        if smooth then
            sliderScroll:SetScript("OnUpdate", function(self, elapsed)
                local cur = self:GetHorizontalScroll()
                local diff = targetScroll - cur
                if math.abs(diff) < 1 then
                    self:SetHorizontalScroll(targetScroll)
                    self:SetScript("OnUpdate", nil)
                    -- If we completed slide away from Card 1, hide the 3D model frame to prevent clipping issues
                    if activeCardIndex ~= 1 then
                        modelFrame:Hide()
                    end
                else
                    self:SetHorizontalScroll(cur + diff * scrollSpeed * elapsed)
                end
            end)
        else
            sliderScroll:SetScript("OnUpdate", nil)
            sliderScroll:SetHorizontalScroll(targetScroll)
            if idx ~= 1 then
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
    tab.stats = { stat1, stat2, stat3, stat4 }
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

                row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.zoneText:SetPoint("LEFT", row.actionsText, "RIGHT", 12, 0)
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
                row.zoneDivider = CreateColumnLine(row.zoneText)

                row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
                row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                row.deleteBtn:SetSize(24, 24)

                row.enabledCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.enabledCheck:SetPoint("RIGHT", row.deleteBtn, "LEFT", -20, 0)
                row.enabledCheck:SetSize(22, 22)

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
            row.zoneDivider:SetColorTexture(0.58, 0.48, 0.34, elementData.isHeader and 0 or 0.18)
            row.nameText:SetText(elementData.name or "")
            row.eventText:SetText(elementData.event or "")
            row.actionsText:SetText(elementData.actions or "")
            row.zoneText:SetText(elementData.zone or "")
            
            row.deleteBtn:SetShown((not elementData.isHeader) and elementData.id ~= nil)
            row.deleteBtn:SetScript("OnClick", function()
                if elementData.id then
                    OxedHub.Triggers:DeleteTrigger(elementData.id)
                end
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
            else
                row.nameText:SetTextColor(1, 0.82, 0.12, 1)
                row.eventText:SetTextColor(0.88, 0.84, 0.74, 1)
                row.actionsText:SetTextColor(0.62, 0.84, 1, 1)
                row.zoneText:SetTextColor(0.90, 0.76, 0.36, 1)
                if row.enabledHeaderText then
                    row.enabledHeaderText:Hide()
                end
                if row.deleteHeaderText then
                    row.deleteHeaderText:Hide()
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
    local subTabNames = { "Mixer", "Library" }
    local xOffset = 25

    for i, name in ipairs(subTabNames) do
        local btn = CreateFrame("Button", nil, subTabs, "UIPanelButtonTemplate")
        btn:SetSize(80, 25)
        btn:SetPoint("TOPLEFT", subTabs, "TOPLEFT", xOffset, 0)
        local label
        if name == "Mixer" then label = L["TOYS_SUBTAB_MIXER"]
        elseif name == "Library" then label = L["TOYS_SUBTAB_LIBRARY"]
        else label = L["TOYS_SUBTAB_ICONS"] end
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

    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubSettingsScrollFrame", tab, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", tab, "TOPLEFT", THEMED_FRAME_INSETS.left, -THEMED_FRAME_INSETS.top)
    scrollFrame:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -THEMED_FRAME_INSETS.right, THEMED_FRAME_INSETS.bottom)
    StyleScrollFrame(scrollFrame)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    local scrollWidth = scrollFrame:GetWidth()
    if scrollWidth <= 0 then scrollWidth = 600 end -- Fallback for initial load
    scrollChild:SetWidth(scrollWidth)
    scrollChild:SetHeight(920) 
    scrollFrame:SetScrollChild(scrollChild)
    tab.scrollChild = scrollChild

    -- Title with gold color
    local title = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, -15)
    title:SetText(L["SETTINGS_TITLE"])
    title:Hide()

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

    -- ── Profile Switcher ─────────────────────────────────────────────────
    local profilesSection = CreateSettingsSectionHeader(scrollChild, skipDelConfirmDesc, "BOTTOMLEFT", -28, -30, L["SETTINGS_SECTION_PROFILES"])

    local profileLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", profilesSection, "BOTTOMLEFT", 18, -10)
    profileLabel:SetText(L["SETTINGS_PROFILES_LABEL"])
    profileLabel:SetTextColor(1, 0.82, 0, 1)

    local profileDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    profileDesc:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -4)
    profileDesc:SetText(L["SETTINGS_PROFILES_DESC"])

    local autoSwitchToggle = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
    autoSwitchToggle:SetPoint("TOPLEFT", profileDesc, "BOTTOMLEFT", -4, -8)
    autoSwitchToggle:SetSize(26, 26)
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
    autoSwitchDesc:SetText(L["SETTINGS_PROFILES_AUTO_DESC"])

    -- Active profile dropdown
    local activeLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeLabel:SetPoint("TOP", autoSwitchDesc, "BOTTOM", 0, -14)
    activeLabel:SetPoint("LEFT", profileLabel, "LEFT", 0, 0)
    activeLabel:SetText(L["SETTINGS_PROFILES_ACTIVE"])
    activeLabel:SetTextColor(1, 1, 1, 1)

    local profileDropdown = CreateFrame("DropdownButton", "OxedHubProfileDropdown", scrollChild, "WowStyle1DropdownTemplate")
    profileDropdown:SetPoint("LEFT", activeLabel, "RIGHT", 8, 0)
    profileDropdown:SetSize(210, 22)

    local selectedCreateClassToken = OxedHub.GetPlayerClassToken and OxedHub:GetPlayerClassToken() or false

    local function RefreshProfileDropdown()
        local activeName = OxedHub:GetActiveProfileName()
        profileDropdown:OverrideText(OxedHub:GetProfileColoredName(activeName))
        profileDropdown:SetupMenu(function(dropdown, rootDescription)
            local profiles = OxedHub:GetProfileList()
            for _, name in ipairs(profiles) do
                rootDescription:CreateRadio(
                    OxedHub:GetProfileColoredName(name),
                    function() return name == OxedHub:GetActiveProfileName() end,
                    function()
                        OxedHub:SwitchProfile(name)
                    end,
                    name
                )
            end
        end)

    end
    UI.RefreshProfileDropdown = RefreshProfileDropdown
    RefreshProfileDropdown()

    -- New profile row
    local newProfileInput = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    newProfileInput:SetSize(150, 22)
    newProfileInput:SetPoint("TOP", activeLabel, "BOTTOM", 0, -14)
    newProfileInput:SetPoint("LEFT", profileLabel, "LEFT", 0, 0)
    newProfileInput:SetAutoFocus(false)
    newProfileInput:SetMaxLetters(30)
    newProfileInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local createClassDropdown = CreateFrame("DropdownButton", "OxedHubCreateClassDropdown", scrollChild, "WowStyle1DropdownTemplate")
    createClassDropdown:SetPoint("LEFT", newProfileInput, "RIGHT", 8, 0)
    createClassDropdown:SetSize(140, 22)
    SetupClassDropdown(
        createClassDropdown,
        function()
            return selectedCreateClassToken
        end,
        function(token)
            selectedCreateClassToken = token
        end
    )

    local createBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(createBtn)
    createBtn:SetSize(70, 22)
    createBtn:SetPoint("LEFT", createClassDropdown, "RIGHT", 8, 0)
    createBtn:SetText(L["SETTINGS_BTN_CREATE"])
    createBtn:SetNormalFontObject("GameFontNormalSmall")

    -- Add info tooltip button next to Create button
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
            RefreshProfileDropdown()
        elseif reason == "max_profiles" then
            print("|cffff0000Oxed Hub:|r Maximum of |cffffff00" .. OxedHub:GetMaxProfileCount() .. "|r profiles reached.")
        else
            print("|cffff0000Oxed Hub:|r Profile name already exists or is invalid.")
        end
    end)
    newProfileInput:SetScript("OnEnterPressed", function(self)
        createBtn:Click()
    end)

    -- Copy / Rename / Delete row
    local copyBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(copyBtn)
    copyBtn:SetSize(70, 22)
    copyBtn:SetPoint("TOP", newProfileInput, "BOTTOM", 0, -10)
    copyBtn:SetPoint("LEFT", profileLabel, "LEFT", 0, 0)
    copyBtn:SetText(L["SETTINGS_BTN_COPY"])
    copyBtn:SetNormalFontObject("GameFontNormalSmall")
    copyBtn:SetScript("OnClick", function()
        local src = OxedHub:GetActiveProfileName()
        local dest = newProfileInput:GetText():match("^%s*(.-)%s*$")
        if dest == "" then
            print("|cffff0000Oxed Hub:|r Type a name in the text field first, then click Copy.")
            return
        end
        local ok, reason = OxedHub:CopyProfile(src, dest, selectedCreateClassToken)
        if ok then
            print("|cff00ff00Oxed Hub:|r Copied |cffffff00" .. src .. "|r to |cffffff00" .. dest .. "|r.")
            newProfileInput:SetText("")
            newProfileInput:ClearFocus()
            RefreshProfileDropdown()
        elseif reason == "max_profiles" then
            print("|cffff0000Oxed Hub:|r Maximum of |cffffff00" .. OxedHub:GetMaxProfileCount() .. "|r profiles reached.")
        else
            print("|cffff0000Oxed Hub:|r Could not copy. Name already exists or is invalid.")
        end
    end)

    local renameBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(renameBtn)
    renameBtn:SetSize(70, 22)
    renameBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
    renameBtn:SetText(L["SETTINGS_BTN_RENAME"])
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
            RefreshProfileDropdown()
        else
            print("|cffff0000Oxed Hub:|r Could not rename. Name already exists or is invalid.")
        end
    end)

    local deleteBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(deleteBtn)
    deleteBtn:SetSize(70, 22)
    deleteBtn:SetPoint("LEFT", renameBtn, "RIGHT", 8, 0)
    deleteBtn:SetText(L["SETTINGS_BTN_DELETE"])
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
                -- Switch to another profile first
                for _, name in ipairs(profiles) do
                    if name ~= activeName then
                        OxedHub:SwitchProfile(name)
                        C_Timer.After(0.05, function()
                            OxedHub:DeleteProfile(activeName)
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

    -- ── Export / Import section ───────────────────────────────────────────
    local exportSection = CreateSettingsSectionHeader(scrollChild, copyBtn, "BOTTOMLEFT", -18, -32, L["SETTINGS_SECTION_EXPORT"])

    local exportImportLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    exportImportLabel:SetPoint("TOPLEFT", exportSection, "BOTTOMLEFT", 18, -10)
    exportImportLabel:SetText(L["SETTINGS_EXPORT_LABEL"])
    exportImportLabel:SetTextColor(1, 0.82, 0, 1)

    local exportBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(exportBtn)
    exportBtn:SetPoint("TOPLEFT", exportImportLabel, "BOTTOMLEFT", 0, -10)
    exportBtn:SetSize(110, 26)
    exportBtn:SetText(L["SETTINGS_BTN_EXPORT_ACTIVE"])
    exportBtn:SetScript("OnClick", function()
        UI:ShowExportFrame()
    end)

    local exportAllBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(exportAllBtn)
    exportAllBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    exportAllBtn:SetSize(100, 26)
    exportAllBtn:SetText(L["SETTINGS_BTN_EXPORT_ALL"])
    exportAllBtn:SetScript("OnClick", function()
        UI:ShowExportSelectionFrame()
    end)

    local importBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
    ApplyRedButtonStyle(importBtn)
    importBtn:SetPoint("LEFT", exportAllBtn, "RIGHT", 10, 0)
    importBtn:SetSize(100, 26)
    importBtn:SetText(L["SETTINGS_BTN_IMPORT"])
    importBtn:SetScript("OnClick", function()
        UI:ShowImportFrame()
    end)
    
    local importStatus = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importStatus:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -15)
    importStatus:SetWidth(400)
    importStatus:SetJustifyH("LEFT")
    importStatus:SetJustifyV("TOP")
    importStatus:SetText("")
    UI.importStatus = importStatus

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

    for _, name in ipairs({"Mixer", "Library", "QuickMixes"}) do
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
        if subTabName == "Mixer" then
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
    elseif subTabName == "QuickMixes" then
        if OxedHub.Toys and OxedHub.Toys.ShowQuickMixesTab then
            OxedHub.Toys:ShowQuickMixesTab(panel)
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

-- Show main window
function UI:ShowMainWindow()
    if mainFrame then
        mainFrame:Show()
        OxedHub.db.profile.settings.mainWindowVisible = true
    end
end

-- Hide main window
function UI:HideMainWindow()
    if mainFrame then
        mainFrame:Hide()
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

local function BuildProfileExportPayload(profileName, db)
    return {
        version = 1,
        profileName = profileName,
        metadata = db.metadata,
        triggers = db.triggers,
        customSounds = db.customSounds,
        animations = db.animations,
        emotionMappings = db.emotionMappings,
        chatTemplates = db.chatTemplates,
        settings = db.settings,
        actionHub = db.actionHub,
        toyMixes = db.toyMixes,
    }
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

function UI:ValidateImport(data)
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

function UI:_ApplySingleProfileData(db, data)
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
    if OxedHub.Core and OxedHub.Core.MigrateLegacySoundPathsAndIds then
        OxedHub.Core:MigrateLegacySoundPathsAndIds()
    end
end

function UI:ApplyImport(data)
    local importedCount = 0
    local lastProfileName = ""
    local skippedCount = 0
    local maxProfiles = OxedHub:GetMaxProfileCount()
    
    -- Version 2+ supports multiple profiles
    if data.profiles then
        for name, profileData in pairs(data.profiles) do
            if OxedHub:GetProfileCount() >= maxProfiles then
                skippedCount = skippedCount + 1
            else
            local finalName = name
            -- Handle existing profile names
            if OxedHubDB.profiles[finalName] then
                finalName = name .. " (Imported)"
                local counter = 1
                while OxedHubDB.profiles[finalName] do
                    finalName = name .. " (Imported " .. counter .. ")"
                    counter = counter + 1
                end
            end
            
                local ok = OxedHub:CreateProfile(finalName)
                if ok then
                    OxedHub:SwitchProfile(finalName)
                    self:_ApplySingleProfileData(OxedHub.db.profile, profileData)
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
        if OxedHubDB.profiles[finalName] then
            finalName = profileName .. " (Imported)"
        end
        if OxedHub:GetProfileCount() >= maxProfiles then
            skippedCount = 1
        else
            local ok = OxedHub:CreateProfile(finalName)
            if ok then
                OxedHub:SwitchProfile(finalName)
                self:_ApplySingleProfileData(OxedHub.db.profile, data)
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
    local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
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
    title:SetText(titleText)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    local edit
    if isImport then
        -- Import: direct EditBox filling the popup, tall and clickable
        edit = CreateFrame("EditBox", "OxedHubImportEdit", f, "BackdropTemplate")
        edit:SetPoint("TOPLEFT", 12, -40)
        edit:SetPoint("BOTTOMRIGHT", -12, 50)
        edit:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 6, right = 6, top = 6, bottom = 6 }
        })
        edit:SetBackdropColor(0.06, 0.06, 0.06, 1)
        edit:SetBackdropBorderColor(1, 0.82, 0, 1)
        edit:SetTextColor(1, 1, 1, 1)
        edit:SetAutoFocus(false)
        edit:SetMultiLine(true)
        edit:SetFontObject("ChatFontNormal")
        edit:SetMaxLetters(0) -- Unlimited
        edit:SetMaxBytes(0)   -- Unlimited
        edit:SetMaxLetters(999999) -- Very high limit for modern WoW client compatibility
        edit:EnableMouse(true)
        edit:EnableKeyboard(true)
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
        hint:SetText("Paste export string here — import will run automatically")
        hint:SetTextColor(1, 0.82, 0, 1)

        local chunkStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chunkStatus:SetPoint("BOTTOMLEFT", 12, 18)
        chunkStatus:SetWidth(420)
        chunkStatus:SetJustifyH("LEFT")
        chunkStatus:SetText("")
        f.chunkStatus = chunkStatus

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
                if not ok or type(deserialized) ~= "table" or not deserialized.version then
                    print("|cffff0000Oxed Hub:|r Invalid import string. Please ensure you copied the entire string.")
                    UI:UpdateChunkStatus(f, "Import failed. Check that all parts were pasted.", "error")
                    return
                end
                data = deserialized
            end

            local missingSounds, missingAnimations = UI:ValidateImport(data)
            if #missingSounds > 0 or #missingAnimations > 0 then
                local msg = "|cffffcc00Import Warning:|r\n"
                if #missingSounds > 0 then
                    msg = msg .. "Missing Sounds: " .. table.concat(missingSounds, ", ") .. "\n"
                end
                if #missingAnimations > 0 then
                    msg = msg .. "Missing Animations: " .. table.concat(missingAnimations, ", ") .. "\n"
                end
                msg = msg .. "Import anyway?"
                StaticPopupDialogs["OXEDHUB_IMPORT_WARNING"] = {
                    text = msg,
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        UI:ApplyImport(data)
                        f:Hide()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("OXEDHUB_IMPORT_WARNING")
            else
                UI:ApplyImport(data)
                f:Hide()
            end
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
            
            -- Quick validation: try to deserialize
            local ok, data = AceSerializer:Deserialize(text)
            if ok and type(data) == "table" and data.version then
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
        else
            UI.exportFrame.editBox:SetText(err or "Error generating export string. Data may be too large or corrupted.")
        end
    end)
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


