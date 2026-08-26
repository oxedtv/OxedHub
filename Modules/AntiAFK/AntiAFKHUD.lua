local addonName, OxedHub = ...

local AntiAFK = OxedHub.AntiAFK or {}
OxedHub.AntiAFK = AntiAFK
local L = OxedHub.L

-- ------------------------------------------------------------
-- Top Screen Timer Frame (Movable / Draggable)
-- ------------------------------------------------------------
local timerFrame = CreateFrame("Frame", "OxedHubAntiAFKTimerFrame", UIParent)
timerFrame:SetSize(420, 70)
timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -60)
timerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
timerFrame:SetFrameLevel(9000)
timerFrame:SetClampedToScreen(true)
timerFrame:EnableMouse(true)
timerFrame:SetMovable(true)
timerFrame:RegisterForDrag("LeftButton")
timerFrame:Hide()

local timerText = timerFrame:CreateFontString(nil, "OVERLAY")
timerText:SetFont("Fonts\\FRIZQT__.TTF", 46, "THICKOUTLINE")
timerText:SetPoint("CENTER")
timerText:SetText("5:00")
timerText:SetTextColor(0, 1, 0)
timerFrame.text = timerText

timerFrame:SetScript("OnDragStart", function(self)
    self.isDragging = true
    self:StartMoving()
end)

timerFrame:SetScript("OnDragStop", function(self)
    self.isDragging = false
    self:StopMovingOrSizing()
    local trigger = AntiAFK:GetActiveTrigger()
    if trigger then
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            trigger.conditions = trigger.conditions or {}
            trigger.conditions.timerPosX = math.floor(cx - ux + 0.5)
            trigger.conditions.timerPosY = math.floor(cy - uy + 0.5)
            trigger.conditions.timerCustomPos = true
            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                local card = OxedHub.Triggers.triggerCards and OxedHub.Triggers.selectedTriggerId and OxedHub.Triggers.triggerCards[OxedHub.Triggers.selectedTriggerId]
                if card then OxedHub.Triggers.ShowAutoSaved(card) end
            end
        end
    end
end)

-- ------------------------------------------------------------
-- Center Screen "MOVE" Alert Frame (Movable / Draggable)
-- ------------------------------------------------------------
local moveFrame = CreateFrame("Frame", "OxedHubAntiAFKMoveFrame", UIParent)
moveFrame:SetSize(700, 160)
moveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
moveFrame:SetFrameStrata("FULLSCREEN_DIALOG")
moveFrame:SetFrameLevel(9100)
moveFrame:SetClampedToScreen(true)
moveFrame:EnableMouse(true)
moveFrame:SetMovable(true)
moveFrame:RegisterForDrag("LeftButton")
moveFrame:Hide()

local moveText = moveFrame:CreateFontString(nil, "OVERLAY")
moveText:SetFont("Fonts\\FRIZQT__.TTF", 96, "OUTLINE")
moveText:SetPoint("CENTER")
moveText:SetText("RUN!!!!!!!!!")
moveText:SetTextColor(1, 0, 0)
moveFrame.text = moveText

moveFrame:SetScript("OnDragStart", function(self)
    self.isDragging = true
    self:StartMoving()
end)

moveFrame:SetScript("OnDragStop", function(self)
    self.isDragging = false
    self:StopMovingOrSizing()
    local trigger = AntiAFK:GetActiveTrigger()
    if trigger then
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and cy and ux and uy then
            trigger.conditions = trigger.conditions or {}
            trigger.conditions.moveBannerPosX = math.floor(cx - ux + 0.5)
            trigger.conditions.moveBannerPosY = math.floor(cy - uy + 0.5)
            trigger.conditions.moveBannerCustomPos = true
            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                local card = OxedHub.Triggers.triggerCards and OxedHub.Triggers.selectedTriggerId and OxedHub.Triggers.triggerCards[OxedHub.Triggers.selectedTriggerId]
                if card then OxedHub.Triggers.ShowAutoSaved(card) end
            end
        end
    end
end)

-- Sound management state
local loopSoundTicker = nil
local loopSoundInterval = nil
local pendingMoveSoundHandle = nil

local function FormatElapsed(t)
    t = math.max(0, t)
    local m = math.floor(t / 60)
    local s = math.floor(t % 60)
    return string.format("%02d:%02d", m, s)
end

local function FormatMax(t)
    t = math.max(0, t)
    local m = math.floor(t / 60)
    local s = math.floor(t % 60)
    return string.format("%d:%02d", m, s)
end

