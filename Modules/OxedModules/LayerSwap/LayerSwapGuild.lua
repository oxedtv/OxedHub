-- ============================================================================
-- Layer Swap, part 3 of 5: guildmates' layers, and layer talk in chat
--
-- Guild: every OxedHub player with Layer Swap on tells the guild (add-on
-- messages in GUILD, prefix "OxLayerSwap") which layer of which zone they
-- stand on and whether they host:
--   S|<layer id or ->|<zone map id or 0>|<1 hosting or 0>
--   H                 "tell me yours", sent once at login
-- The Guild tab shows each one as on your layer, another layer, or another
-- zone; Find them asks that guildmate's layer, Avoid guild keeps a swap off
-- every layer a guildmate stands on.
--
-- Chat: lines in General, Trade, LookingForGroup, guild, say and yell that
-- offer a layer ("anyone need layer? w me") or ask for one ("inv layer pls")
-- are kept, newest first, for the Chat tab and its Whisper button.
-- ============================================================================

local _, OxedHub = ...
local LS = OxedHub.LayerSwap
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local PREFIX = "OxLayerSwap"
local G = {
    TTL = 15 * 60,         -- a guildmate not heard from for this long is dropped
    RESEND = 5 * 60,       -- our state again at least this often
    GAP = 10,              -- never more than one state per this
    ROSTER_FOR = 60,
    CHAT_MAX = 20, CHAT_TTL = 15 * 60,
}

local mates = {}           -- [name] = { layer, zone, host, at }
local lastSent, lastSentText, sendQueued = -1000, nil, false
local roster, rosterAt = {}, -1000
local chatLines = {}
local prefixOk = false

-- ── The guild roster ────────────────────────────────────────────────────────

local function ReadRoster()
    local now = GetTime()
    if now - rosterAt < G.ROSTER_FOR then return roster end
    rosterAt, roster = now, {}
    if not IsInGuild() or not GetNumGuildMembers or not GetGuildRosterInfo then return roster end
    local ok, total = pcall(GetNumGuildMembers)
    if not ok or type(total) ~= "number" then return roster end
    for i = 1, math.min(total, 1000) do
        local okI, name, _, _, level, class, zone, _, _, online = pcall(GetGuildRosterInfo, i)
        local short = okI and LS.Short(name)
        if short then
            roster[short] = { online = online == true or online == 1, zone = LS.Text(zone) and zone or nil,
                level = level, class = class }
        end
    end
    return roster
end

function LS.IsGuildmate(name)
    if not name or not IsInGuild() then return false end
    if mates[name] then return true end
    return ReadRoster()[name] ~= nil
end

