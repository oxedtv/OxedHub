-- ============================================================================
-- Attributes (built-in OxedHub module)
-- Adds the numbers the character sheet leaves out: how fast you are actually
-- moving, and the stats the default panel never prints -- leech, avoidance,
-- stagger, and what your armour really takes off a hit.
--
-- It lives as its own tab beside Character, Reputation and Currency. Squeezing
-- the lines in under Blizzard's own ran out of room the moment a character had
-- a few stats to show; a tab has the whole window, so the numbers can be
-- grouped and read instead of counted into whatever space was left.
--
-- Nothing of Blizzard's is moved or replaced. The tab shows its own frame and
-- steps aside the moment another tab is picked.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled   = false,  -- off until the player switches it on (see ModuleAPI:Register)
    primary   = true,   -- the stat your spec scales with, and stamina
    speed     = true,   -- movement speed, live
    hidden    = true,   -- leech, avoidance, speed rating
    defense   = true,   -- dodge, parry, block, armour reduction
    offense   = true,   -- crit, haste, mastery, versatility with ratings
    ratings   = true,   -- the rating next to each percentage
    vehicle   = true,   -- read the vehicle's speed while in one
}

local settings          -- OxedHubDB.modules.attributes, bound at login
local panel             -- our page inside the character window
local tab               -- the button that opens it
local lines = {}        -- reusable line frames, header or value
local hooked = false
local optionsWindow

local UPDATE_INTERVAL = 0.1   -- the speed line only; the rest moves on events

local HEADER_COLOR = { 1, 0.82, 0 }

-- The frames the other tabs show. Ours hides whenever one of these appears.
local SUBFRAMES = { "PaperDollFrame", "ReputationFrame", "TokenFrame" }

-- ── Reading the stats ───────────────────────────────────────────────────────
-- Every reader returns: value text, label, tooltip body.
-- A reader returning nil means "this character has nothing to show here", and
-- the line is skipped rather than printed as a zero.

local function Percent(value)
    return ("%.2f%%"):format(value or 0)
end

-- The rating in brackets, when the player asked for ratings and there is one.
local function WithRating(text, ratingId)
    if not settings.ratings or not ratingId or not GetCombatRating then return text end
    local rating = GetCombatRating(ratingId)
    if not rating or rating <= 0 then return text end
    return ("%s |cff808080(%d)|r"):format(text, rating)
end

-- Which unit's speed matters right now. In a vehicle the player's own speed is
-- whatever the vehicle grants, so the vehicle is the honest answer.
local function SpeedUnit()
    if settings.vehicle and UnitInVehicle and UnitInVehicle("player")
        and UnitControllingVehicle and UnitControllingVehicle("player") then
        return "vehicle", true
    end
    return "player", false
end

local function ReadSpeed()
    if not GetUnitSpeed then return nil end
    local unit, inVehicle = SpeedUnit()
    local current = GetUnitSpeed(unit) or 0
    local base = BASE_MOVEMENT_SPEED or 7
    local percent = current / base * 100

    local text = ("%.0f%%"):format(percent)
    if inVehicle then text = text .. " |cff808080(vehicle)|r" end

    return text, STAT_MOVEMENT_SPEED or "Movement Speed",
        ("Current: %.1f yards per second.\nStanding still reads 0%%."):format(current)
end

local function ReadSpeedRating()
    if not GetSpeed then return nil end
    local bonus = GetSpeed()
    if not bonus or bonus <= 0 then return nil end
    return WithRating(Percent(bonus), CR_SPEED), STAT_SPEED or "Speed",
        "Passive movement speed from the Speed secondary stat, on top of your normal run speed."
end

local function ReadLeech()
    if not GetLifesteal then return nil end
    local value = GetLifesteal()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_LIFESTEAL), STAT_LIFESTEAL or "Leech",
        "Part of the damage and healing you do comes back to you as healing."
end

local function ReadAvoidance()
    if not GetAvoidance then return nil end
    local value = GetAvoidance()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_AVOIDANCE), STAT_AVOIDANCE or "Avoidance",
        "Reduces the damage area effects do to you."
end

-- ── The primary attributes ──────────────────────────────────────────────────

local STAT_STRENGTH, STAT_AGILITY, STAT_STAMINA, STAT_INTELLECT = 1, 2, 3, 4

