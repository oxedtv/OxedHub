local addonName, OxedHub = ...
local L = OxedHub.L

local ModuleAPI = {
    modules = {}
}
OxedHub.ModuleAPI = ModuleAPI

-- ── Categories ─────────────────────────────────────────────────────────────
-- The tabs across the top of the Modules page, in display order. "all" is not
-- a category a module can declare; it is the view of every one of them.
--
-- A module names its category in one of two places: its .toc, as
--   ## X-OxedHub-Category: combat
-- or the table it passes to ModuleAPI:Register, as category = "combat".
-- Anything missing or misspelled lands in General rather than vanishing.
ModuleAPI.CATEGORIES = {
    { key = "all",       label = "All" },
    { key = "general",   label = "General" },
    { key = "combat",    label = "Combat" },
    { key = "pvp",       label = "PvP" },
    { key = "chat",      label = "Chat & Social" },
    { key = "inventory", label = "Inventory" },
    { key = "character", label = "Character" },
    { key = "interface", label = "Interface" },
    { key = "tools",     label = "Travel & Tools" },
}

local VALID_CATEGORY = {}
for _, category in ipairs(ModuleAPI.CATEGORIES) do
    if category.key ~= "all" then VALID_CATEGORY[category.key] = true end
end

-- Modules published before categories existed, filed where they belong so they
-- do not all pile into General until their authors catch up.
local KNOWN_CATEGORY = {
    kickbar = "combat",
}

local function NormalizeCategory(value, moduleId)
    local key = type(value) == "string" and value:lower():gsub("%s", "") or nil
    if key and VALID_CATEGORY[key] then return key end
    local known = moduleId and KNOWN_CATEGORY[tostring(moduleId):lower()]
    return known or "general"
end

-- ── Registry ───────────────────────────────────────────────────────────────

function ModuleAPI:Register(moduleInfo)
    if not moduleInfo or not moduleInfo.id then return end

    self.modules[moduleInfo.id] = moduleInfo

    -- Ensure saved vars exist for this module
    if not OxedHubDB.modules then
        OxedHubDB.modules = {}
    end

    -- Defaults are copied in key by key, never stored as the table itself.
    -- Storing the module's own DEFAULTS table meant every setting the player
    -- changed was written into the defaults, and a key added in a later version
    -- never reached anyone who already had a saved table.
    local config = OxedHubDB.modules[moduleInfo.id]
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules[moduleInfo.id] = config
    end
    for key, value in pairs(moduleInfo.defaults or {}) do
        if config[key] == nil then config[key] = value end
    end

    -- Create API object for the module
    local api = {
        sounds = OxedHub.Sounds,
        animations = OxedHub.Animations,
    }

    -- Kept so the Modules page can switch it on and off later, and so the page
    -- can tell a module running inside OxedHub from an addon it only found.
    moduleInfo._registered = true
    moduleInfo._api = api

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

-- Whether a registered module is switched on. A module that has never been
-- touched counts as on, which is what Register assumes as well.
function ModuleAPI:IsModuleEnabled(id)
    local config = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules[id]
    return not config or config.enabled ~= false
end

-- Switch a registered module on or off, now, without a reload.
--
-- Goes through the module's own OnEnable / OnDisable, so whatever it runs --
-- an update loop, an event watcher, a frame on screen -- is started or taken
-- down by the code that knows about it. One route for the card's tick box and
-- for anything else that wants to do the same, such as a slash command.
function ModuleAPI:SetModuleEnabled(id, on)
    local mod = self.modules[id]
    if not mod then return end

    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules[id]
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules[id] = config
    end
    config.enabled = on and true or false

    local handler = on and mod.OnEnable or mod.OnDisable
    if handler then
        local ok, err = pcall(handler, mod, config, mod._api)
        if not ok then
            print("|cffff0000OxedHub Module Error (" .. tostring(mod.name or id) .. "):|r " .. tostring(err))
        end
    end

    self:RefreshModulesTab()
end

function ModuleAPI:GetAllModules()
    return self.modules
end

-- ── UI Implementation ───────────────────────────────────────────────────────

