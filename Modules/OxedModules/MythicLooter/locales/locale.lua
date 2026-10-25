local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

-- A line the game client's language file has no translation for is looked up
-- in OxedHub's own dictionary, which follows the language chosen in OxedHub's
-- settings rather than the client's. Not cached: that dictionary is only
-- filled at login, and is filled again when the player switches language.
KeystoneLoot.L = setmetatable({}, {
    __index = function(t, key)
        if (OxedHub.languageApplied and OxedHub.T) then
            return OxedHub.T(key);
        end
        return key;
    end
});
