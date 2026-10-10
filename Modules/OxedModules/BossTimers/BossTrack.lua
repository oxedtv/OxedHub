-- ============================================================================
-- Boss Track (built-in OxedHub module)
-- Two more ways to see the boss abilities Boss Timers lists:
--
--   * The track: a strip standing for the next few seconds. Each ability is
--     its icon, sliding along it toward the line at the end; a mark shows
--     where five seconds is. Easy to read at a glance in a busy fight.
--   * Icon alerts: once an ability is inside its warning time, a large icon
--     with a countdown and a glow, the way a raid warning would look.
--
-- Fed by BossEngine and sharing Boss Timers' per-ability settings (an
-- ability switched off there is off here; its own text is shown here).
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,   -- off until the player switches it on

    track        = true,
    trackSeconds = 20,      -- how far ahead the track looks
    trackLength  = 360,
    trackWidth   = 30,      -- also the icon size
    vertical     = false,   -- icons move down instead of left
    reverse      = false,   -- toward the other end
    showNames    = true,
    markAt       = 5,       -- the line across the track; 0 = none

    icons        = true,
    iconSize     = 56,
    iconMax      = 4,
    iconGlow     = true,
    iconGrowUp   = false,

    scale        = 1,
    locked       = false,
}

-- Smooth enough for icons sliding along the track; faster cost more than
-- it showed.
local TICK = 0.05

local function BySoonest(a, b) return a.trackLeft < b.trackLeft end

local Engine = OxedHub.BossEngine
local settings
local optionsWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    return false
end
local track, iconAnchor
local trackIcons, alertIcons = {}, {}
local ticker
local idleUntil = 0       -- see Tick: no work until an ability comes near
local active = false

local function Own(ev)
    if not (ev.encounterID and ev.abilityID) then return nil end
    local timers = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.bosstimers
    local list = timers and timers.abilities
    return list and list[tostring(ev.encounterID) .. ":" .. tostring(ev.abilityID)] or nil
end

local function TimersSetting(key, fallback)
    local timers = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.bosstimers
    local value = timers and timers[key]
    if value == nil then return fallback end
    return value
end

local function WantedHere()
    local _, kind = IsInInstance()
    if kind == "party" then return TimersSetting("inDungeons", true) end
    if kind == "raid" then return TimersSetting("inRaids", true) end
    return TimersSetting("elsewhere", true)
end

local function Wanted(ev)
    local own = Own(ev)
    if own and own.off then return false end
    if not ev.ability then return not TimersSetting("hideUnknown", false) end
    local spec = GetSpecialization and GetSpecialization()
    local role = spec and GetSpecializationRole(spec)
    if ev.ability.kind == "tank" and TimersSetting("hideTankForOthers", true) and role and role ~= "TANK" then return false end
    if ev.ability.kind == "healer" and TimersSetting("hideHealerForOthers", false) and role and role ~= "HEALER" then return false end
    return true
end

-- Sets a label to the ability's text without ever testing a secret name.
local function SetName(fontString, ev)
    local own = Own(ev)
    if own and own.text and own.text ~= "" then
        fontString:SetText(own.text)
    else
        fontString:SetText(ev.name)
    end
end

local function KindColour(ev)
    local colours = TimersSetting("colours", nil)
    local kind = ev.ability and ev.ability.kind or "other"
    local c = colours and colours[kind]
    if c then return c[1], c[2], c[3] end
    return 1, 0.55, 0.1
end

-- ── Frames ─────────────────────────────────────────────────────────────────

local function Movable(frame, key, label, x, y)
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
    frame.hint = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.hint:SetAllPoints()
    frame.hint:SetColorTexture(0, 0.6, 1, 0.25)
    frame.hintText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hintText:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    frame.hintText:SetText(label)
end

