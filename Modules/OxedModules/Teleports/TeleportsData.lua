-- ============================================================================
-- Teleports: what to look for
-- Plain data, read by Teleports.lua. Nothing here runs or registers events.
--
-- Every id is a candidate, never a promise. The module keeps a spell only when
-- the player knows it, a toy only when they own it, an item only when it is in
-- their bags, and gear only when it is worn. An id that is wrong, or that
-- Blizzard retires in a later patch, therefore shows up as nothing at all
-- rather than as a broken button.
--
-- Mage portals are listed per faction because the spells differ; the player's
-- faction picks the table at build time.
-- ============================================================================

local addonName, OxedHub = ...

local Data = {}
OxedHub.TeleportsData = Data

-- ── Class spells ────────────────────────────────────────────────────────────
-- Anything that moves you (or the group) by itself. "self" is a teleport that
-- takes you alone; "group" is a portal your party can step through.

Data.CLASS_SPELLS = {
    MAGE = {
        Alliance = {
            { spell = 3561,   kind = "self"  },  -- Teleport: Stormwind
            { spell = 3562,   kind = "self"  },  -- Teleport: Ironforge
            { spell = 3565,   kind = "self"  },  -- Teleport: Darnassus
            { spell = 32271,  kind = "self"  },  -- Teleport: Exodar
            { spell = 49359,  kind = "self"  },  -- Teleport: Theramore
            { spell = 33690,  kind = "self"  },  -- Teleport: Shattrath
            { spell = 53140,  kind = "self"  },  -- Teleport: Dalaran - Northrend
            { spell = 88342,  kind = "self"  },  -- Teleport: Tol Barad
            { spell = 132621, kind = "self"  },  -- Teleport: Vale of Eternal Blossoms
            { spell = 176248, kind = "self"  },  -- Teleport: Stormshield
            { spell = 224869, kind = "self"  },  -- Teleport: Dalaran - Broken Isles
            { spell = 281403, kind = "self"  },  -- Teleport: Boralus
            { spell = 344587, kind = "self"  },  -- Teleport: Oribos
            { spell = 395277, kind = "self"  },  -- Teleport: Valdrakken
            { spell = 446540, kind = "self"  },  -- Teleport: Dornogal
            { spell = 193759, kind = "self"  },  -- Teleport: Hall of the Guardian
            { spell = 120145, kind = "self"  },  -- Ancient Teleport: Dalaran

            { spell = 10059,  kind = "group" },  -- Portal: Stormwind
            { spell = 11416,  kind = "group" },  -- Portal: Ironforge
            { spell = 11419,  kind = "group" },  -- Portal: Darnassus
            { spell = 32266,  kind = "group" },  -- Portal: Exodar
            { spell = 49360,  kind = "group" },  -- Portal: Theramore
            { spell = 33691,  kind = "group" },  -- Portal: Shattrath
            { spell = 53142,  kind = "group" },  -- Portal: Dalaran - Northrend
            { spell = 88346,  kind = "group" },  -- Portal: Tol Barad
            { spell = 132620, kind = "group" },  -- Portal: Vale of Eternal Blossoms
            { spell = 176246, kind = "group" },  -- Portal: Stormshield
            { spell = 224871, kind = "group" },  -- Portal: Dalaran - Broken Isles
            { spell = 281400, kind = "group" },  -- Portal: Boralus
            { spell = 344598, kind = "group" },  -- Portal: Oribos
            { spell = 395289, kind = "group" },  -- Portal: Valdrakken
            { spell = 446534, kind = "group" },  -- Portal: Dornogal
        },
        Horde = {
            { spell = 3567,   kind = "self"  },  -- Teleport: Orgrimmar
            { spell = 3563,   kind = "self"  },  -- Teleport: Undercity
            { spell = 3566,   kind = "self"  },  -- Teleport: Thunder Bluff
            { spell = 32272,  kind = "self"  },  -- Teleport: Silvermoon
            { spell = 49358,  kind = "self"  },  -- Teleport: Stonard
            { spell = 35715,  kind = "self"  },  -- Teleport: Shattrath
            { spell = 53140,  kind = "self"  },  -- Teleport: Dalaran - Northrend
            { spell = 88344,  kind = "self"  },  -- Teleport: Tol Barad
            { spell = 132627, kind = "self"  },  -- Teleport: Vale of Eternal Blossoms
            { spell = 176242, kind = "self"  },  -- Teleport: Warspear
            { spell = 224869, kind = "self"  },  -- Teleport: Dalaran - Broken Isles
            { spell = 281404, kind = "self"  },  -- Teleport: Dazar'alor
            { spell = 344587, kind = "self"  },  -- Teleport: Oribos
            { spell = 395277, kind = "self"  },  -- Teleport: Valdrakken
            { spell = 446540, kind = "self"  },  -- Teleport: Dornogal
            { spell = 193759, kind = "self"  },  -- Teleport: Hall of the Guardian
            { spell = 120145, kind = "self"  },  -- Ancient Teleport: Dalaran

            { spell = 11417,  kind = "group" },  -- Portal: Orgrimmar
            { spell = 11418,  kind = "group" },  -- Portal: Undercity
            { spell = 11420,  kind = "group" },  -- Portal: Thunder Bluff
            { spell = 32267,  kind = "group" },  -- Portal: Silvermoon
            { spell = 49361,  kind = "group" },  -- Portal: Stonard
            { spell = 35717,  kind = "group" },  -- Portal: Shattrath
            { spell = 53142,  kind = "group" },  -- Portal: Dalaran - Northrend
            { spell = 88346,  kind = "group" },  -- Portal: Tol Barad
            { spell = 132626, kind = "group" },  -- Portal: Vale of Eternal Blossoms
            { spell = 176244, kind = "group" },  -- Portal: Warspear
            { spell = 224871, kind = "group" },  -- Portal: Dalaran - Broken Isles
            { spell = 281402, kind = "group" },  -- Portal: Dazar'alor
            { spell = 344597, kind = "group" },  -- Portal: Oribos
            { spell = 395289, kind = "group" },  -- Portal: Valdrakken
            { spell = 446534, kind = "group" },  -- Portal: Dornogal
        },
    },

    -- Everyone else gets the same list whatever their faction.
    DEATHKNIGHT = { { spell = 50977,  kind = "self" } },   -- Death Gate
    DRUID       = { { spell = 18960,  kind = "self" },     -- Teleport: Moonglade
                    { spell = 193753, kind = "self" } },   -- Dreamwalk
    SHAMAN      = { { spell = 556,    kind = "self" } },   -- Astral Recall
    MONK        = { { spell = 126892, kind = "self" } },   -- Zen Pilgrimage
    WARLOCK     = { { spell = 48020,  kind = "self" } },   -- Demonic Circle: Teleport
}

