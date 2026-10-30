-- ============================================================================
-- Item Tooltips (built-in OxedHub module)
-- More on every hover, ideas from TipTac, BagSync and Syndicator, own code:
--
--   * ID numbers: item, spell, aura, NPC, currency, quest, achievement,
--     mount, toy, battle pet species, appearance and source, enchant, gems,
--     icon. The format and the key that shows them are yours.
--   * Aura details: who cast it (class or reaction colour), dispel type,
--     time left, stacks.
--   * Item details: expansion, item type, slot, max stack and the vendor
--     price of a full stack, keystone dungeon, level and affixes.
--   * Collected or not: mounts, toys, battle pets, appearances.
--   * Inventory across the account: this character's bags, gear, bank and
--     mail, the warband bank, and every alt, with a total.
--   * An icon beside the tooltip and a border in the item's quality colour.
--
-- ⚠ Notes for whoever edits this next:
--   * Aura details are read from the tooltip's own getter (GetPrimaryTooltip
--     Info), not from a hook on SetUnitAura: that hook runs after the tooltip
--     is drawn, so it always showed the previous aura, and in combat it wrote
--     secret values into table keys, which is an error.
--   * Bags are scanned per bag, only the bags that changed, never in combat
--     (the scan waits for the fight to end). Rebuilding everything on every
--     loot was the same garbage problem Durability had.
--   * The bank is the 12.0 one: CharacterBankTab_1..6 and AccountBankTab_1..5,
--     readable only while the bank is open. The old bank bags are a fallback.
--   * The icon and the quality border go only on GameTooltip and
--     ItemRefTooltip, where OnTooltipCleared takes them off again.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local ItemTooltips = OxedHub.ItemTooltips or {}
OxedHub.ItemTooltips = ItemTooltips
local Data = ItemTooltips.Data or {}

local settings
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local optionsWindow
local subWindows = {}
local PREFIX = "|cff00ff00OxedHub:|r "

local tostring, tonumber, type, pairs, ipairs = tostring, tonumber, type, pairs, ipairs
local math_floor, string_format = math.floor, string.format
local table_insert, table_sort, table_concat = table.insert, table.sort, table.concat

-- The tooltips that get the icon, the border and the inventory lines.
local MAIN_TIPS = {}

-- ── Small helpers ───────────────────────────────────────────────────────────

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- A value Lua may look at, or nil.
local function Clean(v)
    if v == nil or Secret(v) then return nil end
    return v
end

local function Active()
    return settings and settings.enabled == true
        and not (settings.hideInCombat and InCombatLockdown())
end

local function CheckModifier(rule)
    if not rule or rule == "always" then return true end
    if rule == "shift" then return IsShiftKeyDown() end
    if rule == "ctrl" then return IsControlKeyDown() end
    if rule == "alt" then return IsAltKeyDown() end
    return false
end

local function ClassHex(classFile)
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    return c and c.colorStr or "ffffffff"
end

local function Coins(copper)
    if not copper or copper <= 0 then return nil end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg"):format(math_floor(copper / 10000))
end

local function IdText(label, id)
    local style = settings.idPrefix or "label"
    if style == "short" then return "#" .. tostring(id) end
    if style == "brackets" then return "[" .. label .. ": " .. tostring(id) .. "]" end
    return label .. ": " .. tostring(id)
end

local function Colours()
    local id = (settings.customIdColor and settings.idColor) or { 0.25, 0.75, 1.0 }
    local alt = (settings.customAltColor and settings.altColor) or { 0.4, 0.9, 0.4 }
    local total = (settings.customTotalColor and settings.totalColor) or { 1.0, 0.82, 0.0 }
    return id, alt, total
end

local function AddId(tooltip, label, id, right)
    local c = Colours()
    tooltip:AddDoubleLine(IdText(label, id), right or "", c[1], c[2], c[3], 0.8, 0.8, 0.8)
end

local function AddInfo(tooltip, label, value, r, g, b)
    local c = Colours()
    tooltip:AddDoubleLine(label, value, c[1], c[2], c[3], r or 1, g or 1, b or 1)
end

local function Collected(tooltip, label, has, extra)
    if has == nil then return end
    tooltip:AddDoubleLine(label, (has and L["|cff40ff40Collected|r"] or L["|cffff5555Not collected|r"]) .. (extra or ""),
        0.8, 0.8, 0.8, 1, 1, 1)
end

-- ── Icon beside the tooltip ─────────────────────────────────────────────────

local function IconFrame(tooltip)
    if tooltip.OxedItemTooltipIcon then return tooltip.OxedItemTooltipIcon end
    local f = CreateFrame("Frame", nil, tooltip, "BackdropTemplate")
    f:SetFrameLevel(tooltip:GetFrameLevel() + 2)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f.texture = f:CreateTexture(nil, "ARTWORK")
    f.texture:SetPoint("TOPLEFT", 1, -1)
    f.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    f.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.count = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    f.count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f:Hide()
    tooltip.OxedItemTooltipIcon = f
    return f
end

local function ShowIcon(tooltip, texture, quality, maxStack)
    if not (settings.showIcon and texture and MAIN_TIPS[tooltip]) then return end
    local f = IconFrame(tooltip)
    local size = tonumber(settings.iconSize) or 36
    local x, y = tonumber(settings.iconOffsetX) or -4, tonumber(settings.iconOffsetY) or 0
    f:SetSize(size, size)
    f:ClearAllPoints()
    local anchor = settings.iconAnchor or "TOPLEFT"
    if anchor == "BOTTOMLEFT" then
        f:SetPoint("BOTTOMRIGHT", tooltip, "BOTTOMLEFT", x, y)
    elseif anchor == "TOPRIGHT" then
        f:SetPoint("TOPLEFT", tooltip, "TOPRIGHT", -x, y)
    elseif anchor == "BOTTOMRIGHT" then
        f:SetPoint("BOTTOMLEFT", tooltip, "BOTTOMRIGHT", -x, y)
    else
        f:SetPoint("TOPRIGHT", tooltip, "TOPLEFT", x, y)
    end
    f.texture:SetTexture(texture)
    local qc = settings.iconQualityBorder and quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if qc then f:SetBackdropBorderColor(qc.r, qc.g, qc.b, 1) else f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1) end
    if settings.iconStackBadge and maxStack and maxStack > 1 then
        f.count:SetText(maxStack)
        f.count:Show()
    else
        f.count:Hide()
    end
    f:Show()
end

-- ── Border in the item's quality colour ─────────────────────────────────────

local function DefaultBorder()
    local c = TOOLTIP_DEFAULT_COLOR
    if c then return c.r or 1, c.g or 1, c.b or 1 end
    return 1, 1, 1
end

