-- Data.lua
-- Shattersight Disenchanting data and tables for OxedHub
-- Disenchanting outcome tables keyed by [expansionID][itemQuality].

local addonName, OxedHub = ...

OxedHub.Shattersight = OxedHub.Shattersight or {}
local SS = OxedHub.Shattersight

local EXP_TWW      = (LE_EXPANSION_WAR_WITHIN ~= nil) and LE_EXPANSION_WAR_WITHIN or 10
local EXP_MIDNIGHT = (LE_EXPANSION_MIDNIGHT   ~= nil) and LE_EXPANSION_MIDNIGHT   or 11

SS.EXP_TWW      = EXP_TWW
SS.EXP_MIDNIGHT = EXP_MIDNIGHT

-- ---------------------------------------------------------------------------
-- Material definitions
-- ---------------------------------------------------------------------------
SS.MATS = {
    -- ---- The War Within (expansionID 10) ----------------------------------
    TWW_STORM_DUST_Q1        = { id = 219946, name = "Storm Dust",        qualityTier = 1 },
    TWW_STORM_DUST_Q2        = { id = 219947, name = "Storm Dust",        qualityTier = 2 },
    TWW_STORM_DUST_Q3        = { id = 219948, name = "Storm Dust",        qualityTier = 3 },
    TWW_GLEAMING_SHARD_Q1    = { id = 219949, name = "Gleaming Shard",    qualityTier = 1 },
    TWW_GLEAMING_SHARD_Q2    = { id = 219950, name = "Gleaming Shard",    qualityTier = 2 },
    TWW_GLEAMING_SHARD_Q3    = { id = 219951, name = "Gleaming Shard",    qualityTier = 3 },
    TWW_REFULGENT_CRYSTAL_Q1 = { id = 219952, name = "Refulgent Crystal", qualityTier = 1 },
    TWW_REFULGENT_CRYSTAL_Q2 = { id = 219954, name = "Refulgent Crystal", qualityTier = 2 },
    TWW_REFULGENT_CRYSTAL_Q3 = { id = 219955, name = "Refulgent Crystal", qualityTier = 3 },

    -- ---- Midnight (expansionID 11) ----------------------------------------
    EVERSINGING_DUST_R1 = { id = 243599, name = "Eversinging Dust",  qualityTier = 1 },
    EVERSINGING_DUST_R2 = { id = 243600, name = "Eversinging Dust",  qualityTier = 2 },
    RADIANT_SHARD_R1    = { id = 243602, name = "Radiant Shard",     qualityTier = 1 },
    RADIANT_SHARD_R2    = { id = 243603, name = "Radiant Shard",     qualityTier = 2 },
    DAWN_CRYSTAL_R1     = { id = 243605, name = "Dawn Crystal",      qualityTier = 1 },
    DAWN_CRYSTAL_R2     = { id = 243606, name = "Dawn Crystal",      qualityTier = 2 },
}

-- Reverse lookup: itemID -> mat entry
SS.MATS_BY_ID = {}
for _, mat in pairs(SS.MATS) do
    if mat.id and mat.id > 0 then
        SS.MATS_BY_ID[mat.id] = mat
    end
end

-- ---------------------------------------------------------------------------
-- Midnight Disenchanting Specialization node data
-- ---------------------------------------------------------------------------
SS.MIDNIGHT_SPEC_NODES = {
    [107649] = {
        name          = "Disenchanting Delegate",
        perPointSkill = 1,
        qualityFilter = nil,
        breakpoints   = {
            { minPoints = 1,  skill = 5  },
            { minPoints = 10, skill = 5  },
            { minPoints = 20, skill = 10 },
            { minPoints = 30, skill = 20 },
        },
        parentPathID  = nil,
    },
    [107647] = {
        name          = "Shard Supplier",
        perPointSkill = 1,
        qualityFilter = 3,
        breakpoints   = {
            { minPoints = 1,  skill = 5  },
            { minPoints = 5,  skill = 5  },
            { minPoints = 10, skill = 5  },
            { minPoints = 15, skill = 5  },
            { minPoints = 25, skill = 10 },
            { minPoints = 30, skill = 20 },
        },
        parentPathID  = 107649,
    },
    [107648] = {
        name          = "Dust Deliverer",
        perPointSkill = 1,
        qualityFilter = 2,
        breakpoints   = {
            { minPoints = 1,  skill = 5  },
            { minPoints = 5,  skill = 5  },
            { minPoints = 10, skill = 5  },
            { minPoints = 15, skill = 5  },
            { minPoints = 25, skill = 10 },
            { minPoints = 30, skill = 20 },
        },
        parentPathID  = 107649,
    },
    [107646] = {
        name          = "Crystal Collector",
        perPointSkill = 1,
        qualityFilter = 4,
        breakpoints   = {
            { minPoints = 1,  skill = 5  },
            { minPoints = 5,  skill = 5  },
            { minPoints = 10, skill = 5  },
            { minPoints = 15, skill = 5  },
            { minPoints = 25, skill = 10 },
            { minPoints = 30, skill = 20 },
        },
        parentPathID  = 107649,
    },
}

