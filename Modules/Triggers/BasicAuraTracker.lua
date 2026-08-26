local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

local playerContainer
local targetContainer

local function ParseIgnoreList(str)
    local list = {}
    if not str or str == "" then return list end
    for item in string.gmatch(str, "([^,]+)") do
        item = strtrim(item)
        if item ~= "" then
            local id = tonumber(item)
            if id then
                list[id] = true
            else
                list[string.lower(item)] = true
            end
        end
    end
    return list
end

-- ============================================================
-- Preview
-- ============================================================

local function SpawnPreviewAuras(container, size, boxWidth, boxHeight, maskStyle, showCooldown, showDuration)
    if not container.previewFrames then container.previewFrames = {} end
    for _, f in ipairs(container.previewFrames) do f:Hide() end
    if not OxedHubBasicAuraPreviewEnabled then return end

    local spacing = 4
    local cols = math.max(1, math.floor(boxWidth / (size + spacing)))
    local rows = math.max(1, math.floor(boxHeight / (size + spacing)))
    local count = cols * rows

    local icons = { 132276, 132275, 132274, 132273, 132272, 132271, 132270, 132269, 132268, 132267, 132266, 132265, 132264, 132263, 132262, 132261 }
    for i = 1, count do
        local f = container.previewFrames[i]
        if not f then
            f = CreateFrame("Button", nil, container)
            local icon = f:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(f)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            f.icon = icon
            local mask = f:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            mask:SetAllPoints(icon)
            f.mask = mask
            local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetDrawEdge(false)
            f.cd = cd
            table.insert(container.previewFrames, f)
        end
        f:SetSize(size, size)
        f:ClearAllPoints()
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        f:SetPoint("TOPLEFT", container, "TOPLEFT", col * (size + spacing), -row * (size + spacing))
        
        if maskStyle == "CIRCLE" then
            f.icon:AddMaskTexture(f.mask)
            f.cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        else
            f.icon:RemoveMaskTexture(f.mask)
            f.cd:SetSwipeTexture("Interface\\Cooldown\\swipe")
        end
        f.cd:SetDrawSwipe(showCooldown and true or false)
        f.cd:SetHideCountdownNumbers(not showDuration)
        f.icon:SetTexture(icons[(i - 1) % #icons + 1])
        if showCooldown or showDuration then
            f.cd:SetCooldown(GetTime(), 30 + i * 2)
            f.cd:Show()
        else
            f.cd:Hide()
        end
        f:Show()
    end
end

local function MakeDraggable(container, trigger, posXKey, posYKey, widthKey, heightKey, isPreview, boxWidth, boxHeight)
    if not container.dragFrame then
        local dragFrame = CreateFrame("Frame", nil, UIParent)
        dragFrame:SetFrameStrata("DIALOG")
        dragFrame:EnableMouse(true)
        dragFrame:RegisterForDrag("LeftButton")
        
        dragFrame.targetContainer = container

        dragFrame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        
        dragFrame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local x, y = self:GetCenter()
            local ux, uy = UIParent:GetCenter()
            local newX = x - ux
            local newY = y - uy
            
            trigger.actions[posXKey] = newX
            trigger.actions[posYKey] = newY
            
            self.targetContainer:ClearAllPoints()
            self.targetContainer:SetPoint("CENTER", UIParent, "CENTER", newX, newY)

            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(self)
            end
        end)
        
        local tex = dragFrame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(0, 1, 0, 0.2)
        dragFrame.tex = tex
        
        local label = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("BOTTOM", dragFrame, "TOP", 0, 2)
        dragFrame.label = label
        
        -- Resize Handle
        local resizeHandle = CreateFrame("Button", nil, dragFrame)
        resizeHandle:SetSize(16, 16)
        resizeHandle:SetPoint("BOTTOMRIGHT", dragFrame, "BOTTOMRIGHT")
        local resTex = resizeHandle:CreateTexture(nil, "OVERLAY")
        resTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        resTex:SetAllPoints()
        resizeHandle:SetNormalTexture(resTex)
        resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        
        resizeHandle:EnableMouse(true)
        resizeHandle:RegisterForDrag("LeftButton")
        resizeHandle:SetScript("OnDragStart", function(self)
            local p = self:GetParent()
            p:SetResizable(true)
            p:StartSizing("BOTTOMRIGHT")
        end)
        
        resizeHandle:SetScript("OnDragStop", function(self)
            local p = self:GetParent()
            p:StopMovingOrSizing()
            p:SetResizable(false)
            trigger.actions[widthKey] = p:GetWidth()
            trigger.actions[heightKey] = p:GetHeight()
            
            if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(p)
            end
            
            if trigger.event == "BASIC_AURA_TRACKER" then
                if OxedHub.Triggers.RefreshNativeEffects then
                    OxedHub.Triggers.RefreshNativeEffects()
                end
            end
        end)
        dragFrame.resizeHandle = resizeHandle
        container.dragFrame = dragFrame
    end

    if isPreview then
        container.dragFrame:ClearAllPoints()
        container.dragFrame:SetPoint("CENTER", UIParent, "CENTER", trigger.actions[posXKey] or 0, trigger.actions[posYKey] or 0)
        container.dragFrame:SetSize(boxWidth, boxHeight)
        container.dragFrame.label:SetText(posXKey == "playerPosX" and "Player Buffs" or "Target Debuffs")
        container.dragFrame:SetMovable(true)
        container.dragFrame:Show()
    else
        container.dragFrame:Hide()
    end
end

-- ============================================================
-- Build AuraContainer
-- ============================================================

local function BuildAuraContainer(id, unit, filterStr, size, posX, posY, boxWidth, boxHeight, maskStyle, showCooldown, showDuration, ignoreListStr, onlyMine, existingContainer)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end

    local spacing = 4
    local calculatedStride = math.max(1, math.floor(boxWidth / (size + spacing)))

    local container = existingContainer
    local groupKey = "OxedHubBT_" .. id
    
    if not container then
        container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        container:SetFrameStrata("HIGH")
        container:SetUnit(unit)
        container.oxButtons = {}
        container.oxIgnored = {}
        
        -- Set initial state variables so initializeFrame doesn't get nil
        container.oxSize = size
        container.oxStride = calculatedStride
        container.oxMaskStyle = maskStyle
        container.oxShowCd = showCooldown
        container.oxShowDur = showDuration
        container.oxIgnored = ParseIgnoreList(ignoreListStr)
        container.oxOnlyMine = onlyMine
        
        local customFilter = function(auraData)
            if OxedHubBasicAuraPreviewEnabled then return false end
            if auraData.spellId and container.oxIgnored[auraData.spellId] then return false end
            if auraData.name and container.oxIgnored[string.lower(auraData.name)] then return false end
            if container.oxOnlyMine then
                local src = auraData.sourceUnit
                if src ~= "player" and src ~= "pet" and src ~= "vehicle" then
                    return false
                end
            end
            return true
        end

        local options = {
            maxFrameCount = 40,
            customFilter = customFilter,
            initializeFrame = function(button)
                if not button._oxIcon then
                    local icon = button:CreateTexture(nil, "ARTWORK")
                    icon:SetAllPoints(button)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    button:SetIcon(icon)
                    button._oxIcon = icon
                    
                    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
                    cd:SetAllPoints(icon)
                    cd:SetDrawEdge(false)
                    cd:Show()
                    button:SetDurationCooldown(cd)
                    button._oxCd = cd
                    
                    local mask = button:CreateMaskTexture()
                    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                    mask:SetAllPoints(icon)
                    button._oxMask = mask
                    
                    container.oxButtons[button] = true
                end
                
                -- Configure layout based on container settings
                button:SetSize(container.oxSize, container.oxSize)
                if container.oxMaskStyle == "CIRCLE" then
                    button._oxIcon:AddMaskTexture(button._oxMask)
                    button._oxCd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                else
                    button._oxIcon:RemoveMaskTexture(button._oxMask)
                    button._oxCd:SetSwipeTexture("Interface\\Cooldown\\swipe")
                end
                button._oxCd:SetDrawSwipe(container.oxShowCd and true or false)
                button._oxCd:SetHideCountdownNumbers(not container.oxShowDur)
            end,
            layout = {
                elementWidth = size,
                elementHeight = size,
                stride = calculatedStride,
                elementSpacing = spacing,
                lineSpacing = spacing,
            },
        }
        
        container:AddAuraGroup(groupKey, filterStr, options)
    end
    
    -- Update container state variables (for subsequent updates)
    container.oxSize = size
    container.oxStride = calculatedStride
    container.oxMaskStyle = maskStyle
    container.oxShowCd = showCooldown
    container.oxShowDur = showDuration
    container.oxIgnored = ParseIgnoreList(ignoreListStr)
    container.oxOnlyMine = onlyMine
    
    -- Update layout via Blizzard API
    if container:HasAuraGroup(groupKey) then
        container:SetAuraGroupLayout(groupKey, {
            elementWidth = size,
            elementHeight = size,
            stride = calculatedStride,
            elementSpacing = spacing,
            lineSpacing = spacing,
        })
    end
    
    -- Manually reconfigure existing buttons (pcall: buttons may be
    -- Blizzard-protected secure frames that reject addon-tainted calls)
    for button in pairs(container.oxButtons) do
        pcall(function()
            button:SetSize(size, size)
            if maskStyle == "CIRCLE" then
                button._oxIcon:AddMaskTexture(button._oxMask)
                button._oxCd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
            else
                button._oxIcon:RemoveMaskTexture(button._oxMask)
                button._oxCd:SetSwipeTexture("Interface\\Cooldown\\swipe")
            end
            button._oxCd:SetDrawSwipe(showCooldown and true or false)
            button._oxCd:SetHideCountdownNumbers(not showDuration)
        end)
    end
    
    container:SetEnabled(true)
    container:Show()
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
    container:SetSize(boxWidth, boxHeight)
    
    -- Force engine to re-run filters and re-anchor buttons
    if container.UpdateAuras then container:UpdateAuras() end
    if container.UpdateAllAuras then container:UpdateAllAuras() end
    
    return container
end

-- ============================================================
-- Main evaluator
-- ============================================================

local function EvaluateBasicAuraTracker()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile or not profile.triggers then return end

    for id, trigger in pairs(profile.triggers) do
        if trigger.event == "BASIC_AURA_TRACKER" and trigger.enabled then
            local actions = trigger.actions or {}
            local size = actions.iconSize or 40
            local maskStyle = "SQUARE"
            local showCd = false
            local showDur = actions.iconShowDuration
            
            local pBoxW = actions.playerBoxWidth or (size * 5 + 16)
            local pBoxH = actions.playerBoxHeight or (size * 2 + 4)
            local tBoxW = actions.targetBoxWidth or (size * 5 + 16)
            local tBoxH = actions.targetBoxHeight or (size * 2 + 4)

            --[[
            if actions.trackPlayerBuffs then
                playerContainer = BuildAuraContainer("Player", "player", "HELPFUL", size, actions.playerPosX or 0, actions.playerPosY or 100, pBoxW, pBoxH, maskStyle, showCd, showDur, actions.ignoreList, false, playerContainer)
                SpawnPreviewAuras(playerContainer, size, pBoxW, pBoxH, maskStyle, showCd, showDur)
                MakeDraggable(playerContainer, trigger, "playerPosX", "playerPosY", "playerBoxWidth", "playerBoxHeight", OxedHubBasicAuraPreviewEnabled, pBoxW, pBoxH)
            end
            ]]--

            local doTrackTarget = (actions.trackTargetDebuffs == nil) and true or actions.trackTargetDebuffs
            local onlyMine = (actions.onlyMyDebuffs == nil) and true or actions.onlyMyDebuffs
            if doTrackTarget then
                local filterStr = onlyMine and "HARMFUL|PLAYER" or "HARMFUL"
                targetContainer = BuildAuraContainer("Target", "target", filterStr, size, actions.targetPosX or 0, actions.targetPosY or -100, tBoxW, tBoxH, maskStyle, showCd, showDur, actions.ignoreList, onlyMine, targetContainer)
                SpawnPreviewAuras(targetContainer, size, tBoxW, tBoxH, maskStyle, showCd, showDur)
                MakeDraggable(targetContainer, trigger, "targetPosX", "targetPosY", "targetBoxWidth", "targetBoxHeight", OxedHubBasicAuraPreviewEnabled, tBoxW, tBoxH)
                
                -- Target alpha logic based on selection
                if not targetContainer.eventFrame then
                    local targetEventFrame = CreateFrame("Frame")
                    targetEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
                    targetEventFrame:SetScript("OnEvent", function()
                        -- Force the Blizzard engine to rebuild the aura list for the new target immediately
                        if targetContainer.UpdateAllAuras then
                            targetContainer:UpdateAllAuras()
                        end
                        
                        if OxedHubBasicAuraPreviewEnabled then
                            targetContainer:SetAlpha(1)
                            return
                        end
                        if UnitExists("target") and not UnitIsDead("target") then
                            targetContainer:SetAlpha(1)
                        else
                            targetContainer:SetAlpha(0)
                        end
                    end)
                    targetContainer.eventFrame = targetEventFrame
                end
                
                if OxedHubBasicAuraPreviewEnabled or (UnitExists("target") and not UnitIsDead("target")) then
                    targetContainer:SetAlpha(1)
                else
                    targetContainer:SetAlpha(0)
                end
            end
        end
    end
end

-- ============================================================
-- Bootstrap
-- ============================================================

local monitor = CreateFrame("Frame")
monitor:RegisterEvent("PLAYER_ENTERING_WORLD")
monitor:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        EvaluateBasicAuraTracker()
    end
end)

