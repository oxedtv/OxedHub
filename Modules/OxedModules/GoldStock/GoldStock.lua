-- ============================================================================
-- Gold Stock
-- How much gold the account has, everywhere: every character's bags and mail,
-- each guild bank one of them has opened, and the warband bank. A window with
-- three views (characters, realms, guilds), totals, a filter, and an export
-- as CSV or JSON to copy out.
--
-- Its own module since it left Gold World Quests; nothing is read or saved
-- while it is off. Data lives in OxedHubDB.modules.goldstock:
--   stock.chars["Name-Realm"]  = { name, realm, class, faction, copper, bank, mail, guild, at }
--   stock.guilds["Guild-Realm"] = { name, realm, copper, at, by, skip }
--   stock.warband              = { copper, at }
-- (tables made here, never in DEFAULTS: they would be shared by reference).
--
-- ⚠ A guild bank's gold is only known while its window is open, and mail's
-- while a mailbox is; what the window shows is the last time someone on this
-- account looked.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local GoldStock = {}
OxedHub.GoldStock = GoldStock

local PREFIX = "|cffffd100Gold Stock:|r "

local DEFAULTS = {
    enabled               = false,  -- off until the player enables it (OxedHub standard)
    stockWarbandInTotal   = true,   -- the warband bank counts toward the total
    stockCombineFactions  = false,  -- Realms view: one line per realm, not per faction
    stockRoundDown        = true,   -- export whole gold
    stockMinGold          = 0,      -- hide characters with less gold than this
    minimapButton         = true,
}

local settings          -- OxedHubDB.modules.goldstock, bound at login
local running = false
local myKey             -- "Name-Realm", read once out of combat
local window, exportWindow, optionsWindow
local minimapIcon, MinimapIcon

local events = CreateFrame("Frame")

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

local function Realm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not Plain(realm) then realm = (GetRealmName() or ""):gsub("[%s%-]", "") end
    return realm
end

local function Coins(copper, roundGold)
    copper = math.max(0, math.floor(copper or 0))
    if roundGold then copper = math.floor(copper / 10000) * 10000 end
    local fn = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
    if fn then
        local ok, text = pcall(fn, copper)
        if ok and type(text) == "string" then return text end
    end
    return (BreakUpLargeNumbers or tostring)(math.floor(copper / 10000)) .. "g"
end

-- For a column that is usually empty: a row of zero coins hides the ones that matter.
local function CoinsOrDash(copper)
    if (copper or 0) < 10000 then return "|cff777777-|r" end
    return Coins(copper, true)
end

-- Everything one character holds.
local function CharGold(c)
    return (c.copper or 0) + (c.bank or 0) + (c.mail or 0)
end

local function Ago(t)
    if not t then return "never" end
    local d = time() - t
    if d < 3600 then return (L["%dm ago"]):format(math.max(1, math.floor(d / 60))) end
    if d < 86400 then return (L["%dh ago"]):format(math.floor(d / 3600)) end
    return (L["%dd ago"]):format(math.floor(d / 86400))
end

local function Stock()
    settings.stock = type(settings.stock) == "table" and settings.stock or {}
    local s = settings.stock
    s.chars = type(s.chars) == "table" and s.chars or {}
    s.guilds = type(s.guilds) == "table" and s.guilds or {}
    s.warband = type(s.warband) == "table" and s.warband or {}
    return s
end

-- ── Reading what we have ────────────────────────────────────────────────────

local function ReadMe()
    if not running then return end
    local s = Stock()
    if not myKey then
        if InCombatLockdown() then return end
        local name = Plain(UnitName("player"))
        if not name then return end
        myKey = name .. "-" .. Realm()
    end
    local me = s.chars[myKey]
    if type(me) ~= "table" then
        me = {}
        s.chars[myKey] = me
    end
    me.name, me.realm = myKey:match("^(.-)%-(.+)$")
    local money = GetMoney and GetMoney()
    if type(money) == "number" and not IsSecret(money) then me.copper = money end
    -- A character's own bank holds no gold today, only the warband and guild
    -- banks do. Asking the game rather than assuming means it gets counted if
    -- that ever changes.
    if C_Bank and C_Bank.DoesBankTypeSupportMoneyTransfer and C_Bank.FetchDepositedMoney
        and Enum and Enum.BankType and Enum.BankType.Character then
        local ok, holdsGold = pcall(C_Bank.DoesBankTypeSupportMoneyTransfer, Enum.BankType.Character)
        if ok and not IsSecret(holdsGold) and holdsGold then
            local read, copper = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Character)
            if read and type(copper) == "number" and not IsSecret(copper) then
                me.bank = copper > 0 and copper or nil
            end
        end
    end
    me.at = time()
    if not InCombatLockdown() then
        local _, class = UnitClass("player")
        if Plain(class) then me.class = class end
        local faction = UnitFactionGroup("player")
        if Plain(faction) then me.faction = faction end
        local guild, _, _, guildRealm = GetGuildInfo("player")
        if Plain(guild) then
            me.guild = guild .. "-" .. (Plain(guildRealm) and guildRealm:gsub("[%s%-]", "") or me.realm)
        elseif IsInGuild and not IsInGuild() then
            me.guild = nil
        end
    end
