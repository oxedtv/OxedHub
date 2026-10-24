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
    warnTalk        = true,   -- warn when an ignored player whispers you or talks in your group
    warnLFG         = true,   -- warn when a Group Finder leader or applicant is ignored
    askReason       = true,   -- ask for a reason whenever someone is ignored
    trackRecent     = true,   -- remember who you grouped or played a match with
    recentDays      = 7,      -- and for how long
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
local RefreshManager, OpenManager, SetIgnored, SyncToBlizzard, HookBlizzardIgnore

-- Set while OxedHub itself adds to or removes from Blizzard's ignore list
-- (the 50-slot sync), so the hook on that list can tell those calls from the
-- player ignoring someone through the game's own menus.
local ourIgnoreCall = false
local function OurIgnoreCall(fn, ...)
    ourIgnoreCall = true
    local ok = pcall(fn, ...)
    ourIgnoreCall = false
    return ok
end

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
    -- name -> { seen, where, class, guid, count }: who you played with lately.
    settings.recent  = type(settings.recent) == "table" and settings.recent or {}
end

local function PruneExpired()
    local now, removed = time(), 0
    for key, entry in pairs(settings.players) do
        if type(entry) == "table" and entry.expires and entry.expires > 0 and entry.expires <= now then
            settings.players[key] = nil
            removed = removed + 1
            if settings.syncBlizzard and C_FriendList and C_FriendList.DelIgnore then
                OurIgnoreCall(C_FriendList.DelIgnore, key)
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
            OurIgnoreCall(C_FriendList.AddIgnore, full)
            C_Timer.After(1, function() inBlizzardSync = false end)
        end
    else
        settings.players[full] = nil
        print(PREFIX .. ("no longer ignoring %s."):format(full))
        if settings.syncBlizzard and C_FriendList and C_FriendList.DelIgnore then
            inBlizzardSync = true
            OurIgnoreCall(C_FriendList.DelIgnore, full)
            C_Timer.After(1, function() inBlizzardSync = false end)
        end
    end
    if RefreshManager then RefreshManager() end
end

-- ── Reason for an ignore ────────────────────────────────────────────────────
-- Asked right after the ignore, which has already happened: Skip leaves the
-- player ignored with no note. The box is Blizzard's own popup, which takes
-- the keyboard on purpose and lets it go when closed.

local function ReasonEditBox(dialog)
    return dialog and (dialog.EditBox or dialog.editBox)
end

local function AskReason(full)
    if not (settings and settings.askReason and full and settings.players[full]) then return end
    if not StaticPopupDialogs.OXEDHUB_IGNORE_REASON then
        StaticPopupDialogs.OXEDHUB_IGNORE_REASON = {
            text = "Ignoring |cffffd100%s|r.\nWhy? (shown whenever they turn up again)",
            button1 = "Save",
            button2 = "Skip",
            hasEditBox = true,
            maxLetters = 120,
            OnShow = function(dialog, data)
                local box = ReasonEditBox(dialog)
                local entry = data and settings.players[data]
                if box then box:SetText(type(entry) == "table" and entry.note or "") end
            end,
            OnAccept = function(dialog, data)
                local box = ReasonEditBox(dialog)
                local entry = data and settings.players[data]
                if box and type(entry) == "table" then
                    local text = box:GetText() or ""
                    text = text:match("^%s*(.-)%s*$")
                    entry.note = text ~= "" and text or nil
                    if RefreshManager then RefreshManager() end
                end
            end,
            EditBoxOnEnterPressed = function(box)
                local dialog = box:GetParent()
                local which = dialog and dialog.which
                local info = which and StaticPopupDialogs[which]
                if info and info.OnAccept then info.OnAccept(dialog, dialog.data) end
                dialog:Hide()
            end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("OXEDHUB_IGNORE_REASON", full, nil, full)
end

-- ── Warnings ────────────────────────────────────────────────────────────────
-- One line per player and situation every two minutes, with the reason, and a
-- raid warning on screen for the ones that matter right now.

local lastWarned = {}
local WARN_GAP = 120

local function NoteFor(full)
    local entry = full and settings.players[full]
    local note = type(entry) == "table" and entry.note or nil
    if note then return note end
    local realm = full and full:match("%-(.+)$")
    if realm and settings.realms[realm:lower()] then return "ignored realm" end
    return nil
end

local function WarnIgnored(full, what, loud)
    if not full then return end
    local key = full .. "|" .. what
    local now = GetTime()
    if lastWarned[key] and now - lastWarned[key] < WARN_GAP then return end
    lastWarned[key] = now
    local note = NoteFor(full)
    local line = ("%s %s%s"):format(full, what, note and (". Reason: " .. note) or "")
    print(PREFIX .. "|cffff5555Ignored:|r " .. line)
    if loud then
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            pcall(RaidNotice_AddMessage, RaidWarningFrame, "Ignored: " .. line, ChatTypeInfo.RAID_WARNING)
        end
        if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master") end
    end
end

-- ── Reporting ───────────────────────────────────────────────────────────────
-- Blizzard's own report window, opened for a player. From a chat line (its
-- lineID) the report carries the message itself; otherwise the player's GUID
-- stands in. The window asks for the reason; opening it is no protected
-- action, so an addon may do it.

