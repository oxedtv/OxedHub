-- ============================================================================
-- KickBar - Interrupt Alert & Floating Highlight (OxedHub built-in module)
-- State-of-the-art interrupt alert system:
--
--   * Display Modes:
--       - NAMEPLATE : Anchored beside enemy target's nameplate
--       - FLOATING  : Movable HUD icon placed anywhere on screen
--
--   * Visual States:
--       - GREEN PULSING : Interrupt ready & in range -> KICK NOW!
--       - GOLD PROC     : Critical / Important cast highlight!
--       - YELLOW        : Interrupt ready but out of range (Range tint)
--       - DESATURATED   : "Almost Ready" preview (< 2s on CD)
--       - RED DIMMED    : Interrupt on cooldown (cooldown sweep + timer)
--
--   * Modern Retail 12.x / Midnight Features:
--       - FlipBook Proc Loop sparkle glow (UI-HUD-ActionBar-Proc-Loop-Flipbook)
--       - Engine-driven cast countdown timer on the icon
--       - C-side secret-value protection (issecretvalue & SetAlphaFromBoolean)
--       - Focus target & Target cast tracking
--       - OxedHub SoundPicker & Animation integration
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer
local issecretvalue = _G.issecretvalue
local issecret = _G.issecret

-- The ticker runs many times a second, so nothing on its path may build a
-- closure: every `pcall(function() ... end)` is a fresh table for the garbage
-- collector. Helpers below are named once and called with their arguments.
local function TruthTest(v)
    if v then return true end
    return false
end

local function IsSecret(val)
    if issecretvalue then
        local ok, s = pcall(issecretvalue, val)
        if ok then return s == true end
    end
    if issecret then
        local ok, s = pcall(issecret, val)
        if ok and s then return true end
    end
    return not pcall(TruthTest, val)
end

local function HasCast(unit)
    if type(UnitCastingInfo(unit)) ~= "nil" then return true end
    return type(UnitChannelInfo(unit)) ~= "nil"
end

-- ── Interrupt Spell Database ───────────────────────────────────────────────
local INTERRUPT_SPELLS = {
    DEATHKNIGHT = { 47528 },                -- Mind Freeze
    DEMONHUNTER = { 183752 },               -- Disrupt
    DRUID       = { 106839, 78675 },        -- Skull Bash, Solar Beam
    EVOKER      = { 351338 },               -- Quell
    HUNTER      = { 147362, 187707 },       -- Counter Shot, Muzzle
    MAGE        = { 2139 },                 -- Counterspell
    MONK        = { 116705 },               -- Spear Hand Strike
    PALADIN     = { 96231 },                -- Rebuke
    PRIEST      = { 15487 },                -- Silence (Shadow only)
    ROGUE       = { 1766 },                 -- Kick
    SHAMAN      = { 57994 },                -- Wind Shear
    WARLOCK     = {},                       -- through Command Demon (see FindInterruptSpell)
    WARRIOR     = { 6552 },                 -- Pummel
}

local COMMAND_DEMON = 119898
local COMMAND_DEMON_INTERRUPTS = {
    [119910] = true,  -- Spell Lock (Felhunter)
    [132409] = true,  -- Spell Lock (Fel Ravager)
    [119914] = true,  -- Axe Toss (Felguard)
}

-- ── Default Settings ────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled            = false,
    displayMode        = "NAMEPLATE", -- "NAMEPLATE" or "FLOATING"
    scale              = 1.4,
    alpha              = 1.0,

    -- Floating HUD position
    locked             = true,
    posX               = 0,
    posY               = 150,
    point              = "CENTER",
    strata             = "HIGH",

    -- Nameplate anchor
    anchor             = "LEFT",      -- "LEFT", "RIGHT", "TOP"
    offsetX            = -8,
    offsetY            = 0,

    -- Visual & Behavior features
    showLabel          = true,
    showOnCD           = true,
    showAlmostReady    = true,        -- desaturated preview when CD <= 2.0s
    showCastTimer      = true,        -- cast countdown number on the icon
    showGlow           = true,        -- Blizzard Proc FlipBook sparkle glow
    highlightImportant = true,        -- golden glow for important casts
    importantOnly      = false,
    trackFocus         = true,        -- watch focus target if set
    rangeTint          = true,        -- tint icon red when out of range

    -- Sounds & animations
    sound              = "",
    animation          = "",
}

-- ── State ───────────────────────────────────────────────────────────────────
local KickBarDB
local playerClass
local interruptSpellID
local interruptIcon
local interruptHasRange = false
local kickFrame
local currentNameplate
local currentHost
local isShowing = false
local moduleAPI = nil
local castNotInterruptible = false
local castShielded = false
local isImportantCast = false
local currentCastUnit = nil
local debugTestMode = false
local lastInterruptAt = nil

local UPDATE_RATE = 0.1     -- the timer shows tenths; faster only made garbage
local READY_GAP = 0.2
local importantSpell = nil  -- spellID whose "important" answer is cached
local importantCached = false
local timerKey = nil        -- last cast-timer text shown, to skip SetText
local ALMOST_READY_THRESHOLD = 2.0
local readyCheckedAt = 0
local readyCached = false
local interruptBaseMs = 0
local readyEndAt = 0
local cooldownPainted = false
local shownState = nil
local watchTicker = nil

