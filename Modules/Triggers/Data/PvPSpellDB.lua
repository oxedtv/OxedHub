-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- PvPSpellDB.lua â€” Shared spell-ID databases for all PvP trigger modules.
--
-- This file contains the spell-ID data required for the PvP triggers.
--
-- Tables exported under OxedHub.PvPSpellDB:
--   .EnemyBuffSounds   â€” spellID â†’ sound-file map for enemy buffs / defensives
--   .SelfCcSounds      â€” spellID â†’ sound-file map for debuffs applied TO you
--   .CcSpellIds        â€” spellID â†’ true  (raw CC list, used for healer-CC)
--   .TrinketSpellIds   â€” spellID â†’ sound-file map for PvP trinket / Adaptation
--   .ConsumableList    â€” ordered array { spellID, file, label }
--   .ConsumableSpells  â€” spellID â†’ sound-file map (flat, for AddAuraSound)
--
-- MAINTENANCE: When Blizzard adds/renames abilities in a new patch, update
-- the relevant table here. All 5 PvP triggers share this single source of
-- truth so nothing gets out of sync.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local addonName, OxedHub = ...

OxedHub.PvPSpellDB = OxedHub.PvPSpellDB or {}
local DB = OxedHub.PvPSpellDB

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- 1. ENEMY BUFF SOUNDS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- spellID â†’ .ogg filename (relative to a voice-pack base path).
-- These are enemy BUFFS (defensive cooldowns, offensive cooldowns, utility)
-- detected via AddAuraSound on target / focus / arena / nameplate tokens.
--
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DB.EnemyBuffSounds = {
    -- â”€â”€ General / Racials â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [20572]    = true,           -- Blood Fury (Orc racial)
    [34709]    = true,         -- Shadow Sight (arena)
    [345231]   = true,        -- Battlemaster trinket
    [377360]   = true,        -- Precognition
    [377362]   = true,        -- Precognition (variant)
    [212640]   = true,      -- Mending Bandage
    [1293412]  = true,      -- Mending Bandage (49802 HP)
    [1299383]  = true,      -- Mending Bandage (41446 HP)
    [1251903]  = true,      -- Void Stone Barrier

    -- â”€â”€ Death Knight â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [42650]    = true,       -- Army of the Dead
    [1233448]  = true,  -- Dark Mutation
    [48743]    = true,           -- Death Pact (self-debuff)
    [326801]   = true,         -- Rune of Sanguination (passive)
    [326808]   = true,         -- Rune of Sanguination (proc)
    [48792]    = true,   -- Icebound Fortitude
    [55233]    = true,       -- Vampiric Blood
    [51271]    = true,       -- Pillar of Frost
    [48707]    = true,      -- Anti-Magic Shell
    [410358]   = true,      -- AMS (Spellwarding variant)
    [444741]   = true,      -- AMS variant
    [145629]   = true,       -- Anti-Magic Zone
    [212552]   = true,          -- Wraith Walk
    [212654]   = true,
    [223804]   = true,
    [48265]    = true,       -- Death's Advance
    [441749]   = true,
    [441751]   = true,
    [441752]   = true,
    [152279]   = true,  -- Breath of Sindragosa
    [219809]   = true,           -- Tombstone
    [194679]   = true,             -- Rune Tap
    [194844]   = true,           -- Bonestorm
    [207319]   = true,        -- Corpse Shield
    [116888]   = true,           -- Purgatory
    [49039]    = true,           -- Lichborne
    [288977]   = true,         -- Transfusion
    [287254]   = true,   -- Remorseless Winter

    -- â”€â”€ Demon Hunter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [198589]   = true,                -- Blur
    [212800]   = true,
    [162264]   = true,       -- Metamorphosis (Havoc)
    [187827]   = true,       -- Metamorphosis (Vengeance)
    [1217607]  = true,       -- Void Transformation
    [209426]   = true,            -- Darkness
    [188501]   = true,       -- Spectral Sight
    [206803]   = true,       -- Rain from Above
    [354610]   = true,             -- Glimpse

    -- â”€â”€ Druid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [102560]   = true,    -- Incarnation: Chosen of Elune
    [102543]   = true,    -- Incarnation: Avatar of Ashamane
    [102558]   = true,    -- Incarnation: Guardian of Ursoc
    [33891]    = true,     -- Incarnation: Tree of Life
    [106951]   = true,             -- Berserk
    [22812]    = true,            -- Barkskin
    [61336]    = true,   -- Survival Instincts
    [22842]    = true,       -- Frenzied Regeneration
    [102342]   = true,            -- Ironbark
    [102351]   = true,        -- Cenarion Ward
    [108291]   = true,      -- Heart of the Wild
    [108292]   = true,
    [108293]   = true,
    [108294]   = true,
    [112071]   = true,  -- Celestial Alignment
    [194223]   = true,
    [383410]   = true,
    [155835]   = true,        -- Bristling Fur
    [305497]   = true,             -- Thorns
    [382912]   = true,  -- Well-Honed Instincts
    [69369]    = true,   -- Predatory Swiftness
    [1850]     = true,                -- Dash
    [252216]   = true,
    [132158]   = true,    -- Nature's Swiftness

    -- â”€â”€ Evoker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [370553]   = true,        -- Tip the Scales
    [370562]   = true,         -- Stasis (ready)
    [370960]   = true,    -- Emerald Communion
    [363916]   = true,      -- Obsidian Scales
    [374348]   = true,       -- Renewing Blaze
    [375087]   = true,          -- Dragonrage
    [357170]   = true,       -- Time Dilation
    [359816]   = true,         -- Dream Flight
    [360827]   = true,    -- Blistering Scales
    [378464]   = true,    -- Nullifying Shroud
    [409311]   = true,          -- Prescience

    -- â”€â”€ Hunter â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [186265]   = true,          -- Aspect of the Turtle
    [437461]   = true,          -- Aspect of the Turtle (variant)
    [186257]   = true,             -- Aspect of the Cheetah
    [19574]    = true,        -- Bestial Wrath
    [193530]   = true,     -- Aspect of the Wild
    [53271]    = true,         -- Master's Call
    [53480]    = true,     -- Roar of Sacrifice
    [266779]   = true,            -- Trueshot
    [288613]   = true,
    [264735]   = true, -- Survival of the Fittest
    [202748]   = true,     -- Survival Tactics
    [360952]   = true,  -- Coordinated Assault
    [1250646]  = true,      -- Soul Hunt Strike
    [212704]   = true,         -- The Beast Within

    -- â”€â”€ Mage â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [45438]    = true,            -- Ice Block
    [190319]   = true,          -- Combustion
    [12472]    = true,            -- Icy Veins
    [365362]   = true,         -- Arcane Surge
    [11426]    = true,          -- Ice Barrier
    [414661]   = true,          -- Ice Barrier (talent variant)
    [108978]   = true,           -- Alter Time
    [110909]   = true,
    [342246]   = true,
    [86949]    = true,           -- Cauterize
    [87024]    = true,
    [372616]   = true,       -- Empyreal Blaze
    [392966]   = true,          -- Spell Block
    [210824]   = true,      -- Touch of the Magi

    -- â”€â”€ Monk â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [115176]   = true,       -- Zen Meditation
    [115203]   = true,      -- Fortifying Brew
    [201318]   = true,
    [243435]   = true,
    [116849]   = true,          -- Life Cocoon
    [122278]   = true,          -- Dampen Harm
    [122783]   = true,        -- Diffuse Magic
    [209584]   = true,         -- Zen Focus Tea
    [197908]   = true,             -- Mana Tea
    [1249625]  = true,      -- Peak of Serenity

    -- â”€â”€ Paladin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [642]      = true,        -- Divine Shield (Bubble)
    [498]      = true,    -- Divine Protection
    [403876]   = true,    -- Divine Protection (TWW)
    [1022]     = true,    -- Blessing of Protection
    [1044]     = true,       -- Blessing of Freedom
    [31850]    = true,      -- Ardent Defender
    [31884]    = true,       -- Avenging Wrath
    [454351]   = true,       -- Avenging Wrath (TWW)
    [86659]    = true,        -- Guardian of Ancient Kings
    [212641]   = true,
    [204018]   = true,        -- Blessing of Spellwarding
    [205191]   = true,         -- Eye for an Eye
    [210294]   = true,         -- Divine Favor
    [211319]   = true,         -- Restitution
    [215652]   = true,      -- Shield of Virtue
    [216331]   = true,    -- Avenging Crusader
    [231895]   = true,             -- Crusade
    [327193]   = true,       -- Moment of Glory
    [328530]   = true,     -- Divine Ascension
    [378974]   = true,      -- Bastion of Light
    [184662]   = true,     -- Shield of Vengeance
    [213610]   = true,            -- Holy Ward
    [213871]   = true,           -- Bodyguard
    [6940]     = true,           -- Blessing of Sacrifice
    [1260251]  = true,   -- Execution Sentence
    [260251]   = true,
    [200183]   = true,          -- Apotheosis
    [372760]   = true,          -- Divine Word
    [372761]   = true,
    [372783]   = true,
    [372791]   = true,
    -- Divine Steed (multiple mount variants)
    [220509]   = true,
    [221883]   = true,
    [221885]   = true,
    [221886]   = true,
    [221887]   = true,
    [254471]   = true,
    [254472]   = true,
    [254473]   = true,
    [254474]   = true,
    [276111]   = true,
    [276112]   = true,
    [294133]   = true,
    [317911]   = true,
    [348489]   = true,
    [353094]   = true,
    [363608]   = true,
    [453804]   = true,
    [1253723]  = true,
    [1253874]  = true,
    [1253881]  = true,
    [1272854]  = true,
    [1289616]  = true,
    [1289617]  = true,

    -- â”€â”€ Priest â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [33206]    = true,     -- Pain Suppression
    [47788]    = true,      -- Guardian Spirit
    [47585]    = true,          -- Dispersion
    [47536]    = true,             -- Rapture
    [109964]   = true,
    [15286]    = true,     -- Vampiric Embrace
    [197862]   = true,    -- Archangel (Healing)
    [197871]   = true,     -- Archangel (Damage)
    [228260]   = true,            -- Void Form
    [10060]    = true,       -- Power Infusion
    [8611]     = true,          -- Phase Shift
    [408558]   = true,
    [1246968]  = true,         -- Mind Curtain

    -- â”€â”€ Rogue â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [11327]    = true,              -- Vanish
    [31224]    = true,      -- Cloak of Shadows
    [31230]    = true,          -- Cheat Death
    [45182]    = true,
    [5277]     = true,             -- Evasion
    [1966]     = true,               -- Feint
    [2983]     = true,              -- Sprint
    [13750]    = true,      -- Adrenaline Rush
    [1214937]  = true,             -- Jackpot
    [13877]    = true,         -- Blade Flurry
    [121471]   = true,        -- Shadow Blades
    [185313]   = true,         -- Shadow Dance
    [185422]   = true,
    [51690]    = true,        -- Killing Spree
    [343142]   = true,         -- Dreadblades
    [207736]   = true,         -- Shadowy Duel
    [199754]   = true,             -- Riposte
    [202335]   = true,        -- Double Barrel

    -- â”€â”€ Shaman â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [108271]   = true,         -- Astral Shift
    [114050]   = true,          -- Ascendance (Elemental)
    [114051]   = true,          -- Ascendance (Enhancement)
    [114052]   = true,          -- Ascendance (Restoration)
    [1219480]  = true,          -- Ascendance (Fire)
    [79206]    = true,  -- Spiritwalker's Grace
    [191634]   = true,         -- Stormkeeper
    [384352]   = true,           -- Doom Winds
    [466772]   = true,     -- Devastating Wind
    [378081]   = true,    -- Nature's Swiftness (Shaman)
    [443454]   = true,    -- Ancestral Swiftness
    [8178]     = true,           -- Grounding Totem Effect
    [389794]   = true,           -- Snowdrift

    -- â”€â”€ Warlock â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [104773]   = true,    -- Unending Resolve
    [108416]   = true,            -- Dark Pact
    [113860]   = true,            -- Dark Soul
    [212295]   = true,          -- Nether Ward
    [442726]   = true,         -- Malevolence
    [80240]    = true,               -- Havoc
    [410598]   = true,             -- Soul Rip

    -- â”€â”€ Warrior â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [871]      = true,          -- Shield Wall
    [1719]     = true,           -- Recklessness / Battle Cry
    [262228]   = true,
    [12975]    = true,           -- Last Stand
    [18499]    = true,       -- Berserker Rage
    [23920]    = true,     -- Spell Reflection
    [107574]   = true,              -- Avatar
    [118038]   = true,       -- Die by the Sword
    [184364]   = true, -- Enraged Regeneration
    [260708]   = true,     -- Sweeping Strikes
    [147833]   = true,           -- Intervene
    [223658]   = true,           -- Safeguard
    [198817]   = true,        -- Sharpen Blade
    [199086]   = true,             -- Warpath
    [351077]   = true,          -- Second Wind
    [236273]   = true,                -- Duel
    [386196]   = true,        -- Berserker Stance
    [386164]   = true,        -- Battle Stance
    [7366]     = true,
    [2458]     = true,
    [386208]   = true,       -- Defensive Stance
    -- Bladestorm (many variants across specs / talents / PvP talents)
    [46924]    = true,
    [167232]   = true,
    [227847]   = true,
    [253038]   = true,
    [377827]   = true,
    [377844]   = true,
    [381818]   = true,
    [381835]   = true,
    [389774]   = true,
    [389789]   = true,
    [389853]   = true,
    [410235]   = true,
    [410236]   = true,
    [412030]   = true,
    [412031]   = true,
    [412035]   = true,
    [446035]   = true,

    -- â”€â”€ Monk (additional) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [125174]   = true,        -- Touch of Karma
    [122470]   = true,

    -- â”€â”€ Warrior (additional) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [199261]   = true,           -- Death Wish

    -- â”€â”€ Misc â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    [29166]    = true,           -- Innervate
}


