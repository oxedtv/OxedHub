-- ============================================================================
-- Game Events (built-in OxedHub module)
-- A short list of what the game's calendar has on today and in the days ahead.
-- Nothing about an event is kept here: its name, icon and dates come from the
-- calendar, and clicking a holiday gives its Wowhead link for everything else.
-- So there is nothing to update when a new holiday or season arrives.
--
-- ⚠ C_Calendar has no month at all until something sets one, and only Blizzard's
-- calendar window does, when it opens: until then every day reads as empty. So
-- while that window is closed the month is set here (it sets its own again each
-- time it opens). While it is open the month is the player's: offsets are worked
-- out from whatever it shows, and it is not moved.
-- ⚠ Read while another addon has the calendar open, fields can come back as
-- secrets, and comparing one is an error. Each entry is read inside pcall, and
-- one that cannot be read is left out.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled     = false,  -- off until the player switches it on
    daysAhead   = 14,     -- how far ahead Upcoming looks
    showOwn     = false,  -- also list guild events and the ones you were invited to
    openOnLogin = false,
    besideCalendar = true,  -- opens and closes with the game's calendar
    minimapButton = true,
}

local OWN_EVENT_TYPES = {
    PLAYER = true, GUILD_EVENT = true, GUILD_ANNOUNCEMENT = true, COMMUNITY_EVENT = true,
}

local DEFAULT_ICON = "Interface\\Calendar\\UI-Calendar-Event-Other"
local WOWHEAD_LOCALE = {
    deDE = "de/", esES = "es/", esMX = "mx/", frFR = "fr/", itIT = "it/",
    koKR = "ko/", ptBR = "pt/", ruRU = "ru/", zhCN = "cn/", zhTW = "tw/",
}

local ROW_H, HEADER_H = 32, 24

local settings
local running = false
local window, optionsWindow
local minimapIcon, MinimapIcon
local refreshQueued = false

local events = CreateFrame("Frame")
local Refresh

-- ── Reading the calendar ────────────────────────────────────────────────────

-- Server time as a number. time() reads the table as local time, but it is only
-- ever compared with other figures made the same way.
local function Stamp(t)
    return time({ year = t.year, month = t.month, day = t.monthDay, hour = t.hour or 0, min = t.minute or 0 })
end

-- The art for a day in the middle of a holiday is only a thin strip; the first
-- day's has the emblem. A first day that cannot be read keeps the strip.
local function FirstDayIcon(entry, toCurrentMonth, now)
    local first = entry.startTime
    local offset = toCurrentMonth + (first.year - now.year) * 12 + (first.month - now.month)
    for i = 1, C_Calendar.GetNumDayEvents(offset, first.monthDay) do
        local other = C_Calendar.GetDayEvent(offset, first.monthDay, i)
        if other and other.title == entry.title and other.iconTexture then return other.iconTexture end
    end
end

local function ReadEntry(offset, day, index, toCurrentMonth, now)
    local entry = C_Calendar.GetDayEvent(offset, day, index)
    local kind = entry.calendarType
    local isHoliday = kind == "HOLIDAY"
    if not isHoliday and not (settings.showOwn and OWN_EVENT_TYPES[kind]) then return nil end
    if type(entry.title) ~= "string" or entry.title == "" then return nil end

    local start = Stamp(entry.startTime)
    local finish = entry.endTime and Stamp(entry.endTime) or start
    local icon = entry.iconTexture
    if isHoliday and (entry.sequenceType == "ONGOING" or entry.sequenceType == "END") then
        local ok, firstIcon = pcall(FirstDayIcon, entry, toCurrentMonth, now)
        if ok and firstIcon then icon = firstIcon end
    end
    local description
    if isHoliday and C_Calendar.GetHolidayInfo then
        local holiday = C_Calendar.GetHolidayInfo(offset, day, index)
        description = holiday and holiday.description
    end
    return {
        key = entry.title .. "|" .. start,
        title = entry.title,
        icon = icon,
        start = start,
        finish = finish,
        startTime = entry.startTime,
        endTime = entry.endTime or entry.startTime,
        description = description,
        eventID = isHoliday and entry.eventID or nil,
    }
end

-- Only when it differs: setting the month makes the calendar send its update
-- event, which comes back here.
local function SetCurrentMonth(now)
    if CalendarFrame and CalendarFrame:IsShown() then return end
    local ok, shown = pcall(C_Calendar.GetMonthInfo, 0)
    if ok and type(shown) == "table" and shown.month == now.month and shown.year == now.year then return end
    if C_Calendar.SetAbsMonth then pcall(C_Calendar.SetAbsMonth, now.month, now.year) end
