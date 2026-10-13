-- ============================================================================
-- KickSync (built-in OxedHub module)
-- Multi-feature M+ party utility for your group:
--
--   * Party Interrupt Tracker: tracks who can interrupt and who is on cooldown
--     with class-colored bars, cooldown countdowns, and "Ready" indicators.
--   * Failed Kick Watchdog: turns the cooldown number RED if a kick is wasted /
--     overlapped with no target cast stopped, and GREEN on successful interrupts.
--   * Smart Kick Rotation: highlights the next player in line for kicks.
--   * M+ Keystone Manager: reads and announces group Mythic+ keys with 1 click.
--   * Smart Misdirect: auto-assists Hunters & Rogues in targeting the party tank.
--   * OxedHub SoundPicker: custom audio alerts for Kick Ready, Success & Wasted.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled              = false,   -- off until player enables it (OxedHub standard)
    locked               = false,   -- unlock to drag
    showTitle            = true,
    showSolo             = true,    -- show even when not in party (for testing)
    showInParty          = true,
    showInRaid           = false,   -- only party by default
    showInArena          = true,

    -- Layout
    width                = 220,
    barHeight            = 20,
    scale                = 1.0,
    spacing              = 3,
    growUp               = false,
    point                = "CENTER",
    x                    = 260,
    y                    = 60,

    -- Tracker features
    showIcon             = true,
    showFailedRed        = true,    -- turn number red on wasted / overlapped kick
    showNextRotation     = true,    -- badge [1], [2] for next kick order
    announceInterrupts   = false,   -- announce successful kicks to party chat
    announceFailed       = false,   -- announce wasted kicks to party chat

    -- Sound alerts (OxedHub SoundPicker IDs)
    soundReady           = "",      -- when your kick comes off CD
    soundSuccess         = "",      -- when someone lands an interrupt
    soundWasted          = "",      -- when someone wastes a kick

    -- Smart Misdirect
    smartMisdirect       = false,

    -- Keystone sharing & Defensives
    keystonesEnabled     = true,
    announceKeystonesChat = true,
    defensiveOverlay     = true,
}

local settings
local optionsWindow
local mainFrame
local bars = {}
local memberData = {}       -- [unit] = { name, class, spec, spellID, spellName, icon, cd, expires, status }
local activeKicks = {}      -- [guid] = { time, caster, spellName, target, status }
local rotationIndex = 1

local PREFIX = "|cff0091edKickSync:|r "
local WATCHDOG_DELAY = 0.65 -- seconds to determine if a kick actually stopped a cast

-- ── Spec & Interrupt Database (Single Source of Truth) ─────────────────────

