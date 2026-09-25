-- ============================================================================
-- Markers (built-in OxedHub module)
-- The marks a group leader reaches for, on screen instead of in a flyout:
--
--   raid marks    skull, cross, square, moon, triangle, diamond, star, circle
--                 on whatever you have targeted, and a button that clears it
--   world marks   the eight coloured flares on the ground, and clear them all
--   controls      ready check, role check and the pull countdown
--
-- ⚠ These are SECURE buttons. The game lets an addon press them, never do the
-- work itself, so every attribute is set once when the button is made, out of
-- combat. Two consequences, both of which the code below lives by:
--   * Nothing here changes an attribute after that, ever.
--   * A protected button cannot be shown or hidden in combat. Visibility
--     rules -- alone, no target, no assist -- are applied out of combat, and a
--     change asked for in combat waits for it to end.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    raidBar     = true,
    worldBar    = true,
    controls    = true,

    locked      = false,
    scale       = 1,
    size        = 30,      -- one button, in pixels
    spacing     = 4,
    columns     = 9,       -- a row of nine: eight marks and the clear button
    tooltips    = true,
    backdrop    = true,

    hideAlone   = false,   -- on, the bars keep out of the way while you are alone
    needTarget  = false,   -- only while you have something targeted
    needAssist  = false,   -- only while you may actually place a mark

    countdown   = 10,      -- seconds, left click
    countdown2  = 5,       -- seconds, right click

    -- Where each bar sits. Plain numbers, never a table: a table in DEFAULTS
    -- is copied by reference and every character would share one position.
    raidX = -220, raidY = -260,
    worldX = 220, worldY = -260,
    controlX = 0, controlY = -320,
}

local settings          -- OxedHubDB.modules.markers, bound at login
local optionsWindow
local bars = {}         -- raid, world, control
local watcher = CreateFrame("Frame")
local pending = false   -- a visibility change that combat got in the way of
local debugClicks = false

local PREFIX = "|cff00ccffOxedHub Markers:|r "

-- ── What the buttons look like ──────────────────────────────────────────────

local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"

-- The game's own names, so the tooltips read in the player's language.
local RAID_NAMES = {
    _G.RAID_TARGET_1 or "Star", _G.RAID_TARGET_2 or "Circle",
    _G.RAID_TARGET_3 or "Diamond", _G.RAID_TARGET_4 or "Triangle",
    _G.RAID_TARGET_5 or "Moon", _G.RAID_TARGET_6 or "Square",
    _G.RAID_TARGET_7 or "Cross", _G.RAID_TARGET_8 or "Skull",
}

-- The eight ground flares, in the game's order. Drawn as our own round glow
-- tinted to each colour rather than hunting for a Blizzard texture that moves
-- between builds.
local FLARE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Cursor\\glow"
local WORLD_COLOURS = {
    { 0.25, 0.45, 1.00 },   -- blue
    { 0.30, 0.90, 0.35 },   -- green
    { 0.70, 0.40, 1.00 },   -- purple
    { 1.00, 0.25, 0.25 },   -- red
    { 1.00, 0.95, 0.35 },   -- yellow
    { 1.00, 0.60, 0.15 },   -- orange
    { 0.45, 0.90, 1.00 },   -- cyan
    { 1.00, 1.00, 1.00 },   -- white
}

