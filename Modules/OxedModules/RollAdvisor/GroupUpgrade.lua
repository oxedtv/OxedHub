-- ============================================================================
-- Roll Advisor: upgrade % for everyone in the group
-- How much better or worse a dropped item is for each player who rolls on it,
-- next to their roll in "who rolled what". Off until the player switches it
-- on (settings.groupUpgrade).
--
-- For each player:
--   1. Their gear: yours from your character; anyone else's by inspecting
--      them, the way the game's Inspect does it: out of combat, in range, one
--      at a time, never while the Inspect window is open.
--   2. Their spec (Forever): from their group role, since the game does not
--      tell addons anyone's talents. A damage shaman or druid is caster or
--      melee by their gear.
--   3. A score: each stat times what that spec values it, plus weapon damage.
--      On the main game, where stats scale with item level, the score is the
--      item level.
-- Others' numbers carry a ~ (inspected gear, guessed spec). Where the game
-- hides group roles, others get no number in that instance.
--
-- Nothing here runs until Roll Advisor calls Start() from its OnEnable, and
-- the settings say so.
-- ============================================================================

local addonName, OxedHub = ...
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end

local Up = {}
OxedHub.RollGroupUpgrade = Up

local INSPECT_GAP  = 1.5   -- seconds between inspects
local INSPECT_WAIT = 4     -- seconds to wait for the answer before moving on
local GEAR_KEEP    = 600   -- seconds an inspected player's gear is trusted
local KEEP         = 5     -- seconds a worked-out number is kept
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 }

local settings
local running = false

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) if Secret(v) then return nil end return v end

-- A game function's answers, nil for a failure or a secret.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return Plain(a), Plain(b)
end

local function Now() return GetTime() end

local function BaseName(name)
    if type(name) ~= "string" or Secret(name) or name == "" then return nil end
    return (name:gsub("%-.*$", ""):match("^(%S+)"))
end

-- ── Stat weights (Forever) ──────────────────────────────────────────────────
-- What one point of each stat is worth to a spec, its main stat at 1. Rough
-- leveling values: good enough to tell an upgrade from a downgrade.

local MELEE  = { str = 1, agi = 0.6, sta = 0.3, ap = 0.5, armor = 0.005, dps = 4 }
local TANK   = { sta = 1, armor = 0.03, def = 1, str = 0.4, agi = 0.5, block = 0.3, ap = 0.1, dps = 1 }
local CASTER = { sp = 1, spdmg = 1, int = 0.7, spi = 0.3, sta = 0.4, mp5 = 0.5, armor = 0.002, rdps = 1 }
local HEALER = { int = 1, spi = 0.5, heal = 0.6, sp = 0.6, mp5 = 1.5, sta = 0.2, armor = 0.002, rdps = 0.5 }
local function With(base, changes)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(changes) do out[k] = v end
    return out
end
local WEIGHTS = {
    WARRIOR = { arms = MELEE, fury = MELEE, protection = TANK },
    PALADIN = {
        holy = With(HEALER, { spi = 0.2 }),
        protection = With(TANK, { int = 0.3, sp = 0.3, spdmg = 0.3 }),
        retribution = With(MELEE, { int = 0.2, sp = 0.2, spdmg = 0.2 }),
    },
    HUNTER  = { hunter = { agi = 1, rap = 0.45, ap = 0.1, int = 0.2, sta = 0.3, str = 0.05, armor = 0.005, rdps = 3, dps = 0.3 } },
    ROGUE   = { rogue = { agi = 1, str = 0.5, ap = 0.5, sta = 0.3, armor = 0.005, dps = 4 } },
    PRIEST  = { holy = With(HEALER, { spi = 0.8 }), shadow = With(CASTER, { spi = 0.6 }) },
    SHAMAN  = { elemental = CASTER, enhancement = With(MELEE, { int = 0.2 }), restoration = HEALER },
    MAGE    = { mage = CASTER },
    WARLOCK = { warlock = With(CASTER, { sta = 0.6, int = 0.5 }) },
    DRUID   = {
        balance = With(CASTER, { spi = 0.4 }),
        feral = { agi = 1, str = 1, ap = 0.5, fap = 0.5, sta = 0.3, armor = 0.01 },
        bear = { sta = 1, armor = 0.03, agi = 0.6, str = 0.4, def = 0.8, fap = 0.3 },
        restoration = With(HEALER, { spi = 0.8 }),
    },
}

