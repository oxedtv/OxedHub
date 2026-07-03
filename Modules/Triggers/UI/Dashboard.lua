local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

function Triggers:RefreshDashboard()
    local tab = OxedHub.UI and OxedHub.UI:GetContentArea() and OxedHub.UI:GetContentArea().Dashboard
    if not tab then return end
    
    local scrollChild = tab.scrollChild

    local filter = OxedHub.db.profile.settings.filterByClass
    local count = 0
    local disabledCount = 0
    local eventTypeMap = {}

    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if not trigger.enabled then
            disabledCount = disabledCount + 1
        end

        if trigger.enabled then
            local show = true
            if filter and trigger.conditions and trigger.conditions.spellID then
                if not OxedHub:IsSpellRelevant(trigger.conditions.spellID) then
                    show = false
                end
            end

            if show then
                count = count + 1
                eventTypeMap[trigger.event or "Unknown"] = true
            end
        end
    end

    if tab.heroTitle then
        tab.heroTitle:SetText(L["TR_READY_TO_REACT"] or "Ready to React")
    end

    if tab.heroSubtitle then
        local activeProfileName = OxedHub.GetProfileColoredName and OxedHub:GetProfileColoredName(OxedHub:GetActiveProfileName()) or OxedHub:GetActiveProfileName()
        tab.heroSubtitle:SetText((L["TR_CURRENT_PROFILE"] or "Current profile: ") .. (activeProfileName or (L["PROFILES_DEFAULT"] or "Default")))
    end

    -- Keep the dashboard profile dropdown in sync
    if OxedHub.UI and OxedHub.UI.RefreshProfileDropdown then
        OxedHub.UI.RefreshProfileDropdown()
    end

    if tab.heroMeta then
        local playerClass = OxedHub.GetPlayerClassToken and OxedHub:GetPlayerClassToken() or false
        local className = OxedHub.GetClassDisplayName and OxedHub:GetClassDisplayName(playerClass) or nil
        local filterState = filter and (L["TR_CLASS_FILTER_ON"] or "Class filter on") or (L["TR_CLASS_FILTER_OFF"] or "Class filter off")
        local profileClass = OxedHub.GetProfileClassToken and OxedHub:GetProfileClassToken(OxedHub:GetActiveProfileName()) or false
        local profileClassName = OxedHub.GetClassDisplayName and OxedHub:GetClassDisplayName(profileClass) or nil
        local profileSummary = profileClassName and ((L["TR_PROFILE_CLASS"] or "Profile class: ") .. profileClassName) or (L["TR_PROFILE_CLASS_ANY"] or "Profile class: Any")
        local playerSummary = className and ((L["TR_PLAYER_CLASS"] or "Player class: ") .. className) or (L["TR_PLAYER_CLASS_UNKNOWN"] or "Player class: Unknown")
        tab.heroMeta:SetText(playerSummary .. "  |  " .. profileSummary .. "  |  " .. filterState)
    end

    if tab.stats then
        local profileCount = OxedHub.GetProfileList and #OxedHub:GetProfileList() or 0
        local eventTypeCount = 0
        for _ in pairs(eventTypeMap) do
            eventTypeCount = eventTypeCount + 1
        end

        tab.stats[1].value:SetText(tostring(count))
        tab.stats[2].value:SetText(tostring(disabledCount))
        tab.stats[3].value:SetText(tostring(eventTypeCount))
        tab.stats[4].value:SetText(tostring(profileCount))
    end

    if tab.summaryText then
        if count > 0 then
            tab.summaryText:SetText(string.format(L["TR_ENABLED_TRIGGERS_SUMMARY"] or "You have %d enabled triggers. Open the Triggers tab to browse and edit them.", count))
        else
            tab.summaryText:SetText(L["TR_NO_ACTIVE_TRIGGERS"] or "No active triggers yet. Open the Triggers tab to create your first one.")
        end
    end

    if OxedHub.UI and OxedHub.UI.UpdateDashboardSliderStats then
        OxedHub.UI:UpdateDashboardSliderStats()
    end

    scrollChild:SetHeight(586) -- Matches the exact height of our dashboard scrollChild!
end

