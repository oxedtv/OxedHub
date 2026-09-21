-- ============================================================================
-- Chat Filter (built-in OxedHub module)
-- Takes the noise out of chat: an ignore list with no size limit, word filters
-- you write yourself, and built-in catches for the spam every city channel has.
--
--   Ignore   players, whole realms and NPCs. Shared by every character on the
--            account, with a note and an optional expiry on each entry.
--   Filters  your own rules: words or phrases, matched as whole words, as part
--            of a word, or as a Lua pattern, limited to the channels you choose.
--   Presets  boosting and gold selling, guild recruitment, community invites,
--            Asian-script text, raid-icon spam, and the same message repeated.
--   Blocked  a log of what was hidden this session and why, so a filter that
--            catches too much can be seen and fixed instead of guessed at.
--
-- Also turns down duels and group invites from ignored players, and warns when
-- one of them is in your group.
--
-- The game's own ignore list stops at 50 names. This one does not touch it: a
-- message from anyone on this list is hidden before a chat window draws it.
-- ============================================================================

local addonName, OxedHub = ...

-- ⚠ Only true/false/number/string here. ModuleAPI copies defaults key by key,
-- and a table default would be stored by reference -- every edit the player
-- made would be written into DEFAULTS itself. Lists are created in EnsureData.
local DEFAULTS = {
    enabled         = false,  -- off until the player switches it on (see ModuleAPI:Register)

    presetBoost     = true,   -- boost carries, gold selling, "pay in raid"
    presetGuild     = false,  -- guild recruitment
    presetCommunity = true,   -- community and club invite links
    presetAsian     = false,  -- Chinese, Japanese and Korean text
    presetIcons     = true,   -- lines built out of raid target icons
    presetRepeat    = true,   -- the same sender saying the same thing again

    keepGuild       = true,   -- never filter guild or officer chat
    keepGroup       = true,   -- never filter party, raid or instance chat
    keepFriends     = true,   -- never filter friends
    keepWhispers    = false,  -- never word-filter whispers (ignores still apply)

    declineDuels    = true,
    declineInvites  = true,
    warnGroup       = true,
}

local settings          -- OxedHubDB.modules.chatfilter, bound at login
local manager           -- the manager window, built on first open
local optionsWindow
local installed = false

local PREFIX = "|cff00ff00OxedHub:|r "

local REPEAT_WINDOW = 90     -- seconds the same line from the same sender is a repeat
local LOG_LIMIT = 200        -- blocked lines kept for this session
local EXPIRY_STEPS = { 0, 1, 7, 30, 90 }   -- days; 0 means never

-- Forward declarations: these are referenced by code above their definitions.
local RefreshManager, OpenManager

-- ── Names ───────────────────────────────────────────────────────────────────

local function PlayerRealm()
    return (GetNormalizedRealmName and GetNormalizedRealmName())
        or (GetRealmName and GetRealmName():gsub("[%s%-]", "")) or ""
end

-- "name", "Name-Realm" or "name-Some Realm" all become "Name-Realm", so one
-- person is one key whichever way the game or the player spelled them.
local function FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    local short, fromName = name:match("^([^%-]+)%-(.+)$")
    if short then name, realm = short, fromName end
    realm = (realm and realm ~= "") and realm:gsub("[%s%-]", "") or PlayerRealm()
    name = name:sub(1, 1):upper() .. name:sub(2):lower()
    return name .. "-" .. realm, realm
end

local function ShortName(full)
    return (full and full:match("^([^%-]+)")) or full
end

-- ── Saved data ──────────────────────────────────────────────────────────────

local function EnsureData()
    settings.players = type(settings.players) == "table" and settings.players or {}
    settings.realms  = type(settings.realms) == "table" and settings.realms or {}
    settings.npcs    = type(settings.npcs) == "table" and settings.npcs or {}
    settings.filters = type(settings.filters) == "table" and settings.filters or {}
end

-- Entries whose expiry has passed are removed at login, not left to linger.
local function PruneExpired()
    local now, removed = time(), 0
    for key, entry in pairs(settings.players) do
        if type(entry) == "table" and entry.expires and entry.expires > 0 and entry.expires <= now then
            settings.players[key] = nil
            removed = removed + 1
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

