-- ============================================================================
-- Experience Bar (built-in OxedHub module)
-- A modern, customizable XP progression bar with completed quest XP overlays,
-- rested bonus tracking, leveling pace (XP/hour), and session statistics.
-- Completely rewritten from scratch for OxedHub.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled             = false,   -- Built-in modules always ship disabled by default
    locked              = false,
    point               = "TOP",
    relativePoint       = "TOP",
    x                   = 0,
    y                   = -65,
    width               = 580,
    height              = 24,
    fontSize            = 12,
    fontOutline         = "OUTLINE",
    texture             = "smooth",
    strata              = "MEDIUM",
    useClassColor       = false,
    showRestedBar       = true,
    showQuestBar        = true,

    -- Text toggles
    showLevelText       = true,
    showProgressText    = true,
    showPercentText     = true,
    showLevelTime       = true,
    showTotalPlayed     = false,
    showSessionTime     = true,
    showTimeToLevel     = true,
    showQuestRested     = true,

    -- Behavior & Visibility
    hideDefaultBar      = true,
    showMaxLevel        = false,
    hidePetBattle       = true,
    resetReload         = false,
}

local settings
local optionsWindow
local barFrame
local watcher = CreateFrame("Frame")
local updateTicker
local previewMode = false

local PREFIX = "|cff00ccffOxedHub Experience:|r "

local TEXTURES = {
    smooth   = "Interface\\TargetingFrame\\UI-StatusBar",
    flat     = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar",
}

-- Session stats tracking
local session = {
    startTime       = 0,
    gainedXP        = 0,
    lastXP          = 0,
    maxXP           = 0,
    serverTotalTime = 0,
    serverLevelTime = 0,
    clientTimeMark  = 0,
    questXP         = 0,
    completeXP      = 0,
}

-- ── Utilities ───────────────────────────────────────────────────────────────

local function SafeNumber(val)
    if issecretvalue and issecretvalue(val) then return 0 end
    return type(val) == "number" and val or 0
end

local function FormatXP(amount)
    amount = SafeNumber(amount)
    if amount >= 1000000 then
        return ("%.2fM"):format(amount / 1000000)
    elseif amount >= 10000 then
        return ("%.1fK"):format(amount / 1000)
    end
    return FormatLargeNumber and FormatLargeNumber(amount) or tostring(amount)
end

local function FormatTime(seconds)
    seconds = SafeNumber(seconds)
    if seconds < 60 then return "< 1m" end

    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local mins = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return ("%dd %dh"):format(days, hours)
    elseif hours > 0 then
        return ("%dh %dm"):format(hours, mins)
    else
        return ("%dm"):format(mins)
    end
end

local function GetMaxLevel()
    if GetMaxPlayerLevel then
        local maxLvl = SafeNumber(GetMaxPlayerLevel())
        if maxLvl > 0 then return maxLvl end
    end
    if GetMaxLevelForExpansionLevel and GetExpansionLevel then
        local maxLvl = SafeNumber(GetMaxLevelForExpansionLevel(GetExpansionLevel()))
        if maxLvl > 0 then return maxLvl end
    end
    return 80
end

local function IsPlayerMaxLevel()
    local lvl = SafeNumber(UnitLevel("player"))
    return lvl >= GetMaxLevel()
end

local function IsPetBattleActive()
    return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() or false
end

-- ── Quest Log Scanning ──────────────────────────────────────────────────────

local function ScanQuestLog()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then
        session.questXP = 0
        session.completeXP = 0
        return
    end

    local numEntries = SafeNumber(C_QuestLog.GetNumQuestLogEntries())
    local totalQuestXP = 0
    local totalCompleteXP = 0

    -- ⚠ The quest id alone, by index. GetInfo hands back a full table for
    -- every line of the log, headers included: 100 KB for one scan of a full
    -- log, on every QUEST_LOG_UPDATE. A header has no quest id (0 or nil), so
    -- it is skipped the same way.
    for index = 1, numEntries do
        local questID
        if C_QuestLog.GetQuestIDForLogIndex then
            questID = C_QuestLog.GetQuestIDForLogIndex(index)
        elseif C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader then
                questID = info.questID
            end
        end

        if questID and questID > 0 then
            local rewardXP = SafeNumber(GetQuestLogRewardXP(questID))
            if rewardXP > 0 then
                totalQuestXP = totalQuestXP + rewardXP
                local isComplete = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID))
                                or (C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID))
                if isComplete then
                    totalCompleteXP = totalCompleteXP + rewardXP
                end
            end
        end
    end

    session.questXP = totalQuestXP
    session.completeXP = totalCompleteXP
end

-- ── UI Construction ────────────────────────────────────────────────────────

local function GetBarTexture()
    local key = settings and settings.texture or "smooth"
    return TEXTURES[key] or TEXTURES.smooth
end

local function GetFontOutline()
    local outline = settings and settings.fontOutline or "OUTLINE"
    if outline == "NONE" then return nil end
    return outline
end

local function SavePosition()
    if not barFrame or not settings then return end
    local point, _, relPoint, x, y = barFrame:GetPoint()
    if point then
        settings.point = point
        settings.relativePoint = relPoint or point
        settings.x = math.floor(x + 0.5)
        settings.y = math.floor(y + 0.5)
    end
end

