-- ============================================================================
-- Group Finder (built-in OxedHub module, WoW Forever only)
-- One window for finding a group: the listings of the game's own group finder
-- and the group posts people type in chat, in one list, with filters, an
-- Invite / Request button on every row, a post builder for chat, and a card
-- with the group's details when a listed player invites you.
--
-- Rules this client taught everyone who tried:
--   * Never call into or hook the game's own Looking For Group window. It gets
--     tainted and its searches break until a reload. This module has its own
--     window and uses only C_LFGList.
--   * C_LFGList.Search needs a real click. A search started from a timer or an
--     event is dropped without an answer, so only the Search button starts one,
--     and a search that never answers is given up on after SEARCH_TIMEOUT.
--   * Search data comes back secret in a boss fight. Every read goes through
--     Safe(), and a secret counts as "unknown", never as a value to compare.
--   * Chat text and its author can be secret too: such a line is skipped.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on
    minimapButton = true,
    -- The list
    roleTank      = false,
    roleHealer    = false,
    roleDamage    = false,
    roleAuto      = false,   -- the roles my group still lacks
    show          = "all",   -- "all", "groups" or "players"
    levelMode     = "any",   -- "any", "near" or "range"
    levelNear     = 4,
    levelMin      = 0,       -- for levelMode "range"; 0 is "no limit"
    levelMax      = 0,
    hasTank       = false,   -- only groups that already have one
    hasHealer     = false,
    discordOnly   = false,   -- only listings that use Discord
    newbieOnly    = false,   -- only listings marked friendly to new players
    zoneNotice    = true,    -- a chat line on entering a zone whose dungeon has groups
    gameButton    = true,    -- a button of ours beside the game's Looking For Group window
    hideDelisted  = true,
    hideDeclined  = true,
    showChat      = true,    -- group posts from chat in the same list
    chatMinutes   = 10,      -- how long a chat post stays
    -- Extras
    inviteCard    = true,    -- the group's details when a listed player invites you
    alertChat     = true,    -- a chat line for a new post about a picked dungeon
    alertSound    = "None",
    network       = true,    -- the hidden channel that carries posts to every zone
    declineText   = "Sorry, the group is full. Good luck!",   -- whispered by Decline
    whisperSound  = "None",  -- played when a whisper arrives
    -- picks, hidden, hiddenClasses, posts and postChannels are tables, made at login
}

local PREFIX = "|cff00ccffOxedHub|r "
local SEARCH_TIMEOUT = 12    -- a search with no answer is given up on
local LEADER_KEEP = 300      -- a listing is remembered this long for the invite card
local ALERT_GAP = 30         -- at most one alert in this many seconds
local SEND_GAP = 10          -- between two posts to chat
local CARD_TIME = 60         -- the invite card closes itself
local MIN_LEVEL = 10         -- the game's group finder opens at this level
local MAX_POSTS = 8          -- saved posts
-- The network: one custom chat channel (those are realm-wide, where General and
-- Trade only reach a zone or a city) that every copy of this module joins.
-- A post sent from the Post page goes there too, as an ordinary chat line, and
-- every other copy reads it like any other group post. The channel is kept out
-- of the chat windows.
-- It carries only posts a player sends with a click: sending to a channel
-- needs one, and this server refuses addon messages in custom channels, so
-- other people's posts cannot be passed on automatically.
local NET_CHANNEL = "OxedHubLFG"
local NET_JOIN_DELAY = 8     -- after the game's own channels, so theirs keep their numbers
local NET_CHECK = 60         -- rejoin if the server dropped us
local ROW_HEIGHT = 22
local ROLES = { "TANK", "HEALER", "DAMAGER" }
local ROLE_LETTER = { TANK = "|cff4da6ffT|r", HEALER = "|cff40e040H|r", DAMAGER = "|cffff5555D|r" }
local ROLE_FIELD = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local EXPECTED = { TANK = 1, HEALER = 1, DAMAGER = 3 }
-- The line this server prints when a leader turns a request to join down.
local DECLINE_PATTERN = "^(.+) declines your group invitation request%.$"

local DISCORD = Enum and Enum.LFGEntryVoiceMode and Enum.LFGEntryVoiceMode.Discord or 2

local settings
local running = false
local window, card, optionsWindow
local minimapIcon
local results = {}           -- parsed listings of the last search
local posts = {}             -- author -> group post seen in chat
local display = {}           -- what the list shows: headers and entries
local leaders = {}           -- leader name -> { entry, at }, for the invite card
local requested = {}         -- leader name -> true, asked to join
local declined = {}          -- leader name -> true, they said no
local whisperedBy = {}       -- short name -> time of their last whisper, lights their row
local WHISPER_GLOW = 600     -- a row stays lit this long after a whisper
local searching, searchFailed, searchToken, lastSearch = false, false, 0, nil
local sawSecret = false
local hiddenCount = 0
local scroll = 0
local lastAlert, lastSend, lastSent = 0, 0, nil
local lastLevel = 1
local refreshQueued = false
local netTicker, netFiltered
local resultsDirty = false   -- a listing changed: read them again on the next pass
local ticker

local events = CreateFrame("Frame")

-- Defined further down, used above their definitions.
local Refresh, RefreshSoon, ShowOptions, MinimapIcon, UpdatePostPage, UpdateTop
local QuickPost, QuickPostText     -- set with the Post page, used by the Browse page above it

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

-- A value read from the game, or nil when it is secret.
local function Safe(value)
    if IsSecret(value) then
        sawSecret = true
        return nil
    end
    return value
end

-- Calls a function that may be missing or may throw. Nil on either.
local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

