-- ============================================================================
-- Camera (built-in OxedHub module)
-- The game's hidden ActionCam and the camera settings it has no slider for,
-- in one window:
--
--   * Tilt: the camera looks up and your character sits lower on screen, so
--     you see more of what is ahead. Separate angles on foot, while flying
--     and looking down.
--   * Over the shoulder: the character moved to one side of the screen.
--   * Head movement: the camera follows your character's head a little.
--   * Target focus: the camera turns toward your enemy target, or toward
--     the NPC you talk to.
--   * Zoom, turn speed, field of view, follow style, seeing through walls,
--     staying above water.
--   * Situations: enemy focus only in a fight, no shoulder offset while
--     mounted, the whole ActionCam off in raids.
--   * Presets (Subtle, Cinematic, Action, Off) and everything put back as it
--     was when the module is switched off.
--
-- ⚠ Notes for whoever edits this next:
--   * The ActionCam settings are the game's experimental test_camera* CVars.
--     The game asks "use an experimental feature?" when one changes; that
--     popup is closed for the player. A CVar this client does not have
--     answers nil to GetCVar and is simply skipped.
--   * ActionCam does nothing while "Keep Character Centered" is on, and that
--     setting is also part of the game's Motion Sickness option. It is turned
--     off while the tilt or shoulder is used and given back afterwards.
--   * Every CVar this module touches has its original value saved the first
--     time, and OnDisable writes them all back.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    minimapButton = true,   -- its own icon on the minimap while switched on
    enabled            = false,  -- off until the player switches it on (see ModuleAPI:Register)

    -- Tilt (dynamic pitch)
    tilt               = true,
    tiltAngle          = 0.4,    -- 0.01 to 0.99: how far the character sits below the centre
    tiltAngleFlying    = 0.75,
    tiltDown           = 0.25,   -- how much of it stays when you look down
    tiltPivot          = 10,     -- below this distance the tilt eases off

    -- Over the shoulder
    shoulder           = false,
    shoulderOffset     = 1.0,    -- positive: character to the left; negative: to the right

    -- Head movement
    headMove           = false,
    headStrength       = 1,
    headStanding       = 0.3,
    headMoving         = 0.5,
    headRange          = 5,

    -- Target focus
    focusEnemy         = false,
    focusEnemyPitch    = 0.4,
    focusEnemyYaw      = 0.5,
    focusInteract      = false,
    focusInteractPitch = 0.75,
    focusInteractYaw   = 1.0,

    -- The camera's own settings; each only changed while its switch is on
    changeZoom         = false,
    maxZoom            = 2.6,    -- cameraDistanceMaxZoomFactor, 1 to 2.6
    zoomSpeed          = 20,
    changeTurn         = false,
    yawSpeed           = 180,
    pitchSpeed         = 90,
    changeFov          = false,
    fov                = 90,
    changeFollow       = false,
    followStyle        = 1,      -- cameraSmoothStyle
    seeThrough         = false,  -- the camera passes through walls and trees
    seeThroughOffset   = 10,
    aboveWater         = false,  -- the camera stays above the water's surface

    -- Situations
    focusOnlyInCombat  = true,
    noShoulderMounted  = true,
    offInRaids         = false,
}

local settings
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local optionsWindow
local subWindows = {}
local watcher = CreateFrame("Frame")
local PREFIX = "|cff00ff00OxedHub:|r "

-- ── CVars ───────────────────────────────────────────────────────────────────

local TOUCHED = {
    "test_cameraDynamicPitch", "test_cameraDynamicPitchBaseFovPad", "test_cameraDynamicPitchBaseFovPadFlying",
    "test_cameraDynamicPitchBaseFovPadDownScale", "test_cameraDynamicPitchSmartPivotCutoffDist",
    "test_cameraOverShoulder", "test_cameraHeadMovementStrength", "test_cameraHeadMovementStandingStrength",
    "test_cameraHeadMovementMovingStrength", "test_cameraHeadMovementRangeScale",
    "test_cameraTargetFocusEnemyEnable", "test_cameraTargetFocusEnemyStrengthPitch",
    "test_cameraTargetFocusEnemyStrengthYaw", "test_cameraTargetFocusInteractEnable",
    "test_cameraTargetFocusInteractStrengthPitch", "test_cameraTargetFocusInteractStrengthYaw",
    "CameraKeepCharacterCentered", "cameraDistanceMaxZoomFactor", "cameraZoomSpeed", "cameraYawMoveSpeed",
    "cameraPitchMoveSpeed", "cameraFov", "cameraSmoothStyle", "cameraIndirectVisibility",
    "cameraIndirectOffset", "cameraWaterCollision",
}

