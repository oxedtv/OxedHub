-- ============================================================================
-- Prey Hunt (built-in OxedHub module)
-- The settings of the Prey Hunt tracker, which used to be a trigger type
-- (Basic Triggers > Prey Hunt). The tracking itself stays in Modules\Prey\:
-- PreyEngine follows the hunt, PreyHUD draws the bar, PreyGossip marks the
-- achievement targets at Astalor. They read their switches and sounds through
-- Prey.GetConfig(), which answers nil while this module is off, and then they
-- stay quiet: no bar, no sounds, no gossip marks, no polling.
--
-- A player who had a Prey Hunt trigger gets its settings copied in once, the
-- module switched on for them, and the old trigger switched off.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey

local DEFAULTS = {
    enabled            = false,  -- off until the player switches it on (see ModuleAPI:Register)
    enableGossipHelper = true,   -- achievement marks on Astalor Bloodsworn's gossip options
    showHUDBar         = true,   -- the draggable hunt bar
    onlyShowInPreyZone = false,  -- the bar only inside the hunt's zone
    lockHUDBar         = false,
    showBlizzardWidget = true,   -- the game's own prey compass / eye
    blizzScale         = 100,    -- that widget's size, percent
    stage1Sound        = "",
    stage2Sound        = "",
    stage3Sound        = "",
    stage4Sound        = "",
    ambushSound        = "",
    bloodyCommandSound = "",
    killSound          = "",
}

-- Keys copied from an old Prey Hunt trigger.
local TRIGGER_KEYS = {
    "enableGossipHelper", "showHUDBar", "onlyShowInPreyZone", "lockHUDBar",
    "showBlizzardWidget", "blizzScale",
}
local SOUND_KEYS = {
    "stage1Sound", "stage2Sound", "stage3Sound", "stage4Sound",
    "ambushSound", "bloodyCommandSound", "killSound",
}

local settings
local optionsWindow
local PREFIX = "|cff00ff00OxedHub:|r "

-- What the tracker reads. nil while the module is off.
function Prey.GetConfig()
    if settings and settings.enabled == true then return settings end
    return nil
end

local function Refresh()
    local Engine = Prey.Engine
    if Prey.HUD and Prey.HUD.SetLocked then
        Prey.HUD:SetLocked(settings and settings.lockHUDBar or false)
    end
    if Engine and Engine.ApplyBlizzardWidgetVisibility then
        local cfg = Prey.GetConfig()
        Engine:ApplyBlizzardWidgetVisibility(not cfg or cfg.showBlizzardWidget ~= false)
    end
    if Engine and Engine.UpdateActiveHunt then
        pcall(Engine.UpdateActiveHunt, Engine)
    end
end

local function ApplyWidgetScale()
    local value = tonumber(settings and settings.blizzScale) or 100
    if OxedHub.db and OxedHub.db.profile then
        OxedHub.db.profile.preyBlizzScale = value
    end
    local Engine = Prey.Engine
    if Engine and Engine.lastBlizzWidgetFrame then
        Engine.lastBlizzWidgetFrame:SetScale(value / 100)
    end
end

-- ── Moving over from the trigger ────────────────────────────────────────────
-- Once. Only the profile in use is looked at: that is the one whose trigger
-- was driving the tracker.