local function BuildBar()
    if barFrame then return end

    barFrame = CreateFrame("Frame", "OxedHubExperienceBar", UIParent, "BackdropTemplate")
    barFrame:SetClampedToScreen(true)
    barFrame:SetMovable(true)
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")

    barFrame:SetScript("OnDragStart", function(self)
        if settings and not settings.locked then
            self:StartMoving()
        end
    end)

    barFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)

    barFrame:SetScript("OnEnter", function(self)
        if settings and not settings.locked then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L["OxedHub Experience Bar"])
            GameTooltip:AddLine(L["Left-click and drag to reposition."], 1, 1, 1)
            GameTooltip:AddLine(L["Type /oxexp lock or use settings to lock position."], 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    barFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Base frame strata and level
    barFrame:SetFrameStrata(settings and settings.strata or "MEDIUM")
    barFrame:SetFrameLevel(20)
    local baseLevel = 20

    -- Background texture (Layer 1: Behind all bars)
    local bg = barFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(barFrame)
    bg:SetColorTexture(0.08, 0.08, 0.10, 0.85)
    barFrame.bg = bg

    -- Rested XP Bar (Layer 2: Sky Blue)
    local restedBar = CreateFrame("StatusBar", nil, barFrame)
    restedBar:SetAllPoints(barFrame)
    restedBar:SetFrameLevel(baseLevel + 2)
    restedBar:SetMinMaxValues(0, 100)
    restedBar:SetValue(0)
    barFrame.restedBar = restedBar

    -- Completed Quest XP Bar (Layer 3: Golden Orange)
    local questBar = CreateFrame("StatusBar", nil, barFrame)
    questBar:SetAllPoints(barFrame)
    questBar:SetFrameLevel(baseLevel + 4)
    questBar:SetMinMaxValues(0, 100)
    questBar:SetValue(0)
    barFrame.questBar = questBar

    -- Main XP Progress Bar (Layer 4: Vibrant Blue/Purple or Class Color)
    local progressBar = CreateFrame("StatusBar", nil, barFrame)
    progressBar:SetAllPoints(barFrame)
    progressBar:SetFrameLevel(baseLevel + 6)
    progressBar:SetMinMaxValues(0, 100)
    progressBar:SetValue(0)
    barFrame.progressBar = progressBar

    -- 1px Border frame (Layer 5: Edge outline on top of bars)
    local border = CreateFrame("Frame", nil, barFrame, "BackdropTemplate")
    border:SetAllPoints(barFrame)
    border:SetFrameLevel(baseLevel + 8)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    border:SetBackdropBorderColor(0, 0, 0, 0.9)
    barFrame.border = border

    -- Dedicated Text Overlay Frame (Layer 6: Above all bars and borders)
    local textOverlay = CreateFrame("Frame", nil, barFrame)
    textOverlay:SetAllPoints(barFrame)
    textOverlay:SetFrameLevel(baseLevel + 10)
    barFrame.textOverlay = textOverlay

    -- Font Strings on textOverlay
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

    -- Inside bar: Left (Level)
    local levelText = textOverlay:CreateFontString(nil, "OVERLAY")
    levelText:SetPoint("LEFT", textOverlay, "LEFT", 8, 0)
    levelText:SetJustifyH("LEFT")
    levelText:SetTextColor(1, 1, 1, 1)
    levelText:SetShadowOffset(1, -1)
    levelText:SetShadowColor(0, 0, 0, 1)
    barFrame.levelText = levelText

    -- Inside bar: Center (XP Numbers)
    local progressText = textOverlay:CreateFontString(nil, "OVERLAY")
    progressText:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)
    progressText:SetJustifyH("CENTER")
    progressText:SetTextColor(1, 1, 1, 1)
    progressText:SetShadowOffset(1, -1)
    progressText:SetShadowColor(0, 0, 0, 1)
    barFrame.progressText = progressText

    -- Inside bar: Right (Percent)
    local percentText = textOverlay:CreateFontString(nil, "OVERLAY")
    percentText:SetPoint("RIGHT", textOverlay, "RIGHT", -8, 0)
    percentText:SetJustifyH("RIGHT")
    percentText:SetTextColor(1, 0.85, 0.20, 1)
    percentText:SetShadowOffset(1, -1)
    percentText:SetShadowColor(0, 0, 0, 1)
    barFrame.percentText = percentText

    -- Above bar: Top-Left (Level Time)
    local levelTimeText = textOverlay:CreateFontString(nil, "OVERLAY")
    levelTimeText:SetPoint("BOTTOMLEFT", textOverlay, "TOPLEFT", 2, 4)
    levelTimeText:SetJustifyH("LEFT")
    levelTimeText:SetTextColor(0.85, 0.85, 0.85, 1)
    levelTimeText:SetShadowOffset(1, -1)
    levelTimeText:SetShadowColor(0, 0, 0, 1)
    barFrame.levelTimeText = levelTimeText

    -- Above bar: Top-Center (Total Played)
    local totalPlayedText = textOverlay:CreateFontString(nil, "OVERLAY")
    totalPlayedText:SetPoint("BOTTOM", textOverlay, "TOP", 0, 4)
    totalPlayedText:SetJustifyH("CENTER")
    totalPlayedText:SetTextColor(0.75, 0.75, 0.75, 1)
    totalPlayedText:SetShadowOffset(1, -1)
    totalPlayedText:SetShadowColor(0, 0, 0, 1)
    barFrame.totalPlayedText = totalPlayedText

    -- Above bar: Top-Right (Session Time)
    local sessionTimeText = textOverlay:CreateFontString(nil, "OVERLAY")
    sessionTimeText:SetPoint("BOTTOMRIGHT", textOverlay, "TOPRIGHT", -2, 4)
    sessionTimeText:SetJustifyH("RIGHT")
    sessionTimeText:SetTextColor(0.85, 0.85, 0.85, 1)
    sessionTimeText:SetShadowOffset(1, -1)
    sessionTimeText:SetShadowColor(0, 0, 0, 1)
    barFrame.sessionTimeText = sessionTimeText

    -- Below bar: Bottom-Left (Time to Level & XP/Hour)
    local timeToLevelText = textOverlay:CreateFontString(nil, "OVERLAY")
    timeToLevelText:SetPoint("TOPLEFT", textOverlay, "BOTTOMLEFT", 2, -4)
    timeToLevelText:SetJustifyH("LEFT")
    timeToLevelText:SetTextColor(0.85, 0.85, 0.85, 1)
    timeToLevelText:SetShadowOffset(1, -1)
    timeToLevelText:SetShadowColor(0, 0, 0, 1)
    barFrame.timeToLevelText = timeToLevelText

    -- Below bar: Bottom-Right (Completed & Rested %)
    local questRestedText = textOverlay:CreateFontString(nil, "OVERLAY")
    questRestedText:SetPoint("TOPRIGHT", textOverlay, "BOTTOMRIGHT", -2, -4)
    questRestedText:SetJustifyH("RIGHT")
    questRestedText:SetTextColor(0.85, 0.85, 0.85, 1)
    questRestedText:SetShadowOffset(1, -1)
    questRestedText:SetShadowColor(0, 0, 0, 1)
    barFrame.questRestedText = questRestedText
