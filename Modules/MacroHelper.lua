local addonName, OxedHub = ...

-- ── Macro helper ─────────────────────────────────────────────────────────────
-- A reference panel that writes macro syntax into an edit box at the cursor.
--
-- There are two macro editors in the addon -- the Advanced Macros tab on a
-- trigger and the Mix Macro editor -- and both want the same thing. Attach()
-- hangs the panel off whichever edit box is passed, so a snippet added here
-- shows up in both.
--
-- The catalogue below is WoW's own macro syntax. The only part worth writing by
-- hand is the class-aware templates: a "focus interrupt" is useless unless it
-- names the interrupt the player actually has.

local MacroHelper = {}
OxedHub.MacroHelper = MacroHelper

local L = OxedHub.L

-- ── Class spells ─────────────────────────────────────────────────────────────
-- A function instead of an ID where the answer depends on specialisation.

local INTERRUPT = {
    DEATHKNIGHT = 47528,   -- Mind Freeze
    DEMONHUNTER = 183752,  -- Disrupt
    EVOKER      = 351338,  -- Quell
    MAGE        = 2139,    -- Counterspell
    MONK        = 116705,  -- Spear Hand Strike
    PALADIN     = 96231,   -- Rebuke
    PRIEST      = 15487,   -- Silence
    ROGUE       = 1766,    -- Kick
    SHAMAN      = 57994,   -- Wind Shear
    WARLOCK     = 19647,   -- Spell Lock
    WARRIOR     = 6552,    -- Pummel
    DRUID       = function() return GetSpecialization() == 1 and 78675 or 106839 end,
    HUNTER      = function() return GetSpecialization() == 3 and 187707 or 147362 end,
}

local DISPEL = {
    DRUID   = 88423, PALADIN = 4987,  PRIEST = 527,
    SHAMAN  = 77130, MONK    = 115450, EVOKER = 360823,
    MAGE    = 475,
}

local PURGE = {
    HUNTER = 19801, MAGE = 30449, PRIEST = 528, SHAMAN = 370,
    WARLOCK = 19505, EVOKER = 372048,
}

local COMBAT_RES = {
    DEATHKNIGHT = 61999, DRUID = 20484, PALADIN = 391054,
    WARLOCK = 20707, MONK = 115178, EVOKER = 361227,
}

-- Falls back to a readable placeholder so the inserted macro still explains
-- itself on a class that has no such spell.
local function SpellName(map, placeholder)
    local _, class = UnitClass("player")
    local id = map[class]
    if type(id) == "function" then
        local ok, resolved = pcall(id)
        id = ok and resolved or nil
    end
    if not id then return placeholder end

    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    return (info and info.name) or placeholder
end

-- ── Catalogue ────────────────────────────────────────────────────────────────
-- Entries are built on demand: the class templates have to be resolved against
-- the player's current specialisation, not the one they logged in with.

