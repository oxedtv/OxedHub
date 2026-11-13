-- ============================================================================
-- Object Glow (built-in OxedHub module)
-- Makes things you can pick up in the world easier to see:
--
--   game glow   switches on the game's own sparkle for herbs, ore and quest
--               objects (the console setting below), and puts the old value
--               back when the module is switched off
--   hover       while the mouse is on a herb, a vein, a quest object or any
--               other world object, sparks in a matching style play around
--               the pointer: leaves for a herb, embers for ore, and so on
--   pointer     sparks fly from your character toward something close by
--
-- What the pointer can and cannot know. The game does not tell addons where
-- a herb or a vein is: there is no position for it anywhere in the API. It
-- does give a position for its own marks (vignettes: rares, chests, some
-- quest objects), and the module remembers the spots where you gathered. So
-- the pointer aims at those two, never at a node it has not seen before.
--
-- The direction is drawn relative to where the character faces, with "up"
-- meaning ahead. The camera's own angle is not readable, so it is right
-- while the camera sits behind the character.
--
-- The art is the Cursor module's, in Media\Textures\Cursor.
-- ============================================================================

local addonName, OxedHub = ...
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end

local ICON  = "Interface\\Icons\\INV_Misc_Flower_02"
local MEDIA = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Cursor\\"
local CVAR  = "outlineModeShowLootEffectWhenDisabled"

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    minimapButton = true,

    gameGlow      = true,   -- set the game's own sparkle setting
    outlineOff    = true,   -- and switch outlines off, which the sparkle needs

    mark          = true,   -- a beacon where the mouse found something
    markTime      = 1.5,    -- seconds it stands
    markSound     = "",     -- an OxedHub sound id; empty plays nothing
    markSize      = 1,
    markHeight    = 1,      -- the pillar alone
    markAlpha     = 1,
    markColour    = "find", -- find (the style of what was found), class, rainbow or own
    markBeam      = true,   -- the parts it is made of
    markRing      = true,
    markStar      = true,
    markSparks    = true,
    markBurst     = true,
    markTurnOut   = true,   -- goes out when the character turns

    hover         = true,
    hoverSize     = 1,
    herbStyle     = "nature",
    oreStyle      = "fire",
    questStyle    = "holy",
    skin          = true,   -- corpses that can be skinned
    skinStyle     = "blood",
    skinCount     = true,   -- the "left to skin" counter
    otherStyle    = "frost",
    showOther     = true,   -- chests, levers and anything else with a name

    point         = true,
    pointMarks    = true,   -- the game's own marks
    pointSpots    = true,   -- where the player gathered before
    markStyle     = "arcane",
    pointRange    = 120,    -- yards
    pointRadius   = 110,    -- how far from the character the sparks start
    pointSize     = 1,
}

local settings
local running = false
local optionsWindow, pointerWindow, beaconWindow
local minimapIcon, MinimapIcon, ShowOptions

