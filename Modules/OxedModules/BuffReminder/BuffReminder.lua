-- ============================================================================
-- Buff Reminder (built-in OxedHub module)
-- A row of icons for what is missing right now: the group buff your class
-- gives, your own poisons / shields / weapon imbues / form, your pet, and in
-- instances food, flask, augment rune and weapon oil. Click an icon to cast
-- the spell or use the item.
--
-- How it stays safe on 12.x:
--   * Everything is decided OUT OF COMBAT. The bar hides itself the moment
--     combat starts (a secure state driver, so it works while protected) and
--     is rebuilt when combat ends. Auras read in combat can be secret or
--     empty; this module never has to trust one.
--   * Even out of combat some content (keys, encounters) keeps auras secret.
--     C_Secrets.ShouldAurasBeSecret() is asked first; while it says yes the
--     last known bar is kept rather than guessing from empty reads.
--   * Aura lookups go by spell ID (GetUnitAuraBySpellID) inside pcall, and a
--     secret field is treated as "unknown", never as "missing".
--   * Click attributes on the secure buttons change only out of combat.
--
-- Smarter than a plain list:
--   * Group buffs show how many nearby members lack them, with names in the
--     tooltip; dead, offline and far away players are not counted.
--   * A buff running out within five minutes shows too, with its time left.
--   * A missing food, flask, rune or weapon oil shows every matching item in
--     your bags as its own icon, with its count and stat, ready to click;
--     oil is offered per hand and applied to that hand.
--   * A missing pet shows each pet you can call (hunter stable, warlock
--     demons) plus Revive Pet; healthstones, low durability and, on a ready
--     check, Soulwell and Refreshment Table are covered too.
--   * A ready check shows the full bar for 30 seconds, wherever you are.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on (see ModuleAPI:Register)
    showRaid      = true,   -- the group buff your class gives
    showSelf      = true,   -- poisons, shields, imbues, forms
    showPets      = true,
    showConsumables = true, -- food, flask, rune, oil (instances only)
    expiring      = true,   -- also show buffs with under five minutes left
    onlyInstances = false,  -- group and self buffs only inside instances too
    hideResting   = false,  -- nothing in cities and inns
    hideMounted   = true,   -- nothing while mounted or in a vehicle
    readyCheck    = true,   -- a ready check shows everything for 30 seconds
    clickCast     = true,   -- clicking an icon casts / uses
    largeIcons    = false,  -- older setting; iconSize replaces it once moved
    iconSize      = 0,      -- 0: not chosen yet (34, or 44 for largeIcons)
    showNames     = false,  -- a short name under each icon
    locked        = true,   -- unlocked: drag the bar, a sample icon marks it
    shiftDrag     = true,   -- Shift+drag moves the bar even while it is locked
    point = "CENTER", x = 0, y = 180,

    showTargeted  = true,   -- buffs you put on somebody else (beacons, Earth Shield...)
    expiringMinutes = 5,    -- "running out" means under this many minutes
    growDirection = "RIGHT",-- RIGHT, LEFT, CENTER, DOWN, UP
    spacing       = 6,      -- pixels between icons
    perRow        = 10,     -- icons before a new row (or column)
    glowMissing   = false,  -- a glow around icons for what is missing
    glowExpiring  = true,   -- a glow around icons for what is running out
    rightSnooze   = true,   -- right-click an icon to hide it for a while
    snoozeMinutes = 10,
    sound         = "",     -- played when something new goes missing ("" = none)
    onlyInGroup   = false,
    hideLeveling  = false,  -- nothing below the maximum level
    -- Where the bar shows at all (a ready check shows it anywhere).
    where_openWorld = true, where_dungeon = true, where_raid = true,
    where_delve = true, where_scenario = true, where_pvp = false,
    -- Class choices
    prefLethal    = 0,      -- 0 = the best one you know
    prefNonLethal = 0,
    rune_250 = 0, rune_251 = 0, rune_252 = 0,   -- death knight rune per spec, 0 = any
    ignoreTravelForm = true, -- no wrong-form reminder while travelling or mounted
    -- Warlock: the demon whose icon comes first when the pet is missing.
    demon_openWorld = 691, demon_dungeon = 691, demon_raid = 691, demon_pvp = 691,

    benefitOnly   = true,   -- group buffs count only players they do something for
    askBuffs      = true,   -- a group buff you lack from a class in the group: click asks for it
    showLoadout   = true,   -- talents / gear set chosen for this content are not the ones in use
    consumableMemory = true,-- the food / flask / oil you used last (per spec) comes first
    oneConsumable = false,  -- only that first one, not every item you carry
    lowStock      = 2,      -- an item count this low shows in red (0 = never)
    -- Look
    iconAlpha     = 100,    -- percent
    iconZoom      = 8,      -- percent cut from each edge of the icon art
    borderSize    = 1,      -- pixels of black border (0 = none)
    textScale     = 100,    -- percent, for every text on the icons
    missingCountOnly = true,-- group buffs: "3" missing, or "2/5" who have it
    previewCount  = 12,     -- sample icons while previewing
    -- Behaviour
    repairBelow   = 25,     -- durability percent that asks for a repair
    withoutItems  = true,   -- food / flask / oil show even when you carry none
    askMessage    = "",     -- own wording for a request; {buff} is the buff ("" = the default)
    askCooldown   = true,   -- the same request at most once every 30 seconds
    raidSelfOnly  = false,  -- group buffs: only whether you have it, not the group
    readyCheckOnly = false, -- the bar shows only during a ready check
    preKeyMinutes = 15,     -- Mythic dungeon before a key starts: "running out" reaches this far (0 = off)
    healthstoneLow = 0,     -- healthstone reminder at or below this many charges
    hideLegacyItems = false,-- no icons for food, flasks or oil from older expansions
    delveFoodOnly = true,   -- in a delve, delve food instead of the usual food
    delveFoodTimer = true,  -- the delve food reminder gives up after 30 seconds
    withoutItemsReadyCheck = false, -- items you do not carry are shown only on a ready check
    felDomination = false,  -- warlock: a demon click casts Fel Domination first
    soulstoneTarget = "",   -- warlock: Soulstone always goes on this player ("" = whoever had it)
    minimapButton = true,   -- its own icon on the minimap while switched on
    -- Lists (customBuffs, lastTargets, lastUsed, loadouts, gearSets, demons_*)
    -- are made in BindSettings, never here.
}

local READY_CHECK_SECONDS = 30
local REFRESH_DELAY = 0.3     -- events arrive in bursts; one rebuild per burst
local TICK = 10               -- range and time-left change without events
local MAX_BUTTONS = 30

local Data = OxedHub.BuffReminderData
local settings
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local optionsWindow

-- A Mythic dungeon before its key starts: the last chance to refresh
-- anything without the timer running, so "running out" reaches further.
local function BeforeKey()
    if (tonumber(settings and settings.preKeyMinutes) or 0) <= 0 then return false end
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "party" or difficultyID ~= 23 then return false end
    local active = C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    return not active
end

-- Below `local settings`: above it, `settings` would be a global and the
-- "running out" slider would never be read.
local function ExpiringSeconds()
    local minutes = tonumber(settings and settings.expiringMinutes) or 5
    if BeforeKey() then minutes = math.max(minutes, tonumber(settings.preKeyMinutes) or 0) end
    return minutes * 60
end
local watcher = CreateFrame("Frame")

local bar, buttons = nil, {}
local pending, ticker = false, nil
local readyCheckUntil = 0
local delveFoodSince         -- GetTime() the delve food reminder first showed in this delve
local snoozed = {}            -- entry key -> GetTime() until which it stays hidden
local askedAt = {}            -- entry key -> GetTime() of the last request sent in chat
local petPauseUntil = 0       -- pet reminders wait until then after a dismount
local MarkDirty               -- defined with Refresh, used by the click handlers

-- ── Small safe readers ──────────────────────────────────────────────────────

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function AurasSecretNow()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok and secret == true then return true end
    end
    return false
end

local function Known(spellID)
    return spellID and IsPlayerSpell and IsPlayerSpell(spellID) or false
end

local function SpellTexture(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spellID) end
    return GetSpellTexture and GetSpellTexture(spellID)
end

local function CurrentSpecID()
    if not GetSpecialization then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    return (GetSpecializationInfo(index))
end

local function InDelve()
    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == 208
end

-- Where the player is, in the words of the "Where it shows" options.
local function ContentType()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then return "openWorld" end
    if instanceType == "party" then return "dungeon" end
    if instanceType == "raid" then return "raid" end
    if instanceType == "pvp" or instanceType == "arena" then return "pvp" end
    if instanceType == "scenario" then return InDelve() and "delve" or "scenario" end
    return "openWorld"
end

-- Per-spec choices are kept under the spec ID as a string ("0" before one is known).
local function SpecKey(specID)
    return tostring(specID or 0)
end

-- Looks for any of `ids` on `unit`.
-- Returns found (true/false/nil for "cannot tell") and seconds left (or nil).
local function FindAura(unit, ids)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return nil end
    local unknown = false
    for _, id in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
        if not ok or IsSecret(aura) then
            unknown = true
        elseif aura then
            local expires = aura.expirationTime
            if IsSecret(expires) or not expires or expires == 0 then
                return true, nil
            end
            return true, expires - GetTime()
        end
    end
    if unknown then return nil end
    return false
end

-- ── Remembered answers ──────────────────────────────────────────────────────
-- /oxprofile showed a refresh costing 1.1 ms and 33 KB of garbage: every
-- refresh asked the game again for every raid buff on every group member, and
-- each answer that finds an aura is a new table. The answer only changes when
-- that unit's auras change, so it is kept per unit, per entry, until UNIT_AURA
-- for that unit says otherwise. The time left is kept as the moment it runs
-- out, so a remembered answer still counts down.
--
-- ⚠ "cannot tell" (a secret, in combat) is never remembered: the next refresh
-- must ask again rather than keep a guess.

local auraCache = {}       -- unit -> { [ids] = expiresAt, or 0 for none, or -1 for no end }

local function ForgetUnit(unit)
    local cache = auraCache[unit]
    if cache then wipe(cache) end
end

local function ForgetAllUnits()
    for _, cache in pairs(auraCache) do wipe(cache) end
end

local function FindAuraCached(unit, ids)
    local cache = auraCache[unit]
    if not cache then
        cache = {}
        auraCache[unit] = cache
    end
    local known = cache[ids]
    if known ~= nil then
        if known == 0 then return false end
        if known == -1 then return true, nil end
        return true, known - GetTime()
    end
    local found, left = FindAura(unit, ids)
    if found == false then
        cache[ids] = 0
    elseif found then
        cache[ids] = left and (GetTime() + left) or -1
    end
    return found, left
end

-- Food buffs share no spell ID, and in Midnight not always the old food icon
-- either (a delve showed "needs food" with Well Fed up). What they do share is
-- the name -- "Well Fed", "Hearty Well Fed" -- in the client's own language,
-- read from an old Well Fed spell so it works in every locale.
local FOOD_ICON = 136000
local WELL_FED_SPELL = 19705
local wellFedName

local function WellFedName()
    if not wellFedName then
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(WELL_FED_SPELL)
        wellFedName = (type(name) == "string" and name ~= "") and name or "Well Fed"
    end
    return wellFedName
end

local function IsFoodAura(aura)
    local icon, name = aura.icon, aura.name
    if not IsSecret(icon) and icon == FOOD_ICON then return true end
    if not IsSecret(name) and type(name) == "string" then
        if name:find(WellFedName(), 1, true) or name:find("Well Fed", 1, true) then return true end
    end
    return false
end
local function FoodResult(aura)
    local expires = aura.expirationTime
    if IsSecret(expires) or not expires or expires == 0 then return true, nil end
    return true, expires - GetTime()
end

local FOOD_CACHE_KEY = "_food"

local function FindFoodUncached()
    -- Check Core's auraCache first if primed: avoids allocating up to 40 aura tables.
    local Core = OxedHub.Core
    if Core and Core.auraScanPrimed and Core.auraCache then
        local now = GetTime()
        for _, r in pairs(Core.auraCache) do
            if r.food then
                local expires = r.expirationTime
                if IsSecret(expires) or not expires or expires == 0 then return true, nil end
                return true, expires - now
            end
        end
        if not InCombatLockdown() then
            return false
        end
    end
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    -- By name first: one aura read instead of up to forty. Walking every buff
    -- made a fresh table for each one, on every refresh, and that was most of
    -- the garbage this module made. The walk below stays for food buffs
    -- named otherwise ("Hearty Well Fed").
    if C_UnitAuras.GetAuraDataBySpellName then
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", WellFedName(), "HELPFUL")
        if ok and aura and not IsSecret(aura) then return FoodResult(aura) end
    end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or IsSecret(aura) then return nil end
        if not aura then break end
        if IsFoodAura(aura) then
            local expires = aura.expirationTime
            if IsSecret(expires) or not expires or expires == 0 then return true, nil end
            return true, expires - GetTime()
        end
    end
    return false
end

local function FindFood()
    local cache = auraCache["player"]
    if not cache then
        cache = {}
        auraCache["player"] = cache
    end
    local known = cache[FOOD_CACHE_KEY]
    if known ~= nil then
        if known == 0 then return false end
        if known == -1 then return true, nil end
        return true, known - GetTime()
    end
    local found, left = FindFoodUncached()
    if found == false then
        cache[FOOD_CACHE_KEY] = 0
    elseif found then
        cache[FOOD_CACHE_KEY] = left and (GetTime() + left) or -1
    end
    return found, left
end

-- True when either weapon carries one of the enchant IDs; plus whether a
-- temporary enchant exists at all (for the oil reminder).
local function WeaponEnchants(ids)
    if not GetWeaponEnchantInfo then return nil end
    local hasMain, mainLeft, _, mainID, hasOff, offLeft, _, offID = GetWeaponEnchantInfo()
    if ids then
        for _, id in ipairs(ids) do
            if hasMain and mainID == id then return true, mainLeft and mainLeft / 1000 end
            if hasOff and offID == id then return true, offLeft and offLeft / 1000 end
        end
        return false
    end
    if hasMain then return true, mainLeft and mainLeft / 1000 end
    return false
