-- ============================================================================
-- Auto Vendor (built-in OxedHub module)
-- Opening a vendor sells your grey items, anything else you have put on your
-- sell list, and repairs your gear, then says in chat what it did and what it
-- cost.
--
-- The sell list is for the things that are not grey but always go: old tier
-- tokens, a crafting leftover you never use, a quest reward you keep getting.
-- Drop an item on the box in Options, or type its ID, and it is sold from then
-- on. Each item shows as an icon, and clicking the icon takes it off again.
--
-- Selling goes first and the repair waits behind it, so the gold the sale
-- brought in is already there to pay for the repair.
--
-- An optional switch lets holding Shift while opening the vendor skip all of it,
-- for the times you want to look before anything is sold. It is off by default.
-- ============================================================================

local addonName, OxedHub = ...

-- ⚠ No tables here: ModuleAPI copies defaults by reference, so a list default
-- would have every edit written into DEFAULTS. The sell list is made in
-- EnsureData.
local DEFAULTS = {
    enabled     = false,  -- off until the player switches it on (see ModuleAPI:Register)
    shiftSkip   = false,   -- holding Shift skips the module for that moment (player's choice)
    repair      = true,
    guildFunds  = true,    -- try the guild bank before your own gold
    sellJunk    = true,
    sellList    = true,    -- also sell the items on the player's own list
    report      = true,    -- one line in chat saying what happened
    confirm     = false,   -- ask with a Yes / No popup before doing any of it
}

local settings          -- OxedHubDB.modules.autovendor, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "

-- Each sale is its own server call. Sent in one burst, some are dropped and the
-- dropped items stay in the bags with no error to say so.
local SELL_STEP = 0.2

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function Money(amount)
    if GetMoneyString then return GetMoneyString(amount, true) end
    if GetCoinTextureString then return GetCoinTextureString(amount) end
    return tostring(amount)
end

local function EnsureData()
    settings.items = type(settings.items) == "table" and settings.items or {}
end

local function GetInfo(item)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not getInfo then return nil end
    return getInfo(item)
end

local function SellPrice(item)
    return select(11, GetInfo(item))
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
                local price = info.hyperlink and SellPrice(info.hyperlink)
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
    end

    -- Clients without it, or where the button is switched off: sell each grey
    -- item by using it at the vendor.
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

-- ── The sell list ───────────────────────────────────────────────────────────

-- Bag slots holding an item from the list that a vendor will pay for. Grey
-- items are left out when junk selling is on, so nothing is counted twice.
local function CollectListed()
    local picks = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return picks end

    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and settings.items[info.itemID]
                and not info.hasNoValue and not info.isLocked
                and not (settings.sellJunk and info.quality == POOR) then
                local price = SellPrice(info.itemID) or 0
                picks[#picks + 1] = {
                    bag = bag, slot = slot, itemID = info.itemID, info = info,
                    value = price * (info.stackCount or 1),
                }
            end
        end
    end
    return picks
end

-- Sells the list one slot at a time and calls done(count, value). Each step
-- makes sure the vendor is still open and the slot still holds the same item:
-- bags shift as things stack, and a sale sent to the wrong slot sells the
-- wrong thing.
local function SellListed(done)
    local picks = CollectListed()
    local index, count, value = 1, 0, 0

    local function Step()
        if index > #picks then return done(count, value) end
        if not (MerchantFrame and MerchantFrame:IsShown()) then return done(count, value) end
        if settings.shiftSkip and IsShiftKeyDown() then return done(count, value) end

        local pick = picks[index]
        index = index + 1

        local info = C_Container.GetContainerItemInfo(pick.bag, pick.slot)
        if info and info.itemID == pick.itemID and not info.isLocked then
            C_Container.UseContainerItem(pick.bag, pick.slot)
            count = count + 1
            value = value + pick.value
        end
        C_Timer.After(SELL_STEP, Step)
    end

    Step()
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

-- What a visit would do, in words, or nil when there is nothing to do. Read the
-- same way the visit itself reads it, so the question matches what Yes does.
local function DescribeVisit()
    local API = OxedHub.ModuleAPI
    local parts = {}

    -- Every item about to be sold, junk and list together, as the player will
    -- see it in the question: so "Yes" is agreeing to these, not to a number.
    local items, count, value = {}, 0, 0
    if settings.sellJunk then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.quality == POOR and not info.hasNoValue then
                    local price = info.hyperlink and SellPrice(info.hyperlink) or 0
                    local worth = price * (info.stackCount or 1)
                    API:AddItemToList(items, info, worth)
                    count, value = count + 1, value + worth
                end
            end
        end
    end
    if settings.sellList and next(settings.items) then
        for _, pick in ipairs(CollectListed()) do
            API:AddItemToList(items, pick.info, pick.value)
            count, value = count + 1, value + pick.value
        end
    end
    if count > 0 then
        local header = value > 0
            and ("Sell %d item(s) for %s:"):format(count, Money(value))
            or ("Sell %d item(s):"):format(count)
        parts[#parts + 1] = header .. "\n" .. API:FormatItemList(items, 10, Money)
    end

    if settings.repair and CanMerchantRepair and CanMerchantRepair() then
        local cost, canRepair = GetRepairAllCost()
        if canRepair and cost and cost > 0 then
            parts[#parts + 1] = ("Repair for %s"):format(Money(cost))
        end
    end

    if #parts == 0 then return nil end
    return table.concat(parts, "\n\n") .. "\n\nGo ahead?"
end

local RunVisit   -- defined below; OnMerchantShow either asks first or runs it

local function OnMerchantShow()
    if not settings or settings.enabled == false then return end
    if settings.shiftSkip and IsShiftKeyDown() then return end

    if settings.confirm and OxedHub.ModuleAPI and OxedHub.ModuleAPI.Confirm then
        local question = DescribeVisit()
        if question then
            OxedHub.ModuleAPI:Confirm(question, function()
                -- The player may have walked away while deciding.
                if MerchantFrame and MerchantFrame:IsShown() then RunVisit() end
            end)
        end
        return
    end

    RunVisit()
end

function RunVisit()
    local soldCount, soldValue = 0, 0
    if settings.sellJunk then
        soldCount, soldValue = SellJunk()
    end

    local function Report(repairCost, payer, extra)
        if not settings.report then return end
        local parts = {}
        if soldCount > 0 then
            if soldValue > 0 then
                parts[#parts + 1] = ("sold %d item(s) for %s"):format(soldCount, Money(soldValue))
            else
                parts[#parts + 1] = ("sold %d item(s)"):format(soldCount)
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

    local function RepairThenReport()
        if settings.repair then Repair(Report) else Report() end
    end

    -- Give the junk sale a moment to land, then the list, then the repair.
    C_Timer.After(soldCount > 0 and 0.3 or 0, function()
        if settings.sellList and next(settings.items) then
            SellListed(function(count, value)
                soldCount, soldValue = soldCount + count, soldValue + value
                C_Timer.After(count > 0 and 0.3 or 0, RepairThenReport)
            end)
        else
            RepairThenReport()
        end
    end)
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        -- A question about a vendor that is no longer there has no answer.
        if OxedHub.ModuleAPI and OxedHub.ModuleAPI.HideConfirm then OxedHub.ModuleAPI:HideConfirm() end
    end
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
    EnsureData()
end

-- ── The sell list in Options ────────────────────────────────────────────────

local ICON_SIZE, ICON_GAP, PER_ROW = 32, 6, 9
local listIcons = {}
local RefreshList   -- defined below, used by the icons it draws

-- Whatever the player gave: an item link, "item:12345", or a bare number.
local function ParseItemID(text)
    if type(text) ~= "string" then return nil end
    local id = text:match("item:(%d+)") or text:match("^%s*(%d+)%s*$")
    return id and tonumber(id)
end

local function AddItem(itemID)
    if not itemID or itemID <= 0 then return end
    local name, _, _, _, _, _, _, _, _, _, price = GetInfo(itemID)
    if price == 0 then
        print(PREFIX .. ("%s cannot be sold to a vendor."):format(name or ("item " .. itemID)))
        return
    end
    settings.items[itemID] = true
    print(PREFIX .. ("%s will be sold at vendors."):format(name or ("item " .. itemID)))
    RefreshList()
end

-- An item held on the cursor, dropped onto the box. The cursor is emptied only
-- after the item is read, so a drop that is not an item leaves it in hand.
local function TakeCursorItem()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    AddItem(itemID)
end

local function GetIcon(index, parent)
    local icon = listIcons[index]
    if icon then return icon end

    icon = CreateFrame("Button", nil, parent)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetAllPoints()
    icon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(self.itemID)
        else
            GameTooltip:SetText("Item " .. tostring(self.itemID))
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click to take it off the sell list.", 1, 0.4, 0.4)
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icon:SetScript("OnClick", function(self)
        settings.items[self.itemID] = nil
        GameTooltip:Hide()
        RefreshList()
    end)
    -- Dropping an item on an icon adds it too, so the whole grid is a target.
    icon:SetScript("OnReceiveDrag", TakeCursorItem)

    listIcons[index] = icon
    return icon
end

function RefreshList()
    local window = optionsWindow
    if not (window and window.listArea) then return end

    local ids = {}
    for itemID in pairs(settings.items) do ids[#ids + 1] = itemID end
    table.sort(ids)

    for index, itemID in ipairs(ids) do
        local icon = GetIcon(index, window.listArea)
        local column = (index - 1) % PER_ROW
        local row = math.floor((index - 1) / PER_ROW)
        icon:ClearAllPoints()
        icon:SetPoint("TOPLEFT", window.listArea, "TOPLEFT",
            column * (ICON_SIZE + ICON_GAP), -row * (ICON_SIZE + ICON_GAP))
        icon.itemID = itemID
        -- An item the client has not seen this session has no icon yet; the
        -- question mark stands in and is replaced when the data arrives.
        local texture = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID))
            or (GetItemIcon and GetItemIcon(itemID))
        icon.texture:SetTexture(texture or QUESTION_MARK)
        if not texture and C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        icon:Show()
    end
    for index = #ids + 1, #listIcons do listIcons[index]:Hide() end

    window.listEmpty:SetShown(#ids == 0)
    window.listCount:SetText(("%d item(s) on the list"):format(#ids))
end

-- Refills the icons once item data the list asked for has arrived.
local itemDataWatcher = CreateFrame("Frame")
itemDataWatcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemDataWatcher:SetScript("OnEvent", function(_, _, itemID)
    if optionsWindow and optionsWindow:IsShown() and settings and settings.items[itemID] then
        RefreshList()
    end
end)

local function BuildListSection(window)
    local top = window.cursorY - 4

    -- The drop box: drag an item here, or click it while holding one.
    local drop = CreateFrame("Button", nil, window, "BackdropTemplate")
    drop:SetSize(ICON_SIZE + 8, ICON_SIZE + 8)
    drop:SetPoint("TOPLEFT", window, "TOPLEFT", 18, top)
    drop:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        bgFile = "Interface\\Buttons\\WHITE8x8",
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    drop:SetBackdropColor(0, 0, 0, 0.5)
    drop:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    local plus = drop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    plus:SetPoint("CENTER")
    plus:SetText("+")
    drop:SetScript("OnReceiveDrag", TakeCursorItem)
    drop:SetScript("OnClick", TakeCursorItem)
    drop:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add to the sell list")
        GameTooltip:AddLine("Drag an item from your bags onto this box.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    drop:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local dropLabel = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dropLabel:SetPoint("TOPLEFT", drop, "TOPRIGHT", 10, -2)
    dropLabel:SetText("Drop an item here, or type an item ID or paste a link:")

    local input = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    input:SetSize(150, 22)
    input:SetAutoFocus(false)
    input:SetPoint("TOPLEFT", dropLabel, "BOTTOMLEFT", 6, -4)
    local function AddFromInput()
        local itemID = ParseItemID(input:GetText())
        if itemID then
            AddItem(itemID)
            input:SetText("")
        else
            print(PREFIX .. "that is not an item ID or item link.")
        end
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", AddFromInput)
    input:SetScript("OnEscapePressed", input.ClearFocus)

    local add = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    add:SetSize(60, 22)
    add:SetPoint("LEFT", input, "RIGHT", 6, 0)
    add:SetText("Add")
    add:SetScript("OnClick", AddFromInput)

    -- Shift-clicking an item while the box has focus puts its link in, the
    -- way it does for the chat box.
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if input:HasFocus() and type(link) == "string" then
                input:SetText(link)
            end
        end)
    end

    window.listCount = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.listCount:SetPoint("TOPLEFT", drop, "BOTTOMLEFT", 0, -10)

    local area = CreateFrame("Frame", nil, window)
    area:SetPoint("TOPLEFT", window.listCount, "BOTTOMLEFT", 0, -6)
    area:SetSize(PER_ROW * (ICON_SIZE + ICON_GAP), 4 * (ICON_SIZE + ICON_GAP))
    area:EnableMouse(true)
    area:SetScript("OnReceiveDrag", TakeCursorItem)
    area:SetScript("OnMouseUp", TakeCursorItem)
    window.listArea = area

    window.listEmpty = area:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.listEmpty:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -4)
    window.listEmpty:SetText("Nothing on the list yet.")

    window:HookScript("OnShow", RefreshList)
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Auto Vendor", 420, 560)
        optionsWindow:AddCheckbox(settings, "sellJunk", "Sell junk (grey items)",
            "Everything grey in your bags is sold when a vendor opens.")
        optionsWindow:AddCheckbox(settings, "sellList", "Sell the items on my list",
            "Also sells every item on the list below, whatever its quality.")
        optionsWindow:AddCheckbox(settings, "repair", "Repair gear",
            "Repairs everything when the vendor can repair.")
        optionsWindow:AddCheckbox(settings, "guildFunds", "Use guild funds first",
            "Pays with the guild bank when your rank allows it and today's allowance covers the cost, and falls back to your own gold otherwise.")
        optionsWindow:AddCheckbox(settings, "report", "Say what was done in chat",
            "One line after each vendor visit: what was sold and what the repair cost.")
        optionsWindow:AddCheckbox(settings, "confirm", "Ask before doing it",
            "Shows what is about to be sold and what the repair costs, and waits for Yes. No leaves everything as it is.")
        optionsWindow:AddCheckbox(settings, "shiftSkip", "Hold Shift to skip a visit",
            "With this on, holding Shift while opening a vendor leaves everything as it is for that visit.")
        optionsWindow:AddNote("|cffffd100Sell list|r  -- click an icon to take it off.")
        BuildListSection(optionsWindow)
    end
    optionsWindow:Show()
    RefreshList()
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
        version  = "1.1.0",
        author   = "Oxed",
        category = "inventory",
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Sells junk and your sell list, and repairs, at any vendor. Set it up in Options.",
        icon     = "Interface\\Icons\\INV_Misc_Coin_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            EnsureData()
            watcher:RegisterEvent("MERCHANT_SHOW")
            watcher:RegisterEvent("MERCHANT_CLOSED")
        end,

        OnDisable = function()
            watcher:UnregisterEvent("MERCHANT_SHOW")
            watcher:UnregisterEvent("MERCHANT_CLOSED")
        end,
    })
end)
