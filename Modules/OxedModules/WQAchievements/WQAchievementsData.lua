-- ============================================================================
-- WQ Achievements: data. Generated from public-domain world quest data;
-- regenerate rather than edit by hand. Per expansion:
--   achievements = { { name, id, criteriaType?, criteria?, faction?, notAccountwide? } }
--   mounts / pets / toys = { { name, itemID, spellID?, quest = { { wqID } } } }
-- criteria[i] lines up with the achievement's own criterion i, so each one is
-- checked against the game, never assumed.
-- ============================================================================

local addonName, OxedHub = ...
local D = { data = {} }
OxedHub.WQAData = D

-- Legion
do
    --	Legion
    local data = {
        name = _G.EXPANSION_NAME6
    }
    D.data[7] = data

    -- Achievements
    local trainer = {
        42159,
        40299,
        40277,
        42442,
        40298,
        40280,
        40282,
        41687,
        40278,
        41944,
        41895,
        40337,
        41990,
        40279,
        41860
    }
    local argusTrainer = {
        49041,
        49042,
        49043,
        49044,
        49045,
        49046,
        49047,
        49048,
        49049,
        49050,
        49051,
        49052,
        49053,
        49054,
        49055,
        49056,
        49057,
        49058
    }

    data.achievements = {
        {
            name = "Free For All, More For Me",
            id = 11474,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {id = 11475, notAccountwide = true},
                {id = 11476, notAccountwide = true},
                {id = 11477, notAccountwide = true},
                {id = 11478, notAccountwide = true}
            }
        },
        {
            name = "Family Familiar",
            id = 9696,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {id = 9686, criteriaType = "QUESTS", criteria = trainer},
                {id = 9687, criteriaType = "QUESTS", criteria = trainer},
                {id = 9688, criteriaType = "QUESTS", criteria = trainer},
                {id = 9689, criteriaType = "QUESTS", criteria = trainer},
                {id = 9690, criteriaType = "QUESTS", criteria = trainer},
                {id = 9691, criteriaType = "QUESTS", criteria = trainer},
                {id = 9692, criteriaType = "QUESTS", criteria = trainer},
                {id = 9693, criteriaType = "QUESTS", criteria = trainer},
                {id = 9694, criteriaType = "QUESTS", criteria = trainer},
                {id = 9695, criteriaType = "QUESTS", criteria = trainer}
            }
        },
        {
            name = "Family Fighter",
            id = 12100,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {id = 12089, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12091, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12092, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12093, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12094, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12095, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12096, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12097, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12098, criteriaType = "QUESTS", criteria = argusTrainer},
                {id = 12099, criteriaType = "QUESTS", criteria = argusTrainer}
            }
        },
        {name = "Battle on the Broken Isles", id = 10876},
        {
            name = "Fishing 'Round the Isles",
            id = 10598,
            criteriaType = "QUESTS",
            criteria = {
                {41612, 41613, 41270},
                41267,
                {41604, 41605, 41279},
                {41598, 41599, 41264},
                41268,
                41252,
                {41611, 41265, 41610},
                {41617, 41280, 41616},
                {41597, 41244, 41596},
                {41602, 41274, 41603},
                {41609, 41243},
                41273,
                41266,
                {41615, 41275, 41614},
                41278,
                41271,
                41277,
                41240,
                {41269, 41600, 41601},
                41253,
                41276,
                41272,
                41282,
                41283
            }
        },
        {name = "Crate Expectations", id = 11681, criteriaType = "QUEST_SINGLE", criteria = 45542},
        {name = "They See Me Rolling", id = 11607, criteriaType = "QUEST_SINGLE", criteria = 46175},
        {name = "Variety is the Spice of Life", id = 11189, criteriaType = "SPECIAL"}
    }

    -- Mounts
    data.mounts = {
        {
            name = "Maddened Chaosrunner",
            itemID = 152814,
            spellID = 253058,
            quest = {{trackingID = 48695, wqID = 48696}}
        },
        {
            name = "Crimson Slavermaw",
            itemID = 152905,
            spellID = 253661,
            quest = {{trackingID = 49183, wqID = 47561}}
        },
        {name = "Acid Belcher", itemID = 152904, spellID = 253662, quest = {{trackingID = 48721, wqID = 48740}}},
        {name = "Vile Fiend", itemID = 152790, spellID = 243652, quest = {{trackingID = 48821, wqID = 48835}}},
        {name = "Lambent Mana Ray", itemID = 152844, spellID = 253107, quest = {{trackingID = 48705, wqID = 48725}}},
        {
            name = "Biletooth Gnasher",
            itemID = 152903,
            spellID = 253660,
            quest = {{trackingID = 48810, wqID = 48465}, {trackingID = 48809, wqID = 48467}}
        },
        -- Egg
        {
            name = "Vibrant Mana Ray",
            itemID = 152842,
            spellID = 253106,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        },
        {
            name = "Felglow Mana Ray",
            itemID = 152841,
            spellID = 253108,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        },
        {
            name = "Scintillating Mana Ray",
            itemID = 152840,
            spellID = 253109,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        },
        {
            name = "Darkspore Mana Ray",
            itemID = 152843,
            spellID = 235764,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        }
    }

    -- Pets
    data.pets = {
        {
            name = "Grasping Manifestation",
            itemID = 153056,
            creatureID = 128159,
            quest = {{trackingID = 0, wqID = 48729}}
        },
        -- Egg
        {
            name = "Fel-Afflicted Skyfin",
            itemID = 153055,
            creatureID = 128158,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        },
        {
            name = "Docile Skyfin",
            itemID = 153054,
            creatureID = 128157,
            quest = {
                {trackingID = 48667, wqID = 48502},
                {trackingID = 48712, wqID = 48732},
                {trackingID = 48812, wqID = 48827}
            }
        },
        -- Emissary
        {name = "Thistleleaf Adventurer", itemID = 130167, creatureID = 99389, questID = 42170, emissary = true},
        {name = "Wondrous Wisdomball", itemID = 141348, creatureID = 113827, questID = 43179, emissary = true},
        -- Treasure Master Iks'reeged
        {name = "Scraps", itemID = 146953, creatureID = 120397, questID = 45379}
    }

    -- Toys
    data.toys = {
        {
            name = "Barrier Generator",
            itemID = 153183,
            quest = {{trackingID = 48704, wqID = 48724}, {trackingID = 48703, wqID = 48723}}
        },
        {name = "Micro-Artillery Controller", itemID = 153126, quest = {{trackingID = 0, wqID = 48829}}},
        {name = "Spire of Spite", itemID = 153124, quest = {{trackingID = 0, wqID = 48512}}},
        {name = "Yellow Conservatory Scroll", itemID = 153180, quest = {{trackingID = 48718, wqID = 48737}}},
        {name = "Red Conservatory Scroll", itemID = 153181, quest = {{trackingID = 48718, wqID = 48737}}},
        {name = "Blue Conservatory Scroll", itemID = 153179, quest = {{trackingID = 48718, wqID = 48737}}},
        {name = "Baarut the Brisk", itemID = 153193, quest = {{trackingID = 0, wqID = 48701}}},
        -- Treasure Master Iks'reeged
        {name = "Pilfered Sweeper", itemID = 147867, questID = 45379}
    }

    -- Terrors of the Shore
    -- Commander of Argus
