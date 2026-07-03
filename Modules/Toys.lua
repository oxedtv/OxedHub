local addonName, OxedHub = ...

-- Toys Module - Toy Management and Mixer
local Toys = {}
OxedHub.Toys = Toys

-- Local references
local L = OxedHub.L
local C_ToyBox = C_ToyBox
local PlayerHasToy = PlayerHasToy
local C_Timer = C_Timer

-- Mixer State
-- Each slot: { type="toy"|"spell", id=number } or nil
local selectedSlots = { nil, nil }

-- Tooltip scanner for item requirements (level, faction, class, race, etc.)
local reqScanTooltip = CreateFrame("GameTooltip", "OxedHubReqScanTooltip", nil, "GameTooltipTemplate")
reqScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

function Toys:GetItemRequirements(itemID)
    reqScanTooltip:ClearLines()
    reqScanTooltip:SetItemByID(itemID)
    local reqs = {}
    for i = 2, reqScanTooltip:NumLines() do
        local line = _G["OxedHubReqScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and (
                text:find("^Requires") or
                text:find(" Only$") or
                text:find("^Classes:") or
                text:find("^Races:") or
                text:find("Level %d+")
            ) then
                local r, g, b = line:GetTextColor()
                table.insert(reqs, { text = text, r = r, g = g, b = b })
            end
        end
    end
    return reqs
end

local mixerActions = {
    sound = nil,
    animation = nil,
    chat = nil,
    emote = nil,
}



local MIXER_CONTENT_Y_OFFSET = -40
local MIXER_PREVIEW_MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MIXER_PREVIEW_RING_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\ring"
local MIXER_PREVIEW_QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Helper: create a split icon frame (left half + right half)
local function CreateSplitIcon(parent, iconSize, leftIconPath, rightIconPath)
    local iconFrame = CreateFrame("Frame", nil, parent)
    iconFrame:SetSize(iconSize, iconSize)

    local leftTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    leftTexture:SetPoint("TOPLEFT", iconFrame, "TOPLEFT")
    leftTexture:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT")
    leftTexture:SetWidth(iconSize / 2)
    leftTexture:SetHeight(iconSize)
    leftTexture:SetTexture(leftIconPath)
    leftTexture:SetTexCoord(0, 0.5, 0, 1)

    local rightTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    rightTexture:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT")
    rightTexture:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT")
    rightTexture:SetWidth(iconSize / 2)
    rightTexture:SetHeight(iconSize)
    rightTexture:SetTexture(rightIconPath)
    rightTexture:SetTexCoord(0.5, 1, 0, 1)
    iconFrame.leftTexture = leftTexture
    iconFrame.rightTexture = rightTexture

    return iconFrame
end

-- Public wrapper so other modules (ActionHub) can reuse the split icon
function Toys:CreateSplitIcon(parent, iconSize, leftIconPath, rightIconPath)
    return CreateSplitIcon(parent, iconSize, leftIconPath, rightIconPath)
end

local function TruncateText(text, maxLen)
    if not text then return nil end
    maxLen = maxLen or 15
    if #text > maxLen then
        return text:sub(1, maxLen - 3) .. "..."
    end
    return text
end

