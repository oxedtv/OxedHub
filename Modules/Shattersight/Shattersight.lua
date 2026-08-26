-- Shattersight.lua
-- Core logic: initialization, tooltip hook, display formatting, slash commands, and ActionHub Trigger.

local addonName, OxedHub = ...

OxedHub.Shattersight = OxedHub.Shattersight or {}
local SS = OxedHub.Shattersight

local COLOR_TITLE = "|cFF00FFFF"
local COLOR_GOLD  = "|cFFFFD700"
local COLOR_WARN  = "|cFFFF8C00"
local COLOR_ERR   = "|cFFFF4444"
local COLOR_RESET = "|r"

local QUALITY_UNCOMMON = 2
local QUALITY_RARE     = 3
local QUALITY_EPIC     = 4

local QUALITY_ICONS = {
    [1] = "|cFFC0C0C0r1|r",
    [2] = "|cFFFFD700r2|r",
    [3] = "|cFF0070DDr3|r",
}

-- ---------------------------------------------------------------------------
-- SavedVariables / DB
-- ---------------------------------------------------------------------------
local function InitDB()
    if not OxedHubDB then
        OxedHubDB = {}
    end
    if not OxedHubDB.shattersight then
        OxedHubDB.shattersight = {}
    end
    local db = OxedHubDB.shattersight

    if not db.prices   then db.prices   = {} end
    if not db.settings then
        db.settings = {
            showTooltip   = true,
            showBreakdown = true,
            showSource    = false,
            autoScan      = true,
        }
    end
    if db.settings.autoScan == nil then db.settings.autoScan = true end
    if db.settings.showTooltip == nil then db.settings.showTooltip = true end
    if db.settings.showBreakdown == nil then db.settings.showBreakdown = true end

    if not db.chars then db.chars = {} end
    local charName  = UnitName("player") or "Unknown"
    local realmName = GetRealmName()     or "Unknown"
    local charKey   = realmName .. "-" .. charName
    if not db.chars[charKey] then db.chars[charKey] = {} end
    local charDb = db.chars[charKey]
    if not charDb.skillCache then charDb.skillCache = {} end
    if not charDb.tracking   then charDb.tracking   = {} end

    SS.db     = db
    SS.charDb = charDb
end

-- ---------------------------------------------------------------------------
-- Gold formatting
-- ---------------------------------------------------------------------------
function SS:FormatGold(copper)
    if not copper or copper <= 0 then
        return COLOR_ERR .. "N/A" .. COLOR_RESET
    end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100

    if gold > 0 then
        return string.format("%s%dg%s %s%ds%s %s%dc%s",
            COLOR_GOLD,   gold,   COLOR_RESET,
            "|cFFC0C0C0", silver, COLOR_RESET,
            "|cFFCD7F32", cop,    COLOR_RESET)
    elseif silver > 0 then
        return string.format("%s%ds%s %s%dc%s",
            "|cFFC0C0C0", silver, COLOR_RESET,
            "|cFFCD7F32", cop,    COLOR_RESET)
    else
        return string.format("%s%dc%s", "|cFFCD7F32", cop, COLOR_RESET)
    end
end

-- ---------------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------------
local function IsDisenchantableEquipLoc(equipLoc)
    return equipLoc and SS.EQUIPPABLE and SS.EQUIPPABLE[equipLoc] == true
end

local function GetMatName(mat)
    if mat.id and mat.id > 0 then
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(mat.id)
        if name then return name end
        local fallbackName = GetItemInfo(mat.id)
        if fallbackName then return fallbackName end
    end
    return mat.name or ("Item #" .. (mat.id or "?"))
end

