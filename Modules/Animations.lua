local addonName, OxedHub = ...
local L = OxedHub.L
-- Animations Module - TGA sprite animation player
local Animations = {}
OxedHub.Animations = Animations

-- Local references
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetTime = GetTime
local math_floor = math.floor

-- Animation frames cache
local animationPlayers = {}
local activeAnimations = {}
local DEFAULT_ANIMATION_POSITION = { x = 0, y = 200 }

-- Initialize
function Animations:Init()
    self:CreatePlayerFrame()
    self:CreatePositionFrame()
end

function Animations:GetSavedAnimationPosition()
    local settings = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings
    local pos = settings and settings.animationPosition
    if pos and pos.x and pos.y then
        local uiCenterX, uiCenterY = UIParent:GetCenter()
        local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()

        -- Migrate old saved positions that used absolute left/top coordinates.
        if uiCenterX and uiCenterY and uiWidth and uiHeight and
           (math.abs(pos.x) > (uiWidth / 2) or math.abs(pos.y) > (uiHeight / 2)) then
            local frameWidth = (self.playerFrame and self.playerFrame:GetWidth()) or 128
            local frameHeight = (self.playerFrame and self.playerFrame:GetHeight()) or 128
            local migratedX = (pos.x + (frameWidth / 2)) - uiCenterX
            local migratedY = (pos.y - (frameHeight / 2)) - uiCenterY

            settings.animationPosition = {
                x = migratedX,
                y = migratedY,
            }

            return migratedX, migratedY
        end

        return pos.x, pos.y
    end

    return DEFAULT_ANIMATION_POSITION.x, DEFAULT_ANIMATION_POSITION.y
end

function Animations:SaveAnimationPosition(frame)
    if not frame then return end

    local frameX, frameY = frame:GetCenter()
    local uiX, uiY = UIParent:GetCenter()
    if not frameX or not frameY or not uiX or not uiY then
        return
    end

    local relX = frameX - uiX
    local relY = frameY - uiY

    if frame.onSaveCallback then
        frame.onSaveCallback(relX, relY)
    elseif frame.targetAnimId then
        local anim = OxedHub.db.profile.animations[frame.targetAnimId]
        if anim then
            anim.customPositionX = relX
            anim.customPositionY = relY
        end
    elseif OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        OxedHub.db.profile.settings.animationPosition = {
            x = relX,
            y = relY,
        }
    end
end

function Animations:ApplyPositionFramePosition()
    if not self.positionFrame then
        return
    end

    local x, y
    local targetId = self.positionFrame.targetAnimId
    if targetId then
        local anim = OxedHub.db.profile.animations[targetId]
        if anim then
            x = anim.customPositionX or 0
            y = anim.customPositionY or 200
        end
    elseif self.positionFrame.onSaveCallback then
        x = 0
        y = 200
    end
    if not x then
        x, y = self:GetSavedAnimationPosition()
    end
    self.positionFrame:ClearAllPoints()
    self.positionFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function Animations:AttachPlayerFrameToTarget(animData)
    if not self.playerFrame then
        return
    end

    self.playerFrame:ClearAllPoints()
    if not animData and self.positionFrame and self.positionFrame:IsShown() then
        -- Preview mode (no animData): follow the position frame
        self.playerFrame:SetPoint("CENTER", self.positionFrame, "CENTER", 0, 0)
    elseif animData and animData.useCustomPosition then
        -- Animation has its own custom position
        local x = animData.customPositionX or 0
        local y = animData.customPositionY or 200
        self.playerFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    else
        -- Use global default position
        local x, y = self:GetSavedAnimationPosition()
        self.playerFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

function Animations:ResetPreviewPosition()
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.settings then
        return
    end

    OxedHub.db.profile.settings.animationPosition = {
        x = DEFAULT_ANIMATION_POSITION.x,
        y = DEFAULT_ANIMATION_POSITION.y,
    }

    self:ApplyPositionFramePosition()
    self:AttachPlayerFrameToTarget()
end

-- Get or create player frame (Soundie-style)
function Animations:GetOrCreatePlayerFrame()
    if self.playerFrame then return self.playerFrame end
    self:CreatePlayerFrame()
    return self.playerFrame
end

-- Create the clean preview frame (no borders, just animation)
function Animations:CreatePlayerFrame()
    local frame = CreateFrame("Frame", "OxedHubAnimationFrame", UIParent)
    frame:SetSize(128, 128)
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_ANIMATION_POSITION.x, DEFAULT_ANIMATION_POSITION.y)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(50)
    frame:Hide()
    
    -- Texture for animation - no backdrop, no borders
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    frame.texture = tex
    
    self.playerFrame = frame
end

-- Play the target animation looped inside the position frame (live preview)
function Animations:StartPositionPreview(animData)
    self:StopPositionPreview()
    local frame = self.positionFrame
    if not frame or not frame.animTex or not animData then return end
    frame.animTex:SetTexture(animData.tgaPath)
    frame.animTex:Show()

    local cols = animData.columns or math.ceil(math.sqrt(animData.frameCount or 1))
    local rows = animData.rows or cols
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end
    local seq = animData.playSequence
    local maxFrames = (seq and #seq > 0) and #seq or (animData.frameCount or (cols * rows))
    if maxFrames < 1 then maxFrames = 1 end

    local function showStep(s)
        local frameNum = s
        if seq and #seq > 0 then frameNum = seq[s + 1] or s end
        local row = math.floor(frameNum / cols)
        local col = frameNum % cols
        frame.animTex:SetTexCoord(col / cols, (col + 1) / cols, row / rows, (row + 1) / rows)
    end
    showStep(0)

    local step = 0
    local fps = animData.fps or 24
    if fps < 1 then fps = 24 end
    self.positionPreviewTicker = C_Timer.NewTicker(1 / fps, function()
        step = (step + 1) % maxFrames
        showStep(step)
    end)
end

function Animations:StopPositionPreview()
    if self.positionPreviewTicker then
        self.positionPreviewTicker:Cancel()
        self.positionPreviewTicker = nil
    end
    if self.positionFrame and self.positionFrame.animTex then
        self.positionFrame.animTex:Hide()
    end
end

-- Reset the position frame to its plain "move only" look (crosshair, fixed size)
function Animations:_PositionFrameSimpleMode()
    local frame = self.positionFrame
    if not frame then return end
    self:StopPositionPreview()
    frame.lockAspect = nil
    frame._adjusting = true
    frame:SetSize(200, 140)
    frame._adjusting = false
    if frame.crossV then frame.crossV:Show(); frame.crossH:Show() end
    if frame.resizeGrip then frame.resizeGrip:Hide() end
end

-- Create the positioning frame (with controls for moving/strata)
function Animations:CreatePositionFrame()
    local frame = CreateFrame("Frame", "OxedHubPositionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(200, 140)
    frame:SetPoint("CENTER", UIParent, "CENTER", DEFAULT_ANIMATION_POSITION.x, DEFAULT_ANIMATION_POSITION.y)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(200)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()
    frame.targetAnimId = nil
    frame.onSaveCallback = nil

    -- Main window style: dark, semi-transparent with tooltip border
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

    -- Live animation preview filling the frame (shown only in animation mode)
    local animTex = frame:CreateTexture(nil, "ARTWORK")
    animTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    animTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    animTex:Hide()
    frame.animTex = animTex

    -- Title (above the frame so it never covers the preview)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("BOTTOM", frame, "TOP", 0, 18)
    title:SetText(L["ANIM_DRAG_TO_POS"] or "Drag to Position")
    title:SetTextColor(1, 0.82, 0, 1)
    frame.titleText = title

    -- Instructions
    local instr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instr:SetPoint("BOTTOM", frame, "TOP", 0, 4)
    instr:SetText(L["ANIM_DRAG_TO_MOVE"] or "Drag to move  •  drag the corner to resize")
    instr:SetTextColor(0.7, 0.7, 0.7, 0.9)
    frame.instrText = instr

    -- Crosshair center marker (shown only in plain move-only mode)
    local crossV = frame:CreateTexture(nil, "OVERLAY")
    crossV:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    crossV:SetSize(1, 40)
    crossV:SetPoint("CENTER", frame, "CENTER", 0, 0)
    local crossH = frame:CreateTexture(nil, "OVERLAY")
    crossH:SetColorTexture(0.5, 0.5, 0.5, 0.4)
    crossH:SetSize(40, 1)
    crossH:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.crossV = crossV
    frame.crossH = crossH

    -- Reset button
    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 22)
    resetBtn:SetPoint("TOP", frame, "BOTTOM", -34, -8)
    resetBtn:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
    resetBtn:SetScript("OnClick", function()
        if frame.targetAnimId then
            local anim = OxedHub.db.profile.animations[frame.targetAnimId]
            if anim then
                anim.customPositionX = 0
                anim.customPositionY = 200
            end
        elseif frame.onSaveCallback then
            frame.onSaveCallback(0, 200)
        else
            Animations:ResetPreviewPosition()
        end
        Animations:ApplyPositionFramePosition()
    end)

    -- Close/Done button
    local doneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    doneBtn:SetSize(60, 22)
    doneBtn:SetPoint("TOP", frame, "BOTTOM", 34, -8)
    doneBtn:SetText(L["BTN_DONE"] or "Done")
    doneBtn:SetScript("OnClick", function()
        if frame._previewOnlyMode then
            Animations:HidePreviewOverlay()
            return
        end
        Animations:StopPositionPreview()
        frame:Hide()
        Animations:SaveAnimationPosition(frame)
        Animations:AttachPlayerFrameToTarget()
        if Animations.currentScrollChild then
            Animations:RefreshAnimationList(Animations.currentScrollChild)
        end
    end)

    -- Drag handlers (preview-only mode sets the frame un-movable, so guard it)
    frame:SetScript("OnDragStart", function(self)
        if self._previewOnlyMode or not self:IsMovable() then return end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if self._previewOnlyMode then return end
        Animations:SaveAnimationPosition(self)
        Animations:AttachPlayerFrameToTarget()
    end)

    -- Proportional resize via a bottom-right grip (animation mode only)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(60, 40, 1400, 1000) end
    frame:SetScript("OnSizeChanged", function(self, w)
        if not self.lockAspect or self._adjusting then return end
        self._adjusting = true
        self:SetHeight(w / self.lockAspect)
        self._adjusting = false
        if self.targetAnimId then
            local a = OxedHub.db.profile.animations[self.targetAnimId]
            if a then
                a.width = math.max(8, math.floor((w - 6) / 3 + 0.5))
                a.height = math.max(8, math.floor((w / self.lockAspect - 6) / 3 + 0.5))
            end
        end
    end)
    frame:SetScript("OnHide", function() Animations:StopPositionPreview() end)

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:Hide()
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        if Animations.currentScrollChild then
            Animations:RefreshAnimationList(Animations.currentScrollChild)
        end
    end)
    frame.resizeGrip = grip

    frame.resetBtn = resetBtn
    frame.doneBtn = doneBtn
    self.positionFrame = frame