function MacroHelper:GetSections()
    local interrupt = SpellName(INTERRUPT, "Interrupt")
    local dispel    = SpellName(DISPEL, "Dispel")
    local purge     = SpellName(PURGE, "Purge")
    local battleRes = SpellName(COMBAT_RES, "Battle Res")

    return {
        {
            header = L["MACROHELP_TEMPLATES"] or "Ready-made",
            entries = {
                { "Mouseover, else target", "#showtooltip\n/cast [@mouseover,harm][] Spell Name\n" },
                { "Friendly mouseover",     "#showtooltip\n/cast [@mouseover,help][@player] Spell Name\n" },
                { "Help / Harm",            "#showtooltip\n/cast [help] Friendly Spell; [harm] Hostile Spell\n" },
                { "Focus interrupt",        ("#showtooltip\n/cast [@focus,exists,harm][] %s\n"):format(interrupt) },
                { "Mouseover dispel",       ("#showtooltip\n/cast [@mouseover,help][] %s\n"):format(dispel) },
                { "Purge",                  ("#showtooltip\n/cast [@target,harm] %s\n"):format(purge) },
                { "Battle res on mouseover",("#showtooltip\n/cast [@mouseover,help,dead][] %s\n"):format(battleRes) },
                { "Ground at cursor",       "#showtooltip\n/cast [@cursor] Spell Name\n" },
                { "Stop casting first",     "#showtooltip\n/stopcasting\n/cast Spell Name\n" },
                { "Trinket with a spell",   "#showtooltip\n/use 13\n/cast Spell Name\n" },
                { "Modifier swap",          "#showtooltip\n/cast [mod:shift] Other Spell; Spell Name\n" },
            },
        },
        {
            header = L["MACROHELP_TARGETS"] or "Target unit",
            entries = {
                { "[@mouseover]", "[@mouseover]" }, { "[@target]", "[@target]" },
                { "[@focus]", "[@focus]" },         { "[@cursor]", "[@cursor]" },
                { "[@player]", "[@player]" },       { "[@pet]", "[@pet]" },
                { "[@none]", "[@none]" },           { "[@arena1]", "[@arena1]" },
                { "[@boss1]", "[@boss1]" },         { "[@party1]", "[@party1]" },
            },
        },
        {
            header = L["MACROHELP_CONDITIONS"] or "Conditions",
            entries = {
                { "[mod:shift]", "[mod:shift]" }, { "[mod:ctrl]", "[mod:ctrl]" },
                { "[mod:alt]", "[mod:alt]" },     { "[nomod]", "[nomod]" },
                { "[harm]", "[harm]" },           { "[help]", "[help]" },
                { "[dead]", "[dead]" },           { "[nodead]", "[nodead]" },
                { "[combat]", "[combat]" },       { "[nocombat]", "[nocombat]" },
                { "[exists]", "[exists]" },       { "[noexists]", "[noexists]" },
                { "[mounted]", "[mounted]" },     { "[indoors]", "[indoors]" },
                { "[outdoors]", "[outdoors]" },   { "[stealth]", "[stealth]" },
                { "[channeling]", "[channeling]" },{ "[group]", "[group]" },
                { "[form:1]", "[form:1]" },       { "[spec:1]", "[spec:1]" },
                { "[button:2]", "[button:2]" },
            },
        },
        {
            header = L["MACROHELP_COMMANDS"] or "Commands",
            entries = {
                { "#showtooltip", "#showtooltip\n" },
                { "/cast", "/cast " },
                { "/castsequence", "/castsequence reset=3 SpellA, SpellB\n" },
                { "/use 13 (trinket)", "/use 13\n" },
                { "/use 14 (trinket)", "/use 14\n" },
                { "/stopcasting", "/stopcasting\n" },
                { "/stopmacro [noexists]", "/stopmacro [noexists]\n" },
                { "/cancelaura", "/cancelaura Aura Name\n" },
                { "/cancelform", "/cancelform\n" },
                { "/startattack", "/startattack\n" },
                { "/target [@mouseover]", "/target [@mouseover]\n" },
                { "/focus [@mouseover]", "/focus [@mouseover]\n" },
                { "/clearfocus", "/clearfocus\n" },
                { "/petattack", "/petattack\n" },
                { "/petfollow", "/petfollow\n" },
            },
        },
    }
end

-- ── Insertion ────────────────────────────────────────────────────────────────

-- Writes at the caret rather than appending, so a conditional can be dropped
-- into the middle of a line that is already written.
local function InsertSnippet(editBox, snippet, onChanged)
    if not editBox or not snippet then return end

    local body = editBox:GetText() or ""
    if #body + #snippet > 255 then
        UIErrorsFrame:AddExternalErrorMessage(
            L["MACROHELP_TOO_LONG"] or "A macro cannot be longer than 255 characters.")
        return
    end

    editBox:SetFocus()
    editBox:Insert(snippet)

    if onChanged then onChanged(editBox:GetText()) end
end

-- ── Panel ────────────────────────────────────────────────────────────────────
-- Docked beside the editor rather than floating over it. The first version was
-- one endless list dropped on top of the macro text: it covered what the player
-- was editing, ran off the bottom of the window and could not be scanned.
--
-- So: one category at a time, two columns for the short entries, and the panel
-- pinned to the right of the window where it hides nothing.

local PANEL_WIDTH = 330
local COLUMN_WIDTH = 148
local COLUMN_GAP = 8
local ROW_HEIGHT = 20

