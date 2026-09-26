-- ============================================================================
-- PvP Progress (built-in OxedHub module)
-- Everything the PvP frames make you go and look up, on one panel:
--
--   honour        the level you are on and how far into the next one
--   conquest      how much of this week's cap is left
--   vault         the wins still needed for each of the three slots
--   brackets      rating, and the week's and the season's record, per bracket
--   session       what this evening was worth: honour, conquest, wins, losses
--
-- ⚠ Rated figures come from GetPersonalRatedInfo, whose returns are not in the
-- same order for every bracket: Solo Shuffle and Blitz count rounds, and their
-- played and won sit further along the list. The positions live in BRACKETS
-- below; read them from there, never by counting on the fly.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    honour      = true,
    conquest    = true,
    vault       = true,
    brackets    = true,
    session     = true,

    locked      = false,
    scale       = 1,
    point       = "CENTER",
    x           = 0,
    y           = 0,

    open        = false,   -- the panel was left open
    say         = true,    -- a line in chat when a rated match ends
}

local settings
local optionsWindow
local panel
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ccffOxedHub PvP:|r "

-- Currency ids: what the game pays you for PvP.
local HONOUR_CURRENCY = 1792
local CONQUEST_CURRENCY = 1602

-- ⚠ played and won are not at the same position for every bracket: the two
-- that count rounds report theirs further along.
local BRACKETS = {
    { id = 1, name = "2v2",           played = 4,  won = 5 },
    { id = 2, name = "3v3",           played = 4,  won = 5 },
    { id = 4, name = "Rated BG",      played = 4,  won = 5 },
    { id = 7, name = "Solo Shuffle",  played = 12, won = 13 },
    { id = 9, name = "Blitz",         played = 4,  won = 5 },
}

-- What this session has been worth. Not saved: a session is one sitting.
local session = { honour = 0, conquest = 0, wins = 0, losses = 0, startedAt = 0 }

-- ── Reading the game ────────────────────────────────────────────────────────

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function Number(value)
    if IsSecret(value) or type(value) ~= "number" then return 0 end
    return value
end

local function Currency(id)
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, id)
    if not ok or type(info) ~= "table" then return nil end
    return {
        amount = Number(info.quantity),
        cap = Number(info.maxQuantity),
        earned = Number(info.totalEarned),
    }
end

local function Honour()
    local level = UnitHonorLevel and Number(UnitHonorLevel("player")) or 0
    local into = UnitHonor and Number(UnitHonor("player")) or 0
    local needed = UnitHonorMax and Number(UnitHonorMax("player")) or 0
    return level, into, needed
end

-- One bracket, or nil when this client does not have it.
local function Bracket(entry)
    if not GetPersonalRatedInfo then return nil end
    local values = { pcall(GetPersonalRatedInfo, entry.id) }
    if not values[1] then return nil end
    table.remove(values, 1)   -- the pcall's own "ok"

    local rating = Number(values[1])
    local played = Number(values[entry.played])
    local won = Number(values[entry.won])
    if rating == 0 and played == 0 then return nil end

    return {
        name = entry.name,
        rating = rating,
        seasonBest = Number(values[2]),
        weeklyBest = Number(values[3]),
        played = played,
        won = won,
        weekPlayed = Number(values[6]),
        weekWon = Number(values[7]),
    }
end

-- The three Great Vault slots and the wins each still wants.
local function Vault()
    if not (C_WeeklyRewards and C_WeeklyRewards.GetActivities
        and Enum and Enum.WeeklyRewardChestThresholdType) then
        return nil
    end
    local ok, activities = pcall(C_WeeklyRewards.GetActivities,
        Enum.WeeklyRewardChestThresholdType.RankedPvP)
    if not ok or type(activities) ~= "table" then return nil end

    local rows = {}
    for _, activity in ipairs(activities) do
        rows[#rows + 1] = {
            progress = Number(activity.progress),
            threshold = Number(activity.threshold),
            level = Number(activity.level),
        }
    end
    table.sort(rows, function(a, b) return a.threshold < b.threshold end)
    return rows
end

-- ── The panel ───────────────────────────────────────────────────────────────

local function Comma(number)
    local text = tostring(math.floor(number or 0))
    local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function SavePosition()
    if not panel then return end
    local point, _, _, x, y = panel:GetPoint(1)
    if point then settings.point, settings.x, settings.y = point, x, y end
end

local function NewLine(parent, index)
    local line = parent.lines[index]
    if line then return line end

    line = CreateFrame("Frame", nil, parent)
    line:SetHeight(16)
    line.left = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.left:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.left:SetJustifyH("LEFT")
    line.right = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.right:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    line.right:SetJustifyH("RIGHT")
    parent.lines[index] = line
    return line
end

