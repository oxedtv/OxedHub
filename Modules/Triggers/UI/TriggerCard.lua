local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

local function DeepCopy(original)
    local copy = {}
    for k, v in pairs(original) do
        if type(v) == "table" then
            copy[k] = DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

function Triggers:CreateTriggerCard(parent, trigger)
    local card = CreateFrame("Frame", "OxedHubTriggerCard" .. (trigger.id:gsub("%s+", ""):gsub("-", "")), parent)
    card:SetHeight(440)
    
    -- Background removed as requested

    -- Replaced ornate border with a simple top line
    -- Parent it to the tab (bypassing ScrollFrame clipping) so it can extend into the margins
    local tab = parent:GetParent() and parent:GetParent():GetParent() or parent
    local topLine = tab:CreateTexture(nil, "ARTWORK")
    topLine:SetPoint("TOPLEFT", card, "TOPLEFT", -14, -4)
    topLine:SetPoint("TOPRIGHT", card, "TOPRIGHT", 21, -4)
    topLine:SetHeight(2)
    topLine:SetColorTexture(1, 0.82, 0, 0.05) -- Changed layer to ARTWORK and opacity to 0.05 so it's visible on top of background
    topLine:Show()
    card.topLine = topLine

    card:HookScript("OnShow", function() topLine:Show() end)
    card:HookScript("OnHide", function() topLine:Hide() end)
    
    card.triggerId = trigger.id
    trigger.activeTab = trigger.activeTab or "setup"
    
    -- Header with ornate title bar and icon
    local titleBar = CreateFrame("Frame", nil, card)
    titleBar:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, 0)
    titleBar:SetHeight(28)
    titleBar:Hide() -- Hidden for new tabbed layout
    card.titleBar = titleBar

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleText:SetTextColor(1, 0.82, 0, 1)
    titleText:SetText("Trigger Rule")
    card.titleText = titleText

    -- Title bar gold accent line
    local titleLine = titleBar:CreateTexture(nil, "BACKGROUND")
    titleLine:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 2, 0)
    titleLine:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", -2, 0)
    titleLine:SetHeight(2)
    titleLine:SetColorTexture(1, 0.82, 0, 0.5)

    -- Name input row
    local nameLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -18)
    nameLabel:SetTextColor(1, 0.82, 0, 1)
    nameLabel:SetText(L["TRIGGER_RULE_NAME"] or "Rule Name:")
    
    local nameInput = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    nameInput:SetSize(240, 22)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -2)
    nameInput:SetAutoFocus(false)
    nameInput:SetText(trigger.name or "")
    nameInput:SetScript("OnTextChanged", function(self, isUserInput)
        trigger.name = self:GetText()
        -- Update title
        if titleText then
            titleText:SetText(trigger.name ~= "" and trigger.name or "Trigger Rule")
        end
        if isUserInput then Triggers.ShowAutoSaved(card) end
    end)
    card.nameInput = nameInput
    card.nameLabel = nameLabel

    -- Modern WoW-Style side tabs using PetList atlases
    local TRIGGER_SIDE_TAB_WIDTH = 28
    local TRIGGER_SIDE_TAB_HEIGHT = 90
    local TRIGGER_SIDE_TAB_GAP = 4

    local sideTabContainer = CreateFrame("Frame", nil, card)
    sideTabContainer:SetPoint("TOPLEFT", card, "TOPRIGHT", -10, -22)
    sideTabContainer:SetWidth(TRIGGER_SIDE_TAB_WIDTH + 4)
    sideTabContainer:SetHeight((TRIGGER_SIDE_TAB_HEIGHT * 3) + (TRIGGER_SIDE_TAB_GAP * 2))
    sideTabContainer:SetFrameStrata("TOOLTIP")
    sideTabContainer:SetFrameLevel(card:GetFrameLevel() + 120)
    card.sideTabContainer = sideTabContainer

    local sideTabButtons = {}

    local function CreateVerticalTab(label, tabKey)
        local tab = CreateFrame("Button", nil, sideTabContainer)
        tab:SetSize(TRIGGER_SIDE_TAB_WIDTH, TRIGGER_SIDE_TAB_HEIGHT)
        tab:SetFrameStrata("TOOLTIP")
        tab:SetFrameLevel(sideTabContainer:GetFrameLevel() + 20)
        tab.tabKey = tabKey

        -- PetList-style background
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints()
        tab.bg:SetAtlas("PetList-ButtonBackground")
        tab.bg:SetVertexColor(0.6, 0.6, 0.6, 0.6)

        -- Selected overlay
        tab.selected = tab:CreateTexture(nil, "OVERLAY")
        tab.selected:SetAllPoints()
        tab.selected:SetAtlas("PetList-ButtonSelect")
        tab.selected:SetVertexColor(1, 0.82, 0, 0.6)
        tab.selected:Hide()

        -- Highlight
        tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
        tab.highlight:SetAllPoints()
        tab.highlight:SetAtlas("PetList-ButtonHighlight")

        -- Label texture (vertical icon)
        tab.labelTex = tab:CreateTexture(nil, "OVERLAY")
        tab.labelTex:SetSize(14, 64)
        tab.labelTex:SetPoint("CENTER", tab, "CENTER", 0, 0)
        if label == "Settings" then
            tab.labelTex:SetTexture("Interface\\Icons\\Spell_arcane_blast")
        elseif label == "Zones" then
            tab.labelTex:SetTexture("Interface\\Icons\\INV_Misc_Map01")
        else
            tab.labelTex:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_01")
        end
        tab.labelTex:SetTexCoord(0.1, 0.9, 0.1, 0.9)

        tab:SetScript("OnEnter", function(self)
            if trigger.activeTab ~= self.tabKey then
                self.bg:SetVertexColor(0.8, 0.7, 0.3, 0.8)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if card.RefreshSideTabs then
                card.RefreshSideTabs()
            end
        end)
        tab:SetScript("OnClick", function(self)
            trigger.activeTab = self.tabKey
            Triggers:LayoutTriggerCard(card)
        end)

        table.insert(sideTabButtons, tab)
        return tab
    end

    local function ApplyVerticalLayout(tabFrame)
        local previousButton = nil
        for i, tabButton in ipairs(sideTabButtons) do
            tabButton:ClearAllPoints()
            if i == 1 then
                tabButton:SetPoint("TOP", tabFrame, "TOP", 0, 0)
            else
                tabButton:SetPoint("TOP", previousButton, "BOTTOM", 0, -TRIGGER_SIDE_TAB_GAP)
            end
            previousButton = tabButton
        end
    end

    local function RefreshSideTabs()
        for _, tab in ipairs(sideTabButtons) do
            local isActive = (trigger.activeTab == tab.tabKey)
            if isActive then
                tab.selected:Show()
                tab.bg:SetVertexColor(0.8, 0.72, 0.2, 0.85)
                tab.labelTex:SetVertexColor(1, 1, 1, 1)
            else
                tab.selected:Hide()
                tab.bg:SetVertexColor(0.4, 0.4, 0.4, 0.5)
                tab.labelTex:SetVertexColor(0.7, 0.7, 0.7, 0.8)
            end
        end
    end

    card.setupTab = CreateVerticalTab("Settings", "setup")
    card.zoneTab = CreateVerticalTab("Zones", "zone")
    card.advancedTab = CreateVerticalTab("Advanced", "advanced")
    ApplyVerticalLayout(sideTabContainer)
    card.RefreshSideTabs = RefreshSideTabs
    RefreshSideTabs()
    sideTabContainer:Hide()
    card.setupTab:Hide()
    card.zoneTab:Hide()
    card.advancedTab:Hide()

    -- Event dropdown (modern WowStyle1DropdownTemplate)
    local eventLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    eventLabel:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -8)
    eventLabel:SetTextColor(1, 0.82, 0, 1)
    eventLabel:SetText(L["TRIGGER_EVENT_TYPE"] or "Event Type:")

    local eventDropdown = CreateFrame("DropdownButton", nil, card, "WowStyle1DropdownTemplate")
    eventDropdown:SetPoint("TOPLEFT", eventLabel, "BOTTOMLEFT", 0, -2)
    eventDropdown:SetSize(220, 26)

    local function GetCurrentEventLabel()
        local val = trigger.event or "UNIT_SPELLCAST_SUCCEEDED"
        for _, et in ipairs(OxedHub.CONFIG.EVENT_TYPES) do
            if et.value == val then return et.label end
        end
        return val
    end
    eventDropdown:OverrideText(GetCurrentEventLabel())
    card.eventDropdown = eventDropdown
    card.eventLabel = eventLabel

    eventDropdown:SetupMenu(function(dropdown, rootDescription)
        for _, eventType in ipairs(OxedHub.CONFIG.EVENT_TYPES) do
            local btn = rootDescription:CreateRadio(
                eventType.label,
                function() return (trigger.event or "UNIT_SPELLCAST_SUCCEEDED") == eventType.value end,
                function()
                    trigger.event = eventType.value
                    if not Triggers:SupportsAdvancedMacros(trigger) and trigger.activeTab == "advanced" then
                        trigger.activeTab = "setup"
                    end
                    eventDropdown:OverrideText(eventType.label)
                    Triggers:RefreshTriggerCardConditions(card, trigger)
                    Triggers:RefreshTriggerCard(card.triggerId)
                    Triggers:RefreshTriggersList()
                    Triggers.ShowAutoSaved(card)
                end,
                eventType.value
            )
            
        end
    end)
    
    -- Modern Settings-style section box
    local function CreateSectionBox(parent, text, description, anchorFrame, yOffset)
        local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        box:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        box:SetBackdropColor(0, 0, 0, 0.4)
        box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
        
        local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(text)
        label:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)
        label:SetTextColor(1, 0.82, 0, 1)

        local descLabel = nil
        if description then
            descLabel = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            descLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
            descLabel:SetText(description)
            descLabel:SetTextColor(0.6, 0.6, 0.6, 1)
        end
        
        box:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, yOffset or -10)
        box:SetPoint("RIGHT", parent, "RIGHT", -10, 0)
        
        local innerFrame = CreateFrame("Frame", nil, box)
        innerFrame:SetPoint("TOPLEFT", descLabel or label, "BOTTOMLEFT", 0, -12)
        innerFrame:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        
        return box, innerFrame, label, descLabel
    end

    -- Conditions area with section header
    local conditionsBox, conditionsFrame, conditionsLabel, conditionsDescLabel = CreateSectionBox(card, "Conditions", "Define the requirements that must be met for this trigger to execute.", eventDropdown, -10)
    conditionsFrame:SetHeight(60)
    card.conditionsBox = conditionsBox
    card.conditionsFrame = conditionsFrame
    card.conditionsLabel = conditionsLabel
    card.conditionsDescLabel = conditionsDescLabel
    
    -- Actions area with section header
    local actionsBox, actionsFrame, actionsLabel, actionsDescLabel = CreateSectionBox(card, "Actions", "Choose the sounds, animations, and emotes that will play when triggered.", conditionsBox, -10)
    actionsFrame:SetHeight(150)
    self:CreateActionsUI(actionsFrame, trigger)
    card.actionsBox = actionsBox
    card.actionsFrame = actionsFrame
    card.actionsLabel = actionsLabel
    card.actionsDescLabel = actionsDescLabel
    
    -- Zone restrictions
    local zoneLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    zoneLabel:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -10)
    zoneLabel:SetText("Only play in these zones:")
    
    local zoneFrame = CreateFrame("Frame", nil, card)
    zoneFrame:SetPoint("TOPLEFT", zoneLabel, "BOTTOMLEFT", 0, -5)
    zoneFrame:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    zoneFrame:SetHeight(35)
    self:CreateZoneUI(zoneFrame, trigger)
    card.zoneFrame = zoneFrame
    card.zoneLabel = zoneLabel

    local advancedFrame = CreateFrame("Frame", nil, card)
    advancedFrame:SetPoint("TOPLEFT", nameInput, "BOTTOMLEFT", 0, -10)
    advancedFrame:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    advancedFrame:SetHeight(35)
    self:CreateAdvancedMacroUI(advancedFrame, trigger)
    card.advancedFrame = advancedFrame

    -- Tips tab content: explanation of every event type
    local tipsFrame = CreateFrame("Frame", nil, card)
    tipsFrame:Hide()
    local tipsScroll = CreateFrame("ScrollFrame", nil, tipsFrame, "UIPanelScrollFrameTemplate")
    tipsScroll:SetPoint("TOPLEFT", tipsFrame, "TOPLEFT", 0, 0)
    tipsScroll:SetPoint("BOTTOMRIGHT", tipsFrame, "BOTTOMRIGHT", -28, 0)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(tipsScroll)
    end
    local tipsChild = CreateFrame("Frame", nil, tipsScroll)
    tipsChild:SetSize(560, 10)
    tipsScroll:SetScrollChild(tipsChild)

    -- Card factory (matches the About page style)
    local TIP_W = 440
    local function CreateTipCard(titleText, iconTexture, bodyText)
        local c = CreateFrame("Frame", nil, tipsChild, "BackdropTemplate")
        c:SetWidth(TIP_W)
        c:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 12, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        c:SetBackdropColor(0.04, 0.04, 0.05, 0.65)
        c:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.8)
        local icon = c:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -12)
        icon:SetTexture(iconTexture)
        local title = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        title:SetText(titleText)
        title:SetTextColor(1, 0.82, 0, 1)
        local body = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
        body:SetWidth(TIP_W - 24)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(3)
        body:SetText(bodyText)
        local h = 12 + 16 + 10 + (body:GetStringHeight() or 40) + 14
        c:SetHeight(h)
        return c, h
    end

    local cardDefs = {
        { L["TIPS_GETTING_STARTED_TITLE"] or "Getting Started", "Interface\\Icons\\INV_Misc_Book_09",
            L["TIPS_GETTING_STARTED_DESC"] or "" },

        { L["TIPS_COMBAT_SPELLS_TITLE"] or "Combat & Spells", "Interface\\Icons\\Ability_Warrior_BattleShout",
            L["TIPS_COMBAT_SPELLS_DESC"] or "" },

        { L["TIPS_ENCOUNTERS_TITLE"] or "Encounters & Group", "Interface\\Icons\\Achievement_Boss_Ragnaros",
            L["TIPS_ENCOUNTERS_DESC"] or "" },

        { L["TIPS_CHARACTER_STATE_TITLE"] or "Character State", "Interface\\Icons\\Spell_Holy_Resurrection",
            L["TIPS_CHARACTER_STATE_DESC"] or "" },

        { L["TIPS_PETS_TITLE"] or "Pets", "Interface\\Icons\\Ability_Hunter_BeastCall",
            L["TIPS_PETS_DESC"] or "" },

        { L["TIPS_HANDY_TIPS_TITLE"] or "Handy Tips", "Interface\\Icons\\INV_Misc_Note_01",
            L["TIPS_HANDY_TIPS_DESC"] or "" },
    }

    -- Two-column masonry: each card drops into whichever column is currently shorter
    local gap = 16
    local leftX, rightX = 4, 4 + TIP_W + gap
    local leftY, rightY = -4, -4
    for _, def in ipairs(cardDefs) do
        local c, h = CreateTipCard(def[1], def[2], def[3])
        if leftY >= rightY then
            c:SetPoint("TOPLEFT", tipsChild, "TOPLEFT", leftX, leftY)
            leftY = leftY - h - gap
        else
            c:SetPoint("TOPLEFT", tipsChild, "TOPLEFT", rightX, rightY)
            rightY = rightY - h - gap
        end
    end
    local totalH = math.max(math.abs(leftY), math.abs(rightY)) + 16
    tipsChild:SetSize(rightX + TIP_W + 4, totalH)
    card.tipsFrame = tipsFrame
    
    -- Enable toggle with WoW styling
    local enableCheck = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
    enableCheck:SetPoint("LEFT", nameInput, "RIGHT", 10, 0)
    enableCheck:SetSize(22, 22)
    enableCheck:SetChecked(trigger.enabled)
    enableCheck.text:SetText(L["TRIGGER_ENABLED"] or "Enabled")
    enableCheck.text:ClearAllPoints()
    enableCheck.text:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0)
    enableCheck.text:SetFontObject("GameFontNormalSmall")
    enableCheck.text:SetTextColor(1, 0.82, 0, 1)
    enableCheck:SetScript("OnClick", function(self)
        trigger.enabled = self:GetChecked()
        Triggers:InvalidateEnabledEventCache()
        Triggers.ShowAutoSaved(card)
    end)
    card.enableCheck = enableCheck
    

    
    -- Test button with gold styling
    local testBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    testBtn:SetFrameLevel(card:GetFrameLevel() + 10)
    -- Delete button (Top Right)
    local delBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    delBtn:SetPoint("BOTTOMRIGHT", card, "TOPRIGHT", 0, 12)
    delBtn:SetSize(80, 24)
    delBtn:SetText(L["BTN_DELETE"] or "Delete")
    delBtn:SetScript("OnClick", function()
        Triggers:DeleteTrigger(trigger.id)
    end)
    card.delBtn = delBtn

    -- Duplicate button (Top Right)
    local dupBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    dupBtn:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
    dupBtn:SetSize(80, 24)
    dupBtn:SetText(L["BTN_DUPLICATE"] or "Duplicate")
    dupBtn:SetScript("OnClick", function()
        Triggers:DuplicateTrigger(trigger.id)
    end)
    card.dupBtn = dupBtn

    -- Test button (Top Right)
    local testBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    testBtn:SetPoint("RIGHT", dupBtn, "LEFT", -10, 0)
    testBtn:SetSize(80, 24)
    testBtn:SetText(L["BTN_TEST"] or "Test")
    testBtn:SetScript("OnClick", function()
        local actions = trigger.actions or {}
        if actions.sound and actions.sound ~= "" and actions.sound ~= "None" then
            if OxedHub.Sounds then OxedHub.Sounds:Play(actions.sound) end
        end
        if actions.animation and actions.animation ~= "" and actions.animation ~= "None" then
            if OxedHub.Animations then OxedHub.Animations:Play(actions.animation) end
        end
        if actions.emote and actions.emote ~= "" and actions.emote ~= "None" then
            if OxedHub.Emotes then OxedHub.Emotes:DoEmote(actions.emote, actions.whisperTarget or false) end
        end
    end)
    card.testBtn = testBtn

    -- New button (Top Right) - create a new trigger without returning to the list
    local newBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    newBtn:SetPoint("RIGHT", testBtn, "LEFT", -10, 0)
    newBtn:SetSize(80, 24)
    newBtn:SetText(L["BTN_NEW"] or "New")
    newBtn:SetScript("OnClick", function()
        Triggers:CreateNewTrigger()
    end)
    card.newBtn = newBtn

    -- PanelTopTabButtonTemplate System (Bottom Left)
    local TAB_LINE_ALPHA = 0.25  -- <-- Change this to control the yellow line opacity (0 = invisible, 1 = fully visible)

    local function CreateTabButton(parent, id, text)
        local btn = CreateFrame("Button", "$parentTab" .. id, parent, "PanelTopTabButtonTemplate")
        btn:SetText(text)
        PanelTemplates_TabResize(btn, 15, nil, 70)

        -- Dim the built-in bottom "active" line textures from the template
        for _, region in ipairs({btn:GetRegions()}) do
            if region.IsObjectType and region:IsObjectType("Texture") then
                local w = region:GetWidth() or 0
                local h = region:GetHeight() or 0
                -- The bottom line textures are typically very wide and short (the horizontal bar)
                -- Target them by their position relative to the button bottom
                local _, relY = region:GetCenter()
                local btnBottom = btn:GetBottom()
                if btnBottom and relY and math.abs(relY - btnBottom) < 8 then
                    region:SetAlpha(TAB_LINE_ALPHA)
                    -- Store reference so UpdateTabLooks can retarget if needed
                    if not btn.lineRegions then btn.lineRegions = {} end
                    table.insert(btn.lineRegions, region)
                end
            end
        end

        return btn
    end

    local setupTabBtn = CreateTabButton(card, 1, L["TAB_SETTINGS"] or "Settings")
    setupTabBtn:SetFrameLevel(card:GetFrameLevel() + 10)
    setupTabBtn:SetPoint("BOTTOMLEFT", card, "TOPLEFT", 10, -4)
    card.setupTabBtn = setupTabBtn

    local zoneTabBtn = CreateTabButton(card, 2, L["TAB_ZONES"] or "Zones")
    zoneTabBtn:SetFrameLevel(card:GetFrameLevel() + 10)
    zoneTabBtn:SetPoint("LEFT", setupTabBtn, "RIGHT", 5, 0)
    card.zoneTabBtn = zoneTabBtn

    local tipsTabBtn = CreateTabButton(card, 4, L["TAB_TIPS"] or "Tips")
    tipsTabBtn:SetFrameLevel(card:GetFrameLevel() + 10)
    tipsTabBtn:SetPoint("LEFT", zoneTabBtn, "RIGHT", 5, 0)
    card.tipsTabBtn = tipsTabBtn

    local advancedTabBtn = CreateTabButton(card, 3, L["TAB_ADVANCED_MACROS"] or "Advanced Macros")
    advancedTabBtn:SetFrameLevel(card:GetFrameLevel() + 10)
    advancedTabBtn:SetPoint("LEFT", tipsTabBtn, "RIGHT", 5, 0)
    card.advancedTabBtn = advancedTabBtn

    local function UpdateTabLooks()
        local active = trigger.activeTab or "setup"
        local baseLevel = card:GetFrameLevel() + 10
        
        if active == "setup" then
            PanelTemplates_SelectTab(setupTabBtn)
            setupTabBtn:SetFrameLevel(baseLevel + 5)
        else
            PanelTemplates_DeselectTab(setupTabBtn)
            setupTabBtn:SetFrameLevel(baseLevel)
        end

        if active == "zone" then
            PanelTemplates_SelectTab(zoneTabBtn)
            zoneTabBtn:SetFrameLevel(baseLevel + 5)
        else
            PanelTemplates_DeselectTab(zoneTabBtn)
            zoneTabBtn:SetFrameLevel(baseLevel)
        end

        if active == "advanced" then
            PanelTemplates_SelectTab(advancedTabBtn)
            advancedTabBtn:SetFrameLevel(baseLevel + 5)
        else
            PanelTemplates_DeselectTab(advancedTabBtn)
            advancedTabBtn:SetFrameLevel(baseLevel)
        end

        if active == "tips" then
            PanelTemplates_SelectTab(tipsTabBtn)
            tipsTabBtn:SetFrameLevel(baseLevel + 5)
        else
            PanelTemplates_DeselectTab(tipsTabBtn)
            tipsTabBtn:SetFrameLevel(baseLevel)
        end
    end

    setupTabBtn:SetScript("OnClick", function()
        trigger.activeTab = "setup"
        UpdateTabLooks()
        Triggers:LayoutTriggerCard(card)
        Triggers:RefreshTriggersList()
    end)

    zoneTabBtn:SetScript("OnClick", function()
        trigger.activeTab = "zone"
        UpdateTabLooks()
        Triggers:LayoutTriggerCard(card)
        Triggers:RefreshTriggersList()
    end)

    tipsTabBtn:SetScript("OnClick", function()
        trigger.activeTab = "tips"
        UpdateTabLooks()
        Triggers:LayoutTriggerCard(card)
        Triggers:RefreshTriggersList()
    end)

    advancedTabBtn:SetScript("OnClick", function()
        trigger.activeTab = "advanced"
        UpdateTabLooks()
        Triggers:LayoutTriggerCard(card)
        Triggers:RefreshTriggersList()
    end)

    card.UpdateTabLooks = UpdateTabLooks
    UpdateTabLooks()
    
    -- Populate conditions based on event type
    self:RefreshTriggerCardConditions(card, trigger)
    
    return card
