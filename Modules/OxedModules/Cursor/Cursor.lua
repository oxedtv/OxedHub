-- ============================================================================
-- Cursor (built-in OxedHub module)
-- Makes the mouse pointer easy to find and nice to look at:
--
--   glow      a glow, ring, dot or star around the hand, in any colour
--   shadow    a soft dark disc behind it, for contrast on busy scenes
--   trail     sparks left behind as it moves; a theme decides how they
--             behave -- fire rises, frost drifts down, a meteor sprays a tail
--   steering  while the right button is held the game hides the pointer;
--             its arrow is drawn where the pointer froze, so you never lose it
--   ripple    a ring spreads out from every click
--   shake     wiggle the mouse fast and the halo flares up for a moment
--
-- The glow can sit on the pointer's tip or around the hand, with a fine
-- offset on top. The game draws its pointer over every frame, so all of this
-- is always behind the hand.
--
-- The sparks are drawn with our own art in Media\Textures\Cursor: a round
-- glow, an ember and a ring. The game's own glow atlases were tried first and
-- one of them is a white square, which stacked into a solid block of light.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,   -- off until the player switches it on

    theme        = "custom", -- see THEMES

    halo         = true,
    haloShape    = "glow",  -- glow, dot or star (the Custom theme only)
    haloSize     = 56,
    haloAlpha    = 0.85,
    haloOwnColour = false,  -- a colour of its own, instead of the theme's
    haloR        = 1,
    haloG        = 0.55,
    haloB        = 0.15,

    anchor       = "hand",  -- tip or hand
    offsetX      = 0,
    offsetY      = 0,

    shadow       = true,
    shadowSize   = 44,
    shadowAlpha  = 0.35,

    trail        = true,
    trailLength  = 14,      -- sparks alive at once
    trailSize    = 14,
    trailLife    = 0.40,    -- seconds a spark takes to fade (Custom theme)

    classColour  = true,    -- colour from the class; off uses the picked one
    rainbow      = false,   -- cycle through the colours instead
    colourR      = 0.55,
    colourG      = 0.35,
    colourB      = 1.00,

    steering     = true,    -- draw the arrow while the right button steers
    ripple       = true,
    shake        = true,

    onlyCombat   = false,
    idleSwirl    = true,    -- sparks circle the pointer while it rests
    swirlDelay   = 0.3,     -- seconds of rest before they start
    fadeIdle     = false,   -- fade out when the mouse has not moved for a while
    idleSeconds  = 3,
}

local settings          -- OxedHubDB.modules.cursor, bound at login
local optionsWindow
local root              -- everything hangs off this; hidden means no OnUpdate
local halo, shadow, arrow
local sparks = {}       -- trail pool, used round-robin
local ripples = {}      -- click ring pool
local nextSpark = 1
local watcher = CreateFrame("Frame")
local MAX_SPARKS = 220  -- shared by every layer of a theme
local MAX_SPARK_SPEED = 320   -- pixels a second; see DropSpark
local MAX_TRAVEL = 150        -- how far from its birthplace a spark may get

-- ── Textures ────────────────────────────────────────────────────────────────

-- Our own art, so nothing depends on a Blizzard path surviving a patch.
-- GLOW is a round glow that fades out to nothing, EMBER a small bright dot,
-- RING a soft circle. The game's atlases were tried first and one of them
-- turned out to be a white square, which stacked into a solid block.
local MEDIA  = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Cursor\\"
local GLOW   = MEDIA .. "glow"
local EMBER  = MEDIA .. "ember"
local RING   = MEDIA .. "ring"
local STAR   = "Interface\\Cooldown\\star4"
local ARROW  = "Interface\\CURSOR\\Point"

local SHAPES = {
    glow  = { { file = GLOW } },
    soft  = { { file = GLOW } },
    ring  = { { file = RING } },
    dot   = { { file = EMBER } },
    star  = { { file = STAR } },
    burst = { { file = STAR } },
}

