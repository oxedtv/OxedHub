-- ============================================================================
-- Heartbeat & LowHP Alert (built-in OxedHub module)
-- Audio tension & low health warning system:
--
--   * Normal Heartbeat: Plays steady pulse when HP drops below warning threshold.
--   * Fast Heartbeat: Triggers at 35% HP (or customizable critical threshold)
--     with rapid, intense pulse + optional one-shot LowHP warning alarm.
--   * Death Sound: Flatline / cardiac arrest sound when the player dies.
--   * Inspired by Heartbeat Trigger + LowHP addon, unified into a clean module.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

-- ── Default Settings ────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled            = false,   -- off until player enables it
    combatOnly         = true,    -- only beat during combat
    criticalThreshold  = 35,      -- % HP for fast/danger pulse (user standard: 35%)
    warningThreshold   = 60,      -- % HP for normal pulse
    alwaysInCombat     = false,   -- play normal pulse whenever in combat regardless of HP

    -- Audio settings
    soundLevel         = "normal", -- "normal", "lower" (-5dB), "lowest" (-10dB)
    volumeMultiplier   = 2,        -- 1x to 4x (plays layered copies for combat audibility)
    soundChannel       = "Master",

    -- Death Audio
    playDeathSound     = true,    -- play flatline on death

    -- Blizzard LowHealthFrame integration
    useLowHealthFrame  = true,    -- triggers fast pulse if Blizzard's LowHealthFrame activates
}

local settings
local optionsWindow
local moduleActive = false
local inCombat = false
local currentState = "NONE" -- "NONE", "NORMAL", "FAST", "DEAD"
local currentHandles = {}
local beatTimer = nil
local testModeState = nil

-- Base intervals in seconds for each pulse rhythm
local INTERVALS = {
    normal  = 1.981,
    faster  = 1.844,
    intense = 1.654,
    danger  = 1.237,
    dead    = 6.808,
}

local SOUND_FILES = {
    normal  = "1",
    faster  = "2",
    intense = "3",
    danger  = "4",
    dead    = "5",
}

-- ── Helper Functions ────────────────────────────────────────────────────────

local issecretvalue = _G.issecretvalue
local issecret = _G.issecret

local function IsSecret(val)
    if val == nil then return false end
    if issecretvalue and issecretvalue(val) then return true end
    if issecret and issecret(val) then return true end
    return false
end

local function IsBlizzardLowHealthActive()
    local f = _G["LowHealthFrame"]
    return f and f.IsShown and f:IsShown()
end

local function GetPlayerHealthPercent()
    local ok, pct = pcall(function()
        local curHP = UnitHealth("player")
        if IsSecret(curHP) then return nil end
        local maxHP = UnitHealthMax("player")
        if IsSecret(maxHP) then return nil end
        if not maxHP or maxHP <= 0 then return 100 end
        return (curHP / maxHP) * 100
    end)
    if ok and type(pct) == "number" then
        return pct
    end

    -- If health arithmetic is blocked because values are secret (combat taint):
    -- Fall back to Blizzard's native LowHealthFrame which glows at <= 35% HP
    if IsBlizzardLowHealthActive() then
        return 20
    end
    return 100
end

local function GetSoundPath(stateKey)
    local base = SOUND_FILES[stateKey]
    if not base then return nil end
    local suffix = ".ogg"
    if settings and settings.soundLevel == "lower" then
        suffix = "-5.ogg"
    elseif settings and settings.soundLevel == "lowest" then
        suffix = "-10.ogg"
    end
    return "Interface\\AddOns\\OxedHub\\Media\\Sounds\\Heartbeat\\" .. base .. suffix
end

local function StopCurrentSounds()
    if beatTimer then
        beatTimer:Cancel()
        beatTimer = nil
    end
    for i = 1, #currentHandles do
        if currentHandles[i] then
            StopSound(currentHandles[i], 300)
            currentHandles[i] = nil
        end
    end
    wipe(currentHandles)
end

local function PlayPulseBeat(stateKey)
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.soundsEnabled == false then
        return
    end

    local path = GetSoundPath(stateKey)
    if not path then return end

    local channel = (settings and settings.soundChannel) or "Master"
    local mult = (settings and settings.volumeMultiplier) or 2

    for i = 1, mult do
        local willPlay, handle = PlaySoundFile(path, channel)
        if willPlay and handle then
            table.insert(currentHandles, handle)
        end
    end
end

-- ── Rhythm Loop ─────────────────────────────────────────────────────────────

local function ScheduleNextBeat(stateKey, interval)
    if not moduleActive and not testModeState then return end
    if currentState ~= "NORMAL" and currentState ~= "FAST" then return end

    beatTimer = C_Timer.NewTimer(interval, function()
        if not moduleActive and not testModeState then return end
        PlayPulseBeat(stateKey)
        ScheduleNextBeat(stateKey, interval)
    end)
