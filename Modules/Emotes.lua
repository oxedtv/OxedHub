local addonName, OxedHub = ...

-- Emotes Module - Game emote handling
local Emotes = {}
OxedHub.Emotes = Emotes

-- Local references
local DoEmote = DoEmote
local SendChatMessage = SendChatMessage
local GetTime = GetTime
local UnitName = UnitName

-- Emote cooldown
local lastEmoteTime = 0
local EMOTE_COOLDOWN = 0.5

-- Initialize
function Emotes:Init()
    -- Nothing special needed
end

-- Show Emotes UI
function Emotes:ShowUI(parent)
    -- Clear parent
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
    end
    
    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
    title:SetText("Emotes")
    
    -- Search filter
    local searchLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    searchLabel:SetText("Search:")
    
    local searchInput = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    searchInput:SetSize(200, 20)
    searchInput:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchInput:SetAutoFocus(false)
    
    -- Info text
    local infoText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -35)
    infoText:SetText("|cffffcc00Check 'Merge with sound' to auto-play with sounds|r")
    infoText:SetJustifyH("RIGHT")
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -70)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth() - 20, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Store reference for filtering
    parent.scrollChild = scrollChild
    parent.searchInput = searchInput
    
    searchInput:SetScript("OnTextChanged", function()
        self:RefreshEmoteList(scrollChild, searchInput:GetText())
    end)
    
    self:RefreshEmoteList(scrollChild, "")
end

-- Refresh emote list
function Emotes:RefreshEmoteList(parent, filter)
    -- Clear existing
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local yOffset = -5
    local xOffset = 5
    local colWidth = 140
    local col = 0
    
    -- Get emote list from Data.lua
    local emotes = OxedHub.EMOTE_LIST or {}
    
    for _, emote in ipairs(emotes) do
        local matchesFilter = true

        -- WoW uses Lua 5.1, so keep filtering logic free of goto/continue patterns.
        if filter and filter ~= "" then
            matchesFilter = emote:lower():find(filter:lower(), 1, true) ~= nil
        end

        if matchesFilter then
            -- Create emote row
            local row = self:CreateEmoteRow(parent, emote)

            -- Grid layout (4 columns)
            row:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset + (col * colWidth), yOffset)
            row:SetWidth(colWidth - 10)

            col = col + 1
            if col >= 4 then
                col = 0
                yOffset = yOffset - 30
            end
        end
    end
    
    -- Adjust height for grid
    if col > 0 then
        yOffset = yOffset - 30
    end
    
    parent:SetHeight(math.abs(yOffset) + 50)
end

-- Create emote row
function Emotes:CreateEmoteRow(parent, emoteName)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(25)
    
    -- Emote name (clickable to preview)
    local emoteBtn = CreateFrame("Button", nil, row)
    emoteBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    emoteBtn:SetSize(100, 20)
    
    local emoteText = emoteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    emoteText:SetPoint("LEFT", emoteBtn, "LEFT", 0, 0)
    emoteText:SetText(emoteName)
    
    emoteBtn:SetScript("OnClick", function()
        self:DoEmote(emoteName)
    end)
    
    emoteBtn:SetScript("OnEnter", function()
        emoteText:SetTextColor(1, 1, 0, 1)
    end)
    
    emoteBtn:SetScript("OnLeave", function()
        emoteText:SetTextColor(1, 1, 1, 1)
    end)
    
    -- Merge with sound checkbox
    local mergeCheck = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    mergeCheck:SetPoint("LEFT", emoteBtn, "RIGHT", 5, 0)
    mergeCheck:SetSize(15, 15)
    mergeCheck:SetScript("OnClick", function(self)
        -- Store merge preference
        local merges = OxedHub.db.profile.emoteMerges or {}
        merges[emoteName] = self:GetChecked()
        OxedHub.db.profile.emoteMerges = merges
    end)
    
    -- Load saved state
    local merges = OxedHub.db.profile.emoteMerges or {}
    mergeCheck:SetChecked(merges[emoteName] or false)
    
    return row
end

-- Perform emote
function Emotes:DoEmote(emoteName, whisperTarget, targetName)
    local now = GetTime()
    if now - lastEmoteTime < EMOTE_COOLDOWN then
        return -- On cooldown
    end
    lastEmoteTime = now
    
    if not emoteName or emoteName == "" then
        return
    end
    
    -- Convert emote name to uppercase for DoEmote
    emoteName = emoteName:upper()

    -- Do not perform emotes while dead
    if UnitIsDeadOrGhost("player") then
        return
    end
    
    -- Whisper target if requested
    if whisperTarget and targetName and targetName ~= "" then
        -- Route through the clean, untainted dispatcher
        OxedHub_DispatchEmote(emoteName, true, targetName)
    else
        -- Regular emote
        if InCombatLockdown() then
            -- Addons cannot perform emotes via DoEmote in combat
            print("|cff00ff00[OxedHub-Combat]|r emote: " .. emoteName)
        else
            -- Route through the clean, untainted dispatcher
            OxedHub_DispatchEmote(emoteName, false, nil)
        end
    end
end

-- Check if emote should merge with sound
function Emotes:ShouldMergeWithSound(emoteName)
    local merges = OxedHub.db.profile.emoteMerges or {}
    return merges[emoteName] or false
end

-- Play emote merged with sound (called from Sounds module)
function Emotes:PlayMerged(emoteName)
    if self:ShouldMergeWithSound(emoteName) then
        self:DoEmote(emoteName)
    end
end

-- Get all emotes
function Emotes:GetAllEmotes()
    return OxedHub.EMOTE_LIST or {}
end
