-- ============================================================================
-- Bulk Buy (built-in OxedHub module)
-- Shift-click an item at a vendor to buy as many as you like: type a number,
-- or press Stack (one full stack) or Max (as many as you can afford, carry and
-- the vendor has). The total cost is shown before you buy, and a big
-- purchase asks once more.
--
-- The game's own Shift-click opens a small "how many" box that stops at one
-- stack. We hook the click (never replace it) and swap that box for ours.
-- Purchases go out one stack at a time, spaced, like every other per-slot
-- action in OxedHub: a burst is partly dropped by the server with no error.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled  = false,   -- off until the player switches it on
    confirmGold = 100,  -- ask again above this many gold (0 = never)
}

local STEP = 0.25       -- seconds between purchases

local settings
local optionsWindow
local window
local current           -- { index, link, name, icon, unitPrice, bundle, maxStack, ... }
local buying            -- ticker while a purchase runs
local hooked = false

-- ── What the vendor's item is ──────────────────────────────────────────────

local function ItemInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if info then return info end
    end
    local name, texture, price, stackCount, numAvailable, isPurchasable, isUsable, extendedCost = GetMerchantItemInfo(index)
    return { name = name, texture = texture, price = price, stackCount = stackCount,
        numAvailable = numAvailable, isPurchasable = isPurchasable, hasExtendedCost = extendedCost }
end

-- How many of the item fit in the bags as they are now.
local function RoomFor(itemID, stackSize)
    if not itemID then return math.huge end
    local free = 0
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if not info then
                free = free + stackSize
            elseif info.itemID == itemID and stackSize > 1 then
                free = free + math.max(0, stackSize - (info.stackCount or 0))
            end
        end
    end
    return free
end

local function IsCurrencyLink(link)
    return type(link) == "string" and link:find("currency:", 1, true) ~= nil
end

local function CurrencyFromLink(link)
    if not (C_CurrencyInfo and link) then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink and C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    if not info and C_CurrencyInfo.GetCurrencyInfo then
        local id = tonumber(link:match("currency:(%d+)"))
        info = id and C_CurrencyInfo.GetCurrencyInfo(id)
    end
    return info
end

-- How much of one price entry the player has. The link says which kind it
-- is: the fourth return of GetMerchantItemCostItem is not a reliable sign,
-- and reading an item as a currency (or the other way) gave 0, which made
-- every currency purchase look unaffordable.
local function Owned(link)
    if IsCurrencyLink(link) then
        local info = CurrencyFromLink(link)
        return info and info.quantity or nil
    end
    return C_Item.GetItemCount(link, true, false, true, true) or 0
end

-- How many you can pay for: gold, and each currency or item it also costs.
local function Affordable(index, item)
    local most = math.huge
    local bundle = math.max(1, item.stackCount or 1)
    if item.price and item.price > 0 then
        most = math.floor(GetMoney() / item.price) * bundle
    end
    local costs = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
    for i = 1, costs do
        local _, value, link = GetMerchantItemCostItem(index, i)
        -- Without a link the game has not told us yet; let the server decide.
        if value and value > 0 and link then
            local owned = Owned(link)
            if owned then most = math.min(most, math.floor(owned / value) * bundle) end
        end
    end
    return most
end

local function MaxFor(c)
    local most = math.min(c.afford, c.room)
    if c.available and c.available >= 0 then most = math.min(most, c.available * c.bundle) end
    return math.max(0, most)
end

-- ── The window ─────────────────────────────────────────────────────────────

