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
-- glow, an ember, a ring, a twinkle, a snowflake and a leaf. Lightning is
-- drawn with lines. The game's own glow atlases were tried first and
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
    trailOwnColour = false, -- a built-in theme (Fire, Arcane...) in the picked colour
    colourR      = 0.55,
    colourG      = 0.35,
    colourB      = 1.00,

    steering     = true,    -- draw the arrow while the right button steers
    steerStyle   = "arrow", -- arrow, ghost or glow
    steerScale   = 1,
    steerAlpha   = 1,
    steerGlow    = true,    -- the theme's glow behind the steering arrow

    -- The game's own pointer. "game" leaves the game's setting alone; any
    -- other choice sets it, and switching the module off puts it back.
    pointerSize  = "game",  -- game, auto, 32, 48, 64, 96, 128
    lookDelta    = "game",  -- game, instant, normal, late
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
local bolts = {}        -- lightning bolts; drawn further down
local echoes = {}       -- Windows 95 pointer trails
local MAX_ECHOES = 12
local WIN95_ARROW = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Cursor\\win95"
local HideBolt          -- defined with the bolts, used earlier by RestyleAll
local nextSpark = 1
-- Each layer draws from a pool of its own, taken in turn. One shared pool let
-- a dense tail eat the embers and the smoke, and at speed it ate its own far
-- end: a meteor lays a spark every three pixels, so a fast flick wanted more
-- than two hundred of them at once and the ring came round and overwrote the
-- oldest, which is the end of the tail. A pool per layer keeps a tail that
-- shortens at the back instead of breaking in the middle.
local POOL = 70
local watcher = CreateFrame("Frame")
local wasSteering = false   -- the pointer was frozen last frame
local MAX_SPARK_SPEED = 320   -- pixels a second; see DropSpark
local MAX_TRAVEL = 150        -- how far from its birthplace a spark may get

-- The screen's height in real pixels. Called directly, never as
-- "GetPhysicalScreenSize and GetPhysicalScreenSize()": an "and" keeps only
-- the first value, the width, and the height came back nil. The pointer was
-- then sized for a 768 pixel screen and drawn far too big.
local function ScreenHeightPx()
    if not GetPhysicalScreenSize then return nil end
    local _, height = GetPhysicalScreenSize()
    return height
