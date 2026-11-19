-- ============================================================================
-- Rank Up (built-in OxedHub module)
-- Finds spells on your action bars that sit at a lower rank than the one you
-- have learned, and puts the highest rank in their place, after you look:
--
--   Upgrades   every outdated placement: its rank, the rank you could have,
--              the bar, the slot and the key. Upgrade one, the ticked ones,
--              or keep that rank on purpose (a Rank 1 down-rank).
--   Kept ranks the exact ranks you chose to keep, to give back.
--
-- It opens by itself after a trainer when something can be upgraded. Spells
-- are placed out of combat only, from the spellbook (picking a spell up by id
-- was blocked on Forever), and every slot is checked again afterwards.
-- Covers slots 1-180: the game's bars 1-8 and EllesmereUI's bars 9 and 10.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local ICON = "Interface\\Icons\\INV_Misc_Book_11"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREFIX = "|cff33ff99OxedHub Rank Up:|r "
local W, H, ROW_H, ROWS = 620, 520, 46, 7
local MAX_SLOT = 180
local BANK = (Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    minimapButton = true,
    openAfterTrainer = true,
    chatAfterTrainer = true,
    point = "CENTER", x = 0, y = 0,
    -- kept = { [spellID] = { name, rank, icon } } is made after binding: a table
    -- here would be shared by every character.
}

local settings
local running = false
local candidates = {}       -- the outdated placements of the last scan
local selected = {}         -- slot -> true
local scanQueued, combatPending = false, false
local mode = "upgrades"
local offset = 0
local window, optionsWindow
local minimapIcon, MinimapIcon, ShowOptions, Refresh, Scan
local events = CreateFrame("Frame")

-- ── Spells ──────────────────────────────────────────────────────────────────

local function Texture(v)
    if type(v) == "number" and v > 0 then return v end
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function SpellInfo(id)
    if not id then return nil, nil, "" end
    local name, icon, sub
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info then name, icon = info.name, Texture(info.iconID) or Texture(info.originalIconID) end
        if C_Spell.GetSpellSubtext then sub = C_Spell.GetSpellSubtext(id) end
    end
    if not icon and C_Spell and C_Spell.GetSpellTexture then icon = Texture(C_Spell.GetSpellTexture(id)) end
    if (not name or not icon) and GetSpellInfo then
        local n, s, i = GetSpellInfo(id)
        name, sub, icon = name or n, sub or s, icon or Texture(i)
    end
    if (not sub or sub == "") and GetSpellSubtext then sub = GetSpellSubtext(id) end
    return name, icon, sub or ""
end

-- Profession ranks (Apprentice, Journeyman...) get a new spell at each trainer
-- but are never something to swap on a bar.
local PROFESSION_IDS = { 2259, 2018, 7411, 4036, 2366, 45357, 25229, 2108,
                         2575, 8613, 3908, 2550, 3273, 7620, 78670 }
local professions = {}
local function RefreshProfessions()
    for _, id in ipairs(PROFESSION_IDS) do
        local n = SpellInfo(id)
        if n then professions[n] = true end
    end
end

local function IsSpellItem(info)
    if not info then return false end
    local t = info.itemType
    if Enum and Enum.SpellBookItemType and t == Enum.SpellBookItemType.Spell then return true end
    return t == "SPELL" or t == 1
end

-- Calls visit(index) for each spellbook entry on the class tabs; stops on true.
local function ForEachBookIndex(visit)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
        local n = C_SpellBook.GetNumSpellBookSkillLines() or 0
        if n > 0 then
            for tab = 1, n do
                local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                if line then
                    local off = line.itemIndexOffset or 0
                    for i = off + 1, off + (line.numSpellBookItems or 0) do
                        if visit(i) then return end
                    end
                end
            end
            return
        end
    end
    if GetNumSpellTabs and GetSpellTabInfo then
        for tab = 1, GetNumSpellTabs() or 0 do
            local _, _, off, count = GetSpellTabInfo(tab)
            for i = (off or 0) + 1, (off or 0) + (count or 0) do
                if visit(i) then return end
            end
        end
    end
end

