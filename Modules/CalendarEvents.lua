-- ============================================================================
-- Calendar events: the addon dresses up for whatever is on in the game.
--
-- One table below holds every event, its dates and the pieces of art it hangs
-- on the window. Adding next year's holiday is an entry in that table and a
-- folder of textures -- no code anywhere else changes, which is the point of
-- keeping this in its own file.
--
-- The dates are the holiday's own, checked against the game's calendar clock
-- rather than the computer's, so a player whose machine is set to another
-- timezone still sees it on the right day. Checked once at login and again
-- when the window is first built: nothing polls.
--
-- Art lives in Media\Textures\CalendarEvents\<folder>\ and must be saved as
-- full-colour RGBA. A palette PNG loads as a green block in this client.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local Events = {}
OxedHub.CalendarEvents = Events

local ROOT = "Interface\\AddOns\\OxedHub\\Media\\Textures\\CalendarEvents\\"

-- ── The events ──────────────────────────────────────────────────────────────
-- from / to are inclusive. An event that crosses New Year (Winter Veil) is
-- written with the later month first and handled as a wrap below.
--
-- Each piece says where it hangs:
--   target  "window" (the main frame) or "sidebar" (the left column)
--   file    the texture's name inside the event folder
--   w / h   size in pixels
--   point / relPoint / x / y   the usual anchor
--   layer / level              draw layer, for sitting behind the logo

Events.EVENTS = {
    -- No art of its own yet, so Brewfest shows only its dated line. An event
    -- with no pieces is still a valid entry: the caption and the guide link
    -- are worth having on their own, and the folder can be filled in later.
    {
        key    = "brewfest",
        name   = "Brewfest",
        folder = "Brewfest",
        from   = { month = 9,  day = 20 },
        to     = { month = 10, day = 6 },
        guide  = "https://www.wowhead.com/guide/world-events/holidays/brewfest",
        caption = { target = "window", point = "BOTTOM", relPoint = "BOTTOM", x = 100, y = 11 },
        pieces = {
            -- Two corners only, on opposite sides, so the frame is dressed
            -- without the symmetry Hallow's End has.
            { file = "topleft",  target = "content", w = 287, h = 287,
              point = "TOPLEFT",     relPoint = "TOPLEFT",     x = -13, y = 23 },
            { file = "botright", target = "content", w = 223, h = 298,
              point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = 21,  y = -28 },

            -- Horns take the wings' place under the logo. Same slot, same
            -- "behind" flag, so the logo still sits over them.
            { file = "horns", target = "sidebar", w = 240, h = 122,
              point = "BOTTOM", relPoint = "BOTTOM", x = -3, y = 64,
              layer = "ARTWORK", level = 1, behind = true },
        },
    },
    {
        key    = "halloween",
        name   = "Hallow's End",
        folder = "Halloween",
        from   = { month = 10, day = 21 },
        to     = { month = 11, day = 4 },
        guide  = "https://www.wowhead.com/guide/world-events/holidays/hallows-end",
        -- A line along the foot of the window naming the event and its dates,
        -- built from the two above so the caption can never say one thing
        -- while the decoration follows another. Clicking it opens the game's
        -- calendar on the event.
        caption = { target = "window", point = "BOTTOM", relPoint = "BOTTOM", x = 100, y = 11 },
        pieces = {
            -- Pumpkins on the two top corners. Sized to sit on the corner
            -- rather than to float above it: the first pass hung them so far
            -- out that they read as part of the game's background, not as the
            -- window's own trim.
            -- On the content frame, not the window. The window's corners are
            -- out at the very edge of the screen furniture; the corners people
            -- actually look at are the ornate ones of the panel inside it.
            { file = "leftP",  target = "content", w = 78, h = 78,
              point = "CENTER", relPoint = "TOPLEFT",     x = 23,  y = -23 },
            { file = "rightP", target = "content", w = 78, h = 78,
              point = "CENTER", relPoint = "TOPRIGHT",    x = -28, y = -23 },

            -- Cobwebs in the two bottom corners of the same panel.
            { file = "leftbw",  target = "content", w = 104, h = 104,
              point = "BOTTOMLEFT",  relPoint = "BOTTOMLEFT",  x = 2,  y = 2 },
            { file = "rightbw", target = "content", w = 104, h = 104,
              point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -2, y = 2 },

            -- Wings behind the logo at the foot of the sidebar. ARTWORK keeps
            -- them under the logo, which is drawn on the overlay layer.
            { file = "wings", target = "sidebar", w = 252, h = 166,
              point = "BOTTOM", relPoint = "BOTTOM", x = -3, y = 54,
              layer = "ARTWORK", level = 1, behind = true },
        },
    },
}

