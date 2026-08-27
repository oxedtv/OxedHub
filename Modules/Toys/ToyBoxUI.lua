local addonName, OxedHub = ...

local Toys = OxedHub.Toys or {}
OxedHub.Toys = Toys
local L = OxedHub.L

local selectedBoxId = "all"
local toyBoxPanel = nil

local function GetCursorToyID()
    local infoType, itemID = GetCursorInfo()
    if infoType == "item" and itemID then
        if C_ToyBox.GetToyInfo(itemID) then
            return itemID
        end
    end
    return nil
end

local function ApplyModernScroll(scrollFrame)
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll and OxedHub.UIComponents.Scroll.StyleFrame then
        OxedHub.UIComponents.Scroll.StyleFrame(scrollFrame)
    end
end

-- Sidebar rows are 140px wide and the name gets about 90 of them, which is
-- roughly eleven characters. Truncating produced labels like "Stuff & Ca...",
-- so the font steps down until the name fits instead. The row tooltip still
-- carries the full name for anything that stays too long even at the floor.
local BOX_NAME_SIZES = { 12, 11, 10, 9 }

local function FitBoxName(fontString, text)
    text = text or ""
    local font, _, flags = fontString:GetFont()
    local available = fontString:GetWidth()

    -- Before the first layout pass the width is not known yet; fall back to the
    -- default size rather than shrinking on a bad measurement.
    if not font or not available or available <= 0 then
        fontString:SetText(text)
        return
    end

    for _, size in ipairs(BOX_NAME_SIZES) do
        fontString:SetFont(font, size, flags)
        fontString:SetText(text)
        if fontString:GetStringWidth() <= available then return end
    end
end

local function GetToySettings()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return {} end
    profile.toyBoxSettings = profile.toyBoxSettings or {
        showToyNames = false,
        toyNameFontSize = 9,
        hideButtonTooltips = false,
        isLocked = true,
        gridIconSize = 40,
        dockIconSize = 36,
        miniIcon = 135933,
        miniIconAuto = true,
        showDockHearthstone = true,
        showDockRandomToy = true,
    }
    return profile.toyBoxSettings
end

-- Dropdown of ready-made boxes. Each entry shows how many owned toys it would
-- gather, so an empty suggestion is obvious before it is picked.
function Toys:ShowSuggestedBoxMenu(anchorFrame)
    if self.EnsureToyData then self:EnsureToyData(true) end

    local menu = {}
    for _, def in ipairs(self.SUGGESTED_BOXES) do
        local count = #self:GetSuggestedBoxToys(def)
        table.insert(menu, {
            text = string.format("%s  |cff888888(%d)|r", def.name, count),
            icon = def.icon,
            disabled = count == 0,
            notCheckable = true,
            func = function()
                local boxId, info = Toys:CreateSuggestedBox(def.key)
                if not boxId then
                    UIErrorsFrame:AddExternalErrorMessage(tostring(info))
                    return
                end
                selectedBoxId = boxId
                Toys:RefreshToyBoxesUI()
                print(("|cff00d9d9Oxed Hub:|r created |cffffd100%s|r with %d toys.")
                    :format(def.name, tonumber(info) or 0))
            end,
        })
    end

    -- Rebuilding is destructive, so it sits at the bottom behind a confirm
    -- rather than next to the harmless "create one box" entries above.
    table.insert(menu, {
        text = "|cffff8000Rebuild default boxes|r",
        notCheckable = true,
        func = function()
            StaticPopupDialogs["OXEDHUB_CONFIRM_REBUILD_BOXES"] = {
                text = "Rebuild the shipped boxes?\n\n|cff888888They are recreated from the current categories. Any toy you added to or removed from one of them is lost. Your own boxes and your collection are untouched.|r",
                button1 = L["SETTINGS_BTN_YES"] or "Yes",
                button2 = L["SETTINGS_BTN_CANCEL"] or "Cancel",
                OnAccept = function()
                    local count = Toys:RebuildDefaultBoxes()
                    print(("|cff00d9d9Oxed Hub:|r rebuilt %d default box(es)."):format(count))
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("OXEDHUB_CONFIRM_REBUILD_BOXES")
        end,
    })

    if not self._suggestMenu then
        self._suggestMenu = CreateFrame("Frame", "OxedHubToySuggestMenu", UIParent, "UIDropDownMenuTemplate")
    end

    -- EasyMenu is gone on newer clients; same fallback the minimap menu uses.
    if EasyMenu then
        EasyMenu(menu, self._suggestMenu, anchorFrame or "cursor", 0, 0, "MENU")
    else
        UIDropDownMenu_Initialize(self._suggestMenu, function()
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.func = item.func
                info.icon = item.icon
                info.disabled = item.disabled
                info.notCheckable = item.notCheckable
                UIDropDownMenu_AddButton(info)
            end
        end)
        ToggleDropDownMenu(1, nil, self._suggestMenu, anchorFrame or "cursor", 0, 0)
    end
end

-- ============================================================================
-- MODAL: Create New Box / Edit Box Dialog (BasicFrameTemplate)
-- ============================================================================
function Toys:ShowBoxEditorDialog(editingBoxId)
    local dialog = _G["OxedHubToyBoxEditDialog"]
    if not dialog then
        dialog = CreateFrame("Frame", "OxedHubToyBoxEditDialog", UIParent, "BasicFrameTemplate")
        dialog:SetSize(360, 240)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(9900)
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

        if dialog.CloseButton then
            dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)
        end

        -- Name Input Label & EditBox
        local nameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -38)
        nameLabel:SetText("Box Name:")

        local editBox = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        editBox:SetSize(315, 24)
        editBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -4)
        editBox:SetAutoFocus(true)
        editBox:SetScript("OnTextChanged", function()
            if dialog.errorText then dialog.errorText:Hide() end
        end)
        dialog.editBox = editBox

        -- Error warning text
        local errorText = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
        errorText:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)
        errorText:SetText("|cFFFF4444Please enter a box name!|r")
        errorText:Hide()
        dialog.errorText = errorText

        -- Icon Picker Section
        local iconLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconLabel:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -4, -18)
        iconLabel:SetText("Choose Box Icon:")

        -- Large Interactive Icon Preview Button
        local iconBtn = CreateFrame("Button", nil, dialog, "BackdropTemplate")
        iconBtn:SetSize(38, 38)
        iconBtn:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 4, -6)
        iconBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        iconBtn:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
        iconBtn:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.9)

        local iconPreview = iconBtn:CreateTexture(nil, "ARTWORK")
        iconPreview:SetPoint("TOPLEFT", 3, -3)
        iconPreview:SetPoint("BOTTOMRIGHT", -3, 3)
        iconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconBtn.iconPreview = iconPreview
        dialog.iconPreview = iconPreview

        local iconHl = iconBtn:CreateTexture(nil, "HIGHLIGHT")
        iconHl:SetAllPoints()
        iconHl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        iconHl:SetBlendMode("ADD")

        local function OpenSharedIconPicker()
            if OxedHub.IconPicker then
                OxedHub.IconPicker:Open({
                    title = "Choose ToyBox Icon",
                    initialValue = dialog.selectedIcon or 135933,
                    onSelect = function(chosenIcon)
                        dialog.selectedIcon = chosenIcon
                        local resolved = Toys:GetBoxIconTexture(chosenIcon)
                        dialog.iconPreview:SetTexture(resolved or 135933)
                    end
                })
            end
        end

        iconBtn:SetScript("OnClick", OpenSharedIconPicker)
        iconBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Click to open Icon Picker")
            GameTooltip:Show()
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- [ Browse Icons... ] Button
        local browseBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        browseBtn:SetSize(130, 24)
        browseBtn:SetPoint("LEFT", iconBtn, "RIGHT", 12, 6)
        browseBtn:SetText("Browse Icons...")
        browseBtn:SetNormalFontObject("GameFontNormalSmall")
        browseBtn:SetScript("OnClick", OpenSharedIconPicker)

        local browseHint = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        browseHint:SetPoint("TOPLEFT", browseBtn, "BOTTOMLEFT", 0, -2)
        browseHint:SetText("Search 10,000+ WoW icons")

        -- Save Button (with name validation!)
        local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveBtn:SetSize(110, 24)
        saveBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 16)
        saveBtn:SetText("Save Box")
        saveBtn:SetScript("OnClick", function()
            local rawName = dialog.editBox:GetText() or ""
            local name = rawName:match("^%s*(.-)%s*$")
            if not name or name == "" then
                dialog.errorText:Show()
                UIErrorsFrame:AddExternalErrorMessage("Please enter a box name!")
                dialog.editBox:SetFocus()
                return
            end

            local icon = dialog.selectedIcon or 135933
            if dialog.editingBoxId then
                Toys:RenameToyBox(dialog.editingBoxId, name, icon)
            else
                local newId = Toys:CreateToyBox(name, icon)
                if newId then selectedBoxId = newId end
            end
            dialog:Hide()
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        end)
        dialog.saveBtn = saveBtn

        -- Cancel Button
        local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelBtn:SetSize(90, 24)
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() dialog:Hide() end)
    end

    dialog.editingBoxId = editingBoxId
    if dialog.errorText then dialog.errorText:Hide() end

    if editingBoxId then
        local box = Toys:GetToyBox(editingBoxId)
        if dialog.TitleText then
            dialog.TitleText:SetText("Edit ToyBox: " .. (box and box.name or ""))
        end
        dialog.editBox:SetText(box and box.name or "")
        dialog.selectedIcon = box and box.icon or 135933
    else
        if dialog.TitleText then
            dialog.TitleText:SetText("Create New ToyBox")
        end
        dialog.editBox:SetText("")
        dialog.selectedIcon = 135933
    end

    local resolvedTex = Toys:GetBoxIconTexture(dialog.selectedIcon)
    dialog.iconPreview:SetTexture(resolvedTex or 135933)

    dialog:Show()