local function OpenReport(full, guid, lineID)
    if not (ReportFrame and ReportFrame.InitiateReport and ReportInfo and ReportInfo.CreateReportInfoFromType
        and PlayerLocation and Enum and Enum.ReportType) then
        print(PREFIX .. "the game's report window is not available here.")
        return false
    end
    local location, kind
    if lineID ~= nil and not SecretValue(lineID) and PlayerLocation.CreateFromChatLineID then
        local ok, loc = pcall(PlayerLocation.CreateFromChatLineID, PlayerLocation, lineID)
        if ok and loc then location, kind = loc, Enum.ReportType.Chat end
    end
    if not location and type(guid) == "string" and not SecretValue(guid) and PlayerLocation.CreateFromGUID then
        local ok, loc = pcall(PlayerLocation.CreateFromGUID, PlayerLocation, guid)
        if ok and loc then location, kind = loc, Enum.ReportType.InWorld end
    end
    if not location then
        print(PREFIX .. ("cannot report %s from here: the game gave no way to point at them. Report them from a chat line or while they are near."):format(full or "this player"))
        return false
    end
    local okInfo, info = pcall(ReportInfo.CreateReportInfoFromType, ReportInfo, kind)
    if not okInfo or not info then return false end
    return (pcall(ReportFrame.InitiateReport, ReportFrame, info, full, location))
end

-- A Battle.net friend, by account. The constructor's name differs between
-- builds, so each known spelling is tried.
local function OpenBnetReport(bnetID, name)
    if SecretValue(bnetID) or type(bnetID) ~= "number" or bnetID <= 0 then return false end
    if not (ReportFrame and ReportFrame.InitiateReport and ReportInfo and ReportInfo.CreateReportInfoFromType
        and PlayerLocation and Enum and Enum.ReportType) then
        print(PREFIX .. "the game's report window is not available here.")
        return false
    end
    local location
    for _, method in ipairs({ "CreateFromBNetAccountID", "CreateFromBattleNetAccountID", "CreateFromBattlenetID" }) do
        local ctor = PlayerLocation[method]
        if ctor then
            local ok, loc = pcall(ctor, PlayerLocation, bnetID)
            if ok and loc then location = loc break end
        end
    end
    local kind = Enum.ReportType.Chat or Enum.ReportType.InWorld
    if not location or kind == nil then
        print(PREFIX .. "this client cannot report a Battle.net friend from an addon.")
        return false
    end
    local okInfo, info = pcall(ReportInfo.CreateReportInfoFromType, ReportInfo, kind)
    if not okInfo or not info then return false end
    return (pcall(ReportFrame.InitiateReport, ReportFrame, info, name, location))
end

-- ── Who you played with ─────────────────────────────────────────────────────
-- Everyone in your party or raid, and everyone on a battleground or arena
-- scoreboard, is noted with where it was. The point: the player who ruined a
-- key or threw a match without a word cannot be ignored from a chat line, and
-- once the group breaks up they are gone. Here they stay for recentDays.
-- Account-wide, like the ignore list. A name the game keeps secret is skipped.

local RECENT_CAP = 400

local function PlainValue(value)
    if value == nil or SecretValue(value) then return nil end
    return value
end

local function WhereNow()
    local okInfo, name, kind, _, difficultyName = pcall(GetInstanceInfo)
    name, kind, difficultyName = okInfo and PlainValue(name), okInfo and PlainValue(kind), okInfo and PlainValue(difficultyName)
    if kind == nil or kind == "none" then
        local zone = GetRealZoneText and PlainValue(GetRealZoneText())
        return "Group" .. (type(zone) == "string" and zone ~= "" and (", " .. zone) or "")
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local okKey, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        level = okKey and PlainValue(level)
        if type(level) == "number" and level > 0 then return ("%s +%d"):format(name or "Mythic+", level) end
    end
    if type(difficultyName) == "string" and difficultyName ~= "" and kind ~= "pvp" and kind ~= "arena" then
        return ("%s (%s)"):format(name or "Instance", difficultyName)
    end
    return name or "Instance"
end