local function Get(cvar)
    local ok, value = pcall(GetCVar, cvar)
    if not ok then return nil end
    return value
end

-- Only when the value differs: every write of a test_camera CVar may ask the
-- experimental-feature question again.
local function Set(cvar, value)
    local current = Get(cvar)
    if current == nil then return end
    if type(value) == "boolean" then value = value and 1 or 0 end
    value = tostring(value)
    if current == value or tonumber(current) == tonumber(value) then return end
    pcall(SetCVar, cvar, value)
end

-- The player's own values, saved once, before anything is changed.
local function SaveOriginals()
    settings.original = type(settings.original) == "table" and settings.original or {}
    for _, cvar in ipairs(TOUCHED) do
        if settings.original[cvar] == nil then
            local value = Get(cvar)
            if value ~= nil then settings.original[cvar] = value end
        end
    end
end

local function RestoreOriginals()
    if type(settings.original) ~= "table" then return end
    for cvar, value in pairs(settings.original) do
        local current = Get(cvar)
        if current ~= nil and current ~= value then pcall(SetCVar, cvar, value) end
    end
    -- Saved again next time, so a setting the player changes meanwhile counts.
    settings.original = nil
end

-- ── The experimental-feature popup ──────────────────────────────────────────
-- Asked by the game for test_camera CVars. Closed for the player, but only
-- while this module has just changed one.

local closingPopup = 0
local function ClosePopupSoon()
    closingPopup = GetTime() + 2
    C_Timer.After(0, function()
        if StaticPopup_Hide then pcall(StaticPopup_Hide, "EXPERIMENTAL_CVAR_WARNING") end
    end)
end

-- ── Situations ──────────────────────────────────────────────────────────────

-- InCombatLockdown only: UnitAffectingCombat can answer with a secret in a
-- fight, and comparing one is an error. The REGEN events re-apply on change.
local function InCombat() return InCombatLockdown() end

local function Mounted()
    return (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) or false
end

local function InRaid()
    local okInfo, _, kind = pcall(IsInInstance)
    return okInfo and kind == "raid"
end

-- ── Applying ────────────────────────────────────────────────────────────────