local random, sin, cos, sqrt = math.random, math.sin, math.cos, math.sqrt

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- true, false, or nil when the answer is secret or the call failed.
local function Known(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or Secret(v) then return nil end
    return v and true or false
end

local function PlainNumber(v)
    return type(v) == "number" and not Secret(v)
end

local function PlainString(v)
    return type(v) == "string" and not Secret(v) and v ~= ""
end

-- ── Styles ──────────────────────────────────────────────────────────────────
-- glow    the colour of the soft light under the pointer and of the pointer's head
-- layers  what plays around the mouse: tex, rate a second, life, size, and
--         how it moves (rise, spread, sway, spin); c0 fades to c1
-- dart    the spark that flies toward a spot

local STYLES = {
    nature = { name = "Nature", glow = { 0.45, 0.9, 0.35 },
        layers = {
            { tex = "leaf", blend = "BLEND", rate = 6, life = 1.5, size = 15, alpha = 0.95,
              rise = -24, spread = 22, sway = 40, spin = 0.5, c0 = { 0.45, 0.85, 0.25 }, c1 = { 0.8, 0.5, 0.12 } },
            { tex = "ember", rate = 9, life = 1.3, size = 5, alpha = 0.9,
              rise = 20, spread = 14, sway = 20, c0 = { 1, 1, 0.6 }, c1 = { 0.7, 1, 0.4 } },
        },
        dart = { tex = "leaf", blend = "BLEND", life = 0.8, size = 13, alpha = 0.95, spin = 0.8,
                 c0 = { 0.5, 0.95, 0.3 }, c1 = { 0.75, 0.8, 0.2 } } },
    fire = { name = "Fire", glow = { 1, 0.5, 0.12 },
        layers = {
            { tex = "glow", rate = 16, life = 0.6, size = 18, alpha = 0.3,
              rise = 60, spread = 12, sway = 14, c0 = { 1, 0.85, 0.45 }, c1 = { 0.6, 0.08, 0.01 } },
            { tex = "ember", rate = 10, life = 1.1, size = 5, alpha = 0.9,
              rise = 45, spread = 30, sway = 26, c0 = { 1, 0.95, 0.6 }, c1 = { 0.8, 0.2, 0 } },
        },
        dart = { tex = "ember", life = 0.7, size = 8, alpha = 1,
                 c0 = { 1, 0.95, 0.6 }, c1 = { 1, 0.35, 0.05 } } },
    frost = { name = "Frost", glow = { 0.55, 0.85, 1 },
        layers = {
            { tex = "flake", rate = 5, life = 1.5, size = 14, alpha = 0.9,
              rise = -22, spread = 16, sway = 30, spin = 0.35, c0 = { 1, 1, 1 }, c1 = { 0.4, 0.65, 1 } },
            { tex = "twinkle", rate = 7, life = 0.5, size = 10, alpha = 0.95,
              spread = 18, c0 = { 1, 1, 1 }, c1 = { 0.6, 0.85, 1 } },
        },
        dart = { tex = "flake", life = 0.8, size = 12, alpha = 0.95, spin = 0.6,
                 c0 = { 1, 1, 1 }, c1 = { 0.45, 0.7, 1 } } },
    arcane = { name = "Arcane", glow = { 0.8, 0.45, 1 },
        layers = {
            { tex = "twinkle", rate = 10, life = 0.9, size = 11, alpha = 0.95,
              spread = 40, spin = 0.5, c0 = { 1, 0.85, 1 }, c1 = { 0.4, 0.15, 0.9 } },
            { tex = "ring", rate = 1.5, life = 0.8, size = 14, grow = 3, alpha = 0.45,
              c0 = { 0.95, 0.6, 1 }, c1 = { 0.4, 0.2, 1 } },
        },
        dart = { tex = "twinkle", life = 0.7, size = 12, alpha = 1, spin = 0.6,
                 c0 = { 1, 0.85, 1 }, c1 = { 0.55, 0.25, 1 } } },
    holy = { name = "Holy", glow = { 1, 0.85, 0.45 },
        layers = {
            { tex = "twinkle", rate = 9, life = 1.1, size = 11, alpha = 0.95,
              rise = 30, spread = 18, sway = 20, spin = 0.15, c0 = { 1, 1, 0.9 }, c1 = { 1, 0.6, 0.15 } },
            { tex = "ring", rate = 1.5, life = 0.8, size = 14, grow = 3, alpha = 0.4,
              c0 = { 1, 0.95, 0.7 }, c1 = { 1, 0.7, 0.2 } },
        },
        dart = { tex = "twinkle", life = 0.7, size = 12, alpha = 1, spin = 0.3,
                 c0 = { 1, 1, 0.85 }, c1 = { 1, 0.7, 0.2 } } },
    fel = { name = "Fel", glow = { 0.35, 1, 0.15 },
        layers = {
            { tex = "glow", rate = 16, life = 0.6, size = 18, alpha = 0.3,
              rise = 60, spread = 12, sway = 14, c0 = { 0.85, 1, 0.6 }, c1 = { 0.05, 0.3, 0.02 } },
            { tex = "ember", rate = 10, life = 1.1, size = 5, alpha = 0.9,
              rise = 45, spread = 30, sway = 26, c0 = { 0.9, 1, 0.5 }, c1 = { 0.1, 0.5, 0 } },
        },
        dart = { tex = "ember", life = 0.7, size = 8, alpha = 1,
                 c0 = { 0.9, 1, 0.5 }, c1 = { 0.2, 0.8, 0.05 } } },
    blood = { name = "Blood", glow = { 0.85, 0.05, 0.05 },
        layers = {
            { tex = "ember", blend = "BLEND", rate = 9, life = 1.0, size = 7, alpha = 0.95,
              rise = -70, spread = 24, c0 = { 0.85, 0.05, 0.05 }, c1 = { 0.3, 0, 0 } },
            { tex = "glow", rate = 6, life = 0.8, size = 20, alpha = 0.22,
              spread = 8, c0 = { 0.8, 0.05, 0.05 }, c1 = { 0.3, 0, 0 } },
        },
        dart = { tex = "ember", life = 0.7, size = 8, alpha = 1,
                 c0 = { 1, 0.2, 0.15 }, c1 = { 0.5, 0, 0 } } },
}
local STYLE_ORDER = { "nature", "fire", "frost", "arcane", "holy", "fel", "blood" }

local function StyleOf(key)
    return STYLES[settings and settings[key]] or STYLES.holy
end

-- Which setting holds the style for each kind of thing.
local KIND_STYLE = { herb = "herbStyle", ore = "oreStyle", quest = "questStyle", skin = "skinStyle",
                     other = "otherStyle", mark = "markStyle" }

-- ── Particles ───────────────────────────────────────────────────────────────

local root, halo
local live, free = {}, {}
local heads = {}
local MAX_LIVE = 160
local MAX_TARGETS = 3

local function Spawn(layer, x, y, vx, vy, sizeMul)
    if #live >= MAX_LIVE then return end
    local p = table.remove(free)
    if not p then p = root:CreateTexture(nil, "ARTWORK") end
    if p.tex ~= layer.tex then
        p:SetTexture(MEDIA .. layer.tex)
        p.tex = layer.tex
    end
    local blend = layer.blend or "ADD"
    if p.blend ~= blend then
        p:SetBlendMode(blend)
        p.blend = blend
    end
    if p.rotated and not layer.spin then
        p:SetRotation(0)
        p.rotated = nil
    end
    p.layer = layer
    p.x, p.y, p.vx, p.vy = x, y, vx, vy
    p.born = GetTime()
    p.life = (layer.life or 1) * (0.8 + 0.4 * random())
    p.phase = random() * 6.28
    p.size = (layer.size or 10) * (sizeMul or 1) * (0.75 + 0.5 * random())
    p:SetSize(p.size, p.size)
    p:SetVertexColor(1, 1, 1, 0)
    p:SetPoint("CENTER", root, "BOTTOMLEFT", x, y)
    p:Show()
    live[#live + 1] = p
end

local function UpdateParticles(dt, now)
    for index = #live, 1, -1 do
        local p = live[index]
        local layer = p.layer
        local age = (now - p.born) / p.life
        if age >= 1 then
            p:Hide()
            live[index] = live[#live]
            live[#live] = nil
            free[#free + 1] = p
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            local px = p.x
            if layer.sway then px = px + sin(age * 9 + p.phase) * layer.sway * 0.3 * age end
            p:SetPoint("CENTER", root, "BOTTOMLEFT", px, p.y)
            if layer.spin then
                p:SetRotation(p.phase + age * layer.spin * 6.28)
                p.rotated = true
            end
            if layer.grow then
                local size = p.size * (1 + (layer.grow - 1) * age)
                p:SetSize(size, size)
            end
            local a, b = layer.c0, layer.c1
            p:SetVertexColor(a[1] + (b[1] - a[1]) * age, a[2] + (b[2] - a[2]) * age,
                a[3] + (b[3] - a[3]) * age, sin(age * 3.1416) * (layer.alpha or 0.9))
        end
    end
end

local function ClearParticles()
    for index = #live, 1, -1 do
        local p = live[index]
        p:Hide()
        free[#free + 1] = p
        live[index] = nil
    end
end

-- ── What is under the mouse ─────────────────────────────────────────────────

local herbWords, oreWords = {}, {}
local questTitles = {}
local hoverKind          -- herb, ore, quest, other or nil
local hoverName
local hoverAcc = {}      -- per layer: sparks owed

local function SpellName(id)
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then name = n end
    elseif GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, id)
        if ok then name = n end
    end
    if PlainString(name) then return name end
    return nil
end

local function AddWord(list, word)
    if not PlainString(word) then return end
    for _, have in ipairs(list) do
        if have == word then return end
    end
    list[#list + 1] = word
end

-- The profession's name as this client writes it, plus the English one. The
-- node's tooltip and the gathering spell both carry it.
local function BuildWords()
    wipe(herbWords)
    wipe(oreWords)
    AddWord(herbWords, "Herbalism")
    AddWord(herbWords, "Herb Gathering")
    AddWord(herbWords, SpellName(2366))
    AddWord(oreWords, "Mining")
    AddWord(oreWords, SpellName(2575))
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, 182)
        if ok then AddWord(herbWords, name) end
        ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, 186)
        if ok then AddWord(oreWords, name) end
    end
end

local function HasWord(text, list)
    for _, word in ipairs(list) do
        if string.find(text, word, 1, true) then return true end
    end
    return false
end

local function RebuildQuests()
    wipe(questTitles)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local count = C_QuestLog.GetNumQuestLogEntries() or 0
        for index = 1, count do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and PlainString(info.title) then
                questTitles[info.title] = true
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local count = GetNumQuestLogEntries() or 0
        for index = 1, count do
            local title, _, _, isHeader = GetQuestLogTitle(index)
            if not isHeader and PlainString(title) then questTitles[title] = true end
        end
    end
end

local function MouseOverWorld()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        local first = foci and foci[1]
        return first == nil or first == WorldFrame
    elseif GetMouseFocus then
        local focus = GetMouseFocus()
        return focus == nil or focus == WorldFrame
    end
    return true
end

-- A hidden tooltip of our own, for reading a corpse's lines.
local scanTip, scanTried
local function ScanTip()
    if scanTip or scanTried then return scanTip end
    scanTried = true
    local ok, tip = pcall(CreateFrame, "GameTooltip", "OxedHubObjectGlowScan", nil, "GameTooltipTemplate")
    if ok and tip then scanTip = tip end
    return scanTip
end

-- The kind of world object the tooltip is describing, and its name. Nil when
-- the tooltip is for a unit, a button, or is not there.
local function ReadHover()
    if not MouseOverWorld() then return nil end
    -- "Cannot tell" (combat) is left alone. A unit only counts as a corpse
    -- whose tooltip says it can be skinned, mined or picked. It is read with
    -- a tooltip of our own: the game's may be hidden by Mouseover Info or
    -- replaced by another addon.
    local isUnit = Known(UnitExists, "mouseover")
    if isUnit == nil then return nil end
    if isUnit then
        if not settings.skin or Known(UnitIsDead, "mouseover") ~= true then return nil end
        local scan = ScanTip()
        if not scan then return nil end
        scan:SetOwner(WorldFrame, "ANCHOR_NONE")
        scan:SetUnit("mouseover")
        -- Each corpse is its own thing to the beacon; without a readable id
        -- every wolf would share one.
        local okGuid, guid = pcall(UnitGUID, "mouseover")
        local unitKey = okGuid and PlainString(guid) and guid or "corpse"
        for index = 2, scan:NumLines() do
            local fs = _G["OxedHubObjectGlowScanTextLeft" .. index]
            local text = fs and fs:GetText()
            if PlainString(text) then
                if text == UNIT_SKINNABLE_HERB then return "herb", text, unitKey end
                if text == UNIT_SKINNABLE_ROCK then return "ore", text, unitKey end
                if text == UNIT_SKINNABLE_LEATHER or text == UNIT_SKINNABLE_BOLTS then
                    -- Its name is remembered: the counter then knows this
                    -- kind of creature leaves a hide, in any language.
                    local first = _G["OxedHubObjectGlowScanTextLeft1"]
                    local unitName = first and first:GetText()
                    if text == UNIT_SKINNABLE_LEATHER and PlainString(unitName) and settings.skinNames then
                        settings.skinNames[unitName] = true
                    end
                    return "skin", unitName, unitKey
                end
            end
        end
        return nil
    end

    -- Forever and Midnight describe the object under the mouse themselves,
    -- line by line and with each line's type. That does not depend on the
    -- game's tooltip being on screen, and it says whether a quest objective
    -- is already done.
    if C_TooltipInfo and C_TooltipInfo.GetWorldCursor then
        local okData, data = pcall(C_TooltipInfo.GetWorldCursor)
        if okData and type(data) == "table" and type(data.lines) == "table" and data.lines[1] then
            local objectType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
            if objectType and (Secret(data.type) or data.type ~= objectType) then return nil end
            local first = data.lines[1]
            local objectName = type(first) == "table" and first.leftText
            if not PlainString(objectName) then return nil end

            local LineType = Enum and Enum.TooltipDataLineType
            local QT = LineType and LineType.QuestTitle
            local QO = LineType and LineType.QuestObjective
            local found, title, objective, open = nil, false, false, false
            for index = 2, #data.lines do
                local line = data.lines[index]
                if type(line) == "table" then
                    local lineType = line.type
                    if Secret(lineType) then lineType = nil end
                    if QO and lineType == QO then
                        objective = true
                        -- Unreadable counts as still open.
                        if Secret(line.completed) or not line.completed then open = true end
                    elseif QT and lineType == QT then
                        title = true
                    elseif not found and PlainString(line.leftText) then
                        if questTitles[line.leftText] then title = true
                        elseif HasWord(line.leftText, herbWords) then found = "herb"
                        elseif HasWord(line.leftText, oreWords) then found = "ore" end
                    end
                end
            end
            local learnedKind = settings.names and settings.names[objectName]
            if learnedKind == "herb" or learnedKind == "ore" then found = learnedKind end
            -- A quest still asking for it comes first; one already done is
            -- just an object again.
            if open or (title and not objective) then found = "quest" end

            local guid = data.guid
            local objectKey = PlainString(guid) and guid or ("object:" .. objectName)
            return found or "other", objectName, objectKey
        end
    end

    -- Clients without that: the game's tooltip, when it is about the world.
    local tip = GameTooltip
    if not tip or not tip:IsShown() then return nil end
    if tip:GetOwner() ~= UIParent then return nil end

    local name
    local kind
    for index = 1, 8 do
        local fs = _G["GameTooltipTextLeft" .. index]
        local text = fs and fs:IsShown() and fs:GetText()
        if not PlainString(text) then
            if index == 1 then return nil end
        elseif index == 1 then
            name = text
        elseif not kind then
            if questTitles[text] then kind = "quest"
            elseif HasWord(text, herbWords) then kind = "herb"
            elseif HasWord(text, oreWords) then kind = "ore" end
        end
    end
    if not name then return nil end

    -- The game's own word on quest lines, where this client has it.
    if not kind and tip.GetTooltipData and Enum and Enum.TooltipDataLineType then
        local data = tip:GetTooltipData()
        local QT = Enum.TooltipDataLineType.QuestTitle
        local QO = Enum.TooltipDataLineType.QuestObjective
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if line.type == QT or line.type == QO then kind = "quest" break end
            end
        end
    end

    -- Learned from an earlier gather: the surest answer for a herb or a vein.
    local learned = settings.names and settings.names[name]
    if learned == "herb" or learned == "ore" then kind = learned end

    return kind or "other", name, "object:" .. name
end

local StartBeacon   -- defined with the beacons, further down
local hoverKey

local function ScanHover()
    local kind, name, key
    if settings.hover or settings.mark then
        local ok, k, n, id = pcall(ReadHover)
        if ok then kind, name, key = k, n, id end
    end
    if kind == "other" and not settings.showOther then kind = nil end
    if not kind then key = nil end
    -- The mouse has just arrived on something: light a beacon where it is.
    if key and key ~= hoverKey then StartBeacon(kind, key) end
    hoverKey = key
    if not settings.hover then kind = nil end
    if kind ~= hoverKind then wipe(hoverAcc) end
    hoverKind, hoverName = kind, name
end

-- ── Where things are ────────────────────────────────────────────────────────
-- World positions as two plain numbers: the first grows to the north, the
-- second to the west. GetPlayerFacing counts the same way round (0 is north,
-- turning left adds), so a bearing is atan2(west, north).

local function WorldOf(mapID, mapPos)
    local continent, world = C_Map.GetWorldPosFromMapPos(mapID, mapPos)
    if not world then return nil end
    local north, west = world:GetXY()
    if not (PlainNumber(north) and PlainNumber(west) and PlainNumber(continent)) then return nil end
    return continent, north, west
end

local function PlayerWorld()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not PlainNumber(mapID) then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local continent, north, west = WorldOf(mapID, pos)
    if not continent then return nil end
    return continent, north, west, mapID
end

-- Remembered gathering spots: settings.spots[continent] = { {north, west, kind}, ... }
local SPOT_MERGE = 12       -- yards: closer than this is the same node
local SPOT_CAP = 500        -- per continent; the oldest goes first
local SPOT_REST = 300       -- seconds a spot keeps quiet after a visit
local SPOT_ARRIVE = 7       -- yards: standing on it counts as a visit
local resting = {}          -- [spot table] = time it may speak again

local function RememberSpot(kind)
    local ok, continent, north, west = pcall(PlayerWorld)
    if not ok or not continent then return end
    settings.spots = settings.spots or {}
    local list = settings.spots[continent]
    if not list then
        list = {}
        settings.spots[continent] = list
    end
    local now = GetTime()
    for _, spot in ipairs(list) do
        local dn, dw = spot[1] - north, spot[2] - west
        if dn * dn + dw * dw < SPOT_MERGE * SPOT_MERGE then
            spot[3] = kind
            resting[spot] = now + SPOT_REST
            return
        end
    end
    local spot = { math.floor(north * 10 + 0.5) / 10, math.floor(west * 10 + 0.5) / 10, kind }
    list[#list + 1] = spot
    resting[spot] = now + SPOT_REST
    if #list > SPOT_CAP then table.remove(list, 1) end
end

-- A gathering cast names the node it is aimed at. That teaches the module the
-- node's name in whatever language the client speaks, and where it stands.
local function OnCastSent(unit, target, _, spellID)
    if Secret(unit) or unit ~= "player" then return end
    if not PlainNumber(spellID) then return end
    local spell = SpellName(spellID)
    if not spell then return end
    local kind
    if HasWord(spell, herbWords) then kind = "herb"
    elseif HasWord(spell, oreWords) then kind = "ore" end
    if not kind then return end
    if PlainString(target) then
        settings.names = settings.names or {}
        settings.names[target] = kind
    end
    RememberSpot(kind)
end

-- Up to MAX_TARGETS nearest things worth pointing at: { bearing, dist, kind }.
local targets = {}
local targetCount = 0

local function Offer(bearing, dist, kind)
    -- Kept sorted by distance; the list is three long, so a plain insert.
    local at = targetCount + 1
    for index = 1, targetCount do
        if dist < targets[index].dist then at = index break end
    end
    if at > MAX_TARGETS then return end
    local last = math.min(targetCount + 1, MAX_TARGETS)
    local spare = targets[last] or {}
    for index = last, at + 1, -1 do targets[index] = targets[index - 1] end
    spare.bearing, spare.dist, spare.kind = bearing, dist, kind
    targets[at] = spare
    targetCount = last
end

local function FindTargets()
    targetCount = 0
    if not settings.point then return end
    local continent, north, west, mapID = PlayerWorld()
    if not continent then return end
    local range = tonumber(settings.pointRange) or 120
    local now = GetTime()
    local atan2 = math.atan2

    if settings.pointSpots and settings.spots then
        local list = settings.spots[continent]
        if list then
            for _, spot in ipairs(list) do
                local dn, dw = spot[1] - north, spot[2] - west
                local dist = sqrt(dn * dn + dw * dw)
                if dist < SPOT_ARRIVE then
                    resting[spot] = now + SPOT_REST
                elseif dist <= range and (resting[spot] or 0) < now then
                    Offer(atan2(dw, dn), dist, spot[3] == "ore" and "ore" or "herb")
                end
            end
        end
    end

    if settings.pointMarks and C_VignetteInfo and C_VignetteInfo.GetVignettes
        and C_VignetteInfo.GetVignettePosition then
        local guids = C_VignetteInfo.GetVignettes()
        if guids then
            for _, guid in ipairs(guids) do
                local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
                local info = C_VignetteInfo.GetVignetteInfo and C_VignetteInfo.GetVignetteInfo(guid)
                if pos and not (info and info.isDead) then
                    local c, n, w = WorldOf(mapID, pos)
                    if c == continent then
                        local dn, dw = n - north, w - west
                        local dist = sqrt(dn * dn + dw * dw)
                        if dist > SPOT_ARRIVE and dist <= range then
                            Offer(atan2(dw, dn), dist, "mark")
                        end
                    end
                end
            end
        end
    end
end

-- ── Every frame ─────────────────────────────────────────────────────────────

local dartAcc = {}

local function Facing()
    if not GetPlayerFacing then return nil end
    local ok, facing = pcall(GetPlayerFacing)
    if ok and PlainNumber(facing) then return facing end
    return nil
end

local function DrawHover(dt, now, scale)
    if not hoverKind then
        halo:Hide()
        return
    end
    local style = StyleOf(KIND_STYLE[hoverKind])
    local cx, cy = GetCursorPosition()
    local x, y = cx / scale, cy / scale
    local size = tonumber(settings.hoverSize) or 1

    local glow = style.glow
    halo:SetVertexColor(glow[1], glow[2], glow[3], 0.4 + 0.15 * sin(now * 5))
    halo:SetSize(80 * size, 80 * size)
    halo:SetPoint("CENTER", root, "BOTTOMLEFT", x, y)
    halo:Show()

    for index, layer in ipairs(style.layers) do
        local owed = (hoverAcc[index] or 0) + (layer.rate or 5) * dt
        while owed >= 1 do
            owed = owed - 1
            local angle, reach = random() * 6.2832, random() * 20 * size
            local spread = layer.spread or 0
            Spawn(layer, x + cos(angle) * reach, y + sin(angle) * reach,
                (random() * 2 - 1) * spread, (layer.rise or 0) + (random() * 2 - 1) * spread * 0.5, size)
        end
        hoverAcc[index] = owed
    end
end

local function DrawPointer(dt)
    local facing = targetCount > 0 and Facing() or nil
    local shown = 0
    if facing then
        local centreX, centreY = root:GetWidth() / 2, root:GetHeight() / 2
        local radius = tonumber(settings.pointRadius) or 110
        local size = tonumber(settings.pointSize) or 1
        local range = tonumber(settings.pointRange) or 120
        for index = 1, targetCount do
            local target = targets[index]
            local style = StyleOf(KIND_STYLE[target.kind])
            local near = math.max(0, math.min(1, 1 - target.dist / range))
            -- Ahead is up; a bearing to the left of where we face is to the left.
            local turn = target.bearing - facing
            local dirX, dirY = -sin(turn), cos(turn)

            local head = heads[index]
            local glow = style.glow
            head:SetVertexColor(glow[1], glow[2], glow[3], 0.3 + 0.5 * near)
            local headSize = (26 + 26 * near) * size
            head:SetSize(headSize, headSize)
            head:SetPoint("CENTER", root, "BOTTOMLEFT", centreX + dirX * radius, centreY + dirY * radius)
            head:Show()
            shown = index

            local dart = style.dart
            local owed = (dartAcc[index] or 0) + (5 + 20 * near) * dt
            while owed >= 1 do
                owed = owed - 1
                local side = (random() * 2 - 1) * 7
                local start = radius + random() * 10
                local speed = 90 + 60 * near
                Spawn(dart, centreX + dirX * start - dirY * side, centreY + dirY * start + dirX * side,
                    dirX * speed, dirY * speed, size)
            end
            dartAcc[index] = owed
        end
    end
    for index = shown + 1, MAX_TARGETS do heads[index]:Hide() end
end

-- ── Beacons ─────────────────────────────────────────────────────────────────
-- A beacon is lit where the mouse found something and stays there for a
-- moment after the mouse has gone on, so one sweep across the screen leaves
-- every find standing. It is drawn as a thing in the world rather than a
-- flat ping: a ring lying on the ground (a circle squashed to an ellipse),
-- a pillar of light rising from it, a turning star at its foot and motes
-- climbing the pillar, all in the find's own style.
--
-- It cannot follow the spot: an addon has no way to turn a place in the
-- world into a place on the screen. So it stands where the pointer was, and
-- goes out quickly once the character turns and the spot has moved away.

local MAX_BEACONS = 5
local BEACON_REFIRE = 1.5     -- seconds before the same thing lights again
local BEACON_TURN = 0.12      -- radians of turning that put it out
local beacons = {}
local lastBeacon, lastBeaconCount = {}, 0
local lastBeaconSound = 0

-- The beacon's colour: the style of what was found, the class colour, a
-- turning rainbow or one the player picked.
local classColour
local function BeaconColour(style, now)
    local mode = settings.markColour
    if mode == "rainbow" then
        local h = (now * 0.35 % 1) * 6
        local x = 1 - math.abs(h % 2 - 1)
        if h < 1 then return 1, x, 0
        elseif h < 2 then return x, 1, 0
        elseif h < 3 then return 0, 1, x
        elseif h < 4 then return 0, x, 1
        elseif h < 5 then return x, 0, 1 end
        return 1, 0, x
    elseif mode == "class" then
        if not classColour then
            -- Kept once read: in a fight the class may come back as a secret.
            local ok, _, class = pcall(UnitClass, "player")
            local colour = ok and PlainString(class) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if colour then classColour = { colour.r, colour.g, colour.b } end
        end
        if classColour then return classColour[1], classColour[2], classColour[3] end
    elseif mode == "own" and type(settings.markOwn) == "table" then
        return settings.markOwn[1] or 1, settings.markOwn[2] or 1, settings.markOwn[3] or 1
    end
    return style.glow[1], style.glow[2], style.glow[3]
end

-- key nil is a preview from the options: no cooldown, and atX, atY say where.
StartBeacon = function(kind, key, atX, atY)
    if not (settings.mark and root) then return end
    local now = GetTime()
    if key then
        if (lastBeacon[key] or 0) + BEACON_REFIRE > now then return end
        if lastBeacon[key] == nil then lastBeaconCount = lastBeaconCount + 1 end
        if lastBeaconCount > 64 then
            wipe(lastBeacon)
            lastBeaconCount = 1
        end
        lastBeacon[key] = now
    end

    -- A free one, or the oldest still burning.
    local beacon
    for index = 1, MAX_BEACONS do
        local candidate = beacons[index]
        if not candidate.active then beacon = candidate break end
        if not beacon or candidate.born < beacon.born then beacon = candidate end
    end

    local scale = UIParent:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local cx, cy = GetCursorPosition()
    local style = StyleOf(KIND_STYLE[kind])
    local size = tonumber(settings.markSize) or 1
    beacon.active = true
    if atX then
        beacon.x, beacon.y = atX, atY
    else
        beacon.x, beacon.y = cx / scale, cy / scale
    end
    beacon.born, beacon.life = now, math.max(0.4, tonumber(settings.markTime) or 1.5)
    beacon.style, beacon.size = style, size
    beacon.facing, beacon.lost, beacon.owed = Facing(), nil, 0
    if not key then beacon.facing = nil end   -- a preview stands whatever the character does

    -- Its sparks are the style's own, in a copy this beacon may recolour.
    local dart = beacon.dart
    wipe(dart)
    for field, value in pairs(style.dart) do dart[field] = value end
    dart.c0, dart.c1 = beacon.c0, beacon.c1
    local r, g, b = BeaconColour(style, now)
    if settings.markColour == "find" or settings.markColour == nil then
        local a, z = style.dart.c0, style.dart.c1
        beacon.c0[1], beacon.c0[2], beacon.c0[3] = a[1], a[2], a[3]
        beacon.c1[1], beacon.c1[2], beacon.c1[3] = z[1], z[2], z[3]
    else
        -- A spark starts halfway to white and cools to the colour itself.
        beacon.c0[1], beacon.c0[2], beacon.c0[3] = 0.5 + r * 0.5, 0.5 + g * 0.5, 0.5 + b * 0.5
        beacon.c1[1], beacon.c1[2], beacon.c1[3] = r, g, b
    end

    beacon.beam:SetShown(settings.markBeam ~= false)
    beacon.ring:SetShown(settings.markRing ~= false)
    beacon.star:SetShown(settings.markStar ~= false)
    beacon.beam:SetAlpha(0)
    beacon.ring:SetAlpha(0)
    beacon.star:SetAlpha(0)

    -- It opens with sparks thrown out along the ground: wide, not tall.
    if settings.markBurst ~= false then
        for index = 1, 10 do
            local angle = index / 10 * 6.2832
            Spawn(dart, beacon.x, beacon.y, cos(angle) * 110, sin(angle) * 40, size)
        end
    end

    local sound = settings.markSound
    if type(sound) == "string" and sound ~= "" and now - lastBeaconSound > 0.3 then
        lastBeaconSound = now
        local API = OxedHub.ModuleAPI
        if API and API.PlaySound then pcall(API.PlaySound, API, sound) end
    end
    root:Show()
end

local function HideBeacon(beacon)
    beacon.active = false
    beacon.beam:Hide()
    beacon.ring:Hide()
    beacon.star:Hide()
end

-- Returns true while any beacon is still burning.
local function UpdateBeacons(dt, now)
    local any = false
    local facing
    for index = 1, MAX_BEACONS do
        local beacon = beacons[index]
        if beacon.active then
            local age = (now - beacon.born) / beacon.life
            if age >= 1 then
                HideBeacon(beacon)
            else
                any = true
                -- Turned away from where it was lit: a fifth of a second left.
                if not beacon.lost and beacon.facing and settings.markTurnOut ~= false then
                    facing = facing or Facing()
                    if facing then
                        local turned = math.abs(facing - beacon.facing)
                        if turned > 3.1416 then turned = 6.2832 - turned end
                        if turned > BEACON_TURN then
                            beacon.lost = true
                            local left = math.min(0.2, (1 - age) * beacon.life)
                            beacon.life = (now - beacon.born) + left
                            age = (now - beacon.born) / beacon.life
                        end
                    end
                end

                local x, y, size = beacon.x, beacon.y, beacon.size
                local fade = 1
                if age < 0.1 then fade = age / 0.1
                elseif beacon.lost then fade = 1 - age
                elseif age > 0.65 then fade = (1 - age) / 0.35 end
                if fade < 0 then fade = 0 end
                fade = fade * (tonumber(settings.markAlpha) or 1)

                -- Coloured every frame, so a rainbow turns while it stands.
                -- The star is pulled halfway to white: the bright heart.
                local r, g, b = BeaconColour(beacon.style, now)
                beacon.beam:SetVertexColor(r, g, b)
                beacon.ring:SetVertexColor(r, g, b)
                beacon.star:SetVertexColor(0.5 + r * 0.5, 0.5 + g * 0.5, 0.5 + b * 0.5)
                if settings.markColour == "rainbow" then
                    local c0, c1 = beacon.c0, beacon.c1
                    c0[1], c0[2], c0[3] = 0.5 + r * 0.5, 0.5 + g * 0.5, 0.5 + b * 0.5
                    c1[1], c1[2], c1[3] = r, g, b
                end

                -- The pillar shoots up fast and then holds.
                local rise = math.min(1, age * 4)
                rise = 1 - (1 - rise) * (1 - rise)
                beacon.beam:SetSize(30 * size, (40 + 130 * rise) * size * (tonumber(settings.markHeight) or 1))
                beacon.beam:SetPoint("BOTTOM", root, "BOTTOMLEFT", x, y - 8 * size)
                beacon.beam:SetAlpha(math.min(1, 0.6 * fade))

                -- The ring spreads over the ground twice in a beacon's life.
                local pulse = (age * 2) % 1
                local width = (36 + 90 * pulse) * size
                beacon.ring:SetSize(width, width * 0.36)
                beacon.ring:SetPoint("CENTER", root, "BOTTOMLEFT", x, y)
                beacon.ring:SetAlpha(math.min(1, (1 - pulse) * 0.9 * fade))

                local star = (24 + 5 * sin(now * 9)) * size
                beacon.star:SetSize(star, star)
                beacon.star:SetPoint("CENTER", root, "BOTTOMLEFT", x, y)
                beacon.star:SetRotation(now * 1.6)
                beacon.star:SetAlpha(math.min(1, 0.95 * fade))

                if not beacon.lost and settings.markSparks ~= false then
                    local owed = beacon.owed + 16 * dt
                    while owed >= 1 do
                        owed = owed - 1
                        Spawn(beacon.dart, x + (random() * 2 - 1) * 9 * size, y + random() * 24 * size,
                            (random() * 2 - 1) * 6, 60 + random() * 60, size * 0.8)
                    end
                    beacon.owed = owed
                end
            end
        end
    end
    return any
end

local function OnRootUpdate(_, dt)
    if dt > 0.1 then dt = 0.1 end
    local now = GetTime()
    local scale = UIParent:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    DrawHover(dt, now, scale)
    DrawPointer(dt)
    local burning = UpdateBeacons(dt, now)
    UpdateParticles(dt, now)
    if not hoverKind and not burning and targetCount == 0 and #live == 0 then root:Hide() end
end

local function EnsureRoot()
    if root then return end
    root = CreateFrame("Frame", nil, UIParent)
    OxedHub:HideInPetBattle(root)
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("TOOLTIP")
    root:EnableMouse(false)
    root:Hide()

    halo = root:CreateTexture(nil, "BACKGROUND")
    halo:SetTexture(MEDIA .. "glow")
    halo:SetBlendMode("ADD")
    halo:Hide()

    for index = 1, MAX_TARGETS do
        local head = root:CreateTexture(nil, "BORDER")
        head:SetTexture(MEDIA .. "glow")
        head:SetBlendMode("ADD")
        head:Hide()
        heads[index] = head
    end

    for index = 1, MAX_BEACONS do
        local beacon = { active = false, born = 0, dart = {}, c0 = { 1, 1, 1 }, c1 = { 1, 1, 1 } }
        beacon.beam = root:CreateTexture(nil, "BACKGROUND")
        beacon.beam:SetTexture(MEDIA .. "glow")
        beacon.beam:SetBlendMode("ADD")
        beacon.beam:Hide()
        beacon.ring = root:CreateTexture(nil, "BORDER")
        beacon.ring:SetTexture(MEDIA .. "ring")
        beacon.ring:SetBlendMode("ADD")
        beacon.ring:Hide()
        beacon.star = root:CreateTexture(nil, "OVERLAY")
        beacon.star:SetTexture(MEDIA .. "twinkle")
        beacon.star:SetBlendMode("ADD")
        beacon.star:Hide()
        beacons[index] = beacon
    end

    root:SetScript("OnUpdate", OnRootUpdate)
end

-- The watcher looks a few times a second; the root only runs while there is
-- something to draw.
local watcher = CreateFrame("Frame")
local hoverTimer, pointTimer = 0, 0

local function OnWatch(_, dt)
    hoverTimer = hoverTimer + dt
    pointTimer = pointTimer + dt
    if hoverTimer >= 0.05 then
        hoverTimer = 0
        ScanHover()
    end
    if pointTimer >= 0.3 then
        pointTimer = 0
        if not pcall(FindTargets) then targetCount = 0 end
    end
    if (hoverKind or targetCount > 0) and root and not root:IsShown() then root:Show() end
end

-- ── The game's own sparkle ──────────────────────────────────────────────────
-- The game draws its sparkle only while its outline mode is off, so the one
-- setting is not enough: with outlines on it changes nothing. The outline
-- settings are therefore switched off with it, as an option of their own,
-- because that also takes away the outline under the mouse.
--
-- Written only out of combat and never while the game's Options window is
-- open (its own Graphics page would be run from our code). The value each
-- setting had is kept in settings.savedCvars and put back when the option or
-- the module is switched off, unless the player has changed it since.

local OUTLINE_CVARS = { "graphicsOutlineMode", "raidGraphicsOutlineMode", "OutlineEngineMode", "RAIDOutlineEngineMode" }
local glowPending = false
local glowRetry = false

local function ReadCVar(name)
    local ok, value = pcall(GetCVar, name)
    if ok and value ~= nil and not Secret(value) then return tostring(value) end
    return nil   -- this client has no such setting
end

local function CVarLocked(name)
    if not (C_CVar and C_CVar.GetCVarInfo) then return false end
    local ok, _, _, _, _, isLocked, isSecure, isReadOnly = pcall(C_CVar.GetCVarInfo, name)
    return ok and (isLocked or isSecure or isReadOnly) and true or false
end

local function WantCVar(name, value)
    local current = ReadCVar(name)
    if current == nil or current == value or CVarLocked(name) then return end
    settings.savedCvars[name] = current
    pcall(SetCVar, name, value)
end

local function ReleaseCVar(name, value)
    local original = settings.savedCvars[name]
    if type(original) == "string" and ReadCVar(name) == value then
        pcall(SetCVar, name, original)
    end
    settings.savedCvars[name] = nil
end

local function ApplyGameGlow()
    if not settings or not (GetCVar and SetCVar) then return end
    if type(settings.savedCvars) ~= "table" then settings.savedCvars = {} end
    if InCombatLockdown and InCombatLockdown() then
        glowPending = true
        return
    end
    if SettingsPanel and SettingsPanel:IsShown() then
        if not glowRetry then
            glowRetry = true
            C_Timer.After(0.5, function()
                glowRetry = false
                ApplyGameGlow()
            end)
        end
        return
    end
    glowPending = false

    local sparkle = running and settings.gameGlow
    if sparkle then WantCVar(CVAR, "1") else ReleaseCVar(CVAR, "1") end
    local noOutline = sparkle and settings.outlineOff
    for _, name in ipairs(OUTLINE_CVARS) do
        if noOutline then WantCVar(name, "0") else ReleaseCVar(name, "0") end
    end
end

-- ── Left to skin ────────────────────────────────────────────────────────────
-- A corpse has no position an addon can read, so nothing can be drawn on it.
-- What can be known is that a beast died and that a hide was taken, and the
-- difference is shown as a small counter. It is a best guess: a kill counts
-- when the target was a beast or a dragonkin, or a creature whose corpse was
-- once seen to be skinnable. An entry is dropped after a few minutes, since
-- the corpse is gone by then.
--
-- It only counts for a character that has been seen skinning, so it stays
-- out of the way of everyone else.

local SKIN_TYPES = { [1] = true, [2] = true }   -- beast, dragonkin
local CORPSE_LIFE = 180
local SKIN_ICON = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01"
local skinWords = {}
local corpses = {}            -- times each entry expires, oldest first
local skinFrame
local charKey
local targetSkinnable, targetCounted = false, false

local function IsSkinner()
    return charKey and settings.skinners and settings.skinners[charKey] == true
end

local function RefreshSkinFrame(flash)
    if not skinFrame then return end
    local count = #corpses
    if count == 0 or not (running and settings.skinCount) then
        skinFrame:Hide()
        return
    end
    skinFrame.text:SetText(string.format(T("Left to skin: %d"), count))
    skinFrame:SetWidth(skinFrame.text:GetStringWidth() + 44)
    skinFrame:Show()
    if flash then
        skinFrame.flash:Stop()
        skinFrame.flash:Play()
    end
end

local function EnsureSkinFrame()
    if skinFrame then return end
    local f = CreateFrame("Frame", "OxedHubObjectGlowSkin", UIParent)
    skinFrame = f
    f:SetSize(150, 28)
    f:SetPoint(settings.skinPoint or "CENTER", UIParent, settings.skinPoint or "CENTER",
        settings.skinX or 0, settings.skinY or -180)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        settings.skinPoint, settings.skinX, settings.skinY = point, x, y
    end)
    -- Right-click: the corpses are gone or not worth it; start from nothing.
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            wipe(corpses)
            RefreshSkinFrame()
        end
    end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 3, 0)
    icon:SetTexture(SKIN_ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("LEFT", icon, "RIGHT", 6, 0)

    -- The flash is a child texture: its alpha is animated, never the frame's.
    local glow = f:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(MEDIA .. "glow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.1, 0.1)
    glow:SetPoint("CENTER")
    glow:SetSize(220, 70)
    glow:SetAlpha(0)
    local group = glow:CreateAnimationGroup()
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0)
    fade:SetDuration(0.8)
    fade:SetSmoothing("OUT")
    f.flash = group

    -- Drop entries whose corpse has had time to vanish.
    local waited = 0
    f:SetScript("OnUpdate", function(_, dt)
        waited = waited + dt
        if waited < 1 then return end
        waited = 0
        local now, changed = GetTime(), false
        while corpses[1] and corpses[1] <= now do
            table.remove(corpses, 1)
            changed = true
        end
        if changed then RefreshSkinFrame() end
    end)
    f:Hide()
end

local function BuildSkinWords()
    wipe(skinWords)
    AddWord(skinWords, "Skinning")
    AddWord(skinWords, SpellName(8613))
    if C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, 393)
        if ok then AddWord(skinWords, name) end
    end
end

local function IsSkinningSpell(spellID)
    if not PlainNumber(spellID) then return false end
    local spell = SpellName(spellID)
    return spell ~= nil and HasWord(spell, skinWords)
end

-- What the target is, read when it changes and kept: by the time it dies the
-- same questions may be answered with secrets.
local function ReadTarget()
    targetSkinnable, targetCounted = false, false
    if Known(UnitExists, "target") ~= true then return end
    if Known(UnitIsDead, "target") == true then targetCounted = true return end
    if Known(UnitCanAttack, "player", "target") ~= true then return end
    local ok, _, typeID = pcall(UnitCreatureType, "target")
    if ok and PlainNumber(typeID) and SKIN_TYPES[typeID] then
        targetSkinnable = true
        return
    end
    local okName, name = pcall(UnitName, "target")
    if okName and PlainString(name) and settings.skinNames and settings.skinNames[name] then
        targetSkinnable = true
    end
end

local function TargetDied()
    if not settings.skinCount or not IsSkinner() then return end
    if not targetSkinnable or targetCounted then return end
    targetCounted = true
    corpses[#corpses + 1] = GetTime() + CORPSE_LIFE
    EnsureSkinFrame()
    RefreshSkinFrame(true)
end

local function OnSkinCast(target)
    -- Seen skinning: from now on this character's kills are counted.
    if charKey then
        settings.skinners = settings.skinners or {}
        settings.skinners[charKey] = true
    end
    if PlainString(target) then
        settings.skinNames = settings.skinNames or {}
        settings.skinNames[target] = true
    end
end

local function OnSkinned()
    if corpses[1] then
        table.remove(corpses, 1)
        RefreshSkinFrame()
    end
end

-- ── Start and stop ──────────────────────────────────────────────────────────

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_SENT" then
        pcall(OnCastSent, ...)
        local unit, target, _, spellID = ...
        if not Secret(unit) and unit == "player" and IsSkinningSpell(spellID) then
            pcall(OnSkinCast, target)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellID = ...
        if IsSkinningSpell(spellID) then OnSkinned() end
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(ReadTarget)
    elseif event == "UNIT_HEALTH" then
        if Known(UnitIsDead, "target") == true then TargetDied() end
    elseif event == "PARTY_KILL" then
        -- In a fight "is it dead" may be unreadable; only a clear no stops it.
        if Known(UnitIsDead, "target") ~= false then TargetDied() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if glowPending then ApplyGameGlow() end
        if not running then events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A graphics preset may have switched outlines back on.
        ApplyGameGlow()
    else
        pcall(RebuildQuests)
    end
end)

local function Start()
    if running then return end
    running = true
    EnsureRoot()
    BuildWords()
    pcall(RebuildQuests)
    events:RegisterEvent("UNIT_SPELLCAST_SENT")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("QUEST_LOG_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterUnitEvent("UNIT_HEALTH", "target")
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- Not every client has this event, and asking for a missing one is an error.
    pcall(events.RegisterEvent, events, "PARTY_KILL")
    BuildSkinWords()
    local okName, name = pcall(UnitName, "player")
    if okName and PlainString(name) then
        charKey = name .. "-" .. ((GetRealmName and GetRealmName()) or "")
    end
    pcall(ReadTarget)
    hoverTimer, pointTimer = 0, 0
    watcher:SetScript("OnUpdate", OnWatch)
    ApplyGameGlow()
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    watcher:SetScript("OnUpdate", nil)
    hoverKind, hoverName, hoverKey, targetCount = nil, nil, nil, 0
    wipe(corpses)
    if skinFrame then skinFrame:Hide() end
    if root then
        ClearParticles()
        for index = 1, MAX_BEACONS do HideBeacon(beacons[index]) end
        halo:Hide()
        for index = 1, MAX_TARGETS do heads[index]:Hide() end
        root:Hide()
    end
    ApplyGameGlow()
    -- Still in combat: the old value goes back when the fight ends.
    if glowPending then events:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function StyleChoices()
    local list = {}
    for _, key in ipairs(STYLE_ORDER) do
        list[#list + 1] = { value = key, text = STYLES[key].name }
    end
    return list
end

-- The pointer and the counter have a window of their own: one window for
-- everything ran off the bottom of the screen.
local function ShowPointerOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not pointerWindow then
        local w = API:CreateOptionsWindow("Object Glow: pointer and counter", 460, 440)
        pointerWindow = w
        w:AddCheckbox(settings, "point", "Sparks fly toward something close by")
        w:AddCheckbox(settings, "pointSpots", "Toward places where you gathered before")
        w:AddCheckbox(settings, "pointMarks", "Toward the game's own marks (rares, chests)")
        w:AddChoice(settings, "markStyle", "Marks", StyleChoices())
        w:AddSlider(settings, "pointRange", "How far it looks, in yards", 30, 300, 10, "%s: %d")
        w:AddSlider(settings, "pointRadius", "Distance from the character", 60, 300, 5, "%s: %d")
        w:AddSlider(settings, "pointSize", "Size", 0.5, 2, 0.05, "%s: %.2f")
        w:AddNote("The game does not tell addons where a herb or a vein is. The sparks fly toward the game's own marks and toward places where you gathered before. Up means ahead of your character.")
        w:AddCheckbox(settings, "skinCount", "Count the beasts left to skin", nil, function() RefreshSkinFrame() end)
        w:AddNote("The counter starts after you skin something once. It counts beasts you had targeted when they died. Drag it to move, right-click to clear.")
    end
    pointerWindow:Show()
end

-- A beacon lit to the left of the options, so a change is seen at once.
local previewKinds = { "herb", "ore", "quest", "skin" }
local previewTurn = 0
local function PreviewBeacon()
    if not (running and root and settings.mark) then return end
    previewTurn = previewTurn % #previewKinds + 1
    StartBeacon(previewKinds[previewTurn], nil, root:GetWidth() * 0.25, root:GetHeight() * 0.45)
end

local function ShowBeaconOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not beaconWindow then
        local w = API:CreateOptionsWindow("Object Glow: beacon", 460, 560)
        beaconWindow = w
        w:AddCheckbox(settings, "mark", "Leave a beacon where the mouse found it",
            "A pillar of light stands on the spot for a moment after the mouse moves on. Sweep the mouse across the screen to light up everything at once.", PreviewBeacon)
        w:AddSlider(settings, "markTime", "Beacon time, seconds", 0.5, 4, 0.1, "%s: %.1f", PreviewBeacon)
        w:AddSlider(settings, "markSize", "Size", 0.5, 2.5, 0.05, "%s: %.2f", PreviewBeacon)
        w:AddSlider(settings, "markHeight", "Pillar height", 0.3, 3, 0.1, "%s: %.1f", PreviewBeacon)
        w:AddSlider(settings, "markAlpha", "Brightness", 0.2, 1.6, 0.05, "%s: %.2f", PreviewBeacon)
        w:AddChoice(settings, "markColour", "Colour", {
            { value = "find",    text = "By what was found" },
            { value = "class",   text = "Class colour" },
            { value = "rainbow", text = "Rainbow" },
            { value = "own",     text = "Your own" },
        }, PreviewBeacon)
        w:AddColour(settings, "markOwn", "Your own colour", PreviewBeacon)
        w:AddCheckbox(settings, "markBeam", "Pillar of light", nil, PreviewBeacon)
        w:AddCheckbox(settings, "markRing", "Ring on the ground", nil, PreviewBeacon)
        w:AddCheckbox(settings, "markStar", "Star at its foot", nil, PreviewBeacon)
        w:AddCheckbox(settings, "markSparks", "Sparks climbing the pillar", nil, PreviewBeacon)
        w:AddCheckbox(settings, "markBurst", "Burst of sparks when it lights", nil, PreviewBeacon)
        w:AddCheckbox(settings, "markTurnOut", "Put it out when my character turns",
            "The beacon cannot follow the spot. Switched off, it stays for its whole time even when the spot has moved away on the screen.")
        w:AddSoundPicker(settings, "markSound", "Beacon sound", "None")
        w:AddNote("Every change lights a sample beacon to the left of this window, while the module is switched on.")
    end
    beaconWindow:Show()
    PreviewBeacon()
end

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Object Glow", 460, 560)
        optionsWindow = w
        w:AddCheckbox(settings, "gameGlow", "Switch on the game's own sparkle for herbs, ore and quest objects", nil, ApplyGameGlow)
        w:AddCheckbox(settings, "outlineOff", "Switch the game's outlines off (the sparkle needs it)",
            "The game draws its sparkle only while outline mode is off. This also removes the outline under your mouse. Your own settings come back when you switch this off.", ApplyGameGlow)
        w:AddCheckbox(settings, "hover", "Sparks around the pointer on a world object")
        w:AddChoice(settings, "herbStyle", "Herbs", StyleChoices())
        w:AddChoice(settings, "oreStyle", "Ore", StyleChoices())
        w:AddChoice(settings, "questStyle", "Quest objects", StyleChoices())
        w:AddCheckbox(settings, "skin", "Corpses you can skin")
        w:AddChoice(settings, "skinStyle", "Skinning", StyleChoices())
        w:AddCheckbox(settings, "showOther", "Other objects too (chests, levers)")
        w:AddChoice(settings, "otherStyle", "Other objects", StyleChoices())
        w:AddSlider(settings, "hoverSize", "Size", 0.5, 2, 0.05, "%s: %.2f")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)

        local beaconButton = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        beaconButton:SetSize(200, 22)
        beaconButton:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)
        beaconButton:SetText(T("Beacon"))
        beaconButton:SetScript("OnClick", ShowBeaconOptions)

        local more = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        more:SetSize(200, 22)
        more:SetPoint("LEFT", beaconButton, "RIGHT", 10, 0)
        more:SetText(T("Pointer and counter"))
        more:SetScript("OnClick", ShowPointerOptions)
        w.cursorY = w.cursorY - 34
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "objectglow", label = T("Object Glow"), icon = ICON, config = settings,
        hint = T("Click: options."),
        onClick = function() ShowOptions() end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.objectglow
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.objectglow = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Lists are made here, never in DEFAULTS: a table there is shared by reference.
    if type(config.names) ~= "table" then config.names = {} end
    if type(config.spots) ~= "table" then config.spots = {} end
    if type(config.skinNames) ~= "table" then config.skinNames = {} end
    if type(config.skinners) ~= "table" then config.skinners = {} end
    if type(config.savedCvars) ~= "table" then config.savedCvars = {} end
    if type(config.markOwn) ~= "table" then config.markOwn = { 1, 0.8, 0.2 } end
    -- 1.0 kept the one game setting it changed under a key of its own.
    if config.savedGlow ~= nil then
        if config.savedCvars[CVAR] == nil then config.savedCvars[CVAR] = tostring(config.savedGlow) end
        config.savedGlow = nil
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "objectglow",
        name     = "Object Glow",
        version  = "1.4.0",
        added    = 20261113,
        inDevelopment = true,
        updated  = 20261113.5,  -- beacon settings: size, height, colour, parts
        author   = "Oxed",
        category = "quests",
        keywords = { "herb", "ore", "mining", "herbalism", "quest", "object", "glow", "sparkle", "outline", "gather" },
        desc     = "Sparks on herbs, ore and quest objects under your mouse, and a pointer to ones close by.",
        icon     = ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.names) ~= "table" then settings.names = {} end
            if type(settings.spots) ~= "table" then settings.spots = {} end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
