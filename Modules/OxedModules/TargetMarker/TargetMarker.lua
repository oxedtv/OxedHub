-- ============================================================================
-- Target Marker (built-in OxedHub module)
-- A marker on your current target's nameplate, so it is easy to find in a pack.
-- Thirteen styles, each drawn from plain textures the game already has, with a
-- colour, size, opacity, animation and a sound on changing target.
--
-- ⚠ It hangs on the nameplate, so a target without one (friendly plates off, or
-- too far away) has no marker. Friendly plates in dungeons and raids are
-- forbidden to addons, and touching one is an error: those are left alone too.
-- ⚠ UnitCanAttack can answer with a secret in combat. "Cannot tell" shows the
-- marker: better one too many than none on the enemy you are fighting.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on
    style         = "arrow",
    raidIcon      = 8,       -- the raid mark the "raid" style shows; 8 is the skull
    colourMode    = "fixed", -- "fixed" or "class" (your own class's colour)
    combatColour  = false,   -- a second colour while you are in combat
    size          = 28,
    thickness     = 2,
    height        = 24,      -- how far above the health bar
    offsetX       = 0,
    opacity       = 100,
    animation     = "fade",  -- "none", "fade", "grow" or "bob"
    speed         = 0.6,     -- seconds for one sweep of the animation
    enemiesOnly   = false,
    combatOnly    = false,
    sound         = "None",
    minimapButton = true,
    -- colour and fightColour are tables, made in BindSettings
}

local ARROW_ATLAS = "NPE_ArrowDown"
local ARROW_FILE = "Interface\\Buttons\\UI-MicroStream-Yellow"
local CIRCLE_FILE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local BURST_FILE = "Interface\\Cooldown\\star4"
local RAID_ICON_FILE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local BEAM_HEIGHT = 140
local GLOW_RINGS = { 0.85, 0.4, 0.18 }   -- each ring fainter than the last

local settings
local running = false
local optionsWindow
local minimapIcon, MinimapIcon
local marker
-- Kept from the events: at PLAYER_REGEN_DISABLED, InCombatLockdown() still says
-- false, so asking it there left the marker in its out-of-combat look.
local inCombat = false

local events = CreateFrame("Frame")

-- ── Pieces ──────────────────────────────────────────────────────────────────
-- Every texture of every style lives in marker.pieces, made the first time that
-- style is chosen. Arranging hides them all and shows the ones it asks for.

local function AtlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function Piece(key, make)
    local piece = marker.pieces[key]
    if not piece then
        piece = marker:CreateTexture(nil, "OVERLAY")
        piece.baseAlpha = 1
        if make then make(piece) else piece:SetColorTexture(1, 1, 1, 1) end
        marker.pieces[key] = piece
    end
    piece:ClearAllPoints()
    piece:Show()
    return piece
end

local function MakeArrow(rotation)
    return function(piece)
        if AtlasExists(ARROW_ATLAS) then
            piece:SetAtlas(ARROW_ATLAS)
        else
            piece:SetTexture(ARROW_FILE)
        end
        -- Grey first, or the tint is mixed with the art's own gold.
        piece:SetDesaturated(true)
        piece:SetRotation(rotation)
    end
end

-- A square centred above the bar, the place most of the styles use.
local function Above(piece, size)
    piece:SetSize(size, size)
    piece:SetPoint("BOTTOM", marker, "TOP", settings.offsetX, settings.height)
end

local function Line(key, thickness, horizontal)
    local line = Piece(key)
    if horizontal then line:SetHeight(thickness) else line:SetWidth(thickness) end
    return line
end

-- ── Styles ──────────────────────────────────────────────────────────────────

local STYLE = {}

function STYLE.arrow(size)
    Above(Piece("arrow", MakeArrow(0)), size)
end