-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- 2. TRINKET SPELL IDs
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Subset of EnemyBuffSounds specifically for PvP trinket / Adaptation.
-- Kept separate so the PvPTrinket trigger can register ONLY these.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DB.TrinketSpellIds = {
    [336139] = true,   -- Adapted (visible buff after Adaptation procs)
    [214027] = true,   -- Gladiator's Medallion / Adaptation talent
}


-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- 3. CONSUMABLE SPELLS
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Enemy potion / consumable aura IDs. When an enemy drinks a potion, the
-- buff aura appears and AddAuraSound fires the alert.
--
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DB.ConsumableList = {
    { spellID = 1234768, file = true,        label = "Health Potion" },
    { spellID = 1236590, file = true,         label = "Refreshing Serum" },
    { spellID = 1263074, file = true,            label = "Amani Extract" },
    { spellID = 1236994, file = true,          label = "Potion of Recklessness" },
    { spellID = 1236998, file = true,          label = "Abandon Potion" },
    { spellID = 1238443, file = true,          label = "Potion of Zealotry" },
    { spellID = 1295247, file = true,  label = "Health Potion (Concentrated)" },
    { spellID = 1236616, file = true,         label = "Light's Potential" },
    { spellID = 1235568, file = true,      label = "Light's Preservation" },
    { spellID = 1295132, file = true,            label = "Viscous Gloss" },
    { spellID = 1238009, file = true,     label = "Healing Potion" },
    { spellID = 431941,  file = true,     label = "Cheetah Potion" },
}