-- ── Today ───────────────────────────────────────────────────────────────────

-- The game's own date. Falls back to the computer's clock on a client that
-- does not answer, which is close enough to put a pumpkin on a window.
-- A date to pretend it is, for checking a holiday out of season. Saved, so it
-- survives a reload, and reported by /oxdecor so it can never be forgotten
-- about quietly. The real event dates are never edited for this: those ship.
local function FakeDate()
    local settings = OxedHubDB and OxedHubDB.globalSettings
    local fake = settings and settings.calendarFakeDate
    if type(fake) == "table" and fake.month and fake.day then
        return fake.month, fake.day
    end
    return nil
end

local function Today()
    local fakeMonth, fakeDay = FakeDate()
    if fakeMonth then return fakeMonth, fakeDay end

    if C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime then
        local ok, now = pcall(C_DateAndTime.GetCurrentCalendarTime)
        if ok and type(now) == "table" and now.month and now.monthDay then
            return now.month, now.monthDay
        end
    end
    local now = date("*t")
    return now.month, now.day
end

local function InRange(month, day, from, to)
    local afterStart = month > from.month or (month == from.month and day >= from.day)
    local beforeEnd  = month < to.month   or (month == to.month   and day <= to.day)

    -- A range that ends in an earlier month than it starts runs over New Year,
    -- so either half of it counts.
    if from.month > to.month then
        return afterStart or beforeEnd
    end
    return afterStart and beforeEnd
end

function Events:GetActive()
    if not self:IsEnabled() then return nil end

    -- Held for this session only, from /oxdecor <name>: the art has to be
    -- checked in September as well as on the night itself.
    if self.preview then
        for _, event in ipairs(self.EVENTS) do
            if event.key == self.preview then return event end
        end
    end

    local month, day = Today()
    for _, event in ipairs(self.EVENTS) do
        if InRange(month, day, event.from, event.to) then return event end
    end
    return nil
end

-- ── Switched on or off ──────────────────────────────────────────────────────
-- Account-wide: dressing the window up is a look, not a per-character choice.

function Events:IsEnabled()
    local settings = OxedHubDB and OxedHubDB.globalSettings
    if not settings then return true end
    return settings.calendarDecor ~= false
end

function Events:SetEnabled(on)
    if type(OxedHubDB) ~= "table" then return end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    OxedHubDB.globalSettings.calendarDecor = on and true or false
    self:Apply()
end

-- ── Hanging the art ─────────────────────────────────────────────────────────

local pieces = {}   -- textures currently hung, so they can be taken down again
local holders = {}  -- one raised frame per surface, see Holder below

local caption       -- the dated line at the foot of the window

local function Clear()
    for _, texture in ipairs(pieces) do
        texture:Hide()
        texture:SetTexture(nil)
    end
    wipe(pieces)
    if caption then caption:Hide() end
end

-- ── The dated line ──────────────────────────────────────────────────────────

local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
                 "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }

local function DateRangeText(event)
    local from, to = event.from, event.to
    return ("%s:  %s %d - %s %d"):format(
        event.name:upper(),
        MONTHS[from.month] or "?", from.day,
        MONTHS[to.month] or "?", to.day)
end

-- Our window sits on the DIALOG strata, which is above the calendar, so the
-- calendar opened from here came up behind it. Rather than push Blizzard's
-- frame up -- it is shared with everything else and would then sit over other
-- dialogs too -- our own window steps down while the calendar is open and goes
-- back where it was when the calendar closes.
--
-- The raised frames holding the decoration keep the strata they were built
-- with, so they are stepped down as well; otherwise the pumpkins would stay
-- floating over the calendar with the window gone from under them.
local loweredStrata

