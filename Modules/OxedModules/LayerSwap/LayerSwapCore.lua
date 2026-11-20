-- ============================================================================
-- Layer Swap, part 1 of 5: the core (built-in OxedHub module, WoW Forever)
--
-- The files, in load order:
--   LayerSwapCore.lua   shared table, names, zones, reading the layer, events
--   LayerSwapSwap.lua   asking for a swap, accepting, hosting other players
--   LayerSwapGuild.lua  guildmates' layers, layer talk in chat
--   LayerSwapUI.lua     the portal on screen, the window, the request toast
--   LayerSwap.lua       registration, options, minimap button, slash, keys
-- Everything is shared through OxedHub.LayerSwap (LS below). State that one
-- file changes stays local to it and is read through a function.
--
-- How a layer is read: the game has no layer API. A creature's GUID is
-- Creature-0-<server>-<map>-<zoneUID>-<npc>-<spawn>; the layer is <server>
-- (6843 of 6843-8), the second part differs per player. Ids travel whole
-- ("6843-8", what LayerSwap, Bulo and Forever Layers send) and are compared
-- by the server part. Only creatures count: pets, guardians and companions
-- carry their owner's layer. A layer is believed when two creatures agree,
-- or one right after a world transfer.
-- ============================================================================

local _, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local LS = {}
OxedHub.LayerSwap = LS

LS.PREFIX = "|cff9f7bffOxedHub Layer Swap:|r "
LS.ICON = "Interface\\Icons\\Spell_Arcane_PortalDalaran"
LS.running = false
LS.settings = nil

function LS.T(text) return (OxedHub.T and OxedHub.T(text)) or text end

function LS.Say(text)
    print(LS.PREFIX .. tostring(text))
end

-- A line the player can switch off (Chat messages).
function LS.Chat(text)
    if LS.settings and LS.settings.chat == false then return end
    LS.Say(text)
end

-- ── Values that may be secret ───────────────────────────────────────────────