local function Build()
    if track then return end
    track = CreateFrame("Frame", "OxedHubBossTrack", UIParent)
    Movable(track, "track", "Boss Track: drag me", 0, -160)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(0, 0, 0, 0.45)
    track.goal = track:CreateTexture(nil, "ARTWORK")
    track.goal:SetColorTexture(1, 0.82, 0, 0.9)
    track.mark = track:CreateTexture(nil, "ARTWORK")
    track.mark:SetColorTexture(1, 0.2, 0.15, 0.8)

    iconAnchor = CreateFrame("Frame", "OxedHubBossIcons", UIParent)
    Movable(iconAnchor, "icons", "Boss Track icons: drag me", 0, 120)
end

local function TrackIcon(i)
    local icon = trackIcons[i]
    if not icon then
        icon = CreateFrame("Frame", nil, track)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.border = icon:CreateTexture(nil, "BORDER")
        icon.border:SetPoint("TOPLEFT", -1, 1)
        icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
        icon.name = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        icon.name:SetWordWrap(false)
        trackIcons[i] = icon
    end
    return icon
end

local function AlertIcon(i)
    local icon = alertIcons[i]
    if not icon then
        icon = CreateFrame("Frame", nil, iconAnchor)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon.count = icon:CreateFontString(nil, "OVERLAY")
        icon.count:SetPoint("CENTER")
        icon.name = icon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        icon.name:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        icon.name:SetWordWrap(false)
        -- The glow pulses on its own texture, never on the icon frame.
        icon.glow = icon:CreateTexture(nil, "OVERLAY")
        icon.glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        icon.glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        icon.glow:SetPoint("TOPLEFT", -12, 12)
        icon.glow:SetPoint("BOTTOMRIGHT", 12, -12)
        icon.glow:SetBlendMode("ADD")
        local pulse = icon.glow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local fade = pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.3)
        fade:SetDuration(0.4)
        icon.pulse = pulse
        alertIcons[i] = icon
    end
    return icon
end

local function Restyle()
    if not track then return end
    -- Settings changed: every track icon draws itself again on the next tick.
    for _, icon in ipairs(trackIcons) do icon.ev = nil end
    idleUntil = 0
    track:SetScale(settings.scale)
    iconAnchor:SetScale(settings.scale)
    local long, wide = settings.trackLength, settings.trackWidth
    if settings.vertical then track:SetSize(wide, long) else track:SetSize(long, wide) end

    -- The goal line sits at the end the icons travel to.
    track.goal:ClearAllPoints()
    track.mark:ClearAllPoints()
    local goalEnd
    if settings.vertical then
        goalEnd = settings.reverse and "TOP" or "BOTTOM"
        track.goal:SetSize(wide + 6, 3)
        track.goal:SetPoint(goalEnd, track, goalEnd, 0, 0)
    else
        goalEnd = settings.reverse and "RIGHT" or "LEFT"
        track.goal:SetSize(3, wide + 6)
        track.goal:SetPoint(goalEnd, track, goalEnd, 0, 0)
    end
    local markShown = settings.markAt > 0 and settings.markAt < settings.trackSeconds
    track.mark:SetShown(markShown)
    if markShown then
        local offset = long * settings.markAt / settings.trackSeconds
        if settings.vertical then
            track.mark:SetSize(wide, 2)
            track.mark:SetPoint(goalEnd, track, goalEnd, 0, settings.reverse and -offset or offset)
        else
            track.mark:SetSize(2, wide)
            track.mark:SetPoint(goalEnd, track, goalEnd, settings.reverse and -offset or offset, 0)
        end
    end

    local font = GameFontNormalHuge and GameFontNormalHuge:GetFont() or STANDARD_TEXT_FONT
    for _, icon in ipairs(alertIcons) do
        icon:SetSize(settings.iconSize, settings.iconSize)
        icon.count:SetFont(font, math.floor(settings.iconSize * 0.5), "THICKOUTLINE")
    end
    iconAnchor:SetSize(settings.iconSize, settings.iconSize)

    local editing = settings.enabled and not settings.locked and OptionsOpen()
    track:SetShown(active and settings.track and (editing or ticker ~= nil))
    iconAnchor:SetShown(active and settings.icons)
    for _, frame in ipairs({ track, iconAnchor }) do
        frame.hint:SetShown(editing)
        frame.hintText:SetShown(editing)
        frame:EnableMouse(editing)
    end
