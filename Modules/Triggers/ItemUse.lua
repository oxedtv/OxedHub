local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer

-- ── Potion and Trinket triggers ──────────────────────────────────────────────
-- React when you drink a potion, or when a trinket goes off.
--
-- Both work the same way underneath. Using an item casts a spell, and that cast
-- is what the game announces; there is no "item used" event to listen to. So
-- the rule stores an item, and at fire time the item is resolved to the spell
-- it casts and compared against what was actually cast.
--
-- Resolved at fire time rather than stored: a trinket's spell changes when the
-- item is upgraded, and a stored spell id would quietly stop matching.
--
-- Leaving the item unset means "any of them", which is the useful default here
-- and is safe: unlike a bare spell-cast rule, these only ever see casts that
-- came from a potion or a trinket in the first place.

local TRINKET_SLOTS = { 13, 14 }

-- The spell an item casts, or nil for an item with no use effect.
local function ItemSpellID(itemID)
    if not itemID then return nil end
    local _, spellID = GetItemSpell(itemID)
    return spellID
end

local function EquippedTrinkets()
    local list = {}
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then
            list[#list + 1] = { itemID = itemID, slot = slot }
        end
    end
    return list
end

-- Is this item a potion, by the game's own classification?
--
-- Asked of the item database rather than matched on the name, so it is right in
-- every language and does not need a list kept up to date.
-- Returns the answer, and whether the answer is actually known: the item
-- database can come back empty for an item the client has not cached, and
-- "not loaded yet" must never be mistaken for "no".
local function IsPotion(itemID)
    if not itemID or not GetItemInfoInstant then return false, false end
    local _, _, _, _, _, classID, subClassID = GetItemInfoInstant(itemID)
    if not classID then return false, false end
    -- Consumable, and one of the drinkable subclasses. Flasks and phials are
    -- included: people call them potions and expect them to count.
    if classID ~= Enum.ItemClass.Consumable then return false, true end
    return (subClassID == 1 or subClassID == 2 or subClassID == 3), true
end

-- Potions the player is actually carrying, so the picker offers what is to hand
-- rather than every potion in the game.
local function CarriedPotions()
    local seen, list = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        local slots = C_Container and C_Container.GetContainerNumSlots
            and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = info and info.itemID
            if itemID and not seen[itemID] and IsPotion(itemID) and ItemSpellID(itemID) then
                seen[itemID] = true
                list[#list + 1] = { itemID = itemID }
            end
        end
    end
    return list
end

-- The items a rule is restricted to, as a plain list.
--
-- Stored as a set so a rule can watch several at once and give each its own
-- sound. The older single-item field is still read, so rules written before
-- this keep working and quietly upgrade the first time one is edited.
function Triggers:GetTriggerItems(trigger)
    local conditions = trigger and trigger.conditions or {}
    local list = {}

    if type(conditions.items) == "table" then
        for itemID in pairs(conditions.items) do
            local id = tonumber(itemID)
            if id then list[#list + 1] = id end
        end
    elseif tonumber(conditions.itemID) then
        list[#list + 1] = tonumber(conditions.itemID)
    end

    table.sort(list)
    return list
end

-- Which of the rule's items produced this cast, if any.
--
-- Returns the item id so the actions can be chosen per item; nil when the rule
-- watches everything of its kind, which is when the plain actions apply.
function Triggers:GetMatchedItemID(trigger, eventData)
    -- A proc names its item outright: there is no cast to work back from.
    local direct = tonumber(eventData and eventData.itemID)
    if direct then
        for _, itemID in ipairs(self:GetTriggerItems(trigger)) do
            if itemID == direct then return itemID end
        end
        return nil
    end

    local castSpell = tonumber(eventData and eventData.spellID)
    if not castSpell then return nil end

    for _, itemID in ipairs(self:GetTriggerItems(trigger)) do
        local spellID = tonumber(ItemSpellID(itemID))
        if spellID and spellID == castSpell then return itemID end
    end
    return nil
end

-- Redraw both halves of a rule's page.
--
-- RefreshTriggerCard walks the Actions widgets only, so on its own the sound
-- and animation update while the item tiles keep whatever they were built
-- with -- the old icon, the old ticks. Every caller here wants both.
function Triggers:RefreshItemRulePage(triggerId)
    local trigger = OxedHub.db and OxedHub.db.profile
        and OxedHub.db.profile.triggers and OxedHub.db.profile.triggers[triggerId]
    if not trigger then return end

    local card = self.triggerCards and self.triggerCards[triggerId]
    if card and self.RefreshTriggerCardConditions then
        self:RefreshTriggerCardConditions(card, trigger)
    end
    self:RefreshTriggerCard(triggerId)
end

-- The action key prefix for one item, e.g. item191256Sound.
--
-- Keyed by item id rather than by position: a list index would point at a
-- different item the moment one is removed, silently moving somebody's sound.
function Triggers:GetItemActionPrefix(itemID)
    return "item" .. tostring(itemID)
end

-- Shared matcher. eventData carries the spell that was cast.
local function MatchesConfiguredItem(trigger, eventData, candidates)
    local procItem = tonumber(eventData and eventData.itemID)
    local castSpell = tonumber(eventData and eventData.spellID)
    if not procItem and not castSpell then return false end

    local chosen = Triggers:GetTriggerItems(trigger)
    if #chosen > 0 then
        return Triggers:GetMatchedItemID(trigger, eventData) ~= nil
    end

    -- A proc always comes from something the player has on, so with nothing
    -- picked it counts on its own.
    if procItem then return true end

    -- Nothing chosen: any of this kind counts.
    for _, entry in ipairs(candidates) do
        local spellID = tonumber(ItemSpellID(entry.itemID))
        if spellID and spellID == castSpell then return true end
    end
    return false
end

-- ── Condition UI ─────────────────────────────────────────────────────────────

local function BuildItemPicker(frame, trigger, yOffset, entries, emptyText, belongs, dropMissing)
    local conditions = trigger.conditions or {}
    trigger.conditions = conditions

    -- Drop items that belong to the other kind of rule.
    --
    -- Switching a rule's event from Trinket Used to Potion Used keeps its
    -- conditions, so the trinket stayed on the list -- shown as "not held",
    -- offered as a choice, and restricting a potion rule to something no potion
    -- can ever match. Cleared rather than merely hidden: left in place it would
    -- keep the rule silent with nothing on screen explaining why.
    -- Only when the item's class is actually known. GetItemInfoInstant comes
    -- back empty for anything the client has not cached, and treating that as
    -- "wrong kind" would silently wipe the player's picks on any page opened
    -- before their items had loaded.
    local function WrongKind(itemID)
        if not belongs then return false end
        local ok, known = belongs(tonumber(itemID))
        if known == false then return false end
        return not ok
    end

    if type(conditions.items) == "table" then
        for itemID in pairs(conditions.items) do
            if WrongKind(itemID) then conditions.items[itemID] = nil end
        end
        if not next(conditions.items) then conditions.items = nil end
    end
    if tonumber(conditions.itemID) and WrongKind(conditions.itemID) then
        conditions.itemID = nil
    end

    -- A chosen item you no longer have.
    --
    -- Trinkets and potions want opposite treatment here. A trinket you took off
    -- cannot fire, so keeping it in the rule is dead weight and it is dropped.
    -- A potion you ran out of is a temporary state -- you will buy more -- so it
    -- stays, marked, rather than the rule quietly forgetting your choice.
    --
    -- Dropping only when the list is genuinely known: an empty list can also
    -- mean the character's gear has not loaded yet, and wiping the rule then
    -- would be the same "unknown mistaken for no" mistake as before.
    local chosenList = Triggers:GetTriggerItems(trigger)
    local canTrustList = #entries > 0

    for _, itemID in ipairs(chosenList) do
        local present = false
        for _, entry in ipairs(entries) do
            if entry.itemID == itemID then present = true break end
        end
        if not present then
            if dropMissing and canTrustList then
                if type(conditions.items) == "table" then
                    conditions.items[itemID] = nil
                    if not next(conditions.items) then conditions.items = nil end
                end
                if tonumber(conditions.itemID) == itemID then conditions.itemID = nil end
                if Triggers._editingItem and Triggers._editingItem[trigger.id] == itemID then
                    Triggers._editingItem[trigger.id] = nil
                end
                -- Its per-item sound is left alone: re-equip the trinket, tick
                -- it again, and what you set up is still there.
            else
                table.insert(entries, 1, { itemID = itemID, missing = true })
            end
        end
    end

    local function IsChosen(itemID)
        if type(conditions.items) == "table" then return conditions.items[itemID] == true end
        return tonumber(conditions.itemID) == itemID
    end

    -- Which item the Actions section is really editing.
    --
    -- Nothing has been clicked on a freshly opened page, so Actions falls back
    -- to the first picked item. The tiles compared against the raw stored value
    -- instead and so highlighted nothing, leaving the player looking at one
    -- item's sound with no tile marked. One rule, used by both.
    local function EffectiveEditing()
        local picked = Triggers:GetTriggerItems(trigger)
        if #picked == 0 then return nil end
        local current = Triggers._editingItem and Triggers._editingItem[trigger.id]
        for _, itemID in ipairs(picked) do
            if itemID == current then return current end
        end
        return picked[1]
    end

    local function SetChosen(itemID, on)
        -- Migrate the old single field the first time a rule is touched.
        if type(conditions.items) ~= "table" then
            conditions.items = {}
            local legacy = tonumber(conditions.itemID)
            if legacy then conditions.items[legacy] = true end
            conditions.itemID = nil
        end
        conditions.items[itemID] = on or nil
        if not next(conditions.items) then conditions.items = nil end
    end

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    label:SetText("|cffffd100" .. (L["ITEMUSE_PICK"] or "Which item?")
        .. "|r  |cff888888" .. (L["ITEMUSE_PICK_HINT"]
            or "leave all unpicked to react to any of them") .. "|r")
    yOffset = yOffset - 22

    if #entries == 0 then
        local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        empty:SetText(emptyText)
        return yOffset - 24
    end

    local COLS, TILE_W, TILE_H = 3, 190, 40
    for index, entry in ipairs(entries) do
        local row = math.floor((index - 1) / COLS)
        local col = (index - 1) % COLS

        local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
        btn:SetSize(TILE_W, TILE_H)
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT", col * (TILE_W + 8), yOffset - row * (TILE_H + 6))
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })

        -- A left bar, a tick and a greyed icon, not just a slightly warmer
        -- border. Three states told apart only by shades of the same colour is
        -- something people have to stop and compare; these read at a glance.
        local accent = btn:CreateTexture(nil, "OVERLAY")
        accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
        accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
        accent:SetWidth(4)
        accent:SetColorTexture(1, 0.82, 0, 1)
        accent:Hide()

        -- A switch of its own for on and off.
        --
        -- One click used to mean three different things depending on the state
        -- it found -- pick, switch which one is being edited, or unpick. A tick
        -- box says plainly whether the item is watched, and leaves the tile
        -- itself to mean only "show me this one's actions".
        local toggle = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
        toggle:SetSize(24, 24)
        toggle:SetPoint("LEFT", btn, "LEFT", 4, 0)

        local selected = IsChosen(entry.itemID)
        local function Restyle()
            selected = IsChosen(entry.itemID)
            local editing = selected and EffectiveEditing() == entry.itemID

            toggle:SetChecked(selected)
            accent:SetShown(editing)

            -- The tick itself is the strongest signal on the tile, so it
            -- carries the state: gold for the one being edited, plain green for
            -- the others that are merely switched on.
            local check = toggle.GetCheckedTexture and toggle:GetCheckedTexture()
            if check then
                if editing then
                    check:SetVertexColor(1, 0.82, 0)
                else
                    check:SetVertexColor(0.45, 0.9, 0.45)
                end
            end

            if btn.itemIcon then btn.itemIcon:SetDesaturated(not selected) end
            if btn.itemText then
                if editing then
                    btn.itemText:SetTextColor(1, 0.82, 0)
                elseif selected then
                    btn.itemText:SetTextColor(1, 1, 1)
                else
                    btn.itemText:SetTextColor(0.55, 0.55, 0.55)
                end
            end

            -- Gold means exactly one thing on this page: the item whose actions
            -- are on screen. Everything else stays neutral, or two tiles read
            -- as both being selected when only one is.
            if editing then
                btn:SetBackdropColor(0.34, 0.27, 0.05, 1)
                btn:SetBackdropBorderColor(1, 0.82, 0, 1)
            elseif selected then
                -- Watched, but not the one on screen in Actions.
                btn:SetBackdropColor(0.12, 0.12, 0.13, 0.95)
                btn:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
            else
                btn:SetBackdropColor(0.06, 0.06, 0.07, 0.9)
                btn:SetBackdropBorderColor(0.28, 0.28, 0.28, 0.8)
            end
        end

        local icon = btn:CreateTexture(nil, "ARTWORK")
        btn.itemIcon = icon
        icon:SetSize(30, 30)
        -- Shifted right to clear the tick box now sitting at the left edge.
        icon:SetPoint("LEFT", toggle, "RIGHT", 2, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local _, _, _, _, itemIcon = GetItemInfoInstant(entry.itemID)
        icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.itemText = text
        text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        text:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(true)
        -- The name can be missing until the item is cached; ask for it and let
        -- the row fill itself in rather than leaving a blank tile.
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)
        name = name or ("Item " .. entry.itemID)
        -- Says why it is listed when you cannot see it in your bags or on your
        -- character, rather than looking like a stray entry.
        if entry.missing then
            name = name .. "  |cff888888(" .. (L["ITEMUSE_NOT_HELD"] or "not held") .. ")|r"
            icon:SetDesaturated(true)
        end
        text:SetText(name)
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, entry.itemID)
        end

        Restyle()

        local function Redraw()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
            Triggers:RefreshItemRulePage(trigger.id)
        end

        local function SetEditing(itemID)
            Triggers._editingItem = Triggers._editingItem or {}
            Triggers._editingItem[trigger.id] = itemID
        end

        -- The tick box is the only thing that turns an item on and off.
        toggle:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            SetChosen(entry.itemID, on)
            if on then
                -- Just switched on, so show its actions straight away.
                SetEditing(entry.itemID)
            elseif Triggers._editingItem
                and Triggers._editingItem[trigger.id] == entry.itemID then
                -- Switched off while being edited: Actions must not stay
                -- pointed at an item the rule no longer watches.
                SetEditing(nil)
            end
            Redraw()
        end)

        -- The tile means one thing: show me this item's actions.
        btn:SetScript("OnClick", function()
            if not IsChosen(entry.itemID) then
                -- Clicking an item that is off is a clear enough request to
                -- use it; switching it on saves a second click on the box.
                SetChosen(entry.itemID, true)
            end
            SetEditing(entry.itemID)
            Redraw()
        end)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(entry.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(selected
                and (L["ITEMUSE_CLICK_CLEAR"] or "Click to react to any of them again")
                or (L["ITEMUSE_CLICK_PICK"] or "Click to react to this one only"),
                0.5, 0.7, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local rows = math.ceil(#entries / COLS)
    yOffset = yOffset - rows * (TILE_H + 6) - 10

    -- Where the per-item sounds are. They are actions, so they live in the
    -- Actions section with everything else rather than being a second, private
    -- copy of that layout hidden down here among the conditions.
    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
    -- Falls back to the first picked item, which is what the Actions section
    -- actually edits when nothing has been clicked yet. Saying "the first
    -- picked item" instead of naming it left the player to work out which.
    local picked = Triggers:GetTriggerItems(trigger)
    local editingID = Triggers._editingItem and Triggers._editingItem[trigger.id]
    local stillPicked = false
    for _, itemID in ipairs(picked) do
        if itemID == editingID then stillPicked = true break end
    end
    if not stillPicked then editingID = picked[1] end
    local editingName = editingID and C_Item and C_Item.GetItemNameByID
        and C_Item.GetItemNameByID(editingID)
    if #Triggers:GetTriggerItems(trigger) > 0 then
        note:SetText(string.format(L["ITEMUSE_EDITING"]
            or "Actions below are for |cffffd100%s|r. Click another picked item to edit that one instead.",
            editingName or (L["ITEMUSE_FIRST_PICKED"] or "the first picked item")))
    else
        note:SetText(L["ITEMUSE_PICK_FIRST"]
            or "Pick an item above, then Actions below sets that item's sound and animation.")
    end
    yOffset = yOffset - 24

    -- Say so when an equipped trinket can never fire this rule.
    --
    -- A trinket with no use effect is one you never press: it goes off on its
    -- own, and the game tells an addon nothing when it does -- no cast, no
    -- readable cooldown, and buffs are secret in this version. The rule is
    -- silent for that trinket and always will be, so it is said here rather
    -- than left to be reported as a bug.
    if dropMissing then
        for _, entry in ipairs(entries) do
            if not entry.missing and not ItemSpellID(entry.itemID) then
                local warn = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                warn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
                warn:SetWidth(560)
                warn:SetJustifyH("LEFT")
                local itemName = (C_Item and C_Item.GetItemNameByID
                    and C_Item.GetItemNameByID(entry.itemID)) or ("Item " .. entry.itemID)
                warn:SetText(("|cffff8800%s|r %s"):format(itemName,
                    L["ITEMUSE_PROC_ONLY"]
                    or "has no button to press -- it fires on its own, and the game gives addons no way to see that, so this rule cannot react to it."))
                yOffset = yOffset - 26
            end
        end
    end

    return yOffset
end

-- Print exactly what the rule holds, so the tiles and the caption can be
-- compared against the data instead of against each other.
--
-- They disagree on screen: every box ticked, no tile marked, and the caption
-- saying nothing is picked -- yet all three read the same table. One of those
-- three is lying and the code cannot show which.
function Triggers:DumpItemRule()
    local id = self.selectedTriggerId
    local trigger = id and OxedHub.db and OxedHub.db.profile
        and OxedHub.db.profile.triggers and OxedHub.db.profile.triggers[id]
    if not trigger then
        print("|cffff5555OxedHub:|r open a trigger's page first.")
        return
    end

    local conditions = trigger.conditions or {}
    print(("|cff00ff00OxedHub itemdebug:|r %s  event=%s"):format(
        tostring(trigger.name), tostring(trigger.event)))
    print(("  conditions.items = %s   conditions.itemID = %s (%s)"):format(
        type(conditions.items), tostring(conditions.itemID), type(conditions.itemID)))

    if type(conditions.items) == "table" then
        local n = 0
        for key, value in pairs(conditions.items) do
            n = n + 1
            print(("    key=%s (%s)  value=%s (%s)"):format(
                tostring(key), type(key), tostring(value), type(value)))
        end
        if n == 0 then print("    (table is empty)") end
    end

    local picked = self:GetTriggerItems(trigger)
    print(("  GetTriggerItems -> %d entry(s)"):format(#picked))
    for _, itemID in ipairs(picked) do print("    " .. tostring(itemID)) end

    print(("  _editingItem = %s"):format(
        tostring(self._editingItem and self._editingItem[id])))

    -- What the Actions section is reading right now.
    local editing = self._editingItem and self._editingItem[id]
    if not editing then editing = picked[1] end
    if editing then
        local prefix = self:GetItemActionPrefix(editing)
        local actions = trigger.actions or {}
        print(("  editing=%s  %sSound=%s  %sAnim=%s"):format(
            tostring(editing), prefix, tostring(actions[prefix .. "Sound"]),
            prefix, tostring(actions[prefix .. "Anim"])))
    end
end

-- ── Keeping the page current ─────────────────────────────────────────────────
-- The lists are read once, when the page is built: what is equipped now, what
-- is in the bags now. Swap a trinket and the page went on showing the old one
-- until something else forced a rebuild -- changing a sound, say -- which is
-- not a thing anybody should have to discover.
--
-- Only redraws while a rule of this kind is actually open, and one frame later,
-- so a bag update that fires a dozen times in a row costs one rebuild.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:RegisterEvent("BAG_UPDATE_DELAYED")
watcher:SetScript("OnEvent", function()
    local id = Triggers.selectedTriggerId
    if not id then return end

    local trigger = OxedHub.db and OxedHub.db.profile
        and OxedHub.db.profile.triggers and OxedHub.db.profile.triggers[id]
    if not trigger then return end
    if trigger.event ~= "ITEM_TRINKET" and trigger.event ~= "ITEM_POTION" then return end

    if watcher.queued then return end
    watcher.queued = true
    C_Timer.After(0, function()
        watcher.queued = nil
        if Triggers.selectedTriggerId == id then
            -- The tiles are what a gear change alters, so the conditions have
            -- to be rebuilt too, not just the Actions widgets.
            Triggers:RefreshItemRulePage(id)
        end
    end)
end)

-- ── Trinkets that go off by themselves ───────────────────────────────────────
-- A proc trinket is never used, so it never casts anything, so the cast-based
-- path above never sees it. Its effect just happens.
--
-- What it does leave behind is its own cooldown: the moment the effect lands
-- the trinket goes on its internal cooldown, exactly as if it had been used.
-- So a trinket that was ready one moment and is not the next has fired, and
-- that is the signal watched here.
--
-- A trinket the player clicked also starts a cooldown, and that one has already
-- been announced through the cast. Its spell is remembered for a moment so the
-- same trinket is not reported twice.

local PROC_MIN_COOLDOWN = 1.5   -- below this it is the global cooldown, not a proc

local procWatcher = CreateFrame("Frame")
local procState = {}            -- slot -> { itemID = , onCooldown = }
local recentUse = {}            -- itemID -> time it was used by hand

local function TrinketOnCooldown(itemID)
    if not itemID then return false end
    local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
    local ok, rawStart, rawDuration = pcall(getCooldown, itemID)
    if not ok then return false end
    local startTime = tonumber(rawStart)
    local duration = tonumber(rawDuration)
    if not startTime or not duration then return false end
    return startTime > 0 and duration > PROC_MIN_COOLDOWN
end

local function ScanTrinkets(announce)
    local now = GetTime()

    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        local state = procState[slot]

        if not state or state.itemID ~= itemID then
            -- A freshly equipped trinket starts from whatever it is doing now,
            -- so putting one on while it is on cooldown is not read as a proc.
            state = { itemID = itemID }
            procState[slot] = state
            state.onCooldown = TrinketOnCooldown(itemID)
        else
            local onCooldown = TrinketOnCooldown(itemID)
            local started = onCooldown and not state.onCooldown
            state.onCooldown = onCooldown

            if started and announce and itemID then
                local usedAt = recentUse[itemID]
                if not usedAt or (now - usedAt) > 1 then
                    OxedHub.Triggers:ProcessEvent("ITEM_TRINKET", {
                        itemID = itemID,
                        slot = slot,
                        proc = true,
                    })
                end
            end
        end
    end
end

procWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
procWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
procWatcher:RegisterEvent("BAG_UPDATE_COOLDOWN")
procWatcher:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
procWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
procWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Note which trinket was used by hand, so its cooldown starting is not
        -- also reported as a proc a fraction of a second later.
        local cast = tonumber(spellID)
        if cast then
            for _, entry in ipairs(EquippedTrinkets()) do
                if tonumber(ItemSpellID(entry.itemID)) == cast then
                    recentUse[entry.itemID] = GetTime()
                end
            end
        end
        return
    end

    -- The cooldown events fire in bursts during combat. A trinket's cooldown
    -- does not disappear between two of them, so a tenth of a second between
    -- scans loses nothing and keeps this off the hot path.
    local now = GetTime()
    if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        if procWatcher.lastScan and (now - procWatcher.lastScan) < 0.1 then return end
    end
    procWatcher.lastScan = now

    -- Nobody is listening: keep the state current but stay quiet, so enabling a
    -- rule later does not fire on a cooldown that started before it existed.
    local listening = OxedHub.Core and OxedHub.Core.HasEnabledTrigger
        and OxedHub.Core:HasEnabledTrigger("ITEM_TRINKET")

    ScanTrinkets(listening and event ~= "PLAYER_ENTERING_WORLD"
        and event ~= "PLAYER_EQUIPMENT_CHANGED")
end)

-- Print what is actually readable about the equipped trinkets, so a silent
-- rule can be told apart from one whose trinket the client never reports.
function Triggers:DumpTrinketProcs()
    print("|cff00ff00OxedHub procdebug:|r equipped trinkets")
    for _, slot in ipairs(TRINKET_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if not itemID then
            print(("  slot %d: empty"):format(slot))
        else
            local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
            local ok, rawStart, rawDuration = pcall(getCooldown, itemID)
            print(("  slot %d: item=%s useSpell=%s cd=%s/%s%s"):format(
                slot, tostring(itemID), tostring(ItemSpellID(itemID)),
                ok and tostring(rawStart) or "?", ok and tostring(rawDuration) or "?",
                TrinketOnCooldown(itemID) and "  ON COOLDOWN" or ""))
        end
    end
    print(("  listening=%s"):format(tostring(OxedHub.Core
        and OxedHub.Core:HasEnabledTrigger("ITEM_TRINKET"))))
end

-- ── Registration ─────────────────────────────────────────────────────────────

Triggers:RegisterEventType("ITEM_TRINKET", {
    name = "Trinket Used (on-use)",
    CheckCondition = function(trigger, eventData)
        return MatchesConfiguredItem(trigger, eventData, EquippedTrinkets())
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        -- Anything that is not a potion is treated as a trinket here: an item
        -- worn in a trinket slot has no single class to test for.
        return BuildItemPicker(frame, trigger, yOffset, EquippedTrinkets(),
            L["ITEMUSE_NO_TRINKETS"] or "No trinkets equipped, so there is nothing to pick from yet.",
            function(itemID)
                if not itemID then return false, true end
                local isPotion, known = IsPotion(itemID)
                return not isPotion, known
            end,
            -- A trinket that is no longer equipped cannot fire, so it is
            -- dropped from the rule rather than lingering as "not held".
            true)
    end,
})

Triggers:RegisterEventType("ITEM_POTION", {
    name = "Potion Used",
    CheckCondition = function(trigger, eventData)
        return MatchesConfiguredItem(trigger, eventData, CarriedPotions())
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        return BuildItemPicker(frame, trigger, yOffset, CarriedPotions(),
            L["ITEMUSE_NO_POTIONS"] or "No potions, flasks or elixirs in your bags right now.",
            IsPotion)
    end,
})
