-- ============================================================================
-- BubbleChat (built-in OxedHub module)
-- Chat bubbles your way: the font (a set of Google Fonts with Cyrillic, the
-- game's own, and OxedHub's), its size, outline and shadow; the bubble's
-- look (Blizzard, dark, OxedHub stone or text only), its tail and its scale;
-- and bubbles switched off where you do not want them -- dungeons, raids,
-- battlegrounds, arenas -- and back on when you leave.
--
-- ⚠ Bubbles inside instances are forbidden frames: no addon may touch them.
-- The font still applies there (it is the game's shared bubble font); the
-- look and the scale only apply to bubbles in the open world.
--
-- ⚠ The bubble setting is the player's own game option. Before changing it
-- for an instance, their value is saved, and it is put back on leaving the
-- instance and when the module is switched off.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    font        = "default",
    size        = 14,
    outline     = "OUTLINE",
    shadow      = true,

    style       = "dark",  -- blizzard / dark / stone / clear
    tail        = true,    -- the little point under a Blizzard bubble
    scale       = 1,

    hideDungeon = false,
    hideRaid    = false,
    hidePvP     = false,
    hideArena   = false,
    hideDelve   = false,
}

local PREFIX = "|cff00ccffOxedHub BubbleChat:|r "
local settings
local optionsWindow, fontPicker
local running = false

-- ── Fonts ───────────────────────────────────────────────────────────────────
-- Google Fonts (all under the SIL Open Font License, which allows shipping
-- them in an addon; each has Cyrillic), then the game's own, then the ones
-- OxedHub already carries. A file that is missing is left out of the list.

local GF = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\Bubble\\"
local OX = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"