local STAT_KEYS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "fap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spdmg",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_BLOCK_VALUE_SHORT = "block",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
    RESISTANCE0_NAME = "armor",
}
local DPS_STAT = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

-- ── What each class can use ─────────────────────────────────────────────────
-- Armor: 1 cloth, 2 leather, 3 mail, 4 plate, 6 shield, 7 libram, 8 idol,
-- 9 totem. A number is the level it is learned at (Forever).

local ARMOR_FOREVER = {
    WARRIOR = { [1] = true, [2] = true, [3] = true, [4] = 40, [6] = true },
    PALADIN = { [1] = true, [2] = true, [3] = true, [4] = 40, [6] = true, [7] = true },
    HUNTER  = { [1] = true, [2] = true, [3] = 40 },
    SHAMAN  = { [1] = true, [2] = true, [3] = 40, [6] = true, [9] = true },
    ROGUE   = { [1] = true, [2] = true },
    DRUID   = { [1] = true, [2] = true, [8] = true },
    PRIEST  = { [1] = true }, MAGE = { [1] = true }, WARLOCK = { [1] = true },
}
-- The main game: one armor type each (wearing a lighter one is never an upgrade).
local ARMOR_MAINLINE = {
    WARRIOR = { [4] = true, [6] = true }, PALADIN = { [4] = true, [6] = true }, DEATHKNIGHT = { [4] = true },
    HUNTER = { [3] = true }, SHAMAN = { [3] = true, [6] = true }, EVOKER = { [3] = true },
    ROGUE = { [2] = true }, DRUID = { [2] = true }, MONK = { [2] = true }, DEMONHUNTER = { [2] = true },
    PRIEST = { [1] = true }, MAGE = { [1] = true }, WARLOCK = { [1] = true },
}
-- Weapons (Forever): 0 1h axe, 1 2h axe, 2 bow, 3 gun, 4 1h mace, 5 2h mace,
-- 6 polearm, 7 1h sword, 8 2h sword, 10 staff, 13 fist, 15 dagger, 16 thrown,
-- 18 crossbow, 19 wand.
local WEAPONS = {
    WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
    HUNTER  = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
    ROGUE   = { 2, 3, 4, 7, 13, 15, 16, 18 },
    SHAMAN  = { 0, 1, 4, 5, 10, 13, 15 },
    DRUID   = { 4, 5, 10, 13, 15 },
    PRIEST  = { 4, 10, 15, 19 },
    MAGE    = { 7, 10, 15, 19 },
    WARLOCK = { 7, 10, 15, 19 },
}
local weaponSets = {}
for class, list in pairs(WEAPONS) do
    weaponSets[class] = {}
    for _, id in ipairs(list) do weaponSets[class][id] = true end
end

local SLOTS_FOR = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

local function Mainline() return OxedHub.IsMainline == true end

local function Instant(link)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if type(fn) ~= "function" then return nil end
    local ok, _, _, _, equipLoc, _, classID, subclassID = pcall(fn, link)
    if not ok then return nil end
    return { equipLoc = Plain(equipLoc), classID = Plain(classID), subclassID = Plain(subclassID) }
end

local function CanUse(class, level, info)
    if info.classID == 4 then
        local sub = info.subclassID
        if sub == 0 then return true end   -- rings, necks, trinkets, held in the off hand
        if Mainline() and (sub == 5) then return true end   -- cosmetic
        local rules = (Mainline() and ARMOR_MAINLINE or ARMOR_FOREVER)[class]
        local rule = rules and rules[sub]
        if rule == true then return true end
        if type(rule) == "number" then return (level or 0) >= rule end
        return false
    elseif info.classID == 2 then
        if Mainline() then return true end   -- the main game's weapon rules are many; the game greys Need out anyway
        return weaponSets[class] and weaponSets[class][info.subclassID] == true or false
    end
    return false
end

-- ── Scoring ─────────────────────────────────────────────────────────────────

local function ItemStats(link)
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if type(fn) ~= "function" then return nil end
    local ok, stats = pcall(fn, link)
    if not ok or type(stats) ~= "table" or Secret(stats) then return nil end
    return stats
end

local function ItemLevel(link)
    local fn = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
    if type(fn) ~= "function" then return nil end
    local level = Call(fn, link)
    return type(level) == "number" and level > 0 and level or nil
end

