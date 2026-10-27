-- ============================================================================
-- Flight Timer (built-in OxedHub module)
-- A bar while you are on a flight path: where you are going, how long is left,
-- and a sound shortly before you land so you can do something else meanwhile.
--
-- It learns the times itself. The first flight on a route is timed and written
-- down, and every flight after that counts down from what it learned. Nothing
-- is shipped with the module: a table of every route in the game would be
-- larger than the whole addon, and a time measured on your own connection is
-- the right one anyway.
--
-- ⚠ TakeTaxiNode is hooked with hooksecurefunc, never replaced. Replacing a
-- Blizzard global taints everything that calls it afterwards.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    locked      = false,
    width       = 260,
    height      = 20,
    scale       = 1,
    texture     = "game",
    point       = "CENTER",
    x           = 0,
    y           = -180,

    showText    = true,    -- the names of the two ends
    showTime    = true,    -- how long is left
    countUp     = false,   -- time gone instead of time left

    warn        = true,    -- a sound before landing
    warnAt      = 10,      -- how many seconds before
    sound       = "",      -- an OxedHub sound by id; empty plays the game's own
    say         = true,    -- a line in chat when the flight starts

    colourR     = 0.25,
    colourG     = 0.65,
    colourB     = 1.00,

    -- "routes" is a table and is built in BindSettings: a table in DEFAULTS is
    -- copied by reference, and every character would share one set of times.
}

local settings
local optionsWindow
local bar
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ccffOxedHub Flight:|r "
local UPDATE = 0.1

local TEXTURES = {
    game = "Interface\\TargetingFrame\\UI-StatusBar",
    flat = "Interface\\Buttons\\WHITE8X8",
}

-- The flight in progress.
local flight = {}

-- ── Routes ──────────────────────────────────────────────────────────────────
-- One entry per pair of ends, both ways kept apart: the return leg is often a
-- different length. The key is the two names, which is enough to tell routes
-- apart without storing the game's node ids.

local function RouteKey(from, to)
    if not (from and to) then return nil end
    return from .. " > " .. to
end

local function KnownTime(from, to)
    local key = RouteKey(from, to)
    local saved = key and settings.routes[key]
    return type(saved) == "number" and saved > 0 and saved or nil
end

local function Learn(from, to, seconds)
    local key = RouteKey(from, to)
    if not key or seconds < 3 or seconds > 60 * 20 then return end

    -- Averaged with what was there, so one flight that hit a loading screen
    -- does not become the route's time for good.
    local old = settings.routes[key]
    if type(old) == "number" and old > 0 then
        settings.routes[key] = old * 0.7 + seconds * 0.3
    else
        settings.routes[key] = seconds
    end
end

-- ── The names of the two ends ───────────────────────────────────────────────

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeName(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    -- The game writes "Stormwind, Elwynn Forest"; the town is enough.
    return (value:gsub(",.*$", ""))
end

local function CurrentNode()
    if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) then return nil end
    for index = 1, NumTaxiNodes() do
        local ok, kind = pcall(TaxiNodeGetType, index)
        if ok and kind == "CURRENT" then
            local okName, name = pcall(TaxiNodeName, index)
            return okName and SafeName(name) or nil
        end
    end
    return nil
end

-- ── The bar ─────────────────────────────────────────────────────────────────

-- Every sound the player has in OxedHub. The library is shared across
-- characters, so the list is the same wherever you happen to be flying.

local function SoundName(id)
    if not id or id == "" then return L["The game's ready check sound"] end
    local library = (OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds())
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
    local sound = library[id]
    return (sound and sound.name) or id
end

-- Played through OxedHub own player, so it follows the channel and the
-- "sounds off" switch the player already set instead of going around them.
local function PlayWarning()
    local id = settings.sound
    if id and id ~= "" and OxedHub.Sounds and OxedHub.Sounds.Play then
        local ok = pcall(OxedHub.Sounds.Play, OxedHub.Sounds, id)
        if ok then return end
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
        pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
    end
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds + 0.5))
    if seconds >= 60 then
        return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
    end
    return ("%ds"):format(seconds)
end

