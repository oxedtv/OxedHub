-- ============================================================================
-- Mouseover Info (built-in OxedHub module)
-- A small panel for the unit under the mouse: name in class colour, level and
-- class, guild, what it is targeting and its quest lines. It follows the
-- cursor or sits where the player puts it, and can replace the game's own
-- unit tooltip. Ported from the author's SureahiRouge addon.
--
-- Secret-safe: in combat a unit's name, level, guild and quest text can be
-- secret. They are only handed to SetText (inside pcall), never compared,
-- tested or measured as strings; each line remembers itself whether it holds
-- something, so the layout never asks a FontString for its text.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local MAX_QUEST = 3

local DEFAULTS = {
    enabled         = false,  -- off until the player switches it on
    minimapButton   = true,
    anchor          = "cursor", -- "cursor" or "fixed"
    locked          = true,     -- fixed mode: false shows a sample to drag
    offsetX         = 66,
    offsetY         = -24,      -- under 0: below the cursor, over 0: above
    fontSize        = 12,
    scale           = 1,
    showBg          = false,
    bgAlpha         = 0.6,
    showBorder      = false,
    outline         = true,
    showInfo        = true,
    showGuild       = true,
    showTarget      = true,
    showQuests      = true,
    showQuestTitle  = true,
    hideGameTooltip = true,
    point = "BOTTOMRIGHT", x = -300, y = 200,
}

local settings
local running = false
local frame, optionsWindow
local minimapIcon, MinimapIcon, ShowOptions
local lines = {}

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

