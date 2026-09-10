local addonName, OxedHub = ...

local Toys = OxedHub.Toys or {}
OxedHub.Toys = Toys
local L = OxedHub.L

-- ── Toy icons ────────────────────────────────────────────────────────────────
-- Why the grid used to open full of question marks.
--
-- C_ToyBox.GetToyInfo returns nothing for a toy the client has not cached, and
-- after a fresh login it has cached almost none of them. The panel dealt with
-- that by redrawing every 0.7 seconds up to four times, so the icons trickled
-- in over the first three seconds -- every session, from cold, forever.
--
-- Three changes here. Ask the item database directly, which knows the icon
-- without the full item record. Remember what we learn, so the next login draws
-- from the first frame. And listen for the event that says an item arrived
-- instead of polling for it.
--
-- The cache is account-wide rather than per-profile on purpose: profiles are
-- serialised separately, so a per-profile copy would be written out once per
-- profile -- the same mistake that made the saved variables file three times
-- larger than it needed to be.
local QUESTION_MARK_ICON = 134400

local function IconCache()
    if type(OxedHubDB) ~= "table" then return nil end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    OxedHubDB.globalSettings.toyIconCache = OxedHubDB.globalSettings.toyIconCache or {}
    return OxedHubDB.globalSettings.toyIconCache
end

-- Resolve a toy's icon, remembering it for next time.
--
-- Returns the icon and whether it had to fall back to the placeholder, so the
-- caller can decide whether a redraw is still owed.
function Toys:GetToyIcon(itemID)
    itemID = tonumber(itemID)
    if not itemID then return QUESTION_MARK_ICON, false end

    local cache = IconCache()

    local icon = select(3, C_ToyBox.GetToyInfo(itemID))
    if not icon and C_Item and C_Item.GetItemIconByID then
        -- Icons live in the item database and are available well before the
        -- rest of an item's data finishes loading.
        local ok, byId = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = byId end
    end

    if icon then
        if cache then cache[itemID] = icon end
        return icon, false
    end

    if cache and cache[itemID] then
        return cache[itemID], false
    end

    -- Nothing known yet. Ask for it; the event handler redraws when it lands.
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return QUESTION_MARK_ICON, true
end

-- Redraw once an item the client was missing finally arrives.
--
-- Throttled to one redraw per frame: a fresh login resolves hundreds of items
-- in a burst, and rebuilding the grid for each would be far worse than the
-- question marks ever were.
local itemInfoFrame = CreateFrame("Frame")
itemInfoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemInfoFrame:SetScript("OnEvent", function(_, _, itemID)
    if not Toys._toyIconsPending then return end
    if Toys._toyIconRedrawQueued then return end

    Toys._toyIconRedrawQueued = true
    C_Timer.After(0, function()
        Toys._toyIconRedrawQueued = nil
        Toys._toyIconsPending = false
        if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        if Toys.RefreshToyDock then Toys:RefreshToyDock() end
    end)
end)

-- Any change to boxes or their contents must reach BOTH views: the tab in the
-- addon and the floating panel, which each keep their own sidebar.  Missing
-- one is why a reorder only showed up after reopening the panel.
function Toys:NotifyBoxesChanged()
    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
end

-- ============================================================================
-- BOX ORDER
-- The sidebar order is the user's, set by dragging one box onto another.
-- ============================================================================

function Toys:GetBoxOrder()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return {} end
    profile.toyBoxOrder = profile.toyBoxOrder or {}
    return profile.toyBoxOrder
end

-- Move draggedId so it sits where targetId currently is.
-- dropAfter: the box lands below the target rather than above it. The caller
-- decides from where in the target row the cursor was released, so dropping on
-- the upper half puts it above and the lower half below -- the same rule in
-- both directions.
function Toys:ReorderBox(draggedId, targetId, dropAfter)
    if not draggedId or not targetId or draggedId == targetId then return end
    -- These two are fixed positions, never part of the user order.
    if draggedId == "all" or draggedId == "favorites" or draggedId == "mixes" then return end
    if targetId == "all" or targetId == "favorites" or targetId == "mixes" then return end

    local order = self:GetBoxOrder()

    -- Rebuild from what is on screen right now, every time.
    --
    -- Seeding only when the list was empty is what stopped shipped categories
    -- from moving: a profile that already had an order for the player's own
    -- boxes never took the seeding branch, so the categories were missing from
    -- it, their position came back nil, and the move was abandoned without a
    -- word. The player's boxes dragged fine because they were in the list.
    --
    -- Rebuilding is safe because the displayed order already reflects this same
    -- list first, so it round-trips unchanged.
    -- Read the shown order first, then replace the saved one with it.
    --
    -- Wiping before the read destroyed it: GetToyBoxes sorts by this very
    -- table, so it saw an empty order, fell back to the catalogue sequence, and
    -- every drag quietly threw away the arrangement built by the previous one.
    local shown = {}
    for _, box in ipairs(self:GetToyBoxes()) do
        if box.id ~= "all" and box.id ~= "favorites" and box.id ~= "mixes" then
            table.insert(shown, box.id)
        end
    end

    -- Hidden boxes are absent from the shown list, so carry their ids over or
    -- unhiding one would drop it back to the bottom of the sidebar.
    local visible = {}
    for _, id in ipairs(shown) do visible[id] = true end
    local carried = {}
    for _, id in ipairs(order) do
        if not visible[id] then table.insert(carried, id) end
    end

    wipe(order)
    for _, id in ipairs(shown) do
        table.insert(order, id)
    end
    for _, id in ipairs(carried) do
        table.insert(order, id)
    end

    local from, to
    for i, id in ipairs(order) do
        if id == draggedId then from = i end
        if id == targetId then to = i end
    end
    if not from or not to then return end

    table.remove(order, from)

    -- Removing the dragged box shifts everything after it down by one, so a
    -- target that sat below it is now one index lower. Without this correction
    -- a downward drag landed past the target and an upward drag landed on it,
    -- which for neighbouring rows looked exactly like the two swapping places.
    if from < to then to = to - 1 end
    if dropAfter then to = to + 1 end

    if to < 1 then to = 1 end
    if to > #order + 1 then to = #order + 1 end

    table.insert(order, to, draggedId)
    self:NotifyBoxesChanged()
