-- ============================================================================
-- KickBar - Interrupt Alert (built-in OxedHub module)
-- Shows a kick icon on the target's nameplate when your interrupt is off
-- cooldown and the target is casting an interruptible spell.
--
-- States:
--   GREEN  pulsing = interrupt ready + in range  -> KICK NOW!
--   YELLOW         = interrupt ready + out of range
--   RED    dimmed  = interrupt on cooldown (CD sweep shown)
--   HIDDEN         = target not casting / not interruptible / no target
--
-- This used to be an addon of its own, with its own .toc and its own saved
-- variables. It now loads as part of OxedHub: its settings live in
-- OxedHubDB.modules.kickbar, and it is switched on and off from its card on the
-- Modules page, or with /kickbar.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ── Interrupt spell database (first known spell wins) ───────────────────────
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
    WARLOCK     = {},                       -- through Command Demon, see FindInterruptSpell
    WARRIOR     = { 6552 },                 -- Pummel
}

-- ── Default settings ────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled     = false,  -- off until the player switches it on (see ModuleAPI:Register)
    scale       = 1.4,
    alpha       = 1.0,
    anchor      = "LEFT",   -- which side of the nameplate
    offsetX     = -8,
    offsetY     = 0,
    showLabel   = true,
    showOnCD    = true,     -- show dimmed icon when interrupt is on CD
}

-- ── State ───────────────────────────────────────────────────────────────────
-- The module's settings table, OxedHubDB.modules.kickbar, bound at login.
-- Local rather than the old global: it is no longer a saved variable of its
-- own, and a global of the same name would collide with the standalone addon
-- if that is still installed.
local KickBarDB

local playerClass
local interruptSpellID
local interruptIcon
local kickFrame
local currentNameplate
local isShowing = false
local moduleAPI = nil
local castNotInterruptible = false  -- the current cast's flag, possibly a secret
local castShielded = false          -- a readable best guess, for the sound only

-- ── API compatibility wrappers ──────────────────────────────────────────────

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

local function IsSpellInRangeCompat(spellID, unit)
    if C_Spell and C_Spell.IsSpellInRange then
        return C_Spell.IsSpellInRange(spellID, unit)
    end
    if IsSpellInRange then
        local name = GetSpellInfoCompat(spellID)
        if name then
            local r = IsSpellInRange(name, unit)
            return r == 1
        end
    end
    return nil
end

-- ── Find the player's interrupt spell ───────────────────────────────────────

-- ── Is the interrupt actually ready? ────────────────────────────────────────
-- The old check read the cooldown's start and duration and compared them. In
-- combat those come back as secret values, the comparison throws, and the
-- fallback it landed in assumed "ready" -- so in exactly the fights where it
-- mattered, the icon said KICK! with the interrupt still on cooldown.
--
-- isActive is the one field that is never secret. It is also true during the
-- global cooldown, though, so on its own every other spell cast would grey the
-- kick out for a second and a half. The spell's base cooldown is plain static
-- data, and together with when the interrupt was last used it tells a real
-- cooldown apart from the GCD. Same approach as the action hub's cooldowns.

local lastInterruptAt = nil

local function IsGlobalCooldownOnly(spellID)
    local baseMs = 0
    if GetSpellBaseCooldown then
        local ok, value = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(value) == "number" then baseMs = value end
    end
    -- No cooldown of its own: whatever is running is the GCD.
    if baseMs <= 1500 then return true end
    -- Never used, or used long enough ago that its own cooldown is over.
    if not lastInterruptAt then return true end
    return (GetTime() - lastInterruptAt) > (baseMs / 1000)
end

local function IsInterruptReady()
    if not interruptSpellID then return false end

    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, active = pcall(function()
            local info = C_Spell.GetSpellCooldown(interruptSpellID)
            if type(info) ~= "table" or info.isActive == nil then return nil end
            return info.isActive == true
        end)
        if ok and active ~= nil then
            if active and IsGlobalCooldownOnly(interruptSpellID) then active = false end
            return not active
        end
    end

    -- Clients without isActive: the numbers are readable there.
    local start, duration = GetSpellCooldownCompat(interruptSpellID)
    local ok, ready = pcall(function()
        if not start or start == 0 or not duration or duration == 0 then return true end
        return duration <= 1.5
    end)
    if ok then return ready end

    -- Nothing readable at all. Not ready is the safe answer: greying out a
    -- kick that is up costs a glance, calling KICK! on one that is down costs
    -- the cast you meant to stop.
    return false
