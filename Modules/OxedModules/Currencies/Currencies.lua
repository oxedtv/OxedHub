-- ============================================================================
-- Currencies (built-in OxedHub module)
-- Every currency in one list, for the whole account, grouped the way the
-- game's own currency tab groups them (Legion, Shadowlands, ...). Each
-- character's amounts are remembered as it logs in, so any character can see
-- who holds how much of something -- and the total across all of them --
-- without logging over. Built the same way as Reputations.
--
-- ⚠ The game only lists the currencies under headers the player has opened in
-- the currency tab. To learn them all, every closed header is opened once,
-- the list read, and exactly those headers closed again -- the player's tab
-- looks as it did. After that each currency is read by its id, which needs no
-- header open. The opening is never done while the tab is on screen.
--
-- ⚠ Reads are done out of combat only, at most once a second: the currency
-- event arrives in streams while looting, and each read asks the game for one
-- table per currency.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    minimapButton = true,   -- its own icon on the minimap while switched on

    hideEmpty   = true,     -- hide currencies nobody has any of
    showOthers  = true,     -- the total across characters on each row
    capAlert    = true,     -- a line in chat when a currency reaches its cap
    goalSound   = "",       -- an OxedHub sound when a goal is reached; empty plays nothing
    altTooltip  = true,     -- every character's amount in the game's currency tooltips
    trackLocked = false,    -- the bar on screen can be dragged until locked
    trackScale  = 1,
    trackVertical = false,
    trackPoint = "CENTER", trackX = 0, trackY = -200,

    point = "CENTER", x = 0, y = 40,

    -- "known", "chars", "account" and "collapsed" are tables and are built
    -- in BindSettings: a table in DEFAULTS is copied by reference and every
    -- character would share one.
}

local PREFIX = "|cff00ccffOxedHub Currencies:|r "

local settings
local optionsWindow
local window
local watcher = CreateFrame("Frame")
local running = false

local Draw      -- redraws the window when it is open; defined with the window
local MyRecord  -- this character's saved record; defined with the reading code
local ToggleTrack, UpdateTracker   -- the on-screen bar; defined before the events

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Num(v)
    if type(v) ~= "number" or IsSecret(v) then return nil end
    return v
end

local function Str(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

local function Named(label, fn)
    return OxedHub.Profiler and OxedHub.Profiler:Wrap(label, fn) or fn
end

local function CharKey()
    local name = UnitName("player") or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName() or ""
    return name .. "-" .. realm
end

local function ClassHex(class)
    local colour = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return (colour and colour.colorStr) or "ffffffff"
end

local function Big(n)
    return (BreakUpLargeNumbers or tostring)(n or 0)
end

-- Gold with coin icons. ⚠ The global GetCoinTextureString is missing in some
-- builds, and calling it there broke the gold tooltip; ask whichever exists.
local function CoinText(copper)
    copper = copper or 0
    local fn = GetCoinTextureString
        or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
    if fn then
        local ok, text = pcall(fn, copper)
        if ok and type(text) == "string" then return text end
    end
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, copper, true)
        if ok and type(text) == "string" then return text end
    end
    return Big(math.floor(copper / 10000)) .. "g"
end

-- ── Finding every currency ──────────────────────────────────────────────────

local discovering = false
local quietUntil = 0          -- CURRENCY_DISPLAY_UPDATE before this is our own doing
local lastListSize = -1
local discoverOwed = true

local function TabOpen()
    local tab = TokenFrame
    return tab and tab.IsVisible and tab:IsVisible() or false
end

local function IDAt(index)
    local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(index)
    if type(link) ~= "string" or IsSecret(link) then return nil end
    local id = C_CurrencyInfo.GetCurrencyIDFromLink and C_CurrencyInfo.GetCurrencyIDFromLink(link)
    if not id then id = tonumber(link:match("currency:(%d+)")) end
    return Num(id)
end

-- Opens every closed header, files each currency under its group, and closes
-- those same headers again. A group is the header right above the currency:
-- "Legion" under "Legacy", or "Dungeon and Raid" at the top level.
local HIDDEN_IDS = {
    1813,   -- Reservoir Anima
    1810,   -- Redeemed Soul
    1828,   -- Soul Ash
    1906,   -- Soul Cinders
    1767,   -- Stygia
    1977,   -- Stygian Ember
    1931,   -- Cataloged Research
    1979,   -- Cyphers of the First Ones
    2009,   -- Cosmic Flux
}

local function Discover()
    local CI = C_CurrencyInfo
    if not (CI and CI.GetCurrencyListSize and CI.GetCurrencyListInfo and CI.ExpandCurrencyList) then
        return
    end
    if TabOpen() or InCombatLockdown() then
        discoverOwed = true
        return
    end
    discoverOwed = false
    discovering = true

    local me = MyRecord()
    local has = {}
    local openedNames = {}    -- "depth:name" of headers opened here
    local headers = {}        -- depth -> name of the header above
    local index, order = 1, 0
    while index <= CI.GetCurrencyListSize() and index < 3000 do
        local ok, info = pcall(CI.GetCurrencyListInfo, index)
        if ok and type(info) == "table" then
            local depth = Num(info.currencyListDepth) or 0
            local name = Str(info.name)
            if info.isHeader then
                headers[depth] = name
                for d = depth + 1, depth + 4 do headers[d] = nil end
                if not info.isHeaderExpanded then
                    if pcall(CI.ExpandCurrencyList, index, true) then
                        openedNames[depth .. ":" .. tostring(name)] = true
                    end
                end
            else
                local id = IDAt(index)
                if id and name then
                    order = order + 1
                    local known = settings.known[id]
                    if not known then
                        known = {}
                        settings.known[id] = known
                    end
                    local group
                    for d = depth - 1, 0, -1 do
                        if headers[d] then group = headers[d] break end
                    end
                    known.n, known.g, known.o = name, group or known.g or "Other", order
                    known.i = Num(info.iconFileID) or known.i
                    has[id] = true
                end
            end
        end
        index = index + 1
    end

    -- Bottom to top, so closing one header does not move the ones above it.
    for i = CI.GetCurrencyListSize(), 1, -1 do
        local ok, info = pcall(CI.GetCurrencyListInfo, i)
        if ok and type(info) == "table" and info.isHeader and info.isHeaderExpanded then
            local key = (Num(info.currencyListDepth) or 0) .. ":" .. tostring(Str(info.name))
            if openedNames[key] then pcall(CI.ExpandCurrencyList, i, false) end
        end
    end

    -- ⚠ Some Shadowlands currencies are not in the game's list at all (the
    -- covenant ones live in the sanctum). They are read by id; any this
    -- character holds is filed under Shadowlands with the rest.
    local slGroup = EXPANSION_NAME8 or "Shadowlands"
    for i, extraID in ipairs(HIDDEN_IDS) do
        if not has[extraID] then
            local ok, info = pcall(CI.GetCurrencyInfo, extraID)
            local name = ok and type(info) == "table" and Str(info.name)
            if name and ((Num(info.quantity) or 0) > 0 or settings.known[extraID]) then
                local known = settings.known[extraID] or {}
                settings.known[extraID] = known
                known.n, known.g, known.o = name, known.g or slGroup, known.o or (5000 + i)
                known.i = Num(info.iconFileID) or known.i
                has[extraID] = true
            end
        end
    end

    lastListSize = CI.GetCurrencyListSize()
    if type(me) == "table" and next(has) then
        me.has = has
        if type(me.q) == "table" then
            for id in pairs(me.q) do
                if not has[id] then me.q[id] = nil end
            end
        end
    end
    discovering = false
    quietUntil = GetTime() + 0.5
