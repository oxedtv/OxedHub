-- ============================================================================
-- Training Reminder (built-in OxedHub module, WoW Forever only)
-- Tells you when your class trainer has something new for you: a card on
-- screen when you level up, and again later if you still have not been, with
-- the new abilities named first. A window lists what is ready, what it costs
-- and what comes in the next levels.
--
-- What a class learns and at which level is in TrainingReminderData.lua. What
-- you already know is asked of the spellbook. The exceptions are a hunter's
-- pet abilities and a warlock's demon tomes: those live in the pet's book, so
-- what has been seen there is kept per character in petLearned.
--
-- Prices include the 10% a trainer takes off at Honored with its city. The
-- Train All button at the class trainer is opt-in, asks first, and skips the
-- spells on the ignore list.
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
    remindPets        = false,   -- a hunter's pet abilities
    remindTomes       = false,   -- a warlock's demon tomes
    trainAll          = false,   -- a Train All button at the class trainer
    spellbookPanel    = true,    -- what to learn, beside the spellbook
    -- ignored and petLearned are tables, made at login
}

local PREFIX = "|cff00ccffOxedHub|r "
local SOON_LEVELS = 2        -- "coming soon" looks this many levels ahead
local SETTLE = 1.5           -- the spellbook catches up with a level up
local LOGIN_DELAY = 8
local CITY_GAP = 15 * 60     -- the city reminder never comes sooner than this
local RESCAN_DELAY = 1       -- spell events come in bursts
local CARD_ROWS = 8            -- spells named on the card; the rest are in the list
local CARD_ROW = 22
local CARD_TOP = 30           -- where the first row starts, under the banner
local CARD_WIDTH = 350
local ROW_HEIGHT = 22

local settings
local running = false
local Data                   -- OxedHub.TrainingReminderData, or nil
local rankGroup = {}         -- spell id -> { group, index }
local requires = {}          -- spell id -> the spells it needs first
local available, soon, ignoredList = {}, {}, {}
local weapons = {}           -- weapon skills still to learn
local pets = {}              -- a hunter's pet abilities still to learn
local tomes = {}             -- a warlock's demon tomes still to read
local petsSeen = false       -- Beast Training has been opened on this character
local discount = { pct = 0 } -- the class trainer's reputation discount
local extras = {}            -- other reminders, as ready lines of text
local totalCost = 0
local card, window, optionsWindow
local minimapIcon
local display = {}
local scroll = 0
local lastShown = 0
local loginChecked = false   -- the login reminder has had its look this session
local pendingReason          -- a card due in combat
local rescanQueued = false
local ticker
local scanCount = 0           -- goes up with every Scan, so views know to redraw

local events = CreateFrame("Frame")

-- Defined further down, used above their definitions.
local ShowOptions, MinimapIcon, ShowWindow, UpdateWindow
local StartSpellbookPanel, HideSpellbookPanel

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
    wipe(requires)
    if Data and type(Data.spellsByLevel) == "table" then
        for _, spells in pairs(Data.spellsByLevel) do
            for _, spell in ipairs(spells) do
                if type(spell.requiredIds) == "table" then requires[spell.id] = spell.requiredIds end
            end
        end
    end
    if not (Data and type(Data.overriddenGroups) == "table") then return end
    for _, group in ipairs(Data.overriddenGroups) do
        for index, id in ipairs(group) do
            rankGroup[id] = { group = group, index = index }
        end
    end
end

-- ── The pet's book: hunter pet abilities, warlock demon tomes ───────────────

-- What this character's pets are known to have, kept between sessions:
-- { seen = Beast Training was opened, spells = { [id] = true }, tomes = { [itemId] = true } }
local function MyPetStore()
    if type(settings.petLearned) ~= "table" then settings.petLearned = {} end
    local key = Call(UnitGUID, "player")
    if type(key) ~= "string" or IsSecret(key) then key = "?" end
    local store = settings.petLearned[key]
    if type(store) ~= "table" then
        store = {}
        settings.petLearned[key] = store
    end
    if type(store.spells) ~= "table" then store.spells = {} end
    if type(store.tomes) ~= "table" then store.tomes = {} end
    return store
end

local function InPetBook(id)
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if not (C_SpellBook and bank ~= nil) then return false end
    local inBook = Call(C_SpellBook.IsSpellInSpellBook, id, bank, false)
    return inBook and not IsSecret(inBook) or false
end

-- Marks a pet ability as learned, and the ranks it needed before it.
local function MarkPetLearned(id, store, depth)
    store = store or MyPetStore()
    depth = depth or 0
    if depth > 20 or store.spells[id] then return false end
    store.spells[id] = true
    for _, required in ipairs(requires[id] or {}) do MarkPetLearned(required, store, depth + 1) end
    return true
end

local function IsPetAbility(id)
    return Data and type(Data.petAbilityIds) == "table" and Data.petAbilityIds[id] == true or false
end

local function PetKnown(id)
    local store = MyPetStore()
    if store.spells[id] or InPetBook(id) then return true end
    local at = rankGroup[id]
    if at then
        for i = at.index + 1, #at.group do
            if store.spells[at.group[i]] then return true end
        end
    end
    return false
end

-- Known by the player, or by the pet for a pet ability.
local function KnownAny(id)
    if IsPetAbility(id) then return PetKnown(id) end
    return KnownOrHigher(id)
end

-- Beast Training opens a trainer window that lists what the hunter can teach
-- the pet: everything in it has been learned. A pet trainer (someone you talk
-- to) opens the same kind of window but sells, so only "used" counts there.
local function ReadPetTrainer()
    if not (Data and type(Data.petAbilityIds) == "table") then return false end
    if not (C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType and Enum.TrainerType.Pet) then return false end
    local kind = Call(C_Trainer.GetTrainerType)
    if kind ~= Enum.TrainerType.Pet then return false end
    local count = Call(GetNumTrainerServices)
    if type(count) ~= "number" or IsSecret(count) then return false end
    local npc = Call(UnitExists, "npc")
    local talking = npc and not IsSecret(npc)
    local store = MyPetStore()
    local changed = false
    if not talking and not store.seen then
        store.seen = true
        changed = true
    end
    for i = 1, count do
        local _, status = Call(GetTrainerServiceInfo, i)
        if not talking or status == "used" then
            local data = Call(C_TooltipInfo and C_TooltipInfo.GetTrainerService, i)
            local id = type(data) == "table" and data.id or nil
            if type(id) == "number" and not IsSecret(id) and Data.petAbilityIds[id] then
                if MarkPetLearned(id, store) then changed = true end
            end
        end
    end
    return changed
end

-- "You have learned a new spell: <link>": Forever sends a link, and a pet
-- ability learned that way is in no spellbook the module can ask.
local function ReadLearnLine(text)
    if type(text) ~= "string" or IsSecret(text) then return false end
    if not (Data and type(Data.petAbilityIds) == "table") then return false end
    local id = tonumber(text:match("|Hspell:(%d+)"))
    if not id or not Data.petAbilityIds[id] then return false end
    return MarkPetLearned(id)
