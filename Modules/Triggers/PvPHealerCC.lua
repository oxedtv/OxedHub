-- ─────────────────────────────────────────────────────────────────────────────
-- PvPHealerCC.lua — PvP trigger: Healer CC Alert
--
-- Detects when a friendly healer in your party/raid is hit by crowd control.
-- Plays a single shared alert sound (e.g. "HealerCcAlert.ogg") when this happens.
--
-- Detection mechanism:
--   Uses the 12.1+ C_UnitAuras.AddAuraSound() API. Registers a single alert
--   sound for a massive list of CC spell IDs (~1030) on all healer unit tokens
--   in the group.
--
-- Spell database: OxedHub.PvPSpellDB.CcSpellIds
-- ─────────────────────────────────────────────────────────────────────────────
local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local L = OxedHub.L

-- ── Local references ────────────────────────────────────────────────────────
local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local UnitGUID = UnitGUID
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local wipe = wipe
local pairs = pairs
local ipairs = ipairs

-- ── State ───────────────────────────────────────────────────────────────────
-- Map of unitToken → { list of AddAuraSound handle IDs }
local handlesByToken = {}

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

--- Register a single AddAuraSound entry.
---@param unitToken string
---@param spellID number
---@param soundFile string
---@param channel string
---@return number|nil
local function AddOne(unitToken, spellID, soundFile, channel)
    local trigger = Enum.UnitAuraSoundTrigger.Added
    local info = {
        unitToken = unitToken,
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

--- Remove all handles for a specific unit token.
---@param unitToken string
local function UnregisterToken(unitToken)
    local handles = handlesByToken[unitToken]
    if not handles then return end
    for i = #handles, 1, -1 do
        RemoveOne(handles[i])
        handles[i] = nil
    end
    handlesByToken[unitToken] = nil
end

--- Remove ALL handles across all tokens.
local function UnregisterAll()
    for token in pairs(handlesByToken) do
        UnregisterToken(token)
    end
    currentSignature = nil
end

--- Check if a unit is a healer (and not the player, usually, but we can include player if they are a healer).
--- We generally skip pets/minions.
---@param unitToken string
---@return boolean
local function IsHealer(unitToken)
    if not unitToken or not UnitExists(unitToken) then return false end
    -- Skip pets
    if unitToken:match("pet") then return false end
    -- Check role
    local role = UnitGroupRolesAssigned(unitToken)
    return role == "HEALER"
end

--- Get all friendly healer tokens to watch.
---@return table<string, boolean>
local function GetHealerTokens()
    local want = {}
    if not IsInGroup() then return want end
    
    local isRaid = IsInRaid()
    local prefix = isRaid and "raid" or "party"
    local count = GetNumGroupMembers()
    
    for i = 1, count do
        local token = prefix .. i
        if IsHealer(token) then
            want[token] = true
        end
    end
    
    -- In party, "player" is not partyN, so check player explicitly.
    if not isRaid and IsHealer("player") then
        want["player"] = true
    end
    
    return want
end

--- Register all CC spell IDs on a healer token.
---@param unitToken string
---@param spellDB table<number, boolean>
---@param configuredSounds table<number, string>
---@param channel string
---@param disabledSpells table<string, boolean>
local function RegisterToken(unitToken, spellDB, configuredSounds, channel, disabledSpells)
    if handlesByToken[unitToken] then return end
    
    local handles = {}
    for spellID, val in pairs(spellDB) do
        if val and not disabledSpells[tostring(spellID)] then
            for _, soundPath in ipairs(configuredSounds) do
                local handle = AddOne(unitToken, spellID, soundPath, channel)
                if handle then
                    handles[#handles + 1] = handle
                end
            end
        end
    end
    handlesByToken[unitToken] = handles
end

-- ── Refresh logic ───────────────────────────────────────────────────────────

local function GetChannel()
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        return OxedHub.db.profile.settings.soundChannel or "Master"
    end
    return "Master"
end

local function GetConfiguredSounds()
    local sounds = {}
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return sounds end
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.enabled and trigger.event == "PVP_HEALER_CC" then
            local soundVal = trigger.actions and trigger.actions.sound
            local filePath = OxedHub.Sounds and OxedHub.Sounds.GetFilePath and OxedHub.Sounds:GetFilePath(soundVal)
            if filePath then
                sounds[#sounds + 1] = filePath
            end
        end
    end
    return sounds
end

local function Refresh(reason)
    if not IsAddAuraSoundAvailable() then return end

    local configuredSounds = GetConfiguredSounds()
    if #configuredSounds == 0 then
        UnregisterAll()
        return
    end

    local channel = GetChannel()
    local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.CcSpellIds
    
    if not spellDB or not next(spellDB) then
        UnregisterAll()
        return
    end

    local inGroup = IsInGroup() and true or false
    local inRaid = IsInRaid() and true or false
    
    local activeTrigger
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
        for _, trigger in pairs(OxedHub.db.profile.triggers) do
            if trigger.enabled and trigger.event == "PVP_HEALER_CC" then
                activeTrigger = trigger
                break
            end
        end
    end
    local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledHealerCC) or {}

    local sigDisabled = ""
    for k, v in pairs(disabledSpells) do if v then sigDisabled = sigDisabled .. k .. "," end end
    
    local sig = table.concat(configuredSounds, ";") .. "|" .. tostring(channel) .. "|" .. tostring(inGroup) .. "|" .. tostring(inRaid) .. "|" .. sigDisabled
    
    if sig ~= currentSignature then
        UnregisterAll()
        currentSignature = sig
    end

    local wantTokens = GetHealerTokens()

    for token in pairs(handlesByToken) do
        if not wantTokens[token] or not UnitExists(token) then
            UnregisterToken(token)
        end
    end

    for token in pairs(wantTokens) do
        RegisterToken(token, spellDB, configuredSounds, channel, disabledSpells)
    end
end

-- ── Event frame ─────────────────────────────────────────────────────────────

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end)

eventFrame:SetScript("OnEvent", function(_, event)
    Refresh(event)
end)

-- ── Trigger registration ────────────────────────────────────────────────────

Triggers:RegisterEventType("PVP_HEALER_CC", {
    name = L["EVT_PVP_HEALER_CC"] or "Healer CC Alert",

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
            "Plays an alert sound when a friendly healer in your party/raid is crowd "
            .. "controlled. Uses the 12.1 AddAuraSound API to reliably track CC "
            .. "auras across all healers in the group automatically.\n\n"
            .. "Note: Icons and Animations are NOT supported for this trigger "
            .. "due to Blizzard PvP restrictions. Only Sounds will play."
        )
        yOffset = yOffset - 40
        
        if OxedHub.UIComponents and OxedHub.UIComponents.PvPSpellPicker then
            yOffset = OxedHub.UIComponents.PvPSpellPicker:Create(frame, trigger, yOffset + 40, OxedHub.PvPSpellDB.CcSpellIds, "disabledHealerCC")
        end

        return yOffset
    end,

    RefreshNativeEffects = function()
        Refresh("RefreshNativeEffects")
    end,
})