local function Remember(full, where, class, guid)
    if not (full and settings.trackRecent) then return end
    local me = UnitName("player")
    if not SecretValue(me) and ShortName(full) == me then return end
    local entry = settings.recent[full]
    local now = time()
    if type(entry) ~= "table" then
        entry = { count = 0 }
        settings.recent[full] = entry
    end
    -- One sighting per place per hour counts once.
    if entry.where ~= where or now - (entry.seen or 0) > 3600 then entry.count = (entry.count or 0) + 1 end
    entry.seen, entry.where = now, where
    if class then entry.class = class end
    if guid then entry.guid = guid end
end

local function RememberUnit(unit, where)
    local okName, name, realm = pcall(UnitName, unit)
    if not okName then return end
    local full = FullName(name, realm)
    if not full then return end
    local okGuid, guid = pcall(UnitGUID, unit)
    guid = okGuid and PlainValue(guid)
    local okClass, _, class = pcall(UnitClass, unit)
    class = okClass and PlainValue(class)
    Remember(full, where, type(class) == "string" and class or nil, type(guid) == "string" and guid or nil)
end

local function RememberGroup()
    if not (settings and settings.trackRecent) then return end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if count == 0 then return end
    local where = WhereNow()
    if IsInRaid() then
        for i = 1, count do RememberUnit("raid" .. i, where) end
    else
        for i = 1, count - 1 do RememberUnit("party" .. i, where) end
    end
end

-- ── The last match ──────────────────────────────────────────────────────────
-- Arena and battleground only: everyone seen while inside, from every source
-- the game gives. Your group, arena1..5, whatever your team targets, every
-- nameplate that comes into view, and the scoreboard (the only thing that
-- names an arena opponent while their names are secret). Kept after you leave,
-- since a report is usually decided afterwards, and replaced when the next
-- match starts. settings.lastMatch = { where, started, result, rating,
-- ratingChange, mmr, mmrChange, players = { [full] = { class, guid, rating,
-- ratingChange } } }.

local inMatch = false
local matchTicker

local function InPvPMatch()
    local ok, _, kind = pcall(GetInstanceInfo)
    kind = ok and PlainValue(kind)
    return kind == "pvp" or kind == "arena"
end

-- true, false, or nil when the answer is secret. Testing a secret boolean is
-- itself the error, so it is never tested outside this.
local function Known(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok or SecretValue(value) then return nil end
    return value and true or false
end

local function MatchEntry(full)
    local m = settings.lastMatch
    if type(m) ~= "table" or not full then return nil end
    if type(m.players) ~= "table" then m.players = {} end
    local e = m.players[full]
    if type(e) ~= "table" then
        e = {}
        m.players[full] = e
    end
    return e
end

local function IsMe(full)
    local me = UnitName("player")
    return full ~= nil and not SecretValue(me) and ShortName(full) == me
end

local function SeenInMatch(unit)
    if not (inMatch and settings.trackRecent and type(unit) == "string") then return end
    -- Only a definite yes: a secret answer leaves the unit out.
    if Known(UnitIsPlayer, unit) ~= true then return end
    local okName, name, realm = pcall(UnitName, unit)
    if not okName then return end
    local full = FullName(name, realm)
    if not full or IsMe(full) then return end
    local okGuid, guid = pcall(UnitGUID, unit)
    guid = okGuid and PlainValue(guid)
    guid = type(guid) == "string" and guid or nil
    local okClass, _, class = pcall(UnitClass, unit)
    class = okClass and PlainValue(class)
    class = type(class) == "string" and class or nil
    Remember(full, settings.lastMatch.where, class, guid)
    local e = MatchEntry(full)
    if e then
        e.class = class or e.class
        e.guid = guid or e.guid
    end
end

local function ScanMatch()
    if not inMatch or not settings or settings.enabled == false then return end
    for i = 1, 5 do SeenInMatch("arena" .. i) end
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid()
    for i = 1, raid and count or count - 1 do
        local unit = (raid and "raid" or "party") .. i
        SeenInMatch(unit)
        SeenInMatch(unit .. "target")   -- enemies your team fights, even far from you
    end
    SeenInMatch("target")
    SeenInMatch("focus")
end

-- A scoreboard's zeroes mean "no rating here" (skirmishes, unrated
-- battlegrounds), never a rating of 0.
local function Rated(value)
    value = PlainValue(value)
    if type(value) ~= "number" or value == 0 then return nil end
    return value
end

