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

        -- Count unique sound IDs. The generated catalog's entries are also stored
        -- in customSounds (flagged autoImported), so adding both totals would
        -- double-count them and disagree with the Sounds tab.
        local seenSounds = {}
        local soundsCount = 0
        local function CountSounds(tbl)
            for id in pairs(tbl or {}) do
                if not seenSounds[id] then
                    seenSounds[id] = true
                    soundsCount = soundsCount + 1
                end
            end
        end
        CountSounds(OxedHub.GENERATED_SOUND_CATALOG)
        local sharedSounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
        CountSounds(sharedSounds)

        local animationsCount = 0
        if OxedHub.DEFAULTS and OxedHub.DEFAULTS.animations then
            for _ in pairs(OxedHub.DEFAULTS.animations) do animationsCount = animationsCount + 1 end
        end

        tab.stats[1].value:SetText(tostring(count))
        tab.stats[2].value:SetText(tostring(disabledCount))
        tab.stats[3].value:SetText(tostring(eventTypeCount))
        tab.stats[4].value:SetText(tostring(profileCount))
        if tab.stats[5] then tab.stats[5].value:SetText(tostring(soundsCount)) end
        if tab.stats[6] then tab.stats[6].value:SetText(tostring(animationsCount)) end
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

        local shareText = row:CreateFontString(nil, "OVERLAY", detailFont)
        shareText:SetPoint("RIGHT", enabledText, "LEFT", -5, 0)
        shareText:SetWidth(45)
        shareText:SetJustifyH("RIGHT")
        shareText:SetTextColor(1, 0.82, 0, 1)
        shareText:SetText(L["BTN_SHARE"] or "Share")
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
        
        -- Share Button: posts a chat announcement for this one trigger.
        local shareBtn = CreateFrame("Button", nil, row)
        shareBtn:SetSize(18, 18)
        shareBtn:SetPoint("RIGHT", toggle, "LEFT", -12, 0)
        shareBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        shareBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        shareBtn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(shareBtn, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["BTN_SHARE"] or "Share", 1, 0.82, 0)
            GameTooltip:AddLine("Share just this trigger in chat.", 1, 1, 1, true)
            GameTooltip:AddLine("Others with Oxed Hub can click to import it.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        shareBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        shareBtn:SetScript("OnClick", function()
            local Share = OxedHub.Share
            if not Share then
                print("|cffff0000Oxed Hub:|r Sharing module unavailable.")
                return
            end
            local label = trigger and trigger.name
            if not label or label == "" then label = "Trigger" end
            Share:ShowChannelPicker("triggers", { triggerIDs = { triggerId } }, label)
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

function Triggers:GetEventInfo(eventType)
    if not eventType then return nil end
    if not self._eventInfoCache then
        self._eventInfoCache = {}
        if OxedHub.CONFIG and OxedHub.CONFIG.EVENT_TYPES then
            for _, et in ipairs(OxedHub.CONFIG.EVENT_TYPES) do
                self._eventInfoCache[et.value] = et
            end
        end
    end
    return self._eventInfoCache[eventType]
end

function Triggers:GetEventDisplay(eventType)
    local info = self:GetEventInfo(eventType)
    if info and info.label then
        return info.label, info.category or "custom", info.desc or ""
    end
    return eventType or "Unknown", "custom", ""
end

function Triggers:GetActionDetails(trigger)
    local actions = trigger.actions or {}
    local lines = {}
    
    if actions.sound and actions.sound ~= "" and actions.sound ~= "None" then
        table.insert(lines, "|cffffd100Sound:|r " .. tostring(actions.sound))
    end
    if actions.animation and actions.animation ~= "" then
        table.insert(lines, "|cffa335eeAnimation:|r " .. tostring(actions.animation))
    end
    if actions.emote and actions.emote ~= "" then
        table.insert(lines, "|cff00ff00Emote:|r /" .. tostring(actions.emote))
    end
    if actions.chat and actions.chat ~= "" then
        local chan = actions.chatChannel or "SAY"
        table.insert(lines, "|cff00ccffChat (" .. chan .. "):|r " .. tostring(actions.chat))
    end
    if actions.toy and actions.toy ~= "" then
        table.insert(lines, "|cffff8000Toy:|r " .. tostring(actions.toy))
    end
    if actions.cooldownAnimation then
        table.insert(lines, "|cffff4040Cooldown Ready Animation|r")
    end
    
    if #lines == 0 then
        return "|cff888888No actions configured|r"
    end
    return table.concat(lines, "\n")
end

function Triggers:GetZoneDetails(trigger)
    local zones = trigger.zones or {}
    local lines = {}
    
    table.insert(lines, "|cffffd100Active in Zones:|r")
    table.insert(lines, (zones.OPEN_WORLD and "|cff00ff00•|r Open World" or "|cff555555• Open World|r"))
    table.insert(lines, (zones.PARTY and "|cff00ff00•|r Dungeons (Party)" or "|cff555555• Dungeons (Party)|r"))
    table.insert(lines, (zones.DELVE and "|cff00ff00•|r Delves" or "|cff555555• Delves|r"))
    table.insert(lines, (zones.RAID and "|cff00ff00•|r Raids" or "|cff555555• Raids|r"))
    table.insert(lines, (zones.PVP and "|cff00ff00•|r Arenas (PvP)" or "|cff555555• Arenas (PvP)|r"))
    table.insert(lines, (zones.BATTLEGROUND and "|cff00ff00•|r Battlegrounds" or "|cff555555• Battlegrounds|r"))
    
    return table.concat(lines, "\n")
end

function Triggers:GetFormattedActionsSummary(trigger)
    local actions = trigger.actions or {}
    local parts = {}
    
    if actions.sound and actions.sound ~= "" and actions.sound ~= "None" then
        table.insert(parts, "|cffffd100[S]|r")
    end
    if actions.animation and actions.animation ~= "" then
        table.insert(parts, "|cffa335ee[A]|r")
    end
    if actions.emote and actions.emote ~= "" then
        table.insert(parts, "|cff00ff00[E]|r")
    end
    if actions.chat and actions.chat ~= "" then
        table.insert(parts, "|cff00ccff[C]|r")
    end
    if actions.toy and actions.toy ~= "" then
        table.insert(parts, "|cffff8000[T]|r")
    end
    if actions.cooldownAnimation then
        table.insert(parts, "|cffff4040[CD]|r")
    end
    
    if #parts == 0 then
        return "|cff666666None|r"
    end
    return table.concat(parts, " ")
end

function Triggers:GetFormattedZoneSummary(trigger)
    local zones = trigger.zones or {}
    local parts = {}

    -- Nothing shown when the rule runs everywhere, which is the usual case.
    -- The same six letters repeated down every row said only that no rule was
    -- restricted; now the column speaks up only when one is.
    local restricted = false
    for _, key in ipairs({ "OPEN_WORLD", "PARTY", "DELVE", "RAID", "PVP", "BATTLEGROUND" }) do
        if not zones[key] then restricted = true break end
    end
    if not restricted then return "" end


    table.insert(parts, zones.OPEN_WORLD and "|cff55ff55W|r" or "|cff444444W|r")
    table.insert(parts, zones.PARTY and "|cff33ccffD|r" or "|cff444444D|r")
    table.insert(parts, zones.DELVE and "|cffffcc00V|r" or "|cff444444V|r")
    table.insert(parts, zones.RAID and "|cffff6633R|r" or "|cff444444R|r")
    table.insert(parts, zones.PVP and "|cffff3333P|r" or "|cff444444P|r")
    table.insert(parts, zones.BATTLEGROUND and "|cffa335eeB|r" or "|cff444444B|r")
    
    return table.concat(parts, "")
end

function Triggers:EnableAllFiltered()
    local count = 0
    for _, trigger in pairs(OxedHub.db.profile.triggers or {}) do
        if self._lastFilterMatch and self._lastFilterMatch(trigger) then
            if not trigger.enabled then
                trigger.enabled = true
                count = count + 1
            end
        end
    end
    self:InvalidateEnabledEventCache()
    self:RefreshTriggersList()
end

function Triggers:DisableAllFiltered()
    local count = 0
    for _, trigger in pairs(OxedHub.db.profile.triggers or {}) do
        if self._lastFilterMatch and self._lastFilterMatch(trigger) then
            if trigger.enabled then
                trigger.enabled = false
                count = count + 1
            end
        end
    end
    self:InvalidateEnabledEventCache()
    self:RefreshTriggersList()
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
    -- Lowered once here: everything it is matched against is lowercase, so a
    -- capital letter used to make a search silently return nothing.
    local searchText = (OxedHub.globalSearchText or ""):lower()
    local sortedTriggers = {}
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        table.insert(sortedTriggers, trigger)
    end
    
    local sortMode = OxedHub.db.profile.settings and OxedHub.db.profile.settings.triggerSortMode
    if sortMode == "az" or sortMode == "za" then
        table.sort(sortedTriggers, function(a, b)
            local nameA = (a.name or ""):lower()
            local nameB = (b.name or ""):lower()
            if nameA == nameB then
                return (a.id or "") < (b.id or "")   -- stable tiebreak
            end
            if sortMode == "za" then
                return nameA > nameB
            end
            return nameA < nameB
        end)
    else
        table.sort(sortedTriggers, function(a, b)
            -- Since IDs contain timestamp, sorting descending puts newest at top
            return (a.id or "") > (b.id or "")
        end)
    end

    -- Everything about a rule, flattened into one lowercase string to search.
    --
    -- The list used to match on the name, the event and the spell only, which
    -- meant the one question people actually ask it -- "which rule plays that
    -- sound", "what have I got set up for battlegrounds" -- could not be
    -- answered without opening rules one at a time.
    --
    -- Plain words go in alongside the ids, so "toy", "chat" or "raid" find the
    -- rules that use them even though no stored field contains those strings.
    local function BuildSearchText(trigger)
        local parts = {}
        local function Add(value)
            if value == nil then return end
            value = tostring(value)
            if value ~= "" then parts[#parts + 1] = value:lower() end
        end

        Add(trigger.name)
        Add(trigger.event)
        Add(trigger.enabled and "enabled" or "disabled")

        local info = Triggers:GetEventInfo(trigger.event)
        if info then
            Add(info.label)
            Add(info.category)
        end

        local conditions = trigger.conditions or {}
        Add(conditions.auraName)
        Add(conditions.auraType)
        for _, key in ipairs({ "spellID", "spellId" }) do
            local id = tonumber(conditions[key])
            if id then
                Add(id)
                local spell = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                if spell then Add(spell.name) end
            end
        end
        for _, id in ipairs(conditions.extraSpellIDs or {}) do
            Add(id)
            local spell = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(tonumber(id))
            if spell then Add(spell.name) end
        end
        if conditions.inCombat then Add("in combat") end
        if conditions.critical then Add("critical crit") end

        -- Only the string slots: the rest of this table is layout, and indexing
        -- an animation's saved X offset would let a search for "200" hit it.
        local actions = trigger.actions or {}
        for key, value in pairs(actions) do
            if type(value) == "string" and value ~= "" and value ~= "None" then
                Add(value)
                -- The key names the kind of thing this is, so "sound" or
                -- "animation" typed on its own lists everything that has one.
                Add(key)
            end
        end

        -- The same test the list itself uses to dim a rule, so what the search
        -- calls empty and what the row calls empty cannot drift apart.
        if (Triggers:GetActionsSummary(trigger) or "") == "" then
            Add("no actions empty")
        end

        -- Chat templates and toys are stored as references; search the thing
        -- the player would actually recognise, not the id.
        local profile = OxedHub.db and OxedHub.db.profile
        local template = profile and profile.chatTemplates and actions.chat
            and profile.chatTemplates[actions.chat]
        if template then
            Add(template.text)
            Add(template.channel)
        end
        local toyID = tonumber(actions.toy)
        if toyID and C_ToyBox and C_ToyBox.GetToyInfo then
            Add((select(2, C_ToyBox.GetToyInfo(toyID))))
        end

        Add(trigger.customMacroBody)
        Add(trigger.extraMacroText)

        -- Zone words, but only for a rule that is actually restricted.
        --
        -- Having every zone ticked means "runs everywhere", which is the usual
        -- case and is why the Zone column stays blank for it. Indexing those
        -- ticks anyway put "raid", "bg" and "arena" on nearly every rule, so a
        -- search for any of them matched the whole list.
        local zones = trigger.zones or {}
        local ZONE_KEYS = { "OPEN_WORLD", "PARTY", "DELVE", "RAID", "PVP", "BATTLEGROUND" }
        local restricted = false
        for _, key in ipairs(ZONE_KEYS) do
            if not zones[key] then restricted = true break end
        end

        if restricted then
            local ZONE_WORDS = {
                OPEN_WORLD = "world outdoor open",
                PARTY = "party dungeon",
                DELVE = "delve",
                RAID = "raid",
                PVP = "pvp arena",
                BATTLEGROUND = "battleground bg",
            }
            for _, key in ipairs(ZONE_KEYS) do
                if zones[key] then Add(ZONE_WORDS[key]) end
            end
        end

        return table.concat(parts, " ")
    end

    local function TriggerMatchesSearch(trigger)
        local testerOn = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.testerMode == true
        local info = Triggers:GetEventInfo(trigger.event)
        if info and info.isTester and not testerOn then
            return false
        end

        local statusFilter = OxedHub.db.profile.settings and OxedHub.db.profile.settings.triggerStatusFilter or "all"
        if statusFilter == "enabled" and not trigger.enabled then
            return false
        elseif statusFilter == "disabled" and trigger.enabled then
            return false
        end

        local catFilter = OxedHub.db.profile.settings and OxedHub.db.profile.settings.triggerCategoryFilter or "all"
        if catFilter ~= "all" then
            local category = info and info.category or "custom"
            if category ~= catFilter then
                return false
            end
        end

        local match = true
        if searchText ~= "" then
            local haystack = BuildSearchText(trigger)

            -- Every word must appear, so "sound raid" narrows instead of
            -- widening. One long phrase still works: it is simply one word.
            match = true
            for term in searchText:gmatch("%S+") do
                if not haystack:find(term, 1, true) then
                    match = false
                    break
                end
            end
        end

        if match and OxedHub.db.profile.settings.filterByClass and trigger.conditions and trigger.conditions.spellID then
            if not OxedHub:IsSpellRelevant(trigger.conditions.spellID) then
                match = false
            end
        end

        return match
    end

    self._lastFilterMatch = TriggerMatchesSearch

    -- ── Activity log ─────────────────────────────────────────────────────────
    -- A third view of this tab, alongside the list and the single-trigger page,
    -- rather than a window of its own. It is part of the addon, so it belongs
    -- inside the addon's frame and behind the same Back to List everything else
    -- uses.
    if self.showActivityLog then
        if tab.scrollBox then tab.scrollBox:Hide() end
        if tab.scrollBar then tab.scrollBar:Hide() end
        if tab.scrollFrame then
            tab.scrollFrame:Show()
            tab.scrollFrame:EnableMouseWheel(true)
            if tab.scrollFrame.ScrollBar then tab.scrollFrame.ScrollBar:Show() end
            if tab.scrollFrame.scrollBar then tab.scrollFrame.scrollBar:Show() end
        end
        if tab.listIntro then tab.listIntro:Hide() end
        if tab.listDesc then tab.listDesc:Hide() end
        for _, key in ipairs({ "addBtn", "sortDropdown", "statusFilterDropdown",
            "categoryFilterDropdown", "quickSetupBtn", "enableAllBtn",
            "disableAllBtn", "animPreviewBtn" }) do
            if tab[key] then tab[key]:Hide() end
        end
        if searchBox and searchBox:GetParent() then searchBox:GetParent():Hide() end
        if tab.title then tab.title:SetText(L["HISTORY_LOG_TITLE"] or "Activity Log") end

        local backBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        backBtn:SetSize(110, 24)
        backBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
        backBtn:SetText(L["BTN_BACK_TO_LIST"] or "Back to List")
        backBtn:SetScript("OnClick", function()
            Triggers.showActivityLog = nil
            Triggers.activityLogFilter = nil
            Triggers:RefreshTriggersList()
        end)

        local filterId = self.activityLogFilter
        local filtered = filterId and OxedHub.db.profile.triggers[filterId] or nil

        local clearBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
        clearBtn:SetSize(110, 24)
        clearBtn:SetPoint("LEFT", backBtn, "RIGHT", 10, 0)
        clearBtn:SetText(filtered and (L["HISTORY_CLEAR"] or "Clear this rule")
            or (L["HISTORY_CLEAR_ALL"] or "Clear all"))
        clearBtn:SetScript("OnClick", function()
            Triggers:ClearTriggerHistory(filterId)
        end)

        -- Narrowed to one rule, the page still shows every rule one click away.
        if filtered then
            local allBtn = CreateFrame("Button", nil, scrollChild, "UIPanelButtonTemplate")
            allBtn:SetSize(110, 24)
            allBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
            allBtn:SetText(L["HISTORY_SHOW_ALL"] or "All triggers")
            allBtn:SetScript("OnClick", function()
                Triggers.activityLogFilter = nil
                Triggers:RefreshTriggersList()
            end)
        end

        local events, ruleCount, total, trimmed = self:CollectActivityLog(filterId)

        local heading = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", backBtn, "BOTTOMLEFT", 0, -14)
        heading:SetTextColor(1, 0.82, 0)
        heading:SetText(filtered and (filtered.name or filterId)
            or (L["HISTORY_LOG_HEADING"] or "Everything that fired today"))

        local summary = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summary:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
        summary:SetTextColor(0.75, 0.75, 0.75)

        local body = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -12)
        body:SetPoint("RIGHT", scrollChild, "RIGHT", -20, 0)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")

        if total == 0 then
            summary:SetText(filtered and (L["HISTORY_NONE"] or "Has not fired today.")
                or (L["HISTORY_LOG_EMPTY"] or "Nothing has fired today."))
            body:SetText("|cff888888" .. (L["HISTORY_NONE_HINT"]
                or "Counting starts fresh each day.") .. "|r")
        else
            summary:SetText(filtered
                and string.format(L["HISTORY_SUMMARY"] or "Fired %d times today, last at %s",
                    total, date("%H:%M:%S", events[1] and events[1].t or time()))
                or string.format(L["HISTORY_LOG_SUMMARY"] or "%d firings today across %d rules",
                    total, ruleCount))

            local lines = {}
            for _, row in ipairs(events) do
                -- With one rule on screen its name is the heading already, so
                -- the column would just repeat it on every line.
                lines[#lines + 1] = ("|cffffd100%s|r   %s%s"):format(
                    date("%H:%M:%S", row.t),
                    filtered and "" or row.name,
                    row.what and ((filtered and "" or "   ") .. "|cffcccccc" .. row.what .. "|r") or "")
            end
            if trimmed > 0 then
                lines[#lines + 1] = ("|cff888888... and %d earlier, no longer kept|r"):format(trimmed)
            end
            body:SetText(table.concat(lines, "\n"))
        end

        scrollChild:SetHeight(math.max(320, 110 + body:GetStringHeight()))
        return
    end

    local selectedTrigger = self.selectedTriggerId and OxedHub.db.profile.triggers[self.selectedTriggerId] or nil
    if selectedTrigger then
        if tab.scrollBox then tab.scrollBox:Hide() end
        if tab.scrollBar then tab.scrollBar:Hide() end
        if tab.scrollFrame then 
            tab.scrollFrame:Show()
            tab.scrollFrame:EnableMouseWheel(true)
            if tab.scrollFrame.ScrollBar then tab.scrollFrame.ScrollBar:Show() end
            if tab.scrollFrame.scrollBar then tab.scrollFrame.scrollBar:Show() end
        end
        if tab.listIntro then tab.listIntro:Hide() end
        if tab.listDesc then tab.listDesc:Hide() end

        if tab.addBtn then
            tab.addBtn:Hide()
        end
        -- These belong to the list, not the single-trigger page.
        if tab.sortDropdown then
            tab.sortDropdown:Hide()
        end
        if tab.statusFilterDropdown then
            tab.statusFilterDropdown:Hide()
        end
        if tab.categoryFilterDropdown then
            tab.categoryFilterDropdown:Hide()
        end
        if tab.quickSetupBtn then
            tab.quickSetupBtn:Hide()
        end
        if tab.enableAllBtn then
            tab.enableAllBtn:Hide()
        end
        if tab.disableAllBtn then
            tab.disableAllBtn:Hide()
        end
        if tab.animPreviewBtn then
            tab.animPreviewBtn:Hide()
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
        scrollChild:SetHeight(card:GetHeight() + 20)
        return
    end

    if tab.addBtn then
        tab.addBtn:Show()
        tab.addBtn:SetText(L["TRIGGERS_BTN_ADD_NEW"] or "Add New Trigger")

        -- A-Z / Z-A sort dropdown under Add New Trigger button
        if not tab.sortDropdown then
            local dd = CreateFrame("DropdownButton", "OxedHubTriggerSortDropdown", tab,
                "WowStyle1DropdownTemplate")
            dd:SetPoint("TOPRIGHT", tab.addBtn, "BOTTOMRIGHT", 0, -6)
            dd:SetWidth(95)

            local sortOptions = {
                { text = L["MIXER_SORT_AZ"] or "A - Z", value = "az" },
                { text = L["MIXER_SORT_ZA"] or "Z - A", value = "za" },
            }

            local function UpdateSortText()
                local mode = OxedHub.db.profile.settings.triggerSortMode or "az"
                for _, opt in ipairs(sortOptions) do
                    if opt.value == mode then
                        dd:OverrideText(opt.text)
                        return
                    end
                end
                dd:OverrideText(sortOptions[1].text)
            end

            dd:SetupMenu(function(dropdown, rootDescription)
                for _, opt in ipairs(sortOptions) do
                    rootDescription:CreateRadio(opt.text,
                        function()
                            return (OxedHub.db.profile.settings.triggerSortMode or "az") == opt.value
                        end,
                        function()
                            OxedHub.db.profile.settings.triggerSortMode = opt.value
                            UpdateSortText()
                            Triggers:RefreshTriggersList()
                        end
                    )
                end
            end)

            UpdateSortText()
            tab.sortDropdown = dd
        end
        tab.sortDropdown:Show()

        -- Status Filter (All / Enabled / Disabled)
        if not tab.statusFilterDropdown then
            local sdd = CreateFrame("DropdownButton", "OxedHubTriggerStatusFilterDropdown", tab,
                "WowStyle1DropdownTemplate")
            sdd:SetPoint("RIGHT", tab.sortDropdown, "LEFT", -6, 0)
            sdd:SetWidth(120)

            local statusOptions = {
                { text = L["TRIGGERS_FILTER_STATUS_ALL"] or "All Status", value = "all" },
                { text = L["TRIGGERS_FILTER_STATUS_ENABLED"] or "Enabled Only", value = "enabled" },
                { text = L["TRIGGERS_FILTER_STATUS_DISABLED"] or "Disabled Only", value = "disabled" },
            }

            local function UpdateStatusText()
                local cur = OxedHub.db.profile.settings.triggerStatusFilter or "all"
                for _, opt in ipairs(statusOptions) do
                    if opt.value == cur then
                        sdd:OverrideText(opt.text)
                        return
                    end
                end
                sdd:OverrideText(statusOptions[1].text)
            end

            sdd:SetupMenu(function(dropdown, rootDescription)
                for _, opt in ipairs(statusOptions) do
                    rootDescription:CreateRadio(opt.text,
                        function()
                            return (OxedHub.db.profile.settings.triggerStatusFilter or "all") == opt.value
                        end,
                        function()
                            OxedHub.db.profile.settings.triggerStatusFilter = opt.value
                            UpdateStatusText()
                            Triggers:RefreshTriggersList()
                        end
                    )
                end
            end)

            UpdateStatusText()
            tab.statusFilterDropdown = sdd
        end
        tab.statusFilterDropdown:Show()

        -- Category Filter (All / Basic / Combat / PvP / Advanced)
        if not tab.categoryFilterDropdown then
            local cdd = CreateFrame("DropdownButton", "OxedHubTriggerCategoryFilterDropdown", tab,
                "WowStyle1DropdownTemplate")
            cdd:SetPoint("RIGHT", tab.statusFilterDropdown, "LEFT", -6, 0)
            cdd:SetWidth(140)

            local catOptions = {
                { text = L["TRIGGERS_FILTER_CAT_ALL"] or "All Categories", value = "all" },
                { text = L["TRIGGERS_FILTER_CAT_ADVANCED"] or "Advanced Spells", value = "advanced" },
                { text = L["TRIGGERS_FILTER_CAT_COMBAT"] or "Combat Events", value = "combat" },
                { text = L["TRIGGERS_FILTER_CAT_PVP"] or "PvP Alerts", value = "pvp" },
                { text = L["TRIGGERS_FILTER_CAT_BASIC"] or "Basic Events", value = "basic" },
            }

            local function UpdateCatText()
                local cur = OxedHub.db.profile.settings.triggerCategoryFilter or "all"
                for _, opt in ipairs(catOptions) do
                    if opt.value == cur then
                        cdd:OverrideText(opt.text)
                        return
                    end
                end
                cdd:OverrideText(catOptions[1].text)
            end

            cdd:SetupMenu(function(dropdown, rootDescription)
                for _, opt in ipairs(catOptions) do
                    rootDescription:CreateRadio(opt.text,
                        function()
                            return (OxedHub.db.profile.settings.triggerCategoryFilter or "all") == opt.value
                        end,
                        function()
                            OxedHub.db.profile.settings.triggerCategoryFilter = opt.value
                            UpdateCatText()
                            Triggers:RefreshTriggersList()
                        end
                    )
                end
            end)

            UpdateCatText()
            tab.categoryFilterDropdown = cdd
        end
        tab.categoryFilterDropdown:Show()

        -- Quick Setup: build triggers straight from this character's spells.
        if not tab.quickSetupBtn then
            local qs = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
            qs:SetSize(120, 24)
            qs:SetPoint("BOTTOMLEFT", tab.scrollBox, "TOPLEFT", 7, 20)
            qs:SetText(L["QS_BUTTON"] or "Quick Setup")
            qs:SetScript("OnClick", function()
                if Triggers.QuickSetup then Triggers.QuickSetup:Show() end
            end)
            qs:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText(L["QS_BUTTON"] or "Quick Setup", 1, 0.82, 0)
                GameTooltip:AddLine(L["QS_BUTTON_DESC"]
                    or "Create triggers in bulk from the spells your character actually has.",
                    1, 1, 1, true)
                GameTooltip:Show()
            end)
            qs:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tab.quickSetupBtn = qs
        end
        tab.quickSetupBtn:Show()

        -- Bulk Enable All Button
        if not tab.enableAllBtn then
            local eb = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
            eb:SetSize(95, 24)
            eb:SetPoint("LEFT", tab.quickSetupBtn, "RIGHT", 8, 0)
            eb:SetText(L["TRIGGERS_BTN_ENABLE_ALL"] or "Enable All")
            eb:SetScript("OnClick", function()
                Triggers:EnableAllFiltered()
            end)
            eb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["TRIGGERS_BTN_ENABLE_ALL"] or "Enable All", 1, 0.82, 0)
                GameTooltip:AddLine(L["TRIGGERS_BTN_ENABLE_ALL_DESC"] or "Enable all currently visible/filtered triggers.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            eb:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tab.enableAllBtn = eb
        end
        tab.enableAllBtn:Show()

        -- Bulk Disable All Button
        if not tab.disableAllBtn then
            local db = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
            db:SetSize(95, 24)
            db:SetPoint("LEFT", tab.enableAllBtn, "RIGHT", 6, 0)
            db:SetText(L["TRIGGERS_BTN_DISABLE_ALL"] or "Disable All")
            db:SetScript("OnClick", function()
                Triggers:DisableAllFiltered()
            end)
            db:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["TRIGGERS_BTN_DISABLE_ALL"] or "Disable All", 1, 0.82, 0)
                GameTooltip:AddLine(L["TRIGGERS_BTN_DISABLE_ALL_DESC"] or "Disable all currently visible/filtered triggers.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            db:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tab.disableAllBtn = db
        end
        tab.disableAllBtn:Show()

        -- Preview: every animation on screen at once instead of opening one
        -- trigger at a time to find out where its animation sits.
        if not tab.animPreviewBtn then
            local pv = CreateFrame("Button", nil, tab, "UIPanelButtonTemplate")
            pv:SetSize(95, 24)
            pv:SetPoint("LEFT", tab.disableAllBtn, "RIGHT", 6, 0)
            pv:SetText(L["ANIMPREVIEW_BUTTON"] or "Preview")
            pv:SetScript("OnClick", function()
                if OxedHub.AnimationPreview then OxedHub.AnimationPreview:Enter() end
            end)
            pv:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["ANIMPREVIEW_BUTTON"] or "Preview", 1, 0.82, 0)
                GameTooltip:AddLine(L["ANIMPREVIEW_BUTTON_DESC"]
                    or "Show every enabled trigger's animation on screen, labelled, and drag them into place.",
                    1, 1, 1, true)
                GameTooltip:Show()
            end)
            pv:SetScript("OnLeave", function() GameTooltip:Hide() end)
            tab.animPreviewBtn = pv
        end
        tab.animPreviewBtn:Show()

    end
    if searchBox and searchBox:GetParent() then
        searchBox:GetParent():Show()
    end
    if tab.title then
        tab.title:SetText("Trigger Rules")
    end

    local totalTriggers = 0
    local totalEnabled = 0
    for _, tr in pairs(OxedHub.db.profile.triggers or {}) do
        totalTriggers = totalTriggers + 1
        if tr.enabled then totalEnabled = totalEnabled + 1 end
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

        local dataProvider = CreateDataProvider()
        dataProvider:Insert({
            isHeader = true,
            name = L["LBL_NAME"] or "Trigger Name",
            event = L["LBL_EVENT"] or "Event Type",
            actions = L["LBL_ACTIONS"] or "Actions",
            zone = L["LBL_ZONE"] or "Zone",
        })

        -- Grouped by category, with a heading before each run. A flat list of
        -- thirty rules gives no sense of what is set up where; the four
        -- categories the events already carry do.
        --
        -- Collapsed groups are remembered per profile, so a category the player
        -- is not working on stays folded away between sessions.
        local profile = OxedHub.db and OxedHub.db.profile
        if profile then
            profile.collapsedTriggerGroups = profile.collapsedTriggerGroups or {}
        end
        local collapsed = (profile and profile.collapsedTriggerGroups) or {}

        -- Worked out once for the whole list rather than per row: the check
        -- compares every rule against every other, and doing that inside the
        -- row loop would make it quadratic for no gain.
        local soundConflicts = self:GetDuplicateSoundConflicts() or {}

        local grouped, groupOrder = {}, {}
        for _, category in ipairs(OxedHub.CONFIG.EVENT_CATEGORIES or {}) do
            grouped[category.value] = { label = category.label, triggers = {} }
            groupOrder[#groupOrder + 1] = category.value
        end
        -- Anything whose event is not in the catalogue still has to appear.
        grouped["other"] = { label = L["TRIGGER_GROUP_OTHER"] or "Other", triggers = {} }
        groupOrder[#groupOrder + 1] = "other"

        local visibleCount = 0
        for _, trigger in ipairs(sortedTriggers) do
            if TriggerMatchesSearch(trigger) then
                local _, evCat = self:GetEventDisplay(trigger.event)
                local bucket = grouped[evCat] or grouped["other"]
                table.insert(bucket.triggers, trigger)
                visibleCount = visibleCount + 1
            end
        end

        local rowIndex = 0
        for _, key in ipairs(groupOrder) do
            local group = grouped[key]
            if #group.triggers > 0 then
                -- Carried up to the heading so folding a category cannot hide a
                -- warning. A collapsed group is exactly where an unnoticed
                -- clash would sit forever.
                local groupWarn
                for _, trigger in ipairs(group.triggers) do
                    local clash = soundConflicts[trigger.id]
                    if clash then
                        groupWarn = groupWarn or { count = 0, exact = false, names = {} }
                        groupWarn.count = groupWarn.count + 1
                        groupWarn.exact = groupWarn.exact or clash.exact
                        table.insert(groupWarn.names, trigger.name or trigger.id)
                    end
                end

                dataProvider:Insert({
                    isGroupHeader = true,
                    groupKey = key,
                    name = group.label,
                    groupCount = #group.triggers,
                    collapsed = collapsed[key] == true,
                    groupWarn = groupWarn,
                })
            end

            if #group.triggers > 0 and not collapsed[key] then
                for _, trigger in ipairs(group.triggers) do
                rowIndex = rowIndex + 1
                local evLabel, evCat, evDesc = self:GetEventDisplay(trigger.event)
                dataProvider:Insert({
                    id = trigger.id,
                    index = rowIndex,
                    name = trigger.name,
                    event = trigger.event,
                    eventLabel = evLabel,
                    eventCategory = evCat,
                    eventDesc = evDesc,
                    actions = self:GetActionsSummary(trigger),
                    formattedActions = self:GetFormattedActionsSummary(trigger),
                    actionDetails = self:GetActionDetails(trigger),
                    spellID = trigger.conditions and trigger.conditions.spellID,
                    zone = self:GetZoneSummary(trigger),
                    formattedZone = self:GetFormattedZoneSummary(trigger),
                    zoneDetails = self:GetZoneDetails(trigger),
                    enabled = trigger.enabled == true,
                    -- A rule with no actions fires and does nothing. They are
                    -- what half-finished experiments leave behind, and they sit
                    -- in the list looking exactly like working ones.
                    isEmpty = (self:GetActionsSummary(trigger) or "") == "",
                    duplicateSoundOf = soundConflicts[trigger.id],
                })
                end
            end
        end

        tab.listIntro:SetText((L["DASHBOARD_STAT_ACTIVE_TRIGGERS"] or "Active Triggers") .. " (" .. visibleCount .. " visible)")
        tab.listIntro:Show()
        -- The stats line had spare room, and a right-click menu nobody is told
        -- about is a menu nobody finds.
        tab.listDesc:SetText(string.format("Total: %d  |  Enabled: %d  |  Disabled: %d   |cff888888%s|r",
            totalTriggers, totalEnabled, totalTriggers - totalEnabled,
            L["TRIGGERS_LIST_HINT"] or "Right-click a row for more"))
        tab.listDesc:Show()

        if visibleCount == 0 then
            dataProvider:Insert({
                isHeader = false,
                name = searchText ~= "" and "No triggers match search" or "No triggers match filters",
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


