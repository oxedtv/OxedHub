local addonName, OxedHub = ...

-- Mounts Module
-- Single source of truth for the player's collected-mount list. Scanning the
-- whole mount journal (GetMountInfoByID for every mount) is expensive, so we do
-- it ONCE, persist the result in SavedVariables (OxedHubDB.mountCache), and
-- reuse it every session afterwards. When the player collects a new mount they
-- press a "Refresh Mounts" button, which forces a rebuild.
local Mounts = {}
OxedHub.Mounts = Mounts

-- Build the collected-mount list straight from the journal.
-- Returns an array of:
--   { type="mount", id=<mountID>, spellID=<spellID>, name=, icon=, isFavorite= }
-- NOTE: `id` is the mountID (what C_MountJournal.SummonByID needs); `spellID`
-- is kept for tooltips (GameTooltip:SetMountBySpellID).
local function BuildMountList()
    local items = {}
    if not (C_MountJournal and C_MountJournal.GetMountIDs) then
        return items
    end
    local ok, mountIDs = pcall(C_MountJournal.GetMountIDs)
    if not ok or not mountIDs then
        return items
    end
    for _, mountID in ipairs(mountIDs) do
        local ok2, name, spellID, icon, _isActive, _isUsable, _sourceType, isFavorite,
              _isFactionSpecific, _faction, shouldHideOnChar, isCollected =
              pcall(C_MountJournal.GetMountInfoByID, mountID)
        if ok2 and isCollected and not shouldHideOnChar and name and spellID and icon then
            items[#items + 1] = {
                type = "mount",
                id = mountID,
                spellID = spellID,
                name = name,
                icon = icon,
                isFavorite = isFavorite or false,
            }
        end
    end
    table.sort(items, function(a, b)
        if a.isFavorite ~= b.isFavorite then return a.isFavorite end
        return a.name < b.name
    end)
    return items
end

-- Rebuild (when forced or no cache yet) and persist in SavedVariables.
-- Guards against wiping a good cache with an empty rebuild (journal not ready).
function Mounts:CacheMountData(force)
    local db = OxedHub.db
    if not force and db and db.mountCache and #db.mountCache > 0 then
        return db.mountCache
    end

    local items = BuildMountList()
    if db then
        if #items > 0 or not db.mountCache then
            db.mountCache = items
        end
        return db.mountCache
    end
    return items
end

-- Primary accessor used by OxedRing + ActionHub.
-- First call builds + persists; later sessions reuse the saved list.
-- Pass forceRefresh = true (the Refresh Mounts button) to rescan.
function Mounts:GetMounts(forceRefresh)
    return self:CacheMountData(forceRefresh)
end

-- How many mounts are currently cached (without forcing a build).
function Mounts:GetCount()
    local db = OxedHub.db
    return (db and db.mountCache and #db.mountCache) or 0
end