end

-- ── Each tick ──────────────────────────────────────────────────────────────

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

-- ⚠ Nothing to draw until the next ability reaches the track or its warning
-- time: the ticker runs 20 times a second for the whole fight, and most of
-- that time every ability is still far away. Until then a tick returns at
-- once. A new event resets it.


local list = {}
local function Tick()
    if GetTime() < idleUntil then return end
    wipe(list)
    local any = false
    local here = WantedHere()
    for _, ev in pairs(Engine:GetEvents()) do
        any = true
        if here and Engine:IsActive(ev) and Wanted(ev) then
            local left = Engine:TimeLeft(ev)
            if left > 0 then
                ev.trackLeft = left
                list[#list + 1] = ev
            end
        end
    end
    table.sort(list, BySoonest)

    -- The track.
    local used = 0
    if settings.track then
        local long, wide = settings.trackLength, settings.trackWidth
        for _, ev in ipairs(list) do
            if ev.trackLeft <= settings.trackSeconds then
                used = used + 1
                local icon = TrackIcon(used)
                -- What the icon shows changes only when another ability takes
                -- its place; only the position moves on every tick.
                if icon.ev ~= ev or icon.wide ~= wide then
                    icon.ev, icon.wide = ev, wide
                    icon:SetSize(wide, wide)
                    icon.tex:SetTexture(ev.icon)
                    icon.border:SetColorTexture(KindColour(ev))
                    if settings.showNames then SetName(icon.name, ev) end
                end
                local offset = (long - wide) * ev.trackLeft / settings.trackSeconds
                icon:ClearAllPoints()
                icon.name:ClearAllPoints()
                if settings.vertical then
                    local goal = settings.reverse and "TOP" or "BOTTOM"
                    icon:SetPoint(goal, track, goal, 0, settings.reverse and -offset or offset)
                    icon.name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                else
                    local goal = settings.reverse and "RIGHT" or "LEFT"
                    icon:SetPoint(goal, track, goal, settings.reverse and -offset or offset, 0)
                    icon.name:SetPoint("BOTTOM", icon, "TOP", 0, 2)
                end
                icon.name:SetShown(settings.showNames)
                icon:Show()
            end
        end
    end
    for i = used + 1, #trackIcons do trackIcons[i]:Hide() end

    -- Icon alerts: abilities inside their warning time.
    local shown = 0
    if settings.icons then
        local warnDefault = TimersSetting("warnAt", 5)
        for _, ev in ipairs(list) do
            local own = Own(ev)
            local warnAt = (own and own.warnAt) or warnDefault
            if ev.trackLeft <= warnAt and shown < settings.iconMax then
                shown = shown + 1
                local icon = AlertIcon(shown)
                if not icon.styled then
                    icon.styled = true
                    Restyle()
                end
                icon.tex:SetTexture(ev.icon)
                icon.count:SetText(tostring(math.ceil(ev.trackLeft)))
                SetName(icon.name, ev)
                icon:ClearAllPoints()
                local step = (shown - 1) * (settings.iconSize + 22)
                if settings.iconGrowUp then
                    icon:SetPoint("BOTTOM", iconAnchor, "BOTTOM", 0, step)
                else
                    icon:SetPoint("TOP", iconAnchor, "TOP", 0, -step)
                end
                icon.glow:SetShown(settings.iconGlow)
                if settings.iconGlow and not icon.pulse:IsPlaying() then icon.pulse:Play() end
                icon:Show()
            end
        end
    end
    for i = shown + 1, #alertIcons do
        alertIcons[i]:Hide()
        alertIcons[i].pulse:Stop()
    end

    if not any then
        StopTicker()
        Restyle()
        return
    end

    -- Nothing on screen: sleep until the soonest ability is close enough.
    if used == 0 and shown == 0 then
        if not here then
            idleUntil = GetTime() + 1
            return
        end
        local gap
        local warnDefault = TimersSetting("warnAt", 5)
        for _, ev in ipairs(list) do
            local own = Own(ev)
            local near = math.max(settings.track and settings.trackSeconds or 0,
                settings.icons and ((own and own.warnAt) or warnDefault) or 0)
            local wait = ev.trackLeft - near
            if not gap or wait < gap then gap = wait end
        end
        if gap and gap > 0.2 then idleUntil = GetTime() + math.min(gap - 0.1, 2) end
    end
end

local function StartTicker()
    if ticker or not active then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
    Restyle()
end

Engine:AddListener({
    OnEventAdded = function()
        idleUntil = 0
        StartTicker()
    end,
})

local function Start()
    active = true
    Build()
    Engine:Start()
    if next(Engine:GetEvents()) then StartTicker() end
    Restyle()
end

local function Stop()
    active = false
    StopTicker()
    Engine:Stop()
    if track then track:Hide(); iconAnchor:Hide() end
end

local function ShowTest()
    if not settings.enabled then
        print("|cff00ccffOxedHub|r Switch Boss Track on first.")
        return
    end
    Engine:AddTestEvents({
        { name = "Test: Crushing Blow", icon = 136025, duration = 6, kind = "tank" },
        { name = "Test: Shadow Burst", icon = 136197, duration = 11, kind = "mechanic" },
        { name = "Test: Fixate", icon = 136219, duration = 16, kind = "targeted" },
    })
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Boss Track", 480, 710)
        optionsWindow = w
        w:HookScript("OnShow", function() Restyle() end)
        w:HookScript("OnHide", function() Restyle() end)
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(170, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        test:SetText("Show a test")
        test:SetScript("OnClick", ShowTest)
        w.cursorY = w.cursorY - 32
        w:AddCheckbox(settings, "locked", "Lock", "Unlocked, drag the blue boxes.", Restyle)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Restyle)

        w:AddCheckbox(settings, "track", "The track", nil, Restyle)
        w:AddSlider(settings, "trackSeconds", "Looks ahead", 5, 60, 1, "%s: %d s", Restyle)
        w:AddSlider(settings, "trackLength", "Length", 150, 800, 10, "%s: %d", Restyle)
        w:AddSlider(settings, "trackWidth", "Thickness", 16, 60, 1, "%s: %d", Restyle)
        w:AddSlider(settings, "markAt", "Line at", 0, 15, 1, "%s: %d s (0 = none)", Restyle)
        w:AddCheckbox(settings, "vertical", "Up and down instead of across", nil, Restyle)
        w:AddCheckbox(settings, "reverse", "Toward the other end", nil, Restyle)
        w:AddCheckbox(settings, "showNames", "Names by the icons")

        w:AddCheckbox(settings, "icons", "Large icon alerts", nil, Restyle)
        w:AddSlider(settings, "iconSize", "Icon size", 32, 120, 2, "%s: %d", Restyle)
        w:AddSlider(settings, "iconMax", "Icons at once", 1, 6, 1, "%s: %d")
        w:AddCheckbox(settings, "iconGlow", "Glow")
        w:AddCheckbox(settings, "iconGrowUp", "Stack upwards")
        w:AddModuleLinks("Works together with", { "bosstimers", "bossalerts", "trashtimers", "enemycasts", "partyinterrupts", "kickbar", "bosshealth" })
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
    local config = OxedHubDB.modules.bosstrack
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bosstrack = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bosstrack",
        name     = "Boss Track",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "boss", "track", "timeline", "icons", "alert", "raid", "dungeon" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Boss abilities as icons sliding toward a line, and big icon alerts as they land.",
        icon     = "Interface\\Icons\\Ability_Hunter_MarkedForDeath",

        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        quick = { { text = "Test", func = function() ShowTest() end } },
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
