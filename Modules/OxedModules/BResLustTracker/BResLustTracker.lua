-- ============================================================================
-- BRes & Lust Tracker (built-in OxedHub module)
-- Tracks Battle Resurrection charges and Sated / Bloodlust debuffs on screen.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local PREFIX = "|cffffd100BResLust:|r "

local SATED_IDS = {
    [57723]  = true, -- Exhaustion (Heroism - Alliance Shaman)
    [57724]  = true, -- Sated (Bloodlust - Horde Shaman)
    [80354]  = true, -- Temporal Displacement (Time Warp - Mage)
    [264689] = true, -- Fatigued (Hunter Pet Primal Rage)
    [390435] = true, -- Exhaustion (Evoker Fury of the Aspects)
    [160455] = true, -- Fatigued (Netherwinds)
    [357745] = true, -- Sated
}
local BRES_SPELL_ID = 20484

local DEFAULTS = {
    enabled = false,           -- off until the player switches it on (OxedHub standard)
    locked = true,              -- Locked by default! No mover box on screen
    hideInactive = false,       -- false: icons always visible; true: auto-hide when inactive
    style = "compact",          -- "compact" (sleek WeakAura-style icons) or "full" (with text labels)
    orientation = "horizontal", -- "horizontal" (side-by-side) or "vertical" (stacked)
    iconSize = 44,              -- 32 to 64 px
    scale = 1.0,                -- 0.5 to 2.0
    alpha = 1.0,                -- 0.2 to 1.0
    trackBRes = true,           -- track Battle Res charges
    trackLust = true,           -- track Bloodlust / Heroism
    showTime = true,            -- show remaining cooldown timer
    showCharges = true,         -- show BRes charges count
    playSound = true,           -- sound alert when Bloodlust is activated
    sound = "bloodlust",        -- chosen sound ID / file
    inCombatOnly = false,
    showInDungeon = true,
    showInRaid = true,
    showInWorld = true,
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = 120,
}

local settings
local MainFrame, BResFrame, LustFrame
local activeAuraExpiration = 0
local startTime = 0
local lastBResStart = 0
local lastLustStart = 0
local isInitialized = false
local previewMode = false
local currentLustIcon = nil
local activeSoundHandle = nil
local lastSoundTime = 0

-- Forward declarations
local StartTracking, StopTracking, UpdateDisplay, UpdateLayout, CreateUI

local function FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    seconds = math.floor(seconds)
    if seconds >= 60 then
        return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
    else
        return string.format("%ds", seconds)
    end
end

-- Fixed text (preview, empty): forget the cached second so the live timer redraws.
local function PlainTimer(fs, text)
    fs.shownSecond = nil
    fs:SetText(text)
end

-- Builds the timer text only when the shown second changes, not every tick.
local function SetTimer(fs, remain)
    local whole = (settings and settings.showTime and remain and remain > 0) and math.floor(remain) or -1
    if fs.shownSecond == whole then return end
    fs.shownSecond = whole
    fs:SetText(whole >= 0 and FormatTime(whole) or "")
end

-- Sound library integration with OxedHub
local function SoundName(id)
    if id == "None" or id == "none" then
        return "None"
    end
    if not id or id == "" or id == "bloodlust" or id == "oxedhub_bloodlust" then
        return "Bloodlust (Default)"
    end
    if id == "s1" or id == "oxedhub_breslust_horn_1" then return "Horn 1" end
    if id == "s2" or id == "oxedhub_breslust_horn_2" then return "Horn 2" end
    if id == "s3" or id == "oxedhub_breslust_horn_3" then return "Horn 3" end
    if id == "s4" or id == "oxedhub_breslust_horn_4" then return "Horn 4" end
    if id == "s5" or id == "oxedhub_breslust_horn_5" then return "Horn 5" end

    local customLib = (OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds())
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
    if customLib[id] and customLib[id].name then return customLib[id].name end

    if OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[id] then
        return OxedHub.GENERATED_SOUND_CATALOG[id].name or id
    end

    if OxedHub.Sounds and OxedHub.Sounds.ResolvePathOrId then
        local resolved = OxedHub.Sounds:ResolvePathOrId(id)
        if customLib[resolved] and customLib[resolved].name then return customLib[resolved].name end
        if OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[resolved] then
            return OxedHub.GENERATED_SOUND_CATALOG[resolved].name or resolved
        end
    end

    return id
end

