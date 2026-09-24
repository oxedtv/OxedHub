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
}

local EXPIRING_SECONDS = 300
local READY_CHECK_SECONDS = 30
local REFRESH_DELAY = 0.3     -- events arrive in bursts; one rebuild per burst
local TICK = 10               -- range and time-left change without events
local MAX_BUTTONS = 30
local PER_ROW = 10            -- icons wrap onto a new row after this many

local Data = OxedHub.BuffReminderData
local settings
local optionsWindow
local watcher = CreateFrame("Frame")

local bar, buttons = nil, {}
local pending, ticker = false, nil
local readyCheckUntil = 0

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
local function PermanentEnchant(ids)
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

local function ForEachGroupUnit(fn)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do fn("raid" .. i) end
    else
        fn("player")
        for i = 1, GetNumSubgroupMembers() do fn("party" .. i) end
    end
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
    local present = false
    ForEachGroupUnit(function(unit)
        if present or not UnitExists(unit) then return end
        local _, class = UnitClass(unit)
        if class == wanted then present = true end
    end)
    return present
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
        if FindAura("player", entry._notAuraList) then return false end
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
    return found and settings.expiring and left and left < EXPIRING_SECONDS or false
end

local function EvaluateRaid(entry, out)
    local missing, names, soonest = 0, nil, nil
    ForEachGroupUnit(function(unit)
        if not Countable(unit) then return end
        local has, remaining = FindAura(unit, entry.auras)
        if has == false then
            missing = missing + 1
            names = names or {}
            names[#names + 1] = UnitName(unit)
        elseif has and remaining and (not soonest or remaining < soonest) then
            soonest = remaining
        end
    end)
    local spell = CastSpellFor(entry)
    if missing > 0 then
        Add(out, entry, { texture = SpellTexture(spell), count = missing, names = names, spell = spell })
    elseif settings.expiring and soonest and soonest < EXPIRING_SECONDS then
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
        found, left = FindAura("player", entry.auras)
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

local function Evaluate(entry, specID, inInstance, forced, out)
    if entry.group == "raid" then return EvaluateRaid(entry, out) end
    if entry.check == "pet" then return EvaluatePet(entry, specID, out) end

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
        found, left = FindAura("player", entry.auras)
    end
    if not Needed(found, left) then return end
    local spell = CastSpellFor(entry)
    Add(out, entry, { texture = SpellTexture(spell), spell = spell, timeLeft = found and left or nil })
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
    end
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then return list end

    local _, class = UnitClass("player")
    local specID = CurrentSpecID()
    local groupAllowed = forced or not settings.onlyInstances or inInstance

    local function Run(entries, enabled, needsPlace)
        if not enabled or (needsPlace and not groupAllowed) then return end
        for _, entry in ipairs(entries) do
            if #list >= MAX_BUTTONS then return end
            if settings["hide_" .. entry.key] ~= true and Applies(entry, class, specID) then
                Evaluate(entry, specID, inInstance, forced, list)
            end
        end
    end

    Run(Data.RAID, settings.showRaid, true)
    Run(Data.SELF, settings.showSelf, true)
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

local function ShowTooltip(button)
    local record = button.record
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    if not record then
        GameTooltip:SetText("Buff Reminder")
        GameTooltip:AddLine("Nothing is missing right now. Reminders appear here. Shift+drag to move it.", 1, 1, 1, true)
        GameTooltip:Show()
        return
    end
    local key = record.entry.key
    if record.item then
        GameTooltip:SetItemByID(record.item)
    elseif record.spell then
        GameTooltip:SetSpellByID(record.spell)
    else
        GameTooltip:SetText(Data.LABELS[key] or key)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Buff Reminder: " .. (Data.LABELS[key] or key), 0.6, 0.8, 1)
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
    if record.slot then
        GameTooltip:AddLine(record.slot == 16 and "For your main hand" or "For your off hand", 1, 1, 1)
    end
    if settings.clickCast and (record.spell or record.item or record.macro) then
        GameTooltip:AddLine("Click to " .. ((record.item or record.macro) and "use it" or "cast it"), 0.5, 1, 0.5)
    end
    GameTooltip:Show()
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

    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

local function SetAction(button, record)
    button:SetAttribute("type", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macrotext", nil)
    if not settings.clickCast or not record or record.sample then return end
    if record.macro then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", record.macro)
    elseif record.item then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. record.item)
    elseif record.spell then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", record.spell)
        button:SetAttribute("unit", "player")
    end
end

-- Out of combat only: shows, hides and re-targets secure buttons.
local function Render(list)
    if InCombatLockdown() then return end
    local size = IconSize()
    local gap = 6
    local rowHeight = size + 16   -- room for the name / time under each icon

    -- A sample icon marks the bar while it is unlocked or Options is open,
    -- so the player can see where reminders will appear.
    local optionsOpen = optionsWindow and optionsWindow:IsShown()
    if #list == 0 and (not settings.locked or optionsOpen) then
        list = { { sample = true, texture = 136243 } }
    end

    local count = math.min(#list, MAX_BUTTONS)
    local columns = math.max(1, math.min(count, PER_ROW))
    local rows = math.max(1, math.ceil(count / PER_ROW))
    bar:SetSize(columns * size + (columns - 1) * gap, rows * rowHeight)

    for i = 1, MAX_BUTTONS do
        local record = list[i]
        local button = buttons[i] or (record and CreateButton(i))
        if button then
            if record then
                local column = (i - 1) % PER_ROW
                local row = math.floor((i - 1) / PER_ROW)
                button:SetSize(size, size)
                button.under:SetWidth(size + 18)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", bar, "TOPLEFT", column * (size + gap), -row * rowHeight)
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
                        name = name or Data.LABELS[record.entry.key]
                    end
                    button.under:SetText(name or "")
                end

                SetAction(button, record)
                button:Show()
            else
                button.record = nil
                SetAction(button, nil)
                button:Hide()
            end
        end
    end
end

local function Refresh()
    pending = false
    if not settings or settings.enabled ~= true or not bar then return end
    if InCombatLockdown() then return end
    -- While the game keeps auras secret, keep the bar as it was.
    if AurasSecretNow() then return end
    Render(Collect())
end

local function MarkDirty()
    if pending then return end
    pending = true
    C_Timer.After(REFRESH_DELAY, Refresh)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
    "UNIT_AURA", "UNIT_PET", "UNIT_INVENTORY_CHANGED", "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "PLAYER_UPDATE_RESTING",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE",
    "ZONE_CHANGED_NEW_AREA", "READY_CHECK", "BAG_UPDATE_DELAYED", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "UPDATE_INVENTORY_DURABILITY", "PET_STABLE_UPDATE",
}

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        -- Auras change constantly in combat; the bar is hidden then anyway.
        if InCombatLockdown() then return end
        if unit ~= "player" and unit ~= "pet" and not (unit and (unit:find("^party") or unit:find("^raid"))) then
            return
        end
    elseif event == "READY_CHECK" then
        if settings.readyCheck then
            readyCheckUntil = GetTime() + READY_CHECK_SECONDS
            C_Timer.After(READY_CHECK_SECONDS + 0.5, MarkDirty)
        end
    elseif event == "BAG_UPDATE_DELAYED" and InCombatLockdown() then
        return
    end
    MarkDirty()
end)