local function RestoreStrata()
    if not loweredStrata then return end
    local frame = OxedHub.UI and OxedHub.UI.GetMainFrame and OxedHub.UI:GetMainFrame()
    if frame then frame:SetFrameStrata(loweredStrata.window) end
    for holder, strata in pairs(loweredStrata.holders) do
        holder:SetFrameStrata(strata)
    end
    loweredStrata = nil
end

local function LowerForCalendar()
    local frame = OxedHub.UI and OxedHub.UI.GetMainFrame and OxedHub.UI:GetMainFrame()
    if not frame or not frame:IsShown() or loweredStrata then return end

    loweredStrata = { window = frame:GetFrameStrata(), holders = {} }
    frame:SetFrameStrata("MEDIUM")
    for _, holder in pairs(holders) do
        loweredStrata.holders[holder] = holder:GetFrameStrata()
        holder:SetFrameStrata("MEDIUM")
    end

    local calendar = _G.CalendarFrame
    if calendar and not calendar.oxedStrataHooked then
        calendar.oxedStrataHooked = true
        calendar:HookScript("OnHide", RestoreStrata)
    end
end

-- The calendar is a load-on-demand addon, so it may not be in memory yet.
local function OpenCalendar()
    if InCombatLockdown() then
        print("|cff00ff00OxedHub:|r the calendar cannot be opened during combat.")
        return
    end

    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if load then pcall(load, "Blizzard_Calendar") end

    local wasShown = _G.CalendarFrame and _G.CalendarFrame:IsShown()
    if ToggleCalendar then pcall(ToggleCalendar) end

    -- Only step aside when the click opened it; closing it puts us back.
    if wasShown then
        RestoreStrata()
    else
        LowerForCalendar()
    end
end

-- A frame to hang the art on, sitting above the panels.
--
-- A texture drawn straight on the window loses to every panel inside it: those
-- are frames of their own, and a frame always draws over its parent's textures
-- whatever layer they were given. So the art goes on a frame of its own,
-- raised well above the parent's level. It takes no mouse input, so nothing
-- underneath stops being clickable.
local function Holder(parent)
    local holder = holders[parent]
    if holder then return holder end

    holder = CreateFrame("Frame", nil, parent)
    holder:SetAllPoints(parent)
    holder:SetFrameStrata(parent:GetFrameStrata())
    holder:SetFrameLevel((parent:GetFrameLevel() or 0) + 60)
    holder:EnableMouse(false)
    holders[parent] = holder
    return holder
end

local function Surface(target)
    local UI = OxedHub.UI
    if not UI then return nil end
    if target == "sidebar" then
        return UI.GetSidebar and UI:GetSidebar()
    end
    if target == "content" then
        -- The panel with the ornate border, inside the window.
        return (UI.GetContentArea and UI:GetContentArea()) or (UI.GetMainFrame and UI:GetMainFrame())
    end
    return UI.GetMainFrame and UI:GetMainFrame()
end