end

-- Soon after login a 0 can mean the game does not have the figure yet, and it
-- would wipe the amount we saved. So a 0 only replaces a saved amount when
-- `trusted`: the game just said the bank's money changed, or the bank is open.
local function ReadWarband(trusted)
    if not running or not (C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType) then return end
    local ok, copper = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    if ok and type(copper) == "number" and not IsSecret(copper) then
        local w = Stock().warband
        if copper == 0 and (w.copper or 0) > 0 and not trusted then return end
        w.copper, w.at = copper, time()
    end
end

local guildBankOpen = false
local function ReadGuildBank()
    if not running or not guildBankOpen or not GetGuildBankMoney then return end
    local copper = GetGuildBankMoney()
    local guild, _, _, guildRealm = GetGuildInfo("player")
    if type(copper) ~= "number" or IsSecret(copper) or not Plain(guild) then return end
    local realm = Plain(guildRealm) and guildRealm:gsub("[%s%-]", "") or Realm()
    local key = guild .. "-" .. realm
    local g = Stock().guilds[key]
    if type(g) ~= "table" then
        g = {}
        Stock().guilds[key] = g
    end
    g.name, g.realm, g.copper, g.at, g.by = guild, realm, copper, time(), myKey
end

-- Gold waiting in the mailbox. Read on MAIL_INBOX_UPDATE only: at MAIL_SHOW the
-- inbox has not arrived yet and would read as empty. The game hands over the
-- first 50 letters, so gold further down is not seen until those are cleared.
local mailOpen = false
local function ReadMail()
    if not running or not mailOpen or not myKey or not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local me = Stock().chars[myKey]
    if type(me) ~= "table" then return end
    local ok, shown = pcall(GetInboxNumItems)
    if not ok or type(shown) ~= "number" or IsSecret(shown) then return end
    local sum = 0
    for i = 1, shown do
        local read, _, _, _, _, money = pcall(GetInboxHeaderInfo, i)
        if not read then return end
        if type(money) == "number" and not IsSecret(money) then sum = sum + money end
    end
    me.mail = sum > 0 and sum or nil
end

-- ── Gold mailed to your own characters ──────────────────────────────────────
-- It leaves the sender's bags at once but the other character cannot read its
-- mailbox until it logs in, so it would drop out of the total. Added to that
-- character's mail figure instead, which ReadMail replaces with the real sum
-- the next time it opens a mailbox.
--
-- The amount comes from SetSendMailMoney because the game resets it once
-- SendMail has run. One letter at a time, not a queue: a send cancelled at the
-- game's confirmation may never report back, and a queue would then pay the
-- next letter's success to the wrong character.
local moneyToSend = 0
local sending        -- { to, copper } between SendMail and the game's answer
local mailHooked = false

local function OwnCharacter(recipient)
    if type(recipient) ~= "string" or IsSecret(recipient) then return nil end
    local name, realm = recipient:match("^%s*([^%-%s]+)%-?(.-)%s*$")
    if not name then return nil end
    realm = realm ~= "" and realm:gsub("[%s%-]", "") or Realm()
    local chars = Stock().chars
    local exact = chars[name .. "-" .. realm]
    if type(exact) == "table" then return exact end
    name, realm = name:lower(), realm:lower()
    for _, c in pairs(chars) do
        if type(c) == "table" and c.name and c.realm
            and c.name:lower() == name and c.realm:lower() == realm then
            return c
        end
    end
    return nil
end

local function HookMail()
    if mailHooked or not (hooksecurefunc and SendMail and SetSendMailMoney) then return end
    mailHooked = true
    hooksecurefunc("SetSendMailMoney", function(copper)
        -- What the game accepted, when it says; it refuses what you cannot afford.
        local held = GetSendMailMoney and GetSendMailMoney()
        if type(held) == "number" and not IsSecret(held) then copper = held end
        moneyToSend = (type(copper) == "number" and not IsSecret(copper)) and copper or 0
    end)
    hooksecurefunc("SendMail", function(recipient)
        sending = (running and moneyToSend > 0) and { to = recipient, copper = moneyToSend } or nil
        moneyToSend = 0
    end)
end

local function MailDelivered()
    local letter = sending
    sending = nil
    if not (running and letter) then return end
    local c = OwnCharacter(letter.to)
    if c then c.mail = (c.mail or 0) + letter.copper end
end

-- ── Putting it together ─────────────────────────────────────────────────────

local function Matches(text, ...)
    if not text or text == "" then return true end
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v:lower():find(text, 1, true) then return true end
    end
    return false
end

local function Filter()
    local text = window and window.search and window.search:GetText() or ""
    return (text:lower():gsub("^%s+", ""):gsub("%s+$", "")), (tonumber(settings.stockMinGold) or 0) * 10000
