-- ============================================================================
-- Mail (built-in OxedHub module)
-- What the mailbox leaves you to do by hand:
--
--   open all      one button takes the gold and the attachments of every
--                 letter, one letter at a time, and stops when the bags fill
--   summary       how many letters, how much gold, what expires soon
--   address book  the names you write to, with the last ones a click away
--   copies        the same letter sent to several people in turn
--   session       what the visit was worth, printed when the box closes
--
-- A bar under the mailbox window holds all of it, so nothing of Blizzard's is
-- moved or covered.
--
-- ⚠ Mail actions go to the server one at a time, spaced (STEP). A burst is
-- partly dropped, and a dropped take gives no error -- the letter simply stays
-- there. The same rule as AutoBanker's deposits.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,   -- off until the player switches it on

    takeGold     = true,    -- collect the coins as well as the attachments
    skipCOD      = true,    -- never pay a cash on delivery letter
    keepUnread   = false,   -- leave letters you have not opened yet alone
    summaryBar   = true,    -- the line of figures above the buttons
    warnExpiring = true,    -- letters with less than three days left
    sessionTotal = true,    -- print what the visit was worth when it closes

    addressBook  = true,    -- the Book button on the send page
    learnNames   = true,    -- remember who you write to
    copies       = true,    -- the recent names on the bar
    ticks        = true,    -- a box on every letter, for Return and Tidy up
    attaching    = true,    -- the Attach button on the send page
    forwarding   = true,    -- the Forward button on an open letter

    -- "contacts" and "recent" are tables and are built in BindSettings:
    -- a table in DEFAULTS is copied by reference and every character would
    -- share one address book by accident.
}

local settings          -- OxedHubDB.modules.mail, bound at login
local optionsWindow
local bar               -- our strip under the mailbox
local bookWindow
local attachWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ccffOxedHub Mail:|r "
local STEP = 0.35       -- seconds between one take and the next
local MAX_TRIES = 6     -- attempts on one letter before moving on
local EXPIRING_DAYS = 3
local RECENT_KEEP = 8

-- ── Reading the inbox ───────────────────────────────────────────────────────
-- ⚠ On 12.0 a sender's name and a subject can be secret values, and a string
-- operation on one is an error. Everything read here goes through these, so a
-- secret simply reads as "unknown" rather than breaking the letter's row.

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeText(value)
    if IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

local function SafeNumber(value)
    if IsSecret(value) or type(value) ~= "number" then return 0 end
    return value
end

-- One letter, in plain fields. Nil when the index holds nothing.
local function LetterAt(index)
    if not GetInboxHeaderInfo then return nil end
    local ok, _, _, sender, subject, money, cod, daysLeft, itemCount, wasRead = pcall(GetInboxHeaderInfo, index)
    if not ok then return nil end
    -- An index past the last letter answers with nothing at all. Without this
    -- the empty rows of the last page were given a tick box of their own.
    if sender == nil and subject == nil and daysLeft == nil and itemCount == nil then
        return nil
    end
    return {
        sender = SafeText(sender),
        subject = SafeText(subject),
        money = SafeNumber(money),
        cod = SafeNumber(cod),
        daysLeft = SafeNumber(daysLeft),
        items = SafeNumber(itemCount),
        read = wasRead and true or false,
    }
end

local function FreeBagSlots()
    if CalculateTotalNumberOfFreeBagSlots then
        local ok, free = pcall(CalculateTotalNumberOfFreeBagSlots)
        if ok and type(free) == "number" then return free end
    end
    local free = 0
    if C_Container and C_Container.GetContainerNumFreeSlots then
        for bag = 0, 4 do
            local ok, slots = pcall(C_Container.GetContainerNumFreeSlots, bag)
            if ok and type(slots) == "number" then free = free + slots end
        end
    end
    return free
end

local function Gold(copper)
    if GetMoneyString then
        local ok, text = pcall(GetMoneyString, copper, true)
        if ok and text then return text end
    end
    return ("%dg"):format(math.floor((copper or 0) / 10000))
end

-- ── What the box holds ──────────────────────────────────────────────────────

local function Survey()
    local letters, items, money, expiring, cod = 0, 0, 0, 0, 0
    local count = GetInboxNumItems and GetInboxNumItems() or 0
    for index = 1, count do
        local letter = LetterAt(index)
        if letter then
            letters = letters + 1
            items = items + letter.items
            money = money + letter.money
            if letter.cod > 0 then cod = cod + 1 end
            if letter.daysLeft > 0 and letter.daysLeft < EXPIRING_DAYS then
                expiring = expiring + 1
            end
        end
    end
    return letters, items, money, expiring, cod
end

-- ── Taking it all ───────────────────────────────────────────────────────────
-- Downward through the list: taking a letter empty deletes it and shifts every
-- index above it down, and those are the ones already done.

local run = { active = false }