end

-- ============================================================================
-- SUGGESTED BOXES
-- Ready-made boxes built from the player's own collection, so a suggestion only
-- ever contains toys the player actually owns.
--
-- Hearthstones stay a special case because they are identified by their own ID
-- list elsewhere in this file. Everything else comes from the shipped
-- categories in ToyCategories.lua, which match on toy ID.
--
-- The old entries here matched keywords against toy names ("firework",
-- "portal", ...). That only worked on an English client and missed any toy
-- whose name did not happen to contain the word, so it has been dropped.
-- ============================================================================
Toys.SUGGESTED_BOXES = {
    {
        key = "hearthstones", name = "Hearthstones", icon = 134414,
        ids = true,  -- uses Toys.HearthstoneIds rather than a name match
    },
}

for _, category in ipairs(OxedHub.TOY_CATEGORIES or {}) do
    table.insert(Toys.SUGGESTED_BOXES, category)
end

function Toys:GetSuggestedBoxToys(def)
    local out = {}
    if not def then return out end

    -- A shipped category carries an explicit ID list. Filtering by ownership
    -- here is what keeps a box from listing hundreds of toys the player has
    -- never collected.
    if type(def.ids) == "table" then
        for _, id in ipairs(def.ids) do
            if PlayerHasToy(id) then table.insert(out, id) end
        end
        return out
    end

    if def.ids then
        for _, id in ipairs(self.HearthstoneIds or {}) do
            if PlayerHasToy(id) then table.insert(out, id) end
        end
        return out
    end

    for _, toyId in ipairs(self:GetAllCollectedToyIDs()) do
        local _, toyName = C_ToyBox.GetToyInfo(toyId)
        if toyName then
            local lower = toyName:lower()
            for _, word in ipairs(def.words or {}) do
                if lower:find(word, 1, true) then
                    table.insert(out, toyId)
                    break
                end
            end
        end
    end
    return out
end

-- Build a real box from a suggestion. Returns the new box id, or nil plus a
-- reason when there is nothing to put in it.
function Toys:CreateSuggestedBox(key)
    if self.EnsureToyData then self:EnsureToyData(true) end

    local def
    for _, d in ipairs(self.SUGGESTED_BOXES) do
        if d.key == key then def = d break end
    end
    if not def then return nil, "Unknown suggestion." end

    local toys = self:GetSuggestedBoxToys(def)
    if #toys == 0 then
        return nil, "You do not own any toys that fit " .. def.name .. "."
    end

    local boxId = self:CreateToyBox(def.name, def.icon)
    if not boxId then return nil, "Could not create the box." end

    for _, toyId in ipairs(toys) do
        self:AddToyToBox(boxId, toyId)
    end
    return boxId, #toys
end

-- ============================================================================
-- SEARCH + PINNED TOYS
-- ============================================================================

-- Filter a toy id list by a search string, matched against the toy's name.
-- An empty or missing query returns the list untouched.
function Toys:FilterToyList(list, query)
    if type(list) ~= "table" then return {} end
    if not query or query == "" then return list end

    local needle = query:lower()
    local out = {}
    for _, toyId in ipairs(list) do
        -- The mixes box holds names rather than IDs, and feeding a string to
        -- GetToyInfo would only ever come back empty.
        if type(toyId) == "string" then
            if toyId:lower():find(needle, 1, true) then
                table.insert(out, toyId)
            end
        else
        local _, toyName = C_ToyBox.GetToyInfo(toyId)
        if toyName and toyName:lower():find(needle, 1, true) then
            table.insert(out, toyId)
        elseif tostring(toyId):find(needle, 1, true) then
            -- Searching by item id is handy when a name is not cached yet.
            table.insert(out, toyId)
        end
        end
    end
    return out
end

-- Toys the user wants visible at all times, kept at the front of the grid.
function Toys:GetPinnedToys()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return {} end
    profile.toyBoxPinned = profile.toyBoxPinned or {}

    -- Drop anything pinned that is not actually owned.
    --
    -- Right-clicking in the wish list used to pin an uncollected toy, and it
    -- then sat at the front of All Toys and in the quick slots doing nothing.
    -- Cleaning up here rather than at the click, so a pin made before this fix
    -- also goes away.
    --
    -- Only once the collection is known: PlayerHasToy answers no for everything
    -- until the toy data has loaded, and acting on that would clear the lot.
    if not self._pinnedChecked and #self:GetAllCollectedToyIDs() > 0 then
        self._pinnedChecked = true
        for i = 1, self.MAX_PINNED_TOYS do
            local id = profile.toyBoxPinned[i]
            if type(id) == "number" and not PlayerHasToy(id) then
                profile.toyBoxPinned[i] = nil
            end
        end
    end

    return profile.toyBoxPinned
end

Toys.MAX_PINNED_TOYS = 5

function Toys:IsToyPinned(toyId)
    local pinned = self:GetPinnedToys()
    for i = 1, self.MAX_PINNED_TOYS do
        if pinned[i] == toyId then return true end
    end
    return false
end

-- Returns true when pinned, false when unpinned, nil when the list is full.
function Toys:TogglePinnedToy(toyId)
    local pinned = self:GetPinnedToys()
    for i = 1, self.MAX_PINNED_TOYS do
        if pinned[i] == toyId then
            pinned[i] = nil
            return false
        end
    end

    for i = 1, self.MAX_PINNED_TOYS do
        if not pinned[i] then
            pinned[i] = toyId
            return true
        end
    end

    return nil
end

-- ============================================================================
-- HOW OFTEN A TOY IS USED
-- Counted here rather than read from the game: nothing tells an addon that a
-- toy was used. Every place that can use one -- the grid, the dock, the quick
-- bar, the random button -- reports it through this one call.
--
-- Kept account-wide, next to the icon cache. Which toys you reach for is a
-- habit, not a property of a profile, and having the count reset by switching
-- profile would make the ordering look random.
-- ============================================================================

local function UsageStore()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    OxedHubDB.globalSettings.toyUsage = OxedHubDB.globalSettings.toyUsage or {}
    return OxedHubDB.globalSettings.toyUsage
end

function Toys:RecordToyUse(toyId)
    if type(toyId) ~= "number" then return end
    local store = UsageStore()
    local key = tostring(toyId)
    store[key] = (tonumber(store[key]) or 0) + 1
