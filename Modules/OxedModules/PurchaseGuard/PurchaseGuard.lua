-- ============================================================================
-- Purchase Guard (built-in OxedHub module)
-- The "are you sure" popups for buying something you cannot sell back, paying
-- with rare currencies, or spending a lot of gold: the Yes button stays locked
-- for a moment with a countdown, and a red line under the popup says what is
-- at stake. Stops the double-click that buys the wrong thing.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled = false,    -- off until the player switches it on
    lock    = 2,        -- seconds Yes stays locked
}

-- The popups guarded, and the warning shown under each.
local GUARDED = {
    CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = "This cannot be refunded or sold back.",
    CONFIRM_PURCHASE_TOKEN_ITEM = "This is paid with a currency or token.",
    CONFIRM_HIGH_COST_ITEM = "This costs a lot of gold.",
    CONFIRM_PURCHASE_ITEM_DELAYED = "This cannot be refunded or sold back.",
}

local settings
local optionsWindow
local hooked = false
local countdown

local function Guard(which)
    if not (settings and settings.enabled) then return end
    local warning = GUARDED[which]
    if not warning then return end
    local API = OxedHub.ModuleAPI
    local dialog = API and API:FindPopup(which)
    if not dialog then return end
    API:PopupNote(dialog, warning, 1, 0.3, 0.3)

    local button = API:PopupButton(dialog)
    if not button or settings.lock <= 0 then return end
    if countdown then countdown:Cancel() end
    local label = button:GetText()
    local left = math.ceil(settings.lock)
    button:Disable()
    button:SetText(("%s (%d)"):format(label or "", left))
    countdown = C_Timer.NewTicker(1, function(t)
        left = left - 1
        if not dialog:IsShown() then
            t:Cancel()
            button:SetText(label)
            button:Enable()
            return
        end
        if left <= 0 then
            t:Cancel()
            button:SetText(label)
            button:Enable()
        else
            button:SetText(("%s (%d)"):format(label or "", left))
        end
    end, left)
end

local function Hook()
    if hooked then return end
    hooked = true
    -- After the game's own function: the popup exists by then.
    if StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", function(which) Guard(which) end)
    end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Purchase Guard", 420, 170)
        optionsWindow:AddSlider(settings, "lock", "Yes stays locked for", 0, 5, 1, "%s: %d s")
        optionsWindow:AddNote("For purchases that cannot be refunded, paid with tokens, or costing a lot of gold.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.purchaseguard
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.purchaseguard = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "purchaseguard",
        name     = "Purchase Guard",
        version  = "1.0.0",
        author   = "Oxed",
        category = "items",
        keywords = { "buy", "purchase", "refund", "vendor", "confirm", "mistake" },
        desc     = "Locks Yes for a moment on purchases you cannot undo, and says why.",
        icon     = "Interface\\Icons\\INV_Misc_Coin_02",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        -- The hook stays once made (hooks cannot be removed); it does
        -- nothing while the module is off.
        OnEnable = function(_, cfg) settings = cfg; Hook() end,
        OnDisable = function() end,
    })
end)
