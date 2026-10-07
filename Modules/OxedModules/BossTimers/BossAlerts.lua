-- ============================================================================
-- Boss Alerts (built-in OxedHub module)
-- What Boss Timers puts in a bar, this puts in the middle of the screen:
--
--   * Countdown: the abilities about to land, large, counting down the last
--     few seconds ("Crushing Blow 3").
--   * Text alert: a short flash of text the moment an ability enters its
--     warning time: its own text from Boss Timers' abilities window, or its
--     name.
--   * Game warnings: the boss warnings the game itself raises
--     (ENCOUNTER_WARNING), with a sound per severity.
--
-- Both read BossEngine, the same as Boss Timers, and share its per-ability
-- settings: an ability switched off there is off here too, and its own text
-- is used here too.
--
-- ⚠ A game warning's contents are secret in a fight; only its severity
-- (0 low, 1 medium, 2 high) is plain, and that is all this reads. The name
-- shown is the recognised ability landing at that moment, if there is one.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on

    -- Countdown
    countdown     = true,
    countFrom     = 5,       -- seconds before the ability
    countRows     = 3,
    countSize     = 26,
    countDecimals = false,
    countGrowUp   = false,
    countKnownOnly = true,   -- only abilities the data recognises
    kindTank      = true,
    kindHealer    = true,
    kindTargeted  = true,
    kindMechanic  = true,
    kindSpecial   = true,
    kindOther     = false,

    -- Text alert
    flash         = true,
    flashTime     = 2,       -- seconds on screen
    flashSize     = 34,
    flashSound    = false,   -- Boss Timers already sounds; off by default
    flashSoundID  = "",

    -- Game warnings
    warnings      = true,
    warnLow       = false,
    warnMedium    = true,
    warnHigh      = true,
    soundLow      = "",
    soundMedium   = "",
    soundHigh     = "",

    scale         = 1,
    locked        = false,
}

local KIND_SETTING = {
    tank = "kindTank", healer = "kindHealer", targeted = "kindTargeted",
    mechanic = "kindMechanic", special = "kindSpecial", other = "kindOther",
}

local TICK = 0.05

local Engine = OxedHub.BossEngine
local settings
local optionsWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    return false
end
local countFrame, flashFrame
local rows = {}
local ticker
local active = false

-- Boss Timers' per-ability settings, shared: off, text.
local function Own(ev)
    if not (ev.encounterID and ev.abilityID) then return nil end
    local timers = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.bosstimers
    local list = timers and timers.abilities
    return list and list[tostring(ev.encounterID) .. ":" .. tostring(ev.abilityID)] or nil
end

local function WantedHere()
    local timers = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.bosstimers
    if not timers then return true end
    local _, kind = IsInInstance()
    if kind == "party" then return timers.inDungeons ~= false end
    if kind == "raid" then return timers.inRaids ~= false end
    return timers.elsewhere ~= false
end

local function PlayerRole()
    local spec = GetSpecialization and GetSpecialization()
    return spec and GetSpecializationRole and GetSpecializationRole(spec) or nil
end

local function Wanted(ev)
    local own = Own(ev)
    if own and own.off then return false end
    if not ev.ability then return not settings.countKnownOnly end
    local kind = ev.ability.kind or "other"
    if not settings[KIND_SETTING[kind] or "kindOther"] then return false end
    local timers = OxedHubDB.modules.bosstimers
    local role = PlayerRole()
    if timers and kind == "tank" and timers.hideTankForOthers and role and role ~= "TANK" then return false end
    if timers and kind == "healer" and timers.hideHealerForOthers and role and role ~= "HEALER" then return false end
    return true
end

local function DisplayName(ev)
    local own = Own(ev)
    if own and own.text and own.text ~= "" then return own.text end
    -- Only a recognised ability's name is plain text; the game's own name for
    -- an unknown one may be secret and cannot be joined to other text.
    if ev.known then return ev.name end
    return nil
end

local function Play(id)
    local API = OxedHub.ModuleAPI
    if API and API:PlaySound(id) then return end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- ── Frames ─────────────────────────────────────────────────────────────────