end

-- Show position frame for a specific animation
function Animations:ShowPositionFrameForAnimation(animId)
    if not self.positionFrame then
        self:CreatePositionFrame()
    end
    if not self.playerFrame then
        self:CreatePlayerFrame()
    end

    local anim = OxedHub.db.profile.animations[animId]
    if not anim then return end

    local frame = self.positionFrame
    frame.targetAnimId = animId
    frame.onSaveCallback = nil

    -- Size the frame to the animation's on-screen size (3x) and lock the aspect
    local dispW = (anim.width or 64) * 3
    local dispH = (anim.height or 64) * 3
    frame.lockAspect = dispW / math.max(1, dispH)
    frame._adjusting = true
    frame:SetSize(math.max(60, dispW + 6), math.max(40, dispH + 6))
    frame._adjusting = false

    -- Animation mode: hide crosshair, show resize grip, play the animation looped
    if frame.crossV then frame.crossV:Hide(); frame.crossH:Hide() end
    if frame.resizeGrip then frame.resizeGrip:Show() end

    local x = anim.customPositionX or 0
    local y = anim.customPositionY or 200
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    self:StartPositionPreview(anim)
    frame:Show()
end

function Animations:ShowPositionFrameCustom(x, y, onSaveCallback)
    if not self.positionFrame then
        self:CreatePositionFrame()
    end
    if not self.playerFrame then
        self:CreatePlayerFrame()
    end

    self.positionFrame.targetAnimId = nil
    self.positionFrame.onSaveCallback = onSaveCallback
    self:_PositionFrameSimpleMode()

    self.positionFrame:ClearAllPoints()
    self.positionFrame:SetPoint("CENTER", UIParent, "CENTER", x or 0, y or 200)

    self:AttachPlayerFrameToTarget()
    self.positionFrame:Show()
end

-- Cooldown progress position frame
local cdPositionFrame = nil
local cdPreviewIcon = nil

function Animations:CreateCooldownPositionFrame()
    local frame = CreateFrame("Frame", "OxedHubCooldownPositionFrame", UIParent, "BackdropTemplate")
    frame:SetSize(200, 140)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.35)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.7)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", frame, "TOP", 0, -12)
    title:SetText(L["ANIM_CD_POSITION"] or "Cooldown Icon Position")
    title:SetTextColor(1, 0.82, 0, 1)

    local instr = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instr:SetPoint("TOP", title, "BOTTOM", 0, -6)
    instr:SetText(L["ANIM_DRAG_CD_ICON"] or "Drag to position the cooldown icon")
    instr:SetTextColor(0.7, 0.7, 0.7, 0.9)

    -- Preview icon in center
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(64, 64)
    icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(136018)
    frame.previewIcon = icon

    -- Cooldown spiral on preview
    local cd = CreateFrame("Cooldown", nil, frame)
    cd:SetSize(64, 64)
    cd:SetPoint("CENTER", frame, "CENTER", 0, 0)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.8)
    cd:SetCooldown(GetTime(), 3)
    cd:Show()
    frame.previewCooldown = cd

    local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 22)
    resetBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 12)
    resetBtn:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
    resetBtn:SetScript("OnClick", function()
        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
            OxedHub.db.profile.settings.cooldownProgressPosition = { x = 0, y = 150 }
        end
        Animations:ApplyCooldownPosition()
    end)

    local doneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    doneBtn:SetSize(60, 22)
    doneBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 12)
    doneBtn:SetText(L["BTN_DONE"] or "Done")
    doneBtn:SetScript("OnClick", function()
        frame:Hide()
        Animations:SaveCooldownPosition()
    end)

    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Animations:SaveCooldownPosition()
    end)

    cdPositionFrame = frame
end

function Animations:SaveCooldownPosition()
    if not cdPositionFrame then return end
    local fx, fy = cdPositionFrame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not fx or not fy or not ux or not uy then return end
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        OxedHub.db.profile.settings.cooldownProgressPosition = {
            x = fx - ux,
            y = fy - uy,
        }
    end
end

function Animations:ApplyCooldownPosition()
    if not cdPositionFrame then return end
    local pos = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and
                OxedHub.db.profile.settings.cooldownProgressPosition
    local x = pos and pos.x or 0
    local y = pos and pos.y or 150
    cdPositionFrame:ClearAllPoints()
    cdPositionFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function Animations:ShowCooldownPositionFrame(spellID)
    if not cdPositionFrame then
        self:CreateCooldownPositionFrame()
    end
    self:ApplyCooldownPosition()
    
    -- Update preview icon based on selected spell
    if cdPositionFrame.previewIcon then
        local iconTexture = 136018 -- Default question mark
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(tonumber(spellID) or spellID)
            if spellInfo and spellInfo.iconID then
                iconTexture = spellInfo.iconID
            end
        end
        cdPositionFrame.previewIcon:SetTexture(iconTexture)
    end

    -- Restart preview cooldown sweep
    if cdPositionFrame.previewCooldown then
        cdPositionFrame.previewCooldown:SetCooldown(GetTime(), 3)
    end
    cdPositionFrame:Show()
end

-- Hidden texture used to test whether a texture file actually exists on disk.
-- SetTexture() to a missing file leaves GetTexture() == nil, which lets us probe.
local _fileTestTex
local function AnimFileExists(path)
    if not _fileTestTex then
        _fileTestTex = UIParent:CreateTexture(nil, "BACKGROUND")
        _fileTestTex:Hide()
    end
    _fileTestTex:SetTexture(nil)
    _fileTestTex:SetTexture(path)
    return _fileTestTex:GetTexture() ~= nil
end

-- Resolve an animation file: a bare filename is searched in OxedHub_CustomMedia first.
-- If not found, it falls back to the default Media/Animations folder. A full path is used as-is.
local function ResolveAnimationPath(filename)
    if not filename or filename == "" then return "" end
    if filename:find("\\") then return filename end  -- Full path provided, use as-is
    local custom = "Interface\\AddOns\\OxedHub_CustomMedia\\" .. filename
    if AnimFileExists(custom) then return custom end
    return "Interface\\AddOns\\OxedHub\\Media\\Animations\\" .. filename
end

