local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

-- A collection of common class-specific spell proc (glow) IDs for suggestions.
-- The UI will map these IDs to names and icons automatically via C_Spell.
Triggers.ClassGlowSpells = {
    ["DEATHKNIGHT"] = {
        51124,  -- Killing Machine
        59052,  -- Rime
        49530,  -- Sudden Doom
    },
    ["DEMONHUNTER"] = {
        258920, -- Immolation Aura (Proc)
        390142, -- Initiative
    },
    ["DRUID"] = {
        16870,  -- Clearcasting (Omen of Clarity)
        279541, -- Bloodtalons
        213708, -- Galactic Guardian
        93400,  -- Shooting Stars
    },
    ["EVOKER"] = {
        359618, -- Essence Burst
        369299, -- Burnout
    },
    ["HUNTER"] = {
        194594, -- Lock and Load
        323326, -- Deathblow
        259388, -- Mongoose Bite
        260242, -- Precise Shots
    },
    ["MAGE"] = {
        48108,  -- Hot Streak!
        48107,  -- Heating Up
        190446, -- Brain Freeze
        276815, -- Clearcasting
    },
    ["MONK"] = {
        116645, -- Teachings of the Monastery
        322106, -- Dance of Chi-Ji
    },
    ["PALADIN"] = {
        234108, -- Art of War
        54149,  -- Infusion of Light
        85416,  -- Grand Crusader
        223819, -- Divine Purpose
    },
    ["PRIEST"] = {
        114255, -- Surge of Light
        375981, -- Shadowy Insight
    },
    ["ROGUE"] = {
        121153, -- Blindside
        195627, -- Opportunity (Pistol Shot)
    },
    ["SHAMAN"] = {
        344179, -- Maelstrom Weapon
        77762,  -- Lava Surge
        201846, -- Stormbringer
    },
    ["WARLOCK"] = {
        108558, -- Nightfall
        264173, -- Demonic Core
        387384, -- Backlash
    },
    ["WARRIOR"] = {
        280776, -- Sudden Death
        50227,  -- Sword and Board
        46916,  -- Bloodsurge
        7384,   -- Overpower!
    },
}
