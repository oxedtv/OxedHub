local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey
local L = OxedHub.L

local PreyHUD = {}
Prey.HUD = PreyHUD

local barFrame = nil

local STAGE_DOT_COLORS = {
    [1] = { r = 0.3, g = 0.6, b = 1.0 },  -- Stage 1: Cold Blue
    [2] = { r = 1.0, g = 0.85, b = 0.2 }, -- Stage 2: Warm Yellow
    [3] = { r = 1.0, g = 0.55, b = 0.1 }, -- Stage 3: Orange Hot
    [4] = { r = 1.0, g = 0.15, b = 0.15 }, -- Stage 4: Blood Red
}

-- ------------------------------------------------------------
-- Prey Hunt HUD Bar Frame
-- ------------------------------------------------------------
function PreyHUD:GetOrCreateBar()
    if barFrame then return barFrame end

    barFrame = CreateFrame("Button", "OxedHubPreyBar", UIParent, "BackdropTemplate")
    barFrame:SetSize(380, 56)
    barFrame:SetPoint("TOP", UIParent, "TOP", 0, -180)
    barFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    barFrame:SetFrameLevel(9000)
    barFrame:SetClampedToScreen(true)
    barFrame:SetMovable(true)
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")
    barFrame:RegisterForClicks("AnyUp")

    barFrame:SetScript("OnDragStart", function(self)
        if not self.isLocked then
            self:StartMoving()
        end
    end)
    barFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if OxedHub.db and OxedHub.db.profile then
            OxedHub.db.profile.preyHUDPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    -- Stage 4 Super-Track Click: Clicking the bar when at Stage 4 tracks the boss map location
    barFrame:SetScript("OnClick", function(self, button)
        if Prey.Engine and Prey.Engine.state and Prey.Engine.state.stage == 4 then
            local qID = Prey.Engine.state.questID
            if qID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                pcall(C_SuperTrack.SetSuperTrackedQuestID, qID)
            end
        end
    end)

    -- Backdrop
    barFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    barFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.94)
    barFrame:SetBackdropBorderColor(1, 0.82, 0, 0.85)

    -- Fill Bar (Background slot + fill texture)
    local barBg = barFrame:CreateTexture(nil, "BACKGROUND")
    barBg:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 3, -3)
    barBg:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -3, 3)
    barBg:SetColorTexture(0.03, 0.03, 0.04, 0.85)

    local fill = barFrame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 3, 3)
    fill:SetWidth(0)
    fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fill:SetVertexColor(0.85, 0.58, 0.12, 0.95)
    barFrame.fill = fill

    -- Section Dividers (3 vertical tick marks at 25%, 50%, 75%)
    barFrame.dividers = {}
    for i = 1, 3 do
        local div = barFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        div:SetColorTexture(0.0, 0.0, 0.0, 0.85)
        div:SetWidth(2)
        div:SetPoint("TOP", barFrame, "TOP", 0, -3)
        div:SetPoint("BOTTOM", barFrame, "BOTTOM", 0, 3)
        barFrame.dividers[i] = div
    end

    -- Torment Debuff Frame (Top Right)
    local tormentFrame = CreateFrame("Frame", nil, barFrame)
    tormentFrame:SetSize(130, 18)
    tormentFrame:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", -8, -6)

    local tormentIcon = tormentFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    tormentIcon:SetSize(14, 14)
    tormentIcon:SetPoint("RIGHT", tormentFrame, "RIGHT", 0, 0)
    tormentIcon:SetTexture("Interface\\Icons\\Spell_Shadow_ShadowPact")
    tormentIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tormentFrame.icon = tormentIcon

    local tormentText = tormentFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tormentText:SetPoint("RIGHT", tormentIcon, "LEFT", -4, 0)
    tormentText:SetJustifyH("RIGHT")
    tormentText:SetTextColor(1, 0.35, 0.35)
    tormentFrame.text = tormentText
    barFrame.tormentFrame = tormentFrame

    -- Target & Difficulty Label (Top Left, constrained to left of Torment Frame)
    local targetText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetText:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 10, -7)
    targetText:SetPoint("RIGHT", tormentFrame, "LEFT", -6, 0)
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)
    targetText:SetTextColor(1, 0.85, 0.2)
    barFrame.targetText = targetText

    -- Stage & Progress Label (Bottom Left)
    local stageText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stageText:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 10, 7)
    stageText:SetPoint("RIGHT", barFrame, "RIGHT", -60, 0)
    stageText:SetJustifyH("LEFT")
    stageText:SetWordWrap(false)
    stageText:SetTextColor(0.9, 0.9, 0.9)
    barFrame.stageText = stageText

    -- Percent Text (Bottom Right)
    local pctText = barFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pctText:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -10, 7)
    pctText:SetJustifyH("RIGHT")
    pctText:SetTextColor(1, 1, 1)
    barFrame.pctText = pctText

    -- 4 Stage Indicator Dots (Borderless, floating cleanly under bar)
    local dotDock = CreateFrame("Frame", nil, barFrame)
    dotDock:SetSize(100, 14)
    dotDock:SetPoint("TOP", barFrame, "BOTTOM", 0, -4)
    barFrame.dotDock = dotDock

    barFrame.stageDots = {}
    for i = 1, 4 do
        local dot = dotDock:CreateTexture(nil, "OVERLAY", nil, 4)
        dot:SetSize(9, 9)
        dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
        dot:SetPoint("LEFT", dotDock, "LEFT", (i - 1) * 24 + 4, 0)
        barFrame.stageDots[i] = dot
    end

    -- Restore saved position
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.preyHUDPosition then
        local pos = OxedHub.db.profile.preyHUDPosition
        barFrame:ClearAllPoints()
        barFrame:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -180)
    end

    barFrame:Hide()
    return barFrame
