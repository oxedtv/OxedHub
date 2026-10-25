-- KickSyncKeystones.lua - Mythic+ Keystone List & Group Sync
-- Displays party members' keystones with dungeon teleport shortcuts.
--
-- Features:
--   * Speaks "WA-KeyStGrList" on PARTY addon channel (compatible with
--     WeakAuras Keystone List, Astral Keys, and KickSync).
--   * Click-to-cast dungeon teleport button.
--   * Announces all keys to party chat with 1 click (/kskeys).
--   * Sleek OxedHub UI with class colors and draggable frame.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
OxedHub.KickSyncKeystones = OxedHub.KickSyncKeystones or {}
local KL = OxedHub.KickSyncKeystones

local CHAT_PREFIX = "WA-KeyStGrList"
local KEYSTONE_ITEM_ID = 180653

-- Dungeon ID -> { abbr, portSpellID }
local DUNGEON_INFO = {
    -- The War Within & Current M+
    [501] = { abbr = "SV",     port = 445417 }, -- The Stonevault
    [502] = { abbr = "COT",    port = 445416 }, -- City of Threads
    [503] = { abbr = "ARA",    port = 445414 }, -- Ara-Kara, City of Echoes
    [504] = { abbr = "DAWN",   port = 445440 }, -- The Dawnbreaker
    [505] = { abbr = "CIND",   port = 445441 }, -- Cinderbrew Meadery
    [506] = { abbr = "DFC",    port = 445443 }, -- Darkflame Cleft
    [507] = { abbr = "GB",     port = 445424 }, -- Grim Batol
    [499] = { abbr = "ROOK",   port = 445418 }, -- The Rookery
    [500] = { abbr = "PRIORY", port = 445444 }, -- Priory of the Sacred Flame
    [525] = { abbr = "FLOOD",  port = 1216786}, -- Operation: Floodgate

    -- Battle for Azeroth
    [244] = { abbr = "AD",     port = 424187 }, -- Atal'Dazar
    [245] = { abbr = "FH",     port = 410071 }, -- Freehold
    [246] = { abbr = "ML",     port = 410081 }, -- The MOTHERLODE!!
    [247] = { abbr = "KR",     port = 410078 }, -- Kings' Rest
    [248] = { abbr = "WM",     port = 424167 }, -- Waycrest Manor
    [249] = { abbr = "TD",     port = 410075 }, -- Tol Dagor
    [250] = { abbr = "SET",    port = 410077 }, -- Temple of Sethraliss
    [251] = { abbr = "UNDR",   port = 410074 }, -- The Underrot
    [252] = { abbr = "SHR",    port = 410072 }, -- Shrine of the Storm
    [353] = { abbr = "SoB",    port = 445418 }, -- Siege of Boralus
    [369] = { abbr = "YARD",   port = 373262 }, -- Operation: Mechagon - Junkyard
    [370] = { abbr = "WORK",   port = 373262 }, -- Operation: Mechagon - Workshop

    -- Shadowlands
    [375] = { abbr = "MISTS",  port = 354464 }, -- Mists of Tirna Scithe
    [376] = { abbr = "NW",     port = 354462 }, -- The Necrotic Wake
    [377] = { abbr = "DOS",    port = 354465 }, -- De Other Side
    [378] = { abbr = "HOA",    port = 354466 }, -- Halls of Atonement
    [379] = { abbr = "PF",     port = 354467 }, -- Plaguefall
    [380] = { abbr = "SD",     port = 354468 }, -- Sanguine Depths
    [381] = { abbr = "SOA",    port = 354469 }, -- Spires of Ascension
    [382] = { abbr = "TOP",    port = 354463 }, -- Theater of Pain
    [391] = { abbr = "STRT",   port = 367416 }, -- Tazavesh: Streets of Wonder
    [392] = { abbr = "GAMB",   port = 367416 }, -- Tazavesh: So'leah's Gambit

    -- Dragonflight
    [399] = { abbr = "RLP",    port = 393256 }, -- Ruby Life Pools
    [400] = { abbr = "NO",     port = 393262 }, -- The Nokhud Offensive
    [401] = { abbr = "AV",     port = 393267 }, -- The Azure Vault
    [402] = { abbr = "AA",     port = 393273 }, -- Algeth'ar Academy
    [403] = { abbr = "ULD",    port = 424153 }, -- Uldaman: Legacy of Tyr
    [404] = { abbr = "NELTH",  port = 393279 }, -- Neltharus
    [405] = { abbr = "BH",     port = 393283 }, -- Brackenhide Hollow
    [406] = { abbr = "HOI",    port = 393222 }, -- Halls of Infusion
    [463] = { abbr = "FALL",   port = 424197 }, -- Dawn of the Infinite: Galakrond's Fall
    [464] = { abbr = "RISE",   port = 424198 }, -- Dawn of the Infinite: Murozond's Rise

    -- Legion / Older
    [198] = { abbr = "DHT",    port = 424163 }, -- Darkheart Thicket
    [199] = { abbr = "BRH",    port = 424153 }, -- Black Rook Hold
    [200] = { abbr = "HOV",    port = 393276 }, -- Halls of Valor
    [206] = { abbr = "NL",     port = 410074 }, -- Neltharion's Lair
    [210] = { abbr = "COS",    port = 393279 }, -- Court of Stars
    [227] = { abbr = "LOWR",   port = 373274 }, -- Return to Karazhan: Lower
    [234] = { abbr = "UPPR",   port = 373274 }, -- Return to Karazhan: Upper
    [438] = { abbr = "VP",     port = 410080 }, -- Vortex Pinnacle
    [456] = { abbr = "TOT",    port = 424142 }, -- Throne of the Tides
}

