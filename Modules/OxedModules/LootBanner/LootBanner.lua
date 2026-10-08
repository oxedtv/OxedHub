-- ============================================================================
-- Loot Banner (built-in OxedHub module)
-- The banner across the top of the screen after a boss, listing what everyone
-- looted, is trimmed to what you want: none when you are alone, only items of
-- a good enough quality, or only your own.
--
-- The banner's events go through a filter of ours on the way in; switching
-- the module off hands the banner its own handler back.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled    = false,  -- off until the player switches it on
    hideSolo   = true,
    minQuality = 3,      -- 2 green, 3 blue, 4 epic
    onlyMine   = false,
    hideKill   = false,  -- also the "boss defeated" banner
    moveIt     = false,  -- put the banner where the player dragged the box
}

local settings
local optionsWindow
local original
local marker              -- the box shown while options are open
local hooked = false

-- ── Where the banner goes ──────────────────────────────────────────────────
-- The game puts it at the top of the screen. With moveIt on, it is moved
-- each time it shows, to where the player left the box.
local function PlaceBanner()
    if not (settings and settings.enabled and settings.moveIt and BossBanner) then return end
    BossBanner:ClearAllPoints()
    BossBanner:SetPoint("TOP", UIParent, "BOTTOMLEFT", settings.bannerX or (UIParent:GetWidth() / 2),
        settings.bannerY or (UIParent:GetHeight() - 120))
end

local function BuildMarker()
    if marker then return end
    marker = CreateFrame("Frame", "OxedHubLootBannerBox", UIParent)
    marker:SetSize(400, 120)
    marker:SetFrameStrata("HIGH")
    marker:SetClampedToScreen(true)
    marker:SetMovable(true)
    marker:EnableMouse(true)
    marker:RegisterForDrag("LeftButton")
    marker:SetScript("OnDragStart", marker.StartMoving)
    marker:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        settings.bannerX = self:GetLeft() + self:GetWidth() / 2
        settings.bannerY = self:GetTop()
        settings.moveIt = true
        PlaceBanner()
    end)
    local bg = marker:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0.6, 1, 0.25)
    local text = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("CENTER")
    text:SetText("Loot Banner: drag me\nYour loot banner shows here")
    marker:Hide()
end

local function ShowMarker(show)
    BuildMarker()
    if not show then marker:Hide(); return end
    marker:ClearAllPoints()
    marker:SetPoint("TOP", UIParent, "BOTTOMLEFT", settings.bannerX or (UIParent:GetWidth() / 2),
        settings.bannerY or (UIParent:GetHeight() - 120))
    marker:Show()
end

local function Wanted(event, ...)
    if event == "BOSS_KILL" then return not settings.hideKill end
    if event ~= "ENCOUNTER_LOOT_RECEIVED" then return true end
    if settings.hideSolo and not IsInGroup() then return false end
    local _, itemID, itemLink, _, playerName = ...
    if settings.onlyMine then
        local me = UnitName("player")
        if type(playerName) == "string" and not (issecretvalue and issecretvalue(playerName))
            and Ambiguate(playerName, "short") ~= me then
            return false
        end
    end
    local ok, quality = pcall(C_Item.GetItemQualityByID, itemLink or itemID)
    if ok and type(quality) == "number" and quality < settings.minQuality then return false end
    return true
end

local function Filter(frame, event, ...)
    if settings and settings.enabled and not Wanted(event, ...) then return end
    return original(frame, event, ...)
end

local function Start()
    if BossBanner and not hooked then
        hooked = true
        BossBanner:HookScript("OnShow", PlaceBanner)
    end
    if not BossBanner or original then return end
    original = BossBanner:GetScript("OnEvent")
    if original then BossBanner:SetScript("OnEvent", Filter) end
end

local function Stop()
    if BossBanner and original then BossBanner:SetScript("OnEvent", original) end
    original = nil
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Loot Banner", 440, 360)
        optionsWindow = w
        w:AddCheckbox(settings, "hideSolo", "None when you are alone")
        w:AddChoice(settings, "minQuality", "Items at least", {
            { value = 0, text = "Any" }, { value = 2, text = "Uncommon" },
            { value = 3, text = "Rare" }, { value = 4, text = "Epic" },
        })
        w:AddCheckbox(settings, "onlyMine", "Only what you loot")
        w:AddCheckbox(settings, "hideKill", "Hide the boss defeated banner too")
        w:AddCheckbox(settings, "moveIt", "Show it where I put it",
            "Drag the blue box while this window is open. Off, the game's place at the top.")
        local reset = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        reset:SetSize(170, 22)
        reset:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        reset:SetText("Back to the top")
        reset:SetScript("OnClick", function()
            settings.bannerX, settings.bannerY, settings.moveIt = nil, nil, false
            ShowMarker(true)
            if w.checks then for _, box in ipairs(w.checks) do box.Refresh() end end
        end)
        w.cursorY = w.cursorY - 32
        w:AddNote("While this window is open, the blue box shows where the banner will appear.")
        w:HookScript("OnShow", function() ShowMarker(true) end)
        w:HookScript("OnHide", function() ShowMarker(false) end)
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.lootbanner
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.lootbanner = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "lootbanner",
        name     = "Loot Banner",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "loot", "banner", "boss", "raid", "spam" },
        desc     = "Trims the boss loot banner: none solo, only good items, or only yours.",
        icon     = "Interface\\Icons\\INV_Misc_Bag_CenarionHerbBag",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
