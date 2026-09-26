-- ============================================================================
-- Instances (built-in OxedHub module)
-- How many instances you have entered this hour, when the next one frees up,
-- and what each run was worth: how long it took, the gold, the experience and
-- what dropped.
--
-- The game allows ten instances an hour on retail, counted for the whole
-- account rather than one character, and it says nothing until it refuses to
-- let you in. This counts them as they happen and warns you before that.
--
-- ⚠ Entering the world happens for a reload and a login as well as for a
-- zone in. Those two are told apart by the arguments of
-- PLAYER_ENTERING_WORLD, or a reload inside a dungeon would count as a fresh
-- instance every time.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    hourly      = 10,      -- what the game allows in an hour
    warnAt      = 2,       -- warn once this many are left
    say         = true,    -- a line in chat on entering
    summary     = true,    -- a line in chat when a run ends

    bar         = true,    -- the small counter on screen
    locked      = false,
    scale       = 1,
    point       = "CENTER",
    x           = 0,
    y           = 260,
    onlyInside  = true,    -- the counter only while you are in an instance

    keep        = 40,      -- how many runs are remembered

    -- "entries" and "runs" are tables and are built in BindSettings: a table
    -- in DEFAULTS is copied by reference and every character would share one.
}

local settings
local optionsWindow
local bar, logWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ccffOxedHub Instances:|r "
local HOUR = 3600

-- The run in progress.
local run = {}

local ShowLog   -- defined with the log window, used by the bar above it

-- ── The hour's entries ──────────────────────────────────────────────────────

local function Now()
    return (GetServerTime and GetServerTime()) or time()
end

-- Entries older than an hour are gone as far as the game is concerned, so
-- they are dropped rather than kept for ever.
local function Prune()
    local cutoff = Now() - HOUR
    local entries = settings.entries
    for index = #entries, 1, -1 do
        if (entries[index] or 0) < cutoff then table.remove(entries, index) end
    end
end

local function HourCount()
    Prune()
    return #settings.entries
end

-- When the oldest of them falls out of the hour, which is when the next
-- instance becomes free.
local function NextFree()
    Prune()
    local oldest = settings.entries[1]
    if not oldest then return nil end
    return math.max(0, oldest + HOUR - Now())
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds >= 3600 then
        return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
    elseif seconds >= 60 then
        return ("%dm %02ds"):format(math.floor(seconds / 60), seconds % 60)
    end
    return ("%ds"):format(seconds)
end

local function Gold(copper)
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, copper or 0, true)
        if ok and text then return text end
    end
    return ("%dg"):format(math.floor((copper or 0) / 10000))
end

-- ── The counter on screen ───────────────────────────────────────────────────

local function SavePosition()
    if not bar then return end
    local point, _, _, x, y = bar:GetPoint(1)
    if point then settings.point, settings.x, settings.y = point, x, y end
end

local function RefreshBar()
    if not bar then return end

    local inside = IsInInstance and IsInInstance() or false
    local show = settings.bar and settings.enabled ~= false
        and (not settings.onlyInside or inside or run.active)
    if not show then return bar:Hide() end

    local count = HourCount()
    local limit = tonumber(settings.hourly) or 10
    local left = math.max(0, limit - count)
    local colour = left == 0 and "|cffff3333" or (left <= (tonumber(settings.warnAt) or 2) and "|cffff9933" or "|cff40ff40")
    local free = NextFree()

    bar.text:SetFormattedText("%s%d/%d|r this hour%s", colour, count, limit,
        free and ("   next free in %s"):format(Clock(free)) or "")

    if run.active then
        local elapsed = Now() - run.startedAt
        bar.run:SetFormattedText("%s   %s   %s", run.name or "", Clock(elapsed), Gold(run.gold or 0))
        bar.run:Show()
    else
        bar.run:Hide()
    end

    bar:SetWidth(math.max(180, bar.text:GetStringWidth() + 20,
        bar.run:IsShown() and bar.run:GetStringWidth() + 20 or 0))
    bar:SetHeight(bar.run:IsShown() and 38 or 24)
    bar:SetScale(tonumber(settings.scale) or 1)
    bar:Show()