function Events:Apply()
    Clear()

    local event = self:GetActive()
    if not event then return false end

    local hung = 0
    for _, piece in ipairs(event.pieces) do
        local parent = Surface(piece.target)
        if parent then
            -- "behind" pieces stay on the surface itself, under whatever the
            -- page draws over them -- that is how the wings sit beneath the
            -- logo. Everything else goes on the raised frame.
            local host = piece.behind and parent or Holder(parent)
            local texture = host:CreateTexture(nil, piece.layer or "OVERLAY", nil, piece.level or 6)
            texture:SetTexture(ROOT .. event.folder .. "\\" .. piece.file .. ".png")
            texture:SetSize(piece.w or 128, piece.h or 128)
            texture:SetPoint(piece.point, parent, piece.relPoint or piece.point, piece.x or 0, piece.y or 0)
            texture:Show()
            pieces[#pieces + 1] = texture
            hung = hung + 1
        end
    end

    -- The dated line, on the same raised frame so the page cannot cover it.
    if event.caption then
        local parent = Surface(event.caption.target)
        if parent then
            if not caption then
                caption = CreateFrame("Button", nil, Holder(parent))
                caption:SetSize(320, 16)

                caption.text = caption:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                caption.text:SetAllPoints()
                caption.text:SetJustifyH("CENTER")
                caption.text:SetTextColor(1, 0.82, 0, 0.9)

                -- A tenth larger than the font object gives, kept in the same
                -- typeface: asking for the next font object up would jump the
                -- size by a quarter and look like a heading.
                local file, size, flags = caption.text:GetFont()
                if file and size then
                    caption.text:SetFont(file, size * 1.1, flags)
                end

                caption:SetScript("OnEnter", function(self)
                    self.text:SetTextColor(1, 0.95, 0.6, 1)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText("Open the calendar")
                    GameTooltip:Show()
                end)
                caption:SetScript("OnLeave", function(self)
                    self.text:SetTextColor(1, 0.82, 0, 0.9)
                    GameTooltip:Hide()
                end)
                caption:SetScript("OnClick", OpenCalendar)

                -- The guide link, as an icon beside the dates. It hands over a
                -- box with the address in it rather than opening anything: the
                -- game cannot open a browser, so copying is all there is.
                local link = CreateFrame("Button", nil, caption)
                link:SetSize(16, 16)
                link:SetPoint("LEFT", caption, "RIGHT", 6, 0)
                link:SetNormalTexture("Interface\\Icons\\INV_Scroll_03")
                link:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                link:Hide()

                link:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText("Wowhead guide")
                    GameTooltip:AddLine("Click for the address, ready to copy.", 1, 1, 1)
                    GameTooltip:Show()
                end)
                link:SetScript("OnLeave", function() GameTooltip:Hide() end)
                link:SetScript("OnClick", function(self)
                    if not self.url then return end
                    if OxedHub.ShowCopyURLDialog then
                        OxedHub:ShowCopyURLDialog(self.url, self.title or "Wowhead")
                    end
                end)
                caption.link = link
            end

            caption:SetParent(Holder(parent))
            caption:ClearAllPoints()
            caption:SetPoint(event.caption.point, parent, event.caption.relPoint or event.caption.point,
                event.caption.x or 0, event.caption.y or 0)
            caption.text:SetText(DateRangeText(event))
            -- Sized to the text, so the guide icon sits right after the words
            -- instead of out at the end of a fixed-width button.
            caption:SetWidth(math.max(60, caption.text:GetStringWidth() + 4))

            if caption.link then
                caption.link.url = event.guide
                caption.link.title = event.name .. " on Wowhead"
                caption.link:SetShown(event.guide ~= nil)
            end

            caption:Show()
            hung = hung + 1
        end
    end

    self.activeKey = hung > 0 and event.key or nil
    return hung > 0
end

-- ── When to look ────────────────────────────────────────────────────────────
-- The window is built the first time it is opened, so there is nothing to hang
-- anything on at login. This waits for it rather than polling forever: a few
-- tries after login, and then whenever the window is shown, once.

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function(self, event)
    -- Every loading screen is a chance for the date to have rolled over, so
    -- the event is decided again rather than only at login. Costs two numbers
    -- and a table walk.
    if event == "PLAYER_ENTERING_WORLD" then
        local current = Events:GetActive()
        if (current and current.key) ~= Events.activeKey then Events:Apply() end
        return
    end

    self:UnregisterEvent("PLAYER_LOGIN")

    -- The window is built the first time it is opened, which may be an hour
    -- after login or never. Waiting a fixed number of seconds for it meant the
    -- decoration simply never appeared for anyone who opened the addon later,
    -- so the opening itself is what we listen to.
    if OxedHub.UI and OxedHub.UI.ShowMainWindow then
        hooksecurefunc(OxedHub.UI, "ShowMainWindow", function()
            if Events.activeKey then return end
            -- A frame later: the window finishes building after this returns.
            C_Timer.After(0, function() Events:Apply() end)
        end)
    end

    local tries = 0
    local function Attempt()
        tries = tries + 1
        local frame = OxedHub.UI and OxedHub.UI.GetMainFrame and OxedHub.UI:GetMainFrame()
        if frame then
            Events:Apply()
            -- Rebuilt art survives a window that is closed and reopened, but
            -- the hook costs nothing and covers a frame built later than this.
            if not frame.oxedDecorHooked then
                frame.oxedDecorHooked = true
                frame:HookScript("OnShow", function()
                    if not Events.activeKey then Events:Apply() end
                end)
            end
            return
        end
        if tries < 10 then C_Timer.After(2, Attempt) end
    end

    C_Timer.After(3, Attempt)
