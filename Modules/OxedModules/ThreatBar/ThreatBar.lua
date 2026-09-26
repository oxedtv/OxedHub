-- ============================================================================
-- Threat Bar (built-in OxedHub module)
-- A bar under every enemy nameplate: how close your threat is to whoever is
-- holding that enemy. Green while you are nowhere near, red when the next hit
-- takes it off them, with a glow around the plate as the warning.
--
-- ⚠ On 12.0 the threat figures are secret values in combat. A secret cannot be
-- compared, added to or printed: touching one is an error. That would leave
-- the bar grey and mute in every fight, which is the only time it matters --
-- so the colours are drawn without ever reading the number:
--
--   A status bar clamps whatever it is given to its own range. A bar whose
--   range is 79.99 to 80 therefore sits EMPTY below 80 and FULL at 80 or
--   above, whoever does the comparing. Stack one of those per colour step
--   over the fill, hand each the same secret, and the bar paints itself: the
--   highest step that filled is the colour you see. The same trick switches
--   the flash on. Nothing here ever reads the number.
--
--   "Is the enemy on you" is a secret too, and goes to SetAlphaFromBoolean,
--   which lets the game decide what to show.
--
-- ⚠ Threat events arrive many times a second for every enemy in a pull. They
-- only mark a bar as stale; the redraw runs on a ticker.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    style       = "auto",  -- auto, damage or tank colours
    smooth      = true,    -- damage colours fade green to red; off uses steps
    texture     = "game",  -- game or flat

    showText    = true,
    textSize    = 10,
    showName    = true,    -- who is holding the enemy, under the bar

    width       = 0,       -- 0 follows the nameplate's own width
    height      = 9,
    offsetY     = -3,
    alpha       = 1,

    warnAt      = 80,      -- the percentage the warning starts at
    flash       = true,
    glow        = true,    -- a glow around the whole nameplate
    sound       = false,

    onlyGroup   = false,
    onlyCombat  = true,

    rounded     = true,    -- round the bar's ends
    otherPlates = true,    -- sit under Platynator's (or another addon's) bar
}

local settings
local optionsWindow
local bars = {}         -- one per nameplate unit token
local dirty = {}
local ticker
local previewing = false
local lastWarn = 0
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ccffOxedHub Threat:|r "
local REDRAW = 0.1
local WARN_GAP = 3
local EDGE = 0.01       -- how narrow a switch bar's range is; see the header

local TEXTURES = {
    game = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
}

-- Our own art: a white rectangle with its corners rounded by a third of its
-- height, so a bar keeps its shape and only loses the sharp corners. Half the
-- height turned the ends into semicircles, which was far too much. Used as a
-- mask, never drawn on its own.
local PILL = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Bars\\pill"

-- ── Colours ─────────────────────────────────────────────────────────────────
-- Status from UnitDetailedThreatSituation: 0 below whoever holds it, 1 above
-- them and about to pull, 2 holding it but barely, 3 holding it securely.

local DAMAGE = {
    [0] = { 0.40, 0.75, 0.40 },
    [1] = { 1.00, 0.82, 0.20 },
    [2] = { 1.00, 0.50, 0.15 },
    [3] = { 0.95, 0.20, 0.20 },
}
local TANK = {
    [0] = { 0.95, 0.20, 0.20 },
    [1] = { 1.00, 0.50, 0.15 },
    [2] = { 1.00, 0.82, 0.20 },
    [3] = { 0.40, 0.75, 0.40 },
}
local GLOW_COLOUR = { 1, 0.35, 0.15 }

-- Green at nothing, yellow halfway, red at the top: one colour per whole
-- percent, worked out once.
local FADE = {}
do
    local green, yellow, red = { 0.30, 0.80, 0.35 }, { 1, 0.82, 0.20 }, { 0.95, 0.20, 0.20 }
    for percent = 0, 100 do
        local from, to, t = green, yellow, percent / 50
        if percent > 50 then from, to, t = yellow, red, (percent - 50) / 50 end
        FADE[percent] = {
            from[1] + (to[1] - from[1]) * t,
            from[2] + (to[2] - from[2]) * t,
            from[3] + (to[3] - from[3]) * t,
        }
    end