-- Colors
local COLOR_WHITE            = { 1.0, 1.0, 1.0, 1.0 }
local COLOR_OUT_OF_RANGE     = { 0.85, 0.35, 0.35, 1.0 }
local COLOR_IMPORTANT_GLOW   = { 1.0, 0.65, 0.15, 1.0 }

-- ── API Compatibility Wrappers ──────────────────────────────────────────────

local function GetSpellCooldownCompat(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then return info.startTime, info.duration, info.isEnabled end
    end
    if GetSpellCooldown then return GetSpellCooldown(spellID) end
    return 0, 0, 1
end

local function GetSpellInfoCompat(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then return info.name, nil, info.iconID end
    end
    if GetSpellInfo then return GetSpellInfo(spellID) end
    return nil, nil, nil
end

local function ReadSpellRange(spellID, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        local r = C_Spell.IsSpellInRange(spellID, unit)
        if not IsSecret(r) and type(r) == "boolean" then
            return r
        end
        return nil
    end
    if IsSpellInRange then
        local name = GetSpellInfoCompat(spellID)
        if name and not IsSecret(name) then
            local r = IsSpellInRange(name, unit)
            if not IsSecret(r) then
                if r == 1 or r == true then
                    return true
                elseif r == 0 or r == false then
                    return false
                end
            end
        end
    end
    return nil
end

local function IsSpellInRangeCompat(spellID, unit)
    local ok, inRange = pcall(ReadSpellRange, spellID, unit)
    if ok then return inRange end
    return nil
end

local function KnowsSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id)
        if ok and known then return true end
    end
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

local function ResolvedSpell(id)
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, override = pcall(C_Spell.GetOverrideSpell, id)
        if ok and override and override ~= 0 then return override end
    end
    return id
end

local function FindInterruptSpell()
    if not playerClass then
        local _, cls = UnitClass("player")
        playerClass = cls
    end

    interruptSpellID, interruptIcon = nil, nil
    local found

    if playerClass == "WARLOCK" and KnowsSpell(COMMAND_DEMON) then
        local override = ResolvedSpell(COMMAND_DEMON)
        if COMMAND_DEMON_INTERRUPTS[override] then found = override end
    end

    if not found then
        for _, id in ipairs(INTERRUPT_SPELLS[playerClass] or {}) do
            if KnowsSpell(id) then
                found = ResolvedSpell(id)
                break
            end
        end
    end

    if found then
        interruptSpellID = found
        local _, _, icon = GetSpellInfoCompat(found)
        interruptIcon = icon
        if C_Spell and C_Spell.SpellHasRange then
            interruptHasRange = C_Spell.SpellHasRange(found) or false
        else
            interruptHasRange = true
        end
        interruptBaseMs = 0
        if GetSpellBaseCooldown then
            local ok, value = pcall(GetSpellBaseCooldown, found)
            if ok and type(value) == "number" then interruptBaseMs = value end
        end
    end
end

-- ── Cooldown & Readiness Evaluation ─────────────────────────────────────────

local function IsGlobalCooldownOnly()
    if interruptBaseMs <= 1500 then return true end
    if not lastInterruptAt then return true end
    return (GetTime() - lastInterruptAt) > (interruptBaseMs / 1000)
end

local function ReadCooldownState(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if type(info) ~= "table" then return nil, 0 end
    local start = info.startTime
    local duration = info.duration
    local endAt = 0
    if not IsSecret(start) and not IsSecret(duration)
        and type(start) == "number" and type(duration) == "number"
        and start > 0 and duration > 1.5 then
        endAt = start + duration
    end
    local active = info.isActive
    if not IsSecret(active) and active ~= nil then
        local isAct = active and true or false
        if isAct and IsGlobalCooldownOnly() then isAct = false end
        return not isAct, endAt
    end
    if not IsSecret(start) and not IsSecret(duration)
        and type(start) == "number" and type(duration) == "number" then
        return (start == 0 or duration == 0 or duration <= 1.5), endAt
    end
    return nil, 0
end

local function ReadyFromNumbers(start, duration)
    if IsSecret(start) or IsSecret(duration) then return true, 0 end
    if type(start) ~= "number" or type(duration) ~= "number" then return true, 0 end
    if start == 0 or duration == 0 or duration <= 1.5 then return true, 0 end
    return false, start + duration
end

local function RefreshInterruptCooldown()
    if not interruptSpellID then
        readyCached = false
        readyEndAt = 0
        return
    end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, ready, endAt = pcall(ReadCooldownState, interruptSpellID)
        if ok and ready ~= nil then
            readyCached = ready
            readyEndAt = ready and 0 or (endAt or 0)
            return
        end
    end

    local start, duration = GetSpellCooldownCompat(interruptSpellID)
    local ok, ready, endAt = pcall(ReadyFromNumbers, start, duration)
    if ok then
        readyCached = ready
        readyEndAt = endAt or 0
        return
    end

    readyCached = false
    readyEndAt = 0
end

local function ApplyNumericCooldown(cdFrame, start, duration)
    if duration and duration > 1.5 then
        cdFrame:SetCooldown(start, duration)
        cdFrame:Show()
    else
        cdFrame:Hide()
    end
end

local function PaintCooldown(cdFrame)
    if not cdFrame or not interruptSpellID then return end
    if C_Spell and C_Spell.GetSpellCooldownDuration and cdFrame.SetCooldownFromDurationObject then
        local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, interruptSpellID)
        if okDur and durObj then
            local okSet = pcall(cdFrame.SetCooldownFromDurationObject, cdFrame, durObj)
            if okSet then
                cdFrame:Show()
                return
            end
        end
    end

    local start, duration = GetSpellCooldownCompat(interruptSpellID)
    local ok = pcall(ApplyNumericCooldown, cdFrame, start, duration)
    if not ok then cdFrame:Hide() end
end

-- ── Cast Shielding & Target Detection ───────────────────────────────────────

local function ReadVisible(f)
    local v = f:IsVisible()
    if IsSecret(v) then return false end
    return v and true or false
end

local function Visible(f)
    if not f or not f.IsVisible then return false end
    local ok, vis = pcall(ReadVisible, f)
    return ok and vis or false
end

local function ReadCastbarShield()
    if Visible(TargetFrameSpellBar) and Visible(TargetFrameSpellBar.BorderShield) then
        return true
    end
    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    local blizzard = np and np.UnitFrame and np.UnitFrame.CastBar
    if Visible(blizzard) and Visible(blizzard.BorderShield) then
        return true
    end
    local plater = np and np.unitFrame and np.unitFrame.castBar
    if Visible(plater) and Visible(plater.Shield) then
        return true
    end
    if ElvUF_Target and Visible(ElvUF_Target.Castbar) then
        local ni = ElvUF_Target.Castbar.notInterruptible
        if not IsSecret(ni) and ni then
            return true
        end
    end
    return false
end

local function CastbarShielded()
    local ok, shielded = pcall(ReadCastbarShield)
    return ok and shielded or false
end

-- Resolves which unit to watch (focus if set & casting, otherwise target)
local function GetActiveCastUnit()
    local db = KickBarDB or DEFAULTS
    if db.trackFocus and UnitExists("focus") and UnitCanAttack("player", "focus") and not UnitIsDead("focus") then
        local ok, focusCasting = pcall(HasCast, "focus")
        if ok and focusCasting then return "focus" end
    end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        return "target"
    end
    return nil
end

local function ReadHostileCast(unit)
    if not unit or not UnitCanAttack("player", unit) then return nil end

    local name, _, _, _, endTime, _, _, notInterruptible, spellID = UnitCastingInfo(unit)
    if type(name) == "nil" then
        name, _, _, _, endTime, _, notInterruptible, spellID = UnitChannelInfo(unit)
        if type(name) == "nil" then return nil end
    end

    return name, notInterruptible, spellID, endTime
end

-- ── Frame Construction with FlipBook & Dual Layer ──────────────────────────

local function CreateKickFrame()
    if kickFrame then return end

    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:EnableMouse(false)
    f:SetSize(40, 40)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(500)
    f:Hide()

    -- Dark backdrop with crisp border
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, 0.9)
    f:SetBackdropBorderColor(0, 1, 0, 1)

    -- Full-color Spell Icon
    local icon = f:CreateTexture(nil, "BACKGROUND")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- Desaturated Icon Layer (for "Almost Ready" preview)
    local iconDesat = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconDesat:SetAllPoints(icon)
    iconDesat:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconDesat:SetDesaturated(true)
    iconDesat:SetAlpha(0)
    f.iconDesat = iconDesat

    -- Cooldown Sweep
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", 2, -2)
    cd:SetPoint("BOTTOMRIGHT", -2, 2)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)
    cd:Hide()
    f.cooldown = cd

    -- Outer Glow / FlipBook Proc Animation
    local glow = f:CreateTexture(nil, "ARTWORK", nil, 2)
    glow:SetPoint("CENTER", f, "CENTER", 0, 0)
    glow:SetSize(60, 60)
    glow:Hide()
    f.glow = glow

    local hasFlipBook = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-HUD-ActionBar-Proc-Loop-Flipbook")
    if hasFlipBook then
        glow:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local fb = ag:CreateAnimation("FlipBook")
        fb:SetDuration(1.0)
        fb:SetOrder(1)
        fb:SetFlipBookRows(6)
        fb:SetFlipBookColumns(5)
        fb:SetFlipBookFrames(30)
        f.procAnim = ag
    else
        glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0.1, 1, 0.1, 0.8)
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local a1 = ag:CreateAnimation("Alpha")
        a1:SetFromAlpha(0.35)
        a1:SetToAlpha(0.9)
        a1:SetDuration(0.35)
        a1:SetOrder(1)
        local a2 = ag:CreateAnimation("Alpha")
        a2:SetFromAlpha(0.9)
        a2:SetToAlpha(0.35)
        a2:SetDuration(0.35)
        a2:SetOrder(2)
        f.procAnim = ag
    end

    -- Pulse animation (icon scale)
    local scaleAg = f:CreateAnimationGroup()
    scaleAg:SetLooping("REPEAT")
    local up = scaleAg:CreateAnimation("Scale")
    up:SetScaleFrom(1, 1)
    up:SetScaleTo(1.12, 1.12)
    up:SetDuration(0.35)
    up:SetOrder(1)
    up:SetSmoothing("IN_OUT")
    local down = scaleAg:CreateAnimation("Scale")
    down:SetScaleFrom(1.12, 1.12)
    down:SetScaleTo(1, 1)
    down:SetDuration(0.35)
    down:SetOrder(2)
    down:SetSmoothing("IN_OUT")
    f.pulseAnim = scaleAg

    -- Cast Countdown Timer text on bottom-left of icon
    local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    timerText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 3)
    timerText:SetTextColor(1, 1, 1, 1)
    timerText:Hide()
    f.timerText = timerText

    -- Bottom state label ("KICK", "RANGE", "CD", "SOON")
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", f, "BOTTOM", 0, -2)
    label:SetText("KICK")
    label:SetTextColor(0, 1, 0, 1)
    f.label = label

    -- Drag-and-drop support for Floating Mode
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        local db = KickBarDB or DEFAULTS
        if db.displayMode == "FLOATING" and not db.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db = KickBarDB or DEFAULTS
        if db.displayMode == "FLOATING" then
            local point, _, _, x, y = self:GetPoint()
            db.point = point or "CENTER"
            db.posX = math.floor((x or 0) + 0.5)
            db.posY = math.floor((y or 0) + 0.5)
        end
    end)

    kickFrame = f
