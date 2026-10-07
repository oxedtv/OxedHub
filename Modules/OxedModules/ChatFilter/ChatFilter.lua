-- ============================================================================
-- Chat Filter & Global Ignore Suite (built-in OxedHub module)
-- Takes the noise out of chat and protects group play:
--
--   Ignore   players, whole realms and NPCs. Shared by every character on the
--            account, with custom notes, expiration timers and live search.
--   Sync     automatically keeps top 50 active ignores in Blizzard's native
--            list for server-level whisper and queue blocking.
--   LFG      highlights ignored leaders in M+/Raid Group Finder in red, and
--            shows ignore notes directly in the group tooltip.
--   Declines automatically declines party invites, duels, guild invites, and
--            trade requests from ignored players.
--   Filters  custom rules with whole-word, substring, or Lua patterns,
--            with interactive live testing in the manager.
--   Presets  boosting and gold selling, guild recruitment, community invites,
--            Asian-script text, raid-icon spam, repeats, link jokes, politics.
--   Blocked  live session history of filtered messages with 1-click ignore.
-- ============================================================================

local addonName, OxedHub = ...

-- ⚠ Only true/false/number/string here. ModuleAPI copies defaults key by key.
local DEFAULTS = {
    enabled         = false,  -- off until player switches it on

    presetBoost     = true,   -- boost carries, gold selling, "pay in raid"
    presetGuild     = false,  -- guild recruitment
    presetCommunity = true,   -- community and club invite links
    presetAsian     = false,  -- Chinese, Japanese and Korean text
    presetIcons     = true,   -- lines built out of raid target icons
    presetRepeat    = true,   -- the same sender saying the same thing again
    presetJokes     = true,   -- Thunderfury, Dirge, Anal link spam
    presetPolitics  = false,  -- political flamewars in public channels

    keepGuild       = true,   -- never filter guild or officer chat
    keepGroup       = true,   -- never filter party, raid or instance chat
    keepFriends     = true,   -- never filter friends
    keepWhispers    = false,  -- never word-filter whispers (ignores still apply)

    declineDuels    = true,   -- decline duel requests
    declineInvites  = true,   -- decline party/group invites
    declineGuild    = true,   -- decline guild invites
    declineTrade    = true,   -- decline trade requests
    warnGroup       = true,   -- warn when an ignored player is in your group
    lfgHighlight    = true,   -- color leaders red in LFG and show notes in tooltip
    syncBlizzard    = true,   -- sync top 50 ignores to Blizzard native ignore list
}

local settings          -- OxedHubDB.modules.chatfilter, bound at login
local manager           -- the manager window, built on first open
local optionsWindow
local installed = false
local inBlizzardSync = false

local PREFIX = "|cff00ff00OxedHub:|r "

local REPEAT_WINDOW = 90     -- seconds the same line from the same sender is a repeat
local LOG_LIMIT = 250        -- blocked lines kept for this session
local EXPIRY_STEPS = { 0, 1, 7, 30, 90 }   -- days; 0 means never

-- Forward declarations
local RefreshManager, OpenManager, SetIgnored, SyncToBlizzard

-- ── Names ───────────────────────────────────────────────────────────────────

local function SecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

local function PlayerRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName():gsub("[%s%-]", "")) or ""
end

local function FullName(name, realm)
    if SecretValue(name) or SecretValue(realm) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    if realm ~= nil and type(realm) ~= "string" then realm = nil end
    local short, fromName = name:match("^([^%-]+)%-(.+)$")
    if short then name, realm = short, fromName end
    realm = (realm and realm ~= "") and realm:gsub("[%s%-]", "") or PlayerRealm()
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    return name .. "-" .. realm, realm
end

local function ShortName(full)
    if SecretValue(full) or type(full) ~= "string" then return nil end
    return (full:match("^([^%-]+)")) or full
end

-- ── Saved data ──────────────────────────────────────────────────────────────

local function EnsureData()
    settings.players = type(settings.players) == "table" and settings.players or {}
    settings.realms  = type(settings.realms) == "table" and settings.realms or {}
    settings.npcs    = type(settings.npcs) == "table" and settings.npcs or {}
    settings.filters = type(settings.filters) == "table" and settings.filters or {}
end

local function PruneExpired()
    local now, removed = time(), 0
    for key, entry in pairs(settings.players) do
        if type(entry) == "table" and entry.expires and entry.expires > 0 and entry.expires <= now then
            settings.players[key] = nil
            removed = removed + 1
            if settings.syncBlizzard and C_FriendList and C_FriendList.DelIgnore then
                pcall(C_FriendList.DelIgnore, key)
            end
        end
    end
    if removed > 0 then
        print(PREFIX .. ("%d ignore(s) expired and were removed."):format(removed))
    end
end

local function IsIgnoredPlayer(full)
    if not full then return false end
    if settings.players[full] then return true, "Ignored player" end
    local realm = full:match("%-(.+)$")
    if realm and settings.realms[realm:lower()] then return true, "Ignored realm" end
    return false
end

function SetIgnored(full, on, note, days)
    if not full then return end
    if on then
        settings.players[full] = {
            note = (note and note ~= "") and note or nil,
            added = time(),
            expires = (days and days > 0) and (time() + days * 86400) or 0,
        }
        print(PREFIX .. ("now ignoring %s."):format(full))
        if settings.syncBlizzard and C_FriendList and C_FriendList.AddIgnore then
            inBlizzardSync = true
            pcall(C_FriendList.AddIgnore, full)
            C_Timer.After(1, function() inBlizzardSync = false end)
        end
    else
        settings.players[full] = nil
        print(PREFIX .. ("no longer ignoring %s."):format(full))
        if settings.syncBlizzard and C_FriendList and C_FriendList.DelIgnore then
            inBlizzardSync = true
            pcall(C_FriendList.DelIgnore, full)
            C_Timer.After(1, function() inBlizzardSync = false end)
        end
    end
    if RefreshManager then RefreshManager() end
end

-- ── Blizzard 50-slot Native Ignore Sync ─────────────────────────────────────

