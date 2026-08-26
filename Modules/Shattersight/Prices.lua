-- Prices.lua
-- Resolves Auction House prices for disenchant materials in Shattersight.

local addonName, OxedHub = ...

OxedHub.Shattersight = OxedHub.Shattersight or {}
local SS = OxedHub.Shattersight

local CACHE_STALE_AGE = 60 * 60 * 24 * 2  -- 2 days

function SS:GetItemPrice(itemID)
    -- 1. TradeSkillMaster
    if TSM_API then
        local itemString = "i:" .. itemID
        local price = TSM_API.GetCustomPriceValue("first(dbminbuyout,dbmarket,vendorbuy)", itemString)
        if price and price > 0 then
            return price, "tsm"
        end
    end

    -- 2. Auctionator
    if Auctionator and Auctionator.API and Auctionator.API.v1 then
        local price = Auctionator.API.v1.GetAuctionPriceByItemID("OxedHub_Shattersight", itemID)
        if price and price > 0 then
            return price, "auctionator"
        end
    end

    -- 3. Locally cached scan price
    if SS.db and SS.db.prices and SS.db.prices[itemID] then
        local entry = SS.db.prices[itemID]
        if entry.price and entry.price > 0 then
            return entry.price, "cache"
        end
    end

    return nil, nil
end

function SS:IsPriceStale(itemID)
    if SS.db and SS.db.prices and SS.db.prices[itemID] then
        local entry = SS.db.prices[itemID]
        if entry.timestamp then
            return (time() - entry.timestamp) > CACHE_STALE_AGE
        end
    end
    return false
end

function SS:SetManualPrice(itemID, copperValue)
    if not SS.db then return end
    SS.db.prices[itemID] = {
        price     = copperValue,
        timestamp = time(),
        source    = "manual",
    }
end

local scanState = {
    active       = false,
    queue        = {},
    completed    = 0,
    total        = 0,
    isAuto       = false,
    lastAutoScan = 0,
}

local function BuildScanQueue()
    local byName = {}
    for _, mat in pairs(SS.MATS) do
        if mat.id and mat.id > 0 then
            local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(mat.id))
                      or mat.name
            if name then
                if not byName[name] then byName[name] = {} end
                table.insert(byName[name], mat.id)
            end
        end
    end
    local queue = {}
    for name, ids in pairs(byName) do
        table.insert(queue, { name = name, ids = ids })
    end
    return queue
end

local function ScanNext()
    if #scanState.queue == 0 then
        scanState.active = false
        local prefix = scanState.isAuto and "Auto-scan" or "Scan"
        print(string.format("|cFF00FFFF[OxedHub Shattersight]:|r %s complete. Updated %d/%d prices.",
            prefix, scanState.completed, scanState.total))
        return
    end

    local entry = table.remove(scanState.queue, 1)
    scanState.currentName = entry.name
    scanState.currentIDs  = entry.ids

    local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, {
        searchString     = entry.name,
        minLevel         = 0,
        maxLevel         = 0,
        filters          = {},
        itemClassFilters = {},
        sorts            = {},
        offset           = 0,
        maxResults       = 50,
    })
    if not ok then
        print("|cFFFF4444[OxedHub Shattersight]|r Browse query error (" .. entry.name .. "): " .. tostring(err))
        ScanNext()
    end
end

local function OnBrowseResults()
    if not scanState.active then return end

    local wantedIDs = {}
    for _, id in ipairs(scanState.currentIDs or {}) do
        wantedIDs[id] = true
    end

    local results = C_AuctionHouse.GetBrowseResults and C_AuctionHouse.GetBrowseResults() or {}
    for _, result in ipairs(results) do
        if result and result.itemKey then
            local id = result.itemKey.itemID
            if id and wantedIDs[id] and result.minPrice and result.minPrice > 0 then
                SS.db.prices[id] = {
                    price     = result.minPrice,
                    timestamp = time(),
                    source    = "scan",
                }
                scanState.completed = scanState.completed + 1
                wantedIDs[id] = nil
            end
        end
    end

    ScanNext()
end

function SS:ScanAHPrices(isAuto)
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        if not isAuto then
            print("|cFF00FFFF[OxedHub Shattersight]:|r You must be at the Auction House to scan prices.")
            print("  Tip: Open the AH, then run |cFFFFD700/ss scan|r")
        end
        return
    end

    if scanState.active then
        if not isAuto then
            print("|cFF00FFFF[OxedHub Shattersight]:|r A scan is already in progress.")
        end
        return
    end

    local queue = BuildScanQueue()
    if #queue == 0 then
        if not isAuto then
            print("|cFF00FFFF[OxedHub Shattersight]:|r No materials with cached names to scan.")
            print("  Tip: Wait a moment after login for item names to load, then try again.")
        end
        return
    end

    local total = 0
    for _, entry in ipairs(queue) do total = total + #entry.ids end

    scanState.active    = true
    scanState.isAuto    = isAuto or false
    scanState.queue     = queue
    scanState.completed = 0
    scanState.total     = total

    local prefix = isAuto and "Auto-scanning" or "Scanning"
    print(string.format("|cFF00FFFF[OxedHub Shattersight]:|r %s prices (%d queries for %d mats)...",
        prefix, #queue, total))
    ScanNext()
end

function SS:RegisterPriceEvents(frame)
    frame:RegisterEvent("AUCTION_HOUSE_SHOW")
    frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
    frame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
end

function SS:HandlePriceEvent(event, ...)
    if event == "AUCTION_HOUSE_SHOW" then
        if SS.db and SS.db.settings and SS.db.settings.autoScan ~= false then
            local now = time()
            if (now - (scanState.lastAutoScan or 0)) >= 60 then
                scanState.lastAutoScan = now
                C_Timer.After(0.5, function()
                    if AuctionHouseFrame and AuctionHouseFrame:IsShown() and not scanState.active then
                        SS:ScanAHPrices(true)
                    end
                end)
            end
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if scanState.active then
            scanState.active = false
            scanState.queue  = {}
        end
    elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
        OnBrowseResults()
    end
end