local function AtlasExists(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

-- Returns how much the shape's own alpha should be scaled: the plain-circle
-- stand-in for a glow is a hard disc, and at full strength it reads as a blob.
local function ApplyShape(texture, shape)
    for _, candidate in ipairs(SHAPES[shape] or SHAPES.dot) do
        if candidate.atlas and AtlasExists(candidate.atlas) then
            texture:SetAtlas(candidate.atlas)
            return candidate.alphaScale or 1
        elseif candidate.file then
            texture:SetTexture(candidate.file)
            texture:SetTexCoord(0, 1, 0, 1)
            return candidate.alphaScale or 1
        end
    end
    texture:SetTexture(GLOW)
    return 1
end

-- ── Themes ──────────────────────────────────────────────────────────────────
-- A theme is a halo, a spark and a way for the sparks to move. Colours run
-- from head (a fresh spark) to tail (one about to vanish).
--
--   rise     upward speed, negative falls
--   spread   random speed in every direction
--   sway     side to side wobble
--   jitter   jumps about every frame, like a spark of electricity
--   behind   thrown backwards along the mouse's path, the way a meteor sheds
--   grow     swells as it fades, like smoke
--   spin     turns per second
--   flicker  how much the halo and sparks flicker
--   perDrop  sparks dropped at once

local THEMES = {
    { key = "custom",    name = "Custom" },
    -- A real flame: a bright tongue that rises faster as it goes and cools
    -- from white-yellow through orange to deep red, embers that wander up
    -- long after, and a little smoke on top. It burns even while the mouse
    -- is still, the way a torch does.
    { key = "fire",      name = "Fire",
      halo = "glow", haloColour = { 1, 0.5, 0.12 }, flicker = 0.35,
      layers = {
          { shape = "soft", rate = 34, spacing = 6, life = 0.55, lifeVar = 0.25,
            stops = { { 1, 0.92, 0.6 }, { 1, 0.65, 0.18 }, { 1, 0.3, 0.04 }, { 0.45, 0.05, 0.01 } },
            rise = 25, lift = 150, spread = 10, sway = 18,
            size0 = 1.1, size1 = 0.2, alpha = 0.22, alphaPow = 0.9, flicker = 0.25 },
          { shape = "dot", rate = 7, spacing = 40, life = 1.3, lifeVar = 0.5,
            stops = { { 1, 0.95, 0.6 }, { 1, 0.55, 0.12 }, { 0.7, 0.12, 0 } },
            rise = 40, lift = 40, spread = 28, sway = 30, drag = 0.4,
            size0 = 0.2, size1 = 0.07, alpha = 0.85, flicker = 0.6 },
          { shape = "soft", rate = 5, spacing = 45, life = 1.4, lifeVar = 0.4, blend = "BLEND",
            stops = { { 0.2, 0.17, 0.15 }, { 0.1, 0.1, 0.1 } },
            rise = 55, lift = 30, spread = 10, sway = 22, startAt = 0.12,
            size0 = 0.9, size1 = 2.4, alpha = 0.16, puff = true },
      } },
    { key = "frost",     name = "Frost",
      halo = "star", spark = "star", head = { 0.9, 1, 1 }, tail = { 0.2, 0.5, 1 },
      rise = -22, spread = 10, spin = 1.2, life = 0.8 },
    { key = "arcane",    name = "Arcane",
      halo = "glow", spark = "star", head = { 1, 0.65, 1 }, tail = { 0.4, 0.2, 1 },
      spread = 28, spin = 2.5, flicker = 0.25, life = 0.6 },
    { key = "lightning", name = "Lightning",
      halo = "glow", spark = "dot", head = { 1, 1, 1 }, tail = { 0.3, 0.6, 1 },
      jitter = 6, flicker = 0.7, size = 0.6, life = 0.25, perDrop = 2 },
    { key = "nature",    name = "Nature",
      halo = "glow", spark = "star", head = { 0.8, 1, 0.4 }, tail = { 0.1, 0.55, 0.15 },
      rise = -18, sway = 40, spin = 1.5, life = 0.9 },
    { key = "shadow",    name = "Shadow",
      halo = "glow", spark = "soft", head = { 0.65, 0.25, 0.95 }, tail = { 0.08, 0, 0.12 },
      rise = 14, spread = 6, grow = 1.6, life = 0.8, blend = "BLEND" },
    { key = "holy",      name = "Holy",
      halo = "burst", spark = "burst", head = { 1, 1, 0.85 }, tail = { 1, 0.7, 0.15 },
      rise = 22, spread = 8, spin = 0.8, life = 0.7 },
    -- A meteor: a white-hot head, an unbroken burning tail laid along the
    -- exact path (filled in between frames, so a fast flick is a streak and
    -- not a row of dots), a wide glow around the tail, debris thrown off that
    -- falls under gravity, and a smoke trail left hanging behind.
    { key = "meteor",    name = "Meteor",
      halo = "glow", haloColour = { 1, 0.85, 0.55 }, haloScale = 0.75, flicker = 0.15,
      layers = {
          { shape = "soft", spacing = 4, life = 0.42, lifeVar = 0.1,
            stops = { { 1, 0.97, 0.8 }, { 1, 0.75, 0.3 }, { 1, 0.38, 0.06 }, { 0.45, 0.06, 0.01 } },
            size0 = 0.8, size1 = 0.1, alpha = 0.3, alphaPow = 0.7 },
          { shape = "soft", spacing = 9, life = 0.6, lifeVar = 0.15,
            stops = { { 1, 0.6, 0.2 }, { 0.85, 0.2, 0.03 }, { 0.3, 0.03, 0 } },
            size0 = 2.0, size1 = 1.0, alpha = 0.1 },
          { shape = "dot", spacing = 14, chance = 0.8, life = 0.8, lifeVar = 0.35,
            stops = { { 1, 0.95, 0.65 }, { 1, 0.5, 0.1 }, { 0.6, 0.1, 0 } },
            behind = 0.25, spread = 70, gravity = -260, drag = 0.8,
            size0 = 0.22, size1 = 0.07, alpha = 0.8, flicker = 0.5 },
          { shape = "soft", spacing = 16, life = 1.3, lifeVar = 0.4, blend = "BLEND",
            stops = { { 0.22, 0.18, 0.16 }, { 0.12, 0.12, 0.12 } },
            spread = 6, rise = 12, startAt = 0.1,
            size0 = 0.9, size1 = 2.8, alpha = 0.15, puff = true },
      } },
}
local THEME_BY_KEY = {}
for _, theme in ipairs(THEMES) do THEME_BY_KEY[theme.key] = theme end

local function CurrentTheme()
    return THEME_BY_KEY[settings and settings.theme] or THEME_BY_KEY.custom
end

-- ── Colour ──────────────────────────────────────────────────────────────────

local function HueToRGB(hue)
    -- Hue in 0..1 on a fully saturated wheel.
    local h = (hue % 1) * 6
    local x = 1 - math.abs(h % 2 - 1)
    if h < 1 then return 1, x, 0
    elseif h < 2 then return x, 1, 0
    elseif h < 3 then return 0, 1, x
    elseif h < 4 then return 0, x, 1
    elseif h < 5 then return x, 0, 1
    end
    return 1, 0, x
end

-- The Custom theme's colour: rainbow, class or picked.
local function CustomColour(offset)
    if settings.rainbow then
        return HueToRGB(GetTime() * 0.25 + (offset or 0))
    end
    if settings.classColour then
        local _, class = UnitClass("player")
        local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if colour then return colour.r, colour.g, colour.b end
    end
    return settings.colourR or 1, settings.colourG or 1, settings.colourB or 1
end

-- A colour along a list of stops, age 0 the first and 1 the last. No stops
-- means the Custom colour, dimming a little as it goes.
local function StopsColour(stops, age, offset)
    if not stops then
        local r, g, b = CustomColour(offset)
        local dim = 1 - 0.4 * age
        return r * dim, g * dim, b * dim
    end
    local count = #stops
    if count == 1 then return stops[1][1], stops[1][2], stops[1][3] end
    local position = math.max(0, math.min(1, age)) * (count - 1)
    local index = math.min(count - 1, math.floor(position) + 1)
    local t = position - (index - 1)
    local a, b = stops[index], stops[index + 1]
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- The simpler themes are written as one head / tail pair; they become a
-- single layer here, so every theme runs through the same code.
local layerCache = {}
local function LayersOf(theme)
    if theme.layers then return theme.layers end
    local cached = layerCache[theme.key]
    if cached then return cached end
    local size = theme.size or 1
    cached = { {
        shape = theme.spark, step = true, life = theme.life,
        stops = theme.head and { theme.head, theme.tail } or nil,
        rise = theme.rise, spread = theme.spread, sway = theme.sway, jitter = theme.jitter,
        spin = theme.spin, flicker = theme.flicker, perDrop = theme.perDrop, blend = theme.blend,
        size0 = theme.grow and 0.6 * size or size,
        size1 = theme.grow and (0.6 + theme.grow) * size or 0.4 * size,
        alpha = 0.9,
    } }
    layerCache[theme.key] = cached
    return cached
end

local function SparkColour(theme, age, offset)
    return StopsColour(LayersOf(theme)[1].stops, age, offset)
end

-- When the mouse rests, sparks circle it instead of falling behind it: they
-- spiral out from the pointer, turning, and wink out at the edge. The theme
-- lends its colours, so fire circles in orange and frost in blue.
local SWIRL = {
    shape = "dot", orbit = true, life = 2, lifeVar = 0.3,
    r0 = 10, r1 = 52, turns = 1.3, wobble = 6,
    size0 = 0.4, size1 = 0.12, alpha = 0.95, puff = true, flicker = 0.12,
}
local swirlCache = {}
local function SwirlLayer(theme)
    local cached = swirlCache[theme.key]
    if cached then return cached end
    cached = {}
    for key, value in pairs(SWIRL) do cached[key] = value end
    local first = LayersOf(theme)[1]
    cached.stops = first.stops
    if first.shape == "star" then cached.shape = "star" end
    swirlCache[theme.key] = cached
    return cached
end

local function HaloColour(theme)
    if settings.haloOwnColour then
        return settings.haloR or 1, settings.haloG or 1, settings.haloB or 1
    end
    if theme.haloColour then
        return theme.haloColour[1], theme.haloColour[2], theme.haloColour[3]
    end
    if theme.head then
        local h, t = theme.head, theme.tail
        return (h[1] + t[1]) / 2, (h[2] + t[2]) / 2, (h[3] + t[3]) / 2
    end
    return CustomColour()
end

-- ── Where the halo sits ─────────────────────────────────────────────────────
-- The game reports the pointer's tip. The hand is below and to the right of
-- it; this is roughly its middle at the default pointer size, and the offset
-- sliders take care of the rest.

local HAND_X, HAND_Y = 11, -13   -- in screen pixels

local function Anchor(cx, cy, scale)
    local x, y = cx / scale, cy / scale
    if settings.anchor == "hand" then
        x, y = x + HAND_X / scale, y + HAND_Y / scale
    end
    return x + (tonumber(settings.offsetX) or 0), y + (tonumber(settings.offsetY) or 0)
end

-- ── Building ────────────────────────────────────────────────────────────────

local haloAlphaScale = 1

local function RestyleAll()
    if not root then return end
    local theme = CurrentTheme()

    halo:SetSize(settings.haloSize, settings.haloSize)
    haloAlphaScale = ApplyShape(halo, theme.halo or settings.haloShape)
    halo:SetBlendMode(theme.blend or "ADD")
    halo:SetShown(settings.halo)

    shadow:SetSize(settings.shadowSize, settings.shadowSize)
    shadow:SetShown(settings.shadow)

    -- Sparks are shaped when they are dropped, since each layer has its own
    -- look; here they are only made and cleared.
    for index = 1, MAX_SPARKS do
        local spark = sparks[index]
        if not spark then
            spark = root:CreateTexture(nil, "ARTWORK")
            sparks[index] = spark
        end
        spark.layer, spark.shape = nil, nil
        spark:SetRotation(0)
        spark:Hide()
    end
    for _, layer in ipairs(LayersOf(theme)) do layer.acc, layer.timer = 0, 0 end
end

local function EnsureRoot()
    if root then return end

    -- TOOLTIP strata so the pointer's decoration sits over every window, the
    -- way the real pointer does. It takes no mouse input, so nothing under it
    -- stops being clickable.
    root = CreateFrame("Frame", nil, UIParent)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("TOOLTIP")
    root:EnableMouse(false)
    root:Hide()

    shadow = root:CreateTexture(nil, "BACKGROUND")
    shadow:SetTexture(GLOW)
    shadow:SetVertexColor(0, 0, 0, 1)

    halo = root:CreateTexture(nil, "ARTWORK", nil, 2)

    -- The game's own pointer art, drawn while steering hides the real one.
    arrow = root:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW)
    arrow:SetSize(32, 32)
    arrow:Hide()

    RestyleAll()
