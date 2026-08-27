local addonName, OxedHub = ...

local Toys = OxedHub.Toys or {}
OxedHub.Toys = Toys
local L = OxedHub.L

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
function Toys:ReorderBox(draggedId, targetId)
    if not draggedId or not targetId or draggedId == targetId then return end
    -- These two are fixed positions, never part of the user order.
    if draggedId == "all" or draggedId == "favorites" then return end
    if targetId == "all" or targetId == "favorites" then return end

    local order = self:GetBoxOrder()

    -- Seed from the current on-screen order the first time something is moved,
    -- so a drag does not scramble everything that had no saved position.
    if #order == 0 then
        for _, box in ipairs(self:GetToyBoxes()) do
            if box.id ~= "all" and box.id ~= "favorites" then
                table.insert(order, box.id)
            end
        end
    end

    local from, to
    for i, id in ipairs(order) do
        if id == draggedId then from = i end
        if id == targetId then to = i end
    end
    if not from or not to then return end

    table.remove(order, from)
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
        local _, toyName = C_ToyBox.GetToyInfo(toyId)
        if toyName and toyName:lower():find(needle, 1, true) then
            table.insert(out, toyId)
        elseif tostring(toyId):find(needle, 1, true) then
            -- Searching by item id is handy when a name is not cached yet.
            table.insert(out, toyId)
        end
    end
    return out
end

-- Toys the user wants visible at all times, kept at the front of the grid.
function Toys:GetPinnedToys()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return {} end
    profile.toyBoxPinned = profile.toyBoxPinned or {}
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
    for _, category in ipairs(OxedHub.TOY_CATEGORIES) do
        local box = profile.toyBoxes and profile.toyBoxes["default_" .. category.key]
        if box and box.isShipped ~= false then
            box.isShipped = true
            box.name = category.name
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

        table.sort(userBoxes, function(a, b)
            if a.id == "favorites" then return true end
            if b.id == "favorites" then return false end

            local ra, rb = rank[a.id], rank[b.id]
            if ra and rb then return ra < rb end
            if ra then return true end
            if rb then return false end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)

        for _, box in ipairs(userBoxes) do
            table.insert(boxes, box)
        end
    end

    return boxes
end

-- Get a specific toybox by ID
function Toys:GetToyBox(boxId)
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
        if PlayerHasToy(toyId) and C_ToyBox.IsToyUsable(toyId) then
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
        if PlayerHasToy(toyId) and C_ToyBox.IsToyUsable(toyId) then
            table.insert(usableToys, toyId)
        end
    end

    if #usableToys > 0 then
        return usableToys[math.random(1, #usableToys)]
    end

    return box.toys[math.random(1, #box.toys)]
end