end

-- ── Reading one currency ────────────────────────────────────────────────────
-- Into a small record kept in saved variables, reused on every read:
--   q  how many this character holds
--   m  the most it can hold (0 for no cap);  w, wm  earned this week, of
--   capped  q has reached m

local function Fill(id, e, known)
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or type(info) ~= "table" then return false end
    e.q = Num(info.quantity) or 0
    local maxQ = Num(info.maxQuantity) or 0
    if info.useTotalEarnedForMaxQty and maxQ > 0 then
        -- A seasonal cap counts what was earned, not what is held.
        e.m, e.t = maxQ, Num(info.totalEarned) or 0
    else
        e.m, e.t = maxQ, nil
    end
    local wm = Num(info.maxWeeklyQuantity) or 0
    e.w, e.wm = (wm > 0) and (Num(info.quantityEarnedThisWeek) or 0) or nil, (wm > 0) and wm or nil
    e.capped = (e.m > 0 and (e.t or e.q) >= e.m) or nil
    known.a = info.isAccountWide and true or nil
    known.x = info.isAccountTransferable and true or nil
    known.i = Num(info.iconFileID) or known.i
    return true
end

-- ── Reading them all ────────────────────────────────────────────────────────

local primed = false
local cappedNames = {}

MyRecord = function()
    local key = CharKey()
    local me = settings.chars[key]
    if type(me) ~= "table" then
        me = {}
        settings.chars[key] = me
    end
    if type(me.q) ~= "table" then me.q = {} end
    local _, class = UnitClass("player")
    me.class, me.name, me.seen = class, UnitName("player"), time()
    return me
end

local function StoreFor(known, me)
    return known.a and settings.account or me.q
end

-- ── Flow: what came in and went out ─────────────────────────────────────────
-- Gains and spending per currency this session and today, for a farming run
-- ("how much anima an hour"). Session figures live only in memory; today's
-- are saved on the character and start over when the date changes. Gold is
-- filed under id 0.
local session = { gain = {}, spent = {} }
local sessionStart

local function Today(me)
    local d = date("%Y-%m-%d")
    if type(me.day) ~= "table" or me.day.d ~= d then
        me.day = { d = d, gain = {}, spent = {} }
    end
    return me.day
end

local function Record(me, id, delta)
    if not delta or delta == 0 then return end
    local day = Today(me)
    if delta > 0 then
        session.gain[id] = (session.gain[id] or 0) + delta
        day.gain[id] = (day.gain[id] or 0) + delta
    else
        session.spent[id] = (session.spent[id] or 0) - delta
        day.spent[id] = (day.spent[id] or 0) - delta
    end
end