local function CostText(amount)
    local bundles = math.ceil(amount / current.bundle)
    local parts = {}
    if current.price and current.price > 0 then
        parts[#parts + 1] = GetMoneyString(current.price * bundles, true)
    end
    local costs = GetMerchantItemCostInfo and GetMerchantItemCostInfo(current.index) or 0
    for i = 1, costs do
        local texture, value = GetMerchantItemCostItem(current.index, i)
        if value and value > 0 then
            parts[#parts + 1] = ("%d |T%s:14|t"):format(value * bundles, tostring(texture or 134400))
        end
    end
    return #parts > 0 and table.concat(parts, "  ") or "free"
end

local function Amount()
    local n = tonumber(window.amount:GetText() or "") or 0
    n = math.floor(n)
    -- Bundles only: a vendor selling five at a time sells fives.
    if current.bundle > 1 then n = math.floor(n / current.bundle) * current.bundle end
    return math.max(0, n)
end

local function Refresh()
    if not current then return end
    local n = Amount()
    window.cost:SetText(CostText(n))
    window.buy:SetEnabled(n > 0 and n <= MaxFor(current) and not buying)
    window.buy:SetText(window.confirming and "Really?" or (OKAY or "Okay"))
end

local function StopBuying()
    if buying then buying:Cancel(); buying = nil end
end

-- Buys `amount`, a stack (or what is left) at a time, spaced.
local function Purchase(amount)
    StopBuying()
    local index, left = current.index, amount
    local perCall = math.max(1, current.maxStack)
    -- A currency has no stacks: the whole amount goes in one call.
    if current.isCurrency then perCall = amount end
    buying = C_Timer.NewTicker(STEP, function()
        if left <= 0 or not (MerchantFrame and MerchantFrame:IsShown()) then
            StopBuying()
            if window then window:Hide() end
            return
        end
        local now = math.min(left, perCall)
        BuyMerchantItem(index, now)
        left = left - now
    end)
end

local function SetAmount(n)
    n = math.max(current.bundle, math.min(n, math.max(current.bundle, MaxFor(current))))
    window.amount:SetText(tostring(n))
end

-- Small and square like the game's own "how many" box: the number with an
-- arrow each side, the cost under it, then Stack / Max and Okay / Cancel.
local function BuildWindow()
    if window then return end
    local w = CreateFrame("Frame", "OxedHubBulkBuy", UIParent, "BackdropTemplate")
    w:SetSize(196, 132)
    -- Above the vendor window and its portrait.
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    w:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    w:SetBackdropBorderColor(0.75, 0.75, 0.75, 1)

    -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard at once.
    w.amount = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    w.amount:SetAutoFocus(false)
    w.amount:SetSize(116, 28)
    w.amount:SetPoint("TOP", w, "TOP", 0, -14)
    w.amount:SetFontObject(GameFontHighlightLarge)
    w.amount:SetJustifyH("RIGHT")
    w.amount:SetTextInsets(0, 8, 0, 0)
    w.amount:SetNumeric(true)
    w.amount:SetScript("OnTextChanged", function() w.confirming = nil; Refresh() end)
    w.amount:SetScript("OnEnterPressed", function() w.buy:Click() end)
    w.amount:SetScript("OnEscapePressed", function() w:Hide() end)

    local function Arrow(side, delta)
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(22, 24)
        b:SetText(side == "LEFT" and "<" or ">")
        if side == "LEFT" then
            b:SetPoint("RIGHT", w.amount, "LEFT", -6, 0)
        else
            b:SetPoint("LEFT", w.amount, "RIGHT", 2, 0)
        end
        -- Shift steps a whole stack at a time.
        b:SetScript("OnClick", function()
            local step = IsShiftKeyDown() and current.maxStack or current.bundle
            SetAmount(Amount() + delta * step)
        end)
    end
    Arrow("LEFT", -1)
    Arrow("RIGHT", 1)

    w.cost = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.cost:SetPoint("TOP", w.amount, "BOTTOM", 0, -6)

    local function Button(text, point, x, y, onClick)
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(84, 24)
        b:SetPoint(point, w, point, x, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    local stack = Button("Stack", "BOTTOMLEFT", 12, 42, function()
        SetAmount(current.maxStack)
    end)
    stack:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("One stack: %d"):format(current.maxStack))
        GameTooltip:Show()
    end)
    stack:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local max = Button("Max", "BOTTOMRIGHT", -12, 42, function()
        SetAmount(MaxFor(current))
    end)
    max:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("As many as you can: %d"):format(MaxFor(current)))
        GameTooltip:AddLine("What you can afford, carry and the vendor has.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    max:SetScript("OnLeave", function() GameTooltip:Hide() end)

    w.buy = Button(OKAY or "Okay", "BOTTOMLEFT", 12, 14, function()
        local n = Amount()
        if n <= 0 then return end
        local gold = (current.price or 0) * math.ceil(n / current.bundle) / 10000
        if settings.confirmGold > 0 and gold >= settings.confirmGold and not w.confirming then
            w.confirming = true
            Refresh()
            return
        end
        w.confirming = nil
        w.amount:ClearFocus()
        Purchase(n)
        Refresh()
    end)
    Button(CANCEL or "Cancel", "BOTTOMRIGHT", -12, 14, function() w:Hide() end)

    w:SetScript("OnHide", function()
        w.amount:ClearFocus()
        w.confirming = nil
    end)
    w:Hide()
    window = w
end

local function Open(index, owner)
    local item = ItemInfo(index)
    if not (item and item.name) then return false end
    local link = GetMerchantItemLink(index)
    local isCurrency = IsCurrencyLink(link)
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local itemID = link and not isCurrency and instant and instant(link)
    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)) or 1
    local itemStack = (itemID and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(itemID)) or maxStack
    current = {
        index = index, name = item.name, icon = item.texture, price = item.price,
        bundle = math.max(1, item.stackCount or 1), maxStack = math.max(1, maxStack),
        available = item.numAvailable, isCurrency = isCurrency,
    }
    current.afford = Affordable(index, item)
    if isCurrency then
        -- Room for a currency is what is left under its cap (0 = no cap).
        local info = CurrencyFromLink(link)
        local cap = info and info.maxQuantity or 0
        current.room = cap > 0 and math.max(0, cap - (info.quantity or 0)) or math.huge
        current.maxStack = math.max(current.maxStack, current.bundle)
    else
        current.room = RoomFor(itemID, math.max(1, itemStack or 1))
    end

    BuildWindow()
    window:ClearAllPoints()
    -- Over the item that was clicked, where the game's own box would open.
    if owner then
        window:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    else
        window:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 8, 0)
    end
    window.confirming = nil
    window.amount:SetText(tostring(current.bundle))
    window:Show()
    window.amount:SetFocus()
    window.amount:HighlightText()
    Refresh()
    return true
