local addonName, OxedHub = ...
_G["OxedHub"] = OxedHub

-- Core module - Main entry point and event handling
local Core = {}
OxedHub.Core = Core

-- Local references for performance
local C_Timer = C_Timer
local C_CombatLog = C_CombatLog
local C_PvP = C_PvP
local C_ToyBox = C_ToyBox
local C_UnitAuras = C_UnitAuras
local UnitGUID = UnitGUID
local UnitName = UnitName
local UnitClass = UnitClass
local UnitClassBase = UnitClassBase
local IsInInstance = IsInInstance
local IsInCombatLockdown = InCombatLockdown
local GetTime = GetTime
local PlaySoundFile = PlaySoundFile
local SendChatMessage = SendChatMessage
local DoEmote = DoEmote

-- Event frame is created and events are registered in Loader.lua
-- (which loads before libraries in a pristine, untainted context)
local isLoaded = false
local isPlayerLoginHandled = false
local summonHooksInstalled = false
local MAX_PROFILE_COUNT = 16
local CLASS_PROFILE_NAMES = {
    DEATHKNIGHT = "Death Knight",
    DEMONHUNTER = "Demon Hunter",
    DRUID = "Druid",
    EVOKER = "Evoker",
    HUNTER = "Hunter",
    MAGE = "Mage",
    MONK = "Monk",
    PALADIN = "Paladin",
    PRIEST = "Priest",
    ROGUE = "Rogue",
    SHAMAN = "Shaman",
    WARLOCK = "Warlock",
    WARRIOR = "Warrior",
}
local CLASS_PROFILE_ORDER = {
    "DEATHKNIGHT",
    "DEMONHUNTER",
    "DRUID",
    "EVOKER",
    "HUNTER",
    "MAGE",
    "MONK",
    "PALADIN",
    "PRIEST",
    "ROGUE",
    "SHAMAN",
    "WARLOCK",
    "WARRIOR",
}
local CLASS_ID_TO_TOKEN = {
    [1] = "WARRIOR",
    [2] = "PALADIN",
    [3] = "HUNTER",
    [4] = "ROGUE",
    [5] = "PRIEST",
    [6] = "DEATHKNIGHT",
    [7] = "SHAMAN",
    [8] = "MAGE",
    [9] = "WARLOCK",
    [10] = "MONK",
    [11] = "DRUID",
    [12] = "DEMONHUNTER",
    [13] = "EVOKER",
}

local function TablesDeepEqual(left, right)
    if left == right then
        return true
    end

    if type(left) ~= type(right) then
        return false
    end

    if type(left) ~= "table" then
        return left == right
    end

    for key, value in pairs(left) do
        if not TablesDeepEqual(value, right[key]) then
            return false
        end
    end

    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end

    return true
end

local function EnsureProfileUiStartsDisabled(profile)
    if type(profile) ~= "table" then
        return
    end

    profile.settings = profile.settings or {}
    profile.settings.ringVisible = false

    if type(profile.actionHub) == "table" then
        if type(profile.actionHub.hubs) == "table" then
            for _, hub in ipairs(profile.actionHub.hubs) do
                if type(hub) == "table" then
                    hub.onScreen = false
                end
            end
        else
            profile.actionHub.onScreen = false
        end
    end
end

local function SeedBuiltInProfiles()
    local bundledProfiles = OxedHub.BUILT_IN_PROFILES
    if type(bundledProfiles) ~= "table" then
        return 0
    end

    OxedHubDB.profiles = OxedHubDB.profiles or {}
    local deletedList = OxedHubDB.globalSettings and OxedHubDB.globalSettings.deletedBuiltInProfiles or {}

    local addedCount = 0
    for profileName, profileData in pairs(bundledProfiles) do
        if profileName ~= "Starter Profile" and profileName ~= "Imported Profile"
            and OxedHubDB.profiles[profileName] == nil
            and not deletedList[profileName]
            and type(profileData) == "table" then
            OxedHubDB.profiles[profileName] = CopyTable(profileData)
            EnsureProfileUiStartsDisabled(OxedHubDB.profiles[profileName])
            addedCount = addedCount + 1
        end
    end

    return addedCount
end

local function CleanupAccidentalSeededProfiles()
    if type(OxedHubDB) ~= "table" or type(OxedHubDB.profiles) ~= "table" then
        return
    end

    local bundledProfiles = OxedHub.BUILT_IN_PROFILES
    local accidentalTemplate = type(bundledProfiles) == "table" and (bundledProfiles["Starter Profile"] or bundledProfiles["Imported Profile"]) or nil
    if type(accidentalTemplate) ~= "table" then
        accidentalTemplate = nil
    end

    local replacementProfile = nil
    for name in pairs(OxedHubDB.profiles) do
        if name ~= "Starter Profile" and name ~= "Imported Profile" then
            replacementProfile = name
            break
        end
    end

    local function RemoveIfAccidental(profileName)
        local profileData = OxedHubDB.profiles[profileName]
        if type(profileData) ~= "table" then
            return
        end

        if accidentalTemplate and not TablesDeepEqual(profileData, accidentalTemplate) then
            return
        end

        OxedHubDB.profiles[profileName] = nil

        if OxedHubDB.activeProfile == profileName then
            if replacementProfile and OxedHubDB.profiles[replacementProfile] then
                OxedHubDB.activeProfile = replacementProfile
            else
                OxedHubDB.activeProfile = "Default"
                OxedHubDB.profiles["Default"] = OxedHubDB.profiles["Default"] or {}
            end
        end
    end

    RemoveIfAccidental("Starter Profile")
    RemoveIfAccidental("Imported Profile")
end

local function EnsureGlobalSettings()
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    if OxedHubDB.globalSettings.autoSwitchClassProfile == nil then
        OxedHubDB.globalSettings.autoSwitchClassProfile = true
    end
    OxedHubDB.globalSettings.characterActiveProfiles = OxedHubDB.globalSettings.characterActiveProfiles or {}
end

local function GetOrCreateSharedCustomSounds()
    OxedHubDB.sharedCustomSounds = OxedHubDB.sharedCustomSounds or {}
    return OxedHubDB.sharedCustomSounds
end

local function MergeCustomSoundsIntoShared(sharedSounds, sourceSounds)
    if type(sharedSounds) ~= "table" or type(sourceSounds) ~= "table" then
        return
    end

    for soundId, soundData in pairs(sourceSounds) do
        if type(soundData) == "table" then
            sharedSounds[soundId] = CopyTable(soundData)
        else
            sharedSounds[soundId] = soundData
        end
    end
end

local function NormalizeClassToken(classToken)
    if type(classToken) ~= "string" or classToken == "" then
        return false
    end

    local normalized = string.upper(classToken)
    if CLASS_PROFILE_NAMES[normalized] then
        return normalized
    end

    for token, displayName in pairs(CLASS_PROFILE_NAMES) do
        if classToken == displayName then
            return token
        end
    end

    return false
end

local function GetPlayerClassToken()
    if UnitClassBase then
        local okBase, _, classFileBase = pcall(UnitClassBase, "player")
        local normalizedBase = NormalizeClassToken(classFileBase)
        if okBase and normalizedBase then
            return normalizedBase
        end
    end

    if UnitClass then
        local okClass, _, classFile, classID = pcall(UnitClass, "player")
        if okClass then
            local normalizedClass = NormalizeClassToken(classFile)
            if normalizedClass then
                return normalizedClass
            end

            local mappedById = CLASS_ID_TO_TOKEN[tonumber(classID)]
            if mappedById then
                return mappedById
            end
        end
    end

    return false
end

local function ApplyBuiltInProfileMetadata()
    if type(OxedHubDB) ~= "table" or type(OxedHubDB.profiles) ~= "table" then
        return
    end

    for token, displayName in pairs(CLASS_PROFILE_NAMES) do
        local profile = OxedHubDB.profiles[displayName]
        if type(profile) == "table" then
            profile.metadata = profile.metadata or {}
            if not NormalizeClassToken(profile.metadata.classToken) then
                profile.metadata.classToken = token
            end
        end
    end
end

function OxedHub:GetMaxProfileCount()
    return MAX_PROFILE_COUNT
end

function OxedHub:GetSharedCustomSounds()
    if type(OxedHubDB) ~= "table" then
        return {}
    end

    return GetOrCreateSharedCustomSounds()
end

function OxedHub:SyncSharedCustomSounds(targetProfile)
    if type(OxedHubDB) ~= "table" then
        return {}
    end

    local sharedSounds = GetOrCreateSharedCustomSounds()

    if type(OxedHubDB.profiles) == "table" then
        for _, profile in pairs(OxedHubDB.profiles) do
            if type(profile) == "table" then
                if profile.customSounds ~= sharedSounds then
                    MergeCustomSoundsIntoShared(sharedSounds, profile.customSounds)
                end
                profile.customSounds = sharedSounds
            end
        end
    end

    if type(targetProfile) == "table" then
        if targetProfile.customSounds ~= sharedSounds then
            MergeCustomSoundsIntoShared(sharedSounds, targetProfile.customSounds)
        end
        targetProfile.customSounds = sharedSounds
    end

    if type(OxedHubDB.profile) == "table" then
        OxedHubDB.profile.customSounds = sharedSounds
    end
    if type(self.db) == "table" and type(self.db.profile) == "table" then
        self.db.profile.customSounds = sharedSounds
    end

    return sharedSounds
end

function OxedHub:GetProfileCount()
    local count = 0
    for _ in pairs(OxedHubDB.profiles or {}) do
        count = count + 1
    end
    return count
end

function OxedHub:CanCreateProfileSlot()
    return self:GetProfileCount() < MAX_PROFILE_COUNT
end

local PLACEHOLDER_TRIGGER_IDS = {
    bl_hero = true,
    pi_received = true,
    player_death = true,
    interrupt_success = true,
    crit_hit = true,
    achievement = true,
}
local PLACEHOLDER_SOUND_IDS = {
    death_sound = true,
    interrupt_sound = true,
    crit_sound = true,
    achievement_sound = true,
}
local PLACEHOLDER_ANIMATION_IDS = {
    celebration_anim = true,
}

local previousPetState = nil -- "alive", "dead", or "none"

local function GetPetState()
    if UnitExists("pet") then
        local currentHealth = UnitHealth("pet")
        if (currentHealth and currentHealth == 0) or UnitIsDead("pet") then
            return "dead"
        else
            return "alive"
        end
    else
        if UnitIsDead("pet") then
            return "dead"
        else
            return "none"
        end
    end
end

-- Cooldown tracking
local cooldowns = {
    chat = 0,
    emote = 0,
    sound = 0,
}

-- Pending interrupt tracking (for success/fail detection)
local pendingInterrupt = nil
local interruptSeq = 0
local INTERRUPT_RESULT_TIMEOUT = 0.6

-- Spell-cast deduplication: reticle spells (Death and Decay, etc.) fire
-- UNIT_SPELLCAST_SUCCEEDED twice (on button press + on ground placement).
local recentSpellCasts = {}
local SPELL_CAST_DEDUP_WINDOW = 0.3

-- Combat log cache for meta damage tracking
local damageCache = {}
local META_DAMAGE_WINDOW = 5 -- seconds

-- Pet state tracking
local previousPetState = nil
local function GetPetState()
    if UnitExists("pet") then
        if UnitIsDead("pet") then
            return "dead"
        else
            return "alive"
        end
    else
        return "none"
    end
end

local function GetHelpfulAuraData(unit, index)
    if UnitAura then
        local success, name, _, _, duration, expirationTime, sourceUnit, _, _, spellId = pcall(UnitAura, unit, index, "HELPFUL")
        if not success or not name then
            return nil
        end

        -- Convert name through string to strip taint
        local cleanName = "" .. name

        return {
            name = cleanName,
            duration = duration,
            expirationTime = expirationTime,
            sourceUnit = sourceUnit,
            spellId = spellId,
        }
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local success, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
        if not success or not aura then
            return nil
        end

        -- Safely extract name with pcall to handle taint
        local cleanName = nil
        local successName, name = pcall(function() return aura.name end)
        if successName and name then
            -- Convert through string concatenation to strip taint
            cleanName = "" .. name
        end

        if not cleanName then
            return nil
        end

        -- Safely extract spellId with pcall
        local cleanSpellId = nil
        local successId, spellId = pcall(function() return aura.spellId end)
        if successId and spellId then
            cleanSpellId = tonumber(tostring(spellId))
        end

        return {
            name = cleanName,
            duration = aura.duration,
            expirationTime = aura.expirationTime,
            sourceUnit = aura.sourceUnit,
            spellId = cleanSpellId,
        }
    end

    return nil