-- A plain yes or no from the game: true, false, or nil for "cannot tell".
local function Ask(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then return nil end
    return value and true or false
end

local function Say(text)
    print(PREFIX .. text)
end

local function MyLevel()
    local level = Call(UnitLevel, "player")
    if type(level) == "number" and not IsSecret(level) and level > 0 then lastLevel = level end
    return lastLevel
end

local function ClassColoured(name, classFile)
    local colour = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not colour then return name end
    return ("|cff%02x%02x%02x%s|r"):format(colour.r * 255, colour.g * 255, colour.b * 255, name)
end

-- The game's own role and class icons where this client has them, drawn
-- inside the text; the coloured letters stay otherwise.
local ROLE_ATLAS = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
local iconsReady = false
local classIcons = {}

local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    return Call(C_Texture.GetAtlasInfo, name) ~= nil
end

local function UseIcons()
    if iconsReady then return end
    iconsReady = true
    for role, atlas in pairs(ROLE_ATLAS) do
        if HasAtlas(atlas) then ROLE_LETTER[role] = "|A:" .. atlas .. ":15:15|a" end
    end
end

local function ClassIcon(classFile)
    if type(classFile) ~= "string" then return "" end
    local icon = classIcons[classFile]
    if icon == nil then
        local atlas = "groupfinder-icon-class-" .. classFile:lower()
        icon = HasAtlas(atlas) and ("|A:" .. atlas .. ":14:14|a") or ""
        classIcons[classFile] = icon
    end
    return icon
end

local function AgeText(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return L["%ds"]:format(seconds) end
    if seconds < 3600 then return L["%dm"]:format(math.floor(seconds / 60)) end
    return L["%dh"]:format(math.floor(seconds / 3600))
end

local function ShortName(name)
    if Ambiguate then
        local ok, short = pcall(Ambiguate, name, "none")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
    return name
end

local function InGroup() return Ask(IsInGroup) == true end
local function InRaid() return Ask(IsInRaid) == true end

local function CanInvite()
    if not InGroup() then return true end
    return Ask(UnitIsGroupLeader, "player") == true or Ask(UnitIsGroupAssistant, "player") == true
end

local function GroupIsFull()
    local n = Call(GetNumGroupMembers)
    if type(n) ~= "number" or IsSecret(n) or n == 0 then return false end
    if InRaid() then return n >= (MAX_RAID_MEMBERS or 40) end
    return n >= ((MAX_PARTY_MEMBERS or 4) + 1)
end

-- ── The network channel ─────────────────────────────────────────────────────

local function NetChannelId()
    local id = Call(GetChannelName, NET_CHANNEL)
    if type(id) == "number" and not IsSecret(id) and id > 0 then return id end
    return nil
end

local function IsNetChannel(baseName)
    if IsSecret(baseName) or type(baseName) ~= "string" then return false end
    return baseName:lower() == NET_CHANNEL:lower()
end

-- Ours goes to the end of the list, one place at a time, so General keeps the
-- number everyone is used to typing.
local function MoveNetLast()
    local id = NetChannelId()
    if not (id and C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex) then return end
    local last = id
    for i = id + 1, 20 do
        local other = Call(GetChannelName, i)
        if type(other) == "number" and not IsSecret(other) and other > 0 then last = i end
    end
    for i = id, last - 1 do
        pcall(C_ChatInfo.SwapChatChannelsByChannelIndex, i, i + 1)
    end
end

local function JoinNet()
    if not running or not settings.network or NetChannelId() then return end
    local join = JoinTemporaryChannel or JoinChannelByName
    if not join then return end
    pcall(join, NET_CHANNEL)
    C_Timer.After(2, function()
        if running and settings.network then MoveNetLast() end
    end)
end

local function LeaveNet()
    if NetChannelId() and LeaveChannelByName then pcall(LeaveChannelByName, NET_CHANNEL) end
end

local function ApplyNet()
    if running and settings.network then JoinNet() else LeaveNet() end
    UpdatePostPage()
end

-- A chat filter: called once per chat window, on values that may be secret.
-- It only ever answers for our own channel, and false on any doubt.
local function HideNetChannel(_, _, _, _, _, _, _, _, _, _, baseName)
    if not running then return false end
    return IsNetChannel(baseName)
end

local function FilterNetChannel()
    if netFiltered then return end
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then return end
    netFiltered = true
    for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER",
        "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
        pcall(add, event, HideNetChannel)
    end
end

-- ── Dungeons, for filing chat posts ─────────────────────────────────────────
-- words are matched as whole words, on text put in lower case with its
-- punctuation and apostrophes taken out. The longest match wins, so "ruins of
-- lordaeron" is never filed under the Ruins of Ahn'Qiraj.

local DUNGEONS = {
    { name = "Ragefire Chasm",       min = 13, max = 18, words = { "rfc", "ragefire" } },
    { name = "Hall of Thanes",       min = 13, max = 18, words = { "thanes" } },
    { name = "Ruins of Lordaeron",   min = 15, max = 20, words = { "rol", "lordaeron" } },
    { name = "Wailing Caverns",      min = 17, max = 24, words = { "wc", "wailing" } },
    { name = "The Deadmines",        min = 17, max = 26, words = { "deadmines", "dead mines", "vc", "van cleef", "vancleef" } },
    { name = "Shadowfang Keep",      min = 22, max = 30, words = { "sfk", "shadowfang" } },
    { name = "Blackfathom Deeps",    min = 24, max = 32, words = { "bfd", "blackfathom" } },
    { name = "The Stockade",         min = 24, max = 32, words = { "stockade", "stockades", "stocks" } },
    { name = "Excavation Site",      min = 24, max = 29, words = { "excavation", "exc site" } },
    { name = "City of Dalaran",      min = 28, max = 33, words = { "dalaran" } },
    { name = "Gnomeregan",           min = 29, max = 38, words = { "gnomer", "gnomeregan" } },
    { name = "Razorfen Kraul",       min = 29, max = 38, words = { "rfk", "kraul" } },
    { name = "Scarlet Monastery",    min = 28, max = 45, words = { "sm", "scarlet", "monastery", "sm gy", "sm lib", "sm arm", "sm armory", "sm cath", "sm library", "sm graveyard", "sm cathedral" } },
    { name = "The Drowned City",     min = 35, max = 40, words = { "drowned city", "drowned" } },
    { name = "Razorfen Downs",       min = 37, max = 46, words = { "rfd", "razorfen downs" } },
    { name = "Krol'dok Stronghold",  min = 40, max = 45, words = { "kroldok", "krol dok", "stronghold" } },
    { name = "Uldaman",              min = 41, max = 51, words = { "ulda", "uldaman" } },
    { name = "Zul'Farrak",           min = 44, max = 54, words = { "zf", "zulfarrak", "zul farrak" } },
    { name = "Maraudon",             min = 46, max = 55, words = { "mara", "maraudon" } },
    { name = "Alcaz Prison",         min = 48, max = 53, words = { "alcaz" } },
    { name = "Sunken Temple",        min = 50, max = 56, words = { "st", "sunken temple", "sunken", "atalhakkar" } },
    { name = "Blackrock Depths",     min = 52, max = 60, words = { "brd", "blackrock depths" } },
    { name = "Lower Blackrock Spire", min = 55, max = 60, words = { "lbrs", "lower blackrock" } },
    { name = "Upper Blackrock Spire", min = 55, max = 60, words = { "ubrs", "upper blackrock" } },
    { name = "Blackmaw Hold",        min = 55, max = 60, words = { "blackmaw" } },
    { name = "Dire Maul",            min = 55, max = 60, words = { "dire maul", "diremaul", "dm east", "dm west", "dm north", "dme", "dmw", "dmn", "dm tribute" } },
    { name = "Scholomance",          min = 58, max = 60, words = { "scholo", "scholomance" } },
    { name = "Stratholme",           min = 58, max = 60, words = { "strat", "stratholme", "strat live", "strat ud", "strat undead" } },
    { name = "Shaper's Terrace",     min = 58, max = 60, words = { "shapers terrace", "shapers", "terrace" } },
    { name = "Onyxia's Lair",        min = 60, max = 60, words = { "ony", "onyxia" } },
    { name = "Hyjal Summit",         min = 60, max = 60, words = { "hyjal" } },
    { name = "Barrow Deeps",         min = 60, max = 60, words = { "barrow deeps", "barrow" } },
    { name = "Molten Core",          min = 60, max = 60, words = { "mc", "molten core" } },
    { name = "Blackwing Lair",       min = 60, max = 60, words = { "bwl", "blackwing" } },
    { name = "Zul'Gurub",            min = 60, max = 60, words = { "zg", "zulgurub", "zul gurub" } },
    { name = "Ruins of Ahn'Qiraj",   min = 60, max = 60, words = { "aq20", "ruins of ahnqiraj" } },
    { name = "Temple of Ahn'Qiraj",  min = 60, max = 60, words = { "aq40", "temple of ahnqiraj" } },
    { name = "Naxxramas",            min = 60, max = 60, words = { "naxx", "naxxramas" } },
}

-- Text ready for whole-word matching: " word word word ".
local function Words(text)
    text = text:gsub("'", "")
    text = text:gsub("\226\128\153", "")      -- the curly apostrophe
    text = text:lower()
    text = text:gsub("[%p%c]", " ")
    text = text:gsub("%s+", " ")
    return " " .. text .. " "
end

local keywords = {}          -- { pattern = " sfk ", dungeon = <entry> }, longest first
local deadmines, direMaul
for _, dungeon in ipairs(DUNGEONS) do
    if dungeon.name == "The Deadmines" then deadmines = dungeon end
    if dungeon.name == "Dire Maul" then direMaul = dungeon end
    local seen = {}
    local function Add(word)
        local pattern = Words(word)
        if not seen[pattern] then
            seen[pattern] = true
            keywords[#keywords + 1] = { pattern = pattern, dungeon = dungeon }
        end
    end
    Add(dungeon.name)
    for _, word in ipairs(dungeon.words) do Add(word) end
end
table.sort(keywords, function(a, b)
    if #a.pattern ~= #b.pattern then return #a.pattern > #b.pattern end
    return a.pattern < b.pattern
end)

-- The dungeons a line of chat names, each once.
local function FindDungeons(words)
    local found, has = {}, {}
    for _, keyword in ipairs(keywords) do
        local s, e = words:find(keyword.pattern, 1, true)
        while s do
            if not has[keyword.dungeon] then
                has[keyword.dungeon] = true
                found[#found + 1] = keyword.dungeon
            end
            -- Take the matched words out, keeping one space where they stood.
            words = words:sub(1, s) .. words:sub(e + 1)
            s, e = words:find(keyword.pattern, 1, true)
        end
    end
    -- A bare "dm" is the Deadmines or Dire Maul, by the reader's own level.
    if words:find(" dm ", 1, true) then
        local dungeon = (MyLevel() < 40) and deadmines or direMaul
        if dungeon and not has[dungeon] then found[#found + 1] = dungeon end
    end
    return found
end

-- ── The game's group finder ─────────────────────────────────────────────────

local function HasFinder()
    return C_LFGList ~= nil and C_LFGList.Search ~= nil
end

local function GetCategories()
    local list = {}
    local ids = Call(C_LFGList and C_LFGList.GetAvailableCategories)
    if type(ids) ~= "table" then return list end
    for _, id in ipairs(ids) do
        local info = Call(C_LFGList.GetLfgCategoryInfo, id)
        local name = type(info) == "table" and Safe(info.name) or nil
        list[#list + 1] = { id = id, name = name or (L["Category"] .. " " .. id) }
    end
    return list
end

local activityCache = {}
local function ActivityInfo(id)
    if not id then return nil end
    local info = activityCache[id]
    if info == nil then
        info = Call(C_LFGList and C_LFGList.GetActivityInfoTable, id)
        if type(info) ~= "table" then info = false end
        activityCache[id] = info
    end
    return info or nil
end

local function ActivityName(id, short)
    local info = ActivityInfo(id)
    local name
    if info then
        name = short and Safe(info.shortName) or nil
        if not name or name == "" then name = Safe(info.fullName) or Safe(info.shortName) end
    end
    return name or (L["Activity"] .. " " .. tostring(id))
end

local function GetActivities(categoryID)
    local list = {}
    if not categoryID then return list end
    local ids = Call(C_LFGList and C_LFGList.GetAvailableActivities, categoryID)
    if type(ids) ~= "table" then return list end
    for _, id in ipairs(ids) do
        local info = ActivityInfo(id)
        list[#list + 1] = {
            id = id,
            name = ActivityName(id),
            min = info and (Safe(info.minLevelSuggestion) or Safe(info.minLevel)) or nil,
            max = info and (Safe(info.maxLevelSuggestion) or Safe(info.maxLevel)) or nil,
        }
    end
    table.sort(list, function(a, b)
        local la, lb = tonumber(a.min) or 0, tonumber(b.min) or 0
        if la ~= lb then return la < lb end
        return a.name < b.name
    end)
    return list
end

-- The dungeons category when nothing was chosen yet, else the first one.
local function EnsureCategory()
    if settings.categoryID then return end
    local categories = GetCategories()
    for _, category in ipairs(categories) do
        if category.name:lower():find("dungeon", 1, true) then
            settings.categoryID = category.id
            return
        end
    end
    if categories[1] then settings.categoryID = categories[1].id end
end

local function IsPicked(id)
    for _, picked in ipairs(settings.picks) do
        if picked == id then return true end
    end
    return false
end

local function TogglePick(id)
    for i, picked in ipairs(settings.picks) do
        if picked == id then
            table.remove(settings.picks, i)
            return
        end
    end
    settings.picks[#settings.picks + 1] = id
end

-- The names of the picked dungeons, in lower case, for matching chat posts.
local function PickedNames()
    local names = {}
    for _, id in ipairs(settings.picks) do
        names[#names + 1] = ActivityName(id):lower()
    end
    return names
end

-- "Relaxed", "Competitive" and so on, in the game's own words.
local function StyleName(index)
    if type(index) ~= "number" or index <= 0 then return nil end
    local text = Call(GetGeneralPlaystyleString, index)
    if type(text) == "string" and not IsSecret(text) and text ~= "" then return text end
    return nil
end

local function RolesFrom(source)
    if type(source) ~= "table" then return nil end
    local roles = {
        TANK = Safe(source.tank) and true or false,
        HEALER = Safe(source.healer) and true or false,
        DAMAGER = Safe(source.dps) and true or false,
    }
    if roles.TANK or roles.HEALER or roles.DAMAGER then return roles end
    return nil
end

local function ParseResult(id)
    local info = Call(C_LFGList.GetSearchResultInfo, id)
    if type(info) ~= "table" then return nil end
    local entry = {
        source = "native",
        id = id,
        name = Safe(info.leaderName),
        numMembers = Safe(info.numMembers) or 1,
        delisted = Safe(info.isDelisted) and true or false,
        hasSelf = Safe(info.hasSelf) and true or false,
        comment = Safe(info.comment) or "",
        age = Safe(info.age),
        playstyle = Safe(info.generalPlaystyle),
        voice = Safe(info.voiceMode),
        newbie = Safe(info.newPlayerFriendly) and true or false,
        activityIDs = {},
        members = {},
    }
    if type(info.activityIDs) == "table" then
        for _, activityID in ipairs(info.activityIDs) do
            local plain = Safe(activityID)
            if plain then entry.activityIDs[#entry.activityIDs + 1] = plain end
        end
    else
        local single = Safe(info.activityID)
        if single then entry.activityIDs[1] = single end
    end
    if type(entry.numMembers) ~= "number" then entry.numMembers = 1 end
    entry.isSolo = entry.numMembers <= 1

    local count = #entry.activityIDs
    if count == 1 then
        entry.activityText = ActivityName(entry.activityIDs[1])
    elseif count > 1 then
        local names = {}
        for i, activityID in ipairs(entry.activityIDs) do
            if i > 3 then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = ActivityName(activityID, true)
        end
        entry.activityText = table.concat(names, ", ")
    else
        entry.activityText = ""
    end

    local leader = Call(C_LFGList.GetSearchResultLeaderInfo, id)
    if type(leader) == "table" then
        entry.name = entry.name or Safe(leader.name)
        entry.classFile = Safe(leader.classFilename)
        entry.level = Safe(leader.level)
        entry.roles = RolesFrom(leader.lfgRoles)
        entry.area = Safe(leader.areaName)
    end

    if C_LFGList.GetSearchResultPlayerInfo and entry.numMembers <= 40 then
        for i = 1, entry.numMembers do
            local member = Call(C_LFGList.GetSearchResultPlayerInfo, id, i)
            if type(member) == "table" then
                local m = {
                    name = Safe(member.name),
                    classFile = Safe(member.classFilename),
                    level = Safe(member.level),
                    role = Safe(member.assignedRole),
                    spec = Safe(member.specName),
                }
                entry.members[#entry.members + 1] = m
                if entry.isSolo then
                    entry.classFile = entry.classFile or m.classFile
                    entry.level = entry.level or m.level
                    entry.roles = entry.roles or RolesFrom(member.lfgRoles)
                end
            end
        end
    end

    local counts = Call(C_LFGList.GetSearchResultMemberCounts, id)
    if type(counts) == "table" then
        entry.remaining = {}
        entry.have = {}
        for _, role in ipairs(ROLES) do
            entry.have[role] = Safe(counts[role])
            entry.remaining[role] = Safe(counts[role .. "_REMAINING"])
        end
    end
    if type(entry.level) ~= "number" then entry.level = nil end
    return entry
end

local function CollectResults()
    wipe(results)
    sawSecret = false
    if not C_LFGList then return end
    local getter = C_LFGList.GetFilteredSearchResults or C_LFGList.GetSearchResults
    local _, ids = Call(getter)
    if type(ids) ~= "table" then return end
    local now = GetTime()
    for i, id in ipairs(ids) do
        local entry = ParseResult(id)
        if entry then
            entry.order = i
            results[#results + 1] = entry
            if entry.name then leaders[entry.name] = { entry = entry, at = now } end
        end
    end
    for name, kept in pairs(leaders) do
        if now - kept.at > LEADER_KEEP then leaders[name] = nil end
    end
end

-- Only ever called from a click: see the note at the top of the file.
local function Search()
    if not HasFinder() then
        Say(L["This client has no group search. Chat posts still show."])
        return
    end
    if MyLevel() < MIN_LEVEL then
        Say(L["The game's group finder opens at level 10. Chat posts still show."])
        return
    end
    EnsureCategory()
    if not settings.categoryID then
        Say(L["The game offers no group categories right now."])
        return
    end
    local ids = {}
    for _, id in ipairs(settings.picks) do ids[#ids + 1] = id end
    if #ids == 0 then
        for _, activity in ipairs(GetActivities(settings.categoryID)) do ids[#ids + 1] = activity.id end
    end
    local ok = pcall(C_LFGList.Search, settings.categoryID, 0, 0, nil, false, nil, ids)
    if not ok then
        searching, searchFailed = false, true
    else
        searching, searchFailed = true, false
        searchToken = searchToken + 1
        local token = searchToken
        C_Timer.After(SEARCH_TIMEOUT, function()
            if searching and searchToken == token then
                searching, searchFailed = false, true
                Refresh()
            end
        end)
    end
    Refresh()
end

-- ── Group posts from chat ───────────────────────────────────────────────────

local function StripCodes(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", "")
    text = text:gsub("|A.-|a", "")
    text = text:gsub("{.-}", "")
    return text
end

local function HasAny(words, list)
    for _, word in ipairs(list) do
        if words:find(word, 1, true) then return true end
    end
    return false
end

local NOT_A_GROUP = { " wts ", " wtb ", " wtt ", " boost ", " boosts ", " boosting ", " recruiting ", " recruit ", " selling ", " buying " }
local PLAYER_WORDS = { " lfg ", " looking for group ", " looking for a group ", " \208\187\209\132\208\179 ", " \208\184\209\137\209\131 \208\179\209\128\209\131\208\191\208\191\209\131 ", " \208\184\209\137\209\131 \208\191\208\176\209\130\208\184 " }
local GROUP_WORDS = { " lf ", " need ", " needs ", " looking for ", " last spot ", " \208\187\209\132\208\188 ", " \208\189\209\131\208\182\208\181\208\189 ", " \208\189\209\131\208\182\208\189\209\139 ", " \208\189\209\131\208\182\208\189\208\176 ", " \209\129\208\190\208\177\208\184\209\128\208\176\209\142 ", " \208\184\209\137\208\181\208\188 ", " \208\184\209\137\209\131 " }
local TANK_WORDS = { " tank ", " tanks ", " \209\130\208\176\208\189\208\186 ", " \209\130\208\176\208\189\208\186\208\176 " }
local HEAL_WORDS = { " heal ", " healer ", " heals ", " healz ", " \209\133\208\184\208\187 ", " \209\133\208\184\208\187\208\176 " }
local DPS_WORDS = { " dps ", " dd ", " damage ", " \208\180\208\180 ", " \208\180\208\191\209\129 " }

-- "player", "group", or nil for a line that is not about a group at all.
local function PostKind(words)
    if HasAny(words, NOT_A_GROUP) then return nil end
    local more = words:find(" lf%d*m ") or words:find(" lf%d+ ")
    if more then return "group" end
    if HasAny(words, PLAYER_WORDS) then return "player" end
    if HasAny(words, GROUP_WORDS) then return "group" end
    return nil
end

local function Alert(entry)
    if not settings.alertChat or #settings.picks == 0 then return end
    if window and window:IsShown() then return end
    local now = GetTime()
    if now - lastAlert < ALERT_GAP then return end
    local names = PickedNames()
    local matches = false
    for _, dungeon in ipairs(entry.dungeons) do
        local name = dungeon.name:lower():gsub("^the ", "")
        for _, picked in ipairs(names) do
            if picked:find(name, 1, true) then matches = true end
        end
    end
    if not matches then return end
    lastAlert = now
    Say(L["%s: %s. /oxlfg to open the list."]:format(ClassColoured(ShortName(entry.name), entry.classFile), entry.activityText))
    if settings.alertSound and settings.alertSound ~= "None" and OxedHub.ModuleAPI and OxedHub.ModuleAPI.PlaySound then
        OxedHub.ModuleAPI:PlaySound(settings.alertSound)
    end
end

local function OnChatLine(text, author, channel, guid)
    if IsSecret(text) or IsSecret(author) then return end
    if type(text) ~= "string" or type(author) ~= "string" or author == "" then return end
    local me = Call(UnitName, "player")
    if type(me) == "string" and not IsSecret(me) and ShortName(author) == me then return end
    if settings.hidden[ShortName(author)] then return end

    local clean = StripCodes(text)
    local words = Words(clean)
    local kind = PostKind(words)
    if not kind then return end
    local dungeons = FindDungeons(words)

    local now = GetTime()
    local old = posts[author]
    local entry = {
        source = "chat",
        name = author,
        isSolo = (kind == "player"),
        comment = clean,
        dungeons = dungeons,
        first = old and old.first or now,
        last = now,
        channel = (not IsSecret(channel) and type(channel) == "string") and channel or nil,
    }
    -- Through the network only: a post also seen in a channel here is a local one.
    entry.remote = IsNetChannel(channel) and (old == nil or old.remote == true)
    if #dungeons > 0 then
        local names = {}
        for i, dungeon in ipairs(dungeons) do
            names[i] = dungeon.name
            entry.min = math.min(entry.min or dungeon.min, dungeon.min)
            entry.max = math.max(entry.max or dungeon.max, dungeon.max)
        end
        entry.activityText = table.concat(names, ", ")
    else
        entry.activityText = L["Other"]
    end

    local roles = {
        TANK = HasAny(words, TANK_WORDS),
        HEALER = HasAny(words, HEAL_WORDS),
        DAMAGER = HasAny(words, DPS_WORDS),
    }
    if roles.TANK or roles.HEALER or roles.DAMAGER then
        if entry.isSolo then entry.roles = roles else entry.needs = roles end
    end

    if guid and not IsSecret(guid) and GetPlayerInfoByGUID then
        local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
        if ok and type(classFile) == "string" and not IsSecret(classFile) then entry.classFile = classFile end
    end
    if not entry.classFile and old then entry.classFile = old.classFile end

    posts[author] = entry
    if not old then Alert(entry) end
    RefreshSoon()
end

local function PruneChat()
    local limit = (tonumber(settings.chatMinutes) or DEFAULTS.chatMinutes) * 60
    local now = GetTime()
    for author, entry in pairs(posts) do
        if now - entry.last > limit then posts[author] = nil end
    end
end

-- ── Filters ─────────────────────────────────────────────────────────────────

-- The roles my group still lacks, or nil when that cannot be said (a raid).
local function MissingRoles()
    if InRaid() then return nil end
    local have = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    if InGroup() then
        local units = { "player" }
        local n = Call(GetNumSubgroupMembers)
        if type(n) ~= "number" or IsSecret(n) then n = 0 end
        for i = 1, n do units[#units + 1] = "party" .. i end
        for _, unit in ipairs(units) do
            local role = Call(UnitGroupRolesAssigned, unit)
            if not IsSecret(role) and have[role] then have[role] = have[role] + 1 end
        end
    else
        local mine = RolesFrom(Call(C_LFGListRoles and C_LFGListRoles.GetRoles))
        if mine then
            local count, only = 0, nil
            for _, role in ipairs(ROLES) do
                if mine[role] then count, only = count + 1, role end
            end
            if count == 1 then have[only] = 1 end
        end
    end
    local need = {}
    local any = false
    for _, role in ipairs(ROLES) do
        need[role] = have[role] < EXPECTED[role]
        any = any or need[role]
    end
    return any and need or nil
end

-- Which roles the filter asks for: of players (the roles they offer) and of
-- groups (the roles they still have room for). Nil is "no role filter".
local function WantedRoles()
    if settings.roleAuto then
        local mine = RolesFrom(Call(C_LFGListRoles and C_LFGListRoles.GetRoles))
        return MissingRoles(), mine
    end
    if not (settings.roleTank or settings.roleHealer or settings.roleDamage) then return nil, nil end
    local picked = { TANK = settings.roleTank, HEALER = settings.roleHealer, DAMAGER = settings.roleDamage }
    return picked, picked
end

local function PassesRoles(entry, ofPlayers, ofGroups)
    if entry.isSolo then
        if not ofPlayers or not entry.roles then return true end
        for _, role in ipairs(ROLES) do
            if ofPlayers[role] and entry.roles[role] then return true end
        end
        return false
    end
    if not ofGroups then return true end
    if entry.source == "chat" then
        if not entry.needs then return true end
        for _, role in ipairs(ROLES) do
            if ofGroups[role] and entry.needs[role] then return true end
        end
        return false
    end
    if not entry.remaining then return true end
    for _, role in ipairs(ROLES) do
        if ofGroups[role] then
            local left = entry.remaining[role]
            if left == nil or left > 0 then return true end
        end
    end
    return false
end

-- Search text: words separated by spaces must all match, "a|b" matches either,
-- and "!word" must not be there.
local function PassesText(entry, query)
    if not query or query == "" then return true end
    local hay = ((entry.name or "") .. " " .. (entry.comment or "") .. " " .. (entry.activityText or "") .. " " .. (entry.classFile or "")):lower()
    for token in query:lower():gmatch("%S+") do
        local exclude = token:sub(1, 1) == "!"
        if exclude then token = token:sub(2) end
        if token ~= "" then
            local hit = false
            for part in token:gmatch("[^|]+") do
                if hay:find(part, 1, true) then hit = true end
            end
            if exclude == hit then return false end
        end
    end
    return true
end

local function PassesPicks(entry, names)
    if entry.source ~= "chat" or #names == 0 then return true end
    for _, dungeon in ipairs(entry.dungeons) do
        local name = dungeon.name:lower():gsub("^the ", "")
        for _, picked in ipairs(names) do
            if picked:find(name, 1, true) then return true end
        end
    end
    return false
end

local function Passes(entry, ctx)
    if entry.hasSelf then return true end
    if entry.name and settings.hidden[ShortName(entry.name)] then return false end
    if entry.delisted and settings.hideDelisted then return false end
    if settings.show == "groups" and entry.isSolo then return false end
    if settings.show == "players" and not entry.isSolo then return false end
    if settings.hideDeclined and entry.name and declined[entry.name] then return false end
    if entry.isSolo and entry.classFile and settings.hiddenClasses[entry.classFile] then return false end
    if settings.levelMode == "near" then
        local near = tonumber(settings.levelNear) or DEFAULTS.levelNear
        if entry.level then
            if math.abs(entry.level - ctx.level) > near then return false end
        elseif entry.min then
            if ctx.level < entry.min - near or ctx.level > entry.max + near then return false end
        end
    elseif settings.levelMode == "range" then
        local low, high = tonumber(settings.levelMin) or 0, tonumber(settings.levelMax) or 0
        if entry.level then
            if (low > 0 and entry.level < low) or (high > 0 and entry.level > high) then return false end
        elseif entry.min then
            if (low > 0 and entry.max < low) or (high > 0 and entry.min > high) then return false end
        end
    end
    if not entry.isSolo and entry.have then
        local tanks, healers = entry.have.TANK, entry.have.HEALER
        if settings.hasTank and type(tanks) == "number" and tanks < 1 then return false end
        if settings.hasHealer and type(healers) == "number" and healers < 1 then return false end
    end
    if type(entry.playstyle) == "number" and settings.hiddenStyles[entry.playstyle] then return false end
    if entry.source == "native" then
        if settings.discordOnly and entry.voice ~= DISCORD then return false end
        if settings.newbieOnly and not entry.newbie then return false end
    end
    if not PassesRoles(entry, ctx.ofPlayers, ctx.ofGroups) then return false end
    if not PassesPicks(entry, ctx.names) then return false end
    if not PassesText(entry, ctx.query) then return false end
    return true
end

local function ByOrder(a, b)
    -- The game's listings first, in the game's order, then chat, newest first.
    if a.source ~= b.source then return a.source == "native" end
    if a.source == "native" then return a.order < b.order end
    return a.last > b.last
end

local function BuildList(query)
    wipe(display)
    hiddenCount = 0
    local ofPlayers, ofGroups = WantedRoles()
    local ctx = { level = MyLevel(), ofPlayers = ofPlayers, ofGroups = ofGroups, names = PickedNames(), query = query }
    local groups, players = {}, {}
    local function Take(entry)
        if Passes(entry, ctx) then
            local list = entry.isSolo and players or groups
            list[#list + 1] = entry
        else
            hiddenCount = hiddenCount + 1
        end
    end
    for _, entry in ipairs(results) do Take(entry) end
    if settings.showChat then
        PruneChat()
        for _, entry in pairs(posts) do Take(entry) end
    end
    table.sort(groups, ByOrder)
    table.sort(players, ByOrder)
    if #groups > 0 then
        display[#display + 1] = { header = L["Groups recruiting"] .. " (" .. #groups .. ")" }
        for _, entry in ipairs(groups) do display[#display + 1] = entry end
    end
    if #players > 0 then
        display[#display + 1] = { header = L["Players looking"] .. " (" .. #players .. ")" }
        for _, entry in ipairs(players) do display[#display + 1] = entry end
    end
    return #groups + #players
end

-- ── What a row can do ───────────────────────────────────────────────────────

local function Whisper(name)
    if not name then return end
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        ChatFrameUtil.SendTell(name)
    elseif ChatFrame_SendTell then
        ChatFrame_SendTell(name)
    end
end

-- A polite no: a whisper with the player's own text, and the player's row
-- and whisper go quiet. Sending a whisper needs no click, unlike channels.
local declinedByMe = {}      -- short name -> true, told no this session
local function Decline(name)
    if not name or IsSecret(name) then return end
    local text = (settings.declineText or ""):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then text = DEFAULTS.declineText end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, "WHISPER", nil, name) end
    declinedByMe[ShortName(name)] = true
    whisperedBy[ShortName(name)] = nil
    Say(L["Declined %s."]:format(ShortName(name)))
end

-- From a member who is not the leader, the game passes this on to the leader
-- as a suggestion, the same as Invite on a player's own menu.
local function Invite(name)
    if not name then return end
    if GroupIsFull() then
        Say(L["Your group is full."])
        return
    end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not fn then return end
    pcall(fn, name)
    if CanInvite() then
        Say(L["Invited %s."]:format(ShortName(name)))
    else
        Say(L["Suggested %s to your group leader."]:format(ShortName(name)))
    end
end

local function RequestJoin(name)
    if not name then return end
    local fn = (C_PartyInfo and C_PartyInfo.RequestInviteFromUnit) or RequestInviteFromUnit
    if not fn then
        Whisper(name)
        return
    end
    if pcall(fn, name) then
        requested[name] = true
        Say(L["Asked %s to invite you."]:format(ShortName(name)))
        if InGroup() then
            Say(L["You are in a group now. Leave it, or their invite cannot reach you."])
        end
    end
    Refresh()
end

local function Who(name)
    if not name then return end
    local fn = (C_FriendList and C_FriendList.SendWho) or SendWho
    if fn then pcall(fn, ShortName(name)) end
end

-- The button at the end of a row: what it says, and what it does.
local function RowAction(entry)
    local name = entry.name
    if entry.hasSelf then return L["You"], nil end
    if not name then return "", nil end
    if entry.isSolo then
        if declinedByMe[ShortName(name)] then return L["Turned down"], nil end
        if GroupIsFull() then return L["Full"], nil end
        return CanInvite() and L["Invite"] or L["Suggest"], function() Invite(name) end
    end
    if entry.source == "chat" then
        return L["Whisper"], function() Whisper(name) end
    end
    if declined[name] then return L["Declined"], nil end
    if requested[name] then return L["Requested"], nil end
    return L["Request"], function() RequestJoin(name) end
end

local function RowMenu(owner, entry)
    local name = entry.name
    if not name or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ShortName(name))
        root:CreateButton(L["Whisper"], function() Whisper(name) end)
        root:CreateButton(L["Invite"], function() Invite(name) end)
        if not entry.isSolo then
            root:CreateButton(L["Request to join"], function() RequestJoin(name) end)
        end
        root:CreateButton(L["Who"], function() Who(name) end)
        if declinedByMe[ShortName(name)] then
            root:CreateButton(L["Undo decline"], function()
                declinedByMe[ShortName(name)] = nil
                Refresh()
            end)
        else
            root:CreateButton(L["Decline"], function()
                Decline(name)
                Refresh()
            end)
        end
        if declined[name] then
            root:CreateButton(L["Forget that they declined"], function()
                declined[name] = nil
                Refresh()
            end)
        end
        root:CreateButton(L["Hide this player"], function()
            settings.hidden[ShortName(name)] = true
            posts[name] = nil
            Refresh()
        end)
    end)
end

local function RolesText(entry)
    local parts = {}
    if entry.isSolo then
        if entry.roles then
            for _, role in ipairs(ROLES) do
                if entry.roles[role] then parts[#parts + 1] = ROLE_LETTER[role] end
            end
        end
        return table.concat(parts, " ")
    end
    if entry.source == "native" then
        if entry.numMembers > 5 then return "|cffffffff" .. entry.numMembers .. "|r" end
        -- Who is in it, by role, then a dot for every place still open.
        local filled = 0
        for _, role in ipairs(ROLES) do
            for _, member in ipairs(entry.members) do
                if member.role == role and filled < 5 then
                    parts[#parts + 1] = ROLE_LETTER[role]
                    filled = filled + 1
                end
            end
        end
        for _ = math.max(filled, entry.numMembers) + 1, 5 do
            parts[#parts + 1] = "|cff666666o|r"
        end
        return table.concat(parts, " ")
    elseif entry.needs then
        for _, role in ipairs(ROLES) do
            if entry.needs[role] then parts[#parts + 1] = ROLE_LETTER[role] end
        end
    end
    return table.concat(parts, " ")
end

-- The last column: where the leader is, the playstyle, and what they wrote.
local function Details(entry)
    local parts = {}
    if entry.area and entry.area ~= "" then parts[#parts + 1] = entry.area end
    local style = StyleName(entry.playstyle)
    if style then parts[#parts + 1] = style end
    if entry.comment and entry.comment ~= "" then parts[#parts + 1] = entry.comment end
    return table.concat(parts, " / ")
end

local function RowTooltip(row, entry)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ClassColoured(ShortName(entry.name or "?"), entry.classFile))
    if entry.activityText and entry.activityText ~= "" then
        GameTooltip:AddLine(entry.activityText, 1, 0.82, 0, true)
    end
    if entry.comment and entry.comment ~= "" then
        GameTooltip:AddLine(entry.comment, 1, 1, 1, true)
    end
    if entry.source == "chat" then
        GameTooltip:AddLine(" ")
        if entry.remote then
            GameTooltip:AddLine(L["Through the Group Finder network"], 0.4, 0.8, 1)
        elseif entry.channel and entry.channel ~= "" then
            GameTooltip:AddLine(L["From chat"] .. ": " .. entry.channel, 0.4, 0.8, 1)
        else
            GameTooltip:AddLine(L["From chat"], 0.4, 0.8, 1)
        end
        local now = GetTime()
        GameTooltip:AddDoubleLine(L["Last posted"], AgeText(now - entry.last), 0.7, 0.7, 0.7, 0.4, 1, 0.4)
        GameTooltip:AddDoubleLine(L["First posted"], AgeText(now - entry.first), 0.7, 0.7, 0.7, 0.5, 0.7, 1)
    elseif #entry.members > 0 then
        GameTooltip:AddLine(" ")
        for _, member in ipairs(entry.members) do
            local left = (ROLE_LETTER[member.role] and (ROLE_LETTER[member.role] .. " ") or "")
                .. ClassColoured(member.name or "?", member.classFile)
            local right = member.level and tostring(member.level) or ""
            if member.spec and member.spec ~= "" then right = member.spec .. " " .. right end
            GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.8, 0.8, 0.8)
        end
    end
    if entry.remaining then
        local open = {}
        for _, role in ipairs(ROLES) do
            local left = entry.remaining[role]
            if left and left > 0 then open[#open + 1] = ROLE_LETTER[role] .. " " .. left end
        end
        if #open > 0 then GameTooltip:AddLine(L["Room for"] .. ": " .. table.concat(open, "  "), 1, 1, 1) end
    end
    if entry.area and entry.area ~= "" then GameTooltip:AddLine(entry.area, 0.7, 0.7, 0.7) end
    local style = StyleName(entry.playstyle)
    if style then GameTooltip:AddLine(style, 0.7, 0.7, 0.7) end
    if entry.voice == DISCORD then GameTooltip:AddLine("Discord", 0.45, 0.55, 1) end
    if entry.newbie then GameTooltip:AddLine(L["Friendly to new players"], 0.4, 1, 0.4) end
    if entry.delisted then GameTooltip:AddLine(L["No longer listed"], 1, 0.3, 0.3) end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Click: whisper. Right-click: more."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

-- ── The window ──────────────────────────────────────────────────────────────

local function NewButton(parent, text, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 22)
    button:SetText(text)
    if onClick then button:SetScript("OnClick", onClick) end
    return button
end

-- Never takes the keyboard by itself: see "EditBox" in CLAUDE.md.
local function NewEdit(parent, width, height)
    local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "InputBoxTemplate")
    if not ok or not box then
        box = CreateFrame("EditBox", nil, parent)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontNormal")
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
    end
    box:SetAutoFocus(false)
    box:SetSize(width, height or 20)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return box
end

local function NewText(parent, font, width)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    if width then text:SetWidth(width) end
    if text.SetWordWrap then text:SetWordWrap(false) end
    return text
end

local function Toggled(on, text)
    return (on and "|cff40ff40" or "|cff999999") .. text .. "|r"
end

local function OpenMenu(owner, build)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, build)
        return true
    end
    return false
end

local function KeepOpen()
    return MenuResponse and MenuResponse.Refresh or nil
end

local function UpdateRows()
    if not window then return end
    local rows = window.rows
    local maxScroll = math.max(0, #display - #rows)
    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end
    local now = GetTime()
    for i, row in ipairs(rows) do
        local item = display[i + scroll]
        row.entry = nil
        if not item then
            row:Hide()
        elseif item.header then
            row.header:SetText(item.header)
            row.header:Show()
            row.name:SetText("")
            row.level:SetText("")
            row.roles:SetText("")
            row.activity:SetText("")
            row.comment:SetText("")
            row.age:SetText("")
            row.action:Hide()
            row.stripe:Hide()
            row.glow:Hide()
            row:Show()
        else
            row.entry = item
            row.header:Hide()
            row.stripe:SetShown((i + scroll) % 2 == 0)
            local name = ClassColoured(ShortName(item.name or "?"), item.classFile)
            if item.delisted then name = "|cff777777" .. ShortName(item.name or "?") .. "|r" end
            -- Lit when this player whispered you lately: the answer to your post.
            local said = item.name and whisperedBy[ShortName(item.name)]
            local lit = said and now - said < WHISPER_GLOW
            row.glow:SetShown(lit and true or false)
            if lit then name = "|TInterface\\ChatFrame\\UI-ChatWhisperIcon:12:12|t " .. name end
            row.name:SetText(name)
            row.level:SetText((item.level and tostring(item.level) or "") .. (item.isSolo and (" " .. ClassIcon(item.classFile)) or ""))
            row.roles:SetText(RolesText(item))
            row.activity:SetText(item.activityText or "")
            row.comment:SetText(Details(item))
            if item.source == "chat" then
                row.age:SetText("|cff66ccff" .. (item.remote and L["net"] or L["chat"]) .. " " .. AgeText(now - item.last) .. "|r")
            else
                row.age:SetText(item.age and AgeText(item.age) or "")
            end
            local label, action = RowAction(item)
            row.action:SetText(label)
            row.action.run = action
            row.action:SetEnabled(action ~= nil)
            row.action:SetShown(label ~= "")
            row:Show()
        end
    end
end

local function UpdateStatus(shown)
    if not window then return end
    local text
    if searching then
        text = L["Searching..."]
    elseif searchFailed then
        text = L["No answer from the game. Press Search again."]
    else
        text = L["%d shown, %d hidden"]:format(shown, hiddenCount)
        if lastSearch then
            text = text .. ". " .. L["Searched %s ago"]:format(AgeText(GetTime() - lastSearch))
        elseif HasFinder() then
            text = text .. ". " .. L["Press Search for the game's listings."]
        end
        if sawSecret then text = text .. " " .. L["Some details are hidden in a boss fight."] end
    end
    window.status:SetText(text)
end

Refresh = function()
    refreshQueued = false
    if not (window and window:IsShown()) or window.page ~= "browse" then return end
    if resultsDirty then
        resultsDirty = false
        CollectResults()
    end
    local shown = BuildList(window.search:GetText())
    UpdateRows()
    UpdateStatus(shown)
end

-- Chat and search updates come in bursts: one pass serves them all. Holding
-- Shift over the list keeps it still, so a row does not move under the mouse.
RefreshSoon = function()
    if refreshQueued or not (window and window:IsShown()) then return end
    refreshQueued = true
    C_Timer.After(0.4, function()
        if window and window:IsShown() and IsShiftKeyDown() and window.list:IsMouseOver() then
            refreshQueued = false
            return
        end
        Refresh()
    end)
end

UpdateTop = function()
    if not window then return end
    local categoryName = L["Category"]
    for _, category in ipairs(GetCategories()) do
        if category.id == settings.categoryID then categoryName = category.name end
    end
    window.category:SetText(categoryName)
    local picks = #settings.picks
    if picks == 0 then
        window.dungeons:SetText(L["All dungeons"])
    elseif picks == 1 then
        window.dungeons:SetText(ActivityName(settings.picks[1], true))
    else
        window.dungeons:SetText(L["%d picked"]:format(picks))
    end
    window.tank:SetText(Toggled(settings.roleTank and not settings.roleAuto, L["Tank"]))
    window.healer:SetText(Toggled(settings.roleHealer and not settings.roleAuto, L["Healer"]))
    window.damage:SetText(Toggled(settings.roleDamage and not settings.roleAuto, L["Damage"]))
    window.auto:SetText(Toggled(settings.roleAuto, L["Auto"]))
    local showText = { all = L["Everyone"], groups = L["Groups only"], players = L["Players only"] }
    window.show:SetText(showText[settings.show] or showText.all)
    local levelText = { any = L["Any level"], near = L["Near my level"], range = L["Level range"] }
    window.level:SetText(levelText[settings.levelMode] or levelText.any)
    local range = settings.levelMode == "range"
    window.rangeLabel:SetShown(range)
    window.rangeTo:SetShown(range)
    window.levelMin:SetShown(range)
    window.levelMax:SetShown(range)
    local low, high = tonumber(settings.levelMin) or 0, tonumber(settings.levelMax) or 0
    window.levelMin:SetText(low > 0 and tostring(low) or "")
    window.levelMax:SetText(high > 0 and tostring(high) or "")
    local extra = (settings.hasTank and 1 or 0) + (settings.hasHealer and 1 or 0)
        + (settings.discordOnly and 1 or 0) + (settings.newbieOnly and 1 or 0)
    for _ in pairs(settings.hiddenStyles) do extra = extra + 1 end
    window.more:SetText(extra > 0 and (L["More filters"] .. " (" .. extra .. ")") or L["More filters"])
    local classes = 0
    for _ in pairs(settings.hiddenClasses) do classes = classes + 1 end
    window.classes:SetText(classes > 0 and (L["Classes"] .. " -" .. classes) or L["Classes"])
end

local function CategoryMenu(owner)
    local categories = GetCategories()
    if #categories == 0 then
        Say(L["The game offers no group categories right now."])
        return
    end
    local function Pick(id)
        settings.categoryID = id
        wipe(settings.picks)
        UpdateTop()
        Refresh()
    end
    if OpenMenu(owner, function(_, root)
        for _, category in ipairs(categories) do
            local id = category.id
            root:CreateRadio(category.name, function() return settings.categoryID == id end, function() Pick(id) end)
        end
    end) then return end
    -- No menu on this client: step to the next category.
    local nextIndex = 1
    for i, category in ipairs(categories) do
        if category.id == settings.categoryID then nextIndex = i % #categories + 1 end
    end
    Pick(categories[nextIndex].id)
end

local function DungeonMenu(owner)
    EnsureCategory()
    local activities = GetActivities(settings.categoryID)
    if not OpenMenu(owner, function(_, root)
        if root.SetScrollMode then root:SetScrollMode(420) end
        root:CreateButton(L["All dungeons"], function()
            wipe(settings.picks)
            UpdateTop()
            Refresh()
        end)
        for _, activity in ipairs(activities) do
            local id = activity.id
            local label = activity.name
            if activity.min and activity.max and activity.max > 0 then
                label = label .. "  |cff999999" .. activity.min .. "-" .. activity.max .. "|r"
            end
            root:CreateCheckbox(label, function() return IsPicked(id) end, function()
                TogglePick(id)
                UpdateTop()
                Refresh()
                return KeepOpen()
            end)
        end
    end) then
        wipe(settings.picks)
        UpdateTop()
        Refresh()
    end
end

local function MoreMenu(owner)
    OpenMenu(owner, function(_, root)
        root:CreateTitle(L["Groups recruiting"])
        root:CreateCheckbox(L["Already has a tank"], function() return settings.hasTank end, function()
            settings.hasTank = not settings.hasTank
            UpdateTop()
            Refresh()
            return KeepOpen()
        end)
        root:CreateCheckbox(L["Already has a healer"], function() return settings.hasHealer end, function()
            settings.hasHealer = not settings.hasHealer
            UpdateTop()
            Refresh()
            return KeepOpen()
        end)
        root:CreateTitle(L["The game's listings"])
        root:CreateCheckbox(L["Only with Discord"], function() return settings.discordOnly end, function()
            settings.discordOnly = not settings.discordOnly
            UpdateTop()
            Refresh()
            return KeepOpen()
        end)
        root:CreateCheckbox(L["Only friendly to new players"], function() return settings.newbieOnly end, function()
            settings.newbieOnly = not settings.newbieOnly
            UpdateTop()
            Refresh()
            return KeepOpen()
        end)
        local titled = false
        for i = 1, 4 do
            local name = StyleName(i)
            if name then
                if not titled then
                    titled = true
                    root:CreateTitle(L["Playstyle"])
                end
                root:CreateCheckbox(name, function() return not settings.hiddenStyles[i] end, function()
                    settings.hiddenStyles[i] = (not settings.hiddenStyles[i]) or nil
                    UpdateTop()
                    Refresh()
                    return KeepOpen()
                end)
            end
        end
    end)
end

local function ResetFilters()
    settings.roleTank, settings.roleHealer, settings.roleDamage, settings.roleAuto = false, false, false, false
    settings.show, settings.levelMode = "all", "any"
    settings.levelMin, settings.levelMax = 0, 0
    settings.hasTank, settings.hasHealer = false, false
    settings.discordOnly, settings.newbieOnly = false, false
    wipe(settings.hiddenClasses)
    wipe(settings.hiddenStyles)
    if window then window.search:SetText("") end
    UpdateTop()
    Refresh()
end

-- A preset is the filters as they stand, the picked dungeons included.
local PRESET_KEYS = { "roleTank", "roleHealer", "roleDamage", "roleAuto", "show", "levelMode", "levelMin", "levelMax", "hasTank", "hasHealer", "discordOnly", "newbieOnly", "categoryID" }
local PRESET_LISTS = { "picks", "hiddenClasses", "hiddenStyles" }

local function SavePreset(index)
    local preset = {}
    for _, key in ipairs(PRESET_KEYS) do preset[key] = settings[key] end
    for _, key in ipairs(PRESET_LISTS) do
        local copy = {}
        for k, v in pairs(settings[key]) do copy[k] = v end
        preset[key] = copy
    end
    settings.presets[index] = preset
end

local function UsePreset(index)
    local preset = settings.presets[index]
    if type(preset) ~= "table" then return end
    for _, key in ipairs(PRESET_KEYS) do settings[key] = preset[key] end
    for _, key in ipairs(PRESET_LISTS) do
        wipe(settings[key])
        if type(preset[key]) == "table" then
            for k, v in pairs(preset[key]) do settings[key][k] = v end
        end
    end
    UpdateTop()
    Refresh()
end

local function PresetMenu(owner)
    OpenMenu(owner, function(_, root)
        for i = 1, 3 do
            if settings.presets[i] then
                root:CreateButton(L["Use preset %d"]:format(i), function() UsePreset(i) end)
            end
        end
        root:CreateTitle(L["Save the filters as"])
        for i = 1, 3 do
            root:CreateButton(L["Preset %d"]:format(i), function() SavePreset(i) end)
        end
    end)
end

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function ClassMenu(owner)
    OpenMenu(owner, function(_, root)
        root:CreateTitle(L["Show players of these classes"])
        for _, classFile in ipairs(CLASS_ORDER) do
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
            root:CreateCheckbox(ClassColoured(name, classFile),
                function() return not settings.hiddenClasses[classFile] end,
                function()
                    settings.hiddenClasses[classFile] = (not settings.hiddenClasses[classFile]) or nil
                    UpdateTop()
                    Refresh()
                    return KeepOpen()
                end)
        end
    end)
end

local function BuildBrowse(page)
    local f = window
    f.category = NewButton(page, "", 150, 22, function(self) CategoryMenu(self) end)
    f.category:SetPoint("TOPLEFT", 0, 0)
    f.dungeons = NewButton(page, "", 170, 22, function(self) DungeonMenu(self) end)
    f.dungeons:SetPoint("LEFT", f.category, "RIGHT", 4, 0)
    f.searchButton = NewButton(page, L["Search"], 90, 22, function() Search() end)
    f.searchButton:SetPoint("LEFT", f.dungeons, "RIGHT", 4, 0)
    f.postLFG = NewButton(page, L["Post LFG"], 90, 22, function() QuickPost() end)
    f.postLFG:SetPoint("LEFT", f.searchButton, "RIGHT", 4, 0)
    f.postLFG:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["Post LFG"], 1, 0.82, 0)
        GameTooltip:AddLine((QuickPostText()), 1, 1, 1, true)
        GameTooltip:AddLine(L["Made from the picked dungeons and your roles. Goes to the channels ticked on the Post page."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.postLFG:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.status = NewText(page, "GameFontHighlightSmall")
    f.status:SetPoint("LEFT", f.postLFG, "RIGHT", 8, 0)
    f.status:SetPoint("RIGHT", page, "RIGHT", -4, 0)
    f.status:SetTextColor(0.8, 0.8, 0.8)

    local function Role(key)
        return function()
            settings.roleAuto = false
            settings[key] = not settings[key]
            UpdateTop()
            Refresh()
        end
    end
    f.tank = NewButton(page, "", 62, 22, Role("roleTank"))
    f.tank:SetPoint("TOPLEFT", 0, -26)
    f.healer = NewButton(page, "", 66, 22, Role("roleHealer"))
    f.healer:SetPoint("LEFT", f.tank, "RIGHT", 2, 0)
    f.damage = NewButton(page, "", 70, 22, Role("roleDamage"))
    f.damage:SetPoint("LEFT", f.healer, "RIGHT", 2, 0)
    f.auto = NewButton(page, "", 56, 22, function()
        settings.roleAuto = not settings.roleAuto
        UpdateTop()
        Refresh()
    end)
    f.auto:SetPoint("LEFT", f.damage, "RIGHT", 2, 0)
    f.auto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Auto"])
        GameTooltip:AddLine(L["Players who fill a role your group still lacks, and groups with room for your own roles."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.show = NewButton(page, "", 104, 22, function()
        local order = { all = "groups", groups = "players", players = "all" }
        settings.show = order[settings.show] or "all"
        UpdateTop()
        Refresh()
    end)
    f.show:SetPoint("LEFT", f.auto, "RIGHT", 8, 0)
    f.level = NewButton(page, "", 110, 22, function()
        local order = { any = "near", near = "range", range = "any" }
        settings.levelMode = order[settings.levelMode] or "any"
        UpdateTop()
        Refresh()
    end)
    f.level:SetPoint("LEFT", f.show, "RIGHT", 2, 0)
    f.classes = NewButton(page, "", 84, 22, function(self) ClassMenu(self) end)
    f.classes:SetPoint("LEFT", f.level, "RIGHT", 2, 0)

    f.search = NewEdit(page, 150, 20)
    f.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -27)
    f.search:SetScript("OnTextChanged", function() scroll = 0; Refresh() end)
    f.search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Filter by text"])
        GameTooltip:AddLine(L["Name, dungeon, class or message. Space: all the words. a||b: either. !word: without it."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.search:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.more = NewButton(page, "", 150, 22, function(self) MoreMenu(self) end)
    f.more:SetPoint("TOPLEFT", 0, -52)
    f.presets = NewButton(page, L["Presets"], 100, 22, function(self) PresetMenu(self) end)
    f.presets:SetPoint("LEFT", f.more, "RIGHT", 2, 0)
    local reset = NewButton(page, L["Reset filters"], 130, 22, function() ResetFilters() end)
    reset:SetPoint("LEFT", f.presets, "RIGHT", 2, 0)
    f.rangeLabel = NewText(page, "GameFontHighlightSmall")
    f.rangeLabel:SetPoint("LEFT", reset, "RIGHT", 14, 0)
    f.rangeLabel:SetText(L["Levels from"])
    f.levelMin = NewEdit(page, 30, 20)
    f.levelMin:SetPoint("LEFT", f.rangeLabel, "RIGHT", 10, 0)
    f.rangeTo = NewText(page, "GameFontHighlightSmall")
    f.rangeTo:SetPoint("LEFT", f.levelMin, "RIGHT", 6, 0)
    f.rangeTo:SetText(L["to"])
    f.levelMax = NewEdit(page, 30, 20)
    f.levelMax:SetPoint("LEFT", f.rangeTo, "RIGHT", 10, 0)
    for key, box in pairs({ levelMin = f.levelMin, levelMax = f.levelMax }) do
        box:SetNumeric(true)
        box:SetMaxLetters(2)
        box:SetScript("OnTextChanged", function(self, byUser)
            if not byUser then return end
            settings[key] = tonumber(self:GetText()) or 0
            Refresh()
        end)
    end

    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, -80)
    list:SetPoint("BOTTOMRIGHT", 0, 18)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta * 3
        UpdateRows()
    end)
    local bg = list:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.35)
    f.list = list

    f.rows = {}
    local count = math.floor((f:GetHeight() - 34 - 80 - 18 - 30) / ROW_HEIGHT)
    for i = 1, count do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.stripe = row:CreateTexture(nil, "BACKGROUND")
        row.stripe:SetAllPoints()
        row.stripe:SetColorTexture(1, 1, 1, 0.04)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row.glow = row:CreateTexture(nil, "BORDER")
        row.glow:SetAllPoints()
        row.glow:SetColorTexture(1, 0.5, 1, 0.16)    -- whisper pink
        row.glow:Hide()

        row.header = NewText(row, "GameFontNormal")
        row.header:SetPoint("LEFT", 6, 0)
        row.name = NewText(row, "GameFontHighlightSmall", 126)
        row.name:SetPoint("LEFT", 8, 0)
        row.level = NewText(row, "GameFontHighlightSmall", 44)
        row.level:SetPoint("LEFT", 138, 0)
        row.roles = NewText(row, "GameFontHighlightSmall", 86)
        row.roles:SetPoint("LEFT", 186, 0)
        row.activity = NewText(row, "GameFontHighlightSmall", 150)
        row.activity:SetPoint("LEFT", 276, 0)
        row.activity:SetTextColor(1, 0.82, 0)
        row.action = NewButton(row, "", 84, 20, function(self)
            if self.run then self.run() end
        end)
        row.action:SetPoint("RIGHT", -2, 0)
        row.age = NewText(row, "GameFontHighlightSmall", 60)
        row.age:SetPoint("RIGHT", row.action, "LEFT", -4, 0)
        row.age:SetJustifyH("RIGHT")
        row.age:SetTextColor(0.7, 0.7, 0.7)
        row.comment = NewText(row, "GameFontHighlightSmall")
        row.comment:SetPoint("LEFT", 430, 0)
        row.comment:SetPoint("RIGHT", row.age, "LEFT", -6, 0)
        row.comment:SetTextColor(0.85, 0.85, 0.85)

        row:SetScript("OnClick", function(self, mouse)
            local entry = self.entry
            if not entry then return end
            if mouse == "RightButton" then
                RowMenu(self, entry)
            else
                Whisper(entry.name)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.entry then RowTooltip(self, self.entry) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = row
    end

    local hint = NewText(page, "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 2, 2)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["Hold Shift over the list to keep it still. Right-click a row for more."])
end

-- ── The Post page ───────────────────────────────────────────────────────────

local function ChannelList()
    local list = {}
    if not GetChannelList then return list end
    local raw = { GetChannelList() }
    local step = (type(raw[3]) == "boolean") and 3 or 2
    for i = 1, #raw, step do
        local id, name = raw[i], raw[i + 1]
        if type(id) == "number" and type(name) == "string" and not IsSecret(name) then
            list[#list + 1] = { id = id, name = name }
        end
    end
    return list
end

local function SendPost(given)
    local text = given or window.post:GetText() or ""
    text = text:gsub("|", "/")          -- a | in chat text is refused by the game
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        Say(L["Write the post first."])
        return
    end
    local now = GetTime()
    if now - lastSend < SEND_GAP then
        Say(L["Wait a few seconds between posts."])
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return end
    -- The same text twice in a row is dropped by the game's repeat filter.
    local out = text
    if lastSent == text then out = text .. " " end
    local sent = 0
    for _, channel in ipairs(ChannelList()) do
        if settings.postChannels[channel.name] then
            if pcall(send, out, "CHANNEL", nil, channel.id) then sent = sent + 1 end
        end
    end
    if sent == 0 then
        Say(L["Tick at least one channel to post to."])
        return
    end
    lastSend = now
    lastSent = (lastSent == text) and nil or text
    return true
end

-- One click from the Browse page: a post made from the dungeons picked there
-- and your roles. Alone: "LFG <dungeons> <my roles>". In a party: "LFM
-- <dungeons> need <roles still missing>". Goes to the channels ticked on the
-- Post page, and is put in the Post box so it can be changed and sent again.
local POST_ROLE = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
QuickPostText = function()
    local names = {}
    for i, id in ipairs(settings.picks) do
        if i > 3 then break end
        names[#names + 1] = ActivityName(id, true)
    end
    local where = #names > 0 and table.concat(names, " / ") or nil
    local roles = {}
    if InGroup() then
        local need = MissingRoles()
        if need then
            for _, role in ipairs(ROLES) do
                if need[role] then roles[#roles + 1] = POST_ROLE[role] end
            end
        end
        local text = "LFM" .. (where and (" " .. where) or "")
        if #roles > 0 then text = text .. " need " .. table.concat(roles, ", ") end
        return text, where ~= nil
    end
    local mine = RolesFrom(Call(C_LFGListRoles and C_LFGListRoles.GetRoles)) or {}
    for _, role in ipairs(ROLES) do
        if mine[role] then roles[#roles + 1] = POST_ROLE[role] end
    end
    local text = "LFG" .. (where and (" " .. where) or "")
    if #roles > 0 then text = text .. " " .. table.concat(roles, "/") end
    local level = MyLevel()
    if level and level > 0 then text = text .. ", level " .. level end
    return text, where ~= nil
end

QuickPost = function()
    local text, hasDungeon = QuickPostText()
    if not hasDungeon then
        Say(L["Pick at least one dungeon on the Browse page first."])
        return
    end
    if window.post then window.post:SetText(text) end
    if SendPost(text) then Say(L["Posted: %s"]:format(text)) end
end

local function AppendWord(word)
    local box = window.post
    local text = box:GetText() or ""
    if text ~= "" and text:sub(-1) ~= " " then text = text .. " " end
    box:SetText(text .. word .. " ")
    box:SetCursorPosition(#box:GetText())
end

local function PostDungeonMenu(owner)
    local level = MyLevel()
    OpenMenu(owner, function(_, root)
        if root.SetScrollMode then root:SetScrollMode(420) end
        for _, dungeon in ipairs(DUNGEONS) do
            local label = dungeon.name .. "  |cff999999" .. dungeon.min .. "-" .. dungeon.max .. "|r"
            if level >= dungeon.min - 2 and level <= dungeon.max + 2 then
                label = "|cff40ff40" .. dungeon.name .. "|r  |cff999999" .. dungeon.min .. "-" .. dungeon.max .. "|r"
            end
            root:CreateButton(label, function() AppendWord(dungeon.name) end)
        end
    end)
end

local function ListingStatus()
    if not HasFinder() then return L["This client has no group search. Chat posts still show."], false end
    local has = Ask(C_LFGList.HasActiveEntryInfo)
    if not has then return L["You are not listed."], false end
    local info = Call(C_LFGList.GetActiveEntryInfo)
    local names = {}
    if type(info) == "table" and type(info.activityIDs) == "table" then
        for i, id in ipairs(info.activityIDs) do
            if i > 4 then
                names[#names + 1] = "..."
                break
            end
            local plain = Safe(id)
            if plain then names[#names + 1] = ActivityName(plain, true) end
        end
    end
    return L["You are listed for: %s"]:format(table.concat(names, ", ")), true
end

local function ListMe()
    if not HasFinder() or not C_LFGList.CreateListing then return end
    if MyLevel() < MIN_LEVEL then
        Say(L["The game's group finder opens at level 10. Chat posts still show."])
        return
    end
    if InCombatLockdown() then
        Say(L["Not in combat."])
        return
    end
    if Ask(C_LFGList.HasActiveEntryInfo) then
        Say(L["You are listed already. Remove that listing first."])
        return
    end
    if #settings.picks == 0 then
        Say(L["Pick at least one dungeon on the Browse page first."])
        return
    end
    local ids = {}
    for _, id in ipairs(settings.picks) do ids[#ids + 1] = id end
    local playstyle = Enum and Enum.LFGEntryGeneralPlaystyle and Enum.LFGEntryGeneralPlaystyle.FunRelaxed or 2
    local voice = Enum and Enum.LFGEntryVoiceMode and Enum.LFGEntryVoiceMode.None or 0
    local ok, accepted = pcall(C_LFGList.CreateListing, {
        activityIDs = ids, newPlayerFriendly = false, generalPlaystyle = playstyle, voiceMode = voice,
    })
    if not ok or accepted == false then
        Say(L["The game refused the listing."])
    end
end

local function Delist()
    if not (C_LFGList and C_LFGList.RemoveListing) then return end
    if InCombatLockdown() then
        Say(L["Not in combat."])
        return
    end
    pcall(C_LFGList.RemoveListing)
end

UpdatePostPage = function()
    if not (window and window:IsShown()) or window.page ~= "post" then return end
    -- Channels
    local channels = ChannelList()
    for i, box in ipairs(window.channelBoxes) do
        local channel = channels[i]
        if channel then
            box.channel = channel.name
            if IsNetChannel(channel.name) then
                box.text:SetText("|cff66ccff" .. L["Group Finder network, every zone"] .. "|r")
            else
                box.text:SetText(channel.id .. ". " .. channel.name)
            end
            box:SetChecked(settings.postChannels[channel.name] == true)
            box:Show()
        else
            box:Hide()
        end
    end
    -- Saved posts
    for i, row in ipairs(window.savedRows) do
        local text = settings.posts[i]
        row.index = i
        if text then
            row.label:SetText(text)
            row:Show()
        else
            row:Hide()
        end
    end
    window.savedEmpty:SetShown(#settings.posts == 0)
    -- The game's own listing
    local status, listed = ListingStatus()
    window.listing:SetText(status)
    window.listMe:SetEnabled(not listed)
    window.delist:SetEnabled(listed)
    local mine = RolesFrom(Call(C_LFGListRoles and C_LFGListRoles.GetRoles)) or {}
    for _, role in ipairs(ROLES) do
        window.roleBoxes[role]:SetChecked(mine[role] == true)
    end
    local picks = #settings.picks
    if picks == 0 then
        window.listingPicks:SetText(L["No dungeon picked on the Browse page."])
    else
        local names = {}
        for i, id in ipairs(settings.picks) do
            if i > 4 then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = ActivityName(id, true)
        end
        window.listingPicks:SetText(L["Picked: %s"]:format(table.concat(names, ", ")))
    end
end

local function BuildPost(page)
    local f = window
    local title = NewText(page, "GameFontNormal")
    title:SetPoint("TOPLEFT", 2, -2)
    title:SetText(L["A post for chat"])

    f.post = NewEdit(page, 420, 22)
    f.post:SetPoint("TOPLEFT", 8, -24)
    f.post:SetMaxLetters(255)
    f.postCount = NewText(page, "GameFontHighlightSmall")
    f.postCount:SetPoint("LEFT", f.post, "RIGHT", 6, 0)
    f.postCount:SetTextColor(0.7, 0.7, 0.7)
    f.post:SetScript("OnTextChanged", function(self)
        f.postCount:SetText(#(self:GetText() or "") .. "/255")
    end)

    local words = { "LFG", "LFM", "Tank", "Healer", "DPS" }
    local previous
    for _, word in ipairs(words) do
        local button = NewButton(page, word, 60, 20, function() AppendWord(word) end)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("TOPLEFT", 2, -52)
        end
        previous = button
    end
    local dungeon = NewButton(page, L["Dungeon"], 100, 20, function(self) PostDungeonMenu(self) end)
    dungeon:SetPoint("LEFT", previous, "RIGHT", 2, 0)

    local postTo = NewText(page, "GameFontNormal")
    postTo:SetPoint("TOPLEFT", 2, -84)
    postTo:SetText(L["Post to"])
    f.channelBoxes = {}
    for i = 1, 10 do
        local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
        box:SetSize(22, 22)
        local column, line = (i - 1) % 2, math.floor((i - 1) / 2)
        box:SetPoint("TOPLEFT", 4 + column * 215, -102 - line * 22)
        box.text:SetFontObject("GameFontHighlightSmall")
        box:SetScript("OnClick", function(self)
            if self.channel then
                settings.postChannels[self.channel] = self:GetChecked() and true or false
            end
        end)
        f.channelBoxes[i] = box
    end

    local send = NewButton(page, L["Post"], 100, 24, function() SendPost() end)
    send:SetPoint("TOPLEFT", 2, -220)
    local save = NewButton(page, L["Save this post"], 130, 24, function()
        local text = (f.post:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return end
        for _, saved in ipairs(settings.posts) do
            if saved == text then return end
        end
        if #settings.posts >= MAX_POSTS then table.remove(settings.posts, 1) end
        settings.posts[#settings.posts + 1] = text
        UpdatePostPage()
    end)
    save:SetPoint("LEFT", send, "RIGHT", 4, 0)

    local savedTitle = NewText(page, "GameFontNormal")
    savedTitle:SetPoint("TOPLEFT", 2, -256)
    savedTitle:SetText(L["Saved posts"])
    f.savedEmpty = NewText(page, "GameFontHighlightSmall")
    f.savedEmpty:SetPoint("TOPLEFT", 8, -276)
    f.savedEmpty:SetTextColor(0.6, 0.6, 0.6)
    f.savedEmpty:SetText(L["None yet. Click a saved post to load it, right-click to delete it."])
    f.savedRows = {}
    for i = 1, MAX_POSTS do
        local row = CreateFrame("Button", nil, page)
        row:SetSize(440, 18)
        row:SetPoint("TOPLEFT", 4, -274 - (i - 1) * 18)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row.label = NewText(row, "GameFontHighlightSmall", 432)
        row.label:SetPoint("LEFT", 4, 0)
        row:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" then
                table.remove(settings.posts, self.index)
                UpdatePostPage()
            else
                f.post:SetText(settings.posts[self.index] or "")
            end
        end)
        f.savedRows[i] = row
    end

    -- The game's own listing, on the right.
    local side = CreateFrame("Frame", nil, page)
    side:SetPoint("TOPLEFT", 470, 0)
    side:SetPoint("BOTTOMRIGHT", 0, 0)
    local sideTitle = NewText(side, "GameFontNormal")
    sideTitle:SetPoint("TOPLEFT", 0, -2)
    sideTitle:SetText(L["The game's group finder"])
    f.listing = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.listing:SetPoint("TOPLEFT", 0, -24)
    f.listing:SetPoint("RIGHT", side, "RIGHT", -4, 0)
    f.listing:SetJustifyH("LEFT")
    f.listingPicks = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.listingPicks:SetPoint("TOPLEFT", 0, -62)
    f.listingPicks:SetPoint("RIGHT", side, "RIGHT", -4, 0)
    f.listingPicks:SetJustifyH("LEFT")
    f.listingPicks:SetTextColor(1, 0.82, 0)

    local myRoles = NewText(side, "GameFontHighlightSmall")
    myRoles:SetPoint("TOPLEFT", 0, -104)
    myRoles:SetText(L["My roles"])
    f.roleBoxes = {}
    local roleNames = { TANK = L["Tank"], HEALER = L["Healer"], DAMAGER = L["Damage"] }
    for i, role in ipairs(ROLES) do
        local box = CreateFrame("CheckButton", nil, side, "UICheckButtonTemplate")
        box:SetSize(22, 22)
        box:SetPoint("TOPLEFT", (i - 1) * 86, -120)
        box.text:SetFontObject("GameFontHighlightSmall")
        box.text:SetText(roleNames[role])
        box:SetScript("OnClick", function()
            if not (C_LFGListRoles and C_LFGListRoles.SetRoles) then return end
            local roles = {}
            for _, each in ipairs(ROLES) do
                roles[ROLE_FIELD[each]] = f.roleBoxes[each]:GetChecked() and true or false
            end
            pcall(C_LFGListRoles.SetRoles, roles)
        end)
        f.roleBoxes[role] = box
    end

    f.listMe = NewButton(side, L["List me"], 110, 24, function() ListMe() end)
    f.listMe:SetPoint("TOPLEFT", 0, -152)
    f.delist = NewButton(side, L["Remove listing"], 130, 24, function() Delist() end)
    f.delist:SetPoint("LEFT", f.listMe, "RIGHT", 4, 0)

    local note = side:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 0, -188)
    note:SetPoint("RIGHT", side, "RIGHT", -4, 0)
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.7, 0.7, 0.7)
    note:SetText(L["Alone you are listed among the players looking. With a party you are listed among the groups recruiting. The dungeons are the ones picked on the Browse page."])
end

-- ── The Whispers page ───────────────────────────────────────────────────────
-- The whispers of this session, newest first, each with Invite and Reply: the
-- answers to a post arrive here. Kept in memory only, never saved.

local MAX_WHISPERS = 30
local whispers = {}
local unseen = 0

local function UpdateWhispers()
    if not window then return end
    local label = L["Whispers"]
    if unseen > 0 then label = "|cffff80ff" .. label .. " (" .. unseen .. ")|r" end
    window.whisperTab:SetText(Toggled(window.page == "whispers", label))
    if not window:IsShown() or window.page ~= "whispers" then return end
    local now = GetTime()
    for i, row in ipairs(window.whisperRows) do
        local item = whispers[i]
        row.item = item
        if item then
            row.name:SetText(ClassIcon(item.classFile) .. " " .. ClassColoured(ShortName(item.name), item.classFile))
            row.text:SetText(item.text)
            row.age:SetText(AgeText(now - item.at))
            row.invite:SetText(GroupIsFull() and L["Full"] or (CanInvite() and L["Invite"] or L["Suggest"]))
            row.invite:SetEnabled(not GroupIsFull())
            -- New ones lit until read, the rest lit faintly while recent.
            local recent = now - item.at < WHISPER_GLOW
            row.glow:SetShown(item.isNew or recent)
            row.glow:SetAlpha(item.isNew and 1 or 0.45)
            row:Show()
        else
            row:Hide()
        end
    end
    window.whisperEmpty:SetShown(#whispers == 0)
end

local function BuildWhispers(page)
    local f = window
    f.whisperEmpty = NewText(page, "GameFontHighlightSmall")
    f.whisperEmpty:SetPoint("TOPLEFT", 6, -8)
    f.whisperEmpty:SetTextColor(0.6, 0.6, 0.6)
    f.whisperEmpty:SetText(L["Whispers you get while this is switched on show here, with a button to invite the sender."])
    f.whisperRows = {}
    local count = math.floor((f:GetHeight() - 34 - 40) / ROW_HEIGHT)
    for i = 1, math.min(count, MAX_WHISPERS) do
        local row = CreateFrame("Frame", nil, page)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        if i % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(1, 1, 1, 0.04)
        end
        row.glow = row:CreateTexture(nil, "BORDER")
        row.glow:SetAllPoints()
        row.glow:SetColorTexture(1, 0.5, 1, 0.18)    -- whisper pink
        row.glow:Hide()
        row.name = NewText(row, "GameFontHighlightSmall", 150)
        row.name:SetPoint("LEFT", 6, 0)
        row.decline = NewButton(row, L["Decline"], 76, 20, function()
            local item = row.item
            if not item then return end
            Decline(item.name)
            for i = #whispers, 1, -1 do
                if whispers[i].name == item.name then table.remove(whispers, i) end
            end
            UpdateWhispers()
            if Refresh then Refresh() end
        end)
        row.decline:SetPoint("RIGHT", -2, 0)
        row.reply = NewButton(row, L["Reply"], 76, 20, function()
            if row.item then Whisper(row.item.name) end
        end)
        row.reply:SetPoint("RIGHT", row.decline, "LEFT", -2, 0)
        row.invite = NewButton(row, L["Invite"], 84, 20, function()
            if row.item then Invite(row.item.name) end
        end)
        row.invite:SetPoint("RIGHT", row.reply, "LEFT", -2, 0)
        row.age = NewText(row, "GameFontHighlightSmall", 40)
        row.age:SetPoint("RIGHT", row.invite, "LEFT", -6, 0)
        row.age:SetJustifyH("RIGHT")
        row.age:SetTextColor(0.7, 0.7, 0.7)
        row.text = NewText(row, "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 162, 0)
        row.text:SetPoint("RIGHT", row.age, "LEFT", -6, 0)
        f.whisperRows[i] = row
    end
end

local function ShowPage(name)
    window.page = name
    window.browsePage:SetShown(name == "browse")
    window.postPage:SetShown(name == "post")
    window.whisperPage:SetShown(name == "whispers")
    window.browseTab:SetText(Toggled(name == "browse", L["Browse"]))
    window.postTab:SetText(Toggled(name == "post", L["Post"]))
    if name == "whispers" then
        unseen = 0
        -- Read now: they stay lit while this page is open, and dim next time.
        C_Timer.After(4, function()
            for _, item in ipairs(whispers) do item.isNew = nil end
            UpdateWhispers()
        end)
    end
    UpdateWhispers()
    if name == "browse" then
        UpdateTop()
        Refresh()
    elseif name == "post" then
        UpdatePostPage()
    end
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "OxedHubGroupFinderFrame", UIParent, "BasicFrameTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", "OxedHubGroupFinderFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    window = f
    f:Hide()
    UseIcons()
    f:SetSize(780, 520)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        settings.windowX, settings.windowY = self:GetLeft(), self:GetTop()
    end)
    if settings.windowX and settings.windowY then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.windowX, settings.windowY)
    else
        f:SetPoint("CENTER")
    end
    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
    end
    title:SetText(L["Group Finder"])
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "OxedHubGroupFinderFrame") end

    f.browseTab = NewButton(f, "", 90, 22, function() ShowPage("browse") end)
    f.browseTab:SetPoint("TOPLEFT", 12, -28)
    f.postTab = NewButton(f, "", 90, 22, function() ShowPage("post") end)
    f.postTab:SetPoint("LEFT", f.browseTab, "RIGHT", 2, 0)
    f.whisperTab = NewButton(f, "", 110, 22, function() ShowPage("whispers") end)
    f.whisperTab:SetPoint("LEFT", f.postTab, "RIGHT", 2, 0)
    local gear = NewButton(f, L["Options"], 90, 22, function() ShowOptions() end)
    gear:SetPoint("TOPRIGHT", -12, -28)

    f.browsePage = CreateFrame("Frame", nil, f)
    f.browsePage:SetPoint("TOPLEFT", 12, -56)
    f.browsePage:SetPoint("BOTTOMRIGHT", -12, 10)
    f.postPage = CreateFrame("Frame", nil, f)
    f.postPage:SetPoint("TOPLEFT", 12, -56)
    f.postPage:SetPoint("BOTTOMRIGHT", -12, 10)
    f.whisperPage = CreateFrame("Frame", nil, f)
    f.whisperPage:SetPoint("TOPLEFT", 12, -56)
    f.whisperPage:SetPoint("BOTTOMRIGHT", -12, 10)
    BuildBrowse(f.browsePage)
    BuildPost(f.postPage)
    BuildWhispers(f.whisperPage)

    f:SetScript("OnShow", function()
        EnsureCategory()
        ShowPage(f.page or "browse")
        if not ticker and C_Timer.NewTicker then
            -- Ages count up and old chat posts drop off while the window is open.
            ticker = C_Timer.NewTicker(5, function()
                if f.page == "post" then
                    UpdatePostPage()
                elseif f.page == "whispers" then
                    UpdateWhispers()
                else
                    RefreshSoon()
                end
            end)
        end
    end)
    f:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)
end

local function Toggle()
    if not running then
        Say(L["Group Finder is switched off. Switch it on in the Modules page."])
        return
    end
    if not window then CreateWindow() end
    window:SetShown(not window:IsShown())
end

-- ── A button beside the game's own window ───────────────────────────────────
-- The game's Looking For Group window must not be touched: a child of ours, a
-- hook or a call into it taints it and its searches break until a reload. So
-- this button belongs to UIParent, and a slow watch only READS where the
-- game's window is and puts the button above its top right corner. Every read
-- is in pcall: this client can hand out frames that throw on any question.

local HOST_CHECK = 0.2
local hostButton
local hostWatch = CreateFrame("Frame")
local hostElapsed = 0

local function HostCorner()
    local ok, right, top, scale = pcall(function()
        local host = LFGParentFrame
        if not host or (host.IsForbidden and host:IsForbidden()) or not host:IsShown() then return nil end
        return host:GetRight(), host:GetTop(), host:GetEffectiveScale()
    end)
    if not ok or type(right) ~= "number" or type(top) ~= "number" then return nil end
    if IsSecret(right) or IsSecret(top) or IsSecret(scale) then return nil end
    return right, top, (type(scale) == "number" and scale > 0) and scale or 1
end

local function UpdateHostButton()
    local right, top, scale
    if running and settings.gameButton then right, top, scale = HostCorner() end
    if not right then
        if hostButton then hostButton:Hide() end
        return
    end
    if not hostButton then
        hostButton = CreateFrame("Button", "OxedHubGroupFinderGameButton", UIParent, "UIPanelButtonTemplate")
        hostButton:SetSize(170, 22)
        hostButton:SetFrameStrata("HIGH")
        hostButton:SetClampedToScreen(true)
        hostButton:SetText(L["Oxed Group Finder"])
        hostButton:SetScript("OnClick", function()
            if not window then CreateWindow() end
            window:Show()
        end)
        hostButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["Oxed Group Finder"])
            GameTooltip:AddLine(L["The game's listings and group posts from chat in one list, with filters."], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hostButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    local ui = UIParent:GetEffectiveScale()
    if type(ui) ~= "number" or ui <= 0 then ui = 1 end
    local x, y = right * scale / ui, top * scale / ui
    if hostButton.x ~= x or hostButton.y ~= y then
        hostButton.x, hostButton.y = x, y
        hostButton:ClearAllPoints()
        hostButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMLEFT", x - 36, y + 1)
    end
    hostButton:Show()
end

local function WatchHost(on)
    if on then
        hostWatch:SetScript("OnUpdate", function(_, elapsed)
            hostElapsed = hostElapsed + elapsed
            if hostElapsed < HOST_CHECK then return end
            hostElapsed = 0
            UpdateHostButton()
        end)
    else
        hostWatch:SetScript("OnUpdate", nil)
        if hostButton then hostButton:Hide() end
    end
end

-- ── The invite card ─────────────────────────────────────────────────────────
-- When the player inviting you is in the listings of the last search, or
-- posted in chat, this says what the group is for and who is in it.

local function HideCard()
    if card then card:Hide() end
end

local function FindInviter(name)
    local short = ShortName(name)
    local now = GetTime()
    for leader, kept in pairs(leaders) do
        if (leader == name or ShortName(leader) == short) and now - kept.at <= LEADER_KEEP then
            return kept.entry
        end
    end
    for author, entry in pairs(posts) do
        if author == name or ShortName(author) == short then return entry end
    end
    return nil
end

local function ShowCard(name)
    if not settings.inviteCard or IsSecret(name) or type(name) ~= "string" then return end
    local entry = FindInviter(name)
    if not entry then return end
    UseIcons()
    if not card then
        card = CreateFrame("Frame", "OxedHubGroupFinderInvite", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        card:SetSize(300, 100)
        card:SetFrameStrata("DIALOG")
        card:SetClampedToScreen(true)
        card:EnableMouse(true)
        card:SetMovable(true)
        card:RegisterForDrag("LeftButton")
        card:SetScript("OnDragStart", card.StartMoving)
        card:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            settings.cardX, settings.cardY = self:GetLeft(), self:GetTop()
        end)
        card:SetScript("OnMouseUp", function(self, mouse)
            if mouse == "RightButton" then self:Hide() end
        end)
        if card.SetBackdrop then
            card:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            card:SetBackdropColor(0, 0, 0, 0.9)
            card:SetBackdropBorderColor(0.8, 0.6, 0.3, 1)
        end
        card.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        card.text:SetPoint("TOPLEFT", 10, -10)
        card.text:SetWidth(280)
        card.text:SetJustifyH("LEFT")
        card.text:SetSpacing(2)
    end
    local lines = {}
    lines[#lines + 1] = "|cffffd100" .. L["%s invites you"]:format(ClassColoured(ShortName(entry.name or name), entry.classFile)) .. "|r"
    if entry.activityText and entry.activityText ~= "" then
        lines[#lines + 1] = "|cffffd100" .. entry.activityText .. "|r"
    end
    if entry.comment and entry.comment ~= "" then lines[#lines + 1] = entry.comment end
    if entry.source == "native" then
        for _, member in ipairs(entry.members) do
            lines[#lines + 1] = (ROLE_LETTER[member.role] and (ROLE_LETTER[member.role] .. " ") or "")
                .. ClassColoured(member.name or "?", member.classFile)
                .. (member.level and ("  " .. member.level) or "")
                .. ((member.spec and member.spec ~= "") and ("  |cff999999" .. member.spec .. "|r") or "")
        end
        if entry.remaining then
            local open = {}
            for _, role in ipairs(ROLES) do
                local left = entry.remaining[role]
                if left and left > 0 then open[#open + 1] = ROLE_LETTER[role] .. " " .. left end
            end
            if #open > 0 then lines[#lines + 1] = L["Room for"] .. ": " .. table.concat(open, "  ") end
        end
    else
        lines[#lines + 1] = "|cff66ccff" .. L["From chat"] .. "|r"
    end
    lines[#lines + 1] = "|cff999999" .. L["Drag to move. Right-click to close."] .. "|r"
    card.text:SetText(table.concat(lines, "\n"))
    card:SetHeight(card.text:GetStringHeight() + 22)
    card:ClearAllPoints()
    if settings.cardX and settings.cardY then
        card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.cardX, settings.cardY)
    else
        card:SetPoint("TOP", UIParent, "TOP", 320, -150)
    end
    card:Show()
    card.shownAt = GetTime()
    local shownAt = card.shownAt
    C_Timer.After(CARD_TIME, function()
        if card and card.shownAt == shownAt then card:Hide() end
    end)
end

-- ── A word on entering a zone ───────────────────────────────────────────────
-- Which dungeons have their door in which zone. On entering one, a chat line
-- counts the groups and players already known for it: from the last search
-- and from chat. It never starts a search (that needs a click).

local ZONE_DUNGEONS = {
    ["Orgrimmar"] = { "Ragefire Chasm" },
    ["Ironforge"] = { "Hall of Thanes" },
    ["Tirisfal Glades"] = { "Ruins of Lordaeron", "Scarlet Monastery" },
    ["The Barrens"] = { "Wailing Caverns", "Razorfen Kraul", "Razorfen Downs" },
    ["Westfall"] = { "Deadmines" },
    ["Silverpine Forest"] = { "Shadowfang Keep" },
    ["Ashenvale"] = { "Blackfathom Deeps" },
    ["Stormwind City"] = { "Stockade" },
    ["Wetlands"] = { "Excavation Site" },
    ["Alterac Mountains"] = { "City of Dalaran" },
    ["Dun Morogh"] = { "Gnomeregan" },
    ["Stranglethorn Vale"] = { "Drowned City", "Zul'Gurub" },
    ["Riverglades"] = { "Krol'dok Stronghold" },
    ["Badlands"] = { "Uldaman" },
    ["Tanaris"] = { "Zul'Farrak" },
    ["Desolace"] = { "Maraudon" },
    ["Dustwallow Marsh"] = { "Alcaz Prison", "Onyxia's Lair" },
    ["Swamp of Sorrows"] = { "Sunken Temple" },
    ["Searing Gorge"] = { "Blackrock Depths", "Blackrock Spire" },
    ["Burning Steppes"] = { "Blackrock Depths", "Blackrock Spire" },
    ["Azshara"] = { "Blackmaw Hold" },
    ["Feralas"] = { "Dire Maul" },
    ["Western Plaguelands"] = { "Scholomance" },
    ["Eastern Plaguelands"] = { "Stratholme" },
    ["Un'Goro Crater"] = { "Shaper's Terrace" },
}

local lastZone

local function CheckZone()
    if not settings.zoneNotice then return end
    local zone = Call(GetRealZoneText)
    if type(zone) ~= "string" or IsSecret(zone) then return end
    local dungeons = ZONE_DUNGEONS[zone]
    if not dungeons then
        lastZone = nil
        return
    end
    if lastZone == zone then return end       -- once per visit
    lastZone = zone
    PruneChat()
    local parts = {}
    for _, dungeon in ipairs(dungeons) do
        local key = dungeon:lower()
        local groups, players = 0, 0
        local function Count(entry)
            if entry.delisted or entry.hasSelf then return end
            if (entry.activityText or ""):lower():find(key, 1, true) then
                if entry.isSolo then players = players + 1 else groups = groups + 1 end
            end
        end
        for _, entry in ipairs(results) do Count(entry) end
        for _, entry in pairs(posts) do Count(entry) end
        if groups + players > 0 then
            parts[#parts + 1] = L["%s: groups %d, players %d"]:format(dungeon, groups, players)
        end
    end
    if #parts > 0 then
        Say(table.concat(parts, ", ") .. ". " .. L["/oxlfg opens the list."])
    end
end

local function OnWhisper(text, author, guid)
    if IsSecret(text) or IsSecret(author) then return end
    if type(text) ~= "string" or type(author) ~= "string" or author == "" then return end
    local item = { name = author, text = StripCodes(text), at = GetTime(), isNew = true }
    whisperedBy[ShortName(author)] = item.at
    declinedByMe[ShortName(author)] = nil       -- they asked again
    if settings.whisperSound and settings.whisperSound ~= "None" and OxedHub.ModuleAPI and OxedHub.ModuleAPI.PlaySound then
        pcall(OxedHub.ModuleAPI.PlaySound, OxedHub.ModuleAPI, settings.whisperSound)
    end
    if Refresh then Refresh() end
    if guid and not IsSecret(guid) and GetPlayerInfoByGUID then
        local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
        if ok and type(classFile) == "string" and not IsSecret(classFile) then item.classFile = classFile end
    end
    table.insert(whispers, 1, item)
    while #whispers > MAX_WHISPERS do table.remove(whispers) end
    if not (window and window:IsShown() and window.page == "whispers") then unseen = unseen + 1 end
    UpdateWhispers()
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED",
    "GROUP_ROSTER_UPDATE", "CHAT_MSG_SYSTEM", "CHAT_MSG_CHANNEL", "CHAT_MSG_YELL",
    "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL", "CHAT_MSG_WHISPER", "ZONE_CHANGED_NEW_AREA",
}

events:SetScript("OnEvent", function(_, event, arg1, arg2, ...)
    if not running then return end
    if event == "CHAT_MSG_CHANNEL" or event == "CHAT_MSG_YELL" then
        -- arg9 is the channel's name, arg12 the sender's GUID.
        local channel = select(7, ...)
        local guid = select(10, ...)
        pcall(OnChatLine, arg1, arg2, channel, guid)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        pcall(CheckZone)
    elseif event == "CHAT_MSG_WHISPER" then
        pcall(OnWhisper, arg1, arg2, (select(10, ...)))
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        searching, searchFailed = false, false
        lastSearch = GetTime()
        scroll = 0
        CollectResults()
        Refresh()
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        searching, searchFailed = false, true
        Refresh()
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        if window and window:IsShown() and not searching then
            resultsDirty = true
            RefreshSoon()
        end
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        UpdatePostPage()
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        Say(L["The game refused the listing."])
        UpdatePostPage()
    elseif event == "GROUP_ROSTER_UPDATE" then
        if InGroup() then HideCard() end
        RefreshSoon()
    elseif event == "CHAT_MSG_SYSTEM" then
        if IsSecret(arg1) or type(arg1) ~= "string" then return end
        local name = arg1:match(DECLINE_PATTERN)
        if name and requested[name] then
            requested[name] = nil
            declined[name] = true
            Refresh()
        end
    elseif event == "PARTY_INVITE_REQUEST" then
        pcall(ShowCard, arg1)
    elseif event == "PARTY_INVITE_CANCEL" then
        HideCard()
    end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Group Finder", 460, 520)
        optionsWindow = w
        w:AddCheckbox(settings, "showChat", "Show group posts from chat in the list", nil, Refresh)
        w:AddSlider(settings, "chatMinutes", "A chat post stays for, minutes", 2, 30, 1, "%s: %d", Refresh)
        w:AddCheckbox(settings, "hideDelisted", "Hide listings that were taken down", nil, Refresh)
        w:AddCheckbox(settings, "hideDeclined", "Hide groups that declined your request", nil, Refresh)
        w:AddSlider(settings, "levelNear", "Near my level means within, levels", 1, 10, 1, "%s: %d", Refresh)
        w:AddCheckbox(settings, "inviteCard", "Show the group's details when a listed player invites me")
        w:AddCheckbox(settings, "alertChat", "Tell me in chat about a new post for a picked dungeon")
        w:AddSoundPicker(settings, "alertSound", "Sound for that post")
        w:AddSoundPicker(settings, "whisperSound", "Sound when someone whispers me")
        w:AddCheckbox(settings, "zoneNotice", "Tell me in chat when a zone I enter has groups for its dungeon",
            "Counts the groups and players already known from your last search and from chat. It never searches by itself.")
        w:AddCheckbox(settings, "network", "Join the Group Finder network",
            "A hidden chat channel shared by everyone who runs this module. A post you send from the Post page reaches them in every zone, and theirs reach you. Nothing shows in your chat windows.", ApplyNet)
        w:AddCheckbox(settings, "gameButton", "Show a button on the game's Looking For Group window",
            "A button above the game's own window that opens this list. The game's window itself is left alone.")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        local unhide = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        unhide:SetSize(220, 22)
        unhide:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 4)
        unhide:SetText(L["Show hidden players again"])
        unhide:SetScript("OnClick", function()
            wipe(settings.hidden)
            wipe(declined)
            Refresh()
        end)
        w.cursorY = w.cursorY - 32
        w:AddNote("The game only answers a search started by a click, so the list of the game's own listings is as fresh as your last press of Search. Posts from chat arrive by themselves, from the channels you are in. The game's group finder opens at level 10. Chat posts work at any level.")
        w:SetHeight(math.max(200, 16 - w.cursorY))
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "groupfinder", label = L["Group Finder"], icon = "Interface\\Icons\\INV_Misc_Spyglass_03", config = settings,
        hint = L["Click: the list. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else Toggle() end
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBGROUPFINDER1 = "/oxlfg"
SlashCmdList.OXEDHUBGROUPFINDER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" then
        ShowOptions()
    else
        Toggle()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Built for WoW Forever's group finder. The main game's is another thing
    -- with another API, so there the module does not exist at all.
    if OxedHub.IsMainline then return end

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.groupfinder
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.groupfinder = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Lists are made here, never in DEFAULTS (they would be shared).
    for _, key in ipairs({ "picks", "hidden", "hiddenClasses", "hiddenStyles", "presets", "posts", "postChannels" }) do
        if type(config[key]) ~= "table" then config[key] = {} end
    end
    if config.postChannels[NET_CHANNEL] == nil then config.postChannels[NET_CHANNEL] = true end
    settings = config

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "groupfinder",
        name     = "Group Finder",
        version  = "1.5.0",
        updated  = 20261114.1,  -- Post LFG, Decline, whispers lit
        added    = 20261111,
        inDevelopment = true,
        author   = "Oxed",
        category = "groups",
        keywords = { "lfg", "lfm", "group", "finder", "dungeon", "party", "looking", "tank", "healer", "chat", "forever" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "The game's group listings and group posts from chat in one list, with filters. /oxlfg",
        icon     = "Interface\\Icons\\INV_Misc_Spyglass_03",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            for _, key in ipairs({ "picks", "hidden", "hiddenClasses", "hiddenStyles", "presets", "posts", "postChannels" }) do
                if type(settings[key]) ~= "table" then settings[key] = {} end
            end
            if settings.postChannels[NET_CHANNEL] == nil then settings.postChannels[NET_CHANNEL] = true end
            running = true
            WatchHost(true)
            FilterNetChannel()
            C_Timer.After(NET_JOIN_DELAY, JoinNet)
            if not netTicker and C_Timer.NewTicker then
                netTicker = C_Timer.NewTicker(NET_CHECK, JoinNet)
            end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
        end,

        OnDisable = function()
            running = false
            WatchHost(false)
            if netTicker then
                netTicker:Cancel()
                netTicker = nil
            end
            LeaveNet()
            if minimapIcon then minimapIcon:Apply(false) end
            events:UnregisterAllEvents()
            if window then window:Hide() end
            HideCard()
            wipe(posts)
            wipe(results)
            wipe(whispers)
            unseen = 0
            searching, searchFailed = false, false
        end,
    })
end)