end

local function TransitionTo(newState, forceRestart)
    if currentState == newState and not forceRestart then return end

    StopCurrentSounds()
    currentState = newState

    if newState == "NONE" then
        return
    elseif newState == "NORMAL" then
        PlayPulseBeat("normal")
        ScheduleNextBeat("normal", INTERVALS.normal)
    elseif newState == "FAST" then
        PlayPulseBeat("danger")
        ScheduleNextBeat("danger", INTERVALS.danger)
    elseif newState == "DEAD" then
        if settings and settings.playDeathSound ~= false then
            PlayPulseBeat("dead")
        end
    end
end

-- ── Health & Combat State Evaluator ─────────────────────────────────────────

local function EvaluateHealthState()
    if testModeState then return end
    if not moduleActive or not settings or not settings.enabled then
        TransitionTo("NONE")
        return
    end

    -- 1. Dead or Ghost check
    if UnitIsDeadOrGhost("player") then
        TransitionTo("DEAD")
        return
    end

    -- 2. Combat restriction check
    if settings.combatOnly and not inCombat then
        TransitionTo("NONE")
        return
    end

    -- 3. Calculate Health Percent
    local hp = GetPlayerHealthPercent()
    local crit = settings.criticalThreshold or 35
    local warn = settings.warningThreshold or 60

    -- 4. Check Critical Zone (35% or LowHealthFrame active)
    local isLowHealthVisual = settings.useLowHealthFrame and IsBlizzardLowHealthActive()
    if hp <= crit or isLowHealthVisual then
        TransitionTo("FAST")
        return
    end

    -- 5. Check Warning Zone
    if hp <= warn or (settings.alwaysInCombat and inCombat) then
        TransitionTo("NORMAL")
        return
    end

    -- 6. Safe & Healthy
    TransitionTo("NONE")
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")
local updateTicker = nil

local function StartModule()
    moduleActive = true
    inCombat = InCombatLockdown() or false

    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "player")
    eventFrame:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_UNGHOST")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Regular 0.25s watchdog ticker to monitor LowHealthFrame & smooth health transitions
    if not updateTicker then
        updateTicker = C_Timer.NewTicker(0.25, function()
            if moduleActive and not testModeState then
                EvaluateHealthState()
            end
        end)
    end

    EvaluateHealthState()
end

local function StopModule()
    moduleActive = false
    testModeState = nil
    StopCurrentSounds()
    currentState = "NONE"

    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    eventFrame:UnregisterAllEvents()
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        EvaluateHealthState()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        EvaluateHealthState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        EvaluateHealthState()
    elseif event == "PLAYER_DEAD" then
        TransitionTo("DEAD")
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        StopCurrentSounds()
        EvaluateHealthState()
    elseif event == "PLAYER_ENTERING_WORLD" then
        inCombat = InCombatLockdown() or false
        C_Timer.After(1, EvaluateHealthState)
    end
end)

-- ── Settings Binding ────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.heartbeat
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.heartbeat = config
    end
    for k, v in pairs(DEFAULTS) do
        if config[k] == nil then config[k] = v end
    end
    settings = config
end