local function Apply()
    if not (settings and settings.enabled) then return end
    SaveOriginals()

    local raidOff = settings.offInRaids and InRaid()
    local tilt = settings.tilt and not raidOff
    local shoulder = settings.shoulder and not raidOff and not (settings.noShoulderMounted and Mounted())
    local head = settings.headMove and not raidOff
    local enemy = settings.focusEnemy and not raidOff and (not settings.focusOnlyInCombat or InCombat())
    local interact = settings.focusInteract and not raidOff

    Set("test_cameraDynamicPitch", tilt)
    Set("test_cameraDynamicPitchBaseFovPad", settings.tiltAngle)
    Set("test_cameraDynamicPitchBaseFovPadFlying", settings.tiltAngleFlying)
    Set("test_cameraDynamicPitchBaseFovPadDownScale", settings.tiltDown)
    Set("test_cameraDynamicPitchSmartPivotCutoffDist", settings.tiltPivot)

    Set("test_cameraOverShoulder", shoulder and settings.shoulderOffset or 0)

    Set("test_cameraHeadMovementStrength", head and settings.headStrength or 0)
    Set("test_cameraHeadMovementStandingStrength", settings.headStanding)
    Set("test_cameraHeadMovementMovingStrength", settings.headMoving)
    Set("test_cameraHeadMovementRangeScale", settings.headRange)

    Set("test_cameraTargetFocusEnemyEnable", enemy)
    Set("test_cameraTargetFocusEnemyStrengthPitch", settings.focusEnemyPitch)
    Set("test_cameraTargetFocusEnemyStrengthYaw", settings.focusEnemyYaw)
    Set("test_cameraTargetFocusInteractEnable", interact)
    Set("test_cameraTargetFocusInteractStrengthPitch", settings.focusInteractPitch)
    Set("test_cameraTargetFocusInteractStrengthYaw", settings.focusInteractYaw)

    -- ActionCam is ignored while the character is kept centred. Given back
    -- (the player's own value, which Motion Sickness also sets) when nothing
    -- here needs it.
    if tilt or shoulder or head or enemy or interact then
        Set("CameraKeepCharacterCentered", 0)
    elseif settings.original and settings.original.CameraKeepCharacterCentered then
        Set("CameraKeepCharacterCentered", settings.original.CameraKeepCharacterCentered)
    end

    local orig = settings.original or {}
    local function Own(on, cvar, value)
        if on then Set(cvar, value) elseif orig[cvar] then Set(cvar, orig[cvar]) end
    end
    Own(settings.changeZoom, "cameraDistanceMaxZoomFactor", settings.maxZoom)
    Own(settings.changeZoom, "cameraZoomSpeed", settings.zoomSpeed)
    Own(settings.changeTurn, "cameraYawMoveSpeed", settings.yawSpeed)
    Own(settings.changeTurn, "cameraPitchMoveSpeed", settings.pitchSpeed)
    Own(settings.changeFov, "cameraFov", settings.fov)
    Own(settings.changeFollow, "cameraSmoothStyle", settings.followStyle)
    Own(settings.seeThrough, "cameraIndirectVisibility", 1)
    Own(settings.seeThrough, "cameraIndirectOffset", settings.seeThroughOffset)
    Own(settings.aboveWater, "cameraWaterCollision", 1)

    ClosePopupSoon()
end

-- Many changes come at once (dragging a slider); one write a moment later.
local applyQueued = false
local function QueueApply()
    if applyQueued then return end
    applyQueued = true
    C_Timer.After(0.1, function()
        applyQueued = false
        Apply()
    end)
end

-- ── Presets ─────────────────────────────────────────────────────────────────

local PRESETS = {
    subtle = { tilt = true, tiltAngle = 0.3, tiltAngleFlying = 0.5, tiltDown = 0.25,
               shoulder = false, headMove = false, focusEnemy = false, focusInteract = false },
    cinematic = { tilt = true, tiltAngle = 0.55, tiltAngleFlying = 0.75, tiltDown = 0.3,
                  shoulder = true, shoulderOffset = 0.8, headMove = true, headStrength = 0.5,
                  focusEnemy = false, focusInteract = true },
    action = { tilt = true, tiltAngle = 0.45, tiltAngleFlying = 0.75, tiltDown = 0.25,
               shoulder = true, shoulderOffset = 1.2, headMove = true, headStrength = 1,
               focusEnemy = true, focusOnlyInCombat = true, focusInteract = true },
    off = { tilt = false, shoulder = false, headMove = false, focusEnemy = false, focusInteract = false },
}

local function RefreshWindows()
    for _, w in pairs(subWindows) do
        if w:IsShown() then w:Hide() w:Show() end
    end
    if optionsWindow and optionsWindow:IsShown() then optionsWindow:Hide() optionsWindow:Show() end
end

local function ApplyPreset(name)
    local preset = PRESETS[name]
    if not preset then return end
    for key, value in pairs(preset) do settings[key] = value end
    Apply()
    RefreshWindows()
    print(PREFIX .. (L["camera preset: %s."]):format(name))
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED" then
        if GetTime() < closingPopup then ClosePopupSoon() end
    elseif event == "CVAR_UPDATE" then
        -- The game's Motion Sickness option turns centring back on.
        if arg1 == "CameraKeepCharacterCentered" or arg1 == "CAMERA_KEEP_CHARACTER_CENTERED" then QueueApply() end
    else
        QueueApply()
    end
end)

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "CVAR_UPDATE", "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED",
}

local function Start()
    for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    Apply()
end

local function Stop()
    watcher:UnregisterAllEvents()
    RestoreOriginals()
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(b) end
    return b
end

local function Heading(w, text)
    local h = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 6)
    h:SetText(text)
    w.cursorY = w.cursorY - 24
end

local function FitHeight(w) w:SetHeight(math.max(140, -w.cursorY + 24)) end

