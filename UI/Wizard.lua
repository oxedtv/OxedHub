local addonName, OxedHub = ...
local print = OxedHub.Print or print

-- Setup wizard: lets the player choose which sections of the main window they
-- use (Core\Sections.lua holds the choice) and, when Modules is one of them,
-- which modules to switch on.
--
--   welcome    what the addon is
--   sections   six cards, at least one must be ticked
--   modules    every module with what it is for; only when Modules is ticked
--   done       what was chosen, and where to change it
--
-- A section that is left out is hidden at once and stops working after a
-- reload, which Finish offers. Nothing is saved before Finish: closing the
-- window part way through changes nothing.
--
-- For now it opens only from /oxedhub wizard, and from the Dashboard's System
-- button once it has been finished or skipped. Opening by itself on the first
-- visit is written but switched off (AUTO_OFFER, by OfferFirstRun).
--
-- Nothing is built at load. The window is made the first time it is asked for,
-- which is after login, so L already holds the player's language.

local Wizard = {}
OxedHub.Wizard = Wizard

local L = OxedHub.L

-- The wizard is drawn inside the main window, where the Dashboard is, so its
-- sizes come from that space and are worked out in Build (Measure). LEFT and
-- RIGHT points pin a region's vertical centre, so text here gets a width
-- instead of a second anchor, and the widths have to be known as numbers.
local CARD_GAP, CARD_H = 16, 128
local ROW_GAP, ROW_H = 10, 68
local PAGE_W, CARD_W, CARD_TEXT_W
-- The module list: two columns inside a scroll frame, whose bar takes the
-- strip on the right.
local LIST_W, ROW_W, ROW_TEXT_W

local function Measure(innerWidth)
    PAGE_W = innerWidth - 12
    CARD_W = (PAGE_W - CARD_GAP) / 2
    CARD_TEXT_W = CARD_W - 14 - 56 - 12 - 14
    LIST_W = PAGE_W - 28
    ROW_W = (LIST_W - ROW_GAP) / 2
    ROW_TEXT_W = ROW_W - 8 - 22 - 6 - 34 - 8 - 10
end

local frame = nil
local step = 1
local choice = {}          -- section key -> boolean
local moduleChoice = {}    -- module id -> boolean
local moduleRowsBuilt = false
-- Opened from the Modules page's "Add modules": the module list on its own,
-- with no way into the other steps and nothing but the pick being saved.
local modulesOnly = false

local function T(text)
    return OxedHub.T and OxedHub.T(text) or text
end

local function SectionLabel(key)
    return L["TAB_" .. key:upper()] or key
end

-- The steps for the current choice. The modules step exists only while the
-- Modules card is ticked, so the count on screen changes with that card.
local function StepList()
    if modulesOnly then
        return { "modules" }
    end
    local steps = { "welcome", "sections" }
    if choice.Modules then
        steps[#steps + 1] = "modules"
    end
    steps[#steps + 1] = "done"
    return steps
end

local function CountModulesChosen()
    local count = 0
    for _, on in pairs(moduleChoice) do
        if on then count = count + 1 end
    end
    return count
end

local function ClickSound(on)
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

local function RedButton(parent, width, text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 28)
    b:SetText(text)
    local Btn = OxedHub.UIComponents and OxedHub.UIComponents.Button
    if Btn and Btn.ApplyRedStyle then
        Btn.ApplyRedStyle(b)
    end
    return b
end

local BOX_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- A box shows its state three ways: the tick, the border and the icon's colour.
-- Section cards and module rows share it.
local function PaintBox(box, on)
    box.check:SetChecked(on)
    box.icon:SetDesaturated(not on)
    if on then
        box:SetBackdropColor(0.17, 0.13, 0.04, 1)
        box:SetBackdropBorderColor(1, 0.82, 0, 1)
        box.title:SetTextColor(1, 0.82, 0, 1)
    else
        box:SetBackdropColor(0.07, 0.07, 0.08, 1)
        box:SetBackdropBorderColor(0.40, 0.40, 0.40, 1)
        box.title:SetTextColor(0.80, 0.80, 0.80, 1)
    end
end

local function AddHover(box)
    local glow = box:CreateTexture(nil, "HIGHLIGHT")
    glow:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    glow:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)
    glow:SetColorTexture(1, 0.82, 0, 0.07)
end

-- ── Section cards ───────────────────────────────────────────────────────────

local function CreateCard(parent, entry)
    local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
    card:SetSize(CARD_W, CARD_H)
    card:SetBackdrop(BOX_BACKDROP)
    card.key = entry.key
    AddHover(card)

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(56, 56)
    card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
    card.icon:SetTexture(entry.icon)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- The tick is only a picture of the state: the whole card is the button.
    card.check = CreateFrame("CheckButton", nil, card, "UICheckButtonTemplate")
    card.check:SetSize(30, 30)
    card.check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    card.check:EnableMouse(false)

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    card.title:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 12, 0)
    card.title:SetWidth(CARD_TEXT_W - 26)
    card.title:SetJustifyH("LEFT")
    card.title:SetWordWrap(false)
    card.title:SetText(SectionLabel(entry.key))

    -- What it is, in white.
    card.desc = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.desc:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
    card.desc:SetWidth(CARD_TEXT_W)
    card.desc:SetJustifyH("LEFT")
    card.desc:SetJustifyV("TOP")
    card.desc:SetText(T(entry.desc))

    -- Why you would want it, dimmer, underneath.
    card.detail = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    card.detail:SetPoint("TOPLEFT", card.desc, "BOTTOMLEFT", 0, -6)
    card.detail:SetWidth(CARD_TEXT_W)
    card.detail:SetJustifyH("LEFT")
    card.detail:SetJustifyV("TOP")
    card.detail:SetTextColor(0.78, 0.68, 0.42, 1)
    card.detail:SetText(T(entry.detail))

    card:SetScript("OnClick", function(self)
        choice[self.key] = not choice[self.key]
        ClickSound(choice[self.key])
        Wizard:Refresh()
    end)

    return card
