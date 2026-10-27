-- ============================================================================
-- Minimap Buttons (built-in OxedHub module)
-- Every addon's button on the minimap gathered behind one button of ours.
-- A click opens a drawer with all of them in rows; the minimap stays clean.
--
-- What is gathered:
--   * LibDBIcon buttons (most addons), including ones made later, through the
--     library's IconCreated callback; LibMapButton buttons.
--   * Other children of the minimap whose name reads like a minimap button.
--     Blizzard's own (secure globals), map pins (names ending in a number,
--     HandyNotes, TomTom, ...) are left alone.
--   * Anything the player names with /oxmb add <frame or path>; anything named
--     with /oxmb ignore <frame> is never taken.
--
-- ⚠ A gathered button belongs to another addon. Each one keeps what it had
-- (parent, points, scale, strata, drag scripts, any SetPoint of its own) and
-- gets all of it back when the module is switched off, with no reload.
-- While gathered, its SetPoint / ClearAllPoints / SetParent / SetScale are
-- blocked: many addons move their button again every time the minimap
-- changes, and would pull it out of the drawer.
--
-- ⚠ Blizzard's frames are never taken (issecurevariable): moving one taints
-- it. A drawer that holds a protected frame cannot open or close in combat;
-- that is checked before every Show / Hide.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled         = false,  -- off until the player switches it on
    direction       = "leftdown",
    perRow          = 6,
    scale           = 1,      -- our button
    buttonScale     = 1,      -- the gathered buttons
    autoClose       = true,   -- the drawer closes once the mouse leaves it
    rememberOpen    = false,  -- open again after a reload if it was open
    wasOpen         = false,
    background      = true,
    hideCompartment = false,  -- the game's addon compartment beside the minimap
    hideInPetBattle = true,
    locked          = false,  -- no moving our button

    -- "ignore", "include" and "position" are tables, built in Bind: a table
    -- in DEFAULTS is copied by reference and every character would share it.
}

local PREFIX = "|cff00ccffOxedHub Minimap Buttons:|r "
local CELL = 34            -- one slot in the drawer, at button scale 1
local PAD = 6              -- the drawer's edge around the slots
local CLOSE_AFTER = 0.8    -- seconds outside the drawer before it closes

local settings
local optionsWindow
local running = false

local main                 -- our button
local drawer               -- the frame the gathered buttons sit in
local collected = {}       -- [button] = what it had before (see Take)
local order = {}           -- gathered buttons, sorted by name
local hooked = {}          -- [button] = true once Show / Hide are hooked
local libHooked = false

local Layout               -- defined with the drawer
local Scan                 -- defined with the gathering code
local DrawerColours        -- defined with the compartment code

-- The plain widget methods, so a gathered button can still be placed while
-- its own SetPoint and friends are blocked.
local proto = CreateFrame("Frame")
local RawSetPoint, RawClearAllPoints = proto.SetPoint, proto.ClearAllPoints
local RawSetParent, RawSetScale = proto.SetParent, proto.SetScale
proto:Hide()

local BLOCKED = { "SetPoint", "ClearAllPoints", "SetParent", "SetScale" }
local function DoNothing() end

-- ── Small helpers ───────────────────────────────────────────────────────────

local function Name(frame)
    local ok, name = pcall(frame.GetName, frame)
    if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then return name end
    return nil
end

local function IsFrame(value)
    return type(value) == "table" and type(value.IsObjectType) == "function"
        and select(2, pcall(value.IsObjectType, value, "Frame")) == true
end

-- A frame by name or dotted path from the globals: "MyAddon.MinimapButton".
local function FrameByPath(path)
    local node = _G
    for part in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[part]
    end
    return IsFrame(node) and node or nil
end