function Toys:GetSoundDisplayName(soundId)
    if not soundId or soundId == "" then return nil end
    local name = soundId
    local sounds = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds
    if sounds and sounds[soundId] and sounds[soundId].name then
        name = sounds[soundId].name
    end

    -- Strip "oxedhub_" or "oxedhub " or similar prefix case-insensitively
    name = name:gsub("^[Oo][Xx][Ee][Dd][Hh][Uu][Bb][_%s]*", "")
    name = name:gsub("^[Oo][Xx][Ee][Dd][_%s]*", "")

    -- Strip known category prefixes
    local prefixes = {
        "death_", "dh_pack_", "monk_pack_", "worrier_pack_",
        "anime_", "arabic_", "effects_", "meme_", "legions_", "quote_", "other_"
    }
    local lowerName = name:lower()
    for _, prefix in ipairs(prefixes) do
        if lowerName:sub(1, #prefix) == prefix then
            name = name:sub(#prefix + 1)
            break
        end
    end

    return TruncateText(name, 15)
end


local function GetSafeMixMacroName(mixName)
    local clean = tostring(mixName or "Mix"):gsub("[^%w]", "")
    if clean == "" then clean = "Mix" end

    local hash = 0
    local source = tostring(mixName or "Mix")
    for i = 1, #source do
        hash = (hash + (source:byte(i) or 0) * i) % 10000
    end

    return ("OHM_%s_%04d"):format(clean:sub(1, 7), hash)
end

-- Helper: get both slot icon textures for a mix name
local function GetToyIconTexture(itemID)
    if not itemID then
        return nil
    end

    local _, _, icon = C_ToyBox.GetToyInfo(itemID)
    if icon then
        return icon
    end

    if C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return icon
        end
    end

    local _, _, _, _, instantIcon = GetItemInfoInstant(itemID)
    return instantIcon
end

function Toys:GetToyCooldown(itemID)
    if not itemID then return 0 end
    
    self._cdCache = self._cdCache or {}
    if self._cdCache[itemID] then
        return self._cdCache[itemID]
    end
    
    local cd = 0
    local foundInTooltip = false
    
    -- Priority 1: Tooltip Scanning (Most accurate for toys since spells can have generic cooldowns)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local tooltipData = C_TooltipInfo.GetItemByID(itemID)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                if line.leftText then
                    local lowerText = line.leftText:lower()
                    
                    if lowerText == "retrieving item information" or lowerText == "retrieving item information." then
                        -- Item not loaded from server yet. Don't cache a fallback. Return 0 for now.
                        return 0
                    end
                    
                    -- Match Cooldown keywords across WoW locales (EN, DE, FR, RU, ES, PT, IT)
                    if lowerText:find("cooldown") or lowerText:find("abklingzeit") or lowerText:find("recharge") 
                        or lowerText:find("восстановление") or lowerText:find("reutilización") 
                        or lowerText:find("recarga") or lowerText:find("recupero") then
                        
                        -- Match time units across locales
                        local days = lowerText:match("(%d+)%s*day") or lowerText:match("(%d+)%s*tag") or lowerText:match("(%d+)%s*jour") or lowerText:match("(%d+)%s*d") or lowerText:match("(%d+)%s*д") or lowerText:match("(%d+)%s*día") or lowerText:match("(%d+)%s*dia")
                        local hours = lowerText:match("(%d+)%s*hr") or lowerText:match("(%d+)%s*hour") or lowerText:match("(%d+)%s*std") or lowerText:match("(%d+)%s*heure") or lowerText:match("(%d+)%s*h") or lowerText:match("(%d+)%s*ч") or lowerText:match("(%d+)%s*hora")
                        local mins = lowerText:match("(%d+)%s*min") or lowerText:match("(%d+)%s*m") or lowerText:match("(%d+)%s*мин")
                        local secs = lowerText:match("(%d+)%s*sec") or lowerText:match("(%d+)%s*sek") or lowerText:match("(%d+)%s*seg") or lowerText:match("(%d+)%s*s") or lowerText:match("(%d+)%s*сек")
                        
                        local total = 0
                        if days then total = total + tonumber(days) * 86400 end
                        if hours then total = total + tonumber(hours) * 3600 end
                        if mins then total = total + tonumber(mins) * 60 end
                        if secs then total = total + tonumber(secs) end
                        
                        if total > 0 then
                            cd = total
                            foundInTooltip = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- Priority 2: Spell Base Cooldown (Fallback if tooltip doesn't explicitly mention it)
    if not foundInTooltip then
        local _, spellID
        if C_Item and C_Item.GetItemSpell then
            _, spellID = C_Item.GetItemSpell(itemID)
        elseif GetItemSpell then
            _, spellID = GetItemSpell(itemID)
        end
        
        if spellID and GetSpellBaseCooldown then
            local spellCD = GetSpellBaseCooldown(spellID)
            if spellCD and spellCD > 0 then
                cd = spellCD / 1000 -- Convert ms to seconds
            end
        end
    end
    
    self._cdCache[itemID] = cd
    return cd
end

function Toys:GetMixSlotIcons(mixName)
    local mixes = OxedHub.db.profile.toyMixes
    local mixData = mixes and mixes[mixName]
    if type(mixData) ~= "table" or not mixData.slots then
        return "Interface\\Icons\\INV_Misc_QuestionMark",
               "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local icons = {}
    for _, slot in ipairs(mixData.slots) do
        if slot then
            if slot.type == "toy" then
                local icon = GetToyIconTexture(slot.id)
                if icon then table.insert(icons, icon) end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.iconID then
                    table.insert(icons, spellInfo.iconID)
                end
            end
        end
    end

    return icons[1] or "Interface\\Icons\\INV_Misc_QuestionMark",
           icons[2] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Toys:DoesPlayerOwnToy(itemID)
    local id = tonumber(itemID)
    return id and PlayerHasToy(id) == true
end

function Toys:GetMixToyAvailability(mixData)
    local totalToys = 0
    local missingToys = 0

    if type(mixData) ~= "table" then
        return totalToys, missingToys
    end

    for _, slot in ipairs(mixData.slots or {}) do
        if slot and slot.type == "toy" and slot.id then
            totalToys = totalToys + 1
            if not self:DoesPlayerOwnToy(slot.id) then
                missingToys = missingToys + 1
            end
        end
    end

    return totalToys, missingToys
end

local function ApplyMissingVisual(frame, isMissing)
    if not frame then
        return
    end

    if frame.tex then
        if isMissing then
            frame.tex:SetDesaturated(true)
            frame.tex:SetVertexColor(0.45, 0.45, 0.45, 1)
        else
            frame.tex:SetDesaturated(false)
            frame.tex:SetVertexColor(1, 1, 1, 1)
        end
    end

    if frame.SetBackdropBorderColor then
        if isMissing then
            frame:SetBackdropBorderColor(0.7, 0.15, 0.15, 1)
        else
            frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        end
    end
end

-- Initialize
function Toys:Init()
    -- Ensure mixer actions table exists in profile
    if not OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes = {}
    end

    OxedHub.db.profile.toyCollectionCache = OxedHub.db.profile.toyCollectionCache or {
        toyIDs = {},
        toyCache = {},
        stale = false,
    }

    local savedCache = OxedHub.db.profile.toyCollectionCache
    self.toyCache = savedCache.toyCache or {}
    self.toyIDs = savedCache.toyIDs or {}
    self.toyDataInitialized = next(self.toyCache) ~= nil or #self.toyIDs > 0
    self.toyDataDirty = savedCache.stale == true
    self._toyRefreshPending = false

    -- Listen for toy box updates, but do not auto-rescan.
    -- Just mark the saved cache stale so the user can refresh manually.
    if not self._toyEventFrame then
        self._toyEventFrame = CreateFrame("Frame")
        self._toyEventFrame:SetScript("OnEvent", function(_, event)
            if event == "TOYS_UPDATED" then
                Toys.toyDataDirty = true
                local cache = OxedHub.db.profile.toyCollectionCache
                if cache then
                    cache.stale = true
                end
                if Toys.currentMixerScrollChild then
                    Toys:UpdateToyCacheStatus()
                end
            end
        end)
    end
    self._toyEventFrame:RegisterEvent("TOYS_UPDATED")
end

function Toys:EnsureToyData(silent)
    if not self.toyDataInitialized then
        self:CacheToyData(silent)
    end
end

function Toys:PersistToyCache()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then
        return
    end

    profile.toyCollectionCache = profile.toyCollectionCache or {}
    profile.toyCollectionCache.toyIDs = self.toyIDs
    profile.toyCollectionCache.toyCache = self.toyCache
    profile.toyCollectionCache.stale = self.toyDataDirty == true
end

function Toys:UpdateToyCacheStatus()
    if not self.toyCacheStatusText then
        return
    end

    if not self.toyDataInitialized then
        self.toyCacheStatusText:SetText("|cffffcc00" .. (L["TOY_CACHE_EMPTY"] or "Toy cache empty. Click Refresh Toys.") .. "|r")
    elseif self.toyDataDirty then
        self.toyCacheStatusText:SetText("|cffffcc00" .. (L["TOY_CACHE_OUTDATED"] or "Toy cache may be outdated. Click Refresh Toys after learning a new toy.") .. "|r")
    else
        self.toyCacheStatusText:SetText("|cff88ff88" .. (L["TOY_CACHE_SAVED"] or "Using saved toy cache. Refresh only when you learn a new toy.") .. "|r")
    end

    if self.toyCountText then
        local count = #self.toyIDs
        self.toyCountText:SetText("|cffe6d9cc" .. string.format(L["TOY_COLLECTED_COUNT"] or "%d toys collected", count) .. "|r")
    end
end

-- Cache toy names and info (All collected toys)
-- @param silent boolean  If true, suppress chat prints (used by retry loops)
function Toys:CacheToyData(silent)
    self.toyCache = {}
    self.toyIDs = {}
    
    -- Save old filter states to restore them later
    local oldCollected = C_ToyBox.GetCollectedShown()
    local oldUncollected = C_ToyBox.GetUncollectedShown()
    local oldUnusable = C_ToyBox.GetUnusableShown()
    
    -- 1. Reset all filters (CollectMe approach)
    C_ToyBox.SetFilterString("")
    C_ToyBox.SetUnusableShown(true) -- Show toys for other classes/profs too
    C_ToyBox.SetCollectedShown(true)
    C_ToyBox.SetUncollectedShown(false)
    
    -- 2. Clear ALL source filters
    if C_ToyBox.SetAllSourceTypeFilters then
        C_ToyBox.SetAllSourceTypeFilters(true)
    end
    
    -- 3. FORCE the game to apply these filters before we scan (Crucial!)
    C_ToyBox.ForceToyRefilter()
    
    -- 4. Get the total count of toys
    local numToys = C_ToyBox.GetNumFilteredToys() or 0
    
    -- 5. Loop through each toy index and grab the itemID
    for i = 1, numToys do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID and PlayerHasToy(itemID) then
            -- 6. Get detailed info for each toy
            local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
            if toyName then
                -- 7. Store the data in our local cache
                self.toyCache[itemID] = {
                    name = toyName,
                    icon = icon,
                    itemID = itemID,
                }
                table.insert(self.toyIDs, itemID)
            end
        end
    end
    
    -- Restore user's filters
    C_ToyBox.SetCollectedShown(oldCollected)
    C_ToyBox.SetUncollectedShown(oldUncollected)
    C_ToyBox.SetUnusableShown(oldUnusable)
    C_ToyBox.ForceToyRefilter()
    
    -- Active Debug Message (So we know it worked)
    if not silent then
        if #self.toyIDs > 0 then
            -- Scanned account debug hidden
        else
            -- Toy scan retry debug hidden
        end
    end
    
    -- Sort toy IDs by name
    table.sort(self.toyIDs, function(a, b)
        if not self.toyCache[a] or not self.toyCache[b] then return false end
        return self.toyCache[a].name < self.toyCache[b].name
    end)

    self.toyDataInitialized = true
    self.toyDataDirty = false
    self:PersistToyCache()
    self:UpdateToyCacheStatus()
end

function Toys:ShowMixerTab(parent)
    self.currentMixerScrollChild = parent.scrollChild
    self:EnsureToyData(true)

    if OxedHub.UI and OxedHub.UI.searchBox and parent.scrollChild then
        OxedHub.UI.searchBox.customSearchHandler = function(eb, text)
            self:RefreshToyGrid(parent.scrollChild, text or "")
        end
    end

    if parent.initialized then 
        parent:Show()
        return 
    end
    parent.initialized = true

    -- Grid Section
    local gridFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    gridFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    gridFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    gridFrame:SetHeight(165)
    -- gridFrame:SetBackdrop({
    --     bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    --     edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    --     tile = true, tileSize = 16, edgeSize = 12,
    -- })
    -- gridFrame:SetBackdropColor(0.04, 0.03, 0.02, 0.18)
    -- gridFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local refreshBtn = CreateFrame("Button", nil, gridFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(130, 24)
    refreshBtn:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 33, -8)
    refreshBtn:SetText(L["SETTINGS_BTN_REFRESH_TOYS"] or "Refresh Toys")
    refreshBtn:SetScript("OnClick", function()
        self:CacheToyData()
        if parent.scrollChild then
            self:RefreshToyGrid(parent.scrollChild, OxedHub.globalSearchText or "")
        end
    end)

    local filterDropdown = CreateFrame("DropdownButton", "OxedHubToyCooldownFilterDropdown", gridFrame, "WowStyle1DropdownTemplate")
    if filterDropdown then
        filterDropdown:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", -65, -14)
        filterDropdown:SetWidth(130)
        
        local filterOptions = {
            { text = L["TOYS_CD_ALL"] or "All Cooldowns", value = 0 },
            { text = L["TOYS_CD_NONE"] or "No Cooldown", value = 1 },
            { text = L["TOYS_CD_LESS_1"] or "< 1 Min", value = 60 },
            { text = L["TOYS_CD_1_5"] or "1 - 5 Mins", value = 300 },
            { text = L["TOYS_CD_5_10"] or "5 - 10 Mins", value = 600 },
            { text = L["TOYS_CD_10_30"] or "10 - 30 Mins", value = 1800 },
            { text = L["TOYS_CD_MORE_30"] or "> 30 Mins", value = 9999 },
        }
        
        local function UpdateCooldownFilterText()
            local val = self.currentCooldownFilter or 0
            for _, opt in ipairs(filterOptions) do
                if opt.value == val then
                    filterDropdown:OverrideText(opt.text)
                    return
                end
            end
            filterDropdown:OverrideText(L["TOYS_CD_ALL"] or "All Cooldowns")
        end
        
        filterDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, opt in ipairs(filterOptions) do
                rootDescription:CreateRadio(opt.text,
                    function() return (self.currentCooldownFilter or 0) == opt.value end,
                    function()
                        self.currentCooldownFilter = opt.value
                        UpdateCooldownFilterText()
                        if parent.scrollChild then
                            self:RefreshToyGrid(parent.scrollChild, OxedHub.globalSearchText or "")
                        end
                    end
                )
            end
        end)
        UpdateCooldownFilterText()
    end

    local toyCountText = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if filterDropdown then
        toyCountText:SetPoint("BOTTOM", filterDropdown, "TOP", 0, 2)
    else
        toyCountText:SetPoint("RIGHT", gridFrame, "RIGHT", -42, 0)
        toyCountText:SetPoint("TOP", refreshBtn, "TOP", 0, -3)
    end
    toyCountText:SetJustifyH("CENTER")
    self.toyCountText = toyCountText

    local cacheStatusText = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheStatusText:SetPoint("LEFT", refreshBtn, "RIGHT", 10, 0)
    if filterDropdown then
        cacheStatusText:SetPoint("RIGHT", filterDropdown, "LEFT", -15, 0)
    else
        cacheStatusText:SetPoint("RIGHT", toyCountText, "LEFT", -8, 0)
    end
    cacheStatusText:SetJustifyH("LEFT")
    cacheStatusText:SetTextColor(0.85, 0.85, 0.85, 1)
    self.toyCacheStatusText = cacheStatusText
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, gridFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 45, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", -65, -145)
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:ClearAllPoints()
        scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, 2)
        scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMRIGHT", -35, 55)
    end
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    local toyScrollBar = scrollFrame.oxedMinimalScrollBar or scrollFrame.ScrollBar
    if toyScrollBar then
        toyScrollBar:ClearAllPoints()
        toyScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, 2)
        toyScrollBar:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMRIGHT", -35, -40)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    parent.scrollChild = scrollChild
    self.currentMixerScrollChild = scrollChild

    -- Mixer Section (CREATE FIRST before blocker)
    local mixerFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    mixerFrame:SetPoint("TOPLEFT", gridFrame, "BOTTOMLEFT", 0, -10)
    mixerFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    mixerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
    })
    mixerFrame:SetBackdropColor(0, 0, 0, 0)
    mixerFrame:SetBackdropBorderColor(0, 0, 0, 0)
    mixerFrame:SetFrameLevel(gridFrame:GetFrameLevel() + 55)  -- above the blocker (+50)

    local mixerBg = mixerFrame:CreateTexture(nil, "BACKGROUND")
    mixerBg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg-low.png")
    mixerBg:SetTexCoord(0, 1, 0, 1)
    mixerBg:SetAlpha(1)
    mixerFrame.backgroundTexture = mixerBg

    -- NOW create the blocker AFTER mixerFrame exists
    local pngBlocker = CreateFrame("Frame", "OxedHubToysDebugBlocker", parent, "BackdropTemplate")
    pngBlocker:SetFrameStrata("DIALOG")  -- same as contentArea
    pngBlocker:SetFrameLevel(110)  -- just above contentArea (102)
    pngBlocker:EnableMouse(true)
    pngBlocker:SetHitRectInsets(0, 0, 0, 0)
    pngBlocker:Show()
    pngBlocker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    pngBlocker:SetBackdropColor(0, 0, 0, 0)
    
    -- Hide blocker when parent frame hides
    parent:HookScript("OnHide", function()
        pngBlocker:Hide()
    end)
    parent:HookScript("OnShow", function()
        pngBlocker:Show()
    end)

    local function ResizeMixerBackground()
        local frameWidth = mixerFrame:GetWidth() or 0
        local frameHeight = mixerFrame:GetHeight() or 0
        if frameWidth <= 0 or frameHeight <= 0 then
            return
        end

        mixerBg:ClearAllPoints()
        mixerBg:SetPoint("CENTER", mixerFrame, "CENTER", 0, 19 + MIXER_CONTENT_Y_OFFSET)
        local bgW = math.max(1, (frameWidth - 9) * 0.945)
        local bgH = math.max(1, (frameHeight - 14) * 0.735) + 20
        mixerBg:SetWidth(bgW)
        mixerBg:SetHeight(bgH)

        -- Position the pngBlocker to cover the bottom toy rows under the parchment
        local gridWidth = gridFrame:GetWidth() or 800
        local gridHeight = gridFrame:GetHeight() or 165
        local blockerHeight = 100  -- fixed height to cover bottom toy rows
        
        pngBlocker:ClearAllPoints()
        -- Position 100px lower (more down) from the bottom of gridFrame
        -- Inset 50px from left and right
        pngBlocker:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", 50, -(blockerHeight + 100))
        pngBlocker:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", -50, -(blockerHeight + 100))
        pngBlocker:SetHeight(blockerHeight)
    end

    mixerFrame:SetScript("OnSizeChanged", ResizeMixerBackground)
    ResizeMixerBackground()
    
    self:CreateMixerUI(mixerFrame)
    
    -- Hook Search Box (from UI.lua)
    if OxedHub.UI.searchBox and parent.scrollChild then
        OxedHub.UI.searchBox.customSearchHandler = function(eb, text)
            self:RefreshToyGrid(parent.scrollChild, text or "")
        end
    end
    
    self:EnsureToyData(true)
    self:UpdateToyCacheStatus()
    self:RefreshToyGrid(scrollChild, "")