-- ── Toys ────────────────────────────────────────────────────────────────────
-- Kept apart from the hearthstones, which the toy module already collects.

Data.TOYS = {
    { toy = 172179 },  -- Eternal Traveler's Hearthstone is handled with the other stones
    { toy = 87215 },   -- Wormhole Generator: Pandaria
    { toy = 112059 },  -- Wormhole Centrifuge
    { toy = 151652 },  -- Wormhole Generator: Argus
    { toy = 168807 },  -- Wormhole Generator: Kul Tiras
    { toy = 168808 },  -- Wormhole Generator: Zandalar
    { toy = 172924 },  -- Wormhole Generator: Shadowlands
    { toy = 198156 },  -- Wyrmhole Generator: Dragon Isles
    { toy = 221966 },  -- Wormhole Generator: Khaz Algar
    { toy = 168667 },  -- Bottled Tornado / Brinton 7000 class of gadget
    { toy = 167075 },  -- Ultrasafe Transporter: Mechagon
    { toy = 168222 },  -- Encrypted Black Market Radio
    { toy = 30542 },   -- Dimensional Ripper - Area 52
    { toy = 18984 },   -- Dimensional Ripper - Everlook
    { toy = 18986 },   -- Ultrasafe Transporter: Gadgetzan
    { toy = 48933 },   -- Wormhole Generator: Northrend
    { toy = 128353 },  -- Admiral's Compass
    { toy = 140192 },  -- Dalaran Hearthstone
    { toy = 110560 },  -- Garrison Hearthstone
    { toy = 142542 },  -- Tome of Town Portal
    { toy = 141605 },  -- Flight Master's Whistle
    { toy = 151016 },  -- Fractured Necrolyte Skull
    { toy = 129929 },  -- Wyrmy Tunkins / class of hearth gadget
    { toy = 139590 },  -- Scroll of Teleport: Ravenholdt
    { toy = 93672 },   -- Dark Portal
    { toy = 190237 },  -- Broker Translocation Matrix
    { toy = 200613 },  -- Ohn'ir Windsage's Helm / Algari windstone shard
}

-- ── Items carried in bags ───────────────────────────────────────────────────
-- Consumed or charged items, so they only appear while one is actually held.

Data.ITEMS = {
    { item = 6948 },    -- Hearthstone
    { item = 64488 },   -- The Innkeeper's Daughter
    { item = 40768 },   -- MOLL-E, Mobile Mailbox -- travel kit, kept with these
    { item = 37863 },   -- Direbrew's Remote
    { item = 184500 },  -- Venthyr Sinstone / covenant pocket portal
    { item = 184501 },  -- Pocket Portal: Oribos
    { item = 184502 },
    { item = 184503 },
    { item = 184504 },
    { item = 64457 },   -- The Last Relic of Argus
    { item = 136849 },  -- Nature's Beacon
    { item = 52251 },   -- Jaina's Locket
    { item = 87216 },   -- Thermal Anvil class gadget kept for travel kits
    { item = 253629 },  -- Arcane Society private key (12.0)
}

-- ── Worn gear ───────────────────────────────────────────────────────────────
-- Cloaks and rings whose on-use is a teleport. Checked against the slots the
-- player is wearing, so a cloak in the bank is not offered.

Data.EQUIP = {
    { item = 65274 },   -- Cloak of Coordination
    { item = 65360 },   -- Cloak of Coordination
    { item = 63206 },   -- Wrap of Unity
    { item = 63207 },   -- Wrap of Unity
    { item = 63352 },   -- Shroud of Cooperation
    { item = 63353 },   -- Shroud of Cooperation
    { item = 103678 },  -- Time-Lost Artifact
    { item = 142469 },  -- Violet Seal of the Grand Magus
    { item = 144391 },  -- Pugilist's Powerful Punching Ring
    { item = 144392 },  -- Pugilist's Powerful Punching Ring
}

-- Slots worth checking for worn teleports: back, both rings, both trinkets,
-- and the neck. Scanning every slot would cost nothing extra, but these are
-- the only ones such an effect has ever lived in.
Data.EQUIP_SLOTS = { 2, 11, 12, 13, 14, 15 }

Data.GROUP_LABELS = {
    hearth  = "Hearthstones",
    class   = "Class teleports",
    portal  = "Portals for the group",
    toy     = "Toys",
    item    = "In your bags",
    equip   = "Worn",
}

-- The order the groups appear in the window.
Data.GROUP_ORDER = { "hearth", "class", "portal", "toy", "item", "equip" }
