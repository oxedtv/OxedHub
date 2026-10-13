local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

KeystoneLoot.L = setmetatable({}, {
    __index = function(t, key)
        rawset(t, key, key);
        return key;
    end
});