end

-- ── Core Update Logic ───────────────────────────────────────────────────────

local function ShowKick()
    if not isShowing then
        isShowing = true
        kickFrame:Show()
    end
end

local function HideKick()
    cooldownPainted = false
    timerKey = nil
    shownState = nil
    readyCheckedAt = 0
    if isShowing then
        isShowing = false
        if kickFrame.pulseAnim then kickFrame.pulseAnim:Stop() end
        if kickFrame.procAnim then kickFrame.procAnim:Stop() end
        if kickFrame.glow then kickFrame.glow:Hide() end
        if kickFrame.timerText then kickFrame.timerText:Hide() end
        kickFrame:Hide()
        currentNameplate, currentHost = nil, nil
    end
end

local function StopWatch()
    if watchTicker then
        watchTicker:Cancel()
        watchTicker = nil
    end
end

local function Sleep()
    HideKick()
    StopWatch()
end

local function PositionFrame()
    local db = KickBarDB or DEFAULTS
    local mode = db.displayMode or "NAMEPLATE"

    if mode == "FLOATING" then
        if kickFrame:GetParent() ~= UIParent then
            kickFrame:SetParent(UIParent)
        end
        kickFrame:ClearAllPoints()
        kickFrame:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.posX or 0, db.posY or 150)
        kickFrame:EnableMouse(not db.locked)
        return
    end

    -- NAMEPLATE mode
    kickFrame:EnableMouse(false)
    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    local host = np and OxedHub.VisiblePlateBar and OxedHub.VisiblePlateBar(np) or np

    if np ~= currentNameplate or host ~= currentHost then
        currentNameplate, currentHost = np, host
        kickFrame:ClearAllPoints()
        if np then
            kickFrame:SetParent(np)
            local anchor = db.anchor or "LEFT"
            if anchor == "LEFT" then
                kickFrame:SetPoint("RIGHT", host, "LEFT", db.offsetX or -8, db.offsetY or 0)
            elseif anchor == "RIGHT" then
                kickFrame:SetPoint("LEFT", host, "RIGHT", -(db.offsetX or -8), db.offsetY or 0)
            else
                kickFrame:SetPoint("BOTTOM", host, "TOP", db.offsetX or 0, db.offsetY or 5)
            end
        else
            kickFrame:SetParent(UIParent)
            kickFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
    end
