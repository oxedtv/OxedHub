-- ============================================================================
-- Reputations (built-in OxedHub module)
-- Every reputation in one list, for the whole account: renown, friendships,
-- the old standings and paragon, grouped by expansion. Each character's
-- standings are remembered as it logs in, so any character can see which of
-- the others is furthest along with a faction that is not shared by the
-- warband. Says when a paragon cache is waiting, and can track the faction
-- you last earned reputation with.
--
-- ⚠ The game only lists the factions under headers the player has opened in
-- the reputation panel. To learn them all, every closed header is opened
-- once, the list read, and exactly those headers closed again -- the
-- player's panel looks as it did. After that each faction is read by its id,
-- which needs no header open. The opening is never done while the panel is
-- on screen, and the UPDATE_FACTION it causes is ignored.
--
-- ⚠ Reads are done out of combat only. Reputation figures can come back as
-- secret values in a fight, and comparing one is an error; a change seen in
-- combat is read when it ends.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,   -- off until the player switches it on
    minimapButton = true,  -- its own icon on the minimap while switched on

    hideFinished = false,   -- hide what cannot go further (paragon still shows)
    showOthers   = true,    -- the best of the other characters on each row
    paragonAlert = true,    -- a line in chat when a paragon cache is waiting
    paragonSound = "",      -- an OxedHub sound for it; empty plays nothing
    autoWatch    = false,   -- track the faction last gained on the XP bar

    point = "CENTER", x = 0, y = 40,

    -- "known", "chars", "account" and "collapsed" are tables and are built
    -- in BindSettings: a table in DEFAULTS is copied by reference and every
    -- character would share one.
}

local PREFIX = "|cff00ccffOxedHub Reputations:|r "

local settings
local optionsWindow
local window
local watcher = CreateFrame("Frame")
local running = false

local Draw   -- redraws the window when it is open; defined with the window
local MyRecord  -- this character's saved record; defined with the reading code

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Num(v)
    if type(v) ~= "number" or IsSecret(v) then return nil end
    return v
end