local function SetIgnored(full, on, note, days)
    if not full then return end
    if on then
        settings.players[full] = {
            note = note ~= "" and note or nil,
            added = time(),
            expires = (days and days > 0) and (time() + days * 86400) or 0,
        }
        print(PREFIX .. ("now ignoring %s."):format(full))
    else
        settings.players[full] = nil
        print(PREFIX .. ("no longer ignoring %s."):format(full))
    end
    if RefreshManager then RefreshManager() end
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

-- ── Matching ────────────────────────────────────────────────────────────────

-- What the message says, without colour codes or link markup, in lower case.
-- The words inside a link are kept, so "[Thunderfury]" still reads as text.
local function Plain(msg)
    local text = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text:lower()
end

local function EscapePattern(text)
    return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

-- One term against the plain text. A Lua pattern the player typed wrongly is an
-- error, not a false, so it is asked inside pcall and treated as no match.
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

-- Which kind of chat a line came from, in the terms a filter's scope uses.
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
-- Each preset scores signals rather than matching one word. A single signal is
-- ordinary conversation -- "boost" or "vip" on their own mean nothing -- and it
-- is two or more together that make an advert. That is what keeps these from
-- hiding people who are only talking about the thing.

local BOOST_SIGNALS = {
    "wts", "boost", "boosting", "carry", "carries", "pilot", "piloted", "selfplay",
    "self play", "vip", "unsaved", "pay in raid", "gold only", "going now",
    "cheapest", "discount", "discord", "armor stack", "loot funnel", "fully geared",
}

local function ScoreBoost(plain)
    local score = 0
    for _, signal in ipairs(BOOST_SIGNALS) do
        if plain:find(signal, 1, true) then score = score + 1 end
    end
    -- Prices: "450k", "1.3m", "=200k".
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

-- UTF-8 lead bytes for the CJK blocks and Hangul. Cyrillic and accented Latin
-- sit elsewhere and are deliberately left alone.
local function HasAsianScript(raw)
    return raw:find("[\227-\237][\128-\191][\128-\191]") ~= nil
end

local function CountIcons(raw)
    local _, braces = raw:gsub("{[^}]+}", "")
    local _, textures = raw:gsub("RaidTargetingIcon", "")
    return braces + textures
end

local recentLines, recentCount = {}, 0     -- sender -> { text, at }

local function IsRepeat(sender, plain, now)
    -- A busy city meets thousands of senders in a session. Anything older than
    -- the repeat window can no longer match, so the table is cleared of it now
    -- and then instead of growing for as long as the game stays open.
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
    if settings.presetRepeat and lineScope ~= "whisper" and IsRepeat(sender, plain, now) then
        return "Preset: repeated message"
    end
    return nil
end

-- ── Who is never filtered ───────────────────────────────────────────────────

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

-- ── The filter ──────────────────────────────────────────────────────────────

-- A chat filter is called once for every chat window showing the line, so the
-- same message can arrive three or four times. Each line is decided once, by
-- its line id, and every window gets that same answer -- which also keeps the
-- repeat preset from counting a single line as its own repeat, and the log
-- from listing it once per window.
local decisions, decisionCount = {}, 0

-- ⚠ Chat text can be a secret value in restricted content, and any string
-- operation on a secret errors. Such a line is shown untouched rather than
-- read; filtering it is not possible, and breaking chat is worse than spam.
local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Decide(event, msg, author, channelBaseName, guid)
    if type(msg) ~= "string" then return false end

    if NPC_EVENTS[event] then
        if type(author) == "string" and settings.npcs[author:lower()] then
            return true, "Ignored NPC", author
        end
        return false
    end

    local full = FullName(author)
    if not full then return false end
    if ShortName(full) == UnitName("player") and full:match("%-(.+)$") == PlayerRealm() then
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
    -- The extras can be secret on their own even when the text is not, and a
    -- secret number fails the moment it is compared. Dropped, not read.
    if IsSecret(lineID) then lineID = nil end
    if IsSecret(channelBaseName) then channelBaseName = nil end
    if IsSecret(guid) then guid = nil end

    if lineID and lineID > 0 and decisions[lineID] ~= nil then
        return decisions[lineID]
    end

    local ok, block, reason, sender = pcall(Decide, event, msg, author, channelBaseName, guid)
    if not ok then block = false end   -- a filter bug must never eat chat

    if lineID and lineID > 0 then
        decisions[lineID] = block and true or false
        decisionCount = decisionCount + 1
        if decisionCount > 1000 then decisions, decisionCount = {}, 0 end
    end

    if block then LogBlocked(reason, sender or tostring(author), msg, event) end
    return block and true or false