end

local function CalcCastRemaining(endTime)
    if endTime then
        return (endTime / 1000) - GetTime()
    end
    return nil
end

local function ReadImportant(spellID)
    if not (C_Spell and C_Spell.IsSpellImportant) then return false end
    local imp = C_Spell.IsSpellImportant(spellID)
    if IsSecret(imp) then return false end
    return imp and true or false
end

local function UpdateCastTimer(endTime)
    local db = KickBarDB or DEFAULTS
    if not db.showCastTimer or not kickFrame.timerText then
        if kickFrame.timerText then kickFrame.timerText:Hide() end
        return
    end

    local ok, rem = pcall(CalcCastRemaining, endTime)

    if ok and rem and type(rem) == "number" and rem > 0 then
        -- Tenths under 10 s, whole seconds above; only touch the font
        -- string when what it shows would change.
        local key = (rem < 10) and math.floor(rem * 10) or (1000 + math.floor(rem))
        if key ~= timerKey then
            timerKey = key
            if rem < 10 then
                kickFrame.timerText:SetFormattedText("%.1f", key / 10)
            else
                kickFrame.timerText:SetFormattedText("%d", key - 1000)
            end

            -- Color transition: Red (< 2.5s) -> Yellow (< 6s) -> White
            if rem <= 2.5 then
                kickFrame.timerText:SetTextColor(1, 0.4, 0.4, 1)
            elseif rem <= 6.0 then
                kickFrame.timerText:SetTextColor(1, 0.9, 0.3, 1)
            else
                kickFrame.timerText:SetTextColor(1, 1, 1, 1)
            end
        end
        kickFrame.timerText:Show()
    else
        timerKey = nil
        kickFrame.timerText:Hide()
    end
end

