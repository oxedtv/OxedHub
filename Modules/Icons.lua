local addonName, OxedHub = ...
local L = OxedHub.L
local Icons = {}
OxedHub.Icons = Icons

local activeIcons = {}
local iconPool = {}

local HORDE_FLAG = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\H-flag.png"
local ALLIANCE_FLAG = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\A-flag.png"

local function ResolveIconTexture(spellID, textureType)
    local isLust = OxedHub.IsLustSpell and OxedHub.IsLustSpell(spellID)
    if isLust and (not textureType or textureType == "SPELL" or textureType == "FACTION") then
        local faction = UnitFactionGroup("player")
        textureType = (faction == "Alliance") and "ALLIANCE" or "HORDE"
    end

    if textureType == "HORDE" then
        return HORDE_FLAG
    elseif textureType == "ALLIANCE" then
        return ALLIANCE_FLAG
    elseif textureType == "FACTION" then
        local faction = UnitFactionGroup("player")
        return (faction == "Alliance") and ALLIANCE_FLAG or HORDE_FLAG
    end

    local sID = tonumber(spellID)
    if sID then
        local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sID)
        if spellInfo and spellInfo.iconID then
            return spellInfo.iconID
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function AcquireIconFrame()
    local frame = table.remove(iconPool)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(64, 64)
        frame:SetFrameStrata("HIGH")
        
        -- Draining Clip Frame Container (LustAlert style)
        local clipFrame = CreateFrame("Frame", nil, frame)
        clipFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        clipFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        clipFrame:SetHeight(64)
        clipFrame:SetClipsChildren(true)
        frame.clipFrame = clipFrame
        
        local texture = clipFrame:CreateTexture(nil, "ARTWORK")
        texture:SetPoint("BOTTOMLEFT", clipFrame, "BOTTOMLEFT", 0, 0)
        texture:SetPoint("BOTTOMRIGHT", clipFrame, "BOTTOMRIGHT", 0, 0)
        texture:SetHeight(64)
        frame.texture = texture

        local mask = frame:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        mask:SetAllPoints(texture)
        frame.mask = mask

        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(true)
        cd:SetHideCountdownNumbers(true)
        frame.cd = cd
        
        -- Timer Countdown FontString placed UNDER the flag/icon frame (LustAlert style)
        local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
        timerText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
        timerText:SetFont("Fonts\\2002.TTF", 20, "OUTLINE")
        timerText:SetTextColor(1, 1, 1, 1)
        timerText:SetText("")
        frame.timerText = timerText

        -- Animation Group
        local ag = frame:CreateAnimationGroup()
        
        -- Fade In
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.2)
        fadeIn:SetOrder(1)
        
        -- Hold
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(1.5) -- Default hold time
        hold:SetOrder(2)
        frame.holdAnim = hold
        
        -- Fade Out
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.5)
        fadeOut:SetOrder(3)
        
        ag:SetScript("OnFinished", function()
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
            table.insert(iconPool, frame)
            for i, f in ipairs(activeIcons) do
                if f == frame then
                    table.remove(activeIcons, i)
                    break
                end
            end
        end)
        frame.ag = ag
    end
    return frame
end

