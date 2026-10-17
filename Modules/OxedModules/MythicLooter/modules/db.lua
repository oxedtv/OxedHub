local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

KeystoneLoot.DB = {};

local DB = KeystoneLoot.DB;

local CURRENT_SEASON = KeystoneLoot.Config.season;
local DEFAULT_WHISPER_MESSAGE = KeystoneLoot.Config.whisperMessage;

local DB_VERSION = 20;
local CHAR_DB_VERSION = 4;

local observers = {};

function DB:Init()
    self:InitGlobalDB();
    self:InitCharDB();
end

function DB:InitGlobalDB()
    -- TODO: Will be removed in the next version
    if (OxMythicLooterDB and OxMythicLooterDB.minimapButtonEnabled ~= nil) then
        OxMythicLooterDB = {};
    end

    if (not OxMythicLooterDB or not OxMythicLooterDB.version) then
        OxMythicLooterDB = {
            version = 0,
            settings = {},
            favorites = {},
            currentSeason = 0
        };
    end

    while (OxMythicLooterDB.version < DB_VERSION) do
        self:MigrateGlobalDB(OxMythicLooterDB.version);
        OxMythicLooterDB.version = OxMythicLooterDB.version + 1;
    end

    self:CheckSeason();
end

function DB:InitCharDB()
    -- TODO: Will be removed in the next version
    if (OxMythicLooterCharDB and OxMythicLooterCharDB.favoriteLoot ~= nil) then
        OxMythicLooterCharDB = {};
    end

    if (not OxMythicLooterCharDB or not OxMythicLooterCharDB.version) then
        OxMythicLooterCharDB = {
            version = 0,
            filters = {},
            ui = {}
        };
    end

    while (OxMythicLooterCharDB.version < CHAR_DB_VERSION) do
        self:MigrateCharDB(OxMythicLooterCharDB.version);
        OxMythicLooterCharDB.version = OxMythicLooterCharDB.version + 1;
    end
end

function DB:MigrateGlobalDB(fromVersion)
    if (fromVersion == 0) then
        -- First install
        OxMythicLooterDB.settings = {
            minimap = {
                enabled = true,
                degrees = 195
            },
            lootReminder = {
                dungeons = true
            },
            highlighting = {
                crit = true,
                haste = true,
                mastery = true,
                versatility = true,
                noStats = true
            },
            keystoneTooltip = true
        };

        OxMythicLooterDB.favorites = {};
    end

    if (fromVersion == 1) then
        OxMythicLooterDB.settings.favoriteTooltip = true;
    end

    if (fromVersion == 2) then
        OxMythicLooterDB.settings.hiddenCharacters = {};
    end

    if (fromVersion == 3) then
        OxMythicLooterDB.settings.wideMode = false;
    end

    if (fromVersion == 4) then
        OxMythicLooterDB.settings.highlighting.comboMode = false;
    end

    if (fromVersion == 5) then
        OxMythicLooterDB.settings.hideOtherItems = false;
    end

    if (fromVersion == 6) then
        OxMythicLooterDB.settings.lootReminder.dropAlert = true;
        OxMythicLooterDB.settings.lootReminder.whisperMessage = DEFAULT_WHISPER_MESSAGE;
    end

    if (fromVersion == 7) then
        OxMythicLooterDB.settings.multiSlotFilter = false;
    end

    if (fromVersion == 8) then
        OxMythicLooterDB.settings.keyCommand = {
            CHAT_MSG_PARTY = true,
            CHAT_MSG_PARTY_LEADER = true,
            CHAT_MSG_GUILD = true
        };
    end

    if (fromVersion == 9) then
        OxMythicLooterDB.settings.favoriteIcon = true;
    end

    if (fromVersion == 10) then
        OxMythicLooterDB.settings.slotName = true;
    end

    if (fromVersion == 11) then
        OxMythicLooterDB.settings.mythicPlusNotification = true;
    end

    if (fromVersion == 12) then
        OxMythicLooterDB.settings.lootReminder.party = true;
    end

    if (fromVersion == 13) then
        OxMythicLooterDB.settings.ownedTooltip = true;
    end

    if (fromVersion == 14) then
        OxMythicLooterDB.settings.lootReminder.share = true;

        if (OxMythicLooterDB.settings.lootReminder.whisperMessage == "Can I have {item} please?") then
            OxMythicLooterDB.settings.lootReminder.whisperMessage = DEFAULT_WHISPER_MESSAGE;
        end
    end

    if (fromVersion == 15) then
        OxMythicLooterDB.settings.roleCheck = KeystoneLoot.RoleCheck.MODE_MYTHIC_PLUS;
    end

    if (fromVersion == 16) then
        OxMythicLooterDB.settings.windowScale = 100;
    end

    if (fromVersion == 17) then
        OxMythicLooterDB.settings.ownedCheck = "hero";
    end

    if (fromVersion == 18) then
        local enabled = OxMythicLooterDB.settings.mythicPlusNotification;
        OxMythicLooterDB.settings.mythicPlusNotification = {
            joined = enabled,
            full = enabled
        };
    end

    if (fromVersion == 19) then
        OxMythicLooterDB.settings.favoriteIcon = OxMythicLooterDB.settings.favoriteIcon and "BOTTOMLEFT";
    end
