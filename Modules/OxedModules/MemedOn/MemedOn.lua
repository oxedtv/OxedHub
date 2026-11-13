-- ============================================================================
-- MemedOn (built-in OxedHub module)
-- Scans chat, NPC dialogue, and system messages for keywords, plus spells and
-- PvP deaths, triggering authentic physical UI animations, screen effects,
-- OxedHub sounds and animated Meme Toast notifications.
--
-- Features:
--   * Full 1-in-1 keyword engine: per-keyword sounds, effects and variations.
--   * Full 1-in-1 physical UI effects (Wobble, Explosion, Blackhole, Wow, Tilt,
--     Rickroll, Flash) via MemedOnEffects.lua, with safe EditMode *Base setters,
--     plus original Earthquake and Glitch effects!
--   * Full 1-in-1 Spell Triggers: Leap of Faith, Rescue, Power Infusion, etc.
--   * Full 1-in-1 Death Bell: PvP kill alerts ignoring hunter Feign Death.
--   * Original Feature: Animated floating Meme Toast HUD banner on screen!
--   * OxedHub SoundPicker integration with live sound previews.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled              = false,   -- off until player enables it (OxedHub standard)
    showMatchMessage     = true,    -- print a line in chat on match
    showMemeToast        = true,    -- OxedHub Original: floating HUD banner
    triggerOnce          = false,   -- trigger each alert only once per session
    sound                = "",       -- default OxedHub sound ID
    channel              = "Master",
    effectsEnabled       = true,    -- allow physical UI / screen effects
    intensity            = 70,      -- global intensity (10 to 100)

    -- Keyword source filters
    keywordChat          = true,    -- say, yell, channel
    keywordWhisper       = true,    -- whispers
    keywordParty         = true,    -- party & raid chat
    keywordNpc           = true,    -- NPC dialogue & boss emotes
    keywordSystem        = true,    -- system & game messages
    keywordLoot          = false,   -- loot & crafting messages

    -- Spell triggers
    spellTriggersEnabled = true,

    -- Death Bell (PvP kill alert)
    deathBell            = false,
    deathBellSound       = "",
    deathBellArena       = true,
    deathBellBG          = true,
    deathBellWorld       = true,
    deathBellNPC         = false,
}

local settings
local optionsWindow
local watcher = CreateFrame("Frame")
local spellWatcher = CreateFrame("Frame")
local deathWatcher = CreateFrame("Frame")

local firedThisSession = {}
local lastAlertTime = 0
local lastDead = {}
local lastAuraTrigger = {}

local PREFIX = "|cffff6600OxMemes:|r "
local DEDUP_WINDOW = 0.75

-- ── 1-in-1 Preset Data ──────────────────────────────────────────────────────

local PRESET_KEYWORDS = {
    "67",
    "devour",
    "Rick rolled",
    "wow",
    "You died.",
    "Queue popped",
    "Congratulations, you have reached",
}

local PRESET_KEYWORD_CONFIG = {
    ["67"] = { sound = "", effect = "Wobble", intensity = 75, variations = { "6-7", "6 7" } },
    ["devour"] = { sound = "", effect = "Blackhole", intensity = 85, variations = { "dev dh" } },
    ["rick rolled"] = { sound = "", effect = "Rickroll", intensity = 80 },
    ["wow"] = { sound = "", effect = "Wow", intensity = 75 },
    ["you died."] = { sound = "", effect = "Explosion", intensity = 85 },
    ["queue popped"] = { sound = "", effect = "Rickroll", intensity = 75 },
    ["congratulations, you have reached"] = { sound = "", effect = "Wobble", intensity = 70 },
}

local PRESET_SPELLS = {
    "Leap of Faith",
    "Rescue",
    "Power Infusion",
    "Void Metamorphosis",
    "Collapsing Star",
    "Volley",
}

local PRESET_SPELL_CONFIG = {
    ["leap of faith"] = { sound = "", effect = "Tilt", onlyOnMe = true },
    ["rescue"] = { sound = "", effect = "Tilt", onlyOnMe = true },
    ["power infusion"] = { sound = "", effect = "Rickroll", onlyOnMe = true },
    ["void metamorphosis"] = { sound = "", effect = "Wobble", onlyOnMe = false },
    ["collapsing star"] = { sound = "", effect = "Blackhole", onlyOnMe = false },
    ["volley"] = { sound = "", effect = "Wow", onlyOnMe = false },
}

-- ── Safe helpers ────────────────────────────────────────────────────────────

local function SecretValue(val)
    return issecretvalue and issecretvalue(val) and true or false
end

local function StripHyperlinks(text)
    if type(text) ~= "string" or SecretValue(text) then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text
end

local function EnsureData()
    if not settings then return end

    if type(settings.keywords) ~= "table" then
        settings.keywords = {}
        for _, kw in ipairs(PRESET_KEYWORDS) do table.insert(settings.keywords, kw) end
    end

    if type(settings.keywordConfig) ~= "table" then
        settings.keywordConfig = {}
        for k, v in pairs(PRESET_KEYWORD_CONFIG) do
            settings.keywordConfig[k] = {
                sound = v.sound or "",
                effect = v.effect or "Wobble",
                intensity = v.intensity or 70,
                variations = v.variations and { unpack(v.variations) } or {},
            }
        end
    end

    -- "69" was a preset until 4.3.1. Taken out of saved lists once; a player
    -- who adds it back afterwards keeps it.
    if not settings.removedPreset69 then
        settings.removedPreset69 = true
        for i = #settings.keywords, 1, -1 do
            if settings.keywords[i] == "69" then table.remove(settings.keywords, i) end
        end
        settings.keywordConfig["69"] = nil
    end

    if type(settings.spellTriggers) ~= "table" then
        settings.spellTriggers = {}
        for _, sp in ipairs(PRESET_SPELLS) do table.insert(settings.spellTriggers, sp) end
    end

    if type(settings.spellConfig) ~= "table" then
        settings.spellConfig = {}
        for k, v in pairs(PRESET_SPELL_CONFIG) do
            settings.spellConfig[k] = {
                sound = v.sound or "",
                effect = v.effect or "None",
                onlyOnMe = v.onlyOnMe == true,
            }
        end
    end

    if type(settings.messageExclusions) ~= "table" then
        settings.messageExclusions = { "Loot Specialization set to" }
    end
end

-- ── Sound playback ──────────────────────────────────────────────────────────

local function PlayAlertSound(customSoundID, fallbackKitID)
    local id = (customSoundID and customSoundID ~= "") and customSoundID or (settings and settings.sound)
    if id and id ~= "" and OxedHub.Sounds and OxedHub.Sounds.Play then
        local ok = pcall(OxedHub.Sounds.Play, OxedHub.Sounds, id)
        if ok then return end
    end
    local kit = fallbackKitID or (SOUNDKIT and (SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK)) or 8959
    if PlaySound then
        pcall(PlaySound, kit, settings and settings.channel or "Master")
    end
