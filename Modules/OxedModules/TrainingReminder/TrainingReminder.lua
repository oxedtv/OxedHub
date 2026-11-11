-- ============================================================================
-- Training Reminder (built-in OxedHub module, WoW Forever only)
-- Tells you when your class trainer has something new for you: a card on
-- screen when you level up, and again later if you still have not been, with
-- the new abilities named first. A window lists what is ready, what it costs
-- and what comes in the next levels.
--
-- What a class learns and at which level is in TrainingReminderData.lua. What
-- you already know is asked of the spellbook, so nothing is saved about it.
--
-- ⚠ Nothing pops up in combat: a card due in a fight waits for its end.
-- ⚠ The spellbook can lag a moment behind a level up or a visit to the
--   trainer, so every look at it is delayed and several events share one.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on
    minimapButton = true,
    card          = false,   -- the card on screen (off by default)
    chat          = false,   -- a line in chat too (off by default)
    onlyNew       = false,   -- remind about new abilities only, not higher ranks
    onlyAfford    = false,   -- only when there is money for at least one
    remindCity    = true,    -- again on entering a city or an inn
    remindMinutes = 15,      -- again after this long; 0 is never
    sound         = "None",
    remindTalents     = true,    -- unspent talent points
    remindProfessions = true,    -- a profession that cannot go higher without its next rank
    remindWeapons     = false,   -- weapon skills you could learn from a weapon master
    -- ignored is a table, made at login
}

local PREFIX = "|cff00ccffOxedHub|r "
local SOON_LEVELS = 2        -- "coming soon" looks this many levels ahead
local SETTLE = 1.5           -- the spellbook catches up with a level up
local LOGIN_DELAY = 8
local RESCAN_DELAY = 1       -- spell events come in bursts
local CARD_ROWS = 8            -- spells named on the card; the rest are in the list
local CARD_ROW = 22
local CARD_TOP = 34           -- where the first row starts
local CARD_WIDTH = 350
local ROW_HEIGHT = 22

local settings
local running = false
local Data                   -- OxedHub.TrainingReminderData, or nil
local rankGroup = {}         -- spell id -> { group, index }
local available, soon, ignoredList = {}, {}, {}
local weapons = {}           -- weapon skills still to learn
local extras = {}            -- other reminders, as ready lines of text
local totalCost = 0
local card, window, optionsWindow
local minimapIcon
local display = {}
local scroll = 0
local lastShown = 0
local pendingReason          -- a card due in combat
local rescanQueued = false
local ticker

local events = CreateFrame("Frame")

-- Defined further down, used above their definitions.
local ShowOptions, MinimapIcon, ShowWindow, UpdateWindow

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

local function Call(fn, ...)
    if not fn then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function Say(text)
    print(PREFIX .. text)
end

local lastLevel = 1
local function MyLevel()
    local level = Call(UnitLevel, "player")
    if type(level) == "number" and not IsSecret(level) and level > 0 then lastLevel = level end
    return lastLevel
end

local function Money()
    local money = Call(GetMoney)
    if type(money) == "number" and not IsSecret(money) then return money end
    return 0
end

