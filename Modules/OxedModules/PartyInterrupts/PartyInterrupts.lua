-- ============================================================================
-- Party Interrupts (built-in OxedHub module)
-- Two things in one small list, for dungeons:
--
--   * Your interrupt: always on top, filling as it comes off cooldown.
--   * Every interrupt your group lands: who did it and on what, as a bar
--     that fades out over the next RECORD seconds, newest first, so the
--     group can see at a glance who just used theirs.
--
-- ⚠ Who interrupted (a GUID), their name, their class and the spell they
-- stopped are secret values in a fight. They go straight to SetText,
-- SetTexture and the colour setters inside pcall, never into an "if" or a
-- comparison. Your own interrupt's cooldown comes back as a duration object
-- the bar fills itself from.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on
    showOwn     = true,
    showParty   = true,
    onlyDungeons = true,
    classColour = true,
    record      = 15,      -- seconds a party interrupt stays listed
    maxBars     = 6,
    width       = 220,
    height      = 20,
    spacing     = 2,
    fontSize    = 12,
    growUp      = false,
    scale       = 1,
    locked      = false,
}

-- First known spell wins; the same list KickBar uses.
local INTERRUPT_SPELLS = {
    DEATHKNIGHT = { 47528 }, DEMONHUNTER = { 183752 }, DRUID = { 106839, 78675 },
    EVOKER = { 351338 }, HUNTER = { 147362, 187707 }, MAGE = { 2139 },
    MONK = { 116705 }, PALADIN = { 96231 }, PRIEST = { 15487 }, ROGUE = { 1766 },
    SHAMAN = { 57994 }, WARRIOR = { 6552 },
    WARLOCK = { 119910, 132409, 119914 },  -- through the pet
}

local settings
local optionsWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    return false
end
local anchor
local ownBar
local ownSpell
local records = {}       -- party interrupt bars, newest first
local pool = {}
local active = false
local eventFrame = CreateFrame("Frame")

local GREEN = CreateColor(0.2, 0.8, 0.2, 1)

local function WantedHere()
    if not settings.onlyDungeons then return true end
    local _, kind = IsInInstance()
    return kind == "party"
end

local function KnowsSpell(id)
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, known = pcall(C_SpellBook.IsSpellInSpellBook, id)
        if ok and known == true then return true end
    end
    return (IsPlayerSpell and IsPlayerSpell(id)) or false
end

local function FindOwnInterrupt()
    local _, class = UnitClass("player")
    ownSpell = nil
    for _, id in ipairs(INTERRUPT_SPELLS[class] or {}) do
        if KnowsSpell(id) or (IsSpellKnown and IsSpellKnown(id, true)) then
            ownSpell = id
            break
        end
    end
end

-- ── Bars ────────────────────────────────────────────────────────────────────

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "OxedHubPartyInterruptsAnchor", UIParent)
    anchor:SetPoint(settings.point or "CENTER", UIParent, settings.rel or "CENTER", settings.x or -300, settings.y or -150)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        settings.point, settings.rel, settings.x, settings.y = point, rel, x, y
    end)
    anchor.hint = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.hint:SetAllPoints()
    anchor.hint:SetColorTexture(0, 0.6, 1, 0.25)
    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.text:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    anchor.text:SetText("Party Interrupts: drag me")
end

local function NewBar()
    local bar = CreateFrame("Frame", nil, anchor)
    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill:SetMinMaxValues(0, 1)
    bar.bg = bar.fill:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.name = bar.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.time = bar.fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.time:SetJustifyH("RIGHT")
    return bar
end

local function LayoutBar(bar)
    local h = settings.height
    bar:SetSize(settings.width, h)
    bar.icon:ClearAllPoints()
    bar.icon:SetPoint("LEFT")
    bar.icon:SetSize(h, h)
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("TOPLEFT", h + 2, 0)
    bar.fill:SetPoint("BOTTOMRIGHT")
    local font = GameFontHighlightSmall:GetFont()
    bar.name:SetFont(font, settings.fontSize, "OUTLINE")
    bar.time:SetFont(font, settings.fontSize, "OUTLINE")
    bar.time:ClearAllPoints()
    bar.time:SetPoint("RIGHT", -4, 0)
    bar.time:SetWidth(40)
    bar.name:ClearAllPoints()
    bar.name:SetPoint("LEFT", 4, 0)
    bar.name:SetPoint("RIGHT", bar.time, "LEFT", -4, 0)
end