end

-- What the last read found, for /oxevents debug.
local lastRead = {}

-- A holiday is listed on every day it runs, so the first sighting counts and
-- the rest are the same one. Returns what is on today and what comes after.
local function ReadCalendar()
    local today, upcoming = {}, {}
    if not (C_Calendar and C_Calendar.GetDayEvent and C_Calendar.GetNumDayEvents and C_Calendar.GetMonthInfo
        and C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime) then
        return today, upcoming
    end
    local okNow, now = pcall(C_DateAndTime.GetCurrentCalendarTime)
    if not okNow or type(now) ~= "table" then return today, upcoming end
    SetCurrentMonth(now)
    local okShown, shown = pcall(C_Calendar.GetMonthInfo, 0)
    if not okShown or type(shown) ~= "table" then return today, upcoming end

    wipe(lastRead)
    lastRead.now, lastRead.shown, lastRead.entries = now, shown, 0

    local nowStamp = Stamp(now)
    local noon = time({ year = now.year, month = now.month, day = now.monthDay, hour = 12 })
    local tomorrow = noon + 12 * 3600
    local toCurrentMonth = (now.year - shown.year) * 12 + (now.month - shown.month)
    local seen = {}

    for i = 0, tonumber(settings.daysAhead) or DEFAULTS.daysAhead do
        local d = date("*t", noon + i * 86400)
        local offset = toCurrentMonth + (d.year - now.year) * 12 + (d.month - now.month)
        local okCount, count = pcall(C_Calendar.GetNumDayEvents, offset, d.day)
        if okCount and type(count) == "number" then
            lastRead.entries = lastRead.entries + count
            for index = 1, count do
                local ok, event = pcall(ReadEntry, offset, d.day, index, toCurrentMonth, now)
                if not ok then lastRead.err = lastRead.err or event end
                if ok and event and not seen[event.key] and event.finish > nowStamp then
                    seen[event.key] = true
                    if event.start < tomorrow then
                        today[#today + 1] = event
                    else
                        upcoming[#upcoming + 1] = event
                    end
                end
            end
        end
    end

    table.sort(today, function(a, b)
        if a.finish ~= b.finish then return a.finish < b.finish end
        return a.title < b.title
    end)
    table.sort(upcoming, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        return a.title < b.title
    end)
    return today, upcoming, nowStamp
end

-- ── Text ────────────────────────────────────────────────────────────────────

local function Duration(seconds)
    seconds = math.max(60, seconds)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    if days > 0 then return (L["%dd %dh"]):format(days, hours) end
    local minutes = math.floor(seconds % 3600 / 60)
    if hours > 0 then return (L["%dh %dm"]):format(hours, minutes) end
    return (L["%dm"]):format(minutes)
end

local function DateText(t)
    local month = CALENDAR_FULLDATE_MONTH_NAMES and CALENDAR_FULLDATE_MONTH_NAMES[t.month]
    local clock = ("%02d:%02d"):format(t.hour or 0, t.minute or 0)
    return ("%d %s, %s"):format(t.monthDay, OxedHub.T(month) or t.month, clock)
end

local function WhenText(event, nowStamp)
    if event.start > nowStamp then
        return (L["Starts in %s"]):format(Duration(event.start - nowStamp))
    end
    return (L["Ends in %s"]):format(Duration(event.finish - nowStamp))
end

-- ── Wowhead link ────────────────────────────────────────────────────────────

local function ShowLink(eventID)
    StaticPopupDialogs.OXEDHUB_EVENT_LINK = StaticPopupDialogs.OXEDHUB_EVENT_LINK or {
        text = L["Copy with Ctrl+C:"],
        button1 = CLOSE or L["Close"],
        hasEditBox = true,
        editBoxWidth = 320,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    local locale = WOWHEAD_LOCALE[GetLocale()] or ""
    StaticPopup_Show("OXEDHUB_EVENT_LINK", nil, nil, ("https://www.wowhead.com/%sevent=%d"):format(locale, eventID))
end

-- ── The window ──────────────────────────────────────────────────────────────

local function RowOnEnter(self)
    local event = self.event
    if not event then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(event.title, 1, 0.82, 0)
    GameTooltip:AddLine(DateText(event.startTime) .. "  >  " .. DateText(event.endTime), 1, 1, 1)
    if event.description then GameTooltip:AddLine(event.description, 0.85, 0.85, 0.85, true) end
    if event.eventID then GameTooltip:AddLine(L["Click for the Wowhead link."], 0.4, 1, 0.4) end
    GameTooltip:Show()
end

local function RowOnClick(self)
    if self.event and self.event.eventID then ShowLink(self.event.eventID) end
end

local function GetRow(i)
    local row = window.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, window.content)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.when:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 0)
    row.when:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.when:SetJustifyH("LEFT")
    row.when:SetWordWrap(false)
    row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.header:SetPoint("LEFT", row, "LEFT", 4, 0)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", RowOnClick)
    window.rows[i] = row
    return row
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    local today, upcoming, nowStamp = ReadCalendar()
    local index, y = 0, 0

    local function Place(height)
        index = index + 1
        local row = GetRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -y)
        row:SetHeight(height)
        row:Show()
        y = y + height
        return row
    end

    local function Section(label, list)
        if #list == 0 then return end
        local head = Place(HEADER_H)
        head.event = nil
        head:EnableMouse(false)
        head.icon:Hide()
        head.title:Hide()
        head.when:Hide()
        head.header:SetText(label)
        head.header:Show()
        for _, event in ipairs(list) do
            local row = Place(ROW_H)
            row.event = event
            row:EnableMouse(true)
            row.header:Hide()
            row.icon:SetTexture(event.icon or DEFAULT_ICON)
            -- Holiday art fills only part of its file, as in the game's calendar.
            local edge = (event.eventID and event.icon) and 0.7109375 or 1
            row.icon:SetTexCoord(0, edge, 0, edge)
            row.icon:Show()
            row.title:SetText(event.title)
            row.title:Show()
            row.when:SetText(WhenText(event, nowStamp))
            row.when:Show()
        end
    end

    Section(L["Today"], today)
    Section(L["Upcoming"], upcoming)

    for i = index + 1, #window.rows do window.rows[i]:Hide() end
    window.content:SetHeight(math.max(1, y))
    window.empty:SetShown(index == 0)
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function()
        refreshQueued = false
        Refresh()
    end)