local function Str(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

local function Named(label, fn)
    return OxedHub.Profiler and OxedHub.Profiler:Wrap(label, fn) or fn
end

local function CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    return name .. "-" .. realm
end

local function ClassHex(class)
    local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return (colour and colour.colorStr) or "ffffffff"
end

-- ── Finding every faction ───────────────────────────────────────────────────

local discovering = false
local quietUntil = 0          -- UPDATE_FACTION before this is our own doing
local lastNumFactions = -1
local discoverOwed = true

local function PanelOpen()
    local panel = ReputationFrame
    return panel and panel.IsVisible and panel:IsVisible() or false
end

-- Opens every closed header, files each faction under its expansion, and
-- closes those same headers again. Also notes where each faction sits in the
-- full list, which is the order the window shows them in.
local function Discover()
    if not (C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex) then
        return
    end
    if PanelOpen() or InCombatLockdown() then
        discoverOwed = true
        return
    end
    discoverOwed = false
    discovering = true

    -- ⚠ Which factions this character has actually met: only those in its
    -- own list. Every faction any character knows used to be read for every
    -- character, and an alt that had never been near one showed a neutral
    -- zero for it -- in its own list, and as "best" when nobody else had it.
    local me = MyRecord()
    local has = {}

    local opened = {}
    local group
    local index, order = 1, 0
    -- The list grows as headers open; the guard only stops a client that
    -- never stops growing it.
    while index <= C_Reputation.GetNumFactions() and index < 3000 do
        local ok, data = pcall(C_Reputation.GetFactionDataByIndex, index)
        local id = ok and type(data) == "table" and Num(data.factionID)
        if id and id > 0 then
            if data.isHeader and not data.isChild then
                group = Str(data.name) or group
            end
            if data.isHeader and data.isCollapsed then
                if pcall(C_Reputation.ExpandFactionHeader, index) then opened[id] = true end
            end
            if not data.isHeader or data.isHeaderWithRep then
                local name = Str(data.name)
                if name then
                    order = order + 1
                    local known = settings.known[id]
                    if not known then
                        known = {}
                        settings.known[id] = known
                    end
                    known.n, known.g, known.o = name, group or known.g or L["Other"], order
                    known.a = data.isAccountWide and true or nil
                    has[id] = true
                end
            end
        end
        index = index + 1
    end

    -- Bottom to top, so closing one header does not move the ones above it.
    for i = C_Reputation.GetNumFactions(), 1, -1 do
        local ok, data = pcall(C_Reputation.GetFactionDataByIndex, i)
        if ok and type(data) == "table" and data.isHeader and not data.isCollapsed
            and opened[Num(data.factionID) or 0] then
            pcall(C_Reputation.CollapseFactionHeader, i)
        end
    end

    lastNumFactions = C_Reputation.GetNumFactions()
    if type(me) == "table" and next(has) then
        me.has = has
        -- Records left from before for factions this character has not met.
        if type(me.f) == "table" then
            for id in pairs(me.f) do
                if not has[id] then me.f[id] = nil end
            end
        end
    end
    discovering = false
    quietUntil = GetTime() + 0.5
end

-- ── Reading one faction ─────────────────────────────────────────────────────
-- Into a small record kept in saved variables, reused on every read:
--   l  what the standing is called ("Revered", "Renown 12", "Paragon")
--   c, m  progress within it, out of
--   v  a number that compares characters (higher is further along)
--   r  the standing (1-8) for an old-style faction, for its bar colour
--   k  "rep", "renown", "friend" or "paragon"
--   done  nothing further to earn;  p  a paragon cache is waiting

local STANDING_FALLBACK = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

local function StandingLabel(reaction)
    return _G["FACTION_STANDING_LABEL" .. reaction] or STANDING_FALLBACK[reaction] or (L["Rank "] .. reaction)
end

local function IsParagon(id)
    local ask = C_Reputation.IsFactionParagonForCurrentPlayer or C_Reputation.IsFactionParagon
    if not ask then return false end
    local ok, yes = pcall(ask, id)
    return ok and yes == true
end

local function Fill(id, e, kindHint)
    local ok, data = pcall(C_Reputation.GetFactionDataByID, id)
    if not ok or type(data) ~= "table" then return false end

    local kind = kindHint
    if not kind then
        local isMajor = C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(id)
        if isMajor then
            kind = "renown"
        else
            local friend = C_GossipInfo and C_GossipInfo.GetFriendshipReputation
                and C_GossipInfo.GetFriendshipReputation(id)
            kind = (friend and (Num(friend.friendshipFactionID) or 0) > 0) and "friend" or "rep"
        end
    end

    e.p, e.r = nil, nil
    if kind == "renown" and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local major = C_MajorFactions.GetMajorFactionData(id)
        local level = major and Num(major.renownLevel) or 0
        local maxed = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(id) or false
        e.k, e.l = "renown", (L["Renown %d"]):format(level)
        if maxed then
            e.c, e.m, e.done = 1, 1, true
        else
            e.c = major and Num(major.renownReputationEarned) or 0
            e.m = math.max(1, major and Num(major.renownLevelThreshold) or 1)
            e.done = nil
        end
        e.v = level * 100000 + (maxed and 99999 or e.c)
    elseif kind == "friend" then
        local friend = C_GossipInfo.GetFriendshipReputation(id)
        local standing = friend and Num(friend.standing) or 0
        local low = friend and Num(friend.reactionThreshold) or 0
        local nextAt = friend and Num(friend.nextThreshold)
        e.k, e.l = "friend", (friend and Str(friend.reaction)) or L["Friend"]
        if nextAt and nextAt > low then
            e.c, e.m, e.done = standing - low, nextAt - low, nil
        else
            e.c, e.m, e.done = 1, 1, true
        end
        e.v = standing
    else
        kind = "rep"
        local reaction = Num(data.reaction) or 4
        local standing = Num(data.currentStanding) or 0
        local low, high = Num(data.currentReactionThreshold) or 0, Num(data.nextReactionThreshold) or 0
        e.k, e.r, e.l = "rep", reaction, StandingLabel(reaction)
        if high > low and reaction < 8 then
            e.c, e.m, e.done = standing - low, high - low, nil
        else
            e.c, e.m, e.done = 1, 1, true
        end
        e.v = standing
    end

    -- Paragon: what is earned past the top, a cache at every threshold.
    if (e.done or kind == "renown") and IsParagon(id) and C_Reputation.GetFactionParagonInfo then
        local okP, value, threshold, _, pending = pcall(C_Reputation.GetFactionParagonInfo, id)
        value, threshold = okP and Num(value), okP and Num(threshold)
        if value and threshold and threshold > 0 then
            local caches = math.floor(value / threshold)
            if pending == true then caches = math.max(0, caches - 1) end
            e.k, e.done = "paragon", nil
            e.l = caches > 0 and (L["Paragon x%d"]):format(caches) or L["Paragon"]
            e.c, e.m = value % threshold, threshold
            if pending == true then e.c = threshold end
            e.p = pending == true or nil
            e.v = (e.v or 0) + 10000000 + value
        end
    end
    return true, kind
end

-- ── Reading them all ────────────────────────────────────────────────────────

local primed = false          -- the first read of a session sets the baseline
local announced = {}          -- faction id -> true, paragon caches already named

MyRecord = function()
    local key = CharKey()
    local me = settings.chars[key]
    if type(me) ~= "table" then
        me = {}
        settings.chars[key] = me
    end
    if type(me.f) ~= "table" then me.f = {} end
    local _, class = UnitClass("player")
    me.class, me.name, me.seen = class, UnitName("player"), time()
    return me
end

local function StoreFor(known, me)
    return known.a and settings.account or me.f
end

local function SoundAlert()
    local id = settings.paragonSound
    local API = OxedHub.ModuleAPI
    if id and id ~= "" and API and API.PlaySound then API:PlaySound(id) end
end

local function TrackFaction(id)
    if InCombatLockdown() or not id then return end
    if C_Reputation.SetWatchedFactionByID then
        pcall(C_Reputation.SetWatchedFactionByID, id)
    end
end

local readyNames = {}
local Scan = Named("Reputations: read every faction", function()
    if not settings or not C_Reputation or not C_Reputation.GetFactionDataByID then return end
    local me = MyRecord()

    wipe(readyNames)
    local gainedID, gainedBy = nil, 0
    local has = me.has
    for id, known in pairs(settings.known) do
      -- Only what this character has met (see Discover); warband factions
      -- are shared and always read. Before the first Discover there is no
      -- list yet, and everything is read as before.
      if known.a or not has or has[id] then
        local store = StoreFor(known, me)
        local e = store[id]
        if type(e) ~= "table" then
            e = {}
            store[id] = e
        end
        local before, wasReady = e.v, e.p
        local ok, kind = Fill(id, e, known.k)
        if ok then
            -- The kind never changes; asking for it every read was two more
            -- tables from the game per faction.
            known.k = kind
            if primed and before and e.v and e.v > before and (e.v - before) > gainedBy then
                gainedID, gainedBy = id, e.v - before
            end
            if e.p and not announced[id] then
                announced[id] = true
                if not wasReady or not primed then readyNames[#readyNames + 1] = known.n end
            elseif not e.p then
                announced[id] = nil
            end
        end
      end
    end

    if settings.paragonAlert and #readyNames > 0 then
        table.sort(readyNames)
        print(PREFIX .. L["a paragon cache is waiting: |cffffd100"] .. table.concat(readyNames, ", ") .. "|r")
        SoundAlert()
    end

    if gainedID and settings.autoWatch then TrackFaction(gainedID) end
    primed = true
    if Draw then Draw() end
end)

local scanQueued, scanOwed = false, false
local function RunScan()
    scanQueued = false
    if not running then return end
    if InCombatLockdown() then
        scanOwed = true
        return
    end
    if discoverOwed then Discover() end
    Scan()
end

-- At most one read a second: UPDATE_FACTION comes in streams while questing.
local function QueueScan(delay)
    if scanQueued or not running then return end
    scanQueued = true
    C_Timer.After(delay or 1, RunScan)
end

-- ── The window ──────────────────────────────────────────────────────────────

local W, H = 660, 540
local ROW_H = 22
local LIST_TOP = 84
local NAME_W = 210
local OTHER_W = 150

local BAR_RENOWN = { 0.00, 0.60, 1.00 }
local BAR_FRIEND = { 0.20, 0.80, 0.30 }
local BAR_PARAGON = { 0.75, 0.45, 1.00 }
local BAR_DONE = { 0.85, 0.70, 0.20 }

local function BarColour(e)
    if e.k == "paragon" then return BAR_PARAGON end
    if e.done then return BAR_DONE end
    if e.k == "renown" then return BAR_RENOWN end
    if e.k == "friend" then return BAR_FRIEND end
    local c = FACTION_BAR_COLORS and FACTION_BAR_COLORS[e.r or 4]
    if c then return { c.r, c.g, c.b } end
    return BAR_FRIEND
end

local function ProgressText(e)
    if e.done then return e.l or "" end
    if e.p then return (e.l or "") .. L["  |cff40ff40cache ready|r"] end
    local short = BreakUpLargeNumbers or tostring
    return ("%s  %s / %s"):format(e.l or "", short(e.c or 0), short(e.m or 0))
end

-- The best record among the other characters, for a faction not shared by
-- the warband.
local function BestOther(id, myKey)
    local best, bestChar
    for key, char in pairs(settings.chars) do
        if key ~= myKey and type(char) == "table" and type(char.f) == "table" then
            local e = char.f[id]
            if type(e) == "table" and e.v and (not best or e.v > best.v) then
                best, bestChar = e, char
            end
        end
    end
    return best, bestChar
end

local entries = {}        -- what the list shows now, headers and factions
local entryPool = {}
local offset = 0
local rows = {}
local visibleRows = 0

local function Entry()
    local e = table.remove(entryPool) or {}
    entries[#entries + 1] = e
    return e
end

-- Whose list the window shows: nil for the character logged in, or the key
-- of another one, read from what it saved when it last logged in.
local viewKey = nil

local function ViewRecord()
    local char = viewKey and settings.chars[viewKey]
    if type(char) == "table" and type(char.f) == "table" then return char, viewKey end
    viewKey = nil
    return MyRecord(), CharKey()
end

-- Every saved character, this one first, then by name.
local function CharacterList()
    local me = CharKey()
    local list = {}
    for key, char in pairs(settings.chars) do
        if type(char) == "table" and type(char.f) == "table" then list[#list + 1] = key end
    end
    table.sort(list, function(a, b)
        if a == me then return true end
        if b == me then return false end
        return a < b
    end)
    return list
end

local function Ago(seen)
    if not seen then return "never" end
    local s = math.max(0, time() - seen)
    if s < 3600 then return L["just now"] end
    if s < 86400 then return (L["%d h ago"]):format(math.floor(s / 3600)) end
    return (L["%d days ago"]):format(math.floor(s / 86400))
end

local function Gather()
    for i = #entries, 1, -1 do
        local e = entries[i]
        entries[i] = nil
        wipe(e)
        entryPool[#entryPool + 1] = e
    end
    if not settings then return 0, 0, 0 end

    local me = ViewRecord()
    local query = window and window.search and window.search:GetText() or ""
    query = query:lower()
    if query == (SEARCH or "search"):lower() then query = "" end

    local ids = {}
    for id in pairs(settings.known) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        return (settings.known[a].o or 9999) < (settings.known[b].o or 9999)
    end)

    local total, finished, ready = 0, 0, 0
    local header
    for _, id in ipairs(ids) do
        local known = settings.known[id]
        local e = StoreFor(known, me)[id]
        if type(e) == "table" then
            total = total + 1
            if e.done then finished = finished + 1 end
            if e.p then ready = ready + 1 end

            local show = true
            if settings.hideFinished and e.done then show = false end
            if show and query ~= "" then
                show = (known.n or ""):lower():find(query, 1, true) ~= nil
            end
            if show then
                if not header or header.group ~= known.g then
                    header = Entry()
                    header.isHeader, header.group, header.count, header.doneCount = true, known.g, 0, 0
                end
                header.count = header.count + 1
                if e.done then header.doneCount = header.doneCount + 1 end
                if not settings.collapsed[known.g] or query ~= "" then
                    local row = Entry()
                    row.id, row.known, row.rec = id, known, e
                end
            end
        end
    end
    return total, finished, ready
end

local function RowTooltip(row)
    local entry = row.entry
    if not entry or entry.isHeader then return end
    local known, e = entry.known, entry.rec
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(known.n or "?", 1, 0.82, 0)
    local ok, data = pcall(C_Reputation.GetFactionDataByID, entry.id)
    local desc = ok and type(data) == "table" and Str(data.description)
    if desc then GameTooltip:AddLine(desc, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(" ")
    if known.a then
        GameTooltip:AddLine(L["Shared by the warband"], 0.4, 0.8, 1)
        GameTooltip:AddDoubleLine(L["Standing"], ProgressText(e), 1, 1, 1, 1, 1, 1)
    else
        -- Every character that has been seen with it, furthest first.
        local list = {}
        for _, char in pairs(settings.chars) do
            local rec = type(char) == "table" and type(char.f) == "table" and char.f[entry.id]
            if type(rec) == "table" and rec.v then list[#list + 1] = { char = char, rec = rec } end
        end
        table.sort(list, function(a, b) return a.rec.v > b.rec.v end)
        for i, item in ipairs(list) do
            if i > 15 then break end
            GameTooltip:AddDoubleLine(("|c%s%s|r"):format(ClassHex(item.char.class), item.char.name or "?"),
                ProgressText(item.rec), 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    if not known.a then
        GameTooltip:AddLine(L["Click: every character's bar for it."], 0.5, 0.8, 1)
    end
    GameTooltip:AddLine(L["Right-click: track it on the experience bar."], 0.5, 0.8, 1)
    GameTooltip:Show()
end

-- ── One faction across every character ──────────────────────────────────────
-- A panel beside the list: each character that has met the faction, with its
-- bar, furthest first. Clicking a name shows that character's whole list.

local altPanel
local altRows = {}
local ALT_W, ALT_ROW = 300, 20
local ALT_MAX = 24

local function BuildAltPanel()
    if altPanel then return altPanel end
    local p = CreateFrame("Frame", nil, window, "BackdropTemplate")
    p:SetWidth(ALT_W)
    p:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
    p:EnableMouse(true)
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(p, " ", 0.96)
    end
    local okClose, close = pcall(CreateFrame, "Button", nil, p, "UIPanelCloseButton")
    if okClose and close then close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -3, -3) end

    p.head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.head:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -30)
    p.head:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -30)
    p.head:SetJustifyH("LEFT")
    p.head:SetWordWrap(false)

    p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -3)
    p.sub:SetJustifyH("LEFT")
    p:Hide()
    altPanel = p
    return p
end

local function AltRow(p, i)
    local row = altRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, p)
    row:SetHeight(ALT_ROW)
    row:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -64 - (i - 1) * ALT_ROW)
    row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -64 - (i - 1) * ALT_ROW)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.name:SetWidth(100)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", row, "LEFT", 106, 0)
    bar:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    bar:SetHeight(ALT_ROW - 5)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:EnableMouse(false)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar.text:SetShadowOffset(1, -1)
    row.bar = bar

    row:SetScript("OnClick", function(self)
        if not self.key then return end
        viewKey = (self.key ~= CharKey()) and self.key or nil
        offset = 0
        Draw()
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.key or "?")
        GameTooltip:AddLine(L["Saved "] .. Ago(self.seen), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Click to see this character's whole list."], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    altRows[i] = row
    return row
end

local altFor = nil   -- the faction the panel shows
local function ShowAlts(id)
    if not (window and settings and settings.known[id]) then return end
    local p = BuildAltPanel()
    if altFor == id and p:IsShown() then
        p:Hide()
        altFor = nil
        return
    end
    altFor = id
    local known = settings.known[id]

    local list = {}
    for key, char in pairs(settings.chars) do
        local rec = type(char) == "table" and type(char.f) == "table" and char.f[id]
        if type(rec) == "table" and rec.v then list[#list + 1] = { key = key, char = char, rec = rec } end
    end
    table.sort(list, function(a, b) return a.rec.v > b.rec.v end)

    p.head:SetText(known.n or "?")
    local total = 0
    for _ in pairs(settings.chars) do total = total + 1 end
    p.sub:SetFormattedText(L["%d of %d characters have met it"], #list, total)

    local shown = math.min(#list, ALT_MAX)
    for i = 1, shown do
        local item = list[i]
        local row = AltRow(p, i)
        row.key, row.seen = item.key, item.char.seen
        row.name:SetFormattedText("|c%s%s|r", ClassHex(item.char.class), item.char.name or "?")
        local colour = BarColour(item.rec)
        row.bar:SetStatusBarColor(colour[1], colour[2], colour[3], 0.9)
        row.bar:SetValue((item.rec.m and item.rec.m > 0) and math.min(1, (item.rec.c or 0) / item.rec.m) or 0)
        row.bar.text:SetText(ProgressText(item.rec))
        row:Show()
    end
    for i = shown + 1, #altRows do altRows[i]:Hide() end
    p:SetHeight(64 + math.max(1, shown) * ALT_ROW + 16)
    p:Show()
end

local function CreateRow(list, index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)

    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.toggle:SetWidth(14)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 18, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetPoint("LEFT", row, "LEFT", 22 + NAME_W, 0)
    bar:SetPoint("RIGHT", row, "RIGHT", -(OTHER_W + 8), 0)
    bar:SetHeight(ROW_H - 6)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:EnableMouse(false)
    local barBg = bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.55)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetShadowOffset(1, -1)
    row.bar = bar

    row.other = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.other:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.other:SetWidth(OTHER_W)
    row.other:SetJustifyH("RIGHT")
    row.other:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouse)
        local entry = self.entry
        if not entry then return end
        if entry.isHeader then
            settings.collapsed[entry.group] = not settings.collapsed[entry.group] or nil
            Draw()
        elseif mouse == "RightButton" or entry.known.a then
            -- A warband faction is the same for everyone: nothing to compare.
            TrackFaction(entry.id)
        else
            ShowAlts(entry.id)
        end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function PaintRow(row, entry, myKey)
    row.entry = entry
    if entry.isHeader then
        row.toggle:SetText(settings.collapsed[entry.group] and "+" or "-")
        row.toggle:Show()
        row.name:SetFontObject("GameFontNormal")
        row.name:SetText(entry.group or "")
        row.bar:Hide()
        row.other:SetFormattedText(L["|cff9d9d9d%d / %d finished|r"], entry.doneCount or 0, entry.count or 0)
        return
    end

    local e, known = entry.rec, entry.known
    row.toggle:Hide()
    row.name:SetFontObject("GameFontHighlightSmall")
    row.name:SetText(known.n or "?")

    local colour = BarColour(e)
    row.bar:SetStatusBarColor(colour[1], colour[2], colour[3], 0.9)
    row.bar:SetValue((e.m and e.m > 0) and math.min(1, (e.c or 0) / e.m) or 0)
    row.bar.text:SetText(ProgressText(e))
    row.bar:Show()

    local otherText = ""
    if settings.showOthers then
        if known.a then
            otherText = "|cff66ccffwarband|r"
        else
            local best, char = BestOther(entry.id, myKey)
            if best and (not e.v or best.v > e.v) then
                otherText = ("|c%s%s|r |cff9d9d9d%s|r"):format(ClassHex(char.class), char.name or "?", best.l or "")
            end
        end
    end
    row.other:SetText(otherText)
end

Draw = function()
    if not (window and window:IsShown()) then return end
    local total, finished, ready = Gather()
    local viewed, myKey = ViewRecord()

    window.summary:SetFormattedText(L["%d reputations   |cffffd100%d|r finished%s%s"], total, finished,
        ready > 0 and (L["   |cffb380ff%d paragon %s ready|r"]):format(ready, ready == 1 and "cache" or "caches") or "",
        viewKey and ("   |cffff9933saved %s|r"):format(Ago(viewed.seen)) or "")
    if window.fold then window.fold.Refresh() end
    if window.picker then
        window.picker:SetText(("|c%s%s|r"):format(ClassHex(viewed.class), viewed.name or "?"))
    end

    local maxOffset = math.max(0, #entries - visibleRows)
    if offset > maxOffset then offset = maxOffset end
    window.scroll:SetMinMaxValues(0, maxOffset)
    window.scroll:SetShown(maxOffset > 0)
    if math.floor(window.scroll:GetValue() + 0.5) ~= offset then window.scroll:SetValue(offset) end

    for i = 1, visibleRows do
        local entry = entries[offset + i]
        local row = rows[i]
        if entry then
            if not row then
                row = CreateRow(window.list, i)
                rows[i] = row
            end
            PaintRow(row, entry, myKey)
            row:Show()
        elseif row then
            row.entry = nil
            row:Hide()
        end
    end
    window.empty:SetShown(#entries == 0)
end

local function SavePosition()
    if not window then return end
    local point, _, _, x, y = window:GetPoint(1)
    if point then settings.point, settings.x, settings.y = point, x, y end
end

local function BuildWindow()
    if window then return window end

    local w = CreateFrame("Frame", "OxedHubReputations", UIParent, "BackdropTemplate")
    w:SetSize(W, H)
    w:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 0, settings.y or 40)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    w:Hide()
    tinsert(UISpecialFrames, "OxedHubReputations")

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(w, L["Reputations"], 0.96)
    elseif w.SetBackdrop then
        w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        w:SetBackdropColor(0.1, 0.095, 0.085, 0.96)
    end

    local okClose, close = pcall(CreateFrame, "Button", nil, w, "UIPanelCloseButton")
    if okClose and close then
        close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
    end

    -- ⚠ SetAutoFocus(false) first thing: a new EditBox takes the keyboard,
    -- and an unfocused-looking one left the player unable to move or cast.
    local okSearch, search = pcall(CreateFrame, "EditBox", nil, w, "SearchBoxTemplate")
    if not okSearch or not search then
        search = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    end
    search:SetAutoFocus(false)
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -30)
    search:HookScript("OnTextChanged", function()
        offset = 0
        Draw()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.search = search

    local hide = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    hide:SetSize(24, 24)
    hide:SetPoint("LEFT", search, "RIGHT", 14, 0)
    hide.text:SetFontObject("GameFontHighlightSmall")
    hide.text:SetText(L["Hide finished"])
    hide:SetScript("OnClick", function(self)
        settings.hideFinished = self:GetChecked() and true or false
        offset = 0
        Draw()
    end)
    w.hideBox = hide

    local others = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    others:SetSize(24, 24)
    others:SetPoint("LEFT", hide.text, "RIGHT", 14, 0)
    others.text:SetFontObject("GameFontHighlightSmall")
    others.text:SetText(L["Other characters"])
    others:SetScript("OnClick", function(self)
        settings.showOthers = self:GetChecked() and true or false
        Draw()
    end)
    w.othersBox = others

    local options = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    options:SetSize(80, 22)
    options:SetPoint("TOPRIGHT", w, "TOPRIGHT", -34, -29)
    options:SetText(OPTIONS or L["Options"])
    options:SetScript("OnClick", function()
        local API = OxedHub.ModuleAPI
        local mod = API and API.GetModule and API:GetModule("reputations")
        if mod and mod.OnOptionsShow then mod:OnOptionsShow() end
    end)

    -- Whose list: a menu of every saved character. Where the game's menu is
    -- missing, a click steps to the next one instead.
    local function SetView(key)
        viewKey = (key and key ~= CharKey()) and key or nil
        offset = 0
        Draw()
    end
    local picker = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    picker:SetSize(140, 20)
    picker:SetPoint("TOPRIGHT", w, "TOPRIGHT", -34, -55)
    picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    picker:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then return SetView(nil) end
        local list = CharacterList()
        local shown = MenuUtil and MenuUtil.CreateContextMenu and pcall(MenuUtil.CreateContextMenu, self,
            function(_, root)
                root:CreateTitle(L["Show the list of"])
                for _, key in ipairs(list) do
                    local char = settings.chars[key]
                    local label = ("|c%s%s|r  |cff9d9d9d%s|r"):format(ClassHex(char.class),
                        char.name or key, key == CharKey() and "you" or Ago(char.seen))
                    root:CreateButton(label, function() SetView(key) end)
                end
            end)
        if not shown then
            local current = viewKey or CharKey()
            for i, key in ipairs(list) do
                if key == current then
                    SetView(list[i % #list + 1])
                    return
                end
            end
            SetView(nil)
        end
    end)
    picker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Whose reputations"])
        GameTooltip:AddLine(L["Click to pick any of your characters. Right-click: back to this one."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    picker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.picker = picker

    -- Fold every expansion at once, or open them all again when all are folded.
    local function AllFolded()
        for _, known in pairs(settings.known) do
            if known.g and not settings.collapsed[known.g] then return false end
        end
        return true
    end
    local fold = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    fold:SetSize(84, 20)
    fold:SetPoint("RIGHT", picker, "LEFT", -6, 0)
    fold.Refresh = function() fold:SetText(AllFolded() and L["Expand all"] or L["Collapse all"]) end
    fold:SetScript("OnClick", function()
        local open = AllFolded()
        for _, known in pairs(settings.known) do
            if known.g then settings.collapsed[known.g] = (not open) or nil end
        end
        offset = 0
        Draw()
    end)
    w.fold = fold

    w.summary = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.summary:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -60)
    w.summary:SetJustifyH("LEFT")
    w.summary:SetWidth(W - 294)   -- up to the Collapse all button
    w.summary:SetWordWrap(false)

    local line = w:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -LIST_TOP + 4)
    line:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -LIST_TOP + 4)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    -- The list draws only the rows that fit, and a scroll moves which
    -- factions they show: a few hundred rows of bars built at once were a
    -- long first open.
    local list = CreateFrame("Frame", nil, w)
    list:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -28, 14)
    list:EnableMouseWheel(true)
    w.list = list
    visibleRows = math.floor((H - LIST_TOP - 14) / ROW_H)

    -- The game's own thin scrollbar, as its newer windows use. It speaks in
    -- percentages; this wraps it in the few slider calls the list makes. The
    -- plain slider stays as the fallback for a client without the template.
    local function OnOffset(value)
        local wanted = math.floor(value + 0.5)
        if wanted ~= offset then
            offset = wanted
            Draw()
        end
    end
    local scroll
    local okBar, bar = pcall(CreateFrame, "EventFrame", nil, w, "MinimalScrollBar")
    if okBar and bar and bar.SetScrollPercentage and bar.RegisterCallback then
        bar:SetPoint("TOPRIGHT", w, "TOPRIGHT", -14, -LIST_TOP)
        bar:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -14, 16)
        local maxValue, setting = 0, false
        scroll = {
            SetMinMaxValues = function(_, _, high)
                maxValue = high or 0
                local total = visibleRows + maxValue
                if bar.SetVisibleExtentPercentage then
                    bar:SetVisibleExtentPercentage(total > 0 and visibleRows / total or 1)
                end
                if bar.SetPanExtentPercentage then
                    bar:SetPanExtentPercentage(maxValue > 0 and math.min(1, 3 / maxValue) or 1)
                end
            end,
            GetMinMaxValues = function() return 0, maxValue end,
            GetValue = function()
                return maxValue > 0 and (bar:GetScrollPercentage() or 0) * maxValue or 0
            end,
            SetValue = function(_, value)
                setting = true
                bar:SetScrollPercentage(maxValue > 0 and value / maxValue or 0)
                setting = false
                OnOffset(value)
            end,
            SetShown = function(_, shown) bar:SetShown(shown) end,
        }
        bar:RegisterCallback("OnScroll", function(_, percentage)
            if not setting then OnOffset((percentage or 0) * maxValue) end
        end, w)
    else
        scroll = CreateFrame("Slider", nil, w)
        scroll:SetOrientation("VERTICAL")
        scroll:SetWidth(10)
        scroll:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -LIST_TOP)
        scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -12, 16)
        scroll:SetValueStep(1)
        scroll:SetObeyStepOnDrag(true)
        local track = scroll:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.45)
        local thumb = scroll:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, 0.82, 0, 0.55)
        thumb:SetSize(10, 36)
        scroll:SetThumbTexture(thumb)
        scroll:SetScript("OnValueChanged", function(_, value) OnOffset(value) end)
    end
    w.scroll = scroll

    list:SetScript("OnMouseWheel", function(_, delta)
        local low, high = scroll:GetMinMaxValues()
        scroll:SetValue(math.max(low, math.min(high, offset - delta * 3)))
    end)

    w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    w.empty:SetPoint("CENTER", list, "CENTER")
    w.empty:SetText(L["Nothing to show"])

    w:SetScript("OnShow", function(self)
        self.hideBox:SetChecked(settings.hideFinished == true)
        self.othersBox:SetChecked(settings.showOthers ~= false)
        Draw()
        -- A fresh read when opened, out of combat.
        QueueScan(0)
    end)

    window = w
    return w