local function GetSoundPath(id)
    if not id or id == "" or id == "None" or id == "none" then
        return nil
    end
    if id == "bloodlust" or id == "oxedhub_bloodlust" then
        return "Interface\\AddOns\\OxedHub\\Modules\\OxedModules\\BResLustTracker\\Sounds\\bloodlust.ogg"
    end
    local bMap = {
        s1 = "S1.ogg",
        s2 = "S2.ogg",
        s3 = "S3.ogg",
        s4 = "S4.ogg",
        s5 = "S5.ogg",
        oxedhub_breslust_horn_1 = "S1.ogg",
        oxedhub_breslust_horn_2 = "S2.ogg",
        oxedhub_breslust_horn_3 = "S3.ogg",
        oxedhub_breslust_horn_4 = "S4.ogg",
        oxedhub_breslust_horn_5 = "S5.ogg",
    }
    if bMap[id:lower()] then
        return "Interface\\AddOns\\OxedHub\\Modules\\OxedModules\\BResLustTracker\\Sounds\\" .. bMap[id:lower()]
    end

    local customLib = (OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds())
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
    if customLib[id] and customLib[id].filePath then
        return customLib[id].filePath
    end

    if OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[id] and OxedHub.GENERATED_SOUND_CATALOG[id].filePath then
        return OxedHub.GENERATED_SOUND_CATALOG[id].filePath
    end

    if OxedHub.Sounds and OxedHub.Sounds.ResolvePathOrId then
        local resolved = OxedHub.Sounds:ResolvePathOrId(id)
        if customLib[resolved] and customLib[resolved].filePath then
            return customLib[resolved].filePath
        end
        if OxedHub.GENERATED_SOUND_CATALOG and OxedHub.GENERATED_SOUND_CATALOG[resolved] and OxedHub.GENERATED_SOUND_CATALOG[resolved].filePath then
            return OxedHub.GENERATED_SOUND_CATALOG[resolved].filePath
        end
    end

    return nil
end

local function PlayLustSound(specificId)
    local id = specificId or (settings and settings.sound) or "oxedhub_bloodlust"
    if id == "None" or id == "none" then return end
    if not specificId and settings and not settings.playSound then return end

    local now = GetTime()
    if not specificId and (now - lastSoundTime < 5) then return end
    if not specificId then lastSoundTime = now end

    if activeSoundHandle and StopSound then
        pcall(StopSound, activeSoundHandle)
        activeSoundHandle = nil
    end

    local path = GetSoundPath(id)
    local channel = (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings and OxedHub.db.profile.settings.soundChannel) or "Master"

    if OxedHub.Sounds and OxedHub.Sounds.Play then
        local ok, handle = pcall(OxedHub.Sounds.Play, OxedHub.Sounds, path or id, SoundName(id))
        if ok and handle then
            activeSoundHandle = handle
            return
        end
    end

    if path then
        local willPlay, handle = PlaySoundFile(path, channel)
        if willPlay then
            activeSoundHandle = handle
            return
        end
    end

    local willPlay, handle = PlaySoundFile("Interface\\AddOns\\OxedHub\\Modules\\OxedModules\\BResLustTracker\\Sounds\\bloodlust.ogg", "Master")
    if willPlay then activeSoundHandle = handle end
end

-- ── UI Creation & Layout ────────────────────────────────────────────────────

-- What the last layout was built from. The display ticks ten times a second
-- and asked for a full re-layout (fonts, anchors, backdrop) every time.
local laidOut = {}
local LAYOUT_KEYS = { "style", "orientation", "iconSize", "locked", "trackBRes", "trackLust", "scale", "alpha" }