local SPEC_REGISTRY = {
    -- Death Knight
    [250] = { class = "DEATHKNIGHT", spellID = 47528,  cd = 15, name = "Mind Freeze", icon = 237527 },
    [251] = { class = "DEATHKNIGHT", spellID = 47528,  cd = 15, name = "Mind Freeze", icon = 237527 },
    [252] = { class = "DEATHKNIGHT", spellID = 47528,  cd = 15, name = "Mind Freeze", icon = 237527 },
    -- Demon Hunter
    [577] = { class = "DEMONHUNTER", spellID = 183752, cd = 15, name = "Disrupt", icon = 1305153 },
    [581] = { class = "DEMONHUNTER", spellID = 183752, cd = 15, name = "Disrupt", icon = 1305153 },
    -- Druid
    [102] = { class = "DRUID", spellID = 78675,  cd = 45, name = "Solar Beam", icon = 252188 },
    [103] = { class = "DRUID", spellID = 106839, cd = 15, name = "Skull Bash", icon = 236946 },
    [104] = { class = "DRUID", spellID = 106839, cd = 15, name = "Skull Bash", icon = 236946 },
    [105] = { class = "DRUID", noKick = true },
    -- Evoker
    [1467] = { class = "EVOKER", spellID = 351338, cd = 20, name = "Quell", icon = 4622469 },
    [1468] = { class = "EVOKER", spellID = 351338, cd = 20, name = "Quell", icon = 4622469 },
    [1473] = { class = "EVOKER", spellID = 351338, cd = 20, name = "Quell", icon = 4622469 },
    -- Hunter
    [253] = { class = "HUNTER", spellID = 147362, cd = 24, name = "Counter Shot", icon = 249170 },
    [254] = { class = "HUNTER", spellID = 147362, cd = 24, name = "Counter Shot", icon = 249170 },
    [255] = { class = "HUNTER", spellID = 187707, cd = 15, name = "Muzzle", icon = 1376045 },
    -- Mage
    [62]  = { class = "MAGE", spellID = 2139, cd = 24, name = "Counterspell", icon = 135856 },
    [63]  = { class = "MAGE", spellID = 2139, cd = 24, name = "Counterspell", icon = 135856 },
    [64]  = { class = "MAGE", spellID = 2139, cd = 24, name = "Counterspell", icon = 135856 },
    -- Monk
    [268] = { class = "MONK", spellID = 116705, cd = 15, name = "Spear Hand Strike", icon = 608940 },
    [269] = { class = "MONK", spellID = 116705, cd = 15, name = "Spear Hand Strike", icon = 608940 },
    [270] = { class = "MONK", noKick = true },
    -- Paladin
    [65]  = { class = "PALADIN", noKick = true },
    [66]  = { class = "PALADIN", spellID = 96231, cd = 15, name = "Rebuke", icon = 523893 },
    [70]  = { class = "PALADIN", spellID = 96231, cd = 15, name = "Rebuke", icon = 523893 },
    -- Priest
    [256] = { class = "PRIEST", noKick = true },
    [257] = { class = "PRIEST", noKick = true },
    [258] = { class = "PRIEST", spellID = 15487, cd = 45, name = "Silence", icon = 136199 },
    -- Rogue
    [259] = { class = "ROGUE", spellID = 1766, cd = 15, name = "Kick", icon = 132219 },
    [260] = { class = "ROGUE", spellID = 1766, cd = 15, name = "Kick", icon = 132219 },
    [261] = { class = "ROGUE", spellID = 1766, cd = 15, name = "Kick", icon = 132219 },
    -- Shaman
    [262] = { class = "SHAMAN", spellID = 57994, cd = 12, name = "Wind Shear", icon = 136018 },
    [263] = { class = "SHAMAN", spellID = 57994, cd = 12, name = "Wind Shear", icon = 136018 },
    [264] = { class = "SHAMAN", spellID = 57994, cd = 12, name = "Wind Shear", icon = 136018 },
    -- Warlock
    [265] = { class = "WARLOCK", spellID = 119910, cd = 24, name = "Command Demon", icon = 136173 },
    [266] = { class = "WARLOCK", spellID = 119910, cd = 24, name = "Command Demon", icon = 136173 },
    [267] = { class = "WARLOCK", spellID = 119910, cd = 24, name = "Command Demon", icon = 136173 },
    -- Warrior
    [71]  = { class = "WARRIOR", spellID = 6552, cd = 15, name = "Pummel", icon = 132337 },
    [72]  = { class = "WARRIOR", spellID = 6552, cd = 15, name = "Pummel", icon = 132337 },
    [73]  = { class = "WARRIOR", spellID = 6552, cd = 15, name = "Pummel", icon = 132337 },
}

local CLASS_FALLBACK = {
    DEATHKNIGHT = { spellID = 47528,  cd = 15, name = "Mind Freeze", icon = 237527 },
    DEMONHUNTER = { spellID = 183752, cd = 15, name = "Disrupt", icon = 1305153 },
    DRUID       = { spellID = 106839, cd = 15, name = "Skull Bash", icon = 236946 },
    EVOKER      = { spellID = 351338, cd = 20, name = "Quell", icon = 4622469 },
    HUNTER      = { spellID = 147362, cd = 24, name = "Counter Shot", icon = 249170 },
    MAGE        = { spellID = 2139,   cd = 24, name = "Counterspell", icon = 135856 },
    MONK        = { spellID = 116705, cd = 15, name = "Spear Hand Strike", icon = 608940 },
    PALADIN     = { spellID = 96231,  cd = 15, name = "Rebuke", icon = 523893 },
    PRIEST      = { spellID = 15487,  cd = 45, name = "Silence", icon = 136199 },
    ROGUE       = { spellID = 1766,   cd = 15, name = "Kick", icon = 132219 },
    SHAMAN      = { spellID = 57994,  cd = 12, name = "Wind Shear", icon = 136018 },
    WARLOCK     = { spellID = 119910, cd = 24, name = "Command Demon", icon = 136173 },
    WARRIOR     = { spellID = 6552,   cd = 15, name = "Pummel", icon = 132337 },
}