local function BookEntry(index)
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(index, BANK)
        if not IsSpellItem(info) then return nil end
        local id = info.spellID or info.actionID
        local name, sub = info.name, info.subName
        if C_SpellBook.GetSpellBookItemName then
            local n, s = C_SpellBook.GetSpellBookItemName(index, BANK)
            name = name or n
            if not sub or sub == "" then sub = s end
        end
        name = name or (id and SpellInfo(id))
        if not (name and id) then return nil end
        return { index = index, spellID = id, actionID = info.actionID, name = name, rank = sub or "" }
    end
    if GetSpellBookItemInfo then
        local book = BOOKTYPE_SPELL or "spell"
        local kind, id = GetSpellBookItemInfo(index, book)
        if kind ~= "SPELL" or not id then return nil end
        local name, sub
        if GetSpellBookItemName then name, sub = GetSpellBookItemName(index, book) end
        name = name or SpellInfo(id)
        if not name then return nil end
        return { index = index, spellID = id, actionID = id, name = name, rank = sub or "" }
    end
    return nil
end

local function RankNumber(text) return tonumber((text or ""):match("(%d+)")) end

-- name -> the highest learned rank of that spell
local function HighestRanks()
    RefreshProfessions()
    local best = {}
    ForEachBookIndex(function(i)
        local e = BookEntry(i)
        if e and not professions[e.name] then
            if e.rank == "" then
                local _, _, r = SpellInfo(e.spellID)
                e.rank = r or ""
            end
            local prev = best[e.name]
            local a, b = RankNumber(e.rank), prev and RankNumber(prev.rank)
            if not prev or not (a and b and a < b) then best[e.name] = e end
        end
    end)
    return best
end

local function FindInBook(spellID)
    local found, base
    ForEachBookIndex(function(i)
        local e = BookEntry(i)
        if e and (e.spellID == spellID or e.actionID == spellID) then
            found, base = i, e.actionID
            return true
        end
    end)
    return found, base
end

-- ── Bars ────────────────────────────────────────────────────────────────────

-- The bars' first slots are not in order. EllesmereUI's bars 9 and 10 reuse
-- action pages 2 and 10.
local BARS = {
    { n = 1, first = 1,   bind = "ACTIONBUTTON" },
    { n = 2, first = 61,  bind = "MULTIACTIONBAR1BUTTON" },
    { n = 3, first = 49,  bind = "MULTIACTIONBAR2BUTTON" },
    { n = 4, first = 25,  bind = "MULTIACTIONBAR3BUTTON" },
    { n = 5, first = 37,  bind = "MULTIACTIONBAR4BUTTON" },
    { n = 6, first = 145, bind = "MULTIACTIONBAR5BUTTON" },
    { n = 7, first = 157, bind = "MULTIACTIONBAR6BUTTON" },
    { n = 8, first = 169, bind = "MULTIACTIONBAR7BUTTON" },
    { n = 9, first = 13,  bind = "EUI_BAR9_BUTTON",  ellesmere = true },
    { n = 10, first = 109, bind = "EUI_BAR10_BUTTON", ellesmere = true },
}

local function HasEllesmere()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return loaded and loaded("EllesmereUIActionBars") == true or false
end

local function BarOf(slot)
    local eui = HasEllesmere()
    for _, bar in ipairs(BARS) do
        if slot >= bar.first and slot < bar.first + 12 and (eui or not bar.ellesmere) then
            return bar, slot - bar.first + 1
        end
    end
end

local function Placement(slot)
    local bar, button = BarOf(slot)
    local where
    if bar then
        where = (T("Bar %d, button %d")):format(bar.n, button)
    else
        where = (T("Slot %d")):format(slot)
    end
    local key = bar and GetBindingKey and GetBindingKey(bar.bind .. button)
    if key and GetBindingText then key = GetBindingText(key, "KEY_") end
    return where, key
end

-- ── Scanning ────────────────────────────────────────────────────────────────

local function Kept(id) return settings and settings.kept and settings.kept[id] ~= nil end

