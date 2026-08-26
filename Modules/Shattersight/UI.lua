-- UI.lua
-- StatsFrame and DebugFrame for OxedHub Shattersight.

local addonName, OxedHub = ...

OxedHub.Shattersight = OxedHub.Shattersight or {}
local SS = OxedHub.Shattersight

local FRAME_W    = 460
local FRAME_H    = 500
local CONTENT_W  = 400
local PAD        = 14
local LINE_H     = 18
local SECTION_GAP = 8

local statsFrame
local linePool   = {}
local activeLines = 0

local COLOR_RESET  = "|r"
local COLOR_GOLD   = "|cFFFFD700"
local COLOR_GREY   = "|cFF888888"
local COLOR_WARN   = "|cFFFF8C00"

local QUALITY_COLORS = {
    [2] = "|cFF1EFF00",
    [3] = "|cFF0070DD",
    [4] = "|cFFA335EE",
}
local QUALITY_LABELS = {
    [2] = "Uncommon",
    [3] = "Rare",
    [4] = "Epic",
}
local QUALITY_ICONS = {
    [1] = "|cFFC0C0C0r1|r",
    [2] = "|cFFFFD700r2|r",
    [3] = "|cFF0070DDr3|r",
}

local function ResetLines()
    activeLines = 0
    for _, fs in ipairs(linePool) do
        fs:Hide()
    end
end

local function NextLine(parent)
    activeLines = activeLines + 1
    if not linePool[activeLines] then
        linePool[activeLines] = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    local fs = linePool[activeLines]
    fs:Show()
    return fs
end

local function AddHeaderLine(content, text, y)
    local fs = NextLine(content)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, y)
    fs:SetWidth(CONTENT_W - PAD * 2)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return y - LINE_H
end

local function AddDoubleLine(content, leftText, rightText, y)
    local left = NextLine(content)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", content, "TOPLEFT", PAD * 2, y)
    left:SetWidth(CONTENT_W - PAD * 2 - 110)
    left:SetJustifyH("LEFT")
    left:SetText(leftText)

    local right = NextLine(content)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD, y)
    right:SetWidth(110)
    right:SetJustifyH("RIGHT")
    right:SetText(rightText)

    return y - LINE_H
end

local function RefreshStats()
    if not statsFrame then return end

    local content = statsFrame.content
    ResetLines()

    local minSamples = SS.MIN_SAMPLES or 10
    local y = -PAD

    local expansionGroups = {
        { id = SS.EXP_MIDNIGHT, label = "Midnight" },
        { id = SS.EXP_TWW,      label = "The War Within" },
    }

    local hasAnyData = false

    for _, exp in ipairs(expansionGroups) do
        local expID = exp.id
        local expBuckets = {}

        if SS.charDb and SS.charDb.tracking then
            for key, bucket in pairs(SS.charDb.tracking) do
                if bucket.expansionID == expID then
                    table.insert(expBuckets, { key = key, bucket = bucket })
                end
            end
        end

        if #expBuckets > 0 then
            hasAnyData = true
            y = AddHeaderLine(content, "|cFF00FFFF=== " .. exp.label .. " ===|r", y)
            y = y - 4

            table.sort(expBuckets, function(a, b)
                if a.bucket.quality ~= b.bucket.quality then
                    return a.bucket.quality < b.bucket.quality
                end
                return (a.bucket.skillTier or 0) < (b.bucket.skillTier or 0)
            end)

            for _, entry in ipairs(expBuckets) do
                local bucket   = entry.bucket
                local qColor   = QUALITY_COLORS[bucket.quality] or "|cFFFFFFFF"
                local qLabel   = QUALITY_LABELS[bucket.quality] or ("Quality " .. bucket.quality)
                local attempts = bucket.attempts

                local tierStr = ""
                if bucket.skillTier ~= nil then
                    tierStr = string.format(" [Skill %d-%d]",
                        bucket.skillTier, bucket.skillTier + 24)
                end

                local progressStr
                if attempts >= minSamples then
                    progressStr = string.format("|cFF00FF00%d disenchants|r (active in tooltip)", attempts)
                else
                    progressStr = string.format("|cFFFF8C00%d/%d disenchants|r (using estimates)", attempts, minSamples)
                end

                y = AddHeaderLine(content,
                    string.format("  %s%s|r%s — %s", qColor, qLabel, tierStr, progressStr),
                    y)

                local matEntries = {}
                for itemID, total in pairs(bucket.matTotals) do
                    local dropCount = bucket.matCounts and bucket.matCounts[itemID]
                    table.insert(matEntries, {
                        itemID             = itemID,
                        total              = total,
                        avgQty             = total / attempts,
                        dropChance         = dropCount and (dropCount / attempts) or nil,
                        avgQtyWhenReceived = dropCount and (total / dropCount) or nil,
                    })
                end
                table.sort(matEntries, function(a, b) return a.avgQty > b.avgQty end)

                local groupExpectedCopper = 0

                for _, mat in ipairs(matEntries) do
                    local matDef = SS.MATS_BY_ID and SS.MATS_BY_ID[mat.itemID]
                    local name   = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(mat.itemID))
                                or (matDef and matDef.name)
                                or ("Item #" .. mat.itemID)

                    local qIcon = matDef and matDef.qualityTier
                        and QUALITY_ICONS[matDef.qualityTier]
                        and (" " .. QUALITY_ICONS[matDef.qualityTier])
                        or  ""

                    local price, source = SS:GetItemPrice(mat.itemID)
                    local stale = (source == "cache") and SS:IsPriceStale(mat.itemID)

                    local leftText
                    if mat.dropChance then
                        leftText = string.format("    %s%s  |cFFFFFFFF%.0f%%|r · |cFFFFFFFFavg %.1fx|r",
                            name, qIcon, mat.dropChance * 100, mat.avgQtyWhenReceived)
                    else
                        leftText = string.format("    %s%s  avg %.2fx", name, qIcon, mat.avgQty)
                    end

                    local rightText
                    if price then
                        local expectedMatCopper = math.floor(mat.avgQty * price)
                        groupExpectedCopper = groupExpectedCopper + expectedMatCopper
                        local displayCopper = mat.avgQtyWhenReceived
                            and math.floor(mat.avgQtyWhenReceived * price)
                            or  expectedMatCopper
                        rightText = SS:FormatGold(displayCopper)
                        if stale then
                            rightText = rightText .. " " .. COLOR_WARN .. "[stale]" .. COLOR_RESET
                        end
                    else
                        rightText = "|cFFFF4444No price|r"
                    end

                    y = AddDoubleLine(content, leftText, rightText, y)
                end

                if groupExpectedCopper > 0 then
                    y = AddDoubleLine(content,
                        "    |cFFFFD700Expected Value|r",
                        SS:FormatGold(groupExpectedCopper),
                        y)
                end

                y = y - SECTION_GAP
            end
        end
    end

    if not hasAnyData then
        y = AddHeaderLine(content, "|cFF888888No disenchant tracking data recorded yet.|r", y)
        y = AddHeaderLine(content, "|cFF888888Disenchant some equippable gear to build stats.|r", y)
        y = y - SECTION_GAP
    end

    local totalHeight = math.abs(y) + PAD
    content:SetHeight(math.max(totalHeight, FRAME_H - 80))