-- Guildmates online in this zone (for /oxlayer guild): names to ask.
function LS.GuildNames()
    local out, here, me = {}, LS.ZoneName(LS.Zone()), LS.Me()
    for name, r in pairs(ReadRoster()) do
        if r.online and r.zone == here and name ~= me then out[#out + 1] = name end
    end
    return out
end

-- ── Sending ─────────────────────────────────────────────────────────────────

local function StateText()
    local layer = (not LS.Reading()) and LS.MyLayer() or nil
    local zone = LS.Zone()
    if LS.InInstance() then layer, zone = nil, nil end
    return "S|" .. (layer or "-") .. "|" .. tostring(zone or 0) .. "|" .. (LS.Hosting() and "1" or "0")
end

local function Send(text, channel, target)
    if not (prefixOk and C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, channel, target)
end

function LS.SendGuildState(force)
    if not LS.running or not IsInGuild() or LS.settings.shareGuild == false then return end
    local now = GetTime()
    local text = StateText()
    if not force and text == lastSentText and now - lastSent < G.RESEND then return end
    if now - lastSent < G.GAP then
        if not sendQueued then
            sendQueued = true
            C_Timer.After(G.GAP - (now - lastSent) + 0.1, function()
                sendQueued = false
                LS.SendGuildState(force)
            end)
        end
        return
    end
    lastSent, lastSentText = now, text
    Send(text, "GUILD")
end

-- ── Receiving ───────────────────────────────────────────────────────────────

local function OnMessage(text, channel, sender)
    local name = LS.Short(sender)
    if not name or name == LS.Me() then return end
    if text == "H" then
        -- answer the newcomer a moment later, so a guild of fifty does not answer at once
        if LS.settings.shareGuild ~= false then
            C_Timer.After(1 + math.random() * 4, function()
                if LS.running then Send(StateText(), "WHISPER", sender) end
            end)
        end
        return
    end
    local layer, zone, host = text:match("^S|([^|]*)|(%d+)|([01])$")
    if not layer then return end
    zone = tonumber(zone)
    mates[name] = { layer = LS.ValidId(layer) and layer or nil, zone = zone ~= 0 and zone or nil,
        host = host == "1", at = GetTime() }
    if mates[name].layer and mates[name].zone then
        LS.NoteLayer(mates[name].zone, mates[name].layer)
        if mates[name].host then LS.NoteHelper(mates[name].zone, mates[name].layer, name, sender) end
    end
    LS.Changed()
end

LS.On("CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
    if not LS.Public(prefix) or prefix ~= PREFIX then return end
    if not LS.Text(text) or not LS.Text(sender) then return end
    if channel ~= "GUILD" and channel ~= "WHISPER" then return end
    OnMessage(text, channel, sender)
end)

local function Prune()
    local now = GetTime()
    for name, m in pairs(mates) do
        if now - m.at > G.TTL then mates[name] = nil end
    end
end

-- "same", "other" (another layer, same zone), "zone" (another zone) or "unknown".
local function Relation(m)
    local zone, me = LS.Zone(), LS.MyLayer()
    if not m.zone or not m.layer then return "unknown" end
    if m.zone ~= zone then return "zone" end
    if not me then return "unknown" end
    return LS.Same(m.layer, me) and "same" or "other"
end

-- For the Guild tab: { { name, layer, zone, host, rel, age } }, this zone first.
function LS.GuildList()
    Prune()
    local out, now = {}, GetTime()
    for name, m in pairs(mates) do
        out[#out + 1] = { name = name, layer = m.layer, zone = m.zone, host = m.host, rel = Relation(m), age = now - m.at }
    end
    local order = { same = 1, other = 2, zone = 3, unknown = 4 }
    table.sort(out, function(a, b)
        if order[a.rel] ~= order[b.rel] then return order[a.rel] < order[b.rel] end
        return a.name < b.name
    end)
    return out
end

function LS.GuildOnLayer(zone, layer)
    local n = 0
    for _, m in pairs(mates) do
        if m.zone == zone and LS.Same(m.layer, layer) and GetTime() - m.at <= G.TTL then n = n + 1 end
    end
    return n
end

function LS.GuildLayerIds(zone, except)
    local out = {}
    for _, m in pairs(mates) do
        if m.zone == zone and m.layer and not LS.Same(m.layer, except) and GetTime() - m.at <= G.TTL then
            local dup = false
            for _, id in ipairs(out) do if LS.Same(id, m.layer) then dup = true end end
            if not dup then out[#out + 1] = m.layer end
        end
    end
    return out
end

-- Find them: ask for that guildmate's layer.
function LS.FindGuildmate(name)
    local m = mates[name]
    if not m or not m.layer then
        LS.Say((LS.T("%s's layer is not known.")):format(name))
        return
    end
    if m.zone ~= LS.Zone() then
        LS.Say((LS.T("%s is in %s. Layers belong to one zone: go there first.")):format(name, LS.ZoneName(m.zone)))
        return
    end
    if LS.Same(m.layer, LS.MyLayer()) then
        LS.Say((LS.T("You are already on %s's layer.")):format(name))
        return
    end
    LS.NoteHelper(m.zone, m.layer, name, name)
    LS.StartSwap(m.layer)
end

-- ── Layer talk in chat ──────────────────────────────────────────────────────

local OFFER_WORDS = { "w me", "whisper me", "/w me", "anyone need", "who needs", "need a layer%?", "offering",
                      "giving layer", "layer inv", "can inv", "can invite", "free layer" }
local ASK_WORDS = { "inv layer", "layer inv pls", "need layer", "layer swap", "swap layer", "layer pls", "layer plz",
                    "layer please", "need a layer", "lf layer", "change layer", "layer hop" }
local BLOCK = { "wts", "wtb", "lfm", "lfg", "recruit", "guild", "boost", "what layer", "which layer", "how many layer" }

local function Classify(text)
    local lower = text:lower()
    if not lower:find("layer", 1, true) then return nil end
    for _, w in ipairs(BLOCK) do if lower:find(w, 1, true) then return nil end end
    local words = 0
    for _ in lower:gmatch("%S+") do words = words + 1 end
    if words > 14 then return nil end
    for _, w in ipairs(OFFER_WORDS) do if lower:find(w) then return "offer" end end
    for _, w in ipairs(ASK_WORDS) do if lower:find(w, 1, true) then return "ask" end end
    return nil
end

local WHERE = {
    CHAT_MSG_CHANNEL = "channel", CHAT_MSG_GUILD = "guild", CHAT_MSG_SAY = "say", CHAT_MSG_YELL = "yell",
}

local function OnChat(event, text, author, ...)
    if not LS.settings.chatWatch then return end
    if not LS.Text(text) or not LS.Text(author) then return end
    local name = LS.Short(author)
    if not name or name == LS.Me() then return end
    local kind = Classify(text)
    if not kind then return end
    for i = #chatLines, 1, -1 do
        if chatLines[i].name == name then table.remove(chatLines, i) end
    end
    table.insert(chatLines, 1, { name = name, full = author, text = text, kind = kind, at = GetTime(),
        where = WHERE[event] or "chat", zone = LS.Zone() })
    while #chatLines > G.CHAT_MAX do table.remove(chatLines) end
    if kind == "offer" and LS.OnChatOffer then LS.OnChatOffer(name) end
    LS.Changed()
end

for event in pairs(WHERE) do LS.On(event, OnChat) end

function LS.ChatLines()
    local now, out = GetTime(), {}
    for _, l in ipairs(chatLines) do
        if now - l.at <= G.CHAT_TTL then out[#out + 1] = l end
    end
    return out
end

-- Whisper button: opens a tell to them in the chat box (the player sends it).
function LS.WhisperOffer(line)
    if not line then return end
    if ChatFrame_SendTell then
        pcall(ChatFrame_SendTell, line.full or line.name)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        pcall(ChatFrameUtil.SendTell, line.full or line.name)
    end
end

-- ── Start and stop ──────────────────────────────────────────────────────────

local hello = false
function LS.StartGuild()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
        prefixOk = ok
    end
    if GuildRoster then pcall(GuildRoster) elseif C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    C_Timer.After(6, function()
        if not LS.running or not IsInGuild() then return end
        if not hello and LS.settings.shareGuild ~= false then
            hello = true
            Send("H", "GUILD")
        end
        LS.SendGuildState(true)
    end)
end

function LS.StopGuild()
    mates = {}
    chatLines = {}
end

LS.OnTick(function(now)
    if now - lastSent >= G.RESEND then LS.SendGuildState(false) end
end)

LS.On("PLAYER_GUILD_UPDATE", function() rosterAt = -1000 end)
LS.On("GUILD_ROSTER_UPDATE", function() rosterAt = -1000 end)