end

-- The colour steps the switch bars are built from: the bar's own colour, then
-- one step per threshold. Ten steps read as a fade; two read as a warning.
local FADE_STEPS = { base = FADE[0], list = {} }
for t = 10, 100, 10 do FADE_STEPS.list[#FADE_STEPS.list + 1] = { t, FADE[t] } end

local DAMAGE_STEPS = { base = DAMAGE[0], list = {
    { 60, DAMAGE[1] }, { 80, DAMAGE[2] }, { 100, DAMAGE[3] },
} }
-- A tank's percentage sits at 100 while the enemy is on them and drops below
-- it the moment somebody else has it.
local TANK_STEPS = { base = TANK[0], list = { { 100, TANK[3] } } }

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function TankStyle()
    if settings.style == "tank" then return true end
    if settings.style == "damage" then return false end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    return role == "TANK"
end

local function Steps()
    if TankStyle() then return TANK_STEPS end
    return settings.smooth and FADE_STEPS or DAMAGE_STEPS
end

-- ── Building a bar ──────────────────────────────────────────────────────────

local function PlateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and plate or nil
end

-- Another nameplate addon's health bar. Platynator (and others like it) moves
-- Blizzard's UnitFrame into a hidden frame and draws its own plate, so a bar
-- parented to Blizzard's health bar was hidden along with it. Their plate is
-- still a child of the nameplate: the widest visible StatusBar in it is the
-- health bar. Looked for a few levels deep, our own frames skipped, and kept
-- per plate while it stays visible.
local foreignBar = setmetatable({}, { __mode = "k" })

-- ⚠ A plate holds aura buttons, and on 12.0 their IsVisible and size can be
-- secret: testing one is the error. Every answer goes through Plain, which
-- gives nil for a secret, and buttons are never walked into at all.
local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- true, false, or nil when the game will not say (a secret, in combat).
local function Shown(frame)
    local ok, visible = pcall(frame.IsShown, frame)
    if not ok then return nil end
    visible = Plain(visible)
    if visible == nil then return nil end
    return visible == true
end

-- ⚠ Whether Blizzard's plate is in use is read from where it sits, not from
-- whether it is visible: visibility can be secret in combat, and that read
-- as "hidden" sent every plate off to look for another addon's bar that
-- was then skipped too, so the bar only ever showed out of combat. An addon
-- that takes over (Platynator) moves the UnitFrame to a parent of its own.
local function BlizzardInUse(plate, frame)
    local ok, parent = pcall(frame.GetParent, frame)
    return ok and parent == plate
end

local function FindForeignHealth(plate)
    local cached = foreignBar[plate]
    -- Platynator hands its plates from one nameplate to another, so the one
    -- found last time must still be inside this nameplate.
    if cached and Shown(cached) ~= false then
        local parent, steps = cached, 0
        while parent and steps < 8 do
            if parent == plate then return cached end
            parent, steps = parent:GetParent(), steps + 1
        end
    end
    foreignBar[plate] = nil

    local best, bestWidth
    local function Walk(frame, depth)
        if depth > 5 then return end
        local okKids, kids = pcall(function() return { frame:GetChildren() } end)
        if not okKids then return end
        for _, child in ipairs(kids) do
            -- ⚠ Aura buttons on a plate are forbidden objects: any method
            -- call on one but IsForbidden is an error. Asked first, and the
            -- type read inside pcall in case something else is too.
            local forbidden = child.IsForbidden and child:IsForbidden()
            local okType, isButton = false, true
            if not forbidden then
                okType, isButton = pcall(child.IsObjectType, child, "Button")
            end
            if okType and not isButton and not child._oxThreat and child ~= plate.UnitFrame
                and Shown(child) ~= false then
                if child:IsObjectType("StatusBar") then
                    local ok, width = pcall(child.GetWidth, child)
                    width = ok and Plain(width) or 0
                    if width > 20 and (not bestWidth or width > bestWidth) then
                        best, bestWidth = child, width
                    end
                end
                Walk(child, depth + 1)
            end
        end
    end
    Walk(plate, 1)
    foreignBar[plate] = best
    return best
end

-- Shared with KickBar: the health bar actually on screen for a nameplate,
-- Blizzard's or another addon's, or nil when neither can be found.
function OxedHub.VisiblePlateBar(plate)
    if not plate then return nil end
    local frame = plate.UnitFrame
    if frame and BlizzardInUse(plate, frame) then
        return frame.healthBar or frame.HealthBar or frame
    end
    return FindForeignHealth(plate)
end

-- The health bar to sit under: Blizzard's while it is shown, another addon's
-- when that one has taken over, the plate itself as a last resort.
local function AnchorFor(plate)
    if not plate then return nil end
    local frame = plate.UnitFrame
    if frame and BlizzardInUse(plate, frame) then
        return frame.healthBar or frame.HealthBar or frame
    end
    if settings and settings.otherPlates ~= false then
        local found = FindForeignHealth(plate)
        if found then return found end
    end
    if frame then return frame.healthBar or frame.HealthBar or frame end
    return plate
end

local function NewBar()
    local bar = CreateFrame("StatusBar", nil, UIParent)
    bar._oxThreat = true   -- never mistaken for another addon's health bar
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    bar.border = bar:CreateTexture(nil, "BACKGROUND", nil, -2)
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.border:SetColorTexture(0, 0, 0, 0.9)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.10, 0.10, 0.12, 0.8)

    -- One mask for everything drawn inside the bar, one a pixel larger for
    -- the border, so the border keeps its own rounded outline.
    bar.mask = bar:CreateMaskTexture()
    bar.mask:SetTexture(PILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    bar.mask:SetAllPoints(bar)

    bar.borderMask = bar:CreateMaskTexture()
    bar.borderMask:SetTexture(PILL, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    bar.borderMask:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1)
    bar.borderMask:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    bar.text:SetPoint("CENTER", 0, 0)

    -- Who is holding the enemy, under the bar.
    bar.holder = bar:CreateFontString(nil, "OVERLAY", "SystemFont_Shadow_Small")
    bar.holder:SetPoint("TOP", bar, "BOTTOM", 0, -1)
    bar.holder:Hide()

    -- The colour steps. Each one is anchored to the fill, so a full switch
    -- covers exactly the filled part and nothing else.
    bar.switches = {}

    -- The flash: a white sheet over the bar whose own texture pulses. It is a
    -- switch too, so a hidden number can still turn it on.
    local flash = CreateFrame("StatusBar", nil, bar)
    flash:SetAllPoints()
    flash:SetStatusBarTexture(TEXTURES.flat)
    flash:SetStatusBarColor(1, 1, 1, 0.45)
    flash:SetMinMaxValues(0, 1)
    flash:SetValue(0)
    flash:Hide()
    local pulse = flash:GetStatusBarTexture():CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.5)
    fade:SetToAlpha(0)
    fade:SetDuration(0.35)
    fade:SetSmoothing("IN_OUT")
    flash.pulse = pulse
    bar.flash = flash

    return bar