end

local function CreateStatsFrame()
    if statsFrame then return statsFrame end

    local f = CreateFrame("Frame", "OxedHub_ShattersightStatsFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 24,
        insets   = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("|cFF00FFFFOxedHub Shattersight|r — Disenchant Stats")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "OxedHub_ShattersightStatsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -40)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 40)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 100)
    scroll:SetScrollChild(content)
    f.content = content

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(110, 22)
    clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    clearBtn:SetText("Clear Stats")
    clearBtn:SetScript("OnClick", function()
        SS:ClearTrackingData()
        RefreshStats()
    end)

    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(110, 22)
    refreshBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        RefreshStats()
    end)

    f:SetScript("OnShow", RefreshStats)
    statsFrame = f
    return f
end

function SS:ToggleStatsFrame()
    local f = CreateStatsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end

function SS:RefreshStatsFrame()
    if statsFrame and statsFrame:IsShown() then
        RefreshStats()
    end
end

-- ---------------------------------------------------------------------------
-- Debug Frame
-- ---------------------------------------------------------------------------
local debugFrame
local debugLines = {}

local function CreateDebugFrame()
    if debugFrame then return debugFrame end

    local f = CreateFrame("Frame", "OxedHub_ShattersightDebugFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 420)
    f:SetPoint("CENTER", UIParent, "CENTER", 30, 30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 24,
        insets   = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.03, 0.03, 0.05, 0.95)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("|cFF00FFFFOxedHub Shattersight|r — Diagnostics")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

    local scroll = CreateFrame("ScrollFrame", "OxedHub_ShattersightDebugScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 14)

    local editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(460)
    editBox:SetHeight(340)
    scroll:SetScrollChild(editBox)
    f.editBox = editBox

    debugFrame = f
    return f
end

function SS:DebugOutput(msg)
    table.insert(debugLines, tostring(msg))
    if #debugLines > 200 then
        table.remove(debugLines, 1)
    end
    if debugFrame and debugFrame:IsShown() and debugFrame.editBox then
        debugFrame.editBox:SetText(table.concat(debugLines, "\n"))
    end
end

function SS:ClearDebugOutput()
    debugLines = {}
    if debugFrame and debugFrame.editBox then
        debugFrame.editBox:SetText("")
    end
end

function SS:ToggleDebugFrame()
    local f = CreateDebugFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        if f.editBox then
            f.editBox:SetText(table.concat(debugLines, "\n"))
        end
    end
end
