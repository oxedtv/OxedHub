-- ============================================================================
-- Boss Timers (built-in OxedHub module)
-- Bars for the boss abilities that are coming, and a sound a few seconds
-- before each one lands. Every known ability can have its own settings:
-- switched off, its own sound, its own text, its own warning time.
--
-- What is coming comes from BossEngine (BossEngine.lua), which follows the
-- game's boss timeline and recognises each ability from BossData. An ability
-- it cannot recognise still gets a bar, with the game's own name and icon.
--
-- ⚠ An unrecognised event's name and icon can be secret values in a fight.
-- They only ever go to SetText / SetTexture, which accept secrets.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled     = false,   -- off until the player switches it on

    -- Where
    inDungeons  = true,
    inRaids     = true,
    elsewhere   = true,    -- delves, scenarios, the open world

    -- What
    showBars    = true,
    showWithin  = 0,       -- only show a bar this many seconds before; 0 = always
    hideTankForOthers = true,  -- tank abilities only for tanks
    hideHealerForOthers = false,
    hideUnknown = false,   -- events the data does not know
    colourByKind = true,

    -- Sound
    warn        = true,
    warnAt      = 5,       -- seconds before the ability
    sound       = "",      -- an OxedHub sound id; empty plays the raid warning
    warnUnknown = true,    -- a sound for events the data does not know

    -- Look
    maxBars     = 6,
    width       = 240,
    height      = 20,
    spacing     = 3,
    fontSize    = 12,
    growUp      = false,
    scale       = 1,
    locked      = false,
    texture     = "blizzard",
    iconSide    = "left",  -- left, right or none
    showTime    = true,
    decimalsUnder = 10,    -- show tenths below this many seconds
    background  = 0.55,    -- background opacity
    outline     = "OUTLINE",
    warnColour  = true,    -- the warning colour once inside the warning time
    nameFirst   = true,    -- name on the left, time on the right
}