end

function Toys:ShowLibraryTab(parent)
    if parent.initialized then
        self:RefreshSavedMixesList()
        return
    end
    parent.initialized = true

    local libFrame = CreateFrame("Frame", nil, parent)
    libFrame:SetAllPoints()
    
    self:CreateSavedMixesUI(libFrame)
end

function Toys:ShowQuickMixesTab(parent)
    if parent.initialized then
        self:RefreshQuickMixesGrid()
        return
    end
    parent.initialized = true

    local gridFrame = CreateFrame("Frame", nil, parent)
    gridFrame:SetAllPoints()

    local title = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", gridFrame, "TOP", 0, -10)
    title:SetText(L["TOY_QUICK_MIXES"] or "Quick Mixes")
    title:SetTextColor(1, 0.82, 0, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, gridFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)

    self.quickMixesScrollChild = scrollChild
    self:RefreshQuickMixesGrid()
end

function Toys:RefreshQuickMixesGrid()
    local parent = self.quickMixesScrollChild
    if not parent then return end

    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local mixes = OxedHub.db.profile.toyMixes or {}
    local mixNames = {}
    for name in pairs(mixes) do
        table.insert(mixNames, name)
    end

    local btnSize = 64
    local spacing = 12
    local cols = 4
    local x, y = 0, 0

    for i, mixName in ipairs(mixNames) do
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(btnSize, btnSize)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x * (btnSize + spacing), -y * (btnSize + spacing + 20))
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

        local icon1, icon2 = self:GetMixSlotIcons(mixName)
        local splitIcon = CreateSplitIcon(btn, btnSize - 8, icon1, icon2)
        splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 6)

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
        label:SetText(mixName)
        label:SetWidth(btnSize - 4)
        label:SetJustifyH("CENTER")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(mixName, 1, 0.82, 0)
            GameTooltip:AddLine("|cff00ff00Click to assign to selected emotion node|r", 0, 1, 0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            local selectedEmotion = ToyRing and ToyRing.GetSelectedEmotion and ToyRing:GetSelectedEmotion()
            if selectedEmotion then
                ToyRing:SetEmotionMapping(selectedEmotion, "toyMacro", mixName)
                print("|cff00ff00[OxedHub]|r Assigned |cffffd100" .. mixName .. "|r to |cffffd100" .. selectedEmotion .. "|r")
                ToyRing:RefreshAssignmentPanel()
                ToyRing:RefreshNodeStyles()
            else
                print("|cffff0000[OxedHub]|r Select an emotion node in the Ring tab first.")
            end
        end)

        x = x + 1
        if x >= cols then
            x = 0
            y = y + 1
        end
    end

    local rows = math.max(math.ceil(#mixNames / cols), 1)
    parent:SetHeight(rows * (btnSize + spacing + 20) + 20)
    parent:SetWidth(cols * (btnSize + spacing))
end

local function RefreshMixConsumers()
    if OxedHub.ActionHub then
        if OxedHub.ActionHub.RefreshPickerList then
            OxedHub.ActionHub:RefreshPickerList()
        end
        if OxedHub.ActionHub.RefreshTab then
            OxedHub.ActionHub:RefreshTab()
        end
        if OxedHub.ActionHub.RefreshAllWidgets then
            OxedHub.ActionHub:RefreshAllWidgets()
        end
    end

    if OxedHub.EmotionRing and OxedHub.EmotionRing.RefreshAssignmentPanel then
        OxedHub.EmotionRing:RefreshAssignmentPanel()
    end

    if OxedHub.ToyRing then
        if OxedHub.ToyRing.RefreshAssignmentPanel then
            OxedHub.ToyRing:RefreshAssignmentPanel()
        end
        if OxedHub.ToyRing.RefreshNodeStyles then
            OxedHub.ToyRing:RefreshNodeStyles()
        end
    end
end

-- Refresh Toy Grid
function Toys:RefreshToyGrid(parent, filter)
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    filter = (filter or ""):lower()
    local sideInset = 12
    local x, y = sideInset, -5
    local spacing = 6
    local iconSize = 44
    local bottomPaddingRows = 2
    local iconsPerRow = math.max(1, math.floor((parent:GetWidth() - (sideInset * 2)) / (iconSize + spacing)))
    local count = 0
    
    for _, itemID in ipairs(self.toyIDs) do
        local data = self.toyCache[itemID]
        
        -- Cooldown Filter Logic
        local cd = self:GetToyCooldown(itemID)
        local filterVal = self.currentCooldownFilter or 0
        local passFilter = true
        if filterVal == 1 then
            passFilter = (cd == 0)
        elseif filterVal == 60 then
            passFilter = (cd > 0 and cd < 60)
        elseif filterVal == 300 then
            passFilter = (cd >= 60 and cd <= 300)
        elseif filterVal == 600 then
            passFilter = (cd > 300 and cd <= 600)
        elseif filterVal == 1800 then
            passFilter = (cd > 600 and cd <= 1800)
        elseif filterVal == 9999 then
            passFilter = (cd > 1800)
        end
        
        if passFilter and (filter == "" or data.name:lower():find(filter, 1, true)) then
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetSize(iconSize, iconSize)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(iconSize - 6, iconSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(data.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = iconTex

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetToyByItemID(itemID)
                GameTooltip:AddLine("\n|cff00ff00" .. (L["TOYS_CLICK_TO_SELECT_MIXER"] or "Click to select for Mixer") .. "|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)
            
            btn:SetScript("OnClick", function()
                local ctype, itemID_cursor = GetCursorInfo()
                if ctype == "item" or ctype == "toy" then
                    self:SelectSlotForMixer("toy", itemID_cursor)
                    ClearCursor()
                else
                    self:SelectSlotForMixer("toy", itemID)
                end
            end)
            
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function()
                PickupItem(itemID)
            end)
            
            count = count + 1
            x = x + iconSize + spacing
            if count % iconsPerRow == 0 then
                x = sideInset
                y = y - (iconSize + spacing)
            end
        end
    end
    
    parent:SetHeight(math.abs(y) + iconSize + ((iconSize + spacing) * bottomPaddingRows) + 10)
end

-- Select item for Mixer slot (toy or spell)
function Toys:SelectSlotForMixer(slotType, id, targetSlot)
    if not id then return end
    local newSlot = { type = slotType, id = id }
    -- Prevent duplicate exact slots
    if selectedSlots[1] and selectedSlots[1].type == slotType and selectedSlots[1].id == id then return end
    if selectedSlots[2] and selectedSlots[2].type == slotType and selectedSlots[2].id == id then return end

    if targetSlot then
        selectedSlots[targetSlot] = newSlot
    elseif not selectedSlots[1] then
        selectedSlots[1] = newSlot
    elseif not selectedSlots[2] then
        selectedSlots[2] = newSlot
    else
        -- Shift and replace
        selectedSlots[1] = selectedSlots[2]
        selectedSlots[2] = newSlot
    end

    if self.UpdateMixerIcons then
        self:UpdateMixerIcons()
    end
end

-- Create Mixer UI
function Toys:CreateMixerUI(frame)
    local iconSize = 53

    local slotChoiceLabel = frame:CreateFontString(nil, 'OVERLAY')
    slotChoiceLabel:SetPoint('TOPLEFT', frame, 'TOPLEFT', 216, -55 + MIXER_CONTENT_Y_OFFSET)
    slotChoiceLabel:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 34)
    slotChoiceLabel:SetText(L["TOY_CHOOSE_SLOT"] or "Choose toy or spell")
    slotChoiceLabel:SetTextColor(0.22, 0.18, 0.17, 1.0)
    
    -- Magical inscription on the parchment using the custom Darling Charm font
    local magicText = frame:CreateFontString(nil, "OVERLAY")
    magicText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 75, 82)
    magicText:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 24)
    magicText:SetText(L["TOYS_DEATHWING_QUOTE"] or "I am the bringer of destruction,\nthe end of all things – inevitable,\nundeniable, and I am the Cataclysm")
    magicText:SetTextColor(0.22, 0.18, 0.17, 1.0)
    magicText:SetJustifyH("LEFT")
    
    -- Slot 1
    local slot1 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot1:SetSize(iconSize, iconSize)
    slot1:SetPoint("TOPLEFT", frame, "TOPLEFT", 237, -89 + MIXER_CONTENT_Y_OFFSET)
    slot1:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot1:SetBackdropColor(0, 0, 0, 0.5)
    
    local icon1 = slot1:CreateTexture(nil, "ARTWORK")
    icon1:SetAllPoints()
    icon1:Hide()

    slot1:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot1:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    slot1:SetScript("OnEnter", function(self)
        local slot = selectedSlots[1]
        if not slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            local spellInfo = C_Spell.GetSpellInfo(slot.id)
            GameTooltip:SetSpellByID(slot.id)
            if spellInfo then
                GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
            end
        end
        GameTooltip:Show()
    end)
    slot1:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot1:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            selectedSlots[1] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 1)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 1)
            ClearCursor()
        else
            selectedSlots[1] = nil
            self:UpdateMixerIcons()
        end
    end)
    
    -- Slot 2
    local slot2 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot2:SetSize(iconSize, iconSize)
    slot2:SetPoint("TOPLEFT", frame, "TOPLEFT", 335, -89 + MIXER_CONTENT_Y_OFFSET)
    slot2:SetFrameLevel(frame:GetFrameLevel() + 30)
    slot2:RegisterForClicks("AnyUp")
    slot2:RegisterForDrag("LeftButton")
    slot2:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot2:SetBackdropColor(0, 0, 0, 0.5)
    
    local icon2 = slot2:CreateTexture(nil, "ARTWORK")
    icon2:SetAllPoints()
    icon2:Hide()

    slot2:SetBackdropBorderColor(0.18, 0.58, 1, 1)

    local spellSlotHint = frame:CreateFontString(nil, 'OVERLAY')
    spellSlotHint:Hide()
    spellSlotHint:SetPoint('LEFT', slot2, 'RIGHT', 4, 1)
    spellSlotHint:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 23)
    spellSlotHint:SetText(L["TOY_SPELL_HINT"] or "Spell")
    spellSlotHint:SetTextColor(0.22, 0.18, 0.17, 1.0)

    local function ShowSpellSlotTooltip(owner)
        local slot = selectedSlots[2]
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["TOY_SECONDARY_SLOT"] or "Secondary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            local spellInfo = C_Spell.GetSpellInfo(slot.id)
            GameTooltip:SetSpellByID(slot.id)
            if spellInfo then
                GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
            end
        end
        GameTooltip:Show()
    end

    slot2:SetScript("OnEnter", function(self)
        ShowSpellSlotTooltip(self)
    end)
    slot2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function HandleSpellSlotClick(_, button)
        if button == "RightButton" then
            selectedSlots[2] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        else
            self:ShowSpellPickerForMixer()
        end
    end

    slot2:SetScript("OnClick", HandleSpellSlotClick)

    local spellSlotClickCatcher = CreateFrame("Button", nil, frame)
    spellSlotClickCatcher:SetPoint("TOPLEFT", slot2, "TOPLEFT", 0, 0)
    spellSlotClickCatcher:SetPoint("BOTTOMRIGHT", slot2, "BOTTOMRIGHT", 0, 0)
    spellSlotClickCatcher:SetFrameLevel(frame:GetFrameLevel() + 120)
    spellSlotClickCatcher:RegisterForClicks("AnyUp")
    spellSlotClickCatcher:RegisterForDrag("LeftButton")
    spellSlotClickCatcher:SetScript("OnEnter", function(self)
        ShowSpellSlotTooltip(self)
    end)
    spellSlotClickCatcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    spellSlotClickCatcher:SetScript("OnClick", HandleSpellSlotClick)
    spellSlotClickCatcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    spellSlotClickCatcher:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        end
    end)

    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    plus:SetPoint("CENTER", slot1, "RIGHT", 11, 0)
    plus:SetText("+")
    plus:SetScale(2)

    -- Pick Spell button
    local pickSpellBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pickSpellBtn:SetSize(100, 20)
    pickSpellBtn:SetPoint("TOP", slot2, "BOTTOM", 0, -6)
    pickSpellBtn:SetText(L["MIXER_PICK_SPELL"] or "Pick Spell")
    pickSpellBtn:SetNormalFontObject("GameFontNormalSmall")
    pickSpellBtn:SetScript("OnClick", function()
        self:ShowSpellPickerForMixer()
    end)
    pickSpellBtn:Hide()

    -- Actions Section
    local yOffset = -75 + MIXER_CONTENT_Y_OFFSET
    
    local function CreateActionRow(label, type)
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(180, 26)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -72, yOffset)

        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(126, 22)
        btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btn:SetText(label)
        
        btn:SetScript("OnClick", function()
            self:ShowPickerForMixer(type, btn)
        end)

        local iconBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        iconBtn:SetSize(22, 22)
        iconBtn:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        iconBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        iconBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        iconBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("TOPLEFT", iconBtn, "TOPLEFT", 2, -2)
        iconTex:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -2, 2)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        local iconPaths = {
            sound = "Interface\\Icons\\INV_Misc_Horn_01",
            emote = "Interface\\Icons\\UI_Chat",
            animation = "Interface\\Icons\\Ability_Rogue_Sprint",
            chat = "Interface\\Icons\\INV_Misc_Note_01",
        }
        iconTex:SetTexture(iconPaths[type] or "Interface\\Icons\\INV_Misc_QuestionMark")

        iconBtn:SetScript("OnClick", function()
            self:ShowPickerForMixer(type, btn)
        end)
        
        iconBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
        end)
        iconBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end)
        
        yOffset = yOffset - 30
        return btn
    end
    
    local soundBtn = CreateActionRow(L["TOYS_ACT_ADD_SOUND"] or "Add Sound", "sound")
    local emotionBtn = CreateActionRow(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote", "emote")
    local animBtn = CreateActionRow(L["TOYS_ACT_ADD_ANIM"] or "Add Animation", "animation")
    local textBtn = CreateActionRow(L["TOYS_ACT_ADD_TEXT"] or "Add Text", "chat")
    
    -- Macro Section (Internal Mix Panel)
    local macroFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    macroFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 447, -48 + MIXER_CONTENT_Y_OFFSET)
    macroFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -51, 75 + MIXER_CONTENT_Y_OFFSET)
    macroFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
    })
    macroFrame:SetBackdropColor(0, 0, 0, 0)
    macroFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local macroBg = macroFrame:CreateTexture(nil, "BACKGROUND")
    macroBg:SetAllPoints(macroFrame)
    macroBg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-mix-bg.png")
    macroBg:SetTexCoord(0, 1, 0, 1)
    macroBg:Hide()
    macroFrame.backgroundTexture = macroBg

    local macroText = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroText:SetPoint("TOP", macroFrame, "TOP", 0, -15)
    macroText:SetText(L["TOY_INTERNAL_MIX"] or "Internal Mix")
    macroText:Hide()

    local macroIcon = CreateFrame("Button", nil, macroFrame)
    macroIcon:SetSize(88, 88)
    macroIcon:SetPoint("CENTER", frame, "CENTER", -5, 43 + MIXER_CONTENT_Y_OFFSET)
    macroIcon:EnableMouse(true)
    macroIcon:RegisterForDrag("LeftButton")

    -- Ring Animation Texture - RIGHT UNDER the split icons (ARTWORK layer, sublayer -1)
    local animTex = macroIcon:CreateTexture(nil, "ARTWORK", nil, -1)
    animTex:SetPoint("CENTER", macroIcon, "CENTER", 0, 0)  -- Moved right 5px
    animTex:SetSize(344, 344)  -- 30% smaller (originally 492x492), 1:1 aspect ratio
    animTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_00001.png")
    animTex:SetBlendMode("ADD")
    animTex:SetAlpha(0.8)
    animTex:Hide()
    macroIcon.animTex = animTex
    macroIcon.animFrame = 1
    macroIcon.animTime = 0

    local macroIconFill = macroIcon:CreateTexture(nil, "BACKGROUND")
    macroIconFill:SetPoint("CENTER", macroIcon, "CENTER")
    macroIconFill:SetSize(76, 76)
    macroIconFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    macroIconFill:SetVertexColor(0.02, 0.02, 0.02, 0.7)

    local macroIconFillMask = macroIcon:CreateMaskTexture(nil, "BACKGROUND")
    macroIconFillMask:SetAllPoints(macroIconFill)
    macroIconFillMask:SetTexture(MIXER_PREVIEW_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    macroIconFill:AddMaskTexture(macroIconFillMask)

    local macroIconRing = macroIcon:CreateTexture(nil, "BORDER")
    macroIconRing:SetPoint("CENTER", macroIcon, "CENTER")
    macroIconRing:SetSize(80, 80)
    macroIconRing:SetTexture(MIXER_PREVIEW_RING_TEXTURE)
    macroIconRing:Hide()

    local macroIconSize = 83
    local macroHalfWidth = (macroIconSize / 2) + 2
    local macroIconLeft = macroIcon:CreateTexture(nil, "ARTWORK")
    macroIconLeft:SetPoint("LEFT", macroIcon, "LEFT", 1, 0)
    macroIconLeft:SetSize(macroHalfWidth, macroIconSize)
    macroIconLeft:SetTexCoord(0, 0.5, 0, 1)
    macroIconLeft:Hide()

    local macroIconRight = macroIcon:CreateTexture(nil, "ARTWORK")
    macroIconRight:SetPoint("RIGHT", macroIcon, "RIGHT", -1, 0)
    macroIconRight:SetSize(macroHalfWidth, macroIconSize)
    macroIconRight:SetTexCoord(0.5, 1, 0, 1)
    macroIconRight:Hide()

    local macroMaskLeft = macroIcon:CreateMaskTexture(nil, "ARTWORK")
    macroMaskLeft:SetPoint("CENTER", macroIcon, "CENTER")
    macroMaskLeft:SetSize(76, 76)
    macroMaskLeft:SetTexture(MIXER_PREVIEW_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    macroIconLeft:AddMaskTexture(macroMaskLeft)

    local macroMaskRight = macroIcon:CreateMaskTexture(nil, "ARTWORK")
    macroMaskRight:SetPoint("CENTER", macroIcon, "CENTER")
    macroMaskRight:SetSize(76, 76)
    macroMaskRight:SetTexture(MIXER_PREVIEW_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    macroIconRight:AddMaskTexture(macroMaskRight)

    macroIcon.iconLeft = macroIconLeft
    macroIcon.iconRight = macroIconRight

    local macroQuestionText = macroIcon:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    macroQuestionText:SetPoint("CENTER", macroIcon, "CENTER", 0, -1)
    macroQuestionText:SetText("?")
    macroQuestionText:SetTextColor(1, 0.12, 0.08, 1)
    macroQuestionText:SetFont(OxedHub:GetFont("Fonts\\FRIZQT__.ttf"), 52, "OUTLINE")
    macroIcon.questionText = macroQuestionText

    macroIcon:SetScript("OnMouseDown", function()
        Toys:CreateInternalMixMacro()
    end)
    macroIcon:SetScript("OnDragStart", function()
        local macroName = Toys:CreateInternalMixMacro(true)
        if macroName then
            local index = GetMacroIndexByName(macroName)
            if index > 0 then
                PickupMacro(index)
            end
        end
    end)
    macroIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOY_MIX_MACRO"] or "Mix Macro")
        GameTooltip:AddLine(L["MIXER_MACRO_HELP1"] or "Drag this icon to your action bar to use this mix.", 1, 1, 1, true)
        GameTooltip:AddLine(L["MIXER_MACRO_HELP2"] or "Click refreshes or creates the character macro.", 0, 1, 0, true)
        GameTooltip:AddLine(L["MIXER_MACRO_HELP3"] or "This will use 1 character macro slot.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    macroIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Animation OnUpdate script
    macroIcon:SetScript("OnUpdate", function(self, elapsed)
        -- Only animate if both slots are filled
        if selectedSlots[1] and selectedSlots[2] and self.animTex then
            if not self.animStarted then
                print("OxedHub: Ring animation started!")
                self.animStarted = true
            end
            self.animTex:Show()
            
            self.animTime = (self.animTime or 0) + elapsed
            local fps = 30  -- SPEED: Change this number to adjust animation speed (frames per second)
            local frameDuration = 1 / fps
            
            if self.animTime >= frameDuration then
                self.animTime = self.animTime - frameDuration
                self.animFrame = (self.animFrame or 1) + 1
                if self.animFrame > 18 then  -- 18 frames total
                    self.animFrame = 1  -- Loop back to first frame
                end
                
                -- Update texture to current frame
                self.animTex:SetTexture(string.format(
                    "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_%05d.png", self.animFrame))
            end
        else
            -- Hide animation if slots not filled
            if self.animTex then
                self.animTex:Hide()
            end
            self.animFrame = 1
            self.animTime = 0
            self.animStarted = false
        end
    end)

    local macroReqs = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroReqs:SetPoint("BOTTOM", macroIcon, "TOP", 0, 45)
    macroReqs:SetWidth(280)
    macroReqs:SetJustifyH("CENTER")
    macroReqs:Hide()
    self.mixerReqs = macroReqs

    local macroHint = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    macroHint:SetPoint("BOTTOM", macroFrame, "BOTTOM", 0, 20)
    macroHint:SetText("Click Run to execute")

    -- Run Mix button - HIDDEN (functionality removed per user request)
    local runBtn = CreateFrame("Button", "OxedHubRunMixButton", macroFrame, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    runBtn:SetSize(86, 24)
    runBtn:SetPoint("CENTER", frame, "CENTER", -5, -87 + MIXER_CONTENT_Y_OFFSET)
    runBtn:SetText("Run Mix")
    runBtn:Hide()  -- Hidden per user request
    
    macroHint:ClearAllPoints()
    macroHint:SetPoint("TOP", runBtn, "BOTTOM", 0, -3)
    macroHint:Hide()  -- Hide the hint text too

    local saveBtn = CreateFrame("Button", nil, macroFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(110, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", macroFrame, "BOTTOMRIGHT", -39, 48)
    saveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix")
    saveBtn:SetScript("OnClick", function()
        if not selectedSlots[1] and not selectedSlots[2] then
            print("|cffff0000OxedHub:|r Select a toy or spell first!")
            return
        end
        self:SaveMix()
        print("|cff00ff00OxedHub:|r Mix saved successfully!")
    end)
    self.mixerSaveBtn = saveBtn

    -- Subtle flavor text above "Save Mix" using Ronthel Brush DEMO font
    local goWrongText = macroFrame:CreateFontString(nil, "OVERLAY")
    goWrongText:SetPoint("BOTTOMRIGHT", saveBtn, "TOPRIGHT", 10, 8)
    goWrongText:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 20)
    goWrongText:SetText(L["TOY_GO_WRONG"] or "What could possibly go wrong?")
    goWrongText:SetTextColor(0.22, 0.18, 0.17, 1.0)
    goWrongText:SetJustifyH("RIGHT")

    -- New Mix / Cancel Edit button: shown only when editing an existing mix
    local newMixBtn = CreateFrame("Button", nil, macroFrame, "UIPanelButtonTemplate")
    newMixBtn:SetSize(70, 26)
    newMixBtn:SetPoint("LEFT", runBtn, "RIGHT", 6, 0)
    newMixBtn:SetText("New Mix")
    newMixBtn:Hide()
    newMixBtn:SetScript("OnClick", function()
        selectedSlots[1] = nil
        selectedSlots[2] = nil
        for k in pairs(mixerActions) do mixerActions[k] = nil end
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        self.editingMixName = nil
        self.currentMixName = nil
        if self.mixerSaveBtn then self.mixerSaveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix") end
        if self.mixerNewMixBtn then self.mixerNewMixBtn:Hide() end
        if self.mixerSoundBtn then self.mixerSoundBtn:SetText(L["TOYS_ACT_ADD_SOUND"] or "Add Sound") end
        if self.mixerEmoteBtn then self.mixerEmoteBtn:SetText(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote") end
        if self.mixerAnimBtn then self.mixerAnimBtn:SetText(L["TOYS_ACT_ADD_ANIM"] or "Add Animation") end
        if self.mixerChatBtn then self.mixerChatBtn:SetText(L["TOYS_ACT_ADD_TEXT"] or "Add Text") end
        print("|cff00ff00[OxedHub]|r Mixer cleared. Select items to create a new mix.")
    end)
    self.mixerNewMixBtn = newMixBtn
    
    -- Helper to update icons
    self.UpdateMixerIcons = function()
        local firstIcon = nil
        local secondIcon = nil

        if selectedSlots[1] then
            if selectedSlots[1].type == "toy" then
                local _, _, icon = C_ToyBox.GetToyInfo(selectedSlots[1].id)
                icon1:SetTexture(icon)
                firstIcon = icon or firstIcon
            else
                local spellInfo = C_Spell.GetSpellInfo(selectedSlots[1].id)
                firstIcon = spellInfo and spellInfo.iconID or nil
                icon1:SetTexture(firstIcon or MIXER_PREVIEW_QUESTION_ICON)
            end
            icon1:Show()
        else
            icon1:Hide()
        end

        if selectedSlots[2] then
            if selectedSlots[2].type == "toy" then
                local _, _, icon = C_ToyBox.GetToyInfo(selectedSlots[2].id)
                icon2:SetTexture(icon)
                secondIcon = icon or secondIcon
                if not selectedSlots[1] then firstIcon = icon or firstIcon end
            else
                local spellInfo = C_Spell.GetSpellInfo(selectedSlots[2].id)
                secondIcon = spellInfo and spellInfo.iconID or nil
                icon2:SetTexture(secondIcon or MIXER_PREVIEW_QUESTION_ICON)
                if not selectedSlots[1] then firstIcon = secondIcon or firstIcon end
            end
            icon2:Show()
            spellSlotHint:Hide()
        else
            icon2:Hide()
            spellSlotHint:Hide()
        end

        if macroIcon.iconLeft then
            if firstIcon then
                macroIcon.iconLeft:SetTexture(firstIcon)
                macroIcon.iconLeft:Show()
            else
                macroIcon.iconLeft:Hide()
            end
        end
        if macroIcon.iconRight then
            if secondIcon then
                macroIcon.iconRight:SetTexture(secondIcon)
                macroIcon.iconRight:Show()
            else
                macroIcon.iconRight:Hide()
            end
        end
        if macroIcon.questionText then
            if firstIcon or secondIcon then
                macroIcon.questionText:Hide()
            else
                macroIcon.questionText:Show()
            end
        end

        -- Update requirement text in Internal Mix panel
        local reqLines = {}
        for i = 1, 2 do
            local slot = selectedSlots[i]
            if slot and slot.type == "toy" then
                local reqs = self:GetItemRequirements(slot.id)
                for _, req in ipairs(reqs) do
                    local color = string.format("|cff%02x%02x%02x", req.r * 255, req.g * 255, req.b * 255)
                    table.insert(reqLines, color .. req.text .. "|r")
                end
            end
        end
        if #reqLines > 0 then
            macroReqs:SetText(table.concat(reqLines, "\n"))
            macroReqs:Show()
        else
            macroReqs:SetText("")
            macroReqs:Hide()
        end
        
        -- Update the Run Mix button's macro text whenever slots change
        if self.UpdateRunButtonMacro then
            self.UpdateRunButtonMacro()
        end
    end
    
    -- Interaction for slots (Tooltips and click to clear)
    slot1:SetScript("OnEnter", function(self)
        local slot = selectedSlots[1]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_PRIMARY_SLOT"] or "Primary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
            GameTooltip:Show()
            return
        end
        if slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
            GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
        end
        GameTooltip:Show()
    end)
    slot1:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot1:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 1)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 1)
            end
            ClearCursor()
        end
    end)

    slot2:SetScript("OnEnter", function(self)
        local slot = selectedSlots[2]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_SECONDARY_SLOT"] or "Secondary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
            GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
        end
        GameTooltip:Show()
    end)
    slot2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot2:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        end
    end)

    -- macroIcon is now a texture, no button scripts needed
    
    -- Store button refs
    self.mixerSoundBtn = soundBtn
    self.mixerEmoteBtn = emotionBtn
    self.mixerAnimBtn = animBtn
    self.mixerChatBtn = textBtn
end

--- Macro Naming Logic
local function GetSlotInitials(slot)
    if not slot then return "" end
    local name
    if slot.type == "toy" then
        _, name = C_ToyBox.GetToyInfo(slot.id)
    elseif slot.type == "spell" then
        local spellInfo = C_Spell.GetSpellInfo(slot.id)
        name = spellInfo and spellInfo.name
    end
    if not name then return "?" end

    -- Extract initials (first letter of each word, max 4)
    local initials = ""
    for word in name:gmatch("%S+") do
        initials = initials .. word:sub(1, 1):upper()
        if #initials >= 4 then break end
    end
    return initials
end

-- Save Mix to Internal Registry
function Toys:SaveMix()
    if not selectedSlots[1] and not selectedSlots[2] then return end

    local mixName
    if self.editingMixName then
        -- Updating an existing mix being edited
        mixName = self.editingMixName
    else
        -- Creating a new mix: auto-generate name from slot initials
        local name1 = selectedSlots[1] and GetSlotInitials(selectedSlots[1]) or ""
        local name2 = selectedSlots[2] and GetSlotInitials(selectedSlots[2]) or ""
        mixName = name1
        if name1 ~= "" and name2 ~= "" then
            mixName = name1 .. " + " .. name2
        elseif name2 ~= "" then
            mixName = name2
        end
        if not mixName or mixName == "" then
            mixName = "Mix " .. date("%H:%M:%S")
        end
    end

    -- Save via MacroRegistry
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:SaveMacro(mixName, {
            slots = { selectedSlots[1], selectedSlots[2] },
            actions = {
                sound = mixerActions.sound,
                emote = mixerActions.emote,
                animation = mixerActions.animation,
                chat = mixerActions.chat
            }
        })
    end

    -- Also keep toyMixes for backward compat with EmotionRing/ToyRing
    OxedHub.db.profile.toyMixes[mixName] = {
        slots = { selectedSlots[1], selectedSlots[2] },
        actions = {
            sound = mixerActions.sound,
            emote = mixerActions.emote,
            animation = mixerActions.animation,
            chat = mixerActions.chat
        }
    }
    if self:HasGeneratedMixMacro(mixName) then
        self:CreateMacroForMix(mixName, true)
    end

    self.currentMixName = mixName
    local wasEditing = self.editingMixName ~= nil
    self.editingMixName = nil
    if self.mixerSaveBtn then
        self.mixerSaveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix")
    end
    if self.mixerNewMixBtn then
        self.mixerNewMixBtn:Hide()
    end

    -- Auto-clear mixer after editing so user can create a new mix fresh
    if wasEditing then
        selectedSlots[1] = nil
        selectedSlots[2] = nil
        for k in pairs(mixerActions) do mixerActions[k] = nil end
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if self.mixerSoundBtn then self.mixerSoundBtn:SetText(L["TOYS_ACT_ADD_SOUND"] or "Add Sound") end
        if self.mixerEmoteBtn then self.mixerEmoteBtn:SetText(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote") end
        if self.mixerAnimBtn then self.mixerAnimBtn:SetText(L["TOYS_ACT_ADD_ANIM"] or "Add Animation") end
        if self.mixerChatBtn then self.mixerChatBtn:SetText(L["TOYS_ACT_ADD_TEXT"] or "Add Text") end
        print("|cff00ff00[OxedHub]|r Mix updated. Mixer cleared for new creation.")
    end

    if self.savedMixesScrollChild then
        self:RefreshSavedMixesList()
    end
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

-- Picker for Mixer
function Toys:ShowPickerForMixer(type, btn)
    if not OxedHub.Triggers then return end
    
    local function OnSelect(value, label)
        mixerActions[type] = value
        btn:SetText(label or mixerActionButtonText[type])
    end
    
    if type == "sound" then
        OxedHub.Triggers.currentTriggerForPicker = { actions = mixerActions }
        OxedHub.Triggers:ShowSoundPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local disp = mixerActions.sound and Toys:GetSoundDisplayName(mixerActions.sound)
            btn:SetText(disp or mixerActionButtonText.sound)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif type == "emote" then
        OxedHub.Triggers:ShowEmotePicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local disp = mixerActions.emote and TruncateText(mixerActions.emote, 15)
            btn:SetText(disp or mixerActionButtonText.emote)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif type == "chat" then
        -- Pre-populate chatMessage so picker can read existing value
        if mixerActions.chat and not mixerActions.chatMessage then
            mixerActions.chatMessage = mixerActions.chat
        end
        OxedHub.Triggers:ShowChatPicker({ actions = mixerActions })
        OxedHub.Triggers.RefreshTriggersList = function(self)
            mixerActions.chat = mixerActions.chatMessage
            local chat = OxedHub.db.profile.chatTemplates[mixerActions.chat]
            local disp = chat and chat.name and TruncateText(chat.name, 15)
            btn:SetText(disp or mixerActionButtonText.chat)
            OxedHub.Triggers.RefreshTriggersList = orig
            if orig then orig(self) end
        end
    elseif type == "animation" then
        OxedHub.Triggers:ShowAnimationPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local anim = OxedHub.db.profile.animations[mixerActions.animation]
            local disp = anim and anim.name and TruncateText(anim.name, 15)
            btn:SetText(disp or mixerActionButtonText.animation)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    end
end

-- Spell Picker for Mixer
function Toys:ShowSpellPickerForMixer()
    if self.spellPicker then
        self.spellPicker:Show()
        self:RefreshSpellPickerList("")
        return
    end

    local picker = CreateFrame("Frame", "OxedHubSpellPicker", UIParent, "BackdropTemplate")
    picker:SetSize(360, 400)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    picker:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    picker:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", picker, "TOP", 0, -16)
    title:SetText(L["MIXER_PICK_SPELL"] or "Pick Spell")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    searchInput:SetSize(260, 22)
    searchInput:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -55)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function() self:RefreshSpellPickerList(searchInput:GetText()) end)

    local clearBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(300)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local closeBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -18, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() picker:Hide() end)

    picker.searchInput = searchInput
    picker.scrollFrame = scrollFrame
    picker.scrollChild = scrollChild
    picker.rows = {}
    self.spellPicker = picker

    self:RefreshSpellPickerList("")
    picker:Show()
end

function Toys:RefreshSpellPickerList(query)
    local picker = self.spellPicker
    if not picker then return end
    query = query or ""
    query = query:lower():gsub("^%s*", ""):gsub("%s*$", "")

    local results = {}
    local added = {}

    -- Search spellbook
    local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
    for skillLineIndex = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if skillLineInfo then
            local numSpells = skillLineInfo.numSpellBookItems or 0
            for spellIndex = skillLineInfo.itemIndexOffset, skillLineInfo.itemIndexOffset + numSpells - 1 do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(spellIndex, Enum.SpellBookSpellBank.Player)
                if spellInfo and spellInfo.spellID and not added[spellInfo.spellID] then
                    local spellName = C_SpellBook.GetSpellBookItemName(spellIndex, Enum.SpellBookSpellBank.Player)
                    local icon = C_SpellBook.GetSpellBookItemTexture(spellIndex, Enum.SpellBookSpellBank.Player)
                    if spellName and (query == "" or spellName:lower():find(query, 1, true)) then
                        added[spellInfo.spellID] = true
                        table.insert(results, { name = spellName, id = spellInfo.spellID, icon = icon })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.name < b.name end)

    for index, result in ipairs(results) do
        local row = picker.rows[index]
        if not row then
            row = CreateFrame("Button", nil, picker.scrollChild, "UIPanelButtonTemplate")
            row:SetSize(280, 24)
            row:SetNormalFontObject("GameFontNormalSmall")
            picker.rows[index] = row
        end
        row:Show()
        row:SetPoint("TOPLEFT", picker.scrollChild, "TOPLEFT", 5, -((index - 1) * 28))
        row:SetText(result.name .. "  |cffaaaaaaID: " .. result.id .. "|r")
        row:SetScript("OnClick", function()
            self:SelectSlotForMixer("spell", result.id, 2)
            picker:Hide()
        end)
    end

    for index = #results + 1, #picker.rows do
        picker.rows[index]:Hide()
    end

    picker.scrollChild:SetHeight(math.max(#results * 28, 1))
end

-- Create Saved Mixes UI
function Toys:CreateSavedMixesUI(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -18)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -50, 24)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.savedMixesScrollChild = scrollChild
    self:RefreshSavedMixesList()
end

-- Refresh Saved Mixes List (Table-style with editable components)
function Toys:RefreshSavedMixesList()
    local parent = self.savedMixesScrollChild
    if not parent then return end

    if parent.rows then
        for _, row in ipairs(parent.rows) do row:Hide() end
    end
    parent.rows = parent.rows or {}

    local mixes = OxedHub.db.profile.toyMixes or {}
    local filter = OxedHub.db.profile.settings.filterByClass
    local sortedMixes = {}
    for name, data in pairs(mixes) do 
        local show = true
        if filter and data.slots then
            for _, slot in ipairs(data.slots) do
                if slot and slot.type == "spell" then
                    if not OxedHub:IsSpellRelevant(slot.id) then
                        show = false
                        break
                    end
                end
            end
        end
        if show then
            table.insert(sortedMixes, name)
        end
    end
    table.sort(sortedMixes)

    local yOffset = -5
    local rowHeight = 80

    for i, name in ipairs(sortedMixes) do
        local row = parent.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetSize(parent:GetWidth() - 10, rowHeight)

            local separator = row:CreateTexture(nil, "BACKGROUND")
            separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            separator:SetHeight(1)
            separator:SetTexture("Interface\\Buttons\\WHITE8X8")
            separator:SetVertexColor(0.55, 0.55, 0.55, 0.28)
            row.separator = separator

            -- LEFT SECTION: Mix Name
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
            nameLabel:SetWidth(200)
            nameLabel:SetJustifyH("LEFT")
            nameLabel:SetTextColor(1, 1, 1)
            row.nameLabel = nameLabel

            -- Status label (moved to center)
            local statusLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusLabel:SetPoint("TOP", row, "TOP", 0, -14)
            statusLabel:SetJustifyH("CENTER")
            row.statusLabel = statusLabel

            -- Slot icons (moved to right of big icon)
            local slotIconSize = 30
            local slot1Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot1Btn:SetSize(slotIconSize, slotIconSize)
            slot1Btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 74, 20)
            slot1Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot1Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot1Tex = slot1Btn:CreateTexture(nil, "ARTWORK")
            slot1Tex:SetPoint("TOPLEFT", slot1Btn, "TOPLEFT", 2, -2)
            slot1Tex:SetPoint("BOTTOMRIGHT", slot1Btn, "BOTTOMRIGHT", -2, 2)
            slot1Tex:SetTexture(134400)
            slot1Btn.tex = slot1Tex
            slot1Btn:SetScript("OnClick", function(self) Toys:EditMixComponent(self.mixName, "slot1") end)
            slot1Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine(L["MIXER_SLOT1_ASSIGN"] or "Slot 1 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot1Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot1Btn = slot1Btn

            local slot2Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot2Btn:SetSize(slotIconSize, slotIconSize)
            slot2Btn:SetPoint("LEFT", slot1Btn, "RIGHT", 4, 0)
            slot2Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot2Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot2Tex = slot2Btn:CreateTexture(nil, "ARTWORK")
            slot2Tex:SetPoint("TOPLEFT", slot2Btn, "TOPLEFT", 2, -2)
            slot2Tex:SetPoint("BOTTOMRIGHT", slot2Btn, "BOTTOMRIGHT", -2, 2)
            slot2Tex:SetTexture(134400)
            slot2Btn.tex = slot2Tex
            slot2Btn:SetScript("OnClick", function(self) Toys:EditMixComponent(self.mixName, "slot2") end)
            slot2Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine(L["MIXER_SLOT2_ASSIGN"] or "Slot 2 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot2Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot2Btn = slot2Btn

            -- LEFT SECTION: Draggable Split Mix Icon (Moved left under mix name)
            local mixIconFrame = CreateFrame("Button", nil, row, "BackdropTemplate")
            mixIconFrame:SetSize(50, 50)
            mixIconFrame:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 10)
            mixIconFrame:SetBackdrop(nil)
            mixIconFrame:EnableMouse(true)
            mixIconFrame:RegisterForDrag("LeftButton")
            mixIconFrame:SetScript("OnDragStart", function(self)
                local macroName = Toys:CreateMacroForMix(self.mixName)
                if macroName then
                    local index = GetMacroIndexByName(macroName)
                    if index and index > 0 then
                        PickupMacro(index)
                    end
                end
            end)
            mixIconFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.mixName or "Mix", 1, 1, 1)
                if self.missingToyCount and self.missingToyCount > 0 then
                    GameTooltip:AddLine("|cffff6666" .. (L["MIXER_MISSING_TOYS"] or "Missing toys: ") .. self.missingToyCount .. "|r")
                else
                    GameTooltip:AddLine("|cff88ff88" .. (L["MIXER_ALL_TOYS_AVAILABLE"] or "All toys available") .. "|r")
                end
                GameTooltip:AddLine("|cffaaaaaa " .. (L["MIXER_DRAG_TO_ACTION_BAR"] or "Drag to action bar") .. "|r")
                GameTooltip:Show()
            end)
            mixIconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.mixIconFrame = mixIconFrame

            -- INFO TEXT: Centered in the row
            local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetJustifyH("CENTER")
            infoText:SetJustifyV("TOP")
            row.infoText = infoText

            -- RIGHT SECTION: 4 action buttons + Del
            local actionBtnSize = 26
            local actionDefs = {
                { key = "sound",     icon = "Interface\\Icons\\INV_Misc_Horn_01", label = L["MIXER_SOUND_LABEL"] or "Sound"     },
                { key = "emote",     icon = "Interface\\Icons\\UI_Chat",  label = L["MIXER_EMOTE_LABEL"] or "Emote"     },
                { key = "animation", icon = "Interface\\Icons\\Ability_Rogue_Sprint",  label = L["MIXER_ANIM_LABEL"] or "Animation" },
                { key = "chat",      icon = "Interface\\Icons\\INV_Misc_Note_01", label = L["MIXER_CHAT_LABEL"] or "Chat"      },
            }
            row.actionBtns = {}
            for ai, def in ipairs(actionDefs) do
                local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
                btn:SetSize(actionBtnSize, actionBtnSize)
                btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
                btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
                tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
                tex:SetTexture(def.icon)
                btn.tex = tex

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
                hl:SetBlendMode("ADD")

                -- anchor: right side, row of 4 before Del
                -- positions: -75 -105 -135 -165 from TOPRIGHT (each 26+4=30)
                btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -75 - (4 - ai) * 30, -10)

                local capturedDef = def
                btn:SetScript("OnClick", function(self)
                    Toys:EditMixComponent(self.mixName, capturedDef.key)
                end)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(capturedDef.label, 1, 1, 1)
                    local acts = self.mixData and self.mixData.actions or {}
                    local val = acts[capturedDef.key]
                    if val then
                        GameTooltip:AddLine("|cff88ff88" .. tostring(val) .. "|r")
                    else
                        GameTooltip:AddLine("|cffaaaaaa " .. (L["MIXER_NOT_SET"] or "Not set") .. "|r")
                    end
                    GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_EDIT"] or "Click to edit") .. "|r")
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.actionBtns[ai] = btn
                row.actionBtns[def.key] = btn
            end

            local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            delBtn:SetSize(60, 22)
            delBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -10)
            delBtn:SetText(L["MIXER_DEL"] or "Del")
            delBtn:SetNormalFontObject("GameFontNormalSmall")
            delBtn:SetScript("OnClick", function(self)
                Toys:DeleteMix(self.macroName)
            end)
            row.delBtn = delBtn

            parent.rows[i] = row
        end

        row:Show()
        row:SetSize(parent:GetWidth() - 10, rowHeight)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
        row.mixName = name

        local data = mixes[name]
        local totalToys, missingToys = self:GetMixToyAvailability(data)
        local isMissing = missingToys > 0

        -- Update name label
        row.nameLabel:SetText(name)

        -- Status
        if isMissing then
            local suffix = missingToys == 1 and "" or "s"
            row.statusLabel:SetText("|cffff6666" .. string.format(L["TOY_MISSING_COUNT"] or "%d missing toy%s%s", missingToys, suffix, suffix) .. "|r")
        else
            row.statusLabel:SetText("|cff88ff88" .. (L["TOY_STATUS_READY"] or "Ready") .. "|r")
        end

        -- Update split icon
        row.mixIconFrame.mixName = name
        row.mixIconFrame.missingToyCount = missingToys

        -- Gray out split icon border when toys missing (Removed as the border was removed)
        if isMissing then
            -- intentionally left blank
        else
            -- intentionally left blank
        end

        -- Info text
        -- parchment color matching OxedRing editor description text: 0.90, 0.85, 0.80 = #e6d9cc
        local parchment = "|cffe6d9cc"
        if isMissing then
            local suffix = missingToys == 1 and "" or "s"
            row.infoText:SetText(
                "|cffff6666" .. string.format(L["TOY_MISSING_INFO"] or "%d toy%s missing — partially usable. Missing toy effects will be skipped; sounds, animations, emotes and chat will still fire normally.", missingToys, suffix, suffix) .. "|r"
            )
        else
            row.infoText:SetText(
                "|cffffff00ActionHub|r" .. parchment .. ": " .. (L["TOY_INFO_READY"] or "assign to a button — no macro slot used (OxedEngine internal). Or drag the icon to your action bar — uses 1 slot in your general or class macros.") .. "|r"
            )
        end

        -- Clear old split icon if it exists
        if row.splitIcon then
            row.splitIcon:Hide()
            row.splitIcon = nil
        end

        -- Create new split icon, grayed if missing
        local icon1, icon2 = self:GetMixSlotIcons(name)
        local splitIcon = CreateSplitIcon(row.mixIconFrame, 46, icon1, icon2)
        splitIcon:SetPoint("CENTER", row.mixIconFrame, "CENTER", 0, 0)
        if isMissing then
            splitIcon.leftTexture:SetDesaturated(true)
            splitIcon.leftTexture:SetVertexColor(0.45, 0.45, 0.45, 1)
            splitIcon.rightTexture:SetDesaturated(true)
            splitIcon.rightTexture:SetVertexColor(0.45, 0.45, 0.45, 1)
        else
            splitIcon.leftTexture:SetDesaturated(false)
            splitIcon.leftTexture:SetVertexColor(1, 1, 1, 1)
            splitIcon.rightTexture:SetDesaturated(false)
            splitIcon.rightTexture:SetVertexColor(1, 1, 1, 1)
        end
        row.splitIcon = splitIcon

        -- Update action buttons
        local acts = (type(data) == "table" and data.actions) or {}
        for _, btn in ipairs(row.actionBtns) do
            btn.mixName = name
            btn.mixData = data
        end
        local actionKeys = { "sound", "emote", "animation", "chat" }
        for _, key in ipairs(actionKeys) do
            local btn = row.actionBtns[key]
            if btn then
                if acts[key] then
                    btn.tex:SetDesaturated(false)
                    btn.tex:SetVertexColor(1, 1, 1, 1)
                    btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.9)
                else
                    btn.tex:SetDesaturated(true)
                    btn.tex:SetVertexColor(0.4, 0.4, 0.4, 0.8)
                    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                end
            end
        end

        -- Anchor info text to the center (only on first build)
        if not row.infoTextAnchored then
            row.infoText:SetPoint("TOP", row.statusLabel, "BOTTOM", 0, -4)
            row.infoText:SetWidth(380)
            row.infoTextAnchored = true
        end

        -- Update slot icons
        row.slot1Btn.mixName = name
        row.slot2Btn.mixName = name
        row.slot1Btn.itemID = nil
        row.slot1Btn.spellID = nil
        row.slot2Btn.itemID = nil
        row.slot2Btn.spellID = nil

        local slots = type(data) == "table" and data.slots or {}
        for si, slotBtn in ipairs({ row.slot1Btn, row.slot2Btn }) do
            local slot = slots[si]
            if slot then
                if slot.type == "toy" then
                    local _, _, tIcon = C_ToyBox.GetToyInfo(slot.id)
                    slotBtn.tex:SetTexture(tIcon or 134400)
                    slotBtn.itemID = slot.id
                    local owns = self:DoesPlayerOwnToy(slot.id)
                    if owns then
                        slotBtn.tex:SetDesaturated(false)
                        slotBtn.tex:SetVertexColor(1, 1, 1, 1)
                        slotBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    else
                        slotBtn.tex:SetDesaturated(true)
                        slotBtn.tex:SetVertexColor(0.45, 0.45, 0.45, 1)
                        slotBtn:SetBackdropBorderColor(0.7, 0.15, 0.15, 1)
                    end
                elseif slot.type == "spell" then
                    local spellInfo = C_Spell.GetSpellInfo(slot.id)
                    slotBtn.tex:SetTexture(spellInfo and spellInfo.iconID or 134400)
                    slotBtn.spellID = slot.id
                    slotBtn.tex:SetDesaturated(false)
                    slotBtn.tex:SetVertexColor(1, 1, 1, 1)
                    slotBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                end
            else
                slotBtn.tex:SetTexture(134400)
                slotBtn.tex:SetDesaturated(false)
                slotBtn.tex:SetVertexColor(0.5, 0.5, 0.5, 0.5)
                slotBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
            end
        end

        -- Update delete button
        row.delBtn.macroName = name

        yOffset = yOffset - (rowHeight + 2)
    end

    parent:SetHeight(math.abs(yOffset))
