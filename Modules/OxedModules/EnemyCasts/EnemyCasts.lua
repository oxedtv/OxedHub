-- ============================================================================
-- Enemy Casts (built-in OxedHub module)
-- One list of every enemy cast going on around you: the enemies with a
-- nameplate and the bosses. Each bar shows the spell, who it is aimed at, and
-- turns grey when it cannot be interrupted.
--
-- ⚠ In a fight almost everything about an enemy cast is a secret value: its
-- name, icon, timing, target and whether it can be interrupted. None of it is
-- read here. The game hands back a duration object for the cast, the bar is
-- given that object (SetTimerDuration) and fills itself; the name, icon and
-- target go straight to SetText / SetTexture; "can it be interrupted" and
-- "is it aimed at me" go to the *FromBoolean setters, which let the game
-- decide. Lua only ever learns that a cast started or stopped on a unit.
--
-- Because the time left cannot be read, bars are listed in the order the
-- casts started, newest last, not by time left.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,   -- off until the player switches it on

    nameplates   = true,    -- enemies with a nameplate
    bosses       = true,    -- boss1 to boss5
    inDungeons   = true,
    inRaids      = true,
    elsewhere    = false,

    showTarget   = true,    -- who the cast is aimed at
    showOnYou    = true,    -- a marker when it is aimed at you
    showTime     = true,
    maxBars      = 6,
    width        = 260,
    height       = 20,
    spacing      = 2,
    fontSize     = 12,
    growUp       = false,
    scale        = 1,
    locked       = false,
    background   = 0.6,
}

local Engine = OxedHub.BossEngine
local settings
local optionsWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    return false
end
local anchor
local bars = {}          -- pool of bar frames
local byUnit = {}        -- [unit] = bar in use
local order = {}         -- bars in the order their casts started
local active = false
local eventFrame = CreateFrame("Frame")

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE",
}

-- ── Which units ────────────────────────────────────────────────────────────

local function WantedHere()
    local _, kind = IsInInstance()
    if kind == "party" then return settings.inDungeons end
    if kind == "raid" then return settings.inRaids end
    return settings.elsewhere
end

local function IsBossUnit(unit)
    return type(unit) == "string" and unit:match("^boss%d$") ~= nil
end

local function IsPlateUnit(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

-- true, false or nil ("cannot tell": treated as an enemy, a friendly
-- nameplate casting is rare and harmless to show).
local function IsEnemy(unit)
    local ok, value = pcall(UnitCanAttack, "player", unit)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value and true or false
end

local function Tracked(unit)
    if IsBossUnit(unit) then return settings.bosses end
    if IsPlateUnit(unit) then
        if not settings.nameplates then return false end
        -- A boss also has a nameplate: show it once, as the boss.
        if settings.bosses then
            for i = 1, 5 do
                local ok, same = pcall(UnitIsUnit, unit, "boss" .. i)
                if ok and not (issecretvalue and issecretvalue(same)) and same then return false end
            end
        end
        return IsEnemy(unit) ~= false
    end
    return false
end

-- ── Bars ────────────────────────────────────────────────────────────────────

local NORMAL = CreateColor(1, 0.6, 0.1, 1)
local LOCKED = CreateColor(0.55, 0.55, 0.55, 1)

local function SavePosition()
    local point, _, rel, x, y = anchor:GetPoint()
    settings.point, settings.rel, settings.x, settings.y = point, rel, x, y
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "OxedHubEnemyCastsAnchor", UIParent)
    anchor:SetPoint(settings.point or "CENTER", UIParent, settings.rel or "CENTER", settings.x or -300, settings.y or 0)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
    anchor.hint = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.hint:SetAllPoints()
    anchor.hint:SetColorTexture(0, 0.6, 1, 0.25)
    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.text:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    anchor.text:SetText("Enemy Casts: drag me")
end

local function NewBar()
    local bar = CreateFrame("Frame", nil, anchor)
    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill:SetMinMaxValues(0, 1)
    bar.bg = bar.fill:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.name = bar.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.time = bar.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.time:SetJustifyH("RIGHT")
    -- The target sits on its own frame so the game can hide it when the
    -- cast has no target worth naming (a secret yes/no).
    bar.targetHolder = CreateFrame("Frame", nil, bar.fill)
    bar.targetHolder:SetAllPoints()
    bar.target = bar.targetHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.target:SetJustifyH("RIGHT")
    bar.target:SetWordWrap(false)
    bar.onYou = CreateFrame("Frame", nil, bar)
    bar.onYouTex = bar.onYou:CreateTexture(nil, "OVERLAY")
    bar.onYouTex:SetAllPoints()
    bar.onYouTex:SetAtlas("icons_64x64_deadly")
    return bar
end

