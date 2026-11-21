-- ============================================================================
-- Craft Profit
--   A list beside the profession window: every recipe you know, sorted by
--   what it earns. Reagent cost against the best way to turn the result into
--   gold: the auction house (after its 5% cut), a vendor, or disenchanting
--   (values from Disenchant Info). Also beside a profession trainer: what you
--   can learn now and what each of those would earn.
--
--   Reads the newer profession window (C_TradeSkillUI, ProfessionsFrame: WoW
--   Forever and retail) or the old one (GetTradeSkillInfo). Prices: Auctionator,
--   TSM, Disenchant Info, or its own quiet auction scan.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local PREFIX = "|cFF00FFFF[OxedHub Craft Profit]:|r "
local AH_CUT = 0.95
local ROWS = 14
local ROW_H = 24
local W, H = 380, 470

local DEFAULTS = {
    enabled        = false,  -- off until the player switches it on (see ModuleAPI:Register)
    minimapButton  = true,
    showCrafting   = true,   -- the list beside the profession window
    showTrainer    = true,   -- the list beside a profession trainer
    onlyProfitable = false,
    onlyCraftable  = false,  -- only recipes the bags hold reagents for
    useDisenchant  = true,   -- count disenchanting as a way to sell
    ownMatsFree    = false,  -- reagents already in the bags cost nothing
    autoScan       = true,   -- quietly price the chosen professions at the auction house
    skipWithAuctionator = false, -- leave pricing to Auctionator when it is installed
    scanDisenchantMats  = true,  -- include dusts, essences and shards
}
-- Tables are made in BindSettings, never here: prices, vendorPrices,
-- recipeItems (profession -> {itemID = true}), scanProfs (profession -> bool).

local settings
local active = false
local minimapIcon
local optionsWindow
local panel
local list, offset, mode = {}, 0, "craft"   -- mode: "craft" or "trainer"
local refreshQueued = false

-- ── Prices ──────────────────────────────────────────────────────────────────

local function ItemIDFromLink(link)
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

local function ItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if GetItemInfo then return GetItemInfo(item) end
end

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
end

local function AuctionPrice(itemID)
    if not itemID then return nil end
    -- A fresh scan of our own (under a day old) beats older Auctionator data.
    local mine = settings and settings.prices and settings.prices[itemID]
    if type(mine) == "table" and mine.p and mine.p > 0 and mine.t and time() - mine.t < 86400 then
        return mine.p
    end
    if not itemID then return nil end
    local SS = OxedHub.Shattersight
    if SS and SS.GetItemPrice then
        local ok, price = pcall(SS.GetItemPrice, SS, itemID)
        if ok and price and price > 0 then return price end
    end
    local A = Auctionator and Auctionator.API and Auctionator.API.v1
    if A and A.GetAuctionPriceByItemID then
        local ok, price = pcall(A.GetAuctionPriceByItemID, "OxedHub_CraftProfit", itemID)
        if ok and price and price > 0 then return price end
    end
    -- Our own quiet scan (see the Scanner section).
    local own = settings and settings.prices and settings.prices[itemID]
    if type(own) == "table" and own.p and own.p > 0 then return own.p end
    return nil
end

-- Which profession a recipe list belongs to, so the scanner knows what to ask.
local function RememberItems(profession, entries)
    if not settings or type(profession) ~= "string" or profession == "" then return end
    settings.recipeItems[profession] = settings.recipeItems[profession] or {}
    local bag = settings.recipeItems[profession]
    for _, e in ipairs(entries) do
        local id = ItemIDFromLink(e.link)
        if id then bag[id] = true end
        for _, r in ipairs(e.reagents or {}) do
            if r.itemID then bag[r.itemID] = true end
        end
    end
    if settings.scanProfs[profession] == nil then settings.scanProfs[profession] = true end
end

-- Reagents every trade-goods vendor sells, at their price. Anything else seen
-- at a merchant is remembered in settings.vendorPrices (MERCHANT_SHOW).
local VENDOR_REAGENTS = {
    [2320] = 10,    -- Coarse Thread
    [2321] = 100,   -- Fine Thread
    [4291] = 500,   -- Silken Thread
    [8343] = 2000,  -- Heavy Silken Thread
    [14341] = 5000, -- Rune Thread
    [2324] = 25,    -- Bleach
    [2604] = 50,    -- Red Dye
    [6260] = 50,    -- Blue Dye
    [2605] = 100,   -- Green Dye
    [4340] = 350,   -- Gray Dye
    [4341] = 500,   -- Yellow Dye
    [2325] = 1000,  -- Black Dye
    [6261] = 1000,  -- Orange Dye
    [4342] = 2500,  -- Purple Dye
    [10290] = 2500, -- Pink Dye
    [4289] = 50,    -- Salt
    [2678] = 10,    -- Mild Spices
    [2692] = 40,    -- Hot Spices
    [3713] = 160,   -- Soothing Spices
    [159] = 25,     -- Refreshing Spring Water
    [3371] = 4,     -- Empty Vial
    [3372] = 40,    -- Leaded Vial
    [8925] = 500,   -- Crystal Vial
    [2880] = 100,   -- Weak Flux
    [3466] = 2000,  -- Strong Flux
    [3857] = 500,   -- Coal
    [4470] = 38,    -- Simple Wood
    [4399] = 200,   -- Wooden Stock
    [4400] = 2000,  -- Heavy Stock
}

