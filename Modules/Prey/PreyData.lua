local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey

-- Astalor Bloodsworn and Hunt Table NPCs
Prey.ASTALOR_NPC_ID = 246231
Prey.HUNT_TABLE_NPC_IDS = {
    [246231] = true, -- Astalor Bloodsworn
    [245824] = true, -- Hunt Table
}

-- Torment Auras
Prey.TORMENT_SPELL_ID = 1245570       -- Hard: +2% damage taken per stack, max 10
Prey.TORMENT_NIGHTMARE_ID = 1245521   -- Nightmare: +4% damage taken per stack

-- Currencies & Faction
Prey.CURRENCY_REMNANT = 3392          -- Remnant of Anguish
Prey.CURRENCY_PREYSEEKER = 3387       -- Preyseeker's Journey
Prey.FACTION_PREYSEEKER = 2764        -- Prey: Season 1

-- Stage Labels
Prey.STAGE_LABELS = {
    [1] = "Scent in the Wind",
    [2] = "Blood in the Shadows",
    [3] = "Echoes of the Kill",
    [4] = "Feast of the Fang",
}

-- Stage fallback percentages, used only until the widget reports real progress.
-- Quarters: each of the four hunt stages is one quarter of the bar.
Prey.STAGE_PERCENTS = {
    [1] = 25,
    [2] = 50,
    [3] = 75,
    [4] = 100,
}

-- Canonical Map ID Equivalents
Prey.MAP_ID_EQUIVALENTS = {
    [2437] = 2437, [2536] = 2437, [2537] = 2437, -- Zul'Aman
    [2413] = 2413, [2576] = 2413,                -- Harandar
    [2405] = 2405, [2444] = 2405,                -- Voidstorm
    [2395] = 2395,                               -- Eversong Woods
    [2438] = 2437,                               -- Coiled Isle submap -> Zul'Aman
    [2512] = 2512,                               -- The Coiled Isle
}

-- Primary Hunt Achievements by Difficulty (1 = Normal, 2 = Hard, 3 = Nightmare)
Prey.PREY_HUNT_ACHIEVEMENT_IDS = { 42701, 42702, 42703 }

Prey.PREY_HUNT_MODE_ACHIEVEMENT_IDS_BY_DIFFICULTY = {
    [1] = { 61387, 61386, 42701 }, -- Normal I, II, III
    [2] = { 61389, 61388, 42702 }, -- Hard I, II, III
    [3] = { 61392, 61391, 42703 }, -- Nightmare I, II, III
}

-- Specific target encounter achievements
Prey.PREY_HUNT_ACHIEVEMENTS_BY_QUEST = {
    [91210] = { 62144 }, [91212] = { 62144 },
    [91214] = { 62153 }, [91216] = { 62153 },
    [91218] = { 62154 }, [91220] = { 62154 },
    [91222] = { 62155 }, [91224] = { 62155 },
    [91226] = { 62156 }, [91228] = { 62156 },
    [91230] = { 62157 }, [91232] = { 62157 },
    [91234] = { 62158 }, [91236] = { 62158 },
    [91238] = { 62159 }, [91240] = { 62159 },
    [91242] = { 62160 }, [91243] = { 62160 },
    [91244] = { 62161 }, [91245] = { 62161 },
    [91246] = { 62162 }, [91247] = { 62162 },
    [91248] = { 62163 }, [91249] = { 62163 },
    [91250] = { 62164 }, [91251] = { 62164 },
    [91252] = { 62165 }, [91253] = { 62165 },
    [91254] = { 62166 }, [91255] = { 62166 },
    [91211] = { 62167 }, [91213] = { 62167 },
    [91215] = { 62168 }, [91217] = { 62168 },
    [91219] = { 62169 }, [91221] = { 62169 },
    [91223] = { 62173 }, [91225] = { 62173 },
    [91227] = { 62174 }, [91229] = { 62174 },
    [91231] = { 62175 }, [91233] = { 62175 },
    [91235] = { 62176 }, [91237] = { 62176 },
    [91239] = { 62177 }, [91241] = { 62177 },
    [91256] = { 62178 }, [91257] = { 62178 },
    [91258] = { 62179 }, [91259] = { 62179 },
    [91260] = { 62180 }, [91261] = { 62180 },
    [91262] = { 62181 }, [91263] = { 62181 },
    [91264] = { 62182 }, [91265] = { 62182 },
    [91266] = { 62183 }, [91267] = { 62183 },
    [91268] = { 62184 }, [91269] = { 62184 },
}