end

-- The glow hangs off the nameplate rather than the bar, so it frames the whole
-- plate. Three rings, each fainter than the last.
local RINGS = { 0.85, 0.4, 0.18 }

local function EnsureGlow(bar, plate)
    local host = AnchorFor(plate)
    if bar.glow and bar.glow:GetParent() == plate and bar.glowHost == host then return bar.glow end
    if bar.glow then bar.glow:Hide() end

    local glow = CreateFrame("Frame", nil, plate)
    glow._oxThreat = true
    bar.glowHost = host
    glow:SetFrameLevel((host and host:GetFrameLevel() or 1) + 20)
    glow:SetPoint("TOPLEFT", host, "TOPLEFT", -#RINGS, #RINGS)
    glow:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", #RINGS, -#RINGS)
    glow:Hide()

    for ring, alpha in ipairs(RINGS) do
        local inset = ring - 1
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = glow:CreateTexture(nil, "OVERLAY")
            edge:SetColorTexture(GLOW_COLOUR[1], GLOW_COLOUR[2], GLOW_COLOUR[3], alpha)
            if side == "TOP" then
                edge:SetPoint("TOPLEFT", inset, -inset)
                edge:SetPoint("TOPRIGHT", -inset, -inset)
                edge:SetHeight(1)
            elseif side == "BOTTOM" then
                edge:SetPoint("BOTTOMLEFT", inset, inset)
                edge:SetPoint("BOTTOMRIGHT", -inset, inset)
                edge:SetHeight(1)
            elseif side == "LEFT" then
                edge:SetPoint("TOPLEFT", inset, -inset - 1)
                edge:SetPoint("BOTTOMLEFT", inset, inset + 1)
                edge:SetWidth(1)
            else
                edge:SetPoint("TOPRIGHT", -inset, -inset - 1)
                edge:SetPoint("BOTTOMRIGHT", -inset, inset + 1)
                edge:SetWidth(1)
            end
        end
    end

    -- A switch of its own, so a hidden number can light the glow as well.
    local switch = CreateFrame("StatusBar", nil, glow)
    switch:SetAllPoints()
    switch:SetStatusBarTexture(TEXTURES.flat)
    switch:SetStatusBarColor(GLOW_COLOUR[1], GLOW_COLOUR[2], GLOW_COLOUR[3], 0.12)
    switch:SetMinMaxValues(0, 1)
    switch:SetValue(1)
    glow.switch = switch

    bar.glow = glow
    return glow
end

local function HideExtras(bar)
    if bar.glow then bar.glow:Hide() end
    bar.flash.pulse:Stop()
    bar.flash:Hide()
    bar.holder:Hide()
end

local function Release(unit)
    local bar = bars[unit]
    if not bar then return end
    HideExtras(bar)
    bar:Hide()
    bar:SetParent(UIParent)
    bar:ClearAllPoints()
    bars[unit] = nil
    dirty[unit] = nil
end

-- ── The switch stack ────────────────────────────────────────────────────────
-- Rebuilt only when the look changes: the steps, the texture, the flash point.

local function StyleKey()
    return ("%s|%s|%s|%s|%s"):format(tostring(settings.style), tostring(settings.smooth),
        tostring(settings.texture), tostring(settings.warnAt), tostring(settings.rounded))
end

local function Mask(texture, mask, on)
    if not (texture and texture.AddMaskTexture) then return end
    if on then
        pcall(texture.AddMaskTexture, texture, mask)
    else
        pcall(texture.RemoveMaskTexture, texture, mask)
    end
end

-- Everything inside the bar follows the same rounded outline: the fill, every
-- colour step, the flash and the background. A texture keeps a mask until it
-- is taken off again, so switching the option off has to undo it.
local function ApplyRounding(bar)
    local on = settings.rounded == true
    Mask(bar:GetStatusBarTexture(), bar.mask, on)
    Mask(bar.bg, bar.mask, on)
    Mask(bar.border, bar.borderMask, on)
    Mask(bar.flash:GetStatusBarTexture(), bar.mask, on)
    for index = 1, (bar.switchCount or 0) do
        Mask(bar.switches[index]:GetStatusBarTexture(), bar.mask, on)
    end
end

local function BuildSwitches(bar)
    local key = StyleKey()
    if bar.styleKey == key then return end
    bar.styleKey = key

    local texture = TEXTURES[settings.texture] or TEXTURES.game
    local steps = Steps()
    bar:SetStatusBarTexture(texture)
    bar:SetStatusBarColor(steps.base[1], steps.base[2], steps.base[3])

    local fill = bar:GetStatusBarTexture()
    for index, step in ipairs(steps.list) do
        local switch = bar.switches[index]
        if not switch then
            switch = CreateFrame("StatusBar", nil, bar)
            bar.switches[index] = switch
        end
        switch:SetFrameLevel(bar:GetFrameLevel() + index)
        switch:ClearAllPoints()
        switch:SetAllPoints(fill)
        switch:SetStatusBarTexture(texture)
        switch:SetStatusBarColor(step[2][1], step[2][2], step[2][3])
        -- Empty below the step, full at it: the comparing is the bar's.
        switch:SetMinMaxValues(step[1] - EDGE, step[1])
        switch:Show()
    end
    for index = #steps.list + 1, #bar.switches do bar.switches[index]:Hide() end
    bar.switchCount = #steps.list

    local warnAt = tonumber(settings.warnAt) or 80
    bar.flash:SetMinMaxValues(warnAt - EDGE, warnAt)

    ApplyRounding(bar)
end

-- ── Placing ─────────────────────────────────────────────────────────────────

local function Place(bar, unit)
    local plate = PlateOf(unit)
    local anchor = AnchorFor(plate)
    if not anchor then return false end

    bar:SetParent(anchor)
    bar:SetFrameLevel((anchor:GetFrameLevel() or 1) + 2)
    bar:ClearAllPoints()

    local offset = tonumber(settings.offsetY) or -3
    local width = tonumber(settings.width) or 0
    if width > 0 then
        bar:SetPoint("TOP", anchor, "BOTTOM", 0, offset)
        bar:SetWidth(width)
    else
        bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offset)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offset)
    end
    bar:SetHeight(math.max(3, tonumber(settings.height) or 9))
    bar:SetAlpha(tonumber(settings.alpha) or 1)

    local font, _, flags = bar.text:GetFont()
    if font then
        local size = tonumber(settings.textSize) or 10
        bar.text:SetFont(font, size, flags)
        bar.holder:SetFont(font, size, flags)
    end
    bar.text:SetShown(settings.showText == true)

    if settings.glow then EnsureGlow(bar, plate) end
    BuildSwitches(bar)
    return true