-- ---------------------------------------------------------------------------
-- Disenchant outcome table
-- ---------------------------------------------------------------------------
SS.DISENCHANT = {
    [EXP_TWW] = {
        [2] = {
            { matKey = "TWW_STORM_DUST_Q3", minQty = 1, maxQty = 2, chance = 0.50 },
            { matKey = "TWW_STORM_DUST_Q2", minQty = 1, maxQty = 3, chance = 0.35 },
            { matKey = "TWW_STORM_DUST_Q1", minQty = 1, maxQty = 3, chance = 0.15 },
        },
        [3] = {
            { matKey = "TWW_GLEAMING_SHARD_Q3", minQty = 1, maxQty = 1, chance = 0.50 },
            { matKey = "TWW_GLEAMING_SHARD_Q2", minQty = 1, maxQty = 1, chance = 0.35 },
            { matKey = "TWW_GLEAMING_SHARD_Q1", minQty = 1, maxQty = 1, chance = 0.15 },
        },
        [4] = {
            { matKey = "TWW_REFULGENT_CRYSTAL_Q3", minQty = 1, maxQty = 1, chance = 0.50 },
            { matKey = "TWW_REFULGENT_CRYSTAL_Q2", minQty = 1, maxQty = 1, chance = 0.35 },
            { matKey = "TWW_REFULGENT_CRYSTAL_Q1", minQty = 1, maxQty = 1, chance = 0.15 },
        },
    },
    [EXP_MIDNIGHT] = {
        [2] = {
            { matKey = "EVERSINGING_DUST_R2", minQty = 1, maxQty = 2, chance = 0.90 },
            { matKey = "EVERSINGING_DUST_R1", minQty = 1, maxQty = 2, chance = 0.10 },
        },
        [3] = {
            { matKey = "RADIANT_SHARD_R2",    minQty = 1, maxQty = 1, chance = 0.45 },
            { matKey = "RADIANT_SHARD_R1",    minQty = 1, maxQty = 1, chance = 0.45 },
            { matKey = "EVERSINGING_DUST_R2", minQty = 1, maxQty = 3, chance = 0.10 },
        },
        [4] = {
            { matKey = "DAWN_CRYSTAL_R2", minQty = 1, maxQty = 1, chance = 0.75 },
            { matKey = "DAWN_CRYSTAL_R1", minQty = 1, maxQty = 1, chance = 0.25 },
        },
    },
}

function SS:GetDisenchantResults(quality, expansionID)
    local expData = SS.DISENCHANT[expansionID]
    if not expData then return nil end
    return expData[quality]
end

function SS:PreloadMatNames()
    for _, mat in pairs(SS.MATS) do
        if mat.id and mat.id > 0 then
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(mat.id)
            elseif C_Item and C_Item.GetItemInfo then
                C_Item.GetItemInfo(mat.id)
            elseif GetItemInfo then
                GetItemInfo(mat.id)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- WoW Forever (classic-era items): outcomes depend on item level, not on
-- expansionID, and weapons swap the dust / essence odds.
-- ---------------------------------------------------------------------------
local CL = {
    STRANGE_DUST = 10940, SOUL_DUST = 11083, VISION_DUST = 11137,
    DREAM_DUST = 11176, ILLUSION_DUST = 16204,
    LESSER_MAGIC = 10938, GREATER_MAGIC = 10939,
    LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082,
    LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135,
    LESSER_NETHER = 11174, GREATER_NETHER = 11175,
    LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203,
    SMALL_GLIMMERING = 10978, LARGE_GLIMMERING = 11084,
    SMALL_GLOWING = 11138, LARGE_GLOWING = 11139,
    SMALL_RADIANT = 11177, LARGE_RADIANT = 11178,
    SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
    NEXUS_CRYSTAL = 20725,
}
for key, id in pairs(CL) do
    local matKey = "CLASSIC_" .. key
    SS.MATS[matKey] = { id = id, name = key, classic = true }
    SS.MATS_BY_ID[id] = SS.MATS[matKey]
end

