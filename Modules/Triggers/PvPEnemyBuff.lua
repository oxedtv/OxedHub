-- ─────────────────────────────────────────────────────────────────────────────
-- PvPEnemyBuff.lua — PvP trigger: Enemy Buff Detection
--
-- Detects when your TARGET, FOCUS, or ARENA enemy gains an important buff
-- (defensive cooldowns, offensive cooldowns, utility abilities).
--
-- Detection mechanism:
--   Uses the 12.1+ C_UnitAuras.AddAuraSound() API to register sound alerts
--   on enemy unit tokens. The WoW engine itself detects aura gains and plays
--   the configured sound — no CLEU, no polling, no taint, works in combat.
--
-- When the trigger is enabled, AddAuraSound handles are registered on each
-- enemy token. When a tracked aura appears, the engine plays the voice clip.
-- Re-registration happens automatically when you change target/focus or when
-- a nameplate appears/disappears.
--
-- Spell database: OxedHub.PvPSpellDB.EnemyBuffSounds
-- ─────────────────────────────────────────────────────────────────────────────
local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local L = OxedHub.L

-- ── Local references ────────────────────────────────────────────────────────
local C_UnitAuras = C_UnitAuras
local UnitGUID = UnitGUID
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitIsPlayer = UnitIsPlayer
local IsInInstance = IsInInstance
local C_NamePlate = C_NamePlate
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local issecretvalue = issecretvalue

-- ── State ───────────────────────────────────────────────────────────────────
-- Map of unitToken → { list of AddAuraSound handle IDs }
-- Each token gets its own set of registrations; when the token is no longer
-- valid (target changed, nameplate removed) we remove its handles.
local handlesByToken = {}

-- Signature string to detect when a full re-registration is needed
-- (e.g. profile change, zone change, trigger enable/disable).
local currentSignature = nil

-- ── Helpers: AddAuraSound wrappers ──────────────────────────────────────────

--- Check if the 12.1 AddAuraSound API is available.
---@return boolean
local function IsAddAuraSoundAvailable()
    return C_UnitAuras ~= nil
        and C_UnitAuras.AddAuraSound ~= nil
        and Enum ~= nil
        and Enum.UnitAuraSoundTrigger ~= nil
        and Enum.UnitAuraSoundTrigger.Added ~= nil
end

--- Register a single AddAuraSound entry.
---@param unitToken string  The unit to watch (e.g. "target", "focus", "arena1")
---@param spellID number    The aura spell ID to watch for
---@param soundFile string  Full path to the .ogg file to play
---@param channel string    Audio channel ("Master", "SFX", etc.)
---@return number|nil       The handle ID, or nil on failure
local function AddOneAuraSound(unitToken, spellID, soundFile, channel)
    local trigger = Enum.UnitAuraSoundTrigger.Added
    local info = {
        unitToken = unitToken,
        spellID = spellID,
        soundFileName = soundFile,
        outputChannel = channel or "Master",
    }
    local handle = C_UnitAuras.AddAuraSound(trigger, info)
    if handle then
        return handle
    end
    return nil
end

--- Remove a single AddAuraSound registration by handle.
---@param handle number
local function RemoveOneAuraSound(handle)
    if handle and C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        C_UnitAuras.RemoveAuraSound(handle)
    end
end

-- ── Token management ────────────────────────────────────────────────────────

--- Remove all AddAuraSound handles for a specific unit token.
---@param unitToken string
local function UnregisterToken(unitToken)
    local handles = handlesByToken[unitToken]
    if not handles then return end
    for i = #handles, 1, -1 do
        RemoveOneAuraSound(handles[i])
        handles[i] = nil
    end
    handlesByToken[unitToken] = nil
end

--- Remove ALL handles across all tokens (full teardown).
local function UnregisterAll()
    for token in pairs(handlesByToken) do
        UnregisterToken(token)
    end
    currentSignature = nil
end

--- Check if a unit token is a valid hostile player we should watch.
---@param unitToken string
---@return boolean
local function IsEnemyPlayer(unitToken)
    if not unitToken then return false end
    local exists = UnitExists(unitToken)
    -- In instanced PvP, UnitExists returns a "secret value" for arena frames
    -- before they're revealed. Treat those as non-existent.
    if issecretvalue(exists) or not exists then return false end
    local isEnemy = UnitIsEnemy("player", unitToken)
    if issecretvalue(isEnemy) then return false end
    if not isEnemy then return false end
    local isPlayer = UnitIsPlayer(unitToken)
    if issecretvalue(isPlayer) then return false end
    return isPlayer and true or false
end