end

-- ── Drawing ─────────────────────────────────────────────────────────────────

local function Warn()
    if not settings.sound or previewing then return end
    local now = GetTime()
    if now - lastWarn < WARN_GAP then return end
    lastWarn = now
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- Who has the enemy, when it is not you. Names can be secret in combat, so
-- anything unreadable simply leaves the line off.
-- A yes or no the code may actually test. A secret answer, or none at all,
-- counts as "cannot tell" and the caller leaves that part out.
local function Known(...)
    local ok, value = pcall(...)
    if not ok or IsSecret(value) then return nil end
    return value and true or false
end

local function HolderName(unit)
    if not settings.showName then return nil end
    local target = unit .. "target"
    if Known(UnitExists, target) ~= true then return nil end
    if Known(UnitIsUnit, target, "player") ~= false then return nil end

    local okName, name = pcall(UnitName, target)
    if not okName or IsSecret(name) or type(name) ~= "string" then return nil end

    local okClass, _, class = pcall(UnitClass, target)
    if not okClass or IsSecret(class) then class = nil end
    local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if colour and colour.GenerateHexColor then
        return ("|c%s%s|r"):format(colour:GenerateHexColor(), name)
    end
    return name
end

-- The fill, the colour steps, the flash and the glow all take the same value.
-- It is never read here, so a secret goes through exactly like a number.
local function Feed(bar, value, tanking)
    bar:SetValue(value)
    for index = 1, (bar.switchCount or 0) do
        bar.switches[index]:SetValue(value)
    end

    if settings.flash and not TankStyle() then
        bar.flash:SetValue(value)
        bar.flash:Show()
        if not bar.flash.pulse:IsPlaying() then bar.flash.pulse:Play() end
    else
        bar.flash.pulse:Stop()
        bar.flash:Hide()
    end

    if bar.glow and settings.glow then
        if TankStyle() then
            -- A tank wants the glow while the enemy is NOT on them, which is
            -- the one thing the game still answers when the number is hidden.
            if bar.glow.SetAlphaFromBoolean and IsSecret(tanking) then
                bar.glow:Show()
                pcall(bar.glow.SetAlphaFromBoolean, bar.glow, tanking, 1, 0)
            else
                bar.glow:SetAlpha(1)
                bar.glow:SetShown(tanking ~= true)
            end
        else
            -- The glow's own switch decides: lit from the warning point up.
            local warnAt = tonumber(settings.warnAt) or 80
            bar.glow.switch:SetMinMaxValues(warnAt - EDGE, warnAt)
            bar.glow.switch:SetValue(value)
            bar.glow:SetAlpha(1)
            bar.glow:Show()
        end
    elseif bar.glow then
        bar.glow:Hide()
    end