local function SavePosition()
    if not bar then return end
    local point, _, _, x, y = bar:GetPoint(1)
    if point then
        settings.point, settings.x, settings.y = point, x, y
    end
end

local function Restyle()
    if not bar then return end
    bar:SetSize(tonumber(settings.width) or 260, tonumber(settings.height) or 20)
    bar:SetScale(tonumber(settings.scale) or 1)
    bar:SetStatusBarTexture(TEXTURES[settings.texture] or TEXTURES.game)
    bar:SetStatusBarColor(settings.colourR or 0.25, settings.colourG or 0.65, settings.colourB or 1)
    bar:ClearAllPoints()
    bar:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER",
        tonumber(settings.x) or 0, tonumber(settings.y) or -180)
    bar.route:SetShown(settings.showText == true)
    bar.time:SetShown(settings.showTime == true)
end

local function BuildBar()
    if bar then return end

    bar = CreateFrame("StatusBar", "OxedHubFlightTimer", UIParent, "BackdropTemplate")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
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
    bar:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    bar:SetBackdropBorderColor(0, 0, 0, 0.9)

    bar.route = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.route:SetPoint("LEFT", bar, "LEFT", 6, 0)
    bar.route:SetJustifyH("LEFT")

    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
    bar.time:SetJustifyH("RIGHT")

    bar:Hide()
    Restyle()
end

-- ── The flight ──────────────────────────────────────────────────────────────

local function Stop(landed)
    if not flight.active then return end
    local taken = GetTime() - flight.startedAt
    flight.active = false

    if landed and flight.from and flight.to then Learn(flight.from, flight.to, taken) end
    if bar then bar:Hide() end
    watcher:SetScript("OnUpdate", nil)
end

local FIRST_FLIGHT = "First time: calculating"

local function Tick(_, elapsed)
    flight.since = (flight.since or 0) + elapsed
    if flight.since < UPDATE then return end
    flight.since = 0

    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")

    -- ⚠ Taking a flight is not being on it. TakeTaxiNode runs the moment the
    -- destination is clicked, and the player boards a moment later, once the
    -- server answers. Checking "not on a taxi" straight away ended every flight
    -- a tenth of a second after it began, and the bar was never seen. So the
    -- bar waits for boarding, and the clock starts then; a flight that never
    -- starts (not enough gold, the map closed) is given up after a few seconds.
    if not flight.boarded then
        if onTaxi then
            flight.boarded = true
            flight.startedAt = GetTime()
        elseif GetTime() - flight.clickedAt > 8 then
            return Stop(false)
        end
        return
    end

    -- Landing is noticed here as well as by the event: a flight that ends
    -- while the game is loading a new zone never fires PLAYER_CONTROL_GAINED
    -- where we can hear it, and the bar would sit there for good.
    if not onTaxi then
        return Stop(true)
    end

    local gone = GetTime() - flight.startedAt
    local total = flight.total

    if total then
        bar:SetMinMaxValues(0, total)
        bar:SetValue(math.min(gone, total))
        local left = total - gone
        if settings.showTime then
            bar.time:SetText(settings.countUp and Clock(gone) or Clock(left))
        end
        if settings.warn and not flight.warned and left <= (tonumber(settings.warnAt) or 10) then
            flight.warned = true
            PlayWarning()
        end
    else
        -- A route flown for the first time: nothing to count down from yet.
        -- The bar stays full and still and says so; a swinging bar and a
        -- clock counting up read as a time that meant something.
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.time:SetText(FIRST_FLIGHT)
    end
end

local function Start(destination)
    if not settings or settings.enabled == false then return end

    BuildBar()
    flight.from = CurrentNode()
    flight.to = destination
    flight.clickedAt = GetTime()
    flight.startedAt = GetTime()   -- reset on boarding; see Tick
    flight.boarded = UnitOnTaxi and UnitOnTaxi("player") and true or false
    flight.total = KnownTime(flight.from, flight.to)
    flight.warned = false
    flight.since = 0
    flight.active = true

    local names = (flight.from and flight.to) and ("%s to %s"):format(flight.from, flight.to)
        or (flight.to or L["Flight"])
    bar.route:SetText(names)
    bar.time:SetText(flight.total and Clock(flight.total) or FIRST_FLIGHT)
    bar:SetMinMaxValues(0, flight.total or 1)
    bar:SetValue(0)
    Restyle()
    bar:Show()

    if settings.say then
        print(PREFIX .. (flight.total
            and (L["%s, about %s."]):format(names, Clock(flight.total))
            or (L["%s. First time on this route: timing it."]):format(names)))
    end

    watcher:SetScript("OnUpdate", Tick)