end

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_WHISPER", "CHAT_MSG_AFK", "CHAT_MSG_DND",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_EMOTE",
    "CHAT_MSG_MONSTER_WHISPER", "CHAT_MSG_MONSTER_PARTY", "CHAT_MSG_RAID_BOSS_EMOTE",
    "CHAT_MSG_COMMUNITIES_CHANNEL",
}

-- The long-standing global is asked for first: it is known to work on 12.0.
-- ChatFrameUtil is the newer home for the same call and is kept as the
-- fallback for a build that has retired the global.
local function AddFilter(event, fn)
    if ChatFrame_AddMessageEventFilter then
        return ChatFrame_AddMessageEventFilter(event, fn)
    elseif ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        return ChatFrameUtil.AddMessageEventFilter(event, fn)
    end
end

-- ── Duels, invites and group warnings ───────────────────────────────────────

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
        if IsIgnoredPlayer(FullName(name)) then
            CancelDuel()
            StaticPopup_Hide("DUEL_REQUESTED")
            LogBlocked("Declined duel", FullName(name), "Duel request", event)
        end
    elseif event == "PARTY_INVITE_REQUEST" and settings.declineInvites then
        if IsIgnoredPlayer(FullName(name)) then
            DeclineGroup()
            StaticPopup_Hide("PARTY_INVITE")
            LogBlocked("Declined invite", FullName(name), "Group invite", event)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        CheckGroup()
    end
end)

-- ── Right-click menus ───────────────────────────────────────────────────────

-- The name on a unit menu. A chat name carries name and server in the context;
-- a unit frame carries a unit to ask instead.
local function MenuTarget(contextData)
    if type(contextData) ~= "table" then return nil end
    if contextData.name then
        return FullName(contextData.name, contextData.server)
    end
    if contextData.unit and UnitIsPlayer(contextData.unit) then
        local name, realm = UnitName(contextData.unit)
        return FullName(name, realm)
    end
    return nil
end

local MENU_TAGS = {
    "MENU_UNIT_FRIEND", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER",
    "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER",
}

local function InstallMenus()
    if not (Menu and Menu.ModifyMenu) then return end
    for _, tag in ipairs(MENU_TAGS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, contextData)
            if not settings or settings.enabled == false then return end
            local full = MenuTarget(contextData)
            if not full or ShortName(full) == UnitName("player") then return end
            local ignored = settings.players[full] ~= nil
            root:CreateDivider()
            root:CreateButton(ignored and "Unignore (OxedHub)" or "Ignore (OxedHub)", function()
                SetIgnored(full, not ignored)
            end)
        end)
    end
end

-- ── The manager window ──────────────────────────────────────────────────────

local ROW_HEIGHT = 20

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
        box.hint:SetPoint("LEFT", box, "LEFT", 2, 0)
        box.hint:SetText(hint)
        box:SetScript("OnTextChanged", function(self)
            self.hint:SetShown(self:GetText() == "")
        end)
    end
    return box
end

-- A button whose text walks through a list of choices. Used instead of dropdown
-- menus, whose templates have changed too often between builds to rely on.
local function MakeCycle(parent, width, choices, onChange)
    local button = MakeButton(parent, "", width)
    button.choices, button.index = choices, 1
    function button:SetValue(key)
        for index, choice in ipairs(self.choices) do
            if choice.key == key then self.index = index end
        end
        self:SetText(self.choices[self.index].label)
    end
    function button:GetValue() return self.choices[self.index].key end
    button:SetScript("OnClick", function(self)
        self.index = self.index % #self.choices + 1
        self:SetText(self.choices[self.index].label)
        if onChange then onChange(self:GetValue()) end
    end)
    button:SetValue(choices[1].key)
    return button
end