SLASH_OXEDHUBDEBUGBT1 = "/oxedhubdebug"
SlashCmdList["OXEDHUBDEBUGBT"] = function(msg)
    if msg == "bstracker" then
        print("--- OxedHub Basic Aura Tracker Debug ---")
        for _, unitInfo in ipairs({{"player", playerContainer}, {"target", targetContainer}}) do
            local u, c = unitInfo[1], unitInfo[2]
            if c then
                local cacheSize = 0
                if auraCaches[u] then
                    for _ in pairs(auraCaches[u]) do cacheSize = cacheSize + 1 end
                end
                print("|cff00ff00" .. u .. ":|r Size=" .. tostring(c.oxSize) .. " Alpha=" .. string.format("%.1f", c:GetAlpha()) .. " Vis=" .. tostring(c:IsVisible()) .. " CacheSize=" .. cacheSize)
            else
                print("|cffff0000" .. u .. " container: NIL|r")
            end
        end
        print("Preview: " .. tostring(OxedHubBasicAuraPreviewEnabled))
        print("--- END ---")
    end
end

-- ============================================================
-- Register UI
-- ============================================================

Triggers:RegisterEventType("BASIC_AURA_TRACKER", {
    name = "My Target Debuffs",
    allowCustomSpells = false,

    CreateConditionUI = function(frame, trigger, yOffset)
        if not yOffset then yOffset = -10 end

        --[[
        local trackPlayer = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
        trackPlayer:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        trackPlayer.Text:SetText("Track Player Buffs")
        trackPlayer:SetChecked(trigger.actions.trackPlayerBuffs)
        trackPlayer:SetScript("OnClick", function(cb)
            if not trigger.actions then trigger.actions = {} end
            trigger.actions.trackPlayerBuffs = cb:GetChecked()
            EvaluateBasicAuraTracker()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 30
        ]]--

        local trackTarget = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
        trackTarget:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        trackTarget.Text:SetText("Track Target Debuffs")
        trackTarget:SetChecked(trigger.actions.trackTargetDebuffs == nil and true or trigger.actions.trackTargetDebuffs)
        trackTarget:SetScript("OnClick", function(cb)
            if not trigger.actions then trigger.actions = {} end
            trigger.actions.trackTargetDebuffs = cb:GetChecked()
            EvaluateBasicAuraTracker()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 35

        local onlyMineCheck = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
        onlyMineCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        onlyMineCheck.Text:SetText("Only My Debuffs")
        onlyMineCheck:SetChecked(trigger.actions.onlyMyDebuffs == nil and true or trigger.actions.onlyMyDebuffs)
        onlyMineCheck:SetScript("OnClick", function(cb)
            if not trigger.actions then trigger.actions = {} end
            trigger.actions.onlyMyDebuffs = cb:GetChecked()
            EvaluateBasicAuraTracker()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 35

        --[[
        -- Ignore List
        local ignoreLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ignoreLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        ignoreLabel:SetText("Ignore List (IDs or Names, comma separated):")
        yOffset = yOffset - 15

        local ignoreInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        ignoreInput:SetSize(250, 20)
        ignoreInput:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        ignoreInput:SetAutoFocus(false)
        ignoreInput:SetText(trigger.actions.ignoreList or "")
        ignoreInput:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                if not trigger.actions then trigger.actions = {} end
                trigger.actions.ignoreList = self:GetText()
                EvaluateBasicAuraTracker()
                if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
            end
        end)
        yOffset = yOffset - 30
        ]]--

        local durCheck = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
        durCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        durCheck.Text:SetText("Show Duration Text")
        durCheck:SetChecked(trigger.actions.iconShowDuration == nil and true or trigger.actions.iconShowDuration)
        durCheck:SetScript("OnClick", function(cb)
            if not trigger.actions then trigger.actions = {} end
            trigger.actions.iconShowDuration = cb:GetChecked()
            EvaluateBasicAuraTracker()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 35

        local sizeSlider = CreateFrame("Slider", "OxedHubBasicAuraSizeSlider" .. (trigger.id or "New"), frame, "OptionsSliderTemplate")
        sizeSlider:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, yOffset)
        sizeSlider:SetWidth(150)
        sizeSlider:SetMinMaxValues(16, 128)
        sizeSlider:SetValueStep(1)
        sizeSlider:SetObeyStepOnDrag(true)
        sizeSlider:SetValue(trigger.actions.iconSize or 40)
        _G[sizeSlider:GetName() .. "Text"]:SetText("Icon Size: " .. (trigger.actions.iconSize or 40))
        _G[sizeSlider:GetName() .. "Low"]:SetText("16")
        _G[sizeSlider:GetName() .. "High"]:SetText("128")
        sizeSlider:SetScript("OnValueChanged", function(self, value)
            if not trigger.actions then trigger.actions = {} end
            trigger.actions.iconSize = value
            _G[self:GetName() .. "Text"]:SetText("Icon Size: " .. value)
            EvaluateBasicAuraTracker()
            if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
        end)
        yOffset = yOffset - 45

        --[[
        local styleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        styleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        styleLabel:SetText("Icon Style:")
        local styleDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        styleDropdown:SetPoint("LEFT", styleLabel, "RIGHT", 10, 0)
        styleDropdown:SetSize(120, 22)
        local currentStyle = trigger.actions.iconStyle or "CIRCLE"
        styleDropdown:OverrideText(currentStyle == "CIRCLE" and "Circle" or "Square")
        styleDropdown:SetupMenu(function(dropdown, rootDescription)
            rootDescription:CreateRadio("Circle", function() return currentStyle == "CIRCLE" end, function()
                if not trigger.actions then trigger.actions = {} end
                trigger.actions.iconStyle = "CIRCLE"
                currentStyle = "CIRCLE"
                dropdown:OverrideText("Circle")
                EvaluateBasicAuraTracker()
                if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
            end)
            rootDescription:CreateRadio("Square", function() return currentStyle == "SQUARE" end, function()
                if not trigger.actions then trigger.actions = {} end
                trigger.actions.iconStyle = "SQUARE"
                currentStyle = "SQUARE"
                dropdown:OverrideText("Square")
                EvaluateBasicAuraTracker()
                if Triggers.ShowAutoSaved then Triggers.ShowAutoSaved(frame:GetParent()) end
            end)
        end)
        yOffset = yOffset - 30
        ]]--

        local previewCheck = CreateFrame("CheckButton", nil, frame, "ChatConfigCheckButtonTemplate")
        previewCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, yOffset)
        previewCheck.Text:SetText("Preview Layout (Simulate Buffs) & Enable Moving")
        previewCheck:SetChecked(OxedHubBasicAuraPreviewEnabled and true or false)
        previewCheck:SetScript("OnClick", function(cb)
            OxedHubBasicAuraPreviewEnabled = cb:GetChecked()
            EvaluateBasicAuraTracker()
        end)
        yOffset = yOffset - 30

        return yOffset
    end,

    RefreshNativeEffects = EvaluateBasicAuraTracker,
    OnProfileChanged = EvaluateBasicAuraTracker
})