end

-- BattleForAzeroth
do
    -- Battle for Azeroth
    local data = {
        name = _G.EXPANSION_NAME7
    }
    D.data[8] = data

    -- Achievements
    local trainer = {
        52009,
        52165,
        52218,
        52278,
        52297,
        52316,
        52325,
        52430,
        52471,
        52751,
        52754,
        52799,
        52803,
        52850,
        52856,
        52878,
        52892,
        52923,
        52938
    }

    data.achievements = {
        {name = "Adept Sandfisher", id = 13009, criteriaType = "QUEST_SINGLE", criteria = 51173, faction = "Horde"},
        {name = "Scourge of Zem'lan", id = 13011, criteriaType = "QUESTS", criteria = {{51763, 51783}}},
        {name = "Vorrik's Champion", id = 13014, criteriaType = "QUESTS", criteria = {51957, 51983}, faction = "Horde"},
        {
            name = "Revenge is Best Served Speedily",
            id = 13022,
            criteriaType = "QUEST_SINGLE",
            criteria = 50786,
            faction = "Horde"
        },
        {name = "It's Really Getting Out of Hand", id = 13023, criteriaType = "QUESTS", criteria = {{50559, 51127}}},
        {name = "Zandalari Spycatcher", id = 13025, criteriaType = "QUEST_SINGLE", criteria = 50717, faction = "Horde"},
        {
            name = "7th Legion Spycatcher",
            id = 13026,
            criteriaType = "QUEST_SINGLE",
            criteria = 50899,
            faction = "Alliance"
        },
        {name = "By de Power of de Loa!", id = 13035, criteriaType = "QUESTS", criteria = {{51178, 51232}}},
        {name = "Bless the Rains Down in Freehold", id = 13050, criteriaType = "QUESTS", criteria = {{53196, 52159}}},
        {
            name = "Kul Runnings",
            id = 13060,
            criteriaType = "QUESTS",
            criteria = {49994, 53188, 53189},
            faction = "Alliance"
        },
        {
            name = "Battle on Zandalar and Kul Tiras",
            id = 12936,
            criteriaType = "QUESTS",
            criteria = {
                52009,
                52126,
                52165,
                52218,
                52278,
                52297,
                52316,
                52325,
                52430,
                52455,
                52471,
                52751,
                52754,
                52779,
                52799,
                52803,
                52850,
                52856,
                52864,
                52878,
                52892,
                52923,
                52937,
                52938
            }
        },
        {
            name = "A Most Efficient Apocalypse",
            id = 13021,
            criteriaType = "QUEST_SINGLE",
            criteria = 50665,
            faction = "Horde"
        },
        -- Thanks NatalieWright
        {
            name = "Adventurer of Zuldazar",
            id = 12944,
            criteriaType = "QUESTS",
            criteria = {
                50864,
                50877,
                {51085, 51087},
                51081,
                {50287, 51374, 50866},
                50885,
                50863,
                50862,
                50861,
                50859,
                50845,
                50857,
                nil,
                50875,
                50874,
                nil,
                50872,
                50876,
                50871,
                50870,
                50869,
                50868,
                50867
            }
        },
        {
            name = "Adventurer of Vol'dun",
            id = 12943,
            criteriaType = "QUESTS",
            criteria = {
                51105,
                51095,
                51096,
                51117,
                nil,
                51118,
                51120,
                51098,
                51121,
                51099,
                51108,
                51100,
                51125,
                51102,
                51429,
                51103,
                51124,
                51107,
                51122,
                51123,
                51104,
                51116,
                51106,
                51119,
                51112,
                51113,
                51114,
                51115
            }
        },
        {
            name = "Adventurer of Nazmir",
            id = 12942,
            criteriaType = "QUESTS",
            criteria = {
                50488,
                50570,
                50564,
                nil,
                50490,
                50506,
                50568,
                50491,
                50492,
                50499,
                50496,
                50498,
                50501,
                nil,
                50502,
                50503,
                50505,
                50507,
                50566,
                50511,
                50512,
                nil,
                50513,
                50514,
                nil,
                50515,
                50516,
                50489,
                50519,
                50518,
                50509,
                50517
            }
        },
        {
            name = "Adventurer of Drustvar",
            id = 12941,
            criteriaType = "QUESTS",
            criteria = {
                51469,
                51505,
                51506,
                51508,
                51468,
                51972,
                nil,
                nil,
                nil,
                51897,
                51457,
                nil,
                51909,
                51507,
                51917,
                nil,
                51919,
                51908,
                51491,
                51512,
                51527,
                51461,
                51467,
                51528,
                51466,
                51541,
                51542,
                51884,
                51874,
                51906,
                51887,
                51989,
                51988
            }
        },
        {
            name = "Adventurer of Tiragarde Sound",
            id = 12939,
            criteriaType = "QUESTS",
            criteria = {
                51653,
                51652,
                51666,
                51669,
                51841,
                51665,
                51848,
                51842,
                51654,
                51662,
                51844,
                51664,
                51670,
                51895,
                nil,
                51659,
                51843,
                51660,
                51661,
                51890,
                51656,
                51893,
                51892,
                51651,
                51839,
                51891,
                51849,
                51894,
                51655,
                51847,
                nil,
                51657
            }
        },
        {
            name = "Adventurer of Stormsong Valley",
            id = 12940,
            criteriaType = "QUESTS",
            criteria = {
                52452,
                52315,
                51759,
                {51976, 51977, 51978},
                52476,
                51774,
                51921,
                nil,
                51776,
                52459,
                52321,
                51781,
                nil,
                51886,
                51779,
                51778,
                52306,
                52310,
                51901,
                51777,
                52301,
                nil,
                52463,
                nil,
                52328,
                51782, -- Captain Razorspine
                52299, -- Whiplash
                nil,
                52300,
                nil,
                52464,
                52309,
                52322,
                nil
            }
        },
        {name = "Sabertron Assemble", id = 13054, criteriaType = "QUESTS", criteria = {nil, 51977, 51978, 51976, 51974}},
        {name = "Drag Race", id = 13059, criteriaType = "QUEST_SINGLE", criteria = 53346, faction = "Alliance"},
        {
            name = "Unbound Monstrosities",
            id = 12587,
            criteriaType = "QUESTS",
            criteria = {52166, 52157, 52181, 52169, 52196, 136385}
        },
        {name = "Wide World of Quests", id = 13144, criteriaType = "SPECIAL"},
        {
            name = "Family Battler",
            id = 13279,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {id = 13280, criteriaType = "QUESTS", criteria = trainer},
                {id = 13270, criteriaType = "QUESTS", criteria = trainer},
                {id = 13271, criteriaType = "QUESTS", criteria = trainer},
                {id = 13272, criteriaType = "QUESTS", criteria = trainer},
                {id = 13273, criteriaType = "QUESTS", criteria = trainer},
                {id = 13274, criteriaType = "QUESTS", criteria = trainer},
                {id = 13281, criteriaType = "QUESTS", criteria = trainer},
                {id = 13275, criteriaType = "QUESTS", criteria = trainer},
                {id = 13277, criteriaType = "QUESTS", criteria = trainer},
                {id = 13278, criteriaType = "QUESTS", criteria = trainer}
            }
        },
        -- 8.1
        {name = "Upright Citizens", id = 13285, criteriaType = "QUEST_SINGLE", criteria = 53704, faction = "Alliance"},
        {
            name = "Scavenge like a Vulpera",
            id = 13437,
            criteriaType = "QUEST_SINGLE",
            criteria = 54415,
            faction = "Horde"
        },
        {name = "Pushing the Payload", id = 13441, criteriaType = "QUEST_SINGLE", criteria = 54505, faction = "Horde"},
        {
            name = "Pushing the Payload",
            id = 13440,
            criteriaType = "QUEST_SINGLE",
            criteria = 54498,
            faction = "Alliance"
        },
        {name = "Doomsoul Surprise", id = 13435, criteriaType = "QUEST_SINGLE", criteria = 54689, faction = "Horde"},
        {name = "Come On and Slam", id = 13426, criteriaType = "QUEST_SINGLE", criteria = 54512, faction = "Alliance"},
        {name = "Boxing Match", id = 13439, criteriaType = "QUESTS", criteria = {{54524, 54516}}, faction = "Alliance"},
        {name = "Boxing Match", id = 13438, criteriaType = "QUESTS", criteria = {{54524, 54516}}, faction = "Horde"},
        -- 8.1.5
        -- Circle, Square, Triangle
        {
            name = "Master Calligrapher",
            id = 13512,
            criteriaType = "QUESTS",
            criteria = {{55340, 55342}, {55264, 55343}, {55341, 55344}}
        },
        -- Mission Table
        -- Alliance
        {name = "Azeroth at War: The Barrens", id = 12896, criteriaType = "MISSION_TABLE", faction = "Alliance"},
        {name = "Azeroth at War: Kalimdor on Fire", id = 12899, criteriaType = "MISSION_TABLE", faction = "Alliance"},
        {name = "Azeroth at War: After Lordaeron", id = 12898, criteriaType = "MISSION_TABLE", faction = "Alliance"},
        -- Horde
        {name = "Azeroth at War: The Barrens", id = 12867, criteriaType = "MISSION_TABLE", faction = "Horde"},
        {name = "Azeroth at War: Kalimdor on Fire", id = 12870, criteriaType = "MISSION_TABLE", faction = "Horde"},
        {name = "Azeroth at War: After Lordaeron", id = 12869, criteriaType = "MISSION_TABLE", faction = "Horde"},
        -- 8.2
        {
            name = "Outside Influences",
            id = 13556,
            criteriaType = "QUEST_PIN",
            mapID = "1462",
            criteriaInfo = {
                [4] = {55658, 55672},
                [5] = {55658, 55688},
                [6] = {55658, 55717},
                [7] = {55658, 55718},
                [8] = {55658, 56049},
                [10] = {55658, 55469},
                [25] = {56552, 56558}
            }
        },
        {name = "Nazjatarget Eliminated", id = 13690},
        {name = "Puzzle Performer", id = 13764},
        -- criteriaType = "QUESTS", criteria= {56025, 56024, 56023, 56022, 56021, 56020, 56019, 56018, nil, 56008, 56007, 56009, 56006, 56003, 56010, 56011, 56014, 56016, 56015, 56013,  56012}},
        {name = "Periodic Destruction", id = 13699, criteriaType = "QUEST_FLAG", criteria = 55121}
    }

    -- Pets
    data.pets = {
        {name = "Vengeful Chicken", itemID = 160940, creatureID = 139372, quest = {{trackingID = 0, wqID = 51212}}},
        {
            name = "Rebuilt Gorilla Bot",
            itemID = 166715,
            creatureID = 149348,
            quest = {{trackingID = 0, wqID = 54272}},
            faction = "Alliance"
        },
        {
            name = "Rebuilt Mechanical Spider",
            itemID = 166723,
            creatureID = 149361,
            quest = {{trackingID = 0, wqID = 54273}},
            faction = "Horde"
        }
    }

    -- Toys
    data.toys = {
        {
            name = "Echoes of Rezan",
            itemID = 160509,
            quest = {{trackingID = 0, wqID = 50855}, {trackingID = 0, wqID = 50957}}
        },
        {name = "Toy Siege Tower", itemID = 163828, quest = {{trackingID = 0, wqID = 52847}}, faction = "Alliance"},
        {name = "Toy War Machine", itemID = 163829, quest = {{trackingID = 0, wqID = 52848}}, faction = "Horde"}
    }

    -- Mounts
    data.mounts = {
        {name = "Mollie", itemID = 174842, spellID = 298367, quest = {{wqID = 52196}}}
    }