end

-- ── Module rows ─────────────────────────────────────────────────────────────

local function CreateModuleRow(parent, mod)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(ROW_W, ROW_H)
    row:SetBackdrop(BOX_BACKDROP)
    row.id = mod.id
    AddHover(row)

    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(22, 22)
    row.check:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.check:EnableMouse(false)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
    row.icon:SetTexture(mod.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8 + 22 + 6 + 34 + 8, -8)
    row.title:SetWidth(ROW_TEXT_W)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.title:SetText(mod.name or mod.id)

    -- Width and height both set: a description longer than three lines is cut
    -- off inside the row instead of running into the one below.
    row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.desc:SetSize(ROW_TEXT_W, 34)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetJustifyV("TOP")
    row.desc:SetTextColor(0.85, 0.85, 0.85, 1)
    row.desc:SetText(T(mod.desc) or "")

    row:SetScript("OnClick", function(self)
        moduleChoice[self.id] = not moduleChoice[self.id]
        ClickSound(moduleChoice[self.id])
        PaintBox(self, moduleChoice[self.id] == true)
        Wizard:UpdateModuleCount()
    end)

    return row
end

-- Scroll frame names have moved between builds, and a missing template is an
-- error rather than nil, so ask inside pcall and keep a plain one to fall back on.
local function CreateScroll(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    if not ok or not scroll then
        scroll = CreateFrame("ScrollFrame", nil, parent)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local limit = self:GetVerticalScrollRange() or 0
            local value = (self:GetVerticalScroll() or 0) - delta * 70
            if value < 0 then value = 0 elseif value > limit then value = limit end
            self:SetVerticalScroll(value)
        end)
    end
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(LIST_W, 10)
    scroll:SetScrollChild(child)
    return scroll, child
end