local function LayoutBar(bar)
    local h = settings.height
    bar:SetSize(settings.width, h)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icon:SetSize(h, h)
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", h + 2, 0)
    bar.fill:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.bg:SetColorTexture(0, 0, 0, settings.background)
    local font = GameFontHighlightSmall:GetFont()
    for _, fs in ipairs({ bar.name, bar.time, bar.target }) do fs:SetFont(font, settings.fontSize, "OUTLINE") end
    bar.time:ClearAllPoints()
    bar.time:SetPoint("RIGHT", bar.fill, "RIGHT", -4, 0)
    bar.time:SetWidth(settings.showTime and 36 or 1)
    bar.time:SetShown(settings.showTime)
    bar.target:ClearAllPoints()
    bar.target:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)
    bar.target:SetWidth(math.floor((settings.width - h) * 0.35))
    bar.targetHolder:SetShown(settings.showTarget)
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", bar.fill, "LEFT", 4, 0)
    bar.name:SetPoint("RIGHT", settings.showTarget and bar.target or bar.time, "LEFT", -4, 0)
    bar.onYou:ClearAllPoints()
    bar.onYou:SetSize(h + 4, h + 4)
    bar.onYou:SetPoint("RIGHT", bar.icon, "LEFT", -2, 0)
end

local function Relayout()
    if not anchor then return end
    anchor:SetScale(settings.scale)
    anchor:SetSize(settings.width, settings.height)
    local editing = settings.enabled and not settings.locked and OptionsOpen()
    anchor.hint:SetShown(editing)
    anchor.text:SetShown(editing)
    anchor:EnableMouse(editing)
    anchor:SetShown(active)
    local shown = 0
    for _, bar in ipairs(order) do
        shown = shown + 1
        if shown > settings.maxBars then
            bar:Hide()
        else
            LayoutBar(bar)
            local step = (shown - 1) * (settings.height + settings.spacing)
            bar:ClearAllPoints()
            if settings.growUp then
                bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, step)
            else
                bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -step)
            end
            bar:Show()
        end
    end
end

local function Release(unit)
    local bar = byUnit[unit]
    if not bar then return end
    byUnit[unit] = nil
    for i, b in ipairs(order) do
        if b == bar then table.remove(order, i); break end
    end
    if bar.binding and bar.binding.SetEnabled then pcall(bar.binding.SetEnabled, bar.binding, false) end
    bar:Hide()
    table.insert(bars, bar)
    Relayout()
end

-- Shows the time left from the duration object without reading it.
local function BindTime(bar, duration)
    bar.time:SetText("")
    if not settings.showTime then return end
    if not (C_DurationUtil and C_DurationUtil.CreateDurationTextBinding) then return end
    local ok = pcall(function()
        bar.binding = bar.binding or C_DurationUtil.CreateDurationTextBinding()
        local binding = bar.binding
        binding:SetFontString(bar.time)
        binding:SetDuration(duration)
        if binding.SetTextFormat then binding:SetTextFormat("%.1f") end
        binding:SetEnabled(true)
    end)
    if not ok then bar.time:SetText("") end
end

local function SetInterruptColour(bar, notInterruptible)
    local tex = bar.fill:GetStatusBarTexture()
    if tex and tex.SetVertexColorFromBoolean then
        tex:SetVertexColorFromBoolean(notInterruptible, LOCKED, NORMAL)
    else
        tex:SetVertexColor(NORMAL:GetRGBA())
    end
end

-- Fills a bar from what the game says about the unit's current cast.
-- Returns false when the unit is not casting.
local function Fill(bar, unit)
    local castDuration = UnitCastingDuration and UnitCastingDuration(unit)
    local channelDuration = UnitChannelDuration and UnitChannelDuration(unit)
    local duration = castDuration or channelDuration
    if not duration then return false end

    local name, texture, notInterruptible, _
    if channelDuration and not castDuration then
        name, _, texture, _, _, _, notInterruptible = UnitChannelInfo(unit)
    else
        name, _, texture, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
    end
    -- Never "name or ...": testing a secret is itself the error.
    bar.name:SetText(name)
    bar.icon:SetTexture(texture)

    if bar.fill.SetTimerDuration then
        local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
        bar.fill:SetTimerDuration(duration, interpolation, (channelDuration and not castDuration) and 1 or 0)
        if bar.fill.SetToTargetValue then bar.fill:SetToTargetValue() end
    end
    SetInterruptColour(bar, notInterruptible)
    BindTime(bar, duration)

    -- The *FromBoolean setters take the secret as it is; pcall covers a nil
    -- (no target) without Lua ever testing the value.
    bar.target:SetText(nil)
    bar.targetHolder:SetAlpha(1)
    if UnitSpellTargetName then
        bar.target:SetText(UnitSpellTargetName(unit))
        if UnitShouldDisplaySpellTargetName and bar.targetHolder.SetAlphaFromBoolean then
            pcall(bar.targetHolder.SetAlphaFromBoolean, bar.targetHolder,
                UnitShouldDisplaySpellTargetName(unit), 1, 0)
        end
    end
    bar.onYou:Hide()
    if settings.showOnYou and PlayerIsSpellTarget and bar.onYou.SetAlphaFromBoolean then
        local ok = pcall(bar.onYou.SetAlphaFromBoolean, bar.onYou, PlayerIsSpellTarget(unit), 1, 0)
        if ok then bar.onYou:Show() end
    end
    return true
end

