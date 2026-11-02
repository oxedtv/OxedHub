-- ============================================================================
-- Keep Open (built-in OxedHub module)
-- The game closes a window when another one needs its place on screen. Windows
-- it manages are listed in UIPanelWindows, so this takes them off that list and
-- they become plain frames: they stay open together and Escape closes them.
--
-- Same idea as the NoAutoClose addon, written here from scratch. That addon is
-- All Rights Reserved: read it for ideas, never paste from it.
--
-- ⚠ Three things that are easy to get wrong:
--   * Writing to UIPanelWindows from addon code taints it, and the game then
--     refuses to open protected windows in combat. Taking a window off goes
--     through a Blizzard function (RemoveFromWindows). Putting one back cannot,
--     which is why switching the module off asks for a reload.
--   * In combat a protected window cannot be hidden from the Escape list. It
--     gets a secure button that binds Escape for the length of the fight.
--     Those buttons can only be created out of combat, and PLAYER_REGEN_DISABLED
--     still counts as out of combat.
--   * Some windows are left to the game (LEAVE_ALONE). Each of them breaks
--     something or is meant to take over the screen.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L

local DEFAULTS = {
    enabled = false,   -- off until the player switches it on
    anchor  = "TOPLEFT",
    x       = 50,
    y       = -50,
    minimapButton = true,
}

local LEAVE_ALONE = {
    BarberShopFrame = true,
    CinematicFrame = true,
    CommunitiesFrame = true,
    GameMenuFrame = true,
    HouseEditorFrame = true,
    MacroFrame = true,
    PerksProgramFrame = true,
    SettingsPanel = true,
    TokenFrame = true,
    WarboardQuestChoiceFrame = true,
}

-- Cannot be hidden safely through the Escape list, in or out of combat.
local NOT_ON_ESCAPE_LIST = {
    PlayerSpellsFrame = true,
}

-- The game used to close these when the talk with that NPC ended or another began.
local INTERACTION_FRAMES = {
    Gossip = "GossipFrame",
    QuestGiver = "QuestFrame",
}

local LAYOUT_ATTRIBUTES = { "defined", "enabled", "area", "pushable", "whileDead", "maximizePoint" }

local settings
local optionsWindow, moverBox
local minimapIcon, MinimapIcon
local active = false
local taken = {}          -- name -> the window's UIPanelWindows entry, while off the list
local placedByUs = {}     -- frame -> true: it had no place of its own
local onEscapeList = {}   -- names this module added to UISpecialFrames
local escButtons = {}     -- frame -> its secure Escape button
local hideHooked = {}     -- frame -> true
local lastHidden = {}     -- frame -> GetTime() of its last hide
local waitingForCombat = false
local releaseWaiting = false
local hooksDone = false
local escCount = 0

local events = CreateFrame("Frame")

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function IsProtected(frame)
    return frame.IsProtected and frame:IsProtected()
end

local function IsForbidden(frame)
    return frame.IsForbidden and frame:IsForbidden()
end

local function RemoveFromWindows(name)
    local mixin = TextureLoadingGroupMixin
    if mixin and mixin.RemoveTexture then
        mixin.RemoveTexture({ textures = UIPanelWindows }, name)
    else
        UIPanelWindows[name] = nil
    end
end

local function PlaceDefault(frame)
    if IsForbidden(frame) or (InCombatLockdown() and IsProtected(frame)) then return end
    frame:ClearAllPoints()
    -- Edit Mode's frames replace SetPoint and keep the original as SetPointBase.
    local setPoint = frame.SetPointBase or frame.SetPoint
    setPoint(frame, settings.anchor, UIParent, settings.anchor, settings.x, settings.y)
end

-- ── Escape in combat ────────────────────────────────────────────────────────