end

-- Shadowlands
do
    -- Shadowlands
    local data = {
        name = _G.EXPANSION_NAME8
    }
    D.data[9] = data

    -- Achievements
    local trainer = {
        61883,
        61885,
        61886,
        61867,
        61868,
        61866,
        61787,
        61791,
        61784,
        61946,
        61948
    }

    data.achievements = {
        {name = "Tea Tales", id = 14233, criteriaType = "QUESTS", criteria = {59848, 59850, 59852, 59853}},
        {name = "Something's Not Quite Right....", id = 14671, criteriaType = "QUEST_SINGLE", criteria = 60739},
        {name = "A Bit of This, A Bit of That", id = 14672, criteriaType = "QUEST_SINGLE", criteria = 60475},
        {name = "Flight School Graduate", id = 14735, criteriaType = "QUESTS", criteria = {60844, 60858, 60911}},
        {
            name = "What Bastion Remembered",
            id = 14737,
            criteriaType = "QUEST_SINGLE",
            criteria = {
                59717,
                59705
            }
        },
        {name = "Aerial Ace", id = 14741, criteriaType = "QUEST_SINGLE", criteria = 60911},
        {name = "Breaking the Stratus Fear", id = 14762, criteriaType = "QUEST_SINGLE", criteria = 60858},
        {name = "Ramparts Racer", id = 14765, criteriaType = "QUEST_SINGLE", criteria = 59643},
        {name = "Parasoling", id = 14766, criteriaType = "QUEST_SINGLE", criteria = 59718},
        {name = "Caught in a Bat Romance", id = 14772, criteriaType = "QUEST_SINGLE", criteria = 60602},
        {name = "Friend of Ooz", id = 15055, criteriaType = "QUEST_SINGLE", criteria = 64016},
        {name = "Friend of Bloop", id = 15056, criteriaType = "QUEST_SINGLE", criteria = 64017},
        {name = "Friend of Plaguey", id = 15057, criteriaType = "QUEST_SINGLE", criteria = 63989},
        {
            name = "Battle in the Shadowlands",
            id = 14625,
            criteriaType = "QUESTS",
            criteria = {
                61949,
                61948,
                61947,
                61946,
                61886,
                61885,
                61883, -- Sylla
                61879,
                61870,
                61868,
                61867, -- Rotgut
                61866,
                61791,
                61787, -- Zolla
                61784,
                61783
            }
        },
        {
            name = "Adventures: Into the Breach",
            id = 14844,
            criteriaType = "MISSION_TABLE",
            criteria = {{2296, 2250}, {2251, 2297}, {2252, 2298}, {2299, 2253}, 2254, 2255, 2256, 2258, 2259, 2260}
        },
        {
            name = "Impressing Zo'Sorg",
            id = 14516,
            criteriaType = "QUESTS",
            criteria = {
                {59658},
                {59803},
                {59825},
                {60231}
            }
        },
        {
            name = "The World Beyond",
            id = 14758,
            criteriaType = "SPECIAL"
        },
        {
            name = "Family Exorcist",
            id = 14879,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {id = 14868, criteriaType = "QUESTS", criteria = trainer},
                {id = 14869, criteriaType = "QUESTS", criteria = trainer},
                {id = 14870, criteriaType = "QUESTS", criteria = trainer},
                {id = 14871, criteriaType = "QUESTS", criteria = trainer},
                {id = 14872, criteriaType = "QUESTS", criteria = trainer},
                {id = 14873, criteriaType = "QUESTS", criteria = trainer},
                {id = 14874, criteriaType = "QUESTS", criteria = trainer},
                {id = 14875, criteriaType = "QUESTS", criteria = trainer},
                {id = 14876, criteriaType = "QUESTS", criteria = trainer},
                {id = 14877, criteriaType = "QUESTS", criteria = trainer}
            }
        }
    }

    -- Pets
    data.pets = {
        {name = "Dal", itemID = 183859, creatureID = 171136, quest = {{trackingID = 0, wqID = 60655}}},
        {name = "Carpal", itemID = 183114, creatureID = 173847, source = {type = "ITEM", itemID = 183111}},
        {
            name = "Chompy",
            itemID = 186548,
            creatureID = 179230,
            source = {type = "ITEM", itemID = 186548}
        },
        {name = "Primordial Bogling", itemID = 180588, creatureID = 171121, quest = {{trackingID = 0, wqID = 59808}}}
    }

    -- Toys
    data.toys = {
        {name = "Tithe Collector's Vessel", itemID = 180947, source = {type = "ITEM", itemID = 180947}},
        {name = "Gormling in a Bag", itemID = 184487, source = {type = "ITEM", itemID = 184487}}
    }