local function Update(unit)
    if not active or not Tracked(unit) or not WantedHere() then Release(unit); return end
    local bar = byUnit[unit]
    local fresh = false
    if not bar then
        bar = table.remove(bars) or NewBar()
        fresh = true
    end
    if not Fill(bar, unit) then
        if not fresh then Release(unit) else table.insert(bars, bar) end
        return
    end
    if fresh then
        byUnit[unit] = bar
        table.insert(order, bar)
    end
    Relayout()
end

local function ClearAll()
    for unit in pairs(byUnit) do Release(unit) end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_REMOVED" then
        Release(unit)
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        if unit then Update(unit) end
        if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
            for i = 1, 5 do Update("boss" .. i) end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ClearAll()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        -- A channel can follow a cast at once: look again rather than drop.
        if byUnit[unit] then Update(unit) end
    elseif unit and (IsBossUnit(unit) or IsPlateUnit(unit)) then
        Update(unit)
    end
end)

local function Start()
    active = true
    CreateAnchor()
    for _, e in ipairs(CAST_EVENTS) do eventFrame:RegisterEvent(e) end
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Relayout()
end

local function Stop()
    active = false
    eventFrame:UnregisterAllEvents()
    ClearAll()
    if anchor then anchor:Hide() end
end

-- ── Test ───────────────────────────────────────────────────────────────────

local function ShowTest()
    if not settings.enabled then
        print("|cff00ccffOxedHub|r Switch Enemy Casts on first.")
        return
    end
    if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return end
    local samples = {
        { "Test: Shadow Bolt", 136197, 3, false, "Healer" },
        { "Test: Mind Shatter", 136207, 5, true, "Tank" },
        { "Test: Flame Wave", 135808, 4, false, "" },
    }
    for i, s in ipairs(samples) do
        local unit = "test" .. i
        Release(unit)
        local bar = table.remove(bars) or NewBar()
        local duration = C_DurationUtil.CreateDuration()
        duration:SetTimeFromEnd(GetTime() + s[3], s[3], 1)
        bar.name:SetText(s[1])
        bar.icon:SetTexture(s[2])
        if bar.fill.SetTimerDuration then
            bar.fill:SetTimerDuration(duration, 0, 0)
            if bar.fill.SetToTargetValue then bar.fill:SetToTargetValue() end
        end
        bar.fill:GetStatusBarTexture():SetVertexColor((s[4] and LOCKED or NORMAL):GetRGBA())
        BindTime(bar, duration)
        bar.target:SetText(s[5])
        bar.targetHolder:SetAlpha(1)
        bar.onYou:SetShown(settings.showOnYou and i == 1)
        bar.onYou:SetAlpha(1)
        byUnit[unit] = bar
        table.insert(order, bar)
        C_Timer.After(s[3], function() Release(unit) end)
    end
    Relayout()
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Enemy Casts", 480, 710)
        optionsWindow = w
        w:HookScript("OnShow", function() Relayout() end)
        w:HookScript("OnHide", function() Relayout() end)
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(170, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        test:SetText("Show test bars")
        test:SetScript("OnClick", ShowTest)
        w.cursorY = w.cursorY - 32

        w:AddCheckbox(settings, "nameplates", "Enemies with a nameplate")
        w:AddCheckbox(settings, "bosses", "Bosses")
        w:AddCheckbox(settings, "inDungeons", "In dungeons")
        w:AddCheckbox(settings, "inRaids", "In raids")
        w:AddCheckbox(settings, "elsewhere", "Elsewhere")
        w:AddCheckbox(settings, "showTarget", "Show who the cast is aimed at", nil, Relayout)
        w:AddCheckbox(settings, "showOnYou", "Mark casts aimed at you")
        w:AddCheckbox(settings, "showTime", "Show the time left", nil, Relayout)
        w:AddCheckbox(settings, "locked", "Lock the bars", "Unlocked, drag the blue box.", Relayout)
        w:AddCheckbox(settings, "growUp", "Grow upwards", nil, Relayout)
        w:AddSlider(settings, "maxBars", "Bars at most", 1, 15, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "width", "Width", 140, 500, 10, "%s: %d", Relayout)
        w:AddSlider(settings, "height", "Bar height", 12, 40, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "fontSize", "Text size", 8, 24, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Relayout)
        w:AddNote("Grey bars cannot be interrupted. In a fight the game decides that, "
            .. "and who a cast is aimed at, itself.")
        w:AddModuleLinks("Works together with", { "bosstimers", "bossalerts", "bosstrack", "trashtimers", "partyinterrupts", "kickbar", "bosshealth" })
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
    local config = OxedHubDB.modules.enemycasts
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.enemycasts = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "enemycasts",
        name     = "Enemy Casts",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "cast", "castbar", "enemy", "nameplate", "boss", "interrupt", "kick", "mythic" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Every enemy and boss cast in one list, with its target. Grey if it cannot be kicked.",
        icon     = "Interface\\Icons\\Spell_Shadow_ShadowBolt",

        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        quick = { { text = "Test bars", func = function() ShowTest() end } },
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