-- Frames whose global name contains the text, any case: "zygor" finds
-- ZygorGuidesViewerMapIcon. An exact name or dotted path wins outright.
local function FindFrames(text)
    local exact = FrameByPath(text)
    if exact then return { text } end
    local low, found = text:lower(), {}
    for key, value in pairs(_G) do
        if type(key) == "string" and key:lower():find(low, 1, true) and IsFrame(value) then
            found[#found + 1] = key
            if #found >= 20 then break end
        end
    end
    table.sort(found)
    return found
end

-- Gathered whatever their names look like: buttons known to sit outside the
-- usual names. Not saved, so a later build can add to it.
local ALWAYS = { "ZygorGuidesViewerMapIcon", "TrinketMenu_IconFrame", "CodexBrowserIcon" }

local function InList(list, name)
    if not (list and name) then return nil end
    local low = name:lower()
    for key in pairs(list) do
        if key:lower() == low then return key end
    end
    return nil
end

-- Showing or hiding a frame that holds a protected one is refused in combat.
local function CanChange(frame)
    if not InCombatLockdown() then return true end
    local ok, protected = pcall(frame.IsProtected, frame)
    return not (ok and protected)
end

-- ── Our button and the drawer ───────────────────────────────────────────────

local DIRECTIONS = {
    -- first: where a row grows; second: where the next row starts.
    leftdown  = { first = { -1, 0 }, second = { 0, -1 } },
    leftup    = { first = { -1, 0 }, second = { 0,  1 } },
    rightdown = { first = {  1, 0 }, second = { 0, -1 } },
    rightup   = { first = {  1, 0 }, second = { 0,  1 } },
    downleft  = { first = { 0, -1 }, second = { -1, 0 } },
    downright = { first = { 0, -1 }, second = {  1, 0 } },
    upleft    = { first = { 0,  1 }, second = { -1, 0 } },
    upright   = { first = { 0,  1 }, second = {  1, 0 } },
}

local DIRECTION_CHOICES = {
    { value = "leftdown",  text = "Left, rows down" },
    { value = "leftup",    text = "Left, rows up" },
    { value = "rightdown", text = "Right, rows down" },
    { value = "rightup",   text = "Right, rows up" },
    { value = "downleft",  text = "Down, columns left" },
    { value = "downright", text = "Down, columns right" },
    { value = "upleft",    text = "Up, columns left" },
    { value = "upright",   text = "Up, columns right" },
}

local function SavePosition()
    local point, _, relPoint, x, y = main:GetPoint(1)
    local p = settings.position
    p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
end

local function PlaceMain()
    main:ClearAllPoints()
    local p = settings.position
    if p.point then
        main:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        -- First time: just below and left of the minimap.
        main:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 6, 6)
    end
end

local function OpenDrawer()
    if not drawer or drawer:IsShown() or not CanChange(drawer) then return end
    Scan()
    drawer:Show()
    settings.wasOpen = true
end

local function CloseDrawer()
    if not drawer or not drawer:IsShown() or not CanChange(drawer) then return end
    drawer:Hide()
    settings.wasOpen = false
end

local function ShowOptions() end   -- replaced below; the button needs a name for it now

