-- ============================================================================
-- Boss Health (built-in OxedHub module)
-- A health bar for each boss in the fight, with a mark wherever the fight
-- changes (a new phase at 66%, adds at 35%...), from BossData. You can see
-- how close the next phase is without doing the sum.
--
-- ⚠ A boss's health is a secret value in a fight: Lua cannot read or compare
-- it, so there can be no "phase in 5%" alert. The bar does not need to read
-- it: the status bar is handed the secret numbers and fills itself, and the
-- percentage text is formatted by the game. The marks are plain numbers from
-- the data, placed once.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled   = false,   -- off until the player switches it on
    marks     = true,
    showText  = true,
    width     = 260,
    height    = 18,
    spacing   = 4,
    scale     = 1,
    locked    = false,
}

local MAX_BOSSES = 5
local TICK = 0.2

local Engine = OxedHub.BossEngine
local settings
local optionsWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    return false
end
local anchor
local bars = {}
local ticker
local active = false
local eventFrame = CreateFrame("Frame")

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "OxedHubBossHealthAnchor", UIParent)
    anchor:SetPoint(settings.point or "TOP", UIParent, settings.rel or "TOP", settings.x or 0, settings.y or -120)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        settings.point, settings.rel, settings.x, settings.y = point, rel, x, y
    end)
    anchor.hint = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.hint:SetAllPoints()
    anchor.hint:SetColorTexture(0, 0.6, 1, 0.25)
    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.text:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    anchor.text:SetText("Boss Health: drag me")
end

local function Bar(i)
    local bar = bars[i]
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, anchor)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.8, 0.1, 0.1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetPoint("LEFT", 4, 0)
    bar.pct = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.pct:SetPoint("RIGHT", -4, 0)
    bar.marks = {}
    bars[i] = bar
    return bar
end

local function Layout()
    if not anchor then return end
    anchor:SetScale(settings.scale)
    anchor:SetSize(settings.width, settings.height)
    local editing = settings.enabled and not settings.locked and OptionsOpen()
    anchor.hint:SetShown(editing)
    anchor.text:SetShown(editing)
    anchor:EnableMouse(editing)
    for i, bar in ipairs(bars) do
        bar:SetSize(settings.width, settings.height)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (settings.height + settings.spacing))
    end
end

-- Marks at the data's health percentages, the same on every boss bar.
local function PlaceMarks(bar, encounter)
    for _, mark in ipairs(bar.marks) do mark:Hide() end
    if not (settings.marks and encounter and encounter.health) then return end
    for i, row in ipairs(encounter.health) do
        local mark = bar.marks[i]
        if not mark then
            mark = bar:CreateTexture(nil, "OVERLAY")
            mark:SetColorTexture(1, 0.85, 0.1, 0.95)
            bar.marks[i] = mark
        end
        mark:SetSize(2, settings.height)
        mark:ClearAllPoints()
        mark:SetPoint("LEFT", bar, "LEFT", settings.width * row.at / 100, 0)
        mark:Show()
    end
end

-- Run through pcall as named functions: no closure per boss per tick.
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }

local function FillHealth(bar, unit)
    bar:SetMinMaxValues(0, UnitHealthMax(unit))
    bar:SetValue(UnitHealth(unit))
end

local function FillPercent(bar, unit)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    bar.pct:SetFormattedText("%d%%", UnitHealthPercent(unit, true, curve))
end

local function Update()
    local _, encounter = Engine:GetCurrentEncounter()
    local shown = 0
    for i = 1, MAX_BOSSES do
        local unit = BOSS_UNITS[i]
        local ok, exists = pcall(UnitExists, unit)
        -- A secret "exists" is shown: there is a boss frame to fill.
        local present = ok and ((issecretvalue and issecretvalue(exists)) or exists)
        if present then
            shown = shown + 1
            local bar = Bar(shown)
            pcall(FillHealth, bar, unit)
            bar.name:SetText(UnitName(unit))
            bar.pct:SetText("")
            if settings.showText and UnitHealthPercent then
                pcall(FillPercent, bar, unit)
            end
            if bar.encounter ~= encounter then
                bar.encounter = encounter
                PlaceMarks(bar, encounter)
            end
            bar:Show()
        end
    end
    for i = shown + 1, #bars do bars[i]:Hide() end
    anchor:SetShown(shown > 0 or (settings.enabled and not settings.locked and OptionsOpen()))
    if shown == 0 and ticker then ticker:Cancel(); ticker = nil end
end

local function Watch()
    if not active then return end
    Layout()
    Update()
    if not ticker then ticker = C_Timer.NewTicker(TICK, Update) end
end

eventFrame:SetScript("OnEvent", function() Watch() end)

local function Start()
    active = true
    CreateAnchor()
    Engine:Start()
    eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Watch()
end

local function Stop()
    active = false
    eventFrame:UnregisterAllEvents()
    Engine:Stop()
    if ticker then ticker:Cancel(); ticker = nil end
    if anchor then anchor:Hide() end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Boss Health", 460, 420)
        optionsWindow = w
        w:HookScript("OnShow", function() Watch() end)
        w:HookScript("OnHide", function() Watch() end)
        w:AddCheckbox(settings, "marks", "Marks where the fight changes", nil, function()
            for _, bar in ipairs(bars) do bar.encounter = false end
        end)
        w:AddCheckbox(settings, "showText", "Show the percentage")
        w:AddCheckbox(settings, "locked", "Lock", "Unlocked, drag the blue box.", Watch)
        w:AddSlider(settings, "width", "Width", 120, 600, 10, "%s: %d", function()
            Layout(); for _, bar in ipairs(bars) do bar.encounter = false end
        end)
        w:AddSlider(settings, "height", "Height", 10, 40, 1, "%s: %d", Layout)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Layout)
        w:AddModuleLinks("Works together with", { "bosstimers", "bossalerts", "bosstrack" })
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bosshealth
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bosshealth = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bosshealth",
        name     = "Boss Health",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "boss", "health", "phase", "percent", "raid", "dungeon" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A health bar per boss, marked where the fight changes phase.",
        icon     = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",

        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