local function ColourBorder(tooltip, quality)
    if not (settings.qualityBorder and quality and MAIN_TIPS[tooltip]) then return end
    local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not qc or not (tooltip.NineSlice and tooltip.NineSlice.SetBorderColor) then return end
    tooltip.NineSlice:SetBorderColor(qc.r, qc.g, qc.b, 1)
    tooltip._oxedBorderColoured = true
end

local function OnTooltipCleared(tooltip)
    if tooltip._oxedBorderColoured then
        tooltip._oxedBorderColoured = nil
        if tooltip.NineSlice and tooltip.NineSlice.SetBorderColor then
            tooltip.NineSlice:SetBorderColor(DefaultBorder())
        end
    end
    if tooltip.OxedItemTooltipIcon then tooltip.OxedItemTooltipIcon:Hide() end
end

-- ── Inventory: what each character holds ────────────────────────────────────
-- settings.inventory["Name-Realm"] = { bags = { [bag] = { [itemID] = count } },
--   bank = { [tab] = {...} }, equipped = { [itemID] = count }, mail = {...} }
-- settings.warband = { [tab] = { [itemID] = count } }
-- Kept per bag so a change re-reads that bag only.

local charKey
local function PlayerKey()
    if not charKey then
        local name = UnitName("player")
        local realm = GetRealmName()
        if Secret(name) or Secret(realm) then return nil end
        charKey = (name or "?") .. "-" .. (realm or "?")
    end
    return charKey
end

local function Inventory()
    local key = PlayerKey()
    if not key then return nil end
    local inv = settings.inventory[key]
    if type(inv) ~= "table" or inv.version ~= 2 then
        -- Version 2 keeps counts per bag; anything older is read again.
        inv = { version = 2, bags = {}, bank = {}, equipped = {}, mail = {} }
        settings.inventory[key] = inv
    end
    local record = settings.characters[key]
    if type(record) ~= "table" then
        record = {}
        settings.characters[key] = record
    end
    record.name = UnitName("player")
    record.realm = GetRealmName()
    record.class = select(2, UnitClass("player"))
    record.faction = UnitFactionGroup("player")
    local _, raceFile = UnitRace("player")
    record.race = Clean(raceFile) or record.race
    record.sex = Clean(UnitSex("player")) or record.sex
    record.lastSeen = time()
    return inv
end

local function ReadContainer(store, bag)
    local map = store[bag]
    if type(map) ~= "table" then
        map = {}
        store[bag] = map
    end
    wipe(map)
    local okSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
    slots = okSlots and Clean(slots) or 0
    for slot = 1, slots do
        local id = C_Container.GetContainerItemID(bag, slot)
        if id then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            map[id] = (map[id] or 0) + ((info and info.stackCount) or 1)
        end
    end
end

local PLAYER_BAGS = {}
for bag = 0, (NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 1) do PLAYER_BAGS[bag] = true end

local BANK_TABS, WARBAND_TABS = {}, {}
if Enum and Enum.BagIndex then
    for i = 1, 6 do
        local bag = Enum.BagIndex["CharacterBankTab_" .. i]
        if bag then BANK_TABS[bag] = true end
    end
    for i = 1, 5 do
        local bag = Enum.BagIndex["AccountBankTab_" .. i]
        if bag then WARBAND_TABS[bag] = true end
    end
end
if not next(BANK_TABS) then
    -- A client without bank tabs: the old bank and its bags.
    BANK_TABS[BANK_CONTAINER or -1] = true
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAG_SLOTS or 7) - 1 do BANK_TABS[bag] = true end
end

local bankOpen = false
local dirty = {}          -- bag -> true, re-read on the next pass
local scanQueued = false
local pendingAfterCombat = false

local function ScanEquipped()
    local inv = Inventory()
    if not inv then return end
    local equipped = inv.equipped
    wipe(equipped)
    for slot = (INVSLOT_FIRST_EQUIPPED or 1), (INVSLOT_LAST_EQUIPPED or 19) do
        local id = GetInventoryItemID("player", slot)
        if id then equipped[id] = (equipped[id] or 0) + 1 end
    end
end

local function ScanMail()
    local inv = Inventory()
    if not inv or not GetInboxNumItems then return end
    local mail = inv.mail
    wipe(mail)
    for i = 1, (GetInboxNumItems() or 0) do
        for attach = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
            local _, id, _, count = GetInboxItem(i, attach)
            if id then mail[id] = (mail[id] or 0) + (count or 1) end
        end
    end
end

local function ScanDirty()
    scanQueued = false
    if not (settings and settings.enabled) then return end
    if InCombatLockdown() then
        pendingAfterCombat = true
        return
    end
    local inv = Inventory()
    if not inv then return end
    for bag in pairs(dirty) do
        if PLAYER_BAGS[bag] then
            ReadContainer(inv.bags, bag)
        elseif BANK_TABS[bag] and bankOpen then
            ReadContainer(inv.bank, bag)
        elseif WARBAND_TABS[bag] and bankOpen then
            ReadContainer(settings.warband, bag)
        end
    end
    wipe(dirty)
end

local function QueueScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.5, ScanDirty)
end

local function MarkAll(list)
    for bag in pairs(list) do dirty[bag] = true end
    QueueScan()
end

local function CountIn(byBag, id)
    local n = 0
    if type(byBag) == "table" then
        for _, map in pairs(byBag) do
            if type(map) == "table" then n = n + (map[id] or 0) end
        end
    end
    return n
end

-- ── Item tooltips ───────────────────────────────────────────────────────────

