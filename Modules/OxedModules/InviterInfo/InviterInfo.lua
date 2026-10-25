-- ============================================================================
-- Inviter Info (built-in OxedHub module)
-- Who is inviting you, before you say yes: under the group invite popup, their
-- class, race and realm, and whether they are a friend, a Battle.net friend or
-- in your guild. A guild invite gets the same line in chat.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,      -- off until the player switches it on
    inChat      = false,      -- also print the line in chat
    guild       = true,       -- a line for guild invites
    -- What the line says.
    showClass   = true,
    classColour = true,       -- the class in its own colour
    showRace    = true,
    showRealm   = true,
    showKnown   = true,       -- friend, Battle.net friend, guild
    sound       = "",         -- played when an invite arrives; empty plays none
    -- How it looks. The colours are tables, made in Bind (never in DEFAULTS).
    font        = "default",
    fontSize    = 13,
    outline     = "",
    background  = true,
    bgAlpha     = 0.92,
    border      = true,
    position    = "below",    -- below or above the invite
    offset      = 2,
    -- The group window: shown when the group finder puts you in a group.
    groupWindow    = true,
    groupFull      = true,    -- again when the group fills up
    groupChat      = true,    -- a line in chat with a link back to the window
    hideGameInvite = true,    -- the game's own "you joined" message
    rowRole        = true,
    rowName        = true,
    rowLeader      = true,
    rowPlaystyle   = true,
    rowItemLevel   = true,
    rowVoice       = true,
    rowDescription = true,
    teleport       = true,    -- a teleport button for dungeons that have one
}

local PREFIX = "|cff00ccffOxedHub|r "

local settings
local optionsWindow, lookWindow
local frame = CreateFrame("Frame")