end

function Core:HasEnabledTrigger(eventType)
    return OxedHub.Triggers
        and OxedHub.Triggers.HasEnabledTriggerForEvent
        and OxedHub.Triggers:HasEnabledTriggerForEvent(eventType)
end

-- Initialize addon
function Core:Init()
    -- Use C_Timer.After(0) to ensure SavedVariables are available
    C_Timer.After(0, function()
        Core:Bootstrap()
    end)
end

-- Event handler (events are forwarded from Loader.lua's frame)
function Core:OnEvent(event, ...)
    if not isLoaded then
        return
    elseif event == "PLAYER_LOGIN" then
        self:OnPlayerLogin()
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:OnEnteringWorld()
    elseif event == "PLAYER_DEAD" then
        self:OnPlayerDead()
    elseif event == "UNIT_AURA" then
        self:OnUnitAura(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        self:OnSpellCastSucceeded(...)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        self:OnSpellInterrupted(...)
    elseif event == "RESURRECT_REQUEST" then
        self:OnResurrectRequest()
    elseif event == "ENCOUNTER_START" then
        self:OnEncounterStart(...)
    elseif event == "ENCOUNTER_END" then
        self:OnEncounterEnd(...)
    elseif event == "BOSS_KILL" then
        self:OnBossKill(...)
    elseif event == "CONFIRM_SUMMON" then
        self:OnSummonIncoming()
    elseif event == "ACHIEVEMENT_EARNED" then
        self:OnAchievementEarned(...)
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        self:OnSpellCooldownUpdate()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self:OnChallengeModeCompleted()
    elseif event == "PARTY_KILL" then
        self:OnPartyKill(...)
    elseif event == "GROUP_JOINED" or event == "GROUP_LEFT"
        or event == "PARTY_INVITE_REQUEST" or event == "PARTY_LEADER_CHANGED" then
        self:OnGroupEvent(event, ...)
    elseif event == "PLAYER_CONTROL_LOST" then
        self:OnPlayerControlLost()
    elseif event == "PLAYER_CONTROL_GAINED" then
        self:OnPlayerControlGained()
    elseif event == "LOSS_OF_CONTROL_ADDED" or event == "LOSS_OF_CONTROL_UPDATE" then
        self:OnPlayerControlLost(event)
    elseif event == "UNIT_PET" then
        self:OnPetEvent()
    elseif event == "UNIT_FLAGS" then
        local unit = ...
        if unit == "pet" then
            self:OnPetEvent()
        end
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if unit == "pet" then
            self:OnPetEvent()
        elseif unit and unit:match("^party%d$") then
            self:OnPartyMemberHealth(unit)
        end
    elseif event == "PLAYER_LEVEL_UP" then
        self:OnPlayerLevelUp(...)
    elseif event == "UPDATE_PENDING_MAIL" then
        self:OnNewMail(...)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        if self:HasEnabledTrigger("UNIT_AURA") or self:HasEnabledTrigger("EAT_BUFF") then
            self:BuildAuraSpellCache()
        end
        -- When leaving combat, sync ring frames that were secure-toggled during lockdown.
        if event == "PLAYER_REGEN_ENABLED" then
            self:SyncRingFramesAfterCombat()
        end
        self:OnCombatStateChanged(event == "PLAYER_REGEN_DISABLED" and "enter" or "exit")
    end
end

-- Pre-cache aura names before combat
function Core:BuildAuraSpellCache()
    if not Core.spellCache then Core.spellCache = {} end
    
    local function cacheAuras(filter)
        if C_UnitAuras.GetUnitAuras then
            local success, auraList = pcall(C_UnitAuras.GetUnitAuras, "player", filter)
            if success and auraList then
                for _, aura in ipairs(auraList) do
                    local spellId = aura.spellId
                    local name = aura.name
                    if spellId and name then
                        -- Use pcall to skip "secret" spell IDs that Blizzard prevents from being keys
                        pcall(function()
                            Core.spellCache[spellId] = name
                        end)
                    end
                end
            end
        end
    end
    
    cacheAuras("HELPFUL")
    cacheAuras("HARMFUL")
end

-- After combat ends, re-position any ring that was opened during combat
-- (ClearAllPoints/SetPoint were blocked, so position it now).
function Core:SyncRingFramesAfterCombat()
    local function syncRing(ring)
        if not ring or not ring.ringFrame then return end
        local frame = ring.ringFrame
        if frame:IsShown() and ring.actionButton then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", ring.actionButton, "CENTER", 0, 0)
        end
    end
    syncRing(OxedHub.EmotionRing)
    syncRing(OxedHub.ToyRing)
    if OxedHub.RefreshSharedRingSurfaceVisibility then
        OxedHub.RefreshSharedRingSurfaceVisibility()
    end
end

function Core:MigrateUnsupportedTriggers()
    local triggers = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers
    if not triggers then
        return
    end

    for _, trigger in pairs(triggers) do
        if trigger.event == "INTERRUPT_SUCCESS" then
            trigger.event = "INTERRUPT_USED"
        elseif trigger.event == "LOSS_OF_CONTROL" then
            trigger.event = "CONTROL_LOST"
        elseif trigger.event == "INTERRUPT_READY" then
            trigger.event = "CD_READY"
        elseif trigger.event == "CLEU" or trigger.event == "CRITICAL_HIT" or trigger.event == "META_DAMAGE" then
            trigger.enabled = false
        end

        -- Summon chat is no longer supported (Blizzard blocks automated
        -- SendChatMessage). Strip any pre-saved chat actions so old triggers
        -- stop throwing ADDON_ACTION_BLOCKED.
        if trigger.event == "SUMMON" and type(trigger.actions) == "table" then
            trigger.actions.chatMessage = nil
            trigger.actions.summonIncomingChatMessage = nil
            trigger.actions.summonAcceptedChatMessage = nil
            trigger.actions.summonDeclinedChatMessage = nil
        end
    end
end

function Core:MigrateLegacySoundPathsAndIds()
    if not OxedHub.Sounds or not OxedHub.Sounds.ResolvePathOrId then
        return
    end

    local profiles = OxedHubDB and OxedHubDB.profiles
    if type(profiles) ~= "table" then
        return
    end

    for profileName, p in pairs(profiles) do
        if type(p) == "table" then
            -- A. Triggers
            if type(p.triggers) == "table" then
                for _, trigger in pairs(p.triggers) do
                    if type(trigger) == "table" and type(trigger.actions) == "table" then
                        local acts = trigger.actions
                        if acts.sound then
                            acts.sound = OxedHub.Sounds:ResolvePathOrId(acts.sound)
                        end
                        if acts.successSound then
                            acts.successSound = OxedHub.Sounds:ResolvePathOrId(acts.successSound)
                        end
                        if acts.failSound then
                            acts.failSound = OxedHub.Sounds:ResolvePathOrId(acts.failSound)
                        end
                    end
                end
            end
            
            -- B. Emotion Mappings
            if type(p.emotionMappings) == "table" then
                for _, mapping in pairs(p.emotionMappings) do
                    if type(mapping) == "table" and mapping.sound then
                        mapping.sound = OxedHub.Sounds:ResolvePathOrId(mapping.sound)
                    end
                end
            end
            
            -- C. Toy Mixes
            if type(p.toyMixes) == "table" then
                for _, mix in pairs(p.toyMixes) do
                    if type(mix) == "table" and type(mix.actions) == "table" then
                        local acts = mix.actions
                        if acts.sound then
                            acts.sound = OxedHub.Sounds:ResolvePathOrId(acts.sound)
                        end
                    end
                end
            end
        end
    end
end

function Core:CleanupPlaceholderSounds()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then
        return
    end

    local sounds = profile.customSounds
    if sounds then
        for soundId in pairs(PLACEHOLDER_SOUND_IDS) do
            sounds[soundId] = nil
        end
    end

    local triggers = profile.triggers
    if triggers then
        for _, trigger in pairs(triggers) do
            local actions = trigger.actions
            if actions and PLACEHOLDER_SOUND_IDS[actions.sound] then
                actions.sound = nil
            end
        end
    end
end

function Core:CleanupPlaceholderTriggers()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then
        return
    end

    for triggerId in pairs(PLACEHOLDER_TRIGGER_IDS) do
        profile.triggers[triggerId] = nil
    end
end

function Core:CleanupPlaceholderAnimations()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then
        return
    end

    local animations = profile.animations
    if animations then
        for animationId in pairs(PLACEHOLDER_ANIMATION_IDS) do
            animations[animationId] = nil
        end
    end

    local triggers = profile.triggers
    if triggers then
        for _, trigger in pairs(triggers) do
            local actions = trigger.actions
            if actions and PLACEHOLDER_ANIMATION_IDS[actions.animation] then
                actions.animation = nil
            end
        end
    end
end

function Core:FixBuiltInAnimationSizes()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return end
    local animations = profile.animations
    if not animations then return end
    for id, anim in pairs(animations) do
        if anim.isBuiltIn then
            anim.width = 128
            anim.height = 128
        end
    end
end

function Core:MigrateAnimationsToPNG()
    if not OxedHubDB or not OxedHubDB.profiles then return end
    for _, profile in pairs(OxedHubDB.profiles) do
        if profile.animations then
            for id, anim in pairs(profile.animations) do
                if type(anim.tgaPath) == "string" and anim.tgaPath:lower():find("%.tga$") then
                    anim.tgaPath = anim.tgaPath:gsub("%.[tT][gG][aA]$", ".png")
                end
            end
        end
    end
end

-- Deferred startup
function Core:Bootstrap()
    if isLoaded then
        return
    end

    -- Grab the event frame created by Loader.lua (pristine context)
    Core.eventFrame = OxedHub._loaderFrame

    -- Initialize SavedVariables
    if not OxedHubDB then
        OxedHubDB = {}
    end

    -- ── Multi-profile bootstrap ──────────────────────────────────────────
    -- Migrate legacy single-profile DB into the profiles system.
    if not OxedHubDB.profiles then
        OxedHubDB.profiles = {}
        if OxedHubDB.profile then
            -- Move existing data into "Default" profile
            OxedHubDB.profiles["Default"] = OxedHubDB.profile
            OxedHubDB.profile = nil
        end
        OxedHubDB.activeProfile = "Default"
    end

    local seededProfiles = SeedBuiltInProfiles()
    CleanupAccidentalSeededProfiles()
    EnsureGlobalSettings()
    ApplyBuiltInProfileMetadata()

    -- Ensure active profile name is valid for this character
    local charKey = OxedHub:GetCharacterKey()
    local characterActiveProfiles = OxedHubDB.globalSettings.characterActiveProfiles or {}
    local savedProfile = characterActiveProfiles[charKey]

    if not savedProfile or not OxedHubDB.profiles[savedProfile] then
        if not OxedHubDB.activeProfile or not OxedHubDB.profiles[OxedHubDB.activeProfile] then
            local firstName = next(OxedHubDB.profiles)
            OxedHubDB.activeProfile = firstName or "Default"
            OxedHubDB.profiles["Default"] = OxedHubDB.profiles["Default"] or {}
        end
        savedProfile = OxedHubDB.activeProfile
    end

    OxedHubDB.activeProfile = savedProfile
    OxedHubDB.profile = OxedHubDB.profiles[savedProfile]
    -- ─────────────────────────────────────────────────────────────────────
    
    -- Merge with defaults
    OxedHubDB = OxedHub:MergeDefaults(OxedHubDB)
    OxedHub.db = OxedHubDB
    OxedHub:ApplyLanguage()
    OxedHub:SyncSharedCustomSounds(OxedHubDB.profile)
    self:MigrateUnsupportedTriggers()
    self:CleanupPlaceholderTriggers()
    self:CleanupPlaceholderSounds()
    self:CleanupPlaceholderAnimations()
    self:FixBuiltInAnimationSizes()
    self:MigrateAnimationsToPNG()
    if OxedHub.Animations and OxedHub.Animations.SyncMemePack then
        OxedHub.Animations:SyncMemePack()
    elseif OxedHub.Animations and OxedHub.Animations.SyncTikTokPack then
        OxedHub.Animations:SyncTikTokPack()
    end
    if OxedHub.Sounds and OxedHub.Sounds.SyncMemePack then
        OxedHub.Sounds:SyncMemePack()
    elseif OxedHub.Sounds and OxedHub.Sounds.SyncTikTokPack then
        OxedHub.Sounds:SyncTikTokPack()
    end
    if OxedHub.Sounds and OxedHub.Sounds.SyncGeneratedCatalog then
        OxedHub.Sounds:SyncGeneratedCatalog()
    end
    self:MigrateLegacySoundPathsAndIds()

    -- Mark as loaded so events can be processed
    isLoaded = true

    -- Register slash commands
    self:RegisterSlashCommands()

    -- Print load message
    local loadMsg = OxedHub.L["ADDON_LOADED"] or "|cff00ff00Oxed Hub|r v%s loaded. Type |cffffff00/oxedhub|r or |cffffff00/ohub|r to open."
    print(string.format(loadMsg, OxedHub.CONFIG.VERSION))
    if seededProfiles > 0 then
        print("|cff00ff00Oxed Hub:|r Added |cffffff00" .. seededProfiles .. "|r bundled profiles.")
    end

    -- Call refresh on all registered modules
    if OxedHub.Triggers and OxedHub.Triggers.RefreshAllNativeEffects then
        OxedHub.Triggers:RefreshAllNativeEffects()
    end

    -- If PLAYER_LOGIN already fired, run login init now
    if IsLoggedIn and IsLoggedIn() then
        self:OnPlayerLogin()
    end
end

-- â”€â”€ Profile Management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- ── Language & Localization Support ──────────────────────────────────────────

function OxedHub:ApplyLanguage(langKey)
    -- Default to db setting if no argument provided
    if not langKey then
        langKey = self.db and self.db.profile and self.db.profile.settings and self.db.profile.settings.language
    end
    
    -- Fallback to client locale detection if not explicitly set
    if not langKey then
        local clientLocale = GetLocale()
        if clientLocale == "esES" or clientLocale == "esMX" then
            langKey = "esES"
        elseif clientLocale == "arAR" then
            langKey = "arAR"
        else
            langKey = "enUS"
        end
    end
    
    -- Clear current table values
    wipe(self.L)
    
    -- 1. Copy all English keys first as baseline fallback
    if self.Locales and self.Locales.enUS then
        for k, v in pairs(self.Locales.enUS) do
            self.L[k] = v
        end
    end
    
    -- 2. Copy the chosen language's keys to overwrite the English values
    if langKey and langKey ~= "enUS" and self.Locales and self.Locales[langKey] then
        for k, v in pairs(self.Locales[langKey]) do
            self.L[k] = v
        end
    end
end

function OxedHub:GetFont(defaultFont)
    local lang = self.db and self.db.profile and self.db.profile.settings and self.db.profile.settings.language
    if lang == "arAR" then
        return "Interface\\AddOns\\OxedHub\\Media\\Fonts\\NotoSansArabic-Regular.ttf"
    end
    return defaultFont or "Fonts\\FRIZQT__.ttf"
end

function OxedHub:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    return (name and realm) and (name .. "-" .. realm) or "DefaultChar"
end

function OxedHub:GetActiveProfileName()
    local charKey = self:GetCharacterKey()
    if OxedHubDB and OxedHubDB.globalSettings and OxedHubDB.globalSettings.characterActiveProfiles then
        local savedProfile = OxedHubDB.globalSettings.characterActiveProfiles[charKey]
        if savedProfile and OxedHubDB.profiles[savedProfile] then
            return savedProfile
        end
    end
    return OxedHubDB.activeProfile or "Default"
end

function OxedHub:GetPlayerClassToken()
    return GetPlayerClassToken()
end

function OxedHub:GetSupportedClassProfiles()
    local classes = {
        { token = false, name = "No Class" },
    }

    for _, token in ipairs(CLASS_PROFILE_ORDER) do
        classes[#classes + 1] = {
            token = token,
            name = CLASS_PROFILE_NAMES[token],
        }
    end

    return classes
end

function OxedHub:GetClassDisplayName(classToken)
    local normalized = NormalizeClassToken(classToken)
    return normalized and CLASS_PROFILE_NAMES[normalized] or nil
end

function OxedHub:GetProfileClassToken(name)
    local profile = OxedHubDB and OxedHubDB.profiles and OxedHubDB.profiles[name]
    if type(profile) ~= "table" then
        return false
    end

    profile.metadata = profile.metadata or {}
    local normalized = NormalizeClassToken(profile.metadata.classToken)
    if normalized then
        profile.metadata.classToken = normalized
        return normalized
    end

    return false
end

function OxedHub:SetProfileClassToken(name, classToken)
    local profile = OxedHubDB and OxedHubDB.profiles and OxedHubDB.profiles[name]
    if type(profile) ~= "table" then
        return false
    end

    profile.metadata = profile.metadata or {}
    profile.metadata.classToken = NormalizeClassToken(classToken)
    return true
end

function OxedHub:GetProfileDisplayName(name)
    -- The user explicitly requested to completely remove the "[Class]" suffix
    -- so that they can totally rename it without the suffix being appended.
    return name
end

function OxedHub:GetProfileMetadata(name)
    local profile = OxedHubDB and OxedHubDB.profiles and OxedHubDB.profiles[name]
    if type(profile) == "table" then
        profile.metadata = profile.metadata or {}
        return profile.metadata
    end
    return nil
end

function OxedHub:GetProfileColoredName(name)
    local displayName = self:GetProfileDisplayName(name)
    local metadata = self:GetProfileMetadata(name)
    
    local colorCode
    if metadata and metadata.customColor then
        local c = metadata.customColor
        colorCode = string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
    else
        local classToken = self:GetProfileClassToken(name)
        if classToken then
            local classColors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
            local color = classColors and classColors[classToken]
            if color then
                if color.GenerateHexColor then
                    colorCode = color:GenerateHexColor()
                elseif color.colorStr then
                    colorCode = color.colorStr
                end
            end
        end
    end

    if not colorCode or colorCode == "" then
        return displayName
    end

    if not string.find(colorCode, "^|c") then
        colorCode = "|c" .. colorCode
    end

    return colorCode .. displayName .. "|r"
end

function OxedHub:ShowCopyURLDialog(url, titleText)
    if not url or url == "" then return end

    if not StaticPopupDialogs["OXEDHUB_COPY_URL"] then
        StaticPopupDialogs["OXEDHUB_COPY_URL"] = {
            text = "%s\n\n|cffffd100Press Ctrl+C to copy URL:|r",
            button1 = OKAY or "Done",
            hasEditBox = true,
            editBoxWidth = 340,
            maxLetters = 256,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnShow = function(dialog, data)
                local eb = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
                if eb then
                    eb:SetText(data and data.url or "")
                    eb:HighlightText()
                    eb:SetFocus()
                end
            end,
            EditBoxOnEnterPressed = function(editBox)
                editBox:GetParent():Hide()
            end,
            EditBoxOnEscapePressed = function(editBox)
                editBox:GetParent():Hide()
            end,
        }
    end

    local title = titleText or "Wowhead Link"
    local dialog = StaticPopup_Show("OXEDHUB_COPY_URL", "|cffffffff" .. title .. "|r")
    if dialog then
        dialog.data = { url = url }
        local eb = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
        if eb then
            eb:SetText(url)
            eb:HighlightText()
            eb:SetFocus()
        end
    end
end

function OxedHub:GetClassProfileName()
    local classFile = GetPlayerClassToken()
    if not classFile then
        return nil
    end

    local exactName = CLASS_PROFILE_NAMES[classFile]
    if exactName and OxedHubDB and OxedHubDB.profiles and OxedHubDB.profiles[exactName] then
        return exactName
    end

    local activeName = self:GetActiveProfileName()
    if activeName and self:GetProfileClassToken(activeName) == classFile then
        return activeName
    end

    for _, name in ipairs(self:GetProfileList()) do
        if self:GetProfileClassToken(name) == classFile then
            return name
        end
    end

    return nil
end

function OxedHub:GetProfileList()
    local names = {}
    for name in pairs(OxedHubDB.profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function OxedHub:SwitchProfile(name, options)
    if not name or not OxedHubDB.profiles[name] then return false end
    if name == self:GetActiveProfileName() then return true end

    local charKey = self:GetCharacterKey()
    if OxedHubDB.globalSettings and OxedHubDB.globalSettings.characterActiveProfiles then
        OxedHubDB.globalSettings.characterActiveProfiles[charKey] = name
    end

    OxedHubDB.activeProfile = name
    OxedHubDB.profile = OxedHubDB.profiles[name]
    OxedHubDB = self:MergeDefaults(OxedHubDB)
    self.db = OxedHubDB
    self:SyncSharedCustomSounds(OxedHubDB.profile)

    -- Live-refresh all modules so they pick up the new profile data
    if OxedHub.Triggers then
        if OxedHub.Triggers.RefreshAllNativeEffects then OxedHub.Triggers:RefreshAllNativeEffects() end
        if OxedHub.Triggers.RefreshDashboard then OxedHub.Triggers:RefreshDashboard() end
        if OxedHub.Triggers.RefreshTriggersList then OxedHub.Triggers:RefreshTriggersList() end
    end
    if OxedHub.Toys and OxedHub.Toys.RefreshSavedMixesList then
        OxedHub.Toys:RefreshSavedMixesList()
    end
    if OxedHub.ActionHub then
        if OxedHub.ActionHub.RefreshTab then pcall(function() OxedHub.ActionHub:RefreshTab() end) end
        if OxedHub.ActionHub.RefreshAllWidgets then pcall(function() OxedHub.ActionHub:RefreshAllWidgets() end) end
    end
    if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshFromProfile then
        pcall(function() OxedHub.OxedRingEditor:RefreshFromProfile() end)
    end
    if OxedHub.OxedRing then
        if OxedHub.OxedRing.RebuildSlices then pcall(function() OxedHub.OxedRing:RebuildSlices() end) end
        if OxedHub.OxedRing.UpdateSecureAttributes then pcall(function() OxedHub.OxedRing:UpdateSecureAttributes() end) end
    end
    -- Re-show the current tab to force a full UI refresh
    if OxedHub.UI then
        if OxedHub.UI.ApplyGlobalTextSize then
            OxedHub.UI:ApplyGlobalTextSize()
        end
        local mainFrame = OxedHub.UI.GetMainFrame and OxedHub.UI:GetMainFrame()
        local hasContentArea = OxedHub.UI.GetContentArea and OxedHub.UI:GetContentArea()
        if mainFrame and hasContentArea and OxedHub.UI.GetCurrentTab and OxedHub.UI.ShowTab then
            local currentTab = OxedHub.UI:GetCurrentTab()
            if currentTab and not InCombatLockdown() then
                OxedHub.UI:ShowTab(currentTab)
            end
        end
        if mainFrame and hasContentArea and OxedHub.UI.RefreshProfileDropdown then
            OxedHub.UI.RefreshProfileDropdown()
        end
        -- Keep the Settings > Profiles details/credits panel in sync.
        if OxedHub.UI.RefreshProfileDetails then
            OxedHub.UI:RefreshProfileDetails()
        end
    end

    if not (options and options.silent) then
        print("|cff00ff00Oxed Hub:|r Switched to profile |cffffff00" .. name .. "|r.")
    end
    return true
end

function Core:ApplyAutoClassProfile()
    if not OxedHubDB or not OxedHubDB.globalSettings then
        return false
    end

    local charKey = OxedHub:GetCharacterKey()
    local characterActiveProfiles = OxedHubDB.globalSettings.characterActiveProfiles or {}
    local savedProfile = characterActiveProfiles[charKey]

    if savedProfile == nil or not OxedHubDB.profiles[savedProfile] then
        -- FIRST LOGIN of this character or deleted profile!
        if OxedHubDB.globalSettings.autoSwitchClassProfile then
            local classProfileName = OxedHub:GetClassProfileName()
            if classProfileName and OxedHubDB.profiles[classProfileName] then
                -- Save it for this character
                characterActiveProfiles[charKey] = classProfileName
                OxedHubDB.globalSettings.characterActiveProfiles = characterActiveProfiles
                OxedHub:SwitchProfile(classProfileName, { silent = true })
                print("|cff00ff00Oxed Hub:|r Auto-switched to your class profile |cffffff00" .. classProfileName .. "|r.")
                return true
            end
        end
        -- Default fallback if class profile not found or autoSwitch is off
        characterActiveProfiles[charKey] = OxedHubDB.activeProfile or "Default"
        OxedHubDB.globalSettings.characterActiveProfiles = characterActiveProfiles
    else
        -- SUBSEQUENT LOGIN: Switch to their saved choice, respect user choice
        if OxedHubDB.profiles[savedProfile] and savedProfile ~= OxedHubDB.activeProfile then
            OxedHub:SwitchProfile(savedProfile, { silent = true })
            return true
        end
    end

    return false
end

function OxedHub:CreateProfile(name, classToken)
    if not name or name == "" then return false end
    if OxedHubDB.profiles[name] then return false end
    if not self:CanCreateProfileSlot() then return false, "max_profiles" end

    OxedHubDB.profiles[name] = {}
    -- Merge defaults into the new empty profile
    local tempDB = { profile = OxedHubDB.profiles[name] }
    self:MergeDefaults(tempDB)
    OxedHubDB.profiles[name] = tempDB.profile
    self:SyncSharedCustomSounds(OxedHubDB.profiles[name])
    EnsureProfileUiStartsDisabled(OxedHubDB.profiles[name])
    self:SetProfileClassToken(name, classToken)
    return true
end

function OxedHub:CopyProfile(srcName, destName, classToken)
    if not srcName or not destName or destName == "" then return false end
    if not OxedHubDB.profiles[srcName] then return false end
    if OxedHubDB.profiles[destName] then return false end
    if not self:CanCreateProfileSlot() then return false, "max_profiles" end

    OxedHubDB.profiles[destName] = CopyTable(OxedHubDB.profiles[srcName])
    self:SyncSharedCustomSounds(OxedHubDB.profiles[destName])
    EnsureProfileUiStartsDisabled(OxedHubDB.profiles[destName])
    if classToken ~= nil then
        self:SetProfileClassToken(destName, classToken)
    end
    return true
end

function OxedHub:DeleteProfile(name)
    if not name or not OxedHubDB.profiles[name] then return false end
    -- Can't delete the active profile
    if name == OxedHubDB.activeProfile then return false end

    -- If this is a built-in profile, remember that the user deleted it
    -- so SeedBuiltInProfiles won't re-create it on next reload.
    local bundledProfiles = OxedHub.BUILT_IN_PROFILES
    if type(bundledProfiles) == "table" and bundledProfiles[name] then
        OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
        OxedHubDB.globalSettings.deletedBuiltInProfiles = OxedHubDB.globalSettings.deletedBuiltInProfiles or {}
        OxedHubDB.globalSettings.deletedBuiltInProfiles[name] = true
    end

    OxedHubDB.profiles[name] = nil
    return true
end

function OxedHub:RenameProfile(oldName, newName)
    if not oldName or not newName or newName == "" then return false end
    if not OxedHubDB.profiles[oldName] then return false end
    if OxedHubDB.profiles[newName] then return false end

    OxedHubDB.profiles[newName] = OxedHubDB.profiles[oldName]
    OxedHubDB.profiles[oldName] = nil

    if OxedHubDB.activeProfile == oldName then
        OxedHubDB.activeProfile = newName
        OxedHubDB.profile = OxedHubDB.profiles[newName]
    end

    if OxedHubDB.globalSettings and OxedHubDB.globalSettings.characterActiveProfiles then
        for charKey, savedProfileName in pairs(OxedHubDB.globalSettings.characterActiveProfiles) do
            if savedProfileName == oldName then
                OxedHubDB.globalSettings.characterActiveProfiles[charKey] = newName
            end
        end
    end

    return true
end

-- Player login handler
function Core:OnPlayerLogin()
    if isPlayerLoginHandled then
        return
    end
    isPlayerLoginHandled = true

    -- Baseline for the honorable-kill counter, used to attribute kills in
    -- instanced PvP where the attacker GUID is hidden.
    self:InitPvPKillBaseline()

    self:ApplyAutoClassProfile()

    -- Initialize UI
    if OxedHub.UI then
        OxedHub.UI:Init()
    end
    
    -- Initialize Animations (creates player frame)
    if OxedHub.Animations then
        OxedHub.Animations:Init()
    end
    
    -- Initialize minimap button
    if OxedHub.MinimapButton then
        OxedHub.MinimapButton:Init()
    end
    
    -- Initialize Emotion Ring (creates floating button and ring, but keeps it hidden)
    if OxedHub.EmotionRing then
        OxedHub.EmotionRing:Init()
    end
    
    -- Initialize Toy Ring
    if OxedHub.ToyRing then
        OxedHub.ToyRing:Init()
    end

    -- Initialize OxedRing
    if OxedHub.OxedRing then
        OxedHub.OxedRing:Init()
    end
    
    -- Initialize MacroRegistry
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:Init()
    end

    -- Initialize Toys
    if OxedHub.Toys then
        OxedHub.Toys:Init()
    end
    
    -- Initialize ActionHub
    if OxedHub.ActionHub then
        OxedHub.ActionHub:Init()
    end

    -- Register native WoW Options/AddOns page
    if OxedHub.BlizzardSettings and OxedHub.BlizzardSettings.Register then
        OxedHub.BlizzardSettings:Register()
    end

    self:ApplyAutoClassProfile()
    C_Timer.After(1, function()
        if isLoaded then
            self:ApplyAutoClassProfile()
        end
    end)
    
    -- Restore window visibility
    local profile = OxedHub.db.profile
    if profile.settings and profile.settings.mainWindowVisible then
        if OxedHub.UI and OxedHub.UI.ShowMainWindow then
            OxedHub.UI:ShowMainWindow()
        end
    end
    
    -- Initialize pet state
    previousPetState = GetPetState()

    self:InstallSummonHooks()
end

-- Update cooldowns
function Core:UpdateCooldowns()
    local now = GetTime()
    for key, expiry in pairs(cooldowns) do
        if now >= expiry then
            cooldowns[key] = 0
        end
    end
end

-- Check if action is on cooldown
function Core:IsOnCooldown(actionType)
    local expiry = cooldowns[actionType] or 0
    if expiry == 0 then
        return false
    end

    if expiry <= GetTime() then
        cooldowns[actionType] = 0
        return false
    end

    return true
end

-- Set cooldown for action
function Core:SetCooldown(actionType, duration)
    cooldowns[actionType] = GetTime() + duration
end

-- Combat Log Event handler
function Core:OnCombatLogEvent()
    local timestamp, subEvent, _, sourceGUID, sourceName, sourceFlags, _, 
          destGUID, destName, destFlags, _, spellID, spellName, spellSchool, 
          amount, overkill, school, resisted, blocked, absorbed, critical = CombatLogGetCurrentEventInfo()
    
    -- Critical damage
    if subEvent == "SPELL_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "SWING_DAMAGE" or subEvent == "SPELL_PERIODIC_DAMAGE" then
        if sourceGUID == UnitGUID("player") and critical then
            OxedHub.Triggers:ProcessEvent("CRITICAL_HIT", {
                spellID = spellID,
                spellName = spellName,
                amount = amount,
                critical = true,
            })
        end
        
        -- Meta damage tracking
        self:TrackDamage(sourceGUID, sourceName, amount or 0)
    end
    
    -- Damage tracking for meta
    if subEvent == "SPELL_DAMAGE" or subEvent == "RANGE_DAMAGE" or subEvent == "SWING_DAMAGE" then
        local dmg = amount or 0
        if sourceGUID and dmg > 0 then
            self:TrackDamage(sourceGUID, sourceName, dmg)
        end
    end
end

-- Track damage for meta calculation
function Core:TrackDamage(guid, name, amount)
    local now = GetTime()
    
    -- Clean old entries
    for id, data in pairs(damageCache) do
        if now - data.time > META_DAMAGE_WINDOW then
            damageCache[id] = nil
        end
    end
    
    -- Add new entry
    if not damageCache[guid] then
        damageCache[guid] = { total = 0, time = now, name = name }
    end
    damageCache[guid].total = damageCache[guid].total + amount
    damageCache[guid].time = now
    
    -- Check if player is top damage
    local playerGUID = UnitGUID("player")
    if guid == playerGUID and self:IsTopDamage() then
        OxedHub.Triggers:ProcessEvent("META_DAMAGE", {
            total = damageCache[guid].total,
        })
    end
end

-- Check if player has highest damage
function Core:IsTopDamage()
    local playerGUID = UnitGUID("player")
    local playerTotal = damageCache[playerGUID] and damageCache[playerGUID].total or 0
    
    for guid, data in pairs(damageCache) do
        if guid ~= playerGUID and data.total > playerTotal then
            return false
        end
    end
    
    return playerTotal > 0
end

-- Shared buffers for OnUnitAura to prevent excessive memory allocations
local auraBuffer_Current = {}
local auraBuffer_FoodNew = {}
local auraBuffer_Buffs = {}
local auraBuffer_Debuffs = {}
local foodAuraCache = {}
local WELL_FED_ICON = 134062

-- Highly optimized secret value check (prevents per-aura table allocations)
local secretTestTable = {}
local function CheckSecretValue(val)
    if issecretvalue then return issecretvalue(val) end
    if val == nil then return false end
    
    local ok = pcall(function() secretTestTable[val] = true end)
    if ok then
        secretTestTable[val] = nil
        return false
    end
    return true
end

local function NormalizeCooldownNumber(val)
    if val == nil or CheckSecretValue(val) then
        return nil
    end

    local ok, numeric = pcall(function()
        return tonumber(tostring(val))
    end)
    if ok then
        return numeric
    end

    return nil
end

local function SafeUnitMatch(unitA, unitB)
    if not unitA or not unitB or unitA == "" or unitB == "" then
        return false
    end

    local ok, sameUnit = pcall(UnitIsUnit, unitA, unitB)
    return ok and sameUnit or false
end

-- Efficiently scan auras into a pre-allocated buffer
local function ScanUnitAuras(filter, buffer)
    -- Clear previous buffer contents
    for i=1, #buffer do buffer[i] = nil end
    
    local outIdx = 1
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if ok and not aura then 
            if OxedHub.debug then print("[OxedHub-Debug] ScanUnitAuras broke at index:", i, "for filter:", filter) end
            break 
        end
        if ok and aura then
            buffer[outIdx] = aura
            outIdx = outIdx + 1
        end
    end
    
    if OxedHub.debug then print("[OxedHub-Debug] ScanUnitAuras finished for filter:", filter, "found:", #buffer) end
    
    return buffer
end

local function ResolveAuraNameForFoodCheck(spellId)
    if not spellId then
        return nil
    end

    -- spellId can be a "secret" value that Blizzard forbids as a table key, so
    -- every cache read/write has to be pcall-guarded (same as BuildAuraSpellCache).
    local okCache, cached = pcall(function()
        return Core.spellCache and Core.spellCache[spellId]
    end)
    if okCache and cached then
        return cached
    end

    local okInfo, spellInfo = pcall(function()
        return C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
    end)
    local name = okInfo and spellInfo and spellInfo.name
    if name then
        Core.spellCache = Core.spellCache or {}
        pcall(function()
            Core.spellCache[spellId] = name
        end)
    end

    return name
end

-- Comparing a "secret" value (12.0 aura privacy) raises an error, so every
-- equality test against aura data has to run inside a pcall.
local function SafeEquals(value, expected)
    local ok, isEqual = pcall(function() return value == expected end)
    return ok and isEqual or false
end

-- Returns the matching literal from `list` (never the caller's possibly-secret
-- value), so callers have a plain string safe to concatenate, store, or display.
local function SafeMatchesAny(value, list)
    if value == nil then return nil end
    for _, expected in ipairs(list) do
        if SafeEquals(value, expected) then
            return expected
        end
    end
    return nil
end

local FOOD_AURA_NAMES = { "Food", "Drink", "Food & Drink", "Refreshment" }
local WELL_FED_AURA_NAMES = { "Well Fed", "Hearty Well Fed" }

-- Each returns the plain matched name (e.g. "Drink") or nil.
local function IsFoodAuraBySpellId(spellId)
    return SafeMatchesAny(ResolveAuraNameForFoodCheck(spellId), FOOD_AURA_NAMES)
end

local function IsWellFedAuraBySpellId(spellId, icon)
    local resolvedName = ResolveAuraNameForFoodCheck(spellId)

    local name = SafeMatchesAny(resolvedName, WELL_FED_AURA_NAMES)
    if name then
        return name
    end

    -- Icon fallback ONLY when the name can't be read. Several buffs borrow the
    -- Well Fed icon without being food at all (Suspicious Energy Drink, for
    -- one), so matching on the icon while the name is perfectly readable and
    -- clearly says otherwise produced false "you're eating" triggers.
    if resolvedName ~= nil then
        return nil
    end

    if SafeEquals(icon, WELL_FED_ICON) then
        return WELL_FED_AURA_NAMES[1]
    end
    return nil
end

function Core:ProcessFoodAuraOnly(now)
    local currentFoodAuras = {}
    local newFoodNames = {}
    local isEatingNow = false
    local hasWellFedNow = false

    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if ok and not aura then
            break
        end
        if ok and aura then
            local spellId = aura.spellId
            local icon = aura.icon

            -- These return a plain literal ("Drink", "Well Fed", ...) or nil, never
            -- the aura's own possibly-secret name, so they're safe to key and display.
            local foodName = IsFoodAuraBySpellId(spellId)
            local wellFedName = not foodName and IsWellFedAuraBySpellId(spellId, icon) or nil
            local matchedName = foodName or wellFedName

            if matchedName then
                local key = (foodName and "f" or "w") .. matchedName
                currentFoodAuras[key] = matchedName
                if not foodAuraCache[key] then
                    newFoodNames[#newFoodNames + 1] = matchedName
                end
                if foodName then
                    isEatingNow = true
                else
                    hasWellFedNow = true
                end
            end
        end
    end

    if isEatingNow and not Core.wasEating then
        OxedHub.Triggers:ProcessEvent("EAT_BUFF", { eatState = "start" })
    elseif not isEatingNow and Core.wasEating then
        OxedHub.Triggers:ProcessEvent("EAT_BUFF", { eatState = "stop", hasWellFed = hasWellFedNow })
    end
    Core.wasEating = isEatingNow

    if #newFoodNames > 0 then
        if not Core.lastEatBuffTime or (now - Core.lastEatBuffTime > 30) then
            Core.lastEatBuffTime = now
            OxedHub.Triggers:ProcessEvent("EAT_BUFF", {
                unit = "player",
                buffs = newFoodNames,
                eatState = "buff",
            })
        end
    end

    foodAuraCache = currentFoodAuras
end

-- UNIT_AURA handler (Throttled and Optimized)
local lastAuraUpdate = 0
function Core:OnUnitAura(unit)
    if OxedHub.debug then print("[OxedHub-Debug] OnUnitAura called for unit:", unit) end
    if unit ~= "player" then return end

    -- Mount state is read from auras, so it has to be checked before the aura
    -- trigger gates below: those return early, and a profile with only a MOUNT
    -- trigger would never reach the check at the end of this function.
    -- CheckMountState itself bails when no MOUNT trigger is enabled.
    self:CheckMountState()

    local wantsUnitAura = self:HasEnabledTrigger("UNIT_AURA") or self:HasEnabledTrigger("SELF_AURA") or self:HasEnabledTrigger("BLOODLUST")
    local wantsEatBuff = self:HasEnabledTrigger("EAT_BUFF")
    if not wantsUnitAura and not wantsEatBuff then
        return
    end

    -- Throttle: Only process once per frame at most
    local now = GetTime()
    if now == lastAuraUpdate then return end
    lastAuraUpdate = now

    -- Fast path: if we only care about food/eating triggers, avoid the
    -- heavyweight generic aura gained/lost engine entirely.
    if wantsEatBuff and not wantsUnitAura then
        self:ProcessFoodAuraOnly(now)
        return
    end

    if not Core.auraCache then Core.auraCache = {} end
    if not Core.spellCache then Core.spellCache = {} end
    
    local auraCache = Core.auraCache
    local spellCache = Core.spellCache
    
    -- Taint-free spell ID presence set: {[spellID_number] = true}
    -- SelfAura.lua queries this to detect buffs even when WoW secret-taints
    -- all aura data in combat.
    local activeSpellIDsBuild = {}
    
    -- Clear current state buffers
    for k in pairs(auraBuffer_Current) do auraBuffer_Current[k] = nil end
    for k in pairs(auraBuffer_FoodNew) do auraBuffer_FoodNew[k] = nil end

    -- Scan buffs and debuffs
    ScanUnitAuras("HELPFUL", auraBuffer_Buffs)
    ScanUnitAuras("HARMFUL", auraBuffer_Debuffs)
    
    -- Anti-flicker safety check
    if #auraBuffer_Buffs == 0 and #auraBuffer_Debuffs == 0 and not UnitIsDeadOrGhost("player") and next(auraCache) ~= nil then
        if OxedHub.debug then print("[OxedHub-Debug] Anti-flicker triggered, returning.") end
        return
    end
    
    local isEatingNow = false
    local hasWellFedNow = false

    -- Helper to resolve names and update cache
    local function ProcessAuraList(list, prefix)
        for _, aura in ipairs(list) do
            local name = aura.name
            local spellId = aura.spellId
            local instanceId = aura.auraInstanceID
            
            if OxedHub.debug then
                print("[OxedHub-Debug] Raw Aura:", tostring(name), "ID:", tostring(spellId), "isSecretID:", tostring(CheckSecretValue(spellId)), "isSecretName:", tostring(CheckSecretValue(name)))
            end
            
            if instanceId then
                local realSpellID = nil
                if not CheckSecretValue(spellId) then
                    realSpellID = spellId
                else
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
                    if info and info.spellID and not CheckSecretValue(info.spellID) then
                        realSpellID = info.spellID
                    end
                end

                -- If name is secret, try to resolve it using C_Spell (which accepts secret spellIds)
                if CheckSecretValue(name) then
                    local cachedName = realSpellID and spellCache[realSpellID] or nil
                    if cachedName then
                        name = cachedName
                    else
                        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellId)
                        if spellInfo and spellInfo.name then
                            name = spellInfo.name
                            if realSpellID then
                                pcall(function() spellCache[realSpellID] = name end)
                            end
                        end
                    end
                elseif realSpellID and name then
                    -- Update name cache for future secret lookups using primitive spellId
                    pcall(function() spellCache[realSpellID] = name end)
                end

                if name and (spellId or realSpellID) then
                    local safeInstanceId = nil
                    if instanceId ~= nil and not CheckSecretValue(instanceId) then
                        safeInstanceId = tostring(instanceId)
                    elseif realSpellID ~= nil then
                        safeInstanceId = "sp_" .. tostring(realSpellID)
                    elseif name ~= nil and not CheckSecretValue(name) then
                        safeInstanceId = "nm_" .. tostring(name)
                    else
                        safeInstanceId = "idx_" .. tostring(_ or 1)
                    end

                    local key = (prefix or "") .. safeInstanceId
                    local applications = aura.applications or 0
                    local expirationTime = aura.expirationTime or 0
                    
                    -- Store in current buffer
                    auraBuffer_Current[key] = { 
                        name = name, 
                        id = realSpellID or spellId, 
                        applications = applications, 
                        expirationTime = expirationTime,
                        instanceId = instanceId
                    }
                    
                    -- Build taint-free spell ID set: use the clean ID when
                    -- available, otherwise extract from the secret value via
                    -- tonumber(tostring()) inside pcall.
                    if realSpellID then
                        activeSpellIDsBuild[realSpellID] = true
                    else
                        pcall(function()
                            local n = tonumber(tostring(spellId))
                            if n then activeSpellIDsBuild[n] = true end
                        end)
                    end

                    -- Food/Well Fed detection (cached results)
                    local safeName = not CheckSecretValue(name) and name or ""
                    local lowerName = string.lower(safeName)
                    if lowerName:find("refreshment") or lowerName:find("food") or lowerName:find("drink") or lowerName:find("eating") or lowerName:find("drinking") then
                        isEatingNow = true
                        if not auraCache[key] then table.insert(auraBuffer_FoodNew, name) end
                    end
                    if lowerName:find("well fed") or lowerName:find("feast") or lowerName:find("sated") or lowerName:find("bogling root") then
                        hasWellFedNow = true
                        if not auraCache[key] then table.insert(auraBuffer_FoodNew, name) end
                    end

                    -- Fire for newly detected auras OR if stack count increased OR refreshed
                    local isNewAura = not auraCache[key]
                    local isStackIncrease = false
                    local isRefreshed = false
                    if auraCache[key] and type(auraCache[key]) == "table" then
                        local oldApps = auraCache[key].applications or 0
                        local oldExp = auraCache[key].expirationTime or 0
                        -- applications/expirationTime can be "secret" values under
                        -- WoW's aura privacy taint; comparing them directly throws.
                        -- Guard with pcall and treat any failure as "no change" so a
                        -- new aura still fires (isNewAura) even if stack/refresh
                        -- detection isn't possible for this aura.
                        local okApps, appsIncreased = pcall(function() return applications > oldApps end)
                        if okApps and appsIncreased then
                            isStackIncrease = true
                        end
                        local okExp, refreshed = pcall(function() return expirationTime > oldExp + 0.5 end)
                        if okExp and refreshed then
                            isRefreshed = true
                        end
                    end

                    if isNewAura or isStackIncrease or isRefreshed then
                        if OxedHub.debug then
                            if isNewAura then
                                print(string.format("|cff00ffff[OxedHub-Debug]|r Aura Gained: %s (ID: %s)", tostring(name), tostring(realSpellID or spellId)))
                            elseif isStackIncrease then
                                print(string.format("|cff00ffff[OxedHub-Debug]|r Aura Stack Increased: %s (ID: %s) to %d", tostring(name), tostring(realSpellID or spellId), applications))
                            else
                                print(string.format("|cff00ffff[OxedHub-Debug]|r Aura Refreshed: %s (ID: %s)", tostring(name), tostring(realSpellID or spellId)))
                            end
                        end
                        OxedHub.Triggers:ProcessEvent("UNIT_AURA", {
                            spellName = name,
                            spellID = realSpellID or spellId,
                            icon = aura.icon,
                            duration = aura.duration,
                            expirationTime = aura.expirationTime,
                            applications = applications,
                            isLost = false,
                        })
                    end
                end
            end
        end
    end

    ProcessAuraList(auraBuffer_Buffs, "")
    ProcessAuraList(auraBuffer_Debuffs, "d")

    -- Detect lost auras
    for key, data in pairs(auraCache) do
        if not auraBuffer_Current[key] then
            if type(data) == "table" and data.name then
                if OxedHub.debug then
                    print(string.format("|cff00ffff[OxedHub-Debug]|r Aura Lost: %s (ID: %s)", tostring(data.name), tostring(data.id)))
                end
                OxedHub.Triggers:ProcessEvent("UNIT_AURA", {
                    spellName = data.name,
                    spellID = data.id,
                    isLost = true,
                })
            end
            auraCache[key] = nil
        end
    end
    
    -- Finalize cache
    for key, data in pairs(auraBuffer_Current) do
        auraCache[key] = data
    end
    
    -- Publish taint-free spell ID presence set
    Core.activeSpellIDs = activeSpellIDsBuild

    -- Fire Food Start/Stop/Buff events
    if isEatingNow and not Core.wasEating then
        OxedHub.Triggers:ProcessEvent("EAT_BUFF", { eatState = "start" })
    elseif not isEatingNow and Core.wasEating then
        OxedHub.Triggers:ProcessEvent("EAT_BUFF", { eatState = "stop", hasWellFed = hasWellFedNow })
    end
    Core.wasEating = isEatingNow

    if #auraBuffer_FoodNew > 0 then
        if not Core.lastEatBuffTime or (now - Core.lastEatBuffTime > 30) then
            Core.lastEatBuffTime = now
            OxedHub.Triggers:ProcessEvent("EAT_BUFF", {
                unit = "player",
                buffs = auraBuffer_FoodNew,
                eatState = "buff"
            })
        end
    end
end

-- Any loading screen: logging in, taking a portal, zoning into or out of an
-- instance, a hearth. During the transition the client briefly reports you as
-- dismounted and then mounted again, which used to fire a phantom
-- dismount + mount-up pair. Forget the remembered state and ignore changes for
-- a moment so the real state is re-seeded silently instead.
function Core:OnEnteringWorld()
    self.wasMounted = nil
    self.mountSettleUntil = GetTime() + 4
end

function Core:CheckMountState()
    if not self:HasEnabledTrigger("MOUNT") then return end

    -- Still settling after a loading screen: keep the recorded state in step
    -- with reality, but don't treat the change as a mount/dismount action.
    if self.mountSettleUntil and GetTime() < self.mountSettleUntil then
        local okSettle, mountedNow = pcall(IsMounted)
        local okFormSettle, formNow = pcall(GetShapeshiftFormID)
        if not okSettle then mountedNow = false end
        if not okFormSettle then formNow = nil end
        local travelNow = (formNow == 3) or (formNow == 4) or (formNow == 27)
        self.wasMounted = mountedNow or travelNow
        return
    end
    
    local okMounted, isMounted = pcall(IsMounted)
    if not okMounted then isMounted = false end
    
    local okForm, formID = pcall(GetShapeshiftFormID)
    if not okForm then formID = nil end
    
    local isDruidTravel = (formID == 3) or (formID == 4) or (formID == 27)
    local currentState = isMounted or isDruidTravel

    -- First check of the session (login / reload / trigger just enabled): record
    -- the current state without firing. Otherwise logging in while already
    -- mounted would look like a fresh mount-up and play the sound.
    if self.wasMounted == nil then
        self.wasMounted = currentState
        if currentState then
            self.lastMountType = self.lastMountType or "any"
        end
        return
    end

    if currentState ~= self.wasMounted then
        self.wasMounted = currentState
        
        if currentState then
            local currentType = "any"
            if isDruidTravel then
                if formID == 4 then currentType = "aquatic"
                elseif formID == 27 then currentType = "flying"
                else -- formID == 3 (Travel Form)
                    if IsSubmerged() then currentType = "aquatic"
                    elseif IsAdvancedFlyableArea and IsAdvancedFlyableArea() then currentType = "flying"
                    elseif IsFlyableArea and IsFlyableArea() then currentType = "flying"
                    else currentType = "ground"
                    end
                end
            elseif C_MountJournal and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
                -- Find mount aura
                local mountTypeID = nil
                for i = 1, 40 do
                    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
                    if ok and not aura then break end
                    if ok and aura then
                        local mountID = C_MountJournal.GetMountFromSpell(aura.spellId)
                        if mountID then
                            local _, _, _, _, mountType = C_MountJournal.GetMountInfoExtraByID(mountID)
                            mountTypeID = mountType
                            break
                        end
                    end
                end
                
                if mountTypeID then
                    if mountTypeID == 231 or mountTypeID == 232 or mountTypeID == 254 then
                        currentType = "aquatic"
                    elseif mountTypeID == 248 or mountTypeID == 402 or mountTypeID == 424 then
                        currentType = "flying"
                    elseif mountTypeID == 230 or mountTypeID == 241 or mountTypeID == 269 then
                        currentType = "ground"
                    end
                end
            end
            
            self.lastMountType = currentType
            OxedHub.Triggers:ProcessEvent("MOUNT", { actionType = "up", mountType = currentType })
        else
            OxedHub.Triggers:ProcessEvent("MOUNT", { actionType = "down", mountType = self.lastMountType or "any" })
        end
    end
end

-- Player died handler
function Core:OnPlayerDead()
    -- Dying always ends a killing spree, whether or not a trigger wants the event.
    self:ResetPvPStreak()

    if not self:HasEnabledTrigger("PLAYER_DEAD") then
        return
    end

    OxedHub.Triggers:ProcessEvent("PLAYER_DEAD", {})
end

-- Spell cast succeeded handler
function Core:OnSpellCastSucceeded(unit, castGUID, spellID)
    if unit ~= "player" and unit ~= "pet" then return end

    local wantsSpellcast = self:HasEnabledTrigger("UNIT_SPELLCAST_SUCCEEDED")
    local wantsInterrupt = self:HasEnabledTrigger("INTERRUPT_USED")
    local wantsRaidTool = self:HasEnabledTrigger("RAID_TOOL")
    local wantsCDReady = self:HasEnabledTrigger("CD_READY")
    if not wantsSpellcast and not wantsInterrupt and not wantsRaidTool and not wantsCDReady then
        return
    end

    -- Arm Cooldown-Ready tracking the moment the watched spell is cast.
    if unit == "player" and wantsCDReady and spellID then
        self:ArmCooldownReady(spellID)
    end

    if unit == "player" and spellID then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if name then
            if not Core.spellCache then Core.spellCache = {} end
            Core.spellCache[spellID] = name
        end
    end
    
    -- Check for interrupt spells
    if wantsInterrupt then
        for _, interruptID in ipairs(OxedHub.CONFIG.INTERRUPT_SPELLS) do
            if spellID == interruptID then
                local targetGUID = UnitGUID("target")
                local mouseoverGUID = UnitGUID("mouseover")
                local targetUnit = "target"
                if mouseoverGUID and UnitIsEnemy("player", "mouseover") then
                    targetGUID = mouseoverGUID
                    targetUnit = "mouseover"
                end
                interruptSeq = interruptSeq + 1
                local mySeq = interruptSeq
                pendingInterrupt = {
                    spellID = spellID,
                    time = GetTime(),
                    targetGUID = targetGUID,
                    targetUnit = targetUnit,
                    seq = mySeq,
                }

                -- Start cooldown animation immediately on cast (BliZzi-style).
                -- Cooldown shows as soon as you press the button, not after success.
                local hasCooldownAnim = false
                for _, trigger in pairs(OxedHub.db.profile.triggers or {}) do
                    if trigger.enabled and trigger.event == "INTERRUPT_USED" and trigger.actions and trigger.actions.cooldownAnimation then
                        hasCooldownAnim = true
                        break
                    end
                end
                if hasCooldownAnim and OxedHub.Animations and OxedHub.Animations.PlayCooldownProgress then
                    OxedHub.Animations:PlayCooldownProgress(spellID)
                end

                OxedHub.Triggers:ProcessEvent("INTERRUPT_USED", {
                    spellID = spellID,
                    unit = unit,
                    result = "cast",
                })
                -- Schedule fail check after timeout (BliZzi uses 0.6s)
                C_Timer.After(INTERRUPT_RESULT_TIMEOUT, function()
                    if pendingInterrupt and pendingInterrupt.seq == mySeq then
                        OxedHub.Triggers:ProcessEvent("INTERRUPT_USED", {
                            spellID = spellID,
                            unit = unit,
                            result = "failed",
                        })
                        pendingInterrupt = nil
                    end
                end)
                break
            end
        end
    end
    
    -- Check for raid tools
    if wantsRaidTool then
        for _, toolID in ipairs(OxedHub.CONFIG.RAID_TOOL_SPELLS) do
            if spellID == toolID then
                OxedHub.Triggers:ProcessEvent("RAID_TOOL", {
                    spellID = spellID,
                    unit = unit,
                })
                break
            end
        end
    end
    
    -- General spell cast
    -- Deduplicate: reticle spells (Death and Decay, etc.) fire this event twice.
    local now = GetTime()
    local lastCast = recentSpellCasts[spellID]
    if lastCast and (now - lastCast) < SPELL_CAST_DEDUP_WINDOW then
        return
    end
    recentSpellCasts[spellID] = now

    -- Skip if this spell was recently triggered via macro (prevents double-fire).
    -- Reticle spells (Death and Decay etc.) can take several seconds to place.
    local manual = OxedHub._manualSpellTrigger
    if manual and manual.spellID == spellID and (now - manual.time) < 5.0 then
        OxedHub._manualSpellTrigger = nil
        return
    end

    if wantsSpellcast then
        -- Pass the name too: spells often exist under several ids (Avenging
        -- Wrath is 31884 on the player but 231895 in the spell database), so an
        -- id-only comparison misses. Triggers:ShouldTrigger falls back to
        -- matching on name when the ids differ.
        local castName
        if C_Spell and C_Spell.GetSpellName then
            local okName, name = pcall(C_Spell.GetSpellName, spellID)
            if okName then castName = name end
        end

        OxedHub.Triggers:ProcessEvent("UNIT_SPELLCAST_SUCCEEDED", {
            spellID = spellID,
            spellName = castName,
            unit = unit,
        })
    end
end

-- Resurrect request handler
function Core:OnResurrectRequest()
    OxedHub.Triggers:ProcessEvent("RESURRECT_REQUEST", {
        inCombat = IsInCombatLockdown(),
    })
end

-- Encounter start handler
function Core:OnEncounterStart(encounterID, encounterName, difficultyID, groupSize)
    OxedHub.Triggers:ProcessEvent("ENCOUNTER_START", {
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize,
    })
end

-- Encounter end handler
function Core:OnEncounterEnd(encounterID, encounterName, difficultyID, groupSize, success)
    OxedHub.Triggers:ProcessEvent("ENCOUNTER_END", {
        encounterID = encounterID,
        encounterName = encounterName,
        wipe = (success == 0 or success == false),
    })
end

-- Boss kill handler
function Core:OnBossKill(encounterID, encounterName, difficultyID, groupSize)
    OxedHub.Triggers:ProcessEvent("BOSS_KILL", {
        encounterID = encounterID,
        encounterName = encounterName,
        difficultyID = difficultyID,
        groupSize = groupSize
    })
end

-- Blizzard blocks addon chat while a Mythic+ run is active
-- (Enum.AddOnRestrictionType.ChallengeMode). Returns false while that applies.
function OxedHub:CanSendAutomatedChat()
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
        and Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.ChallengeMode then
        local ok, restricted = pcall(C_RestrictedActions.IsAddOnRestrictionActive,
            Enum.AddOnRestrictionType.ChallengeMode)
        if ok and restricted then
            return false
        end
    end
    return true
end

function Core:OnChallengeModeCompleted()
    -- Wait a moment so Blizzard's Mythic+ addon restriction has lifted before
    -- any chat action fires; otherwise the message is silently dropped.
    C_Timer.After(1, function()
        OxedHub.Triggers:ProcessEvent("CHALLENGE_MODE_COMPLETED", {})
    end)
end

function Core:BuildSummonEventData(state)
    local pending = self.pendingSummonInfo or {}
    return {
        summonState = state,
        summoner = pending.summoner,
        areaName = pending.areaName,
        timeLeft = pending.timeLeft,
        inCombat = IsInCombatLockdown(),
    }
end

function Core:OnSummonIncoming()
    self.pendingSummonInfo = {
        summoner = GetSummonConfirmSummoner and GetSummonConfirmSummoner() or nil,
        areaName = GetSummonConfirmAreaName and GetSummonConfirmAreaName() or nil,
        timeLeft = GetSummonConfirmTimeLeft and GetSummonConfirmTimeLeft() or nil,
    }

    OxedHub.Triggers:ProcessEvent("SUMMON", self:BuildSummonEventData("incoming"))
end

function Core:OnSummonAccepted()
    OxedHub.Triggers:ProcessEvent("SUMMON", self:BuildSummonEventData("accepted"))
    self.pendingSummonInfo = nil
end

function Core:OnSummonDeclined()
    OxedHub.Triggers:ProcessEvent("SUMMON", self:BuildSummonEventData("declined"))
    self.pendingSummonInfo = nil
end

function Core:InstallSummonHooks()
    if summonHooksInstalled then
        return
    end
    summonHooksInstalled = true

    if hooksecurefunc and ConfirmSummon then
        hooksecurefunc("ConfirmSummon", function()
            if OxedHub and OxedHub.Core then
                OxedHub.Core:OnSummonAccepted()
            end
        end)
    end

    if hooksecurefunc and CancelSummon then
        hooksecurefunc("CancelSummon", function()
            if OxedHub and OxedHub.Core then
                OxedHub.Core:OnSummonDeclined()
            end
        end)
    end
end

-- Achievement earned handler
function Core:OnAchievementEarned(achievementID)
    if not self:HasEnabledTrigger("ACHIEVEMENT") then
        return
    end

    OxedHub.Triggers:ProcessEvent("ACHIEVEMENT", {
        achievementID = achievementID,
    })
end

-- Control lost handler (upgraded with C_LossOfControl support)
function Core:OnPlayerControlLost(event)
    C_Timer.After(0.5, function()
        if UnitOnTaxi("player") then
            self.wasOnTaxi = true
        end
    end)

    if not self:HasEnabledTrigger("CONTROL_LOST") then
        return
    end

    local data = {
        event = event or "PLAYER_CONTROL_LOST"
    }

    -- Try to get specific LoC data if available (WoW 10.0+)
    if C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount then
        local ok, count = pcall(C_LossOfControl.GetActiveLossOfControlDataCount)
        if ok and count and count > 0 then
            local okData, locData = pcall(C_LossOfControl.GetActiveLossOfControlData, 1)
            if okData and locData then
                data.spellID = locData.spellID
                data.spellName = locData.displayText or locData.text
                data.icon = locData.iconTexture or locData.icon
                data.duration = locData.duration
                data.timeRemaining = locData.timeRemaining
                data.locType = locData.locType
            end
        end
    end

    OxedHub.Triggers:ProcessEvent("CONTROL_LOST", data)
end

-- Control regained handler
function Core:OnPlayerControlGained()
    if self.wasOnTaxi then
        C_Timer.After(0.5, function()
            if not UnitOnTaxi("player") then
                self.wasOnTaxi = false
                if self:HasEnabledTrigger("REACH_FLY_DESTINATION") then
                    OxedHub.Triggers:ProcessEvent("REACH_FLY_DESTINATION", {})
                end
            end
        end)
    end

    if not self:HasEnabledTrigger("CONTROL_GAINED") then
        return
    end

    OxedHub.Triggers:ProcessEvent("CONTROL_GAINED", {})
end

function Core:OnPlayerLevelUp(level)
    if not self:HasEnabledTrigger("PLAYER_LEVEL_UP") then
        return
    end
    OxedHub.Triggers:ProcessEvent("PLAYER_LEVEL_UP", { level = level })
end

function Core:OnNewMail()
    -- UPDATE_PENDING_MAIL fires on login/reload with whatever mail is already
    -- sitting in the mailbox, so firing on every event announced old mail every
    -- time. Only fire on the transition from "no mail" to "mail waiting", and
    -- treat the first check of a session as a baseline.
    local okMail, hasMail = pcall(HasNewMail)
    hasMail = okMail and hasMail and true or false

    if self.hadPendingMail == nil then
        self.hadPendingMail = hasMail
        return
    end

    local isNewMail = hasMail and not self.hadPendingMail
    self.hadPendingMail = hasMail

    if not isNewMail then
        return
    end

    if not self:HasEnabledTrigger("NEW_MAIL") then
        return
    end
    OxedHub.Triggers:ProcessEvent("NEW_MAIL", {})
end

function Core:OnPartyMemberHealth(unit)
    if not self:HasEnabledTrigger("PARTY_MEMBER_DEATH") then
        return
    end

    self.deadPartyMembers = self.deadPartyMembers or {}
    
    local isDead = UnitIsDeadOrGhost(unit)
    if isDead and not self.deadPartyMembers[unit] then
        self.deadPartyMembers[unit] = true
        local unitName = UnitName(unit)
        if unitName then
            OxedHub.Triggers:ProcessEvent("PARTY_MEMBER_DEATH", { unitName = unitName })
        end
    elseif not isDead and self.deadPartyMembers[unit] then
        self.deadPartyMembers[unit] = false
    end
end

-- Cooldown Ready detection.
--
-- In WoW 12.0 (Midnight) the live cooldown start/duration from
-- C_Spell.GetSpellCooldown are "secret values" that addons cannot read, so we
-- can't time the cooldown ourselves (the old SPELL_UPDATE_COOLDOWN approach
-- always saw 0 and never fired). Instead, when the watched spell is cast we
-- hand the (secret) cooldown straight to a hidden Cooldown widget and let its
-- OnCooldownDone callback tell us the exact moment it finishes.

-- True if an enabled CD_READY trigger is watching this spellID.
function Core:IsCooldownReadyWatched(spellID)
    local triggers = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers
    if not triggers then return false end
    for _, trigger in pairs(triggers) do
        if trigger.event == "CD_READY" and trigger.enabled and trigger.conditions then
            local c = trigger.conditions
            if c.spellID and tonumber(c.spellID) == spellID then
                return true
            end
            if c.extraSpellIDs then
                for _, sid in ipairs(c.extraSpellIDs) do
                    if tonumber(sid) == spellID then return true end
                end
            end
        end
    end
    return false
end

-- Arm cooldown-ready tracking for a freshly-cast watched spell.
--
-- We cannot read the secret start/duration, but C_Spell.GetSpellCooldown's
-- `isActive` field is a plain (non-secret) boolean, so we poll it: when it goes
-- from true -> false the cooldown has finished and we fire CD_READY. This works
-- regardless of haste/CDR and never touches a secret value.
function Core:ArmCooldownReady(spellID)
    if not spellID then return end
    if not self:IsCooldownReadyWatched(spellID) then return end

    -- Base cooldown (ms) is static/non-secret: filters GCD-only spells and caps polling.
    local baseMs = 0
    if GetSpellBaseCooldown then
        local ok, b = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(b) == "number" then baseMs = b end
    end
    if baseMs > 0 and baseMs <= 1500 then return end  -- global cooldown only

    self.cdReadyTickers = self.cdReadyTickers or {}
    if self.cdReadyTickers[spellID] then
        self.cdReadyTickers[spellID]:Cancel()
        self.cdReadyTickers[spellID] = nil
    end

    local interval = 0.25
    local elapsed = 0
    local maxTime = (baseMs > 0 and (baseMs / 1000) or 60) + 5  -- hard safety cap
    local sawActive = false

    if Core.debugCD then print("|cffff8800[OxedHub-CD]|r polling "..tostring(spellID).." (base "..tostring(baseMs).."ms)") end

    self.cdReadyTickers[spellID] = C_Timer.NewTicker(interval, function(ticker)
        elapsed = elapsed + interval

        local cdInfo = C_Spell.GetSpellCooldown(spellID)
        -- isActive is a plain bool; reading it is safe (we never touch start/duration)
        local active = cdInfo and cdInfo.isActive and true or false
        if active then sawActive = true end

        -- Fire when the cooldown clears (past the GCD window), or as a fallback
        -- if we somehow exceed the expected duration.
        if (sawActive and not active and elapsed > 1.6) or (elapsed >= maxTime) then
            ticker:Cancel()
            Core.cdReadyTickers[spellID] = nil
            if Core.debugCD then print("|cffff8800[OxedHub-CD]|r FIRING CD_READY for "..tostring(spellID)) end
            OxedHub.Triggers:ProcessEvent("CD_READY", { spellID = spellID })
        end
    end)
end

-- Live cooldown numbers are secret in 12.0, so SPELL_UPDATE_COOLDOWN cannot be
-- used to detect cooldown completion. CD_READY is armed on cast instead.
function Core:OnSpellCooldownUpdate()
end

-- Unit pet handler (for pet abilities)
function Core:OnUnitPet(unit)
    if unit ~= "player" then return end
    
    -- Check for Primal Rage from pet
    if UnitExists("pet") then
        -- Pet abilities would be handled by UNIT_SPELLCAST_SUCCEEDED
    end
end

-- Slash commands
function Core:RegisterSlashCommands()
    SLASH_OXEDHUB1 = "/oxedhub"
    SLASH_OXEDHUB2 = "/ohub"
    SLASH_OXEDHUB3 = "/oxed"
    SlashCmdList["OXEDHUB"] = function(msg)
        Core:HandleSlashCommand(msg)
    end
end

-- Handle slash commands
function Core:HandleSlashCommand(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = (command or ""):lower()
    
    if command == "" or command == "open" or command == "toggle" then
        if OxedHub.UI then
            OxedHub.UI:ToggleMainWindow()
        end
    elseif command == "dock" or command == "toybox" or command == "toydock" then
        if OxedHub.Toys and OxedHub.Toys.ToggleToyDock then
            OxedHub.Toys:ToggleToyDock(rest ~= "" and rest or nil)
        end
    elseif command == "toydebug" then
        if OxedHub.Toys and OxedHub.Toys.DumpToyButtons then
            OxedHub.Toys:DumpToyButtons()
        end
    elseif command == "whatsnew" or command == "news" or command == "changelog" then
        -- Opened by hand, so show the full history rather than only what is new
        -- since the last version the player saw.
        if OxedHub.WhatsNew then
            OxedHub.WhatsNew:Show(true)
        end
    elseif command == "reload" or command == "rl" then
        ReloadUI()
    elseif command == "trigger" then
        if rest == "list" then
            print("|cff00ff00Oxed Hub Triggers:|r")
            for id, trigger in pairs(OxedHub.db.profile.triggers) do
                local status = trigger.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                print("  " .. status .. " " .. (trigger.name or id))
            end
        end
    elseif command == "emotion" or command == "emote" then
        if rest and rest ~= "" then
            OxedHub.EmotionRing:TriggerEmotion(rest)
        else
            print("Usage: /oxedhub emotion <emotion_name>")
        end
    elseif command == "mix" then
        if OxedHub.MacroRegistry then
            OxedHub.MacroRegistry:SlashHandler(rest)
        end
    elseif command == "debug" then
        OxedHub.debug = not OxedHub.debug
        print("|cff00ff00[OxedHub]|r General & Trigger debug logging " .. (OxedHub.debug and "|cff00ff00ENABLED|r" or "|cffff0000DISABLED|r"))
        if OxedHub.Toys then
            OxedHub.Toys.debug = OxedHub.debug
        end
    elseif command == "auratest" then
        -- Ground-truth probe: can we detect a given aura by spell ID right now?
        -- Run it in combat WITH the buff up to settle the "secret in combat" question.
        local sid = tonumber(rest)
        if not sid then
            print("|cffff0000[OxedHub]|r Usage: /oxedhub auratest <spellID>   (run in combat with the buff active)")
        else
            local inCombat = InCombatLockdown()
            print(("|cff00ff00[AuraTest]|r spellID=%d  inCombat=%s"):format(sid, tostring(inCombat)))
            -- 1) targeted existence API
            local ok1, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
            print(("  GetPlayerAuraBySpellID: pcallOK=%s  returnedNil=%s"):format(tostring(ok1), tostring(aura == nil)))
            if ok1 and aura then
                -- try to read a couple of fields to see if they are secret
                local okName = pcall(function() return "" .. tostring(aura.name) end)
                local okApps = pcall(function() return (aura.applications or 0) + 0 end)
                print(("    aura present! nameReadable=%s applicationsReadable=%s"):format(tostring(okName), tostring(okApps)))
            end
            -- 2) AuraUtil name/index fallback
            if AuraUtil and AuraUtil.FindAuraByName then
                local sName = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sid)
                sName = sName and sName.name
                if sName then
                    local ok2, found = pcall(AuraUtil.FindAuraByName, sName, "player", "HELPFUL")
                    print(("  AuraUtil.FindAuraByName('%s'): pcallOK=%s found=%s"):format(tostring(sName), tostring(ok2), tostring(found ~= nil)))
                end
            end
            -- 3) native registration API availability
            print(("  API present: AddAuraSound=%s AddAuraAppliedSound=%s  AddPrivateAuraAppliedSound=%s"):format(
                tostring(C_UnitAuras and C_UnitAuras.AddAuraSound ~= nil),
                tostring(C_UnitAuras and C_UnitAuras.AddAuraAppliedSound ~= nil),
                tostring(C_UnitAuras and C_UnitAuras.AddPrivateAuraAppliedSound ~= nil)))
        end
    elseif command == "help" then
        print("|cff00ff00Oxed Hub Commands:|r")
        print("  /oxedhub or /ohub - Toggle main window")
        print("  /oxedhub reload - Reload UI")
        print("  /oxedhub trigger list - List all triggers")
        print("  /oxedhub emotion <name> - Trigger an emotion")
        print("  /oxedhub mix list - List saved mixes")
        print("  /oxedhub mix run <name> - Run a mix")
        print("  /oxedhub debug - Toggle toy/mix macro debug logging")
        print("  /oxedhub help - Show this help")
    else
        print("Unknown command. Type |cffffff00/oxedhub help|r for available commands.")
    end