--- Get all enemy unit tokens we should currently watch.
--- Returns a list of tokens and a GUID-dedup set to avoid double-registering
--- the same enemy seen as both target and nameplate.
---@return table<string, boolean>  wantTokens: set of tokens to register
local function GetEnemyWatchTokens()
    local want = {}
    local seenGUID = {}

    -- Helper: add a token if the GUID hasn't been seen yet.
    local function TryAdd(token)
        if not IsEnemyPlayer(token) then return end
        local guid = UnitGUID(token)
        if guid and not issecretvalue(guid) then
            if seenGUID[guid] then return end
            seenGUID[guid] = true
        end
        want[token] = true
    end

    -- Always watch target and focus (highest priority).
    TryAdd("target")
    TryAdd("focus")

    -- In arenas, also watch arena unit frames.
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        TryAdd("arena1")
        TryAdd("arena2")
        TryAdd("arena3")
    end

    -- Outside arenas, also watch enemy nameplates (if visible).
    if instanceType ~= "arena" and C_NamePlate then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                local token = plate.unitToken
                if token then TryAdd(token) end
            end
        end
    end

    return want
end

--- Register AddAuraSound on a single unit token for all tracked enemy buffs.
---@param unitToken string
---@param spellDB table<number, boolean>
---@param configuredSounds table<number, string>
---@param channel string
---@param disabledSpells table<string, boolean>
local function RegisterToken(unitToken, spellDB, configuredSounds, channel, disabledSpells)
    if handlesByToken[unitToken] then return end  -- already registered
    if not IsEnemyPlayer(unitToken) then return end

    local handles = {}
    for spellID, val in pairs(spellDB) do
        if val and not disabledSpells[tostring(spellID)] then
            for _, soundPath in ipairs(configuredSounds) do
                local handle = AddOneAuraSound(unitToken, spellID, soundPath, channel)
                if handle then
                    handles[#handles + 1] = handle
                end
            end
        end
    end
    handlesByToken[unitToken] = handles
end


-- ── Refresh logic ───────────────────────────────────────────────────────────

--- Get the audio channel from user settings, defaulting to "Master".
---@return string
local function GetChannel()
    -- Use the addon's global volume channel setting if available.
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        return OxedHub.db.profile.settings.soundChannel or "Master"
    end
    return "Master"
end

--- Get all sound file paths configured by active PVP_ENEMY_BUFF triggers.
---@return table<number, string>
local function GetConfiguredSounds()
    local sounds = {}
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return sounds end
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.enabled and trigger.event == "PVP_ENEMY_BUFF" then
            local soundVal = trigger.actions and trigger.actions.sound
            local filePath = OxedHub.Sounds and OxedHub.Sounds.GetFilePath and OxedHub.Sounds:GetFilePath(soundVal)
            if filePath then
                sounds[#sounds + 1] = filePath
            end
        end
    end
    return sounds
end

--- Full refresh: re-evaluate which tokens need registrations.
--- Called on target/focus change, zone change, nameplate add/remove, etc.
local function Refresh(reason)
    if not IsAddAuraSoundAvailable() then return end

    local configuredSounds = GetConfiguredSounds()
    if #configuredSounds == 0 then
        UnregisterAll()
        return
    end

    local channel = GetChannel()
    local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.EnemyBuffSounds
    if not spellDB or not next(spellDB) then
        UnregisterAll()
        return
    end

    -- We need to rebuild when sound, channel, OR spell toggles change.
    -- The disabledSpells table is passed dynamically from the active trigger.
    -- Wait, if there are multiple active PVP_ENEMY_BUFF triggers, which disabledSpells do we use?
    -- If there are multiple, they might conflict if they track different spells.
    -- For simplicity, we merge all disabled spells (if disabled in ALL triggers, it's disabled. If enabled in ANY trigger, it's enabled).
    -- Or better, we just use the first enabled trigger's settings since multiple triggers of the same event type are rare.
    local activeTrigger
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
        for _, trigger in pairs(OxedHub.db.profile.triggers) do
            if trigger.enabled and trigger.event == "PVP_ENEMY_BUFF" then
                activeTrigger = trigger
                break
            end
        end
    end
    local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledEnemyBuffs) or {}

    local sigDisabled = ""
    for k, v in pairs(disabledSpells) do if v then sigDisabled = sigDisabled .. k .. "," end end
    
    -- Build a signature to detect full-refresh scenarios (profile change, sound change, etc.)
    local sig = table.concat(configuredSounds, ";") .. "|" .. tostring(channel) .. "|" .. sigDisabled
    if sig ~= currentSignature then
        -- Full teardown + rebuild when config changes.
        UnregisterAll()
        currentSignature = sig
    end

    -- Determine which tokens we WANT to be watching.
    local wantTokens = GetEnemyWatchTokens()

    -- Remove registrations for tokens we no longer want (or that are stale).
    for token in pairs(handlesByToken) do
        if not wantTokens[token] or not IsEnemyPlayer(token) then
            UnregisterToken(token)
        end
    end

    -- Add registrations for tokens we want but don't have yet.
    for token in pairs(wantTokens) do
        RegisterToken(token, spellDB, configuredSounds, channel, disabledSpells)
    end
end


-- ── Event frame ─────────────────────────────────────────────────────────────
-- This frame listens for target/focus/nameplate changes and refreshes
-- AddAuraSound registrations accordingly. It is completely independent from
-- the main OxedHub event frame (Loader.lua), so it won't interfere with
-- any existing logic.

local eventFrame = CreateFrame("Frame")

-- Defer event registration to the first frame to avoid ADDON_ACTION_FORBIDDEN
-- during load (same pattern as Loader.lua).
eventFrame:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)

    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- Track when arena enemies become visible / hostile / friendly changes.
    if pcall(self.RegisterUnitEvent, self, "UNIT_FACTION", "target", "focus") then end
