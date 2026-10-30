-- ============================================================================
-- Trinket Ready (built-in OxedHub module)
-- A sound, and a line on screen, the moment an on-use trinket comes off
-- cooldown. Passive trinkets have no cooldown and never announce.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile
local print = OxedHub.Print or print

local DEFAULTS = {
    enabled    = false,   -- off until the player switches it on
    slot13     = true,    -- top trinket
    slot14     = true,    -- bottom trinket
    sound      = "",      -- an OxedHub sound id; empty plays the game's raid warning
    onScreen   = true,    -- the trinket's icon and name on screen
    alertStyle = "both",  -- "both", "icon" or "text"
    -- alertColour: { r, g, b } of the text, made after binding (never a table here)
    alertScale = 100,     -- percent
    alertTime  = 3,       -- seconds it stays up
    alertOffX  = 0,       -- its centre, from the middle of the screen (UIParent units)
    alertOffY  = 150,
    chat       = false,   -- and a line in chat
    combatOnly = false,   -- stay quiet out of a fight
}

local SLOTS = { 13, 14 }
local MIN_COOLDOWN = 2    -- seconds; anything shorter is the global cooldown
local POLL = 0.2          -- seconds between looks while a trinket is cooling down
local FADE = 0.6          -- seconds the alert takes to fade out
local ROW = 42            -- height of one trinket's line in the alert

local settings
local optionsWindow
local ticker
local alert               -- the on-screen alert, built the first time it is needed
local previewing = false  -- options open: the alert stays up as a box to drag
local positionSliders = {} -- the options window's left/right and up/down, refreshed after a drag
local Update              -- forward: the ticker and the events both call it
local state = {}          -- [slot] = { link = item link, readyAt = GetTime() it is due back }
local cooldownOf = {}     -- [item link] = seconds of its cooldown, last time the game said
local eventFrame = CreateFrame("Frame")

-- When the trinket in a slot is next usable: 0 if it is ready now, the
-- GetTime() it comes back otherwise, nil if the game will not say. The
-- second value is the cooldown's full length, when there is one.
-- ⚠ In a fight the cooldown can come back secret, and comparing a secret is
-- an error: the pcall turns that into nil, and Update falls back on the time
-- it saw last, or the one OnCast worked out.
local function ReadyAt(slot)
    local ok, start, duration, enable = pcall(GetInventoryItemCooldown, "player", slot)
    if not ok then return nil end
    local okCompare, readyAt, length = pcall(function()
        -- Not counting down yet (the effect is still running): no answer.
        if enable == 0 or enable == false then return nil end
        if not start or start <= 0 or not duration or duration < MIN_COOLDOWN then return 0 end
        return start + duration, duration
    end)
    if okCompare then return readyAt, length end
    return nil
end

-- Only trinkets with a "Use:" effect. A passive one ("Equip: chance on hit")
-- still reports cooldowns, the 30 seconds after equipping and its own proc
-- cooldown, and announced as if it could be pressed. The game names the use
-- spell of an on-use item only; nil means passive.
local onUseOf = {}        -- [item link] = true / false
local function HasUse(link)
    if not link then return false end
    local known = onUseOf[link]
    if known ~= nil then return known end
    local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not fn then return true end
    local ok, name, spellID = pcall(fn, link)
    if not ok then return false end
    if issecretvalue and (issecretvalue(name) or issecretvalue(spellID)) then return false end
    local use = (name ~= nil or spellID ~= nil)
    -- Item data not loaded yet answers nil too: only remember a yes, or a no
    -- once the item itself is known.
    local loaded = not (C_Item and C_Item.IsItemDataCachedByID) or C_Item.IsItemDataCachedByID(link)
    if use or loaded then onUseOf[link] = use end
    return use
end

local function SlotWanted(slot)
    return settings[slot == 13 and "slot13" or "slot14"]
        and HasUse(GetInventoryItemLink("player", slot))
end

-- ── The on-screen alert ────────────────────────────────────────────────────
-- The trinket's icon and name, one line each, where the player put it.
-- The position is kept in UIParent units; SetPoint offsets are in the
-- frame's own (scaled) units, hence the division by the scale.
local function PlaceAlert()
    local scale = (settings.alertScale or 100) / 100
    alert:SetScale(scale)
    alert:ClearAllPoints()
    alert:SetPoint("CENTER", UIParent, "CENTER",
        (settings.alertOffX or 0) / scale, (settings.alertOffY or 150) / scale)
end

