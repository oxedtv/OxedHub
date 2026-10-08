-- ============================================================================
-- Gold World Quests (built-in OxedHub module)
-- Tracks gold-rewarding world quests, Midnight special assignments, and weekly
-- caches across characters.
--
-- Features:
--   - Scans active world quests in Midnight zones rewarding gold
--   - Calculates optimal 2-opt TomTom routes with auto-advancing crazy arrow
--   - Tracks Special Assignments status and 3-WQ unlock requirements per zone
--   - Tracks weekly cache completion per character with automatic reset detection
--   - Clean, draggable, resizable HUD tracker window
--   - Integrated Options window and slash commands (/gwq, /oxgold)
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer
local Data = OxedHub.GoldWQData or {}

local PREFIX = "|cffffd100GoldWQ:|r "
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_Coin_02"
local MM_ICON = "Interface\\Icons\\Achievement_Character_Goblin_Male"

local DEFAULTS = {
    enabled     = false,  -- off until player enables it (OxedHub standard)
    openOnLogin = false,  -- open the tracker HUD on login
    announce    = true,   -- announce gold WQ count & total gold in chat
    scale       = 1.0,    -- HUD window scale
    alpha       = 0.85,   -- HUD background opacity
    collapsed   = false,  -- collapse HUD to title bar
    noBorder    = false,  -- hide HUD border
    minimap     = true,   -- show minimap button
}

local settings          -- OxedHubDB.modules.goldwq, bound at login
local optionsWindow
local ui, content
local refreshUI
local toggleOptions
local setMinimapShown
local rows = {}
local ROW_H = 18

local watcher = CreateFrame("Frame")
local ticker = nil

-- Runtime state
local available = {}      -- gold WQs currently up: { id, title, zone, mapID, copper, x, y, left }
local specials = {}       -- special assignments currently up
local activeList = {}     -- active WQs for debug
local skippedList = {}    -- skipped POIs for debug
local knownZone = {}      -- questID -> zone name
local seenPOI = {}        -- questIDs found on zone maps
local retries = 0
local shouldAnnounce = false
local pendingScan = false
local routeState = {}     -- TomTom waypoints
local activeRoute = nil   -- { stops = {}, current = 1, maps = {} }
local updateRouteButtonText = nil
local routePins = {}      -- World map numbered pins

-- Forward declarations
local scan, requestScan, openQuest, sendRoute, clearRoute, buildUI, toggleUI, SkipRouteStop

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function SecretValue(val)
    return issecretvalue and issecretvalue(val) or false
end

local function CharKey()
    local name = UnitName("player") or "Unknown"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName():gsub("[%s%-]", "")) or "Realm"
    if SecretValue(name) or SecretValue(realm) then return "Secret-Player" end
    return name .. "-" .. realm
end

local function MoneyString(copper)
    if not copper or copper <= 0 then return "0c" end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    if GetMoneyString then return GetMoneyString(copper, true) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return ("%dg %ds %dc"):format(g, s, c)
end

local function FormatTimeLeft(sec)
    if not sec then return "" end
    if sec >= 86400 then return ("%dd %dh"):format(sec / 86400, (sec % 86400) / 3600) end
    if sec >= 3600 then return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60) end
    return ("%dm"):format(sec / 60)
end

-- ── Saved Data & Weekly Reset ───────────────────────────────────────────────

local function EnsureData()
    if not settings then settings = {} end
    settings.chars = type(settings.chars) == "table" and settings.chars or {}
    settings.disabledCaches = type(settings.disabledCaches) == "table" and settings.disabledCaches or {}
    settings.ui = type(settings.ui) == "table" and settings.ui or {}
    settings.minimap = type(settings.minimap) == "table" and settings.minimap or {}

    -- Seamless migration from standalone GoldWQDB if present
    if _G.GoldWQDB and type(_G.GoldWQDB.chars) == "table" and not settings.migratedFromStandalone then
        for k, v in pairs(_G.GoldWQDB.chars) do
            if not settings.chars[k] then settings.chars[k] = v end
        end
        if _G.GoldWQDB.resetAt and not settings.resetAt then
            settings.resetAt = _G.GoldWQDB.resetAt
        end
        settings.migratedFromStandalone = true
    end
end

local function CurrentChar()
    EnsureData()
    local key = CharKey()
    settings.chars[key] = settings.chars[key] or {
        weekQuests = {}, weekCopper = 0, totalCopper = 0, caches = {}, wqDone = {}, turnedIn = {}, trackingSince = time()
    }
    local c = settings.chars[key]
    c.caches = c.caches or {}
    c.wqDone = c.wqDone or {}
    c.turnedIn = c.turnedIn or {}
    c.weekQuests = c.weekQuests or {}
    c.weekCopper = c.weekCopper or 0
    c.totalCopper = c.totalCopper or 0
    c.trackingSince = c.trackingSince or time()
    return c
end

local function RollWeek()
    if not settings then return end
    local now = time()
    if settings.resetAt and now >= settings.resetAt then
        for _, c in pairs(settings.chars) do
            c.weekQuests = {}
            c.weekCopper = 0
            c.caches = {}
            c.wqDone = {}
            c.turnedIn = {}
            c.trackingSince = time()
        end
    end
    local secUntilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset() or 604800
    settings.resetAt = now + secUntilReset
end

local function CacheEnabled(name)
    return not (settings and settings.disabledCaches and settings.disabledCaches[name])
end