function STYLE.stack(size)
    for i = 1, 3 do
        local piece = Piece("stack" .. i, MakeArrow(0))
        piece.baseAlpha = 1 - (i - 1) * 0.3
        piece:SetSize(size, size)
        piece:SetPoint("BOTTOM", marker, "TOP", settings.offsetX, settings.height + (i - 1) * size * 0.45)
    end
end

function STYLE.sides(size)
    local left = Piece("left", MakeArrow(math.pi / 2))    -- points right, at the bar
    left:SetSize(size, size)
    left:SetPoint("RIGHT", marker, "LEFT", settings.offsetX - 2, 0)
    local right = Piece("right", MakeArrow(-math.pi / 2)) -- points left, at the bar
    right:SetSize(size, size)
    right:SetPoint("LEFT", marker, "RIGHT", 2 - settings.offsetX, 0)
end

function STYLE.dot(size)
    Above(Piece("dot", function(piece) piece:SetTexture(CIRCLE_FILE) end), size * 0.6)
end

function STYLE.burst(size)
    Above(Piece("burst", function(piece)
        piece:SetTexture(BURST_FILE)
        piece:SetBlendMode("ADD")
    end), size * 1.5)
end

function STYLE.raid(size)
    local piece = Piece("raid", function(p) p.keepColour = true end)
    piece:SetTexture(RAID_ICON_FILE .. (tonumber(settings.raidIcon) or 8))
    Above(piece, size)
end

function STYLE.crosshair(size, thickness)
    local arm = math.max(4, size * 0.35)
    local gap = math.max(2, size * 0.12)
    local x, y = settings.offsetX, settings.height + arm + gap

    local left = Line("crossL", thickness, true)
    left:SetWidth(arm)
    left:SetPoint("RIGHT", marker, "TOP", x - gap, y)
    local right = Line("crossR", thickness, true)
    right:SetWidth(arm)
    right:SetPoint("LEFT", marker, "TOP", x + gap, y)
    local up = Line("crossU", thickness, false)
    up:SetHeight(arm)
    up:SetPoint("BOTTOM", marker, "TOP", x, y + gap)
    local down = Line("crossD", thickness, false)
    down:SetHeight(arm)
    down:SetPoint("TOP", marker, "TOP", x, y - gap)
end

function STYLE.beam(size)
    local piece = Piece("beam", function(p)
        p:SetColorTexture(1, 1, 1, 1)
        -- A column of light that fades upward: a gradient, not a tint.
        p.paint = function(self, r, g, b, a)
            self:SetGradient("VERTICAL", CreateColor(r, g, b, a * 0.8), CreateColor(r, g, b, 0))
        end
    end)
    piece:SetSize(size, BEAM_HEIGHT)
    piece:SetPoint("BOTTOM", marker, "TOP", settings.offsetX, 0)
end