-- ---------------------------------------------------------------------------
-- Core tooltip builder
-- ---------------------------------------------------------------------------
local function BuildDisenchantLines(tooltip, data)
    if not tooltip then return end
    if not SS.db or not SS.db.settings or not SS.db.settings.showTooltip then return end

    local itemLink
    if tooltip.GetItem then
        local _, link = tooltip:GetItem()
        itemLink = link
    end
    if not itemLink and data then
        itemLink = data.hyperlink or data.link or data.itemLink
        if not itemLink and (data.id or data.itemID) then
            local _, link = GetItemInfo(data.id or data.itemID)
            itemLink = link
        end
    end

    if SS.tooltipDebug then
        SS.tooltipDebug = false
        SS:ClearDebugOutput()
        SS:DebugOutput("=== /ss tooltipdebug ===")
        SS:DebugOutput("tooltip type : " .. tostring(type(tooltip)))
        SS:DebugOutput("itemLink resolved: " .. tostring(itemLink))
        if data then
            pcall(function()
                for k, v in pairs(data) do
                    SS:DebugOutput(string.format("  .%s = %s (%s)", tostring(k), tostring(v), type(v)))
                end
            end)
        end
    end

    if not itemLink then return end

    -- Mat price display when hovering directly over dust/shards/crystals
    local matItemID = C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(itemLink)
    if matItemID and SS.MATS_BY_ID and SS.MATS_BY_ID[matItemID] then
        local price, source = SS:GetItemPrice(matItemID)
        local stale = (source == "cache") and SS:IsPriceStale(matItemID)

        local stackCount = 1
        if IsShiftKeyDown and IsShiftKeyDown() then
            local owner = tooltip:GetOwner()
            if owner and owner.GetParent and owner.GetID then
                local bag  = owner:GetParent():GetID()
                local slot = owner:GetID()
                if bag and slot and bag >= 0 and bag <= 5 then
                    local info = C_Container.GetContainerItemInfo(bag, slot)
                    if info and info.stackCount and info.stackCount > 1 then
                        stackCount = info.stackCount
                    end
                end
            end
        end

        tooltip:AddLine(" ")
        if price then
            local staleTag = stale and (" " .. COLOR_WARN .. "[stale]" .. COLOR_RESET) or ""
            local srcTag   = (not stale and SS.db.settings.showSource and source)
                and (" |cFF888888[" .. source .. "]|r") or ""

            tooltip:AddDoubleLine(
                COLOR_TITLE .. "AH Price" .. COLOR_RESET,
                SS:FormatGold(price) .. staleTag .. srcTag,
                1, 1, 1, 1, 1, 1)

            if stackCount > 1 then
                tooltip:AddDoubleLine(
                    COLOR_TITLE .. "Stack Value" .. COLOR_RESET
                        .. string.format(" |cFF888888(x%d)|r", stackCount),
                    SS:FormatGold(price * stackCount),
                    1, 1, 1, 1, 1, 1)
            end
        else
            tooltip:AddDoubleLine(
                COLOR_TITLE .. "AH Price" .. COLOR_RESET,
                COLOR_ERR .. "No price — run /ss scan" .. COLOR_RESET,
                1, 1, 1, 1, 1, 1)
        end
        tooltip:Show()
        return
    end

    local _, _, quality, _, _, _, _, _, equipLoc, _, sellPrice, _, _, _, expansionID =
        C_Item.GetItemInfo(itemLink)
    if not quality then return end

    if quality < QUALITY_UNCOMMON or quality > QUALITY_EPIC then return end
    if not IsDisenchantableEquipLoc(equipLoc) then return end

    local results = SS:GetDisenchantResults(quality, expansionID)
    if not results or #results == 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine(COLOR_TITLE .. "Disenchanting" .. COLOR_RESET
            .. "  |cFF888888(expansion not supported)|r")
        tooltip:Show()
        return
    end

    local trackedRates, trackedAttempts, rateSource = SS:GetTrackedRates(quality, expansionID)
    local matList    = {}
    local dataSource = "observed"

    if trackedRates then
        for _, r in ipairs(trackedRates) do
            table.insert(matList, {
                itemID             = r.itemID,
                avgQty             = r.avgQty,
                dropChance         = r.dropChance,
                avgQtyWhenReceived = r.avgQtyWhenReceived,
            })
        end
    else
        dataSource = "static"
        for _, r in ipairs(results) do
            local matDef = SS.MATS[r.matKey]
            if matDef and matDef.id then
                local avgQtyWhenReceived = (r.minQty + r.maxQty) / 2
                local avgQty = avgQtyWhenReceived * (r.chance or 1.0)
                table.insert(matList, {
                    itemID             = matDef.id,
                    avgQty             = avgQty,
                    dropChance         = r.chance,
                    avgQtyWhenReceived = avgQtyWhenReceived,
                    mat                = matDef,
                    result             = r,
                })
            end
        end
    end

    local lines         = {}
    local totalCopper   = 0
    local allHavePrices = true
    local anyStale      = false

    for _, entry in ipairs(matList) do
        local itemID = entry.itemID
        local avgQty = entry.avgQty
        local mat = entry.mat or (SS.MATS_BY_ID and SS.MATS_BY_ID[itemID])

        local name
        if mat then
            name = GetMatName(mat)
        else
            name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
                or GetItemInfo(itemID)
                or ("Item #" .. itemID)
        end

        local qualityIcon = mat and mat.qualityTier and QUALITY_ICONS[mat.qualityTier]
        if qualityIcon then
            name = name .. " " .. qualityIcon
        end

        local price, source = SS:GetItemPrice(itemID)
        local stale = (source == "cache") and SS:IsPriceStale(itemID)
        if stale then anyStale = true end

        local leftText, rightText

        if SS.db.settings.showBreakdown then
            if dataSource == "observed" then
                if entry.dropChance then
                    leftText = string.format("  %s  |cFFFFFFFF%.0f%%|r · |cFFFFFFFFavg %.1fx|r",
                        name, entry.dropChance * 100, entry.avgQtyWhenReceived)
                else
                    leftText = string.format("  %s  |cFFFFFFFFavg %.2fx|r", name, avgQty)
                end
            else
                local result = entry.result
                if result.minQty == result.maxQty then
                    leftText = string.format("  %s x%d", name, result.minQty)
                else
                    leftText = string.format("  %s x%d-%d", name, result.minQty, result.maxQty)
                end
                if result.chance and result.chance < 1.0 then
                    leftText = leftText .. string.format(" (%.0f%%)", result.chance * 100)
                end
            end
        else
            leftText = string.format("  %s", name)
        end

        if price then
            local expectedCopper = math.floor(avgQty * price)
            totalCopper = totalCopper + expectedCopper
            local displayCopper = entry.avgQtyWhenReceived
                and math.floor(entry.avgQtyWhenReceived * price)
                or  expectedCopper
            rightText = SS:FormatGold(displayCopper)
            if stale then
                rightText = rightText .. " " .. COLOR_WARN .. "[stale]" .. COLOR_RESET
            elseif SS.db.settings.showSource and source then
                rightText = rightText .. " " .. "|cFF888888[" .. source .. "]" .. COLOR_RESET
            end
        else
            allHavePrices = false
            rightText = COLOR_ERR .. "No price" .. COLOR_RESET
        end

        table.insert(lines, { left = leftText, right = rightText })
    end

    tooltip:AddLine(" ")
    tooltip:AddLine(COLOR_TITLE .. "Disenchanting" .. COLOR_RESET)

    if SS.db.settings.showBreakdown then
        for _, line in ipairs(lines) do
            tooltip:AddDoubleLine(line.left, line.right, 1, 1, 1, 1, 1, 1)
        end
    end

    if totalCopper > 0 then
        tooltip:AddLine("|cFF555555" .. string.rep("-", 50) .. "|r")
        local totalLabel = "  " .. COLOR_GOLD .. "Expected Value" .. COLOR_RESET
        tooltip:AddDoubleLine(totalLabel, SS:FormatGold(totalCopper), 1, 1, 1, 1, 1, 1)

        if sellPrice and sellPrice > 0 then
            local diff = totalCopper - sellPrice
            if diff > 0 then
                tooltip:AddDoubleLine(
                    "  |cFF00FF00Disenchant Profit|r",
                    "|cFF00FF00+" .. SS:FormatGold(diff) .. "|r",
                    1, 1, 1, 1, 1, 1)
            elseif diff < 0 then
                tooltip:AddDoubleLine(
                    "  |cFFFF4444Vendor is Better|r",
                    "|cFFFF4444+" .. SS:FormatGold(-diff) .. "|r",
                    1, 1, 1, 1, 1, 1)
            end
        end
    end

    if dataSource == "static" then
        tooltip:AddLine("  |cFF888888Estimated baseline (disenchant to build data)|r")
    elseif rateSource == "community" then
        tooltip:AddLine(string.format("  |cFF888888Community data (%d disenchant(s))|r", trackedAttempts))
    else
        tooltip:AddLine(string.format("  |cFF888888Based on %d disenchant(s)|r", trackedAttempts))
    end

    if not allHavePrices then
        tooltip:AddLine("  " .. COLOR_WARN .. "Visit the AH and /ss scan for prices" .. COLOR_RESET)
    elseif anyStale then
        tooltip:AddLine("  " .. COLOR_WARN .. "Prices may be outdated — run /ss scan" .. COLOR_RESET)
    end

    tooltip:Show()