end

-- Initialize the core module
Core:Init()
-- Pet event handler
function Core:OnPetEvent()
    local needsPetTrigger = self:HasEnabledTrigger("PET_SUMMONED")
        or self:HasEnabledTrigger("PET_DIED")
        or self:HasEnabledTrigger("PET_DISMISSED")
    if not needsPetTrigger then
        return
    end

    if previousPetState == nil then
        previousPetState = GetPetState()
        return
    end

    local newState = GetPetState()
    
    if newState == "alive" and previousPetState ~= "alive" then
        OxedHub.Triggers:ProcessEvent("PET_SUMMONED", {
            unit = "pet"
        })
    elseif newState == "dead" and previousPetState == "alive" then
        OxedHub.Triggers:ProcessEvent("PET_DIED", {
            unit = "pet"
        })
    elseif newState == "none" and previousPetState == "alive" then
        OxedHub.Triggers:ProcessEvent("PET_DISMISSED", {
            unit = "pet"
        })
    end
    
    previousPetState = newState
end

-- Check if a spell is relevant to the current player's class/kit
function OxedHub:IsSpellRelevant(spellID)
    if not spellID then return true end
    local sid = tonumber(spellID)
    if not sid then return true end
    
    -- Check if spell is known by player or pet
    -- Use robust checking since global APIs vary by WoW version
    local isKnown = false
    if IsPlayerSpell and IsPlayerSpell(sid) then
        isKnown = true
    elseif IsSpellKnown and IsSpellKnown(sid) then
        isKnown = true
    elseif IsSpellKnown and IsSpellKnown(sid, true) then -- Pet spell
        isKnown = true
    elseif C_Spell and C_Spell.IsSpellKnown and C_Spell.IsSpellKnown(sid) then
        isKnown = true
    end

    if isKnown then
        return true
    end

    -- Check if it's a general/racial/item spell that everyone might have
    -- For now, if it's NOT known, we assume it's filtered if the setting is on.
    return false