end

events:SetScript("OnEvent", QueueRefresh)

local function PlaceSaved(f)
    f:ClearAllPoints()
    if settings.left and settings.top then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.left, settings.top)
    else
        f:SetPoint("CENTER")
    end
end

local function BuildWindow()
    if window then return end
    local f = CreateFrame("Frame", "OxedHubGameEventsWindow", UIParent, "BackdropTemplate")
    f:SetSize(340, 420)
    PlaceSaved(f)
    f:SetFrameStrata("MEDIUM")   -- under the game's popup, which holds the link
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    -- Beside the calendar it stays where it is: its own place is for when it is alone.
    f:SetScript("OnDragStart", function(self)
        if not self.docked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        if self.docked then return end
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        settings.left, settings.top = self:GetLeft(), self:GetTop()
    end)
    f:Hide()

    -- The same frame as Currencies.
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(f, OxedHub.T("Game Events"), 0.96)
    else
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.1, 0.095, 0.085, 0.96)
    end

    local okClose, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if okClose and close then
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
        close:SetScript("OnClick", function() f:Hide() end)
    end

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -34)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.35)

    tinsert(UISpecialFrames, "OxedHubGameEventsWindow")   -- Escape closes it

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -40)
    scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(width) end)
    -- The addon's own bar, which also gives the wheel.
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    end
    f.content = content
    f.rows = {}

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(280)
    f.empty:SetText(L["Nothing on the calendar for these days."])

    -- The calendar only sends its news while someone is listening for it.
    f:SetScript("OnShow", function()
        events:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
        if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
        Refresh()
    end)
    f:SetScript("OnHide", function() events:UnregisterAllEvents() end)
    window = f
end

local function ShowWindow(show)
    if not running then
        print(L["Game Events is switched off. Turn it on in |cffffd100/ohub|r > Modules."])
        return
    end
    BuildWindow()
    if show == nil then show = not window:IsShown() end
    window:SetShown(show)
end

-- ── Beside the game's calendar ──────────────────────────────────────────────
-- Blizzard_Calendar loads the first time it is opened, so it is hooked then.

local DOCK_DOWN = -30   -- level with the calendar's body, below its month tab
local openedForCalendar = false
local calendarHooked = false
local calendarWatch = CreateFrame("Frame")