end

-- ============================================================================
-- HIDDEN BOXES MENU
-- ============================================================================
-- A dropdown rather than a dialog: restoring is a single click on a name, and a
-- modal window for that would be heavier than the action deserves.
function Toys:ShowHiddenBoxesMenu(anchor)
    local hidden = self:GetHiddenBoxes()
    if #hidden == 0 then return end

    MenuUtil.CreateContextMenu(anchor, function(owner, root)
        root:CreateTitle("Hidden boxes")

        for _, entry in ipairs(hidden) do
            local label = ("%s |cff888888(%d)|r"):format(entry.name, entry.count)
            root:CreateButton(label, function()
                Toys:SetBoxHidden(entry.id, false)
            end)
        end

        root:CreateDivider()
        root:CreateButton("Show all", function()
            for _, entry in ipairs(hidden) do
                Toys:SetBoxHidden(entry.id, false)
            end
        end)
    end)
end

-- ============================================================================
-- MODAL: TOYBOX SETTINGS DIALOG (BasicFrameTemplate - Matching Pick Animation)
-- ============================================================================
function Toys:ShowToyBoxesSettingsDialog()
    local dialog = _G["OxedHubToyBoxSettingsDialog"]
    if not dialog then
        dialog = CreateFrame("Frame", "OxedHubToyBoxSettingsDialog", UIParent, "BasicFrameTemplate")
        dialog:SetSize(450, 380)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(9950)
        dialog:SetClampedToScreen(true)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

        if dialog.TitleText then
            dialog.TitleText:SetText("ToyBox Settings")
        end

        local function CancelSettings()
            if dialog.savedSnapshot then
                local cfg = GetToySettings()
                for k, v in pairs(dialog.savedSnapshot) do
                    cfg[k] = v
                end
                if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
                if Toys.RefreshToyDock then Toys:RefreshToyDock() end
            end
            dialog:Hide()
        end

        if dialog.CloseButton then
            dialog.CloseButton:SetScript("OnClick", CancelSettings)
        end

        -- ====================================================================
        -- TOP TAB STRIP (PanelTopTabButtonTemplate)
        -- ====================================================================
        local tabLine = dialog:CreateTexture(nil, "ARTWORK")
        tabLine:SetPoint("TOPLEFT", dialog, "TOPLEFT", 14, -53)
        tabLine:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -14, -53)
        tabLine:SetHeight(2)
        tabLine:SetColorTexture(1, 0.82, 0, 0.1)

        local tabMainBtn = CreateFrame("Button", nil, dialog, "PanelTopTabButtonTemplate")
        tabMainBtn:SetText("Main Window Grid")
        PanelTemplates_TabResize(tabMainBtn, 14, nil, 130)
        tabMainBtn:SetPoint("BOTTOMLEFT", tabLine, "TOPLEFT", 6, -2)

        local tabDockBtn = CreateFrame("Button", nil, dialog, "PanelTopTabButtonTemplate")
        tabDockBtn:SetText("Floating Dock")
        PanelTemplates_TabResize(tabDockBtn, 14, nil, 130)
        tabDockBtn:SetPoint("LEFT", tabMainBtn, "RIGHT", -12, 0)

        -- Panels container
        local mainPanel = CreateFrame("Frame", nil, dialog)
        mainPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -62)
        mainPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 44)
        dialog.mainPanel = mainPanel

        local dockPanel = CreateFrame("Frame", nil, dialog)
        dockPanel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -62)
        dockPanel:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 44)
        dockPanel:Hide()
        dialog.dockPanel = dockPanel

        local function SwitchTab(tabName)
            if tabName == "Main" then
                mainPanel:Show()
                dockPanel:Hide()
                PanelTemplates_SelectTab(tabMainBtn)
                PanelTemplates_DeselectTab(tabDockBtn)
            else
                mainPanel:Hide()
                dockPanel:Show()
                PanelTemplates_DeselectTab(tabMainBtn)
                PanelTemplates_SelectTab(tabDockBtn)
            end
        end

        tabMainBtn:SetScript("OnClick", function() SwitchTab("Main") end)
        tabDockBtn:SetScript("OnClick", function() SwitchTab("Dock") end)
        dialog.SwitchTab = SwitchTab

        -- ====================================================================
        -- TAB 1: MAIN WINDOW GRID SETTINGS
        -- ====================================================================
        local showNamesCb = CreateFrame("CheckButton", "$parent_ShowNamesCb", mainPanel, "UICheckButtonTemplate")
        showNamesCb:SetPoint("TOPLEFT", mainPanel, "TOPLEFT", 8, -10)
        showNamesCb.text:SetText("Show toy names under icons in grid")
        showNamesCb.text:SetFontObject("GameFontHighlightSmall")
        showNamesCb:SetScript("OnClick", function(self)
            local cfg = GetToySettings()
            cfg.showToyNames = self:GetChecked()
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        end)
        dialog.showNamesCb = showNamesCb

        -- Font Size Slider
        local fontTitle = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fontTitle:SetPoint("TOPLEFT", showNamesCb, "BOTTOMLEFT", 6, -14)
        fontTitle:SetText("Toy Names Font Size:")

        local fontSlider = CreateFrame("Slider", "$parent_FontSlider", mainPanel, "OptionsSliderTemplate")
        fontSlider:SetSize(180, 16)
        fontSlider:SetPoint("TOPLEFT", fontTitle, "BOTTOMLEFT", 0, -8)
        fontSlider:SetMinMaxValues(7, 13)
        fontSlider:SetValueStep(1)

        local fontSliderLow = _G[fontSlider:GetName() .. "Low"]
        local fontSliderHigh = _G[fontSlider:GetName() .. "High"]
        local fontSliderText = _G[fontSlider:GetName() .. "Text"]
        if fontSliderLow then fontSliderLow:SetText("7") end
        if fontSliderHigh then fontSliderHigh:SetText("13") end
        if fontSliderText then fontSliderText:SetText("") end

        local fontValText = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontValText:SetPoint("LEFT", fontSlider, "RIGHT", 14, 0)
        dialog.fontValText = fontValText

        fontSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            fontValText:SetText(value .. " pt")
            local cfg = GetToySettings()
            cfg.toyNameFontSize = value
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        end)
        dialog.fontSlider = fontSlider

        -- Grid Icon Size Slider
        local gridIconTitle = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        gridIconTitle:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", 0, -22)
        gridIconTitle:SetText("Grid Toy Icon Size:")

        local iconSizeSlider = CreateFrame("Slider", "$parent_IconSizeSlider", mainPanel, "OptionsSliderTemplate")
        iconSizeSlider:SetSize(180, 16)
        iconSizeSlider:SetPoint("TOPLEFT", gridIconTitle, "BOTTOMLEFT", 0, -8)
        iconSizeSlider:SetMinMaxValues(28, 50)
        iconSizeSlider:SetValueStep(2)

        local iconSizeLow = _G[iconSizeSlider:GetName() .. "Low"]
        local iconSizeHigh = _G[iconSizeSlider:GetName() .. "High"]
        local iconSizeText = _G[iconSizeSlider:GetName() .. "Text"]
        if iconSizeLow then iconSizeLow:SetText("28") end
        if iconSizeHigh then iconSizeHigh:SetText("50") end
        if iconSizeText then iconSizeText:SetText("") end

        local iconValText = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        iconValText:SetPoint("LEFT", iconSizeSlider, "RIGHT", 14, 0)
        dialog.iconValText = iconValText

        iconSizeSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor((value / 2) + 0.5) * 2
            iconValText:SetText(value .. " px")
            local cfg = GetToySettings()
            cfg.gridIconSize = value
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        end)
        dialog.iconSizeSlider = iconSizeSlider

        -- Spacing between toys in the addon grid.
        local gridGapSlider = CreateFrame("Slider", "OxedHubToyGridGapSlider", mainPanel, "OptionsSliderTemplate")
        gridGapSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -28)
        gridGapSlider:SetWidth(200)
        gridGapSlider:SetMinMaxValues(0, 20)
        gridGapSlider:SetValueStep(1)
        gridGapSlider:SetObeyStepOnDrag(true)

        local gridGapLow  = gridGapSlider.Low  or _G[gridGapSlider:GetName() .. "Low"]
        local gridGapHigh = gridGapSlider.High or _G[gridGapSlider:GetName() .. "High"]
        local gridGapText = gridGapSlider.Text or _G[gridGapSlider:GetName() .. "Text"]
        if gridGapLow  then gridGapLow:SetText("0") end
        if gridGapHigh then gridGapHigh:SetText("20") end
        if gridGapText then gridGapText:SetText("Spacing Between Toys") end

        local gridGapVal = mainPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        gridGapVal:SetPoint("LEFT", gridGapSlider, "RIGHT", 14, 0)

        gridGapSlider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value + 0.5)
            gridGapVal:SetText(value .. " px")
            GetToySettings().gridSpacing = value
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
        end)
        dialog.gridGapSlider = gridGapSlider

        -- ====================================================================
        -- TAB 2: FLOATING DOCK SETTINGS
        -- ====================================================================
        local showDockCb = CreateFrame("CheckButton", "$parent_ShowDockCb", dockPanel, "UICheckButtonTemplate")
        showDockCb:SetPoint("TOPLEFT", dockPanel, "TOPLEFT", 8, -4)
        showDockCb.text:SetText("Show Floating ToyBox / Button on screen")
        showDockCb.text:SetFontObject("GameFontHighlightSmall")
        showDockCb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            local cfg = GetToySettings()
            cfg.showOnScreenDock = isChecked
            local profile = OxedHub.db and OxedHub.db.profile
            if isChecked then
                if profile then profile.toyBoxDockState = "expanded" end
                Toys:ExpandToyDock()
            else
                if profile then profile.toyBoxDockState = "hidden" end
                if Toys.ToyboxFrame then Toys.ToyboxFrame:Hide() end
                if Toys.MiniButton then Toys.MiniButton:Hide() end
            end
        end)
        dialog.showDockCb = showDockCb

        local dockIconTitle = dockPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        dockIconTitle:SetPoint("TOPLEFT", showDockCb, "BOTTOMLEFT", 0, -8)
        dockIconTitle:SetText("Dock Toy Icon Size:")

        local dockSizeSlider = CreateFrame("Slider", "$parent_DockSizeSlider", dockPanel, "OptionsSliderTemplate")
        dockSizeSlider:SetSize(180, 16)
        dockSizeSlider:SetPoint("TOPLEFT", dockIconTitle, "BOTTOMLEFT", 0, -6)
        dockSizeSlider:SetMinMaxValues(24, 48)
        dockSizeSlider:SetValueStep(2)

        local dockSizeLow = _G[dockSizeSlider:GetName() .. "Low"]
        local dockSizeHigh = _G[dockSizeSlider:GetName() .. "High"]
        local dockSizeText = _G[dockSizeSlider:GetName() .. "Text"]
        if dockSizeLow then dockSizeLow:SetText("24") end
        if dockSizeHigh then dockSizeHigh:SetText("48") end
        if dockSizeText then dockSizeText:SetText("") end

        local dockValText = dockPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dockValText:SetPoint("LEFT", dockSizeSlider, "RIGHT", 14, 0)
        dialog.dockValText = dockValText

        dockSizeSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor((value / 2) + 0.5) * 2
            dockValText:SetText(value .. " px")
            local cfg = GetToySettings()
            cfg.dockIconSize = value
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)
        dialog.dockSizeSlider = dockSizeSlider

        -- Spacing between toys on the floating panel.
        local dockGapSlider = CreateFrame("Slider", "OxedHubToyDockGapSlider", dockPanel, "OptionsSliderTemplate")
        dockGapSlider:SetPoint("TOPLEFT", dockSizeSlider, "BOTTOMLEFT", 0, -28)
        dockGapSlider:SetWidth(200)
        dockGapSlider:SetMinMaxValues(0, 20)
        dockGapSlider:SetValueStep(1)
        dockGapSlider:SetObeyStepOnDrag(true)

        local dockGapLow  = dockGapSlider.Low  or _G[dockGapSlider:GetName() .. "Low"]
        local dockGapHigh = dockGapSlider.High or _G[dockGapSlider:GetName() .. "High"]
        local dockGapText = dockGapSlider.Text or _G[dockGapSlider:GetName() .. "Text"]
        if dockGapLow  then dockGapLow:SetText("0") end
        if dockGapHigh then dockGapHigh:SetText("20") end
        if dockGapText then dockGapText:SetText("Spacing Between Toys") end

        local dockGapVal = dockPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dockGapVal:SetPoint("LEFT", dockGapSlider, "RIGHT", 14, 0)

        dockGapSlider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value + 0.5)
            dockGapVal:SetText(value .. " px")
            GetToySettings().dockSpacing = value
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)
        dialog.dockGapSlider = dockGapSlider

        -- Minimize Icon Picker
        local miniLabel = dockPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        miniLabel:SetPoint("TOPLEFT", dockGapSlider, "BOTTOMLEFT", 0, -22)
        miniLabel:SetText("Floating Minimize Button Icon:")

        local miniIconBtn = CreateFrame("Button", nil, dockPanel, "BackdropTemplate")
        miniIconBtn:SetSize(34, 34)
        miniIconBtn:SetPoint("TOPLEFT", miniLabel, "BOTTOMLEFT", 0, -4)
        miniIconBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        miniIconBtn:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
        miniIconBtn:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.9)

        local miniIconPreview = miniIconBtn:CreateTexture(nil, "ARTWORK")
        miniIconPreview:SetPoint("TOPLEFT", 3, -3)
        miniIconPreview:SetPoint("BOTTOMRIGHT", -3, 3)
        miniIconPreview:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dialog.miniIconPreview = miniIconPreview

        local function OpenMiniIconPicker()
            if OxedHub.IconPicker then
                OxedHub.IconPicker:Open({
                    title = "Choose Minimized Widget Icon",
                    initialValue = dialog.selectedMiniIcon or 135933,
                    onSelect = function(chosenIcon)
                        dialog.selectedMiniIcon = chosenIcon
                        dialog.miniAutoCb:SetChecked(false)
                        local resolved = Toys:GetBoxIconTexture(chosenIcon)
                        dialog.miniIconPreview:SetTexture(resolved or 135933)
                        local cfg = GetToySettings()
                        cfg.miniIcon = chosenIcon
                        cfg.miniIconAuto = false
                        if Toys.RefreshToyDock then Toys:RefreshToyDock() end
                    end
                })
            end
        end

        miniIconBtn:SetScript("OnClick", OpenMiniIconPicker)
        local miniBrowseBtn = CreateFrame("Button", nil, dockPanel, "UIPanelButtonTemplate")
        miniBrowseBtn:SetSize(135, 22)
        miniBrowseBtn:SetPoint("LEFT", miniIconBtn, "RIGHT", 10, 6)
        miniBrowseBtn:SetText("Change Icon...")
        miniBrowseBtn:SetNormalFontObject("GameFontNormalSmall")
        miniBrowseBtn:SetScript("OnClick", OpenMiniIconPicker)

        local miniAutoCb = CreateFrame("CheckButton", "$parent_MiniAutoCb", dockPanel, "UICheckButtonTemplate")
        miniAutoCb:SetPoint("TOPLEFT", miniBrowseBtn, "BOTTOMLEFT", -4, -2)
        miniAutoCb.text:SetText("Auto: Use active box icon")
        miniAutoCb.text:SetFontObject("GameFontDisableSmall")
        miniAutoCb:SetScript("OnClick", function(self)
            local cfg = GetToySettings()
            cfg.miniIconAuto = self:GetChecked()
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)
        dialog.miniAutoCb = miniAutoCb

        -- Checkboxes
        local showHsCb = CreateFrame("CheckButton", "$parent_ShowHsCb", dockPanel, "UICheckButtonTemplate")
        showHsCb:SetPoint("TOPLEFT", miniIconBtn, "BOTTOMLEFT", -4, -6)
        showHsCb.text:SetText("Show Random Hearthstone in Floating Dock")
        showHsCb.text:SetFontObject("GameFontHighlightSmall")
        showHsCb:SetScript("OnClick", function(self)
            local cfg = GetToySettings()
            cfg.showDockHearthstone = self:GetChecked()
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)
        dialog.showHsCb = showHsCb

        local showRandomCb = CreateFrame("CheckButton", "$parent_ShowRandomCb", dockPanel, "UICheckButtonTemplate")
        showRandomCb:SetPoint("TOPLEFT", showHsCb, "BOTTOMLEFT", 0, -2)
        showRandomCb.text:SetText("Show Random Toy (Dice) in Floating Dock")
        showRandomCb.text:SetFontObject("GameFontHighlightSmall")
        showRandomCb:SetScript("OnClick", function(self)
            local cfg = GetToySettings()
            cfg.showDockRandomToy = self:GetChecked()
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)
        dialog.showRandomCb = showRandomCb

        local hideTooltipsCb = CreateFrame("CheckButton", "$parent_HideTooltipsCb", dockPanel, "UICheckButtonTemplate")
        hideTooltipsCb:SetPoint("TOPLEFT", showRandomCb, "BOTTOMLEFT", 0, -2)
        hideTooltipsCb.text:SetText("Hide action tooltips on buttons")
        hideTooltipsCb.text:SetFontObject("GameFontHighlightSmall")
        hideTooltipsCb:SetScript("OnClick", function(self)
            local cfg = GetToySettings()
            cfg.hideButtonTooltips = self:GetChecked()
        end)
        dialog.hideTooltipsCb = hideTooltipsCb

        -- ====================================================================
        -- BOTTOM ACTIONS: SAVE & CLOSE / CANCEL
        -- ====================================================================
        local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveBtn:SetSize(110, 24)
        saveBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -16, 14)
        saveBtn:SetText("Save & Close")
        saveBtn:SetScript("OnClick", function()
            local cfg = GetToySettings()
            cfg.showToyNames = dialog.showNamesCb:GetChecked()
            cfg.toyNameFontSize = math.floor(dialog.fontSlider:GetValue() + 0.5)
            cfg.gridIconSize = math.floor((dialog.iconSizeSlider:GetValue() / 2) + 0.5) * 2
            cfg.dockIconSize = math.floor((dialog.dockSizeSlider:GetValue() / 2) + 0.5) * 2
            cfg.showOnScreenDock = dialog.showDockCb:GetChecked()
            cfg.miniIcon = dialog.selectedMiniIcon or 135933
            cfg.miniIconAuto = dialog.miniAutoCb:GetChecked()
            cfg.showDockHearthstone = dialog.showHsCb:GetChecked()
            cfg.showDockRandomToy = dialog.showRandomCb:GetChecked()
            cfg.hideButtonTooltips = dialog.hideTooltipsCb:GetChecked()

            dialog.savedSnapshot = nil
            dialog:Hide()
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
            if Toys.RefreshToyDock then Toys:RefreshToyDock() end
        end)

        local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelBtn:SetSize(85, 24)
        cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", CancelSettings)
    end

    local cfg = GetToySettings()
    -- Snapshot settings for rollback on Cancel
    dialog.savedSnapshot = {
        showToyNames = cfg.showToyNames,
        toyNameFontSize = cfg.toyNameFontSize,
        gridIconSize = cfg.gridIconSize,
        dockIconSize = cfg.dockIconSize,
        showOnScreenDock = cfg.showOnScreenDock,
        miniIcon = cfg.miniIcon,
        miniIconAuto = cfg.miniIconAuto,
        showDockHearthstone = cfg.showDockHearthstone,
        showDockRandomToy = cfg.showDockRandomToy,
        hideButtonTooltips = cfg.hideButtonTooltips,
    }

    dialog.SwitchTab("Main")

    dialog.showNamesCb:SetChecked(cfg.showToyNames == true)
    local fontSize = cfg.toyNameFontSize or 9
    dialog.fontSlider:SetValue(fontSize)
    dialog.fontValText:SetText(fontSize .. " pt")

    local iconSize = cfg.gridIconSize or 36
    dialog.iconSizeSlider:SetValue(iconSize)
    dialog.iconValText:SetText(iconSize .. " px")

    if dialog.gridGapSlider then
        dialog.gridGapSlider:SetValue(cfg.gridSpacing or 4)
    end

    local isDockActive = (Toys.ToyboxFrame and Toys.ToyboxFrame:IsShown()) or (Toys.MiniButton and Toys.MiniButton:IsShown()) or (cfg.showOnScreenDock == true)
    dialog.showDockCb:SetChecked(isDockActive == true)

    local dockSize = cfg.dockIconSize or 36
    dialog.dockSizeSlider:SetValue(dockSize)
    dialog.dockValText:SetText(dockSize .. " px")

    if dialog.dockGapSlider then
        dialog.dockGapSlider:SetValue(cfg.dockSpacing or 3)
    end

    dialog.miniAutoCb:SetChecked(cfg.miniIconAuto ~= false)
    dialog.selectedMiniIcon = cfg.miniIcon or 135933
    dialog.miniIconPreview:SetTexture(Toys:GetBoxIconTexture(dialog.selectedMiniIcon) or 135933)
    dialog.showHsCb:SetChecked(cfg.showDockHearthstone ~= false)
    dialog.showRandomCb:SetChecked(cfg.showDockRandomToy ~= false)
    dialog.hideTooltipsCb:SetChecked(cfg.hideButtonTooltips == true)

    dialog:Show()