local function Row(w, items)
    local width = math.floor((w:GetWidth() - 40 - (#items - 1) * 8) / #items)
    for i, item in ipairs(items) do
        local b = Button(w, item[1], width, item[2])
        b:SetPoint("TOPLEFT", w, "TOPLEFT", 20 + (i - 1) * (width + 8), w.cursorY - 4)
    end
    w.cursorY = w.cursorY - 32
end

local function ToggleSub(name, build)
    local w = subWindows[name]
    if not w then
        w = build()
        subWindows[name] = w
    end
    if w:IsShown() then w:Hide() return end
    for other, window in pairs(subWindows) do
        if other ~= name then window:Hide() end
    end
    if optionsWindow then
        w:ClearAllPoints()
        if (optionsWindow:GetRight() or 0) + w:GetWidth() + 8 <= UIParent:GetWidth() then
            w:SetPoint("TOPLEFT", optionsWindow, "TOPRIGHT", 8, 0)
        else
            w:SetPoint("TOPRIGHT", optionsWindow, "TOPLEFT", -8, 0)
        end
    end
    w:Show()
    w:Raise()
end

local FOLLOW_STYLES = {
    { value = 0, text = "Never turns by itself" },
    { value = 1, text = "Behind you, side to side" },
    { value = 4, text = "Behind you while moving" },
    { value = 2, text = "Always behind you" },
}

local function BuildTiltWindow(API)
    local w = API:CreateOptionsWindow("Camera: Tilt and Shoulder", 460, 560)
    Heading(w, L["Tilt"])
    w:AddCheckbox(settings, "tilt", "Tilt the camera up", "Your character sits lower on screen and you see further ahead.", QueueApply)
    w:AddSlider(settings, "tiltAngle", "On foot", 0.01, 0.99, 0.01, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "tiltAngleFlying", "Flying and skyriding", 0.01, 0.99, 0.01, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "tiltDown", "Kept when looking down", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "tiltPivot", "Eases off when closer than", 0, 30, 1, "%s %d yards", QueueApply)
    Heading(w, L["Over the shoulder"])
    w:AddCheckbox(settings, "shoulder", "Character to one side", nil, QueueApply)
    w:AddSlider(settings, "shoulderOffset", "Offset (negative: right)", -3, 3, 0.1, "%s: %.1f", QueueApply)
    w:AddCheckbox(settings, "noShoulderMounted", "Centred again while mounted or on a flight", nil, QueueApply)
    FitHeight(w)
    return w
end

local function BuildMotionWindow(API)
    local w = API:CreateOptionsWindow("Camera: Head and Focus", 460, 620)
    Heading(w, L["Head movement"])
    w:AddCheckbox(settings, "headMove", "Follow the character's head", nil, QueueApply)
    w:AddSlider(settings, "headStrength", "Strength", 0, 2, 0.1, "%s: %.1f", QueueApply)
    w:AddSlider(settings, "headStanding", "Standing still", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "headMoving", "Moving", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "headRange", "Range", 1, 15, 0.5, "%s: %.1f", QueueApply)
    Heading(w, L["Target focus"])
    w:AddCheckbox(settings, "focusEnemy", "Turn toward your enemy target", nil, QueueApply)
    w:AddCheckbox(settings, "focusOnlyInCombat", "Only in a fight", nil, QueueApply)
    w:AddSlider(settings, "focusEnemyPitch", "Up and down", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "focusEnemyYaw", "Side to side", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddCheckbox(settings, "focusInteract", "Turn toward the NPC you talk to", nil, QueueApply)
    w:AddSlider(settings, "focusInteractPitch", "Up and down", 0, 1, 0.05, "%s: %.2f", QueueApply)
    w:AddSlider(settings, "focusInteractYaw", "Side to side", 0, 1, 0.05, "%s: %.2f", QueueApply)
    FitHeight(w)
    return w
end

local function BuildViewWindow(API)
    local w = API:CreateOptionsWindow("Camera: Zoom and View", 460, 620)
    Heading(w, L["Zoom"])
    w:AddCheckbox(settings, "changeZoom", "Change zoom", "Off: the game's own values are left alone.", QueueApply)
    w:AddSlider(settings, "maxZoom", "Furthest zoom", 1, 2.6, 0.1, "%s: x%.1f", QueueApply)
    w:AddSlider(settings, "zoomSpeed", "Zoom speed", 1, 50, 1, "%s: %d", QueueApply)
    Heading(w, L["Turning"])
    w:AddCheckbox(settings, "changeTurn", "Change turn speed", nil, QueueApply)
    w:AddSlider(settings, "yawSpeed", "Side to side", 30, 360, 10, "%s: %d", QueueApply)
    w:AddSlider(settings, "pitchSpeed", "Up and down", 30, 360, 10, "%s: %d", QueueApply)
    w:AddCheckbox(settings, "changeFollow", "Change how the camera follows", nil, QueueApply)
    w:AddChoice(settings, "followStyle", "Follows", FOLLOW_STYLES, QueueApply)
    Heading(w, L["View"])
    w:AddCheckbox(settings, "changeFov", "Change field of view", nil, QueueApply)
    w:AddSlider(settings, "fov", "Field of view", 50, 90, 1, "%s: %d", QueueApply)
    w:AddCheckbox(settings, "seeThrough", "See through walls and trees", "The camera stays out instead of jumping in when something is behind you.", QueueApply)
    w:AddSlider(settings, "seeThroughOffset", "How much it may pass", 1, 10, 1, "%s: %d", QueueApply)
    w:AddCheckbox(settings, "aboveWater", "Stay above the water", nil, QueueApply)
    FitHeight(w)
    return w
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Camera", 460, 520)
        local w = optionsWindow
        Heading(w, L["Presets"])
        Row(w, {
            { "Subtle", function() ApplyPreset("subtle") end },
            { "Cinematic", function() ApplyPreset("cinematic") end },
            { "Action", function() ApplyPreset("action") end },
            { "Off", function() ApplyPreset("off") end },
        })
        Heading(w, L["In use"])
        w:AddCheckbox(settings, "tilt", "Tilt the camera up", nil, QueueApply)
        w:AddCheckbox(settings, "shoulder", "Over the shoulder", nil, QueueApply)
        w:AddCheckbox(settings, "headMove", "Head movement", nil, QueueApply)
        w:AddCheckbox(settings, "focusEnemy", "Turn toward enemies", nil, QueueApply)
        w:AddCheckbox(settings, "focusInteract", "Turn toward NPCs you talk to", nil, QueueApply)
        w:AddCheckbox(settings, "offInRaids", "All of it off in raids", nil, QueueApply)
        Heading(w, L["Settings"])
        Row(w, {
            { "Tilt and Shoulder", function() ToggleSub("tilt", function() return BuildTiltWindow(API) end) end },
            { "Head and Focus", function() ToggleSub("motion", function() return BuildMotionWindow(API) end) end },
        })
        Row(w, {
            { "Zoom and View", function() ToggleSub("view", function() return BuildViewWindow(API) end) end },
        })
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("Switching the module off puts every camera setting back as it was. /camera opens this window.")
        FitHeight(w)
        w:HookScript("OnHide", function()
            for _, sub in pairs(subWindows) do sub:Hide() end
        end)
    end
    optionsWindow:Show()
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.camera
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.camera = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

SLASH_OXEDCAMERA1 = "/camera"
SLASH_OXEDCAMERA2 = "/oxcam"
SlashCmdList["OXEDCAMERA"] = function(msg)
    if not settings then return end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if PRESETS[msg] then
        if settings.enabled then ApplyPreset(msg) else print(PREFIX .. L["switch the Camera module on first."]) end
    else
        ShowOptions()
    end
end

-- Its own icon on the minimap, like the other modules with a window: a click
-- opens the options, a right-click the options.
MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "camera", label = L["Camera"], icon = "Interface\\Icons\\INV_Misc_Spyglass_03", config = settings,
        hint = L["Click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ShowOptions() end
        end,
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
        id       = "camera",
        name     = "Camera",
        version  = "1.1.0",
        updated  = 20261025.6,  -- its own minimap button
        author   = "Oxed",
        category = "character",
        keywords = { "camera", "actioncam", "tilt", "pitch", "shoulder", "zoom", "fov", "focus", "motion" },
        desc     = "ActionCam in a window: tilt, over the shoulder, target focus, zoom, field of view.",
        icon     = "Interface\\Icons\\INV_Misc_Spyglass_03",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
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
