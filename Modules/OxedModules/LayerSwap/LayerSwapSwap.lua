-- ============================================================================
-- Layer Swap, part 2 of 5: asking for a swap, and hosting other players
--
-- A player changes layer by joining a group whose leader stands on another
-- layer of the same zone. The game then moves them, and leaving the group a
-- moment later keeps the new layer.
--
-- On live Forever an add-on cannot post chat lines or send add-on messages
-- to channels; a hidden add-on whisper to one named player goes through. So
-- a swap is asked the way LayerSwap, Bulo, Forever Layers and LayerETA ask,
-- and their hosts answer ours and ours answer theirs (prefix "LayerSwap"):
--   ask    inv layer <LS <zone> not <my id> [not <id>...] <x>,<y>>
--          or "want <id>" for one layer; x,y in percent of the zone map
--   reply  heard <asker>|<their layer or ->|<their zone or ->|<h or ->
--          (h = they host), or "same" from a host on the asker's own layer
-- A host on another layer simply invites.
--
-- The game's player search (only from a click) lists who is in the zone, at
-- most 50 a search; each click searches the zone again, one class at a time.
-- The client allows about ten add-on messages at once and then about one a
-- second, so the asks go out in bursts of eight.
-- ============================================================================

local _, OxedHub = ...
local LS = OxedHub.LayerSwap
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local PREFIX = "LayerSwap"
local S = {
    WAIT = 120,            -- an ask waits this long for an invite
    PROMISE_WAIT = 2,      -- a host that said it helps and sent no invite by then is passed over
    SEARCH_GAP = 5,        -- between two player searches
    SEARCH_TIMEOUT = 6,
    VERIFY = 15,           -- a join that has not moved us by then failed
    COPY_WAIT = 30,        -- after a transfer in the group, for the creatures to show the new layer
    READ_WAIT = 90,
    LEAVE_AFTER = 2.5,     -- leave the host's group this long after the move
    BURST = 8, RETRY = 0.9,
    SKIP = 15 * 60,        -- a player who never answered is not asked again for this long
    BOOK_DAYS = 7,         -- a player who answered is asked first for this long
    BOOK_LIMIT = 3000, ASKED_LIMIT = 3000,
    HELP_CAP = 6, HELP_WINDOW = 600,   -- invites as a host: Blizzard silences invite spam
    PLAYER_GAP = 60,       -- one invite per player per minute
    INVITE_GAP = 1,
    HEARD_GAP = 10,        -- one reply per asker per 10 s
    GONE_WAIT = 12,        -- the game's "no player named" line this soon after our whisper is ours
    GUEST_TTL = 120,
    MOVE_CAP = 10, MOVE_WINDOW = 3600,  -- the game allows about ten layer changes an hour
    MOVE_WARN = 3,
    HOST_WATCH = 20, HOST_MOVED_FOR = 1800,
    CLASSES = { 1, 2, 3, 4, 5, 7, 8, 9, 11 },
}
LS.SWAP_LIMITS = S

local swap                 -- the ask under way, or nil
local last = { at = -1000 }
local helped = {}          -- times of our invites as a host
local invitedAt = {}       -- [name] = GetTime()
local guests = {}          -- [name] = GetTime(): players we invited
local heardAt = {}         -- [name] = GetTime() of our last reply
local sentTo = {}          -- [name as messaged] = GetTime()
local movedBy = {}         -- [name] = GetTime(): a guest whose join moved us instead
local joinedIn = {}        -- [name] = GetTime(): a guest seen in our group
local lastInviteAt, heldUntil = -1000, -1000
local prefixReady = false
local whoRound = -1
local otherHost            -- another layer add-on that hosts for this character
local guestJoinAt = -1000
local stats = { asks = 0, invites = 0, replies = 0, skipped = 0 }

function LS.SwapStats() return stats end
function LS.OtherHost() return otherHost end

-- ── The protocol ────────────────────────────────────────────────────────────