local function BuildAlert()
    if alert then return end
    alert = CreateFrame("Frame", "OxedHubTrinketReadyAlert", UIParent)
    alert:SetSize(320, ROW)
    alert:SetFrameStrata("HIGH")
    alert:SetClampedToScreen(true)
    alert:SetMovable(true)
    alert:EnableMouse(false)
    alert:RegisterForDrag("LeftButton")
    alert:SetScript("OnDragStart", alert.StartMoving)
    alert:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local scale = self:GetScale()
        local x, y = self:GetCenter()
        local midX, midY = UIParent:GetCenter()
        settings.alertOffX = math.floor(x * scale - midX + 0.5)
        settings.alertOffY = math.floor(y * scale - midY + 0.5)
        PlaceAlert()
        for _, slider in ipairs(positionSliders) do slider.Refresh() end
    end)

    -- Seen only while previewing: where it is, and that it can be dragged.
    alert.box = alert:CreateTexture(nil, "BACKGROUND")
    alert.box:SetAllPoints()
    alert.box:SetColorTexture(0, 0.6, 1, 0.25)
    alert.hint = alert:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    alert.hint:SetPoint("BOTTOM", alert, "TOP", 0, 2)
    alert.hint:SetText(L["Drag to move"])

    alert.rows = {}
    for i = 1, #SLOTS do
        local row = CreateFrame("Frame", nil, alert)
        row:SetHeight(ROW - 2)
        row:SetPoint("TOP", alert, "TOP", 0, -(i - 1) * ROW)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(36, 36)
        row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        alert.rows[i] = row
    end

    alert:SetScript("OnUpdate", function(self)
        if previewing then return end
        local left = (self.hideAt or 0) - GetTime()
        if left <= 0 then
            self:Hide()
        else
            self:SetAlpha(left < FADE and left / FADE or 1)
        end
    end)
    alert:Hide()
end