local CLASS_COLORS = RAID_CLASS_COLORS or {
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE        = { r = 0.41, g = 0.80, b = 0.94 },
    MONK        = { r = 0.00, g = 1.00, b = 0.59 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    WARLOCK     = { r = 0.58, g = 0.51, b = 0.79 },
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
}

-- ── Safe Helpers ────────────────────────────────────────────────────────────

local function SecretValue(val)
    return issecretvalue and issecretvalue(val) and true or false
end

local function PlaySoundAlert(soundID, fallbackKitID)
    if soundID and soundID ~= "" and OxedHub.Sounds and OxedHub.Sounds.Play then
        local ok = pcall(OxedHub.Sounds.Play, OxedHub.Sounds, soundID)
        if ok then return end
    end
    if fallbackKitID and PlaySound then
        pcall(PlaySound, fallbackKitID, "Master")
    end
end

local function EnsureData()
    if not settings then return end
    settings.partyKeys = type(settings.partyKeys) == "table" and settings.partyKeys or {}
end

-- ── Unit Resolver ───────────────────────────────────────────────────────────

local function GetUnitInterruptInfo(unit)
    if not UnitExists(unit) then return nil end
    local _, class = UnitClass(unit)
    if not class then return nil end

    local spec = nil
    if UnitIsUnit(unit, "player") then
        local specIdx = GetSpecialization and GetSpecialization()
        if specIdx then spec = GetSpecializationInfo(specIdx) end
    end

    local info = spec and SPEC_REGISTRY[spec]
    if not info and class then info = CLASS_FALLBACK[class] end
    if not info or info.noKick then return nil end

    local name = UnitName(unit)
    if not name or SecretValue(name) then name = unit end

    return {
        unit      = unit,
        guid      = UnitGUID(unit),
        name      = name,
        class     = class,
        spellID   = info.spellID,
        spellName = info.name,
        icon      = info.icon,
        cd        = info.cd or 15,
        expires   = 0,
        status    = "ready", -- "ready", "cooldown", "success", "wasted"
    }
end

-- ── UI Tracker Frame ────────────────────────────────────────────────────────

local function CreateMainTracker()
    if mainFrame then return mainFrame end

    local f = CreateFrame("Frame", "OxedHubKickSyncTracker", UIParent, "BackdropTemplate")
    f:SetSize(settings.width or 220, 140)
    f:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 260, settings.y or 60)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if not settings.locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, _, px, py = self:GetPoint(1)
        if pt then settings.point, settings.x, settings.y = pt, px, py end
    end)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
    f:SetBackdropBorderColor(0, 0, 0, 0.9)

    -- Title Bar
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -4)
    f.title:SetText("|cff0091edKickSync|r Party Interrupts")

    f.keyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.keyBtn:SetSize(42, 16)
    f.keyBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -2)
    f.keyBtn:SetText("Keys")
    f.keyBtn:SetScript("OnClick", function()
        if SlashCmdList.OXEDHUBKICKSYNC then
            SlashCmdList.OXEDHUBKICKSYNC("keys")
        end
    end)

    mainFrame = f
    return mainFrame
end

local function GetBar(index)
    local bar = bars[index]
    if not bar then
        bar = CreateFrame("StatusBar", nil, mainFrame, "BackdropTemplate")
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)

        bar:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        bar:SetBackdropColor(0.1, 0.1, 0.12, 0.9)
        bar:SetBackdropBorderColor(0, 0, 0, 0.8)

        bar.icon = bar:CreateTexture(nil, "ARTWORK")
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        bar.name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.name:SetJustifyH("LEFT")

        bar.timer = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        bar.timer:SetJustifyH("RIGHT")

        bar.rotBadge = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bar.rotBadge:SetTextColor(1, 0.82, 0)

        bars[index] = bar
    end
    return bar
end

-- ── Display Layout & Update ─────────────────────────────────────────────────

