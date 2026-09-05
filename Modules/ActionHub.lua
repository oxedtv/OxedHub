local addonName, OxedHub = ...

-- ActionHub Module - Circular Widget for Quick Actions (Formerly Test Ring)
local ActionHub = {}
OxedHub.ActionHub = ActionHub

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
local ApplyWidgetVisualAlpha

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
    db.style = db.style or "square"
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

local function StyleCooldownText(cdFrame, offsetY)
    local regions = { cdFrame:GetRegions() }
    local activeDB = ActionHub:GetActiveHubDB()
    local fontSize = (activeDB and activeDB.cooldownTextSize) or 11
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            region:SetFont(OxedHub:GetFont("Fonts\\FRIZQT__.ttf"), fontSize, "OUTLINE")
            region:ClearAllPoints()
            region:SetPoint("CENTER", cdFrame, "CENTER", 0, offsetY or 0)
        end
    end
end

local MARKER_ICONS = {
    [0] = "Interface\\Icons\\Spell_ChargeNegative",
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
local FLARE_ICONS = {
    [0] = "Interface\\Icons\\Spell_ChargePositive",
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
-- Must match the icons the picker lists for these entries, otherwise a node
-- ends up showing something different from what was dragged onto it.
local PING_ICONS = {
    [""] = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-main-icon.png",
    attack = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Attack-Icon.png",
    assist = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Assist-Icon.png",
    onmyway = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-OnMyWay-Icon.png",
    warning = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Warning-Icon.png",
}

local function GetMarkerPingIcon(slot)
    -- The picker stores its own icon on the slot; trust that first so the node
    -- always matches what was picked.
    if slot.icon and slot.icon ~= "" then
        return slot.icon
    end

    if slot.type == "marker" then
        return MARKER_ICONS[slot.id] or "Interface\\Icons\\Spell_ChargeNegative"
    elseif slot.type == "targetmarker" then
        return FLARE_ICONS[slot.id] or "Interface\\Icons\\Spell_ChargePositive"
    elseif slot.type == "ping" then
        return PING_ICONS[slot.id] or PING_ICONS[""]
    end
end

local function GetMarkerPingMacro(slot)
    if slot.type == "marker" then
        if slot.id == 0 then return "/cwm all"
        else return "/wm " .. slot.id end
    elseif slot.type == "targetmarker" then
        if slot.id == 0 then return "/tm 0"
        else return "/tm " .. slot.id end
    elseif slot.type == "ping" then
        if slot.id == "" then return "/ping"
        else return "/ping " .. slot.id end
    end
end

-- start/duration coming out of the cooldown APIs are "secret" values in combat:
-- comparing one directly raises an error.  (The isEnabled/isActive booleans are
-- plain and safe to read -- see Core:ArmCooldownReady.)
--
-- The spell branch below already round-tripped its numbers through tostring,
-- but the item/toy branch compared `dur > 1.5` raw.  In combat that threw, the
-- surrounding pcall swallowed it, GetSlotCooldown returned nil, and the node's
-- cooldown swirl disappeared for the whole fight -- reappearing on the way out
-- when the values stopped being secret.
local function SafeNum(value)
    local ok, asString = pcall(tostring, value)
    if not ok or type(asString) ~= "string" then return nil end
    local ok2, num = pcall(tonumber, asString)
    if ok2 and type(num) == "number" then return num end
    return nil
end

-- Read one field off a returned table without branching on its value.  A secret
-- value can be fetched and stringified, but any `if` on it raises an error.
local function SafeField(tbl, key)
    local ok, value = pcall(function() return tbl[key] end)
    if ok then return value end
    return nil
end

local function SpellCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil, nil end
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cdInfo) ~= "table" then return nil, nil end

    -- isEnabled / isActive are deliberately NOT consulted.  They can come back
    -- as secret booleans: fetching one is fine and it even stringifies as
    -- "true", but testing it in a condition throws -- which the caller's pcall
    -- then swallowed, so every spell silently reported "no cooldown".
    -- The numbers alone are enough: a spell that is not on cooldown reports
    -- duration 0.
    local d = SafeNum(SafeField(cdInfo, "duration"))
    local s = SafeNum(SafeField(cdInfo, "startTime"))
    if d and s and d > 1.5 and s > 0 then return s, d end
    return nil, nil
end

-- Toggle with /run OxedHub.ActionHub:ToggleCooldownDebug()
-- Prints what each node's cooldown lookup actually returned, so a node that
-- goes blank in combat can be traced to the exact call that failed.
function ActionHub:ToggleCooldownDebug()
    self.cdDebug = not self.cdDebug
    print("|cff00d9d9Oxed Hub:|r ActionHub cooldown debug "
        .. (self.cdDebug and "|cff88ff88ON|r" or "|cffff6666OFF|r"))
    return self.cdDebug
end

local function CDDebug(msg, force)
    if not ActionHub.cdDebug then return end
    if not force then
        -- Throttle chatter: the pass runs twice a second across every node.
        -- Errors bypass this -- hiding them is what made this hard to find.
        local now = GetTime()
        ActionHub._cdDebugAt = ActionHub._cdDebugAt or 0
        if now - ActionHub._cdDebugAt < 1 then return end
        ActionHub._cdDebugAt = now
    end
    print("|cffff9900[CD]|r " .. tostring(msg))
end

-- Paint a Cooldown frame for a slot, the way the stock action bars do it.
--
-- The numeric Cooldown:SetCooldown(start, duration) path -- which is what
-- CooldownFrame_Set uses -- is closed to addon code in 12.0
-- (SecretArguments AllowedWhenUntainted).  It simply refuses to paint, which is
-- why nodes went blank in combat no matter how carefully the numbers were
-- sanitised: the numbers were never the problem, the sink was.
--
-- The supported route is the duration object: C_Spell.GetSpellCooldownDuration
-- hands back an opaque object that Cooldown:SetCooldownFromDurationObject
-- accepts from tainted code.
--
-- Returns true when a cooldown is being shown.
-- When did the player last actually cast each spell.  This is the only
-- non-secret way to tell a real cooldown apart from the global cooldown: both
-- report isActive, and the remaining time is a secret value we cannot read.
local lastCastAt = {}

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
    spellID = tonumber(spellID)
    if spellID then lastCastAt[spellID] = GetTime() end
end)

-- True when the only thing running on this spell is the global cooldown.
--
-- A toy sitting on a 15 minute cooldown and a toy that is merely blocked for
-- 1.5s by the GCD both report isActive, so a node full of toys used to spin
-- its swirl on every unrelated cast.  Base cooldown is static and readable;
-- combined with when the spell was last actually cast it tells the two apart.
local function IsGlobalCooldownOnly(spellID)
    if not spellID then return false end

    local baseMs = 0
    if GetSpellBaseCooldown then
        local ok, b = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(b) == "number" then baseMs = b end
    end

    -- No cooldown of its own: anything active is the GCD.
    if baseMs <= 1500 then return true end

    -- Has a real cooldown, but we never saw it cast (or it has long since
    -- finished), so what is running now belongs to something else.
    local last = lastCastAt[spellID]
    if not last then return true end
    return (GetTime() - last) > (baseMs / 1000)
end

local function PaintSlotCooldown(cdFrame, spellID, ignoreGCD)
    if not cdFrame then return false end

    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration
        and cdFrame.SetCooldownFromDurationObject then
        local okInfo, info = pcall(C_Spell.GetSpellCooldown, spellID)
        -- isActive is documented as never-secret, so testing it is safe.
        local active = okInfo and type(info) == "table" and info.isActive
        if active and ignoreGCD and IsGlobalCooldownOnly(spellID) then
            active = false
        end
        if active then
            local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
            if okDur and durObj then
                local okSet = pcall(cdFrame.SetCooldownFromDurationObject, cdFrame, durObj)
                if okSet then
                    cdFrame:Show()
                    return true
                end
            end
        end
    end

    if cdFrame.Clear then pcall(cdFrame.Clear, cdFrame) end
    cdFrame:Hide()
    return false
end

-- Show how many charges a spell has left, like the stock bars do.
--
-- Charge fields can come back as secret values in restricted content, and
-- touching one throws.  issecretvalue() is the supported way to ask before
-- reading; it is only present on clients that have the restriction, hence the
-- existence check.
local function UpdateChargeCount(btn, spellID, style)
    local shown = nil

    if spellID and C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and type(info) == "table" then
            local cur, max = info.currentCharges, info.maxCharges
            local secret = issecretvalue
                and (issecretvalue(cur) or issecretvalue(max))
            if not secret then
                cur, max = tonumber(cur), tonumber(max)
                -- Only worth drawing when the spell actually banks charges.
                if cur and max and max > 1 then
                    shown = cur
                end
            end
        end
    end

    if shown == nil then
        if btn.chargeText then btn.chargeText:Hide() end
        return
    end

    if not btn.chargeText then
        btn.chargeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        -- Above the cooldown swipe, same as the keybind label.
        btn.chargeText:SetDrawLayer("OVERLAY", 7)
        btn.chargeText:SetShadowOffset(1, -1)
        btn.chargeText:SetShadowColor(0, 0, 0, 1)
    end

    btn.chargeText:ClearAllPoints()
    btn.chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", style == "ring" and -4 or -2, 2)
    btn.chargeText:SetJustifyH("RIGHT")
    -- Dim the number at zero, the way the default bars grey out a spent spell.
    if shown > 0 then
        btn.chargeText:SetTextColor(1, 1, 1, 1)
    else
        btn.chargeText:SetTextColor(0.6, 0.6, 0.6, 1)
    end
    btn.chargeText:SetText(shown)
    btn.chargeText:Show()
end

local function GetSlotCooldown(slot)
    local ok, startTime, duration = pcall(function()
        if not slot then return nil, nil end
        local id = slot.id
        if not id then return nil, nil end

        if slot.type == "spell" then
            return SpellCooldown(id)
        end

        if slot.type == "toy" or slot.type == "item" then
            local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
            local okItem, rawStart, rawDur = pcall(getCooldown, id)
            if okItem then
                local s, d = SafeNum(rawStart), SafeNum(rawDur)
                if d and s and d > 1.5 and s > 0 then return s, d end
            end

            local _, spellID = GetItemSpell(id)
            if spellID then
                return SpellCooldown(spellID)
            end
            return nil, nil
        end

        if slot.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[slot.id]
            local spellID = trg and OxedHub.Triggers and OxedHub.Triggers.GetTriggerCooldownSpellID and OxedHub.Triggers:GetTriggerCooldownSpellID(trg)
            if spellID then
                return SpellCooldown(spellID)
            end
        end
        return nil, nil
    end)
    if not ok then
        -- startTime holds the error message when pcall fails.
        CDDebug(("%s id=%s ERROR: %s"):format(
            tostring(slot and slot.type), tostring(slot and slot.id), tostring(startTime)), true)
        return nil, nil
    end

    if ActionHub.cdDebug and slot then
        CDDebug(("%s id=%s combat=%s -> start=%s dur=%s"):format(
            tostring(slot.type), tostring(slot.id), tostring(InCombatLockdown()),
            tostring(startTime), tostring(duration)))
    end

    return startTime, duration
end

-- One-shot dump of every node, printing the RAW api returns before any
-- sanitising.  If a value arrives as a secret, tostring shows it as something
-- non-numeric -- which is why SafeNum turns it into nil and the swirl vanishes
-- without any error being raised.
-- Use: /run OxedHub.ActionHub:DumpCooldowns()
function ActionHub:DumpCooldowns()
    local function Raw(v)
        local ok, s = pcall(tostring, v)
        return ok and s or "<unreadable>"
    end

    print("|cff00d9d9Oxed Hub:|r cooldown dump, combat=" .. tostring(InCombatLockdown()))
    local n = 0
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local slot = btn and btn.slotData
            if slot and slot.type and slot.id then
                n = n + 1
                local line = ("  %s id=%s"):format(tostring(slot.type), tostring(slot.id))

                if slot.type == "item" or slot.type == "toy" then
                    local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
                    local ok, s, d = pcall(getCooldown, slot.id)
                    line = line .. (" | item raw ok=%s start=%s dur=%s")
                        :format(tostring(ok), Raw(s), Raw(d))
                end

                local spellID = slot.type == "spell" and slot.id or select(2, GetItemSpell(slot.id))
                if spellID and C_Spell and C_Spell.GetSpellCooldown then
                    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
                    if ok and type(info) == "table" then
                        -- Stringifying a secret works; branching on it throws.
                        -- Test the branch explicitly so the dump shows which.
                        local branchOK = pcall(function()
                            if info.isEnabled and info.isActive then return end
                        end)
                        line = line .. (" | spell %s start=%s dur=%s enabled=%s active=%s branchOK=%s")
                            :format(tostring(spellID), Raw(info.startTime), Raw(info.duration),
                                Raw(info.isEnabled), Raw(info.isActive), tostring(branchOK))
                    else
                        line = line .. " | spell query failed"
                    end
                end

                local rs, rd = GetSlotCooldown(slot)
                line = line .. (" | RESULT start=%s dur=%s"):format(Raw(rs), Raw(rd))
                print("|cffff9900[CD]|r " .. line)
            end
        end
    end
    if n == 0 then print("|cffff9900[CD]|r no nodes with a slot found") end
end

local function GetToyAssignmentMode(slot)
    if slot and slot.type == "toy" and slot.assignmentMode == "direct" then
        return "direct"
    end
    return "mix"
end

-- Is this slot currently usable? Mirrors Blizzard action bar behaviour: a mount
-- in a no-fly/no-mount zone, an unusable spell, etc. Returns true when we can't
-- tell, so anything we don't understand keeps its normal look.
local function IsSlotUsable(slot)
    local ok, usable = pcall(function()
        if not slot then return true end
        local id = slot.id
        if not id then return true end

        if slot.type == "mount" then
            local spellID, collectionUsable
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid, _, _, isUsable = C_MountJournal.GetMountInfoByID(id)
                spellID, collectionUsable = sid, isUsable
            end

            -- The journal's isUsable only covers "do you own and can you ride
            -- this" (collected / faction / level) — it stays true indoors. The
            -- zone restriction lives on the mount's spell, which is what the
            -- default action bars grey out on.
            if collectionUsable == false then return false end

            if spellID and C_Spell and C_Spell.IsSpellUsable then
                local spellUsable = C_Spell.IsSpellUsable(spellID)
                if spellUsable ~= nil then return spellUsable and true or false end
            end

            -- Fallback for clients where the spell query gives nothing back.
            if IsIndoors and IsIndoors() then return false end
            return true
        end

        if slot.type == "spell" then
            if C_Spell and C_Spell.IsSpellUsable then
                local isUsable = C_Spell.IsSpellUsable(id)
                if isUsable ~= nil then return isUsable and true or false end
            end
            return true
        end

        if slot.type == "toy" and GetToyAssignmentMode(slot) == "direct" then
            if C_ToyBox and C_ToyBox.IsToyUsable then
                local isUsable = C_ToyBox.IsToyUsable(id)
                -- IsToyUsable returns nil while the toy is still loading; treat
                -- only an explicit false as unusable.
                if isUsable ~= nil then return isUsable and true or false end
            end
            return true
        end

        if slot.type == "item" then
            if C_Item and C_Item.IsUsableItem then
                local isUsable = C_Item.IsUsableItem(id)
                if isUsable ~= nil then return isUsable and true or false end
            end
            return true
        end

        return true
    end)
    if ok then return usable end
    return true
end

-- Turn a stored binding ("ALT-CTRL-1", "SHIFT-F3", "BUTTON4") into a short
-- readable label like "Alt+1" / "A+C+1", mirroring the default action bars.
local BINDING_KEY_SHORT = {
    MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
    BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
    PAGEUP = "PU", PAGEDOWN = "PD",
    SPACE = "Sp", ESCAPE = "Esc", INSERT = "Ins", DELETE = "Del",
    HOME = "Hm", END = "End", BACKSPACE = "BS", ENTER = "Ent", TAB = "Tab",
}

local function FormatBindingText(binding)
    if not binding or binding == "" then return nil end

    local mods = {}
    local key = binding
    while true do
        local mod, rest = key:match("^(ALT)%-(.+)$")
        if not mod then mod, rest = key:match("^(CTRL)%-(.+)$") end
        if not mod then mod, rest = key:match("^(SHIFT)%-(.+)$") end
        if not mod then break end
        table.insert(mods, mod)
        key = rest
    end

    -- Numpad and function keys keep a compact form.
    key = key:gsub("^NUMPAD", "N"):gsub("^NUMLOCK", "NL")
    key = BINDING_KEY_SHORT[key] or key

    if #mods == 0 then
        return key
    end

    -- One modifier spells out ("Alt+1"); several abbreviate so the text still
    -- fits on the node ("A+C+1").
    local prettyMods = {}
    for _, mod in ipairs(mods) do
        if #mods == 1 then
            table.insert(prettyMods, mod:sub(1, 1) .. mod:sub(2):lower())
        else
            table.insert(prettyMods, mod:sub(1, 1))
        end
    end

    return table.concat(prettyMods, "+") .. "+" .. key
end

-- Show the slot's keybinding on the node, like the default UI. Square nodes get
-- it in the top-right corner; round ("ring") nodes get it centred and nudged
-- down so the text stays inside the circle instead of hanging off the corner.
local function UpdateBindingLabel(btn, slot, size, style)
    local text = slot and FormatBindingText(slot.binding)
    if not text then
        if btn.bindingText then btn.bindingText:Hide() end
        return
    end

    if not btn.bindingText then
        btn.bindingText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        -- Top sublevel so the cooldown swipe/text can't cover it.
        btn.bindingText:SetDrawLayer("OVERLAY", 7)
        btn.bindingText:SetShadowOffset(1, -1)
        btn.bindingText:SetShadowColor(0, 0, 0, 1)
        btn.bindingText:SetTextColor(1, 1, 1, 0.9)
    end

    btn.bindingText:ClearAllPoints()
    if style == "ring" then
        btn.bindingText:SetJustifyH("CENTER")
        btn.bindingText:SetPoint("TOP", btn, "TOP", 0, -6)
    else
        btn.bindingText:SetJustifyH("RIGHT")
        btn.bindingText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
    end
    btn.bindingText:SetWidth((size or btn:GetWidth() or 44) - 4)
    btn.bindingText:SetText(text)
    btn.bindingText:Show()
end

-- The icon picker stores its own value format (not always a texture path), so
-- it has to be resolved before being handed to SetTexture.
local function ResolveCustomIcon(value)
    if not value or value == "" then return nil end
    if OxedHub.IconPicker and OxedHub.IconPicker.ResolveTexture then
        return OxedHub.IconPicker:ResolveTexture(value)
    end
    return value
end

-- ─────────────────────────────────────────────────────────────────────────
-- Proc glow: mirrors Blizzard's spell activation overlay. When the game says a
-- spell has procced, any hub node that casts that spell lights up.
-- ─────────────────────────────────────────────────────────────────────────
local activeProcSpells = {}

-- Which spell (if any) does this slot ultimately cast?
local function GetSlotSpellID(slot)
    if not slot or not slot.id then return nil end
    local ok, spellID = pcall(function()
        if slot.type == "spell" then
            return slot.id
        end
        if slot.type == "mount" then
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid = C_MountJournal.GetMountInfoByID(slot.id)
                return sid
            end
            return nil
        end
        if slot.type == "toy" or slot.type == "item" then
            local _, sid = GetItemSpell(slot.id)
            return sid
        end
        if slot.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[slot.id]
            if trg and OxedHub.Triggers and OxedHub.Triggers.GetTriggerCooldownSpellID then
                return OxedHub.Triggers:GetTriggerCooldownSpellID(trg)
            end
        end
        return nil
    end)
    return ok and spellID or nil
end

-- Is this spell currently proc-glowing? Blizzard often reports the glow against
-- a spell's base or override form rather than the exact id sitting on the node,
-- so check those variants too.
local function Variant(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

-- Ask the game directly whether a spell is currently overlay-glowing. This is
-- what the default action bars use, and it avoids the event-ID mismatch problem
-- entirely (the glow event often reports a different id than the one on the bar).
local function QueryOverlayed(spellID)
    if not spellID then return false end
    local overlayed = Variant(IsSpellOverlayed, spellID)
    if overlayed == nil and C_SpellActivationOverlay then
        overlayed = Variant(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
    end
    return overlayed == true
end

local function IsSpellProcced(spellID)
    if not spellID then return false end

    -- Direct query first, then the ids we captured from the glow events, then
    -- the spell's base / override forms for both.
    local ids = { spellID }
    local base = Variant(FindBaseSpellByID, spellID)
    if base and base ~= spellID then table.insert(ids, base) end
    local override = Variant(FindSpellOverrideByID, spellID)
    if override and override ~= spellID then table.insert(ids, override) end
    local override2 = Variant(C_Spell and C_Spell.GetOverrideSpell, spellID)
    if override2 and override2 ~= spellID then table.insert(ids, override2) end

    for _, id in ipairs(ids) do
        if activeProcSpells[id] or QueryOverlayed(id) then
            return true
        end
    end
    return false
end

-- Create the proc highlight texture. Sizing happens in StyleButton alongside
-- the move-mode glow, so it always matches the node's real size.
local function EnsureProcGlow(btn)
    if btn.procGlow then return btn.procGlow end

    local g = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.9, 0.35, 1)
    g:SetSize((btn:GetWidth() or 44) + 16, (btn:GetHeight() or 44) + 16)
    g:Hide()

    -- Gentle pulse so it reads as "ready now" without being distracting.
    -- (Animations are created via CreateAnimation("Alpha"), not CreateAlpha.)
    local anim = g:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.7)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")
    g.anim = anim

    btn.procGlow = g
    return g
end

-- Size and position the proc glow for a node of the given size. Squares get a
-- noticeably larger halo nudged left and down so it sits over the icon nicely;
-- rings stay centred on the circle.
local function LayoutProcGlow(btn, size, style)
    local g = btn.procGlow
    if not g or not size or size <= 0 then return end

    g:SetSize(size * 1.5, size * 1.5)
    g:ClearAllPoints()
    -- Both centred: the earlier square offset just made it look misaligned.
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

-- Both styles use Blizzard's bright IconAlert glow, unmasked. A circular mask
-- was tried here and looked wrong: it clips the texture's soft outer falloff,
-- turning the glow into a hard-edged ring. Left unmasked, the halo fades out
-- around a round node exactly like it does around a square one.
-- Called from StyleButton, which knows the node's style.
local function SetProcGlowShape(btn, style)
    local g = btn.procGlow
    if not g then return end

    g:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    g:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    -- Clear the mask left over from earlier sessions / style switches.
    if btn.procGlowMasked and btn.procGlowMask then
        g:RemoveMaskTexture(btn.procGlowMask)
        btn.procGlowMasked = false
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Selection highlight. Square nodes use Blizzard's CheckButtonGlow; round ones
-- get a matching circular version built from two masked discs: a gold rim that
-- sits just outside the node, plus a larger faint halo for the soft "shadow"
-- falloff the square glow has.
-- ─────────────────────────────────────────────────────────────────────────
local RING_SELECT_COLOR = { 1, 0.5, 0.05 }   -- orange

local function EnsureRingSelection(btn)
    if btn.ringSelect then return end

    -- Crisp rim: a flat disc clipped to a circle. Drawn under the node art so
    -- only the few pixels extending past the node show — that's the outline.
    local rim = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    rim:SetPoint("CENTER", btn, "CENTER", 0, 0)
    rim:SetTexture("Interface\\Buttons\\WHITE8X8")
    rim:SetVertexColor(RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3], 1)
    rim:SetBlendMode("ADD")
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(rim)
    rim:AddMaskTexture(mask)
    rim.mask = mask
    rim:Hide()
    btn.ringSelect = rim

    -- Soft halo: IconAlert has a real radial falloff, so it fades outward the
    -- way the square glow does. A masked flat disc can't — it just stops dead
    -- at the circle's edge, which is why this used to look like a hard band.
    local halo = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    halo:SetPoint("CENTER", btn, "CENTER", 0, 0)
    halo:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    halo:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    halo:SetVertexColor(RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3], 0.85)
    halo:SetBlendMode("ADD")
    halo:Hide()
    btn.ringSelectHalo = halo
end

local function LayoutRingSelection(btn, size)
    if not btn.ringSelect then return end
    -- +2.5 rather than +5: the rim only shows where it extends past the node,
    -- so halving the overhang halves the visible line thickness.
    btn.ringSelect:SetSize(size + 2.5, size + 2.5)
    btn.ringSelect.mask:SetAllPoints(btn.ringSelect)
    btn.ringSelectHalo:SetSize(size * 1.5, size * 1.5)
end

-- Single entry point for "this node is selected", so every caller gets the
-- right shape for the current style.
local function SetNodeSelected(btn, selected, style, colorMode)
    style = style or btn.nodeStyle
    
    local r, g, b = RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3]
    if colorMode == "group" then
        r, g, b = 0, 0.6, 1
    end

    if style == "ring" then
        if btn.glow then btn.glow:Hide() end
        if selected then
            EnsureRingSelection(btn)
            LayoutRingSelection(btn, btn:GetWidth() or 44)
            btn.ringSelect:SetVertexColor(r, g, b, 1)
            btn.ringSelectHalo:SetVertexColor(r, g, b, 0.85)
            btn.ringSelect:Show()
            btn.ringSelectHalo:Show()
        else
            if btn.ringSelect then btn.ringSelect:Hide() end
            if btn.ringSelectHalo then btn.ringSelectHalo:Hide() end
        end
        return
    end

    if btn.ringSelect then btn.ringSelect:Hide() end
    if btn.ringSelectHalo then btn.ringSelectHalo:Hide() end
    if btn.glow then
        btn.glow:SetShown(selected and true or false)
        if selected then
            if colorMode == "group" then
                btn.glow:SetVertexColor(0, 0.6, 1, 0.6)
            else
                btn.glow:SetVertexColor(1, 0.82, 0, 0.5)
            end
        end
    end
end

-- Show / hide the pulsing proc highlight on a node.
local function ApplyProcGlow(btn, isProcced)
    if not isProcced then
        if btn.procGlow then
            btn.procGlow:Hide()
            if btn.procGlow.anim then btn.procGlow.anim:Stop() end
        end
        return
    end

    -- Never light up a node that isn't laid out yet: an unsized pooled button
    -- would stretch the texture across the screen.
    local w = btn:GetWidth()
    if not btn:IsShown() or not w or w < 8 then
        if btn.procGlow then btn.procGlow:Hide() end
        return
    end

    local g = EnsureProcGlow(btn)
    SetProcGlowShape(btn, btn.nodeStyle)
    LayoutProcGlow(btn, w, btn.nodeStyle)
    g:Show()
    if g.anim and not g.anim:IsPlaying() then
        g.anim:Play()
    end
end

-- =========================================================================
-- Ready Highlight Glow
-- =========================================================================

local function EnsureReadyGlow(btn)
    if btn.readyGlowSquare then return end

    local square = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    square:SetPoint("CENTER", btn, "CENTER", 0, 0)
    square:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    square:SetBlendMode("ADD")
    square:Hide()
    btn.readyGlowSquare = square

    local rim = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    rim:SetPoint("CENTER", btn, "CENTER", 0, 0)
    rim:SetTexture("Interface\\Buttons\\WHITE8X8")
    rim:SetBlendMode("ADD")
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(rim)
    rim:AddMaskTexture(mask)
    rim.mask = mask
    rim:Hide()
    btn.readyGlowRingRim = rim

    local halo = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
    halo:SetPoint("CENTER", btn, "CENTER", 0, 0)
    halo:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    halo:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    halo:SetBlendMode("ADD")
    halo:Hide()
    btn.readyGlowRingHalo = halo

    local anim = btn:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    btn.readyGlowAnim = anim

    local function MakeFade(key)
        local fade = anim:CreateAnimation("Alpha")
        fade:SetChildKey(key)
        fade:SetSmoothing("IN_OUT")
        fade:SetDuration(1.2)
        return fade
    end

    btn.readyGlowFadeSquare = MakeFade("readyGlowSquare")
    btn.readyGlowFadeRim = MakeFade("readyGlowRingRim")
    btn.readyGlowFadeHalo = MakeFade("readyGlowRingHalo")
end

local function LayoutReadyGlow(btn, size, style)
    if not btn.readyGlowSquare or not size or size <= 0 then return end
    
    local scale = 1.0
    local slot = btn.slotData
    if slot and slot.readyGlowSize then
        scale = slot.readyGlowSize / 100.0
    end
    
    if style == "ring" then
        btn.readyGlowRingRim:SetSize((size + 2.5) * scale, (size + 2.5) * scale)
        btn.readyGlowRingRim.mask:SetAllPoints(btn.readyGlowRingRim)
        btn.readyGlowRingHalo:SetSize((size * 1.5) * scale, (size * 1.5) * scale)
    else
        btn.readyGlowSquare:SetSize((size * 1.7) * scale, (size * 1.7) * scale)
    end
end

local function ApplyReadyGlow(btn, isReady)
    local w = btn:GetWidth()
    if not w or w <= 0 then return end

    local slot = btn.slotData
    if not slot or not slot.showReadyGlow then
        if btn.readyGlowSquare then
            btn.readyGlowSquare:Hide()
            btn.readyGlowRingRim:Hide()
            btn.readyGlowRingHalo:Hide()
            if btn.readyGlowAnim then btn.readyGlowAnim:Stop() end
        end
        return
    end

    if not isReady then
        if btn.readyGlowSquare then
            btn.readyGlowSquare:Hide()
            btn.readyGlowRingRim:Hide()
            btn.readyGlowRingHalo:Hide()
            if btn.readyGlowAnim then btn.readyGlowAnim:Stop() end
        end
        return
    end

    EnsureReadyGlow(btn)
    LayoutReadyGlow(btn, w, btn.nodeStyle)
    
    local hex = slot.readyGlowHex or "FFFF00"
    local r, gCol, b = 1, 1, 0
    if #hex == 6 then
        local pR = tonumber(string.sub(hex, 1, 2), 16)
        local pG = tonumber(string.sub(hex, 3, 4), 16)
        local pB = tonumber(string.sub(hex, 5, 6), 16)
        if pR and pG and pB then
            r, gCol, b = pR/255, pG/255, pB/255
        end
    end

    local alphaMax = 0.8
    if slot and slot.readyGlowAlpha then
        alphaMax = (slot.readyGlowAlpha / 100.0) * 0.8
    end

    if btn.nodeStyle == "ring" then
        btn.readyGlowRingRim:SetVertexColor(r, gCol, b, 1)
        btn.readyGlowRingHalo:SetVertexColor(r, gCol, b, 0.85)
        
        btn.readyGlowFadeRim:SetFromAlpha(alphaMax)
        btn.readyGlowFadeRim:SetToAlpha(alphaMax * 0.5)
        btn.readyGlowFadeHalo:SetFromAlpha(alphaMax)
        btn.readyGlowFadeHalo:SetToAlpha(alphaMax * 0.5)
        
        btn.readyGlowSquare:Hide()
        btn.readyGlowRingRim:Show()
        btn.readyGlowRingHalo:Show()
    else
        btn.readyGlowSquare:SetVertexColor(r, gCol, b, 1)
        
        btn.readyGlowFadeSquare:SetFromAlpha(alphaMax)
        btn.readyGlowFadeSquare:SetToAlpha(alphaMax * 0.5)
        
        btn.readyGlowSquare:Show()
        btn.readyGlowRingRim:Hide()
        btn.readyGlowRingHalo:Hide()
    end

    if not btn.readyGlowAnim:IsPlaying() then
        btn.readyGlowAnim:Play()
    end
end

-- Apply / clear the "can't use this right now" dimming on a button's icon(s).
local function ApplyUsabilityShading(btn, usable)
    local textures = {}
    if btn.icon then table.insert(textures, btn.icon) end
    if btn.splitIcon then
        local texs = btn.splitIcon.texs
        if not texs and btn.splitIcon.leftTexture then
            texs = { btn.splitIcon.leftTexture, btn.splitIcon.rightTexture }
        end
        for _, t in ipairs(texs or {}) do table.insert(textures, t) end
    end

    for _, tex in ipairs(textures) do
        if tex.SetDesaturated then tex:SetDesaturated(not usable) end
        if usable then
            tex:SetVertexColor(1, 1, 1)
        else
            tex:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
end

local function GetDirectToyDisplay(itemID)
    local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
    local icon = toyIcon

    if not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    if not icon then
        local _, _, _, _, instantIcon = GetItemInfoInstant(itemID)
        icon = instantIcon
    end

    return toyName, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetActionHubToyMacroText(slot)
    if not slot or slot.type ~= "toy" or not slot.id then
        return ""
    end

    if GetToyAssignmentMode(slot) == "direct" then
        local toyName = GetDirectToyDisplay(slot.id)
        if toyName and PlayerHasToy(slot.id) then
            return "#showtooltip\n/use " .. toyName .. "\n"
        end
        return ""
    end

    local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[slot.id]
    if mixData and OxedHub.Toys and OxedHub.Toys.GetMixMacroText then
        -- resolveRandom=true: this runs on the click's PreClick, so random mode
        -- resolves to a single usable /use <toy> instead of unreliable /castrandom.
        return OxedHub.Toys:GetMixMacroText(mixData, true) or ""
    end

    return ""
end

function ActionHub:UpdateWidgetCooldowns()
    local widgets = self.widgets or {}
    for _, w in ipairs(widgets) do
        if w and w.buttons then
            for _, btn in ipairs(w.buttons) do
                -- Each node is updated in isolation.  This pass runs from a
                -- 0.5s ticker over every node, and an error on one of them used
                -- to abort the whole loop -- so a single bad slot could leave
                -- every node after it without a cooldown until the next pass
                -- that happened to avoid it.
                local okBtn, btnErr = pcall(function()
                -- Dim icons that can't be used right now (e.g. a mount while
                -- indoors / in a no-mount zone), like the default action bars.
                if btn and btn:IsShown() and btn.slotData then
                    ApplyUsabilityShading(btn, IsSlotUsable(btn.slotData))
                    ApplyProcGlow(btn, IsSpellProcced(GetSlotSpellID(btn.slotData)))
                end

                if btn and btn.cooldown1 and btn.cooldown2 and btn:IsShown() then
                    local slot = btn.slotData
                    local mixData
                    if slot and slot.type == "toy" and GetToyAssignmentMode(slot) == "mix" then
                        mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[slot.id]
                    elseif slot and slot.type == "emote" then
                        local mapping = OxedHub.db.profile.emotionMappings and OxedHub.db.profile.emotionMappings[slot.id]
                        if mapping and mapping.toyMacro then
                            mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[mapping.toyMacro]
                        end
                    end

                    -- Per-hub: keep the global cooldown off the nodes.
                    local hubForGCD = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
                        or ActionHub:GetActiveHubDB()
                    local hideGCD = not (hubForGCD and hubForGCD.showGlobalCooldown == true)

                    local isReady = true
                    if slot and slot.type == "toy" and GetToyAssignmentMode(slot) == "direct" then
                        btn.cooldown2:Hide()
                        if PaintSlotCooldown(btn.cooldown1, GetSlotSpellID(slot), hideGCD) then
                            StyleCooldownText(btn.cooldown1, 0)
                            isReady = false
                        end
                    elseif type(mixData) == "table" and mixData.slots then
                        local cdFrames = { btn.cooldown1, btn.cooldown2 }
                        local mixReady = false
                        for i = 1, 2 do
                            local mixSlot = mixData.slots[i]
                            local cdFrame = cdFrames[i]
                            if PaintSlotCooldown(cdFrame, GetSlotSpellID(mixSlot), hideGCD) then
                                StyleCooldownText(cdFrame, i == 1 and 7 or -7)
                            else
                                mixReady = true
                            end
                        end
                        isReady = mixReady
                    else
                        -- Handle single cooldown (for triggers/etc)
                        btn.cooldown2:Hide()
                        if PaintSlotCooldown(btn.cooldown1, GetSlotSpellID(slot), hideGCD) then
                            StyleCooldownText(btn.cooldown1, 0)
                            isReady = false
                        end
                    end

                    -- Charge counter sits outside the branches above: a spell
                    -- can bank charges whether or not a cooldown is running.
                    local hubForStyle = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
                        or ActionHub:GetActiveHubDB()
                    UpdateChargeCount(btn, GetSlotSpellID(slot), hubForStyle and hubForStyle.style)

                    ApplyReadyGlow(btn, isReady)
                end
                end)

                if not okBtn then
                    CDDebug("node update failed: " .. tostring(btnErr))
                end
            end
        end
    end
end

-- Refresh only the usable/unusable dimming (cheap: no cooldown maths).
function ActionHub:UpdateUsability()
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            if btn and btn:IsShown() and btn.slotData then
                ApplyUsabilityShading(btn, IsSlotUsable(btn.slotData))
            end
        end
    end
end