function LS.Public(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then return false end
    return true
end

function LS.Text(v)
    return LS.Public(v) and type(v) == "string" and v ~= "" and #v <= 250 and not v:find("%c")
end

-- true, false, or nil when the answer is secret or the call failed.
function LS.Known(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or not LS.Public(v) then return nil end
    return v and true or false
end

-- ── Names ───────────────────────────────────────────────────────────────────
-- Forever names are "First Surname" with a space; a sender or the who list may
-- add "-Realm". The short form is the key everywhere.

function LS.Short(name)
    if not LS.Text(name) then return nil end
    return name:match("^([^%-]+)") or name
end

function LS.Me()
    local ok, n = pcall(UnitName, "player")
    if ok and LS.Text(n) then return n end
    return nil
end

function LS.UnitShortName(unit)
    local ok, first, surname = pcall(UnitName, unit)
    if not ok or not LS.Text(first) then return nil end
    if LS.Text(surname) then
        if NameUtil and NameUtil.GetFullNameWithoutRealm then
            local ok2, whole = pcall(NameUtil.GetFullNameWithoutRealm, first, surname)
            if ok2 and LS.Text(whole) then return whole end
        end
        return first .. " " .. surname
    end
    return first
end

-- ── Zones ───────────────────────────────────────────────────────────────────

local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

-- The zone's map id: a cave or a building counts as its zone.
function LS.Zone()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not LS.Public(id) or type(id) ~= "number" then return nil end
    for _ = 1, 6 do
        local okI, info = pcall(C_Map.GetMapInfo, id)
        if not okI or type(info) ~= "table" then return id end
        if info.mapType == ZONE_TYPE or not info.parentMapID or info.parentMapID == 0 then return id end
        if (info.mapType or 0) < ZONE_TYPE then return id end
        id = info.parentMapID
    end
    return id
end

function LS.ZoneName(zone)
    if zone and C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, zone)
        if ok and type(info) == "table" and LS.Text(info.name) then return info.name end
    end
    return LS.T("Unknown zone")
end

-- The player's spot on the zone map, 0..1 each, or nil.
function LS.MapPos(zone)
    if not (zone and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, zone, "player")
    if not ok or not LS.Public(pos) or type(pos) ~= "table" then return nil end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then
        local okX, a, b = pcall(pos.GetXY, pos)
        if okX then x, y = a, b end
    end
    if not LS.Public(x) or not LS.Public(y) then return nil end
    if type(x) == "number" and type(y) == "number" and x > 0 and y > 0 and x < 1 and y < 1 then return x, y end
    return nil
end

-- Yards between the player and a spot on the same zone map, or nil.
function LS.Distance(zone, px, py)
    if not (zone and px and py and C_Map and C_Map.GetMapWorldSize) then return nil end
    local x, y = LS.MapPos(zone)
    if not x then return nil end
    local ok, w, h = pcall(C_Map.GetMapWorldSize, zone)
    if not ok or not LS.Public(w) or type(w) ~= "number" or type(h) ~= "number" or w <= 0 then return nil end
    local dx, dy = (x - px) * w, (y - py) * h
    return math.sqrt(dx * dx + dy * dy)
end

function LS.InInstance()
    local ok, inside, kind = pcall(IsInInstance)
    if not ok or not LS.Public(inside) then return false end
    return inside == true and kind ~= "none"
end

-- ── Layer ids and their names ───────────────────────────────────────────────

function LS.Server(id)
    if type(id) ~= "string" then return nil end
    return id:match("^(%d+)%-%d+$") or id:match("^(%d+)$")
end

function LS.Same(a, b)
    local sa, sb = LS.Server(a), LS.Server(b)
    return sa ~= nil and sa == sb
end

function LS.ValidId(id)
    return type(id) == "string" and #id <= 24 and id:match("^%d+%-%d+$") ~= nil
end

-- "W2": worked out from the server number, the same name every player of a
-- layer add-on that names layers this way sees for one layer.
function LS.SharedName(server)
    local n = tonumber(server)
    if not n then return "?" end
    return string.char(65 + n % 26) .. tostring(math.floor(n / 26) % 10)
end

-- A, B, C in the order this character met them in the zone, new every day.
local function LetterName(zone, server)
    local s = LS.settings
    if not s then return "?" end
    if type(s.letters) ~= "table" then s.letters = {} end
    local key = tostring(zone or 0)
    local day = date("%j")
    local z = s.letters[key]
    if type(z) ~= "table" or z.day ~= day then
        z = { n = 0, day = day, k = {} }
        s.letters[key] = z
    end
    if not z.k[server] then
        z.n = z.n + 1
        z.k[server] = z.n
    end
    local n = z.k[server]
    return n <= 26 and string.char(64 + n) or ("Z" .. (n - 25))
end

-- The layer's short name in the player's chosen style.
function LS.LayerName(id, zone)
    local server = LS.Server(id)
    if not server then return "?" end
    local style = LS.settings and LS.settings.names or "shared"
    if style == "number" then return server end
    if style == "letters" then return LetterName(zone or LS.Zone(), server) end
    return LS.SharedName(server)
end

-- One colour per layer, the same for everyone: it tints the portal.
local COLORS = {
    { 0.62, 0.48, 1.00 }, { 0.30, 0.80, 1.00 }, { 0.35, 1.00, 0.55 }, { 1.00, 0.55, 0.25 },
    { 1.00, 0.35, 0.60 }, { 1.00, 0.85, 0.30 }, { 0.40, 1.00, 0.95 }, { 0.95, 0.40, 1.00 },
}
LS.UNKNOWN_COLOR = { 0.62, 0.42, 1.00 } -- arcane violet until the layer is known

function LS.LayerColor(id)
    local n = tonumber(LS.Server(id) or "")
    if not n then return LS.UNKNOWN_COLOR end
    return COLORS[n % #COLORS + 1]
end

function LS.ColorCode(id)
    local c = LS.LayerColor(id)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

function LS.Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return seconds .. LS.T(" s") end
    if seconds < 3600 then return math.floor(seconds / 60) .. LS.T(" min") end
    return math.floor(seconds / 3600) .. LS.T(" h")
end

-- ── Small event bus ─────────────────────────────────────────────────────────
-- Each file adds handlers; the one frame here is registered only while the
-- module runs.

local handlers, tickers, listeners = {}, {}, {}
local events = CreateFrame("Frame")

function LS.On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

-- fn(now) every second while the module runs.
function LS.OnTick(fn) table.insert(tickers, fn) end

-- Something worth redrawing: the UI listens.
function LS.Listen(fn) table.insert(listeners, fn) end

local refreshQueued = false
function LS.Changed()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        for _, fn in ipairs(listeners) do pcall(fn) end
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, event, ...)
        if not ok then
            local key = event .. tostring(err)
            if not LS.reported then LS.reported = {} end
            if not LS.reported[key] then
                LS.reported[key] = true
                LS.Say("|cffff6060" .. event .. ": " .. tostring(err) .. "|r")
            end
        end
    end
end)