local function OnUpdate()
    local db = KickBarDB or DEFAULTS

    -- Test / Preview mode override
    if debugTestMode then
        PositionFrame()
        kickFrame:SetScale(db.scale or 1.4)
        kickFrame:SetAlpha(db.alpha or 1.0)
        kickFrame:SetBackdropBorderColor(0.1, 1, 0.1, 1)
        kickFrame.icon:SetTexture(interruptIcon or 132219)
        kickFrame.icon:SetDesaturated(false)
        kickFrame.icon:SetVertexColor(1, 1, 1, 1)
        kickFrame.iconDesat:SetAlpha(0)
        kickFrame.label:SetText("TEST")
        kickFrame.label:SetTextColor(0.1, 1, 0.1, 1)
        kickFrame.label:SetShown(db.showLabel ~= false)
        kickFrame.cooldown:Hide()
        if db.showGlow and kickFrame.glow then
            kickFrame.glow:Show()
            if kickFrame.procAnim and not kickFrame.procAnim:IsPlaying() then
                kickFrame.procAnim:Play()
            end
        end
        if db.showCastTimer and kickFrame.timerText then
            kickFrame.timerText:SetText("1.8")
            kickFrame.timerText:SetTextColor(1, 0.4, 0.4, 1)
            kickFrame.timerText:Show()
        end
        ShowKick()
        return
    end

    if not db.enabled or not interruptSpellID then
        Sleep()
        return
    end

    local unit = GetActiveCastUnit()
    if not unit then
        Sleep()
        return
    end
    currentCastUnit = unit

    local castName, notInterruptible, spellID, castEndTime = ReadHostileCast(unit)
    if type(castName) == "nil" then
        Sleep()
        return
    end

    -- Secret notInterruptible guard
    -- In WoW 12.0 / Retail, when execution is tainted (e.g. TargetNearestEnemy),
    -- notInterruptible is a <secret boolean>. Any boolean test (if, or, and, not) on it raises:
    -- "attempt to perform boolean test on local 'notInterruptible' (a secret boolean value, while execution tainted by 'OxedHub')"
    local okTest, isShielded = pcall(TruthTest, notInterruptible)

    if okTest then
        -- notInterruptible is a normal un-tainted boolean
        castNotInterruptible = isShielded
        local okShield, visualShield = pcall(CastbarShielded)
        castShielded = isShielded or (okShield and visualShield or false)
    else
        -- notInterruptible is a secret boolean!
        -- Store it directly without boolean testing so it can be passed to SetAlphaFromBoolean
        castNotInterruptible = notInterruptible
        -- Check visible castbar shield textures safely
        local okShield, visualShield = pcall(CastbarShielded)
        castShielded = okShield and visualShield or false
    end

    -- Important spell detection
    -- A spell's "important" flag does not change, so ask once per spellID.
    isImportantCast = false
    if (db.highlightImportant or db.importantOnly) and spellID and not IsSecret(spellID) then
        if spellID ~= importantSpell then
            local okImp, imp = pcall(ReadImportant, spellID)
            importantSpell = spellID
            importantCached = okImp and imp or false
        end
        isImportantCast = importantCached
    end

    if db.importantOnly and not isImportantCast then
        HideKick()
        return
    end

    -- Cooldown & Readiness Check
    local now = GetTime()
    if now - readyCheckedAt >= READY_GAP then
        readyCheckedAt = now
        RefreshInterruptCooldown()
    end
    local isReady = readyCached
    local remCD = (not isReady and readyEndAt > now) and (readyEndAt - now) or 0
    local isAlmostReady = not isReady and db.showAlmostReady and (remCD <= ALMOST_READY_THRESHOLD) and (remCD > 0)

    if not isReady and not isAlmostReady and not db.showOnCD then
        HideKick()
        return
    end

    -- Range Check
    local inRange = true
    if db.rangeTint and interruptHasRange then
        local okR, r = pcall(IsSpellInRangeCompat, interruptSpellID, unit)
        if okR and type(r) == "boolean" then
            inRange = r
        end
    end

    PositionFrame()

    -- Apply scale & alpha
    local scale = db.scale or 1.4
    if kickFrame._scale ~= scale then
        kickFrame._scale = scale
        kickFrame:SetScale(scale)
    end

    local alphaApplied = false
    if kickFrame.SetAlphaFromBoolean then
        local okAlpha = pcall(kickFrame.SetAlphaFromBoolean, kickFrame, castNotInterruptible, 0, db.alpha or 1.0)
        if okAlpha then alphaApplied = true end
    end
    if not alphaApplied then
        kickFrame:SetAlpha(castShielded and 0 or (db.alpha or 1.0))
    end

    if interruptIcon and kickFrame._icon ~= interruptIcon then
        kickFrame._icon = interruptIcon
        kickFrame.icon:SetTexture(interruptIcon)
        kickFrame.iconDesat:SetTexture(interruptIcon)
    end

    -- Determine Visual State:
    -- 1 = Ready & In Range (KICK!)
    -- 2 = Ready & Out of Range (RANGE)
    -- 3 = Almost Ready (< 2s left) (SOON)
    -- 4 = On Cooldown (CD)
    local state = 4
    if isReady and inRange then
        state = 1
    elseif isReady and not inRange then
        state = 2
    elseif isAlmostReady then
        state = 3
    end

    if state ~= shownState then
        shownState = state

        if state == 1 then
            -- STATE 1: GREEN PULSING (KICK!)
            kickFrame:SetBackdropBorderColor(0.1, 1, 0.1, 1)
            kickFrame.icon:SetDesaturated(false)
            kickFrame.icon:SetVertexColor(1, 1, 1, 1)
            kickFrame.iconDesat:SetAlpha(0)
            kickFrame.label:SetTextColor(0.1, 1, 0.1, 1)
            kickFrame.label:SetText(isImportantCast and L["PRIO!"] or L["KICK!"])
            kickFrame.cooldown:Hide()

            -- Proc Glow
            if db.showGlow and kickFrame.glow then
                if isImportantCast and db.highlightImportant then
                    kickFrame.glow:SetVertexColor(unpack(COLOR_IMPORTANT_GLOW))
                else
                    kickFrame.glow:SetVertexColor(1, 1, 1, 0.9)
                end
                kickFrame.glow:Show()
                if kickFrame.procAnim and not kickFrame.procAnim:IsPlaying() then
                    kickFrame.procAnim:Play()
                end
            end

            if not kickFrame.pulseAnim:IsPlaying() then
                kickFrame.pulseAnim:Play()

                -- Play sound / animation once upon transition
                if moduleAPI and not castShielded then
                    if db.sound and db.sound ~= "" and moduleAPI.sounds then
                        moduleAPI.sounds:Play(db.sound)
                    end
                    if db.animation and db.animation ~= "" and moduleAPI.animations then
                        moduleAPI.animations:Play(db.animation)
                    end
                end
            end

        elseif state == 2 then
            -- STATE 2: OUT OF RANGE (RANGE)
            kickFrame:SetBackdropBorderColor(1, 0.82, 0, 0.9)
            kickFrame.icon:SetDesaturated(false)
            kickFrame.icon:SetVertexColor(unpack(COLOR_OUT_OF_RANGE))
            kickFrame.iconDesat:SetAlpha(0)
            kickFrame.label:SetTextColor(1, 0.82, 0, 1)
            kickFrame.label:SetText("RANGE")
            kickFrame.cooldown:Hide()
            if kickFrame.pulseAnim then kickFrame.pulseAnim:Stop() end
            if kickFrame.procAnim then kickFrame.procAnim:Stop() end
            if kickFrame.glow then kickFrame.glow:Hide() end

        elseif state == 3 then
            -- STATE 3: ALMOST READY PREVIEW (SOON)
            kickFrame:SetBackdropBorderColor(0.4, 0.7, 1, 0.8)
            kickFrame.icon:SetDesaturated(true)
            kickFrame.icon:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            kickFrame.iconDesat:SetAlpha(1)
            kickFrame.label:SetTextColor(0.4, 0.7, 1, 1)
            kickFrame.label:SetFormattedText("%.1fs", remCD)
            if kickFrame.pulseAnim then kickFrame.pulseAnim:Stop() end
            if kickFrame.procAnim then kickFrame.procAnim:Stop() end
            if kickFrame.glow then kickFrame.glow:Hide() end

        else
            -- STATE 4: ON COOLDOWN (CD)
            kickFrame:SetBackdropBorderColor(0.8, 0.15, 0.15, 0.7)
            kickFrame.icon:SetDesaturated(true)
            kickFrame.icon:SetVertexColor(1, 1, 1, 0.5)
            kickFrame.iconDesat:SetAlpha(0)
            kickFrame.label:SetTextColor(0.8, 0.15, 0.15, 0.8)
            kickFrame.label:SetText("CD")
            if kickFrame.pulseAnim then kickFrame.pulseAnim:Stop() end
            if kickFrame.procAnim then kickFrame.procAnim:Stop() end
            if kickFrame.glow then kickFrame.glow:Hide() end

            if not cooldownPainted then
                cooldownPainted = true
                PaintCooldown(kickFrame.cooldown)
            end
        end
    elseif state == 3 then
        kickFrame.label:SetFormattedText("%.1fs", remCD)
    end

    if isReady then cooldownPainted = false end

    -- Update Cast Countdown Timer
    UpdateCastTimer(castEndTime)

    kickFrame.label:SetShown(db.showLabel ~= false)
    ShowKick()