end

-- ─────────────────────────────────────────────────────────────────────────
-- PvP kill tracking (PVP_KILL / PVP_MULTIKILL / PVP_SPREE).
--
-- WoW 12.0 removed COMBAT_LOG_EVENT_UNFILTERED for addons, so kills come from
-- the standalone PARTY_KILL event. In instanced PvP the GUIDs are "secret"
-- values, so we fall back to watching the honorable-kill achievement counter
-- to tell whether the killing blow was ours.
-- ─────────────────────────────────────────────────────────────────────────
local PVP_MULTIKILL_WINDOW = 10   -- seconds between kills to count as a multi-kill
local PVP_SPREE_TIMEOUT = 60      -- seconds of no kills before a streak lapses
local PVP_MULTIKILL_TIERS = { 4, 3, 2 }        -- checked high → low
local PVP_SPREE_TIERS = { 20, 15, 10, 5 }

local pvpState = { killStreak = 0, lastKillTime = 0, kills = {}, baselineKills = nil }

local function GetHonorableKillCount()
    local ok, count = pcall(function()
        -- Achievement 1487 = "Honorable Kills"; criteria 0 holds the running total.
        local _, _, _, _, _, _, _, _, killCount = GetAchievementCriteriaInfoByID(1487, 0)
        return killCount
    end)
    return (ok and tonumber(count)) or 0