end

local function Restyle()
    if not barFrame or not settings then return end

    local w = math.max(120, SafeNumber(settings.width) or 580)
    local h = math.max(10, SafeNumber(settings.height) or 24)
    local fSize = math.max(8, SafeNumber(settings.fontSize) or 12)
    local fOutline = GetFontOutline()
    local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local barTex = GetBarTexture()

    barFrame:SetSize(w, h)
    barFrame:SetFrameStrata(settings.strata or "MEDIUM")
    barFrame:ClearAllPoints()
    barFrame:SetPoint(settings.point or "TOP", UIParent, settings.relativePoint or "TOP",
        SafeNumber(settings.x), SafeNumber(settings.y) or -65)

    barFrame:EnableMouse(not settings.locked)
    if barFrame.border then
        if not settings.locked then
            barFrame.border:SetBackdropBorderColor(0.2, 0.7, 1.0, 0.9)
        else
            barFrame.border:SetBackdropBorderColor(0, 0, 0, 0.9)
        end
    end

    -- Explicit child frame sizing
    if barFrame.restedBar then barFrame.restedBar:SetSize(w, h) end
    if barFrame.questBar then barFrame.questBar:SetSize(w, h) end
    if barFrame.progressBar then barFrame.progressBar:SetSize(w, h) end
    if barFrame.border then barFrame.border:SetSize(w, h) end
    if barFrame.textOverlay then barFrame.textOverlay:SetSize(w, h) end

    -- Rested bar texture & color (Sky blue)
    barFrame.restedBar:SetStatusBarTexture(barTex)
    barFrame.restedBar:SetStatusBarColor(0.25, 0.60, 1.00, 0.55)

    -- Quest bar texture & color (Golden orange)
    barFrame.questBar:SetStatusBarTexture(barTex)
    barFrame.questBar:SetStatusBarColor(1.00, 0.58, 0.05, 0.90)

    -- Progress bar texture & color
    barFrame.progressBar:SetStatusBarTexture(barTex)
    if settings.useClassColor then
        local _, class = UnitClass("player")
        local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
        local r = color and color.r or 0.35
        local g = color and color.g or 0.45
        local b = color and color.b or 1.0
        barFrame.progressBar:SetStatusBarColor(r, g, b, 1)
        local pTex = barFrame.progressBar:GetStatusBarTexture()
        if pTex and pTex.SetGradient then
            pTex:SetGradient("HORIZONTAL", CreateColor(r * 0.85, g * 0.85, b * 0.85, 1), CreateColor(math.min(1, r * 1.15), math.min(1, g * 1.15), math.min(1, b * 1.15), 1))
        end
    else
        barFrame.progressBar:SetStatusBarColor(0.40, 0.38, 0.98, 1)
        local pTex = barFrame.progressBar:GetStatusBarTexture()
        if pTex and pTex.SetGradient then
            pTex:SetGradient("HORIZONTAL", CreateColor(0.28, 0.42, 0.98, 1), CreateColor(0.75, 0.32, 0.98, 1))
        end
    end

    -- Font sizes
    barFrame.levelText:SetFont(font, fSize, fOutline)
    barFrame.progressText:SetFont(font, fSize, fOutline)
    barFrame.percentText:SetFont(font, fSize, fOutline)
    barFrame.levelTimeText:SetFont(font, math.max(8, fSize - 1), fOutline)
    barFrame.totalPlayedText:SetFont(font, math.max(8, fSize - 1), fOutline)
    barFrame.sessionTimeText:SetFont(font, math.max(8, fSize - 1), fOutline)
    barFrame.timeToLevelText:SetFont(font, math.max(8, fSize - 1), fOutline)
    barFrame.questRestedText:SetFont(font, math.max(8, fSize - 1), fOutline)

    -- Visibility toggles
    barFrame.levelText:SetShown(settings.showLevelText == true)
    barFrame.progressText:SetShown(settings.showProgressText == true)
    barFrame.percentText:SetShown(settings.showPercentText == true)
    barFrame.levelTimeText:SetShown(settings.showLevelTime == true)
    barFrame.totalPlayedText:SetShown(settings.showTotalPlayed == true)
    barFrame.sessionTimeText:SetShown(settings.showSessionTime == true)
    barFrame.timeToLevelText:SetShown(settings.showTimeToLevel == true)
    barFrame.questRestedText:SetShown(settings.showQuestRested == true)
    barFrame.restedBar:SetShown(settings.showRestedBar == true)
    barFrame.questBar:SetShown(settings.showQuestBar == true)