-- Blizzard fires SPELL_UPDATE_USABLE whenever anything changes what you can
-- cast — including walking in and out of a building, which is what greys out
-- mounts. Waiting for the 0.5s cooldown ticker left nodes stale (and the ticker
-- doesn't run at all when the widget is hidden), so drive it from the events.
local usabilityFrame = CreateFrame("Frame")
usabilityFrame:RegisterEvent("SPELL_UPDATE_USABLE")
usabilityFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
usabilityFrame:RegisterEvent("ZONE_CHANGED")
usabilityFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
usabilityFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
usabilityFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
usabilityFrame:SetScript("OnEvent", function(_, event)
    if not OxedHub.ActionHub then return end
    if not OxedHub.db then return end
    
    if event == "PLAYER_ENTERING_WORLD" then
        OxedHub.ActionHub:RefreshAllWidgets()
    end
    
    OxedHub.ActionHub:UpdateUsability()
    -- Zone transitions can report the old state for a moment, so check again.
    C_Timer.After(0.3, function()
        if OxedHub.ActionHub and OxedHub.db then OxedHub.ActionHub:UpdateUsability() end
    end)
end)

-- Refresh only the proc highlights (cheap: no cooldown maths).
function ActionHub:UpdateProcGlows()
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            if btn and btn:IsShown() and btn.slotData then
                ApplyProcGlow(btn, IsSpellProcced(GetSlotSpellID(btn.slotData)))
            elseif btn then
                ApplyProcGlow(btn, false)
            end
        end
    end
end

-- Two separate Blizzard systems fire on a proc:
--   *_OVERLAY_GLOW_SHOW/HIDE  → the glow drawn on ACTION BUTTONS (what we want)
--   *_OVERLAY_SHOW/HIDE       → the large screen-edge artwork
-- Register both so a node lights up regardless of which one the spell uses.
local procGlowFrame = CreateFrame("Frame")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
procGlowFrame:SetScript("OnEvent", function(_, event, spellID)
    spellID = tonumber(spellID)
    if not spellID then return end

    local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        or (event == "SPELL_ACTIVATION_OVERLAY_SHOW")
    activeProcSpells[spellID] = isShow or nil

    if OxedHub.debug then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        print(("|cffffcc00[OxedHub-Debug]|r %s spellID=%d (%s)"):format(
            event, spellID, info and info.name or "?"))
    end

    if OxedHub.ActionHub then
        OxedHub.ActionHub:UpdateProcGlows()
    end
end)

-- The 0.5s ticker would eventually pick these up, but a charge spent or a
-- cooldown starting should show immediately rather than up to half a second
-- later.
local cooldownEventFrame = CreateFrame("Frame")
cooldownEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cooldownEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
cooldownEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
cooldownEventFrame:SetScript("OnEvent", function()
    if OxedHub.ActionHub and OxedHub.ActionHub.UpdateWidgetCooldowns then
        OxedHub.ActionHub:UpdateWidgetCooldowns()
    end
end)

function ActionHub:QueueCooldownRefresh()
    self:UpdateWidgetCooldowns()

    local delays = { 0.05, 0.2, 0.5, 1.0 }
    for _, delay in ipairs(delays) do
        C_Timer.After(delay, function()
            if OxedHub and OxedHub.ActionHub then
                OxedHub.ActionHub:UpdateWidgetCooldowns()
            end
        end)
    end
end

local function StyleButton(btn, style, size, isPreview)
    -- Remembered so the proc glow can pick a matching shape when it's created
    -- later (it's built lazily, the first time the node actually procs).
    btn.nodeStyle = style
    SetProcGlowShape(btn, style)

    -- Round nodes need a round cooldown sweep, otherwise the dark wedge shows
    -- square corners poking outside the circle.
    for _, cd in ipairs({ btn.cooldown1, btn.cooldown2 }) do
        if cd then
            if cd.SetUseCircularEdge then
                pcall(cd.SetUseCircularEdge, cd, style == "ring")
            end
            if cd.SetSwipeTexture then
                if style == "ring" then
                    cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                else
                    cd:SetSwipeTexture("Interface\\Cooldown\\ping4")
                end
            end
        end
    end

    -- Per-hub background opacity (default 0.5). Lets users fade the dark square /
    -- ring behind an icon (e.g. so an emoji doesn't sit on a black box).
    local styleHubDB = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
        or (btn:GetParent() and btn:GetParent().hubIndex and ActionHub:GetHubDB(btn:GetParent().hubIndex))
        or ActionHub:GetActiveHubDB()
    local bgAlpha = 0.5
    if styleHubDB and styleHubDB.nodeBackgroundAlpha ~= nil then
        bgAlpha = styleHubDB.nodeBackgroundAlpha
    end

    local innerSize = style == "ring" and (size - 2) or (size - 4)
    local zoom = 8
    local iconSize = innerSize + zoom
    btn.icon:SetSize(iconSize, iconSize)
    if btn.splitIcon then
        btn.splitIcon:SetSize(iconSize, iconSize)
        local texs = btn.splitIcon.texs
        if not texs and btn.splitIcon.leftTexture then
            texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
        end
        if texs then
            local numTexs = #texs
            local hw = iconSize / 2
            if numTexs == 2 then
                texs[1]:SetSize(hw, iconSize)
                texs[2]:SetSize(hw, iconSize)
            elseif numTexs == 3 then
                texs[1]:SetSize(hw, iconSize)
                texs[2]:SetSize(hw, hw)
                texs[3]:SetSize(hw, hw)
            elseif numTexs == 4 then
                texs[1]:SetSize(hw, hw)
                texs[2]:SetSize(hw, hw)
                texs[3]:SetSize(hw, hw)
                texs[4]:SetSize(hw, hw)
            end
        end
    end

    if style == "ring" then
        btn:SetBackdrop(nil)
        if not btn.ringBg then
            -- Golden thin border
            btn.ringBg = btn:CreateTexture(nil, "BACKGROUND")
            btn.ringBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            
            btn.ringBgMask = btn:CreateMaskTexture()
            btn.ringBgMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringBgMask:SetAllPoints(btn.ringBg)
            btn.ringBg:AddMaskTexture(btn.ringBgMask)

            -- Dark inner fill
            btn.ringFill = btn:CreateTexture(nil, "BORDER")
            btn.ringFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringFill:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.ringFill:SetVertexColor(0, 0, 0, 0)

            btn.ringFillMask = btn:CreateMaskTexture()
            btn.ringFillMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringFillMask:SetAllPoints(btn.ringFill)
            btn.ringFill:AddMaskTexture(btn.ringFillMask)
            
        end

        -- Ensure masking is applied every refresh (since icons/splitIcons can change)
        if not btn.ringMask then
            btn.ringMask = btn:CreateMaskTexture()
            btn.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        btn.ringMask:ClearAllPoints()
        btn.ringMask:SetAllPoints(btn.ringFill)
        btn.icon:AddMaskTexture(btn.ringMask)
        if btn.plus then btn.plus:AddMaskTexture(btn.ringMask) end
        if btn.squareHighlight then btn.squareHighlight:AddMaskTexture(btn.ringMask) end

        if btn.splitIcon then
            local texs = btn.splitIcon.texs
            if not texs and btn.splitIcon.leftTexture then
                texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
            end
            if texs then
                if not btn.splitMasks then btn.splitMasks = {} end
                local sx, sy = btn.splitIcon:GetSize()
                for i, t in ipairs(texs) do
                    if not btn.splitMasks[i] then
                        btn.splitMasks[i] = btn:CreateMaskTexture(nil, "ARTWORK")
                        btn.splitMasks[i]:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    end
                    btn.splitMasks[i]:ClearAllPoints()
                    btn.splitMasks[i]:SetAllPoints(btn.ringFill)
                    t:AddMaskTexture(btn.splitMasks[i])
                end
            end
        end

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn.ringBg:SetVertexColor(1, 0.95, 0.4, 1)
        else
            -- scaled so the default (bgAlpha 0.5) keeps the original 0.2 look
            btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, bgAlpha * 0.4)
        end
        
        LayoutProcGlow(btn, size, style)
        if btn.glow then
            -- CheckButtonGlow's bright ring sits well inside the texture bounds,
            -- so the texture has to be ~1.7x the node for the ring to land on
            -- the node's edge instead of over the icon.
            btn.glow:SetSize(size * 1.7, size * 1.7)
        end
    else
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, bgAlpha)

        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn:SetBackdropBorderColor(1, 0.95, 0.4, 1)
        else
            -- fade the border with the opacity slider (scaled so 0.5 keeps 0.8)
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, math.min(1, bgAlpha * 1.6))
        end

        if btn.ringBg then btn.ringBg:Hide() end
        if btn.ringFill then btn.ringFill:Hide() end
        if btn.ringMask then 
            btn.icon:RemoveMaskTexture(btn.ringMask) 
            if btn.plus then btn.plus:RemoveMaskTexture(btn.ringMask) end
            if btn.squareHighlight then btn.squareHighlight:RemoveMaskTexture(btn.ringMask) end
        end
        if btn.splitIcon then
            local texs = btn.splitIcon.texs
            if not texs and btn.splitIcon.leftTexture then
                texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
            end
            if texs and btn.splitMasks then
                for i, t in ipairs(texs) do
                    if btn.splitMasks[i] then
                        t:RemoveMaskTexture(btn.splitMasks[i])
                    end
                end
            end
        end
        -- Rings use their own circular selection art instead of the square
        -- CheckButtonGlow, so keep it sized with the node.
        if btn.glow then btn.glow:SetSize(size * 1.7, size * 1.7) end
        LayoutRingSelection(btn, size)
        LayoutProcGlow(btn, size, style)
    end
end

function ActionHub:Init()
    self.editingSide = self.editingSide or "primary"
    -- Migration: move testRing data to actionHub if it exists
    local profile = OxedHub.db.profile
    if profile.testRing and not profile.actionHub then
        profile.actionHub = profile.testRing
    end
    
    -- Ensure data exists
    if not profile.actionHub then
        profile.actionHub = CreateDefaultHubData(1)
    end

    -- Migration: move single-hub data into hubs[1]
    local ah = profile.actionHub
    if not ah.hubs then
        ah.hubs = {}
        ah.hubs[1] = EnsureHubData({
            name = ah.name or "Hub 1",
            slots = ah.slots or {},
            secondarySlots = ah.secondarySlots or {},
            dualSideEnabled = ah.dualSideEnabled,
            dualSideLayout = ah.dualSideLayout or "horizontal",
            quadrant = ah.quadrant or "bottom-right",
            onScreen = ah.onScreen or false,
            widgetPosition = ah.widgetPosition or { x = 0, y = 0 },
            widgetUnlocked = ah.widgetUnlocked or false,
            hideInCombat = ah.hideInCombat,
            showLogoWhenLocked = ah.showLogoWhenLocked,
            style = ah.style or "square",
            globalNodeSize = ah.globalNodeSize,
            nodeLineSize = ah.nodeLineSize,
            allowAnimations = ah.allowAnimations,
        }, 1)
        ah.activeHub = 1
        -- Clean old top-level keys (keep hubs, activeHub)
        ah.slots = nil
        ah.secondarySlots = nil
        ah.dualSideEnabled = nil
        ah.dualSideLayout = nil
        ah.quadrant = nil
        ah.onScreen = nil
        ah.widgetPosition = nil
        ah.widgetUnlocked = nil
        ah.hideInCombat = nil
        ah.showLogoWhenLocked = nil
        ah.style = nil
        ah.globalNodeSize = nil
        ah.nodeLineSize = nil
        ah.allowAnimations = nil
    end

    -- (EmotionRing hook removed - ActionHub manages reactions independently)

    self:EnsureCombatVisibilityEvents()

    self.widgets = self.widgets or {}
    for i = 1, #ah.hubs do
        self:CreateWidget(i)
    end
    self:RefreshAllWidgets()
end

function ActionHub:CreateWidget(hubIndex)
    if not self.widgets then self.widgets = {} end
    if self.widgets[hubIndex] then return self.widgets[hubIndex] end

    local w = CreateFrame("Frame", "OxedHubActionHubWidget" .. hubIndex, UIParent)
    w:SetSize(300, 300)
    w:SetFrameStrata("MEDIUM")
    w:SetFrameLevel(10)
    w:SetMovable(true)
    w:EnableMouse(false)
    -- Allow free positioning anywhere on screen (removed clamping restriction)
    w:SetClampedToScreen(false)
    w.hubIndex = hubIndex

    -- Movable background anchor (visible drag handle)
    local anchor = CreateFrame("Frame", nil, w, "BackdropTemplate")
    anchor:SetSize(48, 48)
    anchor:SetPoint("CENTER", w, "CENTER", 0, 0)
    anchor:SetFrameLevel(w:GetFrameLevel() + 20)
    anchor:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    anchor:SetBackdropColor(0, 0, 0, 0)
    anchor:SetBackdropBorderColor(0, 0, 0, 0)
    anchor:Hide()
    w.anchor = anchor

    local anchorTex = anchor:CreateTexture(nil, "OVERLAY")
    anchorTex:SetAllPoints()
    anchorTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")
    anchor.tex = anchorTex

    local anchorLabel = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchorLabel:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    anchorLabel:SetText("")
    anchorLabel:SetTextColor(1, 1, 1)
    anchor.label = anchorLabel

    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        local parent = self:GetParent()
        local hubDB = ActionHub:GetHubDB(parent.hubIndex)
        local moveMode = ActionHub:IsMinimizedMoveMode(parent.hubIndex) or (ActionHub.pickerDialog and ActionHub.pickerDialog.moveNodeMode and ActionHub:GetActiveHubIndex() == parent.hubIndex)
        if not moveMode and (not parent:IsMovable() or not (hubDB and hubDB.widgetUnlocked)) then
            parent.isMoving = false
            return
        end
        
        if moveMode then
            -- In move mode, drag repositions the logo offset (not the whole widget)
            local scale = UIParent:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            self.logoDragStartCursorX = cursorX / scale
            self.logoDragStartCursorY = cursorY / scale
            self.logoDragStartOffsetX = (hubDB and hubDB.logoOffsetX) or 0
            self.logoDragStartOffsetY = (hubDB and hubDB.logoOffsetY) or 0
            self.isDraggingLogo = true
            self:SetScript("OnUpdate", function(f)
                local cx, cy = GetCursorPosition()
                cx = cx / scale
                cy = cy / scale
                local dx = cx - f.logoDragStartCursorX
                local dy = cy - f.logoDragStartCursorY
                local newX = math.floor(f.logoDragStartOffsetX + dx + 0.5)
                local newY = math.floor(f.logoDragStartOffsetY + dy + 0.5)
                if hubDB then
                    hubDB.logoOffsetX = newX
                    hubDB.logoOffsetY = newY
                end
                f:ClearAllPoints()
                f:SetPoint("CENTER", parent, "CENTER", newX, newY)
            end)
        else
            parent:StartMoving()
            parent.isMoving = true
        end
    end)
    anchor:SetScript("OnDragStop", function(self)
        local parent = self:GetParent()
        
        if self.isDraggingLogo then
            self:SetScript("OnUpdate", nil)
            self.isDraggingLogo = false
            -- Prevent OnMouseUp from toggling the window
            self._justDraggedLogo = true
            C_Timer.After(0.15, function() self._justDraggedLogo = false end)
            ActionHub:RefreshWidget()
            return
        end
        
        if not parent.isMoving then
            return
        end
        parent:StopMovingOrSizing()
        
        -- Use a tiny delay to reset isMoving so it doesn't trigger the click handler
        C_Timer.After(0.1, function() parent.isMoving = false end)

        local centerX, centerY = parent:GetCenter()
        local uiCenterX, uiCenterY = UIParent:GetCenter()
        if centerX and uiCenterX then
            local x = centerX - uiCenterX
            local y = centerY - uiCenterY
            local hubDB = ActionHub:GetHubDB(parent.hubIndex)
            if hubDB then
                hubDB.widgetPosition = { x = x, y = y }
            end
            parent:ClearAllPoints()
            parent:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end)

    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            local parent = self:GetParent()
            if not parent.isMoving and not self._justDraggedLogo then
                if OxedHub.UI and OxedHub.UI.ToggleMainWindow then
                    OxedHub.UI:ToggleMainWindow()
                end
            end
        end
    end)

    w.visibilityElapsed = 0
    w:SetScript("OnUpdate", function(self, elapsed)
        local hubDB = ActionHub:GetHubDB(self.hubIndex)
        if hubDB and hubDB.onScreen and hubDB.hideInCombat then
            self.visibilityElapsed = (self.visibilityElapsed or 0) + (elapsed or 0)
            if self.visibilityElapsed >= 0.05 then
                self.visibilityElapsed = 0
                ActionHub:ApplyWidgetCombatVisibility(self, hubDB)
            end

            local currentAlpha = self:GetAlpha() or 1
            local targetAlpha = self.combatTargetAlpha
            if targetAlpha == nil then
                targetAlpha = InCombatLockdown() and 0 or 1
            end

            local speed = self.combatFadeSpeed or 8
            local step = math.min(1, (elapsed or 0) * speed)
            local newAlpha = currentAlpha + (targetAlpha - currentAlpha) * step
            if math.abs(targetAlpha - newAlpha) < 0.02 then
                newAlpha = targetAlpha
            end
            ApplyWidgetVisualAlpha(self, newAlpha)
        elseif self:GetAlpha() ~= 1 then
            self.combatTargetAlpha = 1
            ApplyWidgetVisualAlpha(self, 1)
        end
    end)

    w.buttons = {}

    -- Move-mode "blue zone" overlay. Shown only during minimized move mode. Sits
    -- below the node buttons (which keep their own node-drag), so dragging an
    -- empty part of the overlay moves the whole widget set.
    -- Blue zone size matches the editor preview (430) plus ~10%, centered on the
    -- widget. moveZoneHalf is used to clamp node dragging inside the zone.
    w.moveZoneHalf = 235
    local moveOverlay = CreateFrame("Frame", nil, w, "BackdropTemplate")
    moveOverlay:SetSize(w.moveZoneHalf * 2, w.moveZoneHalf * 2)
    moveOverlay:SetPoint("CENTER", w, "CENTER", 0, 0)
    moveOverlay:SetFrameLevel(w:GetFrameLevel())
    moveOverlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    moveOverlay:SetBackdropColor(0.1, 0.4, 0.9, 0.22)
    moveOverlay:SetBackdropBorderColor(0.3, 0.6, 1, 0.9)
    moveOverlay:EnableMouse(true)
    moveOverlay:RegisterForDrag("LeftButton")
    moveOverlay:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local parent = self:GetParent()
        parent:SetMovable(true)
        parent:StartMoving()
        parent.isMoving = true
    end)
    moveOverlay:SetScript("OnDragStop", function(self)
        local parent = self:GetParent()
        parent:StopMovingOrSizing()
        C_Timer.After(0.1, function() parent.isMoving = false end)
        local centerX, centerY = parent:GetCenter()
        local uiCenterX, uiCenterY = UIParent:GetCenter()
        if centerX and uiCenterX then
            local x = centerX - uiCenterX
            local y = centerY - uiCenterY
            local hubDB = ActionHub:GetHubDB(parent.hubIndex)
            if hubDB then hubDB.widgetPosition = { x = x, y = y } end
            parent:ClearAllPoints()
            parent:SetPoint("CENTER", UIParent, "CENTER", x, y)
        end
    end)
    local moveLabel = moveOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    moveLabel:SetPoint("TOP", moveOverlay, "TOP", 0, -6)
    moveLabel:SetWidth(280)
    moveLabel:SetJustifyH("CENTER")
    moveLabel:SetText(L["AH_MOVE_MODE_DRAG_SET"] or "Move Mode  â€”  drag nodes; drag here to move the whole set")
    moveLabel:SetTextColor(0.8, 0.9, 1, 1)
    moveOverlay:Hide()
    w.moveOverlay = moveOverlay

    w:Hide()

    self.widgets[hubIndex] = w
    return w
end

function ActionHub:GetQuadrant(hubDB)
    local db = hubDB or self:GetActiveHubDB()
    return db.quadrant or "bottom-right"
end

function ActionHub:GetEditedSide()
    return self.editingSide or "primary"
end

function ActionHub:SetEditedSide(side)
    self.editingSide = (side == "secondary") and "secondary" or "primary"
end

function ActionHub:GetSlotsForSide(hubDB, side)
    local db = EnsureHubData(hubDB or self:GetActiveHubDB())
    if side == "secondary" then
        db.secondarySlots = db.secondarySlots or {}
        return db.secondarySlots
    end
    db.slots = db.slots or {}
    return db.slots
end

-- Put a slot's content onto the WoW cursor (for shift-drag between nodes / off).
-- Returns true if something was actually placed on the cursor. Toys are items,
-- so C_Item.PickupItem works and GetCursorInfo reports them as "item" (the drop
-- handler re-detects toys via C_ToyBox.GetToyInfo).
function ActionHub:PickupSlotToCursor(slot)
    if not slot or not slot.type then return false end
    -- A toy slot in "mix" mode has a MIX NAME (string) as its id, not an itemID —
    -- those can't go on the WoW cursor. Only numeric ids are pickup-able.
    local numericId = type(slot.id) == "number" and slot.id or nil
    ClearCursor()
    if slot.type == "toy" then
        if not numericId then return false end -- toy mix; use internal drag instead
        if C_ToyBox and C_ToyBox.PickupToyBoxItem then
            C_ToyBox.PickupToyBoxItem(numericId)
        elseif C_Item and C_Item.PickupItem then
            C_Item.PickupItem(numericId)
        end
    elseif slot.type == "item" then
        if not numericId then return false end
        if C_Item and C_Item.PickupItem then C_Item.PickupItem(numericId) end
    elseif slot.type == "spell" then
        if not numericId then return false end
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(numericId) end
    elseif slot.type == "macro" then
        if PickupMacro then PickupMacro(slot.id) end
    else
        -- emotes / mounts / other types can't be round-tripped through the cursor
        return false
    end
    return GetCursorInfo() ~= nil
end

function ActionHub:SetQuadrant(q)
    local db = self:GetActiveHubDB()
    db.quadrant = q
    if self.tab then
        self:RefreshTab()
    else
        self:RefreshAllWidgets()
    end
end

local function IsMouseOverActionHubWidget(w)
    if not w then
        return false
    end

    if MouseIsOver(w) then
        return true
    end

    if w.anchor and MouseIsOver(w.anchor) then
        return true
    end

    if w.buttons then
        for _, btn in ipairs(w.buttons) do
            if btn and btn:IsShown() and MouseIsOver(btn) then
                return true
            end
        end
    end

    return false
end

function ActionHub:ApplyWidgetCombatVisibility(w, db)
    if not w or not db then
        return
    end

    local shouldHide = db.onScreen and db.hideInCombat and InCombatLockdown()
    local targetAlpha = 1
    if shouldHide then
        targetAlpha = IsMouseOverActionHubWidget(w) and 1 or 0
    end

    w.combatTargetAlpha = targetAlpha
    w.combatFadeActive = shouldHide
    w.combatFadeSpeed = 8

    if not shouldHide then
        w:SetAlpha(1)
        if w.anchor then
            w.anchor:SetAlpha(1)
        end
        if w.buttons then
            for _, btn in ipairs(w.buttons) do
                if btn then
                    btn:SetAlpha(1)
                    if btn.splitIcon then
                        btn.splitIcon:SetAlpha(1)
                    end
                    if btn.cooldown1 then
                        btn.cooldown1:SetAlpha(1)
                    end
                    if btn.cooldown2 then
                        btn.cooldown2:SetAlpha(1)
                    end
                end
            end
        end
    end
end

ApplyWidgetVisualAlpha = function(w, alpha)
    if not w then
        return
    end

    w:SetAlpha(alpha)

    if w.anchor then
        w.anchor:SetAlpha(alpha)
end

    if w.buttons then
        for _, btn in ipairs(w.buttons) do
            if btn then
                btn:SetAlpha(alpha)
                if btn.splitIcon then
                    btn.splitIcon:SetAlpha(alpha)
                end
                if btn.cooldown1 then
                    btn.cooldown1:SetAlpha(alpha)
                end
                if btn.cooldown2 then
                    btn.cooldown2:SetAlpha(alpha)
                end
            end
        end
    end
end

function ActionHub:RefreshCombatVisibility()
    if not self.widgets then
        return
    end

    for i, w in ipairs(self.widgets) do
        if w then
            self:ApplyWidgetCombatVisibility(w, EnsureHubData(self:GetHubDB(i), i))
        end
    end
end

function ActionHub:UpdateCombatVisibilityTicker()
    local shouldRun = false
    local hubs = self:GetHubs() or {}

    if InCombatLockdown() then
        for i = 1, #hubs do
            local hubDB = EnsureHubData(hubs[i], i)
            if hubDB.onScreen and hubDB.hideInCombat then
                shouldRun = true
                break
            end
        end
    end

    if shouldRun then
        if not self.combatVisibilityTicker then
            self.combatVisibilityTicker = C_Timer.NewTicker(0.1, function()
                ActionHub:RefreshCombatVisibility()
            end)
        end
    elseif self.combatVisibilityTicker then
        self.combatVisibilityTicker:Cancel()
        self.combatVisibilityTicker = nil
    end

    self:RefreshCombatVisibility()
end

function ActionHub:EnsureCombatVisibilityEvents()
    if self.combatVisibilityEvents then
        return
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function()
        ActionHub:UpdateCombatVisibilityTicker()
    end)
    self.combatVisibilityEvents = f
end

function ActionHub:IsPreviewMoveModeActiveForButton(btn)
    local dialog = self.pickerDialog
    return btn
        and dialog
        and dialog:IsShown()
        and dialog.moveNodeMode
        and btn.slotIndex
        and btn.slotSide
end

function ActionHub:BeginPreviewNodeDrag(btn)
    if not self:IsPreviewMoveModeActiveForButton(btn) then
        return
    end

    local dialog = self.pickerDialog
    dialog.slotIndex = btn.slotIndex
    dialog.slotSide = btn.slotSide
    local activeDB = self:GetActiveHubDB()
    local slots = self:GetSlotsForSide(activeDB, btn.slotSide)
    local slot = slots and slots[btn.slotIndex]
    if not slot then
        return
    end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    btn.dragStartCursorX = cursorX / scale
    btn.dragStartCursorY = cursorY / scale
    btn.dragStartOffsetX = slot.nodePositionX or 0
    btn.dragStartOffsetY = slot.nodePositionY or 0
    btn.isDraggingNode = true

    if dialog.groupSelection and dialog.groupSelection[btn.slotSide .. "_" .. btn.slotIndex] then
        btn.dragGroup = {}
        for k, v in pairs(dialog.groupSelection) do
            local sideSlots = self:GetSlotsForSide(activeDB, v.side)
            local s = sideSlots and sideSlots[v.index]
            if s then
                table.insert(btn.dragGroup, {
                    side = v.side,
                    index = v.index,
                    slot = s,
                    startOffsetX = s.nodePositionX or 0,
                    startOffsetY = s.nodePositionY or 0
                })
            end
        end
    else
        btn.dragGroup = nil
    end

    btn:SetScript("OnUpdate", function(self)
        local currentX, currentY = GetCursorPosition()
        currentX = currentX / scale
        currentY = currentY / scale

        local deltaX = currentX - self.dragStartCursorX
        local deltaY = currentY - self.dragStartCursorY
        local newOffsetX = math.floor((self.dragStartOffsetX + deltaX) + 0.5)
        local newOffsetY = math.floor((self.dragStartOffsetY + deltaY) + 0.5)

        local previewParent = self:GetParent()
        
        local rawX = self.basePreviewX + newOffsetX
        local rawY = self.basePreviewY + newOffsetY
        rawX, rawY = ActionHub:SnapMovePosition(previewParent, rawX, rawY, self)
        newOffsetX = rawX - self.basePreviewX
        newOffsetY = rawY - self.basePreviewY

        local previewWidth = previewParent and previewParent:GetWidth() or 400
        local previewHeight = previewParent and previewParent:GetHeight() or 400
        local halfSize = (self:GetWidth() or 44) / 2

        local minOffsetX = halfSize - self.basePreviewX
        local maxOffsetX = (previewWidth - halfSize) - self.basePreviewX
        local minOffsetY = (-(previewHeight - halfSize)) - self.basePreviewY
        local maxOffsetY = (-halfSize) - self.basePreviewY

        newOffsetX = math.max(minOffsetX, math.min(maxOffsetX, newOffsetX))
        newOffsetY = math.max(minOffsetY, math.min(maxOffsetY, newOffsetY))

        local actualDeltaX = newOffsetX - self.dragStartOffsetX
        local actualDeltaY = newOffsetY - self.dragStartOffsetY

        if self.dragGroup then
            for _, item in ipairs(self.dragGroup) do
                local nx = item.startOffsetX + actualDeltaX
                local ny = item.startOffsetY + actualDeltaY
                item.slot.nodePositionX = nx
                item.slot.nodePositionY = ny
                
                if ActionHub.tab and ActionHub.tab.ringButtons then
                    for _, b in ipairs(ActionHub.tab.ringButtons) do
                        if b.slotSide == item.side and b.slotIndex == item.index then
                            b:ClearAllPoints()
                            b:SetPoint("CENTER", b:GetParent(), "TOPLEFT", b.basePreviewX + nx, b.basePreviewY + ny)
                            break
                        end
                    end
                end
            end
        else
            slot.nodePositionX = newOffsetX
            slot.nodePositionY = newOffsetY
            self:ClearAllPoints()
            self:SetPoint("CENTER", self:GetParent(), "TOPLEFT", self.basePreviewX + newOffsetX, self.basePreviewY + newOffsetY)
        end

        if dialog.posXVal then dialog.posXVal:SetText(tostring(newOffsetX)) end
        if dialog.posXInput then dialog.posXInput:SetText(tostring(newOffsetX)) end
        if dialog.posYVal then dialog.posYVal:SetText(tostring(newOffsetY)) end
        if dialog.posYInput then dialog.posYInput:SetText(tostring(newOffsetY)) end
    end)
end

function ActionHub:EndPreviewNodeDrag(btn)
    if not btn or not btn.isDraggingNode then
        return
    end

    btn.isDraggingNode = false
    btn.dragGroup = nil
    btn:SetScript("OnUpdate", nil)
    self:RefreshWidget()
    self:RefreshTab()
end

function ActionHub:AlignGroup(targetSide, targetIndex, mode)
    local dialog = self.pickerDialog
    if not dialog or not dialog.groupSelection then return end
    
    local activeDB = self:GetActiveHubDB()
    local targetSlots = self:GetSlotsForSide(activeDB, targetSide)
    local targetSlot = targetSlots and targetSlots[targetIndex]
    if not targetSlot then return end
    
    local targetBtn = nil
    if ActionHub.tab and ActionHub.tab.ringButtons then
        for _, b in ipairs(ActionHub.tab.ringButtons) do
            if b.slotSide == targetSide and b.slotIndex == targetIndex then
                targetBtn = b
                break
            end
        end
    end
    
    if not targetBtn then return end
    
    local targetAbsX = targetBtn.basePreviewX + (targetSlot.nodePositionX or 0)
    local targetAbsY = targetBtn.basePreviewY + (targetSlot.nodePositionY or 0)
    
    local nodes = {}
    for k, v in pairs(dialog.groupSelection) do
        local sideSlots = self:GetSlotsForSide(activeDB, v.side)
        local s = sideSlots and sideSlots[v.index]
        if s then
            local btn = nil
            if ActionHub.tab and ActionHub.tab.ringButtons then
                for _, b in ipairs(ActionHub.tab.ringButtons) do
                    if b.slotSide == v.side and b.slotIndex == v.index then
                        btn = b
                        break
                    end
                end
            end
            
            if btn then
                table.insert(nodes, {
                    slot = s,
                    btn = btn,
                    order = v.order or 1,
                    absX = btn.basePreviewX + (s.nodePositionX or 0),
                    absY = btn.basePreviewY + (s.nodePositionY or 0)
                })
            end
        end
    end
    
    if #nodes <= 1 then return end

    -- Sort strictly by the user's chosen selection order
    table.sort(nodes, function(a, b) return (a.order or 0) < (b.order or 0) end)
    
    local nodeWidth = (targetBtn and targetBtn:GetWidth() > 0 and targetBtn:GetWidth()) or ((activeDB and activeDB.globalNodeSize) or 40)
    local nodeHeight = (targetBtn and targetBtn:GetHeight() > 0 and targetBtn:GetHeight()) or ((activeDB and activeDB.globalNodeSize) or 40)
    local gap = 4
    local sx = nodeWidth + gap
    local sy = nodeHeight + gap
    
    local startAbsX = targetAbsX
    local startAbsY = targetAbsY
    
    if mode == "vertical" then
        for i, n in ipairs(nodes) do
            n.slot.nodePositionX = startAbsX - n.btn.basePreviewX
            local newAbsY = startAbsY - ((i - 1) * sy)
            n.slot.nodePositionY = newAbsY - n.btn.basePreviewY
        end
    elseif mode == "horizontal" then
        for i, n in ipairs(nodes) do
            n.slot.nodePositionY = startAbsY - n.btn.basePreviewY
            local newAbsX = startAbsX + ((i - 1) * sx)
            n.slot.nodePositionX = newAbsX - n.btn.basePreviewX
        end
    end
    
    self:RefreshWidget()
    self:RefreshTab()
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Minimized Move Mode: hide the main window and drag the real widget's nodes
-- directly on screen, inside a blue "move zone" overlay.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

-- Move mode used to unlock exactly one hub -- the active one.  Every other hub
-- on screen stayed frozen, so a second bar could only be shoved around whole
-- via shift-drag, never rearranged node by node.  It is now a set: any number
-- of hubs can be unlocked together and each of their nodes dragged separately.
--
-- minimizedMoveModeHub survives as the FOCUS: the grid, the spacing sliders and
-- Reset are stored per hub, so those still need one hub to act on.
function ActionHub:GetMoveModeHubs()
    self.minimizedMoveModeHubs = self.minimizedMoveModeHubs or {}
    return self.minimizedMoveModeHubs
end

function ActionHub:IsMinimizedMoveMode(hubIndex)
    if hubIndex == nil then return false end
    return self.minimizedMoveModeHubs ~= nil and self.minimizedMoveModeHubs[hubIndex] == true
end

function ActionHub:IsMoveModeActive()
    return self.minimizedMoveModeHub ~= nil
end

-- Unlock or freeze one hub without leaving move mode.
function ActionHub:SetMoveModeHubEnabled(hubIndex, enabled)
    if not hubIndex or not self:IsMoveModeActive() then return end
    if InCombatLockdown() then return end

    local set = self:GetMoveModeHubs()
    set[hubIndex] = enabled and true or nil

    -- Never leave the whole screen frozen: turning off the last hub would
    -- strand the dialog with nothing left to drag.
    local remaining
    for index in pairs(set) do remaining = remaining or index end
    if not remaining then
        set[hubIndex] = true
        remaining = hubIndex
    end

    -- The focused hub has to stay one that is actually unlocked, or the
    -- sliders and Reset would quietly act on a frozen bar.
    if not set[self.minimizedMoveModeHub] then
        self.minimizedMoveModeHub = remaining
    end

    if enabled then
        local w = self:CreateWidget(hubIndex)
        if w then w:SetMovable(true) end
    end

    local doneFrame = self.moveModeDoneFrame
    if doneFrame then
        if doneFrame.updateHubToggles then doneFrame.updateHubToggles() end
        if doneFrame.updateGridButtons then doneFrame.updateGridButtons() end
        if doneFrame.SyncSpacingSliders then doneFrame.SyncSpacingSliders() end
    end
    self:RefreshWidget()
end

-- Which hub the per-hub controls act on.  Focusing one also unlocks it.
function ActionHub:SetMoveModeFocus(hubIndex)
    if not hubIndex or not self:IsMoveModeActive() then return end
    self.minimizedMoveModeHub = hubIndex
    self:SetMoveModeHubEnabled(hubIndex, true)
end

-- Drag a real widget node on screen, updating its slot offset live.
-- Drag an ENTIRE hub by shift-dragging any of its nodes.
--
-- The blue zone used to be the only way to move a whole set, but it is hidden
-- while the screen grid is up (it is the wrong reference then), which left no
-- way to move the set at all.  Shift on a node works for every hub on screen,
-- so several hubs can be lined up against the same grid.
-- Light up the grid lines a drag is sitting on.  Takes an offset from screen
-- centre, which is the same reference the grid is drawn from.
function ActionHub:MarkGridPosition(offsetX, offsetY)
    if not self.screenGridOn then return end
    local g = self.screenGrid
    if g and g.MarkPosition then g:MarkPosition(offsetX, offsetY) end
end


-- Where a frame sits, measured from screen centre in UIParent units.
--
-- This is the ONE place screen position is worked out.  Both the snapping and
-- the readout call it, so a given spot on screen always produces the same
-- number no matter which hub or which icon is involved -- the whole reason the
-- two bars disagreed before.
function ActionHub:GetFrameGridOffset(frame)
    if not frame then return nil end

    local cx, cy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return nil end

    local fScale = frame:GetEffectiveScale() or 1
    local uScale = UIParent:GetEffectiveScale() or 1
    if fScale <= 0 or uScale <= 0 then return nil end

    return (cx * fScale) / uScale - ux, (cy * fScale) / uScale - uy
end

function ActionHub:MarkGridForFrame(frame)
    if not self.screenGridOn or not frame then return end
    local ox, oy = self:GetFrameGridOffset(frame)
    if ox then self:MarkGridPosition(ox, oy) end
end

function ActionHub:ClearGridMark()
    local g = self.screenGrid
    if g and g.ClearMark then g:ClearMark() end
end

function ActionHub:BeginWidgetSetDrag(btn, hubIndex)
    if InCombatLockdown() then return end
    local w = self.widgets and self.widgets[hubIndex]
    if not w then return end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    local startCursorX, startCursorY = cursorX / scale, cursorY / scale

    local db = self:GetHubDB(hubIndex)
    local pos = (db and db.widgetPosition) or { x = 0, y = 0 }
    local startX, startY = pos.x or 0, pos.y or 0

    btn.isDraggingSet = true
    btn:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then
            ActionHub:EndWidgetSetDrag(self, hubIndex)
            return
        end

        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale

        local newX = startX + (cx - startCursorX)
        local newY = startY + (cy - startCursorY)

        -- Place first, unsnapped.
        w:ClearAllPoints()
        w:SetPoint("CENTER", UIParent, "CENTER", newX, newY)

        -- Then snap the ICON, not the container.
        --
        -- widgetPosition is the offset of the widget FRAME from screen centre,
        -- and every hub has a different gap between that frame's centre and its
        -- icons.  Rounding widgetPosition therefore parks two hubs' icons on
        -- different sub-grid positions: the same spot on screen reads as two
        -- different numbers, and they can never be lined up.  Snapping what is
        -- actually visible, then shifting the frame by that correction, keeps
        -- every hub in one shared coordinate space.
        if ActionHub.screenGridOn and ActionHub.screenSnapOn then
            local step = ActionHub.screenGridStep or 64
            local iconX, iconY = ActionHub:GetFrameGridOffset(self)
            if step >= 4 and iconX then
                local targetX = math.floor((iconX / step) + 0.5) * step
                local targetY = math.floor((iconY / step) + 0.5) * step
                newX = newX + (targetX - iconX)
                newY = newY + (targetY - iconY)

                w:ClearAllPoints()
                w:SetPoint("CENTER", UIParent, "CENTER", newX, newY)
            end
        end

        -- Report the icon under the cursor, in the grid's own terms, so the
        -- reading does not depend on which hub or which icon was grabbed.
        ActionHub:MarkGridForFrame(self)

        local hubDB = ActionHub:GetHubDB(hubIndex)
        if hubDB then hubDB.widgetPosition = { x = newX, y = newY } end
    end)
end

function ActionHub:EndWidgetSetDrag(btn)
    if not btn or not btn.isDraggingSet then return end
    btn.isDraggingSet = false
    btn:SetScript("OnUpdate", nil)
    self:ClearGridMark()
end

function ActionHub:BeginWidgetNodeDrag(btn)
    if not btn or not btn.slotIndex or not btn.slotSide then return end
    if InCombatLockdown() then return end

    -- Shift moves the whole hub instead of the single node.  Prefer the hub
    -- the node actually belongs to, so this works for every hub on screen,
    -- not just the one that opened move mode.
    if IsShiftKeyDown() then
        -- slotHubIndex is not set on these buttons; the owning widget carries
        -- hubIndex, which is what the styling code reads too.
        local parentWidget = btn:GetParent()
        local owner = (parentWidget and parentWidget.hubIndex)
            or btn.slotHubIndex or self.minimizedMoveModeHub
        if owner then
            self:BeginWidgetSetDrag(btn, owner)
            return
        end
    end

    -- Read the hub off the node's own widget, not off the focused one.  With
    -- several hubs unlocked at once, the focus says which one the sliders act
    -- on -- it says nothing about which bar this particular node belongs to,
    -- and using it would write the drag into a different hub's slots.
    local parentWidget = btn:GetParent()
    local hub = (parentWidget and parentWidget.hubIndex)
        or btn.slotHubIndex or self.minimizedMoveModeHub
    if not self:IsMinimizedMoveMode(hub) then return end
    local w = self.widgets and self.widgets[hub]
    if not w then return end
    local slots = self:GetSlotsForSide(self:GetHubDB(hub), btn.slotSide)
    local slot = slots and slots[btn.slotIndex]
    if not slot then return end

    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    btn.dragStartCursorX = cursorX / scale
    btn.dragStartCursorY = cursorY / scale
    btn.dragStartOffsetX = slot.nodePositionX or 0
    btn.dragStartOffsetY = slot.nodePositionY or 0
    btn.isDraggingNode = true

    btn:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then
            ActionHub:EndWidgetNodeDrag(self)
            return
        end
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        local newOffsetX = math.floor((self.dragStartOffsetX + (cx - self.dragStartCursorX)) + 0.5)
        local newOffsetY = math.floor((self.dragStartOffsetY + (cy - self.dragStartCursorY)) + 0.5)

        -- Snap to grid (if enabled), then clamp inside the blue zone
        local rawX = (self.baseArcX or 0) + newOffsetX
        local rawY = (self.baseArcY or 0) + newOffsetY
        rawX, rawY = ActionHub:SnapMovePosition(w, rawX, rawY, self)
        rawX, rawY = ActionHub:SnapToScreenGrid(w, rawX, rawY)
        local half = (self:GetWidth() or 44) / 2
        -- The blue zone is a 235px box around the widget.  With a screen grid
        -- up, that box is the wrong reference: it stops a node long before it
        -- reaches most grid lines, and makes aligning two hubs impossible.
        -- Free the clamp to the screen while the grid is driving placement.
        local zoneHalf = w.moveZoneHalf or 235
        if ActionHub.screenGridOn then
            zoneHalf = math.max(UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080)
        end
        local centerX = w:GetWidth() / 2
        local centerY = -(w:GetHeight() / 2)
        local posX = math.max(centerX - zoneHalf + half, math.min(centerX + zoneHalf - half, rawX))
        local posY = math.max(centerY - zoneHalf + half, math.min(centerY + zoneHalf - half, rawY))
        newOffsetX = posX - (self.baseArcX or 0)
        newOffsetY = posY - (self.baseArcY or 0)

        slot.nodePositionX = newOffsetX
        slot.nodePositionY = newOffsetY

        -- Keep any open editor sliders in sync (harmless while hidden)
        local dialog = ActionHub.pickerDialog
        if dialog then
            if dialog.posXVal then dialog.posXVal:SetText(tostring(newOffsetX)) end
            if dialog.posXInput then dialog.posXInput:SetText(tostring(newOffsetX)) end
            if dialog.posYVal then dialog.posYVal:SetText(tostring(newOffsetY)) end
            if dialog.posYInput then dialog.posYInput:SetText(tostring(newOffsetY)) end
        end

        self:ClearAllPoints()
        self:SetPoint("CENTER", w, "TOPLEFT",
            (self.baseArcX or 0) + newOffsetX, (self.baseArcY or 0) + newOffsetY)

        ActionHub:MarkGridForFrame(self)
    end)