local function ArmEscButton(button, always)
    button:SetAttribute("always", always and true or false)
    button:SetAttribute("_onclick", [[
        self:ClearBindings()
        local panel = self:GetFrameRef("panel")
        if panel:IsShown() then panel:Hide() end
    ]])
    button:SetAttribute("_onhide", [[
        self:ClearBindings()
    ]])
    button:SetAttribute("_onshow", [[
        if self:GetAttribute("always") or PlayerInCombat() then
            self:SetBindingClick(true, "ESCAPE", self)
            self:GetFrameRef("panel"):Raise()
        end
    ]])
end

local function DisarmEscButton(button)
    ClearOverrideBindings(button)
    button:Execute("self:ClearBindings()")
    button:SetAttribute("_onclick", nil)
    button:SetAttribute("_onhide", nil)
    button:SetAttribute("_onshow", nil)
end

local function AddEscButton(frame, always)
    if InCombatLockdown() then return end
    local button = escButtons[frame]
    if not button then
        escCount = escCount + 1
        button = CreateFrame("Button", "OxedHubKeepOpenEsc" .. escCount, frame,
            "SecureHandlerShowHideTemplate,SecureHandlerClickTemplate")
        button:SetFrameRef("panel", frame)
        button.panel = frame
        button.always = always
        escButtons[frame] = button
    end
    ArmEscButton(button, always)
    if always and frame:IsShown() then button:Execute(button:GetAttribute("_onshow")) end
end

-- ── Taking windows off the game's list ──────────────────────────────────────

local function TakePanel(name, specialNames)
    local frame = _G[name]
    if type(frame) ~= "table" or not frame.Show or LEAVE_ALONE[name] or IsForbidden(frame) then return end

    local notOnList = NOT_ON_ESCAPE_LIST[name]
    if InCombatLockdown() and (IsProtected(frame) or notOnList or frame:IsShown()) then
        waitingForCombat = true
        return
    end

    -- Open and held by the game right now: close it through the game first, or
    -- the game would go on thinking that place on screen is taken.
    if frame:IsShown() then HideUIPanel(frame) end

    if IsProtected(frame) or notOnList then AddEscButton(frame, notOnList) end
    if not notOnList and not specialNames[name] then
        specialNames[name] = true
        onEscapeList[name] = true
        tinsert(UISpecialFrames, name)
    end

    taken[name] = UIPanelWindows[name]
    RemoveFromWindows(name)
    if frame.SetAttribute then
        for _, attribute in ipairs(LAYOUT_ATTRIBUTES) do
            frame:SetAttribute("UIPanelLayout-" .. attribute, nil)
        end
        -- The map's Maximize button reads these two; without "area" the game
        -- still treats it as a plain frame.
        if name == "WorldMapFrame" then
            frame:SetAttribute("UIPanelLayout-defined", "1")
            frame:SetAttribute("UIPanelLayout-maximizePoint", "TOP")
        end
    end
    if frame.GetPoint and not frame:GetPoint() then
        placedByUs[frame] = true
        PlaceDefault(frame)
    end

    if frame.HookScript and not hideHooked[frame] then
        hideHooked[frame] = true
        frame:HookScript("OnHide", function(f)
            if active then lastHidden[f] = GetTime() end
        end)
    end
end

local function Sweep()
    if not active then return end
    local specialNames = {}
    for _, name in ipairs(UISpecialFrames) do specialNames[name] = true end
    for name in pairs(UIPanelWindows) do TakePanel(name, specialNames) end
end

-- Back on the list. Written directly, so it taints the list: see the top of the file.
local function ReleaseAll()
    if InCombatLockdown() then
        releaseWaiting = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    releaseWaiting = false
    for name, info in pairs(taken) do
        UIPanelWindows[name] = info
        taken[name] = nil
        local frame = _G[name]
        if type(frame) == "table" and frame.SetAttribute then
            for _, attribute in ipairs(LAYOUT_ATTRIBUTES) do
                frame:SetAttribute("UIPanelLayout-" .. attribute, nil)
            end
        end
    end
    for i = #UISpecialFrames, 1, -1 do
        if onEscapeList[UISpecialFrames[i]] then table.remove(UISpecialFrames, i) end
    end
    wipe(onEscapeList)
    wipe(placedByUs)
    for _, button in pairs(escButtons) do DisarmEscButton(button) end