local ticker
function LS.StartEvents()
    for event in pairs(handlers) do pcall(events.RegisterEvent, events, event) end
    if not ticker then
        ticker = C_Timer.NewTicker(1, function()
            if not LS.running then return end
            local now = GetTime()
            for _, fn in ipairs(tickers) do
                local ok, err = pcall(fn, now)
                if not ok and not (LS.reported and LS.reported[tostring(err)]) then
                    LS.reported = LS.reported or {}
                    LS.reported[tostring(err)] = true
                    LS.Say("|cffff6060tick: " .. tostring(err) .. "|r")
                end
            end
        end)
    end
end

function LS.StopEvents()
    events:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
end

-- ── The log (Log tab) ───────────────────────────────────────────────────────

local log = {}
function LS.Log(text)
    table.insert(log, 1, { at = time(), text = tostring(text) })
    if #log > 120 then table.remove(log) end
    LS.Changed()
end
function LS.GetLog() return log end

-- ── Reading the layer ───────────────────────────────────────────────────────

local TR = {
    WINDOW = 90,          -- a creature read longer ago than this no longer votes
    STALE_FOR = 10,       -- creatures in view at a transfer belong to the old layer this long
    EXPECT_FOR = 60,      -- after a transfer one creature is enough this long
    SEEN_TTL = 3600,      -- a layer not seen for an hour leaves the zone's list
    HIST_MAX = 8,
}
local samples = {}        -- [server] = { guids = { [guid] = t }, id = "server-zoneUID", last = t }
local keyZones = {}       -- [server] = { [zone] = reads }: where each key was read this session
local current, currentId, currentSince
local previous            -- the layer before the last change, for "back"
local trackedZone
local expectUntil, staleUntil = 0, 0
local stale = {}
local unknownSince        -- set while the layer is unknown after a transfer

