-- ============================================================================
-- AddOn Manager (built-in OxedHub module)
-- A tidier addon list: addons grouped under the one they belong to (a plugin
-- under the addon it needs, "DBM-Core" with the other "DBM-" parts), a search
-- box, switching for this character or for all of them, saved sets to swap
-- between (a raid set, a levelling set), and a clear "reload needed" when
-- what is switched on no longer matches what is loaded.
--
-- Switching an addon on or off is not protected, and nothing here runs in
-- combat that could matter; the reload itself is the player's own click.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    allCharacters = false,  -- switch addons for every character, not only this one
    minimapButton = true,   -- its own icon on the minimap while switched on
    -- sets and collapsed are tables, made in BindSettings
}

local ROW_H, ROWS = 22, 20
local SELF = addonName       -- never switched off by "all off" or a set

local settings
local optionsWindow
local window
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local loadedAtStart = {}         -- addon -> was it enabled when the UI loaded

local GetNum      = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
local GetInfo     = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
local IsLoaded    = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
local GetDeps     = C_AddOns and C_AddOns.GetAddOnDependencies or GetAddOnDependencies
local GetMeta     = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local EnableOne   = C_AddOns and C_AddOns.EnableAddOn or EnableAddOn
local DisableOne  = C_AddOns and C_AddOns.DisableAddOn or DisableAddOn
local SaveAddOns  = C_AddOns and C_AddOns.SaveAddOns or SaveAddOns
local EnableState = C_AddOns and C_AddOns.GetAddOnEnableState or GetAddOnEnableState

local function Character()
    return not settings.allCharacters and UnitName("player") or nil
end

local function IsEnabled(name)
    local ok, state = pcall(EnableState, name, UnitName("player"))
    if not ok then ok, state = pcall(EnableState, UnitName("player"), name) end
    return ok and type(state) == "number" and state > 0
end

local function SetEnabled(name, on)
    if name == SELF and not on then return end
    if on then EnableOne(name, Character()) else DisableOne(name, Character()) end
end

local function Commit()
    if SaveAddOns then pcall(SaveAddOns) end
end

-- ── The list ───────────────────────────────────────────────────────────────