end

local function Redraw(unit)
    local bar = bars[unit]
    if not bar then return end

    if previewing then
        if not Place(bar, unit) then return bar:Hide() end
        local fake = ((unit:byte(-1) or 50) * 7) % 101
        Feed(bar, fake, false)
        bar.text:SetFormattedText("%d%%", fake)
        bar.holder:Hide()
        bar:Show()
        return
    end

    if Known(UnitExists, unit) ~= true
        or Known(UnitCanAttack, "player", unit) == false
        or (settings.onlyGroup and IsInGroup and not IsInGroup())
        or not UnitDetailedThreatSituation then
        HideExtras(bar)
        return bar:Hide()
    end
    -- "Is it fighting" can be secret too; unreadable counts as fighting, so
    -- the bar stays rather than flickering off mid-pull.
    if settings.onlyCombat and Known(UnitAffectingCombat, unit) == false then
        HideExtras(bar)
        return bar:Hide()
    end

    local ok, tanking, status, percent = pcall(UnitDetailedThreatSituation, "player", unit)
    if not ok or percent == nil then
        HideExtras(bar)
        return bar:Hide()
    end

    if not Place(bar, unit) then
        HideExtras(bar)
        return bar:Hide()
    end

    Feed(bar, percent, tanking)

    -- The number and the warning sound are the only parts that need to read
    -- it, so they are the only parts a secret leaves out.
    if IsSecret(percent) then
        bar.text:SetText("")
    else
        if settings.showText then
            bar.text:SetFormattedText("%d%%", math.max(0, math.min(100, percent)))
        end
        if not TankStyle() and not IsSecret(status) and (status or 0) >= 1 then Warn() end
    end

    -- ⚠ Never "IsSecret(x) and nil or ...": nil is false in Lua, so that
    -- expression always takes the second branch and reads the secret anyway.
    -- A plain if is the only safe shape here.
    local onYou
    if not IsSecret(tanking) then
        onYou = tanking and true or false
    end
    local holder = (not TankStyle() or onYou == false) and HolderName(unit) or nil
    if holder then
        bar.holder:SetText(holder)
        bar.holder:Show()
    else
        bar.holder:Hide()
    end

    bar:Show()