end

-- ── Hooks on the game's window functions ────────────────────────────────────
-- A hook cannot be taken off again, so each one starts by checking `active`.

local function OnPanelShown(frame)
    if not active or not frame or IsForbidden(frame) then return end
    local name = frame.GetName and frame:GetName()
    local info = name and taken[name]
    if not info or (InCombatLockdown() and IsProtected(frame)) then return end

    if frame.GetPoint and not frame:GetPoint() then
        placedByUs[frame] = true
        PlaceDefault(frame)
    end
    if frame:IsShown() and frame.IsToplevel and frame:IsToplevel() then frame:Raise() end
    if info.checkFit then
        local fit = (FrameUtil and FrameUtil.UpdateScaleForFit) or UIPanelUpdateScaleForFit
        if fit then fit(frame, info.checkFitExtraWidth or 20, info.checkFitExtraHeight or 20) end
    end
end

-- Stunned or feared: the game closes every window except the ones marked
-- ignoreControlLost, which it can no longer tell apart now they are off its list.
local function AfterLostControl()
    if not active then return end
    local now = GetTime()
    for frame, hiddenAt in pairs(lastHidden) do
        local name = frame:GetName()
        local info = name and taken[name]
        if hiddenAt == now and info and info.ignoreControlLost then ShowUIPanel(frame) end
        lastHidden[frame] = nil
    end
end

local function InstallHooks()
    if hooksDone then return end
    hooksDone = true
    hooksecurefunc("ShowUIPanel", OnPanelShown)
    hooksecurefunc("RegisterUIPanel", Sweep)
    hooksecurefunc("RestoreUIPanelArea", function(frame)
        if active and frame and frame.GetName and taken[frame:GetName()] then PlaceDefault(frame) end
    end)
    if type(CloseAllWindows_WithExceptions) == "function" then
        hooksecurefunc("CloseAllWindows_WithExceptions", AfterLostControl)
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

local function CloseInteractionFrames(interaction, closing)
    if not (Enum and Enum.PlayerInteractionType) then return end
    for typeName, frameName in pairs(INTERACTION_FRAMES) do
        local isThisOne = interaction == Enum.PlayerInteractionType[typeName]
        -- A new talk closes the other kind; an ended one closes its own.
        if (closing and isThisOne) or (not closing and not isThisOne) then
            local frame = _G[frameName]
            if frame and frame:IsShown() then HideUIPanel(frame) end
        end
    end
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" and releaseWaiting then
        ReleaseAll()
        if not active then events:UnregisterAllEvents() end
        return
    end
    if not active then return end

    if event == "ADDON_LOADED" then
        Sweep()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        CloseInteractionFrames(arg1, false)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        CloseInteractionFrames(arg1, true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- A window can have become protected since it was taken. Last moment to
        -- give it a button; Escape is bound for whatever is already open.
        for name in pairs(taken) do
            local frame = _G[name]
            if type(frame) == "table" and IsProtected(frame) and not escButtons[frame] then
                AddEscButton(frame, false)
            end
        end
        for frame, button in pairs(escButtons) do
            if frame:IsVisible() then
                SetOverrideBindingClick(button, true, "ESCAPE", button:GetName())
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, button in pairs(escButtons) do
            if not button.always then ClearOverrideBindings(button) end
        end
        if waitingForCombat then
            waitingForCombat = false
            Sweep()
        end
    end
end)

local function Start()
    -- Both at once would fight over the same list.
    if C_AddOns and C_AddOns.IsAddOnLoaded("NoAutoClose") then
        print(L["Keep Open: the NoAutoClose addon is loaded and already does this, so this module stays idle."])
        return
    end
    active = true
    releaseWaiting = false
    InstallHooks()
    events:RegisterEvent("ADDON_LOADED")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    events:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    Sweep()
end