local function Start()
    EnsureBar()
    PlaceBar()
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
    settings = config
end

-- The options window only offers tick boxes, so the size slider is built
-- here: a plain Slider with no template (template names move between builds).
local function AddSizeSlider(w)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(260, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 24, w.cursorY - 24)
    slider:SetMinMaxValues(MIN_SIZE, MAX_SIZE)
    slider:SetValueStep(2)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(0.35, 0.35, 0.35, 0.9)

    local function Show(value) label:SetText(("Icon size: %d"):format(value)) end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        Show(value)
        if value ~= IconSize() then
            settings.iconSize = value
            MarkDirty()
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * 2)
    end)
    w:HookScript("OnShow", function()
        local size = IconSize()
        slider:SetValue(size)
        Show(size)
    end)
    w.cursorY = w.cursorY - 50
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Buff Reminder", 440, 580)
        local w = optionsWindow
        w:AddCheckbox(settings, "showRaid", "Group buff your class gives",
            "Arcane Intellect, Battle Shout, Mark of the Wild and so on, with how many nearby players lack it.", MarkDirty)
        w:AddCheckbox(settings, "showSelf", "Your own buffs",
            "Poisons, elemental shields, weapon imbues, paladin aura, Shadowform, runeforge.", MarkDirty)
        w:AddCheckbox(settings, "showPets", "Missing pet", nil, MarkDirty)
        w:AddCheckbox(settings, "showConsumables", "Consumables: food, flask, rune, oil, healthstone",
            "In instances, every matching item in your bags gets its own icon with its count. Oil is offered per hand. The rune only shows when you carry one. Also: low durability anywhere, and Soulwell or Refreshment Table on a ready check.", MarkDirty)
        w:AddCheckbox(settings, "expiring", "Also buffs with under five minutes left", nil, MarkDirty)
        w:AddCheckbox(settings, "onlyInstances", "Group and own buffs only inside instances", nil, MarkDirty)
        w:AddCheckbox(settings, "hideResting", "Hide in cities and inns", nil, MarkDirty)
        w:AddCheckbox(settings, "hideMounted", "Hide while mounted", nil, MarkDirty)
        w:AddCheckbox(settings, "readyCheck", "Show everything for 30 seconds on a ready check")
        w:AddCheckbox(settings, "clickCast", "Click an icon to cast or use it", nil, MarkDirty)
        w:AddCheckbox(settings, "showNames", "Show names under the icons", nil, MarkDirty)
        AddSizeSlider(w)
        w:AddCheckbox(settings, "locked", "Lock the bar",
            "Untick to drag the bar; a sample icon marks it while nothing is missing.", MarkDirty)
        w:AddCheckbox(settings, "shiftDrag", "Shift+drag moves the locked bar")
        w:AddNote("The bar hides in combat and is rebuilt when combat ends, so nothing it shows is guessed from hidden combat data.")
        w:HookScript("OnShow", MarkDirty)
        w:HookScript("OnHide", MarkDirty)
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
        version  = "1.2.0",
        author   = "Oxed",
        category = "combat",
        keywords = { "buff", "missing", "food", "flask", "rune", "oil", "pet", "poison", "consumables", "healthstone", "ready check" },
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Icons for missing buffs, pets and consumables. Click one to cast it.",
        icon     = "Interface\\Icons\\Spell_Holy_MagicalSentry",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            SafeStart()
        end,

        OnDisable = function()
            Stop()
            -- The bar cannot be hidden in combat; finish when it ends.
            if InCombatLockdown() then lateStart:RegisterEvent("PLAYER_REGEN_ENABLED") end
        end,
    })
end)