end

-- Delete Mix
function Toys:_PerformDeleteMix(name)
    -- Delete from internal registry
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:DeleteMacro(name)
    end

    -- Delete generated and legacy WoW macros if they exist.
    local generatedIndex = GetMacroIndexByName(GetSafeMixMacroName(name))
    if generatedIndex > 0 then
        DeleteMacro(generatedIndex)
    end
    local index = GetMacroIndexByName(name)
    if index > 0 then
        DeleteMacro(index)
    end

    if OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes[name] = nil
    end

    -- Also remove from assignments
    local mappings = OxedHub.db.profile.emotionMappings or {}
    for emotion, data in pairs(mappings) do
        if data.toyMacro == name then
            data.toyMacro = nil
        end
    end

    self:RefreshSavedMixesList()
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

function Toys:DeleteMix(name)
    if InCombatLockdown() then
        print("|cffff0000OxedHub:|r Cannot delete mixes in combat.")
        return
    end

    -- Check if skip confirmation is enabled
    if OxedHub.db.profile.settings and OxedHub.db.profile.settings.skipDeleteConfirmation then
        self:_PerformDeleteMix(name)
        return
    end

    -- Show confirmation dialog
    StaticPopupDialogs["OXEDHUB_CONFIRM_DELETE_MIX"] = {
        text = "Are you sure you wish to delete the mix '%s'?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(self, data)
            Toys:_PerformDeleteMix(data)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_CONFIRM_DELETE_MIX", name, nil, name)
end

-- Rename Mix
function Toys:RenameMix(oldName, newName)
    if InCombatLockdown() then
        print("|cffff0000OxedHub:|r Cannot rename mixes in combat.")
        return
    end

    -- Rename via internal registry
    if OxedHub.MacroRegistry then
        if not OxedHub.MacroRegistry:RenameMacro(oldName, newName) then
            print("|cffff0000OxedHub:|r Mix name '" .. newName .. "' already exists.")
            return
        end
    end

    -- Remove generated macro for the old name; the drag icon will create a fresh one.
    local generatedIndex = GetMacroIndexByName(GetSafeMixMacroName(oldName))
    if generatedIndex > 0 then
        DeleteMacro(generatedIndex)
    end

    -- Rename legacy WoW macro if it exists.
    local legacyIndex = GetMacroIndexByName(oldName)
    if legacyIndex > 0 and GetMacroIndexByName(newName) == 0 then
        local _, icon, body = GetMacroInfo(legacyIndex)
        EditMacro(legacyIndex, newName, icon, body)
    end

    -- Update DB
    if OxedHub.db.profile.toyMixes then
        local data = OxedHub.db.profile.toyMixes[oldName]
        OxedHub.db.profile.toyMixes[oldName] = nil
        OxedHub.db.profile.toyMixes[newName] = data or true
    end

    -- Update assignments
    local mappings = OxedHub.db.profile.emotionMappings or {}
    for emotion, data in pairs(mappings) do
        if data.toyMacro == oldName then
            data.toyMacro = newName
        end
    end

    self:RefreshSavedMixesList()
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

-- Load a saved mix into the mixer state for editing
function Toys:LoadMixIntoMixer(name)
    local data = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name]
    if type(data) ~= "table" then return end

    selectedSlots[1] = nil
    selectedSlots[2] = nil
    for k in pairs(mixerActions) do mixerActions[k] = nil end

    if data.slots then
        if data.slots[1] then selectedSlots[1] = { type = data.slots[1].type, id = data.slots[1].id } end
        if data.slots[2] then selectedSlots[2] = { type = data.slots[2].type, id = data.slots[2].id } end
    end

    if data.actions then
        mixerActions.sound = data.actions.sound
        mixerActions.animation = data.actions.animation
        mixerActions.emote = data.actions.emote
        mixerActions.chat = data.actions.chat
    end

    if self.UpdateMixerIcons then self:UpdateMixerIcons() end
    if self.mixerSoundBtn then
        local disp = mixerActions.sound and Toys:GetSoundDisplayName(mixerActions.sound)
        self.mixerSoundBtn:SetText(disp or mixerActionButtonText.sound)
    end
    if self.mixerEmoteBtn then
        local disp = mixerActions.emote and TruncateText(mixerActions.emote, 15)
        self.mixerEmoteBtn:SetText(disp or mixerActionButtonText.emote)
    end
    if self.mixerAnimBtn then
        local anim = mixerActions.animation and OxedHub.db.profile.animations[mixerActions.animation]
        local disp = anim and anim.name and TruncateText(anim.name, 15)
        self.mixerAnimBtn:SetText(disp or mixerActionButtonText.animation)
    end
    if self.mixerChatBtn then
        local chat = mixerActions.chat and OxedHub.db.profile.chatTemplates[mixerActions.chat]
        local disp = chat and chat.name and TruncateText(chat.name, 15)
        self.mixerChatBtn:SetText(disp or mixerActionButtonText.chat)
    end