-- Builds the list once, the first time the modules step is shown: by then
-- every module has registered. Grouped under the Modules page's own headings.
local function BuildModuleRows(page)
    if moduleRowsBuilt then return end
    local API = OxedHub.ModuleAPI
    if not API or not API.modules then return end
    moduleRowsBuilt = true

    local byCategory = {}
    for id, mod in pairs(API.modules) do
        if mod._registered then
            local key = API.CategoryOf and API:CategoryOf(mod) or "quests"
            byCategory[key] = byCategory[key] or {}
            table.insert(byCategory[key], mod)
        end
    end

    page.rows = {}
    page.categoryButtons = {}
    local y = 0
    for _, category in ipairs(API.CATEGORIES or {}) do
        local list = byCategory[category.key]
        if list and #list > 0 then
            table.sort(list, function(a, b)
                return tostring(a.name or a.id):lower() < tostring(b.name or b.id):lower()
            end)

            local header = page.child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            header:SetPoint("TOPLEFT", page.child, "TOPLEFT", 4, -(y + 6))
            header:SetTextColor(1, 0.82, 0, 1)
            header:SetText(T(category.label))
            local line = page.child:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 0.82, 0, 0.35)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", page.child, "TOPLEFT", 0, -(y + 28))
            line:SetWidth(LIST_W)

            -- One click for the whole heading: ticks every module under it,
            -- or unticks them when they are all ticked already. The label is
            -- kept right by UpdateModuleCount.
            local all = CreateFrame("Button", nil, page.child)
            all:SetSize(150, 22)
            all:SetPoint("TOPRIGHT", page.child, "TOPLEFT", LIST_W, -(y + 4))
            all.label = all:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            all.label:SetPoint("RIGHT", all, "RIGHT", -4, 0)
            all.label:SetTextColor(0.55, 0.78, 1, 1)
            all.category = category.key
            all:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
            all:SetScript("OnLeave", function(self) self.label:SetTextColor(0.55, 0.78, 1, 1) end)
            all:SetScript("OnClick", function(self)
                local turnOn = not self.allOn
                for _, row in ipairs(page.rows) do
                    if row.category == self.category then
                        moduleChoice[row.id] = turnOn
                    end
                end
                ClickSound(turnOn)
                Wizard:Refresh()
            end)
            page.categoryButtons[#page.categoryButtons + 1] = all
            y = y + 36

            for i, mod in ipairs(list) do
                local row = CreateModuleRow(page.child, mod)
                local column = (i - 1) % 2
                local rowIndex = math.floor((i - 1) / 2)
                row:SetPoint("TOPLEFT", page.child, "TOPLEFT",
                    column * (ROW_W + ROW_GAP), -(y + rowIndex * (ROW_H + 8)))
                row.category = category.key
                page.rows[#page.rows + 1] = row
            end
            y = y + math.ceil(#list / 2) * (ROW_H + 8) + 6
        end
    end
    page.child:SetHeight(math.max(y, 10))
end

function Wizard:UpdateModuleCount()
    if not frame then return end
    local page = frame.pages.modules
    page.count:SetText(string.format(L["Switched on: %d"], CountModulesChosen()))

    for _, button in ipairs(page.categoryButtons or {}) do
        local allOn = true
        for _, row in ipairs(page.rows) do
            if row.category == button.category and not moduleChoice[row.id] then
                allOn = false
                break
            end
        end
        button.allOn = allOn
        button.label:SetText(allOn and L["Clear this group"] or L["Select this group"])
    end
end

-- ── Pages ───────────────────────────────────────────────────────────────────

local function CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -4)
    page:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 44)
    page:Hide()

    page.heading = page:CreateFontString(nil, "OVERLAY", "QuestFont_Shadow_Huge")
    page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
    page.heading:SetWidth(PAGE_W)
    page.heading:SetJustifyH("LEFT")
    page.heading:SetTextColor(1, 0.82, 0, 1)

    page.text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.text:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -8)
    page.text:SetWidth(PAGE_W)
    page.text:SetJustifyH("LEFT")
    page.text:SetTextColor(0.85, 0.85, 0.85, 1)

    return page
end