-- Compose the timer line: optional label, then the number in the chosen shape.
local function BuildTimerText(cond, elapsed, maxTime)
    cond = cond or {}
    local mode = cond.timerFormat or "countdown"

    local body
    if mode == "elapsed" then
        body = FormatElapsed(elapsed)
    elseif mode == "both" then
        body = FormatElapsed(elapsed) .. " / " .. FormatMax(maxTime)
    else
        body = FormatMax(math.max(0, (maxTime or 0) - (elapsed or 0)))
    end

    local label = cond.timerLabel
    if label and label ~= "" then
        return label .. " " .. body
    end
    return body
end

function AntiAFK:PlaySoundDirect(soundVal)
    if not soundVal or soundVal == "" or soundVal == "None" or soundVal == "none" then return end
    if tonumber(soundVal) then
        PlaySound(tonumber(soundVal), "Master")
    elseif OxedHub.Sounds and OxedHub.Sounds.Play then
        OxedHub.Sounds:Play(soundVal)
    else
        PlaySoundFile(soundVal, "Master")
    end
end

function AntiAFK:StopLoopSound()
    if loopSoundTicker then
        loopSoundTicker:Cancel()
        loopSoundTicker = nil
    end
    loopSoundInterval = nil
end

function AntiAFK:StopAllSounds()
    self:StopLoopSound()
    pendingMoveSoundHandle = nil
end

function AntiAFK:StartLoopSound(soundVal, interval)
    if not soundVal or soundVal == "" or soundVal == "None" then return end
    if loopSoundTicker and loopSoundInterval == interval then return end

    self:StopLoopSound()
    loopSoundInterval = interval

    self:PlaySoundDirect(soundVal)
    loopSoundTicker = C_Timer.NewTicker(interval, function()
        AntiAFK:PlaySoundDirect(soundVal)
    end)
end

function AntiAFK:ApplyFramePositions(trigger)
    local cond = trigger and trigger.conditions or {}
    
    if not timerFrame.isDragging then
        if cond.timerCustomPos and cond.timerPosX and cond.timerPosY then
            timerFrame:ClearAllPoints()
            timerFrame:SetPoint("CENTER", UIParent, "CENTER", cond.timerPosX, cond.timerPosY)
        else
            timerFrame:ClearAllPoints()
            timerFrame:SetPoint("TOP", UIParent, "TOP", 0, -60)
        end
    end

    if not moveFrame.isDragging then
        if cond.moveBannerCustomPos and cond.moveBannerPosX and cond.moveBannerPosY then
            moveFrame:ClearAllPoints()
            moveFrame:SetPoint("CENTER", UIParent, "CENTER", cond.moveBannerPosX, cond.moveBannerPosY)
        else
            moveFrame:ClearAllPoints()
            moveFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        end
    end
end

-- Show both HUD pieces together while the appearance is being adjusted.
-- Unlike ToggleMoveBannerPreview (banner only, for positioning), this also
-- pins the timer up so font, size and colour changes have something to land on.
function AntiAFK:TogglePreview(trigger)
    trigger = trigger or self:GetActiveTrigger()
    local cond = (trigger and trigger.conditions) or {}

    if self.stylePreviewOn then
        self.stylePreviewOn = false
        moveFrame.isPreview = false
        moveFrame:Hide()
        -- Hand control back to the live timer; it hides itself if not running.
        self:UpdateTimerDisplay(0, cond.maxTime or 300, "none", cond.showTimer ~= false, false)
        return false
    end

    self.stylePreviewOn = true
    self:ApplyFramePositions(trigger)
    self:ApplyHUDStyle(cond)

    -- Mid-way through the countdown, so the number is representative.
    local sample = math.floor((cond.maxTime or 300) * 0.4)
    self:UpdateTimerDisplay(sample, cond.maxTime or 300, "red", true, false)

    moveFrame.isPreview = true
    moveText:SetText(moveFrame.customText or AntiAFK.DEFAULT_WARNING)
    moveFrame:Show()
    return true
end

function AntiAFK:ToggleMoveBannerPreview(trigger)
    trigger = trigger or self:GetActiveTrigger()
    if moveFrame:IsShown() and moveFrame.isPreview then
        moveFrame.isPreview = false
        moveFrame:Hide()
        return false
    else
        self:ApplyFramePositions(trigger)
        moveFrame.isPreview = true
        moveText:SetText(moveFrame.customText or AntiAFK.DEFAULT_WARNING)
        moveFrame:Show()
        return true
    end
end

-- Look & feel, all driven from the trigger's conditions so each user can dial
-- the HUD in.  Defaults reproduce the original hard-coded appearance exactly.
AntiAFK.PHASE_DEFAULT_COLORS = {
    none   = { 0, 1, 0 },
    yellow = { 1, 1, 0 },
    red    = { 1, 0, 0 },
    move   = { 1, 0, 0 },
}