-- An item's score; nil while it has not loaded.
local function Score(link, weights, hand)
    if type(link) ~= "string" then return nil end
    if Mainline() then return ItemLevel(link) end
    local stats = ItemStats(link)
    if not stats then return nil end
    local total = 0
    for stat, amount in pairs(stats) do
        local key = STAT_KEYS[stat]
        amount = Plain(amount)
        if key and type(amount) == "number" and weights[key] then total = total + amount * weights[key] end
    end
    local dps = Plain(stats[DPS_STAT])
    if type(dps) == "number" then
        if hand == "ranged" then
            total = total + dps * (weights.rdps or 0)
        elseif weights.dps then
            total = total + dps * (hand == "off" and weights.dps / 2 or weights.dps)
        end
    end
    return total
end

local function GearLeans(slots)
    local int, phys = 0, 0
    for _, link in pairs(slots) do
        local stats = ItemStats(link)
        if stats then
            int = int + (Plain(stats.ITEM_MOD_INTELLECT_SHORT) or 0)
            phys = phys + (Plain(stats.ITEM_MOD_AGILITY_SHORT) or 0) + (Plain(stats.ITEM_MOD_STRENGTH_SHORT) or 0)
        end
    end
    return int > phys and "caster" or "physical"
end

local function DualWields(slots)
    local off = slots[17] and Instant(slots[17])
    return off ~= nil and (off.equipLoc == "INVTYPE_WEAPON" or off.equipLoc == "INVTYPE_WEAPONOFFHAND")
end

local ONE_SPEC = { ROGUE = "rogue", MAGE = "mage", WARLOCK = "warlock", HUNTER = "hunter" }
local function SpecOf(class, role, slots)
    if ONE_SPEC[class] then return ONE_SPEC[class] end
    if role == "TANK" then
        return ({ WARRIOR = "protection", PALADIN = "protection", DRUID = "bear", SHAMAN = "enhancement" })[class]
    elseif role == "HEALER" then
        return ({ PALADIN = "holy", PRIEST = "holy", SHAMAN = "restoration", DRUID = "restoration" })[class]
    elseif role == "DAMAGER" then
        if class == "WARRIOR" then return DualWields(slots) and "fury" or "arms" end
        if class == "PALADIN" then return "retribution" end
        if class == "PRIEST" then return "shadow" end
        if class == "SHAMAN" then return GearLeans(slots) == "caster" and "elemental" or "enhancement" end
        if class == "DRUID" then return GearLeans(slots) == "caster" and "balance" or "feral" end
    end
    return nil
end

-- { pct = number } or { new = true }, or nil: cannot use it, cannot tell,
-- or still loading.
local function Work(link, class, level, role, slots)
    local info = Instant(link)
    local where = info and SLOTS_FOR[info.equipLoc]
    if not where or type(class) ~= "string" or not CanUse(class, level, info) then return nil end
    local weights = {}
    if not Mainline() then
        local spec = SpecOf(class, role, slots)
        weights = spec and WEIGHTS[class] and WEIGHTS[class][spec]
        if not weights then return nil end
    end
    local hand = (info.equipLoc == "INVTYPE_WEAPONOFFHAND") and "off" or ((where[1] == 18) and "ranged") or "main"
    local new = Score(link, weights, hand)
    if not new then return nil end

    local old, empty
    if info.equipLoc == "INVTYPE_2HWEAPON" then
        if not slots[16] and not slots[17] then
            empty = true
        else
            local main = slots[16] and Score(slots[16], weights, "main")
            local off = slots[17] and Score(slots[17], weights, "off")
            if (slots[16] and not main) or (slots[17] and not off) then return nil end
            if Mainline() then
                old = math.max(main or 0, off or 0)   -- item levels do not add up
            else
                old = (main or 0) + (off or 0)
            end
        end
    else
        for _, slot in ipairs(where) do
            if not slots[slot] then
                empty = true
                break
            end
            local s = Score(slots[slot], weights, slot == 17 and "off" or slot == 18 and "ranged" or "main")
            if not s then return nil end
            if not old or s < old then old = s end   -- two rings or trinkets: the weaker goes
        end
    end
    if empty or not old or old <= 0 then
        if new <= 0 then return nil end
        return { new = true }
    end
    return { pct = (new - old) / old * 100 }
end

-- ── The group ───────────────────────────────────────────────────────────────

