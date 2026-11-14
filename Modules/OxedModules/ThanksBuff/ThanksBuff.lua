-- ============================================================================
-- Thanks for the Buff (built-in OxedHub module)
-- Somebody buffs you, you say thanks:
--
--   strangers   a player outside your group buffs you while you are out of
--               combat: an emote at them (picked at random from the ones
--               ticked), and a line in your chat naming them and the buff
--   group       a party or raid member uses a big spell on you (Power
--               Infusion, Blessing of Protection, a battle resurrection...):
--               a line in your chat, or a whisper to them
--   /oxthanks   thanks your target: an emote and a whisper
--
-- Who cast what comes from the combat log on Forever. The main game no longer
-- gives addons the combat log, so there the new buff's own source is read
-- (UNIT_AURA), which knows the caster only when the game has a unit for them
-- and says nothing in a fight, where auras are secret.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local ICON = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit"
local PREFIX = "|cff33ff99OxedHub Thanks:|r "
local SAFETY_PAUSE = 3      -- after a loading screen your buffs come back: no thanks for those
local GROUP_GAP = 3         -- the same group member is thanked at most this often

-- Emotes that can be picked for strangers and for /oxthanks.
local EMOTES = { "THANK", "BOW", "CHEER", "SMILE", "HUG", "SALUTE", "WAVE" }
local EMOTE_LABEL = { THANK = "Thank", BOW = "Bow", CHEER = "Cheer", SMILE = "Smile", HUG = "Hug",
                      SALUTE = "Salute", WAVE = "Wave" }

local DEFAULTS = {
    enabled        = false,  -- off until the player switches it on
    minimapButton  = true,
    -- Strangers
    strangers      = true,
    strangerEmote  = true,
    strangerNote   = true,   -- a line in your own chat
    strangerWhisper = false,
    strangerGap    = 60,     -- seconds before the same stranger is thanked again
    minDuration    = 60,     -- buffs shorter than this (Renew, Rejuvenation) are not thanked
    -- Group
    group          = true,
    groupNote      = true,
    groupWhisper   = false,
    -- The emotes, one key each: a table here would be shared by every character.
    emote_THANK = true, emote_BOW = true, emote_CHEER = false, emote_SMILE = true,
    emote_HUG = false, emote_SALUTE = false, emote_WAVE = false,
}

-- Big spells a group member may use on you, by the spell id that lands on you.
-- noAura: no buff stays (a resurrection, Lay on Hands): taken from the cast.
local GROUP_SPELLS = {
    { ids = { 10060 } },                                         -- Power Infusion
    { ids = { 33206 } },                                         -- Pain Suppression
    { ids = { 47788 } },                                         -- Guardian Spirit
    { ids = { 6346 } },                                          -- Fear Ward
    { ids = { 1022, 5599, 10278 } },                             -- Blessing of Protection
    { ids = { 1044 } },                                          -- Blessing of Freedom
    { ids = { 6940, 20729, 27147, 27148 } },                     -- Blessing of Sacrifice
    { ids = { 19752 } },                                         -- Divine Intervention
    { ids = { 29166 } },                                         -- Innervate
    { ids = { 102342 } },                                        -- Ironbark
    { ids = { 20707, 20762, 20763, 20764, 20765, 27239 } },      -- Soulstone
    { ids = { 204018 } },                                        -- Blessing of Spellwarding
    { ids = { 357170 } },                                        -- Time Dilation
    { ids = { 633, 2800, 10310, 27154 }, noAura = true },        -- Lay on Hands
    { ids = { 20484, 20739, 20742, 20747, 20748, 26994 }, noAura = true },  -- Rebirth
    { ids = { 2006, 2010, 10880, 10881, 20770, 25435 }, noAura = true },    -- Resurrection
    { ids = { 7328, 10322, 10324, 20772, 20773 }, noAura = true },          -- Redemption
    { ids = { 2008, 20609, 20610, 20776, 20777 }, noAura = true },          -- Ancestral Spirit
}
local groupSpell = {}       -- spell id -> { noAura }
for _, def in ipairs(GROUP_SPELLS) do
    for _, id in ipairs(def.ids) do groupSpell[id] = { noAura = def.noAura == true } end
end

local settings
local running = false
local readyAt = 0
local thankedAt = {}        -- guid -> GetTime() of the last thanks
local optionsWindow
local minimapIcon, MinimapIcon, ShowOptions
local events = CreateFrame("Frame")

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Plain(v) return v ~= nil and not Secret(v) end

local function MyGUID()
    local ok, guid = pcall(UnitGUID, "player")
    return (ok and Plain(guid)) and guid or nil
end