end

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
    twinkle = { { file = MEDIA .. "twinkle" } },
    flake = { { file = MEDIA .. "flake" } },
    leaf  = { { file = MEDIA .. "leaf" } },
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
--   bolt     not a spark: a forked lightning bolt drawn with lines

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
    -- Frost: snowflakes that turn as they drift down, glints of ice that
    -- flash and vanish, and a pale mist that hangs behind the pointer.
    { key = "frost",     name = "Frost",
      halo = "glow", haloColour = { 0.55, 0.85, 1 },
      layers = {
          { shape = "flake", spacing = 16, rate = 2, life = 1.6, lifeVar = 0.3, blend = "ADD",
            stops = { { 1, 1, 1 }, { 0.7, 0.9, 1 }, { 0.35, 0.6, 1 } },
            rise = -28, spread = 14, sway = 30, spin = 0.35, drag = 0.6,
            size0 = 1.0, size1 = 0.7, alpha = 0.9, alphaPow = 1.4 },
          { shape = "twinkle", spacing = 14, scatter = 10, life = 0.45, lifeVar = 0.3,
            stops = { { 1, 1, 1 }, { 0.6, 0.85, 1 } },
            spread = 18, size0 = 0.55, size1 = 0.1, alpha = 0.95, flicker = 0.5 },
          { shape = "soft", spacing = 7, life = 0.9, lifeVar = 0.2,
            stops = { { 0.6, 0.85, 1 }, { 0.25, 0.45, 0.9 } },
            rise = -8, spread = 6, size0 = 1.2, size1 = 2.2, alpha = 0.1, puff = true },
      } },
    -- Arcane: violet sparkles flung out and slowed as if by thick air,
    -- runic rings that open and fade, and a soft glow along the path.
    { key = "arcane",    name = "Arcane",
      halo = "ring", haloColour = { 0.8, 0.45, 1 }, spin = 0.6,
      layers = {
          { shape = "twinkle", spacing = 14, scatter = 12, chance = 0.8, rate = 6, life = 0.9, lifeVar = 0.3,
            stops = { { 1, 0.85, 1 }, { 0.85, 0.4, 1 }, { 0.35, 0.15, 0.9 } },
            spread = 70, drag = 3.5, spin = 0.5,
            size0 = 0.6, size1 = 0.15, alpha = 0.95, flicker = 0.3 },
          { shape = "ring", spacing = 55, life = 0.7, accent = true,
            stops = { { 0.95, 0.6, 1 }, { 0.4, 0.2, 1 } },
            size0 = 0.8, size1 = 3.4, alpha = 0.45, alphaPow = 1.3 },
          { shape = "soft", spacing = 5, life = 0.5, lifeVar = 0.2,
            stops = { { 0.8, 0.4, 1 }, { 0.3, 0.1, 0.8 } },
            size0 = 1.4, size1 = 0.6, alpha = 0.12 },
      } },
    -- Lightning: real forked bolts that crackle out from the pointer, bright
    -- sparks, and a cold blue glow left in the air.
    { key = "lightning", name = "Lightning",
      halo = "glow", haloColour = { 0.5, 0.75, 1 }, flicker = 0.7,
      layers = {
          { bolt = true, spacing = 70, rate = 3, life = 0.16, reach = 55, segments = 7, accent = true,
            thickness = 2, stops = { { 1, 1, 1 }, { 0.55, 0.8, 1 } } },
          { shape = "dot", spacing = 10, life = 0.3, lifeVar = 0.4,
            stops = { { 1, 1, 1 }, { 0.5, 0.75, 1 } },
            spread = 120, drag = 5, jitter = 2,
            size0 = 0.3, size1 = 0.1, alpha = 1, flicker = 0.7 },
          { shape = "soft", spacing = 6, life = 0.35,
            stops = { { 0.6, 0.8, 1 }, { 0.2, 0.35, 1 } },
            size0 = 1.3, size1 = 0.5, alpha = 0.14, flicker = 0.5 },
      } },
    -- Nature: leaves that tumble down and turn from green to autumn, pollen
    -- that floats up, and a fresh green glow.
    { key = "nature",    name = "Nature",
      halo = "glow", haloColour = { 0.45, 0.9, 0.35 },
      layers = {
          { shape = "leaf", spacing = 22, rate = 1.5, life = 1.8, lifeVar = 0.3, blend = "BLEND",
            stops = { { 0.45, 0.85, 0.25 }, { 0.75, 0.8, 0.2 }, { 0.8, 0.45, 0.12 } },
            rise = -30, spread = 16, sway = 55, spin = 0.5, drag = 0.8,
            size0 = 1.1, size1 = 0.9, alpha = 0.95, alphaPow = 2 },
          { shape = "dot", spacing = 12, rate = 4, life = 1.6, lifeVar = 0.4,
            stops = { { 1, 1, 0.6 }, { 0.8, 1, 0.4 } },
            rise = 18, spread = 12, sway = 25,
            size0 = 0.18, size1 = 0.1, alpha = 0.9, flicker = 0.3 },
          { shape = "soft", spacing = 6, life = 0.5,
            stops = { { 0.5, 1, 0.4 }, { 0.15, 0.5, 0.15 } },
            size0 = 1.2, size1 = 0.5, alpha = 0.1 },
      } },
    -- Void: dark smoke that swells and hangs, violet wisps curling up
    -- through it, and a faint glow at its heart. Saved as "shadow", the name
    -- it had first, so a player's choice survives the rename.
    { key = "shadow",    name = "Void",
      halo = "glow", haloColour = { 0.5, 0.15, 0.8 },
      layers = {
          { shape = "soft", spacing = 6, rate = 12, life = 1.2, lifeVar = 0.3, blend = "BLEND",
            stops = { { 0.12, 0.02, 0.18 }, { 0.05, 0, 0.08 } },
            rise = 22, spread = 8, sway = 20,
            size0 = 1.0, size1 = 3.0, alpha = 0.45, puff = true },
          { shape = "soft", spacing = 12, rate = 5, life = 1.0, lifeVar = 0.3,
            stops = { { 0.85, 0.45, 1 }, { 0.5, 0.15, 0.85 }, { 0.2, 0, 0.4 } },
            rise = 35, lift = 25, spread = 10, sway = 45,
            size0 = 0.45, size1 = 0.15, alpha = 0.55 },
          { shape = "twinkle", spacing = 30, life = 0.5,
            stops = { { 0.9, 0.6, 1 }, { 0.4, 0.1, 0.7 } },
            spread = 20, size0 = 0.4, size1 = 0.1, alpha = 0.8, flicker = 0.5 },
      } },
    -- Holy: golden light that rises gently, sparkling motes, and bright
    -- rings of light that open where the pointer passes.
    { key = "holy",      name = "Holy",
      halo = "glow", haloColour = { 1, 0.85, 0.45 },
      layers = {
          { shape = "twinkle", spacing = 16, scatter = 10, rate = 5, life = 1.2, lifeVar = 0.3,
            stops = { { 1, 1, 0.9 }, { 1, 0.85, 0.4 }, { 1, 0.6, 0.15 } },
            rise = 30, lift = 20, spread = 14, sway = 20, spin = 0.15,
            size0 = 0.55, size1 = 0.15, alpha = 0.95, flicker = 0.25 },
          { shape = "ring", spacing = 70, life = 0.8, accent = true,
            stops = { { 1, 0.95, 0.7 }, { 1, 0.7, 0.2 } },
            size0 = 0.6, size1 = 3.0, alpha = 0.4, alphaPow = 1.4 },
          { shape = "soft", spacing = 5, life = 0.6,
            stops = { { 1, 0.9, 0.55 }, { 1, 0.6, 0.15 } },
            rise = 10, size0 = 1.3, size1 = 0.6, alpha = 0.12 },
      } },
    -- Fel: the green fire of the Burning Legion, with sickly embers and a
    -- black smoke.
    { key = "fel",       name = "Fel",
      halo = "glow", haloColour = { 0.35, 1, 0.15 }, flicker = 0.35,
      layers = {
          { shape = "soft", rate = 34, spacing = 6, life = 0.55, lifeVar = 0.25,
            stops = { { 0.85, 1, 0.6 }, { 0.45, 1, 0.15 }, { 0.15, 0.7, 0.05 }, { 0.03, 0.25, 0.02 } },
            rise = 25, lift = 150, spread = 10, sway = 18,
            size0 = 1.1, size1 = 0.2, alpha = 0.22, alphaPow = 0.9, flicker = 0.25 },
          { shape = "dot", rate = 7, spacing = 40, life = 1.3, lifeVar = 0.5,
            stops = { { 0.9, 1, 0.5 }, { 0.4, 1, 0.1 }, { 0.1, 0.5, 0 } },
            rise = 40, lift = 40, spread = 28, sway = 30, drag = 0.4,
            size0 = 0.2, size1 = 0.07, alpha = 0.85, flicker = 0.6 },
          { shape = "soft", rate = 5, spacing = 45, life = 1.4, lifeVar = 0.4, blend = "BLEND",
            stops = { { 0.06, 0.1, 0.04 }, { 0.03, 0.03, 0.03 } },
            rise = 55, lift = 30, spread = 10, sway = 22, startAt = 0.12,
            size0 = 0.9, size1 = 2.4, alpha = 0.22, puff = true },
      } },
    -- Blood: heavy drops that fall and darken, with a thin red mist.
    { key = "blood",     name = "Blood",
      halo = "glow", haloColour = { 0.85, 0.05, 0.05 },
      layers = {
          { shape = "dot", spacing = 11, rate = 2, life = 1.1, lifeVar = 0.3, blend = "BLEND",
            stops = { { 0.8, 0.05, 0.05 }, { 0.55, 0.02, 0.02 }, { 0.3, 0, 0 } },
            spread = 22, gravity = -420, drag = 0.5,
            size0 = 0.45, size1 = 0.3, alpha = 0.95, alphaPow = 2 },
          { shape = "soft", spacing = 7, life = 0.8,
            stops = { { 0.7, 0.05, 0.05 }, { 0.3, 0, 0 } },
            spread = 6, size0 = 1.0, size1 = 1.8, alpha = 0.12, puff = true },
      } },
    -- Bubbles: rising bubbles that wobble on the way up and pop with a glint.
    { key = "bubbles",   name = "Bubbles",
      halo = "ring", haloColour = { 0.6, 0.9, 1 },
      layers = {
          { shape = "ring", spacing = 18, rate = 3, life = 1.6, lifeVar = 0.4,
            stops = { { 0.85, 1, 1 }, { 0.5, 0.85, 1 } },
            rise = 45, lift = 20, spread = 10, sway = 45,
            size0 = 0.6, size1 = 1.1, alpha = 0.7, alphaPow = 0.5 },
          { shape = "twinkle", spacing = 30, life = 0.35,
            stops = { { 1, 1, 1 }, { 0.6, 0.9, 1 } },
            spread = 10, rise = 30, size0 = 0.4, size1 = 0.1, alpha = 0.9 },
      } },
    -- Fairy: a glittering dust in every colour, drifting and twinkling.
    { key = "fairy",     name = "Fairy",
      halo = "glow", haloColour = { 1, 0.7, 0.95 },
      layers = {
          { shape = "twinkle", spacing = 12, scatter = 12, rate = 8, life = 1.2, lifeVar = 0.4,
            stops = { { 1, 0.5, 0.8 }, { 1, 0.9, 0.4 }, { 0.5, 1, 0.6 }, { 0.5, 0.7, 1 }, { 0.8, 0.5, 1 } },
            rise = -10, spread = 25, sway = 30, drag = 1.5, spin = 0.3,
            size0 = 0.45, size1 = 0.15, alpha = 1, flicker = 0.45 },
          { shape = "soft", spacing = 6, life = 0.6,
            stops = { { 1, 0.7, 0.95 }, { 0.6, 0.5, 1 } },
            size0 = 1.2, size1 = 0.5, alpha = 0.1 },
      } },
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
    -- Windows 95: the old "pointer trails" option. A line of arrows, each a
    -- moment behind the one before, that catches up when the mouse stops.
    -- No glow, no shadow, no sparks: just the arrows, as it was. The one
    -- layer is there only to lend the circles a colour; it drops nothing.
    { key = "win95",     name = "Windows 95",
      noHalo = true, noShadow = true, noSwirl = true,
      echo = { gap = 0.035 },
      layers = {
          { shape = "dot", stops = { { 1, 1, 1 }, { 0.75, 0.75, 0.75 } } },
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

-- A built-in theme recoloured: the picked colour (or the rainbow) takes the
-- place of the theme's own hue, and each stop keeps its brightness, so Fire
-- in green still runs from a bright head to a dark tail. Near-white stops
-- keep some of their white, which is what makes the head look hot.
local function Tinted(r, g, b, offset)
    if not (settings.trailOwnColour or settings.rainbow) then return r, g, b end
    local tr, tg, tb
    if settings.rainbow then
        tr, tg, tb = HueToRGB(GetTime() * 0.25 + (offset or 0))
    else
        tr, tg, tb = settings.colourR or 1, settings.colourG or 1, settings.colourB or 1
    end
    local v = math.max(r, g, b)
    local white = v > 0 and 0.6 * math.min(r, g, b) / v or 0
    return (tr * (1 - white) + white) * v, (tg * (1 - white) + white) * v, (tb * (1 - white) + white) * v
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
    if count == 1 then return Tinted(stops[1][1], stops[1][2], stops[1][3], offset) end
    local position = math.max(0, math.min(1, age)) * (count - 1)
    local index = math.min(count - 1, math.floor(position) + 1)
    local t = position - (index - 1)
    local a, b = stops[index], stops[index + 1]
    return Tinted(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, offset)
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
        return Tinted(theme.haloColour[1], theme.haloColour[2], theme.haloColour[3])
    end
    if theme.head then
        local h, t = theme.head, theme.tail
        return Tinted((h[1] + t[1]) / 2, (h[2] + t[2]) / 2, (h[3] + t[3]) / 2)
    end
    return CustomColour()
end

-- ── Where the halo sits ─────────────────────────────────────────────────────
-- The game reports the pointer's tip. The hand is below and to the right of
-- it; this is roughly its middle at the default pointer size, and the offset
-- sliders take care of the rest.

local HAND_X, HAND_Y = 11, -13   -- in screen pixels, for a 32 pixel pointer

-- ── The game's own pointer ──────────────────────────────────────────────────
-- Two game settings the pointer depends on:
--   cursorSizePreferred       -1 picks a size from the resolution, 0-4 fix it
--   CursorFreelookStartDelta  how far the mouse must move with a button held
--                             before the camera starts turning; 0 turns at once
-- Only touched when the player picks something other than "Game". The value
-- the game had is kept first, and put back when "Game" is picked again or
-- the module is switched off.

local SIZE_CVAR = { auto = -1, ["32"] = 0, ["48"] = 1, ["64"] = 2, ["96"] = 3, ["128"] = 4 }
local SIZE_PX = { [0] = 32, [1] = 48, [2] = 64, [3] = 96, [4] = 128 }
local DELTA_CVAR = { instant = 0, normal = 0.001, late = 0.005 }

local pointerPx = 32   -- the pointer's size now, read when it may have changed

local function ReadPointerPx()
    local value = tonumber(GetCVar and GetCVar("cursorSizePreferred"))
    if value and SIZE_PX[value] then
        pointerPx = SIZE_PX[value]
    else
        -- Automatic: the game grows the pointer with the screen's height.
        local height = ScreenHeightPx()
        local steps = height and math.floor(height / 1080 + 0.25) or 1
        pointerPx = SIZE_PX[math.max(0, math.min(4, steps - 1))] or 32
    end
end

local function SetGameValue(cvar, value, backupKey)
    if not (GetCVar and SetCVar) then return end
    local current = GetCVar(cvar)
    if current == nil then return end
    if settings[backupKey] == nil then settings[backupKey] = current end
    if tonumber(current) ~= value then pcall(SetCVar, cvar, value) end
end

local function RestoreGameValue(cvar, backupKey)
    local saved = settings[backupKey]
    if saved == nil then return end
    if SetCVar then pcall(SetCVar, cvar, saved) end
    settings[backupKey] = nil
end

local function ApplyGamePointer()
    if not settings or settings.enabled == false then return end
    local size = SIZE_CVAR[tostring(settings.pointerSize)]
    if size then
        SetGameValue("cursorSizePreferred", size, "savedPointerSize")
    else
        RestoreGameValue("cursorSizePreferred", "savedPointerSize")
    end
    local delta = DELTA_CVAR[tostring(settings.lookDelta)]
    if delta then
        SetGameValue("CursorFreelookStartDelta", delta, "savedLookDelta")
    else
        RestoreGameValue("CursorFreelookStartDelta", "savedLookDelta")
    end
    ReadPointerPx()
end

local function RestoreGamePointer()
    if not settings then return end
    RestoreGameValue("cursorSizePreferred", "savedPointerSize")
    RestoreGameValue("CursorFreelookStartDelta", "savedLookDelta")
    ReadPointerPx()
end

-- The game's pointer is drawn in real screen pixels, and the UI is not: one
-- UI unit is 768ths of the screen's height, then scaled by the UI scale. A
-- copy drawn "32 wide" in UI units is therefore bigger or smaller than the
-- real 32 pixel pointer on most screens, and the hand seemed to change size
-- the moment the copy took over. This turns real pixels into UI units.
local function PixelsToUI(px)
    local height = ScreenHeightPx()
    if not height or height <= 0 then height = 768 end
    return px * 768 / height / UIParent:GetEffectiveScale()
end

-- The same for the cursor position's own units, which are the UI's at scale 1.
local function PixelsToCursor(px)
    local height = ScreenHeightPx()
    if not height or height <= 0 then height = 768 end
    return px * 768 / height
end

local function Anchor(cx, cy, scale)
    local x, y = cx / scale, cy / scale
    if settings.anchor == "hand" then
        -- The hand grows with the pointer, so its middle does too.
        local grow = pointerPx / 32
        x = x + PixelsToCursor(HAND_X * grow) / scale
        y = y + PixelsToCursor(HAND_Y * grow) / scale
    end
    return x + (tonumber(settings.offsetX) or 0), y + (tonumber(settings.offsetY) or 0)
end

-- ── Building ────────────────────────────────────────────────────────────────

local haloAlphaScale = 1

local function RestyleAll()
    if not root then return end
    local theme = CurrentTheme()

    halo:SetSize(settings.haloSize, settings.haloSize)
    -- The player's pick for this theme; each theme starts on its own shape.
    haloAlphaScale = ApplyShape(halo, settings.haloShape or theme.halo or "glow")
    halo:SetBlendMode(theme.blend or "ADD")
    halo:SetShown(settings.halo)

    shadow:SetSize(settings.shadowSize, settings.shadowSize)
    shadow:SetShown(settings.shadow)

    -- Sparks are shaped when they are dropped, since each layer has its own
    -- look; here they are only put out. They are made on demand, per layer.
    for index = 1, #sparks do
        local spark = sparks[index]
        spark.layer, spark.shape = nil, nil
        spark:SetRotation(0)
        spark:Hide()
    end
    for _, layer in ipairs(LayersOf(theme)) do layer.acc, layer.timer = 0, 0 end
    for _, bolt in ipairs(bolts) do HideBolt(bolt) end
    for index = 1, MAX_ECHOES do
        if echoes[index] then echoes[index]:Hide() end
    end
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

    -- The theme's glow behind the steering arrow.
    arrow.glow = root:CreateTexture(nil, "ARTWORK", nil, 5)
    arrow.glow:SetTexture(GLOW)
    arrow.glow:SetBlendMode("ADD")
    arrow.glow:Hide()

    -- Windows 95 pointer trails. Nearest filtering keeps the pixel art sharp.
    for index = 1, MAX_ECHOES do
        local echo = root:CreateTexture(nil, "ARTWORK", nil, 6)
        echo:SetTexture(WIN95_ARROW, nil, nil, "NEAREST")
        echo:Hide()
        echoes[index] = echo
    end

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
-- ── Bolts ───────────────────────────────────────────────────────────────────
-- Lightning is drawn as lines, not sparks: a jagged path from the pointer out
-- to a random point, each bend pushed sideways, with a wider faint line under
-- it for the glow. A bolt lives a fraction of a second and stays where it
-- struck, which is what makes it read as a crack of electricity.

local MAX_BOLTS, MAX_SEGMENTS = 8, 10

local function NewBolt()
    local bolt = { lines = {}, glows = {} }
    for i = 1, MAX_SEGMENTS do
        local glow = root:CreateLine(nil, "ARTWORK", nil, 1)
        glow:SetColorTexture(1, 1, 1, 1)
        glow:SetBlendMode("ADD")
        glow:Hide()
        bolt.glows[i] = glow

        local line = root:CreateLine(nil, "ARTWORK", nil, 4)
        line:SetColorTexture(1, 1, 1, 1)
        line:SetBlendMode("ADD")
        line:Hide()
        bolt.lines[i] = line
    end
    bolts[#bolts + 1] = bolt
    return bolt
end

HideBolt = function(bolt)
    bolt.active = false
    for i = 1, MAX_SEGMENTS do
        bolt.lines[i]:Hide()
        bolt.glows[i]:Hide()
    end
end

local function DropBolt(layer, x, y, now)
    if layer.chance and random() > layer.chance then return end
    local bolt
    for _, candidate in ipairs(bolts) do
        if not candidate.active then bolt = candidate break end
    end
    if not bolt then
        if #bolts >= MAX_BOLTS then return end
        bolt = NewBolt()
    end

    local segments = math.min(MAX_SEGMENTS, layer.segments or 6)
    local angle = random() * 6.2832
    local reach = (layer.reach or 50) * (0.6 + 0.4 * random())
    local ex, ey = x + math.cos(angle) * reach, y + math.sin(angle) * reach
    local px, py = -math.sin(angle), math.cos(angle)
    local thickness = layer.thickness or 2

    local fromX, fromY = x, y
    for i = 1, MAX_SEGMENTS do
        local line, glow = bolt.lines[i], bolt.glows[i]
        if i <= segments then
            local t = i / segments
            local offset = (i < segments) and (random() * 2 - 1) * reach * 0.2 or 0
            local toX = x + (ex - x) * t + px * offset
            local toY = y + (ey - y) * t + py * offset
            for _, piece in ipairs({ line, glow }) do
                piece:SetStartPoint("BOTTOMLEFT", UIParent, fromX, fromY)
                piece:SetEndPoint("BOTTOMLEFT", UIParent, toX, toY)
                piece:Show()
            end
            -- Thinner toward the tip, like a real discharge.
            line:SetThickness(math.max(1, thickness * (1.2 - t * 0.6)))
            glow:SetThickness(thickness * 5)
            fromX, fromY = toX, toY
        else
            line:Hide()
            glow:Hide()
        end
    end

    bolt.layer, bolt.born, bolt.life, bolt.active = layer, now, layer.life or 0.15, true
end

local function UpdateBolts(now)
    for _, bolt in ipairs(bolts) do
        if bolt.active then
            local age = (now - bolt.born) / bolt.life
            if age >= 1 then
                HideBolt(bolt)
            else
                -- Flickers as it dies, the way a spark does.
                local alpha = (1 - age) * (0.6 + 0.4 * random())
                local r, g, b = StopsColour(bolt.layer.stops, age)
                for i = 1, MAX_SEGMENTS do
                    bolt.lines[i]:SetVertexColor(r, g, b, alpha)
                    bolt.glows[i]:SetVertexColor(r, g, b, alpha * 0.18)
                end
            end
        end
    end
end

local function DropSpark(layer, x, y, mvx, mvy, now)
    if layer.bolt then return DropBolt(layer, x, y, now) end
    if layer.chance and random() > layer.chance then return end

    local pool = layer.pool
    if not pool then
        pool = {}
        layer.pool, layer.next = pool, 1
    end

    local slot = layer.next or 1
    layer.next = slot % POOL + 1

    local spark = pool[slot]
    if not spark then
        spark = root:CreateTexture(nil, "ARTWORK")
        pool[slot] = spark
        sparks[#sparks + 1] = spark   -- the flat list, for hiding everything
    end

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
    -- Scatter: dropped a few pixels off the path in a random direction, so a
    -- layer of small sparks reads as a cloud and not as a dotted line.
    local scatter = layer.scatter
    if scatter and scatter > 0 then
        local angle = random() * 6.2832
        local distance = random() * scatter
        x = x + math.cos(angle) * distance
        y = y + math.sin(angle) * distance
    end
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
        spark.vy = spark.vy * keep
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

-- ── Pointer trails ──────────────────────────────────────────────────────────
-- Where the tip has been, newest last, in a ring. Each copy of the arrow is
-- drawn where the tip was a fixed moment ago; when the mouse stops, the
-- older places are all the same place and the copies fold into the pointer.

local HISTORY = 120
local histX, histY, histT = {}, {}, {}
local histHead, histCount = 0, 0

local function PushHistory(x, y, now)
    histHead = histHead % HISTORY + 1
    histX[histHead], histY[histHead], histT[histHead] = x, y, now
    if histCount < HISTORY then histCount = histCount + 1 end
end

-- Where the tip was at time t: the newest entry at or before it.
local function PlaceAt(t)
    local index = histHead
    for _ = 1, histCount do
        if histT[index] <= t then return histX[index], histY[index] end
        index = index - 1
        if index < 1 then index = HISTORY end
    end
    return nil
end

local function HideEchoes()
    for index = 1, MAX_ECHOES do
        if echoes[index] then echoes[index]:Hide() end
    end
end

local function UpdateEchoes(echo, tipX, tipY, now)
    PushHistory(tipX, tipY, now)
    -- Trail density picks how many arrows: 14, the default, gives seven.
    local count = math.max(2, math.min(MAX_ECHOES, math.floor((tonumber(settings.trailLength) or 14) / 2)))
    local size = PixelsToUI(pointerPx) * (tonumber(settings.steerScale) or 1)
    for index = 1, MAX_ECHOES do
        local texture = echoes[index]
        local x, y
        if index <= count then x, y = PlaceAt(now - index * (echo.gap or 0.035)) end
        -- A copy sitting on the pointer adds nothing; it is left hidden, so
        -- a resting mouse shows one arrow, the real one.
        if x and ((x - tipX) ^ 2 + (y - tipY) ^ 2) > 4 then
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
            texture:SetSize(size, size)
            texture:SetAlpha(0.95 - index * (0.6 / count))
            texture:Show()
        else
            texture:Hide()
        end
    end
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
    -- While the right button turns the camera the game hides its pointer. With
    -- "Show the pointer while turning the camera" off, everything here hides
    -- with it, the way it is without the module: no arrow, no glow, no trail.
    if not settings.steering and IsMouselooking and IsMouselooking() then alpha = 0 end
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
        -- Sized like the real pointer, then by the player's own scale.
        local size = PixelsToUI(pointerPx) * (tonumber(settings.steerScale) or 1)
        local style = settings.steerStyle
        local strength = tonumber(settings.steerAlpha) or 1

        arrow:ClearAllPoints()
        -- The arrow's tip is its top-left corner, same as the real pointer.
        arrow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tipX, tipY)
        arrow:SetSize(size, size)
        if style == "glow" then
            arrow:Hide()
        else
            -- Ghost: a pale, see-through copy, so it reads as "the pointer
            -- will come back here" rather than as a live pointer.
            arrow:SetDesaturated(style == "ghost")
            if style == "ghost" then
                arrow:SetVertexColor(0.8, 0.9, 1, strength * 0.55)
            else
                arrow:SetVertexColor(1, 1, 1, strength)
            end
            arrow:Show()
        end

        if settings.steerGlow or style == "glow" then
            local r, g, b = HaloColour(theme)
            arrow.glow:ClearAllPoints()
            arrow.glow:SetPoint("CENTER", UIParent, "BOTTOMLEFT", tipX + size * 0.3, tipY - size * 0.35)
            arrow.glow:SetSize(size * 2.2, size * 2.2)
            arrow.glow:SetVertexColor(r, g, b, strength * (style == "glow" and 0.9 or 0.5))
            arrow.glow:Show()
        else
            arrow.glow:Hide()
        end
    elseif arrow:IsShown() or arrow.glow:IsShown() then
        arrow:Hide()
        arrow.glow:Hide()
    end

    -- Windows 95 pointer trails, following the tip itself.
    if theme.echo and settings.trail and not steering then
        UpdateEchoes(theme.echo, tipX, tipY, now)
    elseif echoes[1] and echoes[1]:IsShown() then
        HideEchoes()
    end

    -- Trail: drop sparks along the path, spaced so a still mouse leaves no
    -- pile of dots behind it.
    if settings.trail then
        -- Trail length scales how thick every layer is: 14 is the design.
        local length = math.max(4, math.min(60, tonumber(settings.trailLength) or 14))
        -- ⚠ Trail density thickens the trail; it must not turn it into a line.
        -- Unbounded, 44 on the slider packed every layer three times tighter:
        -- rings overlapped into a tube and sparks lay edge to edge as a solid
        -- streak. So it is capped, accents (rings, bolts) ignore it, and no
        -- layer is ever laid closer than half the spacing it was drawn for.
        local density = math.min(1.6, length / 14)
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
        -- ⚠ A jump is not a path to fill: a long frame, a loading screen, or
        -- the pointer coming back from steering somewhere else entirely.
        -- Those laid a straight row of sparks across the screen, far from the
        -- pointer, which then had nothing left to move them.
        local jumped = distance > 200 or elapsed > 0.1 or steering or wasSteering

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
                    local rateScale = layer.accent and 1 or density
                    layer.timer = (layer.timer or 0) + elapsed * layer.rate * rateScale
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
                    local spacing = layer.accent and layer.spacing
                        or math.max(layer.spacing * 0.5, layer.spacing / density)
                    layer.acc = (layer.acc or 0) + distance
                    local count = 0
                    while layer.acc >= spacing and count < 24 do
                        layer.acc = layer.acc - spacing
                        count = count + 1
                        local t = distance > 0 and math.min(1, layer.acc / distance) or 0
                        DropSpark(layer, x - dx * t, y - dy * t, mvx, mvy, now)
                    end
                    -- ⚠ What the cap left over is dropped, not carried. Kept,
                    -- it was laid next frame at t > 1: past the start of that
                    -- frame's segment, in a straight line off the path. That
                    -- was the soft, straight "sticks" beside a dense trail.
                    if layer.acc > spacing then layer.acc = layer.acc % spacing end
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

        UpdateBolts(now)

        local baseSize = tonumber(settings.trailSize) or 14
        for _, layer in ipairs(LayersOf(theme)) do
            local pool = layer.pool
            if pool then
                for index = 1, POOL do
                    local spark = pool[index]
                    if spark and spark.layer then
                        UpdateSpark(spark, elapsed, now, baseSize, index)
                    end
                end
            end
        end

        -- ⚠ A safety net. A spark left over from another theme, or from a
        -- pool no longer in use, has nobody to age it and would hang on
        -- screen for ever. Anything shown without a live layer goes here.
        for index = 1, #sparks do
            local spark = sparks[index]
            if spark:IsShown() and not spark.layer then spark:Hide() end
        end
    end

    lastX, lastY = x, y
    wasSteering = steering and true or false
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
    if show and not root:IsShown() then
        -- Start from where the pointer is now: where it was last seen may be
        -- an hour and a continent away.
        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        lastX, lastY = Anchor(cx, cy, scale)
        wasSteering = true
    end
    root:SetShown(show)
    if not show then
        -- Put out, and disowned: a spark that comes back later would carry on
        -- from an age set before the module was switched off.
        for _, spark in ipairs(sparks) do
            spark.layer = nil
            spark:Hide()
        end
        for _, bolt in ipairs(bolts) do HideBolt(bolt) end
        if arrow then arrow:Hide() arrow.glow:Hide() end
        HideEchoes()
    end
end

watcher:SetScript("OnEvent", function(_, event, cvar)
    if event == "CVAR_UPDATE" then
        if cvar == "cursorSizePreferred" or cvar == "CURSOR_SIZE_PREFERRED" then ReadPointerPx() end
        return
    end
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
    ApplyGamePointer()
    RestyleAll()
    pcall(watcher.RegisterEvent, watcher, "CVAR_UPDATE")
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
    RestoreGamePointer()
    if root then
        root:SetScript("OnUpdate", nil)
        root:Hide()
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

-- ── Settings per theme ──────────────────────────────────────────────────────
-- Each theme keeps its own look: a big soft glow for Fire, a small ring for
-- Arcane, a long trail for Meteor. The keys below are saved per theme; the
-- rest (where the glow sits, clicks, steering, combat) are shared by every
-- theme.
--
-- The live values stay where the drawing code reads them, at the top of the
-- settings table. Switching theme files the old theme's values away and brings
-- the new theme's back, so nothing else in this file needs to know.

local PER_THEME = {
    "halo", "haloShape", "haloSize", "haloAlpha", "haloOwnColour", "haloR", "haloG", "haloB",
    "shadow", "shadowSize", "shadowAlpha",
    "trail", "trailLength", "trailSize", "trailLife",
    "idleSwirl", "swirlDelay",
    "classColour", "rainbow", "trailOwnColour", "colourR", "colourG", "colourB",
}

local function StoreTheme()
    local store = settings.themeSettings
    local saved = store[settings.theme]
    if type(saved) ~= "table" then
        saved = {}
        store[settings.theme] = saved
    end
    for _, key in ipairs(PER_THEME) do saved[key] = settings[key] end
end

local function LoadTheme(key)
    local saved = settings.themeSettings[key]
    for _, name in ipairs(PER_THEME) do
        local value
        if type(saved) == "table" then value = saved[name] end
        if value == nil then value = DEFAULTS[name] end
        -- A theme seen for the first time starts on its own glow shape.
        local fresh = not (type(saved) == "table" and saved[name] ~= nil)
        local theme = THEME_BY_KEY[key]
        if fresh and theme then
            if name == "haloShape" then value = theme.halo or value end
            if name == "halo" and theme.noHalo then value = false end
            if name == "shadow" and theme.noShadow then value = false end
            if name == "idleSwirl" and theme.noSwirl then value = false end
        end
        settings[name] = value
    end
end

local function SwitchTheme(key)
    if settings.theme == key then return end
    StoreTheme()
    settings.theme = key
    LoadTheme(key)
    RestyleAll()
end

local function ResetTheme()
    settings.themeSettings[settings.theme] = nil
    LoadTheme(settings.theme)
    RestyleAll()
end

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
    -- Built here, not in DEFAULTS: a table there is shared by reference.
    if type(config.themeSettings) ~= "table" then config.themeSettings = {} end
    settings = config
end

-- Opens the game's colour picker on the chosen colour.
-- keys are the three settings holding the colour, red first.
-- onPick runs once a colour is chosen: picking a colour while Class colour
-- or Rainbow is ticked used to change nothing on screen, because those win.
local function PickColour(keys, onPick)
    if not ColorPickerFrame then return end
    local before = { settings[keys[1]], settings[keys[2]], settings[keys[3]] }
    local function Apply()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        settings[keys[1]], settings[keys[2]], settings[keys[3]] = r, g, b
        if onPick then onPick() end
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

-- ── The options window ──────────────────────────────────────────────────────
-- Wide, with a tab per theme across the top in the Modules page's own tab
-- style. Picking a tab switches to that theme, and the left column shows its
-- own settings; the right column is shared by all of them.
--
-- The controls are placed by column rather than through AddCheckbox, which
-- only knows one column. Each has a Refresh in the window's checks list, so
-- opening the window or changing tab puts every control back in step.

local WINDOW_W, WINDOW_H = 1120, 700
local COLUMN_W = 420

local function RefreshWindow(w)
    for _, control in ipairs(w.checks) do control.Refresh() end
end

-- A column: where it starts and how far down it has got.
local function Column(w, x, y, title)
    local col = { w = w, x = x, y = y }
    if title then
        local head = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", w, "TOPLEFT", x, y)
        head:SetText(title)
        col.y = y - 22
    end
    return col
end

local function Check(col, key, label, tooltip, onChange)
    local w = col.w
    local box = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", w, "TOPLEFT", col.x - 4, col.y)
    box.text:SetFontObject("GameFontHighlight")
    box.text:SetText(label)
    box:SetScript("OnClick", function(self)
        settings[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    if tooltip then
        box:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    box.Refresh = function() box:SetChecked(settings[key] == true) end
    table.insert(w.checks, box)
    col.y = col.y - 26
    return box
end

local function Slider(col, key, caption, minValue, maxValue, step, format, apply)
    local w = col.w
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", col.x, col.y - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(190, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", col.x + COLUMN_W - 200, col.y - 5)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    -- The template's Low / High captions say nothing the label does not.
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    -- ⚠ A fresh slider holds 0 and the template moves it about while the
    -- window is laid out. Nothing is saved until it has been told what the
    -- setting really is, or those moves overwrite it.
    local ready, refreshing = false, false
    local function Show(value) label:SetText((format):format(caption, value)) end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing or not ready then return end
        settings[key] = value
        if apply then apply() end
    end)
    slider.Refresh = function()
        refreshing = true
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
        refreshing = false
        ready = true
    end
    slider.Refresh()
    table.insert(w.checks, slider)
    col.y = col.y - 28
    return slider
end

-- A row of small buttons, one per choice, the picked one lit.
local function Choice(col, key, caption, choices, apply)
    local w = col.w
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", col.x, col.y - 4)
    label:SetText(caption)

    local holder = {}
    local buttons = {}
    holder.Refresh = function()
        for _, entry in ipairs(buttons) do
            entry.button:SetNormalFontObject(settings[key] == entry.key
                and "GameFontNormal" or "GameFontDisableSmall")
        end
    end
    -- Up to four choices sit beside the label; more get a row of their own
    -- under it.
    local below = #choices > 4
    local width = below and 56 or 60
    local startX = below and col.x or (col.x + COLUMN_W - (#choices * (width + 4)))
    local rowY = below and (col.y - 22) or (col.y - 1)
    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetPoint("TOPLEFT", w, "TOPLEFT", startX + (index - 1) * (width + 4), rowY)
        button:SetText(choice.name)
        button:SetScript("OnClick", function()
            settings[key] = choice.key
            holder.Refresh()
            if apply then apply() end
        end)
        buttons[#buttons + 1] = { key = choice.key, button = button }
    end
    table.insert(w.checks, holder)
    col.y = col.y - (below and 50 or 28)
end

local function Button(col, text, width, onClick, xOffset)
    local button = CreateFrame("Button", nil, col.w, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetPoint("TOPLEFT", col.w, "TOPLEFT", col.x + (xOffset or 0), col.y - 1)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- The template's name has moved between builds; asking for a missing one is
-- an error, so each is tried in turn and a plain button is the last resort.
local TAB_TEMPLATES = { "PanelTopTabButtonTemplate", "TabButtonTemplate" }
local function NewTab(parent)
    for _, template in ipairs(TAB_TEMPLATES) do
        local ok, button = pcall(CreateFrame, "Button", nil, parent, template)
        if ok and button then return button, true end
    end
    return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"), false
end

local function BuildThemeTabs(w)
    local strip = CreateFrame("Frame", nil, w)
    strip:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -34)
    strip:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -34)
    strip:SetHeight(32)

    -- One row, each tab as wide as its name, side by side like the Modules
    -- page's category tabs.
    local tabs = {}
    local previous
    for _, theme in ipairs(THEMES) do
        local button, isTab = NewTab(strip)
        button:SetText(theme.name)
        if isTab and PanelTemplates_TabResize then
            pcall(PanelTemplates_TabResize, button, 10, nil, 60)
        else
            button:SetSize(72, 24)
        end
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
        end
        previous = button
        button:SetScript("OnClick", function()
            SwitchTheme(theme.key)
            RefreshWindow(w)
        end)
        button.themeKey = theme.key
        button.isTab = isTab
        tabs[#tabs + 1] = button
    end

    local holder = {}
    holder.Refresh = function()
        local base = strip:GetFrameLevel() + 5
        for _, button in ipairs(tabs) do
            local selected = button.themeKey == settings.theme
            if button.isTab then
                if selected then
                    pcall(PanelTemplates_SelectTab, button)
                    button:SetFrameLevel(base + 5)
                else
                    pcall(PanelTemplates_DeselectTab, button)
                    button:SetFrameLevel(base)
                end
            else
                button:SetNormalFontObject(selected and "GameFontNormal" or "GameFontDisableSmall")
            end
        end
    end
    table.insert(w.checks, holder)
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Cursor", WINDOW_W, WINDOW_H)
        local w = optionsWindow

        BuildThemeTabs(w)

        -- The same soft gold line as under the Modules page's tabs.
        local under = CreateFrame("Frame", nil, w)
        under:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -34)
        under:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -34)
        under:SetHeight(32)
        API:AddTabLine(w, under, 0, 0)

        -- ── Left: this theme ──
        local left = Column(w, 24, -82, "This theme (saved for it alone)")

        Check(left, "halo", "Glow around the hand", nil, RestyleAll)
        Choice(left, "haloShape", "Glow shape", {
            { key = "glow", name = "Glow" },
            { key = "ring", name = "Ring" },
            { key = "dot",  name = "Dot" },
            { key = "star", name = "Star" },
        }, RestyleAll)
        Slider(left, "haloSize", "Glow size", 20, 120, 2, "%s: %d", RestyleAll)
        Slider(left, "haloAlpha", "Glow strength", 0.1, 1, 0.05, "%s: %.2f")
        Button(left, "Pick glow colour", 140, function() PickColour({ "haloR", "haloG", "haloB" }, function()
            settings.haloOwnColour = true
            RefreshWindow(w)
        end) end, COLUMN_W - 140)
        Check(left, "haloOwnColour", "Own colour for the glow",
            "Off, the glow takes the theme's colour: orange for Fire, white-hot for Meteor, your class colour in Custom.")

        Check(left, "shadow", "Shadow behind it",
            "A soft dark disc that keeps the pointer readable over bright spell effects.", RestyleAll)
        Slider(left, "shadowAlpha", "Shadow strength", 0.05, 0.8, 0.05, "%s: %.2f")

        Check(left, "trail", "Trail of sparks")
        Slider(left, "trailLength", "Trail density", 4, 60, 1, "%s: %d")
        Slider(left, "trailSize", "Spark size", 6, 40, 1, "%s: %d")

        Check(left, "idleSwirl", "Magic circles when the mouse rests",
            "Let go of the mouse and the sparks spiral around the pointer in the theme's colours instead of trailing behind it.")
        Slider(left, "swirlDelay", "Circles start after", 0, 3, 0.1, "%s: %.1f s")

        local customNote = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        customNote:SetPoint("TOPLEFT", w, "TOPLEFT", left.x, left.y - 6)
        customNote:SetTextColor(0.75, 0.75, 0.75)
        customNote:SetText("Trail colour, for this theme:")
        Button(left, "Pick trail colour", 140, function() PickColour({ "colourR", "colourG", "colourB" }, function()
            settings.classColour, settings.rainbow = false, false
            settings.trailOwnColour = true
            RefreshWindow(w)
        end) end, COLUMN_W - 140)
        left.y = left.y - 30
        Check(left, "trailOwnColour", "Own colour for the trail",
            "Recolours this theme in the picked colour and keeps its shape. Untick for the theme's own colours.")
        Check(left, "classColour", "Class colour", "Custom theme only. Untick to use your own colour.")
        Check(left, "rainbow", "Rainbow", "Cycles through every colour; the trail runs through them too.")

        -- ── Right: every theme ──
        local right = Column(w, 540, -82, "Every theme")

        Choice(right, "anchor", "The glow sits on", {
            { key = "hand", name = "Hand" },
            { key = "tip",  name = "Tip" },
        })
        Slider(right, "offsetX", "Nudge sideways", -40, 40, 1, "%s: %d")
        Slider(right, "offsetY", "Nudge up / down", -40, 40, 1, "%s: %d")
        right.y = right.y - 6

        Check(right, "steering", "Show the pointer while turning the camera",
            "Holding the right button to turn the camera hides the game's pointer. On, the module draws it where it froze. Off, the pointer and all its effects disappear, as they do without the module.")
        Choice(right, "steerStyle", "Steering pointer", {
            { key = "arrow", name = "Arrow" },
            { key = "ghost", name = "Ghost" },
            { key = "glow",  name = "Glow" },
        })
        Slider(right, "steerScale", "Steering pointer size", 0.5, 2.5, 0.05, "%s: %.2f")
        Slider(right, "steerAlpha", "Steering pointer strength", 0.2, 1, 0.05, "%s: %.2f")
        Check(right, "steerGlow", "Theme glow behind it")
        right.y = right.y - 6

        -- The game's own pointer.
        Choice(right, "pointerSize", "Game pointer size", {
            { key = "game", name = "Game" },
            { key = "auto", name = "Auto" },
            { key = "32",   name = "32" },
            { key = "48",   name = "48" },
            { key = "64",   name = "64" },
            { key = "96",   name = "96" },
            { key = "128",  name = "128" },
        }, ApplyGamePointer)
        Choice(right, "lookDelta", "Camera turns after", {
            { key = "game",    name = "Game" },
            { key = "instant", name = "At once" },
            { key = "normal",  name = "Normal" },
            { key = "late",    name = "Later" },
        }, ApplyGamePointer)
        right.y = right.y - 6
        Check(right, "ripple", "Ripple on every click")
        Check(right, "shake", "Shake to find it", "Wiggle the mouse quickly left and right and the glow flares up.")
        Check(right, "onlyCombat", "Only in combat", nil, ApplyVisibility)
        Check(right, "fadeIdle", "Fade out when the mouse is still",
            "Hides everything while the mouse is untouched. It turns the circles off too, since there is nothing left to see.")

        right.y = right.y - 14
        Button(right, "Reset this theme", 150, function()
            ResetTheme()
            RefreshWindow(w)
        end)
    end
    optionsWindow:Show()
end

-- ── /oxcursor ───────────────────────────────────────────────────────────────
-- Prints the numbers the steering arrow is sized from, so a pointer that
-- comes out the wrong size can be measured instead of guessed at.
SLASH_OXEDHUBCURSOR1 = "/oxcursor"
SlashCmdList.OXEDHUBCURSOR = function()
    local height = ScreenHeightPx()
    ReadPointerPx()
    print(("|cff00ccffOxedHub Cursor|r cursorSizePreferred=%s  pointer=%d px  screen height=%s  UI scale=%.3f  arrow=%.1f UI units (x%.2f)")
        :format(tostring(GetCVar and GetCVar("cursorSizePreferred")), pointerPx, tostring(height),
            UIParent:GetEffectiveScale(), PixelsToUI(pointerPx),
            settings and tonumber(settings.steerScale) or 1))
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
        category = "character",
        keywords = { "cursor", "mouse", "pointer", "trail", "windows 95", "retro", "glow", "halo", "steering", "mouselook", "find", "fire", "frost", "meteor", "lightning", "void", "fel", "blood", "bubbles", "fairy" },
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