end

local function HookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            BuildDisenchantLines(tooltip, data)
        end)
    else
        GameTooltip:HookScript("OnTooltipSetItem", BuildDisenchantLines)
        ItemRefTooltip:HookScript("OnTooltipSetItem", BuildDisenchantLines)
    end
end

-- ---------------------------------------------------------------------------
-- Event Frame
-- ---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "OxedHub_ShattersightFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == addonName then
        InitDB()
        HookTooltips()
        SS:RegisterPriceEvents(self)
        SS:RegisterTrackingEvents(self)
        SS:PreloadMatNames()
    elseif event == "PLAYER_LOGIN" then
        SS:PrintLoginSummary()
    else
        SS:HandlePriceEvent(event, arg1, ...)
        SS:HandleTrackingEvent(event, arg1, ...)
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_OXEDHUB_SHATTERSIGHT1 = "/shattersight"
SLASH_OXEDHUB_SHATTERSIGHT2 = "/ss"
SLASH_OXEDHUB_SHATTERSIGHT3 = "/dea"

SlashCmdList["OXEDHUB_SHATTERSIGHT"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.*)")
    cmd = (cmd or ""):lower()

    if cmd == "scan" then
        SS:ScanAHPrices()
    elseif cmd == "autoscan" then
        SS.db.settings.autoScan = not SS.db.settings.autoScan
        local state = SS.db.settings.autoScan and "|cFF00FF00enabled|r" or "|cFFFF4444disabled|r"
        print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Auto AH scan " .. state)
    elseif cmd == "toggle" then
        SS.db.settings.showTooltip = not SS.db.settings.showTooltip
        local state = SS.db.settings.showTooltip and "|cFF00FF00enabled|r" or "|cFFFF4444disabled|r"
        print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Tooltip " .. state)
    elseif cmd == "breakdown" then
        SS.db.settings.showBreakdown = not SS.db.settings.showBreakdown
        local state = SS.db.settings.showBreakdown and "|cFF00FF00enabled|r" or "|cFFFF4444disabled|r"
        print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Per-mat breakdown " .. state)
    elseif cmd == "source" then
        SS.db.settings.showSource = not SS.db.settings.showSource
        local state = SS.db.settings.showSource and "|cFF00FF00shown|r" or "|cFFFF4444hidden|r"
        print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Price source tag " .. state)
    elseif cmd == "setprice" then
        local itemID, goldStr = rest:match("^(%d+)%s+(%d+)g?$")
        if itemID and goldStr then
            local copper = tonumber(goldStr) * 10000
            SS:SetManualPrice(tonumber(itemID), copper)
            print(string.format("%s[OxedHub Shattersight]:%s Set price for item %d to %s",
                COLOR_TITLE, COLOR_RESET, tonumber(itemID), SS:FormatGold(copper)))
        else
            print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Usage: /ss setprice <itemID> <gold>")
        end
    elseif cmd == "stats" then
        SS:ToggleStatsFrame()
    elseif cmd == "trackdebug" then
        SS:ToggleTrackDebug()
    elseif cmd == "skillcheck" then
        SS:SkillCheck()
    elseif cmd == "clearstats" then
        SS:ClearTrackingData()
    elseif cmd == "prices" then
        print(COLOR_TITLE .. "[OxedHub Shattersight] Price diagnostics:" .. COLOR_RESET)
        print("  TSM_API present: " .. tostring(TSM_API ~= nil))

        local entries = {}
        for key, mat in pairs(SS.MATS) do
            if mat.id and mat.id > 0 then
                local expID = (key:sub(1, 4) == "TWW_") and SS.EXP_TWW or SS.EXP_MIDNIGHT
                local name  = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(mat.id))
                           or mat.name or ("Item #" .. mat.id)
                entries[#entries + 1] = { mat = mat, expID = expID, name = name }
            end
        end

        table.sort(entries, function(a, b)
            if a.expID ~= b.expID then return a.expID < b.expID end
            if a.name  ~= b.name  then return a.name  < b.name  end
            return (a.mat.qualityTier or 0) < (b.mat.qualityTier or 0)
        end)

        local lastExpID = nil
        for _, e in ipairs(entries) do
            if e.expID ~= lastExpID then
                local label = (e.expID == SS.EXP_TWW) and "The War Within" or "Midnight"
                print(COLOR_TITLE .. "  — " .. label .. " —" .. COLOR_RESET)
                lastExpID = e.expID
            end
            local icon     = (e.mat.qualityTier and QUALITY_ICONS[e.mat.qualityTier] and
                               QUALITY_ICONS[e.mat.qualityTier] .. " ") or ""
            local price, source = SS:GetItemPrice(e.mat.id)
            local priceStr = price and SS:FormatGold(price) or (COLOR_ERR .. "nil" .. COLOR_RESET)
            print(string.format("  [%d] %s%s -> %s (src=%s)", e.mat.id, icon, e.name, priceStr, tostring(source)))
        end
    elseif cmd == "tooltipdebug" then
        SS.tooltipDebug = true
        print(COLOR_TITLE .. "[OxedHub Shattersight]:|r Hover any item — debug frame will dump info.")
        SS:ToggleDebugFrame()
    elseif cmd == "debug" then
        local itemLink
        if GameTooltip.GetItem then
            local _, link = GameTooltip:GetItem()
            itemLink = link
        end
        if not itemLink then
            print(COLOR_TITLE .. "[OxedHub Shattersight]:|r No item currently in tooltip.")
        else
            local name, _, quality, ilvl, _, _, _, _, equipLoc, _, _, _, _, _, expansionID =
                C_Item.GetItemInfo(itemLink)
            print(string.format("%s[OxedHub Shattersight]:%s item=%s quality=%s ilvl=%s expansionID=%s equipLoc=%s",
                COLOR_TITLE, COLOR_RESET,
                tostring(name), tostring(quality), tostring(ilvl),
                tostring(expansionID), tostring(equipLoc)))
            local results = quality and expansionID and SS:GetDisenchantResults(quality, expansionID)
            if results then
                print("  Disenchant results found: " .. #results .. " mat(s)")
            else
                print("  " .. COLOR_WARN .. "No disenchant data for this quality/expansionID." .. COLOR_RESET)
            end
        end
    else
        print(COLOR_TITLE .. "[OxedHub Shattersight] Commands:" .. COLOR_RESET)
        print("  /ss scan        — Scan AH mat prices (at Auction House)")
        print("  /ss autoscan    — Toggle auto-scan on AH open")
        print("  /ss toggle      — Toggle tooltip display")
        print("  /ss breakdown   — Toggle per-mat breakdown lines")
        print("  /ss source      — Toggle price source tag (TSM/cache)")
        print("  /ss setprice    — Set a mat price: /ss setprice <id> <g>")
        print("  /ss stats       — Open stats window")
        print("  /ss prices      — Show price lookup diagnostics")
        print("  /ss debug       — Show data for hovered item")
    end
end

-- ---------------------------------------------------------------------------
-- ActionHub Basic Trigger Registration
-- ---------------------------------------------------------------------------
local ShattersightTriggerHandler = {
    name = "Disenchant Insight",
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}

        local enableCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        enableCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        enableCheck:SetSize(20, 20)
        enableCheck:SetChecked(SS.db and SS.db.settings and SS.db.settings.showTooltip ~= false)
        enableCheck.text:SetText("Enable Disenchant Tooltips (Shattersight)")
        enableCheck:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            conditions.enableTooltip = isChecked
            if SS.db and SS.db.settings then
                SS.db.settings.showTooltip = isChecked
            end
            if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 30

        local breakdownCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        breakdownCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        breakdownCheck:SetSize(20, 20)
        breakdownCheck:SetChecked(SS.db and SS.db.settings and SS.db.settings.showBreakdown ~= false)
        breakdownCheck.text:SetText("Show Per-Material Drop Breakdown")
        breakdownCheck:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            conditions.showBreakdown = isChecked
            if SS.db and SS.db.settings then
                SS.db.settings.showBreakdown = isChecked
            end
            if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 30

        local autoScanCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        autoScanCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        autoScanCheck:SetSize(20, 20)
        autoScanCheck:SetChecked(SS.db and SS.db.settings and SS.db.settings.autoScan ~= false)
        autoScanCheck.text:SetText("Auto-scan Reagent Prices at Auction House")
        autoScanCheck:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            conditions.autoScan = isChecked
            if SS.db and SS.db.settings then
                SS.db.settings.autoScan = isChecked
            end
            if OxedHub.Triggers.ShowAutoSaved then OxedHub.Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 35

        local statsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        statsBtn:SetSize(160, 24)
        statsBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        statsBtn:SetText("Open Stats Window")
        statsBtn:SetScript("OnClick", function()
            SS:ToggleStatsFrame()
        end)
        yOffset = yOffset - 35

        return yOffset
    end
}

if OxedHub.Triggers and OxedHub.Triggers.RegisterEventType then
    OxedHub.Triggers:RegisterEventType("SHATTERSIGHT", ShattersightTriggerHandler)
end
