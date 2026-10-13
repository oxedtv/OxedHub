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
        dungeon = name or "Unknown",
        name    = UnitName("player"),
    }
end

local function BroadcastOwnKey()
    if not IsInGroup() then return end
    local own = GetOwnKeystone()
    if not own then return end

    partyKeys[own.name] = own

    -- Format: WA-KeyStGrList protocol: "mapID:level:rating:dungeonScore"
    local channel = IsInRaid() and "RAID" or "PARTY"
    local msg = string.format("%d:%d:0:0", own.mapID, own.level)
    pcall(C_ChatInfo.SendAddOnMessage, CHAT_PREFIX, msg, channel)
end

-- ── Network Receiver ────────────────────────────────────────────────────────

local function OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= CHAT_PREFIX or not msg or not sender then return end

    local name = Ambiguate(sender, "none")
    local mapID, level = msg:match("^(%d+):(%d+)")
    mapID = tonumber(mapID)
    level = tonumber(level)

    if mapID and mapID > 0 and level and level > 0 then
        local dungeon = C_ChallengeMode.GetMapUIInfo(mapID) or "M+"
        local _, class = UnitClass(name)
        partyKeys[name] = {
            mapID   = mapID,
            level   = level,
            class   = class or "PRIEST",
            dungeon = dungeon,
            name    = name,
        }
        if listWindow and listWindow:IsShown() then
            KL:UpdateListUI()
        end
    end
end

-- ── UI Window ───────────────────────────────────────────────────────────────

local function EnsureListUI()
    if listWindow then return listWindow end

    local ok, w = pcall(CreateFrame, "Frame", "OxedHub_KickSyncKeysWindow", UIParent, "BasicFrameTemplate")
    if not ok or not w then
        w = CreateFrame("Frame", "OxedHub_KickSyncKeysWindow", UIParent, "BasicFrameTemplateWithInset")
    end
    w:SetSize(370, 280)
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:SetClampedToScreen(true)
    w:SetFrameStrata("DIALOG")
    w:SetFrameLevel(200)

    -- Window Title
    local titleText = w.TitleText
    if not titleText then
        titleText = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        titleText:SetPoint("CENTER", w.TitleBg or w, w.TitleBg and "CENTER" or "TOP", 0, w.TitleBg and 0 or -12)
        w.TitleText = titleText
    end
    titleText:SetText("Party Keystones")
    titleText:SetTextColor(1, 0.82, 0, 1)

    -- Close Button
    if w.CloseButton then
        w.CloseButton:SetScript("OnClick", function() w:Hide() end)
    end

    -- Empty status message
    local emptyLabel = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyLabel:SetPoint("CENTER", w, "CENTER", 0, 10)
    emptyLabel:SetText("No party keystones detected.\nClick 'Sync Keys' or invite party members.")
    emptyLabel:SetJustifyH("CENTER")
    w.emptyLabel = emptyLabel

    -- Bottom action buttons: Red OxedHub style
    local annBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    annBtn:SetSize(150, 24)
    annBtn:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 28, 12)
    annBtn:SetText("Announce to Party")
    annBtn:SetScript("OnClick", function() KL:AnnounceToChat() end)
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
        OxedHub.UI:ApplyRedButtonStyle(annBtn)
    elseif OxedHub.UIComponents and OxedHub.UIComponents.Button then
        OxedHub.UIComponents.Button.ApplyRedStyle(annBtn)
    end

    local syncBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    syncBtn:SetSize(120, 24)
    syncBtn:SetPoint("LEFT", annBtn, "RIGHT", 14, 0)
    syncBtn:SetText("Sync Keys")
    syncBtn:SetScript("OnClick", function()
        BroadcastOwnKey()
        KL:UpdateListUI()
    end)
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
        OxedHub.UI:ApplyRedButtonStyle(syncBtn)
    elseif OxedHub.UIComponents and OxedHub.UIComponents.Button then
        OxedHub.UIComponents.Button.ApplyRedStyle(syncBtn)
    end

    w.rows = {}
    listWindow = w
    return w
end

