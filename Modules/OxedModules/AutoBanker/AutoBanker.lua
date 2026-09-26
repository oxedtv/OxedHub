-- ============================================================================
-- Auto Banker (built-in OxedHub module)
-- Opening the bank puts away what obviously belongs there: reagents, and
-- anything you already keep a stack of in the bank.
--
-- "Already in the bank" is the rule that does the work. It needs no list to
-- maintain and no guessing about what you value: whatever you have chosen to
-- store before is what you want stored now, and everything else is left in
-- your bags where you put it.
--
-- An optional switch lets holding Shift while opening the bank skip it, and
-- pressing Shift part way through stop the run where it stands. Off by default.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled   = false,  -- off until the player switches it on (see ModuleAPI:Register)
    shiftSkip   = false,   -- holding Shift skips the module for that moment (player's choice)
    reagents  = true,   -- the game's own "deposit all reagents"
    matching  = true,   -- items you already keep in the bank
    tradeGoods = false, -- every trade good, stored or not
    report    = true,   -- one line in chat saying what happened
    confirm   = false,  -- ask with a Yes / No popup before doing any of it
}

local settings          -- OxedHubDB.modules.autobanker, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "

-- Deposits are one server call each, so they go out spaced rather than in one
-- burst: a flood is dropped, and the items that were dropped stay in the bags
-- with nothing to say they failed.
local STEP = 0.05

local TRADE_GOODS_CLASS = (Enum and Enum.ItemClass and Enum.ItemClass.Tradegoods) or 7

-- ── Which containers are the bank ───────────────────────────────────────────