local function UpdateBars()
    if not mainFrame or not settings or not settings.enabled then return end

    local inInstance, instanceType = IsInInstance()
    local inParty = IsInGroup()
    local inRaid = IsInRaid()

    local shouldShow = false
    if settings.showSolo and not inParty then shouldShow = true
    elseif inParty and not inRaid and settings.showInParty then shouldShow = true
    elseif inRaid and settings.showInRaid then shouldShow = true
    elseif instanceType == "arena" and settings.showInArena then shouldShow = true
    end

    if not shouldShow then
        mainFrame:Hide()
        return
    end
    mainFrame:Show()
    mainFrame:SetScale(settings.scale or 1.0)
    mainFrame:SetWidth(settings.width or 220)

    local units = {}
    if inParty then
        table.insert(units, "player")
        local num = GetNumGroupMembers()
        for i = 1, (inRaid and math.min(num, 5) or 4) do
            local u = (inRaid and "raid" .. i or "party" .. i)
            if UnitExists(u) and not UnitIsUnit(u, "player") then
                table.insert(units, u)
            end
        end
    else
        table.insert(units, "player")
    end

    local now = GetTime()
    local bH = settings.barHeight or 20
    local bW = (settings.width or 220) - (settings.showIcon and (bH + 6) or 12)
    local curY = settings.showTitle and -22 or -6

    -- Find next ready interrupter for rotation
    local nextUpUnit = nil
    for _, u in ipairs(units) do
        local m = memberData[u]
        if m and m.expires <= now then
            nextUpUnit = u
            break
        end
    end

    for i, u in ipairs(units) do
        local m = memberData[u]
        if not m or m.guid ~= UnitGUID(u) then
            m = GetUnitInterruptInfo(u)
            memberData[u] = m
        end

        local bar = GetBar(i)
        if m then
            bar:SetSize(bW, bH)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", settings.showIcon and (bH + 6) or 6, curY)

            -- Icon
            if settings.showIcon then
                bar.icon:SetSize(bH, bH)
                bar.icon:ClearAllPoints()
                bar.icon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
                bar.icon:SetTexture(m.icon or 132219)
                bar.icon:Show()
            else
                bar.icon:Hide()
            end

            -- Color
            local c = CLASS_COLORS[m.class] or { r = 0.5, g = 0.5, b = 0.5 }
            bar:SetStatusBarColor(c.r, c.g, c.b, 0.9)

            -- Text
            bar.name:ClearAllPoints()
            bar.name:SetPoint("LEFT", bar, "LEFT", 4, 0)
            bar.name:SetPoint("RIGHT", bar, "RIGHT", -55, 0)
            bar.name:SetText(m.name or u)

            bar.timer:ClearAllPoints()
            bar.timer:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

            local left = m.expires - now
            if left > 0 then
                bar:SetMinMaxValues(0, m.cd or 15)
                bar:SetValue(m.cd - left)
                if m.status == "wasted" and settings.showFailedRed then
                    bar.timer:SetText(("|cffff2020%.1fs|r"):format(left))
                else
                    bar.timer:SetText(("%.1fs"):format(left))
                end
            else
                bar:SetMinMaxValues(0, 1)
                bar:SetValue(1)
                if u == nextUpUnit and settings.showNextRotation then
                    bar.timer:SetText("|cff00ff00READY [NEXT]|r")
                else
                    bar.timer:SetText("|cff00ff00READY|r")
                end
            end

            bar:Show()
            curY = curY - bH - (settings.spacing or 3)
        else
            bar:Hide()
        end
    end

    for j = #units + 1, #bars do bars[j]:Hide() end
    mainFrame:SetHeight(math.abs(curY) + 6)
end

-- ── Interrupt & Watchdog Processor ──────────────────────────────────────────

local function TriggerInterruptCooldown(unit, spellID)
    local m = memberData[unit] or GetUnitInterruptInfo(unit)
    if not m then return end

    local now = GetTime()
    m.expires = now + (m.cd or 15)
    m.status = "pending"
    memberData[unit] = m

    local guid = UnitGUID(unit)
    if guid then
        activeKicks[guid] = {
            time      = now,
            caster    = m.name or unit,
            spellName = m.spellName or "Kick",
            unit      = unit,
            status    = "pending",
        }

        -- Watchdog timer to verify if a cast was successfully stopped
        C_Timer.After(WATCHDOG_DELAY, function()
            local kick = activeKicks[guid]
            if kick and kick.status == "pending" then
                -- No interrupt detected within watchdog window -> WASTED!
                kick.status = "wasted"
                m.status = "wasted"
                if settings.announceFailed and IsInGroup() then
                    SendChatMessage(("[KickSync] %s used %s (no cast interrupted / wasted)!"):format(kick.caster, kick.spellName), "PARTY")
                end
                if UnitIsUnit(unit, "player") and settings.soundWasted ~= "" then
                    PlaySoundAlert(settings.soundWasted, 882)
                end
            end
        end)
    end