local partyKeys = {}  -- [name] = { mapID = mapID, level = level, class = class, dungeon = name }
local isRegistered = false
local listWindow = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────

-- The teleport for a dungeon. MythicLooter's dungeon list is kept up to date
-- each season, so it is asked first; the table above only knows older
-- dungeons, and the new season's keys had icons that did nothing on click.
local seasonPorts
local function PortFor(mapID)
    if not mapID then return nil end
    if not seasonPorts then
        local ML = OxedHub.MythicLooter
        local list = ML and ML.DungeonDatabase
        if type(list) == "table" then
            seasonPorts = {}
            for _, dungeon in ipairs(list) do
                local port = dungeon.teleportSpellId
                if type(port) == "function" then
                    local ok, id = pcall(port)
                    port = ok and id or nil
                end
                if dungeon.challengeModeId and type(port) == "number" then
                    seasonPorts[dungeon.challengeModeId] = port
                end
            end
        end
    end
    local port = seasonPorts and seasonPorts[mapID]
    if port then return port end
    local info = DUNGEON_INFO[mapID]
    return info and info.port or nil
end

local function GetOwnKeystone()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()
    if not mapID or mapID == 0 then return nil end
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    local _, class = UnitClass("player")
    return {
        mapID   = mapID,
        level   = level or 0,
        class   = class or "WARRIOR",
        dungeon = name or L["Unknown"],
        name    = UnitName("player"),
    }
end

-- ── Sync ────────────────────────────────────────────────────────────────────
-- Three ways keys reach us, so a party member's key shows whichever key
-- addon they run:
--   * "WA-KeyStGrList" on the PARTY channel, the protocol the Keystone Group
--     List weakaura and several key addons speak:
--         KSGL:Send:<mapID>:<level>:<activityID>:<groupID>:<resilient>
--         KSGL:Request:0       -- "everyone, send me your key"
--     ⚠ It used to send "mapID:level:0:0" through C_ChatInfo.SendAddOnMessage
--     -- a name that does not exist (it is SendAddonMessage), inside pcall,
--     so nothing ever left, and no other addon could have read it anyway.
--   * LibOpenRaid, when another addon (Details!, ...) has loaded it.
--   * LibKeystone, when another addon (BigWigs, ...) has loaded it.
-- Keys are kept only for people in the party; the list is pruned on every
-- roster change.

local lastSentStamp = nil       -- "mapID:level" last announced, to skip repeats
local wasInGroup = false
local rosterQueued = false
local RefreshShown              -- defined below the window code
local ApplyRaidVisibility       -- the list hides in a raid; defined with the window

