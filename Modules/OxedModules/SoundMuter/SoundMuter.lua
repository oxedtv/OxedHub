-- ============================================================================
-- Sound Muter (built-in OxedHub module)
-- Silences chosen game sounds and NPC voice lines, each group either always
-- or only while you are in combat. Any other sound can be added by its file
-- ID (/oxmute add <id>).
--
-- ⚠ MuteSoundFile lasts until UnmuteSoundFile or the game is restarted, so
-- everything muted here is unmuted again in OnDisable, and a group switched
-- off in the options is unmuted at once. `muted` remembers what this module
-- muted, so it never unmutes a sound some other addon silenced.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L

-- The game's sound file IDs, by group.
local GROUPS = {
    { key = "bloodlust", label = "Bloodlust, Heroism and Time Warp", ids = {
        568812, 569013, 569578, 569379, 568818, 569126, 568451, 4567038, 4567040,
        4567042, 1416760, 1416761, 1416762, 4558551, 4558553, 4558555, 4558557,
        4558559, 4575217, 4575219, 4575221 } },
    { key = "warlock", label = "Warlock demon summons", ids = {
        551168, 547320, 547328, 547335, 547332, 561163, 561168, 561157, 561154,
        2068351, 2068352, 561144, 1466150 } },
    { key = "pterodactyl", label = "Pterrordax mount screech", ids = {
        838877, 838879, 838881, 838883, 838885, 838887, 838903, 838905, 838907,
        838909, 838911, 838913, 838915, 838917, 838919, 838921 } },
    { key = "yak", label = "Grand Expedition Yak vendors", ids = {
        640336, 640338, 640340, 640314, 640316, 640318, 640320,
        640180, 640182, 640184, 640158, 640160, 640162, 640164 } },
    { key = "banlu", label = "Ban-Lu, Grandmaster's companion", ids = { 1593212, 1593213, 1593214 } },
    { key = "peafowl", label = "Peafowl mount calls", ids = { 5546937, 5546939, 5546941, 5546943 } },
    { key = "summon", label = "Summoning stone portal", ids = {
        568938, 1684459, 1684460, 1684461, 1684462, 1684463 } },
    { key = "repair", label = "Repair sound", ids = { 569801, 569811, 569792, 569794, 569821 } },
    { key = "pings", label = "Pings (minimap and ping system)", ids = {
        567416, 5342387, 5339002, 5339006, 5340605, 5350036 } },
    { key = "auction", label = "Auction house open and close", ids = { 567482, 567499 } },
}
OxedHub:RegisterLocalizedTable(GROUPS, "label")

local DEFAULTS = {
    enabled = false,   -- off until the player switches it on
    -- mode_<group> ("off", "always" or "combat") is added below; "custom" is a table and
    -- is built at login: a table in DEFAULTS would be shared by every character.
}
for _, group in ipairs(GROUPS) do
    DEFAULTS["mode_" .. group.key] = "off"
end
DEFAULTS.combat_custom = false

local PREFIX = "|cff00ccffOxedHub Sound Muter:|r "

local settings
local optionsWindow
local running = false
local muted = {}           -- [fileID] = true while this module has it muted
local events = CreateFrame("Frame")
local inCombat = false     -- from the combat events; UnitAffectingCombat can be secret

local MODES = {
    { value = "off",    text = "Plays" },
    { value = "always", text = "Muted" },
    { value = "combat", text = "Muted in combat" },
}

-- Every file that should be silent right now.
local function Wanted()
    local want = {}
    if not running then return want end
    for _, group in ipairs(GROUPS) do
        local mode = settings["mode_" .. group.key]
        if mode == "always" or (mode == "combat" and inCombat) then
            for _, id in ipairs(group.ids) do want[id] = true end
        end
    end
    if not settings.combat_custom or inCombat then
        for id in pairs(settings.custom) do
            if type(id) == "number" then want[id] = true end
        end
    end
    return want
end

local function Apply()
    if not settings then return end
    local want = Wanted()
    for id in pairs(muted) do
        if not want[id] then
            pcall(UnmuteSoundFile, id)
            muted[id] = nil
        end
    end
    for id in pairs(want) do
        if not muted[id] then
            pcall(MuteSoundFile, id)
            muted[id] = true
        end
    end
end

events:SetScript("OnEvent", function(_, event)
    -- Entering or leaving combat: the "only in combat" groups change.
    inCombat = event == "PLAYER_REGEN_DISABLED"
    Apply()
end)

local function Start()
    running = true
    inCombat = InCombatLockdown() and true or false
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Apply()
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    Apply()   -- wants nothing now, so everything this module muted is unmuted
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Sound Muter", 520, 500)
        optionsWindow = w
        for _, group in ipairs(GROUPS) do
            w:AddChoice(settings, "mode_" .. group.key, group._en_label or group.label, MODES, Apply)
        end
        w:AddCheckbox(settings, "combat_custom", "Sounds added by ID: only in combat", nil, Apply)
        w:AddNote("/oxmute add <file ID> silences any other sound, /oxmute remove <file ID> lets it play, /oxmute list shows them. A sound's file ID is listed on wago.tools and Wowhead.")
    end
    optionsWindow:Show()
end

-- ── Slash command ───────────────────────────────────────────────────────────

SLASH_OXEDSOUNDMUTER1 = "/oxmute"
SlashCmdList.OXEDSOUNDMUTER = function(msg)
    if not settings then return end
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local id = tonumber(arg)
    if cmd == "add" and id then
        settings.custom[id] = true
        Apply()
        print(PREFIX .. (L["sound %d is muted."]):format(id))
    elseif cmd == "remove" and id then
        settings.custom[id] = nil
        Apply()
        print(PREFIX .. (L["sound %d plays again."]):format(id))
    elseif cmd == "list" then
        print(PREFIX .. L["added by ID:"])
        for k in pairs(settings.custom) do print("   " .. tostring(k)) end
    else
        ShowOptions()
    end
end

-- ── Login ───────────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.soundmuter
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.soundmuter = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.custom) ~= "table" then config.custom = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "soundmuter",
        name     = "Sound Muter",
        version  = "1.0.0",
        added    = 20261127,
        updated  = 20261127,
        author   = "Oxed",
        category = "character",
        keywords = { "mute", "sound", "silence", "voice", "npc", "annoying", "bloodlust", "yak", "pterrordax" },
        desc     = "Mutes chosen annoying game sounds and NPC voice lines, some only in combat.",
        icon     = "Interface\\Icons\\Spell_Holy_Silence",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.custom) ~= "table" then settings.custom = {} end
            Start()
        end,
        OnDisable = function()
            Stop()
        end,
    })
end)
