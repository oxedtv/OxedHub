-- ============================================================================
-- Trash Timers (built-in OxedHub module)
-- Cooldowns of the dangerous trash in this season's dungeons: when a pack is
-- pulled, each of its mobs' abilities gets a timer, its first cast and then
-- every cooldown after it, from TrashData.
--
-- It draws nothing itself. The timers are handed to BossEngine as events of
-- their own, so they show wherever boss abilities show: Boss Timers' bars,
-- Boss Alerts' countdown, Boss Track. Switch on any of those to see them;
-- each ability has its own settings in Boss Timers' abilities window, under
-- the dungeon's "Trash".
--
-- ⚠ In a fight an enemy's identity (its GUID, so its npc id) is a secret
-- value. So mobs are recognised by their nameplate *before* the pull, when
-- it can still be read, and the pull counts every recognised enemy around
-- you. That makes these timers an estimate: they start at the pull and are
-- not corrected by what the mobs actually cast. A mob type stops being
-- timed once all of its recognised nameplates are gone.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on
    keystoneOnly = false,  -- only in Mythic+ keystones
    maxAhead    = 30,      -- do not list a cast further ahead than this
}

local Engine = OxedHub.BossEngine
local settings
local optionsWindow
local active = false
local eventFrame = CreateFrame("Frame")

local plates = {}        -- [unit] = npc id, read while it could be
local pulled = {}        -- [npc id] = how many recognised plates are left
local timers = {}        -- [key] = C_Timer handle
local dungeon            -- this dungeon's TrashData row

local function NpcID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or (issecretvalue and issecretvalue(guid)) or guid == nil then return nil end
    local id = select(6, strsplit("-", guid))
    return tonumber(id)
end

local function FindDungeon()
    dungeon = nil
    local data = OxedHub.TrashData
    if not data then return end
    local keystone = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID
        and C_ChallengeMode.GetActiveChallengeMapID()
    if keystone and data[keystone] then dungeon = data[keystone]; return end
    if settings.keystoneOnly then return end
    local instanceID = select(8, GetInstanceInfo())
    for _, row in pairs(data) do
        if row.instance == instanceID then dungeon = row; return end
    end
end

-- ── Scheduling ─────────────────────────────────────────────────────────────

local function Key(npc, spell) return npc .. ":" .. spell end

local function Cancel(key)
    if timers[key] then timers[key]:Cancel(); timers[key] = nil end
    Engine:RemoveCustomEvent(key)
end

-- Puts the next cast of a spell on the engine and, when it is due, the one
-- after. turn counts the casts so the cooldown list is used in order.
local function Schedule(npc, spellID, info, seconds, turn)
    local key = Key(npc, spellID)
    if seconds > settings.maxAhead then
        -- Too far ahead to list yet: come back when it is close enough.
        timers[key] = C_Timer.NewTimer(seconds - settings.maxAhead, function()
            timers[key] = nil
            if pulled[npc] then Schedule(npc, spellID, info, settings.maxAhead, turn) end
        end)
        return
    end
    local name = C_Spell.GetSpellName(spellID)
    if not name then return end
    Engine:AddCustomEvent({
        key = key, name = name, icon = C_Spell.GetSpellTexture(spellID), seconds = seconds,
        kind = info.kind, spell = spellID, encounterID = "trash", abilityID = spellID,
    })
    timers[key] = C_Timer.NewTimer(seconds, function()
        timers[key] = nil
        if not pulled[npc] then
            Engine:RemoveCustomEvent(key)
            return
        end
        local cds = info.cd
        local gap = cds and (cds[turn] or cds[#cds])
        if gap and gap > 0 then
            Schedule(npc, spellID, info, gap, turn + 1)
        else
            Engine:RemoveCustomEvent(key)
        end
    end)
end

local function StartMob(npc)
    local spells = dungeon and dungeon.mobs[npc]
    if not spells then return end
    for spellID, info in pairs(spells) do
        if info.first then
            Schedule(npc, spellID, info, info.first, 1)
        elseif info.cd and info.cd[1] then
            Schedule(npc, spellID, info, info.cd[1], 2)
        end
    end
end

local function StopMob(npc)
    pulled[npc] = nil
    local spells = dungeon and dungeon.mobs[npc]
    if not spells then return end
    for spellID in pairs(spells) do Cancel(Key(npc, spellID)) end
end

local function StopAll()
    for npc in pairs(pulled) do StopMob(npc) end
    for key in pairs(timers) do Cancel(key) end
    wipe(pulled)
end

-- ── Events ─────────────────────────────────────────────────────────────────

local function OnPull()
    FindDungeon()
    if not dungeon then return end
    local counts = {}
    for unit, npc in pairs(plates) do
        if dungeon.mobs[npc] then counts[npc] = (counts[npc] or 0) + 1 end
    end
    for npc, count in pairs(counts) do
        if not pulled[npc] then
            pulled[npc] = count
            StartMob(npc)
        else
            pulled[npc] = pulled[npc] + count
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local npc = NpcID(unit)
        if npc then plates[unit] = npc end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local npc = plates[unit]
        plates[unit] = nil
        if npc and pulled[npc] and InCombatLockdown() then
            pulled[npc] = pulled[npc] - 1
            if pulled[npc] <= 0 then StopMob(npc) end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnPull()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_START" then
        -- Out of the fight, or a boss: its own timeline takes over.
        StopAll()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" then
        StopAll()
        wipe(plates)
        FindDungeon()
    end
end)

local function Start()
    active = true
    Engine:Start()
    for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START" }) do
        eventFrame:RegisterEvent(e)
    end
    FindDungeon()
end

local function Stop()
    active = false
    eventFrame:UnregisterAllEvents()
    StopAll()
    wipe(plates)
    Engine:Stop()
end

-- For the abilities window: every trash spell of a dungeon, by instance id.
function OxedHub.TrashSpellsForInstance(instanceID)
    local data = OxedHub.TrashData
    if not data then return nil end
    for _, row in pairs(data) do
        if row.instance == instanceID then
            local spells = {}
            for _, list in pairs(row.mobs) do
                for spellID, info in pairs(list) do
                    spells[spellID] = { spell = spellID, kind = info.kind }
                end
            end
            return spells
        end
    end
    return nil
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Trash Timers", 460, 430)
        optionsWindow = w
        w:AddCheckbox(settings, "keystoneOnly", "Only in Mythic+ keystones", nil, FindDungeon)
        w:AddSlider(settings, "maxAhead", "List a cast once it is", 5, 60, 1, "%s: %d s away")
        w:AddNote("The timers show in Boss Timers, Boss Alerts and Boss Track: switch on at "
            .. "least one. Each ability can be switched off or given its own sound in Boss "
            .. "Timers' abilities window, under the dungeon's Trash. Timers start at the pull "
            .. "and are an estimate: the game hides which mob is which in a fight.")
        w:AddModuleLinks("Works together with", { "bosstimers", "bossalerts", "bosstrack", "enemycasts", "partyinterrupts", "kickbar", "bosshealth" })
    end
    optionsWindow:Show()
end

-- ── Settings and registration ──────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.trashtimers
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.trashtimers = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "trashtimers",
        name     = "Trash Timers",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "trash", "mythic", "keystone", "dungeon", "cooldown", "timer", "pack" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Cooldowns of dangerous dungeon trash after each pull, shown by the boss modules.",
        icon     = "Interface\\Icons\\INV_Relics_Hourglass",

        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