local function GetLib(name)
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, name, true)
    return ok and lib or nil
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- ⚠ Keys are filed under the character's bare name, without the realm.
-- The addon channel, LibKeystone and LibOpenRaid all name a player from
-- another realm "Name-Realm", while UnitName hands back "Name" and the realm
-- apart. Comparing the two whole threw away every cross-realm key -- in a
-- group from the finder that is nearly everyone, so the list only ever held
-- the player's own key. Two members of one party sharing a name on
-- different realms is the only case this cannot tell apart.
local function BareName(name)
    if type(name) ~= "string" or IsSecret(name) or name == "" then return nil end
    return name:match("^([^%-]+)") or name
end

-- ⚠ A message the game refuses is lost without an error: throttled, or, on
-- 12.0, addon messages are not allowed during a fight in an instance. The
-- send's own answer says so; it is tried again a few seconds later, a few
-- times at most.
local SEND_RETRIES, SEND_RETRY_GAP = 3, 3
local function SendParty(msg, tries)
    -- The protocol is party only; a raid has no use for five keys.
    if not IsInGroup() or IsInRaid() then return end
    local send = C_ChatInfo and (C_ChatInfo.SendAddonMessage or C_ChatInfo.SendAddOnMessage)
    if not send then return end
    local ok, result = pcall(send, CHAT_PREFIX, msg, "PARTY")
    -- Success is 0 in the result enum; older clients answered true or nothing.
    local sent = ok and (result == nil or result == true or result == 0)
    tries = tries or 0
    if not sent and tries < SEND_RETRIES then
        C_Timer.After(SEND_RETRY_GAP, function() SendParty(msg, tries + 1) end)
    end
end

local function PartyUnitFor(name)
    name = BareName(name)
    if not name then return nil end
    if name == UnitName("player") then return "player" end
    for i = 1, 4 do
        local unit = "party" .. i
        local ok, unitName = pcall(UnitName, unit)
        if ok and BareName(unitName) == name then
            return unit
        end
    end
    return nil
end

-- name: short or "Name-Realm"; rating: optional, from LibKeystone.
local function StoreKey(name, mapID, level, rating, classFile)
    mapID, level = tonumber(mapID), tonumber(level)
    name = BareName(name)
    if not name or not mapID or not level or mapID <= 0 or level <= 0 then
        return false
    end
    local unit = PartyUnitFor(name)
    if not unit then return false end

    local old = partyKeys[name]
    if old and old.mapID == mapID and old.level == level and (not rating or old.rating == rating) then
        return false
    end

    if not classFile then
        local ok, _, cls = pcall(UnitClass, unit)
        if ok and type(cls) == "string" then classFile = cls end
    end
    partyKeys[name] = {
        mapID   = mapID,
        level   = level,
        class   = classFile or (old and old.class) or "PRIEST",
        dungeon = C_ChallengeMode.GetMapUIInfo(mapID) or "M+",
        name    = name,
        rating  = rating or (old and old.rating),
    }
    return true
end

-- Our own key, to anyone who asks. force: send even if it was sent before
-- (an answer to a request, or someone new in the party).
local function BroadcastOwnKey(force)
    local own = GetOwnKeystone()
    if not own then return end
    partyKeys[own.name] = own
    if not IsInGroup() then return end

    local stamp = own.mapID .. ":" .. own.level
    if not force and stamp == lastSentStamp then return end
    lastSentStamp = stamp
    SendParty(("KSGL:Send:%d:%d:0:0:0"):format(own.mapID, own.level))
end

-- Ask everyone, through every route there is.
local function RequestKeys()
    SendParty("KSGL:Request:0")

    local openRaid = GetLib("LibOpenRaid-1.0")
    if openRaid and openRaid.RequestKeystoneDataFromParty then
        pcall(openRaid.RequestKeystoneDataFromParty)
    end
    local libKeystone = GetLib("LibKeystone")
    if libKeystone and libKeystone.Request then
        pcall(libKeystone.Request, "PARTY")
    end
end

-- Drop everyone who has left; everything when we have.
local function PruneKeys()
    local me = UnitName("player")
    for name in pairs(partyKeys) do
        if name ~= me and not PartyUnitFor(name) then
            partyKeys[name] = nil
        end
    end
end

-- ── Network Receiver ────────────────────────────────────────────────────────