end

local function IsSecretValue(v)
    return issecretvalue and issecretvalue(v) or false
end

function Core:ResetPvPStreak()
    pvpState.killStreak = 0
    pvpState.kills = {}
end

function Core:InitPvPKillBaseline()
    pvpState.baselineKills = GetHonorableKillCount()
end

-- True only in instanced PvP, where every kill really is a player kill and the
-- GUIDs are hidden from us.
local function InInstancedPvP()
    local ok, instanceType = pcall(function()
        local _, t = IsInInstance()
        return t
    end)
    if not ok then return false end
    return instanceType == "pvp" or instanceType == "arena"
end

-- Did we land this killing blow, and was the victim a player?
local function IsOurPlayerKill(attackerGUID, targetGUID)
    -- Victim check. A hidden GUID used to be treated as proof of instanced PvP,
    -- but 12.0 hides GUIDs across all instanced content, so every raid and
    -- dungeon NPC passed this check and the PvP triggers fired on trash.
    -- Hidden GUIDs now only count inside an actual battleground or arena.
    local targetIsPlayer
    if IsSecretValue(targetGUID) then
        targetIsPlayer = InInstancedPvP()
    else
        local ok, found = pcall(function()
            return targetGUID and tostring(targetGUID):find("^Player%-") ~= nil
        end)
        targetIsPlayer = ok and found or false
    end
    if not targetIsPlayer then return false end

    -- Attacker check: compare GUIDs when we can see them, otherwise watch our
    -- honorable-kill total for an increase.
    if IsSecretValue(attackerGUID) then
        local current = GetHonorableKillCount()
        -- No baseline yet means achievement data was not ready when we asked.
        -- Adopt the current total and skip this kill: comparing against a stale
        -- or zero baseline is what made the trigger fire on an unrelated kill
        -- once the real total finally loaded.
        if not pvpState.baselineKills then
            pvpState.baselineKills = current
            return false
        end
        if current > pvpState.baselineKills then
            pvpState.baselineKills = current
            return true
        end
        return false
    end

    local ok, isUs = pcall(function() return attackerGUID == UnitGUID("player") end)
    return ok and isUs or false