function SyncToBlizzard(silent)
    if not (settings and settings.syncBlizzard and C_FriendList and C_FriendList.GetNumIgnores and C_FriendList.AddIgnore) then
        return
    end

    inBlizzardSync = true

    -- Gather all ignored players sorted by most recently added
    local list = {}
    for full, entry in pairs(settings.players) do
        list[#list + 1] = {
            name = full,
            added = (type(entry) == "table" and entry.added) or 0,
        }
    end
    table.sort(list, function(a, b) return a.added > b.added end)

    local blizzIgnores = {}
    local num = C_FriendList.GetNumIgnores() or 0
    for i = 1, num do
        local bName = C_FriendList.GetIgnoreName(i)
        if bName and bName ~= "" and bName ~= _G.UNKNOWN then
            blizzIgnores[FullName(bName) or bName] = true
        end
    end

    local maxSlots = 50
    local currentCount = num
    local syncedCount = 0
    for i = 1, math.min(#list, maxSlots) do
        local name = list[i].name
        if not blizzIgnores[name] and currentCount < maxSlots then
            pcall(C_FriendList.AddIgnore, name)
            currentCount = currentCount + 1
            syncedCount = syncedCount + 1
        end
    end

    if not silent and syncedCount > 0 then
        print(PREFIX .. ("Synchronized %d player(s) to Blizzard ignore list."):format(syncedCount))
    end

    C_Timer.After(1.5, function() inBlizzardSync = false end)
end

-- ── The blocked log ─────────────────────────────────────────────────────────

local blockedLog = {}      -- newest last; session only, never saved

local function LogBlocked(reason, sender, text, event)
    blockedLog[#blockedLog + 1] = {
        time = time(), reason = reason, sender = sender, text = text, event = event,
    }
    if #blockedLog > LOG_LIMIT then table.remove(blockedLog, 1) end
    if manager and manager:IsShown() and manager.tab == "blocked" then RefreshManager() end
end

-- ── Matching & Filters ──────────────────────────────────────────────────────

local function Plain(msg)
    local text = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text:lower()
end

local function EscapePattern(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

local function TermMatches(plain, term, mode)
    if term == "" then return false end
    if mode == "pattern" then
        local ok, found = pcall(string.find, plain, term)
        return ok and found ~= nil
    elseif mode == "word" then
        return plain:find("%f[%w]" .. EscapePattern(term) .. "%f[%W]") ~= nil
    end
    return plain:find(term, 1, true) ~= nil
end

local function SplitTerms(terms)
    local out = {}
    for term in tostring(terms or ""):gmatch("[^,]+") do
        term = term:gsub("^%s+", ""):gsub("%s+$", "")
        if term ~= "" then out[#out + 1] = term:lower() end
    end
    return out
end

local function ScopeOf(event, channelBaseName)
    if event == "CHAT_MSG_CHANNEL" then
        local base = type(channelBaseName) == "string" and channelBaseName:lower() or ""
        if base:find("trade") or base:find("services") then return "trade" end
        return "channel"
    elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER" then
        return "whisper"
    elseif event == "CHAT_MSG_SAY" or event == "CHAT_MSG_YELL" or event == "CHAT_MSG_EMOTE" then
        return "say"
    end
    return "other"
end

local SCOPES = {
    { key = "all",     label = "All chat" },
    { key = "trade",   label = "Trade only" },
    { key = "channel", label = "All channels" },
    { key = "say",     label = "Say / Yell" },
    { key = "whisper", label = "Whispers" },
}

local function ScopeAllows(scope, lineScope)
    if scope == "all" or not scope then return true end
    if scope == "channel" then return lineScope == "channel" or lineScope == "trade" end
    return scope == lineScope
end

local function CustomFilterHit(plain, raw, lineScope)
    for _, filter in ipairs(settings.filters) do
        if filter.on ~= false and ScopeAllows(filter.scope, lineScope)
            and (not filter.needLink or raw:find("|H", 1, true)) then
            local terms = SplitTerms(filter.terms)
            if #terms > 0 then
                local hits = 0
                for _, term in ipairs(terms) do
                    if TermMatches(plain, term, filter.mode) then hits = hits + 1 end
                end
                if (filter.match == "all" and hits == #terms) or (filter.match ~= "all" and hits > 0) then
                    return "Filter: " .. (filter.name ~= "" and filter.name or "unnamed")
                end
            end
        end
    end
    return nil
end

-- ── Presets ─────────────────────────────────────────────────────────────────

local BOOST_SIGNALS = {
    "wts", "boost", "boosting", "carry", "carries", "pilot", "piloted", "selfplay",
    "self play", "vip", "unsaved", "pay in raid", "gold only", "going now",
    "cheapest", "discount", "discord", "armor stack", "loot funnel", "fully geared",
    "fast delivery", "funstart", "g2g", "playerauctions",
}

local function ScoreBoost(plain)
    local score = 0
    for _, signal in ipairs(BOOST_SIGNALS) do
        if plain:find(signal, 1, true) then score = score + 1 end
    end
    local _, prices = plain:gsub("%d[%d%.]*%s?[km]%f[%W]", "")
    if prices >= 2 then score = score + 2 elseif prices == 1 then score = score + 1 end
    return score
end

local function IsGuildRecruit(plain)
    local recruiting = plain:find("recruit", 1, true) or plain:find("looking for members", 1, true)
        or plain:find("lf members", 1, true) or plain:find("now accepting", 1, true)
    local guildish = plain:find("guild", 1, true) or plain:find("<[^>]+>")
        or plain:find("raiding team", 1, true) or plain:find("progression", 1, true)
    return recruiting and guildish
end

local function IsCommunityInvite(raw, plain)
    return raw:find("|Hclub", 1, true) ~= nil
        or (plain:find("community", 1, true) and plain:find("join", 1, true))
end

local function HasAsianScript(raw)
    return raw:find("[\227-\237][\128-\191][\128-\191]") ~= nil
end

local function CountIcons(raw)
    local _, braces = raw:gsub("{[^}]+}", "")
    local _, textures = raw:gsub("RaidTargetingIcon", "")
    return braces + textures
end

local function IsLinkJoke(raw, plain)
    local hasLink = raw:find("|Hitem:", 1, true) or raw:find("|Hspell:", 1, true)
        or raw:find("|Hachievement:", 1, true) or raw:find("|Htalent:", 1, true)
    if not hasLink then return false end

    -- Thunderfury: item 19019
    if raw:find("item:19019", 1, true) or plain:find("thunderfury", 1, true) then
        return true
    end
    -- Dirge: spell 23555
    if raw:find("spell:23555", 1, true) or plain:find("dirge", 1, true) then
        return true
    end
    -- Anal jokes with item or spell link
    if plain:find("%f[%w]anal%f[%W]") or plain:find("analan", 1, true) then
        return true
    end
    -- Murloc spam
    if plain:find("murloc", 1, true) then
        return true
    end
    return false
end

local POLITICAL_WORDS = {
    "trump", "biden", "putin", "zelensky", "democrat", "republican", "libtard",
    "maga", "conservatives", "liberals", "socialism", "communism", "election",
}

local function IsPolitical(plain)
    for _, word in ipairs(POLITICAL_WORDS) do
        if plain:find(word, 1, true) then return true end
    end
    return false
end

local recentLines, recentCount = {}, 0

local function IsRepeat(sender, plain, now)
    recentCount = recentCount + 1
    if recentCount > 500 then
        recentCount = 0
        for name, seen in pairs(recentLines) do
            if now - seen.at >= REPEAT_WINDOW then recentLines[name] = nil end
        end
    end

    local last = recentLines[sender]
    recentLines[sender] = { text = plain, at = now }
    return last and last.text == plain and (now - last.at) < REPEAT_WINDOW
end

local function PresetHit(raw, plain, sender, lineScope, now)
    if settings.presetBoost and (lineScope == "trade" or lineScope == "channel" or lineScope == "say")
        and ScoreBoost(plain) >= 3 then
        return "Preset: boosting / selling"
    end
    if settings.presetGuild and IsGuildRecruit(plain) then return "Preset: guild recruitment" end
    if settings.presetCommunity and IsCommunityInvite(raw, plain) then return "Preset: community invite" end
    if settings.presetAsian and HasAsianScript(raw) then return "Preset: Asian-script text" end
    if settings.presetIcons and CountIcons(raw) >= 3 then return "Preset: raid icon spam" end
    if settings.presetJokes and IsLinkJoke(raw, plain) then return "Preset: link joke spam" end
    if settings.presetPolitics and (lineScope == "channel" or lineScope == "trade" or lineScope == "say")
        and IsPolitical(plain) then
        return "Preset: political spam"
    end
    if settings.presetRepeat and lineScope ~= "whisper" and IsRepeat(sender, plain, now) then
        return "Preset: repeated message"
    end
    return nil
end

-- ── Protected Channels & Friends ────────────────────────────────────────────

local GUILD_EVENTS = { CHAT_MSG_GUILD = true, CHAT_MSG_OFFICER = true, CHAT_MSG_GUILD_ACHIEVEMENT = true }
local GROUP_EVENTS = {
    CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true, CHAT_MSG_RAID = true,
    CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}
local NPC_EVENTS = {
    CHAT_MSG_MONSTER_SAY = true, CHAT_MSG_MONSTER_YELL = true, CHAT_MSG_MONSTER_EMOTE = true,
    CHAT_MSG_MONSTER_WHISPER = true, CHAT_MSG_MONSTER_PARTY = true, CHAT_MSG_RAID_BOSS_EMOTE = true,
}

local function Protected(event, full, guid)
    if settings.keepGuild and GUILD_EVENTS[event] then return true end
    if settings.keepGroup and GROUP_EVENTS[event] then return true end
    if settings.keepFriends and guid and guid ~= "" then
        if C_FriendList and C_FriendList.IsFriend then
            local ok, friend = pcall(C_FriendList.IsFriend, guid)
            if ok and friend then return true end
        end
        if C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
            local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
            if ok and info then return true end
        end
    end
    if settings.keepGuild and guid and IsGuildMember then
        local ok, member = pcall(IsGuildMember, guid)
        if ok and member then return true end
    end
    return false
end

-- ── Core Chat Filter Engine ─────────────────────────────────────────────────

local decisions, decisionCount = {}, 0

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Decide(event, msg, author, channelBaseName, guid)
    if type(msg) ~= "string" then return false end

    -- System messages (suppress Blizzard ignore spam while syncing)
    if event == "CHAT_MSG_SYSTEM" then
        if inBlizzardSync then
            if msg == ERR_IGNORE_FULL or msg == ERR_IGNORE_NOT_FOUND or msg == ERR_FRIEND_ERROR then
                return true, "System sync notice", "Blizzard"
            end
            if ERR_IGNORE_ADDED_S and msg:find(ERR_IGNORE_ADDED_S:gsub("%%s", ".-")) then
                return true, "System sync notice", "Blizzard"
            end
            if ERR_IGNORE_REMOVED_S and msg:find(ERR_IGNORE_REMOVED_S:gsub("%%s", ".-")) then
                return true, "System sync notice", "Blizzard"
            end
            if ERR_IGNORE_ALREADY_S and msg:find(ERR_IGNORE_ALREADY_S:gsub("%%s", ".-")) then
                return true, "System sync notice", "Blizzard"
            end
        end
        return false
    end

    if NPC_EVENTS[event] then
        if type(author) == "string" and settings.npcs[author:lower()] then
            return true, "Ignored NPC", author
        end
        return false
    end

    local full = FullName(author)
    if not full then return false end

    local me = UnitName("player")
    if not SecretValue(me) and ShortName(full) == me
        and full:match("%-(.+)$") == PlayerRealm() then
        return false
    end

    local ignored, why = IsIgnoredPlayer(full)
    if ignored then return true, why, full end

    if Protected(event, full, guid) then return false end

    local lineScope = ScopeOf(event, channelBaseName)
    if settings.keepWhispers and lineScope == "whisper" then return false end

    local plain = Plain(msg)
    local reason = CustomFilterHit(plain, msg, lineScope)
        or PresetHit(msg, plain, full, lineScope, GetTime())
    if reason then return true, reason, full end
    return false
end

local function ChatFilter(_, event, msg, author, _, _, _, _, _, _, channelBaseName, _, lineID, guid)
    if not settings or settings.enabled == false then return false end
    if IsSecret(msg) or IsSecret(author) then return false end
    if IsSecret(lineID) then lineID = nil end
    if IsSecret(channelBaseName) then channelBaseName = nil end
    if IsSecret(guid) then guid = nil end

    if lineID and lineID > 0 and decisions[lineID] ~= nil then
        return decisions[lineID]
    end

    local ok, block, reason, sender = pcall(Decide, event, msg, author, channelBaseName, guid)
    if not ok then block = false end

    if lineID and lineID > 0 then
        decisions[lineID] = block and true or false
        decisionCount = decisionCount + 1
        if decisionCount > 1000 then decisions, decisionCount = {}, 0 end
    end

    if block and reason ~= "System sync notice" then
        LogBlocked(reason, sender or tostring(author), msg, event)
    end
    return block and true or false
end

local CHAT_EVENTS = {
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_AFK", "CHAT_MSG_DND",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function AddFilter(event, fn)
    if ChatFrame_AddMessageEventFilter then
        return ChatFrame_AddMessageEventFilter(event, fn)
    elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        return ChatFrameUtil.AddMessageEventFilter(event, fn)
    end
end

-- ── Social Protection (Duels, Invites, Trade, Group Alerts) ──────────────────

local warnedInGroup = {}

local function CheckGroup()
    if not settings.warnGroup then return end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if count == 0 then wipe(warnedInGroup) return end

    local prefix = IsInRaid() and "raid" or "party"
    for index = 1, count do
        local unit = prefix .. index
        local name, realm = UnitName(unit)
        local full = name and FullName(name, realm)
        if full and IsIgnoredPlayer(full) and not warnedInGroup[full] then
            warnedInGroup[full] = true
            local entry = settings.players[full]
            local note = type(entry) == "table" and entry.note
            print(PREFIX .. ("|cffff5555%s is in your group|r and on your ignore list%s.")
                :format(full, note and (" (" .. note .. ")") or ""))
            if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
end

local social = CreateFrame("Frame")
social:SetScript("OnEvent", function(_, event, name, ...)
    if not settings or settings.enabled == false then return end

    if event == "DUEL_REQUESTED" and settings.declineDuels then
        local full = FullName(name)
        if full and IsIgnoredPlayer(full) then
            CancelDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
            LogBlocked("Declined duel", full, "Duel request", event)
        end
    elseif event == "PARTY_INVITE_REQUEST" and settings.declineInvites then
        local full = FullName(name)
        if full and IsIgnoredPlayer(full) then
            DeclineGroup()
            StaticPopup_Hide("PARTY_INVITE")
            LogBlocked("Declined invite", full, "Group invite", event)
        end
    elseif event == "GUILD_INVITE_REQUEST" and settings.declineGuild then
        local full = FullName(name)
        if full and IsIgnoredPlayer(full) then
            DeclineGuild()
            StaticPopup_Hide("GUILD_INVITE")
            LogBlocked("Declined guild invite", full, "Guild invite", event)
        end
    elseif event == "TRADE_REQUEST" and settings.declineTrade then
        local full = FullName(name)
        if full and IsIgnoredPlayer(full) then
            CancelTrade()
            StaticPopup_Hide("TRADE")
            LogBlocked("Declined trade", full, "Trade request", event)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CheckGroup()
    end
end)

local SOCIAL_EVENTS = {
    "DUEL_REQUESTED", "PARTY_INVITE_REQUEST", "GUILD_INVITE_REQUEST",
    "TRADE_REQUEST", "GROUP_ROSTER_UPDATE",
}

local function SetSocialEvents(on)
    for _, event in ipairs(SOCIAL_EVENTS) do
        if on then social:RegisterEvent(event) else social:UnregisterEvent(event) end
    end
end

-- ── LFG Dungeon & Raid Finder Hooks (from GlobalIgnoreList) ──────────────────

local function HighlightLFGIgnore(self)
    if not (settings and settings.enabled and settings.lfgHighlight) then return end
    if not self.resultID or not C_LFGList or not C_LFGList.HasSearchResultInfo then return end
    local ok, hasInfo = pcall(C_LFGList.HasSearchResultInfo, self.resultID)
    if not (ok and hasInfo) then return end
    local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, self.resultID)
    if not (okInfo and info and info.leaderName) then return end
    local full = FullName(info.leaderName)
    if full and IsIgnoredPlayer(full) then
        if self.Name then
            self.Name:SetTextColor(1, 0.25, 0.25)
        end
    end
end

local function TooltipLFGIgnore(self)
    if not (settings and settings.enabled and settings.lfgHighlight) then return end
    if not self.resultID or not C_LFGList or not C_LFGList.HasSearchResultInfo then return end
    local ok, hasInfo = pcall(C_LFGList.HasSearchResultInfo, self.resultID)
    if not (ok and hasInfo) then return end
    local okInfo, info = pcall(C_LFGList.GetSearchResultInfo, self.resultID)
    if not (okInfo and info and info.leaderName) then return end
    local full = FullName(info.leaderName)
    if full and IsIgnoredPlayer(full) then
        local entry = settings.players[full]
        local note = type(entry) == "table" and entry.note
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffff3333[OxedHub] Ignored Group Leader!|r")
        if note and note ~= "" then
            GameTooltip:AddLine("|cffffd100Note:|r " .. note, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end
end

local lfgHooked = false
local function HookLFG()
    if lfgHooked then return end
    lfgHooked = true
    if hooksecurefunc then
        pcall(hooksecurefunc, "LFGListSearchEntry_Update", HighlightLFGIgnore)
        pcall(hooksecurefunc, "LFGListSearchEntry_OnEnter", TooltipLFGIgnore)
    end
end

-- ── Right-Click Menus (Retail 11.x Menu API) ────────────────────────────────

local function MenuTarget(contextData, owner)
    if type(contextData) == "table" then
        if not SecretValue(contextData) and (not canaccesstable or canaccesstable(contextData)) then
            if contextData.name then
                return FullName(contextData.name, contextData.server)
            end

            -- LFG search result entry
            if contextData.resultID and C_LFGList and C_LFGList.GetSearchResultInfo then
                local ok, info = pcall(C_LFGList.GetSearchResultInfo, contextData.resultID)
                if ok and info and info.leaderName then
                    return FullName(info.leaderName)
                end
            end

            -- LFG applicant entry
            if contextData.applicantID and C_LFGList and C_LFGList.GetApplicantInfo then
                local ok, info = pcall(C_LFGList.GetApplicantInfo, contextData.applicantID)
                if ok and info and info.name then
                    return FullName(info.name)
                end
            end

            local unit = contextData.unit
            if unit and not SecretValue(unit) then
                local ok, isPlayer = pcall(UnitIsPlayer, unit)
                if ok and not SecretValue(isPlayer) and isPlayer then
                    local okName, name, realm = pcall(UnitName, unit)
                    if okName then return FullName(name, realm) end
                end
            end
        end
    end

    if owner and owner.resultID and C_LFGList and C_LFGList.GetSearchResultInfo then
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, owner.resultID)
        if ok and info and info.leaderName then
            return FullName(info.leaderName)
        end
    end

    return nil
end

local MENU_TAGS = {
    "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_LFG_FRAME_SEARCH_ENTRY", "MENU_LFG_FRAME_APPLICANT",
}

local function InstallMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs(MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, function(owner, root, contextData)
            if not settings or settings.enabled == false then return end
            local full = MenuTarget(contextData, owner)
            if not full then return end
            local me = UnitName("player")
            if SecretValue(me) or ShortName(full) == me then return end
            local ignored = settings.players[full] ~= nil
            root:CreateDivider()
            root:CreateButton(ignored and "Unignore (OxedHub)" or "Ignore (OxedHub)", function()
                SetIgnored(full, not ignored)
            end)
        end)
    end
end

-- ── Manager Window UI ───────────────────────────────────────────────────────

local ROW_HEIGHT = 22

local function MakeButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function MakeInput(parent, width, hint)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetSize(width, 22)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    if hint then
        box.hint = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        box.hint:SetPoint("LEFT", box, "LEFT", 4, 0)
        box.hint:SetText(hint)
        box:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(self:GetText() == "")
        end)
    end
    return box
end

local function MakeCycle(parent, width, choices, onChange)
    local button = MakeButton(parent, "", width)
    button.choices, button.index = choices, 1
    function button:SetValue(key)
        for index, choice in ipairs(self.choices) do
            if choice.key == key then
                self.index = index
                self:SetText(choice.label)
                return
            end
        end
        self.index = 1
        self:SetText(self.choices[1] and self.choices[1].label or "")
    end
    function button:GetValue()
        local choice = self.choices[self.index]
        return choice and choice.key
    end
    button:SetScript("OnClick", function(self)
        self.index = (self.index % #self.choices) + 1
        self:SetText(self.choices[self.index].label)
        if onChange then onChange(self:GetValue()) end
    end)
    button:SetValue(choices[1] and choices[1].key)
    return button
end

local function GetRow(index)
    local rows = manager.rows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Button", nil, manager.content)
    row:SetHeight(ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.07)
    highlight:Hide()
    row.highlight = highlight

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(20, 20)
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.delete = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.delete:SetSize(22, 18)
    row.delete:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.delete:SetText("x")

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.right:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
    row.right:SetJustifyH("RIGHT")

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)
    row.left:SetJustifyH("LEFT")
    row.left:SetWordWrap(false)

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipTitle or "")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        self.highlight:Hide()
        GameTooltip:Hide()
    end)

    rows[index] = row
    return row
end

local function DrawRows(items)
    local y = 0
    for index, item in ipairs(items) do
        local row = GetRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", manager.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", manager.content, "TOPRIGHT", 0, -y)
        row.left:SetText(item.left or "")
        row.right:SetText(item.right or "")
        row.tooltip, row.tooltipTitle = item.tooltip, item.tooltipTitle

        row.check:SetShown(item.onCheck ~= nil)
        if item.onCheck then
            row.check:SetChecked(item.checked and true or false)
            row.check:SetScript("OnClick", function(self) item.onCheck(self:GetChecked()) end)
        end
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", item.onCheck and row.check or row, item.onCheck and "RIGHT" or "LEFT",
            item.onCheck and 2 or 6, 0)
        row.left:SetPoint("RIGHT", row.right, "LEFT", -8, 0)

        row.delete:SetShown(item.onDelete ~= nil)
        row.delete:SetScript("OnClick", item.onDelete)
        row:SetScript("OnClick", item.onClick)
        row:Show()
        y = y + ROW_HEIGHT
    end
    for index = #items + 1, #manager.rows do manager.rows[index]:Hide() end
    manager.content:SetHeight(math.max(1, y))
    manager.content:SetWidth(manager.scroll:GetWidth())