end

-- ── Data Calculation & Display ──────────────────────────────────────────────

local function UpdateDisplay()
    if not barFrame or not settings then return end

    if not settings.enabled then
        barFrame:Hide()
        return
    end

    -- Pet battle hiding
    if settings.hidePetBattle and IsPetBattleActive() then
        barFrame:Hide()
        return
    end

    local isMax = IsPlayerMaxLevel()
    if isMax and not settings.showMaxLevel and not previewMode then
        barFrame:Hide()
        return
    end

    barFrame:Show()

    local level, currentXP, maxXP, remainingXP, restedXP, questXP, completeXP
    local sessionTime, levelTime, totalTime, hourlyXP, timeToLevel

    if previewMode then
        -- Sample preview data for styling & configuring
        level = 75
        currentXP = 45000
        maxXP = 100000
        remainingXP = 55000
        restedXP = 20000
        completeXP = 15000
        questXP = 25000
        sessionTime = 2520 -- 42m
        levelTime = 5100   -- 1h 25m
        totalTime = 86400 * 5 + 3600 * 12
        hourlyXP = 142500
        timeToLevel = math.floor((remainingXP / hourlyXP) * 3600)
    else
        level = SafeNumber(UnitLevel("player"))
        currentXP = SafeNumber(UnitXP("player"))
        maxXP = math.max(1, SafeNumber(UnitXPMax("player")))
        remainingXP = math.max(0, maxXP - currentXP)
        restedXP = SafeNumber(GetXPExhaustion())
        completeXP = SafeNumber(session.completeXP)
        questXP = SafeNumber(session.questXP)

        local now = GetServerTime()
        sessionTime = math.max(0, now - session.startTime)
        local elapsedSinceMsg = math.max(0, now - session.clientTimeMark)
        levelTime = session.serverLevelTime + elapsedSinceMsg
        totalTime = session.serverTotalTime + elapsedSinceMsg

        if sessionTime > 0 and session.gainedXP > 0 then
            hourlyXP = math.floor((session.gainedXP / (sessionTime / 3600)))
            if hourlyXP > 0 and remainingXP > 0 then
                timeToLevel = math.floor((remainingXP / hourlyXP) * 3600)
            else
                timeToLevel = 0
            end
        else
            hourlyXP = 0
            timeToLevel = 0
        end
    end

    local pctXP = math.min(100, (currentXP / maxXP) * 100)
    local pctQuest = math.min(100, (completeXP / maxXP) * 100)
    local pctRested = math.min(100, (restedXP / maxXP) * 100)

    -- Bar values
    barFrame.progressBar:SetValue(pctXP)

    if settings.showQuestBar then
        barFrame.questBar:SetValue(math.min(100, pctXP + pctQuest))
    else
        barFrame.questBar:SetValue(0)
    end

    if settings.showRestedBar then
        local base = settings.showQuestBar and (pctXP + pctQuest) or pctXP
        barFrame.restedBar:SetValue(math.min(100, base + pctRested))
    else
        barFrame.restedBar:SetValue(0)
    end

    -- Text 1: Level
    if isMax and not previewMode then
        barFrame.levelText:SetText(L["Max Level"])
    else
        barFrame.levelText:SetText(L["Level "] .. level)
    end

    -- Text 2: Current / Max (Remaining)
    if isMax and not previewMode then
        barFrame.progressText:SetText(L["|cffffd100Maximum Level Reached|r"])
    else
        barFrame.progressText:SetText(("%s / %s (%s)"):format(
            FormatXP(currentXP), FormatXP(maxXP), FormatXP(remainingXP)
        ))
    end

    -- Text 3: Percent
    if isMax and not previewMode then
        barFrame.percentText:SetText("100%")
    else
        if pctQuest > 0 and settings.showQuestBar then
            barFrame.percentText:SetText(("%.1f%% |cffff9900(+%.1f%%)|r"):format(pctXP, pctQuest))
        else
            barFrame.percentText:SetText(("%.1f%%"):format(pctXP))
        end
    end

    -- Text 4: Time this level
    if isMax and not previewMode then
        barFrame.levelTimeText:SetText(L["Time played: "] .. FormatTime(totalTime))
    else
        barFrame.levelTimeText:SetText(L["Time this level: "] .. FormatTime(levelTime))
    end

    -- Text 5: Total played
    barFrame.totalPlayedText:SetText(L["Played: "] .. FormatTime(totalTime))

    -- Text 6: Session time
    barFrame.sessionTimeText:SetText(L["Session: "] .. FormatTime(sessionTime))

    -- Text 7: Next level estimate & XP/Hour
    if isMax and not previewMode then
        barFrame.timeToLevelText:SetText("")
    else
        if timeToLevel > 0 and hourlyXP > 0 then
            barFrame.timeToLevelText:SetText((L["Level in: %s (%s/h)"]):format(
                FormatTime(timeToLevel), FormatXP(hourlyXP)
            ))
        elseif hourlyXP > 0 then
            barFrame.timeToLevelText:SetText((L["Pace: %s/h"]):format(FormatXP(hourlyXP)))
        else
            barFrame.timeToLevelText:SetText(L["Pace: --"])
        end
    end

    -- Text 8: Completed Quest % & Rested %
    if isMax and not previewMode then
        barFrame.questRestedText:SetText("")
    else
        barFrame.questRestedText:SetText((L["Quests: |cffff9900%.1f%%|r  Rested: |cff44aaff%.1f%%|r"]):format(
            pctQuest, pctRested
        ))
    end

    -- Enforce visibility of all text and bar elements immediately
    barFrame.levelText:SetShown(settings.showLevelText == true)
    barFrame.progressText:SetShown(settings.showProgressText == true)
    barFrame.percentText:SetShown(settings.showPercentText == true)
    barFrame.levelTimeText:SetShown(settings.showLevelTime == true)
    barFrame.totalPlayedText:SetShown(settings.showTotalPlayed == true)
    barFrame.sessionTimeText:SetShown(settings.showSessionTime == true)
    barFrame.timeToLevelText:SetShown(settings.showTimeToLevel == true)
    barFrame.questRestedText:SetShown(settings.showQuestRested == true)
    barFrame.restedBar:SetShown(settings.showRestedBar == true)
    barFrame.questBar:SetShown(settings.showQuestBar == true)