end

-- ── Physical Effects Dispatcher ─────────────────────────────────────────────

local function RunAlertEffect(effectName, intensity)
    if not settings or not settings.effectsEnabled then return end
    effectName = effectName or "Wobble"
    if effectName == "None" then return end

    local effs = OxedHub.MemedOnEffects
    if effs and effs[effectName] and effs[effectName].Run then
        pcall(effs[effectName].Run, intensity or settings.intensity or 70)
    end
end

-- ── Effects for Triggers ────────────────────────────────────────────────────
-- A trigger can pick one of these effects as an action. It plays only while
-- OxMemes is switched on, at the player's own intensity; force is the trigger
-- card's preview, which plays it regardless.

OxedHub.MemedOn = OxedHub.MemedOn or {}

function OxedHub.MemedOn:IsEnabled()
    return settings and settings.enabled == true or false
end

function OxedHub.MemedOn:RunTriggerEffect(effectName, force)
    if not effectName or effectName == "" or effectName == "None" then return end
    if force then
        local effs = OxedHub.MemedOnEffects
        if effs and effs[effectName] and effs[effectName].Run then
            pcall(effs[effectName].Run, settings and settings.intensity or 70)
        end
        return
    end
    if not self:IsEnabled() then return end
    RunAlertEffect(effectName, settings.intensity)
end

-- ── Meme Toast: the card on screen when something matches ──────────────────
-- A dark card with a neutral edge and a coloured strip down its left side
-- (purple for chat, blue for a spell, red for a kill), a big emoji that pops
-- in, the match in large white text, a small "OxMemes · source" line and a
-- bar along the bottom that runs down until the card fades out.
-- Nothing animates the card's own alpha while a secret could drive it: the
-- card only ever shows plain text, so the fade is safe here.

local EMOJI = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\"
local TOAST_ICONS = {
    chat  = EMOJI .. "Tears of joy.png",
    spell = EMOJI .. "Star eyes.png",
    death = EMOJI .. "Skull.png",
}
local TOAST_COLOURS = {
    chat  = { 0.68, 0.45, 0.95 },
    spell = { 0.35, 0.65, 1.00 },
    death = { 1.00, 0.35, 0.35 },
}
local TOAST_HOLD = 3.0       -- seconds on screen before the fade
local TOAST_FADE = 0.5

local toastFrame = CreateFrame("Frame", "OxedHubMemedOnToast", UIParent, "BackdropTemplate")
toastFrame:SetSize(340, 62)
toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -115)
toastFrame:SetFrameStrata("FULLSCREEN_DIALOG")
toastFrame:SetClampedToScreen(true)
toastFrame:SetMovable(true)
toastFrame:EnableMouse(true)
toastFrame:RegisterForDrag("LeftButton")
toastFrame:SetScript("OnDragStart", toastFrame.StartMoving)
toastFrame:SetScript("OnDragStop", toastFrame.StopMovingOrSizing)
toastFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
})
toastFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
toastFrame:SetBackdropBorderColor(0.38, 0.38, 0.42, 1)
toastFrame:Hide()

-- A soft light across the top half, so the card is not one flat colour.
toastFrame.shine = toastFrame:CreateTexture(nil, "BORDER")
toastFrame.shine:SetPoint("TOPLEFT", 4, -4)
toastFrame.shine:SetPoint("TOPRIGHT", -4, -4)
toastFrame.shine:SetHeight(26)
toastFrame.shine:SetColorTexture(1, 1, 1, 0.04)

-- The coloured strip down the left edge.
toastFrame.accent = toastFrame:CreateTexture(nil, "ARTWORK")
toastFrame.accent:SetPoint("TOPLEFT", 4, -4)
toastFrame.accent:SetPoint("BOTTOMLEFT", 4, 4)
toastFrame.accent:SetWidth(3)

-- The emoji, and a faint glow of the accent colour behind it.
toastFrame.glow = toastFrame:CreateTexture(nil, "ARTWORK", nil, 1)
toastFrame.glow:SetSize(58, 58)
toastFrame.glow:SetPoint("LEFT", toastFrame, "LEFT", 4, 0)
toastFrame.glow:SetTexture("Interface\\Cooldown\\star4")
toastFrame.glow:SetBlendMode("ADD")
toastFrame.glow:SetAlpha(0.35)

toastFrame.icon = toastFrame:CreateTexture(nil, "ARTWORK", nil, 2)
toastFrame.icon:SetSize(46, 46)
toastFrame.icon:SetPoint("CENTER", toastFrame.glow, "CENTER", 0, 0)
toastFrame.icon:SetTexture(TOAST_ICONS.chat)

-- The emoji pops: a quick grow past full size and back.
do
    local pop = toastFrame.icon:CreateAnimationGroup()
    local grow = pop:CreateAnimation("Scale")
    local settle = pop:CreateAnimation("Scale")
    local ok = pcall(function()
        grow:SetScaleFrom(0.4, 0.4)
        grow:SetScaleTo(1.15, 1.15)
        settle:SetScaleFrom(1.15, 1.15)
        settle:SetScaleTo(1, 1)
    end)
    if not ok then
        pcall(grow.SetScale, grow, 1.15, 1.15)
        pcall(settle.SetScale, settle, 0.87, 0.87)
    end
    grow:SetDuration(0.18)
    grow:SetOrder(1)
    grow:SetSmoothing("OUT")
    settle:SetDuration(0.12)
    settle:SetOrder(2)
    settle:SetSmoothing("IN_OUT")
    toastFrame.pop = pop
end

toastFrame.caption = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
toastFrame.caption:SetPoint("TOPLEFT", toastFrame, "TOPLEFT", 66, -10)
toastFrame.caption:SetPoint("RIGHT", toastFrame, "RIGHT", -12, 0)
toastFrame.caption:SetJustifyH("LEFT")

toastFrame.title = toastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
toastFrame.title:SetPoint("TOPLEFT", toastFrame.caption, "BOTTOMLEFT", 0, -3)
toastFrame.title:SetPoint("RIGHT", toastFrame, "RIGHT", -12, 0)
toastFrame.title:SetJustifyH("LEFT")
toastFrame.title:SetTextColor(1, 1, 1)
if toastFrame.title.SetWordWrap then toastFrame.title:SetWordWrap(false) end

-- Kept for older callers; the source now rides in the caption.
toastFrame.sub = toastFrame.caption