local function BuildMain()
    if main then return end
    main = CreateFrame("Button", "OxedHubMinimapButtonsButton", UIParent)
    main:SetSize(32, 32)
    main:SetFrameStrata("MEDIUM")
    main:SetFrameLevel(8)
    main:SetClampedToScreen(true)
    main:SetMovable(true)
    main:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    main:Hide()

    local bg = main:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = main:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10_Blue")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local mask = main:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
    local border = main:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    main:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Alt + drag, or the middle button, moves it; a plain click opens.
    main:SetScript("OnMouseDown", function(self, mouse)
        if settings.locked then return end
        if mouse == "MiddleButton" or IsAltKeyDown() then
            self.moving = true
            self:StartMoving()
        end
    end)
    main:SetScript("OnMouseUp", function(self)
        if self.moving then
            self.moving = nil
            self:StopMovingOrSizing()
            SavePosition()
        end
    end)
    main:SetScript("OnClick", function(_, mouse)
        if IsAltKeyDown() then return end
        if mouse == "RightButton" then
            ShowOptions()
        elseif drawer:IsShown() then
            CloseDrawer()
        else
            OpenDrawer()
        end
    end)
    main:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Minimap Buttons"])
        GameTooltip:AddLine((L["%d button(s) gathered"]):format(#order), 1, 1, 1)
        GameTooltip:AddLine(L["|cffffd100Click|r open or close"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["|cffffd100Right-click|r options"], 0.8, 0.8, 0.8)
        if not settings.locked then
            GameTooltip:AddLine(L["|cffffd100Alt + drag|r or |cffffd100middle button|r move"], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    main:SetScript("OnLeave", function() GameTooltip:Hide() end)

    drawer = CreateFrame("Frame", nil, main, "BackdropTemplate")
    drawer:SetFrameStrata("MEDIUM")
    drawer:SetFrameLevel(7)
    drawer:Hide()
    drawer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })

    -- Closing when the mouse has left both the drawer and our button for a
    -- moment; only checked while the drawer is open.
    local away, tick = 0, 0
    drawer:SetScript("OnShow", function() away, tick = 0, 0 end)
    drawer:SetScript("OnUpdate", function(self, elapsed)
        if not settings.autoClose then return end
        tick = tick + elapsed
        if tick < 0.2 then return end
        if self:IsMouseOver(4, -4, -4, 4) or main:IsMouseOver() then
            away = 0
        else
            away = away + tick
            if away >= CLOSE_AFTER then CloseDrawer() end
        end
        tick = 0
    end)
end

-- Slots laid out from our button outward, in the chosen direction.
Layout = function()
    if not drawer then return end
    if InCombatLockdown() and not CanChange(drawer) then return end
    local dir = DIRECTIONS[settings.direction] or DIRECTIONS.leftdown
    local perRow = math.max(1, math.floor(tonumber(settings.perRow) or 6))
    local cell = CELL * (tonumber(settings.buttonScale) or 1)

    local minX, minY, maxX, maxY
    local slot = 0
    for _, button in ipairs(order) do
        local holder = collected[button] and collected[button].holder
        if holder then
            if button:IsShown() then
                local col, row = slot % perRow, math.floor(slot / perRow)
                local x = (col + 1) * dir.first[1] * cell + row * dir.second[1] * cell
                local y = (col + 1) * dir.first[2] * cell + row * dir.second[2] * cell
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", main, "CENTER", x, y)
                holder:SetSize(cell, cell)
                holder:Show()
                minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
                minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
                slot = slot + 1
            else
                holder:Hide()
            end
        end
    end

    drawer:ClearAllPoints()
    if slot == 0 then
        drawer:SetSize(1, 1)
        drawer:SetPoint("CENTER", main, "CENTER")
        drawer:SetBackdropColor(0, 0, 0, 0)
        drawer:SetBackdropBorderColor(0, 0, 0, 0)
        return
    end
    local half = cell / 2 + PAD
    drawer:SetPoint("TOPLEFT", main, "CENTER", minX - half, maxY + half)
    drawer:SetPoint("BOTTOMRIGHT", main, "CENTER", maxX + half, minY - half)
    if settings.background then
        local r, g, b, a, er, eg, eb, ea = DrawerColours()
        drawer:SetBackdropColor(r, g, b, a)
        drawer:SetBackdropBorderColor(er, eg, eb, ea)
    else
        drawer:SetBackdropColor(0, 0, 0, 0)
        drawer:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

local function ApplyScale()
    if main then main:SetScale(tonumber(settings.scale) or 1) end
    for button in pairs(collected) do
        RawSetScale(button, tonumber(settings.buttonScale) or 1)
    end
    Layout()
end

-- ── Taking a button, and giving it back ─────────────────────────────────────

local layoutQueued = false
local function QueueLayout()
    if layoutQueued then return end
    layoutQueued = true
    C_Timer.After(0, function()
        layoutQueued = false
        if running then Layout() end
    end)
end

local function Take(button)
    if collected[button] or button == main then return false end
    local saved = {
        parent  = button:GetParent(),
        strata  = button:GetFrameStrata(),
        scale   = button:GetScale(),
        ignoreParentScale = button.GetIgnoreParentScale and button:GetIgnoreParentScale(),
        points  = {},
        own     = {},   -- the button's own methods we cover, if it had any
        dragStart = button:GetScript("OnDragStart"),
        dragStop  = button:GetScript("OnDragStop"),
    }
    for i = 1, button:GetNumPoints() do saved.points[i] = { button:GetPoint(i) } end
    for _, method in ipairs(BLOCKED) do saved.own[method] = rawget(button, method) end

    local holder = CreateFrame("Frame", nil, drawer)
    holder:SetSize(CELL, CELL)
    saved.holder = holder
    collected[button] = saved

    RawSetParent(button, holder)
    RawClearAllPoints(button)
    RawSetPoint(button, "CENTER", holder, "CENTER", 0, 0)
    if button.SetIgnoreParentScale then button:SetIgnoreParentScale(false) end
    RawSetScale(button, tonumber(settings.buttonScale) or 1)
    button:SetFrameStrata("MEDIUM")
    button:SetScript("OnDragStart", nil)
    button:SetScript("OnDragStop", nil)
    for _, method in ipairs(BLOCKED) do button[method] = DoNothing end

    -- Its addon hiding or showing it changes the drawer; hooked once, and
    -- quiet once the button is given back.
    if not hooked[button] and type(button.Show) == "function" then
        hooked[button] = true
        hooksecurefunc(button, "Show", function(self) if collected[self] then QueueLayout() end end)
        hooksecurefunc(button, "Hide", function(self) if collected[self] then QueueLayout() end end)
    end

    order[#order + 1] = button
    return true
end

local function GiveBack(button)
    local saved = collected[button]
    if not saved then return end
    for _, method in ipairs(BLOCKED) do button[method] = saved.own[method] end
    RawSetParent(button, saved.parent or Minimap)
    RawClearAllPoints(button)
    for _, point in ipairs(saved.points) do
        pcall(RawSetPoint, button, unpack(point))
    end
    RawSetScale(button, saved.scale or 1)
    if button.SetIgnoreParentScale and saved.ignoreParentScale ~= nil then
        button:SetIgnoreParentScale(saved.ignoreParentScale)
    end
    pcall(button.SetFrameStrata, button, saved.strata or "MEDIUM")
    button:SetScript("OnDragStart", saved.dragStart)
    button:SetScript("OnDragStop", saved.dragStop)
    saved.holder:Hide()
    collected[button] = nil
end

local function GiveAllBack()
    for i = #order, 1, -1 do
        GiveBack(order[i])
        order[i] = nil
    end
end

-- ── Which frames are minimap buttons ────────────────────────────────────────

local BUTTON_PATTERNS = {
    "^LibDBIcon10_", "MinimapButton", "MinimapIcon", "MinimapFrame",
    "[%-_]Minimap[%-_]", "Minimap$",
}
local PIN_PATTERNS = {
    "^HandyNotes", "^TomTom", "^HereBeDragons", "^Questie", "^GatherMate", "^[Pp]in",
}

local function LooksLikeButton(name)
    if issecurevariable(_G, name) then return false end   -- Blizzard's own
    if name:find("^TomCats%-") then return true end      -- some end in the year
    if name:find("%d$") then return false end            -- map pins, numbered
    for _, pattern in ipairs(PIN_PATTERNS) do
        if name:find(pattern) then return false end
    end
    for _, pattern in ipairs(BUTTON_PATTERNS) do
        if name:find(pattern) then return true end
    end
    return false
end

local function Allowed(button)
    if not IsFrame(button) or collected[button] or button == main then return false end
    local name = Name(button)
    if name and InList(settings.ignore, name) then return false end
    -- A protected frame cannot be moved in combat and would lock the drawer.
    local ok, protected = pcall(button.IsProtected, button)
    if ok and protected then return false end
    return true
end

local function LibDBIcon()
    return LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
end

local function LibMapButton()
    return LibStub and LibStub:GetLibrary("LibMapButton-1.1", true)
end

local function SortOrder()
    table.sort(order, function(a, b) return (Name(a) or "") < (Name(b) or "") end)
end

-- Gathers whatever is new; a frame already taken is left as it is.
Scan = function()
    if not running or not drawer then return end
    if InCombatLockdown() then return end
    local before = #order

    local DBI = LibDBIcon()
    if DBI and DBI.GetButtonList then
        for _, id in ipairs(DBI:GetButtonList()) do
            local button = DBI:GetMinimapButton(id)
            if Allowed(button) then Take(button) end
        end
    end

    local LMB = LibMapButton()
    if LMB and type(LMB.buttons) == "table" then
        for _, button in pairs(LMB.buttons) do
            if Allowed(button) then Take(button) end
        end
    end

    for path in pairs(settings.include) do
        local button = FrameByPath(path)
        if button and not collected[button] and button ~= main then Take(button) end
    end
    for _, name in ipairs(ALWAYS) do
        local button = _G[name]
        if Allowed(button) then Take(button) end
    end

    for _, child in ipairs({ Minimap:GetChildren() }) do
        local name = Name(child)
        if name and Allowed(child) and LooksLikeButton(name) then Take(child) end
    end

    if #order ~= before then
        SortOrder()
        Layout()
    end
end

local function HookLibDBIcon()
    if libHooked then return end
    local DBI = LibDBIcon()
    if not (DBI and DBI.RegisterCallback) then return end
    libHooked = true
    -- A key of our own: the library keeps one callback per key and event.
    DBI.RegisterCallback(collected, "LibDBIcon_IconCreated", function(_, button)
        if running and not InCombatLockdown() and Allowed(button) and Take(button) then
            SortOrder()
            Layout()
        end
    end)
end

-- ── The game's addon compartment ────────────────────────────────────────────

-- The game shows it again on its own (a zone change, a new addon), so a
-- hook hides it each time while the option is on.
local compartmentHooked = false
local function ApplyCompartment()
    local frame = AddonCompartmentFrame
    if not frame then return end
    if not compartmentHooked then
        compartmentHooked = true
        frame:HookScript("OnShow", function(self)
            if running and settings.hideCompartment then self:Hide() end
        end)
    end
    local hide = running and settings.hideCompartment
    if hide then frame:Hide() elseif not frame:IsShown() then frame:Show() end
end

-- With ElvUI loaded, its own colours for the drawer, so it matches the rest.
DrawerColours = function()
    local E = ElvUI and ElvUI[1]
    local media = E and E.media
    if type(media) == "table" and type(media.backdropcolor) == "table" and type(media.bordercolor) == "table" then
        local bg, edge = media.backdropcolor, media.bordercolor
        return bg[1] or 0, bg[2] or 0, bg[3] or 0, 0.9, edge[1] or 0, edge[2] or 0, edge[3] or 0, 1
    end
    return 0.05, 0.05, 0.05, 0.85, 1, 0.82, 0, 0.5
end

-- ── Events ──────────────────────────────────────────────────────────────────

local events = CreateFrame("Frame")
local scanQueued = false
local function QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay or 1, function()
        scanQueued = false
        Scan()
    end)
end

events:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then
        -- An addon loaded on demand may add its button a moment later.
        QueueScan(1)
        HookLibDBIcon()
    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueScan(0.5)
    elseif event == "PET_BATTLE_OPENING_START" then
        if settings.hideInPetBattle and main then main:Hide() end
    elseif event == "PET_BATTLE_CLOSE" then
        if running and main then main:Show() end
    end
end)

local function Start()
    if running then return end
    running = true
    BuildMain()
    PlaceMain()
    main:Show()
    ApplyScale()
    HookLibDBIcon()
    Scan()
    -- Addons that make their button at login, or a second later.
    C_Timer.After(1, Scan)
    C_Timer.After(5, Scan)
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_REGEN_ENABLED",
        "PET_BATTLE_OPENING_START", "PET_BATTLE_CLOSE" }) do
        pcall(events.RegisterEvent, events, event)
    end
    ApplyCompartment()
    if settings.rememberOpen and settings.wasOpen then OpenDrawer() end