end

local function OnInterruptLand(casterGUID, casterName, targetName, spellName)
    local kick = casterGUID and activeKicks[casterGUID]
    if kick then
        kick.status = "success"
        local m = memberData[kick.unit]
        if m then m.status = "success" end
    end

    PlaySoundAlert(settings.soundSuccess, SOUNDKIT and SOUNDKIT.HEROIC_ITEM_LOOT_CHECK)

    if settings.announceInterrupts and IsInGroup() then
        SendChatMessage(("[KickSync] %s interrupted %s!"):format(casterName or "Party", spellName or "Spell"), "PARTY")
    end
end

-- ── Keystone Sharing & Smart Misdirect ──────────────────────────────────────

local function AnnounceKeystones()
    local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    local mapName = mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)

    if mapName and level and level > 0 then
        local msg = ("[KickSync Keystone] My Key: +%d %s"):format(level, mapName)
        print(PREFIX .. msg)
        if IsInGroup() then SendChatMessage(msg, IsInRaid() and "RAID" or "PARTY") end
    else
        print(PREFIX .. "No Mythic+ keystone found in your bags for this week.")
    end
end

local function SetupSmartMisdirect()
    if not settings or not settings.smartMisdirect then return end
    local _, class = UnitClass("player")
    if class ~= "HUNTER" and class ~= "ROGUE" then return end

    local tankUnit = nil
    for i = 1, GetNumGroupMembers() do
        local u = "party" .. i
        if UnitGroupRolesAssigned and UnitGroupRolesAssigned(u) == "TANK" then
            tankUnit = u
            break
        end
    end

    if tankUnit and not InCombatLockdown() then
        SetFocus(tankUnit)
        print(PREFIX .. ("Smart Misdirect: Tank (%s) focused!"):format(UnitName(tankUnit) or tankUnit))
    end
end

-- ── Lifecycle & Event Handlers ──────────────────────────────────────────────

local function StartModule()
    EnsureData()
    CreateMainTracker()

    local DEF = OxedHub.KickSyncDefensives
    if DEF and settings.defensiveOverlay then
        DEF:SetEnabled(true)
    end
    local KL = OxedHub.KickSyncKeystones
    if KL and settings.keystonesEnabled then
        KL:Initialize()
    end
    local SM = OxedHub.KickSyncMisdirect
    if SM and settings.smartMisdirect then
        SM:UpdateMacro()
    end

    local updateTicker
    updateTicker = C_Timer.NewTicker(0.05, function()
        if not settings or not settings.enabled then
            if updateTicker then updateTicker:Cancel() end
            return
        end
        UpdateBars()
    end)

    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "party1", "party2", "party3", "party4")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            -- Match against any interrupt spell
            for _, info in pairs(CLASS_FALLBACK) do
                if info.spellID == spellID then
                    TriggerInterruptCooldown(unit, spellID)
                    break
                end
            end
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            local targetName = UnitName(unit)
            OnInterruptLand(nil, "Party", targetName, "Spell")
        elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
            wipe(memberData)
            SetupSmartMisdirect()
            local d = OxedHub.KickSyncDefensives
            if d and settings.defensiveOverlay then
                d:RefreshAll()
            end
        end
    end)
    mainFrame._eventWatcher = f
end

local function StopModule()
    if mainFrame then
        if mainFrame._eventWatcher then
            mainFrame._eventWatcher:UnregisterAllEvents()
        end
        mainFrame:Hide()
    end
    local d = OxedHub.KickSyncDefensives
    if d then
        d:SetEnabled(false)
    end
end

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.kicksync
    if type(config) ~= "table" then
        config = {}
    end
    OxedHubDB.modules.kicksync = config
    settings = config
    EnsureData()
end