local function DockToCalendar()
    if not (running and settings.besideCalendar) then return end
    BuildWindow()
    openedForCalendar = not window:IsShown()
    window.docked = true
    window:ClearAllPoints()
    -- On the right, or the left when the screen has no room there.
    local screenRight = UIParent:GetRight() * UIParent:GetEffectiveScale()
    local calendarRight = (CalendarFrame:GetRight() or 0) * CalendarFrame:GetEffectiveScale()
    if calendarRight + window:GetWidth() * window:GetEffectiveScale() <= screenRight then
        window:SetPoint("TOPLEFT", CalendarFrame, "TOPRIGHT", 8, DOCK_DOWN)
    else
        window:SetPoint("TOPRIGHT", CalendarFrame, "TOPLEFT", -8, DOCK_DOWN)
    end
    window:Show()
end

-- A list the player had open already stays open, back in its own place.
local function Undock()
    if not (window and window.docked) then return end
    window.docked = false
    if openedForCalendar then window:Hide() end
    openedForCalendar = false
    PlaceSaved(window)
end

local function HookCalendar()
    if calendarHooked or not CalendarFrame then return end
    calendarHooked = true
    calendarWatch:UnregisterAllEvents()
    CalendarFrame:HookScript("OnShow", DockToCalendar)
    CalendarFrame:HookScript("OnHide", Undock)
    if CalendarFrame:IsShown() then DockToCalendar() end
end

calendarWatch:SetScript("OnEvent", function(_, _, loaded)
    if loaded == "Blizzard_Calendar" then HookCalendar() end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Game Events", 440, 360)
        optionsWindow = w

        local open = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        open:SetSize(170, 24)
        open:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        open:SetText(L["Open the list"])
        open:SetScript("OnClick", function()
            w:Hide()
            ShowWindow(true)
        end)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(open) end
        local cmd = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cmd:SetPoint("LEFT", open, "RIGHT", 10, 0)
        cmd:SetText(L["or type /oxevents"])
        w.cursorY = w.cursorY - 36

        w:AddSlider(settings, "daysAhead", "Days ahead", 7, 60, 1, "%s: %d", function() Refresh() end)
        w:AddCheckbox(settings, "showOwn", "Also list guild events and your invitations", nil, function() Refresh() end)
        w:AddCheckbox(settings, "openOnLogin", "Open the list when you log in")
        w:AddCheckbox(settings, "besideCalendar", "Open the list beside the game's calendar")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        w:AddNote("Everything comes from the game's calendar, so a holiday hidden by its filters is not listed here either. Click a holiday for its Wowhead link.")
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "gameevents", label = L["Game Events"], icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", config = settings,
        hint = L["Click: the list. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ShowWindow() end
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBGAMEEVENTS1 = "/oxevents"
SlashCmdList.OXEDHUBGAMEEVENTS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" or msg == "config" then
        ShowOptions()
    elseif msg == "debug" then
        local today, upcoming = ReadCalendar()
        local now, shown = lastRead.now or {}, lastRead.shown or {}
        print(("Game Events: today %s/%s, calendar on %s/%s, entries %s, listed %d + %d, error: %s"):format(
            tostring(now.month), tostring(now.year), tostring(shown.month), tostring(shown.year),
            tostring(lastRead.entries), #today, #upcoming, tostring(lastRead.err or "none")))
    else
        ShowWindow()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.gameevents
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.gameevents = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "gameevents",
        name     = "Game Events",
        version  = "1.0.0",
        updated  = 20261102.8,
        author   = "Oxed",
        category = "quests",
        keywords = { "calendar", "holiday", "events", "today", "upcoming", "darkmoon", "timewalking", "wowhead" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A list of today's and upcoming game events, with Wowhead links. /oxevents",
        icon     = "Interface\\Icons\\INV_Misc_PocketWatch_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,
        quick = {
            { text = L["Show or hide"], func = function() ShowWindow() end },
        },

        OnEnable = function(_, cfg)
            settings = cfg
            running = true
            HookCalendar()
            if not calendarHooked then calendarWatch:RegisterEvent("ADDON_LOADED") end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            if settings.openOnLogin then
                C_Timer.After(3, function()
                    if running then ShowWindow(true) end
                end)
            end
        end,

        OnDisable = function()
            Undock()
            running = false
            calendarWatch:UnregisterAllEvents()
            if minimapIcon then minimapIcon:Apply(false) end
            if window then window:Hide() end
        end,
    })
end)