end

-- Permanent enchants (runeforges) sit in the item link: item:ID:enchantID:...
-- The tooltip fallback below builds the whole tooltip as tables, so the answer
-- is kept until either weapon's link changes.
local enchantLinks, enchantAnswer = {}, nil
local PermanentEnchantNow

local function PermanentEnchant(ids)
    local main, off = GetInventoryItemLink("player", 16), GetInventoryItemLink("player", 17)
    if enchantAnswer ~= nil and enchantLinks[1] == main and enchantLinks[2] == off then
        return enchantAnswer
    end
    enchantLinks[1], enchantLinks[2] = main, off
    enchantAnswer = PermanentEnchantNow(ids)
    return enchantAnswer
end

PermanentEnchantNow = function(ids)
    for _, slot in ipairs({ 16, 17 }) do
        local link = GetInventoryItemLink("player", slot)
        local enchant = link and tonumber(link:match("item:%d+:(%d*)"))
        -- Rune IDs are not a fixed list across patches, and a death knight
        -- weapon has no other permanent enchant worth nagging about: any
        -- enchant counts.
        if enchant and enchant > 0 then return true end
        -- Fallback: the tooltip's "Enchanted:" line, for links without the ID.
        if C_TooltipInfo and C_TooltipInfo.GetInventoryItem and ENCHANTED_TOOLTIP_LINE then
            local prefix = ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s")
            local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
            if prefix and prefix ~= "" and ok and data and data.lines then
                for _, line in ipairs(data.lines) do
                    -- Locale-free: the line type says "permanent enchant".
                    if Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
                        and line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent then
                        return true
                    end
                    local text = line.leftText
                    if type(text) == "string" and not IsSecret(text) and text:find(prefix, 1, true) == 1 then
                        return true
                    end
                end
            end
        end
    end
    return false
end


-- ── Who is in the group, and in reach ──────────────────────────────────────

local RAID_UNITS, PARTY_UNITS = {}, { "player" }
for i = 1, 40 do RAID_UNITS[i] = "raid" .. i end
for i = 1, 4 do PARTY_UNITS[i + 1] = "party" .. i end

-- The unit list and how many of it are in use; made once, never per refresh.
local function GroupUnits()
    if IsInRaid() then return RAID_UNITS, math.min(40, GetNumGroupMembers()) end
    return PARTY_UNITS, 1 + math.min(4, GetNumSubgroupMembers())
end

local function Countable(unit)
    if not UnitExists(unit) or not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost(unit) then return false end
    if unit ~= "player" and not UnitIsVisible(unit) then return false end
    return true
end

-- A member's spec, when the game knows it (it does for anybody inspected,
-- which most group frames do); nil otherwise.
local function UnitSpecID(unit)
    if unit == "player" then return CurrentSpecID() end
    if not GetInspectSpecialization then return nil end
    local ok, id = pcall(GetInspectSpecialization, unit)
    if ok and not IsSecret(id) and type(id) == "number" and id > 0 then return id end
    return nil
end

-- Does `entry` (a group buff) do anything for `unit`? The spec decides when
-- known, else the class; unknown counts as yes, so nobody is left out.
local function Benefits(entry, unit)
    if not settings.benefitOnly then return true end
    local specs = Data.BENEFIT_SPECS[entry.key]
    if not specs then return true end
    local spec = UnitSpecID(unit)
    if spec then return specs[spec] == true end
    local ok, _, class = pcall(UnitClass, unit)
    if not ok or IsSecret(class) or type(class) ~= "string" then return true end
    return Data.BENEFIT_CLASSES[entry.key][class] == true
end

-- ── Items in the bags ───────────────────────────────────────────────────────

local function ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
    return GetItemCount and GetItemCount(itemID) or 0
end

local function ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

-- Charges, not stacks: a healthstone is one item with several uses.
local function ItemCharges(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID, false, true) or 0 end
    return ItemCount(itemID)
end

-- An item from an older expansion, when the player asked not to be offered
-- those. An item the game has not loaded yet counts as current.
local currentExpansion
local function IsLegacyItem(itemID)
    if not settings.hideLegacyItems or not (C_Item and C_Item.GetItemInfo) then return false end
    currentExpansion = currentExpansion
        or (GetServerExpansionLevel and GetServerExpansionLevel())
        or (GetExpansionLevel and GetExpansionLevel())
    local expansion = select(15, C_Item.GetItemInfo(itemID))
    return type(currentExpansion) == "number" and type(expansion) == "number" and expansion < currentExpansion
end

-- Whether a consumable you carry none of still gets an icon.
local function ShowWithoutItems()
    if not settings.withoutItems then return false end
    return not settings.withoutItemsReadyCheck or GetTime() < readyCheckUntil
end

-- One record per item of this kind in the bags, best first, at most
-- ITEMS_PER_KIND of them.
-- The item of this kind you used last on this spec (see RememberItem).
local function PreferredItem(kind)
    if not settings.consumableMemory or type(settings.lastUsed) ~= "table" then return nil end
    local mine = settings.lastUsed[SpecKey(CurrentSpecID())]
    return type(mine) == "table" and mine[kind] or nil
end

-- One record per item of this kind in the bags, best first, at most
-- ITEMS_PER_KIND of them. The one you used last on this spec comes first;
-- with "only one" chosen it is the only one.
local function CarriedItems(kind)
    local found = {}
    local preferred = PreferredItem(kind)
    local function Take(info, count)
        found[#found + 1] = {
            item = info.id, stack = count, label = info.label, badge = info.badge,
            texture = ItemIcon(info.id), kind = kind,
        }
    end
    if preferred and not IsLegacyItem(preferred) then
        for _, info in ipairs(Data.ITEMS[kind] or {}) do
            if info.id == preferred then
                local count = ItemCount(info.id)
                if count > 0 then Take(info, count) end
                break
            end
        end
    end
    local preferredTaken = #found > 0
    local limit = settings.oneConsumable and 1 or Data.ITEMS_PER_KIND
    for _, info in ipairs(Data.ITEMS[kind] or {}) do
        if #found >= limit then break end
        if not (preferredTaken and info.id == preferred) and not IsLegacyItem(info.id) then
            local count = ItemCount(info.id)
            if count > 0 then Take(info, count) end
        end
    end
    return found
end

-- Remembers a clicked food / flask / rune / oil for this spec. Fleeting
-- flasks are not remembered: they would push the regular choice aside.
local function RememberItem(record)
    if not settings.consumableMemory or not record.item or not record.kind then return end
    if record.badge == "F" then return end
    local key = SpecKey(CurrentSpecID())
    settings.lastUsed[key] = settings.lastUsed[key] or {}
    settings.lastUsed[key][record.kind] = record.item
end

local function IsWeapon(slot)
    local id = GetInventoryItemID("player", slot)
    if not id or not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(id)
    return classID == 2   -- Enum.ItemClass.Weapon; off-hand shields and books are not
end

local function GroupHasClass(wanted)
    local units, count = GroupUnits()
    for i = 1, count do
        local unit = units[i]
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class == wanted then return true end
        end
    end
    return false
end

-- ── Asking the group ────────────────────────────────────────────────────────
-- A click on an "ask" icon runs a one-line macro that says the request in
-- group chat. Only ever on the player's own click, and once per ASK_COOLDOWN.

local function ChatPrefix()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "/i " end
    if IsInRaid() then return "/raid " end
    return "/p "
end

local function AskMacro(text)
    return ChatPrefix() .. (text:gsub("[\r\n]", " "))
end

-- The request, in the player's own words when they wrote some. {buff} is
-- replaced as plain text, so a "%" typed in the message cannot break it.
local function AskText(buffName)
    local text = settings.askMessage
    if type(text) ~= "string" or strtrim(text) == "" then text = Data.ASK_MESSAGE end
    if not text:find("{buff}", 1, true) then text = text .. " ({buff})" end
    return (text:gsub("{buff}", function() return buffName end))
end

local function AskedRecently(key)
    if not settings.askCooldown then return false end
    local at = askedAt[key]
    return at ~= nil and GetTime() - at < Data.ASK_COOLDOWN
end

-- ── Deciding what to show ───────────────────────────────────────────────────

local function Applies(entry, class, specID)
    if entry.class and entry.class ~= class then return false end
    if entry.specs and not (specID and entry.specs[specID]) then return false end
    if entry.notSpecs and specID and entry.notSpecs[specID] then return false end
    if entry.level and UnitLevel("player") < entry.level then return false end
    if entry.notKnown and Known(entry.notKnown) then return false end
    if entry.known then
        if not Known(entry.known) then return false end
    elseif entry.castList then
        local any = false
        for _, id in ipairs(entry.castList) do
            if Known(id) then any = true break end
        end
        if not any then return false end
    end
    if entry.notAura then
        -- The one-id list is made once per entry, not on every check.
        entry._notAuraList = entry._notAuraList or { entry.notAura }
        if FindAuraCached("player", entry._notAuraList) then return false end
    end
    return true
end

local function CastSpellFor(entry)
    if entry.castList then
        for _, id in ipairs(entry.castList) do
            if Known(id) then return id end
        end
    end
    return entry.cast or entry.known
end