local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= CHAT_PREFIX or type(msg) ~= "string" or type(sender) ~= "string" then return end
    if channel ~= "PARTY" or IsSecret(msg) then return end
    local name = BareName(sender)
    if not name or name == UnitName("player") then return end

    local kind, rest = msg:match("^KSGL:(%a+):(.*)$")
    local changed = false
    if kind == "Send" then
        local mapID, level = rest:match("^(%d+):(%d+)")
        changed = StoreKey(name, mapID, level)
    elseif kind == "Request" then
        BroadcastOwnKey(true)
    elseif not kind then
        -- Older OxedHub builds sent a bare "mapID:level:0:0".
        local mapID, level = msg:match("^(%d+):(%d+):")
        changed = StoreKey(name, mapID, level)
    end
    if changed and RefreshShown then RefreshShown() end
end

-- ── Keys linked in party chat ──────────────────────────────────────────────
-- Astral Keys and several others answer "!keys" with real keystone links,
-- and players link their own key. A link carries the dungeon and level:
--     |Hkeystone:<itemID>:<mapID>:<level>:...|h[Keystone: ...]|h
-- Whose key it is: Astral Keys writes "Astral Keys: <character> [link]" and
-- lists the sender's alts too, so such a line counts only when the character
-- is the sender. Any other line with exactly one link is the sender's key.
local function OnPartyChat(text, sender)
    if IsSecret(text) or IsSecret(sender) then return end
    if type(text) ~= "string" or type(sender) ~= "string" then return end
    if not text:find("|Hkeystone:", 1, true) then return end

    local name = BareName(sender)
    if not name or name == UnitName("player") then return end

    local owner = text:match("Astral Keys:%s*([^%s|%[]+)")
    if owner and BareName(owner) ~= name then return end

    local mapID, level, count = nil, nil, 0
    for m, l in text:gmatch("|Hkeystone:%d+:(%d+):(%d+)") do
        mapID, level, count = m, l, count + 1
    end
    if count ~= 1 then return end

    if StoreKey(name, mapID, level) and RefreshShown then
        RefreshShown()
    end
end

-- Party members we hold no key for.
local function MissingKeys()
    local missing = 0
    for i = 1, GetNumSubgroupMembers() do
        local ok, unitName = pcall(UnitName, "party" .. i)
        if ok and type(unitName) == "string" and not IsSecret(unitName)
            and not partyKeys[unitName] then
            missing = missing + 1
        end
    end
    return missing
end

local lastChatAsk = 0
local CHAT_ASK_GAP = 60

-- Last resort, on the player's own Sync click only: ask in party chat, which
-- every key addon answers. Seen by the party, so at most once a minute, and
-- only when the quiet routes left someone out.
local function AskInChatIfMissing()
    if not IsInGroup() or IsInRaid() then return end
    local db = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.kicksync
    if type(db) == "table" and db.keysChatAsk == false then return end
    if GetTime() - lastChatAsk < CHAT_ASK_GAP then return end
    if MissingKeys() == 0 then return end
    lastChatAsk = GetTime()
    pcall(SendChatMessage, "!keys", "PARTY")
end

local libsHooked = false
local function HookLibraries()
    if libsHooked then return end
    libsHooked = true

    local openRaid = GetLib("LibOpenRaid-1.0")
    if openRaid and openRaid.RegisterCallback then
        local listener = {
            -- Called as a plain function: (playerName, info, allKeystones).
            OnKeystoneUpdate = function(playerName, info)
                if type(playerName) ~= "string" or type(info) ~= "table" then return end
                local classFile
                if info.classID and GetClassInfo then
                    classFile = select(2, GetClassInfo(info.classID))
                end
                local rating = tonumber(info.rating)
                if rating and rating <= 0 then rating = nil end
                if StoreKey(playerName, info.challengeMapID, info.level, rating, classFile) and RefreshShown then
                    RefreshShown()
                end
            end,
        }
        pcall(openRaid.RegisterCallback, listener, "KeystoneUpdate", "OnKeystoneUpdate")
    end

    local libKeystone = GetLib("LibKeystone")
    if libKeystone and libKeystone.Register then
        pcall(libKeystone.Register, KL, function(level, mapID, rating, sender)
            rating = tonumber(rating)
            if rating and rating <= 0 then rating = nil end
            if StoreKey(sender, mapID, level, rating) and RefreshShown then
                RefreshShown()
            end
        end)
    end
end