local function ReadOutcome(myRow)
    local m = settings.lastMatch
    if type(m) ~= "table" then return end
    if type(myRow) == "table" then
        m.rating = Rated(myRow.rating) or m.rating
        m.ratingChange = Rated(myRow.ratingChange) or m.ratingChange
        m.mmr = Rated(myRow.prematchMMR) or m.mmr
        m.mmrChange = Rated(myRow.mmrChange) or m.mmrChange
        local side = PlainValue(myRow.faction)
        if type(side) == "number" then m.side = side end
    end
    -- Solo shuffle has no single winner: the rating's direction says it.
    if C_PvP and C_PvP.IsSoloShuffle and Known(C_PvP.IsSoloShuffle) then
        if m.ratingChange then m.result = m.ratingChange > 0 and "Rating up" or "Rating down" end
        return
    end
    local okWinner, winner = pcall(GetBattlefieldWinner)
    winner = okWinner and PlainValue(winner)
    if type(winner) ~= "number" then return end
    if winner == 255 then
        m.result = "Draw"
    elseif m.side then
        m.result = winner == m.side and "Victory" or "Defeat"
    end
end

-- Battleground and arena scoreboards name both teams, including the half you
-- never stood near. Their GUIDs are secret, so those rows report from chat or
-- in person only.
local function RememberScoreboard()
    if not (settings and settings.trackRecent and C_PvP and C_PvP.GetScoreInfo and GetNumBattlefieldScores) then return end
    local okCount, count = pcall(GetNumBattlefieldScores)
    count = okCount and PlainValue(count)
    if type(count) ~= "number" or count == 0 then return end
    local where = WhereNow()
    local myRow
    for i = 1, count do
        -- One row at a time: a secret in one row leaves the rest readable.
        local ok, info = pcall(C_PvP.GetScoreInfo, i)
        if ok and type(info) == "table" and not SecretValue(info) then
            local full = FullName(info.name)
            local class = PlainValue(info.classToken)
            class = type(class) == "string" and class or nil
            if IsMe(full) then
                myRow = info
            elseif full then
                Remember(full, where, class, nil)
                if inMatch then
                    local e = MatchEntry(full)
                    e.class = class or e.class
                    e.rating = Rated(info.rating) or e.rating
                    e.ratingChange = Rated(info.ratingChange) or e.ratingChange
                end
            end
        end
    end
    if inMatch then ReadOutcome(myRow) end
end

-- Entering a match from outside starts a new one; leaving keeps it.
local function CheckMatch()
    if not settings then return end
    local now = InPvPMatch()
    if now and not inMatch then
        inMatch = true
        settings.lastMatch = { where = WhereNow(), started = time(), players = {} }
        if not matchTicker then matchTicker = C_Timer.NewTicker(5, ScanMatch) end
        C_Timer.After(1, ScanMatch)
    elseif not now and inMatch then
        inMatch = false
        if matchTicker then matchTicker:Cancel() matchTicker = nil end
    end
end

local function PruneRecent()
    if type(settings.recent) ~= "table" then return end
    local cutoff = time() - math.max(1, tonumber(settings.recentDays) or 7) * 86400
    local list = {}
    for full, entry in pairs(settings.recent) do
        if type(entry) ~= "table" or (entry.seen or 0) < cutoff then
            settings.recent[full] = nil
        else
            list[#list + 1] = full
        end
    end
    if #list > RECENT_CAP then
        table.sort(list, function(a, b) return (settings.recent[a].seen or 0) > (settings.recent[b].seen or 0) end)
        for i = RECENT_CAP + 1, #list do settings.recent[list[i]] = nil end
    end
end

local groupScanQueued = false
local function QueueGroupScan()
    if groupScanQueued then return end
    groupScanQueued = true
    C_Timer.After(2, function()
        groupScanQueued = false
        RememberGroup()
    end)
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
            OurIgnoreCall(C_FriendList.AddIgnore, name)
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
            WarnIgnored(full, "is in your group", true)
        end
    end
end

-- Lines from the people you talk to and play with: an ignored one is warned
-- about (the line itself is hidden by the filter as before).
local TALK_EVENTS = {
    CHAT_MSG_WHISPER = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
    CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true,
    CHAT_MSG_INSTANCE_CHAT = true, CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}

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
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if event == "GROUP_ROSTER_UPDATE" then CheckGroup() end
        if event == "PLAYER_ENTERING_WORLD" then CheckMatch() end
        QueueGroupScan()
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        CheckMatch()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- Caught as it appears: an enemy who runs past once is gone by the next scan.
        if inMatch then SeenInMatch(name) end
    elseif event == "ARENA_OPPONENT_UPDATE" then
        if inMatch then SeenInMatch(name) end
    elseif event == "UPDATE_BATTLEFIELD_SCORE" or event == "PVP_MATCH_COMPLETE" then
        RememberScoreboard()
    elseif TALK_EVENTS[event] and settings.warnTalk then
        -- name here is the line's text; the author comes next. Either can be
        -- a secret: FullName gives nil for one, and nothing is warned.
        local author = ...
        local full = FullName(author)
        if full and IsIgnoredPlayer(full) then
            WarnIgnored(full, event == "CHAT_MSG_WHISPER" and "whispered you" or "is talking in your group")
        end
    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" and settings.warnLFG then
        -- name here is the search result id, the status comes next.
        local status = ...
        if status ~= "applied" and status ~= "invited" then return end
        local ok, info = pcall(C_LFGList.GetSearchResultInfo, name)
        if not ok or type(info) ~= "table" or SecretValue(info) then return end
        local full = FullName(info.leaderName)
        if full and IsIgnoredPlayer(full) then
            if status == "invited" then
                WarnIgnored(full, "leads the group that just invited you", true)
            else
                WarnIgnored(full, "leads a group you signed up to", true)
            end
        end
    elseif event == "LFG_LIST_APPLICANT_LIST_UPDATED" and settings.warnLFG then
        -- Someone applying to your own listing, or anyone in their group.
        if not (C_LFGList.GetApplicants and C_LFGList.GetApplicantInfo and C_LFGList.GetApplicantMemberInfo) then return end
        local ok, applicants = pcall(C_LFGList.GetApplicants)
        if not ok or type(applicants) ~= "table" or SecretValue(applicants) then return end
        for _, applicantID in ipairs(applicants) do
            local okInfo, info = pcall(C_LFGList.GetApplicantInfo, applicantID)
            local members = okInfo and type(info) == "table" and not SecretValue(info) and info.numMembers or 0
            if SecretValue(members) or type(members) ~= "number" then members = 0 end
            for i = 1, members do
                local okMember, memberName = pcall(C_LFGList.GetApplicantMemberInfo, applicantID, i)
                local full = okMember and FullName(memberName)
                if full and IsIgnoredPlayer(full) then
                    WarnIgnored(full, "applied to your group", true)
                end
            end
        end
    end
end)

