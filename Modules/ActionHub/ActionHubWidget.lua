local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ActionHub: the hubs on screen: building them, showing and hiding them
-- in and out of combat, move mode and the grid, and dragging nodes and hubs.
-- The files and what each holds are listed at the top of ActionHubData.lua.
local ActionHub = OxedHub.ActionHub
local Private = ActionHub._private

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

-- From the files loaded before this one (see Private in ActionHubData.lua).
local ApplyButtonColoring = Private.ApplyButtonColoring
local CreateDefaultHubData = Private.CreateDefaultHubData
local EnsureHubData = Private.EnsureHubData
local GetArcCoordinates = Private.GetArcCoordinates
local GetDualQuadrant = Private.GetDualQuadrant
local GetSecondarySkipEdge = Private.GetSecondarySkipEdge
local MouseIsOver = Private.MouseIsOver
local TrimSideToLimit = Private.TrimSideToLimit
local GetActionHubToyMacroText = Private.GetActionHubToyMacroText
local GetDirectToyDisplay = Private.GetDirectToyDisplay
local GetMarkerPingIcon = Private.GetMarkerPingIcon
local GetMarkerPingMacro = Private.GetMarkerPingMacro
local GetToyAssignmentMode = Private.GetToyAssignmentMode
local ResolveCustomIcon = Private.ResolveCustomIcon
local SetNodeSelected = Private.SetNodeSelected
local StyleButton = Private.StyleButton
local StyleCooldownText = Private.StyleCooldownText
local UpdateBindingLabel = Private.UpdateBindingLabel