-- Roster changes come in bursts; one pass a second later covers them.
local function OnRosterSettled()
    rosterQueued = false
    local inGroup = IsInGroup()
    if not inGroup then
        local own = partyKeys[UnitName("player")]
        wipe(partyKeys)
        if own then partyKeys[own.name] = own end
        lastSentStamp = nil
    else
        PruneKeys()
        -- Someone new may be in the party: they need our key, and we theirs.
        -- Roster changes are rare enough that asking each time costs nothing.
        BroadcastOwnKey(true)
        RequestKeys()
    end
    wasInGroup = inGroup
    if ApplyRaidVisibility then ApplyRaidVisibility() end
    if RefreshShown then RefreshShown() end
end

-- ── UI Window ───────────────────────────────────────────────────────────────
-- A see-through list: one row per key, the dungeon's icon with the level on
-- it, the owner (class coloured, rating in orange) above the dungeon's name.
-- A thin header fades in on hover. Clicking an icon casts that dungeon's
-- teleport through a secure button: CastSpellByID from a plain click is
-- protected, so the icon's attributes change only out of combat.

local ROW_H, ICON, LIST_W, HEADER_H = 40, 36, 240, 18
local MAX_ROWS = 5
local HEADER_IDLE_ALPHA = 0.3
local RATING_HEX = "ff8000"

-- Saved next to the KickSync settings. Plain values only.
local KEY_DEFAULTS = {
    keysPoint = "CENTER", keysX = 0, keysY = 100,
    keysLocked = false, keysScale = 1.0, keysBgAlpha = 0,
}

local listDirty = false   -- an update was asked for in combat
local keysOptions = nil

local function Config()
    -- Still saved under "kicksync", where players' positions already are.
    -- The KickSync module is gone, so nothing else makes the table now.
    if not OxedHubDB then return KEY_DEFAULTS end
    OxedHubDB.modules = OxedHubDB.modules or {}
    local db = OxedHubDB.modules.kicksync
    if type(db) ~= "table" then
        db = {}
        OxedHubDB.modules.kicksync = db
    end
    for k, v in pairs(KEY_DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return db
end

local function RatingFor(name)
    local unit = PartyUnitFor(name)
    if not unit or not (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then return nil end
    local ok, score = pcall(function()
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary(unit)
        local s = summary and summary.currentSeasonScore
        if type(s) == "number" and s > 0 then return math.floor(s) end
        return nil
    end)
    return ok and score or nil
end

-- Keys other addons already shared, through LibOpenRaid when it is loaded.
-- Through StoreKey, like every other route: it files them under the bare
-- name and keeps only the party. (Its updates arrive by the listener in
-- HookLibraries; a second listener here redrew the list for every guild
-- member's key.)
local function MergeOpenRaid()
    local lib = GetLib("LibOpenRaid-1.0")
    if not (lib and lib.GetAllKeystonesInfo) then return end
    local ok, all = pcall(lib.GetAllKeystonesInfo)
    if not ok or type(all) ~= "table" then return end
    for unitName, info in pairs(all) do
        if type(info) == "table" then
            local classFile
            if info.classID and GetClassInfo then
                classFile = select(2, GetClassInfo(info.classID))
            end
            local rating = tonumber(info.rating)
            if rating and rating <= 0 then rating = nil end
            pcall(StoreKey, unitName, info.challengeMapID, info.level, rating, classFile)
        end
    end
end

local function SavePosition(w)
    local db = Config()
    local point, _, _, x, y = w:GetPoint(1)
    db.keysPoint, db.keysX, db.keysY = point or "CENTER", x or 0, y or 0
end

local function ApplyLook(w)
    local db = Config()
    w:SetScale(db.keysScale or 1)
    w.bg:SetColorTexture(0, 0, 0, db.keysBgAlpha or 0)
end

local function SetHeaderHot(w, hot)
    w.header:SetAlpha(hot and 1 or HEADER_IDLE_ALPHA)
end

local function CheckHover(w)
    SetHeaderHot(w, w:IsMouseOver())
end

local function HeaderButton(w, texture, tip, onClick)
    local b = CreateFrame("Button", nil, w.header)
    b:SetSize(14, 14)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(texture)
    b:SetHighlightTexture(texture, "ADD")
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        SetHeaderHot(w, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        CheckHover(w)
    end)
    return b
end

local function ShowKeysOptions()
    local API = OxedHub.ModuleAPI
    if not API or not API.CreateOptionsWindow then return end
    local db = Config()
    if db == KEY_DEFAULTS then return end   -- settings not bound yet
    if not keysOptions then
        local o = API:CreateOptionsWindow("Party Keystones", 400, 230)
        local function Refresh() if listWindow then ApplyLook(listWindow) end end
        o:AddCheckbox(db, "keysLocked", "Lock the list", "Unlocked: drag it by the header.")
        o:AddSlider(db, "keysScale", "Scale", 0.6, 1.8, 0.05, "%s: %.2f", Refresh)
        o:AddSlider(db, "keysBgAlpha", "Background opacity", 0, 1, 0.05, "%s: %.2f", Refresh)
        o:AddNote("Click a dungeon icon to cast its teleport.")
        keysOptions = o
    end
    keysOptions:Show()
end

local function CreateRow(w, i)
    local row = CreateFrame("Frame", nil, w)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -HEADER_H - (i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, -HEADER_H - (i - 1) * ROW_H)

    local btn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate")
    btn:SetSize(ICON, ICON)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "spell")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)

    local lvl = btn:CreateFontString(nil, "OVERLAY")
    lvl:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    lvl:SetPoint("CENTER", btn, "CENTER", 0, 0)
    lvl:SetTextColor(1, 1, 1, 1)
    btn.lvl = lvl

    btn:SetScript("OnEnter", function(self)
        SetHeaderHot(w, true)
        local id = self:GetAttribute("spell")
        if id then
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetSpellByID(id)
            GameTooltip:AddLine(L["|cffffd100Click to teleport|r"])
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        CheckHover(w)
    end)
    row.btn = btn

    local who = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    who:SetPoint("TOPLEFT", btn, "TOPRIGHT", 6, -2)
    who:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    who:SetJustifyH("LEFT")
    who:SetWordWrap(false)
    who:SetShadowOffset(1, -1)
    row.who = who

    local dungeon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dungeon:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -3)
    dungeon:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    dungeon:SetJustifyH("LEFT")
    dungeon:SetWordWrap(false)
    dungeon:SetShadowOffset(1, -1)
    row.dungeon = dungeon

    return row
