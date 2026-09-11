-- ============================================================================
-- Auto Vendor (built-in OxedHub module)
-- Opening a vendor sells your grey items and repairs your gear, then says in
-- chat what it did and what it cost.
--
-- Junk goes first and the repair waits a moment behind it, so the gold the junk
-- brought in is already there to pay for the repair.
--
-- Hold Shift while opening the vendor to skip both, for the times you want to
-- look before anything is sold.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled     = true,
    repair      = true,
    guildFunds  = true,    -- try the guild bank before your own gold
    sellJunk    = true,
    report      = true,    -- one line in chat saying what happened
}

local settings          -- OxedHubDB.modules.autovendor, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "

local function Money(amount)
    if GetMoneyString then return GetMoneyString(amount, true) end
    if GetCoinTextureString then return GetCoinTextureString(amount) end
    return tostring(amount)
end

-- ── Junk ────────────────────────────────────────────────────────────────────

local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- What the grey items in the bags are worth, and how many there are. Worked out
-- before they are sold, because afterwards there is nothing left to count.
-- An item the client has not cached yet has no known price and is counted but
-- not valued, so the figure errs low rather than inventing a number.
local function SurveyJunk()
    local count, value = 0, 0
    if not (C_Container and C_Container.GetContainerNumSlots) then return count, value end

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == POOR and not info.hasNoValue then
                count = count + 1
                local link = info.hyperlink
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local price = link and getInfo and select(11, getInfo(link))
                if price and price > 0 then
                    value = value + price * (info.stackCount or 1)
                end
            end
        end
    end
    return count, value
end

-- Returns how many were sold and what they were worth.
local function SellJunk()
    local count, value = SurveyJunk()
    if count == 0 then return 0, 0 end

    -- The game's own "sell all junk", when this client has it and allows it
    -- right now -- the same action as the button on the merchant window.
    if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        local allowed = not C_MerchantFrame.IsSellAllJunkEnabled
            or C_MerchantFrame.IsSellAllJunkEnabled()
        if allowed then
            C_MerchantFrame.SellAllJunkItems()
            return count, value
        end
        return 0, 0
    end

    -- Clients without it: sell each grey item by using it at the vendor.
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == POOR and not info.hasNoValue then
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end
    return count, value
end

-- ── Repair ──────────────────────────────────────────────────────────────────

-- Whether the guild bank can cover this. What you may withdraw today is the
-- limit that matters, not what the bank holds; -1 means no limit at all.
local function GuildCanPay(cost)
    if not (settings.guildFunds and IsInGuild and IsInGuild()) then return false end
    if not (CanGuildBankRepair and CanGuildBankRepair()) then return false end
    local allowance = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
    if allowance == nil then return false end
    return allowance == -1 or allowance >= cost
end

-- Calls done() with how much it cost and who paid, or with nothing when there
-- was nothing to do. A guild repair can still be refused by the server -- the
-- bank ran dry since the allowance was read -- so it is checked a moment later
-- and, if the gear is still damaged, paid from your own gold instead.
local function Repair(done)
    if not (CanMerchantRepair and CanMerchantRepair()) then return done() end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then return done() end

    if GuildCanPay(cost) then
        RepairAllItems(true)
        C_Timer.After(0.5, function()
            local left = GetRepairAllCost()
            if left and left > 0 then
                if GetMoney() >= left then
                    RepairAllItems()
                    done(left, "own", cost - left)
                else
                    done(nil, "short", left)
                end
            else
                done(cost, "guild")
            end
        end)
        return
    end

    if GetMoney() >= cost then
        RepairAllItems()
        done(cost, "own")
    else
        done(nil, "short", cost)
    end
end

-- ── At the vendor ───────────────────────────────────────────────────────────

local function OnMerchantShow()
    if not settings or settings.enabled == false then return end
    if IsShiftKeyDown() then return end

    local soldCount, soldValue = 0, 0
    if settings.sellJunk then
        soldCount, soldValue = SellJunk()
    end

    -- Give the sale a moment to land before paying for anything.
    C_Timer.After(soldCount > 0 and 0.3 or 0, function()
        local function Report(repairCost, payer, extra)
            if not settings.report then return end
            local parts = {}
            if soldCount > 0 then
                if soldValue > 0 then
                    parts[#parts + 1] = ("sold %d junk item(s) for %s"):format(soldCount, Money(soldValue))
                else
                    parts[#parts + 1] = ("sold %d junk item(s)"):format(soldCount)
                end
            end
            if payer == "guild" then
                parts[#parts + 1] = ("repaired for %s from guild funds"):format(Money(repairCost))
            elseif payer == "own" then
                if extra and extra > 0 then
                    parts[#parts + 1] = ("repaired for %s (%s from the guild, the rest yours)"):format(
                        Money(repairCost + extra), Money(extra))
                else
                    parts[#parts + 1] = ("repaired for %s"):format(Money(repairCost))
                end
            elseif payer == "short" then
                parts[#parts + 1] = ("|cffff5555not enough gold to repair|r (%s needed)"):format(Money(extra))
            end
            if #parts > 0 then print(PREFIX .. table.concat(parts, ", ") .. ".") end
        end

        if settings.repair then
            Repair(Report)
        else
            Report()
        end
    end)
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then OnMerchantShow() end
end)

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autovendor
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autovendor = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Auto Vendor", 400, 240)
        optionsWindow:AddCheckbox(settings, "sellJunk", "Sell junk (grey items)",
            "Everything grey in your bags is sold when a vendor opens.")
        optionsWindow:AddCheckbox(settings, "repair", "Repair gear",
            "Repairs everything when the vendor can repair.")
        optionsWindow:AddCheckbox(settings, "guildFunds", "Use guild funds first",
            "Pays with the guild bank when your rank allows it and today's allowance covers the cost, and falls back to your own gold otherwise.")
        optionsWindow:AddCheckbox(settings, "report", "Say what was done in chat",
            "One line after each vendor visit: what was sold and what the repair cost.")
        optionsWindow:AddNote("Hold Shift while opening a vendor to skip it for that visit.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled ~= false then watcher:RegisterEvent("MERCHANT_SHOW") end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autovendor",
        name     = "Auto Vendor",
        version  = "1.0.0",
        author   = "Oxed",
        category = "inventory",
        desc     = "Sells your junk and repairs your gear whenever you open a vendor. Hold Shift to skip.",
        icon     = "Interface\\Icons\\INV_Misc_Coin_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            watcher:RegisterEvent("MERCHANT_SHOW")
        end,

        OnDisable = function()
            watcher:UnregisterEvent("MERCHANT_SHOW")
        end,
    })
end)