end

-- ── Blizzard Default Bar Handling ──────────────────────────────────────────

local function ManageDefaultBlizzardBar()
    if not StatusTrackingBarManager then return end
    if settings and settings.enabled and settings.hideDefaultBar then
        StatusTrackingBarManager:Hide()
    else
        StatusTrackingBarManager:Show()
    end
end

-- ── Session Life Cycle ─────────────────────────────────────────────────────

local function ResetSessionStats()
    session.startTime = GetServerTime()
    session.gainedXP = 0
    session.lastXP = SafeNumber(UnitXP("player"))
    session.maxXP = math.max(1, SafeNumber(UnitXPMax("player")))
    session.serverLevelTime = 0
    session.serverTotalTime = 0
    session.clientTimeMark = session.startTime
    ScanQuestLog()
    RequestTimePlayed()
    UpdateDisplay()
end

local function Start()
    BuildBar()
    Restyle()
    ManageDefaultBlizzardBar()

    if session.startTime == 0 or (settings and settings.resetReload) then
        session.startTime = GetServerTime()
        session.gainedXP = 0
        session.lastXP = SafeNumber(UnitXP("player"))
        session.maxXP = math.max(1, SafeNumber(UnitXPMax("player")))
        session.clientTimeMark = session.startTime
    end

    ScanQuestLog()
    RequestTimePlayed()

    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_XP_UPDATE")
    watcher:RegisterEvent("UPDATE_EXHAUSTION")
    watcher:RegisterEvent("PLAYER_LEVEL_UP")
    watcher:RegisterEvent("QUEST_LOG_UPDATE")
    watcher:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    watcher:RegisterEvent("TIME_PLAYED_MSG")
    watcher:RegisterEvent("PET_BATTLE_OPENING_START")
    watcher:RegisterEvent("PET_BATTLE_CLOSE")
    watcher:RegisterEvent("UPDATE_EXPANSION_LEVEL")
    watcher:RegisterEvent("MAX_EXPANSION_LEVEL_UPDATED")

    if not updateTicker then
        updateTicker = C_Timer.NewTicker(0.5, UpdateDisplay)
    end

    UpdateDisplay()
end

local function Stop()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    watcher:UnregisterAllEvents()
    previewMode = false

    if barFrame then
        barFrame:Hide()
    end

    ManageDefaultBlizzardBar()
end

-- ── Event Handling ─────────────────────────────────────────────────────────

local questScanQueued = false
local function RunQuestScan()
    questScanQueued = false
    if not settings or settings.enabled == false then return end
    ScanQuestLog()
    UpdateDisplay()
end

