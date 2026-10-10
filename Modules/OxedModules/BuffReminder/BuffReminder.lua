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
}

local function ExpiringSeconds()
    return (tonumber(settings and settings.expiringMinutes) or 5) * 60
end
local READY_CHECK_SECONDS = 30
local REFRESH_DELAY = 0.3     -- events arrive in bursts; one rebuild per burst
local TICK = 10               -- range and time-left change without events
local MAX_BUTTONS = 30

local Data = OxedHub.BuffReminderData
local settings
local optionsWindow
local watcher = CreateFrame("Frame")

local bar, buttons = nil, {}
local pending, ticker = false, nil
local readyCheckUntil = 0
local snoozed = {}            -- entry key -> GetTime() until which it stays hidden
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

local function FindFood()
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

-- ── Items in the bags ───────────────────────────────────────────────────────

local function ItemCount(itemID)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
    return GetItemCount and GetItemCount(itemID) or 0
end

local function ItemIcon(itemID)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
    return GetItemIcon and GetItemIcon(itemID)
end

-- One record per item of this kind in the bags, best first, at most
-- ITEMS_PER_KIND of them.
local function CarriedItems(kind)
    local found = {}
    for _, info in ipairs(Data.ITEMS[kind] or {}) do
        local count = ItemCount(info.id)
        if count > 0 then
            found[#found + 1] = {
                item = info.id, stack = count, label = info.label, badge = info.badge,
                texture = ItemIcon(info.id),
            }
            if #found >= Data.ITEMS_PER_KIND then break end
        end
    end
    return found
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

local function EvaluateRaid(entry, out)
    local missing, names, soonest = 0, nil, nil
    local units, count = GroupUnits()
    for i = 1, count do
        local unit = units[i]
        if Countable(unit) then
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
        Add(out, entry, { texture = SpellTexture(spell), count = missing, names = names, spell = spell })
    elseif settings.expiring and soonest and soonest < ExpiringSeconds() then
        Add(out, entry, { texture = SpellTexture(spell), timeLeft = soonest, spell = spell })
    end
end

local function SpellRecord(spellID, name)
    return { texture = SpellTexture(spellID), spell = spellID, name = name }
end

-- Missing pet: one icon per pet you can call, so the right one is one click.
local function EvaluatePet(entry, specID, out)
    if UnitExists("pet") and not UnitIsDead("pet") then return end
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
                    Add(out, entry, SpellRecord(spellID, Data.DEMON_NAMES[spellID]))
                end
            end
            if #out > before then return end
        end
    end

    local spell = CastSpellFor(entry)
    Add(out, entry, SpellRecord(spell))
end