function Triggers:CreateDashboardRow(parent, name, event, actions, zone, isHeader, triggerId)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(isHeader and 28 or 36)
    local headerFont = "GameFontHighlightSmall"
    local nameFont = isHeader and headerFont or "GameFontNormal"
    local detailFont = isHeader and headerFont or "GameFontNormalSmall"
    
    if isHeader then
        -- Header row with dark background and gold text
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.12, 0.12, 0.18, 0.95)
        
        -- Gold accent line at bottom
        local accentLine = row:CreateTexture(nil, "OVERLAY")
        accentLine:SetPoint("BOTTOMLEFT", row)
        accentLine:SetPoint("BOTTOMRIGHT", row)
        accentLine:SetHeight(1)
        accentLine:SetColorTexture(1, 0.82, 0, 0.5)
    else
        -- Data rows with stone backgrounds
        if OxedHub.UIComponents and OxedHub.UIComponents.Panel then
            OxedHub.UIComponents.Panel.ApplyStoneBackdrop(row, 0.3)
        else
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
        end
        
        -- Row highlight on hover
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 0.82, 0, 0.15)
        row.highlight:Hide()
        
        -- Selection border
        row.selectBorder = row:CreateTexture(nil, "BORDER")
        row.selectBorder:SetPoint("TOPLEFT", row)
        row.selectBorder:SetPoint("BOTTOMRIGHT", row)
        row.selectBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
        row.selectBorder:SetVertexColor(1, 0.82, 0, 0.4)
        row.selectBorder:Hide()
        
        row.triggerId = triggerId
    end
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", nameFont)
    nameText:SetPoint("LEFT", row, "LEFT", 12, 0)
    nameText:SetWidth(150)
    nameText:SetJustifyH("LEFT")
    if isHeader then
        nameText:SetTextColor(1, 0.82, 0, 1)
    end
    nameText:SetText(name)
    
    -- Event
    local eventText = row:CreateFontString(nil, "OVERLAY", detailFont)
    eventText:SetPoint("LEFT", nameText, "RIGHT", 10, 0)
    eventText:SetWidth(100)
    eventText:SetJustifyH("LEFT")
    if isHeader then
        eventText:SetTextColor(1, 0.82, 0, 1)
    else
        eventText:SetTextColor(0.8, 0.8, 0.8, 1)
    end
    eventText:SetText(event)
    
    -- Actions
    local actionsText = row:CreateFontString(nil, "OVERLAY", detailFont)
    actionsText:SetPoint("LEFT", eventText, "RIGHT", 10, 0)
    actionsText:SetWidth(150)
    actionsText:SetJustifyH("LEFT")
    if isHeader then
        actionsText:SetTextColor(1, 0.82, 0, 1)
    else
        actionsText:SetTextColor(0.8, 0.8, 0.8, 1)
    end
    actionsText:SetText(actions)
    
    -- Zone
    local zoneText = row:CreateFontString(nil, "OVERLAY", detailFont)
    zoneText:SetPoint("LEFT", actionsText, "RIGHT", 10, 0)
    zoneText:SetWidth(80)
    zoneText:SetJustifyH("LEFT")
    if isHeader then
        zoneText:SetTextColor(1, 0.82, 0, 1)
    else
        zoneText:SetTextColor(0.8, 0.8, 0.8, 1)
    end
    zoneText:SetText(zone)
    
    if isHeader then
        local deleteText = row:CreateFontString(nil, "OVERLAY", detailFont)
        deleteText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        deleteText:SetWidth(45)
        deleteText:SetJustifyH("RIGHT")
        deleteText:SetTextColor(1, 0.82, 0, 1)
        deleteText:SetText(L["TRIGGERS_HEADER_DELETE"] or "Delete")

        local enabledText = row:CreateFontString(nil, "OVERLAY", detailFont)
        enabledText:SetPoint("RIGHT", deleteText, "LEFT", -5, 0)
        enabledText:SetWidth(60)
        enabledText:SetJustifyH("RIGHT")
        enabledText:SetTextColor(1, 0.82, 0, 1)
        enabledText:SetText(L["TRIGGERS_HEADER_ENABLE"] or "Enable")
    else
        -- Delete Button
        local delBtn = CreateFrame("Button", nil, row)
        delBtn:SetSize(20, 20)
        delBtn:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        delBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        delBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        delBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        delBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(delBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete Trigger", 1, 0, 0)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        delBtn:SetScript("OnClick", function()
            Triggers:DeleteTrigger(triggerId)
        end)

        -- Toggle
        local toggle = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        toggle:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
        toggle:SetSize(22, 22)
        local trigger = OxedHub.db.profile.triggers[triggerId]
        toggle:SetChecked(trigger and trigger.enabled)
        toggle:SetScript("OnClick", function(self)
            if trigger then
                trigger.enabled = self:GetChecked()
                Triggers:InvalidateEnabledEventCache()
            end
        end)
        
        -- Gold accent on left edge
        local edge = row:CreateTexture(nil, "OVERLAY")
        edge:SetSize(3, row:GetHeight())
        edge:SetPoint("LEFT", row, "LEFT", 0, 0)
        edge:SetColorTexture(1, 0.82, 0, 0.6)
    end
    
    -- Click to edit
    if not isHeader then
        row:EnableMouse(true)
        row:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                Triggers:OpenTriggerDetails(triggerId)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.bg then self.bg:SetColorTexture(0.1, 0.1, 0.15, 0.9) end
            if self.highlight then
                self.highlight:Show()
            end
            if self.selectBorder then
                self.selectBorder:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.bg then self.bg:SetColorTexture(0.06, 0.06, 0.08, 0.85) end
            if self.highlight then
                self.highlight:Hide()
            end
            if self.selectBorder then
                self.selectBorder:Hide()
            end
        end)
    end
    
    return row