local function ShowSnippetTooltip(button)
    if not button.snippet then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(button.label or "", 1, 0.82, 0.2)
    GameTooltip:AddLine(" ")
    -- The exact text that will be inserted, so a template can be read before it
    -- lands in the macro rather than after.
    for line in (button.snippet .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then GameTooltip:AddLine(line, 0.8, 0.9, 1) end
    end
    GameTooltip:Show()
end

local function AcquireEntry(panel, index)
    panel.entries = panel.entries or {}
    local button = panel.entries[index]
    if button then return button end

    button = CreateFrame("Button", nil, panel.list, "BackdropTemplate")
    button:SetHeight(ROW_HEIGHT)
    -- Rows get the same rounded edge, one notch lighter than the panel so they
    -- read as sitting inside it.
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    button:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
    button:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)

    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 6, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    button.text = text

    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.20, 0.18, 0.05, 0.95)
        self:SetBackdropBorderColor(1, 0.82, 0, 0.7)
        ShowSnippetTooltip(self)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.14, 0.9)
        self:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.9)
        GameTooltip:Hide()
    end)

    panel.entries[index] = button
    return button
end

local function LayoutCategory(panel)
    local sections = OxedHub.MacroHelper:GetSections()
    local section = sections[panel.activeCategory] or sections[1]
    local query = (panel.searchText or ""):lower()

    -- Columns are worked out from the space actually available rather than
    -- fixed at two. Filling the width of the window gives four or five, which
    -- is the whole point of putting the panel in the empty area.
    local listWidth = math.max(panel.scroll:GetWidth() - 8, COLUMN_WIDTH)
    local columns = math.max(1, math.floor(listWidth / (COLUMN_WIDTH + COLUMN_GAP)))

    -- Templates are sentences and need room; the rest are short tokens.
    if panel.activeCategory == 1 then
        columns = math.max(1, math.floor(columns / 2))
    end

    local cellWidth = (listWidth - COLUMN_GAP * (columns - 1)) / columns
    panel.list:SetWidth(listWidth)

    local index, y = 0, 0
    for _, entry in ipairs(section.entries) do
        local label, snippet = entry[1], entry[2]
        if query == "" or label:lower():find(query, 1, true)
            or snippet:lower():find(query, 1, true) then

            index = index + 1
            local button = AcquireEntry(panel, index)
            button.label = label
            button.snippet = snippet
            button.text:SetText(label)
            button:SetScript("OnClick", function(self)
                InsertSnippet(panel.editBox, self.snippet, panel.onChanged)
            end)

            local column = (index - 1) % columns
            button:ClearAllPoints()
            button:SetWidth(cellWidth)
            button:SetPoint("TOPLEFT", panel.list, "TOPLEFT",
                column * (cellWidth + COLUMN_GAP), -y)
            if column == columns - 1 then y = y + ROW_HEIGHT + 3 end

            button:Show()
        end
    end

    -- A part-filled last row still owes its height.
    if index % columns ~= 0 then y = y + ROW_HEIGHT + 3 end

    for i = index + 1, #(panel.entries or {}) do panel.entries[i]:Hide() end

    panel.empty:SetShown(index == 0)
    panel.list:SetHeight(math.max(y, 1))
    panel.scroll:SetVerticalScroll(0)

    -- The bar only belongs there when there is something to scroll to. With the
    -- panel this wide most categories fit outright, and an inert scrollbar beside
    -- a full list is just clutter.
    --
    -- Both bars are hidden: the template's own and the restyled one the addon
    -- puts over it. Hiding only the first left the replacement on screen.
    local visibleHeight = panel.scroll:GetHeight() or 0
    local needsBar = visibleHeight > 0 and y > visibleHeight

    for _, bar in ipairs({ panel.scroll.ScrollBar, panel.scroll.oxedMinimalScrollBar }) do
        if bar then bar:SetShown(needsBar) end
    end
end

-- Fills the empty space under the editor instead of hanging off the side of the
-- window. Docking outside put it past the screen edge, and there is a whole
-- unused half below the info box that costs nothing to use.
local function DockPanel(panel, owner, below)
    panel:ClearAllPoints()

    -- Read from the owner so the host can name its anchor after the button has
    -- already been attached; the info box is usually built further down.
    below = below or owner.macroHelperDock

    if below then
        -- Height is fixed rather than stretched to the owner: the editor frame
        -- ends just under its own content, so anchoring the bottom to it left
        -- the panel a few pixels tall with only the tabs visible.
        panel:SetHeight(300)
        panel:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -40)
        panel:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -40)
    else
        -- No anchor given: sit in the lower half of the editor itself.
        panel:SetPoint("TOPLEFT", owner, "LEFT", 12, 0)
        panel:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -12, 12)
    end