end

-- The cooldown sweep. Numeric SetCooldown is closed to addons in this version;
-- the duration object is the route that is allowed, secrets and all.
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
    -- Older clients: plain numbers, still guarded in case they are secret.
    local start, duration = GetSpellCooldownCompat(interruptSpellID)
    local ok = pcall(function()
        if duration and duration > 1.5 then
            cdFrame:SetCooldown(start, duration)
            cdFrame:Show()
        else
            cdFrame:Hide()
        end
    end)
    if not ok then cdFrame:Hide() end
end

-- A warlock does not kick with a spell of their own. Their pet does, and the
-- player orders it through Command Demon, which turns into the pet's interrupt
-- while that pet is out. The pet's own spell ids (19647, 89766) are never known
-- to the player, which is why looking for them found no interrupt at all.
local COMMAND_DEMON = 119898
local COMMAND_DEMON_INTERRUPTS = {
    [119910] = true,  -- Spell Lock (Felhunter)
    [132409] = true,  -- Spell Lock (Fel Ravager)
    [119914] = true,  -- Axe Toss (Felguard)
}

local function KnowsSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id)
        if ok and known then return true end
    end
    return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false
end

-- The id actually on the player's bar: talents can replace a spell with a
-- version of their own, and that is the one whose cooldown and range count.
local function Resolved(id)
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
        local override = Resolved(COMMAND_DEMON)
        if COMMAND_DEMON_INTERRUPTS[override] then found = override end
    end

    if not found then
        for _, id in ipairs(INTERRUPT_SPELLS[playerClass] or {}) do
            if KnowsSpell(id) then
                found = Resolved(id)
                break
            end
        end
    end

    if found then
        interruptSpellID = found
        local _, _, icon = GetSpellInfoCompat(found)
        interruptIcon = icon
    end
end

-- Talents, a spec change and a new pet all settle over several events in a
-- row, and the spellbook is not final at the first of them. One rescan a
-- moment after the last one reads it once it has.
local rescanPending = false
local function QueueRescan(restart)
    if rescanPending then return end
    rescanPending = true
    C_Timer.After(0.5, function()
        rescanPending = false
        restart()
    end)
end

-- ── Build the kick icon frame ───────────────────────────────────────────────

local function CreateKickFrame()
    if kickFrame then return end

    -- No global name: nothing looks it up by name, and "KickBarFrame" would be
    -- shared with the standalone addon if both happened to be loaded.
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:EnableMouse(false)
    f:SetSize(38, 38)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(500)
    f:Hide()

    -- Dark backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    f:SetBackdropBorderColor(0, 1, 0, 1)

    -- Spell icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon

    -- Cooldown sweep
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", 2, -2)
    cd:SetPoint("BOTTOMRIGHT", -2, 2)
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(false)
    cd:Hide()
    f.cooldown = cd

    -- Outer glow (larger colored border behind the frame)
    local glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetPoint("TOPLEFT", -5, 5)
    glow:SetPoint("BOTTOMRIGHT", 5, -5)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0, 1, 0, 0)
    f.glow = glow

    -- "KICK" label below icon
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", f, "BOTTOM", 0, -1)
    label:SetText("KICK")
    label:SetTextColor(0, 1, 0, 1)
    f.label = label

    -- Pulse animation group (scale)
    local scaleAg = f:CreateAnimationGroup()
    scaleAg:SetLooping("REPEAT")
    local up = scaleAg:CreateAnimation("Scale")
    up:SetScaleFrom(1, 1)
    up:SetScaleTo(1.15, 1.15)
    up:SetDuration(0.35)
    up:SetOrder(1)
    up:SetSmoothing("IN_OUT")
    local down = scaleAg:CreateAnimation("Scale")
    down:SetScaleFrom(1.15, 1.15)
    down:SetScaleTo(1, 1)
    down:SetDuration(0.35)
    down:SetOrder(2)
    down:SetSmoothing("IN_OUT")
    f.pulseAnim = scaleAg

    -- Glow alpha pulse
    local glowAg = f.glow:CreateAnimationGroup()
    glowAg:SetLooping("REPEAT")
    local gIn = glowAg:CreateAnimation("Alpha")
    gIn:SetFromAlpha(0.35)
    gIn:SetToAlpha(0.85)
    gIn:SetDuration(0.4)
    gIn:SetOrder(1)
    local gOut = glowAg:CreateAnimation("Alpha")
    gOut:SetFromAlpha(0.85)
    gOut:SetToAlpha(0.35)
    gOut:SetDuration(0.4)
    gOut:SetOrder(2)
    f.glowAnim = glowAg

    -- Fade-in animation
    local fadeIn = f:CreateAnimationGroup()
    local a = fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.15)
    f.fadeIn = fadeIn

    kickFrame = f