-- The bar that runs down while the card is up.
toastFrame.timer = toastFrame:CreateTexture(nil, "OVERLAY")
toastFrame.timer:SetPoint("BOTTOMLEFT", toastFrame, "BOTTOMLEFT", 7, 5)
toastFrame.timer:SetHeight(2)
toastFrame.timerTrack = toastFrame:CreateTexture(nil, "ARTWORK")
toastFrame.timerTrack:SetPoint("BOTTOMLEFT", toastFrame, "BOTTOMLEFT", 7, 5)
toastFrame.timerTrack:SetPoint("BOTTOMRIGHT", toastFrame, "BOTTOMRIGHT", -7, 5)
toastFrame.timerTrack:SetHeight(2)
toastFrame.timerTrack:SetColorTexture(1, 1, 1, 0.08)

-- Slides down a little and fades in, holds, then fades out.
local toastShownAt = 0
local toastFull = 0
toastFrame:SetScript("OnUpdate", function(self)
    local age = GetTime() - toastShownAt
    if age < 0.2 then
        local t = age / 0.2
        self:SetAlpha(t)
        self.slide = 10 * (1 - t)
    elseif age < TOAST_HOLD then
        self:SetAlpha(1)
        self.slide = 0
    elseif age < TOAST_HOLD + TOAST_FADE then
        self:SetAlpha(1 - (age - TOAST_HOLD) / TOAST_FADE)
    else
        self:Hide()
        self:SetAlpha(1)
        return
    end
    local left = math.max(0, 1 - age / TOAST_HOLD)
    self.timer:SetWidth(math.max(0.01, toastFull * left))
    if self.slide ~= self.lastSlide then
        self.lastSlide = self.slide
        if self.home then
            self:ClearAllPoints()
            self:SetPoint(self.home[1], UIParent, self.home[3], self.home[4], self.home[5] + (self.slide or 0))
        end
    end
end)

-- kind: "chat", "spell" or "death"; icon overrides the emoji.
local function ShowMemeToast(title, subtitle, icon, kind)
    if not settings or not settings.showMemeToast then return end
    kind = TOAST_COLOURS[kind] and kind or "chat"
    local colour = TOAST_COLOURS[kind]
    toastFrame.accent:SetColorTexture(colour[1], colour[2], colour[3], 1)
    toastFrame.timer:SetColorTexture(colour[1], colour[2], colour[3], 0.9)
    toastFrame.glow:SetVertexColor(colour[1], colour[2], colour[3])
    toastFrame.caption:SetTextColor(colour[1], colour[2], colour[3])
    toastFrame.icon:SetTexture(icon or TOAST_ICONS[kind])

    -- A caster name can be a secret in a fight: then the line says less.
    local source = subtitle
    if issecretvalue and issecretvalue(source) then source = nil end
    if type(source) == "string" and source ~= "" then
        toastFrame.caption:SetText("OxMemes  |cff9a9aa0·|r  |cffd0d0d8" .. source .. "|r")
    else
        toastFrame.caption:SetText("OxMemes")
    end
    toastFrame.title:SetText(title or L["Meme Alert"])

    -- Where the player left it (dragged or not): the slide starts from there.
    if not toastFrame:IsShown() then
        local point, _, relPoint, x, y = toastFrame:GetPoint(1)
        toastFrame.home = { point or "TOP", nil, relPoint or "TOP", x or 0, y or -115 }
        toastFrame.lastSlide = nil
    end
    toastFull = toastFrame:GetWidth() - 14
    toastShownAt = GetTime()
    toastFrame:SetAlpha(0)
    toastFrame:Show()
    toastFrame.pop:Stop()
    toastFrame.pop:Play()
end

-- ── Keyword Matching Logic ──────────────────────────────────────────────────

local function MessageMatches(msg)
    if not msg or msg == "" or not settings or not settings.keywords then return false, nil, nil end
    local clean = StripHyperlinks(msg):lower()
    if clean == "" then return false, nil, nil end

    if settings.messageExclusions then
        for _, excl in ipairs(settings.messageExclusions) do
            if excl and excl ~= "" and clean:sub(1, #excl) == excl:lower() then
                return false, nil, nil
            end
        end
    end

    for _, kw in ipairs(settings.keywords) do
        if kw and kw ~= "" then
            local kwLow = kw:lower()
            local cfg = settings.keywordConfig and settings.keywordConfig[kwLow]
            if clean:find(kwLow, 1, true) then
                return true, kw, cfg
            end
            if cfg and cfg.variations then
                for _, var in ipairs(cfg.variations) do
                    if var and var ~= "" and clean:find(var:lower(), 1, true) then
                        return true, kw, cfg
                    end
                end
            end
        end
    end

    return false, nil, nil
end

local function TriggerAlert(matchedWord, categoryName, kwConfig)
    local now = GetTime()
    if (now - lastAlertTime) < DEDUP_WINDOW then return end
    lastAlertTime = now

    local key = tostring(matchedWord):lower()
    if settings.triggerOnce then
        if firedThisSession[key] then return end
        firedThisSession[key] = true
    end

    local effectName = kwConfig and kwConfig.effect or "Wobble"
    local soundID    = kwConfig and kwConfig.sound or settings.sound
    local intensity  = kwConfig and kwConfig.intensity or settings.intensity

    -- Execute sound, physical effect and Meme Toast!
    PlayAlertSound(soundID, SOUNDKIT and SOUNDKIT.RAID_WARNING)
    RunAlertEffect(effectName, intensity)
    local source = tostring(categoryName or "chat")
    source = OxedHub.T(source:sub(1, 1):upper() .. source:sub(2))
    ShowMemeToast(('"%s"'):format(tostring(matchedWord)), source, nil, "chat")

    if settings.showMatchMessage then
        print(PREFIX .. ('Matched |cffffd100"%s"|r (|cffaaaaaa%s|r) -> Effect: |cff00ff00%s|r'):format(tostring(matchedWord), categoryName or "chat", effectName))
    end
end

-- ── Chat Events Processor ───────────────────────────────────────────────────

local EVENT_CATEGORIES = {
    CHAT_MSG_SAY            = "chat",
    CHAT_MSG_YELL           = "chat",
    CHAT_MSG_CHANNEL        = "chat",
    CHAT_MSG_WHISPER        = "whisper",
    CHAT_MSG_WHISPER_INFORM = "whisper",
    CHAT_MSG_BN_WHISPER     = "whisper",
    CHAT_MSG_PARTY          = "party",
    CHAT_MSG_PARTY_LEADER   = "party",
    CHAT_MSG_RAID           = "party",
    CHAT_MSG_RAID_LEADER    = "party",
    CHAT_MSG_MONSTER_SAY    = "npc",
    CHAT_MSG_MONSTER_YELL   = "npc",
    CHAT_MSG_MONSTER_EMOTE  = "npc",
    CHAT_MSG_MONSTER_WHISPER= "npc",
    CHAT_MSG_RAID_BOSS_EMOTE= "npc",
    CHAT_MSG_RAID_BOSS_WHISPER = "npc",
    CHAT_MSG_SYSTEM         = "system",
    CHAT_MSG_LOOT           = "loot",
}

local function ProcessChatMessage(event, ...)
    if not settings or settings.enabled == false then return end

    local category = EVENT_CATEGORIES[event] or "chat"
    if category == "chat" and not settings.keywordChat then return end
    if category == "whisper" and not settings.keywordWhisper then return end
    if category == "party" and not settings.keywordParty then return end
    if category == "npc" and not settings.keywordNpc then return end
    if category == "system" and not settings.keywordSystem then return end
    if category == "loot" and not settings.keywordLoot then return end

    local msg = select(1, ...)
    if type(msg) ~= "string" or SecretValue(msg) then
        msg = select(2, ...)
        if type(msg) ~= "string" or SecretValue(msg) then return end
    end
    if msg == "" then return end
    if msg:find("%[OxedHub") or msg:find("%[MemedOn") or msg:find("%[OxMemes") then return end

    local hit, matched, cfg = MessageMatches(msg)
    if hit then
        TriggerAlert(matched, category, cfg)
    end
end

-- ── Spell Triggers Engine ───────────────────────────────────────────────────

-- force: the Test button. ⚠ It skips the dedup and once-per-session checks:
-- it used to share one 0.75 s window with every other alert, so a second
-- click (or any keyword alert just before) did nothing and Test looked broken.
-- Each spell also has its own window now, so one spell never silences another.
local lastSpellAlert = {}
local function TriggerSpellAlert(spellName, cfg, casterUnit, force)
    local now = GetTime()
    local key = "spell:" .. tostring(spellName):lower()
    if not force then
        if (now - (lastSpellAlert[key] or 0)) < DEDUP_WINDOW then return end
        if settings.triggerOnce then
            if firedThisSession[key] then return end
            firedThisSession[key] = true
        end
    end
    lastSpellAlert[key] = now

    local effectName = cfg and cfg.effect or "Tilt"
    local soundID    = cfg and cfg.sound or settings.sound

    PlayAlertSound(soundID, SOUNDKIT and SOUNDKIT.READY_CHECK)
    RunAlertEffect(effectName, settings.intensity)
    -- The spell's own icon when the game gives it, the emoji otherwise.
    local spellIcon
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellName)
        if ok and tex and not (issecretvalue and issecretvalue(tex)) then spellIcon = tex end
    end
    local caster = UnitName(casterUnit)
    if caster == nil or (issecretvalue and issecretvalue(caster)) then caster = "unit" end
    ShowMemeToast(spellName, (L["Spell Cast by %s"]):format(caster), spellIcon, "spell")

    if settings.showMatchMessage then
        print(PREFIX .. ('Spell Trigger: |cffffd100%s|r (|cffaaaaaa%s|r)'):format(spellName, UnitName(casterUnit) or "unit"))
    end
