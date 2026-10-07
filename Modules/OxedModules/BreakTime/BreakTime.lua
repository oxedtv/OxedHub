-- ============================================================================
-- Break Time (built-in OxedHub module)
-- A friendly nudge to stand up after a long stretch of play. Never in a fight
-- or a boss encounter: the reminder waits until you are out of it. Going away
-- from the keyboard for a while counts as a break and starts the clock again.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled  = false,   -- off until the player switches it on
    every    = 60,      -- minutes of play before a reminder
    snooze   = 10,      -- minutes "Later" waits
    afkBreak = 5,       -- minutes away that count as a break
    sound    = "",      -- an OxedHub sound id; empty plays the game's
}

local CHECK = 30        -- seconds between looks at the clock

local settings
local optionsWindow
local reminder
local ticker
local dueAt              -- GetTime() at which the next reminder is due
local afkSince
local eventFrame = CreateFrame("Frame")

local function Reset(minutes)
    dueAt = GetTime() + (minutes or settings.every) * 60
end

local function Busy()
    if InCombatLockdown() then return true end
    if IsEncounterInProgress and IsEncounterInProgress() then return true end
    return false
end

local function PlayedText()
    local minutes = math.floor((GetTime() - (dueAt - settings.every * 60)) / 60 + 0.5)
    if minutes >= 90 then
        return ("%d hours %d minutes"):format(math.floor(minutes / 60), minutes % 60)
    end
    return ("%d minutes"):format(minutes)
end

local function BuildReminder()
    if reminder then return end
    local ok, f = pcall(CreateFrame, "Frame", "OxedHubBreakTime", UIParent, "BasicFrameTemplate")
    if not ok or not f then f = CreateFrame("Frame", "OxedHubBreakTime", UIParent, "BackdropTemplate") end
    f:SetSize(340, 150)
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if f.TitleText then f.TitleText:SetText("Break time") end
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", 0, -40)
    f.text:SetWidth(300)

    local later = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    later:SetSize(130, 24)
    later:SetPoint("BOTTOMLEFT", 30, 18)
    later:SetScript("OnClick", function() Reset(settings.snooze); f:Hide() end)
    f.later = later

    local done = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    done:SetSize(130, 24)
    done:SetPoint("BOTTOMRIGHT", -30, 18)
    done:SetText("I took a break")
    done:SetScript("OnClick", function() Reset(); f:Hide() end)
    f:Hide()
    reminder = f
end

local function ShowReminder()
    BuildReminder()
    reminder.text:SetText(("You have been playing for %s.\nStand up, stretch, drink some water."):format(PlayedText()))
    reminder.later:SetText(("Later (%d min)"):format(settings.snooze))
    reminder:Show()
    local API = OxedHub.ModuleAPI
    if not (API and API:PlaySound(settings.sound)) and PlaySound and SOUNDKIT then
        pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
    end
end

local function Check()
    if not dueAt then Reset() end
    if reminder and reminder:IsShown() then return end
    if GetTime() >= dueAt and not Busy() then ShowReminder() end
end

eventFrame:SetScript("OnEvent", function()
    local away = UnitIsAFK("player")
    if away and not afkSince then
        afkSince = GetTime()
    elseif not away and afkSince then
        if GetTime() - afkSince >= settings.afkBreak * 60 then Reset() end
        afkSince = nil
    end
end)

local function Start()
    Reset()
    eventFrame:RegisterEvent("PLAYER_FLAGS_CHANGED")
    if not ticker then ticker = C_Timer.NewTicker(CHECK, Check) end
end

local function Stop()
    eventFrame:UnregisterAllEvents()
    if ticker then ticker:Cancel(); ticker = nil end
    if reminder then reminder:Hide() end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Break Time", 440, 290)
        optionsWindow = w
        w:AddSlider(settings, "every", "Remind me after", 15, 180, 5, "%s: %d min", function() Reset() end)
        w:AddSlider(settings, "snooze", "Later waits", 5, 60, 5, "%s: %d min")
        w:AddSlider(settings, "afkBreak", "Away this long counts as a break", 1, 30, 1, "%s: %d min")
        w:AddSoundPicker(settings, "sound", "Sound", "Ready check")
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(150, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        test:SetText("Show it now")
        test:SetScript("OnClick", ShowReminder)
        w.cursorY = w.cursorY - 32
        w:AddNote("Never shown in a fight or a boss encounter; it waits until you are out.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.breaktime
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.breaktime = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "breaktime",
        name     = "Break Time",
        version  = "1.0.0",
        author   = "Oxed",
        category = "character",
        keywords = { "break", "reminder", "health", "stretch", "time" },
        desc     = "A friendly reminder to take a break after a long session. Never in a fight.",
        icon     = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        quick = { { text = "Show it now", func = function() ShowReminder() end } },
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