function Icons:PlayScreenIcon(spellID, posData, duration, expirationTime, isAura)
    local frame = AcquireIconFrame()
    frame.spellID = tonumber(spellID) or spellID -- Tag frame with spellID
    
    posData = posData or {}
    local iconTexture = ResolveIconTexture(spellID, posData.iconTextureType)
    frame.texture:SetTexture(iconTexture)
    
    local style = posData.style or "SQUARE"
    if type(iconTexture) == "string" and iconTexture:find("%-flag%.png") then
        frame.texture:SetTexCoord(0, 1, 0, 1)
    else
        frame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    if style == "CIRCLE" then
        frame.texture:AddMaskTexture(frame.mask)
        frame.cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    else
        frame.texture:RemoveMaskTexture(frame.mask)
        frame.cd:SetSwipeTexture("Interface\\Cooldown\\swipe")
    end
    
    local size = 64
    if posData.useCustomPosition then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", posData.x or 0, posData.y or 0)
        size = posData.size or 64
        frame:SetSize(size, size)
    else
        -- Default position
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        frame:SetSize(64, 64)
    end
    
    frame.clipFrame:SetSize(size, size)
    frame.texture:SetSize(size, size)
    frame.clipFrame:SetHeight(size)
    frame.texture:SetHeight(size)
    
    local fontSize = math.max(12, math.floor(size * 0.32))
    frame.timerText:SetFont("Fonts\\2002.TTF", fontSize, "OUTLINE")
    
    local isLust = OxedHub.IsLustSpell and OxedHub.IsLustSpell(spellID)
    local isDurationMode = posData.showDuration or isLust
    if isDurationMode then
        if not duration or type(duration) ~= "number" or duration <= 0 then
            duration = 40
        end
        if not expirationTime or type(expirationTime) ~= "number" then
            expirationTime = GetTime() + duration
        end
    end

    local cdDuration = duration
    local cdStart = GetTime()
    if expirationTime and duration and type(expirationTime) == "number" and type(duration) == "number" then
        cdStart = expirationTime - duration
    end
    
    -- Reset OnUpdate & timer text
    frame:SetScript("OnUpdate", nil)
    frame.timerText:SetText("")
    
    if posData.showCooldown and not isLust then
        cdDuration = 3 -- Default visual CD if unknown
        local sID = tonumber(spellID)
        if sID then
            local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(sID)
            if cdInfo and cdInfo.duration then
                if type(cdInfo.duration) == "number" and cdInfo.duration > 0 then
                    cdDuration = cdInfo.duration
                    cdStart = cdInfo.startTime
                elseif type(cdInfo.duration) ~= "number" then
                    cdDuration = cdInfo.duration
                    cdStart = cdInfo.startTime
                end
            end
        end
        frame.cd:Show()
        frame.cd:SetCooldown(cdStart, cdDuration)
        local animDuration = type(cdDuration) == "number" and cdDuration or 3
        frame.holdAnim:SetDuration(isAura and 86400 or math.max(0.2, animDuration)) -- 24 hours if aura
    elseif isDurationMode then
        -- Draining Clip Height + Timer Countdown (LustAlert style)
        frame.cd:Hide()
        local totalDur = duration or 40
        local expTime = expirationTime or (GetTime() + totalDur)
        frame.totalDuration = totalDur
        frame.expirationTime = expTime
        frame.baseSize = size
        
        frame:SetScript("OnUpdate", function(self, elapsed)
            local remaining = math.max(0, self.expirationTime - GetTime())
            if remaining <= 0 then
                self:SetScript("OnUpdate", nil)
                self.timerText:SetText("")
                self.clipFrame:SetHeight(0.1)
                self.ag:Stop()
                self:Hide()
                return
            end
            
            self.timerText:SetText(string.format("%.1f", remaining))
            
            local pct = remaining / self.totalDuration
            local clipH = math.max(1, math.floor(pct * self.baseSize))
            self.clipFrame:SetHeight(clipH)
        end)
        
        frame.holdAnim:SetDuration(totalDur)
    else
        frame.cd:Hide()
        local animDuration = type(duration) == "number" and duration or 1.5
        frame.holdAnim:SetDuration(isAura and 86400 or animDuration)
    end
    
    frame:Show()
    frame.ag:Play()
    table.insert(activeIcons, frame)
end

function Icons:StopScreenIcon(spellID)
    local targetID = tonumber(spellID) or spellID
    for i = #activeIcons, 1, -1 do
        local frame = activeIcons[i]
        if frame.spellID == targetID then
            frame:SetScript("OnUpdate", nil)
            frame.ag:Stop()
            frame:Hide()
            table.remove(activeIcons, i)
            table.insert(iconPool, frame)
        end
    end