local function ItemDetails(tooltip, itemId, link, info)
    local c = Colours()
    if settings.showItemLevel and link and C_Item.GetDetailedItemLevelInfo then
        local level = C_Item.GetDetailedItemLevelInfo(link)
        if level and level > 1 then AddInfo(tooltip, L["Item level"], tostring(level)) end
    end
    if settings.showExpansionName and info.expansion and Data.EXPANSIONS[info.expansion] then
        AddInfo(tooltip, L["Expansion"], Data.EXPANSIONS[info.expansion])
    end
    if settings.showItemType and info.itemType and info.itemType ~= "" then
        local text = (info.subType and info.subType ~= "" and info.subType ~= info.itemType)
            and (info.itemType .. ", " .. info.subType) or info.itemType
        AddInfo(tooltip, L["Type"], text)
    end
    -- Only a real slot: items that are not worn come back with a slot type
    -- whose name is an empty string (INVTYPE_NON_EQUIP_IGNORE).
    local slotName = settings.showEquipSlot and info.equipLoc and info.equipLoc ~= "" and _G[info.equipLoc]
    if type(slotName) == "string" and slotName ~= "" then
        AddInfo(tooltip, L["Slot"], slotName)
    end
    if settings.showStackCount and info.maxStack and info.maxStack > 1 then
        local stackPrice = settings.showStackPrice and info.sellPrice and info.sellPrice > 0
            and Coins(info.sellPrice * info.maxStack)
        AddInfo(tooltip, L["Max stack"], tostring(info.maxStack) .. (stackPrice and ("  (" .. stackPrice .. ")") or ""))
    end
    -- Keystone: dungeon, level and affixes from the keystone link.
    if settings.showKeystoneDetails and link and Data.KEYSTONE_ITEMS[itemId] then
        local rest = link:match("keystone:%d+:([%d:]+)")
        if rest then
            local parts = {}
            for n in rest:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
            local mapId, level = parts[1], parts[2]
            local mapName = mapId and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapId)
            if mapName and level then
                tooltip:AddDoubleLine(L["Keystone"], ("+%d %s"):format(level, mapName), 1, 0.82, 0, 1, 1, 1)
            end
            local affixes = {}
            for i = 3, #parts do
                local name = C_ChallengeMode and C_ChallengeMode.GetAffixInfo and C_ChallengeMode.GetAffixInfo(parts[i])
                if name then affixes[#affixes + 1] = name end
            end
            if #affixes > 0 then AddInfo(tooltip, L["Affixes"], table_concat(affixes, ", "), 0.9, 0.9, 0.9) end
        end
    end
end

local function ItemIds(tooltip, itemId, link, info)
    if settings.showItemId then AddId(tooltip, L["Item ID"], itemId) end
    if settings.showMountId and C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountId = C_MountJournal.GetMountFromItem(itemId)
        if mountId then AddId(tooltip, L["Mount ID"], mountId) end
    end
    if settings.showToyId and C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemId) then
        AddId(tooltip, L["Toy ID"], itemId)
    end
    if settings.showPetId and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local species = select(13, C_PetJournal.GetPetInfoByItemID(itemId))
        if species then AddId(tooltip, L["Pet species"], species) end
    end
    if settings.showTransmogId and link and C_TransmogCollection and C_TransmogCollection.GetItemInfo then
        local appearance, source = C_TransmogCollection.GetItemInfo(link)
        if appearance then AddId(tooltip, L["Appearance ID"], appearance, source and ("source " .. source) or nil) end
    end
    if link and (settings.showEnchantId or settings.showGemIds) then
        local enchant, g1, g2, g3, g4 = link:match("item:%d+:(%d*):(%d*):(%d*):(%d*):(%d*)")
        enchant = tonumber(enchant)
        if settings.showEnchantId and enchant and enchant > 0 then AddId(tooltip, L["Enchant ID"], enchant) end
        if settings.showGemIds then
            for i, gem in ipairs({ tonumber(g1), tonumber(g2), tonumber(g3), tonumber(g4) }) do
                if gem and gem > 0 then AddId(tooltip, L["Gem "] .. i .. " ID", gem) end
            end
        end
    end
    if settings.showIconId and info.texture then AddId(tooltip, L["Icon ID"], info.texture) end
end

local function ItemCollection(tooltip, itemId, link)
    if settings.showMountCollected and C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountId = C_MountJournal.GetMountFromItem(itemId)
        if mountId then
            Collected(tooltip, L["Mount"], (select(11, C_MountJournal.GetMountInfoByID(mountId))) == true)
        end
    end
    if settings.showToyCollected and C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemId) and PlayerHasToy then
        Collected(tooltip, L["Toy"], PlayerHasToy(itemId) == true)
    end
    if settings.showPetCollected and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local species = select(13, C_PetJournal.GetPetInfoByItemID(itemId))
        if species and C_PetJournal.GetNumCollectedInfo then
            local have, limit = C_PetJournal.GetNumCollectedInfo(species)
            if have then Collected(tooltip, L["Battle pet"], have > 0, ("  %d/%d"):format(have, limit or 3)) end
        end
    end
    if settings.showTransmogCollected and link and C_TransmogCollection
        and C_TransmogCollection.GetItemInfo and C_TransmogCollection.PlayerHasTransmogByItemInfo
        and C_TransmogCollection.GetItemInfo(link) then
        Collected(tooltip, L["Appearance"], C_TransmogCollection.PlayerHasTransmogByItemInfo(link) == true)
    end
end

-- The game's own count, which knows the bank and the warband bank anywhere,
-- bank open or not. nil when it cannot answer.
local GetItemCountFn = (C_Item and C_Item.GetItemCount) or GetItemCount
local function LiveCount(itemId, bank, warband)
    if not GetItemCountFn then return nil end
    local ok, n = pcall(GetItemCountFn, itemId, bank, false, bank, warband)
    n = ok and Clean(n)
    return type(n) == "number" and n or nil
end

-- Bank and warband bank from the live count; the saved scan when the game
-- does not answer. Never below what the scan saw.
local function LiveBankCounts(itemId, savedBank, savedWarband)
    local carried = LiveCount(itemId, false, false)
    local withBank = LiveCount(itemId, true, false)
    local withAll = LiveCount(itemId, true, true)
    local bank, warband = savedBank, savedWarband
    if carried and withBank and withBank >= carried then bank = withBank - carried end
    if withBank and withAll and withAll >= withBank then warband = withAll - withBank end
    return bank, warband
end

local function GuildKey()
    if not IsInGuild() then return nil end
    local name = Clean(GetGuildInfo("player"))
    local realm = Clean(GetRealmName())
    if type(name) ~= "string" or name == "" then return nil end
    return name .. "-" .. (realm or "?")
end

-- The tab on screen in the guild bank: its slots are only known once viewed.
local function ScanGuildTab()
    if not (settings and settings.enabled and settings.trackGuildBank) then return end
    local key = GuildKey()
    local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
    if not key or not tab then return end
    local ok, _, _, viewable = pcall(GetGuildBankTabInfo, tab)
    if not ok or not viewable then return end
    local gb = settings.guildBanks[key]
    if type(gb) ~= "table" then
        gb = { name = Clean(GetGuildInfo("player")), realm = Clean(GetRealmName()), tabs = {} }
        settings.guildBanks[key] = gb
    end
    local map = {}
    for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or 98) do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            local _, count = GetGuildBankItemInfo(tab, slot)
            if id then map[id] = (map[id] or 0) + (tonumber(count) or 1) end
        end
    end
    gb.tabs[tab] = map
    gb.at = time()
end

-- Race portraits from the game's atlas; the few races whose atlas name is not
-- their race file are mapped here.
local RACE_ATLAS = {
    Scourge = "undead", HighmountainTauren = "highmountain", LightforgedDraenei = "lightforged",
    ZandalariTroll = "zandalari", KulTiran = "kultiran", EarthenDwarf = "earthen",
}

local function RaceIcon(who)
    if not (settings.showRaceIcons and who and type(who.race) == "string") then return "" end
    local race = RACE_ATLAS[who.race] or who.race:lower()
    local atlas = ("raceicon128-%s-%s"):format(race, who.sex == 3 and "female" or "male")
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) then return "" end
    return CreateAtlasMarkup and (CreateAtlasMarkup(atlas, 14, 14) .. " ") or ""