end

-- Save current mixer state back to a mix name
function Toys:SaveMixerStateToMix(name)
    if not name or name == "" then return end
    local mixData = {
        slots = {},
        actions = {
            sound = mixerActions.sound,
            emote = mixerActions.emote,
            animation = mixerActions.animation,
            chat = mixerActions.chat
        }
    }
    if selectedSlots[1] then mixData.slots[1] = { type = selectedSlots[1].type, id = selectedSlots[1].id } end
    if selectedSlots[2] then mixData.slots[2] = { type = selectedSlots[2].type, id = selectedSlots[2].id } end

    if OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes[name] = mixData
    end
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:SaveMacro(name, mixData)
    end
    if self:HasGeneratedMixMacro(name) then
        self:CreateMacroForMix(name, true)
    end
    self:RefreshQuickMixesGrid()
end

-- Edit a specific component of a saved mix
function Toys:EditMixComponent(mixName, componentType)
    self:LoadMixIntoMixer(mixName)
    self.currentMixName = mixName
    self.editingMixName = mixName
    if self.mixerSaveBtn then
        self.mixerSaveBtn:SetText("Update Mix")
    end
    if self.mixerNewMixBtn then
        self.mixerNewMixBtn:Show()
    end

    local function SaveAndRefresh()
        self:SaveMixerStateToMix(mixName)
        self:RefreshSavedMixesList()
    end

    if componentType == "slot1" then
        selectedSlots[1] = nil
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if OxedHub.UI and OxedHub.UI.ShowToysSubTab then OxedHub.UI:ShowToysSubTab("Mixer") end
        print("|cff00ff00[OxedHub]|r " .. (L["MIXER_SLOT1_PRINT"] or "Click a toy or spell in the grid to set Slot 1, then Save Mix."))
    elseif componentType == "slot2" then
        selectedSlots[2] = nil
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if OxedHub.UI and OxedHub.UI.ShowToysSubTab then OxedHub.UI:ShowToysSubTab("Mixer") end
        print("|cff00ff00[OxedHub]|r " .. (L["MIXER_SLOT2_PRINT"] or "Click a toy or spell in the grid to set Slot 2, then Save Mix."))
    elseif componentType == "emote" then
        OxedHub.Triggers:ShowEmotePicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif componentType == "chat" then
        if mixerActions.chat and not mixerActions.chatMessage then
            mixerActions.chatMessage = mixerActions.chat
        end
        OxedHub.Triggers:ShowChatPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function(self)
            mixerActions.chat = mixerActions.chatMessage
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
            if orig then orig(self) end
        end
    elseif componentType == "animation" then
        OxedHub.Triggers:ShowAnimationPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif componentType == "sound" then
        OxedHub.Triggers:ShowSoundPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    end
