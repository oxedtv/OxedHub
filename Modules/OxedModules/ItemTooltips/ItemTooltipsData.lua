-- ============================================================================
-- Item Tooltips: defaults and lists (built-in OxedHub module)
-- Loaded before ItemTooltips.lua; see that file for what each setting does.
-- ============================================================================

local addonName, OxedHub = ...
OxedHub.ItemTooltips = OxedHub.ItemTooltips or {}
local ItemTooltips = OxedHub.ItemTooltips
ItemTooltips.Data = ItemTooltips.Data or {}
local Data = ItemTooltips.Data

-- ⚠ Only true/false/number/string here: ModuleAPI copies defaults key by key,
-- and a table would be shared by every character. Colours and the inventory
-- tables are made in BindSettings.
Data.DEFAULTS = {
    enabled               = false, -- off until the player switches it on (see ModuleAPI:Register)
    hideInCombat          = true,  -- no extra lines in a fight

    -- The sections
    showIds               = true,
    showAuraInfo          = true,
    showItemDetails       = true,
    showCollection        = true,
    showInventory         = true,
    showIcon              = false,
    qualityBorder         = false,

    -- When each section shows: "always", "shift", "ctrl", "alt", "never"
    mod_ids               = "always",
    mod_auras             = "always",
    mod_details           = "always",
    mod_inventory         = "always",

    -- ID numbers
    showItemId            = true,
    showSpellId           = true,
    showAuraSpellId       = true,
    showUnitId            = true,
    showCurrencyId        = true,
    showQuestId           = true,
    showAchievementId     = true,
    showMountId           = true,
    showToyId             = true,
    showPetId             = true,
    showTransmogId        = false,
    showEnchantId         = false,
    showGemIds            = false,
    showIconId            = false,
    idPrefix              = "label", -- "label" (Item ID: 123), "short" (#123), "brackets" ([Item ID: 123])
    copyOnClick           = false,   -- Ctrl+Shift-click an item prints its ID in chat

    -- Aura details
    showAuraCaster        = true,
    colorCasterByClass    = true,
    colorCasterByReaction = true,
    showDispelType        = true,
    colorByDispel         = true,
    showAuraDuration      = true,
    showAuraStacks        = true,

    -- Item details
    showItemLevel         = false,   -- the game shows it on gear already
    showExpansionName     = true,
    showStackCount        = true,
    showItemType          = true,
    showEquipSlot         = false,
    showKeystoneDetails   = true,
    showStackPrice        = true,    -- vendor price of a full stack

    -- Collection status
    showMountCollected    = true,
    showToyCollected      = true,
    showPetCollected      = true,
    showTransmogCollected = true,

    -- Inventory and alts
    trackCurrentBags      = true,
    trackCurrentEquipped  = true,
    trackCurrentBank      = true,
    trackCurrentMail      = true,
    trackWarbandBank      = true,
    trackAlts             = true,
    colorAltsByClass      = true,
    showAltRealm          = "different", -- "never", "different", "always"
    showAltFaction        = true,
    showTotalCount        = true,
    totalHighlight        = true,
    maxAltsToShow         = 8,
    sortAltsBy            = "count",     -- "count", "name", "realm"
    onlySameRealm         = false,
    onlySameFaction       = false,

    -- Icon beside the tooltip
    iconSize              = 36,
    iconAnchor            = "TOPLEFT",
    iconOffsetX           = -4,
    iconOffsetY           = 0,
    iconQualityBorder     = true,
    iconStackBadge        = true,

    -- Colours
    customIdColor         = false,
    customAltColor        = false,
    customTotalColor      = false,
}

-- Expansion names by the expansion number GetItemInfo returns.
Data.EXPANSIONS = {
    [0]  = "Classic",
    [1]  = "The Burning Crusade",
    [2]  = "Wrath of the Lich King",
    [3]  = "Cataclysm",
    [4]  = "Mists of Pandaria",
    [5]  = "Warlords of Draenor",
    [6]  = "Legion",
    [7]  = "Battle for Azeroth",
    [8]  = "Shadowlands",
    [9]  = "Dragonflight",
    [10] = "The War Within",
    [11] = "Midnight",
}

Data.DISPEL_COLORS = {
    Magic   = "3399ff",
    Curse   = "9900ff",
    Disease = "996600",
    Poison  = "009900",
    Enrage  = "ff8000",
}

-- Mythic Keystones, old and current.
Data.KEYSTONE_ITEMS = { [180653] = true, [158923] = true, [151086] = true }

Data.MODIFIER_CHOICES = {
    { value = "always", text = "Always" },
    { value = "shift",  text = "Holding Shift" },
    { value = "ctrl",   text = "Holding Ctrl" },
    { value = "alt",    text = "Holding Alt" },
    { value = "never",  text = "Never" },
}

Data.ID_FORMAT_CHOICES = {
    { value = "label",    text = "Item ID: 1234" },
    { value = "short",    text = "#1234" },
    { value = "brackets", text = "[Item ID: 1234]" },
}

Data.REALM_CHOICES = {
    { value = "different", text = "Other realms only" },
    { value = "always",    text = "Always" },
    { value = "never",     text = "Never" },
}

Data.SORT_ALTS_CHOICES = {
    { value = "count", text = "Most first" },
    { value = "name",  text = "Name" },
    { value = "realm", text = "Realm, then name" },
}

Data.ICON_ANCHORS = {
    { value = "TOPLEFT",     text = "Left, top" },
    { value = "BOTTOMLEFT",  text = "Left, bottom" },
    { value = "TOPRIGHT",    text = "Right, top" },
    { value = "BOTTOMRIGHT", text = "Right, bottom" },
}