end

-- ── Tab: Ignore ─────────────────────────────────────────────────────────────

local IGNORE_KINDS = {
    { key = "player", label = "Player" },
    { key = "realm",  label = "Realm" },
    { key = "npc",    label = "NPC" },
}

local EXPIRY_CHOICES = {}
for _, days in ipairs(EXPIRY_STEPS) do
    EXPIRY_CHOICES[#EXPIRY_CHOICES + 1] = {
        key = days, label = days == 0 and "Never expires" or ("Expires in " .. days .. "d"),
    }
end

-- The game's own note for an ignored player (12.x lets you write one when you
-- ignore someone). Its function's name is not settled across builds, so the
-- friend list's ignore functions are tried, by name and by list position.
local function PlainText(value)
    if type(value) ~= "string" or (issecretvalue and issecretvalue(value)) or value == "" then return nil end
    return value
end

local function GameIgnoreNote(full)
    if not C_FriendList then return nil end
    local short = full and full:match("^([^%-]+)")
    local index
    if C_FriendList.GetNumIgnores and C_FriendList.GetIgnoreName then
        for i = 1, C_FriendList.GetNumIgnores() or 0 do
            local okN, name = pcall(C_FriendList.GetIgnoreName, i)
            if okN and (name == full or name == short) then index = i; break end
        end
    end
    for key, fn in pairs(C_FriendList) do
        if type(fn) == "function" and key:find("^Get") and key:find("Ignore") then
            for _, arg in ipairs({ full, short, index }) do
                if arg ~= nil then
                    local ok, result = pcall(fn, arg)
                    if ok then
                        if key:find("Note") and PlainText(result) then return result end
                        if type(result) == "table" then
                            local note = PlainText(result.note) or PlainText(result.notes)
                            if note then return note end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function DrawIgnoreTab()
    local items = {}
    local filterText = manager.searchBox and manager.searchBox:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

    local names = {}
    for full in pairs(settings.players) do
        local entry = settings.players[full]
        local note = (type(entry) == "table" and entry.note) or ""
        if filterText == "" or full:lower():find(filterText, 1, true) or note:lower():find(filterText, 1, true) then
            names[#names + 1] = full
        end
    end
    table.sort(names)

    for _, full in ipairs(names) do
        local entry = settings.players[full]
        local right = ""
        if type(entry) == "table" and entry.expires and entry.expires > 0 then
            right = ("|cff55ff55%dd left|r"):format(math.max(0, math.ceil((entry.expires - time()) / 86400)))
        else
            right = "|cff888888Permanent|r"
        end
        local note = (type(entry) == "table" and entry.note) or GameIgnoreNote(full)
        items[#items + 1] = {
            left = "|cffffffff" .. full .. "|r" .. (note and ("  |cffffd100(" .. note .. ")|r") or ""),
            right = right,
            tooltipTitle = full,
            tooltip = (type(entry) == "table" and entry.added)
                and ("Added " .. date("%Y-%m-%d", entry.added) .. (note and ("\nNote: " .. note) or "")) or nil,
            onDelete = function() SetIgnored(full, false) end,
        }
    end

    for realm in pairs(settings.realms) do
        if filterText == "" or realm:lower():find(filterText, 1, true) then
            items[#items + 1] = {
                left = "|cff00ccff[Realm]|r  " .. realm, right = "whole realm",
                onDelete = function() settings.realms[realm] = nil; RefreshManager() end,
            }
        end
    end

    for npc in pairs(settings.npcs) do
        if filterText == "" or npc:lower():find(filterText, 1, true) then
            items[#items + 1] = {
                left = "|cffffaa00[NPC]|r  " .. npc, right = "monster/npc",
                onDelete = function() settings.npcs[npc] = nil; RefreshManager() end,
            }
        end
    end

    if #items == 0 then
        items[1] = { left = "|cff9d9d9dNo matching ignores found.|r" }
    end
    DrawRows(items)

    local totalPlayers = 0
    for _ in pairs(settings.players) do totalPlayers = totalPlayers + 1 end
    manager.count:SetText(("%d player(s) ignored"):format(totalPlayers))
end

local function AddIgnoreFromInputs()
    local panel = manager.ignorePanel
    local text = panel.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end

    local kind = panel.kind:GetValue()
    if kind == "realm" then
        settings.realms[text:gsub("[%s%-]", ""):lower()] = true
        print(PREFIX .. ("now ignoring everyone from realm %s."):format(text))
    elseif kind == "npc" then
        settings.npcs[text:lower()] = true
        print(PREFIX .. ("now ignoring the NPC %s."):format(text))
    else
        SetIgnored(FullName(text), true, panel.note:GetText(), panel.expiry:GetValue())
    end
    panel.name:SetText("")
    panel.note:SetText("")
    RefreshManager()
end

-- ── Tab: Filters ────────────────────────────────────────────────────────────

local PRESETS = {
    { key = "presetBoost",     label = "Boosting and gold selling",       tip = "Adverts for carries, piloting, VIP runs and gold sales." },
    { key = "presetGuild",     label = "Guild recruitment",               tip = "Messages recruiting for a guild or raiding team." },
    { key = "presetCommunity", label = "Community invites",               tip = "Links inviting you to join a community or club." },
    { key = "presetAsian",     label = "Asian-script text",               tip = "Chinese, Japanese and Korean text." },
    { key = "presetIcons",     label = "Raid icon spam",                  tip = "Lines using three or more raid target icons." },
    { key = "presetJokes",     label = "Link jokes (Thunderfury, Anal)",  tip = "Catches Thunderfury, Dirge, Anal and Murloc spam with links." },
    { key = "presetPolitics",  label = "Political flamewars",             tip = "Political arguments and keywords in public chat." },
    { key = "presetRepeat",    label = "Repeated messages",               tip = "The same sender posting the same line again within 90 seconds." },
}

local MODES = {
    { key = "contains", label = "Part of a word" },
    { key = "word",     label = "Whole word" },
    { key = "pattern",  label = "Lua pattern" },
}
local MATCHES = {
    { key = "any", label = "Any term" },
    { key = "all", label = "All terms" },
}
local LINKS = {
    { key = false, label = "Any message" },
    { key = true,  label = "Only with a link" },
}

local function SaveFilterFromInputs()
    local panel = manager.filterPanel
    local terms = panel.terms:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    if terms == "" then return end

    local index = manager.editing or (#settings.filters + 1)
    settings.filters[index] = {
        name     = panel.name:GetText():gsub("^%s+", ""):gsub("%s+$", ""),
        terms    = terms,
        mode     = panel.mode:GetValue(),
        match    = panel.match:GetValue(),
        scope    = panel.scope:GetValue(),
        needLink = panel.link:GetValue() and true or false,
        on       = settings.filters[index] and settings.filters[index].on or true,
    }
    manager.editing = nil
    panel.name:SetText("")
    panel.terms:SetText("")
    panel.save:SetText("Add filter")
    RefreshManager()
end

local function EditFilter(index)
    local filter = settings.filters[index]
    if not filter then return end
    manager.editing = index
    local panel = manager.filterPanel
    panel.name:SetText(filter.name or "")
    panel.terms:SetText(filter.terms or "")
    panel.mode:SetValue(filter.mode or "contains")
    panel.match:SetValue(filter.match or "any")
    panel.scope:SetValue(filter.scope or "all")
    panel.link:SetValue(filter.needLink and true or false)
    panel.save:SetText("Save filter")
    panel.name:SetFocus()
end

local function DrawFiltersTab()
    local items = {}
    for _, preset in ipairs(PRESETS) do
        items[#items + 1] = {
            left = "|cffffffff" .. preset.label .. "|r",
            right = "|cff888888preset|r",
            checked = settings[preset.key] and true or false,
            onCheck = function(checked) settings[preset.key] = checked end,
            tooltipTitle = preset.label,
            tooltip = preset.tip,
        }
    end
    for index, filter in ipairs(settings.filters) do
        local summary = filter.name ~= "" and filter.name or filter.terms
        items[#items + 1] = {
            left = "|cff00ff00Filter:|r " .. summary,
            right = filter.scope or "all",
            checked = filter.on ~= false,
            onCheck = function(checked) filter.on = checked end,
            tooltipTitle = filter.name ~= "" and filter.name or "Custom filter",
            tooltip = "Terms: " .. filter.terms .. "\nClick to edit this filter.",
            onClick = function() EditFilter(index) end,
            onDelete = function()
                table.remove(settings.filters, index)
                if manager.editing == index then manager.editing = nil end
                RefreshManager()
            end,
        }
    end
    DrawRows(items)
    manager.count:SetText(("%d custom filter(s)"):format(#settings.filters))
end

-- ── Tab: Blocked ────────────────────────────────────────────────────────────

local function DrawBlockedTab()
    local items = {}
    local filterText = manager.searchBox and manager.searchBox:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "") or ""

    for i = #blockedLog, 1, -1 do
        local entry = blockedLog[i]
        local sender = entry.sender or "Unknown"
        local text = entry.text or ""
        local reason = entry.reason or "Filtered"

        if filterText == "" or sender:lower():find(filterText, 1, true)
            or text:lower():find(filterText, 1, true) or reason:lower():find(filterText, 1, true) then
            items[#items + 1] = {
                left = "|cffff5555[" .. reason .. "]|r  " .. sender .. ": |cffbbbbbb" .. text:sub(1, 60) .. "|r",
                right = date("%H:%M:%S", entry.time),
                tooltipTitle = sender .. " (" .. date("%H:%M:%S", entry.time) .. ")",
                tooltip = "|cffffd100Reason:|r " .. reason .. "\n|cffffffff" .. text .. "\n\n|cff00ff00Click to add " .. sender .. " to ignore list.|r",
                onClick = function()
                    local full = FullName(sender)
                    if full then SetIgnored(full, true, "Blocked: " .. reason) end
                end,
            }
        end
    end
    if #items == 0 then
        items[1] = { left = "|cff9d9d9dNo blocked messages in this session yet.|r" }
    end
    DrawRows(items)
    manager.count:SetText(("%d blocked this session"):format(#blockedLog))
end

-- ── Building the Manager Window ─────────────────────────────────────────────

local TABS = {
    { key = "ignore",  label = "Ignore List" },
    { key = "filters", label = "Spam Filters" },
    { key = "blocked", label = "Blocked History" },
}

function RefreshManager()
    if not (manager and manager:IsShown()) then return end
    for _, button in ipairs(manager.tabButtons) do
        if button.key == manager.tab then button:LockHighlight() else button:UnlockHighlight() end
    end
    manager.ignorePanel:SetShown(manager.tab == "ignore")
    manager.filterPanel:SetShown(manager.tab == "filters")
    manager.blockedPanel:SetShown(manager.tab == "blocked")
    manager.searchBox:SetShown(manager.tab ~= "filters")

    if manager.tab == "filters" then
        DrawFiltersTab()
    elseif manager.tab == "blocked" then
        DrawBlockedTab()
    else
        DrawIgnoreTab()
    end
end

local function BuildIgnorePanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    panel.kind = MakeCycle(panel, 75, IGNORE_KINDS)
    panel.kind:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)

    panel.name = MakeInput(panel, 180, "Name-Realm, realm or NPC")
    panel.name:SetPoint("LEFT", panel.kind, "RIGHT", 8, 0)
    panel.name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); AddIgnoreFromInputs() end)

    panel.note = MakeInput(panel, 140, "Note (optional)")
    panel.note:SetPoint("LEFT", panel.name, "RIGHT", 8, 0)

    panel.expiry = MakeCycle(panel, 120, EXPIRY_CHOICES)
    panel.expiry:SetPoint("TOPLEFT", panel.kind, "BOTTOMLEFT", 0, -6)

    local add = MakeButton(panel, "Add", 65, AddIgnoreFromInputs)
    add:SetPoint("LEFT", panel.expiry, "RIGHT", 8, 0)

    local targetBtn = MakeButton(panel, "Add Target", 85, function()
        if not UnitExists("target") then
            print(PREFIX .. "No target selected.")
            return
        end
        if not UnitIsPlayer("target") then
            local npcName = UnitName("target")
            if npcName and npcName ~= "" then
                settings.npcs[npcName:lower()] = true
                print(PREFIX .. ("now ignoring NPC %s."):format(npcName))
                RefreshManager()
            end
            return
        end
        local name, realm = UnitName("target")
        local full = name and FullName(name, realm)
        if full then
            local note = panel.note:GetText()
            local days = panel.expiry:GetValue()
            SetIgnored(full, true, note, days)
            panel.name:SetText("")
            panel.note:SetText("")
            RefreshManager()
        end
    end)
    targetBtn:SetPoint("LEFT", add, "RIGHT", 6, 0)

    local pruneBtn = MakeButton(panel, "Prune (90d+)", 95, function()
        local now = time()
        local pruned = 0
        for key, entry in pairs(settings.players) do
            if type(entry) == "table" and entry.added and (now - entry.added) >= (90 * 86400) then
                settings.players[key] = nil
                pruned = pruned + 1
                if settings.syncBlizzard and C_FriendList and C_FriendList.DelIgnore then
                    pcall(C_FriendList.DelIgnore, key)
                end
            end
        end
        if pruned > 0 then
            print(PREFIX .. ("Pruned %d ignore(s) older than 90 days."):format(pruned))
            RefreshManager()
        else
            print(PREFIX .. "No ignores older than 90 days found.")
        end
    end)
    pruneBtn:SetPoint("LEFT", targetBtn, "RIGHT", 6, 0)

    local syncBtn = MakeButton(panel, "Sync Blizzard", 95, function()
        SyncToBlizzard(false)
    end)
    syncBtn:SetPoint("LEFT", pruneBtn, "RIGHT", 6, 0)

    return panel
end

local function BuildFilterPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    panel.name = MakeInput(panel, 120, "Filter name")
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, 0)

    panel.terms = MakeInput(panel, 320, "Words to catch, separated by commas")
    panel.terms:SetPoint("LEFT", panel.name, "RIGHT", 8, 0)

    panel.mode = MakeCycle(panel, 110, MODES)
    panel.mode:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -28)
    panel.match = MakeCycle(panel, 80, MATCHES)
    panel.match:SetPoint("LEFT", panel.mode, "RIGHT", 4, 0)
    panel.scope = MakeCycle(panel, 100, SCOPES)
    panel.scope:SetPoint("LEFT", panel.match, "RIGHT", 4, 0)
    panel.link = MakeCycle(panel, 110, LINKS)
    panel.link:SetPoint("LEFT", panel.scope, "RIGHT", 4, 0)

    panel.save = MakeButton(panel, "Add filter", 80, SaveFilterFromInputs)
    panel.save:SetPoint("LEFT", panel.link, "RIGHT", 4, 0)

    local new = MakeButton(panel, "New", 50, function() manager.editing = nil; RefreshManager() end)
    new:SetPoint("LEFT", panel.save, "RIGHT", 4, 0)

    -- Live filter tester
    panel.testBox = MakeInput(panel, 360, "Test a phrase here to verify filter matching...")
    panel.testBox:SetPoint("TOPLEFT", panel.mode, "BOTTOMLEFT", 6, -8)

    panel.testResult = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.testResult:SetPoint("LEFT", panel.testBox, "RIGHT", 10, 0)

    panel.testBox:SetScript("OnTextChanged", function(self)
        if self.hint then self.hint:SetShown(self:GetText() == "") end
        local text = self:GetText()
        if text == "" then
            panel.testResult:SetText("")
        else
            local plain = Plain(text)
            local hit = CustomFilterHit(plain, text, "trade")
                or PresetHit(text, plain, "TestSender-Realm", "trade", GetTime())
            if hit then
                panel.testResult:SetText("|cffff4444Blocks: " .. hit .. "|r")
            else
                panel.testResult:SetText("|cff44ff44Allows message|r")
            end
        end
    end)

    return panel