-- Bar textures: the game's own, plus everything LibSharedMedia offers.
local TEXTURES = {
    { value = "blizzard", text = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { value = "flat", text = "Flat", path = "Interface\\Buttons\\WHITE8X8" },
    { value = "raid", text = "Raid frame", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { value = "skills", text = "Skills bar", path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}
local function TextureChoices()
    local list = {}
    for _, t in ipairs(TEXTURES) do list[#list + 1] = t end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, name in ipairs(LSM:List("statusbar") or {}) do
            list[#list + 1] = { value = "lsm:" .. name, text = name }
        end
    end
    return list
end
local function TexturePath(value)
    for _, t in ipairs(TEXTURES) do
        if t.value == value then return t.path end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and type(value) == "string" and value:sub(1, 4) == "lsm:" then
        return LSM:Fetch("statusbar", value:sub(5), true) or TEXTURES[1].path
    end
    return TEXTURES[1].path
end

-- Colours by ability kind, when colourByKind is on.
local KIND_COLOUR = {
    tank      = { 0.85, 0.25, 0.20 },
    healer    = { 0.25, 0.80, 0.35 },
    targeted  = { 0.95, 0.75, 0.15 },
    mechanic  = { 0.30, 0.60, 1.00 },
    special   = { 0.75, 0.40, 1.00 },
    other     = { 1.00, 0.55, 0.10 },
}
local KIND_NAME = {
    tank = "Tank", healer = "Healer", targeted = "Targeted",
    mechanic = "Mechanic", special = "Special", other = "Other",
}

local TICK       = 0.1   -- bar and warning refresh while anything is coming

local function BySoonest(a, b) return a.left < b.left end
local MIN_REFIRE = 1.0   -- two abilities at once give one sound, not two

local Engine = OxedHub.BossEngine
local settings
local optionsWindow, abilitiesWindow
local lookWindow

-- The blue "drag me" boxes show only while this module's options are open.
local function OptionsOpen()
    if optionsWindow and optionsWindow:IsShown() then return true end
    if lookWindow and lookWindow:IsShown() then return true end
    return false
end
local anchor
local bars = {}
local ticker
local lastSound = 0
local active = false

-- ── Per-ability settings ───────────────────────────────────────────────────
-- settings.abilities["<encounter>:<event>"] = { off, sound, text, warnAt, mute }
-- Built after the settings are bound: a table in DEFAULTS would be shared.

local function AbilityKey(encounterID, abilityID)
    return tostring(encounterID) .. ":" .. tostring(abilityID)
end

local function AbilitySettings(ev, create)
    if not (ev.encounterID and ev.abilityID) then return nil end
    local key = AbilityKey(ev.encounterID, ev.abilityID)
    local row = settings.abilities[key]
    if not row and create then
        row = {}
        settings.abilities[key] = row
    end
    return row
end

local function PlayerRole()
    local spec = GetSpecialization and GetSpecialization()
    return spec and GetSpecializationRole and GetSpecializationRole(spec) or nil
end

local function WantedHere()
    local inInstance, kind = IsInInstance()
    if kind == "party" then return settings.inDungeons end
    if kind == "raid" then return settings.inRaids end
    return settings.elsewhere
end

-- Whether an event is shown and warned for at all.
local function Wanted(ev)
    local own = AbilitySettings(ev)
    if own and own.off then return false end
    if not ev.ability then return not settings.hideUnknown end
    local kind = ev.ability.kind
    local role = PlayerRole()
    if kind == "tank" and settings.hideTankForOthers and role and role ~= "TANK" then return false end
    if kind == "healer" and settings.hideHealerForOthers and role and role ~= "HEALER" then return false end
    return true
end

local function PlayWarning(soundID)
    local now = GetTime()
    if now - lastSound < MIN_REFIRE then return end
    lastSound = now
    local API = OxedHub.ModuleAPI
    if API and API:PlaySound(soundID) then return end
    if API and API:PlaySound(settings.sound) then return end
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
        pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
    end
end

-- ── Bars ────────────────────────────────────────────────────────────────────

local function SavePosition()
    local point, _, relPoint, x, y = anchor:GetPoint()
    settings.point, settings.relPoint, settings.x, settings.y = point, relPoint, x, y
end

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "OxedHubBossTimersAnchor", UIParent)
    anchor:SetPoint(settings.point or "CENTER", UIParent, settings.relPoint or "CENTER",
        settings.x or 300, settings.y or 100)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self)
        if not settings.locked then self:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    local hint = anchor:CreateTexture(nil, "BACKGROUND")
    hint:SetAllPoints()
    hint:SetColorTexture(0, 0.6, 1, 0.25)
    anchor.hint = hint
    -- Above the box, so the bars never cover it.
    local text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    text:SetText("Boss Timers: drag me")
    anchor.text = text
    anchor:Hide()
end

local function CreateBar(index)
    local bar = CreateFrame("StatusBar", nil, anchor)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.icon = bar:CreateTexture(nil, "ARTWORK")
    bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.name:SetWordWrap(false)
    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bars[index] = bar
    return bar
end

local function LayoutBar(bar, index)
    local h = settings.height
    local step = (index - 1) * (h + settings.spacing)
    local side = settings.iconSide
    local left = (side == "left") and (h + 2) or 0
    local width = settings.width - ((side == "none") and 0 or (h + 2))
    bar:ClearAllPoints()
    if settings.growUp then
        bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", left, step)
    else
        bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", left, -step)
    end
    bar:SetSize(width, h)
    bar:SetStatusBarTexture(TexturePath(settings.texture))
    bar.bg:SetColorTexture(0, 0, 0, settings.background)

    bar.icon:ClearAllPoints()
    bar.icon:SetSize(h, h)
    if side == "right" then
        bar.icon:SetPoint("LEFT", bar, "RIGHT", 2, 0)
    else
        bar.icon:SetPoint("RIGHT", bar, "LEFT", -2, 0)
    end
    bar.icon:SetShown(side ~= "none")

    local font = GameFontHighlightSmall:GetFont()
    local outline = settings.outline ~= "" and settings.outline or nil
    bar.name:SetFont(font, settings.fontSize, outline)
    bar.time:SetFont(font, settings.fontSize, outline)
    local tc = settings.colours.text
    bar.name:SetTextColor(tc[1], tc[2], tc[3])
    bar.time:SetTextColor(tc[1], tc[2], tc[3])

    -- Name on one side, time on the other; the name stops short of the time.
    local nameSide, timeSide = "LEFT", "RIGHT"
    if not settings.nameFirst then nameSide, timeSide = "RIGHT", "LEFT" end
    local inset = function(point) return (point == "LEFT") and 4 or -4 end
    bar.name:ClearAllPoints()
    bar.time:ClearAllPoints()
    bar.time:SetPoint(timeSide, inset(timeSide), 0)
    bar.time:SetShown(settings.showTime)
    bar.name:SetJustifyH(nameSide)
    bar.name:SetPoint(nameSide, inset(nameSide), 0)
    if settings.showTime then
        bar.name:SetPoint(timeSide, bar.time, nameSide, -inset(timeSide), 0)
    else
        bar.name:SetPoint(timeSide, inset(timeSide), 0)
    end
end

local function Restyle()
    if not anchor then return end
    anchor:SetScale(settings.scale or 1)
    anchor:SetSize(settings.width, settings.height)
    for index, bar in ipairs(bars) do LayoutBar(bar, index) end
    local editing = not settings.locked and settings.enabled and OptionsOpen()
    anchor.hint:SetShown(editing)
    anchor.text:SetShown(editing)
    anchor:EnableMouse(editing)
    anchor:SetShown(editing or ticker ~= nil)
end

-- ── Each tick ──────────────────────────────────────────────────────────────

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local sorted = {}
local function Tick()
    wipe(sorted)
    local here = WantedHere()
    local any = false
    for _, ev in pairs(Engine:GetEvents()) do
        any = true
        if here and Engine:IsActive(ev) and Wanted(ev) then
            local left = Engine:TimeLeft(ev)
            ev.left = left
            if left > 0 then
                local own = AbilitySettings(ev)
                local warnAt = (own and own.warnAt) or settings.warnAt
                local wantsSound = settings.warn and not (own and own.mute)
                    and (ev.ability or settings.warnUnknown or ev.test)
                if wantsSound and not ev.warned and left <= warnAt then
                    ev.warned = true
                    PlayWarning(own and own.sound)
                end
                if settings.showWithin <= 0 or left <= settings.showWithin then
                    sorted[#sorted + 1] = ev
                end
            end
        end
    end

    local shown = 0
    if settings.showBars then
        table.sort(sorted, BySoonest)
        for i = 1, math.min(#sorted, settings.maxBars) do
            local ev = sorted[i]
            local bar = bars[i] or CreateBar(i)
            if not bar.laidOut then LayoutBar(bar, i); bar.laidOut = true end
            local own = AbilitySettings(ev)
            bar:SetMinMaxValues(0, ev.duration > 0 and ev.duration or 1)
            bar:SetValue(ev.left)
            -- An unrecognised event's name and icon may be secret: handed over
            -- as they are, never tested with "or".
            if own and own.text and own.text ~= "" then
                bar.name:SetText(own.text)
            else
                bar.name:SetText(ev.name)
            end
            bar.icon:SetTexture(ev.icon)
            bar.time:SetText(ev.left < settings.decimalsUnder and ("%.1f"):format(ev.left)
                or ("%d"):format(ev.left))
            local warnAt = (own and own.warnAt) or settings.warnAt
            local colours = settings.colours
            local colour = (settings.colourByKind and ev.ability and colours[ev.ability.kind])
                or colours.other
            if settings.warnColour and ev.left <= warnAt then
                local wc = colours.warn
                bar:SetStatusBarColor(wc[1], wc[2], wc[3])
            else
                bar:SetStatusBarColor(colour[1], colour[2], colour[3])
            end
            bar:Show()
            shown = i
        end
    end
    for i = shown + 1, #bars do bars[i]:Hide() end

    if not any then
        StopTicker()
        Restyle()
    end
end

local function StartTicker()
    if ticker or not active then return end
    ticker = C_Timer.NewTicker(TICK, Tick)
    Restyle()
end

Engine:AddListener({
    OnEventAdded = function() StartTicker() end,
    OnEncounterEnd = function()
        for _, bar in ipairs(bars) do bar:Hide() end
    end,
})

local function Start()
    active = true
    CreateAnchor()
    Engine:Start()
    if next(Engine:GetEvents()) then StartTicker() end
    Restyle()
end

local function Stop()
    active = false
    StopTicker()
    Engine:Stop()
    for _, bar in ipairs(bars) do bar:Hide() end
    if anchor then anchor:Hide() end
end

local function Relayout()
    for _, bar in ipairs(bars) do bar.laidOut = nil end
    Restyle()
end

local function ShowTest()
    if not settings.enabled then
        print("|cff00ccffOxedHub|r Switch Boss Timers on first.")
        return
    end
    Engine:AddTestEvents({
        { name = "Test: Crushing Blow", icon = 136025, duration = 6, kind = "tank" },
        { name = "Test: Shadow Burst", icon = 136197, duration = 10, kind = "mechanic" },
        { name = "Test: Healing Check", icon = 136218, duration = 14, kind = "healer" },
        { name = "Test: Fixate", icon = 136219, duration = 18, kind = "targeted" },
    })
end

-- ── The abilities window ───────────────────────────────────────────────────
-- Every boss in BossData, grouped by dungeon or raid, and each of its
-- abilities with its own switch, text, warning time and sound.

local function SortedEncounters()
    local list = {}
    for id, enc in pairs((OxedHub.BossData and OxedHub.BossData.encounters) or {}) do
        local instance, boss = enc.instance, enc.boss
        if (not instance or not boss) and EJ_GetEncounterInfo and enc.journalID then
            local name, _, _, _, _, journalInstance = EJ_GetEncounterInfo(enc.journalID)
            boss = boss or name
            if not instance and journalInstance and EJ_GetInstanceInfo then
                instance = EJ_GetInstanceInfo(journalInstance)
            end
        end
        list[#list + 1] = { id = id, enc = enc, instance = instance or "Unknown",
            boss = boss or ("Encounter " .. id) }
    end
    -- Each dungeon's trash, first in its dungeon, as one more "boss".
    if OxedHub.TrashSpellsForInstance then
        local names = {}
        for _, item in ipairs(list) do names[item.enc.mapID or 0] = item.instance end
        for mapID, name in pairs(names) do
            local spells = OxedHub.TrashSpellsForInstance(mapID)
            if spells then
                list[#list + 1] = { id = "trash", instance = name, boss = "Trash",
                    enc = { abilities = spells, raid = false, order = 0, mapID = mapID } }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.enc.raid ~= b.enc.raid then return not a.enc.raid end
        if a.instance ~= b.instance then return a.instance < b.instance end
        return (a.enc.order or 0) < (b.enc.order or 0)
    end)
    return list
end

local ROW_HEIGHT = 30

local function BuildAbilitiesWindow()
    local API = OxedHub.ModuleAPI
    local w = API:CreateOptionsWindow("Boss Timers: abilities", 640, 560)

    -- Left: bosses. Right: the chosen boss's abilities.
    local bossScroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
    bossScroll:SetPoint("TOPLEFT", 12, -32)
    bossScroll:SetPoint("BOTTOMLEFT", 12, 12)
    bossScroll:SetWidth(200)
    local bossList = CreateFrame("Frame", nil, bossScroll)
    bossList:SetSize(200, 1)
    bossScroll:SetScrollChild(bossList)

    local abilityScroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
    abilityScroll:SetPoint("TOPLEFT", 240, -32)
    abilityScroll:SetPoint("BOTTOMRIGHT", -32, 12)
    local abilityList = CreateFrame("Frame", nil, abilityScroll)
    abilityList:SetSize(360, 1)
    abilityScroll:SetScrollChild(abilityList)

    local abilityRows = {}
    local selected

    local function ShowBoss(item)
        selected = item
        for _, row in ipairs(abilityRows) do row:Hide() end
        local ids = {}
        for abilityID in pairs(item.enc.abilities or {}) do ids[#ids + 1] = abilityID end
        table.sort(ids)

        for index, abilityID in ipairs(ids) do
            local ability = item.enc.abilities[abilityID]
            local row = abilityRows[index]
            if not row then
                row = CreateFrame("Frame", nil, abilityList)
                row:SetHeight(ROW_HEIGHT)
                row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.check:SetSize(22, 22)
                row.check:SetPoint("LEFT", 0, 0)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetWidth(150)
                row.name:SetJustifyH("LEFT")
                row.name:SetWordWrap(false)
                row.sound = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.sound:SetSize(70, 20)
                row.sound:SetPoint("RIGHT", -96, 0)
                row.sound:SetText("Sound")
                row.more = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                row.more:SetSize(90, 20)
                row.more:SetPoint("RIGHT", 0, 0)
                row.more:SetText("Text & time")
                abilityRows[index] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", abilityList, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
            row:SetPoint("TOPRIGHT", abilityList, "TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)

            local ev = { encounterID = item.id, abilityID = abilityID }
            local function Own(create) return AbilitySettings(ev, create) end
            local function Label()
                local own = Own()
                local name = (own and own.text and own.text ~= "" and own.text) or Engine:AbilityName(ability)
                local extra = KIND_NAME[ability.kind] or ""
                if own and own.warnAt then extra = extra .. ", " .. own.warnAt .. " s" end
                if own and own.mute then extra = extra .. ", silent"
                elseif own and own.sound and own.sound ~= "" then
                    extra = extra .. ", " .. API:SoundName(own.sound)
                end
                row.name:SetText(name .. "  |cff888888" .. extra .. "|r")
            end

            row.icon:SetTexture(Engine:AbilityIcon(ability))
            row.check:SetChecked(not (Own() and Own().off))
            row.check:SetScript("OnClick", function(box)
                Own(true).off = not box:GetChecked() or nil
            end)
            row.name:SetScript("OnEnter", nil)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if ability.spell and GameTooltip.SetSpellByID then
                    GameTooltip:SetSpellByID(ability.spell)
                else
                    GameTooltip:SetText(Engine:AbilityName(ability))
                end
                GameTooltip:AddLine("Kind: " .. (KIND_NAME[ability.kind] or "Other"), 1, 1, 1)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.sound:SetScript("OnClick", function()
                local Triggers = OxedHub.Triggers
                if not (Triggers and Triggers.ShowSoundPicker) then return end
                local own = Own(true)
                local mock = { actions = { sound = own.sound or "" } }
                Triggers:ShowSoundPicker(mock, "sound", function(id)
                    if not id or id == "" or id == "None" or id == "none" then
                        own.sound = nil
                    else
                        own.sound = id
                    end
                    Label()
                end)
            end)
            row.more:SetScript("OnClick", function()
                local own = Own(true)
                StaticPopupDialogs["OXEDHUB_BOSSTIMER_TEXT"] = {
                    text = "Text on the bar for %s, and seconds before it to warn (empty: the usual). Add \"mute\" for no sound.\nExample:  Soak 4   or   Spread mute",
                    button1 = ACCEPT, button2 = CANCEL,
                    hasEditBox = true, maxLetters = 60,
                    OnShow = function(popup)
                        local parts = {}
                        if own.text then parts[#parts + 1] = own.text end
                        if own.warnAt then parts[#parts + 1] = tostring(own.warnAt) end
                        if own.mute then parts[#parts + 1] = "mute" end
                        local box = popup.editBox or popup.EditBox
                        box:SetText(table.concat(parts, " "))
                        box:SetAutoFocus(false)
                    end,
                    OnAccept = function(popup)
                        local text = (popup.editBox or popup.EditBox):GetText() or ""
                        own.mute = nil
                        if text:find("%f[%w]mute%f[%W]") then
                            own.mute = true
                            text = text:gsub("%s*%f[%w]mute%f[%W]%s*", " ")
                        end
                        local seconds = text:match("(%d+%.?%d*)%s*$")
                        if seconds then
                            own.warnAt = tonumber(seconds)
                            text = text:gsub("%s*%d+%.?%d*%s*$", "")
                        else
                            own.warnAt = nil
                        end
                        text = text:gsub("^%s+", ""):gsub("%s+$", "")
                        own.text = text ~= "" and text or nil
                        Label()
                    end,
                    EditBoxOnEnterPressed = function(box)
                        local popup = box:GetParent()
                        StaticPopupDialogs["OXEDHUB_BOSSTIMER_TEXT"].OnAccept(popup)
                        popup:Hide()
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("OXEDHUB_BOSSTIMER_TEXT", Engine:AbilityName(ability))
            end)
            Label()
            row:Show()
        end
        abilityList:SetHeight(math.max(1, #ids * ROW_HEIGHT))
    end

    local bossButtons = {}
    w:HookScript("OnShow", function()
        local list = SortedEncounters()
        local y, lastInstance = 0, nil
        local index = 0
        for _, b in ipairs(bossButtons) do b:Hide() end
        for _, item in ipairs(list) do
            if item.instance ~= lastInstance then
                index = index + 1
                local header = bossButtons[index] or CreateFrame("Button", nil, bossList)
                bossButtons[index] = header
                header:SetSize(200, 20)
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", 0, -y)
                if not header.label then
                    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    header.label:SetPoint("LEFT", 2, 0)
                end
                header.label:SetText((item.enc.raid and "Raid: " or "") .. item.instance)
                header:SetScript("OnClick", nil)
                header:Show()
                y = y + 20
                lastInstance = item.instance
            end
            index = index + 1
            local button = bossButtons[index] or CreateFrame("Button", nil, bossList)
            bossButtons[index] = button
            button:SetSize(200, 18)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", 0, -y)
            if not button.label then
                button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                button.label:SetPoint("LEFT", 12, 0)
            end
            button.label:SetText(item.boss)
            button:SetScript("OnClick", function() ShowBoss(item) end)
            button:Show()
            y = y + 18
        end
        bossList:SetHeight(math.max(1, y))
        if selected then ShowBoss(selected) elseif list[1] then ShowBoss(list[1]) end
    end)
    return w
end

local function ShowAbilities()
    if not abilitiesWindow then abilitiesWindow = BuildAbilitiesWindow() end
    abilitiesWindow:Show()
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function AddButton(w, text, x, onClick)
    local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
    button:SetSize(170, 22)
    button:SetPoint("TOPLEFT", w, "TOPLEFT", x, w.cursorY - 2)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local colourWindow
local function ShowColours()
    local API = OxedHub.ModuleAPI
    if not colourWindow then
        local w = API:CreateOptionsWindow("Boss Timers: colours", 420, 330)
        colourWindow = w
        w:AddCheckbox(settings, "colourByKind", "Colour bars by kind")
        w:AddColour(settings.colours, "tank", "Tank")
        w:AddColour(settings.colours, "healer", "Healer")
        w:AddColour(settings.colours, "targeted", "On a player")
        w:AddColour(settings.colours, "mechanic", "Mechanic")
        w:AddColour(settings.colours, "special", "Special")
        w:AddColour(settings.colours, "other", "Other")
        w:AddCheckbox(settings, "warnColour", "Change colour inside the warning time")
        w:AddColour(settings.colours, "warn", "Warning colour")
    end
    colourWindow:Show()
end

local function ShowLook()
    local API = OxedHub.ModuleAPI
    if not lookWindow then
        local w = API:CreateOptionsWindow("Boss Timers: look", 480, 580)
        lookWindow = w
        w:HookScript("OnShow", function() Restyle() end)
        w:HookScript("OnHide", function() Restyle() end)
        AddButton(w, "Show test bars", 20, ShowTest)
        AddButton(w, "Colours", 250, ShowColours)
        w.cursorY = w.cursorY - 32

        w:AddCheckbox(settings, "locked", "Lock the bars",
            "Unlocked, drag the blue box with the left button.", Restyle)
        w:AddCheckbox(settings, "growUp", "Bars grow upwards", nil, Relayout)
        w:AddSlider(settings, "maxBars", "Bars at most", 1, 12, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "width", "Width", 120, 500, 10, "%s: %d", Relayout)
        w:AddSlider(settings, "height", "Bar height", 12, 40, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "spacing", "Space between bars", 0, 12, 1, "%s: %d", Relayout)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", Relayout)

        w:AddChoice(settings, "texture", "Bar texture", TextureChoices(), Relayout)
        w:AddSlider(settings, "background", "Background", 0, 1, 0.05, "%s: %.2f", Relayout)
        w:AddChoice(settings, "iconSide", "Icon", {
            { value = "left", text = "Left" }, { value = "right", text = "Right" },
            { value = "none", text = "Hidden" },
        }, Relayout)

        w:AddSlider(settings, "fontSize", "Text size", 8, 24, 1, "%s: %d", Relayout)
        w:AddChoice(settings, "outline", "Text outline", {
            { value = "OUTLINE", text = "Thin" }, { value = "THICKOUTLINE", text = "Thick" },
            { value = "", text = "None" },
        }, Relayout)
        w:AddCheckbox(settings, "nameFirst", "Name on the left, time on the right", nil, Relayout)
        w:AddCheckbox(settings, "showTime", "Show the time", nil, Relayout)
        w:AddSlider(settings, "decimalsUnder", "Tenths of a second below", 0, 30, 1, "%s: %d s")
        w:AddColour(settings.colours, "text", "Text colour", Relayout)
    end
    lookWindow:Show()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Boss Timers", 480, 670)
        optionsWindow = w
        w:HookScript("OnShow", function() Restyle() end)
        w:HookScript("OnHide", function() Restyle() end)

        AddButton(w, "Abilities, one by one", 20, ShowAbilities)
        AddButton(w, "Look", 250, ShowLook)
        w.cursorY = w.cursorY - 28
        AddButton(w, "Show test bars", 20, ShowTest)
        w.cursorY = w.cursorY - 32

        w:AddCheckbox(settings, "inDungeons", "In dungeons")
        w:AddCheckbox(settings, "inRaids", "In raids")
        w:AddCheckbox(settings, "elsewhere", "Elsewhere (delves, scenarios, outdoors)")

        w:AddCheckbox(settings, "showBars", "Show bars", nil, Restyle)
        w:AddSlider(settings, "showWithin", "Show a bar only in the last", 0, 60, 1, "%s: %d s (0 = always)")
        w:AddCheckbox(settings, "hideTankForOthers", "Tank abilities only when you are a tank")
        w:AddCheckbox(settings, "hideHealerForOthers", "Healer abilities only when you are a healer")
        w:AddCheckbox(settings, "hideUnknown", "Hide abilities the data does not know")

        w:AddCheckbox(settings, "warn", "Sound before each ability")
        w:AddSlider(settings, "warnAt", "Sound this early", 1, 15, 1, "%s: %d s")
        w:AddSoundPicker(settings, "sound", "Sound", "Raid warning")
        w:AddCheckbox(settings, "warnUnknown", "Also for abilities the data does not know")

        w:AddNote("Bars follow the game's own boss timeline. Known bosses get each "
            .. "ability recognised, so it can have its own sound, text and timing "
            .. "under Abilities, one by one.")
        w:AddModuleLinks("Works together with", { "bossalerts", "bosstrack", "trashtimers", "enemycasts", "partyinterrupts", "kickbar", "bosshealth" })
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
    local config = OxedHubDB.modules.bosstimers
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bosstimers = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.abilities) ~= "table" then config.abilities = {} end
    -- Colours are tables, so they are built here, never in DEFAULTS.
    if type(config.colours) ~= "table" then config.colours = {} end
    for kind, c in pairs(KIND_COLOUR) do
        if type(config.colours[kind]) ~= "table" then config.colours[kind] = { c[1], c[2], c[3] } end
    end
    if type(config.colours.warn) ~= "table" then config.colours.warn = { 1, 0.15, 0.1 } end
    if type(config.colours.text) ~= "table" then config.colours.text = { 1, 1, 1 } end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bosstimers",
        name     = "Boss Timers",
        version  = "1.1.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "boss", "timer", "timeline", "dbm", "bigwigs", "raid", "dungeon", "warning" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "Bars for coming boss abilities, each with its own sound, text and timing.",
        icon     = "Interface\\Icons\\Spell_Holy_BorrowedTime",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        quick = {
            { text = "Test bars", func = function() ShowTest() end },
            { text = "Abilities", func = function() ShowAbilities() end },
        },

        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.abilities) ~= "table" then settings.abilities = {} end
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
