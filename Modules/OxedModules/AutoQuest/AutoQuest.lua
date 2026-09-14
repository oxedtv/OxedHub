-- ============================================================================
-- Auto Quest (built-in OxedHub module)
-- Takes the clicking out of questing: talking to an NPC picks up the quests
-- they offer, accepts them, and hands in the ones that are done. When a quest
-- has a single reward, or none, it is taken; when there is a real choice, the
-- choice stays yours.
--
-- What it does is set entirely in Options: accepting, handing in, quests from
-- the menu, low-level and repeatable quests and the reward each have a switch.
--
-- It stops short of anything that costs: a quest that takes gold to hand in is
-- left for the player, and so is a reward choice unless they ask for the most
-- valuable one to be picked.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled      = false,  -- off until the player switches it on (see ModuleAPI:Register)
    shiftSkip   = false,   -- holding Shift skips the module for that moment (player's choice)
    accept       = true,   -- accept quests that are offered
    turnIn       = true,   -- hand in quests that are complete
    fromGossip   = true,   -- open quests listed in an NPC's conversation menu
    skipTrivial  = true,   -- leave low-level (grey) quests alone
    repeatable   = true,   -- include daily, weekly and repeatable quests
    bestReward   = false,  -- with a choice of rewards, take the one worth most gold
    report       = false,  -- a line in chat for each quest accepted or handed in
}

local settings          -- OxedHubDB.modules.autoquest, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "

-- Quests opened from a menu in the last few seconds. When a quest cannot be
-- accepted -- a full quest log, a requirement not met -- the NPC's menu comes
-- straight back with the same quest on it, and opening it again would loop
-- until the player walked away. A quest tried recently is passed over instead.
local RETRY_AFTER = 10
local tried = {}

local function TriedRecently(questID)
    if not questID then return false end
    local at = tried[questID]
    return at and (GetTime() - at) < RETRY_AFTER
end

local function MarkTried(questID)
    if questID then tried[questID] = GetTime() end
end

-- Nothing is done while the module is off.
local function Paused()
    return not settings or settings.enabled == false
        or (settings.shiftSkip and IsShiftKeyDown())
end

local function Report(verb, title)
    if settings.report and title and title ~= "" then
        print(PREFIX .. ("%s |cffffd100%s|r."):format(verb, title))
    end
end

local DAILY  = Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily or 1
local WEEKLY = Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly or 2

-- Whether an offered quest is one the settings allow picking up.
local function WantOffered(info)
    if type(info) ~= "table" then return false end
    if info.isIgnored then return false end
    if settings.skipTrivial and info.isTrivial then return false end
    local repeating = info.repeatable or info.isRepeatable
        or info.frequency == DAILY or info.frequency == WEEKLY
    if repeating and not settings.repeatable then return false end
    return not TriedRecently(info.questID)
end

-- ── The conversation menu (the modern layout) ───────────────────────────────

local function HandleGossip()
    if not (C_GossipInfo and settings.fromGossip) then return end

    -- Handing in first: finishing a quest often unlocks the next one from the
    -- same NPC, which then appears on the menu that comes back.
    if settings.turnIn and C_GossipInfo.GetActiveQuests then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if info.isComplete and not TriedRecently(info.questID) then
                MarkTried(info.questID)
                C_GossipInfo.SelectActiveQuest(info.questID)
                return
            end
        end
    end

    if settings.accept and C_GossipInfo.GetAvailableQuests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if WantOffered(info) then
                MarkTried(info.questID)
                C_GossipInfo.SelectAvailableQuest(info.questID)
                return
            end
        end
    end
end

-- ── The quest greeting (the older layout some NPCs still use) ───────────────

local function HandleGreeting()
    if settings.turnIn and GetNumActiveQuests then
        for index = 1, GetNumActiveQuests() do
            local title, isComplete = GetActiveTitle(index)
            local questID = GetActiveQuestID and GetActiveQuestID(index)
            if isComplete and not TriedRecently(questID or title) then
                MarkTried(questID or title)
                SelectActiveQuest(index)
                return
            end
        end
    end

    if settings.accept and GetNumAvailableQuests then
        for index = 1, GetNumAvailableQuests() do
            local isTrivial, frequency, isRepeatable, _, questID = GetAvailableQuestInfo(index)
            local info = {
                isTrivial = isTrivial, frequency = frequency,
                isRepeatable = isRepeatable, questID = questID,
            }
            if WantOffered(info) then
                MarkTried(questID)
                SelectAvailableQuest(index)
                return
            end
        end
    end
end

-- ── One quest ───────────────────────────────────────────────────────────────