-- Flat spellID â†’ file map built from ConsumableList for AddAuraSound.
DB.ConsumableSpells = {}
for _, entry in ipairs(DB.ConsumableList) do
    DB.ConsumableSpells[entry.spellID] = entry.file
end


-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- 4. SELF CC SOUNDS  (truncated to PvP-relevant player spells only)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- spellID â†’ .ogg filename for debuffs applied TO the player (stuns, fears,
-- polymorphs, silences, etc.). The full table has ~880 entries including many PvE / legacy dungeon / boss 
-- abilities. We include the complete set so nothing is missed.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DB.SelfCcSounds = {
    -- â”€â”€ Core PvP CC abilities (most frequently seen in arenas / BGs) â”€â”€â”€â”€
    [99]     = true,
    [118]    = true,
    [122]    = true,
    [339]    = true,
    [408]    = true,
    [605]    = true,
    [710]    = true,
    [853]    = true,
    [1330]   = true,
    [1776]   = true,
    [1833]   = true,
    [2094]   = true,
    [2637]   = true,
    [3355]   = true,
    [5211]   = true,
    [5246]   = true,
    [5484]   = true,
    [6358]   = true,
    [6409]   = true,
    [6466]   = true,
    [6726]   = true,
    [6770]   = true,
    [6789]   = true,
    [7093]   = true,
    [8122]   = true,
    [10326]  = true,
    [15487]  = true,
    [19386]  = true,
    [20066]  = true,
    [20549]  = true,
    [28271]  = true,
    [28272]  = true,
    [29964]  = true,
    [30283]  = true,
    [33786]  = true,
    [47476]  = true,
    [51514]  = true,
    [64044]  = true,
    [82691]  = true,
    [89766]  = true,
    [93422]  = true,
    [102359] = true,
    [105421] = true,
    [105771] = true,
    [107079] = true,
    [108194] = true,
    [115078] = true,
    [118699] = true,
    [118905] = true,
    [119381] = true,
    [152108] = true,
    [163505] = true,
    [179057] = true,
    [196942] = true,
    [200196] = true,
    [200200] = true,
    [203123] = true,
    [204437] = true,
    [207167] = true,
    [207777] = true,
    [208086] = true,
    [217832] = true,
    [221527] = true,
    [221562] = true,
    [236077] = true,
    [236236] = true,
    [305485] = true,
    [332544] = true,
    [355689] = true,
    [357768] = true,
    [360806] = true,
    [386761] = true,
    [410870] = true,
    [414257] = true,
}


