-- Instantiating addon-owned frames directly from XML taints the retail 12.0.7
-- Blizzard_DamageMeter secret-value execution path. Keep XML definitions
-- virtual and create the five runtime frames from Lua instead.
CreateFrame("Frame", "OxMythicLooterFrame", UIParent, "OxMythicLooterFrameTemplate");
CreateFrame("Button", "OxMythicLooterMinimapButton", Minimap, "OxMythicLooterMinimapButtonTemplate");
CreateFrame("Frame", "OxMythicLooterReminderFrame", UIParent, "OxMythicLooterReminderFrameTemplate");
CreateFrame("Frame", "OxMythicLooterDropNotificationFrame", UIParent, "OxMythicLooterDropNotificationFrameTemplate");
CreateFrame("Frame", "OxMythicLooterMythicPlusNotificationFrame", UIParent, "OxMythicLooterMythicPlusNotificationFrameTemplate");

MythicLooterFrame = OxMythicLooterFrame;