end

-- ── Hooks and events ────────────────────────────────────────────────────────

local hooked = false

local function InstallHooks()
    if hooked then return end
    if type(TakeTaxiNode) ~= "function" then return end
    hooked = true

    -- ⚠ hooksecurefunc, not a replacement: the taxi map's own buttons call
    -- this, and a replaced global would taint every one of them.
    hooksecurefunc("TakeTaxiNode", function(slot)
        if not settings or settings.enabled == false then return end
        local okName, name = pcall(TaxiNodeName, slot)
        Start(okName and SafeName(name) or nil)
    end)

    local addingTooltip = false
    if GameTooltip and GameTooltip.Show then
        -- ⚠ This runs for every tooltip the game shows, from every part of
        -- the UI. Some owners are forbidden frames (the house editor's fixture
        -- points were one): any method on them but IsForbidden is an error,
        -- and the error landed on OxedHub eighteen times in two minutes. A
        -- forbidden owner is left alone, and the rest runs inside pcall: a
        -- tooltip line about a flight is never worth an error.
        local function AddFlightLine(self)
            local owner = self:GetOwner()
            if not owner then return end
            if owner.IsForbidden and owner:IsForbidden() then return end

            local name = owner.GetName and owner:GetName()
            local isRetailFlightPin = type(owner.taxiNodeData) == "table"
            local isClassicTaxiBtn = name and type(name) == "string" and name:match("^TaxiButton")
            if not (isRetailFlightPin or isClassicTaxiBtn) then return end

            local text = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
            if not text then return end

            local from = CurrentNode()
            local to = SafeName(text)
            if not from or not to or from == to then return end

            local time = KnownTime(from, to)
            if time then
                addingTooltip = true
                self:AddLine(L["Duration: "] .. Clock(time), 1, 1, 1)
                self:Show()
                addingTooltip = false
            end
        end

        hooksecurefunc(GameTooltip, "Show", function(self)
            if addingTooltip then return end
            if not settings or settings.enabled == false then return end
            if self.IsForbidden and self:IsForbidden() then return end
            local ok = pcall(AddFlightLine, self)
            if not ok then addingTooltip = false end
        end)
    end
end

watcher:SetScript("OnEvent", function(_, event)
    if not settings or settings.enabled == false then return end

    if event == "PLAYER_CONTROL_GAINED" then
        -- The flight ended, or the player was let go of for another reason.
        if flight.active and flight.boarded and UnitOnTaxi and not UnitOnTaxi("player") then
            Stop(true)
        end
    elseif event == "PLAYER_LEAVING_WORLD" then
        -- A flight that crosses a loading screen keeps going; the clock is
        -- GetTime, which does not stop.
    elseif event == "PLAYER_ENTERING_WORLD" then
        InstallHooks()
        if flight.active and flight.boarded and UnitOnTaxi and not UnitOnTaxi("player") then
            Stop(false)
        end
    end
end)

local function StartModule()
    InstallHooks()
    for _, event in ipairs({ "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    -- Switched on while already in the air: time what is left of it.
    if UnitOnTaxi and UnitOnTaxi("player") then Start(nil) end
end

local function StopModule()
    watcher:UnregisterAllEvents()
    Stop(false)
    if bar then bar:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.flighttimer
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.flighttimer = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.routes) ~= "table" then config.routes = {} end
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
        slider:SetValue(tonumber(settings[key]) or minValue)
        Show(tonumber(settings[key]) or minValue)
        refreshing = false
        ready = true
    end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing or not ready then return end
        settings[key] = value
        Restyle()
    end)
    Load()
    w:HookScript("OnShow", Load)
    w.cursorY = w.cursorY - 30