-- Which of the four the specialisation actually scales with. Asked of the
-- specialisation rather than guessed from the class: a druid's answer changes
-- with the spec, not with the class.
local function PrimaryStatIndex()
    local spec = GetSpecialization and GetSpecialization()
    if spec and spec > 0 and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local _, _, primary = select(4, C_SpecializationInfo.GetSpecializationInfo(spec))
        if primary then return primary end
    end

    -- No specialisation yet (a low level character): the biggest of the three
    -- is the one being stacked.
    local best, bestValue
    for _, index in ipairs({ STAT_STRENGTH, STAT_AGILITY, STAT_INTELLECT }) do
        local value = select(2, UnitStat("player", index))
        if value and (not bestValue or value > bestValue) then best, bestValue = index, value end
    end
    return best
end

local function StatName(index)
    return _G["SPELL_STAT" .. index .. "_NAME"] or "Attribute"
end

local function ReadPrimaryStat()
    if not UnitStat then return nil end
    local index = PrimaryStatIndex()
    if not index then return nil end

    local effective, _, positive, negative = select(2, UnitStat("player", index))
    if not effective then return nil end

    local body
    if (positive and positive > 0) or (negative and negative < 0) then
        body = ("Base: %d\nFrom gear and effects: %+d"):format(
            effective - (positive or 0) - (negative or 0), (positive or 0) + (negative or 0))
    end
    return tostring(effective), StatName(index), body
end

local function ReadStamina()
    if not UnitStat then return nil end
    local effective = select(2, UnitStat("player", STAT_STAMINA))
    if not effective then return nil end
    return tostring(effective), StatName(STAT_STAMINA),
        ("Health: %d"):format(UnitHealthMax and UnitHealthMax("player") or 0)
end

-- The lowest crit of the spell schools. A school left behind is the one that
-- decides whether a spell crits, so the smallest is the honest figure.
local function MinSpellCrit()
    if not GetSpellCritChance then return 0 end
    local lowest = GetSpellCritChance(2) or 0
    for school = 3, (MAX_SPELL_SCHOOLS or 7) do
        local value = GetSpellCritChance(school)
        if value then lowest = math.min(lowest, value) end
    end
    return lowest
end

-- Crit comes in three kinds and a character only cares about the one their
-- attacks use. The largest is the one their gear is rated for, which is how
-- the character sheet picks it too.
local function ReadCrit()
    if not GetCritChance then return nil end
    local melee = GetCritChance() or 0
    local ranged = (GetRangedCritChance and GetRangedCritChance()) or 0
    local spell = MinSpellCrit()

    local value, ratingId
    if spell >= ranged and spell >= melee then
        value, ratingId = spell, CR_CRIT_SPELL
    elseif ranged >= melee then
        value, ratingId = ranged, CR_CRIT_RANGED
    else
        value, ratingId = melee, CR_CRIT_MELEE
    end

    return WithRating(Percent(value), ratingId),
        STAT_CRITICAL_STRIKE or "Critical Strike",
        ("Melee: %s\nRanged: %s\nSpell: %s"):format(Percent(melee), Percent(ranged), Percent(spell))
end

local function ReadHaste()
    if not GetHaste then return nil end
    return WithRating(Percent(GetHaste()), CR_HASTE_MELEE), STAT_HASTE or "Haste", nil
end

local function ReadMastery()
    if not GetMasteryEffect then return nil end
    local value = GetMasteryEffect()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_MASTERY), STAT_MASTERY or "Mastery", nil
end

-- Versatility is two numbers wearing one name: what it adds to the damage you
-- deal, and what it takes off the damage you take. The sheet prints the first.
local function ReadVersatility()
    if not (GetCombatRatingBonus and GetVersatilityBonus and CR_VERSATILITY_DAMAGE_DONE) then
        return nil
    end
    local done = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
        + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
    local taken = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN)
        + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)

    return WithRating(Percent(done), CR_VERSATILITY_DAMAGE_DONE),
        STAT_VERSATILITY or "Versatility",
        ("Damage done: %s\nDamage taken: %s"):format(Percent(done), Percent(taken))
end

local function ReadDodge()
    if not GetDodgeChance then return nil end
    return WithRating(Percent(GetDodgeChance()), CR_DODGE), DODGE_CHANCE or "Dodge", nil
end

local function ReadParry()
    if not GetParryChance then return nil end
    local value = GetParryChance()
    -- Classes that cannot parry read a flat zero; printing it says nothing.
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_PARRY), PARRY_CHANCE or "Parry", nil
end

