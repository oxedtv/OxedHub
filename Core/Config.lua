local addonName, OxedHub = ...

-- Configuration and Constants
OxedHub.CONFIG = {
    VERSION = "2.2.39",
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
        { value = "preset", label = "Basic Triggers", desc = "Ready-to-use events that need no extra configuration" },
        { value = "advanced", label = "Advanced Triggers", desc = "Events that you configure with a specific spell or aura" },
    },

    -- Event Types (technical -> human-readable mapping with descriptions)
    -- category defaults to "preset" when omitted.
    EVENT_TYPES = {
        { value = "UNIT_AURA", label = "Aura Gained/Lost", desc = "When you gain or lose a buff/debuff", category = "advanced" },
        { value = "SELF_AURA", label = "My Buff (by Spell ID)", desc = "Detect one of YOUR buffs by spell ID (e.g. Power Infusion). Works out of combat now; sound also plays IN COMBAT on WoW 12.1+ (native aura sound).", category = "advanced" },
        { value = "SPELL_PROC", label = "Spell Proc Glow (by Spell ID)", desc = "Fires when a spell's proc/activation glow appears on your bar (e.g. Sudden Doom lighting up Death Coil). Uses the game's proc-glow event, so it works IN COMBAT.", category = "advanced" },
        { value = "UNIT_SPELLCAST_SUCCEEDED", label = "Spell Cast Success", desc = "When you successfully cast a spell (e.g., Sprint, Hearthstone, Portals)", category = "advanced" },
        { value = "SUMMON", label = "Summon", desc = "When a summon appears, is accepted, or is declined" },
        { value = "PLAYER_DEAD", label = "Player Died", desc = "When your character dies" },
        { value = "ENCOUNTER_START", label = "Boss Encounter Start", desc = "When a boss fight begins" },
        { value = "ENCOUNTER_END", label = "Boss Encounter End", desc = "When a boss fight ends (win or wipe)" },
        { value = "BOSS_KILL", label = "Boss Killed", desc = "When your group kills a boss" },
        { value = "CHALLENGE_MODE_COMPLETED", label = "M+ Completed", desc = "When a Mythic+ dungeon is completed" },
        -- { value = "SUMMON_ACCEPT", label = "Summon Accepted", desc = "When you accept a summon from another player" },
        { value = "CD_READY", label = "Cooldown Ready", desc = "When a tracked spell's cooldown finishes" },
        { value = "INTERRUPT_USED", label = "Interrupt", desc = "When you use your interrupt spell (cast, success, or fail)" },
        { value = "EAT_BUFF", label = "Food/Drink Buff", desc = "When you eat or drink (Well Fed, Refreshment)" },
        { value = "ACHIEVEMENT", label = "Achievement Earned", desc = "When you earn an achievement" },
        { value = "CONTROL_LOST", label = "Control Lost", desc = "When you lose control (fear, MC, taxi)" },
        { value = "CONTROL_GAINED", label = "Control Regained", desc = "When you regain control" },
        { value = "PET_DIED", label = "Pet Died", desc = "When your pet dies" },
        { value = "PET_SUMMONED", label = "Pet Summoned", desc = "When your pet is summoned" },
        { value = "PET_DISMISSED", label = "Pet Dismissed", desc = "When your pet is dismissed" },
        { value = "SPELL_INTERRUPTED", label = "Spell Interrupted", desc = "When your spell is interrupted" },
        { value = "PARTY_MEMBER_DEATH", label = "Party Member Died", desc = "When a party member dies" },
        { value = "PLAYER_LEVEL_UP", label = "Level Up", desc = "When you gain a level" },
        { value = "NEW_MAIL", label = "New Mail", desc = "When you receive new mail" },
        { value = "REACH_FLY_DESTINATION", label = "Reach Fly Destination", desc = "When you land from a flight path" },
        { value = "MOUNT", label = "Mount Up / Dismount", desc = "When you mount up, dismount, or shapeshift into Travel Form" },
        { value = "COMBAT_STATE", label = "Enter/Exit Combat", desc = "When you enter or leave combat" },
        { value = "PVP_KILL", label = "PvP Kill", desc = "When you land a killing blow on an enemy player" },
        { value = "PVP_MULTIKILL", label = "PvP Multi-Kill", desc = "Double / Triple / Multi kill within 10 seconds" },
        { value = "PVP_SPREE", label = "PvP Killing Spree", desc = "Killing Spree / Dominating / Unstoppable / Godlike" },
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