-- Show Advanced Animations UI
function Animations:ShowAdvancedUI(parent)
    -- Hide and cleanup existing scroll frame safely
    if self.currentScrollFrame then
        self.currentScrollFrame:Hide()
        self.currentScrollFrame:SetParent(nil)
        self.currentScrollFrame = nil
    end
    if self.currentScrollChild then
        self.currentScrollChild:Hide()
        self.currentScrollChild:SetParent(nil)
        self.currentScrollChild = nil
    end
    
    -- Clear parent completely (children and regions)
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({parent:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end

    -- Cancel active preview ticker if any
    if self.previewTicker then
        self.previewTicker:Cancel()
        self.previewTicker = nil
    end

    local function StylePremiumCard(card, titleText, iconTexture)
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        card:SetBackdropColor(0.04, 0.04, 0.05, 0.65)
        card:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)


        if titleText then
            local icon
            if iconTexture then
                icon = card:CreateTexture(nil, "OVERLAY")
                icon:SetSize(14, 14)
                icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
                icon:SetTexture(iconTexture)
            end

            local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            if icon then
                title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            else
                title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
            end
            title:SetText(titleText)
            title:SetTextColor(1, 0.82, 0, 1)
            card.titleString = title
        end
    end

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    title:SetText(L["ANIM_ADVANCED_ENGINE"] or "Advanced Animation Engine")

    local intro = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    intro:SetWidth(560)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(0.86, 0.82, 0.72, 1)
    intro:SetText(L["ANIM_INTRO_TEXT"] or "Use this page for custom animation imports. Sprite sheets can be TGA or PNG. Load files from |cff99cc99OxedHub_CustomMedia|r (in AddOns folder). If you don't have this folder, you must create it with the exact name. If your source is a GIF, convert it to a sprite sheet first.")

    local urlDialog = CreateFrame("Frame", "OxedHubAdvancedConverterDialog", UIParent, "BackdropTemplate")
    urlDialog:SetSize(460, 100)
    urlDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    urlDialog:SetFrameStrata("DIALOG")
    urlDialog:SetFrameLevel(500)
    urlDialog:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    urlDialog:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    urlDialog:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
    urlDialog:EnableMouse(true)
    urlDialog:SetMovable(true)
    urlDialog:RegisterForDrag("LeftButton")
    urlDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    urlDialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    urlDialog:Hide()

    local dlgLabel = urlDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlgLabel:SetPoint("TOPLEFT", urlDialog, "TOPLEFT", 12, -15)
    dlgLabel:SetText(L["ANIM_CONVERTER_TITLE"] or "|cff00ff00GIF to TGA Converter:|r  Copy the link below and paste it in your browser")
    dlgLabel:SetTextColor(1, 0.9, 0.4, 1)

    local urlBox = CreateFrame("EditBox", nil, urlDialog, "InputBoxTemplate")
    urlBox:SetSize(420, 22)
    urlBox:SetPoint("TOPLEFT", dlgLabel, "BOTTOMLEFT", 4, -10)
    urlBox:SetAutoFocus(false)
    urlBox:SetText("https://customwowaddon.com/en/gif-to-tga-converter")
    urlBox:SetScript("OnShow", function(self) self:SetFocus(); self:HighlightText() end)
    urlBox:SetScript("OnEscapePressed", function() urlDialog:Hide() end)

    local closeBtn = CreateFrame("Button", nil, urlDialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", urlDialog, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() urlDialog:Hide() end)

    -- Copy folder name dialog
    local folderDialog = CreateFrame("Frame", "OxedHubAdvancedFolderDialog", UIParent, "BackdropTemplate")
    folderDialog:SetSize(460, 115)
    folderDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    folderDialog:SetFrameStrata("DIALOG")
    folderDialog:SetFrameLevel(500)
    folderDialog:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    folderDialog:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    folderDialog:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
    folderDialog:EnableMouse(true)
    folderDialog:SetMovable(true)
    folderDialog:RegisterForDrag("LeftButton")
    folderDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    folderDialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    folderDialog:Hide()

    local foldLabel = folderDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    foldLabel:SetPoint("TOPLEFT", folderDialog, "TOPLEFT", 12, -15)
    foldLabel:SetText(L["ANIM_FOLDER_TITLE"] or "|cff00ff00Custom Media Folder:|r Copy the name below and create a new folder\nin the AddOns folder (same location where OxedHub addon is located)")
    foldLabel:SetTextColor(1, 0.9, 0.4, 1)
    foldLabel:SetJustifyH("LEFT")

    local folderBox = CreateFrame("EditBox", nil, folderDialog, "InputBoxTemplate")
    folderBox:SetSize(420, 22)
    folderBox:SetPoint("TOPLEFT", foldLabel, "BOTTOMLEFT", 4, -10)
    folderBox:SetAutoFocus(false)
    folderBox:SetText("OxedHub_CustomMedia")
    folderBox:SetScript("OnShow", function(self) self:SetFocus(); self:HighlightText() end)
    folderBox:SetScript("OnEscapePressed", function() folderDialog:Hide() end)

    local foldCloseBtn = CreateFrame("Button", nil, folderDialog, "UIPanelCloseButton")
    foldCloseBtn:SetPoint("TOPRIGHT", folderDialog, "TOPRIGHT", 2, 2)
    foldCloseBtn:SetScript("OnClick", function() folderDialog:Hide() end)

    -- ── Right column: "Sprite Sheet" controls card (top) + preview card (below) ──
    local controlsCard = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    controlsCard:SetWidth(360)
    controlsCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -15, -45)
    controlsCard:SetHeight(200)
    StylePremiumCard(controlsCard, L["ANIM_SPRITE_SHEET"] or "Sprite Sheet", "Interface\\Icons\\INV_Misc_FilmStrip")

    local converterBtn = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")
    converterBtn:SetSize(158, 20)
    converterBtn:SetPoint("TOPLEFT", controlsCard, "TOPLEFT", 12, -30)
    converterBtn:SetText(L["ANIM_GET_CONVERTER"] or "Get Converter")
    converterBtn:SetNormalFontObject("GameFontNormalSmall")
    converterBtn:SetScript("OnClick", function()
        if urlDialog:IsShown() then
            urlDialog:Hide()
        else
            folderDialog:Hide()
            urlDialog:Show()
            urlBox:SetFocus()
            urlBox:HighlightText()
        end
    end)

    local folderBtn = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")
    folderBtn:SetSize(173, 20)
    folderBtn:SetPoint("LEFT", converterBtn, "RIGHT", 10, 0)
    folderBtn:SetText(L["ANIM_GET_FOLDER"] or "Get Folder Name")
    folderBtn:SetNormalFontObject("GameFontNormalSmall")
    folderBtn:SetScript("OnClick", function()
        if folderDialog:IsShown() then
            folderDialog:Hide()
        else
            urlDialog:Hide()
            folderDialog:Show()
            folderBox:SetFocus()
            folderBox:HighlightText()
        end
    end)

    local fileLabel = controlsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fileLabel:SetPoint("TOPLEFT", converterBtn, "BOTTOMLEFT", 0, -10)
    fileLabel:SetText(L["ANIM_FILE_PATH"] or "TGA / PNG File Path:")

    -- Info icon with tooltip
    local fileInfoIcon = CreateFrame("Button", nil, controlsCard)
    fileInfoIcon:SetSize(16, 16)
    fileInfoIcon:SetPoint("LEFT", fileLabel, "RIGHT", 6, 0)
    fileInfoIcon:SetNormalTexture("Interface\\Common\\help-i")
    fileInfoIcon:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    fileInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ANIM_FILE_PATH_TT_TITLE"] or "TGA / PNG File Path")
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_1"] or "You can enter just the filename (with or without .png/.tga/.gif extension).", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_2"] or "Place your files in:", 0.9, 0.82, 0.4, true)
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_3"] or "• |cff99cc99OxedHub_CustomMedia|r (in AddOns folder)", 1, 1, 1, true)
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_4"] or "If you don't have this folder, you must create it with the exact name: |cff99cc99OxedHub_CustomMedia|r", 1, 0.82, 0, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_5"] or "Use the |cff00ff00Get Converter|r to convert GIF to sprite sheets.", 0.9, 0.82, 0.4, true)
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_6"] or "If you add a new file, use |cffff9900/reload|r to refresh WoW's texture cache.", 0.9, 0.82, 0.4, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ANIM_FILE_PATH_TT_7"] or "|cff99ff99Custom animations & sounds in OxedHub_CustomMedia won't be deleted when updating from Curse Forge.|r", 0.5, 1, 0.5, true)
        GameTooltip:Show()
    end)
    fileInfoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local fileEdit = CreateFrame("EditBox", nil, controlsCard, "InputBoxTemplate")
    fileEdit:SetSize(320, 20)
    fileEdit:SetPoint("TOPLEFT", fileLabel, "BOTTOMLEFT", 5, -4)
    fileEdit:SetAutoFocus(false)

    local colsLabel = controlsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colsLabel:SetPoint("TOPLEFT", fileEdit, "BOTTOMLEFT", -5, -10)
    colsLabel:SetText(L["ANIM_COLS"] or "Cols:")
    local colsEdit = CreateFrame("EditBox", nil, controlsCard, "InputBoxTemplate")
    colsEdit:SetSize(30, 20)
    colsEdit:SetPoint("LEFT", colsLabel, "RIGHT", 5, 0)
    colsEdit:SetNumeric(true)
    colsEdit:SetText("5")

    local rowsLabel = controlsCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowsLabel:SetPoint("LEFT", colsEdit, "RIGHT", 15, 0)
    rowsLabel:SetText(L["ANIM_ROWS"] or "Rows:")
    local rowsEdit = CreateFrame("EditBox", nil, controlsCard, "InputBoxTemplate")
    rowsEdit:SetSize(30, 20)
    rowsEdit:SetPoint("LEFT", rowsLabel, "RIGHT", 5, 0)
    rowsEdit:SetNumeric(true)
    rowsEdit:SetText("5")

    local loadBtn = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")
    loadBtn:SetSize(130, 22)
    loadBtn:SetPoint("TOPLEFT", colsLabel, "BOTTOMLEFT", 0, -12)
    loadBtn:SetText(L["ANIM_LOAD_GRID"] or "Load Grid")

    -- Auto-detect grid from converter filenames like "name_col-11_row-11.png".
    -- Only fills when the pattern is present, so manual entries are left alone.
    fileEdit:SetScript("OnTextChanged", function(self)
        local name = self:GetText() or ""
        local c = name:match("[cC][oO][lL][sS]?[-_]?(%d+)")
        local r = name:match("[rR][oO][wW][sS]?[-_]?(%d+)")
        if c then colsEdit:SetText(c) end
        if r then rowsEdit:SetText(r) end
    end)

    -- Right Panel: Animation Sequence Preview, Settings & Timeline (below controls)
    local previewBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    previewBox:SetWidth(360)
    previewBox:SetPoint("TOPRIGHT", controlsCard, "BOTTOMRIGHT", 0, -10)
    previewBox:SetPoint("BOTTOM", parent, "BOTTOM", 0, 18)
    StylePremiumCard(previewBox, L["ANIM_PREVIEW_TITLE"] or "Sequence Preview, Settings & Timeline", "Interface\\Icons\\INV_Misc_FilmStrip")

    -- Canvas Area (Grid) - fills the entire left side
    local canvas = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -12)
    canvas:SetPoint("RIGHT", controlsCard, "LEFT", -15, 0)
    canvas:SetPoint("BOTTOM", parent, "BOTTOM", 0, 18)
    StylePremiumCard(canvas)

    local cellButtons = {}
    local selectedFrames = {}

    -- Main Preview Frame (200x150 - Stacked Centered)
    local mainPreview = CreateFrame("Frame", nil, previewBox, "BackdropTemplate")
    mainPreview:SetSize(200, 150)
    mainPreview:SetPoint("TOPLEFT", previewBox, "TOPLEFT", 30, -35)
    mainPreview:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    mainPreview:SetBackdropColor(0, 0, 0, 0.95)
    mainPreview:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
    mainPreview:SetClipsChildren(true)

    local previewTexture = mainPreview:CreateTexture(nil, "ARTWORK")
    previewTexture:SetPoint("CENTER", mainPreview, "CENTER")

    -- Scrollable Timeline Container (222x34 - Original Size)
    local timelineScrollFrame = CreateFrame("ScrollFrame", nil, previewBox)
    timelineScrollFrame:SetSize(222, 34)
    timelineScrollFrame:SetPoint("TOPLEFT", mainPreview, "BOTTOMLEFT", -11, -15)
    timelineScrollFrame:EnableMouseWheel(true)

    local timelineScrollChild = CreateFrame("Frame", nil, timelineScrollFrame)
    timelineScrollChild:SetSize(222, 34)
    timelineScrollFrame:SetScrollChild(timelineScrollChild)

    -- Animation Settings (Stacked below timeline scroll frame)
    -- Name
    local nmLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nmLabel:SetPoint("TOPLEFT", timelineScrollFrame, "BOTTOMLEFT", 15, -14)
    nmLabel:SetText(L["ANIM_NAME"] or "Name:")
    local nameEdit = CreateFrame("EditBox", nil, previewBox, "InputBoxTemplate")
    nameEdit:SetSize(140, 20)
    nameEdit:SetPoint("LEFT", nmLabel, "RIGHT", 10, 0)
    nameEdit:SetAutoFocus(false)

    -- Width & Height (hidden - auto-set by aspect ratio presets)
    local wLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wLabel:SetPoint("TOPLEFT", timelineScrollFrame, "BOTTOMLEFT", 15, -14)
    wLabel:SetText(L["ANIM_WIDTH"] or "Width:")
    wLabel:Hide()
    local wEdit = CreateFrame("EditBox", nil, previewBox, "InputBoxTemplate")
    wEdit:SetSize(40, 20)
    wEdit:SetPoint("LEFT", wLabel, "RIGHT", 10, 0)
    wEdit:SetNumeric(true)
    wEdit:SetText("64")
    wEdit:Hide()

    local hLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hLabel:SetPoint("LEFT", wEdit, "RIGHT", 15, 0)
    hLabel:SetText(L["ANIM_HEIGHT"] or "Height:")
    hLabel:Hide()
    local hEdit = CreateFrame("EditBox", nil, previewBox, "InputBoxTemplate")
    hEdit:SetSize(40, 20)
    hEdit:SetPoint("LEFT", hLabel, "RIGHT", 10, 0)
    hEdit:SetNumeric(true)
    hEdit:SetText("64")
    hEdit:Hide()

    -- Forward-declare SizePreviewTexture and previewState so aspect buttons can reference them
    local SizePreviewTexture
    local previewState

    -- Aspect ratio presets (moved up to replace Width/Height row)
    local aspectLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    aspectLabel:SetPoint("TOPLEFT", timelineScrollFrame, "BOTTOMLEFT", 15, -14)
    aspectLabel:SetText(L["ANIM_ASPECT"] or "Aspect:")
    local aspectPresets = {
        { label = "1:1",  w = 96,  h = 96 },
        { label = "16:9", w = 128, h = 72 },
        { label = "9:16", w = 72,  h = 128 },
    }
    local lastAspect = aspectLabel
    for _, ap in ipairs(aspectPresets) do
        local b = CreateFrame("Button", nil, previewBox, "UIPanelButtonTemplate")
        b:SetSize(44, 18)
        b:SetPoint("LEFT", lastAspect, "RIGHT", 6, 0)
        b:SetText(ap.label)
        b:SetNormalFontObject("GameFontNormalSmall")
        b:SetScript("OnClick", function()
            wEdit:SetText(tostring(ap.w))
            hEdit:SetText(tostring(ap.h))
            SizePreviewTexture(previewState.scale)
        end)
        lastAspect = b
    end

    -- Info icon explaining size adjustment
    local aspectInfoIcon = CreateFrame("Button", nil, previewBox)
    aspectInfoIcon:SetSize(16, 16)
    aspectInfoIcon:SetPoint("LEFT", lastAspect, "RIGHT", 8, 0)
    aspectInfoIcon:SetNormalTexture("Interface\\Common\\help-i")
    aspectInfoIcon:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    aspectInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Aspect Ratio")
        GameTooltip:AddLine("Choose the aspect ratio that matches your sprite sheet frames.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("• 1:1 — Square frames (most common)", 1, 1, 1, true)
        GameTooltip:AddLine("• 16:9 — Widescreen frames", 1, 1, 1, true)
        GameTooltip:AddLine("• 9:16 — Tall / portrait frames", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You can change the size of your animation when you\nposition it on the screen using Move / Scale.", 0.5, 1, 0.5, true)
        GameTooltip:Show()
    end)
    aspectInfoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- FPS & Loop
    local fpsLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fpsLabel:SetPoint("TOPLEFT", aspectLabel, "BOTTOMLEFT", 0, -10)
    fpsLabel:SetText(L["ANIM_FPS"] or "FPS:")
    local fpsEdit = CreateFrame("EditBox", nil, previewBox, "InputBoxTemplate")
    fpsEdit:SetSize(40, 20)
    fpsEdit:SetPoint("LEFT", fpsLabel, "RIGHT", 10, 0)
    fpsEdit:SetNumeric(true)
    fpsEdit:SetText("24")

    local loopLabel = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loopLabel:SetPoint("LEFT", fpsEdit, "RIGHT", 15, 0)
    loopLabel:SetText(L["ANIM_LOOP"] or "Loop:")
    local loopEdit = CreateFrame("EditBox", nil, previewBox, "InputBoxTemplate")
    loopEdit:SetSize(40, 20)
    loopEdit:SetPoint("LEFT", loopLabel, "RIGHT", 10, 0)
    loopEdit:SetNumeric(true)
    loopEdit:SetText("1")

    local function GetSortedSelection()
        local seq = {}
        for idx in pairs(selectedFrames) do table.insert(seq, idx) end
        table.sort(seq)
        return seq
    end

    -- Save Animation button (under Animation Settings)
    local saveBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    saveBtn:SetSize(120, 22)
    saveBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -15, -15)
    saveBtn:SetText(L["ANIM_SAVE"] or "Save Animation")

    -- Name field placed just left of the Save Animation button
    nameEdit:ClearAllPoints()
    nameEdit:SetWidth(170)
    nameEdit:SetPoint("RIGHT", saveBtn, "LEFT", -14, 0)
    nmLabel:ClearAllPoints()
    nmLabel:SetPoint("RIGHT", nameEdit, "LEFT", -6, 0)
    saveBtn:SetScript("OnClick", function()
        local seq = GetSortedSelection()
        if #seq == 0 then print("OxedHub: Select at least one frame!") return end
        local nm = nameEdit:GetText()
        if nm == "" then print("OxedHub: Enter a name!") return end
        
        local path = fileEdit:GetText()
        if not path:lower():find("%.tga$") and not path:lower():find("%.png$") then path = path .. ".tga" end
        
        local data = {
            id = Animations.saveTargetId,
            name = nm,
            filename = path,
            width = tonumber(wEdit:GetText()) or 64,
            height = tonumber(hEdit:GetText()) or 64,
            frameCount = tonumber(colsEdit:GetText()) * tonumber(rowsEdit:GetText()),
            columns = tonumber(colsEdit:GetText()),
            rows = tonumber(rowsEdit:GetText()),
            fps = tonumber(fpsEdit:GetText()) or 24,
            loopCount = tonumber(loopEdit:GetText()) or 1,
            playSequence = seq,
        }
        Animations:AddAnimation(data)
        Animations.saveTargetId = nil
        print("OxedHub: Saved advanced animation: " .. nm)
        nameEdit:SetText("")
        for _, btn in ipairs(cellButtons) do
            btn.selBorder:Hide()
            btn.check:Hide()
        end
        selectedFrames = {}
    end)

    -- Info Card
    local infoBox = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    infoBox:SetHeight(55)
    infoBox:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 15, 15)
    infoBox:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -15, 15)
    StylePremiumCard(infoBox)
    infoBox:EnableMouse(true)
    infoBox:SetScript("OnMouseDown", function()
        if urlDialog:IsShown() then
            urlDialog:Hide()
        else
            urlDialog:Show()
            urlBox:SetFocus()
            urlBox:HighlightText()
        end
    end)

    local helpIcon = infoBox:CreateTexture(nil, "ARTWORK")
    helpIcon:SetSize(24, 24)
    helpIcon:SetPoint("LEFT", infoBox, "LEFT", 14, 0)
    helpIcon:SetTexture("Interface\\common\\help-i")

    local infoTitle = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoTitle:SetPoint("TOPLEFT", helpIcon, "TOPRIGHT", 10, 2)
    infoTitle:SetText(L["ANIM_INFO_TITLE"] or "Help & Instructions:")
    infoTitle:SetTextColor(1, 0.82, 0, 1)

    local infoText = infoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoTitle, "BOTTOMLEFT", 0, -2)
    infoText:SetPoint("RIGHT", infoBox, "RIGHT", -15, 0)
    infoText:SetJustifyH("LEFT")
    infoText:SetText(L["ANIM_INFO_TEXT"] or "1. Convert GIF to a TGA or PNG sprite sheet [|cff00ff00Get Converter|r]   2. Create |cff99cc99OxedHub_CustomMedia|r folder in AddOns (exact name) and place your file there.   3. Enter filename, dimensions, then Load.   4. Select frames.   5. Save at top-right.")

    -- Help & Instructions hidden for now (kept in code; remove this line to show it again)
    infoBox:Hide()



    local timelineButtons = {}
    previewState = {
        isPlaying = false,
        currentIndex = 0,
        loop = true,
        scale = "Fit",
    }

    local function SetTextureToFrame(texture, frameIndex, cols, rows)
        if not texture then return end
        cols = cols or 5
        rows = rows or 5
        if cols < 1 then cols = 1 end
        if rows < 1 then rows = 1 end

        local row = math_floor(frameIndex / cols)
        local col = frameIndex % cols

        local left = col / cols
        local right = (col + 1) / cols
        local top = row / rows
        local bottom = (row + 1) / rows

        texture:SetTexCoord(left, right, top, bottom)
    end

    local function UpdateTimelineHighlight(stepIndex)
        local seq = GetSortedSelection()
        for i, btn in ipairs(timelineButtons) do
            if btn:IsShown() then
                if (i - 1) == stepIndex then
                    btn.highlight:Show()
                    btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                else
                    btn.highlight:Hide()
                    btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)
                end
            end
        end

        -- Scroll to center the highlighted frame
        if stepIndex >= 0 and stepIndex < #seq then
            local btnX = stepIndex * 38
            local scrollFrameWidth = 222
            local childWidth = math.max(222, #seq * 38 - 6)
            local maxScroll = math.max(0, childWidth - scrollFrameWidth)
            
            local targetScroll = btnX - (scrollFrameWidth / 2) + 16
            targetScroll = math.max(0, math.min(targetScroll, maxScroll))
            timelineScrollFrame:SetHorizontalScroll(targetScroll)
        end
    end

    timelineScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local seq = GetSortedSelection()
        local currentScroll = self:GetHorizontalScroll()
        local childWidth = math.max(222, #seq * 38 - 6)
        local maxScroll = math.max(0, childWidth - 222)
        local newScroll = currentScroll - (delta * 20)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetHorizontalScroll(newScroll)
    end)

    local function UpdateTimeline()
        for _, btn in ipairs(timelineButtons) do btn:Hide() end
        
        local seq = GetSortedSelection()
        local path = fileEdit:GetText()
        if path == "" then return end
        if not path:lower():find("%.tga$") and not path:lower():find("%.png$") then path = path .. ".tga" end
        local fullPath = ResolveAnimationPath(path)
        
        local c = tonumber(colsEdit:GetText()) or 5
        local r = tonumber(rowsEdit:GetText()) or 5

        local totalWidth = math.max(222, #seq * 38 - 6)
        timelineScrollChild:SetWidth(totalWidth)
        
        for i = 1, #seq do
            local frameIndex = seq[i]
            local btn = timelineButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, timelineScrollChild, "BackdropTemplate")
                btn:SetSize(32, 32)
                btn:SetBackdrop({
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                })
                btn:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.8)
                
                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                btn.texture = tex
                
                local hl = btn:CreateTexture(nil, "OVERLAY")
                hl:SetColorTexture(1, 0.82, 0, 0.2)
                hl:SetAllPoints()
                hl:Hide()
                btn.highlight = hl
                
                timelineButtons[i] = btn
            end
            
            btn:SetPoint("LEFT", timelineScrollChild, "LEFT", (i - 1) * 38, 0)
            btn.texture:SetTexture(fullPath)
            SetTextureToFrame(btn.texture, frameIndex, c, r)
            btn:SetScript("OnClick", function()
                if previewState.isPlaying then
                    if self.previewTicker then
                        self.previewTicker:Cancel()
                        self.previewTicker = nil
                    end
                    previewState.isPlaying = false
                end
                previewState.currentIndex = i - 1
                local fIdx = seq[i]
                previewTexture:SetTexture(fullPath)
                SetTextureToFrame(previewTexture, fIdx, c, r)
                UpdateTimelineHighlight(i - 1)
            end)
            btn:Show()
        end
    end

    local function PlayPreviewFrame(stepIndex)
        local seq = GetSortedSelection()
        if #seq == 0 then
            previewTexture:SetTexture(nil)
            UpdateTimelineHighlight(-1)
            return
        end
        if stepIndex < 0 then
            stepIndex = #seq - 1
        elseif stepIndex >= #seq then
            if previewState.loop then
                stepIndex = 0
            else
                -- Stop playback
                previewState.isPlaying = false
                if self.previewTicker then
                    self.previewTicker:Cancel()
                    self.previewTicker = nil
                end
                return
            end
        end
        previewState.currentIndex = stepIndex
        local frameIndex = seq[stepIndex + 1]
        
        local path = fileEdit:GetText()
        if path ~= "" then
            if not path:lower():find("%.tga$") and not path:lower():find("%.png$") then path = path .. ".tga" end
            local fullPath = ResolveAnimationPath(path)
            previewTexture:SetTexture(fullPath)

            local c = tonumber(colsEdit:GetText()) or 5
            local r = tonumber(rowsEdit:GetText()) or 5
            SetTextureToFrame(previewTexture, frameIndex, c, r)
        else
            previewTexture:SetTexture(nil)
        end
        
        UpdateTimelineHighlight(stepIndex)
    end

    local function StartPreviewPlayback()
        if previewState.isPlaying then return end
        local seq = GetSortedSelection()
        if #seq == 0 then return end
        
        previewState.isPlaying = true
        local fps = tonumber(fpsEdit:GetText()) or 24
        if fps <= 0 then fps = 24 end
        
        self.previewTicker = C_Timer.NewTicker(1 / fps, function()
            PlayPreviewFrame(previewState.currentIndex + 1)
        end)
    end

    local function StopPreviewPlayback()
        previewState.isPlaying = false
        if self.previewTicker then
            self.previewTicker:Cancel()
            self.previewTicker = nil
        end
    end


    -- Draw Grid function
    local function DrawGrid()
        for _, btn in ipairs(cellButtons) do btn:Hide() end
        cellButtons = {}
        selectedFrames = {}
        
        local path = fileEdit:GetText()
        if path == "" then return end
        
        if not path:lower():find("%.tga$") and not path:lower():find("%.png$") then path = path .. ".tga" end
        local fullPath = ResolveAnimationPath(path)

        local c = tonumber(colsEdit:GetText()) or 1
        local r = tonumber(rowsEdit:GetText()) or 1
        local canvasW, canvasH = canvas:GetWidth() - 16, canvas:GetHeight() - 16 -- 8px padding
        
        local spacing = 4
        local btnW = (canvasW - (c - 1) * spacing) / c
        local btnH = (canvasH - (r - 1) * spacing) / r
        
        for row=0, r-1 do
            for col=0, c-1 do
                local index = row * c + col
                local btn = CreateFrame("Button", nil, canvas, "BackdropTemplate")
                btn:SetSize(btnW, btnH)
                btn:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * (btnW + spacing) + 8, -row * (btnH + spacing) - 8)
                
                local tex = btn:CreateTexture(nil, "BACKGROUND")
                tex:SetAllPoints()
                tex:SetTexture(fullPath)
                SetTextureToFrame(tex, index, c, r)
                btn.previewTex = tex
                
                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetColorTexture(1, 1, 1, 0.15)
                hl:SetAllPoints()
                
                local selBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
                selBorder:SetAllPoints()
                selBorder:SetBackdrop({
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 2,
                })
                selBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
                selBorder:Hide()
                btn.selBorder = selBorder
                
                local check = btn:CreateTexture(nil, "OVERLAY")
                check:SetSize(12, 12)
                check:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
                check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                check:Hide()
                btn.check = check
                
                local idxText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                idxText:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
                idxText:SetText(index + 1)
                idxText:SetTextColor(1, 1, 1, 0.8)
                
                selectedFrames[index] = true
                selBorder:Show()
                check:Show()
                
                btn:SetScript("OnClick", function()
                    if selectedFrames[index] then
                        selectedFrames[index] = nil
                        selBorder:Hide()
                        check:Hide()
                    else
                        selectedFrames[index] = true
                        selBorder:Show()
                        check:Show()
                    end
                    UpdateTimeline()
                    PlayPreviewFrame(0)
                end)
                
                table.insert(cellButtons, btn)
            end
        end
        
        UpdateTimeline()
        PlayPreviewFrame(0)
    end

    loadBtn:SetScript("OnClick", DrawGrid)

    local selectAllBtn = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")
    selectAllBtn:SetSize(101, 20)
    selectAllBtn:SetPoint("LEFT", loadBtn, "RIGHT", 8, 0)
    selectAllBtn:SetText(L["ANIM_SELECT_ALL"] or "Select All")
    selectAllBtn:SetScript("OnClick", function()
        for i, btn in ipairs(cellButtons) do
            local index = i - 1
            selectedFrames[index] = true
            btn.selBorder:Show()
            btn.check:Show()
        end
        UpdateTimeline()
        PlayPreviewFrame(0)
    end)

    local unselectAllBtn = CreateFrame("Button", nil, controlsCard, "UIPanelButtonTemplate")
    unselectAllBtn:SetSize(101, 20)
    unselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 8, 0)
    unselectAllBtn:SetText(L["ANIM_CLEAR_ALL"] or "Clear All")
    unselectAllBtn:SetScript("OnClick", function()
        for i, btn in ipairs(cellButtons) do
            local index = i - 1
            selectedFrames[index] = nil
            btn.selBorder:Hide()
            btn.check:Hide()
        end
        UpdateTimeline()
        PlayPreviewFrame(0)
    end)

    local loopCheck = CreateFrame("CheckButton", nil, controlsCard, "UICheckButtonTemplate")
    loopCheck:SetPoint("TOPLEFT", loadBtn, "BOTTOMLEFT", 0, -8)
    loopCheck:SetSize(22, 22)
    loopCheck:SetChecked(true)
    loopCheck:SetScript("OnClick", function(self)
        previewState.loop = self:GetChecked()
    end)

    local loopCheckText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loopCheckText:SetPoint("LEFT", loopCheck, "RIGHT", 4, 0)
    loopCheckText:SetText(L["ANIM_LOOP_SEQUENCE"] or "Loop Sequence")
    loopCheckText:SetTextColor(0.9, 0.9, 0.9)

    -- Playback media controls
    -- Playback controls stacked in a column to the RIGHT of the preview window
    local playBtnMedia = CreateFrame("Button", nil, previewBox, "UIPanelButtonTemplate")
    playBtnMedia:SetSize(64, 22)
    playBtnMedia:SetPoint("TOPLEFT", mainPreview, "TOPRIGHT", 14, -2)
    playBtnMedia:SetText(L["ANIM_PLAY"] or "Play")
    playBtnMedia:SetScript("OnClick", StartPreviewPlayback)

    local stopBtnMedia = CreateFrame("Button", nil, previewBox, "UIPanelButtonTemplate")
    stopBtnMedia:SetSize(64, 22)
    stopBtnMedia:SetPoint("TOPLEFT", playBtnMedia, "BOTTOMLEFT", 0, -6)
    stopBtnMedia:SetText(L["ANIM_STOP"] or "Stop")
    stopBtnMedia:SetScript("OnClick", function()
        StopPreviewPlayback()
        PlayPreviewFrame(0)
    end)

    local prevBtnMedia = CreateFrame("Button", nil, previewBox, "UIPanelButtonTemplate")
    prevBtnMedia:SetSize(30, 22)
    prevBtnMedia:SetPoint("TOPLEFT", stopBtnMedia, "BOTTOMLEFT", 0, -6)
    prevBtnMedia:SetText("<<")
    prevBtnMedia:SetScript("OnClick", function()
        StopPreviewPlayback()
        PlayPreviewFrame(previewState.currentIndex - 1)
    end)

    local nextBtnMedia = CreateFrame("Button", nil, previewBox, "UIPanelButtonTemplate")
    nextBtnMedia:SetSize(30, 22)
    nextBtnMedia:SetPoint("LEFT", prevBtnMedia, "RIGHT", 4, 0)
    nextBtnMedia:SetText(">>")
    nextBtnMedia:SetScript("OnClick", function()
        StopPreviewPlayback()
        PlayPreviewFrame(previewState.currentIndex + 1)
    end)

    -- Shared helper: size the preview texture for the given scale + current W/H
    SizePreviewTexture = function(sc)
        sc = sc or previewState.scale or "Fit"
        local w = tonumber(wEdit:GetText()) or 64
        local h = tonumber(hEdit:GetText()) or 64
        if w < 1 then w = 1 end
        if h < 1 then h = 1 end
        if sc == "1x" then
            previewTexture:SetSize(w, h)
        elseif sc == "2x" then
            previewTexture:SetSize(w * 2, h * 2)
        elseif sc == "4x" then
            previewTexture:SetSize(w * 4, h * 4)
        else
            local scale = math.min(200 / w, 150 / h)
            previewTexture:SetSize(w * scale, h * scale)
        end
    end

    -- Scale controls (under the playback buttons on the right, no label)
    local scaleButtons = {}
    local scales = { "1x", "2x", "4x", "Fit" }
    local lastBtn = nil

    for i, sc in ipairs(scales) do
        local btn = CreateFrame("Button", nil, previewBox)
        btn:SetSize(24, 16)
        if i == 1 then
            btn:SetPoint("TOPLEFT", nextBtnMedia, "BOTTOMLEFT", -40, -12)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", 6, 0)
        end

        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetAllPoints()
        text:SetText(sc)
        btn.text = text

        btn:SetScript("OnClick", function()
            previewState.scale = sc
            for _, b in ipairs(scaleButtons) do
                b.text:SetTextColor(0.6, 0.6, 0.6)
            end
            text:SetTextColor(1, 0.82, 0)
            SizePreviewTexture(sc)
        end)

        table.insert(scaleButtons, btn)
        lastBtn = btn
    end

    -- (Aspect ratio presets moved up to the settings area above)

    -- Default Fit selection
    scaleButtons[4]:Click()

    -- Populate from editTarget if present
    if Animations.editTarget then
        local editData = Animations.editTarget
        Animations.saveTargetId = Animations.editTargetId
        
        local path = editData.tgaPath or ""
        local filename = path:match("([^/\\]+)$") or path
        
        fileEdit:SetText(filename)
        colsEdit:SetText(tostring(editData.columns or 5))
        rowsEdit:SetText(tostring(editData.rows or 5))
        
        nameEdit:SetText(editData.name or "")
        wEdit:SetText(tostring(editData.width or 64))
        hEdit:SetText(tostring(editData.height or 64))
        fpsEdit:SetText(tostring(editData.fps or 24))
        loopEdit:SetText(tostring(editData.loopCount or 1))
        
        DrawGrid()
        
        if editData.playSequence then
            for k in pairs(selectedFrames) do selectedFrames[k] = nil end
            for _, btn in ipairs(cellButtons) do
                btn.selBorder:Hide()
                btn.check:Hide()
            end

            for _, idx in ipairs(editData.playSequence) do
                selectedFrames[idx] = true
                local btn = cellButtons[idx + 1]
                if btn then
                    btn.selBorder:Show()
                    btn.check:Show()
                end
            end
        end
        
        UpdateTimeline()
        PlayPreviewFrame(0)
        
        Animations.editTarget = nil
        Animations.editTargetId = nil
    else
        Animations.saveTargetId = nil
    end