end

-- ── Lifecycle Watchers ──────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")

local function IsOn()
    return KickBarDB ~= nil and KickBarDB.enabled ~= false
end

local function StartWatch()
    if watchTicker then return end
    watchTicker = C_Timer.NewTicker(UPDATE_RATE, OnUpdate)
    OnUpdate()
end

local function Wake()
    if debugTestMode then
        StartWatch()
        return
    end

    if not (IsOn() and interruptSpellID and kickFrame) then
        HideKick()
        StopWatch()
        return
    end

    local unit = GetActiveCastUnit()
    if unit then
        local ok, hasCast = pcall(HasCast, unit)
        if ok and hasCast then
            StartWatch()
            return
        end
    end

    HideKick()
    StopWatch()
end

local function StartUpdates()
    FindInterruptSpell()
    CreateKickFrame()
    Wake()
end

local function StopUpdates()
    HideKick()
    StopWatch()
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.kickbar
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.kickbar = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    KickBarDB = config
end

local function SetEnabled(on)
    if OxedHub.ModuleAPI and OxedHub.ModuleAPI:GetModule("kickbar") then
        OxedHub.ModuleAPI:SetModuleEnabled("kickbar", on)
    else
        if KickBarDB then KickBarDB.enabled = on end
        if on then StartUpdates() else StopUpdates() end
    end
end

-- ── Options Window ──────────────────────────────────────────────────────────