local function SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if not name and GetSpellInfo then name = GetSpellInfo(id) end
    return type(name) == "string" and name or nil
end

local function SpellLink(id)
    local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)
    if not link and GetSpellLink then link = GetSpellLink(id) end
    return type(link) == "string" and link or SpellName(id) or "?"
end

local function ShortName(name)
    return (type(name) == "string" and name:gsub("%-.*$", "")) or "?"
end

local function Coloured(name, guid)
    local short = ShortName(name)
    if guid and GetPlayerInfoByGUID then
        local ok, _, cls = pcall(GetPlayerInfoByGUID, guid)
        if ok and Plain(cls) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
            local c = RAID_CLASS_COLORS[cls]
            return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, short)
        end
    end
    return short
end

local function InMyGroup(name)
    local okP, party = pcall(UnitInParty, name)
    local okR, raid = pcall(UnitInRaid, name)
    return (okP and party == true) or (okR and raid ~= nil and not Secret(raid))
end

local function PickEmote()
    local list = {}
    for _, e in ipairs(EMOTES) do
        if settings["emote_" .. e] then list[#list + 1] = e end
    end
    if #list == 0 then return nil end
    return list[math.random(#list)]
end

local function Whisper(text, name)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send or not name then return end
    text = text:gsub("|", "/")          -- a | in chat text gets the whole line refused
    pcall(send, text, "WHISPER", nil, name)
end

local function BuffDuration(spellID)
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or not aura or Secret(aura) then return nil end
    local d = aura.duration
    if not Plain(d) or type(d) ~= "number" then return nil end
    return d
end

-- ── Saying thanks ───────────────────────────────────────────────────────────

local function ThankStranger(guid, name, spellID)
    if not settings.strangers then return end
    if InCombatLockdown() then return end
    local d = BuffDuration(spellID)
    -- 0 is a buff with no end (an aura): always worth it.
    if d and d > 0 and d < (tonumber(settings.minDuration) or 0) then return end
    local now = GetTime()
    if thankedAt[guid] and now - thankedAt[guid] < (tonumber(settings.strangerGap) or 60) then return end
    thankedAt[guid] = now
    if settings.strangerNote then
        print(PREFIX .. (L["%s buffed you with %s."]):format(Coloured(name, guid), SpellLink(spellID)))
    end
    if settings.strangerEmote then
        local emote = PickEmote()
        if emote and DoEmote then pcall(DoEmote, emote, name) end
    end
    if settings.strangerWhisper then
        Whisper(("Thanks for the %s!"):format(SpellName(spellID) or "buff"), name)
    end
end

local function ThankGroup(guid, name, spellID)
    if not settings.group then return end
    local now = GetTime()
    if thankedAt[guid] and now - thankedAt[guid] < GROUP_GAP then return end
    thankedAt[guid] = now
    if settings.groupNote then
        print(PREFIX .. (L["%s used %s on you."]):format(Coloured(name, guid), SpellLink(spellID)))
    end
    if settings.groupWhisper then
        Whisper(("Thanks for the %s!"):format(SpellName(spellID) or "help"), name)
    end
end

-- One buff or cast on you, from somebody: decide who it was and what to do.
local function OnBuff(guid, name, spellID, isAura, isPlayer)
    if not running or GetTime() < readyAt then return end
    if not (Plain(guid) and Plain(name) and Plain(spellID)) then return end
    if type(name) ~= "string" or name == "" or type(spellID) ~= "number" then return end
    if guid == MyGUID() then return end
    if InMyGroup(name) then
        local def = groupSpell[spellID]
        if not def then return end
        -- An aura spell counts when it lands, the rest when cast: never twice.
        if def.noAura == isAura then return end
        ThankGroup(guid, name, spellID)
    elseif isAura and isPlayer then
        ThankStranger(guid, name, spellID)
    end
end

-- ── Where the news comes from ───────────────────────────────────────────────

local PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400

local function OnCombatLog()
    local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, _, _, _, spellID = CombatLogGetCurrentEventInfo()
    if sub ~= "SPELL_AURA_APPLIED" and sub ~= "SPELL_CAST_SUCCESS" then return end
    if dstGUID ~= MyGUID() then return end
    local isPlayer = type(srcFlags) == "number" and bit and bit.band(srcFlags, PLAYER_FLAG) > 0
    OnBuff(srcGUID, srcName, spellID, sub == "SPELL_AURA_APPLIED", isPlayer)
end

-- The main game: the new aura says who put it on, when the game will say.
local function OnAura(info)
    if type(info) ~= "table" or info.isFullUpdate or type(info.addedAuras) ~= "table" then return end
    for _, aura in ipairs(info.addedAuras) do
        if Plain(aura) and aura.isHelpful ~= false then
            local unit, spellID = aura.sourceUnit, aura.spellId
            if Plain(unit) and type(unit) == "string" and Plain(spellID) then
                local okP, isPlayer = pcall(UnitIsPlayer, unit)
                local okG, guid = pcall(UnitGUID, unit)
                local okN, name = pcall(GetUnitName, unit, true)
                if okP and okG and okN and isPlayer == true then OnBuff(guid, name, spellID, true, true) end
            end
        end
    end
end

local useCombatLog = false

events:SetScript("OnEvent", function(_, event, a, b)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        pcall(OnCombatLog)
    elseif event == "UNIT_AURA" then
        if a == "player" then pcall(OnAura, b) end
    elseif event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_ENTERING_WORLD" then
        readyAt = GetTime() + SAFETY_PAUSE
    end
end)

local function Start()
    if running then return end
    running = true
    readyAt = GetTime() + SAFETY_PAUSE
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    pcall(events.RegisterEvent, events, "LOADING_SCREEN_DISABLED")
    useCombatLog = false
    if not OxedHub.IsMainline and CombatLogGetCurrentEventInfo then
        useCombatLog = pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED") and true or false
    end
    if not useCombatLog then events:RegisterUnitEvent("UNIT_AURA", "player") end
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    wipe(thankedAt)
end

-- ── /oxthanks: thank your target ────────────────────────────────────────────

local function ThankTarget()
    if not running then
        print(PREFIX .. L["Switch Thanks for the Buff on in the Modules page first."])
        return
    end
    local okE, exists = pcall(UnitExists, "target")
    local okP, isPlayer = pcall(UnitIsPlayer, "target")
    if not (okE and exists == true and okP and isPlayer == true) then
        print(PREFIX .. L["Target a player to thank."])
        return
    end
    local okS, me = pcall(UnitIsUnit, "target", "player")
    if okS and me == true then
        print(PREFIX .. L["You cannot thank yourself."])
        return
    end
    local emote = PickEmote() or "THANK"
    if DoEmote then pcall(DoEmote, emote, "target") end
    local okN, name = pcall(GetUnitName, "target", true)
    local okF1, mine = pcall(UnitFactionGroup, "player")
    local okF2, theirs = pcall(UnitFactionGroup, "target")
    if okN and Plain(name) and okF1 and okF2 and Plain(mine) and Plain(theirs) and mine == theirs then
        Whisper("Thank you!", name)
    end
end

SLASH_OXEDHUBTHANKS1 = "/oxthanks"
SlashCmdList.OXEDHUBTHANKS = ThankTarget

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Thanks for the Buff", 460, 660)
        optionsWindow = w
        w:AddCheckbox(settings, "strangers", "Thank strangers who buff me",
            "A player outside your group, while you are out of combat.")
        w:AddCheckbox(settings, "strangerEmote", "With an emote at them")
        w:AddCheckbox(settings, "strangerNote", "With a line in my chat")
        w:AddCheckbox(settings, "strangerWhisper", "With a whisper to them")
        w:AddSlider(settings, "strangerGap", "The same stranger again after, seconds", 10, 600, 10, "%s: %d")
        w:AddSlider(settings, "minDuration", "Buffs shorter than this are skipped, seconds", 0, 600, 10, "%s: %d")
        w:AddCheckbox(settings, "group", "Notice big spells from my group",
            "Power Infusion, Blessing of Protection, Pain Suppression, Innervate, a Soulstone or a resurrection on you.")
        w:AddCheckbox(settings, "groupNote", "With a line in my chat")
        w:AddCheckbox(settings, "groupWhisper", "With a whisper to them")
        for _, e in ipairs(EMOTES) do
            w:AddCheckbox(settings, "emote_" .. e, (T("Emote: %s")):format(T(EMOTE_LABEL[e])))
        end
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("One of the ticked emotes is picked at random. /oxthanks thanks your target with an emote and a whisper.")
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "thanksbuff", label = T("Thanks for the Buff"), icon = ICON, config = settings,
        hint = T("Click: thank your target. Right-click: options."),
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ThankTarget() end
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
    local config = OxedHubDB.modules.thanksbuff
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.thanksbuff = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "thanksbuff",
        name     = "Thanks for the Buff",
        version  = "1.0.0",
        added    = 20261114,
        updated  = 20261114.8,
        author   = "Oxed",
        category = "chat",
        keywords = { "thanks", "thank", "buff", "emote", "whisper", "power infusion", "soulstone", "tftb" },
        desc     = "Someone buffs you: an emote and thanks. Notes big spells from your group.",
        icon     = ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
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