end

-- ── Clicks ──────────────────────────────────────────────────────────────────

local function Ripple(x, y)
    if not settings.ripple or not root or not root:IsShown() then return end

    -- Reuse a ring that has finished; make one when all are busy.
    local ring
    for _, candidate in ipairs(ripples) do
        if not candidate.anim:IsPlaying() then ring = candidate break end
    end
    if not ring then
        if #ripples >= 6 then return end   -- a storm of clicks needs no more
        ring = root:CreateTexture(nil, "ARTWORK", nil, 3)
        ring:SetBlendMode("ADD")
        ApplyShape(ring, "glow")
        ring:SetSize(24, 24)

        local anim = ring:CreateAnimationGroup()
        local grow = anim:CreateAnimation("Scale")
        grow:SetScaleFrom(0.4, 0.4)
        grow:SetScaleTo(3.2, 3.2)
        grow:SetDuration(0.45)
        grow:SetSmoothing("OUT")
        local fade = anim:CreateAnimation("Alpha")
        fade:SetFromAlpha(0.9)
        fade:SetToAlpha(0)
        fade:SetDuration(0.45)
        anim:SetScript("OnFinished", function() ring:Hide() end)
        ring.anim = anim
        ripples[#ripples + 1] = ring
    end

    local r, g, b = SparkColour(CurrentTheme(), 0)
    ring:SetVertexColor(r, g, b, 1)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    ring:Show()
    ring.anim:Stop()
    ring.anim:Play()
end

-- ── Every frame ─────────────────────────────────────────────────────────────
-- Only while the root is shown: a hidden frame gets no OnUpdate, so switching
-- the module off, or leaving combat with "only in combat" on, costs nothing.

local lastX, lastY = 0, 0
local curX, curY = 0, 0     -- where the pointer is now; the swirl circles it
local swirlTimer = 0
local lastMoveAt = 0
local sparkTimer = 0
local random = math.random

-- Shake detection: count how often the horizontal direction flips within a
-- short window while the mouse is moving fast.
local SHAKE_WINDOW, SHAKE_FLIPS, SHAKE_SPEED = 0.5, 4, 1200
local lastDirection, flips, flipStart = 0, 0, 0
local flareUntil = 0

-- Drops one spark of a layer at x, y. vx, vy is the mouse's own speed, for
-- layers thrown back along the path.
local function DropSpark(layer, x, y, mvx, mvy, now)
    if layer.chance and random() > layer.chance then return end
    local spark = sparks[nextSpark]
    nextSpark = nextSpark % MAX_SPARKS + 1

    local shape = layer.shape or (settings.haloShape == "star" and "star" or "dot")
    if spark.shape ~= shape then
        spark.alphaScale = ApplyShape(spark, shape)
        spark.shape = shape
    end
    spark:SetBlendMode(layer.blend or "ADD")

    local spread = layer.spread or 0
    local vx = (random() * 2 - 1) * spread
    local vy = (layer.rise or 0) + (random() * 2 - 1) * spread * 0.5
    if layer.behind then
        vx = vx - mvx * layer.behind
        vy = vy - mvy * layer.behind
    end
    -- Capped: a fast flick used to hand a spark a thousand pixels a second,
    -- and it shot off across the monitor as a long streak, well away from
    -- anything the pointer was doing.
    vx = math.max(-MAX_SPARK_SPEED, math.min(MAX_SPARK_SPEED, vx))
    vy = math.max(-MAX_SPARK_SPEED, math.min(MAX_SPARK_SPEED, vy))

    local life = layer.life or math.max(0.1, tonumber(settings.trailLife) or 0.4)
    if layer.lifeVar then life = life * (1 + (random() * 2 - 1) * layer.lifeVar) end

    spark.layer = layer
    spark.born, spark.life = now, life
    spark.x, spark.y = x, y
    spark.bx, spark.by = x, y
    spark.vx, spark.vy = vx, vy
    spark.phase = random() * 6.28
    spark.angle = random() * 6.28
    spark.sizeVar = 0.75 + random() * 0.5
    if layer.orbit then spark.dir = random() < 0.5 and 1 or -1 end
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    spark:SetAlpha(0)
    spark:Show()
end

-- Moves, colours and sizes one live spark; hides it once it has burnt out.
local function UpdateSpark(spark, elapsed, now, baseSize, index)
    local layer = spark.layer
    local age = (now - spark.born) / spark.life
    if age >= 1 or not layer then
        spark:Hide()
        spark.layer = nil
        return
    end

    -- Circling the resting pointer: out along a spiral, around it as it goes.
    -- The centre is read live, so nudging the mouse carries the ring with it.
    if layer.orbit then
        local angle = spark.angle + spark.dir * age * (layer.turns or 1) * 6.28
        local radius = layer.r0 + (layer.r1 - layer.r0) * age
            + math.sin(age * 12 + spark.phase) * (layer.wobble or 0)
        local px = curX + math.cos(angle) * radius
        local py = curY + math.sin(angle) * radius
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)

        local alpha = math.sin(age * math.pi) * (layer.alpha or 0.9) * (spark.alphaScale or 1)
        if layer.flicker then alpha = alpha * (1 - layer.flicker * random()) end
        local r, g, b = StopsColour(layer.stops, age, index * 0.04)
        spark:SetVertexColor(r, g, b, 1)
        spark:SetAlpha(alpha)

        local s0, s1 = layer.size0 or 1, layer.size1 or 0.4
        local size = baseSize * spark.sizeVar * (s0 + (s1 - s0) * age)
        spark:SetSize(size, size)
        return
    end

    -- Buoyancy speeds a flame up as it rises; gravity pulls debris down;
    -- drag slows whatever was thrown.
    if layer.lift then spark.vy = spark.vy + layer.lift * elapsed end
    if layer.gravity then spark.vy = spark.vy + layer.gravity * elapsed end
    if layer.drag then
        local keep = math.max(0, 1 - layer.drag * elapsed)
        spark.vx = spark.vx * keep
    end
    spark.x = spark.x + spark.vx * elapsed
    spark.y = spark.y + spark.vy * elapsed

    -- A hard leash. Whatever went wrong -- a stutter, a flick, a pointer that
    -- jumped -- a spark that has left this circle is no longer part of the
    -- trail, and it is put out rather than drawn streaking across the screen.
    local awayX, awayY = spark.x - spark.bx, spark.y - spark.by
    if awayX * awayX + awayY * awayY > MAX_TRAVEL * MAX_TRAVEL then
        spark:Hide()
        spark.layer = nil
        return
    end

    local px, py = spark.x, spark.y
    if layer.sway then
        px = px + math.sin(age * 9 + spark.phase) * layer.sway * 0.25 * age
    end
    if layer.jitter then
        px = px + (random() * 2 - 1) * layer.jitter
        py = py + (random() * 2 - 1) * layer.jitter
    end
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", UIParent, "BOTTOMLEFT", px, py)
    if layer.spin then spark:SetRotation(spark.angle + age * layer.spin * 6.28) end

    -- Alpha: fades out, or for smoke swells in and out again after a delay.
    local alpha
    if layer.puff then
        local start = layer.startAt or 0
        if age < start then
            alpha = 0
        else
            alpha = math.sin((age - start) / (1 - start) * math.pi)
        end
    else
        alpha = (1 - age) ^ (layer.alphaPow or 1)
    end
    alpha = alpha * (layer.alpha or 0.9) * (spark.alphaScale or 1)
    if layer.flicker then alpha = alpha * (1 - layer.flicker * random()) end

    local r, g, b = StopsColour(layer.stops, age, index * 0.04)
    spark:SetVertexColor(r, g, b, 1)
    spark:SetAlpha(alpha)

    local s0, s1 = layer.size0 or 1, layer.size1 or 0.4
    local size = baseSize * spark.sizeVar * (s0 + (s1 - s0) * age)
    spark:SetSize(size, size)
