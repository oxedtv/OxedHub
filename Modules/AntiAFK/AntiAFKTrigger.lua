local addonName, OxedHub = ...

local AntiAFK = OxedHub.AntiAFK or {}
OxedHub.AntiAFK = AntiAFK
local L = OxedHub.L

OxedHub.Triggers:RegisterEventType("PVP_ANTI_AFK", {
    name = L["EVT_PVP_ANTI_AFK"] or "Anti-AFK BG Guard",
    CheckCondition = function(trigger, eventData)
        return false -- Handled internally by AntiAFKEngine
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}
        local conditions = trigger.conditions
        trigger.actions = trigger.actions or {}
        local actions = trigger.actions
        yOffset = yOffset or 0

        -- Defaults
        if conditions.showTimer == nil then conditions.showTimer = true end
        if conditions.showMoveBanner == nil then conditions.showMoveBanner = true end
        if conditions.bgOnly == nil then conditions.bgOnly = true end
        if conditions.testMode == nil then conditions.testMode = false end

        -- Seed the urgent stage with the bundled "run" clip so the alarm is
        -- audible out of the box.  Only on first setup: a user who clears it
        -- back to None must stay cleared, hence the separate marker flag.
        if not conditions.moveSoundSeeded then
            conditions.moveSoundSeeded = true
            trigger.actions = trigger.actions or {}
            if not trigger.actions.moveSound and not conditions.moveSound then
                trigger.actions.moveSound = AntiAFK.DEFAULT_MOVE_SOUND
            end
        end

        local function saveConditions()
            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
            if AntiAFK.ResetTimer then
                AntiAFK:ResetTimer()
            end
            if AntiAFK.CheckState then
                AntiAFK:CheckState()
            end
        end

        local function CreateIcon(parent, texturePath)
            local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            iconFrame:SetSize(22, 22)
            iconFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            iconFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            iconFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

            local icon = iconFrame:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -2, 2)
            icon:SetTexture(texturePath or "Interface\\Icons\\INV_Misc_Horn_01")
            icon:SetTexCoord(0, 1, 0, 1)
            iconFrame.icon = icon
            return iconFrame
        end

        local function TruncateText(text, maxLength)
            if not text or text == "None" or text == (L["NONE"] or "None") then return L["NONE"] or "None" end
            if string.len(text) <= maxLength then return text end
            return string.sub(text, 1, maxLength - 3) .. "..."
        end

        -- ----------------------------------------------------
        -- SECTION 1: General & Display Options
        -- ----------------------------------------------------
        local featureHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        featureHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        featureHeader:SetText("|cFFFFD900Anti-AFK Protection & Visual Displays|r")
        yOffset = yOffset - 24

        -- Top Timer Checkbox
        local timerCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        timerCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        timerCheck:SetSize(20, 20)
        timerCheck:SetChecked(conditions.showTimer)
        timerCheck.text:SetText(L["ANTI_AFK_TOP_TIMER"] or "Show Top On-Screen Timer (AFK: 00:00 / 5:00)")
        timerCheck.text:SetTextColor(0.9, 0.9, 0.9)
        timerCheck:SetScript("OnClick", function(self)
            conditions.showTimer = self:GetChecked()
            saveConditions()
        end)
        yOffset = yOffset - 24

        -- Move Banner Checkbox
        local moveCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        moveCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        moveCheck:SetSize(20, 20)
        moveCheck:SetChecked(conditions.showMoveBanner)
        moveCheck.text:SetText(L["ANTI_AFK_MOVE_BANNER"] or "Show Center Screen 'MOVE' Alert Banner")
        moveCheck.text:SetTextColor(0.9, 0.9, 0.9)
        moveCheck:SetScript("OnClick", function(self)
            conditions.showMoveBanner = self:GetChecked()
            saveConditions()
        end)

        local previewMoveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        previewMoveBtn:SetPoint("LEFT", frame, "TOPLEFT", 320, yOffset - 2)
        previewMoveBtn:SetSize(140, 22)
        previewMoveBtn:SetText("Test / Move Banner")
        previewMoveBtn:SetNormalFontObject("GameFontNormalSmall")
        previewMoveBtn:SetScript("OnClick", function(self)
            if AntiAFK.ToggleMoveBannerPreview then
                local isShown = AntiAFK:ToggleMoveBannerPreview(trigger)
                if isShown then
                    self:SetText("Hide Banner")
                else
                    self:SetText("Test / Move Banner")
                end
            end
        end)

        yOffset = yOffset - 24

        -- BG Only Checkbox
        local bgCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        bgCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        bgCheck:SetSize(20, 20)
        bgCheck:SetChecked(conditions.bgOnly)
        bgCheck.text:SetText(L["ANTI_AFK_BG_ONLY"] or "Active only in Battlegrounds (Normal & Epic)")
        bgCheck.text:SetTextColor(0.9, 0.9, 0.9)
        bgCheck:SetScript("OnClick", function(self)
            conditions.bgOnly = self:GetChecked()
            saveConditions()
        end)
        yOffset = yOffset - 24

        -- Test Mode Checkbox
        local testCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        testCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        testCheck:SetSize(20, 20)
        testCheck:SetChecked(conditions.testMode)
        testCheck.text:SetText(L["ANTI_AFK_TEST_MODE"] or "Test Mode (Accelerated Timers: 15s / 30s / 45s — still Battleground-only unless unticked above)")
        testCheck.text:SetTextColor(0.4, 0.9, 0.4)
        testCheck:SetScript("OnClick", function(self)
            conditions.testMode = self:GetChecked()
            saveConditions()
        end)

        -- Reset Positions Button
        local resetPosBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        resetPosBtn:SetPoint("LEFT", frame, "TOPLEFT", 320, yOffset - 2)
        resetPosBtn:SetSize(140, 22)
        resetPosBtn:SetText("Reset HUD Positions")
        resetPosBtn:SetNormalFontObject("GameFontNormalSmall")
        resetPosBtn:SetScript("OnClick", function()
            conditions.timerCustomPos = false
            conditions.timerPosX = nil
            conditions.timerPosY = nil
            conditions.moveBannerCustomPos = false
            conditions.moveBannerPosX = nil
            conditions.moveBannerPosY = nil
            if AntiAFK.ApplyFramePositions then
                AntiAFK:ApplyFramePositions(trigger)
            end
            saveConditions()
        end)

        yOffset = yOffset - 32

        -- ----------------------------------------------------
        -- SECTION 2: Appearance
        -- Font sizes, outline and per-stage colours for the HUD. Changes apply
        -- live so the preview reflects them while adjusting.
        -- ----------------------------------------------------
        local lookHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lookHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        lookHeader:SetText("|cFFFFD900Appearance (Font, Size & Colors)|r")
        yOffset = yOffset - 26

        -- Keep the HUD on screen while the look is being adjusted, otherwise
        -- font/size/colour changes have nothing visible to land on.
        local previewBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        previewBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        previewBtn:SetSize(150, 22)
        previewBtn:SetNormalFontObject("GameFontNormalSmall")
        previewBtn:SetText("Preview On Screen")
        previewBtn:SetScript("OnClick", function(self)
            local on = AntiAFK.TogglePreview and AntiAFK:TogglePreview(trigger)
            self:SetText(on and "Hide Preview" or "Preview On Screen")
        end)
        yOffset = yOffset - 30

        local function RefreshHUDPreview()
            if AntiAFK.ApplyHUDStyle then AntiAFK:ApplyHUDStyle(conditions) end
            if AntiAFK.UpdateTimerDisplay then
                if AntiAFK.stylePreviewOn then
                    -- Keep the sample reading while the preview is pinned,
                    -- otherwise every slider nudge would reset it to 0.
                    local maxTime = conditions.maxTime or 300
                    AntiAFK:UpdateTimerDisplay(math.floor(maxTime * 0.4), maxTime, "red", true, false)
                else
                    AntiAFK:UpdateTimerDisplay(0, conditions.maxTime or 300, "none",
                        conditions.showTimer ~= false, false)
                end
            end
            saveConditions()
        end

        local function AddFontSlider(labelText, key, defaultValue, minV, maxV)
            local slider = CreateFrame("Slider", "OxedHubAntiAFK_" .. key,
                frame, "OptionsSliderTemplate")
            slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset - 14)
            slider:SetWidth(170)
            slider:SetMinMaxValues(minV, maxV)
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)

            local low  = slider.Low  or _G[slider:GetName() .. "Low"]
            local high = slider.High or _G[slider:GetName() .. "High"]
            local text = slider.Text or _G[slider:GetName() .. "Text"]
            if low  then low:SetText(tostring(minV)) end
            if high then high:SetText(tostring(maxV)) end
            if text then text:SetText(labelText) end

            local valText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            valText:SetPoint("LEFT", slider, "RIGHT", 12, 0)

            local startValue = conditions[key] or defaultValue
            slider:SetValue(startValue)
            valText:SetText(startValue .. " pt")

            slider:SetScript("OnValueChanged", function(_, value)
                value = math.floor(value + 0.5)
                valText:SetText(value .. " pt")
                conditions[key] = value
                RefreshHUDPreview()
            end)

            yOffset = yOffset - 48
            return slider
        end

        AddFontSlider("Timer Font Size", "timerFontSize", 46, 20, 90)
        AddFontSlider("MOVE Banner Size", "moveFontSize", 96, 40, 160)

        -- Font face -------------------------------------------------------
        local fontLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fontLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        fontLabel:SetText("Font:")

        local fontIndex = 1
        for i, def in ipairs(AntiAFK.FONTS) do
            if def.path == conditions.fontPath then fontIndex = i end
        end

        local fontDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        fontDropdown:SetPoint("LEFT", fontLabel, "RIGHT", 10, 0)
        fontDropdown:SetSize(200, 24)

        -- Sample rendered in the chosen face.  It lives on our own frame:
        -- SetFont is disallowed on Blizzard menu widgets, so neither the
        -- dropdown label nor the menu rows can be restyled.
        local fontSample = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fontSample:SetPoint("LEFT", fontDropdown, "RIGHT", 12, 0)
        fontSample:SetTextColor(1, 0.82, 0, 1)

        local function ShowFontOnDropdown(def)
            fontDropdown:OverrideText(def.label)
            fontSample:SetFont(def.path, 18, "OUTLINE")
            fontSample:SetText("RUN!!!")
        end

        fontDropdown:SetupMenu(function(_, rootDescription)
            for _, def in ipairs(AntiAFK.FONTS) do
                rootDescription:CreateRadio(
                    def.label,
                    function()
                        return (conditions.fontPath or AntiAFK.FONTS[1].path) == def.path
                    end,
                    function()
                        conditions.fontPath = def.path
                        ShowFontOnDropdown(def)
                        RefreshHUDPreview()
                    end)
            end
        end)

        ShowFontOnDropdown(AntiAFK.FONTS[fontIndex])
        yOffset = yOffset - 32

        -- Timer readout ---------------------------------------------------
        local formatLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        formatLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        formatLabel:SetText("Timer Shows:")

        local formatIndex = 1
        for i, def in ipairs(AntiAFK.TIMER_FORMATS) do
            if def.key == (conditions.timerFormat or "countdown") then formatIndex = i end
        end

        local formatBtn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        formatBtn:SetPoint("LEFT", formatLabel, "RIGHT", 10, 0)
        formatBtn:SetSize(140, 24)
        formatBtn:SetupMenu(function(_, rootDescription)
            for _, def in ipairs(AntiAFK.TIMER_FORMATS) do
                rootDescription:CreateRadio(
                    def.label,
                    function() return (conditions.timerFormat or "countdown") == def.key end,
                    function()
                        conditions.timerFormat = def.key
                        formatBtn:OverrideText(def.label)
                        RefreshHUDPreview()
                    end)
            end
        end)
        formatBtn:OverrideText(AntiAFK.TIMER_FORMATS[formatIndex].label)

        -- Optional word in front of the number. Empty by default: the old
        -- hard-coded "AFK:" prefix was noise once the number counts down.
        local labelInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        labelInput:SetPoint("LEFT", formatBtn, "RIGHT", 12, 0)
        labelInput:SetSize(110, 22)
        labelInput:SetAutoFocus(false)
        labelInput:SetMaxLetters(12)
        labelInput:SetText(conditions.timerLabel or "")

        local labelHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        labelHint:SetPoint("LEFT", labelInput, "RIGHT", 8, 0)
        labelHint:SetText("label (optional)")

        local function CommitLabel(box)
            conditions.timerLabel = box:GetText()
            box:ClearFocus()
            RefreshHUDPreview()
        end
        labelInput:SetScript("OnEnterPressed", CommitLabel)
        labelInput:SetScript("OnEditFocusLost", CommitLabel)
        yOffset = yOffset - 30
        local outlineLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        outlineLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        outlineLabel:SetText("Text Outline:")

        local outlineIndex = 1
        for i, def in ipairs(AntiAFK.FONT_OUTLINES) do
            if def.key == (conditions.timerOutline or "THICKOUTLINE") then outlineIndex = i end
        end

        local outlineBtn = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        outlineBtn:SetPoint("LEFT", outlineLabel, "RIGHT", 10, 0)
        outlineBtn:SetSize(140, 24)
        outlineBtn:SetupMenu(function(_, rootDescription)
            for _, def in ipairs(AntiAFK.FONT_OUTLINES) do
                rootDescription:CreateRadio(
                    def.label,
                    function() return (conditions.timerOutline or "THICKOUTLINE") == def.key end,
                    function()
                        conditions.timerOutline = def.key
                        conditions.moveOutline = def.key
                        outlineBtn:OverrideText(def.label)
                        RefreshHUDPreview()
                    end)
            end
        end)
        outlineBtn:OverrideText(AntiAFK.FONT_OUTLINES[outlineIndex].label)
        yOffset = yOffset - 30

        local colorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        colorLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        colorLabel:SetText("Stage Colors:")
        yOffset = yOffset - 24

        local colorDefs = {
            { key = "none",   label = "Safe" },
            { key = "yellow", label = "Early" },
            { key = "red",    label = "Critical" },
            { key = "move",   label = "MOVE" },
        }

        local prevSwatch
        for _, def in ipairs(colorDefs) do
            local swatch = CreateFrame("Button", nil, frame, "BackdropTemplate")
            swatch:SetSize(22, 22)
            if prevSwatch then
                swatch:SetPoint("LEFT", prevSwatch, "RIGHT", 64, 0)
            else
                swatch:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, yOffset)
            end
            swatch:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            swatch:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)

            local dr, dg, db = unpack(AntiAFK.PHASE_DEFAULT_COLORS[def.key])
            local stored = conditions["color" .. def.key]
            if type(stored) == "table" and stored[1] then
                dr, dg, db = stored[1], stored[2], stored[3]
            end
            swatch:SetBackdropColor(dr, dg, db, 1)

            local swatchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            swatchLabel:SetPoint("LEFT", swatch, "RIGHT", 4, 0)
            swatchLabel:SetText(def.label)

            swatch:SetScript("OnClick", function(self)
                local cr, cg, cb = self:GetBackdropColor()
                local info = {
                    r = cr, g = cg, b = cb,
                    hasOpacity = false,
                    swatchFunc = function()
                        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                        conditions["color" .. def.key] = { nr, ng, nb }
                        self:SetBackdropColor(nr, ng, nb, 1)
                        RefreshHUDPreview()
                    end,
                    cancelFunc = function(prev)
                        if prev then
                            conditions["color" .. def.key] = { prev.r, prev.g, prev.b }
                            self:SetBackdropColor(prev.r, prev.g, prev.b, 1)
                            RefreshHUDPreview()
                        end
                    end,
                }
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
            prevSwatch = swatch
        end
        yOffset = yOffset - 34

        local bannerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bannerLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, yOffset)
        bannerLabel:SetText("Warning Message:")

        local bannerInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        bannerInput:SetPoint("LEFT", bannerLabel, "RIGHT", 10, 0)
        bannerInput:SetSize(150, 22)
        bannerInput:SetAutoFocus(false)
        bannerInput:SetMaxLetters(32)
        bannerInput:SetText(conditions.moveText or AntiAFK.DEFAULT_WARNING)

        local function CommitBanner(box)
            conditions.moveText = box:GetText()
            box:ClearFocus()
            RefreshHUDPreview()
        end
        bannerInput:SetScript("OnEnterPressed", CommitBanner)
        bannerInput:SetScript("OnEditFocusLost", CommitBanner)

        local resetLookBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        resetLookBtn:SetPoint("LEFT", bannerInput, "RIGHT", 12, 0)
        resetLookBtn:SetSize(110, 22)
        resetLookBtn:SetText("Reset Look")
        resetLookBtn:SetNormalFontObject("GameFontNormalSmall")
        resetLookBtn:SetScript("OnClick", function()
            conditions.timerFontSize = nil
            conditions.moveFontSize = nil
            conditions.timerOutline = nil
            conditions.moveOutline = nil
            conditions.moveText = nil
            conditions.fontPath = nil
            conditions.timerFormat = nil
            conditions.timerLabel = nil
            for _, def in ipairs(colorDefs) do
                conditions["color" .. def.key] = nil
            end
            RefreshHUDPreview()
            if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggerCard then
                OxedHub.Triggers:RefreshTriggerCard(trigger.id)
            end
        end)

        yOffset = yOffset - 36

        -- ----------------------------------------------------
        -- SECTION 3: Stage Alerts (Audio & Animations)
        -- ----------------------------------------------------
        local stageHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stageHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        stageHeader:SetText("|cFFFFD900Warning Alerts (Sounds & Animations per Stage)|r")
        yOffset = yOffset - 24

        local stages = {
            { 
                key = "yellow", 
                label = "|cFFFFDD00Stage 1 — Early Warning (2:00)|r", 
                soundKey = "yellowSound",
                animKey = "yellowAnimation",
                defaultMode = "loop"
            },
            { 
                key = "red", 
                label = "|cFFFF6600Stage 2 — Critical Warning (3:00)|r", 
                soundKey = "redSound",
                animKey = "redAnimation",
                defaultMode = "loop"
            },
            { 
                key = "move", 
                label = "|cFFFF2200Stage 3 — Urgent \"MOVE\" Alarm (3:30)|r", 
                soundKey = "moveSound",
                animKey = "moveAnimation",
                defaultMode = "once"
            },
        }

        local function CreateStageBlock(parent, st)
            -- Stage Header title (clean, no extra spell icon)
            local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
            title:SetText(st.label)
            yOffset = yOffset - 24

            -- Sound row with Horn Icon
            local soundIcon = CreateIcon(parent, "Interface\\Icons\\INV_Misc_Horn_01")
            soundIcon:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)

            local soundLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            soundLabel:SetPoint("LEFT", soundIcon, "RIGHT", 6, 0)
            soundLabel:SetText((L["LBL_SOUND"] or "Sound") .. ":")

            local soundBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            soundBtn:SetPoint("LEFT", soundLabel, "RIGHT", 6, 0)
            soundBtn:SetSize(130, 22)
            soundBtn:SetNormalFontObject("GameFontNormalSmall")

            local function UpdateSoundBtn()
                local val = actions[st.soundKey] or conditions[st.soundKey]
                local text = L["NONE"] or "Default / Built-in"
                local fullName = text
                if val and val ~= "" and val ~= "None" then
                    local data = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[val]
                    fullName = data and data.name or val
                    text = TruncateText(fullName, 15)
                end
                soundBtn:SetText(text)
                soundBtn.fullText = fullName
            end
            UpdateSoundBtn()

            soundBtn:SetScript("OnEnter", function(self)
                if self.fullText and self.fullText ~= "None" and self.fullText ~= (L["NONE"] or "None") then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.fullText)
                    GameTooltip:Show()
                end
            end)
            soundBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            soundBtn:SetScript("OnClick", function()
                if OxedHub.Triggers and OxedHub.Triggers.ShowSoundPicker then
                    OxedHub.Triggers:ShowSoundPicker(trigger, st.soundKey)
                end
            end)

            soundBtn:SetScript("OnUpdate", function(self)
                local val = actions[st.soundKey] or conditions[st.soundKey]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateSoundBtn()
                end
            end)

            local playSoundBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            playSoundBtn:SetPoint("LEFT", soundBtn, "RIGHT", 4, 0)
            playSoundBtn:SetSize(40, 22)
            playSoundBtn:SetText("Play")
            playSoundBtn:SetNormalFontObject("GameFontNormalSmall")
            playSoundBtn:SetScript("OnClick", function()
                local val = actions[st.soundKey] or conditions[st.soundKey]
                if val and val ~= "" and val ~= "None" then
                    AntiAFK:PlaySoundDirect(val)
                else
                    if st.key == "move" then
                        PlaySound(9278, "Master")
                    else
                        PlaySound(8959, "Master")
                    end
                end
            end)

            -- Animation row with static Sprint Icon (never changes texture)
            local animIcon = CreateIcon(parent, "Interface\\Icons\\Ability_Rogue_Sprint")
            animIcon:SetPoint("LEFT", playSoundBtn, "RIGHT", 14, 0)

            local animLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            animLabel:SetPoint("LEFT", animIcon, "RIGHT", 6, 0)
            animLabel:SetText((L["LBL_ANIMATION"] or "Animation") .. ":")

            local animBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            animBtn:SetPoint("LEFT", animLabel, "RIGHT", 6, 0)
            animBtn:SetSize(130, 22)
            animBtn:SetNormalFontObject("GameFontNormalSmall")

            local function UpdateAnimBtn()
                local val = actions[st.animKey] or conditions[st.animKey]
                local text = L["NONE"] or "None"
                local fullName = text
                if val and val ~= "" and val ~= "None" then
                    local data = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.animations and OxedHub.db.profile.animations[val]
                    fullName = data and data.name or val
                    text = TruncateText(fullName, 15)
                end
                animBtn:SetText(text)
                animBtn.fullText = fullName
            end
            UpdateAnimBtn()

            animBtn:SetScript("OnEnter", function(self)
                if self.fullText and self.fullText ~= "None" and self.fullText ~= (L["NONE"] or "None") then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.fullText)
                    GameTooltip:Show()
                end
            end)
            animBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            animBtn:SetScript("OnClick", function()
                if OxedHub.Triggers and OxedHub.Triggers.ShowAnimationPicker then
                    OxedHub.Triggers:ShowAnimationPicker(trigger, st.animKey)
                end
            end)

            local moveScaleBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            moveScaleBtn:SetPoint("LEFT", animBtn, "RIGHT", 4, 0)
            moveScaleBtn:SetSize(85, 22)
            moveScaleBtn:SetText(L["ANIM_MOVE_SCALE"] or "Move / Scale")
            moveScaleBtn:SetNormalFontObject("GameFontNormalSmall")

            local function RefreshAnimControls()
                local val = actions[st.animKey] or conditions[st.animKey]
                local hasAnim = val and val ~= "" and val ~= "None"
                if hasAnim then
                    moveScaleBtn:Enable()
                    moveScaleBtn:SetAlpha(1)
                else
                    moveScaleBtn:Disable()
                    moveScaleBtn:SetAlpha(0.5)
                end
            end
            RefreshAnimControls()

            animBtn:SetScript("OnUpdate", function(self)
                local val = actions[st.animKey] or conditions[st.animKey]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateAnimBtn()
                    RefreshAnimControls()
                end
            end)

            moveScaleBtn:SetScript("OnClick", function()
                if OxedHub.Animations and OxedHub.Animations.ShowPositionFrameForTrigger then
                    OxedHub.Animations:ShowPositionFrameForTrigger(trigger, st.animKey)
                end
            end)

            -- ------------------------------------------------
            -- Playback Options (Play Once / Loop / Repeat Count)
            -- ------------------------------------------------
            yOffset = yOffset - 26

            local currentMode = actions[st.key .. "Mode"] or st.defaultMode
            local currentCount = actions[st.key .. "Count"] or 3

            local playOnceCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            playOnceCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 38, yOffset)
            playOnceCheck:SetSize(18, 18)
            playOnceCheck.text:SetText("Play Once")
            playOnceCheck.text:SetFontObject("GameFontHighlightSmall")

            local loopCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            loopCheck:SetPoint("LEFT", playOnceCheck.text, "RIGHT", 14, 0)
            loopCheck:SetSize(18, 18)
            loopCheck.text:SetText("Continuous Loop")
            loopCheck.text:SetFontObject("GameFontHighlightSmall")

            local repeatCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            repeatCheck:SetPoint("LEFT", loopCheck.text, "RIGHT", 14, 0)
            repeatCheck:SetSize(18, 18)
            repeatCheck.text:SetText("Repeat:")
            repeatCheck.text:SetFontObject("GameFontHighlightSmall")

            local repeatInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
            repeatInput:SetPoint("LEFT", repeatCheck.text, "RIGHT", 8, 0)
            repeatInput:SetSize(35, 18)
            repeatInput:SetAutoFocus(false)
            repeatInput:SetNumeric(true)
            repeatInput:SetMaxLetters(3)
            repeatInput:SetText(tostring(currentCount))

            local timesLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            timesLabel:SetPoint("LEFT", repeatInput, "RIGHT", 4, 0)
            timesLabel:SetText("times")

            local function SyncModeRadios()
                local m = actions[st.key .. "Mode"] or st.defaultMode
                playOnceCheck:SetChecked(m == "once")
                loopCheck:SetChecked(m == "loop")
                repeatCheck:SetChecked(m == "repeat")
                if m == "repeat" then
                    repeatInput:Enable()
                    repeatInput:SetAlpha(1)
                else
                    repeatInput:Disable()
                    repeatInput:SetAlpha(0.5)
                end
            end
            SyncModeRadios()

            playOnceCheck:SetScript("OnClick", function()
                actions[st.key .. "Mode"] = "once"
                SyncModeRadios()
                saveConditions()
            end)

            loopCheck:SetScript("OnClick", function()
                actions[st.key .. "Mode"] = "loop"
                SyncModeRadios()
                saveConditions()
            end)

            repeatCheck:SetScript("OnClick", function()
                actions[st.key .. "Mode"] = "repeat"
                SyncModeRadios()
                saveConditions()
            end)

            repeatInput:SetScript("OnTextChanged", function(self, isUserInput)
                if isUserInput then
                    local countVal = tonumber(self:GetText()) or 1
                    actions[st.key .. "Count"] = countVal
                    actions[st.key .. "Mode"] = "repeat"
                    SyncModeRadios()
                    saveConditions()
                end
            end)

            yOffset = yOffset - 32
        end

        for _, st in ipairs(stages) do
            CreateStageBlock(frame, st)
        end

        return yOffset
    end
})