local function GetRow(index)
    local rows = manager.rows
    if rows[index] then return rows[index] end

    local row = CreateFrame("Button", nil, manager.content)
    row:SetHeight(ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
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

-- Draws a list of items: { left, right, checked, onCheck, onDelete, onClick,
-- tooltip, tooltipTitle }. A missing handler hides that control on the row.
local function DrawRows(items)
    local y = 0
    for index, item in ipairs(items) do
        local row = GetRow(index)
        -- TOPLEFT and TOPRIGHT, never LEFT/RIGHT plus TOP: LEFT and RIGHT pin
        -- the vertical centre, and the two disagree about where the row sits.
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

local function DrawIgnoreTab()
    local items = {}
    local names = {}
    for full in pairs(settings.players) do names[#names + 1] = full end
    table.sort(names)

    for _, full in ipairs(names) do
        local entry = settings.players[full]
        local right = ""
        if type(entry) == "table" and entry.expires and entry.expires > 0 then
            right = ("%dd left"):format(math.max(0, math.ceil((entry.expires - time()) / 86400)))
        end
        local note = type(entry) == "table" and entry.note
        items[#items + 1] = {
            left = full .. (note and ("  |cff9d9d9d" .. note .. "|r") or ""),
            right = right,
            tooltipTitle = full,
            tooltip = (type(entry) == "table" and entry.added)
                and ("Added " .. date("%Y-%m-%d", entry.added)) or nil,
            onDelete = function() SetIgnored(full, false) end,
        }
    end
    for realm in pairs(settings.realms) do
        items[#items + 1] = {
            left = "|cffffd100Realm|r  " .. realm, right = "whole realm",
            onDelete = function() settings.realms[realm] = nil; RefreshManager() end,
        }
    end
    for npc in pairs(settings.npcs) do
        items[#items + 1] = {
            left = "|cffffd100NPC|r  " .. npc, right = "npc",
            onDelete = function() settings.npcs[npc] = nil; RefreshManager() end,
        }
    end
    if #items == 0 then
        items[1] = { left = "|cff9d9d9dNothing ignored yet. Add a name below, or right-click a name in chat.|r" }
    end
    DrawRows(items)
    manager.count:SetText(("%d player(s)"):format(#names))
end

local function AddIgnoreFromInputs()
    local panel = manager.ignorePanel
    local text = panel.name:GetText():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end

    local kind = panel.kind:GetValue()
    if kind == "realm" then
        settings.realms[text:gsub("[%s%-]", ""):lower()] = true
        print(PREFIX .. ("now ignoring everyone from %s."):format(text))
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
    { key = "presetBoost",     label = "Boosting and gold selling",  tip = "Adverts for carries, piloting, VIP runs and gold. Needs several signals together -- prices, 'pay in raid', 'unsaved' -- so a player just mentioning a boost is not hidden." },
    { key = "presetGuild",     label = "Guild recruitment",          tip = "Messages recruiting for a guild or raiding team." },
    { key = "presetCommunity", label = "Community invites",          tip = "Links inviting you to join a community." },
    { key = "presetAsian",     label = "Asian-script text",          tip = "Chinese, Japanese and Korean text. Cyrillic and accented letters are not affected." },
    { key = "presetIcons",     label = "Raid icon spam",             tip = "Lines using three or more raid target icons." },
    { key = "presetRepeat",    label = "Repeated messages",          tip = "The same sender posting the same line again within 90 seconds. Whispers are never counted." },
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

local function DrawFiltersTab()
    local items = {}
    for _, preset in ipairs(PRESETS) do
        items[#items + 1] = {
            left = "|cffffd100Built-in|r  " .. preset.label,
            checked = settings[preset.key],
            onCheck = function(on) settings[preset.key] = on and true or false end,
            tooltipTitle = preset.label, tooltip = preset.tip,
        }
    end
    for index, filter in ipairs(settings.filters) do
        items[#items + 1] = {
            left = (filter.name ~= "" and filter.name or "Unnamed") .. "  |cff9d9d9d" .. (filter.terms or "") .. "|r",
            right = filter.scope ~= "all" and filter.scope or "",
            checked = filter.on ~= false,
            onCheck = function(on) filter.on = on and true or false end,
            onClick = function() manager.editing = index; RefreshManager() end,
            onDelete = function()
                table.remove(settings.filters, index)
                manager.editing = nil
                RefreshManager()
            end,
            tooltipTitle = "Click to edit",
            tooltip = ("Terms: %s\nMatch: %s, %s"):format(filter.terms or "", filter.mode or "contains", filter.match or "any"),
        }
    end
    DrawRows(items)
    manager.count:SetText(("%d filter(s)"):format(#settings.filters))

    local panel = manager.filterPanel
    local filter = manager.editing and settings.filters[manager.editing]
    panel.name:SetText(filter and filter.name or "")
    panel.terms:SetText(filter and filter.terms or "")
    panel.mode:SetValue(filter and filter.mode or "contains")
    panel.match:SetValue(filter and filter.match or "any")
    panel.scope:SetValue(filter and filter.scope or "all")
    panel.link:SetValue(filter and filter.needLink or false)
    panel.save:SetText(filter and "Save" or "Add filter")
end

local function SaveFilterFromInputs()
    local panel = manager.filterPanel
    local terms = panel.terms:GetText()
    if #SplitTerms(terms) == 0 then
        print(PREFIX .. "a filter needs at least one word to look for.")
        return
    end
    local filter = (manager.editing and settings.filters[manager.editing]) or {}
    filter.name = panel.name:GetText()
    filter.terms = terms
    filter.mode = panel.mode:GetValue()
    filter.match = panel.match:GetValue()
    filter.scope = panel.scope:GetValue()
    filter.needLink = panel.link:GetValue()
    if filter.on == nil then filter.on = true end
    if not manager.editing then settings.filters[#settings.filters + 1] = filter end
    manager.editing = nil
    RefreshManager()
end

-- ── Tab: Blocked ────────────────────────────────────────────────────────────

local function DrawBlockedTab()
    local items = {}
    for index = #blockedLog, 1, -1 do
        local line = blockedLog[index]
        local sender = line.sender or "?"
        items[#items + 1] = {
            left = ("|cff9d9d9d%s|r  %s: %s"):format(date("%H:%M", line.time), ShortName(sender), Plain(line.text or "")),
            right = line.reason,
            tooltipTitle = sender .. "  --  " .. (line.reason or ""),
            tooltip = (line.text or "") .. "\n\n|cff9d9d9dClick to ignore this sender.|r",
            onClick = function()
                local full = FullName(sender)
                if full and not settings.players[full] then SetIgnored(full, true) end
            end,
        }
    end
    if #items == 0 then
        items[1] = { left = "|cff9d9d9dNothing blocked this session.|r" }
    end
    DrawRows(items)
    manager.count:SetText(("%d blocked"):format(#blockedLog))
end

-- ── Building the window ─────────────────────────────────────────────────────

local TABS = {
    { key = "ignore",  label = "Ignore" },
    { key = "filters", label = "Filters" },
    { key = "blocked", label = "Blocked" },
}

function RefreshManager()
    if not (manager and manager:IsShown()) then return end
    for _, button in ipairs(manager.tabButtons) do
        if button.key == manager.tab then button:LockHighlight() else button:UnlockHighlight() end
    end
    manager.ignorePanel:SetShown(manager.tab == "ignore")
    manager.filterPanel:SetShown(manager.tab == "filters")
    manager.blockedPanel:SetShown(manager.tab == "blocked")

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

    panel.kind = MakeCycle(panel, 70, IGNORE_KINDS)
    panel.kind:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)

    panel.name = MakeInput(panel, 170, "Name-Realm, realm or NPC")
    panel.name:SetPoint("LEFT", panel.kind, "RIGHT", 10, 0)
    panel.name:SetScript("OnEnterPressed", function(self) self:ClearFocus(); AddIgnoreFromInputs() end)

    panel.note = MakeInput(panel, 140, "Note (optional)")
    panel.note:SetPoint("LEFT", panel.name, "RIGHT", 10, 0)

    panel.expiry = MakeCycle(panel, 120, EXPIRY_CHOICES)
    panel.expiry:SetPoint("TOPLEFT", panel.kind, "BOTTOMLEFT", 0, -6)

    local add = MakeButton(panel, "Add", 80, AddIgnoreFromInputs)
    add:SetPoint("LEFT", panel.expiry, "RIGHT", 8, 0)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", add, "RIGHT", 10, 0)
    hint:SetText("Tip: right-click a name in chat to ignore it.")
    return panel
end

local function BuildFilterPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    panel.name = MakeInput(panel, 120, "Filter name")
    panel.name:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, 0)

    panel.terms = MakeInput(panel, 300, "Words to catch, separated by commas")
    panel.terms:SetPoint("LEFT", panel.name, "RIGHT", 10, 0)

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
    hint:SetText("Hover a line to read it, click to ignore the sender. Kept for this session only.")
    return panel
end

local function BuildManager()
    if manager then return manager end

    manager = CreateFrame("Frame", "OxedHubChatFilterWindow", UIParent, "BasicFrameTemplateWithInset")
    manager:SetSize(640, 470)
    manager:SetPoint("CENTER")
    -- FULLSCREEN_DIALOG, like OxedHub's own popups: the main window lives in DIALOG
    -- with parts raised as high as level 500, so no level inside DIALOG is safely
    -- above it. Toplevel raises it on every click.
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
    title:SetText("Chat Filter")

    manager.tabButtons = {}
    local previous
    for _, tabInfo in ipairs(TABS) do
        local button = MakeButton(manager, tabInfo.label, 90, function()
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

    manager.count = manager:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    manager.count:SetPoint("TOPRIGHT", manager, "TOPRIGHT", -18, -36)

    local scroll = CreateFrame("ScrollFrame", "OxedHubChatFilterScroll", manager, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", manager, "TOPLEFT", 14, -60)
    scroll:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -34, 84)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    manager.scroll, manager.content = scroll, content

    local bottom = CreateFrame("Frame", nil, manager)
    bottom:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -10)
    bottom:SetPoint("BOTTOMRIGHT", manager, "BOTTOMRIGHT", -14, 12)

    manager.ignorePanel = BuildIgnorePanel(bottom)
    manager.filterPanel = BuildFilterPanel(bottom)
    manager.blockedPanel = BuildBlockedPanel(bottom)

    manager:SetScript("OnShow", RefreshManager)
    tinsert(UISpecialFrames, "OxedHubChatFilterWindow")
    manager:Hide()
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

    -- Named for /oxprofile. The filter is handed to the game rather than set as
    -- a script, so the profiler cannot see it on its own; the wrapper is a
    -- straight pass-through while nothing is being recorded.
    local filter = OxedHub.Profiler and OxedHub.Profiler:Wrap("Chat Filter: message", ChatFilter)
        or ChatFilter
    for _, event in ipairs(CHAT_EVENTS) do
        AddFilter(event, filter)
    end
    InstallMenus()

    SLASH_OXEDCHATFILTER1 = "/oxfilter"
    SLASH_OXEDCHATFILTER2 = "/chatfilter"
    SlashCmdList["OXEDCHATFILTER"] = function(argument)
        local tab = argument and argument:match("^%s*(%a+)")
        OpenManager(tab and tab:lower() or nil)
    end

    -- /oxignore Name-Realm [note]   -- toggles that name
    SLASH_OXEDIGNORE1 = "/oxignore"
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

local function SetSocialEvents(on)
    for _, event in ipairs({ "DUEL_REQUESTED", "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE" }) do
        if on then social:RegisterEvent(event) else social:UnregisterEvent(event) end
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
        optionsWindow = API:CreateOptionsWindow("Chat Filter", 430, 400)
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
        optionsWindow:AddCheckbox(settings, "warnGroup", "Warn when an ignored player joins your group")
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
        version  = "1.0.0",
        author   = "Oxed",
        category = "chat",
        keywords = { "chat", "spam", "ignore", "filter", "block", "mute", "words" },
        -- Card text is clipped at about 100 characters; the rest lives in Options.
        desc     = "Unlimited ignore list, word filters and spam blocking. Type /oxfilter to manage.",
        icon     = "Interface\\Icons\\INV_Misc_Book_09",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        -- The chat filters stay registered once added -- the game has no clean
        -- way to take one back on every build -- and fall silent while off,
        -- through the enabled check at the top of ChatFilter.
        OnEnable = function(_, config)
            settings = config
            EnsureData()
            Install()
            SetSocialEvents(true)
        end,

        OnDisable = function()
            SetSocialEvents(false)
            if manager then manager:Hide() end
        end,
    })
end)