local function Build()
    local Sections = OxedHub.Sections

    local UI = OxedHub.UI
    local host, insets
    if UI and UI.GetWizardHost then
        host, insets = UI:GetWizardHost()
    end
    if not host then return end
    insets = insets or { left = 42, right = 56, top = 66, bottom = 54 }

    -- Fills the content area and wears the same ornate background as the
    -- pages, so it reads as one more page of the window rather than a popup.
    local outer = CreateFrame("Frame", "OxedHubWizardFrame", host)
    outer:SetAllPoints(host)
    outer:SetFrameLevel(host:GetFrameLevel() + 20)
    outer:EnableMouse(true)
    outer:Hide()
    if UI.ApplyToysBackground then
        UI.ApplyToysBackground(outer)
    end

    -- Hidden for any reason (Skip, Finish, the window closing, Escape): the
    -- sidebar comes back. The explicit Hide matters when it was the window
    -- that closed, or the wizard would reappear with it the next time.
    outer:SetScript("OnHide", function(self)
        self:Hide()
        if OxedHub.UI and OxedHub.UI.SetWizardMode then
            OxedHub.UI:SetWizardMode(false)
            -- SetWizardMode leaves the Dashboard up. Opened from the Modules
            -- page, the player goes back there, saved or cancelled.
            if modulesOnly and OxedHub.UI.ShowTab then
                OxedHub.UI:ShowTab("Modules")
            end
        end
    end)

    -- Everything sits in the space inside the ornate border.
    local f = CreateFrame("Frame", nil, outer)
    f:SetPoint("TOPLEFT", outer, "TOPLEFT", insets.left, -insets.top)
    f:SetPoint("BOTTOMRIGHT", outer, "BOTTOMRIGHT", -insets.right, insets.bottom)
    f.outer = outer

    local hostWidth = host:GetWidth() or 0
    local innerWidth = hostWidth - insets.left - insets.right
    if innerWidth < 600 then innerWidth = 992 end
    Measure(innerWidth)

    f.stepText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.stepText:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    f.stepText:SetTextColor(0.7, 0.7, 0.7, 1)

    f.pages = {}

    -- Welcome
    local p1 = CreatePage(f)
    p1.logo = p1:CreateTexture(nil, "ARTWORK")
    p1.logo:SetSize(150, 150)
    p1.logo:SetPoint("TOP", p1, "TOP", 0, -30)
    p1.logo:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png")
    p1.heading:ClearAllPoints()
    p1.heading:SetPoint("TOP", p1.logo, "BOTTOM", 0, -18)
    p1.heading:SetJustifyH("CENTER")
    p1.heading:SetText(L["Welcome to Oxed Hub"])
    p1.text:SetFontObject(GameFontHighlightLarge)
    p1.text:ClearAllPoints()
    p1.text:SetPoint("TOP", p1.heading, "BOTTOM", 0, -16)
    p1.text:SetWidth(PAGE_W - 120)
    p1.text:SetJustifyH("CENTER")
    p1.text:SetSpacing(4)
    p1.text:SetText(L["Oxed Hub is several tools in one window. Choose the ones you want, and the rest stay out of your way."]
        .. "\n\n" .. L["Dashboard and Settings are always there."]
        .. "\n\n" .. L["It takes a minute. Nothing is deleted, and you can come back to this at any time."])
    f.pages.welcome = p1

    -- Sections
    local p2 = CreatePage(f)
    p2.heading:SetText(L["What do you need?"])
    p2.text:SetText(L["Click a card to add or remove it. Choose at least one. You can change this later."])
    p2.cards = {}
    for i, entry in ipairs(Sections.LIST) do
        local card = CreateCard(p2, entry)
        local column = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        card:SetPoint("TOPLEFT", p2, "TOPLEFT", column * (CARD_W + CARD_GAP), -(64 + row * (CARD_H + 12)))
        p2.cards[i] = card
    end
    f.pages.sections = p2

    -- Modules
    local p3 = CreatePage(f)
    p3.heading:SetWidth(PAGE_W - 410)
    p3.heading:SetText(L["Which modules?"])
    p3.text:SetText(L["Tick the modules you want. Only these are switched on and listed in the Modules page. You can add more there later."])
    p3.clear = RedButton(p3, 110, L["Clear all"])
    p3.clear:SetPoint("TOPRIGHT", p3, "TOPRIGHT", 0, 2)
    p3.clear:SetScript("OnClick", function()
        for id in pairs(moduleChoice) do
            moduleChoice[id] = false
        end
        Wizard:Refresh()
    end)
    p3.count = p3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p3.selectAll = RedButton(p3, 110, L["Select all"])
    p3.selectAll:SetPoint("RIGHT", p3.clear, "LEFT", -8, 0)
    p3.selectAll:SetScript("OnClick", function()
        for id in pairs(moduleChoice) do
            moduleChoice[id] = true
        end
        Wizard:Refresh()
    end)
    p3.count:SetPoint("TOPRIGHT", p3, "TOPRIGHT", -240, -4)
    p3.count:SetTextColor(0.4, 1, 0.4, 1)
    p3.scroll, p3.child = CreateScroll(p3)
    p3.scroll:SetPoint("TOPLEFT", p3, "TOPLEFT", 0, -62)
    p3.scroll:SetPoint("BOTTOMRIGHT", p3, "BOTTOMRIGHT", -26, 0)
    local Scroll = OxedHub.UIComponents and OxedHub.UIComponents.Scroll
    if Scroll and Scroll.StyleFrame then
        pcall(Scroll.StyleFrame, p3.scroll)
    end
    f.pages.modules = p3

    -- Done
    local p4 = CreatePage(f)
    p4.heading:SetText(L["All set"])
    p4.text:SetText(L["These sections will be in your window:"])
    p4.list = p4:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    p4.list:SetPoint("TOPLEFT", p4.text, "BOTTOMLEFT", 12, -18)
    p4.list:SetWidth(PAGE_W - 12)
    p4.list:SetJustifyH("LEFT")
    p4.list:SetSpacing(10)
    p4.modules = p4:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p4.modules:SetPoint("TOPLEFT", p4.list, "BOTTOMLEFT", 0, -20)
    p4.modules:SetWidth(PAGE_W - 12)
    p4.modules:SetJustifyH("LEFT")
    p4.note = p4:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    p4.note:SetPoint("BOTTOMLEFT", p4, "BOTTOMLEFT", 0, 6)
    p4.note:SetWidth(PAGE_W)
    p4.note:SetJustifyH("LEFT")
    p4.note:SetTextColor(0.7, 0.7, 0.7, 1)
    p4.note:SetText(L["To change this later, press System on the Dashboard."])
    f.pages.done = p4

    -- The way out for a player who does not want to choose: the addon as it
    -- comes, every section on and no module switched (Wizard:Skip).
    f.skipBtn = RedButton(f, 110, L["Skip"])
    f.skipBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 4)
    f.skipBtn:SetScript("OnClick", function()
        Wizard:ConfirmSkip()
    end)
    f.skipBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Skip"])
        GameTooltip:AddLine(L["Keep every section, as the addon comes. Modules stay as they are, off until you switch them on."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.skipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.backBtn = RedButton(f, 130, L["Back"])
    f.backBtn:SetPoint("LEFT", f.skipBtn, "RIGHT", 10, 0)
    f.backBtn:SetScript("OnClick", function()
        -- On its own the list has no step to go back to: the button is
        -- Cancel there, and leaves without saving.
        if modulesOnly then
            outer:Hide()
            return
        end
        if step > 1 then
            step = step - 1
            Wizard:Refresh()
        end
    end)

    f.nextBtn = RedButton(f, 130, L["Next"])
    f.nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    f.nextBtn:SetScript("OnClick", function()
        local steps = StepList()
        if step < #steps then
            -- The button is disabled when nothing is ticked; this is the second lock.
            if steps[step] == "sections" and Sections:CountChosen(choice) < 1 then
                return
            end
            step = step + 1
            Wizard:Refresh()
        else
            Wizard:Finish()
        end
    end)

    frame = f
end

function Wizard:Refresh()
    if not frame then return end
    local Sections = OxedHub.Sections

    local steps = StepList()
    if step > #steps then step = #steps end
    if step < 1 then step = 1 end
    local name = steps[step]

    for key, page in pairs(frame.pages) do
        page:SetShown(key == name)
    end

    if modulesOnly then
        frame.stepText:SetText("")
        frame.skipBtn:Hide()
        frame.backBtn:Show()
        frame.backBtn:SetText(L["Cancel"])
        frame.backBtn:ClearAllPoints()
        frame.backBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 4)
        frame.nextBtn:SetText(L["Save"])
    else
        frame.stepText:SetText(string.format(L["Step %d of %d"], step, #steps))
        frame.skipBtn:Show()
        frame.backBtn:SetShown(step > 1)
        frame.backBtn:SetText(L["Back"])
        frame.backBtn:ClearAllPoints()
        frame.backBtn:SetPoint("LEFT", frame.skipBtn, "RIGHT", 10, 0)
        frame.nextBtn:SetText(step == #steps and L["Finish"] or L["Next"])
    end

    local canGoOn = name ~= "sections" or Sections:CountChosen(choice) >= 1
    frame.nextBtn:SetEnabled(canGoOn)
    frame.nextBtn:SetAlpha(canGoOn and 1 or 0.45)

    if name == "sections" then
        for _, card in ipairs(frame.pages.sections.cards) do
            PaintBox(card, choice[card.key] == true)
        end
    elseif name == "modules" then
        local page = frame.pages.modules
        BuildModuleRows(page)
        for _, row in ipairs(page.rows or {}) do
            PaintBox(row, moduleChoice[row.id] == true)
        end
        self:UpdateModuleCount()
    elseif name == "done" then
        local page = frame.pages.done
        local lines = {}
        for _, entry in ipairs(Sections.LIST) do
            if choice[entry.key] then
                lines[#lines + 1] = string.format("|T%s:24:24:0:0|t  %s", tostring(entry.icon), SectionLabel(entry.key))
            end
        end
        page.list:SetText(table.concat(lines, "\n"))
        if choice.Modules then
            page.modules:SetText(string.format(L["Modules switched on: %d"], CountModulesChosen()))
        else
            page.modules:SetText("")
        end
    end
end

-- Makes the ticks the player's pick of modules: the Modules page lists only
-- these from now on. A module ticked for the first time is switched on, one
-- that was left out is switched off, and one that was already in the pick
-- keeps whatever the player set on its card since.
local function ApplyModuleChoice()
    local API = OxedHub.ModuleAPI
    if not API or not API.SetModuleEnabled then return end
    local hadPicks = API.HasModulePicks and API:HasModulePicks()
    API.switchingAll = true
    for id, on in pairs(moduleChoice) do
        if API.modules and API.modules[id] then
            local enabled = API:IsModuleEnabled(id)
            if on then
                local alreadyPicked = hadPicks and API:IsModulePicked(id)
                if not alreadyPicked and not enabled then
                    pcall(API.SetModuleEnabled, API, id, true)
                end
            elseif enabled then
                pcall(API.SetModuleEnabled, API, id, false)
            end
        end
    end
    API.switchingAll = nil
    if API.SetModulePicks then
        API:SetModulePicks(moduleChoice)
    end
    if API.RefreshModulesTab then
        pcall(API.RefreshModulesTab, API)
    end
end

function Wizard:Finish()
    local Sections = OxedHub.Sections
    if not Sections then return end
    -- Some modules show or hide secure buttons when they start, which the game
    -- refuses in combat, so the whole choice waits.
    if InCombatLockdown() then
        print(L["|cffff0000[OxedHub]|r Finish the setup after combat."])
        return
    end
    -- From "Add modules" only the pick of modules is saved, and the player is
    -- put back on the Modules page they came from.
    if modulesOnly then
        if frame then
            frame.outer:Hide()
        end
        ApplyModuleChoice()
        local UI = OxedHub.UI
        if UI then
            if UI.ApplySections then UI:ApplySections() end
            if UI.ShowTab then UI:ShowTab("Modules") end
        end
        return
    end
    if not Sections:Save(choice) then
        return
    end
    -- Hiding it hands the window back: sidebar live, Dashboard shown.
    if frame then
        frame.outer:Hide()
    end

    -- Left out of the choice, the module ticks are not touched at all.
    if choice.Modules then
        ApplyModuleChoice()
    end

    local UI = OxedHub.UI
    if UI then
        if UI.ApplySections then
            UI:ApplySections()
        end
        if UI.ShowTab then
            UI:ShowTab("Dashboard")
        end
    end
    print(L["|cff00ff00Oxed Hub:|r sections saved."])
    self:OfferReload()
end

-- Skip is asked about first, so nobody lands in the full addon by a stray
-- click: the popup says what will be running.
function Wizard:ConfirmSkip()
    local Sections = OxedHub.Sections
    if not Sections then return end
    local names = {}
    for _, entry in ipairs(Sections.LIST) do
        names[#names + 1] = SectionLabel(entry.key)
    end
    StaticPopupDialogs["OXEDHUB_WIZARD_SKIP"] = {
        text = L["Skip the setup?"] .. "\n\n"
            .. L["Oxed Hub will start with all its standard features:"] .. "\n|cffffd100"
            .. table.concat(names, ", ") .. "|r\n\n"
            .. L["Modules stay off until you switch them on."],
        button1 = L["Skip"],
        button2 = L["Back"],
        OnAccept = function()
            Wizard:Skip()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("OXEDHUB_WIZARD_SKIP")
end

-- Shown by itself the first time the main window is opened by a player who
-- has not chosen yet (UI:ShowMainWindow calls this). Offered once per account:
-- closing the window without answering does not bring it back every time.
-- The mark is set before Show, which opens the window and so comes back here.
--
-- ⚠ Switched off while the wizard is being tested: with AUTO_OFFER false it
-- never opens by itself, for anybody, and /oxedhub wizard is the only way in.
-- Set it to true to release it.
local AUTO_OFFER = false

function Wizard:OfferFirstRun()
    if not AUTO_OFFER then return end
    local Sections = OxedHub.Sections
    if not Sections or Sections:HasChosen() then return end
    local gs = type(OxedHubDB) == "table" and OxedHubDB.globalSettings
    if type(gs) ~= "table" or gs.wizardOffered then return end
    if InCombatLockdown() then return end
    gs.wizardOffered = true
    self:Show(1)
end

-- Skip: the addon as it comes. Every section is saved as on, whatever was
-- ticked on the cards, and no module is switched either way. Saving (rather
-- than leaving no choice at all) records that the player has been through
-- setup, which is what shows the Dashboard's System button.
function Wizard:Skip()
    local Sections = OxedHub.Sections
    if not Sections then return end
    local all = {}
    for _, entry in ipairs(Sections.LIST) do
        all[entry.key] = true
    end
    if not Sections:Save(all) then
        return
    end
    -- As the addon comes: the Modules page lists every module.
    if OxedHub.ModuleAPI and OxedHub.ModuleAPI.SetModulePicks then
        OxedHub.ModuleAPI:SetModulePicks(nil)
    end
    if frame then
        frame.outer:Hide()
    end
    local UI = OxedHub.UI
    if UI then
        if UI.ApplySections then
            UI:ApplySections()
        end
        if UI.ShowTab then
            UI:ShowTab("Dashboard")
        end
    end
    print(L["|cff00ff00Oxed Hub:|r setup skipped. Every section is on."])
    self:OfferReload()
end

-- The window follows a new choice at once, but the work of a section (rules,
-- the ring's key, hubs, the dock, modules) starts and stops only at login. So
-- when the choice differs from what this session is running, ask for a reload.
function Wizard:OfferReload()
    local Sections = OxedHub.Sections
    if not Sections or not Sections:NeedsReload() then
        return
    end
    StaticPopupDialogs["OXEDHUB_SECTIONS_RELOAD"] = {
        text = L["Oxed Hub switches sections on and off when the interface reloads. Reload now?"],
        button1 = L["Reload"],
        button2 = L["Later"],
        OnAccept = function()
            ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_SECTIONS_RELOAD")
end

-- startStep is optional. Without it a player who has already chosen goes
-- straight to the cards, and a new one starts at the welcome.
function Wizard:Show(startStep, onlyModules)
    modulesOnly = onlyModules and true or false
    local Sections = OxedHub.Sections
    local UI = OxedHub.UI
    if not Sections or not UI or not UI.SetWizardMode then return end
    -- It lives inside the main window, which cannot be opened in combat.
    if InCombatLockdown() then
        print(L["|cffff0000[OxedHub]|r The setup cannot be opened in combat."])
        return
    end
    UI:ShowMainWindow()
    if not frame then
        Build()
    end
    if not frame then return end

    -- Asked before anything can be changed, so the session's own state is on
    -- record even if nothing else has asked yet.
    Sections:NeedsReload()
    choice = Sections:GetChoice()

    step = startStep or (Sections:HasChosen() and 2 or 1)

    -- A setup from the start is a clean sheet: no module is ticked, and what
    -- the player ticks is exactly what will be on. Starting with the old ones
    -- ticked far down a long list left them on without the player seeing it.
    -- Coming back through the System button or the Modules page's "Add
    -- modules" is an edit, so it starts from the modules picked last time
    -- (or, with no pick yet, from what is switched on now).
    local cleanSheet = step == 1 and not modulesOnly
    moduleChoice = {}
    local API = OxedHub.ModuleAPI
    if API and API.modules then
        for id, mod in pairs(API.modules) do
            if mod._registered then
                local ticked = false
                if not cleanSheet then
                    if API.HasModulePicks and API:HasModulePicks() then
                        ticked = API:IsModulePicked(id)
                    else
                        ticked = API:IsModuleEnabled(id)
                    end
                end
                moduleChoice[id] = ticked and true or false
            end
        end
    end

    self:Refresh()
    UI:SetWizardMode(true)
    frame.outer:Show()
end

-- Straight to the module list, from the Modules page's "Add modules".
function Wizard:ShowModules()
    self:Show(1, true)
end

function Wizard:Hide()
    if frame then
        frame.outer:Hide()
    end
end