-- [questID] = { difficultyIndex, criteriaID, targetName }
Prey.PreyQuestData = {
    -- Normal (Difficulty 1)
    [91095] = { 1, 105912, "Magister Sunbreaker" },
    [91096] = { 1, 105913, "Magistrix Emberlash" },
    [91097] = { 1, 105914, "Senior Tinker Ozwold" },
    [91098] = { 1, 105915, "L-N-0R the Recycler" },
    [91099] = { 1, 105916, "Mordril Shadowfell" },
    [91100] = { 1, 105917, "Deliah Gloomsong" },
    [91101] = { 1, 105918, "Phaseblade Talasha" },
    [91102] = { 1, 105919, "Nexus-Edge Hadim" },
    [91103] = { 1, 105920, "Jo'zolo the Breaker" },
    [91104] = { 1, 105921, "Zadu, Fist of Nalorakk" },
    [91105] = { 1, 105922, "The Talon of Jan'alai" },
    [91106] = { 1, 105923, "The Wing of Akil'zon" },
    [91107] = { 1, 105924, "Ranger Swiftglade" },
    [91108] = { 1, 105925, "Lieutenant Blazewing" },
    [91109] = { 1, 105926, "Petyoll the Razorleaf" },
    [91110] = { 1, 105927, "Lamyne of the Undercroft" },
    [91111] = { 1, 105928, "High Vindicator Vureem" },
    [91112] = { 1, 105929, "Crusader Luxia Maxwell" },
    [91113] = { 1, 105930, "Praetor Singularis" },
    [91114] = { 1, 105931, "Consul Nebulor" },
    [91115] = { 1, 105932, "Executor Kaenius" },
    [91116] = { 1, 105933, "Imperator Enigmalia" },
    [91117] = { 1, 105934, "Knight-Errant Bloodshatter" },
    [91118] = { 1, 105935, "Vylenna the Defector" },
    [91119] = { 1, 105936, "Lost Theldrin" },
    [91120] = { 1, 105937, "Neydra the Starving" },
    [91121] = { 1, 105938, "Thornspeaker Edgath" },
    [91122] = { 1, 105939, "Thorn-Witch Liset" },
    [91123] = { 1, 105940, "Grothoz, the Burning Shadow" },
    [91124] = { 1, 105941, "Dengzag, the Darkened Blaze" },

    -- Hard (Difficulty 2)
    [91210] = { 2, 105942, "Magister Sunbreaker" },
    [91212] = { 2, 105943, "Magistrix Emberlash" },
    [91214] = { 2, 105944, "Senior Tinker Ozwold" },
    [91216] = { 2, 105945, "L-N-0R the Recycler" },
    [91218] = { 2, 105946, "Mordril Shadowfell" },
    [91220] = { 2, 105947, "Deliah Gloomsong" },
    [91222] = { 2, 105948, "Phaseblade Talasha" },
    [91224] = { 2, 105949, "Nexus-Edge Hadim" },
    [91226] = { 2, 105950, "Jo'zolo the Breaker" },
    [91228] = { 2, 105951, "Zadu, Fist of Nalorakk" },
    [91230] = { 2, 105952, "The Talon of Jan'alai" },
    [91232] = { 2, 105953, "The Wing of Akil'zon" },
    [91234] = { 2, 105954, "Ranger Swiftglade" },
    [91236] = { 2, 105955, "Lieutenant Blazewing" },
    [91238] = { 2, 105956, "Petyoll the Razorleaf" },
    [91240] = { 2, 105957, "Lamyne of the Undercroft" },
    [91242] = { 2, 105958, "High Vindicator Vureem" },
    [91243] = { 2, 105959, "Crusader Luxia Maxwell" },
    [91244] = { 2, 105960, "Praetor Singularis" },
    [91245] = { 2, 105961, "Consul Nebulor" },
    [91246] = { 2, 105962, "Executor Kaenius" },
    [91247] = { 2, 105963, "Imperator Enigmalia" },
    [91248] = { 2, 105964, "Knight-Errant Bloodshatter" },
    [91249] = { 2, 105965, "Vylenna the Defector" },
    [91250] = { 2, 105966, "Lost Theldrin" },
    [91251] = { 2, 105967, "Neydra the Starving" },
    [91252] = { 2, 105968, "Thornspeaker Edgath" },
    [91253] = { 2, 105969, "Thorn-Witch Liset" },
    [91254] = { 2, 105970, "Grothoz, the Burning Shadow" },
    [91255] = { 2, 105971, "Dengzag, the Darkened Blaze" },

    -- Nightmare (Difficulty 3)
    [91211] = { 3, 105972, "Magister Sunbreaker" },
    [91213] = { 3, 105973, "Magistrix Emberlash" },
    [91215] = { 3, 105974, "Senior Tinker Ozwold" },
    [91217] = { 3, 105975, "L-N-0R the Recycler" },
    [91219] = { 3, 105976, "Mordril Shadowfell" },
    [91221] = { 3, 105977, "Deliah Gloomsong" },
    [91223] = { 3, 105978, "Phaseblade Talasha" },
    [91225] = { 3, 105979, "Nexus-Edge Hadim" },
    [91227] = { 3, 105980, "Jo'zolo the Breaker" },
    [91229] = { 3, 105981, "Zadu, Fist of Nalorakk" },
    [91231] = { 3, 105982, "The Talon of Jan'alai" },
    [91233] = { 3, 105983, "The Wing of Akil'zon" },
    [91235] = { 3, 105984, "Ranger Swiftglade" },
    [91237] = { 3, 105985, "Lieutenant Blazewing" },
    [91239] = { 3, 105986, "Petyoll the Razorleaf" },
    [91241] = { 3, 105987, "Lamyne of the Undercroft" },
    [91256] = { 3, 105988, "High Vindicator Vureem" },
    [91257] = { 3, 105989, "Crusader Luxia Maxwell" },
    [91258] = { 3, 105990, "Praetor Singularis" },
    [91259] = { 3, 105991, "Consul Nebulor" },
    [91260] = { 3, 105992, "Executor Kaenius" },
    [91261] = { 3, 105993, "Imperator Enigmalia" },
    [91262] = { 3, 105994, "Knight-Errant Bloodshatter" },
    [91263] = { 3, 105995, "Vylenna the Defector" },
    [91264] = { 3, 105996, "Lost Theldrin" },
    [91265] = { 3, 105997, "Neydra the Starving" },
    [91266] = { 3, 105998, "Thornspeaker Edgath" },
    [91267] = { 3, 105999, "Thorn-Witch Liset" },
    [91268] = { 3, 106000, "Grothoz, the Burning Shadow" },
    [91269] = { 3, 106001, "Dengzag, the Darkened Blaze" },
}

-- Unit GUID / NPC helper
function Prey:GetUnitNpcID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local ok, _, _, _, _, _, npcIDStr = pcall(string.split, "-", guid)
    if not ok then return nil end
    return tonumber(npcIDStr)
end

-- Prey:CanonicalizeMapID is defined in PreyEngine.lua, where the secret-number
-- sanitizer it depends on lives.