end

local function EnsureListUI()
    if listWindow then return listWindow end

    local db = Config()
    local w = CreateFrame("Frame", "OxedHub_KickSyncKeysWindow", UIParent)
    w:SetSize(LIST_W, HEADER_H + ROW_H)
    w:SetPoint(db.keysPoint or "CENTER", UIParent, db.keysPoint or "CENTER", db.keysX or 0, db.keysY or 100)
    w:SetMovable(true)
    w:SetClampedToScreen(true)
    w:SetFrameStrata("MEDIUM")
    w:Hide()

    local bg = w:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    w.bg = bg

    local header = CreateFrame("Frame", nil, w)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not Config().keysLocked and not InCombatLockdown() then w:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        w:StopMovingOrSizing()
        SavePosition(w)
    end)
    header:SetScript("OnEnter", function() SetHeaderHot(w, true) end)
    header:SetScript("OnLeave", function() CheckHover(w) end)
    w.header = header

    local line = header:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)

    local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", header, "LEFT", 2, 0)
    title:SetText(L["Party Keystones"])

    local close = HeaderButton(w, "Interface\\Buttons\\UI-StopButton", L["Close"], function()
        -- The rows hold secure buttons, so the list cannot hide in combat.
        if not InCombatLockdown() then
            w:Hide()
            Config().keysShown = false
        end
    end)
    close:SetPoint("RIGHT", header, "RIGHT", -1, 0)
    local gear = HeaderButton(w, "Interface\\Buttons\\UI-OptionsButton", L["Settings"], ShowKeysOptions)
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local announce = HeaderButton(w, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", L["Announce to party"],
        function() KL:AnnounceToChat() end)
    announce:SetPoint("RIGHT", gear, "LEFT", -4, 0)
    local sync = HeaderButton(w, "Interface\\Buttons\\UI-RefreshButton", L["Sync keys"], function()
        KL:SyncNow(true)
    end)
    sync:SetPoint("RIGHT", announce, "LEFT", -4, 0)

    local empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -HEADER_H - 6)
    empty:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -HEADER_H - 6)
    empty:SetJustifyH("LEFT")
    empty:SetText(L["No keystones yet. Press sync or wait for the group."])
    w.emptyLabel = empty

    w:SetScript("OnShow", function(self) SetHeaderHot(self, false) end)

    w.rows = {}
    ApplyLook(w)
    SetHeaderHot(w, false)
    listWindow = w
    return w
