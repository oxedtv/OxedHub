local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile
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
    -- Not a category a module can belong to: the player's own starred ones,
    -- shown second so they are one click from opening the page.
    { key = "favorites", label = "Favorites" },
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
    if category.key ~= "all" and category.key ~= "favorites" then
        VALID_CATEGORY[category.key] = true
    end
end

-- ── Favourites ──────────────────────────────────────────────────────────────
-- Starred on the card, kept account-wide by module id: a favourite is a habit of
-- the player's, not a setting of one character. The table is made the first
-- time a star is clicked, never earlier.

local function FavoriteKey(mod)
    return tostring(mod and mod.id or ""):lower()
end

function ModuleAPI:IsFavorite(mod)
    local store = OxedHubDB and OxedHubDB.globalSettings and OxedHubDB.globalSettings.moduleFavorites
    return type(store) == "table" and store[FavoriteKey(mod)] == true
end

function ModuleAPI:ToggleFavorite(mod)
    if type(OxedHubDB) ~= "table" or not mod then return end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    local store = OxedHubDB.globalSettings.moduleFavorites
    if type(store) ~= "table" then
        store = {}
        OxedHubDB.globalSettings.moduleFavorites = store
    end
    local key = FavoriteKey(mod)
    store[key] = (not store[key]) or nil
    self:RefreshModulesTab()
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

    -- ⚠ Modules are off until the player switches them on. They used to start
    -- on, and players found things selling, depositing and typing for them that
    -- they had never asked for. Every built-in module's DEFAULTS now says
    -- enabled = false, which covers new installs.
    --
    -- A saved table from before the change still says enabled = true, and
    -- nothing records whether the player chose that or simply never touched the
    -- card. So once per module, a table the player has not switched through
    -- SetModuleEnabled since (playerSet) is turned off, and the names are
    -- announced at login so nobody is left wondering where a module went.
    -- defaultOffSeen makes it happen exactly once: a module the player turns
    -- back on afterwards stays on.
    if not config.defaultOffSeen then
        config.defaultOffSeen = true
        if not config.playerSet and config.enabled ~= false then
            config.enabled = false
            self:NoteTurnedOff(moduleInfo.name or moduleInfo.id)
        end
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