end

local function BuildPanel(owner, editBox, onChanged)
    -- Parented to UIParent, not to the editor. Docked to the editor's right it
    -- sits outside its parent's bounds, and with the addon window nearly as
    -- wide as the screen there was simply nothing on screen to see -- no error,
    -- no panel. Placement is chosen on open by DockPanel below.
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetClampedToScreen(true)
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    -- The same backdrop as the macro preview box: rounded corners from the
    -- tooltip border art, matching the frame the panel sits under.
    panel:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    panel:Hide()

    panel.editBox = editBox
    panel.onChanged = onChanged
    panel.activeCategory = 1

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    title:SetText(L["MACROHELP_TITLE"] or "Macro Helper")
    title:SetTextColor(1, 0.82, 0, 1)

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() panel:Hide() end)

    local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
    search:SetHeight(20)
    search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -6)
    search:SetPoint("RIGHT", panel, "RIGHT", -14, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then
            SearchBoxTemplate_OnTextChanged(self)
        end
        panel.searchText = self:GetText()
        LayoutCategory(panel)
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Category buttons. One list at a time beats a single roll of everything:
    -- the conditionals alone are twenty entries.
    local tabs = {}
    local sections = OxedHub.MacroHelper:GetSections()

    for i, section in ipairs(sections) do
        local tab = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        tab:SetHeight(20)
        tab:SetNormalFontObject("GameFontNormalSmall")
        tab:SetText(section.header)
        if i == 1 then
            tab:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -6)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", 6, 0)
        end
        tab:SetScript("OnClick", function()
            panel.activeCategory = i
            for index, other in ipairs(tabs) do
                if index == i then other:LockHighlight() else other:UnlockHighlight() end
            end
            LayoutCategory(panel)
        end)
        tabs[i] = tab
    end
    tabs[1]:LockHighlight()
    panel.tabs = tabs

    -- Tab widths are shared out at layout time: the panel stretches to whatever
    -- room the window has, so a width fixed at build time would not fit it.
    panel.SizeTabs = function(self)
        local total = (self:GetWidth() or PANEL_WIDTH) - 24 - 6 * (#tabs - 1)
        local each = math.max(40, total / #tabs)
        for _, tab in ipairs(tabs) do tab:SetWidth(each) end
    end

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", tabs[1], "BOTTOMLEFT", 0, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 12)
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll
        and OxedHub.UIComponents.Scroll.StyleFrame then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    end
    panel.scroll = scroll

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(COLUMN_WIDTH * 2 + COLUMN_GAP, 1)
    scroll:SetScrollChild(list)
    panel.list = list

    -- Parented to UIParent for placement, so it no longer disappears with the
    -- editor on its own.
    owner:HookScript("OnHide", function() panel:Hide() end)

    local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOP", scroll, "TOP", 0, -20)
    empty:SetText(L["MACROHELP_EMPTY"] or "Nothing matches that search.")
    empty:Hide()
    panel.empty = empty

    return panel
end

-- Adds a Helper button next to an existing macro editor.
--
--   editBox    the macro body being edited
--   anchor     the button is placed to the right of this
--   onChanged  called with the new text, for hosts that need to refresh
--              something the edit box does not update on its own
--   dockBelow  the panel fills the space under this frame
function MacroHelper:Attach(owner, editBox, anchor, onChanged, dockBelow)
    if not owner or not editBox then return end

    local button = CreateFrame("Button", nil, owner, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
    button:SetText(L["MACROHELP_BUTTON"] or "Macro Helper")
    button:SetNormalFontObject("GameFontNormalSmall")

    local panel

    button:SetScript("OnClick", function()
        -- Built on first use and refilled on every open: the class templates
        -- depend on the current specialisation, which can change between two
        -- openings of the same editor.
        panel = panel or BuildPanel(owner, editBox, onChanged)

        if panel:IsShown() then
            panel:Hide()
        else
            -- Placed on open rather than at build time: the window can be
            -- moved or resized between two openings.
            DockPanel(panel, owner, dockBelow)
            panel:Show()
            if panel.SizeTabs then panel:SizeTabs() end
            LayoutCategory(panel)
            panel:Raise()
        end
    end)

    return button
end