end

-- ── Counting from the game rather than from our own buttons ─────────────────
-- Hanging the count off click handlers was wrong, and it showed: a toy used
-- five times from the dock counted zero. The tiles are secure buttons, so the
-- game itself fires the toy from an attribute, and whether our own handler also
-- ran depended on the lock state, on which panel it was, and on the branch it
-- happened to take. Four places to count in, each able to miss.
--
-- Using a toy casts its spell, and that the client does announce. One listener,
-- and it catches every route -- our grid, our dock, the quick slots, a macro, a
-- keybind, even Blizzard's own toy box.

local spellToToy = nil

local function BuildSpellMap()
    spellToToy = {}
    for _, itemID in ipairs(Toys:GetAllCollectedToyIDs()) do
        local _, spellID = GetItemSpell(itemID)
        if spellID then spellToToy[spellID] = itemID end
    end
end

function Toys:InvalidateToySpellMap()
    spellToToy = nil
end

function Toys:NoteToySpellCast(spellID)
    spellID = tonumber(spellID)
    if not spellID then return end

    if not spellToToy then BuildSpellMap() end
    local itemID = spellToToy[spellID]
    -- A toy learned since the map was built would be missed, so a miss is worth
    -- one rebuild before it is believed.
    if not itemID and not self._spellMapFresh then
        BuildSpellMap()
        self._spellMapFresh = true
        itemID = spellToToy[spellID]
    end
    if not itemID then return end

    self:RecordToyUse(itemID)
    self:RefreshAfterUsageChange()
end

local usageWatcher = CreateFrame("Frame")
usageWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
usageWatcher:RegisterEvent("TOYS_UPDATED")
usageWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "TOYS_UPDATED" then
        Toys:InvalidateToySpellMap()
        Toys._spellMapFresh = nil
        return
    end
    Toys:NoteToySpellCast(spellID)
end)

-- Use a toy and count it, in that order, from one place.
--
-- Every caller had its own pcall around C_ToyBox.UseToyByItemID, so counting
-- meant remembering to add a line beside each of them -- and the one that gets
-- forgotten is the one that makes the ordering wrong.
function Toys:UseToyById(toyId)
    if type(toyId) ~= "number" then return false end
    if not (C_ToyBox and C_ToyBox.UseToyByItemID) then return false end

    -- The count is not taken here. It is taken from the spell the toy casts,
    -- which catches every way a toy can be used rather than only this one.
    local ok = pcall(C_ToyBox.UseToyByItemID, toyId)
    return ok
end

-- Redraw so a new count actually shows.
--
-- The order is worked out while the grid is being drawn, so counting a use
-- changed nothing on screen until something else forced a redraw -- which is
-- why a toy used ten times sat exactly where it was.
--
-- Never during a fight: the tiles carry secure attributes that cannot be
-- changed in combat, and moving buttons around under the cursor mid-pull is
-- not something to do for a cosmetic reordering either. It waits.
function Toys:RefreshAfterUsageChange()
    local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings
    if not cfg or not cfg.sortByUsage then return end

    if InCombatLockdown() then
        if not self._usageCombatWatcher then
            self._usageCombatWatcher = CreateFrame("Frame")
            self._usageCombatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            self._usageCombatWatcher:SetScript("OnEvent", function()
                if Toys._usageRefreshPending then
                    Toys._usageRefreshPending = nil
                    Toys:RefreshAfterUsageChange()
                end
            end)
        end
        self._usageRefreshPending = true
        return
    end

    -- One redraw for a burst of uses, not one per click.
    if self._usageRefreshQueued then return end
    self._usageRefreshQueued = true
    C_Timer.After(0.5, function()
        Toys._usageRefreshQueued = nil
        if InCombatLockdown() then
            Toys._usageRefreshPending = true
            return
        end
        if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        if Toys.UpdateQuickToyBar then Toys:UpdateQuickToyBar() end
    end)
end

function Toys:GetToyUseCount(toyId)
    if type(toyId) ~= "number" then return 0 end
    return tonumber(UsageStore()[tostring(toyId)]) or 0
end