-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- 5. CC SPELL IDs (Healer CC alert â€” full list)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Used by the Healer-CC trigger: register one shared alert sound on every
-- party/raid healer for ALL known CC spell IDs.  When any CC lands on a
-- healer, the game plays the alert clip.
--
-- Only the most PvP-relevant subset is included here to keep the file
-- manageable. The full set can be added later if needed.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DB.CcSpellIds = {
    -- Polymorph variants
    [118] = true, [28271] = true, [28272] = true, [61305] = true,
    [61721] = true, [61780] = true, [126819] = true, [161353] = true,
    [161354] = true, [161355] = true, [161372] = true, [277787] = true,
    [277788] = true, [277792] = true, [277793] = true,
    -- Hex variants
    [51514] = true, [210873] = true, [211004] = true, [211010] = true,
    [211015] = true, [269352] = true, [309328] = true, [309329] = true,
    -- Fear / Howl
    [5246] = true, [5484] = true, [8122] = true, [118699] = true,
    [6789] = true, [115199] = true,
    -- Cyclone
    [33786] = true, [410870] = true,
    -- Blind
    [2094] = true,
    -- Sap
    [6770] = true,
    -- Gouge
    [1776] = true,
    -- Cheap Shot
    [1833] = true, [6409] = true,
    -- Kidney Shot
    [408] = true,
    -- Garrote Silence
    [1330] = true,
    -- Freezing Trap
    [3355] = true, [203337] = true,
    -- Scatter Shot
    [213691] = true,
    -- Wyvern Sting
    [19386] = true,
    -- Repentance
    [20066] = true,
    -- Hammer of Justice
    [853] = true,
    -- Blinding Light
    [105421] = true,
    -- Turn Evil
    [10326] = true,
    -- Chastise
    [200196] = true, [200200] = true,
    -- Mind Control
    [605] = true,
    -- Psychic Horror / Scream
    [64044] = true,
    -- Silence (Priest)
    [15487] = true,
    -- Strangulate
    [47476] = true,
    -- Asphyxiate
    [108194] = true, [221562] = true,
    -- Imprison
    [217832] = true, [221527] = true, [332544] = true, [386761] = true,
    -- Chaos Nova
    [179057] = true,
    -- Entangling Roots / Mass Entanglement
    [339] = true, [102359] = true,
    -- Frost Nova
    [122] = true,
    -- Ring of Frost
    [82691] = true,
    -- Dragon's Breath
    [29964] = true,
    -- Mighty Bash
    [5211] = true,
    -- Hibernate
    [2637] = true,
    -- Disorienting Roar
    [99] = true,
    -- Rake Stun
    [163505] = true,
    -- Maim
    [203123] = true,
    -- Intimidation
    [7093] = true,
    -- Shadowfury
    [30283] = true,
    -- Banish
    [710] = true,
    -- Seduction / Mesmerize
    [6358] = true,
    -- Mortal Coil
    [6789] = true,
    -- Axe Toss (Felguard)
    [6466] = true, [89766] = true,
    -- War Stomp
    [20549] = true,
    -- Quaking Palm
    [107079] = true,
    -- Paralysis
    [115078] = true, [357768] = true,
    -- Leg Sweep
    [119381] = true,
    -- Capacitor Totem
    [118905] = true,
    -- Lightning Lasso
    [204437] = true, [305485] = true,
    -- Shockwave
    [46968] = true,
    -- Storm Bolt
    [107570] = true,
    -- Charge stun
    [105771] = true,
    -- Landslide
    [355689] = true, [414257] = true,
    -- Sleep Walk (Evoker)
    [360806] = true,
}