-- Every installed addon, with the group it belongs to. A plugin goes under
-- the first addon it needs; addons sharing a name prefix ("DBM-", "BigWigs_")
-- with at least one other go together.
local function ReadAddons()
    local list, byName = {}, {}
    for i = 1, GetNum() do
        local name, title, notes, loadable, reason = GetInfo(i)
        if name then
            local a = {
                index = i, name = name, title = (title and title ~= "") and title or name, notes = notes,
                loadable = loadable, reason = reason, loaded = IsLoaded(i),
                deps = { GetDeps(i) }, version = GetMeta and GetMeta(i, "Version"),
                onDemand = C_AddOns and C_AddOns.IsAddOnLoadOnDemand and C_AddOns.IsAddOnLoadOnDemand(i),
            }
            a.enabled = IsEnabled(name)
            list[#list + 1] = a
            byName[name] = a
        end
    end

    local prefixCount = {}
    for _, a in ipairs(list) do
        local prefix = a.name:match("^(.-)[_%-]")
        a.prefix = (prefix and prefix ~= "") and prefix or nil
        if a.prefix then prefixCount[a.prefix] = (prefixCount[a.prefix] or 0) + 1 end
    end

    -- The root: follow the first installed dependency up, else the prefix.
    for _, a in ipairs(list) do
        local root, seen = a, {}
        while root and not seen[root] do
            seen[root] = true
            local parent
            for _, dep in ipairs(root.deps) do
                if byName[dep] and not dep:match("^Blizzard_") then parent = byName[dep] break end
            end
            if not parent then break end
            root = parent
        end
        if root ~= a then
            a.group = root.name
        elseif a.prefix and prefixCount[a.prefix] > 1 then
            a.group = byName[a.prefix] and a.prefix or ("~" .. a.prefix)
        else
            a.group = a.name
        end
    end
    return list, byName
end

-- What the window shows, in order: a group header, then its members when
-- the group is open. Search shows matching addons flat.
local function BuildRows(filter)
    local list, byName = ReadAddons()
    local groups, order = {}, {}
    for _, a in ipairs(list) do
        local g = groups[a.group]
        if not g then
            g = { key = a.group, members = {} }
            g.head = byName[a.group]
            g.title = g.head and g.head.title or a.group:gsub("^~", "")
            groups[a.group] = g
            order[#order + 1] = g
        end
        if a ~= g.head then g.members[#g.members + 1] = a end
    end
    local function Plain(text) return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower() end
    table.sort(order, function(x, y) return Plain(x.title) < Plain(y.title) end)

    local rows = {}
    if filter and filter ~= "" then
        filter = filter:lower()
        for _, a in ipairs(list) do
            if Plain(a.title):find(filter, 1, true) or a.name:lower():find(filter, 1, true) then
                rows[#rows + 1] = { addon = a }
            end
        end
        table.sort(rows, function(x, y) return Plain(x.addon.title) < Plain(y.addon.title) end)
        return rows, list
    end
    for _, g in ipairs(order) do
        table.sort(g.members, function(x, y) return Plain(x.title) < Plain(y.title) end)
        if #g.members == 0 and g.head then
            rows[#rows + 1] = { addon = g.head }
        else
            rows[#rows + 1] = { group = g }
            if not settings.collapsed[g.key] then
                for _, a in ipairs(g.members) do rows[#rows + 1] = { addon = a, child = true } end
            end
        end
    end
    return rows, list
end

-- Whether what is switched on now differs from what the UI loaded with.
local function ReloadNeeded(list)
    for _, a in ipairs(list) do
        if not a.onDemand and (loadedAtStart[a.name] or false) ~= a.enabled then return true end
    end
    return false
end

local function Status(a)
    if a.loaded then return "|cff40ff40" .. L["Loaded"] .. "|r" end
    if not a.enabled then return "|cff808080" .. L["Off"] .. "|r" end
    if a.onDemand then return "|cffaaaaaa" .. L["On demand"] .. "|r" end
    if a.reason and a.reason ~= "" and a.reason ~= "DISABLED" then
        return "|cffff6060" .. (_G["ADDON_" .. a.reason] or a.reason) .. "|r"
    end
    return "|cffffd100" .. L["Reload needed"] .. "|r"
end

-- ── Sets ───────────────────────────────────────────────────────────────────

local function SaveSet(name)
    local set = {}
    for _, a in ipairs((ReadAddons())) do
        if a.enabled then set[a.name] = true end
    end
    settings.sets[name] = set
end

local function LoadSet(name)
    local set = settings.sets[name]
    if type(set) ~= "table" then return end
    for _, a in ipairs((ReadAddons())) do
        SetEnabled(a.name, set[a.name] == true or a.name == SELF)
    end
    Commit()
end

-- ── The window ─────────────────────────────────────────────────────────────

local function Build()
    local w = CreateFrame("Frame", "OxedHubAddonManager", UIParent, "BackdropTemplate")
    w:SetSize(560, 120 + ROWS * ROW_H)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    tinsert(UISpecialFrames, "OxedHubAddonManager")

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(w, L["AddOn Manager"], 0.96)
    else
        w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        w:SetBackdropColor(0.1, 0.095, 0.085, 0.96)
    end
    local okClose, close = pcall(CreateFrame, "Button", nil, w, "UIPanelCloseButton")
    if okClose and close then
        close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
        close:SetScript("OnClick", function() w:Hide() end)
    end

    local offset, rows, list = 0, {}, {}
    local Draw

    -- ⚠ SetAutoFocus(false) first thing: a new EditBox takes the keyboard.
    local okSearch, search = pcall(CreateFrame, "EditBox", nil, w, "SearchBoxTemplate")
    if not okSearch or not search then search = CreateFrame("EditBox", nil, w, "InputBoxTemplate") end
    search:SetAutoFocus(false)
    search:SetSize(200, 20)
    search:SetPoint("TOPLEFT", w, "TOPLEFT", 24, -32)
    search:HookScript("OnTextChanged", function() offset = 0 Draw() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local function Button(text, width, onClick)
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    local scope = Button("", 150, function()
        settings.allCharacters = not settings.allCharacters
        Draw()
    end)
    scope:SetPoint("LEFT", search, "RIGHT", 12, 0)

    local sets = Button(L["Sets"], 80, nil)
    sets:SetPoint("LEFT", scope, "RIGHT", 6, 0)
    sets:SetScript("OnClick", function(self)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Saved sets"])
            local names = {}
            for name in pairs(settings.sets) do names[#names + 1] = name end
            table.sort(names)
            for _, name in ipairs(names) do
                local entry = root:CreateButton(name)
                entry:CreateButton(L["Switch to this set"], function() LoadSet(name) Draw() end)
                entry:CreateButton(L["Save the current list here"], function() SaveSet(name) end)
                entry:CreateButton(L["Delete"], function() settings.sets[name] = nil end)
            end
            if #names == 0 then root:CreateTitle(L["No sets yet"]) end
            root:CreateDivider()
            root:CreateButton(L["Save the current list as a new set..."], function()
                w.setBox:Show()
                w.setBox:SetFocus()
            end)
        end)
    end)

    -- The name for a new set, typed in a small box that appears on demand.
    local setBox = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
    setBox:SetAutoFocus(false)
    setBox:SetSize(160, 20)
    setBox:SetPoint("TOPRIGHT", w, "TOPRIGHT", -30, -58)
    setBox:SetMaxLetters(40)
    setBox:Hide()
    setBox:SetScript("OnEnterPressed", function(self)
        local name = strtrim(self:GetText() or "")
        if name ~= "" then SaveSet(name) end
        self:SetText("")
        self:ClearFocus()
        self:Hide()
    end)
    setBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() self:Hide() end)
    setBox:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    local setLabel = setBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    setLabel:SetPoint("RIGHT", setBox, "LEFT", -8, 0)
    setLabel:SetText(L["New set name:"])
    w.setBox = setBox

    -- Rows
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, w)
        row:SetSize(w:GetWidth() - 48, ROW_H)
        row:SetPoint("TOPLEFT", w, "TOPLEFT", 24, -84 - (i - 1) * ROW_H)
        row:RegisterForClicks("LeftButtonUp")
        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.06)

        row.toggle = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.toggle:SetPoint("LEFT", 2, 0)
        row.toggle:SetWidth(14)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 16, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("RIGHT", -4, 0)
        row.status:SetJustifyH("RIGHT")

        row.check:SetScript("OnClick", function(self)
            local on = self:GetChecked() and true or false
            if row.data.group then
                local g = row.data.group
                if g.head then SetEnabled(g.head.name, on) end
                for _, a in ipairs(g.members) do SetEnabled(a.name, on) end
            else
                SetEnabled(row.data.addon.name, on)
            end
            Commit()
            Draw()
        end)
        row:SetScript("OnClick", function()
            local g = row.data and row.data.group
            if not g then return end
            settings.collapsed[g.key] = not settings.collapsed[g.key] or nil
            Draw()
        end)
        row:SetScript("OnEnter", function(self)
            local a = self.data and (self.data.addon or self.data.group.head)
            if not a then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(a.title)
            if a.version and a.version ~= "" then GameTooltip:AddLine(L["Version: "] .. a.version, 0.8, 0.8, 0.8) end
            if a.notes and a.notes ~= "" then GameTooltip:AddLine(a.notes, 1, 1, 1, true) end
            if #a.deps > 0 then GameTooltip:AddLine(L["Needs: "] .. table.concat(a.deps, ", "), 1, 0.82, 0, true) end
            if a.loaded and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
                UpdateAddOnMemoryUsage()
                local kb = GetAddOnMemoryUsage(a.name) or 0
                GameTooltip:AddLine((L["Memory: %.1f MB"]):format(kb / 1024), 0.6, 0.8, 1)
            end
            GameTooltip:AddLine(a.name, 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end

    local allOn = Button(L["All on"], 90, function()
        for _, a in ipairs((ReadAddons())) do SetEnabled(a.name, true) end
        Commit()
        Draw()
    end)
    allOn:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 24, 16)
    local allOff = Button(L["All off"], 90, function()
        for _, a in ipairs((ReadAddons())) do SetEnabled(a.name, false) end
        Commit()
        Draw()
    end)
    allOff:SetPoint("LEFT", allOn, "RIGHT", 6, 0)
    local reload = Button(L["Reload UI"], 120, function() ReloadUI() end)
    reload:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -24, 16)
    local count = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", allOff, "RIGHT", 12, 0)
    count:SetPoint("RIGHT", reload, "LEFT", -12, 0)
    count:SetJustifyH("LEFT")

    local view = {}
    Draw = function()
        if not w:IsShown() then return end
        view, list = BuildRows(search:GetText())
        offset = math.max(0, math.min(offset, #view - ROWS))
        scope:SetText(settings.allCharacters and L["All characters"] or L["This character"])
        for i = 1, ROWS do
            local row, data = rows[i], view[i + offset]
            row.data = data
            if not data then
                row:Hide()
            elseif data.group then
                local g = data.group
                local on, total = 0, #g.members + (g.head and 1 or 0)
                if g.head and g.head.enabled then on = on + 1 end
                for _, a in ipairs(g.members) do if a.enabled then on = on + 1 end end
                row.toggle:SetText(settings.collapsed[g.key] and "+" or "-")
                row.check:SetChecked(on > 0)
                row.check:SetAlpha(on > 0 and on < total and 0.6 or 1)
                row.text:SetText(("%s  |cff9d9d9d(%d)|r"):format(g.title, total))
                row.status:SetText(g.head and Status(g.head) or ("|cffaaaaaa%d/%d|r"):format(on, total))
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", 16, 0)
                row:Show()
            else
                local a = data.addon
                row.toggle:SetText("")
                row.check:SetChecked(a.enabled)
                row.check:SetAlpha(1)
                row.check:ClearAllPoints()
                row.check:SetPoint("LEFT", data.child and 34 or 16, 0)
                row.text:SetText(a.title)
                row.status:SetText(Status(a))
                row:Show()
            end
        end
        local on = 0
        for _, a in ipairs(list) do if a.enabled then on = on + 1 end end
        local needed = ReloadNeeded(list)
        count:SetText((L["%d of %d addons on"]):format(on, #list)
            .. (needed and ("   |cffffd100" .. L["Reload to apply the changes."] .. "|r") or ""))
        reload:SetAlpha(needed and 1 or 0.6)
    end
    w.Draw = Draw

    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Draw()
    end)
    w:SetScript("OnShow", Draw)
    w:SetScript("OnHide", function() search:ClearFocus() setBox:ClearFocus() end)
    return w
end

local function Toggle()
    if not (settings and settings.enabled) then
        print("|cff00ccffOxedHub|r " .. L["switch the AddOn Manager module on first (/ohub > Modules)."])
        return
    end
    window = window or Build()
    window:SetShown(not window:IsShown())
end

-- ── Options and registration ───────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("AddOn Manager", 420, 260)
        optionsWindow = w
        w:AddCheckbox(settings, "allCharacters", "Switch addons for every character",
            "Off: a change applies to the character you are playing only.", function() if window then window.Draw() end end)
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        local open = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        open:SetSize(160, 22)
        open:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
        open:SetText(L["Open the list"])
        open:SetScript("OnClick", function() w:Hide() Toggle() end)
        w.cursorY = w.cursorY - 34
        w:AddNote("Type /oxaddons to open the list. A plugin is listed under the addon it needs, and addons that share a name, like DBM- or BigWigs_, are kept together. OxedHub itself is never switched off by All off or a set.")
    end
    optionsWindow:Show()
end

SLASH_OXEDADDONS1 = "/oxaddons"
SlashCmdList.OXEDADDONS = function() Toggle() end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "addonmanager", label = L["AddOn Manager"], icon = "Interface\\Icons\\INV_Misc_Gear_01",
        config = settings, hint = L["Click: the list. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else Toggle() end
        end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.addonmanager
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.addonmanager = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Lists are made here, never in DEFAULTS (they would be shared).
    if type(config.sets) ~= "table" then config.sets = {} end
    if type(config.collapsed) ~= "table" then config.collapsed = {} end
    settings = config

    -- What the UI loaded with, to tell when a reload is needed.
    for i = 1, GetNum() do
        local name = GetInfo(i)
        if name then loadedAtStart[name] = IsEnabled(name) end
    end

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "addonmanager",
        name     = "AddOn Manager",
        version  = "1.0.0",
        updated  = 20261025.12,  -- new
        author   = "Oxed",
        category = "character",
        keywords = { "addon", "addons", "manager", "enable", "disable", "set", "profile", "reload" },
        desc     = "Addons grouped, searchable, switched per character, with saved sets. /oxaddons",
        icon     = "Interface\\Icons\\INV_Misc_Gear_01",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.sets) ~= "table" then settings.sets = {} end
            if type(settings.collapsed) ~= "table" then settings.collapsed = {} end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            if window then window:Hide() end
        end,
    })
end)