UpdateLayout = function()
    if not MainFrame then return end
    if settings and laidOut.frame == MainFrame then
        local same = true
        for _, key in ipairs(LAYOUT_KEYS) do
            if laidOut[key] ~= settings[key] then same = false break end
        end
        if same then return end
    end
    laidOut.frame = MainFrame
    for _, key in ipairs(LAYOUT_KEYS) do laidOut[key] = settings and settings[key] end

    local isCompact = (settings and settings.style) ~= "full"
    local isHoriz = (settings and settings.orientation) ~= "vertical"
    local sz = (settings and tonumber(settings.iconSize)) or 44
    local isUnlocked = not (settings and settings.locked)

    local showBRes = (settings and settings.trackBRes) ~= false
    local showLust = (settings and settings.trackLust) ~= false
    local activeCount = (showBRes and 1 or 0) + (showLust and 1 or 0)
    if activeCount == 0 then activeCount = 1 end

    local textWidth = isCompact and 0 or 68
    local itemWidth = sz + textWidth
    local gap = 8
    local pad = 6
    local topPad = isUnlocked and 24 or pad
    local bottomPad = isUnlocked and 18 or pad

    -- Calculate content dimensions
    local contentW
    if isHoriz then
        contentW = (itemWidth * activeCount) + (gap * (activeCount - 1))
    else
        contentW = itemWidth
    end

    local minUnlockedW = isUnlocked and 210 or 0
    local frameW = math.max(contentW + pad * 2, minUnlockedW)
    local frameH
    if isHoriz then
        frameH = sz + topPad + bottomPad
    else
        frameH = (sz * activeCount) + (gap * (activeCount - 1)) + topPad + bottomPad
    end

    MainFrame:SetSize(frameW, frameH)
    MainFrame:SetScale((settings and settings.scale) or 1.0)
    MainFrame:SetAlpha((settings and settings.alpha) or 1.0)

    -- Mover frame styling (Clean dark slate with gold accent, NO ugly green)
    if isUnlocked then
        MainFrame:EnableMouse(true)
        MainFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.85)
        MainFrame:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        if MainFrame.moverTitle then MainFrame.moverTitle:Show() end
        if MainFrame.moverHint then MainFrame.moverHint:Show() end
    else
        MainFrame:EnableMouse(false)
        MainFrame:SetBackdropColor(0, 0, 0, 0)
        MainFrame:SetBackdropBorderColor(0, 0, 0, 0)
        if MainFrame.moverTitle then MainFrame.moverTitle:Hide() end
        if MainFrame.moverHint then MainFrame.moverHint:Hide() end
    end

    -- Icon sizes
    if BResFrame then BResFrame:SetSize(sz, sz) end
    if LustFrame then LustFrame:SetSize(sz, sz) end

    local leftOffset = isUnlocked and math.floor((frameW - contentW) / 2) or pad

    -- BRes Typography & Anchors
    if BResFrame then
        BResFrame:ClearAllPoints()
        BResFrame.count:ClearAllPoints()
        BResFrame.timer:ClearAllPoints()
        BResFrame.label:ClearAllPoints()

        BResFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", leftOffset, -topPad)

        if isCompact then
            BResFrame.label:Hide()
            BResFrame.count:SetPoint("BOTTOMRIGHT", BResFrame, "BOTTOMRIGHT", -2, 2)
            BResFrame.count:SetFont("Fonts\\FRIZQT__.TTF", math.max(12, math.floor(sz * 0.40)), "OUTLINE")
            BResFrame.timer:SetPoint("TOP", BResFrame, "TOP", 0, -3)
            BResFrame.timer:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(sz * 0.28)), "OUTLINE")
            BResFrame.timer:SetTextColor(1, 1, 1)
        else
            BResFrame.label:Show()
            BResFrame.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            BResFrame.label:SetText(L["Res:"])
            BResFrame.label:SetTextColor(1, 1, 1)
            BResFrame.label:SetPoint("TOPLEFT", BResFrame, "TOPRIGHT", 6, -2)

            BResFrame.count:SetPoint("LEFT", BResFrame.label, "RIGHT", 4, 0)
            BResFrame.count:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")

            BResFrame.timer:SetPoint("BOTTOMLEFT", BResFrame, "BOTTOMRIGHT", 6, 4)
            BResFrame.timer:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
            BResFrame.timer:SetTextColor(1, 1, 1)
        end
    end

    -- Lust Typography & Anchors
    if LustFrame then
        LustFrame:ClearAllPoints()
        LustFrame.label:ClearAllPoints()
        LustFrame.timer:ClearAllPoints()

        if isHoriz then
            if showBRes then
                LustFrame:SetPoint("TOPLEFT", BResFrame, "TOPRIGHT", textWidth + gap, 0)
            else
                LustFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", pad, -topPad)
            end
        else
            if showBRes then
                LustFrame:SetPoint("TOPLEFT", BResFrame, "BOTTOMLEFT", 0, -gap)
            else
                LustFrame:SetPoint("TOPLEFT", MainFrame, "TOPLEFT", pad, -topPad)
            end
        end

        if isCompact then
            LustFrame.label:Hide()
            LustFrame.timer:SetPoint("CENTER", LustFrame, "CENTER", 0, 0)
            LustFrame.timer:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, math.floor(sz * 0.32)), "OUTLINE")
            LustFrame.timer:SetTextColor(1, 0.82, 0)
        else
            LustFrame.label:Show()
            LustFrame.label:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            LustFrame.label:SetText(L["Sated"])
            LustFrame.label:SetTextColor(1, 0.6, 0)
            LustFrame.label:SetPoint("TOPLEFT", LustFrame, "TOPRIGHT", 6, -2)

            LustFrame.timer:SetPoint("BOTTOMLEFT", LustFrame, "BOTTOMRIGHT", 6, 4)
            LustFrame.timer:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
            LustFrame.timer:SetTextColor(1, 1, 1)
        end
    end
end