local function GroupUnits()
    local out = {}
    local count = Call(GetNumGroupMembers) or 0
    if Call(IsInRaid) == true then
        for i = 1, count do out[#out + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, count - 1) do out[#out + 1] = "party" .. i end
    end
    return out
end

local function IsPlayerUnit(unit) return unit == "player" or Call(UnitIsUnit, unit, "player") == true end

local byName, byNameAt = {}, -math.huge
local function UnitNamed(name)
    if type(name) ~= "string" then return nil end
    local now = Now()
    if now - byNameAt >= 1 then
        byName, byNameAt = {}, now
        for _, unit in ipairs(GroupUnits()) do
            local plain = not IsPlayerUnit(unit) and BaseName(Call(UnitName, unit))
            if plain and not byName[plain] then byName[plain] = unit end
        end
    end
    return byName[name]
end

-- A unit's role, and true when the game hides it.
local function RoleOf(unit)
    if type(UnitGroupRolesAssigned) ~= "function" then return nil, false end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    if not ok then return nil, false end
    if Secret(role) then return nil, true end
    return type(role) == "string" and role or nil, false
end

local function InstanceKey()
    if Call(IsInInstance) ~= true then return nil end
    local ok, name, _, _, _, _, _, _, id = pcall(GetInstanceInfo)
    if not ok then return "instance" end
    return tostring(Plain(id) or Plain(name) or "instance")
end

local blockedIn, warnedIn, clearIn, clearAt
local function RolesReadable()
    if Mainline() then return true end   -- the item-level score needs no role
    local here = InstanceKey()
    if not here then
        blockedIn = nil
        return true
    end
    if blockedIn == here then return false end
    local now = Now()
    if clearIn == here and clearAt and now - clearAt < 1 then return true end
    clearIn, clearAt = here, now
    for _, unit in ipairs(GroupUnits()) do
        local _, hidden = RoleOf(unit)
        if hidden then
            blockedIn, clearIn = here, nil
            if warnedIn ~= here then
                warnedIn = here
                print("|cff33ff99OxedHub Roll Advisor:|r " .. T("Upgrade % for others is off in this instance: the game hides group roles here."))
            end
            return false
        end
    end
    return true
end

-- ── Inspecting ──────────────────────────────────────────────────────────────

local gear = {}    -- [guid] = { at, class, level, slots, stale, hidden }
local cache = {}   -- ["name|link"] = { at, value }
local pending      -- { unit, guid, at }
local lastInspect = -math.huge

local function InspectWindowOpen()
    return InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() and true or false
end

local function CanInspectUnit(unit)
    if Call(UnitExists, unit) ~= true or IsPlayerUnit(unit) then return false end
    if Call(UnitIsConnected, unit) == false then return false end
    if type(CanInspect) == "function" and Call(CanInspect, unit) ~= true then return false end
    if type(CheckInteractDistance) == "function" then
        -- CheckInteractDistance is refused in combat on some clients; we never get here in combat.
        if Call(CheckInteractDistance, unit, 1) ~= true then return false end
    end
    return true
end

local function WornBy(unit)
    local slots, found = {}, 0
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = Call(GetInventoryItemLink, unit, slot)
        if type(link) == "string" then
            slots[slot] = link
            found = found + 1
        end
    end
    return slots, found
end

local function Step()
    if not (running and settings and settings.groupUpgrade) then return end
    local now = Now()
    if pending then
        if now - pending.at < INSPECT_WAIT then return end
        pending = nil
    end
    if now - lastInspect < INSPECT_GAP or Call(InCombatLockdown) ~= false or InspectWindowOpen() then return end
    if type(NotifyInspect) ~= "function" or not RolesReadable() then return end
    for _, unit in ipairs(GroupUnits()) do
        local guid = Call(UnitGUID, unit)
        if type(guid) == "string" and CanInspectUnit(unit) then
            local g = gear[guid]
            if not g or g.stale or now - g.at > GEAR_KEEP then
                pending = { unit = unit, guid = guid, at = now }
                lastInspect = now
                pcall(NotifyInspect, unit)
                return
            end
        end
    end
end

local function Inspected(guid)
    guid = Plain(guid)
    if type(guid) ~= "string" then return end
    local unit = pending and pending.guid == guid and pending.unit
    if not unit then
        -- Someone else's inspect (yours, another addon's): take the gear too.
        for _, u in ipairs(GroupUnits()) do
            if Call(UnitGUID, u) == guid then unit = u break end
        end
    end
    if not unit or IsPlayerUnit(unit) then return end
    local slots, found = WornBy(unit)
    local _, class = Call(UnitClass, unit)
    local level = Call(UnitLevel, unit)
    gear[guid] = { at = Now(), slots = slots, class = class, level = type(level) == "number" and level or nil,
                   hidden = found == 0 or nil }
    wipe(cache)
    if pending and pending.guid == guid then
        pending = nil
        if not InspectWindowOpen() and type(ClearInspectPlayer) == "function" then pcall(ClearInspectPlayer) end
    end
    if Up.OnChanged then pcall(Up.OnChanged) end