local optionsWindow
local optionsFrame

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API then return end

    local db = KickBarDB or DEFAULTS

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("KickBar", 460, 560)
        optionsFrame = optionsWindow

        optionsWindow:AddNote("Interrupt alert icon on enemy nameplates or floating HUD with timer, proc glow, and almost-ready preview.")

        -- Action Buttons Row 1: Mode & Lock
        local btnMode = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnMode:SetSize(200, 24)
        btnMode:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 2)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnMode) end

        local btnLock = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnLock:SetSize(200, 24)
        btnLock:SetPoint("LEFT", btnMode, "RIGHT", 10, 0)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnLock) end

        optionsWindow.cursorY = optionsWindow.cursorY - 30

        -- Action Buttons Row 2: Test & Reset
        local btnTest = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnTest:SetSize(200, 24)
        btnTest:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 2)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnTest) end

        local btnReset = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnReset:SetSize(200, 24)
        btnReset:SetPoint("LEFT", btnTest, "RIGHT", 10, 0)
        btnReset:SetText(L["Reset HUD Center"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnReset) end

        optionsWindow.cursorY = optionsWindow.cursorY - 34

        local function RefreshActionButtons()
            local curDb = KickBarDB or DEFAULTS
            local isFloating = (curDb.displayMode == "FLOATING")
            btnMode:SetText(isFloating and L["Mode: Floating HUD"] or L["Mode: Nameplate"])
            btnLock:SetText(curDb.locked and L["Locked (Click to Drag)"] or L["Unlocked (Click to Lock)"])
            btnTest:SetText(debugTestMode and L["Test Mode: ON"] or L["Test Mode: OFF"])
        end

        btnMode:SetScript("OnClick", function()
            local curDb = KickBarDB or DEFAULTS
            curDb.displayMode = (curDb.displayMode == "FLOATING") and "NAMEPLATE" or "FLOATING"
            PositionFrame()
            OnUpdate()
            RefreshActionButtons()
        end)

        btnLock:SetScript("OnClick", function()
            local curDb = KickBarDB or DEFAULTS
            curDb.locked = not curDb.locked
            PositionFrame()
            RefreshActionButtons()
        end)

        btnTest:SetScript("OnClick", function()
            debugTestMode = not debugTestMode
            if debugTestMode then StartUpdates() else Wake() end
            RefreshActionButtons()
        end)

        btnReset:SetScript("OnClick", function()
            local curDb = KickBarDB or DEFAULTS
            curDb.posX = 0
            curDb.posY = 150
            curDb.point = "CENTER"
            PositionFrame()
            RefreshActionButtons()
        end)

        -- Scale Slider
        optionsWindow:AddSlider(db, "scale", "Icon scale", 0.6, 2.5, 0.05, "%s: %.2fx", function(val)
            if kickFrame then kickFrame:SetScale(val) end
        end)

        -- Nameplate Anchor Choice
        optionsWindow:AddChoice(db, "anchor", "Nameplate anchor", {
            { value = "LEFT",  text = L["Left"] },
            { value = "RIGHT", text = L["Right"] },
            { value = "TOP",   text = L["Top"] },
        }, function()
            PositionFrame()
            OnUpdate()
        end)

        -- Sound Picker
        optionsWindow:AddSoundPicker(db, "sound", "Sound alert", "None")

        -- Animation Picker
        local animLabel = optionsWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        animLabel:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 6)
        animLabel:SetTextColor(0.8, 0.8, 0.8)

        local function RefreshAnim()
            local curDb = KickBarDB or DEFAULTS
            local aVal = (curDb.animation and curDb.animation ~= "") and curDb.animation or "None"
            animLabel:SetText(L["Animation alert: "] .. aVal)
        end

        local animButton = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        animButton:SetSize(140, 22)
        animButton:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", optionsWindow:GetWidth() - 180, optionsWindow.cursorY - 2)
        animButton:SetText(L["Choose animation"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(animButton) end

        animButton:SetScript("OnClick", function()
            local Triggers = OxedHub.Triggers
            if not Triggers then return end
            local curDb = KickBarDB or DEFAULTS
            local mockTrigger = { actions = { animation = curDb.animation or "" } }
            local origRefresh = Triggers.RefreshTriggersList
            Triggers.RefreshTriggersList = function(self)
                Triggers.RefreshTriggersList = origRefresh
                curDb.animation = mockTrigger.actions.animation
                RefreshAnim()
            end
            Triggers:ShowAnimationPicker(mockTrigger, "animation")
        end)

        animButton.Refresh = RefreshAnim
        table.insert(optionsWindow.checks, animButton)
        optionsWindow.cursorY = optionsWindow.cursorY - 30

        -- Feature Checkboxes
        optionsWindow:AddCheckbox(db, "showCastTimer", "Show cast countdown timer on icon", "Displays remaining enemy cast duration with color shift.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "showAlmostReady", "Almost ready preview (< 2s on CD)", "Displays desaturated preview icon when kick is almost off CD.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "showGlow", "Blizzard proc sparkle glow", "FlipBook sparkle animation when interrupt is ready.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "highlightImportant", "Highlight priority casts in gold", "Uses Blizzard spell database to illuminate critical interrupts.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "trackFocus", "Track focus target casts", "Watches enemy Focus target casts in addition to your current target.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "rangeTint", "Range tinting", "Tints the icon red when target is out of interrupt range.", function()
            OnUpdate()
        end)

        optionsWindow:AddCheckbox(db, "showOnCD", "Show dimmed icon on cooldown", "Displays dimmed icon with sweep when interrupt is on CD.", function()
            OnUpdate()
        end)

        optionsWindow.RefreshUI = function()
            RefreshActionButtons()
            RefreshAnim()
            for _, box in ipairs(optionsWindow.checks) do
                if box.Refresh then box.Refresh() end
            end
        end

        optionsWindow:HookScript("OnShow", function()
            optionsWindow:RefreshUI()
        end)
    end

    optionsWindow:RefreshUI()
    optionsWindow:Show()
end

-- ── Module Registration ─────────────────────────────────────────────────────

local function RegisterModule()
    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "kickbar",
        name     = "KickBar",
        version  = "2.0.0",
        updated  = 20261013.9,
        author   = "Oxed",
        category = "combat",
        keywords = { "kick", "interrupt", "nameplate", "cast", "floating", "pummel", "counterspell" },
        desc     = "Interrupt alert icon on enemy nameplates or floating HUD with timer, proc glow, and almost-ready preview.",
        icon     = "Interface\\Icons\\ability_kick",

        defaults = DEFAULTS,

        OnOptionsShow = function()
            ShowOptions()
        end,

        OnEnable = function(_, config, api)
            KickBarDB = config
            moduleAPI = api
            StartUpdates()
        end,

        OnDisable = function()
            StopUpdates()
        end,
    })
