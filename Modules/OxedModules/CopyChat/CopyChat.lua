-- ============================================================================
-- Copy Chat (built-in OxedHub module)
-- Puts a small button on each chat window that opens everything in it as
-- selectable text, so a link, a name or a whole conversation can be copied out
-- with Ctrl+C.
--
-- The chat frame itself cannot be selected, and retyping what someone said is
-- the usual answer. This gives the same lines back as plain text instead.
--
-- Colour codes, textures and links are stripped in the copy: pasting
-- "|cff00ff00|Hitem:..." outside the game is not what anyone wants. The
-- original is left untouched in the chat window.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled     = true,
    button      = true,    -- the button on each chat window
    strip       = true,    -- remove colour codes and link markup from the copy
    timestamps  = true,    -- keep the timestamp at the start of a line
    chatLog     = false,   -- keep /chatlog on across sessions
}

local settings          -- OxedHubDB.modules.copychat, bound at login
local window            -- the copy window, built on first use
local optionsHooked = false
local optionsWindow

local MAX_WINDOWS = 10  -- chat windows the game can have

-- The name the Key Bindings panel prints. Set as the file loads rather than
-- when the module starts: a module switched off still has its key listed, and
-- an unnamed binding shows the raw key instead.
BINDING_NAME_OXEDHUB_COPY_CHAT = "Copy Chat"

-- ── Turning a chat window into text ─────────────────────────────────────────

-- What the player sees, without the markup that carries it. Colour codes and
-- link wrappers are what make a pasted line unreadable, so they come off,
-- while the text inside a link -- the item name, the player name -- stays.
local function Clean(message)
    if type(message) ~= "string" then return tostring(message or "") end
    if not settings.strip then return message end

    local text = message
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")        -- keep the link's own words
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|n", "\n")
    return text
end

-- Reads a frame's history. A line the client refuses to hand over -- some
-- system text is protected -- is skipped rather than allowed to stop the copy
-- half way through the log.
local function Collect(frame)
    local out = {}
    if not (frame and frame.GetNumMessages) then return out, 0 end

    local count = frame:GetNumMessages() or 0
    for index = 1, count do
        local ok, message = pcall(frame.GetMessageInfo, frame, index)
        if ok and message then
            local line = Clean(message)
            if not settings.timestamps then
                line = line:gsub("^%[?%d%d?:%d%d[^%]]*%]?%s*", "")
            end
            out[#out + 1] = line
        end
    end
    return out, count
end

-- ── The copy window ─────────────────────────────────────────────────────────

-- One line of the copy. Each is its own read-only box, because the point of
-- the window is usually a single message: clicking a line selects that line
-- and nothing else, so Ctrl+C takes one link or one name rather than the log.
local function GetRow(index)
    local rows = window.rows
    local row = rows[index]
    if row then return row end

    row = CreateFrame("EditBox", nil, window.content)
    row:SetAutoFocus(false)
    row:SetFontObject("ChatFontNormal")
    row:SetHeight(14)
    row:SetPoint("LEFT", window.content, "LEFT", 0, 0)
    row:SetPoint("RIGHT", window.content, "RIGHT", 0, 0)

    row:SetScript("OnEscapePressed", function() window:Hide() end)
    -- A viewer, not an editor: an edit here would go nowhere, so it is undone.
    row:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self.original or "") end
    end)
    -- Clicking anywhere in the line takes the whole line, not a caret position.
    row:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    row:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        self:HighlightText()
    end)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.07)
    highlight:Hide()
    row:SetScript("OnEnter", function() highlight:Show() end)
    row:SetScript("OnLeave", function() highlight:Hide() end)

    rows[index] = row
    return row
end
local Redraw   -- defined below, referenced while the window is built