end

-- ── For Roll Advisor ────────────────────────────────────────────────────────

local function WorkMine(link)
    local _, class = Call(UnitClass, "player")
    local level = Call(UnitLevel, "player")
    local role = RoleOf("player")
    return Work(link, class, type(level) == "number" and level or nil, role, (WornBy("player")))
end

local function WorkTheirs(link, name)
    if not RolesReadable() then return nil end
    local unit = UnitNamed(name)
    local guid = unit and Call(UnitGUID, unit)
    local g = guid and gear[guid]
    if not (g and not g.hidden and g.class) then return nil end
    return Work(link, g.class, g.level or Call(UnitLevel, unit), (RoleOf(unit)), g.slots)
end

-- What a player gains from the item: { pct, new, exact } or nil.
function Up.For(link, name, isMe)
    if not (running and settings and settings.groupUpgrade) then return nil end
    if type(link) ~= "string" or Secret(link) or type(name) ~= "string" then return nil end
    local key = (isMe and "\001me" or name) .. "|" .. link
    local now = Now()
    local hit = cache[key]
    if hit and now - hit.at < KEEP then return hit.value end
    local ok, w = pcall(isMe and WorkMine or WorkTheirs, link, name)
    local value = ok and w and { pct = w.pct, new = w.new, exact = isMe and true or nil } or nil
    cache[key] = { at = now, value = value }
    return value
end

-- "+12%" green, "-22%" red, "0%" grey, "new" green; a ~ in front of others'.
function Up.Text(value)
    if type(value) ~= "table" then return "" end
    local mark = value.exact and "" or "~"
    if value.new then return "|cff40ff40" .. mark .. T("new") .. "|r" end
    local pct = value.pct >= 0 and math.floor(value.pct + 0.5) or -math.floor(-value.pct + 0.5)
    if pct >= 1 then return "|cff40ff40" .. mark .. "+" .. pct .. "%|r" end
    if pct <= -1 then return "|cffff4040" .. mark .. pct .. "%|r" end
    return "|cff9d9d9d" .. mark .. "0%|r"
end

-- r, g, b for a value's mark on the list, or nil.
function Up.Colour(value)
    if type(value) ~= "table" then return nil end
    if value.new or (value.pct or 0) >= 1 then return 0.25, 1, 0.25 end
    if (value.pct or 0) <= -1 then return 1, 0.25, 0.25 end
    return 0.6, 0.6, 0.6
end

local events = CreateFrame("Frame")
local ticker = CreateFrame("Frame")
local waited = 0
ticker:SetScript("OnUpdate", nil)

events:SetScript("OnEvent", function(_, event, a)
    if event == "INSPECT_READY" then
        pcall(Inspected, a)
    elseif event == "UNIT_INVENTORY_CHANGED" then
        local guid = Call(UnitGUID, a)
        if type(guid) == "string" and gear[guid] then gear[guid].stale = true end
        wipe(cache)
    elseif event == "PLAYER_ENTERING_WORLD" then
        blockedIn, pending, clearIn, byNameAt = nil, nil, nil, -math.huge
        wipe(cache)
    end
end)

local function OnTick(_, dt)
    waited = waited + dt
    if waited < 0.5 then return end
    waited = 0
    pcall(Step)
end

-- Roll Advisor's settings, and whether the work should run now.
-- on: true the module is being switched on, false off, nil as the settings say.
local moduleOn = false
function Up.Apply(cfg, on)
    settings = cfg or settings
    if on ~= nil then moduleOn = on end
    local want = moduleOn and settings and settings.groupUpgrade and true or false
    if want == running then return end
    running = want
    if want then
        pcall(events.RegisterEvent, events, "INSPECT_READY")
        pcall(events.RegisterEvent, events, "UNIT_INVENTORY_CHANGED")
        pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
        ticker:SetScript("OnUpdate", OnTick)
    else
        events:UnregisterAllEvents()
        ticker:SetScript("OnUpdate", nil)
        pending = nil
        wipe(cache)
    end
end
