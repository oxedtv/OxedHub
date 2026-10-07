-- ============================================================================
-- Fast Loot (built-in OxedHub module)
-- Takes everything the moment the loot window opens, instead of one item per
-- frame as the game's auto loot does. It follows the game's own auto loot
-- setting and its modifier key: when the game would not auto loot, neither
-- does this.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled  = false,   -- off until the player switches it on
    hideWindow = true,  -- keep the loot window from flashing up
}

local settings
local optionsWindow
local frame = CreateFrame("Frame")
local lastRun = 0

local function WantsAutoLoot()
    local auto = GetCVarBool and GetCVarBool("autoLootDefault")
    local toggled = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")
    return (auto and not toggled) or (not auto and toggled)
end

frame:SetScript("OnEvent", function(_, event)
    if event ~= "LOOT_READY" or not settings or not settings.enabled then return end
    -- The event can come twice for one window.
    local now = GetTime()
    if now - lastRun < 0.3 then return end
    lastRun = now
    if not WantsAutoLoot() then return end
    for slot = GetNumLootItems(), 1, -1 do
        LootSlot(slot)
    end
    if settings.hideWindow and LootFrame and LootFrame:IsShown() then
        -- Only when nothing is left: a full bag keeps the window up.
        if GetNumLootItems() == 0 then LootFrame:Hide() end
    end
end)

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Fast Loot", 420, 180)
        optionsWindow:AddCheckbox(settings, "hideWindow", "Keep the loot window hidden",
            "It still opens when something could not be taken, a full bag for example.")
        optionsWindow:AddNote("Works with the game's auto loot setting and its key: hold it to loot by hand.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.fastloot
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.fastloot = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "fastloot",
        name     = "Fast Loot",
        version  = "1.0.0",
        author   = "Oxed",
        category = "items",
        keywords = { "loot", "fast", "auto", "speed" },
        desc     = "Takes all the loot at once, the moment the window opens.",
        icon     = "Interface\\Icons\\INV_Misc_Bag_10_Green",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg) settings = cfg; frame:RegisterEvent("LOOT_READY") end,
        OnDisable = function() frame:UnregisterEvent("LOOT_READY") end,
    })
end)