-- Collects the modules the switch-off in Register turned off during this login
-- and names them in one chat line once every module has registered, instead
-- of one line per module scattered through the login messages.
local turnedOff = {}
function ModuleAPI:NoteTurnedOff(name)
    turnedOff[#turnedOff + 1] = name
    if #turnedOff > 1 then return end
    C_Timer.After(6, function()
        print("|cff00ff00OxedHub:|r modules are now |cffffd100off until you switch them on|r. "
            .. "Turned off: " .. table.concat(turnedOff, ", ")
            .. ". Open |cffffd100/ohub|r > Modules to turn back on the ones you use.")
    end)
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
    -- The player's own choice, which the one-time switch-off in Register leaves
    -- alone.
    config.playerSet = true
    config.defaultOffSeen = true

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

-- ── Asking first ───────────────────────────────────────────────────────────
-- One Yes / No popup for every module that acts on the player's behalf, so a
-- player who wants to see what is about to happen can have that on any of them.
-- A module describes what it is about to do; Yes runs it, No or Escape does not.
--
-- ModuleAPI:Confirm("Sell 5 items for 1g?", function() ... end)
-- ModuleAPI:HideConfirm()   -- when the thing being asked about went away
--
-- The name starts with OXEDHUB_ so Auto Confirm, which watches every popup the
-- game shows, knows it is ours and never tries to answer it.
local CONFIRM_POPUP = "OXEDHUB_MODULE_CONFIRM"

function ModuleAPI:Confirm(text, onAccept, onCancel)
    if not (StaticPopupDialogs and StaticPopup_Show) then
        -- No popup system to ask with: acting silently would defeat the point
        -- of asking, so nothing happens.
        return
    end

    if not StaticPopupDialogs[CONFIRM_POPUP] then
        StaticPopupDialogs[CONFIRM_POPUP] = {
            text = "%s",
            button1 = YES or "Yes",
            button2 = NO or "No",
            -- The callbacks ride in the popup's data, so two questions in a row
            -- each run their own answer rather than whichever was set last.
            OnAccept = function(self, data)
                data = data or (self and self.data)
                if data and data.accept then data.accept() end
            end,
            OnCancel = function(self, data)
                data = data or (self and self.data)
                if data and data.cancel then data.cancel() end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end

    StaticPopup_Hide(CONFIRM_POPUP)
    StaticPopup_Show(CONFIRM_POPUP, "|cff00ff00OxedHub|r\n\n" .. tostring(text), nil,
        { accept = onAccept, cancel = onCancel })
end

function ModuleAPI:HideConfirm()
    if StaticPopup_Hide then StaticPopup_Hide(CONFIRM_POPUP) end
end

-- Adds one bag slot to a list of items for a question, merging stacks of the
-- same item so twelve slots of the same ore read as one line.
--   list: the table being built, reused between calls
--   info: a C_Container.GetContainerItemInfo result
--   value: copper this slot is worth, or nil
function ModuleAPI:AddItemToList(list, info, value)
    if type(info) ~= "table" or not info.itemID then return end
    list.byID = list.byID or {}
    local entry = list.byID[info.itemID]
    if not entry then
        entry = { icon = info.iconFileID, link = info.hyperlink, itemID = info.itemID, count = 0, value = 0 }
        list.byID[info.itemID] = entry
        list[#list + 1] = entry
    end
    entry.count = entry.count + (info.stackCount or 1)
    entry.value = entry.value + (value or 0)
end

-- The items as lines of text: icon, name in its quality colour, how many, and
-- the value when a formatter is given. Most valuable first, then largest
-- stacks, so the lines worth a second look are the ones at the top. Long lists
-- stop at `limit` and say how many more there are, because a popup that runs
-- off the screen hides its own Yes button.
function ModuleAPI:FormatItemList(list, limit, formatValue)
    limit = limit or 10
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.count > b.count
    end)

    local lines = {}
    for index, entry in ipairs(list) do
        if index > limit then
            lines[#lines + 1] = ("|cff9d9d9d...and %d more|r"):format(#list - limit)
            break
        end
        -- The link without its clickable wrapper: a popup cannot open it, and
        -- the bare "[Name]" keeps its quality colour.
        local name = entry.link and entry.link:gsub("|H.-|h(.-)|h", "%1") or ("item " .. entry.itemID)
        local line = ("|T%s:14:14:0:0|t %s"):format(tostring(entry.icon or 134400), name)
        if entry.count > 1 then line = line .. (" x%d"):format(entry.count) end
        if formatValue and entry.value > 0 then
            line = line .. "  |cffffffff" .. formatValue(entry.value) .. "|r"
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
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
                keywords = getAddOnMetadata(i, "X-OxedHub-Keywords"),
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
    if saved == "all" or saved == "favorites" or VALID_CATEGORY[saved] then return saved end
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
        if self:IsFavorite(mod) then counts.favorites = (counts.favorites or 0) + 1 end
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

-- ── Search ──────────────────────────────────────────────────────────────────
-- The box at the top of the window filters the cards while the Modules page is
-- open. A card matches when every word typed appears somewhere in its name,
-- its description, its category or the keywords the module declares -- so
-- "repair" finds Auto Vendor although its name never says so, and "auto sell"
-- does not also bring back Auto Quest.
--
-- Keywords come from the registration (keywords = { "repair", "junk" }) or,
-- for an addon that was only discovered, from its .toc:
--   ## X-OxedHub-Keywords: repair, junk, sell

ModuleAPI.searchQuery = nil

local function SearchWords(query)
    if type(query) ~= "string" then return nil end
    local words = {}
    for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
    return #words > 0 and words or nil
end

local function CategoryLabel(key)
    for _, category in ipairs(ModuleAPI.CATEGORIES) do
        if category.key == key then return category.label end
    end
    return ""
end

local function Haystack(mod)
    local parts = { mod.name or "", mod.desc or "", CategoryLabel(mod.category) }
    local keywords = mod.keywords
    if type(keywords) == "table" then
        for _, word in ipairs(keywords) do parts[#parts + 1] = tostring(word) end
    elseif type(keywords) == "string" then
        parts[#parts + 1] = keywords
    end
    return table.concat(parts, " "):lower()
end

local function Matches(mod, words)
    local haystack = Haystack(mod)
    for _, word in ipairs(words) do
        -- Plain find: a word such as "+" or "." is text to look for here, not a
        -- pattern character.
        if not haystack:find(word, 1, true) then return false end
    end
    return true
end

function ModuleAPI:SetSearch(query)
    self.searchQuery = query
    self:RefreshModulesTab()
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
            if mod.keywords then allModules[lowerId].keywords = mod.keywords end

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

    -- Narrow to what the search box asks for, before anything is counted: the
    -- category tabs then show how many matches each holds, and the ones with
    -- none drop out of the strip the same way empty categories always have.
    local words = SearchWords(self.searchQuery)
    local shownModules = allModules
    if words then
        shownModules = {}
        for id, mod in pairs(allModules) do
            if Matches(mod, words) then shownModules[id] = mod end
        end
    end

    local selected = self:GetSelectedCategory()

    -- While searching, a tab with no matches is looked past for the moment
    -- rather than switched away from for good: typing must not quietly change
    -- which tab the page opens on next time.
    if words and selected ~= "all" then
        local any = false
        for _, mod in pairs(shownModules) do
            if mod.category == selected or (selected == "favorites" and self:IsFavorite(mod)) then
                any = true
                break
            end
        end
        if not any then selected = "all" end
    end

    self:RebuildCategoryTabs(tab, shownModules, selected)
    -- The tab builder may have fallen back to All when the saved one is empty.
    if not words then selected = self:GetSelectedCategory() end

    -- Said out loud when nothing matches, instead of an empty page.
    if not tab.noMatches then
        tab.noMatches = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        tab.noMatches:SetPoint("TOP", scrollChild, "TOP", 0, -140)
        tab.noMatches:SetWidth(700)
    end
    local noneFound = words and next(shownModules) == nil
    if noneFound then
        tab.noMatches:SetText(("No module matches \"%s\"."):format(self.searchQuery or ""))
    end
    tab.noMatches:SetShown(noneFound and true or false)

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
    for id, mod in pairs(shownModules) do
        if selected == "all" or mod.category == selected
            or (selected == "favorites" and self:IsFavorite(mod)) then
            table.insert(sortedModules, mod)
        end
    end
    -- Starred ones first on every tab, then by name.
    table.sort(sortedModules, function(a, b)
        local fa, fb = self:IsFavorite(a), self:IsFavorite(b)
        if fa ~= fb then return fa end
        return (a.name or "") < (b.name or "")
    end)
    
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

            -- The star, on the icon's corner. Same star the sound list uses for
            -- its favourites, so it reads the same wherever it appears: bright
            -- when starred, a faint outline of itself when not.
            local star = CreateFrame("Button", nil, card)
            star:SetSize(18, 18)
            star:SetPoint("CENTER", icon, "TOPLEFT", 2, -2)
            star:SetFrameLevel(card:GetFrameLevel() + 5)
            star.tex = star:CreateTexture(nil, "OVERLAY")
            star.tex:SetAllPoints()
            star.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
            star:SetScript("OnClick", function()
                if card.mod then ModuleAPI:ToggleFavorite(card.mod) end
            end)
            star:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(card.mod and ModuleAPI:IsFavorite(card.mod)
                    and "Remove from favourites" or "Add to favourites")
                GameTooltip:Show()
            end)
            star:SetScript("OnLeave", function() GameTooltip:Hide() end)
            card.star = star
            
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

        if self:IsFavorite(mod) then
            card.star.tex:SetVertexColor(1, 1, 1, 1)
            card.star.tex:SetDesaturated(false)
        else
            card.star.tex:SetVertexColor(0.6, 0.6, 0.6, 0.45)
            card.star.tex:SetDesaturated(true)
        end
        
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