CreateUI = function()
    if MainFrame then return end

    MainFrame = CreateFrame("Frame", "OxedHubBResLustTracker", UIParent, "BackdropTemplate")
    MainFrame:SetMovable(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetClampedToScreen(true)

    MainFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    MainFrame:SetScript("OnDragStart", function(self)
        if not (settings and settings.locked) then self:StartMoving() end
    end)
    MainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if settings then
            settings.point = p
            settings.relativePoint = rp
            settings.x = math.floor(x + 0.5)
            settings.y = math.floor(y + 0.5)
        end
    end)

    MainFrame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and not (settings and settings.locked) then
            settings.locked = true
            UpdateLayout()
            UpdateDisplay()
            print(PREFIX .. L["Position locked. Tracker will now only show during combat/dungeons/heroism."])
        end
    end)

    MainFrame.moverTitle = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    MainFrame.moverTitle:SetPoint("TOP", MainFrame, "TOP", 0, -4)
    MainFrame.moverTitle:SetText("|cffffd100BRes & Lust|r")
    MainFrame.moverTitle:Hide()

    MainFrame.moverHint = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    MainFrame.moverHint:SetPoint("BOTTOM", MainFrame, "BOTTOM", 0, 3)
    MainFrame.moverHint:SetText(L["Drag to move · Right-click to lock"])
    MainFrame.moverHint:Hide()

    MainFrame:ClearAllPoints()
    MainFrame:SetPoint((settings and settings.point) or "CENTER", UIParent, (settings and settings.relativePoint) or "CENTER", (settings and settings.x) or 0, (settings and settings.y) or 120)

    -- Row 1: BRes Frame
    BResFrame = CreateFrame("Frame", nil, MainFrame)
    BResFrame.Icon = BResFrame:CreateTexture(nil, "BACKGROUND")
    BResFrame.Icon:SetAllPoints()
    BResFrame.Icon:SetTexture(136080)
    BResFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    BResFrame.Border = CreateFrame("Frame", nil, BResFrame, "BackdropTemplate")
    BResFrame.Border:SetPoint("TOPLEFT", -1, 1)
    BResFrame.Border:SetPoint("BOTTOMRIGHT", 1, -1)
    BResFrame.Border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    BResFrame.Border:SetBackdropBorderColor(0, 0, 0, 0.8)

    BResFrame.Cooldown = CreateFrame("Cooldown", nil, BResFrame, "CooldownFrameTemplate")
    BResFrame.Cooldown:SetAllPoints()
    BResFrame.Cooldown:SetHideCountdownNumbers(true)

    BResFrame.label = BResFrame:CreateFontString(nil, "OVERLAY")
    BResFrame.count = BResFrame:CreateFontString(nil, "OVERLAY")
    BResFrame.timer = BResFrame:CreateFontString(nil, "OVERLAY")

    -- Row 2: Lust Frame
    LustFrame = CreateFrame("Frame", nil, MainFrame)
    LustFrame.Icon = LustFrame:CreateTexture(nil, "BACKGROUND")
    LustFrame.Icon:SetAllPoints()
    LustFrame.Icon:SetTexture(136012)
    LustFrame.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    LustFrame.Border = CreateFrame("Frame", nil, LustFrame, "BackdropTemplate")
    LustFrame.Border:SetPoint("TOPLEFT", -1, 1)
    LustFrame.Border:SetPoint("BOTTOMRIGHT", 1, -1)
    LustFrame.Border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    LustFrame.Border:SetBackdropBorderColor(0, 0, 0, 0.8)

    LustFrame.Cooldown = CreateFrame("Cooldown", nil, LustFrame, "CooldownFrameTemplate")
    LustFrame.Cooldown:SetAllPoints()
    LustFrame.Cooldown:SetHideCountdownNumbers(true)

    LustFrame.label = LustFrame:CreateFontString(nil, "OVERLAY")
    LustFrame.timer = LustFrame:CreateFontString(nil, "OVERLAY")

    local MSQ = LibStub and LibStub("Masque", true)
    if MSQ and MSQ.Group then
        local group = MSQ:Group("OxedHub - BRes & Lust")
        if BResFrame then group:AddButton(BResFrame, { Icon = BResFrame.Icon, Cooldown = BResFrame.Cooldown }) end
        if LustFrame then group:AddButton(LustFrame, { Icon = LustFrame.Icon, Cooldown = LustFrame.Cooldown }) end
    end

    UpdateLayout()
    MainFrame:Hide()
end

local cachedCharges, chargesAskedAt, chargesDirty = nil, 0, true

-- ── Display Engine ──────────────────────────────────────────────────────────