local SOCIAL_EVENTS = {
    "DUEL_REQUESTED", "PARTY_INVITE_REQUEST", "GUILD_INVITE_REQUEST",
    "TRADE_REQUEST", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UPDATE_BATTLEFIELD_SCORE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "LFG_LIST_APPLICATION_STATUS_UPDATED", "LFG_LIST_APPLICANT_LIST_UPDATED",
    "ZONE_CHANGED_NEW_AREA", "NAME_PLATE_UNIT_ADDED", "ARENA_OPPONENT_UPDATE", "PVP_MATCH_COMPLETE",
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
    -- A Battle.net friend's menu has no Report of its own. Its name is a
    -- protected string, so it goes to the report window untouched.
    pcall(Menu.ModifyMenu, "MENU_UNIT_BN_FRIEND", function(_, root, contextData)
        if not settings or settings.enabled == false then return end
        if type(contextData) ~= "table" or SecretValue(contextData)
            or (canaccesstable and not canaccesstable(contextData)) then return end
        local bnetID = contextData.bnetIDAccount
        if SecretValue(bnetID) or type(bnetID) ~= "number" then return end
        root:CreateDivider()
        root:CreateButton("Report (OxedHub)", function()
            OpenBnetReport(bnetID, contextData.name)
        end)
    end)
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
                if not ignored then AskReason(full) end
            end)
            -- A name clicked in chat brings the line it came from. The game's
            -- own chat menu has no Report at all; this one sends the message
            -- along with the name. Unit menus already have Blizzard's Report.
            local lineID = type(contextData) == "table" and not SecretValue(contextData) and contextData.lineID or nil
            if lineID ~= nil and not SecretValue(lineID) then
                root:CreateButton("Report this message", function()
                    OpenReport(full, nil, lineID)
                end)
                if not ignored then
                    root:CreateButton("Ignore + report", function()
                        SetIgnored(full, true)
                        AskReason(full)
                        OpenReport(full, nil, lineID)
                    end)
                end
            end
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

-- A row laid out in columns: item.cols = { text, ... } under COLUMN_WIDTHS;
-- the last column takes what is left up to the delete button.
local COLUMN_WIDTHS = { 110, 105, 46, 58 }