end

local function OnUpdate(_, elapsed)
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local tipX, tipY = cx / scale, cy / scale
    local x, y = Anchor(cx, cy, scale)
    curX, curY = x, y
    local now = GetTime()
    local theme = CurrentTheme()

    local dx, dy = x - lastX, y - lastY
    local moved = (dx * dx + dy * dy) > 0.25
    if moved then lastMoveAt = now end

    -- Shake to find.
    if settings.shake and elapsed > 0 then
        local speed = math.abs(dx) / elapsed
        local direction = dx > 0 and 1 or (dx < 0 and -1 or 0)
        if speed > SHAKE_SPEED and direction ~= 0 and direction ~= lastDirection then
            if now - flipStart > SHAKE_WINDOW then flips, flipStart = 0, now end
            flips = flips + 1
            lastDirection = direction
            if flips >= SHAKE_FLIPS then
                flareUntil = now + 0.7
                flips = 0
            end
        end
    end

    -- Fading out when idle, back in the moment it moves.
    local alpha = 1
    if settings.fadeIdle then
        local idle = now - lastMoveAt
        local start = tonumber(settings.idleSeconds) or 3
        if idle > start then alpha = math.max(0, 1 - (idle - start) / 0.6) end
    end
    root:SetAlpha(alpha)

    -- Halo, flaring up after a shake, flickering for themes that do.
    if settings.halo then
        local size = settings.haloSize * (theme.haloScale or 1)
        if now < flareUntil then
            local left = (flareUntil - now) / 0.7
            size = size * (1 + 2.2 * left)
        end
        local flicker = theme.flicker or 0
        local strength = 1
        if flicker > 0 then
            strength = 1 - flicker * 0.5 * (0.5 + 0.5 * math.sin(now * 23) * math.sin(now * 7.3))
        end
        halo:SetSize(size, size)
        halo:ClearAllPoints()
        halo:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        local r, g, b = HaloColour(theme)
        halo:SetVertexColor(r, g, b, (settings.haloAlpha or 0.85) * haloAlphaScale * strength)
        if theme.spin then halo:SetRotation(now * theme.spin * 0.5) else halo:SetRotation(0) end
    end

    if settings.shadow then
        shadow:ClearAllPoints()
        shadow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        shadow:SetAlpha(settings.shadowAlpha or 0.35)
    end

    -- Steering: the game hides the pointer, so show its arrow where it froze.
    local steering = settings.steering and IsMouselooking and IsMouselooking()
    if steering then
        arrow:ClearAllPoints()
        -- The arrow's tip is its top-left corner, same as the real pointer.
        arrow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tipX, tipY)
        arrow:Show()
    elseif arrow:IsShown() then
        arrow:Hide()
    end

    -- Trail: drop sparks along the path, spaced so a still mouse leaves no
    -- pile of dots behind it.
    if settings.trail then
        -- Trail length scales how thick every layer is: 14 is the design.
        local length = math.max(4, math.min(60, tonumber(settings.trailLength) or 14))
        local density = length / 14
        local distance = math.sqrt(dx * dx + dy * dy)
        local mvx = elapsed > 0 and dx / elapsed or 0
        local mvy = elapsed > 0 and dy / elapsed or 0
        local speed = math.sqrt(mvx * mvx + mvy * mvy)
        if speed > 900 then
            local keep = 900 / speed
            mvx, mvy = mvx * keep, mvy * keep
        end
        -- A jump across the screen (a loading screen, the pointer coming
        -- back from steering) is not a path to fill with fire.
        -- A long frame is a stutter or a loading screen, not a real path.
        local jumped = distance > 300 or elapsed > 0.1

        for _, layer in ipairs(LayersOf(theme)) do
            if layer.step then
                -- The simple themes: a spark every so often while moving.
                layer.timer = (layer.timer or 0) + elapsed
                local life = layer.life or math.max(0.1, tonumber(settings.trailLife) or 0.4)
                if moved and not jumped and layer.timer >= life / length then
                    layer.timer = 0
                    for _ = 1, layer.perDrop or 1 do
                        DropSpark(layer, x, y, mvx * 0.15, mvy * 0.15, now)
                    end
                end
            else
                -- Burning in place, whether the mouse moves or not.
                if layer.rate then
                    layer.timer = (layer.timer or 0) + elapsed * layer.rate * density
                    local count = 0
                    while layer.timer >= 1 and count < 8 do
                        layer.timer = layer.timer - 1
                        count = count + 1
                        DropSpark(layer, x + (random() * 2 - 1) * 3, y + (random() * 2 - 1) * 3, mvx, mvy, now)
                    end
                end
                -- Laid along the path, filled in between this frame and the
                -- last so a fast flick stays one unbroken streak.
                if layer.spacing and moved and not jumped then
                    local spacing = layer.spacing / density
                    layer.acc = (layer.acc or 0) + distance
                    local count = 0
                    while layer.acc >= spacing and count < 24 do
                        layer.acc = layer.acc - spacing
                        count = count + 1
                        local t = distance > 0 and (layer.acc / distance) or 0
                        DropSpark(layer, x - dx * t, y - dy * t, mvx, mvy, now)
                    end
                end
            end
        end

        -- At rest: sparks circle the pointer instead of trailing behind it.
        if settings.idleSwirl and (now - lastMoveAt) > (tonumber(settings.swirlDelay) or 0.3) then
            swirlTimer = swirlTimer + elapsed * 11 * density
            local count = 0
            while swirlTimer >= 1 and count < 4 do
                swirlTimer = swirlTimer - 1
                count = count + 1
                DropSpark(SwirlLayer(theme), x, y, 0, 0, now)
            end
        else
            swirlTimer = 0
        end

        local baseSize = tonumber(settings.trailSize) or 14
        for index = 1, MAX_SPARKS do
            local spark = sparks[index]
            if spark.layer then UpdateSpark(spark, elapsed, now, baseSize, index) end
        end
    end

    lastX, lastY = x, y
