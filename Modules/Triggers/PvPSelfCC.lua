-- ─────────────────────────────────────────────────────────────────────────────
-- PvPSelfCC.lua — PvP trigger: Self CC Detection
--
-- Detects when YOU (the player) get hit by crowd control (stuns, fears,
-- polymorphs, silences, roots, etc.) and plays a voice clip announcing
-- the specific CC type.
--
-- Detection mechanism:
--   Uses the 12.1+ C_UnitAuras.AddAuraSound() API to register sound alerts
--   on the "player" unit token for each known CC spell ID. The WoW engine
--   itself detects aura gains and plays the sound — no polling, works in
--   combat, zero taint.
--
-- Spell database: OxedHub.PvPSpellDB.SelfCcSounds
-- ─────────────────────────────────────────────────────────────────────────────
local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local L = OxedHub.L

-- ── Local references ────────────────────────────────────────────────────────
local C_UnitAuras = C_UnitAuras
local wipe = wipe
local pairs = pairs

-- ── State ───────────────────────────────────────────────────────────────────
-- List of AddAuraSound handle IDs currently registered on the player.
local activeHandles = {}

-- Signature string to detect when a full re-registration is needed.
local currentSignature = nil

-- ── Helpers ─────────────────────────────────────────────────────────────────

--- Check if the 12.1 AddAuraSound API is available.
---@return boolean
local function IsAddAuraSoundAvailable()
    return C_UnitAuras ~= nil
        and C_UnitAuras.AddAuraSound ~= nil
        and Enum ~= nil
        and Enum.UnitAuraSoundTrigger ~= nil
        and Enum.UnitAuraSoundTrigger.Added ~= nil
end

--- Register a single AddAuraSound entry on the player.
---@param spellID number
---@param soundFile string  Full path to the .ogg file
---@param channel string    Audio channel
---@return number|nil
local function AddOne(spellID, soundFile, channel)
    local trigger = Enum.UnitAuraSoundTrigger.Added
    local info = {
        unitToken = "player",
        spellID = spellID,
        soundFileName = soundFile,
        outputChannel = channel or "Master",
    }
    local handle = C_UnitAuras.AddAuraSound(trigger, info)
    if handle then return handle end
    return nil
end

--- Remove a single AddAuraSound registration.
---@param handle number
local function RemoveOne(handle)
    if handle and C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        C_UnitAuras.RemoveAuraSound(handle)
    end
end

--- Remove all current registrations.
local function UnregisterAll()
    for i = #activeHandles, 1, -1 do
        RemoveOne(activeHandles[i])
        activeHandles[i] = nil
    end
    currentSignature = nil
end

--- Get the audio channel from user settings.
---@return string
local function GetChannel()
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        return OxedHub.db.profile.settings.soundChannel or "Master"
    end
    return "Master"
end

--- Get all sound file paths configured by active PVP_SELF_CC triggers.
---@return table<number, string>
local function GetConfiguredSounds()
    local sounds = {}
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return sounds end
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.enabled and trigger.event == "PVP_SELF_CC" then
            local soundVal = trigger.actions and trigger.actions.sound
            local filePath = OxedHub.Sounds and OxedHub.Sounds.GetFilePath and OxedHub.Sounds:GetFilePath(soundVal)
            if filePath then
                sounds[#sounds + 1] = filePath
            end
        end
    end
    return sounds
end

--- Full refresh: re-register all CC spell IDs on the player token.
--- Called on zone change, profile load, trigger enable/disable, etc.
local function Refresh(reason)
    if not IsAddAuraSoundAvailable() then return end

    local configuredSounds = GetConfiguredSounds()
    if #configuredSounds == 0 then
        UnregisterAll()
        return
    end

    local channel = GetChannel()
    local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.SelfCcSounds
    if not spellDB or not next(spellDB) then
        UnregisterAll()
        return
    end

    local activeTrigger
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
        for _, trigger in pairs(OxedHub.db.profile.triggers) do
            if trigger.enabled and trigger.event == "PVP_SELF_CC" then
                activeTrigger = trigger
                break
            end
        end
    end
    local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledSelfCC) or {}

    local sigDisabled = ""
    for k, v in pairs(disabledSpells) do if v then sigDisabled = sigDisabled .. k .. "," end end

    -- Build a signature to detect config changes that require full re-registration.
    local sig = table.concat(configuredSounds, ";") .. "|" .. tostring(channel) .. "|" .. sigDisabled
    if sig == currentSignature then
        return  -- nothing changed, keep existing registrations
    end

    -- Full teardown + rebuild.
    UnregisterAll()
    currentSignature = sig

    -- Register AddAuraSound for every CC spell on the player.
    for spellID, val in pairs(spellDB) do
        if val and not disabledSpells[tostring(spellID)] then
            for _, soundPath in ipairs(configuredSounds) do
                local handle = AddOne(spellID, soundPath, channel)
                if handle then
                    activeHandles[#activeHandles + 1] = handle
                end
            end
        end
    end
end


-- ── Event frame ─────────────────────────────────────────────────────────────
-- Minimal event frame — Self CC only needs to refresh on zone/profile changes
-- since the player token never changes.

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end)

eventFrame:SetScript("OnEvent", function(_, event)
    Refresh(event)
end)


-- ── Trigger registration ────────────────────────────────────────────────────

Triggers:RegisterEventType("PVP_SELF_CC", {
    name = L["EVT_PVP_SELF_CC"] or "Self CC Alert",

    CheckCondition = function(trigger, eventData)
        return true
    end,

    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}

        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        info:SetText("|cff00ff00Native Engine|r")
        info:SetTextColor(1, 0.82, 0, 1)
        yOffset = yOffset - 20

        local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        desc:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 2)
        desc:SetWidth(450)
        desc:SetJustifyH("LEFT")
        desc:SetText(
            "Plays a voice alert when you get CC'd (stunned, feared, polymorphed, "
            .. "silenced, etc.). Uses the 12.1 AddAuraSound API for instant, "
            .. "in-combat detection.\n\n"
            .. "Note: Icons and Animations are NOT supported for this trigger "
            .. "due to Blizzard PvP restrictions. Only Sounds will play."
        )
        yOffset = yOffset - 40
        
        if OxedHub.UIComponents and OxedHub.UIComponents.PvPSpellPicker then
            yOffset = OxedHub.UIComponents.PvPSpellPicker:Create(frame, trigger, yOffset + 40, OxedHub.PvPSpellDB.SelfCcSounds, "disabledSelfCC")
        end

        return yOffset
    end,

    RefreshNativeEffects = function()
        Refresh("RefreshNativeEffects")
    end,
})