local function Refresh()
    if not (panel and panel:IsShown() and settings) then return end

    local shown, y = 0, 0
    local function Row(left, right, gold)
        shown = shown + 1
        local line = NewLine(panel, shown)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -30 - y)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, -30 - y)
        line.left:SetText(gold and ("|cffffd100%s|r"):format(left) or left)
        line.right:SetText(right or "")
        line:Show()
        y = y + (right == nil and 18 or 16)
    end

    if settings.honour then
        local level, into, needed = Honour()
        Row("Honour", nil, true)
        Row(("Level %d"):format(level), needed > 0
            and ("%s / %s"):format(Comma(into), Comma(needed)) or Comma(into))
        local honour = Currency(HONOUR_CURRENCY)
        if honour then
            Row("Honour held", honour.cap > 0
                and ("%s / %s"):format(Comma(honour.amount), Comma(honour.cap))
                or Comma(honour.amount))
        end
    end

    if settings.conquest then
        local conquest = Currency(CONQUEST_CURRENCY)
        if conquest then
            Row("Conquest", nil, true)
            if conquest.cap > 0 then
                local left = math.max(0, conquest.cap - conquest.earned)
                Row("This week", ("%s / %s"):format(Comma(conquest.earned), Comma(conquest.cap)))
                Row("Still to earn", Comma(left))
            else
                Row("Held", Comma(conquest.amount))
            end
        end
    end

    if settings.vault then
        local rows = Vault()
        if rows and #rows > 0 then
            Row("Great Vault", nil, true)
            for _, slot in ipairs(rows) do
                local done = slot.progress >= slot.threshold
                local text = ("%d / %d wins"):format(math.min(slot.progress, slot.threshold), slot.threshold)
                Row(done and "|cff40ff40Slot earned|r" or "Slot",
                    done and ("|cff40ff40%s|r"):format(text) or text)
            end
        end
    end

    if settings.brackets then
        local any = false
        for _, entry in ipairs(BRACKETS) do
            local data = Bracket(entry)
            if data then
                if not any then
                    Row("Rating", nil, true)
                    any = true
                end
                local record = data.weekPlayed > 0
                    and ("%d  |cff9d9d9d%d-%d this week|r"):format(data.rating, data.weekWon,
                        data.weekPlayed - data.weekWon)
                    or ("%d  |cff9d9d9d%d-%d season|r"):format(data.rating, data.won,
                        data.played - data.won)
                Row(data.name, record)
            end
        end
    end

    if settings.session then
        Row("This session", nil, true)
        Row("Honour", Comma(session.honour))
        Row("Conquest", Comma(session.conquest))
        Row("Rated", ("%d won, %d lost"):format(session.wins, session.losses))
    end

    for index = shown + 1, #panel.lines do panel.lines[index]:Hide() end
    panel:SetHeight(44 + y)
end

local function BuildPanel()
    if panel then return end

    local ok, frame = pcall(CreateFrame, "Frame", "OxedHubPvPProgress", UIParent, "BasicFrameTemplate")
    if not ok or not frame then return end

    panel = frame
    panel:SetSize(260, 300)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self)
        if not settings.locked then self:StartMoving() end
    end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    if panel.TitleText then panel.TitleText:SetText("PvP Progress") end
    if panel.CloseButton then
        panel.CloseButton:SetScript("OnClick", function()
            settings.open = false
            panel:Hide()
        end)
    end
    tinsert(UISpecialFrames, "OxedHubPvPProgress")

    panel.lines = {}
    panel:SetScale(tonumber(settings.scale) or 1)
    panel:ClearAllPoints()
    panel:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER",
        tonumber(settings.x) or 0, tonumber(settings.y) or 0)
    panel:SetScript("OnShow", Refresh)
    panel:Hide()
end

local function TogglePanel(show)
    BuildPanel()
    if not panel then return end
    if show == nil then show = not panel:IsShown() end
    settings.open = show and true or false
    panel:SetShown(show)
    if show then Refresh() end
end

-- ── Events ──────────────────────────────────────────────────────────────────

local lastHonour, lastConquest

local function TrackCurrencies()
    local honour = Currency(HONOUR_CURRENCY)
    if honour then
        if lastHonour and honour.amount > lastHonour then
            session.honour = session.honour + (honour.amount - lastHonour)
        end
        lastHonour = honour.amount
    end

    local conquest = Currency(CONQUEST_CURRENCY)
    if conquest then
        -- Earned, not held: conquest spent at a vendor would otherwise read as
        -- a loss and take the session's total down with it.
        if lastConquest and conquest.earned > lastConquest then
            session.conquest = session.conquest + (conquest.earned - lastConquest)
        end
        lastConquest = conquest.earned
    end
end