end

-- Dragonflight
do
    -- Dragonflight
    local data = {
        name = _G.EXPANSION_NAME9
    }
    D.data[10] = data

    -- Achievements
    data.achievements = {
        {
            name = "Malicia's Challenge",
            id = 16589,
            criteriaType = "QUESTS",
            criteria = {
                { 67005 },
                { 70209 },
                { 70439 },
                { 69949 }
            }
        },
        {
            name = "A Champion's Tour: Dragon Isles",
            id = 16590,
            criteriaType = "QUESTS",
            criteria = {
                { 67005 },
                { 70209 },
                { 70439 },
                { 69949 }
            }
        },
        {
            name = "A Champion's Pursuit",
            id = 16599,
            criteriaType = "QUESTS",
            criteria = {
                { 72008 },
                { 72058 },
                { 72019 },
                { 71225 }
            }
        },
        {
            name = "Wildlife Photographer",
            id = 16560,
            criteriaType = "QUESTS",
            criteria = {
                { 70075, 70632 },
                { 70079, 70659 },
                { 70100 },
                { 70110, 70699 }
            }
        },
        {
            name = "A Legendary Album",
            id = 16570,
            criteriaType = "QUESTS",
            criteria = {
                { 70075 },
                { 70632 },
                { 70100 },
                { 70659 },
                { 70110 },
                { 70079 },
                { 70699 }
            }
        },
        {
            name = "Great Shots Galore!",
            id = 16568,
            criteriaType = "QUESTS",
            criteria = {
                {
                    70075,
                    70632,
                    70079,
                    70659,
                    70100,
                    70110,
                    70699
                }
            }
        },
        -- Grand Hunt
        {
            name = "Hunt Master",
            id = 16540,
            criteriaType = "AREA_POI",
            criteria = {
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7344, MapId = 1978 },
                { AreaPoiId = 7344, MapId = 1978 }
            }
        },
        {
            name = "The Disgruntled Hunter",
            id = 16542,
            criteriaType = "AREA_POI",
            criteria = {
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7342, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7343, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7345, MapId = 1978 },
                { AreaPoiId = 7344, MapId = 1978 },
                { AreaPoiId = 7344, MapId = 1978 }
            }
        },
        --
        -- Primal Storms
        {
            name = "Chasing Storms in The Waking Shores",
            id = 16468,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {
                    name = "Thunderstorms in The Waking Shores",
                    id = 16463,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7249, MapId = 2022 },
                            { AreaPoiId = 7253, MapId = 2022 },
                            { AreaPoiId = 7257, MapId = 2022 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Sandstorms in The Waking Shores",
                    id = 16465,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7250, MapId = 2022 },
                            { AreaPoiId = 7254, MapId = 2022 },
                            { AreaPoiId = 7258, MapId = 2022 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Firestorms in The Waking Shores",
                    id = 16466,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7251, MapId = 2022 },
                            { AreaPoiId = 7255, MapId = 2022 },
                            { AreaPoiId = 7259, MapId = 2022 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Snowstorms in The Waking Shores",
                    id = 16467,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7252, MapId = 2022 },
                            { AreaPoiId = 7256, MapId = 2022 },
                            { AreaPoiId = 7260, MapId = 2022 }
                        }
                    },
                    notAccountwide = true
                }
            }
        },
        {
            name = "Chasing Storms in the Ohn'ahran Plains",
            id = 16476,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {
                    name = "Thunderstorms in the Ohn'ahran Plains",
                    id = 16475,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7221, MapId = 2023 },
                            { AreaPoiId = 7225, MapId = 2023 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Sandstorms in the Ohn'ahran Plains",
                    id = 16477,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7222, MapId = 2023 },
                            { AreaPoiId = 7226, MapId = 2023 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Firestorms in the Ohn'ahran Plains",
                    id = 16478,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7223, MapId = 2023 },
                            { AreaPoiId = 7227, MapId = 2023 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Snowstorms in the Ohn'ahran Plains",
                    id = 16479,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7224, MapId = 2023 },
                            { AreaPoiId = 7228, MapId = 2023 }
                        }
                    },
                    notAccountwide = true
                }
            }
        },
        {
            name = "Chasing Storms in The Azure Span",
            id = 16484,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {
                    name = "Thunderstorms in The Azure Span",
                    id = 16480,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7237, MapId = 2024 },
                            { AreaPoiId = 7233, MapId = 2024 },
                            { AreaPoiId = 7229, MapId = 2024 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Sandstorms in The Azure Span",
                    id = 16481,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7238, MapId = 2024 },
                            { AreaPoiId = 7234, MapId = 2024 },
                            { AreaPoiId = 7230, MapId = 2024 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Firestorms in The Azure Span",
                    id = 16482,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7239, MapId = 2024 },
                            { AreaPoiId = 7235, MapId = 2024 },
                            { AreaPoiId = 7231, MapId = 2024 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Snowstorms in The Azure Span",
                    id = 16483,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7240, MapId = 2024 },
                            { AreaPoiId = 7236, MapId = 2024 },
                            { AreaPoiId = 7232, MapId = 2024 }
                        }
                    },
                    notAccountwide = true
                }
            }
        },
        {
            name = "Chasing Storms in Thaldraszus",
            id = 16489,
            criteriaType = "ACHIEVEMENT",
            criteria = {
                {
                    name = "Thunderstorms in Thaldraszus",
                    id = 16485,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7298, MapId = 2025 },
                            { AreaPoiId = 7245, MapId = 2025 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Sandstorms in Thaldraszus",
                    id = 16486,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7299, MapId = 2025 },
                            { AreaPoiId = 7246, MapId = 2025 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Firestorms in Thaldraszus",
                    id = 16487,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7300, MapId = 2025 },
                            { AreaPoiId = 7247, MapId = 2025 }
                        }
                    },
                    notAccountwide = true
                },
                {
                    name = "Snowstorms in Thaldraszus",
                    id = 16488,
                    criteriaType = "AREA_POI",
                    criteria = {
                        {
                            { AreaPoiId = 7301, MapId = 2025 },
                            { AreaPoiId = 7248, MapId = 2025 }
                        }
                    },
                    notAccountwide = true
                }
            }
        },
        --
        {
            name = "Battle on the Dragon Isles",
            id = 16464,
            criteriaType = "QUESTS",
            criteria = {
                71206,
                71202,
                66588,
                71145,
                71166,
                66551,
                71140,
                71180
            }
        },
        {
            name = "Battle on the Dragon Isles II",
            id = 17406,
            criteriaType = "QUESTS",
            criteria = {
                74841,
                74838,
                74835,
                74794,
                74840,
                74837,
                74836,
                74792
            }
        },
        {
            name = "Global Swarming",
            id = 17541,
            criteriaType = "QUESTS",
            criteria = {
                73146,
                73147,
                73148,
                73149
            }
        },
        {
            name = "Battle in Zaralek Cavern",
            id = 17880,
            criteriaType = "QUESTS",
            criteria = {
                75680,
                75750,
                75834,
                75835
            }
        },
        {
            name = "Friends In Feather",
            id = 19293,
            criteriaType = "QUEST_SINGLE",
            criteria = 78370
        },
        {
            name = "Goggle Wobble",
            id = 19791,
            criteriaType = "QUESTS",
            criteria = {
                78820,
                78931,
                78616
            }
        },
        {
            name = "When a Rock is Just a Rock",
            id = 19786,
            criteriaType = "QUESTS",
            criteria = {
                { 78645, 78661, 78663 }
            }
        },
        {
            name = "Clued In",
            id = 19787,
            criteriaType = "QUESTS",
            criteria = {
                { 77424, 76587, 76734, 76739, 77362 }
            }
        },
        {
            name = "Just One More Thing",
            id = 19792,
            criteriaType = "QUESTS",
            criteria = {

                77424, -- Lost Atheneum
                76587, -- The Riverbed
                76734, -- Igira's Watch
                76739, -- Gaze of Neltharion
                76911, -- Concord Observatory
                77362  -- Winglord's Perch
            }
        },
        {
            name = "Taking From Nature",
            id = 16553,
            criteriaType = "AREA_POI",
            criteria = {
                { AreaPoiId = 7086, MapId = 2022 },
                { AreaPoiId = 7266, MapId = 2024 },
                { AreaPoiId = 7270, MapId = 2023 },
                { AreaPoiId = 7271, MapId = 2025 },
                { AreaPoiId = 7272, MapId = 2024 }
            }
        },
    }

    -- Pets
    data.pets = {
        {
            name = "Wildfire",
            itemID = 202412,
            creatureID = 200771,
            quest = { { trackingID = 0, wqID = 73148 } }
        },
        {
            name = "Vortex",
            itemID = 202413,
            creatureID = 200769,
            quest = { { trackingID = 0, wqID = 73146 } }
        },
        {
            name = "Tremblor",
            itemID = 202411,
            creatureID = 200770,
            quest = { { trackingID = 0, wqID = 73147 } }
        },
        {
            name = "Flow",
            itemID = 202407,
            creatureID = 200772,
            quest = { { trackingID = 0, wqID = 73149 } }
        },
        {
            name = "Time-Lost Vorquin Foal",
            itemID = 193855,
            creatureID = 191298,
            quest = { { trackingID = 0, wqID = 74378 } }
        }
    }

    -- Toys
    data.toys = {
        {
            name = "Glutinous Glitterscale Glob",
            itemID = 205688,
            quest = { { trackingID = 0, wqID = 75343 } }
        },
        {
            name = "Chasing Storm",
            itemID = 202020,
            quest = { { trackingID = 0, wqID = 74378 } }
        }
    }

    -- Mounts
    data.mounts = {
        {
            name = "Skyskin Hornstrider",
            itemID = 192800,
            spellID = 352926,
            quest = { { trackingID = 0, wqID = 74378 } }
        }
    }