UpdateDisplay = function()
    if not settings or not settings.enabled then 
        if MainFrame then MainFrame:Hide() end
        return 
    end

    if not MainFrame then CreateUI() end
    UpdateLayout()

    -- 1. Preview / Test Mode
    if previewMode then
        MainFrame:Show()
        if settings.trackBRes then
            BResFrame:Show()
            BResFrame.count:SetText(settings.showCharges and "2" or "")
            BResFrame.count:SetTextColor(0, 1, 0)
            PlainTimer(BResFrame.timer, settings.showTime and "3:45" or "")
            BResFrame.Cooldown:SetCooldown(GetTime() - 75, 300)
        else
            BResFrame:Hide()
        end

        if settings.trackLust then
            LustFrame:Show()
            LustFrame.Icon:SetTexture(136012)
            PlainTimer(LustFrame.timer, settings.showTime and "7:20" or "")
            LustFrame.Cooldown:SetCooldown(GetTime() - 160, 600)
        else
            LustFrame:Hide()
        end
        return
    end

    -- 2. Unlock / Move Mode
    if not settings.locked then
        MainFrame:Show()
        if settings.trackBRes then
            BResFrame:Show()
            BResFrame.count:SetText(settings.showCharges and "3" or "")
            BResFrame.count:SetTextColor(0, 1, 0)
            PlainTimer(BResFrame.timer, "") -- Full charges: clean view with no timer
            BResFrame.Cooldown:Clear()
        else
            BResFrame:Hide()
        end

        if settings.trackLust then
            LustFrame:Show()
            LustFrame.Icon:SetTexture(136012)
            PlainTimer(LustFrame.timer, settings.showTime and "10:00" or "")
            LustFrame.Cooldown:Clear()
        else
            LustFrame:Hide()
        end
        return
    end

    -- 3. Live In-Game Tracking (when locked)
    local shouldShow = true
    local _, instanceType = GetInstanceInfo()
    if instanceType == "party" and not settings.showInDungeon then shouldShow = false end
    if instanceType == "raid" and not settings.showInRaid then shouldShow = false end
    if instanceType == "none" and not settings.showInWorld then shouldShow = false end
    if shouldShow and settings.inCombatOnly and not InCombatLockdown() then shouldShow = false end

    if not shouldShow then 
        MainFrame:Hide()
        return 
    end

    local bresActive = false
    local lustActive = false

    -- Update BRes
    if settings.trackBRes then
        -- Each ask hands back a new table; ten a second was most of this
        -- module's garbage. Charges change on SPELL_UPDATE_CHARGES or a zone
        -- change, and the countdown only needs start and duration.
        local nowT = GetTime()
        if chargesDirty or nowT - chargesAskedAt >= 1 then
            cachedCharges = C_Spell.GetSpellCharges(BRES_SPELL_ID)
            chargesAskedAt, chargesDirty = nowT, false
        end
        local bresInfo = cachedCharges
        if bresInfo and bresInfo.maxCharges and bresInfo.maxCharges > 0 then
            bresActive = true
            BResFrame:Show()
            local cur = bresInfo.currentCharges or 0
            BResFrame.count:SetText(settings.showCharges and tostring(cur) or "")
            if cur > 0 then
                BResFrame.count:SetTextColor(0, 1, 0)
            else
                BResFrame.count:SetTextColor(1, 0.2, 0.2)
            end

            if cur < bresInfo.maxCharges and bresInfo.cooldownStartTime > 0 then
                local remain = (bresInfo.cooldownStartTime + bresInfo.cooldownDuration) - GetTime()
                SetTimer(BResFrame.timer, remain)
                if lastBResStart ~= bresInfo.cooldownStartTime then 
                    BResFrame.Cooldown:SetCooldown(bresInfo.cooldownStartTime, bresInfo.cooldownDuration)
                    lastBResStart = bresInfo.cooldownStartTime 
                end
            else 
                PlainTimer(BResFrame.timer, "") 
                BResFrame.Cooldown:Clear()
                lastBResStart = 0 
            end
        else
            if settings.hideInactive then
                BResFrame:Hide()
            else
                BResFrame:Show()
                BResFrame.count:SetText("")
                PlainTimer(BResFrame.timer, "")
                BResFrame.Cooldown:Clear()
            end
            lastBResStart = 0
        end
    else
        BResFrame:Hide()
    end

    -- Update Lust
    if settings.trackLust then
        if startTime > 0 then
            local remain = 600 - (GetTime() - startTime)
            if remain > 0 then
                lustActive = true
                LustFrame:Show()
                SetTimer(LustFrame.timer, remain)
                if lastLustStart ~= startTime then 
                    LustFrame.Cooldown:SetCooldown(startTime, 600)
                    lastLustStart = startTime 
                end
            else
                startTime = 0
                activeAuraExpiration = 0
                if settings.hideInactive then
                    LustFrame:Hide()
                else
                    LustFrame:Show()
                    PlainTimer(LustFrame.timer, "")
                    LustFrame.Cooldown:Clear()
                end
                lastLustStart = 0
            end
        else
            if settings.hideInactive then
                LustFrame:Hide()
            else
                LustFrame:Show()
                PlainTimer(LustFrame.timer, "")
                LustFrame.Cooldown:Clear()
            end
            lastLustStart = 0
        end
    else
        LustFrame:Hide()
    end

    if settings.hideInactive then
        if bresActive or lustActive then
            MainFrame:Show()
        else
            MainFrame:Hide()
        end
    else
        MainFrame:Show()
    end
end