local function BuildWindow()
    if window then return window end

    window = CreateFrame("Frame", "OxedHubCopyChatWindow", UIParent,
        "BasicFrameTemplateWithInset")
    window:SetSize(620, 440)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetResizable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)

    window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    window.title:SetPoint("CENTER", window.TitleBg, "CENTER", 0, 0)

    local scroll = CreateFrame("ScrollFrame", "OxedHubCopyChatScroll", window,
        "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -32, 40)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    window.scroll, window.content, window.rows = scroll, content, {}

    -- The whole log in one box, for when the point is the conversation rather
    -- than a line of it.
    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetMaxLetters(0)            -- a long session is a lot of text
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(560)
    box:SetScript("OnEscapePressed", function() window:Hide() end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self.original or "") end
    end)
    box:Hide()
    window.box = box

    local all = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    all:SetSize(110, 20)
    all:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 12)
    all:SetText("Select all")
    all:SetScript("OnClick", function(self)
        window.wholeLog = not window.wholeLog
        self:SetText(window.wholeLog and "One line" or "Select all")
        window:Redraw()
    end)

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 16, 16)
    hint:SetTextColor(0.75, 0.75, 0.75)
    hint:SetText("Click a line to select it, then Ctrl+C. Escape closes.")

    window.Redraw = Redraw

    tinsert(UISpecialFrames, "OxedHubCopyChatWindow")   -- Escape closes it
    window:Hide()
    return window
end

-- Draws whatever mode the window is in, from the lines it is already holding.
function Redraw(self)
    local lines = self.lines or {}

    if self.wholeLog then
        for _, row in ipairs(self.rows) do row:Hide() end
        self.content:Hide()

        local text = table.concat(lines, "\n")
        self.box:ClearAllPoints()
        self.box:SetPoint("TOPLEFT", self.scroll, "TOPLEFT", 0, 0)
        self.box:SetWidth(self.scroll:GetWidth())
        self.box.original = text
        self.box:SetText(text)
        self.scroll:SetScrollChild(self.box)
        self.box:Show()
        self.box:HighlightText()
        self.box:SetFocus()
        return
    end

    self.box:Hide()
    self.scroll:SetScrollChild(self.content)
    self.content:Show()
    self.content:SetWidth(self.scroll:GetWidth())

    -- Newest at the top: the line you came to copy is almost always the one
    -- that just went past.
    local y = 0
    for index = #lines, 1, -1 do
        local shown = #lines - index + 1
        local row = GetRow(shown)
        row.original = lines[index]
        row:SetText(lines[index])
        row:SetPoint("TOP", self.content, "TOP", 0, -y)
        row:Show()
        y = y + 15
    end

    for index = #lines + 1, #self.rows do
        self.rows[index]:Hide()
    end

    self.content:SetHeight(math.max(1, y))
    self.scroll:SetVerticalScroll(0)
end

local function ShowText(frame, title)
    BuildWindow()

    local lines, count = Collect(frame)

    -- An empty window is worth saying out loud: a blank page looks like the
    -- copy failed, when the window simply has nothing in it.
    if count == 0 then
        lines = { ("This chat window (%s) holds no messages."):format(frame:GetName() or "?") }
    end

    window.lines = lines
    window.title:SetText(("%s  |cffffffff%d|r"):format(title or CHAT or "Chat", count))
    window:Show()
    window:Redraw()
end

local function TabTitle(index)
    local tab = _G["ChatFrame" .. index .. "Tab"]
    return (tab and tab:GetText()) or CHAT or "Chat"
end

-- ── The button on a chat window ─────────────────────────────────────────────

local function AttachButton(index)
    local frame = _G["ChatFrame" .. index]
    if not (frame and frame.GetNumMessages) then return end

    if frame.OxedCopyButton then
        frame.OxedCopyButton:SetShown(settings.button ~= false)
        return
    end
    if settings.button == false then return end

    local button = CreateFrame("Button", "OxedHubCopyChatButton" .. index, frame)
    button:SetSize(18, 18)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:EnableMouse(true)
    -- Above the chat text, or the frame swallows the click.
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((frame:GetFrameLevel() or 1) + 10)

    -- An atlas that is not in this build leaves an invisible button, which
    -- looks exactly like a broken one. A plain texture is used if the atlas
    -- does not take.
    local ok = pcall(button.SetNormalAtlas, button, "poi-workorders")
    if not ok or not button:GetNormalTexture() then
        button:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    end
    pcall(button.SetHighlightTexture, button, "Interface\\Buttons\\UI-Common-MouseHilight")
    button:SetAlpha(0.8)

    -- The bottom right corner: the one part of a chat window that is never text.
    button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(("Copy %s"):format(TabTitle(index)))
        GameTooltip:AddLine(("%d line(s) in this window."):format(frame:GetNumMessages() or 0),
            1, 1, 1)
        GameTooltip:Show()
        self:SetAlpha(1)
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:SetAlpha(0.65)
    end)
    button:SetScript("OnClick", function()
        ShowText(frame, TabTitle(index))
    end)

    frame.OxedCopyButton = button
end