local function HandleDetail()
    if not settings.accept then return end
    -- A quest that is accepted the moment it is shown only needs to be let go.
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        return
    end
    local title = GetTitleText and GetTitleText()
    AcceptQuest()
    Report("accepted", title)
end

-- The "bring me these" page. Handing in continues to the reward page, which
-- is where gold would change hands, so a quest asking for gold stops here.
local function HandleProgress()
    if not settings.turnIn then return end
    if GetQuestMoneyToGet and GetQuestMoneyToGet() > 0 then return end
    if IsQuestCompletable and IsQuestCompletable() then
        CompleteQuest()
    end
end

-- The reward with the highest vendor price, or nil when any price is unknown:
-- guessing past an unloaded item could throw away the better one.
local function MostValuableChoice(count)
    local best, bestValue
    for index = 1, count do
        local link = GetQuestItemLink and GetQuestItemLink("choice", index)
        if not link then return nil end
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local price = getInfo and select(11, getInfo(link))
        if price == nil then return nil end
        local _, _, quantity = GetQuestItemInfo("choice", index)
        local value = price * (quantity or 1)
        if not bestValue or value > bestValue then best, bestValue = index, value end
    end
    return best
end

local function HandleComplete()
    if not settings.turnIn then return end
    local title = GetTitleText and GetTitleText()
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0

    if choices <= 1 then
        GetQuestReward(choices)
        Report("handed in", title)
        return
    end

    -- A real choice is left open unless the player asked for the gold one.
    if settings.bestReward then
        local pick = MostValuableChoice(choices)
        if pick then
            GetQuestReward(pick)
            Report("handed in", title)
        end
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event, arg1)
    if Paused() then return end

    if event == "GOSSIP_SHOW" then
        HandleGossip()
    elseif event == "QUEST_GREETING" then
        HandleGreeting()
    elseif event == "QUEST_DETAIL" then
        HandleDetail()
    elseif event == "QUEST_PROGRESS" then
        HandleProgress()
    elseif event == "QUEST_COMPLETE" then
        HandleComplete()
    elseif event == "QUEST_AUTOCOMPLETE" then
        -- A quest that finishes out in the world, with a popup instead of an
        -- NPC to walk back to.
        if settings.turnIn and ShowQuestComplete and arg1 then
            ShowQuestComplete(arg1)
        end
    elseif event == "QUEST_ACCEPT_CONFIRM" then
        -- Someone in the group started an escort or a shared quest.
        if settings.accept and ConfirmAcceptQuest then ConfirmAcceptQuest() end
    end
end)

local EVENTS = {
    "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
    "QUEST_COMPLETE", "QUEST_AUTOCOMPLETE", "QUEST_ACCEPT_CONFIRM",
}

local function SetEvents(on)
    for _, event in ipairs(EVENTS) do
        if on then watcher:RegisterEvent(event) else watcher:UnregisterEvent(event) end
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autoquest
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autoquest = config
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
        optionsWindow = API:CreateOptionsWindow("Auto Quest", 430, 340)
        optionsWindow:AddCheckbox(settings, "accept", "Accept quests",
            "Quests an NPC offers are accepted when you talk to them.")
        optionsWindow:AddCheckbox(settings, "turnIn", "Hand in finished quests",
            "Completed quests are handed in, and a single reward is taken. Quests that cost gold to hand in are left for you.")
        optionsWindow:AddCheckbox(settings, "fromGossip", "Open quests from the NPC's menu",
            "Picks quests out of an NPC's conversation list instead of waiting for you to click them.")
        optionsWindow:AddCheckbox(settings, "skipTrivial", "Skip low-level quests",
            "Grey quests, far below your level, are left alone.")
        optionsWindow:AddCheckbox(settings, "repeatable", "Include daily and repeatable quests")
        optionsWindow:AddCheckbox(settings, "bestReward", "Pick the reward worth the most gold",
            "When a quest offers a choice, take the one that sells for most. Off, the choice is always yours.")
        optionsWindow:AddCheckbox(settings, "report", "Say what was done in chat")
        optionsWindow:AddCheckbox(settings, "shiftSkip", "Hold Shift to handle quests yourself",
            "With this on, holding Shift while talking to an NPC leaves their quests to you.")
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
        if settings.enabled == true then SetEvents(true) end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autoquest",
        name     = "Auto Quest",
        version  = "1.0.0",
        author   = "Oxed",
        category = "general",
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Accepts and hands in quests when you talk to NPCs. Choose what it does in Options.",
        icon     = "Interface\\GossipFrame\\AvailableQuestIcon",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            SetEvents(true)
        end,

        OnDisable = function()
            SetEvents(false)
        end,
    })
end)