end

-- WarWithin
do
    -- War Within
    local data = {
        name = _G.EXPANSION_NAME10
    }
    D.data[11] = data

    -- Achievements
    local trainer = {
        82293,
        82292,
        82294,
        82295

    }

    data.achievements = {
        {
            name = "Worm Theory",
            id = 40869,
            criteriaType = "QUESTS",
            criteria = {
                { 82324 },
                { 79959 },
                { 79958 }
            }
        },
        {
            name = "I Only Need One Trip",
            id = 40623,
            criteriaType = "QUESTS",
            criteria = {
                { 82580 }
            }
        },
        {
            name = "For the Collective",
            id = 40630,
            criteriaType = "QUESTS",
            criteria = {
                { 82580 }
            }
        },
        {
            name = "Hanging Tight",
            id = 40507,
            criteriaType = "QUESTS",
            criteria = {
                { 83101 }
            }
        },
        {
            name = "Children's Entertainer",
            id = 40150,
            criteriaType = "QUESTS",
            criteria = {
                { 82288 },
                { 82288 },
                { 82288 },
                { 82288 },
                { 82288 },
                { 82288 },
                { 82288 },
                { 82288 }
            }
        },
        {
            name = "Mine Poppin'",
            id = 40843,
            criteriaType = "QUESTS",
            criteria = {
                { 82468 }
            }
        },
        {
            name = "Never Enough",
            id = 40082,
            criteriaType = "QUESTS",
            criteria = {
                { 82120 }
            }
        },
        {
            name = "A Champion's Tour: The War Within",
            id = 40088,
            criteriaType = "QUESTS",
            criteria = {
                { 80395 },
                { 80394 },
                { 80208 },
                { 80323 },
                { 80412 },
                { 81622 },
                { 80409 },
                { 80457 }
            }
        },
        {
            name = "Unbound Battle",
            id = 40087,
            criteriaType = "QUESTS",
            criteria = {
                { 80395 },
                { 80394 },
                { 80208 },
                { 80323 },
                { 80412 },
                { 81622 },
                { 80409 },
                { 80457 }
            }
        },
        {
            name = "Battle on Khaz Algar",
            id = 40153,
            criteriaType = "QUESTS",
            criteria = {
                { 82291 }, -- Awakened Custodian
                { 82300 }, -- Haywire Servobot
                { 82298 }, -- Guttergunk
                { 82292 }, -- Collector Dyna
                { 82297 }, -- Zadeu
                { 82293 }, -- Friendhaver Grem
                { 82294 }, -- Kyrie
                { 82295 }  -- Ziriak
            }
        }
    }

    -- Miscellaneous
    data.miscellaneous = {
        {
            name = "Special Assignment",
            criteriaType = "AREA_POI",
            criteria = {
                { AreaPoiID = 7823, MapId = 2248 }, -- Special Assignment: Cinderbee Surge
                { AreaPoiID = 7824, MapId = 2248 }, -- Special Assignment: Titanic Resurgence
                { AreaPoiID = 7825, MapId = 2214 }, -- Special Assignment: Shadows Below
                { AreaPoiID = 7826, MapId = 2214 }, -- Special Assignment: When the Deeps Stir
                { AreaPoiID = 7827, MapId = 2215 }, -- Special Assignment: Lynx Rescue
                { AreaPoiID = 7828, MapId = 2215 }, -- Special Assignment: Rise of the Colossals
                { AreaPoiID = 7829, MapId = 2255 }, -- Special Assignment: Bombs from Behind
                { AreaPoiID = 7830, MapId = 2255 }, -- Special Assignment: A Pound of Cure
                { AreaPoiID = 7886, MapId = 2248 }, -- Special Assignment: Titanic Resurgence
                { AreaPoiID = 7887, MapId = 2248 }  -- Special Assignment: Titanic Resurgence
            }
        },
    }
