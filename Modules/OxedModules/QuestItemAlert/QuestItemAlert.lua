-- ============================================================================
-- Quest Item Alert (built-in OxedHub module)
-- Deleting an item that starts a quest asks for confirmation already, but
-- never says which quest. This names it under the popup, and says whether you
-- have done it, are on it, or have never started it.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled = false,    -- off until the player switches it on
}

local POPUPS = { "DELETE_QUEST_ITEM", "DELETE_GOOD_QUEST_ITEM", "DELETE_ITEM", "DELETE_GOOD_ITEM" }

local settings
local optionsWindow
local frame = CreateFrame("Frame")

-- The quest the item on the cursor starts, from its place in the bags.
local function QuestForCursorItem()
    local kind, itemID = GetCursorInfo()
    if kind ~= "item" or not itemID then return nil end
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == itemID then
                local info = C_Container.GetContainerItemQuestInfo(bag, slot)
                if info and info.questID then return info.questID, info.isActive end
            end
        end
    end
    return nil
end

local function Describe(questID, isActive)
    local title = C_QuestLog.GetTitleForQuestID(questID) or ("Quest " .. questID)
    if C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return ("Starts \"%s\". You have already done it."):format(title), 0.4, 1, 0.4
    elseif isActive or C_QuestLog.GetLogIndexForQuestID(questID) then
        return ("Starts \"%s\". You are on it now."):format(title), 1, 0.82, 0
    end
    return ("Starts \"%s\". You have not done it yet!"):format(title), 1, 0.3, 0.3
end

frame:SetScript("OnEvent", function(_, _, _, _, _, questWarn)
    if not (settings and settings.enabled) then return end
    local questID, isActive = QuestForCursorItem()
    if not questID then return end
    -- The popup comes up with the same event: find it a moment later.
    C_Timer.After(0, function()
        local API = OxedHub.ModuleAPI
        for _, which in ipairs(POPUPS) do
            local dialog = API:FindPopup(which)
            if dialog then
                local text, r, g, b = Describe(questID, isActive)
                API:PopupNote(dialog, text, r, g, b)
                return
            end
        end
    end)
end)

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Quest Item Alert", 400, 130)
        optionsWindow:AddNote("Names the quest an item starts when you are about to delete it.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.questitemalert
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.questitemalert = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "questitemalert",
        name     = "Quest Item Alert",
        version  = "1.0.0",
        author   = "Oxed",
        category = "quests",
        keywords = { "quest", "delete", "destroy", "item", "warning" },
        desc     = "Names the quest an item starts before you delete it, and if you did it.",
        icon     = "Interface\\Icons\\INV_Misc_Note_06",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg) settings = cfg; frame:RegisterEvent("DELETE_ITEM_CONFIRM") end,
        OnDisable = function() frame:UnregisterAllEvents() end,
    })
end)
