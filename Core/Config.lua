local addonName, OxedHub = ...

-- Configuration and Constants
OxedHub.CONFIG = {
    VERSION = "2.3.43",
    DB_VERSION = 1,

    -- Shown in the Export/Import "About" panel. Edit freely.
    CREDITS = {
        author = "Oxed",
        thanks = "Thanks to everyone testing & sharing profiles.",
        links = nil, -- e.g. "Discord: discord.gg/xxxx"
    },
    
    -- UI Dimensions
    MAIN_FRAME_WIDTH = 1320,
    MAIN_FRAME_HEIGHT = 800,
    SIDEBAR_WIDTH = 200,
    CONTENT_WIDTH = 1090,
    
    -- Trigger categories for the two-step Event Type picker. "advanced" events
    -- need a spell ID (or similar) to be configured; everything else is
    -- ready to use as soon as it's selected.
    EVENT_CATEGORIES = {
        { value = "basic", label = "Basic Triggers", desc = "General events like mounts, leveling, mail, achievements, and party invites" },
        { value = "combat", label = "Combat Triggers", desc = "Combat events like interrupts, boss encounters, deaths, and cooldowns" },
        { value = "pvp", label = "PvP Triggers", desc = "Player versus Player kills, multi-kills, and sprees" },
        { value = "advanced", label = "Advanced Triggers", desc = "Configurable triggers requiring spell IDs, aura names, or proc glows" },
    },

    -- Event Types (technical -> human-readable mapping with descriptions)
    EVENT_TYPES = {
        -- Advanced Triggers
        { value = "UNIT_AURA", label = "Aura Gained/Lost", desc = "When you gain or lose a buff/debuff", category = "advanced" },
        { value = "SELF_AURA", label = "My Buff (by Spell ID)", desc = "Detect one of YOUR buffs by spell ID (e.g. Power Infusion). Works out of combat now; sound also plays IN COMBAT on WoW 12.1+ (native aura sound).", category = "advanced" },
        -- { value = "TEST_ICON_AURA", label = "Test Trigger (by Icon ID)", desc = "Monitors a buff by resolving the chosen spell to its icon, checking if any active buff shares that icon.", category = "advanced" },
        { value = "SPELL_PROC", label = "Spell Proc Glow (by Spell ID)", desc = "Fires when a spell's proc/activation glow appears on your bar (e.g. Sudden Doom lighting up Death Coil). Uses the game's proc-glow event, so it works IN COMBAT.", category = "advanced" },
        { value = "UNIT_SPELLCAST_SUCCEEDED", label = "Spell Cast Success", desc = "When you successfully cast a spell (e.g., Sprint, Hearthstone, Portals)", category = "advanced" },

        -- Basic Triggers
        { value = "SHATTERSIGHT", label = "Disenchant Insight", desc = "Analyze and track Disenchant values vs vendor prices directly on tooltips", category = "basic" },
        { value = "SUMMON", label = "Summon", desc = "When a summon appears, is accepted, or is declined", category = "basic" },
        { value = "EAT_BUFF", label = "Food/Drink Buff", desc = "When you eat or drink (Well Fed, Refreshment)", category = "basic" },
        { value = "ACHIEVEMENT", label = "Achievement Earned", desc = "When you earn an achievement", category = "basic" },
        { value = "PLAYER_LEVEL_UP", label = "Level Up", desc = "When you gain a level", category = "basic" },
        { value = "NEW_MAIL", label = "New Mail", desc = "When you receive new mail", category = "basic" },
        { value = "REACH_FLY_DESTINATION", label = "Reach Fly Destination", desc = "When you land from a flight path", category = "basic" },
        { value = "MOUNT", label = "Mount Up / Dismount", desc = "When you mount up, dismount, or shapeshift into Travel Form", category = "basic" },
        { value = "GROUP_JOINED", label = "Joined Group", desc = "When you join a party or raid", category = "basic" },
        { value = "GROUP_LEFT", label = "Left Group", desc = "When you leave a party or raid", category = "basic" },
        { value = "PARTY_INVITE_REQUEST", label = "Party Invite", desc = "When you receive a party invite", category = "basic" },
        { value = "PARTY_LEADER_CHANGED", label = "Leader Changed", desc = "When the party leader changes", category = "basic" },
        { value = "HEARTBEAT", label = "Heartbeat", desc = "Plays a heartbeat sound that speeds up as your health drops below a threshold", category = "basic" },
        { value = "PREY_HUNT", label = "Prey Hunt", desc = "Track Prey Hunts, Astalor gossip achievement markers, stage alerts, and HUD bar", category = "basic" },

        -- Combat Triggers
        { value = "COMBAT_STATE", label = "Enter/Exit Combat", desc = "When you enter or leave combat", category = "combat" },
        { value = "BLOODLUST", label = "Bloodlust / Heroism", desc = "When the Bloodlust/Heroism/Time Warp buff lands on you (works in combat)", category = "combat" },
        { value = "BASIC_AURA_TRACKER", label = "My Target Debuffs", desc = "Native aura tracker that automatically monitors your target debuffs (no spell ID required).", category = "combat" },
        { value = "CD_READY", label = "Cooldown Ready", desc = "When a tracked spell's cooldown finishes", category = "combat" },
        { value = "INTERRUPT_USED", label = "Interrupt", desc = "When you use your interrupt spell (cast, success, or fail)", category = "combat" },
        { value = "SPELL_INTERRUPTED", label = "Spell Interrupted", desc = "When your spell is interrupted", category = "combat" },
        { value = "CONTROL_LOST", label = "Control Lost", desc = "When you lose control (fear, MC, taxi)", category = "combat" },
        { value = "CONTROL_GAINED", label = "Control Regained", desc = "When you regain control", category = "combat" },
        { value = "PLAYER_DEAD", label = "Player Died", desc = "When your character dies", category = "combat" },
        { value = "PARTY_MEMBER_DEATH", label = "Party Member Died", desc = "When a party member dies", category = "combat" },
        { value = "PET_DIED", label = "Pet Died", desc = "When your pet dies", category = "combat" },
        { value = "PET_SUMMONED", label = "Pet Summoned", desc = "When your pet is summoned", category = "combat" },
        { value = "PET_DISMISSED", label = "Pet Dismissed", desc = "When your pet is dismissed", category = "combat" },
        { value = "ENCOUNTER_START", label = "Boss Encounter Start", desc = "When a boss fight begins", category = "combat" },
        { value = "ENCOUNTER_END", label = "Boss Encounter End", desc = "When a boss fight ends (win or wipe)", category = "combat" },
        { value = "BOSS_KILL", label = "Boss Killed", desc = "When your group kills a boss", category = "combat" },
        { value = "CHALLENGE_MODE_COMPLETED", label = "M+ Completed", desc = "When a Mythic+ dungeon is completed", category = "combat" },

        -- PvP Triggers
        { value = "PVP_KILL", label = "PvP Kill", desc = "When you land a killing blow on an enemy player", category = "pvp" },
        { value = "PVP_MULTIKILL", label = "PvP Multi-Kill", desc = "Double / Triple / Multi kill within 10 seconds", category = "pvp" },
        { value = "PVP_SPREE", label = "PvP Killing Spree", desc = "Killing Spree / Dominating / Unstoppable / Godlike", category = "pvp" },
        { value = "PVP_ENEMY_BUFF", label = "Enemy Buff Alert", desc = "Instantly plays a voice clip when your target, focus, or arena enemy gains an important buff (defensive, offensive, utility).", category = "pvp" },
        { value = "PVP_SELF_CC", label = "Self CC Alert", desc = "Instantly plays a voice clip when you are hit by crowd control (stuns, fears, poly, silence, etc.).", category = "pvp" },
        { value = "PVP_HEALER_CC", label = "Healer CC Alert", desc = "Plays an alert when a friendly healer in your party/raid is hit by crowd control.", category = "pvp" },
        { value = "PVP_TRINKET", label = "Enemy Trinket Alert", desc = "Plays an alert when an enemy uses their PvP trinket or Adaptation.", category = "pvp" },
        { value = "PVP_CONSUMABLE", label = "Enemy Consumable Alert", desc = "Plays an alert when an enemy drinks a healing potion or consumable.", category = "pvp" },
        { value = "PVP_ANTI_AFK", label = "Anti-AFK BG Guard", desc = "Tracks idle time in Battlegrounds, displays an on-screen timer, and alerts with sounds and a MOVE banner.", category = "pvp" },
    },
    
    -- Zone Types
    ZONE_TYPES = {
        "OPEN_WORLD",
        "PARTY",
        "RAID",
        "PVP",
        "BATTLEGROUND",
    },
    
    -- Chat Channels
    CHAT_CHANNELS = {
        "SAY",
        "PARTY",
        "RAID",
        "YELL",
        "INSTANCE_CHAT",
        "GUILD",
        "OFFICER",
        "WHISPER",
    },
    
    -- Emotions for Emotion Ring (Legacy)
    EMOTIONS = {
        "Happy",
        "Sad",
        "Angry",
        "Surprised",
        "Laugh",
        "Cry",
        "Dance",
        "Cheer",
        "Fear",
        "Love",
        "Taunt",
        "Proud",
    },
    
    -- Reactions/Emojis for Editor
    REACTIONS = {
        { id = "angry", name = "Angry", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Cursing angry.png", command = "angry" },
        { id = "kiss", name = "Kiss", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Kiss.png", command = "kiss" },
        { id = "laugh", name = "Laugh", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Tears of joy.png", command = "laugh" },
        { id = "cry", name = "Cry", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Sadly Crying.png", command = "cry" },
        { id = "cheer", name = "Cheer", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Party.png", command = "cheer" },
        { id = "sleep", name = "Sleep", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Sleeping.png", command = "sleep" },
        { id = "dance", name = "Dance", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Excited laugh.png", command = "dance" },
        { id = "love", name = "Love", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Heart eyes.png", command = "love" },
        { id = "sick", name = "Sick", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Vomiting.png", command = "sick" },
        { id = "taunt", name = "Taunt", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Playful tongue.png", command = "taunt" },
        { id = "fear", name = "Fear", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Shocked.png", command = "cower" },
        { id = "money", name = "Money", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Money face.png", command = "cheer" },
        { id = "cool", name = "Cool", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Sunglasses cool.png", command = "flex" },
        { id = "sad", name = "Sad", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Sad.png", command = "mourn" },
        { id = "thinking", name = "Thinking", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Thinking.png", command = "ponder" },
        { id = "smirk", name = "Smirk", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Smirk.png", command = "smirk" },
    },
    
    -- Raid Tool Spell IDs
    RAID_TOOL_SPELLS = {
        43987,  -- Ritual of Refreshment (Mage Table)
        29893,  -- Ritual of Souls (Warlock Stone)
        67826,  -- Jeeves (Repair Bot)
        54710,  -- MOLL-E (Mailbox)
        261602, -- Katy's Stampwhistle (Mailbox)
    },
    
    -- Interrupt Spell IDs (common)
    INTERRUPT_SPELLS = {
        1766,   -- Kick (Rogue)
        6552,   -- Pummel (Warrior)
        2139,   -- Counterspell (Mage)
        15487,  -- Silence (Priest)
        57994,  -- Wind Shear (Shaman)
        47528,  -- Mind Freeze (DK)
        106839, -- Skull Bash (Druid)
        116705, -- Spear Hand Strike (Monk)
        96231,  -- Rebuke (Paladin)
        147362, -- Counter Shot (Hunter)
        187707, -- Muzzle (Hunter)
        183752, -- Disrupt (Demon Hunter)
        351338, -- Quell (Evoker)
    },
    
    -- Performance
    COOLDOWN_CHAT = 1.0,  -- seconds between chat messages
    COOLDOWN_EMOTE = 0.5, -- seconds between emotes
    COOLDOWN_SOUND = 0.1, -- seconds between sounds
    
    -- Animation
    DEFAULT_ANIMATION_FPS = 24,
}


-- Utility function to get localized string
function OxedHub:GetString(key, ...)
    local str = self.L[key] or key
    if ... then
        return str:format(...)
    end
    return str
end

local LUST_SPELL_IDS = {
    -- Haste Buffs
    [2825]    = true, -- Bloodlust
    [32182]   = true, -- Heroism
    [80353]   = true, -- Time Warp
    [390386]  = true, -- Fury of the Aspects
    [264667]  = true, -- Primal Rage
    [90355]   = true, -- Ancient Hysteria
    [160452]  = true, -- Netherwinds
    [381301]  = true, -- Feral Hide Drums
    [230935]  = true, -- Drums of the Mountain
    [256740]  = true, -- Drums of the Maelstrom
    [309658]  = true, -- Drums of Deathly Ferocity
    [466904]  = true, -- Harrier's Cry / Drums of War
    [1243972] = true, -- Void-touched Drums

    -- Sated / Exhaustion Debuffs (used in 12.1 combat existence tracking)
    [57724]   = true, -- Sated (Bloodlust)
    [57723]   = true, -- Exhaustion (Heroism)
    [80354]   = true, -- Temporal Displacement (Time Warp)
    [390435]  = true, -- Exhaustion (Fury of the Aspects)
    [264689]  = true, -- Fatigued (Primal Rage / Drums)
}

function OxedHub.IsLustSpell(val)
    if not val then return false end
    local n = tonumber(val)
    if n and LUST_SPELL_IDS[n] then
        return true
    end
    local s = tostring(val):lower()
    if LUST_SPELL_IDS[s] or s:find("bloodlust") or s:find("heroism") or s:find("time warp") or s:find("fury of the aspects") or s:find("primal rage") or s:find("drums") then
        return true
    end
    return false
end

function OxedHub.IsLustTrigger(trigger)
    if not trigger then return false end
    local c = trigger.conditions or {}
    if OxedHub.IsLustSpell(c.spellID) or OxedHub.IsLustSpell(c.spellName) then
        return true
    end
    if c.extraSpellIDs then
        for _, id in ipairs(c.extraSpellIDs) do
            if OxedHub.IsLustSpell(id) then return true end
        end
    end
    if c.extraSpellNames then
        for _, name in ipairs(c.extraSpellNames) do
            if OxedHub.IsLustSpell(name) then return true end
        end
    end
    return false
end

function OxedHub.GetRingDB()
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.oxedRingUnique ~= false then
        return OxedHub.db.profile
    end
    return OxedHub.db and OxedHub.db.globalSettings or {}
end

function OxedHub.GetEffectiveRingRadius(numNodes)
    local baseRadius = (OxedHub.db and OxedHub.db.profile and OxedHub.GetRingDB().oxedRingRadius) or 100
    local autoAdjust = (OxedHub.db and OxedHub.db.profile and OxedHub.GetRingDB().oxedRingAutoRadius)
    if autoAdjust == nil then autoAdjust = true end
    
    if not autoAdjust or not numNodes or numNodes <= 1 then
        return baseRadius
    end
    
    local scale = math.min(1.0, math.max(0.45, (numNodes / 12) ^ 0.65))
    local calcRadius = math.floor(baseRadius * scale)
    return math.max(60, calcRadius)
end

