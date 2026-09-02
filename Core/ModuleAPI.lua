local addonName, OxedHub = ...
local L = OxedHub.L

local ModuleAPI = {
    modules = {}
}
OxedHub.ModuleAPI = ModuleAPI

-- ── Registry ───────────────────────────────────────────────────────────────

function ModuleAPI:Register(moduleInfo)
    if not moduleInfo or not moduleInfo.id then return end
    
    self.modules[moduleInfo.id] = moduleInfo
    
    -- Ensure saved vars exist for this module
    if not OxedHubDB.modules then
        OxedHubDB.modules = {}
    end
    if not OxedHubDB.modules[moduleInfo.id] then
        OxedHubDB.modules[moduleInfo.id] = moduleInfo.defaults or {}
    end
    
    local config = OxedHubDB.modules[moduleInfo.id]
    
    -- Create API object for the module
    local api = {
        sounds = OxedHub.Sounds,
        animations = OxedHub.Animations,
    }
    
    if config.enabled ~= false and moduleInfo.OnEnable then
        -- Run safe
        local ok, err = pcall(moduleInfo.OnEnable, moduleInfo, config, api)
        if not ok then
            print("|cffff0000OxedHub Module Error (" .. moduleInfo.name .. "):|r " .. tostring(err))
        end
    end
end

function ModuleAPI:GetModule(id)
    return self.modules[id]
end

function ModuleAPI:GetAllModules()
    return self.modules
end

-- ── UI Implementation ───────────────────────────────────────────────────────

local function AutoDiscoverModules()
    local getNumAddOns = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
    local getAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local isAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local getAddOnInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    
    local discovered = {}
    
    for i = 1, getNumAddOns() do
        local isModule = getAddOnMetadata(i, "X-OxedHub-Module")
        if isModule == "true" or isModule == "1" then
            local name, title, notes = getAddOnInfo(i)
            local lowerName = name and string.lower(name)
            if lowerName then
                discovered[lowerName] = {
                    id = name,
                name = getAddOnMetadata(i, "Title") or name,
                version = getAddOnMetadata(i, "Version") or "1.0",
                author = getAddOnMetadata(i, "Author") or "Unknown",
                desc = getAddOnMetadata(i, "Notes") or "",
                icon = getAddOnMetadata(i, "IconTexture") or "Interface\\Icons\\inv_misc_questionmark",
                isLoaded = isAddOnLoaded(i)
            }
            end
        end
    end
    
    return discovered
end

function ModuleAPI:RefreshModulesTab()
    local tab = OxedHub.UI.contentArea and OxedHub.UI.contentArea.Modules
    if not tab then return end
    
    local scrollChild = tab.scrollChild
    if not scrollChild then return end
    
    -- Clear existing cards
    if not tab.cards then tab.cards = {} end
    for _, card in ipairs(tab.cards) do
        card:Hide()
    end
    
    -- Merge auto-discovered modules with registered ones
    local allModules = AutoDiscoverModules()
    for id, mod in pairs(self.modules) do
        local lowerId = string.lower(id)
        if not allModules[lowerId] then
            allModules[lowerId] = mod
            allModules[lowerId].isLoaded = true
        else
            -- Use registered data if available, but keep isLoaded flag
            allModules[lowerId].icon = mod.icon or allModules[lowerId].icon
            allModules[lowerId].name = mod.name or allModules[lowerId].name
            allModules[lowerId].desc = mod.desc or allModules[lowerId].desc
            allModules[lowerId].version = mod.version or allModules[lowerId].version
            allModules[lowerId].author = mod.author or allModules[lowerId].author
            allModules[lowerId].OnOptionsShow = mod.OnOptionsShow
        end
    end
    
    local cardIndex = 1
    local columns = 3
    local cardWidth = 310
    local cardHeight = 110
    local paddingX = 16
    local paddingY = 16
    local startX = 16
    local startY = -70
    
    -- Convert to sorted array for consistent display
    local sortedModules = {}
    for id, mod in pairs(allModules) do
        table.insert(sortedModules, mod)
    end
    table.sort(sortedModules, function(a, b) return (a.name or "") < (b.name or "") end)
    
    for i, mod in ipairs(sortedModules) do
        local card = tab.cards[cardIndex]
        if not card then
            card = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
            card:SetSize(cardWidth, cardHeight)
            
            card:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 14,
                insets   = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            card:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            
            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(40, 40)
            icon:SetPoint("TOPLEFT", card, "TOPLEFT", 15, -15)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            card.icon = icon
            
            local title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
            title:SetPoint("RIGHT", card, "RIGHT", -15, 0)
            title:SetJustifyH("LEFT")
            card.title = title
            
            local status = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
            status:SetJustifyH("LEFT")
            card.status = status
            
            local desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
            desc:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -15, 15)
            desc:SetJustifyV("TOP")
            card.desc = desc
            
            local optionsBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
            optionsBtn:SetSize(80, 22)
            optionsBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
            optionsBtn:SetText("Options")
            optionsBtn:SetScript("OnClick", function()
                if card.mod and card.mod.OnOptionsShow then
                    card.mod.OnOptionsShow(card.mod)
                end
            end)
            card.optionsBtn = optionsBtn
            
            tab.cards[cardIndex] = card
        end
        
        card.mod = mod
        
        card.icon:SetTexture(mod.icon or "Interface\\Icons\\inv_misc_questionmark")
        card.title:SetText(mod.name or mod.id)
        
        if mod.isLoaded then
            card.status:SetText("|cff00ff00Active|r - v" .. (mod.version or "1.0"))
            card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            card.icon:SetDesaturated(false)
        else
            card.status:SetText("|cffff0000Disabled|r - v" .. (mod.version or "1.0"))
            card:SetBackdropBorderColor(0.3, 0.1, 0.1, 1)
            card.icon:SetDesaturated(true)
        end
        
        card.desc:SetText(mod.desc or "")
        
        if mod.OnOptionsShow then
            card.optionsBtn:Show()
        else
            card.optionsBtn:Hide()
        end
        
        -- Calculate grid position
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        
        local x = startX + (col * (cardWidth + paddingX))
        local y = startY - (row * (cardHeight + paddingY))
        
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
        card:Show()
        
        cardIndex = cardIndex + 1
    end
end