local function MakeMovable(frame, key, label, x, y)
    frame:SetPoint(settings[key .. "Point"] or "CENTER", UIParent, settings[key .. "Rel"] or "CENTER",
        settings[key .. "X"] or x, settings[key .. "Y"] or y)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, px, py = self:GetPoint()
        settings[key .. "Point"], settings[key .. "Rel"], settings[key .. "X"], settings[key .. "Y"] = point, rel, px, py
    end)
    local hint = frame:CreateTexture(nil, "BACKGROUND")
    hint:SetAllPoints()
    hint:SetColorTexture(0, 0.6, 1, 0.25)
    frame.hint = hint
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    text:SetText(label)
    frame.hintText = text
end

local function BuildFrames()
    if countFrame then return end
    countFrame = CreateFrame("Frame", "OxedHubBossAlertsCountdown", UIParent)
    countFrame:SetSize(360, 40)
    MakeMovable(countFrame, "count", "Boss Alerts countdown: drag me", 0, 180)

    flashFrame = CreateFrame("Frame", "OxedHubBossAlertsText", UIParent)
    flashFrame:SetSize(500, 50)
    MakeMovable(flashFrame, "flash", "Boss Alerts text: drag me", 0, 260)
    flashFrame.label = flashFrame:CreateFontString(nil, "OVERLAY")
    flashFrame.label:SetPoint("CENTER")
    -- The pop when the text appears is on the label, never on the frame:
    -- nothing here touches the frame's own alpha.
    local group = flashFrame.label:CreateAnimationGroup()
    local grow = group:CreateAnimation("Scale")
    grow:SetScaleFrom(1.4, 1.4)
    grow:SetScaleTo(1, 1)
    grow:SetDuration(0.18)
    flashFrame.pop = group
end

local function Restyle()
    if not countFrame then return end
    local font = GameFontNormalHuge and GameFontNormalHuge:GetFont() or STANDARD_TEXT_FONT
    countFrame:SetScale(settings.scale)
    flashFrame:SetScale(settings.scale)
    flashFrame.label:SetFont(font, settings.flashSize, "THICKOUTLINE")
    for i, row in ipairs(rows) do
        row:SetFont(font, settings.countSize, "THICKOUTLINE")
        row:ClearAllPoints()
        local step = (i - 1) * (settings.countSize + 6)
        if settings.countGrowUp then
            row:SetPoint("BOTTOM", countFrame, "BOTTOM", 0, step)
        else
            row:SetPoint("TOP", countFrame, "TOP", 0, -step)
        end
    end
    local editing = settings.enabled and not settings.locked and OptionsOpen()
    for _, frame in ipairs({ countFrame, flashFrame }) do
        frame.hint:SetShown(editing)
        frame.hintText:SetShown(editing)
        frame:EnableMouse(editing)
        frame:SetShown(true)
    end
    if not editing and not (flashFrame.until_ and flashFrame.until_ > GetTime()) then
        flashFrame.label:SetText("")
    end
end

local function Row(i)
    local row = rows[i]
    if not row then
        row = countFrame:CreateFontString(nil, "OVERLAY")
        rows[i] = row
        Restyle()
    end
    return row
end

local function Flash(text, r, g, b)
    if not flashFrame then return end
    flashFrame.label:SetText(text)
    flashFrame.label:SetTextColor(r or 1, g or 0.82, b or 0)
    flashFrame.until_ = GetTime() + settings.flashTime
    flashFrame.pop:Stop()
    flashFrame.pop:Play()
    C_Timer.After(settings.flashTime, function()
        if flashFrame.until_ and GetTime() >= flashFrame.until_ - 0.01 then
            flashFrame.label:SetText("")
        end
    end)
end