end)

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- A new nameplate appeared — register it if it's an enemy player.
        local configuredSounds = GetConfiguredSounds()
        if #configuredSounds == 0 then return end
        
        if IsEnemyPlayer(arg1) and not handlesByToken[arg1] then
            -- Check GUID dedup against existing registrations.
            local guid = UnitGUID(arg1)
            if guid and not issecretvalue(guid) then
                for token in pairs(handlesByToken) do
                    local g = UnitGUID(token)
                    if g and not issecretvalue(g) and g == guid then
                        return  -- already watching this enemy on another token
                    end
                end
            end
            local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.EnemyBuffSounds
            if #configuredSounds > 0 and spellDB then
                local activeTrigger
                if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
                    for _, trigger in pairs(OxedHub.db.profile.triggers) do
                        if trigger.enabled and trigger.event == "PVP_ENEMY_BUFF" then
                            activeTrigger = trigger
                            break
                        end
                    end
                end
                local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledEnemyBuffs) or {}
                RegisterToken(arg1, spellDB, configuredSounds, GetChannel(), disabledSpells)
            end
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        -- Nameplate gone — remove its registrations.
        if arg1 and handlesByToken[arg1] then
            UnregisterToken(arg1)
        end
    else
        -- For all other events (target change, focus change, zone change, etc.)
        -- do a full refresh to re-evaluate all tokens.
        Refresh(event)
    end
end)


-- ── Trigger registration ────────────────────────────────────────────────────
-- Register this event type so it appears in the PvP Triggers dropdown.
-- CheckCondition always returns true — filtering is done at the AddAuraSound
-- registration level (only tracked spell IDs are registered).

Triggers:RegisterEventType("PVP_ENEMY_BUFF", {
    -- Display name shown in the event type picker.
    name = L["EVT_PVP_ENEMY_BUFF"] or "Enemy Buff Alert",

    -- Condition check: always true because AddAuraSound handles filtering.
    CheckCondition = function(trigger, eventData)
        return true
    end,

    -- Condition UI: shows an info label explaining the trigger.
    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}

        -- Info text explaining how this trigger works.
        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        info:SetText("|cff00ff00Native Engine|r")
        info:SetTextColor(1, 0.82, 0, 1)
        yOffset = yOffset - 20

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 2)
        desc:SetWidth(420)
        desc:SetJustifyH("LEFT")
        desc:SetText(
            "Automatically announces enemy buffs (defensives, offensives, utility) "
            .. "using the 12.1 AddAuraSound API. Tracks your target, focus, and arena "
            .. "enemies. The sound you pick in the 'Actions' tab below will play "
            .. "instantly when an enemy gains a tracked buff.\n\n"
            .. "Note: Icons and Animations are NOT supported for this trigger "
            .. "due to Blizzard PvP restrictions. Only Sounds will play."
        )
        yOffset = yOffset - 40
        
        if OxedHub.UIComponents and OxedHub.UIComponents.PvPSpellPicker then
            yOffset = OxedHub.UIComponents.PvPSpellPicker:Create(frame, trigger, yOffset + 40, OxedHub.PvPSpellDB.EnemyBuffSounds, "disabledEnemyBuffs")
        end
        
        return yOffset
    end,

    -- Called when the trigger system refreshes native effects (e.g. on profile load).
    RefreshNativeEffects = function()
        Refresh("RefreshNativeEffects")
    end,
})