local function Relayout()
    if not anchor then return end
    anchor:SetScale(settings.scale)
    anchor:SetSize(settings.width, settings.height)
    local editing = settings.enabled and not settings.locked and OptionsOpen()
    anchor.hint:SetShown(editing)
    anchor.text:SetShown(editing)
    anchor:EnableMouse(editing)
    local here = active and WantedHere()
    anchor:SetShown(here or editing)

    local list = {}
    if ownBar and settings.showOwn and ownSpell and here then list[#list + 1] = ownBar
    elseif ownBar then ownBar:Hide() end
    if settings.showParty and here then
        for _, bar in ipairs(records) do list[#list + 1] = bar end
    end
    for i, bar in ipairs(list) do
        if i > settings.maxBars then
            bar:Hide()
        else
            LayoutBar(bar)
            local step = (i - 1) * (settings.height + settings.spacing)
            bar:ClearAllPoints()
            if settings.growUp then
                bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, step)
            else
                bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -step)
            end
            bar:Show()
        end
    end
    if not here then
        for _, bar in ipairs(records) do bar:Hide() end
    end
end

-- ── Your interrupt ─────────────────────────────────────────────────────────

-- The bar's cooldown only: what runs on every cooldown change in the game,
-- so nothing here builds a table, a closure or a layout.
local bindingDuration
local function BindOwnTime()
    ownBar.binding = ownBar.binding or C_DurationUtil.CreateDurationTextBinding()
    ownBar.binding:SetFontString(ownBar.time)
    ownBar.binding:SetDuration(bindingDuration)
    if ownBar.binding.SetTextFormat then ownBar.binding:SetTextFormat("%.0f") end
    ownBar.binding:SetEnabled(true)
end

local function RefreshOwnCooldown()
    if not (ownBar and ownSpell) then return end
    local duration
    if C_Spell.GetSpellCooldownDuration then
        local ok, value = pcall(C_Spell.GetSpellCooldownDuration, ownSpell)
        if ok then duration = value end
    end
    if duration and ownBar.fill.SetTimerDuration then
        -- Fills as the interrupt comes back; full means ready.
        ownBar.fill:SetTimerDuration(duration, 0, 1)
        if ownBar.fill.SetToTargetValue then ownBar.fill:SetToTargetValue() end
        if C_DurationUtil and C_DurationUtil.CreateDurationTextBinding then
            bindingDuration = duration
            pcall(BindOwnTime)
        end
    else
        ownBar.fill:SetValue(1)
        ownBar.time:SetText("")
    end
end

-- The game fires its cooldown event for every spell of everyone's bars, many
-- times a second in a fight. Ours waits for a quiet moment and looks once.
local cooldownQueued = false
local function RunQueuedCooldown()
    cooldownQueued = false
    RefreshOwnCooldown()
end
local function QueueOwnCooldown()
    if cooldownQueued then return end
    cooldownQueued = true
    C_Timer.After(0.15, RunQueuedCooldown)
end

-- Who and what the bar shows: on a spec, talent or pet change, not per cooldown.
local function UpdateOwn()
    if not ownSpell then FindOwnInterrupt() end
    if not ownSpell then Relayout(); return end
    ownBar = ownBar or NewBar()
    ownBar.name:SetText(UnitName("player"))
    ownBar.icon:SetTexture(C_Spell.GetSpellTexture(ownSpell))
    local _, class = UnitClass("player")
    local colour = settings.classColour and C_ClassColor and C_ClassColor.GetClassColor(class)
    ownBar.name:SetTextColor((colour or WHITE_FONT_COLOR):GetRGB())
    ownBar.fill:GetStatusBarTexture():SetVertexColor(GREEN:GetRGBA())
    RefreshOwnCooldown()
    Relayout()
end

-- ── The group's interrupts ─────────────────────────────────────────────────

local function Drop(bar)
    for i, b in ipairs(records) do
        if b == bar then table.remove(records, i); break end
    end
    bar:Hide()
    table.insert(pool, bar)
    Relayout()
end

local function AddRecord(interruptedBy, spellID)
    local bar = table.remove(pool) or NewBar()
    -- Each value may be secret: handed to the setters as they are.
    pcall(function() bar.name:SetText(UnitNameFromGUID(interruptedBy)) end)
    bar.name:SetTextColor(1, 1, 1)
    if settings.classColour then
        pcall(function()
            local _, class = UnitClassFromGUID(interruptedBy)
            local colour = C_ClassColor.GetClassColor(class)
            bar.name:SetTextColor(colour:GetRGB())
        end)
    end
    bar.icon:SetTexture(132357)
    pcall(function() bar.icon:SetTexture(C_Spell.GetSpellTexture(spellID)) end)
    bar.fill:GetStatusBarTexture():SetVertexColor(0.3, 0.6, 1, 1)

    local seconds = settings.record
    if C_DurationUtil and C_DurationUtil.CreateDuration and bar.fill.SetTimerDuration then
        local duration = C_DurationUtil.CreateDuration()
        duration:SetTimeFromEnd(GetTime() + seconds, seconds, 1)
        bar.fill:SetTimerDuration(duration, 0, 0)
        if bar.fill.SetToTargetValue then bar.fill:SetToTargetValue() end
    else
        bar.fill:SetValue(1)
    end
    bar.time:SetText("")
    table.insert(records, 1, bar)
    while #records > 10 do Drop(records[#records]) end
    Relayout()
    C_Timer.After(seconds, function() Drop(bar) end)