local FONTS = {
    { key = "default",     name = "Game default" },
    { key = "montserrat",  name = "Montserrat",      path = GF .. "Montserrat.ttf" },
    { key = "rubik",       name = "Rubik",           path = GF .. "Rubik.ttf" },
    { key = "nunito",      name = "Nunito",          path = GF .. "Nunito.ttf" },
    { key = "comfortaa",   name = "Comfortaa",       path = GF .. "Comfortaa.ttf" },
    { key = "ptsans",      name = "PT Sans",         path = GF .. "PTSans-Regular.ttf" },
    { key = "oswald",      name = "Oswald",          path = GF .. "Oswald.ttf" },
    { key = "exo2",        name = "Exo 2",           path = GF .. "Exo2.ttf" },
    { key = "firasans",    name = "Fira Sans",       path = GF .. "FiraSans-Regular.ttf" },
    { key = "russoone",    name = "Russo One",       path = GF .. "RussoOne-Regular.ttf" },
    { key = "lobster",     name = "Lobster",         path = GF .. "Lobster-Regular.ttf" },
    { key = "marckscript", name = "Marck Script",    path = GF .. "MarckScript-Regular.ttf" },
    { key = "pressstart",  name = "Press Start 2P",  path = GF .. "PressStart2P-Regular.ttf" },
    { key = "friz",        name = "Friz Quadrata (game)", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arialn",      name = "Arial Narrow (game)",  path = "Fonts\\ARIALN.TTF" },
    { key = "morpheus",    name = "Morpheus (game)",      path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri",      name = "Skurri (game)",        path = "Fonts\\SKURRI.TTF" },
    { key = "darling",     name = "Darling Charm",   path = OX .. "Darling Charm.otf" },
    { key = "mustard",     name = "Mustard Nebula",  path = OX .. "Mustard Nebula.otf" },
}

local fontByKey = {}
for _, f in ipairs(FONTS) do fontByKey[f.key] = f end

-- Whether a font file loads, asked once each with a hidden string.
local probe
local loads = {}
local function FontLoads(path)
    if not path then return true end
    if loads[path] ~= nil then return loads[path] end
    if not probe then
        local holder = CreateFrame("Frame")
        holder:Hide()
        probe = holder:CreateFontString(nil, "OVERLAY")
    end
    -- A file that fails to load leaves the font string on the font it had,
    -- so the probe starts from the game's and checks what it holds after.
    pcall(probe.SetFont, probe, STANDARD_TEXT_FONT, 12, "")
    local ok, result = pcall(probe.SetFont, probe, path, 12, "")
    local now = probe:GetFont()
    local function Same(a, b)
        return type(a) == "string" and type(b) == "string"
            and a:gsub("/", "\\"):lower() == b:gsub("/", "\\"):lower()
    end
    loads[path] = ok and result ~= false and Same(now, path)
    return loads[path]
end

local defaultFont, defaultSize, defaultFlags
local function RememberDefault()
    if defaultFont or not ChatBubbleFont then return end
    defaultFont, defaultSize, defaultFlags = ChatBubbleFont:GetFont()
end

local function FontPath(key)
    local f = fontByKey[key]
    if f and f.path and FontLoads(f.path) then return f.path end
    return defaultFont
end

-- ── The bubble font ─────────────────────────────────────────────────────────

local function ApplyFont()
    if not ChatBubbleFont then return end
    RememberDefault()
    if not running then return end
    local flags = settings.outline or ""
    local size = tonumber(settings.size) or defaultSize or 14
    pcall(ChatBubbleFont.SetFont, ChatBubbleFont, FontPath(settings.font) or defaultFont, size, flags)
    if settings.shadow then
        ChatBubbleFont:SetShadowOffset(1, -1)
        ChatBubbleFont:SetShadowColor(0, 0, 0, 1)
    else
        ChatBubbleFont:SetShadowOffset(0, 0)
    end
end

local function RestoreFont()
    if ChatBubbleFont and defaultFont then
        pcall(ChatBubbleFont.SetFont, ChatBubbleFont, defaultFont, defaultSize, defaultFlags)
        ChatBubbleFont:SetShadowOffset(1, -1)
    end
end

-- ── Bubbles in instances ────────────────────────────────────────────────────

local function GetBubbleCVar()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    return get and get("chatBubbles")
end

local function SetBubbleCVar(value)
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    if set then pcall(set, "chatBubbles", value) end
end

-- Should bubbles be off where the player is now?
local function HideHere()
    local inside, kind = IsInInstance()
    if not inside then return false end
    if kind == "party" then return settings.hideDungeon end
    if kind == "raid" then return settings.hideRaid end
    if kind == "pvp" then return settings.hidePvP end
    if kind == "arena" then return settings.hideArena end
    if kind == "scenario" then return settings.hideDelve end
    return false
end

local function UpdateInstanceBubbles()
    if not running then return end
    if HideHere() then
        local now = GetBubbleCVar()
        -- The player's own value, kept before the first change.
        if settings.savedBubbles == nil then settings.savedBubbles = now end
        if now ~= "0" then SetBubbleCVar("0") end
    elseif settings.savedBubbles ~= nil then
        if GetBubbleCVar() ~= settings.savedBubbles then SetBubbleCVar(settings.savedBubbles) end
        settings.savedBubbles = nil
    end
end

local function RestoreInstanceBubbles()
    if settings and settings.savedBubbles ~= nil then
        SetBubbleCVar(settings.savedBubbles)
        settings.savedBubbles = nil
    end
end

-- ── The bubble's look ───────────────────────────────────────────────────────

local STYLE_COLOURS = {
    dark  = { bg = { 0.02, 0.02, 0.03, 0.82 }, edge = { 1, 0.82, 0, 0.55 } },
    stone = { bg = { 0.10, 0.095, 0.085, 0.94 }, edge = { 0.55, 0.45, 0.30, 0.95 } },
}

-- Our background, behind the text, for the dark and stone looks.
local function OwnBackdrop(frame)
    local bg = frame.oxedBubbleBg
    if bg then return bg end
    bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    bg:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
    bg:EnableMouse(false)
    frame.oxedBubbleBg = bg
    return bg
end

local function PaintBackdrop(bg, style)
    local c = STYLE_COLOURS[style]
    if not c then return end
    if style == "stone" then
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    else
        bg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    end
    bg:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], c.bg[4])
    bg:SetBackdropBorderColor(c.edge[1], c.edge[2], c.edge[3], c.edge[4])
end

-- Blizzard's art on a bubble: its textures and its nine-slice frame. The
-- text is a font string and is never among them.
local function SetBlizzardArt(frame, shown)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(shown and 1 or 0)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= frame.oxedBubbleBg then child:SetAlpha(shown and 1 or 0) end
    end
end

local function SkinBubble(bubble)
    if not bubble or (bubble.IsForbidden and bubble:IsForbidden()) then return end
    local frame = bubble:GetChildren()
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end

    local style = running and settings.style or "blizzard"
    local scale = running and (tonumber(settings.scale) or 1) or 1
    local tail = not running or settings.tail ~= false
    if frame.oxedStyle == style and frame.oxedScale == scale and frame.oxedTail == tail then return end
    frame.oxedStyle, frame.oxedScale, frame.oxedTail = style, scale, tail

    frame:SetScale(scale)
    if style == "blizzard" then
        SetBlizzardArt(frame, true)
        if frame.Tail then frame.Tail:SetShown(tail) end
        if frame.oxedBubbleBg then frame.oxedBubbleBg:Hide() end
        return
    end

    SetBlizzardArt(frame, false)
    if style == "clear" then
        if frame.oxedBubbleBg then frame.oxedBubbleBg:Hide() end
        return
    end
    local bg = OwnBackdrop(frame)
    PaintBackdrop(bg, style)
    bg:Show()