-- Every bank container this client has, whichever bank layout it uses. Asked
-- of the game rather than assumed: the tab based bank and the older numbered
-- bank bags answer in different places, and a character may have either.
local function BankContainers()
    local containers = {}

    -- The tab layout knows exactly which tabs were bought.
    if BankPanel and BankPanel.purchasedBankTabData then
        for _, tabData in ipairs(BankPanel.purchasedBankTabData) do
            if tabData.ID and tabData.ID ~= -1 then
                containers[#containers + 1] = tabData.ID
            end
        end
    end

    if #containers == 0 then
        if BANK_CONTAINER then containers[#containers + 1] = BANK_CONTAINER end
        local first = (NUM_BAG_SLOTS or 4) + 1
        for bag = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do
            containers[#containers + 1] = bag
        end
        if REAGENTBANK_CONTAINER then containers[#containers + 1] = REAGENTBANK_CONTAINER end
    end

    return containers
end

local function FreeBankSlots()
    local free = 0
    if not (C_Container and C_Container.GetContainerNumFreeSlots) then return free end
    for _, bag in ipairs(BankContainers()) do
        free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return free
end

-- What is already stored, by item. The set is read once per visit: reading it
-- again after each deposit would make the first item of a kind teach the rule
-- that sends the rest, and one stray item would drag its whole kind in.
local function StoredItems()
    local stored = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return stored end

    for _, bag in ipairs(BankContainers()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then stored[info.itemID] = true end
        end
    end
    return stored
end

-- ── What to send ────────────────────────────────────────────────────────────

local function IsTradeGood(itemID)
    if not (C_Item and C_Item.GetItemInfoInstant) then return false end
    local classID = select(6, C_Item.GetItemInfoInstant(itemID))
    return classID == TRADE_GOODS_CLASS
end

-- The bag slots worth sending, newest rule first. A locked slot is one the
-- server is already busy with, and touching it again loses the item's place.
local function Collect(stored)
    local picks = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return picks end

    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked then
                local wanted = (settings.matching and stored[info.itemID])
                    or (settings.tradeGoods and IsTradeGood(info.itemID))
                if wanted then
                    picks[#picks + 1] = { bag = bag, slot = slot, itemID = info.itemID, info = info }
                end
            end
        end
    end
    return picks
end

-- ── Sending them ────────────────────────────────────────────────────────────

local function BankType()
    if BankFrame and BankFrame.GetActiveBankType then
        local ok, value = pcall(BankFrame.GetActiveBankType, BankFrame)
        if ok then return value end
    end
    return nil
end

-- Runs down the list one slot at a time. Every step checks the bank is still
-- open and nothing has changed underneath: a deposit sent after the window
-- closed is an item dropped on the floor of the interface, not stored.
local function Send(picks, free, done)
    local index, moved = 1, 0
    local bankType = BankType()

    local function Step()
        if index > #picks or moved >= free then return done(moved) end
        if not (BankFrame and BankFrame:IsShown()) then return done(moved) end
        if InCombatLockdown() then return done(moved) end
        if settings.shiftSkip and IsShiftKeyDown() then return done(moved) end

        local pick = picks[index]
        index = index + 1

        if C_Container.HasContainerItem and C_Container.HasContainerItem(pick.bag, pick.slot) then
            local info = C_Container.GetContainerItemInfo(pick.bag, pick.slot)
            -- The slot may hold something else by now: bags move under you as
            -- items stack and sort.
            if info and info.itemID == pick.itemID and not info.isLocked then
                C_Container.UseContainerItem(pick.bag, pick.slot, nil, bankType, true)
                moved = moved + 1
            end
        end

        C_Timer.After(STEP, Step)
    end

    Step()
end

-- Reagent stacks in the bags right now. The deposit call answers the same way
-- whether it moved fifty stacks or none, so without counting first the report
-- said "reagents deposited" on every visit, including the ones with nothing to
-- put away.
local function CountBagReagents()
    local count = 0
    if not (C_Container and C_Container.GetContainerNumSlots) then return count end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink then
                local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local isReagent = getInfo and select(17, getInfo(info.hyperlink))
                if isReagent then count = count + 1 end
            end
        end
    end
    return count
end

-- Returns the number of reagent stacks that were in the bags when the deposit
-- was sent, or 0 when there was nothing to send.
local function DepositReagents()
    if not settings.reagents then return 0 end
    local stacks = CountBagReagents()
    if stacks == 0 then return 0 end
    if C_Bank and C_Bank.AutoDepositItemsIntoBank then
        local ok = pcall(C_Bank.AutoDepositItemsIntoBank, BankType()
            or (Enum and Enum.BankType and Enum.BankType.Character))
        if ok then return stacks end
    end
    if DepositReagentBank then
        local ok = pcall(DepositReagentBank)
        if ok then return stacks end
    end
    return 0
end

-- ── At the bank ─────────────────────────────────────────────────────────────

-- What a visit would do, in words, or nil when there is nothing to do.
local function DescribeVisit()
    local API = OxedHub.ModuleAPI
    local parts = {}

    -- The reagents themselves, read the same way CountBagReagents reads them,
    -- so the list in the question is the list the deposit will take.
    if settings.reagents then
        local reagents, stacks = {}, 0
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.hyperlink and getInfo and select(17, getInfo(info.hyperlink)) then
                    API:AddItemToList(reagents, info)
                    stacks = stacks + 1
                end
            end
        end
        if stacks > 0 then
            parts[#parts + 1] = ("Deposit %d reagent stack(s):"):format(stacks)
                .. "\n" .. API:FormatItemList(reagents, 10)
        end
    end

    local picks = Collect(StoredItems())
    if #picks > 0 then
        local stored = {}
        for _, pick in ipairs(picks) do API:AddItemToList(stored, pick.info) end
        parts[#parts + 1] = ("Put away %d stack(s) you already store:"):format(#picks)
            .. "\n" .. API:FormatItemList(stored, 10)
    end

    if #parts == 0 then return nil end
    return table.concat(parts, "\n\n") .. "\n\nGo ahead?"
end

local RunVisit   -- defined below; OnBankOpened either asks first or runs it

local function OnBankOpened()
    if not settings or settings.enabled == false then return end
    if settings.shiftSkip and IsShiftKeyDown() then return end

    if settings.confirm and OxedHub.ModuleAPI and OxedHub.ModuleAPI.Confirm then
        local question = DescribeVisit()
        if question then
            OxedHub.ModuleAPI:Confirm(question, function()
                -- The player may have closed the bank while deciding.
                if BankFrame and BankFrame:IsShown() then RunVisit() end
            end)
        end
        return
    end

    RunVisit()
end

function RunVisit()
    local reagents = DepositReagents()   -- stacks sent, 0 when none

    local free = FreeBankSlots()
    if free <= 0 then
        if settings.report then
            print(PREFIX .. "|cffff5555the bank is full|r, nothing was put away.")
        end
        return
    end

    local picks = Collect(StoredItems())
    if #picks == 0 then
        if reagents > 0 and settings.report then
            print(PREFIX .. ("deposited %d reagent stack(s)."):format(reagents))
        end
        return
    end

    Send(picks, free, function(moved)
        if not settings.report then return end

        local parts = {}
        if reagents > 0 then parts[#parts + 1] = ("deposited %d reagent stack(s)"):format(reagents) end
        if moved > 0 then
            parts[#parts + 1] = ("put away %d stack(s)"):format(moved)
        end
        if moved < #picks and moved >= free then
            parts[#parts + 1] = "|cffff5555bank filled up|r"
        end
        if #parts > 0 then print(PREFIX .. table.concat(parts, ", ") .. ".") end
    end)
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_CLOSED" then
        -- A question about a bank that is no longer open has no answer.
        if OxedHub.ModuleAPI and OxedHub.ModuleAPI.HideConfirm then OxedHub.ModuleAPI:HideConfirm() end
    elseif event == "BANKFRAME_OPENED" then
        -- One frame's grace: the tab list is filled in as the window opens,
        -- and reading it in the same instant finds a bank with no tabs.
        C_Timer.After(0.2, OnBankOpened)
    end
end)

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autobanker
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autobanker = config
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
        optionsWindow = API:CreateOptionsWindow("Auto Banker", 420, 270)
        optionsWindow:AddCheckbox(settings, "reagents", "Deposit reagents",
            "The same as pressing the game's own deposit button when the bank opens.")
        optionsWindow:AddCheckbox(settings, "matching", "Restock what you already store",
            "Sends anything from your bags that you already keep in the bank.")
        optionsWindow:AddCheckbox(settings, "tradeGoods", "Send all trade goods",
            "Every trade good, whether or not you already store it. Off by default: it will send things you were carrying on purpose.")
        optionsWindow:AddCheckbox(settings, "report", "Say what was done in chat",
            "One line after each visit saying how much was put away.")
        optionsWindow:AddCheckbox(settings, "confirm", "Ask before doing it",
            "Shows what is about to be deposited and waits for Yes. No leaves your bags as they are.")
        optionsWindow:AddCheckbox(settings, "shiftSkip", "Hold Shift to skip a visit",
            "With this on, holding Shift while opening the bank leaves your bags as they are for that visit.")
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
        if settings.enabled ~= false then watcher:RegisterEvent("BANKFRAME_OPENED") end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autobanker",
        name     = "Auto Banker",
        version  = "1.0.0",
        author   = "Oxed",
        category = "items",
        keywords = { "bank", "reagents", "deposit", "restock", "warband" },
        desc     = "Deposits reagents and restocks what you already store when the bank opens.",
        icon     = "Interface\\Icons\\INV_Misc_Bag_10_Blue",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            watcher:RegisterEvent("BANKFRAME_OPENED")
            watcher:RegisterEvent("BANKFRAME_CLOSED")
        end,

        OnDisable = function()
            watcher:UnregisterEvent("BANKFRAME_OPENED")
            watcher:UnregisterEvent("BANKFRAME_CLOSED")
        end,
    })
end)