end

local function OnInterrupted(unit, spellID, interruptedBy)
    if not (settings.showParty and WantedHere()) then return end
    if type(unit) ~= "string" or not (unit:match("^nameplate%d+$") or unit:match("^boss%d$")) then return end
    -- No interrupter at all is a plain nil; a secret one is not tested.
    if interruptedBy == nil then return end
    AddRecord(interruptedBy, spellID)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        local unit, _, spellID, interruptedBy = ...
        local ok, err = pcall(OnInterrupted, unit, spellID, interruptedBy)
        if not ok then geterrorhandler()(err) end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        QueueOwnCooldown()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and ownSpell and not (issecretvalue and issecretvalue(spellID)) and spellID == ownSpell then
            C_Timer.After(0.1, RefreshOwnCooldown)
        end
    else
        -- Spec, talents, pet or zone changed: find the interrupt again.
        ownSpell = nil
        C_Timer.After(0.5, UpdateOwn)
    end
end)

local function Start()
    active = true
    CreateAnchor()
    for _, e in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "SPELL_UPDATE_COOLDOWN",
        "PLAYER_SPECIALIZATION_CHANGED", "TRAIT_CONFIG_UPDATED", "UNIT_PET", "PLAYER_ENTERING_WORLD" }) do
        eventFrame:RegisterEvent(e)
    end
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    UpdateOwn()
end

local function Stop()
    active = false
    eventFrame:UnregisterAllEvents()
    for i = #records, 1, -1 do Drop(records[i]) end
    if ownBar then ownBar:Hide() end
    if anchor then anchor:Hide() end
end

local function ShowTest()
    if not settings.enabled then
        print("|cff00ccffOxedHub|r Switch Party Interrupts on first.")
        return
    end
    local guid = UnitGUID("player")
    AddRecord(guid, 2139)
    C_Timer.After(1.5, function() AddRecord(guid, 1766) end)
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Party Interrupts", 460, 630)
        optionsWindow = w
        w:HookScript("OnShow", function() Relayout() end)
        w:HookScript("OnHide", function() Relayout() end)
        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(170, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        test:SetText("Show a test")
        test:SetScript("OnClick", ShowTest)
        w.cursorY = w.cursorY - 32
        w:AddCheckbox(settings, "showOwn", "Your interrupt", nil, UpdateOwn)
        w:AddCheckbox(settings, "showParty", "Interrupts your group lands", nil, Relayout)
        w:AddCheckbox(settings, "onlyDungeons", "Only in dungeons", nil, Relayout)
        w:AddCheckbox(settings, "classColour", "Names in class colour", nil, UpdateOwn)
        w:AddSlider(settings, "record", "Each stays listed for", 5, 30, 1, "%s: %d s")
        w:AddCheckbox(settings, "locked", "Lock the list", "Unlocked, drag the blue box.", Relayout)
        w:AddCheckbox(settings, "growUp", "Grow upwards", nil, Relayout)
        w:AddSlider(settings, "maxBars", "Bars at most", 1, 10, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "width", "Width", 120, 400, 10, "%s: %d", Relayout)
        w:AddSlider(settings, "height", "Bar height", 12, 36, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Relayout)
        w:AddModuleLinks("Works together with", { "bosstimers", "bossalerts", "bosstrack", "trashtimers", "enemycasts", "kickbar", "bosshealth" })
    end
    optionsWindow:Show()
end

-- ── Settings and registration ──────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.partyinterrupts
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.partyinterrupts = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "partyinterrupts",
        name     = "Party Interrupts",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "interrupt", "kick", "party", "group", "mythic", "cooldown" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Your kick's cooldown, and who in your group just interrupted what.",
        icon     = "Interface\\Icons\\Ability_Kick",

        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        quick = { { text = "Test", func = function() ShowTest() end } },
        OnEnable = function(_, cfg) settings = cfg; Start() end,
        OnDisable = function() Stop() end,
    })
end)
