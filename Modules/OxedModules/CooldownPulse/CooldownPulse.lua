-- ============================================================================
-- Cooldown Pulse (built-in OxedHub module)
-- A spell's icon flashes in the middle of the screen the moment it comes off
-- cooldown, with a sound if one is chosen.
--
-- Spells are watched once you cast them: a cast whose cooldown is longer than
-- the minimum goes on the list, and leaves it when it pulses.
--
-- ⚠ Notes for whoever edits this next:
--   * Cooldowns can read back secret in combat. Every read is inside pcall and
--     checked with issecretvalue; when the live figure cannot be read, the end
--     time worked out at the cast is used (the cooldown then, or the spell's
--     base cooldown), so a pulse still comes, if a little early or late when
--     something shortened the cooldown in between.
--   * Nothing animates the frame's own alpha; the fade runs on its children.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on
    minCooldown = 8,       -- seconds; shorter cooldowns are not watched
    size        = 64,
    hold        = 0.6,     -- seconds the icon stays at full strength
    showName    = true,
    sound       = "",      -- an OxedHub sound id; empty: no sound
    inCombatOnly = false,
    x           = 0,
    y           = 120,
    -- "ignore" is a table and is built at login: a table in DEFAULTS would be
    -- shared by every character.
}

local PREFIX = "|cff00ccffOxedHub Cooldown Pulse:|r "
local GCD_SPELL = 61304    -- the global cooldown's own spell
local TICK = 0.1

local settings
local optionsWindow
local running = false
local watching = {}        -- [spellID] = time the cooldown should end
local queue = {}           -- spells waiting for their pulse
local pulse                -- the frame
local watcher = CreateFrame("Frame")

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- start, duration of a spell's cooldown, or nil when it cannot be read.
local function ReadCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
        if not ok or type(info) ~= "table" then return nil end
        local start, duration = Plain(info.startTime), Plain(info.duration)
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        return start, duration
    elseif GetSpellCooldown then
        local ok, start, duration = pcall(GetSpellCooldown, spellID)
        start, duration = ok and Plain(start), ok and Plain(duration)
        if type(start) ~= "number" or type(duration) ~= "number" then return nil end
        return start, duration
    end
    return nil
end

local function GcdLeft()
    local start, duration = ReadCooldown(GCD_SPELL)
    if not start or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

local function SpellInfo(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return Plain(info.name), Plain(info.iconID) end
    elseif GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, spellID)
        if ok then return Plain(name), Plain(icon) end
    end
    return nil
end

local function Ignored(spellID)
    if not settings.ignore then return false end
    if settings.ignore[spellID] then return true end
    local name = SpellInfo(spellID)
    return name ~= nil and settings.ignore[name:lower()] == true
end

-- ── The pulse ───────────────────────────────────────────────────────────────

local function Build()
    if pulse then return end
    pulse = CreateFrame("Frame", "OxedHubCooldownPulse", UIParent)
    pulse:SetFrameStrata("HIGH")
    pulse:Hide()

    -- Everything that fades sits on this child, not on the frame itself.
    local body = CreateFrame("Frame", nil, pulse)
    body:SetAllPoints()
    pulse.body = body
    pulse.icon = body:CreateTexture(nil, "ARTWORK")
    pulse.icon:SetAllPoints()
    pulse.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    pulse.name = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pulse.name:SetPoint("TOP", body, "BOTTOM", 0, -4)
    pulse.name:SetTextColor(1, 0.82, 0)
end

local function Place()
    pulse:ClearAllPoints()
    pulse:SetPoint("CENTER", UIParent, "CENTER", tonumber(settings.x) or 0, tonumber(settings.y) or 120)
    local size = tonumber(settings.size) or 64
    pulse:SetSize(size, size)
end

local FADE_IN, FADE_OUT = 0.15, 0.5
local shownAt                  -- GetTime() the current pulse began, or nil

local function ShowNext()
    local spellID = table.remove(queue, 1)
    if not spellID then
        shownAt = nil
        pulse:Hide()
        return
    end
    local name, icon = SpellInfo(spellID)
    pulse.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    pulse.name:SetText(settings.showName and name or "")
    Place()
    pulse.body:SetAlpha(0)
    pulse.body:SetScale(1)
    shownAt = GetTime()
    pulse:Show()
    if settings.sound and settings.sound ~= "" and OxedHub.ModuleAPI then
        OxedHub.ModuleAPI:PlaySound(settings.sound)
    end
end

local function Animate()
    if not shownAt then return end
    local t = GetTime() - shownAt
    local hold = tonumber(settings.hold) or 0.6
    local alpha, scale
    if t < FADE_IN then
        alpha, scale = t / FADE_IN, 1.4 - 0.4 * (t / FADE_IN)
    elseif t < FADE_IN + hold then
        alpha, scale = 1, 1
    elseif t < FADE_IN + hold + FADE_OUT then
        local p = (t - FADE_IN - hold) / FADE_OUT
        alpha, scale = 1 - p, 1 + 0.3 * p
    else
        return ShowNext()
    end
    pulse.body:SetAlpha(alpha)
    pulse.body:SetScale(scale)
end