-- { maxIlvl, dust, dustMin, dustMax, essence, essMin, essMax, shard }
local UNCOMMON_BRACKETS = {
    { 15, "STRANGE_DUST", 1, 2, "LESSER_MAGIC",    1, 2, nil },
    { 20, "STRANGE_DUST", 2, 3, "GREATER_MAGIC",   1, 2, "SMALL_GLIMMERING" },
    { 25, "STRANGE_DUST", 4, 6, "LESSER_ASTRAL",   1, 1, "SMALL_GLIMMERING" },
    { 30, "SOUL_DUST",    1, 2, "GREATER_ASTRAL",  1, 2, "LARGE_GLIMMERING" },
    { 35, "SOUL_DUST",    2, 5, "LESSER_MYSTIC",   1, 2, "SMALL_GLOWING" },
    { 40, "VISION_DUST",  1, 2, "GREATER_MYSTIC",  1, 2, "LARGE_GLOWING" },
    { 45, "VISION_DUST",  2, 5, "LESSER_NETHER",   1, 2, "SMALL_RADIANT" },
    { 50, "DREAM_DUST",   1, 2, "GREATER_NETHER",  1, 2, "LARGE_RADIANT" },
    { 55, "DREAM_DUST",   2, 5, "LESSER_ETERNAL",  1, 2, "SMALL_BRILLIANT" },
    { 60, "ILLUSION_DUST",1, 2, "GREATER_ETERNAL", 1, 2, "LARGE_BRILLIANT" },
    { 99, "ILLUSION_DUST",2, 5, "GREATER_ETERNAL", 2, 3, "LARGE_BRILLIANT" },
}
local RARE_BRACKETS = {
    { 25, "SMALL_GLIMMERING" }, { 30, "LARGE_GLIMMERING" },
    { 35, "SMALL_GLOWING" },    { 40, "LARGE_GLOWING" },
    { 45, "SMALL_RADIANT" },    { 50, "LARGE_RADIANT" },
    { 55, "SMALL_BRILLIANT" },  { 99, "LARGE_BRILLIANT", nexus = true },
}
local EPIC_BRACKETS = {
    { 45, "SMALL_RADIANT", 2, 4 }, { 50, "LARGE_RADIANT", 2, 4 },
    { 55, "SMALL_BRILLIANT", 2, 4 }, { 60, "NEXUS_CRYSTAL", 1, 1 },
    { 99, "NEXUS_CRYSTAL", 1, 2 },
}
local CLASSIC_WEAPON = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

local classicCache = {}

function SS:GetClassicDisenchantResults(quality, ilvl, equipLoc)
    ilvl = tonumber(ilvl)
    if not ilvl or ilvl < 1 then return nil end
    local weapon = CLASSIC_WEAPON[equipLoc] and true or false
    local cacheKey = quality .. ":" .. ilvl .. ":" .. tostring(weapon)
    if classicCache[cacheKey] then return classicCache[cacheKey] end

    local out
    if quality == 2 then
        for _, b in ipairs(UNCOMMON_BRACKETS) do
            if ilvl <= b[1] then
                local shard = b[8] and 0.05 or 0
                if b[1] == 25 then shard = 0.10 end
                local main = 1 - shard
                local dustChance = weapon and main * 0.25 or main * 0.75
                local essChance  = main - dustChance
                out = {
                    { matKey = "CLASSIC_" .. b[2], minQty = b[3], maxQty = b[4], chance = dustChance },
                    { matKey = "CLASSIC_" .. b[5], minQty = b[6], maxQty = b[7], chance = essChance },
                }
                if b[8] then
                    out[3] = { matKey = "CLASSIC_" .. b[8], minQty = 1, maxQty = 1, chance = shard }
                end
                table.sort(out, function(a, c) return a.chance > c.chance end)
                break
            end
        end
    elseif quality == 3 then
        for _, b in ipairs(RARE_BRACKETS) do
            if ilvl <= b[1] then
                if b.nexus then
                    out = {
                        { matKey = "CLASSIC_" .. b[2], minQty = 1, maxQty = 1, chance = 0.995 },
                        { matKey = "CLASSIC_NEXUS_CRYSTAL", minQty = 1, maxQty = 1, chance = 0.005 },
                    }
                else
                    out = { { matKey = "CLASSIC_" .. b[2], minQty = 1, maxQty = 1, chance = 1.0 } }
                end
                break
            end
        end
    elseif quality == 4 and ilvl >= 40 then
        for _, b in ipairs(EPIC_BRACKETS) do
            if ilvl <= b[1] then
                out = { { matKey = "CLASSIC_" .. b[2], minQty = b[3], maxQty = b[4], chance = 1.0 } }
                break
            end
        end
    end

    classicCache[cacheKey] = out
    return out
end