end

-- Every bubble in the open world (instance ones are forbidden and not
-- handed out).
local function SkinAll()
    if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles, false)
    if not ok or type(list) ~= "table" then return end
    for _, bubble in ipairs(list) do pcall(SkinBubble, bubble) end
end

-- A bubble appears the frame after its chat line; one look a moment later
-- covers a burst of lines.
local skinQueued = false
local function RunSkin()
    skinQueued = false
    SkinAll()
end
local function QueueSkin()
    if skinQueued then return end
    -- The Blizzard look at scale 1 needs no work at all.
    if settings.style == "blizzard" and (tonumber(settings.scale) or 1) == 1 and settings.tail ~= false then return end
    skinQueued = true
    C_Timer.After(0.05, RunSkin)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local watcher = CreateFrame("Frame")
local BUBBLE_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
}
local PLACE_EVENTS = { "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_DISABLED", "ZONE_CHANGED_NEW_AREA" }

local isPlace = {}
for _, e in ipairs(PLACE_EVENTS) do isPlace[e] = true end

watcher:SetScript("OnEvent", function(_, event)
    if not running then return end
    if isPlace[event] then
        UpdateInstanceBubbles()
        ApplyFont()
    else
        QueueSkin()
    end
end)

local function Start()
    if running then return end
    running = true
    for _, event in ipairs(BUBBLE_EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    for _, event in ipairs(PLACE_EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    ApplyFont()
    UpdateInstanceBubbles()
end

local function Stop()
    if not running then return end
    running = false
    watcher:UnregisterAllEvents()
    RestoreFont()
    RestoreInstanceBubbles()
    SkinAll()   -- the open-world bubbles back to Blizzard's look
end

-- Everything the options change, at once.
local function Reapply()
    if not running then return end
    ApplyFont()
    UpdateInstanceBubbles()
    SkinAll()
end

-- ── Options ─────────────────────────────────────────────────────────────────

local preview
local function PaintPreview()
    if not preview then return end
    local style = settings.style
    local path = FontPath(settings.font) or defaultFont or STANDARD_TEXT_FONT
    pcall(preview.text.SetFont, preview.text, path, tonumber(settings.size) or 14, settings.outline or "")
    if settings.shadow then preview.text:SetShadowOffset(1, -1) else preview.text:SetShadowOffset(0, 0) end
    -- Latin only: the game's default font on an English client has no Cyrillic
    -- and drew squares for it.
    preview.text:SetText("Hello there, adventurer! Ready for the key?")
    local w = math.min(380, preview.text:GetStringWidth() + 28)
    preview:SetSize(w, preview.text:GetStringHeight() + 22)
    preview:SetScale(tonumber(settings.scale) or 1)

    if style == "blizzard" then
        preview:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        preview:SetBackdropColor(0, 0, 0, 0.75)
        preview:SetBackdropBorderColor(1, 1, 1, 1)
    elseif style == "clear" then
        preview:SetBackdrop(nil)
    else
        PaintBackdrop(preview, style)
    end
end

local function FontLabel()
    local f = fontByKey[settings.font] or FONTS[1]
    return f.name
end

-- A list of every font, each name written in its own font.
local function ShowFontPicker(anchor)
    if not fontPicker then
        local p = CreateFrame("Frame", "OxedHubBubbleFontPicker", UIParent, "BackdropTemplate")
        p:SetFrameStrata("DIALOG")
        p:SetFrameLevel(230)
        p:SetClampedToScreen(true)
        p:EnableMouse(true)
        local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
        if Panel and Panel.ApplyOrnateFrame then Panel.ApplyOrnateFrame(p, "Bubble font", 0.97) end
        p.rows = {}
        local y = -30
        for _, f in ipairs(FONTS) do
            if not f.path or FontLoads(f.path) then
                local b = CreateFrame("Button", nil, p)
                b:SetHeight(24)
                b:SetPoint("TOPLEFT", p, "TOPLEFT", 14, y)
                b:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, y)
                local hl = b:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 0.82, 0, 0.12)
                b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                b.text:SetPoint("LEFT", b, "LEFT", 6, 0)
                if f.path then pcall(b.text.SetFont, b.text, f.path, 15, "") end
                b.text:SetText(f.name)
                b.key = f.key
                b:SetScript("OnClick", function(self)
                    settings.font = self.key
                    p:Hide()
                    Reapply()
                    PaintPreview()
                    if p.onPick then p.onPick() end
                end)
                p.rows[#p.rows + 1] = b
                y = y - 25
            end
        end
        p:SetSize(240, -y + 14)
        p:SetScript("OnShow", function(self)
            for _, b in ipairs(self.rows) do
                b.text:SetTextColor(1, b.key == settings.font and 0.82 or 1, b.key == settings.font and 0 or 1)
            end
        end)
        tinsert(UISpecialFrames, "OxedHubBubbleFontPicker")
        fontPicker = p
    end
    fontPicker:ClearAllPoints()
    fontPicker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
    fontPicker:SetShown(not fontPicker:IsShown())
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not (API and settings) then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("BubbleChat", 500, 650)
        local function Changed() Reapply() PaintPreview() end

        -- Font: a button opening the list, its name in the chosen font.
        local label = o:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 6)
        label:SetText("Font")
        local pick = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        pick:SetSize(190, 22)
        pick:SetPoint("TOPLEFT", o, "TOPLEFT", o:GetWidth() - 230, o.cursorY - 2)
        pick.Refresh = function() pick:SetText(FontLabel()) end
        pick:SetScript("OnClick", function(self)
            ShowFontPicker(o)
            fontPicker.onPick = self.Refresh
        end)
        table.insert(o.checks, pick)
        o.cursorY = o.cursorY - 30

        o:AddSlider(settings, "size", "Font size", 8, 32, 1, "%s: %d", Changed)
        o:AddChoice(settings, "outline", "Outline", {
            { value = "", text = "None" },
            { value = "OUTLINE", text = "Thin" },
            { value = "THICKOUTLINE", text = "Thick" },
        }, Changed)
        o:AddCheckbox(settings, "shadow", "Shadow under the text", nil, Changed)

        o:AddChoice(settings, "style", "Bubble look", {
            { value = "dark", text = "Dark glass" },
            { value = "stone", text = "OxedHub stone" },
            { value = "clear", text = "Text only" },
            { value = "blizzard", text = "Blizzard" },
        }, Changed)
        o:AddCheckbox(settings, "tail", "Keep the tail on Blizzard bubbles", nil, Changed)
        o:AddSlider(settings, "scale", "Bubble scale", 0.6, 1.6, 0.05, "%s: %.2f", Changed)

        local head = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        head:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 8)
        head:SetText("No bubbles in")
        o.cursorY = o.cursorY - 26
        o:AddCheckbox(settings, "hideDungeon", "Dungeons", nil, Changed)
        o:AddCheckbox(settings, "hideRaid", "Raids", nil, Changed)
        o:AddCheckbox(settings, "hidePvP", "Battlegrounds", nil, Changed)
        o:AddCheckbox(settings, "hideArena", "Arenas", nil, Changed)
        o:AddCheckbox(settings, "hideDelve", "Delves and scenarios", nil, Changed)

        -- What it will look like.
        preview = CreateFrame("Frame", nil, o, "BackdropTemplate")
        preview:SetPoint("TOP", o, "TOP", 0, o.cursorY - 14)
        preview.text = preview:CreateFontString(nil, "OVERLAY")
        preview.text:SetPoint("CENTER")
        preview.text:SetTextColor(1, 1, 1, 1)
        o.cursorY = o.cursorY - 70

        o:AddNote("Inside instances the game does not let addons touch bubbles: the font applies there, the look and scale only in the open world. Your own bubble setting comes back when you leave, and when this module is switched off.")
        o:HookScript("OnShow", PaintPreview)
        optionsWindow = o
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBBUBBLE1 = "/oxbubble"
SLASH_OXEDHUBBUBBLE2 = "/bubblechat"
SlashCmdList.OXEDHUBBUBBLE = function()
    ShowOptions()
end

-- ── Registration ────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bubblechat
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bubblechat = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    -- The game's own font, before anything changes it.
    RememberDefault()

    -- A bubble setting left over from a session that ended inside an
    -- instance with the module since switched off.
    if settings.enabled ~= true and settings.savedBubbles ~= nil then
        RestoreInstanceBubbles()
    end

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "bubblechat",
        name     = "BubbleChat",
        version  = "1.0.0",
        updated  = 20261016.1,   -- new module
        author   = "Oxed",
        category = "chat",
        keywords = { "bubble", "chat bubble", "font", "say", "yell", "speech", "instance", "google fonts" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Chat bubbles with your font, size and look; off in dungeons or raids if you like. /oxbubble",
        icon     = "Interface\\Icons\\INV_Misc_Note_06",

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