end

function Triggers:GetActionsSummary(trigger)
    local actions = trigger.actions or {}
    local parts = {}
    
    if actions.sound and actions.sound ~= "" and actions.sound ~= "None" then
        table.insert(parts, "S")
    end
    if actions.animation and actions.animation ~= "" then
        table.insert(parts, "A")
    end
    if actions.emote and actions.emote ~= "" then
        table.insert(parts, "E")
    end
    if actions.chat and actions.chat ~= "" then
        table.insert(parts, "C")
    end
    if actions.toy and actions.toy ~= "" then
        table.insert(parts, "T")
    end
    if actions.cooldownAnimation then
        table.insert(parts, "CD")
    end
    
    return table.concat(parts, "/")
end

function Triggers:GetZoneSummary(trigger)
    local zones = trigger.zones or {}
    local parts = {}
    
    if zones.OPEN_WORLD then table.insert(parts, "W") end
    if zones.PARTY then table.insert(parts, "D") end
    if zones.DELVE then table.insert(parts, "V") end
    if zones.RAID then table.insert(parts, "R") end
    if zones.PVP then table.insert(parts, "P") end
    if zones.BATTLEGROUND then table.insert(parts, "B") end
    
    return table.concat(parts, "")
end

function Triggers:RefreshTriggersList()
    self:InvalidateEnabledEventCache()
    local tab = OxedHub.UI and OxedHub.UI:GetContentArea() and OxedHub.UI:GetContentArea().Triggers
    if not tab then return end
    
    local scrollChild = tab.scrollChild
    local searchBox = _G["OxedHubSearchBox"]

    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    for _, region in ipairs({scrollChild:GetRegions()}) do
        if region.Hide then
            region:Hide()
        end
    end
    
    -- Clear existing cards
    for id, card in pairs(Triggers.triggerCards) do
        card:Hide()
        card:SetParent(nil)
    end
    wipe(Triggers.triggerCards)
    local searchText = OxedHub.globalSearchText or ""
    local sortedTriggers = {}
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        table.insert(sortedTriggers, trigger)
    end
    
    table.sort(sortedTriggers, function(a, b)
        -- Since IDs contain timestamp, sorting descending puts newest at top
        return (a.id or "") > (b.id or "")
    end)

    local function TriggerMatchesSearch(trigger)
        local match = true
        if searchText ~= "" then
            match = false
            local name = (trigger.name or ""):lower()
            local event = (trigger.event or ""):lower()
            local spellName = ""
            local spellId = ""
            if trigger.conditions and trigger.conditions.spellID then
                spellId = tostring(trigger.conditions.spellID):lower()
                local spellInfo = C_Spell.GetSpellInfo(tonumber(trigger.conditions.spellID) or trigger.conditions.spellID)
                if spellInfo and spellInfo.name then
                    spellName = spellInfo.name:lower()
                end
            end
            local soundName = ""
            if trigger.actions and trigger.actions.sound then
                soundName = tostring(trigger.actions.sound):lower()
            end

            if name:find(searchText, 1, true) or
               event:find(searchText, 1, true) or
               spellName:find(searchText, 1, true) or
               spellId:find(searchText, 1, true) or
               soundName:find(searchText, 1, true) then
                match = true
            end
        end

        if match and OxedHub.db.profile.settings.filterByClass and trigger.conditions and trigger.conditions.spellID then
            if not OxedHub:IsSpellRelevant(trigger.conditions.spellID) then
                match = false
            end
        end

        return match
    end

    local selectedTrigger = self.selectedTriggerId and OxedHub.db.profile.triggers[self.selectedTriggerId] or nil
    if selectedTrigger then
        if tab.scrollBox then tab.scrollBox:Hide() end
        if tab.scrollBar then tab.scrollBar:Hide() end
        if tab.scrollFrame then 
            tab.scrollFrame:Show()
            tab.scrollFrame:EnableMouseWheel(false)
            tab.scrollFrame:SetVerticalScroll(0)
            if tab.scrollFrame.ScrollBar then
                tab.scrollFrame.ScrollBar:SetAlpha(0)
                tab.scrollFrame.ScrollBar:Hide()
            end
            if tab.scrollFrame.oxedMinimalScrollBar then
                tab.scrollFrame.oxedMinimalScrollBar:SetAlpha(0)
                tab.scrollFrame.oxedMinimalScrollBar:Hide()
            end
            for _, child in ipairs({tab.scrollFrame:GetChildren()}) do
                if child:GetObjectType() == "Slider" then
                    child:SetAlpha(0)
                    child:Hide()
                end
            end
        end
        if tab.listIntro then tab.listIntro:Hide() end
        if tab.listDesc then tab.listDesc:Hide() end

        if tab.addBtn then
            tab.addBtn:Hide()
        end
        if searchBox and searchBox:GetParent() then
            searchBox:GetParent():Hide()
        end
        if tab.title then
            tab.title:SetText("Trigger Details")
        end

        local backBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        backBtn:SetSize(110, 24)
        backBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
        backBtn:SetText(L["BTN_BACK_TO_LIST"] or "Back to List")
        backBtn:SetScript("OnClick", function()
            Triggers:ReturnToTriggerList()
        end)

        local triggerDropdown = CreateFrame("DropdownButton", "OxedHubTriggerJumpDropdown", scrollChild, "WowStyle1DropdownTemplate")
        triggerDropdown:SetPoint("LEFT", backBtn, "RIGHT", 15, 0)
        triggerDropdown:SetSize(250, 24)
        triggerDropdown:SetupMenu(function(dropdown, rootDescription)
            local dTriggers = {}
            for _, trigger in pairs(OxedHub.db.profile.triggers) do
                table.insert(dTriggers, trigger)
            end
            table.sort(dTriggers, function(a, b)
                return (a.id or "") > (b.id or "")
            end)
            
            for _, trigger in ipairs(dTriggers) do
                rootDescription:CreateRadio(
                    trigger.name or "Unnamed Trigger",
                    function() return self.selectedTriggerId == trigger.id end,
                    function()
                        Triggers:OpenTriggerDetails(trigger.id)
                    end
                )
            end
        end)
        
        if triggerDropdown.SetDefaultText then
            triggerDropdown:SetDefaultText(selectedTrigger.name or "Unnamed Trigger")
        elseif triggerDropdown.SetText then
            triggerDropdown:SetText(selectedTrigger.name or "Unnamed Trigger")
        end

        local detailLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        detailLabel:SetPoint("LEFT", triggerDropdown, "RIGHT", 12, 0)
        detailLabel:SetText("")

        local card = self:CreateTriggerCard(scrollChild, selectedTrigger)
        card:SetPoint("TOPLEFT", backBtn, "BOTTOMLEFT", 0, -35)
        card:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 22, 0)
        Triggers.triggerCards[selectedTrigger.id] = card
        scrollChild:SetHeight(1) -- Foolproof way to force ScrollUtil to hide the scrollbar
        return
    end

    if tab.addBtn then
        tab.addBtn:Show()
        tab.addBtn:SetText(L["TRIGGERS_BTN_ADD_NEW"] or "Add New Trigger")
    end
    if searchBox and searchBox:GetParent() then
        searchBox:GetParent():Show()
    end
    if tab.title then
        tab.title:SetText("Trigger Rules")
    end

    if tab.scrollBox and tab.scrollBar and CreateDataProvider then
        if tab.scrollFrame then tab.scrollFrame:Hide() end
        tab.scrollBox:Show()
        tab.scrollBar:Show()

        if not tab.listIntro then
            local insetLeft, _, insetTop = 42, 56, 66
            if OxedHub.UI and OxedHub.UI.GetThemedFrameInsets then
                insetLeft, _, insetTop = OxedHub.UI:GetThemedFrameInsets()
            end
            tab.listIntro = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
            tab.listIntro:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -insetTop)
            tab.listIntro:SetTextColor(1, 0.82, 0, 1)
        end
        if not tab.listDesc then
            tab.listDesc = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            tab.listDesc:SetPoint("TOPLEFT", tab.listIntro, "BOTTOMLEFT", 0, -4)
            tab.listDesc:SetTextColor(0.72, 0.72, 0.72, 1)
        end
        tab.listIntro:SetText(L["DASHBOARD_STAT_ACTIVE_TRIGGERS"] or "Active Triggers")
        tab.listIntro:Show()
        tab.listDesc:SetText(L["TRIGGERS_LIST_DESC"] or "Click any trigger to open its page. Create new ones with the button below.")
        tab.listDesc:Show()

        local dataProvider = CreateDataProvider()
        dataProvider:Insert({
            isHeader = true,
            name = L["LBL_NAME"] or "Trigger Name",
            event = L["LBL_EVENT"] or "Event Type",
            actions = L["LBL_ACTIONS"] or "Actions",
            zone = L["LBL_ZONE"] or "Zone",
        })

        local visibleCount = 0
        for _, trigger in ipairs(sortedTriggers) do
            if TriggerMatchesSearch(trigger) then
                visibleCount = visibleCount + 1
                dataProvider:Insert({
                    id = trigger.id,
                    index = visibleCount,
                    name = trigger.name,
                    event = trigger.event,
                    actions = self:GetActionsSummary(trigger),
                    zone = self:GetZoneSummary(trigger),
                    enabled = trigger.enabled == true,
                })
            end
        end

        if visibleCount == 0 then
            dataProvider:Insert({
                isHeader = false,
                name = searchText ~= "" and "No triggers match search" or "No triggers yet",
                event = "",
                actions = "",
                zone = "",
                enabled = false,
            })
        end

        local retainScroll = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
        tab.scrollBox:SetDataProvider(dataProvider, retainScroll)
        return
    end

    local listIntro = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    listIntro:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
    listIntro:SetText(L["DASHBOARD_STAT_ACTIVE_TRIGGERS"] or "Active Triggers")
    listIntro:SetTextColor(1, 0.82, 0, 1)

    local listDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    listDesc:SetPoint("TOPLEFT", listIntro, "BOTTOMLEFT", 0, -4)
    listDesc:SetTextColor(0.65, 0.65, 0.65, 1)
    listDesc:SetText(L["TRIGGERS_LIST_DESC"] or "Click any trigger to open its page. Create new ones with the button below.")

    local yOffset = -52
    local header = self:CreateDashboardRow(scrollChild, L["LBL_NAME"] or "Trigger Name", L["LBL_EVENT"] or "Event Type", L["LBL_ACTIONS"] or "Actions", L["LBL_ZONE"] or "Zone", true)
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
    header:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -5, yOffset)
    yOffset = yOffset - header:GetHeight() - 6

    local visibleCount = 0
    for _, trigger in ipairs(sortedTriggers) do
        if TriggerMatchesSearch(trigger) then
            local row = self:CreateDashboardRow(scrollChild, trigger.name, trigger.event,
                self:GetActionsSummary(trigger), self:GetZoneSummary(trigger), false, trigger.id)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -5, yOffset)
            yOffset = yOffset - row:GetHeight() - 4
            visibleCount = visibleCount + 1
        end
    end

    if visibleCount == 0 then
        local emptyTitle = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyTitle:SetPoint("TOP", listDesc, "BOTTOM", 0, -40)
        emptyTitle:SetText("No Triggers Found")
        emptyTitle:SetTextColor(0.9, 0.8, 0.3)

        local emptyDesc = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        emptyDesc:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -12)
        emptyDesc:SetJustifyH("CENTER")
        emptyDesc:SetTextColor(0.7, 0.7, 0.7)
        if searchText ~= "" then
            emptyDesc:SetText("Try another search, or create a new trigger.")
        else
            emptyDesc:SetText("Create your first trigger to start building reactions.")
        end
        yOffset = yOffset - 110
    end
    
    scrollChild:SetHeight(math.abs(yOffset) + 70)
end


