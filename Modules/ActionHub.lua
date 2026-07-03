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
function ActionHub:GetHubs()
    local ah = OxedHub.db.profile.actionHub
    if not ah.hubs then ah.hubs = {} end
    for i = 1, #ah.hubs do
        ah.hubs[i] = EnsureHubData(ah.hubs[i], i)
    end
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
local PING_ICONS = {
    [""] = "Interface\\Icons\\ability_hunter_pathfinding",
    attack = "Interface\\Icons\\ability_warrior_charge",
    assist = "Interface\\Icons\\spell_holy_layonhands",
    onmyway = "Interface\\Icons\\ability_rogue_sprint",
    warning = "Interface\\Icons\\spell_shadow_deathscream",
}

local function GetMarkerPingIcon(slot)
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

local function GetSlotCooldown(slot)
    local ok, startTime, duration = pcall(function()
        if not slot then return nil, nil end
        local id = slot.id
        if not id then return nil, nil end

        if slot.type == "spell" then
            local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
            if cdInfo and cdInfo.isEnabled and cdInfo.isActive then
                local d = tonumber(tostring(cdInfo.duration))
                local s = tonumber(tostring(cdInfo.startTime))
                if d and d > 1.5 then return s, d end
            end
            return nil, nil
        end

        if slot.type == "toy" or slot.type == "item" then
            local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
            local start, dur = getCooldown(id)
            if dur and dur > 1.5 then return start, dur end
            
            local spellName, spellID = GetItemSpell(id)
            if spellID then
                local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
                if cdInfo and cdInfo.isEnabled and cdInfo.isActive then
                    local d = tonumber(tostring(cdInfo.duration))
                    local s = tonumber(tostring(cdInfo.startTime))
                    if d and d > 1.5 then return s, d end
                end
            end
        end

        if slot.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[slot.id]
            local spellID = trg and OxedHub.Triggers and OxedHub.Triggers.GetTriggerCooldownSpellID and OxedHub.Triggers:GetTriggerCooldownSpellID(trg)
            if spellID then
                local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
                if cdInfo and cdInfo.isEnabled and cdInfo.isActive then
                    local d = tonumber(tostring(cdInfo.duration))
                    local s = tonumber(tostring(cdInfo.startTime))
                    if d and d > 1.5 then return s, d end
                end
            end
        end
        return nil, nil
    end)
    if ok then return startTime, duration end
    return nil, nil
end

local function GetToyAssignmentMode(slot)
    if slot and slot.type == "toy" and slot.assignmentMode == "direct" then
        return "direct"
    end
    return "mix"
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
        return OxedHub.Toys:GetMixMacroText(mixData) or ""
    end

    return ""
end

function ActionHub:UpdateWidgetCooldowns()
    local widgets = self.widgets or {}
    for _, w in ipairs(widgets) do
        if w and w.buttons then
            for _, btn in ipairs(w.buttons) do
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

                    local start, dur
                    if slot and slot.type == "toy" and GetToyAssignmentMode(slot) == "direct" then
                        btn.cooldown2:Hide()
                        local start, dur = GetSlotCooldown(slot)
                        if start and dur then
                            CooldownFrame_Set(btn.cooldown1, start, dur, true)
                            btn.cooldown1:Show()
                            StyleCooldownText(btn.cooldown1, 0)
                        else
                            btn.cooldown1:Hide()
                        end
                    elseif type(mixData) == "table" and mixData.slots then
                        local cdFrames = { btn.cooldown1, btn.cooldown2 }
                        for i = 1, 2 do
                            local mixSlot = mixData.slots[i]
                            local cdFrame = cdFrames[i]
                            local start, dur = GetSlotCooldown(mixSlot)
                            if start and dur then
                                CooldownFrame_Set(cdFrame, start, dur, true)
                                cdFrame:Show()
                                StyleCooldownText(cdFrame, i == 1 and 7 or -7)
                            else
                                cdFrame:Hide()
                            end
                        end
                    else
                        -- Handle single cooldown (for triggers/etc)
                        btn.cooldown2:Hide()
                        local start, dur = GetSlotCooldown(slot)
                        if start and dur then
                            CooldownFrame_Set(btn.cooldown1, start, dur, true)
                            btn.cooldown1:Show()
                            StyleCooldownText(btn.cooldown1, 0)
                        else
                            btn.cooldown1:Hide()
                        end
                    end
                end
            end
        end
    end