end

-- Show Animations UI
function Animations:ShowUI(parent)
    -- Hide and cleanup existing scroll frame safely
    if self.currentScrollFrame then
        self.currentScrollFrame:Hide()
        self.currentScrollFrame:SetParent(nil)
        self.currentScrollFrame = nil
    end
    if self.currentScrollChild then
        self.currentScrollChild:Hide()
        self.currentScrollChild:SetParent(nil)
        self.currentScrollChild = nil
    end
    
    -- Clear parent completely (children and regions)
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({parent:GetRegions()}) do
        region:Hide()
        region:SetParent(nil)
    end
    
    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    title:SetText(L["ANIM_CUSTOM_TITLE"] or "Custom Animations")
    
    -- Instructions
    local instructions = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    instructions:SetTextColor(0.86, 0.82, 0.72, 1)
    instructions:SetText(L["ANIM_CUSTOM_DESC"] or "Manage your animation library here. Use Add Animations for custom sprite-sheet setup.")

    -- URL copy dialog (created once, reused)
    local urlDialog = CreateFrame("Frame", "OxedHubConverterDialog", UIParent, "BackdropTemplate")
    urlDialog:SetSize(460, 100)
    urlDialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    urlDialog:SetFrameStrata("DIALOG")
    urlDialog:SetFrameLevel(500)
    urlDialog:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    urlDialog:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
    urlDialog:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
    urlDialog:EnableMouse(true)
    urlDialog:SetMovable(true)
    urlDialog:RegisterForDrag("LeftButton")
    urlDialog:SetScript("OnDragStart", function(self) self:StartMoving() end)
    urlDialog:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    urlDialog:Hide()

    local dlgLabel = urlDialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dlgLabel:SetPoint("TOPLEFT", urlDialog, "TOPLEFT", 12, -15)
    dlgLabel:SetText(L["ANIM_CONVERTER_TITLE"] or "|cff00ff00GIF to TGA Converter:|r  Copy the link below and paste it in your browser")
    dlgLabel:SetTextColor(1, 0.9, 0.4, 1)

    local urlBox = CreateFrame("EditBox", nil, urlDialog, "InputBoxTemplate")
    urlBox:SetSize(420, 22)
    urlBox:SetPoint("TOPLEFT", dlgLabel, "BOTTOMLEFT", 4, -10)
    urlBox:SetAutoFocus(false)
    urlBox:SetText("https://customwowaddon.com/en/gif-to-tga-converter")
    urlBox:SetScript("OnShow",        function(self) self:SetFocus(); self:HighlightText() end)
    urlBox:SetScript("OnEscapePressed", function() urlDialog:Hide() end)

    local closeBtn = CreateFrame("Button", nil, urlDialog, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", urlDialog, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() urlDialog:Hide() end)

    -- Player position button
    local posBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    posBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
    posBtn:SetSize(120, 25)
    posBtn:SetText(L["ANIM_POS_FRAME"] or "Position Frame")
    posBtn:SetScript("OnClick", function()
        self:ShowPlayerFrame()
    end)
    
    -- Add Animation inline form (Soundie MVP style)
    local formFrame = CreateFrame("Frame", nil, parent)
    formFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -65)
    formFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -65)
    formFrame:SetHeight(65)

    -- Filter dropdown only (Add New Animation form removed)
    local filterDropdown = CreateFrame("DropdownButton", nil, formFrame, "WowStyle1DropdownTemplate")
    filterDropdown:SetPoint("TOPLEFT", formFrame, "TOPLEFT", 0, 0)
    filterDropdown:SetSize(160, 26)

    local filterOptions = {
        { key = "all",   name = L["ANIM_FILTER_ALL"] or "Show All" },
        { key = "oxed",  name = L["ANIM_FILTER_GEN"] or "General" },
        { key = "male",  name = L["ANIM_FILTER_MALE"] or "Male" },
        { key = "female",name = L["ANIM_FILTER_FEMALE"] or "Female" },
        { key = "users", name = L["ANIM_FILTER_USERS"] or "Users" },
    }

    local function IsFilterSelected(key)
        return (Animations.currentFilter or "all") == key
    end

    local function ApplyFilter(key, name)
        Animations.currentFilter = key
        filterDropdown:OverrideText(name)
        if Animations.currentScrollChild then
            Animations:RefreshAnimationList(Animations.currentScrollChild)
        end
    end

    filterDropdown:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(filterOptions) do
            rootDescription:CreateRadio(
                entry.name,
                function(k) return IsFilterSelected(k) end,
                function()
                    ApplyFilter(entry.key, entry.name)
                end,
                entry.key
            )
        end
    end)

    local currentFilter = Animations.currentFilter or "all"
    for _, entry in ipairs(filterOptions) do
        if entry.key == currentFilter then
            filterDropdown:OverrideText(entry.name)
            break
        end
    end

    Animations.filterDropdown = filterDropdown


    -- Scroll frame for animation list
    local scrollFrame = CreateFrame("ScrollFrame", "OxedHubAnimsScrollFrame" .. tostring(GetTime()), parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -95)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store references for cleanup
    self.currentScrollFrame = scrollFrame
    self.currentScrollChild = scrollChild
    
    self:RefreshAnimationList(scrollChild)
