-- ============================================================================
-- Buff Reminder: what to look for
-- Plain data, read by BuffReminder.lua. Nothing here runs or registers events.
--
-- Every entry describes one reminder:
--   key       unique name, also the settings key "hide_<key>"
--   group     "raid" (you give it to the group), "self", "pet", "consumable"
--   class     only for this class (file name, e.g. "MAGE")
--   specs     only for these specialisation IDs (set); notSpecs: never for these
--   level     only from this character level on
--   notAura   not while this aura is on you (e.g. a pet sacrificed for a buff)
--   known     only when this spell is known (IsPlayerSpell); with castList
--             and no known, any spell of castList being known is enough
--   notKnown  not when this spell is known (a talent replaces the reminder)
--   auras     spell IDs; any one of them on the unit counts as covered
--   cast      spell cast when the icon is clicked (defaults to known)
--   castList  first known spell from this list is cast instead
--   enchants  weapon enchant IDs; any one on either hand counts
--   form      true: any shapeshift form / stance / aura counts as covered
--   check     "pet", "food", "flask" or "rune": a special test in the module
--   instance  true: only reminded inside instances (consumables)
-- ============================================================================

local addonName, OxedHub = ...

local Data = {}
OxedHub.BuffReminderData = Data

-- Buffs the whole group shares. Coverage is counted over group members nearby.
Data.RAID = {
    { key = "intellect",   group = "raid", class = "MAGE",    auras = { 1459, 432778 }, known = 1459 },
    { key = "attackPower", group = "raid", class = "WARRIOR", auras = { 6673 },         known = 6673 },
    { key = "versatility", group = "raid", class = "DRUID",   auras = { 1126, 432661 }, known = 1126 },
    { key = "stamina",     group = "raid", class = "PRIEST",  auras = { 21562 },        known = 21562 },
    { key = "skyfury",     group = "raid", class = "SHAMAN",  auras = { 462854 },       known = 462854 },
    { key = "bronze",      group = "raid", class = "EVOKER",  known = 364342,
      auras = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752,
                381753, 381754, 381756, 381757, 381758 } },
}

-- Things that only concern you.
Data.SELF = {
    -- Rogue poisons: one lethal and one non-lethal.
    { key = "lethalPoison", group = "self", class = "ROGUE", known = 2823,
      auras = { 2823, 8679, 315584, 381664 }, castList = { 315584, 2823, 8679, 381664 } },
    { key = "utilityPoison", group = "self", class = "ROGUE", known = 3408,
      auras = { 3408, 5761, 381637 }, castList = { 3408, 381637, 5761 } },

    -- Shaman
    { key = "shamanShield", group = "self", class = "SHAMAN",
      auras = { 52127, 192106, 974, 383648 }, castList = { 192106, 52127 } },
    { key = "flametongue", group = "self", class = "SHAMAN", known = 318038, enchants = { 5400 } },
    { key = "windfury",    group = "self", class = "SHAMAN", known = 33757,  enchants = { 5401 } },
    { key = "earthliving", group = "self", class = "SHAMAN", known = 382021, enchants = { 6498 } },
    { key = "tidecaller",  group = "self", class = "SHAMAN", known = 457481, enchants = { 7528 } },

    -- Paladin
    { key = "paladinAura", group = "self", class = "PALADIN", known = 465, form = true },
    { key = "riteSanctification", group = "self", class = "PALADIN", known = 433568, enchants = { 7143 } },
    { key = "riteAdjuration",     group = "self", class = "PALADIN", known = 433583, enchants = { 7144 } },

    -- Priest: Shadowform (a stance, so it reads correctly anywhere)
    { key = "shadowform", group = "self", class = "PRIEST", specs = { [258] = true }, known = 232698, form = true },

    -- Mage
    { key = "arcaneFamiliar", group = "self", class = "MAGE", known = 205022, auras = { 210126 } },

    -- Evoker: Augmentation attunement
    { key = "attunement", group = "self", class = "EVOKER", specs = { [1473] = true }, known = 403208,
      auras = { 403264, 403265 }, castList = { 403264, 403265 } },

    -- Death knight runeforge on the weapon
    { key = "runeforge", group = "self", class = "DEATHKNIGHT", level = 55, cast = 53428, permanent = true,
      enchants = { 3368, 3370, 3847, 6241, 6242, 6243, 6244, 6245 } },
}

Data.PET = {
    { key = "hunterPet",  group = "pet", class = "HUNTER",  known = 883, check = "pet", notSpecs = { [254] = true } },
    { key = "warlockPet", group = "pet", class = "WARLOCK", known = 688, check = "pet", notAura = 196099 },
    { key = "unholyPet",  group = "pet", class = "DEATHKNIGHT", specs = { [252] = true }, known = 46584, check = "pet" },
    { key = "frostPet",   group = "pet", class = "MAGE", specs = { [64] = true }, known = 31687, check = "pet" },
}

Data.CONSUMABLE = {
    { key = "food",  group = "consumable", check = "food",  instance = true, icon = 136000 },
    { key = "flask", group = "consumable", check = "flask", instance = true,
      auras = { 432021, 431971, 431972, 431973, 431974, 432473,
                1235057, 1235108, 1235110, 1235111, 1239355 } },
    { key = "rune",  group = "consumable", check = "rune",  instance = true,
      auras = { 1234969, 1242347, 453250, 393438, 1264426, 1295329, 347901 } },
    { key = "weaponOil", group = "consumable", check = "oil", instance = true },
}

-- Labels shown in tooltips and in Options, by key.
Data.LABELS = {
    intellect = "Arcane Intellect", attackPower = "Battle Shout", versatility = "Mark of the Wild",
    stamina = "Power Word: Fortitude", skyfury = "Skyfury", bronze = "Blessing of the Bronze",
    lethalPoison = "Lethal poison", utilityPoison = "Non-lethal poison", shamanShield = "Elemental shield",
    skyfuryOwn = "Skyfury", flametongue = "Flametongue Weapon", windfury = "Windfury Weapon",
    earthliving = "Earthliving Weapon", tidecaller = "Tidecaller's Guard", paladinAura = "Paladin aura",
    riteSanctification = "Rite of Sanctification", riteAdjuration = "Rite of Adjuration",
    shadowform = "Shadowform", arcaneFamiliar = "Arcane Familiar", attunement = "Attunement",
    runeforge = "Runeforge", hunterPet = "Pet", warlockPet = "Demon", unholyPet = "Ghoul",
    frostPet = "Water Elemental", food = "Well Fed", flask = "Flask", rune = "Augment rune",
    weaponOil = "Weapon oil or stone",
}

-- Classes whose weapon slot already holds a class imbue; the oil reminder
-- would only nag them.
Data.NO_OIL_CLASS = { ROGUE = true, SHAMAN = true, DEATHKNIGHT = true, PALADIN = true }

-- Flask and rune icons are clickable with no item list to keep up to date:
-- the module looks through the bags for an item whose use effect is one of
-- the entry's auras (FindItemFor in BuffReminder.lua).