local function Plain(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

-- ── Fonts ───────────────────────────────────────────────────────────────────
-- The game's own fonts go through OxedHub:GetFont, which swaps in the
-- Cyrillic or Arabic file when OxedHub is set to that language. The bundled
-- ones below all draw Cyrillic themselves.

local GF = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\Bubble\\"

local FONTS = {
    { value = "default",    text = "Game default" },
    { value = "friz",       text = "Friz Quadrata (game)", path = "Fonts\\FRIZQT__.TTF", game = true },
    { value = "arialn",     text = "Arial Narrow (game)",  path = "Fonts\\ARIALN.TTF",   game = true },
    { value = "morpheus",   text = "Morpheus (game)",      path = "Fonts\\MORPHEUS.TTF", game = true },
    { value = "skurri",     text = "Skurri (game)",        path = "Fonts\\SKURRI.TTF",   game = true },
    { value = "montserrat", text = "Montserrat",  path = GF .. "Montserrat.ttf" },
    { value = "rubik",      text = "Rubik",       path = GF .. "Rubik.ttf" },
    { value = "ptsans",     text = "PT Sans",     path = GF .. "PTSans-Regular.ttf" },
    { value = "oswald",     text = "Oswald",      path = GF .. "Oswald.ttf" },
    { value = "russoone",   text = "Russo One",   path = GF .. "RussoOne-Regular.ttf" },
}

-- The list above plus every font LibSharedMedia knows, when it is loaded.
local function FontChoices()
    local list = {}
    for _, f in ipairs(FONTS) do list[#list + 1] = f end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("font") or {}) do
            list[#list + 1] = { value = "lsm:" .. name, text = name }
        end
    end
    return list
end

local function FontPath(value)
    local fallback = GameFontHighlight:GetFont()
    for _, f in ipairs(FONTS) do
        if f.value == value and f.path then
            return f.game and OxedHub:GetFont(f.path) or f.path
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(value) == "string" and value:sub(1, 4) == "lsm:" then
        return LSM:Fetch("font", value:sub(5), true) or fallback
    end
    return fallback
end

-- ── The line ────────────────────────────────────────────────────────────────

local function Hex(c, fallback)
    c = type(c) == "table" and c or fallback
    return ("ff%02x%02x%02x"):format((c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255)
end

-- "Paladin, Human, Silvermoon. Your guild" with the class in its colour.
-- The game often has not loaded a stranger's class and race yet when the
-- invite arrives; then the line starts with the realm from their name, and
-- complete says false so the caller can ask again a moment later.
local function Describe(guid, name)
    guid = Plain(guid)
    local className, classFile, race, realm
    if guid then
        local ok, c, cf, r, _, _, _, rl = pcall(GetPlayerInfoByGUID, guid)
        if ok then className, classFile, race, realm = Plain(c), Plain(cf), Plain(r), Plain(rl) end
    end
    if not realm or realm == "" then
        realm = type(Plain(name)) == "string" and name:match("%-(.+)$") or nil
    end
    -- Same realm as you: GetPlayerInfoByGUID answers with an empty realm.
    if (not realm or realm == "") and guid then realm = GetRealmName and GetRealmName() or nil end

    local parts = {}
    if className and settings.showClass then
        local colour = settings.classColour and classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
        parts[#parts + 1] = colour and colour:WrapTextInColorCode(className) or className
    end
    if race and race ~= "" and settings.showRace then parts[#parts + 1] = race end
    if realm and realm ~= "" and settings.showRealm then parts[#parts + 1] = realm end
    local text
    if #parts > 0 then
        text = table.concat(parts, ", ")
    elseif settings.showClass and not className then
        text = L["Class not known yet"]
    end

    if not guid or not settings.showKnown then
        return text and (text .. ".") or "", className ~= nil
    end

    local known = {}
    if C_FriendList and C_FriendList.IsFriend then
        local okF, isFriend = pcall(C_FriendList.IsFriend, guid)
        if okF and isFriend == true then known[#known + 1] = L["friend"] end
    end
    -- Not for yourself (the preview describes you): your own account
    -- answers as a Battle.net friend.
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and guid ~= UnitGUID("player") then
        local okB, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        if okB and type(info) == "table" then known[#known + 1] = L["Battle.net friend"] end
    end
    if IsGuildMember then
        local okG, member = pcall(IsGuildMember, guid)
        if okG and member == true then known[#known + 1] = L["your guild"] end
    end
    local status
    if #known > 0 then
        status = ("|c%s%s|r"):format(Hex(settings.knownColour, { 0.25, 1, 0.25 }), table.concat(known, ", "))
    else
        status = ("|c%s%s|r"):format(Hex(settings.strangerColour, { 0.67, 0.67, 0.67 }), L["Not a friend or guild member."])
    end
    return text and (text .. ". " .. status) or status, className ~= nil
end

-- ── The note under the invite ───────────────────────────────────────────────
-- Our own frame rather than ModuleAPI:PopupNote, which other modules share:
-- its font, colours and place are this module's settings.

local note
local hookedPopups = setmetatable({}, { __mode = "k" })  -- never write into Blizzard's frames

local function BuildNote()
    if note then return note end
    note = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    note:SetFrameStrata("DIALOG")
    note:Hide()
    -- OxedHub's stone panel with the ornate corners and edges, the frame
    -- every OxedHub window has.
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then Panel.ApplyOrnateFrame(note, nil, 0.92) end
    note.edges = {}
    for _, key in ipairs({ "cornerTL", "cornerTR", "cornerBL", "cornerBR", "topEdge", "bottomEdge", "leftEdge", "rightEdge" }) do
        if note[key] then note.edges[#note.edges + 1] = note[key] end
    end
    note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note.text:SetPoint("CENTER")
    note.text:SetJustifyH("CENTER")
    return note
end

local function Style()
    if not note then return end
    local outline = settings.outline ~= "" and settings.outline or nil
    if not note.text:SetFont(FontPath(settings.font), settings.fontSize, outline) then
        note.text:SetFont(GameFontHighlight:GetFont(), settings.fontSize, outline)
    end
    local c = settings.textColour or { 1, 1, 1 }
    note.text:SetTextColor(c[1], c[2], c[3])
    -- The stone, as see-through as set; the ornate frame round it, or none.
    if note.SetBackdropColor and note:GetBackdrop() then
        note:SetBackdropColor(0.10, 0.095, 0.085, settings.background and (settings.bgAlpha or 0.92) or 0)
    end
    for _, edge in ipairs(note.edges) do edge:SetShown(settings.border) end
end

-- Shows text by `anchor`, under it or above as set. The note follows the
-- anchor's width, and hides with it.
local function ShowNote(anchor, text)
    if not anchor then return end
    BuildNote()
    Style()
    note:SetParent(anchor)
    note:SetFrameLevel(anchor:GetFrameLevel() + 5)
    note:ClearAllPoints()
    local gap = settings.offset or 2
    if settings.position == "above" then
        note:SetPoint("BOTTOM", anchor, "TOP", 0, gap)
    else
        note:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    end
    local width = math.max(220, anchor:GetWidth() or 320)
    note.text:SetWidth(width - 24)
    note.text:SetText(text)
    -- Room inside the ornate edges.
    note:SetSize(width + 8, math.max(34, note.text:GetStringHeight() + 24))
    note:Show()
    if not hookedPopups[anchor] then
        hookedPopups[anchor] = true
        anchor:HookScript("OnHide", function()
            if note and note:GetParent() == anchor then note:Hide() end
        end)
    end
end

-- The invite popup: same-realm and cross-realm invites use different ones.
local function InvitePopup()
    local API = OxedHub.ModuleAPI
    if not API then return nil end
    return API:FindPopup("PARTY_INVITE") or API:FindPopup("PARTY_INVITE_XREALM")
end

-- Tries for about a second: the popup is shown by the same event and may not
-- be up yet, and the inviter's class may arrive a moment after the invite.
-- A popup that never turns up gets the line in chat instead, so the player
-- always sees it.
local RETRY_STEP, RETRIES = 0.2, 5
local inviteSerial = 0

local function ShowInvite(serial, guid, name, tries)
    if serial ~= inviteSerial or not (settings and settings.enabled) then return end
    local text, complete = Describe(guid, name)
    local dialog = InvitePopup()
    if dialog and text ~= "" then ShowNote(dialog, text) end
    if (not dialog or not complete) and tries < RETRIES then
        C_Timer.After(RETRY_STEP, function() ShowInvite(serial, guid, name, tries + 1) end)
        return
    end
    if (settings.inChat or not dialog) and text ~= "" then
        print(PREFIX .. (Plain(name) or "?") .. L[" invites you: "] .. text)
    end
end

-- ── The group window ────────────────────────────────────────────────────────
-- A window of its own, in OxedHub's stone panel, when the group finder puts
-- you in a group (and again when it fills up): the activity, your role, the
-- listing's name, leader, playstyle, item level, voice chat and description,
-- and the dungeon's teleport. So it can still be read once the finder closes.
-- ⚠ A listing's name and comment are protected strings: SetText only, never
-- joined, compared or measured as Lua strings.
-- ⚠ The teleport button is a secure button. The window holding it cannot be
-- shown in combat, so a group joined in combat opens it afterwards.

local GW_WIDTH, GW_PAD, GW_LABEL_W = 380, 18, 96
local ROLE_ATLAS = { TANK = "GM-icon-role-tank", HEALER = "GM-icon-role-healer", DAMAGER = "GM-icon-role-dps" }
local GROUP_LINK = "addon:oxedhub:invitergroup"

local ROWS = {
    { key = "name",      option = "rowName",        label = "Group:" },
    { key = "leader",    option = "rowLeader",      label = "Leader:" },
    { key = "playstyle", option = "rowPlaystyle",   label = "Playstyle:" },
    { key = "itemLevel", option = "rowItemLevel",   label = "Item level:" },
    { key = "voice",     option = "rowVoice",       label = "Voice chat:" },
    { key = "comment",   option = "rowDescription", label = "Description:", wrap = true },
}

local groupWin
local shown          -- what the window shows now
local tracked        -- the group being watched for filling up
local pendingShow    -- a show held back by combat
local suppressResult -- the search result whose game message is hidden

local function IsBlank(value)
    if value == nil then return true end
    if issecretvalue and issecretvalue(value) then return false end
    return value == "" or value == 0
end

local function PlaystyleText(info, activityInfo)
    local style = Plain(info.generalPlaystyle)
    if type(style) == "number" and style > 0 then
        local text = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. style]
        if type(text) == "string" then return text end
    end
    style = Plain(info.playstyle)
    if style and C_LFGList.GetPlaystyleString and activityInfo then
        local ok, text = pcall(C_LFGList.GetPlaystyleString, style, activityInfo)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return nil
end

-- The dungeon behind an activity, from MythicLooter's list when it is loaded:
-- its portrait and its teleport spell.
local function DungeonFor(mapID)
    local ML = OxedHub.MythicLooter
    local Query = ML and ML.Query
    if not (mapID and Query and Query.GetDungeons) then return nil end
    local ok, list = pcall(Query.GetDungeons, Query)
    if not ok or type(list) ~= "table" then return nil end
    for _, dungeon in ipairs(list) do
        if dungeon.instanceId == mapID then return dungeon end
    end
    return nil
end

local function TeleportSpell(dungeon)
    local id = dungeon and dungeon.teleportSpellId
    if type(id) == "function" then
        local ok, value = pcall(id)
        id = ok and value or nil
    end
    return type(id) == "number" and id or nil
end

local function SpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and known ~= nil then return known == true end
    end
    return IsSpellKnown and IsSpellKnown(id) == true or false
end

-- Everything the window needs, read while the listing still exists.
local function ReadListing(info, activityInfo, leader, role)
    if type(info) ~= "table" then return nil end
    local name = info.name
    if not (issecretvalue and issecretvalue(name)) and (name == "" or name == UNKNOWN) then name = nil end
    local ilvl = Plain(info.requiredItemLevel)
    local voice = Plain(info.voiceChat)
    local data = {
        activity  = activityInfo and Plain(activityInfo.fullName) or nil,
        mapID     = activityInfo and Plain(activityInfo.mapID) or nil,
        maxSize   = activityInfo and Plain(activityInfo.maxNumPlayers) or nil,
        name      = name,
        comment   = info.comment,
        leader    = leader or Plain(info.leaderName),
        playstyle = PlaystyleText(info, activityInfo),
        itemLevel = type(ilvl) == "number" and ilvl > 0 and tostring(math.floor(ilvl)) or nil,
        voice     = type(voice) == "string" and voice ~= "" and voice or nil,
        role      = role,
    }
    if type(data.maxSize) ~= "number" or data.maxSize <= 0 then data.maxSize = 5 end
    return data
end

local function BuildGroupWindow()
    if groupWin then return groupWin end
    local w = CreateFrame("Frame", "OxedHubInviterGroupWindow", UIParent, "BackdropTemplate")
    groupWin = w
    w:SetSize(GW_WIDTH, 200)
    w:SetFrameStrata("DIALOG")
    -- Not toplevel: a click would lift the window over its teleport button.
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    -- Not moved in combat: the teleport button is anchored to it.
    w:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and ux then settings.winX, settings.winY = x - ux, y - uy end
    end)
    w:Hide()
    tinsert(UISpecialFrames, "OxedHubInviterGroupWindow")  -- Escape closes it

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(w, L["Group joined"], 0.97)
    else
        w:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        w:SetBackdropColor(0.08, 0.075, 0.07, 0.97)
        w:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    end

    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", w, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() w:Hide() end)

    -- The activity: portrait on the left, its name and your role beside it.
    w.icon = w:CreateTexture(nil, "ARTWORK")
    w.icon:SetSize(48, 48)
    w.icon:SetPoint("TOPLEFT", w, "TOPLEFT", GW_PAD, -34)
    w.iconBorder = w:CreateTexture(nil, "OVERLAY")
    w.iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    w.iconBorder:SetSize(84, 84)
    w.iconBorder:SetPoint("CENTER", w.icon, "CENTER")

    w.activity = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    w.activity:SetPoint("TOPLEFT", w.icon, "TOPRIGHT", 12, -4)
    w.activity:SetPoint("RIGHT", w, "RIGHT", -GW_PAD, 0)
    w.activity:SetJustifyH("LEFT")
    -- Two lines: "The Blinding Vale (Mythic Keystone)" does not fit on one.
    w.activity:SetWordWrap(true)
    w.activity:SetMaxLines(2)

    w.roleIcon = w:CreateTexture(nil, "OVERLAY")
    w.roleIcon:SetSize(16, 16)
    w.roleIcon:SetPoint("TOPLEFT", w.activity, "BOTTOMLEFT", 0, -6)
    w.roleText = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.roleText:SetPoint("LEFT", w.roleIcon, "RIGHT", 4, 0)

    w.divider = w:CreateTexture(nil, "ARTWORK")
    w.divider:SetColorTexture(0.6, 0.5, 0.2, 0.5)
    w.divider:SetHeight(1)
    w.divider:SetPoint("TOPLEFT", w, "TOPLEFT", GW_PAD, -94)
    w.divider:SetPoint("TOPRIGHT", w, "TOPRIGHT", -GW_PAD, -94)

    w.rows = {}
    for _, row in ipairs(ROWS) do
        local label = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetWidth(GW_LABEL_W)
        label:SetJustifyH("RIGHT")
        local value = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("TOPLEFT", label, "TOPRIGHT", 8, 0)
        value:SetPoint("RIGHT", w, "RIGHT", -GW_PAD, 0)
        value:SetJustifyH("LEFT")
        value:SetJustifyV("TOP")
        value:SetWordWrap(row.wrap == true)
        w.rows[row.key] = { label = label, value = value }
    end

    -- The teleport: a secure spell button, set up out of combat only. It is
    -- not the window's child, only placed over it: a window holding a secure
    -- button could not be closed in combat (Escape, the X). Closed in combat,
    -- the window leaves the button invisible until combat ends, then hides it.
    local tp = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    tp:SetSize(220, 26)
    tp:SetFrameStrata("DIALOG")
    tp:Hide()
    w:HookScript("OnHide", function()
        if InCombatLockdown() then
            tp:SetAlpha(0)
            frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            tp:Hide()
        end
    end)
    tp:RegisterForClicks("AnyUp", "AnyDown")
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(tp) end
    tp.icon = tp:CreateTexture(nil, "OVERLAY")
    tp.icon:SetSize(18, 18)
    tp.icon:SetPoint("LEFT", tp, "LEFT", 6, 0)
    w.teleport = tp

    w.notLearned = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    w.notLearned:SetTextColor(1, 0.4, 0.4)
    w.notLearnedIcon = w:CreateTexture(nil, "OVERLAY")
    w.notLearnedIcon:SetSize(16, 16)
    w.notLearnedIcon:SetPoint("RIGHT", w.notLearned, "LEFT", -5, 0)
    w.notLearnedIcon:SetDesaturated(true)

    w.footer = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    w.footer:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -10, 7)
    w.footer:SetText("OxedHub")
    return w
end

-- Lays the window out for `data`; returns false when it has to wait for
-- combat to end.
local function FillGroupWindow(data, isFull)
    if InCombatLockdown() then return false end
    local w = BuildGroupWindow()
    if w.titleText then w.titleText:SetText(isFull and L["Group is full!"] or L["Group joined"]) end

    local dungeon = DungeonFor(data.mapID)
    local texture
    if dungeon and dungeon.challengeModeId and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, mapName, _, _, tex = pcall(C_ChallengeMode.GetMapUIInfo, dungeon.challengeModeId)
        if ok then
            texture = tex
            if not data.activity or data.activity == "" then data.activity = mapName end
        end
    end
    w.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_GroupNeedMore")
    w.activity:SetText(data.activity or L["Group finder"])

    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
    if not ROLE_ATLAS[Plain(role) or ""] then role = data.role end
    local atlas = role and ROLE_ATLAS[role]
    local showRole = settings.rowRole and atlas ~= nil
    w.roleIcon:SetShown(showRole)
    w.roleText:SetShown(showRole)
    if showRole then
        w.roleIcon:SetAtlas(atlas)
        w.roleText:SetText(_G[role] or role)
    end

    -- A name on two lines pushes the role, the divider and the rows down.
    local okH, nameH = pcall(w.activity.GetStringHeight, w.activity)
    local extra = (okH and type(nameH) == "number" and nameH > 24) and math.ceil(nameH - 18) or 0
    w.divider:ClearAllPoints()
    w.divider:SetPoint("TOPLEFT", w, "TOPLEFT", GW_PAD, -(94 + extra))
    w.divider:SetPoint("TOPRIGHT", w, "TOPRIGHT", -GW_PAD, -(94 + extra))
    local y = 106 + extra
    for _, row in ipairs(ROWS) do
        local r = w.rows[row.key]
        local value = data[row.key]
        if IsBlank(value) or not settings[row.option] then
            r.label:Hide()
            r.value:Hide()
        else
            r.label:ClearAllPoints()
            r.label:SetPoint("TOPLEFT", w, "TOPLEFT", GW_PAD, -y)
            r.label:SetText(L[row.label])
            r.value:SetText(value)
            r.label:Show()
            r.value:Show()
            -- The height of a protected text can itself come back secret.
            local ok, h = pcall(r.value.GetStringHeight, r.value)
            if not ok or type(h) ~= "number" or (issecretvalue and issecretvalue(h)) then
                h = row.wrap and 42 or 14
            end
            y = y + math.max(14, h) + 6
        end
    end

    -- A learned teleport is a button; one not learned yet is a line of
    -- text in the window, not a greyed button nobody can read.
    local tp = w.teleport
    local spell = settings.teleport and TeleportSpell(dungeon)
    local info = spell and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
    tp:Hide()
    w.notLearned:Hide()
    w.notLearnedIcon:Hide()
    if spell and SpellKnown(spell) then
        y = y + 6
        tp:ClearAllPoints()
        tp:SetPoint("TOP", w, "TOP", 0, -y)
        tp.icon:SetTexture(info and info.iconID or 136222)
        tp:SetAttribute("type", "spell")
        tp:SetAttribute("spell", spell)
        tp:SetText(L["Teleport to the dungeon"])
        tp:Enable()
        tp:SetAlpha(1)
        y = y + 26
    elseif spell then
        y = y + 8
        w.notLearned:ClearAllPoints()
        w.notLearned:SetPoint("TOP", w, "TOP", 10, -y)
        w.notLearned:SetText(L["Teleport not learned yet"])
        w.notLearnedIcon:SetTexture(info and info.iconID or 136222)
        w.notLearned:Show()
        w.notLearnedIcon:Show()
        y = y + 18
    end

    w:SetHeight(y + 30)
    w:ClearAllPoints()
    w:SetPoint("CENTER", UIParent, "CENTER", settings.winX or 0, settings.winY or 160)
    w:Show()
    -- Above the window: it is not the window's child, so it is not lifted
    -- with it on its own.
    if spell and SpellKnown(spell) then
        tp:SetFrameStrata(w:GetFrameStrata())
        tp:SetFrameLevel(w:GetFrameLevel() + 20)
        tp:Show()
    end
    return true
end

local function AnnounceGroup(data, isFull)
    local parts = { data.activity or L["Group finder"] }
    if type(data.leader) == "string" then parts[#parts + 1] = L["leader %s"]:format(data.leader) end
    local role = data.role and _G[data.role]
    if settings.rowRole and type(role) == "string" then parts[#parts + 1] = L["as %s"]:format(role) end
    print(("%s%s %s. |cffffd100|H%s|h[%s]|h|r"):format(PREFIX,
        isFull and L["Your group is full:"] or L["You joined a group:"],
        table.concat(parts, ", "), GROUP_LINK, L["Show the window"]))
end

local function OpenGroup(data, isFull)
    if not (settings and settings.enabled and settings.groupWindow and data) then return end
    shown = data
    if not FillGroupWindow(data, isFull) then
        pendingShow = { data = data, isFull = isFull }
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    if settings.groupChat then AnnounceGroup(data, isFull) end
end

-- Whether this module draws the group window, so MythicLooter's own teleport
-- popup stays out of the way.
OxedHub.InviterInfo = {
    OwnsGroupWindow = function()
        return settings and settings.enabled and settings.groupWindow and true or false
    end,
}

local function HideGameMessage()
    if not (settings and settings.enabled and settings.groupWindow and settings.hideGameInvite) then return end
    local dialog = LFGListInviteDialog
    if dialog and dialog:IsShown() and dialog.informational and dialog.resultID == suppressResult then
        StaticPopupSpecial_Hide(dialog)
    end
end

local function Watch(data, sawIncomplete)
    tracked = { data = data, sawIncomplete = sawIncomplete }
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("GROUP_LEFT")
end

local function OnApplication(resultID, status)
    if status ~= "inviteaccepted" or not settings.groupWindow then return end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or not info.activityIDs then return end
    local activityInfo = C_LFGList.GetActivityInfoTable(info.activityIDs[1], nil, info.isWarMode)
    local _, _, _, _, role = C_LFGList.GetApplicationInfo(resultID)
    local data = ReadListing(info, activityInfo, nil, Plain(role))
    if not data then return end
    suppressResult = resultID
    HideGameMessage()
    OpenGroup(data, false)
    Watch(data, true)
end

-- Your own listing: watched so the window opens when it fills up.
local function OnActiveEntry()
    if tracked or not (settings.groupWindow and settings.groupFull) then return end
    local entry = C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()
    if not entry or not entry.activityIDs then return end
    local activityInfo = C_LFGList.GetActivityInfoTable(entry.activityIDs[1])
    local data = ReadListing(entry, activityInfo, Plain(UnitName("player")), nil)
    if data then Watch(data, GetNumGroupMembers() < data.maxSize) end
end

local function OnRoster()
    if not tracked then return end
    local size = tracked.data.maxSize or 5
    if GetNumGroupMembers() < size then
        tracked.sawIncomplete = true
        return
    end
    frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    if tracked.sawIncomplete and settings.groupFull and size <= 5 then OpenGroup(tracked.data, true) end
    tracked = nil
end

local function OnGroupLeft()
    tracked, pendingShow, suppressResult = nil, nil, nil
    frame:UnregisterEvent("GROUP_ROSTER_UPDATE")
    frame:UnregisterEvent("GROUP_LEFT")
end

local function OnCombatEnd()
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    -- A window closed in combat left its teleport button invisible.
    if groupWin and not groupWin:IsShown() then groupWin.teleport:Hide() end
    local p = pendingShow
    pendingShow = nil
    if p then FillGroupWindow(p.data, p.isFull) end
end

-- The window with made-up details, so the options can be judged without
-- queueing. It takes the first dungeon whose teleport you know.
local function TestGroupWindow()
    local data = {
        activity = L["Test dungeon"], name = L["Test group"], leader = UnitName("player"),
        playstyle = GROUP_FINDER_GENERAL_PLAYSTYLE2, itemLevel = "640", voice = "Discord",
        comment = L["A sample description, as the group leader would write it. Long ones wrap onto more lines."],
        role = "DAMAGER", maxSize = 5,
    }
    local ML = OxedHub.MythicLooter
    local Query = ML and ML.Query
    if Query and Query.GetDungeons then
        local ok, list = pcall(Query.GetDungeons, Query)
        for _, dungeon in ipairs(ok and list or {}) do
            local spell = TeleportSpell(dungeon)
            if not data.mapID or (spell and SpellKnown(spell)) then
                data.mapID = dungeon.instanceId
                data.activity = nil
                if spell and SpellKnown(spell) then break end
            end
        end
    end
    if not FillGroupWindow(data, false) then
        print(PREFIX .. L["The group window cannot open in combat."])
    end
end

local function ResetGroupWindow()
    settings.winX, settings.winY = nil, nil
    if groupWin and groupWin:IsShown() then
        groupWin:ClearAllPoints()
        groupWin:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    end
end

if EventRegistry and EventRegistry.RegisterCallback then
    -- Whether the owner comes first depends on the build; the link is
    -- whichever of the first two arguments it is.
    EventRegistry:RegisterCallback("SetItemRef", function(a, b)
        if a ~= GROUP_LINK and b ~= GROUP_LINK then return end
        if shown and not FillGroupWindow(shown, false) then
            print(PREFIX .. L["The group window cannot open in combat."])
        end
    end)
end

if EventUtil and EventUtil.ContinueOnAddOnLoaded then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder", function()
        if LFGListInviteDialog_Show then hooksecurefunc("LFGListInviteDialog_Show", HideGameMessage) end
    end)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if not (settings and settings.enabled) then return end
    if event == "PARTY_INVITE_REQUEST" then
        local name, _, _, _, _, _, guid = ...
        inviteSerial = inviteSerial + 1
        local serial = inviteSerial
        if settings.sound ~= "" and OxedHub.ModuleAPI then OxedHub.ModuleAPI:PlaySound(settings.sound) end
        C_Timer.After(0, function() ShowInvite(serial, guid, Plain(name), 0) end)
    elseif event == "GUILD_INVITE_REQUEST" and settings.guild then
        local inviter, guildName, points, _, isNewGuild = ...
        if not (Plain(inviter) and Plain(guildName)) then return end
        local line = (L["%s invites you to <%s>"]):format(inviter, guildName)
        if Plain(points) then line = line .. (L[", %d achievement points"]):format(points) end
        if isNewGuild == true then line = line .. L[", |cffffd100a brand new guild|r"] end
        print(PREFIX .. line .. ".")
    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        OnApplication(...)
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        OnActiveEntry()
    elseif event == "GROUP_ROSTER_UPDATE" then
        OnRoster()
    elseif event == "GROUP_LEFT" then
        OnGroupLeft()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

-- The note as it would look, under the options window, describing you.
local function Preview(window)
    if not window or not window:IsShown() then return end
    local text = Describe(UnitGUID("player"), UnitName("player"))
    if text == "" then text = L["Nothing chosen to show."] end
    ShowNote(window, text)
end

-- A made-up group invite where the game shows the real one, with the line
-- under it, so the look can be judged in place. Its buttons only close it.
local testInvite
local function TestInvite()
    if not testInvite then
        local t = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        testInvite = t
        t:SetSize(320, 96)
        t:SetFrameStrata("DIALOG")
        t:SetPoint("TOP", UIParent, "TOP", 0, -135)
        local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
        if Panel and Panel.ApplyOrnateFrame then Panel.ApplyOrnateFrame(t, nil, 0.97) end
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t.text:SetPoint("TOP", t, "TOP", 0, -20)
        t.text:SetWidth(290)
        t.tag = t:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        t.tag:SetPoint("TOPRIGHT", t, "TOPRIGHT", -10, -6)
        for i, label in ipairs({ ACCEPT or "Accept", DECLINE or "Decline" }) do
            local b = CreateFrame("Button", nil, t, "UIPanelButtonTemplate")
            b:SetSize(120, 22)
            b:SetPoint("BOTTOM", t, "BOTTOM", i == 1 and -64 or 64, 16)
            b:SetText(label)
            b:SetScript("OnClick", function() t:Hide() end)
        end
        -- Gone on its own after a while, like an invite that was ignored.
        t:SetScript("OnShow", function(self)
            self.serial = (self.serial or 0) + 1
            local serial = self.serial
            C_Timer.After(20, function() if self.serial == serial then self:Hide() end end)
        end)
    end
    testInvite.tag:SetText(L["Test"])
    testInvite.text:SetText(L["%s invites you to a group."]:format(UnitName("player") or "?"))
    testInvite:Hide()
    testInvite:Show()
    Preview(testInvite)
end

local function Restyle()
    if note and note:IsShown() then
        local anchor = note:GetParent()
        if anchor == optionsWindow or anchor == lookWindow or anchor == testInvite then
            Preview(anchor)
        else
            Style()
        end
    end
end

-- A window just as tall as what was put in it.
local function Fit(w)
    w:SetHeight(math.max(140, -w.cursorY + 16))
end

local function AddButton(w, text, x, onClick)
    local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetPoint("TOPLEFT", w, "TOPLEFT", x, w.cursorY - 2)
    button:SetText(OxedHub.T(text))
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
        OxedHub.UI:ApplyRedButtonStyle(button)
    end
    button:SetScript("OnClick", onClick)
    return button
end

local function ShowLook()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not lookWindow then
        local w = API:CreateOptionsWindow("Inviter Info: look", 460, 560)
        lookWindow = w
        w:HookScript("OnShow", function() C_Timer.After(0, function() Preview(w) end) end)

        w:AddChoice(settings, "font", "Font", FontChoices(), Restyle)
        w:AddSlider(settings, "fontSize", "Text size", 8, 28, 1, "%s: %d", Restyle)
        w:AddChoice(settings, "outline", "Text outline", {
            { value = "", text = "None" }, { value = "OUTLINE", text = "Thin" },
            { value = "THICKOUTLINE", text = "Thick" },
        }, Restyle)
        w:AddColour(settings, "textColour", "Text colour", Restyle)
        w:AddColour(settings, "knownColour", "Friend or guild colour", Restyle)
        w:AddColour(settings, "strangerColour", "Stranger colour", Restyle)
        w:AddCheckbox(settings, "background", "Dark background", nil, Restyle)
        w:AddSlider(settings, "bgAlpha", "Background", 0, 1, 0.05, "%s: %.2f", Restyle)
        w:AddCheckbox(settings, "border", "Ornate frame", nil, Restyle)
        w:AddChoice(settings, "position", "Where", {
            { value = "below", text = "Under the invite" }, { value = "above", text = "Above the invite" },
        }, Restyle)
        w:AddSlider(settings, "offset", "Gap", 0, 40, 1, "%s: %d", Restyle)
        w:AddNote("The line under this window shows how an invite will look.")
        AddButton(w, "Show a test invite", 20, TestInvite)
        w.cursorY = w.cursorY - 32
        Fit(w)
    end
    if optionsWindow then optionsWindow:Hide() end
    lookWindow:Show()
end

local groupOptions
local function ShowGroupOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not groupOptions then
        local w = API:CreateOptionsWindow("Inviter Info: group window", 460, 600)
        groupOptions = w
        w:AddNote("When the group finder puts you in a group, a window shows the activity, your role and the group's listing, with a teleport button for dungeons.")
        AddButton(w, "Test", 20, TestGroupWindow)
        AddButton(w, "Reset position", 250, ResetGroupWindow)
        w.cursorY = w.cursorY - 32
        w:AddCheckbox(settings, "groupWindow", "Show the window when you join a group")
        w:AddCheckbox(settings, "groupFull", "Again when the group fills up", "Also for a group you listed yourself.")
        w:AddCheckbox(settings, "groupChat", "A line in chat as well", "With a link that brings the window back after it is closed.")
        w:AddCheckbox(settings, "hideGameInvite", "Hide the game's own invite message")
        w:AddCheckbox(settings, "teleport", "Teleport button", "Needs MythicLooter's dungeon list, which loads with OxedHub.")
        w:AddNote("The window shows:")
        w:AddCheckbox(settings, "rowRole", "Your role")
        w:AddCheckbox(settings, "rowName", "Group name")
        w:AddCheckbox(settings, "rowLeader", "Leader")
        w:AddCheckbox(settings, "rowPlaystyle", "Playstyle")
        w:AddCheckbox(settings, "rowItemLevel", "Item level")
        w:AddCheckbox(settings, "rowVoice", "Voice chat")
        w:AddCheckbox(settings, "rowDescription", "Description")
        Fit(w)
    end
    groupOptions:Show()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Inviter Info", 440, 500)
        optionsWindow = w
        w:HookScript("OnShow", function() C_Timer.After(0, function() Preview(w) end) end)

        AddButton(w, "Group window", 20, ShowGroupOptions)
        AddButton(w, "Look and position", 250, ShowLook)
        w.cursorY = w.cursorY - 32
        AddButton(w, "Show a test invite", 20, TestInvite)
        w.cursorY = w.cursorY - 32

        w:AddCheckbox(settings, "showClass", "Class", nil, Restyle)
        w:AddCheckbox(settings, "classColour", "Class in its own colour", nil, Restyle)
        w:AddCheckbox(settings, "showRace", "Race", nil, Restyle)
        w:AddCheckbox(settings, "showRealm", "Realm", nil, Restyle)
        w:AddCheckbox(settings, "showKnown", "Whether they are a friend or in your guild", nil, Restyle)
        w:AddCheckbox(settings, "inChat", "Also say it in chat")
        w:AddCheckbox(settings, "guild", "A line in chat for guild invites")
        w:AddSoundPicker(settings, "sound", "Sound on an invite", "None")
        w:AddNote("Shown under the group invite: class, race, realm, and whether you know them. The line under this window shows how it will look.")
        Fit(w)
    end
    if lookWindow then lookWindow:Hide() end
    optionsWindow:Show()
end

-- The colours are tables: made here, per character's saved settings, so no
-- two share one by accident.
local function Bind(config)
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    local colours = {
        textColour = { 1, 1, 1 }, knownColour = { 0.25, 1, 0.25 },
        strangerColour = { 0.67, 0.67, 0.67 },
    }
    for key, value in pairs(colours) do
        if type(config[key]) ~= "table" then config[key] = value end
    end
    settings = config
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.inviterinfo
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.inviterinfo = config
    end
    Bind(config)

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "inviterinfo",
        name     = "Inviter Info",
        version  = "1.2.2",
        updated  = 20261025.18,  -- teleport button above the window, readable "not learned", long names wrap
        author   = "Oxed",
        category = "groups",
        keywords = { "invite", "group", "party", "guild", "class", "friend", "font", "teleport", "lfg", "reminder" },
        desc     = "Who invites you, and a window with the group's details when the group finder puts you in one.",
        icon     = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            Bind(cfg)
            frame:RegisterEvent("PARTY_INVITE_REQUEST")
            frame:RegisterEvent("GUILD_INVITE_REQUEST")
            frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
            frame:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
        end,
        OnDisable = function()
            frame:UnregisterAllEvents()
            tracked, pendingShow = nil, nil
            if note then note:Hide() end
            if groupWin and not InCombatLockdown() then groupWin:Hide() end
        end,
    })
end)