local function AskText(zone, want, avoid, more, x, y)
    local parts = { "<LS", tostring(zone) }
    if want then
        parts[#parts + 1] = "want " .. want
    elseif avoid then
        parts[#parts + 1] = "not " .. avoid
        for _, id in ipairs(more or {}) do
            if #parts < 9 and not LS.Same(id, avoid) then parts[#parts + 1] = "not " .. id end
        end
    end
    if x and y then parts[#parts + 1] = string.format("%.1f,%.1f", x * 100, y * 100) end
    return "inv layer " .. table.concat(parts, " ") .. ">"
end

local function ParseAsk(text)
    if not LS.Text(text) or not text:find("^inv layer") then return nil end
    local body = text:match("<LS([^<>]*)>")
    if not body then return { plain = true, avoids = {} } end
    local ask = { avoids = {} }
    ask.zone = tonumber(body:match("^%s*(%d+)%s") or body:match("^%s*(%d+)%s*$") or "")
    ask.want = body:match("want%s+(%d+%-%d+)")
    for id in body:gmatch("not%s+(%d+%-%d+)") do ask.avoids[#ask.avoids + 1] = id end
    local px, py = body:match("(%d+%.?%d*),(%d+%.?%d*)%s*$")
    local x, y = tonumber(px or ""), tonumber(py or "")
    if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then ask.x, ask.y = x / 100, y / 100 end
    return ask
end

local function HeardText(asker, layer, zone, hosting)
    return "heard " .. asker .. "|" .. (layer or "-") .. "|" .. (zone and tostring(zone) or "-") .. "|" .. (hosting and "h" or "-")
end

local function ParseHeard(text)
    if not LS.Text(text) then return nil end
    local target, layer, zone, h = text:match("^heard (.-)|([^|]*)|([^|]*)|([^|]*)$")
    if not target then return nil end
    return { target = target, layer = LS.ValidId(layer) and layer or nil, zone = tonumber(zone), hosting = h == "h" }
end

local function Sent(result)
    if result == true or result == 0 or result == nil then return true end
    local E = Enum and Enum.SendAddonMessageResult
    return E ~= nil and result == E.Success
end

local function Throttled(result)
    local E = Enum and Enum.SendAddonMessageResult
    return E ~= nil and result == E.AddonMessageThrottle
end

local function Whisper(text, to)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "WHISPER", to)
    if not ok then return false end
    if Sent(result) then sentTo[to] = GetTime() end
    return result
end

-- ── Saved lists ─────────────────────────────────────────────────────────────
-- book:  players who answered, asked first for a week
-- asked: players asked who never answered, left alone for 15 minutes

local function Prune(list, limit, maxAge)
    local wall, count, oldestName, oldest = time(), 0, nil, math.huge
    for name, rec in pairs(list) do
        local at = type(rec) == "table" and rec.at or rec
        if type(at) ~= "number" or wall - at > maxAge then
            list[name] = nil
        else
            count = count + 1
            if at < oldest then oldestName, oldest = name, at end
        end
    end
    if count > limit and oldestName then list[oldestName] = nil end
end

local function Book() return LS.settings.book end
local function Asked() return LS.settings.asked end

local function Remember(name, from, zone, layer, hosting)
    Book()[name] = { at = time(), from = from, zone = zone, layer = layer, h = hosting or nil }
    Asked()[name] = nil
    Prune(Book(), S.BOOK_LIMIT, S.BOOK_DAYS * 86400)
end

local function Remembered(name)
    local rec = name and Book()[name]
    if type(rec) == "table" and type(rec.at) == "number" and time() - rec.at <= S.BOOK_DAYS * 86400 then return rec end
    return nil
end

local function Gone(rec)
    return type(rec) == "table" and type(rec.gone) == "number" and time() - rec.gone < 600
end

function LS.KnownHostCount()
    local n = 0
    for _, rec in pairs(Book()) do if type(rec) == "table" and rec.h then n = n + 1 end end
    return n
end

-- Hosts heard on a layer of a zone in the last hour.
local helpers = {}         -- [zone] = { [server] = { [name] = { at, from } } }
function LS.NoteHelper(zone, layer, name, from)
    local server = LS.Server(layer)
    if not (zone and server and name) then return end
    helpers[zone] = helpers[zone] or {}
    helpers[zone][server] = helpers[zone][server] or {}
    helpers[zone][server][name] = { at = GetTime(), from = from or name }
end

function LS.HelpersOn(zone, layer)
    local out = {}
    local server = LS.Server(layer)
    local list = zone and server and helpers[zone] and helpers[zone][server]
    local now = GetTime()
    for name, rec in pairs(list or {}) do
        if now - rec.at <= 3600 then out[#out + 1] = { name = name, from = rec.from, at = rec.at } end
    end
    table.sort(out, function(a, b) return a.at > b.at end)
    return out
end

-- ── Layer changes this hour ─────────────────────────────────────────────────

local function Moves()
    local s = LS.settings
    if type(s.moves) ~= "table" then s.moves = {} end
    local keep, wall = {}, time()
    for _, t in ipairs(s.moves) do
        if type(t) == "number" and wall - t < S.MOVE_WINDOW then keep[#keep + 1] = t end
    end
    s.moves = keep
    return keep
end

function LS.MovesLeft()
    local m = Moves()
    local left = S.MOVE_CAP - #m
    local resetIn = m[1] and (m[1] + S.MOVE_WINDOW - time()) or 0
    return math.max(0, left), resetIn
end

local function NoteMove()
    local m = Moves()
    m[#m + 1] = time()
    LS.settings.moves = m
end

-- ── The game's player search ────────────────────────────────────────────────
-- The group finder's who list and the Friends window open themselves on any
-- search answer, so while our search is out they are taken off the event,
-- unless the player has one open.

local WHO_LISTS = { "LFGWhoListFrame", "FriendsFrame", "WhoFrame" }
local muted = {}
local searchAt

local function Visible(frame)
    return type(frame) == "table" and type(frame.IsVisible) == "function" and frame:IsVisible() == true
end

local function HushWhoLists()
    for _, name in ipairs(WHO_LISTS) do
        local frame = _G[name]
        if type(frame) == "table" and not muted[name] and type(frame.IsEventRegistered) == "function"
            and frame:IsEventRegistered("WHO_LIST_UPDATE") and not Visible(frame) then
            frame:UnregisterEvent("WHO_LIST_UPDATE")
            muted[name] = frame
        end
    end
end

local function ReleaseWhoLists()
    searchAt = nil
    for name, frame in pairs(muted) do
        pcall(frame.RegisterEvent, frame, "WHO_LIST_UPDATE")
        muted[name] = nil
    end
    local open = false
    for _, name in ipairs(WHO_LISTS) do if Visible(_G[name]) then open = true end end
    if not open and C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, false) end
end

-- The class filter lists the classes left OUT (as Blizzard's own who list fills it).
local function LeftOut(keep)
    local out = {}
    if not keep then return out end
    for _, id in ipairs(S.CLASSES) do if id ~= keep then out[#out + 1] = id end end
    return out
end

-- Must run first in a click: the search only counts from one.
local function Search(zone)
    whoRound = (whoRound + 1) % (#S.CLASSES + 1)
    local class = whoRound > 0 and S.CLASSES[whoRound] or nil
    local name = LS.ZoneName(zone)
    local text = (name ~= LS.T("Unknown zone")) and ('z-"' .. name .. '"') or ""
    if C_FriendList and C_FriendList.SetWhoToUi then pcall(C_FriendList.SetWhoToUi, true) end
    HushWhoLists()
    searchAt = GetTime()
    local origin = Enum and Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social
    local ok = false
    if C_FriendList and C_FriendList.SendWho then
        ok = pcall(C_FriendList.SendWho, text, origin, { classIDs = LeftOut(class), raceIDs = {}, uiMapIDs = { zone } })
        if not ok then ok = pcall(C_FriendList.SendWho, text) end
    elseif SendWho then
        ok = pcall(SendWho, text)
    end
    C_Timer.After(5, function()
        if searchAt and GetTime() - searchAt >= 4.9 then ReleaseWhoLists() end
    end)
    return ok
end

-- ── Asking ──────────────────────────────────────────────────────────────────

local function Finish(result, text)
    if not swap then return end
    last = { at = GetTime(), result = result, text = text, from = swap.from, to = swap.to, zone = swap.zone }
    swap = nil
    if text then LS.Chat(text) end
    LS.Log(text or result)
    if LS.OnSwapFinished then LS.OnSwapFinished(result) end
    LS.Changed()
end

local function Counts(s)
    local heard, hosting = 0, 0
    for _, r in pairs(s.heard) do
        heard = heard + 1
        if r.hosting and not LS.Same(r.layer, s.from) then hosting = hosting + 1 end
    end
    return heard, hosting
end

local function Queue(s, name, to)
    if s.asked[name] or name == LS.Me() then return false end
    s.asked[name] = true
    s.queue[#s.queue + 1] = to or name
    return true
end

local function Wanted(s, layer)
    if not layer or LS.Same(layer, s.from) then return false end
    if s.want then return LS.Same(layer, s.want) end
    for _, id in ipairs(s.avoid or {}) do if LS.Same(layer, id) then return false end end
    if s.avoidGuild and LS.GuildOnLayer and LS.GuildOnLayer(s.zone, layer) > 0 then return false end
    return true
end

-- Why a swap cannot start now, or nil.
function LS.SwapBlocked()
    if not LS.running then return LS.T("Switch Layer Swap on in the Modules page first.") end
    if not prefixReady then return LS.T("Layer swaps are not available: the message prefix was refused.") end
    if LS.InInstance() then return LS.T("There are no layers in an instance.") end
    if InCombatLockdown() then return LS.T("Not in combat.") end
    if IsInGroup() then return LS.T("Leave your group first: a swap joins a host's group.") end
    if not LS.MyLayer() then
        if LS.WantLayer then LS.WantLayer() end
        return LS.T("Your layer is not known yet: target or mouse over a creature.")
    end
    if not LS.Zone() then return LS.T("Your zone is not known yet.") end
    local left = LS.MovesLeft()
    if left <= 0 then
        local _, resetIn = LS.MovesLeft()
        return (LS.T("The game allows about 10 layer changes an hour. Try again in %s.")):format(LS.Clock(resetIn))
    end
    return nil
end

local function Pump(limit)
    local s = swap
    local n = 0
    limit = limit or S.BURST
    while s and swap == s and #s.queue > 0 and n < limit and GetTime() >= heldUntil
        and s.state ~= "searching" and s.state ~= "joined" and not s.paused do
        local to = table.remove(s.queue, 1)
        local result = Whisper(s.text, to)
        if Throttled(result) then
            table.insert(s.queue, 1, to)
            heldUntil = GetTime() + S.RETRY
            break
        end
        n = n + 1
        if Sent(result) then
            s.sent = s.sent + 1
            stats.asks = stats.asks + 1
            local name = LS.Short(to)
            if name and not Book()[name] then Asked()[name] = time() end
        end
    end
    if n > 0 then
        Prune(Asked(), S.ASKED_LIMIT, S.SKIP)
        LS.Changed()
    end
end

-- The portal's click, the key and /oxlayer swap. want: one layer's id, or nil
-- for any other. The player search goes first in the click.
function LS.StartSwap(want, guildOnly)
    if swap then
        if swap.paused then
            swap.paused, swap.pausedAt = nil, nil
            Pump()
            return
        end
        LS.SwapNext()
        return
    end
    local blocked = LS.SwapBlocked()
    if blocked then
        LS.Say(blocked)
        return
    end
    local zone, from = LS.Zone(), LS.MyLayer()
    local s = LS.settings
    local helperList = want and LS.HelpersOn(zone, want) or nil
    local searched = false
    if not guildOnly and (not want or not helperList or #helperList == 0) then
        searched = Search(zone)
    end
    local x, y = LS.MapPos(zone)
    local onlyNew = not want and s.onlyNew
    local more = onlyNew and LS.StoodLayerIds(zone, from, 6) or {}
    local avoid = onlyNew and LS.StoodLayerIds(zone, from, 20) or {}
    if not want and s.avoidGuild and LS.GuildLayerIds then
        for _, id in ipairs(LS.GuildLayerIds(zone, from)) do
            table.insert(more, 1, id)
            avoid[#avoid + 1] = id
        end
    end
    swap = { at = GetTime(), zone = zone, from = from, want = want, queue = {}, asked = {}, heard = {}, same = 0,
        avoid = avoid, sent = 0, tried = {}, noInvite = {}, avoidGuild = not want and s.avoidGuild,
        state = searched and "searching" or "asking", searchedAt = searched and GetTime() or nil }
    swap.text = AskText(zone, want, from, more, x, y)
    for _, h in ipairs(helperList or {}) do
        if not Gone(Book()[h.name]) then Queue(swap, h.name, h.from) end
    end
    if guildOnly and LS.GuildNames then
        for _, name in ipairs(LS.GuildNames()) do Queue(swap, name, name) end
    end
    if want then
        LS.Chat((LS.T("Asking for layer %s in %s.")):format(LS.LayerName(want, zone), LS.ZoneName(zone)))
    else
        LS.Chat((LS.T("Looking for a host on another layer in %s.")):format(LS.ZoneName(zone)))
    end
    if LS.OnSwapStarted then LS.OnSwapStarted() end
    if not searched and #swap.queue == 0 then
        Finish("nobody", LS.T("Nobody to ask. Try again from a busier spot."))
        return
    end
    Pump()
    LS.Changed()
end

-- A further click: search the zone again (another class), or carry on.
function LS.SwapNext()
    local s = swap
    if not s then return LS.StartSwap() end
    if s.state == "joined" then
        LS.Say(LS.T("A host is inviting you. Wait for the move."))
        return
    end
    if s.paused then
        s.paused, s.pausedAt = nil, nil
        Pump()
        return
    end
    if s.state == "searching" or GetTime() - (s.searchedAt or 0) < S.SEARCH_GAP then
        LS.Say(LS.T("Still searching. Wait a few seconds."))
        return
    end
    if Search(s.zone) then
        s.state, s.at, s.searchedAt, s.more = "searching", GetTime(), GetTime(), true
    end
    LS.Changed()
end

function LS.StopSwap()
    if swap then Finish("stopped", LS.T("Swap stopped.")) end
end

function LS.SwapActive() return swap ~= nil end
function LS.SwapState() return swap end
function LS.LastSwap() return last end

local function OnWhoList()
    if not searchAt then return end
    local s = swap
    local count = C_FriendList and C_FriendList.GetNumWhoResults and C_FriendList.GetNumWhoResults() or 0
    ReleaseWhoLists()
    if not LS.Public(count) or type(count) ~= "number" then count = 0 end
    if not s or s.state ~= "searching" then return end
    s.state = "asking"
    local asked, first, fresh = Asked(), {}, 0
    local me = LS.Me()
    for i = 1, math.min(count, 50) do
        local ok, info = pcall(C_FriendList.GetWhoInfo, i)
        local full = ok and type(info) == "table" and LS.Text(info.fullName) and info.fullName or nil
        local name = LS.Short(full)
        if name and name ~= me and not s.asked[name] then
            local rec = Remembered(name)
            if rec then
                if not Gone(rec) then
                    s.asked[name] = true
                    first[#first + 1] = { to = full, at = rec.at, h = rec.h }
                end
            else
                local before = asked[name]
                if not (before and time() - before < S.SKIP) and Queue(s, name, full) then fresh = fresh + 1 end
            end
        end
    end
    -- known hosts first, the most recent first
    table.sort(first, function(a, b)
        if (a.h ~= nil) ~= (b.h ~= nil) then return a.h ~= nil end
        return a.at > b.at
    end)
    for i, entry in ipairs(first) do table.insert(s.queue, i, entry.to) end
    s.found = (s.found or 0) + fresh + #first
    s.full = count >= 50
    if #s.queue == 0 then
        if s.more then
            LS.Chat(LS.T("Nobody new to ask this time. Still waiting for answers; click again to search more."))
        else
            Finish("nobody", (LS.T("Nobody new to ask in %s right now. Try again in a few minutes.")):format(LS.ZoneName(s.zone)))
        end
    end
    Pump()
    LS.Changed()
end

local function HelperInGroup(name)
    if not name or not IsInGroup() then return false end
    local read = false
    for i = 1, 4 do
        local unit = "party" .. i
        if LS.Known(UnitExists, unit) then
            local whole = LS.UnitShortName(unit)
            if whole then
                read = true
                if whole == name then return true end
            end
        end
    end
    if read then return false end
    return nil
end

local function LeaveAfterMove(helper)
    if not LS.settings.autoLeave then return end
    C_Timer.After(S.LEAVE_AFTER, function()
        if LS.Known(UnitIsGroupLeader, "player") == true then return end
        if HelperInGroup(helper) == true then
            local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
            if leave then pcall(leave) end
        end
    end)
end

local function Moved(s, id, how)
    s.state, s.to = "moved", id
    NoteMove()
    LeaveAfterMove(s.inviter)
    local left = LS.MovesLeft()
    local tail = s.inviter and (" " .. (LS.T("Thanks to %s.")):format(s.inviter)) or ""
    if left <= S.MOVE_WARN then tail = tail .. " " .. (LS.T("%d layer changes left this hour.")):format(left) end
    LS.Log("Moved " .. tostring(s.from) .. " -> " .. tostring(id) .. " (" .. how .. ")")
    Finish("moved", (LS.T("Welcome to layer %s."):format(LS.ColorCode(id) .. LS.LayerName(id, s.zone) .. "|r")) .. tail)
end

local function Tick(now)
    Pump(S.BURST)
    local s = swap
    if not s then return end
    if s.state == "searching" and now - (s.searchedAt or s.at) > S.SEARCH_TIMEOUT then
        ReleaseWhoLists()
        s.state = "asking"
        if #s.queue == 0 and not s.more then
            Finish("nobody", LS.T("The player search did not answer. Try again."))
            return
        end
    end
    if s.state == "joined" then
        LS.Scan()
        local here = HelperInGroup(s.inviter)
        if here == false or (here == nil and now - s.joinedAt >= S.VERIFY) then
            Finish("other", LS.T("The host is not in the group you joined, so the swap stopped. You stay in the group."))
            return
        end
        if here == nil then return end
        local id = LS.MyLayer()
        if id and not LS.Reading() and not LS.Same(id, s.from) then
            Moved(s, id, "a new layer")
            return
        end
        if id and s.transferAt and not LS.Reading() and id ~= s.from and LS.Same(id, s.from) then
            Moved(s, id, "the same number, another copy")
            return
        end
        if LS.Reading() and s.transferAt and now - s.joinedAt < S.READ_WAIT then
            if not s.reminded and now - s.transferAt >= 3 then
                s.reminded = true
                LS.Chat(LS.T("The world changed around you. Look at a creature or NPC so the new layer can be read."))
            end
            return
        end
        if now - s.joinedAt >= S.VERIFY and not (s.transferAt and now - s.transferAt < S.COPY_WAIT) then
            s.tried[s.inviter or "?"] = true
            if IsInGroup() and LS.Known(UnitIsGroupLeader, "player") ~= true then
                local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
                if leave then pcall(leave) end
            end
            LS.Chat((LS.T("%s's group did not move you. Asking the others.")):format(s.inviter or "?"))
            s.state, s.inviter, s.joinedAt, s.transferAt, s.at = "asking", nil, nil, nil, now
        end
        return
    end
    if s.paused and not s.inviter and s.pausedAt and now - s.pausedAt >= S.PROMISE_WAIT then
        s.noInvite[s.paused] = true
        s.paused, s.pausedAt, s.at = nil, nil, now
        Pump()
        LS.Changed()
        return
    end
    if now - s.at > S.WAIT then
        local heard, hosting = Counts(s)
        Finish("timeout", (LS.T("No invite came. %d asked, %d have a layer add-on, %d host on another layer. Try another spot or later.")):format(s.sent, heard, hosting))
    end
end
LS.OnTick(Tick)

local function OnReply(text, sender)
    local s = swap
    local name = LS.Short(sender)
    if not name then return end
    stats.replies = stats.replies + 1
    if text == "same" then
        if s then
            s.same = s.same + 1
            s.heard[name] = s.heard[name] or { layer = s.from, hosting = true }
        end
        Remember(name, sender, s and s.zone, s and s.from, true)
        LS.Changed()
        return
    end
    local heard = ParseHeard(text)
    if not heard or heard.target ~= LS.Me() then return end
    if heard.zone and heard.layer then
        LS.NoteLayer(heard.zone, heard.layer)
        if heard.hosting then LS.NoteHelper(heard.zone, heard.layer, name, sender) end
    end
    Remember(name, sender, heard.zone, heard.layer, heard.hosting)
    if s then s.heard[name] = { layer = heard.layer, zone = heard.zone, hosting = heard.hosting } end
    if s and heard.hosting and not s.paused and not s.noInvite[name] and not s.inviter and s.state ~= "joined"
        and Wanted(s, heard.layer) then
        s.paused, s.pausedAt = name, GetTime()
        LS.Chat((LS.T("%s on layer %s will host you. Waiting for the invite.")):format(name, LS.LayerName(heard.layer, s.zone)))
    end
    LS.Changed()
end

-- ── Accepting ───────────────────────────────────────────────────────────────

local function HideInvitePopup()
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE_XREALM") end
end

LS.On("PARTY_INVITE_REQUEST", function(_, name)
    local s = swap
    local inviter = LS.Short(name)
    if not s or not inviter or s.state == "joined" then return end
    if not (s.asked[inviter] or s.heard[inviter]) then return end
    local reply = s.heard[inviter]
    if reply and reply.layer and not Wanted(s, reply.layer) then return end
    if s.tried[inviter] then return end
    s.inviter = inviter
    if LS.settings.autoAccept then
        if AcceptGroup then pcall(AcceptGroup) end
        HideInvitePopup()
    else
        LS.Chat((LS.T("%s invites you to swap layers. Accept the invite.")):format(inviter))
    end
    LS.Changed()
end)

LS.On("GROUP_JOINED", function()
    local s = swap
    if not s then return end
    if not s.inviter then
        Finish("other", LS.T("You joined a group that is not a host's, so the swap stopped."))
        return
    end
    s.state, s.joinedAt = "joined", GetTime()
    LS.Changed()
end)

LS.On("SHARD_TRANSFER", function()
    local s = swap
    if s and s.state == "joined" then
        s.transferAt = GetTime()
        -- the host said its layer: show it at once, creatures confirm it
        local said = s.inviter and s.heard[s.inviter]
        if said and said.layer and said.zone == LS.Zone() and not LS.Same(said.layer, s.from) then
            LS.AssumeLayer(said.layer, "the host's answer")
        end
        return
    end
    -- not our swap: did a guest's join move us, the host?
    local now = GetTime()
    if now - guestJoinAt <= S.HOST_WATCH then
        local guest, at = nil, -math.huge
        for name, t in pairs(guests) do
            if now - t <= S.GUEST_TTL and t > at then guest, at = name, t end
        end
        if guest then
            movedBy[guest] = now
            LS.Chat((LS.T("The game moved you to %s's layer instead of the other way round. They are not invited again for 30 minutes.")):format(guest))
            LS.Log("Host moved by " .. guest)
        end
    end
end)

-- ── Hosting ─────────────────────────────────────────────────────────────────

local function InGuild(name)
    return LS.IsGuildmate and LS.IsGuildmate(name) or false
end

local function GuestsOnly()
    if not IsInGroup() then return true, 0 end
    if IsInRaid() or LS.Known(UnitIsGroupLeader, "player") ~= true then return false end
    local count, now = 0, GetTime()
    for i = 1, 4 do
        local unit = "party" .. i
        if LS.Known(UnitExists, unit) then
            local name = LS.UnitShortName(unit)
            if not name or not guests[name] or now - guests[name] > S.GUEST_TTL * 5 then return false end
            count = count + 1
        end
    end
    return true, count
end

function LS.HostInvitesLeft(now)
    now = now or GetTime()
    local keep = {}
    for _, at in ipairs(helped) do if now - at < S.HELP_WINDOW then keep[#keep + 1] = at end end
    helped = keep
    return S.HELP_CAP - #keep, keep[1] and (keep[1] + S.HELP_WINDOW - now) or 0
end

function LS.Hosting()
    return LS.running and LS.settings and LS.settings.host == true and not otherHost
end

-- Why we cannot host this asker right now, or nil. "same": we are on their layer.
local function Refusal(ask, name, now)
    local s = LS.settings
    if otherHost then return otherHost .. " hosts for you" end
    if not s.host then return "hosting is off" end
    if s.hostGuildOnly and not InGuild(name) then return "not a guildmate" end
    if swap then return "our own swap is under way" end
    if LS.InInstance() then return "in an instance" end
    if InCombatLockdown() or LS.Known(UnitAffectingCombat, "player") ~= false then return "in combat" end
    if s.hostNotAfk and LS.Known(UnitIsAFK, "player") == true then return "away" end
    local me = LS.MyLayer()
    if not me or LS.Reading() then return "our layer is unknown" end
    if ask.want and not LS.Same(ask.want, me) then return "wants another layer" end
    for _, id in ipairs(ask.avoids or {}) do if LS.Same(id, me) then return "same" end end
    if movedBy[name] and now - movedBy[name] < S.HOST_MOVED_FOR then return "their join moved us before" end
    local ok, count = GuestsOnly()
    if not ok then return "in a group" end
    if count >= 4 then return "group full" end
    if LS.HostInvitesLeft(now) <= 0 then return "six invites in ten minutes" end
    if invitedAt[name] and now - invitedAt[name] < S.PLAYER_GAP then return "invited a minute ago" end
    if now - lastInviteAt < S.INVITE_GAP then return "busy" end
    if s.skipNear and ask.x then
        local yards = LS.Distance(ask.zone, ask.x, ask.y)
        if yards and yards < (s.nearYards or 150) then return "asks from " .. math.floor(yards) .. " yards away" end
    end
    return nil
end

local function Invite(name)
    local now = GetTime()
    helped[#helped + 1] = now
    invitedAt[name], guests[name], lastInviteAt = now, now, now
    stats.invites = stats.invites + 1
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local ok = fn and pcall(fn, name)
    if ok then
        LS.Chat((LS.T("Invited %s to your layer.")):format(name))
        LS.Log("Hosted: invited " .. name)
        if LS.OnHostInvite then LS.OnHostInvite(name) end
    end
    LS.Changed()
    return ok
end

-- Requests waiting for a click (Ask before inviting).
local requests = {}        -- { { name, at, layer } }
function LS.Requests()
    local now, keep = GetTime(), {}
    for _, r in ipairs(requests) do if now - r.at < 60 then keep[#keep + 1] = r end end
    requests = keep
    return requests
end

-- From the toast's button or the key: the oldest request still valid.
function LS.InviteNext(name)
    local list = LS.Requests()
    for i, r in ipairs(list) do
        if not name or r.name == name then
            table.remove(list, i)
            local why = Refusal(r.ask, r.name, GetTime())
            if why and why ~= "busy" then
                LS.Say((LS.T("Cannot invite %s now: %s.")):format(r.name, LS.T(why)))
            else
                Invite(r.name)
            end
            LS.Changed()
            return true
        end
    end
    return false
end

function LS.DeclineRequest(name)
    local list = LS.Requests()
    for i, r in ipairs(list) do
        if r.name == name then table.remove(list, i) break end
    end
    LS.Changed()
end

local function OnAsk(text, sender)
    local name = LS.Short(sender)
    if not name or name == LS.Me() then return end
    local ask = ParseAsk(text)
    if not ask or ask.plain then return end
    local zone = LS.Zone()
    if not ask.zone or ask.zone ~= zone then return end
    local now = GetTime()
    local refusal = Refusal(ask, name, now)
    if otherHost then return end
    local me = LS.MyLayer()
    if not heardAt[name] or now - heardAt[name] >= S.HEARD_GAP then
        heardAt[name] = now
        Whisper(HeardText(name, (not LS.Reading()) and me or nil, zone, refusal == nil or refusal == "same"), sender)
    end
    if refusal == "same" then
        Whisper("same", sender)
        return
    end
    if refusal then
        stats.skipped = stats.skipped + 1
        return
    end
    if LS.settings.askFirst then
        for _, r in ipairs(LS.Requests()) do if r.name == name then return end end
        requests[#requests + 1] = { name = name, at = now, ask = ask }
        if LS.OnHostRequest then LS.OnHostRequest(name) end
        LS.Changed()
        return
    end
    Invite(name)
end

-- Remove the players we invited from our group (a click).
function LS.KickGuests()
    if not IsInGroup() or LS.Known(UnitIsGroupLeader, "player") ~= true then
        LS.Say(LS.T("You do not lead a group."))
        return
    end
    local n = 0
    local fn = (C_PartyInfo and C_PartyInfo.UninviteUnit) or UninviteUnit
    for i = 4, 1, -1 do
        local name = LS.UnitShortName("party" .. i)
        if name and guests[name] and fn and pcall(fn, name) then n = n + 1 end
    end
    LS.Say((LS.T("Removed %d guests.")):format(n))
end

-- ── Hops and ranks ──────────────────────────────────────────────────────────
-- A guest who joins our group is one hop; one per player per day.

LS.RANKS = {
    { at = 0,   name = "Spark" },
    { at = 3,   name = "Wanderer" },
    { at = 10,  name = "Pathfinder" },
    { at = 25,  name = "Portal Keeper" },
    { at = 60,  name = "Archmage" },
    { at = 150, name = "Legend of the Ley" },
}

function LS.Hops()
    local s = LS.settings
    if type(s.hops) ~= "table" then s.hops = { total = 0, day = "", names = {} } end
    return s.hops
end

function LS.Rank()
    local total = LS.Hops().total or 0
    local idx = 1
    for i, r in ipairs(LS.RANKS) do if total >= r.at then idx = i end end
    return idx, LS.RANKS[idx], LS.RANKS[idx + 1]
end

local function CountHop(name)
    local h = LS.Hops()
    local day = date("%Y%m%d")
    if h.day ~= day then h.day, h.names = day, {} end
    if h.names[name] then return end
    local before = LS.Rank()
    h.names[name] = true
    h.total = (h.total or 0) + 1
    local after, rank = LS.Rank()
    if LS.OnHop then LS.OnHop(name, after > before and rank or nil) end
end

LS.On("GROUP_ROSTER_UPDATE", function()
    if not IsInGroup() then return end
    local now = GetTime()
    for i = 1, 4 do
        local unit = "party" .. i
        if LS.Known(UnitExists, unit) then
            local name = LS.UnitShortName(unit)
            if name and guests[name] and now - guests[name] <= S.GUEST_TTL then
                if not joinedIn[name] or now - joinedIn[name] > S.GUEST_TTL then
                    joinedIn[name] = now
                    guestJoinAt = now
                    CountHop(name)
                end
            end
        end
    end
end)

-- ── Messages ────────────────────────────────────────────────────────────────

LS.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if not LS.Public(prefix) or prefix ~= PREFIX then return end
    if not LS.Text(text) or not LS.Text(sender) or channel ~= "WHISPER" then return end
    if text:find("^inv layer") then OnAsk(text, sender) else OnReply(text, sender) end
end)

LS.On("WHO_LIST_UPDATE", function() OnWhoList() end)

-- The game's "No player named X is currently playing" for a name we just
-- whispered is ours: hide it, and leave that player alone for ten minutes.
local function NotPlaying(text)
    local form = _G.ERR_CHAT_PLAYER_NOT_FOUND_S
    if not LS.Text(text) or not LS.Text(form) then return nil end
    local pattern = "^" .. form:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
    local name = text:match(pattern)
    if not name then return nil end
    local now = GetTime()
    for to, at in pairs(sentTo) do
        if now - at > S.GONE_WAIT then
            sentTo[to] = nil
        elseif to == name or LS.Short(to) == LS.Short(name) then
            return to
        end
    end
    return nil
end

local filterAdded = false
local function SystemFilter(_, _, text, ...)
    local ok, to = pcall(NotPlaying, text)
    if not ok or not to then return false end
    local rec = Book()[LS.Short(to) or ""]
    if type(rec) == "table" then rec.gone = time() end
    return true
end

function LS.StartSwapping()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        local codes = Enum and Enum.RegisterAddonMessagePrefixResult
        prefixReady = ok and (result == true or result == nil or (codes and (result == codes.Success or result == codes.DuplicatePrefix)) or false)
    end
    otherHost = nil
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, addon in ipairs({ "LayerSwap", "BuloLayerForever", "ForeverLayers" }) do
        local ok, isLoaded, done = pcall(loaded, addon)
        if ok and (isLoaded == true or done == true) and not otherHost then otherHost = addon end
    end
    if not filterAdded then
        local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
        if add then
            pcall(add, "CHAT_MSG_SYSTEM", SystemFilter)
            filterAdded = true
        end
    end
end

function LS.StopSwapping()
    if swap then Finish("stopped", nil) end
    ReleaseWhoLists()
    requests = {}
end

-- One line for the portal: what the swap is doing.
function LS.SwapStatus()
    local s = swap
    if s then
        local zoneName = LS.ZoneName(s.zone)
        if s.state == "searching" then return (LS.T("Searching %s...")):format(zoneName) end
        if s.state == "joined" then
            if LS.Reading() and s.reminded then return LS.T("Look at a creature to read the new layer") end
            return (LS.T("%s invited you. Crossing...")):format(s.inviter or "?")
        end
        if s.inviter then return (LS.T("%s is inviting you")):format(s.inviter) end
        if s.paused then return (LS.T("%s will host. Waiting...")):format(s.paused) end
        local heard, hosting = Counts(s)
        local line = (LS.T("Asked %d")):format(s.sent)
        if #s.queue > 0 then line = line .. "/" .. (s.sent + #s.queue) end
        if heard > 0 then line = line .. "  " .. (LS.T("%d heard, %d hosting")):format(heard, hosting) end
        return line
    end
    if GetTime() - last.at < 20 and last.result then
        if last.result == "moved" then return LS.T("Moved. The new layer stays.") end
        if last.result == "timeout" then return LS.T("No invite came") end
        if last.result == "nobody" then return LS.T("Nobody to ask here") end
    end
    return nil
end
