local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey
local L = OxedHub.L

OxedHub.Triggers:RegisterEventType("PREY_HUNT", {
    name = L["EVT_PREY_HUNT"] or "Prey Hunt",
    CheckCondition = function(trigger, eventData)
        return false -- Handled internally by PreyEngine
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}
        local conditions = trigger.conditions
        trigger.actions = trigger.actions or {}
        local actions = trigger.actions
        yOffset = yOffset or 0

        -- Defaults
        if conditions.enableGossipHelper == nil then conditions.enableGossipHelper = true end
        if conditions.showHUDBar == nil then conditions.showHUDBar = true end
        if conditions.onlyShowInPreyZone == nil then conditions.onlyShowInPreyZone = false end
        if conditions.showBlizzardWidget == nil then conditions.showBlizzardWidget = true end
        if conditions.showSections == nil then conditions.showSections = true end
        if conditions.lockHUDBar == nil then conditions.lockHUDBar = false end

        local function saveConditions()
            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
            if Prey.HUD then
                Prey.HUD:SetLocked(conditions.lockHUDBar)
            end
            if Prey.Engine and Prey.Engine.ApplyBlizzardWidgetVisibility then
                Prey.Engine:ApplyBlizzardWidgetVisibility(conditions.showBlizzardWidget)
            end
            if Prey.Engine and Prey.Engine.UpdateActiveHunt then
                Prey.Engine:UpdateActiveHunt()
            end
        end

        -- Mirrors CreateActionIcon in Triggers/UI/ActionsTab.lua so Prey rows
        -- look identical to every other sound row in the addon.
        local function CreateIcon(parent, texturePath)
            local iconFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            iconFrame:SetSize(28, 28)
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
            iconFrame.icon = icon
            return iconFrame
        end

        local function TruncateText(text, maxLength)
            if not text or text == "None" or text == (L["NONE"] or "None") then return L["NONE"] or "None" end
            if string.len(text) <= maxLength then return text end
            return string.sub(text, 1, maxLength - 3) .. "..."
        end

        -- ----------------------------------------------------
        -- SECTION 1: Features & Visual Helpers
        -- ----------------------------------------------------
        local featureHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        featureHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        featureHeader:SetText("|cFFFFD900Visual Tracking & Gossip Helpers|r")
        yOffset = yOffset - 24

        -- Gossip Helper Checkbox
        local gossipCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        gossipCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        gossipCheck:SetSize(20, 20)
        gossipCheck:SetChecked(conditions.enableGossipHelper)
        gossipCheck.text:SetText("Show Achievement Helpers on Astalor Bloodsworn (Gossip Menu)")
        gossipCheck.text:SetTextColor(0.9, 0.9, 0.9)
        gossipCheck.text:SetWordWrap(false)
        gossipCheck:SetScript("OnClick", function(self)
            conditions.enableGossipHelper = self:GetChecked()
            saveConditions()
        end)
        yOffset = yOffset - 24

        -- HUD Bar Checkbox
        local hudCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        hudCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        hudCheck:SetSize(20, 20)
        hudCheck:SetChecked(conditions.showHUDBar)
        hudCheck.text:SetText("Show Draggable On-Screen Prey Hunt HUD Bar")
        hudCheck.text:SetTextColor(0.9, 0.9, 0.9)
        hudCheck.text:SetWordWrap(false)
        hudCheck:SetScript("OnClick", function(self)
            conditions.showHUDBar = self:GetChecked()
            saveConditions()
        end)

        -- Test HUD Button
        local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        testBtn:SetPoint("LEFT", hudCheck.text, "RIGHT", 14, 0)
        testBtn:SetPoint("CENTER", hudCheck, "CENTER", 0, 0)
        testBtn:SetSize(135, 22)
        testBtn:SetText("Test / Preview HUD")
        testBtn:SetNormalFontObject("GameFontNormalSmall")
        testBtn:SetScript("OnClick", function()
            if Prey.HUD then
                local isPreview = Prey.HUD:ToggleTestMode()
                testBtn:SetText(isPreview and "Hide Preview HUD" or "Test / Preview HUD")
            end
        end)

        -- Reset HUD Position Button
        local resetHUDPosBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        resetHUDPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 8, 0)
        resetHUDPosBtn:SetSize(130, 22)
        resetHUDPosBtn:SetText("Reset HUD Pos")
        resetHUDPosBtn:SetNormalFontObject("GameFontNormalSmall")
        resetHUDPosBtn:SetScript("OnClick", function()
            if Prey.HUD and Prey.HUD.ResetPosition then
                Prey.HUD:ResetPosition()
            end
        end)
        yOffset = yOffset - 24

        -- Only Show in Prey Zone Checkbox
        local onlyZoneCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        onlyZoneCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, yOffset)
        onlyZoneCheck:SetSize(20, 20)
        onlyZoneCheck:SetChecked(conditions.onlyShowInPreyZone)
        onlyZoneCheck.text:SetText("Only Show HUD Bar when Inside the Hunt Zone (Hide when outside)")
        onlyZoneCheck.text:SetTextColor(0.8, 0.8, 0.8)
        onlyZoneCheck.text:SetWordWrap(false)
        onlyZoneCheck:SetScript("OnClick", function(self)
            conditions.onlyShowInPreyZone = self:GetChecked()
            saveConditions()
        end)
        yOffset = yOffset - 24

        -- Lock Bar Checkbox
        local lockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        lockCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, yOffset)
        lockCheck:SetSize(20, 20)
        lockCheck:SetChecked(conditions.lockHUDBar)
        lockCheck.text:SetText("Lock HUD Bar in place (disable drag)")
        lockCheck.text:SetTextColor(0.8, 0.8, 0.8)
        lockCheck.text:SetWordWrap(false)
        lockCheck:SetScript("OnClick", function(self)
            conditions.lockHUDBar = self:GetChecked()
            saveConditions()
        end)
        yOffset = yOffset - 26

        -- Blizzard Native Widget Controls
        if conditions.blizzScale == nil then conditions.blizzScale = 100 end

        local blizzWidgetCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        blizzWidgetCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, yOffset)
        blizzWidgetCheck:SetSize(20, 20)
        blizzWidgetCheck:SetChecked(conditions.showBlizzardWidget)
        blizzWidgetCheck.text:SetText("Show Blizzard Native Prey Widget (Compass / Eye Icon on Screen)")
        blizzWidgetCheck.text:SetTextColor(0.9, 0.9, 0.9)
        blizzWidgetCheck.text:SetWordWrap(false)
        blizzWidgetCheck:SetScript("OnClick", function(self)
            conditions.showBlizzardWidget = self:GetChecked()
            saveConditions()
        end)

        -- Move Blizzard Widget Button
        local moveWidgetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        moveWidgetBtn:SetPoint("LEFT", blizzWidgetCheck.text, "RIGHT", 14, 0)
        moveWidgetBtn:SetPoint("CENTER", blizzWidgetCheck, "CENTER", 0, 0)
        moveWidgetBtn:SetSize(130, 22)
        moveWidgetBtn:SetText("Move Widget")
        moveWidgetBtn:SetNormalFontObject("GameFontNormalSmall")
        moveWidgetBtn:SetScript("OnClick", function()
            if Prey.Engine and Prey.Engine.ToggleBlizzardWidgetMover then
                local isActive = Prey.Engine:ToggleBlizzardWidgetMover()
                moveWidgetBtn:SetText(isActive and "Hide Mover" or "Move Widget")
            end
        end)

        -- Reset Blizzard Widget Position Button
        local resetWidgetPosBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        resetWidgetPosBtn:SetPoint("LEFT", moveWidgetBtn, "RIGHT", 8, 0)
        resetWidgetPosBtn:SetSize(110, 22)
        resetWidgetPosBtn:SetText("Reset Pos")
        resetWidgetPosBtn:SetNormalFontObject("GameFontNormalSmall")
        resetWidgetPosBtn:SetScript("OnClick", function()
            if OxedHub.db and OxedHub.db.profile then
                OxedHub.db.profile.preyBlizzWidgetPosition = nil
            end
            if Prey.Engine and Prey.Engine.blizzMoverFrame then
                Prey.Engine.blizzMoverFrame:ClearAllPoints()
                Prey.Engine.blizzMoverFrame:SetPoint("TOP", UIParent, "TOP", 0, -120)
            end
            local container = UIWidgetTopCenterContainerFrame
            if container then
                container:ClearAllPoints()
                container:SetPoint("TOP", UIParent, "TOP", 0, -120)
            end
        end)
        yOffset = yOffset - 28

        -- Blizzard Widget Scale Slider
        local scaleSlider = CreateFrame("Slider", "OxedHubPreyBlizzScaleSlider", frame, "OptionsSliderTemplate")
        scaleSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, yOffset)
        scaleSlider:SetWidth(180)
        scaleSlider:SetMinMaxValues(50, 150)
        scaleSlider:SetValueStep(5)
        scaleSlider:SetObeyStepOnDrag(true)
        scaleSlider:SetValue(conditions.blizzScale)
        -- OptionsSliderTemplate exposes Low/High/Text as frame members on current
        -- clients; the $parent globals are not reliable, so prefer the members.
        local sliderName = scaleSlider:GetName()
        local sliderLow  = scaleSlider.Low  or _G[sliderName .. "Low"]
        local sliderHigh = scaleSlider.High or _G[sliderName .. "High"]
        local sliderText = scaleSlider.Text or _G[sliderName .. "Text"]
        if sliderLow then sliderLow:SetText("50%") end
        if sliderHigh then sliderHigh:SetText("150%") end
        if sliderText then sliderText:SetText(string.format("Widget Scale: %d%%", conditions.blizzScale)) end

        scaleSlider:SetScript("OnValueChanged", function(self, value)
            value = math.floor(value + 0.5)
            if sliderText then sliderText:SetText(string.format("Widget Scale: %d%%", value)) end
            conditions.blizzScale = value
            if OxedHub.db and OxedHub.db.profile then
                OxedHub.db.profile.preyBlizzScale = value
            end
            if Prey.Engine and Prey.Engine.lastBlizzWidgetFrame then
                Prey.Engine.lastBlizzWidgetFrame:SetScale(value / 100)
            end
            saveConditions()
        end)
        yOffset = yOffset - 36

        -- ----------------------------------------------------
        -- SECTION 2: Audio Cues & Stage Triggers
        -- ----------------------------------------------------
        local soundHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        soundHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        soundHeader:SetText("|cFFFFD900Stage Transitions & Combat Audio|r")
        yOffset = yOffset - 24

        -- Same icon the standard sound rows use, so the section reads as one
        -- consistent "(icon) <what> Sound:" list.
        local SOUND_ICON = "Interface\\Icons\\INV_Misc_Horn_01"
        local soundRows = {
            { key = "stage1Sound", label = "Stage 1 (Scent in the Wind):" },
            { key = "stage2Sound", label = "Stage 2 (Blood in Shadows):" },
            { key = "stage3Sound", label = "Stage 3 (Echoes of Kill):" },
            { key = "stage4Sound", label = "Stage 4 (Feast of Fang):" },
            { key = "ambushSound", label = "Ambush Alert Sound:" },
            { key = "bloodyCommandSound", label = "Bloody Command (Nightmare):" },
            { key = "killSound", label = "Prey Slain (Turn-in / Kill):" },
        }

        local function CreateSoundRow(parent, labelText, actionKey, iconPath)
            local icon = CreateIcon(parent, iconPath)
            icon:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOffset)

            local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            label:SetText(labelText)
            label:SetWidth(190)
            label:SetJustifyH("LEFT")

            local soundBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            soundBtn:SetPoint("LEFT", label, "RIGHT", 10, 0)
            soundBtn:SetSize(150, 22)
            soundBtn:SetNormalFontObject("GameFontNormalSmall")

            local function UpdateSoundBtn()
                local val = actions[actionKey] or conditions[actionKey]
                local text = L["NONE"] or "None"
                local fullName = L["NONE"] or "None"
                if val and val ~= "" and val ~= "None" then
                    local data = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds and OxedHub.db.profile.customSounds[val]
                    fullName = data and data.name or val
                    text = TruncateText(fullName, 20)
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
                    OxedHub.Triggers:ShowSoundPicker(trigger, actionKey)
                end
            end)

            soundBtn:SetScript("OnUpdate", function(self)
                local val = actions[actionKey] or conditions[actionKey]
                if self.lastVal ~= val then
                    self.lastVal = val
                    UpdateSoundBtn()
                end
            end)

            yOffset = yOffset - 32
        end

        for _, sRow in ipairs(soundRows) do
            CreateSoundRow(frame, sRow.label, sRow.key, SOUND_ICON)
        end

        return yOffset - 10
    end
})