end

local function BuildBlockedPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    local clear = MakeButton(panel, "Clear log", 90, function()
        wipe(blockedLog)
        RefreshManager()
    end)
    clear:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    hint:SetText("Click any blocked row to ignore the sender. History is session-only.")
    return panel
end

local function BuildManager()
    if manager then return manager end

    manager = CreateFrame("Frame", "OxedHubChatFilterWindow", UIParent, "BasicFrameTemplate")
    manager:SetSize(680, 500)
    manager:SetPoint("CENTER")
    manager:SetFrameStrata("FULLSCREEN_DIALOG")
    manager:SetFrameLevel(210)
    manager:SetToplevel(true)
    manager:SetClampedToScreen(true)
    manager:EnableMouse(true)
    manager:SetMovable(true)
    manager:RegisterForDrag("LeftButton")
    manager:SetScript("OnDragStart", manager.StartMoving)
    manager:SetScript("OnDragStop", manager.StopMovingOrSizing)
    manager.tab = "ignore"
    manager.rows = {}

    local title = manager:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", manager.TitleBg, "CENTER", 0, 0)
    title:SetText("Chat Filter & Global Ignore")

    manager.tabButtons = {}
    local previous
    for _, tabInfo in ipairs(TABS) do
        local button = MakeButton(manager, tabInfo.label, 110, function()
            manager.tab = tabInfo.key
            manager.editing = nil
            manager.scroll:SetVerticalScroll(0)
            RefreshManager()
        end)
        button.key = tabInfo.key
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", manager, "TOPLEFT", 14, -30)
        end
        previous = button
        manager.tabButtons[#manager.tabButtons + 1] = button
    end

    -- Live Search EditBox
    manager.searchBox = MakeInput(manager, 170, "Search ignores...")
    manager.searchBox:SetPoint("TOPRIGHT", manager, "TOPRIGHT", -20, -31)
    manager.searchBox:SetScript("OnTextChanged", function(self)
        if self.hint then self.hint:SetShown(self:GetText() == "") end
        RefreshManager()
    end)

    manager.count = manager:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    manager.count:SetPoint("TOPRIGHT", manager.searchBox, "BOTTOMRIGHT", 0, -4)

    local scroll = CreateFrame("ScrollFrame", "OxedHubChatFilterScroll", manager, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", manager, "TOPLEFT", 14, -66)
    scroll:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -34, 88)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(600, 1)
    scroll:SetScrollChild(content)
    manager.scroll, manager.content = scroll, content

    local bottom = CreateFrame("Frame", nil, manager)
    bottom:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
    bottom:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -14, 10)

    manager.ignorePanel  = BuildIgnorePanel(bottom)
    manager.filterPanel  = BuildFilterPanel(bottom)
    manager.blockedPanel = BuildBlockedPanel(bottom)

    return manager
