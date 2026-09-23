-- ============================================================================
-- Performance window
-- The readable side of Core\Profiler.lua: what in OxedHub has cost the most
-- time, and what was running during each lag spike.
--
-- Two tabs. Top lists every named part of OxedHub by the time it has taken,
-- sortable by total, slowest single call, number of calls or average. Spikes
-- lists each long frame, newest first; hovering one shows everything that ran
-- in it, nested the way it ran.
--
-- Copy report turns all of it into text a player can paste to the author.
-- Opened with /oxprofile, or from the Performance button in the debug log.
-- ============================================================================

local addonName, OxedHub = ...

local Performance = {}
OxedHub.Performance = Performance

local window, reportWindow
local ShowMini, HideMini   -- the small on-screen version, defined further down
local ROW_HEIGHT = 18
local REFRESH_SECONDS = 1

local function Profiler() return OxedHub.Profiler end

local function Button(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

-- Colour for a time: fine, worth a look, a problem.
local function MsColour(ms)
    if ms >= 16 then return "|cffff5555" end
    if ms >= 4 then return "|cffffd100" end
    return "|cffffffff"
end

-- ── Rows ────────────────────────────────────────────────────────────────────

local function GetRow(index)
    local row = window.rows[index]
    if row then return row end

    row = CreateFrame("Button", nil, window.content)
    row:SetHeight(ROW_HEIGHT)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.06)
    highlight:Hide()

    row.cols = {}
    for i = 1, 5 do
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH(i == 5 and "LEFT" or "RIGHT")
        fs:SetWordWrap(false)
        row.cols[i] = fs
    end

    row:SetScript("OnEnter", function(self)
        highlight:Show()
        if self.tooltip then self.tooltip(self) end
    end)
    row:SetScript("OnLeave", function()
        highlight:Hide()
        GameTooltip:Hide()
    end)

    window.rows[index] = row
    return row
end

-- Column layout shared by the header and every row: four numbers, then a name
-- taking the rest of the width.
local WIDTHS = { 80, 70, 70, 80 }
local function LayoutColumns(parentRow, cols)
    local x = 0
    for i = 1, 4 do
        cols[i]:ClearAllPoints()
        cols[i]:SetPoint("LEFT", parentRow, "LEFT", x, 0)
        cols[i]:SetWidth(WIDTHS[i])
        x = x + WIDTHS[i] + 6
    end
    cols[5]:ClearAllPoints()
    cols[5]:SetPoint("LEFT", parentRow, "LEFT", x + 6, 0)
    cols[5]:SetPoint("RIGHT", parentRow, "RIGHT", -4, 0)
end

local function PlaceRows(count)
    for index = count + 1, #window.rows do window.rows[index]:Hide() end
    window.content:SetHeight(math.max(1, count * ROW_HEIGHT))
    window.content:SetWidth(window.scroll:GetWidth())
end

-- ── Tab: Top ────────────────────────────────────────────────────────────────

local SORTS = {
    { key = "total", header = "Total ms" },
    { key = "max",   header = "Slowest" },
    { key = "count", header = "Calls" },
    { key = "avg",   header = "Average" },
}

