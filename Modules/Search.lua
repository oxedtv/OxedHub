local addonName, OxedHub = ...

-- Search Module - Global search across all categories
local Search = {}
OxedHub.Search = Search

-- Local references
local CreateFrame = CreateFrame
local C_Timer = C_Timer

-- Search results dropdown
local searchDropdown = nil
local searchResults = {}

-- Initialize
function Search:Init()
    self:CreateSearchDropdown()
end

-- Create search dropdown
function Search:CreateSearchDropdown()
    searchDropdown = CreateFrame("Frame", "OxedHubSearchDropdown", UIParent, "BackdropTemplate")
    searchDropdown:SetSize(300, 200)
    searchDropdown:SetFrameStrata("DIALOG")
    searchDropdown:SetFrameLevel(200)
    searchDropdown:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    searchDropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    searchDropdown:SetBackdropBorderColor(0.4, 0.6, 1, 1)
    searchDropdown:EnableMouse(true)
    searchDropdown:Hide()
    
    -- Title
    local title = searchDropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", searchDropdown, "TOPLEFT", 10, -10)
    title:SetText("Search Results")
    
    -- Scroll frame for results
    local scrollFrame = CreateFrame("ScrollFrame", nil, searchDropdown, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchDropdown, "TOPLEFT", 10, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", searchDropdown, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    searchDropdown.scrollChild = scrollChild
    
    -- Hide when clicking elsewhere
    searchDropdown:SetScript("OnLeave", function(self)
        C_Timer.After(0.5, function()
            if not MouseIsOver(self) then
                self:Hide()
            end
        end)
    end)
end

-- Perform search
function Search:Search(query)
    if not query or query == "" then
        self:ClearResults()
        return
    end
    
    query = query:lower()
    local results = {}
    
    -- Search triggers
    for id, trigger in pairs(OxedHub.db.profile.triggers or {}) do
        local name = (trigger.name or ""):lower()
        local event = (trigger.event or ""):lower()
        local spellName = ""
        local spellId = ""
        local displaySpellName = ""
        if trigger.conditions and trigger.conditions.spellID then
            spellId = tostring(trigger.conditions.spellID):lower()
            local spellInfo = C_Spell.GetSpellInfo(tonumber(trigger.conditions.spellID) or trigger.conditions.spellID)
            if spellInfo and spellInfo.name then
                displaySpellName = spellInfo.name
                spellName = spellInfo.name:lower()
            end
        end
        local soundName = ""
        if trigger.actions and trigger.actions.sound then
            soundName = tostring(trigger.actions.sound):lower()
        end
        
        if name:find(query, 1, true) or 
           event:find(query, 1, true) or 
           spellName:find(query, 1, true) or 
           spellId:find(query, 1, true) or 
           soundName:find(query, 1, true) then
           
            local displayName = trigger.name or id
            if displaySpellName ~= "" then
                displayName = displayName .. " (" .. displaySpellName .. ")"
            end
            
            table.insert(results, {
                type = "Trigger",
                name = displayName,
                id = id,
                category = "Triggers",
                icon = "|TInterface\\Icons\\INV_Misc_Note_01:16|t",
            })
        end
    end
    
    -- Search sounds
    for id, sound in pairs(OxedHub.db.profile.customSounds or {}) do
        local name = (sound.name or ""):lower()
        if name:find(query) then
            table.insert(results, {
                type = "Sound",
                name = sound.name or id,
                id = id,
                category = "Sounds",
                icon = "|TInterface\\Icons\\INV_Misc_Drum_01:16|t",
            })
        end
    end
    
    -- Search animations
    for id, anim in pairs(OxedHub.db.profile.animations or {}) do
        local name = (anim.name or ""):lower()
        if name:find(query) then
            table.insert(results, {
                type = "Animation",
                name = anim.name or id,
                id = id,
                category = "Animations",
                icon = "|TInterface\\Icons\\Spell_Magic_PolymorphChicken:16|t",
            })
        end
    end
    
    -- Search chat templates
    for id, chat in pairs(OxedHub.db.profile.chatTemplates or {}) do
        local name = (chat.name or ""):lower()
        if name:find(query) then
            table.insert(results, {
                type = "Chat",
                name = chat.name or id,
                id = id,
                category = "Chat",
                icon = "|TInterface\\Icons\\INV_Letter_15:16|t",
            })
        end
    end
    
    -- Search toys
    for id, toy in pairs(OxedHub.db.profile.toys or {}) do
        local name = (toy.name or ""):lower()
        if name:find(query) then
            table.insert(results, {
                type = "Toy",
                name = toy.name or id,
                id = id,
                category = "Toys",
                icon = "|TInterface\\Icons\\INV_Misc_Toy_01:16|t",
            })
        end
    end
    
    -- Search emotions
    for _, emotion in ipairs(OxedHub.CONFIG.EMOTIONS or {}) do
        if emotion:lower():find(query) then
            table.insert(results, {
                type = "Emotion",
                name = emotion,
                id = emotion,
                category = "EmotionRing",
                icon = "|TInterface\\Icons\\Spell_Shadow_DetectInvisibility:16|t",
            })
        end
    end
    
    -- Sort results by type then name
    table.sort(results, function(a, b)
        if a.type ~= b.type then
            return a.type < b.type
        end
        return a.name < b.name
    end)
    
    -- Limit results
    local maxResults = 20
    if #results > maxResults then
        for i = maxResults + 1, #results do
            results[i] = nil
        end
    end
    
    self:DisplayResults(results)
end

-- Display search results
function Search:DisplayResults(results)
    if not searchDropdown then return end
    
    local scrollChild = searchDropdown.scrollChild
    
    -- Clear existing
    for _, child in ipairs({scrollChild:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    searchResults = results
    
    if #results == 0 then
        local empty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        empty:SetPoint("CENTER", scrollChild, "CENTER", 0, 0)
        empty:SetText("No results found")
        scrollChild:SetHeight(50)
    else
        local yOffset = -5
        for _, result in ipairs(results) do
            local row = self:CreateResultRow(scrollChild, result)
            row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, yOffset)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -5, yOffset)
            yOffset = yOffset - 30
        end
        scrollChild:SetHeight(math.abs(yOffset) + 10)
    end
    
    -- Position and show dropdown
    local mainFrame = OxedHub.mainFrame
    if mainFrame and mainFrame:IsShown() then
        searchDropdown:ClearAllPoints()
        searchDropdown:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -10, -80)
        searchDropdown:Show()
    end