local function AttachAll()
    for index = 1, MAX_WINDOWS do
        AttachButton(index)
    end
end

-- ── Wiring ──────────────────────────────────────────────────────────────────

local function InstallHooks()
    if optionsHooked then return end
    optionsHooked = true

    AttachAll()

    function OxedHub_CopyChat()
        local frame = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME
        if frame then ShowText(frame, TabTitle(frame:GetID() or 1)) end
    end

    -- A way in that does not depend on finding a small button: /copychat for
    -- the window you are looking at, /copychat 3 for a particular one.
    SLASH_OXEDCOPYCHAT1 = "/copychat"
    SLASH_OXEDCOPYCHAT2 = "/oxedcopy"
    SlashCmdList["OXEDCOPYCHAT"] = function(argument)
        local index = tonumber(argument and argument:match("%d+") or "")
        -- The window the player is reading. FCF_GetCurrentChatFrame answers
        -- for the tab menu, not for the chat, and away from a menu it names
        -- whichever window was touched last -- often an empty one.
        local frame = (index and _G["ChatFrame" .. index])
            or SELECTED_CHAT_FRAME
            or DEFAULT_CHAT_FRAME
        if not frame then
            print("|cffff5555OxedHub:|r no chat window found.")
            return
        end
        ShowText(frame, TabTitle(frame:GetID() or 1))
    end

    -- A window opened later gets its button too.
    if FCF_OpenNewWindow then
        hooksecurefunc("FCF_OpenNewWindow", function()
            C_Timer.After(0, AttachAll)
        end)
    end

    -- The right-click menu on a chat tab is where a player already looks for
    -- things to do with that window, so the copy is offered there as well.
    if Menu and Menu.ModifyMenu then
        pcall(Menu.ModifyMenu, "MENU_FCF_TAB", function(owner, root)
            if not settings or settings.enabled == false then return end
            local frame = FCF_GetCurrentChatFrame and FCF_GetCurrentChatFrame()
            if not frame then return end
            root:CreateDivider()
            root:CreateButton("Copy this window", function()
                ShowText(frame, TabTitle(frame:GetID() or 1))
            end)
        end)
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.copychat
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.copychat = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

-- /chatlog is the game's own file log, and it forgets the setting between
-- sessions. Turning it back on is only done when the player asked for it.
local function ApplyChatLog()
    if not (settings.chatLog and LoggingChat and C_ChatInfo) then return end
    if C_ChatInfo.IsLoggingChat and not C_ChatInfo.IsLoggingChat() then
        LoggingChat(true)
    end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Copy Chat", 420, 240)
        optionsWindow:AddCheckbox(settings, "button", "Button on each chat window",
            "A small button under the scroll arrow. Without it, use the right-click menu on a chat tab.",
            AttachAll)
        optionsWindow:AddCheckbox(settings, "strip", "Plain text",
            "Remove colour codes and link markup from the copy, keeping the words inside a link.")
        optionsWindow:AddCheckbox(settings, "timestamps", "Keep timestamps",
            "Leave the time at the start of each line in the copy.")
        optionsWindow:AddCheckbox(settings, "chatLog", "Keep /chatlog on",
            "Turns the game's chat log file back on at login. The file is Logs/WoWChatLog.txt.",
            ApplyChatLog)
        optionsWindow:AddNote("Set the key first: Escape, Options, Key Bindings, OxedHub, Copy Chat. Without a key, use /copychat or the button on the chat window.\n\nIn the window, click a line to select it and press Ctrl+C. Select all takes the whole log.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    ApplyChatLog()

    if not OxedHub.ModuleAPI then
        if settings.enabled ~= false then InstallHooks() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "copychat",
        name     = "Copy Chat",
        version  = "1.0.0",
        author   = "Oxed",
        category = "chat",
        -- Short enough to be read in full on the card, which clips what does
        -- not fit. The key comes first because without one the module does
        -- nothing at all.
        desc     = "Needs a key: Key Bindings, OxedHub, Copy Chat. Opens the chat as text to copy.",
        icon     = "Interface\\Icons\\INV_Misc_Note_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            InstallHooks()
            AttachAll()
        end,

        OnDisable = function()
            if window then window:Hide() end
            for index = 1, MAX_WINDOWS do
                local frame = _G["ChatFrame" .. index]
                if frame and frame.OxedCopyButton then frame.OxedCopyButton:Hide() end
            end
        end,
    })
end)