end

-- ── Core update logic ───────────────────────────────────────────────────────

local elapsed = 0
local UPDATE_RATE = 0.04

local function ShowKick()
    if not isShowing then
        isShowing = true
        kickFrame:Show()
        -- ⚠ No fade-in. An Alpha animation on the frame itself drives the
        -- frame's alpha while it plays, which overrode SetAlphaFromBoolean and
        -- flashed the icon on casts that cannot be interrupted. Animations on
        -- child textures (the glow) are fine: a child's alpha multiplies the
        -- frame's, so a hidden frame keeps them hidden.
    end
end

local function HideKick()
    if isShowing then
        isShowing = false
        kickFrame.pulseAnim:Stop()
        kickFrame.glowAnim:Stop()
        kickFrame:Hide()
        currentNameplate = nil
    end
end

-- The update loop only runs while the target is casting. It used to run every
-- frame for as long as the module was on -- flying round a city with no target
-- at all -- which /oxprofile showed as one call per frame, all session. A cast
-- starting on the target wakes it (see the events at the bottom of the file),
-- and the first tick that finds nothing to watch puts it back to sleep.
local function Sleep(frame)
    HideKick()
    frame:SetScript("OnUpdate", nil)
end

local function OnUpdate(self, dt)
    elapsed = elapsed + dt
    if elapsed < UPDATE_RATE then return end
    elapsed = 0

    local db = KickBarDB or DEFAULTS

    -- Must be enabled and have an interrupt spell
    if not db.enabled or not interruptSpellID then
        Sleep(self)
        return
    end

    -- Must have an attackable, alive target
    if not UnitExists("target") or not UnitCanAttack("player", "target") or UnitIsDead("target") then
        Sleep(self)
        return
    end

    -- Check if target is casting or channeling
    local castName, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("target")
    local isCasting = castName ~= nil
    if not isCasting then
        castName, _, _, _, _, _, notInterruptible = UnitChannelInfo("target")
        isCasting = castName ~= nil
    end

    if not isCasting then
        Sleep(self)
        return
    end

    -- ⚠ WHETHER THE CAST CAN BE INTERRUPTED. Do not go back to reading the
    -- castbars for this.
    --
    -- In combat notInterruptible is a secret value: comparing it errors, so the
    -- addon cannot know the answer. The old code guessed from the shield on a
    -- visible castbar, and whenever no castbar was showing -- a different UI,
    -- the castbar turned off -- it guessed "interruptible" and put KICK! on
    -- casts that cannot be kicked.
    --
    -- The frame is handed the secret instead (SetAlphaFromBoolean, further
    -- down), and the game itself hides the icon when the cast cannot be
    -- interrupted. castShielded below is only a best guess, and only decides
    -- whether to play the sound, which the game has no way to hide for us.
    if notInterruptible == nil then notInterruptible = false end
    castNotInterruptible = notInterruptible

    local safeNotInterruptible = false
    do
        local ok, val = pcall(function() return notInterruptible == true end)
        if ok then
            safeNotInterruptible = val
        else
            -- A secret: read the castbars, for the sound only.
            local isShielded = false

            pcall(function()
                -- 1. Default UI Target Frame
                if TargetFrameSpellBar and TargetFrameSpellBar.IsVisible and TargetFrameSpellBar:IsVisible() then
                    if TargetFrameSpellBar.BorderShield and TargetFrameSpellBar.BorderShield.IsVisible and TargetFrameSpellBar.BorderShield:IsVisible() then
                        isShielded = true
                    end
                end

                -- 2. Default UI Nameplates
                local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
                if not isShielded and np and np.UnitFrame and np.UnitFrame.CastBar and np.UnitFrame.CastBar.IsVisible and np.UnitFrame.CastBar:IsVisible() then
                    if np.UnitFrame.CastBar.BorderShield and np.UnitFrame.CastBar.BorderShield.IsVisible and np.UnitFrame.CastBar.BorderShield:IsVisible() then
                        isShielded = true
                    end
                end

                -- 3. Plater Nameplates
                if not isShielded and np and np.unitFrame and np.unitFrame.castBar and np.unitFrame.castBar.IsVisible and np.unitFrame.castBar:IsVisible() then
                    if np.unitFrame.castBar.Shield and np.unitFrame.castBar.Shield.IsVisible and np.unitFrame.castBar.Shield:IsVisible() then
                        isShielded = true
                    end
                end

                -- 4. ElvUI Target Frame
                if not isShielded and ElvUF_Target and ElvUF_Target.Castbar and ElvUF_Target.Castbar.IsVisible and ElvUF_Target.Castbar:IsVisible() then
                    if ElvUF_Target.Castbar.notInterruptible then
                        isShielded = true
                    end
                end
            end)

            safeNotInterruptible = isShielded
        end
    end

    castShielded = safeNotInterruptible

    -- ── Target IS casting an interruptible spell! ───────────────────────

    -- Check interrupt cooldown
    local isReady = IsInterruptReady()

    -- If on CD and user doesn't want to see CD state, hide
    if not isReady and not db.showOnCD then
        HideKick()
        return
    end

    -- Check range
    local inRange = IsSpellInRangeCompat(interruptSpellID, "target")
    if inRange == nil then inRange = true end

    -- ── Position on nameplate ───────────────────────────────────────────

    local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit("target")
    if np ~= currentNameplate then
        currentNameplate = np
        kickFrame:ClearAllPoints()
        if np then
            kickFrame:SetParent(np)
            local anchor = db.anchor or "LEFT"
            if anchor == "LEFT" then
                kickFrame:SetPoint("RIGHT", np, "LEFT", db.offsetX or -8, db.offsetY or 0)
            elseif anchor == "RIGHT" then
                kickFrame:SetPoint("LEFT", np, "RIGHT", -(db.offsetX or -8), db.offsetY or 0)
            else
                kickFrame:SetPoint("BOTTOM", np, "TOP", db.offsetX or 0, db.offsetY or 5)
            end
        else
            -- No nameplate visible - show near screen center
            kickFrame:SetParent(UIParent)
            kickFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        end
        kickFrame:SetFrameStrata("HIGH")
        kickFrame:SetFrameLevel(500)
    end

    -- ── Apply scale ─────────────────────────────────────────────────────
    kickFrame:SetScale(db.scale or 1.4)
    -- The game decides visibility from the secret: fully transparent when the
    -- cast cannot be interrupted, the chosen alpha when it can. Plain booleans
    -- are accepted too, so the same call serves out of combat. Clients without
    -- the setter fall back to the readable answer, where there is one.
    if kickFrame.SetAlphaFromBoolean then
        kickFrame:SetAlphaFromBoolean(castNotInterruptible, 0, db.alpha or 1.0)
    else
        kickFrame:SetAlpha(castShielded and 0 or (db.alpha or 1.0))
    end

    -- ── Update icon ─────────────────────────────────────────────────────
    if interruptIcon then
        kickFrame.icon:SetTexture(interruptIcon)
    end

    -- ── Visual state ────────────────────────────────────────────────────
    if isReady and inRange then
        -- GREEN PULSING - KICK NOW!
        kickFrame:SetBackdropBorderColor(0.1, 1, 0.1, 1)
        kickFrame.glow:SetVertexColor(0.1, 1, 0.1, 0.6)
        kickFrame.icon:SetDesaturated(false)
        kickFrame.icon:SetVertexColor(1, 1, 1, 1)
        kickFrame.label:SetTextColor(0.1, 1, 0.1, 1)
        kickFrame.label:SetText("KICK!")
        kickFrame.cooldown:Hide()
        if not kickFrame.pulseAnim:IsPlaying() then
            kickFrame.pulseAnim:Play()
            kickFrame.glowAnim:Play()

            -- The sound and animation picked in the module's options. Skipped
            -- when the castbars show a shield: the icon is already hidden for
            -- such a cast, but a sound cannot be hidden, so this is the one
            -- place the best guess is still used.
            if moduleAPI and not castShielded then
                if db.sound and db.sound ~= "" and moduleAPI.sounds then
                    moduleAPI.sounds:Play(db.sound)
                end
                if db.animation and db.animation ~= "" and moduleAPI.animations then
                    moduleAPI.animations:Play(db.animation)
                end
            end
        end

    elseif isReady and not inRange then
        -- YELLOW - ready but out of range
        kickFrame:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        kickFrame.glow:SetVertexColor(1, 0.82, 0, 0.3)
        kickFrame.icon:SetDesaturated(false)
        kickFrame.icon:SetVertexColor(1, 1, 1, 0.85)
        kickFrame.label:SetTextColor(1, 0.82, 0, 1)
        kickFrame.label:SetText("RANGE")
        kickFrame.cooldown:Hide()
        kickFrame.pulseAnim:Stop()
        kickFrame.glowAnim:Stop()

    else
        -- RED - on cooldown
        kickFrame:SetBackdropBorderColor(0.8, 0.15, 0.15, 0.7)
        kickFrame.glow:SetVertexColor(0, 0, 0, 0)
        kickFrame.icon:SetDesaturated(true)
        kickFrame.icon:SetVertexColor(1, 1, 1, 0.5)
        kickFrame.label:SetTextColor(0.8, 0.15, 0.15, 0.8)
        kickFrame.label:SetText("CD")
        kickFrame.pulseAnim:Stop()
        kickFrame.glowAnim:Stop()
        PaintCooldown(kickFrame.cooldown)
    end

    -- Show label
    kickFrame.label:SetShown(db.showLabel ~= false)

    ShowKick()