function KL:UpdateListUI()
    local w = EnsureListUI()
    local own = GetOwnKeystone()
    if own then partyKeys[own.name] = own end

    -- Re-order rows
    local entries = {}
    for name, data in pairs(partyKeys) do
        entries[#entries + 1] = data
    end
    table.sort(entries, function(a, b) return (a.level or 0) > (b.level or 0) end)

    if w.emptyLabel then
        w.emptyLabel:SetShown(#entries == 0)
    end

    for i = 1, 5 do
        local row = w.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, w)
            row:SetSize(342, 36)
            row:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -34 - (i - 1) * 38)

            local hl = row:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.05)
            hl:Hide()
            row.hl = hl

            local sep = row:CreateTexture(nil, "BORDER")
            sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            sep:SetHeight(1)
            sep:SetColorTexture(1, 1, 1, 0.08)
            row.sep = sep

            row:EnableMouse(true)
            row:SetScript("OnEnter", function() hl:Show() end)
            row:SetScript("OnLeave", function() hl:Hide() end)

            -- Level Text: clean font directly on row (no box)
            local lvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            lvlText:SetPoint("LEFT", row, "LEFT", 8, 0)
            lvlText:SetWidth(44)
            lvlText:SetJustifyH("LEFT")
            row.lvlText = lvlText

            -- Dungeon Name
            local dName = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            dName:SetPoint("TOPLEFT", lvlText, "TOPRIGHT", 4, 1)
            dName:SetWidth(240)
            dName:SetJustifyH("LEFT")
            dName:SetWordWrap(false)
            row.dName = dName

            -- Player Name (Class Colored)
            local pName = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            pName:SetPoint("BOTTOMLEFT", lvlText, "BOTTOMRIGHT", 4, 1)
            pName:SetWidth(240)
            pName:SetJustifyH("LEFT")
            pName:SetWordWrap(false)
            row.pName = pName

            -- Teleport Spell Button
            local portBtn = CreateFrame("Button", nil, row)
            portBtn:SetSize(26, 26)
            portBtn:SetPoint("RIGHT", row, "RIGHT", -6, 0)

            local icon = portBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportIronforge")
            portBtn.icon = icon

            local hlIcon = portBtn:CreateTexture(nil, "HIGHLIGHT")
            hlIcon:SetAllPoints()
            hlIcon:SetColorTexture(1, 1, 1, 0.3)
            portBtn:SetHighlightTexture(hlIcon)

            portBtn:SetScript("OnClick", function(self)
                if self.spellID then
                    CastSpellByID(self.spellID)
                end
            end)
            portBtn:SetScript("OnEnter", function(self)
                if self.spellID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(self.spellID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffffd100Click to cast dungeon teleport|r", 0.9, 0.9, 0.9)
                    GameTooltip:Show()
                end
            end)
            portBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.portBtn = portBtn

            w.rows[i] = row
        end

        local item = entries[i]
        if item then
            local lvl = item.level or 0
            row.lvlText:SetText(string.format("|cffffd100+%d|r", lvl))
            row.dName:SetText(string.format("|cffffffff%s|r", item.dungeon or "Mythic+"))

            local cHex = "ffffff"
            if item.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class] then
                cHex = RAID_CLASS_COLORS[item.class].colorStr or "ffffff"
            end
            row.pName:SetText(string.format("|c%s%s|r", cHex, item.name or "Unknown"))

            local info = DUNGEON_INFO[item.mapID]
            if info and info.port then
                row.portBtn.spellID = info.port
                local spellTex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(info.port)) or (GetSpellTexture and GetSpellTexture(info.port))
                row.portBtn.icon:SetTexture(spellTex or "Interface\\Icons\\Spell_Arcane_TeleportIronforge")
                row.portBtn:Show()
            else
                row.portBtn.spellID = nil
                row.portBtn:Hide()
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

function KL:ToggleWindow()
    local w = EnsureListUI()
    if w:IsShown() then
        w:Hide()
    else
        BroadcastOwnKey()
        KL:UpdateListUI()
        w:Show()
    end
end

-- ── Chat Announcer ──────────────────────────────────────────────────────────

function KL:AnnounceToChat()
    local own = GetOwnKeystone()
    if own then partyKeys[own.name] = own end

    local entries = {}
    for name, data in pairs(partyKeys) do
        entries[#entries + 1] = string.format("%s: +%d %s", name, data.level or 0, data.dungeon or "M+")
    end

    if #entries == 0 then
        print("|cff0091edKickSync:|r No keystones found in group.")
        return
    end

    local chatTarget = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    local out = "Keys: " .. table.concat(entries, " | ")
    if chatTarget then
        SendChatMessage(out, chatTarget)
    else
        print("|cff0091edKickSync Keys:|r " .. out)
    end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

function KL:Initialize()
    if isRegistered then return end
    isRegistered = true

    pcall(C_ChatInfo.RegisterAddonMessagePrefix, CHAT_PREFIX)

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")

    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            OnAddonMessage(...)
        elseif event == "BAG_UPDATE_DELAYED" or event == "GROUP_ROSTER_UPDATE" then
            BroadcastOwnKey()
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(2, BroadcastOwnKey)
        end
    end)
end

C_Timer.After(1, function() KL:Initialize() end)
