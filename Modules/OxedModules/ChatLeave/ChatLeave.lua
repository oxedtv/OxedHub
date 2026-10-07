-- ============================================================================
-- Chat Leave (built-in OxedHub module)
-- Right-click a channel's name in chat ([2. Trade], [4. LookingForGroup]...)
-- and the menu gets "Leave this channel" -- the game makes you type /leave.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled = false,    -- off until the player switches it on
}

local PREFIX = "|cff00ccffOxedHub|r "

local settings
local optionsWindow
local hooked = false
local lastTarget      -- the channel the menu was opened on

local function Hook()
    if hooked then return end
    hooked = true
    if ChatFrameUtil and ChatFrameUtil.ShowChatChannelContextMenu then
        hooksecurefunc(ChatFrameUtil, "ShowChatChannelContextMenu", function(_, _, chatTarget)
            lastTarget = chatTarget
        end)
    end
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_CHAT_FRAME_CHANNEL", function(_, root)
            if not (settings and settings.enabled) then return end
            local target = lastTarget
            if target == nil or (issecretvalue and issecretvalue(target)) then return end
            root:CreateDivider()
            root:CreateButton("|cffff6060Leave this channel|r", function()
                local _, name = GetChannelName(target)
                LeaveChannelByName(name or target)
                print(PREFIX .. "left " .. tostring(name or target) .. ".")
            end)
        end)
    end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Chat Leave", 400, 130)
        optionsWindow:AddNote("Right-click a channel's name in chat to find Leave this channel in the menu.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.chatleave
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.chatleave = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "chatleave",
        name     = "Chat Leave",
        version  = "1.0.0",
        author   = "Oxed",
        category = "chat",
        keywords = { "chat", "channel", "leave", "trade", "general" },
        desc     = "Right-click a channel in chat to leave it, no /leave needed.",
        icon     = "Interface\\Icons\\INV_Letter_15",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        -- The menu hook stays once made; it adds nothing while off.
        OnEnable = function(_, cfg) settings = cfg; Hook() end,
        OnDisable = function() end,
    })
end)