local function DrawColumns(row, cols)
    row.cols = row.cols or {}
    local x = 6
    for i, text in ipairs(cols) do
        local fs = row.cols[i]
        if not fs then
            fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            row.cols[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        local width = COLUMN_WIDTHS[i]
        if width then
            fs:SetWidth(width - 6)
            x = x + width
        else
            fs:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
        end
        fs:SetText(text or "")
        fs:Show()
    end
    for i = #cols + 1, #row.cols do row.cols[i]:Hide() end
end

local function DrawRows(items)
    local y = 0
    for index, item in ipairs(items) do
        local row = GetRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", manager.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", manager.content, "TOPRIGHT", 0, -y)
        if item.cols then
            DrawColumns(row, item.cols)
            row.left:SetText("")
            row.right:SetText("")
        else
            if row.cols then DrawColumns(row, {}) end
            row.left:SetText(item.left or "")
            row.right:SetText(item.right or "")
        end
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

    -- Columns: name, realm, how long on the list, when it expires, the note.
    local GOLD = "|cffffd100%s|r"
    items[1] = { cols = { GOLD:format("Player Name"), GOLD:format("Server Name"), GOLD:format("Listed"),
        GOLD:format("Expires"), GOLD:format("Note") } }
    local now = time()

    for _, full in ipairs(names) do
        local entry = settings.players[full]
        if type(entry) ~= "table" then entry = {} end
        local name, realm = full:match("^([^%-]+)%-(.+)$")
        name, realm = name or full, realm or ""
        local listed = entry.added and ("%dd"):format(math.max(0, math.floor((now - entry.added) / 86400))) or ""
        local expires
        if entry.expires and entry.expires > 0 then
            expires = ("|cff55ff55%dd|r"):format(math.max(0, math.ceil((entry.expires - now) / 86400)))
        else
            expires = "|cff888888Never|r"
        end
        local ownNote = entry.note
        local note = ownNote or GameIgnoreNote(full)
        items[#items + 1] = {
            cols = {
                "|cffffd100" .. name .. "|r",
                realm,
                listed,
                expires,
                note and ((ownNote and "|cff66ccff" or "|cff9d9d9d") .. note .. "|r") or "",
            },
            tooltipTitle = full,
            tooltip = (entry.added and ("Added " .. date("%Y-%m-%d", entry.added)) or "Added before dates were kept")
                .. (note and ("\nNote: " .. note) or ""),
            onDelete = function() SetIgnored(full, false) end,
        }
    end

    for realm in pairs(settings.realms) do
        if filterText == "" or realm:lower():find(filterText, 1, true) then
            items[#items + 1] = {
                cols = { "|cff00ccff[Realm]|r", realm, "", "|cff888888Never|r", "|cff9d9d9deveryone from this realm|r" },
                onDelete = function() settings.realms[realm] = nil; RefreshManager() end,
            }
        end
    end

    for npc in pairs(settings.npcs) do
        if filterText == "" or npc:lower():find(filterText, 1, true) then
            items[#items + 1] = {
                cols = { "|cffffaa00[NPC]|r", npc, "", "|cff888888Never|r", "|cff9d9d9dmonster or NPC|r" },
                onDelete = function() settings.npcs[npc] = nil; RefreshManager() end,
            }
        end
    end

    if #items == 1 then
        items[2] = { left = "|cff9d9d9dNo matching ignores found.|r" }
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

-- ── Tab: Recent ─────────────────────────────────────────────────────────────

local function TimeAgo(t)
    local d = time() - (t or 0)
    if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
    if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
    return ("%dd ago"):format(math.floor(d / 86400))
end

local function ClassColour(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

local function Whisper(full)
    if ChatFrameUtil and ChatFrameUtil.SendTell then
        pcall(ChatFrameUtil.SendTell, full)
    elseif ChatFrame_SendTell then
        pcall(ChatFrame_SendTell, full)
    end
end

local function RecentMenu(owner, full, entry)
    local ignored = settings.players[full] ~= nil
    local function Ignore()
        if ignored then
            SetIgnored(full, false)
        else
            SetIgnored(full, true, entry.where and ("Played together: " .. entry.where) or nil)
            AskReason(full)
        end
    end
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        Ignore()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(full)
        root:CreateButton(ignored and "Unignore" or "Ignore...", Ignore)
        root:CreateButton(entry.guid and "Report" or "Report (needs them near or a chat line)", function()
            OpenReport(full, entry.guid, nil)
        end)
        root:CreateButton("Whisper", function() Whisper(full) end)
        root:CreateButton("Forget", function()
            settings.recent[full] = nil
            RefreshManager()
        end)
    end)
end