end

function ActionHub:EndWidgetNodeDrag(btn)
    -- A shift-drag runs on the same button, so release has to clear either.
    if btn and btn.isDraggingSet then
        self:EndWidgetSetDrag(btn)
        return
    end
    if not btn or not btn.isDraggingNode then return end
    btn.isDraggingNode = false
    btn:SetScript("OnUpdate", nil)
    self:ClearGridMark()
end

-- Full-screen alignment grid, shown only while positioning nodes.
--
-- Lines are laid out from the CENTRE outwards rather than from a corner, so
-- the spacing left of centre always mirrors the spacing right of it.  That is
-- the whole point: it lets a hub be placed symmetrically by eye.
function ActionHub:GetOrCreateScreenGrid()
    if self.screenGrid then return self.screenGrid end

    local g = CreateFrame("Frame", "OxedHubActionHubScreenGrid", UIParent)
    g:SetAllPoints(UIParent)
    g:SetFrameStrata("BACKGROUND")
    g:EnableMouse(false)
    g.lines = {}
    g:Hide()

    -- One screen pixel expressed in UIParent units.  Everything below is
    -- rounded to whole screen pixels: at a non-integer UI scale a 1-unit line
    -- straddles two pixels, and neighbouring lines round different ways, which
    -- is what made the spacing look arbitrary near the centre.
    local function PixelSize()
        local scale = UIParent:GetEffectiveScale() or 1
        if scale <= 0 then return 1, 1 end
        return 1 / scale, scale
    end

    function g:Rebuild(step)
        step = step or 64
        for _, tex in ipairs(self.lines) do tex:Hide() end

        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end

        local px, scale = PixelSize()

        -- Round an offset so the line lands exactly on a screen pixel.
        local function Align(v)
            return math.floor(v * scale + 0.5) / scale
        end

        local used = 0
        local function Line(isVertical, offset, isAxis)
            used = used + 1
            local tex = self.lines[used]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND")
                self.lines[used] = tex
            end

            local thickness = isAxis and (px * 2) or px
            offset = Align(offset)

            tex:ClearAllPoints()
            if isVertical then
                tex:SetWidth(thickness)
                tex:SetPoint("TOP", self, "TOP", offset, 0)
                tex:SetPoint("BOTTOM", self, "BOTTOM", offset, 0)
            else
                tex:SetHeight(thickness)
                tex:SetPoint("LEFT", self, "LEFT", 0, offset)
                tex:SetPoint("RIGHT", self, "RIGHT", 0, offset)
            end

            -- Centre axes stand out; the rest stay faint so icons read clearly.
            if isAxis then
                tex:SetColorTexture(1, 0.82, 0, 0.65)
            else
                tex:SetColorTexture(1, 1, 1, 0.14)
            end
            tex:Show()
        end

        Line(true, 0, true)
        Line(false, 0, true)

        -- Integer multiples of the step, so the n-th line left of centre is
        -- always the exact mirror of the n-th line right of it.
        local nx = math.floor((w / 2) / step)
        for i = 1, nx do
            Line(true, i * step, false)
            Line(true, -i * step, false)
        end

        local ny = math.floor((h / 2) / step)
        for i = 1, ny do
            Line(false, i * step, false)
            Line(false, -i * step, false)
        end

        for i = used + 1, #self.lines do self.lines[i]:Hide() end
    end

    -- Crosshair marking the lines a dragged node is currently snapped to,
    -- plus its distance from centre.  Without this there is no way to tell
    -- which line something landed on, and no way to mirror it on the far side.
    g.markX = g:CreateTexture(nil, "ARTWORK")
    g.markY = g:CreateTexture(nil, "ARTWORK")
    g.markX:Hide()
    g.markY:Hide()

    g.readout = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.readout:SetTextColor(1, 0.82, 0, 1)
    g.readout:Hide()

    -- offsetX/offsetY are measured from screen centre, same as the grid.
    function g:MarkPosition(offsetX, offsetY)
        if not self:IsShown() then return end
        local px = PixelSize()

        self.markX:ClearAllPoints()
        self.markX:SetWidth(px * 3)
        self.markX:SetPoint("TOP", self, "TOP", offsetX, 0)
        self.markX:SetPoint("BOTTOM", self, "BOTTOM", offsetX, 0)
        self.markX:SetColorTexture(0.3, 1, 0.4, 0.85)
        self.markX:Show()

        self.markY:ClearAllPoints()
        self.markY:SetHeight(px * 3)
        self.markY:SetPoint("LEFT", self, "LEFT", 0, offsetY)
        self.markY:SetPoint("RIGHT", self, "RIGHT", 0, offsetY)
        self.markY:SetColorTexture(0.3, 1, 0.4, 0.85)
        self.markY:Show()

        self.readout:ClearAllPoints()
        self.readout:SetPoint("CENTER", self, "CENTER", offsetX, offsetY + 26)
        self.readout:SetText(string.format("%d , %d",
            math.floor(offsetX + 0.5), math.floor(offsetY + 0.5)))
        self.readout:Show()
    end

    function g:ClearMark()
        self.markX:Hide()
        self.markY:Hide()
        self.readout:Hide()
    end
    self.screenGrid = g
    return g
end

-- Snap a node to the nearest screen-grid intersection.
--
-- Node offsets are stored relative to their own widget, but the grid belongs
-- to the screen.  Converting through screen space is what lets nodes from
-- DIFFERENT hubs land on the same lines -- which is the only practical way to
-- line several hubs up with each other.
--
-- rawX/rawY are offsets from the widget TOPLEFT; the return values are too.
function ActionHub:SnapToScreenGrid(w, rawX, rawY)
    if not self.screenGridOn or not self.screenSnapOn then return rawX, rawY end

    local step = self.screenGridStep or 64
    if step < 4 then return rawX, rawY end

    local wLeft, wTop = w:GetLeft(), w:GetTop()
    local ux, uy = UIParent:GetCenter()
    if not (wLeft and wTop and ux and uy) then return rawX, rawY end

    -- GetLeft/GetCenter report in each frame's OWN scaled units.  The widget
    -- and UIParent can sit at different scales, so comparing those numbers
    -- directly lands the node elsewhere -- which is why this looked like it
    -- was not snapping at all.  Convert both sides to absolute pixels first.
    local wScale = w:GetEffectiveScale() or 1
    local uScale = UIParent:GetEffectiveScale() or 1
    if wScale <= 0 or uScale <= 0 then return rawX, rawY end

    local nodeAbsX = (wLeft + rawX) * wScale
    local nodeAbsY = (wTop + rawY) * wScale
    local centreAbsX, centreAbsY = ux * uScale, uy * uScale
    local stepAbs = step * uScale

    -- Snap measured FROM THE CENTRE, matching how the grid is drawn.
    local snapAbsX = centreAbsX + math.floor(((nodeAbsX - centreAbsX) / stepAbs) + 0.5) * stepAbs
    local snapAbsY = centreAbsY + math.floor(((nodeAbsY - centreAbsY) / stepAbs) + 0.5) * stepAbs

    return (snapAbsX / wScale) - wLeft, (snapAbsY / wScale) - wTop
end

function ActionHub:SetScreenGridShown(shown, step)
    local g = self:GetOrCreateScreenGrid()
    if shown then
        g:Rebuild(step or self.screenGridStep or 64)
        g:Show()
    else
        g:Hide()
    end
    self.screenGridOn = shown and true or false
end