end

-- Determine animation category for filtering
function Animations:GetAnimationCategory(id, anim)
    if anim.isBuiltIn then
        local path = anim.tgaPath or ""
        if path:find("Oxed%-male%-") or path:find("oxed%-male%-") then
            return "male"
        elseif path:find("Oxed%-female%-") or path:find("oxed%-female%-") then
            return "female"
        else
            return "oxed"
        end
    end
    return "users"
end

-- Refresh animation list
function Animations:RefreshAnimationList(parent)
    -- Clear existing
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local yOffset = -5
    local anims = OxedHub.db.profile.animations or {}
    local searchText = OxedHub.globalSearchText or ""
    local filter = Animations.currentFilter or "all"
    local matchCount = 0

    for id, anim in pairs(anims) do
        local animName = (anim.name or id):lower()
        local passesSearch = (searchText == "" or string.find(animName, searchText, 1, true))
        local passesFilter = true
        if filter ~= "all" then
            local cat = self:GetAnimationCategory(id, anim)
            if filter == "oxed" then
                passesFilter = (cat == "oxed" or cat == "male" or cat == "female")
            else
                passesFilter = (cat == filter)
            end
        end
        if passesSearch and passesFilter then
            local row = self:CreateAnimationRow(parent, id, anim)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, yOffset)
            yOffset = yOffset - 145
            matchCount = matchCount + 1
        end
    end

    if matchCount == 0 then
        local empty = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("CENTER", parent, "CENTER", 0, 0)
        if next(anims) == nil then
            empty:SetText(L["ANIM_EMPTY_NO_ANIMS"] or "No custom animations. Click 'Add Animation' to create one.")
        else
            empty:SetText(L["ANIM_EMPTY_FILTER"] or "No animations match your filter.")
        end
    end
    
    parent:SetHeight(math.abs(yOffset) + 50)
    
    -- Reset scroll position using stored reference
    if self.currentScrollFrame then
        self.currentScrollFrame:SetVerticalScroll(0)
        self.currentScrollFrame:UpdateScrollChildRect()
        -- Reset scrollbar thumb
        for _, child in ipairs({self.currentScrollFrame:GetChildren()}) do
            if child.SetValue and child.GetMinMaxValues then
                child:SetValue(0)
            end
        end
    end
