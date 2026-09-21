-- ============================================================================
-- Auto Gossip (built-in OxedHub module)
-- When an NPC's conversation menu has exactly one thing to choose, it is
-- chosen: the flight master's "Show me where I can fly", the vendor's "Let me
-- browse your goods", the next line of a story that only goes one way.
--
-- One option only. With two or more, the menu is a real choice and is left to
-- the player.
--
-- It never takes an option that would change something you cannot easily
-- change back: making an inn your home is always left alone. And when the
-- menu also lists quests, it steps aside, so a quest is never skipped past by
-- choosing the conversation instead.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled     = false,  -- off until the player switches it on (see ModuleAPI:Register)
    shiftSkip   = false,   -- holding Shift skips the module for that moment (player's choice)
    inInstances = true,   -- also inside dungeons, raids and delves
    report      = false,  -- a line in chat naming the option that was chosen
}

local settings          -- OxedHubDB.modules.autogossip, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "

-- Options identified by their icon. Only the ones this module refuses are
-- listed: the inn ("make this inn your home") moves your hearthstone.
local ICON_BINDER = 132052

-- Some menus answer an option by showing themselves again with the same single
-- option -- a greeting that loops. Choosing it twice in quick succession from
-- the same NPC is taken as that loop, and the menu is left for the player.
local LOOP_WINDOW = 3
local lastChoice = { npc = nil, option = nil, at = 0 }

local function IsLoop(npc, optionID)
    local now = GetTime()
    local looping = lastChoice.npc == npc and lastChoice.option == optionID
        and (now - lastChoice.at) < LOOP_WINDOW
    lastChoice.npc, lastChoice.option, lastChoice.at = npc, optionID, now
    return looping
end

local function MenuHasQuests()
    if not C_GossipInfo then return false end
    local available = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
    local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}
    return #available > 0 or #active > 0
end

local function OnGossipShow()
    if not settings or settings.enabled == false then return end
    if InCombatLockdown() then return end
    if settings.shiftSkip and IsShiftKeyDown() then return end
    if not (C_GossipInfo and C_GossipInfo.GetOptions and C_GossipInfo.SelectOption) then return end

    if not settings.inInstances and IsInInstance() then return end

    -- Quests on the menu are Auto Quest's, or the player's; the conversation
    -- option is never chosen over them.
    if MenuHasQuests() then return end

    local options = C_GossipInfo.GetOptions() or {}
    if #options ~= 1 then return end

    local option = options[1]
    if not option or not option.gossipOptionID then return end
    if option.icon == ICON_BINDER then return end

    local npc = UnitGUID and UnitGUID("npc")
    if IsLoop(npc, option.gossipOptionID) then return end

    if settings.report and option.name then
        print(PREFIX .. ("chose |cffffd100%s|r."):format(option.name))
    end
    C_GossipInfo.SelectOption(option.gossipOptionID)
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "GOSSIP_SHOW" then OnGossipShow() end
end)

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autogossip
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autogossip = config
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
        optionsWindow = API:CreateOptionsWindow("Auto Gossip", 420, 220)
        optionsWindow:AddCheckbox(settings, "inInstances", "Also in dungeons, raids and delves",
            "Off, menus inside instances are always left for you to read.")
        optionsWindow:AddCheckbox(settings, "report", "Say what was chosen in chat")
        optionsWindow:AddCheckbox(settings, "shiftSkip", "Hold Shift to read a menu yourself",
            "With this on, holding Shift while talking to an NPC leaves the menu to you.")
        optionsWindow:AddNote("Only menus with a single option are chosen, never setting your hearthstone, and never when the NPC also has quests.")
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
        if settings.enabled == true then watcher:RegisterEvent("GOSSIP_SHOW") end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autogossip",
        name     = "Auto Gossip",
        version  = "1.0.0",
        author   = "Oxed",
        category = "general",
        keywords = { "gossip", "npc", "dialog", "talk", "option" },
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Picks the option when an NPC's menu has only one. Choose where in Options.",
        icon     = "Interface\\GossipFrame\\GossipGossipIcon",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            watcher:RegisterEvent("GOSSIP_SHOW")
        end,

        OnDisable = function()
            watcher:UnregisterEvent("GOSSIP_SHOW")
        end,
    })
end)
