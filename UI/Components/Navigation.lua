local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.Navigation = OxedHub.UIComponents.Navigation or {}

local Navigation = OxedHub.UIComponents.Navigation
local CreateFrame = CreateFrame

local function ApplyNavButtonState(button, selected)
    if not button then return end

    if selected then
        button.selected:Show()
        button.text:SetTextColor(1, 0.82, 0, 1)
    else
        button.selected:Hide()
        button.text:SetTextColor(1, 1, 1, 1)
    end
end

local customOverlays = {
    Dashboard = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\dashboard.png",
    Triggers = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\triggers.png",
    Reactions = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\actions.png",
    Toys = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\toys.png",
    OxedRing = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\oxedring.png",
    ActionHub = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\actionhub.png",
    Settings = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\settings.png",
    About = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\about.png",
}

function Navigation.CreateButton(parent, tabName, label, config, icons)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(config.SIDEBAR_WIDTH - 10, 32)
    button:RegisterForClicks("LeftButtonUp")

    -- Black button underlay and borders
    -- local bg = button:CreateTexture(nil, "BACKGROUND")
    -- bg:SetAllPoints()
    -- bg:SetAtlas("PetList-ButtonBackground")
    -- button.bg = bg
    
    if customOverlays[tabName] then
        local customBg = button:CreateTexture(nil, "ARTWORK")
        customBg:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 2)
        customBg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -2)
        customBg:SetTexture(customOverlays[tabName])
        button.customBg = customBg
    end

    local selected = button:CreateTexture(nil, "OVERLAY", nil, 7) -- Set to higher sublevel to be above everything
    selected:SetAllPoints()
    selected:SetAtlas("PetList-ButtonSelect")
    selected:Hide()
    button.selected = selected

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetAtlas("PetList-ButtonHighlight")

    button.icon = button:CreateTexture(nil, "OVERLAY", nil, 1)
    button.icon:SetSize(20, 20)
    button.icon:SetPoint("LEFT", 10, 0)
    button.icon:SetTexture(icons[tabName] or 134400)

    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.text:SetPoint("LEFT", 38, 0)
    button.text:SetJustifyH("LEFT")
    button.text:SetText(label)

    button.LockHighlight = function(self)
        ApplyNavButtonState(self, true)
    end

    button.UnlockHighlight = function(self)
        ApplyNavButtonState(self, false)
    end

    ApplyNavButtonState(button, false)
    return button
end