local function Tip(button, title, body)
    button:SetScript("OnEnter", function(self)
        if not (settings and settings.tooltips) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── Are we allowed to place a mark? ─────────────────────────────────────────

local function MayMark()
    if not IsInGroup or not IsInGroup() then return true end   -- alone: your own target
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then return true end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then return true end
    -- In a party, everyone may mark; in a raid it takes lead or assist.
    return not (IsInRaid and IsInRaid())
end

local function ShouldShow(kind)
    if not settings or settings.enabled == false then return false end
    if kind == "raid" and not settings.raidBar then return false end
    if kind == "world" and not settings.worldBar then return false end
    if kind == "control" and not settings.controls then return false end
    if settings.hideAlone and IsInGroup and not IsInGroup() then return false end
    if settings.needAssist and not MayMark() then return false end
    if settings.needTarget and kind ~= "control" and not UnitExists("target") then return false end
    return true
end

-- Why nothing is on screen, in one line, so switching the module on and
-- seeing an empty screen is never a mystery.
local function Explain()
    if not settings or settings.enabled == false then return end
    local reasons = {}
    if settings.hideAlone and IsInGroup and not IsInGroup() then
        reasons[#reasons + 1] = "you are not in a group"
    end
    if settings.needAssist and not MayMark() then
        reasons[#reasons + 1] = "you are not the leader or an assistant"
    end
    if settings.needTarget and not UnitExists("target") then
        reasons[#reasons + 1] = "you have nothing targeted"
    end
    if not (settings.raidBar or settings.worldBar or settings.controls) then
        reasons[#reasons + 1] = "all three bars are switched off"
    end
    if #reasons == 0 then return end
    print(PREFIX .. ("the bars are hidden because %s. Change that in Options, or type /oxmark.")
        :format(table.concat(reasons, " and ")))
end

-- World markers need a real group. A follower dungeon is not one: its
-- companions are NPCs, and the game answers "You aren't in a party". The
-- buttons dim rather than pretending, since dimming a texture is allowed in
-- combat where showing or hiding the button is not.
local function RefreshWorldButtons()
    local frame = bars.world
    if not frame then return end
    local allowed = IsInGroup and IsInGroup() and MayMark()
    for _, button in ipairs(frame.buttons) do
        local art = button.flare or button.dimmable
        if art then art:SetAlpha(allowed and 1 or 0.3) end
    end
end

local function ApplyVisibility()
    -- ⚠ A protected button cannot be shown or hidden while you are fighting.
    -- The change is remembered and made the moment combat ends.
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    for kind, frame in pairs(bars) do
        frame:SetShown(ShouldShow(kind))
    end
    RefreshWorldButtons()
end

-- ── Building a bar ──────────────────────────────────────────────────────────

local function SavePosition(frame)
    local point, _, _, x, y = frame:GetPoint(1)
    if not point then return end
    settings[frame.keyX], settings[frame.keyY] = x, y
    settings[frame.keyPoint] = point
end

local function PlaceBar(frame)
    frame:ClearAllPoints()
    local point = settings[frame.keyPoint] or "CENTER"
    frame:SetPoint(point, UIParent, point,
        tonumber(settings[frame.keyX]) or 0, tonumber(settings[frame.keyY]) or 0)
end

local function NewBar(kind, keyX, keyY)
    local frame = CreateFrame("Frame", "OxedHubMarkers" .. kind, UIParent, "BackdropTemplate")
    frame.kind, frame.keyX, frame.keyY, frame.keyPoint = kind, keyX, keyY, keyX .. "Point"
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not settings.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
    frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)
    frame.buttons = {}
    frame:Hide()
    bars[kind] = frame
    return frame
end

-- Buttons laid out in rows of settings.columns, in the order they were made.
local function Layout(frame)
    local size = tonumber(settings.size) or 30
    local gap = tonumber(settings.spacing) or 4
    local columns = math.max(1, math.min(16, tonumber(settings.columns) or 9))
    local pad = 6

    local shown = {}
    for _, button in ipairs(frame.buttons) do
        if button.wanted ~= false then shown[#shown + 1] = button end
    end

    for index, button in ipairs(shown) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT",
            pad + column * (size + gap), -(pad + row * (size + gap)))
        button:Show()
    end

    local rows = math.max(1, math.ceil(#shown / columns))
    local across = math.min(#shown, columns)
    frame:SetSize(pad * 2 + across * size + (across - 1) * gap,
        pad * 2 + rows * size + (rows - 1) * gap)
    frame:SetScale(tonumber(settings.scale) or 1)

    if settings.backdrop then
        frame:SetBackdropColor(0.04, 0.04, 0.06, 0.8)
        frame:SetBackdropBorderColor(0.35, 0.35, 0.4, 0.9)
    else
        frame:SetBackdropColor(0, 0, 0, 0)
        frame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

-- A secure button. Its attributes are set here, once, and never again: the
-- game refuses an attribute change in combat, and a half-changed button is
-- worse than one that always does the same thing.
local function SecureButton(frame, attributes)
    local button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    button:EnableMouse(true)
    -- Both edges, the way a working marker addon registers them.
    button:RegisterForClicks("AnyUp", "AnyDown")
    for key, value in pairs(attributes) do
        button:SetAttribute(key, value)
    end
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    -- ⚠ HookScript, never SetScript: the template's own OnClick is what runs
    -- the macro, and replacing it would take the button's whole job away.
    -- Silent unless /oxmark debug is on, so a button that seems to do nothing
    -- can be traced instead of guessed at.
    button:HookScript("OnClick", function(self, click, down)
        if not debugClicks then return end
        print(PREFIX .. ("click %s %s: type1=%s macrotext1=%s macrotext2=%s"):format(
            tostring(click), down and "down" or "up",
            tostring(self:GetAttribute("type1")),
            tostring(self:GetAttribute("macrotext1")),
            tostring(self:GetAttribute("macrotext2"))))
    end)

    frame.buttons[#frame.buttons + 1] = button
    return button
end

local function BuildRaidBar()
    local frame = NewBar("raid", "raidX", "raidY")

    for index = 1, 8 do
        -- "/tm N" is the game's own command for marking your target, and it
        -- works from a secure button in combat, where SetRaidTarget would not.
        local button = SecureButton(frame, { type1 = "macro", macrotext1 = ("/tm %d"):format(index) })
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture(RAID_ICON:format(index))
        Tip(button, RAID_NAMES[index] or ("Mark %d"):format(index),
            "Puts this mark on your target.")
    end

    local clear = SecureButton(frame, { type1 = "macro", macrotext1 = "/tm 0" })
    local icon = clear:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    Tip(clear, "Clear the mark", "Takes the mark off your target.")

    return frame
end

local function BuildWorldBar()
    local frame = NewBar("world", "worldX", "worldY")

    for index = 1, 8 do
        -- ⚠ Through the game's own commands, not the "worldmarker" attribute:
        -- that one did nothing at all when pressed, in a group or out of it.
        -- /wm puts the flare down, /cwm takes it away, and a secure macro
        -- button is allowed to run both in combat.
        local button = SecureButton(frame, {
            type1 = "macro", macrotext1 = ("/wm %d"):format(index),
            type2 = "macro", macrotext2 = ("/cwm %d"):format(index),
        })
        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER")
        icon:SetTexture(FLARE)
        icon:SetVertexColor(unpack(WORLD_COLOURS[index]))
        button.flare = icon
        Tip(button, ("World marker %d"):format(index),
            "Left click puts this flare where you are standing, right click takes it away. "
            .. "Dimmed means the game will refuse it: world markers need a real group, and in a raid "
            .. "the leader or an assistant. A follower dungeon does not count, since its companions are NPCs.")
    end

    local clear = SecureButton(frame, { type1 = "macro", macrotext1 = "/cwm all" })
    local icon = clear:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    clear.dimmable = icon
    Tip(clear, "Clear the flares", "Takes every world marker off the ground. A real group, and lead or assist, again.")

    return frame
end

-- The three controls are ordinary buttons: a ready check, a role check and a
-- countdown are all things an addon may ask for itself.
local function PlainButton(frame, texture, title, body, onClick)
    local button = CreateFrame("Button", nil, frame)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(texture)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", onClick)
    Tip(button, title, body)
    frame.buttons[#frame.buttons + 1] = button
    return button
end

local function BuildControlBar()
    local frame = NewBar("control", "controlX", "controlY")

    PlainButton(frame, "Interface\\Icons\\Spell_Holy_Rune", "Ready check",
        "Asks the group whether everyone is ready.", function()
            if not MayMark() then return print(PREFIX .. "only the leader or an assistant can do that.") end
            if DoReadyCheck then pcall(DoReadyCheck) end
        end)

    PlainButton(frame, "Interface\\Icons\\INV_Misc_GroupNeedMore", "Role check",
        "Asks everyone to name their role again.", function()
            if not MayMark() then return print(PREFIX .. "only the leader or an assistant can do that.") end
            if InitiateRolePoll then pcall(InitiateRolePoll) end
        end)

    PlainButton(frame, "Interface\\Icons\\INV_Misc_PocketWatch_01", "Countdown",
        "Left click starts the pull timer, right click the short one, shift click stops it.",
        function(_, button)
            if not (C_PartyInfo and C_PartyInfo.DoCountdown) then return end
            if not MayMark() then return print(PREFIX .. "only the leader or an assistant can do that.") end
            if IsShiftKeyDown() then
                pcall(C_PartyInfo.DoCountdown, 0)
                return
            end
            local seconds = button == "RightButton"
                and (tonumber(settings.countdown2) or 5)
                or (tonumber(settings.countdown) or 10)
            if seconds > 0 then pcall(C_PartyInfo.DoCountdown, seconds) end
        end)

    return frame
end

local function LayoutAll()
    if not settings then return end
    for _, frame in pairs(bars) do
        -- The flare is a round glow, so it is drawn a little inside the button.
        for _, button in ipairs(frame.buttons) do
            if button.flare then
                local size = (tonumber(settings.size) or 30) * 0.9
                button.flare:SetSize(size, size)
            end
        end
        Layout(frame)
        PlaceBar(frame)
    end
end

local function Build()
    if bars.raid then return end
    BuildRaidBar()
    BuildWorldBar()
    BuildControlBar()
    LayoutAll()
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then ApplyVisibility() end
        return
    end
    ApplyVisibility()
end)

local function Start()
    Build()
    C_Timer.After(1, Explain)
    for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_TARGET_CHANGED",
            "PLAYER_ENTERING_WORLD", "PARTY_LEADER_CHANGED", "PLAYER_REGEN_ENABLED",
            "PLAYER_ROLES_ASSIGNED" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    ApplyVisibility()
end

local function Stop()
    watcher:UnregisterAllEvents()
    if InCombatLockdown() then
        -- Hiding a protected frame now is refused; it goes when combat ends.
        pending = true
        watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, frame in pairs(bars) do frame:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.markers
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.markers = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end

    -- ⚠ Once, for anyone who already has this module saved: the hiding rules
    -- used to be on by default, so switching the module on showed nothing at
    -- all and looked broken. They are cleared here one time; whatever the
    -- player sets afterwards is left alone.
    if not config.hidingSeen then
        config.hidingSeen = true
        config.hideAlone, config.needAssist, config.needTarget = false, false, false
    end

    settings = config
end

local function Redraw()
    LayoutAll()
    ApplyVisibility()
end

-- A labelled slider bound to one number.
local function AddSlider(w, key, caption, minValue, maxValue, step, format)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(200, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 250, w.cursorY - 5)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    local refreshing = false
    local function Show(value) label:SetText((format):format(caption, value)) end
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing then return end
        settings[key] = value
        Redraw()
    end)
    w:HookScript("OnShow", function()
        refreshing = true
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
        refreshing = false
    end)
    w.cursorY = w.cursorY - 30
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Markers", 500, 620)
        local w = optionsWindow

        w:AddCheckbox(settings, "raidBar", "Raid marks", "Skull, cross and the rest, for your target.", Redraw)
        w:AddCheckbox(settings, "worldBar", "World marks", "The eight coloured flares on the ground.", Redraw)
        w:AddCheckbox(settings, "controls", "Ready check, role check and countdown", nil, Redraw)

        w:AddCheckbox(settings, "locked", "Lock the bars in place",
            "Unlocked, drag any bar with the left button.")
        w:AddCheckbox(settings, "backdrop", "Show the panel behind the buttons", nil, Redraw)
        w:AddCheckbox(settings, "tooltips", "Tooltips")

        AddSlider(w, "size", "Button size", 16, 64, 1, "%s: %d")
        AddSlider(w, "spacing", "Space between", 0, 16, 1, "%s: %d")
        AddSlider(w, "columns", "Buttons in a row", 1, 9, 1, "%s: %d")
        AddSlider(w, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f")

        w:AddCheckbox(settings, "hideAlone", "Hide while you are on your own",
            "On, the bars only appear once you are in a group. Off, they are always there.", Redraw)
        w:AddCheckbox(settings, "needAssist", "Hide when you may not mark",
            "In a raid the marks only work for the leader and assistants.", Redraw)
        w:AddCheckbox(settings, "needTarget", "Show the marks only with a target", nil, Redraw)

        AddSlider(w, "countdown", "Countdown, left click", 0, 30, 1, "%s: %d s")
        AddSlider(w, "countdown2", "Countdown, right click", 0, 30, 1, "%s: %d s")

        w:AddNote("Nothing on screen? One of the three boxes above is hiding the bars. /oxmark show turns all three off.")
        w:AddNote("A world marker goes down where you stand: left click sets it, right click clears that one, and the last button clears them all. The game refuses all of it outside a group, and in a raid for anyone who is neither the leader nor an assistant.")
        w:AddNote("Shift click the countdown to stop one that is running.")
        w:AddNote("The buttons are secure ones, which the game will not let an addon show or hide during a fight: a bar that should appear or disappear does so the moment combat ends.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBMARKERS1 = "/oxmark"
SlashCmdList.OXEDHUBMARKERS = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()
    if msg == "lock" then
        settings.locked = not settings.locked
        print(PREFIX .. (settings.locked and "bars locked." or "bars unlocked, drag them where you like."))
        return
    end
    if msg == "show" then
        settings.hideAlone, settings.needAssist, settings.needTarget = false, false, false
        Redraw()
        print(PREFIX .. "every bar is on screen now; the hiding rules are off.")
        return
    end
    -- Where each bar thinks it is, for a bar that is on but not to be seen.
    if msg == "debug" then
        debugClicks = not debugClicks
        print(PREFIX .. (debugClicks and "click tracing on: press a marker button."
            or "click tracing off."))
        return
    end
    if msg == "where" then
        for _, kind in ipairs({ "raid", "world", "control" }) do
            local frame = bars[kind]
            if not frame then
                print(PREFIX .. kind .. ": not built.")
            else
                local point, _, _, x, y = frame:GetPoint(1)
                print(PREFIX .. ("%s: %s, %d buttons, %dx%d at %s %d, %d, alpha %.1f")
                    :format(kind, frame:IsShown() and "|cff40ff40shown|r" or "|cffff5555hidden|r",
                        #frame.buttons, frame:GetWidth() or 0, frame:GetHeight() or 0,
                        tostring(point), x or 0, y or 0, frame:GetAlpha()))
            end
        end
        return
    end
    if msg == "reset" then
        for _, key in ipairs({ "raidX", "raidY", "worldX", "worldY", "controlX", "controlY" }) do
            settings[key] = DEFAULTS[key]
        end
        for _, frame in pairs(bars) do settings[frame.keyPoint] = nil end
        LayoutAll()
        print(PREFIX .. "bars put back where they started.")
        return
    end
    ShowOptions()
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
        id       = "markers",
        name     = "Markers",
        version  = "1.0.0",
        author   = "Oxed",
        category = "combat",
        keywords = { "marker", "markers", "raid marks", "skull", "world marker", "flare",
            "ready check", "role check", "countdown", "pull timer" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Raid marks, world flares, ready check and a pull timer on screen. Type /oxmark.",
        icon     = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