-- Small floating "Done Positioning" control shown while in minimized move mode.
function ActionHub:GetOrCreateMoveModeDoneFrame()
    if self.moveModeDoneFrame then return self.moveModeDoneFrame end

    -- Clean themed dialog (same style as the Pick Sound picker).
    local f = CreateFrame("Frame", "OxedHubActionHubMoveDone", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 384)
    f:SetPoint("TOP", UIParent, "TOP", 0, -130)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(300)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if f.TitleText then f.TitleText:SetText(L["AH_MOVE_MODE_DRAG_SCREEN"] or "Move Mode — drag nodes on screen") end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() ActionHub:ExitMinimizedMoveMode() end) end

    local function updateGridButtons()
        local t = ActionHub.moveGridType or "off"
        local gridText = t == "square" and (L["GRID_SQUARE"] or "Square") or 
                         t == "radial" and (L["GRID_RADIAL"] or "Radial") or 
                         t == "magnetic" and (L["GRID_MAGNETIC"] or "Magnetic") or 
                         (L["GRID_OFF"] or "Off")
        f.gridBtn:SetText(string.format(L["AH_GRID_LABEL"] or "Grid: %s", gridText))

        local gridActive = (t == "square" or t == "radial")
        for _, s in ipairs({ f.hSpacingSlider, f.vSpacingSlider }) do
            if s then
                if gridActive then
                    s:Show()
                    if s.lbl then s.lbl:Show() end
                    if s.valTxt then s.valTxt:Show() end
                else
                    s:Hide()
                    if s.lbl then s.lbl:Hide() end
                    if s.valTxt then s.valTxt:Hide() end
                end
            end
        end
        if f.magneticGapSlider then
            if t == "magnetic" then
                f.magneticGapSlider:Show()
                if f.magneticGapSlider.lbl then f.magneticGapSlider.lbl:Show() end
                if f.magneticGapSlider.valTxt then f.magneticGapSlider.valTxt:Show() end
            else
                f.magneticGapSlider:Hide()
                if f.magneticGapSlider.lbl then f.magneticGapSlider.lbl:Hide() end
                if f.magneticGapSlider.valTxt then f.magneticGapSlider.valTxt:Hide() end
            end
        end
    end
    f.updateGridButtons = updateGridButtons

    -- Row 0: which hubs are unlocked.
    --
    -- One button per hub, cycling locked -> unlocked -> focused -> locked.  Several hubs can
    -- be unlocked at once so their nodes get rearranged side by side; the
    -- focused one is what the grid and spacing sliders below act on, since
    -- those settings are stored per hub.
    local hubLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hubLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
    hubLabel:SetText("Unlocked hubs")
    hubLabel:SetTextColor(0.9, 0.9, 0.9)

    f.hubToggles = {}

    local allBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    allBtn:SetSize(52, 20)
    allBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -30)
    allBtn:SetText("All")
    allBtn:SetScript("OnClick", function()
        local hubs = ActionHub:GetHubs() or {}
        local set = ActionHub:GetMoveModeHubs()
        -- Anything still locked means "unlock everything"; otherwise collapse
        -- back to the focused hub alone.
        local anyLocked = false
        for i = 1, #hubs do
            if not set[i] then anyLocked = true end
        end
        if anyLocked then
            for i = 1, #hubs do ActionHub:SetMoveModeHubEnabled(i, true) end
        else
            local keep = ActionHub.minimizedMoveModeHub or 1
            for i = 1, #hubs do
                if i ~= keep then ActionHub:SetMoveModeHubEnabled(i, false) end
            end
        end
    end)
    allBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Unlock every hub at once.", 1, 1, 1)
        GameTooltip:AddLine("Click again to leave only the focused one unlocked.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    allBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function updateHubToggles()
        local hubs = ActionHub:GetHubs() or {}
        local rowWidth, x, y = 332, 0, 0

        for i = 1, #hubs do
            local btn = f.hubToggles[i]
            if not btn then
                btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                btn:SetHeight(20)
                btn.hubIndex = i
                btn:SetScript("OnClick", function(self)
                    local index = self.hubIndex
                    if not ActionHub:IsMinimizedMoveMode(index) then
                        ActionHub:SetMoveModeFocus(index)
                    elseif ActionHub.minimizedMoveModeHub ~= index then
                        ActionHub:SetMoveModeFocus(index)
                    else
                        ActionHub:SetMoveModeHubEnabled(index, false)
                    end
                end)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self:GetText() or "", 1, 0.85, 0.2)
                    if not ActionHub:IsMinimizedMoveMode(self.hubIndex) then
                        GameTooltip:AddLine("Locked. Click to unlock and drag its nodes.", 0.8, 0.8, 0.8, true)
                    elseif ActionHub.minimizedMoveModeHub == self.hubIndex then
                        GameTooltip:AddLine("Focused: the grid and spacing sliders act on this hub.", 0.8, 0.8, 0.8, true)
                        GameTooltip:AddLine("Click to lock it again.", 0.8, 0.8, 0.8, true)
                    else
                        GameTooltip:AddLine("Unlocked. Click to focus the grid controls on it.", 0.8, 0.8, 0.8, true)
                    end
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                f.hubToggles[i] = btn
            end

            local db = ActionHub:GetHubDB(i)
            btn:SetText((db and db.name) or ("Hub " .. i))
            btn:SetWidth(math.max(58, (btn:GetTextWidth() or 40) + 20))
            btn.hubIndex = i

            -- Wrap once the row runs out of dialog width.
            if x > 0 and (x + btn:GetWidth()) > rowWidth then
                x, y = 0, y - 24
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", 14 + x, -52 + y)
            x = x + btn:GetWidth() + 4

            local unlocked = ActionHub:IsMinimizedMoveMode(i)
            local focused = ActionHub.minimizedMoveModeHub == i
            btn:SetAlpha(unlocked and 1 or 0.5)
            local text = btn:GetFontString()
            if text then
                if focused then
                    text:SetTextColor(1, 0.82, 0)
                elseif unlocked then
                    text:SetTextColor(0.5, 1, 0.5)
                else
                    text:SetTextColor(0.6, 0.6, 0.6)
                end
            end
            btn:Show()
        end

        for i = #hubs + 1, #f.hubToggles do
            f.hubToggles[i]:Hide()
        end
    end
    f.updateHubToggles = updateHubToggles

    -- Row 1: Grid Dropdown
    local gridBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gridBtn:SetSize(160, 24)
    gridBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -88)
    gridBtn:SetText(string.format(L["AH_GRID_LABEL"] or "Grid: %s", L["GRID_OFF"] or "Off"))
    
    local tex = gridBtn:CreateTexture(nil, "ARTWORK")
    tex:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    tex:SetSize(16, 16)
    tex:SetPoint("RIGHT", gridBtn, "RIGHT", -4, 0)

    gridBtn:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(owner, root)
            local titleText = L["AH_GRID_LABEL"] and string.gsub(L["AH_GRID_LABEL"], ":? ?%%s", "") or "Grid"
            root:CreateTitle(titleText)
            
            local function IsSelected(gridType) return (ActionHub.moveGridType or "off") == gridType end
            local function SetGrid(gridType) 
                ActionHub.moveGridType = gridType
                if gridType ~= "off" then
                    ActionHub.moveSnap = true
                end
                ActionHub:UpdateMoveGrid()
                updateGridButtons()
            end
            
            root:CreateRadio(L["GRID_OFF"] or "Off", IsSelected, SetGrid, "off")
            root:CreateRadio(L["GRID_SQUARE"] or "Square", IsSelected, SetGrid, "square")
            root:CreateRadio(L["GRID_RADIAL"] or "Radial", IsSelected, SetGrid, "radial")
            root:CreateRadio(L["GRID_MAGNETIC"] or "Magnetic", IsSelected, SetGrid, "magnetic")
            
            root:CreateDivider()
            
            local snapTitle = L["AH_SNAP_LABEL"] and string.gsub(L["AH_SNAP_LABEL"], ":? ?%%s", "") or "Snap"
            root:CreateCheckbox(snapTitle,
                function() return ActionHub.moveSnap end,
                function()
                    ActionHub.moveSnap = not ActionHub.moveSnap
                    updateGridButtons()
                end)
        end)
    end)
    f.gridBtn = gridBtn

    -- Snap-spacing sliders (Square grid): horizontal + vertical gap between snaps.
    local function MakeSpacingSlider(labelText, axisKey, minVal, maxVal, anchorTo, yOff)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOff)
        lbl:SetText(labelText)
        lbl:SetTextColor(0.8, 0.9, 1)

        local valTxt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        valTxt:SetPoint("LEFT", lbl, "RIGHT", 6, 0)

        local slider = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 4, -12)
        slider:SetWidth(300)
        slider:SetMinMaxValues(minVal or 24, maxVal or 120)
        slider:SetValueStep(2)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:SetText("") end
        if slider.High then slider.High:SetText("") end
        if slider.Text then slider.Text:SetText("") end
        slider.axisKey = axisKey
        slider.lbl = lbl
        slider.valTxt = valTxt
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            self.valTxt:SetText(value)
            if self.isSyncing then return end
            local hub = ActionHub.minimizedMoveModeHub or ActionHub:GetActiveHubIndex()
            local db = hub and ActionHub:GetHubDB(hub)
            if db then db[axisKey] = value end
            ActionHub:UpdateMoveGrid()
        end)
        return slider
    end

    f.hSpacingSlider = MakeSpacingSlider("Horizontal snap spacing", "snapStepX", 24, 120, gridBtn, -22)
    f.vSpacingSlider = MakeSpacingSlider("Vertical snap spacing", "snapStepY", 24, 120, f.hSpacingSlider, -30)
    f.magneticGapSlider = MakeSpacingSlider("Magnetic Gap", "magneticGap", -10, 10, gridBtn, -22)

    -- Screen grid: a separate aid from the snap grid above.  It changes
    -- nothing about placement, it just draws guides to line things up by eye.
    local screenGridCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    screenGridCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -204)
    screenGridCheck:SetSize(24, 24)
    screenGridCheck:SetChecked(ActionHub.screenGridOn == true)

    local moveHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    moveHint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -182)
    moveHint:SetWidth(320)
    moveHint:SetJustifyH("LEFT")
    moveHint:SetText("|cff88AAFFShift + drag a node|r moves that whole hub.")

    local screenGridLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    screenGridLabel:SetPoint("LEFT", screenGridCheck, "RIGHT", 4, 0)
    screenGridLabel:SetText("Screen Grid")
    screenGridLabel:SetTextColor(0.9, 0.9, 0.9)

    local gridStepSlider = CreateFrame("Slider", "OxedHubAHScreenGridStep", f, "OptionsSliderTemplate")
    gridStepSlider:SetPoint("TOPLEFT", screenGridCheck, "BOTTOMLEFT", 6, -20)
    gridStepSlider:SetWidth(300)
    gridStepSlider:SetMinMaxValues(24, 160)
    gridStepSlider:SetValueStep(8)
    gridStepSlider:SetObeyStepOnDrag(true)

    local stepLow  = gridStepSlider.Low  or _G[gridStepSlider:GetName() .. "Low"]
    local stepHigh = gridStepSlider.High or _G[gridStepSlider:GetName() .. "High"]
    local stepText = gridStepSlider.Text or _G[gridStepSlider:GetName() .. "Text"]
    if stepLow  then stepLow:SetText("24") end
    if stepHigh then stepHigh:SetText("160") end
    if stepText then stepText:SetText("Grid Spacing") end

    gridStepSlider:SetValue(ActionHub.screenGridStep or 64)
    gridStepSlider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        ActionHub.screenGridStep = value
        if stepText then stepText:SetText("Grid Spacing  " .. value) end
        if ActionHub.screenGridOn then ActionHub:SetScreenGridShown(true, value) end
    end)

    screenGridCheck:SetScript("OnClick", function(self)
        ActionHub:SetScreenGridShown(self:GetChecked(), ActionHub.screenGridStep)
        -- Refresh the per-widget dot grids so they hide/return in step.
        if ActionHub.UpdateMoveGrid then ActionHub:UpdateMoveGrid() end
        -- Redraw so the logo and empty nodes appear/disappear immediately.
        if ActionHub.RefreshAllWidgets then ActionHub:RefreshAllWidgets() end
        -- Show/hide the blue zone to match, without waiting for a redraw.
        for _, w in ipairs(ActionHub.widgets or {}) do
            if w and w.moveOverlay then
                w.moveOverlay:SetShown(
                    ActionHub.minimizedMoveModeHub ~= nil and not ActionHub.screenGridOn)
            end
        end
    end)
    screenGridCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Screen Grid", 1, 0.82, 0)
        GameTooltip:AddLine("Draws guides over the whole screen while positioning.", 1, 1, 1, true)
        GameTooltip:AddLine("Lines run out from the centre, so left and right match.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    screenGridCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.screenGridCheck = screenGridCheck

    -- Snapping is a separate opt-in: some people want the guides only.
    local snapCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    snapCheck:SetPoint("LEFT", screenGridLabel, "RIGHT", 20, 0)
    snapCheck:SetSize(24, 24)
    snapCheck:SetChecked(ActionHub.screenSnapOn == true)

    local snapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapLabel:SetPoint("LEFT", snapCheck, "RIGHT", 4, 0)
    snapLabel:SetText("Snap to Grid")
    snapLabel:SetTextColor(0.9, 0.9, 0.9)

    snapCheck:SetScript("OnClick", function(self)
        ActionHub.screenSnapOn = self:GetChecked() and true or false
    end)
    snapCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Snap to Grid", 1, 0.82, 0)
        GameTooltip:AddLine("Nodes jump to the nearest grid intersection.", 1, 1, 1, true)
        GameTooltip:AddLine("Works across hubs: they all snap to the same lines.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    snapCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.snapCheck = snapCheck

    -- Sync the sliders to the current hub's stored (or default) spacing.
    f.SyncSpacingSliders = function()
        local hub = ActionHub.minimizedMoveModeHub or ActionHub:GetActiveHubIndex()
        local db = hub and ActionHub:GetHubDB(hub)
        local base = ActionHub:GetDefaultSnapStep()
        local sx = (db and db.snapStepX) or base
        local sy = (db and db.snapStepY) or base
        local gap = (db and db.magneticGap) or 8
        for slider, v in pairs({ [f.hSpacingSlider] = sx, [f.vSpacingSlider] = sy }) do
            slider.isSyncing = true
            slider:SetValue(math.min(120, math.max(24, v)))
            slider.isSyncing = false
            slider.valTxt:SetText(math.floor(v + 0.5))
        end
        if f.magneticGapSlider then
            f.magneticGapSlider.isSyncing = true
            f.magneticGapSlider:SetValue(math.min(10, math.max(-10, gap)))
            f.magneticGapSlider.isSyncing = false
            f.magneticGapSlider.valTxt:SetText(math.floor(gap + 0.5))
        end
    end

    -- Row 2: Reset + Done
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 24)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    resetBtn:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
    resetBtn:SetScript("OnClick", function() ActionHub:ResetMoveModePositions() end)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(160, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
    doneBtn:SetText(L["AH_DONE_POSITIONING"] or "Done Positioning")
    doneBtn:SetScript("OnClick", function() ActionHub:ExitMinimizedMoveMode() end)

    updateHubToggles()
    updateGridButtons()

    f:Hide()
    self.moveModeDoneFrame = f
    return f
end

-- Reset every node's custom offset for the hub being positioned, returning
-- all nodes to their default ring layout.
function ActionHub:ResetMoveModePositions()
    local hub = self.minimizedMoveModeHub
    if not hub then return end
    if InCombatLockdown() then
        print("|cffff5555OxedHub:|r " .. (L["ERR_CANNOT_RESET_COMBAT"] or "Can't reset during combat."))
        return
    end
    local db = self:GetHubDB(hub)
    for _, sideKey in ipairs({ "primary", "secondary" }) do
        local slots = self:GetSlotsForSide(db, sideKey)
        for _, slot in ipairs(slots or {}) do
            slot.nodePositionX = nil
            slot.nodePositionY = nil
        end
    end
    self:RefreshWidget()
end

-- Grid settings (shared by snapping + the visual dots)
local MOVE_GRID_SQUARE_STEP = 40
local MOVE_GRID_RADIAL_RSTEP = 40
local MOVE_GRID_RADIAL_ASTEP = math.rad(30)  -- 12 spokes
local MOVE_GRID_SQUARE_GAP = 8  -- extra px between snapped square nodes

-- Square grid step per axis. Defaults to node size (+ gap) so squares never
-- overlap, but the user can override the horizontal/vertical spacing via the two
-- move-mode sliders (stored per hub in snapStepX / snapStepY).
-- Default snap step: centered in the 24–120 slider range (so the handle starts in
-- the middle) while never smaller than a node (+ gap) so squares can't overlap.
local SNAP_STEP_DEFAULT = 72
function ActionHub:GetDefaultSnapStep()
    local hub = self.minimizedMoveModeHub or self:GetActiveHubIndex()
    local db = hub and self:GetHubDB(hub)
    local nodeSize = (db and db.globalNodeSize) or 44
    return nodeSize + MOVE_GRID_SQUARE_GAP
end
function ActionHub:GetSquareGridStepXY()
    local hub = self.minimizedMoveModeHub or self:GetActiveHubIndex()
    local db = hub and self:GetHubDB(hub)
    local base = self:GetDefaultSnapStep()
    local sx = (db and db.snapStepX) or base
    local sy = (db and db.snapStepY) or base
    return sx, sy
end
-- Radial grid steps driven by the same two sliders: V (snapStepY) = ring spacing,
-- H (snapStepX) = angular spacing (larger = fewer spokes).
function ActionHub:GetRadialSteps()
    local hub = self.minimizedMoveModeHub or self:GetActiveHubIndex()
    local db = hub and self:GetHubDB(hub)
    local base = self:GetDefaultSnapStep()
    local rstep = (db and db.snapStepY) or base
    local aDeg = ((db and db.snapStepX) or base) / 4  -- ~18° at the default
    aDeg = math.max(6, math.min(90, aDeg))            -- clamp spoke density
    return rstep, math.rad(aDeg)
end

-- Back-compat single-value accessor (uses the horizontal step).
function ActionHub:GetSquareGridStep()
    local sx = self:GetSquareGridStepXY()
    return sx
end

-- Snap a node position (w TOPLEFT coords) to the active grid, if snap is on.
function ActionHub:SnapMovePosition(w, posX, posY, draggingBtn)
    local gridType = self.moveGridType or "off"
    if gridType == "off" or not self.moveSnap then
        return posX, posY
    end
    local centerX = w:GetWidth() / 2
    local centerY = -(w:GetHeight() / 2)
    local relX = posX - centerX
    local relY = posY - centerY
    
    if gridType == "magnetic" then
        local hub = self.minimizedMoveModeHub or self:GetActiveHubIndex()
        local db = self:GetHubDB(hub)
        local gap = db and db.magneticGap
        if gap == nil then gap = 0 end
        
        local nodeSize = draggingBtn and draggingBtn:GetWidth() or 44
        local spacing = nodeSize + gap
        local snapDist = 28
        
        local bestX, bestY = relX, relY
        local minDistance = snapDist
        
        local buttons = w.ringButtons or w.buttons or (self.tab and self.tab.ringButtons) or {}
        
        for _, btn in ipairs(buttons) do
            if btn ~= draggingBtn and btn:IsShown() then
                local s = btn.slotData
                local hasContent = s and (s.type or s.id or s.spell or s.item or s.macro or s.toy or s.custom or s.binding)
                local isManuallyMoved = s and (s.nodePositionX ~= nil or s.nodePositionY ~= nil)
                
                -- Only active/placed nodes act as magnetic anchors (ignores default unplaced background slots)
                if hasContent or isManuallyMoved then
                    local bx, by
                    if btn.basePreviewX then
                        bx = btn.basePreviewX + (s and s.nodePositionX or 0) - centerX
                        by = btn.basePreviewY + (s and s.nodePositionY or 0) - centerY
                    else
                        local p, r, rp, x, y = btn:GetPoint()
                        bx = x - centerX
                        by = y - centerY
                    end
                    
                    if bx and by then
                        -- 8 magnetic slots around the anchor node + 1 center overlap slot
                        local candidateSlots = {
                            { x = bx + spacing, y = by },           -- Right
                            { x = bx - spacing, y = by },           -- Left
                            { x = bx,           y = by + spacing }, -- Top
                            { x = bx,           y = by - spacing }, -- Bottom
                            { x = bx + spacing, y = by + spacing }, -- Top-Right
                            { x = bx - spacing, y = by + spacing }, -- Top-Left
                            { x = bx + spacing, y = by - spacing }, -- Bottom-Right
                            { x = bx - spacing, y = by - spacing }, -- Bottom-Left
                            { x = bx,           y = by },           -- Center
                        }
                        
                        for _, slot in ipairs(candidateSlots) do
                            local dx = slot.x - relX
                            local dy = slot.y - relY
                            local dist = math.sqrt(dx * dx + dy * dy)
                            if dist < minDistance then
                                minDistance = dist
                                bestX = slot.x
                                bestY = slot.y
                            end
                        end
                    end
                end
            end
        end
        return centerX + bestX, centerY + bestY
    end
    
    if gridType == "square" then
        local sx, sy = self:GetSquareGridStepXY()
        relX = math.floor(relX / sx + 0.5) * sx
        relY = math.floor(relY / sy + 0.5) * sy
    elseif gridType == "radial" then
        local rstep, astep = self:GetRadialSteps()
        local r = math.sqrt(relX * relX + relY * relY)
        local theta = math.atan2(relY, relX)
        r = math.floor(r / rstep + 0.5) * rstep
        theta = math.floor(theta / astep + 0.5) * astep
        relX = r * math.cos(theta)
        relY = r * math.sin(theta)
    end
    return centerX + relX, centerY + relY
end

-- Draw (or hide) the grid dots that show where nodes will snap.
function ActionHub:UpdateMoveGrid()
    local hub = self.minimizedMoveModeHub
    local w = hub and self.widgets and self.widgets[hub]
    if not w or not w.moveOverlay then return end
    local overlay = w.moveOverlay
    overlay.gridDots = overlay.gridDots or {}
    for _, d in ipairs(overlay.gridDots) do d:Hide() end

    -- The per-widget dot grid competes with the screen grid; show one or the
    -- other, never both.
    if self.screenGridOn then return end

    local gridType = self.moveGridType or "off"
    if gridType == "off" or gridType == "magnetic" then return end

    local zoneHalf = w.moveZoneHalf or 235
    local idx = 0
    local function dot(gx, gy)
        if math.abs(gx) > zoneHalf or math.abs(gy) > zoneHalf then return end
        idx = idx + 1
        local d = overlay.gridDots[idx]
        if not d then
            d = overlay:CreateTexture(nil, "ARTWORK")
            d:SetTexture("Interface\\Buttons\\WHITE8X8")
            overlay.gridDots[idx] = d
        end
        d:SetSize(4, 4)
        d:SetVertexColor(0.6, 0.85, 1, 0.55)
        d:ClearAllPoints()
        d:SetPoint("CENTER", overlay, "CENTER", gx, gy)
        d:Show()
    end

    if gridType == "square" then
        local sx, sy = self:GetSquareGridStepXY()
        local nx = math.floor(zoneHalf / sx)
        local ny = math.floor(zoneHalf / sy)
        for i = -nx, nx do
            for j = -ny, ny do
                dot(i * sx, j * sy)
            end
        end
    elseif gridType == "radial" then
        dot(0, 0)
        local rstep, astep = self:GetRadialSteps()
        local rings = math.floor(zoneHalf / rstep)
        for ring = 1, rings do
            local r = ring * rstep
            local a = 0
            while a < math.pi * 2 - 0.001 do
                dot(r * math.cos(a), r * math.sin(a))
                a = a + astep
            end
        end
    end
end

function ActionHub:UpdatePreviewMoveGrid(tab)
    if not tab or not tab.moveOverlay then return end
    local overlay = tab.moveOverlay
    overlay.gridDots = overlay.gridDots or {}
    for _, d in ipairs(overlay.gridDots) do d:Hide() end

    local gridType = self.moveGridType or "off"
    if gridType == "off" or gridType == "magnetic" then return end

    local zoneHalf = 205
    local idx = 0
    local function dot(gx, gy)
        if math.abs(gx) > zoneHalf or math.abs(gy) > zoneHalf then return end
        idx = idx + 1
        local d = overlay.gridDots[idx]
        if not d then
            d = overlay:CreateTexture(nil, "ARTWORK")
            d:SetTexture("Interface\\Buttons\\WHITE8X8")
            overlay.gridDots[idx] = d
        end
        d:SetSize(4, 4)
        d:SetVertexColor(0.6, 0.85, 1, 0.55)
        d:ClearAllPoints()
        d:SetPoint("CENTER", overlay, "CENTER", gx, gy)
        d:Show()
    end

    if gridType == "square" then
        local sx, sy = self:GetSquareGridStepXY()
        local nx = math.floor(zoneHalf / sx)
        local ny = math.floor(zoneHalf / sy)
        for i = -nx, nx do
            for j = -ny, ny do
                dot(i * sx, j * sy)
            end
        end
    elseif gridType == "radial" then
        dot(0, 0)
        local rstep, astep = self:GetRadialSteps()
        local rings = math.floor(zoneHalf / rstep)
        for ring = 1, rings do
            local r = ring * rstep
            local a = 0
            while a < math.pi * 2 - 0.001 do
                dot(r * math.cos(a), r * math.sin(a))
                a = a + astep
            end
        end
    end
end

function ActionHub:EnterMinimizedMoveMode()
    if InCombatLockdown() then
        print("|cffff5555OxedHub:|r " .. (L["ERR_CANNOT_MOVE_COMBAT"] or "Can't enter move mode during combat."))
        return
    end

    self.minimizedMoveModeHub = self:GetActiveHubIndex() or 1

    -- Start on the active hub alone; the dialog's hub row unlocks the others.
    self.minimizedMoveModeHubs = { [self.minimizedMoveModeHub] = true }

    local w = self:CreateWidget(self.minimizedMoveModeHub)
    if w then w:SetMovable(true) end

    -- Hide the editor / main window so the screen is clear for dragging
    if self.pickerDialog and self.pickerDialog:IsShown() then self.pickerDialog:Hide() end
    if OxedHub.mainFrame then OxedHub.mainFrame:Hide() end

    local doneFrame = self:GetOrCreateMoveModeDoneFrame()
    doneFrame:Show()
    if doneFrame.updateHubToggles then doneFrame.updateHubToggles() end
    if doneFrame.updateGridButtons then doneFrame.updateGridButtons() end
    if doneFrame.SyncSpacingSliders then doneFrame.SyncSpacingSliders() end
    self:RefreshWidget()
end

function ActionHub:ExitMinimizedMoveMode()
    -- The grid is a positioning aid only; never leave it on screen after.
    if self.SetScreenGridShown then self:SetScreenGridShown(false) end
    self.minimizedMoveModeHub = nil
    self.minimizedMoveModeHubs = nil
    if self.moveModeDoneFrame then self.moveModeDoneFrame:Hide() end
    if OxedHub.mainFrame then OxedHub.mainFrame:Show() end
    self:RefreshWidget()
    if self.tab then self:RefreshTab() end
end

local function CloneSlotData(slot)
    if type(slot) ~= "table" then
        return { type = nil, id = nil }
    end

    local copy = {}
    for key, value in pairs(slot) do
        copy[key] = value
    end
    return copy
end

local function GetPreviewButtonDragIconTexture(btn)
    if not btn then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    if btn.splitIcon and btn.splitIcon:IsShown() and btn.splitIcon.leftTexture and btn.splitIcon.leftTexture:GetTexture() then
        return btn.splitIcon.leftTexture:GetTexture()
    end

    if btn.icon and btn.icon:GetTexture() then
        return btn.icon:GetTexture()
    end

    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Swap a node's CONTENT while keeping its own layout (position/size/binding), so
-- swapping two nodes doesn't make them jump to each other's positions.
local WIDGET_SLOT_LAYOUT_KEYS = { "nodeSize", "nodePositionX", "nodePositionY", "binding" }
local function BuildSlotWithLayout(layoutSource, contentSource)
    local out = CloneSlotData(contentSource)
    for _, k in ipairs(WIDGET_SLOT_LAYOUT_KEYS) do
        out[k] = layoutSource and layoutSource[k] or nil
    end
    return out
end

function ActionHub:BeginPreviewAssignmentDrag(btn)
    if not btn or self:IsPreviewMoveModeActiveForButton(btn) then
        return
    end

    local slot = btn.slotData
    if not (slot and slot.type and btn.slotIndex and btn.slotSide) then
        return
    end

    self.dragData = {
        type = "panel_slot",
        sourceSlotIndex = btn.slotIndex,
        sourceSlotSide = btn.slotSide,
        sourceHubIndex = self:GetActiveHubIndex(),
        icon = GetPreviewButtonDragIconTexture(btn),
    }

    if not self.dragIcon then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(32, 32)
        f:SetFrameStrata("TOOLTIP")
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        f.tex = t
        self.dragIcon = f
    end

    self.dragIcon.tex:SetTexture(self.dragData.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    self.dragIcon:Show()
    self.dragIcon:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    end)

    btn.wasAssignmentDragged = false
end

function ActionHub:EndPreviewAssignmentDrag(btn)
    if self.dragIcon then
        self.dragIcon:Hide()
        self.dragIcon:SetScript("OnUpdate", nil)
    end

    local dragData = self.dragData
    self.dragData = nil

    if not dragData or dragData.type ~= "panel_slot" then
        return
    end

    local dropTarget = nil
    local tab = self.tab
    if tab and tab.ringButtons then
        for _, rb in ipairs(tab.ringButtons) do
            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                dropTarget = rb
                break
            end
        end
    end

    if not dropTarget then
        return
    end

    local activeHubIndex = self:GetActiveHubIndex()
    if dragData.sourceHubIndex ~= activeHubIndex then
        return
    end

    local sourceSlots = self:GetSlotsForSide(self:GetActiveHubDB(), dragData.sourceSlotSide)
    local targetSlots = self:GetSlotsForSide(self:GetActiveHubDB(), dropTarget.slotSide)
    local sourceSlot = sourceSlots and sourceSlots[dragData.sourceSlotIndex]
    local targetSlot = targetSlots and targetSlots[dropTarget.slotIndex]
    if not sourceSlot or not targetSlot then
        return
    end

    if dragData.sourceSlotSide == dropTarget.slotSide and dragData.sourceSlotIndex == dropTarget.slotIndex then
        return
    end

    -- Swap CONTENT only; each node keeps its own on-screen layout so the icons
    -- don't jump to each other's positions when swapped.
    local sourceContent = CloneSlotData(sourceSlot)
    local targetContent = CloneSlotData(targetSlot)

    sourceSlots[dragData.sourceSlotIndex] = BuildSlotWithLayout(sourceSlot, targetContent)
    targetSlots[dropTarget.slotIndex] = BuildSlotWithLayout(targetSlot, sourceContent)

    if btn then
        btn.wasAssignmentDragged = true
    end
    dropTarget.wasAssignmentDragged = true

    self:RefreshPickerList()
    self:RefreshWidget()
    self:RefreshTab()
end

-- ── On-screen widget shift-drag (works for ALL node types) ──────────────────
-- The WoW cursor can only carry toys/spells/items/macros, not toy-mixes, emotes
-- or mounts. So on-screen nodes use an INTERNAL drag: a floating icon follows the
-- cursor and, on release over another node, the two nodes' CONTENT is swapped
-- (each node keeps its own position/size/binding). Released over nothing = remove.
function ActionHub:BeginWidgetSlotDrag(btn)
    if InCombatLockdown() then return false end
    local w = btn:GetParent()
    if not (w and w.hubIndex and btn.slotIndex and btn.slotSide) then return false end
    local slots = self:GetSlotsForSide(self:GetHubDB(w.hubIndex), btn.slotSide)
    local slot = slots and slots[btn.slotIndex]
    if not (slot and slot.type) then return false end

    self.widgetDragData = {
        hubIndex = w.hubIndex,
        slotIndex = btn.slotIndex,
        slotSide = btn.slotSide,
    }

    if not self.dragIcon then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(36, 36)
        f:SetFrameStrata("TOOLTIP")
        local t = f:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        f.tex = t
        self.dragIcon = f
    end
    self.dragIcon.tex:SetTexture(GetPreviewButtonDragIconTexture(btn))
    self.dragIcon:Show()
    self.dragIcon:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    end)
    return true
end

function ActionHub:EndWidgetSlotDrag()
    if self.dragIcon then
        self.dragIcon:Hide()
        self.dragIcon:SetScript("OnUpdate", nil)
    end
    local drag = self.widgetDragData
    self.widgetDragData = nil
    if not drag or InCombatLockdown() then return end

    local srcSlots = self:GetSlotsForSide(self:GetHubDB(drag.hubIndex), drag.slotSide)
    local srcSlot = srcSlots and srcSlots[drag.slotIndex]
    if not srcSlot then return end

    -- Find the widget node currently under the cursor.
    local target
    for _, w in ipairs(self.widgets or {}) do
        if w.buttons then
            for _, b in ipairs(w.buttons) do
                local isOver = false
                if b and b.IsMouseOver then
                    isOver = b:IsMouseOver()
                elseif b and type(_G.MouseIsOver) == "function" then
                    isOver = _G.MouseIsOver(b)
                end
                if b and b:IsShown() and b.slotIndex and b.slotSide and isOver then
                    target = b
                    break
                end
            end
        end
        if target then break end
    end

    if target then
        local tgtHub = target:GetParent().hubIndex
        if drag.hubIndex == tgtHub and drag.slotSide == target.slotSide and drag.slotIndex == target.slotIndex then
            return -- dropped on itself, no change
        end
        local tgtSlots = self:GetSlotsForSide(self:GetHubDB(tgtHub), target.slotSide)
        local tgtSlot = tgtSlots and tgtSlots[target.slotIndex]
        if not tgtSlot then return end
        -- swap CONTENT, keep each node's own layout
        local srcContent = CloneSlotData(srcSlot)
        local tgtContent = CloneSlotData(tgtSlot)
        srcSlots[drag.slotIndex] = BuildSlotWithLayout(srcSlot, tgtContent)
        tgtSlots[target.slotIndex] = BuildSlotWithLayout(tgtSlot, srcContent)
    else
        -- released over empty space: clear the node (keep its layout)
        srcSlots[drag.slotIndex] = BuildSlotWithLayout(srcSlot, nil)
    end

    self:RefreshAllWidgets()
    if self.pickerDialog and self.pickerDialog:IsShown() then
        self:RefreshTab()
    end
end

function ActionHub:RefreshAllWidgets()
    local hubs = self:GetHubs()
    for i = 1, #hubs do
        self:RefreshWidgetForHub(i)
    end
    -- Hide any extra widgets that no longer have hubs
    if self.widgets then
        for i = #hubs + 1, #self.widgets do
            if self.widgets[i] then self.widgets[i]:Hide() end
        end
    end
end

-- Alias so existing code calling RefreshWidget still works
function ActionHub:RefreshWidget()
    self:RefreshAllWidgets()
end

function ActionHub:RefreshWidgetForHub(hubIndex)
    if InCombatLockdown() then
        if not self.pendingRefreshEvent then
            self.pendingRefreshEvent = CreateFrame("Frame")
            self.pendingRefreshEvent:SetScript("OnEvent", function(f)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                ActionHub:RefreshAllWidgets()
            end)
        end
        self.pendingRefreshEvent:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    local w = self:CreateWidget(hubIndex)
    if not w then return end
    w.hubIndex = hubIndex

    local db = EnsureHubData(self:GetHubDB(hubIndex), hubIndex)
    if not db then w:Hide() return end
    local moveMode = self:IsMinimizedMoveMode(hubIndex) or (ActionHub.pickerDialog and ActionHub.pickerDialog.moveNodeMode and self:GetActiveHubIndex() == hubIndex)
    TrimSideToLimit(db, "primary")
    TrimSideToLimit(db, "secondary")
    local slots = self:GetSlotsForSide(db, "primary")
    local secondarySlots = self:GetSlotsForSide(db, "secondary")
    local quadrant = self:GetQuadrant(db)
    local dualQuadrant = GetDualQuadrant(quadrant, db.dualSideLayout)
    local maxSlots = #slots
    local secondaryMaxSlots = (db.dualSideEnabled and #secondarySlots) or 0
    local totalSlots = maxSlots + secondaryMaxSlots

    -- Position the widget based on saved position
    local pos = db.widgetPosition or { x = 0, y = 0 }
    w:ClearAllPoints()
    w:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)

    -- Show/hide anchor
    local unlocked = not not db.widgetUnlocked
    local isMoveActive = not not moveMode
    -- While the screen grid is up the logo and the empty "+" nodes only get in
    -- the way: they widen the hub visually, so its real edges no longer line up
    -- with the grid and symmetric placement becomes guesswork.
    local gridAligning = not not ActionHub.screenGridOn
    local showLogo = (unlocked or not not db.showLogoWhenLocked or isMoveActive)
        and not gridAligning
    w:SetMovable(unlocked or isMoveActive)
    w.anchor:ClearAllPoints()
    w.anchor:SetPoint("CENTER", w, "CENTER", db.logoOffsetX or 0, db.logoOffsetY or 0)
    w.anchor:Show()
    if showLogo then
        if w.anchor.tex then w.anchor.tex:Show() end
    else
        if w.anchor.tex then w.anchor.tex:Hide() end
    end
    if unlocked then
        if w.anchor.label then w.anchor.label:Show() end
        w.anchor:SetBackdropColor(0.15, 0.15, 0.15, 0.85)
        w.anchor:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        w.anchor:EnableMouse(true)
    else
        if w.anchor.label then w.anchor.label:Hide() end
        w.anchor:SetBackdropColor(0, 0, 0, 0)
        w.anchor:SetBackdropBorderColor(0, 0, 0, 0)
        -- FIX 1: Only capture mouse when the logo is visible so the user has
        -- something to click.  When the widget is locked and the logo is hidden
        -- the anchor sits invisibly at FrameLevel 120 (above the node buttons at
        -- ~100) and silently swallows every click that lands on it.
        w.anchor:EnableMouse(not not (db.showLogoWhenLocked or isMoveActive))
    end

    -- Hide old buttons
    for _, btn in ipairs(w.buttons) do
        btn:Hide()
    end

    if totalSlots == 0 then
        w:SetShown(db.onScreen or moveMode)
        -- The blue zone marks a 235px drag box.  With the screen grid up that
        -- box is the wrong reference and just occludes the guides, so it hides.
        if w.moveOverlay then
            w.moveOverlay:SetShown(moveMode and not ActionHub.screenGridOn)
        end
        self:ApplyWidgetCombatVisibility(w, db)
        self:UpdateCombatVisibilityTicker()
        return
    end

    local cx, cy = 150, -150 -- center of the 300x300 widget
    local baseRadius = 65
    local radiusStep = db.nodeLineSize or 48

    -- Commands that MUST stay in the secure macro because they are protected
    -- (can only run from a secure button click). Everything else — /say, /yell,
    -- /emote and other social commands — is deliberately dropped here because the
    -- button's PostClick handler already fires chat/emote/sound/animation via
    -- SendChatMessage/DoEmote. Leaving them in the macro too caused DOUBLE chat.
    local ALLOWED_MACRO_CMDS = {
        ["/use"] = true, ["/cast"] = true, ["/castrandom"] = true,
        ["/castsequence"] = true, ["/userandom"] = true, ["/cancelaura"] = true,
        ["/cancelqueuedspell"] = true, ["/stopmacro"] = true, ["/stopcasting"] = true,
        ["/target"] = true, ["/cleartarget"] = true, ["/focus"] = true,
        ["/petattack"] = true, ["/startattack"] = true, ["/click"] = true,
    }
    local function StripRestrictedMacroLines(text)
        if not text then return nil end
        local lines = {}
        for line in text:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                if trimmed:match("^#") then
                    -- keep macro directives like #showtooltip
                    table.insert(lines, trimmed)
                else
                    local cmd = trimmed:match("^(/%S+)")
                    if cmd and ALLOWED_MACRO_CMDS[cmd:lower()] then
                        table.insert(lines, trimmed)
                    end
                    -- else: social/effect line — handled by PostClick, drop it
                end
            end
        end
        return table.concat(lines, "\n")
    end

    local function EnsureWidgetButton(index)
        local btn = w.buttons[index]
        if btn then
            return btn
        end

        -- FIX 2: Include hubIndex in the global frame name.  WoW reuses an
        -- existing frame when CreateFrame is called with a name that already
        -- exists, which meant Hub 2 was silently stealing Hub 1's buttons and
        -- parenting them to the wrong widget.
        btn = CreateFrame("Button", "OxedHubActionHubButton"..w.hubIndex.."_"..index, w, "SecureActionButtonTemplate, BackdropTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type1", "macro")
        local initSize = db.globalNodeSize or 44
        btn:SetSize(initSize, initSize)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", btn, "CENTER", 0, -1)
        icon:SetSize(32, 32)
        btn.icon = icon

        local plus = btn:CreateTexture(nil, "OVERLAY")
        plus:SetPoint("CENTER", btn, "CENTER", 0, -3)
        plus:SetSize(24, 24)
        plus:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\add.tga")
        btn.plus = plus

        -- Golden/blue glow shown only during minimized move mode
        local glow = btn:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
        glow:SetSize(initSize + 20, initSize + 20)
        glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
        glow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0.3, 0.7, 1, 1)
        glow:Hide()
        btn.glow = glow

        -- Clockwise darkening sweep while on cooldown, like the default bars.
        -- SetReverse(false) makes it wind down clockwise instead of filling up.
        local cd1 = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd1:SetAllPoints()
        cd1:SetFrameLevel(btn:GetFrameLevel() + 5)
        cd1:SetDrawBling(false)
        cd1:SetDrawEdge(false)
        cd1:SetDrawSwipe(true)
        cd1:SetSwipeColor(0, 0, 0, 0.65)
        cd1:SetReverse(false)
        cd1:EnableMouse(false)
        cd1:Hide()
        StyleCooldownText(cd1, 6)
        btn.cooldown1 = cd1

        local cd2 = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd2:SetAllPoints()
        cd2:SetFrameLevel(btn:GetFrameLevel() + 6)
        cd2:SetDrawBling(false)
        cd2:SetDrawEdge(false)
        cd2:SetDrawSwipe(true)
        cd2:SetSwipeColor(0, 0, 0, 0.65)
        cd2:SetReverse(false)
        cd2:EnableMouse(false)
        cd2:Hide()
        StyleCooldownText(cd2, -6)
        btn.cooldown2 = cd2

        local hlFrame = CreateFrame("Frame", nil, btn)
        hlFrame:SetAllPoints()
        hlFrame:SetFrameLevel(btn:GetFrameLevel() + 20)
        local hlTex = hlFrame:CreateTexture(nil, "OVERLAY")
        hlTex:SetAllPoints()
        hlTex:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hlTex:SetBlendMode("ADD")
        hlTex:Hide()
        btn.squareHighlight = hlTex

        btn:SetScript("OnEnter", function(self)
            local s = self.slotData
            if s and s.type and db.showTooltip ~= false then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if s.type == "toy" then
                    if GetToyAssignmentMode(s) == "direct" then
                        local toyName = GetDirectToyDisplay(s.id)
                        GameTooltip:SetText(string.format(L["TOOLTIP_TOY_FORMAT"] or "Toy: %s", tostring(toyName or s.id)))
                    else
                        GameTooltip:SetText(string.format(L["TOOLTIP_TOYMIX_FORMAT"] or "Toy Mix: %s", tostring(s.id)))
                    end
                elseif s.type == "emote" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_REACTION_FORMAT"] or "Reaction: %s", tostring(s.id)))
                elseif s.type == "trigger" then
                    local trg = OxedHub.db.profile.triggers[s.id]
                    GameTooltip:SetText(string.format(L["TOOLTIP_TRIGGER_FORMAT"] or "Trigger: %s", (trg and (trg.name or s.id) or tostring(s.id))))
                elseif s.type == "mount" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_MOUNT_FORMAT"] or "Mount: %s", tostring(s.label or s.id)))
                elseif s.type == "item" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_ITEM_FORMAT"] or "Item: %s", tostring(s.label or s.id)))
                elseif s.type == "spell" then
                    GameTooltip:SetText(string.format("Spell: %s", tostring(s.label or s.id)))
                elseif s.type == "macro" then
                    GameTooltip:SetText(string.format("Macro: %s", tostring(s.label or s.id)))
                end
                GameTooltip:Show()
            end
            local currentStyle = db.style or "square"
            if currentStyle == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(1, 0.95, 0.4, 1)
            else
                self:SetBackdropBorderColor(1, 0.95, 0.4, 1)
            end
            if self.squareHighlight then self.squareHighlight:Show() end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            local currentStyle = db.style or "square"
            if currentStyle == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
            else
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            end
            if self.squareHighlight then self.squareHighlight:Hide() end
        end)

        -- Drag-and-drop: accept emote drags from the picker grid, plus external game cursor drops
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnReceiveDrag", function(self)
            if InCombatLockdown() then
                print("|cffff0000OxedHub:|r Cannot assign slots during combat.")
                ClearCursor()
                return
            end

            local infoType, info1, info2, info3 = GetCursorInfo()
            if not infoType then return end

            local w = self:GetParent()
            local hubIndex = w.hubIndex
            local hubDB = ActionHub:GetHubDB(hubIndex)
            local slots = ActionHub:GetSlotsForSide(hubDB, self.slotSide)
            local currentSlot = slots[self.slotIndex] or {}

            -- Preserve the displaced content so we can swap it onto the cursor.
            local displaced = (currentSlot and currentSlot.type) and currentSlot or nil

            local newSlot = {
                nodeSize = currentSlot.nodeSize,
                nodePositionX = currentSlot.nodePositionX,
                nodePositionY = currentSlot.nodePositionY,
                binding = currentSlot.binding
            }

            if infoType == "item" then
                local itemID = info1
                if C_ToyBox.GetToyInfo(itemID) then
                    newSlot.type = "toy"
                    newSlot.id = itemID
                    newSlot.mode = "direct"
                else
                    newSlot.type = "item"
                    newSlot.id = itemID
                    newSlot.icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or GetItemIcon(itemID)
                    newSlot.label = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or GetItemInfo(itemID) or tostring(itemID)
                end
            elseif infoType == "mount" then
                local mountID = info1
                local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
                newSlot.type = "mount"
                newSlot.id = mountID
                newSlot.icon = icon
                newSlot.label = name
            elseif infoType == "spell" then
                local spellID = info3
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                newSlot.type = "spell"
                newSlot.id = spellID
                newSlot.icon = spellInfo and spellInfo.iconID
                newSlot.label = spellInfo and spellInfo.name
            elseif infoType == "macro" then
                local macroIndex = info1
                local name, icon, body = GetMacroInfo(macroIndex)
                newSlot.type = "macro"
                newSlot.id = macroIndex
                newSlot.icon = icon
                newSlot.label = name
                newSlot.body = body
            else
                return -- unsupported type, ignore
            end

            slots[self.slotIndex] = newSlot
            ClearCursor()
            -- Swap: if this node already held something, put it on the cursor so the
            -- player can drop it on another node (or discard it), like WoW bars.
            if displaced then
                ActionHub:PickupSlotToCursor(displaced)
            end
            ActionHub:RefreshWidget(w)

            if ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.hubIndex == hubIndex then
                ActionHub:RefreshTab()
            end
        end)
        
        -- We attach drop logic via OnUpdate on the source's OnDragStop,
        -- so also detect via the hover approach below:
        btn.acceptDrop = true

        -- Node drag (minimized move mode only): drag the button on screen to
        -- reposition the node. Outside move mode these are no-ops.
        btn:SetScript("OnDragStart", function(self)
            if ActionHub:IsMinimizedMoveMode(w.hubIndex) then
                ActionHub:BeginWidgetNodeDrag(self)
            elseif ActionHub.minimizedMoveModeHub and IsShiftKeyDown() then
                -- Move mode is open for a DIFFERENT hub.  Shift still moves this
                -- one as a whole, so several hubs can be aligned in one session
                -- without leaving and re-entering move mode for each.
                ActionHub:BeginWidgetSetDrag(self, w.hubIndex)
            elseif IsShiftKeyDown() and not InCombatLockdown() then
                -- Internal drag: works for every node type (mixes, emotes, mounts,
                -- toys, spells...) since it moves DB slot content, not the WoW cursor.
                self._widgetSlotDragging = ActionHub:BeginWidgetSlotDrag(self)
            end
        end)
        btn:SetScript("OnDragStop", function(self)
            if self._widgetSlotDragging then
                self._widgetSlotDragging = nil
                ActionHub:EndWidgetSlotDrag()
            else
                ActionHub:EndWidgetNodeDrag(self)
            end
        end)

        -- PreClick: Regenerate macro text to ensure toy/spell names are fresh (fixes login data issue)
        -- NOTE: must run on the DOWN phase too — the button is registered for
        -- "AnyDown", so the secure action executes on key-down. Skipping down here
        -- made every press run the PREVIOUS press's resolved random toy (off-by-one).
        btn:SetScript("PreClick", function(self, button, down)
            if ActionHub:IsMinimizedMoveMode(w.hubIndex) then return end
            if InCombatLockdown() or not self._cachedSlot then return end
            -- Only regenerate once per press: on the phase that actually fires.
            if not down then return end
            
            local slot = self._cachedSlot
            if slot and slot.type == "toy" then
                local freshMacroText = GetActionHubToyMacroText(slot)
                if freshMacroText and freshMacroText ~= "" then
                    self:SetAttribute("macrotext1", StripRestrictedMacroLines(freshMacroText))
                end
            elseif slot and slot.type == "emote" then
                -- ActionHub handles emotes via TriggerEmoteById (non-secure, PostClick)
                -- No secure macro needed for emotes in ActionHub
            elseif slot and slot.type == "mount" then
                if slot.label and slot.label ~= "" then
                    self:SetAttribute("macrotext1", "/cast " .. slot.label)
                end
            elseif slot and slot.type == "item" then
                if slot.id then
                    self:SetAttribute("macrotext1", "/use item:" .. slot.id)
                end
            elseif slot and slot.type == "spell" then
                local spellName = slot.label
                if (not spellName or spellName == "") and slot.id and C_Spell and C_Spell.GetSpellInfo then
                    local info = C_Spell.GetSpellInfo(slot.id)
                    spellName = info and info.name
                end
                if spellName and spellName ~= "" then
                    self:SetAttribute("macrotext1", "/cast " .. spellName)
                end
            end
        end)

        btn:SetScript("PostClick", function(self, button, down)
            if down then return end

            if OxedHub.Animations and OxedHub.Animations.AcquireAnimationFrame and db.allowAnimations ~= false then
                local animData = {
                    tgaPath = "Interface\\AddOns\\OxedHub\\Media\\Textures\\sparkles.tga",
                    width = 128,
                    height = 128,
                    frameCount = 25,
                    fps = 30,
                }
                local frame = OxedHub.Animations:AcquireAnimationFrame()
                if frame then
                    frame:SetParent(self)
                    frame:SetSize(self:GetWidth() * 2, self:GetHeight() * 2)
                    frame:SetFrameLevel(self:GetFrameLevel() + 10)
                    frame.texture:SetTexture(animData.tgaPath)
                    frame.currentFrame = 0
                    frame.animData = animData
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", self, "CENTER", 0, 15)
                    frame:Show()
                    OxedHub.Animations:SetAnimationFrame(frame, 0, animData)
                    local maxLoops = 1
                    local currentLoop = 1

                    -- Same safety net as the shared player: this ticker also
                    -- releases the frame only on its final tick, so record when
                    -- playback should be over and let the sweeper in Animations
                    -- clear it if that tick never arrives.
                    frame.deadline = GetTime()
                        + ((maxLoops * animData.frameCount) / animData.fps) + 2

                    frame.timer = C_Timer.NewTicker(1/animData.fps, function()
                        frame.currentFrame = frame.currentFrame + 1
                        if frame.currentFrame >= animData.frameCount then
                            if currentLoop >= maxLoops then
                                OxedHub.Animations:ReleaseAnimationFrame(frame)
                            else
                                currentLoop = currentLoop + 1
                                frame.currentFrame = 0
                                OxedHub.Animations:SetAnimationFrame(frame, 0, animData)
                            end
                        else
                            OxedHub.Animations:SetAnimationFrame(frame, frame.currentFrame, animData)
                        end
                    end, maxLoops * animData.frameCount)
                end
            end

            local s = self.slotData
            if s and s.type then
                -- Name the slot for the error journal, so a failure here reads
                -- as the node the user clicked rather than a line in this file.
                if OxedHub.ErrorJournal then
                    OxedHub.ErrorJournal:SetContext("ActionHub",
                        s.label or s.name or tostring(s.id), s.type)
                end

                if s.type == "toy" then
                    if GetToyAssignmentMode(s) == "mix" then
                        local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[s.id]
                        if mixData and mixData.actions then
                            local canRunEffects = true
                            if OxedHub.Triggers and OxedHub.Triggers.CanRunEffectsKeyed then
                                canRunEffects = OxedHub.Triggers:CanRunEffectsKeyed("mix_" .. tostring(s.id))
                            end
                            if canRunEffects then
                                if mixData.actions.sound and OxedHub.Sounds then
                                    OxedHub.Sounds:Play(mixData.actions.sound)
                                end
                                if mixData.actions.animation and OxedHub.Animations then
                                    OxedHub.Animations:Play(mixData.actions.animation, {
                                        useCustomPosition = mixData.actions.animationUseCustomPosition,
                                        x = mixData.actions.animationCustomX,
                                        y = mixData.actions.animationCustomY
                                    })
                                end
                                if mixData.actions.emote then
                                    DoEmote(mixData.actions.emote)
                                end
                                if mixData.actions.chat and OxedHub.db.profile.chatTemplates and OxedHub.db.profile.chatTemplates[mixData.actions.chat] then
                                    local ct = OxedHub.db.profile.chatTemplates[mixData.actions.chat]
                                    SendChatMessage(ct.text, ct.channel)
                                end
                            end
                        end
                    end
                elseif s.type == "emote" then
                    ActionHub:TriggerEmoteById(s.id)
                elseif s.type == "trigger" then
                    if OxedHub.Triggers and OxedHub.Triggers.ExecuteTriggerByID then
                        OxedHub.Triggers:ExecuteTriggerByID(s.id, true)
                    end
                end

                if OxedHub.ErrorJournal then OxedHub.ErrorJournal:ClearContext() end
            end

            ActionHub:QueueCooldownRefresh()
        end)

        w.buttons[index] = btn
        return btn
    end

    local function RenderSlot(slot, btn)
        local macroText = ""

        if slot and slot.type then
            if btn.plus then btn.plus:Hide() end
            if btn.splitIcon then btn.splitIcon:Hide() end

            if slot.type == "toy" then
                macroText = GetActionHubToyMacroText(slot)
                if GetToyAssignmentMode(slot) == "direct" then
                    local _, icon = GetDirectToyDisplay(slot.id)
                    btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.icon:Show()
                else
                    -- Check for custom icon override first
                    local customIcon = OxedHub.Toys and OxedHub.Toys.GetMixCustomIcon and OxedHub.Toys:GetMixCustomIcon(slot.id)
                    if customIcon then
                        btn.icon:SetTexture(customIcon)
                        btn.icon:Show()
                    else
                        local icon1, icon2, icon3, icon4
                        if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                            icon1, icon2, icon3, icon4 = OxedHub.Toys:GetMixSlotIcons(slot.id)
                        end
                        if icon1 and icon2 and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                            btn.icon:Hide()
                            btn.splitIcon = OxedHub.Toys:CreateSplitIcon(btn, 40, icon1, icon2, icon3, icon4)
                            btn.splitIcon:SetPoint("CENTER", btn, "CENTER", 0, -1)
                            btn.splitIcon:Show()
                        else
                            btn.icon:SetTexture(icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                            btn.icon:Show()
                        end
                    end
                end
            elseif slot.type == "emote" then
                local reactionIcon = ActionHub:GetEmoteIconById(slot.id)
                    or "Interface\\Icons\\Spell_Holy_AshesToAshes"
                btn.icon:SetTexture(reactionIcon)
                btn.icon:Show()
                -- Emote playback is handled in PostClick via TriggerEmoteById
            elseif slot.type == "trigger" then
                local trg = OxedHub.db.profile.triggers[slot.id]
                if trg then
                    local triggerIcon = (OxedHub.Triggers and OxedHub.Triggers.GetTriggerDisplayIcon and OxedHub.Triggers:GetTriggerDisplayIcon(trg))
                        or "Interface\\Icons\\INV_Misc_QuestionMark"
                    btn.icon:SetTexture(triggerIcon)
                    btn.icon:Show()
                    if OxedHub.Triggers and OxedHub.Triggers.BuildTriggerMacroBody then
                        macroText = OxedHub.Triggers:BuildTriggerMacroBody(trg) or ""
                    end
                end
            elseif slot.type == "marker" or slot.type == "targetmarker" or slot.type == "ping" then
                btn.icon:SetTexture(GetMarkerPingIcon(slot))
                btn.icon:Show()
                macroText = GetMarkerPingMacro(slot) or ""
            elseif slot.type == "mount" then
                btn.icon:SetTexture(slot.icon or "Interface\\Icons\\MountJournalPortrait")
                btn.icon:Show()
                if slot.label and slot.label ~= "" then
                    macroText = "/cast " .. slot.label
                end
            elseif slot.type == "item" then
                btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_Bag_08")
                btn.icon:Show()
                if slot.id then
                    macroText = "/use item:" .. slot.id
                end
            elseif slot.type == "spell" then
                btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:Show()
                if slot.id then
                    local spellName = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(slot.id)) or slot.label or slot.id
                    macroText = "/cast " .. spellName
                end
            elseif slot.type == "macro" then
                btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:Show()
                if slot.body then
                    macroText = slot.body
                end
            end
        else
            btn.icon:Hide()
            if btn.splitIcon then btn.splitIcon:Hide() end
            if btn.plus then btn.plus:Show() end
        end

        -- A custom icon replaces whatever the slot's content resolved to above,
        -- including split (multi-toy) icons.
        local customTex = slot and slot.type and ResolveCustomIcon(slot.customIcon)
        if customTex then
            if btn.splitIcon then btn.splitIcon:Hide() end
            btn.icon:SetTexture(customTex)
            btn.icon:Show()
        end

        if not InCombatLockdown() then
            -- In move mode, clear the macro so clicking a node does nothing
            -- (only dragging should act on it).
            btn:SetAttribute("macrotext1", moveMode and "" or StripRestrictedMacroLines(macroText))

            -- Store slot reference for PreClick regeneration
            btn._cachedSlot = slot
            
            ClearOverrideBindings(btn)
            if slot and slot.binding then
                SetOverrideBindingClick(btn, true, slot.binding, btn:GetName())
            end
        else
            -- FIX 4: SetAttribute and ClearOverrideBindings are forbidden during
            -- combat lockdown, so this render pass left the button with its old
            -- (possibly empty) macro.  Schedule a full widget refresh for when
            -- combat ends so all attributes and bindings get reapplied cleanly.
            if not ActionHub.pendingRefreshEvent then
                ActionHub.pendingRefreshEvent = CreateFrame("Frame")
                ActionHub.pendingRefreshEvent:SetScript("OnEvent", function(f)
                    f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    ActionHub:RefreshAllWidgets()
                end)
            end
            ActionHub.pendingRefreshEvent:RegisterEvent("PLAYER_REGEN_ENABLED")
        end

        local size = (slot and slot.nodeSize) or db.globalNodeSize or 44
        btn:SetSize(size, size)
        StyleButton(btn, db.style or "square", size, false)
        -- Not a protected operation, so this still updates during combat lockdown.
        UpdateBindingLabel(btn, slot, size, db.style or "square")
    end

    local buttonCursor = 1
    local function RenderSide(sideSlots, sideKey, sideQuadrant)
        local skipEdge = (sideKey == "secondary") and GetSecondarySkipEdge(quadrant, sideQuadrant, db.dualSideLayout) or nil
        for i = 1, #sideSlots do
            local slot = sideSlots[i]
            local btn = EnsureWidgetButton(buttonCursor)
            buttonCursor = buttonCursor + 1

            local x, y = GetArcCoordinates(i, #sideSlots, sideQuadrant, cx, cy, baseRadius, radiusStep, slot, skipEdge)
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", w, "TOPLEFT", x, y)
            -- Base arc position WITHOUT the node offset (used by on-screen drag)
            btn.baseArcX = x - ((slot and slot.nodePositionX) or 0)
            btn.baseArcY = y - ((slot and slot.nodePositionY) or 0)
            btn.slotData = slot
            btn.slotIndex = i
            btn.slotSide = sideKey

            -- Move mode normally forces empty slots visible so they can be
            -- filled.  While aligning to the screen grid they are hidden
            -- outright: their frames widen the hub and defeat the whole point
            -- of lining its real edges up against the grid.
            local showEmpty = (db.widgetUnlocked or moveMode)
                and not ActionHub.screenGridOn
            if (slot and slot.type) or showEmpty then
                btn:Show()
                RenderSlot(slot, btn)
            else
                btn:Hide()
                if not InCombatLockdown() then
                    ClearOverrideBindings(btn)
                end
                if btn.cooldown1 then btn.cooldown1:Hide() end
                if btn.cooldown2 then btn.cooldown2:Hide() end
            end
        end
    end

    RenderSide(slots, "primary", quadrant)
    if db.dualSideEnabled and secondaryMaxSlots > 0 then
        RenderSide(secondarySlots, "secondary", dualQuadrant)
    end

    for i = buttonCursor, #w.buttons do
        local btn = w.buttons[i]
        if btn then
            btn:Hide()
            btn.slotData = nil
            btn.slotIndex = nil
            btn.slotSide = nil
            if not InCombatLockdown() then
                ClearOverrideBindings(btn)
            end
            if btn.cooldown1 then btn.cooldown1:Hide() end
            if btn.cooldown2 then btn.cooldown2:Hide() end
        end
    end

    w:SetShown(db.onScreen or moveMode)

    -- Move-mode visuals: blue overlay, node glows, and raise nodes above the
    -- overlay so they keep their own drag handling.
    -- The blue zone marks a 235px drag box.  With the screen grid up that
    -- box is the wrong reference and just occludes the guides, so it hides.
    if w.moveOverlay then
        w.moveOverlay:SetShown(moveMode and not ActionHub.screenGridOn)
    end
    if moveMode then
        w:SetMovable(true)
        self:UpdateMoveGrid()
    end
    for _, btn in ipairs(w.buttons) do
        SetNodeSelected(btn, moveMode and btn:IsShown(), db.style or "square")
        if moveMode and btn:IsShown() then
            btn:SetFrameLevel(w:GetFrameLevel() + 10)
        end
    end

    self:ApplyWidgetCombatVisibility(w, db)

    if ActionHub.cooldownTicker then
        ActionHub.cooldownTicker:Cancel()
        ActionHub.cooldownTicker = nil
    end

    self:UpdateWidgetCooldowns()

    if totalSlots > 0 and db.onScreen then
        ActionHub.cooldownTicker = C_Timer.NewTicker(0.5, function()
            ActionHub:UpdateWidgetCooldowns()
        end)
    end

    self:UpdateCombatVisibilityTicker()
end

function ActionHub:CreateTab(contentArea)
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(7)
    if OxedHub.UI and OxedHub.UI.ApplyToysBackground then
        OxedHub.UI.ApplyToysBackground(tab)
    end
    local insetLeft, insetRight, insetTop, insetBottom = 42, 56, 66, 54
    if OxedHub.UI and OxedHub.UI.GetThemedFrameInsets then
        insetLeft, insetRight, insetTop, insetBottom = OxedHub.UI:GetThemedFrameInsets()
    end

    -- Title
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -insetTop + 34)
    title:SetText(L["AH_TITLE"] or "Action Hub")
    title:Hide()

    -- Description
    local desc = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    desc:SetText(L["AH_DESC"] or "Quarter-ring (1/4 circle) floating widget with optional Dual Side support.")
    desc:SetTextColor(0.7, 0.7, 0.7)

    local infoBtn = CreateFrame("Button", nil, tab)
    infoBtn:SetSize(16, 16)
    infoBtn:SetPoint("LEFT", desc, "RIGHT", 4, 0)
    infoBtn:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    infoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["AH_ALIGN_INFO"] or "Hold |cFFFFD100CTRL|r and click to select multiple nodes.\nThen |cFFFFD100Right-Click|r any selected node to align them.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Hub selector row
    local hubRow = CreateFrame("Frame", nil, tab)
    hubRow:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    hubRow:SetSize(500, 28)
    tab.hubRow = hubRow
    tab.hubBtns = {}

    -- Controls row
    local controls = CreateFrame("Frame", nil, tab)
    controls:SetPoint("TOPLEFT", hubRow, "BOTTOMLEFT", 0, -8)
    controls:SetSize(980, 112)

    local function GetDB() return ActionHub:GetActiveHubDB() end
    local function GetEditSlots()
        return ActionHub:GetSlotsForSide(GetDB(), ActionHub:GetEditedSide())
    end

    local hideCombatCheck = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    hideCombatCheck:SetPoint("TOPLEFT", controls, "TOPLEFT", 0, -4)
    hideCombatCheck:SetSize(22, 22)
    hideCombatCheck:SetChecked(GetDB().hideInCombat)
    hideCombatCheck:SetScript("OnClick", function(self)
        GetDB().hideInCombat = self:GetChecked()
        ActionHub:UpdateCombatVisibilityTicker()
        ActionHub:RefreshWidget()
    end)
    tab.hideCombatToggle = hideCombatCheck

    local hideCombatLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hideCombatLabel:SetPoint("LEFT", hideCombatCheck, "RIGHT", 4, 0)
    hideCombatLabel:SetText(L["AH_HIDE_IN_COMBAT"] or "Hide In Combat")
    hideCombatLabel:SetTextColor(0.9, 0.9, 0.9)

    local keepLogoCheck = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    keepLogoCheck:SetPoint("LEFT", hideCombatLabel, "RIGHT", 28, 0)
    keepLogoCheck:SetSize(22, 22)
    keepLogoCheck:SetChecked(GetDB().showLogoWhenLocked)
    keepLogoCheck:SetScript("OnClick", function(self)
        GetDB().showLogoWhenLocked = self:GetChecked()
        ActionHub:RefreshWidget()
    end)
    tab.keepLogoToggle = keepLogoCheck

    local keepLogoLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keepLogoLabel:SetPoint("LEFT", keepLogoCheck, "RIGHT", 4, 0)
    keepLogoLabel:SetText(L["AH_SHOW_LOGO"] or "Show Logo")
    keepLogoLabel:SetTextColor(0.9, 0.9, 0.9)

    -- On Screen toggle
    local onScreen = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    onScreen:SetPoint("LEFT", keepLogoLabel, "RIGHT", 28, 0)
    onScreen:SetSize(22, 22)
    onScreen:SetChecked(GetDB().onScreen)
    onScreen:SetScript("OnClick", function(self)
        GetDB().onScreen = self:GetChecked()
        ActionHub:RefreshWidget()
    end)
    tab.onScreenToggle = onScreen

    local onScreenLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    onScreenLabel:SetPoint("LEFT", onScreen, "RIGHT", 4, 0)
    onScreenLabel:SetText(L["AH_ON_SCREEN"] or "On Screen")
    onScreenLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Unlock Position toggle
    local unlockPos = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    unlockPos:SetPoint("LEFT", onScreenLabel, "RIGHT", 15, 0)
    unlockPos:SetSize(22, 22)
    unlockPos:SetChecked(GetDB().widgetUnlocked)
    unlockPos:SetScript("OnClick", function(self)
        GetDB().widgetUnlocked = self:GetChecked()
        ActionHub:RefreshWidget()
    end)
    tab.unlockToggle = unlockPos

    local unlockLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unlockLabel:SetPoint("LEFT", unlockPos, "RIGHT", 4, 0)
    unlockLabel:SetText(L["AH_UNLOCK_POSITION"] or "Unlock Position")
    unlockLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Global cooldown toggle.  Off by default: a hub full of toys otherwise
    -- spins its swirl on every unrelated cast, which reads as noise.
    local gcdCheck = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    gcdCheck:SetPoint("LEFT", unlockLabel, "RIGHT", 20, 0)
    gcdCheck:SetSize(22, 22)
    gcdCheck:SetChecked(GetDB().showGlobalCooldown == true)

    local gcdLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gcdLabel:SetPoint("LEFT", gcdCheck, "RIGHT", 4, 0)
    gcdLabel:SetText("Show Global Cooldown")
    gcdLabel:SetTextColor(0.9, 0.9, 0.9)

    gcdCheck:SetScript("OnClick", function(self)
        GetDB().showGlobalCooldown = self:GetChecked() and true or false
        ActionHub:UpdateWidgetCooldowns()
    end)
    gcdCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Show Global Cooldown", 1, 0.82, 0)
        GameTooltip:AddLine("Off: nodes only sweep for their own cooldown.", 1, 1, 1, true)
        GameTooltip:AddLine("On: they also sweep for the 1.5s global cooldown.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    gcdCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.gcdCheck = gcdCheck


    -- Quadrant dropdown
    local quadLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quadLabel:SetPoint("TOPLEFT", controls, "TOPLEFT", 4, -40)
    quadLabel:SetText(L["AH_SIDE"] or "Side:")
    quadLabel:SetTextColor(1, 0.82, 0)

    local quadBtn = CreateFrame("DropdownButton", nil, controls, "WowStyle1DropdownTemplate")
    quadBtn:SetPoint("LEFT", quadLabel, "RIGHT", 6, 0)
    quadBtn:SetSize(130, 26)
    tab.quadBtn = quadBtn

    local quads = {
        { key = "bottom-right", name = L["QUAD_BOTTOM_RIGHT"] or "Bottom Right" },
        { key = "bottom-left",  name = L["QUAD_BOTTOM_LEFT"] or "Bottom Left" },
        { key = "top-right",    name = L["QUAD_TOP_RIGHT"] or "Top Right" },
        { key = "top-left",     name = L["QUAD_TOP_LEFT"] or "Top Left" },
    }

    local function IsQuadSelected(key)
        return ActionHub:GetQuadrant() == key
    end

    quadBtn:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(quads) do
            rootDescription:CreateRadio(
                entry.name,
                function() return IsQuadSelected(entry.key) end,
                function()
                    ActionHub:SetQuadrant(entry.key)
                    quadBtn:OverrideText(entry.name)
                end,
                entry.key
            )
        end
    end)

    for _, entry in ipairs(quads) do
        if entry.key == ActionHub:GetQuadrant() then
            quadBtn:OverrideText(entry.name)
            break
        end
    end

    -- Style dropdown
    local styleLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    styleLabel:SetPoint("LEFT", quadBtn, "RIGHT", 20, 0)
    styleLabel:SetText(L["AH_STYLE"] or "Style:")
    styleLabel:SetTextColor(1, 0.82, 0)

    local styleBtn = CreateFrame("DropdownButton", nil, controls, "WowStyle1DropdownTemplate")
    styleBtn:SetPoint("LEFT", styleLabel, "RIGHT", 6, 0)
    styleBtn:SetSize(110, 26)
    tab.styleBtn = styleBtn

    local styles = {
        { key = "square", name = L["STYLE_SQUARES"] or "Squares" },
        { key = "ring",   name = L["STYLE_RINGS"] or "Rings" },
    }

    local function IsStyleSelected(key)
        return (GetDB().style or "square") == key
    end

    styleBtn:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(styles) do
            rootDescription:CreateRadio(
                entry.name,
                function() return IsStyleSelected(entry.key) end,
                function()
                    GetDB().style = entry.key
                    styleBtn:OverrideText(entry.name)
                    ActionHub:RefreshWidget()
                    ActionHub:RefreshTab()
                end,
                entry.key
            )
        end
    end)

    for _, entry in ipairs(styles) do
        if entry.key == (GetDB().style or "square") then
            styleBtn:OverrideText(entry.name)
            break
        end
    end



    -- Preview container (Expanded width for wide sideways movement)
    local ringContainer = CreateFrame("Frame", nil, tab)
    ringContainer:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 16, 32)
    ringContainer:SetSize(534, 430)
    tab.ringContainer = ringContainer

    local previewLogoFrame = CreateFrame("Frame", nil, ringContainer, "BackdropTemplate")
    previewLogoFrame:SetSize(48, 48)
    previewLogoFrame:SetFrameLevel(ringContainer:GetFrameLevel() + 20)
    previewLogoFrame:SetMovable(true)
    previewLogoFrame:EnableMouse(true)
    previewLogoFrame:RegisterForDrag("LeftButton")
    
    local previewLogoTex = previewLogoFrame:CreateTexture(nil, "OVERLAY")
    previewLogoTex:SetAllPoints()
    previewLogoTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")
    
    previewLogoFrame:SetScript("OnDragStart", function(self)
        if ActionHub.pickerDialog and ActionHub.pickerDialog.moveNodeMode then
            local activeDB = ActionHub:GetActiveHubDB()
            if not activeDB then return end
            
            local scale = UIParent:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            self.dragStartCursorX = cursorX / scale
            self.dragStartCursorY = cursorY / scale
            self.dragStartOffsetX = activeDB.logoOffsetX or 0
            self.dragStartOffsetY = activeDB.logoOffsetY or 0
            
            self:SetScript("OnUpdate", function(f)
                local currentX, currentY = GetCursorPosition()
                currentX = currentX / scale
                currentY = currentY / scale
                
                local deltaX = currentX - f.dragStartCursorX
                local deltaY = currentY - f.dragStartCursorY
                local newOffsetX = math.floor((f.dragStartOffsetX + deltaX) + 0.5)
                local newOffsetY = math.floor((f.dragStartOffsetY + deltaY) + 0.5)
                
                local cx, cy = 256, -204
                local rawX = cx + newOffsetX
                local rawY = cy + newOffsetY
                rawX, rawY = ActionHub:SnapMovePosition(ringContainer, rawX, rawY, self)
                newOffsetX = rawX - cx
                newOffsetY = rawY - cy
                
                activeDB.logoOffsetX = newOffsetX
                activeDB.logoOffsetY = newOffsetY
                
                f:ClearAllPoints()
                f:SetPoint("CENTER", ringContainer, "TOPLEFT", cx + newOffsetX, cy + newOffsetY)
            end)
        end
    end)
    previewLogoFrame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        ActionHub:RefreshWidget()
        ActionHub:RefreshTab()
    end)
    previewLogoFrame:Hide()
    tab.previewLogo = previewLogoFrame

    local moveOverlay = CreateFrame("Frame", nil, ringContainer, "BackdropTemplate")
    moveOverlay:SetAllPoints(ringContainer)
    moveOverlay:SetFrameLevel(ringContainer:GetFrameLevel() + 1)
    moveOverlay:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    moveOverlay:SetBackdropColor(0.1, 0.35, 0.9, 0.15)
    moveOverlay:SetBackdropBorderColor(0.3, 0.7, 1, 0.85)
    moveOverlay:Hide()
    moveOverlay:EnableMouse(false)
    tab.moveOverlay = moveOverlay

    local moveOverlayText = moveOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    moveOverlayText:SetPoint("TOP", moveOverlay, "TOP", 0, -10)
    moveOverlayText:SetText(L["AH_MOVE_MODE_DRAG"] or "Move Mode: Drag selected node")
    moveOverlayText:SetTextColor(0.7, 0.9, 1, 1)
    tab.moveOverlayText = moveOverlayText

    -- Two vertical sliders (placed OUTSIDE the blue move zone, on its right) that
    -- control horizontal / vertical snap spacing. Changing one also rescales the
    -- already-placed nodes on that axis so a connected block moves together.
    local function MakePreviewSpacingSlider(labelText, axisKey, minVal, maxVal, xOffset)
        local slider = CreateFrame("Slider", nil, moveOverlay, "OptionsSliderTemplate")
        slider:SetOrientation("VERTICAL")
        slider:SetSize(22, 170)
        slider:SetPoint("LEFT", moveOverlay, "RIGHT", xOffset, -6)
        slider:SetMinMaxValues(minVal or 24, maxVal or 120)
        slider:SetValueStep(2)
        slider:SetObeyStepOnDrag(true)
        if slider.Low then slider.Low:SetText("") end
        if slider.High then slider.High:SetText("") end
        if slider.Text then slider.Text:SetText("") end

        local lbl = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("BOTTOM", slider, "TOP", 0, 4)
        lbl:SetText(labelText)
        lbl:SetTextColor(1, 0.9, 0.4)
        local valTxt = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valTxt:SetPoint("TOP", slider, "BOTTOM", 0, -3)

        slider.axisKey = axisKey
        slider.posKey = posKey
        slider.valTxt = valTxt
        slider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            valTxt:SetText(value)
            if self.isSyncing then return end
            local db = ActionHub:GetActiveHubDB()
            if db then db[axisKey] = value end
            -- Only the grid dots change; placed nodes stay where they are.
            ActionHub:UpdatePreviewMoveGrid(tab)
        end)
        return slider
    end

    -- V first (closer to the panel), then H to its right — matching the drawing.
    tab.vSpacingSlider = MakePreviewSpacingSlider("V", "snapStepY", 24, 120, 30)
    tab.hSpacingSlider = MakePreviewSpacingSlider("H", "snapStepX", 24, 120, 60)
    tab.magneticGapSlider = MakePreviewSpacingSlider("Gap", "magneticGap", -10, 10, 45)


    tab.SyncSpacingSliders = function()
        local db = ActionHub:GetActiveHubDB()
        local base = ActionHub:GetDefaultSnapStep()
        local sx = (db and db.snapStepX) or base
        local sy = (db and db.snapStepY) or base
        local gap = (db and db.magneticGap) or 8
        for slider, v in pairs({ [tab.hSpacingSlider] = sx, [tab.vSpacingSlider] = sy }) do
            slider.isSyncing = true
            slider:SetValue(math.min(120, math.max(24, v)))
            slider.isSyncing = false
            slider._appliedValue = v
            slider.valTxt:SetText(math.floor(v + 0.5))
        end
        if tab.magneticGapSlider then
            tab.magneticGapSlider.isSyncing = true
            tab.magneticGapSlider:SetValue(math.min(10, math.max(-10, gap)))
            tab.magneticGapSlider.isSyncing = false
            tab.magneticGapSlider._appliedValue = gap
            tab.magneticGapSlider.valTxt:SetText(math.floor(gap + 0.5))
        end
    end

    tab.ringButtons = {}

    local sideControls = CreateFrame("Frame", nil, tab)
    sideControls:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", insetLeft, insetBottom + 15)
    sideControls:SetSize(420, 24)
    tab.sideControls = sideControls

    local mainSideBtn = CreateFrame("Button", nil, sideControls, "UIPanelButtonTemplate")
    mainSideBtn:SetSize(92, 24)
    mainSideBtn:SetPoint("LEFT", sideControls, "LEFT", 0, 0)
    mainSideBtn:SetText(L["AH_MAIN_SIDE"] or "Main Side")
    mainSideBtn:SetScript("OnClick", function()
        ActionHub:SetEditedSide("primary")
        ActionHub:RefreshTab()
    end)
    tab.mainSideBtn = mainSideBtn

    local dualSideBtn = CreateFrame("Button", nil, sideControls, "UIPanelButtonTemplate")
    dualSideBtn:SetSize(92, 24)
    dualSideBtn:SetPoint("LEFT", mainSideBtn, "RIGHT", 6, 0)
    dualSideBtn:SetText(L["AH_DUAL_SIDE"] or "Dual Side")
    dualSideBtn:SetScript("OnClick", function()
        ActionHub:SetEditedSide("secondary")
        ActionHub:RefreshTab()
    end)
    tab.dualSideBtn = dualSideBtn

    local sideInfo = sideControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sideInfo:SetPoint("LEFT", dualSideBtn, "RIGHT", 8, 0)
    sideInfo:SetTextColor(0.8, 0.8, 0.8)
    tab.sideInfo = sideInfo

    local dualSideCheck = CreateFrame("CheckButton", nil, sideControls, "UICheckButtonTemplate")
    dualSideCheck:SetPoint("LEFT", sideInfo, "RIGHT", 20, 0)
    dualSideCheck:SetSize(22, 22)
    dualSideCheck:SetChecked(GetDB().dualSideEnabled)
    dualSideCheck:SetScript("OnClick", function(self)
        GetDB().dualSideEnabled = self:GetChecked()
        if not self:GetChecked() and ActionHub:GetEditedSide() == "secondary" then
            ActionHub:SetEditedSide("primary")
        end
        ActionHub:RefreshWidget()
        ActionHub:RefreshTab()
    end)
    tab.dualSideCheck = dualSideCheck

    local dualSideLabel = sideControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dualSideLabel:SetPoint("LEFT", dualSideCheck, "RIGHT", 4, 0)
    dualSideLabel:SetText(L["AH_ENABLE_DUAL_SIDE"] or "Enable Dual Side")
    dualSideLabel:SetTextColor(0.9, 0.9, 0.9)

    local dualLayoutLabel = sideControls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dualLayoutLabel:SetPoint("LEFT", dualSideLabel, "RIGHT", 18, 0)
    dualLayoutLabel:SetText(L["AH_DUAL_LAYOUT"] or "Dual Layout:")
    dualLayoutLabel:SetTextColor(1, 0.82, 0)
    tab.dualLayoutLabel = dualLayoutLabel

    local dualLayoutBtn = CreateFrame("DropdownButton", nil, sideControls, "WowStyle1DropdownTemplate")
    dualLayoutBtn:SetPoint("LEFT", dualLayoutLabel, "RIGHT", 6, 0)
    dualLayoutBtn:SetSize(120, 26)
    tab.dualLayoutBtn = dualLayoutBtn

    local dualLayouts = {
        { key = "horizontal", name = L["LAYOUT_HORIZONTAL"] or "Horizontal" },
        { key = "vertical", name = L["LAYOUT_VERTICAL"] or "Vertical" },
    }

    dualLayoutBtn:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(dualLayouts) do
            rootDescription:CreateRadio(
                entry.name,
                function()
                    return (GetDB().dualSideLayout or "horizontal") == entry.key
                end,
                function()
                    GetDB().dualSideLayout = entry.key
                    dualLayoutBtn:OverrideText(entry.name)
                    ActionHub:RefreshWidget()
                    ActionHub:RefreshTab()
                end,
                entry.key
            )
        end
    end)

    for _, entry in ipairs(dualLayouts) do
        if entry.key == (GetDB().dualSideLayout or "horizontal") then
            dualLayoutBtn:OverrideText(entry.name)
            break
        end
    end

    -- Limit Nodes toggle
    local limitCheck = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    limitCheck:SetPoint("LEFT", styleBtn, "RIGHT", 20, 0)
    limitCheck:SetSize(22, 22)
    local ldb = GetDB()
    if ldb.limitNodes == nil then ldb.limitNodes = true end
    limitCheck:SetChecked(ldb.limitNodes)
    tab.limitCheck = limitCheck

    local limitLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    limitLabel:SetPoint("LEFT", limitCheck, "RIGHT", 4, 0)
    limitLabel:SetText(L["AH_LIMIT_NODES_LABEL"] or "Limit Nodes (14 main / 11 dual)")
    limitLabel:SetTextColor(0.9, 0.9, 0.9)


    -- Share only the hub currently being edited, not the whole collection.
    local shareHubBtn = CreateFrame("Button", nil, controls)
    shareHubBtn:SetPoint("LEFT", limitLabel, "RIGHT", 16, 0)
    shareHubBtn:SetSize(20, 20)
    shareHubBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    shareHubBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    shareHubBtn:SetScript("OnClick", function()
        local Share = OxedHub.Share
        if not Share then
            print("|cffff0000Oxed Hub:|r Sharing module unavailable.")
            return
        end
        local idx = ActionHub:GetActiveHubIndex()
        local hub = ActionHub:GetActiveHubDB()
        local label = (type(hub) == "table" and hub.name) or ("Hub " .. tostring(idx))
        Share:ShowChannelPicker("hubs", { hubIndex = idx }, label)
    end)
    shareHubBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BTN_SHARE"] or "Share", 1, 0.82, 0)
        GameTooltip:AddLine("Share only the hub you are editing.", 1, 1, 1, true)
        GameTooltip:AddLine("Others with Oxed Hub can click to import it.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    shareHubBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.shareHubBtn = shareHubBtn

    -- Warning text for limit removal
    local warningText = L["AH_WARNING_LIMIT"] or "By removing the node limit you accept that there might be interface overlays and issues since the Action Hub may not be stable over 14 nodes.\n\nAre you sure you want to continue?"

    limitCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if checked then
            -- Re-enabling the limit, just save
            GetDB().limitNodes = true
            ActionHub:RefreshTab()
        else
            -- Unchecking: revert checkbox and show custom popup
            self:SetChecked(true)
            ShowConfirmDialog(warningText, function()
                GetDB().limitNodes = false
                if tab.limitCheck then tab.limitCheck:SetChecked(false) end
                ActionHub:RefreshTab()
            end, function()
                if tab.limitCheck then tab.limitCheck:SetChecked(true) end
            end)
        end
    end)

    -- Node Management Row (Compact +, -, Clear Node, Clear All)
    local addBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    addBtn:SetSize(30, 26)
    addBtn:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", insetLeft, insetBottom - 11)
    addBtn:SetText("+")
    addBtn:GetFontString():SetTextColor(0.3, 1, 0.3)
    addBtn:SetScript("OnClick", function()
        local db = GetDB()
        local slots = GetEditSlots()
        local maxNodes = GetEffectiveNodeLimit(db, ActionHub:GetEditedSide())
        if #slots >= maxNodes then return end

        local moveMode = ActionHub.pickerDialog and ActionHub.pickerDialog.moveNodeMode
        local hasMoved = false
        for _, s in ipairs(slots) do
            if s and (s.nodePositionX ~= nil or s.nodePositionY ~= nil) then
                hasMoved = true
                break
            end
        end

        local shouldPreserve = (moveMode or hasMoved) and tab.ringButtons
        local absolutePositions = {}
        
        -- If in move mode or custom layout exists, capture current absolute positions so we can compensate for layout shift
        if shouldPreserve then
            for _, btn in ipairs(tab.ringButtons) do
                if btn:IsShown() and btn.slotData and btn.slotSide == ActionHub:GetEditedSide() then
                    absolutePositions[btn.slotData] = {
                        x = btn.basePreviewX + (btn.slotData.nodePositionX or 0),
                        y = btn.basePreviewY + (btn.slotData.nodePositionY or 0)
                    }
                end
            end
        end

        local newNode = { type = nil, id = nil }
        table.insert(slots, newNode)
        ActionHub:RefreshTab()

        if shouldPreserve then
            local prevLastNode = #slots > 1 and slots[#slots - 1] or nil
            for _, btn in ipairs(tab.ringButtons) do
                if btn:IsShown() and btn.slotData and btn.slotSide == ActionHub:GetEditedSide() then
                    if absolutePositions[btn.slotData] then
                        local old = absolutePositions[btn.slotData]
                        btn.slotData.nodePositionX = old.x - btn.basePreviewX
                        btn.slotData.nodePositionY = old.y - btn.basePreviewY
                    elseif btn.slotData == newNode and prevLastNode and absolutePositions[prevLastNode] then
                        -- Spawn newly added node next to the previously last node
                        local old = absolutePositions[prevLastNode]
                        btn.slotData.nodePositionX = (old.x + 48) - btn.basePreviewX
                        btn.slotData.nodePositionY = old.y - btn.basePreviewY
                    end
                end
            end
            ActionHub:RefreshTab()
            ActionHub:RefreshWidget()
        end
    end)
    tab.addBtn = addBtn

    local removeBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    removeBtn:SetSize(30, 26)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 4, 0)
    removeBtn:SetText("-")
    removeBtn:GetFontString():SetTextColor(1, 0.3, 0.3)
    removeBtn:SetScript("OnClick", function()
        local slots = GetEditSlots()
        if #slots > 0 then
            local moveMode = ActionHub.pickerDialog and ActionHub.pickerDialog.moveNodeMode
            local hasMoved = false
            for _, s in ipairs(slots) do
                if s and (s.nodePositionX ~= nil or s.nodePositionY ~= nil) then
                    hasMoved = true
                    break
                end
            end

            local shouldPreserve = (moveMode or hasMoved) and tab.ringButtons
            local absolutePositions = {}
            
            if shouldPreserve then
                for _, btn in ipairs(tab.ringButtons) do
                    if btn:IsShown() and btn.slotData and btn.slotSide == ActionHub:GetEditedSide() then
                        absolutePositions[btn.slotData] = {
                            x = btn.basePreviewX + (btn.slotData.nodePositionX or 0),
                            y = btn.basePreviewY + (btn.slotData.nodePositionY or 0)
                        }
                    end
                end
            end

            table.remove(slots, #slots)
            
            if ActionHub.pickerDialog and ActionHub.pickerDialog.slotSide == ActionHub:GetEditedSide() and ActionHub.pickerDialog.slotIndex and ActionHub.pickerDialog.slotIndex > #slots then
                ActionHub:ShowSlotPicker(nil)
            end
            
            ActionHub:RefreshTab()

            if shouldPreserve then
                for _, btn in ipairs(tab.ringButtons) do
                    if btn:IsShown() and btn.slotData and btn.slotSide == ActionHub:GetEditedSide() then
                        if absolutePositions[btn.slotData] then
                            local old = absolutePositions[btn.slotData]
                            btn.slotData.nodePositionX = old.x - btn.basePreviewX
                            btn.slotData.nodePositionY = old.y - btn.basePreviewY
                        end
                    end
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshWidget()
            end
        end
    end)
    tab.removeBtn = removeBtn

    local nodeCount = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nodeCount:SetPoint("LEFT", removeBtn, "RIGHT", 6, 0)
    nodeCount:SetTextColor(0.8, 0.8, 0.8)
    tab.nodeCount = nodeCount

    local clearNodeBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    clearNodeBtn:SetSize(90, 26)
    clearNodeBtn:SetPoint("LEFT", nodeCount, "RIGHT", 10, 0)
    clearNodeBtn:SetText(L["AH_CLEAR_NODE"] or "Clear Node")
    clearNodeBtn:SetScript("OnClick", function()
        if ActionHub.pickerDialog and ActionHub.pickerDialog.slotIndex then
            local slots = ActionHub:GetSlotsForSide(GetDB(), ActionHub.pickerDialog.slotSide)
            local s = slots and slots[ActionHub.pickerDialog.slotIndex]
            if s then
                s.type = nil
                s.id = nil
                s.assignmentMode = nil
            end
            ActionHub:RefreshPickerList()
            ActionHub:RefreshTab()
        end
    end)
    tab.clearNodeBtn = clearNodeBtn

    local clearBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    clearBtn:SetSize(90, 26)
    clearBtn:SetPoint("LEFT", clearNodeBtn, "RIGHT", 8, 0)
    clearBtn:SetText(L["AH_CLEAR_ALL"] or "Clear All")
    clearBtn:SetScript("OnClick", function()
        if ActionHub:GetEditedSide() == "secondary" then
            GetDB().secondarySlots = {}
        else
            GetDB().slots = {}
        end
        ActionHub:ShowSlotPicker(nil)
        ActionHub:RefreshTab()
    end)
    tab.clearBtn = clearBtn

    local moveBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    moveBtn:SetSize(70, 26)
    moveBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    moveBtn:SetText(L["AH_MOVE"] or "Move")
    moveBtn:SetScript("OnClick", function(self)
        if ActionHub.pickerDialog and ActionHub.pickerDialog.slotIndex then
            ActionHub.pickerDialog.moveNodeMode = not ActionHub.pickerDialog.moveNodeMode
            if ActionHub.pickerDialog.moveNodeMode then
                if not ActionHub.moveGridType or ActionHub.moveGridType == "off" then
                    ActionHub.moveGridType = "magnetic"
                    ActionHub.moveSnap = true
                end
                if tab.UpdateGridText then tab.UpdateGridText() end
            end
            self:SetText(ActionHub.pickerDialog.moveNodeMode and (L["AH_MOVING"] or "Moving") or (L["AH_MOVE"] or "Move"))
            ActionHub:RefreshTab()
        end
    end)
    tab.moveBtn = moveBtn

    -- Minimize: hide the addon window and drag nodes directly on screen.
    -- Only visible while Move mode is active.
    local minimizeBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    minimizeBtn:SetSize(90, 26)
    minimizeBtn:SetPoint("LEFT", moveBtn, "RIGHT", 6, 0)
    minimizeBtn:SetText(L["AH_MINIMIZE"] or "Minimize")
    minimizeBtn:SetScript("OnClick", function()
        ActionHub:EnterMinimizedMoveMode()
    end)
    minimizeBtn:Hide()
    tab.minimizeBtn = minimizeBtn

    -- Default grid type to Magnetic with Snap enabled
    if not ActionHub.moveGridType then
        ActionHub.moveGridType = "magnetic"
        ActionHub.moveSnap = true
    end

    local gridMenuBtn = CreateFrame("DropdownButton", nil, tab, "WowStyle1DropdownTemplate")
    gridMenuBtn:SetPoint("LEFT", minimizeBtn, "RIGHT", 6, 0)
    gridMenuBtn:SetSize(110, 26)
    gridMenuBtn:Hide()
    
    local function UpdateGridText()
        local t = ActionHub.moveGridType or "magnetic"
        local gridText = t == "square" and (L["GRID_SQUARE"] or "Square") or 
                         t == "radial" and (L["GRID_RADIAL"] or "Radial") or 
                         t == "magnetic" and (L["GRID_MAGNETIC"] or "Magnetic") or 
                         (L["GRID_OFF"] or "Off")
        gridMenuBtn:OverrideText(string.format(L["AH_GRID_LABEL"] or "Grid: %s", gridText))
        
        if tab.vSpacingSlider then
            if t == "square" or t == "radial" then
                tab.vSpacingSlider:Show()
                tab.hSpacingSlider:Show()
            else
                tab.vSpacingSlider:Hide()
                tab.hSpacingSlider:Hide()
            end
        end
        
        if tab.magneticGapSlider then
            if t == "magnetic" then
                tab.magneticGapSlider:Show()
            else
                tab.magneticGapSlider:Hide()
            end
        end
    end
    tab.UpdateGridText = UpdateGridText
    UpdateGridText()
    
    gridMenuBtn:SetupMenu(function(dropdown, rootDescription)
        local titleText = L["AH_GRID_LABEL"] and string.gsub(L["AH_GRID_LABEL"], ":? ?%%s", "") or "Grid"
        rootDescription:CreateTitle(titleText)
        
        local function SelectGrid(gridType)
            ActionHub.moveGridType = gridType
            if gridType ~= "off" then
                ActionHub.moveSnap = true
            end
            UpdateGridText()
            ActionHub:UpdatePreviewMoveGrid(tab)
            ActionHub:UpdateMoveGrid()
        end
        
        rootDescription:CreateRadio(L["GRID_OFF"] or "Off", function() return (ActionHub.moveGridType or "off") == "off" end, function() SelectGrid("off") end)
        rootDescription:CreateRadio(L["GRID_SQUARE"] or "Square", function() return (ActionHub.moveGridType or "off") == "square" end, function() SelectGrid("square") end)
        rootDescription:CreateRadio(L["GRID_RADIAL"] or "Radial", function() return (ActionHub.moveGridType or "off") == "radial" end, function() SelectGrid("radial") end)
        rootDescription:CreateRadio(L["GRID_MAGNETIC"] or "Magnetic", function() return (ActionHub.moveGridType or "off") == "magnetic" end, function() SelectGrid("magnetic") end)
        rootDescription:CreateDivider()
        
        local snapTitle = L["AH_SNAP_LABEL"] and string.gsub(L["AH_SNAP_LABEL"], ":? ?%%s", "") or "Snap"
        rootDescription:CreateCheckbox(snapTitle, function() return ActionHub.moveSnap end, function() ActionHub.moveSnap = not ActionHub.moveSnap end)
    end)
    tab.gridMenuBtn = gridMenuBtn

    tab:Hide()
    contentArea.ActionHub = tab
    self.tab = tab
    
    return tab
end

-- Popup to rename a hub. Stored in hubs[idx].name; empty name resets to "Hub N".
function ActionHub:ShowRenameHubDialog(hubIndex)
    local hubs = self:GetHubs()
    local hub = hubs and hubs[hubIndex]
    if not hub then return end
    local current = hub.name
    if not current or current:match("^Hub %d+$") then current = "Hub " .. hubIndex end

    StaticPopupDialogs["OXEDHUB_RENAME_HUB"] = {
        text = "Rename this hub to:",
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 24,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if eb then eb:SetText(current); eb:HighlightText(); eb:SetFocus() end
        end,
        EditBoxOnEnterPressed = function(self)
            local name = (self:GetText() or ""):gsub("^%s*(.-)%s*$", "%1")
            hubs[hubIndex].name = (name ~= "" and name) or nil
            ActionHub:RefreshTab()
            local p = self:GetParent()
            if p and p.Hide then p:Hide() end
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local name = ((eb and eb:GetText()) or ""):gsub("^%s*(.-)%s*$", "%1")
            hubs[hubIndex].name = (name ~= "" and name) or nil
            ActionHub:RefreshTab()
        end,
    }
    StaticPopup_Show("OXEDHUB_RENAME_HUB")
end

function ActionHub:RefreshTab()
    local tab = self.tab
    if not tab then return end

    -- Build hub selector tabs
    local hubRow = tab.hubRow
    if hubRow then
        -- Clear old hub buttons
        if tab.hubBtns then
            for _, b in ipairs(tab.hubBtns) do b:Hide() end
        end
        if tab.hubAddBtn then tab.hubAddBtn:Hide() end
        if tab.hubRemoveBtn then tab.hubRemoveBtn:Hide() end
        tab.hubBtns = {}

        local hubs = self:GetHubs()
        local activeIdx = self:GetActiveHubIndex()
        local xOffset = 0

        for i = 1, #hubs do
            local hb = CreateFrame("Button", nil, hubRow, "UIPanelButtonTemplate")
            hb:SetSize(70, 24)
            hb:SetPoint("LEFT", hubRow, "LEFT", xOffset, 0)
            local hubName = hubs[i].name
            if not hubName or string.match(hubName, "^Hub %d+$") then
                hubName = "Hub " .. i
            end
            hb:SetText(hubName)
            hb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local function ShowHubTooltip(owner)
                GameTooltip:SetOwner(owner, "ANCHOR_TOP")
                GameTooltip:SetText(hubName, 1, 0.82, 0)
                GameTooltip:AddLine("|cff00ff00Left-click:|r switch  |cff00ff00Right-click:|r rename", 1, 1, 1)
                GameTooltip:Show()
            end

            if i == activeIdx then
                -- Active hub: keep the original grayed/disabled look (only Disable()
                -- gives that on this 3-slice button). A disabled button can't be
                -- clicked, so overlay a transparent right-click catcher for rename.
                hb:GetFontString():SetTextColor(1, 0.82, 0)
                hb:Disable()

                local rc = CreateFrame("Button", nil, hb)
                rc:SetAllPoints(hb)
                rc:SetFrameLevel(hb:GetFrameLevel() + 5)
                rc:RegisterForClicks("RightButtonUp")
                rc:SetScript("OnClick", function() ActionHub:ShowRenameHubDialog(i) end)
                rc:SetScript("OnEnter", function(self) ShowHubTooltip(self) end)
                rc:SetScript("OnLeave", function() GameTooltip:Hide() end)
            else
                hb:GetFontString():SetTextColor(1, 1, 1)
                hb:Enable()
                hb:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        ActionHub:ShowRenameHubDialog(i)
                        return
                    end
                    if self.pickerDialog then self.pickerDialog:Hide() end
                    self:SetActiveHubIndex(i)
                    self:RefreshTab()
                end)
                hb:SetScript("OnEnter", function(self) ShowHubTooltip(self) end)
                hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end

            tab.hubBtns[i] = hb
            xOffset = xOffset + 74
        end

        -- "+" button to add a new hub
        local addHub = CreateFrame("Button", nil, hubRow, "UIPanelButtonTemplate")
        addHub:SetSize(26, 24)
        addHub:SetPoint("LEFT", hubRow, "LEFT", xOffset, 0)
        addHub:SetText("+")
        addHub:GetFontString():SetTextColor(0.3, 1, 0.3)
        addHub:SetScript("OnClick", function()
            local hubs = self:GetHubs()
            local newIdx = #hubs + 1
            hubs[newIdx] = CreateDefaultHubData(newIdx)
            hubs[newIdx].name = nil
            if self.pickerDialog then self.pickerDialog:Hide() end
            self:SetActiveHubIndex(newIdx)
            self:CreateWidget(newIdx)
            self:RefreshAllWidgets()
            self:RefreshTab()
        end)
        tab.hubAddBtn = addHub
        xOffset = xOffset + 30

        -- "-" button to delete current hub (only if more than 1)
        if #hubs > 1 then
            local removeHub = CreateFrame("Button", nil, hubRow, "UIPanelButtonTemplate")
            removeHub:SetSize(26, 24)
            removeHub:SetPoint("LEFT", hubRow, "LEFT", xOffset, 0)
            removeHub:SetText("-")
            removeHub:GetFontString():SetTextColor(1, 0.3, 0.3)
            removeHub:SetScript("OnClick", function()
                local hubs = self:GetHubs()
                local idx = self:GetActiveHubIndex()
                -- Hide and remove the widget
                if self.widgets and self.widgets[idx] then
                    self.widgets[idx]:Hide()
                    table.remove(self.widgets, idx)
                end
                table.remove(hubs, idx)
                -- Adjust active index
                if idx > #hubs then idx = #hubs end
                if idx < 1 then idx = 1 end
                if self.pickerDialog then self.pickerDialog:Hide() end
                self:SetActiveHubIndex(idx)
                self:RefreshAllWidgets()
                self:RefreshTab()
            end)
            tab.hubRemoveBtn = removeHub
        end
    end

    local db = self:GetActiveHubDB()
    TrimSideToLimit(db, "primary")
    TrimSideToLimit(db, "secondary")
    if not db.dualSideEnabled and self:GetEditedSide() == "secondary" then
        self:SetEditedSide("primary")
    end
    local slots = self:GetSlotsForSide(db, "primary")
    local secondarySlots = self:GetSlotsForSide(db, "secondary")
    local activeSlots = self:GetSlotsForSide(db, self:GetEditedSide())
    local quadrant = self:GetQuadrant()
    local maxSlots = #activeSlots

    -- Update control states to match active hub
    if tab.onScreenToggle then tab.onScreenToggle:SetChecked(db.onScreen) end
    if tab.unlockToggle then tab.unlockToggle:SetChecked(db.widgetUnlocked) end
    if tab.keepLogoToggle then tab.keepLogoToggle:SetChecked(db.showLogoWhenLocked) end
    if tab.hideCombatToggle then tab.hideCombatToggle:SetChecked(db.hideInCombat) end
    if tab.dualSideCheck then tab.dualSideCheck:SetChecked(db.dualSideEnabled) end
    if tab.showTooltipToggle then tab.showTooltipToggle:SetChecked(db.showTooltip ~= false) end

    local dualLayoutNames = {
        horizontal = L["LAYOUT_HORIZONTAL"] or "Horizontal",
        vertical = L["LAYOUT_VERTICAL"] or "Vertical"
    }
    if tab.dualLayoutBtn then
        tab.dualLayoutBtn:OverrideText(dualLayoutNames[db.dualSideLayout or "horizontal"] or "Horizontal")
        tab.dualLayoutBtn:SetShown(db.dualSideEnabled)
    end
    if tab.dualLayoutLabel then
        tab.dualLayoutLabel:SetShown(db.dualSideEnabled)
    end
    -- Update quadrant dropdown text
    local quadNames = {
        ["bottom-right"] = L["QUAD_BOTTOM_RIGHT"] or "Bottom Right",
        ["bottom-left"] = L["QUAD_BOTTOM_LEFT"] or "Bottom Left",
        ["top-right"] = L["QUAD_TOP_RIGHT"] or "Top Right",
        ["top-left"] = L["QUAD_TOP_LEFT"] or "Top Left"
    }
    if tab.quadBtn then tab.quadBtn:OverrideText(quadNames[quadrant] or "Bottom Right") end

    -- Disable Side dropdown if any custom node positions exist
    local hasCustomPositions = false
    if db.slots then
        for _, s in ipairs(db.slots) do
            if s and (s.nodePositionX ~= nil or s.nodePositionY ~= nil) then
                hasCustomPositions = true
                break
            end
        end
    end
    if not hasCustomPositions and db.secondarySlots then
        for _, s in ipairs(db.secondarySlots) do
            if s and (s.nodePositionX ~= nil or s.nodePositionY ~= nil) then
                hasCustomPositions = true
                break
            end
        end
    end

    if tab.quadBtn then
        tab.quadBtn:SetEnabled(not hasCustomPositions)
        tab.quadBtn:SetAlpha(hasCustomPositions and 0.5 or 1.0)
    end
    if tab.dualLayoutBtn then
        tab.dualLayoutBtn:SetEnabled(not hasCustomPositions)
        tab.dualLayoutBtn:SetAlpha(hasCustomPositions and 0.5 or 1.0)
    end
    -- Update style dropdown text
    local styleNames = {
        square = L["STYLE_SQUARES"] or "Squares",
        ring = L["STYLE_RINGS"] or "Rings"
    }
    if tab.styleBtn then tab.styleBtn:OverrideText(styleNames[db.style or "square"] or "Squares") end

    -- Update limit nodes checkbox and Add Slot button state
    if tab.limitCheck then
        if db.limitNodes == nil then db.limitNodes = true end
        tab.limitCheck:SetChecked(db.limitNodes)
    end
    local maxNodes = GetEffectiveNodeLimit(db, self:GetEditedSide())
    if tab.addBtn then
        tab.addBtn:SetEnabled(maxSlots < maxNodes)
    end
    if tab.nodeCount then
        tab.nodeCount:SetText("(" .. maxSlots .. "/" .. (maxNodes < 999 and maxNodes or "âˆž") .. ")")
    end

    if tab.nodeCount then
        local mainLimitText = GetEffectiveNodeLimit(db, "primary")
        local dualLimitText = GetEffectiveNodeLimit(db, "secondary")
        local formatStr = L["AH_NODE_COUNT_FORMAT"] or "Main %d/%s  Dual %d/%s"
        tab.nodeCount:SetText(string.format(
            formatStr,
            #slots,
            (mainLimitText < 999 and mainLimitText or "inf"),
            #secondarySlots,
            (dualLimitText < 999 and dualLimitText or "inf")
        ))
    end
    if tab.mainSideBtn then
        tab.mainSideBtn:SetEnabled(self:GetEditedSide() ~= "primary")
    end
    if tab.dualSideBtn then
        tab.dualSideBtn:SetShown(db.dualSideEnabled)
        tab.dualSideBtn:SetEnabled(self:GetEditedSide() ~= "secondary")
    end
    if tab.sideInfo then
        tab.sideInfo:SetText(self:GetEditedSide() == "secondary" and (L["AH_EDITING_DUAL"] or "Editing: Dual Side") or (L["AH_EDITING_MAIN"] or "Editing: Main Side"))
    end

    -- --- Update preview in Tab ---
    local ringContainer = tab.ringContainer
    local buttons = tab.ringButtons or {}
    for _, btn in ipairs(buttons) do
        btn:Hide()
    end

    -- Shift the tab preview farther down-right to better use the freed space.
    local cx, cy = 256, -204
    local baseRadius = 65
    local radiusStep = db.nodeLineSize or 48

    local dualQuadrant = GetDualQuadrant(quadrant, db.dualSideLayout)
    local buttonCursor = 1

    local function EnsurePreviewButton(index)
        local btn = buttons[index]
        if btn then
            return btn
        end

        btn = CreateFrame("Button", nil, ringContainer, "BackdropTemplate")
        btn:SetSize(40, 40)
        btn.isActionHubSlot = true

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetSize(30, 30)
        btn.icon = icon

        local plus = btn:CreateTexture(nil, "OVERLAY")
        plus:SetPoint("CENTER", btn, "CENTER", 0, 0)
        plus:SetSize(24, 24)
        plus:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\add.tga")
        btn.plus = plus

        local glow = btn:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
        glow:SetSize(52, 52)
        glow:SetTexture("Interface\\Buttons\\CheckButtonGlow")
        glow:SetVertexColor(1, 0.82, 0, 1)
        glow:SetBlendMode("ADD")
        glow:Hide()
        btn.glow = glow

        btn:SetScript("OnEnter", function(self)
            local s = self.slotData
            if s and s.type and ActionHub:GetActiveHubDB().showTooltip ~= false then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if s.type == "toy" then
                    if GetToyAssignmentMode(s) == "direct" then
                        local toyName = GetDirectToyDisplay(s.id)
                        GameTooltip:SetText(string.format(L["TOOLTIP_TOY_FORMAT"] or "Toy: %s", tostring(toyName or s.id)))
                    else
                        GameTooltip:SetText(string.format(L["TOOLTIP_TOYMIX_FORMAT"] or "Toy Mix: %s", tostring(s.id)))
                    end
                elseif s.type == "emote" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_REACTION_FORMAT"] or "Reaction: %s", tostring(s.id)))
                elseif s.type == "trigger" then
                    local trg = OxedHub.db.profile.triggers[s.id]
                    GameTooltip:SetText(string.format(L["TOOLTIP_TRIGGER_FORMAT"] or "Trigger: %s", (trg and (trg.name or s.id) or tostring(s.id))))
                elseif s.type == "mount" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_MOUNT_FORMAT"] or "Mount: %s", tostring(s.label or s.id)))
                elseif s.type == "item" then
                    GameTooltip:SetText(string.format(L["TOOLTIP_ITEM_FORMAT"] or "Item: %s", tostring(s.label or s.id)))
                end
                GameTooltip:Show()
            end
            local style = ActionHub:GetActiveHubDB().style or "square"
            if style == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(1, 0.82, 0, 1)
            else
                self:SetBackdropBorderColor(1, 0.82, 0, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            local style = ActionHub:GetActiveHubDB().style or "square"
            local dialog = ActionHub.pickerDialog
            local isSelected = dialog and dialog:IsShown() and dialog.slotIndex == self.slotIndex and dialog.slotSide == self.slotSide
            local isGroup = dialog and dialog.groupSelection and dialog.groupSelection[self.slotSide .. "_" .. self.slotIndex]
            
            if style == "ring" and self.ringBg then
                if isGroup then
                    self.ringBg:SetVertexColor(0, 0.6, 1, 1)
                elseif isSelected then
                    self.ringBg:SetVertexColor(1, 0.82, 0, 1)
                else
                    self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
                end
            else
                if isGroup then
                    self:SetBackdropBorderColor(0, 0.6, 1, 1)
                elseif isSelected then
                    self:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                end
            end
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnReceiveDrag", function(self)
            local infoType, info1, info2, info3 = GetCursorInfo()
            if not infoType then return end

            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, self.slotSide)
            local currentSlot = slots[self.slotIndex]
            if not currentSlot then return end

            if infoType == "item" then
                local itemID = info1
                if C_ToyBox.GetToyInfo(itemID) then
                    currentSlot.type = "toy"
                    currentSlot.id = itemID
                    currentSlot.mode = "direct"
                else
                    currentSlot.type = "item"
                    currentSlot.id = itemID
                    currentSlot.icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or GetItemIcon(itemID)
                    currentSlot.label = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or GetItemInfo(itemID) or tostring(itemID)
                end
            elseif infoType == "mount" then
                local mountID = info1
                local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
                currentSlot.type = "mount"
                currentSlot.id = mountID
                currentSlot.icon = icon
                currentSlot.label = name
            elseif infoType == "spell" then
                local spellID = info3
                local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
                currentSlot.type = "spell"
                currentSlot.id = spellID
                currentSlot.icon = spellInfo and spellInfo.iconID
                currentSlot.label = spellInfo and spellInfo.name
            elseif infoType == "macro" then
                local macroIndex = info1
                local name, icon, body = GetMacroInfo(macroIndex)
                currentSlot.type = "macro"
                currentSlot.id = macroIndex
                currentSlot.icon = icon
                currentSlot.label = name
                currentSlot.body = body
            else
                return -- unsupported type, ignore
            end
            
            ClearCursor()
            ActionHub:RefreshWidget()
            ActionHub:RefreshTab()
        end)
        btn:SetScript("OnDragStart", function(self)
            if ActionHub:IsPreviewMoveModeActiveForButton(self) then
                ActionHub:BeginPreviewNodeDrag(self)
            else
                ActionHub:BeginPreviewAssignmentDrag(self)
            end
        end)
        btn:SetScript("OnDragStop", function(self)
            if self.isDraggingNode then
                ActionHub:EndPreviewNodeDrag(self)
            else
                ActionHub:EndPreviewAssignmentDrag(self)
            end
        end)
        btn:SetScript("OnClick", function(self, button)
            if self.wasAssignmentDragged then
                self.wasAssignmentDragged = false
                return
            end
            if button == "LeftButton" and ActionHub:IsPreviewMoveModeActiveForButton(self) then
                local dialog = ActionHub.pickerDialog
                if not dialog then return end
                if IsControlKeyDown() then
                    dialog.groupSelection = dialog.groupSelection or {}
                    dialog.groupSelectionOrder = dialog.groupSelectionOrder or 0
                    
                    if next(dialog.groupSelection) == nil and dialog.slotIndex and dialog.slotSide then
                        dialog.groupSelectionOrder = 1
                        dialog.groupSelection[dialog.slotSide .. "_" .. dialog.slotIndex] = {
                            side = dialog.slotSide,
                            index = dialog.slotIndex,
                            order = 1
                        }
                    end
                    
                    local key = self.slotSide .. "_" .. self.slotIndex
                    if dialog.groupSelection[key] then
                        dialog.groupSelection[key] = nil
                    else
                        dialog.groupSelectionOrder = (dialog.groupSelectionOrder or 0) + 1
                        dialog.groupSelection[key] = {
                            side = self.slotSide,
                            index = self.slotIndex,
                            order = dialog.groupSelectionOrder
                        }
                    end
                    ActionHub:RefreshTab()
                else
                    dialog.groupSelection = {}
                    dialog.groupSelectionOrder = 0
                    dialog.slotIndex = self.slotIndex
                    dialog.slotSide = self.slotSide
                    ActionHub:RefreshTab()
                end
                return
            end
            local infoType = GetCursorInfo()
            if infoType and button == "LeftButton" then
                local handler = self:GetScript("OnReceiveDrag")
                if handler then handler(self) end
                return
            end
            if button == "RightButton" and ActionHub:IsPreviewMoveModeActiveForButton(self) then
                local dialog = ActionHub.pickerDialog
                if dialog and dialog.groupSelection and dialog.groupSelection[self.slotSide .. "_" .. self.slotIndex] then
                    MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
                        rootDescription:CreateTitle("Align Group")
                        rootDescription:CreateButton("Align Vertically", function()
                            ActionHub:AlignGroup(self.slotSide, self.slotIndex, "vertical")
                        end)
                        rootDescription:CreateButton("Align Horizontally", function()
                            ActionHub:AlignGroup(self.slotSide, self.slotIndex, "horizontal")
                        end)
                    end)
                    return
                end
            end
            if button == "RightButton" then
                local s = self.slotData
                if s then
                    s.type = nil
                    s.id = nil
                    s.assignmentMode = nil
                    ActionHub:RefreshPickerList()
                    ActionHub:RefreshTab()
                end
            else
                ActionHub:ShowSlotPicker(self.slotIndex, self.slotSide)
            end
        end)
        btn.isActionHubSlot = true
        buttons[index] = btn
        return btn
    end

    local function RenderPreviewSide(sideSlots, sideKey, sideQuadrant)
        local skipEdge = (sideKey == "secondary") and GetSecondarySkipEdge(quadrant, sideQuadrant, db.dualSideLayout) or nil
        for i = 1, #sideSlots do
            local slot = sideSlots[i]
            local btn = EnsurePreviewButton(buttonCursor)
            buttonCursor = buttonCursor + 1

            local baseX, baseY = GetArcCoordinates(i, #sideSlots, sideQuadrant, cx, cy, baseRadius, radiusStep, nil, skipEdge)
            local x, y = GetArcCoordinates(i, #sideSlots, sideQuadrant, cx, cy, baseRadius, radiusStep, slot, skipEdge)
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", ringContainer, "TOPLEFT", x, y)
            btn.basePreviewX = baseX
            btn.basePreviewY = baseY
            btn.slotIndex = i
            btn.slotSide = sideKey
            btn.slotData = slot
            btn:Show()

            if slot and slot.type then
                btn.plus:Hide()
                if btn.splitIcon then btn.splitIcon:Hide() end

                if slot.type == "toy" then
                    if GetToyAssignmentMode(slot) == "direct" then
                        local _, icon = GetDirectToyDisplay(slot.id)
                        btn.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                        btn.icon:Show()
                    else
                        -- Check for custom icon override first
                        local customIcon = OxedHub.Toys and OxedHub.Toys.GetMixCustomIcon and OxedHub.Toys:GetMixCustomIcon(slot.id)
                        if customIcon then
                            btn.icon:SetTexture(customIcon)
                            btn.icon:Show()
                        else
                            local icon1, icon2, icon3, icon4
                            if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                                icon1, icon2, icon3, icon4 = OxedHub.Toys:GetMixSlotIcons(slot.id)
                            end
                            if icon1 and icon2 and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                                btn.icon:Hide()
                                btn.splitIcon = OxedHub.Toys:CreateSplitIcon(btn, 32, icon1, icon2, icon3, icon4)
                                btn.splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                                btn.splitIcon:Show()
                            else
                                btn.icon:SetTexture(icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                                btn.icon:Show()
                            end
                        end
                    end
                elseif slot.type == "emote" then
                    local reactionIcon = ActionHub:GetEmoteIconById(slot.id)
                        or "Interface\\Icons\\Spell_Holy_AshesToAshes"
                    btn.icon:SetTexture(reactionIcon)
                    btn.icon:Show()
                elseif slot.type == "trigger" then
                    local trg = OxedHub.db.profile.triggers[slot.id]
                    if trg then
                        local triggerIcon = (OxedHub.Triggers and OxedHub.Triggers.GetTriggerDisplayIcon and OxedHub.Triggers:GetTriggerDisplayIcon(trg))
                            or "Interface\\Icons\\INV_Misc_QuestionMark"
                        btn.icon:SetTexture(triggerIcon)
                        btn.icon:Show()
                    end
                elseif slot.type == "marker" or slot.type == "targetmarker" or slot.type == "ping" then
                    btn.icon:SetTexture(GetMarkerPingIcon(slot))
                    btn.icon:Show()
                elseif slot.type == "mount" then
                    btn.icon:SetTexture(slot.icon or "Interface\\Icons\\MountJournalPortrait")
                    btn.icon:Show()
                elseif slot.type == "item" then
                    btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_Bag_08")
                    btn.icon:Show()
                elseif slot.type == "spell" then
                    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(slot.id)
                    btn.icon:SetTexture((info and info.iconID) or slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.icon:Show()
                elseif slot.type == "macro" then
                    btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.icon:Show()
                else
                    -- Unknown type: fall back to a stored icon rather than a blank node.
                    btn.icon:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    btn.icon:Show()
                end
            else
                btn.icon:Hide()
                if btn.splitIcon then btn.splitIcon:Hide() end
                btn.plus:Show()
            end

            -- Custom icon override, same as the on-screen widget.
            local customTex = slot and slot.type and ResolveCustomIcon(slot.customIcon)
            if customTex then
                if btn.splitIcon then btn.splitIcon:Hide() end
                btn.icon:SetTexture(customTex)
                btn.icon:Show()
            end

            local style = db.style or "square"
            local size = (slot and slot.nodeSize) or db.globalNodeSize or 44
            btn:SetSize(size, size)
            StyleButton(btn, style, size, true)
            ApplyReadyGlow(btn, false)
            -- Show the same keybind label as the on-screen widget nodes.
            UpdateBindingLabel(btn, slot, size, style)
            
            local dialog = self.pickerDialog
            local isSelected = dialog and dialog:IsShown() and dialog.slotIndex == i and dialog.slotSide == sideKey
            local isGroup = dialog and dialog.groupSelection and dialog.groupSelection[sideKey .. "_" .. i]
            
            if isGroup then
                SetNodeSelected(btn, true, style, "group")
            elseif isSelected then
                SetNodeSelected(btn, true, style)
            else
                SetNodeSelected(btn, false, style)
            end
            
            local handler = btn:GetScript("OnLeave")
            if handler then handler(btn) end
        end
    end

    RenderPreviewSide(slots, "primary", quadrant)
    if db.dualSideEnabled and #secondarySlots > 0 then
        RenderPreviewSide(secondarySlots, "secondary", dualQuadrant)
    end
    for i = buttonCursor, #buttons do
        if buttons[i] then
            buttons[i]:Hide()
        end
    end
    tab.ringButtons = buttons

    local dialog = self.pickerDialog
    local moveModeActive = dialog
        and dialog:IsShown()
        and dialog.moveNodeMode
        and dialog.slotIndex
        and tab.moveOverlay

    if tab.moveOverlay then
        tab.moveOverlay:SetShown(moveModeActive and true or false)
        if tab.previewLogo then
            tab.previewLogo:SetShown(db.showLogoWhenLocked or moveModeActive)
            tab.previewLogo:ClearAllPoints()
            tab.previewLogo:SetPoint("CENTER", tab.ringContainer, "TOPLEFT", 256 + (db.logoOffsetX or 0), -204 + (db.logoOffsetY or 0))
            tab.previewLogo:EnableMouse(moveModeActive)
        end
        if moveModeActive then
            ActionHub:UpdatePreviewMoveGrid(tab)
            if tab.SyncSpacingSliders then tab.SyncSpacingSliders() end
        end
    end
    if tab.moveBtn then
        if dialog and dialog:IsShown() and dialog.slotIndex then
            tab.moveBtn:Enable()
            tab.moveBtn:SetText(moveModeActive and (L["AH_MOVING"] or "Moving") or (L["AH_MOVE"] or "Move"))
        else
            tab.moveBtn:Disable()
            if dialog then dialog.moveNodeMode = false end
            tab.moveBtn:SetText(L["AH_MOVE"] or "Move")
        end
    end
    if tab.minimizeBtn then
        tab.minimizeBtn:SetShown(moveModeActive and true or false)
    end
    if tab.gridMenuBtn then
        tab.gridMenuBtn:SetShown(moveModeActive and true or false)
    end
    if tab.UpdateGridText then
        tab.UpdateGridText()
    end

    if maxSlots > 0 and (not self.pickerDialog or not self.pickerDialog:IsShown()) then
        self:ShowSlotPicker(1, self:GetEditedSide())
    elseif maxSlots == 0 and self.pickerDialog and self.pickerDialog:IsShown() and self.pickerDialog.slotSide == self:GetEditedSide() then
        self.pickerDialog:Hide()
    end

    self:RefreshWidget()
end

function ActionHub:RefreshSidebarCategories()
    local dialog = self.pickerDialog
    if not dialog then return end

    local activeDB = self:GetActiveHubDB()
    activeDB.visibleTabs = activeDB.visibleTabs or {
        toy = true,
        emote = true,
        trigger = true,
        marker = true,
        mount = false,
        item = false,
        spell = false,
        settings = true,
    }
    activeDB.visibleTabs.settings = true
    -- Spellbook tab is opt-in: default OFF for existing hubs too (nil would read as
    -- "shown"). Only nil is migrated so a toggled choice persists.
    if activeDB.visibleTabs.spell == nil then activeDB.visibleTabs.spell = false end

    if not activeDB.visibleTabs[dialog.selectedType] then
        for _, catType in ipairs({"toy", "emote", "trigger", "marker", "mount", "item", "spell", "settings"}) do
            if activeDB.visibleTabs[catType] then
                dialog.selectedType = catType
                break
            end
        end
    end

    local yOffset = -120
    if dialog.sidebarButtons then
        for _, container in ipairs(dialog.sidebarButtons) do
            local shown = activeDB.visibleTabs[container.catType]
            if shown then
                container:ClearAllPoints()
                container:SetPoint("TOPLEFT", dialog, "TOPLEFT", -34, yOffset)
                container:Show()
                yOffset = yOffset - 52
            else
                container:Hide()
            end
        end
    end
end

function ActionHub:ShowSlotPicker(slotIndex, slotSide)
    if not slotIndex then
        if self.pickerDialog then self.pickerDialog:Hide() end
        self:RefreshTab()
        return
    end

    local db = self:GetActiveHubDB()
    local dialog = self.pickerDialog
    if not dialog then
        dialog = CreateFrame("Frame", nil, self.tab, "BackdropTemplate")
        local insetLeft, insetRight, insetTop, insetBottom = 42, 56, 66, 54
        if OxedHub.UI and OxedHub.UI.GetThemedFrameInsets then
            insetLeft, insetRight, insetTop, insetBottom = OxedHub.UI:GetThemedFrameInsets()
        end
        dialog:SetPoint("TOPRIGHT", self.tab, "TOPRIGHT", -insetRight, -insetTop)
        dialog:SetPoint("BOTTOMRIGHT", self.tab, "BOTTOMRIGHT", -insetRight, insetBottom)
        dialog:SetWidth(310)
        ApplyAssignmentBackdrop(dialog)

        local sectionTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sectionTitle:SetPoint("TOPLEFT", dialog, "TOPLEFT", 26, -14)
        sectionTitle:SetText(L["AH_ASSIGNMENTS"] or "Assignments")
        sectionTitle:SetTextColor(0.95, 0.90, 0.85, 1)

        local sectionInfo = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sectionInfo:SetPoint("TOPLEFT", sectionTitle, "BOTTOMLEFT", 0, -4)
        sectionInfo:SetJustifyH("LEFT")
        sectionInfo:SetText(L["AH_CONFIGURE_ACTION"] or "Configure action for this slot")
        sectionInfo:SetTextColor(0.90, 0.85, 0.80, 1)
        dialog.sectionInfo = sectionInfo

        local showToysCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
        showToysCheck:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -105, -12)
        showToysCheck:SetSize(22, 22)
        showToysCheck:SetScript("OnClick", function(self)
            dialog.showDirectToys = self:GetChecked() and true or false
            ActionHub:RefreshPickerList()
        end)
        dialog.showToysCheck = showToysCheck

        local showToysLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        showToysLabel:SetPoint("LEFT", showToysCheck, "RIGHT", 2, 0)
        showToysLabel:SetText(L["AH_SHOW_TOYS"] or "Show Toys")
        showToysLabel:SetTextColor(1, 0.82, 0)
        dialog.showToysLabel = showToysLabel

        -- "All Triggers" checkbox (shown only when trigger section is active)
        local allTriggersCheck = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
        allTriggersCheck:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -105, -12)
        allTriggersCheck:SetSize(22, 22)
        allTriggersCheck:SetChecked(false)
        allTriggersCheck:SetScript("OnClick", function(self)
            dialog.showAllTriggers = self:GetChecked() and true or false
            ActionHub:RefreshPickerList()
        end)
        allTriggersCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["AH_ALL_TRIGGERS"] or "All Triggers")
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_DESC"] or "Show triggers of ALL event types (Cooldown Ready, Aura, Interrupt, etc.), not just Spell Cast triggers.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        allTriggersCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
        allTriggersCheck:Hide()
        dialog.allTriggersCheck = allTriggersCheck

        local allTriggersLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        allTriggersLabel:SetPoint("LEFT", allTriggersCheck, "RIGHT", 2, 0)
        allTriggersLabel:SetText(L["AH_ALL_TRIGGERS"] or "All Triggers")
        allTriggersLabel:SetTextColor(1, 0.82, 0)
        allTriggersLabel:Hide()
        dialog.allTriggersLabel = allTriggersLabel

        -- (i) help icon next to "All Triggers"
        local allTriggersHelp = CreateFrame("Button", nil, dialog)
        allTriggersHelp:SetSize(16, 16)
        allTriggersHelp:SetPoint("LEFT", allTriggersLabel, "RIGHT", 4, 0)
        allTriggersHelp:SetNormalTexture("Interface\\Common\\help-i")
        allTriggersHelp:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
        allTriggersHelp:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["AH_ALL_TRIGGERS_HELP_TITLE"] or "|cffffd100All Triggers|r")
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_LINE1"] or "By default, ActionHub only shows |cff00ff00Spell Cast|r triggers in this list. These are the basic triggers that fire when you cast a specific spell.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_LINE2"] or "Check this box to also include triggers from other event types:", 1, 1, 1, true)
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_BULLET1"] or "  â€¢ Cooldown Ready", 0.62, 0.84, 1)
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_BULLET2"] or "  â€¢ Aura Applied / Removed", 0.62, 0.84, 1)
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_BULLET3"] or "  â€¢ Interrupt Used / Spell Interrupted", 0.62, 0.84, 1)
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_BULLET4"] or "  â€¢ Death, Resurrect, Pet Events, etc.", 0.62, 0.84, 1)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["AH_ALL_TRIGGERS_HELP_LINE3"] or "Useful if you want to assign a non-spell trigger to an ActionHub node.", 0.9, 0.82, 0.4, true)
            GameTooltip:Show()
        end)
        allTriggersHelp:SetScript("OnLeave", function() GameTooltip:Hide() end)
        allTriggersHelp:Hide()
        dialog.allTriggersHelp = allTriggersHelp

        local toySearchBox = CreateFrame("EditBox", "OxedHubActionHubSearchBox", dialog, "SearchBoxTemplate")
        toySearchBox:SetSize(140, 20)
        toySearchBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", 33, -50)
        toySearchBox:SetAutoFocus(false)
        toySearchBox:HookScript("OnTextChanged", function(self, isUserInput)
            if self.isSyncingText then
                return
            end
            local text = self:GetText() or ""
            -- SearchBoxTemplate sets the text to the localized "Search" placeholder when
            -- the field is empty. Treat that as an empty filter so all items are shown.
            if text == (SEARCH or "Search") or text == "Search" then
                text = ""
            end
            dialog.toySearchText = text
            if dialog.showDirectToys or (dialog.selectedType and (dialog.selectedType == "mount" or dialog.selectedType == "item")) then
                ActionHub:RefreshPickerList()
            elseif dialog.showDirectToys then
                ActionHub:RefreshPickerList()
            end
        end)
        toySearchBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)
        dialog.toySearchBox = toySearchBox

        -- Mount Count Label on the right side of the search box
        local mountCountLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mountCountLabel:SetPoint("LEFT", toySearchBox, "RIGHT", 10, 0)
        mountCountLabel:SetTextColor(0.95, 0.90, 0.85, 1)
        mountCountLabel:Hide()
        dialog.mountCountLabel = mountCountLabel

        -- Scroll area
        local scroll = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
        scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 36)
        if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
            OxedHub.UI:StyleScrollFrame(scroll)
        end
        dialog.scroll = scroll

        local gridUnderlay = scroll:CreateTexture(nil, "BACKGROUND")
        gridUnderlay:SetPoint("TOPLEFT", dialog, "TOPLEFT", 9, -10)
        gridUnderlay:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -18, 14)
        gridUnderlay:SetColorTexture(0.2, 0.1, 0.05, 0.1)
        gridUnderlay:SetDrawLayer("BACKGROUND", 1)
        dialog.gridUnderlay = gridUnderlay

        local child = CreateFrame("Frame")
        child:SetWidth(260)
        child:SetHeight(1)
        scroll:SetScrollChild(child)
        dialog.scrollChild = child

        -- Sidebar category buttons
        local sidebarCategories = {
            { name = "ToyMix",    type = "toy",      icon = 134508 },
            { name = "Reactions", type = "emote",    icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Kiss.png" },
            { name = "Triggers",  type = "trigger",  icon = 236248 },
            { name = "Markers",   type = "marker",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
            { name = "Mounts",    type = "mount",    icon = "Interface\\Icons\\MountJournalPortrait" },
            { name = "Items",     type = "item",     icon = 3753262 },
            { name = "Spells",    type = "spell",    icon = "Interface\\Icons\\INV_Misc_Book_09" },
            { name = "Settings",  type = "settings", icon = 4548872 }
        }

        dialog.sidebarButtons = {}
        for i, cat in ipairs(sidebarCategories) do
            local container = CreateFrame("Button", nil, dialog)
            container:SetSize(44, 44)
            container:SetFrameLevel(dialog:GetFrameLevel() + 20)

            local mask = container:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetSize(32, 32)
            mask:SetPoint("CENTER", 1, -1)
            container.iconMask = mask
            
            local bg = container:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetSize(32, 32)
            bg:SetPoint("CENTER", 1, -1)
            bg:SetVertexColor(0, 0, 0, 1)
            bg:AddMaskTexture(mask)
            
            local icon = container:CreateTexture(nil, "ARTWORK")
            icon:SetTexture(cat.icon)
            icon:SetSize(32, 32)
            icon:SetPoint("CENTER", 1, -1)
            icon:AddMaskTexture(mask)
            
            local ring = container:CreateTexture(nil, "OVERLAY")
            ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            ring:SetAllPoints()
            ring:SetTexCoord(0, 0.6, 0, 0.6)
            container.border = ring
            
            container.catType = cat.type
            
            container:SetScript("OnClick", function()
                if dialog.selectedType ~= cat.type then
                    dialog.toySearchText = ""
                    if dialog.toySearchBox then
                        dialog.toySearchBox.isSyncingText = true
                        dialog.toySearchBox:SetText("")
                        dialog.toySearchBox.isSyncingText = false
                    end
                end
                dialog.selectedType = cat.type
                ActionHub:RefreshPickerList()
            end)
            
            container:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local key = "TAB_" .. (cat.type == "toy" and "TOYMIX" or cat.type:upper())
                GameTooltip:SetText(L[key] or cat.name)
                GameTooltip:Show()
            end)
            container:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            table.insert(dialog.sidebarButtons, container)
        end

        -- Integrated Reaction Editor Frames (mimicking EmotionRing)
        local editor = CreateFrame("Frame", nil, dialog)
        editor:SetAllPoints()
        editor:Hide()
        dialog.editor = editor

        local function CreateEditorPicker(labelText, xOffset, yOffset, valueGetter, onClick)
            local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", editor, "TOPLEFT", xOffset, yOffset)
            label:SetText(labelText)
            label:SetTextColor(1, 0.82, 0)

            local button = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
            button:SetSize(110, 24)
            button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
            
            local btnText = button:GetFontString()
            if btnText then
                btnText:SetWordWrap(false)
                btnText:SetWidth(100)
                btnText:SetJustifyH("CENTER")
            end
            
            button.valueGetter = valueGetter
            button:SetScript("OnClick", onClick)
            return { label = label, button = button }
        end

        -- Helper: get or create reaction data for an emote key
        local function GetReaction(emoteKey)
            if not emoteKey or emoteKey == "None" then return {} end
            local profile = OxedHub.db and OxedHub.db.profile
            if not profile then return {} end
            profile.emotionMappings = profile.emotionMappings or {}
            profile.emotionMappings[emoteKey] = profile.emotionMappings[emoteKey] or {}
            return profile.emotionMappings[emoteKey]
        end

        -- Helper: build option lists for dropdown pickers
        local function BuildSoundOptions()
            local opts = {{label = "None", value = nil}}
            local profile = OxedHub.db and OxedHub.db.profile
            if profile then
                for id, sound in pairs(profile.customSounds or {}) do
                    table.insert(opts, {label = sound.name or id, value = id})
                end
            end
            return opts
        end
        local function BuildAnimationOptions()
            local opts = {{label = "None", value = nil}}
            local profile = OxedHub.db and OxedHub.db.profile
            if profile then
                for id, anim in pairs(profile.animations or {}) do
                    table.insert(opts, {label = anim.name or id, value = id})
                end
            end
            return opts
        end
        local function BuildEmoteOptions()
            local opts = {{label = "None", value = nil}}
            local added = {}
            local predefined = {"APPLAUD","BEG","BOW","CHEER","CHICKEN","CRY","DANCE","FLEX","FLIRT","GASP","KISS","LAUGH","LEAN","POINT","ROAR","RUDE","SALUTE","SHY","SIGH","SLEEP","TAUNT","WAVE"}
            for _, cmd in ipairs(predefined) do
                local display = cmd:sub(1,1) .. cmd:sub(2):lower()
                table.insert(opts, {label = display, value = cmd})
                added[cmd] = true
            end
            local profile = OxedHub.db and OxedHub.db.profile
            if profile then
                for id in pairs(profile.emotionMappings or {}) do
                    if not added[id] then
                        table.insert(opts, {label = id, value = id})
                    end
                end
            end
            return opts
        end
        local function BuildChatOptions()
            local opts = {{label = "None", value = nil}}
            local profile = OxedHub.db and OxedHub.db.profile
            if profile then
                for id, chat in pairs(profile.chatTemplates or {}) do
                    table.insert(opts, {label = chat.name or chat.text or id, value = id})
                end
            end
            return opts
        end
        local function BuildToyMacroOptions()
            local opts = {{label = "None", value = nil}}
            local profile = OxedHub.db and OxedHub.db.profile
            if profile then
                for name in pairs(profile.toyMixes or {}) do
                    table.insert(opts, {label = name, value = name})
                end
            end
            return opts
        end
        local function GetOptionLabel(opts, val)
            if not val then return "None" end
            for _, o in ipairs(opts) do if o.value == val then return o.label end end
            return tostring(val)
        end

        -- Reuse the OxedRing native picker if it exists, otherwise create one
        local nativePicker = _G["OxedRingNativePicker"]
        if not nativePicker then
            nativePicker = CreateFrame("Frame", "OxedRingNativePicker", UIParent, "BackdropTemplate")
            nativePicker:SetSize(220, 264)
            nativePicker:SetFrameStrata("DIALOG")
            nativePicker:SetFrameLevel(500)
            nativePicker:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            nativePicker:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            nativePicker:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            nativePicker:Hide()

            local searchBox = CreateFrame("EditBox", nil, nativePicker, "SearchBoxTemplate")
            searchBox:SetSize(204, 20)
            searchBox:SetPoint("TOPLEFT", nativePicker, "TOPLEFT", 8, -8)
            searchBox:SetAutoFocus(false)
            nativePicker.searchBox = searchBox

            local scroll = CreateFrame("ScrollFrame", nil, nativePicker, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 8, -32)
            scroll:SetPoint("BOTTOMRIGHT", -26, 8)
            if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
                OxedHub.UI:StyleScrollFrame(scroll)
            end
            nativePicker.scrollFrame = scroll

            local child = CreateFrame("Frame")
            child:SetWidth(180)
            child:SetHeight(1)
            scroll:SetScrollChild(child)
            nativePicker.scrollChild = child
            nativePicker.buttons = {}
            nativePicker.playButtons = {}

            searchBox:HookScript("OnTextChanged", function(self)
                local text = self:GetText():lower()
                nativePicker:FilterOptions(text)
            end)

            nativePicker:SetScript("OnUpdate", function(self)
                if self:IsShown() and not self:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        self:Hide()
                    end
                end
            end)
        end

        local function GetSoundInfo(val)
            local profile = OxedHub.db and OxedHub.db.profile
            return profile and profile.customSounds and profile.customSounds[val]
        end

        nativePicker.FilterOptions = function(self, filterText)
            for _, btn in ipairs(self.buttons) do btn:Hide() end
            for _, pbtn in ipairs(self.playButtons) do pbtn:Hide() end

            local matchedOptions = {}
            for _, opt in ipairs(self.fullOptions or {}) do
                local match = true
                if filterText and filterText ~= "" then
                    local label = opt.label and tostring(opt.label):lower() or ""
                    local value = opt.value and tostring(opt.value):lower() or ""
                    if not label:find(filterText, 1, true) and not value:find(filterText, 1, true) then
                        match = false
                    end
                end
                if match then
                    table.insert(matchedOptions, opt)
                end
            end

            local displayList = {}
            if self.isSound then
                local noneOpt = nil
                local favorites = {}
                local customs = {}
                local others = {}

                for _, opt in ipairs(matchedOptions) do
                    if opt.value == nil then
                        noneOpt = opt
                    else
                        local sound = GetSoundInfo(opt.value)
                        if sound then
                            if sound.isFavorite then
                                table.insert(favorites, opt)
                            end
                            if not sound.autoImported then
                                table.insert(customs, opt)
                            else
                                local cat = (sound.category and sound.category ~= "") and sound.category or "Other"
                                others[cat] = others[cat] or {}
                                table.insert(others[cat], opt)
                            end
                        else
                            local cat = "Other"
                            others[cat] = others[cat] or {}
                            table.insert(others[cat], opt)
                        end
                    end
                end

                local function sortFunc(a, b)
                    return (a.label or ""):lower() < (b.label or ""):lower()
                end
                table.sort(favorites, sortFunc)
                table.sort(customs, sortFunc)
                for cat, list in pairs(others) do
                    table.sort(list, sortFunc)
                end

                if noneOpt then
                    table.insert(displayList, noneOpt)
                end

                local function insertCategory(catName, list)
                    if #list > 0 then
                        local isCollapsed = true
                        if filterText and filterText ~= "" then
                            isCollapsed = false
                        else
                            if self.collapsedCategories[catName] == false then
                                isCollapsed = false
                            end
                        end

                        table.insert(displayList, {
                            isHeader = true,
                            label = (isCollapsed and "> " or "v ") .. catName .. " (" .. #list .. ")",
                            catName = catName,
                            isCollapsed = isCollapsed
                        })

                        if not isCollapsed then
                            for _, opt in ipairs(list) do
                                table.insert(displayList, opt)
                            end
                        end
                    end
                end

                insertCategory("Favorites", favorites)
                insertCategory("Custom", customs)

                local CATEGORY_ORDER = {
                    "DH Pack",
                    "Monk Pack",
                    "Worrier Pack",
                    "Death",
                    "Effects",
                    "Meme",
                    "Legions",
                    "Quote",
                    "Anime",
                    "Arabic",
                    "Other"
                }

                local processed = {}
                for _, catName in ipairs(CATEGORY_ORDER) do
                    local list = others[catName]
                    if list and #list > 0 then
                        insertCategory(catName, list)
                        processed[catName] = true
                    end
                end

                local extraCats = {}
                for catName, list in pairs(others) do
                    if not processed[catName] and #list > 0 then
                        table.insert(extraCats, catName)
                    end
                end
                table.sort(extraCats)
                for _, catName in ipairs(extraCats) do
                    insertCategory(catName, others[catName])
                end
            else
                displayList = matchedOptions
            end

            local y = 0
            local count = 0
            for _, opt in ipairs(displayList) do
                count = count + 1
                local btn = self.buttons[count]
                if not btn then
                    btn = CreateFrame("Button", nil, self.scrollChild)
                    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    self.buttons[count] = btn
                end
                
                btn:Show()
                btn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -y)

                if opt.isHeader then
                    btn:SetSize(180, 20)
                    btn:SetNormalFontObject("GameFontNormalSmall")
                    btn:SetText(opt.label)
                    btn:SetEnabled(true)
                    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetAlpha(0.2) end
                    btn:SetScript("OnClick", function()
                        self.collapsedCategories[opt.catName] = not opt.isCollapsed
                        self:FilterOptions(self.searchBox:GetText())
                    end)
                    
                    local playBtn = self.playButtons[count]
                    if playBtn then playBtn:Hide() end
                else
                    btn:SetNormalFontObject("GameFontHighlightSmall")
                    btn:SetText(opt.label)
                    btn:SetEnabled(true)
                    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetAlpha(0.4) end
                    btn:SetScript("OnClick", function()
                        self:Hide()
                        if self.onSelect then self.onSelect(opt.value) end
                    end)

                    if self.isSound and opt.value ~= nil then
                        btn:SetSize(158, 20)
                        local playBtn = self.playButtons[count]
                        if not playBtn then
                            playBtn = CreateFrame("Button", nil, self.scrollChild)
                            playBtn:SetSize(18, 18)
                            local playIcon = playBtn:CreateTexture(nil, "ARTWORK")
                            playIcon:SetAllPoints()
                            playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                            playIcon:SetVertexColor(0.9, 0.1, 0.1)
                            playBtn.icon = playIcon
                            playBtn:SetScript("OnEnter", function(self)
                                self.icon:SetVertexColor(1, 0.3, 0.3)
                            end)
                            playBtn:SetScript("OnLeave", function(self)
                                self.icon:SetVertexColor(0.9, 0.1, 0.1)
                            end)
                            self.playButtons[count] = playBtn
                        end
                        playBtn:Show()
                        playBtn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 160, -y)
                        playBtn:SetScript("OnClick", function()
                            if OxedHub.Sounds then
                                OxedHub.Sounds:Play(opt.value)
                            end
                        end)
                    else
                        btn:SetSize(180, 20)
                        local playBtn = self.playButtons[count]
                        if playBtn then playBtn:Hide() end
                    end
                end
                y = y + 22
            end
            self.scrollChild:SetHeight(math.max(y, 1))
            self.scrollFrame:SetVerticalScroll(0)
        end

        nativePicker.ShowOptions = function(self, anchor, options, onSelect, isSound)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
            self:Show()
            self.fullOptions = options
            self.onSelect = onSelect
            self.isSound = isSound
            if isSound then
                self.collapsedCategories = {}
            end
            self.searchBox:SetText("")
            self:FilterOptions("")
        end

        dialog.reactionTabFrame = CreateFrame("Frame", nil, editor)
        dialog.reactionTabFrame:SetAllPoints()

        dialog.macroTabFrame = CreateFrame("Frame", nil, editor)
        dialog.macroTabFrame:SetAllPoints()

        dialog.soundPicker = CreateEditorPicker("Sound", 26, -10,
            function()
                local emote = ActionHub:GetSelectedEmote()
                local r = emote and GetReaction(emote) or {}
                return r.sound
            end,
            function()
                local emote = ActionHub:GetSelectedEmote()
                if not emote then return end
                nativePicker:ShowOptions(dialog.soundPicker.button, BuildSoundOptions(), function(val)
                    GetReaction(emote).sound = val
                    ActionHub:RefreshPickerList()
                end, true)
            end)
        dialog.soundPicker.label:SetParent(dialog.reactionTabFrame)
        dialog.soundPicker.button:SetParent(dialog.reactionTabFrame)

        dialog.animationPicker = CreateEditorPicker("Animation", 26, -60,
            function()
                local emote = ActionHub:GetSelectedEmote()
                local r = emote and GetReaction(emote) or {}
                return r.animation
            end,
            function()
                local emote = ActionHub:GetSelectedEmote()
                if not emote then return end
                nativePicker:ShowOptions(dialog.animationPicker.button, BuildAnimationOptions(), function(val)
                    GetReaction(emote).animation = val
                    ActionHub:RefreshPickerList()
                end)
            end)
        dialog.animationPicker.label:SetParent(dialog.reactionTabFrame)
        dialog.animationPicker.button:SetParent(dialog.reactionTabFrame)

        local animCheck = CreateFrame("CheckButton", nil, dialog.reactionTabFrame, "UICheckButtonTemplate")
        animCheck:SetPoint("TOPLEFT", dialog.animationPicker.button, "BOTTOMLEFT", 0, -4)
        animCheck:SetSize(20, 20)

        dialog.animCheck = animCheck
        local animCheckLabel = dialog.reactionTabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        animCheckLabel:SetPoint("LEFT", animCheck, "RIGHT", 4, 0)
        animCheckLabel:SetText(L["LBL_CUSTOM"] or "Custom")

        local setPosBtn = CreateFrame("Button", nil, dialog.reactionTabFrame, "UIPanelButtonTemplate")
        setPosBtn:SetSize(70, 20)
        setPosBtn:SetPoint("LEFT", animCheckLabel, "RIGHT", 8, 0)
        setPosBtn:SetText(L["BTN_SET_POS"] or "Set Pos")
        setPosBtn:SetScript("OnClick", function()
            local emote = ActionHub:GetSelectedEmote()
            if not emote then return end
            local r = GetReaction(emote)
            local x = r.animationCustomX or 0
            local y = r.animationCustomY or 200
            
            if OxedHub.Animations and OxedHub.Animations.ShowPositionFrameCustom then
                OxedHub.Animations:ShowPositionFrameCustom(x, y, function(relX, relY)
                    local currentEmote = ActionHub:GetSelectedEmote()
                    if currentEmote then
                        local cr = GetReaction(currentEmote)
                        cr.animationCustomX = relX
                        cr.animationCustomY = relY
                    end
                end)
            end
        end)
        dialog.setPosBtn = setPosBtn

        animCheck:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            local emote = ActionHub:GetSelectedEmote()
            if emote then GetReaction(emote).animationUseCustomPosition = checked end
            setPosBtn:SetEnabled(checked)
        end)

        dialog.emotePicker = CreateEditorPicker("Emote", 146, -10,
            function()
                local emote = ActionHub:GetSelectedEmote()
                local r = emote and GetReaction(emote) or {}
                return r.emote
            end,
            function()
                local emote = ActionHub:GetSelectedEmote()
                if not emote then return end
                nativePicker:ShowOptions(dialog.emotePicker.button, BuildEmoteOptions(), function(val)
                    GetReaction(emote).emote = val
                    ActionHub:RefreshPickerList()
                end)
            end)
        dialog.emotePicker.label:SetParent(dialog.reactionTabFrame)
        dialog.emotePicker.button:SetParent(dialog.reactionTabFrame)

        dialog.chatPicker = CreateEditorPicker("Chat Template", 146, -60,
            function()
                local emote = ActionHub:GetSelectedEmote()
                local r = emote and GetReaction(emote) or {}
                return r.chat
            end,
            function()
                local emote = ActionHub:GetSelectedEmote()
                if not emote then return end
                nativePicker:ShowOptions(dialog.chatPicker.button, BuildChatOptions(), function(val)
                    GetReaction(emote).chat = val
                    ActionHub:RefreshPickerList()
                end)
            end)
        dialog.chatPicker.label:SetParent(dialog.reactionTabFrame)
        dialog.chatPicker.button:SetParent(dialog.reactionTabFrame)

        dialog.toyMacroPicker = CreateEditorPicker("Toy Macro", 26, -10,
            function()
                local emote = ActionHub:GetSelectedEmote()
                local r = emote and GetReaction(emote) or {}
                return r.toyMacro
            end,
            function()
                local emote = ActionHub:GetSelectedEmote()
                if not emote then return end
                nativePicker:ShowOptions(dialog.toyMacroPicker.button, BuildToyMacroOptions(), function(val)
                    GetReaction(emote).toyMacro = val
                    ActionHub:RefreshPickerList()
                end)
            end)
        dialog.toyMacroPicker.label:SetParent(dialog.macroTabFrame)
        dialog.toyMacroPicker.button:SetParent(dialog.macroTabFrame)

        dialog.settingsTabFrame = CreateFrame("Frame", nil, dialog)
        dialog.settingsTabFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
        dialog.settingsTabFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 36)
        dialog.settingsTabFrame:Hide()

        -- Scroll frame for settings
        local settingsScroll = CreateFrame("ScrollFrame", nil, dialog.settingsTabFrame, "UIPanelScrollFrameTemplate")
        settingsScroll:SetPoint("TOPLEFT", dialog.settingsTabFrame, "TOPLEFT", 0, 0)
        settingsScroll:SetPoint("BOTTOMRIGHT", dialog.settingsTabFrame, "BOTTOMRIGHT", 0, 0)
        if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
            OxedHub.UI:StyleScrollFrame(settingsScroll)
        end
        dialog.settingsScroll = settingsScroll

        local settingsChild = CreateFrame("Frame")
        settingsChild:SetWidth(250)
        settingsChild:SetHeight(750)
        settingsScroll:SetScrollChild(settingsChild)
        dialog.settingsChild = settingsChild

        local function TriggerRefresh()
            if not ActionHub.pendingSliderRefresh then
                ActionHub.pendingSliderRefresh = C_Timer.NewTimer(0.05, function()
                    ActionHub.pendingSliderRefresh = nil
                    ActionHub:RefreshWidget()
                    ActionHub:RefreshTab()
                end)
            end
        end

        local function CreateNumericInput(parent, anchorTo)
            local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            input:SetSize(34, 20)
            input:SetAutoFocus(false)
            input:SetNumeric(false)
            input:SetJustifyH("CENTER")
            input:SetPoint("LEFT", anchorTo, "RIGHT", 18, 0)
            return input
        end

        local function BindSliderInput(slider, input, minValue, maxValue, step, applyValue)
            local function SnapValue(value)
                if not value then return nil end
                local snapped = value
                if step and step > 0 then
                    snapped = math.floor((value / step) + 0.5) * step
                end
                if minValue then snapped = math.max(minValue, snapped) end
                if maxValue then snapped = math.min(maxValue, snapped) end
                return snapped
            end

            local function CommitInput()
                local text = input:GetText()
                local value = tonumber(text)
                if not value then
                    input:SetText(tostring(math.floor((slider:GetValue() or 0) + 0.5)))
                    return
                end

                local snapped = SnapValue(value)
                if not snapped then
                    return
                end

                slider.isResetting = true
                slider:SetValue(snapped)
                slider.isResetting = false
                input:SetText(tostring(snapped))
                if applyValue then
                    applyValue(snapped)
                end
                TriggerRefresh()
            end

            input:SetScript("OnEnterPressed", function(self)
                CommitInput()
                self:ClearFocus()
            end)
            input:SetScript("OnEditFocusLost", function()
                CommitInput()
            end)
            input:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(math.floor((slider:GetValue() or 0) + 0.5)))
                self:ClearFocus()
            end)

            return function(value)
                input:SetText(tostring(value))
            end
        end

        local bindLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bindLabel:SetPoint("TOPLEFT", settingsChild, "TOPLEFT", 16, -10)
        bindLabel:SetText(L["AH_KEYBIND"] or "Keybind")
        bindLabel:SetTextColor(1, 0.82, 0)

        local bindBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        bindBtn:SetSize(160, 24)
        bindBtn:SetPoint("TOPLEFT", bindLabel, "BOTTOMLEFT", 0, -6)
        bindBtn:SetText(L["KEYBIND_NOT_BOUND"] or "Not Bound")
        
        bindBtn:SetScript("OnClick", function(self)
            self.isListening = true
            self:SetText(L["KEYBIND_LISTENING"] or "Press a key...")
            self:EnableKeyboard(true)
        end)
        bindBtn:SetScript("OnKeyDown", function(self, key)
            if not self.isListening then return end
            if key == "ESCAPE" then
                self.isListening = false
                self:EnableKeyboard(false)
                local activeDB = ActionHub:GetActiveHubDB()
                local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                local s = slots[dialog.slotIndex]
                if s then s.binding = nil end
                ActionHub:RefreshPickerList()
                ActionHub:RefreshWidget()
                return
            end
            
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then return end
            
            local prefix = ""
            if IsAltKeyDown() then prefix = prefix .. "ALT-" end
            if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
            if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
            
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then
                s.binding = prefix .. key
            end
            self.isListening = false
            self:EnableKeyboard(false)
            ActionHub:RefreshPickerList()
            ActionHub:RefreshWidget()
        end)
        bindBtn:SetScript("OnHide", function(self)
            self.isListening = false
            self:EnableKeyboard(false)
        end)
        dialog.bindBtn = bindBtn

        local bindResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        bindResetBtn:SetSize(22, 22)
        bindResetBtn:SetPoint("LEFT", bindBtn, "RIGHT", 10, 0)
        bindResetBtn:SetText("")
        local bindResetIcon = bindResetBtn:CreateTexture(nil, "ARTWORK")
        bindResetIcon:SetSize(14, 14)
        bindResetIcon:SetPoint("CENTER", bindResetBtn, "CENTER", 0, 0)
        bindResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        bindResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        bindResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bindResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then
                s.binding = nil
            end
            if dialog.bindBtn then
                dialog.bindBtn.isListening = false
                dialog.bindBtn:EnableKeyboard(false)
                dialog.bindBtn:SetText(L["KEYBIND_NOT_BOUND"] or "Not Bound")
            end
            ActionHub:RefreshWidget()
            ActionHub:RefreshTab()
        end)
        dialog.bindResetBtn = bindResetBtn

        -- Custom icon: overrides whatever icon the slot's content would show.
        -- Uses the shared IconPicker (same list as the Advanced Macro picker).
        local iconLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconLabel:SetPoint("TOPLEFT", bindBtn, "BOTTOMLEFT", 0, -24)
        iconLabel:SetText(L["AH_CUSTOM_ICON"] or "Custom Icon")
        iconLabel:SetTextColor(1, 0.82, 0)

        local iconPreview = CreateFrame("Button", nil, settingsChild, "BackdropTemplate")
        iconPreview:SetSize(32, 32)
        iconPreview:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -6)
        iconPreview:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        iconPreview:SetBackdropColor(0, 0, 0, 0.6)
        iconPreview:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
        iconPreview:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        local iconPreviewTex = iconPreview:CreateTexture(nil, "ARTWORK")
        iconPreviewTex:SetPoint("TOPLEFT", 3, -3)
        iconPreviewTex:SetPoint("BOTTOMRIGHT", -3, 3)
        iconPreviewTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dialog.iconPreviewTex = iconPreviewTex

        local iconHint = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        iconHint:SetPoint("LEFT", iconPreview, "RIGHT", 8, 0)
        iconHint:SetWidth(120)
        iconHint:SetJustifyH("LEFT")
        iconHint:SetText(L["AH_CUSTOM_ICON_HINT"] or "Click to pick,\nright-click to clear.")

        local function CurrentSlot()
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            return slots and slots[dialog.slotIndex]
        end

        function dialog:RefreshCustomIcon()
            local s = CurrentSlot()
            local custom = ResolveCustomIcon(s and s.customIcon)
            iconPreviewTex:SetTexture(custom or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconPreviewTex:SetDesaturated(not custom)
        end

        iconPreview:SetScript("OnClick", function(self, button)
            local s = CurrentSlot()
            if not s then return end

            if button == "RightButton" then
                s.customIcon = nil
                dialog:RefreshCustomIcon()
                ActionHub:RefreshWidget()
                ActionHub:RefreshTab()
                return
            end

            if OxedHub.IconPicker then
                OxedHub.IconPicker:Open({
                    title = L["AH_CHOOSE_ICON"] or "Choose Node Icon",
                    initialValue = s.customIcon,
                    anchor = iconPreview,
                    allowClear = true,
                    onSelect = function(storedValue)
                        s.customIcon = storedValue
                        dialog:RefreshCustomIcon()
                        ActionHub:RefreshWidget()
                        ActionHub:RefreshTab()
                    end,
                })
            end
        end)

        iconPreview:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["AH_CUSTOM_ICON"] or "Custom Icon")
            GameTooltip:AddLine(L["AH_CUSTOM_ICON_LEFT"]
                or "Left-click to choose an icon for this node.", 1, 1, 1, true)
            GameTooltip:AddLine(L["AH_CUSTOM_ICON_RIGHT"]
                or "Right-click to go back to the default icon.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        iconPreview:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local sizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeLabel:SetPoint("TOPLEFT", iconPreview, "BOTTOMLEFT", 0, -22)
        sizeLabel:SetText(L["AH_NODE_SIZE"] or "Node Size")
        sizeLabel:SetTextColor(1, 0.82, 0)

        local sizeSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        sizeSlider:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 4, -14)
        sizeSlider:SetWidth(110)
        sizeSlider:SetMinMaxValues(20, 80)
        sizeSlider:SetValueStep(2)
        sizeSlider:SetObeyStepOnDrag(true)

        local sizeInput = CreateNumericInput(settingsChild, sizeSlider)
        dialog.sizeInput = sizeInput

        local sizeResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        sizeResetBtn:SetSize(22, 22)
        sizeResetBtn:SetPoint("LEFT", sizeInput, "RIGHT", 10, 0)
        sizeResetBtn:SetText("")
        local sizeResetIcon = sizeResetBtn:CreateTexture(nil, "ARTWORK")
        sizeResetIcon:SetSize(14, 14)
        sizeResetIcon:SetPoint("CENTER", sizeResetBtn, "CENTER", 0, 0)
        sizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        sizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        sizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sizeResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodeSize = nil end
            local val = activeDB.globalNodeSize or 44
            dialog.sizeSlider.isResetting = true
            dialog.sizeSlider:SetValue(val)
            dialog.sizeVal:SetText(tostring(val))
            dialog.sizeInput:SetText(tostring(val))
            dialog.sizeSlider.isResetting = false
            TriggerRefresh()
        end)

        local sizeVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeVal:SetPoint("BOTTOM", sizeSlider, "TOP", 0, 2)
        dialog.sizeVal = sizeVal

        sizeSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodeSize = value end
            dialog.sizeVal:SetText(tostring(value))
            dialog.sizeInput:SetText(tostring(value))
            TriggerRefresh()
        end)
        BindSliderInput(sizeSlider, sizeInput, 20, 80, 2, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodeSize = value end
            dialog.sizeVal:SetText(tostring(value))
        end)
        dialog.sizeSlider = sizeSlider

        -- Global Node Size
        local globalSizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        globalSizeLabel:SetPoint("TOPLEFT", sizeSlider, "BOTTOMLEFT", -4, -30)
        globalSizeLabel:SetText(L["SETTINGS_GLOBAL_NODE_SIZE"] or "Global Node Size")
        globalSizeLabel:SetTextColor(1, 0.82, 0)

        local globalSizeSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        globalSizeSlider:SetPoint("TOPLEFT", globalSizeLabel, "BOTTOMLEFT", 4, -14)
        globalSizeSlider:SetWidth(110)
        globalSizeSlider:SetMinMaxValues(20, 80)
        globalSizeSlider:SetValueStep(2)
        globalSizeSlider:SetObeyStepOnDrag(true)

        local globalSizeInput = CreateNumericInput(settingsChild, globalSizeSlider)
        dialog.globalSizeInput = globalSizeInput

        local globalSizeResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        globalSizeResetBtn:SetSize(22, 22)
        globalSizeResetBtn:SetPoint("LEFT", globalSizeInput, "RIGHT", 10, 0)
        globalSizeResetBtn:SetText("")
        local globalSizeResetIcon = globalSizeResetBtn:CreateTexture(nil, "ARTWORK")
        globalSizeResetIcon:SetSize(14, 14)
        globalSizeResetIcon:SetPoint("CENTER", globalSizeResetBtn, "CENTER", 0, 0)
        globalSizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        globalSizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        globalSizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        globalSizeResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.globalNodeSize = nil
            dialog.globalSizeSlider.isResetting = true
            dialog.globalSizeSlider:SetValue(44)
            dialog.globalSizeVal:SetText("44")
            dialog.globalSizeInput:SetText("44")
            dialog.globalSizeSlider.isResetting = false
            TriggerRefresh()
        end)

        local globalSizeVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        globalSizeVal:SetPoint("BOTTOM", globalSizeSlider, "TOP", 0, 2)
        dialog.globalSizeVal = globalSizeVal

        globalSizeSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.globalNodeSize = value
            dialog.globalSizeVal:SetText(tostring(value))
            dialog.globalSizeInput:SetText(tostring(value))
            TriggerRefresh()
        end)
        BindSliderInput(globalSizeSlider, globalSizeInput, 20, 80, 2, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.globalNodeSize = value
            dialog.globalSizeVal:SetText(tostring(value))
        end)
        dialog.globalSizeSlider = globalSizeSlider

        -- Node Line Size
        local lineSizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lineSizeLabel:SetPoint("TOPLEFT", globalSizeSlider, "BOTTOMLEFT", -4, -30)
        lineSizeLabel:SetText(L["AH_NODE_LINE_SPACING"] or "Node Line Spacing")
        lineSizeLabel:SetTextColor(1, 0.82, 0)

        local lineSizeSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        lineSizeSlider:SetPoint("TOPLEFT", lineSizeLabel, "BOTTOMLEFT", 4, -14)
        lineSizeSlider:SetWidth(110)
        lineSizeSlider:SetMinMaxValues(30, 100)
        lineSizeSlider:SetValueStep(2)
        lineSizeSlider:SetObeyStepOnDrag(true)

        local lineSizeInput = CreateNumericInput(settingsChild, lineSizeSlider)
        dialog.lineSizeInput = lineSizeInput

        local lineSizeResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        lineSizeResetBtn:SetSize(22, 22)
        lineSizeResetBtn:SetPoint("LEFT", lineSizeInput, "RIGHT", 10, 0)
        lineSizeResetBtn:SetText("")
        local lineSizeResetIcon = lineSizeResetBtn:CreateTexture(nil, "ARTWORK")
        lineSizeResetIcon:SetSize(14, 14)
        lineSizeResetIcon:SetPoint("CENTER", lineSizeResetBtn, "CENTER", 0, 0)
        lineSizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        lineSizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        lineSizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lineSizeResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeLineSize = nil
            dialog.lineSizeSlider.isResetting = true
            dialog.lineSizeSlider:SetValue(48)
            dialog.lineSizeVal:SetText("48")
            dialog.lineSizeInput:SetText("48")
            dialog.lineSizeSlider.isResetting = false
            TriggerRefresh()
        end)

        local lineSizeVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lineSizeVal:SetPoint("BOTTOM", lineSizeSlider, "TOP", 0, 2)
        dialog.lineSizeVal = lineSizeVal

        lineSizeSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeLineSize = value
            dialog.lineSizeVal:SetText(tostring(value))
            dialog.lineSizeInput:SetText(tostring(value))
            TriggerRefresh()
        end)
        BindSliderInput(lineSizeSlider, lineSizeInput, 30, 100, 2, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeLineSize = value
            dialog.lineSizeVal:SetText(tostring(value))
        end)
        dialog.lineSizeSlider = lineSizeSlider

        -- Node Position X
        local posXLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posXLabel:SetPoint("TOPLEFT", lineSizeSlider, "BOTTOMLEFT", -4, -30)
        posXLabel:SetText(L["AH_NODE_POS_X"] or "Node Position X")
        posXLabel:SetTextColor(1, 0.82, 0)

        local posXSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        posXSlider:SetPoint("TOPLEFT", posXLabel, "BOTTOMLEFT", 4, -14)
        posXSlider:SetWidth(110)
        posXSlider:SetMinMaxValues(-150, 150)
        posXSlider:SetValueStep(1)
        posXSlider:SetObeyStepOnDrag(true)

        local posXInput = CreateNumericInput(settingsChild, posXSlider)
        dialog.posXInput = posXInput

        local posXResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        posXResetBtn:SetSize(22, 22)
        posXResetBtn:SetPoint("LEFT", posXInput, "RIGHT", 10, 0)
        posXResetBtn:SetText("")
        local posXResetIcon = posXResetBtn:CreateTexture(nil, "ARTWORK")
        posXResetIcon:SetSize(14, 14)
        posXResetIcon:SetPoint("CENTER", posXResetBtn, "CENTER", 0, 0)
        posXResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        posXResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        posXResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        posXResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionX = nil end
            dialog.posXSlider.isResetting = true
            dialog.posXSlider:SetValue(0)
            dialog.posXVal:SetText("0")
            dialog.posXInput:SetText("0")
            dialog.posXSlider.isResetting = false
            TriggerRefresh()
        end)

        local posXVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posXVal:SetPoint("BOTTOM", posXSlider, "TOP", 0, 2)
        dialog.posXVal = posXVal

        posXSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionX = value end
            dialog.posXVal:SetText(tostring(value))
            dialog.posXInput:SetText(tostring(value))
            TriggerRefresh()
        end)
        BindSliderInput(posXSlider, posXInput, -150, 150, 1, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionX = value end
            dialog.posXVal:SetText(tostring(value))
        end)
        dialog.posXSlider = posXSlider

        -- Node Position Y
        local posYLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posYLabel:SetPoint("TOPLEFT", posXSlider, "BOTTOMLEFT", -4, -30)
        posYLabel:SetText(L["AH_NODE_POS_Y"] or "Node Position Y")
        posYLabel:SetTextColor(1, 0.82, 0)

        local posYSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        posYSlider:SetPoint("TOPLEFT", posYLabel, "BOTTOMLEFT", 4, -14)
        posYSlider:SetWidth(110)
        posYSlider:SetMinMaxValues(-150, 150)
        posYSlider:SetValueStep(1)
        posYSlider:SetObeyStepOnDrag(true)

        local posYInput = CreateNumericInput(settingsChild, posYSlider)
        dialog.posYInput = posYInput

        local posYResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        posYResetBtn:SetSize(22, 22)
        posYResetBtn:SetPoint("LEFT", posYInput, "RIGHT", 10, 0)
        posYResetBtn:SetText("")
        local posYResetIcon = posYResetBtn:CreateTexture(nil, "ARTWORK")
        posYResetIcon:SetSize(14, 14)
        posYResetIcon:SetPoint("CENTER", posYResetBtn, "CENTER", 0, 0)
        posYResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        posYResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        posYResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        posYResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionY = nil end
            dialog.posYSlider.isResetting = true
            dialog.posYSlider:SetValue(0)
            dialog.posYVal:SetText("0")
            dialog.posYInput:SetText("0")
            dialog.posYSlider.isResetting = false
            TriggerRefresh()
        end)

        local posYVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        posYVal:SetPoint("BOTTOM", posYSlider, "TOP", 0, 2)
        dialog.posYVal = posYVal

        -- Cooldown Text Size
        local textSizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        textSizeLabel:SetPoint("TOPLEFT", posYSlider, "BOTTOMLEFT", -4, -30)
        textSizeLabel:SetText(L["AH_TEXT_SIZE"] or "Text Size")
        textSizeLabel:SetTextColor(1, 0.82, 0)

        local textSizeSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        textSizeSlider:SetPoint("TOPLEFT", textSizeLabel, "BOTTOMLEFT", 4, -14)
        textSizeSlider:SetWidth(110)
        textSizeSlider:SetMinMaxValues(6, 24)
        textSizeSlider:SetValueStep(1)
        textSizeSlider:SetObeyStepOnDrag(true)

        local textSizeInput = CreateNumericInput(settingsChild, textSizeSlider)
        dialog.textSizeInput = textSizeInput

        local textSizeResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        textSizeResetBtn:SetSize(22, 22)
        textSizeResetBtn:SetPoint("LEFT", textSizeInput, "RIGHT", 10, 0)
        textSizeResetBtn:SetText("")
        local textSizeResetIcon = textSizeResetBtn:CreateTexture(nil, "ARTWORK")
        textSizeResetIcon:SetSize(14, 14)
        textSizeResetIcon:SetPoint("CENTER", textSizeResetBtn, "CENTER", 0, 0)
        textSizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        textSizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        textSizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        textSizeResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.cooldownTextSize = nil
            dialog.textSizeSlider.isResetting = true
            dialog.textSizeSlider:SetValue(11)
            dialog.textSizeVal:SetText("11")
            dialog.textSizeInput:SetText("11")
            dialog.textSizeSlider.isResetting = false
            ActionHub:UpdateWidgetCooldowns()
        end)

        local textSizeVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        textSizeVal:SetPoint("BOTTOM", textSizeSlider, "TOP", 0, 2)
        dialog.textSizeVal = textSizeVal

        -- Node Background Opacity (fade the dark square / ring behind icons)
        local bgAlphaLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bgAlphaLabel:SetPoint("TOPLEFT", textSizeSlider, "BOTTOMLEFT", -4, -30)
        bgAlphaLabel:SetText(L["AH_NODE_BG_ALPHA"] or "Background Opacity")
        bgAlphaLabel:SetTextColor(1, 0.82, 0)

        local bgAlphaSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        bgAlphaSlider:SetPoint("TOPLEFT", bgAlphaLabel, "BOTTOMLEFT", 4, -14)
        bgAlphaSlider:SetWidth(110)
        bgAlphaSlider:SetMinMaxValues(0, 100)
        bgAlphaSlider:SetValueStep(5)
        bgAlphaSlider:SetObeyStepOnDrag(true)
        if bgAlphaSlider.Low then bgAlphaSlider.Low:SetText("0%") end
        if bgAlphaSlider.High then bgAlphaSlider.High:SetText("100%") end
        if bgAlphaSlider.Text then bgAlphaSlider.Text:SetText("") end
        bgAlphaSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if dialog.bgAlphaInput and not dialog.bgAlphaInput:HasFocus() then
                dialog.bgAlphaInput:SetText(tostring(value))
            end
            if dialog.bgAlphaVal then dialog.bgAlphaVal:SetText(value .. "%") end
            if self.isSyncing then return end
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeBackgroundAlpha = value / 100
            ActionHub:RefreshAllWidgets()
            ActionHub:RefreshTab()
        end)
        dialog.bgAlphaSlider = bgAlphaSlider

        local bgAlphaInput = CreateNumericInput(settingsChild, bgAlphaSlider)
        dialog.bgAlphaInput = bgAlphaInput

        local bgAlphaResetBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        bgAlphaResetBtn:SetSize(22, 22)
        bgAlphaResetBtn:SetPoint("LEFT", bgAlphaInput, "RIGHT", 10, 0)
        local bgAlphaResetIcon = bgAlphaResetBtn:CreateTexture(nil, "ARTWORK")
        bgAlphaResetIcon:SetSize(14, 14)
        bgAlphaResetIcon:SetPoint("CENTER", bgAlphaResetBtn, "CENTER", 0, 0)
        bgAlphaResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        bgAlphaResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        bgAlphaResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bgAlphaResetBtn:SetScript("OnClick", function()
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeBackgroundAlpha = nil
            dialog.bgAlphaSlider.isSyncing = true
            dialog.bgAlphaSlider:SetValue(50)
            dialog.bgAlphaSlider.isSyncing = false
            if dialog.bgAlphaInput then dialog.bgAlphaInput:SetText("50") end
            if dialog.bgAlphaVal then dialog.bgAlphaVal:SetText("50%") end
            ActionHub:RefreshAllWidgets()
            ActionHub:RefreshTab()
        end)

        local bgAlphaVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bgAlphaVal:SetPoint("BOTTOM", bgAlphaSlider, "TOP", 0, 2)
        dialog.bgAlphaVal = bgAlphaVal

        local allowAnimCheck = CreateFrame("CheckButton", nil, settingsChild, "UICheckButtonTemplate")
        allowAnimCheck:SetPoint("TOPLEFT", bgAlphaSlider, "BOTTOMLEFT", -4, -14)
        allowAnimCheck:SetSize(22, 22)
        allowAnimCheck:SetScript("OnClick", function(self)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.allowAnimations = self:GetChecked()
            ActionHub:RefreshTab()
        end)
        dialog.allowAnimCheck = allowAnimCheck

        local allowAnimLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        allowAnimLabel:SetPoint("LEFT", allowAnimCheck, "RIGHT", 4, 0)
        allowAnimLabel:SetText(L["AH_ALLOW_ANIMATIONS"] or "Allow Animations")
        allowAnimLabel:SetTextColor(0.9, 0.9, 0.9)

        local showTooltipCheck = CreateFrame("CheckButton", nil, settingsChild, "UICheckButtonTemplate")
        showTooltipCheck:SetPoint("TOPLEFT", allowAnimCheck, "BOTTOMLEFT", 0, -4)
        showTooltipCheck:SetSize(22, 22)
        showTooltipCheck:SetScript("OnClick", function(self)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.showTooltip = self:GetChecked()
            ActionHub:RefreshWidget()
        end)
        dialog.showTooltipCheck = showTooltipCheck

        local showTooltipLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        showTooltipLabel:SetPoint("LEFT", showTooltipCheck, "RIGHT", 4, 0)
        showTooltipLabel:SetText(L["AH_SHOW_TOOLTIP"] or "Show Tooltip")
        showTooltipLabel:SetTextColor(0.9, 0.9, 0.9)

        local showTooltipInfo = CreateFrame("Button", nil, settingsChild)
        showTooltipInfo:SetSize(14, 14)
        showTooltipInfo:SetPoint("LEFT", showTooltipLabel, "RIGHT", 4, 0)
        local showTooltipInfoIcon = showTooltipInfo:CreateTexture(nil, "ARTWORK")
        showTooltipInfoIcon:SetAllPoints()
        showTooltipInfoIcon:SetTexture("Interface\\FriendsFrame\\InformationIcon")
        showTooltipInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["AH_SHOW_TOOLTIP_INFO"] or "you can drag and drop spells on your screen while holding shift", nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        showTooltipInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Ready Glow Settings
        local readyGlowCheck = CreateFrame("CheckButton", nil, settingsChild, "UICheckButtonTemplate")
        readyGlowCheck:SetPoint("TOPLEFT", showTooltipCheck, "BOTTOMLEFT", 0, -4)
        readyGlowCheck:SetSize(22, 22)
        readyGlowCheck:SetScript("OnClick", function(self)
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.showReadyGlow = self:GetChecked() end
            ActionHub:RefreshWidget()
        end)
        dialog.readyGlowCheck = readyGlowCheck

        local readyGlowLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowLabel:SetPoint("LEFT", readyGlowCheck, "RIGHT", 4, 0)
        readyGlowLabel:SetText(L["AH_SHOW_READY_GLOW"] or "Ready Highlight")
        readyGlowLabel:SetTextColor(0.9, 0.9, 0.9)

        local readyGlowHexLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowHexLabel:SetPoint("TOPLEFT", readyGlowCheck, "BOTTOMLEFT", 4, -8)
        readyGlowHexLabel:SetText(L["AH_READY_GLOW_COLOR"] or "Hex Color:")
        readyGlowHexLabel:SetTextColor(1, 0.82, 0)
        
        local readyGlowHexInput = CreateFrame("EditBox", nil, settingsChild, "InputBoxTemplate")
        readyGlowHexInput:SetSize(70, 20)
        readyGlowHexInput:SetPoint("LEFT", readyGlowHexLabel, "RIGHT", 8, 0)
        readyGlowHexInput:SetAutoFocus(false)
        readyGlowHexInput:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        
        local readyGlowColorBtn = CreateFrame("Button", nil, settingsChild)
        readyGlowColorBtn:SetSize(16, 16)
        readyGlowColorBtn:SetPoint("LEFT", readyGlowHexInput, "RIGHT", 6, 0)
        
        local readyGlowColorPreview = readyGlowColorBtn:CreateTexture(nil, "OVERLAY")
        readyGlowColorPreview:SetAllPoints()
        readyGlowColorPreview:SetTexture("Interface\\Buttons\\WHITE8x8")
        
        readyGlowColorBtn:SetScript("OnClick", function()
            local r, g, b = readyGlowColorPreview:GetVertexColor()
            local info = {}
            info.r, info.g, info.b = r, g, b
            info.hasOpacity = false
            info.swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local hex = string.format("%02X%02X%02X", nr*255, ng*255, nb*255)
                readyGlowHexInput:SetText(hex)
                local activeDB = ActionHub:GetActiveHubDB()
                local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                local s = slots[dialog.slotIndex]
                if s then s.readyGlowHex = hex end
                ActionHub:RefreshWidget()
                ActionHub:RefreshTab()
            end
            info.cancelFunc = function(prev)
                local hex = string.format("%02X%02X%02X", prev.r*255, prev.g*255, prev.b*255)
                readyGlowHexInput:SetText(hex)
                local activeDB = ActionHub:GetActiveHubDB()
                local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                local s = slots[dialog.slotIndex]
                if s then s.readyGlowHex = hex end
                ActionHub:RefreshWidget()
                ActionHub:RefreshTab()
            end
            if ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow(info)
            else
                ColorPickerFrame:Hide()
                ColorPickerFrame.func = info.swatchFunc
                ColorPickerFrame.cancelFunc = info.cancelFunc
                ColorPickerFrame.previousValues = info
                ColorPickerFrame:SetColorRGB(info.r, info.g, info.b)
                ColorPickerFrame:Show()
            end
        end)
        
        readyGlowHexInput:SetScript("OnTextChanged", function(self, userInput)
            local val = self:GetText()
            -- Strip # if present
            if string.sub(val, 1, 1) == "#" then val = string.sub(val, 2) end
            if #val == 6 then
                local r = tonumber(string.sub(val, 1, 2), 16)
                local g = tonumber(string.sub(val, 3, 4), 16)
                local b = tonumber(string.sub(val, 5, 6), 16)
                if r and g and b then
                    readyGlowColorPreview:SetVertexColor(r/255, g/255, b/255)
                    local activeDB = ActionHub:GetActiveHubDB()
                    local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                    local s = slots[dialog.slotIndex]
                    if s then s.readyGlowHex = val end
                    ActionHub:RefreshWidget()
                    ActionHub:RefreshTab()
                end
            else
                readyGlowColorPreview:SetVertexColor(0.5, 0.5, 0.5)
            end
        end)
        dialog.readyGlowHexInput = readyGlowHexInput
        dialog.readyGlowColorPreview = readyGlowColorPreview

        local readyGlowSizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowSizeLabel:SetPoint("TOPLEFT", readyGlowHexLabel, "BOTTOMLEFT", 0, -20)
        readyGlowSizeLabel:SetText(L["AH_READY_GLOW_SIZE"] or "Glow Width")
        readyGlowSizeLabel:SetTextColor(1, 0.82, 0)
        
        local readyGlowSizeSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        readyGlowSizeSlider:SetPoint("TOPLEFT", readyGlowSizeLabel, "BOTTOMLEFT", 4, -14)
        readyGlowSizeSlider:SetWidth(110)
        readyGlowSizeSlider:SetMinMaxValues(50, 200)
        readyGlowSizeSlider:SetValueStep(5)
        readyGlowSizeSlider:SetObeyStepOnDrag(true)
        if readyGlowSizeSlider.Low then readyGlowSizeSlider.Low:SetText("50%") end
        if readyGlowSizeSlider.High then readyGlowSizeSlider.High:SetText("200%") end
        if readyGlowSizeSlider.Text then readyGlowSizeSlider.Text:SetText("") end
        
        local readyGlowSizeVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowSizeVal:SetPoint("LEFT", readyGlowSizeSlider, "RIGHT", 8, 0)
        dialog.readyGlowSizeVal = readyGlowSizeVal
        
        readyGlowSizeSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if dialog.readyGlowSizeVal then dialog.readyGlowSizeVal:SetText(value .. "%") end
            if self.isSyncing then return end
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.readyGlowSize = value end
            ActionHub:RefreshWidget()
            ActionHub:RefreshTab()
        end)
        dialog.readyGlowSizeSlider = readyGlowSizeSlider
        
        local readyGlowAlphaLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowAlphaLabel:SetPoint("TOPLEFT", readyGlowSizeSlider, "BOTTOMLEFT", -4, -14)
        readyGlowAlphaLabel:SetText(L["AH_READY_GLOW_ALPHA"] or "Glow Fade")
        readyGlowAlphaLabel:SetTextColor(1, 0.82, 0)
        
        local readyGlowAlphaSlider = CreateFrame("Slider", nil, settingsChild, "OptionsSliderTemplate")
        readyGlowAlphaSlider:SetPoint("TOPLEFT", readyGlowAlphaLabel, "BOTTOMLEFT", 4, -14)
        readyGlowAlphaSlider:SetWidth(110)
        readyGlowAlphaSlider:SetMinMaxValues(10, 100)
        readyGlowAlphaSlider:SetValueStep(5)
        readyGlowAlphaSlider:SetObeyStepOnDrag(true)
        if readyGlowAlphaSlider.Low then readyGlowAlphaSlider.Low:SetText("10%") end
        if readyGlowAlphaSlider.High then readyGlowAlphaSlider.High:SetText("100%") end
        if readyGlowAlphaSlider.Text then readyGlowAlphaSlider.Text:SetText("") end
        
        local readyGlowAlphaVal = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        readyGlowAlphaVal:SetPoint("LEFT", readyGlowAlphaSlider, "RIGHT", 8, 0)
        dialog.readyGlowAlphaVal = readyGlowAlphaVal
        
        readyGlowAlphaSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if dialog.readyGlowAlphaVal then dialog.readyGlowAlphaVal:SetText(value .. "%") end
            if self.isSyncing then return end
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.readyGlowAlpha = value end
            ActionHub:RefreshWidget()
            ActionHub:RefreshTab()
        end)
        dialog.readyGlowAlphaSlider = readyGlowAlphaSlider

        -- Sidebar Tabs Visibility Settings
        local tabsHeader = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabsHeader:SetPoint("TOPLEFT", readyGlowAlphaLabel, "BOTTOMLEFT", -4, -40)
        tabsHeader:SetText(L["AH_SIDEBAR_TABS"] or "Sidebar Tabs")
        tabsHeader:SetTextColor(1, 0.82, 0)

        local tabCheckboxes = {}
        local tabDefs = {
            { key = "toy",      label = L["TAB_TOYMIX"] or "ToyMix" },
            { key = "emote",    label = L["TAB_REACTIONS"] or "Reactions" },
            { key = "trigger",  label = L["TAB_TRIGGERS"] or "Triggers" },
            { key = "marker",   label = L["TAB_MARKERS"] or "Markers" },
            { key = "mount",    label = L["TAB_MOUNTS"] or "Mounts" },
            { key = "item",     label = L["TAB_ITEMS"] or "Items" },
            { key = "spell",    label = L["TAB_SPELLS"] or "Spellbook" },
        }

        local prevAnchor = tabsHeader
        for i, def in ipairs(tabDefs) do
            local check = CreateFrame("CheckButton", nil, settingsChild, "UICheckButtonTemplate")
            if i == 1 then
                check:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", -4, -10)
            else
                check:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, -6)
            end
            check:SetSize(22, 22)
            
            local lbl = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            lbl:SetPoint("LEFT", check, "RIGHT", 4, 0)
            lbl:SetText(def.label)
            lbl:SetTextColor(0.9, 0.9, 0.9)

            check:SetScript("OnClick", function(self)
                local activeDB = ActionHub:GetActiveHubDB()
                activeDB.visibleTabs = activeDB.visibleTabs or {
                    toy = true,
                    emote = true,
                    trigger = true,
                    marker = true,
                    mount = false,
                    item = false,
                    spell = false,
                    settings = true,
                }
                activeDB.visibleTabs[def.key] = self:GetChecked()

                -- Ensure at least one tab is shown
                local anyShown = false
                for _, k in ipairs({"toy", "emote", "trigger", "marker", "mount", "item", "spell"}) do
                    if activeDB.visibleTabs[k] then
                        anyShown = true
                        break
                    end
                end
                if not anyShown then
                    self:SetChecked(true)
                    activeDB.visibleTabs[def.key] = true
                    return
                end

                ActionHub:RefreshSidebarCategories()
                ActionHub:RefreshPickerList()
            end)

            tabCheckboxes[def.key] = check
            prevAnchor = check
        end
        dialog.tabCheckboxes = tabCheckboxes

        -- Refresh Toys / Mounts
        local refreshCollectLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        refreshCollectLabel:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 4, -20)
        refreshCollectLabel:SetText(L["SETTINGS_REFRESH_COLLECTIONS"] or "Refresh Collections")
        refreshCollectLabel:SetTextColor(1, 0.82, 0)

        local refreshToysLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        refreshToysLabel:SetPoint("TOPLEFT", refreshCollectLabel, "BOTTOMLEFT", 0, -12)
        refreshToysLabel:SetText(L["SETTINGS_BTN_REFRESH_TOYS"] or "Refresh Toys")

        local refreshToysBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        refreshToysBtn:SetSize(26, 26)
        refreshToysBtn:SetPoint("LEFT", refreshToysLabel, "RIGHT", 10, 0)
        refreshToysBtn:SetText("")
        local toysIcon = refreshToysBtn:CreateTexture(nil, "ARTWORK")
        toysIcon:SetSize(14, 14)
        toysIcon:SetPoint("CENTER", refreshToysBtn, "CENTER", 0, 0)
        toysIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        refreshToysBtn:SetScript("OnClick", function()
            if OxedHub.Toys and OxedHub.Toys.CacheToyData then
                OxedHub.Toys:CacheToyData(true)
                ActionHub:RefreshPickerList()
                -- Keep the Toys tab and OxedRing picker in step as well.
                if OxedHub.Toys.RefreshToyConsumers then
                    OxedHub.Toys:RefreshToyConsumers()
                end
            end
        end)

        local refreshMountsLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        refreshMountsLabel:SetPoint("TOPLEFT", refreshToysLabel, "BOTTOMLEFT", 0, -16)
        refreshMountsLabel:SetText(L["SETTINGS_BTN_REFRESH_MOUNTS"] or "Refresh Mounts")

        local refreshMountsBtn = CreateFrame("Button", nil, settingsChild, "UIPanelButtonTemplate")
        refreshMountsBtn:SetSize(26, 26)
        refreshMountsBtn:SetPoint("LEFT", refreshMountsLabel, "RIGHT", 10, 0)
        refreshMountsBtn:SetText("")
        local mountsIcon = refreshMountsBtn:CreateTexture(nil, "ARTWORK")
        mountsIcon:SetSize(14, 14)
        mountsIcon:SetPoint("CENTER", refreshMountsBtn, "CENTER", 0, 0)
        mountsIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        refreshMountsBtn:SetScript("OnClick", function()
            if OxedHub.Mounts and OxedHub.Mounts.CacheMountData then
                OxedHub.Mounts:CacheMountData(true)
            end
            ActionHub:RefreshPickerList()
            -- Mount lists are shared, so refresh the OxedRing picker too.
            if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshPickerList then
                pcall(function() OxedHub.OxedRingEditor:RefreshPickerList() end)
            end
        end)

        local refreshNote = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        refreshNote:SetPoint("TOPLEFT", refreshMountsLabel, "BOTTOMLEFT", 0, -12)
        refreshNote:SetWidth(220)
        refreshNote:SetJustifyH("LEFT")
        refreshNote:SetText(L["SETTINGS_REFRESH_WARNING"] or "* If you have a lot of toys/mounts the screen can freeze for 1-2 sec.")
        refreshNote:SetTextColor(0.72, 0.72, 0.72)

        posYSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionY = value end
            dialog.posYVal:SetText(tostring(value))
            dialog.posYInput:SetText(tostring(value))
            TriggerRefresh()
        end)
        BindSliderInput(posYSlider, posYInput, -150, 150, 1, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
            local s = slots[dialog.slotIndex]
            if s then s.nodePositionY = value end
            dialog.posYVal:SetText(tostring(value))
        end)
        dialog.posYSlider = posYSlider

        textSizeSlider:SetScript("OnValueChanged", function(self, value)
            if self.isResetting then return end
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.cooldownTextSize = value
            dialog.textSizeVal:SetText(tostring(value))
            dialog.textSizeInput:SetText(tostring(value))
            ActionHub:UpdateWidgetCooldowns()
        end)
        BindSliderInput(textSizeSlider, textSizeInput, 6, 24, 1, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.cooldownTextSize = value
            dialog.textSizeVal:SetText(tostring(value))
            ActionHub:UpdateWidgetCooldowns()
        end)
        dialog.textSizeSlider = textSizeSlider

        BindSliderInput(bgAlphaSlider, bgAlphaInput, 0, 100, 5, function(value)
            local activeDB = ActionHub:GetActiveHubDB()
            activeDB.nodeBackgroundAlpha = value / 100
            dialog.bgAlphaVal:SetText(value .. "%")
            ActionHub:RefreshAllWidgets()
            ActionHub:RefreshTab()
        end)

        local testBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        testBtn:SetSize(70, 24)
        testBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 18, 14)
        testBtn:SetText(L["BTN_TEST"] or "Test")
        testBtn:SetScript("OnClick", function()
            local emote = ActionHub:GetSelectedEmote()
            if emote then ActionHub:TriggerEmoteById(emote) end
        end)


        self.pickerDialog = dialog
    end

    dialog.slotIndex = slotIndex
    dialog.slotSide = slotSide or self:GetEditedSide()
    if not dialog.selectedType then
        dialog.selectedType = "toy"
    end

    dialog.toySearchText = ""
    if dialog.toySearchBox then
        dialog.toySearchBox.isSyncingText = true
        dialog.toySearchBox:SetText("")
        dialog.toySearchBox.isSyncingText = false
    end

    local activeDB = self:GetActiveHubDB()
    local slots = self:GetSlotsForSide(activeDB, dialog.slotSide)
    local s = slots[slotIndex]
    if s and s.type == "emote" then
        ActionHub.selectedEmoteId = s.id
    else
        ActionHub.selectedEmoteId = nil
    end

    dialog:Show()
    self:RefreshSidebarCategories()
    self:RefreshPickerList()
    self:RefreshTab()
    if OxedHub.UI and OxedHub.UI.ApplyGlobalTextSize then
        OxedHub.UI:ApplyGlobalTextSize()
    end