end

-- ── Starting and stopping ───────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")

local function IsOn()
    return KickBarDB ~= nil and KickBarDB.enabled ~= false
end

-- Runs the check only while switched on and while the class actually has an
-- interrupt. The old code started it on every login regardless, so turning the
-- module off only hid the icon while the loop kept running underneath.
-- Starts the update loop if there is a cast worth watching right now: an
-- attackable target that is casting or channelling. Otherwise the loop stays
-- off and the icon hidden; the next cast on the target calls this again.
local function Wake()
    if not (IsOn() and interruptSpellID and kickFrame) then
        HideKick()
        eventFrame:SetScript("OnUpdate", nil)
        return
    end
    local attackable = UnitExists("target") and UnitCanAttack("player", "target")
        and not UnitIsDead("target")
    -- ⚠ Take the answer into a local first. With nothing being cast these
    -- return NO VALUES at all, not nil, and type() with no argument is an
    -- error: "bad argument #1 to '?' (value expected)". Passing the call
    -- straight into type() threw every time the player took a target that was
    -- not casting.
    local castName, channelName
    if attackable then
        castName = UnitCastingInfo("target")
        channelName = UnitChannelInfo("target")
    end
    local casting = attackable and (castName ~= nil or channelName ~= nil)
    if casting then
        eventFrame:SetScript("OnUpdate", OnUpdate)
    else
        HideKick()
        eventFrame:SetScript("OnUpdate", nil)
    end