-- Fills the alert with one line per trinket and shows it for alertTime.
-- Each line is the icon, the text, or both (alertStyle), the text in the
-- player's colour: the plain name, without the link's quality colour.
local function ShowAlert(entries)
    BuildAlert()
    local style = settings.alertStyle or "both"
    local showIcon, showText = style ~= "text", style ~= "icon"
    local c = type(settings.alertColour) == "table" and settings.alertColour or { 1, 0.82, 0 }
    local widest = 0
    for i, row in ipairs(alert.rows) do
        local entry = entries[i]
        if entry then
            local name = entry.link and entry.link:match("%[(.-)%]") or L["Trinket"]
            row.icon:SetTexture(entry.icon or 134400)  -- the question mark icon
            row.icon:SetShown(showIcon)
            row.text:SetShown(showText)
            row.text:ClearAllPoints()
            if showIcon then
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
            else
                row.text:SetPoint("LEFT", row, "LEFT", 0, 0)
            end
            row.text:SetText((L["%s is ready."]):format(name))
            row.text:SetTextColor(c[1] or 1, c[2] or 0.82, c[3] or 0)
            local width = (showIcon and 36 or 0) + (showIcon and showText and 8 or 0)
                + (showText and row.text:GetStringWidth() or 0)
            row:SetWidth(width)
            widest = math.max(widest, width)
            row:Show()
        else
            row:Hide()
        end
    end
    alert:SetWidth(math.max(44, widest + 8))
    alert:SetHeight(math.max(1, math.min(#entries, #alert.rows)) * ROW)
    alert.hideAt = GetTime() + (settings.alertTime or 3)
    alert:SetAlpha(1)
    PlaceAlert()
    alert:Show()
end

local function WornTrinkets()
    local entries = {}
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link and HasUse(link) then entries[#entries + 1] = { link = link, icon = GetInventoryItemTexture("player", slot) } end
    end
    if #entries == 0 then entries[1] = { link = nil } end
    return entries
end

-- Options open: the alert stays up, tinted, and can be dragged into place.
-- ⚠ Raised above every window while it is: on HIGH it sat under OxedHub's
-- own main window (DIALOG), and the player never saw the box to drag.
local function SetPreview(on)
    previewing = on
    BuildAlert()
    alert:SetFrameStrata(on and "FULLSCREEN_DIALOG" or "HIGH")
    alert:EnableMouse(on)
    alert.box:SetShown(on)
    alert.hint:SetShown(on)
    if on then
        ShowAlert(WornTrinkets())
    else
        alert:Hide()
    end
end

local function Announce(links)
    if settings.combatOnly and not InCombatLockdown() then return end
    local API = OxedHub.ModuleAPI
    if not (API and API:PlaySound(settings.sound)) and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
    if settings.onScreen then ShowAlert(links) end
    if settings.chat then
        for _, entry in ipairs(links) do
            print((L["%s is ready."]):format(entry.link or L["Trinket"]))
        end
    end
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

Update = function()
    if not (settings and settings.enabled) then return end
    local ready, cooling = {}, false
    local now = GetTime()
    for _, slot in ipairs(SLOTS) do
        local s = state[slot]
        if not s then s = {}; state[slot] = s end
        local link = GetInventoryItemLink("player", slot)
        -- A different trinket in the slot: whatever was counting is not its.
        if link ~= s.link then
            s.link, s.readyAt, s.pressedAt = link, nil, nil
        end
        if link and SlotWanted(slot) then
            local readyAt, length = ReadyAt(slot)
            -- Just pressed: the game may not have started the cooldown yet,
            -- and "ready" then is the press, not the trinket coming back.
            if readyAt == 0 and s.pressedAt and now - s.pressedAt < 1 then readyAt = nil end
            local due = s.readyAt and (readyAt == 0 or (readyAt == nil and now >= s.readyAt))
            if due then
                s.readyAt = nil
                ready[#ready + 1] = { link = link, icon = GetInventoryItemTexture("player", slot) }
            elseif readyAt and readyAt > 0 then
                s.readyAt = readyAt
                cooldownOf[link] = length
            end
            if s.readyAt then cooling = true end
        else
            s.readyAt = nil
        end
    end
    if #ready > 0 then Announce(ready) end
    -- Poll only while something is counting down; the events notice it start.
    if cooling then
        if not ticker then ticker = C_Timer.NewTicker(POLL, Update) end
    else
        StopTicker()
    end
end

-- A trinket pressed in a fight, while its cooldown reads secret: time it
-- from the press, with the length seen the last time it could be read.
-- Update ignores a "ready" read for a moment after the press (pressedAt):
-- the game may not have started the cooldown yet.
local function OnCast(spellID)
    if not spellID or (issecretvalue and issecretvalue(spellID)) then return end
    if not (C_Item and C_Item.GetItemSpell) then return end
    local now = GetTime()
    for _, slot in ipairs(SLOTS) do
        local s = state[slot]
        local length = s and s.link and cooldownOf[s.link]
        if length and not (s.readyAt and s.readyAt > now) and SlotWanted(slot) then
            local ok, _, useSpell = pcall(C_Item.GetItemSpell, s.link)
            if ok and useSpell == spellID then
                s.readyAt, s.pressedAt = now + length, now
                if not ticker then ticker = C_Timer.NewTicker(POLL, Update) end
            end
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnCast(spellID)
        return
    end
    Update()
end)

local function Start()
    -- Trinkets already cooling down at switch-on still announce; nothing
    -- counted before then is remembered.
    wipe(state)
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    Update()
end

local function Stop()
    eventFrame:UnregisterAllEvents()
    StopTicker()
    wipe(state)
    if alert and not previewing then alert:Hide() end
end

-- Plays the chosen sound and names the trinkets worn, as if they came back.
local function Test()
    local links = WornTrinkets()
    local combatOnly = settings.combatOnly
    settings.combatOnly = false
    Announce(links)
    settings.combatOnly = combatOnly
end

local function Button(w, text, x, onClick)
    local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    button:SetPoint("TOPLEFT", w, "TOPLEFT", x, w.cursorY - 2)
    button:SetText(L[text])
    button:SetScript("OnClick", onClick)
    return button
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Trinket Ready", 440, 570)
        optionsWindow = w
        local function Replace() if alert then PlaceAlert() end end
        -- Style and colour show at once on the preview box.
        local function Redraw() if previewing then ShowAlert(WornTrinkets()) end end
        w:AddCheckbox(settings, "slot13", "Top trinket", nil, function() Update() end)
        w:AddCheckbox(settings, "slot14", "Bottom trinket", nil, function() Update() end)
        w:AddCheckbox(settings, "onScreen", "Show it on screen")
        w:AddChoice(settings, "alertStyle", "Show", {
            { value = "both", text = "Icon and name" },
            { value = "icon", text = "Icon only" },
            { value = "text", text = "Name only" },
        }, Redraw)
        w:AddColour(settings, "alertColour", "Text colour", Redraw)
        w:AddSlider(settings, "alertScale", "Size", 50, 200, 10, "%s: %d%%", Replace)
        positionSliders[1] = w:AddSlider(settings, "alertOffX", "Left / right", -1000, 1000, 5, "%s: %d", Replace)
        positionSliders[2] = w:AddSlider(settings, "alertOffY", "Down / up", -600, 600, 5, "%s: %d", Replace)
        w:AddSlider(settings, "alertTime", "Stays up", 1, 10, 1, "%s: %d sec")
        w:AddCheckbox(settings, "chat", "Say it in chat")
        w:AddCheckbox(settings, "combatOnly", "Only in a fight")
        w:AddSoundPicker(settings, "sound", "Sound", "Raid warning")
        Button(w, "Test it", 20, Test)
        Button(w, "Reset position", 190, function()
            settings.alertOffX, settings.alertOffY = DEFAULTS.alertOffX, DEFAULTS.alertOffY
            Replace()
            for _, slider in ipairs(positionSliders) do slider.Refresh() end
        end)
        w.cursorY = w.cursorY - 32
        w:AddNote("While this window is open, drag the blue box or use the sliders to place the alert.")
        w:AddNote("Only trinkets you press have a cooldown. Passive ones never announce.")
        w:HookScript("OnShow", function() SetPreview(true) end)
        w:HookScript("OnHide", function() SetPreview(false) end)
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.trinketready
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.trinketready = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.alertColour) ~= "table" then config.alertColour = { 1, 0.82, 0 } end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "trinketready",
        name     = "Trinket Ready",
        version  = "1.2.1",
        updated  = 20261030.6,  -- passive (Equip:) trinkets never announce
        author   = "Oxed",
        category = "combat",
        keywords = { "trinket", "cooldown", "ready", "alert", "sound" },
        desc     = "A sound and a line on screen the moment an on-use trinket is ready again.",
        icon     = "Interface\\Icons\\INV_Jewelry_TrinketPVP_01",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        quick = { { text = L["Test it"], func = function() Test() end } },
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
