local addonName, OxedHub = ...

local Toys = OxedHub.Toys or {}
OxedHub.Toys = Toys
local L = OxedHub.L

-- ============================================================================
-- TOY HEARTHSTONE DATABASE
-- ============================================================================
Toys.HearthstoneIds = {
    162973, 246565, 208704, 206195, 168907, 235016, 190196, 54452,
    263489, 64488, 193588, 245970, 200630, 228940, 210455, 93672,
    172179, 183716, 188952, 165802, 190237, 209035, 212337, 142542,
    236687, 165669, 184353, 182773, 163045, 180290, 166746, 165670,
    166747, 263933, 265100, 257736
}

function Toys:GetUsableHearthstones()
    if self.EnsureToyData then self:EnsureToyData(true) end

    local usable, owned = {}, {}
    for _, hsID in ipairs(self.HearthstoneIds) do
        if PlayerHasToy(hsID) then
            table.insert(owned, hsID)
            if C_ToyBox.IsToyUsable(hsID) then
                table.insert(usable, hsID)
            end
        end
    end

    -- IsToyUsable reports nil for anything the client has not cached yet, so on
    -- a cold start every hearthstone looks unusable and the button ends up with
    -- no toy assigned at all.  Owning it is a good enough fallback.
    if #usable > 0 then return usable end
    return owned
end

-- ============================================================================
-- MODERN FLOATING TOYBOX WINDOW (BasicFrameTemplate - Matching Pick Sound)
-- ============================================================================
local isMoving = false
local isResizing = false
local selectedHearthstoneId = 0
local selectedToyboxId = "all"

local function GetCursorToy()
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

