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
--   * Flask and rune icons find a matching item in your bags by its use
--     effect, so new expansions' items work without an item list.
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
    largeIcons    = false,
    locked        = true,   -- unlocked: drag the bar, a sample icon marks it
    shiftDrag     = true,   -- Shift+drag moves the bar even while it is locked
    point = "CENTER", x = 0, y = 180,
}

local EXPIRING_SECONDS = 300
local READY_CHECK_SECONDS = 30
local REFRESH_DELAY = 0.3     -- events arrive in bursts; one rebuild per burst
local TICK = 10               -- range and time-left change without events
local MAX_BUTTONS = 12

local Data = OxedHub.BuffReminderData
local settings
local optionsWindow
local watcher = CreateFrame("Frame")

local bar, buttons = nil, {}
local pending, ticker = false, nil
local readyCheckUntil = 0
local itemSpellCache = {}     -- itemID -> spellID of its use effect, or false

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

-- Well Fed has dozens of spell IDs; the food icon is the one thing they share.
local FOOD_ICON = 136000
local function FindFood()
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or IsSecret(aura) then return nil end
        if not aura then break end
        local icon = aura.icon
        if not IsSecret(icon) and icon == FOOD_ICON then
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

local function ItemUseSpell(itemID)
    local cached = itemSpellCache[itemID]
    if cached ~= nil then return cached end
    local getSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not getSpell then return false end
    local _, spellID = getSpell(itemID)
    if not spellID then
        -- No use effect is remembered only once the item is loaded; before
        -- that the answer may simply not have arrived yet.
        if C_Item and C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(itemID) then
            itemSpellCache[itemID] = false
        end
        return false
    end
    itemSpellCache[itemID] = spellID
    return spellID
end

-- The first item in the bags whose use effect is one of `auras`.
local function FindItemFor(auras)
    if not (C_Container and C_Container.GetContainerNumSlots) then return nil end
    local wanted = {}
    for _, id in ipairs(auras) do wanted[id] = true end
    for bag = 0, 5 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local itemID = C_Container.GetContainerItemID(bag, slot)
            if itemID then
                local spellID = ItemUseSpell(itemID)
                if spellID and wanted[spellID] then return itemID end
            end
        end
    end
    return nil
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
    if entry.notAura and FindAura("player", { entry.notAura }) then return false end
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