end

-- ── The hook ───────────────────────────────────────────────────────────────

local function OnModifiedClick(frame, button)
    if not (settings and settings.enabled) then return end
    if button ~= "LeftButton" or not IsShiftKeyDown() then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    -- The buyback tab is not a vendor list.
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then return end
    local index = frame and frame.GetID and frame:GetID()
    if not index or index <= 0 then return end
    if Open(index, frame) and StackSplitFrame and StackSplitFrame:IsShown() then
        StackSplitFrame:Hide()
    end
end

-- The game's own "how many" box opening over a vendor item: the click route
-- has moved between builds, so this catches it whichever way it came.
local function IsMerchantItemButton(frame)
    local name = frame and frame.GetName and frame:GetName()
    return type(name) == "string" and name:match("^MerchantItem%d+ItemButton$") ~= nil
end

local function OnStackSplitShown(splitFrame)
    if not (settings and settings.enabled) then return end
    if not (MerchantFrame and MerchantFrame:IsShown()) then return end
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then return end
    local owner = splitFrame.owner
    if not IsMerchantItemButton(owner) then return end
    local index = owner:GetID()
    if index and index > 0 and Open(index, owner) then splitFrame:Hide() end
end

local function Hook()
    if hooked then return end
    hooked = true
    if MerchantItemButton_OnModifiedClick then
        hooksecurefunc("MerchantItemButton_OnModifiedClick", OnModifiedClick)
    end
    if StackSplitFrame then
        StackSplitFrame:HookScript("OnShow", OnStackSplitShown)
    end
end

local merchantFrame = CreateFrame("Frame")
merchantFrame:SetScript("OnEvent", function()
    StopBuying()
    if window then window:Hide() end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Bulk Buy", 440, 200)
        optionsWindow:AddSlider(settings, "confirmGold", "Ask again above", 0, 5000, 50, "%s: %d gold (0 = never)")
        optionsWindow:AddNote("Shift-click an item at a vendor. Type how many, or press Stack or Max. "
            .. "Max is what you can afford, carry and the vendor has.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bulkbuy
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bulkbuy = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bulkbuy",
        name     = "Bulk Buy",
        version  = "1.0.0",
        author   = "Oxed",
        category = "items",
        keywords = { "buy", "vendor", "merchant", "bulk", "stack", "max", "shift" },
        desc     = "Shift-click a vendor item to buy any amount: Stack, Max, and the total cost.",
        icon     = "Interface\\Icons\\INV_Misc_Bag_08",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        -- The click hook stays once made; it does nothing while off.
        OnEnable = function(_, cfg)
            settings = cfg
            Hook()
            merchantFrame:RegisterEvent("MERCHANT_CLOSED")
        end,
        OnDisable = function()
            merchantFrame:UnregisterAllEvents()
            StopBuying()
            if window then window:Hide() end
        end,
    })
end)