-- What a reagent costs to buy, and where: "Vendor" or "AH".
local function ReagentPrice(itemID)
    if not itemID then return nil end
    local seen = settings and settings.vendorPrices and settings.vendorPrices[itemID]
    if seen and seen > 0 then return seen, "Vendor" end
    if VENDOR_REAGENTS[itemID] then return VENDOR_REAGENTS[itemID], "Vendor" end
    local A = Auctionator and Auctionator.API and Auctionator.API.v1
    if A and A.GetVendorPriceByItemID then
        local ok, price = pcall(A.GetVendorPriceByItemID, "OxedHub_CraftProfit", itemID)
        if ok and price and price > 0 then return price, "Vendor" end
    end
    local ah = AuctionPrice(itemID)
    if ah then return ah, "AH" end
    return nil
end

-- Remember what this merchant sells for gold, per single item.
local function RecordMerchant()
    if not settings or not GetMerchantNumItems then return end
    settings.vendorPrices = type(settings.vendorPrices) == "table" and settings.vendorPrices or {}
    for i = 1, (Call(GetMerchantNumItems) or 0) do
        local link = Call(GetMerchantItemLink, i)
        local id = ItemIDFromLink(link)
        local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and Call(C_MerchantFrame.GetItemInfo, i)
        local price, stack, extended
        if type(info) == "table" then
            price, stack, extended = info.price, info.stackCount, info.hasExtendedCost
        else
            local _, _, p, q, _, _, _, ext = Call(GetMerchantItemInfo, i)
            price, stack, extended = p, q, ext
        end
        if id and type(price) == "number" and price > 0 and not extended then
            settings.vendorPrices[id] = math.floor(price / math.max(1, stack or 1) + 0.5)
        end
    end
end

local DE_EQUIP = {
    INVTYPE_HEAD=true, INVTYPE_NECK=true, INVTYPE_SHOULDER=true, INVTYPE_BODY=true,
    INVTYPE_CHEST=true, INVTYPE_ROBE=true, INVTYPE_WAIST=true, INVTYPE_LEGS=true,
    INVTYPE_FEET=true, INVTYPE_WRIST=true, INVTYPE_HAND=true, INVTYPE_FINGER=true,
    INVTYPE_TRINKET=true, INVTYPE_CLOAK=true, INVTYPE_WEAPON=true, INVTYPE_SHIELD=true,
    INVTYPE_RANGED=true, INVTYPE_RANGEDRIGHT=true, INVTYPE_2HWEAPON=true,
    INVTYPE_WEAPONMAINHAND=true, INVTYPE_WEAPONOFFHAND=true, INVTYPE_HOLDABLE=true,
    INVTYPE_THROWN=true,
}

-- Expected disenchant value of one item, from Disenchant Info's tables.
local function DisenchantValue(link)
    local SS = OxedHub.Shattersight
    if not SS or not link then return nil end
    local _, _, quality, ilvl, _, _, _, _, equipLoc, _, _, _, _, _, expansionID = ItemInfo(link)
    if not quality or quality < 2 or quality > 4 or not DE_EQUIP[equipLoc] then return nil end
    local results
    if not OxedHub.IsMainline and SS.GetClassicDisenchantResults then
        results = SS:GetClassicDisenchantResults(quality, ilvl, equipLoc)
    elseif SS.GetDisenchantResults then
        results = SS:GetDisenchantResults(quality, expansionID)
    end
    if not results then return nil end
    local total = 0
    for _, r in ipairs(results) do
        local mat = SS.MATS and SS.MATS[r.matKey]
        local price = mat and AuctionPrice(mat.id)
        if not price then return nil end
        total = total + price * (r.minQty + r.maxQty) / 2 * (r.chance or 1)
    end
    return math.floor(total * AH_CUT)
end

-- Best way to turn one crafted item into gold: value and "AH" / "DE" / "Vendor".
local function BestSale(link)
    if not link then return nil end
    local itemID = ItemIDFromLink(link)
    local best, how
    local ah = AuctionPrice(itemID)
    if ah then best, how = math.floor(ah * AH_CUT), "AH" end
    local vendor = select(11, ItemInfo(link))
    if vendor and vendor > 0 and (not best or vendor > best) then best, how = vendor, "Vendor" end
    if settings.useDisenchant then
        local de = DisenchantValue(link)
        if de and (not best or de > best) then best, how = de, "DE" end
    end
    return best, how
end

-- reagents: { { itemID, count, have } ... }. Returns cost, or nil if a price is missing.
local function ReagentCost(reagents)
    local total, missing = 0, false
    for _, r in ipairs(reagents) do
        local need = r.count
        if settings.ownMatsFree and r.have then need = math.max(0, need - r.have) end
        r.unit, r.source = ReagentPrice(r.itemID)   -- kept for the tooltip
        r.need = need
        if need > 0 then
            if r.unit then total = total + r.unit * need else missing = true end
        end
    end
    if missing then return nil end
    return total
end

-- ── Reading recipes ─────────────────────────────────────────────────────────

local function Evaluate(entry)
    local each = entry.made or 1
    local sale, how = BestSale(entry.link)
    local cost = ReagentCost(entry.reagents)
    entry.sale, entry.how, entry.cost = sale and sale * each or nil, how, cost
    if sale and cost then entry.profit = sale * each - cost else entry.profit = nil end
end

-- The newer profession window (ProfessionsFrame, WoW Forever and retail).
local DIFFICULTY = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