end

local function StartUpdates()
    FindInterruptSpell()
    CreateKickFrame()
    Wake()
end

local function StopUpdates()
    HideKick()
    eventFrame:SetScript("OnUpdate", nil)
end

-- The settings table, created with every default it is missing. Bound whether
-- or not the module is on: switched off, OnEnable never runs, and the old code
-- then invented a fresh table with enabled = true and ran anyway.
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

-- On and off through the Modules page whenever it is there, so the card's tick
-- box, the saved flag and the running loop can never disagree.
local function SetEnabled(on)
    if OxedHub.ModuleAPI and OxedHub.ModuleAPI:GetModule("kickbar") then
        OxedHub.ModuleAPI:SetModuleEnabled("kickbar", on)
    else
        if KickBarDB then KickBarDB.enabled = on end
        if on then StartUpdates() else StopUpdates() end
    end
end

-- ── Options window ──────────────────────────────────────────────────────────

local optionsFrame

local function ShowOptions()
    if not optionsFrame then
        local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(400, 300)
        f:SetPoint("CENTER")
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
        f.title:SetText("KickBar Settings")
        -- Above the OxedHub window, below the pickers it opens.
        --
        -- Same strata as the main window but at the default level, it drew
        -- under the window's sidebar and content, which sit well above their
        -- base level. The sound and animation pickers are DIALOG at level 220,
        -- so this stays just under them: a strata higher and the picker opened
        -- by "Select Sound" would itself be hidden behind these settings.
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetClampedToScreen(true)

        local function OpenPicker(pickerType, callback)
            local Triggers = OxedHub.Triggers
            if not Triggers then return end

            local mockTrigger = { actions = {} }

            local origRefresh = Triggers.RefreshTriggersList
            Triggers.RefreshTriggersList = function(self)
                Triggers.RefreshTriggersList = origRefresh -- restore immediately
                callback(mockTrigger.actions[pickerType])
            end

            if pickerType == "sound" then
                Triggers:ShowSoundPicker(mockTrigger, "sound")
            elseif pickerType == "animation" then
                Triggers:ShowAnimationPicker(mockTrigger, "animation")
            end
        end

        local soundLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        soundLabel:SetPoint("TOPLEFT", 20, -40)
        soundLabel:SetText("Sound:")

        local soundValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        soundValue:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", 0, -8)
        soundValue:SetText("None")
        f.soundValue = soundValue

        local soundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        soundBtn:SetSize(120, 22)
        soundBtn:SetPoint("LEFT", soundValue, "RIGHT", 15, 0)
        soundBtn:SetText("Select Sound")
        soundBtn:SetScript("OnClick", function()
            OpenPicker("sound", function(val)
                if KickBarDB then KickBarDB.sound = val end
                f.soundValue:SetText((val and val ~= "") and val or "None")
            end)
        end)

        local animLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        animLabel:SetPoint("TOPLEFT", soundValue, "BOTTOMLEFT", 0, -20)
        animLabel:SetText("Animation:")

        local animValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        animValue:SetPoint("TOPLEFT", animLabel, "BOTTOMLEFT", 0, -8)
        animValue:SetText("None")
        f.animValue = animValue

        local animBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        animBtn:SetSize(120, 22)
        animBtn:SetPoint("LEFT", animValue, "RIGHT", 15, 0)
        animBtn:SetText("Select Animation")
        animBtn:SetScript("OnClick", function()
            OpenPicker("animation", function(val)
                if KickBarDB then KickBarDB.animation = val end
                f.animValue:SetText((val and val ~= "") and val or "None")
            end)
        end)

        local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", animValue, "BOTTOMLEFT", 0, -30)
        desc:SetWidth(360)
        desc:SetJustifyH("LEFT")
        desc:SetText("Select an OxedHub sound or animation to play when your kick becomes ready.")

        -- Make frame draggable
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        optionsFrame = f
    end

    local currentSound = KickBarDB and KickBarDB.sound or ""
    optionsFrame.soundValue:SetText(currentSound ~= "" and currentSound or "None")

    local currentAnim = KickBarDB and KickBarDB.animation or ""
    optionsFrame.animValue:SetText(currentAnim ~= "" and currentAnim or "None")

    optionsFrame:Show()
