local addonName, OxedHub = ...
local L = OxedHub.L
local Toys = OxedHub.Toys
local C_Timer = C_Timer
local GetTime = GetTime

local mixMacroEditorFrame = nil

local function CreateBorderedFrame(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
    return f
end

-- Build the default (auto-generated) macro text, ignoring any custom override
function Toys:GetDefaultMixMacroText(mixData)
    if type(mixData) ~= "table" then return nil end

    local body = "#showtooltip\n"
    local toyNames = {}
    local useRandom = mixData.randomToys == true

    for _, slot in ipairs(mixData.slots or {}) do
        if slot then
            if slot.type == "toy" then
                local _, name = C_ToyBox.GetToyInfo(slot.id)
                if name and self:DoesPlayerOwnToy(slot.id) then
                    if useRandom then
                        table.insert(toyNames, name)
                    else
                        body = body .. "/use " .. name .. "\n"
                    end
                end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.name then
                    body = body .. "/cast " .. spellInfo.name .. "\n"
                end
            end
        end
    end

    if useRandom and #toyNames > 0 then
        body = body .. "/castrandom " .. table.concat(toyNames, ", ") .. "\n"
    end

    local actions = mixData.actions or {}
    if actions.emote then
        body = body .. "/" .. actions.emote:lower() .. "\n"
    end
    if actions.chat then
        local chat = OxedHub.db.profile.chatTemplates[actions.chat]
        if chat then
            body = body .. "/" .. chat.channel:lower() .. " " .. chat.text .. "\n"
        end
    end
    local extras = self:BuildExtrasRunLine(actions.sound, actions.animation)
    if extras then
        body = body .. extras
    end

    if #body > 255 then
        body = body:sub(1, 255)
    end
    return body
end

function Toys:ShowMixMacroEditor(mixName)
    if not mixName then return end
    local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[mixName]
    if type(mixData) ~= "table" then return end

    local Triggers = OxedHub.Triggers

    -- Create the inline frame once
    if not mixMacroEditorFrame then
        local f = CreateFrame("Frame", "OxedHubMixMacroEditor", Toys.libFrame, "BackdropTemplate")
        f:SetAllPoints(Toys.libFrame)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(120)
        f:EnableMouse(true) -- block clicks to things behind it

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -14)
        title:SetTextColor(1, 0.82, 0, 1)
        f.title = title

        -- Back button (instead of close)
        local backBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        backBtn:SetSize(120, 24)
        backBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -10)
        backBtn:SetText(L["MIX_MACRO_BACK"] or "Back to Mixes")
        backBtn:SetScript("OnClick", function()
            f:Hide()
            -- Restore the blocker when leaving the editor
            local blocker = _G["OxedHubToysDebugBlocker"]
            if blocker then blocker:Show() end
            if Toys.savedMixesScrollFrame then
                Toys.savedMixesScrollFrame:Show()
            end
            if Toys.hideUnavailableCheck then
                Toys.hideUnavailableCheck:Show()
            end
            if Toys.mixSortDropdown then
                Toys.mixSortDropdown:Show()
            end
        end)

        -- Desc
        local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetWidth(420)
        desc:SetJustifyH("LEFT")
        desc:SetText(L["ADV_MACRO_EXTEND_DESC"] or "Edit the final trigger macro directly and optionally set your own icon override.")
        desc:SetTextColor(0.75, 0.75, 0.75, 1)

        -- Icon Preview
        local iconPreview = CreateFrame("Button", nil, f, "BackdropTemplate")
        iconPreview:SetSize(40, 40)
        iconPreview:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
        iconPreview:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
        })
        iconPreview:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
        iconPreview:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

        local iconTex = iconPreview:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("TOPLEFT", iconPreview, "TOPLEFT", 3, -3)
        iconTex:SetPoint("BOTTOMRIGHT", iconPreview, "BOTTOMRIGHT", -3, 3)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.iconPreview = iconPreview
        f.iconTexture = iconTex

        local iconLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iconLabel:SetPoint("TOPLEFT", iconPreview, "TOPRIGHT", 12, -2)
        iconLabel:SetText(L["ADV_MACRO_CUSTOM_ICON"] or "Custom Icon")

        local iconInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        iconInput:SetSize(220, 22)
        iconInput:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -6)
        iconInput:SetAutoFocus(false)
        f.iconInput = iconInput

        local iconHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        iconHint:SetPoint("TOPLEFT", iconInput, "BOTTOMLEFT", 4, -4)
        iconHint:SetText(L["ADV_MACRO_CUSTOM_ICON_DESC"] or "Click the icon to pick from Blizzard's macro icons, or type an ID.")
        iconHint:SetTextColor(0.6, 0.6, 0.6, 1)

        -- Macro Preview label
        local previewLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewLabel:SetPoint("TOPLEFT", iconPreview, "BOTTOMLEFT", 0, -18)
        previewLabel:SetText(L["ADV_MACRO_PREVIEW"] or "Macro Preview")

        -- Preview container
        local previewContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
        previewContainer:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -6)
        previewContainer:SetPoint("RIGHT", f, "RIGHT", -28, 0)
        previewContainer:SetHeight(180)
        previewContainer:EnableMouse(false)
        previewContainer:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        previewContainer:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
        previewContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        f.previewContainer = previewContainer

        -- Focus glow
        local focusGlow = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
        focusGlow:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", -1, 1)
        focusGlow:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", 1, -1)
        focusGlow:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
        focusGlow:SetBackdropBorderColor(1, 0.82, 0, 0)
        focusGlow:EnableMouse(false)
        f.focusGlow = focusGlow

        -- Gutter (line numbers)
        local gutter = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
        gutter:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", 6, -6)
        gutter:SetPoint("BOTTOMLEFT", previewContainer, "BOTTOMLEFT", 6, 6)
        gutter:SetWidth(36)
        gutter:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        gutter:SetBackdropColor(0.09, 0.09, 0.11, 0.92)

        local gutterDivider = gutter:CreateTexture(nil, "BORDER")
        gutterDivider:SetPoint("TOPRIGHT", gutter, "TOPRIGHT", 0, 0)
        gutterDivider:SetPoint("BOTTOMRIGHT", gutter, "BOTTOMRIGHT", 0, 0)
        gutterDivider:SetWidth(1)
        gutterDivider:SetColorTexture(0.22, 0.22, 0.24, 1)

        local gutterScroll = CreateFrame("ScrollFrame", nil, gutter)
        gutterScroll:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
        gutterScroll:SetPoint("BOTTOMRIGHT", gutter, "BOTTOMRIGHT", 0, 0)
        gutterScroll:EnableMouse(false)

        local gutterText = CreateFrame("EditBox", nil, gutterScroll)
        gutterText:SetPoint("TOPLEFT")
        gutterText:SetMultiLine(true)
        gutterText:SetFontObject("ChatFontNormal")
        gutterText:SetTextInsets(0, 4, 0, 4)
        gutterText:SetAutoFocus(false)
        gutterText:SetJustifyH("RIGHT")
        gutterText:SetJustifyV("TOP")
        gutterText:EnableMouse(false)
        gutterText:SetWidth(36)
        gutterScroll:SetScrollChild(gutterText)
        f.gutterScroll = gutterScroll
        f.gutterText = gutterText

        -- Faux (colored overlay) scroll + editbox
        local fauxScroll = CreateFrame("ScrollFrame", nil, previewContainer, "UIPanelScrollFrameTemplate")
        fauxScroll:SetPoint("TOPLEFT", gutter, "TOPRIGHT", 6, 0)
        fauxScroll:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", -28, 6)
        fauxScroll:SetFrameLevel(previewContainer:GetFrameLevel() + 1)
        fauxScroll:EnableMouse(false)
        fauxScroll.ScrollBar:Hide()

        local fauxBox = CreateFrame("EditBox", nil, fauxScroll)
        fauxBox:SetAllPoints()
        fauxBox:SetMultiLine(true)
        fauxBox:SetFontObject("ChatFontNormal")
        fauxBox:SetTextInsets(0, 0, 0, 0)
        fauxBox:SetAutoFocus(false)
        fauxBox:SetCountInvisibleLetters(true)
        fauxBox:SetJustifyH("LEFT")
        fauxBox:SetJustifyV("TOP")
        fauxBox:EnableMouse(false)
        fauxBox:SetWidth(480)
        fauxBox.cursorOffset = 0
        fauxBox.cursorHeight = 16
        fauxScroll:SetScrollChild(fauxBox)
        f.fauxScroll = fauxScroll
        f.fauxBox = fauxBox

        local fauxRegions = { fauxBox:GetRegions() }
        for _, region in ipairs(fauxRegions) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                region:SetAlpha(1)
            end
        end
        fauxBox:SetScript("OnUpdate", nil)
        fauxBox:SetScript("OnTextChanged", nil)

        -- Real editable scroll + editbox
        local previewScroll = CreateFrame("ScrollFrame", nil, previewContainer, "UIPanelScrollFrameTemplate")
        previewScroll:SetPoint("TOPLEFT", gutter, "TOPRIGHT", 6, 0)
        previewScroll:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", -28, 6)
        previewScroll:EnableMouseWheel(true)
        previewScroll:SetClipsChildren(true)
        previewScroll:SetFrameLevel(previewContainer:GetFrameLevel() + 2)
        if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
            OxedHub.UI:StyleScrollFrame(previewScroll)
        end

        local previewBox = CreateFrame("EditBox", nil, previewScroll)
        previewBox:SetAllPoints()
        previewBox:SetMultiLine(true)
        previewBox:SetFontObject("ChatFontNormal")
        previewBox:SetTextInsets(0, 0, 0, 0)
        previewBox:SetAutoFocus(false)
        previewBox:SetJustifyH("LEFT")
        previewBox:SetJustifyV("TOP")
        previewBox:SetCountInvisibleLetters(true)
        previewBox:EnableMouse(true)
        previewBox.cursorOffset = 0
        previewBox.cursorHeight = 16
        previewBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        previewScroll:SetScrollChild(previewBox)
        f.previewScroll = previewScroll
        f.previewBox = previewBox

        local previewRegions = { previewBox:GetRegions() }
        local previewTextRegion = nil
        for _, region in ipairs(previewRegions) do
            if region.GetObjectType and region:GetObjectType() == "FontString" then
                previewTextRegion = region
                region:SetAlpha(0.4)
            end
        end
        f.previewTextRegion = previewTextRegion

        fauxBox:SetScript("OnEditFocusGained", function()
            previewBox:SetFocus()
        end)

        -- Character counter
        local countText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 2, -8)
        countText:SetTextColor(0.8, 0.8, 0.8, 1)
        f.countText = countText

        -- Cursor position
        local cursorText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cursorText:SetPoint("LEFT", countText, "RIGHT", 18, 0)
        cursorText:SetTextColor(0.7, 0.9, 1, 1)
        f.cursorText = cursorText

        -- Caret measure helper
        local caretMeasure = previewBox:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
        caretMeasure:Hide()
        f.caretMeasure = caretMeasure

        -- Fake caret
        local fakeCaret = previewBox:CreateTexture(nil, "OVERLAY")
        fakeCaret:SetColorTexture(1, 0.94, 0.4, 1)
        fakeCaret:SetWidth(2)
        fakeCaret:Hide()
        f.fakeCaret = fakeCaret

        -- Reset button
        local resetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        resetBtn:SetSize(130, 24)
        resetBtn:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 0, -28)
        resetBtn:SetText(L["MIX_MACRO_RESET"] or "Reset to Default")
        resetBtn:SetNormalFontObject("GameFontNormalSmall")
        f.resetBtn = resetBtn

        -- Info box
        local infoBox = CreateBorderedFrame(f)
        infoBox:SetHeight(55)
        infoBox:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -12)
        infoBox:SetPoint("RIGHT", previewContainer, "RIGHT", 0, 0)
        infoBox:SetBackdropColor(0, 0, 0, 0.6)

        local infoIcon = infoBox:CreateTexture(nil, "ARTWORK")
        infoIcon:SetSize(28, 28)
        infoIcon:SetPoint("LEFT", infoBox, "LEFT", 14, 0)
        infoIcon:SetTexture("Interface\\common\\help-i")

        local infoTitle = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        infoTitle:SetPoint("TOPLEFT", infoIcon, "TOPRIGHT", 10, 2)
        infoTitle:SetText("|cffffd100" .. (L["MIX_MACRO_INFO_TITLE"] or "Mix Macro Customization:") .. "|r")

        local infoDesc = infoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        infoDesc:SetPoint("TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -4)
        infoDesc:SetPoint("RIGHT", infoBox, "RIGHT", -14, 0)
        infoDesc:SetJustifyH("LEFT")
        infoDesc:SetText(L["MIX_MACRO_INFO_DESC"] or "Edit the macro to customize how this mix fires. You can add conditions, reorder toys, or use /castsequence.\nClick 'Reset to Default' to revert to the auto-generated macro.")

        -- GgutterText update, fake caret and editing behaviors
        local function RefreshPreviewBoxHeight(text)
            local lineCount = 1
            for _ in tostring(text or ""):gmatch("\n") do
                lineCount = lineCount + 1
            end
            local minHeight = math.max((previewContainer:GetHeight() or 180) - 12, 168)
            local targetHeight = math.max(minHeight, (lineCount * 18) + 12)
            previewBox:SetHeight(targetHeight)
            fauxBox:SetHeight(targetHeight)
            gutterText:SetHeight(targetHeight)

            -- Ensure width is always set correctly to match the previewContainer size
            -- so that the editbox is wide and clickable (not 0 width)
            local targetWidth = math.max((previewContainer:GetWidth() or 200) - 76, 120)
            previewBox:SetWidth(targetWidth)
            fauxBox:SetWidth(targetWidth)
        end

        local function SyncPreviewScroll(offset)
            previewScroll:SetVerticalScroll(offset)
            fauxScroll:SetVerticalScroll(offset)
            gutterScroll:SetVerticalScroll(offset)
        end

        local function UpdateFakeCaret()
            if not previewBox:HasFocus() then
                fakeCaret:Hide()
                return
            end
            local Triggers = OxedHub.Triggers
            if not Triggers or not Triggers.GetCursorLineText then
                fakeCaret:Hide()
                return
            end
            local cursorPosition = previewBox:GetCursorPosition()
            local currentLineText = Triggers.GetCursorLineText(previewBox:GetText(), cursorPosition)
            caretMeasure:SetFontObject("ChatFontNormal")
            caretMeasure:SetText(currentLineText)
            local x = caretMeasure:GetStringWidth()
            local y = previewBox.overlayCursorOffset
            local h = previewBox.overlayCursorHeight
            if y == nil then
                local line = Triggers.GetCursorLineAndColumn(previewBox:GetText(), cursorPosition)
                y = -(((line or 1) - 1) * 16)
                h = 16
            end
            fakeCaret:ClearAllPoints()
            fakeCaret:SetPoint("TOPLEFT", previewBox, "TOPLEFT", x, y)
            fakeCaret:SetHeight(math.max((h or 16) - 1, 12))
            fakeCaret:Show()
        end

        local function UpdateCursorIndicator()
            local Triggers = OxedHub.Triggers
            if Triggers and Triggers.GetCursorLineAndColumn then
                local line, column = Triggers.GetCursorLineAndColumn(previewBox:GetText(), previewBox:GetCursorPosition())
                cursorText:SetFormattedText("Line %d, Col %d", line, column)
                if Triggers.BuildMacroLineNumberText then
                    gutterText:SetText(Triggers.BuildMacroLineNumberText(previewBox:GetText(), line))
                end
            end
            UpdateFakeCaret()
        end

        local function SetEditorFocusState(isFocused)
            if previewTextRegion then
                previewTextRegion:SetAlpha(0.4)
            end
            if fauxBox then
                fauxBox:SetAlpha(1)
            end
            if focusGlow then
                focusGlow:SetBackdropBorderColor(1, 0.82, 0, isFocused and 0.9 or 0)
            end
            if previewContainer then
                if isFocused then
                    previewContainer:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    previewContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
            end
        end

        local function UpdateCountText(text)
            local used = #(text or "")
            local color = used > 255 and "|cffff4444" or "|cffcccccc"
            countText:SetText(color .. string.format(L["ADV_MACRO_CHARACTERS_USED"] or "%d/255 Characters Used", used) .. "|r")
        end

        local function LoadMacroText(body)
            previewBox.isSyncingText = true
            previewBox:SetText(body)
            local Triggers = OxedHub.Triggers
            if Triggers and Triggers.BuildStyledMacroPreviewText then
                fauxBox:SetText(Triggers.BuildStyledMacroPreviewText(body))
            else
                fauxBox:SetText(body)
            end
            RefreshPreviewBoxHeight(body)
            SyncPreviewScroll(0)
            previewBox.isSyncingText = false
            UpdateCountText(body)
            UpdateCursorIndicator()
        end

        local function PlaceCursorFromMouse()
            previewBox:SetFocus()
            local Triggers = OxedHub.Triggers
            if not Triggers or not Triggers.GetCursorPositionFromLineAndX then return end
            local cursorX, cursorY = GetCursorPosition()
            local scale = previewScroll:GetEffectiveScale() or 1
            local left = previewScroll:GetLeft()
            local top = previewScroll:GetTop()
            if not left or not top then return end
            local localX = (cursorX / scale) - left
            local localY = top - (cursorY / scale) + (previewScroll:GetVerticalScroll() or 0)
            local lineHeight = math.max((select(2, previewBox:GetFont()) or 14) + 2, 14)
            local targetLine = math.max(1, math.floor(localY / lineHeight) + 1)
            caretMeasure:SetFontObject("ChatFontNormal")
            local pos = Triggers.GetCursorPositionFromLineAndX(previewBox:GetText(), targetLine, localX, caretMeasure)
            previewBox:SetCursorPosition(pos)
            previewBox.overlayCursorX = nil
            previewBox.overlayCursorOffset = nil
            previewBox.overlayCursorHeight = nil
            fauxBox.overlayCursorX = nil
            fauxBox.overlayCursorOffset = nil
            fauxBox.overlayCursorHeight = nil
            previewBox.pendingCaretRefresh = 2
            UpdateCursorIndicator()
        end

        local function UpdateMixMacroIconUI()
            local mixData = f.mixData
            if not mixData then return end
            local Triggers = OxedHub.Triggers
            if not Triggers then return end
            local iconValue = Triggers.TrimText(mixData.customMacroIcon)
            local resolvedIcon = Triggers:ResolveCustomMacroIcon(iconValue)
            iconTex:SetTexture(resolvedIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

            local displayIconValue = iconValue
            if OxedHub.IconPicker and OxedHub.IconPicker.GetDisplayValue then
                displayIconValue = OxedHub.IconPicker:GetDisplayValue(iconValue)
            end

            if OxedHub.IconPicker and OxedHub.IconPicker.IsStoredTextureValue and OxedHub.IconPicker:IsStoredTextureValue(iconValue) then
                iconInput.lastPickerStoredValue = iconValue
                iconInput.lastPickerDisplayValue = displayIconValue or ""
            else
                iconInput.lastPickerStoredValue = nil
                iconInput.lastPickerDisplayValue = nil
            end

            if iconInput:GetText() ~= (displayIconValue or "") then
                iconInput.isSyncingValue = true
                iconInput:SetText(displayIconValue or "")
                iconInput.isSyncingValue = false
            end

            -- Refresh UI components with the new icon immediately
            local Toys = OxedHub.Toys
            if Toys then
                if Toys.RefreshSavedMixesList then Toys:RefreshSavedMixesList() end
                if Toys.RefreshQuickMixesGrid then Toys:RefreshQuickMixesGrid() end
                if Toys.UpdateMixerIcons then Toys:UpdateMixerIcons() end
            end
            local ActionHub = OxedHub.ActionHub
            if ActionHub then
                if ActionHub.RefreshTab then ActionHub:RefreshTab() end
                if ActionHub.RefreshPickerList then ActionHub:RefreshPickerList() end
            end
        end

        -- Bind script handlers
        previewBox:SetScript("OnTextChanged", function(self)
            if self.isSyncingText then return end
            local currentText = self:GetText() or ""
            RefreshPreviewBoxHeight(currentText)
            local Triggers = OxedHub.Triggers
            if Triggers and Triggers.BuildStyledMacroPreviewText then
                fauxBox:SetText(Triggers.BuildStyledMacroPreviewText(currentText))
            else
                fauxBox:SetText(currentText)
            end
            ScrollingEdit_OnTextChanged(self, self:GetParent())
            ScrollingEdit_OnTextChanged(fauxBox, fauxScroll)

            -- Save custom body (or clear if matches default)
            local mixData = f.mixData
            if mixData then
                local defBody = Toys:GetDefaultMixMacroText(mixData) or ""
                local normalized = currentText:gsub("%s+$", "")
                local defNormalized = defBody:gsub("%s+$", "")
                if normalized == defNormalized then
                    mixData.customMacroBody = nil
                else
                    mixData.customMacroBody = currentText
                end
            end

            -- Update existing WoW macro if one exists
            if Toys:HasGeneratedMixMacro(f.currentMixName) then
                Toys:CreateMacroForMix(f.currentMixName, true)
            end

            UpdateCountText(currentText)
            UpdateCursorIndicator()
        end)

        previewBox:SetScript("OnCursorChanged", function(self, x, y, _, h)
            self.cursorX = x
            self.cursorOffset = y or 0
            self.cursorHeight = h or self.cursorHeight or 16
            self.overlayCursorX = x
            self.overlayCursorOffset = y
            self.overlayCursorHeight = h
            self.handleCursorChange = true
            fauxBox.cursorX = x
            fauxBox.cursorOffset = y or 0
            fauxBox.cursorHeight = h or fauxBox.cursorHeight or 16
            fauxBox.overlayCursorX = x
            fauxBox.overlayCursorOffset = y
            fauxBox.overlayCursorHeight = h
            fauxBox.handleCursorChange = true
            UpdateCursorIndicator()
        end)

        previewBox:SetScript("OnUpdate", function(self)
            if self.cursorOffset == nil then self.cursorOffset = 0 end
            if fauxBox.cursorOffset == nil then fauxBox.cursorOffset = 0 end
            ScrollingEdit_OnUpdate(self)
            ScrollingEdit_OnUpdate(fauxBox)
            if self.pendingCaretRefresh and self.pendingCaretRefresh > 0 then
                self.overlayCursorX = nil
                self.overlayCursorOffset = nil
                self.overlayCursorHeight = nil
                fauxBox.overlayCursorX = nil
                fauxBox.overlayCursorOffset = nil
                fauxBox.overlayCursorHeight = nil
                UpdateCursorIndicator()
                self.pendingCaretRefresh = self.pendingCaretRefresh - 1
            end
            if self:HasFocus() then
                UpdateFakeCaret()
                local pulse = math.floor(GetTime() * 2) % 2
                fakeCaret:SetAlpha(pulse == 0 and 1 or 0)
            else
                fakeCaret:Hide()
            end
        end)

        previewBox:HookScript("OnMouseDown", function()
            PlaceCursorFromMouse()
        end)

        previewBox:SetScript("OnMouseUp", function()
            previewBox.pendingCaretRefresh = 3
        end)

        previewBox:SetScript("OnEditFocusGained", function()
            SetEditorFocusState(true)
            UpdateCursorIndicator()
        end)

        previewBox:SetScript("OnEditFocusLost", function()
            SetEditorFocusState(false)
            fakeCaret:Hide()
        end)

        previewScroll:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll() or 0
            local minScroll, maxScroll = 0, 0
            if self.ScrollBar and self.ScrollBar.GetMinMaxValues then
                minScroll, maxScroll = self.ScrollBar:GetMinMaxValues()
            end
            local nextScroll = current - (delta * 24)
            if nextScroll < minScroll then nextScroll = minScroll end
            if nextScroll > maxScroll then nextScroll = maxScroll end
            SyncPreviewScroll(nextScroll)
        end)

        previewScroll:SetScript("OnVerticalScroll", function(self, offset)
            SyncPreviewScroll(offset)
            UpdateCursorIndicator()
        end)

        previewContainer:SetScript("OnSizeChanged", function(self)
            local targetWidth = math.max((self:GetWidth() or 200) - 76, 120)
            previewBox:SetWidth(targetWidth)
            fauxBox:SetWidth(targetWidth)
            RefreshPreviewBoxHeight(previewBox:GetText())
        end)

        iconPreview:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        iconPreview:SetScript("OnClick", function(_, button)
            local mixData = f.mixData
            if not mixData then return end
            if button == "RightButton" then
                mixData.customMacroIcon = nil
                UpdateMixMacroIconUI()
                if Toys:HasGeneratedMixMacro(f.currentMixName) then
                    Toys:CreateMacroForMix(f.currentMixName, true)
                end
                return
            end

            if OxedHub.IconPicker then
                OxedHub.IconPicker:Open({
                    title = L["ADV_MACRO_CHOOSE_ICON"] or "Choose Trigger Macro Icon",
                    initialValue = mixData.customMacroIcon,
                    anchor = iconPreview,
                    allowClear = true,
                    onSelect = function(storedValue)
                        mixData.customMacroIcon = storedValue
                        UpdateMixMacroIconUI()
                        if Toys:HasGeneratedMixMacro(f.currentMixName) then
                            Toys:CreateMacroForMix(f.currentMixName, true)
                        end
                    end,
                })
            end
        end)

        iconPreview:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["ADV_MACRO_CUSTOM_ICON"] or "Custom Icon")
            GameTooltip:AddLine(L["ADV_MACRO_CHOOSE_ICON_LEFT_CLICK"] or "Left-click to choose an icon from Blizzard's macro icon list.", 1, 1, 1, true)
            GameTooltip:AddLine(L["ADV_MACRO_CLEAR_ICON_RIGHT_CLICK"] or "Right-click to clear the custom icon.", 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)

        iconPreview:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        iconInput:SetScript("OnTextChanged", function(self)
            if self.isSyncingValue then
                return
            end

            local Triggers = OxedHub.Triggers
            local mixData = f.mixData
            if not mixData or not Triggers then return end

            local typedValue = Triggers.TrimText(self:GetText())
            if self.lastPickerStoredValue and typedValue == (self.lastPickerDisplayValue or "") then
                mixData.customMacroIcon = self.lastPickerStoredValue
            else
                mixData.customMacroIcon = typedValue
            end

            if mixData.customMacroIcon == "" then
                mixData.customMacroIcon = nil
            end
            UpdateMixMacroIconUI()
            
            if Toys:HasGeneratedMixMacro(f.currentMixName) then
                Toys:CreateMacroForMix(f.currentMixName, true)
            end
        end)

        resetBtn:SetScript("OnClick", function()
            local mixData = f.mixData
            if not mixData then return end
            mixData.customMacroBody = nil
            mixData.customMacroIcon = nil
            local defBody = Toys:GetDefaultMixMacroText(mixData) or ""
            UpdateMixMacroIconUI()
            LoadMacroText(defBody)
            if Toys:HasGeneratedMixMacro(f.currentMixName) then
                Toys:CreateMacroForMix(f.currentMixName, true)
            end
        end)

        -- Expose functions on f so they can be called on subsequent ShowMixMacroEditor invocations
        f.UpdateMixMacroIconUI = UpdateMixMacroIconUI
        f.LoadMacroText = LoadMacroText
        f.SetEditorFocusState = SetEditorFocusState

        mixMacroEditorFrame = f
    end

    local f = mixMacroEditorFrame
    f.currentMixName = mixName
    f.mixData = mixData

    -- Update title
    f.title:SetText((L["MIX_MACRO_TITLE"] or "Mix Macro:") .. " |cffffffff" .. mixName .. "|r")

    -- Get the current macro body (custom or default)
    local defaultBody = Toys:GetDefaultMixMacroText(mixData) or ""
    local currentBody = mixData.customMacroBody or defaultBody

    -- Load the current text
    f.UpdateMixMacroIconUI()
    f.LoadMacroText(currentBody)
    f.SetEditorFocusState(false)

    if Toys.savedMixesScrollFrame then
        Toys.savedMixesScrollFrame:Hide()
    end
    if Toys.hideUnavailableCheck then
        Toys.hideUnavailableCheck:Hide()
    end
    if Toys.mixSortDropdown then
        Toys.mixSortDropdown:Hide()
    end
    -- Hide the pngBlocker so it doesn't eat mouse events on our editor
    local blocker = _G["OxedHubToysDebugBlocker"]
    if blocker then blocker:Hide() end
    f:Show()
end