end

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
    local innerSize = style == "ring" and (size - 2) or (size - 4)
    btn.icon:SetSize(innerSize, innerSize)
    if btn.splitIcon then
        btn.splitIcon:SetSize(innerSize, innerSize)
        if btn.splitIcon.leftTexture then btn.splitIcon.leftTexture:SetSize(innerSize/2, innerSize) end
        if btn.splitIcon.rightTexture then btn.splitIcon.rightTexture:SetSize(innerSize/2, innerSize) end
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
            btn.ringMask:SetAllPoints(btn.icon)
        end
        btn.icon:AddMaskTexture(btn.ringMask)
        if btn.plus then btn.plus:AddMaskTexture(btn.ringMask) end

        if btn.splitIcon and btn.splitIcon.leftTexture and btn.splitIcon.rightTexture then
            if not btn.splitMaskL then
                btn.splitMaskL = btn:CreateMaskTexture(nil, "ARTWORK")
                btn.splitMaskL:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
            if not btn.splitMaskR then
                btn.splitMaskR = btn:CreateMaskTexture(nil, "ARTWORK")
                btn.splitMaskR:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
            local sx, sy = btn.splitIcon:GetSize()
            btn.splitMaskL:ClearAllPoints()
            btn.splitMaskL:SetPoint("CENTER", btn.splitIcon, "CENTER")
            btn.splitMaskL:SetSize(sx, sy)
            btn.splitMaskR:ClearAllPoints()
            btn.splitMaskR:SetPoint("CENTER", btn.splitIcon, "CENTER")
            btn.splitMaskR:SetSize(sx, sy)
            btn.splitIcon.leftTexture:AddMaskTexture(btn.splitMaskL)
            btn.splitIcon.rightTexture:AddMaskTexture(btn.splitMaskR)
        end

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn.ringBg:SetVertexColor(1, 0.82, 0, 1)
        else
            btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
        end
        
        if btn.glow then
            btn.glow:SetSize(size + 16, size + 16)
        end
    else
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end

        if btn.ringBg then btn.ringBg:Hide() end
        if btn.ringFill then btn.ringFill:Hide() end
        if btn.ringMask then 
            btn.icon:RemoveMaskTexture(btn.ringMask) 
            if btn.plus then btn.plus:RemoveMaskTexture(btn.ringMask) end
        end
        if btn.splitIcon and btn.splitIcon.leftTexture and btn.splitIcon.rightTexture then
            if btn.splitMaskL then btn.splitIcon.leftTexture:RemoveMaskTexture(btn.splitMaskL) end
            if btn.splitMaskR then btn.splitIcon.rightTexture:RemoveMaskTexture(btn.splitMaskR) end
        end
        if btn.glow then btn.glow:SetSize(size + 24, size + 24) end
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
        if not parent:IsMovable() or not (hubDB and hubDB.widgetUnlocked) then
            parent.isMoving = false
            return
        end
        parent:StartMoving()
        parent.isMoving = true
    end)
    anchor:SetScript("OnDragStop", function(self)
        local parent = self:GetParent()
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
            if not parent.isMoving then
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

    btn:SetScript("OnUpdate", function(self)
        local currentX, currentY = GetCursorPosition()
        currentX = currentX / scale
        currentY = currentY / scale

        local deltaX = currentX - self.dragStartCursorX
        local deltaY = currentY - self.dragStartCursorY
        local newOffsetX = math.floor((self.dragStartOffsetX + deltaX) + 0.5)
        local newOffsetY = math.floor((self.dragStartOffsetY + deltaY) + 0.5)

        local previewParent = self:GetParent()
        local previewWidth = previewParent and previewParent:GetWidth() or 400
        local previewHeight = previewParent and previewParent:GetHeight() or 400
        local halfSize = (self:GetWidth() or 44) / 2

        local minOffsetX = halfSize - self.basePreviewX
        local maxOffsetX = (previewWidth - halfSize) - self.basePreviewX
        local minOffsetY = (-(previewHeight - halfSize)) - self.basePreviewY
        local maxOffsetY = (-halfSize) - self.basePreviewY

        newOffsetX = math.max(minOffsetX, math.min(maxOffsetX, newOffsetX))
        newOffsetY = math.max(minOffsetY, math.min(maxOffsetY, newOffsetY))

        slot.nodePositionX = newOffsetX
        slot.nodePositionY = newOffsetY

        if dialog.posXVal then dialog.posXVal:SetText(tostring(newOffsetX)) end
        if dialog.posXInput then dialog.posXInput:SetText(tostring(newOffsetX)) end
        if dialog.posYVal then dialog.posYVal:SetText(tostring(newOffsetY)) end
        if dialog.posYInput then dialog.posYInput:SetText(tostring(newOffsetY)) end

        self:ClearAllPoints()
        self:SetPoint("CENTER", self:GetParent(), "TOPLEFT", self.basePreviewX + newOffsetX, self.basePreviewY + newOffsetY)
    end)
end

function ActionHub:EndPreviewNodeDrag(btn)
    if not btn or not btn.isDraggingNode then
        return
    end

    btn.isDraggingNode = false
    btn:SetScript("OnUpdate", nil)
    self:RefreshWidget()
    self:RefreshTab()
end

-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
-- Minimized Move Mode: hide the main window and drag the real widget's nodes
-- directly on screen, inside a blue "move zone" overlay.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

function ActionHub:IsMinimizedMoveMode(hubIndex)
    return self.minimizedMoveModeHub ~= nil and self.minimizedMoveModeHub == hubIndex
end

-- Drag a real widget node on screen, updating its slot offset live.
function ActionHub:BeginWidgetNodeDrag(btn)
    if not btn or not btn.slotIndex or not btn.slotSide then return end
    if InCombatLockdown() then return end
    local hub = self.minimizedMoveModeHub
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
        rawX, rawY = ActionHub:SnapMovePosition(w, rawX, rawY)
        local half = (self:GetWidth() or 44) / 2
        local zoneHalf = w.moveZoneHalf or 235
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
    end)