-- Lines for a tooltip about one currency (id 0: gold).
local function FlowLines(tooltip, id)
    local me = settings and settings.chars[CharKey()]
    if type(me) ~= "table" then return end
    local fmt = id == 0 and CoinText or Big
    local g, sp = session.gain[id] or 0, session.spent[id] or 0
    local day = type(me.day) == "table" and me.day.d == date("%Y-%m-%d") and me.day or nil
    local dg, ds = day and day.gain[id] or 0, day and day.spent[id] or 0
    if g == 0 and sp == 0 and dg == 0 and ds == 0 then return end
    tooltip:AddLine(" ")
    if g > 0 or sp > 0 then
        local hours = sessionStart and math.max(1 / 60, (GetTime() - sessionStart) / 3600) or 1
        tooltip:AddDoubleLine("This session", ("|cff40ff40+%s|r  |cffff6040-%s|r"):format(fmt(g), fmt(sp)),
            0.8, 0.8, 0.8, 1, 1, 1)
        if g > 0 then
            tooltip:AddDoubleLine("Per hour", "|cff40ff40+" .. fmt(math.floor(g / hours)) .. "|r", 0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    if dg > 0 or ds > 0 then
        tooltip:AddDoubleLine("Today", ("|cff40ff40+%s|r  |cffff6040-%s|r"):format(fmt(dg), fmt(ds)),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
end

-- ── History: one balance per day ────────────────────────────────────────────
-- What each currency stood at on each day, kept for 90 days, so a tooltip can
-- say how far it moved in a week or a month. Only amounts above zero are
-- kept; a day is overwritten until it ends. Gold is id 0.
local HISTORY_DAYS = 90

local function DayNumber(t)
    return math.floor((t or time()) / 86400)
end

local function WriteHistory(me)
    if type(me.hist) ~= "table" then me.hist = {} end
    local today = DayNumber()
    -- Today's table is refilled in place: a new one on every read was garbage.
    local snap = me.hist[today]
    if type(snap) == "table" then wipe(snap) else snap = {} end
    for id, e in pairs(me.q) do
        if type(e) == "table" and (e.q or 0) > 0 then snap[id] = e.q end
    end
    for id, e in pairs(settings.account) do
        if type(e) == "table" and (e.q or 0) > 0 then snap[id] = e.q end
    end
    if me.money then snap[0] = me.money end
    me.hist[today] = snap
    for day in pairs(me.hist) do
        if day < today - HISTORY_DAYS then me.hist[day] = nil end
    end
end

-- The balance on the last recorded day at or before `daysAgo` days back.
local function AmountAgo(me, id, daysAgo)
    if type(me) ~= "table" or type(me.hist) ~= "table" then return nil end
    local target = DayNumber() - daysAgo
    local bestDay
    for day in pairs(me.hist) do
        if day <= target and (not bestDay or day > bestDay) then bestDay = day end
    end
    if not bestDay then return nil end
    return me.hist[bestDay][id] or 0
end

local function HistoryLines(tooltip, id, now)
    local me = settings and settings.chars[CharKey()]
    local shown = false
    for _, span in ipairs({ { 7, "A week ago" }, { 30, "A month ago" } }) do
        local was = AmountAgo(me, id, span[1])
        if was then
            if not shown then tooltip:AddLine(" ") shown = true end
            local diff = (now or 0) - was
            local fmt = id == 0 and CoinText or Big
            local sign = diff >= 0 and "|cff40ff40+" or "|cffff6040-"
            tooltip:AddDoubleLine(span[2], ("%s  %s%s|r"):format(fmt(was), sign, fmt(math.abs(diff))),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
end

local function ScanOne(id, known, me)
    local store = StoreFor(known, me)
    local e = store[id]
    if type(e) ~= "table" then
        e = {}
        store[id] = e
    end
    local wasCapped, before = e.capped, e.q
    if Fill(id, e, known) then
        if primed and before then Record(me, id, (e.q or 0) - before) end
        -- Moved between stores if the game changed whether it is shared.
        if known.a and me.q[id] then me.q[id] = nil end
        if e.capped and not wasCapped and primed then
            cappedNames[#cappedNames + 1] = known.n
        end
        local goal = settings.goals[id]
        if goal and primed and before and before < goal and (e.q or 0) >= goal then
            print(PREFIX .. ("goal reached: |cff40ff40%s %s|r"):format(Big(goal), known.n or "?"))
            local API = OxedHub.ModuleAPI
            if settings.goalSound and settings.goalSound ~= "" and API and API.PlaySound then
                API:PlaySound(settings.goalSound)
            end
        end
    end
end

-- `only`: the ids the game said changed, or nil to read every currency.
-- Looting sends one event per currency; asking the game for all of them
-- each time made a table per currency, several hundred, for one change.
local Scan = Named("Currencies: read every currency", function(only)
    if not settings or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return end
    local me = MyRecord()
    wipe(cappedNames)
    local has = me.has
    if only then
        for id in pairs(only) do
            local known = settings.known[id]
            if known and (known.a or not has or has[id]) then ScanOne(id, known, me) end
        end
    else
        for id, known in pairs(settings.known) do
            if known.a or not has or has[id] then ScanOne(id, known, me) end
        end
    end
    if settings.capAlert and #cappedNames > 0 then
        table.sort(cappedNames)
        print(PREFIX .. "at its cap: |cffffd100" .. table.concat(cappedNames, ", ") .. "|r")
    end
    -- Gold too: the summary line shows this character's and the account's.
    local money = GetMoney and GetMoney()
    if primed and money and me.money then Record(me, 0, money - me.money) end
    if not sessionStart then sessionStart = GetTime() end
    me.money = money or me.money
    WriteHistory(me)
    primed = true
    if Draw then Draw() end
end)

local SyncWarband   -- defined with the warband code below
local scanQueued, scanOwed = false, false
local fullScanOwed = true     -- read every currency next time, not only the changed ones
local changedIDs, scanningIDs = {}, {}
local function RunScan()
    scanQueued = false
    if not running then return end
    if InCombatLockdown() then
        scanOwed = true
        return
    end
    if discoverOwed then
        Discover()
        fullScanOwed = true
    end
    if fullScanOwed or not primed then
        fullScanOwed = false
        wipe(changedIDs)
        Scan()
    else
        -- Swapped, so an event arriving during the read lands in a fresh set.
        changedIDs, scanningIDs = scanningIDs, changedIDs
        Scan(scanningIDs)
        wipe(scanningIDs)
    end
    -- The game may have sent the warband amounts already (the Currency
    -- Transfer module asks too); read what it holds rather than wait.
    if window and window:IsShown() then SyncWarband() end
end

local function QueueScan(delay)
    if scanQueued or not running then return end
    scanQueued = true
    C_Timer.After(delay or 1, RunScan)
end

-- ── Across characters ───────────────────────────────────────────────────────

-- Every saved character's amount of one currency, most first.
-- ── Live amounts from the warband ───────────────────────────────────────────
-- For a currency that can be transferred, the game can say what every
-- character in the warband holds right now. Without this, a transfer left the
-- sender's saved amount as it was until it logged in again, and the total
-- across characters counted the moved amount twice. Characters that never
-- logged in with the module on show up this way too.
local function RealmKey(realm)
    if not realm or realm == "" then
        return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return (realm:gsub("[%s%-]", ""))
end

local requestedAt = 0
local function RequestWarband()
    if InCombatLockdown() or not C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then return end
    if GetTime() - requestedAt < 5 then return end
    requestedAt = GetTime()
    pcall(C_CurrencyInfo.RequestCurrencyDataForAccountCharacters)
end

SyncWarband = Named("Currencies: warband amounts", function()
    if not settings or InCombatLockdown() or not C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then return end
    local myKey = CharKey()
    for id, known in pairs(settings.known) do
        if known.x and not known.a then
            local ok, list = pcall(C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters, id)
            if ok and type(list) == "table" then
                for _, v in ipairs(list) do
                    local guid, quantity = v.characterGUID, Num(v.quantity)
                    if type(guid) == "string" and not IsSecret(guid) and quantity then
                        local okInfo, _, class, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
                        name = okInfo and Str(name) or Str(v.characterName)
                        if name then
                            local key = name .. "-" .. RealmKey(okInfo and Str(realm) or nil)
                            if key ~= myKey then
                                local char = settings.chars[key]
                                if type(char) ~= "table" then
                                    char = { name = name, class = okInfo and class or nil }
                                    settings.chars[key] = char
                                end
                                if type(char.q) ~= "table" then char.q = {} end
                                local rec = char.q[id]
                                if type(rec) ~= "table" then
                                    rec = {}
                                    char.q[id] = rec
                                end
                                rec.q = quantity
                                if type(char.has) == "table" then char.has[id] = true end
                            end
                        end
                    end
                end
            end
        end
    end
    if Draw then Draw() end
end)

local function Holders(id)
    local list = {}
    for key, char in pairs(settings.chars) do
        local rec = type(char) == "table" and type(char.q) == "table" and char.q[id]
        if type(rec) == "table" and (rec.q or 0) > 0 then
            list[#list + 1] = { key = key, char = char, rec = rec }
        end
    end
    table.sort(list, function(a, b) return a.rec.q > b.rec.q end)
    return list
end

local function TotalOf(id)
    local sum, count = 0, 0
    for _, char in pairs(settings.chars) do
        local rec = type(char) == "table" and type(char.q) == "table" and char.q[id]
        if type(rec) == "table" and (rec.q or 0) > 0 then
            sum, count = sum + rec.q, count + 1
        end
    end
    return sum, count
end

local function AmountText(e)
    if not e then return "|cff6060600|r" end
    local q = e.q or 0
    local colour = q > 0 and "ffffffff" or "ff606060"
    if e.capped then
        colour = "ffff6040"
    elseif e.m and e.m > 0 and (e.t or q) >= e.m * 0.8 then
        colour = "ffffb040"     -- near the cap: spend some before it is wasted
    end
    local text = ("|c%s%s|r"):format(colour, Big(q))
    if e.m and e.m > 0 then
        text = text .. ("|cff9d9d9d / %s|r"):format(Big(e.m))
    end
    return text
end

-- A goal replaces the cap in the main list: "1,240 / 5,000", green once met.
local function GoalText(id, e)
    local goal = settings.goals[id]
    if not goal then return AmountText(e) end
    local q = (e and e.q) or 0
    local colour = q >= goal and "ff40ff40" or "ffffb040"
    return ("|c%s%s|r|cff9d9d9d / %s|r"):format(colour, Big(q), Big(goal))
end

local function Coins(copper)
    return CoinText(math.floor((copper or 0) / 10000) * 10000)
end

local function WarbandGold()
    if not (C_Bank and C_Bank.FetchDepositedMoney and Enum and Enum.BankType and Enum.BankType.Account) then return 0 end
    local ok, money = pcall(C_Bank.FetchDepositedMoney, Enum.BankType.Account)
    money = ok and Num(money) or nil
    if money then settings.warbandMoney = money end
    return settings.warbandMoney or 0
end

local function GoldTotal()
    local sum = WarbandGold()
    for _, char in pairs(settings.chars) do
        if type(char) == "table" and type(char.money) == "number" then sum = sum + char.money end
    end
    return sum
end

-- Right-click a row: how many of it you are working towards.
local function AskGoal(id)
    local known = settings.known[id]
    if not known then return end
    if not StaticPopupDialogs["OXEDHUB_CURRENCY_GOAL"] then
        StaticPopupDialogs["OXEDHUB_CURRENCY_GOAL"] = {
            text = "How many %s are you collecting?\n(0 or empty clears the goal)",
            button1 = ACCEPT or "Accept",
            button2 = CANCEL or "Cancel",
            hasEditBox = true,
            OnShow = function(self, data)
                local eb = self.EditBox or self.editBox
                if eb then eb:SetText(settings.goals[data] and tostring(settings.goals[data]) or "") end
            end,
            OnAccept = function(self, data)
                local eb = self.EditBox or self.editBox
                local n = eb and tonumber((eb:GetText() or ""):gsub("[^%d]", ""), 10)
                settings.goals[data] = (n and n > 0) and n or nil
                if Draw then Draw() end
            end,
            EditBoxOnEnterPressed = function(eb)
                local dialog = eb:GetParent()
                local button = dialog and (dialog.button1 or (dialog.GetButton1 and dialog:GetButton1()))
                if button then button:Click() end
            end,
            EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end
    StaticPopup_Show("OXEDHUB_CURRENCY_GOAL", known.n or "it", nil, id)
end

-- ── The window ──────────────────────────────────────────────────────────────

local W, H = 620, 540
local ROW_H = 22
local LIST_TOP = 84
local NAME_W = 250
local OTHER_W = 170

local entries = {}
local entryPool = {}
local offset = 0
local rows = {}
local visibleRows = 0

local function Entry()
    local e = table.remove(entryPool) or {}
    entries[#entries + 1] = e
    return e
end

-- Whose list the window shows: nil for the character logged in, or the key
-- of another one, read from what it saved when it last logged in.
local viewKey = nil

local function ViewRecord()
    local char = viewKey and settings.chars[viewKey]
    if type(char) == "table" and type(char.q) == "table" then return char, viewKey end
    viewKey = nil
    return MyRecord(), CharKey()
end

local function CharacterList()
    local me = CharKey()
    local list = {}
    for key, char in pairs(settings.chars) do
        if type(char) == "table" and type(char.q) == "table" then list[#list + 1] = key end
    end
    table.sort(list, function(a, b)
        if a == me then return true end
        if b == me then return false end
        return a < b
    end)
    return list
end

local function Ago(seen)
    if not seen then return "never" end
    local s = math.max(0, time() - seen)
    if s < 3600 then return "just now" end
    if s < 86400 then return ("%d h ago"):format(math.floor(s / 3600)) end
    return ("%d days ago"):format(math.floor(s / 86400))
end

local function Gather()
    for i = #entries, 1, -1 do
        local e = entries[i]
        entries[i] = nil
        wipe(e)
        entryPool[#entryPool + 1] = e
    end
    if not settings then return 0, 0 end

    local me = ViewRecord()
    local query = window and window.search and window.search:GetText() or ""
    query = query:lower()
    if query == (SEARCH or "search"):lower() then query = "" end

    local ids = {}
    for id in pairs(settings.known) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        return (settings.known[a].o or 9999) < (settings.known[b].o or 9999)
    end)

    local total, held, near = 0, 0, 0
    local header
    for _, id in ipairs(ids) do
        local known = settings.known[id]
        local e = StoreFor(known, me)[id]
        local sum = known.a and ((type(e) == "table" and e.q) or 0) or TotalOf(id)
        total = total + 1
        local mine = type(e) == "table" and (e.q or 0) or 0
        if mine > 0 then held = held + 1 end
        if type(e) == "table" and e.m and e.m > 0 and (e.t or e.q or 0) >= e.m * 0.8 then near = near + 1 end

        local show = true
        if settings.hideEmpty and mine == 0 and (not settings.showOthers or sum == 0) then show = false end
        if show and query ~= "" then
            show = (known.n or ""):lower():find(query, 1, true) ~= nil
        end
        if show then
            if not header or header.group ~= known.g then
                header = Entry()
                header.isHeader, header.group, header.count = true, known.g, 0
            end
            header.count = header.count + 1
            if not settings.collapsed[known.g] or query ~= "" then
                local row = Entry()
                row.id, row.known, row.rec, row.sum = id, known, e, sum
            end
        end
    end
    return total, held, near
end

local ownTooltip = false   -- our own row tooltip lists characters itself

local function RowTooltip(row)
    local entry = row.entry
    if not entry or entry.isHeader then return end
    local known, e = entry.known, entry.rec
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    ownTooltip = true
    local shown = pcall(GameTooltip.SetCurrencyByID, GameTooltip, entry.id)
    ownTooltip = false
    if not shown then
        GameTooltip:SetText(known.n or "?", 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    if known.a then
        GameTooltip:AddLine("Shared by the warband", 0.4, 0.8, 1)
    else
        local list = Holders(entry.id)
        for i, item in ipairs(list) do
            if i > 15 then break end
            GameTooltip:AddDoubleLine(("|c%s%s|r"):format(ClassHex(item.char.class), item.char.name or "?"),
                AmountText(item.rec), 1, 1, 1, 1, 1, 1)
        end
        if #list > 1 then
            GameTooltip:AddDoubleLine("All characters", Big(entry.sum), 1, 0.82, 0, 1, 0.82, 0)
        end
        if known.x then
            GameTooltip:AddLine("Can be transferred between your characters.", 0.4, 0.8, 1)
        end
    end
    FlowLines(GameTooltip, entry.id)
    if not viewKey then HistoryLines(GameTooltip, entry.id, type(e) == "table" and e.q or 0) end
    if type(e) == "table" and e.wm then
        GameTooltip:AddDoubleLine("This week", ("%s / %s"):format(Big(e.w), Big(e.wm)), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    if not known.a then
        GameTooltip:AddLine("Click: every character's amount.", 0.5, 0.8, 1)
    end
    if settings.goals[entry.id] then
        GameTooltip:AddDoubleLine("Goal", Big(settings.goals[entry.id]), 0.8, 0.8, 0.8, 1, 0.7, 0.25)
    end
    GameTooltip:AddLine("Right-click: set a goal.", 0.5, 0.8, 1)
    GameTooltip:AddLine(settings.tracked[entry.id] and "Shift-click: take it off the bar on screen." or "Shift-click: show it on the bar on screen.", 0.5, 0.8, 1)
    GameTooltip:Show()
end

-- ── One currency across every character ─────────────────────────────────────

local altPanel
local altRows = {}
local ALT_W, ALT_ROW = 280, 20
local ALT_MAX = 24

local function BuildAltPanel()
    if altPanel then return altPanel end
    local p = CreateFrame("Frame", nil, window, "BackdropTemplate")
    p:SetWidth(ALT_W)
    p:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, 0)
    p:EnableMouse(true)
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(p, " ", 0.96)
    end
    local okClose, close = pcall(CreateFrame, "Button", nil, p, "UIPanelCloseButton")
    if okClose and close then close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -3, -3) end

    p.head = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    p.head:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -30)
    p.head:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -30)
    p.head:SetJustifyH("LEFT")
    p.head:SetWordWrap(false)

    p.sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.sub:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -3)
    p.sub:SetJustifyH("LEFT")
    p:Hide()
    altPanel = p
    return p
end

local function AltRow(p, i)
    local row = altRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, p)
    row:SetHeight(ALT_ROW)
    row:SetPoint("TOPLEFT", p, "TOPLEFT", 12, -64 - (i - 1) * ALT_ROW)
    row:SetPoint("TOPRIGHT", p, "TOPRIGHT", -12, -64 - (i - 1) * ALT_ROW)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.name:SetWidth(150)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amount:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.amount:SetJustifyH("RIGHT")

    row:SetScript("OnClick", function(self)
        if not self.key then return end
        viewKey = (self.key ~= CharKey()) and self.key or nil
        offset = 0
        Draw()
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.key or "?")
        GameTooltip:AddLine("Saved " .. Ago(self.seen), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Click to see this character's whole list.", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    altRows[i] = row
    return row
end

local altFor = nil
local function ShowAlts(id)
    if not (window and settings and settings.known[id]) then return end
    local p = BuildAltPanel()
    if altFor == id and p:IsShown() then
        p:Hide()
        altFor = nil
        return
    end
    altFor = id
    local known = settings.known[id]
    local list = Holders(id)
    local sum = TotalOf(id)

    p.head:SetText(known.n or "?")
    p.sub:SetFormattedText("%d characters hold |cffffd100%s|r in all", #list, Big(sum))

    local shown = math.min(#list, ALT_MAX)
    for i = 1, shown do
        local item = list[i]
        local row = AltRow(p, i)
        row.key, row.seen = item.key, item.char.seen
        row.name:SetFormattedText("|c%s%s|r", ClassHex(item.char.class), item.char.name or "?")
        row.amount:SetText(AmountText(item.rec))
        row:Show()
    end
    for i = shown + 1, #altRows do altRows[i]:Hide() end
    p:SetHeight(64 + math.max(1, shown) * ALT_ROW + 16)
    p:Show()
end

local function CreateRow(list, index)
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(index - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)

    row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.toggle:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.toggle:SetWidth(14)

    -- A green dot beside a currency that is on the bar on screen.
    row.pin = row:CreateTexture(nil, "OVERLAY")
    row.pin:SetTexture("Interface\\COMMON\\Indicator-Green")
    row.pin:SetSize(14, 14)
    row.pin:SetPoint("LEFT", row, "LEFT", 3, 0)
    row.pin:Hide()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ROW_H - 6, ROW_H - 6)
    row.icon:SetPoint("LEFT", row, "LEFT", 18, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", row, "LEFT", 22 + ROW_H - 6, 0)
    row.name:SetWidth(NAME_W)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.amount:SetPoint("RIGHT", row, "RIGHT", -(OTHER_W + 8), 0)
    row.amount:SetJustifyH("RIGHT")

    row.other = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.other:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.other:SetWidth(OTHER_W)
    row.other:SetJustifyH("RIGHT")
    row.other:SetWordWrap(false)

    row:SetScript("OnClick", function(self, mouse)
        local entry = self.entry
        if not entry then return end
        if entry.isHeader then
            settings.collapsed[entry.group] = not settings.collapsed[entry.group] or nil
            Draw()
        elseif IsShiftKeyDown() and mouse ~= "RightButton" then
            -- Into chat while typing, the way every link works; otherwise
            -- onto the bar on screen (or off it).
            local typing = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
            local link = typing and C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(entry.id, 0)
            if link then
                ChatEdit_InsertLink(link)
            else
                ToggleTrack(entry.id)
            end
        elseif mouse == "RightButton" then
            AskGoal(entry.id)
        elseif not entry.known.a then
            ShowAlts(entry.id)
        end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function PaintRow(row, entry)
    row.entry = entry
    if entry.isHeader then
        row.toggle:SetText(settings.collapsed[entry.group] and "+" or "-")
        row.toggle:Show()
        row.icon:Hide()
        row.pin:Hide()
        row.name:SetFontObject("GameFontNormal")
        row.name:SetText(entry.group or "")
        row.amount:SetText("")
        row.other:SetFormattedText("|cff9d9d9d%d|r", entry.count or 0)
        return
    end

    local e, known = entry.rec, entry.known
    row.toggle:Hide()
    row.icon:SetTexture(known.i or 134400)
    row.icon:Show()
    row.pin:SetShown(settings.tracked[entry.id] ~= nil)
    row.name:SetFontObject("GameFontHighlightSmall")
    row.name:SetText(known.n or "?")
    row.amount:SetText(GoalText(entry.id, type(e) == "table" and e or nil))

    local otherText = ""
    if settings.showOthers then
        if known.a then
            otherText = "|cff66ccffwarband|r"
        elseif (entry.sum or 0) > 0 then
            local mine = type(e) == "table" and (e.q or 0) or 0
            if entry.sum > mine then
                otherText = ("|cff9d9d9dall chars|r |cffffd100%s|r"):format(Big(entry.sum))
            end
        end
    end
    row.other:SetText(otherText)
end

Draw = function()
    if not (window and window:IsShown()) then return end
    local total, held, near = Gather()
    local viewed = ViewRecord()

    window.summary:SetFormattedText("%d currencies   |cffffd100%d|r held%s   gold %s  |cff9d9d9d(all %s)|r%s",
        total, held, near > 0 and ("   |cffffb040%d near cap|r"):format(near) or "", Coins(viewed.money), Coins(GoldTotal()),
        viewKey and ("   |cffff9933saved %s|r"):format(Ago(viewed.seen)) or "")
    if window.fold then window.fold.Refresh() end
    if window.picker then
        window.picker:SetText(("|c%s%s|r"):format(ClassHex(viewed.class), viewed.name or "?"))
    end

    local maxOffset = math.max(0, #entries - visibleRows)
    if offset > maxOffset then offset = maxOffset end
    window.scroll:SetMinMaxValues(0, maxOffset)
    window.scroll:SetShown(maxOffset > 0)
    if math.floor(window.scroll:GetValue() + 0.5) ~= offset then window.scroll:SetValue(offset) end

    for i = 1, visibleRows do
        local entry = entries[offset + i]
        local row = rows[i]
        if entry then
            if not row then
                row = CreateRow(window.list, i)
                rows[i] = row
            end
            PaintRow(row, entry)
            row:Show()
        elseif row then
            row.entry = nil
            row:Hide()
        end
    end
    window.empty:SetShown(#entries == 0)
end

local function SavePosition()
    if not window then return end
    local point, _, _, x, y = window:GetPoint(1)
    if point then settings.point, settings.x, settings.y = point, x, y end
end

local tokenAskedAt

local function BuildWindow()
    if window then return window end

    local w = CreateFrame("Frame", "OxedHubCurrencies", UIParent, "BackdropTemplate")
    w:SetSize(W, H)
    w:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 0, settings.y or 40)
    w:SetFrameStrata("HIGH")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    w:Hide()
    tinsert(UISpecialFrames, "OxedHubCurrencies")

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(w, "Currencies", 0.96)
    elseif w.SetBackdrop then
        w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        w:SetBackdropColor(0.1, 0.095, 0.085, 0.96)
    end

    local okClose, close = pcall(CreateFrame, "Button", nil, w, "UIPanelCloseButton")
    if okClose and close then
        close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
        close:SetScript("OnClick", function() w:Hide() end)
    end

    -- ⚠ SetAutoFocus(false) first thing: a new EditBox takes the keyboard.
    local okSearch, search = pcall(CreateFrame, "EditBox", nil, w, "SearchBoxTemplate")
    if not okSearch or not search then
        search = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    end
    search:SetAutoFocus(false)
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -30)
    search:HookScript("OnTextChanged", function()
        offset = 0
        Draw()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    w.search = search

    local hide = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    hide:SetSize(24, 24)
    hide:SetPoint("LEFT", search, "RIGHT", 14, 0)
    hide.text:SetFontObject("GameFontHighlightSmall")
    hide.text:SetText("Hide empty")
    hide:SetScript("OnClick", function(self)
        settings.hideEmpty = self:GetChecked() and true or false
        offset = 0
        Draw()
    end)
    w.hideBox = hide

    local others = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    others:SetSize(24, 24)
    others:SetPoint("LEFT", hide.text, "RIGHT", 14, 0)
    others.text:SetFontObject("GameFontHighlightSmall")
    others.text:SetText("Other characters")
    others:SetScript("OnClick", function(self)
        settings.showOthers = self:GetChecked() and true or false
        Draw()
    end)
    w.othersBox = others

    local options = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    options:SetSize(80, 22)
    options:SetPoint("TOPRIGHT", w, "TOPRIGHT", -34, -29)
    options:SetText(OPTIONS or "Options")
    options:SetScript("OnClick", function()
        local API = OxedHub.ModuleAPI
        local mod = API and API.GetModule and API:GetModule("currencies")
        if mod and mod.OnOptionsShow then mod:OnOptionsShow() end
    end)

    local function SetView(key)
        viewKey = (key and key ~= CharKey()) and key or nil
        offset = 0
        Draw()
    end
    local picker = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    picker:SetSize(140, 20)
    picker:SetPoint("TOPRIGHT", w, "TOPRIGHT", -34, -55)
    picker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    picker:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then return SetView(nil) end
        local list = CharacterList()
        local shown = MenuUtil and MenuUtil.CreateContextMenu and pcall(MenuUtil.CreateContextMenu, self,
            function(_, root)
                root:CreateTitle("Show the currencies of")
                for _, key in ipairs(list) do
                    local char = settings.chars[key]
                    local label = ("|c%s%s|r  |cff9d9d9d%s|r"):format(ClassHex(char.class),
                        char.name or key, key == CharKey() and "you" or Ago(char.seen))
                    root:CreateButton(label, function() SetView(key) end)
                end
            end)
        if not shown then
            local current = viewKey or CharKey()
            for i, key in ipairs(list) do
                if key == current then
                    SetView(list[i % #list + 1])
                    return
                end
            end
            SetView(nil)
        end
    end)
    picker:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Whose currencies")
        GameTooltip:AddLine("Click to pick any of your characters. Right-click: back to this one.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    picker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.picker = picker

    local function AllFolded()
        for _, known in pairs(settings.known) do
            if known.g and not settings.collapsed[known.g] then return false end
        end
        return true
    end
    local fold = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    fold:SetSize(84, 20)
    fold:SetPoint("RIGHT", picker, "LEFT", -6, 0)
    fold.Refresh = function() fold:SetText(AllFolded() and "Expand all" or "Collapse all") end
    fold:SetScript("OnClick", function()
        local open = AllFolded()
        for _, known in pairs(settings.known) do
            if known.g then settings.collapsed[known.g] = (not open) or nil end
        end
        offset = 0
        Draw()
    end)
    w.fold = fold

    w.summary = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    w.summary:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -60)
    w.summary:SetJustifyH("LEFT")
    w.summary:SetWidth(W - 294)   -- up to the Collapse all button
    w.summary:SetWordWrap(false)

    -- Hovering the summary: the gold in detail.
    local goldHover = CreateFrame("Frame", nil, w)
    goldHover:SetAllPoints(w.summary)
    goldHover:EnableMouse(true)
    goldHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Gold")
        local list = {}
        for _, char in pairs(settings.chars) do
            if type(char) == "table" and (char.money or 0) > 0 then list[#list + 1] = char end
        end
        table.sort(list, function(a, b) return a.money > b.money end)
        for i, char in ipairs(list) do
            if i > 15 then break end
            GameTooltip:AddDoubleLine(("|c%s%s|r"):format(ClassHex(char.class), char.name or "?"),
                CoinText(char.money), 1, 1, 1, 1, 1, 1)
        end
        local bank = WarbandGold()
        if bank > 0 then
            GameTooltip:AddDoubleLine("|cff66ccffWarband bank|r", CoinText(bank), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("All", CoinText(GoldTotal()), 1, 0.82, 0, 1, 0.82, 0)
        FlowLines(GameTooltip, 0)
        HistoryLines(GameTooltip, 0, GetMoney())
        if C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice then
            local price = Num(C_WowTokenPublic.GetCurrentMarketPrice())
            if price and price > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("WoW Token", CoinText(price), 0.8, 0.8, 0.8, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    end)
    goldHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local line = w:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -LIST_TOP + 4)
    line:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -LIST_TOP + 4)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    local list = CreateFrame("Frame", nil, w)
    list:SetPoint("TOPLEFT", w, "TOPLEFT", 14, -LIST_TOP)
    list:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -28, 14)
    list:EnableMouseWheel(true)
    w.list = list
    visibleRows = math.floor((H - LIST_TOP - 14) / ROW_H)

    -- The game's own thin scrollbar, as its newer windows use. It speaks in
    -- percentages; this wraps it in the few slider calls the list makes. The
    -- plain slider stays as the fallback for a client without the template.
    local function OnOffset(value)
        local wanted = math.floor(value + 0.5)
        if wanted ~= offset then
            offset = wanted
            Draw()
        end
    end
    local scroll
    local okBar, bar = pcall(CreateFrame, "EventFrame", nil, w, "MinimalScrollBar")
    if okBar and bar and bar.SetScrollPercentage and bar.RegisterCallback then
        bar:SetPoint("TOPRIGHT", w, "TOPRIGHT", -14, -LIST_TOP)
        bar:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -14, 16)
        local maxValue, setting = 0, false
        scroll = {
            SetMinMaxValues = function(_, _, high)
                maxValue = high or 0
                local total = visibleRows + maxValue
                if bar.SetVisibleExtentPercentage then
                    bar:SetVisibleExtentPercentage(total > 0 and visibleRows / total or 1)
                end
                if bar.SetPanExtentPercentage then
                    bar:SetPanExtentPercentage(maxValue > 0 and math.min(1, 3 / maxValue) or 1)
                end
            end,
            GetMinMaxValues = function() return 0, maxValue end,
            GetValue = function()
                return maxValue > 0 and (bar:GetScrollPercentage() or 0) * maxValue or 0
            end,
            SetValue = function(_, value)
                setting = true
                bar:SetScrollPercentage(maxValue > 0 and value / maxValue or 0)
                setting = false
                OnOffset(value)
            end,
            SetShown = function(_, shown) bar:SetShown(shown) end,
        }
        bar:RegisterCallback("OnScroll", function(_, percentage)
            if not setting then OnOffset((percentage or 0) * maxValue) end
        end, w)
    else
        scroll = CreateFrame("Slider", nil, w)
        scroll:SetOrientation("VERTICAL")
        scroll:SetWidth(10)
        scroll:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -LIST_TOP)
        scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -12, 16)
        scroll:SetValueStep(1)
        scroll:SetObeyStepOnDrag(true)
        local track = scroll:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.45)
        local thumb = scroll:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, 0.82, 0, 0.55)
        thumb:SetSize(10, 36)
        scroll:SetThumbTexture(thumb)
        scroll:SetScript("OnValueChanged", function(_, value) OnOffset(value) end)
    end
    w.scroll = scroll

    list:SetScript("OnMouseWheel", function(_, delta)
        local low, high = scroll:GetMinMaxValues()
        scroll:SetValue(math.max(low, math.min(high, offset - delta * 3)))
    end)

    w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    w.empty:SetPoint("CENTER", list, "CENTER")
    w.empty:SetText("Nothing to show")

    w:SetScript("OnShow", function(self)
        self.hideBox:SetChecked(settings.hideEmpty == true)
        self.othersBox:SetChecked(settings.showOthers ~= false)
        Draw()
        fullScanOwed = true
        QueueScan(0)
        RequestWarband()
        if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice and GetTime() - (tokenAskedAt or -9999) > 600 then
            tokenAskedAt = GetTime()
            pcall(C_WowTokenPublic.UpdateMarketPrice)
        end
    end)

    window = w
    return w
end

local function ToggleWindow()
    if not settings then return end
    if not running then
        print(PREFIX .. "switch the module on first (/ohub > Modules).")
        return
    end
    local w = BuildWindow()
    w:SetShown(not w:IsShown())
end

-- ── The bar on screen ───────────────────────────────────────────────────────
-- Shift-click a currency in the list to pin it here: its icon and how many
-- you hold, on a small bar you drag wherever it suits. Right-click an icon to
-- take it off. Amounts are read straight from the game for these few only, so
-- the bar keeps up in a fight while the full list waits for it to end.

local bar
local barIcons = {}
local BAR_ICON = 26
local BAR_GAP = 46

local function TrackedList()
    local list = {}
    for id, order in pairs(settings.tracked) do list[#list + 1] = { id = id, order = order } end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

local function SaveBarPosition()
    local point, _, _, x, y = bar:GetPoint(1)
    if point then settings.trackPoint, settings.trackX, settings.trackY = point, x, y end
end

local function StartBarDrag()
    if not settings.trackLocked and not InCombatLockdown() then bar:StartMoving() end
end

local function StopBarDrag()
    bar:StopMovingOrSizing()
    SaveBarPosition()
end

local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "OxedHubCurrencyBar", UIParent, "BackdropTemplate")
    bar:SetPoint(settings.trackPoint or "CENTER", UIParent, settings.trackPoint or "CENTER",
        settings.trackX or 0, settings.trackY or -200)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", StartBarDrag)
    bar:SetScript("OnDragStop", StopBarDrag)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    bar:Hide()
    return bar
end

local function BarIcon(i)
    local b = barIcons[i]
    if b then return b end
    b = CreateFrame("Button", nil, bar)
    b:SetSize(BAR_ICON, BAR_ICON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("LEFT", b, "RIGHT", 3, 0)
    b.count:SetJustifyH("LEFT")
    -- Dragging an icon moves the whole bar.
    b:SetScript("OnDragStart", StartBarDrag)
    b:SetScript("OnDragStop", StopBarDrag)
    b:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and self.id then
            ToggleTrack(self.id)
        elseif not InCombatLockdown() and settings then
            SlashCmdList.OXEDHUBCURRENCIES()
        end
    end)
    b:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if not pcall(GameTooltip.SetCurrencyByID, GameTooltip, self.id) then
            GameTooltip:SetText(settings.known[self.id] and settings.known[self.id].n or "?")
        end
        FlowLines(GameTooltip, self.id)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(settings.trackLocked and "Click: the list. Right-click: take it off the bar."
            or "Drag: move the bar. Click: the list. Right-click: take it off.", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    barIcons[i] = b
    return b
end

local function LiveAmount(id)
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if ok and type(info) == "table" then
        local q = Num(info.quantity)
        if q then return q, Num(info.maxQuantity) or 0, Num(info.iconFileID) end
    end
    local known = settings.known[id]
    local e = known and StoreFor(known, MyRecord())[id]
    return type(e) == "table" and e.q or 0, type(e) == "table" and e.m or 0, known and known.i
end

UpdateTracker = function()
    if not settings then return end
    local list = TrackedList()
    if not running or #list == 0 then
        if bar then bar:Hide() end
        return
    end
    BuildBar()
    bar:SetScale(settings.trackScale or 1)
    local vertical = settings.trackVertical
    local widest = 0
    for i, item in ipairs(list) do
        local b = BarIcon(i)
        local q, m, icon = LiveAmount(item.id)
        b.id = item.id
        b.icon:SetTexture(icon or (settings.known[item.id] and settings.known[item.id].i) or 134400)
        local colour = "ffffffff"
        if m > 0 and q >= m then colour = "ffff6040" elseif m > 0 and q >= m * 0.8 then colour = "ffffb040" end
        local goal = settings.goals[item.id]
        if goal and q >= goal then colour = "ff40ff40" end
        b.count:SetText(("|c%s%s|r"):format(colour, Big(q)))
        widest = math.max(widest, b.count:GetStringWidth())
        b:ClearAllPoints()
        b:Show()
    end
    local step = math.max(BAR_GAP, BAR_ICON + 10 + widest)
    for i in ipairs(list) do
        local b = barIcons[i]
        if vertical then
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4 - (i - 1) * (BAR_ICON + 4))
        else
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", 4 + (i - 1) * step, -4)
        end
    end
    for i = #list + 1, #barIcons do barIcons[i]:Hide() end
    if vertical then
        bar:SetSize(BAR_ICON + 14 + widest, 8 + #list * (BAR_ICON + 4) - 4)
    else
        bar:SetSize(8 + #list * step - 6, BAR_ICON + 8)
    end
    -- A faint backdrop only while it can be moved, so it is easy to grab.
    if bar.SetBackdropColor then
        bar:SetBackdropColor(0, 0, 0, settings.trackLocked and 0 or 0.45)
        bar:SetBackdropBorderColor(1, 0.82, 0, settings.trackLocked and 0 or 0.5)
    end
    bar:Show()
end

ToggleTrack = function(id)
    if settings.tracked[id] then
        settings.tracked[id] = nil
    else
        local top = 0
        for _, order in pairs(settings.tracked) do top = math.max(top, order) end
        settings.tracked[id] = top + 1
    end
    UpdateTracker()
    if Draw then Draw() end
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not running then return end
    if event == "CURRENCY_DISPLAY_UPDATE" then
        if discovering or GetTime() < quietUntil then return end
        -- A currency the list has not seen yet: learn the list again first.
        local id = Num(arg1)
        if id and not settings.known[id] then discoverOwed = true end
        if id then changedIDs[id] = true else fullScanOwed = true end
        if bar and bar:IsShown() then UpdateTracker() end
        if C_CurrencyInfo.GetCurrencyListSize and C_CurrencyInfo.GetCurrencyListSize() ~= lastListSize
            and not TabOpen() then
            discoverOwed = true
        end
        QueueScan()
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        if isLogin or isReload then
            discoverOwed = true
            QueueScan(3)
        end
    elseif event == "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED" then
        SyncWarband()
    elseif event == "CURRENCY_TRANSFER_LOG_UPDATE" then
        requestedAt = 0
        RequestWarband()
    elseif event == "PLAYER_MONEY" then
        QueueScan()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if scanOwed then
            scanOwed = false
            QueueScan(0.5)
        end
    end
end)

local EVENTS = { "CURRENCY_DISPLAY_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_MONEY",
    "ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", "CURRENCY_TRANSFER_LOG_UPDATE" }

local function Start()
    if running then return end
    running = true
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    discoverOwed = true
    QueueScan(3)
    UpdateTracker()
end

local function Stop()
    running = false
    watcher:UnregisterAllEvents()
    if window then window:Hide() end
    if bar then bar:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function EnsureTables(config)
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.known) ~= "table" then config.known = {} end
    if type(config.chars) ~= "table" then config.chars = {} end
    if type(config.account) ~= "table" then config.account = {} end
    if type(config.collapsed) ~= "table" then config.collapsed = {} end
    if type(config.goals) ~= "table" then config.goals = {} end
    if type(config.tracked) ~= "table" then config.tracked = {} end   -- id -> order added
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.currencies
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.currencies = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    EnsureTables(config)
    settings = config
end

local function ForgetOthers()
    local me = CharKey()
    for key in pairs(settings.chars) do
        if key ~= me then settings.chars[key] = nil end
    end
    Draw()
end

local minimapIcon
local function MinimapIcon()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "currencies", label = "Currencies", icon = "Interface\\Icons\\INV_Misc_Coin_17", config = settings,
        hint = "Click: the list. Right-click: options.",
        onClick = function(mouse)
            if mouse == "RightButton" then
                local mod = API:GetModule("currencies")
                if mod and mod.OnOptionsShow then mod:OnOptionsShow() end
            else
                ToggleWindow()
            end
        end,
    })
    return minimapIcon
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Currencies", 480, 620)
        local o = optionsWindow

        o:AddCheckbox(settings, "showOthers", "Show the total across your characters on each row",
            "For currencies not shared by the warband: what all your characters hold together.", Draw)
        o:AddCheckbox(settings, "hideEmpty", "Hide currencies nobody has",
            "With the total shown, a currency only an alt holds still shows.", Draw)
        o:AddCheckbox(settings, "capAlert", "Say when a currency reaches its cap")
        o:AddCheckbox(settings, "altTooltip", "Your characters' amounts in currency tooltips",
            "Anywhere the game shows a currency tooltip: the currency tab, links in chat, vendors.")
        o:AddSoundPicker(settings, "goalSound", "Goal reached sound", "None")
        o:AddCheckbox(settings, "trackLocked", "Lock the bar on screen",
            "Shift-click a currency in the list to put it on the bar. Unlocked, drag the bar to move it.", UpdateTracker)
        o:AddCheckbox(settings, "trackVertical", "Bar on screen runs downwards", nil, UpdateTracker)
        o:AddSlider(settings, "trackScale", "Bar size", 0.6, 2, 0.05, "%s: %.2f", UpdateTracker)

        local open = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        open:SetSize(150, 22)
        open:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 4)
        open:SetText("Open the list")
        open:SetScript("OnClick", ToggleWindow)

        local forget = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        forget:SetSize(190, 22)
        forget:SetPoint("LEFT", open, "RIGHT", 8, 0)
        forget:SetText("Forget other characters")
        forget:SetScript("OnClick", function()
            API:Confirm("Forget the currencies saved for every other character?", ForgetOthers)
        end)
        o.cursorY = o.cursorY - 34

        o:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        o:AddModuleLinks("Works together with", { "reputations", "currencytransfer" })
        o:AddNote("Each character's currencies are saved when it logs in with this module on, so log in on your alts once for them to show.")
        o:AddNote("In the list: right-click a currency to set a goal, Shift-click it to show it on the bar on screen. Type /oxcurrency to open the list.")
    end
    optionsWindow:Show()
end

-- ── Other characters in the game's currency tooltips ────────────────────────
-- Hovering a currency anywhere -- the currency tab, a link in chat, a vendor --
-- lists what each of your characters holds, the way the list does.
local function AddAltLines(tooltip, data)
    if ownTooltip or not running or not settings or not settings.altTooltip then return end
    local id = data and data.id
    if type(id) ~= "number" or IsSecret(id) then return end
    local known = settings.known[id]
    if not known or known.a then return end
    local list = Holders(id)
    if #list == 0 then return end
    tooltip:AddLine(" ")
    for i, item in ipairs(list) do
        if i > 10 then break end
        tooltip:AddDoubleLine(("|c%s%s|r"):format(ClassHex(item.char.class), item.char.name or "?"),
            AmountText(item.rec), 1, 1, 1, 1, 1, 1)
    end
    if #list > 1 then
        tooltip:AddDoubleLine("All characters", Big(TotalOf(id)), 1, 0.82, 0, 1, 0.82, 0)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
    and Enum.TooltipDataType.Currency then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Currency, function(tooltip, data)
        pcall(AddAltLines, tooltip, data)
    end)
end

SLASH_OXEDHUBCURRENCIES1 = "/oxcurrency"
SLASH_OXEDHUBCURRENCIES2 = "/oxcurrencies"
SlashCmdList.OXEDHUBCURRENCIES = function()
    ToggleWindow()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "currencies",
        name     = "Currencies",
        version  = "1.5.1",
        updated  = 20261023.1,  -- reads only the currencies that changed
        author   = "Oxed",
        category = "character",
        keywords = { "currency", "currencies", "tokens", "warband", "alts", "cap", "decor", "legacy" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Every currency for all your characters, with totals across them. /oxcurrency",
        icon     = "Interface\\Icons\\INV_Misc_Coin_17",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,
        quick = {
            { text = "Currencies", func = function() ToggleWindow() end },
        },

        OnEnable = function(_, config)
            settings = config
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            EnsureTables(settings)
            Start()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