-- A record is one icon. Fields:
--   entry            the data entry it belongs to (tooltip title, hide option)
--   texture          icon
--   count            group members missing it (raid buffs)
--   stack            how many of the item you carry
--   label, badge     short text on top of the icon (stat, hand, H / F)
--   name             text under the icon (pet name)
--   timeLeft         seconds left on a buff that is running out
--   spell/item/macro what a click does
local function Add(out, entry, record)
    record.entry = entry
    out[#out + 1] = record
end

local function Needed(found, left)
    if found == false then return true end
    return found and settings.expiring and left and left < ExpiringSeconds() or false
end

local SELF_ONLY = { "player" }

local function EvaluateRaid(entry, out)
    local missing, total, names, soonest = 0, 0, nil, nil
    local units, count = GroupUnits()
    if settings.raidSelfOnly then units, count = SELF_ONLY, 1 end
    for i = 1, count do
        local unit = units[i]
        if Countable(unit) and Benefits(entry, unit) then
            total = total + 1
            local has, remaining = FindAuraCached(unit, entry.auras)
            if has == false then
                missing = missing + 1
                names = names or {}
                names[#names + 1] = UnitName(unit)
            elseif has and remaining and (not soonest or remaining < soonest) then
                soonest = remaining
            end
        end
    end
    local spell = CastSpellFor(entry)
    if missing > 0 then
        Add(out, entry, { texture = SpellTexture(spell), count = missing, total = total, names = names, spell = spell })
    elseif settings.expiring and soonest and soonest < ExpiringSeconds() then
        Add(out, entry, { texture = SpellTexture(spell), timeLeft = soonest, spell = spell })
    end
end

local function SpellRecord(spellID, name)
    return { texture = SpellTexture(spellID), spell = spellID, name = name }
end

-- ── Warlock demons ──────────────────────────────────────────────────────────

-- The demon choices are kept per content row; dungeons stand for scenarios.
local function DemonRow()
    local content = ContentType()
    if content == "dungeon" or content == "scenario" then return "dungeon" end
    if content == "raid" or content == "pvp" then return content end
    return "openWorld"
end

-- The demons wanted here, as a set of summon spells; nil when none is chosen.
-- Demonology always wants its Felguard.
local FELGUARD_ONLY = { [30146] = true }
local function AllowedDemons(specID)
    if specID == 266 then return FELGUARD_ONLY end
    local set = settings["demons_" .. DemonRow()]
    if type(set) ~= "table" or next(set) == nil then return nil end
    return set
end

-- The summon spell of the demon out now, from the creature ID in its GUID.
-- nil when there is no demon, the GUID is hidden, or the creature is unknown.
local function PetSummonSpell()
    local ok, guid = pcall(UnitGUID, "pet")
    if not ok or IsSecret(guid) or type(guid) ~= "string" then return nil end
    local npc = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
    return npc and Data.DEMON_NPC[npc] or nil
end

-- One summon icon. With Fel Domination asked for and known, the click casts
-- it first so the demon arrives at once.
local function DemonRecord(spellID)
    local record = SpellRecord(spellID, Data.DEMON_NAMES[spellID])
    if settings.felDomination and Known(Data.FEL_DOMINATION) and C_Spell and C_Spell.GetSpellName then
        local fel, summon = C_Spell.GetSpellName(Data.FEL_DOMINATION), C_Spell.GetSpellName(spellID)
        if type(fel) == "string" and type(summon) == "string" then
            record.macro = ("/cast %s\n/cast %s"):format(fel, summon)
        end
    end
    return record
end

-- A demon is out, but not one of those chosen for this content: an icon for
-- each wanted demon you know.
local function EvaluateDemonChoice(entry, specID, out)
    if not UnitExists("pet") or UnitIsDead("pet") then return end
    local allowed = AllowedDemons(specID)
    if not allowed then return end
    local current = PetSummonSpell()
    if not current or allowed[current] then return end
    local wanted = {}
    for _, id in ipairs(Data.DEMON_CHOICES) do
        if allowed[id] then wanted[#wanted + 1] = Data.DEMON_NAMES[id] end
    end
    for _, id in ipairs(Data.DEMON_CHOICES) do
        if allowed[id] and Known(id) then
            local record = DemonRecord(id)
            record.wrong = table.concat(wanted, ", ")
            Add(out, entry, record)
        end
    end
end

-- Missing pet: one icon per pet you can call, so the right one is one click.
local function EvaluatePet(entry, specID, out)
    if UnitExists("pet") and not UnitIsDead("pet") then return end
    -- The pet comes back on its own a moment after a dismount.
    if GetTime() < petPauseUntil then return end
    local _, class = UnitClass("player")

    if class == "HUNTER" then
        if specID == 254 and not Known(Data.MM_PET_TALENT) then return end
        local exotic = Known(Data.EXOTIC_BEASTS)
        local before = #out
        if C_StableInfo and C_StableInfo.GetStablePetInfo then
            for slot, spellID in ipairs(Data.CALL_PET) do
                if Known(spellID) then
                    local ok, info = pcall(C_StableInfo.GetStablePetInfo, slot)
                    if ok and info and info.name and (not info.isExotic or exotic) then
                        Add(out, entry, {
                            texture = info.icon or SpellTexture(spellID), spell = spellID,
                            name = info.name, label = info.specialization and info.specialization:sub(1, 4),
                        })
                    end
                end
            end
        end
        if #out == before then Add(out, entry, SpellRecord(Data.CALL_PET[1])) end
        if Known(Data.REVIVE_PET) then Add(out, entry, SpellRecord(Data.REVIVE_PET, "Revive")) end
        return
    end

    if class == "WARLOCK" and GetFlyoutInfo then
        local ok, _, _, slots, known = pcall(GetFlyoutInfo, Data.DEMON_FLYOUT)
        if ok and known and slots then
            local before = #out
            for i = 1, slots do
                local okSlot, spellID, _, slotKnown = pcall(GetFlyoutSlotInfo, Data.DEMON_FLYOUT, i)
                if okSlot and spellID and slotKnown then
                    Add(out, entry, DemonRecord(spellID))
                end
            end
            if #out > before then
                -- The demons chosen for this content come first, in the order
                -- they were offered; Demonology's Felguard before anything.
                local allowed = AllowedDemons(specID)
                if allowed then
                    local first, rest = {}, {}
                    for i = before + 1, #out do
                        local record = out[i]
                        if allowed[record.spell] then first[#first + 1] = record else rest[#rest + 1] = record end
                    end
                    local i = before
                    for _, record in ipairs(first) do i = i + 1 out[i] = record end
                    for _, record in ipairs(rest) do i = i + 1 out[i] = record end
                end
                return
            end
        end
    end

    local spell = CastSpellFor(entry)
    Add(out, entry, SpellRecord(spell))
end

-- Food, flask, rune: the aura is checked, and when it is missing every
-- matching item carried gets its own icon.
local function EvaluateBuffItem(entry, out)
    -- A delve has its own food; the usual Well Fed is not what it asks for.
    if entry.check == "food" and settings.delveFoodOnly and InDelve() then return end
    local found, left
    if entry.check == "food" then
        found, left = FindFood()
    else
        found, left = FindAuraCached("player", entry.auras)
    end
    if not Needed(found, left) then return end
    local timeLeft = found and left or nil

    local items = CarriedItems(entry.check)
    if #items == 0 then
        -- A rune you do not carry is not worth a reminder.
        if entry.check == "rune" or not ShowWithoutItems() then return end
        local texture = entry.icon or SpellTexture(entry.auras and entry.auras[#entry.auras])
        Add(out, entry, { texture = texture, timeLeft = timeLeft })
        return
    end
    for _, record in ipairs(items) do
        record.timeLeft = timeLeft
        Add(out, entry, record)
    end
end

-- Weapon oil: checked per hand; each carried oil is offered for each hand
-- that needs one, and a click applies it to that hand.
local function EvaluateOil(entry, out)
    local _, class = UnitClass("player")
    if Data.NO_OIL_CLASS[class] or not GetWeaponEnchantInfo then return end
    local hasMain, mainLeft, _, _, hasOff, offLeft = GetWeaponEnchantInfo()
    local hands = {
        { slot = 16, tag = "MH", has = hasMain, left = mainLeft },
        { slot = 17, tag = "OH", has = hasOff,  left = offLeft },
    }
    local items
    for _, hand in ipairs(hands) do
        local left = hand.left and hand.left / 1000
        if IsWeapon(hand.slot) and Needed(hand.has and true or false, left) then
            local timeLeft = hand.has and left or nil
            items = items or CarriedItems("weaponOil")
            if #items == 0 then
                if ShowWithoutItems() then Add(out, entry, { texture = GetInventoryItemTexture("player", hand.slot), label = hand.tag, timeLeft = timeLeft }) end
            else
                for _, info in ipairs(items) do
                    Add(out, entry, {
                        texture = info.texture, item = info.item, stack = info.stack, label = hand.tag,
                        timeLeft = timeLeft, slot = hand.slot, kind = "weaponOil",
                        macro = ("/use item:%d\n/use %d"):format(info.item, hand.slot),
                    })
                end
            end
        end
    end
end

local function EvaluateHealthstone(out, entry)
    local _, class = UnitClass("player")
    if class ~= "WARLOCK" and not GroupHasClass("WARLOCK") then return end
    local total = 0
    for _, id in ipairs(Data.HEALTHSTONES) do total = total + ItemCharges(id) end
    if total > (tonumber(settings.healthstoneLow) or 0) then return end
    local record = { texture = ItemIcon(Data.HEALTHSTONES[1]), stack = total }
    if class == "WARLOCK" then
        if IsInGroup() and Known(Data.CREATE_SOULWELL) then
            record.spell = Data.CREATE_SOULWELL
        elseif Known(Data.CREATE_HEALTHSTONE) then
            record.spell = Data.CREATE_HEALTHSTONE
        end
    elseif settings.askBuffs and IsInGroup() and not AskedRecently(entry.key) then
        record.macro = AskMacro(Data.ASK_HEALTHSTONE)
        record.ask = true
    end
    Add(out, entry, record)
end

local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"

-- What a click on the repair icon uses: a mount you own whose vendor repairs,
-- else an item that repairs on the spot. nil when you have neither.
local function RepairSource()
    if C_MountJournal and C_MountJournal.GetMountFromSpell and C_MountJournal.GetMountInfoByID then
        for _, spellID in ipairs(Data.REPAIR_MOUNTS) do
            local mountID = C_MountJournal.GetMountFromSpell(spellID)
            if mountID then
                local _, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if isCollected and isUsable then return { spell = spellID } end
            end
        end
    end
    for _, itemID in ipairs(Data.REPAIR_ITEMS) do
        if ItemCount(itemID) > 0 then return { item = itemID } end
    end
    return nil
end

local function EvaluateRepair(out, entry)
    if not GetInventoryItemDurability then return end
    local worst
    for slot = 1, 18 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local percent = current / maximum * 100
            if not worst or percent < worst then worst = percent end
        end
    end
    if worst and worst < (tonumber(settings.repairBelow) or Data.REPAIR_BELOW) then
        local record = { texture = REPAIR_ICON, label = ("%d%%"):format(worst) }
        local how = RepairSource()
        if how then record.spell, record.item = how.spell, how.item end
        Add(out, entry, record)
    end
end

-- ── Buffs you put on others ─────────────────────────────────────────────────

local function SpellName(spellID)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    return type(name) == "string" and name or nil
end

-- Is one of `ids` on `unit`, cast by you? Answers like FindAura.
local function FindMine(unit, ids)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return nil end
    local unknown = false
    for _, id in ipairs(ids) do
        local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
        if not ok or IsSecret(aura) then
            unknown = true
        elseif aura then
            local source = aura.sourceUnit
            if IsSecret(source) then
                unknown = true
            elseif source == "player" or (source and UnitIsUnit(source, "player")) then
                local expires = aura.expirationTime
                if IsSecret(expires) or not expires or expires == 0 then return true, nil end
                return true, expires - GetTime()
            end
        end
    end
    if unknown then return nil end
    return false
end

-- Kept beside the other answers for the unit, under the entry itself (the
-- ids table already holds the "anybody's" answer).
local function FindMineCached(unit, entry)
    local cache = auraCache[unit]
    if not cache then
        cache = {}
        auraCache[unit] = cache
    end
    local known = cache[entry]
    if known ~= nil then
        if known == 0 then return false end
        if known == -1 then return true, nil end
        return true, known - GetTime()
    end
    local found, left = FindMine(unit, entry.auras)
    if found == false then
        cache[entry] = 0
    elseif found then
        cache[entry] = left and (GetTime() + left) or -1
    end
    return found, left
end

local function RoleOf(unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if IsSecret(role) then return nil end
    return role
end

-- "/cast" on the player it was on last, else one with the wanted role, else
-- mouseover or target, else the plain cast. Names are cleaned so a strange
-- one cannot break out of the [@...] condition.
local function TargetMacro(entry, spellID)
    local name = SpellName(spellID)
    if not name then return nil end
    local target = settings.lastTargets and settings.lastTargets[entry.key]
    -- A Soulstone the player has given a home to always goes there first.
    if entry.key == "soulstone" and type(settings.soulstoneTarget) == "string" and settings.soulstoneTarget ~= "" then
        target = settings.soulstoneTarget
    end
    if not target and entry.role then
        local units, count = GroupUnits()
        for i = 1, count do
            local unit = units[i]
            if unit ~= "player" and UnitExists(unit) and RoleOf(unit) == entry.role then
                target = GetUnitName(unit, true)
                break
            end
        end
    end
    local first = ""
    if type(target) == "string" and target ~= "" then
        first = ("[@%s,help,nodead]"):format((target:gsub("[%[%];,\r\n]", "")))
    end
    return ("/cast %s[@mouseover,help,nodead][@target,help,nodead][] %s"):format(first, name)
end

local function EvaluateTargeted(entry, out)
    if not IsInGroup() then return end
    if entry.readyCheckOnly then
        if GetTime() >= readyCheckUntil then return end
        local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(entry.known)
        if cd and not IsSecret(cd.duration) and (cd.duration or 0) > 2 then return end
    end
    local spell = entry.cast or entry.known
    local record = { texture = SpellTexture(spell), spell = spell }

    if entry.selfAura then
        entry._selfList = entry._selfList or { entry.selfAura }
        local found, left = FindAuraCached("player", entry._selfList)
        if not Needed(found, left) then return end
        record.timeLeft = found and left or nil
        record.macro = TargetMacro(entry, spell)
        Add(out, entry, record)
        return
    end

    local units, count = GroupUnits()
    local anyFound, soonest = false, nil
    for i = 1, count do
        local unit = units[i]
        if unit ~= "player" and Countable(unit) then
            local found, left = FindMineCached(unit, entry)
            if found == nil then return end         -- cannot tell: show nothing
            if found then
                anyFound = true
                settings.lastTargets[entry.key] = GetUnitName(unit, true)
                if left and (not soonest or left < soonest) then soonest = left end
            end
        end
    end
    if anyFound then
        if not (settings.expiring and soonest and soonest < ExpiringSeconds()) then return end
        record.timeLeft = soonest
    end
    record.macro = TargetMacro(entry, spell)
    Add(out, entry, record)
end

-- ── Class specials ──────────────────────────────────────────────────────────

-- Rogue poisons of one kind: how many are on, against how many you may have.
local function EvaluatePoison(entry, out)
    local list = entry.castList
    entry._one = entry._one or {}
    local known, active, soonest = 0, 0, nil
    for _, id in ipairs(list) do
        if Known(id) then
            known = known + 1
            entry._one[id] = entry._one[id] or { id }
            local found, left = FindAuraCached("player", entry._one[id])
            if found == nil then return end
            if found then
                active = active + 1
                if left and (not soonest or left < soonest) then soonest = left end
            end
        end
    end
    if known == 0 then return end
    local required = math.min(known, Known(Data.TWO_POISONS_TALENT) and 2 or 1)
    local missing = active < required
    if not missing and not (settings.expiring and soonest and soonest < ExpiringSeconds()) then return end

    -- What a click casts: the chosen poison if it is not on, else the best
    -- known one that is not on.
    local pref = settings[entry.poisons == "lethal" and "prefLethal" or "prefNonLethal"]
    local cast
    if pref and pref > 0 and Known(pref) and FindAuraCached("player", entry._one[pref] or { pref }) == false then
        cast = pref
    end
    if not cast then
        for _, id in ipairs(list) do
            if Known(id) and FindAuraCached("player", entry._one[id]) == false then cast = id break end
        end
    end
    cast = cast or (pref and pref > 0 and Known(pref) and pref) or nil
    if not cast then
        for _, id in ipairs(list) do if Known(id) then cast = id break end end
    end
    Add(out, entry, { texture = SpellTexture(cast), spell = cast, timeLeft = (not missing) and soonest or nil,
        label = required > 1 and ("%d/%d"):format(active, required) or nil })
end

local function WeaponEnchantID(slot)
    local link = GetInventoryItemLink("player", slot)
    return link and tonumber(link:match("item:%d+:(%d*)")) or 0
end

local function RuneInfo(enchant)
    for _, rune in ipairs(Data.RUNES) do
        if rune.enchant == enchant then return rune end
    end
end

-- The rune chosen for this spec on each weapon; with none chosen, any rune.
local function EvaluateRuneforge(entry, specID, out)
    local wanted = specID and tonumber(settings["rune_" .. specID]) or 0
    if wanted <= 0 then
        if PermanentEnchant(entry.enchants) then return end
        Add(out, entry, { texture = SpellTexture(entry.cast), spell = entry.cast })
        return
    end
    local rune = RuneInfo(wanted)
    for _, hand in ipairs({ { 16, "MH" }, { 17, "OH" } }) do
        if (hand[1] == 16 or IsWeapon(17)) and GetInventoryItemID("player", hand[1]) and WeaponEnchantID(hand[1]) ~= wanted then
            Add(out, entry, { texture = SpellTexture(rune and rune.spell or entry.cast), spell = entry.cast,
                label = hand[2], wrong = rune and rune.name })
        end
    end
end

local function ActiveFormSpell()
    local index = GetShapeshiftForm and GetShapeshiftForm() or 0
    if index == 0 then return 0 end
    local _, _, _, spellID = GetShapeshiftFormInfo(index)
    return spellID
end

local function EvaluateDruidForm(entry, specID, out)
    local want = specID and Data.DRUID_FORM[specID]
    if not want then return end
    if settings.ignoreTravelForm and ((GetShapeshiftFormID and Data.DRUID_TRAVEL_FORMS[GetShapeshiftFormID() or 0])
        or IsMounted()) then return end
    local active = ActiveFormSpell()
    if active == nil or active == want then return end
    Add(out, entry, { texture = SpellTexture(want), spell = want })
end

local function EvaluateStance(entry, specID, out)
    local allowed = specID and Data.WARRIOR_STANCE[specID]
    if not allowed then return end
    local active = ActiveFormSpell()
    if active == nil then return end
    for _, id in ipairs(allowed) do if id == active then return end end
    local want = (specID == 72 and Known(Data.BERSERKER_STANCE)) and Data.BERSERKER_STANCE or allowed[1]
    Add(out, entry, { texture = SpellTexture(want), spell = want })
end

local function EvaluateFelguard(entry, out)
    if not UnitExists("pet") or UnitIsDead("pet") then return end
    local ok, _, family = pcall(UnitCreatureFamily, "pet")
    if not ok or IsSecret(family) or type(family) ~= "number" then return end
    if family == 29 then return end
    Add(out, entry, { texture = SpellTexture(entry.cast), spell = entry.cast })
end

local function EvaluatePassive(entry, out)
    if not UnitExists("pet") or not GetPetActionInfo then return end
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_PASSIVE" and isActive then
            Add(out, entry, { texture = entry.icon, macro = "/petassist" })
            return
        end
    end
end

local function EvaluateMageFood(entry, out)
    local index = GetSpecialization and GetSpecialization()
    local role = index and GetSpecializationRole and GetSpecializationRole(index)
    if role ~= "HEALER" or not IsInGroup() or not GroupHasClass("MAGE") then return end
    if ItemCount(entry.item) > 0 then return end
    Add(out, entry, { texture = entry.icon, stack = 0 })
end

-- A group buff another class gives, missing on you while one of that class
-- is in the group: a click asks for it.
local function EvaluateAsk(entry, out)
    if not IsInGroup() or AskedRecently(entry.key) then return end
    if not GroupHasClass(entry.class) or not Benefits(entry, "player") then return end
    if FindAuraCached("player", entry.auras) ~= false then return end
    local name = SpellName(entry.known) or Data.LABELS[entry.key] or entry.key
    Add(out, entry, { texture = SpellTexture(entry.known), ask = true,
        macro = AskMacro(AskText(name)) })
end

-- ── Talents and gear for this content ──────────────────────────────────────

local function LoadoutContent()
    local content = ContentType()
    if content == "scenario" then return "dungeon" end
    return content
end

-- The name chosen in Options for this spec and content, or nil.
local function Chosen(store, specID)
    local mine = type(settings[store]) == "table" and settings[store][SpecKey(specID)]
    local name = type(mine) == "table" and mine[LoadoutContent()]
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

-- The saved loadouts of a spec, as { name, configID } pairs.
local function Loadouts(specID)
    local list = {}
    if not (specID and C_ClassTalents and C_ClassTalents.GetConfigIDsBySpecID and C_Traits) then return list end
    local ok, ids = pcall(C_ClassTalents.GetConfigIDsBySpecID, specID)
    if not ok or type(ids) ~= "table" then return list end
    for _, id in ipairs(ids) do
        local okInfo, info = pcall(C_Traits.GetConfigInfo, id)
        if okInfo and info and type(info.name) == "string" then
            list[#list + 1] = { name = info.name, configID = id }
        end
    end
    return list
end

local function LoadoutID(specID, name)
    for _, loadout in ipairs(Loadouts(specID)) do
        if loadout.name == name then return loadout.configID end
    end
    return nil
end

-- Name of the loadout in use; false on an unsaved build; nil when unknown.
local function ActiveLoadoutName(specID)
    if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID and C_Traits) then return nil end
    local ok, id = pcall(C_ClassTalents.GetLastSelectedSavedConfigID, specID)
    if not ok then return nil end
    if not id then return false end
    local okInfo, info = pcall(C_Traits.GetConfigInfo, id)
    if okInfo and info and type(info.name) == "string" then return info.name end
    return nil
end

local function EvaluateTalents(entry, specID, out)
    if not specID then return end
    local want = Chosen("loadouts", specID)
    if not want then return end
    local active = ActiveLoadoutName(specID)
    if active == nil or active == want then return end
    -- A loadout deleted since it was chosen: nothing a click could load.
    if not LoadoutID(specID, want) then return end
    Add(out, entry, { texture = Data.LOADOUT_ICON, name = want, wrong = want, apply = "talents" })
end

local function EvaluateGear(entry, specID, out)
    local want = Chosen("gearSets", specID)
    if not want or not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID) then return end
    local setID = C_EquipmentSet.GetEquipmentSetID(want)
    if not setID then return end
    local _, icon, _, isEquipped = C_EquipmentSet.GetEquipmentSetInfo(setID)
    if isEquipped then return end
    Add(out, entry, { texture = icon or Data.GEAR_ICON, name = want, wrong = want,
        apply = "gear", setID = setID })
end

-- A talent swap that has to cast ("Changing Talents") finishes later; the
-- loadout is marked as the selected one when it does (TRAIT_CONFIG_UPDATED).
local pendingLoadout

local function MarkLoadoutSelected(specID, configID)
    if C_ClassTalents.UpdateLastSelectedSavedConfigID then
        pcall(C_ClassTalents.UpdateLastSelectedSavedConfigID, specID, configID)
    end
end

-- A click on a talents or gear icon. Out of combat only (the caller checks).
local function ApplyFix(record)
    if record.apply == "gear" then
        pcall(C_EquipmentSet.UseEquipmentSet, record.setID)
    elseif record.apply == "talents" then
        local specID = CurrentSpecID()
        local configID = specID and LoadoutID(specID, record.wrong)
        local loaded = false
        if configID and C_ClassTalents.LoadConfig then
            local ok, result = pcall(C_ClassTalents.LoadConfig, configID, true)
            local codes = Enum.LoadConfigResult
            if ok and result ~= nil and not (codes and result == codes.Error) then
                loaded = true
                if codes and result == codes.LoadInProgress then
                    pendingLoadout = { specID = specID, configID = configID, untilTime = GetTime() + 10 }
                else
                    MarkLoadoutSelected(specID, configID)
                end
            end
        end
        if not loaded and PlayerSpellsUtil and PlayerSpellsUtil.OpenToClassTalentsTab then
            PlayerSpellsUtil.OpenToClassTalentsTab()
        end
    end
    MarkDirty()
end

local function Evaluate(entry, specID, inInstance, forced, out)
    if entry.check == "talentLoadout" then return EvaluateTalents(entry, specID, out) end
    if entry.check == "gearSet" then return EvaluateGear(entry, specID, out) end
    if entry.group == "raid" then return EvaluateRaid(entry, out) end
    if entry.group == "targeted" then return EvaluateTargeted(entry, out) end
    if entry.check == "pet" then return EvaluatePet(entry, specID, out) end
    if entry.check == "demonChoice" then return EvaluateDemonChoice(entry, specID, out) end
    if entry.check == "felguard" then return EvaluateFelguard(entry, out) end
    if entry.check == "passive" then return EvaluatePassive(entry, out) end
    if entry.check == "poison" then return EvaluatePoison(entry, out) end
    if entry.check == "runeforge" then return EvaluateRuneforge(entry, specID, out) end
    if entry.check == "druidForm" then return EvaluateDruidForm(entry, specID, out) end
    if entry.check == "stance" then return EvaluateStance(entry, specID, out) end
    if entry.check == "delveFood" then
        if not InDelve() then delveFoodSince = nil return end
        -- Asked for once on the way in, then left alone.
        if settings.delveFoodTimer then
            delveFoodSince = delveFoodSince or GetTime()
            if GetTime() - delveFoodSince > Data.DELVE_FOOD_SECONDS then return end
        end
        local found, left = FindAuraCached("player", entry.auras)
        if Needed(found, left) then Add(out, entry, { texture = entry.icon, timeLeft = found and left or nil }) end
        return
    end
    if entry.present then
        -- Shown while it is ON (a buff you should not leave running).
        if FindAuraCached("player", entry.auras) == true then
            Add(out, entry, { texture = SpellTexture(entry.known) })
        end
        return
    end

    if entry.group == "consumable" then
        local check = entry.check
        if check == "repair" then return EvaluateRepair(out, entry) end
        if check == "readycheck" then
            if GetTime() < readyCheckUntil and IsInGroup() and inInstance then
                Add(out, entry, SpellRecord(entry.known))
            end
            return
        end
        if not inInstance and not forced then return end
        if check == "oil" then return EvaluateOil(entry, out) end
        if check == "healthstone" then return EvaluateHealthstone(out, entry) end
        if check == "mageFood" then return EvaluateMageFood(entry, out) end
        return EvaluateBuffItem(entry, out)
    end

    -- Self buffs
    local found, left
    if entry.form then
        found = GetShapeshiftForm and GetShapeshiftForm() > 0
    elseif entry.enchants and entry.permanent then
        found = PermanentEnchant(entry.enchants)
    elseif entry.enchants then
        found, left = WeaponEnchants(entry.enchants)
    else
        found, left = FindAuraCached("player", entry.auras)
    end
    if not Needed(found, left) then return end
    local spell = CastSpellFor(entry)
    Add(out, entry, { texture = SpellTexture(spell), spell = spell, timeLeft = found and left or nil })
end

-- Custom buffs become entries like the built-in ones, made once per spell.
local customEntries = {}
local function CustomEntries()
    local list = settings.customBuffs
    local out = customEntries.list or {}
    customEntries.list = out
    wipe(out)
    for _, id in ipairs(list) do
        local entry = customEntries[id]
        if not entry then
            entry = { key = "custom" .. id, group = "custom", auras = { id }, cast = id, custom = true }
            customEntries[id] = entry
        end
        out[#out + 1] = entry
    end
    return out
end

local function MaxLevel()
    return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 80
end

local function Collect()
    local list = {}
    local forced = GetTime() < readyCheckUntil
    local inInstance, instanceType = IsInInstance()
    inInstance = inInstance and instanceType ~= "pvp" and instanceType ~= "arena"

    if not forced then
        if settings.readyCheckOnly then return list end
        if settings.hideResting and IsResting() then return list end
        if settings.hideMounted and (IsMounted() or UnitInVehicle("player")) then return list end
        if UnitIsDeadOrGhost("player") then return list end
        if settings["where_" .. ContentType()] == false then return list end
        if settings.onlyInGroup and not IsInGroup() then return list end
        if settings.hideLeveling and UnitLevel("player") < MaxLevel() then return list end
    end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return list end

    local _, class = UnitClass("player")
    local specID = CurrentSpecID()
    local groupAllowed = forced or not settings.onlyInstances or inInstance

    local function Run(entries, enabled, needsPlace)
        if not enabled or (needsPlace and not groupAllowed) then return end
        for _, entry in ipairs(entries) do
            if #list >= MAX_BUTTONS then return end
            local hideKey = entry._hideKey
            if not hideKey then
                hideKey = "hide_" .. entry.key
                entry._hideKey = hideKey
            end
            local on
            if entry.optIn then on = settings[hideKey] == false else on = settings[hideKey] ~= true end
            local until_ = snoozed[entry.key]
            if until_ and until_ <= GetTime() then snoozed[entry.key] = nil until_ = nil end
            if on and not until_ and (entry.custom or Applies(entry, class, specID)) then
                Evaluate(entry, specID, inInstance, forced, list)
            end
        end
    end

    Run(Data.LOADOUT, settings.showLoadout, false)
    Run(Data.RAID, settings.showRaid, true)
    -- Group buffs you cannot give yourself, asked for with a click.
    if settings.askBuffs and groupAllowed then
        for _, entry in ipairs(Data.RAID) do
            if #list >= MAX_BUTTONS then break end
            -- ask_<key>: each one can be unticked in the Reminders window.
            if entry.class ~= class and settings["ask_" .. entry.key] ~= false
                and not ((snoozed[entry.key] or 0) > GetTime()) then
                EvaluateAsk(entry, list)
            end
        end
    end
    Run(Data.SELF, settings.showSelf, true)
    Run(CustomEntries(), true, true)
    Run(Data.TARGETED, settings.showTargeted, true)
    Run(Data.PET, settings.showPets, true)
    Run(Data.CONSUMABLE, settings.showConsumables, false)
    return list
end

-- ── The bar ─────────────────────────────────────────────────────────────────

local MIN_SIZE, MAX_SIZE = 20, 64

local function IconSize()
    local size = tonumber(settings.iconSize) or 0
    if size <= 0 then return settings.largeIcons and 44 or 34 end
    return math.max(MIN_SIZE, math.min(MAX_SIZE, size))
end


local function FormatLeft(seconds)
    if seconds >= 60 then return ("%dm"):format(math.ceil(seconds / 60)) end
    return ("%ds"):format(math.max(0, math.floor(seconds)))
end

local function LabelOf(entry)
    if entry.custom then return SpellName(entry.cast) or (L["Spell "] .. entry.cast) end
    return OxedHub.T(Data.LABELS[entry.key]) or entry.key
end

local function ShowTooltip(button)
    local record = button.record
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if not record then
        GameTooltip:SetText("Buff Reminder")
        GameTooltip:AddLine(L["Nothing is missing right now. Reminders appear here. Shift+drag to move it."], 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local label = LabelOf(record.entry)
    if record.item then
        GameTooltip:SetItemByID(record.item)
    elseif record.spell then
        GameTooltip:SetSpellByID(record.spell)
    else
        GameTooltip:SetText(label)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Buff Reminder: " .. label, 0.6, 0.8, 1)
    if record.count then
        GameTooltip:AddLine((L["%d nearby missing it"]):format(record.count), 1, 0.4, 0.4)
        if record.names then
            GameTooltip:AddLine(table.concat(record.names, ", "), 1, 1, 1, true)
        end
    elseif record.timeLeft then
        GameTooltip:AddLine((L["Runs out in %s"]):format(FormatLeft(record.timeLeft)), 1, 0.82, 0)
    elseif record.stack == 0 then
        GameTooltip:AddLine(L["None in your bags"], 1, 0.4, 0.4)
    end
    if record.wrong then
        GameTooltip:AddLine(L["Wanted: "] .. record.wrong, 1, 0.4, 0.4)
    end
    if record.slot then
        GameTooltip:AddLine(record.slot == 16 and L["For your main hand"] or L["For your off hand"], 1, 1, 1)
    end
    if record.entry.group == "targeted" then
        local last = settings.lastTargets[record.entry.key]
        if record.entry.key == "soulstone" and settings.soulstoneTarget ~= "" then last = settings.soulstoneTarget end
        if last then GameTooltip:AddLine(L["Casts on "] .. last .. L[" (it was on them last)"], 1, 1, 1) end
    end
    if record.ask and not record.stack then
        GameTooltip:AddLine(L["You are missing it; somebody in the group can give it"], 1, 0.4, 0.4, true)
    end
    if settings.clickCast and record.ask and record.macro then
        GameTooltip:AddLine(L["Click to ask for it in group chat"], 0.5, 1, 0.5)
    elseif settings.clickCast and record.apply then
        GameTooltip:AddLine(L["Click to switch to it"], 0.5, 1, 0.5)
    elseif settings.clickCast and (record.spell or record.item or record.macro) and not record.entry.noClick then
        GameTooltip:AddLine(L["Click to "] .. ((record.item or (record.macro and not record.spell)) and L["use it"] or L["cast it"]), 0.5, 1, 0.5)
    end
    if record.kind and settings.consumableMemory then
        GameTooltip:AddLine(L["The one you click is offered first next time on this spec"], 0.7, 0.7, 0.7, true)
    end
    if settings.rightSnooze then
        GameTooltip:AddLine((L["Right-click: hide it for %d minutes"]):format(settings.snoozeMinutes or 10), 0.7, 0.7, 0.7)
    end
    GameTooltip:Show()
end

-- Glow: a soft border that pulses. The animation runs on the texture, never
-- on the secure button itself.
local function CreateGlow(button)
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetPoint("CENTER")
    glow:Hide()
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.6)
    glow.pulse = pulse
    button.glow = glow
end

local function SetGlow(button, on, r, g, b)
    local glow = button.glow
    if on then
        local size = button:GetWidth() * 1.9
        glow:SetSize(size, size)
        glow:SetVertexColor(r, g, b)
        glow:Show()
        if not glow.pulse:IsPlaying() then glow.pulse:Play() end
    else
        glow.pulse:Stop()
        glow:Hide()
    end
end

local function CreateButton(index)
    local button = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    -- Both edges: the secure template acts on press or release depending on
    -- the player's "cast on key down" setting, and ignores the other one.
    -- Registering one edge only makes clicks do nothing for half of players.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button:RegisterForDrag("LeftButton")

    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetColorTexture(0, 0, 0, 0.9)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Stat or hand on top, H / F badge in the corner, count bottom right,
    -- pet name or time left under the icon.
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    button.label:SetPoint("TOP", button, "TOP", 0, -1)

    button.badge = button:CreateFontString(nil, "OVERLAY", "GameFontGreenSmall")
    button.badge:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)

    button.under = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.under:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.under:SetWordWrap(false)   -- long names are cut with "..."

    button.texts = { button.label, button.badge, button.count, button.under }
    CreateGlow(button)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Right-click hides the reminder for a while. The secure actions are set
    -- for the left button only, so the right one never casts.
    button:SetScript("PostClick", function(self, mouse, down)
        local record = self.record
        if not record or down or InCombatLockdown() then return end
        -- Left: the secure action has run (or there was none); what follows
        -- is bookkeeping, plus the talents / gear switch, which is not secure.
        if mouse == "LeftButton" then
            if not settings.clickCast then return end
            if record.ask then
                askedAt[record.entry.key] = GetTime()
                MarkDirty()
            elseif record.apply then
                ApplyFix(record)
            elseif record.kind then
                RememberItem(record)
            end
            return
        end
        if mouse ~= "RightButton" or not settings.rightSnooze then return end
        snoozed[record.entry.key] = GetTime() + (settings.snoozeMinutes or 10) * 60
        GameTooltip:Hide()
        MarkDirty()
    end)
    button:SetScript("OnDragStart", function()
        if not settings or InCombatLockdown() then return end
        if not settings.locked or (settings.shiftDrag and IsShiftKeyDown()) then
            button.dragging = true
            bar:StartMoving()
        end
    end)
    button:SetScript("OnDragStop", function()
        if not button.dragging then return end
        button.dragging = false
        bar:StopMovingOrSizing()
        local point, _, _, x, y = bar:GetPoint(1)
        settings.point, settings.x, settings.y = point, x, y
    end)
    button:Hide()
    buttons[index] = button
    return button
end

local function EnsureBar()
    if bar then return end
    bar = CreateFrame("Frame", "OxedHubBuffReminderBar", UIParent)
    bar:SetSize(40, 40)
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()
end

local function PlaceBar()
    bar:ClearAllPoints()
    bar:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 0, settings.y or 180)
end

local ACTION_KEYS = { "type", "type1", "spell1", "item1", "macrotext1", "unit1", "type2" }

local function SetAction(button, record)
    local kind, val
    if settings.clickCast and record and not record.sample and not record.entry.noClick then
        if record.macro then
            kind, val = "macro", record.macro
        elseif record.item then
            kind, val = "item", record.item
        elseif record.spell then
            kind, val = "spell", record.spell
        end
    end
    if button._actKind == kind and button._actVal == val then return end
    button._actKind, button._actVal = kind, val
    for _, key in ipairs(ACTION_KEYS) do button:SetAttribute(key, nil) end
    if not kind then return end
    if kind == "macro" then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", val)
    elseif kind == "item" then
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", "item:" .. val)
    elseif kind == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", val)
        button:SetAttribute("unit1", "player")
    end
end

-- Where icon i of `count` goes, by the chosen direction. Rows (or columns,
-- for UP and DOWN) hold perRow icons each.
local function Slot(i, count, perRow, size, gap, rowHeight)
    local direction = settings.growDirection or "RIGHT"
    local line = math.floor((i - 1) / perRow)          -- which row / column
    local pos = (i - 1) % perRow                       -- place within it
    local lines = math.ceil(count / perRow)
    local across = math.min(count, perRow)
    local step = size + gap

    if direction == "DOWN" or direction == "UP" then
        local x = line * step
        local y
        if direction == "DOWN" then y = -pos * rowHeight
        else y = -(across - 1 - pos) * rowHeight end
        return x, y, lines * step - gap, across * rowHeight
    end

    local inThisRow = math.min(perRow, count - line * perRow)
    local x
    if direction == "LEFT" then
        x = (across - 1 - pos) * step
    elseif direction == "CENTER" then
        x = (across - inThisRow) * step / 2 + pos * step
    else
        x = pos * step
    end
    return x, -line * rowHeight, across * step - gap, lines * rowHeight
end

-- ── Preview ─────────────────────────────────────────────────────────────────
-- While previewing, the bar shows previewCount sample icons made from every
-- reminder there is, in every state (missing with a count, running out,
-- items with a stack, a name under a pet), so size, spacing, rows, glow and
-- text can be set without waiting for something to go missing. Sample icons
-- never cast anything.

local previewing = false

local function EntryTexture(entry)
    if entry.icon then return entry.icon end
    local kind = entry.check == "oil" and "weaponOil" or entry.check
    local items = kind and Data.ITEMS[kind]
    if items and items[1] then return ItemIcon(items[1].id) end
    local spell = entry.cast or entry.known or (entry.castList and entry.castList[1])
        or (entry.auras and entry.auras[1]) or entry.selfAura
    return spell and SpellTexture(spell) or nil
end

local function PreviewList()
    local pool = {}
    for _, part in ipairs({ Data.RAID, Data.SELF, Data.TARGETED, Data.PET, Data.CONSUMABLE }) do
        for _, entry in ipairs(part) do
            local texture = EntryTexture(entry)
            if texture then pool[#pool + 1] = { entry = entry, texture = texture } end
        end
    end
    local list = {}
    local wanted = math.max(1, math.min(MAX_BUTTONS, tonumber(settings.previewCount) or 12))
    for i = 1, wanted do
        local source = pool[(i - 1) % #pool + 1]
        local entry = source.entry
        local record = { sample = true, preview = true, entry = entry, texture = source.texture }
        if entry.group == "raid" then
            record.count, record.total = (i % 3) + 1, 5
        elseif entry.group == "consumable" and entry.check ~= "repair" then
            record.item, record.stack = true, (i % 4 == 0) and 1 or 12
            if entry.check == "flask" then record.label = "Crit" end
        elseif entry.group == "pet" then
            record.name = "Pet"
        end
        if i % 4 == 2 then record.timeLeft = 90 + i * 7 end
        list[#list + 1] = record
    end
    return list
end

local function SetPreview(on)
    previewing = on and true or false
    MarkDirty()
end

-- Out of combat only: shows, hides and re-targets secure buttons.
local function Render(list)
    if InCombatLockdown() then return end
    local size = IconSize()
    local gap = tonumber(settings.spacing) or 6
    local perRow = math.max(1, tonumber(settings.perRow) or 10)
    local rowHeight = size + 16   -- room for the name / time under each icon
    local zoom = math.max(0, math.min(30, tonumber(settings.iconZoom) or 8)) / 100
    local alpha = math.max(10, math.min(100, tonumber(settings.iconAlpha) or 100)) / 100
    local border = math.max(0, math.min(4, tonumber(settings.borderSize) or 1))
    local textScale = math.max(50, math.min(200, tonumber(settings.textScale) or 100)) / 100

    -- A sample icon marks the bar while it is unlocked or Options is open,
    -- so the player can see where reminders will appear.
    local optionsOpen = optionsWindow and optionsWindow:IsShown()
    if #list == 0 and (not settings.locked or optionsOpen) then
        list = { { sample = true, texture = 136243 } }
    end

    local count = math.min(#list, MAX_BUTTONS)
    local _, _, width, height = Slot(1, math.max(1, count), perRow, size, gap, rowHeight)
    bar:SetSize(math.max(1, width), math.max(1, height))

    for i = 1, MAX_BUTTONS do
        local record = list[i]
        local button = buttons[i] or (record and CreateButton(i))
        if button then
            if record then
                local x, y = Slot(i, count, perRow, size, gap, rowHeight)
                button:SetSize(size, size)
                button.under:SetWidth(size + 18)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", bar, "TOPLEFT", x, y)
                button.record = not record.sample and record or nil
                button.icon:SetTexture(record.texture or 134400)
                button.icon:SetDesaturated(record.timeLeft ~= nil or record.stack == 0)
                button.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                button.icon:SetAlpha(alpha)
                button.border:SetShown(border > 0)
                button.border:SetPoint("TOPLEFT", -border, border)
                button.border:SetPoint("BOTTOMRIGHT", border, -border)
                for _, text in ipairs(button.texts) do
                    if text.SetTextScale then text:SetTextScale(textScale) end
                end
                button.label:SetText(record.label or "")
                button.badge:SetText(record.badge or "")

                local number = ""
                if record.count and record.count > 0 and (IsInGroup() or record.preview) then
                    if settings.missingCountOnly or not record.total then number = record.count
                    else number = ("%d/%d"):format(record.total - record.count, record.total) end
                elseif record.stack then number = record.stack end
                button.count:SetText(number)
                local low = tonumber(settings.lowStock) or 0
                if record.item and record.stack and record.stack > 0 and record.stack <= low then
                    button.count:SetTextColor(1, 0.25, 0.25)
                else
                    button.count:SetTextColor(1, 1, 1)
                end

                if record.timeLeft then
                    button.under:SetText(FormatLeft(record.timeLeft))
                else
                    local name = record.name
                    if not name and settings.showNames and record.preview then
                        name = LabelOf(record.entry)
                    elseif not name and settings.showNames and not record.sample then
                        name = record.item and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(record.item)
                        name = name or LabelOf(record.entry)
                    end
                    button.under:SetText(name or "")
                end

                if record.sample and not record.preview then
                    SetGlow(button, false)
                elseif record.timeLeft then
                    SetGlow(button, settings.glowExpiring, 1, 0.82, 0.2)
                else
                    SetGlow(button, settings.glowMissing, 1, 0.3, 0.3)
                end

                SetAction(button, record)
                button:Show()
            else
                button.record = nil
                SetGlow(button, false)
                SetAction(button, nil)
                button:Hide()
            end
        end
    end
end

-- A sound when something new goes missing. Not on the first look after
-- login or a switch-on, and not more than once in ten seconds.
local shownKeys, nextKeys = {}, {}
local quietUntil, lastSound = 0, 0

local function SoundForNew(list)
    local fresh = false
    wipe(nextKeys)
    for _, record in ipairs(list) do
        local key = record.entry and record.entry.key
        if key then
            nextKeys[key] = true
            if not shownKeys[key] and not record.timeLeft then fresh = true end
        end
    end
    shownKeys, nextKeys = nextKeys, shownKeys
    local now = GetTime()
    if fresh and settings.sound and settings.sound ~= "" and now >= quietUntil and now - lastSound > 10 then
        lastSound = now
        local API = OxedHub.ModuleAPI
        if API and API.PlaySound then API:PlaySound(settings.sound) end
    end
end

local function Refresh()
    pending = false
    if not settings or settings.enabled ~= true or not bar then return end
    if InCombatLockdown() then return end
    if previewing then
        Render(PreviewList())
        return
    end
    -- While the game keeps auras secret, keep the bar as it was.
    if AurasSecretNow() then return end
    local list = Collect()
    SoundForNew(list)
    Render(list)
end

MarkDirty = function()
    if pending then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, Refresh)
end

-- ⚠ Other group members' auras change all the time in a raid or a busy
-- group: one refresh for each made 156 MB of garbage in two hours. Their
-- changes wait GROUP_DELAY and fold into one refresh; your own still show
-- at once.
local GROUP_DELAY = 2
local groupPending = false
local function RunGroupRefresh()
    groupPending = false
    MarkDirty()
end
local function MarkGroupDirty()
    if groupPending or pending then return end
    groupPending = true
    C_Timer.After(GROUP_DELAY, RunGroupRefresh)
end

local GROUP_UNIT_SET = {}
for i = 1, 40 do GROUP_UNIT_SET["raid" .. i] = true end
for i = 1, 4 do GROUP_UNIT_SET["party" .. i] = true end

local function IsGroupUnit(unit)
    return unit ~= nil and GROUP_UNIT_SET[unit] == true
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    "UNIT_AURA", "UNIT_PET", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "ZONE_CHANGED_NEW_AREA", "READY_CHECK", "BAG_UPDATE_DELAYED", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "UPDATE_INVENTORY_DURABILITY", "PET_STABLE_UPDATE", "PET_BAR_UPDATE", "PLAYER_LEVEL_UP",
    "TRAIT_CONFIG_UPDATED", "EQUIPMENT_SETS_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
}

local combatAurasDirty = false

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        -- Nameplates, the target and the rest: not ours to track, dropped
        -- before anything else (this event arrives a million times a session).
        -- In combat the bar is hidden and never rebuilt, so defer cache wipes
        -- until combat ends instead of wiping per-unit tables on every hit.
        if InCombatLockdown() then
            combatAurasDirty = true
            return
        end
        local own = unit == "player" or unit == "pet"
        if not own and not GROUP_UNIT_SET[unit] then return end
        ForgetUnit(unit)
        if not own then
            MarkGroupDirty()
            return
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combatAurasDirty then
            combatAurasDirty = false
            ForgetAllUnits()
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- raid3 may be somebody else now.
        combatAurasDirty = false
        ForgetAllUnits()
    elseif event == "TRAIT_CONFIG_UPDATED" then
        local load = pendingLoadout
        pendingLoadout = nil
        if load and GetTime() < load.untilTime then MarkLoadoutSelected(load.specID, load.configID) end
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        if not IsMounted() then
            petPauseUntil = GetTime() + Data.DISMOUNT_PET_PAUSE
            C_Timer.After(Data.DISMOUNT_PET_PAUSE + 0.2, MarkDirty)
        end
    elseif event == "READY_CHECK" then
        if settings.readyCheck or settings.readyCheckOnly then
            readyCheckUntil = GetTime() + READY_CHECK_SECONDS
            C_Timer.After(READY_CHECK_SECONDS + 0.5, MarkDirty)
        end
    elseif (event == "BAG_UPDATE_DELAYED" or event == "PET_BAR_UPDATE") and InCombatLockdown() then
        return
    end
    MarkDirty()
end)

local function Start()
    EnsureBar()
    PlaceBar()
    quietUntil = GetTime() + 5
    for _, event in ipairs(EVENTS) do watcher:RegisterEvent(event) end
    if not InCombatLockdown() then
        -- The game hides the bar in combat and shows it after, even while
        -- the frame is protected by its secure buttons.
        RegisterStateDriver(bar, "visibility", "[combat][petbattle] hide; show")
    end
    if not ticker then ticker = C_Timer.NewTicker(TICK, MarkDirty) end
    MarkDirty()
end

local function Stop()
    watcher:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    if bar and not InCombatLockdown() then
        UnregisterStateDriver(bar, "visibility")
        bar:Hide()
    end
end

-- Switched on or off during combat: the driver cannot be set up until it ends.
local lateStart = CreateFrame("Frame")
lateStart:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    if settings and settings.enabled == true then Start() else Stop() end
end)

local function SafeStart()
    if InCombatLockdown() then
        lateStart:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        Start()
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.buffreminder
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.buffreminder = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Lists are made here, never in DEFAULTS (they would be shared).
    if type(config.customBuffs) ~= "table" then config.customBuffs = {} end
    if type(config.lastTargets) ~= "table" then config.lastTargets = {} end
    if type(config.lastUsed) ~= "table" then config.lastUsed = {} end   -- spec -> kind -> itemID
    if type(config.loadouts) ~= "table" then config.loadouts = {} end   -- spec -> content -> loadout name
    if type(config.gearSets) ~= "table" then config.gearSets = {} end   -- spec -> content -> set name
    -- Warlock demons per content: a set of summon spells, so a content can
    -- want more than one. Older settings held a single demon; it carries over.
    for _, content in ipairs(Data.DEMON_CONTENT) do
        local key = "demons_" .. content.key
        if type(config[key]) ~= "table" then
            local old = tonumber(config["demon_" .. content.key])
            config[key] = old and { [old] = true } or {}
        end
    end
    -- The old "large icons" box becomes a size the slider can show.
    if (tonumber(config.iconSize) or 0) <= 0 then config.iconSize = config.largeIcons and 44 or 34 end
    settings = config
end

-- ── Options ─────────────────────────────────────────────────────────────────

local subWindows = {}

-- A plain button on an options window, two to a row.
local function AddButtonRow(w, items)
    local width = math.floor((w:GetWidth() - 50) / 2)
    for i, item in ipairs(items) do
        local col = (i - 1) % 2
        if i > 1 and col == 0 then w.cursorY = w.cursorY - 26 end
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", w, "TOPLEFT", 20 + col * (width + 10), w.cursorY - 4)
        b:SetText(item[1])
        b:SetScript("OnClick", item[2])
    end
    w.cursorY = w.cursorY - 34
end

local function Heading(w, text)
    local h = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 6)
    h:SetText(OxedHub.T(text))
    w.cursorY = w.cursorY - 24
end

-- Shows a second window once built; the second click closes it.
local function ToggleSub(name, build)
    local w = subWindows[name]
    if not w then
        w = build()
        subWindows[name] = w
        w:HookScript("OnShow", MarkDirty)
    end
    if w:IsShown() then w:Hide() return end
    -- Every options window opens at the centre of the screen, so two of them
    -- landed on top of each other. One at a time, beside the main window
    -- (left of it when there is no room on the right).
    for other, sub in pairs(subWindows) do
        if other ~= name then sub:Hide() end
    end
    if optionsWindow then
        w:ClearAllPoints()
        local right = (optionsWindow:GetRight() or 0) + w:GetWidth() + 8
        if right <= UIParent:GetWidth() then
            w:SetPoint("TOPLEFT", optionsWindow, "TOPRIGHT", 8, 0)
        else
            w:SetPoint("TOPRIGHT", optionsWindow, "TOPLEFT", -8, 0)
        end
    end
    w:Show()
    w:Raise()
end

local function FitHeight(w)
    w:SetHeight(math.max(120, -w.cursorY + 16))
end

-- How many custom buffs the list holds (the Custom buffs window adds them).
local MAX_CUSTOM = 12

-- Every reminder there is, for every class, each with its icon and its own
-- box, by section; your class first, the others under their class's name.
-- Scrolls, since all of them together are taller than the screen.
local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local function ClassName(classFile)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile
end

local function ClassLabel(classFile)
    local colour = C_ClassColor and C_ClassColor.GetClassColor(classFile)
    local name = ClassName(classFile)
    return colour and colour:WrapTextInColorCode(name) or name
end

local function BuildReminders(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Reminders", 620, 640)
    local _, myClass = UnitClass("player")

    -- A tick means "remind me"; stored as hide_<key>, opt-in ones off until ticked.
    local byKey = {}
    local remindProxy = setmetatable({}, {
        __index = function(_, key)
            local entry = byKey[key]
            if entry and entry.optIn then return settings["hide_" .. key] == false end
            return settings["hide_" .. key] ~= true
        end,
        __newindex = function(_, key, value)
            settings["hide_" .. key] = not value
            MarkDirty()
        end,
    })
    -- Group buffs other classes give, asked for with a click: ask_<key>,
    -- on until unticked.
    local askProxy = setmetatable({}, {
        __index = function(_, key) return settings["ask_" .. key] ~= false end,
        __newindex = function(_, key, value)
            settings["ask_" .. key] = value and true or false
            MarkDirty()
        end,
    })

    local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -32, 12)
    local CONTENT_W = 570
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(CONTENT_W, 10)
    scroll:SetScrollChild(content)

    local COL_W, ROW_H = CONTENT_W / 2, 26
    local y = -4
    local col = 0
    local rows = {}

    local function EndLine()
        if col ~= 0 then
            y = y - ROW_H
            col = 0
        end
    end

    -- A section title with a gold rule under it, or (small) a class's name.
    local function Head(text, small)
        EndLine()
        local h = content:CreateFontString(nil, "OVERLAY", small and "GameFontHighlight" or "GameFontNormalLarge")
        h:SetPoint("TOPLEFT", content, "TOPLEFT", small and 10 or 4, y - (small and 4 or 10))
        h:SetText(small and text or OxedHub.T(text))
        y = y - (small and 22 or 34)
        if not small then
            local line = content:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(0.6, 0.5, 0.2, 0.5)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", content, "TOPLEFT", 4, y + 4)
            line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, y + 4)
        end
    end

    -- One tick box with the buff's icon and name, two to a line.
    local function Row(config, key, label, texture, tooltip)
        local box = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("TOPLEFT", content, "TOPLEFT", 8 + col * COL_W, y)
        box.icon = box:CreateTexture(nil, "ARTWORK")
        box.icon:SetSize(20, 20)
        box.icon:SetPoint("LEFT", box, "RIGHT", 2, 0)
        box.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        box.icon:SetTexture(texture or 134400)
        box.text:ClearAllPoints()
        box.text:SetPoint("LEFT", box.icon, "RIGHT", 6, 0)
        box.text:SetWidth(COL_W - 64)
        box.text:SetJustifyH("LEFT")
        box.text:SetWordWrap(false)
        box.text:SetFontObject("GameFontHighlight")
        box.text:SetText(OxedHub.T(label))
        box:SetScript("OnClick", function(self) config[key] = self:GetChecked() and true or false end)
        box.Refresh = function() box:SetChecked(config[key] == true) end
        if tooltip then
            box:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.text:GetText())
                GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            box:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        rows[#rows + 1] = box
        col = col + 1
        if col == 2 then
            col = 0
            y = y - ROW_H
        end
        return box
    end

    local function EntryRow(config, entry)
        byKey[entry.key] = entry
        return Row(config, entry.key, Data.LABELS[entry.key] or entry.key, EntryTexture(entry),
            entry.optIn and OxedHub.T("Off until you tick it.") or nil)
    end

    -- A section of class buffs: those with no class and your class's first,
    -- then each other class under its coloured name.
    local function ClassSection(title, entries)
        Head(title)
        local mine = {}
        for _, entry in ipairs(entries) do
            if not entry.class or entry.class == myClass then mine[#mine + 1] = entry end
        end
        if #mine > 0 then
            Head(ClassLabel(myClass), true)
            for _, entry in ipairs(mine) do EntryRow(remindProxy, entry) end
        end
        for _, classFile in ipairs(CLASS_ORDER) do
            if classFile ~= myClass then
                local any = false
                for _, entry in ipairs(entries) do
                    if entry.class == classFile then
                        if not any then
                            Head(ClassLabel(classFile), true)
                            any = true
                        end
                        EntryRow(remindProxy, entry)
                    end
                end
            end
        end
    end

    Head(Data.GROUP_TITLES.loadout)
    for _, entry in ipairs(Data.LOADOUT) do
        byKey[entry.key] = entry
        Row(remindProxy, entry.key, Data.LABELS[entry.key] or entry.key,
            entry.key == "gearSet" and Data.GEAR_ICON or Data.LOADOUT_ICON)
    end

    Head("Group buffs you give")
    for _, entry in ipairs(Data.RAID) do
        byKey[entry.key] = entry
        Row(remindProxy, entry.key, Data.LABELS[entry.key] or entry.key, EntryTexture(entry),
            OxedHub.T("When you play this class: shows how many nearby players lack it, and a click casts it.")
            .. " (" .. ClassLabel(entry.class) .. ")")
    end

    Head("Group buffs from others")
    for _, entry in ipairs(Data.RAID) do
        Row(askProxy, entry.key, Data.LABELS[entry.key] or entry.key, EntryTexture(entry),
            OxedHub.T("Shown when it is missing on you and that class is in your group. A click asks for it. Needs \"Ask for buffs you lack\" in Smarter choices.")
            .. " (" .. ClassLabel(entry.class) .. ")")
    end

    ClassSection(Data.GROUP_TITLES.self, Data.SELF)
    ClassSection(Data.GROUP_TITLES.targeted, Data.TARGETED)
    ClassSection(Data.GROUP_TITLES.pet, Data.PET)

    Head(Data.GROUP_TITLES.consumable)
    for _, entry in ipairs(Data.CONSUMABLE) do
        if not entry.class then EntryRow(remindProxy, entry) end
    end
    for _, entry in ipairs(Data.CONSUMABLE) do
        if entry.class then EntryRow(remindProxy, entry) end
    end

    -- Your custom buffs: a row per possible one, filled each time the window
    -- opens, since the list changes in the Custom buffs window.
    Head("Custom buffs")
    local customProxy = setmetatable({}, {
        __index = function(_, slot)
            local id = settings.customBuffs[tonumber(slot:match("%d+"))]
            return id and settings["hide_custom" .. id] ~= true or false
        end,
        __newindex = function(_, slot, value)
            local id = settings.customBuffs[tonumber(slot:match("%d+"))]
            if id then
                settings["hide_custom" .. id] = not value
                MarkDirty()
            end
        end,
    })
    local customTop = y
    local customRows = {}
    for i = 1, MAX_CUSTOM do customRows[i] = Row(customProxy, "slot" .. i, "", nil) end
    local none = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    none:SetPoint("TOPLEFT", content, "TOPLEFT", 12, customTop - 6)
    none:SetText(L["None yet. Add them in Custom buffs."])

    local function Refresh()
        local list = settings.customBuffs
        for i, box in ipairs(customRows) do
            local id = list[i]
            if id then
                box.icon:SetTexture(SpellTexture(id) or 134400)
                box.text:SetText(SpellName(id) or (L["Spell "] .. id))
                box:Show()
            else
                box:Hide()
            end
        end
        none:SetShown(#list == 0)
        local customH = math.max(1, math.ceil(#list / 2)) * ROW_H
        content:SetHeight(-customTop + customH + 10)
        for _, box in ipairs(rows) do box.Refresh() end
    end
    w:HookScript("OnShow", Refresh)
    Refresh()
    return w
end

local DIRECTIONS = {
    { value = "RIGHT", text = "Grow to the right" }, { value = "LEFT", text = "Grow to the left" },
    { value = "CENTER", text = "Centred" }, { value = "DOWN", text = "Grow downwards" },
    { value = "UP", text = "Grow upwards" },
}

local function BuildLayout(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Layout and glow", 440, 400)
    w:AddSlider(settings, "iconSize", "Icon size", MIN_SIZE, MAX_SIZE, 2, "%s: %d", MarkDirty)
    w:AddSlider(settings, "spacing", "Space between icons", 0, 20, 1, "%s: %d", MarkDirty)
    w:AddSlider(settings, "perRow", "Icons per row", 1, 20, 1, "%s: %d", MarkDirty)
    w:AddChoice(settings, "growDirection", "Direction", DIRECTIONS, MarkDirty)
    w:AddSlider(settings, "iconAlpha", "Icon opacity", 10, 100, 5, "%s: %d%%", MarkDirty)
    w:AddSlider(settings, "iconZoom", "Icon zoom", 0, 30, 1, "%s: %d%%", MarkDirty)
    w:AddSlider(settings, "borderSize", "Border", 0, 4, 1, "%s: %d px", MarkDirty)
    w:AddSlider(settings, "textScale", "Text size", 50, 200, 10, "%s: %d%%", MarkDirty)
    w:AddCheckbox(settings, "missingCountOnly", "Group buffs: count who is missing it",
        "Ticked: \"3\" means three players lack it. Unticked: \"2/5\", two of five have it.", MarkDirty)
    w:AddCheckbox(settings, "showNames", "Show names under the icons", nil, MarkDirty)
    w:AddCheckbox(settings, "glowMissing", "Glow around what is missing", nil, MarkDirty)
    w:AddCheckbox(settings, "glowExpiring", "Glow around what is running out", nil, MarkDirty)
    w:AddCheckbox(settings, "locked", "Lock the bar",
        "Untick to drag the bar; a sample icon marks it while nothing is missing.", MarkDirty)
    w:AddCheckbox(settings, "shiftDrag", "Shift+drag moves the locked bar")
    FitHeight(w)
    return w
end

local function BuildWhere(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Where it shows", 380, 400)
    Heading(w, L["Show the bar in"])
    w:AddCheckbox(settings, "where_openWorld", "The open world", nil, MarkDirty)
    w:AddCheckbox(settings, "where_dungeon", "Dungeons", nil, MarkDirty)
    w:AddCheckbox(settings, "where_raid", "Raids", nil, MarkDirty)
    w:AddCheckbox(settings, "where_delve", "Delves", nil, MarkDirty)
    w:AddCheckbox(settings, "where_scenario", "Other scenarios", nil, MarkDirty)
    w:AddCheckbox(settings, "where_pvp", "Battlegrounds and arenas", nil, MarkDirty)
    Heading(w, L["And hide it"])
    w:AddCheckbox(settings, "onlyInstances", "Group and own buffs only inside instances", nil, MarkDirty)
    w:AddCheckbox(settings, "onlyInGroup", "When you are not in a group", nil, MarkDirty)
    w:AddCheckbox(settings, "hideLeveling", "While you are levelling", nil, MarkDirty)
    w:AddCheckbox(settings, "hideResting", "In cities and inns", nil, MarkDirty)
    w:AddCheckbox(settings, "hideMounted", "While mounted", nil, MarkDirty)
    w:AddNote("A ready check shows everything for 30 seconds wherever you are.")
    FitHeight(w)
    return w
end

local function SpellChoices(ids, firstText)
    local choices = { { value = 0, text = firstText } }
    for _, id in ipairs(ids) do
        choices[#choices + 1] = { value = id, text = SpellName(id) or (L["Spell "] .. id) }
    end
    return choices
end

local function BuildClass(API, class)
    local w = API:CreateOptionsWindow("Buff Reminder: Class choices", 440, 300)
    if class == "ROGUE" then
        Heading(w, L["Poisons a click applies"])
        w:AddChoice(settings, "prefLethal", "Lethal", SpellChoices(Data.LETHAL_POISONS, L["Best you know"]), MarkDirty)
        w:AddChoice(settings, "prefNonLethal", "Non-lethal", SpellChoices(Data.NONLETHAL_POISONS, L["Best you know"]), MarkDirty)
        w:AddNote("With Dragon-Tempered Blades two of each kind are needed; the icon shows how many are on.")
    elseif class == "DEATHKNIGHT" then
        Heading(w, L["Rune each spec should have"])
        local choices = { { value = 0, text = L["Any rune"] } }
        for _, rune in ipairs(Data.RUNES) do choices[#choices + 1] = { value = rune.enchant, text = rune.name } end
        for _, spec in ipairs(Data.DK_SPECS) do
            w:AddChoice(settings, "rune_" .. spec.id, spec.name, choices, MarkDirty)
        end
        w:AddNote("A weapon with a different rune shows the one you want; a click opens Runeforging.")
    elseif class == "DRUID" then
        w:AddCheckbox(settings, "ignoreTravelForm", "No wrong-form reminder while travelling or mounted", nil, MarkDirty)
        w:AddNote("Turn on \"Wrong druid form\" in Reminders: Balance wants Moonkin Form, Feral wants Cat Form.")
    elseif class == "WARRIOR" then
        w:AddNote("Turn on \"Wrong warrior stance\" in Reminders: Arms wants Battle Stance, Fury Battle or Berserker, Protection Defensive.")
    elseif class == "WARLOCK" then
        Heading(w, L["Demons wanted, per content"])
        -- A row of boxes per content: any number of demons can be wanted.
        local boxes = {}
        for _, content in ipairs(Data.DEMON_CONTENT) do
            local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
            label:SetText(OxedHub.T(content.text))
            w.cursorY = w.cursorY - 22
            for i, id in ipairs(Data.DEMON_CHOICES) do
                local box = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
                box:SetSize(22, 22)
                box:SetPoint("TOPLEFT", w, "TOPLEFT", 22 + (i - 1) * 100, w.cursorY)
                box.text:SetFontObject("GameFontHighlightSmall")
                box.text:SetText(OxedHub.T(Data.DEMON_NAMES[id]) or SpellName(id) or (L["Spell "] .. id))
                box.key, box.id = "demons_" .. content.key, id
                box:SetScript("OnClick", function(self)
                    settings[self.key][self.id] = self:GetChecked() and true or nil
                    MarkDirty()
                end)
                boxes[#boxes + 1] = box
            end
            w.cursorY = w.cursorY - 28
        end
        w:HookScript("OnShow", function()
            for _, box in ipairs(boxes) do box:SetChecked(settings[box.key][box.id] == true) end
        end)
        for _, box in ipairs(boxes) do box:SetChecked(settings[box.key][box.id] == true) end
        w:AddNote("The ticked demons come first when yours is missing. Turn on \"Not one of your demons for this content\" "
            .. "in Reminders to be told when another one is out. Demonology always wants its Felguard.")
        w:AddCheckbox(settings, "felDomination", "Fel Domination before a summon",
            "A click on a demon icon casts Fel Domination first, so the demon arrives at once.", MarkDirty)

        Heading(w, L["Soulstone always goes on"])
        -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard at once.
        local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
        box:SetAutoFocus(false)
        box:SetSize(220, 22)
        box:SetPoint("TOPLEFT", w, "TOPLEFT", 26, w.cursorY - 4)
        box:SetMaxLetters(60)
        local function Save()
            settings.soulstoneTarget = strtrim(box:GetText() or "")
            box:ClearFocus()
            MarkDirty()
        end
        box:SetScript("OnEnterPressed", Save)
        box:SetScript("OnEditFocusLost", Save)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(settings.soulstoneTarget or "")
            self:ClearFocus()
        end)
        w:HookScript("OnShow", function() box:SetText(settings.soulstoneTarget or "") end)
        w:HookScript("OnHide", function() box:ClearFocus() end)
        box:SetText(settings.soulstoneTarget or "")
        w.cursorY = w.cursorY - 32
        w:AddNote("A player's name, with the realm when it is not yours. Empty: whoever had it last, else the healer.")
    end
    FitHeight(w)
    return w
end

-- Talent loadout and equipment set per kind of content, for the current
-- spec. The choice lists are refilled each time the window opens, so a new
-- loadout or a spec change shows up.
local function BuildLoadouts(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Talents and gear", 460, 400)
    w:AddNote("Pick what you want for each kind of content. When something else is in use an icon shows; "
        .. "a click switches to it. Chosen per specialisation.")
    local specLine = w:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specLine:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 6)
    w.cursorY = w.cursorY - 24

    -- Reads and writes settings[store][spec][content] for the spec in use now.
    local function Store(store)
        return setmetatable({}, {
            __index = function(_, content)
                local mine = settings[store][SpecKey(CurrentSpecID())]
                return mine and mine[content] or ""
            end,
            __newindex = function(_, content, value)
                local key = SpecKey(CurrentSpecID())
                settings[store][key] = settings[store][key] or {}
                settings[store][key][content] = (value ~= "") and value or nil
                MarkDirty()
            end,
        })
    end

    local talentChoices, gearChoices, choiceButtons = {}, {}, {}
    local talents, gear = Store("loadouts"), Store("gearSets")
    Heading(w, L["Talent loadout"])
    for _, content in ipairs(Data.LOADOUT_CONTENT) do
        choiceButtons[#choiceButtons + 1] = w:AddChoice(talents, content.key, content.text, talentChoices)
    end
    Heading(w, L["Equipment set"])
    for _, content in ipairs(Data.LOADOUT_CONTENT) do
        choiceButtons[#choiceButtons + 1] = w:AddChoice(gear, content.key, content.text, gearChoices)
    end
    w:AddNote("Other scenarios use the dungeon choice. Nothing switches in combat.")

    local function Fill()
        local specID = CurrentSpecID()
        local specName = specID and GetSpecializationInfoByID and select(2, GetSpecializationInfoByID(specID))
        specLine:SetText(L["For: "] .. (specName or L["no specialisation yet"]))
        wipe(talentChoices)
        talentChoices[1] = { value = "", text = L["Don't care"] }
        for _, loadout in ipairs(Loadouts(specID)) do
            talentChoices[#talentChoices + 1] = { value = loadout.name, text = loadout.name }
        end
        wipe(gearChoices)
        gearChoices[1] = { value = "", text = L["Don't care"] }
        if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
            for _, id in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
                local name = C_EquipmentSet.GetEquipmentSetInfo(id)
                if type(name) == "string" then gearChoices[#gearChoices + 1] = { value = name, text = name } end
            end
        end
        for _, button in ipairs(choiceButtons) do button.Refresh() end
    end
    w:HookScript("OnShow", Fill)
    Fill()
    FitHeight(w)
    return w
end

local function BuildSmarter(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Smarter choices", 460, 300)
    Heading(w, L["Group buffs"])
    w:AddCheckbox(settings, "benefitOnly", "Count only players the buff helps",
        "Arcane Intellect is not missing on a warrior, nor Battle Shout on a priest. Uses each player's spec when the game knows it.", MarkDirty)
    w:AddCheckbox(settings, "askBuffs", "Ask for buffs you lack",
        "A group buff you cannot give yourself, missing on you while its class is in the group, shows an icon; "
        .. "a click asks for it in group chat (once every 30 seconds). Also asks for a Soulwell when you have no Healthstone.", MarkDirty)
    w:AddCheckbox(settings, "askCooldown", "Wait 30 seconds before asking again",
        "Untick if a request seems not to arrive and you want to send it again at once.", MarkDirty)
    w:AddCheckbox(settings, "raidSelfOnly", "Only check yourself",
        "The group buff icon shows only when you lack it, not when somebody else in the group does.", MarkDirty)
    Heading(w, L["Consumables"])
    w:AddCheckbox(settings, "consumableMemory", "Offer the one you used last first",
        "Remembered per specialisation: the food, flask, rune or oil you clicked last time comes first.", MarkDirty)
    w:AddCheckbox(settings, "oneConsumable", "Only one icon per kind", "Just the first: the remembered one, else the best you carry.", MarkDirty)
    w:AddSlider(settings, "lowStock", "Count in red at or below", 0, 10, 1, "%s %d", MarkDirty)
    w:AddCheckbox(settings, "withoutItems", "Show food, flask and oil even with none in your bags", nil, MarkDirty)
    w:AddCheckbox(settings, "withoutItemsReadyCheck", "...but those only on a ready check", nil, MarkDirty)
    w:AddCheckbox(settings, "hideLegacyItems", "Leave out items from older expansions",
        "Food, flasks and oil from a past expansion get no icon, even when they are in your bags.", MarkDirty)
    w:AddCheckbox(settings, "delveFoodOnly", "Only delve food in delves", nil, MarkDirty)
    w:AddCheckbox(settings, "delveFoodTimer", "Delve food reminder gives up after 30 seconds", nil, MarkDirty)
    w:AddSlider(settings, "healthstoneLow", "Healthstone reminder at or below", 0, 3, 1, "%s %d charges", MarkDirty)
    w:AddSlider(settings, "repairBelow", "Repair reminder below", 5, 95, 5, "%s %d%% durability", MarkDirty)
    w:AddNote("A click on the repair icon summons your Grand Expedition Yak or Mighty Caravan Brutosaur, or uses an Auto-Hammer or Jeeves, whichever you have.")

    Heading(w, L["Your request in chat"])
    -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard at once.
    local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(w:GetWidth() - 60, 22)
    box:SetPoint("TOPLEFT", w, "TOPLEFT", 26, w.cursorY - 4)
    box:SetMaxLetters(200)
    local function Save()
        settings.askMessage = strtrim(box:GetText() or "")
        box:ClearFocus()
        MarkDirty()
    end
    box:SetScript("OnEnterPressed", Save)
    box:SetScript("OnEditFocusLost", Save)
    box:SetScript("OnEscapePressed", function(self)
        self:SetText(settings.askMessage or "")
        self:ClearFocus()
    end)
    w:HookScript("OnShow", function()
        local text = settings.askMessage
        box:SetText((type(text) == "string" and text ~= "") and text or Data.ASK_MESSAGE)
    end)
    w:HookScript("OnHide", function() box:ClearFocus() end)
    box:SetText((settings.askMessage ~= "" and settings.askMessage) or Data.ASK_MESSAGE)
    w.cursorY = w.cursorY - 32
    w:AddNote("{buff} becomes the buff's name. Empty the box for the default wording.")
    FitHeight(w)
    return w
end

-- Custom buffs: any spell, by ID or by the name of one you know. Shown when
-- it is not on you; a click casts it when you know it.
local function BuildCustom(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Custom buffs", 400, 200)
    w:AddNote("Start typing a spell's name and pick it from the list, or type a spell ID and press Add. "
        .. "It shows when that buff is not on you.")

    -- The same search box as the triggers: suggestions drop down as you type.
    -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard at once.
    local box = CreateFrame("EditBox", nil, w, "SearchBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(220, 22)
    box:SetPoint("TOPLEFT", w, "TOPLEFT", 26, w.cursorY - 4)

    local add = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    add:SetSize(80, 22)
    add:SetPoint("LEFT", box, "RIGHT", 10, 0)
    add:SetText(L["Add"])

    local status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -4, -4)
    status:SetTextColor(1, 0.5, 0.5)
    w.cursorY = w.cursorY - 48

    local top = w.cursorY
    local rows = {}
    local function Rebuild()
        local list = settings.customBuffs
        for i = 1, MAX_CUSTOM do
            local row = rows[i]
            local id = list[i]
            if id and not row then
                row = CreateFrame("Frame", nil, w)
                row:SetSize(w:GetWidth() - 40, 24)
                row:SetPoint("TOPLEFT", w, "TOPLEFT", 20, top - (i - 1) * 26)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT")
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.remove:SetSize(70, 20)
                row.remove:SetPoint("RIGHT")
                row.remove:SetText(L["Remove"])
                rows[i] = row
            end
            if row then
                if id then
                    row.icon:SetTexture(SpellTexture(id) or 134400)
                    row.text:SetText(("%s  |cff888888%d|r"):format(SpellName(id) or L["Unknown spell"], id))
                    row.remove:SetScript("OnClick", function()
                        table.remove(settings.customBuffs, i)
                        Rebuild()
                        MarkDirty()
                    end)
                    row:Show()
                else
                    row:Hide()
                end
            end
        end
        w:SetHeight(-top + math.max(1, #list) * 26 + 20)
    end

    local results  -- the suggestion list, made below

    local function AddID(id, text)
        if not id or not SpellName(id) then
            status:SetText(L["No spell found for \""] .. tostring(text or id) .. "\".")
            return
        end
        for _, have in ipairs(settings.customBuffs) do
            if have == id then status:SetText(L["Already on the list."]) return end
        end
        if #settings.customBuffs >= MAX_CUSTOM then
            status:SetText((L["At most %d custom buffs."]):format(MAX_CUSTOM))
            return
        end
        table.insert(settings.customBuffs, id)
        status:SetText("")
        box:SetText("")
        box:ClearFocus()
        if results then results:Hide() end
        Rebuild()
        MarkDirty()
    end

    -- Add or Enter: the first suggestion if there is one, else the text as
    -- an ID or the name of a spell you know.
    local function Add()
        local text = strtrim(box:GetText() or "")
        if text == "" then return end
        if results and results:IsShown() and results.buttons[1] and results.buttons[1]:IsShown() then
            AddID(results.buttons[1].spellID, text)
            return
        end
        local id = tonumber(text)
        if not id and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(text)
            id = info and info.spellID
        end
        AddID(id, text)
    end

    -- The suggestions under the box, from the triggers' spell search: your
    -- spellbook first, then the common buffs other classes give.
    results = CreateFrame("Frame", nil, w, "BackdropTemplate")
    results:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -5, -2)
    results:SetSize(240, 120)
    results:SetFrameStrata("TOOLTIP")
    results:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10 })
    results:SetBackdropColor(0, 0, 0, 0.95)
    results:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    results:Hide()
    results.buttons = {}
    local MAX_RESULTS = 6

    local function Suggest(text)
        local Triggers = OxedHub.Triggers
        local list = (text ~= "" and Triggers and Triggers.SearchPlayerSpells)
            and Triggers:SearchPlayerSpells(text, MAX_RESULTS, true) or {}
        for i = 1, math.max(#list, #results.buttons) do
            local spell = list[i]
            local b = results.buttons[i]
            if spell and not b then
                b = CreateFrame("Button", nil, results)
                b:SetSize(230, 22)
                b:SetPoint("TOPLEFT", results, "TOPLEFT", 5, -5 - (i - 1) * 23)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetSize(16, 16)
                b.icon:SetPoint("LEFT")
                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                b.text:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
                b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                b:SetScript("OnClick", function(self) AddID(self.spellID, self.text:GetText()) end)
                results.buttons[i] = b
            end
            if b then
                if spell then
                    b.spellID = tonumber(spell.id)
                    b.icon:SetTexture(spell.icon or 134400)
                    b.text:SetText(spell.name)
                    b:Show()
                else
                    b:Hide()
                end
            end
        end
        if #list == 0 then results:Hide() return end
        results:SetHeight(#list * 23 + 10)
        results:Show()
    end

    local searchTimer, hideTimer
    box:SetScript("OnTextChanged", function(self, userInput)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(self) end
        if not userInput then return end
        if searchTimer then searchTimer:Cancel() end
        local text = strtrim(self:GetText() or "")
        if text == "" then results:Hide() return end
        searchTimer = C_Timer.NewTimer(0.1, function()
            if strtrim(self:GetText() or "") == text then Suggest(text) end
        end)
    end)
    box:SetScript("OnEscapePressed", function(self) results:Hide() self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function()
        if hideTimer then hideTimer:Cancel() end
    end)
    -- Hidden a moment after the box loses focus, so a click on a suggestion
    -- still lands.
    box:SetScript("OnEditFocusLost", function()
        if searchTimer then searchTimer:Cancel() end
        hideTimer = C_Timer.NewTimer(0.2, function() results:Hide() end)
    end)

    add:SetScript("OnClick", Add)
    box:SetScript("OnEnterPressed", Add)
    w:HookScript("OnShow", Rebuild)
    w:HookScript("OnHide", function() box:ClearFocus() results:Hide() end)
    Rebuild()
    return w
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Buff Reminder", 440, 600)
        local w = optionsWindow
        -- First thing in the window: the list of every buff, by section.
        -- Behind a "Reminders" button at the bottom it was not found.
        local choose = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        choose:SetSize(w:GetWidth() - 40, 28)
        choose:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        choose:SetText(OxedHub.T("Choose your buffs: every buff, by section"))
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(choose) end
        choose:SetScript("OnClick", function()
            ToggleSub("reminders", function() return BuildReminders(API) end)
        end)
        w.cursorY = w.cursorY - 38
        w:AddCheckbox(settings, "showRaid", "Group buff your class gives",
            "Arcane Intellect, Battle Shout, Mark of the Wild and so on, with how many nearby players lack it.", MarkDirty)
        w:AddCheckbox(settings, "showSelf", "Your own buffs",
            "Poisons, shields, weapon imbues, paladin aura, Shadowform, runeforge, and your custom buffs.", MarkDirty)
        w:AddCheckbox(settings, "showTargeted", "Buffs you put on others",
            "Beacons, Earth Shield, Source of Magic, Blistering Scales, Symbiotic Relationship, Soulstone on a ready check. "
            .. "A click casts on whoever had it last.", MarkDirty)
        w:AddCheckbox(settings, "showPets", "Pet: missing, on Passive, or the wrong demon", nil, MarkDirty)
        w:AddCheckbox(settings, "showConsumables", "Consumables: food, flask, rune, oil, healthstone",
            "In instances, every matching item in your bags gets its own icon with its count. Oil is offered per hand. The rune only shows when you carry one. Also: delve food, low durability anywhere, and Soulwell or Refreshment Table on a ready check.", MarkDirty)
        w:AddCheckbox(settings, "expiring", "Also buffs that are running out", nil, MarkDirty)
        w:AddSlider(settings, "expiringMinutes", "Running out means under", 1, 30, 1, "%s %d min", MarkDirty)
        w:AddSlider(settings, "preKeyMinutes", "Before a Mythic+ key starts, under", 0, 60, 5, "%s %d min (0 = off)", MarkDirty)
        w:AddCheckbox(settings, "readyCheck", "Show everything for 30 seconds on a ready check")
        w:AddCheckbox(settings, "readyCheckOnly", "Only on a ready check",
            "The bar stays hidden the rest of the time and shows for 30 seconds when a ready check starts.", MarkDirty)
        w:AddCheckbox(settings, "clickCast", "Click an icon to cast or use it", nil, MarkDirty)
        w:AddCheckbox(settings, "rightSnooze", "Right-click an icon to hide it for a while", nil, MarkDirty)
        w:AddSlider(settings, "snoozeMinutes", "Hidden for", 1, 60, 1, "%s %d min")
        w:AddSoundPicker(settings, "sound", "Sound when something goes missing", "None")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        -- Preview: not saved, and switched off when this window closes.
        local previewToggle = setmetatable({}, {
            __index = function() return previewing end,
            __newindex = function(_, _, value) SetPreview(value) end,
        })
        w:AddCheckbox(previewToggle, "on", "Preview sample icons on screen",
            "Fills the bar with sample icons in every state, to set size, spacing and position. They do nothing when clicked.")
        w:AddSlider(settings, "previewCount", "Sample icons", 1, MAX_BUTTONS, 1, "%s: %d", MarkDirty)

        local _, class = UnitClass("player")
        local items = {
            { OxedHub.T("Choose buffs"), function() ToggleSub("reminders", function() return BuildReminders(API) end) end },
            { "Custom buffs", function() ToggleSub("custom", function() return BuildCustom(API) end) end },
            { "Layout and glow", function() ToggleSub("layout", function() return BuildLayout(API) end) end },
            { "Where it shows", function() ToggleSub("where", function() return BuildWhere(API) end) end },
            { "Talents and gear", function() ToggleSub("loadouts", function() return BuildLoadouts(API) end) end },
            { "Smarter choices", function() ToggleSub("smarter", function() return BuildSmarter(API) end) end },
        }
        if class == "ROGUE" or class == "DEATHKNIGHT" or class == "DRUID" or class == "WARRIOR" or class == "WARLOCK" then
            items[#items + 1] = { "Class choices", function() ToggleSub("class", function() return BuildClass(API, class) end) end }
        end
        AddButtonRow(w, items)
        w:AddNote("The bar hides in combat and is rebuilt when combat ends, so nothing it shows is guessed from hidden combat data.")
        FitHeight(w)
        w:HookScript("OnShow", MarkDirty)
        w:HookScript("OnHide", function()
            for _, sub in pairs(subWindows) do sub:Hide() end
            previewing = false
            MarkDirty()
        end)
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

-- Its own icon on the minimap, like the other modules with a window: a click
-- opens the options.
MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "buffreminder", label = L["Buff Reminder"], icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        config = settings, hint = L["Click: options."],
        onClick = function() ShowOptions() end,
    })
    return minimapIcon
end

-- /oxbuffs why: for each group buff another class gives, the check that keeps
-- its "ask" icon away. Written for a player who reported them missing; every
-- line names one check in the order Collect and EvaluateAsk make them.
local function ExplainAsk()
    local say = function(text) print("|cff00ccffOxedHub Buffs|r " .. text) end
    if not settings then return say("settings not loaded yet.") end
    local inInstance, instanceType = IsInInstance()
    inInstance = inInstance and instanceType ~= "pvp" and instanceType ~= "arena"
    local groupAllowed = not settings.onlyInstances or inInstance
    say(("module on: %s, ask option: %s, in a group: %s, allowed here: %s, in combat: %s"):format(
        tostring(settings.enabled), tostring(settings.askBuffs), tostring(IsInGroup()),
        tostring(groupAllowed), tostring(InCombatLockdown())))
    -- Class and aura reads can be secret in a fight, and comparing one errors.
    if InCombatLockdown() then return say("run it again out of combat.") end
    say(("bar shown: %s, icons now: %d, auras secret now: %s"):format(
        tostring(bar and bar:IsShown()), #Collect(), tostring(AurasSecretNow())))
    local _, class = UnitClass("player")
    for _, entry in ipairs(Data.RAID) do
        if entry.class ~= class then
            local reason
            if settings["ask_" .. entry.key] == false then
                reason = "unticked in Reminders"
            elseif (snoozed[entry.key] or 0) > GetTime() then
                reason = "snoozed"
            elseif AskedRecently(entry.key) then
                reason = "asked for recently"
            elseif not GroupHasClass(entry.class) then
                reason = "no " .. entry.class .. " in the group"
            elseif not Benefits(entry, "player") then
                reason = "does nothing for your spec"
            else
                ForgetUnit("player")
                local found = FindAuraCached("player", entry.auras)
                if found == nil then
                    reason = "the game will not say (secret)"
                elseif found then
                    reason = "already on you"
                else
                    reason = "missing: the icon should show"
                end
            end
            say(("%s (%s): %s"):format(entry.key, entry.class, reason))
        end
    end
end

SLASH_OXEDHUBBUFFS1 = "/oxbuffs"
SlashCmdList.OXEDHUBBUFFS = function(msg)
    msg = strtrim(msg or ""):lower()
    if msg == "why" then return ExplainAsk() end
    ShowOptions()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then SafeStart() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "buffreminder",
        name     = "Buff Reminder",
        version  = "1.8.1",
        updated  = 20261026.5,  -- /oxbuffs why: says why an ask icon is missing
        author   = "Oxed",
        category = "combat",
        keywords = { "buff", "missing", "food", "flask", "rune", "oil", "pet", "poison", "consumables",
            "healthstone", "ready check", "beacon", "earth shield", "soulstone", "stance", "form", "custom",
            "talents", "loadout", "gear set", "ask" },
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Icons for missing buffs, pets and consumables. Click one to cast it.",
        icon     = "Interface\\Icons\\Spell_Holy_MagicalSentry",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.customBuffs) ~= "table" then settings.customBuffs = {} end
            if type(settings.lastTargets) ~= "table" then settings.lastTargets = {} end
            if type(settings.lastUsed) ~= "table" then settings.lastUsed = {} end
            if type(settings.loadouts) ~= "table" then settings.loadouts = {} end
            if type(settings.gearSets) ~= "table" then settings.gearSets = {} end
            for _, content in ipairs(Data.DEMON_CONTENT) do
                if type(settings["demons_" .. content.key]) ~= "table" then settings["demons_" .. content.key] = {} end
            end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            SafeStart()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
            -- The bar cannot be hidden in combat; finish when it ends.
            if InCombatLockdown() then lateStart:RegisterEvent("PLAYER_REGEN_ENABLED") end
        end,
    })
end)
