-- ============================================================================
-- Train All (built-in OxedHub module)
-- A "Train All" button on the trainer window: learns every skill you can
-- learn there now, with its total cost on the button.
--
-- ⚠ Notes for whoever edits this next:
--   * Purchases go out spaced (STEP), one at a time, never in a burst: a burst
--     is partly dropped by the server with no error. The list shifts after
--     every purchase, so each step looks again for the first available skill
--     instead of keeping indexes from the start.
--   * The trainer window is load-on-demand (Blizzard_TrainerUI); the button is
--     made the first time the window exists, on TRAINER_SHOW.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled = false,   -- off until the player switches it on
    confirm = true,    -- ask before spending
    report  = true,    -- a line in chat when done
}

local PREFIX = "|cff00ccffOxedHub Train All:|r "
local STEP = 0.4           -- seconds between purchases
local MAX_STEPS = 200      -- a list that never empties stops here

local settings
local optionsWindow
local button
local busy = false
local events = CreateFrame("Frame")

-- Every skill that can be learned now: { index, cost }.
local function Available()
    local list, total = {}, 0
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then return list, 0 end
    local okN, count = pcall(GetNumTrainerServices)
    if not okN or type(count) ~= "number" then return list, 0 end
    for i = 1, count do
        local ok, _, _, category = pcall(GetTrainerServiceInfo, i)
        if ok and category == "available" then
            local okC, cost = pcall(GetTrainerServiceCost, i)
            cost = okC and tonumber(cost) or 0
            list[#list + 1] = { index = i, cost = cost }
            total = total + cost
        end
    end
    return list, total
end

local function Coins(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg"):format(math.floor(copper / 10000))
end

local function Refresh()
    if not button then return end
    if not (settings and settings.enabled) then button:Hide() return end
    button:Show()
    if busy then return end
    local list, total = Available()
    if #list == 0 then
        button:SetText(L["Train All"])
        button:Disable()
    else
        button:SetText(("%s (%d)"):format(L["Train All"], #list))
        -- Enabled even when short of gold: it learns what can be paid for.
        button:Enable()
    end
    button.total, button.count = total, #list
end

local function Finish(learned, spent)
    busy = false
    if settings.report and learned > 0 then
        print(PREFIX .. (L["learned %d skill(s) for %s."]):format(learned, Coins(spent)))
    end
    Refresh()
end

local function Run()
    if busy then return end
    busy = true
    button:Disable()
    local learned, spent, steps = 0, 0, 0
    local function Step()
        steps = steps + 1
        -- The window was closed, or the module switched off.
        if not (settings.enabled and ClassTrainerFrame and ClassTrainerFrame:IsShown()) or steps > MAX_STEPS then
            return Finish(learned, spent)
        end
        local list = Available()
        local pick
        for _, entry in ipairs(list) do
            if entry.cost <= GetMoney() then pick = entry break end
        end
        if not pick then
            if #list > 0 then print(PREFIX .. L["not enough gold for the rest."]) end
            return Finish(learned, spent)
        end
        local ok = pcall(BuyTrainerService, pick.index)
        if ok then
            learned, spent = learned + 1, spent + pick.cost
        end
        C_Timer.After(STEP, Step)
    end
    Step()
end

local POPUP = "OXEDHUB_TRAIN_ALL"
StaticPopupDialogs[POPUP] = {
    text = "%s",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function() Run() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

local function OnClick()
    local list, total = Available()
    if #list == 0 then return end
    if settings.confirm and total > 0 then
        StaticPopup_Show(POPUP, (L["Learn %d skill(s) for %s?"]):format(#list, Coins(total)))
    else
        Run()
    end
end

local function Build()
    if button or not ClassTrainerFrame then return end
    button = CreateFrame("Button", "OxedHubTrainAllButton", ClassTrainerFrame, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    local train = ClassTrainerTrainButton or (ClassTrainerFrame and ClassTrainerFrame.TrainButton)
    if train then
        button:SetPoint("RIGHT", train, "LEFT", -4, 0)
    else
        button:SetPoint("BOTTOMRIGHT", ClassTrainerFrame, "BOTTOMRIGHT", -100, 6)
    end
    button:SetText(L["Train All"])
    button:SetScript("OnClick", OnClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Train All"])
        if self.count and self.count > 0 then
            GameTooltip:AddLine((L["%d skill(s), %s in all."]):format(self.count, Coins(self.total or 0)), 1, 1, 1)
        else
            GameTooltip:AddLine(L["Nothing to learn here right now."], 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

events:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        -- The window is built on the frame it first opens.
        C_Timer.After(0, function()
            Build()
            Refresh()
        end)
    elseif event == "TRAINER_UPDATE" then
        Refresh()
    elseif event == "TRAINER_CLOSED" then
        busy = false
    end
end)

local function Start()
    for _, e in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED" }) do
        pcall(events.RegisterEvent, events, e)
    end
    Refresh()
end

local function Stop()
    events:UnregisterAllEvents()
    busy = false
    if button then button:Hide() end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Train All", 420, 220)
        optionsWindow = w
        w:AddCheckbox(settings, "confirm", "Ask before spending gold")
        w:AddCheckbox(settings, "report", "A line in chat when done")
        w:AddNote("The button sits beside Train on any class or profession trainer.")
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.trainall
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.trainall = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "trainall",
        name     = "Train All",
        version  = "1.0.0",
        added    = 20261127,
        updated  = 20261127,
        author   = "Oxed",
        category = "character",
        keywords = { "trainer", "train", "learn", "skills", "spells", "profession", "all" },
        desc     = "Learns every skill at a trainer with one click.",
        icon     = "Interface\\Icons\\INV_Misc_Book_11",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            Start()
        end,
        OnDisable = function()
            Stop()
        end,
    })
end)