-- ── Options windows ────────────────────────────────────────────────────────
-- One small settings window, built the same way for every module.
--
-- KickBar grew its own by hand, and sixty modules each doing that would be
-- sixty slightly different windows. This gives a module a titled, draggable
-- frame and a way to add tick boxes bound straight to its saved settings.
--
-- DIALOG at level 200: above the OxedHub window, whose sidebar sits at 150,
-- and below the sound and animation pickers at 220, so a picker opened from
-- one of these is never hidden behind it.
function ModuleAPI:CreateOptionsWindow(title, width, height)
    local f = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(width or 380, height or 220)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    titleText:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0)
    titleText:SetText(title or "Settings")

    f.cursorY = -36
    f.checks = {}

    -- A tick box for one boolean setting. It reads the saved value each time
    -- the window opens rather than once, so a change made elsewhere -- a slash
    -- command, another window -- is what the box shows.
    function f:AddCheckbox(config, key, label, tooltip, onChange)
        local box = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
        box:SetSize(24, 24)
        box:SetPoint("TOPLEFT", self, "TOPLEFT", 16, self.cursorY)
        box.text:SetFontObject("GameFontHighlight")
        box.text:SetText(label)

        box:SetScript("OnClick", function(button)
            config[key] = button:GetChecked() and true or false
            if onChange then onChange(config[key]) end
        end)

        if tooltip then
            box:SetScript("OnEnter", function(button)
                GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
                GameTooltip:SetText(label)
                GameTooltip:AddLine(tooltip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            box:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end

        box.Refresh = function() box:SetChecked(config[key] == true) end
        table.insert(self.checks, box)
        self.cursorY = self.cursorY - 28
        return box
    end

    -- A line of explanation under the boxes, wrapped to the window.
    function f:AddNote(text)
        local note = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", self, "TOPLEFT", 20, self.cursorY - 6)
        note:SetWidth(self:GetWidth() - 40)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.75, 0.75, 0.75, 1)
        note:SetText(text)
        self.cursorY = self.cursorY - 6 - note:GetStringHeight() - 8
        return note
    end

    f:SetScript("OnShow", function(self)
        for _, box in ipairs(self.checks) do box.Refresh() end
    end)

    f:Hide()
    return f
end

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
                category = NormalizeCategory(getAddOnMetadata(i, "X-OxedHub-Category"), name),
                isLoaded = isAddOnLoaded(i)
            }
            end
        end
    end
    
    return discovered
end

-- Which tab is open. Remembered account-wide: it is a viewing preference, not
-- part of a profile, and reopening the page on the tab you left is the point.
function ModuleAPI:GetSelectedCategory()
    local settings = OxedHubDB and OxedHubDB.globalSettings
    local saved = settings and settings.modulesCategory
    if saved == "all" or VALID_CATEGORY[saved] then return saved end
    return "all"
end

function ModuleAPI:SetSelectedCategory(key)
    if type(OxedHubDB) ~= "table" then return end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    OxedHubDB.globalSettings.modulesCategory = key
end