end

-- ── Events ──────────────────────────────────────────────────────────────────

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterUnitEvent("UNIT_PET", "player")

eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target", "focus")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_EMPOWER_START", "target", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

eventFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if interruptSpellID and not IsSecret(spellID) then
            local okNum, numID = pcall(tonumber, spellID)
            if okNum and numID == interruptSpellID then
                lastInterruptAt = GetTime()
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        BindSettings()
        RegisterModule()
        if not OxedHub.ModuleAPI and IsOn() then StartUpdates() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsOn() then StartUpdates() end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        interruptSpellID = nil
        interruptIcon = nil
        if IsOn() then StartUpdates() else StopUpdates() end

    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "UNIT_PET" then
        C_Timer.After(0.5, function()
            FindInterruptSpell()
            Wake()
        end)

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        Wake()

    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        currentNameplate, currentHost = nil, nil
        Wake()
    end
end)

-- ── Slash Commands ──────────────────────────────────────────────────────────

SLASH_KICKBAR1 = "/kickbar"
SLASH_KICKBAR2 = "/kb"
SlashCmdList["KICKBAR"] = function(msg)
    msg = (msg or ""):lower():trim()
    local db = KickBarDB or DEFAULTS

    if msg == "toggle" or msg == "" then
        ShowOptions()

    elseif msg == "on" then
        SetEnabled(true)
        print(L["|cff00ff96KickBar|r: Enabled"])

    elseif msg == "off" then
        SetEnabled(false)
        print(L["|cff00ff96KickBar|r: Disabled"])

    elseif msg == "test" or msg == "debug" then
        debugTestMode = not debugTestMode
        print(L["|cff00ff96KickBar|r: Test Preview "] .. (debugTestMode and "|cff00ff00ON|r" or "|cffff4040OFF|r"))
        if debugTestMode then StartUpdates() else Wake() end
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:RefreshUI() end

    elseif msg == "lock" then
        db.locked = true
        PositionFrame()
        print(L["|cff00ff96KickBar|r: Icon Locked"])
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:RefreshUI() end

    elseif msg == "unlock" then
        db.locked = false
        PositionFrame()
        print(L["|cff00ff96KickBar|r: Icon Unlocked (Drag with Left Mouse Button)"])
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:RefreshUI() end

    elseif msg == "floating" or msg == "mode" then
        db.displayMode = (db.displayMode == "FLOATING") and "NAMEPLATE" or "FLOATING"
        PositionFrame()
        print(L["|cff00ff96KickBar|r: Mode set to |cffffffff"] .. db.displayMode .. "|r")
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:RefreshUI() end

    elseif msg:match("^scale") then
        local val = tonumber(msg:match("scale%s+(.+)"))
        if val and val >= 0.5 and val <= 3.0 then
            db.scale = val
            if kickFrame then kickFrame:SetScale(val) end
            print(L["|cff00ff96KickBar|r: Scale set to "] .. val)
            if optionsFrame and optionsFrame:IsShown() then optionsFrame:RefreshUI() end
        else
            print(L["|cff00ff96KickBar|r: Usage: /kickbar scale 0.5-3.0 (current: "] .. (db.scale or 1.4) .. ")")
        end

    elseif msg == "status" then
        print(L["|cff00ff96KickBar|r Status:"])
        print(L["  Enabled: "] .. tostring(IsOn()))
        print(L["  Mode: "] .. (db.displayMode or "NAMEPLATE"))
        print(L["  Locked: "] .. tostring(db.locked))
        print(L["  Scale: "] .. (db.scale or 1.4))
        if interruptSpellID then
            local name = GetSpellInfoCompat(interruptSpellID)
            print(L["  Interrupt: "] .. (name or "?") .. " (ID: " .. interruptSpellID .. ")")
        else
            print(L["  Interrupt: None found for your class/spec"])
        end

    else
        ShowOptions()
    end
end