end

function Core:OnPartyKill(attackerGUID, targetGUID)
    if not (self:HasEnabledTrigger("PVP_KILL")
        or self:HasEnabledTrigger("PVP_MULTIKILL")
        or self:HasEnabledTrigger("PVP_SPREE")) then
        return
    end
    if not IsOurPlayerKill(attackerGUID, targetGUID) then return end

    local now = GetTime()

    -- A long gap since the last kill ends the streak.
    if pvpState.lastKillTime > 0 and (now - pvpState.lastKillTime) > PVP_SPREE_TIMEOUT then
        self:ResetPvPStreak()
    end
    pvpState.lastKillTime = now
    pvpState.killStreak = pvpState.killStreak + 1
    table.insert(pvpState.kills, now)

    -- Drop kills that fell out of the multi-kill window.
    while #pvpState.kills > 0 and (now - pvpState.kills[1]) > PVP_MULTIKILL_WINDOW do
        table.remove(pvpState.kills, 1)
    end
    local multiKill = #pvpState.kills

    local eventData = { killStreak = pvpState.killStreak, multiKill = multiKill }

    OxedHub.Triggers:ProcessEvent("PVP_KILL", eventData)

    -- Multi-kill: report the highest tier this kill reached.
    for _, tier in ipairs(PVP_MULTIKILL_TIERS) do
        if multiKill >= tier then
            OxedHub.Triggers:ProcessEvent("PVP_MULTIKILL", {
                killStreak = pvpState.killStreak, multiKill = multiKill, tier = tier,
            })
            break
        end
    end

    -- Spree: only on the kill that actually hits the milestone, so a 12-kill
    -- streak doesn't keep re-firing "Dominating" on every subsequent kill.
    for _, tier in ipairs(PVP_SPREE_TIERS) do
        if pvpState.killStreak == tier then
            OxedHub.Triggers:ProcessEvent("PVP_SPREE", {
                killStreak = pvpState.killStreak, multiKill = multiKill, tier = tier,
            })
            break
        end
    end
