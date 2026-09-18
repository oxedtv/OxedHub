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
    { key = "hunterPet",  group = "pet", class = "HUNTER",  known = 883, check = "pet" },
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
    { key = "healthstone", group = "consumable", check = "healthstone", instance = true },
    { key = "repair", group = "consumable", check = "repair" },
    -- Group utility, only while a ready check is up (or forced by one).
    { key = "soulwell", group = "consumable", check = "readycheck", class = "WARLOCK", known = 29893 },
    { key = "refreshment", group = "consumable", check = "readycheck", class = "MAGE", known = 190336 },
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
    weaponOil = "Weapon oil or stone", healthstone = "Healthstone", repair = "Repair your gear",
    soulwell = "Soulwell", refreshment = "Refreshment Table",
}

-- Classes whose weapon slot already holds a class imbue; the oil reminder
-- would only nag them.
Data.NO_OIL_CLASS = { ROGUE = true, SHAMAN = true, DEATHKNIGHT = true, PALADIN = true }

-- ── Consumables shown one icon per item carried ─────────────────────────────
-- When food, a flask, a rune or weapon oil is missing, every matching item in
-- the bags gets its own clickable icon with its stack count, a short stat
-- label on top and a small badge (H = hearty, F = fleeting). Listed best
-- first; the first entries are the current expansion's.
local function I(id, label, badge) return { id = id, label = label, badge = badge } end

Data.ITEMS = {
    flask = {
        I(241320, "Vers"), I(241321, "Vers"), I(241322, "Mast"), I(241323, "Mast"),
        I(241324, "Haste"), I(241325, "Haste"), I(241326, "Crit"), I(241327, "Crit"),
        I(241334, "PvP"), I(241335, "PvP"),
        I(245926, "Vers", "F"), I(245927, "Vers", "F"), I(245928, "Crit", "F"), I(245929, "Crit", "F"),
        I(245930, "Haste", "F"), I(245931, "Haste", "F"), I(245932, "Mast", "F"), I(245933, "Mast", "F"),
        -- The War Within
        I(212269, "Crit"), I(212270, "Crit"), I(212271, "Crit"),
        I(212272, "Haste"), I(212273, "Haste"), I(212274, "Haste"),
        I(212275, "Vers"), I(212276, "Vers"), I(212277, "Vers"),
        I(212278, "Mast"), I(212279, "Mast"), I(212280, "Mast"),
        I(212281, "Rand"), I(212282, "Rand"), I(212283, "Rand"),
        I(212299, "Heal"), I(212300, "Heal"), I(212301, "Heal"),
    },
    rune = {
        I(274797), I(259085), I(243191), I(246492), I(224572), I(211495), I(201325), I(181468),
    },
    food = {
        I(255845, "Feast"), I(255846, "Feast"), I(266985, "Feast", "H"), I(266996, "Feast", "H"),
        I(275264, "Feast"), I(275265, "Feast"), I(275266, "Feast"),
        I(242275, "Hi 1st"), I(255847, "Hi 1st"), I(242747, "Hi 1st", "H"), I(268679, "Hi 1st", "H"),
        I(242272, "Hi 2nd"), I(242273, "Hi 2nd"), I(242274, "Hi 2nd"), I(255848, "Hi 2nd"),
        I(275258, "Hi 2nd"), I(275260, "Hi 2nd"), I(275261, "Hi 2nd"),
        I(242744, "Hi 2nd", "H"), I(242745, "Hi 2nd", "H"), I(242746, "Hi 2nd", "H"),
        I(266986, "Hi 2nd", "H"), I(267000, "Hi 2nd", "H"), I(268680, "Hi 2nd", "H"),
        I(242279, "Mid 1st"), I(242288, "Mid 1st"), I(242289, "Mid 1st"),
        I(242751, "Mid 1st", "H"), I(242760, "Mid 1st", "H"), I(242761, "Mid 1st", "H"),
        I(242276, "V"), I(242280, "V"), I(242284, "V"), I(242294, "V"),
        I(242277, "H"), I(242282, "H"), I(242286, "H"),
        I(242278, "Crit"), I(242283, "Crit"), I(242287, "Crit"),
        I(242281, "M"), I(242285, "M"),
        I(242290, "Crit/V"), I(242304, "Crit/V"), I(242291, "M/V"), I(242305, "M/V"),
        I(242292, "M/Crit"), I(242306, "M/Crit"), I(242293, "H/V"), I(242307, "H/V"),
        I(242295, "H/Crit"), I(242308, "H/Crit"), I(242296, "M/H"), I(242309, "M/H"),
        I(242748, "V", "H"), I(242752, "V", "H"), I(242756, "V", "H"), I(242766, "V", "H"),
        I(242749, "H", "H"), I(242754, "H", "H"), I(242758, "H", "H"),
        I(242750, "Crit", "H"), I(242755, "Crit", "H"), I(242759, "Crit", "H"),
        I(242753, "M", "H"), I(242757, "M", "H"),
        I(242762, "Crit/V", "H"), I(242771, "Crit/V", "H"), I(242763, "M/V", "H"), I(242772, "M/V", "H"),
        I(242764, "M/Crit", "H"), I(242773, "M/Crit", "H"), I(242765, "H/V", "H"), I(242774, "H/V", "H"),
        I(242767, "H/Crit", "H"), I(242775, "H/Crit", "H"), I(242768, "M/H", "H"), I(242776, "M/H", "H"),
        I(242302, "Lo 1st"), I(242303, "Lo 1st"), I(242532, "Lo 1st"),
        I(242769, "Lo 1st", "H"), I(242770, "Lo 1st", "H"),
    },
    weaponOil = {
        I(243733), I(243734), I(243735), I(243736), I(243737), I(243738),
        I(237367), I(237369), I(237370), I(237371),
        I(257749), I(257750), I(257751), I(257752),
    },
}

-- At most this many item icons per consumable; the best ones come first.
Data.ITEMS_PER_KIND = 6

Data.HEALTHSTONES = { 5512, 224464 }
Data.CREATE_HEALTHSTONE = 6201
Data.CREATE_SOULWELL = 29893

-- Pets
Data.CALL_PET = { 883, 83242, 83243, 83244, 83245 }
Data.REVIVE_PET = 982
Data.MM_PET_TALENT = 1223323     -- Marksmanship keeps a pet only with this
Data.EXOTIC_BEASTS = 53270
Data.DEMON_FLYOUT = 10           -- Summon Demon
Data.FELGUARD = 30146
Data.DEMON_NAMES = { [688] = "Imp", [697] = "Voidwalker", [691] = "Felhunter", [366222] = "Sayaad", [30146] = "Felguard" }

-- Gear below this durability (percent, worst item) gets a repair reminder.
Data.REPAIR_BELOW = 25