end

local function Stop()
    if not running then return end
    events:UnregisterAllEvents()
    if InCombatLockdown() then
        -- Taking frames back is refused for protected ones in combat; after it.
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            if not settings.enabled then Stop() end
        end)
        return
    end
    running = false
    GiveAllBack()
    if drawer then drawer:Hide() end
    if main then main:Hide() end
    ApplyCompartment()
end

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Minimap Buttons", 460, 560)
        optionsWindow = w
        w:AddChoice(settings, "direction", "Drawer opens", DIRECTION_CHOICES, Layout)
        w:AddSlider(settings, "perRow", "Buttons in a row", 1, 12, 1, "%s: %d", Layout)
        w:AddSlider(settings, "scale", "Size of this button", 0.5, 2, 0.1, "%s: %.1f", ApplyScale)
        w:AddSlider(settings, "buttonScale", "Size of the gathered buttons", 0.5, 2, 0.1, "%s: %.1f", ApplyScale)
        w:AddCheckbox(settings, "autoClose", "Close the drawer when the mouse leaves it")
        w:AddCheckbox(settings, "rememberOpen", "Open it again after a reload if it was open")
        w:AddCheckbox(settings, "background", "Dark background behind the drawer", nil, Layout)
        w:AddCheckbox(settings, "locked", "Lock this button in place")
        w:AddCheckbox(settings, "hideCompartment", "Hide the game's addon compartment",
            "The small list of addons beside the minimap.", ApplyCompartment)
        w:AddCheckbox(settings, "hideInPetBattle", "Hide during pet battles")
        w:AddNote("Alt + drag or the middle button moves this button. "
            .. "/oxmb list shows what is gathered. /oxmb ignore <name> leaves a button on the minimap, "
            .. "/oxmb unignore <name> takes it again. /oxmb add <frame> gathers one that was missed, "
            .. "/oxmb remove <frame> stops. A part of a name is enough. /oxmb clearignore and "
            .. "/oxmb clearadd empty those lists. /oxmb reset puts this button back beside the minimap.")
    end
    optionsWindow:Show()
