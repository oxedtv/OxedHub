local addonName, OxedHub = ...
local print = OxedHub.Print or print
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ActionHub Module - Circular Widget for Quick Actions (Formerly Test Ring)
local ActionHub = {}
OxedHub.ActionHub = ActionHub

-- ActionHub is split over five files, loaded in this order:
--   ActionHubData.lua      hub data, layout maths, the confirm dialog
--   ActionHubNodes.lua     what a node shows: cooldowns, glows, StyleButton
--   ActionHubWidget.lua    the hubs on screen, move mode, dragging
--   ActionHubSettings.lua  the ActionHub tab and the slot picker window
--   ActionHubPicker.lua    the list inside the slot picker
-- A local a later file needs is handed over through Private at the end of
-- the file that defines it and taken at the top of the file that uses it.
-- ⚠ Only functions go through it. A local that holds state must stay in
-- the one file that changes it: a copy taken at load would never update.
local Private = {}
ActionHub._private = Private

-- Local references
local CONFIG = OxedHub.CONFIG
local L = OxedHub.L
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local C_ToyBox = C_ToyBox
local GameTooltip = GameTooltip
local SendChatMessage = SendChatMessage
local DoEmote = DoEmote
local math = math
local table = table
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local type = type

local function IsMouseOver(frame)
    if not frame then return false end
    if frame.IsMouseOver then
        return frame:IsMouseOver()
    elseif type(_G.MouseIsOver) == "function" then
        return _G.MouseIsOver(frame)
    end
    return false
end
local MouseIsOver = IsMouseOver

local function ApplyAssignmentBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,  -- Remove border
        tile = true, tileSize = 16, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(0.15, 0.08, 0.04, 0.1)  -- Dark brown overlay (10% opacity)
    frame:SetBackdropBorderColor(0, 0, 0, 0)  -- Transparent border
    
    -- Add the assignments.tga background texture with manual pixel size control
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\assignments.tga")
    -- Manual size in pixels - adjust these values as needed
    bg:SetSize(399, 673.075)  -- WIDTH, HEIGHT in pixels
    -- Position offset in pixels - moved 5px right and 5px up
    bg:SetPoint("CENTER", frame, "CENTER", 5, 5)  -- X offset (right), Y offset (up)
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetAlpha(0.95)
    frame.assignmentBgTexture = bg
end

local RADIUS = 110
local NODE_SIZE = 44

local function CreateDefaultHubData(idx)
    return {
        name = "Hub " .. (idx or 1),
        slots = {},
        secondarySlots = {},
        dualSideEnabled = false,
        dualSideLayout = "horizontal",
        quadrant = "bottom-right",
        onScreen = false,
        widgetPosition = { x = 0, y = 0 },
        widgetUnlocked = false,
        hideInCombat = false,
        showLogoWhenLocked = false,
        showTooltip = true,
        enableRangeCheck = true,
        style = "square",
    }
end