end

-- Create result row
function Search:CreateResultRow(parent, result)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(25)
    
    row:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    })
    row:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
    
    -- Icon
    local iconText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    iconText:SetPoint("LEFT", row, "LEFT", 5, 0)
    iconText:SetText(result.icon)
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", iconText, "RIGHT", 5, 0)
    nameText:SetWidth(150)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(result.name)
    
    -- Type badge
    local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    typeText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
    typeText:SetText("|cffffcc00" .. result.type .. "|r")
    typeText:SetJustifyH("RIGHT")
    
    -- Hover effects
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.3, 0.4, 0.8)
    end)
    
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
    end)
    
    -- Click handler
    row:SetScript("OnClick", function()
        self:NavigateToResult(result)
        self:ClearResults()
    end)
    
    return row
end

-- Navigate to result
function Search:NavigateToResult(result)
    if result.category == "Triggers" then
        OxedHub.UI:ShowTab("Triggers")
        C_Timer.After(0.1, function()
            OxedHub.Triggers:ScrollToTrigger(result.id)
        end)
    elseif result.category == "Sounds" then
        OxedHub.UI:ShowTab("Reactions")
        C_Timer.After(0.1, function()
            OxedHub.UI:ShowSubTab("Sounds")
        end)
    elseif result.category == "Animations" then
        OxedHub.UI:ShowTab("Reactions")
        C_Timer.After(0.1, function()
            OxedHub.UI:ShowSubTab("Animations")
        end)
    elseif result.category == "Chat" then
        OxedHub.UI:ShowTab("Reactions")
        C_Timer.After(0.1, function()
            OxedHub.UI:ShowSubTab("Chat")
        end)
    elseif result.category == "Toys" then
        OxedHub.UI:ShowTab("Reactions")
        C_Timer.After(0.1, function()
            OxedHub.UI:ShowSubTab("Toys")
        end)
    elseif result.category == "EmotionRing" then
        OxedHub.UI:ShowTab("Reactions")
        C_Timer.After(0.1, function()
            OxedHub.UI:ShowSubTab("EmotionRing")
            C_Timer.After(0.1, function()
                if OxedHub.EmotionRing then
                    OxedHub.EmotionRing:TriggerEmotion(result.id)
                end
            end)
        end)
    end
end

-- Clear results
function Search:ClearResults()
    if searchDropdown then
        searchDropdown:Hide()
    end
    searchResults = {}
end

-- Get search dropdown
function Search:GetDropdown()
    return searchDropdown
end