-- Food, flask, rune: the aura is checked, and when it is missing every
-- matching item carried gets its own icon.
local function EvaluateBuffItem(entry, out)
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
        if entry.check == "rune" then return end
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
                Add(out, entry, { texture = GetInventoryItemTexture("player", hand.slot), label = hand.tag, timeLeft = timeLeft })
            else
                for _, info in ipairs(items) do
                    Add(out, entry, {
                        texture = info.texture, item = info.item, stack = info.stack, label = hand.tag,
                        timeLeft = timeLeft, slot = hand.slot,
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
    for _, id in ipairs(Data.HEALTHSTONES) do total = total + ItemCount(id) end
    if total > 0 then return end
    local record = { texture = ItemIcon(Data.HEALTHSTONES[1]), stack = 0 }
    if class == "WARLOCK" then
        if IsInGroup() and Known(Data.CREATE_SOULWELL) then
            record.spell = Data.CREATE_SOULWELL
        elseif Known(Data.CREATE_HEALTHSTONE) then
            record.spell = Data.CREATE_HEALTHSTONE
        end
    end
    Add(out, entry, record)
end

local REPAIR_ICON = "Interface\\Icons\\Trade_BlackSmithing"
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
    if worst and worst < Data.REPAIR_BELOW then
        Add(out, entry, { texture = REPAIR_ICON, label = ("%d%%"):format(worst) })
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

local function InDelve()
    local _, _, difficultyID = GetInstanceInfo()
    return difficultyID == 208
end

local function EvaluateMageFood(entry, out)
    local index = GetSpecialization and GetSpecialization()
    local role = index and GetSpecializationRole and GetSpecializationRole(index)
    if role ~= "HEALER" or not IsInGroup() or not GroupHasClass("MAGE") then return end
    if ItemCount(entry.item) > 0 then return end
    Add(out, entry, { texture = entry.icon, stack = 0 })
end

local function Evaluate(entry, specID, inInstance, forced, out)
    if entry.group == "raid" then return EvaluateRaid(entry, out) end
    if entry.group == "targeted" then return EvaluateTargeted(entry, out) end
    if entry.check == "pet" then return EvaluatePet(entry, specID, out) end
    if entry.check == "felguard" then return EvaluateFelguard(entry, out) end
    if entry.check == "passive" then return EvaluatePassive(entry, out) end
    if entry.check == "poison" then return EvaluatePoison(entry, out) end
    if entry.check == "runeforge" then return EvaluateRuneforge(entry, specID, out) end
    if entry.check == "druidForm" then return EvaluateDruidForm(entry, specID, out) end
    if entry.check == "stance" then return EvaluateStance(entry, specID, out) end
    if entry.check == "delveFood" then
        if not InDelve() then return end
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

    Run(Data.RAID, settings.showRaid, true)
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
    if entry.custom then return SpellName(entry.cast) or ("Spell " .. entry.cast) end
    return Data.LABELS[entry.key] or entry.key
end

local function ShowTooltip(button)
    local record = button.record
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if not record then
        GameTooltip:SetText("Buff Reminder")
        GameTooltip:AddLine("Nothing is missing right now. Reminders appear here. Shift+drag to move it.", 1, 1, 1, true)
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
        GameTooltip:AddLine(("%d nearby missing it"):format(record.count), 1, 0.4, 0.4)
        if record.names then
            GameTooltip:AddLine(table.concat(record.names, ", "), 1, 1, 1, true)
        end
    elseif record.timeLeft then
        GameTooltip:AddLine(("Runs out in %s"):format(FormatLeft(record.timeLeft)), 1, 0.82, 0)
    elseif record.stack == 0 then
        GameTooltip:AddLine("None in your bags", 1, 0.4, 0.4)
    end
    if record.wrong then
        GameTooltip:AddLine("Wanted: " .. record.wrong, 1, 0.4, 0.4)
    end
    if record.slot then
        GameTooltip:AddLine(record.slot == 16 and "For your main hand" or "For your off hand", 1, 1, 1)
    end
    if record.entry.group == "targeted" then
        local last = settings.lastTargets[record.entry.key]
        if last then GameTooltip:AddLine("Casts on " .. last .. " (it was on them last)", 1, 1, 1) end
    end
    if settings.clickCast and (record.spell or record.item or record.macro) and not record.entry.noClick then
        GameTooltip:AddLine("Click to " .. ((record.item or (record.macro and not record.spell)) and "use it" or "cast it"), 0.5, 1, 0.5)
    end
    if settings.rightSnooze then
        GameTooltip:AddLine(("Right-click: hide it for %d minutes"):format(settings.snoozeMinutes or 10), 0.7, 0.7, 0.7)
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

    CreateGlow(button)

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Right-click hides the reminder for a while. The secure actions are set
    -- for the left button only, so the right one never casts.
    button:SetScript("PostClick", function(self, mouse, down)
        if mouse ~= "RightButton" or down or not settings.rightSnooze then return end
        local record = self.record
        if not record or InCombatLockdown() then return end
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
    for _, key in ipairs(ACTION_KEYS) do button:SetAttribute(key, nil) end
    if not settings.clickCast or not record or record.sample or record.entry.noClick then return end
    if record.macro then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", record.macro)
    elseif record.item then
        button:SetAttribute("type1", "item")
        button:SetAttribute("item1", "item:" .. record.item)
    elseif record.spell then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell1", record.spell)
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

-- Out of combat only: shows, hides and re-targets secure buttons.
local function Render(list)
    if InCombatLockdown() then return end
    local size = IconSize()
    local gap = tonumber(settings.spacing) or 6
    local perRow = math.max(1, tonumber(settings.perRow) or 10)
    local rowHeight = size + 16   -- room for the name / time under each icon

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
                button.label:SetText(record.label or "")
                button.badge:SetText(record.badge or "")

                local number = ""
                if record.count and record.count > 0 and IsInGroup() then number = record.count
                elseif record.stack then number = record.stack end
                button.count:SetText(number)

                if record.timeLeft then
                    button.under:SetText(FormatLeft(record.timeLeft))
                else
                    local name = record.name
                    if not name and settings.showNames and not record.sample then
                        name = record.item and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(record.item)
                        name = name or LabelOf(record.entry)
                    end
                    button.under:SetText(name or "")
                end

                if record.sample then
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

local function IsGroupUnit(unit)
    return type(unit) == "string" and (unit:find("^party") or unit:find("^raid")) ~= nil
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    "UNIT_AURA", "UNIT_PET", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "ZONE_CHANGED_NEW_AREA", "READY_CHECK", "BAG_UPDATE_DELAYED", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "UPDATE_INVENTORY_DURABILITY", "PET_STABLE_UPDATE", "PET_BAR_UPDATE", "PLAYER_LEVEL_UP",
}

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        -- Nameplates, the target and the rest: not ours to track, dropped
        -- before anything else (this event arrives a million times a session).
        local own = unit == "player" or unit == "pet"
        if not own and not IsGroupUnit(unit) then return end
        -- Forgotten even in combat, so the answer after the fight is fresh;
        -- the bar itself is hidden in combat and is not rebuilt then.
        ForgetUnit(unit)
        if InCombatLockdown() then return end
        if not own then
            MarkGroupDirty()
            return
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        -- raid3 may be somebody else now.
        ForgetAllUnits()
    elseif event == "READY_CHECK" then
        if settings.readyCheck then
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
    h:SetText(text)
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
    if w:IsShown() then w:Hide() else w:Show() end
end

local function FitHeight(w)
    w:SetHeight(math.max(120, -w.cursorY + 16))
end

-- Every reminder that can apply to your class, each with its own box.
local function BuildReminders(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Reminders", 380, 400)
    local _, class = UnitClass("player")
    -- A tick means "remind me"; stored as hide_<key>, opt-in ones off until ticked.
    local byKey = {}
    local proxy = setmetatable({}, {
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
    local parts = {
        { "raid", Data.RAID }, { "self", Data.SELF }, { "targeted", Data.TARGETED },
        { "pet", Data.PET }, { "consumable", Data.CONSUMABLE },
    }
    for _, part in ipairs(parts) do
        local any = false
        for _, entry in ipairs(part[2]) do
            if not entry.class or entry.class == class then
                if not any then
                    Heading(w, Data.GROUP_TITLES[part[1]])
                    any = true
                end
                byKey[entry.key] = entry
                w:AddCheckbox(proxy, entry.key, Data.LABELS[entry.key] or entry.key,
                    entry.optIn and "Off until you tick it." or nil)
            end
        end
    end
    FitHeight(w)
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
    Heading(w, "Show the bar in")
    w:AddCheckbox(settings, "where_openWorld", "The open world", nil, MarkDirty)
    w:AddCheckbox(settings, "where_dungeon", "Dungeons", nil, MarkDirty)
    w:AddCheckbox(settings, "where_raid", "Raids", nil, MarkDirty)
    w:AddCheckbox(settings, "where_delve", "Delves", nil, MarkDirty)
    w:AddCheckbox(settings, "where_scenario", "Other scenarios", nil, MarkDirty)
    w:AddCheckbox(settings, "where_pvp", "Battlegrounds and arenas", nil, MarkDirty)
    Heading(w, "And hide it")
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
        choices[#choices + 1] = { value = id, text = SpellName(id) or ("Spell " .. id) }
    end
    return choices
end

local function BuildClass(API, class)
    local w = API:CreateOptionsWindow("Buff Reminder: Class choices", 440, 300)
    if class == "ROGUE" then
        Heading(w, "Poisons a click applies")
        w:AddChoice(settings, "prefLethal", "Lethal", SpellChoices(Data.LETHAL_POISONS, "Best you know"), MarkDirty)
        w:AddChoice(settings, "prefNonLethal", "Non-lethal", SpellChoices(Data.NONLETHAL_POISONS, "Best you know"), MarkDirty)
        w:AddNote("With Dragon-Tempered Blades two of each kind are needed; the icon shows how many are on.")
    elseif class == "DEATHKNIGHT" then
        Heading(w, "Rune each spec should have")
        local choices = { { value = 0, text = "Any rune" } }
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
    end
    FitHeight(w)
    return w
end

-- Custom buffs: any spell, by ID or by the name of one you know. Shown when
-- it is not on you; a click casts it when you know it.
local MAX_CUSTOM = 12

local function BuildCustom(API)
    local w = API:CreateOptionsWindow("Buff Reminder: Custom buffs", 400, 200)
    w:AddNote("Type a spell ID, or the name of a spell you know, and press Add. "
        .. "It shows when that buff is not on you.")

    -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard at once.
    local box = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetSize(220, 22)
    box:SetPoint("TOPLEFT", w, "TOPLEFT", 26, w.cursorY - 4)
    box:SetScript("OnEscapePressed", box.ClearFocus)

    local add = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    add:SetSize(80, 22)
    add:SetPoint("LEFT", box, "RIGHT", 10, 0)
    add:SetText("Add")

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
                row.remove:SetText("Remove")
                rows[i] = row
            end
            if row then
                if id then
                    row.icon:SetTexture(SpellTexture(id) or 134400)
                    row.text:SetText(("%s  |cff888888%d|r"):format(SpellName(id) or "Unknown spell", id))
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

    local function Add()
        local text = strtrim(box:GetText() or "")
        if text == "" then return end
        local id = tonumber(text)
        if not id and C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(text)
            id = info and info.spellID
        end
        if not id or not SpellName(id) then
            status:SetText("No spell found for \"" .. text .. "\".")
            return
        end
        for _, have in ipairs(settings.customBuffs) do
            if have == id then status:SetText("Already on the list.") return end
        end
        if #settings.customBuffs >= MAX_CUSTOM then
            status:SetText(("At most %d custom buffs."):format(MAX_CUSTOM))
            return
        end
        table.insert(settings.customBuffs, id)
        status:SetText("")
        box:SetText("")
        box:ClearFocus()
        Rebuild()
        MarkDirty()
    end
    add:SetScript("OnClick", Add)
    box:SetScript("OnEnterPressed", Add)
    w:HookScript("OnShow", Rebuild)
    w:HookScript("OnHide", function() box:ClearFocus() end)
    Rebuild()
    return w
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Buff Reminder", 440, 600)
        local w = optionsWindow
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
        w:AddCheckbox(settings, "readyCheck", "Show everything for 30 seconds on a ready check")
        w:AddCheckbox(settings, "clickCast", "Click an icon to cast or use it", nil, MarkDirty)
        w:AddCheckbox(settings, "rightSnooze", "Right-click an icon to hide it for a while", nil, MarkDirty)
        w:AddSlider(settings, "snoozeMinutes", "Hidden for", 1, 60, 1, "%s %d min")
        w:AddSoundPicker(settings, "sound", "Sound when something goes missing", "None")

        local _, class = UnitClass("player")
        local items = {
            { "Reminders", function() ToggleSub("reminders", function() return BuildReminders(API) end) end },
            { "Custom buffs", function() ToggleSub("custom", function() return BuildCustom(API) end) end },
            { "Layout and glow", function() ToggleSub("layout", function() return BuildLayout(API) end) end },
            { "Where it shows", function() ToggleSub("where", function() return BuildWhere(API) end) end },
        }
        if class == "ROGUE" or class == "DEATHKNIGHT" or class == "DRUID" or class == "WARRIOR" then
            items[#items + 1] = { "Class choices", function() ToggleSub("class", function() return BuildClass(API, class) end) end }
        end
        AddButtonRow(w, items)
        w:AddNote("The bar hides in combat and is rebuilt when combat ends, so nothing it shows is guessed from hidden combat data.")
        FitHeight(w)
        w:HookScript("OnShow", MarkDirty)
        w:HookScript("OnHide", function()
            for _, sub in pairs(subWindows) do sub:Hide() end
            MarkDirty()
        end)
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

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
        version  = "1.3.0",
        author   = "Oxed",
        category = "combat",
        keywords = { "buff", "missing", "food", "flask", "rune", "oil", "pet", "poison", "consumables",
            "healthstone", "ready check", "beacon", "earth shield", "soulstone", "stance", "form", "custom" },
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Icons for missing buffs, pets and consumables. Click one to cast it.",
        icon     = "Interface\\Icons\\Spell_Holy_MagicalSentry",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.customBuffs) ~= "table" then settings.customBuffs = {} end
            if type(settings.lastTargets) ~= "table" then settings.lastTargets = {} end
            SafeStart()
        end,

        OnDisable = function()
            Stop()
            -- The bar cannot be hidden in combat; finish when it ends.
            if InCombatLockdown() then lateStart:RegisterEvent("PLAYER_REGEN_ENABLED") end
        end,
    })
end)