watcher:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_ENTERING_WORLD" then
        ScanQuestLog()
        RequestTimePlayed()
        UpdateDisplay()
    elseif event == "PLAYER_XP_UPDATE" then
        local currentXP = SafeNumber(UnitXP("player"))
        local delta = currentXP - session.lastXP
        if delta < 0 then
            -- Dinged or reset
            delta = math.max(0, session.maxXP - session.lastXP + currentXP)
        end
        session.gainedXP = session.gainedXP + delta
        session.lastXP = currentXP
        session.maxXP = math.max(1, SafeNumber(UnitXPMax("player")))
        UpdateDisplay()
    elseif event == "PLAYER_LEVEL_UP" then
        session.serverLevelTime = 0
        session.clientTimeMark = GetServerTime()
        session.lastXP = SafeNumber(UnitXP("player"))
        session.maxXP = math.max(1, SafeNumber(UnitXPMax("player")))
        UpdateDisplay()
    elseif event == "TIME_PLAYED_MSG" then
        session.serverTotalTime = SafeNumber(arg1)
        session.serverLevelTime = SafeNumber(arg2)
        session.clientTimeMark = GetServerTime()
        UpdateDisplay()
    elseif event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and arg1 == "player") then
        -- These come in bursts; one scan for the whole burst.
        if not questScanQueued then
            questScanQueued = true
            C_Timer.After(0.5, RunQuestScan)
        end
    elseif event == "UPDATE_EXHAUSTION" or event == "PET_BATTLE_OPENING_START"
        or event == "PET_BATTLE_CLOSE" or event == "UPDATE_EXPANSION_LEVEL"
        or event == "MAX_EXPANSION_LEVEL_UPDATED" then
        UpdateDisplay()
    end
end)

-- ── Options Window (OxedHub Style) ─────────────────────────────────────────

