local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ActionHub: the ActionHub tab in the OxedHub window: the hub list,
-- the preview you assign to, renaming, and the slot picker window.
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
local ApplyAssignmentBackdrop = Private.ApplyAssignmentBackdrop
local CreateDefaultHubData = Private.CreateDefaultHubData
local GetArcCoordinates = Private.GetArcCoordinates
local GetDualQuadrant = Private.GetDualQuadrant
local GetEffectiveNodeLimit = Private.GetEffectiveNodeLimit
local GetSecondarySkipEdge = Private.GetSecondarySkipEdge
local ShowConfirmDialog = Private.ShowConfirmDialog
local TrimSideToLimit = Private.TrimSideToLimit
local ApplyReadyGlow = Private.ApplyReadyGlow
local GetDirectToyDisplay = Private.GetDirectToyDisplay
local GetMarkerPingIcon = Private.GetMarkerPingIcon
local GetToyAssignmentMode = Private.GetToyAssignmentMode
local ResolveCustomIcon = Private.ResolveCustomIcon
local SetNodeSelected = Private.SetNodeSelected
local StyleButton = Private.StyleButton
local UpdateBindingLabel = Private.UpdateBindingLabel

-- Fits the preview inside the box. A layout that already fits is left at
-- its real size and place. One that does not is moved so that its own middle
-- sits in the middle of the box, then scaled down just enough for its width
-- and height: a long row or column off to one side used to be shrunk about
-- the box's centre instead, which made it tiny and still let it run out.
-- A view only: saved positions, node sizes and the hubs on screen are
-- untouched. The pan is kept on the canvas for dragging (fitPanX / fitPanY).
local FIT_MARGIN = 8
local FIT_SMALLEST = 0.2