end

local function OnSpellCast(unit, spellID)
    if not settings or not settings.enabled or not settings.spellTriggersEnabled then return end
    if not spellID then return end
    local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if not spellName or spellName == "" then return end

    local cfg = settings.spellConfig and settings.spellConfig[spellName:lower()]
    if not cfg then return end

    -- Only the player's own casts are listened to (UNIT_SPELLCAST_SUCCEEDED
    -- for "player"), so "Self" needs no unit check here.
    TriggerSpellAlert(spellName, cfg, unit)
end

-- "Self" spells also fire when their buff lands on you (Power Infusion,
-- Leap of Faith cast by someone else). ⚠ Rewritten: it walked all 40 auras
-- on every aura change, called :lower() on names that are secret in combat
-- (an error), and replayed the sound every 4 s for as long as the buff stayed.
-- Now only the configured names are asked about, a secret answer counts as
-- "cannot tell" and changes nothing, and a buff fires once when it appears.
local auraPresent = {}   -- lower-case name -> true while the buff is up

local function AuraPresent(name)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
    if not ok or SecretValue(aura) then return nil end
    return aura ~= nil, aura
end

local function OnPlayerAuraUpdate()
    if not settings or not settings.enabled or not settings.spellTriggersEnabled then return end
    for _, sp in ipairs(settings.spellTriggers or {}) do
        local low = sp:lower()
        local cfg = settings.spellConfig and settings.spellConfig[low]
        if cfg and cfg.onlyOnMe then
            local present, aura = AuraPresent(sp)
            if present == true and not auraPresent[low] then
                auraPresent[low] = true
                -- Seen only now but applied long ago: it was hidden, not new.
                local fresh = true
                if type(aura) == "table" then
                    local exp, dur = aura.expirationTime, aura.duration
                    if not SecretValue(exp) and not SecretValue(dur) and type(exp) == "number"
                        and type(dur) == "number" and dur > 0 and exp > 0 then
                        fresh = (GetTime() - (exp - dur)) < 4
                    end
                end
                if fresh then TriggerSpellAlert(sp, cfg, "player") end
            elseif present == false then
                auraPresent[low] = nil
            end
        end
    end
end

-- ── Death Bell Engine (PvP/World Enemy Kill Alert) ──────────────────────────

