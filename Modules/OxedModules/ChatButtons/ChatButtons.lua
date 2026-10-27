-- ============================================================================
-- Chat Buttons (built-in OxedHub module)
-- Three small buttons by the chat window, each with a right-click menu:
--
--   Say    Opens the chat box in Say or Yell. Keeps who whispered you and what
--          they said, with a count of the ones you have not answered; reply
--          from the menu.
--   Group  Opens party, raid or instance chat. The mouse wheel over it sends
--          one of two lines you write yourself (wheel up / wheel down), and a
--          ready check can be answered for you after a few seconds (hold Alt
--          to stop it). The menu lists the group, to whisper anyone.
--   Guild  Opens guild chat and shows how many are online. A mark when the
--          guild has new applicants or a community has unread messages. The
--          menu lists who is online, to whisper.
--
-- ⚠ Whisper text and names can be secret values in 12.0 (some instances).
--   A whisper that arrives secret is counted but not kept; nothing secret is
--   ever compared or stored.
-- ⚠ Sending chat is only done from the player's own mouse wheel, never on a
--   timer, and at most once every two seconds.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    minimapButton = true,   -- its own icon on the minimap while switched on
    enabled     = false,    -- off until the player switches it on
    showSay     = true,
    showGroup   = true,
    showGuild   = true,
    scale       = 1,
    vertical    = false,
    locked      = false,
    sayType     = "SAY",    -- SAY or YELL for the Say button's click
    keepWhispers = 30,      -- how many people the whisper list remembers
    readyDelay  = 0,        -- seconds before a ready check is answered; 0 = never
    wheelUp     = "{rt1} Pulling in 5",
    wheelDown   = "{rt7} Wait, not ready",
    point = "BOTTOMLEFT", relPoint = "TOPLEFT", x = 0, y = 30,  -- above the chat window and its tabs

    -- "whispers" is a table, built in Bind: never in DEFAULTS.
}

local PREFIX = "|cff00ccffOxedHub Chat Buttons:|r "
local SIZE = 26

local settings
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local optionsWindow
local running = false
local bar
local buttons = {}

local events = CreateFrame("Frame")
local ShowOptions   -- the options window; defined at the end, the menus open it

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

-- The chat box, opened with a slash command already typed in.
local function OpenChat(text)
    if ChatFrameUtil and ChatFrameUtil.OpenChat then
        pcall(ChatFrameUtil.OpenChat, text)
    elseif ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, text)
    end
end

local function Whisper(name)
    if name then OpenChat("/w " .. name .. " ") end
end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr or "ffffffff"
end

local function Ago(t)
    local d = time() - (t or 0)
    if d < 60 then return "now" end
    if d < 3600 then return ("%dm"):format(d / 60) end
    if d < 86400 then return ("%dh"):format(d / 3600) end
    return ("%dd"):format(d / 86400)
end

local function HasMenu()
    return MenuUtil and MenuUtil.CreateContextMenu
end

-- ── The bar and its buttons ─────────────────────────────────────────────────

local function SavePosition()
    local point, rel, relPoint, x, y = bar:GetPoint(1)
    settings.point, settings.relPoint, settings.x, settings.y = point, relPoint, x, y
    settings.toUIParent = rel == UIParent or rel == nil
end

local function PlaceBar()
    bar:ClearAllPoints()
    if settings.toUIParent then
        bar:SetPoint(settings.point or "CENTER", UIParent, settings.relPoint or "CENTER", settings.x or 0, settings.y or 0)
    else
        -- First time: just above the main chat window.
        bar:SetPoint(settings.point or "BOTTOMLEFT", ChatFrame1 or UIParent, settings.relPoint or "TOPLEFT", settings.x or 0, settings.y or 30)
    end
end