end

function Triggers:LayoutTriggerCard(card)
    if not card or not card.conditionsFrame then
        return
    end

    local trigger = OxedHub.db.profile.triggers[card.triggerId]
    local activeTab = trigger and trigger.activeTab or "setup"
    local hasAdvancedMacros = Triggers:SupportsAdvancedMacros(trigger)

    if activeTab == "advanced" and not hasAdvancedMacros then
        activeTab = "setup"
        if trigger then
            trigger.activeTab = "setup"
        end
    end
    
    if card.UpdateTabLooks then
        card.UpdateTabLooks()
    end
    
    if card.sideTabContainer then card.sideTabContainer:Hide() end
    if card.setupTab then card.setupTab:Hide() end
    if card.zoneTab then card.zoneTab:Hide() end
    if card.advancedTab then card.advancedTab:Hide() end
    if card.advancedFrame then card.advancedFrame:Hide() end
    if card.tipsFrame then card.tipsFrame:Hide() end
    card.testBtn:Show()
    card.dupBtn:Show()
    card.delBtn:Show()
    card.setupTabBtn:Show()
    card.zoneTabBtn:Show()
    if card.tipsTabBtn then card.tipsTabBtn:Show() end
    if hasAdvancedMacros then
        card.advancedTabBtn:Show()
    else
        card.advancedTabBtn:Hide()
    end

    if card.RefreshSideTabs then
        card.RefreshSideTabs()
    end

    if activeTab == "setup" then
        if card.nameLabel then card.nameLabel:Show() end
        if card.nameInput then card.nameInput:Show() end
        if card.enableCheck then card.enableCheck:Show() end
        card.eventLabel:Show()
        card.eventDropdown:Show()
        card.conditionsBox:Show()
        card.conditionsFrame:Show()
        card.conditionsLabel:Show()
        if card.conditionsDescLabel then card.conditionsDescLabel:Show() end
        
        card.actionsBox:Show()
        card.actionsFrame:Show()
        card.actionsLabel:Show()
        if card.actionsDescLabel then card.actionsDescLabel:Show() end
        card.zoneLabel:Hide()
        card.zoneFrame:Hide()
        if card.advancedFrame then card.advancedFrame:Hide() end
    elseif activeTab == "zone" then
        if card.nameLabel then card.nameLabel:Hide() end
        if card.nameInput then card.nameInput:Hide() end
        if card.enableCheck then card.enableCheck:Hide() end
        card.eventLabel:Hide()
        card.eventDropdown:Hide()
        card.conditionsBox:Hide()
        card.conditionsFrame:Hide()
        card.conditionsLabel:Hide()
        if card.conditionsDescLabel then card.conditionsDescLabel:Hide() end
        
        card.actionsBox:Hide()
        card.actionsFrame:Hide()
        card.actionsLabel:Hide()
        if card.actionsDescLabel then card.actionsDescLabel:Hide() end
        card.zoneLabel:Hide()
        card.zoneFrame:Show()
        if card.advancedFrame then card.advancedFrame:Hide() end
    elseif activeTab == "tips" then
        if card.nameLabel then card.nameLabel:Hide() end
        if card.nameInput then card.nameInput:Hide() end
        if card.enableCheck then card.enableCheck:Hide() end
        card.eventLabel:Hide()
        card.eventDropdown:Hide()
        card.conditionsBox:Hide()
        card.conditionsFrame:Hide()
        card.conditionsLabel:Hide()
        if card.conditionsDescLabel then card.conditionsDescLabel:Hide() end

        card.actionsBox:Hide()
        card.actionsFrame:Hide()
        card.actionsLabel:Hide()
        if card.actionsDescLabel then card.actionsDescLabel:Hide() end
        card.zoneLabel:Hide()
        card.zoneFrame:Hide()
        if card.advancedFrame then card.advancedFrame:Hide() end
        if card.tipsFrame then card.tipsFrame:Show() end
    else
        if card.nameLabel then card.nameLabel:Hide() end
        if card.nameInput then card.nameInput:Hide() end
        if card.enableCheck then card.enableCheck:Hide() end
        card.eventLabel:Hide()
        card.eventDropdown:Hide()
        card.conditionsBox:Hide()
        card.conditionsFrame:Hide()
        card.conditionsLabel:Hide()
        if card.conditionsDescLabel then card.conditionsDescLabel:Hide() end

        card.actionsBox:Hide()
        card.actionsFrame:Hide()
        card.actionsLabel:Hide()
        if card.actionsDescLabel then card.actionsDescLabel:Hide() end
        card.zoneLabel:Hide()
        card.zoneFrame:Hide()
        if card.advancedFrame then card.advancedFrame:Show() end
    end

    local cardHeight = 150
    if activeTab == "setup" then
        local conditionsHeight = card.conditionsFrame:GetHeight() or 60
        local actionsHeight = card.actionsFrame and card.actionsFrame.naturalHeight or 150
        
        local conditionsPadding = card.conditionsDescLabel and 50 or 36
        card.conditionsBox:SetHeight(conditionsHeight + conditionsPadding)
        
        local actionsPadding = card.actionsDescLabel and 50 or 36
        card.actionsBox:ClearAllPoints()
        card.actionsBox:SetPoint("TOPLEFT", card.conditionsBox, "BOTTOMLEFT", 0, -10)
        card.actionsBox:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        card.actionsBox:SetHeight(actionsHeight + actionsPadding)
        
        -- Base fixed padding + dynamic heights
        cardHeight = 110 + card.conditionsBox:GetHeight() + card.actionsBox:GetHeight() + 10
    elseif activeTab == "zone" then
        card.zoneLabel:ClearAllPoints()
        card.zoneLabel:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -26)
        
        card.zoneFrame:ClearAllPoints()
        card.zoneFrame:SetPoint("TOPLEFT", card.zoneLabel, "BOTTOMLEFT", 0, -10)
        card.zoneFrame:SetPoint("RIGHT", card, "RIGHT", -10, 0)
        
        cardHeight = 560
    elseif activeTab == "tips" then
        card.tipsFrame:ClearAllPoints()
        card.tipsFrame:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -26)
        card.tipsFrame:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 16)
        cardHeight = 500
    else
        if card.advancedFrame then
            card.advancedFrame:ClearAllPoints()
            card.advancedFrame:SetPoint("TOPLEFT", card, "TOPLEFT", 16, -26)
            card.advancedFrame:SetPoint("RIGHT", card, "RIGHT", -10, 0)
            card.advancedFrame:SetPoint("BOTTOM", card, "BOTTOM", 0, 16)
        end
        cardHeight = 460
    end

    card:SetHeight(cardHeight)