function STYLE.box(_, thickness)
    local top = Line("boxT", thickness, true)
    top:SetPoint("BOTTOMLEFT", marker, "TOPLEFT", -thickness, 1)
    top:SetPoint("BOTTOMRIGHT", marker, "TOPRIGHT", thickness, 1)
    local bottom = Line("boxB", thickness, true)
    bottom:SetPoint("TOPLEFT", marker, "BOTTOMLEFT", -thickness, -1)
    bottom:SetPoint("TOPRIGHT", marker, "BOTTOMRIGHT", thickness, -1)
    local left = Line("boxL", thickness, false)
    left:SetPoint("TOPRIGHT", marker, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMRIGHT", marker, "BOTTOMLEFT", -1, -1)
    local right = Line("boxR", thickness, false)
    right:SetPoint("TOPLEFT", marker, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMLEFT", marker, "BOTTOMRIGHT", 1, -1)
end

function STYLE.brackets(size, thickness)
    local length = math.max(4, size * 0.4)
    local corners = {
        { "TL", "TOPLEFT", -1, 1 }, { "TR", "TOPRIGHT", 1, 1 },
        { "BL", "BOTTOMLEFT", -1, -1 }, { "BR", "BOTTOMRIGHT", 1, -1 },
    }
    for _, corner in ipairs(corners) do
        local key, point, dx, dy = corner[1], corner[2], corner[3], corner[4]
        local across = Line("brk" .. key .. "H", thickness, true)
        across:SetWidth(length)
        across:SetPoint(point, marker, point, dx * 2, dy * 2)
        local along = Line("brk" .. key .. "V", thickness, false)
        along:SetHeight(length)
        along:SetPoint(point, marker, point, dx * 2, dy * 2)
    end
end

function STYLE.glow()
    for ring, alpha in ipairs(GLOW_RINGS) do
        local out = ring
        local top = Line("glowT" .. ring, 1, true)
        top.baseAlpha = alpha
        top:SetPoint("TOPLEFT", marker, "TOPLEFT", -out, out)
        top:SetPoint("TOPRIGHT", marker, "TOPRIGHT", out, out)
        local bottom = Line("glowB" .. ring, 1, true)
        bottom.baseAlpha = alpha
        bottom:SetPoint("BOTTOMLEFT", marker, "BOTTOMLEFT", -out, -out)
        bottom:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", out, -out)
        local left = Line("glowL" .. ring, 1, false)
        left.baseAlpha = alpha
        left:SetPoint("TOPLEFT", marker, "TOPLEFT", -out, out)
        left:SetPoint("BOTTOMLEFT", marker, "BOTTOMLEFT", -out, -out)
        local right = Line("glowR" .. ring, 1, false)
        right.baseAlpha = alpha
        right:SetPoint("TOPRIGHT", marker, "TOPRIGHT", out, out)
        right:SetPoint("BOTTOMRIGHT", marker, "BOTTOMRIGHT", out, -out)
    end
end

function STYLE.tint()
    local piece = Piece("tint")
    piece.baseAlpha = 0.35
    piece:SetAllPoints(marker)
end

function STYLE.underline(_, thickness)
    local line = Line("under", thickness + 1, true)
    line:SetPoint("TOPLEFT", marker, "BOTTOMLEFT", 0, -2)
    line:SetPoint("TOPRIGHT", marker, "BOTTOMRIGHT", 0, -2)
end

-- ── The marker ──────────────────────────────────────────────────────────────

local function NewAnimation(kind, setup)
    local group = marker:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local animation = group:CreateAnimation(kind)
    setup(animation)
    group.animation = animation
    return group
end

local function BuildMarker()
    if marker then return end
    marker = CreateFrame("Frame", "OxedHubTargetMarker", UIParent)
    marker:SetSize(1, 1)
    marker:Hide()
    marker.pieces = {}
    marker.animations = {
        fade = NewAnimation("Alpha", function(a)
            a:SetFromAlpha(1)
            a:SetToAlpha(0.3)
        end),
        grow = NewAnimation("Scale", function(a)
            a:SetScaleFrom(1, 1)
            a:SetScaleTo(1.2, 1.2)
            a:SetOrigin("CENTER", 0, 0)
        end),
        bob = NewAnimation("Translation", function(a) a:SetOffset(0, 8) end),
    }
end

local function CurrentColour()
    if settings.combatColour and inCombat then return settings.fightColour end
    if settings.colourMode == "class" and RAID_CLASS_COLORS then
        local _, class = UnitClass("player")
        local colour = class and RAID_CLASS_COLORS[class]
        if colour then return { colour.r, colour.g, colour.b } end
    end
    return settings.colour
end

local function PaintMarker()
    if not marker then return end
    local c = CurrentColour()
    local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
    local opacity = (tonumber(settings.opacity) or 100) / 100
    for _, piece in pairs(marker.pieces) do
        if piece.paint then
            piece:paint(r, g, b, opacity)
        else
            if not piece.keepColour then piece:SetVertexColor(r, g, b) end
            piece:SetAlpha(piece.baseAlpha * opacity)
        end
    end
end

local function Arrange(bar)
    for _, piece in pairs(marker.pieces) do piece:Hide() end
    marker:ClearAllPoints()
    marker:SetAllPoints(bar)
    local draw = STYLE[settings.style] or STYLE.arrow
    draw(tonumber(settings.size) or DEFAULTS.size, tonumber(settings.thickness) or DEFAULTS.thickness)
end

local function Animate()
    local speed = tonumber(settings.speed) or DEFAULTS.speed
    for name, group in pairs(marker.animations) do
        if name == settings.animation then
            if group.speed ~= speed then
                group:Stop()
                group.animation:SetDuration(speed)
                group.speed = speed
            end
            if not group:IsPlaying() then group:Play() end
        else
            group:Stop()
        end
    end
end

local function HideMarker()
    if not marker then return end
    for _, group in pairs(marker.animations) do group:Stop() end
    marker:Hide()
    marker:ClearAllPoints()
    marker:SetParent(UIParent)
end

-- True, false, or nil for "cannot tell".
local function TargetIsEnemy()
    local ok, value = pcall(UnitCanAttack, "player", "target")
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value and true or false
end

local function ShouldShow()
    if settings.combatOnly and not inCombat then return false end
    if settings.enemiesOnly and TargetIsEnemy() == false then return false end
    return true
end

local function Update()
    if not running then return false end
    local plate
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, found = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        plate = ok and found or nil
    end
    if not plate or (plate.IsForbidden and plate:IsForbidden()) or not ShouldShow() then
        HideMarker()
        return false
    end

    BuildMarker()
    -- Blizzard's bar or another nameplate addon's, whichever is on screen.
    local bar = OxedHub.VisiblePlateBar and OxedHub.VisiblePlateBar(plate) or plate
    marker:SetParent(plate)
    marker:SetFrameStrata(plate:GetFrameStrata())
    marker:SetFrameLevel(plate:GetFrameLevel() + 20)
    Arrange(bar)
    PaintMarker()
    marker:Show()
    Animate()
    return true
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    local shown = Update()
    if event == "PLAYER_TARGET_CHANGED" then
        if shown and settings.sound and settings.sound ~= "None" then
            OxedHub.ModuleAPI:PlaySound(settings.sound)
        end
        -- A plate can still be laying itself out when its event arrives.
        C_Timer.After(0.15, Update)
    end
end)

local EVENTS = {
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Target Marker", 460, 700)
        optionsWindow = w
        local function Redraw() Update() end

        w:AddChoice(settings, "style", "Style", {
            { value = "arrow",     text = "Arrow above" },
            { value = "stack",     text = "Three arrows above" },
            { value = "sides",     text = "Arrows on both sides" },
            { value = "dot",       text = "Dot above" },
            { value = "burst",     text = "Star burst above" },
            { value = "raid",      text = "Raid mark above" },
            { value = "crosshair", text = "Crosshair above" },
            { value = "beam",      text = "Column of light" },
            { value = "box",       text = "Box around the health bar" },
            { value = "brackets",  text = "Corners around the health bar" },
            { value = "glow",      text = "Glow around the health bar" },
            { value = "tint",      text = "Tint over the health bar" },
            { value = "underline", text = "Line under the health bar" },
        }, Redraw)
        w:AddChoice(settings, "raidIcon", "Raid mark", {
            { value = 8, text = RAID_TARGET_8 or "Skull" },
            { value = 7, text = RAID_TARGET_7 or "Cross" },
            { value = 6, text = RAID_TARGET_6 or "Square" },
            { value = 5, text = RAID_TARGET_5 or "Moon" },
            { value = 4, text = RAID_TARGET_4 or "Triangle" },
            { value = 3, text = RAID_TARGET_3 or "Diamond" },
            { value = 2, text = RAID_TARGET_2 or "Circle" },
            { value = 1, text = RAID_TARGET_1 or "Star" },
        }, Redraw)
        w:AddChoice(settings, "colourMode", "Colour from", {
            { value = "fixed", text = "The colour below" },
            { value = "class", text = "Your class" },
        }, PaintMarker)
        w:AddColour(settings, "colour", "Colour", PaintMarker)
        w:AddCheckbox(settings, "combatColour", "Another colour while you are in combat", nil, PaintMarker)
        w:AddColour(settings, "fightColour", "Colour in combat", PaintMarker)
        w:AddSlider(settings, "size", "Size", 12, 64, 1, "%s: %d", Redraw)
        w:AddSlider(settings, "thickness", "Thickness", 1, 8, 1, "%s: %d", Redraw)
        w:AddSlider(settings, "height", "Height", 0, 60, 1, "%s: %d", Redraw)
        w:AddSlider(settings, "offsetX", "Offset X", -60, 60, 1, "%s: %d", Redraw)
        w:AddSlider(settings, "opacity", "Opacity", 10, 100, 5, "%s: %d", PaintMarker)
        w:AddChoice(settings, "animation", "Animation", {
            { value = "none", text = "None" },
            { value = "fade", text = "Fade" },
            { value = "grow", text = "Grow" },
            { value = "bob",  text = "Bob up and down" },
        }, Redraw)
        w:AddSlider(settings, "speed", "Animation speed", 0.2, 1.5, 0.1, "%s: %.1f", Redraw)
        w:AddCheckbox(settings, "enemiesOnly", "Only on enemies", nil, Redraw)
        w:AddCheckbox(settings, "combatOnly", "Only while you are in combat", nil, Redraw)
        w:AddSoundPicker(settings, "sound", "Sound on a new target")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        w:AddNote("The marker sits on the target's nameplate. With no nameplate there is no marker. In dungeons and raids the game keeps friendly nameplates from addons.")
        -- Exactly as tall as what went in it, whichever language that was in.
        w:SetHeight(math.max(200, 16 - w.cursorY))
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "targetmarker", label = L["Target Marker"], icon = "Interface\\Icons\\Ability_Hunter_SniperShot", config = settings,
        hint = L["Click: options."],
        onClick = function()
            ShowOptions()
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBTARGETMARKER1 = "/oxtarget"
SlashCmdList.OXEDHUBTARGETMARKER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg ~= "debug" then return ShowOptions() end
    -- Why there is or is not a marker right now.
    local okPlate, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    print(("Target Marker: on %s, nameplate %s, forbidden %s, style %s, in combat %s (only in combat %s), enemy %s (only enemies %s), marker shown %s"):format(
        tostring(running), tostring(okPlate and plate ~= nil),
        tostring(okPlate and plate and plate.IsForbidden and plate:IsForbidden() or false),
        tostring(settings and settings.style), tostring(inCombat), tostring(settings and settings.combatOnly),
        tostring(TargetIsEnemy()), tostring(settings and settings.enemiesOnly),
        tostring(marker and marker:IsShown() or false)))
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.targetmarker
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.targetmarker = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.colour) ~= "table" then config.colour = { 1, 0.82, 0 } end
    if type(config.fightColour) ~= "table" then config.fightColour = { 1, 0.2, 0.2 } end
    settings = config

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "targetmarker",
        name     = "Target Marker",
        version  = "1.0.0",
        updated  = 20261102.95,
        author   = "Oxed",
        category = "combat",
        keywords = { "target", "indicator", "marker", "arrow", "nameplate", "highlight", "glow", "crosshair" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A marker on your target's nameplate: arrows, glow, box, crosshair and more. /oxtarget",
        icon     = "Interface\\Icons\\Ability_Hunter_SniperShot",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            running = true
            inCombat = InCombatLockdown()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
            Update()
        end,

        OnDisable = function()
            running = false
            if minimapIcon then minimapIcon:Apply(false) end
            events:UnregisterAllEvents()
            HideMarker()
        end,
    })
end)