-- Assigned further down, used by the hub frames above that point.
local ApplyWidgetVisualAlpha

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
        if hubDB and hubDB.onScreen
            and (ActionHub:GetVisibilityMode(hubDB) ~= "always" or hubDB.hideMounted) then
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
    -- ⚠ Invisible and let through. The blue box with its label sat over the
    -- world around every hub while positioning, in the way of the grid and
    -- of the other hubs. A hub moves with Shift + drag on any of its nodes;
    -- this frame only stays to carry the hub's own grid dots.
    moveOverlay:SetBackdropColor(0.1, 0.4, 0.9, 0)
    moveOverlay:SetBackdropBorderColor(0.3, 0.6, 1, 0)
    moveOverlay:EnableMouse(false)
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
    moveLabel:Hide()
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

    local shouldHide = ActionHub:ShouldFadeHub(db)
    local targetAlpha = 1
    if shouldHide then
        targetAlpha = IsMouseOverActionHubWidget(w) and 1 or (db.fadedAlpha or 0)
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

    -- Runs while any hub is faded, so hovering it brings it back.
    for i = 1, #hubs do
        local hubDB = EnsureHubData(hubs[i], i)
        if self:ShouldFadeHub(hubDB) then
            shouldRun = true
            break
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
    f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
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

    -- The node's own scale, not UIParent's: the preview canvas may be scaled
    -- down to fit, and the node must still follow the cursor exactly.
    local scale = btn:GetEffectiveScale()
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

        -- The box as it is seen: a canvas scaled down to fit shows more of
        -- itself than its own size, centred, so the limits widen by 1/scale.
        local fit = (previewParent and previewParent:GetScale()) or 1
        if fit <= 0 then fit = 1 end
        local spanX = (previewWidth / 2) / fit
        local spanY = (previewHeight / 2) / fit
        -- And moved: the middle of what is seen is off the canvas's middle
        -- by the pan the fit applied.
        local midX = previewWidth / 2 - (previewParent and previewParent.fitPanX or 0)
        local midY = -previewHeight / 2 - (previewParent and previewParent.fitPanY or 0)

        local minOffsetX = (midX - spanX + halfSize) - self.basePreviewX
        local maxOffsetX = (midX + spanX - halfSize) - self.basePreviewX
        local minOffsetY = (midY - spanY + halfSize) - self.basePreviewY
        local maxOffsetY = (midY + spanY - halfSize) - self.basePreviewY

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
    -- Drawn on the canvas, so the dots shrink with the nodes and keep lining
    -- up with where they snap. The old dots on the overlay are put away.
    if tab.previewCanvas and tab.moveOverlay.gridDots and not tab.moveOverlay.gridMoved then
        for _, d in ipairs(tab.moveOverlay.gridDots) do d:Hide() end
        tab.moveOverlay.gridMoved = true
    end
    local overlay = tab.previewCanvas or tab.moveOverlay
    overlay.gridDots = overlay.gridDots or {}
    for _, d in ipairs(overlay.gridDots) do d:Hide() end

    local gridType = self.moveGridType or "off"
    if gridType == "off" or gridType == "magnetic" then return end

    -- Wide enough to cover the whole box however the fit moved and scaled it.
    local pan = math.max(math.abs(overlay.fitPanX or 0), math.abs(overlay.fitPanY or 0))
    local zoneHalf = (205 + pan) / math.max(0.1, overlay:GetScale() or 1)
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
    -- ⚠ The screen grid no longer hides anything. It used to hide the logo
    -- and the empty "+" nodes while it was up, and a hub with nothing on it
    -- yet vanished outright the moment the grid was switched on.
    local showLogo = (unlocked or not not db.showLogoWhenLocked or isMoveActive)
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

        -- The moment a sweep ends, look at this node again: that is when it
        -- turns ready. The game times the sweep itself, so nothing has to
        -- watch it on a ticker.
        local function CooldownEnded() ActionHub:QueueNodeRefresh(btn) end
        cd1:HookScript("OnCooldownDone", CooldownEnded)
        cd2:HookScript("OnCooldownDone", CooldownEnded)

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
            if s and s.type and db.showTooltip ~= false
                and not (db.tooltipInCombat == false and InCombatLockdown()) then
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
                elseif s.type == "module" then
                    local name, action = ActionHub:DescribeModuleNode(s.id)
                    GameTooltip:SetText(string.format("Module: %s", name or tostring(s.id)))
                    if action then GameTooltip:AddLine(action, 1, 1, 1) end
                end
                GameTooltip:Show()
            end
            -- While positioning, every node (empty ones too) says how to move
            -- the whole hub: Shift + drag is not something anyone guesses.
            if ActionHub:IsMoveModeActive() then
                if not GameTooltip:IsOwned(self) then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Move Mode", 1, 0.82, 0)
                end
                GameTooltip:AddLine("Drag to move this node.", 1, 1, 1)
                GameTooltip:AddLine("Hold Shift and drag to move the whole hub.", 0.4, 0.8, 1)
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
                elseif s.type == "module" then
                    ActionHub:RunModuleNode(s.id, button)
                end

                if OxedHub.ErrorJournal then OxedHub.ErrorJournal:ClearContext() end
            end

            ActionHub:QueueNodeRefresh(self)
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
            elseif slot.type == "module" then
                btn.icon:SetTexture(ActionHub:GetModuleNodeIcon(slot.id))
                btn.icon:Show()
                -- Run in PostClick via RunModuleNode: nothing secure to arm.
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

            -- Move mode shows empty slots so they can be filled and placed,
            -- grid or no grid (see showLogo above).
            local showEmpty = (db.widgetUnlocked or moveMode)
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
        local tick = 0
        -- Only a safety net now: a node is looked at again the moment its
        -- sweep ends (OnCooldownDone), and procs come by their own events.
        -- With many nodes the old half-second pass was most of what the
        -- bars cost.
        ActionHub.cooldownTicker = C_Timer.NewTicker(1.5, function()
            ActionHub:UpdateRunningCooldowns()
            -- A proc whose event named a different spell id is still caught.
            tick = tick + 1
            if tick % 2 == 0 then ActionHub:UpdateProcGlows() end
        end)
    end

    self:UpdateCombatVisibilityTicker()
    if self.UpdateRangeChecks then
        self:UpdateRangeChecks()
    end
end