end

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t "
local PLACE_ICON = {
    bags    = "|TInterface\\Icons\\INV_Misc_Bag_08:12|t",
    gear    = "|TInterface\\Icons\\INV_Chest_Chain:12|t",
    bank    = "|TInterface\\Icons\\INV_Misc_Coin_02:12|t",
    mail    = "|TInterface\\Icons\\INV_Letter_15:12|t",
    warband = "|TInterface\\Icons\\INV_Misc_Bag_EnchantedRunecloth:12|t",
    guild   = "|TInterface\\Icons\\INV_Misc_Bag_10_Green:12|t",
}

-- "Bags 3, Bank 2", or the numbers with icons when the icon style is on.
local function Places(bags, gear, bank, mail)
    local parts = {}
    local icons = settings.inventoryIcons
    local function Add(n, word, place)
        if n <= 0 then return end
        parts[#parts + 1] = icons and (n .. " " .. PLACE_ICON[place]) or (L[word] .. n)
    end
    Add(bags, "Bags ", "bags")
    Add(gear, "Worn ", "gear")
    Add(bank, "Bank ", "bank")
    Add(mail, "Mail ", "mail")
    return table_concat(parts, icons and "  " or ", ")
end

local function ItemInventory(tooltip, itemId)
    local _, altColour, totalColour = Colours()
    local key = PlayerKey()
    local myRealm, myFaction = GetRealmName(), UnitFactionGroup("player")
    local total = 0
    local chars, others = {}, {}

    local mine = key and settings.inventory[key]
    if type(mine) == "table" then
        local bags = settings.trackCurrentBags and CountIn(mine.bags, itemId) or 0
        local gear = settings.trackCurrentEquipped and mine.equipped and mine.equipped[itemId] or 0
        local bank = settings.trackCurrentBank and CountIn(mine.bank, itemId) or 0
        if settings.trackCurrentBank then bank = (LiveBankCounts(itemId, bank, 0)) end
        local mail = settings.trackCurrentMail and mine.mail and mine.mail[itemId] or 0
        local sum = bags + gear + bank + mail
        if sum > 0 then
            chars[#chars + 1] = { who = settings.characters[key] or {}, key = key, me = true,
                sum = sum, bags = bags, gear = gear, bank = bank, mail = mail }
            total = total + sum
        end
    end

    if settings.trackAlts then
        for altKey, inv in pairs(settings.inventory) do
            local who = settings.characters[altKey]
            if altKey ~= key and type(inv) == "table" and type(who) == "table"
                and (not settings.onlySameRealm or who.realm == myRealm)
                and (not settings.onlySameFaction or who.faction == myFaction) then
                local bags, gear = CountIn(inv.bags, itemId), inv.equipped and inv.equipped[itemId] or 0
                local bank, mail = CountIn(inv.bank, itemId), inv.mail and inv.mail[itemId] or 0
                -- Data saved before per-bag counts: bags and bank were flat maps.
                if inv.version ~= 2 then
                    bags = type(inv.bags) == "table" and tonumber(inv.bags[itemId]) or 0
                    bank = type(inv.bank) == "table" and tonumber(inv.bank[itemId]) or 0
                end
                local sum = bags + gear + bank + mail
                if sum > 0 then
                    chars[#chars + 1] = { who = who, key = altKey, sum = sum, bags = bags, gear = gear, bank = bank, mail = mail }
                    total = total + sum
                end
            end
        end
    end

    if settings.trackWarbandBank then
        local _, warband = LiveBankCounts(itemId, 0, CountIn(settings.warband, itemId))
        if warband > 0 then
            others[#others + 1] = { L["|cff66ccffWarband bank|r"], warband, "warband" }
            total = total + warband
        end
    end

    if settings.trackGuildBank then
        for gKey, gb in pairs(settings.guildBanks) do
            if type(gb) == "table" and (not settings.onlySameRealm or gb.realm == myRealm) then
                local n = CountIn(gb.tabs, itemId)
                if n > 0 then
                    local label = (gb.name or gKey) .. ((gb.realm and gb.realm ~= myRealm) and (" - " .. gb.realm) or "")
                    others[#others + 1] = { "|cff40c040<" .. label .. ">|r", n, "guild" }
                    total = total + n
                end
            end
        end
    end

    local lines = #chars + #others
    if lines == 0 then return end

    local sortBy = settings.sortAltsBy or "count"
    local meFirst = settings.currentFirst ~= false
    table_sort(chars, function(a, b)
        if meFirst and (a.me or false) ~= (b.me or false) then return a.me == true end
        local an, bn = a.who.name or a.key, b.who.name or b.key
        if sortBy == "name" then return an < bn end
        if sortBy == "realm" and (a.who.realm or "") ~= (b.who.realm or "") then
            return (a.who.realm or "") < (b.who.realm or "")
        end
        if sortBy == "realm" then return an < bn end
        if a.sum ~= b.sum then return a.sum > b.sum end
        return an < bn
    end)

    local function Total()
        if not (settings.showTotalCount and lines > 1) then return end
        if settings.totalHighlight then
            tooltip:AddDoubleLine(L["Total"], tostring(total), totalColour[1], totalColour[2], totalColour[3],
                totalColour[1], totalColour[2], totalColour[3])
        else
            tooltip:AddDoubleLine(L["Total"], tostring(total), 1, 1, 1, 1, 1, 1)
        end
    end

    if settings.blankLineBefore then tooltip:AddLine(" ") end
    if settings.totalFirst then Total() end

    local maxShow = tonumber(settings.maxAltsToShow) or 8
    local mode = settings.showAltRealm or "different"
    for i, c in ipairs(chars) do
        if i > maxShow then
            tooltip:AddLine((L["  and %d more"]):format(#chars - maxShow), 0.6, 0.6, 0.6)
            break
        end
        local name = c.who.name or (c.me and L["You"]) or c.key:match("^([^-]+)") or c.key
        local realm = c.who.realm or ""
        local realmText = (realm ~= "" and (mode == "always" or (mode == "different" and realm ~= myRealm)))
            and (" - " .. realm) or ""
        local faction = ""
        if settings.showAltFaction and c.who.faction and c.who.faction ~= myFaction then
            faction = c.who.faction == "Alliance" and " |cff0070dd[A]|r" or c.who.faction == "Horde" and " |cffc41e3a[H]|r" or ""
        end
        local colour = (c.me or settings.colorAltsByClass) and ClassHex(c.who.class) or "ffffffff"
        local mark = (c.me and settings.markCurrent) and CHECK or ""
        tooltip:AddDoubleLine(("%s%s|c%s%s|r%s%s"):format(RaceIcon(c.who), mark, colour, name, realmText, faction),
            Places(c.bags, c.gear, c.bank, c.mail), 1, 1, 1, altColour[1], altColour[2], altColour[3])
    end

    for _, o in ipairs(others) do
        local right = settings.inventoryIcons and (o[2] .. " " .. PLACE_ICON[o[3]])
            or (o[3] == "guild" and (L["Guild bank "] .. o[2]) or tostring(o[2]))
        tooltip:AddDoubleLine(o[1], right, 1, 1, 1, altColour[1], altColour[2], altColour[3])
    end

    if not settings.totalFirst then Total() end
end

local function ProcessItem(tooltip, data)
    if not Active() then return end
    local _, link, itemId
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        _, link, itemId = TooltipUtil.GetDisplayedItem(tooltip)
    end
    if not link and tooltip.GetItem then _, link = tooltip:GetItem() end
    link, itemId = Clean(link), Clean(itemId)
    if not itemId and type(link) == "string" then itemId = tonumber(link:match("item:(%d+)")) end
    if not itemId and data then itemId = Clean(data.id) end
    if type(itemId) ~= "number" then return end
    if type(link) ~= "string" then link = nil end

    -- A keystone link is not an item link: the item's own facts come by id.
    local query = (link and link:find("|Hitem:")) and link or itemId
    local _, _, quality, _, _, itemType, subType, maxStack, equipLoc, texture, sellPrice, _, _, _, expansion =
        C_Item.GetItemInfo(query)
    local info = {
        itemType = itemType, subType = subType, maxStack = maxStack, equipLoc = equipLoc,
        texture = texture, sellPrice = sellPrice, expansion = expansion,
    }

    ColourBorder(tooltip, quality)
    ShowIcon(tooltip, texture, quality, maxStack)

    if settings.showItemDetails and CheckModifier(settings.mod_details) then ItemDetails(tooltip, itemId, link, info) end
    if settings.showCollection then ItemCollection(tooltip, itemId, link) end
    if settings.showIds and CheckModifier(settings.mod_ids) then ItemIds(tooltip, itemId, link, info) end
    -- Account counts on the main tooltips only: comparison tooltips would
    -- repeat them for every item being compared.
    if settings.showInventory and MAIN_TIPS[tooltip] and CheckModifier(settings.mod_inventory) then
        ItemInventory(tooltip, itemId)
    end
end

-- ── Spells and auras ────────────────────────────────────────────────────────

local function ProcessSpell(tooltip, data)
    if not Active() then return end
    local spellId = data and Clean(data.id)
    if type(spellId) ~= "number" then return end
    if settings.showIds and CheckModifier(settings.mod_ids) then
        if settings.showSpellId then AddId(tooltip, L["Spell ID"], spellId) end
        if settings.showMountId and C_MountJournal and C_MountJournal.GetMountFromSpell then
            local mountId = C_MountJournal.GetMountFromSpell(spellId)
            if mountId then AddId(tooltip, L["Mount ID"], mountId) end
        end
    end
end

-- The aura the tooltip is showing, from the tooltip's own getter.
local function AuraOf(tooltip)
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    local getter = info and Clean(info.getterName)
    local args = info and info.getterArgs
    if type(getter) ~= "string" or type(args) ~= "table" or not C_UnitAuras then return nil end
    local unit = Clean(args[1])
    if type(unit) ~= "string" then return nil end
    if getter:find("AuraInstanceID") then
        return C_UnitAuras.GetAuraDataByAuraInstanceID(unit, args[2]), unit
    end
    local filter = (getter == "GetUnitBuff" and "HELPFUL") or (getter == "GetUnitDebuff" and "HARMFUL") or args[3]
    return C_UnitAuras.GetAuraDataByIndex(unit, args[2], filter), unit
end

local function ProcessAura(tooltip, data)
    if not Active() then return end
    local spellId = data and Clean(data.id)
    if settings.showIds and settings.showAuraSpellId and type(spellId) == "number" and CheckModifier(settings.mod_ids) then
        AddId(tooltip, L["Spell ID"], spellId)
    end
    if not (settings.showAuraInfo and CheckModifier(settings.mod_auras)) then return end
    local ok, aura = pcall(AuraOf, tooltip)
    if not ok or type(aura) ~= "table" or Secret(aura) then return end

    if settings.showAuraCaster then
        local source = Clean(aura.sourceUnit)
        if type(source) == "string" then
            local okName, name = pcall(UnitName, source)
            name = okName and Clean(name)
            if type(name) == "string" then
                local colour = "ffffffff"
                local okPlayer, isPlayer = pcall(UnitIsPlayer, source)
                isPlayer = okPlayer and Clean(isPlayer)
                if isPlayer == true and settings.colorCasterByClass then
                    local okClass, _, class = pcall(UnitClass, source)
                    colour = ClassHex(okClass and Clean(class))
                elseif settings.colorCasterByReaction then
                    local okR, reaction = pcall(UnitReaction, source, "player")
                    reaction = okR and Clean(reaction)
                    if type(reaction) == "number" then
                        colour = reaction >= 5 and "ff33ff33" or reaction == 4 and "ffffff33" or "ffff3333"
                    end
                end
                AddInfo(tooltip, L["Cast by"], ("|c%s%s|r"):format(colour, name))
            end
        end
    end
    if settings.showDispelType then
        local dispel = Clean(aura.dispelName)
        if type(dispel) == "string" and dispel ~= "" then
            local hex = settings.colorByDispel and Data.DISPEL_COLORS[dispel]
            AddInfo(tooltip, L["Dispel type"], hex and ("|cff" .. hex .. dispel .. "|r") or dispel)
        end
    end
    if settings.showAuraDuration then
        local dur, exp = Clean(aura.duration), Clean(aura.expirationTime)
        if type(dur) == "number" and type(exp) == "number" and dur > 0 and exp > 0 then
            AddInfo(tooltip, L["Time left"], (L["%.1fs of %ds"]):format(math.max(0, exp - GetTime()), dur))
        end
    end
    if settings.showAuraStacks then
        local stacks = Clean(aura.applications)
        if type(stacks) == "number" and stacks > 1 then AddInfo(tooltip, L["Stacks"], tostring(stacks)) end
    end
end

-- ── Units, currencies, quests, achievements ─────────────────────────────────

local function ProcessUnit(tooltip)
    if not (Active() and settings.showIds and settings.showUnitId and CheckModifier(settings.mod_ids)) then return end
    local okUnit, _, unit = pcall(tooltip.GetUnit, tooltip)
    unit = okUnit and Clean(unit)
    if type(unit) ~= "string" then return end
    local okGuid, guid = pcall(UnitGUID, unit)
    guid = okGuid and Clean(guid)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, _, npcId = strsplit("-", guid)
    if (kind == "Creature" or kind == "Vehicle") and npcId then AddId(tooltip, L["NPC ID"], npcId) end
end

local function SimpleId(label, option)
    return function(tooltip, data)
        if not (Active() and settings.showIds and settings[option] and CheckModifier(settings.mod_ids)) then return end
        local id = data and Clean(data.id)
        if type(id) ~= "number" then return end
        if option == "showAchievementId" and GetAchievementCategory then
            local category = GetAchievementCategory(id)
            AddId(tooltip, label, id, category and ("category " .. category) or nil)
        else
            AddId(tooltip, label, id)
        end
    end
end

-- ── Hooks, installed once at login, quiet while the module is off ───────────

local hooked = false
local function InstallHooks()
    if hooked then return end
    hooked = true
    MAIN_TIPS[GameTooltip] = true
    if ItemRefTooltip then MAIN_TIPS[ItemRefTooltip] = true end
    for tip in pairs(MAIN_TIPS) do tip:HookScript("OnTooltipCleared", OnTooltipCleared) end

    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    local T = Enum.TooltipDataType
    -- A post-call that throws must not break the game's tooltip.
    local function Safe(fn)
        return function(tooltip, data)
            if settings and settings.enabled then pcall(fn, tooltip, data) end
        end
    end
    local hooks = {
        { T.Item, ProcessItem },
        { T.Spell, ProcessSpell },
        { T.UnitAura, ProcessAura },
        { T.Unit, ProcessUnit },
        { T.Currency, SimpleId(L["Currency ID"], "showCurrencyId") },
        { T.Quest, SimpleId(L["Quest ID"], "showQuestId") },
        { T.Achievement, SimpleId(L["Achievement ID"], "showAchievementId") },
    }
    for _, h in ipairs(hooks) do
        if h[1] then TooltipDataProcessor.AddTooltipPostCall(h[1], Safe(h[2])) end
    end

    -- Ctrl+Shift-click an item: its ID in chat. Plain Shift-click is left to
    -- the game (links, split stacks).
    if HandleModifiedItemClick then
        hooksecurefunc("HandleModifiedItemClick", function(link)
            if not (settings and settings.enabled and settings.copyOnClick) then return end
            if not (IsShiftKeyDown() and IsControlKeyDown()) or type(link) ~= "string" or Secret(link) then return end
            local id = link:match("item:(%d+)")
            if id then print(PREFIX .. (L["%s  Item ID: |cffffd100%s|r"]):format(link, id)) end
        end)
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

local watcher = CreateFrame("Frame")

-- The shown tooltip again, so "holding Shift" takes effect at once.
local function RefreshShownTooltip()
    for tip in pairs(MAIN_TIPS) do
        if tip:IsShown() and tip.RefreshData then pcall(tip.RefreshData, tip) end
    end
end

local function UsesModifiers()
    for _, key in ipairs({ "mod_ids", "mod_auras", "mod_details", "mod_inventory" }) do
        local rule = settings[key]
        if rule == "shift" or rule == "ctrl" or rule == "alt" then return true end
    end
    return false
end

watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "BAG_UPDATE" then
        if type(arg1) == "number" then dirty[arg1] = true end
    elseif event == "BAG_UPDATE_DELAYED" then
        QueueScan()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if not InCombatLockdown() then ScanEquipped() else pendingAfterCombat = true end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        MarkAll(BANK_TABS)
        MarkAll(WARBAND_TABS)
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = false
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        -- 12.0 opens the bank through the interaction manager; BANKFRAME_* may not come.
        local t = Enum and Enum.PlayerInteractionType
        local isBank = t and (arg1 == t.Banker or arg1 == t.AccountBanker or arg1 == t.CharacterBanker)
        if isBank and event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            bankOpen = true
            MarkAll(BANK_TABS)
            MarkAll(WARBAND_TABS)
        elseif isBank then
            bankOpen = false
        elseif t and arg1 == t.GuildBanker and event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            C_Timer.After(0.5, ScanGuildTab)
        end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        ScanGuildTab()
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERACCOUNTBANKSLOTS_CHANGED" then
        MarkAll(BANK_TABS)
        MarkAll(WARBAND_TABS)
    elseif event == "MAIL_INBOX_UPDATE" then
        ScanMail()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingAfterCombat then
            pendingAfterCombat = false
            ScanEquipped()
            QueueScan()
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        if UsesModifiers() then RefreshShownTooltip() end
    end
end)

local EVENTS = {
    "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED", "PLAYERACCOUNTBANKSLOTS_CHANGED", "MAIL_INBOX_UPDATE",
    "PLAYER_REGEN_ENABLED", "MODIFIER_STATE_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "GUILDBANKBAGSLOTS_CHANGED",
}

local function Start()
    InstallHooks()
    for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    C_Timer.After(2, function()
        if not (settings and settings.enabled) then return end
        ScanEquipped()
        MarkAll(PLAYER_BAGS)
    end)
end

local function Stop()
    watcher:UnregisterAllEvents()
    for tip in pairs(MAIN_TIPS) do OnTooltipCleared(tip) end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function FitHeight(w)
    if w and w.cursorY then w:SetHeight(math.max(140, -w.cursorY + 24)) end
end

local function Heading(w, text)
    local h = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 6)
    h:SetText(text)
    w.cursorY = w.cursorY - 24
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(b) end
    return b
end

local function ToggleSub(name, build)
    local w = subWindows[name]
    if not w then
        w = build()
        subWindows[name] = w
    end
    if w:IsShown() then w:Hide() return end
    for other, window in pairs(subWindows) do
        if other ~= name then window:Hide() end
    end
    if optionsWindow then
        w:ClearAllPoints()
        if (optionsWindow:GetRight() or 0) + w:GetWidth() + 8 <= UIParent:GetWidth() then
            w:SetPoint("TOPLEFT", optionsWindow, "TOPRIGHT", 8, 0)
        else
            w:SetPoint("TOPRIGHT", optionsWindow, "TOPLEFT", -8, 0)
        end
    end
    w:Show()
    w:Raise()
end

local function ButtonGrid(w, items)
    local width = math_floor((w:GetWidth() - 50) / 2)
    for i, item in ipairs(items) do
        local col = (i - 1) % 2
        if i > 1 and col == 0 then w.cursorY = w.cursorY - 26 end
        local b = Button(w, item[1], width, item[2])
        b:SetPoint("TOPLEFT", w, "TOPLEFT", 20 + col * (width + 10), w.cursorY - 4)
    end
    w.cursorY = w.cursorY - 34
end

local function BuildIdsWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: ID Numbers", 440, 600)
    Heading(w, L["Which IDs"])
    w:AddCheckbox(settings, "showItemId", "Item ID")
    w:AddCheckbox(settings, "showSpellId", "Spell ID")
    w:AddCheckbox(settings, "showAuraSpellId", "Spell ID on buffs and debuffs")
    w:AddCheckbox(settings, "showUnitId", "NPC ID")
    w:AddCheckbox(settings, "showCurrencyId", "Currency ID")
    w:AddCheckbox(settings, "showQuestId", "Quest ID")
    w:AddCheckbox(settings, "showAchievementId", "Achievement ID and category")
    w:AddCheckbox(settings, "showMountId", "Mount ID", "On mount items and mount spells.")
    w:AddCheckbox(settings, "showToyId", "Toy ID")
    w:AddCheckbox(settings, "showPetId", "Battle pet species ID", "On pet cage and companion items.")
    w:AddCheckbox(settings, "showTransmogId", "Appearance and source ID")
    w:AddCheckbox(settings, "showEnchantId", "Enchant ID")
    w:AddCheckbox(settings, "showGemIds", "Socketed gem IDs")
    w:AddCheckbox(settings, "showIconId", "Icon (file) ID")
    Heading(w, L["Format"])
    w:AddChoice(settings, "idPrefix", "Written as", Data.ID_FORMAT_CHOICES)
    w:AddChoice(settings, "mod_ids", "Show IDs", Data.MODIFIER_CHOICES)
    w:AddCheckbox(settings, "copyOnClick", "Ctrl+Shift-click an item prints its ID in chat")
    FitHeight(w)
    return w
end

local function BuildAurasWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Buffs and Debuffs", 440, 400)
    Heading(w, L["On a buff or debuff"])
    w:AddCheckbox(settings, "showAuraCaster", "Who cast it")
    w:AddCheckbox(settings, "colorCasterByClass", "Players in their class colour")
    w:AddCheckbox(settings, "colorCasterByReaction", "NPCs green, yellow or red by reaction")
    w:AddCheckbox(settings, "showDispelType", "Dispel type (Magic, Curse, Poison, Disease, Enrage)")
    w:AddCheckbox(settings, "colorByDispel", "Dispel type in its colour")
    w:AddCheckbox(settings, "showAuraDuration", "Time left")
    w:AddCheckbox(settings, "showAuraStacks", "Stacks")
    w:AddChoice(settings, "mod_auras", "Show these", Data.MODIFIER_CHOICES)
    w:AddNote("In a fight the game hides some of this; what it hides is left out.")
    FitHeight(w)
    return w
end

local function BuildDetailsWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Item Details", 440, 560)
    Heading(w, L["About the item"])
    w:AddCheckbox(settings, "showExpansionName", "Expansion it comes from")
    w:AddCheckbox(settings, "showItemType", "Type (Armor, Plate)")
    w:AddCheckbox(settings, "showEquipSlot", "Slot")
    w:AddCheckbox(settings, "showItemLevel", "Item level", "The game shows it on gear already; this adds it everywhere.")
    w:AddCheckbox(settings, "showStackCount", "Max stack")
    w:AddCheckbox(settings, "showStackPrice", "Vendor price of a full stack, beside it")
    w:AddCheckbox(settings, "showKeystoneDetails", "Keystone dungeon, level and affixes")
    w:AddChoice(settings, "mod_details", "Show details", Data.MODIFIER_CHOICES)
    Heading(w, L["Collected or not"])
    w:AddCheckbox(settings, "showCollection", "Show collection status")
    w:AddCheckbox(settings, "showMountCollected", "Mounts")
    w:AddCheckbox(settings, "showToyCollected", "Toys")
    w:AddCheckbox(settings, "showPetCollected", "Battle pets (how many of 3)")
    w:AddCheckbox(settings, "showTransmogCollected", "Appearances")
    FitHeight(w)
    return w
end

local function BuildInventoryWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Inventory and Alts", 460, 700)
    Heading(w, L["This character"])
    w:AddCheckbox(settings, "trackCurrentBags", "Bags")
    w:AddCheckbox(settings, "trackCurrentEquipped", "Worn")
    w:AddCheckbox(settings, "trackCurrentBank", "Bank", "Read when you open the bank.")
    w:AddCheckbox(settings, "trackCurrentMail", "Mail", "Read when you open the mailbox.")
    Heading(w, L["Account"])
    w:AddCheckbox(settings, "trackWarbandBank", "Warband bank", "Counted live by the game, wherever you are.")
    w:AddCheckbox(settings, "trackGuildBank", "Guild banks", "Read when you open a guild bank, one tab at a time as you view it.")
    w:AddCheckbox(settings, "trackAlts", "Other characters")
    w:AddCheckbox(settings, "colorAltsByClass", "Names in class colour")
    w:AddChoice(settings, "showAltRealm", "Realm", Data.REALM_CHOICES)
    w:AddCheckbox(settings, "showAltFaction", "[A] / [H] for the other faction")
    w:AddCheckbox(settings, "showTotalCount", "Total line")
    w:AddCheckbox(settings, "totalHighlight", "Total in gold")
    Heading(w, L["Which alts"])
    w:AddSlider(settings, "maxAltsToShow", "Up to", 1, 20, 1, "%s %d characters")
    w:AddChoice(settings, "sortAltsBy", "Order", Data.SORT_ALTS_CHOICES)
    w:AddCheckbox(settings, "onlySameRealm", "This realm only")
    w:AddCheckbox(settings, "onlySameFaction", "This faction only")
    w:AddChoice(settings, "mod_inventory", "Show counts", Data.MODIFIER_CHOICES)
    Heading(w, L["Look"])
    w:AddCheckbox(settings, "showRaceIcons", "Race icons")
    w:AddCheckbox(settings, "inventoryIcons", "Icons for bags, bank and mail instead of words")
    w:AddCheckbox(settings, "markCurrent", "Tick beside this character")
    w:AddCheckbox(settings, "currentFirst", "This character first")
    w:AddCheckbox(settings, "blankLineBefore", "A blank line before the counts")
    w:AddCheckbox(settings, "totalFirst", "Total above the characters")
    FitHeight(w)
    return w
end

local function BuildIconWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Icon and Border", 440, 480)
    Heading(w, L["Icon beside the tooltip"])
    w:AddCheckbox(settings, "showIcon", "Show the item's icon")
    w:AddSlider(settings, "iconSize", "Size", 20, 64, 2, "%s: %d px")
    w:AddChoice(settings, "iconAnchor", "Position", Data.ICON_ANCHORS)
    w:AddSlider(settings, "iconOffsetX", "Offset X", -30, 30, 1, "%s: %d px")
    w:AddSlider(settings, "iconOffsetY", "Offset Y", -30, 30, 1, "%s: %d px")
    w:AddCheckbox(settings, "iconQualityBorder", "Icon border in quality colour")
    w:AddCheckbox(settings, "iconStackBadge", "Max stack on the icon")
    Heading(w, L["Tooltip border"])
    w:AddCheckbox(settings, "qualityBorder", "Tooltip border in the item's quality colour")
    FitHeight(w)
    return w
end

local function BuildColoursWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Colours", 440, 340)
    w:AddCheckbox(settings, "customIdColor", "Own colour for labels and IDs")
    w:AddColour(settings, "idColor", "Labels and IDs")
    w:AddCheckbox(settings, "customAltColor", "Own colour for counts")
    w:AddColour(settings, "altColor", "Counts")
    w:AddCheckbox(settings, "customTotalColor", "Own colour for the total")
    w:AddColour(settings, "totalColor", "Total")
    FitHeight(w)
    return w
end

local function BuildDataWindow(API)
    local w = API:CreateOptionsWindow("Item Tooltips: Saved Characters", 440, 300)
    w:AddNote("Each character's bags, gear, bank and mail are saved for the whole account when you play it.")
    local status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)
    local function Refresh()
        local chars = 0
        for _ in pairs(settings.characters) do chars = chars + 1 end
        status:SetText((L["%d characters saved."]):format(chars))
    end
    w:HookScript("OnShow", Refresh)
    w.cursorY = w.cursorY - 30
    local rescan = Button(w, L["Read this character again"], 200, function()
        ScanEquipped()
        MarkAll(PLAYER_BAGS)
        print(PREFIX .. L["bags and gear read again. The bank and mail are read when you open them."])
    end)
    rescan:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    w.cursorY = w.cursorY - 30
    local forget = Button(w, L["Forget this character"], 200, function()
        local key = PlayerKey()
        if key then
            settings.characters[key], settings.inventory[key] = nil, nil
            charKey = nil
        end
        Refresh()
    end)
    forget:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    w.cursorY = w.cursorY - 30
    local forgetAll = Button(w, L["Forget every other character"], 200, function()
        API:Confirm(L["Forget every other character's items? Each is saved again when you log in on it."], function()
            local key = PlayerKey()
            local me, mine = settings.characters[key], settings.inventory[key]
            wipe(settings.characters)
            wipe(settings.inventory)
            wipe(settings.warband)
            wipe(settings.guildBanks)
            if key then settings.characters[key], settings.inventory[key] = me, mine end
            Refresh()
        end)
    end)
    forgetAll:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    w.cursorY = w.cursorY - 34
    FitHeight(w)
    Refresh()
    return w
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Item Tooltips", 460, 560)
        local w = optionsWindow
        Heading(w, L["On every tooltip"])
        w:AddCheckbox(settings, "showIds", "ID numbers", "Item, spell, NPC, quest, currency, achievement, mount, toy, pet and more.")
        w:AddCheckbox(settings, "showAuraInfo", "Buff and debuff details", "Who cast it, dispel type, time left, stacks.")
        w:AddCheckbox(settings, "showItemDetails", "Item details", "Expansion, type, max stack and stack price, keystone affixes.")
        w:AddCheckbox(settings, "showCollection", "Collected or not", "Mounts, toys, battle pets and appearances.")
        w:AddCheckbox(settings, "showInventory", "Counts across your account", "Bags, bank, mail, warband bank and every alt, with a total.")
        w:AddCheckbox(settings, "showIcon", "Icon beside the tooltip")
        w:AddCheckbox(settings, "qualityBorder", "Border in the item's quality colour")
        w:AddCheckbox(settings, "hideInCombat", "Nothing extra in combat")
        Heading(w, L["Settings for each part"])
        ButtonGrid(w, {
            { "ID Numbers", function() ToggleSub("ids", function() return BuildIdsWindow(API) end) end },
            { "Buffs and Debuffs", function() ToggleSub("auras", function() return BuildAurasWindow(API) end) end },
            { "Item Details", function() ToggleSub("details", function() return BuildDetailsWindow(API) end) end },
            { "Inventory and Alts", function() ToggleSub("inventory", function() return BuildInventoryWindow(API) end) end },
            { "Icon and Border", function() ToggleSub("icon", function() return BuildIconWindow(API) end) end },
            { "Colours", function() ToggleSub("colours", function() return BuildColoursWindow(API) end) end },
            { "Saved Characters", function() ToggleSub("data", function() return BuildDataWindow(API) end) end },
        })
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("/itt opens this window. Hold the key you picked for a part to see it.")
        FitHeight(w)
        w:HookScript("OnHide", function()
            for _, sub in pairs(subWindows) do sub:Hide() end
        end)
    end
    optionsWindow:Show()
end

-- ── Settings and registration ───────────────────────────────────────────────

local function EnsureTables(config)
    if type(config.characters) ~= "table" then config.characters = {} end
    if type(config.inventory) ~= "table" then config.inventory = {} end
    if type(config.warband) ~= "table" then config.warband = {} end
    if type(config.guildBanks) ~= "table" then config.guildBanks = {} end
    if type(config.idColor) ~= "table" then config.idColor = { 0.25, 0.75, 1.0 } end
    if type(config.altColor) ~= "table" then config.altColor = { 0.4, 0.9, 0.4 } end
    if type(config.totalColor) ~= "table" then config.totalColor = { 1.0, 0.82, 0.0 } end
    -- The warband bank used to be one flat map; now it is per tab.
    for k, v in pairs(config.warband) do
        if type(v) ~= "table" then wipe(config.warband) break end
    end
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.itemtooltips
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.itemtooltips = config
    end
    for key, value in pairs(Data.DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    EnsureTables(config)
    settings = config
end

SLASH_OXEDHUB_ITEMTOOLTIPS1 = "/itt"
SLASH_OXEDHUB_ITEMTOOLTIPS2 = "/itemtooltips"
SlashCmdList["OXEDHUB_ITEMTOOLTIPS"] = function(msg)
    if not settings then return end
    msg = (msg or ""):lower():gsub("%s+", "")
    if msg == "scan" then
        ScanEquipped()
        MarkAll(PLAYER_BAGS)
        print(PREFIX .. L["bags and gear read again."])
    else
        ShowOptions()
    end
end

-- Its own icon on the minimap, like the other modules with a window: a click
-- opens the options, a right-click the options.
MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "itemtooltips", label = L["Item Tooltips"], icon = "Interface\\Icons\\INV_Misc_Book_09", config = settings,
        hint = L["Click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ShowOptions() end
        end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "itemtooltips",
        name     = "Item Tooltips",
        version  = "1.3.0",
        updated  = 20261030.4,  -- race icons, place icons, tick, layout options
        author   = "Oxed",
        category = "items",
        keywords = { "tooltip", "item", "id", "aura", "spell", "inventory", "count", "alts", "expansion",
                     "caster", "collected", "transmog", "mount", "toy", "pet", "warband" },
        desc     = "Adds ID numbers, aura info, collection status and counts across your alts on hover.",
        icon     = "Interface\\Icons\\INV_Misc_Book_09",

        defaults = Data.DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            EnsureTables(settings)
            Start()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