end

function PreyHUD:Update(state)
    local bar = self:GetOrCreateBar()

    if not state or not state.active or state.shouldShowHUD == false then
        if not self.testModeActive then
            bar:Hide()
        end
        return
    end

    local maxWidth = bar:GetWidth() - 6
    local stage = state.stage or 1
    if stage < 1 then stage = 1 end
    if stage > 4 then stage = 4 end

    local pct = state.percent or Prey.STAGE_PERCENTS[stage] or 0
    local targetName = state.targetName or "Prey Hunt"
    local difficulty = state.difficulty or "Normal"

    -- Update HUD Bar
    bar.targetText:SetText(string.format("%s (%s)", targetName, difficulty))
    
    if state.tormentPct and state.tormentPct > 0 then
        bar.tormentFrame.text:SetText(string.format("Torment +%d%%%s", state.tormentPct, state.isNightmare and " (NM)" or ""))
        bar.tormentFrame:Show()
    else
        bar.tormentFrame:Hide()
    end

    -- Stage Dividers (at 25%, 50%, 75%)
    for i = 1, 3 do
        local div = bar.dividers[i]
        local xOffset = 3 + (maxWidth * (i * 0.25))
        div:ClearAllPoints()
        div:SetPoint("TOPLEFT", bar, "TOPLEFT", xOffset, -3)
        div:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", xOffset, 3)
        div:Show()
    end

    -- 4 Stage Indicator Dots
    for i = 1, 4 do
        local dot = bar.stageDots[i]
        if i <= stage then
            local col = STAGE_DOT_COLORS[i] or { r = 1, g = 1, b = 1 }
            dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
            dot:SetVertexColor(col.r, col.g, col.b, 1)
            if i == stage then
                dot:SetSize(12, 12)
            else
                dot:SetSize(9, 9)
            end
        else
            dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
            dot:SetVertexColor(0.4, 0.4, 0.4, 0.6)
            dot:SetSize(8, 8)
        end
    end

    local now = GetTime and GetTime() or 0
    local isKillCelebration = now < (state.killStageUntil or 0)

    local stageName = Prey.STAGE_LABELS[stage] or "Hunting"
    if isKillCelebration then
        stageName = "|cFF00FF00PREY SLAIN! (COMPLETED)|r"
    elseif state.isAmbush then
        stageName = "|cFFFF3333AMBUSH IN PROGRESS!|r"
    elseif state.isBloodyCommand then
        stageName = "|cFFFF6600BLOODY COMMAND: DRAIN ANGUISH!|r"
    elseif stage == 4 then
        stageName = "|cFFFF8822STAGE 4: BOSS SPAWNED! (CLICK TO TRACK)|r"
    end

    bar.stageText:SetText(string.format("Stage %d: %s", stage, stageName))
    bar.pctText:SetText(string.format("%d%%", pct))

    bar.fill:SetWidth(math.max(1, maxWidth * (pct / 100)))

    if not bar:IsShown() then
        bar:Show()
    end
end

function PreyHUD:SetLocked(locked)
    local bar = self:GetOrCreateBar()
    bar.isLocked = locked
    if locked then
        bar:EnableMouse(false)
    else
        bar:EnableMouse(true)
    end
end

function PreyHUD:ToggleTestMode()
    local bar = self:GetOrCreateBar()
    self.testModeActive = not self.testModeActive
    if self.testModeActive then
        self:SetLocked(false)
        self:Update({
            active = true,
            stage = 2,
            percent = 50,
            targetName = "Magister Sunbreaker",
            difficulty = "Nightmare",
            tormentPct = 16,
            isNightmare = true,
            isAmbush = false,
            shouldShowHUD = true,
        })
        bar:Show()
    else
        self.testModeActive = false
        if Prey.Engine and Prey.Engine.state then
            self:Update(Prey.Engine.state)
        else
            bar:Hide()
        end
    end
    return self.testModeActive
end

function PreyHUD:ResetPosition()
    local bar = self:GetOrCreateBar()
    bar:ClearAllPoints()
    bar:SetPoint("TOP", UIParent, "TOP", 0, -180)
    if OxedHub.db and OxedHub.db.profile then
        OxedHub.db.profile.preyHUDPosition = { point = "TOP", relPoint = "TOP", x = 0, y = -180 }
    end
end