local function EnsureHubData(db, idx)
    if not db then
        db = CreateDefaultHubData(idx)
    end
    db.name = db.name or ("Hub " .. (idx or 1))
    db.slots = db.slots or {}
    db.secondarySlots = db.secondarySlots or {}
    if db.dualSideEnabled == nil then
        db.dualSideEnabled = false
    end
    db.dualSideLayout = db.dualSideLayout or "horizontal"
    db.quadrant = db.quadrant or "bottom-right"
    db.widgetPosition = db.widgetPosition or { x = 0, y = 0 }
    if db.onScreen == nil then db.onScreen = false end
    if db.widgetUnlocked == nil then db.widgetUnlocked = false end
    if db.hideInCombat == nil then db.hideInCombat = false end
    if db.showLogoWhenLocked == nil then db.showLogoWhenLocked = false end
    if db.showTooltip == nil then db.showTooltip = true end
    if db.enableRangeCheck == nil then db.enableRangeCheck = true end
    db.style = db.style or "square"
    -- Buttons and visibility (the hub's "More options" window).
    if db.hideMounted == nil then db.hideMounted = false end
    if db.fadedAlpha == nil then db.fadedAlpha = 0 end
    if db.manaTint == nil then db.manaTint = true end
    if db.desatOnCooldown == nil then db.desatOnCooldown = false end
    if db.cooldownAlpha == nil then db.cooldownAlpha = 1 end
    if db.showItemCount == nil then db.showItemCount = true end
    if db.iconZoom == nil then db.iconZoom = 8 end
    if db.showKeybind == nil then db.showKeybind = true end
    if db.tooltipInCombat == nil then db.tooltipInCombat = true end
    return db
end

local function GetDualQuadrant(quadrant, layout)
    if layout == "vertical" then
        if quadrant == "bottom-right" then
            return "top-right"
        elseif quadrant == "bottom-left" then
            return "top-left"
        elseif quadrant == "top-left" then
            return "bottom-left"
        end
        return "bottom-right"
    end

    if quadrant == "bottom-right" then
        return "bottom-left"
    elseif quadrant == "bottom-left" then
        return "bottom-right"
    elseif quadrant == "top-left" then
        return "top-right"
    end
    return "top-left"
end

local function GetQuadrantAngles(quadrant)
    if quadrant == "bottom-right" then
        return 0, math.pi / 2
    elseif quadrant == "bottom-left" then
        return math.pi / 2, math.pi
    elseif quadrant == "top-left" then
        return math.pi, 3 * math.pi / 2
    end
    return 3 * math.pi / 2, 2 * math.pi
end

local function GetEffectiveNodeLimit(db, side)
    if not db or db.limitNodes == false then
        return 999
    end

    if side == "secondary" and db.dualSideEnabled then
        return 11
    end

    return 14
end

local function TrimSideToLimit(db, side)
    if not db then
        return
    end

    local slots = (side == "secondary") and (db.secondarySlots or {}) or (db.slots or {})
    local limit = GetEffectiveNodeLimit(db, side)
    while #slots > limit do
        table.remove(slots)
    end
end

local function GetSecondarySkipEdge(primaryQuadrant, secondaryQuadrant, layout)
    if layout == "vertical" then
        if primaryQuadrant == "top-right" and secondaryQuadrant == "bottom-right" then
            return "start"
        elseif primaryQuadrant == "bottom-right" and secondaryQuadrant == "top-right" then
            return "finish"
        elseif primaryQuadrant == "top-left" and secondaryQuadrant == "bottom-left" then
            return "finish"
        elseif primaryQuadrant == "bottom-left" and secondaryQuadrant == "top-left" then
            return "start"
        end
    else
        if primaryQuadrant == "top-right" and secondaryQuadrant == "top-left" then
            return "finish"
        elseif primaryQuadrant == "top-left" and secondaryQuadrant == "top-right" then
            return "start"
        elseif primaryQuadrant == "bottom-right" and secondaryQuadrant == "bottom-left" then
            return "start"
        elseif primaryQuadrant == "bottom-left" and secondaryQuadrant == "bottom-right" then
            return "finish"
        end
    end
end

local function GetArcCoordinates(i, maxSlots, quadrant, cx, cy, baseRadius, radiusStep, slot, skipEdge)
    local angleStart, angleEnd = GetQuadrantAngles(quadrant)
    local span = angleEnd - angleStart

    local baseSlots = 3
    local ringIndex = 0
    local ringCapacity = skipEdge and (baseSlots - 1) or baseSlots
    local countBeforeRing = 0

    while i > countBeforeRing + ringCapacity do
        countBeforeRing = countBeforeRing + ringCapacity
        ringIndex = ringIndex + 1
        local rawRingCapacity = baseSlots + (ringIndex * 2)
        ringCapacity = skipEdge and (rawRingCapacity - 1) or rawRingCapacity
    end

    local indexInRing = i - countBeforeRing
    local slotsInThisRing = math.min(maxSlots - countBeforeRing, ringCapacity)
    local t
    if skipEdge == "start" then
        t = indexInRing / slotsInThisRing
    elseif skipEdge == "finish" then
        t = (indexInRing - 1) / slotsInThisRing
    else
        t = (slotsInThisRing > 1) and ((indexInRing - 1) / (slotsInThisRing - 1)) or 0.5
    end
    local angle = angleStart + span * t
    local currentRadius = baseRadius + ringIndex * radiusStep

    local x = cx + currentRadius * math.cos(angle)
    local y = cy - currentRadius * math.sin(angle)

    if slot and slot.nodePositionX then
        x = x + slot.nodePositionX
    end
    if slot and slot.nodePositionY then
        y = y + slot.nodePositionY
    end

    return x, y
end

-- Custom confirmation dialog for ActionHub (Main Addon Style)
local confirmDialog
local function ShowConfirmDialog(text, onAccept, onCancel)
    if not confirmDialog then
        confirmDialog = CreateFrame("Frame", "OxedHubActionHubConfirm", UIParent, "BackdropTemplate")
        confirmDialog:SetSize(460, 160)
        confirmDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        confirmDialog:SetFrameStrata("DIALOG")
        confirmDialog:SetFrameLevel(150)
        confirmDialog:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        confirmDialog:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
        confirmDialog:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
        confirmDialog:EnableMouse(true)
        confirmDialog:SetMovable(true)
        confirmDialog:RegisterForDrag("LeftButton")
        confirmDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
        confirmDialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
        confirmDialog:Hide()

        local title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", confirmDialog, "TOP", 0, -15)
        title:SetText("|cffff4444" .. (L["LBL_WARNING"] or "Warning") .. "|r")

        local msg = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        msg:SetPoint("TOP", title, "BOTTOM", 0, -10)
        msg:SetWidth(420)
        msg:SetJustifyH("CENTER")
        confirmDialog.msg = msg

        local okBtn = CreateFrame("Button", nil, confirmDialog, "UIPanelButtonTemplate")
        okBtn:SetSize(110, 26)
        okBtn:SetPoint("BOTTOMRIGHT", confirmDialog, "BOTTOM", -15, 20)
        okBtn:SetText(L["BTN_OK"] or "OK")
        confirmDialog.okBtn = okBtn

        local cancelBtn = CreateFrame("Button", nil, confirmDialog, "UIPanelButtonTemplate")
        cancelBtn:SetSize(110, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", confirmDialog, "BOTTOM", 15, 20)
        cancelBtn:SetText(L["BTN_CANCEL"] or "Cancel")
        confirmDialog.cancelBtn = cancelBtn

        local closeBtn = CreateFrame("Button", nil, confirmDialog, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", confirmDialog, "TOPRIGHT", 2, 2)
        closeBtn:SetScript("OnClick", function() confirmDialog:Hide() end)
    end

    confirmDialog.msg:SetText(text)
    confirmDialog.okBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if onAccept then onAccept() end
    end)
    confirmDialog.cancelBtn:SetScript("OnClick", function()
        confirmDialog:Hide()
        if onCancel then onCancel() end
    end)
    confirmDialog:Show()
end

-- Emote helpers
-- Looks up the icon texture for an emote ID from CONFIG.REACTIONS or customReactions
function ActionHub:GetEmoteIconById(emoteId)
    if not emoteId then return nil end

    local lookupId = emoteId
    -- If it's an ActionHub slot ID, find the underlying emote key
    if string.match(emoteId, "^ActionHubHub") then
        local profile = OxedHub.db and OxedHub.db.profile
        if profile and profile.emotionMappings and profile.emotionMappings[emoteId] then
            lookupId = profile.emotionMappings[emoteId].emote or emoteId
        end
    end

    -- Check built-in reactions
    for _, r in ipairs(OxedHub.CONFIG and OxedHub.CONFIG.REACTIONS or {}) do
        if r.id == lookupId then return r.icon end
    end
    -- Check custom reactions
    for _, r in pairs(OxedHub.db.profile.customReactions or {}) do
        if r.id == lookupId then return r.icon end
    end
    return nil
end

-- ── Module nodes ─────────────────────────────────────────────────────────────
-- A node can open something of a built-in module: one of its windows (the
-- quick actions a module registers, the same ones as on the minimap button's
-- menu), its settings window, or switch it on and off. The node keeps
-- "<module id>|<action>" as its id: "pvpprogress|q1", "goldwq|options",
-- "mail|toggle". Names and icons are looked up when drawn, so a renamed module
-- or a new icon shows without reassigning the node.
local MODULE_ICON = "Interface\\Icons\\INV_Gizmo_02"

local function ModuleAPI() return OxedHub.ModuleAPI end

-- What a module node id stands for: the module, and the action key.
local function SplitModuleNode(id)
    if type(id) ~= "string" then return nil end
    local modId, action = id:match("^([^|]+)|(.+)$")
    return modId, action
end

-- Every action a picker can offer, sorted by module name. Quick actions are
-- listed only for switched-on modules: a window of a module that is off has
-- nothing to show.
-- One node per module. On a hub, left-click opens settings and right-click
-- switches it. A ring slot fires on release and cannot tell the mouse buttons
-- apart, so it gets Settings and On / off as two entries, next to the
-- module's own window actions (Gold World Quests: Show or hide).
function ActionHub:GetModuleNodeChoices(forRing)
    local API = ModuleAPI()
    local list = {}
    if not (API and API.modules) then return list end
    local mods = {}
    for _, mod in pairs(API.modules) do mods[#mods + 1] = mod end
    table.sort(mods, function(a, b) return tostring(a.name or a.id) < tostring(b.name or b.id) end)
    for _, mod in ipairs(mods) do
        local name = tostring(mod.name or mod.id)
        if API:IsModuleEnabled(mod.id) and type(mod.quick) == "table" then
            for index, action in ipairs(mod.quick) do
                list[#list + 1] = { id = mod.id .. "|q" .. index, name = name,
                    action = tostring(action.text or "Open"), icon = mod.icon or MODULE_ICON }
            end
        end
        if forRing then
            if mod.OnOptionsShow then
                list[#list + 1] = { id = mod.id .. "|options", name = name, action = L["Settings"],
                    icon = mod.icon or MODULE_ICON }
            end
            list[#list + 1] = { id = mod.id .. "|toggle", name = name, action = L["On / off"],
                icon = mod.icon or MODULE_ICON }
        else
            list[#list + 1] = { id = mod.id .. "|main", name = name,
                action = L["Left: settings, right: switch"], icon = mod.icon or MODULE_ICON }
        end
    end
    return list
end

-- Name, action text and icon of a module node, or nil for a module that is
-- not there any more (uninstalled, renamed id).
function ActionHub:DescribeModuleNode(id)
    local API = ModuleAPI()
    local modId, action = SplitModuleNode(id)
    local mod = modId and API and API.modules and API.modules[modId]
    if not mod then return nil end
    local text
    if action == "main" then
        text = L["Left-click: settings|nRight-click: "] .. (API:IsModuleEnabled(modId) and L["switch off"] or L["switch on"])
    elseif action == "options" then
        text = L["Settings"]
    elseif action == "toggle" then
        text = API:IsModuleEnabled(modId) and L["Switch off"] or L["Switch on"]
    else
        local index = tonumber(action:match("^q(%d+)$") or "")
        local quick = index and type(mod.quick) == "table" and mod.quick[index]
        text = quick and tostring(quick.text or "Open") or L["Open"]
    end
    return tostring(mod.name or modId), text, mod.icon or MODULE_ICON
end

function ActionHub:GetModuleNodeIcon(id)
    local _, _, icon = self:DescribeModuleNode(id)
    return icon or MODULE_ICON
end

-- Runs a module node. Nothing here is protected; turning a module on or off
-- waits for the end of a fight, since some modules show secure frames.
function ActionHub:RunModuleNode(id, button)
    local API = ModuleAPI()
    local modId, action = SplitModuleNode(id)
    if action == "main" then
        local switch = (button == "RightButton")
        action = switch and "toggle" or "options"
    end
    local mod = modId and API and API.modules and API.modules[modId]
    if not mod then
        print(L["|cff00ccffOxedHub|r that module is not there any more."])
        return
    end
    local name = tostring(mod.name or modId)
    if action == "options" then
        if mod.OnOptionsShow then pcall(mod.OnOptionsShow, mod) end
    elseif action == "toggle" then
        if InCombatLockdown() then
            print((L["|cff00ccffOxedHub|r %s can be switched on or off after the fight."]):format(name))
            return
        end
        local on = not API:IsModuleEnabled(modId)
        API:SetModuleEnabled(modId, on)
        print(("|cff00ccffOxedHub|r %s %s."):format(name, on and L["switched on"] or L["switched off"]))
        if API.RefreshModulesTab then pcall(API.RefreshModulesTab, API) end
    else
        if not API:IsModuleEnabled(modId) then
            print((L["|cff00ccffOxedHub|r %s is switched off. Switch it on on the Modules page."]):format(name))
            return
        end
        local index = tonumber(action:match("^q(%d+)$") or "")
        local quick = index and type(mod.quick) == "table" and mod.quick[index]
        if quick and quick.func then
            local ok, err = pcall(quick.func)
            if not ok then print(("|cffff5555OxedHub (%s):|r %s"):format(name, tostring(err))) end
        end
    end
end

-- Plays all effects for an emote ID based on its emotionMappings entry
function ActionHub:TriggerEmoteById(emoteId)
    if not emoteId then return end
    local mapping = OxedHub.db.profile.emotionMappings and OxedHub.db.profile.emotionMappings[emoteId]
    if not mapping then
        -- No mapping, just try to do the emote command directly
        DoEmote(emoteId)
        return
    end
    -- Respect the shared effects delay so rapid presses don't spam effects
    if OxedHub.Triggers and OxedHub.Triggers.CanRunEffectsKeyed then
        if not OxedHub.Triggers:CanRunEffectsKeyed("emote_" .. tostring(emoteId)) then
            return
        end
    end
    -- Play sound
    if mapping.sound and OxedHub.Sounds and OxedHub.Sounds.Play then
        OxedHub.Sounds:Play(mapping.sound)
    end
    -- Play animation
    if mapping.animation and OxedHub.Animations and OxedHub.Animations.Play then
        OxedHub.Animations:Play(mapping.animation, {
            useCustomPosition = mapping.animationUseCustomPosition,
            x = mapping.animationCustomX,
            y = mapping.animationCustomY
        })
    end
    -- Do emote
    if mapping.emote then
        DoEmote(mapping.emote)
    end
    -- Send chat template (ActionHub exclusive feature)
    if mapping.chat and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[mapping.chat] then
        if OxedHub.ChatMessages and OxedHub.ChatMessages.Send then
            OxedHub.ChatMessages:Send(mapping.chat, nil, { isManual = true })
        else
            local ct = OxedHub.db.profile.chatTemplates[mapping.chat]
            if ct and ct.text then
                SendChatMessage(ct.text, ct.channel or "SAY")
            end
        end
    end
end

-- Multi-hub helpers
-- Validated once, then trusted.
--
-- Every GetHubDB and GetActiveHubDB call went through here, and each one
-- rebuilt the defaults for every hub -- roughly twenty field checks per hub,
-- from a hundred and twenty places in the addon, including per-button loops
-- while a panel is being drawn. The work was real but almost always repeated:
-- nothing about a hub changes between two lookups in the same frame.
--
-- The cache is keyed on the table itself and its length, so switching profile
-- (a new table) or adding and removing a hub (a new length) both invalidate it
-- without anyone having to remember to say so.
local validatedHubs, validatedCount = nil, -1

function ActionHub:InvalidateHubCache()
    validatedHubs, validatedCount = nil, -1
end

function ActionHub:GetHubs()
    local ah = OxedHub.db.profile.actionHub
    if not ah.hubs then ah.hubs = {} end

    if validatedHubs == ah.hubs and validatedCount == #ah.hubs then
        return ah.hubs
    end

    for i = 1, #ah.hubs do
        ah.hubs[i] = EnsureHubData(ah.hubs[i], i)
    end

    validatedHubs, validatedCount = ah.hubs, #ah.hubs
    return ah.hubs
end

function ActionHub:GetActiveHubIndex()
    return OxedHub.db.profile.actionHub.activeHub or 1
end

function ActionHub:SetActiveHubIndex(idx)
    OxedHub.db.profile.actionHub.activeHub = idx
end

function ActionHub:GetActiveHubDB()
    local hubs = self:GetHubs()
    local idx = self:GetActiveHubIndex()
    if not hubs[idx] then
        hubs[idx] = CreateDefaultHubData(idx)
    end
    hubs[idx] = EnsureHubData(hubs[idx], idx)
    return hubs[idx]
end

function ActionHub:GetHubDB(idx)
    local hubs = self:GetHubs()
    if hubs[idx] then
        hubs[idx] = EnsureHubData(hubs[idx], idx)
    end
    return hubs[idx]
end

-- When a hub is shown: "always", "hideCombat", "onlyCombat" or "mouseover".
-- The older "Hide In Combat" tick box is the hideCombat mode, so both stay in
-- step whichever one the player uses.
function ActionHub:GetVisibilityMode(db)
    if not db then return "always" end
    local mode = db.visibility
    if mode == "onlyCombat" or mode == "mouseover" then return mode end
    return db.hideInCombat and "hideCombat" or "always"
end

-- Whether the hub should fade out right now (it comes back on mouseover).
function ActionHub:ShouldFadeHub(db)
    if not (db and db.onScreen) then return false end
    local mode = self:GetVisibilityMode(db)
    local combat = InCombatLockdown()
    if mode == "hideCombat" and combat then return true end
    if mode == "onlyCombat" and not combat then return true end
    if mode == "mouseover" then return true end
    if db.hideMounted and IsMounted and IsMounted() then return true end
    return false
end


-- Handed to the ActionHub files loaded after this one.
Private.ApplyAssignmentBackdrop = ApplyAssignmentBackdrop
Private.CreateDefaultHubData = CreateDefaultHubData
Private.EnsureHubData = EnsureHubData
Private.GetArcCoordinates = GetArcCoordinates
Private.GetDualQuadrant = GetDualQuadrant
Private.GetEffectiveNodeLimit = GetEffectiveNodeLimit
Private.GetSecondarySkipEdge = GetSecondarySkipEdge
Private.MouseIsOver = MouseIsOver
Private.ShowConfirmDialog = ShowConfirmDialog
Private.TrimSideToLimit = TrimSideToLimit
