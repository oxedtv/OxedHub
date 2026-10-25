-- ============================================================================
-- Frame Mover (built-in OxedHub module)
-- Drag any of the game's own windows by an empty part of it, and it opens
-- there next time. Ctrl + mouse wheel over a window makes it bigger or smaller.
--
-- How it stays out of the way:
--   * Nothing is replaced. The windows keep their own scripts; this only adds
--     hooks (HookScript, hooksecurefunc) and moves them when the player asks.
--   * A protected window is never touched in combat: no drag, no restore.
--     The game opens it where it likes, and the next open out of combat puts
--     it back.
--   * The game's panel manager places the windows it owns after they show,
--     so the saved place is applied again once it has done that.
--   * Every window's own first position is kept, so "put back" and a window
--     that is not remembered return exactly where the game had them.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L

local DEFAULTS = {
    enabled    = false,  -- off until the player switches it on
    remember   = true,   -- a moved window opens where it was left
    scaleWheel = true,   -- Ctrl + mouse wheel over a window resizes it
    clamp      = true,   -- a window cannot be dragged off the screen
    -- positions and scales are tables, made in BindSettings
}

-- The windows it knows. Most belong to load-on-demand parts of the game;
-- they are picked up when those load.
local FRAMES = {
    "CharacterFrame", "PlayerSpellsFrame", "ProfessionsBookFrame", "CollectionsJournal",
    "EncounterJournal", "PVEFrame", "FriendsFrame", "CommunitiesFrame", "AchievementFrame",
    "QuestFrame", "GossipFrame", "MerchantFrame", "MailFrame", "OpenMailFrame", "BankFrame",
    "AuctionHouseFrame", "ProfessionsFrame", "ProfessionsCustomerOrdersFrame", "ClassTrainerFrame",
    "DressUpFrame", "TradeFrame", "SettingsPanel", "AddonList", "MacroFrame", "ItemSocketingFrame",
    "InspectFrame", "WeeklyRewardsFrame", "CalendarFrame", "TimeManagerFrame", "BlackMarketFrame",
    "GuildBankFrame", "VoidStorageFrame", "ItemUpgradeFrame", "TabardFrame", "PetitionFrame",
    "ItemTextFrame", "ScrappingMachineFrame", "StableFrame", "MajorFactionRenownFrame",
    "ExpansionLandingPage", "HelpFrame", "DelvesDashboardFrame", "GenericTraitFrame",
    "QuestLogPopupDetailFrame", "ChannelFrame", "ItemInteractionFrame", "ChallengesKeystoneFrame",
    "HousingDashboardFrame", "GameMenuFrame", "LootFrame",
}

local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.05

local settings
local optionsWindow
local known = {}      -- name -> frame, once hooked
local defaults = {}   -- frame -> its first anchors, as the game set them
local events = CreateFrame("Frame")

local function Active()
    return settings and settings.enabled == true
end

-- Whether the frame may be moved right now.
local function Touchable(frame)
    if frame.IsForbidden and frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame.IsProtected and frame:IsProtected())
end

local function KeepDefault(frame)
    if defaults[frame] then return end
    local points = {}
    for i = 1, frame:GetNumPoints() do points[i] = { frame:GetPoint(i) } end
    defaults[frame] = points
end

local function PutDefault(frame)
    local points = defaults[frame]
    if not points or #points == 0 or not Touchable(frame) then return end
    frame:ClearAllPoints()
    for _, p in ipairs(points) do frame:SetPoint(unpack(p)) end
end

-- The saved place and size, if there is one.
local function Restore(name, frame)
    if not Active() or not Touchable(frame) then return end
    local scale = settings.scales[name]
    if scale then frame:SetScale(scale) end
    local pos = settings.remember and settings.positions[name]
    if pos then
        KeepDefault(frame)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    end
end