Scan = function()
    if not running then return end
    if InCombatLockdown() then combatPending = true return end
    local best = HighestRanks()
    local list = {}
    for slot = 1, MAX_SLOT do
        local kind, id = GetActionInfo(slot)
        if kind == "spell" and type(id) == "number" then
            local name, icon, rank = SpellInfo(id)
            local top = name and best[name]
            if top and id ~= top.spellID and id ~= top.actionID and not Kept(id) and not professions[name] then
                local _, topIcon, topRank = SpellInfo(top.spellID)
                local where, key = Placement(slot)
                list[#list + 1] = {
                    slot = slot, name = name, currentID = id, currentRank = rank or "",
                    maxID = top.spellID, maxActionID = top.actionID,
                    maxRank = (topRank and topRank ~= "") and topRank or top.rank or "",
                    icon = icon or QUESTION, maxIcon = topIcon or icon or QUESTION,
                    where = where, key = key,
                }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then return a.slot < b.slot end
        return a.name < b.name
    end)
    -- New placements start ticked; ones the player unticked stay unticked.
    local old, nowSel = selected, {}
    for _, c in ipairs(list) do
        local was = old[c.slot]
        nowSel[c.slot] = (was == nil) and true or was
    end
    candidates, selected = list, nowSel
    if window and window:IsShown() then Refresh() end
    return list
end

local function QueueScan(delay)
    if scanQueued or not running then return end
    scanQueued = true
    C_Timer.After(delay or 0.15, function()
        scanQueued = false
        Scan()
    end)
end

-- ── Upgrading ───────────────────────────────────────────────────────────────