-- The tab strip under the page title.
--
-- Only categories that hold at least one module get a tab. Eight empty tabs
-- would be most of the strip on day one, and a tab that opens onto nothing
-- reads as broken rather than as "coming later". They appear as modules do.
--
-- Built with PanelTopTabButtonTemplate, the same tabs as the trigger page and
-- the toy categories, so the page does not invent a third look.
function ModuleAPI:RebuildCategoryTabs(tab, allModules, selected)
    local scrollChild = tab.scrollChild
    if not scrollChild then return end

    local strip = tab.categoryStrip
    if not strip then
        strip = CreateFrame("Frame", nil, scrollChild)
        strip:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, -62)
        strip:SetSize(960, 30)
        tab.categoryStrip = strip
    end

    for _, button in ipairs(tab.categoryTabs or {}) do
        button:Hide()
        button:SetParent(nil)
    end
    tab.categoryTabs = {}

    local counts, total = {}, 0
    for _, mod in pairs(allModules) do
        counts[mod.category] = (counts[mod.category] or 0) + 1
        total = total + 1
    end
    counts.all = total

    -- The remembered tab may have been emptied since -- its only module
    -- uninstalled -- so fall back to All rather than open onto nothing.
    if selected ~= "all" and not counts[selected] then
        selected = "all"
        self:SetSelectedCategory("all")
    end

    local baseLevel = strip:GetFrameLevel() + 10
    local previous

    for _, category in ipairs(self.CATEGORIES) do
        local count = counts[category.key]
        if count and count > 0 then
            local button = CreateFrame("Button", nil, strip, "PanelTopTabButtonTemplate")
            -- rawget, not L[...]: the locale table answers a missing key with
            -- the key itself, so a translation lacking these would print
            -- MODULES_CAT_COMBAT on the tab instead of falling back.
            local label = (L and rawget(L, "MODULES_CAT_" .. category.key:upper()))
                or category.label
            button:SetText(("%s (%d)"):format(label, count))
            PanelTemplates_TabResize(button, 15, nil, 70)

            if previous then
                button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
            else
                button:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
            end
            previous = button

            if category.key == selected then
                PanelTemplates_SelectTab(button)
                button:SetFrameLevel(baseLevel + 5)
            else
                PanelTemplates_DeselectTab(button)
                button:SetFrameLevel(baseLevel)
            end

            local key = category.key
            button:SetScript("OnClick", function()
                if ModuleAPI:GetSelectedCategory() == key then return end
                ModuleAPI:SetSelectedCategory(key)
                ModuleAPI:RefreshModulesTab()
            end)

            table.insert(tab.categoryTabs, button)
        end
    end
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
            -- The registration wins: it is the module's own code speaking,
            -- where the .toc may be older than it.
            if mod.category then allModules[lowerId].category = mod.category end

            -- Registered means it is running inside OxedHub, whatever the
            -- addon list says. A module that moved in from its own folder can
            -- still be found there as a disabled addon, and trusting that
            -- flag showed it as Disabled while it was working.
            allModules[lowerId].id = mod.id
            allModules[lowerId].isLoaded = true
            allModules[lowerId]._registered = true
        end
    end

    -- Every module ends up with a valid category, whichever route it came by.
    for id, mod in pairs(allModules) do
        mod.category = NormalizeCategory(mod.category, mod.id or id)
    end

    local selected = self:GetSelectedCategory()
    self:RebuildCategoryTabs(tab, allModules, selected)
    -- The tab builder may have fallen back to All when the saved one is empty.
    selected = self:GetSelectedCategory()

    local cardIndex = 1
    local columns = 3
    local cardWidth = 310
    local cardHeight = 110
    local paddingX = 16
    local paddingY = 16
    local startX = 16
    -- Below the title, the description and the category tabs.
    local startY = -104
    
    -- Convert to sorted array for consistent display
    local sortedModules = {}
    for id, mod in pairs(allModules) do
        if selected == "all" or mod.category == selected then
            table.insert(sortedModules, mod)
        end
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

            -- On / off, for modules that run inside OxedHub. An addon that was
            -- only discovered has no switch here: loading or unloading one
            -- takes a reload and belongs to the game's addon list.
            local enableCheck = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
            enableCheck:SetSize(22, 22)
            enableCheck:SetPoint("TOPRIGHT", optionsBtn, "BOTTOMRIGHT", 0, -4)
            enableCheck.text:ClearAllPoints()
            enableCheck.text:SetPoint("RIGHT", enableCheck, "LEFT", -2, 1)
            enableCheck.text:SetFontObject("GameFontHighlightSmall")
            enableCheck.text:SetText(L and rawget(L, "MODULES_ENABLED") or "Enabled")
            enableCheck:SetScript("OnClick", function(self)
                local current = card.mod
                if not current or not current._registered then return end
                ModuleAPI:SetModuleEnabled(current.id, self:GetChecked() and true or false)
            end)
            card.enableCheck = enableCheck
            
            tab.cards[cardIndex] = card
        end
        
        card.mod = mod
        
        card.icon:SetTexture(mod.icon or "Interface\\Icons\\inv_misc_questionmark")
        card.title:SetText(mod.name or mod.id)
        
        -- A built-in module is active when its own setting says so; a found
        -- addon is active when the game has loaded it.
        local active
        if mod._registered then
            active = self:IsModuleEnabled(mod.id)
            card.enableCheck:SetChecked(active)
            card.enableCheck:Show()
        else
            active = mod.isLoaded
            card.enableCheck:Hide()
        end

        if active then
            card.status:SetText("|cff00ff00Active|r - v" .. (mod.version or "1.0"))
            card:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            card.icon:SetDesaturated(false)
        else
            card.status:SetText("|cffff0000Disabled|r - v" .. (mod.version or "1.0"))
            card:SetBackdropBorderColor(0.3, 0.1, 0.1, 1)
            card.icon:SetDesaturated(true)
        end
        
        -- ⚠ The card has a fixed height and no ellipsis handling, so a long
        -- desc is cut off mid-word with no sign that anything is missing. Keep
        -- desc in ModuleAPI:Register to roughly 100 characters; anything longer
        -- belongs in the module's options window, via AddNote.
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
        
        -- Cards are reused, so a card that sat elsewhere last time must lose
        -- its old anchor or it stretches between the two positions.
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", x, y)
        card:Show()

        cardIndex = cardIndex + 1
    end

    -- Tall enough to scroll to the last row once a category has more modules
    -- than fit on the page.
    local rows = math.ceil(#sortedModules / columns)
    local needed = -startY + rows * (cardHeight + paddingY) + 16
    scrollChild:SetHeight(math.max(586, needed))
end
