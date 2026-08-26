local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────
-- BLOODLUST trigger — fires when the haste buff lands on YOU.
--
-- Why this doesn't use the normal SELF_AURA path: in combat WoW marks aura data
-- as "secret", so the generic aura scanner can't read spell IDs off the player
-- and only notices the buff once combat ends (the "it played after the fight"
-- problem). C_UnitAuras.GetPlayerAuraBySpellID can still be asked about ONE
-- specific spell id though — we only need to know whether it returned anything,
-- never read its fields — so polling the known lust ids works mid-combat.
--
-- eventData.spellID / spellName identify which version landed.
-- ─────────────────────────────────────────────────────────────────────────

-- Buff ids granted by every source of the 30% haste burst.
local LUST_BUFFS = {
    -- Helpful Buffs
    2825,     -- Bloodlust (Shaman, Horde)
    32182,    -- Heroism (Shaman, Alliance)
    80353,    -- Time Warp (Mage)
    390386,   -- Fury of the Aspects (Evoker)
    264667,   -- Primal Rage (Hunter pet)
    90355,    -- Ancient Hysteria (Core Hound)
    160452,   -- Netherwinds (Nether Ray)
    381301,   -- Feral Hide Drums
    230935,   -- Drums of the Mountain
    256740,   -- Drums of the Maelstrom
    309658,   -- Drums of Deathly Ferocity
    466904,   -- Drums of War
    
    -- Harmful Debuffs (Sated/Exhaustion) - Used for combat detection since debuffs are less restricted
    57724,    -- Sated (Bloodlust)
    57723,    -- Exhaustion (Heroism)
    80354,    -- Temporal Displacement (Time Warp)
    390435,   -- Exhaustion (Fury of the Aspects)
    264689,   -- Fatigued (Primal Rage)
}

-- Returns the id of whichever lust buff is on the player, or nil.
-- Existence only: the aura table's contents are secret in combat, so nothing
-- inside it is ever read.
local function GetActiveLustBuff()
    if not C_UnitAuras then return nil end
    local function checkBuffs(spellID)
        if C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if ok and aura then return true end
        end
        local Core = OxedHub.Core
        if Core and Core.activeSpellIDs and Core.activeSpellIDs[spellID] then
            return true
        end
        if C_UnitAuras.GetAuraDataBySpellID then
            local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellID, "player", spellID)
            if ok and aura then return true end
        end
        return false
    end

    for _, spellID in ipairs(LUST_BUFFS) do
        if checkBuffs(spellID) then
            return spellID
        end
    end
    return nil
end

Triggers:RegisterEventType("BLOODLUST", {
    name = L["EVT_BLOODLUST"] or "Bloodlust / Heroism",
    CheckCondition = function()
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        info:SetWidth(560)
        info:SetJustifyH("LEFT")
        info:SetText(L["BLOODLUST_DESC"]
            or "Fires the moment Bloodlust, Heroism, Time Warp, Primal Rage,\n"
            .. "Fury of the Aspects or a drum buff lands on you — including\n"
            .. "during combat.")
        return yOffset - 40
    end,
})

local watcher = CreateFrame("Frame")
local activeBuff = nil          -- id currently on the player, nil when none
local pollTicker = nil

local function CheckLust()
    -- Nothing to fire into until the profile is loaded.
    if not (OxedHub.db and OxedHub.db.profile) then return end

    local current = GetActiveLustBuff()

    if current and not activeBuff then
        activeBuff = current
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(current)
        local spellName = info and info.name

        if OxedHub.debug then
            print(("|cff00ffff[OxedHub-Debug]|r BLOODLUST buff gained: %s (%d)")
                :format(tostring(spellName), current))
        end

        Triggers:ProcessEvent("BLOODLUST", {
            spellID = current,
            spellName = spellName,
        })
    elseif not current and activeBuff then
        activeBuff = nil
    end
end

-- UNIT_AURA still fires in combat even though the payload is secret, so it's
-- the cheapest signal. The ticker is a safety net for the cases where the event
-- is throttled or the aura appears between updates.
local function StartPolling()
    if pollTicker then return end
    pollTicker = C_Timer.NewTicker(0.25, CheckLust)
end

local function StopPolling()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

watcher:RegisterUnitEvent("UNIT_AURA", "player")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Don't announce a lust that was already running when we loaded.
        activeBuff = GetActiveLustBuff()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        StartPolling()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        -- Keep polling briefly: lust often outlives the pull, and stopping dead
        -- on combat end would leave activeBuff stale for the next fight.
        C_Timer.After(5, function()
            if not InCombatLockdown() then
                StopPolling()
                CheckLust()
            end
        end)
        return
    end

    CheckLust()
end)

-- Seed state at load WITHOUT firing: calling ProcessEvent here would run before
-- the database exists and abort this file, taking every module loaded after it
-- down with it. PLAYER_ENTERING_WORLD re-seeds properly.
activeBuff = GetActiveLustBuff()