end

function ActionHub:EndWidgetNodeDrag(btn)
    if not btn or not btn.isDraggingNode then return end
    btn.isDraggingNode = false
    btn:SetScript("OnUpdate", nil)
end

-- Small floating "Done Positioning" control shown while in minimized move mode.
function ActionHub:GetOrCreateMoveModeDoneFrame()
    if self.moveModeDoneFrame then return self.moveModeDoneFrame end

    local f = CreateFrame("Frame", "OxedHubActionHubMoveDone", UIParent, "BackdropTemplate")
    f:SetSize(300, 104)
    f:SetPoint("TOP", UIParent, "TOP", 0, -130)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(300)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.06, 0.09, 0.96)
    f:SetBackdropBorderColor(0.3, 0.6, 1, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    title:SetText(L["AH_MOVE_MODE_DRAG_SCREEN"] or "Move Mode â€” drag nodes on screen")
    title:SetTextColor(0.8, 0.9, 1, 1)

    local function updateGridButtons()
        local t = ActionHub.moveGridType or "off"
        local gridText = t == "square" and L["GRID_SQUARE"] or t == "radial" and L["GRID_RADIAL"] or L["GRID_OFF"]
        f.gridBtn:SetText(string.format(L["AH_GRID_LABEL"] or "Grid: %s", gridText))

        local snapText = ActionHub.moveSnap and L["SNAP_ON"] or L["SNAP_OFF"]
        f.snapBtn:SetText(string.format(L["AH_SNAP_LABEL"] or "Snap: %s", snapText))
        if t == "off" then f.snapBtn:Disable() else f.snapBtn:Enable() end
    end
    f.updateGridButtons = updateGridButtons

    -- Row 1: Grid type + Snap toggle
    local gridBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    gridBtn:SetSize(135, 24)
    gridBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -24)
    gridBtn:SetText(string.format(L["AH_GRID_LABEL"] or "Grid: %s", L["GRID_OFF"] or "Off"))
    gridBtn:SetScript("OnClick", function()
        local t = ActionHub.moveGridType or "off"
        ActionHub.moveGridType = (t == "off" and "square") or (t == "square" and "radial") or "off"
        ActionHub:UpdateMoveGrid()
        updateGridButtons()
    end)
    f.gridBtn = gridBtn

    local snapBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    snapBtn:SetSize(135, 24)
    snapBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -24)
    snapBtn:SetText(string.format(L["AH_SNAP_LABEL"] or "Snap: %s", L["SNAP_OFF"] or "Off"))
    snapBtn:SetScript("OnClick", function()
        ActionHub.moveSnap = not ActionHub.moveSnap
        updateGridButtons()
    end)
    f.snapBtn = snapBtn

    -- Row 2: Reset + Done
    local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    resetBtn:SetSize(135, 24)
    resetBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    resetBtn:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
    resetBtn:SetScript("OnClick", function() ActionHub:ResetMoveModePositions() end)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(135, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    doneBtn:SetText(L["AH_DONE_POSITIONING"] or "Done Positioning")
    doneBtn:SetScript("OnClick", function() ActionHub:ExitMinimizedMoveMode() end)

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

-- Snap a node position (w TOPLEFT coords) to the active grid, if snap is on.
function ActionHub:SnapMovePosition(w, posX, posY)
    local gridType = self.moveGridType or "off"
    if gridType == "off" or not self.moveSnap then
        return posX, posY
    end
    local centerX = w:GetWidth() / 2
    local centerY = -(w:GetHeight() / 2)
    local relX = posX - centerX
    local relY = posY - centerY
    if gridType == "square" then
        local s = MOVE_GRID_SQUARE_STEP
        relX = math.floor(relX / s + 0.5) * s
        relY = math.floor(relY / s + 0.5) * s
    elseif gridType == "radial" then
        local r = math.sqrt(relX * relX + relY * relY)
        local theta = math.atan2(relY, relX)
        r = math.floor(r / MOVE_GRID_RADIAL_RSTEP + 0.5) * MOVE_GRID_RADIAL_RSTEP
        theta = math.floor(theta / MOVE_GRID_RADIAL_ASTEP + 0.5) * MOVE_GRID_RADIAL_ASTEP
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

    local gridType = self.moveGridType or "off"
    if gridType == "off" then return end

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
        local s = MOVE_GRID_SQUARE_STEP
        local n = math.floor(zoneHalf / s)
        for i = -n, n do
            for j = -n, n do
                dot(i * s, j * s)
            end
        end
    elseif gridType == "radial" then
        dot(0, 0)
        local rings = math.floor(zoneHalf / MOVE_GRID_RADIAL_RSTEP)
        for ring = 1, rings do
            local r = ring * MOVE_GRID_RADIAL_RSTEP
            local a = 0
            while a < math.pi * 2 - 0.001 do
                dot(r * math.cos(a), r * math.sin(a))
                a = a + MOVE_GRID_RADIAL_ASTEP
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

    local w = self:CreateWidget(self.minimizedMoveModeHub)
    if w then w:SetMovable(true) end

    -- Hide the editor / main window so the screen is clear for dragging
    if self.pickerDialog and self.pickerDialog:IsShown() then self.pickerDialog:Hide() end
    if OxedHub.mainFrame then OxedHub.mainFrame:Hide() end

    local doneFrame = self:GetOrCreateMoveModeDoneFrame()
    doneFrame:Show()
    if doneFrame.updateGridButtons then doneFrame.updateGridButtons() end
    self:RefreshWidget()
end

function ActionHub:ExitMinimizedMoveMode()
    self.minimizedMoveModeHub = nil
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

    local sourceCopy = CloneSlotData(sourceSlot)
    local targetCopy = CloneSlotData(targetSlot)

    sourceSlots[dragData.sourceSlotIndex] = targetCopy
    targetSlots[dropTarget.slotIndex] = sourceCopy

    if btn then
        btn.wasAssignmentDragged = true
    end
    dropTarget.wasAssignmentDragged = true

    self:RefreshPickerList()
    self:RefreshWidget()
    self:RefreshTab()
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
    local moveMode = self:IsMinimizedMoveMode(hubIndex)
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
    local unlocked = db.widgetUnlocked
    local showLogo = unlocked or db.showLogoWhenLocked
    w:SetMovable(unlocked)
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
        w.anchor:EnableMouse(db.showLogoWhenLocked or false)
    end

    -- Hide old buttons
    for _, btn in ipairs(w.buttons) do
        btn:Hide()
    end

    if totalSlots == 0 then
        w:SetShown(db.onScreen or moveMode)
        if w.moveOverlay then w.moveOverlay:SetShown(moveMode) end
        self:ApplyWidgetCombatVisibility(w, db)
        self:UpdateCombatVisibilityTicker()
        return
    end

    local cx, cy = 150, -150 -- center of the 300x300 widget
    local baseRadius = 65
    local radiusStep = db.nodeLineSize or 48

    local function StripRestrictedMacroLines(text)
        if not text then return nil end
        local lines = {}
        for line in text:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" and not trimmed:match("^/run") and not trimmed:match("^/script") and not trimmed:match("^/console") then
                table.insert(lines, trimmed)
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
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetSize(32, 32)
        btn.icon = icon

        local plus = btn:CreateTexture(nil, "OVERLAY")
        plus:SetPoint("CENTER", btn, "CENTER", 0, 0)
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

        local cd1 = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd1:SetAllPoints()
        cd1:SetFrameLevel(btn:GetFrameLevel() + 5)
        cd1:SetDrawBling(false)
        cd1:SetDrawEdge(false)
        cd1:SetDrawSwipe(false)
        cd1:SetReverse(true)
        cd1:EnableMouse(false)
        cd1:Hide()
        StyleCooldownText(cd1, 6)
        btn.cooldown1 = cd1

        local cd2 = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd2:SetAllPoints()
        cd2:SetFrameLevel(btn:GetFrameLevel() + 6)
        cd2:SetDrawBling(false)
        cd2:SetDrawEdge(false)
        cd2:SetDrawSwipe(false)
        cd2:SetReverse(true)
        cd2:EnableMouse(false)
        cd2:Hide()
        StyleCooldownText(cd2, -6)
        btn.cooldown2 = cd2

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
                end
                GameTooltip:Show()
            end
            local currentStyle = db.style or "square"
            if currentStyle == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(1, 0.82, 0, 1)
            else
                self:SetBackdropBorderColor(1, 0.82, 0, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            local currentStyle = db.style or "square"
            if currentStyle == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
            else
                self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            end
        end)

        -- Drag-and-drop: accept emote drags from the picker grid
        btn:RegisterForDrag("LeftButton")
        btn:SetScript("OnReceiveDrag", function(self)
            -- no-op: we handle drops via OnDragStop on the source
        end)
        -- We attach drop logic via OnUpdate on the source's OnDragStop,
        -- so also detect via the hover approach below:
        btn.acceptDrop = true

        -- Node drag (minimized move mode only): drag the button on screen to
        -- reposition the node. Outside move mode these are no-ops.
        btn:SetScript("OnDragStart", function(self)
            if ActionHub:IsMinimizedMoveMode(w.hubIndex) then
                ActionHub:BeginWidgetNodeDrag(self)
            end
        end)
        btn:SetScript("OnDragStop", function(self)
            ActionHub:EndWidgetNodeDrag(self)
        end)

        -- PreClick: Regenerate macro text to ensure toy/spell names are fresh (fixes login data issue)
        btn:SetScript("PreClick", function(self, button, down)
            if ActionHub:IsMinimizedMoveMode(w.hubIndex) then return end
            if InCombatLockdown() or down or not self._cachedSlot then return end
            
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
                    local icon1, icon2
                    if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                        icon1, icon2 = OxedHub.Toys:GetMixSlotIcons(slot.id)
                    end
                    if icon1 and icon2 and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                        btn.icon:Hide()
                        btn.splitIcon = OxedHub.Toys:CreateSplitIcon(btn, 32, icon1, icon2)
                        btn.splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                        btn.splitIcon:Show()
                    else
                        btn.icon:SetTexture(icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                        btn.icon:Show()
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
            end
        else
            btn.icon:Hide()
            if btn.splitIcon then btn.splitIcon:Hide() end
            if btn.plus then btn.plus:Show() end
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

            local showEmpty = db.widgetUnlocked or moveMode
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
    if w.moveOverlay then w.moveOverlay:SetShown(moveMode) end
    if moveMode then
        w:SetMovable(true)
        self:UpdateMoveGrid()
    end
    for _, btn in ipairs(w.buttons) do
        if btn.glow then btn.glow:SetShown(moveMode and btn:IsShown()) end
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



    -- Preview container
    local ringContainer = CreateFrame("Frame", nil, tab)
    ringContainer:SetPoint("TOPLEFT", controls, "BOTTOMLEFT", 68, 32)
    ringContainer:SetSize(430, 430)
    tab.ringContainer = ringContainer

    local moveOverlay = CreateFrame("Frame", nil, ringContainer, "BackdropTemplate")
    -- ~10% wider than the preview container so the move zone has breathing room
    moveOverlay:SetPoint("TOPLEFT", ringContainer, "TOPLEFT", -22, 0)
    moveOverlay:SetPoint("BOTTOMRIGHT", ringContainer, "BOTTOMRIGHT", 22, 0)
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
        table.insert(slots, { type = nil, id = nil })
        ActionHub:RefreshTab()
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
            table.remove(slots, #slots)
            if ActionHub.pickerDialog and ActionHub.pickerDialog.slotSide == ActionHub:GetEditedSide() and ActionHub.pickerDialog.slotIndex and ActionHub.pickerDialog.slotIndex > #slots then
                ActionHub:ShowSlotPicker(nil)
            end
            ActionHub:RefreshTab()
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

    tab:Hide()
    contentArea.ActionHub = tab
    self.tab = tab
    
    return tab
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

            if i == activeIdx then
                hb:GetFontString():SetTextColor(1, 0.82, 0)
                hb:SetEnabled(false)
            else
                hb:GetFontString():SetTextColor(1, 1, 1)
            end

            hb:SetScript("OnClick", function()
                if self.pickerDialog then self.pickerDialog:Hide() end
                self:SetActiveHubIndex(i)
                self:RefreshTab()
            end)

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
    local cx, cy = 204, -204
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
            local isSelected = ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == self.slotIndex and ActionHub.pickerDialog.slotSide == self.slotSide
            if style == "ring" and self.ringBg then
                self.ringBg:SetVertexColor(isSelected and 1 or 0.8, isSelected and 0.82 or 0.8, isSelected and 0 or 0.8, isSelected and 1 or 0.2)
            else
                self:SetBackdropBorderColor(isSelected and 1 or 0.5, isSelected and 0.82 or 0.5, isSelected and 0 or 0.5, isSelected and 1 or 0.8)
            end
        end)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")
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
                return
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
                        local icon1, icon2
                        if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                            icon1, icon2 = OxedHub.Toys:GetMixSlotIcons(slot.id)
                        end
                        if icon1 and icon2 and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                            btn.icon:Hide()
                            btn.splitIcon = OxedHub.Toys:CreateSplitIcon(btn, 32, icon1, icon2)
                            btn.splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                            btn.splitIcon:Show()
                        else
                            btn.icon:SetTexture(icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                            btn.icon:Show()
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
                end
            else
                btn.icon:Hide()
                if btn.splitIcon then btn.splitIcon:Hide() end
                btn.plus:Show()
            end

            local style = db.style or "square"
            local size = (slot and slot.nodeSize) or db.globalNodeSize or 44
            btn:SetSize(size, size)
            StyleButton(btn, style, size, true)

            if self.pickerDialog and self.pickerDialog:IsShown() and self.pickerDialog.slotIndex == i and self.pickerDialog.slotSide == sideKey then
                btn.glow:Show()
            else
                btn.glow:Hide()
            end
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
        settings = true,
    }
    activeDB.visibleTabs.settings = true

    if not activeDB.visibleTabs[dialog.selectedType] then
        for _, catType in ipairs({"toy", "emote", "trigger", "marker", "mount", "item", "settings"}) do
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

        local sizeLabel = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sizeLabel:SetPoint("TOPLEFT", bindBtn, "BOTTOMLEFT", 0, -30)
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

        local allowAnimCheck = CreateFrame("CheckButton", nil, settingsChild, "UICheckButtonTemplate")
        allowAnimCheck:SetPoint("TOPLEFT", textSizeSlider, "BOTTOMLEFT", -4, -14)
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

        -- Sidebar Tabs Visibility Settings
        local tabsHeader = settingsChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabsHeader:SetPoint("TOPLEFT", showTooltipCheck, "BOTTOMLEFT", 4, -20)
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
                    settings = true,
                }
                activeDB.visibleTabs[def.key] = self:GetChecked()
                
                -- Ensure at least one tab is shown
                local anyShown = false
                for _, k in ipairs({"toy", "emote", "trigger", "marker", "mount", "item"}) do
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
                    local icon1 = "Interface\\Icons\\INV_Misc_QuestionMark"
                    local icon2 = "Interface\\Icons\\INV_Misc_QuestionMark"
                    if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                        icon1, icon2 = OxedHub.Toys:GetMixSlotIcons(mixName)
                    end
                    table.insert(items, { type = "toy", assignmentMode = "mix", id = mixName, name = mixName, icon1 = icon1, icon2 = icon2 })
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
                local splitIcon = OxedHub.Toys:CreateSplitIcon(btn, btnSize - 6, item.icon1, item.icon2)
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

        local bindingText = (currentSlot and currentSlot.binding) or L["KEYBIND_NOT_BOUND"] or "Not Bound"
        dialog.bindBtn:SetText(bindingText)

        if dialog.allowAnimCheck then
            local allowAnim = ActionHub:GetActiveHubDB().allowAnimations
            if allowAnim == nil then allowAnim = true end
            dialog.allowAnimCheck:SetChecked(allowAnim)
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
                    if key == "mount" or key == "item" then
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