local function Stop()
    if moverBox then moverBox:Hide() end
    if not active then return end
    active = false
    waitingForCombat = false
    events:UnregisterAllEvents()
    wipe(lastHidden)
    ReleaseAll()
    print(L["Keep Open is off. Type /reload so the game's windows are fully its own again."])
end

-- ── Options ─────────────────────────────────────────────────────────────────

-- A window placed by this module moves along; one with its own place stays.
local function PlaceAllAgain()
    for name in pairs(taken) do
        local frame = _G[name]
        if type(frame) == "table" and placedByUs[frame] and not frame:IsShown() then PlaceDefault(frame) end
    end
end

local function PlaceMoverBox()
    moverBox:ClearAllPoints()
    moverBox:SetPoint(settings.anchor, UIParent, settings.anchor, settings.x, settings.y)
end

local function ToggleMoverBox()
    if not moverBox then
        local box = CreateFrame("Frame", "OxedHubKeepOpenMover", UIParent, "BackdropTemplate")
        box:SetSize(220, 120)
        box:SetFrameStrata("DIALOG")
        box:SetFrameLevel(200)
        box:SetClampedToScreen(true)
        box:SetMovable(true)
        box:EnableMouse(true)
        box:RegisterForDrag("LeftButton")
        box:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        box:SetBackdropColor(0.1, 0.3, 0.6, 0.6)
        box:SetScript("OnDragStart", box.StartMoving)
        box:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            self:SetUserPlaced(false)
            local anchor, _, _, x, y = self:GetPoint()
            settings.anchor, settings.x, settings.y = anchor, x, y
            PlaceAllAgain()
        end)
        local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 10, -10)
        text:SetPoint("BOTTOMRIGHT", -10, 10)
        text:SetText(L["Drag me. Windows open here unless they have a place of their own."])
        box:Hide()
        moverBox = box
    end
    PlaceMoverBox()
    moverBox:SetShown(not moverBox:IsShown())
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Keep Open", 460, 360)
        optionsWindow = w

        w:AddNote("Opening a game window no longer closes the others. Escape closes them.")

        local move = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        move:SetSize(190, 24)
        move:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        move:SetText(L["Move where windows open"])
        move:SetScript("OnClick", ToggleMoverBox)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(move) end

        local reset = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        reset:SetSize(120, 24)
        reset:SetPoint("LEFT", move, "RIGHT", 10, 0)
        reset:SetText(L["Reset place"])
        reset:SetScript("OnClick", function()
            settings.anchor, settings.x, settings.y = DEFAULTS.anchor, DEFAULTS.x, DEFAULTS.y
            if moverBox then PlaceMoverBox() end
            PlaceAllAgain()
        end)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(reset) end
        w.cursorY = w.cursorY - 36

        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        w:AddNote("Windows all open in the same place, so a new one covers the last. Frame Mover lets you drag each one to a place of its own, and it opens there again.")
        w:AddNote("In combat a protected window closes with Escape one at a time, ahead of anything else Escape would do.")
        w:AddNote("Switching the module on closes the windows you have open. Switching it off needs a /reload.")
        w:AddModuleLinks("Works together with", { "framemover" })
        w:HookScript("OnHide", function()
            if moverBox then moverBox:Hide() end
        end)
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "keepwindowsopen", label = L["Keep Open"], icon = "Interface\\Icons\\INV_Misc_Book_09", config = settings,
        hint = L["Click: options."],
        onClick = function(mouse)
            ShowOptions()
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBKEEPOPEN1 = "/keepopen"
SlashCmdList.OXEDHUBKEEPOPEN = function()
    ShowOptions()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.keepwindowsopen
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.keepwindowsopen = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "keepwindowsopen",
        name     = "Keep Open",
        version  = "1.0.0",
        updated  = 20261102.7,
        author   = "Oxed",
        category = "character",
        keywords = { "windows", "frames", "panels", "auto close", "no auto close", "noautoclose", "stay open", "escape" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Opening a game window no longer closes the others, so they stay open together.",
        icon     = "Interface\\Icons\\INV_Misc_Book_09",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,

        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