end

-- Create animation row
function Animations:CreateAnimationRow(parent, id, anim)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(140)
    
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
    })
    row:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    row:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Preview frame (shows first frame)
    local preview = CreateFrame("Frame", nil, row, "BackdropTemplate")
    preview:SetSize(128, 128)
    preview:SetPoint("LEFT", row, "LEFT", 10, 0)
    preview:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    })
    preview:SetBackdropColor(0, 0, 0, 1)
    
    local previewTex = preview:CreateTexture(nil, "ARTWORK")
    previewTex:SetAllPoints()
    previewTex:SetTexture(anim.tgaPath)
    -- Show only the first frame based on sprite sheet grid
    local prevCols = anim.columns or math.ceil(math.sqrt(anim.frameCount or 25))
    local prevRows = anim.rows or prevCols
    if prevCols < 1 then prevCols = 1 end
    if prevRows < 1 then prevRows = 1 end
    previewTex:SetTexCoord(0, 1/prevCols, 0, 1/prevRows)
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", preview, "TOPRIGHT", 15, 0)
    nameText:SetWidth(170)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(anim.name or id)

    -- Info
    local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)
    infoText:SetWidth(170)
    infoText:SetJustifyH("LEFT")
    local loopText = tostring(anim.loopCount or 1)
    local infoCols = anim.columns or math.ceil(math.sqrt(anim.frameCount or 1))
    local infoRows = anim.rows or infoCols
    local infoAspect = anim.aspectRatio or "1:1"
    infoText:SetText(string.format("%dx%d, %d frames (%dx%d), %s, %d FPS, Loop: %s",
        anim.width or 64, anim.height or 64, anim.frameCount or 1, infoCols, infoRows, infoAspect, anim.fps or 24, loopText))
    infoText:SetTextColor(0.7, 0.7, 0.7, 1)

    -- File path
    local pathText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pathText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -2)
    pathText:SetWidth(350)
    pathText:SetJustifyH("LEFT")
    pathText:SetText(anim.tgaPath or "")
    pathText:SetTextColor(0.5, 0.5, 0.5, 1)

    -- Right-side buttons: Preview (top) + Delete (mid)
    local previewBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    previewBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -10)
    previewBtn:SetSize(80, 22)
    previewBtn:SetText(L["ANIM_BTN_PREVIEW"] or "Preview")
    previewBtn:SetScript("OnClick", function()
        Animations:ShowPreviewOverlay(id)
    end)

    local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    editBtn:SetPoint("TOPRIGHT", previewBtn, "BOTTOMRIGHT", 0, -2)
    editBtn:SetSize(80, 22)
    editBtn:SetText(L["ANIM_BTN_EDIT"] or "Edit")
    editBtn:SetScript("OnClick", function()
        Animations.editTarget = anim
        Animations.editTargetId = id
        OxedHub.UI:ShowAnimationsSubTab("Advanced")
    end)

    local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    delBtn:SetPoint("TOPRIGHT", editBtn, "BOTTOMRIGHT", 0, -2)
    delBtn:SetSize(80, 22)
    delBtn:SetText(L["ANIM_BTN_DELETE"] or "Delete")
    delBtn:SetScript("OnClick", function()
        self:DeleteAnimation(id)
    end)

    -- Bottom controls: Enable + Loop (left)  Custom + Set Pos (right)
    local enableCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    enableCheck:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 145, 10)
    enableCheck:SetSize(15, 15)
    enableCheck:SetChecked(anim.enabled or false)
    enableCheck.text:SetText(L["ANIM_ENABLE"] or "Enable")
    enableCheck:SetScript("OnClick", function(self)
        anim.enabled = self:GetChecked()
    end)

    local loopLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    loopLabel:SetPoint("LEFT", enableCheck.text, "RIGHT", 10, 0)
    loopLabel:SetText(L["ANIM_LOOP"] or "Loop:")
    loopLabel:SetTextColor(0.7, 0.7, 0.5, 1)

    local loopEdit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    loopEdit:SetPoint("LEFT", loopLabel, "RIGHT", 3, 0)
    loopEdit:SetSize(35, 20)
    loopEdit:SetAutoFocus(false)
    loopEdit:SetNumeric(true)
    loopEdit:SetText(tostring(anim.loopCount or 1))
    loopEdit:SetScript("OnTextChanged", function(self)
        local val = tonumber(self:GetText())
        if val then
            anim.loopCount = val
            local newLoopText = tostring(val or 1)
            local updCols = anim.columns or math.ceil(math.sqrt(anim.frameCount or 1))
            local updRows = anim.rows or updCols
            local updAspect = anim.aspectRatio or "1:1"
            infoText:SetText(string.format("%dx%d, %d frames (%dx%d), %s, %d FPS, Loop: %s",
                anim.width or 64, anim.height or 64, anim.frameCount or 1, updCols, updRows, updAspect, anim.fps or 24, newLoopText))
        end
    end)

    -- Loop info icon
    local loopInfoIcon = CreateFrame("Button", nil, row)
    loopInfoIcon:SetSize(15, 15)
    loopInfoIcon:SetPoint("LEFT", loopEdit, "RIGHT", 6, 0)
    loopInfoIcon:SetNormalTexture("Interface\\Common\\help-i")
    loopInfoIcon:SetHighlightTexture("Interface\\Common\\help-i", "ADD")
    loopInfoIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ANIM_LOOP"] or "Loop")
        GameTooltip:AddLine(L["ANIM_LOOP_DESC"] or "How many times your animation plays on screen before it fades out.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    loopInfoIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local customPosCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    customPosCheck:SetPoint("LEFT", loopInfoIcon, "RIGHT", 14, 0)
    customPosCheck:SetSize(15, 15)
    customPosCheck:SetChecked(anim.useCustomPosition or false)
    customPosCheck.text:SetText(L["ANIM_CUSTOM_POS"] or "Custom Position")
    customPosCheck:SetScript("OnClick", function(self)
        anim.useCustomPosition = self:GetChecked()
        if anim.useCustomPosition then
            self.posBtn:Enable()
        else
            self.posBtn:Disable()
        end
    end)

    local posBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    posBtn:SetPoint("LEFT", customPosCheck.text, "RIGHT", 5, 0)
    posBtn:SetSize(105, 18)
    posBtn:SetText(L["ANIM_MOVE_SCALE"] or "Move / Scale")
    posBtn:SetScript("OnClick", function()
        Animations:ShowPositionFrameForAnimation(id)
    end)
    if not (anim.useCustomPosition or false) then
        posBtn:Disable()
    end
    customPosCheck.posBtn = posBtn

    return row
end

-- Add animation
function Animations:AddAnimation(data)
    local id = data.id or OxedHub:GenerateID("anim")
    
    -- Ensure a recognized extension (default to .tga)
    local filename = data.filename
    if not filename:lower():find("%.tga$") and not filename:lower():find("%.png$") then
        filename = filename .. ".tga"
    end

    -- Honor a pre-resolved path (advanced engine), else resolve across both folders
    local tgaPath = data.tgaPath or ResolveAnimationPath(filename)
    
    local frameCount = tonumber(data.frameCount) or 12
    local aspectRatio = data.aspectRatio or "1:1"
    
    local columns = tonumber(data.columns)
    local rows = tonumber(data.rows)

    -- Calculate grid layout based on aspect ratio if not explicitly provided
    if not columns or not rows then
        if aspectRatio == "16:9" then
            -- Wide: more rows than columns to keep sprite sheet squarish
            rows = math.ceil(math.sqrt(frameCount * 16 / 9))
            columns = math.ceil(frameCount / rows)
        elseif aspectRatio == "9:16" then
            -- Tall: more columns than rows to keep sprite sheet squarish
            columns = math.ceil(math.sqrt(frameCount * 16 / 9))
            rows = math.ceil(frameCount / columns)
        else
            -- 1:1 square grid (default, backward compatible)
            columns = math.ceil(math.sqrt(frameCount))
            rows = columns
        end
    end

    OxedHub.db.profile.animations[id] = {
        name = data.name,
        tgaPath = tgaPath,
        width = tonumber(data.width) or 64,
        height = tonumber(data.height) or 64,
        frameCount = frameCount,
        columns = columns,
        rows = rows,
        aspectRatio = aspectRatio,
        fps = tonumber(data.fps) or 24,
        loopCount = data.loopCount or 1,
        playSequence = data.playSequence,
        enabled = true,
        useCustomPosition = false,
        customPositionX = 0,
        customPositionY = 200,
    }
    
    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Animations")
    end
end

-- Delete animation
function Animations:DeleteAnimation(id)
    -- Stop if playing
    if activeAnimations[id] then
        self:Stop(id)
    end
    
    OxedHub.db.profile.animations[id] = nil
    
    -- Refresh UI if visible
    if OxedHub.UI and OxedHub.UI:GetCurrentTab() == "Reactions" then
        OxedHub.UI:ShowSubTab("Animations")
    end
end

-- Show position frame for dragging animation to desired position
function Animations:ShowPlayerFrame()
    if not self.positionFrame then
        self:CreatePositionFrame()
    end
    if not self.playerFrame then
        self:CreatePlayerFrame()
    end

    self.positionFrame.targetAnimId = nil
    self:_PositionFrameSimpleMode()
    self:ApplyPositionFramePosition()
    self:AttachPlayerFrameToTarget()
    self.positionFrame:Show()
end

-- Preview overlay: reuses the position frame in preview-only mode (no drag/resize/reset)
function Animations:ShowPreviewOverlay(animId)
    if not self.positionFrame then
        self:CreatePositionFrame()
    end
    if not self.playerFrame then
        self:CreatePlayerFrame()
    end

    local anim = OxedHub.db.profile.animations[animId]
    if not anim then return end

    local frame = self.positionFrame
    frame.targetAnimId = nil
    frame.onSaveCallback = nil
    frame._previewOnlyMode = true
    frame._previewOnlyAnimId = animId

    -- Size the frame to the animation's on-screen size (3x) and lock the aspect
    local dispW = (anim.width or 64) * 3
    local dispH = (anim.height or 64) * 3
    frame.lockAspect = dispW / math.max(1, dispH)
    frame._adjusting = true
    frame:SetSize(math.max(60, dispW + 6), math.max(40, dispH + 6))
    frame._adjusting = false

    -- Hide crosshair, hide resize grip (no resizing in preview mode)
    if frame.crossV then frame.crossV:Hide(); frame.crossH:Hide() end
    if frame.resizeGrip then frame.resizeGrip:Hide() end

    -- Update title and subtitle for preview mode
    if frame.titleText then frame.titleText:SetText("Preview") end
    if frame.instrText then frame.instrText:SetText("This is a preview of your animation and position") end

    -- Hide Reset button, only show Done
    if frame.resetBtn then frame.resetBtn:Hide() end
    if frame.doneBtn then
        frame.doneBtn:ClearAllPoints()
        frame.doneBtn:SetPoint("TOP", frame, "BOTTOM", 0, -8)
    end

    -- Disable dragging in preview mode
    frame:SetMovable(false)

    -- Position at the animation's custom position or default
    local x = anim.customPositionX or 0
    local y = anim.customPositionY or 200
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x, y)

    -- Play the animation looped inside the frame
    self:StartPositionPreview(anim)
    frame:Show()