function ActionHub:FitPreviewCanvas(tab)
    local canvas = tab and tab.previewCanvas
    if not canvas then return end
    local width, height = canvas:GetWidth(), canvas:GetHeight()

    -- The layout's bounds, in canvas units (y runs down from 0).
    local minX, maxX, minY, maxY
    local function Take(frame)
        if not (frame and frame:IsShown()) then return end
        local _, _, _, x, y = frame:GetPoint(1)
        if not (x and y) then return end
        local half = (frame:GetWidth() or 44) / 2
        minX = math.min(minX or x - half, x - half)
        maxX = math.max(maxX or x + half, x + half)
        minY = math.min(minY or y - half, y - half)
        maxY = math.max(maxY or y + half, y + half)
    end
    for _, btn in ipairs(tab.ringButtons or {}) do Take(btn) end
    Take(tab.previewLogo)

    local scale, panX, panY = 1, 0, 0
    if minX then
        local fits = minX >= FIT_MARGIN and maxX <= width - FIT_MARGIN
            and maxY <= -FIT_MARGIN and minY >= -(height - FIT_MARGIN)
        if not fits then
            local spanX = math.max(1, maxX - minX)
            local spanY = math.max(1, maxY - minY)
            scale = math.min(1, (width - 2 * FIT_MARGIN) / spanX, (height - 2 * FIT_MARGIN) / spanY)
            scale = math.max(FIT_SMALLEST, scale)
            -- The layout's middle onto the box's middle. Offsets of a scaled
            -- frame are in its own units, so these are canvas units.
            panX = width / 2 - (minX + maxX) / 2
            panY = -height / 2 - (minY + maxY) / 2
        end
    end

    canvas.fitPanX, canvas.fitPanY = panX, panY
    canvas:SetScale(scale)
    canvas:ClearAllPoints()
    canvas:SetPoint("CENTER", tab.ringContainer, "CENTER", panX, panY)
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

    -- Buttons and visibility for the selected hub, in a window of its own.
    local moreBtn = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
    moreBtn:SetSize(130, 22)
    moreBtn:SetPoint("LEFT", hubRow, "RIGHT", 10, 0)
    moreBtn:SetText(L["More options"])
    moreBtn:SetScript("OnClick", function() ActionHub:ShowHubOptions() end)
    moreBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["More options"])
        GameTooltip:AddLine(L["When the hub shows, mana and cooldown colours, item counts, icon zoom."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    moreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
        GetDB().visibility = self:GetChecked() and "hideCombat" or "always"
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
    gcdLabel:SetText(L["Show Global Cooldown"])
    gcdLabel:SetTextColor(0.9, 0.9, 0.9)

    gcdCheck:SetScript("OnClick", function(self)
        GetDB().showGlobalCooldown = self:GetChecked() and true or false
        ActionHub:UpdateWidgetCooldowns()
    end)
    gcdCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Show Global Cooldown"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Off: nodes only sweep for their own cooldown."], 1, 1, 1, true)
        GameTooltip:AddLine(L["On: they also sweep for the 1.5s global cooldown."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    gcdCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.gcdCheck = gcdCheck

    -- Range check toggle. On by default: turns ability/item red when target is out of range.
    local rangeCheck = CreateFrame("CheckButton", nil, controls, "UICheckButtonTemplate")
    rangeCheck:SetPoint("LEFT", gcdLabel, "RIGHT", 20, 0)
    rangeCheck:SetSize(22, 22)
    rangeCheck:SetChecked(GetDB().enableRangeCheck ~= false)

    local rangeLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rangeLabel:SetPoint("LEFT", rangeCheck, "RIGHT", 4, 0)
    rangeLabel:SetText(L["AH_RANGE_CHECK"] or "Range Check")
    rangeLabel:SetTextColor(0.9, 0.9, 0.9)

    rangeCheck:SetScript("OnClick", function(self)
        GetDB().enableRangeCheck = self:GetChecked() and true or false
        if ActionHub.UpdateRangeChecks then
            ActionHub:UpdateRangeChecks()
        end
    end)
    rangeCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["AH_RANGE_CHECK"] or "Range Check", 1, 0.82, 0)
        GameTooltip:AddLine(L["Tints ability and item icons red when your target is out of range."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    rangeCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.rangeCheckToggle = rangeCheck


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

    -- The preview's nodes and logo sit on this canvas, the same size as the
    -- box and centred in it. When a layout reaches past the box (a long
    -- aligned row, say) the canvas is scaled down about the centre until it
    -- fits: a view only. Saved positions, node sizes and the hubs on screen
    -- are untouched. See FitPreviewCanvas.
    local previewCanvas = CreateFrame("Frame", nil, ringContainer)
    previewCanvas:SetSize(534, 430)
    previewCanvas:SetPoint("CENTER", ringContainer, "CENTER")
    previewCanvas:SetFrameLevel(ringContainer:GetFrameLevel() + 2)
    tab.previewCanvas = previewCanvas

    local previewLogoFrame = CreateFrame("Frame", nil, previewCanvas, "BackdropTemplate")
    previewLogoFrame:SetSize(48, 48)
    previewLogoFrame:SetFrameLevel(previewCanvas:GetFrameLevel() + 20)
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

            -- The logo's own scale: the canvas may be scaled down, and a
            -- cursor move then covers more canvas than screen.
            local scale = self:GetEffectiveScale()
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
                rawX, rawY = ActionHub:SnapMovePosition(previewCanvas, rawX, rawY, self)
                newOffsetX = rawX - cx
                newOffsetY = rawY - cy

                activeDB.logoOffsetX = newOffsetX
                activeDB.logoOffsetY = newOffsetY

                f:ClearAllPoints()
                f:SetPoint("CENTER", previewCanvas, "TOPLEFT", cx + newOffsetX, cy + newOffsetY)
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
    tab.magneticGapSlider = MakePreviewSpacingSlider(L["Gap"], "magneticGap", -10, 10, 45)


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
            print(L["|cffff0000Oxed Hub:|r Sharing module unavailable."])
            return
        end
        local idx = ActionHub:GetActiveHubIndex()
        local hub = ActionHub:GetActiveHubDB()
        local label = (type(hub) == "table" and hub.name) or (L["Hub "] .. tostring(idx))
        Share:ShowChannelPicker("hubs", { hubIndex = idx }, label)
    end)
    shareHubBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["BTN_SHARE"] or "Share", 1, 0.82, 0)
        GameTooltip:AddLine(L["Share only the hub you are editing."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Others with Oxed Hub can click to import it."], 0.8, 0.8, 0.8, true)
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
        local titleText = L["AH_GRID_LABEL"] and string.gsub(L["AH_GRID_LABEL"], ":? ?%%s", "") or L["Grid"]
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
        
        local snapTitle = L["AH_SNAP_LABEL"] and string.gsub(L["AH_SNAP_LABEL"], ":? ?%%s", "") or L["Snap"]
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
    if not current or current:match("^Hub %d+$") then current = L["Hub "] .. hubIndex end

    StaticPopupDialogs["OXEDHUB_RENAME_HUB"] = {
        text = L["Rename this hub to:"],
        button1 = ACCEPT or L["Accept"],
        button2 = CANCEL or L["Cancel"],
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
                hubName = L["Hub "] .. i
            end
            hb:SetText(hubName)
            hb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local function ShowHubTooltip(owner)
                GameTooltip:SetOwner(owner, "ANCHOR_TOP")
                GameTooltip:SetText(hubName, 1, 0.82, 0)
                GameTooltip:AddLine(L["|cff00ff00Left-click:|r switch  |cff00ff00Right-click:|r rename"], 1, 1, 1)
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
    if tab.gcdCheck then tab.gcdCheck:SetChecked(db.showGlobalCooldown == true) end
    if tab.rangeCheckToggle then tab.rangeCheckToggle:SetChecked(db.enableRangeCheck ~= false) end

    local dualLayoutNames = {
        horizontal = L["LAYOUT_HORIZONTAL"] or "Horizontal",
        vertical = L["LAYOUT_VERTICAL"] or "Vertical"
    }
    if tab.dualLayoutBtn then
        tab.dualLayoutBtn:OverrideText(dualLayoutNames[db.dualSideLayout or "horizontal"] or L["Horizontal"])
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
    if tab.quadBtn then tab.quadBtn:OverrideText(quadNames[quadrant] or L["Bottom Right"]) end

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
    if tab.styleBtn then tab.styleBtn:OverrideText(styleNames[db.style or "square"] or L["Squares"]) end

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
    -- The canvas, when there is one: everything below positions on it.
    local ringContainer = tab.previewCanvas or tab.ringContainer
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
                elseif s.type == "module" then
                    local name, action = ActionHub:DescribeModuleNode(s.id)
                    GameTooltip:SetText((L["Module: %s"]):format(name or tostring(s.id)))
                    if action then GameTooltip:AddLine(action, 1, 1, 1) end
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
                    local getItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
                    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                    currentSlot.icon = (getItemIcon and getItemIcon(itemID))
                    currentSlot.label = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or (getItemInfo and getItemInfo(itemID)) or tostring(itemID)
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
                        rootDescription:CreateTitle(L["Align Group"])
                        rootDescription:CreateButton(L["Align Vertically"], function()
                            ActionHub:AlignGroup(self.slotSide, self.slotIndex, "vertical")
                        end)
                        rootDescription:CreateButton(L["Align Horizontally"], function()
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
                elseif slot.type == "module" then
                    btn.icon:SetTexture(ActionHub:GetModuleNodeIcon(slot.id))
                    btn.icon:Show()
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
    self:FitPreviewCanvas(tab)

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
            tab.previewLogo:SetPoint("CENTER", tab.previewCanvas or tab.ringContainer, "TOPLEFT", 256 + (db.logoOffsetX or 0), -204 + (db.logoOffsetY or 0))
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
        module = true,
        settings = true,
    }
    activeDB.visibleTabs.settings = true
    -- Spellbook tab is opt-in: default OFF for existing hubs too (nil would read as
    -- "shown"). Only nil is migrated so a toggled choice persists.
    if activeDB.visibleTabs.spell == nil then activeDB.visibleTabs.spell = false end
    -- Modules is new: shown on every hub until the player hides it.
    if activeDB.visibleTabs.module == nil then activeDB.visibleTabs.module = true end

    if not activeDB.visibleTabs[dialog.selectedType] then
        for _, catType in ipairs({"toy", "emote", "trigger", "marker", "mount", "item", "spell", "module", "settings"}) do
            if activeDB.visibleTabs[catType] then
                dialog.selectedType = catType
                break
            end
        end
    end

    local yOffset = -92
    if dialog.sidebarButtons then
        for _, container in ipairs(dialog.sidebarButtons) do
            local shown = activeDB.visibleTabs[container.catType]
            if shown then
                container:ClearAllPoints()
                container:SetPoint("TOPLEFT", dialog, "TOPLEFT", -34, yOffset)
                container:Show()
                yOffset = yOffset - 48
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
            { name = L["Reactions"], type = "emote",    icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Kiss.png" },
            { name = L["Triggers"],  type = "trigger",  icon = 236248 },
            { name = L["Markers"],   type = "marker",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
            { name = L["Mounts"],    type = "mount",    icon = "Interface\\Icons\\MountJournalPortrait" },
            { name = L["Items"],     type = "item",     icon = 3753262 },
            { name = L["Spells"],    type = "spell",    icon = "Interface\\Icons\\INV_Misc_Book_09" },
            { name = L["Modules"],   type = "module",   icon = "Interface\\Icons\\INV_Gizmo_02" },
            { name = L["Settings"],  type = "settings", icon = 4548872 }
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

        dialog.animationPicker = CreateEditorPicker(L["Animation"], 26, -60,
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

        dialog.toyMacroPicker = CreateEditorPicker(L["Toy Macro"], 26, -10,
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
            { key = "module",   label = L["Modules"] },
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
                    module = true,
                    settings = true,
                }
                activeDB.visibleTabs[def.key] = self:GetChecked()

                -- Ensure at least one tab is shown
                local anyShown = false
                for _, k in ipairs({"toy", "emote", "trigger", "marker", "mount", "item", "spell", "module"}) do
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


-- ── More options: buttons and visibility, per hub ─────────────────────────
-- One window per hub, bound to that hub's saved table, built the first time
-- it is asked for.
local hubOptionWindows = {}

local function RefreshHubLook()
    ActionHub:RefreshAllWidgets()
    ActionHub:UpdateCombatVisibilityTicker()
    ActionHub:UpdateWidgetCooldowns()
    ActionHub:UpdateItemCounts()
end

function ActionHub:ShowHubOptions()
    local API = OxedHub.ModuleAPI
    if not (API and API.CreateOptionsWindow) then return end
    for _, w in pairs(hubOptionWindows) do w:Hide() end

    local index = self:GetActiveHubIndex()
    local db = self:GetActiveHubDB()
    local w = hubOptionWindows[index]
    if not w then
        w = API:CreateOptionsWindow((db.name or (L["Hub "] .. index)) .. L[": more options"], 460, 520)
        hubOptionWindows[index] = w

        -- The visibility choice keeps the older "Hide In Combat" box in step.
        db.visibility = self:GetVisibilityMode(db)
        w:AddChoice(db, "visibility", L["Show the hub"], {
            { value = "always", text = L["Always"] },
            { value = "hideCombat", text = L["Hidden in combat"] },
            { value = "onlyCombat", text = L["Only in combat"] },
            { value = "mouseover", text = L["On mouseover"] },
        }, function(value)
            db.hideInCombat = (value == "hideCombat")
            local tab = ActionHub.tab
            if tab and tab.hideCombatToggle then tab.hideCombatToggle:SetChecked(db.hideInCombat) end
            RefreshHubLook()
        end)
        w:AddCheckbox(db, "hideMounted", L["Hide while mounted"], nil, RefreshHubLook)
        w:AddSlider(db, "fadedAlpha", L["When hidden, opacity"], 0, 1, 0.05, "%s: %.2f", RefreshHubLook)
        w:AddNote(L["A hidden hub comes back while the mouse is over it."])

        w:AddCheckbox(db, "manaTint", L["Blue when short of mana or energy"], nil, RefreshHubLook)
        w:AddCheckbox(db, "desatOnCooldown", L["Grey icons while on cooldown"], nil, RefreshHubLook)
        w:AddSlider(db, "cooldownAlpha", L["Icon opacity on cooldown"], 0.2, 1, 0.05, "%s: %.2f", RefreshHubLook)
        w:AddCheckbox(db, "showItemCount", L["How many of an item you carry"], nil, RefreshHubLook)
        w:AddCheckbox(db, "showKeybind", L["Show the key on each node"], nil, RefreshHubLook)
        w:AddSlider(db, "iconZoom", L["Icon zoom"], 0, 20, 1, "%s: %d", RefreshHubLook)
        w:AddCheckbox(db, "tooltipInCombat", L["Tooltips in combat"],
            L["Off, hovering a node in a fight shows no tooltip."])
    end
    w:Show()
end