local function Pulse(spellID)
    if settings.inCombatOnly and not InCombatLockdown() then return end
    Build()
    for _, queued in ipairs(queue) do
        if queued == spellID then return end
    end
    queue[#queue + 1] = spellID
    if not shownAt then ShowNext() end
end

-- ── Watching cooldowns ──────────────────────────────────────────────────────

local function Watch(spellID)
    if type(spellID) ~= "number" or Ignored(spellID) then return end
    local now = GetTime()
    local start, duration = ReadCooldown(spellID)
    local ends
    if start and duration and duration > 1.6 then
        ends = start + duration
    else
        -- Not readable, or not started yet this frame: the base cooldown.
        local okBase, base = pcall(GetSpellBaseCooldown or function() end, spellID)
        base = okBase and Plain(base)
        if type(base) == "number" and base > 0 then ends = now + base / 1000 end
    end
    if not ends or ends - now < (tonumber(settings.minCooldown) or 8) then return end
    watching[spellID] = ends
end

local since = 0
local function OnUpdate(_, elapsed)
    if shownAt then Animate() end
    since = since + elapsed
    if since < TICK then return end
    since = 0
    if not next(watching) then return end
    local now = GetTime()
    local gcd = GcdLeft()
    for spellID, ends in pairs(watching) do
        local start, duration = ReadCooldown(spellID)
        local ready
        if start then
            -- Live figure: ready once only the global cooldown is left.
            ready = duration == 0 or start + duration - now <= gcd + 0.05
            if not ready then watching[spellID] = start + duration end
        else
            ready = now >= ends
        end
        if ready then
            watching[spellID] = nil
            Pulse(spellID)
        end
    end
end

watcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        spellID = Plain(spellID)
        if type(spellID) ~= "number" then return end
        -- Next frame: the cooldown starts after the cast event.
        C_Timer.After(0.1, function()
            if running then Watch(spellID) end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(watching)
    end
end)

local function Start()
    if running then return end
    running = true
    Build()
    pcall(watcher.RegisterUnitEvent, watcher, "UNIT_SPELLCAST_SUCCEEDED", "player")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnUpdate", OnUpdate)
end

local function Stop()
    running = false
    watcher:UnregisterAllEvents()
    watcher:SetScript("OnUpdate", nil)
    wipe(watching)
    wipe(queue)
    shownAt = nil
    if pulse then pulse:Hide() end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function Test()
    if not settings then return end
    local was = settings.inCombatOnly
    settings.inCombatOnly = false
    Pulse(6603)   -- Auto Attack: a spell every character has
    settings.inCombatOnly = was
    if not running then watcher:SetScript("OnUpdate", OnUpdate) end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Cooldown Pulse", 460, 520)
        optionsWindow = w
        w:AddSlider(settings, "minCooldown", "Shortest cooldown watched, seconds", 2, 120, 1, "%s: %d")
        w:AddSlider(settings, "size", "Icon size", 32, 160, 4, "%s: %d")
        w:AddSlider(settings, "hold", "Seconds at full strength", 0.2, 3, 0.1, "%s: %.1f")
        w:AddSlider(settings, "x", "Left and right", -800, 800, 10, "%s: %d")
        w:AddSlider(settings, "y", "Up and down", -500, 500, 10, "%s: %d")
        w:AddCheckbox(settings, "showName", "Spell name under the icon")
        w:AddCheckbox(settings, "inCombatOnly", "Only in combat")
        w:AddSoundPicker(settings, "sound", "Sound", "None")
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(120, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
        test:SetText(L["Test"])
        test:SetScript("OnClick", Test)
        w.cursorY = w.cursorY - 32
        w:AddNote("A spell is watched once you cast it. /oxpulse ignore <spell name or ID> stops one from pulsing, /oxpulse unignore <spell> lets it again, /oxpulse list shows them.")
    end
    optionsWindow:Show()
end

-- ── Slash command ───────────────────────────────────────────────────────────

SLASH_OXEDCOOLDOWNPULSE1 = "/oxpulse"
SlashCmdList.OXEDCOOLDOWNPULSE = function(msg)
    if not settings then return end
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    local key = tonumber(arg) or (arg ~= "" and arg:lower()) or nil
    if cmd == "ignore" and key then
        settings.ignore[key] = true
        if type(key) == "number" then watching[key] = nil end
        print(PREFIX .. (L["%s will not pulse."]):format(arg))
    elseif cmd == "unignore" and key then
        settings.ignore[key] = nil
        print(PREFIX .. (L["%s pulses again."]):format(arg))
    elseif cmd == "list" then
        print(PREFIX .. L["Not pulsing:"])
        for k in pairs(settings.ignore) do print("   " .. tostring(k)) end
    elseif cmd == "test" then
        Test()
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
    local config = OxedHubDB.modules.cooldownpulse
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.cooldownpulse = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.ignore) ~= "table" then config.ignore = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "cooldownpulse",
        name     = "Cooldown Pulse",
        version  = "1.0.0",
        added    = 20261127,
        updated  = 20261127,
        author   = "Oxed",
        category = "combat",
        keywords = { "cooldown", "pulse", "flash", "ready", "spell", "icon", "sound", "doom" },
        desc     = "A spell's icon flashes mid-screen the moment it is ready again, with a sound.",
        icon     = "Interface\\Icons\\Spell_Holy_BorrowedTime",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.ignore) ~= "table" then settings.ignore = {} end
            Start()
        end,
        OnDisable = function()
            Stop()
        end,
    })
end)