end

local function BuildBar()
    if bar then return end

    bar = CreateFrame("Frame", "OxedHubInstanceBar", UIParent, "BackdropTemplate")
    bar:SetSize(200, 24)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
        if not settings.locked then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
    bar:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("TOP", bar, "TOP", 0, -5)

    bar.run = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bar.run:SetPoint("TOP", bar.text, "BOTTOM", 0, -2)

    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and ShowLog then ShowLog() end
    end)

    bar:ClearAllPoints()
    bar:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER",
        tonumber(settings.x) or 0, tonumber(settings.y) or 260)
    bar:Hide()
end

-- ── A run ───────────────────────────────────────────────────────────────────

local function InstanceName()
    if not GetInstanceInfo then return nil end
    local ok, name, kind, _, difficulty = pcall(GetInstanceInfo)
    if not ok or type(name) ~= "string" then return nil, nil end
    local label = name
    if type(difficulty) == "string" and difficulty ~= "" then
        label = ("%s (%s)"):format(name, difficulty)
    end
    return label, kind
end

local function StartRun(counted)
    local name, kind = InstanceName()
    run.active = true
    run.name = name or "Instance"
    run.kind = kind
    run.startedAt = Now()
    run.gold = 0
    run.xp = 0
    run.loot = 0
    run.money = GetMoney and GetMoney() or 0
    run.xpAt = UnitXP and UnitXP("player") or 0
    run.counted = counted and true or false

    if settings.say and counted then
        local count, limit = HourCount(), tonumber(settings.hourly) or 10
        local free = NextFree()
        print(PREFIX .. ("%s. |cffffd100%d of %d|r this hour%s."):format(
            run.name, count, limit, free and (", next free in " .. Clock(free)) or ""))

        local left = limit - count
        if left <= (tonumber(settings.warnAt) or 2) then
            print(PREFIX .. (left <= 0
                and "|cffff3333that was the last one; the game will refuse the next.|r"
                or ("|cffff9933only %d left this hour.|r"):format(left)))
        end
    end
    RefreshBar()
end