end

-- Group / party events. These map straight onto the Blizzard events; the only
-- extra data worth passing along is who sent a party invite.
function Core:OnGroupEvent(event, ...)
    if not self:HasEnabledTrigger(event) then
        return
    end

    local eventData = {}
    if event == "PARTY_INVITE_REQUEST" then
        local inviter = ...
        eventData.inviter = inviter
        eventData.playerName = inviter
    end

    OxedHub.Triggers:ProcessEvent(event, eventData)
end

-- Enter / leave combat handler. state is "enter" or "exit".
function Core:OnCombatStateChanged(state)
    if not self:HasEnabledTrigger("COMBAT_STATE") then
        return
    end
    OxedHub.Triggers:ProcessEvent("COMBAT_STATE", {
        combatState = state,
    })
end

-- Spell Interrupted handler
function Core:OnSpellInterrupted(unit, castGUID, spellID)
    local wantsSpellInterrupted = self:HasEnabledTrigger("SPELL_INTERRUPTED")
    local wantsInterrupt = self:HasEnabledTrigger("INTERRUPT_USED")
    if not wantsSpellInterrupted and not wantsInterrupt then
        return
    end

    if wantsSpellInterrupted and unit == "player" then
        OxedHub.Triggers:ProcessEvent("SPELL_INTERRUPTED", {
            spellID = spellID,
            unit = unit
        })
        return
    end

    -- Detect our interrupt landing on the target via UNIT_SPELLCAST_INTERRUPTED
    if wantsInterrupt and pendingInterrupt then
        local guid = UnitGUID(unit)
        local matchesPendingTarget = SafeUnitMatch(unit, pendingInterrupt.targetUnit)

        if not matchesPendingTarget and guid and pendingInterrupt.targetGUID then
            local ok, sameGuid = pcall(function()
                return guid == pendingInterrupt.targetGUID
            end)
            matchesPendingTarget = ok and sameGuid or false
        end

        if matchesPendingTarget then
            local sid = pendingInterrupt.spellID
            pendingInterrupt = nil
            OxedHub.Triggers:ProcessEvent("INTERRUPT_USED", {
                spellID = sid,
                result = "success",
            })
        end
    end