end

function Animations:HidePreviewOverlay()
    local frame = self.positionFrame
    if not frame or not frame._previewOnlyMode then return end

    local animId = frame._previewOnlyAnimId
    if animId then
        self:Stop(animId)
    end

    self:StopPositionPreview()
    frame._previewOnlyMode = false
    frame._previewOnlyAnimId = nil
    frame:SetMovable(true)
    frame:Hide()

    -- Restore title and subtitle for normal position mode
    if frame.titleText then frame.titleText:SetText(L["ANIM_DRAG_TO_POS"] or "Drag to Position") end
    if frame.instrText then frame.instrText:SetText(L["ANIM_DRAG_TO_MOVE"] or "Drag to move  •  drag the corner to resize") end

    -- Restore Reset button + Done button layout for normal position mode
    if frame.resetBtn then frame.resetBtn:Show() end
    if frame.doneBtn then
        frame.doneBtn:ClearAllPoints()
        frame.doneBtn:SetPoint("TOP", frame, "BOTTOM", 34, -8)
    end
end

-- Play animation
function Animations:Play(animationIdOrName, customPosData)
    local anim = nil
    local id = nil
    
    -- Look up by ID
    if OxedHub.db.profile.animations[animationIdOrName] then
        id = animationIdOrName
        anim = OxedHub.db.profile.animations[id]
    else
        -- Look up by name
        for animId, data in pairs(OxedHub.db.profile.animations) do
            if data.name == animationIdOrName then
                id = animId
                anim = data
                break
            end
        end
    end
    
    if not anim or not anim.enabled then
        return
    end
    
    -- Clone anim to prevent mutating global table
    local playData = {}
    for k, v in pairs(anim) do playData[k] = v end
    playData.id = id

    if customPosData and customPosData.useCustomPosition then
        playData.useCustomPosition = true
        playData.customPositionX = customPosData.x
        playData.customPositionY = customPosData.y
    end

    self:PlayAnimationDirect(playData)
end

-- Set animation frame texture coordinates (supports rectangular grids)
function Animations:SetAnimationFrame(frame, stepIndex, animData)
    if not frame or not frame.texture then return end
    
    -- Support rectangular grids: use explicit columns/rows if available, else fall back to square
    local cols = animData.columns or math.ceil(math.sqrt(animData.frameCount))
    local rows = animData.rows or cols
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end
    
    -- Map sequence step to actual frame index if playSequence is defined
    local frameNum = stepIndex
    if animData.playSequence and #animData.playSequence > 0 then
        -- Step index is 0-based from the ticker, but Lua arrays are 1-based
        frameNum = animData.playSequence[stepIndex + 1] or stepIndex
    end
    
    -- Calculate row and column in grid
    local row = math_floor(frameNum / cols)
    local col = frameNum % cols
    
    -- Calculate texture coordinates (0-1 range)
    local left = col / cols
    local right = (col + 1) / cols
    local top = row / rows
    local bottom = (row + 1) / rows
    
    frame.texture:SetTexCoord(left, right, top, bottom)