local function TrackedCaches()
    local list = {}
    for _, cache in ipairs(Data.Caches or {}) do
        if #cache.quests > 0 and CacheEnabled(cache.name) then
            list[#list + 1] = cache
        end
    end
    return list
end

local function SnapshotCaches()
    local c = CurrentChar()
    for _, cache in ipairs(Data.Caches or {}) do
        local count = 0
        for _, id in ipairs(cache.quests) do
            if c.turnedIn[id] then count = count + 1 end
        end
        c.caches[cache.name] = count
    end
    if refreshUI then refreshUI() end
end

-- ── Scanning Engine ─────────────────────────────────────────────────────────

local function ZoneName(id, fallback)
    local zid = C_TaskQuest and C_TaskQuest.GetQuestZoneID and C_TaskQuest.GetQuestZoneID(id)
    if zid and zid > 0 and C_Map and C_Map.GetMapInfo then
        local mi = C_Map.GetMapInfo(zid)
        if mi and mi.name then return mi.name end
    end
    return fallback
end

local function QuestTitle(id)
    local info = C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(id)
    if type(info) == "string" and info ~= "" then return info end
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    return title or ("Quest " .. tostring(id))
end

-- ── Remembered names ──────────────────────────────────────────────────────
-- A quest's title and zone do not change while it is up, and asking for them
-- costs a map info table each time. Kept per quest id; the fallbacks ("Quest
-- 12345", the scan zone's own name) are not kept, so a title that was still
-- loading is asked for again next time.
local titleCache, zoneCache = {}, {}

local function CachedTitle(id)
    local title = titleCache[id]
    if title then return title end
    title = QuestTitle(id)
    if title ~= ("Quest " .. tostring(id)) then titleCache[id] = title end
    return title
end

local function CachedZone(id, fallback)
    local zone = zoneCache[id]
    if zone then return zone end
    zone = ZoneName(id, nil)
    if zone then
        zoneCache[id] = zone
        return zone
    end
    return fallback
end

-- ── The scan, a zone a frame ──────────────────────────────────────────────
-- ⚠ /oxprofile caught the whole scan in one go at 8 ms and 170 KB, a third of
-- a frame, every time it ran. Most of that was a debug string built for every
-- quest (each of its fields, sorted and joined) that nothing ever read, now
-- gone, and names asked for again on every scan, now kept above. What is left
-- is spread out: one zone per frame, so six zones cost six small frames rather
-- than one long one. A scan asked for while one runs waits for it to finish.

local job               -- the scan in progress, or nil
local rescanWanted = false

local function ScanZone(z, j)
    local getQuests = C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)
    if not getQuests then return end
    local ok, infos = pcall(getQuests, z[1])
    if not (ok and type(infos) == "table") then return end

    for _, info in ipairs(infos) do
        local id = info.questID
        if id and not j.seen[id] then
            j.seen[id] = true
            local isWQ = C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(id)
            if isWQ then
                knownZone[id] = CachedZone(id, z[2])
            end
            local left = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds and C_TaskQuest.GetQuestTimeLeftSeconds(id)

            local reason = nil
            if not isWQ then
                reason = "not a world quest"
            elseif not (C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(id)) then
                reason = "not active"
            elseif left and left <= 0 then
                reason = "expired"
            elseif C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) then
                reason = "completed"
            end

            if reason then
                j.skipped[#j.skipped + 1] = {
                    id = id, title = CachedTitle(id), zone = CachedZone(id, z[2]),
                    reason = reason, mapID = z[1], x = info.x, y = info.y, left = left,
                }
            else
                local ex, ey, emap = info.x, info.y, z[1]
                local zid = C_TaskQuest and C_TaskQuest.GetQuestZoneID and C_TaskQuest.GetQuestZoneID(id)
                if zid and zid > 0 and zid ~= z[1] and C_TaskQuest and C_TaskQuest.GetQuestLocation then
                    local lx, ly = C_TaskQuest.GetQuestLocation(id, zid)
                    if lx and ly then ex, ey, emap = lx, ly, zid end
                end

                local entry = {
                    id = id, title = CachedTitle(id), zone = CachedZone(id, z[2]), mapID = emap,
                    x = ex, y = ey, left = left, copper = 0,
                }

                local tag = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
                local tagName = tag and tag.tagName
                local isSA = (info.isCapstone == true)
                    or (tagName and tagName:lower():find("assignment") ~= nil) or false
                local rewNames = {}
                local loaded = (not HaveQuestRewardData) or HaveQuestRewardData(id)
                if loaded then
                    entry.copper = (GetQuestLogRewardMoney and GetQuestLogRewardMoney(id)) or 0
                    local numRewards = (GetNumQuestLogRewards and GetNumQuestLogRewards(id)) or 0
                    for i = 1, numRewards do
                        local rname = GetQuestLogRewardInfo and GetQuestLogRewardInfo(i, id)
                        if rname then
                            rewNames[#rewNames + 1] = rname
                            if rname:find("Fabled") and rname:find("Cache") then isSA = true end
                        end
                    end
                else
                    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
                        C_TaskQuest.RequestPreloadRewardData(id)
                    end
                    j.unloaded = j.unloaded + 1
                end

                j.active[#j.active + 1] = {
                    entry = entry,
                    rew = loaded and table.concat(rewNames, ", ") or "(reward not loaded)"
                }
                if entry.copper > 0 then j.list[#j.list + 1] = entry end
                if isSA then j.sa[#j.sa + 1] = entry end
            end
        end
    end
end

local function FinishScan(j)
    table.sort(j.list, function(a, b) return a.copper > b.copper end)
    table.sort(j.sa, function(a, b) return (a.zone or "") < (b.zone or "") end)
    available = j.list
    specials = j.sa
    activeList = j.active
    skippedList = j.skipped
    seenPOI = j.seen

    if refreshUI then refreshUI() end

    -- Retry preload for rewards if some weren't cached yet
    if j.unloaded > 0 and retries < 5 then
        retries = retries + 1
        C_Timer.After(2, scan)
        return
    end

    if shouldAnnounce and settings.announce then
        shouldAnnounce = false
        local total = 0
        for _, q in ipairs(available) do total = total + q.copper end
        print(PREFIX .. ("%d gold world quest(s) available (%s total). Type /gwq to view."):format(#available, MoneyString(total)))
    end
end

local function StepScan()
    local j = job
    if not j then return end
    if not settings or settings.enabled == false then
        job = nil
        return
    end

    j.zone = j.zone + 1
    local zones = Data.ZONES or {}
    local z = zones[j.zone]
    if z then
        ScanZone(z, j)
        C_Timer.After(0, StepScan)
        return
    end

    job = nil
    FinishScan(j)
    if rescanWanted then
        rescanWanted = false
        scan()
    end
end

-- ⚠ QUEST_LOG_UPDATE arrives many times a minute (any quest progress, any
-- loot): a full scan of every zone for each one was most of what this module
-- cost. That event scans at most once per QUEST_LOG_GAP; zone changes, turn-ins
-- and the Rescan button still scan at once.
local QUEST_LOG_GAP = 30
local lastScanAt = 0

scan = function()
    if not settings or settings.enabled == false then return end
    if not (C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)) then return end
    if job then
        rescanWanted = true
        return
    end
    lastScanAt = GetTime()
    job = { zone = 0, list = {}, seen = {}, unloaded = 0, sa = {}, active = {}, skipped = {} }
    StepScan()
end

requestScan = function(delay)
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(delay or 1, function()
        pendingScan = false
        retries = 0
        scan()
    end)
end

-- ── Map & Waypoint Navigation ───────────────────────────────────────────────

local function ShowMap(mapID)
    if not (WorldMapFrame and mapID) then return end
    if not WorldMapFrame:IsShown() and ToggleWorldMap then ToggleWorldMap() end
    if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    C_Timer.After(0.2, function()
        if WorldMapFrame:IsShown() and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() ~= mapID then
            WorldMapFrame:SetMapID(mapID)
        end
    end)
end

local function SetNativeWaypoint(mapID, x, y, questID, showMap)
    if C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
    if questID and C_QuestLog and C_QuestLog.AddWorldQuestWatch then
        pcall(C_QuestLog.AddWorldQuestWatch, questID)
    end
    C_Timer.After(0, function()
        if mapID and x and y and C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID) then
            if UiMapPoint and UiMapPoint.CreateFromCoordinates then
                local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
                if point then
                    C_Map.SetUserWaypoint(point)
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
                    end
                end
            end
        elseif questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            C_SuperTrack.SetSuperTrackedQuestID(questID)
        end
        if showMap and mapID then ShowMap(mapID) end
    end)
end

openQuest = function(q)
    if not q then return end
    print(PREFIX .. "Waypoint set: |cffffd100" .. tostring(q.title) .. "|r")
    SetNativeWaypoint(q.mapID, q.x, q.y, q.id, true)
end

-- ── Shortest 2-Opt Route Calculation (Native + Optional TomTom) ─────────────

local function PDist(a, b)
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function TwoOpt(p)
    local n, guard, improved = #p, 0, true
    while improved and guard < 50 do
        improved, guard = false, guard + 1
        for i = 1, n - 1 do
            for j = i + 1, n do
                local a, b, c, d = p[i], p[i + 1], p[j], p[j + 1]
                local before = PDist(a, b) + (d and PDist(c, d) or 0)
                local after = PDist(a, c) + (d and PDist(b, d) or 0)
                if after + 1e-9 < before then
                    local lo, hi = i + 1, j
                    while lo < hi do
                        p[lo], p[hi] = p[hi], p[lo]
                        lo, hi = lo + 1, hi - 1
                    end
                    improved = true
                end
            end
        end
    end
end

local function BuildRoute()
    local byMap = {}
    for _, q in ipairs(available) do
        if q.x and q.y and q.mapID then
            byMap[q.mapID] = byMap[q.mapID] or {}
            table.insert(byMap[q.mapID], q)
        end
    end

    local maps, listed = {}, {}
    for _, m in ipairs(Data.ROUTE_ORDER or {}) do
        listed[m] = true
        if byMap[m] then maps[#maps + 1] = m end
    end
    for m in pairs(byMap) do
        if not listed[m] then maps[#maps + 1] = m end
    end

    local silvermoon = Data.SILVERMOON or 2393
    local function Centre(m)
        if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
        local cont, pos = C_Map.GetWorldPosFromMapPos(m, CreateVector2D(0.5, 0.5))
        if cont and pos then
            local x, y = pos:GetXY()
            return cont, x, y
        end
    end

    local idx = {}
    for i, m in ipairs(Data.ROUTE_ORDER or {}) do idx[m] = i end
    local hc, hx, hy = Centre(silvermoon)

    local function RouteKey(m)
        if m == silvermoon then return 0 end
        local c, x, y = Centre(m)
        if hc and c and c == hc and hx and hy and x and y then
            return 1 + math.sqrt((x - hx) ^ 2 + (y - hy) ^ 2)
        end
        return 1e9 + (idx[m] or 99)
    end
    table.sort(maps, function(a, b) return RouteKey(a) < RouteKey(b) end)

    local route = {}
    for _, m in ipairs(maps) do
        local remaining = {}
        for _, q in ipairs(byMap[m]) do remaining[#remaining + 1] = q end

        local path, virtual = {}, false
        local pos = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m, "player")
        if pos then
            local px, py = pos:GetXY()
            if px and py then
                path[1] = { x = px, y = py }
                virtual = true
            end
        end
        if not virtual then path[1] = table.remove(remaining, 1) end

        while #remaining > 0 do
            local last, bi, bd = path[#path], 1, math.huge
            for i, q in ipairs(remaining) do
                local d = PDist(last, q)
                if d < bd then bi, bd = i, d end
            end
            path[#path + 1] = table.remove(remaining, bi)
        end
        TwoOpt(path)

        for i, q in ipairs(path) do
            if not (virtual and i == 1) then route[#route + 1] = q end
        end
    end
    return route, maps
end

local function PointArrow(r)
    if r and r.uid and _G.TomTom and _G.TomTom.SetCrazyArrow then
        local arrival = (_G.TomTom.profile and _G.TomTom.profile.arrow and _G.TomTom.profile.arrow.arrival) or 10
        _G.TomTom:SetCrazyArrow(r.uid, arrival, r.title)
    end
end

-- ── World Map Route Pins ────────────────────────────────────────────────────

local function CreateRoutePin(index, q, isCurrent)
    local pin = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
    pin:SetSize(24, 24)
    pin:SetFrameStrata("FULLSCREEN_DIALOG")
    pin:SetFrameLevel(2000 + index)
    pin.mapID = q.mapID
    pin.normX = q.x
    pin.normY = q.y

    local bg = pin:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    pin.bg = bg

    local ring = pin:CreateTexture(nil, "BORDER")
    ring:SetPoint("TOPLEFT", -1, 1)
    ring:SetPoint("BOTTOMRIGHT", 1, -1)
    if isCurrent then
        ring:SetColorTexture(0, 1, 0, 0.9)
    else
        ring:SetColorTexture(1, 0.82, 0, 0.85)
    end
    pin.ring = ring

    local inner = pin:CreateTexture(nil, "ARTWORK")
    inner:SetPoint("TOPLEFT", 1, -1)
    inner:SetPoint("BOTTOMRIGHT", -1, 1)
    inner:SetColorTexture(0.12, 0.12, 0.12, 0.9)
    pin.inner = inner

    local num = pin:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    num:SetPoint("CENTER", 0, 0)
    if isCurrent then
        num:SetTextColor(0, 1, 0, 1)
    else
        num:SetTextColor(1, 0.82, 0, 1)
    end
    num:SetText(tostring(index))
    pin.num = num

    pin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(("#%d: %s"):format(index, q.title))
        GameTooltip:AddLine(MoneyString(q.copper), 1, 1, 1)
        GameTooltip:AddLine(q.zone, 0.7, 0.7, 0.7)
        if isCurrent then
            GameTooltip:AddLine("|cff00ff00[Current Stop]|r", 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return pin
end

local function PositionRoutePin(pin)
    if not pin or not WorldMapFrame:GetCanvas() then return end
    local mapID = WorldMapFrame:GetMapID()
    if mapID ~= pin.mapID then
        pin:Hide()
        return
    end
    local canvas = WorldMapFrame:GetCanvas()
    local w, h = canvas:GetSize()
    if w and h and w > 0 and h > 0 then
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.normX * w, -pin.normY * h)
        pin:Show()
    else
        pin:Hide()
    end
end

local function RefreshRoutePins()
    for _, pin in ipairs(routePins) do
        PositionRoutePin(pin)
    end
end

local function ClearRoutePins()
    for _, pin in ipairs(routePins) do
        pin:Hide()
        pin:SetParent(nil)
    end
    routePins = {}
end

local function CreateRoutePins(route, currentIdx)
    ClearRoutePins()
    if not WorldMapFrame or not WorldMapFrame:GetCanvas() then return end
    for i, q in ipairs(route) do
        if q.x and q.y and q.mapID then
            local pin = CreateRoutePin(i, q, i == (currentIdx or 1))
            routePins[#routePins + 1] = pin
            PositionRoutePin(pin)
        end
    end
end

local function UpdatePinHighlights(currentIdx)
    for i, pin in ipairs(routePins) do
        if i == currentIdx then
            pin.ring:SetColorTexture(0, 1, 0, 0.9)
            pin.num:SetTextColor(0, 1, 0, 1)
        else
            pin.ring:SetColorTexture(1, 0.82, 0, 0.85)
            pin.num:SetTextColor(1, 0.82, 0, 1)
        end
    end
end

-- Hook world map to reposition pins on map change
local mapHookInstalled = false
local function InstallMapHook()
    if mapHookInstalled or not WorldMapFrame then return end
    mapHookInstalled = true
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        RefreshRoutePins()
    end)
end

clearRoute = function(quiet)
    -- Remove TomTom waypoints if any exist
    if _G.TomTom and _G.TomTom.RemoveWaypoint then
        for _, r in ipairs(routeState) do
            if r.uid then pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, r.uid) end
        end
    end
    routeState = {}

    -- Clear map pins
    ClearRoutePins()

    -- Clear Blizzard native user waypoint
    if C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end

    local wasActive = (activeRoute ~= nil)
    activeRoute = nil

    if not quiet and wasActive then
        print(PREFIX .. "Route cleared.")
    end

    if updateRouteButtonText then updateRouteButtonText() end
    if refreshUI then refreshUI() end
end

local function ActivateRouteStop(index)
    if not activeRoute or not activeRoute.stops or not activeRoute.stops[index] then return end
    local q = activeRoute.stops[index]
    activeRoute.current = index

    -- Set native Blizzard waypoint & supertrack (no addons needed!)
    SetNativeWaypoint(q.mapID, q.x, q.y, q.id, false)

    -- Sync with TomTom arrow if TomTom is installed
    if #routeState > 0 and routeState[index] then
        PointArrow(routeState[index])
    end

    -- Update pin highlights
    UpdatePinHighlights(index)

    print(PREFIX .. ("Stop %d/%d: |cffffd100%s|r (%s) in %s. Waypoint set!"):format(
        index, #activeRoute.stops, q.title, MoneyString(q.copper), q.zone
    ))

    if updateRouteButtonText then updateRouteButtonText() end
    if refreshUI then refreshUI() end
end

sendRoute = function()
    local route, maps = BuildRoute()
    if #route == 0 then
        print(PREFIX .. "No gold world quests to route. Try clicking Rescan.")
        return
    end

    clearRoute(true)

    -- Register with TomTom if installed
    if _G.TomTom and _G.TomTom.AddWaypoint then
        for i, q in ipairs(route) do
            local title = ("%d. %s - %dg"):format(i, q.title, math.floor(q.copper / 10000))
            local uid = _G.TomTom:AddWaypoint(q.mapID, q.x, q.y, {
                title = title, persistent = false, minimap = true, world = true, from = "OxedHub_GoldWQ",
            })
            routeState[#routeState + 1] = { q = q, uid = uid, title = title }
        end
    end

    activeRoute = { stops = route, current = 1, maps = maps }

    -- Create numbered map pins
    InstallMapHook()
    CreateRoutePins(route, 1)

    local names = {}
    for _, m in ipairs(maps) do
        local mi = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        names[#names + 1] = (mi and mi.name) or tostring(m)
    end

    local provider = (_G.TomTom and _G.TomTom.AddWaypoint) and "Native Waypoint + TomTom" or "Native Waypoint"
    print(PREFIX .. ("Shortest route calculated: %d stops (%s)."):format(#route, provider))
    print(PREFIX .. "Zone order: " .. table.concat(names, " > "))

    ActivateRouteStop(1)
end

local function AdvanceRoute(questID)
    if not activeRoute or not activeRoute.stops then
        if #routeState > 0 and _G.TomTom then
            for i, r in ipairs(routeState) do
                if r.q and r.q.id == questID then
                    if r.uid and _G.TomTom.RemoveWaypoint then pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, r.uid) end
                    table.remove(routeState, i)
                    if routeState[1] then PointArrow(routeState[1]) end
                    return
                end
            end
        end
        return
    end

    local foundIdx = nil
    for idx, q in ipairs(activeRoute.stops) do
        if q.id == questID then
            foundIdx = idx
            break
        end
    end

    if not foundIdx then return end

    if #routeState >= foundIdx and routeState[foundIdx] and _G.TomTom and _G.TomTom.RemoveWaypoint then
        if routeState[foundIdx].uid then
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, routeState[foundIdx].uid)
        end
        table.remove(routeState, foundIdx)
    end

    table.remove(activeRoute.stops, foundIdx)

    if #activeRoute.stops == 0 then
        print(PREFIX .. "|cff00ff00Route complete! All gold world quests finished.|r")
        clearRoute(true)
    else
        local nextIdx = math.min(activeRoute.current, #activeRoute.stops)
        ActivateRouteStop(nextIdx)
    end
end

SkipRouteStop = function()
    if not activeRoute or not activeRoute.stops or #activeRoute.stops == 0 then
        print(PREFIX .. "No active route running.")
        return
    end
    print(PREFIX .. "Skipping current route stop...")
    table.remove(activeRoute.stops, activeRoute.current)
    if #routeState >= activeRoute.current then
        if routeState[activeRoute.current].uid and _G.TomTom and _G.TomTom.RemoveWaypoint then
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, routeState[activeRoute.current].uid)
        end
        table.remove(routeState, activeRoute.current)
    end
    if #activeRoute.stops == 0 then
        print(PREFIX .. "Route finished.")
        clearRoute(true)
    else
        local nextIdx = math.min(activeRoute.current, #activeRoute.stops)
        ActivateRouteStop(nextIdx)
    end
end

-- ── Special Assignments State ───────────────────────────────────────────────

local function SpecialAssignmentState(sa)
    local timeLeft = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftSeconds or function() return nil end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(sa.quest) then
        return "done"
    end

    local questLive = (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(sa.quest))
        or (C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(sa.quest))
        or (timeLeft(sa.quest) ~= nil)
    local unlocked = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(sa.unlock)) or questLive

    local thisWeek = (C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(sa.unlock))
        or (timeLeft(sa.unlock) ~= nil)
        or unlocked

    if not thisWeek then return "none" end
    local state = unlocked and "up" or "locked"

    local mapID
    for _, z in ipairs(Data.ZONES or {}) do
        if z[2] == sa.zone then mapID = z[1] end
    end
    local e = {
        id = sa.quest, title = "Special Assignment: " .. sa.name, zone = sa.zone, mapID = mapID,
        left = timeLeft(sa.quest) or timeLeft(sa.unlock)
    }
    if mapID and C_TaskQuest and C_TaskQuest.GetQuestLocation then
        local x, y = C_TaskQuest.GetQuestLocation(sa.unlock, mapID)
        if not x then x, y = C_TaskQuest.GetQuestLocation(sa.quest, mapID) end
        e.x, e.y = x, y
    end
    return state, e
end

-- ── HUD Window UI & Styling ──────────────────────────────────────────────────

local function ApplyRedButtonStyle(button)
    if not button then return end
    if button.Left then button.Left:SetVertexColor(1, 1, 1, 1) end
    if button.Middle then button.Middle:SetVertexColor(1, 1, 1, 1) end
    if button.Right then button.Right:SetVertexColor(1, 1, 1, 1) end
    if button.Text then button.Text:SetTextColor(1, 0.82, 0, 1) end
    button:HookScript("OnEnter", function()
        if button.Text then button.Text:SetTextColor(1, 1, 1, 1) end
    end)
    button:HookScript("OnLeave", function()
        if button.Text then button.Text:SetTextColor(1, 0.82, 0, 1) end
    end)
end

local function ApplyTrackerBackdrop(frame, alpha, noBorder)
    -- Native BasicFrameTemplate handles grey stone background and border automatically
end

local function UpdateFrameBorders(frame, noBorder)
    -- Native BasicFrameTemplate NineSlice stone border
end

local function StyleScroll(scrollFrame)
    if not scrollFrame then return end
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll and OxedHub.UIComponents.Scroll.StyleFrame then
        OxedHub.UIComponents.Scroll.StyleFrame(scrollFrame)
    end
end

local function GetRow(i)
    local r = rows[i]
    if not r then
        r = CreateFrame("Button", nil, content)
        r:SetHeight(ROW_H)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        r:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", 4, 0)
        r.text:SetPoint("RIGHT", -4, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 0.82, 0, 0.12)
        r.hl:Hide()
        r:SetScript("OnEnter", function(self) if self.clickable then self.hl:Show() end end)
        r:SetScript("OnLeave", function(self) self.hl:Hide() end)
        rows[i] = r
    end
    return r
end

refreshUI = function()
    if not ui or not ui:IsShown() or not settings then return end
    local n = 0
    local function AddRow(text, onclick)
        n = n + 1
        local r = GetRow(n)
        r.text:SetText(text)
        r:SetScript("OnClick", onclick)
        r.clickable = (onclick ~= nil)
        r.hl:Hide()
        r:Show()
    end

    -- 1. Gold World Quests grouped by zone
    local totalGold = 0
    local groups, zoneTotal, zoneNames = {}, {}, {}
    for _, q in ipairs(available) do
        totalGold = totalGold + q.copper
        if not groups[q.zone] then
            groups[q.zone] = {}
            zoneTotal[q.zone] = 0
            zoneNames[#zoneNames + 1] = q.zone
        end
        table.insert(groups[q.zone], q)
        zoneTotal[q.zone] = zoneTotal[q.zone] + q.copper
    end
    table.sort(zoneNames, function(x, y) return zoneTotal[x] > zoneTotal[y] end)

    AddRow(("|cffffd100Gold World Quests: %d (%s)|r"):format(#available, MoneyString(totalGold)))
    if #available == 0 then
        AddRow("  |cff999999No gold world quests found. Click Rescan.|r")
    end
    for _, zone in ipairs(zoneNames) do
        AddRow(("  |cffffffff%s|r |cff999999(%d, %s)|r"):format(zone, #groups[zone], MoneyString(zoneTotal[zone])))
        for _, q in ipairs(groups[zone]) do
            local prefixTag = ""
            if activeRoute and activeRoute.stops then
                for sIdx, stop in ipairs(activeRoute.stops) do
                    if stop.id == q.id then
                        if sIdx == activeRoute.current then
                            prefixTag = "|cff00ff00[Next] |r"
                        else
                            prefixTag = ("|cffffd100[#%d] |r"):format(sIdx)
                        end
                        break
                    end
                end
            end
            AddRow(("      %s%s  %s |cff999999%s|r"):format(prefixTag, MoneyString(q.copper), q.title, FormatTimeLeft(q.left)), function()
                openQuest(q)
            end)
        end
    end

    -- 2. Special Assignments
    AddRow(" ")
    AddRow("|cffffd100Special Assignments|r")
    local rank = { done = 3, up = 2, locked = 1 }
    local best = {}
    for _, sa in ipairs(Data.SpecialAssignments or {}) do
        local state, e = SpecialAssignmentState(sa)
        if rank[state] and (not best[sa.zone] or rank[state] > best[sa.zone].rank) then
            best[sa.zone] = { rank = rank[state], sa = sa, state = state, e = e }
        end
    end
    for _, sa in ipairs(Data.SpecialAssignments or {}) do
        local b = best[sa.zone]
        local state, e = "none", nil
        if b and b.sa == sa then state, e = b.state, b.e end
        local label = ("%s |cff999999[%s]|r"):format(sa.name, sa.zone)
        if state == "done" then
            AddRow("  |cff00ff00done|r    " .. label)
        elseif state == "up" then
            AddRow("  |cffffd100UP|r      " .. label .. " |cff999999" .. FormatTimeLeft(e and e.left) .. "|r", function() openQuest(e) end)
        elseif state == "locked" then
            AddRow("  |cffff9900locked|r  " .. label .. " |cff999999" .. FormatTimeLeft(e and e.left) .. "|r", function() openQuest(e) end)
        end
    end

    -- Unlocked assignment progress (3 per zone)
    local function NormName(name)
        name = (name or ""):lower():gsub("^the ", "")
        return (name:gsub("[^%w]", ""))
    end
    local cc = CurrentChar()
    local counts = {}
    for _, zone in pairs((cc and cc.wqDone) or {}) do
        local k = NormName(zone)
        counts[k] = (counts[k] or 0) + 1
    end

    local headerShown = false
    for _, sa in ipairs(Data.SpecialAssignments or {}) do
        local b = best[sa.zone]
        if b and b.sa == sa and (b.state == "locked" or b.state == "up") then
            if not headerShown then
                AddRow("  |cff999999WQ progress toward unlock (3 in zone):|r")
                headerShown = true
            end
            local nDone = counts[NormName(sa.zone)] or 0
            if nDone >= 3 then
                AddRow("    " .. sa.zone .. "  |cff00ff003/3 — unlocked|r")
            else
                AddRow("    " .. sa.zone .. "  " .. nDone .. "/3")
            end
        end
    end

    -- 3. Weekly Caches
    AddRow(" ")
    AddRow("|cffffd100Weekly Caches|r")
    local apexDone = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(93744)
    AddRow(("   |cff999999Unity Against the Void: %s|r"):format(apexDone and "|cff00ff00done|r" or "|cffff6060not done|r"))

    for _, cache in ipairs(TrackedCaches()) do
        local doneCount = ((cc and cc.caches) or {})[cache.name] or 0
        local extra = ""
        if #cache.quests > 1 then
            local names = {}
            if doneCount > 0 then
                for _, id in ipairs(cache.quests) do
                    if cc.turnedIn[id] then names[#names + 1] = cc.turnedIn[id] end
                end
                if #names == 0 then names[1] = "done" end
            else
                for _, id in ipairs(cache.quests) do
                    if C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then
                        names[1] = QuestTitle(id)
                        break
                    end
                end
            end
            if #names > 0 then extra = " |cff999999- " .. table.concat(names, ", ") .. "|r" end
        end

        if doneCount > 0 then
            AddRow("   |cff00ff00done|r    " .. cache.name .. extra)
        else
            local fresh = cc and cc.trackingSince and (time() - cc.trackingSince) < 6 * 86400
            AddRow("   |cffff6060to do|r   " .. cache.name .. (fresh and " |cff999999(fresh tracking)|r" or extra))
        end
    end

    for i = n + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(n * ROW_H, 1))
end

local function SaveUI()
    if not ui or not settings then return end
    if not settings.collapsed then ui.fullHeight = ui:GetHeight() end
    local point, _, relPoint, x, y = ui:GetPoint()
    settings.ui = {
        point = point, relPoint = relPoint, x = x, y = y,
        w = ui:GetWidth(), h = ui.fullHeight or ui:GetHeight()
    }
end

buildUI = function()
    if ui then return end
    EnsureData()
    local saved = (settings and settings.ui) or {}
    local minW = 400
    local curW = math.max(tonumber(saved.w) or minW, minW)
    local curH = math.max(tonumber(saved.h) or 420, 200)
    local ok, frame = pcall(CreateFrame, "Frame", "OxedHubGoldWQFrame", UIParent, "BasicFrameTemplate")
    if not ok or not frame then
        frame = CreateFrame("Frame", "OxedHubGoldWQFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    ui = frame
    ui:SetSize(curW, curH)
    ui:SetScale(tonumber(settings and settings.scale) or 1)
    ui:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or 150, saved.y or 0)
    ui:SetFrameStrata("MEDIUM")
    ui:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "OxedHubGoldWQFrame")

    -- Draggable & Resizable
    ui:SetMovable(true)
    ui:EnableMouse(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", function() ui:StopMovingOrSizing(); SaveUI() end)
    ui:SetResizable(true)
    if ui.SetResizeBounds then ui:SetResizeBounds(380, 200, 750, 1000) end

    -- Native Close Button
    if ui.CloseButton then
        ui.CloseButton:SetScript("OnClick", function() ui:Hide() end)
    end

    -- Hide native title — the content area already shows "Gold World Quests: N (gold)"
    if ui.TitleText then ui.TitleText:SetText("") end

    -- Collapse Button (in the title bar area)
    local cbtn = CreateFrame("Button", nil, ui)
    cbtn:SetSize(14, 14)
    cbtn:SetPoint("TOPLEFT", ui, "TOPLEFT", 10, -7)
    cbtn.t = cbtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbtn.t:SetPoint("CENTER", 0, 0)
    cbtn.t:SetTextColor(0.85, 0.85, 0.85, 1)
    cbtn.t:SetText("-")
    cbtn:SetScript("OnEnter", function() cbtn.t:SetTextColor(1, 1, 1, 1) end)
    cbtn:SetScript("OnLeave", function() cbtn.t:SetTextColor(0.85, 0.85, 0.85, 1) end)

    -- Header action buttons in classic red with gold text (matching OxedHub style)
    local rescan = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    rescan:SetSize(56, 18)
    if ui.CloseButton then
        rescan:SetPoint("RIGHT", ui.CloseButton, "LEFT", 2, 0)
    else
        rescan:SetPoint("TOPRIGHT", ui, "TOPRIGHT", -32, -6)
    end
    rescan:SetText("Rescan")
    ApplyRedButtonStyle(rescan)
    rescan:SetScript("OnClick", function() requestScan(0) end)

    local routeBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    routeBtn:SetSize(58, 18)
    routeBtn:SetPoint("RIGHT", rescan, "LEFT", -3, 0)
    routeBtn:SetText("Route")
    ApplyRedButtonStyle(routeBtn)
    routeBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    routeBtn:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if activeRoute then
                clearRoute()
            end
        else
            if IsShiftKeyDown() then
                SkipRouteStop()
            elseif activeRoute and activeRoute.stops and #activeRoute.stops > 0 then
                ActivateRouteStop(activeRoute.current or 1)
            else
                sendRoute()
            end
        end
    end)
    routeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Shortest Route (2-Opt)")
        GameTooltip:AddLine("Calculates the optimal shortest path through all active gold world quests.", 1, 1, 1, true)
        GameTooltip:AddLine(" ", 1, 1, 1)
        if activeRoute and activeRoute.stops and #activeRoute.stops > 0 then
            GameTooltip:AddLine(("|cffffd100Left-click:|r Re-point waypoint to stop %d/%d"):format(activeRoute.current or 1, #activeRoute.stops), 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cffffd100Shift + Left-click:|r Skip current stop", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cffffd100Right-click:|r Clear active route", 0.9, 0.9, 0.9)
        else
            GameTooltip:AddLine("|cffffd100Left-click:|r Calculate & start shortest route", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("|cff999999Works with native Blizzard waypoints (TomTom synced if installed).|r", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    routeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updateRouteButtonText = function()
        if not routeBtn then return end
        if activeRoute and activeRoute.stops and #activeRoute.stops > 0 then
            routeBtn:SetText(("%d/%d"):format(activeRoute.current or 1, #activeRoute.stops))
        else
            routeBtn:SetText("Route")
        end
    end
    updateRouteButtonText()

    local optBtn = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    optBtn:SetSize(52, 18)
    optBtn:SetPoint("RIGHT", routeBtn, "LEFT", -3, 0)
    optBtn:SetText("Config")
    ApplyRedButtonStyle(optBtn)
    optBtn:SetScript("OnClick", function() toggleOptions() end)

    -- Scroll Area (inside the stone border, below TitleBg)
    local scroll = CreateFrame("ScrollFrame", nil, ui)
    scroll:SetPoint("TOPLEFT", 14, -26)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(curW - 42, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxRange = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - delta * ROW_H * 3, 0), maxRange))
    end)
    StyleScroll(scroll)

    local grip = CreateFrame("Button", nil, ui)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() ui:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() ui:StopMovingOrSizing(); SaveUI() end)

    ui.fullHeight = curH

    local function ApplyCollapse()
        if settings and settings.collapsed then
            scroll:Hide()
            grip:Hide()
            ui:SetHeight(32)
            cbtn.t:SetText("+")
        else
            scroll:Show()
            grip:Show()
            ui:SetHeight(ui.fullHeight or 420)
            cbtn.t:SetText("-")
        end
    end

    ui.SetCollapsed = function(v)
        if v and not (settings and settings.collapsed) then ui.fullHeight = ui:GetHeight() end
        if settings then settings.collapsed = v and true or false end
        ApplyCollapse()
        SaveUI()
    end
    cbtn:SetScript("OnClick", function()
        ui.SetCollapsed(not (settings and settings.collapsed))
    end)
    ApplyCollapse()

    ui:SetScript("OnShow", function()
        SnapshotCaches()
        refreshUI()
        requestScan(0)
    end)

    ui:Hide()
end

toggleUI = function()
    if not ui then buildUI() end
    if ui:IsShown() then ui:Hide() else ui:Show() end
end

-- ── Minimap Button ──────────────────────────────────────────────────────────

local function MMTooltip(tt)
    tt:AddLine("|cffffd100Gold World Quests|r")
    tt:AddLine("Left-click: Show / hide tracker window", 1, 1, 1)
    tt:AddLine("Right-click: Open options window", 1, 1, 1)
    tt:AddLine("Drag: Move minimap icon", 1, 1, 1)
end

local function MMClick(_, button)
    if button == "RightButton" then toggleOptions() else toggleUI() end
end

local mmButton, dbicon

local function PlaceMinimapButton()
    if not mmButton then return end
    local angle = math.rad(settings.minimap.minimapPos or 220)
    local rw = Minimap:GetWidth() / 2 + 5
    local rh = Minimap:GetHeight() / 2 + 5
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        x = math.max(-rw, math.min(x * rw * 1.4142, rw))
        y = math.max(-rh, math.min(y * rh * 1.4142, rh))
    else
        x, y = x * rw, y * rh
    end
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    EnsureData()
    if not settings.minimap then settings.minimap = {} end

    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and DBIcon then
        local obj = LDB:NewDataObject("OxedHub_GoldWQ", {
            type = "launcher", label = "GoldWQ", icon = MM_ICON,
            OnClick = MMClick, OnTooltipShow = MMTooltip,
        }) or LDB:GetDataObjectByName("OxedHub_GoldWQ")
        DBIcon:Register("OxedHub_GoldWQ", obj, settings.minimap)
        dbicon = DBIcon
        if settings.minimap.hide or not settings.minimapButton then
            DBIcon:Hide("OxedHub_GoldWQ")
        end
        return
    end

    local b = CreateFrame("Button", "LibDBIcon10_OxedHub_GoldWQ", Minimap)
    mmButton = b
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetSize(31, 31)
    b:RegisterForClicks("anyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local overlay = b:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(MM_ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:SetPoint("TOPLEFT", 7, -6)
    b.icon = icon

    b:SetScript("OnClick", MMClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        MMTooltip(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            settings.minimap.minimapPos = math.deg(math.atan2(py - my, px - mx)) % 360
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    PlaceMinimapButton()
    b:SetShown(settings.minimapButton ~= false)
end

setMinimapShown = function(show)
    if dbicon then
        if show then dbicon:Show("OxedHub_GoldWQ") else dbicon:Hide("OxedHub_GoldWQ") end
    elseif mmButton then
        mmButton:SetShown(show)
    end
end

-- ── Options Dialog (OxedHub Standard) ───────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Gold World Quests", 440, 480)

        optionsWindow:AddCheckbox(settings, "announce", "Announce active quests on login",
            "Prints a summary of active gold world quests and total gold in chat when you log in.")
        optionsWindow:AddCheckbox(settings, "openOnLogin", "Open tracker HUD on login",
            "Automatically displays the tracker window upon entering the game.")
        optionsWindow:AddCheckbox(settings, "minimapButton", "Show minimap icon",
            "Displays a shortcut icon on the minimap.", function(val)
                setMinimapShown(val)
            end)

        optionsWindow:AddNote("|cffffd100Controls & Actions|r")

        -- Button: Open Tracker
        local btnOpen = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnOpen:SetSize(130, 22)
        btnOpen:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 6)
        btnOpen:SetText("Open Tracker")
        ApplyRedButtonStyle(btnOpen)
        btnOpen:SetScript("OnClick", function()
            optionsWindow:Hide()
            if not ui then buildUI() end
            ui:Show()
        end)

        -- Button: Shortest Route
        local btnRoute = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnRoute:SetSize(130, 22)
        btnRoute:SetPoint("LEFT", btnOpen, "RIGHT", 10, 0)
        btnRoute:SetText("Shortest Route")
        ApplyRedButtonStyle(btnRoute)
        btnRoute:SetScript("OnClick", function()
            sendRoute()
        end)

        -- Button: Reset Position
        local btnReset = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnReset:SetSize(130, 22)
        btnReset:SetPoint("LEFT", btnRoute, "RIGHT", 10, 0)
        btnReset:SetText("Reset Position")
        ApplyRedButtonStyle(btnReset)
        btnReset:SetScript("OnClick", function()
            settings.ui = nil
            if ui then
                ui:ClearAllPoints()
                ui:SetPoint("CENTER", UIParent, "CENTER", 150, 0)
                ui:SetSize(400, 420)
                ui:SetScale(1)
                ui.fullHeight = 420
                if ui.SetCollapsed then ui.SetCollapsed(false) end
            end
            print(PREFIX .. "Tracker HUD position reset to center.")
        end)

        optionsWindow.cursorY = optionsWindow.cursorY - 36

        optionsWindow:AddNote("|cffffd100Weekly Caches to Track|r  -- uncheck any caches you wish to ignore:")
        for _, cache in ipairs(Data.Caches or {}) do
            local cacheKey = cache.name
            local box = CreateFrame("CheckButton", nil, optionsWindow, "UICheckButtonTemplate")
            box:SetSize(22, 22)
            box:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY)
            box.text:SetFontObject("GameFontHighlightSmall")
            box.text:SetText(cacheKey)
            box:SetScript("OnClick", function(button)
                settings.disabledCaches[cacheKey] = (not button:GetChecked()) or nil
                if refreshUI then refreshUI() end
            end)
            box.Refresh = function()
                box:SetChecked(CacheEnabled(cacheKey))
            end
            table.insert(optionsWindow.checks, box)
            optionsWindow.cursorY = optionsWindow.cursorY - 24
        end

        optionsWindow:AddNote("Type /gwq to toggle the tracker, /gwq route for shortest route, or /gwq report for weekly summary.")
    end

    optionsWindow:Show()
end

toggleOptions = function()
    ShowOptions()
end

-- ── Chat Reports & Commands ─────────────────────────────────────────────────

local function ShowAvailableChat()
    if #available == 0 then
        print(PREFIX .. "No gold world quests found. Try /gwq scan in a moment.")
        return
    end
    print(PREFIX .. "Gold world quests available now:")
    for _, q in ipairs(available) do
        print(("  %s - %s [%s]"):format(MoneyString(q.copper), q.title, q.zone))
    end
end

local function PrintWeeklyReport()
    EnsureData()
    print(PREFIX .. "Weekly summary (resets at weekly reset):")
    for name, c in pairs(settings.chars or {}) do
        local count = 0
        for _ in pairs(c.weekQuests or {}) do count = count + 1 end
        print(("  |cffffffff%s|r: %d gold WQs, %s (lifetime %s)"):format(
            name, count, MoneyString(c.weekCopper), MoneyString(c.totalCopper)
        ))
        for _, cache in ipairs(Data.Caches or {}) do
            local done = (c.caches or {})[cache.name] or 0
            print(("     %s: %d/%d"):format(cache.name, done, #cache.quests))
        end
    end
end

-- ── Event Handling ──────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(self, event, ...)
    if not settings or settings.enabled == false then return end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        requestScan(2)
    elseif event == "QUEST_LOG_UPDATE" then
        if GetTime() - lastScanAt >= QUEST_LOG_GAP then requestScan(1) end
    elseif event == "QUEST_TURNED_IN" then
        local questID, _, money = ...
        if SecretValue(questID) then return end

        AdvanceRoute(questID)
        local c = CurrentChar()
        c.turnedIn[questID] = QuestTitle(questID)

        local isWQ = knownZone[questID] ~= nil or (C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID))
        if isWQ then
            c.wqDone[questID] = knownZone[questID] or ZoneName(questID, "Unknown zone")
        end

        if money and not SecretValue(money) and money > 0 and isWQ then
            if not c.weekQuests[questID] then
                c.weekQuests[questID] = money
                c.weekCopper = (c.weekCopper or 0) + money
                c.totalCopper = (c.totalCopper or 0) + money
                print(PREFIX .. "+" .. MoneyString(money))
            end
        end
        C_Timer.After(1, SnapshotCaches)
        requestScan(2)
    end
end)

-- ── Slash Commands ──────────────────────────────────────────────────────────

local function HandleSlash(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "list" then
        ShowAvailableChat()
    elseif msg == "scan" then
        shouldAnnounce = true
        requestScan(0)
    elseif msg == "report" then
        PrintWeeklyReport()
    elseif msg == "route" then
        sendRoute()
    elseif msg == "clearroute" or msg == "stop" then
        clearRoute()
    elseif msg == "next" or msg == "skip" then
        SkipRouteStop()
    elseif msg == "options" or msg == "config" then
        ShowOptions()
    elseif msg == "minimap" then
        settings.minimapButton = not (settings.minimapButton ~= false)
        setMinimapShown(settings.minimapButton)
        print(PREFIX .. "Minimap button " .. (settings.minimapButton and "shown." or "hidden."))
    elseif msg == "reset" then
        settings.ui = nil
        if ui then
            ui:ClearAllPoints()
            ui:SetPoint("CENTER", UIParent, "CENTER", 150, 0)
            ui:SetSize(360, 420)
            ui:SetScale(1)
            ui.fullHeight = 420
            if ui.SetCollapsed then ui.SetCollapsed(false) end
        end
        print(PREFIX .. "Window position reset.")
    else
        toggleUI()
    end
end

SLASH_OXEDGOLDWQ1 = "/gwq"
SLASH_OXEDGOLDWQ2 = "/oxgold"
SLASH_OXEDGOLDWQ3 = "/oxgwq"
SlashCmdList["OXEDGOLDWQ"] = HandleSlash

-- ── Registration ────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.goldwq
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.goldwq = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
    EnsureData()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    RollWeek()
    CurrentChar()
    SnapshotCaches()
    CreateMinimapButton()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "goldwq",
        name     = "Gold World Quests",
        version  = "1.0.0",
        author   = "Marcus / Oxed",
        category = "quests",
        keywords = { "gold", "wq", "world quest", "caches", "special assignment", "tomtom", "route" },
        -- Card desc clipped at ~100 chars; detail lives in Options
        desc     = "Tracks gold world quests, special assignments, and weekly caches in Midnight.",
        icon     = QUESTION_MARK,

        defaults = DEFAULTS,

        -- On the minimap button's right-click menu and as an Action Hub node.
        quick = {
            { text = "Show or hide", func = function() toggleUI() end },
        },

        OnOptionsShow = function()
            ShowOptions()
        end,

        OnEnable = function(_, config)
            settings = config
            EnsureData()
            RollWeek()
            CurrentChar()
            SnapshotCaches()

            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            watcher:RegisterEvent("QUEST_LOG_UPDATE")
            watcher:RegisterEvent("QUEST_TURNED_IN")

            if not ticker then
                ticker = C_Timer.NewTicker(60, function()
                    if not settings or settings.enabled == false then return end
                    local before = settings.resetAt
                    RollWeek()
                    if before and settings.resetAt ~= before and time() >= (before or 0) then
                        CurrentChar()
                        SnapshotCaches()
                        requestScan(2)
                        print(PREFIX .. "Weekly reset detected, weekly counters cleared.")
                    end
                end)
            end

            shouldAnnounce = settings.announce
            requestScan(3)

            if settings.openOnLogin then
                C_Timer.After(2, function()
                    if not ui then buildUI() end
                    ui:Show()
                end)
            end
        end,

        OnDisable = function()
            watcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
            watcher:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
            watcher:UnregisterEvent("QUEST_LOG_UPDATE")
            watcher:UnregisterEvent("QUEST_TURNED_IN")

            if ticker then
                ticker:Cancel()
                ticker = nil
            end

            clearRoute()

            if ui then ui:Hide() end
            if optionsWindow then optionsWindow:Hide() end
        end,
    })
end)