-- Bundled faces plus the stock WoW ones.  path is what SetFont needs; label
-- is what the picker shows.
AntiAFK.FONTS = {
    { label = "Friz Quadrata (default)", path = "Fonts\\FRIZQT__.TTF" },
    { label = "Arial Narrow",            path = "Fonts\\ARIALN.TTF" },
    { label = "Skurri",                  path = "Fonts\\skurri.ttf" },
    { label = "Morpheus",                path = "Fonts\\MORPHEUS.TTF" },
    { label = "Hotman Ridley",  path = "Interface\\AddOns\\OxedHub\\Media\\Fonts\\Hotman Ridley.otf" },
    { label = "Orlando Kaiden", path = "Interface\\AddOns\\OxedHub\\Media\\Fonts\\Orlando Kaiden.otf" },
    { label = "Mustard Nebula", path = "Interface\\AddOns\\OxedHub\\Media\\Fonts\\Mustard Nebula.otf" },
    { label = "Darling Charm",  path = "Interface\\AddOns\\OxedHub\\Media\\Fonts\\Darling Charm.otf" },
}

-- Default wording for the big centre warning.
AntiAFK.DEFAULT_WARNING = "RUN!!!!!!!!!"

-- Catalog key for the bundled clip used by the urgent stage by default.
-- Users can pick anything else in the sound picker.
AntiAFK.DEFAULT_MOVE_SOUND = "oxedhub_meme_run"

-- How the on-screen timer reads.  Counting DOWN to the kick is the useful
-- number; "elapsed / max" made you do the subtraction yourself.
AntiAFK.TIMER_FORMATS = {
    { key = "countdown", label = "Time left" },
    { key = "elapsed",   label = "Time idle" },
    { key = "both",      label = "Idle / limit" },
}

AntiAFK.FONT_OUTLINES = {
    { key = "THICKOUTLINE", label = "Thick Outline" },
    { key = "OUTLINE",      label = "Outline" },
    { key = "NONE",         label = "None" },
}

local function ResolveOutline(value)
    if value == "NONE" then return "" end
    return value or "THICKOUTLINE"
end

local function PhaseColor(cond, phase)
    local stored = cond and cond["color" .. tostring(phase)]
    if type(stored) == "table" and stored[1] then
        return stored[1], stored[2] or 0, stored[3] or 0
    end
    local def = AntiAFK.PHASE_DEFAULT_COLORS[phase] or AntiAFK.PHASE_DEFAULT_COLORS.none
    return def[1], def[2], def[3]
end

-- Re-apply fonts/sizes. Cheap enough to run on every display update, which
-- keeps the preview live while the user drags a slider.
function AntiAFK:ApplyHUDStyle(cond)
    cond = cond or {}
    -- An explicit pick wins; otherwise fall back to the locale-aware default
    -- (Arabic needs its own face).
    local font = cond.fontPath or OxedHub:GetFont("Fonts\\FRIZQT__.TTF")

    timerText:SetFont(font, cond.timerFontSize or 46, ResolveOutline(cond.timerOutline))
    moveText:SetFont(font, cond.moveFontSize or 96, ResolveOutline(cond.moveOutline or "OUTLINE"))

    local mr, mg, mb = PhaseColor(cond, "move")
    moveText:SetTextColor(mr, mg, mb)

    if cond.moveText and cond.moveText ~= "" then
        moveFrame.customText = cond.moveText
    else
        moveFrame.customText = nil
    end
end

function AntiAFK:UpdateTimerDisplay(elapsed, maxTime, phase, showTimer, showMoveBanner)
    local trigger = self:GetActiveTrigger()
    self:ApplyFramePositions(trigger)

    local cond = (trigger and trigger.conditions) or {}
    self:ApplyHUDStyle(cond)
    moveText:SetText(moveFrame.customText or AntiAFK.DEFAULT_WARNING)

    if showTimer then
        timerText:SetText(BuildTimerText(cond, elapsed, maxTime))
        timerText:SetTextColor(PhaseColor(cond, phase or "none"))
        timerFrame:Show()
    else
        timerFrame:Hide()
    end

    if (showMoveBanner and phase == "move") or moveFrame.isPreview then
        moveFrame:Show()
    else
        moveFrame:Hide()
    end
end

function AntiAFK:HideAll()
    moveFrame.isPreview = false
    timerFrame:Hide()
    moveFrame:Hide()
    self:StopAllSounds()
end

AntiAFK.timerFrame = timerFrame
AntiAFK.moveFrame = moveFrame