watcher:SetScript("OnEvent", function(_, event, ...)
    if not settings or settings.enabled == false then return end

    if event == "CURRENCY_DISPLAY_UPDATE" or event == "HONOR_XP_UPDATE"
        or event == "HONOR_LEVEL_UPDATE" then
        TrackCurrencies()
        Refresh()

    elseif event == "PVP_MATCH_COMPLETE" then
        -- The result is asked for a moment later: the score is not final at
        -- the instant the match is called complete.
        C_Timer.After(1, function()
            local won = false
            if C_PvP and C_PvP.GetActiveMatchWinner and GetBattlefieldWinner then
                local ok, winner = pcall(GetBattlefieldWinner)
                local faction = UnitFactionGroup and UnitFactionGroup("player")
                if ok and type(winner) == "number" and faction then
                    won = (winner == 0 and faction == "Horde") or (winner == 1 and faction == "Alliance")
                end
            end
            if won then session.wins = session.wins + 1 else session.losses = session.losses + 1 end
            if settings.say then
                print(PREFIX .. (won and "won." or "lost.")
                    .. (" This session: %d won, %d lost."):format(session.wins, session.losses))
            end
            Refresh()
        end)

    elseif event == "PVP_RATED_STATS_UPDATE" or event == "WEEKLY_REWARDS_UPDATE"
        or event == "PLAYER_ENTERING_WORLD" then
        Refresh()
    end
end)

local EVENTS = {
    "CURRENCY_DISPLAY_UPDATE", "HONOR_XP_UPDATE", "HONOR_LEVEL_UPDATE",
    "PVP_RATED_STATS_UPDATE", "WEEKLY_REWARDS_UPDATE", "PVP_MATCH_COMPLETE",
    "PLAYER_ENTERING_WORLD",
}

local function Start()
    BuildPanel()
    for _, event in ipairs(EVENTS) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    session.startedAt = time()
    lastHonour, lastConquest = nil, nil
    TrackCurrencies()

    -- Rated figures arrive late after a login, so the first draw waits for
    -- them rather than showing a panel full of zeroes.
    if C_PvP and C_PvP.RequestRatedInfo then pcall(C_PvP.RequestRatedInfo) end
    C_Timer.After(3, Refresh)

    if settings.open then TogglePanel(true) end
end

local function Stop()
    watcher:UnregisterAllEvents()
    if panel then panel:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.pvpprogress
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.pvpprogress = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
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
        if panel then panel:SetScale(tonumber(settings.scale) or 1) end
        Refresh()
    end)
    Load()
    w:HookScript("OnShow", Load)
    w.cursorY = w.cursorY - 30
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("PvP Progress", 480, 480)
        local w = optionsWindow

        w:AddCheckbox(settings, "honour", "Honour level and honour held", nil, Refresh)
        w:AddCheckbox(settings, "conquest", "This week's conquest", nil, Refresh)
        w:AddCheckbox(settings, "vault", "Great Vault slots", nil, Refresh)
        w:AddCheckbox(settings, "brackets", "Rating for every bracket", nil, Refresh)
        w:AddCheckbox(settings, "session", "What this session was worth", nil, Refresh)

        w:AddCheckbox(settings, "say", "Say won or lost in chat after a match")
        w:AddCheckbox(settings, "locked", "Lock the panel",
            "Unlocked, drag it with the left button.")
        AddSlider(w, "scale", "Panel scale", 0.6, 2, 0.05, "%s: %.2f")

        local open = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        open:SetSize(140, 22)
        open:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        open:SetText("Show the panel")
        open:SetScript("OnClick", function() TogglePanel(true) end)

        local reset = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        reset:SetSize(140, 22)
        reset:SetPoint("LEFT", open, "RIGHT", 8, 0)
        reset:SetText("Reset the session")
        reset:SetScript("OnClick", function()
            session.honour, session.conquest, session.wins, session.losses = 0, 0, 0, 0
            session.startedAt = time()
            Refresh()
            print(PREFIX .. "session reset.")
        end)
        w.cursorY = w.cursorY - 30

        w:AddNote("The session counts from when you logged in, or from the last reset. It is not saved: one sitting is one session.")
        w:AddNote("Conquest is counted as earned rather than held, so spending it at a vendor does not read as a loss.")
        w:AddNote("Type /oxpvp to open and close the panel.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBPVP1 = "/oxpvp"
SlashCmdList.OXEDHUBPVP = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()

    if msg == "reset" then
        session.honour, session.conquest, session.wins, session.losses = 0, 0, 0, 0
        session.startedAt = time()
        Refresh()
        print(PREFIX .. "session reset.")
        return
    end
    if msg == "options" then
        ShowOptions()
        return
    end
    TogglePanel()
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
        id       = "pvpprogress",
        name     = "PvP Progress",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "pvp", "honor", "honour", "conquest", "rating", "vault", "arena",
            "battleground", "solo shuffle", "blitz", "progress" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Honour, conquest, vault wins and every rating on one panel. Type /oxpvp.",
        icon     = "Interface\\Icons\\Achievement_PVP_A_A",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,
        -- On the minimap button's right-click menu.
        quick = {
            { text = "Show or hide", func = function() TogglePanel() end },
        },

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