-- ============================================================================
-- MOVABLE MINIMIZED FLOATING BUTTON
-- ============================================================================
function Toys:GetOrCreateMiniButton()
    if self.MiniButton then return self.MiniButton end

    local profile = OxedHub.db and OxedHub.db.profile
    profile.toyBoxMini = profile.toyBoxMini or {
        point = "CENTER", relativePoint = "CENTER", offsetX = 250, offsetY = 0
    }
    local conf = profile.toyBoxMini

    local mb = CreateFrame("Button", "OxedHub_ToyboxMiniButton", UIParent, "BackdropTemplate")
    mb:SetSize(38, 38)
    mb:SetFrameStrata("HIGH")
    mb:SetFrameLevel(520)
    mb:SetClampedToScreen(true)
    mb:SetMovable(true)
    mb:EnableMouse(true)
    mb:RegisterForDrag("LeftButton")
    mb:SetPoint(conf.point or "CENTER", UIParent, conf.relativePoint or "CENTER", conf.offsetX or 250, conf.offsetY or 0)

    mb:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    mb:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
    mb:SetBackdropBorderColor(0.85, 0.70, 0.20, 1.0)

    local icon = mb:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture(135933)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    mb.icon = icon

    local hl = mb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    local isDragging = false
    mb:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            isDragging = true
            self:StartMoving()
        end
    end)
    mb:SetScript("OnDragStop", function(self)
        if isDragging then
            self:StopMovingOrSizing()
            isDragging = false
            local p, _, rp, x, y = self:GetPoint()
            conf.point = p
            conf.relativePoint = rp
            conf.offsetX = x
            conf.offsetY = y
        end
    end)

    mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mb:SetScript("OnClick", function(self, mouseButton)
        if isDragging then return end
        if mouseButton == "RightButton" then
            Toys:ShowExpandDirectionMenu(self)
        else
            Toys:ExpandToyDock()
        end
    end)

    mb:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("|cFFFFD900ToyBox (Minimized)|r")
        GameTooltip:AddLine("|cFFFFFFFFClick:|r Expand ToyBox window", 1, 1, 1)
        GameTooltip:AddLine("|cFF88AAFFRight-click:|r Choose open direction", 0.6, 0.8, 1)
        GameTooltip:AddLine("|cFF88AAFFShift + Drag:|r Move button anywhere", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    mb:Hide()
    self.MiniButton = mb
    return mb
end

-- Where the panel appears relative to the minimised button.
Toys.EXPAND_DIRECTIONS = {
    { key = "auto",     label = "Auto (Smart Near Button)" },
    { key = "down",     label = "Below Button" },
    { key = "up",       label = "Above Button" },
    { key = "left",     label = "Left of Button" },
    { key = "right",    label = "Right of Button" },
    { key = "remember", label = "Custom (Saved Position)" },
}

local function PlayExpandAnimation(frame)
    if not frame.expandAnimGroup then
        local ag = frame:CreateAnimationGroup()
        
        local alpha = ag:CreateAnimation("Alpha")
        alpha:SetDuration(0.12)
        alpha:SetFromAlpha(0.2)
        alpha:SetToAlpha(1.0)
        alpha:SetOrder(1)
        if alpha.SetSmoothing then
            alpha:SetSmoothing("OUT")
        end
        
        frame.expandAnimGroup = ag
    end
    
    pcall(function()
        frame.expandAnimGroup:Stop()
        frame.expandAnimGroup:Play()
    end)
end

local function AnchorFrameToButton(f, mini, direction)
    local miniLeft, miniBottom, miniWidth, miniHeight = mini:GetRect()
    if not miniLeft then
        local p, _, rp, x, y = mini:GetPoint()
        f:ClearAllPoints()
        f:SetPoint(p or "CENTER", UIParent, rp or "CENTER", x or 0, y or 0)
        return "CENTER"
    end

    local uiW = UIParent:GetWidth() or 1920
    local uiH = UIParent:GetHeight() or 1080
    local fW = f:GetWidth() or 380
    local fH = f:GetHeight() or 270

    local miniRight = miniLeft + miniWidth
    local miniTop = miniBottom + miniHeight

    local dir = direction or "auto"
    if dir == "auto" or dir == "" or not dir then
        local spaceBelow = miniBottom
        local spaceAbove = uiH - miniTop
        local spaceLeft = miniLeft

        if spaceBelow >= fH + 10 then
            dir = "down"
        elseif spaceAbove >= fH + 10 then
            dir = "up"
        elseif spaceLeft >= fW + 10 then
            dir = "left"
        else
            dir = "right"
        end
    end

    local anchorPoint = "TOPLEFT"
    local originPoint = "TOPLEFT"
    local targetX = miniLeft
    local targetY = miniBottom - 4

    if dir == "down" then
        if miniLeft + fW > uiW - 10 then
            anchorPoint = "TOPRIGHT"
            targetX = miniRight
            targetY = miniBottom - 4
            originPoint = "TOPRIGHT"
        else
            anchorPoint = "TOPLEFT"
            targetX = miniLeft
            targetY = miniBottom - 4
            originPoint = "TOPLEFT"
        end
    elseif dir == "up" then
        if miniLeft + fW > uiW - 10 then
            anchorPoint = "BOTTOMRIGHT"
            targetX = miniRight
            targetY = miniTop + 4
            originPoint = "BOTTOMRIGHT"
        else
            anchorPoint = "BOTTOMLEFT"
            targetX = miniLeft
            targetY = miniTop + 4
            originPoint = "BOTTOMLEFT"
        end
    elseif dir == "left" then
        anchorPoint = "TOPRIGHT"
        targetX = miniLeft - 4
        targetY = math.min(uiH - 10, math.max(fH + 10, miniTop))
        originPoint = "TOPRIGHT"
    elseif dir == "right" then
        anchorPoint = "TOPLEFT"
        targetX = miniRight + 4
        targetY = math.min(uiH - 10, math.max(fH + 10, miniTop))
        originPoint = "TOPLEFT"
    end

    -- Clamp to screen bounds
    if anchorPoint == "TOPLEFT" then
        targetX = math.max(10, math.min(uiW - fW - 10, targetX))
        targetY = math.max(fH + 10, math.min(uiH - 10, targetY))
    elseif anchorPoint == "TOPRIGHT" then
        targetX = math.max(fW + 10, math.min(uiW - 10, targetX))
        targetY = math.max(fH + 10, math.min(uiH - 10, targetY))
    elseif anchorPoint == "BOTTOMLEFT" then
        targetX = math.max(10, math.min(uiW - fW - 10, targetX))
        targetY = math.max(10, math.min(uiH - fH - 10, targetY))
    elseif anchorPoint == "BOTTOMRIGHT" then
        targetX = math.max(fW + 10, math.min(uiW - 10, targetX))
        targetY = math.max(10, math.min(uiH - fH - 10, targetY))
    end

    f:ClearAllPoints()
    f:SetPoint(anchorPoint, UIParent, "BOTTOMLEFT", targetX, targetY)

    return originPoint
end

function Toys:ExpandToyDock(sourceButton)
    local mini = sourceButton or self.MiniButton
    local profile = OxedHub.db and OxedHub.db.profile
    if profile then
        profile.toyBoxDockState = "expanded"
        if profile.toyBoxSettings then
            profile.toyBoxSettings.showOnScreenDock = true
        end
    end
    local f = self:GetOrCreateToyboxFrame()

    local cfg = profile and profile.toyBoxSettings or {}
    local originPoint = "TOPLEFT"
    local dir = cfg.expandDirection or "auto"
    if dir ~= "remember" and mini and (mini:IsShown() or mini:GetLeft()) then
        originPoint = AnchorFrameToButton(f, mini, dir)
    end

    if mini then mini:Hide() end
    f:Show()
    PlayExpandAnimation(f)
    f:RefreshSideMenu()
    f:UpdateToyButtons()

    -- Re-roll on every open.
    if not InCombatLockdown() then
        if f.SelectNewRandomHearthstone then f:SelectNewRandomHearthstone() end
        if f.SelectNewRandomToy then f:SelectNewRandomToy() end
    end
end

-- ============================================================================
-- MAIN FLOATING FRAME
-- ============================================================================
function Toys:GetOrCreateToyboxFrame()
    if self.ToyboxFrame then return self.ToyboxFrame end

    local profile = OxedHub.db and OxedHub.db.profile
    profile.toyBoxFrame = profile.toyBoxFrame or {
        width = 420,
        height = 270,
        locked = false,
        isSideBarShown = true,
        iconSize = 36,
        location = { point = "CENTER", relativePoint = "CENTER", offsetX = 0, offsetY = -50 }
    }
    local conf = profile.toyBoxFrame

    -- Native WoW BasicFrameTemplate (Exact match to Pick Sound modal dialog)
    local f = CreateFrame("Frame", "OxedHub_ToyboxFrame", UIParent, "BasicFrameTemplate")
    f:SetFrameLevel(510)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetResizeBounds(260, 200, 900, 700)

    f:SetSize(conf.width or 420, conf.height or 270)
    f:SetPoint(conf.location.point or "CENTER", UIParent, conf.location.relativePoint or "CENTER", conf.location.offsetX or 0, conf.location.offsetY or -50)

    f:SetScript("OnDragStart", function(self)
        if not isMoving and not conf.locked then
            self:StartMoving()
            isMoving = true
        end
    end)
    f:SetScript("OnDragStop", function(self)
        if isMoving then
            self:StopMovingOrSizing()
            self:SavePosition()
            isMoving = false
        end
    end)
    f:SetScript("OnHide", function(self)
        if isMoving then
            self:StopMovingOrSizing()
            self:SavePosition()
            isMoving = false
        end
    end)

    function f:SavePosition()
        local p, _, rp, x, y = self:GetPoint()
        conf.location.point = p
        conf.location.relativePoint = rp
        conf.location.offsetX = x
        conf.location.offsetY = y
        conf.width = self:GetWidth()
        conf.height = self:GetHeight()
    end

    function f:Minimize()
        self:Hide()
        local profile = OxedHub.db and OxedHub.db.profile
        if profile then
            profile.toyBoxDockState = "minimized"
            if profile.toyBoxSettings then
                profile.toyBoxSettings.showOnScreenDock = true
            end
        end
        local mb = Toys:GetOrCreateMiniButton()
        local cfg = profile and profile.toyBoxSettings or {}
        if cfg.miniIconAuto == false and cfg.miniIcon then
            mb.icon:SetTexture(Toys:GetBoxIconTexture(cfg.miniIcon) or 135933)
        else
            local box = Toys:GetToyBox(selectedToyboxId)
            if box and box.icon then
                mb.icon:SetTexture(Toys:GetBoxIconTexture(box.icon))
            else
                mb.icon:SetTexture(135933)
            end
        end
        mb:Show()
    end

    -- Header Title (Native BasicFrameTemplate TitleText)
    if f.TitleText then
        f.TitleText:SetText("ToyBox: All Toys")
    end

    -- Hide native Close Button so we can place the dedicated Minimize button in its spot
    if f.CloseButton then
        f.CloseButton:Hide()
    end

    -- [-] Minimize Button in Top-Right Titlebar
    local minBtn = CreateFrame("Button", "$parent_MinBtn", f, "UIPanelButtonTemplate")
    minBtn:SetSize(26, 26)
    minBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 2)
    minBtn:SetText("-")
    minBtn:SetNormalFontObject("GameFontNormalLarge")
    minBtn:SetScript("OnClick", function()
        f:Minimize()
    end)
    minBtn:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Minimize to movable button")
        GameTooltip:Show()
    end)
    minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.MinimizeButton = minBtn

    -- ========================================================================
    -- TOP SUB-HEADER CONTROL BAR (BELOW TITLE BAR)
    -- ========================================================================
    local controlBar = CreateFrame("Frame", nil, f)
    controlBar:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24)
    controlBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -24)
    controlBar:SetHeight(26)
    f.ControlBar = controlBar

    -- [ Boxes ] Sidebar Toggle Button (Clean ASCII without broken characters)
    local sideMenuBtn = CreateFrame("Button", "$parent_SideMenuBtn", controlBar, "UIPanelButtonTemplate")
    sideMenuBtn:SetSize(68, 20)
    sideMenuBtn:SetPoint("LEFT", controlBar, "LEFT", 2, 0)
    sideMenuBtn:SetText("Boxes v")
    sideMenuBtn:SetNormalFontObject("GameFontNormalSmall")
    sideMenuBtn:SetScript("OnClick", function()
        f:ToggleSideMenuBar()
    end)
    f.SideMenuButton = sideMenuBtn

    -- [ Lock ] Toggle Button
    -- [ Search ] filters the toys shown on the panel.
    local searchBox = CreateFrame("EditBox", "$parent_Search", controlBar, "SearchBoxTemplate")
    searchBox:SetSize(110, 20)
    searchBox:SetPoint("LEFT", sideMenuBtn, "RIGHT", 6, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(box)
        SearchBoxTemplate_OnTextChanged(box)
        local text = box:GetText() or ""
        if text == (SEARCH or "Search") then text = "" end
        Toys._dockSearch = text
        f:UpdateToyButtons()
    end)
    searchBox:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
        Toys._dockSearch = ""
        f:UpdateToyButtons()
    end)
    f.SearchBox = searchBox

    -- [ Settings ] jumps back to the ToyBoxes tab in the addon, so the panel is
    -- not a dead end when you want to edit what is in a box.
    local settingsBtn = CreateFrame("Button", "$parent_SettingsBtn", controlBar, "UIPanelButtonTemplate")
    settingsBtn:SetSize(22, 20)
    settingsBtn:SetPoint("RIGHT", controlBar, "RIGHT", -2, 0)

    local gearIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetPoint("TOPLEFT", 3, -3)
    gearIcon:SetPoint("BOTTOMRIGHT", -3, 3)
    gearIcon:SetTexture("Interface\\GossipFrame\\BinderGossipIcon")
    settingsBtn.gearIcon = gearIcon

    settingsBtn:SetScript("OnClick", function()
        local UI = OxedHub.UI
        if not UI then return end

        -- ShowTab only switches tabs inside an already-open window; on its own
        -- it does nothing when the addon is closed.  Open the window first.
        if UI.ShowMainWindow then
            UI:ShowMainWindow()
        end

        -- The tab content is built lazily, so give the window a frame to come
        -- up before selecting the sub-tab.
        C_Timer.After(0, function()
            if UI.ShowTab then UI:ShowTab("Toys") end
            if UI.ShowToysSubTab then UI:ShowToysSubTab("ToyBoxes") end
        end)
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("|cFFFFD900ToyBox Settings|r")
        GameTooltip:AddLine("Open the ToyBoxes tab in Oxed Hub.", 1, 1, 1)
        GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.SettingsButton = settingsBtn

    local lockBtn = CreateFrame("Button", "$parent_LockBtn", controlBar, "UIPanelButtonTemplate")
    lockBtn:SetSize(52, 20)
    lockBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -4, 0)
    lockBtn:SetText(conf.locked and "Unlock" or "Lock")
    lockBtn:SetNormalFontObject("GameFontNormalSmall")
    lockBtn:SetScript("OnClick", function(self)
        conf.locked = not conf.locked
        self:SetText(conf.locked and "Unlock" or "Lock")
        if f.UpdateUnlockedBanner then f:UpdateUnlockedBanner() end

        -- The tiles carry their armed state as attributes now, so they have to
        -- be redrawn for the new lock state to take effect.
        if f.UpdateToyButtons then f:UpdateToyButtons() end

        if conf.locked then
            f.ResizeButton:Hide()
        else
            f.ResizeButton:Show()
        end
    end)
    lockBtn:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if conf.locked then
            GameTooltip:AddLine("|cFF00FF00Click to Unlock|r")
            GameTooltip:AddLine("Move and resize the dock, and rearrange its tiles.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["TOYBOX_UNLOCK_WARNING"]
                or "While unlocked, clicking a tile will not use the toy.", 1, 0.4, 0.3, true)
        else
            GameTooltip:AddLine("|cFFFF5555Click to Lock|r")
            GameTooltip:AddLine("Back to using toys.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.LockButton = lockBtn

    -- Same rule as the ToyBox panel: unlocked is a mode you are in while
    -- arranging, so hiding the dock ends it rather than storing it for the next
    -- time the player wants to actually use a toy.
    f:HookScript("OnHide", function()
        if conf.locked then return end
        conf.locked = true
        lockBtn:SetText("Unlock")
        if f.UpdateUnlockedBanner then f:UpdateUnlockedBanner() end
        if f.ResizeButton then f.ResizeButton:Hide() end
        -- Re-arming the tiles writes secure attributes, which is forbidden in
        -- combat. The dock can be hidden by a fight starting, so skip it there;
        -- showing it again redraws anyway, and the saved state is already right.
        if not InCombatLockdown() and f.UpdateToyButtons then
            f:UpdateToyButtons()
        end
    end)

    -- [ Random Hearthstone ] Secure Button
    local randomHsBtn = CreateFrame("Button", "$parent_RandomHsBtn", controlBar, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    randomHsBtn:SetSize(22, 20)
    randomHsBtn:SetPoint("RIGHT", lockBtn, "LEFT", -6, 0)
    -- Both edges, and both attribute forms.
    --
    -- Whether a secure action fires on the press or the release is the player's
    -- ActionButtonUseKeyDown setting, not ours. Registering only for the press
    -- means the button does nothing at all for anyone who casts on release --
    -- which is why this worked here and not for other people. The grid and
    -- slot buttons were already fixed this way; these two were missed.
    randomHsBtn:RegisterForClicks("AnyDown", "AnyUp")
    randomHsBtn:SetAttribute("type", "toy")
    randomHsBtn:SetAttribute("type1", "toy")
    
    local hsIcon = randomHsBtn:CreateTexture(nil, "ARTWORK")
    hsIcon:SetPoint("TOPLEFT", 2, -2)
    hsIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    hsIcon:SetTexture(134414)
    hsIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    randomHsBtn.hsIcon = hsIcon

    local hsCd = CreateFrame("Cooldown", nil, randomHsBtn, "CooldownFrameTemplate")
    hsCd:SetAllPoints(hsIcon)
    randomHsBtn.Cooldown = hsCd

    local hsTimer = randomHsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hsTimer:SetPoint("CENTER", randomHsBtn, "CENTER", 0, 0)
    hsTimer:SetScale(0.65)
    randomHsBtn.Timer = hsTimer

    -- Re-rolled next frame, not inline.
    --
    -- Registered for both edges, this hook now runs twice per click, and one of
    -- those runs happens on the same edge that casts. Re-arming the attribute
    -- there could swap the toy out from under the press. A zero-delay timer
    -- puts the new roll safely after the click is done with.
    randomHsBtn:HookScript("OnClick", function()
        C_Timer.After(0, function() f:SelectNewRandomHearthstone() end)
    end)
    randomHsBtn:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("|cFFFFD900Random Hearthstone|r")
        GameTooltip:AddLine("Cast a random usable toy hearthstone.", 1, 1, 1)
        GameTooltip:Show()
    end)
    randomHsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.RandomHearthstoneButton = randomHsBtn

    -- [ Random Toy ] Secure Button (🎲 130772)
    local randomToyBtn = CreateFrame("Button", "$parent_RandomToyBtn", controlBar, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    randomToyBtn:SetSize(22, 20)
    randomToyBtn:SetPoint("RIGHT", randomHsBtn, "LEFT", -4, 0)
    randomToyBtn:RegisterForClicks("AnyDown", "AnyUp")
    randomToyBtn:SetAttribute("type", "toy")
    randomToyBtn:SetAttribute("type1", "toy")
    
    local diceIcon = randomToyBtn:CreateTexture(nil, "ARTWORK")
    diceIcon:SetPoint("TOPLEFT", 2, -2)
    diceIcon:SetPoint("BOTTOMRIGHT", -2, 2)
    diceIcon:SetTexture(130772)
    diceIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    randomToyBtn.diceIcon = diceIcon

    randomToyBtn:HookScript("OnClick", function()
        C_Timer.After(0, function() f:SelectNewRandomToy() end)
    end)
    randomToyBtn:SetScript("OnEnter", function(self)
        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if cfg.hideButtonTooltips then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("|cFFFFD900Random Toy|r")
        GameTooltip:AddLine("Use a random ready toy from this box.", 1, 1, 1)
        GameTooltip:Show()
    end)
    randomToyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.RandomToyButton = randomToyBtn

    -- Bottom-Right Resize Grip
    local resizeBtn = CreateFrame("Button", "$parent_ResizeBtn", f)
    resizeBtn:SetSize(14, 14)
    resizeBtn:SetNormalTexture(386864)
    resizeBtn:SetPushedTexture(386862)
    resizeBtn:SetHighlightTexture(386863)
    resizeBtn:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and not conf.locked then
            f:StartSizing("BOTTOMRIGHT", true)
            f:SetUserPlaced(true)
            isResizing = true
        end
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f:SavePosition()
        isResizing = false
        f:UpdateToyButtons()
    end)
    f.ResizeButton = resizeBtn
    if conf.locked then resizeBtn:Hide() end

    -- ========================================================================
    -- SIDEBAR DRAWER (BOX LIST - Compact 130px Wide, Scrollbar on LEFT of line)
    -- ========================================================================
    local sideMenu = CreateFrame("Frame", "$parent_SideMenu", f)
    -- Matches the toy grid: holder sits at -58 and its first row is inset by a
    -- further 4px, so the box list has to start at the same -62 to line up.
    sideMenu:SetPoint("TOPLEFT", 8, -58)
    sideMenu:SetPoint("BOTTOMLEFT", 8, 8)
    sideMenu:SetWidth(130)
    f.SideMenuBar = sideMenu

    -- 3px right divider line
    local sideDivider = sideMenu:CreateTexture(nil, "ARTWORK")
    sideDivider:SetPoint("TOPRIGHT", sideMenu, "TOPRIGHT", 3, -4)
    sideDivider:SetPoint("BOTTOMRIGHT", sideMenu, "BOTTOMRIGHT", 3, 4)
    sideDivider:SetWidth(1)
    sideDivider:SetColorTexture(1, 1, 1, 0.1)

    -- Inset by -26px so MinimalScrollBar sits strictly on LEFT side of line!
    local sideScroll = CreateFrame("ScrollFrame", "$parent_SideScroll", sideMenu, "UIPanelScrollFrameTemplate")
    sideScroll:SetPoint("TOPLEFT", 0, 0)
    sideScroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetSize(102, 200)
    sideScroll:SetScrollChild(sideChild)
    sideMenu.sideChild = sideChild
    ApplyModernScroll(sideScroll)
    sideScroll:HookScript("OnScrollRangeChanged", function(self, xrange, yrange)
        if self.oxedMinimalScrollBar then
            self.oxedMinimalScrollBar:SetShown(yrange and yrange > 0)
        end
    end)

    -- ========================================================================
    -- RIGHT QUICK TOYS BAR (5 PINNED ACCESS SLOTS ON THE RIGHT PANEL)
    -- ========================================================================
    local quickBar = CreateFrame("Frame", "$parent_QuickBar", f)
    quickBar:SetPoint("TOPRIGHT", -8, -58)
    quickBar:SetPoint("BOTTOMRIGHT", -8, 8)
    quickBar:SetWidth(44)
    f.QuickBar = quickBar

    -- Vertical divider between toy grid and quick bar
    local quickDivider = quickBar:CreateTexture(nil, "ARTWORK")
    quickDivider:SetPoint("TOPLEFT", quickBar, "TOPLEFT", -3, -4)
    quickDivider:SetPoint("BOTTOMLEFT", quickBar, "BOTTOMLEFT", -3, 4)
    quickDivider:SetWidth(1)
    quickDivider:SetColorTexture(1, 1, 1, 0.1)

    f.QuickSlots = {}
    Toys._quickSlots = f.QuickSlots
    local function HandleDropOnQuickSlot(slotBtn)
        local cursorToy = GetCursorToy() or Toys._draggedToyID
        if cursorToy then
            ClearCursor()
            local fromSlot = Toys._draggedFromQuickSlot
            Toys._draggedToyID = nil
            Toys._draggedFromQuickSlot = nil
            local targetIdx = slotBtn.slotIndex
            local pinned = Toys:GetPinnedToys()
            local oldTargetToy = pinned[targetIdx]

            if fromSlot and fromSlot ~= targetIdx then
                -- Dragged from one slot to another -> swap the two slots!
                pinned[fromSlot] = oldTargetToy
                pinned[targetIdx] = cursorToy
            else
                -- Dragged from grid/bags -> if cursorToy was already in another slot, clear it
                for i = 1, (Toys.MAX_PINNED_TOYS or 5) do
                    if i ~= targetIdx and pinned[i] == cursorToy then
                        pinned[i] = nil
                        break
                    end
                end
                -- Directly replace the target slot!
                pinned[targetIdx] = cursorToy
            end

            f:UpdateQuickSlots()
            if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
            f:UpdateToyButtons()
        end
    end

    for i = 1, (Toys.MAX_PINNED_TOYS or 5) do
        local slot = CreateFrame("Button", "$parent_QuickSlot" .. i, quickBar, "SecureActionButtonTemplate, BackdropTemplate")
        slot:SetSize(36, 36)
        slot:SetFrameLevel(530)
        slot:SetPoint("TOP", quickBar, "TOP", 0, -((i - 1) * 40))
        slot:RegisterForClicks("AnyDown", "AnyUp")
        slot:RegisterForDrag("LeftButton")
        slot:SetAttribute("type", "toy")
        slot:SetAttribute("type1", "toy")
        slot.slotIndex = i

        slot:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        slot:SetBackdropColor(0.06, 0.06, 0.09, 0.9)
        slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.7)

        local slotIcon = slot:CreateTexture(nil, "ARTWORK")
        slotIcon:SetPoint("TOPLEFT", 3, -3)
        slotIcon:SetPoint("BOTTOMRIGHT", -3, 3)
        slotIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slotIcon:Hide()
        slot.icon = slotIcon

        local emptyTxt = slot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        emptyTxt:SetPoint("CENTER")
        emptyTxt:SetText("+" .. i)
        slot.emptyTxt = emptyTxt

        local hl = slot:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")

        local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        cd:SetPoint("TOPLEFT", 3, -3)
        cd:SetPoint("BOTTOMRIGHT", -3, 3)
        cd:Hide()
        slot.Cooldown = cd

        slot:SetScript("PreClick", function(self, button)
            local cursorType = GetCursorInfo()
            if cursorType or Toys._draggedToyID or self._isDragging or button == "RightButton" then
                self:SetAttribute("type", nil)
                self:SetAttribute("type1", nil)
            elseif self.toyID then
                self:SetAttribute("type", "toy")
                self:SetAttribute("type1", "toy")
                self:SetAttribute("toy", self.toyID)
                self:SetAttribute("toy1", self.toyID)
            end
        end)

        slot:SetScript("PostClick", function(self, button)
            self._isDragging = nil
            if button == "RightButton" and self.slotIndex then
                local pinned = Toys:GetPinnedToys()
                pinned[self.slotIndex] = nil
                f:UpdateQuickSlots()
                if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
                f:UpdateToyButtons()
            elseif button == "LeftButton" and self.toyID then
                if C_ToyBox and C_ToyBox.UseToyByItemID then
                    pcall(C_ToyBox.UseToyByItemID, self.toyID)
                end
                if not InCombatLockdown() then
                    self:SetAttribute("type", "toy")
                    self:SetAttribute("type1", "toy")
                    self:SetAttribute("toy", self.toyID)
                    self:SetAttribute("toy1", self.toyID)
                end
            end
        end)

        slot:SetScript("OnDragStart", function(self)
            if self.toyID and not InCombatLockdown() then
                self._isDragging = true
                self:SetAttribute("type", nil)
                self:SetAttribute("type1", nil)
                C_Item.PickupItem(self.toyID)
                Toys._draggedToyID = self.toyID
                Toys._draggedFromQuickSlot = self.slotIndex
            end
        end)

        slot:SetScript("OnDragStop", function(self)
            self._isDragging = nil
        end)

        slot:SetScript("OnReceiveDrag", function(self)
            self:SetAttribute("type", nil)
            self:SetAttribute("type1", nil)
            HandleDropOnQuickSlot(self)
        end)

        slot:HookScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                local cursorToy = GetCursorToy() or Toys._draggedToyID
                if cursorToy then
                    HandleDropOnQuickSlot(self)
                end
            end
        end)

        slot:SetScript("OnEnter", function(self)
            local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
            if cfg.hideButtonTooltips then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.toyID then
                GameTooltip:SetToyByItemID(self.toyID)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFFFF4444Right-Click:|r Remove from Quick Slots", 0.9, 0.4, 0.4)
                GameTooltip:AddLine("|cFF88AAFFDrag:|r Reorder or replace", 0.6, 0.8, 1)
            else
                GameTooltip:AddLine("|cFFFFD900Quick Toy Slot #" .. self.slotIndex .. "|r")
                GameTooltip:AddLine("Drag & drop any toy here for quick access.", 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

        function slot:CheckCooldown()
            if self.toyID and self:IsShown() then
                local start, duration, enable = C_Item.GetItemCooldown(self.toyID)
                if start and start > 0 and duration and duration > 0 then
                    CooldownFrame_Set(self.Cooldown, start, duration, enable)
                    self.Cooldown:Show()
                else
                    self.Cooldown:Hide()
                end
            end
        end

        table.insert(f.QuickSlots, slot)
    end

    function f:UpdateQuickSlots()
        local pinned = Toys:GetPinnedToys()
        for i = 1, (Toys.MAX_PINNED_TOYS or 5) do
            local slot = f.QuickSlots[i]
            if slot then
                local toyID = pinned[i]
                slot.toyID = toyID
                if toyID then
                    local _, name = C_ToyBox.GetToyInfo(toyID)
                    local icon, stillMissing = Toys:GetToyIcon(toyID)
                    if stillMissing then Toys._toyIconsPending = true end
                    slot.icon:SetTexture(icon)
                    slot.icon:Show()
                    slot.emptyTxt:Hide()
                    slot:SetBackdropBorderColor(0.85, 0.70, 0.20, 0.9)
                    if not InCombatLockdown() then
                        slot:SetAttribute("type", "toy")
                        slot:SetAttribute("type1", "toy")
                        slot:SetAttribute("toy", toyID)
                        slot:SetAttribute("toy1", toyID)
                    end
                    slot:CheckCooldown()
                else
                    slot.icon:Hide()
                    slot.emptyTxt:Show()
                    slot.Cooldown:Hide()
                    slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.6)
                    if not InCombatLockdown() then
                        slot:SetAttribute("type", nil)
                        slot:SetAttribute("type1", nil)
                        slot:SetAttribute("toy", nil)
                        slot:SetAttribute("toy1", nil)
                    end
                end
            end
        end
    end

    -- ========================================================================
    -- MAIN TOY GRID
    -- ========================================================================
    local holder = CreateFrame("Frame", "$parent_Holder", f)
    holder:SetPoint("TOPLEFT", (conf.isSideBarShown and 144 or 10), -58)
    holder:SetPoint("BOTTOMRIGHT", -56, 8)
    f.ToyButtonHolderFrame = holder

    local toyScroll = CreateFrame("ScrollFrame", "$parent_ToyScroll", holder, "UIPanelScrollFrameTemplate")
    toyScroll:SetPoint("TOPLEFT", 0, 0)
    toyScroll:SetPoint("BOTTOMRIGHT", -16, 0)
    local toyChild = CreateFrame("Frame", nil, toyScroll)
    toyChild:SetSize(240, 200)
    toyScroll:SetScrollChild(toyChild)
    holder.ScrollChild = toyChild
    holder.ScrollFrame = toyScroll
    ApplyModernScroll(toyScroll)

    -- Said across the top of the grid, where the player is already looking.
    -- Nothing about the tiles changes when the dock is unlocked, so someone who
    -- forgot to lock it again just finds their toys have stopped working.
    local unlockedBanner = CreateFrame("Frame", nil, f, "BackdropTemplate")
    -- Lifted clear of the first row of tiles. There are only eight pixels
    -- between the button row and the grid, so it rides up into that gap rather
    -- than sitting on top of the icons.
    unlockedBanner:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 13)
    unlockedBanner:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 13)
    unlockedBanner:SetHeight(15)
    unlockedBanner:SetFrameLevel(f:GetFrameLevel() + 30)
    unlockedBanner:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    unlockedBanner:SetBackdropColor(0.35, 0.05, 0.03, 0.9)

    local unlockedText = unlockedBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unlockedText:SetPoint("CENTER", unlockedBanner, "CENTER", 0, 0)
    unlockedText:SetTextColor(1, 0.55, 0.45)
    unlockedText:SetText(L["TOYBOX_UNLOCKED_WARNING"]
        or "Toys Use Blocked While Unlocked")
    unlockedBanner:Hide()
    f.UnlockedBanner = unlockedBanner

    function f:UpdateUnlockedBanner()
        if self.UnlockedBanner then
            self.UnlockedBanner:SetShown(not conf.locked)
        end
    end
    f:UpdateUnlockedBanner()

    toyScroll:HookScript("OnScrollRangeChanged", function(self, xrange, yrange)
        if self.oxedMinimalScrollBar then
            self.oxedMinimalScrollBar:SetShown(yrange and yrange > 0)
        end
    end)

    -- Drag-to-add target onto the grid (adds at end)
    toyChild:EnableMouse(true)
    toyChild:SetScript("OnReceiveDrag", function()
        local cursorToy = GetCursorToy() or Toys._draggedToyID
        if cursorToy and selectedToyboxId and selectedToyboxId ~= "all" then
            ClearCursor()
            local ok, err = Toys:AddToyToBox(selectedToyboxId, cursorToy)
            if not ok and err then UIErrorsFrame:AddExternalErrorMessage(err) end
            Toys._draggedToyID = nil
            f:UpdateToyButtons()
        end
    end)
    toyChild:SetScript("OnMouseUp", function(_, btn)
        if btn == "LeftButton" then
            local cursorToy = GetCursorToy() or Toys._draggedToyID
            if cursorToy and selectedToyboxId and selectedToyboxId ~= "all" then
                ClearCursor()
                local ok, err = Toys:AddToyToBox(selectedToyboxId, cursorToy)
                if not ok and err then UIErrorsFrame:AddExternalErrorMessage(err) end
                Toys._draggedToyID = nil
                f:UpdateToyButtons()
            end
        end
    end)

    -- Cooldown periodic check loop
    local elapsedTimer = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        if isResizing then
            self:UpdateToyButtons()
        end
        elapsedTimer = elapsedTimer + elapsed
        if elapsedTimer >= 0.25 then
            elapsedTimer = 0
            if f.ToyButtons then
                for _, b in ipairs(f.ToyButtons) do
                    if b:IsShown() and b.id then
                        b:CheckCooldown()
                    end
                end
            end
            if f.QuickSlots then
                for _, slot in ipairs(f.QuickSlots) do
                    if slot:IsShown() and slot.toyID then
                        slot:CheckCooldown()
                    end
                end
            end
            if f.RandomHearthstoneButton and selectedHearthstoneId and selectedHearthstoneId > 0 then
                local start, duration, enable = C_Item.GetItemCooldown(selectedHearthstoneId)
                if start and start > 0 and duration and duration > 0 then
                    CooldownFrame_Set(f.RandomHearthstoneButton.Cooldown, start, duration, enable)
                    local remaining = math.max(0, math.floor(start + duration - GetTime()))
                    local mins = math.floor(remaining / 60)
                    local secs = remaining % 60
                    f.RandomHearthstoneButton.Timer:SetText(string.format("%02d:%02d", mins, secs))
                else
                    f.RandomHearthstoneButton.Cooldown:Hide()
                    f.RandomHearthstoneButton.Timer:SetText("")
                end
            end
        end
    end)

    -- ========================================================================
    -- MEMBER FUNCTIONS
    -- ========================================================================
    f.ToyButtons = {}
    Toys._dockButtons = f.ToyButtons

    function f:ToggleSideMenuBar(forceShow)
        if forceShow ~= nil then
            conf.isSideBarShown = forceShow
        else
            conf.isSideBarShown = not conf.isSideBarShown
        end

        if conf.isSideBarShown then
            f.SideMenuBar:Show()
            f.ToyButtonHolderFrame:SetPoint("TOPLEFT", 144, -58)
            f.ToyButtonHolderFrame:SetPoint("BOTTOMRIGHT", -56, 8)
            sideMenuBtn:SetText("Boxes ^")
        else
            f.SideMenuBar:Hide()
            f.ToyButtonHolderFrame:SetPoint("TOPLEFT", 10, -58)
            f.ToyButtonHolderFrame:SetPoint("BOTTOMRIGHT", -56, 8)
            sideMenuBtn:SetText("Boxes v")
        end
        f:RefreshSideMenu()
        f:UpdateToyButtons()
    end

    function f:RefreshSideMenu()
        local boxes = Toys:GetToyBoxes()
        sideChild.buttons = sideChild.buttons or {}
        for _, b in ipairs(sideChild.buttons) do b:Hide() end

        local y = 0
        for i, box in ipairs(boxes) do
            local b = sideChild.buttons[i]
            if not b then
                b = CreateFrame("Button", nil, sideChild)
                b:SetSize(102, 24)

                local bg = b:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.12, 0.12, 0.15, 0.6)
                b.bg = bg

                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 0.82, 0, 0.25)

                local icon = b:CreateTexture(nil, "ARTWORK")
                icon:SetSize(18, 18)
                icon:SetPoint("LEFT", 3, 0)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.icon = icon

                local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                txt:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                txt:SetPoint("RIGHT", -2, 0)
                txt:SetJustifyH("LEFT")
                txt:SetWordWrap(false)
                b.txt = txt

                b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                b:SetScript("OnClick", function(self, mouseButton)
                    if mouseButton == "RightButton" and self.boxId and self.boxId ~= "all" then
                        if Toys.ShowBoxEditorDialog then
                            Toys:ShowBoxEditorDialog(self.boxId)
                        end
                    else
                        selectedToyboxId = self.boxId
                        if f.TitleText then
                            f.TitleText:SetText("ToyBox: " .. self.boxName)
                        end
                        f:RefreshSideMenu()
                        f:UpdateToyButtons()
                        f:SelectNewRandomToy()
                    end
                end)

                b:SetScript("OnEnter", function(self)
                    local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
                    if cfg.hideButtonTooltips then return end
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
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Drag target onto sidebar box
                local function HandleDropOnDockSidebar(selfBtn)
                    local cursorToy = GetCursorToy() or Toys._draggedToyID
                    if cursorToy and selfBtn.boxId and selfBtn.boxId ~= "all" then
                        ClearCursor()
                        Toys:AddToyToBox(selfBtn.boxId, cursorToy)
                        Toys._draggedToyID = nil
                        f:UpdateToyButtons()
                    end
                end

                b:EnableMouse(true)
                b:SetScript("OnReceiveDrag", function(self)
                    HandleDropOnDockSidebar(self)
                end)
                b:HookScript("OnMouseUp", function(self, button)
                    if button == "LeftButton" then
                        local cursorToy = GetCursorToy() or Toys._draggedToyID
                        if cursorToy then
                            HandleDropOnDockSidebar(self)
                        end
                    end
                end)

                table.insert(sideChild.buttons, b)
            end

            b:SetPoint("TOPLEFT", 1, -y - 4)
            b.boxId = box.id
            b.boxName = box.name
            
            local resolvedIcon = Toys:GetBoxIconTexture(box.icon)
            b.icon:SetTexture(resolvedIcon or 135933)
            b.txt:SetText(box.name)

            if box.id == selectedToyboxId then
                b.bg:SetColorTexture(0.35, 0.28, 0.06, 0.9)
                b.txt:SetTextColor(1, 0.85, 0.2)
            else
                b.bg:SetColorTexture(0.08, 0.08, 0.10, 0.4)
                b.txt:SetTextColor(0.85, 0.85, 0.85)
            end

            b:Show()
            y = y + 26
        end
        sideChild:SetHeight(math.max(y, 140))
    end

    function f:CreateToyButton()
        local b = CreateFrame("Button", nil, holder.ScrollChild, "SecureActionButtonTemplate")
        local sz = conf.iconSize or 36
        b:SetSize(sz, sz)
        -- Both edges, exactly like the quick slots on the right. A secure button
        -- fires on key-down or key-up depending on the client's
        -- ActionButtonUseKeyDown setting, so registering only "...Up" left the
        -- secure handler unreachable -- the attributes were armed correctly and
        -- the click still did nothing.
        b:RegisterForClicks("AnyDown", "AnyUp")
        b:SetAttribute("type", "toy")

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = icon

        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
        hl:SetBlendMode("ADD")

        local cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        cd:Hide()
        b.Cooldown = cd

        -- No attribute juggling in PreClick.
        --
        -- It used to flip "type" on every click, which meant the button was
        -- only ever armed for a split second and any early return -- a stale
        -- drag marker, something on the cursor -- left it disarmed with nothing
        -- to put it back. The attributes are set once when the panel is drawn
        -- and when the lock is toggled, so a tile is either armed or it is not.
        b:SetScript("PreClick", function(self, button)
        end)

        b:SetScript("PostClick", function(self, button, down)
            -- Both edges are registered now, so this runs twice per click.
            -- Act on the release only, or every action would double up.
            if down then return end

            self._isDragging = nil

            -- The quick slots on the right do this and they work, so the grid
            -- does it too: use the toy outright rather than trusting the secure
            -- attribute alone. Out of combat this is allowed, and it is what
            -- makes a click land every time instead of only when the attributes
            -- happen to be armed.
            if conf.locked and button == "LeftButton" and type(self.id) == "number" then
                if C_ToyBox and C_ToyBox.UseToyByItemID then
                    pcall(C_ToyBox.UseToyByItemID, self.id)
                end
            end

            -- The macro text only carries the toys and spells. Sound, animation,
            -- emote and chat are not macro commands, so a mix clicked here would
            -- fire its toy and stay silent without this.
            if self._kind == "macro" and type(self.id) == "string" then
                local mixData = OxedHub.db and OxedHub.db.profile
                    and OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[self.id]
                if mixData and OxedHub.MacroRegistry then
                    OxedHub.MacroRegistry:PlayMixActions(mixData)
                end
            end
        end)

        -- Drag and drop support for reordering inside the floating dock
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            -- Rearranging belongs to the unlocked state, the mirror of the click
            -- rule in PreClick: locked uses the tile, unlocked moves it.
            if conf.locked then return end

            -- Only real items can go on the cursor; a mix has nothing to pick up.
            if type(self.id) == "number" and not InCombatLockdown() then
                self._isDragging = true
                self:SetAttribute("type", nil)
                C_Item.PickupItem(self.id)
                Toys._draggedToyID = self.id
                Toys._draggedFromBoxId = selectedToyboxId
            end
        end)

        b:SetScript("OnDragStop", function(self)
            self._isDragging = nil

            -- Clear the drag marker even when the toy was dropped on nothing.
            -- Left set, PreClick keeps stripping the type off every button and
            -- the whole panel goes dead until a reload. Deferred by a frame so
            -- the drop handlers, which run first, still see it.
            C_Timer.After(0, function() Toys._draggedToyID = nil end)
        end)

        local function HandleDropOnDockToy(targetBtn)
            local cursorToyID = GetCursorToy() or Toys._draggedToyID
            -- The mixes box is assembled from the saved mixes rather than
            -- stored, so there is nothing for a dropped toy to be written into.
            if cursorToyID and targetBtn.id and selectedToyboxId
                and selectedToyboxId ~= "all" and selectedToyboxId ~= "mixes" then
                ClearCursor()
                targetBtn._isDragging = nil
                targetBtn:SetAttribute("type", nil)
                if cursorToyID == targetBtn.id then
                    Toys._draggedToyID = nil
                    C_Timer.After(0.05, function()
                        if not InCombatLockdown() then targetBtn:SetAttribute("type", "toy") end
                    end)
                    return
                end
                if Toys:IsToyInBox(selectedToyboxId, cursorToyID) then
                    Toys:ReorderToyInBox(selectedToyboxId, cursorToyID, targetBtn.id)
                else
                    Toys:InsertToyInBox(selectedToyboxId, cursorToyID, targetBtn.id)
                end
                Toys._draggedToyID = nil
                f:UpdateToyButtons()
            end
        end

        b:SetScript("OnReceiveDrag", function(self)
            self:SetAttribute("type", nil)
            HandleDropOnDockToy(self)
        end)

        b:SetScript("OnEnter", function(self)
            -- A mix slot holds a name, and the toy tooltip getter only takes an
            -- item ID: handing it a string is what produced the "outside of
            -- expected range" error from Blizzard's tooltip code.
            if type(self.id) == "string" then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.id, 1, 0.85, 0.2)
                GameTooltip:AddLine("Toy mix", 0.7, 0.7, 0.7)
                GameTooltip:Show()
                return
            end

            if self.id then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetToyByItemID(self.id)
                local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
                if not cfg.hideButtonTooltips then
                    GameTooltip:AddLine(" ")
                    if selectedToyboxId ~= "all" then
                        GameTooltip:AddLine("|cFF00FF00Drag onto other toys to change order|r", 0.4, 1.0, 0.4)
                        GameTooltip:AddLine("|cFFFF5555Right-Click: Remove from box|r", 1, 0.3, 0.3)
                    end
                end
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        b:HookScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                local cursorToyID = GetCursorToy() or Toys._draggedToyID
                if cursorToyID then
                    self:SetAttribute("type", nil)
                    if cursorToyID ~= self.id then
                        HandleDropOnDockToy(self)
                    else
                        ClearCursor()
                        Toys._draggedToyID = nil
                    end
                end
            elseif button == "RightButton" and self.id and selectedToyboxId and selectedToyboxId ~= "all" then
                Toys:RemoveToyFromBox(selectedToyboxId, self.id)
                f:UpdateToyButtons()
            end
        end)

        function b:CheckCooldown()
            -- A mix has no item cooldown of its own, and the getter only takes
            -- an item ID.
            if type(self.id) == "number" and self:IsShown() then
                local start, duration, enable = C_Item.GetItemCooldown(self.id)
                if start and start > 0 and duration and duration > 0 then
                    CooldownFrame_Set(self.Cooldown, start, duration, enable)
                    self.Cooldown:Show()
                else
                    self.Cooldown:Hide()
                end
            end
        end

        return b
    end

    function f:UpdateToyButtons()
        local box = Toys:GetToyBox(selectedToyboxId) or Toys:GetToyBox("all") or Toys:GetToyBox("favorites")
        if not box then return end

        local cfg = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.toyBoxSettings or {}
        if f.RandomHearthstoneButton then
            f.RandomHearthstoneButton:SetShown(cfg.showDockHearthstone ~= false)
        end
        if f.RandomToyButton then
            f.RandomToyButton:SetShown(cfg.showDockRandomToy ~= false)
        end

        if f.TitleText then
            f.TitleText:SetText("ToyBox: " .. (box.name or "All Toys"))
        end

        for _, b in ipairs(f.ToyButtons) do b:Hide() b.id = nil end

        -- Same search + pin treatment the addon grid gets.
        local toysList = Toys.FilterToyList
            and Toys:FilterToyList(box.toys or {}, Toys._dockSearch)
            or (box.toys or {})
        if Toys.ApplyPinnedToys then
            toysList = Toys:ApplyPinnedToys(toysList, box.id)
        end
        local numToys = #toysList

        while #f.ToyButtons < numToys do
            table.insert(f.ToyButtons, f:CreateToyButton())
        end

        local iconSz = cfg.dockIconSize or conf.iconSize or 36
        -- Spacing between toys, configurable; 3 was the old fixed value.
        local margin = cfg.dockSpacing or 3
        local availW = holder:GetWidth()
        if not availW or availW <= 50 then
            availW = f:GetWidth() - (conf.isSideBarShown and 110 or 20)
        end
        local gridW = math.max(50, availW - 14)
        local iconsPerRow = math.max(1, math.floor((gridW + margin) / (iconSz + margin)))

        local row = 0
        local col = 0

        for i, toyID in ipairs(toysList) do
            local b = f.ToyButtons[i]
            col = (i - 1) % iconsPerRow
            row = math.floor((i - 1) / iconsPerRow)

            b:SetSize(iconSz, iconSz)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", holder.ScrollChild, "TOPLEFT", col * (iconSz + margin) + 4, -row * (iconSz + margin) - 4)

            -- A mix arrives as its name, not an item ID, and is driven by macro
            -- text rather than the "toy" attribute -- the same way ActionHub
            -- runs one. GetToyInfo would raise on the string, so the two kinds
            -- are separated here.
            if type(toyID) == "string" then
                local mixData = OxedHub.db and OxedHub.db.profile
                    and OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[toyID]

                b.id = toyID
                b._kind = "macro"

                -- Attributes cannot be changed in combat. The button keeps
                -- whatever it was last given, which stays valid.
                if not InCombatLockdown() then
                    local body = (mixData and Toys.GetMixMacroText
                        and Toys:GetMixMacroText(mixData, true)) or ""
                    b:SetAttribute("type", conf.locked and "macro" or nil)
                    b:SetAttribute("type1", conf.locked and "macro" or nil)
                    b:SetAttribute("macrotext", body)
                    b:SetAttribute("macrotext1", body)
                end

                -- Split icon, the same shape My Mixes uses: one tile showing
                -- both halves of the mix rather than only its first slot.
                Toys:ApplyMixSplitIcon(b, toyID, iconSz)
                if b.Cooldown then b.Cooldown:Hide() end
                b:Show()
            else

            b.id = toyID
            b._kind = "toy"
            Toys:ClearMixSplitIcon(b)
            if not InCombatLockdown() then
                b:SetAttribute("type", conf.locked and "toy" or nil)
                b:SetAttribute("type1", conf.locked and "toy" or nil)
                b:SetAttribute("toy", toyID)
                b:SetAttribute("toy1", toyID)
            end

            local toyIcon, stillMissing = Toys:GetToyIcon(toyID)
            if stillMissing then Toys._toyIconsPending = true end
            b.icon:SetTexture(toyIcon)
            b:CheckCooldown()
            b:Show()
            end
        end

        if f.UpdateQuickSlots then
            f:UpdateQuickSlots()
        end

        local totalH = (row + 1) * (iconSz + margin) + 16
        holder.ScrollChild:SetHeight(math.max(totalH, 120))
    end

    -- Both rollers change a secure attribute, which the client forbids in
    -- combat.  Re-rolling is only a convenience; the attribute already set
    -- stays valid, so skipping it mid-fight costs nothing.
    function f:SelectNewRandomToy()
        if InCombatLockdown() then return end
        local nextToy = Toys:GetRandomToyFromBox(selectedToyboxId)
        -- The mixes box yields names, which the "toy" attribute cannot use.
        -- Roll over the whole collection instead of arming a dead button.
        if type(nextToy) ~= "number" then
            nextToy = Toys:GetRandomToyFromBox("all")
        end
        if type(nextToy) == "number" then
            -- Both forms: "toy" is the fallback, "toy1" is what a left click
            -- actually reads, and a button carrying only one of them stays
            -- inert for some click setups.
            f.RandomToyButton:SetAttribute("toy", nextToy)
            f.RandomToyButton:SetAttribute("toy1", nextToy)
        end
    end

    function f:SelectNewRandomHearthstone()
        if InCombatLockdown() then return end
        local hsList = Toys:GetUsableHearthstones()
        if #hsList > 0 then
            local pick = hsList[math.random(1, #hsList)]
            selectedHearthstoneId = pick
            f.RandomHearthstoneButton:SetAttribute("toy", pick)
            f.RandomHearthstoneButton:SetAttribute("toy1", pick)
        end
    end

    -- Initial load
    f:ToggleSideMenuBar(conf.isSideBarShown)
    f:SelectNewRandomHearthstone()
    f:SelectNewRandomToy()

    f:Hide()
    self.ToyboxFrame = f
    return f
end

function Toys:ToggleToyDock(boxId)
    local f = self:GetOrCreateToyboxFrame()
    if boxId and boxId ~= "" then
        selectedToyboxId = boxId
    end
    local profile = OxedHub.db and OxedHub.db.profile
    if f:IsShown() or (self.MiniButton and self.MiniButton:IsShown()) then
        f:Hide()
        if self.MiniButton then self.MiniButton:Hide() end
        if profile then
            profile.toyBoxDockState = "hidden"
            if profile.toyBoxSettings then
                profile.toyBoxSettings.showOnScreenDock = false
            end
        end
    else
        self:ExpandToyDock()
    end
    return f:IsShown()
end

function Toys:RefreshToyDock()
    if self.ToyboxFrame and self.ToyboxFrame:IsShown() then
        self.ToyboxFrame:RefreshSideMenu()
        self.ToyboxFrame:UpdateToyButtons()
    end
end

-- ============================================================================
-- RESTORE DOCK STATE ON RELOAD / LOGIN
-- ============================================================================
local dockEventFrame = CreateFrame("Frame")
dockEventFrame:RegisterEvent("PLAYER_LOGIN")
dockEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
dockEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
dockEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
dockEventFrame:SetScript("OnEvent", function(self, event)
    if event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        local f = Toys.ToyboxFrame
        if f and f:IsShown() and f.QuickSlots then
            for _, slot in ipairs(f.QuickSlots) do
                if slot.CheckCooldown then slot:CheckCooldown() end
            end
        end
        return
    end

    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(0.5, function()
        local profile = OxedHub.db and OxedHub.db.profile
        if not profile then return end
        local state = profile.toyBoxDockState
        local cfg = profile.toyBoxSettings or {}
        if state == "expanded" or (state == nil and cfg.showOnScreenDock == true) then
            Toys:ExpandToyDock()
        elseif state == "minimized" then
            local mb = Toys:GetOrCreateMiniButton()
            if cfg.miniIconAuto == false and cfg.miniIcon then
                mb.icon:SetTexture(Toys:GetBoxIconTexture(cfg.miniIcon) or 135933)
            else
                local box = Toys:GetToyBox(selectedToyboxId)
                if box and box.icon then
                    mb.icon:SetTexture(Toys:GetBoxIconTexture(box.icon))
                else
                    mb.icon:SetTexture(135933)
                end
            end
            mb:Show()
            Toys:UpdateQuickToyBar()
        elseif cfg.showOnScreenDock == true then
            Toys:ExpandToyDock()
        end
    end)
end)

-- ============================================================================
-- KEY BINDINGS
-- Names shown in the game's Key Bindings panel, plus the globals Bindings.xml
-- calls.  Bindings.xml is loaded by the client automatically from the addon
-- root, so it needs no TOC entry.
-- ============================================================================
BINDING_HEADER_OXEDHUB_HEADER = "Oxed Hub"
BINDING_NAME_OXEDHUB_TOGGLE_TOYBOX = "Toggle ToyBox Panel"
BINDING_NAME_OXEDHUB_RANDOM_TOY = "Use Random Toy"
BINDING_NAME_OXEDHUB_RANDOM_HEARTHSTONE = "Use Random Hearthstone"

function OxedHub_ToggleToyDock()
    if OxedHub.Toys and OxedHub.Toys.ToggleToyDock then
        OxedHub.Toys:ToggleToyDock()
    end
end

-- The random buttons are secure frames, so a binding cannot cast through them.
-- Fire the toy directly instead; C_ToyBox.UseToyByItemID is callable from a
-- hardware event, which a key binding is.
function OxedHub_UseRandomToy()
    local Toys = OxedHub.Toys
    if not Toys then return end
    local boxId = (Toys.ToyboxFrame and Toys.ToyboxFrame.selectedBoxId) or "all"
    local toyId = Toys.GetRandomToyFromBox and Toys:GetRandomToyFromBox(boxId)
    if toyId and C_ToyBox and C_ToyBox.UseToyByItemID then
        pcall(C_ToyBox.UseToyByItemID, toyId)
    end
end

function OxedHub_UseRandomHearthstone()
    local Toys = OxedHub.Toys
    if not Toys or not Toys.GetUsableHearthstones then return end
    local list = Toys:GetUsableHearthstones()
    if #list > 0 and C_ToyBox and C_ToyBox.UseToyByItemID then
        pcall(C_ToyBox.UseToyByItemID, list[math.random(1, #list)])
    end
end

-- Pick which way the panel opens from the minimised button.
function Toys:ShowExpandDirectionMenu(anchorFrame)
    local profile = OxedHub.db and OxedHub.db.profile
    local cfg = (profile and profile.toyBoxSettings) or {}
    local current = cfg.expandDirection or "auto"

    local menu = { 
        { text = "Open direction", isTitle = true, notCheckable = true } 
    }
    for _, def in ipairs(self.EXPAND_DIRECTIONS) do
        table.insert(menu, {
            text = def.label,
            checked = (current == def.key),
            func = function()
                if profile then
                    profile.toyBoxSettings = profile.toyBoxSettings or {}
                    profile.toyBoxSettings.expandDirection = def.key
                end
            end,
        })
    end

    table.insert(menu, { text = " ", isTitle = true, notCheckable = true })
    table.insert(menu, {
        text = "Clear 5 Quick Slots",
        notCheckable = true,
        func = function()
            if profile then
                profile.toyBoxPinned = {}
                Toys:UpdateQuickToyBar()
                if Toys.RefreshToyBoxesUI then Toys:RefreshToyBoxesUI() end
                if Toys.ToyboxFrame and Toys.ToyboxFrame:IsShown() then
                    Toys.ToyboxFrame:UpdateToyButtons()
                end
            end
        end,
    })

    if not self._dirMenu then
        self._dirMenu = CreateFrame("Frame", "OxedHubToyDirMenu", UIParent, "UIDropDownMenuTemplate")
    end

    if EasyMenu then
        EasyMenu(menu, self._dirMenu, anchorFrame or "cursor", 0, 0, "MENU")
    else
        UIDropDownMenu_Initialize(self._dirMenu, function()
            for _, item in ipairs(menu) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.func = item.func
                info.isTitle = item.isTitle
                info.checked = item.checked
                info.notCheckable = item.notCheckable
                UIDropDownMenu_AddButton(info)
            end
        end)
        ToggleDropDownMenu(1, nil, self._dirMenu, anchorFrame or "cursor", 0, 0)
    end
end

function Toys:UpdateQuickToyBar()
    if self.ToyboxFrame and self.ToyboxFrame.UpdateQuickSlots then
        self.ToyboxFrame:UpdateQuickSlots()
    end
end