end

-- ── Slash command ───────────────────────────────────────────────────────────

local function PrintList()
    print(PREFIX .. (L["%d button(s) gathered:"]):format(#order))
    for _, button in ipairs(order) do print("   " .. (Name(button) or L["(no name)"])) end
    if next(settings.include) then
        print(PREFIX .. L["added by hand:"])
        for path in pairs(settings.include) do print("   " .. path) end
    end
    if next(settings.ignore) then
        print(PREFIX .. L["left on the minimap:"])
        for name in pairs(settings.ignore) do print("   " .. name) end
    end
end

-- One frame for a command: a part of a name that matches several lists
-- them and asks for a longer one.
local function OneFrame(text)
    local found = FindFrames(text)
    if #found == 1 then return found[1] end
    if #found == 0 then
        print(PREFIX .. (L["no frame named like %s. /fstack shows the name of the one under the mouse."]):format(text))
    else
        print(PREFIX .. (L["more than one frame has %s in its name:"]):format(text))
        for _, name in ipairs(found) do print("   " .. name) end
    end
    return nil
end

-- Hands one gathered button back to the minimap now.
local function Release(button)
    if not (button and collected[button]) then return end
    GiveBack(button)
    for i, b in ipairs(order) do
        if b == button then table.remove(order, i) break end
    end
    Layout()
end

SLASH_OXEDMINIMAPBUTTONS1 = "/oxmb"
SLASH_OXEDMINIMAPBUTTONS2 = "/minimapbuttons"
SlashCmdList.OXEDMINIMAPBUTTONS = function(msg)
    if not settings then return end
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if not settings.enabled and cmd ~= "" then
        print(PREFIX .. L["switched off. Switch it on in OxedHub's Modules page first."])
        return
    end
    if cmd == "list" then
        PrintList()
    elseif cmd == "reset" then
        wipe(settings.position)
        if main then PlaceMain() end
        print(PREFIX .. L["the button is back beside the minimap."])
    elseif cmd == "ignore" and arg ~= "" then
        local name = OneFrame(arg) or InList(settings.include, arg)
        if not name then return end
        local key = InList(settings.include, name)
        if key then settings.include[key] = nil end
        settings.ignore[name] = true
        Release(FrameByPath(name))
        print(PREFIX .. (L["%s stays on the minimap."]):format(name))
    elseif cmd == "unignore" and arg ~= "" then
        local key = InList(settings.ignore, arg)
        if key then
            settings.ignore[key] = nil
            Scan()
            print(PREFIX .. (L["%s is gathered again."]):format(key))
        else
            print(PREFIX .. (L["%s was not being left out."]):format(arg))
        end
    elseif cmd == "add" and arg ~= "" then
        local name = OneFrame(arg)
        if not name then return end
        local key = InList(settings.ignore, name)
        if key then settings.ignore[key] = nil end
        settings.include[name] = true
        Scan()
        print(PREFIX .. (L["%s is gathered."]):format(name))
    elseif cmd == "remove" and arg ~= "" then
        local key = InList(settings.include, arg)
        if not key then
            print(PREFIX .. (L["%s was not added by hand."]):format(arg))
            return
        end
        settings.include[key] = nil
        Release(FrameByPath(key))
        print(PREFIX .. (L["%s is no longer gathered by hand."]):format(key))
    elseif cmd == "clearignore" then
        wipe(settings.ignore)
        Scan()
        print(PREFIX .. L["nothing is left out any more."])
    elseif cmd == "clearadd" then
        for path in pairs(settings.include) do Release(FrameByPath(path)) end
        wipe(settings.include)
        Scan()   -- a button that also looks like one by its name comes back
        print(PREFIX .. L["nothing is gathered by hand any more."])
    elseif cmd == "help" then
        print(PREFIX .. L["/oxmb list, reset, ignore <name>, unignore <name>, add <name>, remove <name>, "]
            .. L["clearignore, clearadd. A part of a name is enough. /oxmb alone opens the options."])
    else
        ShowOptions()
    end
end

-- ── Login ───────────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.minimapbuttons
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.minimapbuttons = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    for _, key in ipairs({ "ignore", "include", "position" }) do
        if type(config[key]) ~= "table" then config[key] = {} end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "minimapbuttons",
        name     = "Minimap Buttons",
        version  = "1.0.0",
        updated  = 20261024.6,
        author   = "Oxed",
        category = "character",
        keywords = { "minimap", "button", "buttons", "icon", "libdbicon", "drawer", "clean", "compartment" },
        desc     = "Every addon's minimap button gathered behind one button, in a drawer. /oxmb",
        icon     = "Interface\\Icons\\INV_Misc_Bag_10_Blue",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            for _, key in ipairs({ "ignore", "include", "position" }) do
                if type(settings[key]) ~= "table" then settings[key] = {} end
            end
            -- Next frame: addons that make their button at login come first.
            C_Timer.After(0, function()
                if settings.enabled then Start() end
            end)
        end,
        OnDisable = function()
            Stop()
        end,
    })
end)