local function MakeButton(key, atlas, tip)
    local b = CreateFrame("Button", nil, bar)
    b:SetSize(SIZE, SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetVertexColor(0, 0, 0, 0.7)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 4, -4)
    b.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    if not pcall(b.icon.SetAtlas, b.icon, atlas) then b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
    -- The minimap's round border: its art sits in the top-left of the file.
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(SIZE * 54 / 32, SIZE * 54 / 32)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    b.badge = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.badge:SetPoint("TOPRIGHT", 3, 2)
    b.mark = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.mark:SetSize(11, 11)
    b.mark:SetPoint("TOPLEFT", -2, 2)
    b.mark:Hide()
    b.tip = tip

    -- Dragging any button moves the whole bar (a plain click still clicks);
    -- "Lock them in place" stops it.
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function()
        if not settings.locked then bar:StartMoving() end
    end)
    b:SetScript("OnDragStop", function()
        bar:StopMovingOrSizing()
        SavePosition()
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        self.tip(GameTooltip)
        if not settings.locked then GameTooltip:AddLine(L["Drag: move the buttons"], 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[key] = b
    return b
end

local function Layout()
    if not bar then return end
    bar:SetScale(tonumber(settings.scale) or 1)
    local prev, shown = nil, 0
    for _, key in ipairs({ "say", "group", "guild" }) do
        local b = buttons[key]
        local want = settings["show" .. key:sub(1, 1):upper() .. key:sub(2)]
        b:SetShown(want and true or false)
        if want then
            b:ClearAllPoints()
            if prev then
                if settings.vertical then b:SetPoint("TOP", prev, "BOTTOM", 0, -4)
                else b:SetPoint("LEFT", prev, "RIGHT", 4, 0) end
            else
                b:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            end
            prev = b
            shown = shown + 1
        end
    end
    local long = math.max(1, shown) * SIZE + math.max(0, shown - 1) * 4
    if settings.vertical then bar:SetSize(SIZE, long) else bar:SetSize(long, SIZE) end
end

-- ── Say: whispers kept ──────────────────────────────────────────────────────
-- settings.whispers = { { name, class, at, unread, lines = { { at, text, mine } } } },
-- newest person first.

local MAX_LINES = 10
local unread = 0

local function FindPerson(name)
    for i, p in ipairs(settings.whispers) do
        if p.name == name then return p, i end
    end
    return nil
end

local function UpdateSayBadge()
    local b = buttons.say
    if not b then return end
    unread = 0
    for _, p in ipairs(settings.whispers) do unread = unread + (p.unread or 0) end
    b.badge:SetText(unread > 0 and ("|cffff60ff%d|r"):format(unread) or "")
end

local function KeepWhisper(name, text, mine, guid)
    name, text = Plain(name), Plain(text)
    if not name then return end
    local p, i = FindPerson(name)
    if p then
        table.remove(settings.whispers, i)
    else
        p = { name = name, lines = {} }
    end
    table.insert(settings.whispers, 1, p)
    p.at = time()
    if guid and not IsSecret(guid) and GetPlayerInfoByGUID then
        local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
        if ok and Plain(class) then p.class = class end
    end
    if mine then
        p.unread = 0   -- answered
    else
        p.unread = (p.unread or 0) + 1
    end
    if text then
        table.insert(p.lines, { at = time(), text = text, mine = mine or nil })
        while #p.lines > MAX_LINES do table.remove(p.lines, 1) end
    end
    local keep = math.max(5, tonumber(settings.keepWhispers) or 30)
    while #settings.whispers > keep do table.remove(settings.whispers) end
    UpdateSayBadge()
end

local function SayMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Say"])
        for _, t in ipairs({ { "SAY", SAY or L["Say"] }, { "YELL", YELL or L["Yell"] } }) do
            root:CreateRadio(t[2], function() return settings.sayType == t[1] end, function() settings.sayType = t[1] end)
        end
        root:CreateDivider()
        root:CreateTitle((L["Whispers (%d)"]):format(#settings.whispers))
        if #settings.whispers == 0 then
            root:CreateButton(L["|cff9d9d9dNobody yet|r"], function() end)
        end
        for i, p in ipairs(settings.whispers) do
            if i > 20 then break end
            local label = ("|c%s%s|r  |cff9d9d9d%s|r%s"):format(ClassHex(p.class), p.name, Ago(p.at),
                (p.unread or 0) > 0 and ("  |cffff60ff%d new|r"):format(p.unread) or "")
            local sub = root:CreateButton(label, function()
                p.unread = 0
                UpdateSayBadge()
                Whisper(p.name)
            end)
            sub:SetTooltip(function(tooltip)
                tooltip:SetText(p.name)
                for _, line in ipairs(p.lines) do
                    tooltip:AddLine(("|cff9d9d9d%s|r %s%s"):format(date("%H:%M", line.at),
                        line.mine and L["|cff80c0ffyou:|r "] or "", line.text), 1, 1, 1, true)
                end
                tooltip:AddLine(L["Click: whisper back"], 0.4, 1, 0.4)
            end)
        end
        if #settings.whispers > 0 then
            root:CreateDivider()
            root:CreateButton(L["Mark all as read"], function()
                for _, p in ipairs(settings.whispers) do p.unread = 0 end
                UpdateSayBadge()
            end)
            root:CreateButton(L["Forget all whispers"], function()
                wipe(settings.whispers)
                UpdateSayBadge()
            end)
        end
    end)
end

-- ── Group: its chat, quick lines, ready check ───────────────────────────────

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT", "/i " end
    if IsInRaid() then return "RAID", "/ra " end
    if IsInGroup() then return "PARTY", "/p " end
    return nil
end

local lastSent = 0
local function SendQuickLine(up)
    local channel = GroupChannel()
    if not channel then
        print(PREFIX .. L["not in a group."])
        return
    end
    if GetTime() - lastSent < 2 then return end
    local text = up and settings.wheelUp or settings.wheelDown
    if type(text) ~= "string" or text:gsub("%s", "") == "" then return end
    lastSent = GetTime()
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok = pcall(send, text, channel)
    if not ok then print(PREFIX .. L["the game did not let that line be sent here."]) end
end

local function GroupMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Group"])
        local count = GetNumGroupMembers() or 0
        if count == 0 then
            root:CreateButton(L["|cff9d9d9dNot in a group|r"], function() end)
        else
            local raid = IsInRaid()
            local me = Plain(UnitName("player"))
            for i = 1, raid and count or count - 1 do
                local unit = (raid and "raid" or "party") .. i
                local okN, name, realm = pcall(UnitName, unit)
                name, realm = okN and Plain(name), okN and Plain(realm)
                -- A raid lists you too; a name in combat may be secret and is left out.
                if name and not (raid and name == me and not realm) then
                    local full = realm and (name .. "-" .. realm) or name
                    local okC, _, class = pcall(UnitClass, unit)
                    class = okC and Plain(class)
                    root:CreateButton(("|c%s%s|r"):format(ClassHex(class), full), function() Whisper(full) end)
                end
            end
        end
        root:CreateDivider()
        root:CreateTitle(L["Answer ready checks"])
        for _, s in ipairs({ 0, 1, 3, 5 }) do
            root:CreateRadio(s == 0 and L["Myself"] or (L["After %d s (Alt stops it)"]):format(s),
                function() return (tonumber(settings.readyDelay) or 0) == s end,
                function() settings.readyDelay = s end)
        end
        root:CreateDivider()
        root:CreateButton(L["Change the wheel lines..."], function() ShowOptions() end)
    end)
end

local readyTimer
local function OnReadyCheck(initiator, timeLeft)
    local delay = tonumber(settings.readyDelay) or 0
    if delay <= 0 then return end
    -- The one who started it is already counted as ready.
    local me, who = Plain(UnitName("player")), Plain(initiator)
    if me and who and (who:match("^[^%-]+") == me) then return end
    if readyTimer then readyTimer:Cancel() end
    print(PREFIX .. (L["ready check answered in %d s. Hold Alt to answer yourself."]):format(delay))
    readyTimer = C_Timer.NewTimer(delay, function()
        readyTimer = nil
        if not running or IsAltKeyDown() then
            print(PREFIX .. L["ready check left to you."])
            return
        end
        local ok = pcall(ConfirmReadyCheck, true)
        if ok and ReadyCheckFrame and ReadyCheckFrame:IsShown() then ReadyCheckFrame:Hide() end
    end)
end

-- ── Guild: online, applicants, unread ───────────────────────────────────────

local function GuildClubID()
    if not (C_Club and C_Club.GetGuildClubId) then return nil end
    local ok, id = pcall(C_Club.GetGuildClubId)
    if ok and not IsSecret(id) then return id end
    return nil
end

local function HasApplicants()
    local clubID = GuildClubID()
    if not (clubID and C_ClubFinder and C_ClubFinder.ReturnClubApplicantList) then return false end
    local ok, list = pcall(C_ClubFinder.ReturnClubApplicantList, clubID)
    return ok and type(list) == "table" and not IsSecret(list) and #list > 0
end

local function HasUnread()
    local util = CommunitiesUtil and CommunitiesUtil.DoesCommunityHaveUnreadMessages
    if not (util and C_Club and C_Club.GetSubscribedClubs) then return false end
    local ok, clubs = pcall(C_Club.GetSubscribedClubs)
    if not ok or type(clubs) ~= "table" then return false end
    for _, club in ipairs(clubs) do
        local id = club.clubId
        if id and not IsSecret(id) then
            local okU, has = pcall(util, id)
            if okU and not IsSecret(has) and has == true then return true end
        end
    end
    return false
end

local function UpdateGuildButton()
    local b = buttons.guild
    if not b then return end
    if not IsInGuild() then
        b.badge:SetText("")
        b.mark:Hide()
        b.icon:SetDesaturated(true)
        return
    end
    b.icon:SetDesaturated(false)
    local _, online = GetNumGuildMembers()
    online = (type(online) == "number" and not IsSecret(online)) and math.max(0, online - 1) or 0
    b.badge:SetText(online > 0 and ("|cff40ff40%d|r"):format(online) or "")
    local applicants, unreadMsg = HasApplicants(), HasUnread()
    if applicants then
        pcall(b.mark.SetAtlas, b.mark, "communities-icon-invitemail")
    elseif unreadMsg then
        pcall(b.mark.SetAtlas, b.mark, "communities-icon-notification")
    end
    b.mark:SetShown(applicants or unreadMsg)
    b.applicants, b.unread = applicants, unreadMsg
end

local function GuildMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        if not IsInGuild() then
            root:CreateTitle(L["Not in a guild"])
            return
        end
        local guildName = GetGuildInfo("player")
        root:CreateTitle(Plain(guildName) or L["Guild"])
        local list = {}
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local ok, name, _, _, level, _, zone, _, _, isOnline, _, class = pcall(GetGuildRosterInfo, i)
            if ok and not IsSecret(isOnline) and isOnline == true and Plain(name) then
                list[#list + 1] = { name = name, zone = Plain(zone), class = Plain(class), level = level }
            end
        end
        table.sort(list, function(a, b) return a.name < b.name end)
        local me = Plain(UnitName("player"))
        local shown = 0
        for _, m in ipairs(list) do
            if not (me and m.name:match("^[^%-]+") == me) then
                shown = shown + 1
                if shown > 30 then
                    root:CreateButton((L["|cff9d9d9d...and %d more|r"]):format(#list - 30), function() end)
                    break
                end
                root:CreateButton(("|c%s%s|r  |cff9d9d9d%s|r"):format(ClassHex(m.class), m.name:match("^[^%-]+") or m.name, m.zone or ""),
                    function() Whisper(m.name) end)
            end
        end
        if shown == 0 then root:CreateButton(L["|cff9d9d9dNobody else online|r"], function() end) end
        root:CreateDivider()
        if buttons.guild.applicants then root:CreateTitle(L["|cff40ff40New applicants waiting|r"]) end
        if buttons.guild.unread then root:CreateTitle(L["|cffffd100Unread community messages|r"]) end
        if CanReplaceGuildMaster and CanReplaceGuildMaster() then
            root:CreateTitle(L["|cffff8040The guild master is inactive: you can replace them|r"])
        end
        root:CreateButton(L["Open Guild & Communities"], function()
            if ToggleGuildFrame then ToggleGuildFrame() end
        end)
    end)
end

-- ── Building ────────────────────────────────────────────────────────────────

local function Build()
    if bar then return end
    bar = CreateFrame("Frame", "OxedHubChatButtonsBar", UIParent)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local say = MakeButton("say", "ChatFrameExpandArrow", function(tt)
        tt:SetText(L["Say"])
        tt:AddLine((L["Click: open %s"]):format(settings.sayType == "YELL" and L["Yell"] or L["Say"]), 1, 1, 1)
        tt:AddLine(L["Right-click: Say or Yell, and your whispers"], 1, 1, 1)
        if unread > 0 then tt:AddLine((L["%d whisper(s) not answered"]):format(unread), 1, 0.4, 1) end
    end)
    pcall(say.icon.SetAtlas, say.icon, "chatframe-button-icon-speaker-on")
    say:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and HasMenu() then
            SayMenu(self)
        else
            OpenChat(settings.sayType == "YELL" and "/y " or "/s ")
        end
    end)

    local group = MakeButton("group", "UI-HUD-MicroMenu-Groupfinder-Up", function(tt)
        tt:SetText(L["Group"])
        local _, slash = GroupChannel()
        tt:AddLine(slash and (L["Click: open %s chat"]):format(slash:match("/(%a+)")) or L["Not in a group"], 1, 1, 1)
        tt:AddLine(L["Wheel up: "] .. (settings.wheelUp or ""), 1, 1, 1, true)
        tt:AddLine(L["Wheel down: "] .. (settings.wheelDown or ""), 1, 1, 1, true)
        tt:AddLine(L["Right-click: the group, and ready checks"], 1, 1, 1)
    end)
    group:EnableMouseWheel(true)
    group:SetScript("OnMouseWheel", function(_, delta) SendQuickLine(delta > 0) end)
    group:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and HasMenu() then
            GroupMenu(self)
        else
            local _, slash = GroupChannel()
            if slash then OpenChat(slash) else print(PREFIX .. L["not in a group."]) end
        end
    end)

    local guild = MakeButton("guild", "UI-HUD-MicroMenu-GuildCommunities-Up", function(tt)
        tt:SetText(L["Guild"])
        if not IsInGuild() then
            tt:AddLine(L["Not in a guild"], 0.6, 0.6, 0.6)
            return
        end
        tt:AddLine(L["Click: open guild chat"], 1, 1, 1)
        tt:AddLine(L["Right-click: who is online"], 1, 1, 1)
        if buttons.guild.applicants then tt:AddLine(L["New applicants waiting"], 0.3, 1, 0.3) end
        if buttons.guild.unread then tt:AddLine(L["Unread community messages"], 1, 0.82, 0) end
    end)
    guild:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and HasMenu() then
            GuildMenu(self)
        elseif IsInGuild() then
            OpenChat("/g ")
        end
    end)
end

-- ── Events, start and stop ──────────────────────────────────────────────────

local guildQueued = false
local function QueueGuild()
    if guildQueued then return end
    guildQueued = true
    C_Timer.After(1, function()
        guildQueued = false
        if running then UpdateGuildButton() end
    end)
end

events:SetScript("OnEvent", function(_, event, ...)
    if not running then return end
    if event == "CHAT_MSG_WHISPER" then
        local text, sender, _, _, _, _, _, _, _, _, _, guid = ...
        KeepWhisper(sender, text, false, guid)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local text, target, _, _, _, _, _, _, _, _, _, guid = ...
        KeepWhisper(target, text, true, guid)
    elseif event == "READY_CHECK" then
        OnReadyCheck(...)
    elseif event == "READY_CHECK_FINISHED" then
        if readyTimer then readyTimer:Cancel() readyTimer = nil end
    else
        QueueGuild()
    end
end)

local EVENTS = {
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "READY_CHECK", "READY_CHECK_FINISHED",
    "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "CLUB_FINDER_RECRUITS_UPDATED",
    "CLUB_FINDER_APPLICANT_INVITE_RECIEVED", "STREAM_VIEW_MARKER_UPDATED", "CLUB_MESSAGE_ADDED",
}

local rosterTicker

local function Start()
    if running then return end
    running = true
    Build()
    PlaceBar()
    Layout()
    bar:Show()
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    UpdateSayBadge()
    -- The online count only moves when the roster is asked for.
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    if not rosterTicker then
        rosterTicker = C_Timer.NewTicker(60, function()
            if running and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
        end)
    end
    QueueGuild()
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    if rosterTicker then rosterTicker:Cancel() rosterTicker = nil end
    if readyTimer then readyTimer:Cancel() readyTimer = nil end
    if bar then bar:Hide() end
end

-- ── Options ─────────────────────────────────────────────────────────────────

-- A one-line text box for a setting. Never takes the keyboard on its own.
local function AddTextBox(w, key, caption)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    label:SetText(caption)
    local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(w:GetWidth() - 60, 20)
    box:SetPoint("TOPLEFT", w, "TOPLEFT", 26, w.cursorY - 22)
    box:SetMaxLetters(240)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    box:SetScript("OnEnterPressed", box.ClearFocus)
    box:SetScript("OnTextChanged", function(self, user)
        if user then settings[key] = self:GetText() end
    end)
    box.Refresh = function() box:SetText(settings[key] or "") end
    table.insert(w.checks, box)
    w.cursorY = w.cursorY - 50
end

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Chat Buttons", 460, 588)
        optionsWindow = w
        w:AddCheckbox(settings, "showSay", "Say button: Say or Yell, and your whispers", nil, Layout)
        w:AddCheckbox(settings, "showGroup", "Group button: group chat, quick lines, ready checks", nil, Layout)
        w:AddCheckbox(settings, "showGuild", "Guild button: online, applicants, unread", nil, Layout)
        w:AddCheckbox(settings, "vertical", "Stack the buttons", nil, Layout)
        w:AddCheckbox(settings, "locked", "Lock them in place")
        w:AddSlider(settings, "scale", "Size", 0.6, 2, 0.1, "%s: %.1f", Layout)
        w:AddSlider(settings, "keepWhispers", "People kept in the whisper list", 5, 100, 5, "%s: %d")
        w:AddSlider(settings, "readyDelay", "Answer ready checks after", 0, 10, 1, "%s: %d s")
        w:AddNote("0 seconds: never; you answer yourself. Holding Alt when the time runs out leaves it to you.")
        AddTextBox(w, "wheelUp", L["Mouse wheel up over Group sends:"])
        AddTextBox(w, "wheelDown", L["Mouse wheel down over Group sends:"])
        w:AddNote("Raid marks work: {rt1} star ... {rt8} skull. Drag a button to move them; /oxchat reset puts them back.")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        if w.AddModuleLinks then w:AddModuleLinks("Works with", { "bubblechat", "chatfilter", "copychat" }) end
    end
    optionsWindow:Show()
end

SLASH_OXEDCHATBUTTONS1 = "/oxchat"
SlashCmdList.OXEDCHATBUTTONS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" and settings then
        settings.toUIParent, settings.point, settings.relPoint, settings.x, settings.y = nil, "BOTTOMLEFT", "TOPLEFT", 0, 30
        if bar then PlaceBar() end
        print(PREFIX .. L["the buttons are back above the chat window."])
    else
        ShowOptions()
    end
end

-- ── Login ───────────────────────────────────────────────────────────────────

-- Its own icon on the minimap, like the other modules with a window: a click
-- opens the options, a right-click the options.
MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "chatbuttons", label = L["Chat Buttons"], icon = "Interface\\Icons\\INV_Letter_15", config = settings,
        hint = L["Click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ShowOptions() end
        end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.chatbuttons
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.chatbuttons = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.whispers) ~= "table" then config.whispers = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "chatbuttons",
        name     = "Chat Buttons",
        version  = "1.1.0",
        updated  = 20261025.3,  -- its own minimap button
        author   = "Oxed",
        category = "chat",
        keywords = { "chat", "say", "yell", "whisper", "group", "party", "raid", "guild", "ready check", "applicant" },
        desc     = "Say, Group and Guild buttons by the chat: whisper history, quick lines, ready checks, guild alerts.",
        icon     = "Interface\\Icons\\INV_Letter_15",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            if type(settings.whispers) ~= "table" then settings.whispers = {} end
            Start()
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
