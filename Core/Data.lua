local addonName, OxedHub = ...

-- Default data that will be merged with saved variables
-- Never overwrites existing user data

OxedHub.DEFAULTS = {
    -- Triggers start empty; create your own from the UI.
    triggers = {},
    
    -- Custom sounds start empty; add real files from the UI.
    customSounds = {},
    
    -- Built-in Oxed animations (bundled TGA sprite sheets)
    animations = {
        -- Oxed Female
        ["oxed_anim_female_hello"] = { name = "Female Hello", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-Hello.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_achievement"] = { name = "Female Achievement", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-achievmnet.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_alliance"] = { name = "Female Alliance", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-alliance.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_angry"] = { name = "Female Angry", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-angry.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_back"] = { name = "Female Back", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-back.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_brb"] = { name = "Female BRB", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-brb.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_celebrate"] = { name = "Female Celebrate", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-celebrate.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_crazy"] = { name = "Female Crazy", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-crazy.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_cry"] = { name = "Female Cry", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-cry.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_dead"] = { name = "Female Dead", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-dead.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_devil"] = { name = "Female Devil", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-devil.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_eat"] = { name = "Female Eat", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-eat.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_gg"] = { name = "Female GG", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-gg.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_lol"] = { name = "Female LOL", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-lol.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_megaphone"] = { name = "Female Megaphone", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-megaphone.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_power"] = { name = "Female Power", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-power.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_crazy_shaking"] = { name = "Female Crazy Shaking", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-scrazy-shaking.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_shooting"] = { name = "Female Shooting", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-shooting.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_surprise"] = { name = "Female Surprise", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-surprise.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_female_horde"] = { name = "Female Horde", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-female-horde.png", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        -- Oxed Male
        ["oxed_anim_male_achievement"] = { name = "Male Achievement", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-achievmnet.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_alliance"] = { name = "Male Alliance", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-alliance.png", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_argue"] = { name = "Male Argue", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-argue.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_back"] = { name = "Male Back", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-back.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_brb"] = { name = "Male BRB", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-brb.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_celebrate"] = { name = "Male Celebrate", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-celebrate.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_crazy"] = { name = "Male Crazy", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-crazy.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_cry"] = { name = "Male Cry", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-cry.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_dead"] = { name = "Male Dead", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-dead.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_devil"] = { name = "Male Devil", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-devil.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_eat"] = { name = "Male Eat", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-eat.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_eating"] = { name = "Male Eating", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-eating.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_gg"] = { name = "Male GG", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-gg.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_hello"] = { name = "Male Hello", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-hello.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_horde"] = { name = "Male Horde", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-horde.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_lol"] = { name = "Male LOL", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-lol.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_megaphone"] = { name = "Male Megaphone", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-megaphone.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_power"] = { name = "Male Power", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-power.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_crazy_shaking"] = { name = "Male Crazy Shaking", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-scrazy-shaking.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_shooting"] = { name = "Male Shooting", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-shooting.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
        ["oxed_anim_male_surprise"] = { name = "Male Surprise", tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Animations\\Oxed-male-surprise.tga", width = 128, height = 128, frameCount = 25, fps = 24, loopCount = 1, enabled = true, isBuiltIn = true },
    },
    
    -- Chat templates start empty; add your own from the UI.
    chatTemplates = {},

    -- Profile metadata used for UI and auto-switch behavior.
    metadata = {
        classToken = false,
    },
    
    -- Default toys (placeholders)
    toys = {
        -- User can add their favorite toys here
    },
    
    -- Default emotion mappings
    emotionMappings = {
        ["Happy"] = {
            sound = nil,
            animation = nil,
            emote = "HAPPY",
            chat = nil,
        },
        ["Sad"] = {
            sound = nil,
            animation = nil,
            emote = "CRY",
            chat = nil,
        },
        ["Angry"] = {
            sound = nil,
            animation = nil,
            emote = "ANGRY",
            chat = nil,
        },
        ["Surprised"] = {
            sound = nil,
            animation = nil,
            emote = "SHOCKED",
            chat = nil,
        },
        ["Laugh"] = {
            sound = nil,
            animation = nil,
            emote = "LAUGH",
            chat = nil,
        },
        ["Cry"] = {
            sound = nil,
            animation = nil,
            emote = "CRY",
            chat = nil,
        },
        ["Dance"] = {
            sound = nil,
            animation = nil,
            emote = "DANCE",
            chat = nil,
        },
        ["Cheer"] = {
            sound = nil,
            animation = nil,
            emote = "CHEER",
            chat = nil,
        },
        ["Fear"] = {
            sound = nil,
            animation = nil,
            emote = "COWER",
            chat = nil,
        },
        ["Love"] = {
            sound = nil,
            animation = nil,
            emote = "LOVE",
            chat = nil,
        },
        ["Taunt"] = {
            sound = nil,
            animation = nil,
            emote = "TAUNT",
            chat = nil,
        },
        ["Proud"] = {
            sound = nil,
            animation = nil,
            emote = "PROUD",
            chat = nil,
        },
    },
    
    -- Settings
    settings = {
        mainWindowVisible = false,
        windowPosition = { x = 100, y = 100 },
        hasCustomWindowPosition = false,
        minimapPosition = { hide = false, minimapPos = 225 },
        floatingButtonPosition = { x = 100, y = 100 },
        soundVolume = 1.0,
        soundChannel = "Master",
        triggerEffectsDelay = 5,
        animationScale = 1.0,
        animationPosition = { x = 0, y = 200 },
        cooldownProgressPosition = { x = 0, y = 150 },
        showTimerBar = true,
        timerBarPosition = { x = 0, y = 200 },
        emotionRingPosition = { x = 0, y = 0 },
        emotionRingButtonPosition = { x = 280, y = 0 },
        emotionRingButtonUnlocked = false,
        ringVisible = false,
        allowChatOnSpellCast = false,
        filterByClass = false,
        textSizeOffset = 0,
        language = "enUS",
    },

    -- Action Hub half-ring (experimental side panel ring)
    actionHub = {
        activeHub = 1,
        hubs = {
            {
                name = "Hub 1",
                slots = {}, -- { type="toy"|"emote", id=number|name }
                quadrant = "bottom-right",
                onScreen = false,
                widgetPosition = { x = 0, y = 0 },
                widgetUnlocked = false,
                style = "square",
            },
        },
    },

    experimental = {
        graph = {
            nextNodeId = 4,
            nodes = {
                { id = "node_1", type = "spell_event", label = "Spell Cast", x = 70, y = 80 },
                { id = "node_2", type = "condition", label = "Checks", x = 330, y = 80 },
                { id = "node_3", type = "sound_action", label = "Sound", x = 590, y = 80 },
            },
            links = {
                { from = "node_1", to = "node_2" },
                { from = "node_2", to = "node_3" },
            },
        },
    },

    -- Toy Mixes (Macro chains)
    toyMixes = {},

    -- Cached toy browser data (populated only when user refreshes/scans)
    toyCollectionCache = {
        toyIDs = {},
        toyCache = {},
        stale = false,
    },

    -- Toy Ring Mappings
    toyRingMappings = {},
}

-- Emote list (common emotes available in WoW)
OxedHub.EMOTE_LIST = {
    "AGREE", "AMAZED", "ANGRY", "APOLOGIZE", "APPLAUD", "BASHFUL", "BECKON",
    "BEG", "BITE", "BLEED", "BLINK", "BLUSH", "BONK", "BORED", "BOUNCE",
    "BOW", "BRB", "BURP", "BYE", "CACKLE", "CHEER", "CHUCKLE", "CLAP",
    "CONFUSED", "CONGRATS", "COUGH", "COWER", "CRACK", "CRINGE", "CRY",
    "CUDDLE", "CURIOUS", "CURTSEY", "DANCE", "DISAPPOINTED", "DOOM", "DRINK",
    "DROOL", "DUCK", "EAT", "EYE", "FAREWELL", "FART", "FEAR", "FIDGET",
    "FLEE", "FLEX", "FLIRT", "FLOP", "FOLLOW", "GASP", "GAZE", "GIGGLE",
    "GLARE", "GLOAT", "GOLFCLAP", "GOODBYE", "GREET", "GRIN", "GROAN",
    "GROVEL", "GROWL", "GUFFAW", "HAIL", "HAPPY", "HELLO", "HIC", "HUG",
    "HUNGRY", "INSULT", "INTRODUCE", "JK", "KISS", "KNEEL", "LAUGH", "LAY", "LEAN",
    "LECTURE", "LICK", "LIE", "LOVE", "MAJORFAIL", "MASSAGE", "MOCK", "MOON",
    "MOURN", "MUTTER", "NERVOUS", "NO", "NOD", "NOSEPICK", "OBJECTION",
    "OOO", "OPENFIRE", "PANIC", "PAT", "PEER", "PET", "PINCH", "PITY",
    "PLEAD", "POINT", "POKE", "PONDER", "POUNCE", "PRAISE", "PRAY", "PROUD",
    "PULSE", "PUNCH", "PURR", "PUZZLED", "RAGE", "RAISE", "RASP", "READ",
    "READY", "REAR", "REGRET", "REVENGE", "ROAR", "ROFL", "ROLLEYES", "RUDE",
    "RUFFLE", "SAD", "SALUTE", "SCARED", "SCOFF", "SCOLD", "SCOWL", "SCRATCH",
    "SEARCH", "SENTRY", "SHOO", "SHRUG", "SHUDDER", "SIGH", "SIGNAL", "SILLY",
    "SIT", "SLAP", "SLEEP", "SMIRK", "SNARL", "SNICKER", "SNIFF", "SNUB",
    "SOOTHE", "SPIT", "SPOON", "SQUINT", "STARE", "STEALTH", "STINK", "SURRENDER",
    "SUSPICIOUS", "SWEAT", "TALK", "TANTRUM", "TAUNT", "TEASE", "THANK",
    "THREATEN", "THROW", "TICKLE", "TIRED", "TY", "VICTORY", "VIOLIN",
    "WAIT", "WAVE", "WELCOME", "WHINE", "WHISTLE", "WINK", "WORK", "YAWN",
    "YAY", "YES", "YWL", "BLOW", "CHARGE", "FAIL", "FACEPALM", "FISTBUMP",
    "HANDSHAKE", "LAVISH", "PROMISE", "PUPPY", "SNAP", "CHICKEN", "COVEREARS",
    "CROSSARMS", "HANGHEAD", "HEEL", "LOST", "MUTTERING", "PLUG EARS", "POUT",
    "SHIVER", "SHOO", "SHRUG", "THRILLED", "WIPE", "WOW",
}

-- Merge defaults with existing DB (non-destructive)
function OxedHub:MergeDefaults(db)
    if not db then db = {} end
    if not db.profile then db.profile = {} end
    local profile = db.profile
    
    -- Merge each category
    for key, defaults in pairs(self.DEFAULTS) do
        if type(defaults) == "table" then
            if not profile[key] then
                profile[key] = CopyTable(defaults)
            else
                -- Merge nested tables without overwriting existing
                for id, data in pairs(defaults) do
                    if profile[key][id] == nil then
                        if type(data) == "table" then
                            profile[key][id] = CopyTable(data)
                        else
                            profile[key][id] = data
                        end
                    end
                end
            end
        else
            if profile[key] == nil then
                profile[key] = defaults
            end
        end
    end
    
    -- Ensure version
    db.version = self.CONFIG.DB_VERSION
    
    return db
end

-- Generate unique ID
function OxedHub:GenerateID(prefix)
    return (prefix or "id") .. "_" .. time() .. "_" .. math.random(1000, 9999)
end