local function UnitKey(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or type(name) ~= "string" or SecretValue(name) then return nil end
    if type(realm) == "string" and realm ~= "" and not SecretValue(realm) then
        return name .. "-" .. realm, name
    end
    return name, name
end

local function IsDeadTarget(unit)
    local ok, dead = pcall(UnitIsDeadOrGhost, unit)
    if not ok or SecretValue(dead) or not dead then return false end
    local okF, feign = pcall(UnitIsFeignDeath, unit)
    if okF and not SecretValue(feign) and feign then return false end
    return true
end

local function CheckDeathBellScope()
    if not settings or not settings.deathBell then return false end
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return settings.deathBellWorld == true
    elseif instanceType == "arena" then
        return settings.deathBellArena == true
    elseif instanceType == "pvp" then
        return settings.deathBellBG == true
    end
    return false
end

local function CheckUnitDeath(unit)
    if not CheckDeathBellScope() then return end
    if not UnitExists(unit) then return end
    local canAttack = UnitCanAttack("player", unit)
    if SecretValue(canAttack) or canAttack ~= true then return end

    local isPlayer = UnitIsPlayer(unit)
    if SecretValue(isPlayer) then isPlayer = false end
    if not isPlayer and not settings.deathBellNPC then return end

    if IsDeadTarget(unit) then
        local key, displayName = UnitKey(unit)
        if not key then return end
        local now = GetTime()
        if not lastDead[key] or (now - lastDead[key]) > 5 then
            lastDead[key] = now
            PlayAlertSound(settings.deathBellSound, 12867)
            ShowMemeToast(L["Enemy Down!"], displayName or key, nil, "death")
            if settings.showMatchMessage then
                print(PREFIX .. (L["|cffff2020Enemy down:|r %s"]):format(displayName or key))
            end
        end
    end
end

local function SweepTokens()
    if not CheckDeathBellScope() then return end
    if UnitExists("target") then CheckUnitDeath("target") end
    if UnitExists("focus") then CheckUnitDeath("focus") end
    for i = 1, 5 do
        local token = "arena" .. i
        if UnitExists(token) then CheckUnitDeath(token) end
    end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                local token = plate.UnitFrame and plate.UnitFrame.unit
                if token and UnitExists(token) then
                    CheckUnitDeath(token)
                end
            end
        end
    end
end

-- ── Lifecycle & Event Binding ───────────────────────────────────────────────

local function StartModule()
    EnsureData()
    watcher:UnregisterAllEvents()
    for ev in pairs(EVENT_CATEGORIES) do
        pcall(watcher.RegisterEvent, watcher, ev)
    end
    watcher:SetScript("OnEvent", function(_, event, ...)
        ProcessChatMessage(event, ...)
    end)

    spellWatcher:UnregisterAllEvents()
    spellWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    -- The player's only: every unit's aura change used to arrive here and be
    -- thrown away, hundreds of thousands of calls in a long session.
    spellWatcher:RegisterUnitEvent("UNIT_AURA", "player")
    spellWatcher:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            OnSpellCast(unit, spellID)
        elseif event == "UNIT_AURA" and unit == "player" then
            OnPlayerAuraUpdate()
        end
    end)

    deathWatcher:UnregisterAllEvents()
    deathWatcher:RegisterEvent("UNIT_DIED")
    deathWatcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    deathWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    deathWatcher:SetScript("OnEvent", function()
        SweepTokens()
        C_Timer.After(0.08, SweepTokens)
    end)
end

local function StopModule()
    watcher:UnregisterAllEvents()
    watcher:SetScript("OnEvent", nil)
    spellWatcher:UnregisterAllEvents()
    spellWatcher:SetScript("OnEvent", nil)
    deathWatcher:UnregisterAllEvents()
    deathWatcher:SetScript("OnEvent", nil)
    toastFrame:Hide()
    wipe(firedThisSession)
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.memedon
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.memedon = config
    end
    settings = config
    EnsureData()
end

