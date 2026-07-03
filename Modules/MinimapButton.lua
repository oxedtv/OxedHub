local addonName, OxedHub = ...

-- MinimapButton Module - Uses LibDBIcon like TargetInsider
local MinimapButton = {}
OxedHub.MinimapButton = MinimapButton
local L = OxedHub.L

-- Debug log
local debugLog = {}
local MAX_LOG_ENTRIES = 50

local function Log(message)
    local timestamp = date("%H:%M:%S")
    table.insert(debugLog, 1, "[" .. timestamp .. "] " .. message)
    if #debugLog > MAX_LOG_ENTRIES then
        table.remove(debugLog)
    end
end

-- Create standalone button immediately at file load time
local button = CreateFrame("Button", "OxedHubMinimapButton", Minimap)
MinimapButton.button = button
button:SetFrameStrata("MEDIUM")
button:SetSize(31, 31)
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetAllPoints(button)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetTexCoord(0, 0.6, 0, 0.6)

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(22, 22)
icon:SetPoint("CENTER")
icon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Minimap\\o-oxed-minimap.tga")
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

-- Mask it to a circle so it doesn't poke out of the golden ring
if button.CreateMaskTexture then
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(22, 22)
    mask:SetPoint("CENTER")
    icon:AddMaskTexture(mask)
end

-- Initialize settings and handlers
function MinimapButton:Init()
    Log("MinimapButton Init starting...")
    
    -- Initialize minimap icon settings
    if type(OxedHub.db.profile.settings.minimapPosition) ~= "table" then
        OxedHub.db.profile.settings.minimapPosition = { hide = false, minimapPos = 225 }
        Log("Minimap position converted to table")
    end
    
    local button = self.button
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(L["MINIMAP_TOOLTIP_TITLE"])
        GameTooltip:AddLine(L["MINIMAP_TOOLTIP_TOGGLE"], 1, 1, 1)
        GameTooltip:AddLine(L["MINIMAP_TOOLTIP_MENU"], 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            if OxedHub.UI then OxedHub.UI:ToggleMainWindow() end
        elseif btn == "RightButton" then
            MinimapButton:ShowContextMenu()
        end
    end)
    
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            MinimapButton:UpdatePosition(angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    
    -- Set initial position immediately
    MinimapButton:UpdatePosition(OxedHub.db.profile.settings.minimapPosition.minimapPos)
    
    -- Ensure it snaps perfectly on login if Minimap size changes
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function()
        MinimapButton:UpdatePosition(OxedHub.db.profile.settings.minimapPosition.minimapPos)
    end)
    
    if OxedHub.db.profile.settings.minimapPosition.hide then
        button:Hide()
    end
    
    Log("Minimap button registered natively")
end

function MinimapButton:UpdatePosition(angle)
    if not self.button then return end
    local radius = (Minimap:GetWidth() / 2) + 10
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings.minimapPosition then
        OxedHub.db.profile.settings.minimapPosition.minimapPos = angle
    end
end

-- Show context menu
function MinimapButton:ShowContextMenu()
    local menu = {
        { text = L["MINIMAP_MENU_TITLE"], isTitle = true, notCheckable = true },
        { text = L["MINIMAP_MENU_TOGGLE"], func = function()
            if OxedHub.UI then OxedHub.UI:ToggleMainWindow() end
        end, notCheckable = true },
        { text = L["MINIMAP_MENU_RESET"], func = function()
            OxedHub.db.profile.settings.minimapPosition = { hide = false, minimapPos = 225 }
            MinimapButton:UpdatePosition(225)
            Log("Position reset to default")
        end, notCheckable = true },
        { text = L["MINIMAP_MENU_DEBUG"], func = function()
            MinimapButton:ShowDebugLog()
        end, notCheckable = true },
        { text = " " },
        { text = L["MINIMAP_MENU_CLOSE"], func = function() end, notCheckable = true },
    }
    
    local menuFrame = CreateFrame("Frame", "OxedHubMinimapMenu", UIParent, "UIDropDownMenuTemplate")
    
    if EasyMenu then
        EasyMenu(menu, menuFrame, "cursor", 0, 0, "MENU")
    else
        -- Fallback for when EasyMenu is not available
        UIDropDownMenu_Initialize(menuFrame, function()
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.func = item.func
                info.isTitle = item.isTitle
                info.notCheckable = item.notCheckable
                UIDropDownMenu_AddButton(info)
            end
        end)
        ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
    end
end

-- Show debug log
function MinimapButton:ShowDebugLog()
    local frame = CreateFrame("Frame", "OxedHubDebugLog", UIParent, "BackdropTemplate")
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText(L["DEBUG_LOG_TITLE"])
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -35, 50)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Log entries
    local yOffset = 0
    for _, entry in ipairs(debugLog) do
        local text = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
        text:SetText(entry)
        yOffset = yOffset - 15
    end
    
    scrollChild:SetHeight(math.abs(yOffset) + 20)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 15)
    closeBtn:SetSize(100, 25)
    closeBtn:SetText(L["DEBUG_LOG_CLOSE"])
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    Log("Debug log window opened")
    frame:Show()
end

-- Toggle button visibility
function MinimapButton:SetShown(shown)
    if self.button then
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings.minimapPosition then
            OxedHub.db.profile.settings.minimapPosition.hide = not shown
        end
        self.button:SetShown(shown)
    end
end

-- Check if button is shown
function MinimapButton:IsShown()
    return self.button and self.button:IsShown()
end