end

-- Midnight
do
    -- Midnight
    local data = {
        name = _G.EXPANSION_NAME11
    }

    D.data[12] = data

    -- World Quest achievements
    --
    -- For achievements whose criteria expose quest IDs through
    -- GetAchievementCriteriaInfo(), no explicit criteriaType is needed. The
    -- achievement registrar will map only unfinished criteria to their WQs.
    --
    -- Some one-off challenge achievements expose a spell/internal credit rather
    -- than the WQ quest ID, so those use QUEST_SINGLE explicitly.
    data.achievements = {
        {
            name = "No Time to Paws",
            id = 61219,
            criteriaType = "QUEST_SINGLE",
            criteria = 92085 -- Claw Enforcement
        },
        {
            name = "Lysikas Would Be Proud",
            id = 62105,
            criteriaType = "QUEST_SINGLE",
            criteria = 94743 -- Special Assignment: Precision Excision
        },
        {
            name = "A Stack of Snacks",
            id = 63633,
            criteriaType = "QUEST_SINGLE",
            criteria = 94967 -- Ki'clak Snack Attack
        },

        -- Slayer's Rise PvP World Quests.
        -- Blizzard exposes the individual WQ IDs as achievement criteria.
        {
            name = "Investigating the Rise",
            id = 61225
        },
        {
            name = "Uprising",
            id = 61226
        },

        -- Val / Naigtal Showdown World Quests.
        -- These rotate quickly, so use Blizzard's live achievement criteria
        -- instead of duplicating a brittle static quest-ID list here.
        {
            name = "Showdown Success: Val",
            id = 62880
        },
        {
            name = "Showdown Success: Naigtal",
            id = 62882
        }
    }