end

-- Use a toy by itemID (called from triggers)
function Toys:UseToy(itemID, eventData)
    if not itemID then return end
    local id = tonumber(itemID)
    if not id then return end
    if PlayerHasToy(id) then
        C_ToyBox.UseToyByItemID(id)
    end
end

-- Compact helper: play sound + animation from a single /run line in macros
-- Called as: OxedHub.Toys:E("soundKey","animKey")
function Toys:E(soundKey, animKey)
    if soundKey and soundKey ~= "" and OxedHub.Sounds then
        OxedHub.Sounds:Play(soundKey)
    end
    if animKey and animKey ~= "" and OxedHub.Animations then
        OxedHub.Animations:Play(animKey)
    end
end

-- Build a single compact /run line for sound + animation
function Toys:BuildExtrasRunLine(soundKey, animKey)
    if not soundKey and not animKey then return nil end
    local s = soundKey and ('"' .. soundKey .. '"') or 'nil'
    local a = animKey and ('"' .. animKey .. '"') or 'nil'
    return '/run OxedHub.Toys:E(' .. s .. ',' .. a .. ')\n'
end

-- Generate a real WoW macro from mix data and execute it
-- This is the only reliable way to use toys and cast spells from a button click
-- Build macro text from saved mix data (for secure action buttons)
function Toys:GetMixMacroText(mixData)
    if type(mixData) ~= "table" then return nil end

    local body = "#showtooltip\n"
    for _, slot in ipairs(mixData.slots or {}) do
        if slot then
            if slot.type == "toy" then
                local _, name = C_ToyBox.GetToyInfo(slot.id)
                if name and self:DoesPlayerOwnToy(slot.id) then
                    body = body .. "/use " .. name .. "\n"
                end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.name then
                    body = body .. "/cast " .. spellInfo.name .. "\n"
                end
            end
        end
    end

    local actions = mixData.actions or {}
    if actions.emote then
        body = body .. "/" .. actions.emote:lower() .. "\n"
    end
    if actions.chat then
        local chat = OxedHub.db.profile.chatTemplates[actions.chat]
        if chat then
            body = body .. "/" .. chat.channel:lower() .. " " .. chat.text .. "\n"
        end
    end
    -- Combine sound + animation into one compact /run to save macro space
    local extras = self:BuildExtrasRunLine(actions.sound, actions.animation)
    if extras then
        body = body .. extras
    end

    if #body > 255 then
        body = body:sub(1, 255)
    end
    return body