-- ── Options UI ──────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("OxMemes", 540, 680)
        local w = optionsWindow

        -- Navigation Tabs
        local activeTab = 1
        local pageKeywords = CreateFrame("Frame", nil, w)
        local pageSpells   = CreateFrame("Frame", nil, w)
        local pageGeneral  = CreateFrame("Frame", nil, w)

        local pages = { pageKeywords, pageSpells, pageGeneral }
        for _, page in ipairs(pages) do
            page:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -70)
            page:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -16, 16)
            page:Hide()
        end

        local tabButtons = {}
        local tabNames = { L["Keywords"], L["Spells"], L["Settings & PvP"] }

        local function SelectTab(index)
            activeTab = index
            for i, btn in ipairs(tabButtons) do
                if i == index then
                    btn:LockHighlight()
                    btn:SetAlpha(1.0)
                else
                    btn:UnlockHighlight()
                    btn:SetAlpha(0.65)
                end
                pages[i]:SetShown(i == index)
            end
        end

        for i, name in ipairs(tabNames) do
            local tabBtn = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
            tabBtn:SetSize(160, 24)
            tabBtn:SetPoint("TOPLEFT", w, "TOPLEFT", 16 + (i - 1) * 168, -38)
            tabBtn:SetText(name)
            tabBtn:SetScript("OnClick", function() SelectTab(i) end)
            tabButtons[i] = tabBtn
        end

        -- ── Page 1: Keywords List ───────────────────────────────────────────
        local kwScroll = CreateFrame("ScrollFrame", "OxedHubMemedOnKwScroll", pageKeywords, "UIPanelScrollFrameTemplate")
        kwScroll:SetPoint("TOPLEFT", pageKeywords, "TOPLEFT", 0, 0)
        kwScroll:SetPoint("BOTTOMRIGHT", pageKeywords, "BOTTOMRIGHT", -24, 75)

        local kwContent = CreateFrame("Frame", nil, kwScroll)
        kwContent:SetSize(470, 800)
        kwScroll:SetScrollChild(kwContent)

        local kwRows = {}
        local function RefreshKeywordsList()
            for _, r in ipairs(kwRows) do r:Hide() end
            local y = 0
            for i, kw in ipairs(settings.keywords or {}) do
                local row = kwRows[i]
                if not row then
                    row = CreateFrame("Frame", nil, kwContent)
                    row:SetSize(460, 30)

                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
                    row.text:SetWidth(140)
                    row.text:SetJustifyH("LEFT")

                    -- Effect button
                    row.effectBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.effectBtn:SetSize(90, 22)
                    row.effectBtn:SetPoint("LEFT", row.text, "RIGHT", 4, 0)

                    -- Sound picker button
                    row.soundBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.soundBtn:SetSize(100, 22)
                    row.soundBtn:SetPoint("LEFT", row.effectBtn, "RIGHT", 6, 0)

                    -- Test button
                    row.testBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.testBtn:SetSize(48, 22)
                    row.testBtn:SetPoint("LEFT", row.soundBtn, "RIGHT", 6, 0)
                    row.testBtn:SetText(L["Test"])

                    -- Delete button
                    row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.delBtn:SetSize(28, 22)
                    row.delBtn:SetPoint("LEFT", row.testBtn, "RIGHT", 6, 0)
                    row.delBtn:SetText("X")

                    -- A long sound or effect name ran out over the next
                    -- button; it is cut to the button now, the full name in
                    -- the tooltip.
                    for _, b in ipairs({ row.effectBtn, row.soundBtn }) do
                        b:SetText(" ")
                        local fs = b:GetFontString()
                        if fs then
                            fs:SetWidth(b:GetWidth() - 12)
                            fs:SetWordWrap(false)
                        end
                        b:SetScript("OnEnter", function(self)
                            local shown = self:GetText()
                            if not shown or shown == "" then return end
                            GameTooltip:SetOwner(self, "ANCHOR_TOP")
                            GameTooltip:SetText(shown, 1, 1, 1)
                            GameTooltip:Show()
                        end)
                        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end

                    kwRows[i] = row
                end

                local kwLow = kw:lower()
                local cfg = settings.keywordConfig and settings.keywordConfig[kwLow]
                if not cfg then
                    cfg = { sound = "", effect = "Wobble", intensity = 70 }
                    settings.keywordConfig[kwLow] = cfg
                end

                row.text:SetText(kw)
                row.effectBtn:SetText(cfg.effect or "Wobble")
                row.effectBtn:SetScript("OnClick", function()
                    local list = OxedHub.MEMEDON_EFFECTS_LIST or { "Wobble", "Explosion", "Blackhole", "Rickroll", "Wow", "Tilt", "Earthquake", "Glitch", "None" }
                    local curIdx = 1
                    for idx, name in ipairs(list) do
                        if name == cfg.effect then curIdx = idx; break end
                    end
                    local nextIdx = (curIdx % #list) + 1
                    cfg.effect = list[nextIdx]
                    row.effectBtn:SetText(cfg.effect)
                end)

                row.soundBtn:SetText(cfg.sound ~= "" and API:SoundName(cfg.sound, "Sound") or L["Pick Sound"])
                row.soundBtn:SetScript("OnClick", function()
                    local Triggers = OxedHub.Triggers
                    if Triggers and Triggers.ShowSoundPicker then
                        Triggers:ShowSoundPicker({ actions = { sound = cfg.sound or "" } }, "sound", function(id)
                            cfg.sound = (id and id ~= "None" and id ~= "none") and id or ""
                            row.soundBtn:SetText(cfg.sound ~= "" and API:SoundName(cfg.sound, "Sound") or L["Pick Sound"])
                        end)
                    end
                end)

                row.testBtn:SetScript("OnClick", function()
                    TriggerAlert(kw, "test", cfg)
                end)

                row.delBtn:SetScript("OnClick", function()
                    table.remove(settings.keywords, i)
                    RefreshKeywordsList()
                end)

                row:SetPoint("TOPLEFT", kwContent, "TOPLEFT", 0, y)
                row:Show()
                y = y - 34
            end
            kwContent:SetHeight(math.max(200, -y + 20))
        end

        -- Add Keyword Bar at bottom of Page 1
        local addBox = CreateFrame("EditBox", nil, pageKeywords, "InputBoxTemplate")
        addBox:SetSize(180, 22)
        addBox:SetPoint("BOTTOMLEFT", pageKeywords, "BOTTOMLEFT", 6, 20)
        addBox:SetAutoFocus(false)

        local addBtn = CreateFrame("Button", nil, pageKeywords, "UIPanelButtonTemplate")
        addBtn:SetSize(110, 24)
        addBtn:SetPoint("LEFT", addBox, "RIGHT", 10, 0)
        addBtn:SetText(L["Add Keyword"])
        addBtn:SetScript("OnClick", function()
            local text = addBox:GetText():trim()
            if text ~= "" then
                table.insert(settings.keywords, text)
                settings.keywordConfig[text:lower()] = { sound = "", effect = "Wobble", intensity = 70 }
                addBox:SetText("")
                RefreshKeywordsList()
            end
        end)

        local resetKwBtn = CreateFrame("Button", nil, pageKeywords, "UIPanelButtonTemplate")
        resetKwBtn:SetSize(130, 24)
        resetKwBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
        resetKwBtn:SetText(L["Reset Presets"])
        resetKwBtn:SetScript("OnClick", function()
            wipe(settings.keywords)
            for _, kw in ipairs(PRESET_KEYWORDS) do table.insert(settings.keywords, kw) end
            for k, v in pairs(PRESET_KEYWORD_CONFIG) do
                settings.keywordConfig[k] = { sound = v.sound, effect = v.effect, intensity = v.intensity }
            end
            RefreshKeywordsList()
        end)

        -- ── Page 2: Spells List ─────────────────────────────────────────────
        local spScroll = CreateFrame("ScrollFrame", "OxedHubMemedOnSpScroll", pageSpells, "UIPanelScrollFrameTemplate")
        spScroll:SetPoint("TOPLEFT", pageSpells, "TOPLEFT", 0, 0)
        spScroll:SetPoint("BOTTOMRIGHT", pageSpells, "BOTTOMRIGHT", -24, 60)

        local spContent = CreateFrame("Frame", nil, spScroll)
        spContent:SetSize(470, 600)
        spScroll:SetScrollChild(spContent)

        local spRows = {}
        local function RefreshSpellsList()
            for _, r in ipairs(spRows) do r:Hide() end
            local y = 0
            for i, sp in ipairs(settings.spellTriggers or {}) do
                local row = spRows[i]
                if not row then
                    row = CreateFrame("Frame", nil, spContent)
                    row:SetSize(460, 30)

                    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    row.text:SetPoint("LEFT", row, "LEFT", 10, 0)
                    row.text:SetWidth(130)
                    row.text:SetJustifyH("LEFT")

                    row.onlyMe = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.onlyMe:SetSize(20, 20)
                    row.onlyMe:SetPoint("LEFT", row.text, "RIGHT", 4, 0)
                    row.onlyMe.text:SetText(L["Self"])

                    row.effectBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.effectBtn:SetSize(85, 22)
                    row.effectBtn:SetPoint("LEFT", row.onlyMe.text, "RIGHT", 6, 0)

                    row.soundBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.soundBtn:SetSize(90, 22)
                    row.soundBtn:SetPoint("LEFT", row.effectBtn, "RIGHT", 6, 0)

                    row.testBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.testBtn:SetSize(44, 22)
                    row.testBtn:SetPoint("LEFT", row.soundBtn, "RIGHT", 6, 0)
                    row.testBtn:SetText(L["Test"])

                    row.delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.delBtn:SetSize(28, 22)
                    row.delBtn:SetPoint("LEFT", row.testBtn, "RIGHT", 6, 0)
                    row.delBtn:SetText("X")

                    -- A long sound or effect name ran out over the next
                    -- button; it is cut to the button now, the full name in
                    -- the tooltip.
                    for _, b in ipairs({ row.effectBtn, row.soundBtn }) do
                        b:SetText(" ")
                        local fs = b:GetFontString()
                        if fs then
                            fs:SetWidth(b:GetWidth() - 12)
                            fs:SetWordWrap(false)
                        end
                        b:SetScript("OnEnter", function(self)
                            local shown = self:GetText()
                            if not shown or shown == "" then return end
                            GameTooltip:SetOwner(self, "ANCHOR_TOP")
                            GameTooltip:SetText(shown, 1, 1, 1)
                            GameTooltip:Show()
                        end)
                        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end

                    spRows[i] = row
                end

                local spLow = sp:lower()
                local cfg = settings.spellConfig and settings.spellConfig[spLow]
                if not cfg then
                    cfg = { sound = "", effect = "Tilt", onlyOnMe = false }
                    settings.spellConfig[spLow] = cfg
                end

                row.text:SetText(sp)
                row.onlyMe:SetChecked(cfg.onlyOnMe == true)
                row.onlyMe:SetScript("OnClick", function(btn)
                    cfg.onlyOnMe = btn:GetChecked() and true or false
                end)

                row.effectBtn:SetText(cfg.effect or "Tilt")
                row.effectBtn:SetScript("OnClick", function()
                    local list = OxedHub.MEMEDON_EFFECTS_LIST or { "Wobble", "Explosion", "Blackhole", "Rickroll", "Wow", "Tilt", "Earthquake", "Glitch", "None" }
                    local curIdx = 1
                    for idx, name in ipairs(list) do
                        if name == cfg.effect then curIdx = idx; break end
                    end
                    local nextIdx = (curIdx % #list) + 1
                    cfg.effect = list[nextIdx]
                    row.effectBtn:SetText(cfg.effect)
                end)

                row.soundBtn:SetText(cfg.sound ~= "" and API:SoundName(cfg.sound, "Sound") or L["Pick Sound"])
                row.soundBtn:SetScript("OnClick", function()
                    local Triggers = OxedHub.Triggers
                    if Triggers and Triggers.ShowSoundPicker then
                        Triggers:ShowSoundPicker({ actions = { sound = cfg.sound or "" } }, "sound", function(id)
                            cfg.sound = (id and id ~= "None" and id ~= "none") and id or ""
                            row.soundBtn:SetText(cfg.sound ~= "" and API:SoundName(cfg.sound, "Sound") or L["Pick Sound"])
                        end)
                    end
                end)

                row.testBtn:SetScript("OnClick", function()
                    TriggerSpellAlert(sp, cfg, "player", true)
                end)

                row.delBtn:SetScript("OnClick", function()
                    table.remove(settings.spellTriggers, i)
                    RefreshSpellsList()
                end)

                row:SetPoint("TOPLEFT", spContent, "TOPLEFT", 0, y)
                row:Show()
                y = y - 34
            end
            spContent:SetHeight(math.max(200, -y + 20))
        end

        local addSpBox = CreateFrame("EditBox", nil, pageSpells, "InputBoxTemplate")
        addSpBox:SetSize(200, 22)
        addSpBox:SetPoint("BOTTOMLEFT", pageSpells, "BOTTOMLEFT", 6, 20)
        addSpBox:SetAutoFocus(false)

        local addSpBtn = CreateFrame("Button", nil, pageSpells, "UIPanelButtonTemplate")
        addSpBtn:SetSize(110, 24)
        addSpBtn:SetPoint("LEFT", addSpBox, "RIGHT", 10, 0)
        addSpBtn:SetText(L["Add Spell"])
        -- What was typed is looked up first: a name, a spell id or a
        -- shift-clicked link all become the game's own spelling of the name,
        -- which is what a cast is matched against. A name the game does not
        -- know (another class's spell is only known by id) is still added,
        -- with a warning that it must be spelled exactly.
        local function ResolveSpell(text)
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            local id = tonumber(text) or tonumber(text:match("|Hspell:(%d+)") or "")
            text = text:gsub("|H.-|h%[?(.-)%]?|h", "%1"):match("^%s*(.-)%s*$")
            local query = id or text
            if C_Spell and C_Spell.GetSpellInfo then
                local ok, info = pcall(C_Spell.GetSpellInfo, query)
                if ok and type(info) == "table" and type(info.name) == "string" and not SecretValue(info.name) then
                    return info.name, true
                end
            end
            return text, false
        end
        local function AddTypedSpell()
            local raw = addSpBox:GetText() or ""
            if raw:match("^%s*$") then return end
            local name, known = ResolveSpell(raw)
            if name == "" then return end
            local low = name:lower()
            for _, existing in ipairs(settings.spellTriggers) do
                if existing:lower() == low then
                    print(PREFIX .. (L["|cffffd100%s|r is already in the list."]):format(name))
                    addSpBox:SetText("")
                    return
                end
            end
            table.insert(settings.spellTriggers, name)
            settings.spellConfig[low] = settings.spellConfig[low] or { sound = "", effect = "Tilt", onlyOnMe = false }
            if not known then
                print(PREFIX .. (L["|cffffd100%s|r is not a spell this character knows by name. It is added, but it must match the spell's exact name; a spell id also works."]):format(name))
            end
            addSpBox:SetText("")
            addSpBox:ClearFocus()
            RefreshSpellsList()
        end
        addSpBtn:SetScript("OnClick", AddTypedSpell)
        addSpBox:SetScript("OnEnterPressed", AddTypedSpell)

        -- Suggestions while typing: the same spell search the triggers use
        -- (your spellbook plus the common spells of other classes). The list
        -- opens upward, the box being at the bottom of the window. Clicking a
        -- spell adds it at once.
        local suggest = CreateFrame("Frame", nil, pageSpells, "BackdropTemplate")
        suggest:SetPoint("BOTTOMLEFT", addSpBox, "TOPLEFT", -6, 2)
        suggest:SetSize(240, 10)
        suggest:SetFrameStrata("TOOLTIP")
        suggest:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        suggest:SetBackdropColor(0, 0, 0, 0.95)
        suggest:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        suggest:Hide()
        local suggestRows = {}

        local function ShowSuggestions(text)
            local Triggers = OxedHub.Triggers
            if not (Triggers and Triggers.SearchPlayerSpells) or not text or text:match("^%s*$") or tonumber(text) then
                suggest:Hide()
                return
            end
            local ok, results = pcall(Triggers.SearchPlayerSpells, Triggers, text, 8, true)
            if not ok or type(results) ~= "table" or #results == 0 then
                suggest:Hide()
                return
            end
            for i, spell in ipairs(results) do
                local b = suggestRows[i]
                if not b then
                    b = CreateFrame("Button", nil, suggest)
                    b:SetSize(228, 22)
                    b.icon = b:CreateTexture(nil, "ARTWORK")
                    b.icon:SetSize(18, 18)
                    b.icon:SetPoint("LEFT", 2, 0)
                    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
                    b.text:SetPoint("RIGHT", b, "RIGHT", -2, 0)
                    b.text:SetJustifyH("LEFT")
                    b.text:SetWordWrap(false)
                    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    suggestRows[i] = b
                end
                -- Best match closest to the box, at the bottom.
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", suggest, "BOTTOMLEFT", 6, 5 + (i - 1) * 23)
                b.icon:SetTexture(spell.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.text:SetText(spell.name)
                b:SetScript("OnClick", function()
                    addSpBox:SetText(spell.id and tostring(spell.id) or spell.name)
                    suggest:Hide()
                    AddTypedSpell()
                end)
                b:Show()
            end
            for i = #results + 1, #suggestRows do suggestRows[i]:Hide() end
            suggest:SetHeight(#results * 23 + 10)
            suggest:Show()
        end

        local suggestTimer, hideTimer
        addSpBox:SetScript("OnTextChanged", function(self, user)
            if not user then return end
            if suggestTimer then suggestTimer:Cancel() end
            local text = self:GetText()
            suggestTimer = C_Timer.NewTimer(0.15, function()
                if self:GetText() == text then ShowSuggestions(text) end
            end)
        end)
        addSpBox:SetScript("OnEscapePressed", function(self) suggest:Hide(); self:ClearFocus() end)
        addSpBox:SetScript("OnEditFocusLost", function()
            if suggestTimer then suggestTimer:Cancel() end
            -- A moment, so a click on a suggestion lands before it closes.
            hideTimer = C_Timer.NewTimer(0.25, function() suggest:Hide() end)
        end)
        addSpBox:SetScript("OnEditFocusGained", function(self)
            if hideTimer then hideTimer:Cancel() end
            ShowSuggestions(self:GetText())
        end)
        pageSpells:HookScript("OnHide", function() suggest:Hide() end)

        -- ── Page 3: General Settings & Death Bell ───────────────────────────
        local function AddCheck(parent, cfg, key, label, yOffset)
            local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
            cb:SetSize(22, 22)
            cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
            cb.text:SetFontObject("GameFontHighlight")
            cb.text:SetText(label)
            cb:SetChecked(cfg[key] == true)
            cb:SetScript("OnClick", function(btn)
                cfg[key] = btn:GetChecked() and true or false
            end)
            return cb
        end

        local y = -10
        AddCheck(pageGeneral, settings, "showMatchMessage", L["Show match line in chat"], y); y = y - 26
        AddCheck(pageGeneral, settings, "showMemeToast", L["|cffffd100Show Meme Toast floating HUD banner|r (OxedHub Original)"], y); y = y - 26
        AddCheck(pageGeneral, settings, "triggerOnce", L["Trigger each keyword once per session"], y); y = y - 26
        AddCheck(pageGeneral, settings, "effectsEnabled", L["Enable physical UI & screen effects"], y); y = y - 30

        local chkLabel = pageGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chkLabel:SetPoint("TOPLEFT", pageGeneral, "TOPLEFT", 10, y)
        chkLabel:SetText(L["Chat Channels Monitored:"])
        y = y - 22

        AddCheck(pageGeneral, settings, "keywordChat", L["Say, Yell & Public Channels"], y); y = y - 24
        AddCheck(pageGeneral, settings, "keywordWhisper", L["Whispers (direct & Battle.net)"], y); y = y - 24
        AddCheck(pageGeneral, settings, "keywordParty", L["Party & Raid Chat"], y); y = y - 24
        AddCheck(pageGeneral, settings, "keywordNpc", L["NPC Dialogue & Boss Emotes"], y); y = y - 24
        AddCheck(pageGeneral, settings, "keywordSystem", L["System & Game Alert Messages"], y); y = y - 24
        AddCheck(pageGeneral, settings, "keywordLoot", L["Loot & Crafting Messages"], y); y = y - 32

        local dbLabel = pageGeneral:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dbLabel:SetPoint("TOPLEFT", pageGeneral, "TOPLEFT", 10, y)
        dbLabel:SetText(L["Death Bell (PvP Kill Alerts):"])
        y = y - 22

        AddCheck(pageGeneral, settings, "deathBell", L["|cffff4040Enable Death Bell (ring sound on enemy death)|r"], y); y = y - 24
        AddCheck(pageGeneral, settings, "deathBellArena", L["Ring in Arenas"], y); y = y - 24
        AddCheck(pageGeneral, settings, "deathBellBG", L["Ring in Battlegrounds"], y); y = y - 24
        AddCheck(pageGeneral, settings, "deathBellWorld", L["Ring in World PvP"], y); y = y - 24
        AddCheck(pageGeneral, settings, "deathBellNPC", L["Ring for Hostile NPCs too"], y); y = y - 32

        local dbSoundBtn = CreateFrame("Button", nil, pageGeneral, "UIPanelButtonTemplate")
        dbSoundBtn:SetSize(160, 24)
        dbSoundBtn:SetPoint("TOPLEFT", pageGeneral, "TOPLEFT", 10, y)
        dbSoundBtn:SetText(settings.deathBellSound ~= "" and API:SoundName(settings.deathBellSound, "Bell Sound") or L["Death Bell Sound"])
        dbSoundBtn:SetScript("OnClick", function()
            local Triggers = OxedHub.Triggers
            if Triggers and Triggers.ShowSoundPicker then
                Triggers:ShowSoundPicker({ actions = { sound = settings.deathBellSound or "" } }, "sound", function(id)
                    settings.deathBellSound = (id and id ~= "None" and id ~= "none") and id or ""
                    dbSoundBtn:SetText(settings.deathBellSound ~= "" and API:SoundName(settings.deathBellSound, "Bell Sound") or L["Death Bell Sound"])
                end)
            end
        end)

        SelectTab(1)
        RefreshKeywordsList()
        RefreshSpellsList()
    end

    optionsWindow:Show()
end

-- ── Slash Command ───────────────────────────────────────────────────────────

SLASH_OXEDHUBMEMEDON1 = "/memedon"
SLASH_OXEDHUBMEMEDON2 = "/mo"
SlashCmdList.OXEDHUBMEMEDON = function(msg)
    msg = (msg or ""):trim()
    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "test" then
        TriggerAlert(arg ~= "" and arg or "Test Alert", "slash test", { effect = "Wobble", intensity = 75 })
    elseif cmd == "add" and arg ~= "" then
        EnsureData()
        table.insert(settings.keywords, arg)
        settings.keywordConfig[arg:lower()] = { sound = "", effect = "Wobble", intensity = 70 }
        print(PREFIX .. ('Added keyword: |cffffd100"%s"|r'):format(arg))
    elseif cmd == "clear" then
        EnsureData()
        wipe(settings.keywords)
        print(PREFIX .. L["All keywords cleared."])
    elseif cmd == "reset" then
        wipe(firedThisSession)
        wipe(lastDead)
        print(PREFIX .. L["Session trigger limits reset."])
    elseif cmd == "list" then
        EnsureData()
        print(PREFIX .. (L["Keywords (%d): %s"]):format(#settings.keywords, table.concat(settings.keywords, ", ")))
    else
        ShowOptions()
    end
end

-- ── Module Registration ─────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then StartModule() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "memedon",
        name     = "OxMemes",   -- renamed from MemedOn; id and saved settings unchanged
        version  = "4.5.0",
        updated  = 20261113.1,  -- a new meme card on screen, emoji icons
        author   = "Oxed",
        category = "chat",
        keywords = { "meme", "memedon", "sound", "chat", "trigger", "wobble", "explosion", "blackhole", "death", "bell" },
        desc     = "Scans chat, NPC dialogue and spells for keywords to trigger physical screen effects and sounds.",
        icon     = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Tears of joy.png",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            EnsureData()
            StartModule()
        end,

        OnDisable = function()
            StopModule()
        end,
    })
end)