DB.SpellClassMap = {
    [203123] = "DRUID",
    [381818] = "WARRIOR",
    [114052] = "SHAMAN",
    [28272] = "MAGE",
    [377360] = "GENERAL",
    [605] = "PRIEST",
    [20572] = "GENERAL",
    [254471] = "PALADIN",
    [211319] = "PALADIN",
    [108291] = "SHAMAN",
    [277792] = "MAGE",
    [11327] = "ROGUE",
    [13750] = "ROGUE",
    [212654] = "DEATHKNIGHT",
    [254474] = "PALADIN",
    [5484] = "WARLOCK",
    [115078] = "MONK",
    [215652] = "PALADIN",
    [377844] = "WARRIOR",
    [122] = "MAGE",
    [167232] = "WARRIOR",
    [93422] = "GENERAL",
    [19386] = "HUNTER",
    [412031] = "WARRIOR",
    [7093] = "HUNTER",
    [453804] = "PALADIN",
    [48792] = "DEATHKNIGHT",
    [378974] = "PALADIN",
    [185313] = "ROGUE",
    [221885] = "PALADIN",
    [370553] = "EVOKER",
    [161353] = "MAGE",
    [410236] = "WARRIOR",
    [360806] = "EVOKER",
    [200183] = "PALADIN",
    [15286] = "PRIEST",
    [386164] = "WARRIOR",
    [236273] = "WARRIOR",
    [264735] = "HUNTER",
    [221562] = "DEATHKNIGHT",
    [409311] = "EVOKER",
    [357768] = "MONK",
    [99] = "DRUID",
    [260251] = "PALADIN",
    [203337] = "HUNTER",
    [31850] = "PALADIN",
    [184662] = "PALADIN",
    [29964] = "MAGE",
    [105421] = "PALADIN",
    [1219480] = "SHAMAN",
    [13877] = "ROGUE",
    [106951] = "SHAMAN",
    [437461] = "HUNTER",
    [412030] = "WARRIOR",
    [466772] = "SHAMAN",
    [305497] = "SHAMAN",
    [211004] = "SHAMAN",
    [260708] = "WARRIOR",
    [389794] = "SHAMAN",
    [30283] = "WARLOCK",
    [8122] = "WARLOCK",
    [208086] = "GENERAL",
    [48743] = "DEATHKNIGHT",
    [408] = "ROGUE",
    [102543] = "SHAMAN",
    [326808] = "DEATHKNIGHT",
    [357170] = "EVOKER",
    [345231] = "GENERAL",
    [200196] = "PRIEST",
    [6940] = "PALADIN",
    [6358] = "WARLOCK",
    [46924] = "WARRIOR",
    [370960] = "EVOKER",
    [1253881] = "PALADIN",
    [410598] = "WARLOCK",
    [193530] = "HUNTER",
    [2637] = "DRUID",
    [186257] = "HUNTER",
    [197871] = "MAGE",
    [254472] = "PALADIN",
    [410358] = "DEATHKNIGHT",
    [1330] = "ROGUE",
    [1966] = "ROGUE",
    [441752] = "DEATHKNIGHT",
    [87024] = "MAGE",
    [51690] = "ROGUE",
    [1253874] = "PALADIN",
    [351077] = "WARRIOR",
    [1719] = "WARRIOR",
    [228260] = "MAGE",
    [33891] = "SHAMAN",
    [212295] = "WARLOCK",
    [132158] = "SHAMAN",
    [194223] = "SHAMAN",
    [210873] = "SHAMAN",
    [48265] = "DEATHKNIGHT",
    [219809] = "DEATHKNIGHT",
    [442726] = "WARLOCK",
    [202335] = "ROGUE",
    [10326] = "PALADIN",
    [102558] = "SHAMAN",
    [498] = "PALADIN",
    [221886] = "PALADIN",
    [231895] = "PALADIN",
    [342246] = "MAGE",
    [47536] = "PRIEST",
    [51271] = "DEATHKNIGHT",
    [211010] = "SHAMAN",
    [55233] = "DEATHKNIGHT",
    [107570] = "WARRIOR",
    [213871] = "PALADIN",
    [198817] = "WARRIOR",
    [108978] = "MAGE",
    [199261] = "WARRIOR",
    [145629] = "DEATHKNIGHT",
    [47788] = "PRIEST",
    [207167] = "GENERAL",
    [11426] = "MAGE",
    [53271] = "HUNTER",
    [254473] = "PALADIN",
    [353094] = "PALADIN",
    [1833] = "ROGUE",
    [276112] = "PALADIN",
    [354610] = "DEMONHUNTER",
    [125174] = "MONK",
    [305485] = "SHAMAN",
    [108294] = "SHAMAN",
    [446035] = "WARRIOR",
    [161372] = "MAGE",
    [46968] = "WARRIOR",
    [389853] = "WARRIOR",
    [1022] = "PALADIN",
    [45438] = "MAGE",
    [326801] = "DEATHKNIGHT",
    [31230] = "ROGUE",
    [61780] = "MAGE",
    [227847] = "WARRIOR",
    [122278] = "MONK",
    [223804] = "DEATHKNIGHT",
    [223658] = "WARRIOR",
    [6409] = "ROGUE",
    [221887] = "PALADIN",
    [410235] = "WARRIOR",
    [152108] = "GENERAL",
    [378081] = "SHAMAN",
    [212552] = "DEATHKNIGHT",
    [377827] = "WARRIOR",
    [328530] = "PALADIN",
    [162264] = "DEMONHUNTER",
    [53480] = "HUNTER",
    [372791] = "PALADIN",
    [277787] = "MAGE",
    [204437] = "SHAMAN",
    [122783] = "MONK",
    [7366] = "WARRIOR",
    [121471] = "ROGUE",
    [1293412] = "GENERAL",
    [194844] = "DEATHKNIGHT",
    [163505] = "DRUID",
    [389789] = "WARRIOR",
    [185422] = "ROGUE",
    [184364] = "WARRIOR",
    [262228] = "WARRIOR",
    [1246968] = "MAGE",
    [1289617] = "PALADIN",
    [317911] = "PALADIN",
    [288613] = "HUNTER",
    [197862] = "PRIEST",
    [197908] = "MONK",
    [152279] = "DEATHKNIGHT",
    [871] = "WARRIOR",
    [309329] = "SHAMAN",
    [115176] = "MONK",
    [372761] = "PALADIN",
    [61305] = "MAGE",
    [343142] = "ROGUE",
    [118699] = "WARLOCK",
    [294133] = "PALADIN",
    [116888] = "DEATHKNIGHT",
    [2983] = "ROGUE",
    [5246] = "WARLOCK",
    [339] = "DRUID",
    [386761] = "DEMONHUNTER",
    [28271] = "MAGE",
    [1289616] = "PALADIN",
    [348489] = "PALADIN",
    [186265] = "HUNTER",
    [102351] = "SHAMAN",
    [20549] = "GENERAL",
    [1249625] = "MONK",
    [1217607] = "DEMONHUNTER",
    [207319] = "DEATHKNIGHT",
    [1776] = "ROGUE",
    [372616] = "MAGE",
    [253038] = "WARRIOR",
    [5277] = "ROGUE",
    [191634] = "SHAMAN",
    [375087] = "EVOKER",
    [454351] = "PALADIN",
    [710] = "WARLOCK",
    [22812] = "SHAMAN",
    [6726] = "GENERAL",
    [108292] = "SHAMAN",
    [212800] = "DEMONHUNTER",
    [194679] = "DEATHKNIGHT",
    [359816] = "EVOKER",
    [355689] = "EVOKER",
    [199754] = "ROGUE",
    [31884] = "PALADIN",
    [113860] = "WARLOCK",
    [19574] = "HUNTER",
    [443454] = "SHAMAN",
    [1260251] = "PALADIN",
    [118905] = "SHAMAN",
    [179057] = "DEMONHUNTER",
    [5211] = "DRUID",
    [161355] = "MAGE",
    [108416] = "WARLOCK",
    [198589] = "DEMONHUNTER",
    [2094] = "ROGUE",
    [190319] = "MAGE",
    [382912] = "SHAMAN",
    [287254] = "DEATHKNIGHT",
    [277788] = "MAGE",
    [212641] = "PALADIN",
    [213691] = "HUNTER",
    [6770] = "ROGUE",
    [360827] = "EVOKER",
    [200200] = "PRIEST",
    [107079] = "GENERAL",
    [51514] = "SHAMAN",
    [29166] = "WARRIOR",
    [327193] = "PALADIN",
    [381835] = "WARRIOR",
    [389774] = "WARRIOR",
    [410870] = "DRUID",
    [48707] = "DEATHKNIGHT",
    [115203] = "MONK",
    [126819] = "MAGE",
    [205191] = "PALADIN",
    [8178] = "SHAMAN",
    [210294] = "PALADIN",
    [1850] = "SHAMAN",
    [69369] = "SHAMAN",
    [414661] = "MAGE",
    [309328] = "SHAMAN",
    [12472] = "MAGE",
    [45182] = "ROGUE",
    [49039] = "DEATHKNIGHT",
    [266779] = "HUNTER",
    [102359] = "DRUID",
    [211015] = "SHAMAN",
    [372760] = "PALADIN",
    [212640] = "GENERAL",
    [118038] = "WARRIOR",
    [6789] = "WARLOCK",
    [155835] = "SHAMAN",
    [414257] = "EVOKER",
    [212704] = "HUNTER",
    [332544] = "DEMONHUNTER",
    [236236] = "GENERAL",
    [269352] = "SHAMAN",
    [89766] = "WARLOCK",
    [22842] = "SHAMAN",
    [210824] = "MAGE",
    [199086] = "WARRIOR",
    [1044] = "PALADIN",
    [15487] = "PRIEST",
    [102342] = "SHAMAN",
    [374348] = "EVOKER",
    [441751] = "DEATHKNIGHT",
    [10060] = "MAGE",
    [853] = "PALADIN",
    [114051] = "SHAMAN",
    [110909] = "MAGE",
    [115199] = "WARLOCK",
    [34709] = "GENERAL",
    [1214937] = "ROGUE",
    [1251903] = "GENERAL",
    [147833] = "WARRIOR",
    [112071] = "SHAMAN",
    [47585] = "PRIEST",
    [363916] = "EVOKER",
    [277793] = "MAGE",
    [1299383] = "GENERAL",
    [86949] = "MAGE",
    [363608] = "PALADIN",
    [243435] = "MONK",
    [220509] = "PALADIN",
    [209584] = "MONK",
    [288977] = "DEATHKNIGHT",
    [196942] = "GENERAL",
    [360952] = "HUNTER",
    [82691] = "MAGE",
    [1250646] = "HUNTER",
    [403876] = "PALADIN",
    [107574] = "WARRIOR",
    [276111] = "PALADIN",
    [47476] = "DEATHKNIGHT",
    [86659] = "PALADIN",
    [61721] = "MAGE",
    [108293] = "SHAMAN",
    [412035] = "WARRIOR",
    [31224] = "ROGUE",
    [383410] = "SHAMAN",
    [209426] = "DEMONHUNTER",
    [386208] = "WARRIOR",
    [118] = "MAGE",
    [20066] = "PALADIN",
    [114050] = "SHAMAN",
    [18499] = "WARRIOR",
    [6466] = "WARLOCK",
    [102560] = "DRUID",
    [221527] = "DEMONHUNTER",
    [444741] = "DEATHKNIGHT",
    [377362] = "GENERAL",
    [384352] = "SHAMAN",
    [161354] = "MAGE",
    [206803] = "DEMONHUNTER",
    [1253723] = "PALADIN",
    [1272854] = "PALADIN",
    [202748] = "HUNTER",
    [80240] = "WARLOCK",
    [122470] = "MONK",
    [119381] = "MONK",
    [372783] = "PALADIN",
    [1233448] = "DEATHKNIGHT",
    [365362] = "MAGE",
    [23920] = "WARRIOR",
    [204018] = "PALADIN",
    [221883] = "PALADIN",
    [370562] = "EVOKER",
    [188501] = "DEMONHUNTER",
    [642] = "PALADIN",
    [2458] = "WARRIOR",
    [386196] = "WARRIOR",
    [108271] = "SHAMAN",
    [216331] = "PALADIN",
    [207736] = "ROGUE",
    [33206] = "PRIEST",
    [105771] = "WARRIOR",
    [64044] = "PRIEST",
    [201318] = "MONK",
    [42650] = "DEATHKNIGHT",
    [187827] = "DEMONHUNTER",
    [8611] = "MAGE",
    [392966] = "MAGE",
    [217832] = "DEMONHUNTER",
    [108194] = "DEATHKNIGHT",
    [441749] = "DEATHKNIGHT",
    [116849] = "MONK",
    [213610] = "PALADIN",
    [104773] = "WARLOCK",
    [79206] = "SHAMAN",
    [33786] = "DRUID",
    [109964] = "PRIEST",
    [207777] = "GENERAL",
    [252216] = "SHAMAN",
    [12975] = "WARRIOR",
    [408558] = "MAGE",
    [61336] = "SHAMAN",
    [3355] = "HUNTER",
    [378464] = "EVOKER",
    [236077] = "GENERAL",
}