end

function Toys:GetMixMacroName(mixName)
    return GetSafeMixMacroName(mixName)
end

function Toys:HasGeneratedMixMacro(mixName)
    return GetMacroIndexByName(self:GetMixMacroName(mixName)) > 0
end

function Toys:CreateMacroForMix(mixName, silent)
    if InCombatLockdown() then
        if not silent then
            print("|cffff0000[OxedHub]|r Cannot create mix macros in combat.")
        end
        return
    end

    local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[mixName]
    if type(mixData) ~= "table" and OxedHub.MacroRegistry then
        mixData = OxedHub.MacroRegistry:GetMacros()[mixName]
    end
    if type(mixData) ~= "table" then
        if not silent then
            print("|cffff0000[OxedHub]|r Mix not found: " .. tostring(mixName))
        end
        return
    end

    local body = self:GetMixMacroText(mixData)
    if not body or body == "#showtooltip\n" then
        if not silent then
            print("|cffff0000[OxedHub]|r This mix has no usable toy, spell, or action.")
        end
        return
    end

    local _, missingToys = self:GetMixToyAvailability(mixData)

    local macroName = self:GetMixMacroName(mixName)
    local icon = self:GetMixIcon(mixName) or "INV_MISC_QUESTIONMARK"
    local index = GetMacroIndexByName(macroName)
    if index > 0 then
        EditMacro(index, macroName, icon, body)
        if not silent then
            print("|cff00ff00[OxedHub]|r Mix macro updated. Drag the icon to your bar.")
        end
    else
        local _, numChar = GetNumMacros()
        if numChar >= 18 then
            if not silent then
                print("|cffff0000[OxedHub]|r Your Character Macro slots are full (18/18). Please delete one.")
            end
            return
        end
        CreateMacro(macroName, icon, body, 1)
        if not silent then
            print("|cff00ff00[OxedHub]|r Mix macro created. Drag the icon to your bar!")
        end
    end

    if missingToys > 0 and not silent then
        print("|cffffcc00[OxedHub]|r Mix |cffffff00" .. tostring(mixName) .. "|r has |cffffff00" .. missingToys .. "|r missing toy(s). Missing toys were skipped.")
    end

    return macroName