end

-- ── When to show ────────────────────────────────────────────────────────────

local function ShouldShow()
    if not settings or settings.enabled == false then return false end
    if settings.onlyCombat and not InCombatLockdown() then return false end
    return true
end

local function ApplyVisibility()
    if not root then return end
    local show = ShouldShow()
    root:SetShown(show)
    if not show then
        for _, spark in ipairs(sparks) do spark:Hide() end
        if arrow then arrow:Hide() end
    end
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "GLOBAL_MOUSE_DOWN" then
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        Ripple(Anchor(cx, cy, scale))
        return
    end
    ApplyVisibility()
end)

local function Start()
    EnsureRoot()
    RestyleAll()
    root:SetScript("OnUpdate", OnUpdate)
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- A click anywhere, even on the game world; nothing is intercepted.
    pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN")
    ApplyVisibility()
end

local function Stop()
    watcher:UnregisterAllEvents()
    if root then
        root:SetScript("OnUpdate", nil)
        root:Hide()
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.cursor
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.cursor = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

-- A labelled slider bound to one numeric setting.
local function AddSlider(w, key, caption, minValue, maxValue, step, format, apply)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(200, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 230, w.cursorY - 6)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local function Show(value) label:SetText((format):format(caption, value)) end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        settings[key] = value
        if apply then apply() end
    end)
    w:HookScript("OnShow", function()
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
    end)
    w.cursorY = w.cursorY - 30