end

function KL:UpdateListUI()
    -- Secure icons cannot be created, shown or retargeted in combat.
    if InCombatLockdown() then
        listDirty = true
        return
    end
    listDirty = false

    local w = EnsureListUI()
    local own = GetOwnKeystone()
    if own then partyKeys[own.name] = own end
    MergeOpenRaid()

    local entries = {}
    for _, data in pairs(partyKeys) do
        entries[#entries + 1] = data
    end
    table.sort(entries, function(a, b) return (a.level or 0) > (b.level or 0) end)

    w.emptyLabel:SetShown(#entries == 0)
    local shown = math.min(#entries, MAX_ROWS)
    w:SetHeight(HEADER_H + math.max(shown, 1) * ROW_H)

    for i = 1, MAX_ROWS do
        local item = entries[i]
        local row = w.rows[i]
        if item and not row then
            row = CreateRow(w, i)
            w.rows[i] = row
        end
        if row then
            if item then
                local _, _, _, texture = C_ChallengeMode.GetMapUIInfo(item.mapID)
                row.btn.icon:SetTexture(texture or "Interface\\Icons\\INV_Relics_Hourglass")
                row.btn.lvl:SetText("+" .. (item.level or 0))

                local cHex = "ffffffff"
                local colour = item.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class]
                if colour and colour.colorStr then cHex = colour.colorStr end
                local rating = RatingFor(item.name) or item.rating
                if rating then
                    row.who:SetFormattedText("|c%s%s|r |cff%s(%d)|r", cHex, item.name or "?", RATING_HEX, rating)
                else
                    row.who:SetFormattedText("|c%s%s|r", cHex, item.name or "?")
                end
                row.dungeon:SetText(item.dungeon or L["Mythic+"])

                row.btn:SetAttribute("spell", PortFor(item.mapID))
                row:Show()
            else
                row.btn:SetAttribute("spell", nil)
                row:Hide()
            end
        end
    end
end

RefreshShown = function()
    if listWindow and listWindow:IsShown() then KL:UpdateListUI() end
    -- MythicLooter's Keys tab shows the same keys.
    if KL.onKeysChanged then pcall(KL.onKeysChanged) end
end

-- The party's keys for another view (MythicLooter's Keys tab): a fresh list,
-- highest key first, each { name, class, level, mapID, dungeon, rating, port }.
function KL:GetPartyKeys()
    local own = GetOwnKeystone()
    if own then partyKeys[own.name] = own end
    MergeOpenRaid()
    local list = {}
    for _, data in pairs(partyKeys) do
        list[#list + 1] = {
            name = data.name, class = data.class, level = data.level or 0,
            mapID = data.mapID, dungeon = data.dungeon,
            rating = RatingFor(data.name) or data.rating,
            port = PortFor(data.mapID),
        }
    end
    table.sort(list, function(a, b) return a.level > b.level end)
    return list
end

-- The header's Sync button and the window opening: send ours, ask for theirs.
-- fromClick: the player pressed Sync. Then, if the quiet routes have not
-- brought everyone's key within a few seconds, ask once in party chat.
function KL:SyncNow(fromClick)
    KL:Initialize()
    BroadcastOwnKey(true)
    RequestKeys()
    RefreshShown()
    if fromClick then
        C_Timer.After(3, AskInChatIfMissing)
    end
end

-- A raid has no use for five party keys: the list hides there and comes
-- back when the group is a party again (if the player had it open). The rows
-- are secure buttons, so in combat this waits for the fight to end.
ApplyRaidVisibility = function()
    if not listWindow then return end
    local db = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.kicksync
    local wanted = type(db) == "table" and db.keysShown == true and not IsInRaid()
    if listWindow:IsShown() == wanted then return end
    if InCombatLockdown() then
        listDirty = true
        return
    end
    if wanted then
        KL:UpdateListUI()
        listWindow:Show()
    else
        listWindow:Hide()
    end
end

function KL:ToggleWindow()
    KL:Initialize()
    if IsInRaid() then
        print(L["|cff9d5db8MythicLooter:|r the keystone list is for parties; it does not show in a raid."])
        return
    end
    if InCombatLockdown() then
        print(L["|cff9d5db8MythicLooter:|r the keystone list opens after combat."])
        return
    end
    local w = EnsureListUI()
    if w:IsShown() then
        w:Hide()
        Config().keysShown = false
    else
        KL:UpdateListUI()
        w:Show()
        Config().keysShown = true
        KL:SyncNow()
    end
end

-- Left open, it stays open: after a reload or a relog the list comes back
-- where it was. Asked only once the saved settings exist, and never in
-- combat (the rows are secure buttons).
local restoreFrame = CreateFrame("Frame")
restoreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
restoreFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(1, function()
        local db = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.kicksync
        if type(db) ~= "table" or db.keysShown ~= true then return end
        if listWindow and listWindow:IsShown() then return end
        if IsInRaid() then return end
        if InCombatLockdown() then
            listDirty = true
            return
        end
        KL:Initialize()
        KL:UpdateListUI()
        EnsureListUI():Show()
        KL:SyncNow()
    end)
end)