end

local function RedrawAll()
    for unit in pairs(bars) do dirty[unit] = true end
end

-- ── The ticker ──────────────────────────────────────────────────────────────

local function Tick()
    if not next(dirty) then return end
    for unit in pairs(dirty) do
        dirty[unit] = nil
        Redraw(unit)
    end
end

local function StartTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(REDRAW, Tick)
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
    wipe(dirty)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED",
}

watcher:SetScript("OnEvent", function(_, event, unit)
    if not settings or settings.enabled == false then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        -- Your own plate. Secret here means "cannot tell", and a bar on the
        -- personal plate is harmless, so it is let through rather than erroring.
        if Known(UnitIsUnit, unit, "player") == true then return end
        bars[unit] = bars[unit] or NewBar()
        dirty[unit] = true
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        Release(unit)
    elseif event == "UNIT_THREAT_LIST_UPDATE" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        if unit and bars[unit] then dirty[unit] = true end
        if unit == "player" or unit == nil then RedrawAll() end
    else
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            previewing = false
        end
        RedrawAll()
    end
end)

local function Start()
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    StartTicker()

    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for _, plate in ipairs(plates) do
                local unit = plate.namePlateUnitToken
                if unit and Known(UnitIsUnit, unit, "player") ~= true then
                    bars[unit] = bars[unit] or NewBar()
                    dirty[unit] = true
                end
            end
        end
    end
