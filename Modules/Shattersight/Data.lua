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
            if C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(mat.id)
            else
                GetItemInfo(mat.id)
            end
        end
    end
end