-- Which Sated debuff the aura scan saw on the player: an id, false for none,
-- nil when the scan has nothing to say (it is not running, or in a fight).
local function SatedFromScan()
    local Core = OxedHub.Core
    local active = Core and Core.activeSpellIDs
    if not active or next(active) == nil then return nil end
    for spellID in pairs(SATED_IDS) do
        if active[spellID] then return spellID end
    end
    return false
end

local currentSated = nil
local lastSatedAsk = 0

local function SyncLust()
    if not settings or not settings.enabled then return end

    -- ⚠ Nothing to ask when nothing changed. Every aura change asked the game
    -- for all seven Sated debuffs, and the one that is up comes back as a
    -- new table: 2 KB per aura change, 12 MB in half an hour. The aura scan
    -- already knows what is on the player; when it agrees with what we hold,
    -- the game is not asked. When it cannot say, it is asked as before.
    local seen = SatedFromScan()
    if seen ~= nil then
        if seen and seen == currentSated and activeAuraExpiration > 0 then return end
        if seen == false and activeAuraExpiration == 0 then return end
    else
        -- The scan cannot say (in a dungeon the game keeps aura data secret).
        -- Sated, once seen, lasts its ten minutes: until its known end there
        -- is nothing to ask. Otherwise the seven questions are asked at most
        -- four times a second, not on every aura change, so a lust still
        -- shows within a quarter second.
        local now = GetTime()
        local known = activeAuraExpiration
        if type(known) == "number" and not (issecretvalue and issecretvalue(known))
            and known > now then
            return
        end
        if now - lastSatedAsk < 0.25 then return end
        lastSatedAsk = now
    end

    local found = false

    for spellID in pairs(SATED_IDS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if aura and aura.expirationTime and aura.expirationTime > 0 then
            if isInitialized and activeAuraExpiration == 0 then
                PlayLustSound()
            end
            startTime = aura.expirationTime - 600
            activeAuraExpiration = aura.expirationTime
            currentSated = spellID
            currentLustIcon = aura.icon
            if LustFrame and LustFrame.Icon and aura.icon then
                LustFrame.Icon:SetTexture(aura.icon)
            end
            found = true
            break
        end
    end

    if not found then
        currentSated = nil
        startTime = 0
        activeAuraExpiration = 0
        currentLustIcon = nil
        if LustFrame and LustFrame.Icon then
            LustFrame.Icon:SetTexture(136012)
        end
    end
end

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(self, event, ...)
    if not settings or not settings.enabled then return end
    if event ~= "UNIT_AURA" then chargesDirty = true end
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        startTime = 0
        activeAuraExpiration = 0
        lastBResStart = 0
        lastLustStart = 0
        lastSoundTime = 0
        currentLustIcon = nil
        if activeSoundHandle and StopSound then
            pcall(StopSound, activeSoundHandle)
            activeSoundHandle = nil
        end
        if MainFrame then MainFrame:Hide() end
        isInitialized = false
        SyncLust()
        if MainFrame then
            MainFrame:ClearAllPoints()
            MainFrame:SetPoint(settings.point or "CENTER", UIParent, settings.relativePoint or "CENTER", settings.x or 0, settings.y or 120)
        end
        C_Timer.After(2, function()
            SyncLust()
            isInitialized = true
        end)
    elseif event == "UNIT_AURA" then
        -- The display ticks ten times a second by itself; redrawing it on
        -- every aura change as well only doubled the work.
        SyncLust()
        return
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        SyncLust()
    end
    UpdateDisplay()
end)

local updateTicker
local syncTicker

StartTracking = function()
    CreateUI()
    if not updateTicker then
        updateTicker = C_Timer.NewTicker(0.1, UpdateDisplay)
    end
    if not syncTicker then
        syncTicker = C_Timer.NewTicker(1.0, SyncLust)
    end
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    watcher:RegisterEvent("SPELL_UPDATE_CHARGES")
    watcher:RegisterUnitEvent("UNIT_AURA", "player")
    SyncLust()
    UpdateDisplay()
end

StopTracking = function()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
    if syncTicker then
        syncTicker:Cancel()
        syncTicker = nil
    end
    watcher:UnregisterAllEvents()
    if MainFrame then MainFrame:Hide() end
end

-- ── Options Window ──────────────────────────────────────────────────────────