end

local function Stop()
    watcher:UnregisterAllEvents()
    StopTicker()
    previewing = false
    for unit in pairs(bars) do Release(unit) end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.threatbar
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.threatbar = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

-- The look changed, so the switch stacks are rebuilt on the next redraw.
local function Restyle()
    for _, bar in pairs(bars) do bar.styleKey = nil end
    RedrawAll()
end

local function AddSlider(w, key, caption, minValue, maxValue, step, format)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(190, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 250, w.cursorY - 5)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    -- ⚠ A fresh slider holds 0 and the template moves it about while the
    -- window is laid out. Nothing is saved until it has been told what the
    -- setting really is, or those moves overwrite it.
    local ready, refreshing = false, false
    local function Show(value) label:SetText((format):format(caption, value)) end
    local function Load()
        refreshing = true
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
        refreshing = false
        ready = true
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing or not ready then return end
        settings[key] = value
        Restyle()
    end)

    Load()
    w:HookScript("OnShow", Load)
    w.cursorY = w.cursorY - 30
end

local function AddChoiceRow(w, key, caption, choices)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    label:SetText(caption)

    local holder, buttons = {}, {}
    holder.Refresh = function()
        for _, entry in ipairs(buttons) do
            entry.button:SetNormalFontObject(settings[key] == entry.key
                and "GameFontNormal" or "GameFontDisableSmall")
        end
    end
    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(90, 22)
        button:SetPoint("TOPLEFT", w, "TOPLEFT", 170 + (index - 1) * 94, w.cursorY - 2)
        button:SetText(choice.name)
        button:SetScript("OnClick", function()
            settings[key] = choice.key
            holder.Refresh()
            Restyle()
        end)
        buttons[#buttons + 1] = { key = choice.key, button = button }
    end
    table.insert(w.checks, holder)
    w.cursorY = w.cursorY - 30
end

local function SetPreview(on)
    previewing = on and true or false
    if previewing then
        StartTicker()
        print(PREFIX .. "sample bars on. They go off when a fight starts, or type /oxthreat test again.")
    end
    RedrawAll()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Threat Bar", 520, 655)
        local w = optionsWindow

        AddChoiceRow(w, "style", "Colours", {
            { key = "auto",   name = "Auto" },
            { key = "damage", name = "Damage" },
            { key = "tank",   name = "Tank" },
        })
        AddChoiceRow(w, "texture", "Bar texture", {
            { key = "game", name = "Game" },
            { key = "flat", name = "Flat" },
        })
        w:AddCheckbox(settings, "smooth", "Fade green to red",
            "Damage colours run smoothly with the percentage. Off, they step from green to yellow to orange to red.", Restyle)
        w:AddCheckbox(settings, "rounded", "Round the ends", nil, Restyle)
        w:AddCheckbox(settings, "showText", "Show the percentage", nil, Restyle)
        w:AddCheckbox(settings, "showName", "Name whoever is holding it",
            "Under the bar, in their class colour.", Restyle)
        AddSlider(w, "textSize", "Text size", 6, 20, 1, "%s: %d")

        AddSlider(w, "height", "Bar height", 3, 24, 1, "%s: %d")
        AddSlider(w, "width", "Bar width", 0, 200, 5, "%s: %d")
        AddSlider(w, "offsetY", "Distance below the plate", -40, 20, 1, "%s: %d")
        AddSlider(w, "alpha", "Opacity", 0.2, 1, 0.05, "%s: %.2f")

        AddSlider(w, "warnAt", "Warn from", 30, 100, 5, "%s: %d%%")
        w:AddCheckbox(settings, "flash", "Flash the bar", nil, Restyle)
        w:AddCheckbox(settings, "glow", "Glow around the nameplate", nil, Restyle)
        w:AddCheckbox(settings, "sound", "Warning sound when you take it",
            "A raid warning the moment your threat passes whoever is holding the enemy. Silent while the game hides the numbers.")

        w:AddCheckbox(settings, "onlyCombat", "Only enemies in combat", nil, Restyle)
        w:AddCheckbox(settings, "otherPlates", "Work with Platynator and other nameplate addons",
            "When another addon hides the game's nameplates, the bar sits under that addon's health bar instead.", Restyle)
        w:AddCheckbox(settings, "onlyGroup", "Only in a group",
            "On your own there is nobody to take the enemy from.", Restyle)

        w:AddNote("Bar width 0 follows the nameplate's own width. Type /oxthreat test for sample bars while you set the look.")
        w:AddNote("In a fight the game keeps the exact threat from addons. The colours, the flash and the glow keep working anyway: each one is a bar whose range is a hair wide, so the game itself decides whether it is empty or full. Only the printed number and the sound need reading it, and those are the parts that go quiet.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBTHREAT1 = "/oxthreat"
SlashCmdList.OXEDHUBTHREAT = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()
    if msg == "test" then
        SetPreview(not previewing)
        return
    end
    if msg == "why" then
        -- Walks Redraw's checks for the target's plate and says which one
        -- stops the bar. Every read is guarded: this runs in combat.
        local say = function(text) print("|cff00ccffOxedHub Threat|r " .. text) end
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and PlateOf("target")
        if not plate then return say("no nameplate on your target.") end
        local unit = plate.namePlateUnitToken or plate.unitToken
        say("plate " .. tostring(unit) .. ", bar made: " .. tostring(unit and bars[unit] ~= nil))
        say("module on: " .. tostring(settings.enabled) .. ", only in a group: " .. tostring(settings.onlyGroup)
            .. ", in a group: " .. tostring(IsInGroup and IsInGroup() or false))
        say("can attack: " .. tostring(Known(UnitCanAttack, "player", "target"))
            .. ", in combat: " .. tostring(Known(UnitAffectingCombat, "target")) .. " (nil = the game will not say)")
        local ok, _, _, percent = pcall(UnitDetailedThreatSituation, "player", "target")
        say("threat read: " .. tostring(ok) .. ", value " .. (IsSecret(percent) and "secret (fine)" or tostring(percent)))
        local frame = plate.UnitFrame
        say("Blizzard plate in use: " .. tostring(frame and BlizzardInUse(plate, frame)))
        local anchor = AnchorFor(plate)
        say("sits under: " .. tostring(anchor and (anchor:GetDebugName() or anchor:GetName()) or "nothing"))
        local bar = unit and bars[unit]
        if bar then say("bar shown: " .. tostring(Plain(bar:IsShown()))) end
        return
    end
    ShowOptions()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "threatbar",
        name     = "Threat Bar",
        version  = "1.1.0",
        author   = "Oxed",
        category = "combat",
        keywords = { "threat", "aggro", "nameplate", "tank", "pull", "omen", "glow" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A threat bar under every enemy nameplate, with a glow as you close in. /oxthreat",
        icon     = "Interface\\Icons\\Ability_Warrior_BattleShout",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
