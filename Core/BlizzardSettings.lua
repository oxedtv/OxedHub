local addonName, OxedHub = ...

local BlizzardSettings = {}
OxedHub.BlizzardSettings = BlizzardSettings

local function OpenOxedHubOptions()
    if not OxedHub.UI then
        return
    end

    if OxedHub.UI.ShowMainWindow then
        OxedHub.UI:ShowMainWindow()
    end
    if OxedHub.UI.ShowTab then
        OxedHub.UI:ShowTab("Settings")
    end
end

local function CreateCenteredText(parent, text, fontObject, yOffset)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
    fs:SetPoint("CENTER", parent, "CENTER", 0, yOffset)
    fs:SetText(text)
    fs:SetJustifyH("CENTER")
    return fs
end

function BlizzardSettings:Refresh()
    if self.versionText then
        local version = OxedHub.CONFIG and OxedHub.CONFIG.VERSION or "2.0.5"
        self.versionText:SetText("Version: " .. version)
    end
end

function BlizzardSettings:CreatePanel()
    local panel = CreateFrame("Frame", "OxedHubBlizzardSettingsPanel")
    panel.name = "Oxed Hub"

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    bg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg.png")
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetAlpha(0.38)

    local shade = panel:CreateTexture(nil, "BORDER")
    shade:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    shade:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    shade:SetColorTexture(0, 0, 0, 0.42)

    local logo = panel:CreateTexture(nil, "ARTWORK")
    logo:SetSize(320, 210)
    logo:SetPoint("CENTER", panel, "CENTER", 0, 110)
    logo:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\logo-settings.tga")

    self.versionText = CreateCenteredText(panel, "Version: 2.0.5", "GameFontHighlight", -20)

    local commandText = CreateCenteredText(panel, "Access options with /oxedhub or /ohub", "GameFontHighlightLarge", -50)
    commandText:SetTextColor(1, 1, 1, 1)

    local openButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openButton:SetSize(420, 42)
    openButton:SetPoint("TOP", commandText, "BOTTOM", 0, -28)
    openButton:SetText("Open Options")
    openButton:SetScript("OnClick", OpenOxedHubOptions)

    local buttonText = openButton:GetFontString()
    if buttonText and buttonText.SetFont then
        buttonText:SetFont(OxedHub:GetFont("Fonts\\FRIZQT__.TTF"), 24, "OUTLINE")
        buttonText:SetTextColor(1, 0.82, 0, 1)
    end

    panel:SetScript("OnShow", function()
        BlizzardSettings:Refresh()
    end)

    self.panel = panel
    return panel
end

function BlizzardSettings:Register()
    if self.registered then
        self:Refresh()
        return
    end

    local panel = self.panel or self:CreatePanel()

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Oxed Hub")
        Settings.RegisterAddOnCategory(category)
        self.category = category
        self.registered = true
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        self.registered = true
    end

    self:Refresh()
end