end

-- ── Module registration ─────────────────────────────────────────────────────

local function RegisterModule()
    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "kickbar",
        name     = "KickBar",
        version  = "1.2.0",
        author   = "Oxed",
        category = "combat",
        desc     = "Shows a kick alert icon on enemy nameplates when your interrupt is ready.",
        icon     = "Interface\\Icons\\ability_kick",

        defaults = DEFAULTS,

        OnOptionsShow = function()
            ShowOptions()
        end,

        -- Register calls this at login when the module is on, and the Modules
        -- page calls it when it is switched back on.
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
-- The interrupt can change without a spec change: a talent that replaces it,
-- or a warlock summoning a different pet.
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:RegisterUnitEvent("UNIT_PET", "player")
-- A cast starting on the target is what wakes the update loop; nothing else
-- needs it running.
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "target")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "target")
pcall(eventFrame.RegisterUnitEvent, eventFrame, "UNIT_SPELLCAST_EMPOWER_START", "target")
-- When the interrupt was last used, for telling its cooldown from the GCD.
-- The pet as well: Spell Lock is the warlock's pet casting, not the warlock.
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

eventFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if interruptSpellID and tonumber(spellID) == interruptSpellID then
            lastInterruptAt = GetTime()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        BindSettings()
        -- Starts the check through OnEnable when the module is switched on.
        RegisterModule()
        -- Without the Modules page to hand the switch to, start it directly.
        if not OxedHub.ModuleAPI and IsOn() then StartUpdates() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The interrupt known can change while away (talents, a spec swap).
        if IsOn() then StartUpdates() end

    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Re-scan for interrupt spell (different specs may have different interrupts)
        interruptSpellID = nil
        interruptIcon = nil
        if IsOn() then StartUpdates() else StopUpdates() end

    elseif event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED" or event == "UNIT_PET" then
        if IsOn() then QueueRescan(StartUpdates) end

    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_EMPOWER_START" then
        Wake()

    elseif event == "PLAYER_TARGET_CHANGED" then
        currentNameplate = nil
        -- The new target may already be half way through a cast.
        Wake()
    end
