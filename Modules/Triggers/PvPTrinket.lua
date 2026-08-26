-- ─────────────────────────────────────────────────────────────────────────────
-- PvPTrinket.lua — PvP trigger: Enemy Trinket Detection
--
-- Detects when your TARGET, FOCUS, or ARENA enemy uses their PvP trinket
-- (Gladiator's Medallion or Adaptation).
--
-- Detection mechanism:
--   Uses the 12.1+ C_UnitAuras.AddAuraSound() API.
--
-- Spell database: OxedHub.PvPSpellDB.TrinketSpellIds
-- ─────────────────────────────────────────────────────────────────────────────
local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local L = OxedHub.L

local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local UnitIsEnemy = UnitIsEnemy
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = UnitGUID
local IsInInstance = IsInInstance
local C_NamePlate = C_NamePlate

local handlesByToken = {}
local currentSignature = nil

local function IsAddAuraSoundAvailable()
    return C_UnitAuras ~= nil and C_UnitAuras.AddAuraSound ~= nil and Enum and Enum.UnitAuraSoundTrigger
end

local function AddOne(unitToken, spellID, soundFile, channel)
    local info = { unitToken = unitToken, spellID = spellID, soundFileName = soundFile, outputChannel = channel or "Master" }
    local ok, handle = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added, info)
    return (ok and handle) and handle or nil
end

local function RemoveOne(handle)
    if handle and C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        pcall(C_UnitAuras.RemoveAuraSound, handle)
    end
end

local function UnregisterToken(unitToken)
    local handles = handlesByToken[unitToken]
    if not handles then return end
    for i = #handles, 1, -1 do RemoveOne(handles[i]); handles[i] = nil end
    handlesByToken[unitToken] = nil
end

local function UnregisterAll()
    for token in pairs(handlesByToken) do UnregisterToken(token) end
    currentSignature = nil
end

local function IsEnemyPlayer(unitToken)
    if not unitToken then return false end
    local exists = UnitExists(unitToken)
    if issecretvalue(exists) or not exists then return false end
    local isEnemy = UnitIsEnemy("player", unitToken)
    if issecretvalue(isEnemy) or not isEnemy then return false end
    local isPlayer = UnitIsPlayer(unitToken)
    return (not issecretvalue(isPlayer) and isPlayer) and true or false
end

local function GetEnemyWatchTokens()
    local want, seenGUID = {}, {}
    local function TryAdd(token)
        if not IsEnemyPlayer(token) then return end
        local guid = UnitGUID(token)
        if guid and not issecretvalue(guid) then
            if seenGUID[guid] then return end
            seenGUID[guid] = true
        end
        want[token] = true
    end

    TryAdd("target")
    TryAdd("focus")

    local _, instanceType = IsInInstance()
    if instanceType == "arena" then
        TryAdd("arena1"); TryAdd("arena2"); TryAdd("arena3")
    elseif C_NamePlate then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do if plate.unitToken then TryAdd(plate.unitToken) end end
        end
    end
    return want
end

local function RegisterToken(unitToken, spellDB, configuredSounds, channel, disabledSpells)
    if handlesByToken[unitToken] or not IsEnemyPlayer(unitToken) then return end
    local handles = {}
    for spellID, val in pairs(spellDB) do
        if val and not disabledSpells[tostring(spellID)] then
            for _, soundPath in ipairs(configuredSounds) do
                local handle = AddOne(unitToken, spellID, soundPath, channel)
                if handle then handles[#handles + 1] = handle end
            end
        end
    end
    handlesByToken[unitToken] = handles
end

local function GetChannel()
    return (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.soundChannel) or "Master"
end

local function GetConfiguredSounds()
    local sounds = {}
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return sounds end
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.enabled and trigger.event == "PVP_TRINKET" then
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
    if #configuredSounds == 0 then return UnregisterAll() end

    local channel = GetChannel()
    local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.TrinketSpellIds
    if not spellDB or not next(spellDB) then return UnregisterAll() end

    local activeTrigger
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
        for _, trigger in pairs(OxedHub.db.profile.triggers) do
            if trigger.enabled and trigger.event == "PVP_TRINKET" then
                activeTrigger = trigger
                break
            end
        end
    end
    local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledTrinkets) or {}

    local sigDisabled = ""
    for k, v in pairs(disabledSpells) do if v then sigDisabled = sigDisabled .. k .. "," end end

    local sig = table.concat(configuredSounds, ";") .. "|" .. tostring(channel) .. "|" .. sigDisabled
    if sig ~= currentSignature then UnregisterAll(); currentSignature = sig end

    local wantTokens = GetEnemyWatchTokens()
    for token in pairs(handlesByToken) do
        if not wantTokens[token] or not IsEnemyPlayer(token) then UnregisterToken(token) end
    end
    for token in pairs(wantTokens) do RegisterToken(token, spellDB, configuredSounds, channel, disabledSpells) end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED")
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
end)

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local configuredSounds = GetConfiguredSounds()
        if #configuredSounds == 0 or not IsEnemyPlayer(arg1) or handlesByToken[arg1] then return end
        local guid = UnitGUID(arg1)
        if guid and not issecretvalue(guid) then
            for token in pairs(handlesByToken) do
                local g = UnitGUID(token)
                if g and not issecretvalue(g) and g == guid then return end
            end
        end
        local spellDB = OxedHub.PvPSpellDB and OxedHub.PvPSpellDB.TrinketSpellIds
        if spellDB then 
            local activeTrigger
            if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
                for _, trigger in pairs(OxedHub.db.profile.triggers) do
                    if trigger.enabled and trigger.event == "PVP_TRINKET" then
                        activeTrigger = trigger
                        break
                    end
                end
            end
            local disabledSpells = (activeTrigger and activeTrigger.conditions and activeTrigger.conditions.disabledTrinkets) or {}
            RegisterToken(arg1, spellDB, configuredSounds, GetChannel(), disabledSpells) 
        end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        UnregisterToken(arg1)
    else
        Refresh(event)
    end
end)

Triggers:RegisterEventType("PVP_TRINKET", {
    name = L["EVT_PVP_TRINKET"] or "Enemy Trinket Alert",
    CheckCondition = function() return true end,
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
            "Plays a voice alert when your target, focus, or arena enemy uses their PvP trinket (Gladiator's Medallion or Adaptation).\n\n"
            .. "Note: Icons and Animations are NOT supported for this trigger "
            .. "due to Blizzard PvP restrictions. Only Sounds will play."
        )
        yOffset = yOffset - 40
        
        if OxedHub.UIComponents and OxedHub.UIComponents.PvPSpellPicker then
            yOffset = OxedHub.UIComponents.PvPSpellPicker:Create(frame, trigger, yOffset + 40, OxedHub.PvPSpellDB.TrinketSpellIds, "disabledTrinkets")
        end
        return yOffset
    end,
    RefreshNativeEffects = function() Refresh("RefreshNativeEffects") end,
})