local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
    if listDirty then
        KL:UpdateListUI()
        if ApplyRaidVisibility then ApplyRaidVisibility() end
        -- A reload in combat left the list waiting to come back.
        local db = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.kicksync
        if type(db) == "table" and db.keysShown == true and listWindow and not listWindow:IsShown() and not IsInRaid() then
            KL:Initialize()
            listWindow:Show()
        end
    end
end)

-- ── Chat Announcer ──────────────────────────────────────────────────────────

function KL:AnnounceToChat()
    local own = GetOwnKeystone()
    if own then partyKeys[own.name] = own end

    local entries = {}
    for name, data in pairs(partyKeys) do
        entries[#entries + 1] = string.format("%s: +%d %s", name, data.level or 0, data.dungeon or "M+")
    end

    if #entries == 0 then
        print(L["|cff9d5db8MythicLooter:|r no keystones found in the group."])
        return
    end

    local chatTarget = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    local out = L["Keys: "] .. table.concat(entries, " | ")
    if chatTarget then
        SendChatMessage(out, chatTarget)
    else
        print(L["|cff9d5db8MythicLooter|r (only you see this, you are not in a group): "] .. out)
    end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function KL:Initialize()
    if isRegistered then return end
    isRegistered = true

    pcall(C_ChatInfo.RegisterAddonMessagePrefix, CHAT_PREFIX)

    local f = CreateFrame("Frame")
    HookLibraries()
    wasInGroup = IsInGroup()

    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("CHAT_MSG_PARTY")
    f:RegisterEvent("CHAT_MSG_PARTY_LEADER")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("CHALLENGE_MODE_START")

    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
            local text, sender = ...
            pcall(OnPartyChat, text, sender)
        elseif event == "GROUP_ROSTER_UPDATE" then
            if not rosterQueued then
                rosterQueued = true
                C_Timer.After(1, OnRosterSettled)
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            -- Only sends when the key itself changed (new key, reroll, depleted).
            BroadcastOwnKey(false)
        elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_START" then
            -- The key changes level a moment after either.
            C_Timer.After(2, function() BroadcastOwnKey(false); RefreshShown() end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, function()
                BroadcastOwnKey(true)
                RequestKeys()
            end)
        end
    end)

    -- Already in a party when this starts (a reload, or the module switched
    -- on mid-group): ask now rather than at the next roster change.
    if IsInGroup() then
        C_Timer.After(2, function()
            BroadcastOwnKey(true)
            RequestKeys()
        end)
    end
end

-- Nothing starts at load: KickSync calls Initialize from OnEnable, and
-- ToggleWindow calls it when the player opens the list.

-- ── Commands ────────────────────────────────────────────────────────────────
-- The same commands the KickSync module had, kept for the players who type
-- them: /kskeys opens the list, /kskey announces.
SLASH_OXEDHUBKEYSTONES1 = "/kskeys"
SlashCmdList.OXEDHUBKEYSTONES = function() KL:ToggleWindow() end
SLASH_OXEDHUBKEYANNOUNCE1 = "/kskey"
SlashCmdList.OXEDHUBKEYANNOUNCE = function() KL:AnnounceToChat() end