end

-- Create a new animation frame (reuses from pool if available)
function Animations:AcquireAnimationFrame()
    if not self.animationPool then
        self.animationPool = {}
    end
    for _, frame in ipairs(self.animationPool) do
        if not frame.isActive then
            frame.isActive = true
            return frame
        end
    end
    -- No available frame, create new
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(50)
    frame:Hide()
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    frame.texture = tex
    frame.isActive = true
    table.insert(self.animationPool, frame)
    return frame
end

-- Release an animation frame back to the pool
function Animations:ReleaseAnimationFrame(frame)
    if frame.timer then
        frame.timer:Cancel()
        frame.timer = nil
    end
    frame:Hide()
    frame.isActive = false
    frame.texture:SetTexture(nil)
end

-- Play animation using Soundie approach (supports multiple concurrent animations)
function Animations:PlayAnimationDirect(animData)
    local frame = self:AcquireAnimationFrame()
    if not frame then return end

    -- Built-in animations display at 128x128 on-screen; user animations scale 3x
    local scale = animData.isBuiltIn and (128 / animData.width) or 3
    frame:SetSize(animData.width * scale, animData.height * scale)
    frame.texture:SetTexture(animData.tgaPath)
    frame.currentFrame = 0
    frame.animData = animData

    -- Position the frame
    self:AttachPlayerFrameToTarget(animData)
    -- Copy the anchor from playerFrame to this animation frame
    if self.playerFrame then
        local point, relativeTo, relativePoint, xOfs, yOfs = self.playerFrame:GetPoint(1)
        if point then
            frame:ClearAllPoints()
            frame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
        end
    end

    frame:Show()

    -- Set first frame
    self:SetAnimationFrame(frame, 0, animData)

    -- Setup looping
    local loopCount = animData.loopCount or 1
    if loopCount < 1 then loopCount = 1 end
    local maxLoops = loopCount
    local currentLoop = 1

    local maxFrames = animData.frameCount
    if animData.playSequence and #animData.playSequence > 0 then
        maxFrames = #animData.playSequence
    end

    -- Create animation ticker
    local fps = animData.fps or 24
    frame.timer = C_Timer.NewTicker(1/fps, function()
        frame.currentFrame = frame.currentFrame + 1
        if frame.currentFrame >= maxFrames then
            -- End of one loop iteration
            if currentLoop >= maxLoops then
                -- All loops done
                Animations:ReleaseAnimationFrame(frame)
                -- Auto-hide preview overlay if showing for this animation
                if Animations.positionFrame and Animations.positionFrame._previewOnlyMode
                   and Animations.positionFrame._previewOnlyAnimId == animData.id then
                    Animations:HidePreviewOverlay()
                end
            else
                -- Start next loop
                currentLoop = currentLoop + 1
                frame.currentFrame = 0
                Animations:SetAnimationFrame(frame, 0, animData)
            end
        else
            Animations:SetAnimationFrame(frame, frame.currentFrame, animData)
        end
    end, maxLoops * maxFrames)
end

-- Stop animation
function Animations:Stop(id)
    -- Release all active animation frames matching this id
    if self.animationPool then
        for _, frame in ipairs(self.animationPool) do
            if frame.isActive and frame.animData and frame.animData.id == id then
                self:ReleaseAnimationFrame(frame)
            end
        end
    end

    -- Legacy cleanup
    if activeAnimations[id] then
        activeAnimations[id] = nil
    end
end

-- Active cooldown progress frames
local cooldownProgressFrames = {}

--- Play a cooldown progress animation showing a spell icon with cooldown spiral
-- @param spellID number - the spell ID whose cooldown to track
-- @param iconTexture string|number - icon texture path or fileID (optional, auto-fetched if nil)
-- @param customDuration number - override duration in seconds (optional)
-- Known interrupt spell cooldowns (fallback when API returns 0)
local INTERRUPT_COOLDOWNS = {
    [47528] = 15,  -- Mind Freeze (DK)
    [183752] = 15, -- Disrupt (DH)
    [106839] = 15, -- Skull Bash (Druid)
    [147362] = 24, -- Counter Shot (Hunter)
    [187707] = 15, -- Muzzle (Hunter)
    [2139] = 24,   -- Counterspell (Mage)
    [116705] = 15, -- Spear Hand Strike (Monk)
    [96231] = 15,  -- Rebuke (Paladin)
    [31935] = 15,  -- Avenger's Shield (Paladin)
    [15487] = 45,  -- Silence (Priest)
    [1766] = 15,   -- Kick (Rogue)
    [57994] = 12,  -- Wind Shear (Shaman)
    [6552] = 15,   -- Pummel (Warrior)
    [119898] = 24, -- Command Demon (Warlock)
    [212619] = 24, -- Call Felhunter (Warlock)
    [351338] = 60, -- Netherstrike (Evoker)
    [362969] = 15, -- Wake of Sleep (Evoker)
}

function Animations:PlayCooldownProgress(spellID, iconTexture, customDuration)
    if not spellID then return end

    -- Get spell info
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local icon = iconTexture or (spellInfo and spellInfo.iconID) or 136018

    -- Reuse or create frame immediately (show icon even before we know cooldown)
    local frame = cooldownProgressFrames[spellID]
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(64, 64)
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(60)

        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.iconTexture = tex

        local cd = CreateFrame("Cooldown", nil, frame)
        cd:SetAllPoints()
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        cd:SetDrawSwipe(true)
        cd:SetSwipeColor(0, 0, 0, 0.8)
        cd:SetHideCountdownNumbers(true)
        frame.cooldown = cd

        -- Custom countdown text (BliZzi-style)
        local txt = frame:CreateFontString(nil, "OVERLAY")
        txt:SetPoint("CENTER", frame, "CENTER", 0, 0)
        txt:SetFont(OxedHub:GetFont(STANDARD_TEXT_FONT), 20, "OUTLINE")
        txt:SetTextColor(1, 1, 1, 1)
        frame.countdownText = txt

        local x, y
        local settings = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings
        local pos = settings and settings.cooldownProgressPosition
        if pos and pos.x and pos.y then
            x, y = pos.x, pos.y
        else
            x, y = 0, 150
        end
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)

        cooldownProgressFrames[spellID] = frame
    end

    frame.iconTexture:SetTexture(icon)
    frame:Show()

    -- Cancel any existing retry timer
    if frame.cdRetryTicker then
        frame.cdRetryTicker:Cancel()
        frame.cdRetryTicker = nil
    end
    -- Cancel existing hide ticker
    if frame.hideTicker then
        frame.hideTicker:Cancel()
        frame.hideTicker = nil
    end

    -- Determine duration: custom > API query > fallback table
    local duration = customDuration
    local startTime = GetTime()

    if not duration then
        -- Try API query (pcall for taint safety)
        local ok, cdInfo = pcall(function()
            return C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
        end)
        if ok and cdInfo then
            local durOk, dur = pcall(function() return cdInfo.duration end)
            if durOk and dur then
                duration = dur
            end
        end
    end

    -- If API returned 0 or nothing, use known fallback and retry
    local apiDuration = duration
    local fallbackDuration = INTERRUPT_COOLDOWNS[spellID] or 15

    local function ApplyCooldown(cdDuration)
        frame.cooldown:SetCooldown(startTime, cdDuration)
        frame.cooldown:Show()
        -- Auto-hide ticker + custom countdown text update (BliZzi-style)
        frame.hideTicker = C_Timer.NewTicker(0.1, function()
            local remaining = cdDuration - (GetTime() - startTime)
            -- Update countdown text
            if frame.countdownText then
                local display = math.max(0, math.floor(remaining + 0.5))
                if display > 0 then
                    frame.countdownText:SetText(tostring(display))
                else
                    frame.countdownText:SetText("")
                end
            end
            local tickOk, shouldHide = pcall(function() return remaining <= 0 end)
            if tickOk and shouldHide then
                frame:Hide()
                if frame.countdownText then
                    frame.countdownText:SetText("")
                end
                if frame.hideTicker then
                    frame.hideTicker:Cancel()
                    frame.hideTicker = nil
                end
            end
        end)
    end

    local apiOk, apiPositive = pcall(function() return apiDuration and apiDuration > 0 end)
    if apiOk and apiPositive then
        -- API gave us a valid duration immediately
        ApplyCooldown(apiDuration)
    else
        -- Use fallback immediately so user sees something,
        -- then retry API for more accurate duration
        ApplyCooldown(fallbackDuration)

        -- Retry up to 10 times (1 second) for API to update
        local retries = 0
        frame.cdRetryTicker = C_Timer.NewTicker(0.1, function()
            retries = retries + 1
            if retries > 10 then
                if frame.cdRetryTicker then
                    frame.cdRetryTicker:Cancel()
                    frame.cdRetryTicker = nil
                end
                return
            end
            local ok, cdInfo = pcall(function()
                return C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
            end)
            if ok and cdInfo then
                local durOk, dur = pcall(function() return cdInfo.duration end)
                local cmpOk, isPositive = pcall(function() return dur and dur > 0 end)
                if durOk and cmpOk and isPositive then
                    -- API now reports a real duration, restart cooldown
                    startTime = GetTime()
                    if frame.hideTicker then
                        frame.hideTicker:Cancel()
                        frame.hideTicker = nil
                    end
                    ApplyCooldown(dur)
                    if frame.cdRetryTicker then
                        frame.cdRetryTicker:Cancel()
                        frame.cdRetryTicker = nil
                    end
                end
            end
        end)
    end
end

-- Hide a specific cooldown progress frame
function Animations:HideCooldownProgress(spellID)
    local frame = cooldownProgressFrames[spellID]
    if frame then
        frame:Hide()
        if frame.countdownText then
            frame.countdownText:SetText("")
        end
        if frame.hideTicker then
            frame.hideTicker:Cancel()
            frame.hideTicker = nil
        end
        if frame.cdRetryTicker then
            frame.cdRetryTicker:Cancel()
            frame.cdRetryTicker = nil
        end
    end
end

-- Stop all animations
function Animations:StopAll()
    -- Release all active animation frames
    if self.animationPool then
        for _, frame in ipairs(self.animationPool) do
            if frame.isActive then
                self:ReleaseAnimationFrame(frame)
            end
        end
    end

    -- Hide preview frame
    if self.playerFrame then
        self.playerFrame:Hide()
    end

    wipe(activeAnimations)
end