end)

-- ── Slash commands ──────────────────────────────────────────────────────────

SLASH_KICKBAR1 = "/kickbar"
SLASH_KICKBAR2 = "/kb"
SlashCmdList["KICKBAR"] = function(msg)
    msg = (msg or ""):lower():trim()
    local db = KickBarDB or DEFAULTS

    if msg == "toggle" or msg == "" then
        SetEnabled(not IsOn())
        print("|cff00ff00KickBar|r: " .. (IsOn() and "Enabled" or "Disabled"))

    elseif msg == "on" then
        SetEnabled(true)
        print("|cff00ff00KickBar|r: Enabled")

    elseif msg == "off" then
        SetEnabled(false)
        print("|cff00ff00KickBar|r: Disabled")

    elseif msg:match("^scale") then
        local val = tonumber(msg:match("scale%s+(.+)"))
        if val and val >= 0.5 and val <= 3.0 then
            db.scale = val
            print("|cff00ff00KickBar|r: Scale set to " .. val)
        else
            print("|cff00ff00KickBar|r: Usage: /kickbar scale 0.5-3.0 (current: " .. (db.scale or 1.4) .. ")")
        end

    elseif msg == "cd" then
        db.showOnCD = not db.showOnCD
        print("|cff00ff00KickBar|r: Show on cooldown: " .. (db.showOnCD and "ON" or "OFF"))

    elseif msg == "label" then
        db.showLabel = not db.showLabel
        print("|cff00ff00KickBar|r: Label: " .. (db.showLabel and "ON" or "OFF"))

    elseif msg:match("^sound") then
        local val = msg:match("sound%s+(.+)")
        db.sound = val or ""
        print("|cff00ff00KickBar|r: Sound set to '" .. db.sound .. "'")

    elseif msg:match("^anim") then
        local val = msg:match("anim%s+(.+)")
        db.animation = val or ""
        print("|cff00ff00KickBar|r: Animation set to '" .. db.animation .. "'")

    elseif msg == "status" then
        print("|cff00ff00KickBar|r Status:")
        print("  Enabled: " .. tostring(IsOn()))
        print("  Scale: " .. (db.scale or 1.4))
        print("  Show on CD: " .. tostring(db.showOnCD))
        print("  Show label: " .. tostring(db.showLabel))
        if interruptSpellID then
            local name = GetSpellInfoCompat(interruptSpellID)
            print("  Interrupt: " .. (name or "?") .. " (ID: " .. interruptSpellID .. ")")
        else
            print("  Interrupt: None found for your class/spec")
        end

    else
        print("|cff00ff00KickBar|r Commands:")
        print("  /kickbar         - Toggle on/off")
        print("  /kickbar on/off  - Enable or disable")
        print("  /kickbar scale # - Set icon scale (0.5-3.0)")
        print("  /kickbar cd      - Toggle show on cooldown")
        print("  /kickbar label   - Toggle KICK/RANGE/CD label")
        print("  /kickbar status  - Show current settings")
    end
end