-- true, false, or nil when the answer is secret or the call failed.
local function Known(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or Secret(v) then return nil end
    return v and true or false
end

-- Show v on a line; nil clears it. The line keeps whether it has text.
-- Has a value at all? A secret counts as yes (it is never nil).
local function Has(v) return Secret(v) or v ~= nil end

-- Never "x and y or z" on a value that may be secret: testing it is the error.
local function Set(fs, v)
    if not Has(v) then
        fs:SetText("")
        fs.has = false
    elseif pcall(fs.SetText, fs, v) then
        fs.has = true
    else
        fs:SetText("")
        fs.has = false
    end
end

local function Fmt(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if ok then return s end
    return (...)
end

-- Quest title and objective lines from the unit's tooltip data.
local function QuestLines(unit)
    local out = {}
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit and Enum and Enum.TooltipDataLineType) then return out end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data or not data.lines then return out end
    local QT = Enum.TooltipDataLineType.QuestTitle
    local QO = Enum.TooltipDataLineType.QuestObjective
    local wantTitle = settings.showQuestTitle ~= false
    for _, line in ipairs(data.lines) do
        local ok, isQuest = pcall(function() return (wantTitle and line.type == QT) or line.type == QO end)
        if ok and isQuest == true then
            out[#out + 1] = line.leftText
            if #out >= MAX_QUEST then break end
        end
    end
    return out
end

-- ── Layout and look ─────────────────────────────────────────────────────────

local function Layout()
    local w, h, prev = 0, 0, nil
    for _, fs in ipairs(lines) do
        fs:ClearAllPoints()
        fs:SetShown(fs.has == true)
        if fs.has then
            if prev then
                fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
                h = h + 2
            else
                fs:SetPoint("TOPLEFT", 8, -7)
            end
            -- A secret text measures as a secret number: fall back to a guess.
            local okH, sh = pcall(function() local v = fs:GetStringHeight() return v + 0 end)
            local okW, sw = pcall(function() local v = fs:GetStringWidth() if v > w then return v end return w end)
            h = h + ((okH and type(sh) == "number") and sh or (settings.fontSize + 2))
            w = (okW and type(sw) == "number") and sw or math.max(w, 180)
            prev = fs
        end
    end
    frame:SetSize(math.max(60, w + 16), h + 14)
end

local function FollowCursor()
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale()
    x, y = x / s, y / s
    local us = UIParent:GetEffectiveScale() / s
    local sw, sh = UIParent:GetWidth() * us, UIParent:GetHeight() * us
    local w, h = frame:GetWidth(), frame:GetHeight()
    local ox, oy = settings.offsetX or 0, settings.offsetY or -24

    local left = x - w / 2 + ox
    local top
    if oy <= 0 then
        top = y + oy
        if top - h < 0 then top = y - oy + h end   -- no room below: above instead
    else
        top = y + oy + h
        if top > sh then top = y - oy end          -- no room above: below instead
    end
    if left < 0 then left = 0 elseif left + w > sw then left = sw - w end
    if top > sh then top = sh end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

local function ApplyStyle()
    if not frame then return end
    local flags = settings.outline and "OUTLINE" or ""
    for i, fs in ipairs(lines) do
        local size = settings.fontSize + (i == 1 and 2 or 0)
        if i > 4 then size = settings.fontSize - 1 end
        pcall(fs.SetFont, fs, STANDARD_TEXT_FONT, size, flags)
        fs:SetShadowOffset(settings.outline and 0 or 1, settings.outline and 0 or -1)
    end
    frame:SetScale(settings.scale or 1)
    frame:SetBackdropColor(0, 0, 0, settings.showBg and settings.bgAlpha or 0)
    frame:SetBackdropBorderColor(0.6, 0.6, 0.6, settings.showBorder and 1 or 0)
    frame:ClearAllPoints()
    if settings.anchor == "fixed" then
        frame:SetPoint(settings.point or "BOTTOMRIGHT", UIParent, settings.point or "BOTTOMRIGHT", settings.x or -300, settings.y or 200)
    else
        frame:SetPoint("CENTER")
    end
    Layout()
end

-- Is anything under the mouse? A secret answer counts as yes, so the panel
-- still shows in combat.
local function MouseoverExists()
    local v = Known(UnitExists, "mouseover")
    if v == nil then return true end
    return v
end

local function Moving()
    return settings.anchor == "fixed" and not settings.locked
end

-- ── Content ─────────────────────────────────────────────────────────────────

local function Update()
    if not frame then return end
    if not (running and settings.enabled) then frame:Hide() return end
    if Moving() then return end
    if not MouseoverExists() then frame:Hide() return end

    local unit = "mouseover"
    local okN, name = pcall(UnitName, unit)
    if okN then Set(frame.name, name) else Set(frame.name, nil) end

    local r, g, b = 1, 0.82, 0
    local okC, className, classToken = pcall(UnitClass, unit)
    if okC and not Secret(classToken) and classToken ~= nil and Known(UnitIsPlayer, unit) then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
        if c then r, g, b = c.r, c.g, c.b end
    end
    frame.name:SetTextColor(r, g, b)

    if settings.showInfo then
        local okL, lvl = pcall(UnitLevel, unit)
        local cls = ""
        if okC and Has(className) then cls = className end
        local lv = "?"
        if okL and Has(lvl) then lv = lvl end
        Set(frame.info, Fmt(T("Level %s %s"), lv, cls))
    else
        Set(frame.info, nil)
    end

    local guild
    if settings.showGuild and GetGuildInfo then
        local okG, gname = pcall(GetGuildInfo, unit)
        if okG then guild = gname end
    end
    if Has(guild) then Set(frame.guild, Fmt("<%s>", guild)) else Set(frame.guild, nil) end

    local tName
    if settings.showTarget then
        local okT, n = pcall(UnitName, "mouseovertarget")
        if okT then tName = n end
    end
    if Has(tName) then Set(frame.target, Fmt(T("Target: %s"), tName)) else Set(frame.target, nil) end

    local quests = {}
    if settings.showQuests then
        local ok, q = pcall(QuestLines, unit)
        if ok then quests = q end
    end
    for i = 1, MAX_QUEST do Set(frame.quest[i], quests[i]) end

    Layout()
    if settings.anchor == "cursor" then FollowCursor() end
    frame:Show()
end

local function SafeUpdate() pcall(Update) end

-- Fixed mode, unlocked: a sample panel to drag into place.
local function ApplyLock()
    if not frame then return end
    local moving = running and Moving()
    frame:EnableMouse(moving)
    if moving then
        Set(frame.name, T("Mouseover Info"))
        frame.name:SetTextColor(1, 0.82, 0)
        Set(frame.info, T("Drag to move. Lock it in the options."))
        for _, fs in ipairs({ frame.guild, frame.target, unpack(frame.quest) }) do Set(fs, nil) end
        ApplyStyle()
        frame:Show()
    else
        frame:Hide()
        ApplyStyle()
    end
end

local function Build()
    if frame then return end
    frame = CreateFrame("Frame", "OxedHubMouseoverInfo", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint(1)
        settings.point, settings.x, settings.y = p, x, y
    end)

    local function Line()
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs.has = false
        lines[#lines + 1] = fs
        return fs
    end
    frame.name   = Line()
    frame.info   = Line()
    frame.guild  = Line()
    frame.target = Line()
    frame.quest  = {}
    for i = 1, MAX_QUEST do
        frame.quest[i] = Line()
        frame.quest[i]:SetTextColor(0.75, 0.75, 0.75)
    end
    frame:Hide()

    -- Follow the cursor, and hide once the mouse leaves the unit.
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        if Moving() then return end
        if settings.anchor == "cursor" then FollowCursor() end
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        if not MouseoverExists() then self:Hide() end
    end)
end

-- Hide the game's own unit tooltip while this panel replaces it. Hooked once;
-- does nothing while the module is off.
local tooltipHooked = false
local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    local function MaybeHide(tt)
        if tt ~= GameTooltip or not (running and settings and settings.hideGameTooltip) then return end
        -- Only for units in the world, not unit frames' own tooltips owned elsewhere.
        if tt:GetOwner() ~= UIParent then return end
        tt:Hide()
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt) pcall(MaybeHide, tt) end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tt) pcall(MaybeHide, tt) end)
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", SafeUpdate)