local function EndRun()
    if not run.active then return end
    run.active = false

    local taken = Now() - run.startedAt
    if taken < 20 then return RefreshBar() end   -- walked in and straight out

    local entry = {
        name = run.name, at = run.startedAt, seconds = taken,
        gold = run.gold or 0, xp = run.xp or 0, loot = run.loot or 0,
    }
    table.insert(settings.runs, 1, entry)
    while #settings.runs > (tonumber(settings.keep) or 40) do table.remove(settings.runs) end

    if settings.summary then
        local parts = { Clock(taken) }
        if entry.gold > 0 then parts[#parts + 1] = Gold(entry.gold) end
        if entry.xp > 0 then parts[#parts + 1] = ("%d xp"):format(entry.xp) end
        if entry.loot > 0 then parts[#parts + 1] = ("%d items"):format(entry.loot) end
        print(PREFIX .. ("%s: %s."):format(entry.name, table.concat(parts, ", ")))
    end
    RefreshBar()
end

-- ── The log window ──────────────────────────────────────────────────────────

local function BuildLog()
    if logWindow then return logWindow end
    local ok, window = pcall(CreateFrame, "Frame", "OxedHubInstanceLog", UIParent, "BasicFrameTemplate")
    if not ok or not window then return nil end

    window:SetSize(460, 420)
    window:SetPoint("CENTER")
    window:SetFrameStrata("HIGH")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.TitleText then window.TitleText:SetText("Instances") end
    tinsert(UISpecialFrames, "OxedHubInstanceLog")

    window.head = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    window.head:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -32)

    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -56)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -26, 14)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(400, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local limit = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(limit, self:GetVerticalScroll() - delta * 40)))
    end)
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    end
    scroll:HookScript("OnSizeChanged", function(self) content:SetWidth(self:GetWidth()) end)

    local rows = {}
    local function Refresh()
        local count, limit = HourCount(), tonumber(settings.hourly) or 10
        local free = NextFree()
        window.head:SetFormattedText("%d of %d this hour%s", count, limit,
            free and ("   |cff9d9d9dnext free in %s|r"):format(Clock(free)) or "")

        local y = 0
        for index, entry in ipairs(settings.runs) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Frame", nil, content)
                row:SetHeight(32)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -2)
                row.name:SetJustifyH("LEFT")
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -1)
                row.detail:SetJustifyH("LEFT")
                rows[index] = row
            end
            local parts = { Clock(entry.seconds) }
            if (entry.gold or 0) > 0 then parts[#parts + 1] = Gold(entry.gold) end
            if (entry.xp or 0) > 0 then parts[#parts + 1] = ("%d xp"):format(entry.xp) end
            if (entry.loot or 0) > 0 then parts[#parts + 1] = ("%d items"):format(entry.loot) end

            row.name:SetText(entry.name or "Instance")
            row.detail:SetFormattedText("%s   |cff9d9d9d%s|r",
                table.concat(parts, "   "), date("%d %b %H:%M", entry.at or 0))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row:Show()
            y = y + 34
        end
        for index = #settings.runs + 1, #rows do rows[index]:Hide() end
        content:SetHeight(math.max(1, y))
        window.empty:SetShown(#settings.runs == 0)
    end
    window.Refresh = Refresh

    window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    window.empty:SetPoint("CENTER", scroll, "CENTER")
    window.empty:SetText("No runs yet")

    window:SetScript("OnShow", Refresh)
    window:Hide()
    logWindow = window
    return window
end

ShowLog = function()
    local window = BuildLog()
    if window then window:SetShown(not window:IsShown()) end
end

-- ── Events ──────────────────────────────────────────────────────────────────

local ticker

watcher:SetScript("OnEvent", function(_, event, arg1, arg2)
    if not settings or settings.enabled == false then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = arg1, arg2
        local inside = IsInInstance and IsInInstance() or false

        if not inside then
            EndRun()
            RefreshBar()
            return
        end

        -- ⚠ A reload or a login inside an instance is not a new entry. Only a
        -- real zone in counts, or every /reload in a dungeon would eat one of
        -- the ten the game allows.
        if isLogin or isReload then
            if not run.active then StartRun(false) end
            RefreshBar()
            return
        end

        local _, kind = InstanceName()
        local counts = kind == "party" or kind == "raid" or kind == "scenario"
        if counts then
            table.insert(settings.entries, Now())
        end
        StartRun(counts)

    elseif event == "PLAYER_MONEY" then
        if run.active and GetMoney then
            local now = GetMoney()
            local gained = now - (run.money or now)
            if gained > 0 then run.gold = (run.gold or 0) + gained end
            run.money = now
        end

    elseif event == "PLAYER_XP_UPDATE" then
        if run.active and UnitXP then
            local now = UnitXP("player")
            local gained = now - (run.xpAt or now)
            if gained > 0 then run.xp = (run.xp or 0) + gained end
            run.xpAt = now
        end

    elseif event == "CHAT_MSG_LOOT" then
        -- Only our own lines, and only when the text can be read: chat text is
        -- a secret value in some content and any match on one is an error.
        if run.active and type(arg1) == "string" and not (issecretvalue and issecretvalue(arg1)) then
            local me = UnitName("player")
            if type(me) == "string" and arg1:find(me, 1, true) then
                run.loot = (run.loot or 0) + 1
            end
        end
    end
end)

-- ⚠ No kill counting. The combat log is closed to addons on 12.0, and the
-- standalone kill event does not fire inside instances, so every run would
-- have shown a zero that looked like a count.
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_MONEY", "PLAYER_XP_UPDATE", "CHAT_MSG_LOOT",
}

local function Start()
    BuildBar()
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    if not ticker then ticker = C_Timer.NewTicker(1, RefreshBar) end
    if IsInInstance and IsInInstance() and not run.active then StartRun(false) end
    RefreshBar()
end

local function Stop()
    watcher:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    EndRun()
    if bar then bar:Hide() end
    if logWindow then logWindow:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.instances
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.instances = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.entries) ~= "table" then config.entries = {} end
    if type(config.runs) ~= "table" then config.runs = {} end
    settings = config
end

local function AddSlider(w, key, caption, minValue, maxValue, step, format)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(190, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 250, w.cursorY - 5)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    -- ⚠ A fresh slider holds 0 and the template moves it while the window is
    -- laid out. Nothing is saved until it has been told the real value.
    local ready, refreshing = false, false
    local function Show(value) label:SetText((format):format(caption, value)) end
    local function Load()
        refreshing = true
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
        refreshing = false
        ready = true
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing or not ready then return end
        settings[key] = value
        RefreshBar()
    end)
    Load()
    w:HookScript("OnShow", Load)
    w.cursorY = w.cursorY - 30
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Instances", 500, 520)
        local w = optionsWindow

        w:AddCheckbox(settings, "bar", "Show the counter on screen", nil, RefreshBar)
        w:AddCheckbox(settings, "onlyInside", "Only while you are in an instance", nil, RefreshBar)
        w:AddCheckbox(settings, "locked", "Lock it in place",
            "Unlocked, drag the counter with the left button. Right-click it for the log.")
        AddSlider(w, "scale", "Counter scale", 0.5, 2, 0.05, "%s: %.2f")

        w:AddCheckbox(settings, "say", "Say the count when you enter")
        w:AddCheckbox(settings, "summary", "Say what the run was worth when you leave")
        AddSlider(w, "hourly", "Instances the game allows an hour", 5, 30, 1, "%s: %d")
        AddSlider(w, "warnAt", "Warn when this many are left", 0, 5, 1, "%s: %d")
        AddSlider(w, "keep", "Runs remembered", 10, 200, 10, "%s: %d")

        local log = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        log:SetSize(140, 22)
        log:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        log:SetText("Open the log")
        log:SetScript("OnClick", ShowLog)

        local clear = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        clear:SetSize(140, 22)
        clear:SetPoint("LEFT", log, "RIGHT", 8, 0)
        clear:SetText("Clear the log")
        clear:SetScript("OnClick", function()
            API:Confirm("Forget every run in the log?", function()
                wipe(settings.runs)
                if logWindow and logWindow:IsShown() then logWindow.Refresh() end
                print(PREFIX .. "log cleared.")
            end)
        end)
        w.cursorY = w.cursorY - 30

        w:AddNote("Retail allows ten instances an hour, counted for the whole account rather than one character. The counter here only sees what this character does, so a second character running dungeons at the same time will not show up.")
        w:AddNote("Type /oxinst for the count, /oxinst log for the log.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBINSTANCES1 = "/oxinst"
SlashCmdList.OXEDHUBINSTANCES = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()

    if msg == "log" then
        ShowLog()
        return
    end
    if msg == "clear" then
        wipe(settings.runs)
        print(PREFIX .. "log cleared.")
        return
    end
    if msg == "reset" then
        wipe(settings.entries)
        RefreshBar()
        print(PREFIX .. "the hour's entries forgotten. The game still counts its own.")
        return
    end

    local count, limit = HourCount(), tonumber(settings.hourly) or 10
    local free = NextFree()
    print(PREFIX .. ("%d of %d this hour%s. %d runs in the log."):format(
        count, limit, free and (", next free in " .. Clock(free)) or "", #settings.runs))
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "instances",
        name     = "Instances",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "instance", "dungeon", "lockout", "limit", "per hour", "farm", "log", "gold" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Counts your instances an hour and logs what each run was worth. /oxinst",
        icon     = "Interface\\Icons\\Achievement_Boss_Archaedas",

        defaults = DEFAULTS,

        ShowLog  = ShowLog,

        OnOptionsShow = function() ShowOptions() end,
        -- On the minimap button's right-click menu.
        quick = {
            { text = "Run log", func = function() ShowLog() end },
        },

        OnEnable = function(_, config)
            settings = config
            if type(settings.entries) ~= "table" then settings.entries = {} end
            if type(settings.runs) ~= "table" then settings.runs = {} end
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