end

-- A row of small buttons, one per choice, the picked one lit.
local function AddChoiceRow(w, key, caption, choices, perRow, apply)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    label:SetText(caption)

    local buttons = {}
    local function Repaint()
        for _, entry in ipairs(buttons) do
            entry.button:SetNormalFontObject(settings[key] == entry.key
                and "GameFontNormal" or "GameFontDisableSmall")
        end
    end
    local width = perRow > 3 and 70 or 80
    for index, choice in ipairs(choices) do
        local column = (index - 1) % perRow
        local rowIndex = math.floor((index - 1) / perRow)
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", w, "TOPLEFT", 120 + column * (width + 4), w.cursorY - 2 - rowIndex * 24)
        button:SetText(choice.name)
        button:SetScript("OnClick", function()
            settings[key] = choice.key
            Repaint()
            if apply then apply() end
        end)
        buttons[#buttons + 1] = { key = choice.key, button = button }
    end
    w:HookScript("OnShow", Repaint)
    w.cursorY = w.cursorY - 6 - math.ceil(#choices / perRow) * 24
end

-- Opens the game's colour picker on the chosen colour.
-- keys are the three settings holding the colour, red first.
local function PickColour(keys)
    if not ColorPickerFrame then return end
    local before = { settings[keys[1]], settings[keys[2]], settings[keys[3]] }
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        settings[keys[1]], settings[keys[2]], settings[keys[3]] = r, g, b
    end
    local info = {
        r = settings[keys[1]], g = settings[keys[2]], b = settings[keys[3]],
        swatchFunc = Apply,
        cancelFunc = function()
            settings[keys[1]], settings[keys[2]], settings[keys[3]] = before[1], before[2], before[3]
        end,
    }
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Cursor", 470, 900)
        local w = optionsWindow

        AddChoiceRow(w, "theme", "Theme", THEMES, 4, RestyleAll)
        AddChoiceRow(w, "anchor", "Sits on", {
            { key = "hand", name = "Hand" },
            { key = "tip",  name = "Tip" },
        }, 3)
        AddSlider(w, "offsetX", "Nudge sideways", -40, 40, 1, "%s: %d")
        AddSlider(w, "offsetY", "Nudge up / down", -40, 40, 1, "%s: %d")

        w:AddCheckbox(settings, "halo", "Glow around the hand", nil, RestyleAll)
        AddChoiceRow(w, "haloShape", "Glow shape", {
            { key = "glow", name = "Glow" },
            { key = "ring", name = "Ring" },
            { key = "dot",  name = "Dot" },
            { key = "star", name = "Star" },
        }, 4, RestyleAll)
        AddSlider(w, "haloSize", "Glow size", 20, 120, 2, "%s: %d", RestyleAll)
        AddSlider(w, "haloAlpha", "Glow strength", 0.1, 1, 0.05, "%s: %.2f")
        w:AddCheckbox(settings, "haloOwnColour", "Own colour for the glow",
            "Off, the glow takes the theme's colour: orange for Fire, white-hot for Meteor, your class colour in Custom.")

        local glowPick = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        glowPick:SetSize(150, 22)
        glowPick:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        glowPick:SetText("Pick glow colour")
        glowPick:SetScript("OnClick", function() PickColour({ "haloR", "haloG", "haloB" }) end)
        w.cursorY = w.cursorY - 30

        w:AddCheckbox(settings, "shadow", "Shadow behind it", "A soft dark disc that keeps the pointer readable over bright spell effects.", RestyleAll)
        AddSlider(w, "shadowAlpha", "Shadow strength", 0.05, 0.8, 0.05, "%s: %.2f")

        w:AddCheckbox(settings, "trail", "Trail of sparks")
        AddSlider(w, "trailLength", "Trail length", 4, 60, 1, "%s: %d")
        AddSlider(w, "trailSize", "Spark size", 6, 40, 1, "%s: %d")

        w:AddNote("Colours below are for the Custom theme; the others bring their own.")
        w:AddCheckbox(settings, "classColour", "Class colour", "Untick to use your own colour.")
        w:AddCheckbox(settings, "rainbow", "Rainbow", "Cycles through every colour; the trail runs through them too.")

        local pick = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        pick:SetSize(130, 22)
        pick:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        pick:SetText("Pick trail colour")
        pick:SetScript("OnClick", function() PickColour({ "colourR", "colourG", "colourB" }) end)
        w.cursorY = w.cursorY - 30

        w:AddCheckbox(settings, "steering", "Keep the pointer while steering",
            "Holding the right button hides the pointer. This draws it where it froze, so you always know where it will come back.")
        w:AddCheckbox(settings, "ripple", "Ripple on every click")
        w:AddCheckbox(settings, "shake", "Shake to find it", "Wiggle the mouse quickly left and right and the halo flares up.")
        w:AddCheckbox(settings, "onlyCombat", "Only in combat", nil, ApplyVisibility)
        w:AddCheckbox(settings, "idleSwirl", "Magic circles when the mouse rests",
            "Let go of the mouse and the sparks spiral around the pointer in the theme's colours instead of trailing behind it.")
        AddSlider(w, "swirlDelay", "Circles start after", 0, 3, 0.1, "%s: %.1f s")
        w:AddCheckbox(settings, "fadeIdle", "Fade out when the mouse is still",
            "Hides everything while the mouse is untouched. It turns the circles off too, since there is nothing left to see.")
    end
    optionsWindow:Show()
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
        id       = "cursor",
        name     = "Cursor",
        version  = "1.1.0",
        author   = "Oxed",
        category = "interface",
        keywords = { "cursor", "mouse", "pointer", "trail", "glow", "halo", "steering", "mouselook", "find", "fire", "frost", "meteor", "lightning" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Fire, frost, meteor and more on your pointer: halo, trail, click ripples.",
        icon     = "Interface\\Icons\\Spell_Arcane_Arcane04",

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