end

function ActionHub:GetSelectedEmote()
    return ActionHub.selectedEmoteId
end

function ActionHub:RefreshPickerList()
    local dialog = self.pickerDialog
    if not dialog then return end

    local child = dialog.scrollChild
    if not child then return end

    if dialog.mountCountLabel then
        dialog.mountCountLabel:Hide()
    end

    -- Update tab highlights
    if dialog.sidebarButtons then
        for _, b in ipairs(dialog.sidebarButtons) do
            if b.catType == dialog.selectedType then
                b.border:SetVertexColor(1, 0.82, 0)  -- Bright gold when selected
            else
                b.border:SetVertexColor(0.6, 0.5, 0.3)  -- Dim bronze when not selected
            end
        end
    end

    if dialog.markerHeaders then
        for _, h in ipairs(dialog.markerHeaders) do
            h:Hide()
        end
    end

    local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
    local currentSlot = slots[dialog.slotIndex]

    -- Reset scroll anchor to full height for all tabs except emote
    dialog.scroll:ClearAllPoints()
    dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
    dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 36)

    if dialog.selectedType == "toy" then
        -- Show Macro Grid
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Show()
        dialog.showToysLabel:Show()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.showToysCheck:SetChecked(dialog.showDirectToys and true or false)
        dialog.sectionInfo:SetText(dialog.showDirectToys and (L["AH_PICK_TOY"] or "Pick a Toy for this slot") or (L["AH_PICK_TOYMIX"] or "Pick a ToyMix for this slot"))
        if dialog.showDirectToys then
            dialog.toySearchBox:Show()
            local desiredSearch = dialog.toySearchText or ""
            if dialog.toySearchBox:GetText() ~= desiredSearch then
                dialog.toySearchBox.isSyncingText = true
                dialog.toySearchBox:SetText(desiredSearch)
                dialog.toySearchBox.isSyncingText = false
            end
        else
            dialog.toySearchBox:Hide()
        end

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local items = {}
        if dialog.showDirectToys then
            if OxedHub.Toys and OxedHub.Toys.CacheToyData and (not OxedHub.Toys.toyDataInitialized or not OxedHub.Toys.toyIDs or #OxedHub.Toys.toyIDs == 0) then
                OxedHub.Toys:CacheToyData(true)
            end

            local toyIDs = OxedHub.Toys and OxedHub.Toys.toyIDs or {}
            local toyCache = OxedHub.Toys and OxedHub.Toys.toyCache or {}
            local searchText = (dialog.toySearchText or ""):lower()
            local totalToys = 0
            for _, toyID in ipairs(toyIDs) do
                if PlayerHasToy(toyID) then
                    local cached = toyCache[toyID] or {}
                    local toyName, toyIcon = GetDirectToyDisplay(toyID)
                    local displayName = cached.name or toyName or ("Toy " .. tostring(toyID))
                    if displayName then
                        totalToys = totalToys + 1
                        if searchText == "" or displayName:lower():find(searchText, 1, true) then
                            table.insert(items, {
                                type = "toy",
                                assignmentMode = "direct",
                                id = toyID,
                                name = displayName,
                                icon1 = cached.icon or toyIcon,
                            })
                        end
                    end
                end
            end

            if dialog.mountCountLabel then
                local labelText = "Toys: " .. totalToys
                if searchText ~= "" then
                    labelText = "Found: " .. #items .. " / " .. totalToys
                end
                dialog.mountCountLabel:SetText(labelText)
                dialog.mountCountLabel:Show()
            end
        else
            local mixes = OxedHub.db.profile.toyMixes or {}
            local filter = OxedHub.db.profile.settings.filterByClass

            for mixName, mixData in pairs(mixes) do
                local show = true
                if filter and mixData.slots then
                    for _, slot in ipairs(mixData.slots) do
                        if slot and slot.type == "spell" then
                            if not OxedHub:IsSpellRelevant(slot.id) then
                                show = false
                                break
                            end
                        end
                    end
                end

                if show and OxedHub.Toys and OxedHub.Toys.GetMixToyAvailability then
                    local _, missingToys = OxedHub.Toys:GetMixToyAvailability(mixData)
                    if missingToys and missingToys > 0 then
                        show = false
                    end
                end

                if show then
                    local customIcon = OxedHub.Toys and OxedHub.Toys.GetMixCustomIcon and OxedHub.Toys:GetMixCustomIcon(mixName)
                    local icon1, icon2, icon3, icon4
                    if customIcon then
                        icon1 = customIcon
                    else
                        icon1 = "Interface\\Icons\\INV_Misc_QuestionMark"
                        icon2 = "Interface\\Icons\\INV_Misc_QuestionMark"
                        if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                            icon1, icon2, icon3, icon4 = OxedHub.Toys:GetMixSlotIcons(mixName)
                        end
                    end
                    table.insert(items, { type = "toy", assignmentMode = "mix", id = mixName, name = mixName, icon1 = icon1, icon2 = icon2, icon3 = icon3, icon4 = icon4 })
                end
            end
        end

        table.sort(items, function(a, b) return a.name < b.name end)

        local btnSize = 48
        local spacing = 8
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -y * (btnSize + spacing + 18) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local q = "Interface\\Icons\\INV_Misc_QuestionMark"
            if item.icon2 and item.icon1 ~= q and item.icon2 ~= q and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                local splitIcon = OxedHub.Toys:CreateSplitIcon(btn, btnSize - 6, item.icon1, item.icon2, item.icon3, item.icon4)
                splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            else
                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon1 or q)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12) -- Prevent multiple lines if too long
            label:SetTextColor(0.90, 0.85, 0.80, 1)

            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

            -- Click assigns to currently selected slot
            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "toy"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].assignmentMode = item.assignmentMode
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
            end)

            -- Drag support: start dragging this macro
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "toy", id = item.id, assignmentMode = item.assignmentMode, icon = item.icon1 }
                -- Create floating drag icon
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    -- Find which ring slot the cursor is over
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.assignmentMode = ActionHub.dragData.assignmentMode
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 20) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "emote" then
        -- Show Reaction Editor Split Screen
        dialog.scroll:ClearAllPoints()
        dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
        dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 240)
        dialog.scroll:Show()
        child:Show()
        
        dialog.settingsTabFrame:Hide()
        
        dialog.editor:ClearAllPoints()
        dialog.editor:SetPoint("TOPLEFT", dialog.scroll, "BOTTOMLEFT", -16, 0)
        dialog.editor:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 36)
        dialog.editor:Show()
        
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_PICK_EMOJI"] or "Pick an Emoji, then configure it below")
        dialog.reactionTabFrame:Show()
        dialog.macroTabFrame:Hide()

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local items = {}
        for _, r in ipairs(OxedHub.CONFIG.REACTIONS or {}) do table.insert(items, r) end
        for _, r in pairs(OxedHub.db.profile.customReactions or {}) do 
            if r.icon and r.name then
                table.insert(items, r) 
            end
        end

        local btnSize = 44
        local spacing = 6
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing + 14) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            
            local isSelected = false
            local s = currentSlot
            local selectedBase = nil
            if s and s.type == "emote" then
                local map = OxedHub.db and OxedHub.db.profile.emotionMappings and OxedHub.db.profile.emotionMappings[s.id]
                selectedBase = map and map.emote or s.id
            end
            
            if ActionHub.selectedEmoteId == item.id or (selectedBase and selectedBase == item.id) then
                isSelected = true
            end

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12)

            if isSelected then
                btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                btn:SetBackdropColor(0.25, 0.2, 0.05, 0.9)
                if not btn.selectedOverlay then
                    btn.selectedOverlay = btn:CreateTexture(nil, "OVERLAY")
                    btn.selectedOverlay:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                    btn.selectedOverlay:SetBlendMode("ADD")
                end
                btn.selectedOverlay:ClearAllPoints()
                btn.selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", -20, 20)
                btn.selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 20, -20)
                btn.selectedOverlay:Show()
                iconTex:SetAlpha(1.0)
                label:SetTextColor(1, 0.82, 0, 1)
            else
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
                if btn.selectedOverlay then
                    btn.selectedOverlay:Hide()
                end
                iconTex:SetAlpha(0.5)
                label:SetTextColor(0.7, 0.65, 0.6, 0.8)
            end

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if type(item.id) == "string" and string.match(item.id, "^custom_") then
                        -- Loop through and delete matching keys
                        for k, v in pairs(OxedHub.db.profile.customReactions) do
                            if type(v) == "table" and v.id == item.id then
                                OxedHub.db.profile.customReactions[k] = nil
                            end
                        end
                        if ActionHub.selectedEmoteId == item.id then
                            ActionHub.selectedEmoteId = nil
                        end
                        ActionHub:RefreshPickerList()
                    end
                    return
                end

                ActionHub.selectedEmoteId = item.id
                
                local activeDB = ActionHub:GetActiveHubDB()
                local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                if slots and dialog.slotIndex then
                    slots[dialog.slotIndex] = slots[dialog.slotIndex] or {}
                    local slot = slots[dialog.slotIndex]
                    slot.type = "emote"
                    slot.id = item.id
                    slot.label = item.name
                    slot.icon = item.icon
                    slot.assignmentMode = nil
                    slot.requiresParty = nil
                    slot.requiresTarget = nil
                end

                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
            end)

            -- Add tooltip hint for right-click delete
            if type(item.id) == "string" and string.match(item.id, "^custom_") then
                btn:SetScript("OnEnter", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(1, 0.82, 0, 0.8) 
                        iconTex:SetAlpha(1.0)
                    end 
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(item.name)
                    GameTooltip:AddLine(L["RIGHT_CLICK_TO_DELETE"] or "Right-Click to delete", 1, 0.2, 0.2)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) 
                        iconTex:SetAlpha(0.5)
                    end 
                    GameTooltip:Hide()
                end)
            else
                btn:SetScript("OnEnter", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(1, 0.82, 0, 0.8) 
                        iconTex:SetAlpha(1.0)
                    end 
                end)
                btn:SetScript("OnLeave", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) 
                        iconTex:SetAlpha(0.5)
                    end 
                end)
            end

            -- Drag support: drag this emoji onto a hub button
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetFrameStrata("TOOLTIP")
                    f:SetSize(40, 40)
                    f.tex = f:CreateTexture(nil, "OVERLAY")
                    f.tex:SetAllPoints()
                    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    f:EnableMouse(false)
                    f:SetScript("OnUpdate", function(fs)
                        local cx, cy = GetCursorPosition()
                        local sc = UIParent:GetEffectiveScale()
                        fs:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/sc, cy/sc)
                    end)
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragPayload = { type = "emote", id = item.id, name = item.name, icon = item.icon }
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then ActionHub.dragIcon:Hide() end
                local payload = ActionHub.dragPayload
                ActionHub.dragPayload = nil
                if not payload then return end

                local targetBtn = GetMouseFocus and GetMouseFocus() or nil

                -- Fallback to IsMouseOver if GetMouseFocus didn't get the preview button
                if not (targetBtn and targetBtn.slotIndex) then
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, pb in ipairs(tab.ringButtons) do
                            if pb and pb:IsShown() and pb:IsMouseOver() and pb.slotIndex then
                                targetBtn = pb
                                break
                            end
                        end
                    end
                end

                -- Fallback to live widgets
                if not (targetBtn and targetBtn.slotIndex) then
                    for _, w in ipairs(ActionHub.widgets or {}) do
                        if w and w.buttons then
                            for _, wb in ipairs(w.buttons) do
                                if wb and wb:IsShown() and wb:IsMouseOver() then
                                    targetBtn = wb
                                    break
                                end
                            end
                        end
                        if targetBtn and targetBtn.slotIndex then break end
                    end
                end

                if targetBtn and targetBtn.slotIndex and targetBtn.slotSide then
                    local activeDB = ActionHub:GetActiveHubDB()
                    local slots = ActionHub:GetSlotsForSide(activeDB, targetBtn.slotSide)
                    if not slots[targetBtn.slotIndex] then
                        slots[targetBtn.slotIndex] = {}
                    end
                    local slot = slots[targetBtn.slotIndex]
                    slot.type = payload.type
                    slot.id = payload.id
                    slot.label = payload.name
                    slot.icon = payload.icon
                    slot.assignmentMode = nil
                    slot.requiresParty = nil
                    slot.requiresTarget = nil

                    ActionHub.selectedEmoteId = payload.id
                    C_Timer.After(0, function()
                        ActionHub:ShowSlotPicker(targetBtn.slotIndex, targetBtn.slotSide)
                        ActionHub:RefreshTab()
                        ActionHub:RefreshPickerList()
                    end)
                end
            end)

            x = x + 1
            if x >= cols then
                x = 0
                y = y + 1
            end
        end

        -- Add New Button
        local addBtn = CreateFrame("Button", nil, child, "BackdropTemplate")
        addBtn:SetSize(btnSize, btnSize)
        addBtn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing + 14) - 4)
        addBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
        })
        addBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        addBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.8)

        local addIcon = addBtn:CreateTexture(nil, "ARTWORK")
        addIcon:SetSize(24, 24)
        addIcon:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        addIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\add")
        addIcon:SetVertexColor(0.3, 0.8, 0.3)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addLabel:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
        addLabel:SetText(L["AH_ADD_NEW"] or "Add New")
        addLabel:SetWidth(btnSize + 4)
        addLabel:SetJustifyH("CENTER")
        addLabel:SetHeight(10)
        addLabel:SetTextColor(0.3, 0.8, 0.3)

        addBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.5, 1, 0.5, 1) end)
        addBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.8) end)

        addBtn:SetScript("OnClick", function()
            StaticPopupDialogs["OXEDHUB_NEW_EMOJI"] = {
                text = L["NEW_REACTION_TITLE"] or "Enter a name for the new custom reaction:",
                button1 = ACCEPT,
                button2 = CANCEL,
                hasEditBox = true,
                OnAccept = function(self)
                    local text = self.EditBox and self.EditBox:GetText() or _G[self:GetName().."EditBox"]:GetText()
                    if text and text ~= "" and OxedHub.IconPicker then
                        OxedHub.IconPicker:Open({
                            title = string.format(L["PICK_ICON_FOR"] or "Pick an Icon for %s", text),
                            customRingIconsOnly = true,
                            onSelect = function(value, texture)
                                OxedHub.db.profile.customReactions = OxedHub.db.profile.customReactions or {}
                                local id = "custom_" .. time()
                                OxedHub.db.profile.customReactions[id] = {
                                    id = id,
                                    name = text,
                                    icon = texture,
                                    command = ""
                                }
                                ActionHub:RefreshPickerList()
                            end
                        })
                    end
                end,
                EditBoxOnEnterPressed = function(self)
                    local parent = self:GetParent()
                    StaticPopup_OnClick(parent, 1)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("OXEDHUB_NEW_EMOJI")
        end)
        
        -- Set scrollchild size
        child:SetHeight((y + 1) * (btnSize + spacing + 14) + 10)
        child:SetWidth(cols * (btnSize + spacing))

        local currentEmote = "None"
        if currentSlot then
            currentEmote = ActionHub.selectedEmoteId
            if not currentEmote then
                currentEmote = (currentSlot.type == "emote") and currentSlot.id or "None"
            end
        end
        local hasEmote = (currentEmote and currentEmote ~= "None")
        local profile = OxedHub.db and OxedHub.db.profile
        local mappings = profile and profile.emotionMappings or {}
        local mapping = mappings[currentEmote] or {}

        -- Build option lists for labels
        local soundOpts = {{label = "None", value = nil}}
        for id, sound in pairs(profile and profile.customSounds or {}) do
            table.insert(soundOpts, {label = sound.name or id, value = id})
        end
        local animOpts = {{label = "None", value = nil}}
        for id, anim in pairs(profile and profile.animations or {}) do
            table.insert(animOpts, {label = anim.name or id, value = id})
        end
        local emoteOpts = {{label = "None", value = nil}}
        local predefined = {"APPLAUD","BEG","BOW","CHEER","CHICKEN","CRY","DANCE","FLEX","FLIRT","GASP","KISS","LAUGH","LEAN","POINT","ROAR","RUDE","SALUTE","SHY","SIGH","SLEEP","TAUNT","WAVE"}
        for _, cmd in ipairs(predefined) do
            local display = cmd:sub(1,1) .. cmd:sub(2):lower()
            table.insert(emoteOpts, {label = display, value = cmd})
        end
        local chatOpts = {{label = "None", value = nil}}
        for id, chat in pairs(profile and profile.chatTemplates or {}) do
            table.insert(chatOpts, {label = chat.name or chat.text or id, value = id})
        end
        local toyMixOpts = {{label = "None", value = nil}}
        for name in pairs(profile and profile.toyMixes or {}) do
            table.insert(toyMixOpts, {label = name, value = name})
        end

        local function getLabel(opts, val)
            if not val then return "None" end
            for _, o in ipairs(opts) do if o.value == val then return o.label end end
            return tostring(val)
        end

        dialog.soundPicker.button:SetText(getLabel(soundOpts, mapping.sound))
        dialog.animationPicker.button:SetText(getLabel(animOpts, mapping.animation))
        dialog.animCheck:SetChecked(mapping.animationUseCustomPosition or false)
        
        dialog.soundPicker.button:SetEnabled(hasEmote)
        dialog.animationPicker.button:SetEnabled(hasEmote)
        dialog.animCheck:SetEnabled(hasEmote)
        if dialog.setPosBtn then
            dialog.setPosBtn:SetEnabled(hasEmote and (mapping.animationUseCustomPosition or false))
        end
        dialog.emotePicker.button:SetEnabled(hasEmote)
        dialog.chatPicker.button:SetEnabled(hasEmote)
        dialog.toyMacroPicker.button:SetEnabled(hasEmote)

        dialog.emotePicker.button:SetText(getLabel(emoteOpts, mapping.emote))
        dialog.chatPicker.button:SetText(getLabel(chatOpts, mapping.chat))
        dialog.toyMacroPicker.button:SetText(getLabel(toyMixOpts, mapping.toyMacro))
    elseif dialog.selectedType == "mount" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Show()
        local desiredSearch = dialog.toySearchText or ""
        if dialog.toySearchBox:GetText() ~= desiredSearch then
            dialog.toySearchBox.isSyncingText = true
            dialog.toySearchBox:SetText(desiredSearch)
            dialog.toySearchBox.isSyncingText = false
        end
        dialog.sectionInfo:SetText(L["AH_PICK_MOUNT"] or "Pick a Mount for this slot")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        -- Shared, SavedVariables-backed mount list (same source as OxedRing).
        -- Built once; rebuilt only when the player presses Refresh Mounts.
        local items = OxedHub.Mounts and OxedHub.Mounts:GetMounts() or {}

        local totalMounts = #items
        local filterText = (dialog.toySearchText or ""):lower()
        if filterText ~= "" then
            local filtered = {}
            for _, item in ipairs(items) do
                if item.name:lower():find(filterText, 1, true) then
                    table.insert(filtered, item)
                end
            end
            items = filtered
        end

        if dialog.mountCountLabel then
            local labelText = "Mounts: " .. totalMounts
            if filterText ~= "" then
                labelText = "Found: " .. #items .. " / " .. totalMounts
            end
            dialog.mountCountLabel:SetText(labelText)
            dialog.mountCountLabel:Show()
        end

        -- Grid layout matching the OxedRing mount picker (icon-only, no name labels)
        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetMountBySpellID and item.spellID then
                    GameTooltip:SetMountBySpellID(item.spellID)
                else
                    GameTooltip:SetText(item.name)
                end
                GameTooltip:AddLine("|cff00ff00Click to assign to this slot|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "mount"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = nil
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "mount", id = item.id, label = item.name, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = nil
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 16)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "item" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["RING_PICK_BAG_ITEM"] or "Pick a Potion, Flask, or Food from your bags")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        -- Scan player bags for consumable items (Potions, Flasks, Food)
        local items = {}
        local seenIDs = {}
        for bag = 0, 4 do
            local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container and C_Container.GetContainerItemInfo(bag, slot) or nil
                local itemID = info and info.itemID or nil
                if not itemID and not C_Container then
                    itemID = GetContainerItemID(bag, slot)
                end
                if itemID and not seenIDs[itemID] then
                    seenIDs[itemID] = true
                    local itemName, _, _, _, _, itemType, itemSubType, _, _, itemIcon = GetItemInfo(itemID)
                    if itemType == "Consumable" then
                        local cat = itemSubType or "Other"
                        local count = GetItemCount(itemID) or 0
                        table.insert(items, {
                            type = "item",
                            id = itemID,
                            name = itemName or ("Item #" .. itemID),
                            icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                            category = cat,
                            count = count,
                        })
                    end
                end
            end
        end

        -- Sort by category then name
        table.sort(items, function(a, b)
            if a.category ~= b.category then
                local order = { Potion = 1, Flask = 2, Food = 3 }
                local orderA = order[a.category] or 9
                local orderB = order[b.category] or 9
                if orderA ~= orderB then
                    return orderA < orderB
                else
                    return a.category < b.category
                end
            end
            return (a.name or "") < (b.name or "")
        end)

        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -(y * (btnSize + spacing)) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            if item.count and item.count > 1 then
                local countLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                countLabel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
                countLabel:SetText(item.count)
                countLabel:SetTextColor(1, 1, 1)
            end

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetItemByID(item.id)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "item"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = "direct"
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "item", id = item.id, label = item.name, icon = item.icon, assignmentMode = "direct" }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = "direct"
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "spell" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["RING_PICK_SPELL"] or "Pick a spell from your spellbook")

        for _, c in ipairs({child:GetChildren()}) do
            c:Hide(); c:SetParent(nil)
        end

        -- Reuse the shared spellbook scanner (OxedRing built it first).
        local items = {}
        if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.GetPlayerSpellList then
            items = OxedHub.OxedRingEditor:GetPlayerSpellList() or {}
        end

        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -(y * (btnSize + spacing)) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if item.id then GameTooltip:SetSpellByID(item.id) else GameTooltip:SetText(item.name) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "spell"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = nil
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then ActionHub:RefreshWidget() end
            end)

            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "spell", id = item.id, label = item.name, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = nil
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "trigger" then
        -- Show Trigger Grid
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.toySearchBox:Hide()
        dialog.allTriggersCheck:Show()
        dialog.allTriggersLabel:Show()
        dialog.allTriggersHelp:Show()
        dialog.sectionInfo:SetText(L["AH_PICK_TRIGGER"] or "Pick a Trigger for this slot")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local items = {}
        local triggers = OxedHub.db.profile.triggers or {}
        local filter = OxedHub.db.profile.settings.filterByClass
        local showAll = dialog.showAllTriggers

        for id, trg in pairs(triggers) do
            -- By default only show Spell Cast triggers; show all types when checkbox is checked
            if showAll or trg.event == "UNIT_SPELLCAST_SUCCEEDED" then
                local show = true
                if filter and trg.conditions and trg.conditions.spellID then
                    if not OxedHub:IsSpellRelevant(trg.conditions.spellID) then
                        show = false
                    end
                end

                if show then
                    local spellInfo = trg.conditions and trg.conditions.spellID and C_Spell.GetSpellInfo(trg.conditions.spellID)
                    local icon = (OxedHub.Triggers and OxedHub.Triggers.GetTriggerDisplayIcon and OxedHub.Triggers:GetTriggerDisplayIcon(trg))
                        or (spellInfo and spellInfo.iconID)
                        or "Interface\\Icons\\INV_Misc_QuestionMark"
                    local name = trg.name or (spellInfo and spellInfo.name) or id
                    table.insert(items, { type = "trigger", id = id, name = name, icon = icon })
                end
            end
        end

        table.sort(items, function(a, b) return a.name < b.name end)

        local btnSize = 48
        local spacing = 8
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -y * (btnSize + spacing + 18) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12)
            label:SetTextColor(0.90, 0.85, 0.80, 1)

            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "trigger"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].assignmentMode = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "trigger", id = item.id, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            local isOver = false
                            if rb and rb.IsMouseOver then
                                isOver = rb:IsMouseOver()
                            elseif rb and type(_G.MouseIsOver) == "function" then
                                isOver = _G.MouseIsOver(rb)
                            end
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and isOver then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.assignmentMode = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 20) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "marker" then
        -- Show Marker Grid (Raid Targets + Flares + Pings)
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_PICK_RAID_TARGET"] or "Pick a Raid Target, Flare, or Ping")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local categories = {
            {
                name = "Marks",
                items = {
                    { type = "marker", id = 1, name = "Target: Star", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "marker", id = 2, name = "Target: Circle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "marker", id = 3, name = "Target: Diamond", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "marker", id = 4, name = "Target: Triangle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "marker", id = 5, name = "Target: Moon", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "marker", id = 6, name = "Target: Square", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "marker", id = 7, name = "Target: Cross", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "marker", id = 8, name = "Target: Skull", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "marker", id = 0, name = "Clear Target", icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = "Flares",
                items = {
                    { type = "targetmarker", id = 6, name = "Flare: Blue",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "targetmarker", id = 4, name = "Flare: Green",  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "targetmarker", id = 3, name = "Flare: Purple", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "targetmarker", id = 7, name = "Flare: Red",    icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "targetmarker", id = 1, name = "Flare: Yellow", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "targetmarker", id = 2, name = "Flare: Orange", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "targetmarker", id = 5, name = "Flare: Silver", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "targetmarker", id = 8, name = "Flare: White",  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "targetmarker", id = 0, name = "Clear Flares",  icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = "Pings",
                items = {
                    { type = "ping", id = "", name = "Ping", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-main-icon.png" },
                    { type = "ping", id = "attack", name = "Ping: Attack", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Attack-Icon.png" },
                    { type = "ping", id = "assist", name = "Ping: Assist", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Assist-Icon.png" },
                    { type = "ping", id = "onmyway", name = "Ping: On My Way", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-OnMyWay-Icon.png" },
                    { type = "ping", id = "warning", name = "Ping: Warning", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Warning-Icon.png" },
                }
            }
        }

        if not dialog.markerHeaders then
            dialog.markerHeaders = {}
            for _, cat in ipairs(categories) do
                local header = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                header:SetText(cat.name)
                header:SetTextColor(1, 0.82, 0)
                table.insert(dialog.markerHeaders, header)
            end
        end
        for _, h in ipairs(dialog.markerHeaders) do
            h:Hide()
        end

        local btnSize = 44
        local spacing = 6
        local cols = 4
        local currentY = 8

        for catIdx, cat in ipairs(categories) do
            local header = dialog.markerHeaders[catIdx]
            header:SetPoint("TOPLEFT", child, "TOPLEFT", 12, -currentY)
            header:Show()

            currentY = currentY + 18

            local x, y = 0, 0
            for i, item in ipairs(cat.items) do
                local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
                btn:SetSize(btnSize, btnSize)
                btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -currentY - y * (btnSize + spacing + 18))
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 10,
                })
                btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
                btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
                label:SetText(item.name)
                label:SetWidth(btnSize + 4)
                label:SetJustifyH("CENTER")
                label:SetHeight(12)
                label:SetTextColor(0.90, 0.85, 0.80, 1)

                btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
                btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

                btn:SetScript("OnClick", function()
                    local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                    if slots[dialog.slotIndex] then
                        slots[dialog.slotIndex].type = item.type
                        slots[dialog.slotIndex].id = item.id
                        slots[dialog.slotIndex].assignmentMode = nil
                    end
                    ActionHub:RefreshTab()
                    ActionHub:RefreshPickerList()
                end)

                -- Drag support
                btn:RegisterForDrag("LeftButton")
                btn:SetScript("OnDragStart", function(self)
                    ActionHub.dragData = { type = item.type, id = item.id, icon = item.icon }
                    if not ActionHub.dragIcon then
                        local f = CreateFrame("Frame", nil, UIParent)
                        f:SetSize(32, 32)
                        f:SetFrameStrata("TOOLTIP")
                        local t = f:CreateTexture(nil, "OVERLAY")
                        t:SetAllPoints()
                        f.tex = t
                        ActionHub.dragIcon = f
                    end
                    ActionHub.dragIcon.tex:SetTexture(item.icon)
                    ActionHub.dragIcon:Show()
                    ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                        local cx, cy = GetCursorPosition()
                        local s = UIParent:GetEffectiveScale()
                        self:ClearAllPoints()
                        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                    end)
                end)
                btn:SetScript("OnDragStop", function(self)
                    if ActionHub.dragIcon then
                        ActionHub.dragIcon:Hide()
                        ActionHub.dragIcon:SetScript("OnUpdate", nil)
                    end
                    if ActionHub.dragData then
                        local dropTarget = nil
                        local tab = ActionHub.tab
                        if tab and tab.ringButtons then
                            for _, rb in ipairs(tab.ringButtons) do
                                if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                    dropTarget = rb
                                    break
                                end
                            end
                        end
                        if dropTarget then
                            local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide or dialog.slotSide)
                            if slots[dropTarget.slotIndex] then
                                slots[dropTarget.slotIndex].type = ActionHub.dragData.type
                                slots[dropTarget.slotIndex].id = ActionHub.dragData.id
                                slots[dropTarget.slotIndex].assignmentMode = nil
                            end
                            ActionHub:RefreshTab()
                            ActionHub:RefreshPickerList()
                        end
                        ActionHub.dragData = nil
                    end
                end)

                x = x + 1
                if x >= cols then
                    x = 0
                    y = y + 1
                end
            end

            local numRows = math.max(math.ceil(#cat.items / cols), 1)
            currentY = currentY + numRows * (btnSize + spacing + 18) + 12
        end

        child:SetHeight(currentY + 10)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "settings" then
        dialog.scroll:Hide()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Show()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_CONFIGURE_SETTINGS"] or "Configure settings for this slot")
        dialog.moveNodeMode = dialog.moveNodeMode == true

        local size = (currentSlot and currentSlot.nodeSize) or ActionHub:GetActiveHubDB().globalNodeSize or 44
        dialog.sizeSlider.isResetting = true
        dialog.sizeSlider:SetValue(size)
        dialog.sizeSlider.isResetting = false
        dialog.sizeVal:SetText(tostring(size))
        dialog.sizeInput:SetText(tostring(size))

        local gSize = ActionHub:GetActiveHubDB().globalNodeSize or 44
        dialog.globalSizeSlider.isResetting = true
        dialog.globalSizeSlider:SetValue(gSize)
        dialog.globalSizeSlider.isResetting = false
        dialog.globalSizeVal:SetText(tostring(gSize))
        dialog.globalSizeInput:SetText(tostring(gSize))

        local lSize = ActionHub:GetActiveHubDB().nodeLineSize or 48
        dialog.lineSizeSlider.isResetting = true
        dialog.lineSizeSlider:SetValue(lSize)
        dialog.lineSizeSlider.isResetting = false
        dialog.lineSizeVal:SetText(tostring(lSize))
        dialog.lineSizeInput:SetText(tostring(lSize))

        local posX = (currentSlot and currentSlot.nodePositionX) or 0
        dialog.posXSlider.isResetting = true
        dialog.posXSlider:SetValue(posX)
        dialog.posXSlider.isResetting = false
        dialog.posXVal:SetText(tostring(posX))
        dialog.posXInput:SetText(tostring(posX))

        local posY = (currentSlot and currentSlot.nodePositionY) or 0
        dialog.posYSlider.isResetting = true
        dialog.posYSlider:SetValue(posY)
        dialog.posYSlider.isResetting = false
        dialog.posYVal:SetText(tostring(posY))
        dialog.posYInput:SetText(tostring(posY))

        local tSize = ActionHub:GetActiveHubDB().cooldownTextSize or 11
        if dialog.textSizeSlider then
            dialog.textSizeSlider.isResetting = true
            dialog.textSizeSlider:SetValue(tSize)
            dialog.textSizeSlider.isResetting = false
            dialog.textSizeVal:SetText(tostring(tSize))
            dialog.textSizeInput:SetText(tostring(tSize))
        end

        if dialog.bgAlphaSlider then
            local a = ActionHub:GetActiveHubDB().nodeBackgroundAlpha
            if a == nil then a = 0.5 end
            local pct = math.floor(a * 100 + 0.5)
            dialog.bgAlphaSlider.isSyncing = true
            dialog.bgAlphaSlider:SetValue(pct)
            dialog.bgAlphaSlider.isSyncing = false
            dialog.bgAlphaVal:SetText(pct .. "%")
            if dialog.bgAlphaInput then dialog.bgAlphaInput:SetText(tostring(pct)) end
        end

        local bindingText = (currentSlot and currentSlot.binding) or L["KEYBIND_NOT_BOUND"] or "Not Bound"
        dialog.bindBtn:SetText(bindingText)

        -- Keep the custom-icon preview in step with the slot being edited.
        if dialog.RefreshCustomIcon then dialog:RefreshCustomIcon() end

        if dialog.allowAnimCheck then
            local allowAnim = ActionHub:GetActiveHubDB().allowAnimations
            if allowAnim == nil then allowAnim = true end
            dialog.allowAnimCheck:SetChecked(allowAnim)
        end
        
        if dialog.readyGlowCheck then
            dialog.readyGlowCheck:SetChecked(currentSlot and currentSlot.showReadyGlow == true)
        end
        if dialog.readyGlowHexInput then
            local hex = (currentSlot and currentSlot.readyGlowHex) or "FFFF00"
            dialog.readyGlowHexInput:SetText(hex)
            -- The OnTextChanged script will update the color preview
        end
        if dialog.readyGlowSizeSlider then
            dialog.readyGlowSizeSlider.isSyncing = true
            local size = (currentSlot and currentSlot.readyGlowSize) or 100
            dialog.readyGlowSizeSlider:SetValue(size)
            if dialog.readyGlowSizeVal then dialog.readyGlowSizeVal:SetText(size .. "%") end
            dialog.readyGlowSizeSlider.isSyncing = false
        end
        if dialog.readyGlowAlphaSlider then
            dialog.readyGlowAlphaSlider.isSyncing = true
            local alpha = (currentSlot and currentSlot.readyGlowAlpha) or 100
            dialog.readyGlowAlphaSlider:SetValue(alpha)
            if dialog.readyGlowAlphaVal then dialog.readyGlowAlphaVal:SetText(alpha .. "%") end
            dialog.readyGlowAlphaSlider.isSyncing = false
        end

        if dialog.showTooltipCheck then
            local showTT = ActionHub:GetActiveHubDB().showTooltip
            if showTT == nil then showTT = true end
            dialog.showTooltipCheck:SetChecked(showTT)
        end

        if dialog.tabCheckboxes then
            local activeDB = ActionHub:GetActiveHubDB()
            local visibleTabs = activeDB.visibleTabs or {
                toy = true,
                emote = true,
                trigger = true,
                marker = true,
                mount = false,
                item = false,
                settings = true,
            }
            for key, check in pairs(dialog.tabCheckboxes) do
                local val = visibleTabs[key]
                if val == nil then
                    if key == "mount" or key == "item" or key == "spell" then
                        val = false
                    else
                        val = true
                    end
                end
                check:SetChecked(val)
            end
        end
    end
    if OxedHub.UI and OxedHub.UI.ApplyGlobalTextSize then
        OxedHub.UI:ApplyGlobalTextSize()
    end
end