local function ReadBlock()
    if not GetBlockChance then return nil end
    local value = GetBlockChance()
    if not value or value <= 0 then return nil end

    local body
    if GetShieldBlock then
        local amount = GetShieldBlock()
        if amount and amount > 0 then
            body = ("A blocked hit is reduced by %d."):format(amount)
        end
    end
    return WithRating(Percent(value), CR_BLOCK), BLOCK_CHANCE or "Block", body
end

-- Monks only: the share of a hit that is delayed instead of taken at once.
local function ReadStagger()
    if not (C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage) then return nil end
    local stagger, againstTarget = C_PaperDollInfo.GetStaggerPercentage("player")
    if not stagger or stagger <= 0 then return nil end

    local body
    if againstTarget and againstTarget ~= stagger then
        body = ("Against your current target: %s"):format(Percent(againstTarget))
    end
    return Percent(stagger), STAT_STAGGER or "Stagger", body
end

local function ReadArmor()
    if not UnitArmor then return nil end
    local effective = select(2, UnitArmor("player"))
    if not effective or effective <= 0 then return nil end
    return tostring(effective), ARMOR or "Armor", nil
end

-- What the armour is actually worth, which the sheet only shows on hover.
local function ReadArmorReduction()
    if not (UnitArmor and PaperDollFrame_GetArmorReduction) then return nil end
    local effective = select(2, UnitArmor("player"))
    if not effective or effective <= 0 then return nil end

    local level = (UnitEffectiveLevel and UnitEffectiveLevel("player")) or UnitLevel("player")
    local reduction = PaperDollFrame_GetArmorReduction(effective, level)
    if not reduction then return nil end

    local body
    if PaperDollFrame_GetArmorReductionAgainstTarget then
        local vsTarget = PaperDollFrame_GetArmorReductionAgainstTarget(effective)
        if vsTarget then
            body = ("Against your current target: %s"):format(Percent(vsTarget))
        end
    end
    return Percent(reduction), "Damage reduction", body
end

-- What is printed, in order. A header only appears when a line under it does.
local ROWS = {
    { group = "primary", header = STAT_CATEGORY_ATTRIBUTES or "Attributes" },
    { group = "primary", read = ReadPrimaryStat },
    { group = "primary", read = ReadStamina },

    { group = "speed",   header = "Movement" },
    { group = "speed",   read = ReadSpeed, live = true },
    { group = "speed",   read = ReadSpeedRating },

    { group = "offense", header = "Offense" },
    { group = "offense", read = ReadCrit },
    { group = "offense", read = ReadHaste },
    { group = "offense", read = ReadMastery },
    { group = "offense", read = ReadVersatility },

    { group = "hidden",  header = "Hidden stats" },
    { group = "hidden",  read = ReadLeech },
    { group = "hidden",  read = ReadAvoidance },

    { group = "defense", header = "Defense" },
    { group = "defense", read = ReadArmor },
    { group = "defense", read = ReadArmorReduction },
    { group = "defense", read = ReadDodge },
    { group = "defense", read = ReadParry },
    { group = "defense", read = ReadBlock },
    { group = "defense", read = ReadStagger },
}

-- ── The lines ───────────────────────────────────────────────────────────────

local function GetLine(index, parent)
    local line = lines[index]
    if line then return line end

    line = CreateFrame("Frame", nil, parent)
    line:SetHeight(18)

    line.label = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.label:SetPoint("LEFT", line, "LEFT", 10, 0)
    line.label:SetJustifyH("LEFT")

    line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.value:SetPoint("RIGHT", line, "RIGHT", -14, 0)
    line.value:SetJustifyH("RIGHT")

    line:EnableMouse(true)
    line:SetScript("OnEnter", function(self)
        if not self.tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle)
        if self.tipBody then GameTooltip:AddLine(self.tipBody, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)

    lines[index] = line
    return line
end

local function SetHeaderLine(line, text)
    line.label:SetFontObject("GameFontNormal")
    line.label:SetTextColor(unpack(HEADER_COLOR))
    line.label:SetText(text)
    line.value:SetText("")
    line.tipTitle, line.tipBody = nil, nil
end