-- ── Each tick ──────────────────────────────────────────────────────────────

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local coming = {}
local function Tick()
    wipe(coming)
    local any = false
    local here = WantedHere()
    for _, ev in pairs(Engine:GetEvents()) do
        any = true
        if here and Engine:IsActive(ev) and Wanted(ev) then
            local left = Engine:TimeLeft(ev)
            if left > 0 then
                local own = Own(ev)
                local timers = OxedHubDB.modules.bosstimers
                local warnAt = (own and own.warnAt) or (timers and timers.warnAt) or 5
                if settings.flash and not ev.flashed and left <= warnAt then
                    ev.flashed = true
                    Flash(DisplayName(ev) or "Ability coming")
                    if settings.flashSound then Play(settings.flashSoundID) end
                end
                if settings.countdown and left <= settings.countFrom then
                    ev.alertLeft = left
                    coming[#coming + 1] = ev
                end
            end
        end
    end

    table.sort(coming, function(a, b) return a.alertLeft < b.alertLeft end)
    local shown = 0
    for i = 1, math.min(#coming, settings.countRows) do
        local ev = coming[i]
        local row = Row(i)
        local left = ev.alertLeft
        local number = settings.countDecimals and ("%.1f"):format(left) or tostring(math.ceil(left))
        row:SetText((DisplayName(ev) or "Ability") .. "  " .. number)
        if left <= 1.5 then row:SetTextColor(1, 0.2, 0.15)
        elseif left <= 3 then row:SetTextColor(1, 0.65, 0.1)
        else row:SetTextColor(1, 0.9, 0.3) end
        row:Show()
        shown = i
    end
    for i = shown + 1, #rows do rows[i]:Hide() end

    if not any then StopTicker() end
end

local function StartTicker()
    if ticker or not active then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
end

Engine:AddListener({
    OnEventAdded = function() StartTicker() end,
    OnEncounterEnd = function() for _, row in ipairs(rows) do row:Hide() end end,
})

-- ── Game warnings ──────────────────────────────────────────────────────────

local SEVERITY = {
    [0] = { setting = "warnLow", sound = "soundLow", colour = { 0.6, 0.85, 1 } },
    [1] = { setting = "warnMedium", sound = "soundMedium", colour = { 1, 0.82, 0 } },
    [2] = { setting = "warnHigh", sound = "soundHigh", colour = { 1, 0.25, 0.2 } },
}

-- The recognised ability landing nearest to now, within a few seconds.
local function LandingNow()
    local best, bestGap
    for _, ev in pairs(Engine:GetEvents()) do
        if ev.known and not ev.test then
            local gap = math.abs(ev.endsAt - GetTime())
            if gap <= 3 and (not bestGap or gap < bestGap) then best, bestGap = ev, gap end
        end
    end
    return best
end

local warningFrame = CreateFrame("Frame")
warningFrame:SetScript("OnEvent", function(_, _, info)
    if not (settings and settings.enabled and settings.warnings and active) then return end
    if not WantedHere() then return end
    local severity = type(info) == "table" and Engine.Plain(info.severity) or nil
    local row = severity and SEVERITY[severity]
    if not row or not settings[row.setting] then return end
    local ev = LandingNow()
    local text = ev and DisplayName(ev) or "Warning"
    Flash(text, row.colour[1], row.colour[2], row.colour[3])
    Play(settings[row.sound])
end)

-- ── Start and stop ─────────────────────────────────────────────────────────

local function Start()
    active = true
    BuildFrames()
    Engine:Start()
    warningFrame:RegisterEvent("ENCOUNTER_WARNING")
    if next(Engine:GetEvents()) then StartTicker() end
    Restyle()
end

local function Stop()
    active = false
    StopTicker()
    Engine:Stop()
    warningFrame:UnregisterAllEvents()
    if countFrame then countFrame:Hide(); flashFrame:Hide() end
end

local function ShowTest()
    if not settings.enabled then
        print("|cff00ccffOxedHub|r Switch Boss Alerts on first.")
        return
    end
    Engine:AddTestEvents({
        { name = "Test: Crushing Blow", icon = 136025, duration = 4, kind = "tank" },
        { name = "Test: Shadow Burst", icon = 136197, duration = 7, kind = "mechanic" },
        { name = "Test: Fixate", icon = 136219, duration = 9, kind = "targeted" },
    })
    C_Timer.After(1, function() Flash("Test: game warning", 1, 0.25, 0.2) end)
end

-- ── Options ─────────────────────────────────────────────────────────────────

local textWindow
local function ShowTextOptions()
    local API = OxedHub.ModuleAPI
    if not textWindow then
        local w = API:CreateOptionsWindow("Boss Alerts: text and warnings", 480, 440)
        textWindow = w
        w:AddCheckbox(settings, "flash", "Text alert when an ability is close")
        w:AddSlider(settings, "flashTime", "Text stays for", 1, 6, 0.5, "%s: %.1f s")
        w:AddSlider(settings, "flashSize", "Text size", 16, 72, 1, "%s: %d", Restyle)
        w:AddCheckbox(settings, "flashSound", "Sound with the text alert")
        w:AddSoundPicker(settings, "flashSoundID", "Text alert sound", "Raid warning")

        w:AddCheckbox(settings, "warnings", "The game's own boss warnings")
        w:AddCheckbox(settings, "warnHigh", "High warnings")
        w:AddSoundPicker(settings, "soundHigh", "High", "Raid warning")
        w:AddCheckbox(settings, "warnMedium", "Medium warnings")
        w:AddSoundPicker(settings, "soundMedium", "Medium", "Raid warning")
        w:AddCheckbox(settings, "warnLow", "Low warnings")
        w:AddSoundPicker(settings, "soundLow", "Low", "Raid warning")
    end
    textWindow:Show()
end

local function AddButton(w, text, x, onClick)
    local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetPoint("TOPLEFT", w, "TOPLEFT", x, w.cursorY - 2)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Boss Alerts", 480, 670)
        optionsWindow = w
        w:HookScript("OnShow", function() Restyle() end)
        w:HookScript("OnHide", function() Restyle() end)

        AddButton(w, "Show a test", 20, ShowTest)
        AddButton(w, "Text and warnings", 250, ShowTextOptions)
        w.cursorY = w.cursorY - 32

        w:AddCheckbox(settings, "locked", "Lock the alerts",
            "Unlocked, drag the blue boxes with the left button.", Restyle)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Restyle)

        w:AddCheckbox(settings, "countdown", "Countdown in the middle of the screen")
        w:AddSlider(settings, "countFrom", "Count down from", 2, 10, 1, "%s: %d s")
        w:AddSlider(settings, "countRows", "Abilities at once", 1, 6, 1, "%s: %d")
        w:AddSlider(settings, "countSize", "Countdown size", 14, 60, 1, "%s: %d", Restyle)
        w:AddCheckbox(settings, "countDecimals", "Tenths of a second")
        w:AddCheckbox(settings, "countGrowUp", "Grow upwards", nil, Restyle)
        w:AddCheckbox(settings, "countKnownOnly", "Only abilities the data recognises")
        w:AddCheckbox(settings, "kindTank", "Tank abilities")
        w:AddCheckbox(settings, "kindHealer", "Healer abilities")
        w:AddCheckbox(settings, "kindTargeted", "Abilities on a player")
        w:AddCheckbox(settings, "kindMechanic", "Mechanics")
        w:AddCheckbox(settings, "kindSpecial", "Special")
        w:AddCheckbox(settings, "kindOther", "Everything else")

        w:AddNote("Abilities switched off, and their own text, come from Boss Timers' "
            .. "Abilities window.")
        w:AddModuleLinks("Works together with", { "bosstimers", "bosstrack", "trashtimers", "enemycasts", "partyinterrupts", "kickbar", "bosshealth" })
    end
    optionsWindow:Show()
end

-- ── Settings and registration ──────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bossalerts
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bossalerts = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bossalerts",
        name     = "Boss Alerts",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "boss", "alert", "countdown", "warning", "raid", "dungeon", "text" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Countdown and text alerts in the middle of the screen for boss abilities.",
        icon     = "Interface\\Icons\\Ability_Warrior_Rampage",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        quick = {
            { text = "Test", func = function() ShowTest() end },
        },

        OnEnable = function(_, cfg)
            settings = cfg
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