end

function Icons:StopAll()
    for _, frame in ipairs(activeIcons) do
        frame:SetScript("OnUpdate", nil)
        frame.ag:Stop()
        frame:Hide()
        table.insert(iconPool, frame)
    end
    table.wipe(activeIcons)
end

function Icons:CreatePositionFrame()
    if self.positionFrame then return end
    
    local frame = CreateFrame("Frame", "OxedHubIconPositionFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(310, 220, 800, 800) end
    frame:SetSize(310, 250)
    frame:SetPoint("CENTER")
    frame:Hide()
    
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.35)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", frame, "TOP", 0, 18)
    title:SetText(L["ANIM_DRAG_TO_POS"] or "Drag to Position")
    title:SetTextColor(1, 0.82, 0, 1)
    
    local instr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instr:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    instr:SetText(L["ANIM_DRAG_TO_MOVE"] or "Drag to move  •  drag the corner to resize")
    instr:SetTextColor(0.7, 0.7, 0.7, 0.9)
    
    -- Inner container for the actual icon preview so it can be resized cleanly
    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("TOP", frame, "TOP", 0, -20)
    container:SetSize(64, 64)
    frame.iconContainer = container
    
    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    frame.icon = icon
    
    local mask = container:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    frame.mask = mask

    local cd = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(true)
    cd:SetHideCountdownNumbers(true)
    frame.cd = cd
    
    local timerText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    timerText:SetPoint("TOP", container, "BOTTOM", 0, -2)
    timerText:SetFont("Fonts\\2002.TTF", 18, "OUTLINE")
    timerText:SetTextColor(1, 1, 1, 1)
    timerText:SetText("9.0")
    timerText:Hide()
    frame.timerText = timerText

    frame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    
    local function SavePosition()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if frame.targetTrigger and frame.targetTrigger.actions then
            local xKey = frame.posXKey or "iconPositionX"
            local yKey = frame.posYKey or "iconPositionY"
            frame.targetTrigger.actions[xKey] = x - ux
            frame.targetTrigger.actions[yKey] = y - uy
            frame.targetTrigger.actions.iconUseCustomPosition = true
            frame.targetTrigger.actions.iconSize = container:GetWidth()
        end
    end
    
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()
            SavePosition()
        end
    end)
    
    frame:SetScript("OnSizeChanged", function(self, w, h)
        local padding = 125 -- space for controls and top padding
        local size = math.min(w - 20, h - padding)
        size = math.max(32, size)
        container:SetSize(size, size)
        local fontSize = math.max(12, math.floor(size * 0.28))
        timerText:SetFont("Fonts\\2002.TTF", fontSize, "OUTLINE")
    end)
    
    -- Controls Row 2 (Top Row of Controls, y = 40)
    local styleBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    styleBtn:SetSize(110, 22)
    styleBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
    styleBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.styleBtn = styleBtn
    
    styleBtn:SetScript("OnClick", function()
        if not frame.targetTrigger then return end
        local actions = frame.targetTrigger.actions or {}
        local current = actions.iconStyle or "SQUARE"
        if current == "SQUARE" then
            actions.iconStyle = "ROUNDED"
        elseif current == "ROUNDED" then
            actions.iconStyle = "CIRCLE"
        else
            actions.iconStyle = "SQUARE"
        end
        Icons:UpdatePreviewStyling()
        if OxedHub.Modules and OxedHub.Modules.Triggers and OxedHub.Modules.Triggers.ShowAutoSaved then 
            OxedHub.Modules.Triggers.ShowAutoSaved(frame:GetParent()) 
        end
    end)
    
    -- Texture Selector button: Default -> Auto Faction -> Horde Flag -> Alliance Flag
    local texBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    texBtn:SetSize(140, 22)
    texBtn:SetPoint("LEFT", styleBtn, "RIGHT", 6, 0)
    texBtn:SetNormalFontObject("GameFontNormalSmall")
    frame.texBtn = texBtn
    
    texBtn:SetScript("OnClick", function()
        if not frame.targetTrigger then return end
        local actions = frame.targetTrigger.actions or {}
        local isLust = OxedHub.IsLustTrigger and OxedHub.IsLustTrigger(frame.targetTrigger)
        local faction = UnitFactionGroup("player")
        local defaultFlag = (faction == "Alliance") and "ALLIANCE" or "HORDE"
        local current = actions.iconTextureType or (isLust and defaultFlag or "SPELL")
        
        if isLust then
            if current == "HORDE" then
                actions.iconTextureType = "ALLIANCE"
            else
                actions.iconTextureType = "HORDE"
            end
        else
            if current == "SPELL" then
                actions.iconTextureType = "HORDE"
            elseif current == "HORDE" then
                actions.iconTextureType = "ALLIANCE"
            else
                actions.iconTextureType = "SPELL"
            end
        end
        Icons:UpdatePreviewStyling()
        if OxedHub.Modules and OxedHub.Modules.Triggers and OxedHub.Modules.Triggers.ShowAutoSaved then 
            OxedHub.Modules.Triggers.ShowAutoSaved(frame:GetParent()) 
        end
    end)
    
    -- Controls Row 1 (Bottom Row of Controls, y = 10)
    local cdCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cdCheck:SetSize(20, 20)
    cdCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    cdCheck.text:SetText("Show CD")
    frame.cdCheck = cdCheck
    
    local durCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    durCheck:SetSize(20, 20)
    durCheck:SetPoint("LEFT", cdCheck.text, "RIGHT", 15, 0)
    durCheck.text:SetText("Duration")
    frame.durCheck = durCheck
    
    cdCheck:SetScript("OnClick", function(self)
        if not frame.targetTrigger then return end
        local actions = frame.targetTrigger.actions or {}
        actions.iconShowCooldown = self:GetChecked()
        if actions.iconShowCooldown then 
            actions.iconShowDuration = false 
            durCheck:SetChecked(false)
        end
        Icons:UpdatePreviewStyling()
        if OxedHub.Modules and OxedHub.Modules.Triggers and OxedHub.Modules.Triggers.ShowAutoSaved then 
            OxedHub.Modules.Triggers.ShowAutoSaved(frame:GetParent()) 
        end
    end)
    
    durCheck:SetScript("OnClick", function(self)
        if not frame.targetTrigger then return end
        local actions = frame.targetTrigger.actions or {}
        actions.iconShowDuration = self:GetChecked()
        if actions.iconShowDuration then
            actions.iconShowCooldown = false
            cdCheck:SetChecked(false)
        end
        Icons:UpdatePreviewStyling()
        if OxedHub.Modules and OxedHub.Modules.Triggers and OxedHub.Modules.Triggers.ShowAutoSaved then 
            OxedHub.Modules.Triggers.ShowAutoSaved(frame:GetParent()) 
        end
    end)
    
    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 22)
    resetBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -78, 10)
    resetBtn:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
    resetBtn:SetScript("OnClick", function()
        if frame.targetTrigger and frame.targetTrigger.actions then
            frame.targetTrigger.actions.iconPositionX = 0
            frame.targetTrigger.actions.iconPositionY = 100
            frame.targetTrigger.actions.iconSize = 64
            frame.targetTrigger.actions.iconTextureType = "SPELL"
            Icons:ShowPositionFrameForTrigger(frame.targetTrigger)
        end
    end)
    
    local doneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    doneBtn:SetSize(60, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 10)
    doneBtn:SetText(L["BTN_DONE"] or "Done")
    doneBtn:SetScript("OnClick", function()
        SavePosition()
        frame:Hide()
    end)
    
    -- Resize grip
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() 
        frame:StopMovingOrSizing() 
        SavePosition()
    end)
    
    self.positionFrame = frame