local function AddChoiceRow(w, key, caption, choices, onChange)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    label:SetText(caption)

    local holder, buttons = {}, {}
    holder.Refresh = function()
        for _, entry in ipairs(buttons) do
            local active = settings[key] == entry.key
            if entry.button.SetNormalFontObject then
                entry.button:SetNormalFontObject(active and "GameFontNormal" or "GameFontDisableSmall")
            end
        end
    end

    local btnWidth = math.floor((w:GetWidth() - 170) / #choices) - 4
    btnWidth = math.min(100, math.max(65, btnWidth))

    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(btnWidth, 22)
        button:SetPoint("TOPLEFT", w, "TOPLEFT", 150 + (index - 1) * (btnWidth + 4), w.cursorY - 2)
        button:SetText(choice.name)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(button)
        end
        button:SetScript("OnClick", function()
            settings[key] = choice.key
            holder.Refresh()
            if onChange then onChange(choice.key) else Restyle(); UpdateDisplay() end
        end)
        buttons[#buttons + 1] = { key = choice.key, button = button }
    end

    table.insert(w.checks, holder)
    w.cursorY = w.cursorY - 28
end

local function AddSlider(w, key, caption, minValue, maxValue, step, formatStr, onChange)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 180, w.cursorY)
    slider:SetWidth(180)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    local ready, refreshing = false, false
    local function Show(val) label:SetText((formatStr):format(caption, val)) end
    local function Load()
        refreshing = true
        local val = tonumber(settings[key]) or minValue
        slider:SetValue(val)
        Show(val)
        refreshing = false
        ready = true
    end

    slider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val / step + 0.5) * step
        Show(val)
        if refreshing or not ready then return end
        settings[key] = val
        if onChange then onChange(val) else Restyle(); UpdateDisplay() end
    end)

    local holder = { Refresh = Load }
    table.insert(w.checks, holder)
    Load()
    w.cursorY = w.cursorY - 28
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Experience Bar", 500, 560)
        local w = optionsWindow

        -- Sub-page containers
        local pages = {}
        local currentTab = 1

        local function CreatePage()
            local p = CreateFrame("Frame", nil, w)
            p:SetPoint("TOPLEFT", w, "TOPLEFT", 0, -70)
            p:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", 0, 10)
            p.cursorY = -10
            p.checks = {}
            p.AddCheckbox = function(self, cfg, k, lbl, tip, cb)
                local box = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
                box:SetSize(24, 24)
                box:SetPoint("TOPLEFT", self, "TOPLEFT", 20, self.cursorY)
                box.text:SetFontObject("GameFontHighlight")
                box.text:SetText(lbl)
                box:SetScript("OnClick", function(btn)
                    cfg[k] = btn:GetChecked() and true or false
                    if cb then cb(cfg[k]) else Restyle(); UpdateDisplay() end
                end)
                if tip then
                    box:SetScript("OnEnter", function(btn)
                        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                        GameTooltip:SetText(lbl)
                        GameTooltip:AddLine(tip, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
                box.Refresh = function() box:SetChecked(cfg[k] == true) end
                table.insert(self.checks, box)
                self.cursorY = self.cursorY - 26
                return box
            end
            p.AddNote = function(self, text)
                local note = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                note:SetPoint("TOPLEFT", self, "TOPLEFT", 22, self.cursorY - 4)
                note:SetWidth(w:GetWidth() - 44)
                note:SetJustifyH("LEFT")
                note:SetTextColor(0.75, 0.75, 0.75, 1)
                note:SetText(text)
                self.cursorY = self.cursorY - 4 - note:GetStringHeight() - 6
                return note
            end
            return p
        end

        local pageDisplay  = CreatePage()
        local pageTexts    = CreatePage()
        local pageSettings = CreatePage()
        pages = { pageDisplay, pageTexts, pageSettings }

        -- Tab switching
        local tabs = {}
        local tabNames = { "Display & Size", "Text Overlays", "Settings" }

        local function SwitchTab(index)
            currentTab = index
            for i, p in ipairs(pages) do
                p:SetShown(i == index)
                if i == index then
                    for _, c in ipairs(p.checks) do if c.Refresh then c.Refresh() end end
                end
            end
            for i, btn in ipairs(tabs) do
                local selected = (i == index)
                if selected then
                    btn:SetNormalFontObject("GameFontHighlight")
                    if btn.glow then btn.glow:Show() end
                else
                    btn:SetNormalFontObject("GameFontDisableSmall")
                    if btn.glow then btn.glow:Hide() end
                end
            end
        end

        -- Build Tab bar
        local tabStrip = CreateFrame("Frame", nil, w)
        tabStrip:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -34)
        tabStrip:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -34)
        tabStrip:SetHeight(32)

        local prevTab
        local tabW = 145
        for i, name in ipairs(tabNames) do
            local btn = CreateFrame("Button", nil, tabStrip, "UIPanelButtonTemplate")
            btn:SetSize(tabW, 24)
            btn:SetText(name)
            if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
                OxedHub.UI:ApplyRedButtonStyle(btn)
            end

            local glow = btn:CreateTexture(nil, "OVERLAY")
            glow:SetHeight(2)
            glow:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 4, -2)
            glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -4, -2)
            glow:SetColorTexture(1, 0.82, 0, 1)
            glow:Hide()
            btn.glow = glow

            if prevTab then
                btn:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
            else
                btn:SetPoint("LEFT", tabStrip, "LEFT", 12, 0)
            end

            btn:SetScript("OnClick", function()
                SwitchTab(i)
            end)

            tabs[#tabs + 1] = btn
            prevTab = btn
        end

        API:AddTabLine(w, tabStrip, 0, 0)

        -- ── Page 1: Display & Size ──────────────────────────────────────────
        local p1 = pageDisplay

        -- Action Buttons Row
        local btnUnlock = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
        btnUnlock:SetSize(110, 22)
        btnUnlock:SetPoint("TOPLEFT", p1, "TOPLEFT", 20, p1.cursorY)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnUnlock) end
        local function RefreshUnlockText()
            btnUnlock:SetText(settings.locked and L["Unlock"] or L["Lock Bar"])
        end
        RefreshUnlockText()
        btnUnlock:SetScript("OnClick", function()
            settings.locked = not settings.locked
            RefreshUnlockText()
            Restyle()
        end)

        local btnTest = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
        btnTest:SetSize(110, 22)
        btnTest:SetPoint("LEFT", btnUnlock, "RIGHT", 8, 0)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnTest) end
        local function RefreshTestText()
            btnTest:SetText(previewMode and L["Stop Test"] or L["Test Mode"])
        end
        RefreshTestText()
        btnTest:SetScript("OnClick", function()
            previewMode = not previewMode
            RefreshTestText()
            UpdateDisplay()
        end)

        local btnResetPos = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
        btnResetPos:SetSize(110, 22)
        btnResetPos:SetPoint("LEFT", btnTest, "RIGHT", 8, 0)
        btnResetPos:SetText(L["Reset Pos"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnResetPos) end
        btnResetPos:SetScript("OnClick", function()
            settings.point = "TOP"
            settings.relativePoint = "TOP"
            settings.x = 0
            settings.y = -65
            Restyle()
            print(PREFIX .. L["Position reset to top center."])
        end)

        local btnResetStats = CreateFrame("Button", nil, p1, "UIPanelButtonTemplate")
        btnResetStats:SetSize(110, 22)
        btnResetStats:SetPoint("LEFT", btnResetPos, "RIGHT", 8, 0)
        btnResetStats:SetText(L["Reset Stats"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnResetStats) end
        btnResetStats:SetScript("OnClick", function()
            ResetSessionStats()
            print(PREFIX .. L["Session stats and timers reset."])
        end)

        p1.cursorY = p1.cursorY - 32

        p1:AddNote("|cffffd100Geometry & Appearance|r")
        AddSlider(p1, "width", L["Bar width"], 200, 1100, 10, "%s: %d")
        AddSlider(p1, "height", L["Bar height"], 12, 50, 1, "%s: %d")
        AddSlider(p1, "fontSize", L["Font size"], 8, 22, 1, "%s: %d")

        AddChoiceRow(p1, "texture", L["Bar texture"], {
            { key = "smooth",   name = L["Smooth"] },
            { key = "flat",     name = L["Flat"] },
            { key = "blizzard", name = "Blizzard" },
        })

        AddChoiceRow(p1, "fontOutline", L["Text outline"], {
            { key = "NONE",         name = "None" },
            { key = "OUTLINE",      name = L["Outline"] },
            { key = "THICKOUTLINE", name = L["Thick"] },
        })

        AddChoiceRow(p1, "strata", L["Frame strata"], {
            { key = "BACKGROUND", name = L["Back"] },
            { key = "LOW",        name = L["Low"] },
            { key = "MEDIUM",     name = L["Medium"] },
            { key = "HIGH",       name = L["High"] },
        })

        p1:AddCheckbox(settings, "showQuestBar", "Show Completed Quest XP Bar (Orange)",
            "Displays a golden amber overlay showing available XP from completed quests in your log.", function() Restyle(); UpdateDisplay() end)
        p1:AddCheckbox(settings, "showRestedBar", "Show Rested Bonus Bar (Blue)",
            "Displays a translucent sky blue overlay for accumulated rested bonus XP.", function() Restyle(); UpdateDisplay() end)
        p1:AddCheckbox(settings, "useClassColor", "Use Class Color for Progress Bar",
            "Colors the main experience progress bar with your character class color.", function() Restyle(); UpdateDisplay() end)

        -- ── Page 2: Texts ───────────────────────────────────────────────────
        local p2 = pageTexts
        p2:AddNote("|cffffd100Inside Bar Texts|r")
        p2:AddCheckbox(settings, "showLevelText", "Character Level (e.g. \"Level 81\")",
            "Shows your character's current level on the left side of the bar.", function() Restyle(); UpdateDisplay() end)
        p2:AddCheckbox(settings, "showProgressText", "XP Values (e.g. \"108.8K / 423.4K (314.6K)\")",
            "Shows current XP / required XP (remaining) in the center of the bar.", function() Restyle(); UpdateDisplay() end)
        p2:AddCheckbox(settings, "showPercentText", "XP Percentage (e.g. \"25.7% (+3.2%)\")",
            "Shows current XP percentage and quest completion gain on the right side.", function() Restyle(); UpdateDisplay() end)

        p2:AddNote("|cffffd100Above Bar Texts|r")
        p2:AddCheckbox(settings, "showLevelTime", "Time this Level (Top-Left: e.g. \"Time this level: 37m\")",
            "Displays time spent on your current level.", function() Restyle(); UpdateDisplay() end)
        p2:AddCheckbox(settings, "showTotalPlayed", "Total Lifetime Played (Top-Center: e.g. \"Played: 12d 4h\")",
            "Displays total lifetime playtime for this character.", function() Restyle(); UpdateDisplay() end)
        p2:AddCheckbox(settings, "showSessionTime", "Session Time (Top-Right: e.g. \"Session: < 1m\")",
            "Displays time elapsed during your current game session.", function() Restyle(); UpdateDisplay() end)

        p2:AddNote("|cffffd100Below Bar Texts|r")
        p2:AddCheckbox(settings, "showTimeToLevel", "Leveling Pace & XP/Hour (Bottom-Left: e.g. \"Pace: --\")",
            "Calculates estimated time to level up and XP gained per hour.", function() Restyle(); UpdateDisplay() end)
        p2:AddCheckbox(settings, "showQuestRested", "Completed Quests & Rested (Bottom-Right: e.g. \"Quests: 3.2% Rested: 97.9%\")",
            "Shows quest completion percentage and rested bonus percentage.", function() Restyle(); UpdateDisplay() end)

        -- ── Page 3: General Settings ────────────────────────────────────────
        local p3 = pageSettings
        p3:AddNote("|cffffd100General & Integration|r")

        p3:AddCheckbox(settings, "hideDefaultBar", "Hide Default Blizzard XP Bar",
            "Automatically hides Blizzard's StatusTrackingBarManager while this module is active.", function(val)
                ManageDefaultBlizzardBar()
            end)

        p3:AddCheckbox(settings, "showMaxLevel", "Show Bar at Maximum Level",
            "Keep the experience bar visible on max-level characters instead of auto-hiding.", function() UpdateDisplay() end)

        p3:AddCheckbox(settings, "hidePetBattle", "Hide During Pet Battles",
            "Automatically hides the experience bar when a pet battle starts.", function() UpdateDisplay() end)

        p3:AddCheckbox(settings, "resetReload", "Reset Session Stats on /reload",
            "Do not retain session time and hourly XP calculations across UI reloads.")

        p3:AddNote("|cff888888Hint: You can unlock the bar and drag it anywhere on your screen. Type /oxexp for quick controls.|r")

        -- OnShow sync
        w:HookScript("OnShow", function()
            RefreshUnlockText()
            RefreshTestText()
            SwitchTab(currentTab)
        end)
    end

    optionsWindow:Show()
end

-- ── Slash Command ──────────────────────────────────────────────────────────

SLASH_OXEDHUBEXP1 = "/oxexp"
SLASH_OXEDHUBEXP2 = "/oxxp"
SLASH_OXEDHUBEXP3 = "/eeb"

SlashCmdList.OXEDHUBEXP = function(msg)
    if not settings then return end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "test" then
        previewMode = not previewMode
        print(PREFIX .. (previewMode and L["Test mode enabled."] or L["Test mode disabled."]))
        UpdateDisplay()
    elseif msg == "lock" or msg == "unlock" then
        settings.locked = not settings.locked
        print(PREFIX .. (settings.locked and L["Bar locked."] or L["Bar unlocked (drag to move)."]))
        Restyle()
    elseif msg == "reset" then
        settings.point = "TOP"
        settings.relativePoint = "TOP"
        settings.x = 0
        settings.y = -65
        Restyle()
        print(PREFIX .. L["Position reset to top center."])
    elseif msg == "stats" then
        ResetSessionStats()
        print(PREFIX .. L["Session stats reset."])
    else
        ShowOptions()
    end
end

-- ── Settings Binding ───────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}

    local config = OxedHubDB.modules.easyexperiencebar
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.easyexperiencebar = config
    end

    for key, defaultValue in pairs(DEFAULTS) do
        if config[key] == nil then
            config[key] = defaultValue
        end
    end

    settings = config
end

-- ── Registration ───────────────────────────────────────────────────────────

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
        id       = "easyexperiencebar",
        name     = "Experience Bar",
        version  = "1.0.0",
        author   = "Oxed",
        category = "character",
        keywords = { "xp", "experience", "bar", "level", "played", "rested", "quest", "leveling" },
        desc     = "A sleek experience bar with completed quest XP overlays, rested bonus, and leveling rate. /oxexp",
        icon     = "Interface\\Icons\\Achievement_Level_80",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