-- ── Options UI ──────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("KickSync", 500, 700)
        local w = optionsWindow

        w:AddCheckbox(settings, "locked", "Lock tracker frame", "Unlocked: drag with left mouse button.")
        w:AddCheckbox(settings, "showTitle", "Show title & keys header bar", nil, UpdateBars)
        w:AddCheckbox(settings, "showIcon", "Show interrupt spell icon", nil, UpdateBars)
        w:AddCheckbox(settings, "showFailedRed", "|cffff4040Turn CD red on wasted / overlapped kicks|r (Watchdog)")
        w:AddCheckbox(settings, "showNextRotation", "Show [NEXT] badge on ready interrupter", nil, UpdateBars)
        w:AddCheckbox(settings, "announceInterrupts", "Announce landed kicks to party chat")
        w:AddCheckbox(settings, "announceFailed", "Announce wasted kicks to party chat")

        w:AddSlider(settings, "width", "Tracker width", 140, 340, 10, "%s: %d px", UpdateBars)
        w:AddSlider(settings, "barHeight", "Bar height", 14, 34, 2, "%s: %d px", UpdateBars)
        w:AddSlider(settings, "scale", "Tracker scale", 0.6, 1.8, 0.05, "%s: %.2f", UpdateBars)

        w:AddSoundPicker(settings, "soundReady", "Your Kick Ready sound", "None")
        w:AddSoundPicker(settings, "soundSuccess", "Party Interrupt Landed sound", "Heroic Loot")
        w:AddSoundPicker(settings, "soundWasted", "Wasted / Overlapped Kick sound", "Error")

        -- Companion features
        w:AddCheckbox(settings, "defensiveOverlay", "|cff00ff96Defensive Overlay|r (Active big defensives on party unit frames)")
        w:AddModuleLinks("Companion modules", { "smartmisdirect" })

        local btnRow = CreateFrame("Frame", nil, w)
        btnRow:SetSize(460, 30)
        btnRow:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)

        local keyWinBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        keyWinBtn:SetSize(145, 24)
        keyWinBtn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)
        keyWinBtn:SetText("Keystones Window")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(keyWinBtn) end
        keyWinBtn:SetScript("OnClick", function()
            local KL = OxedHub.KickSyncKeystones
            if KL then
                KL:ToggleWindow()
            else
                AnnounceKeystones()
            end
        end)

        local annKeyBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        annKeyBtn:SetSize(145, 24)
        annKeyBtn:SetPoint("LEFT", keyWinBtn, "RIGHT", 6, 0)
        annKeyBtn:SetText("Announce Keystones")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(annKeyBtn) end
        annKeyBtn:SetScript("OnClick", function()
            local KL = OxedHub.KickSyncKeystones
            if KL then
                KL:AnnounceToChat()
            else
                AnnounceKeystones()
            end
        end)

        local previewBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        previewBtn:SetSize(120, 24)
        previewBtn:SetPoint("LEFT", annKeyBtn, "RIGHT", 6, 0)
        previewBtn:SetText("Preview Bars")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(previewBtn) end
        previewBtn:SetScript("OnClick", function()
            if mainFrame then mainFrame:SetShown(not mainFrame:IsShown()) end
        end)

        w.cursorY = w.cursorY - 38

        local UF = OxedHub.KickSyncUnitFrames
        local providerName = UF and UF:GetDetectedProviderName() or "Blizzard Compact Party"
        w:AddNote("|cff888888Detected Unit Frames: |cffffffff" .. providerName .. "|r")
        w:AddNote("Commands: /kicksync or /ksync (options), /kskeys (keystones window), /kskey (announce keys).")
    end

    optionsWindow:Show()
end

-- ── Slash Commands ──────────────────────────────────────────────────────────

SLASH_OXEDHUBKICKSYNC1 = "/kicksync"
SLASH_OXEDHUBKICKSYNC2 = "/ksync"
SLASH_OXEDHUBKICKSYNC3 = "/kskey"
SLASH_OXEDHUBKICKSYNC4 = "/kskeys"
SlashCmdList.OXEDHUBKICKSYNC = function(msg)
    msg = (msg or ""):trim():lower()
    local KL = OxedHub.KickSyncKeystones
    if msg == "keys" or msg == "key" then
        if KL then
            KL:ToggleWindow()
        else
            AnnounceKeystones()
        end
    elseif msg == "announce" then
        if KL then
            KL:AnnounceToChat()
        else
            AnnounceKeystones()
        end
    elseif msg == "test" then
        if mainFrame then mainFrame:SetShown(not mainFrame:IsShown()) end
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
        id       = "kicksync",
        name     = "KickSync",
        version  = "4.2.3",
        updated  = 20261013.9,
        author   = "Oxed",
        category = "groups",
        keywords = { "kicksync", "interrupt", "kick", "party", "m+", "dungeon", "keystone", "cd", "watchdog" },
        desc     = "M+ party interrupt tracker with cooldowns, wasted-kick watchdog, and keystone sharing.",
        icon     = "Interface\\Icons\\Ability_Kick",

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