end

local function ToggleWindow()
    if not settings then return end
    if not running then
        print(PREFIX .. L["switch the module on first (/ohub > Modules)."])
        return
    end
    local w = BuildWindow()
    w:SetShown(not w:IsShown())
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not running then return end

    if event == "UPDATE_FACTION" then
        if discovering or GetTime() < quietUntil then return end
        -- A faction the list has not seen, or a header the player opened:
        -- learn the list again before the next read.
        if C_Reputation.GetNumFactions and C_Reputation.GetNumFactions() ~= lastNumFactions then
            discoverOwed = true
        end
        QueueScan()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        if isLogin or isReload then
            discoverOwed = true
            QueueScan(3)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if scanOwed then
            scanOwed = false
            QueueScan(0.5)
        end
    else
        -- Renown levels and new major factions.
        QueueScan()
    end
end)

local EVENTS = {
    "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
    "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED",
}

local function Start()
    if running then return end
    running = true
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    discoverOwed = true
    QueueScan(3)
end

local function Stop()
    running = false
    watcher:UnregisterAllEvents()
    if window then window:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function EnsureTables(config)
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.known) ~= "table" then config.known = {} end
    if type(config.chars) ~= "table" then config.chars = {} end
    if type(config.account) ~= "table" then config.account = {} end
    if type(config.collapsed) ~= "table" then config.collapsed = {} end
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.reputations
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.reputations = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    EnsureTables(config)
    settings = config