end

local function CharacterRows()
    local text, min = Filter()
    local list = {}
    for key, c in pairs(Stock().chars) do
        if type(c) == "table" and CharGold(c) >= min and Matches(text, c.name, c.realm, c.guild) then
            list[#list + 1] = { key = key, c = c }
        end
    end
    return list
end

local function GuildRows()
    local text = Filter()
    local list = {}
    for key, g in pairs(Stock().guilds) do
        if type(g) == "table" and Matches(text, g.name, g.realm) then
            list[#list + 1] = { key = key, g = g }
        end
    end
    return list
end

-- Realm (and faction, unless combined) -> characters, purses, guild banks.
local function RealmRows()
    local text, min = Filter()
    local combine = settings.stockCombineFactions
    local byKey, list = {}, {}
    local function Entry(realm, faction)
        local key = combine and realm or (realm .. "|" .. (faction or "Neutral"))
        local e = byKey[key]
        if not e then
            e = { realm = realm, faction = (not combine) and (faction or "Neutral") or nil, chars = 0, personal = 0, guild = 0 }
            byKey[key] = e
            list[#list + 1] = e
        end
        return e
    end
    local guildFaction = {}
    for _, c in pairs(Stock().chars) do
        if type(c) == "table" and c.realm and CharGold(c) >= min and Matches(text, c.name, c.realm, c.guild) then
            local e = Entry(c.realm, c.faction)
            e.chars = e.chars + 1
            e.personal = e.personal + CharGold(c)
            if c.guild then guildFaction[c.guild] = c.faction end
        end
    end
    for key, g in pairs(Stock().guilds) do
        if type(g) == "table" and not g.skip and g.realm and Matches(text, g.name, g.realm) then
            local e = Entry(g.realm, guildFaction[key])
            e.guild = e.guild + (g.copper or 0)
        end
    end
    return list
end

local function Totals()
    local bags, bank, mail, guild = 0, 0, 0, 0
    for _, c in pairs(Stock().chars) do
        if type(c) == "table" then
            bags = bags + (c.copper or 0)
            bank = bank + (c.bank or 0)
            mail = mail + (c.mail or 0)
        end
    end
    for _, g in pairs(Stock().guilds) do
        if type(g) == "table" and not g.skip then guild = guild + (g.copper or 0) end
    end
    local warband = Stock().warband.copper or 0
    local total = bags + bank + mail + guild + (settings.stockWarbandInTotal ~= false and warband or 0)
    return bags, bank, mail, guild, warband, total
end

-- ── The window ──────────────────────────────────────────────────────────────

local ROW_H = 18
local TABS = {
    { key = "chars",  label = "Characters" },
    { key = "realms", label = "Realms" },
    { key = "guilds", label = "Guilds" },
}
OxedHub:RegisterLocalizedTable(TABS, "label")

-- Columns per view: label, width, the value to sort by, the text shown.
local FACTION_COLOUR = { Alliance = "ff4a8cff", Horde = "ffff3030", Neutral = "ffcccccc" }

local function ClassName(c)
    local colour = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
    return ("|c%s%s|r"):format(colour and colour.colorStr or "ffffffff", c.name or "?")
end

local function FactionText(f)
    if not f then return "" end
    return ("|c%s%s|r"):format(FACTION_COLOUR[f] or "ffcccccc", f)
end

local COLUMNS = {
    chars = {
        { label = "Name",    width = 110, sort = function(r) return r.c.name or "" end, text = function(r) return ClassName(r.c) end },
        { label = "Realm",   width = 95,  sort = function(r) return r.c.realm or "" end, text = function(r) return r.c.realm or "" end },
        { label = "Faction", width = 60,  sort = function(r) return r.c.faction or "" end, text = function(r) return FactionText(r.c.faction) end },
        { label = "Bags",    width = 115, sort = function(r) return r.c.copper or 0 end, text = function(r) return Coins(r.c.copper, true) end, right = true },
        { label = "Mail",    width = 80,  sort = function(r) return r.c.mail or 0 end, text = function(r) return CoinsOrDash(r.c.mail) end, right = true },
        { label = "Total",   width = 115, sort = function(r) return CharGold(r.c) end, text = function(r) return Coins(CharGold(r.c), true) end, right = true },
        { label = "Guild",   width = 85,  sort = function(r) return r.c.guild or "" end, text = function(r) return (r.c.guild or ""):match("^(.-)%-[^%-]+$") or "" end },
        { label = "Updated", width = 65,  sort = function(r) return r.c.at or 0 end, text = function(r) return "|cff9d9d9d" .. Ago(r.c.at) .. "|r" end },
    },
    realms = {
        { label = "Realm",      width = 140, sort = function(r) return r.realm end, text = function(r) return r.realm end },
        { label = "Faction",    width = 70,  sort = function(r) return r.faction or "" end, text = function(r) return r.faction and FactionText(r.faction) or "|cff9d9d9dall|r" end },
        { label = "Chars",      width = 45,  sort = function(r) return r.chars end, text = function(r) return tostring(r.chars) end, right = true },
        { label = "Characters", width = 130, sort = function(r) return r.personal end, text = function(r) return Coins(r.personal, true) end, right = true },
        { label = "Guild banks", width = 120, sort = function(r) return r.guild end, text = function(r) return Coins(r.guild, true) end, right = true },
        { label = "Total",      width = 130, sort = function(r) return r.personal + r.guild end, text = function(r) return Coins(r.personal + r.guild, true) end, right = true },
    },
    guilds = {
        { label = "Guild",   width = 150, sort = function(r) return r.g.name or "" end, text = function(r) return (r.g.skip and "|cff777777" or "|cff40ff40") .. (r.g.name or "?") .. "|r" end },
        { label = "Realm",   width = 115, sort = function(r) return r.g.realm or "" end, text = function(r) return r.g.realm or "" end },
        { label = "Bank",    width = 140, sort = function(r) return r.g.copper or 0 end, text = function(r) return Coins(r.g.copper, true) end, right = true },
        { label = "Seen by", width = 110, sort = function(r) return r.g.by or "" end, text = function(r) return (r.g.by or ""):match("^[^%-]+") or "" end },
        { label = "Updated", width = 70,  sort = function(r) return r.g.at or 0 end, text = function(r) return "|cff9d9d9d" .. Ago(r.g.at) .. "|r" end },
    },
}
for _, columns in pairs(COLUMNS) do OxedHub:RegisterLocalizedTable(columns, "label") end

local Refresh

-- Its own box over the window: the game's popup shares the window's DIALOG
-- strata and ended up hidden behind it, so the x looked like it did nothing.
local confirmBox

local function ConfirmDelete(key)
    if not confirmBox then
        local f = CreateFrame("Frame", nil, window, "BackdropTemplate")
        f:SetSize(300, 96)
        f:SetPoint("CENTER", window, "CENTER", 0, 0)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        if f.SetBackdrop then
            f:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24,
                insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("TOPLEFT", 16, -18)
        f.text:SetPoint("TOPRIGHT", -16, -18)
        local yes = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        yes:SetSize(100, 22)
        yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
        yes:SetText(DELETE or L["Delete"])
        yes:SetScript("OnClick", function()
            local k = f.key
            f:Hide()
            if not k then return end
            Stock().chars[k] = nil
            print(PREFIX .. (L["forgot %s."]):format(k))
            Refresh()
        end)
        local no = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        no:SetSize(100, 22)
        no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
        no:SetText(CANCEL or L["Cancel"])
        no:SetScript("OnClick", function() f:Hide() end)
        f:SetScript("OnHide", function(self) self.key = nil end)
        f:Hide()
        confirmBox = f
    end
    confirmBox.key = key
    confirmBox.text:SetText((L["Forget %s and its gold?"]):format(key))
    confirmBox:Show()
end

local function GetRow(i)
    local rows = window.rows
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, window.content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetAllPoints()
    stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.cells = {}
    row.action = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.action:SetSize(22, 16)
    row.action:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    rows[i] = row
    return row
end

local function Cell(row, i)
    local fs = row.cells[i]
    if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetWordWrap(false)
        row.cells[i] = fs
    end
    return fs
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    local tab = window.tab
    for _, b in ipairs(window.tabButtons) do
        if b.key == tab then b:LockHighlight() else b:UnlockHighlight() end
    end

    local list = tab == "realms" and RealmRows() or tab == "guilds" and GuildRows() or CharacterRows()
    local cols = COLUMNS[tab]
    local sortIndex = window.sort[tab] or (tab == "chars" and 6 or tab == "realms" and 6 or 3)
    local desc = window.desc[tab]
    if desc == nil then desc = true end
    local key = cols[sortIndex] and cols[sortIndex].sort
    if key then
        table.sort(list, function(a, b)
            local x, y = key(a), key(b)
            if x == y then return false end
            if desc then return x > y end
            return x < y
        end)
    end

    -- Headers.
    local x = 6
    for i, col in ipairs(cols) do
        local h = window.headers[i]
        if not h then
            h = CreateFrame("Button", nil, window)
            h:SetHeight(18)
            h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            h.text:SetAllPoints()
            h:SetScript("OnClick", function(self)
                local t = window.tab
                if window.sort[t] == self.index then
                    window.desc[t] = not (window.desc[t] ~= false)
                else
                    window.sort[t], window.desc[t] = self.index, true
                end
                Refresh()
            end)
            window.headers[i] = h
        end
        h.index = i
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", window.content:GetParent(), "TOPLEFT", x, 20)
        h:SetWidth(col.width - 6)
        h.text:SetJustifyH(col.right and "RIGHT" or "LEFT")
        local arrow = (i == sortIndex) and (desc and " v" or " ^") or ""
        h.text:SetText(col.label .. arrow)
        h:Show()
        x = x + col.width
    end
    for i = #cols + 1, #window.headers do window.headers[i]:Hide() end

    -- Rows.
    for i, r in ipairs(list) do
        local row = GetRow(i)
        local cx = 6
        for c, col in ipairs(cols) do
            local fs = Cell(row, c)
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", row, "LEFT", cx, 0)
            fs:SetWidth(col.width - 6)
            fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
            fs:SetText(col.text(r))
            fs:Show()
            cx = cx + col.width
        end
        for c = #cols + 1, #row.cells do row.cells[c]:Hide() end

        row.action:Show()
        if tab == "chars" then
            row.action:SetText("x")
            row.action:SetScript("OnClick", function() ConfirmDelete(r.key) end)
            row.action:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["Forget this character"])
                GameTooltip:Show()
            end)
        elseif tab == "guilds" then
            row.action:SetText(r.g.skip and "+" or "-")
            row.action:SetScript("OnClick", function()
                r.g.skip = (not r.g.skip) or nil
                Refresh()
            end)
            row.action:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(r.g.skip and L["Count this guild bank again"] or L["Leave this guild bank out of the totals"])
                GameTooltip:Show()
            end)
        else
            row.action:Hide()
        end
        row.action:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Show()
    end
    for i = #list + 1, #window.rows do window.rows[i]:Hide() end
    window.content:SetHeight(math.max(1, #list * ROW_H))
    window.empty:SetShown(#list == 0)

    local bags, bank, mail, guild, warband, total = Totals()
    window.totals:SetText((L["|cffffd100Bags|r %s%s    |cffffd100Mail|r %s    |cffffd100Guild banks|r %s    |cffffd100Warband bank|r %s%s\n|cffffd100Total|r %s"])
        :format(Coins(bags, true), bank > 0 and ("    |cffffd100" .. L["Bank"] .. "|r " .. Coins(bank, true)) or "",
            Coins(mail, true), Coins(guild, true), Coins(warband, true),
            settings.stockWarbandInTotal ~= false and "" or L[" |cff9d9d9d(not in total)|r"], Coins(total, true)))
end

-- ── Export ──────────────────────────────────────────────────────────────────

local function Gold(copper)
    local g = (copper or 0) / 10000
    if settings.stockRoundDown ~= false then return tostring(math.floor(g)) end
    return ("%.4f"):format(g)
end

local function CSVField(v)
    v = tostring(v or "")
    if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

local function JSONString(v)
    v = tostring(v or ""):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n")
    return '"' .. v .. '"'
end

-- Characters richest first, then the guild banks counted in the totals, then
-- the warband bank. The search applies; the warband bank has no name to match,
-- so it is left out while one is typed.
local function ExportRows()
    local rows = {}
    local list = CharacterRows()
    table.sort(list, function(a, b) return CharGold(a.c) > CharGold(b.c) end)
    for _, r in ipairs(list) do
        local c = r.c
        rows[#rows + 1] = { type = "character", name = c.name, realm = c.realm, faction = c.faction,
            bags = c.copper, bank = c.bank, mail = c.mail, gold = CharGold(c), guild = c.guild, at = c.at }
    end
    for _, r in ipairs(GuildRows()) do
        if not r.g.skip then
            rows[#rows + 1] = { type = "guild", name = r.g.name, realm = r.g.realm, gold = r.g.copper, at = r.g.at }
        end
    end
    local w = Stock().warband
    if w.copper and Filter() == "" then
        rows[#rows + 1] = { type = "warband", name = "Warband bank", gold = w.copper, at = w.at }
    end
    return rows
end

local function ExportText(kind)
    local rows = ExportRows()
    local out = {}
    if kind == "json" then
        out[1] = "["
        for i, r in ipairs(rows) do
            out[#out + 1] = ('  {"type":%s,"name":%s,"realm":%s,"faction":%s,"bags":%s,"bank":%s,"mail":%s,"gold":%s,"guild":%s,"updated":%d}%s'):format(
                JSONString(r.type), JSONString(r.name), JSONString(r.realm), JSONString(r.faction),
                Gold(r.bags), Gold(r.bank), Gold(r.mail), Gold(r.gold),
                JSONString(r.guild), r.at or 0, i < #rows and "," or "")
        end
        out[#out + 1] = "]"
    else
        out[1] = "Type,Name,Realm,Faction,Bags,Bank,Mail,Gold,Guild,Updated"
        for _, r in ipairs(rows) do
            out[#out + 1] = table.concat({ r.type, CSVField(r.name), CSVField(r.realm), CSVField(r.faction),
                Gold(r.bags), Gold(r.bank), Gold(r.mail), Gold(r.gold), CSVField(r.guild),
                r.at and date("%Y-%m-%d %H:%M", r.at) or "" }, ",")
        end
    end
    return table.concat(out, "\n")
end

local function ShowExport(kind)
    if not exportWindow then
        local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplate")
        f:SetSize(560, 360)
        f:SetPoint("CENTER", 40, -20)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(220)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.TitleText then f.TitleText:SetText(L["Gold Stock export"]) end
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
        local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("TOPLEFT", 14, -30)
        hint:SetText(L["Ctrl+A then Ctrl+C to copy."])
        local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 12, -46)
        scroll:SetPoint("BOTTOMRIGHT", -32, 12)
        local box = CreateFrame("EditBox", nil, scroll)
        box:SetAutoFocus(false)   -- never take the keyboard on its own
        box:SetMultiLine(true)
        box:SetFontObject("ChatFontNormal")
        box:SetWidth(500)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
        -- Read only: typing puts the export back.
        box:SetScript("OnTextChanged", function(self, user)
            if user and f.text then self:SetText(f.text) end
        end)
        scroll:SetScrollChild(box)
        f.box = box
        f:SetScript("OnHide", function() box:ClearFocus() end)
        exportWindow = f
    end
    exportWindow.text = ExportText(kind)
    exportWindow.box:SetText(exportWindow.text)
    exportWindow:Show()
    exportWindow.box:SetFocus()
    exportWindow.box:HighlightText()
end

-- ── Building the window ─────────────────────────────────────────────────────

local function MakeButton(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function BuildWindow()
    if window then return end
    local f = CreateFrame("Frame", "OxedHubGoldStockWindow", UIParent, "BasicFrameTemplate")
    f:SetSize(800, 470)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(150)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if f.TitleText then f.TitleText:SetText("Gold Stock") end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    tinsert(UISpecialFrames, "OxedHubGoldStockWindow")   -- Escape closes it

    f.tab = "chars"
    f.sort, f.desc = {}, {}
    f.rows, f.headers, f.tabButtons = {}, {}, {}

    local prev
    for _, t in ipairs(TABS) do
        local b = MakeButton(f, t.label, 100, function()
            f.tab = t.key
            Refresh()
        end)
        b.key = t.key
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 12, -30) end
        f.tabButtons[#f.tabButtons + 1] = b
        prev = b
    end

    -- Filter: a name, realm or guild, and the least gold a character needs.
    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(130, 20)
    search:SetPoint("TOPRIGHT", -16, -31)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() Refresh() end)
    search:SetScript("OnEscapePressed", search.ClearFocus)
    search:SetScript("OnEnterPressed", search.ClearFocus)
    local searchHint = search:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", 4, 0)
    searchHint:SetText(L["Search"])
    search:HookScript("OnTextChanged", function(self) searchHint:SetShown(self:GetText() == "") end)
    f.search = search

    local list = CreateFrame("Frame", nil, f, "BackdropTemplate")
    list:SetPoint("TOPLEFT", 10, -84)
    list:SetPoint("BOTTOMRIGHT", -10, 96)
    list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    list:SetBackdropColor(0, 0, 0, 0.35)

    local scroll = CreateFrame("ScrollFrame", nil, list, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -2)
    scroll:SetPoint("BOTTOMRIGHT", -24, 2)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(740, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
    -- The addon's own bar, which also gives the wheel.
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    end
    f.content = content

    f.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(L["Nothing yet. Each character is counted when it logs in; a guild bank when it is opened."])

    f.totals = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.totals:SetPoint("BOTTOMLEFT", 14, 52)
    f.totals:SetPoint("RIGHT", -14, 0)
    f.totals:SetJustifyH("LEFT")

    -- Bottom row: options and export.
    local function Check(key, label, default, x)
        local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        box:SetSize(22, 22)
        box:SetPoint("BOTTOMLEFT", x, 14)
        box.text:SetFontObject("GameFontHighlightSmall")
        box.text:SetText(label)
        box:SetScript("OnShow", function(self)
            local v = settings[key]
            if v == nil then v = default end
            self:SetChecked(v and true or false)
        end)
        box:SetScript("OnClick", function(self)
            settings[key] = self:GetChecked() and true or false
            Refresh()
        end)
        return box
    end
    Check("stockWarbandInTotal", L["Warband bank in total"], true, 12)
    Check("stockCombineFactions", L["Realms: both factions together"], false, 170)
    Check("stockRoundDown", L["Export whole gold"], true, 370)

    local json = MakeButton(f, "JSON", 60, function() ShowExport("json") end)
    json:SetPoint("BOTTOMRIGHT", -12, 14)
    local csv = MakeButton(f, "CSV", 60, function() ShowExport("csv") end)
    csv:SetPoint("RIGHT", json, "LEFT", -6, 0)
    local exportLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    exportLabel:SetPoint("RIGHT", csv, "LEFT", -6, 0)
    exportLabel:SetText(L["Export"])

    -- The least gold a character needs to be listed.
    local minBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    minBox:SetSize(60, 20)
    minBox:SetPoint("RIGHT", search, "LEFT", -14, 0)
    minBox:SetAutoFocus(false)
    minBox:SetNumeric(true)
    minBox:SetScript("OnShow", function(self) self:SetText(tostring(tonumber(settings.stockMinGold) or 0)) end)
    minBox:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        settings.stockMinGold = tonumber(self:GetText()) or 0
        Refresh()
    end)
    minBox:SetScript("OnEnterPressed", minBox.ClearFocus)
    minBox:SetScript("OnEscapePressed", minBox.ClearFocus)
    local minLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minLabel:SetPoint("RIGHT", minBox, "LEFT", -8, 0)
    minLabel:SetText(L["At least (g)"])

    -- Back to the gold world quest tracker, on the left of the title bar
    -- where the tracker keeps its own minimise button.
    local tracker = MakeButton(f, L["Tracker"], 70, function()
        f:Hide()
        if OxedHub.GoldWQShowTracker then OxedHub.GoldWQShowTracker() end
    end)
    tracker:SetHeight(20)
    tracker:SetPoint("TOPLEFT", 6, -1)
    tracker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Gold World Quests")
        GameTooltip:AddLine(L["Back to the quest tracker."], 1, 1, 1)
        GameTooltip:Show()
    end)
    tracker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if OxedHub.UIComponents and OxedHub.UIComponents.Button and OxedHub.UIComponents.Button.ApplyRedStyle then
        pcall(OxedHub.UIComponents.Button.ApplyRedStyle, tracker)
    end

    -- Minimise, beside the close button: down to the tracker's gold coin,
    -- which stays on screen and opens the tracker again.
    local mini = MakeButton(f, "-", 30, function()
        f:Hide()
        if OxedHub.GoldWQMinimise then OxedHub.GoldWQMinimise() end
    end)
    mini:SetHeight(20)
    if f.CloseButton then
        mini:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
    else
        mini:SetPoint("TOPRIGHT", -30, -1)
    end
    local dash = mini:GetFontString()
    if dash then dash:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE"); dash:SetTextColor(1, 0.82, 0) end
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Minimise to a gold coin"])
        GameTooltip:AddLine(L["Click the coin to open the tracker again."], 1, 1, 1)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if OxedHub.UIComponents and OxedHub.UIComponents.Button and OxedHub.UIComponents.Button.ApplyRedStyle then
        pcall(OxedHub.UIComponents.Button.ApplyRedStyle, mini)
        if dash then dash:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE"); dash:SetTextColor(1, 0.82, 0) end
    end

    f:SetScript("OnShow", function()
        -- Both lead back to Gold World Quests, so only while that module is on.
        local trackerOn = OxedHub.ModuleAPI and OxedHub.ModuleAPI:IsModuleEnabled("goldwq") or false
        tracker:SetShown(trackerOn)
        mini:SetShown(trackerOn)
        ReadMe()
        ReadWarband()
        Refresh()
    end)
    window = f
end

-- ── Events, start and stop ──────────────────────────────────────────────────

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local guildBanker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
        if arg1 ~= guildBanker then return end
        guildBankOpen = event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW"
        if guildBankOpen then C_Timer.After(0.5, ReadGuildBank) end
        return
    end
    if event == "GUILDBANK_UPDATE_MONEY" or event == "GUILDBANKFRAME_OPENED" then
        if event == "GUILDBANKFRAME_OPENED" then guildBankOpen = true end
        ReadGuildBank()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        guildBankOpen = false
    elseif event == "ACCOUNT_MONEY" or event == "BANKFRAME_OPENED" then
        ReadWarband(true)
    elseif event == "MAIL_SHOW" then
        mailOpen = true
        sending = nil
        ReadMe()   -- makes sure this character has its row and key before the inbox arrives
    elseif event == "MAIL_CLOSED" then
        mailOpen = false
    elseif event == "MAIL_INBOX_UPDATE" then
        ReadMail()
    elseif event == "MAIL_SEND_SUCCESS" then
        MailDelivered()
    elseif event == "MAIL_FAILED" or event == "SECURE_TRANSFER_CANCEL" then
        sending = nil
    else
        ReadMe()
    end
    if window and window:IsShown() then Refresh() end
end)

local EVENTS = {
    "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "PLAYER_GUILD_UPDATE", "PLAYER_REGEN_ENABLED",
    "ACCOUNT_MONEY", "BANKFRAME_OPENED", "GUILDBANK_UPDATE_MONEY", "GUILDBANKFRAME_OPENED", "GUILDBANKFRAME_CLOSED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
    "MAIL_SEND_SUCCESS", "MAIL_FAILED", "SECURE_TRANSFER_CANCEL",
}

function GoldStock:Start(config)
    settings = config
    if running then return end
    running = true
    Stock()
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    HookMail()
    C_Timer.After(2, function()
        ReadMe()
        ReadWarband()
    end)
end

function GoldStock:Stop()
    running = false
    mailOpen, guildBankOpen = false, false
    sending = nil
    events:UnregisterAllEvents()
    if window then window:Hide() end
    if exportWindow then exportWindow:Hide() end
end

function GoldStock:IsRunning()
    return running
end

local function SayOff()
    print(PREFIX .. L["switched off. Turn it on in |cffffd100/ohub|r > Modules."])
end

function GoldStock:Show()
    if not running then return SayOff() end
    BuildWindow()
    window:Show()
    window:Raise()
end

function GoldStock:Toggle()
    if not running then return SayOff() end
    BuildWindow()
    window:SetShown(not window:IsShown())
end

-- One line per character plus the totals, for /goldstock list in chat.
function GoldStock:PrintSummary()
    if not running then return SayOff() end
    ReadMe()
    ReadWarband()
    local list = CharacterRows()
    table.sort(list, function(a, b) return CharGold(a.c) > CharGold(b.c) end)
    print(PREFIX .. L["gold on this account:"])
    for _, r in ipairs(list) do
        print(("   %s-%s  %s"):format(ClassName(r.c), r.c.realm or "?", Coins(CharGold(r.c), true)))
    end
    local bags, bank, mail, guild, warband, total = Totals()
    print((L["   Bags %s%s, mail %s, guild banks %s, warband bank %s. |cffffd100Total %s|r"])
        :format(Coins(bags, true), bank > 0 and (L[", bank %s"]):format(Coins(bank, true)) or "",
            Coins(mail, true), Coins(guild, true), Coins(warband, true), Coins(total, true)))
end

-- The amount for a tooltip line (the minimap button).
function GoldStock:Total()
    if not settings then return 0 end
    local _, _, _, _, _, total = Totals()
    return total
end

-- ── Options ─────────────────────────────────────────────────────────────────
-- The window's own tick boxes stay in the window, beside what they change.

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Gold Stock", 460, 360)
        optionsWindow = w

        local open = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        open:SetSize(170, 24)
        open:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        open:SetText(L["Open Gold Stock"])
        open:SetScript("OnClick", function()
            w:Hide()
            GoldStock:Show()
        end)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(open) end
        local cmd = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cmd:SetPoint("LEFT", open, "RIGHT", 10, 0)
        cmd:SetText(L["or type /goldstock"])
        w.cursorY = w.cursorY - 36

        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        w:AddNote("Bags: counted each time a character logs in. Mail: counted when that character opens a mailbox, and gold you mail to your own characters counts as soon as it is sent.")
        w:AddNote("Guild banks: counted when one of your characters opens the bank, so the figure is from the last visit. The warband bank is read wherever you are.")
        w:AddNote("A character's own bank cannot hold gold. The game keeps banked gold only in the warband and guild banks.")
        w:AddNote("/goldstock list prints it all in chat.")
        w:AddModuleLinks("Works together with", { "goldwq" })
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "goldstock", label = L["Gold Stock"], icon = "Interface\\Icons\\INV_Misc_Coin_01", config = settings,
        hint = L["Click: the window. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else GoldStock:Toggle() end
        end,
    })
    return minimapIcon
end

SLASH_OXEDGOLDSTOCK1 = "/goldstock"
SLASH_OXEDGOLDSTOCK2 = "/oxstock"
SlashCmdList["OXEDGOLDSTOCK"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "list" then
        GoldStock:PrintSummary()
    elseif msg == "options" or msg == "config" then
        ShowOptions()
    else
        GoldStock:Toggle()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

-- Up to 2.4.51 all of this lived in Gold World Quests' settings. Moved across
-- once, so nobody loses the characters they have gathered. A player who was
-- using it stays switched on: it did not ask to be turned on, it merely moved.
local MOVED_KEYS = { "stock", "stockWarbandInTotal", "stockCombineFactions", "stockRoundDown", "stockMinGold" }

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.goldstock
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.goldstock = config
    end
    local old = OxedHubDB.modules.goldwq
    if not config.movedFromGoldWQ then
        config.movedFromGoldWQ = true
        if type(old) == "table" then
            local inUse = old.enabled == true and type(old.stock) == "table"
                and type(old.stock.chars) == "table" and next(old.stock.chars) ~= nil
            for _, key in ipairs(MOVED_KEYS) do
                if config[key] == nil then config[key] = old[key] end
                old[key] = nil
            end
            if inUse then
                config.enabled, config.playerSet, config.defaultOffSeen = true, true, true
            end
        end
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "goldstock",
        name     = "Gold Stock",
        version  = "1.0.2",
        updated  = 20261102.9,  -- gold mailed to your own characters stays counted; warband bank keeps its figure at login
        author   = "Oxed",
        category = "items",
        keywords = { "gold", "money", "stock", "alts", "guild bank", "warband", "bank", "mail", "export" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Gold on all your characters: bags, mail, guild banks and the warband bank. /goldstock",
        icon     = "Interface\\Icons\\INV_Misc_Coin_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,
        -- On the minimap button's right-click menu and as an Action Hub node.
        quick = {
            { text = L["Show or hide"], func = function() GoldStock:Toggle() end },
        },

        OnEnable = function(_, config)
            GoldStock:Start(config)
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end,

        OnDisable = function()
            GoldStock:Stop()
            if minimapIcon then minimapIcon:Apply(false) end
        end,
    })
end)
