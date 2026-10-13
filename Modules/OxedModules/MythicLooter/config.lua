local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

KeystoneLoot.Config = {
    season         = 17, -- Used to detect season changes and wipe favorites
    expansionName  = EXPANSION_NAME11,
    seasonNumber   = 2,
    whisperMessage = "Hi! Any chance I could get {item} if you don't need it? Thanks a lot either way!",
};