end

function Icons:UpdatePreviewStyling()
    local frame = self.positionFrame
    if not frame or not frame.targetTrigger then return end
    
    local actions = frame.targetTrigger.actions or {}
    local style = actions.iconStyle or "SQUARE"
    local isLust = OxedHub.IsLustTrigger and OxedHub.IsLustTrigger(frame.targetTrigger)
    local faction = UnitFactionGroup("player")
    local defaultFlag = (faction == "Alliance") and "ALLIANCE" or "HORDE"
    local texType = actions.iconTextureType or (isLust and defaultFlag or "SPELL")
    if isLust and (texType == "SPELL" or texType == "FACTION") then
        texType = defaultFlag
        actions.iconTextureType = defaultFlag
    end
    
    if style == "ROUNDED" then
        frame.styleBtn:SetText("Style: Rounded")
    elseif style == "CIRCLE" then
        frame.styleBtn:SetText("Style: Circle")
    else
        frame.styleBtn:SetText("Style: Square")
    end

    if texType == "ALLIANCE" then
        frame.texBtn:SetText("Alliance Flag")
    elseif texType == "HORDE" then
        frame.texBtn:SetText("Horde Flag")
    else
        frame.texBtn:SetText("Default Icon")
    end
    
    local iconTex = ResolveIconTexture(frame.targetTrigger.conditions and frame.targetTrigger.conditions.spellID, texType)
    frame.icon:SetTexture(iconTex)
    if type(iconTex) == "string" and iconTex:find("%-flag%.png") then
        frame.icon:SetTexCoord(0, 1, 0, 1)
    else
        frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    
    if style == "CIRCLE" then
        frame.icon:AddMaskTexture(frame.mask)
        frame.cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    else
        frame.icon:RemoveMaskTexture(frame.mask)
        frame.cd:SetSwipeTexture("Interface\\Cooldown\\swipe")
    end
    
    if isLust then
        frame.styleBtn:Hide()
        frame.texBtn:ClearAllPoints()
        frame.texBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 40)
        
        frame.cdCheck:Hide()
        actions.iconShowDuration = true
        actions.iconShowCooldown = false
        if frame.durCheck then
            frame.durCheck:ClearAllPoints()
            frame.durCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
            frame.durCheck:SetChecked(true)
        end
    else
        frame.styleBtn:Show()
        frame.texBtn:ClearAllPoints()
        frame.texBtn:SetPoint("LEFT", frame.styleBtn, "RIGHT", 6, 0)
        
        frame.cdCheck:Show()
        frame.cdCheck:SetChecked(actions.iconShowCooldown and true or false)
        if frame.durCheck then
            frame.durCheck:ClearAllPoints()
            frame.durCheck:SetPoint("LEFT", frame.cdCheck.text, "RIGHT", 15, 0)
            frame.durCheck:SetChecked(actions.iconShowDuration and true or false)
        end
    end
    
    if actions.iconShowCooldown and not isLust then
        frame.cd:Show()
        frame.cd:SetCooldown(GetTime(), 10)
        frame.timerText:Hide()
    elseif actions.iconShowDuration or isLust then
        frame.cd:Hide()
        frame.timerText:Show()
        frame.timerText:SetText("9.0")
    else
        frame.cd:Hide()
        frame.timerText:Hide()
    end
end

function Icons:ShowPositionFrameForTrigger(trigger, posXKey, posYKey)
    if not trigger then return end
    
    self:CreatePositionFrame()
    local frame = self.positionFrame
    frame.targetTrigger = trigger
    frame.posXKey = posXKey
    frame.posYKey = posYKey
    
    local actions = trigger.actions or {}
    
    local x = actions[posXKey or "iconPositionX"] or 0
    local y = actions[posYKey or "iconPositionY"] or 100
    local size = actions.iconSize or 64
    
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    frame:SetSize(math.max(310, size + 60), math.max(250, size + 130))
    frame.iconContainer:SetSize(size, size)
    
    Icons:UpdatePreviewStyling()
    
    frame:Show()
end