-- Returns a reminder record, or nil when nothing needs doing.
-- Record: { entry, texture, count, timeLeft, names, spell, item }
local function Evaluate(entry, inInstance, forced)
    local wantExpiring = settings.expiring
    local found, left

    if entry.group == "raid" then
        local missing, names = 0, nil
        local soonest
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
            return { entry = entry, texture = SpellTexture(spell), count = missing, names = names, spell = spell }
        end
        if wantExpiring and soonest and soonest < EXPIRING_SECONDS then
            return { entry = entry, texture = SpellTexture(spell), timeLeft = soonest, spell = spell }
        end
        return nil
    end

    if entry.check == "pet" then
        if UnitExists("pet") and not UnitIsDead("pet") then return nil end
        local spell = CastSpellFor(entry)
        return { entry = entry, texture = SpellTexture(spell), spell = spell }
    end

    if entry.group == "consumable" then
        if not inInstance and not forced then return nil end
        local item
        if entry.check == "food" then
            found, left = FindFood()
        elseif entry.check == "oil" then
            local _, class = UnitClass("player")
            if Data.NO_OIL_CLASS[class] then return nil end
            if not GetInventoryItemID("player", 16) then return nil end
            found, left = WeaponEnchants(nil)
        else
            found, left = FindAura("player", entry.auras)
            if found == false or (found and left and left < EXPIRING_SECONDS) then
                item = FindItemFor(entry.auras)
                -- A rune you do not carry is not worth a reminder.
                if entry.check == "rune" and not item then return nil end
            end
        end
        if found == nil then return nil end
        local texture
        if entry.icon then texture = entry.icon
        elseif entry.check == "oil" then texture = GetInventoryItemTexture("player", 16)
        elseif item then texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item)
        end
        texture = texture or SpellTexture(entry.auras and entry.auras[#entry.auras] or 0)
        if found == false then
            return { entry = entry, texture = texture, item = item }
        end
        if wantExpiring and left and left < EXPIRING_SECONDS then
            return { entry = entry, texture = texture, timeLeft = left, item = item }
        end
        return nil
    end

    -- Self buffs
    if entry.form then
        found = GetShapeshiftForm and GetShapeshiftForm() > 0
    elseif entry.enchants and entry.permanent then
        found = PermanentEnchant(entry.enchants)
    elseif entry.enchants then
        found, left = WeaponEnchants(entry.enchants)
    else
        found, left = FindAura("player", entry.auras)
    end
    if found == nil then return nil end
    local spell = CastSpellFor(entry)
    if not found then
        return { entry = entry, texture = SpellTexture(spell), spell = spell }
    end
    if wantExpiring and left and left < EXPIRING_SECONDS then
        return { entry = entry, texture = SpellTexture(spell), timeLeft = left, spell = spell }
    end
    return nil
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
                local record = Evaluate(entry, inInstance, forced)
                if record then list[#list + 1] = record end
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
    GameTooltip:SetText(Data.LABELS[key] or key)
    if record.count then
        GameTooltip:AddLine(("%d nearby missing it"):format(record.count), 1, 0.4, 0.4)
        if record.names then
            GameTooltip:AddLine(table.concat(record.names, ", "), 1, 1, 1, true)
        end
    elseif record.timeLeft then
        GameTooltip:AddLine(("Runs out in %s"):format(FormatLeft(record.timeLeft)), 1, 0.82, 0)
    else
        GameTooltip:AddLine("Missing", 1, 0.4, 0.4)
    end
    if settings.clickCast and (record.spell or record.item) then
        GameTooltip:AddLine("Click to " .. (record.item and "use it" or "cast it"), 0.5, 1, 0.5)
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

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetDrawLayer("BACKGROUND")
    button.border:SetColorTexture(0, 0, 0, 0.9)

    button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -2, 2)

    button.timer = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.timer:SetPoint("TOP", button, "BOTTOM", 0, -1)

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

-- Out of combat only: shows, hides and re-targets secure buttons.
local function Render(list)
    if InCombatLockdown() then return end
    local size = settings.largeIcons and 44 or 34
    local gap = 6

    -- A sample icon marks the bar while it is unlocked or Options is open,
    -- so the player can see where reminders will appear.
    local optionsOpen = optionsWindow and optionsWindow:IsShown()
    if #list == 0 and (not settings.locked or optionsOpen) then
        list = { { sample = true, texture = 136243 } }
    end

    local count = #list
    bar:SetSize(math.max(size, count * size + (count - 1) * gap), size)

    for i = 1, MAX_BUTTONS do
        local record = list[i]
        local button = buttons[i] or (record and CreateButton(i))
        if button then
            if record then
                button:SetSize(size, size)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * (size + gap), 0)
                button.record = not record.sample and record or nil
                button.icon:SetTexture(record.texture or 134400)
                button.icon:SetDesaturated(record.timeLeft ~= nil)
                button.count:SetText(record.count and record.count > 0 and IsInGroup() and record.count or "")
                button.timer:SetText(record.timeLeft and FormatLeft(record.timeLeft) or "")

                local clickable = settings.clickCast and not record.sample
                if clickable and record.item then
                    button:SetAttribute("type", "item")
                    button:SetAttribute("item", "item:" .. record.item)
                    button:SetAttribute("spell", nil)
                elseif clickable and record.spell then
                    button:SetAttribute("type", "spell")
                    button:SetAttribute("spell", record.spell)
                    button:SetAttribute("unit", "player")
                    button:SetAttribute("item", nil)
                else
                    button:SetAttribute("type", nil)
                end
                button:Show()
            else
                button.record = nil
                button:SetAttribute("type", nil)
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

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Buff Reminder", 440, 500)
        local w = optionsWindow
        w:AddCheckbox(settings, "showRaid", "Group buff your class gives",
            "Arcane Intellect, Battle Shout, Mark of the Wild and so on, with how many nearby players lack it.", MarkDirty)
        w:AddCheckbox(settings, "showSelf", "Your own buffs",
            "Poisons, elemental shields, weapon imbues, paladin aura, Shadowform, runeforge.", MarkDirty)
        w:AddCheckbox(settings, "showPets", "Missing pet", nil, MarkDirty)
        w:AddCheckbox(settings, "showConsumables", "Food, flask, rune and weapon oil in instances",
            "The rune only shows when you carry one.", MarkDirty)
        w:AddCheckbox(settings, "expiring", "Also buffs with under five minutes left", nil, MarkDirty)
        w:AddCheckbox(settings, "onlyInstances", "Group and own buffs only inside instances", nil, MarkDirty)
        w:AddCheckbox(settings, "hideResting", "Hide in cities and inns", nil, MarkDirty)
        w:AddCheckbox(settings, "hideMounted", "Hide while mounted", nil, MarkDirty)
        w:AddCheckbox(settings, "readyCheck", "Show everything for 30 seconds on a ready check")
        w:AddCheckbox(settings, "clickCast", "Click an icon to cast or use it", nil, MarkDirty)
        w:AddCheckbox(settings, "largeIcons", "Large icons", nil, MarkDirty)
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
        version  = "1.0.0",
        author   = "Oxed",
        category = "combat",
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