end

function Triggers:RefreshTriggerCard(triggerId)
    local card = Triggers.triggerCards[triggerId]
    if not card or not card.actionsFrame then return end
    
    local af = card.actionsFrame
    if af.UpdateSoundButton then af.UpdateSoundButton() end
    if af.UpdateAnimButton then af.UpdateAnimButton() end
    if af.UpdateEmoteButton then af.UpdateEmoteButton() end
    if af.UpdateChatButtonText then af.UpdateChatButtonText() end
    if af.UpdateSuccessSoundButton then af.UpdateSuccessSoundButton() end
    if af.UpdateSuccessAnimButton then af.UpdateSuccessAnimButton() end
    if af.UpdateFailSoundButton then af.UpdateFailSoundButton() end
    if af.UpdateFailAnimButton then af.UpdateFailAnimButton() end
    if af.UpdateStartChatButtonText then af.UpdateStartChatButtonText() end
    if af.UpdateStopChatButtonText then af.UpdateStopChatButtonText() end
    if af.UpdateSummonIncomingChatButtonText then af.UpdateSummonIncomingChatButtonText() end
    if af.UpdateSummonAcceptedChatButtonText then af.UpdateSummonAcceptedChatButtonText() end
    if af.UpdateSummonDeclinedChatButtonText then af.UpdateSummonDeclinedChatButtonText() end
    if af.RefreshActionVisibility then af.RefreshActionVisibility() end
    if af.UpdateMacroIconInternal then af.UpdateMacroIconInternal() end
    if af.UpdateAdvancedMacroUI then af.UpdateAdvancedMacroUI() end
end

function Triggers:ReturnToTriggerList()
    self.selectedTriggerId = nil
    self:RefreshTriggersList()
end

function Triggers:OpenTriggerDetails(triggerId)
    if not triggerId or not OxedHub.db.profile.triggers[triggerId] then
        return
    end

    self.selectedTriggerId = triggerId
    self:RefreshTriggersList()
end

function Triggers:GetSelectedTriggerId()
    return self.selectedTriggerId
end