local function Save(name, frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then settings.positions[name] = { x = left, y = top } end
    -- Moved by hand, but the game's layout file must not keep it: the place
    -- lives in OxedHub's settings, so switching the module off undoes it.
    frame:SetUserPlaced(false)
end

local function Hook(name, frame)
    known[name] = frame
    frame:SetMovable(true)

    frame:HookScript("OnMouseDown", function(f, button)
        if button ~= "LeftButton" or not Active() or not Touchable(f) then return end
        KeepDefault(f)
        if settings.clamp then f:SetClampedToScreen(true) end
        f:StartMoving()
        f.oxMoving = true
    end)
    frame:HookScript("OnMouseUp", function(f)
        if not f.oxMoving then return end
        f.oxMoving = nil
        f:StopMovingOrSizing()
        Save(name, f)
    end)
    frame:HookScript("OnMouseWheel", function(f, delta)
        if not (Active() and settings.scaleWheel and IsControlKeyDown() and Touchable(f)) then return end
        local scale = math.min(MAX_SCALE, math.max(MIN_SCALE, (f:GetScale() or 1) + delta * SCALE_STEP))
        f:SetScale(scale)
        settings.scales[name] = math.abs(scale - 1) < 0.001 and nil or scale
    end)
    frame:HookScript("OnShow", function(f) Restore(name, f) end)
    frame:HookScript("OnHide", function(f)
        if f.oxMoving then
            f.oxMoving = nil
            f:StopMovingOrSizing()
            Save(name, f)
        end
        -- Not remembered: the next open is the game's own place again.
        if Active() and not settings.remember then PutDefault(f) end
    end)
end

-- Picks up every listed window that exists now. Setting one up touches it,
-- so a protected one waits for the end of combat.
local pendingCombat = false
local function HookAll()
    for _, name in ipairs(FRAMES) do
        local frame = not known[name] and _G[name]
        if type(frame) == "table" and frame.HookScript and not (frame.IsForbidden and frame:IsForbidden()) then
            if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
                pendingCombat = true
            else
                Hook(name, frame)
                if frame:IsShown() then Restore(name, frame) end
            end
        end
    end
    -- Mouse input for the wheel and the drag, asked for out of combat only.
    if not InCombatLockdown() then
        for _, frame in pairs(known) do
            if not frame.oxMouse then
                frame.oxMouse = true
                frame:EnableMouse(true)
                frame:EnableMouseWheel(true)
            end
        end
    end
end

-- The panel manager places its windows after they show; this runs after it.
local managerHooked = false
local function HookManager()
    if managerHooked then return end
    managerHooked = true
    local function Again()
        if not Active() then return end
        for name, frame in pairs(known) do
            if frame:IsShown() then Restore(name, frame) end
        end
    end
    if type(UpdateUIPanelPositions) == "function" then hooksecurefunc("UpdateUIPanelPositions", Again) end
    if type(ShowUIPanel) == "function" then hooksecurefunc("ShowUIPanel", Again) end
end

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if not pendingCombat then return end
        pendingCombat = false
    end
    HookAll()
end)

local function Start()
    HookManager()
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    HookAll()
end

-- Every window back where the game puts it, at its normal size.
local function ResetAll()
    wipe(settings.positions)
    wipe(settings.scales)
    for _, frame in pairs(known) do
        if Touchable(frame) then
            frame:SetScale(1)
            PutDefault(frame)
        end
    end
end

local function Stop()
    events:UnregisterAllEvents()
    -- The hooks stay (they cannot be taken off) but do nothing while off;
    -- what is on screen goes back to the game's own place and size.
    for _, frame in pairs(known) do
        if Touchable(frame) then
            frame:SetScale(1)
            PutDefault(frame)
        end
    end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Frame Mover", 430, 300)
        optionsWindow = w
        w:AddCheckbox(settings, "remember", "Remember where each window was",
            "Off: a moved window goes back to its usual place when you close it.")
        w:AddCheckbox(settings, "scaleWheel", "Ctrl + mouse wheel resizes a window")
        w:AddCheckbox(settings, "clamp", "Keep windows on the screen")
        local reset = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        reset:SetSize(200, 22)
        reset:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
        reset:SetText(L["Put every window back"])
        reset:SetScript("OnClick", function()
            if InCombatLockdown() then
                print("|cff00ccffOxedHub|r " .. L["windows can be put back after the fight."])
                return
            end
            ResetAll()
        end)
        w.cursorY = w.cursorY - 34
        w:AddNote("Drag a window by an empty part of it, such as its title or border. "
            .. "Protected windows (spellbook, talents and some others) cannot be moved during a fight. /oxmove reset puts every window back.")
    end
    optionsWindow:Show()
end

SLASH_OXEDFRAMEMOVER1 = "/oxmove"
SlashCmdList.OXEDFRAMEMOVER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "reset" and settings then
        if InCombatLockdown() then
            print("|cff00ccffOxedHub|r " .. L["windows can be put back after the fight."])
        else
            ResetAll()
            print("|cff00ccffOxedHub|r " .. L["every window is back in its usual place."])
        end
        return
    end
    ShowOptions()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.framemover
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.framemover = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Lists are made here, never in DEFAULTS (they would be shared).
    if type(config.positions) ~= "table" then config.positions = {} end
    if type(config.scales) ~= "table" then config.scales = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "framemover",
        name     = "Frame Mover",
        version  = "1.0.0",
        updated  = 20261025.11,  -- new
        author   = "Oxed",
        category = "character",
        keywords = { "move", "drag", "window", "frame", "scale", "blizzmove", "position" },
        desc     = "Drag the game's windows anywhere and they open there again. Ctrl+wheel resizes. /oxmove",
        icon     = "Interface\\Icons\\INV_Misc_Map_01",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.positions) ~= "table" then settings.positions = {} end
            if type(settings.scales) ~= "table" then settings.scales = {} end
            Start()
        end,
        OnDisable = function() Stop() end,
    })
end)