-- What the counter actually holds, and whether the ordering is switched on.
--
-- "I used it ten times and it did not move" has three possible causes -- the
-- setting is off, the uses were never counted, or they were counted and the
-- sort is not being applied -- and they look identical from the outside.
function Toys:DumpToyUsage()
    local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
    print(("|cff00ff00OxedHub usagedebug:|r sortByUsage=%s"):format(tostring(cfg.sortByUsage)))
    if not cfg.sortByUsage then
        print("  |cffff5555the setting is off|r -- ToyBoxes > Settings > Sort toys by how often you use them.")
    end

    -- The map is what turns a cast into a toy; empty means nothing can ever be
    -- counted, however many times a toy is used.
    if not spellToToy then BuildSpellMap() end
    local mapped = 0
    for _ in pairs(spellToToy) do mapped = mapped + 1 end
    print(("  %d toys mapped to their spell"):format(mapped))

    local store = UsageStore()
    local rows = {}
    for key, count in pairs(store) do
        rows[#rows + 1] = { id = tonumber(key), count = tonumber(count) or 0 }
    end
    table.sort(rows, function(a, b) return a.count > b.count end)

    if #rows == 0 then
        print("  |cffff5555nothing counted yet|r -- no toy use has been recorded since this went in.")
        return
    end

    print(("  %d toys counted, most used first:"):format(#rows))
    for index = 1, math.min(10, #rows) do
        local row = rows[index]
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(row.id))
            or ("item " .. tostring(row.id))
        print(("    %-40s %d use(s)"):format(tostring(name), row.count))
    end
end

function Toys:ClearToyUsage()
    if OxedHubDB and OxedHubDB.globalSettings then
        OxedHubDB.globalSettings.toyUsage = nil
    end
end

-- Most used first, when the player has asked for it.
--
-- Stable in the ties: everything with the same count keeps the order it came
-- in with, so a box of unused toys looks exactly as it did rather than being
-- shuffled into whatever order pairs() happened to produce.
function Toys:ApplyToySorting(list, box)
    local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings
    if not cfg or not cfg.sortByUsage then return list end
    -- Mixes are names, not toy ids, and a wish list is of toys never used.
    if box and (box.isMixes or box.isWishList) then return list end

    local position = {}
    for index, id in ipairs(list) do position[id] = index end

    local sorted = {}
    for _, id in ipairs(list) do sorted[#sorted + 1] = id end

    table.sort(sorted, function(a, b)
        local ua, ub = self:GetToyUseCount(a), self:GetToyUseCount(b)
        if ua ~= ub then return ua > ub end
        return (position[a] or 0) < (position[b] or 0)
    end)

    return sorted
end

-- ============================================================================
-- WISH LIST
-- Every toy the player has not collected, as one box. Built from the game's
-- own toy list with the collected ones taken out.
--
-- The client's toy box carries filters -- collected, uncollected, a search
-- string, source and expansion -- and they decide what the enumeration returns.
-- They are read, widened for the length of the scan and put back exactly as
-- they were, because they belong to the player's own toy box window.
-- ============================================================================

function Toys:GetUncollectedToyIDs()
    -- Rebuilt when the collection changes, not on every draw: this walks the
    -- whole toy list, which is thousands of entries.
    if self._wishListCache then return self._wishListCache end

    local list = {}
    if not (C_ToyBox and C_ToyBox.GetNumFilteredToys and C_ToyBox.GetToyFromIndex) then
        return list
    end

    local restore = {}
    local function Widen(getter, setter, value)
        if not (C_ToyBox[getter] and C_ToyBox[setter]) then return end
        local ok, current = pcall(C_ToyBox[getter])
        if ok then
            restore[#restore + 1] = { setter = setter, value = current }
            pcall(C_ToyBox[setter], value)
        end
    end

    Widen("GetCollectedShown", "SetCollectedShown", true)
    Widen("GetUncollectedShown", "SetUncollectedShown", true)

    local ok, count = pcall(C_ToyBox.GetNumFilteredToys)
    if ok and count then
        for index = 1, count do
            local okToy, itemID = pcall(C_ToyBox.GetToyFromIndex, index)
            if okToy and itemID and itemID > 0 and not PlayerHasToy(itemID) then
                list[#list + 1] = itemID
            end
        end
    end

    for i = #restore, 1, -1 do
        pcall(C_ToyBox[restore[i].setter], restore[i].value)
    end

    self._wishListCache = list
    return list
end

function Toys:InvalidateWishList()
    self._wishListCache = nil
end

-- Prove what the wish list holds, rather than judging it by the icons.
--
-- "These are toys I already have" and "the scan is picking up the wrong ones"
-- look identical on screen; PlayerHasToy for each entry settles it.
function Toys:DumpWishList()
    local missing = self:GetUncollectedToyIDs()
    local owned = self:GetAllCollectedToyIDs()
    print(("|cff00ff00OxedHub wishdebug:|r %d not collected, %d collected"):format(
        #missing, #owned))

    local wrong = 0
    for _, itemID in ipairs(missing) do
        if PlayerHasToy(itemID) then wrong = wrong + 1 end
    end
    if wrong > 0 then
        print(("  |cffff5555%d entries are toys you DO own|r -- the scan is wrong."):format(wrong))
    else
        print("  every entry is a toy you do not own.")
    end

    print("  first few:")
    for index = 1, math.min(8, #missing) do
        local itemID = missing[index]
        local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
            or ("item " .. tostring(itemID))
        print(("    %s (%s)  owned=%s"):format(
            tostring(name), tostring(itemID), tostring(PlayerHasToy(itemID))))
    end
end

-- Move pinned toys to the front, keeping the rest in their existing order.
function Toys:ApplyPinnedToys(list, boxId)
    if boxId ~= "all" then return list end

    local pinned = self:GetPinnedToys()
    local isPinned, out = {}, {}
    for i = 1, self.MAX_PINNED_TOYS do
        local id = pinned[i]
        if id then
            isPinned[id] = true
            table.insert(out, id)
        end
    end
    if #out == 0 then return list end

    for _, id in ipairs(list) do
        if not isPinned[id] then table.insert(out, id) end
    end
    return out
end

-- ============================================================================
-- DELETE CONFIRMATIONS
-- Removing a toy or a whole box cannot be undone, so both ask first.  Holding
-- shift on the toy's [x] skips the prompt for clearing several in a row.
-- ============================================================================

function Toys:ConfirmRemoveToy(boxId, toyId)
    local _, toyName = C_ToyBox.GetToyInfo(toyId)
    local box = self:GetToyBox(boxId)

    StaticPopupDialogs["OXEDHUB_CONFIRM_REMOVE_TOY"] = {
        text = "Remove |cffffd100%s|r from |cffffd100%s|r?\n\n|cff888888Hold Shift when clicking [x] to skip this prompt.|r",
        button1 = L["SETTINGS_BTN_YES"] or "Yes",
        button2 = L["SETTINGS_BTN_NO"] or "No",
        OnAccept = function()
            Toys:RemoveToyFromBox(boxId, toyId)
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_CONFIRM_REMOVE_TOY",
        toyName or ("Toy #" .. tostring(toyId)),
        (box and box.name) or "this box")
end

-- ============================================================================
-- HIDING BOXES
-- ============================================================================
-- Hiding takes a box out of both sidebars but keeps the box and its contents,
-- so a shipped category the player has no use for right now can come back later
-- without rebuilding it by hand. Deleting stays available for boxes they are
-- certain about.

function Toys:IsBoxHidden(boxId)
    local box = OxedHub.db and OxedHub.db.profile
        and OxedHub.db.profile.toyBoxes and OxedHub.db.profile.toyBoxes[boxId]
    return box ~= nil and box.hidden == true
end

function Toys:SetBoxHidden(boxId, hidden)
    -- These two are the entry points to the whole panel; hiding either would
    -- leave the player with no way back to their collection.
    if boxId == "all" or boxId == "favorites" then return false end

    self:EnsureToyBoxData()
    local box = OxedHub.db.profile.toyBoxes[boxId]
    if not box then return false end

    box.hidden = hidden and true or nil
    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return true
end

-- Sorted by name so the restore list reads predictably.
function Toys:GetHiddenBoxes()
    self:EnsureToyBoxData()
    local out = {}
    local boxes = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxes
    if not boxes then return out end

    for id, box in pairs(boxes) do
        if box.hidden then
            table.insert(out, { id = id, name = box.name or "?", icon = box.icon, count = #(box.toys or {}) })
        end
    end
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

function Toys:ConfirmDeleteBox(boxId, boxName, toyCount)
    -- Hide is the first button because it is the reversible one. Deleting a box
    -- that took effort to fill is the kind of mistake worth making harder to
    -- reach by accident.
    StaticPopupDialogs["OXEDHUB_CONFIRM_DELETE_BOX"] = {
        text = "Remove the box |cffffd100%s|r?\n\n|cffff6666%s|r\n|cff888888Hide keeps the box and its contents -- you can bring it back from Settings.\nDelete removes the box for good. Either way the toys stay in your collection.|r",
        button1 = L["TOYBOX_BTN_HIDE"] or "Hide",
        button2 = L["SETTINGS_BTN_CANCEL"] or "Cancel",
        button3 = L["TOYBOX_BTN_DELETE"] or "Delete",
        OnAccept = function()
            Toys:SetBoxHidden(boxId, true)
        end,
        OnAlt = function()
            Toys:DeleteToyBox(boxId)
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    local countText = (toyCount == 1)
        and "It holds 1 toy."
        or ("It holds " .. tostring(toyCount or 0) .. " toys.")
    StaticPopup_Show("OXEDHUB_CONFIRM_DELETE_BOX", boxName or "?", countText)
end

-- Default preset icon textures for custom toy boxes
Toys.BOX_PRESET_ICONS = {
    134400, -- Star (Favorites)
    132152, -- Monster Skull (Morphs / Costumes)
    134414, -- Hearthstone / Portal
    133940, -- Party / Horn
    132274, -- Music / Instrument
    134062, -- Flag / Banner
    132223, -- Fireworks
    134269, -- Toy Train / Engineering
    132333, -- Magic / Arcane Book
    136012, -- Dragon / Mount toy
    132353, -- Campfire / Cooking
    135933, -- Treasure Chest
}

-- Resolve icon texture regardless of whether it is a stored string, spell ID, or texture ID
function Toys:GetBoxIconTexture(iconValue)
    if not iconValue or iconValue == "" then
        return 135933
    end
    if OxedHub.IconPicker and OxedHub.IconPicker.ResolveTexture then
        local resolved = OxedHub.IconPicker:ResolveTexture(iconValue)
        if resolved then return resolved end
    end
    local num = tonumber(iconValue)
    if num then return num end
    return iconValue
end

-- Get all collected toy IDs from the player's toybox
function Toys:GetAllCollectedToyIDs()
    if self.EnsureToyData then self:EnsureToyData() end
    if self.toyIDs and #self.toyIDs > 0 then
        return self.toyIDs
    end
    local list = {}
    if C_ToyBox and C_ToyBox.GetNumFilteredToys then
        for i = 1, C_ToyBox.GetNumFilteredToys() do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and itemID > 0 and PlayerHasToy(itemID) then
                table.insert(list, itemID)
            end
        end
    end
    return list
end

-- Get all favorite toy IDs (synced dynamically from WoW native favorites + custom profile)
function Toys:GetFavoriteToyIDs()
    local all = self:GetAllCollectedToyIDs()
    local favList = {}
    local seen = {}

    -- 1. All toys marked as favorite in native WoW ToyBox
    if C_ToyBox and C_ToyBox.GetIsFavorite then
        for _, toyID in ipairs(all) do
            if C_ToyBox.GetIsFavorite(toyID) and not seen[toyID] then
                seen[toyID] = true
                table.insert(favList, toyID)
            end
        end
    end

    -- 2. Plus any custom toys added by user into profile.toyBoxes["favorites"].toys
    local profile = OxedHub.db and OxedHub.db.profile
    local savedFavs = profile and profile.toyBoxes and profile.toyBoxes["favorites"] and profile.toyBoxes["favorites"].toys
    if savedFavs then
        for _, toyID in ipairs(savedFavs) do
            if not seen[toyID] and PlayerHasToy(toyID) then
                seen[toyID] = true
                table.insert(favList, toyID)
            end
        end
    end

    return favList
end

-- Initialize default boxes in profile if not already present
-- Fills the sidebar on a fresh profile so the categories are visible without
-- the player having to build them by hand.
--
-- Runs once and records that it did. Without the marker, deleting a shipped box
-- would simply bring it back on the next load, and there would be no way to get
-- rid of one. An empty category is skipped rather than created empty, and the
-- toy collection is not always loaded on the first call -- so a run that finds
-- nothing does not count, and the seeding is retried later.
function Toys:SeedDefaultBoxes()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not OxedHub.TOY_CATEGORIES then return end

    -- Seeding is recorded per category, not as one global "done" flag. A single
    -- flag meant a category added in a later version could never reach anyone
    -- who already had the earlier set, while re-seeding without a record would
    -- resurrect every box the player had deleted.
    if not profile.seededBoxKeys then
        profile.seededBoxKeys = {}
        -- Carry over an install seeded by the earlier flag: whatever it created
        -- is already on screen and must not be created a second time.
        if profile.toyBoxesSeeded then
            for id in pairs(profile.toyBoxes or {}) do
                local key = tostring(id):match("^default_(.+)$")
                if key then profile.seededBoxKeys[key] = true end
            end
        end
    end

    -- Keep the shipped boxes in step with the category definitions. Without
    -- this a box created by an earlier version keeps whatever name and icon it
    -- was born with -- which is how a category whose icon path turned out not to
    -- exist in the client stayed blank even after the definition was fixed.
    --
    -- Only boxes still marked as shipped are touched; renaming one opts it out
    -- for good. Contents are never rewritten here, since the player may have
    -- added or removed toys -- that is what RebuildDefaultBoxes is for.
    -- Drop shipped boxes whose category no longer exists. Reworking the
    -- catalogue would otherwise leave the previous set behind as orphans with
    -- names that match nothing. A box the player has renamed is theirs now and
    -- is left alone.
    local known = {}
    for _, category in ipairs(OxedHub.TOY_CATEGORIES) do
        known["default_" .. category.key] = true
    end
    for id, box in pairs(profile.toyBoxes or {}) do
        if tostring(id):match("^default_") and not known[id] and box.isShipped ~= false then
            profile.toyBoxes[id] = nil
        end
    end

    for _, category in ipairs(OxedHub.TOY_CATEGORIES) do
        local box = profile.toyBoxes and profile.toyBoxes["default_" .. category.key]
        if box and box.isShipped ~= false then
            box.isShipped = true
            box.name = category.name
            box.desc = category.desc

            -- Overwrites unconditionally, which is the point: boxes created by
            -- earlier versions carry icons taken from whichever toy happened to
            -- be first, so several shared one and some had none at all.
            box.icon = category.icon
        end
    end

    for _, category in ipairs(OxedHub.TOY_CATEGORIES) do
        if not profile.seededBoxKeys[category.key] then
            local owned = self:GetSuggestedBoxToys(category)
            -- An empty result usually means the toy collection has not loaded
            -- yet, so nothing is recorded and the category is tried again later.
            if #owned > 0 then
                local boxId = "default_" .. category.key
                if not profile.toyBoxes[boxId] then
                    profile.toyBoxes[boxId] = {
                        id = boxId,
                        name = category.name,
                        desc = category.desc,
                        icon = category.icon,
                        toys = owned,
                        isShipped = true,
                        createdAt = time(),
                    }
                end
                profile.seededBoxKeys[category.key] = true
                profile.toyBoxesSeeded = true
            end
        end
    end
end

-- Throws away the shipped boxes and builds them again from the current
-- categories. Offered as an explicit action because it discards any toy the
-- player added to or removed from one of them -- seeding alone never touches a
-- box that already exists.
function Toys:RebuildDefaultBoxes()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not OxedHub.TOY_CATEGORIES then return 0 end

    for id in pairs(profile.toyBoxes or {}) do
        if tostring(id):match("^default_") then
            profile.toyBoxes[id] = nil
        end
    end
    profile.seededBoxKeys = nil
    profile.toyBoxesSeeded = nil

    self:SeedDefaultBoxes()

    local count = 0
    for id in pairs(profile.toyBoxes or {}) do
        if tostring(id):match("^default_") then count = count + 1 end
    end

    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return count
end

function Toys:EnsureToyBoxData()
    if not OxedHub.db or not OxedHub.db.profile then return end
    local profile = OxedHub.db.profile
    profile.toyBoxes = profile.toyBoxes or {}

    -- Create default "Favorites" box if empty
    if not profile.toyBoxes["favorites"] then
        profile.toyBoxes["favorites"] = {
            id = "favorites",
            name = "Favorites",
            icon = 134400,
            toys = {},
            isDefault = true,
            createdAt = time(),
        }
    end

    self:SeedDefaultBoxes()

    -- Ensure all box entries have valid structure
    for id, box in pairs(profile.toyBoxes) do
        box.id = id
        box.name = box.name or "Unnamed Box"
        box.icon = box.icon or 135933
        box.toys = box.toys or {}
    end
end

-- Get all toyboxes ordered by name (with All Toys and Favorites first)
function Toys:GetToyBoxes()
    self:EnsureToyBoxData()
    local boxes = {}

    -- Add virtual "All Toys" box
    local allToys = self:GetAllCollectedToyIDs()
    table.insert(boxes, {
        id = "all",
        name = "All Toys",
        icon = 134400,
        isAll = true,
        toys = allToys,
    })

    -- Virtual box holding every saved mix. Mixes are not toys and live in their
    -- own table, so this box carries their names rather than toy IDs and the
    -- grid renders it differently -- see the isMixes branch in the UI.
    local mixNames = self:GetMixNames()
    if #mixNames > 0 then
        table.insert(boxes, {
            id = "mixes",
            name = "My Mixes",
            icon = 134064,
            isMixes = true,
            toys = mixNames,
        })
    end

    -- Everything still missing, as a wish list. Off the list entirely when the
    -- player has hidden it, rather than shown empty: somebody who does not care
    -- what they are missing should not have a box for it at all.
    local toySettings = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings
    if toySettings and toySettings.showWishList then
        local missing = self:GetUncollectedToyIDs()
        if #missing > 0 then
            table.insert(boxes, {
                id = "wishlist",
                name = "Wish List",
                icon = 134153,
                isWishList = true,
                toys = missing,
            })
        end
    end

    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxes then
        local userBoxes = {}
        for id, box in pairs(OxedHub.db.profile.toyBoxes) do
            if id == "favorites" then
                -- Always dynamically sync real favorites list
                table.insert(userBoxes, {
                    id = "favorites",
                    name = box.name or "Favorites",
                    icon = box.icon or 134400,
                    isFavorites = true,
                    isDefault = true,
                    toys = self:GetFavoriteToyIDs(),
                })
            elseif not box.hidden then
                table.insert(userBoxes, box)
            end
        end

        -- Favourites stays pinned at the top.  Everything else follows the
        -- user's own drag order; boxes with no saved position (newly created)
        -- fall to the end in alphabetical order.
        local order = self:GetBoxOrder()
        local rank = {}
        for i, id in ipairs(order) do rank[id] = i end

        -- Shipped boxes keep the catalogue order until the player drags one.
        -- Sorting them by name would scramble a deliberate sequence into
        -- Banner, Brew, Clone, Corpse and lose the grouping entirely.
        local catalogueRank = {}
        for i, category in ipairs(OxedHub.TOY_CATEGORIES or {}) do
            catalogueRank["default_" .. category.key] = i
        end

        table.sort(userBoxes, function(a, b)
            if a.id == "favorites" then return true end
            if b.id == "favorites" then return false end

            -- An explicit drag outranks everything below it.
            local ra, rb = rank[a.id], rank[b.id]
            if ra and rb then return ra < rb end
            if ra then return true end
            if rb then return false end

            local ca, cb = catalogueRank[a.id], catalogueRank[b.id]
            if ca and cb then return ca < cb end
            -- The player's own boxes sit after the shipped ones.
            if ca then return true end
            if cb then return false end

            return (a.name or ""):lower() < (b.name or ""):lower()
        end)

        for _, box in ipairs(userBoxes) do
            table.insert(boxes, box)
        end
    end

    return boxes
end

-- Get a specific toybox by ID
-- ============================================================================
-- CLICK DIAGNOSTICS  (/oxedhub toydebug)
-- ============================================================================
-- Reports what a tile actually is at runtime rather than what the code intends.
-- Every guess about why clicking did nothing was about how the attributes get
-- set; none of them checked whether the button was still secure by the time it
-- was clicked, which is the thing that was actually broken.

local function DescribeButton(label, button)
    if not button then
        print(("|cff00d9d9%s:|r no button"):format(label))
        return
    end

    local isProtected, isExplicit = button:IsProtected()
    local hasOnClick = button:GetScript("OnClick") ~= nil

    print(("|cff00d9d9%s|r  shown=%s protected=%s explicit=%s ownOnClick=%s"):format(
        label, tostring(button:IsShown()), tostring(isProtected),
        tostring(isExplicit), tostring(hasOnClick)))

    print(("   id=%s kind=%s"):format(
        tostring(button.toyID or button.id or button.mixName), tostring(button._kind)))

    print(("   type=%s type1=%s toy=%s toy1=%s macrotext=%s"):format(
        tostring(button:GetAttribute("type")), tostring(button:GetAttribute("type1")),
        tostring(button:GetAttribute("toy")), tostring(button:GetAttribute("toy1")),
        button:GetAttribute("macrotext") and "set" or "nil"))
end

function Toys:DumpToyButtons()
    local profile = OxedHub.db and OxedHub.db.profile or {}
    local tabLocked = profile.toyBoxSettings and profile.toyBoxSettings.isLocked
    local dockLocked = profile.toyBoxFrame and profile.toyBoxFrame.locked

    print("|cff00d9d9=== OxedHub toy click diagnostics ===|r")
    print(("lock: tab=%s dock=%s | combat=%s | draggedToy=%s"):format(
        tostring(tabLocked), tostring(dockLocked),
        tostring(InCombatLockdown()), tostring(Toys._draggedToyID)))

    DescribeButton("tab grid  [1]", self._gridButtons and self._gridButtons[1])
    DescribeButton("dock grid [1]", self._dockButtons and self._dockButtons[1])
    DescribeButton("quick slot[1]", self._quickSlots and self._quickSlots[1])

    print("|cff888888Compare the quick slot with the two grids: it is the one that works.|r")
end

function Toys:GetMixNames()
    local mixes = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyMixes
    local names = {}
    if type(mixes) ~= "table" then return names end

    for name in pairs(mixes) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function Toys:GetToyBox(boxId)
    if boxId == "mixes" then
        local names = self:GetMixNames()
        if #names == 0 then return nil end
        return { id = "mixes", name = "My Mixes", icon = 134064, isMixes = true, toys = names }
    end
    if boxId == "wishlist" then
        -- Every virtual box needs its own branch here. The sidebar lists what
        -- GetToyBoxes returns, but selecting one asks this function for it, and
        -- a box missing from here simply refuses to open when clicked.
        return {
            id = "wishlist",
            name = "Wish List",
            icon = 134153,
            isWishList = true,
            toys = self:GetUncollectedToyIDs(),
        }
    end
    if boxId == "all" then
        return {
            id = "all",
            name = "All Toys",
            icon = 134400,
            isAll = true,
            toys = self:GetAllCollectedToyIDs(),
        }
    elseif boxId == "favorites" then
        local profile = OxedHub.db and OxedHub.db.profile
        local favBox = profile and profile.toyBoxes and profile.toyBoxes["favorites"]
        return {
            id = "favorites",
            name = favBox and favBox.name or "Favorites",
            icon = favBox and favBox.icon or 134400,
            isFavorites = true,
            isDefault = true,
            toys = self:GetFavoriteToyIDs(),
        }
    end

    self:EnsureToyBoxData()
    if not boxId or not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.toyBoxes then return nil end
    return OxedHub.db.profile.toyBoxes[boxId]
end

-- Create a new toybox
function Toys:CreateToyBox(name, icon)
    self:EnsureToyBoxData()
    name = (name or ""):gsub("^%s*(.-)%s*$", "%1")
    if name == "" then return nil, "Box name cannot be empty." end

    local boxId = "box_" .. time() .. "_" .. math.random(100, 999)
    OxedHub.db.profile.toyBoxes[boxId] = {
        id = boxId,
        name = name,
        icon = icon or 135933,
        toys = {},
        createdAt = time(),
    }

    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return boxId
end

-- Delete a toybox
function Toys:DeleteToyBox(boxId)
    if not boxId or boxId == "favorites" or boxId == "all" then return false, "Cannot delete this box." end
    self:EnsureToyBoxData()

    if OxedHub.db.profile.toyBoxes[boxId] then
        OxedHub.db.profile.toyBoxes[boxId] = nil
        if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
        if self.RefreshToyDock then self:RefreshToyDock() end
        return true
    end
    return false
end

-- Rename a toybox or change its icon
function Toys:RenameToyBox(boxId, newName, newIcon)
    if boxId == "all" then return false end
    local box = self:GetToyBox(boxId)
    if not box then return false end

    if newName and newName ~= "" then
        box.name = newName:gsub("^%s*(.-)%s*$", "%1")
    end
    if newIcon then
        box.icon = newIcon
    end

    -- Once the player has named or re-iconed a shipped box it stops tracking the
    -- category definition, so their choice survives the next update.
    box.isShipped = false

    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return true
end

-- Add a toy ID to a box
function Toys:AddToyToBox(boxId, toyId)
    -- The mixes box is rebuilt from the saved mixes on every read, so a write
    -- here would be discarded without a word.
    if boxId == "mixes" then return false, "The My Mixes list cannot be edited here." end
    if boxId == "all" then return false end
    toyId = tonumber(toyId)
    if not toyId then return false, "Invalid toy ID." end

    if boxId == "favorites" then
        if C_ToyBox and C_ToyBox.SetIsFavorite then
            pcall(C_ToyBox.SetIsFavorite, toyId, true)
        end
        local profile = OxedHub.db and OxedHub.db.profile
        if profile and profile.toyBoxes and profile.toyBoxes["favorites"] then
            local favs = profile.toyBoxes["favorites"].toys or {}
            profile.toyBoxes["favorites"].toys = favs
            local exists = false
            for _, id in ipairs(favs) do
                if id == toyId then exists = true break end
            end
            if not exists then table.insert(favs, toyId) end
        end
        if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
        if self.RefreshToyDock then self:RefreshToyDock() end
        return true
    end

    local box = self:GetToyBox(boxId)
    if not box then return false, "Box not found." end

    box.toys = box.toys or {}
    for _, id in ipairs(box.toys) do
        if id == toyId then
            return false, "Toy is already in this box."
        end
    end

    table.insert(box.toys, toyId)
    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return true
end

-- Insert a toy ID at a specific position relative to targetToyId
function Toys:InsertToyInBox(boxId, toyId, targetToyId)
    -- The mixes box is rebuilt from the saved mixes on every read, so a write
    -- here would be discarded without a word.
    if boxId == "mixes" then return false, "The My Mixes list cannot be edited here." end
    if boxId == "all" then return false end
    local box = self:GetToyBox(boxId)
    if not box then return false end
    box.toys = box.toys or {}

    toyId = tonumber(toyId)
    targetToyId = tonumber(targetToyId)
    if not toyId then return false end

    -- If already in box, remove first to prevent duplicates
    for i, id in ipairs(box.toys) do
        if id == toyId then
            table.remove(box.toys, i)
            break
        end
    end

    local tgtIdx = nil
    if targetToyId then
        for i, id in ipairs(box.toys) do
            if id == targetToyId then
                tgtIdx = i
                break
            end
        end
    end

    if tgtIdx then
        table.insert(box.toys, tgtIdx, toyId)
    else
        table.insert(box.toys, toyId)
    end

    if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
    if self.RefreshToyDock then self:RefreshToyDock() end
    return true
end

-- Remove a toy ID from a box
function Toys:RemoveToyFromBox(boxId, toyId)
    -- The mixes box is rebuilt from the saved mixes on every read, so a write
    -- here would be discarded without a word.
    if boxId == "mixes" then return false, "The My Mixes list cannot be edited here." end
    if boxId == "all" then return false end
    toyId = tonumber(toyId)
    if not toyId then return false end

    if boxId == "favorites" then
        if C_ToyBox and C_ToyBox.SetIsFavorite then
            pcall(C_ToyBox.SetIsFavorite, toyId, false)
        end
        local profile = OxedHub.db and OxedHub.db.profile
        if profile and profile.toyBoxes and profile.toyBoxes["favorites"] then
            local favs = profile.toyBoxes["favorites"].toys or {}
            for i, id in ipairs(favs) do
                if id == toyId then
                    table.remove(favs, i)
                    break
                end
            end
        end
        if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
        if self.RefreshToyDock then self:RefreshToyDock() end
        return true
    end

    local box = self:GetToyBox(boxId)
    if not box or not box.toys then return false end

    for i, id in ipairs(box.toys) do
        if id == toyId then
            table.remove(box.toys, i)
            if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
            if self.RefreshToyDock then self:RefreshToyDock() end
            return true
        end
    end
    return false
end

-- Check if toy is in box
function Toys:IsToyInBox(boxId, toyId)
    local box = self:GetToyBox(boxId)
    if not box or not box.toys then return false end
    toyId = tonumber(toyId)
    if not toyId then return false end

    for _, id in ipairs(box.toys) do
        if id == toyId then return true end
    end
    return false
end

-- Reorder toys inside a box
function Toys:ReorderToyInBox(boxId, sourceToyId, targetToyId)
    -- The mixes box is rebuilt from the saved mixes on every read, so a write
    -- here would be discarded without a word.
    if boxId == "mixes" then return false, "The My Mixes list cannot be edited here." end
    if boxId == "all" then return false end
    local box = self:GetToyBox(boxId)
    if not box or not box.toys then return false end

    sourceToyId = tonumber(sourceToyId)
    targetToyId = tonumber(targetToyId)
    if not sourceToyId or not targetToyId or sourceToyId == targetToyId then return false end

    local srcIdx, tgtIdx
    for i, id in ipairs(box.toys) do
        if id == sourceToyId then srcIdx = i end
        if id == targetToyId then tgtIdx = i end
    end

    if srcIdx and tgtIdx and srcIdx ~= tgtIdx then
        table.remove(box.toys, srcIdx)
        table.insert(box.toys, tgtIdx, sourceToyId)
        if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
        if self.RefreshToyDock then self:RefreshToyDock() end
        return true
    end
    return false
end

-- Pick a random toy from a box
function Toys:GetRandomToyFromBox(boxId)
    if self.EnsureToyData then self:EnsureToyData(true) end

    local box = self:GetToyBox(boxId)
    if not box or not box.toys or #box.toys == 0 then return nil end

    -- Cooldown start/duration are "secret" values in combat; comparing one
    -- directly throws. Round-trip through tostring before looking at them.
    local function SafeNum(value)
        local ok, s = pcall(tostring, value)
        if not ok or type(s) ~= "string" then return nil end
        local ok2, n = pcall(tonumber, s)
        return (ok2 and type(n) == "number") and n or nil
    end

    local readyToys = {}
    for _, toyId in ipairs(box.toys) do
        -- The mixes box holds names rather than item IDs. Skipping them here
        -- covers every caller at once, instead of each one having to know which
        -- boxes are safe to roll over.
        if type(toyId) == "number"
            and PlayerHasToy(toyId) and C_ToyBox.IsToyUsable(toyId) then
            local okCd, rawStart, rawDur = pcall(C_Item.GetItemCooldown, toyId)
            local start = okCd and SafeNum(rawStart) or nil
            local duration = okCd and SafeNum(rawDur) or nil
            if not start or start == 0 or not duration or duration <= 0 then
                table.insert(readyToys, toyId)
            end
        end
    end

    if #readyToys > 0 then
        return readyToys[math.random(1, #readyToys)]
    end

    -- Fallback to any usable toy in the box
    local usableToys = {}
    for _, toyId in ipairs(box.toys) do
        if type(toyId) == "number"
            and PlayerHasToy(toyId) and C_ToyBox.IsToyUsable(toyId) then
            table.insert(usableToys, toyId)
        end
    end

    if #usableToys > 0 then
        return usableToys[math.random(1, #usableToys)]
    end

    return box.toys[math.random(1, #box.toys)]
end