local function DrawTop()
    local list = Profiler():GetTop(window.sortKey)
    for index, entry in ipairs(list) do
        local row = GetRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
        LayoutColumns(row, row.cols)
        row.cols[1]:SetText(("%s%.1f|r"):format(MsColour(entry.total / 20), entry.total))
        row.cols[2]:SetText(("%s%.2f|r"):format(MsColour(entry.max), entry.max))
        row.cols[3]:SetText(tostring(entry.count))
        row.cols[4]:SetText(("%s%.3f|r"):format(MsColour(entry.avg), entry.avg))
        row.cols[5]:SetText(entry.label)
        row.tooltip = function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetText(entry.label, 1, 1, 1, 1, true)
            GameTooltip:AddLine(("%.1f ms in %d calls, %.3f ms each on average")
                :format(entry.total, entry.count, entry.avg), 0.9, 0.9, 0.9)
            GameTooltip:AddLine(("Slowest %.2f ms%s"):format(entry.max,
                entry.maxAt and (" at " .. date("%H:%M:%S", entry.maxAt)) or ""), 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end
        row:Show()
    end
    PlaceRows(#list)
    window.empty:SetShown(#list == 0)
end

-- ── Tab: Spikes ─────────────────────────────────────────────────────────────

local function SpikeTooltip(spike)
    return function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(("Frame %.0f ms at %s"):format(spike.frameMs, date("%H:%M:%S", spike.at)), 1, 1, 1)
        local share = spike.frameMs > 0 and spike.oxedMs / spike.frameMs * 100 or 0
        GameTooltip:AddLine(("OxedHub measured %.1f ms (%.0f%% of the frame)"):format(spike.oxedMs, share), 0.9, 0.9, 0.9)
        if spike.addonMs then
            GameTooltip:AddLine(("The game counts %.1f ms for OxedHub"):format(spike.addonMs), 0.9, 0.9, 0.9)
        end
        if share < 25 and spike.reason == "hitch" then
            GameTooltip:AddLine("Most of this frame was not OxedHub.", 0.4, 1, 0.4, true)
        end
        if spike.cause then
            GameTooltip:AddLine("Cause: " .. spike.cause, 1, 0.82, 0, true)
        end
        if spike.others and #spike.others > 0 then
            local parts = {}
            for _, other in ipairs(spike.others) do
                parts[#parts + 1] = ("%s %.1f ms"):format(other.name, other.ms)
            end
            GameTooltip:AddLine("Busiest addons: " .. table.concat(parts, ", "), 0.9, 0.9, 0.9, true)
        end
        if spike.events and #spike.events > 0 then
            local parts = {}
            for _, event in ipairs(spike.events) do
                parts[#parts + 1] = event.n > 1 and ("%s x%d"):format(event.name, event.n) or event.name
            end
            GameTooltip:AddLine("Events: " .. table.concat(parts, ", "), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(("%s%s, %.0f KB allocated%s"):format(spike.where,
            spike.combat and ", in combat" or "", spike.allocKB or 0,
            spike.overflow > 0 and (", %d more calls not listed"):format(spike.overflow) or ""),
            0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(" ")

        local shown = 0
        for _, entry in ipairs(spike.entries) do
            if entry.ms >= 0.1 and shown < 30 then
                shown = shown + 1
                GameTooltip:AddDoubleLine(string.rep("   ", entry.depth) .. entry.label,
                    ("%s%.2f ms|r"):format(MsColour(entry.ms), entry.ms), 1, 1, 1, 1, 1, 1)
            end
        end
        if shown == 0 then
            GameTooltip:AddLine("Nothing from OxedHub took measurable time in this frame.", 0.4, 1, 0.4, true)
        end
        GameTooltip:Show()
    end
end

local function DrawSpikes()
    local spikes = Profiler():GetSpikes()
    local count = 0
    for i = #spikes, 1, -1 do
        local spike = spikes[i]
        count = count + 1
        local row = GetRow(count)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -(count - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -(count - 1) * ROW_HEIGHT)
        LayoutColumns(row, row.cols)

        local share = spike.frameMs > 0 and spike.oxedMs / spike.frameMs * 100 or 0
        local culprit = Profiler():SpikeCulprit(spike)
        row.cols[1]:SetText(date("%H:%M:%S", spike.at))
        row.cols[2]:SetText(("%s%.0f|r"):format(MsColour(spike.frameMs / 3), spike.frameMs))
        row.cols[3]:SetText(("%s%.1f|r"):format(MsColour(spike.oxedMs), spike.oxedMs))
        row.cols[4]:SetText(("%.0f%%"):format(share))
        row.cols[5]:SetText(culprit
            and ("%s  |cff9d9d9d%.1f ms|r"):format(culprit.label, culprit.ms)
            or "|cff9d9d9dnothing measured from OxedHub|r")
        row.tooltip = SpikeTooltip(spike)
        row:Show()
    end
    PlaceRows(count)
    window.empty:SetShown(count == 0)
end

-- ── Header, status and refresh ──────────────────────────────────────────────

local function SetHeader()
    local h = window.header
    if window.tab == "top" then
        for i, sort in ipairs(SORTS) do
            h.cols[i]:SetText((window.sortKey == sort.key and "|cffffd100" or "|cffaaaaaa") .. sort.header .. "|r")
        end
        h.cols[5]:SetText("|cffaaaaaaWhat  (click a column title to sort)|r")
    else
        h.cols[1]:SetText("|cffaaaaaaTime|r")
        h.cols[2]:SetText("|cffaaaaaaFrame ms|r")
        h.cols[3]:SetText("|cffaaaaaaOxedHub ms|r")
        h.cols[4]:SetText("|cffaaaaaaShare|r")
        h.cols[5]:SetText("|cffaaaaaaSlowest part  (hover for everything that ran)|r")
    end
end

local function Refresh()
    if not (window and window:IsShown()) then return end
    local P = Profiler()
    local s = P:GetSession()
    local length = s.startedAt and ((s.stoppedAt or time()) - s.startedAt) or 0

    local view = P:GetView()
    local state
    if view then
        state = ("|cffffd100Saved %s|r"):format(view.endedAt and date("%d %b %H:%M", view.endedAt) or "")
    else
        state = P:IsActive() and "|cff40ff40Recording|r" or "|cffff5555Stopped|r"
    end
    window.status:SetText(("%s   %d s   %d frames   %d hitches   normal frame %.1f ms")
        :format(state, length, s.frames, s.hitches, P:GetBaseline()))

    -- Which recording is on screen: the live one, or one saved at a reload.
    local history = P:GetHistory()
    if view then
        window.session:SetText(("Saved %d of %d"):format(P.viewIndex, #history))
    else
        window.session:SetText(#history > 0 and ("Live  (%d saved)"):format(#history) or "Live")
    end
    window.deleteSaved:SetShown(view ~= nil)
    window.startStop:SetText(P:IsActive() and "Stop" or "Start")
    window.fromLogin:SetChecked(P:GetFromLogin())

    for _, tabButton in ipairs(window.tabs) do
        if tabButton.key == window.tab then tabButton:LockHighlight() else tabButton:UnlockHighlight() end
    end

    SetHeader()
    if window.tab == "spikes" then DrawSpikes() else DrawTop() end
end

-- ── The report text ─────────────────────────────────────────────────────────

local function ShowReport()
    if not reportWindow then
        reportWindow = CreateFrame("Frame", "OxedHubPerformanceReport", UIParent, "BasicFrameTemplateWithInset")
        reportWindow:SetSize(700, 480)
        reportWindow:SetPoint("CENTER")
        reportWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        reportWindow:SetFrameLevel(230)
        reportWindow:SetToplevel(true)
        reportWindow:SetClampedToScreen(true)
        reportWindow:EnableMouse(true)
        reportWindow:SetMovable(true)
        reportWindow:RegisterForDrag("LeftButton")
        reportWindow:SetScript("OnDragStart", reportWindow.StartMoving)
        reportWindow:SetScript("OnDragStop", reportWindow.StopMovingOrSizing)

        local title = reportWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("CENTER", reportWindow.TitleBg, "CENTER", 0, 0)
        title:SetText("OxedHub performance report")

        local scroll = CreateFrame("ScrollFrame", nil, reportWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", reportWindow, "TOPLEFT", 12, -32)
        scroll:SetPoint("BOTTOMRIGHT", reportWindow, "BOTTOMRIGHT", -32, 36)

        local box = CreateFrame("EditBox", nil, scroll)
        box:SetMultiLine(true)
        box:SetMaxLetters(0)
        box:SetAutoFocus(false)
        box:SetFontObject("ChatFontNormal")
        box:SetWidth(640)
        -- A multi-line box inside a scroll frame starts with no height, and a box
        -- with no height shows nothing and cannot be clicked -- which looked like
        -- the button doing nothing. It is given a real height up front.
        box:SetHeight(400)
        box:SetScript("OnEscapePressed", function() reportWindow:Hide() end)
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(self.original or "") end
        end)
        -- Clicking into the text selects all of it again, so a stray click
        -- that dropped the selection is fixed by the next one.
        box:SetScript("OnMouseUp", function(self)
            self:SetFocus()
            self:HighlightText()
        end)
        scroll:SetScrollChild(box)
        reportWindow.box = box

        -- The game gives addons no way to put text on the clipboard, so the
        -- player copies it. The instruction sits at the top, where it is read.
        local steps = reportWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        steps:SetPoint("TOPLEFT", reportWindow, "TOPLEFT", 16, -30)
        steps:SetPoint("TOPRIGHT", reportWindow, "TOPRIGHT", -140, -30)
        steps:SetJustifyH("LEFT")
        steps:SetText("The text below is selected. Press |cffffffffCtrl+C|r to copy it, then paste with |cffffffffCtrl+V|r.")
        scroll:ClearAllPoints()
        scroll:SetPoint("TOPLEFT", reportWindow, "TOPLEFT", 12, -54)
        scroll:SetPoint("BOTTOMRIGHT", reportWindow, "BOTTOMRIGHT", -32, 36)

        local selectAll = Button(reportWindow, "Select all", 110, function()
            reportWindow.box:SetFocus()
            reportWindow.box:HighlightText()
        end)
        selectAll:SetPoint("TOPRIGHT", reportWindow, "TOPRIGHT", -12, -26)

        local hint = reportWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOMLEFT", reportWindow, "BOTTOMLEFT", 16, 14)
        hint:SetText("Lost the selection? Click the text or Select all. Escape closes.")
        tinsert(UISpecialFrames, "OxedHubPerformanceReport")
    end

    -- A report that fails to build still opens, with the error in it: the
    -- window silently not appearing was indistinguishable from a dead button.
    local ok, text = pcall(Profiler().BuildReport, Profiler())
    if not ok then
        text = "The report could not be built:\n" .. tostring(text)
    end

    local box = reportWindow.box
    box.original = text
    box:SetText(text)
    local lines = select(2, text:gsub("\n", "\n")) + 1
    box:SetHeight(math.max(400, lines * 15))

    reportWindow:Show()
    reportWindow:Raise()
    box:SetFocus()
    box:HighlightText()
end

-- ── The window ──────────────────────────────────────────────────────────────

local function Build()
    if window then return window end
    local P = Profiler()

    window = CreateFrame("Frame", "OxedHubPerformanceWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(760, 520)
    window:SetPoint("CENTER")
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetFrameLevel(210)
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window.rows, window.tab, window.sortKey = {}, "top", "total"

    local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("CENTER", window.TitleBg, "CENTER", 0, 0)
    title:SetText("OxedHub Performance")

    window.startStop = Button(window, "Start", 80, function()
        if P:IsActive() then P:Stop() else P:Start() end
        Refresh()
    end)
    window.startStop:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -30)

    local reset = Button(window, "Reset", 70, function() P:Reset(); Refresh() end)
    reset:SetPoint("LEFT", window.startStop, "RIGHT", 6, 0)

    local copy = Button(window, "Copy report", 100, ShowReport)
    copy:SetPoint("LEFT", reset, "RIGHT", 6, 0)

    -- Down to the small version that stays on screen while playing.
    local minimise = Button(window, "Minimise", 80, function()
        window:Hide()
        ShowMini()
    end)
    minimise:SetPoint("TOPRIGHT", window, "TOPRIGHT", -14, -30)

    window.fromLogin = CreateFrame("CheckButton", nil, window, "UICheckButtonTemplate")
    window.fromLogin:SetSize(22, 22)
    window.fromLogin:SetPoint("LEFT", copy, "RIGHT", 12, 0)
    window.fromLogin.text:SetFontObject("GameFontHighlightSmall")
    window.fromLogin.text:SetText("Record from login")
    window.fromLogin:SetScript("OnClick", function(self)
        P:SetFromLogin(self:GetChecked())
    end)
    window.fromLogin:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Record from login")
        GameTooltip:AddLine("Starts recording as soon as you log in or /reload, so timers and repeating effects created at login are named too. Costs a little while it runs: switch it off when you are done.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    window.fromLogin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.status:SetPoint("TOPLEFT", window.startStop, "BOTTOMLEFT", 2, -8)

    -- Switches between the live recording and the ones saved when the player
    -- reloaded or logged out. Each click moves one along and wraps back to live.
    window.session = Button(window, "Live", 130, function()
        local count = #P:GetHistory()
        local nextIndex = (P.viewIndex or 0) + 1
        if nextIndex > count then nextIndex = nil end
        P:SetView(nextIndex)
        window.scroll:SetVerticalScroll(0)
        Refresh()
    end)
    window.session:SetPoint("TOPRIGHT", window, "TOPRIGHT", -14, -56)
    window.session:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Recordings")
        GameTooltip:AddLine("Each reload or logout keeps the recording, so nothing is lost when you reload to test something. The last ten are kept. Click to step through them; Copy report works on whichever is shown.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    window.session:SetScript("OnLeave", function() GameTooltip:Hide() end)

    window.deleteSaved = Button(window, "Delete", 70, function()
        if P.viewIndex then
            P:DeleteSaved(P.viewIndex)
            Refresh()
        end
    end)
    window.deleteSaved:SetPoint("RIGHT", window.session, "LEFT", -4, 0)

    window.tabs = {}
    local previous
    for _, tabInfo in ipairs({ { key = "top", label = "Top" }, { key = "spikes", label = "Spikes" } }) do
        local tabButton = Button(window, tabInfo.label, 80, function()
            window.tab = tabInfo.key
            window.scroll:SetVerticalScroll(0)
            Refresh()
        end)
        tabButton.key = tabInfo.key
        if previous then
            tabButton:SetPoint("LEFT", previous, "RIGHT", 4, 0)
        else
            -- Left of the Minimise button, with both tabs clear of it.
            tabButton:SetPoint("TOPRIGHT", window, "TOPRIGHT", -184, -30)
        end
        previous = tabButton
        window.tabs[#window.tabs + 1] = tabButton
    end

    -- Column titles. On the Top tab the four number columns sort the list.
    local header = CreateFrame("Frame", nil, window)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -84)
    header:SetPoint("TOPRIGHT", window, "TOPRIGHT", -34, -84)
    header.cols = {}
    for i = 1, 5 do
        local hit = CreateFrame("Button", nil, header)
        hit:SetHeight(ROW_HEIGHT)
        local fs = hit:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH(i == 5 and "LEFT" or "RIGHT")
        header.cols[i] = fs
        if i <= 4 then
            hit:SetScript("OnClick", function()
                if window.tab == "top" then
                    window.sortKey = SORTS[i].key
                    Refresh()
                end
            end)
        end
        hit.fs = fs
        header["hit" .. i] = hit
    end
    -- Lay the clickable areas out on the same columns as the rows.
    local x = 0
    for i = 1, 4 do
        header["hit" .. i]:SetPoint("LEFT", header, "LEFT", x, 0)
        header["hit" .. i]:SetWidth(WIDTHS[i])
        x = x + WIDTHS[i] + 6
    end
    header.hit5:SetPoint("LEFT", header, "LEFT", x + 6, 0)
    header.hit5:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    window.header = header

    local scroll = CreateFrame("ScrollFrame", "OxedHubPerformanceScroll", window, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -34, 36)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(700, 1)
    scroll:SetScrollChild(content)
    window.scroll, window.content = scroll, content

    window.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    window.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -8)
    window.empty:SetWidth(680)
    window.empty:SetJustifyH("LEFT")
    window.empty:SetText("Nothing recorded yet. Press Start, then play the way that lags -- the same fight, the same rotation -- and come back here.")

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 14)
    hint:SetText("Times are OxedHub's own work. A spike where OxedHub's share is small came from the game or another addon.")

    -- The numbers keep moving while recording; once a second is plenty to read.
    local elapsed = 0
    window:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < REFRESH_SECONDS then return end
        elapsed = 0
        Refresh()
    end)

    tinsert(UISpecialFrames, "OxedHubPerformanceWindow")
    window:Hide()
    return window
end

-- ── The mini version ────────────────────────────────────────────────────────
-- A small readout that stays on screen while playing: a round button, and two
-- bars beside it with the live numbers. Click the button for the full window,
-- right-click it to start or stop recording, drag anywhere to move it.
--
--   top bar     OxedHub's cost right now (ms per second) and your FPS
--   bottom bar  spikes this session, and the last one with OxedHub's share

local mini

local function MiniSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.profiler = OxedHubDB.profiler or {}
    return OxedHubDB.profiler
end

local function Bar(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(width, height)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bar:SetBackdropColor(0, 0, 0, 0.75)
    bar:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.9)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("LEFT", bar, "LEFT", 16, 0)
    bar.text:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)
    return bar
end

local function UpdateMini()
    if not (mini and mini:IsShown()) then return end
    local P = Profiler()
    -- The readout is always about now, even while the big window is showing a
    -- saved recording.
    local viewing = P.viewIndex
    P.viewIndex = nil
    local live = P:GetLive()
    local s = P:GetSession()
    local fps = GetFramerate and GetFramerate() or 0

    mini.dot:SetVertexColor(P:IsActive() and 0.25 or 1, P:IsActive() and 1 or 0.3, 0.25)

    if P:IsActive() then
        mini.top.text:SetText(("OxedHub %s%.2f ms/s|r   peak %s%.1f ms|r   %d fps")
            :format(MsColour(live.msPerSecond), live.msPerSecond,
                MsColour(live.peakFrameMs), live.peakFrameMs, fps + 0.5))
    else
        mini.top.text:SetText(("|cffff5555Stopped|r   %d fps   right-click to record"):format(fps + 0.5))
    end

    local spikes = P:GetSpikes()
    P.viewIndex = viewing   -- hand the big window its saved recording back
    local last = spikes[#spikes]
    if last then
        local share = last.frameMs > 0 and last.oxedMs / last.frameMs * 100 or 0
        mini.bottom.text:SetText(("%d spikes   last %s%.0f ms|r at %s, OxedHub %s%.0f%%|r")
            :format(s.hitches, MsColour(last.frameMs / 3), last.frameMs, date("%H:%M:%S", last.at),
                share >= 25 and "|cffff5555" or "|cff40ff40", share))
    else
        mini.bottom.text:SetText(("%d spikes   none recorded yet"):format(s.hitches))
    end
end

local function SaveMiniPosition()
    local point, _, relPoint, x, y = mini:GetPoint(1)
    local saved = MiniSettings()
    saved.miniPoint, saved.miniRelPoint, saved.miniX, saved.miniY = point, relPoint, x, y
end

local function BuildMini()
    if mini then return mini end
    local saved = MiniSettings()

    mini = CreateFrame("Frame", "OxedHubPerformanceMini", UIParent)
    mini:SetSize(320, 40)
    -- LOW: above the world and the action bars' backdrop, below every window the
    -- game opens. It sat in HIGH and covered the bags, which open in MEDIUM; a
    -- readout left on screen while playing must never be in the way of them.
    mini:SetFrameStrata("LOW")
    mini:SetClampedToScreen(true)
    mini:SetMovable(true)
    mini:EnableMouse(true)
    mini:RegisterForDrag("LeftButton")
    mini:SetScript("OnDragStart", mini.StartMoving)
    mini:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMiniPosition()
    end)
    mini:SetPoint(saved.miniPoint or "TOP", UIParent, saved.miniRelPoint or "TOP",
        saved.miniX or 0, saved.miniY or -120)

    -- The two bars, the lower one the longer, tucked behind the round button.
    mini.top = Bar(mini, 280, 19)
    mini.top:SetPoint("TOPLEFT", mini, "TOPLEFT", 22, -2)
    mini.bottom = Bar(mini, 298, 19)
    mini.bottom:SetPoint("TOPLEFT", mini.top, "BOTTOMLEFT", 0, 1)

    -- The round button, drawn over the start of both bars.
    local button = CreateFrame("Button", nil, mini)
    button:SetSize(32, 32)   -- the size of a minimap button
    button:SetPoint("LEFT", mini, "LEFT", 0, 0)
    button:SetFrameLevel(mini.bottom:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function() mini:StartMoving() end)
    button:SetScript("OnDragStop", function()
        mini:StopMovingOrSizing()
        SaveMiniPosition()
    end)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("TOPLEFT", 4, -4)
    background:SetColorTexture(0, 0, 0, 0.85)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 6, -6)
    icon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Minimap\\o-oxed-minimap.tga")
    -- Round, like the minimap buttons: the same mask the rest of OxedHub uses.
    for _, texture in ipairs({ background, icon }) do
        local mask = button:CreateMaskTexture()
        mask:SetAllPoints(texture)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        texture:AddMaskTexture(mask)
    end
    local ring = button:CreateTexture(nil, "OVERLAY")
    ring:SetSize(54, 54)   -- the minimap border art is drawn for a 32 px button
    ring:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Recording light: green while recording, red when stopped.
    -- A plain round dot, set on the icon's lower right edge so it sits inside
    -- the ring. The indicator texture used before was not a clean circle, and
    -- pinned to the button's corner it landed on the ring itself, crooked: the
    -- ring art is drawn smaller than the button it belongs to.
    mini.dot = button:CreateTexture(nil, "OVERLAY", nil, 2)
    mini.dot:SetSize(7, 7)
    mini.dot:SetPoint("CENTER", icon, "BOTTOMRIGHT", -2, 2)
    mini.dot:SetColorTexture(1, 1, 1, 1)
    local dotMask = button:CreateMaskTexture()
    dotMask:SetAllPoints(mini.dot)
    dotMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mini.dot:AddMaskTexture(dotMask)

    button:SetScript("OnClick", function(_, mouse)
        local P = Profiler()
        if mouse == "RightButton" then
            if P:IsActive() then P:Stop() else P:Start() end
            UpdateMini()
        else
            HideMini()
            Performance:Open()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("OxedHub Performance")
        GameTooltip:AddLine("Click: open the full window", 1, 1, 1)
        GameTooltip:AddLine("Right-click: start or stop recording", 1, 1, 1)
        GameTooltip:AddLine("Drag: move", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Twice a second is plenty for figures that are averaged over a second.
    local elapsed = 0
    mini:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        UpdateMini()
    end)

    mini:Hide()
    return mini
end

function ShowMini()
    BuildMini()
    MiniSettings().miniShown = true
    mini:Show()
    UpdateMini()
end

function HideMini()
    if mini then mini:Hide() end
    MiniSettings().miniShown = false
end

function Performance:Open(tab)
    if not Profiler() then return end
    Build()
    if tab then window.tab = tab end
    HideMini()
    window:Show()
    Refresh()
end

-- A mini window left on screen comes back after a reload.
local restore = CreateFrame("Frame")
restore:RegisterEvent("PLAYER_LOGIN")
restore:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if OxedHubDB and OxedHubDB.profiler and OxedHubDB.profiler.miniShown then
        ShowMini()
    end
end)

-- Shows or hides the mini window. Used by Ctrl+click on the minimap button and
-- by /oxprofile mini. Opening the mini closes the full window, as Minimise does.
function Performance:ToggleMini()
    if not Profiler() then return end
    if mini and mini:IsShown() then
        HideMini()
    else
        if window then window:Hide() end
        ShowMini()
    end
end

function Performance:Toggle()
    if window and window:IsShown() then window:Hide() else self:Open() end
end

-- /oxprofile            open the window
-- /oxprofile start|stop|reset|report|spikes|mini
SLASH_OXEDPROFILE1 = "/oxprofile"
SlashCmdList["OXEDPROFILE"] = function(argument)
    local P = Profiler()
    if not P then return end
    local command = tostring(argument or ""):lower():match("^%s*(%a*)")
    if command == "start" then
        P:Start()
        print("|cff00ff00OxedHub:|r performance recording started. /oxprofile to see it.")
    elseif command == "stop" then
        P:Stop()
        print("|cff00ff00OxedHub:|r performance recording stopped.")
    elseif command == "reset" then
        P:Reset()
        print("|cff00ff00OxedHub:|r performance data cleared.")
    elseif command == "report" then
        Build()
        ShowReport()
    elseif command == "spikes" then
        Performance:Open("spikes")
    elseif command == "mini" then
        if window then window:Hide() end
        if mini and mini:IsShown() then HideMini() else ShowMini() end
    else
        Performance:Open()
    end
end