end

local function ForgetOthers()
    local me = CharKey()
    for key in pairs(settings.chars) do
        if key ~= me then settings.chars[key] = nil end
    end
    Draw()
end

-- Its own minimap icon, made the first time it is needed (after binding).
local minimapIcon
local function MinimapIcon()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "reputations", label = L["Reputations"], icon = "Interface\\Icons\\Achievement_Reputation_01", config = settings,
        hint = L["Click: the list. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then
                local mod = API:GetModule("reputations")
                if mod and mod.OnOptionsShow then mod:OnOptionsShow() end
            else
                ToggleWindow()
            end
        end,
    })
    return minimapIcon
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Reputations", 480, 420)
        local o = optionsWindow

        o:AddCheckbox(settings, "showOthers", "Show your other characters on each row",
            "For factions not shared by the warband: the character furthest along, when it is ahead of this one.", Draw)
        o:AddCheckbox(settings, "hideFinished", "Hide finished reputations",
            "Exalted, top renown or a full friendship. Paragon factions still show.", Draw)
        o:AddCheckbox(settings, "paragonAlert", "Say when a paragon cache is waiting")
        o:AddSoundPicker(settings, "paragonSound", "Paragon sound", "None")
        o:AddCheckbox(settings, "autoWatch", "Track the faction you last gained reputation with",
            "Switches the reputation shown on the experience bar, out of combat.")

        local open = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        open:SetSize(150, 22)
        open:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 4)
        open:SetText(L["Open the list"])
        open:SetScript("OnClick", ToggleWindow)

        local forget = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        forget:SetSize(190, 22)
        forget:SetPoint("LEFT", open, "RIGHT", 8, 0)
        forget:SetText(L["Forget other characters"])
        forget:SetScript("OnClick", function()
            API:Confirm(L["Forget the reputations saved for every other character?"], ForgetOthers)
        end)
        o.cursorY = o.cursorY - 34

        o:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        o:AddNote("Each character's standings are saved when it logs in with this module on, so log in on your alts once for them to show.")
        o:AddNote("Type /oxrep to open the list.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBREPUTATIONS1 = "/oxrep"
SLASH_OXEDHUBREPUTATIONS2 = "/oxreps"
SlashCmdList.OXEDHUBREPUTATIONS = function()
    ToggleWindow()
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
        id       = "reputations",
        name     = "Reputations",
        version  = "1.2.0",
        updated  = 20261016.99,  -- Minimap button
        author   = "Oxed",
        category = "character",
        keywords = { "reputation", "rep", "renown", "paragon", "faction", "friendship", "warband", "alts" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Every reputation and renown for all your characters, with paragon alerts. /oxrep",
        icon     = "Interface\\Icons\\Achievement_Reputation_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,
        -- On the minimap button's right-click menu.
        quick = {
            { text = L["Reputations"], func = function() ToggleWindow() end },
        },

        OnEnable = function(_, config)
            settings = config
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            EnsureTables(settings)
            Start()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