local function Upgrade(list)
    if #list == 0 then print(PREFIX .. L["Nothing is ticked."]) return end
    if InCombatLockdown() then print(PREFIX .. L["Action bars cannot be changed in combat."]) return end
    local tried, moved, missing, failed = {}, 0, 0, 0
    for _, c in ipairs(list) do
        local kind, id = GetActionInfo(c.slot)
        if kind ~= "spell" or id ~= c.currentID then
            moved = moved + 1           -- the bar changed since the scan
        else
            ClearCursor()
            local index, base = FindInBook(c.maxID)
            if not index then
                missing = missing + 1
            else
                if C_SpellBook and C_SpellBook.PickupSpellBookItem then
                    C_SpellBook.PickupSpellBookItem(index, BANK)
                elseif PickupSpellBookItem then
                    PickupSpellBookItem(index, BOOKTYPE_SPELL or "spell")
                end
                if GetCursorInfo and GetCursorInfo() == "spell" then
                    PlaceAction(c.slot)
                    tried[#tried + 1] = { c = c, base = base }
                else
                    failed = failed + 1
                end
            end
            ClearCursor()
        end
    end
    ClearCursor()
    -- Only count what the bar really shows once the game has caught up.
    C_Timer.After(0.2, function()
        local done, notDone = 0, 0
        for _, t in ipairs(tried) do
            local kind, id = GetActionInfo(t.c.slot)
            if kind == "spell" and id ~= t.c.currentID and (id == t.c.maxID or id == t.base or id == t.c.maxActionID) then
                done = done + 1
            else
                notDone = notDone + 1
            end
        end
        if done > 0 then print(PREFIX .. (L["Upgraded %d placements."]):format(done)) end
        if moved > 0 then print(PREFIX .. (L["Skipped %d: the bar changed since the scan."]):format(moved)) end
        if missing > 0 then print(PREFIX .. (L["Skipped %d: the higher rank is not in your spellbook."]):format(missing)) end
        if failed + notDone > 0 then
            print(PREFIX .. (L["%d could not be placed. Drag them from the spellbook."]):format(failed + notDone))
        end
        Scan()
    end)
end

local function Ticked()
    local out = {}
    for _, c in ipairs(candidates) do
        if selected[c.slot] then out[#out + 1] = c end
    end
    return out
end

local function Keep(c)
    settings.kept[c.currentID] = { name = c.name, rank = c.currentRank, icon = c.icon }
    selected[c.slot] = nil
    print(PREFIX .. (L["%s is kept at this rank."]):format(c.name .. (c.currentRank ~= "" and (" (" .. c.currentRank .. ")") or "")))
    Scan()
end

local function KeptList()
    local out = {}
    for id, d in pairs(settings.kept) do
        local name, icon, rank = SpellInfo(id)
        out[#out + 1] = { id = id, name = name or d.name or "?", rank = (rank ~= "" and rank) or d.rank or "",
                          icon = icon or d.icon or QUESTION }
    end
    table.sort(out, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    return out
end

-- ── Window ──────────────────────────────────────────────────────────────────

local function MakeButton(parent, width, text, onClick, height)
    local B = OxedHub.UIComponents and OxedHub.UIComponents.Button
    if B and B.CreateTab then
        local ok, b = pcall(B.CreateTab, parent, width, text, onClick, height or 22)
        if ok and b then return b end
    end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height or 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b.SetActive = function() end
    return b
end

local function RowTooltip(row)
    local c = row.data
    if not c or not GameTooltip then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if c.maxID and GameTooltip.SetSpellByID then
        pcall(GameTooltip.SetSpellByID, GameTooltip, c.maxID)
    elseif c.id and GameTooltip.SetSpellByID then
        pcall(GameTooltip.SetSpellByID, GameTooltip, c.id)
    end
    GameTooltip:Show()
end

local function BuildRow(parent, i)
    local r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    r:SetHeight(ROW_H - 4)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.25, 0.2, 0.1, i % 2 == 0 and 0.35 or 0.2)
    r:EnableMouse(true)
    r:SetScript("OnEnter", RowTooltip)
    r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(24, 24)
    r.check:SetPoint("LEFT", 4, 0)
    r.check:SetScript("OnClick", function(self)
        if r.data then selected[r.data.slot] = self:GetChecked() and true or false end
        Refresh()
    end)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(32, 32)
    r.icon:SetPoint("LEFT", 32, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.arrow = r:CreateTexture(nil, "ARTWORK")
    r.arrow:SetSize(16, 16)
    r.arrow:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
    r.arrow:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    r.icon2 = r:CreateTexture(nil, "ARTWORK")
    r.icon2:SetSize(32, 32)
    r.icon2:SetPoint("LEFT", r.arrow, "RIGHT", 4, 0)
    r.icon2:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon2, "TOPRIGHT", 8, -1)
    r.name:SetJustifyH("LEFT")
    r.name:SetWidth(270)
    r.name:SetWordWrap(false)
    r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.detail:SetPoint("BOTTOMLEFT", r.icon2, "BOTTOMRIGHT", 8, 1)
    r.detail:SetJustifyH("LEFT")
    r.detail:SetWidth(270)
    r.detail:SetWordWrap(false)

    r.keep = MakeButton(r, 74, L["Keep rank"], function()
        if r.data then Keep(r.data) end
    end)
    r.keep:SetPoint("RIGHT", -6, 0)
    r.go = MakeButton(r, 74, L["Upgrade"], function()
        if r.data then Upgrade({ r.data }) end
    end)
    r.go:SetPoint("RIGHT", r.keep, "LEFT", -4, 0)
    r.give = MakeButton(r, 110, L["Allow upgrade"], function()
        if r.data and r.data.id then
            settings.kept[r.data.id] = nil
            Scan()
            Refresh()
        end
    end)
    r.give:SetPoint("RIGHT", -6, 0)
    return r
end

local function FillUpgradeRow(r, c)
    r.data = c
    r.check:Show()
    r.check:SetChecked(selected[c.slot] == true)
    r.icon:SetTexture(c.icon)
    r.arrow:Show()
    r.icon2:Show()
    r.icon2:SetTexture(c.maxIcon)
    r.name:SetText(c.name)
    local ranks = ("|cffff8060%s|r  >  |cff60ff60%s|r"):format(c.currentRank ~= "" and c.currentRank or "?", c.maxRank ~= "" and c.maxRank or "?")
    r.detail:SetText(ranks .. "   |cffb0a080" .. c.where .. (c.key and ("  [" .. c.key .. "]") or "") .. "|r")
    r.go:Show()
    r.keep:Show()
    r.give:Hide()
end

local function FillKeptRow(r, k)
    r.data = k
    r.check:Hide()
    r.icon:SetTexture(k.icon)
    r.arrow:Hide()
    r.icon2:Hide()
    r.name:ClearAllPoints()
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.detail:ClearAllPoints()
    r.detail:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.name:SetText(k.name)
    r.detail:SetText(("|cffffd060%s|r   |cffb0a080%s|r"):format(k.rank ~= "" and k.rank or "?", T("Stays at this rank on every bar")))
    r.go:Hide()
    r.keep:Hide()
    r.give:Show()
end

Refresh = function()
    if not window then return end
    local f = window
    local list = (mode == "kept") and KeptList() or candidates
    local maxOff = math.max(0, #list - ROWS)
    if offset > maxOff then offset = maxOff end
    for i = 1, ROWS do
        local r = f.rows[i]
        local item = list[offset + i]
        if item then
            if mode == "kept" then
                FillKeptRow(r, item)
            else
                -- put the text back beside the second icon after a kept page
                r.name:ClearAllPoints()
                r.name:SetPoint("TOPLEFT", r.icon2, "TOPRIGHT", 8, -1)
                r.detail:ClearAllPoints()
                r.detail:SetPoint("BOTTOMLEFT", r.icon2, "BOTTOMRIGHT", 8, 1)
                FillUpgradeRow(r, item)
            end
            r:Show()
        else
            r.data = nil
            r:Hide()
        end
    end
    f.tabUp:SetActive(mode == "upgrades")
    f.tabKept:SetActive(mode == "kept")
    f.tabUp:SetText((T("Upgrades (%d)")):format(#candidates))
    f.tabKept:SetText((T("Kept ranks (%d)")):format(#KeptList()))
    if #list == 0 then
        f.empty:SetText(mode == "kept" and T("No kept ranks. Press Keep rank on a row to keep a down-rank on purpose.")
            or T("Your action bars are up to date."))
        f.empty:Show()
    else
        f.empty:Hide()
    end
    f.summary:SetText(#list > ROWS and (T("%d-%d of %d")):format(offset + 1, math.min(#list, offset + ROWS), #list) or "")
    local up = mode == "upgrades"
    local n = #Ticked()
    f.all:SetShown(up)
    f.none:SetShown(up)
    f.doTicked:SetShown(up)
    f.keepTicked:SetShown(up)
    f.doTicked:SetText((T("Upgrade ticked (%d)")):format(n))
end

local function BuildWindow()
    if window then return end
    local f = CreateFrame("Frame", "OxedHubRankUpWindow", UIParent, "BackdropTemplate")
    window = f
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    local ornate = false
    if Panel and Panel.ApplyOrnateFrame then
        local shell = CreateFrame("Frame", nil, f, "BackdropTemplate")
        shell:SetAllPoints(f)
        shell:SetFrameLevel(f:GetFrameLevel())
        shell:EnableMouse(false)
        ornate = pcall(Panel.ApplyOrnateFrame, shell, T("Rank Up"), 0.96)
    end
    if not ornate then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 0.9)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText(T("Rank Up"))
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetSize(W, H)
    f:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 0, settings.y or 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint(1)
        settings.point, settings.x, settings.y = p, x, y
    end)
    f:SetScript("OnShow", function() offset = 0 Scan() Refresh() end)
    f:Hide()
    tinsert(UISpecialFrames, "OxedHubRankUpWindow")

    f.tabUp = MakeButton(f, 150, "", function() mode = "upgrades" offset = 0 Refresh() end, 26)
    f.tabUp:SetPoint("TOPLEFT", 18, -36)
    f.tabKept = MakeButton(f, 150, "", function() mode = "kept" offset = 0 Refresh() end, 26)
    f.tabKept:SetPoint("LEFT", f.tabUp, "RIGHT", 4, 0)
    local opt = MakeButton(f, 70, L["Options"], function() ShowOptions() end, 26)
    opt:SetPoint("TOPRIGHT", -26, -36)
    local rescan = MakeButton(f, 80, L["Rescan"], function()
        Scan()
        Refresh()
    end, 26)
    rescan:SetPoint("RIGHT", opt, "LEFT", -4, 0)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 18, -72)
    divider:SetPoint("TOPRIGHT", -18, -72)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 18, -82)
    list:SetPoint("TOPRIGHT", -18, -82)
    list:SetHeight(ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        Refresh()
    end)
    f.rows = {}
    for i = 1, ROWS do f.rows[i] = BuildRow(list, i) end
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
    f.empty:SetWidth(W - 80)

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.summary:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", 0, -2)

    f.all = MakeButton(f, 70, L["All"], function()
        for _, c in ipairs(candidates) do selected[c.slot] = true end
        Refresh()
    end)
    f.all:SetPoint("BOTTOMLEFT", 18, 20)
    f.none = MakeButton(f, 70, L["None"], function()
        for _, c in ipairs(candidates) do selected[c.slot] = false end
        Refresh()
    end)
    f.none:SetPoint("LEFT", f.all, "RIGHT", 4, 0)
    f.doTicked = MakeButton(f, 170, "", function() Upgrade(Ticked()) end)
    f.doTicked:SetPoint("BOTTOMRIGHT", -18, 20)
    f.keepTicked = MakeButton(f, 120, L["Keep ticked"], function()
        local n = 0
        for _, c in ipairs(Ticked()) do
            if not settings.kept[c.currentID] then
                settings.kept[c.currentID] = { name = c.name, rank = c.currentRank, icon = c.icon }
                n = n + 1
            end
        end
        if n > 0 then print(PREFIX .. (L["Kept %d ranks."]):format(n)) end
        Scan()
        Refresh()
    end)
    f.keepTicked:SetPoint("RIGHT", f.doTicked, "LEFT", -4, 0)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 48)
    hint:SetWidth(W - 40)
    hint:SetText(T("Keep rank leaves that exact rank alone on every bar, for a down-rank you use on purpose."))
end

local function ShowWindow()
    if not running then
        print(PREFIX .. L["Switch Rank Up on in the Modules page first."])
        return
    end
    BuildWindow()
    window:Show()
end

local function ToggleWindow()
    if window and window:IsShown() then window:Hide() else ShowWindow() end
end

-- ── Events ──────────────────────────────────────────────────────────────────

events:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_CLOSED" then
        QueueScan(0.35)
        C_Timer.After(0.6, function()
            if not running or #candidates == 0 or InCombatLockdown() then return end
            if settings.chatAfterTrainer then
                print(PREFIX .. (L["%d spells on your bars can be upgraded. /oxrankup to review."]):format(#candidates))
            end
            if settings.openAfterTrainer then ShowWindow() end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if combatPending then
            combatPending = false
            QueueScan(0.1)
        end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        QueueScan(0.3)
    else
        QueueScan(0.1)
    end
end)

local EVENTS = { "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "TRAINER_CLOSED", "ACTIONBAR_SLOT_CHANGED",
                 "ACTIONBAR_PAGE_CHANGED", "UPDATE_BINDINGS", "PLAYER_REGEN_ENABLED" }

local function Start()
    if running then return end
    running = true
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    QueueScan(0.35)
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    wipe(candidates)
    wipe(selected)
    if window then window:Hide() end
end

SLASH_OXEDHUBRANKUP1 = "/oxrankup"
SlashCmdList.OXEDHUBRANKUP = function(msg)
    msg = strlower(strtrim(msg or ""))
    if msg == "scan" then
        if not running then ShowWindow() return end
        Scan()
        print(PREFIX .. (L["%d spells on your bars can be upgraded."]):format(#candidates))
    elseif msg == "reset" then
        if settings then wipe(settings.kept) end
        Scan()
        print(PREFIX .. L["Kept ranks cleared."])
    else
        ToggleWindow()
    end
end

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Rank Up", 440, 330)
        optionsWindow = w
        w:AddCheckbox(settings, "openAfterTrainer", "Open after a trainer",
            "When you leave a trainer and a spell on your bars can be upgraded.")
        w:AddCheckbox(settings, "chatAfterTrainer", "Say so in chat after a trainer")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("/oxrankup opens the window. /oxrankup reset gives back every kept rank. Bars are changed out of combat only.")
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "rankup", label = T("Rank Up"), icon = ICON, config = settings,
        hint = T("Click: outdated ranks on your bars. Right-click: options."),
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ToggleWindow() end
        end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.rankup
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.rankup = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.kept) ~= "table" then config.kept = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "rankup",
        name     = "Rank Up",
        version  = "1.0.0",
        added    = 20261119,
        updated  = 20261119.1,
        author   = "Oxed",
        category = "character",
        keywords = { "rank", "ranks", "spell", "upgrade", "action bar", "trainer", "down-rank", "spellupgrade" },
        desc     = "Swaps old spell ranks on your bars for the highest you know. Keeps down-ranks you choose.",
        icon     = ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.kept) ~= "table" then settings.kept = {} end
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