local SCAN_UNITS = { "target", "mouseover", "focus", "softenemy", "softfriend", "softinteract", "npc" }
for i = 1, 40 do SCAN_UNITS[#SCAN_UNITS + 1] = "nameplate" .. i end

function LS.MyLayer() return currentId end
function LS.MyServer() return current end
function LS.LayerSince() return currentSince end
function LS.PreviousLayer() return previous end
function LS.Reading() return unknownSince ~= nil end

local function SeenTable(zone)
    local s = LS.settings
    if not (s and zone) then return nil end
    if type(s.seen) ~= "table" then s.seen = {} end
    local key = tostring(zone)
    if type(s.seen[key]) ~= "table" then s.seen[key] = {} end
    return s.seen[key]
end

local function HistTable(zone)
    local s = LS.settings
    if not (s and zone) then return nil end
    if type(s.hist) ~= "table" then s.hist = {} end
    local key = tostring(zone)
    if type(s.hist[key]) ~= "table" then s.hist[key] = {} end
    return s.hist[key]
end

-- Layers seen in a zone in the last hour: { { id, server, first, last } }, newest first.
function LS.SeenLayers(zone)
    local seen = SeenTable(zone or LS.Zone())
    local out, wall = {}, time()
    if not seen then return out end
    for server, rec in pairs(seen) do
        if type(rec) ~= "table" or wall - (rec.last or 0) > TR.SEEN_TTL then
            seen[server] = nil
        else
            out[#out + 1] = { id = rec.id, server = server, first = rec.first, last = rec.last }
        end
    end
    table.sort(out, function(a, b) return (a.last or 0) > (b.last or 0) end)
    return out
end

-- Note a layer in a zone (ours, or one a helper or guildmate said they are on).
function LS.NoteLayer(zone, id, own)
    local seen = SeenTable(zone)
    local server = LS.Server(id)
    if not (seen and server) then return end
    local wall = time()
    local rec = seen[server]
    if type(rec) ~= "table" then
        rec = { id = id, first = wall }
        seen[server] = rec
    end
    rec.last = wall
    if own then rec.id = id rec.mine = wall end
end

-- The layers this character stood on in a zone, newest first: { { server, id, at } }.
function LS.History(zone)
    return HistTable(zone or LS.Zone()) or {}
end

-- Layers stood on in this zone in the last hour, the current one left out.
function LS.StoodLayerIds(zone, except, limit)
    local out = {}
    local wall = time()
    for _, h in ipairs(LS.History(zone)) do
        if wall - (h.at or 0) <= TR.SEEN_TTL and not LS.Same(h.id, except) then
            local dup = false
            for _, id in ipairs(out) do if LS.Same(id, h.id) then dup = true end end
            if not dup then out[#out + 1] = h.id end
            if #out >= (limit or 6) then break end
        end
    end
    return out
end

local function ResetZone(zone)
    trackedZone = zone
    samples = {}
    current, currentId, currentSince = nil, nil, nil
end

local function SetCurrent(server, how)
    local rec = samples[server]
    if not rec then return end
    local old, oldId = current, currentId
    unknownSince = nil
    if old == server then
        currentId = rec.id
        return
    end
    current, currentId, currentSince = server, rec.id, GetTime()
    local zone = trackedZone
    LS.NoteLayer(zone, rec.id, true)
    local hist = HistTable(zone)
    if hist and not (hist[1] and hist[1].server == server) then
        table.insert(hist, 1, { server = server, id = rec.id, at = time() })
        while #hist > TR.HIST_MAX do table.remove(hist) end
    end
    if oldId then previous = oldId end
    LS.Log(("Layer %s (%s) in %s, %s."):format(LS.LayerName(rec.id, zone), rec.id, LS.ZoneName(zone), how))
    if LS.OnLayerChanged then LS.OnLayerChanged(oldId, rec.id, how) end
    LS.Changed()
end

local function Border(server, zone)
    local zones = keyZones[server]
    if not zones then return false end
    local here = zones[zone] or 0
    for z, n in pairs(zones) do
        if z ~= zone and n >= 2 and n > here then return true end
    end
    return false
end

local function Decide(now)
    local zone = trackedZone
    local counts, best, bestN = {}, nil, 0
    for server, rec in pairs(samples) do
        local n = 0
        for guid, t in pairs(rec.guids) do
            if now - t > TR.WINDOW then rec.guids[guid] = nil else n = n + 1 end
        end
        if n == 0 then
            samples[server] = nil
        elseif not Border(server, zone) or server == current then
            counts[server] = n
            if n > bestN then best, bestN = server, n end
        end
    end
    if not best or best == current then
        if best and unknownSince then SetCurrent(best, "read again") end
        return
    end
    -- one creature is enough for a first reading; changing a known layer needs two
    local need = (now < expectUntil or not current) and 1 or 2
    local curN = current and counts[current] or 0
    if bestN < need then return end
    if curN > 0 and bestN <= curN then return end
    SetCurrent(best, (now < expectUntil) and "after a transfer" or (current and "the creatures changed" or "read"))
end

-- One GUID from a unit; guid may be handed in by the caller.
function LS.ReadUnit(unit, guid)
    if not LS.running then return end
    local function Skip(why) LS.lastSkip = tostring(unit) .. ": " .. why end
    if not guid then
        if LS.Known(UnitExists, unit) ~= true then return end
        local ok, g = pcall(UnitGUID, unit)
        if not ok then return Skip("GUID refused") end
        guid = g
    end
    if not LS.Public(guid) or type(guid) ~= "string" then return Skip("GUID secret") end
    local kind, _, server, _, zoneUID = strsplit("-", guid)
    if kind == "Player" or kind == "Pet" then return end
    if (kind ~= "Creature" and kind ~= "Vehicle") or not server or not zoneUID then return Skip("not a creature " .. guid) end
    if not server:match("^%d+$") or not zoneUID:match("^%d+$") or zoneUID == "0" then return Skip("no layer in " .. guid) end
    if unit then
        if LS.Known(UnitPlayerControlled, unit) == true then return Skip("player controlled") end
        if UnitIsOtherPlayersPet and LS.Known(UnitIsOtherPlayersPet, unit) == true then return Skip("a pet") end
        if UnitIsBattlePetCompanion and LS.Known(UnitIsBattlePetCompanion, unit) == true then return Skip("a companion") end
    end
    if LS.InInstance() then return Skip("in an instance") end
    local now = GetTime()
    if now < staleUntil and stale[guid] then return Skip("old layer") end
    local zone = LS.Zone()
    if not zone then return Skip("zone unknown") end
    LS.lastSkip = nil
    LS.lastGuid = guid
    if zone ~= trackedZone then ResetZone(zone) end
    local rec = samples[server]
    if not rec then
        rec = { guids = {} }
        samples[server] = rec
    end
    rec.guids[guid] = now
    rec.id, rec.last = server .. "-" .. zoneUID, now
    keyZones[server] = keyZones[server] or {}
    keyZones[server][zone] = (keyZones[server][zone] or 0) + 1
    LS.lastReadAt = now
    Decide(now)
end

function LS.Scan()
    if not LS.running then return end
    for _, unit in ipairs(SCAN_UNITS) do LS.ReadUnit(unit) end
end

-- A transfer: what is in view belongs to the layer left, and one creature of
-- another layer is enough for a while.
function LS.ExpectMove(why)
    local now = GetTime()
    stale = {}
    for _, rec in pairs(samples) do
        for guid in pairs(rec.guids) do stale[guid] = true end
    end
    staleUntil = now + TR.STALE_FOR
    expectUntil = now + TR.EXPECT_FOR
    samples = {}
    unknownSince = now
    C_Timer.After(1.2, LS.WantLayer)
    LS.Log("World transfer (" .. tostring(why) .. "): reading the layer again.")
    LS.Changed()
    -- the new creatures come into view over the next seconds
    for _, delay in ipairs({ 1.2, 2.5, 4, 7, 11 }) do
        C_Timer.After(delay, function() if unknownSince then LS.Scan() end end)
    end
end

-- Someone we trust named the layer we moved to (the host's answer): show it
-- at once, provisional, until creatures confirm or correct it.
function LS.AssumeLayer(id, how)
    if not LS.ValidId(id) then return end
    local server = LS.Server(id)
    samples[server] = samples[server] or { guids = {} }
    samples[server].id, samples[server].last = id, GetTime()
    SetCurrent(server, how or "the host's answer")
end

local function OnZone()
    local zone = LS.Zone()
    if zone ~= trackedZone then
        ResetZone(zone)
        if LS.InInstance() then unknownSince = nil end
        LS.Changed()
    end
    C_Timer.After(1, LS.WantLayer)
end

LS.On("PLAYER_ENTERING_WORLD", function() OnZone() end)
LS.On("ZONE_CHANGED_NEW_AREA", function() OnZone() end)
LS.On("ZONE_CHANGED", function() OnZone() end)
LS.On("ZONE_CHANGED_INDOORS", function() OnZone() end)
LS.On("NAME_PLATE_UNIT_ADDED", function(_, unit) if LS.Text(unit) then LS.ReadUnit(unit) end end)
LS.On("PLAYER_TARGET_CHANGED", function() LS.ReadUnit("target") end)
LS.On("UPDATE_MOUSEOVER_UNIT", function() LS.ReadUnit("mouseover") end)
LS.On("PLAYER_FOCUS_CHANGED", function() LS.ReadUnit("focus") end)
LS.On("PLAYER_SOFT_ENEMY_CHANGED", function() LS.ReadUnit("softenemy") end)
LS.On("PLAYER_SOFT_FRIEND_CHANGED", function() LS.ReadUnit("softfriend") end)
LS.On("PLAYER_SOFT_INTERACT_CHANGED", function() LS.ReadUnit("softinteract") end)
LS.On("GOSSIP_SHOW", function() LS.ReadUnit("npc") end)
LS.On("MERCHANT_SHOW", function() LS.ReadUnit("npc") end)
LS.On("QUEST_GREETING", function() LS.ReadUnit("npc") end)
LS.On("QUEST_DETAIL", function() LS.ReadUnit("npc") end)
LS.On("SHARD_TRANSFER", function() LS.ExpectMove("the game moved you") end)

-- A creature that speaks is heard only on its own layer, and the line
-- carries its GUID (the 12th argument).
local function Spoke(_, _, _, _, _, _, _, _, _, _, _, _, guid)
    if LS.Text(guid) then LS.ReadUnit(nil, guid) end
end
LS.On("CHAT_MSG_MONSTER_SAY", Spoke)
LS.On("CHAT_MSG_MONSTER_YELL", Spoke)
LS.On("CHAT_MSG_MONSTER_EMOTE", Spoke)

-- ── Showing the nameplates for a moment ─────────────────────────────────────
-- With nameplates off nothing in view can be read until the player points at
-- a creature. While the layer is unknown, switch the creature nameplates on
-- for a few seconds, read what they bring, and put each setting back exactly
-- as it was (only one we switched on, and only while it still reads "1").

local PLATES = { "nameplateShowEnemies", "nameplateShowFriendlyNPCs", "nameplateShowAll" }
local FLASH_FOR, FLASH_EVERY, FLASH_TRIES = 3, 12, 5
local flashAt, flashTries = nil, FLASH_TRIES   -- no showing until the player asks (a click)
local lastFlash = -1000

local function CVar(name, value)
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if type(get) ~= "function" or type(set) ~= "function" then return nil end
    if value ~= nil then return pcall(set, name, value) end
    local ok, v = pcall(get, name)
    if not ok or not LS.Public(v) or v == nil then return nil end
    return tostring(v)
end

local function Busy()
    if LS.Known(InCombatLockdown) == true then return true end
    if UnitOnTaxi and LS.Known(UnitOnTaxi, "player") == true then return true end
    return LS.InInstance()
end

function LS.PlatesBack()
    local s = LS.settings
    local back = s and s.platesBack
    flashAt = nil
    if type(back) ~= "table" then return end
    if LS.Known(InCombatLockdown) == true then return end
    for name, old in pairs(back) do
        if CVar(name) == "1" then CVar(name, old) end
    end
    s.platesBack = nil
end

local function FlashPlates(now)
    local s = LS.settings
    if not s or s.flashPlates == false or flashAt or s.platesBack then return end
    if flashTries >= FLASH_TRIES or now - lastFlash < FLASH_EVERY or Busy() then return end
    local back = {}
    for _, name in ipairs(PLATES) do
        local v = CVar(name)
        if v and v ~= "1" then back[name] = v end
    end
    lastFlash = now
    flashTries = flashTries + 1
    if not next(back) then return end   -- already shown: what is in view is all there is
    s.platesBack = back                  -- saved first, so a crash or logout still puts them back
    for name in pairs(back) do CVar(name, "1") end
    flashAt = now
    LS.Log("Nameplates shown for a moment to read the layer.")
    C_Timer.After(0.5, LS.Scan)
    C_Timer.After(1.5, LS.Scan)
end

-- A fresh need to know the layer (login, zone, transfer, a click): read every
-- second and allow the nameplates to be shown again.
local pollUntil = 0
function LS.WantLayer(byClick)
    pollUntil = GetTime() + 240
    -- the nameplates are shown once, and only for a click: shown on every zone
    -- change they flickered on and off all the time while the layer stayed unknown
    flashTries = byClick and (FLASH_TRIES - 1) or FLASH_TRIES
    LS.Scan()
end

LS.OnTick(function(now)
    if flashAt and (current or now - flashAt >= FLASH_FOR) then LS.PlatesBack() end
    if current and not unknownSince then return end
    if now > pollUntil then return end
    LS.Scan()
    if not current then FlashPlates(now) end
end)

LS.On("PLAYER_REGEN_ENABLED", function()
    if LS.settings and LS.settings.platesBack and not flashAt then LS.PlatesBack() end
end)
LS.On("PLAYER_LOGOUT", function() flashAt = nil LS.PlatesBack() end)

function LS.ResetReading()
    ResetZone(LS.Zone())
    keyZones, stale, unknownSince = {}, {}, nil
    LS.PlatesBack()   -- left on by a crash or a reload mid-moment
    LS.WantLayer()
end