end

-- Demon tomes: summon spell per family, the sayaad's two counting as one.
local SUMMONS = { Imp = { 688 }, Voidwalker = { 697 }, Sayaad = { 712, 713 }, Felhunter = { 691 } }
local FAMILY_LABEL = { Imp = "Imp", Voidwalker = "Voidwalker", Sayaad = "Succubus or Incubus", Felhunter = "Felhunter" }

local function TomeFamily(tome)
    if tome.family == "Succubus" or tome.family == "Incubus" then return "Sayaad" end
    return tome.family
end

local function ItemName(itemId)
    local name = Call(C_Item and C_Item.GetItemNameByID, itemId)
    if type(name) ~= "string" or IsSecret(name) or name == "" then name = Call(GetItemInfo, itemId) end
    if type(name) == "string" and not IsSecret(name) and name ~= "" then return name end
    return nil
end

-- ── Trainer reputation ──────────────────────────────────────────────────────

local function FactionInfo(key)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = Call(C_Reputation.GetFactionDataByID, key)
        if type(data) == "table" and type(data.reaction) == "number" and not IsSecret(data.reaction) then
            return data.name, data.reaction
        end
    end
    local name, _, standing = Call(GetFactionInfoByID, key)
    if type(standing) == "number" and not IsSecret(standing) then return name, standing end
    return nil, nil
end

-- The best discount any trainer of this role gives, and whose it is.
-- Forever: Honored (6) or better takes 10% off.
local function RoleDiscount(role, faction)
    local data = Data and Data.trainerFactions
    local roles = type(data) == "table" and type(data.roles) == "table" and data.roles[role]
    local keys = type(roles) == "table" and faction and roles[faction]
    if type(keys) ~= "table" then return 0, nil end
    for _, key in ipairs(keys) do
        local name, standing = FactionInfo(key)
        if standing and standing >= 6 then
            return 10, (type(name) == "string" and not IsSecret(name)) and name or nil
        end
    end
    return 0, nil
end