local function SetValueLine(line, label, value, body)
    line.label:SetFontObject("GameFontHighlight")
    line.label:SetTextColor(0.8, 0.8, 0.8)
    line.label:SetText(label)
    line.value:SetText(value)
    line.tipTitle, line.tipBody = label, body
end

-- Redraws every line. Called when the tab opens and whenever the game says a
-- stat changed -- not on the timer, which touches the speed line alone.
local function Refresh()
    if not (panel and panel:IsShown()) then return end

    local content = panel.content
    local shown, y = 0, 0
    local pendingHeader        -- drawn only once a value under it appears

    for _, row in ipairs(ROWS) do
        if settings[row.group] ~= false then
            if row.header then
                pendingHeader = row.header
            else
                local value, label, body = row.read()
                if value then
                    if pendingHeader then
                        shown = shown + 1
                        local header = GetLine(shown, content)
                        SetHeaderLine(header, pendingHeader)
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 6)
                        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y - 6)
                        header:Show()
                        y = y + 24
                        pendingHeader = nil
                    end

                    shown = shown + 1
                    local line = GetLine(shown, content)
                    SetValueLine(line, label, value, body)
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    line:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                    line:Show()
                    y = y + 18
                end
            end
        end
    end

    for index = shown + 1, #lines do
        lines[index]:Hide()
    end

    content:SetHeight(math.max(1, y))

    -- A page that shrank below where it was scrolled to would otherwise sit
    -- past its own end, showing nothing.
    local limit = math.max(0, y - panel.scroll:GetHeight())
    if panel.scroll:GetVerticalScroll() > limit then
        panel.scroll:SetVerticalScroll(limit)
    end
end

-- Only the speed line changes between events, so the timer redraws that one
-- alone. Reading every stat ten times a second would cost far more than the
-- one number that actually moves.
local function RefreshSpeedOnly()
    if not (settings and settings.speed and panel and panel:IsShown()) then return end
    for _, line in ipairs(lines) do
        if line:IsShown() and line.tipTitle == (STAT_MOVEMENT_SPEED or "Movement Speed") then
            local value, _, body = ReadSpeed()
            if value then
                line.value:SetText(value)
                line.tipBody = body
            end
            return
        end
    end
end

-- ── The page ────────────────────────────────────────────────────────────────

local function HideBlizzardSubframes()
    for _, name in ipairs(SUBFRAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then frame:Hide() end
    end
end

local function BuildPanel()
    if panel then return panel end
    if not CharacterFrame then return nil end

    panel = CreateFrame("Frame", "OxedHubAttributesPanel", CharacterFrame)
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 14, -70)
    panel:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -36, 36)
    panel:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    -- The wheel moves the page, and only as far as there is page to move.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, direction)
        local limit = math.max(0, (content:GetHeight() or 0) - self:GetHeight())
        local position = self:GetVerticalScroll() - direction * 20
        self:SetVerticalScroll(math.max(0, math.min(limit, position)))
    end)

    panel.scroll, panel.content = scroll, content

    panel:SetScript("OnShow", function()
        content:SetWidth(scroll:GetWidth())
        Refresh()
    end)

    return panel
end

-- ── The tab ─────────────────────────────────────────────────────────────────

-- The last tab the game itself put on the window. Counted rather than assumed
-- to be three: another addon may already have added one, and sitting on top of
-- it would hide whatever it opens.
local function LastTab()
    local last, index = nil, 1
    while true do
        local button = _G["CharacterFrameTab" .. index]
        if not button then break end
        if button ~= tab then last = button end
        index = index + 1
    end
    return last
end

local function SelectOurTab()
    HideBlizzardSubframes()
    if PanelTemplates_DeselectTab then
        local index = 1
        while _G["CharacterFrameTab" .. index] do
            local button = _G["CharacterFrameTab" .. index]
            if button ~= tab then pcall(PanelTemplates_DeselectTab, button) end
            index = index + 1
        end
    end
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    BuildPanel()
    if panel then panel:Show() end
end

-- Any other tab takes the window back: its frame appearing is the signal, so
-- this works for Blizzard's tabs and for a tab another addon added alike.
local function StandDown()
    if panel then panel:Hide() end
    if tab and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
end

-- The name of the tab template has moved between builds, and asking for one
-- that is not there is an error rather than a nil. So each candidate is tried
-- until one takes, and a plain button is the answer if none of them do: a tab
-- that looks slightly wrong still opens the page, an error opens nothing.
local TAB_TEMPLATES = {
    "PanelTabButtonTemplate",
    "CharacterFrameTabButtonTemplate",
    "CharacterFrameTabTemplate",
    "PanelTopTabButtonTemplate",
    "TabButtonTemplate",
}