local function StopRun(reason)
    if not run.active then return end
    run.active = false
    if run.timer then run.timer:Cancel() run.timer = nil end

    local parts = {}
    if run.money > 0 then parts[#parts + 1] = Gold(run.money) end
    if run.items > 0 then parts[#parts + 1] = ("%d items"):format(run.items) end
    local took = #parts > 0 and table.concat(parts, " and ") or "nothing"

    if reason == "full" then
        print(PREFIX .. ("bags are full. Took %s; make room and press it again."):format(took))
    elseif reason == "done" then
        print(PREFIX .. ("took %s."):format(took))
    end

    run.sessionMoney = (run.sessionMoney or 0) + run.money
    run.sessionItems = (run.sessionItems or 0) + run.items
    if bar then bar.Refresh() end
end

local Take   -- one step, defined below

local function Schedule()
    run.timer = C_Timer.NewTimer(STEP, Take)
end

Take = function()
    run.timer = nil
    if not run.active then return end
    if not (MailFrame and MailFrame:IsShown()) then return StopRun("closed") end

    local count = GetInboxNumItems and GetInboxNumItems() or 0
    if run.index > count then run.index = count end
    if run.index < 1 then return StopRun("done") end

    local letter = LetterAt(run.index)
    if not letter then
        run.index = run.index - 1
        return Schedule()
    end

    -- Left alone: a letter that would cost money, an unread one when asked,
    -- and anyone on the skip list.
    local skip = (settings.skipCOD and letter.cod > 0)
        or (settings.keepUnread and not letter.read)
    if skip then
        run.index = run.index - 1
        return Schedule()
    end

    local wantsItems = letter.items > 0
    local wantsMoney = settings.takeGold and letter.money > 0

    if wantsItems and FreeBagSlots() < 1 then
        return StopRun("full")
    end

    if not wantsItems and not wantsMoney then
        run.index = run.index - 1
        return Schedule()
    end

    -- The same letter is only worth so many tries: a take the server drops
    -- leaves it exactly as it was, and without this the run would sit on it.
    run.tries = (run.tries or 0) + 1
    if run.tries > MAX_TRIES then
        run.tries = 0
        run.index = run.index - 1
        return Schedule()
    end

    -- Counted before the take, since the letter is gone once it empties.
    if wantsItems then
        if AutoLootMailItem then pcall(AutoLootMailItem, run.index) end
        run.items = run.items + letter.items
        if settings.takeGold then run.money = run.money + letter.money end
    else
        if TakeInboxMoney then pcall(TakeInboxMoney, run.index) end
        run.money = run.money + letter.money
    end

    -- Read again on the next step: if it emptied, the letter is gone and this
    -- index now holds the one that was above it.
    local expected = run.index
    C_Timer.After(STEP * 0.5, function()
        if not run.active then return end
        local now = LetterAt(expected)
        local emptied = not now
            or (now.items == 0 and (now.money == 0 or not settings.takeGold))
        if emptied then
            run.tries = 0
            run.index = run.index - 1
        end
    end)
    Schedule()
end

local function StartRun()
    if run.active then return StopRun("stopped") end
    if not (MailFrame and MailFrame:IsShown()) then return end

    local count = GetInboxNumItems and GetInboxNumItems() or 0
    if count < 1 then
        print(PREFIX .. "the box is empty.")
        return
    end

    run.active, run.index, run.tries = true, count, 0
    run.money, run.items = 0, 0
    if bar then bar.Refresh() end
    Take()
end

-- ── The address book ────────────────────────────────────────────────────────

local function NameKey(name)
    return type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local function Remember(name)
    name = NameKey(name)
    if name == "" or not settings then return end

    settings.contacts[name] = settings.contacts[name] or { at = time() }
    settings.contacts[name].at = time()

    -- The recent list, newest first, without repeats.
    local recent = settings.recent
    for index = #recent, 1, -1 do
        if recent[index] == name then table.remove(recent, index) end
    end
    table.insert(recent, 1, name)
    while #recent > RECENT_KEEP do table.remove(recent) end
end

local function Forget(name)
    if not settings then return end
    settings.contacts[NameKey(name)] = nil
    for index = #settings.recent, 1, -1 do
        if settings.recent[index] == name then table.remove(settings.recent, index) end
    end
end

local function SortedContacts(filter)
    local list = {}
    filter = (filter or ""):lower()
    for name in pairs(settings.contacts or {}) do
        if filter == "" or name:lower():find(filter, 1, true) then
            list[#list + 1] = name
        end
    end
    table.sort(list)
    return list
end

local function WriteTo(name)
    if not (MailFrameTab2 and SendMailNameEditBox) then return end
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, MailFrameTab2, 2) end
    SendMailNameEditBox:SetText(name)
    SendMailNameEditBox:SetFocus()
end

-- ── Copies ──────────────────────────────────────────────────────────────────
-- The same letter to several people. Text only: an attachment exists once and
-- cannot be sent twice, so copies carry the subject and the body.

local queue = {}

local function SendNext()
    local entry = table.remove(queue, 1)
    if not entry then return end
    if SendMail then pcall(SendMail, entry.name, entry.subject, entry.body) end
    print(PREFIX .. ("copy sent to |cffffd100%s|r."):format(entry.name))
    if #queue > 0 then C_Timer.After(1.2, SendNext) end
end

local function QueueCopies(names, subject, body)
    for _, name in ipairs(names) do
        queue[#queue + 1] = { name = name, subject = subject, body = body }
    end
    -- After the letter the player sent themselves, spaced: several SendMail
    -- calls in one moment are dropped by the server.
    if #queue > 0 then C_Timer.After(1.5, SendNext) end
end

-- A scroll area with the addon's own slim bar rather than the old template,
-- whose arrow buttons hang outside the window's edge.
local function ScrollArea(window, bottomInset)
    local scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", 14, -66)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -26, bottomInset)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local limit = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(limit, self:GetVerticalScroll() - delta * 40)))
    end)
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    end

    scroll:HookScript("OnSizeChanged", function(self)
        content:SetWidth(self:GetWidth())
    end)
    content:SetWidth(window:GetWidth() - 40)
    return scroll, content
end

-- Only one of the two side windows at a time: opened together they landed on
-- the same spot and sat on top of each other.
local function ShowOnly(which)
    if which ~= bookWindow and bookWindow then bookWindow:Hide() end
    if which ~= attachWindow and attachWindow then attachWindow:Hide() end
    if which then which:Show() end
end

-- ── The book window ─────────────────────────────────────────────────────────

local function BuildBook()
    if bookWindow then return bookWindow end

    local ok, window = pcall(CreateFrame, "Frame", "OxedHubMailBook", UIParent, "BasicFrameTemplate")
    if not ok or not window then return nil end
    window:SetSize(300, 420)
    window:SetPoint("TOPLEFT", MailFrame or UIParent, "TOPRIGHT", 6, 0)
    window:SetFrameStrata("HIGH")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.TitleText then window.TitleText:SetText("Address Book") end
    tinsert(UISpecialFrames, "OxedHubMailBook")

    -- ⚠ SetAutoFocus(false): a new EditBox takes the keyboard the moment it
    -- exists, and an addon that swallows every key is unusable.
    local search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    search:SetAutoFocus(false)
    search:SetSize(236, 20)
    search:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -32)
    window.search = search

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    hint:SetText("Click a name to write to it, right-click to forget it.")

    local scroll, content = ScrollArea(window, 44)

    local rows = {}
    local function Refresh()
        local names = SortedContacts(search:GetText())
        local y = 0
        for index, name in ipairs(names) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(20)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
                row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.text:SetJustifyH("LEFT")
                row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
                rows[index] = row
            end
            row.name = name
            row.text:SetText(name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    Forget(self.name)
                    window.Refresh()
                else
                    WriteTo(self.name)
                end
            end)
            row:Show()
            y = y + 20
        end
        for index = #names + 1, #rows do rows[index]:Hide() end
        content:SetHeight(math.max(1, y))
        window.empty:SetShown(#names == 0)
    end
    window.Refresh = Refresh

    window.empty = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    window.empty:SetPoint("CENTER", scroll, "CENTER")
    window.empty:SetText("No names yet")

    search:SetScript("OnTextChanged", Refresh)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Add whoever is in the To box right now.
    local add = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    add:SetSize(110, 22)
    add:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 14, 14)
    add:SetText("Add the To name")
    add:SetScript("OnClick", function()
        local name = SendMailNameEditBox and SendMailNameEditBox:GetText()
        if NameKey(name) == "" then
            print(PREFIX .. "write a name on the send page first.")
            return
        end
        Remember(name)
        Refresh()
    end)

    -- Every ticked name gets a copy of the letter being written.
    local copies = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    copies:SetSize(110, 22)
    copies:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -14, 14)
    copies:SetText("Copy to all")
    copies:SetScript("OnClick", function()
        local subject = SendMailSubjectEditBox and SendMailSubjectEditBox:GetText() or ""
        local body = SendMailBodyEditBox and SendMailBodyEditBox:GetText() or ""
        local to = NameKey(SendMailNameEditBox and SendMailNameEditBox:GetText() or "")
        local names = {}
        for _, name in ipairs(SortedContacts(search:GetText())) do
            if name ~= to then names[#names + 1] = name end
        end
        if #names == 0 then
            print(PREFIX .. "no other names to copy to.")
            return
        end
        if subject == "" and body == "" then
            print(PREFIX .. "write the letter first; copies carry its text, never its attachments.")
            return
        end
        QueueCopies(names, subject, body)
        print(PREFIX .. ("sending %d copies, one a second."):format(#names))
    end)

    window:SetScript("OnShow", Refresh)
    window:Hide()
    bookWindow = window
    return window
end

-- ── Ticking letters ─────────────────────────────────────────────────────────
-- A box on every row of the inbox. The selection is by index and is dropped
-- whenever the inbox changes, because the indices move underneath it: tick,
-- then press, and what you ticked is what happens.

local selected = {}
local ROWS_PER_PAGE = 7
local checks = {}

local function ClearSelection()
    wipe(selected)
    for _, box in pairs(checks) do box:SetChecked(false) end
end

local function SelectedIndices()
    local list = {}
    for index, on in pairs(selected) do
        if on then list[#list + 1] = index end
    end
    -- Highest first: acting on one letter shifts every index above it down,
    -- and those are the ones already dealt with.
    table.sort(list, function(a, b) return a > b end)
    return list
end

local function PageOffset()
    local page = InboxFrame and InboxFrame.pageNum or 1
    return (page - 1) * ROWS_PER_PAGE
end

local function RefreshChecks()
    if not settings or settings.enabled == false then return end
    local offset = PageOffset()
    for row = 1, ROWS_PER_PAGE do
        local parent = _G["MailItem" .. row]
        if parent then
            local box = checks[row]
            if not box then
                box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
                box:SetSize(20, 20)
                -- Bottom right: the days left are printed at the top right.
                box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 4)
                box:SetScript("OnClick", function(self)
                    if self.mailIndex then
                        selected[self.mailIndex] = self:GetChecked() and true or nil
                    end
                end)
                box:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText("Pick this letter")
                    GameTooltip:AddLine("Then use Return or Tidy up on the bar below.", 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                box:SetScript("OnLeave", function() GameTooltip:Hide() end)
                checks[row] = box
            end
            local index = offset + row
            local letter = LetterAt(index)
            box.mailIndex = index
            box:SetChecked(selected[index] and true or false)
            box:SetShown(settings.ticks == true and letter ~= nil and parent:IsShown())
        end
    end
end

-- Runs one action over a list of letters, spaced, and says what it did.
local function RunOver(indices, action, verb)
    if #indices == 0 then
        print(PREFIX .. "no letters picked.")
        return
    end
    for step, index in ipairs(indices) do
        C_Timer.After(STEP * step, function()
            if MailFrame and MailFrame:IsShown() then pcall(action, index) end
        end)
    end
    print(PREFIX .. ("%s %d letters."):format(verb, #indices))
    C_Timer.After(STEP * (#indices + 1), function()
        ClearSelection()
        if CheckInbox then pcall(CheckInbox) end
    end)
end

local function ReturnSelected()
    local indices = SelectedIndices()
    if #indices == 0 then return print(PREFIX .. "tick the letters to send back first.") end
    OxedHub.ModuleAPI:Confirm(("Send %d letters back to their senders?"):format(#indices), function()
        RunOver(indices, ReturnInboxItem, "sending back")
    end)
end

-- Only letters that are read, hold nothing and owe nothing: throwing one of
-- those away loses nothing. Anything with an attachment or a coin in it is
-- never touched, ticked or not.
local function TidyUp()
    local count = GetInboxNumItems and GetInboxNumItems() or 0
    local empties = {}
    for index = count, 1, -1 do
        local letter = LetterAt(index)
        if letter and letter.read and letter.items == 0 and letter.money == 0 and letter.cod == 0 then
            empties[#empties + 1] = index
        end
    end
    if #empties == 0 then
        print(PREFIX .. "nothing to tidy: every letter still holds something.")
        return
    end
    OxedHub.ModuleAPI:Confirm(("Throw away %d read letters that hold nothing?"):format(#empties), function()
        RunOver(empties, DeleteInboxItem, "throwing away")
    end)
end

-- ── Attaching from the bags ─────────────────────────────────────────────────

local ATTACH_SLOTS = 12

local function BagItems(filter)
    local list = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return list end
    filter = (filter or ""):lower()
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and info and info.itemID then
                local name
                if C_Item and C_Item.GetItemNameByID then
                    local okName, itemName = pcall(C_Item.GetItemNameByID, info.itemID)
                    if okName then name = SafeText(itemName) end
                end
                name = name or ("Item " .. tostring(info.itemID))
                if filter == "" or name:lower():find(filter, 1, true) then
                    list[#list + 1] = {
                        bag = bag, slot = slot, name = name,
                        icon = info.iconFileID, count = info.stackCount or 1,
                        locked = info.isLocked,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function AttachedCount()
    local used = 0
    for slot = 1, ATTACH_SLOTS do
        if GetSendMailItem and GetSendMailItem(slot) then used = used + 1 end
    end
    return used
end

-- One item onto the letter. The cursor is ours for that instant only.
local function AttachItem(bag, slot)
    if AttachedCount() >= ATTACH_SLOTS then
        print(PREFIX .. "the letter is full: twelve attachments is the limit.")
        return false
    end
    if not (C_Container and C_Container.PickupContainerItem and ClickSendMailItemButton) then return false end
    if CursorHasItem and CursorHasItem() then ClearCursor() end
    local ok = pcall(C_Container.PickupContainerItem, bag, slot)
    if not ok then return false end
    local placed = pcall(ClickSendMailItemButton)
    if not placed then
        if ClearCursor then ClearCursor() end
        return false
    end
    return true
end

local function BuildAttachWindow()
    if attachWindow then return attachWindow end
    local ok, window = pcall(CreateFrame, "Frame", "OxedHubMailAttach", UIParent, "BasicFrameTemplate")
    if not ok or not window then return nil end
    window:SetSize(300, 420)
    window:SetPoint("TOPLEFT", MailFrame or UIParent, "TOPRIGHT", 6, 0)
    window:SetFrameStrata("HIGH")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    if window.TitleText then window.TitleText:SetText("Attach from bags") end
    tinsert(UISpecialFrames, "OxedHubMailAttach")

    local search = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
    search:SetAutoFocus(false)   -- ⚠ never a focused EditBox: it eats every key
    search:SetSize(236, 20)
    search:SetPoint("TOPLEFT", window, "TOPLEFT", 18, -32)

    local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -4)
    hint:SetText("Click an item to attach it. Twelve fit on a letter.")

    local scroll, content = ScrollArea(window, 14)

    local rows = {}
    local function Refresh()
        local items = BagItems(search:GetText())
        local y = 0
        for index, item in ipairs(items) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetHeight(22)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(18, 18)
                row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
                row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
                row.text:SetJustifyH("LEFT")
                row:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight", "ADD")
                rows[index] = row
            end
            row.icon:SetTexture(item.icon)
            row.text:SetText(item.count > 1 and ("%s |cff808080x%d|r"):format(item.name, item.count) or item.name)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
            row:SetScript("OnClick", function()
                if AttachItem(item.bag, item.slot) then
                    C_Timer.After(0.1, Refresh)
                end
            end)
            row:Show()
            y = y + 22
        end
        for index = #items + 1, #rows do rows[index]:Hide() end
        content:SetHeight(math.max(1, y))
    end
    window.Refresh = Refresh

    search:SetScript("OnTextChanged", Refresh)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    window:SetScript("OnShow", Refresh)
    window:Hide()
    attachWindow = window
    return window
end

-- ── Passing a letter on ─────────────────────────────────────────────────────
-- The open letter's text goes to someone else. Its attachments come to the
-- bags first and are put back on the new letter: an attachment exists once,
-- so it has to travel through you.

local function OpenLetterIndex()
    local index = InboxFrame and InboxFrame.openMailID
    return type(index) == "number" and index or nil
end

local function BagSnapshot()
    local snapshot = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return snapshot end
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and info and info.itemID then
                snapshot[bag * 100 + slot] = info.itemID
            end
        end
    end
    return snapshot
end

local function NewSlotsSince(before)
    local fresh = {}
    if not (C_Container and C_Container.GetContainerNumSlots) then return fresh end
    for bag = 0, 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and info and info.itemID and before[bag * 100 + slot] ~= info.itemID then
                fresh[#fresh + 1] = { bag = bag, slot = slot }
            end
        end
    end
    return fresh
end

local function Forward(to)
    local index = OpenLetterIndex()
    if not index then
        print(PREFIX .. "open a letter first.")
        return
    end
    local letter = LetterAt(index)
    if not letter then return end

    local body = ""
    if GetInboxText then
        local ok, text = pcall(GetInboxText, index)
        if ok then body = SafeText(text) or "" end
    end
    local subject = letter.subject or "Forwarded mail"
    if not subject:find("^Fwd: ") then subject = "Fwd: " .. subject end

    local function WriteIt(attachments)
        if MailFrameTab_OnClick and MailFrameTab2 then pcall(MailFrameTab_OnClick, MailFrameTab2, 2) end
        if SendMailNameEditBox then SendMailNameEditBox:SetText(to) end
        if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject) end
        if SendMailBodyEditBox then SendMailBodyEditBox:SetText(body) end
        local attached = 0
        for _, place in ipairs(attachments or {}) do
            if AttachItem(place.bag, place.slot) then attached = attached + 1 end
        end
        Remember(to)
        print(PREFIX .. ("ready to forward to |cffffd100%s|r%s. Press Send when it looks right."):format(
            to, attached > 0 and (" with %d attachments"):format(attached) or ""))
    end

    if letter.items > 0 then
        if FreeBagSlots() < letter.items then
            print(PREFIX .. "not enough room in the bags to hold the attachments on the way.")
            return
        end
        local before = BagSnapshot()
        if AutoLootMailItem then pcall(AutoLootMailItem, index) end
        -- The server answers in its own time; the bags are read once it has.
        C_Timer.After(0.6, function() WriteIt(NewSlotsSince(before)) end)
    else
        WriteIt(nil)
    end
end

local function AskForward()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    if not StaticPopupDialogs["OXEDHUB_MAIL_FORWARD"] then
        StaticPopupDialogs["OXEDHUB_MAIL_FORWARD"] = {
            text = "Forward this letter to:",
            button1 = ACCEPT or "Accept",
            button2 = CANCEL or "Cancel",
            hasEditBox = true,
            maxLetters = 60,
            OnShow = function(self)
                local box = self.editBox or (self.GetEditBox and self:GetEditBox())
                if box then
                    box:SetText(settings.recent[1] or "")
                    box:HighlightText()
                end
            end,
            OnAccept = function(self)
                local box = self.editBox or (self.GetEditBox and self:GetEditBox())
                local name = NameKey(box and box:GetText() or "")
                if name ~= "" then Forward(name) end
            end,
            EditBoxOnEnterPressed = function(self)
                local parent = self:GetParent()
                local name = NameKey(self:GetText())
                if name ~= "" then Forward(name) end
                parent:Hide()
            end,
            EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
    end
    StaticPopup_Show("OXEDHUB_MAIL_FORWARD")
end

-- ── The bar ─────────────────────────────────────────────────────────────────

local function BarTip(button, title, body)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 0.82, 0)
        GameTooltip:AddLine(body, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildBar()
    if bar or not _G.MailFrame then return end

    bar = CreateFrame("Frame", "OxedHubMailBar", MailFrame, "BackdropTemplate")
    -- Above the window, on a layer of its own. Below it are Blizzard's Inbox
    -- and Send Mail tabs, which the bar sat on top of.
    bar:SetPoint("BOTTOMLEFT", MailFrame, "TOPLEFT", 6, 2)
    bar:SetPoint("BOTTOMRIGHT", MailFrame, "TOPRIGHT", -6, 2)
    bar:SetFrameStrata("HIGH")
    bar:SetHeight(92)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    bar:SetBackdropBorderColor(0.35, 0.3, 0.2, 0.9)

    local summary = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", bar, "TOPLEFT", 10, -7)
    summary:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -10, -7)
    summary:SetWordWrap(false)
    summary:SetJustifyH("LEFT")
    bar.summary = summary

    bar.rows = { {}, {}, {} }   -- filled below, then laid out by Layout()

    local openAll = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    openAll:SetText("Collect All")
    openAll:SetScript("OnClick", StartRun)
    BarTip(openAll, "Collect All",
        "Takes the attachments and the coins, one letter at a time, and stops when the bags fill rather than leaving half a letter behind. Cash on delivery letters are walked past. Press again to stop.")
    bar.openAll = openAll

    local gold = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    gold:SetText("Gold only")
    BarTip(gold, "Gold only", "Takes the coins and leaves every attachment where it is, for when the bags are full.")
    gold:SetScript("OnClick", function()
        -- Coins only: the attachments are left where they are, which is what
        -- you want when the bags are full and the auction house has paid.
        local count = GetInboxNumItems and GetInboxNumItems() or 0
        local taken, total = 0, 0
        for index = count, 1, -1 do
            local letter = LetterAt(index)
            if letter and letter.money > 0 and not (settings.skipCOD and letter.cod > 0) then
                total = total + letter.money
                taken = taken + 1
                local at = index
                C_Timer.After(STEP * taken, function()
                    if TakeInboxMoney then pcall(TakeInboxMoney, at) end
                end)
            end
        end
        if taken == 0 then
            print(PREFIX .. "no coins waiting.")
        else
            print(PREFIX .. ("taking %s from %d letters."):format(Gold(total), taken))
            run.sessionMoney = (run.sessionMoney or 0) + total
        end
    end)
    bar.gold = gold

    local book = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    book:SetText("Address Book")
    BarTip(book, "Address Book", "The names you write to. Click one to start a letter, right-click to forget it.")
    book:SetScript("OnClick", function()
        local window = BuildBook()
        if window then ShowOnly(not window:IsShown() and window or nil) end
    end)
    bar.book = book

    -- Second row: what to do with the letters you ticked, and the button
    -- that fills a letter from the bags.
    local returnPicked = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    returnPicked:SetText("Return picked")
    BarTip(returnPicked, "Return picked", "Sends the ticked letters back to whoever sent them. It asks first.")
    returnPicked:SetScript("OnClick", ReturnSelected)

    local tidy = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    tidy:SetText("Tidy up")
    BarTip(tidy, "Tidy up", "Throws away read letters that hold nothing at all: no attachment, no coin, nothing owed. It asks first.")
    tidy:SetScript("OnClick", TidyUp)

    local attach = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    -- Just "Bags": the long name did not fit the button on a mailbox this narrow.
    attach:SetText("Bags")
    BarTip(attach, "Attach from bags", "A searchable list of your bags. Click an item to put it on the letter.")
    attach:SetScript("OnClick", function()
        local window = BuildAttachWindow()
        if window then ShowOnly(not window:IsShown() and window or nil) end
    end)

    -- The last few names, one click each.
    bar.recent = {}
    for index = 1, 4 do
        local button = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        button:SetNormalFontObject("GameFontHighlightSmall")
        button:SetScript("OnClick", function(self)
            if self.contact then WriteTo(self.contact) end
        end)
        bar.recent[index] = button
    end

    bar.rows[1] = { returnPicked, tidy, attach }
    bar.rows[2] = { openAll, gold, book }
    bar.rows[3] = bar.recent

    -- Every row fills the bar: each button is a share of what is left after
    -- the padding and the gaps, so nothing runs past the edge however narrow
    -- the mailbox is.
    local PAD, GAP, ROW_H = 8, 4, 22
    function bar.Layout()
        local width = bar:GetWidth()
        if not width or width < 40 then return end

        local y = 26   -- the summary line sits above the rows
        local rows = 0
        for _, row in ipairs(bar.rows) do
            local shown = {}
            for _, button in ipairs(row) do
                if button.wanted ~= false then shown[#shown + 1] = button end
            end
            if #shown > 0 then
                rows = rows + 1
                local each = (width - PAD * 2 - GAP * (#shown - 1)) / #shown
                for index, button in ipairs(shown) do
                    button:ClearAllPoints()
                    button:SetSize(each, ROW_H)
                    button:SetPoint("TOPLEFT", bar, "TOPLEFT",
                        PAD + (index - 1) * (each + GAP), -y)
                    button:Show()
                end
                y = y + ROW_H + GAP
            end
        end
        bar:SetHeight(math.max(40, y + 4))
    end
    bar:HookScript("OnSizeChanged", bar.Layout)

    function bar.Refresh()
        if not settings then return end
        local letters, items, money, expiring, cod = Survey()

        if settings.summaryBar then
            local parts = { ("%d letters"):format(letters) }
            if items > 0 then parts[#parts + 1] = ("%d attachments"):format(items) end
            if money > 0 then parts[#parts + 1] = Gold(money) end
            if cod > 0 then parts[#parts + 1] = ("|cffff8800%d cash on delivery|r"):format(cod) end
            if settings.warnExpiring and expiring > 0 then
                parts[#parts + 1] = ("|cffff3333%d expire within %d days|r"):format(expiring, EXPIRING_DAYS)
            end
            summary:SetText(table.concat(parts, "   "))
            summary:Show()
        else
            summary:Hide()
        end

        openAll:SetText(run.active and "Stop" or "Collect All")
        book.wanted = settings.addressBook == true
        returnPicked.wanted = settings.ticks == true
        tidy.wanted = settings.ticks == true
        attach.wanted = settings.attaching == true
        for _, button in ipairs({ book, returnPicked, tidy, attach }) do
            if not button.wanted then button:Hide() end
        end
        RefreshChecks()

        for index, button in ipairs(bar.recent) do
            local name = settings.copies ~= false and settings.recent[index] or nil
            button.contact = name
            button.wanted = name ~= nil
            if name then
                button:SetText(name)
            else
                button:Hide()
            end
        end

        bar.Layout()
    end

    bar:Hide()
end

-- ── Events ──────────────────────────────────────────────────────────────────

-- A Forward button on the open letter, beside Blizzard's own Reply.
local forwardButton

local function EnsureForwardButton()
    if forwardButton or not _G.OpenMailFrame then return end
    forwardButton = CreateFrame("Button", nil, OpenMailFrame, "UIPanelButtonTemplate")
    forwardButton:SetSize(80, 20)
    -- Above Reply, not beside it: that row is already full of Blizzard's own
    -- Reply, Delete and Close, and ours landed on top of them.
    if _G.OpenMailReplyButton then
        forwardButton:SetPoint("BOTTOMLEFT", OpenMailReplyButton, "TOPLEFT", 0, 3)
    else
        forwardButton:SetPoint("BOTTOMLEFT", OpenMailFrame, "BOTTOMLEFT", 22, 56)
    end
    forwardButton:SetText("Forward")
    forwardButton:SetScript("OnClick", AskForward)
    forwardButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Forward this letter")
        GameTooltip:AddLine("Its text goes to the name you give. Attachments come to your bags and are put back on the new letter, so look it over before you press Send.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    forwardButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    OpenMailFrame:HookScript("OnShow", function()
        if forwardButton then forwardButton:SetShown(settings and settings.forwarding == true) end
    end)
end

local function OnMailShown()
    BuildBar()
    EnsureForwardButton()
    if not bar then return end
    bar:Show()
    bar.Refresh()
    run.sessionMoney, run.sessionItems = 0, 0
end

local function OnMailClosed()
    StopRun("closed")
    if bar then bar:Hide() end
    if bookWindow then bookWindow:Hide() end
    if attachWindow then attachWindow:Hide() end
    ClearSelection()

    if settings and settings.sessionTotal then
        local money, items = run.sessionMoney or 0, run.sessionItems or 0
        if money > 0 or items > 0 then
            print(PREFIX .. ("this visit: %s and %d items."):format(Gold(money), items))
        end
    end
    run.sessionMoney, run.sessionItems = 0, 0
end

watcher:SetScript("OnEvent", function(_, event, arg1)
    if not settings or settings.enabled == false then return end

    if event == "MAIL_SHOW" then
        OnMailShown()
    elseif event == "MAIL_CLOSED" then
        OnMailClosed()
    elseif event == "MAIL_INBOX_UPDATE" or event == "UPDATE_PENDING_MAIL" then
        -- The letters moved, so what was ticked no longer means anything.
        ClearSelection()
        if bar and bar:IsShown() then bar.Refresh() end
    elseif event == "MAIL_SEND_SUCCESS" then
        if settings.learnNames and SendMailNameEditBox then
            Remember(SendMailNameEditBox:GetText())
        end
        if bar and bar:IsShown() then bar.Refresh() end
    end
end)

local function Start()
    for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
            "MAIL_SEND_SUCCESS", "UPDATE_PENDING_MAIL" }) do
        pcall(watcher.RegisterEvent, watcher, event)
    end
    -- Already standing at a mailbox when the module is switched on.
    if MailFrame and MailFrame:IsShown() then OnMailShown() end
end

local function Stop()
    watcher:UnregisterAllEvents()
    StopRun("closed")
    if bar then bar:Hide() end
    if bookWindow then bookWindow:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.mail
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.mail = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.contacts) ~= "table" then config.contacts = {} end
    if type(config.recent) ~= "table" then config.recent = {} end
    settings = config
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Mail", 480, 560)
        local w = optionsWindow
        local function Redraw() if bar then bar.Refresh() end end

        w:AddCheckbox(settings, "takeGold", "Open All takes the coins too",
            "Off, it collects the attachments and leaves the gold where it is.", Redraw)
        w:AddCheckbox(settings, "skipCOD", "Never open a cash on delivery letter",
            "Those cost money to accept, so Open All walks past them.")
        w:AddCheckbox(settings, "keepUnread", "Leave unread letters alone",
            "Open All only empties the letters you have already read.")
        w:AddCheckbox(settings, "summaryBar", "Show the summary line", nil, Redraw)
        w:AddCheckbox(settings, "warnExpiring", "Warn about letters running out of time",
            "Letters with less than three days left are counted in red.", Redraw)
        w:AddCheckbox(settings, "sessionTotal", "Print what the visit was worth")
        w:AddCheckbox(settings, "addressBook", "Address Book button", nil, Redraw)
        w:AddCheckbox(settings, "learnNames", "Remember who you write to")
        w:AddCheckbox(settings, "copies", "Recent names on the bar", nil, Redraw)
        w:AddCheckbox(settings, "ticks", "Tick boxes on the letters",
            "For Return picked and Tidy up. Tidy up only throws away read letters that hold nothing at all.", Redraw)
        w:AddCheckbox(settings, "attaching", "Attach from bags button", nil, Redraw)
        w:AddCheckbox(settings, "forwarding", "Forward button on an open letter")

        w:AddNote("The bar sits under the mailbox window. Open All takes one letter at a time, a third of a second apart: mail sent to the server in a burst is partly dropped, and a dropped take leaves the letter sitting there.")
        w:AddNote("Copy to all, in the Address Book, sends the letter's subject and text to every name on the list. Attachments exist once and are never copied.")
    end
    optionsWindow:Show()
end

SLASH_OXEDHUBMAIL1 = "/oxmail"
SlashCmdList.OXEDHUBMAIL = function(msg)
    if not settings then return end
    msg = (msg or ""):lower()
    if msg == "book" then
        local window = BuildBook()
        ShowOnly(window)
        return
    end
    if msg == "all" then
        StartRun()
        return
    end
    local count = 0
    for _ in pairs(settings.contacts) do count = count + 1 end
    print(PREFIX .. ("%s, %d names in the book. /oxmail all collects, /oxmail book opens it.")
        :format(settings.enabled == false and "switched off" or "on", count))
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
        id       = "mail",
        name     = "Mail",
        version  = "1.0.0",
        author   = "Oxed",
        category = "inventory",
        keywords = { "mail", "mailbox", "post", "letters", "open all", "address book", "contacts", "gold" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Open All, return, forward, an address book and bag attaching. Type /oxmail.",
        icon     = "Interface\\Icons\\INV_Letter_15",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.contacts) ~= "table" then settings.contacts = {} end
            if type(settings.recent) ~= "table" then settings.recent = {} end
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