local function Discounted(cost, pct)
    if not pct or pct <= 0 then return cost end
    return math.floor((cost * (100 - pct) + 50) / 100)
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
    scanCount = scanCount + 1
    wipe(available)
    wipe(soon)
    wipe(ignoredList)
    wipe(weapons)
    wipe(pets)
    wipe(tomes)
    wipe(extras)
    totalCost = 0
    local spellsByLevel = Data and type(Data.spellsByLevel) == "table" and Data.spellsByLevel or {}
    local level = MyLevel()
    local faction = Call(UnitFactionGroup, "player")
    if IsSecret(faction) then faction = nil end
    local _, _, race = Call(UnitRace, "player")
    if IsSecret(race) then race = nil end
    local _, classToken = Call(UnitClass, "player")
    if IsSecret(classToken) then classToken = nil end
    local petStore = MyPetStore()
    petsSeen = petStore.seen == true

    -- Prices as the cheapest trainer asks them.
    discount.pct, discount.name = 0, nil
    if classToken then discount.pct, discount.name = RoleDiscount(classToken, faction) end
    local petPct = RoleDiscount("PET", faction)

    for spellLevel, spells in pairs(spellsByLevel) do
        if spellLevel <= level + SOON_LEVELS then
            for _, spell in ipairs(spells) do
                local id = spell.id
                local isPet = IsPetAbility(id)
                if ForMe(spell, faction, race) and not KnownAny(id)
                    and (not spell.requiredTalentId or Known(spell.requiredTalentId)) then
                    local name = SpellName(id)
                    local base = tonumber(spell.cost) or 0
                    local entry = {
                        id = id,
                        level = spellLevel,
                        baseCost = base,
                        cost = Discounted(base, isPet and petPct or discount.pct),
                        name = name or (L["Spell"] .. " " .. id),
                        isNew = IsNewAbility(spell, name),
                        pet = isPet or nil,
                    }
                    if settings.ignored[id] then
                        ignoredList[#ignoredList + 1] = entry
                    elseif spellLevel > level then
                        -- Pet abilities only once the module knows what the pet has.
                        if not isPet or petsSeen then soon[#soon + 1] = entry end
                    else
                        -- A rank whose earlier rank is still unlearned waits
                        -- for it: the earlier one is in the list already.
                        local ready = true
                        if type(spell.requiredIds) == "table" then
                            for _, required in ipairs(spell.requiredIds) do
                                if not KnownAny(required) then ready = false end
                            end
                        end
                        if ready and isPet then
                            pets[#pets + 1] = entry
                        elseif ready then
                            available[#available + 1] = entry
                            totalCost = totalCost + entry.cost
                        end
                    end
                end
            end
        end
    end

    -- Demon tomes, for the demons this warlock can summon. What a demon has
    -- read is seen in the pet's book while it is out, and remembered.
    local tomesByLevel = Data and Data.tomesByLevel
    local taughtBy = Data and Data.tomeTaughtSpells
    if type(tomesByLevel) == "table" and type(taughtBy) == "table" then
        local families = {}
        for family, ids in pairs(SUMMONS) do
            for _, id in ipairs(ids) do
                if Known(id) then families[family] = true end
            end
        end
        -- A higher rank read means the lower ones are no use any more.
        -- And of two ranks ready now, only the higher is worth buying.
        local best, top = {}, {}
        for tomeLevel, list in pairs(tomesByLevel) do
            for _, tome in ipairs(list) do
                local taught = taughtBy[tome.itemId]
                if taught then
                    if InPetBook(taught) then petStore.tomes[tome.itemId] = true end
                    local key = TomeFamily(tome) .. ":" .. (SpellName(taught) or taught)
                    if petStore.tomes[tome.itemId] and (best[key] or 0) < tomeLevel then best[key] = tomeLevel end
                    if tomeLevel <= level and (top[key] or 0) < tomeLevel then top[key] = tomeLevel end
                end
            end
        end
        local listed = {}
        for tomeLevel, list in pairs(tomesByLevel) do
            if tomeLevel <= level + SOON_LEVELS then
                for _, tome in ipairs(list) do
                    local family = TomeFamily(tome)
                    local taught = taughtBy[tome.itemId]
                    local spellName = taught and SpellName(taught)
                    local key = family .. ":" .. (spellName or taught or 0)
                    if taught and families[family] and not listed[tome.itemId]
                        and not petStore.tomes[tome.itemId] and not ((best[key] or 0) > tomeLevel)
                        and not ((top[key] or 0) > tomeLevel) then
                        listed[tome.itemId] = true
                        local entry = {
                            id = taught, itemId = tome.itemId, level = tomeLevel,
                            baseCost = tonumber(tome.cost) or 0, cost = tonumber(tome.cost) or 0,
                            name = (spellName or ItemName(tome.itemId) or (L["Spell"] .. " " .. taught))
                                .. " (" .. L[FAMILY_LABEL[family] or family] .. ")",
                            isNew = false, tome = true,
                        }
                        if settings.ignored[taught] then
                            ignoredList[#ignoredList + 1] = entry
                        elseif tomeLevel > level then
                            soon[#soon + 1] = entry
                        else
                            tomes[#tomes + 1] = entry
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
    if type(classToken) == "string" then
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
    table.sort(pets, BySoonest)
    table.sort(tomes, BySoonest)
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
    -- Until Beast Training has been opened every pet ability looks unlearned.
    if settings.remindPets and petsSeen then
        for _, entry in ipairs(pets) do list[#list + 1] = entry end
    end
    if settings.remindTomes then
        for _, entry in ipairs(tomes) do list[#list + 1] = entry end
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

-- ── Shared look ──────────────────────────────────────────────────────────────

-- Tab buttons and the scroll bar are shared OxedHub components
-- (UI\Components\Button.lua, Scroll.lua): the game's own when this client
-- has them, drawn ones otherwise.
local function TabButton(parent, width, text, onClick, height)
    return OxedHub.UIComponents.Button.CreateTab(parent, width, text, onClick, height or 28)
end
local RedButton = TabButton

local function ScrollBar(f, top, height, onScroll)
    return OxedHub.UIComponents.Scroll.CreateMinimalBar(f, top, height, onScroll)
end

-- A thin dark frame round a spell icon, the way the game's own lists draw
-- them. The icon goes inside it.
local function IconFrame(parent, size)
    local edge = parent:CreateTexture(nil, "BORDER")
    edge:SetSize(size + 2, size + 2)
    edge:SetColorTexture(0, 0, 0, 0.9)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("CENTER", edge, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return edge, icon
end

-- The ornate OxedHub frame on a child, so it never eats the parent's clicks.
-- Returns a function that changes the title.
local function OrnateShell(f, title)
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        local shell = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        shell:SetAllPoints(f)
        shell:SetFrameLevel(f:GetFrameLevel())
        shell:EnableMouse(false)
        local ok = pcall(Panel.ApplyOrnateFrame, shell, title, 0.96)
        if ok and shell.titleText then
            return function(text) shell.titleText:SetText(text) end
        end
        shell:Hide()
    end
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.055, 0.05, 0.94)
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOP", 0, -8)
    text:SetText(title)
    return function(value) text:SetText(value) end
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
    -- The same ornate frame as the list window; the title sits on its banner.
    card.setTitle = OrnateShell(card, L["Learn at your trainer"])
    local close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    close:SetScale(0.8)
    close:SetPoint("TOPRIGHT", card, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() card:Hide() end)

    -- One line per spell: its icon, name and rank, and what it costs.
    card.rows = {}
    for i = 1, CARD_ROWS do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(CARD_WIDTH - 24, CARD_ROW)
        row:SetPoint("TOPLEFT", 12, -CARD_TOP - (i - 1) * CARD_ROW)
        local stripe = row:CreateTexture(nil, "BACKGROUND", nil, -8)
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.03 or 0.07)
        row.edge, row.icon = IconFrame(row, 18)
        row.edge:SetPoint("LEFT", 1, 0)
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
    card.setTitle(#list > 0 and L["Learn at your trainer"] or L["Do not forget"])

    for i, row in ipairs(card.rows) do
        local entry = list[i]
        if entry then
            cost = cost + entry.cost
            row.id, row.spell = entry.id, entry.name
            row.icon:SetTexture(SpellIcon(entry.id))
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
        if discount.pct > 0 then
            lines[#lines + 1] = "|cff40ff40" .. L["%d%% off at the trainers of %s (Honored)"]:format(discount.pct, discount.name or "?") .. "|r"
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
-- When the last reminder came and which spells it named, kept per character
-- (in the same store as the pet's book) so a reload or a new login does not
-- start the clock again.
local function ReminderStore()
    local store = MyPetStore()
    if type(store.remindedIds) ~= "table" then store.remindedIds = {} end
    return store
end

-- Seconds since the last reminder; huge when there never was one.
local function SinceLastReminder()
    local at = ReminderStore().remindedAt
    local now = Call(time)
    if type(at) ~= "number" or type(now) ~= "number" then return math.huge end
    return now - at
end

-- A spell on the list that the last reminder did not name.
local function HasNewSpell(list)
    local named = ReminderStore().remindedIds
    for _, entry in ipairs(list) do
        if not named[entry.id] then return true end
    end
    return false
end

local function RecordReminder(list)
    local store = ReminderStore()
    store.remindedAt = Call(time) or store.remindedAt
    wipe(store.remindedIds)
    for _, entry in ipairs(list) do store.remindedIds[entry.id] = true end
end

-- reason: "level", "login", "city", "timer" or "test".
-- Something new on the list shows at once (a level that brings new spells).
-- The same list again waits for "Remind me again every" since the last
-- reminder; at 0 the same list never comes back by itself.
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
        local minutes = tonumber(settings.remindMinutes) or 0
        local due = minutes > 0 and SinceLastReminder() >= minutes * 60
        if not due and not HasNewSpell(list) then return end
        if settings.onlyAfford and #extras == 0 and not CanAffordAny(list) then return end
        if InCombatLockdown() then
            pendingReason = reason
            return
        end
    end
    lastShown = GetTime()
    if reason ~= "test" then RecordReminder(list) end
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

-- Looks like the other OxedHub windows (Hunter Pets, Leveling Finds): the
-- ornate frame, red tab buttons, two-line rows with a big icon.

local WIN_W, WIN_H = 640, 560
local LIST_TOP = -112        -- where the first row starts
local LIST_ROW = 40
local TABS = {
    { key = "all",     label = "All",            width = 86 },
    { key = "ready",   label = "Ready to learn", width = 146 },
    { key = "soon",    label = "Coming soon",    width = 136 },
    { key = "other",   label = "Other",          width = 100 },
    { key = "ignored", label = "Ignored",        width = 104 },
}

local function VisibleRows()
    return math.floor((WIN_H + LIST_TOP - 40) / LIST_ROW)
end

local function TabCount(key)
    if key == "ready" then return #available end
    if key == "soon" then return #soon end
    if key == "other" then return #weapons + #pets + #tomes end
    if key == "ignored" then return #ignoredList end
    return #available + #soon + #weapons + #pets + #tomes
end

local function AddSection(header, list, hint)
    if #list == 0 then return end
    if header then display[#display + 1] = { header = header .. " (" .. #list .. ")" } end
    if hint then display[#display + 1] = { header = hint, quiet = true } end
    for _, entry in ipairs(list) do display[#display + 1] = entry end
end

local function BuildDisplay()
    wipe(display)
    for _, entry in ipairs(ignoredList) do entry.ignored = true end
    local tab = settings.tab or "all"
    local petHint = not petsSeen and L["Open Beast Training once so the list knows what your pet has"] or nil
    if tab == "all" or tab == "ready" then
        for _, extra in ipairs(extras) do display[#display + 1] = { header = extra, notice = true } end
    end
    if tab == "all" then
        AddSection(L["Ready to learn"], available)
        AddSection(L["Coming soon"], soon)
        AddSection(L["Weapon skills, from a weapon master"], weapons)
        AddSection(L["Pet abilities, from a pet trainer"], pets, petHint)
        AddSection(L["Demon tomes, from your demon trainer"], tomes)
        AddSection(L["Ignored"], ignoredList)
    elseif tab == "ready" then
        AddSection(nil, available)
    elseif tab == "soon" then
        AddSection(nil, soon)
    elseif tab == "other" then
        AddSection(L["Weapon skills, from a weapon master"], weapons)
        AddSection(L["Pet abilities, from a pet trainer"], pets, petHint)
        AddSection(L["Demon tomes, from your demon trainer"], tomes)
    elseif tab == "ignored" then
        AddSection(nil, ignoredList)
    end
end

-- The second line of a row: where it comes from and from which level.
local function SourceText(item, level)
    local where = AreaNames(item.areas)
    local text
    if item.quest then
        text = L["Class quest, level %d"]:format(item.level)
        if where ~= "" then text = text .. ", " .. where end
    elseif item.weapon then
        text = L["Weapon master"]
        if where ~= "" then text = text .. ", " .. where end
    elseif item.tome then
        text = L["Demon tome, level %d"]:format(item.level)
    elseif item.pet then
        text = L["Pet trainer, level %d"]:format(item.level)
    else
        text = L["Trainer, level %d"]:format(item.level)
    end
    if item.level > level then text = "|cffff8040" .. text .. "|r" end
    if item.ignored then
        text = text .. "   |cff888888" .. L["ignored"] .. "|r"
    elseif item.isNew then
        text = text .. "   |cff40ff40" .. L["new ability"] .. "|r"
    end
    return text
end

local function RefreshTabs()
    local tab = settings.tab or "all"
    for _, b in ipairs(window.tabs) do
        local count = TabCount(b.key)
        b:SetLabel(L[b.textKey] .. (count > 0 and (" (" .. count .. ")") or ""))
        b:SetActive(b.key == tab)
    end
end

local function RefreshSummary()
    local money = Money()
    local text
    if #available > 0 then
        local have = MoneyText(money)
        if money < totalCost then have = "|cffff6060" .. have .. "|r" end
        text = L["%d to learn, %s in all. You have %s"]:format(#available, MoneyText(totalCost), have)
    else
        text = L["Nothing to learn from your trainer right now."]
    end
    if discount.pct > 0 then
        text = text .. "\n|cff40ff40" .. L["%d%% off at the trainers of %s (Honored)"]:format(discount.pct, discount.name or "?") .. "|r"
    end
    window.summary:SetText(text)
end

UpdateWindow = function()
    if not (window and window:IsShown()) then return end
    BuildDisplay()
    RefreshTabs()
    RefreshSummary()
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
            row.bg:Hide()
            row.icon:Hide()
            row.edge:Hide()
            row.sub:SetText("")
            row.cost:SetText("")
            row.title:ClearAllPoints()
            row.title:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.title:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
            if item.quiet then
                row.title:SetText("|cff999999" .. item.header .. "|r")
                row.line:Hide()
            elseif item.notice then
                row.title:SetText("|cffffd100!|r  " .. item.header)
                row.line:Hide()
            else
                row.title:SetText("|cffffd100" .. item.header .. "|r")
                row.line:Show()
            end
            row:Show()
        else
            row.entry = item
            row.bg:Show()
            row.line:Hide()
            row.icon:SetTexture(SpellIcon(item.id))
            row.icon:Show()
            row.edge:Show()
            row.icon:SetDesaturated(item.ignored == true)
            row.title:ClearAllPoints()
            row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
            row.title:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
            local colour = item.ignored and "|cff888888" or (item.isNew and "|cff40ff40" or "|cffffffff")
            local rank = SpellRank(item.id)
            row.title:SetText(colour .. item.name .. "|r" .. (rank and ("  |cff999999" .. rank .. "|r") or ""))
            row.sub:SetText(SourceText(item, level))
            if item.quest then
                row.cost:SetText("|cffffd100" .. L["class quest"] .. "|r")
            elseif item.cost > money then
                row.cost:SetText("|cffff6060" .. MoneyText(item.cost) .. "|r")
            elseif item.baseCost and item.cost < item.baseCost then
                row.cost:SetText("|cff40ff40" .. MoneyText(item.cost) .. "|r")
            else
                row.cost:SetText(MoneyText(item.cost))
            end
            row:Show()
        end
    end
    window.empty:SetShown(#display == 0)
    if not Data then
        window.empty:SetText(L["There is no trainer list for this class."])
    elseif (settings.tab or "all") == "ignored" then
        window.empty:SetText(L["Nothing ignored. Right-click a spell to stop the reminders about it."])
    else
        window.empty:SetText(L["Nothing here right now."])
    end
    window.bar:Sync(scroll, maxScroll, #rows, #display)
end

local function RowTooltip(self)
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
    elseif entry.tome then
        GameTooltip:AddLine(L["A tome for your demon, from level %d"]:format(entry.level), 1, 0.82, 0)
        local book = ItemName(entry.itemId)
        if book then GameTooltip:AddLine(book, 1, 1, 1, true) end
        GameTooltip:AddLine(L["Known once the demon is out with it in its spellbook."], 0.6, 0.6, 0.6, true)
    elseif entry.pet then
        GameTooltip:AddLine(L["Pet ability, from level %d"]:format(entry.level), 1, 0.82, 0)
    else
        GameTooltip:AddLine(L["Trainer level %d"]:format(entry.level), 1, 0.82, 0)
    end
    if entry.baseCost and entry.cost < entry.baseCost then
        GameTooltip:AddLine(L["%s, reputation discount included (full price %s)"]:format(MoneyText(entry.cost), MoneyText(entry.baseCost)), 0.25, 1, 0.25, true)
    end
    GameTooltip:AddLine(entry.ignored and L["Right-click: remind me about it again."] or L["Right-click: never remind me about it."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function BuildWindow()
    local f = CreateFrame("Frame", "OxedHubTrainingReminderFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    window = f
    f:Hide()
    f:SetSize(WIN_W, WIN_H)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        settings.winPoint, settings.winX, settings.winY = point, x, y
    end)
    f:SetPoint(settings.winPoint or "CENTER", UIParent, settings.winPoint or "CENTER", settings.winX or 0, settings.winY or 0)
    OrnateShell(f, L["Training Reminder"])
    f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
    f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OxedHubTrainingReminderFrame") end

    f.tabs = {}
    local tabX = 18
    for i, tab in ipairs(TABS) do
        local b = TabButton(f, tab.width, L[tab.label], function()
            settings.tab = tab.key
            scroll = 0
            UpdateWindow()
        end)
        b:SetPoint("TOPLEFT", tabX, -34)
        tabX = tabX + tab.width + 6
        b.key, b.textKey = tab.key, tab.label
        f.tabs[i] = b
    end

    local opt = RedButton(f, 80, L["Options"], function() ShowOptions() end)
    opt:SetPoint("TOPRIGHT", -24, -74)
    local test = RedButton(f, 80, L["Test"], function() Remind("test") end)
    test:SetPoint("RIGHT", opt, "LEFT", -6, 0)

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.summary:SetPoint("TOPLEFT", 24, -80)
    f.summary:SetPoint("RIGHT", test, "LEFT", -10, 0)
    f.summary:SetJustifyH("LEFT")
    f.summary:SetSpacing(2)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.empty:SetPoint("TOP", 0, LIST_TOP - 60)
    f.empty:SetWidth(WIN_W - 80)
    f.empty:Hide()

    -- The game's minimal scroll bar beside the rows; the mouse wheel moves it too.
    local count = VisibleRows()
    f.bar = ScrollBar(f, LIST_TOP, count * LIST_ROW - 2, function(value)
        if value ~= scroll then
            scroll = value
            UpdateWindow()
        end
    end)

    local function Wheel(_, delta)
        scroll = scroll - delta * 3
        UpdateWindow()
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", Wheel)

    f.rows = {}
    for i = 1, count do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(LIST_ROW - 2)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 18, LIST_TOP - (i - 1) * LIST_ROW)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, LIST_TOP - (i - 1) * LIST_ROW)
        row:RegisterForClicks("RightButtonUp")
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", Wheel)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)
        local shine = row:CreateTexture(nil, "HIGHLIGHT")
        shine:SetAllPoints()
        shine:SetColorTexture(1, 1, 1, 0.06)
        -- A thin gold line under a section's name.
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetColorTexture(1, 1, 1, 0.12)
        row.line:SetHeight(1)
        row.line:SetPoint("BOTTOMLEFT", 4, 6)
        row.line:SetPoint("BOTTOMRIGHT", -4, 6)
        row.edge, row.icon = IconFrame(row, 30)
        row.edge:SetPoint("LEFT", 4, 0)
        row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.cost:SetPoint("RIGHT", -8, 0)
        row.cost:SetJustifyH("RIGHT")
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.title:SetJustifyH("LEFT")
        if row.title.SetWordWrap then row.title:SetWordWrap(false) end
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
        row.sub:SetPoint("RIGHT", row.cost, "LEFT", -8, 0)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetTextColor(0.75, 0.75, 0.75)
        if row.sub.SetWordWrap then row.sub:SetWordWrap(false) end
        row:SetScript("OnClick", function(self)
            local entry = self.entry
            if not entry then return end
            settings.ignored[entry.id] = (not settings.ignored[entry.id]) or nil
            Rescan()
        end)
        row:SetScript("OnEnter", RowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        f.rows[i] = row
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 22, 14)
    hint:SetPoint("BOTTOMRIGHT", -22, 14)
    hint:SetJustifyH("LEFT")
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

-- ── Beside the spellbook ────────────────────────────────────────────────────
-- A panel next to the game's spellbook: for the page that is open (Survival,
-- Marksmanship...) the ranks ready to learn and those coming next, then the
-- other pages. Like Train All it is our own frame on UIParent, placed from
-- the spellbook's position; the spellbook itself is never touched.
--
-- Which page a spell belongs to is asked of the spellbook: the slot of the
-- spell itself (the book lists some future spells) or of a rank already
-- known, and the page whose slots hold it. A brand new ability that is in
-- no page yet goes under "New abilities".

local SIDE_W, SIDE_ROW = 280, 24
local SIDE_TOP = -54         -- where the first row starts
local side
local sideItems = {}
local sideScroll = 0
local sideClosed = false     -- closed with its x: back when the spellbook reopens
local sideCheck = 0
local sideDrawn = {}         -- what the drawn list was built from
local sideWatcher = CreateFrame("Frame")
sideWatcher:Hide()

local function OpenSpellbook()
    local frame = PlayerSpellsFrame
    local book = frame and frame.SpellBookFrame
    if book and book:IsVisible() then return frame, book end
    return nil
end

-- The spellbook's pages, with the slots each one holds.
local function SkillLines()
    local lines = {}
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo) then return lines end
    local count = Call(C_SpellBook.GetNumSpellBookSkillLines)
    if type(count) ~= "number" or IsSecret(count) then return lines end
    for i = 1, count do
        local info = Call(C_SpellBook.GetSpellBookSkillLineInfo, i)
        if type(info) == "table" and type(info.name) == "string" and not IsSecret(info.name)
            and type(info.itemIndexOffset) == "number" and type(info.numSpellBookItems) == "number"
            and not IsSecret(info.itemIndexOffset) and not IsSecret(info.numSpellBookItems) then
            lines[#lines + 1] = {
                order = i, name = info.name, icon = info.iconID,
                first = info.itemIndexOffset + 1, last = info.itemIndexOffset + info.numSpellBookItems,
            }
        end
    end
    return lines
end

local function SlotOf(id)
    if not (C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell) then return nil end
    local slot = Call(C_SpellBook.FindSpellBookSlotForSpell, id, false, true, true, true)
    if type(slot) == "number" and not IsSecret(slot) then return slot end
    return nil
end

local function LineOfSlot(lines, slot)
    for _, line in ipairs(lines) do
        if slot >= line.first and slot <= line.last then return line end
    end
    return nil
end

-- The page a spell is on: itself, then its lower ranks, then what it needs.
local function LineOf(lines, id)
    local tried = {}
    local function Try(spell, depth)
        if not spell or tried[spell] or depth > 12 then return nil end
        tried[spell] = true
        local slot = SlotOf(spell)
        local line = slot and LineOfSlot(lines, slot)
        if line then return line end
        local at = rankGroup[spell]
        if at then
            for i = at.index - 1, 1, -1 do
                local found = Try(at.group[i], depth + 1)
                if found then return found end
            end
        end
        for _, required in ipairs(requires[spell] or {}) do
            local found = Try(required, depth + 1)
            if found then return found end
        end
        return nil
    end
    return Try(id, 0)
end

-- The page that is open, told by the icon on its tab.
local function OpenTabIcon(book)
    local tabs = book.CategoryTabSystem
    local id = tabs and tabs.selectedTabID
    if not (id and tabs.GetTabButton) then return nil, id end
    local ok, button = pcall(tabs.GetTabButton, tabs, id)
    if not (ok and button and button.Icon and button.Icon.GetTexture) then return nil, id end
    local icon = Call(button.Icon.GetTexture, button.Icon)
    if IsSecret(icon) then icon = nil end
    return icon, id
end

local function BuildSideItems(book)
    wipe(sideItems)
    local lines = SkillLines()
    local icon = OpenTabIcon(book)
    local current
    for _, line in ipairs(lines) do
        if icon ~= nil and line.icon ~= nil and line.icon == icon then current = line end
    end

    local groups = {}
    local function Add(key, name, order, entry, ready)
        local group = groups[key]
        if not group then
            group = { name = name, order = order, list = {}, current = current ~= nil and key == current.name }
            groups[key] = group
        end
        group.list[#group.list + 1] = { entry = entry, ready = ready }
    end
    local function AddSpell(entry, ready)
        if entry.pet then
            Add("~pet", L["Pet abilities"], 1001, entry, ready)
        elseif entry.tome then
            Add("~tome", L["Demon tomes"], 1002, entry, ready)
        else
            local line = LineOf(lines, entry.id)
            if line then
                Add(line.name, line.name, line.order, entry, ready)
            else
                Add("~new", L["New abilities"], 1000, entry, ready)
            end
        end
    end
    for _, entry in ipairs(available) do AddSpell(entry, true) end
    for _, entry in ipairs(pets) do AddSpell(entry, true) end
    for _, entry in ipairs(tomes) do AddSpell(entry, true) end
    for _, entry in ipairs(soon) do AddSpell(entry, false) end

    -- The open page first, even when it has nothing, then the book's order.
    if current and not groups[current.name] then
        groups[current.name] = { name = current.name, order = current.order, list = {}, current = true }
    end
    local order = {}
    for _, group in pairs(groups) do order[#order + 1] = group end
    table.sort(order, function(a, b)
        if a.current ~= b.current then return a.current end
        return a.order < b.order
    end)
    for _, group in ipairs(order) do
        table.sort(group.list, function(a, b)
            if a.ready ~= b.ready then return a.ready end
            if a.entry.level ~= b.entry.level then return a.entry.level < b.entry.level end
            return a.entry.name < b.entry.name
        end)
        sideItems[#sideItems + 1] = { header = group.name, current = group.current }
        if #group.list == 0 then
            sideItems[#sideItems + 1] = { note = L["Nothing to learn on this page yet."] }
        end
        for _, item in ipairs(group.list) do sideItems[#sideItems + 1] = item end
    end
end

local function SideRowCount()
    return side and math.max(1, math.floor((side:GetHeight() + SIDE_TOP - 34) / SIDE_ROW)) or 0
end

local function DrawSide()
    if not side then return end
    local money = Money()
    if #available > 0 then
        local have = MoneyText(money)
        if money < totalCost then have = "|cffff6060" .. have .. "|r" end
        side.summary:SetText(L["%d to learn, %s in all. You have %s"]:format(#available, MoneyText(totalCost), have))
    else
        side.summary:SetText(L["Nothing to learn from your trainer right now."])
    end
    local count = SideRowCount()
    local maxScroll = math.max(0, #sideItems - count)
    if sideScroll > maxScroll then sideScroll = maxScroll end
    if sideScroll < 0 then sideScroll = 0 end
    local level = MyLevel()
    for i, row in ipairs(side.rows) do
        local item = i <= count and sideItems[i + sideScroll] or nil
        row.entry = nil
        if not item then
            row:Hide()
        elseif item.header then
            row.icon:Hide()
            row.mark:SetShown(item.current == true)
            row.line:Show()
            row.right:SetText("")
            row.name:SetText((item.current and "|cffffd100" or "|cffc8a050") .. item.header .. "|r")
            row:Show()
        elseif item.note then
            row.icon:Hide()
            row.mark:Hide()
            row.line:Hide()
            row.right:SetText("")
            row.name:SetText("|cff888888" .. item.note .. "|r")
            row:Show()
        else
            local entry = item.entry
            row.entry = entry
            row.mark:Hide()
            row.line:Hide()
            row.icon:SetTexture(SpellIcon(entry.id))
            row.icon:SetDesaturated(not item.ready)
            row.icon:Show()
            local rank = SpellRank(entry.id)
            local colour = item.ready and (entry.isNew and "|cff40ff40" or "|cffffffff") or "|cffaaaaaa"
            row.name:SetText(colour .. entry.name .. "|r" .. (rank and ("  |cff888888" .. rank .. "|r") or ""))
            if not item.ready then
                row.right:SetText("|cffff8040" .. L["level %d"]:format(entry.level) .. "|r")
            elseif entry.quest then
                row.right:SetText("|cffffd100" .. L["class quest"] .. "|r")
            elseif entry.cost > money then
                row.right:SetText("|cffff6060" .. MoneyText(entry.cost) .. "|r")
            else
                row.right:SetText(MoneyText(entry.cost))
            end
            row:Show()
        end
    end
end

local function BuildSide()
    local f = CreateFrame("Frame", "OxedHubTrainingReminderSpellbook", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    side = f
    f:Hide()
    f:SetSize(SIDE_W, 480)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    OrnateShell(f, L["Training Reminder"])
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetScale(0.8)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        sideClosed = true
        f:Hide()
    end)

    f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.summary:SetPoint("TOPLEFT", 14, -28)
    f.summary:SetPoint("TOPRIGHT", -14, -28)
    f.summary:SetJustifyH("LEFT")

    local function Wheel(_, delta)
        sideScroll = sideScroll - delta * 3
        DrawSide()
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", Wheel)

    f.rows = {}
    for i = 1, 40 do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(SIDE_ROW - 2)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 10, SIDE_TOP - (i - 1) * SIDE_ROW)
        row:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, SIDE_TOP - (i - 1) * SIDE_ROW)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", Wheel)
        local shine = row:CreateTexture(nil, "HIGHLIGHT")
        shine:SetAllPoints()
        shine:SetColorTexture(1, 1, 1, 0.06)
        -- The open page's name gets a soft light band.
        row.mark = row:CreateTexture(nil, "BACKGROUND")
        row.mark:SetAllPoints()
        row.mark:SetColorTexture(1, 1, 1, 0.07)
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetColorTexture(1, 1, 1, 0.12)
        row.line:SetHeight(1)
        row.line:SetPoint("BOTTOMLEFT", 2, 1)
        row.line:SetPoint("BOTTOMRIGHT", -2, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(20, 20)
        row.icon:SetPoint("LEFT", 2, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.right:SetPoint("RIGHT", -2, 0)
        row.right:SetJustifyH("RIGHT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 28, 0)
        row.name:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row.name:SetJustifyH("LEFT")
        if row.name.SetWordWrap then row.name:SetWordWrap(false) end
        row:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" and self.entry then
                settings.ignored[self.entry.id] = (not settings.ignored[self.entry.id]) or nil
                Rescan()
            else
                ShowWindow()
            end
        end)
        row:SetScript("OnEnter", function(self)
            if self.entry then RowTooltip(self) end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        f.rows[i] = row
    end

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 12)
    hint:SetPoint("BOTTOMRIGHT", -14, 12)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Click: the full list. Right-click a spell: ignore it."])
end

-- Checked a few times a second while the module runs; the work is done only
-- while the spellbook is open.
sideWatcher:SetScript("OnUpdate", function(_, elapsed)
    sideCheck = sideCheck - (elapsed or 0)
    if sideCheck > 0 then return end
    sideCheck = 0.15
    local frame, book
    if running and settings and settings.spellbookPanel then frame, book = OpenSpellbook() end
    if not book then
        sideClosed = false
        if side and side:IsShown() then side:Hide() end
        return
    end
    if sideClosed then return end
    local opening = not (side and side:IsShown())
    if not side then BuildSide() end
    if opening then Scan() end

    -- Beside the spellbook window, or on its left when the right is too tight.
    local left, bottom, width, height = frame:GetRect()
    if not (left and bottom and width and height) then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    left, bottom, width, height = left * scale, bottom * scale, width * scale, height * scale
    local top, right = bottom + height, left + width
    local onRight = right + SIDE_W + 4 <= UIParent:GetWidth()
    local h = math.max(260, math.min(height, 640))
    if side.at ~= (onRight and "R" or "L") or side.x ~= left or side.y ~= top or side.h ~= h or side.w ~= width then
        side.at, side.x, side.y, side.h, side.w = onRight and "R" or "L", left, top, h, width
        side:ClearAllPoints()
        if onRight then
            side:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + 4, top)
        else
            side:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - 4, top)
        end
        side:SetHeight(h)
        sideDrawn.scan = nil
    end
    side:SetFrameStrata(frame:GetFrameStrata())
    side:SetFrameLevel(frame:GetFrameLevel() + 20)

    -- Rebuilt when the page or the lists changed.
    local icon, tab = OpenTabIcon(book)
    if opening or sideDrawn.scan ~= scanCount or sideDrawn.tab ~= tab or sideDrawn.icon ~= icon then
        if opening or sideDrawn.tab ~= tab then sideScroll = 0 end
        sideDrawn.scan, sideDrawn.tab, sideDrawn.icon = scanCount, tab, icon
        BuildSideItems(book)
        DrawSide()
    end
    if opening then side:Show() end
end)

StartSpellbookPanel = function()
    sideCheck = 0
    sideWatcher:Show()
end

-- off: the module is switched off, so stop looking too.
HideSpellbookPanel = function(off)
    if off then sideWatcher:Hide() end
    if side then side:Hide() end
    sideDrawn.scan = nil
end

-- ── Train All, at the class trainer ─────────────────────────────────────────
-- Never parented to, anchored to or changing the game's trainer window: the
-- button sits on UIParent where the window's own Train button is.

local trainButton, trainConfirm
local trainBusy = false
local trainCheck = 0
local trainWatcher = CreateFrame("Frame")
trainWatcher:Hide()

local function NativeTrainButton()
    local frame = ClassTrainerFrame
    return (frame and frame.TrainButton) or ClassTrainerTrainButton
end

local function AtClassTrainer()
    if not (running and settings and settings.trainAll) then return false end
    if InCombatLockdown() then return false end
    local frame = ClassTrainerFrame
    if not (frame and frame:IsVisible()) then return false end
    -- Older clients answer 1 or nil here, newer ones true or false.
    local tradeskill = Call(IsTradeskillTrainer)
    if IsSecret(tradeskill) or tradeskill then return false end
    if C_Trainer and C_Trainer.GetTrainerType and Enum and Enum.TrainerType and Enum.TrainerType.General then
        if Call(C_Trainer.GetTrainerType) ~= Enum.TrainerType.General then return false end
    end
    return true
end

-- What the trainer would teach now, minus the ignore list: { index, id, cost }.
local function TrainerServices()
    local list, cost, skipped = {}, 0, 0
    local count = Call(GetNumTrainerServices)
    if type(count) ~= "number" or IsSecret(count) then return list, 0, 0 end
    local step = Call(GetTrainerServiceStepIndex)
    for index = 1, count do
        local name, status = Call(GetTrainerServiceInfo, index)
        if name and status == "available" and index ~= step then
            local data = Call(C_TooltipInfo and C_TooltipInfo.GetTrainerService, index)
            local id = type(data) == "table" and data.id or nil
            if type(id) == "number" and not IsSecret(id) then
                if settings.ignored[id] then
                    skipped = skipped + 1
                else
                    local price, isProfession = Call(GetTrainerServiceCost, index)
                    -- A profession needs the game's own slot check and popup.
                    if type(price) == "number" and not IsSecret(price) and not isProfession then
                        list[#list + 1] = { index = index, id = id, cost = price }
                        cost = cost + price
                    end
                end
            end
        end
    end
    return list, cost, skipped
end

local function BuyAll(quoted)
    if trainBusy or not quoted or not AtClassTrainer() then return end
    local list, cost = TrainerServices()
    if #list == 0 or Money() < cost then return end
    -- Never buy a different batch from the one the player said yes to.
    local same = #list == #quoted
    for i, service in ipairs(list) do
        local q = quoted[i]
        if not q or q.id ~= service.id or q.index ~= service.index or q.cost ~= service.cost then same = false end
    end
    if not same then
        Say(L["The trainer's list changed. Press Train All again."])
        return
    end
    trainBusy = true
    local before = Money()
    -- From the bottom up: a learned row can leave the list at once.
    for i = #list, 1, -1 do pcall(BuyTrainerService, list[i].index) end
    C_Timer.After(3, function()
        trainBusy = false
        local learned = 0
        for _, service in ipairs(list) do
            if Known(service.id) or KnownOrHigher(service.id) then learned = learned + 1 end
        end
        local spent = math.max(0, before - Money())
        if learned > 0 or spent > 0 then
            Say(L["Learned %d at the trainer for %s."]:format(learned, MoneyText(spent)))
        end
        QueueRescan()
    end)
end

local function BuildTrainConfirm()
    local f = CreateFrame("Frame", "OxedHubTrainingReminderConfirm", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    trainConfirm = f
    f:Hide()
    f:SetSize(330, 110)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    OrnateShell(f, L["Train All"])
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOP", 0, -26)
    f.text:SetWidth(296)
    f.text:SetSpacing(2)
    local yes = TabButton(f, 120, L["Train"])
    yes:SetActive(true)
    yes:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16)
    yes:SetScript("OnClick", function()
        local quoted = f.quoted
        f:Hide()
        BuyAll(quoted)
    end)
    local no = TabButton(f, 120, L["Cancel"])
    no:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16)
    no:SetScript("OnClick", function() f:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "OxedHubTrainingReminderConfirm") end
end

local function TrainTooltip(self)
    local list, cost, skipped = TrainerServices()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local money = MoneyText(cost)
    if Money() < cost then money = "|cffff6060" .. money .. "|r" end
    GameTooltip:SetText(L["Train %d for %s"]:format(#list, money))
    if skipped > 0 then
        GameTooltip:AddLine(L["%d on your ignore list are skipped"]:format(skipped), 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(L["Spells on the ignore list of /oxtrain are skipped."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function BuildTrainButton()
    local b = CreateFrame("Button", "OxedHubTrainingReminderTrainAll", UIParent, "UIPanelButtonTemplate")
    trainButton = b
    b:Hide()
    -- The trainer's list sits on HIGH.
    b:SetFrameStrata("DIALOG")
    b:SetSize(90, 22)
    b:SetText(L["Train All"])
    if b.SetMotionScriptsWhileDisabled then b:SetMotionScriptsWhileDisabled(true) end
    b:SetScript("OnClick", function(self)
        local list, cost = TrainerServices()
        if #list == 0 or trainBusy then return end
        if Money() < cost then
            Say(L["Not enough money to train them all."])
            return
        end
        if not trainConfirm then BuildTrainConfirm() end
        trainConfirm.quoted = list
        trainConfirm.text:SetText(L["Learn all %d for %s? Spells you ignore are skipped."]:format(#list, MoneyText(cost)))
        trainConfirm:Show()
        GameTooltip:Hide()
    end)
    b:SetScript("OnEnter", TrainTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnHide", function()
        if trainConfirm then trainConfirm:Hide() end
    end)
end

local function HideTrainAll()
    trainWatcher:Hide()
    if trainButton then trainButton:Hide() end
    if trainConfirm then trainConfirm:Hide() end
end

-- Runs only while a trainer window is open (TRAINER_SHOW to TRAINER_CLOSED).
trainWatcher:SetScript("OnUpdate", function(_, elapsed)
    if not AtClassTrainer() then
        if trainButton then trainButton:Hide() end
        return
    end
    local native = NativeTrainButton()
    local left, bottom, height
    if native and native.GetRect then
        local _, _, _, h = native:GetRect()
        left, bottom = native:GetLeft(), native:GetBottom()
        height = h
    end
    if not (left and bottom and height) then
        if trainButton then trainButton:Hide() end
        return
    end
    if not trainButton then BuildTrainButton() end
    local b = trainButton
    local scale = native:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if b.x ~= left or b.y ~= bottom or b.h ~= height or b.s ~= scale then
        b.x, b.y, b.h, b.s = left, bottom, height, scale
        b:SetScale(scale)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left - 6, bottom + height / 2)
    end
    trainCheck = trainCheck - (elapsed or 0)
    if trainCheck <= 0 or not b:IsShown() then
        trainCheck = 0.3
        local list, cost = TrainerServices()
        b:SetEnabled(not trainBusy and #list > 0 and Money() >= cost)
    end
    if not b:IsShown() then b:Show() end
end)

-- ── Events ──────────────────────────────────────────────────────────────────

local EVENTS = {
    "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "PLAYER_UPDATE_RESTING", "PLAYER_REGEN_ENABLED",
    "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_CLOSED", "PLAYER_MONEY", "CHARACTER_POINTS_CHANGED",
    "SKILL_LINES_CHANGED", "QUEST_TURNED_IN", "TRAINER_SHOW", "TRAINER_UPDATE", "UPDATE_FACTION",
}
-- Only for the classes with a pet book to follow.
local PET_EVENTS = { "CHAT_MSG_SYSTEM", "UNIT_PET", "PET_BAR_UPDATE" }

events:SetScript("OnEvent", function(_, event, arg1)
    if not running then return end
    if event == "PLAYER_LEVEL_UP" then
        -- The new level arrives with the event, before UnitLevel has it.
        if type(arg1) == "number" and not IsSecret(arg1) then lastLevel = arg1 end
        C_Timer.After(SETTLE, function() Remind("level") end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(LOGIN_DELAY, function()
            -- Only once per session: a loading screen is not a reason.
            if not loginChecked then
                loginChecked = true
                Remind("login")
            end
        end)
    elseif event == "PLAYER_UPDATE_RESTING" then
        local resting = Call(IsResting)
        -- Resting flips at every city edge and inn door, so the city reminder
        -- waits as long as the timer does (at least CITY_GAP) since the last
        -- one, counted across reloads and logins.
        local minutes = tonumber(settings.remindMinutes) or 0
        local gap = math.max(minutes * 60, CITY_GAP)
        if settings.remindCity and resting and not IsSecret(resting)
            and not (card and card:IsShown())
            and SinceLastReminder() >= gap then
            Remind("city")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingReason then
            local reason = pendingReason
            pendingReason = nil
            Remind(reason)
        end
    elseif event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        if event == "TRAINER_SHOW" and settings.trainAll then
            trainCheck = 0
            trainWatcher:Show()
        end
        if ReadPetTrainer() then QueueRescan() end
    elseif event == "TRAINER_CLOSED" then
        HideTrainAll()
        QueueRescan()
    elseif event == "CHAT_MSG_SYSTEM" then
        if ReadLearnLine(arg1) then QueueRescan() end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then QueueRescan() end
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
        w:AddCheckbox(settings, "remindPets", "Remind me about pet abilities too (hunter)", nil, Rescan)
        w:AddCheckbox(settings, "remindTomes", "Remind me about demon tomes too (warlock)", nil, Rescan)
        w:AddCheckbox(settings, "spellbookPanel", "Show what to learn beside the spellbook", nil, function(on)
            if not on then HideSpellbookPanel() end
        end)
        w:AddCheckbox(settings, "trainAll", "Train All button at the class trainer", nil, function(on)
            if not on then HideTrainAll() end
        end)
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
        w:AddNote("The reminder comes when you level up, when you log in, and again later while something is still unlearned. Right-click a spell in the list to stop the reminders about it. Spells from class quests are in the list too. Weapon skills, pet abilities and demon tomes are listed, and join the reminder only if you tick them. A hunter opens Beast Training once so the list knows what the pet has; a warlock's demon shows what it has read while it is out. Prices include the reputation discount. Train All asks before it buys and skips the spells you ignore.")
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
    if type(config.petLearned) ~= "table" then config.petLearned = {} end
    settings = config

    Data = OxedHub.TrainingReminderData
    if Data and type(Data.spellsByLevel) ~= "table" then Data = nil end
    BuildRanks()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "trainingreminder",
        name     = "Training Reminder",
        version  = "1.3.5",
        updated  = 20261112.7,
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
            if Data and (Data.petAbilityIds or Data.tomesByLevel) then
                for _, event in ipairs(PET_EVENTS) do pcall(events.RegisterEvent, events, event) end
            end
            StartSpellbookPanel()
            -- Switched on by hand in the middle of a session: look soon, once
            -- the spellbook is sure to be there.
            C_Timer.After(LOGIN_DELAY, function()
                if running and not loginChecked then
                    loginChecked = true
                    Remind("login")
                end
            end)
            if not ticker and C_Timer.NewTicker then
                ticker = C_Timer.NewTicker(60, function()
                    local minutes = tonumber(settings.remindMinutes) or 0
                    if minutes <= 0 or not loginChecked then return end
                    if card and card:IsShown() then return end
                    if SinceLastReminder() >= minutes * 60 then Remind("timer") end
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
            HideTrainAll()
            HideSpellbookPanel(true)
            HideCard()
            if window then window:Hide() end
        end,
    })
end)