end

-- Helper to recursively apply font to all text regions within a menu/frame hierarchy
local function TraverseFrameAndApplyFont(frame, font)
    if not frame or not frame.GetRegions then return end
    local regions = { frame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:IsObjectType("FontString") then
            local fontPath, size, flags = region:GetFont()
            if fontPath ~= font then
                if not size or size <= 0 then size = 12 end
                region:SetFont(font, size, flags)
            end
        end
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            TraverseFrameAndApplyFont(child, font)
        end
    end
end

-- Hook StaticPopup_Show to apply dynamic font for any OxedHub dialogs
hooksecurefunc("StaticPopup_Show", function(which)
    if which and string.find(which, "^OXEDHUB_") then
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.language == "arAR" then
            C_Timer.After(0.01, function()
                for i = 1, STATICPOPUP_NUMDIALOGS or 4 do
                    local dialog = _G["StaticPopup"..i]
                    if dialog and dialog:IsShown() and dialog.which == which then
                        local font = OxedHub:GetFont()
                        if font then
                            TraverseFrameAndApplyFont(dialog, font)
                        end
                    end
                end
            end)
        end
    end
end)

-- Hook GameTooltip and ItemRefTooltip to apply dynamic font for Arabic locale
local function ApplyFontToTooltip(self)
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.language == "arAR" then
        local font = OxedHub:GetFont()
        if font then
            TraverseFrameAndApplyFont(self, font)
        end
    end
end

if GameTooltip then
    GameTooltip:HookScript("OnShow", ApplyFontToTooltip)
    GameTooltip:HookScript("OnUpdate", ApplyFontToTooltip)
end
if ItemRefTooltip then
    ItemRefTooltip:HookScript("OnShow", ApplyFontToTooltip)
    ItemRefTooltip:HookScript("OnUpdate", ApplyFontToTooltip)
end

-- Deprecated (replaced by TraverseFrameAndApplyFont)
local function TraverseMenuAndApplyFont(frame, font)
    TraverseFrameAndApplyFont(frame, font)
end

-- Hook new Retail Menu system dropdowns
if Menu and Menu.ModifyMenu and MenuInputContext and MenuInputContext.OnShow then
    Menu.ModifyMenu("*", function(owner, rootDescription, contextData)
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.language == "arAR" then
            rootDescription:RegisterCallback(MenuInputContext.OnShow, function(menu)
                local font = OxedHub:GetFont()
                if font and menu.GetFrame then
                    local frame = menu:GetFrame()
                    if frame then
                        TraverseMenuAndApplyFont(frame, font)
                    end
                end
            end)
        end
    end)
end

-- Hook UIDropDownMenu system via ToggleDropDownMenu
if ToggleDropDownMenu then
    hooksecurefunc("ToggleDropDownMenu", function(...)
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.language == "arAR" then
            C_Timer.After(0.01, function()
                local font = OxedHub:GetFont()
                if font then
                    for i = 1, UIDROPDOWNMENU_MAXLEVELS or 2 do
                        local listFrame = _G["DropDownList"..i]
                        if listFrame and listFrame:IsShown() then
                            TraverseFrameAndApplyFont(listFrame, font)
                        end
                    end
                end
            end)
        end
    end)
end