local function CreateTabButton()
    for _, template in ipairs(TAB_TEMPLATES) do
        local ok, button = pcall(CreateFrame, "Button", "OxedHubAttributesTab",
            CharacterFrame, template)
        if ok and button then return button end
    end
    local ok, button = pcall(CreateFrame, "Button", "OxedHubAttributesTab",
        CharacterFrame, "UIPanelButtonTemplate")
    if ok and button then
        button:SetSize(90, 22)
        return button
    end
    return nil
end

local function BuildTab()
    if tab or not CharacterFrame then return end

    local anchor = LastTab()
    if not anchor then return end   -- tabs not built yet

    tab = CreateTabButton()
    if not tab then return end
    tab:SetText(STAT_CATEGORY_ATTRIBUTES or "Attributes")
    -- The tab is built as soon as the character window exists, which can be
    -- before settings are read. It starts hidden and OnEnable shows it, so a
    -- module that is off never puts a tab on the window.
    if not (settings and settings.enabled == true) then tab:Hide() end
    -- Blizzard's own tabs overlap by about 16px, which is what their artwork is
    -- cut for. Ours is a separate tab rather than one more of the same strip, so
    -- it stands clear instead of sitting on top of Currency.
    tab:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    tab:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        SelectOurTab()
    end)

    for _, name in ipairs(SUBFRAMES) do
        local frame = _G[name]
        if frame then frame:HookScript("OnShow", StandDown) end
    end

    CharacterFrame:HookScript("OnHide", StandDown)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local watcher = CreateFrame("Frame")

local STAT_EVENTS = {
    "UNIT_STATS", "UNIT_AURA", "COMBAT_RATING_UPDATE", "MASTERY_UPDATE",
    "SPEED_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TARGET_CHANGED",
}

local function InstallHook()
    if hooked then return end
    if not (CharacterFrame and _G.CharacterFrameTab1) then return end
    hooked = true

    BuildTab()

    for _, event in ipairs(STAT_EVENTS) do
        pcall(watcher.RegisterUnitEvent, watcher, event, "player")
    end
    watcher:SetScript("OnEvent", Refresh)

    watcher.elapsed = 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < UPDATE_INTERVAL then return end
        self.elapsed = 0
        RefreshSpeedOnly()
    end)
end

-- The character frame is loaded on demand, so the tab waits for it.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon == "Blizzard_CharacterUI" or _G.CharacterFrameTab1 then
        InstallHook()
        if hooked then
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end
end)

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.attributes
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.attributes = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Attributes", 400, 280)
        optionsWindow:AddCheckbox(settings, "primary", "Attributes",
            "Your specialisation's main stat and stamina.", Refresh)
        optionsWindow:AddCheckbox(settings, "speed", "Movement",
            "A live reading of how fast you are moving, plus the Speed stat.", Refresh)
        optionsWindow:AddCheckbox(settings, "offense", "Offense",
            "Crit, haste, mastery and versatility, each with its rating.", Refresh)
        optionsWindow:AddCheckbox(settings, "hidden", "Hidden stats",
            "Leech and avoidance -- the ones the sheet never prints.", Refresh)
        optionsWindow:AddCheckbox(settings, "defense", "Defense",
            "Armour and what it actually takes off a hit, dodge, parry, block, stagger.", Refresh)
        optionsWindow:AddCheckbox(settings, "ratings", "Show ratings",
            "Print the rating in grey next to each percentage.", Refresh)
        optionsWindow:AddCheckbox(settings, "vehicle", "Read vehicle speed",
            "While you are driving something, show its speed instead of your own.", Refresh)
        optionsWindow:AddNote("Everything appears on the Attributes tab of your character window.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    InstallHook()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "attributes",
        name     = "Attributes",
        version  = "1.1.0",
        author   = "Oxed",
        category = "character",
        desc     = "A character window tab with live move speed and hidden stats like leech and stagger.",
        icon     = "Interface\\Icons\\Spell_Holy_WordFortitude",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            InstallHook()
            if tab then tab:Show() end
        end,

        OnDisable = function()
            StandDown()
            if tab then tab:Hide() end
        end,
    })
end)