end)

SLASH_OXEDHUBDECOR1 = "/oxdecor"
SlashCmdList["OXEDHUBDECOR"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if msg == "off" then
        Events.preview = nil
        Events:SetEnabled(false)
        print("|cff00ff00OxedHub:|r seasonal decoration off.")
        return
    end

    -- /oxdecor today 10 25   -- pretend, so the date logic itself is tested
    -- /oxdecor today off     -- back to the game's own date
    local todayArgs = msg:match("^today%s*(.*)$")
    if todayArgs then
        OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}

        if todayArgs == "off" or todayArgs == "" then
            OxedHubDB.globalSettings.calendarFakeDate = nil
            Events:Apply()
            print("|cff00ff00OxedHub:|r back to the game's own date.")
            return
        end

        local month, day = todayArgs:match("^(%d+)%s+(%d+)$")
        month, day = tonumber(month), tonumber(day)
        if not month or not day or month < 1 or month > 12 or day < 1 or day > 31 then
            print("|cff00ff00OxedHub:|r use /oxdecor today <month> <day>, for example /oxdecor today 10 25.")
            return
        end

        OxedHubDB.globalSettings.calendarFakeDate = { month = month, day = day }
        Events.preview = nil
        Events:Apply()
        local event = Events:GetActive()
        print(("|cff00ff00OxedHub:|r pretending it is %s %d -- %s."):format(
            MONTHS[month] or "?", day,
            event and event.name or "nothing running that day"))
        return
    end

    if msg ~= "" and msg ~= "on" then
        for _, event in ipairs(Events.EVENTS) do
            if event.key == msg then
                Events.preview = msg
                if not Events:IsEnabled() then Events:SetEnabled(true) end
                local hung = Events:Apply()
                print(("|cff00ff00OxedHub:|r showing %s%s. Type /oxdecor on to go back to the calendar."):format(
                    event.name, hung and "" or " -- nothing appeared, open the OxedHub window first"))
                return
            end
        end

        local names = {}
        for _, event in ipairs(Events.EVENTS) do names[#names + 1] = event.key end
        print(("|cff00ff00OxedHub:|r no such event. Try: %s"):format(table.concat(names, ", ")))
        return
    end

    if msg == "on" then
        Events.preview = nil
        Events:SetEnabled(true)
        local event = Events:GetActive()
        if event then
            print(("|cff00ff00OxedHub:|r seasonal decoration on -- %s."):format(event.name))
        else
            print("|cff00ff00OxedHub:|r seasonal decoration on. Nothing is running today.")
        end
        return
    end

    -- Plain /oxdecor: say what the addon believes, so the date it is reading
    -- and the decision it made from it can both be checked without waiting for
    -- October.
    local month, day = Today()
    local fakeMonth = FakeDate()
    print("|cff00ff00OxedHub seasonal decoration|r")
    if fakeMonth then
        print(("  |cffffd100pretending it is %s %d|r -- /oxdecor today off to stop"):format(
            MONTHS[month] or "?", day))
    else
        print(("  the game's date: %s %d"):format(MONTHS[month] or "?", day))
    end
    print(("  switched %s"):format(Events:IsEnabled() and "on" or "|cffff5555off|r"))

    local byDate
    for _, event in ipairs(Events.EVENTS) do
        local active = InRange(month, day, event.from, event.to)
        if active then byDate = event end
        print(("  %s  %s %d - %s %d   %s"):format(
            event.name,
            MONTHS[event.from.month] or "?", event.from.day,
            MONTHS[event.to.month] or "?", event.to.day,
            active and "|cff40ff40running today|r" or "|cff808080not today|r"))
    end

    if Events.preview then
        print(("  |cffffd100showing %s by hand|r -- /oxdecor on goes back to the calendar."):format(Events.preview))
    elseif byDate then
        print("  the window is dressed for it.")
    else
        print("  nothing to show today. Try /oxdecor halloween to see it anyway.")
    end
end