end

function OpenManager(tab)
    if not settings then return end
    BuildManager()
    if tab then manager.tab = tab end
    manager:Show()
    manager:Raise()
    RefreshManager()
end

-- ── Switching on ────────────────────────────────────────────────────────────

local function Install()
    if installed then return end
    installed = true

    local filter = OxedHub.Profiler and OxedHub.Profiler:Wrap("Chat Filter: message", ChatFilter)
        or ChatFilter
    for _, event in ipairs(CHAT_EVENTS) do
        AddFilter(event, filter)
    end
    InstallMenus()
    HookLFG()

    SLASH_OXEDCHATFILTER1 = "/oxfilter"
    SLASH_OXEDCHATFILTER2 = "/chatfilter"
    SLASH_OXEDCHATFILTER3 = "/gi"
    SlashCmdList["OXEDCHATFILTER"] = function(argument)
        local tab = argument and argument:match("^%s*(%a+)")
        OpenManager(tab and tab:lower() or nil)
    end

    SLASH_OXEDIGNORE1 = "/oxignore"
    SLASH_OXEDIGNORE2 = "/gignore"
    SlashCmdList["OXEDIGNORE"] = function(argument)
        local name, note = tostring(argument or ""):match("^%s*(%S+)%s*(.-)%s*$")
        if not name then
            print(PREFIX .. "usage: /oxignore Name-Realm [note]")
            return
        end
        local full = FullName(name)
        SetIgnored(full, not settings.players[full], note)
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.chatfilter
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.chatfilter = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
    EnsureData()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Chat Filter & Global Ignore", 450, 520)
        optionsWindow:AddCheckbox(settings, "keepGuild", "Never filter guild",
            "Guild and officer chat, and guild members anywhere, are never hidden by filters.")
        optionsWindow:AddCheckbox(settings, "keepGroup", "Never filter your group",
            "Party, raid and instance chat are never hidden by filters.")
        optionsWindow:AddCheckbox(settings, "keepFriends", "Never filter friends",
            "Friends and Battle.net friends are never hidden by filters.")
        optionsWindow:AddCheckbox(settings, "keepWhispers", "Never word-filter whispers",
            "Whispers skip the word filters and presets. Ignored players are still hidden.")
        optionsWindow:AddCheckbox(settings, "declineDuels", "Decline duels from ignored players")
        optionsWindow:AddCheckbox(settings, "declineInvites", "Decline group invites from ignored players")
        optionsWindow:AddCheckbox(settings, "declineGuild", "Decline guild invites from ignored players")
        optionsWindow:AddCheckbox(settings, "declineTrade", "Decline trade requests from ignored players")
        optionsWindow:AddCheckbox(settings, "warnGroup", "Warn when an ignored player joins your group")
        optionsWindow:AddCheckbox(settings, "lfgHighlight", "Highlight ignored leaders in LFG / Group Finder",
            "Colors ignored group leaders red in M+ and Raid Finder, and displays your note in the tooltip.")
        optionsWindow:AddCheckbox(settings, "syncBlizzard", "Sync top 50 to Blizzard ignore list",
            "Keeps the 50 most recent ignores in Blizzard's native list for engine-level whisper and queue blocking.")

        optionsWindow:AddNote("Ignored players are always hidden. The ignore list, word filters, built-in spam filters and the blocked log are in the manager.")

        local open = MakeButton(optionsWindow, "Open manager", 140, function()
            optionsWindow:Hide()
            OpenManager()
        end)
        open:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 4)
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    PruneExpired()

    if settings.enabled ~= false and settings.syncBlizzard then
        C_Timer.After(3, function() SyncToBlizzard(true) end)
    end

    if not OxedHub.ModuleAPI then
        if settings.enabled ~= false then
            Install()
            SetSocialEvents(true)
        end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "chatfilter",
        name     = "Chat Filter",
        version  = "1.2.0",
        author   = "Oxed",
        category = "chat",
        keywords = { "chat", "spam", "ignore", "filter", "block", "mute", "words", "gil" },
        desc     = "Unlimited ignore list, LFG warnings, Blizzard 50-slot sync, and spam blocking. /oxfilter",
        icon     = "Interface\\Icons\\INV_Misc_Book_09",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            EnsureData()
            Install()
            SetSocialEvents(true)
            if settings.syncBlizzard then
                C_Timer.After(2, function() SyncToBlizzard(true) end)
            end
        end,

        OnDisable = function()
            SetSocialEvents(false)
            if manager then manager:Hide() end
        end,
    })
end)