end

-- Zones with world quests, per expansion
D.ZoneIDList = {
    [7] = {
        619, -- Broken Isles
        627, -- Dalaran
        630, -- Azsuna
        641, -- Val'sharah
        650, -- Highmountain
        -- 625, -- Dalaran
        680, -- Suramar
        634, -- Stormheim
        646, -- Broken Shore
        790, -- Eye of Azshara
        885,
        830,
        882
    },
    [8] = {
        14, -- Arathi Highlands
        62, -- Darkshore
        875,
        876,
        862,
        863,
        864,
        895,  -- Tiragarde Sound
        942,
        896,  -- Drustvar
        1161, -- Boralus
        1165, -- Dazar'alor
        1355, -- Nazjatar
        1462, -- Mechagon
        1527, -- Uldum
        1530  -- Vale of Eternal Blossoms
    },
    [9] = {
        1525, -- Revendreth
        1533, -- Bastion
        1536, -- Maldraxxus
        1565, -- Ardenweald
        1543, -- The Maw
        1961, -- Korthia
        1970  -- Zereth Mortis
    },
    [10] = {
        2022, -- The Waking Shores
        2023, -- Ohn'ahran Plains
        2024, -- The Azure Span	Zone
        2025, -- Thaldraszus Zone
        1978, -- Dragon Isles
        2085, -- Primalist Tomorrow
        2112, -- Valdrakken
        2151, -- The Forbidden Reach
        2133, -- Zaralek Cavern
        2200  -- Emerald Dream
    },
    [11] = {
        2213, -- City of Threads
        2214, -- Ringing Deeps
        2215, -- Hallowfall
        2216, -- City of Threads - Lower
        2248, -- Isle of Dorn
        2255, -- Azj-Kahet
        2256, -- Azj-Kahet - Lower
        2339, -- Dornogal
        2369, -- Siren Isle
        2346, -- Undermine
        2371, -- K'aresh
        2472, -- Tazavesh (open-world K'aresh hub)
    },
    [12] = {
        2395, -- Eversong Woods
        2413, -- Harandar
        2437, -- Zul'Aman
        2405, -- Voidstorm
        2393, -- Silvermoon City
        2424, -- Isle of Quel'Danas
        2541, -- The Arcantina
        2444, -- Slayer's Rise
        2536, -- Atal'Aman
        2576, -- The Den
        2599, -- Val
        2600, -- Naigtal
        2512, -- The Coiled Isle
},
}