local function MoneyText(copper)
    copper = math.max(0, math.floor(copper or 0))
    local text = Call(GetCoinTextureString, copper)
    if type(text) == "string" and text ~= "" then return text end
    local gold, silver = math.floor(copper / 10000), math.floor(copper % 10000 / 100)
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. "g" end
    if silver > 0 then parts[#parts + 1] = silver .. "s" end
    if #parts == 0 or copper % 100 > 0 then parts[#parts + 1] = (copper % 100) .. "c" end
    return table.concat(parts, " ")
end

local function SpellName(id)
    local name = Call(C_Spell and C_Spell.GetSpellName, id)
    if type(name) ~= "string" or IsSecret(name) or name == "" then
        name = Call(GetSpellInfo, id)
    end
    if type(name) == "string" and not IsSecret(name) and name ~= "" then return name end
    return nil
end

local function SpellIcon(id)
    local icon = Call(C_Spell and C_Spell.GetSpellTexture, id)
    if icon == nil or IsSecret(icon) then icon = Call(GetSpellTexture, id) end
    if icon == nil or IsSecret(icon) then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return icon
end

-- True when the spellbook has it. A secret or a failed call is "no".
local function Known(id)
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if C_SpellBook and bank ~= nil then
        local known = Call(C_SpellBook.IsSpellKnown, id, bank)
        if known and not IsSecret(known) then return true end
        local inBook = Call(C_SpellBook.IsSpellInSpellBook, id, bank, false)
        if inBook and not IsSecret(inBook) then return true end
    end
    local old = Call(IsSpellKnown, id)
    if old and not IsSecret(old) then return true end
    local mine = Call(IsPlayerSpell, id)
    if mine and not IsSecret(mine) then return true end
    return false
end

-- Some ranks replace the one before in the spellbook: knowing a later rank
-- then counts as knowing this one.
local function KnownOrHigher(id)
    if Known(id) then return true end
    local at = rankGroup[id]
    if not at then return false end
    for i = at.index + 1, #at.group do
        if Known(at.group[i]) then return true end
    end
    return false
end

local function BuildRanks()
    wipe(rankGroup)
    if not (Data and type(Data.overriddenGroups) == "table") then return end
    for _, group in ipairs(Data.overriddenGroups) do
        for index, id in ipairs(group) do
            rankGroup[id] = { group = group, index = index }
        end
    end
end

-- ── Weapon skills, talents, professions ─────────────────────────────────────

-- Weapon skills by their spell, who may learn them, and the cities (area ids)
-- whose weapon master teaches them. Ten silver each unless it says otherwise.
local IRONFORGE, STORMWIND, DARNASSUS = 1537, 1519, 1657
local ORGRIMMAR, THUNDER_BLUFF, UNDERCITY = 1637, 1638, 1497
local WEAPONS = {
    { id = 196,   classes = "WARRIOR PALADIN HUNTER SHAMAN ROGUE", Alliance = { IRONFORGE }, Horde = { ORGRIMMAR } },
    { id = 197,   classes = "WARRIOR PALADIN HUNTER SHAMAN", Alliance = { IRONFORGE }, Horde = { ORGRIMMAR } },
    { id = 198,   classes = "WARRIOR PALADIN ROGUE PRIEST SHAMAN DRUID", Alliance = { IRONFORGE }, Horde = { THUNDER_BLUFF } },
    { id = 199,   classes = "WARRIOR PALADIN SHAMAN DRUID", Alliance = { IRONFORGE }, Horde = { THUNDER_BLUFF } },
    { id = 201,   classes = "WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK", Alliance = { STORMWIND }, Horde = { UNDERCITY } },
    { id = 202,   classes = "WARRIOR PALADIN HUNTER", Alliance = { STORMWIND }, Horde = { UNDERCITY } },
    { id = 1180,  classes = "WARRIOR HUNTER ROGUE PRIEST SHAMAN DRUID WARLOCK MAGE", Alliance = { IRONFORGE, STORMWIND, DARNASSUS }, Horde = { ORGRIMMAR, UNDERCITY } },
    { id = 15590, classes = "WARRIOR HUNTER ROGUE SHAMAN DRUID", Alliance = { IRONFORGE, DARNASSUS }, Horde = { ORGRIMMAR } },
    { id = 227,   classes = "WARRIOR HUNTER PRIEST SHAMAN DRUID WARLOCK MAGE", Alliance = { STORMWIND, DARNASSUS }, Horde = { ORGRIMMAR, THUNDER_BLUFF } },
    { id = 200,   classes = "WARRIOR PALADIN HUNTER DRUID", level = 20, cost = 10000, Alliance = { STORMWIND }, Horde = { UNDERCITY } },
    { id = 264,   classes = "WARRIOR HUNTER ROGUE", Alliance = { DARNASSUS }, Horde = { ORGRIMMAR } },
    { id = 266,   classes = "WARRIOR HUNTER ROGUE", Alliance = { IRONFORGE }, Horde = { THUNDER_BLUFF } },
    { id = 5011,  classes = "WARRIOR HUNTER ROGUE", Alliance = { IRONFORGE, STORMWIND }, Horde = { UNDERCITY } },
    { id = 2567,  classes = "WARRIOR HUNTER ROGUE", Alliance = { IRONFORGE, DARNASSUS }, Horde = { ORGRIMMAR } },
}

local function AreaNames(areas)
    local names = {}
    for _, id in ipairs(areas or {}) do
        local name = Call(C_Map and C_Map.GetAreaInfo, id)
        if type(name) == "string" and not IsSecret(name) and name ~= "" then names[#names + 1] = name end
    end
    return table.concat(names, ", ")
end

local function QuestDone(quests)
    for _, id in ipairs(quests or {}) do
        local done = Call(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, id)
        if done == nil then done = Call(IsQuestFlaggedCompleted, id) end
        if done and not IsSecret(done) then return true end
    end
    return false
end

local function TalentPoints()
    local points = Call(UnitCharacterPoints, "player")
    if type(points) == "number" and not IsSecret(points) and points > 0 then return points end
    return 0
end

-- A profession at 75, 150 or 225 of the same goes no higher until its next
-- rank is bought, and that rank asks for a character level.
local RANK_GATE = { [75] = 10, [150] = 20, [225] = 35 }

local function AddCap(list, name, rank, limit, level)
    if type(name) ~= "string" or type(rank) ~= "number" or type(limit) ~= "number" then return end
    if IsSecret(name) or IsSecret(rank) or IsSecret(limit) then return end
    local gate = RANK_GATE[limit]
    if gate and rank >= limit and level >= gate then
        list[#list + 1] = { name = name, rank = rank }
    end
end

local function ProfessionCaps(level)
    local list = {}
    if GetProfessions and GetProfessionInfo then
        local got = { pcall(GetProfessions) }
        if got[1] then
            for i = 2, 7 do
                if got[i] then
                    local ok, name, _, rank, limit = pcall(GetProfessionInfo, got[i])
                    if ok then AddCap(list, name, rank, limit, level) end
                end
            end
        end
    elseif GetNumSkillLines and GetSkillLineInfo then
        -- The old skill list: professions are the lines under two headers.
        local count = Call(GetNumSkillLines)
        if type(count) ~= "number" or IsSecret(count) then return list end
        local secondary = type(SECONDARY_SKILLS) == "string" and (SECONDARY_SKILLS:gsub(":%s*$", "")) or nil
        local inside = false
        for i = 1, count do
            local ok, name, isHeader, _, rank, _, _, limit = pcall(GetSkillLineInfo, i)
            if ok and not IsSecret(name) and not IsSecret(isHeader) then
                if isHeader then
                    inside = (name == TRADE_SKILLS) or (secondary ~= nil and name == secondary)
                elseif inside then
                    AddCap(list, name, rank, limit, level)
                end
            end
        end
    end
    return list
end

-- ── What there is to learn ──────────────────────────────────────────────────

local function ForMe(spell, faction, race)
    if spell.faction and faction and spell.faction ~= faction then return false end
    if spell.race and race and spell.race ~= race then return false end
    if type(spell.races) == "table" and race then
        local mine = false
        for _, each in ipairs(spell.races) do
            if each == race then mine = true end
        end
        if not mine then return false end
    end
    return true
end

-- A new ability, not a higher rank of one you have: none of the spells it
-- needs first carries its name.
local function IsNewAbility(spell, name)
    if type(spell.requiredIds) ~= "table" or #spell.requiredIds == 0 then return true end
    if not name then return false end
    for _, required in ipairs(spell.requiredIds) do
        if SpellName(required) == name then return false end
    end
    return true
end

local function ByImportance(a, b)
    if a.isNew ~= b.isNew then return a.isNew end
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
end

local function BySoonest(a, b)
    if a.level ~= b.level then return a.level < b.level end
    return a.name < b.name
end

local function Scan()
    wipe(available)
    wipe(soon)
    wipe(ignoredList)
    wipe(weapons)
    wipe(extras)
    totalCost = 0
    local spellsByLevel = Data and type(Data.spellsByLevel) == "table" and Data.spellsByLevel or {}
    local level = MyLevel()
    local faction = Call(UnitFactionGroup, "player")
    if IsSecret(faction) then faction = nil end
    local _, _, race = Call(UnitRace, "player")
    if IsSecret(race) then race = nil end

    for spellLevel, spells in pairs(spellsByLevel) do
        if spellLevel <= level + SOON_LEVELS then
            for _, spell in ipairs(spells) do
                local id = spell.id
                if ForMe(spell, faction, race) and not KnownOrHigher(id)
                    and (not spell.requiredTalentId or Known(spell.requiredTalentId)) then
                    local name = SpellName(id)
                    local entry = {
                        id = id,
                        level = spellLevel,
                        cost = tonumber(spell.cost) or 0,
                        name = name or (L["Spell"] .. " " .. id),
                        isNew = IsNewAbility(spell, name),
                    }
                    if settings.ignored[id] then
                        ignoredList[#ignoredList + 1] = entry
                    elseif spellLevel > level then
                        soon[#soon + 1] = entry
                    else
                        -- A rank whose earlier rank is still unlearned waits
                        -- for it: the earlier one is in the list already.
                        local ready = true
                        if type(spell.requiredIds) == "table" then
                            for _, required in ipairs(spell.requiredIds) do
                                if not KnownOrHigher(required) then ready = false end
                            end
                        end
                        if ready then
                            available[#available + 1] = entry
                            totalCost = totalCost + entry.cost
                        end
                    end
                end
            end
        end
    end

    -- Spells a class quest teaches: always worth a reminder.
    local questSpells = Data and Data.questSpells
    if type(questSpells) == "table" and race then
        for id, entries in pairs(questSpells) do
            for _, quest in ipairs(entries) do
                local mine = false
                for _, each in ipairs(quest.races or {}) do
                    if each == race then mine = true end
                end
                if mine then
                    if type(quest.level) == "number" and quest.level <= level + SOON_LEVELS
                        and not KnownOrHigher(id) and not QuestDone(quest.quests) then
                        local entry = {
                            id = id, level = quest.level, cost = 0,
                            name = SpellName(id) or (L["Spell"] .. " " .. id),
                            isNew = true, quest = true,
                            areas = quest.areas or { quest.area },
                        }
                        if settings.ignored[id] then
                            ignoredList[#ignoredList + 1] = entry
                        elseif quest.level > level then
                            soon[#soon + 1] = entry
                        else
                            available[#available + 1] = entry
                        end
                    end
                    break
                end
            end
        end
    end

    -- Weapon skills this class may learn and has not.
    local _, classToken = Call(UnitClass, "player")
    if type(classToken) == "string" and not IsSecret(classToken) then
        for _, weapon in ipairs(WEAPONS) do
            if weapon.classes:find(classToken, 1, true) and (weapon.level or 1) <= level and not Known(weapon.id) then
                local entry = {
                    id = weapon.id, level = weapon.level or 1, cost = weapon.cost or 1000,
                    name = SpellName(weapon.id) or (L["Spell"] .. " " .. weapon.id),
                    isNew = true, weapon = true,
                    areas = faction and weapon[faction] or nil,
                }
                if settings.ignored[weapon.id] then
                    ignoredList[#ignoredList + 1] = entry
                else
                    weapons[#weapons + 1] = entry
                end
            end
        end
    end

    if settings.remindTalents then
        local points = TalentPoints()
        if points > 0 then extras[#extras + 1] = L["Unspent talent points: %d"]:format(points) end
    end
    if settings.remindProfessions then
        for _, cap in ipairs(ProfessionCaps(level)) do
            extras[#extras + 1] = L["%s is at its limit (%d): learn the next rank from its trainer"]:format(cap.name, cap.rank)
        end
    end

    table.sort(available, ByImportance)
    table.sort(weapons, BySoonest)
    table.sort(soon, BySoonest)
    table.sort(ignoredList, BySoonest)
end

-- What a reminder is about: everything ready, or the new abilities only.
local function Reminded()
    local list = {}
    for _, entry in ipairs(available) do
        if entry.isNew or not settings.onlyNew then list[#list + 1] = entry end
    end
    if settings.remindWeapons then
        for _, entry in ipairs(weapons) do list[#list + 1] = entry end
    end
    return list
end

local function CanAffordAny(list)
    local money = Money()
    for _, entry in ipairs(list) do
        if entry.cost <= money then return true end
    end
    return false
end

-- ── The card on screen ──────────────────────────────────────────────────────

local function HideCard()
    if card then card:Hide() end
end

-- The rank as the game words it ("Rank 2", "Passive"), once it has loaded.
local function SpellRank(id)
    local text = Call(C_Spell and C_Spell.GetSpellSubtext, id)
    if type(text) ~= "string" or IsSecret(text) then text = Call(GetSpellSubtext, id) end
    if type(text) == "string" and not IsSecret(text) and text ~= "" then return text end
    Call(C_Spell and C_Spell.RequestLoadSpellData, id)
    return nil
end

local rankRetry = false      -- one more look for ranks that had not loaded

local function BuildCard()
    card = CreateFrame("Button", "OxedHubTrainingReminderCard", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    card:Hide()
    card:SetSize(CARD_WIDTH, 96)
    card:SetFrameStrata("HIGH")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:RegisterForDrag("LeftButton")
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card:SetScript("OnDragStart", card.StartMoving)
    card:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        settings.cardX, settings.cardY = self:GetLeft(), self:GetTop()
    end)
    local function Clicked(_, mouse)
        if mouse == "RightButton" then
            card:Hide()
        else
            ShowWindow()
        end
    end
    card:SetScript("OnClick", Clicked)
    if card.SetBackdrop then
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        card:SetBackdropColor(0, 0, 0, 0.9)
        card:SetBackdropBorderColor(1, 0.82, 0, 1)
    end

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", 12, -10)

    -- One line per spell: its icon, name and rank, and what it costs.
    card.rows = {}
    for i = 1, CARD_ROWS do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(CARD_WIDTH - 24, CARD_ROW)
        row:SetPoint("TOPLEFT", 12, -CARD_TOP - (i - 1) * CARD_ROW)
        -- A gold edge marks a new ability.
        row.edge = row:CreateTexture(nil, "BACKGROUND")
        row.edge:SetSize(22, 22)
        row.edge:SetPoint("LEFT", 0, 0)
        row.edge:SetColorTexture(1, 0.82, 0, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("CENTER", row.edge, "CENTER", 0, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.cost:SetPoint("RIGHT", 0, 0)
        row.cost:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 28, 0)
        row.name:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
        row.name:SetJustifyH("LEFT")
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.id then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.id) then
                GameTooltip:SetText(self.spell or "")
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- A row swallows the click meant for the card: hand it on.
        row:SetScript("OnMouseUp", Clicked)
        card.rows[i] = row
    end

    card.more = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.more:SetTextColor(0.7, 0.7, 0.7)
    card.foot = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.foot:SetWidth(CARD_WIDTH - 24)
    card.foot:SetJustifyH("LEFT")
    card.foot:SetSpacing(2)
    card.hint = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.hint:SetTextColor(0.6, 0.6, 0.6)
    card.hint:SetText(L["Click: the list. Right-click: close."])
end

-- How many of them the money in the bags pays for, cheapest first.
local function AffordCount(list, money)
    local costs = {}
    for _, entry in ipairs(list) do costs[#costs + 1] = entry.cost end
    table.sort(costs)
    local count = 0
    for _, cost in ipairs(costs) do
        if cost > money then break end
        money = money - cost
        count = count + 1
    end
    return count
end

local function ShowCard(list)
    if not card then BuildCard() end
    local money = Money()
    local cost = 0
    local missingRank = false
    card.title:SetText(#list > 0 and L["Learn at your trainer"] or L["Do not forget"])

    for i, row in ipairs(card.rows) do
        local entry = list[i]
        if entry then
            cost = cost + entry.cost
            row.id, row.spell = entry.id, entry.name
            row.icon:SetTexture(SpellIcon(entry.id))
            row.edge:SetShown(entry.isNew)
            local rank = SpellRank(entry.id)
            if not rank then missingRank = true end
            row.name:SetText((entry.isNew and "|cff40ff40" or "|cffffffff") .. entry.name .. "|r"
                .. (rank and ("  |cff999999" .. rank .. "|r") or ""))
            if entry.quest then
                row.cost:SetText("|cffffd100" .. L["class quest"] .. "|r")
            elseif entry.cost <= money then
                row.cost:SetText(MoneyText(entry.cost))
            else
                row.cost:SetText("|cffff6060" .. MoneyText(entry.cost) .. "|r")
            end
            row:Show()
        else
            row.id = nil
            row:Hide()
        end
    end
    for i = CARD_ROWS + 1, #list do cost = cost + list[i].cost end

    local y = CARD_TOP + math.min(#list, CARD_ROWS) * CARD_ROW
    card.more:ClearAllPoints()
    if #list > CARD_ROWS then
        card.more:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y - 2)
        card.more:SetText(L["and %d more, in the list"]:format(#list - CARD_ROWS))
        card.more:Show()
        y = y + 16
    else
        card.more:Hide()
    end

    local lines = {}
    if #list > 0 then
        if money >= cost then
            lines[#lines + 1] = L["In all %s. You have %s"]:format(MoneyText(cost), MoneyText(money))
        else
            lines[#lines + 1] = L["In all %s. You have %s"]:format(MoneyText(cost), "|cffff6060" .. MoneyText(money) .. "|r")
            local count = AffordCount(list, money)
            if count > 0 then
                lines[#lines + 1] = L["Enough for %d of them now"]:format(count)
            else
                lines[#lines + 1] = "|cffff6060" .. L["Not enough for any of them yet"] .. "|r"
            end
        end
    end
    for _, extra in ipairs(extras) do
        lines[#lines + 1] = "|cffffd100" .. extra .. "|r"
    end
    -- What the next level brings, so the money can be kept for it.
    if soon[1] then
        local nextLevel = soon[1].level
        local names = {}
        for _, entry in ipairs(soon) do
            if entry.level == nextLevel then
                if #names >= 5 then
                    names[#names + 1] = "..."
                    break
                end
                names[#names + 1] = entry.name
            end
        end
        lines[#lines + 1] = "|cff8fb8ff" .. L["At level %d: %s"]:format(nextLevel, table.concat(names, ", ")) .. "|r"
    end
    card.foot:ClearAllPoints()
    card.foot:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y - 6)
    card.foot:SetText(table.concat(lines, "\n"))
    y = y + 6 + (#lines > 0 and card.foot:GetStringHeight() or 0)

    card.hint:ClearAllPoints()
    card.hint:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -y - 6)
    card:SetHeight(y + 6 + 22)

    card:ClearAllPoints()
    if settings.cardX and settings.cardY then
        card:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", settings.cardX, settings.cardY)
    else
        card:SetPoint("TOP", UIParent, "TOP", 0, -170)
    end
    card:Show()

    -- Ranks arrive a moment after they are first asked for.
    if missingRank and not rankRetry then
        rankRetry = true
        C_Timer.After(1.5, function()
            if card and card:IsShown() and running then ShowCard(Reminded()) end
            rankRetry = false
        end)
    end
end
-- reason: "level", "login", "city", "timer" or "test".
local function Remind(reason)
    if not running then return end
    Scan()
    UpdateWindow()
    local list = Reminded()
    if #list == 0 and #extras == 0 then
        HideCard()
        if reason == "test" then Say(L["Nothing to learn from your trainer right now."]) end
        return
    end
    if reason ~= "test" then
        if settings.onlyAfford and #extras == 0 and not CanAffordAny(list) then return end
        if InCombatLockdown() then
            pendingReason = reason
            return
        end
    end
    lastShown = GetTime()
    if settings.card or reason == "test" then ShowCard(list) end
    -- A card already up is refreshed quietly: the sound and the chat line are
    -- for a level up, the login, or a card that had been closed.
    if (settings.chat or reason == "test") and #list > 0 then
        local names = {}
        for i, entry in ipairs(list) do
            if i > 5 then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = (entry.isNew and "|cff40ff40" or "|cffffffff") .. entry.name .. "|r"
        end
        Say(L["Your trainer has %d to teach you: %s. /oxtrain for the list."]:format(#list, table.concat(names, ", ")))
    end
    if settings.chat or reason == "test" then
        for _, extra in ipairs(extras) do Say(extra .. ".") end
    end
    if settings.sound and settings.sound ~= "None" and OxedHub.ModuleAPI and OxedHub.ModuleAPI.PlaySound then
        OxedHub.ModuleAPI:PlaySound(settings.sound)
    end
end

-- After the spellbook changed: no sound, no chat, only what is on screen.
local function Rescan()
    rescanQueued = false
    if not running then return end
    Scan()
    UpdateWindow()
    if card and card:IsShown() then
        local list = Reminded()
        if #list == 0 and #extras == 0 then HideCard() else ShowCard(list) end
    end
end

local function QueueRescan()
    if rescanQueued then return end
    rescanQueued = true
    C_Timer.After(RESCAN_DELAY, Rescan)
end

-- ── The list ────────────────────────────────────────────────────────────────

local function BuildDisplay()
    wipe(display)
    for _, extra in ipairs(extras) do
        display[#display + 1] = { header = extra }
    end
    if #available > 0 then
        display[#display + 1] = { header = L["Ready to learn"] .. " (" .. #available .. ")", cost = totalCost }
        for _, entry in ipairs(available) do display[#display + 1] = entry end
    end
    if #soon > 0 then
        display[#display + 1] = { header = L["Coming soon"] .. " (" .. #soon .. ")" }
        for _, entry in ipairs(soon) do display[#display + 1] = entry end
    end
    if #weapons > 0 then
        display[#display + 1] = { header = L["Weapon skills, from a weapon master"] .. " (" .. #weapons .. ")" }
        for _, entry in ipairs(weapons) do display[#display + 1] = entry end
    end
    if #ignoredList > 0 then
        display[#display + 1] = { header = L["Ignored"] .. " (" .. #ignoredList .. ")" }
        for _, entry in ipairs(ignoredList) do
            entry.ignored = true
            display[#display + 1] = entry
        end
    end
end

UpdateWindow = function()
    if not (window and window:IsShown()) then return end
    BuildDisplay()
    local rows = window.rows
    local maxScroll = math.max(0, #display - #rows)
    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end
    local level, money = MyLevel(), Money()
    for i, row in ipairs(rows) do
        local item = display[i + scroll]
        row.entry = nil
        if not item then
            row:Hide()
        elseif item.header then
            row.icon:Hide()
            row.name:SetText("|cffffd100" .. item.header .. "|r")
            row.level:SetText("")
            row.cost:SetText(item.cost and MoneyText(item.cost) or "")
            row:Show()
        else
            row.entry = item
            row.icon:SetTexture(SpellIcon(item.id))
            row.icon:Show()
            local name = item.name
            if item.ignored then
                name = "|cff777777" .. name .. "|r"
            elseif item.isNew then
                name = "|cff40ff40" .. name .. "|r  |cff40ff40" .. L["new"] .. "|r"
            end
            row.name:SetText(name)
            row.level:SetText((item.level > level and "|cffff8040" or "|cffaaaaaa") .. item.level .. "|r")
            if item.quest then
                row.cost:SetText("|cffffd100" .. L["class quest"] .. "|r")
            else
                row.cost:SetText((item.cost > money and "|cffff6060" or "") .. MoneyText(item.cost))
            end
            row:Show()
        end
    end
    window.empty:SetShown(#display == 0)
    if Data then
        window.empty:SetText(L["Nothing to learn from your trainer right now."])
    else
        window.empty:SetText(L["There is no trainer list for this class."])
    end
end

local function BuildWindow()
    local ok, f = pcall(CreateFrame, "Frame", "OxedHubTrainingReminderFrame", UIParent, "BasicFrameTemplate")
    if not ok or not f then
        f = CreateFrame("Frame", "OxedHubTrainingReminderFrame", UIParent, "BasicFrameTemplateWithInset")
    end
    window = f
    f:Hide()
    f:SetSize(440, 500)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -6)
    end
    title:SetText(L["Training Reminder"])
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "OxedHubTrainingReminderFrame") end

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 10, -30)
    list:SetPoint("BOTTOMRIGHT", -10, 30)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta * 3
        UpdateWindow()
    end)

    f.rows = {}
    local count = math.floor((f:GetHeight() - 60) / ROW_HEIGHT)
    for i = 1, count do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("RightButtonUp")
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.08)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.cost:SetPoint("RIGHT", -4, 0)
        row.cost:SetJustifyH("RIGHT")
        row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.level:SetPoint("RIGHT", -110, 0)
        row.level:SetWidth(30)
        row.level:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", 28, 0)
        row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            settings.ignored[entry.id] = (not settings.ignored[entry.id]) or nil
            Rescan()
        end)
        row:SetScript("OnEnter", function(self)
            local entry = self.entry
            if not entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetSpellByID, GameTooltip, entry.id) then
                GameTooltip:SetText(entry.name)
            end
            GameTooltip:AddLine(" ")
            local where = AreaNames(entry.areas)
            if entry.quest then
                GameTooltip:AddLine(L["Taught by a class quest, from level %d"]:format(entry.level), 1, 0.82, 0)
                if where ~= "" then GameTooltip:AddLine(L["The quest starts in: %s"]:format(where), 1, 1, 1, true) end
            elseif entry.weapon then
                GameTooltip:AddLine(L["Taught by a weapon master"], 1, 0.82, 0)
                if where ~= "" then GameTooltip:AddLine(where, 1, 1, 1, true) end
            else
                GameTooltip:AddLine(L["Trainer level %d"]:format(entry.level), 1, 0.82, 0)
            end
            GameTooltip:AddLine(entry.ignored and L["Right-click: remind me about it again."] or L["Right-click: never remind me about it."], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[i] = row
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER", 0, 20)
    f.empty:SetTextColor(0.7, 0.7, 0.7)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 10)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["Green is a new ability. Right-click a spell to stop the reminders about it."])

    f:SetScript("OnShow", function()
        Scan()
        UpdateWindow()
    end)
end

ShowWindow = function()
    if not running then
        Say(L["Training Reminder is switched off. Switch it on in the Modules page."])
        return
    end
    if not window then BuildWindow() end
    window:Show()
end

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_CLOSED", "PLAYER_MONEY", "CHARACTER_POINTS_CHANGED",
    "SKILL_LINES_CHANGED", "QUEST_TURNED_IN",
}

events:SetScript("OnEvent", function(_, event, arg1)
    if not running then return end
    if event == "PLAYER_LEVEL_UP" then
        -- The new level arrives with the event, before UnitLevel has it.
        if type(arg1) == "number" and not IsSecret(arg1) then lastLevel = arg1 end
        C_Timer.After(SETTLE, function() Remind("level") end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(LOGIN_DELAY, function()
            -- Only once per session: a loading screen is not a reason.
            if lastShown == 0 then Remind("login") end
        end)
    elseif event == "PLAYER_UPDATE_RESTING" then
        local resting = Call(IsResting)
        if settings.remindCity and resting and not IsSecret(resting)
            and not (card and card:IsShown()) then
            Remind("city")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingReason then
            local reason = pendingReason
            pendingReason = nil
            Remind(reason)
        end
    else
        QueueRescan()
    end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Training Reminder", 460, 460)
        optionsWindow = w
        w:AddCheckbox(settings, "card", "Show a card on screen", nil, function(on)
            if not on then HideCard() end
        end)
        w:AddCheckbox(settings, "chat", "Say it in chat too")
        w:AddSoundPicker(settings, "sound", "Sound with the reminder")
        w:AddCheckbox(settings, "onlyNew", "Remind about new abilities only, not higher ranks", nil, Rescan)
        w:AddCheckbox(settings, "onlyAfford", "Only when I have the money for at least one")
        w:AddCheckbox(settings, "remindTalents", "Remind me about unspent talent points", nil, Rescan)
        w:AddCheckbox(settings, "remindProfessions", "Remind me when a profession needs its next rank", nil, Rescan)
        w:AddCheckbox(settings, "remindWeapons", "Remind me about weapon skills too", nil, Rescan)
        w:AddCheckbox(settings, "remindCity", "Remind me again when I enter a city or an inn")
        w:AddSlider(settings, "remindMinutes", "Remind me again every, minutes (0 is never)", 0, 60, 5, "%s: %d")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(200, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY - 4)
        test:SetText(L["Test notification"])
        test:SetScript("OnClick", function() Remind("test") end)
        w.cursorY = w.cursorY - 32
        w:AddNote("The reminder comes when you level up, when you log in, and again later while something is still unlearned. Right-click a spell in the list to stop the reminders about it. Spells from class quests are in the list too. Weapon skills are listed, and join the reminder only if you tick them. Pet abilities and warlock tomes are not covered.")
        w:SetHeight(math.max(200, 16 - w.cursorY))
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "trainingreminder", label = L["Training Reminder"], icon = "Interface\\Icons\\INV_Misc_Book_09", config = settings,
        hint = L["Click: the list. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ShowWindow() end
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBTRAININGREMINDER1 = "/oxtrain"
SlashCmdList.OXEDHUBTRAININGREMINDER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" then
        ShowOptions()
    elseif msg == "test" then
        Remind("test")
    else
        ShowWindow()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- The trainer lists are Forever's. The main game teaches spells by itself.
    if OxedHub.IsMainline then return end

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.trainingreminder
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.trainingreminder = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- A list is made here, never in DEFAULTS (it would be shared).
    if type(config.ignored) ~= "table" then config.ignored = {} end
    settings = config

    Data = OxedHub.TrainingReminderData
    if Data and type(Data.spellsByLevel) ~= "table" then Data = nil end
    BuildRanks()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "trainingreminder",
        name     = "Training Reminder",
        version  = "1.2.1",
        updated  = 20261111.9,
        added    = 20261111,
        author   = "Oxed",
        category = "character",
        keywords = { "trainer", "train", "spell", "skill", "rank", "learn", "level", "reminder", "ability", "forever" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A card on screen when your trainer has new spells, and again if you forget. /oxtrain",
        icon     = "Interface\\Icons\\INV_Misc_Book_09",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.ignored) ~= "table" then settings.ignored = {} end
            running = true
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            for _, event in ipairs(EVENTS) do pcall(events.RegisterEvent, events, event) end
            -- Switched on by hand in the middle of a session: look soon, once
            -- the spellbook is sure to be there.
            C_Timer.After(LOGIN_DELAY, function()
                if running and lastShown == 0 then Remind("login") end
            end)
            if not ticker and C_Timer.NewTicker then
                ticker = C_Timer.NewTicker(60, function()
                    local minutes = tonumber(settings.remindMinutes) or 0
                    if minutes <= 0 or lastShown == 0 then return end
                    if card and card:IsShown() then return end
                    if GetTime() - lastShown >= minutes * 60 then Remind("timer") end
                end)
            end
        end,

        OnDisable = function()
            running = false
            pendingReason = nil
            if ticker then
                ticker:Cancel()
                ticker = nil
            end
            if minimapIcon then minimapIcon:Apply(false) end
            events:UnregisterAllEvents()
            HideCard()
            if window then window:Hide() end
        end,
    })
end)