local function ScanCraftingModern()
    local out = {}
    local ids = Call(C_TradeSkillUI.GetAllRecipeIDs)
    if type(ids) ~= "table" then return out end
    for _, recipeID in ipairs(ids) do
        local info = Call(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if type(info) == "table" and info.learned and not info.isRecraft and not info.isDummyRecipe then
            local sch = Call(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            local link = Call(C_TradeSkillUI.GetRecipeItemLink, recipeID)
            if not ItemIDFromLink(link) and type(sch) == "table" and sch.outputItemID then
                link = select(2, ItemInfo(sch.outputItemID)) or ("item:" .. sch.outputItemID)
            end
            local entry = {
                index = recipeID, recipeID = recipeID, name = info.name or "?",
                kind = DIFFICULTY[info.relativeDifficulty], available = info.numAvailable or 0,
                link = ItemIDFromLink(link) and link or nil, icon = info.icon, reagents = {}, made = 1,
            }
            if type(sch) == "table" then
                entry.made = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
                for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                    local basic = not (Enum and Enum.CraftingReagentType) or slot.reagentType == Enum.CraftingReagentType.Basic
                    local first = slot.reagents and slot.reagents[1]
                    if basic and first and first.itemID and (slot.required ~= false) then
                        entry.reagents[#entry.reagents + 1] = {
                            itemID = first.itemID, count = slot.quantityRequired or 1,
                            have = Call(GetItemCount, first.itemID),
                        }
                    end
                end
            end
            -- ⚠ On Forever numAvailable came back 0 for a recipe the window
            -- itself showed as [31]. Count it from the reagents in the bags.
            if entry.available < 1 and #entry.reagents > 0 then
                local can
                for _, r in ipairs(entry.reagents) do
                    local n = math.floor((tonumber(r.have) or 0) / math.max(1, r.count or 1))
                    if not can or n < can then can = n end
                end
                entry.available = can or 0
            end
            Evaluate(entry)
            out[#out + 1] = entry
        end
    end
    local base = Call(C_TradeSkillUI.GetBaseProfessionInfo)
    local prof = type(base) == "table" and base.professionName or nil
    if not prof then
        local child = Call(C_TradeSkillUI.GetChildProfessionInfo)
        prof = type(child) == "table" and (child.parentProfessionName or child.professionName) or nil
    end
    RememberItems(prof, out)
    return out
end

local function ScanCrafting()
    if type(GetNumTradeSkills) ~= "function" and C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs then
        return ScanCraftingModern()
    end
    local out = {}
    local n = Call(GetNumTradeSkills) or 0
    for i = 1, n do
        local name, kind, available = Call(GetTradeSkillInfo, i)
        if name and kind ~= "header" and kind ~= "subheader" then
            local entry = {
                index = i, name = name, kind = kind, available = available or 0,
                link = Call(GetTradeSkillItemLink, i),
                icon = Call(GetTradeSkillIcon, i),
                reagents = {},
            }
            local minMade, maxMade = Call(GetTradeSkillNumMade, i)
            entry.made = ((minMade or 1) + (maxMade or minMade or 1)) / 2
            for r = 1, (Call(GetTradeSkillNumReagents, i) or 0) do
                local _, _, count, have = Call(GetTradeSkillReagentInfo, i, r)
                local rlink = Call(GetTradeSkillReagentItemLink, i, r)
                entry.reagents[#entry.reagents + 1] = { itemID = ItemIDFromLink(rlink), count = count or 1, have = have }
            end
            Evaluate(entry)
            out[#out + 1] = entry
        end
    end
    RememberItems((Call(GetTradeSkillLine)), out)
    return out
end

local function ScanTrainer()
    local out = {}
    local n = Call(GetNumTrainerServices) or 0
    local step = Call(GetTrainerServiceStepIndex)
    for i = 1, n do
        -- name, status ("available" / "unavailable" / "used"): status is the
        -- SECOND value on this client.
        local name, status = Call(GetTrainerServiceInfo, i)
        if type(name) == "string" and status == "available" and i ~= step then
            local entry = {
                index = i, name = name, kind = "trainer", available = 0,
                link = Call(GetTrainerServiceItemLink, i),
                icon = Call(GetTrainerServiceIcon, i),
                learnCost = Call(GetTrainerServiceCost, i),
                reagents = {}, made = 1,
            }
            for r = 1, (Call(GetTrainerServiceNumReagents, i) or 0) do
                local rname, _, count, have = Call(GetTrainerServiceReagentInfo, i, r)
                local rlink = Call(GetTrainerServiceReagentLink, i, r)
                local id = ItemIDFromLink(rlink)
                if not id and rname then id = ItemIDFromLink(select(2, ItemInfo(rname))) end
                entry.reagents[#entry.reagents + 1] = { itemID = id, count = count or 1, have = have }
            end
            -- No trainer reagent API: ask the recipe itself by its spell.
            if (not entry.link or #entry.reagents == 0) and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
                local data = Call(C_TooltipInfo and C_TooltipInfo.GetTrainerService, i)
                local spellID = type(data) == "table" and data.id or nil
                local sch = type(spellID) == "number" and Call(C_TradeSkillUI.GetRecipeSchematic, spellID, false)
                if type(sch) == "table" then
                    if not entry.link and sch.outputItemID then
                        entry.link = select(2, ItemInfo(sch.outputItemID)) or ("item:" .. sch.outputItemID)
                    end
                    entry.made = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
                    if #entry.reagents == 0 and type(sch.reagentSlotSchematics) == "table" then
                        for _, slot in ipairs(sch.reagentSlotSchematics) do
                            local first = slot.reagents and slot.reagents[1]
                            if first and first.itemID then
                                entry.reagents[#entry.reagents + 1] = {
                                    itemID = first.itemID, count = slot.quantityRequired or 1,
                                    have = Call(GetItemCount, first.itemID),
                                }
                            end
                        end
                    end
                end
            end
            if entry.link then Evaluate(entry) end
            out[#out + 1] = entry
            local skill = Call(GetTrainerServiceSkillLine, i)
            if type(skill) == "string" then RememberItems(skill, { entry }) end
        end
    end
    return out
end

local function SortList(entries)
    local shown = {}
    for _, e in ipairs(entries) do
        local keep = true
        if settings.onlyProfitable and not (e.profit and e.profit > 0) then keep = false end
        if settings.onlyCraftable and mode == "craft" and (e.available or 0) < 1 then keep = false end
        if keep then shown[#shown + 1] = e end
    end
    table.sort(shown, function(a, b)
        local pa, pb = a.profit, b.profit
        if pa and pb then if pa ~= pb then return pa > pb end
        elseif pa then return true
        elseif pb then return false end
        return a.name < b.name
    end)
    return shown
end

-- ── Scanner ─────────────────────────────────────────────────────────────────
-- A quiet price check at the auction house for the chosen professions, for
-- players without Auctionator. One exact-name query per item through the old
-- auction API (what WoW Forever has), spaced by CanSendAuctionQuery. No chat.
-- A search of the player's own stops it at once.

local Rescanner            -- set to QueueRescan below
local statusLabels = {}    -- font strings showing ScanStatus(), refreshed on change
local scan = { running = false, queue = {}, index = 0, done = 0, found = 0 }
local scanTicker
local hooked = false

local function AHOpen()
    return (AuctionFrame and AuctionFrame:IsShown()) or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or false
end

local function ScanStatus()
    if scan.running then
        return (T("Scanning the auction house: %d of %d")):format(scan.index, #scan.queue)
    end
    if settings and settings.lastScan then
        return (T("Last price scan: %s, %d prices")):format(date("%d.%m.%Y %H:%M", settings.lastScan), settings.lastScanCount or 0)
    end
    return T("Auction house not scanned yet.")
end

local function ShowStatus()
    local text = ScanStatus()
    for _, label in ipairs(statusLabels) do label:SetText(text) end
end

local function ScanQueue()
    local ids = {}
    for prof, on in pairs(settings.scanProfs) do
        if on and type(settings.recipeItems[prof]) == "table" then
            for id in pairs(settings.recipeItems[prof]) do ids[id] = true end
        end
    end
    local SS = OxedHub.Shattersight
    if settings.scanDisenchantMats and SS and SS.MATS then
        for _, mat in pairs(SS.MATS) do
            if mat.id and (mat.classic and not OxedHub.IsMainline or not mat.classic and OxedHub.IsMainline) then
                ids[mat.id] = true
            end
        end
    end
    -- Bought from vendors: no need to ask.
    for id in pairs(VENDOR_REAGENTS) do ids[id] = nil end
    for id in pairs(settings.vendorPrices) do ids[id] = nil end
    local queue = {}
    for id in pairs(ids) do queue[#queue + 1] = id end
    table.sort(queue)
    return queue
end

local function FinishScan(stopped)
    if scan.running then
        if stopped then
            print(PREFIX .. (T("Price scan stopped at %d of %d.")):format(scan.index, #scan.queue))
        else
            print(PREFIX .. (T("Price scan done: %d of %d prices found.")):format(scan.found, #scan.queue))
        end
    end
    scan.running = false
    scan.waiting = nil
    if scanTicker then scanTicker:Cancel() scanTicker = nil end
    if scan.done > 0 then
        settings.lastScan = time()
        settings.lastScanCount = 0
        for _ in pairs(settings.prices) do settings.lastScanCount = settings.lastScanCount + 1 end
    end
    ShowStatus()
    if Rescanner then Rescanner() end
end

-- WoW Forever has the newer auction house (C_AuctionHouse, as Disenchant
-- Info's scan uses); older clients have QueryAuctionItems. Ask the one present.
local function ModernAH()
    return C_AuctionHouse and type(C_AuctionHouse.SendBrowseQuery) == "function"
        and type(C_AuctionHouse.GetBrowseResults) == "function"
end

local function SendQuery(name)
    scan.ours = true
    if ModernAH() then
        pcall(C_AuctionHouse.SendBrowseQuery, {
            searchString = name, minLevel = 0, maxLevel = 0, filters = {},
            itemClassFilters = {}, sorts = {}, offset = 0, maxResults = 50,
        })
    else
        pcall(QueryAuctionItems, name, nil, nil, 0, nil, nil, false, true, nil)
    end
    scan.ours = false
end

-- Disenchant Info scanned this item in the last hour: its price is read
-- through AuctionPrice already, so asking again only costs time. Looked at
-- when the item's turn comes, since both scans start together.
local function FreshFromDisenchant(id)
    local SS = OxedHub.Shattersight
    local entry = SS and SS.db and SS.db.prices and SS.db.prices[id]
    return type(entry) == "table" and entry.source == "scan" and type(entry.timestamp) == "number"
        and time() - entry.timestamp < 3600 or false
end

local function SendNext()
    while scan.index < #scan.queue do
        scan.index = scan.index + 1
        local id = scan.queue[scan.index]
        local name = ItemInfo(id)
        if FreshFromDisenchant(id) then
            scan.found = scan.found + 1   -- its price is known, just not asked twice
        elseif type(name) == "string" then
            scan.waiting, scan.sentAt = id, GetTime()
            SendQuery(name)
            ShowStatus()
            return
        elseif C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, id)
        end
    end
    FinishScan()
end

local function OtherScanRunning()
    local SS = OxedHub.Shattersight
    return SS and SS.IsScanning and SS:IsScanning() or false
end

local function ScanTick()
    if not scan.running then return end
    if not AHOpen() then FinishScan(true) return end
    if scan.waiting then
        if GetTime() - (scan.sentAt or 0) > 6 then scan.waiting = nil end  -- no answer: move on
        return
    end
    -- Disenchant Info's own scan reads the same results: wait for it.
    if OtherScanRunning() then return end
    if ModernAH() then
        SendNext()
    else
        local ok, can = pcall(CanSendAuctionQuery)
        if ok and can then SendNext() end
    end
end

local function Store(id, unit)
    if not unit or unit <= 0 then return end
    settings.prices[id] = { p = math.floor(unit + 0.5), t = time() }
    scan.found = scan.found + 1
end

-- Results for one of our queries: cheapest price per single item.
local function ReadResults(event)
    local id = scan.waiting
    if not scan.running or not id then return end
    scan.waiting = nil
    scan.done = scan.done + 1
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
        for _, r in ipairs(ok and type(results) == "table" and results or {}) do
            if r and r.itemKey and r.itemKey.itemID == id then
                Store(id, r.minPrice)
                break
            end
        end
        return
    end
    local best
    for i = 1, (Call(GetNumAuctionItems, "list") or 0) do
        -- name, texture, count, quality, canUse, level, levelColHeader, minBid,
        -- minIncrement, buyoutPrice, bidAmount, highBidder, bidderFullName,
        -- owner, ownerFullName, saleStatus, itemId (pcall's ok comes first)
        local info = { pcall(GetAuctionItemInfo, "list", i) }
        local count, buyout, itemID = info[4], info[11], info[18]
        if info[1] and itemID == id and type(buyout) == "number" and buyout > 0
            and type(count) == "number" and count > 0 then
            local unit = buyout / count
            if not best or unit < best then best = unit end
        end
    end
    Store(id, best)
end

local function HookPlayerSearches()
    if hooked then return end
    hooked = true
    -- The player's own search ends our scan, so their results stay theirs.
    -- ⚠ Disenchant Info's scan sends the same browse queries. Taken for the
    -- player's, it stopped this scan at 0 every time both started together;
    -- ScanTick already waits for it to finish.
    local function Theirs()
        if scan.running and not scan.ours and not OtherScanRunning() then FinishScan(true) end
    end
    if ModernAH() then
        hooksecurefunc(C_AuctionHouse, "SendBrowseQuery", Theirs)
        if C_AuctionHouse.SendSearchQuery then hooksecurefunc(C_AuctionHouse, "SendSearchQuery", Theirs) end
    elseif type(QueryAuctionItems) == "function" then
        hooksecurefunc("QueryAuctionItems", Theirs)
    end
end

local function StartScan(manual)
    if scan.running or not settings then return end
    if not ModernAH() and type(QueryAuctionItems) ~= "function" then
        if manual then print(PREFIX .. T("This auction house cannot be scanned by the module. Auctionator prices are used instead.")) end
        return
    end
    if not AHOpen() then
        if manual then print(PREFIX .. T("Open the auction house first.")) end
        return
    end
    HookPlayerSearches()
    local queue = ScanQueue()
    if #queue == 0 then
        if manual or not scan.hinted then
            scan.hinted = true
            print(PREFIX .. T("Nothing to scan yet. Open a profession window once so the module learns its recipes."))
        end
        return
    end
    scan.queue, scan.index, scan.done, scan.found, scan.waiting = queue, 0, 0, 0, nil
    scan.running = true
    scanTicker = C_Timer.NewTicker(0.3, ScanTick)
    print(PREFIX .. (T("Scanning %d items quietly. Searching yourself stops it.")):format(#queue))
    ShowStatus()
end

local function AutoScan()
    if not settings.autoScan then return end
    if Auctionator and settings.skipWithAuctionator then return end
    if settings.lastScan and time() - settings.lastScan < 20 * 60 then return end
    C_Timer.After(1.5, function() if active then StartScan(false) end end)
end


-- ── Display ─────────────────────────────────────────────────────────────────

local function Money(copper)
    if not copper then return "|cFF888888?|r" end
    local neg = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local text
    if g > 0 then text = ("%d|cFFFFD700g|r %d|cFFC0C0C0s|r"):format(g, s)
    elseif s > 0 then text = ("%d|cFFC0C0C0s|r %d|cFFCD7F32c|r"):format(s, c)
    else text = ("%d|cFFCD7F32c|r"):format(c) end
    return neg and ("|cFFFF4444-|r" .. text) or text
end

local KIND_COLOUR = {
    optimal = "|cFFFF8040", medium = "|cFFFFFF00", easy = "|cFF40BF40", trivial = "|cFF808080",
}

local Refresh

local function ShowRowTooltip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if e.link then GameTooltip:SetHyperlink(e.link) else GameTooltip:SetText(e.name) end
    GameTooltip:AddLine(" ")
    for _, r in ipairs(e.reagents or {}) do
        local name = r.itemID and ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.itemID))
            or ItemInfo(r.itemID)) or "?"
        local left = ("  %dx %s"):format(r.count or 1, name)
        if r.source then left = left .. " |cFF888888(" .. T(r.source) .. " " .. Money(r.unit) .. "|cFF888888)|r" end
        local right = r.unit and Money(r.unit * (r.need or r.count or 1)) or "|cFFFF4444" .. T("no price") .. "|r"
        if (r.need or 1) == 0 then right = "|cFF888888" .. T("in bags") .. "|r" end
        GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(T("Reagents cost"), Money(e.cost), 1, 0.82, 0, 1, 1, 1)
    if e.sale then
        GameTooltip:AddDoubleLine(T("Sells for") .. " (" .. T(e.how or "") .. ")", Money(e.sale), 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddDoubleLine(T("Profit"), Money(e.profit), 1, 0.82, 0, 1, 1, 1)
    if e.learnCost then GameTooltip:AddDoubleLine(T("Cost to learn"), Money(e.learnCost), 1, 0.82, 0, 1, 1, 1) end
    if not e.cost then GameTooltip:AddLine(T("A reagent has no price yet. Search it at the auction house."), 0.6, 0.6, 0.6, true) end
    if mode == "craft" then GameTooltip:AddLine(T("Click to open this recipe."), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

local function OnRowClick(row)
    local e = row.entry
    if not e or mode ~= "craft" then return end
    if e.recipeID then
        if C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, e.recipeID) end
        return
    end
    if TradeSkillFrame_SetSelection then pcall(TradeSkillFrame_SetSelection, e.index)
    elseif SelectTradeSkill then pcall(SelectTradeSkill, e.index) end
    if TradeSkillFrame_Update then pcall(TradeSkillFrame_Update) end
end

local function BuildPanel()
    if panel then return end
    local f = CreateFrame("Frame", "OxedHubCraftProfitPanel", UIParent, "BackdropTemplate")
    panel = f
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    local ornate = false
    if Panel and Panel.ApplyOrnateFrame then
        local shell = CreateFrame("Frame", nil, f, "BackdropTemplate")
        shell:SetAllPoints(f)
        shell:SetFrameLevel(f:GetFrameLevel())
        shell:EnableMouse(false)
        ornate = pcall(Panel.ApplyOrnateFrame, shell, T("Craft Profit"), 0.96)
    end
    if not ornate then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 0.9)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText(T("Craft Profit"))
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(#list - ROWS, offset - delta * 3))
        Refresh()
    end)

    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 20, -38)
    f.sub:SetPoint("TOPRIGHT", -20, -38)
    f.sub:SetJustifyH("LEFT")

    local header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPRIGHT", -24, -56)
    header:SetText(T("Profit"))
    f.header = header

    f.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -70 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -70 - (i - 1) * ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 2, 0)
        row.profit = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.profit:SetPoint("RIGHT", -4, 0)
        row.profit:SetJustifyH("RIGHT")
        row.how = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.how:SetPoint("RIGHT", row.profit, "LEFT", -6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row.how, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", ShowRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", OnRowClick)
        f.rows[i] = row
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER", 0, 0)
    f.empty:SetWidth(W - 60)

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.footer:SetPoint("BOTTOMLEFT", 20, 16)
    f.footer:SetPoint("BOTTOMRIGHT", -20, 16)
    f.footer:SetJustifyH("LEFT")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("BOTTOMLEFT", 20, 32)
    f.status:SetPoint("BOTTOMRIGHT", -20, 32)
    f.status:SetJustifyH("LEFT")
    statusLabels[#statusLabels + 1] = f.status
    f.status:SetText(ScanStatus())
    f:Hide()
end

Refresh = function()
    if not panel or not panel:IsShown() then return end
    local f = panel
    local craftable, profitable = 0, 0
    for _, e in ipairs(list) do
        if (e.available or 0) > 0 then craftable = craftable + 1 end
        if e.profit and e.profit > 0 then profitable = profitable + 1 end
    end
    if mode == "craft" then
        f.sub:SetText((T("%d recipes earn gold, %d you can make now.")):format(profitable, craftable))
    else
        f.sub:SetText((T("%d recipes to learn here, %d of them earn gold.")):format(#list, profitable))
    end
    for i, row in ipairs(f.rows) do
        local e = list[offset + i]
        row.entry = e
        if e then
            row.icon:SetTexture(e.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local colour = KIND_COLOUR[e.kind] or "|cFFFFFFFF"
            local label = colour .. e.name .. "|r"
            if mode == "craft" and (e.available or 0) > 0 then
                label = label .. " |cFF00FF00[" .. e.available .. "]|r"
            elseif mode == "trainer" and e.learnCost then
                label = label .. " |cFF888888(" .. Money(e.learnCost) .. "|cFF888888)|r"
            end
            row.name:SetText(label)
            row.how:SetText(e.how and T(e.how) or "")
            local p = e.profit
            row.profit:SetText(p and ((p >= 0 and "|cFF00FF00+|r" or "") .. Money(p)) or Money(nil))
            row:Show()
        else
            row:Hide()
        end
    end
    f.empty:SetShown(#list == 0)
    f.empty:SetText(T("Nothing to show. Untick a filter in the options, or open the categories in the profession window."))
    local range = #list > ROWS and (T("%d-%d of %d")):format(offset + 1, math.min(#list, offset + ROWS), #list) or ""
    f.footer:SetText(range .. (range ~= "" and "   " or "") .. T("[n] = can make now. Prices after the 5% auction cut."))
end

local function Rescan()
    if not active or not panel or not panel:IsShown() then return end
    local entries = mode == "craft" and ScanCrafting() or ScanTrainer()
    list = SortList(entries)
    offset = math.max(0, math.min(offset, #list - ROWS))
    Refresh()
end

local function QueueRescan()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function()
        refreshQueued = false
        Rescan()
    end)
end
Rescanner = QueueRescan

local lastAttach, lastDetach   -- for /cprofit debug
local function Attach(newMode, host)
    if not active or not host then return end
    BuildPanel()
    if mode ~= newMode then offset = 0 end
    mode = newMode
    panel:ClearAllPoints()
    -- Right of the window; on its left when there is no room on the right.
    local right = host.GetRight and host:GetRight()
    local screen = UIParent:GetRight()
    if right and screen and right * (host:GetEffectiveScale() / UIParent:GetEffectiveScale()) + W > screen then
        panel:SetPoint("TOPRIGHT", host, "TOPLEFT", 2, 0)
    else
        panel:SetPoint("TOPLEFT", host, "TOPRIGHT", -2, 0)
    end
    panel:SetFrameLevel(math.max(panel:GetFrameLevel(), (host:GetFrameLevel() or 0) + 5))
    panel:Show()
    lastAttach = newMode .. " at " .. date("%H:%M:%S")
    Rescan()
end

local function Detach(whichMode)
    if panel and mode == whichMode then
        panel:Hide()
        lastDetach = whichMode .. " at " .. date("%H:%M:%S")
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

local HookCraftFrame   -- defined below the event handler

-- The profession window: the newer ProfessionsFrame or the old TradeSkillFrame.
local function CraftHost()
    return ProfessionsFrame or TradeSkillFrame
end
local watcher = CreateFrame("Frame")
local EVENTS = {
    "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
    "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED",
    "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED", "MERCHANT_SHOW",
    "ADDON_LOADED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
}

local function IsProfessionTrainer()
    if IsTradeskillTrainer then
        local ok, yes = pcall(IsTradeskillTrainer)
        if ok then return yes and true or false end
    end
    return false
end

watcher:SetScript("OnEvent", function(_, event)
    if not active then return end
    if event == "TRADE_SKILL_SHOW" then
        HookCraftFrame()
        -- The window may be built by this same event: look again next frame.
        C_Timer.After(0, function()
            HookCraftFrame()
            local host = CraftHost()
            if active and settings.showCrafting and host and host:IsShown() then
                Attach("craft", host)
            end
        end)
    elseif event == "TRADE_SKILL_CLOSE" then
        Detach("craft")
    elseif event == "TRAINER_SHOW" then
        if settings.showTrainer and IsProfessionTrainer() then
            Attach("trainer", ClassTrainerFrame)
        end
    elseif event == "ADDON_LOADED" then
        HookCraftFrame()
    elseif event == "MERCHANT_SHOW" then
        RecordMerchant()
    elseif event == "AUCTION_HOUSE_SHOW" then
        AutoScan()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if scan.running then FinishScan(true) end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" or event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        ReadResults(event)
    elseif event == "TRAINER_CLOSED" then
        Detach("trainer")
    else
        QueueRescan()
    end
end)

-- Follow the profession window itself too, in case its events come late.
local craftHooked = {}
HookCraftFrame = function()
    for _, host in ipairs({ ProfessionsFrame or false, TradeSkillFrame or false }) do
        if host and not craftHooked[host] and host.HookScript then
            craftHooked[host] = true
            host:HookScript("OnShow", function(self)
                if active and settings.showCrafting then Attach("craft", self) end
            end)
            host:HookScript("OnHide", function() Detach("craft") end)
        end
    end
end

local function Start()
    if active then return end
    HookCraftFrame()
    active = true
    for _, e in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, e) end
    local host = CraftHost()
    if host and host:IsShown() and settings.showCrafting then
        Attach("craft", host)
    end
end

local function Stop()
    active = false
    if scan.running then FinishScan(true) end
    watcher:UnregisterAllEvents()
    if panel then panel:Hide() end
end

-- ── Options ─────────────────────────────────────────────────────────────────

-- "How it works": a window of its own, the options one is tall enough already.
local aboutWindow
local ABOUT = {
    "Beside a profession window, or a profession trainer, a list of every recipe sorted by the gold it earns. Every profession works, Cooking and First Aid too.",
    "Open each profession window once: the module learns its recipes and their reagents, and from then on their prices are scanned.",
    "Profit is what the item sells for, minus what its reagents cost. The best way to sell is used: the auction house after its 5% cut, a vendor, or disenchanting (when that option is on). \"Vendor\" means a vendor pays the most.",
    "A \"?\" means a price is missing: the item or one of its reagents has not been seen at the auction house yet. It fills in after the next scan, if anyone sells it.",
    "[n] after a name is how many you can make now with the reagents in your bags. With \"Reagents in your bags cost nothing\" on, those reagents are free in the sum.",
    "Where prices come from: the module's own scan if under a day old, then Disenchant Info, then Auctionator, then an older scan of its own. Reagents sold by vendors use the vendor's price.",
    "The scan starts by itself when the auction house opens, at most every 20 minutes, one quiet search per item. Searching yourself stops it. It waits while Disenchant Info scans, and skips the dusts and essences Disenchant Info priced in the last hour.",
    "Commands: /cprofit opens the options, /cprofit scan scans now (at the auction house), /cprofit show brings the list back beside the profession window.",
}

local function ShowAbout()
    local API = OxedHub.ModuleAPI
    if not API then return end
    if not aboutWindow then
        local w = API:CreateOptionsWindow("Craft Profit: how it works", 470, 640)
        for _, text in ipairs(ABOUT) do w:AddNote(text) end
        aboutWindow = w
    end
    aboutWindow:Show()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local profs = {}
        for prof in pairs(settings.recipeItems) do profs[#profs + 1] = prof end
        table.sort(profs)
        local o = API:CreateOptionsWindow("Craft Profit", 470, 560 + math.max(1, #profs) * 28)
        local function Again() QueueRescan() end
        o:AddCheckbox(settings, "showCrafting", "List beside the profession window")
        o:AddCheckbox(settings, "showTrainer", "List beside a profession trainer")
        o:AddCheckbox(settings, "onlyProfitable", "Only recipes that earn gold", nil, Again)
        o:AddCheckbox(settings, "onlyCraftable", "Only recipes you have reagents for", nil, Again)
        o:AddCheckbox(settings, "useDisenchant", "Count disenchanting as a way to sell",
            "Uses the values from Disenchant Info.", Again)
        o:AddCheckbox(settings, "ownMatsFree", "Reagents in your bags cost nothing",
            "Off: everything is priced as if bought.", Again)
        o:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            if minimapIcon then minimapIcon:Apply(settings.enabled == true) end
        end)
        o:AddCheckbox(settings, "autoScan", "Scan prices quietly when the auction house opens",
            "At most every 20 minutes. Searching yourself stops it.")
        o:AddCheckbox(settings, "skipWithAuctionator", "Do not scan when Auctionator is installed")
        o:AddCheckbox(settings, "scanDisenchantMats", "Also scan dusts, essences and shards")
        o:AddNote("Professions to scan:")
        if #profs == 0 then
            o:AddNote("Open a profession window once and it is listed here.")
        end
        for _, prof in ipairs(profs) do
            local count = 0
            for _ in pairs(settings.recipeItems[prof]) do count = count + 1 end
            o:AddCheckbox(settings.scanProfs, prof, prof .. " |cFF888888(" .. count .. ")|r")
        end

        local row = CreateFrame("Frame", nil, o)
        row:SetSize(420, 24)
        row:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 2)
        local scanBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        scanBtn:SetSize(130, 22)
        scanBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
        scanBtn:SetText(L["Scan Now"])
        scanBtn:SetScript("OnClick", function() StartScan(true) end)
        local clear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        clear:SetSize(130, 22)
        clear:SetPoint("LEFT", scanBtn, "RIGHT", 8, 0)
        clear:SetText(L["Forget Prices"])
        clear:SetScript("OnClick", function()
            wipe(settings.prices)
            settings.lastScan, settings.lastScanCount = nil, nil
            ShowStatus()
            QueueRescan()
        end)
        local about = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        about:SetSize(140, 22)
        about:SetPoint("LEFT", clear, "RIGHT", 8, 0)
        about:SetText(T("How it works"))
        about:SetScript("OnClick", ShowAbout)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(scanBtn)
            OxedHub.UI:ApplyRedButtonStyle(clear)
            OxedHub.UI:ApplyRedButtonStyle(about)
        end
        o.cursorY = o.cursorY - 32
        local status = o:AddNote(ScanStatus())
        statusLabels[#statusLabels + 1] = status

        o:AddModuleLinks("Disenchant values:", { "shattersight" })
        o:AddNote("Prices: Auctionator if installed, otherwise the module's own scan. Vendor reagents use the vendor's price.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

-- /cprofit debug: what this client answers for the first trainer services.
SLASH_OXEDCRAFTPROFIT1 = "/cprofit"
SlashCmdList["OXEDCRAFTPROFIT"] = function(message)
    message = (message or ""):lower()
    if message == "scan" then
        StartScan(true)
    elseif message == "show" then
        local host = CraftHost()
        host = host and host:IsShown() and host
        if host then Attach("craft", host) else print(PREFIX .. T("Open a profession window first.")) end
    elseif message == "debug" then
        local tf = CraftHost()
        print(PREFIX .. ("active=%s showCrafting=%s window=%s shown=%s"):format(tostring(active),
            tostring(settings and settings.showCrafting), tostring(tf and tf:GetName()), tostring(tf and tf:IsShown())))
        if tf then
            print(("  window: left=%s top=%s right=%s width=%s scale=%s"):format(tostring(tf:GetLeft()), tostring(tf:GetTop()),
                tostring(tf:GetRight()), tostring(tf:GetWidth()), tostring(tf:GetEffectiveScale())))
        end
        print(("  panel: built=%s shown=%s visible=%s left=%s top=%s mode=%s rows=%d"):format(tostring(panel ~= nil),
            tostring(panel and panel:IsShown()), tostring(panel and panel:IsVisible()),
            tostring(panel and panel:GetLeft()), tostring(panel and panel:GetTop()), tostring(mode), #list))
        print("  last attach: " .. tostring(lastAttach) .. ", last detach: " .. tostring(lastDetach)
            .. ", trade line: " .. tostring(Call(GetTradeSkillLine)))
        local n = Call(GetNumTrainerServices) or 0
        print(PREFIX .. "trainer services: " .. tostring(n) .. ", trade skills: " .. tostring(Call(GetNumTradeSkills)))
        for i = 1, math.min(n, 5) do
            local a, b, c = Call(GetTrainerServiceInfo, i)
            print(("  %d: %s | %s | %s | link=%s | reagents=%s"):format(i, tostring(a), tostring(b), tostring(c),
                tostring(Call(GetTrainerServiceItemLink, i)), tostring(Call(GetTrainerServiceNumReagents, i))))
        end
    else
        ShowOptions()
    end
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.craftprofit
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.craftprofit = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    for _, key in ipairs({ "prices", "vendorPrices", "recipeItems", "scanProfs" }) do
        if type(config[key]) ~= "table" then config[key] = {} end
    end
    settings = config
end

local function MinimapIcon()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "craftprofit", label = L["Craft Profit"], icon = "Interface\\Icons\\Trade_Engineering",
        config = settings,
        hint = L["Click or right-click: options. The list opens with a profession window."],
        onClick = function() ShowOptions() end,
    })
    return minimapIcon
end

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
        id       = "craftprofit",
        name     = "Craft Profit",
        version  = "1.2.0",
        added    = 20261121,
        updated  = 20261121.95,  -- "How it works" window, can-make count from bags, scan waits for Disenchant Info
        author   = "Oxed",
        category = "items",
        keywords = { "profession", "craft", "crafting", "profit", "gold", "trainer", "recipe", "auction", "disenchant" },
        desc     = "Beside a profession window or trainer: every recipe sorted by the gold it earns.",
        icon     = "Interface\\Icons\\Trade_Engineering",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config or settings
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