local function MigrateFromTrigger(config)
    if config.migratedFromTrigger then return end
    local triggers = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers
    -- Not loaded yet: try again next login rather than mark it done.
    if type(triggers) ~= "table" then return end
    config.migratedFromTrigger = true
    for _, trigger in pairs(triggers) do
        if type(trigger) == "table" and trigger.event == "PREY_HUNT" and trigger.enabled then
            local c = type(trigger.conditions) == "table" and trigger.conditions or {}
            local a = type(trigger.actions) == "table" and trigger.actions or {}
            for _, key in ipairs(TRIGGER_KEYS) do
                if c[key] ~= nil then config[key] = c[key] end
            end
            for _, key in ipairs(SOUND_KEYS) do
                local value = a[key] or c[key]
                if type(value) == "string" and value ~= "None" then config[key] = value end
            end
            -- They were using it: on, as their own choice, so the one-time
            -- switch-off in ModuleAPI:Register leaves it alone.
            config.enabled = true
            config.playerSet = true
            config.defaultOffSeen = true
            trigger.enabled = false
            C_Timer.After(8, function()
                print(PREFIX .. L["Prey Hunt is now a module: |cffffd100/ohub|r > Modules > Prey Hunt. "]
                    .. L["Your settings and sounds came along, and the old trigger is switched off."])
            end)
            return
        end
    end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function Button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(b) end
    return b
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("Prey Hunt", 470, 640)
        o:AddCheckbox(settings, "enableGossipHelper", "Achievement marks at Astalor Bloodsworn",
            "Marks the hunt targets you still need for an achievement in his gossip menu.", Refresh)
        o:AddCheckbox(settings, "showHUDBar", "Hunt bar on screen", nil, Refresh)
        o:AddCheckbox(settings, "onlyShowInPreyZone", "Only inside the hunt's zone", nil, Refresh)
        o:AddCheckbox(settings, "lockHUDBar", "Lock the hunt bar", nil, Refresh)

        local row1 = CreateFrame("Frame", nil, o)
        row1:SetSize(420, 24)
        row1:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 2)
        local test = Button(row1, L["Preview Bar"], 130)
        test:SetPoint("LEFT", row1, "LEFT", 0, 0)
        test:SetScript("OnClick", function(self)
            if Prey.HUD and Prey.HUD.ToggleTestMode then
                local on = Prey.HUD:ToggleTestMode()
                self:SetText(on and L["Hide Preview"] or L["Preview Bar"])
            end
        end)
        local resetBar = Button(row1, L["Reset Bar"], 110)
        resetBar:SetPoint("LEFT", test, "RIGHT", 8, 0)
        resetBar:SetScript("OnClick", function()
            if Prey.HUD and Prey.HUD.ResetPosition then Prey.HUD:ResetPosition() end
        end)
        o.cursorY = o.cursorY - 34

        o:AddCheckbox(settings, "showBlizzardWidget", "The game's prey widget (compass / eye)", nil, Refresh)
        o:AddSlider(settings, "blizzScale", "Widget size", 50, 150, 5, "%s: %d%%", ApplyWidgetScale)

        local row2 = CreateFrame("Frame", nil, o)
        row2:SetSize(420, 24)
        row2:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 2)
        local move = Button(row2, L["Move Widget"], 130)
        move:SetPoint("LEFT", row2, "LEFT", 0, 0)
        move:SetScript("OnClick", function(self)
            local Engine = Prey.Engine
            if Engine and Engine.ToggleBlizzardWidgetMover then
                local on = Engine:ToggleBlizzardWidgetMover()
                self:SetText(on and L["Hide Mover"] or L["Move Widget"])
            end
        end)
        local resetWidget = Button(row2, L["Reset Widget"], 110)
        resetWidget:SetPoint("LEFT", move, "RIGHT", 8, 0)
        resetWidget:SetScript("OnClick", function()
            if OxedHub.db and OxedHub.db.profile then OxedHub.db.profile.preyBlizzWidgetPosition = nil end
            local Engine = Prey.Engine
            if Engine and Engine.blizzMoverFrame then
                Engine.blizzMoverFrame:ClearAllPoints()
                Engine.blizzMoverFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
            end
            local container = UIWidgetTopCenterContainerFrame
            if container then
                container:ClearAllPoints()
                container:SetPoint("TOP", UIParent, "TOP", 0, -120)
            end
        end)
        o.cursorY = o.cursorY - 36

        o:AddSoundPicker(settings, "stage1Sound", "Stage 1 (Scent in the Wind)", "None")
        o:AddSoundPicker(settings, "stage2Sound", "Stage 2 (Blood in Shadows)", "None")
        o:AddSoundPicker(settings, "stage3Sound", "Stage 3 (Echoes of Kill)", "None")
        o:AddSoundPicker(settings, "stage4Sound", "Stage 4 (Feast of Fang)", "None")
        o:AddSoundPicker(settings, "ambushSound", "Ambush", "None")
        o:AddSoundPicker(settings, "bloodyCommandSound", "Bloody Command (Nightmare)", "None")
        o:AddSoundPicker(settings, "killSound", "Prey slain", "None")
        o:AddNote("The hunt bar and widget stay out of dungeons, raids and battlegrounds.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.preyhunt
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.preyhunt = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    -- Before Register: a migrated module must already say "on, chosen".
    pcall(MigrateFromTrigger, settings)

    if not OxedHub.ModuleAPI then
        Refresh()
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "preyhunt",
        name     = "Prey Hunt",
        version  = "1.0.0",
        updated  = 20261021.3,  -- moved here from the trigger list
        author   = "Oxed",
        category = "quests",
        keywords = { "prey", "hunt", "astalor", "achievement", "hud", "stage", "ambush", "midnight" },
        desc     = "Hunt bar with stages, ambush and kill sounds, and achievement marks at Astalor.",
        icon     = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            ApplyWidgetScale()
            Refresh()
        end,

        OnDisable = function()
            -- GetConfig now answers nil: the bar hides, the widget goes back
            -- to the game's own, and nothing plays.
            Refresh()
        end,
    })
end)