local function AddChoiceRow(w, key, caption, choices, onChange)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
    label:SetText(caption)

    local holder, buttons = {}, {}
    holder.Refresh = function()
        for _, entry in ipairs(buttons) do
            if settings[key] == entry.key then
                entry.button:SetNormalFontObject("GameFontNormal")
                if entry.button.SetBackdropBorderColor then
                    entry.button:SetBackdropBorderColor(1, 0.82, 0, 1)
                end
            else
                entry.button:SetNormalFontObject("GameFontDisableSmall")
                if entry.button.SetBackdropBorderColor then
                    entry.button:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                end
            end
        end
    end
    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(120, 22)
        button:SetPoint("TOPLEFT", w, "TOPLEFT", 145 + (index - 1) * 126, w.cursorY - 2)
        button:SetText(choice.name)
        button:SetScript("OnClick", function()
            settings[key] = choice.key
            holder.Refresh()
            if onChange then onChange(choice.key) end
        end)
        buttons[#buttons + 1] = { key = choice.key, button = button }
    end
    table.insert(w.checks, holder)
    w.cursorY = w.cursorY - 28
end

local function AddSlider(w, key, caption, minValue, maxValue, step, formatStr, onChange)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 160, w.cursorY)
    slider:SetWidth(180)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    for _, part in ipairs({ "Low", "High", "Text" }) do
        local region = slider[part] or (slider:GetName() and _G[slider:GetName() .. part])
        if region then region:SetText("") end
    end

    local ready, refreshing = false, false
    local function Show(value)
        if formatStr:find("%%%%") then
            label:SetText((formatStr):format(caption, math.floor(value * 100)))
        else
            label:SetText((formatStr):format(caption, value))
        end
    end
    local function Load()
        refreshing = true
        local value = tonumber(settings[key]) or minValue
        slider:SetValue(value)
        Show(value)
        refreshing = false
        ready = true
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        Show(value)
        if refreshing or not ready then return end
        settings[key] = value
        if onChange then onChange(value) end
    end)

    local holder = { Refresh = Load }
    table.insert(w.checks, holder)
    Load()
    w.cursorY = w.cursorY - 28
end

local function OpenSoundPicker()
    if OxedHub.Triggers and OxedHub.Triggers.ShowSoundPicker then
        local current = settings.sound or "oxedhub_bloodlust"
        if current == "bloodlust" then
            current = "oxedhub_bloodlust"
        elseif type(current) == "string" and current:match("^s%d$") then
            current = "oxedhub_breslust_horn_" .. current:sub(2)
        end
        local mock = { actions = { sound = current } }
        OxedHub.Triggers:ShowSoundPicker(mock, "sound", function(chosenSound)
            if not chosenSound or chosenSound == "" or chosenSound == "None" or chosenSound == "none" then
                settings.sound = "None"
            else
                settings.sound = chosenSound
            end
            if optionsWindow and optionsWindow.soundLabel then
                optionsWindow.soundLabel:SetText(L["Bloodlust sound: "] .. SoundName(settings.sound))
            end
            if settings.sound ~= "None" then
                PlayLustSound(settings.sound)
            end
        end)
    end
end