local function Start()
    if running then return end
    running = true
    Build()
    HookTooltip()
    events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    ApplyLock()
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    if frame then frame:Hide() frame:EnableMouse(false) end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function Restyle()
    ApplyLock()
end

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Mouseover Info", 440, 690)
        optionsWindow = w
        w:AddChoice(settings, "anchor", "Position", {
            { value = "cursor", text = "Follow the cursor" },
            { value = "fixed",  text = "Fixed spot" },
        }, Restyle)
        w:AddCheckbox(settings, "locked", "Lock it (fixed spot)", nil, Restyle)
        w:AddSlider(settings, "offsetX", "Across from the cursor", -200, 200, 2, "%s: %d", Restyle)
        w:AddSlider(settings, "offsetY", "Below (under 0) or above the cursor", -200, 200, 2, "%s: %d", Restyle)
        w:AddSlider(settings, "fontSize", "Text size", 8, 20, 1, "%s: %d", Restyle)
        w:AddSlider(settings, "scale", "Size", 0.5, 2, 0.05, "%s: %.2f", Restyle)
        w:AddCheckbox(settings, "outline", "Outline the text", nil, Restyle)
        w:AddCheckbox(settings, "showBg", "Background", nil, Restyle)
        w:AddSlider(settings, "bgAlpha", "Background", 0, 1, 0.05, "%s: %.2f", Restyle)
        w:AddCheckbox(settings, "showBorder", "Border", nil, Restyle)
        w:AddCheckbox(settings, "showInfo", "Level and class")
        w:AddCheckbox(settings, "showGuild", "Guild")
        w:AddCheckbox(settings, "showTarget", "What it is targeting")
        w:AddCheckbox(settings, "showQuests", "Quest lines")
        w:AddCheckbox(settings, "showQuestTitle", "Quest titles with them")
        w:AddCheckbox(settings, "hideGameTooltip", "Hide the game's own tooltip for units in the world")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "mouseoverinfo", label = T("Mouseover Info"), icon = ICON, config = settings,
        hint = T("Click: options."),
        onClick = function() ShowOptions() end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.mouseoverinfo
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.mouseoverinfo = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if config.anchor ~= "cursor" and config.anchor ~= "fixed" then config.anchor = "cursor" end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "mouseoverinfo",
        name     = "Mouseover Info",
        version  = "1.0.0",
        updated  = 20261108.2,  -- new: panel for the unit under the mouse
        author   = "Oxed",
        category = "character",
        keywords = { "mouseover", "tooltip", "unit", "cursor", "guild", "target", "quest" },
        desc     = "A small panel for the unit under your mouse: name, level, guild, target and quests.",
        icon     = ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