end



local function PickColour()
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then return end
    local before = { settings.colourR, settings.colourG, settings.colourB }
    ColorPickerFrame:SetupColorPickerAndShow({
        r = settings.colourR, g = settings.colourG, b = settings.colourB,
        swatchFunc = function()
            settings.colourR, settings.colourG, settings.colourB = ColorPickerFrame:GetColorRGB()
            Restyle()
        end,
        cancelFunc = function()
            settings.colourR, settings.colourG, settings.colourB = before[1], before[2], before[3]
            Restyle()
        end,
    })
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Flight Timer", 500, 580)
        local w = optionsWindow

        w:AddCheckbox(settings, "showText", "Show where you are going", nil, Restyle)
        w:AddCheckbox(settings, "showTime", "Show the time", nil, Restyle)
        w:AddCheckbox(settings, "countUp", "Count up instead of down")
        w:AddCheckbox(settings, "say", "Say the flight in chat when it starts")

        w:AddCheckbox(settings, "warn", "Sound before you land")
        AddSlider(w, "warnAt", "Sound this early", 3, 60, 1, "%s: %d s")

        w:AddSoundPicker(settings, "sound", "Landing sound", "The game's ready check sound")

        w:AddCheckbox(settings, "locked", "Lock the bar",
            "Unlocked, drag the bar with the left button.")
        AddSlider(w, "width", L["Bar width"], 120, 500, 10, "%s: %d")
        AddSlider(w, "height", L["Bar height"], 10, 40, 1, "%s: %d")
        AddSlider(w, "scale", L["Scale"], 0.5, 2, 0.05, "%s: %.2f")

        local pick = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        pick:SetSize(140, 22)
        pick:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        pick:SetText(L["Pick bar colour"])
        pick:SetScript("OnClick", PickColour)
        w.cursorY = w.cursorY - 30

        local forget = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        forget:SetSize(140, 22)
        forget:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        forget:SetText(L["Forget all times"])
        forget:SetScript("OnClick", function()
            API:Confirm(L["Forget every flight time learned so far?"], function()
                wipe(settings.routes)
                print(PREFIX .. L["every route forgotten; they will be timed again."])
            end)
        end)
        w.cursorY = w.cursorY - 30

        w:AddNote("The first flight on a route is timed and written down. Every flight after that counts down from what was learned, and each new flight nudges the figure, so it settles on your own connection rather than on a table shipped with the addon.")
        w:AddNote("The landing sound is picked from your own OxedHub sounds, the same library the triggers use, and it plays through OxedHub so it follows your sound channel.")
        w:AddNote("Type /oxflight for what has been learned so far.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBFLIGHT1 = "/oxflight"
SlashCmdList.OXEDHUBFLIGHT = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()

    if msg == "forget" then
        wipe(settings.routes)
        print(PREFIX .. L["every route forgotten."])
        return
    end

    if msg == "list" then
        local rows = {}
        for key, seconds in pairs(settings.routes) do
            rows[#rows + 1] = ("  %s: %s"):format(key, Clock(seconds))
        end
        table.sort(rows)
        print(PREFIX .. (L["%d routes learned"]):format(#rows))
        for index = 1, math.min(#rows, 30) do print(rows[index]) end
        if #rows > 30 then print((L["  ... and %d more"]):format(#rows - 30)) end
        return
    end

    local count = 0
    for _ in pairs(settings.routes) do count = count + 1 end
    print(PREFIX .. (L["%d routes learned. /oxflight list shows them, /oxflight forget clears them."])
        :format(count))
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then StartModule() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "flighttimer",
        name     = "Flight Timer",
        version  = "1.0.0",
        author   = "Oxed",
        category = "quests",
        keywords = { "flight", "taxi", "flight path", "timer", "inflight", "travel", "afk" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A timer bar on flight paths, with a sound before you land. Type /oxflight.",
        icon     = "Interface\\Icons\\Ability_Mount_Gryphon_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.routes) ~= "table" then settings.routes = {} end
            StartModule()
        end,

        OnDisable = function()
            StopModule()
        end,
    })
end)