local function DrawRecentTab()
    PruneRecent()
    local filterText = manager.searchBox and manager.searchBox:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    local list = {}
    for full, entry in pairs(settings.recent) do
        local where = entry.where or ""
        if filterText == "" or full:lower():find(filterText, 1, true) or where:lower():find(filterText, 1, true) then
            list[#list + 1] = full
        end
    end
    table.sort(list, function(a, b) return (settings.recent[a].seen or 0) > (settings.recent[b].seen or 0) end)

    local items = {}
    for _, full in ipairs(list) do
        local entry = settings.recent[full]
        local ignored = IsIgnoredPlayer(full)
        local note = ignored and NoteFor(full)
        items[#items + 1] = {
            left = ("|c%s%s|r  |cff9d9d9d%s|r%s"):format(ClassColour(entry.class), full, entry.where or "",
                ignored and "  |cffff5555ignored|r" or ""),
            right = TimeAgo(entry.seen),
            tooltipTitle = full,
            tooltip = ("|cffffd100Where:|r %s\n|cffffd100Last seen:|r %s\n|cffffd100Times:|r %d%s\n\n|cff00ff00Click: ignore, report or whisper.|r")
                :format(entry.where or "?", date("%Y-%m-%d %H:%M", entry.seen or 0), entry.count or 1,
                    note and ("\n|cffff5555Ignored:|r " .. note) or ""),
            onClick = function(row) RecentMenu(row, full, entry) end,
            onDelete = function()
                settings.recent[full] = nil
                RefreshManager()
            end,
        }
    end
    if #items == 0 then
        items[1] = { left = settings.trackRecent and "|cff9d9d9dNobody yet. Everyone you group with or play a match against shows up here.|r"
            or "|cff9d9d9dSwitched off in the Chat Filter options.|r" }
    end
    DrawRows(items)
    manager.count:SetText(("%d players, last %d days"):format(#list, tonumber(settings.recentDays) or 7))
end

-- ── Tab: Last match ─────────────────────────────────────────────────────────

local function Signed(n)
    if not n then return "" end
    return n > 0 and ("|cff40ff40+%d|r"):format(n) or ("|cffff5050%d|r"):format(n)
end

local function MatchSummary(m)
    if type(m) ~= "table" then return "|cff9d9d9dNo arena or battleground yet.|r" end
    local colour = (m.result == "Victory" or m.result == "Rating up") and "ff40ff40"
        or (m.result == "Defeat" or m.result == "Rating down") and "ffff5050" or "ffffd100"
    local parts = { ("|c%s%s|r"):format(colour, m.result or "In progress or not known"), m.where or "" }
    if m.rating then parts[#parts + 1] = ("Rating %d %s"):format(m.rating, Signed(m.ratingChange)) end
    if m.mmr then parts[#parts + 1] = ("MMR %d %s"):format(m.mmr, Signed(m.mmrChange)) end
    if m.started then parts[#parts + 1] = "|cff9d9d9d" .. date("%H:%M", m.started) .. "|r" end
    return table.concat(parts, "   ")
end

local function DrawMatchTab()
    local m = settings.lastMatch
    local filterText = manager.searchBox and manager.searchBox:GetText():lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
    local items = { { left = MatchSummary(m) } }
    local names = {}
    if type(m) == "table" and type(m.players) == "table" then
        for full in pairs(m.players) do
            if filterText == "" or full:lower():find(filterText, 1, true) then names[#names + 1] = full end
        end
    end
    table.sort(names)
    for _, full in ipairs(names) do
        local e = m.players[full]
        local ignored = IsIgnoredPlayer(full)
        local menuEntry = settings.recent[full] or { where = m.where, guid = e.guid, class = e.class }
        if not menuEntry.guid then menuEntry.guid = e.guid end
        items[#items + 1] = {
            left = ("|c%s%s|r%s%s"):format(ClassColour(e.class), full,
                e.rating and ("  |cff9d9d9d%d|r"):format(e.rating) or "",
                ignored and "  |cffff5555ignored|r" or ""),
            right = Signed(e.ratingChange),
            tooltipTitle = full,
            tooltip = (e.guid and "" or "|cff9d9d9dOnly on the scoreboard: report them from a chat line, or while they are near.|r\n")
                .. "|cff00ff00Click: ignore, report or whisper.|r",
            onClick = function(row) RecentMenu(row, full, menuEntry) end,
        }
    end
    if #names == 0 and type(m) == "table" then
        items[2] = { left = "|cff9d9d9dNobody seen yet.|r" }
    end
    DrawRows(items)
    manager.count:SetText(("%d players"):format(#names))
end

local function BuildMatchPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hint:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Everyone in your last arena or battleground: your team, the enemy team from the scoreboard and arena frames, "
        .. "whoever your team targeted and every nameplate you saw. It stays after you leave and is replaced when the next match starts. "
        .. "Open it with a key: Key Bindings, Oxed Hub, Last Match Players.")
    return panel
end

local function BuildRecentPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    local clear = MakeButton(panel, "Clear list", 90, function()
        wipe(settings.recent)
        RefreshManager()
    end)
    clear:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    hint:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Your group, dungeon, key, raid, battleground and arena players. Click one to ignore, report or whisper them, even if they never said a word.")
    return panel
end

-- ── Building the Manager Window ─────────────────────────────────────────────

local TABS = {
    { key = "ignore",  label = "Ignore List" },
    { key = "filters", label = "Spam Filters" },
    { key = "blocked", label = "Blocked" },
    { key = "recent",  label = "Recent" },
    { key = "match",   label = "Last Match" },
}

function RefreshManager()
    if not (manager and manager:IsShown()) then return end
    for _, button in ipairs(manager.tabButtons) do
        if button.key == manager.tab then button:LockHighlight() else button:UnlockHighlight() end
    end
    manager.ignorePanel:SetShown(manager.tab == "ignore")
    manager.filterPanel:SetShown(manager.tab == "filters")
    manager.blockedPanel:SetShown(manager.tab == "blocked")
    manager.recentPanel:SetShown(manager.tab == "recent")
    manager.matchPanel:SetShown(manager.tab == "match")
    manager.searchBox:SetShown(manager.tab ~= "filters")

    if manager.tab == "filters" then
        DrawFiltersTab()
    elseif manager.tab == "match" then
        DrawMatchTab()
    elseif manager.tab == "blocked" then
        DrawBlockedTab()
    elseif manager.tab == "recent" then
        DrawRecentTab()
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
                    OurIgnoreCall(C_FriendList.DelIgnore, key)
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
        local button = MakeButton(manager, tabInfo.label, 92, function()
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
    manager.searchBox = MakeInput(manager, 150, "Search...")
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
    manager.recentPanel  = BuildRecentPanel(bottom)
    manager.matchPanel   = BuildMatchPanel(bottom)

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

-- The key binding (Bindings.xml): the Last Match tab, or closes the window.
-- Named at file scope, so the key is listed even with the module off.
BINDING_NAME_OXEDHUB_CHATFILTER_LASTMATCH = "Last Match Players (Chat Filter)"
function OxedHub_ChatFilterLastMatch()
    if not settings or settings.enabled == false then
        print(PREFIX .. "switched off. Switch it on in OxedHub's Modules page first.")
        return
    end
    if manager and manager:IsShown() and manager.tab == "match" then
        manager:Hide()
    else
        OpenManager("match")
    end
end

-- ── Switching on ────────────────────────────────────────────────────────────

-- Someone ignored through the game itself (its right-click menu, /ignore):
-- they join the account-wide list too, and the reason is asked for. OxedHub's
-- own sync calls are marked and skipped.
local blizzardHooked = false
local function OnBlizzardIgnore(name, toggled)
    if ourIgnoreCall or not settings or settings.enabled == false then return end
    local full = FullName(name)
    if not full then return end
    -- AddOrDelIgnore may have removed them instead: asked a moment later.
    C_Timer.After(0.5, function()
        local okIgnored, isIgnored = pcall(C_FriendList.IsIgnored, name)
        if toggled and okIgnored and not SecretValue(isIgnored) and not isIgnored then return end
        if not settings.players[full] then
            SetIgnored(full, true)
            AskReason(full)
        end
    end)
end

function HookBlizzardIgnore()
    if blizzardHooked or not C_FriendList then return end
    blizzardHooked = true
    if C_FriendList.AddIgnore then
        hooksecurefunc(C_FriendList, "AddIgnore", function(name) OnBlizzardIgnore(name, false) end)
    end
    if C_FriendList.AddOrDelIgnore then
        hooksecurefunc(C_FriendList, "AddOrDelIgnore", function(name) OnBlizzardIgnore(name, true) end)
    end
end

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
    HookBlizzardIgnore()

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
        local adding = full and not settings.players[full]
        SetIgnored(full, adding, note)
        if adding and (not note or note == "") then AskReason(full) end
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
        optionsWindow = API:CreateOptionsWindow("Chat Filter & Global Ignore", 450, 700)
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
        optionsWindow:AddCheckbox(settings, "warnTalk", "Warn when an ignored player whispers or talks in your group",
            "One line with your reason, at most every two minutes per player.")
        optionsWindow:AddCheckbox(settings, "warnLFG", "Warn about ignored players in the Group Finder",
            "When you sign up to a group an ignored player leads, are invited by one, or one applies to your group.")
        optionsWindow:AddCheckbox(settings, "askReason", "Ask for a reason when ignoring",
            "A small window after each ignore, including the game's own Ignore. Skip keeps them ignored with no note.")
        optionsWindow:AddCheckbox(settings, "trackRecent", "Remember who I played with",
            "Group, dungeon, key, raid, battleground and arena players, in the manager's Recent Players tab.")
        optionsWindow:AddSlider(settings, "recentDays", "Keep them for", 1, 30, 1, "%s %d days")
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
        version  = "1.5.0",
        updated  = 20261024.8,  -- Last Match tab, more PvP players caught, Battle.net report
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