end

-- ============================================================================
-- MAIN TOYBOXES TAB VIEW
-- ============================================================================
function Toys:ShowToyBoxesTab(parentPanel)
    toyBoxPanel = parentPanel
    local cfg = GetToySettings()

    -- Reuse the addon's own search bar in the header, exactly like the Mixer
    -- sub-tab does, instead of a second box crowding the button row.
    if OxedHub.UI and OxedHub.UI.searchBox then
        local currentText = OxedHub.UI.searchBox:GetText()
        if currentText == (SEARCH or "Search") then currentText = "" end
        Toys._boxSearch = currentText or ""
        OxedHub.UI.searchBox.customSearchHandler = function(_, text)
            if text == (SEARCH or "Search") then text = "" end
            Toys._boxSearch = text or ""
            Toys:RefreshToyBoxesUI()
        end
    end

    if not parentPanel.initialized then
        parentPanel.initialized = true

        -- Left Sidebar: 140px wide (dedicated 28px left inset away from stone border)
        local sidebar = CreateFrame("Frame", nil, parentPanel)
        sidebar:SetPoint("TOPLEFT", parentPanel, "TOPLEFT", 28, 0)
        sidebar:SetPoint("BOTTOMLEFT", parentPanel, "BOTTOMLEFT", 28, 38)
        sidebar:SetWidth(140)
        parentPanel.sidebar = sidebar

        -- Subtle vertical divider (slid 2px right)
        local sideDivider = sidebar:CreateTexture(nil, "ARTWORK")
        sideDivider:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 2, -2)
        sideDivider:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 2, 2)
        sideDivider:SetWidth(1)
        sideDivider:SetColorTexture(1, 1, 1, 0.1)

        local sideHeader = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sideHeader:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 2, -2)
        sideHeader:SetText("|cFFFFD900My ToyBoxes|r")

        -- [ + New Box ] Button at bottom of sidebar
        local newBoxBtn = CreateFrame("Button", nil, sidebar, "UIPanelButtonTemplate")
        newBoxBtn:SetSize(116, 22)
        newBoxBtn:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMLEFT", 2, 2)
        newBoxBtn:SetText("+ New Box")
        newBoxBtn:SetNormalFontObject("GameFontNormalSmall")
        -- Left-click makes an empty box; right-click offers ready-made ones
        -- built from toys the player already owns.
        newBoxBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        newBoxBtn:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" then
                Toys:ShowSuggestedBoxMenu(newBoxBtn)
            else
                Toys:ShowBoxEditorDialog(nil)
            end
        end)
        newBoxBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFFD900New Box|r")
            GameTooltip:AddLine("|cFFFFFFFFClick:|r create an empty box", 1, 1, 1)
            GameTooltip:AddLine("|cFF88AAFFRight-click:|r suggested boxes", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        newBoxBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Scrollable box list
        local boxScroll = CreateFrame("ScrollFrame", "$parent_BoxScroll", sidebar, "UIPanelScrollFrameTemplate")
        boxScroll:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -22)
        boxScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -24, 28)
        
        local boxScrollChild = CreateFrame("Frame", nil, boxScroll)
        boxScrollChild:SetSize(116, 300)
        boxScroll:SetScrollChild(boxScrollChild)
        sidebar.boxScrollChild = boxScrollChild
        ApplyModernScroll(boxScroll)

        -- Right Main Area: Box Contents & Drag Target Grid (dedicated 38px right/bottom insets)
        local content = CreateFrame("Frame", nil, parentPanel)
        content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 10, 0)
        content:SetPoint("BOTTOMRIGHT", parentPanel, "BOTTOMRIGHT", -38, 38)
        parentPanel.content = content

        -- Content Header (Active Box Name + Controls)
        local boxTitle = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        boxTitle:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -2)
        boxTitle:SetText("Favorites")
        content.boxTitle = boxTitle

        local boxCount = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        boxCount:SetPoint("LEFT", boxTitle, "RIGHT", 8, 0)
        content.boxCount = boxCount

        -- [ Show On-Screen Dock ] Toggle Button
        local showDockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        showDockBtn:SetSize(130, 20)
        showDockBtn:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
        showDockBtn:SetText("Open On-Screen Dock")
        showDockBtn:SetNormalFontObject("GameFontNormalSmall")
        showDockBtn:SetScript("OnClick", function()
            if Toys.ToggleToyDock then
                Toys:ToggleToyDock(selectedBoxId)
            end
        end)

        -- [ Settings ] Button
        local settingsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        settingsBtn:SetSize(58, 20)
        settingsBtn:SetPoint("RIGHT", showDockBtn, "LEFT", -4, 0)
        settingsBtn:SetText("Settings")
        settingsBtn:SetNormalFontObject("GameFontNormalSmall")
        settingsBtn:SetScript("OnClick", function()
            Toys:ShowToyBoxesSettingsDialog()
        end)
        content.settingsBtn = settingsBtn

        -- [ Hidden ] Button. Only appears once something is actually hidden --
        -- a permanently visible button for an empty list is just clutter, and
        -- its appearance is the hint that hidden boxes can be brought back.
        --
        -- It sits left of Lock, so its point is set once Lock exists. Anchoring
        -- Lock to this button instead would leave a gap the width of a hidden
        -- frame, since hidden frames keep their position.
        local hiddenBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        hiddenBtn:SetSize(74, 20)
        hiddenBtn:SetNormalFontObject("GameFontNormalSmall")
        hiddenBtn:SetScript("OnClick", function()
            Toys:ShowHiddenBoxesMenu(hiddenBtn)
        end)
        hiddenBtn:SetScript("OnEnter", function(self)
            local s = GetToySettings()
            if s.hideButtonTooltips then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Hidden boxes", 1, 0.85, 0.2)
            GameTooltip:AddLine("Click to bring one back.", 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end)
        hiddenBtn:SetScript("OnLeave", GameTooltip_Hide)
        function hiddenBtn:UpdateHiddenState()
            local hidden = Toys.GetHiddenBoxes and Toys:GetHiddenBoxes() or {}
            if #hidden > 0 then
                self:SetText(("Hidden (%d)"):format(#hidden))
                self:Show()
            else
                self:Hide()
            end
        end
        content.hiddenBtn = hiddenBtn

        -- [ Lock / Unlock ] Toggle Button (Controls [X] Delete Badges)
        local lockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        lockBtn:SetSize(52, 20)
        lockBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)

        hiddenBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        hiddenBtn:UpdateHiddenState()
        lockBtn:SetNormalFontObject("GameFontNormalSmall")
        lockBtn:SetScript("OnClick", function(self)
            local s = GetToySettings()
            s.isLocked = not s.isLocked
            self:UpdateLockState()
            Toys:RefreshToyBoxesUI()
        end)
        function lockBtn:UpdateLockState()
            local s = GetToySettings()
            if s.isLocked then
                self:SetText("Unlock")
            else
                self:SetText("|cFFFF5555Lock|r")
            end
        end
        lockBtn:SetScript("OnEnter", function(self)
            local s = GetToySettings()
            if s.hideButtonTooltips then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if s.isLocked then
                GameTooltip:AddLine("|cFF00FF00Click to Unlock|r")
                GameTooltip:AddLine("Shows [X] delete badges on toy icons so they can be removed.", 1, 1, 1)
            else
                GameTooltip:AddLine("|cFFFF5555Click to Lock|r")
                GameTooltip:AddLine("Hides delete badges to prevent accidental deletion.", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        lockBtn:UpdateLockState()
        content.lockBtn = lockBtn

        -- [ Edit Box ] Button
        local editBoxBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        editBoxBtn:SetSize(58, 20)
        editBoxBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
        editBoxBtn:SetText("Edit Box")
        editBoxBtn:SetNormalFontObject("GameFontNormalSmall")
        editBoxBtn:SetScript("OnClick", function()
            if selectedBoxId and selectedBoxId ~= "all" then Toys:ShowBoxEditorDialog(selectedBoxId) end
        end)
        content.editBoxBtn = editBoxBtn

        -- [ Delete Box ] Button
        local delBoxBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        delBoxBtn:SetSize(66, 20)
        delBoxBtn:SetPoint("RIGHT", editBoxBtn, "LEFT", -4, 0)
        delBoxBtn:SetText("Delete Box")
        delBoxBtn:SetNormalFontObject("GameFontNormalSmall")
        delBoxBtn:SetScript("OnClick", function()
            if selectedBoxId and selectedBoxId ~= "favorites" and selectedBoxId ~= "all" then
                local box = Toys:GetToyBox(selectedBoxId)
                local boxName = (box and box.name) or "this box"
                local toyCount = (box and box.toys and #box.toys) or 0
                Toys:ConfirmDeleteBox(selectedBoxId, boxName, toyCount)
            end
        end)
        content.delBoxBtn = delBoxBtn

        -- Drag Target Hint Label
        local hintText = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hintText:SetPoint("TOPLEFT", boxTitle, "BOTTOMLEFT", 0, -4)
        hintText:SetText("|cFF88AAFF* Drag toys to reorder or into a sidebar box. Drag boxes to reorder them. Right-click a toy to always show it. Shift+click [x] deletes without asking.|r")

        -- Scrollable Grid for Toys with MinimalScrollBar
        local gridScroll = CreateFrame("ScrollFrame", "$parent_GridScroll", content, "UIPanelScrollFrameTemplate")
        gridScroll:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -34)
        gridScroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 4)

        local gridScrollChild = CreateFrame("Frame", nil, gridScroll)
        gridScrollChild:SetSize(480, 400)
        gridScroll:SetScrollChild(gridScrollChild)
        content.gridScrollChild = gridScrollChild
        ApplyModernScroll(gridScroll)

        -- Enable cursor drop onto the grid background (adds at end)
        gridScrollChild:EnableMouse(true)
        gridScrollChild:SetScript("OnReceiveDrag", function()
            local cursorToyID = GetCursorToyID() or Toys._draggedToyID
            if cursorToyID and selectedBoxId and selectedBoxId ~= "all" then
                ClearCursor()
                local ok, err = Toys:AddToyToBox(selectedBoxId, cursorToyID)
                if not ok and err then
                    UIErrorsFrame:AddExternalErrorMessage(err)
                end
                Toys._draggedToyID = nil
            end
        end)
        gridScrollChild:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                local cursorToyID = GetCursorToyID() or Toys._draggedToyID
                if cursorToyID and selectedBoxId and selectedBoxId ~= "all" then
                    ClearCursor()
                    local ok, err = Toys:AddToyToBox(selectedBoxId, cursorToyID)
                    if not ok and err then
                        UIErrorsFrame:AddExternalErrorMessage(err)
                    end
                    Toys._draggedToyID = nil
                end
            end
        end)
    end

    self:RefreshToyBoxesUI()
end

-- ============================================================================
-- REFRESH TOYBOXES UI
-- ============================================================================
function Toys:RefreshToyBoxesUI()
    if not toyBoxPanel or not toyBoxPanel.sidebar then return end
    self:EnsureToyBoxData()

    -- A box can disappear underneath us (deleted from the confirm dialog, or
    -- from another view), leaving the selection pointing at nothing.  Fall back
    -- rather than rendering an empty grid with no way out.
    -- Hiding the selected box counts too: GetToyBox still finds it, so without
    -- this the grid would keep showing a box that is no longer in the sidebar.
    if selectedBoxId and selectedBoxId ~= "all" and selectedBoxId ~= "favorites"
        and (not self:GetToyBox(selectedBoxId) or self:IsBoxHidden(selectedBoxId)) then
        selectedBoxId = "favorites"
    end

    if toyBoxPanel.content and toyBoxPanel.content.hiddenBtn then
        toyBoxPanel.content.hiddenBtn:UpdateHiddenState()
    end

    -- EnsureToyBoxData only builds the box structure.  Without the toy
    -- collection scan, C_ToyBox.GetToyInfo returns nil for every id and the
    -- whole grid renders as the red "?" placeholder -- which is what happened
    -- on first open and on every tab switch.
    if self.EnsureToyData then self:EnsureToyData(true) end

    local cfg = GetToySettings()

    local sidebar = toyBoxPanel.sidebar
    local content = toyBoxPanel.content
    local scrollChild = sidebar.boxScrollChild
    local gridChild = content.gridScrollChild

    if content.lockBtn and content.lockBtn.UpdateLockState then
        content.lockBtn:UpdateLockState()
    end

    -- Clear existing sidebar buttons
    sidebar.boxButtons = sidebar.boxButtons or {}
    for _, b in ipairs(sidebar.boxButtons) do
        b:Hide()
    end

    local boxes = self:GetToyBoxes()
    local yOff = 0
    for i, box in ipairs(boxes) do
        local btn = sidebar.boxButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(116, 24)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.12, 0.12, 0.15, 0.6)
            btn.bg = bg

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.82, 0, 0.25)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", btn, "LEFT", 3, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = icon

            local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            nameText:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)
            btn.nameText = nameText

            local countText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            countText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            countText:SetJustifyH("RIGHT")
            btn.countText = countText

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, mouseButton)
                if mouseButton == "RightButton" and self.boxId and self.boxId ~= "all" then
                    Toys:ShowBoxEditorDialog(self.boxId)
                else
                    selectedBoxId = self.boxId
                    Toys:RefreshToyBoxesUI()
                end
            end)

            btn:SetScript("OnEnter", function(self)
                local s = GetToySettings()
                if s.hideButtonTooltips then return end
                if self.boxName then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.boxName, 1, 0.85, 0.2)
                    if self.boxId ~= "all" then
                        GameTooltip:AddLine("|cFFFFFFFFLeft-Click:|r Select box", 0.9, 0.9, 0.9)
                        GameTooltip:AddLine("|cFF00FF00Right-Click:|r Edit box name & icon", 0.4, 1.0, 0.4)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            local function HandleDropOnSidebar(selfBtn)
                local cursorToyID = GetCursorToyID() or Toys._draggedToyID
                if cursorToyID and selfBtn.boxId and selfBtn.boxId ~= "all" then
                    ClearCursor()
                    local ok, err = Toys:AddToyToBox(selfBtn.boxId, cursorToyID)
                    if not ok and err then
                        UIErrorsFrame:AddExternalErrorMessage(err)
                    end
                    Toys._draggedToyID = nil
                end
            end

            btn:EnableMouse(true)
            btn:SetScript("OnReceiveDrag", function(self)
                -- A box being dragged takes priority over a toy on the cursor.
                if Toys._draggedBoxId then
                    -- ReorderBox refreshes both the tab and the floating panel.
                    Toys:ReorderBox(Toys._draggedBoxId, self.boxId)
                    Toys._draggedBoxId = nil
                    return
                end
                HandleDropOnSidebar(self)
            end)
            btn:HookScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    if Toys._draggedBoxId then
                        Toys:ReorderBox(Toys._draggedBoxId, self.boxId)
                        Toys._draggedBoxId = nil
                        return
                    end
                    local cursorToyID = GetCursorToyID() or Toys._draggedToyID
                    if cursorToyID then
                        HandleDropOnSidebar(self)
                    end
                end
            end)

            -- Drag a box onto another to move it there.  "All Toys" and
            -- "Favorites" are fixed, so they are not draggable.
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                if self.boxId == "all" or self.boxId == "favorites" then return end
                Toys._draggedBoxId = self.boxId
                self:SetAlpha(0.5)
            end)
            btn:SetScript("OnDragStop", function(self)
                self:SetAlpha(1)
                -- Dropped somewhere that is not a box: forget the drag rather
                -- than leaving it armed for the next unrelated click.
                C_Timer.After(0, function() Toys._draggedBoxId = nil end)
            end)

            table.insert(sidebar.boxButtons, btn)
        end

        btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOff)
        btn.boxId = box.id
        btn.boxName = box.name
        
        local resolvedIcon = Toys:GetBoxIconTexture(box.icon)
        btn.icon:SetTexture(resolvedIcon or 135933)
        FitBoxName(btn.nameText, box.name)
        btn.countText:SetText(tostring(#(box.toys or {})))

        if box.id == selectedBoxId then
            btn.bg:SetColorTexture(0.35, 0.28, 0.06, 0.9)
            btn.nameText:SetTextColor(1, 0.85, 0.2)
        else
            btn.bg:SetColorTexture(0.08, 0.08, 0.10, 0.4)
            btn.nameText:SetTextColor(0.85, 0.85, 0.85)
        end

        btn:Show()
        yOff = yOff + 25
    end
    scrollChild:SetHeight(math.max(yOff, 240))

    -- Render Active Box Contents in Grid
    local currentBox = self:GetToyBox(selectedBoxId) or self:GetToyBox("all") or self:GetToyBox("favorites")
    if not currentBox then return end

    content.boxTitle:SetText(currentBox.name)
    content.boxCount:SetText(string.format("(%d toys)", #(currentBox.toys or {})))
    content.editBoxBtn:SetShown(currentBox.id ~= "all")
    content.delBoxBtn:SetShown(currentBox.id ~= "favorites" and currentBox.id ~= "all")

    -- Clear existing toy items
    content.toyButtons = content.toyButtons or {}
    for _, b in ipairs(content.toyButtons) do
        b:Hide()
    end

    -- Search filter, plus the "always shown" picks pinned to the front.
    local toysList = Toys:FilterToyList(currentBox.toys or {}, Toys._boxSearch)
    toysList = Toys:ApplyPinnedToys(toysList, currentBox.id)

    if Toys._boxSearch and Toys._boxSearch ~= "" then
        content.boxCount:SetText(string.format("(%d of %d toys)",
            #toysList, #(currentBox.toys or {})))
    end

    local showNames = cfg.showToyNames == true
    local itemSize = cfg.gridIconSize or (showNames and 36 or 34)
    local slotHeight = showNames and (itemSize + 24) or itemSize
    -- Spacing is user-configurable; the old values are the defaults.
    local baseGap = cfg.gridSpacing or (showNames and 8 or 4)
    local gapX = baseGap
    local gapY = baseGap

    local parentScroll = gridChild:GetParent()
    local availWidth = (parentScroll and parentScroll:GetWidth() or 0) - 10
    if not availWidth or availWidth <= 50 then
        availWidth = (content:GetWidth() or 0) - 24
    end
    if not availWidth or availWidth <= 50 then
        availWidth = 660
    end

    gridChild:SetWidth(availWidth)
    local cols = math.max(1, math.floor((availWidth - 2) / (itemSize + gapX)))
    local row = 0
    local col = 0

    for i, toyID in ipairs(toysList) do
        local btn = content.toyButtons[i]
        if not btn then
            btn = CreateFrame("Button", nil, gridChild)
            btn:SetSize(itemSize, slotHeight)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetSize(itemSize, itemSize)
            icon:SetPoint("TOP", btn, "TOP", 0, 0)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = icon

            -- Gold star marking a toy that is pinned to the front of the grid.
            local pinStar = btn:CreateTexture(nil, "OVERLAY", nil, 6)
            pinStar:SetSize(12, 12)
            pinStar:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 1, 1)
            pinStar:SetTexture("Interface\\COMMON\\FavoritesIcon")
            pinStar:Hide()
            btn.pinStar = pinStar

            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
            hl:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
            hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            hl:SetBlendMode("ADD")

            local nameLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameLabel:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", -5, -2)
            nameLabel:SetPoint("TOPRIGHT", icon, "BOTTOMRIGHT", 5, -2)
            nameLabel:SetHeight(26)
            nameLabel:SetJustifyH("CENTER")
            nameLabel:SetJustifyV("TOP")
            nameLabel:SetWordWrap(true)
            nameLabel:SetMaxLines(2)
            nameLabel:SetScale(0.75)
            nameLabel:SetTextColor(0.9, 0.9, 0.9)
            btn.nameLabel = nameLabel

            -- Remove icon badge on top right
            local removeBtn = CreateFrame("Button", nil, btn)
            removeBtn:SetSize(14, 14)
            removeBtn:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 2, 2)
            local removeTex = removeBtn:CreateTexture(nil, "OVERLAY")
            removeTex:SetAllPoints()
            removeTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            removeBtn.tex = removeTex
            removeBtn:SetScript("OnClick", function(self)
                local parentBtn = self:GetParent()
                if parentBtn and parentBtn.toyID and selectedBoxId and selectedBoxId ~= "all" then
                    -- Shift-click skips the prompt, the usual WoW convention for
                    -- clearing several entries in a row.
                    if IsShiftKeyDown() then
                        Toys:RemoveToyFromBox(selectedBoxId, parentBtn.toyID)
                    else
                        Toys:ConfirmRemoveToy(selectedBoxId, parentBtn.toyID)
                    end
                end
            end)
            btn.removeBtn = removeBtn

            -- Right-click pins a toy so it always sits at the front of the grid.
            btn:SetScript("OnClick", function(self, mouseButton)
                if mouseButton ~= "RightButton" or not self.toyID then return end
                local result = Toys:TogglePinnedToy(self.toyID)
                if result == nil then
                    UIErrorsFrame:AddExternalErrorMessage(
                        ("You can only keep %d toys always shown."):format(Toys.MAX_PINNED_TOYS))
                    return
                end
                Toys:RefreshToyBoxesUI()
                if Toys.RefreshToyDock then Toys:RefreshToyDock() end
                if Toys.UpdateQuickToyBar then Toys:UpdateQuickToyBar() end
            end)

            -- Drag and Drop Reordering & Insertion
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                if self.toyID then
                    C_Item.PickupItem(self.toyID)
                    Toys._draggedToyID = self.toyID
                    Toys._draggedFromBoxId = selectedBoxId
                end
            end)

            local function HandleDropOnGridToy(targetBtn)
                local cursorToyID = GetCursorToyID() or Toys._draggedToyID
                if cursorToyID and targetBtn.toyID and selectedBoxId and selectedBoxId ~= "all" then
                    ClearCursor()
                    if cursorToyID == targetBtn.toyID then
                        Toys._draggedToyID = nil
                        return
                    end
                    if Toys:IsToyInBox(selectedBoxId, cursorToyID) then
                        Toys:ReorderToyInBox(selectedBoxId, cursorToyID, targetBtn.toyID)
                    else
                        Toys:InsertToyInBox(selectedBoxId, cursorToyID, targetBtn.toyID)
                    end
                    Toys._draggedToyID = nil
                end
            end

            btn:SetScript("OnReceiveDrag", function(self)
                HandleDropOnGridToy(self)
            end)

            btn:SetScript("OnEnter", function(self)
                if self.toyID then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetToyByItemID(self.toyID)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF88AAFFRight-click: Copy Wowhead URL|r", 0.5, 0.8, 1.0)
                    if selectedBoxId ~= "all" then
                        GameTooltip:AddLine("|cFF00FF00Drag onto other toys to change order|r", 0.4, 1.0, 0.4)
                        if not cfg.isLocked then
                            GameTooltip:AddLine("|cFFFF5555Click [X] to remove from this box|r", 1.0, 0.4, 0.4)
                        end
                    else
                        GameTooltip:AddLine("|cFF00FF00Drag to add to any ToyBox in sidebar|r", 0.4, 1.0, 0.4)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            btn:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" then
                    local cursorToyID = GetCursorToyID() or Toys._draggedToyID
                    if cursorToyID and cursorToyID ~= self.toyID then
                        HandleDropOnGridToy(self)
                    end
                elseif button == "RightButton" and self.toyID then
                    if OxedHub.ShowCopyURLDialog then
                        OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.toyID), select(2, C_ToyBox.GetToyInfo(self.toyID)) or "Toy")
                    end
                end
            end)

            table.insert(content.toyButtons, btn)
        end

        btn:SetSize(itemSize, slotHeight)
        btn.icon:SetSize(itemSize, itemSize)
        col = (i - 1) % cols
        row = math.floor((i - 1) / cols)
        btn:SetPoint("TOPLEFT", gridChild, "TOPLEFT", col * (itemSize + gapX) + 2, -row * (slotHeight + gapY) - 2)

        local _, toyName, iconTex = C_ToyBox.GetToyInfo(toyID)

        -- A toy the client has not cached yet still returns nil here.  Ask for
        -- it and flag one redraw, rather than leaving a "?" on screen forever.
        if not iconTex then
            local okItem, _, _, _, _, _, _, _, _, itemIcon = pcall(C_Item.GetItemInfo, toyID)
            if okItem and itemIcon then
                iconTex = itemIcon
            else
                Toys._toyIconsPending = true
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, toyID)
                end
            end
        end

        btn.toyID = toyID
        btn.icon:SetTexture(iconTex or 134400)
        if btn.pinStar then
            btn.pinStar:SetShown(Toys:IsToyPinned(toyID))
        end

        -- Red [X] badge only shown if unlocked AND not in "All Toys"
        local canDelete = (selectedBoxId ~= "all") and (not cfg.isLocked)
        btn.removeBtn:SetShown(canDelete)

        if showNames then
            local fontSize = cfg.toyNameFontSize or 9
            btn.nameLabel:SetScale(fontSize / 11.5)
            btn.nameLabel:SetText(toyName or "")
            btn.nameLabel:Show()
        else
            btn.nameLabel:Hide()
        end

        btn:Show()
    end

    local totalHeight = (math.floor(#toysList / cols) + 1) * (slotHeight + gapY) + 24
    gridChild:SetHeight(math.max(totalHeight, 320))

    -- Some icons were not cached yet; redraw shortly so they fill in.  Capped
    -- so an id the client can never resolve cannot loop forever.
    if Toys._toyIconsPending and not Toys._toyIconRedrawQueued then
        Toys._toyIconRedrawQueued = true
        Toys._toyIconRedrawTries = (Toys._toyIconRedrawTries or 0) + 1
        C_Timer.After(0.7, function()
            Toys._toyIconRedrawQueued = nil
            Toys._toyIconsPending = false
            if (Toys._toyIconRedrawTries or 0) <= 4 and toyBoxPanel and toyBoxPanel:IsShown() then
                Toys:RefreshToyBoxesUI()
            end
        end)
    end
end