local optionsWindow
local function ShowOptions()
    CreateUI()
    if not optionsWindow and OxedHub.ModuleAPI then
        optionsWindow = OxedHub.ModuleAPI:CreateOptionsWindow("BRes & Lust Tracker", 460, 680)
        
        optionsWindow:AddNote("Clean, customizable display for Battle Resurrection charges and Bloodlust/Heroism debuffs.")

        -- Action Buttons Row
        local btnUnlock = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnUnlock:SetSize(130, 22)
        btnUnlock:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 20, optionsWindow.cursorY - 4)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnUnlock) end

        local function RefreshUnlockBtn()
            btnUnlock:SetText(settings.locked and L["Unlock / Move"] or L["Lock Position"])
        end
        RefreshUnlockBtn()

        btnUnlock:SetScript("OnClick", function()
            settings.locked = not settings.locked
            RefreshUnlockBtn()
            UpdateLayout()
            UpdateDisplay()
        end)

        local btnTest = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnTest:SetSize(130, 22)
        btnTest:SetPoint("LEFT", btnUnlock, "RIGHT", 8, 0)
        btnTest:SetText(L["Test Mode"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnTest) end

        local function RefreshTestBtn()
            btnTest:SetText(previewMode and L["Stop Test"] or L["Test Mode"])
        end
        RefreshTestBtn()

        btnTest:SetScript("OnClick", function()
            previewMode = not previewMode
            RefreshTestBtn()
            UpdateDisplay()
        end)

        local btnReset = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        btnReset:SetSize(130, 22)
        btnReset:SetPoint("LEFT", btnTest, "RIGHT", 8, 0)
        btnReset:SetText(L["Reset Position"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnReset) end

        btnReset:SetScript("OnClick", function()
            settings.point = "CENTER"
            settings.relativePoint = "CENTER"
            settings.x = 0
            settings.y = 120
            if MainFrame then
                MainFrame:ClearAllPoints()
                MainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
            end
            print(PREFIX .. L["Position reset to center."])
        end)

        optionsWindow:HookScript("OnShow", function()
            RefreshUnlockBtn()
            RefreshTestBtn()
            if optionsWindow.soundLabel then
                optionsWindow.soundLabel:SetText(L["Bloodlust sound: "] .. SoundName(settings.sound))
            end
        end)

        optionsWindow.cursorY = optionsWindow.cursorY - 32

        -- Section: Style & Orientation
        optionsWindow:AddNote("|cffffd100Display & Layout|r")

        AddChoiceRow(optionsWindow, "style", L["Display Style"], {
            { key = "compact", name = L["Compact Icons"] },
            { key = "full",    name = L["With Text"] },
        }, function() UpdateLayout(); UpdateDisplay() end)

        AddChoiceRow(optionsWindow, "orientation", L["Orientation"], {
            { key = "horizontal", name = L["Horizontal"] },
            { key = "vertical",   name = L["Vertical"] },
        }, function() UpdateLayout(); UpdateDisplay() end)

        -- Section: Tracking & Conditions
        optionsWindow:AddNote("|cffffd100Tracking & Conditions|r")

        optionsWindow:AddCheckbox(settings, "enabled", "Enable BRes & Lust Tracker",
            "Turn the tracker module on or off.", function(val)
                if OxedHub.ModuleAPI and OxedHub.ModuleAPI.SetModuleEnabled then
                    OxedHub.ModuleAPI:SetModuleEnabled("breslusttracker", val)
                else
                    if val then StartTracking() else StopTracking() end
                end
            end)

        optionsWindow:AddCheckbox(settings, "trackBRes", "Track Battle Resurrection charges",
            "Show Battle Res charges and recharge timer.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "trackLust", "Track Bloodlust / Sated debuff",
            "Show Bloodlust / Heroism / Time Warp cooldown.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "showTime", "Show countdown timer",
            "Display remaining cooldown time.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "showCharges", "Show charges count",
            "Display the number of available Battle Res charges.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "playSound", "Play sound alert on Bloodlust cast",
            "Play an audible sound when Bloodlust or Heroism is activated.")

        local soundLabel = optionsWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        soundLabel:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 44, optionsWindow.cursorY - 4)
        soundLabel:SetWidth(212)
        soundLabel:SetWordWrap(false)
        soundLabel:SetJustifyH("LEFT")
        soundLabel:SetTextColor(0.8, 0.8, 0.8)
        soundLabel:SetText(L["Bloodlust sound: "] .. SoundName(settings.sound))
        optionsWindow.soundLabel = soundLabel

        local pickSound = CreateFrame("Button", nil, optionsWindow, "UIPanelButtonTemplate")
        pickSound:SetSize(140, 22)
        pickSound:SetPoint("TOPLEFT", optionsWindow, "TOPLEFT", 260, optionsWindow.cursorY)
        pickSound:SetText(L["Choose a sound"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(pickSound)
        end
        pickSound:SetScript("OnClick", function()
            OpenSoundPicker()
        end)
        optionsWindow.cursorY = optionsWindow.cursorY - 30

        optionsWindow:AddCheckbox(settings, "hideInactive", "Hide when inactive",
            "Automatically hide icons when no charges or debuff are active.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "inCombatOnly", "Only show in Combat",
            "Hide tracker when out of combat.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "showInDungeon", "Show in Dungeons",
            "Display tracker while inside 5-player dungeons.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "showInRaid", "Show in Raids",
            "Display tracker while inside raid instances.", UpdateDisplay)

        optionsWindow:AddCheckbox(settings, "showInWorld", "Show in Open World",
            "Display tracker while exploring open world zones.", UpdateDisplay)

        -- Section: Appearance Sliders
        optionsWindow:AddNote("|cffffd100Appearance|r")

        AddSlider(optionsWindow, "scale", L["UI Scale"], 0.5, 2.0, 0.05, "%s: %.2fx", function(v)
            if MainFrame then MainFrame:SetScale(v) end
        end)

        AddSlider(optionsWindow, "alpha", L["Opacity"], 0.2, 1.0, 0.05, "%s: %d%%", function(v)
            if MainFrame then MainFrame:SetAlpha(v) end
        end)

        AddSlider(optionsWindow, "iconSize", L["Icon Size"], 32, 64, 2, L["%s: %d px"], function()
            UpdateLayout()
            UpdateDisplay()
        end)
    end

    if optionsWindow then
        optionsWindow:SetSize(460, 680)
        optionsWindow:Show()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.breslusttracker
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.breslusttracker = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "breslusttracker",
        name     = "BRes & Lust Tracker",
        version  = "1.1.1",
        updated  = 20261018.1,  -- lighter in combat
        author   = "Oxed",
        category = "combat",
        keywords = { "bres", "lust", "sated", "resurrection" },
        desc     = "Tracks Battle Resurrection charges and Sated debuffs on screen.",
        icon     = 136012,
        defaults = DEFAULTS,

        OnOptionsShow = function()
            ShowOptions()
        end,
        OnEnable = function(_, configData)
            settings = configData
            CreateUI()
            StartTracking()
        end,
        OnDisable = function()
            StopTracking()
        end,
    })
end)