-- ── Options Window ──────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Heartbeat", 440, 450)

        optionsWindow:AddNote("Dynamic heartbeat audio tension: plays a steady pulse when injured or in combat, speeding up into an intense rapid pulse at 35% health.")

        optionsWindow:AddCheckbox(settings, "combatOnly", "Combat only", "Only play heartbeat sounds during active combat.", function()
            EvaluateHealthState()
        end)

        optionsWindow:AddCheckbox(settings, "alwaysInCombat", "Keep steady heartbeat in combat", "Play steady pulse throughout combat even if health is full.", function()
            EvaluateHealthState()
        end)

        optionsWindow:AddCheckbox(settings, "useLowHealthFrame", "Link with Blizzard low health effect", "Activates fast pulse if Blizzard's red low health screen effect appears.", function()
            EvaluateHealthState()
        end)

        optionsWindow:AddCheckbox(settings, "playDeathSound", "Play cardiac arrest (flatline) on death", "Plays cardiac arrest flatline sound when your character dies.")

        optionsWindow:AddSlider(settings, "criticalThreshold", "Fast pulse threshold", 15, 50, 1, "%s: %d%% HP", function()
            EvaluateHealthState()
        end)

        optionsWindow:AddSlider(settings, "warningThreshold", "Normal pulse threshold", 30, 85, 1, "%s: %d%% HP", function()
            EvaluateHealthState()
        end)

        optionsWindow:AddSlider(settings, "volumeMultiplier", "Volume boost", 1, 4, 1, "%s: %dx")

        optionsWindow:AddChoice(settings, "soundLevel", "Sound volume level", {
            { value = "normal", text = L["Normal (0 dB)"] },
            { value = "lower",  text = L["Lower (-5 dB)"] },
            { value = "lowest", text = L["Lowest (-10 dB)"] },
        })

        -- Live Test Buttons
        local testLabel = optionsWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        testLabel:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 6)
        testLabel:SetText(L["Test sounds:"])

        local function StyleBtn(b)
            if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
                OxedHub.UI:ApplyRedButtonStyle(b)
            end
        end

        local btnTestNormal = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnTestNormal:SetSize(75, 22)
        btnTestNormal:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 115, optionsWindow.cursorY - 2)
        btnTestNormal:SetText(L["Normal"])
        StyleBtn(btnTestNormal)
        btnTestNormal:SetScript("OnClick", function()
            testModeState = "NORMAL"
            TransitionTo("NORMAL", true)
        end)

        local btnTestFast = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnTestFast:SetSize(80, 22)
        btnTestFast:SetPoint("LEFT", btnTestNormal, "RIGHT", 4, 0)
        btnTestFast:SetText(L["35% Pulse"])
        StyleBtn(btnTestFast)
        btnTestFast:SetScript("OnClick", function()
            testModeState = "FAST"
            TransitionTo("FAST", true)
        end)

        local btnTestDead = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnTestDead:SetSize(70, 22)
        btnTestDead:SetPoint("LEFT", btnTestFast, "RIGHT", 4, 0)
        btnTestDead:SetText(L["Death"])
        StyleBtn(btnTestDead)
        btnTestDead:SetScript("OnClick", function()
            testModeState = "DEAD"
            TransitionTo("DEAD", true)
        end)

        local btnStopTest = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnStopTest:SetSize(60, 22)
        btnStopTest:SetPoint("LEFT", btnTestDead, "RIGHT", 4, 0)
        btnStopTest:SetText(L["Stop"])
        StyleBtn(btnStopTest)
        btnStopTest:SetScript("OnClick", function()
            testModeState = nil
            StopCurrentSounds()
            EvaluateHealthState()
        end)

        optionsWindow:HookScript("OnHide", function()
            if testModeState then
                testModeState = nil
                StopCurrentSounds()
                EvaluateHealthState()
            end
        end)
    end

    optionsWindow:Show()
end

-- ── Slash Commands ──────────────────────────────────────────────────────────

SLASH_OXEDHUBHEARTBEAT1 = "/heartbeat"
SLASH_OXEDHUBHEARTBEAT2 = "/hb"
SlashCmdList.OXEDHUBHEARTBEAT = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "test" then
        testModeState = (testModeState == nil) and "FAST" or nil
        if testModeState then
            TransitionTo("FAST", true)
            print(L["|cffff4040Heartbeat:|r Test Mode |cff00ff00ON|r (35% Pulse)"])
        else
            testModeState = nil
            StopCurrentSounds()
            EvaluateHealthState()
            print(L["|cffff4040Heartbeat:|r Test Mode |cffff4040OFF|r"])
        end
    elseif msg == "toggle" or msg == "on" or msg == "off" then
        local on = (msg == "on") or (msg == "toggle" and not (settings and settings.enabled))
        if settings then settings.enabled = on end
        if on then StartModule() else StopModule() end
        print(L["|cffff4040Heartbeat:|r "] .. (on and L["|cff00ff00Enabled|r"] or L["|cffff4040Disabled|r"]))
    elseif msg == "status" then
        print(L["|cffff4040Heartbeat Status:|r"])
        print(L["  Enabled: "] .. tostring(settings and settings.enabled))
        print(L["  State: "] .. tostring(currentState))
        print(L["  Critical: "] .. tostring(settings and settings.criticalThreshold) .. "%")
        print(L["  Warning: "] .. tostring(settings and settings.warningThreshold) .. "%")
        print(L["  Player HP: "] .. string.format("%.1f%%", GetPlayerHealthPercent()))
    else
        ShowOptions()
    end
end

-- ── Module Registration ─────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then StartModule() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "heartbeat",
        name     = "Heartbeat",
        version  = "2.0.0",
        updated  = 20261013.5,
        author   = "Oxed",
        category = "combat",
        keywords = { "heartbeat", "pulse", "lowhp", "health", "sound", "tension", "audio", "blood" },
        desc     = "Dynamic heartbeat sound effects: steady pulse in combat, fast danger pulse at 35% HP, and death flatline.",
        icon     = "Interface\\Icons\\Spell_Shadow_BloodBoil",

        defaults = DEFAULTS,

        OnOptionsShow = function()
            ShowOptions()
        end,

        OnEnable = function(_, config)
            settings = config
            StartModule()
        end,

        OnDisable = function()
            StopModule()
        end,
    })
end)