end

function DB:MigrateCharDB(fromVersion)
    if (fromVersion == 0) then
        -- First install
        local _, _, classId = UnitClass("player");
        local specId = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization() or 1);

        OxMythicLooterCharDB.filters = {
            classId = classId,
            specId = specId or 0,
            slotId = 0,
            dungeon = {
                track = "champion",
                rank = 1
            },
            raid = {
                difficulty = "normal",
                rank = 1
            }
        };

        OxMythicLooterCharDB.ui = {
            selectedTab = "dungeons",
            selectedRaidTab = KeystoneLoot.RaidDatabase[1].journalInstanceId
        }
    end

    if (fromVersion == 1) then
        OxMythicLooterCharDB.voidcore = {};
    end

    if (fromVersion == 2) then
        OxMythicLooterCharDB.voidcoreChecked = false;
    end

    if (fromVersion == 3) then
        OxMythicLooterCharDB.bankTracks = {};
    end
end

function DB:CheckSeason()
    local currentSeason = CURRENT_SEASON;

    if (not OxMythicLooterDB.currentSeason) then
        OxMythicLooterDB.currentSeason = currentSeason;
        return;
    end

    if (OxMythicLooterDB.currentSeason ~= currentSeason) then
        -- New season - wipe all favorites
        wipe(OxMythicLooterDB.favorites);
        OxMythicLooterDB.currentSeason = currentSeason;
    end
end

function DB:Get(path)
    local keys = { strsplit(".", path) };
    local current = OxMythicLooterCharDB;

    -- Try CharDB first
    for _, key in ipairs(keys) do
        if (current) then
            current = current[key];
        else
            break;
        end
    end

    -- Fallback to global DB
    if (current == nil) then
        current = OxMythicLooterDB;

        for _, key in ipairs(keys) do
            if (current) then
                current = current[key];
            else
                break;
            end
        end
    end

    return current;
end

function DB:Set(path, value)
    local keys = { strsplit(".", path) };
    local lastKey = table.remove(keys);

    -- Determine which DB
    local db
    if (path:match("^settings") or path:match("^favorites")) then
        db = OxMythicLooterDB;
    else
        db = OxMythicLooterCharDB;
    end

    -- Navigate to parent
    local current = db;
    for _, key in ipairs(keys) do
        if (not current[key]) then
            current[key] = {};
        end

        current = current[key];
    end

    -- Set value
    current[lastKey] = value;

    -- Notify observers
    self:Notify(path, value);
end

function DB:AddObserver(key, callback)
    if (not observers[key]) then
        observers[key] = {};
    end

    table.insert(observers[key], callback);
end

function DB:Notify(path, value)
    -- Exact match
    if (observers[path]) then
        for _, callback in ipairs(observers[path]) do
            callback(value);
        end
    end

    -- Wildcard match (e.g., "filters.*")
    for pattern, callbacks in pairs(observers) do
        if (pattern:match("%*$")) then
            local prefix = pattern:gsub("%*$", "");
            if (path:match("^" .. prefix)) then
                for _, callback in ipairs(callbacks) do
                    callback(value);
                end
            end
        end
    end
end