end

function Toys:CreateInternalMixMacro(silent)
    if InCombatLockdown() then
        if not silent then
            print("|cffff0000[OxedHub]|r Cannot create mix macros in combat.")
        end
        return
    end

    local mixData = {
        slots = { selectedSlots[1], selectedSlots[2] },
        actions = {
            emote = mixerActions.emote,
            chat = mixerActions.chat,
            sound = mixerActions.sound,
            animation = mixerActions.animation,
        }
    }

    local body = self:GetMixMacroText(mixData)
    if not body or body == "#showtooltip\n" then
        if not silent then
            print("|cffff0000[OxedHub]|r This mix has no usable toy, spell, or action.")
        end
        return
    end

    local macroName = "OH_InternalMix"
    local firstIcon = "INV_MISC_QUESTIONMARK"
    if selectedSlots[1] then
        if selectedSlots[1].type == "toy" then
            local _, _, icon = C_ToyBox.GetToyInfo(selectedSlots[1].id)
            firstIcon = icon or firstIcon
        else
            local spellInfo = C_Spell.GetSpellInfo(selectedSlots[1].id)
            firstIcon = spellInfo and spellInfo.iconID or firstIcon
        end
    elseif selectedSlots[2] then
        if selectedSlots[2].type == "toy" then
            local _, _, icon = C_ToyBox.GetToyInfo(selectedSlots[2].id)
            firstIcon = icon or firstIcon
        else
            local spellInfo = C_Spell.GetSpellInfo(selectedSlots[2].id)
            firstIcon = spellInfo and spellInfo.iconID or firstIcon
        end
    end

    local index = GetMacroIndexByName(macroName)
    if index > 0 then
        EditMacro(index, macroName, firstIcon, body)
        if not silent then
            print("|cff00ff00[OxedHub]|r Internal mix macro updated. Drag the icon to your bar.")
        end
    else
        local _, numChar = GetNumMacros()
        if numChar >= 18 then
            if not silent then
                print("|cffff0000[OxedHub]|r Your Character Macro slots are full (18/18). Please delete one.")
            end
            return
        end
        CreateMacro(macroName, firstIcon, body, 1)
        if not silent then
            print("|cff00ff00[OxedHub]|r Internal mix macro created. Drag the icon to your bar!")
        end
    end

    return macroName
end

function Toys:GenerateAndExecuteMix(mixData)
    print("|cff00ff00[DEBUG]|r GenerateAndExecuteMix called")
    print("|cff00ff00[DEBUG]|r mixData type:", type(mixData))
    
    if not mixData then 
        print("|cffff0000[DEBUG]|r mixData is nil!")
        return 
    end
    
    if InCombatLockdown() then
        print("|cffff0000[OxedHub]|r Cannot run mix in combat.")
        return
    end

    print("|cff00ff00[DEBUG]|r Getting macro text...")
    local body = self:GetMixMacroText(mixData)
    
    if not body then 
        print("|cffff0000[DEBUG]|r GetMixMacroText returned nil!")
        return 
    end
    
    print("|cff00ff00[DEBUG]|r Macro body length:", #body)
    print("|cff00ff00[DEBUG]|r Macro body:")
    print(body)

    local tempName = "OxedHub_RunMix"
    print("|cff00ff00[DEBUG]|r Creating/updating macro:", tempName)
    
    local index = GetMacroIndexByName(tempName)
    print("|cff00ff00[DEBUG]|r Macro index:", index)
    
    if index > 0 then
        EditMacro(index, tempName, nil, body)
        print("|cff00ff00[DEBUG]|r Macro updated")
    else
        CreateMacro(tempName, "INV_MISC_QUESTIONMARK", body, 1)
        print("|cff00ff00[DEBUG]|r Macro created")
    end

    -- ExecuteMacro doesn't exist; use a temporary secure button
    if not self.runMixSecureBtn then
        print("|cff00ff00[DEBUG]|r Creating secure button...")
        self.runMixSecureBtn = CreateFrame("Button", "OxedHubTempRunMix", UIParent, "SecureActionButtonTemplate")
        self.runMixSecureBtn:SetAttribute("type", "macro")
        print("|cff00ff00[DEBUG]|r Secure button created")
    end
    
    print("|cff00ff00[DEBUG]|r Setting macrotext attribute...")
    self.runMixSecureBtn:SetAttribute("macrotext", body)
    
    print("|cff00ff00[DEBUG]|r Clicking secure button...")
    self.runMixSecureBtn:Click()
    
    print("|cff00ff00[DEBUG]|r Secure button clicked!")
end

-- Get icon texture from saved mix data (first toy or spell icon)
function Toys:GetMixIcon(name)
    local mixData = (OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name])
        or (OxedHub.MacroRegistry and OxedHub.MacroRegistry:GetMacros()[name])
    if type(mixData) ~= "table" or not mixData.slots then return nil end
    for _, slot in ipairs(mixData.slots) do
        if slot then
            if slot.type == "toy" then
                local icon = GetToyIconTexture(slot.id)
                if icon then return icon end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.iconID then return spellInfo.iconID end
            end
        end
    end
    return nil
end
