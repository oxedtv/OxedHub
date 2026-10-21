-- ============================================================================
-- MythicLooter: Run Tracker
-- During a Mythic+ key: how far the enemy forces are, how much more is
-- wanted before the next boss, what the pull in progress is worth, and each
-- mob's share on its nameplate and tooltip. Says when the forces are ready
-- for the next boss, warns when a boss is pulled short, and can put the
-- tank's and healer's marks on them when the key starts.
--
-- Targets ("have this much before pulling that boss") are the player's own:
-- the last boss wants 100%, and every timed run notes what you had at each
-- boss pull and keeps those numbers for that dungeon. They can be set by hand
-- too, and a hand-set dungeon is never overwritten.
--
-- ⚠ Secret values. In a fight the scenario's numbers can be secret: then the
-- panel keeps what it last read, and nothing compares them. A mob's share on
-- its nameplate is handed to the game as it comes, secret or not -- the font
-- string may show a secret, Lua may not look at one.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local RT = {}
OxedHub.MythicLooterRun = RT

local DEFAULTS = {
    enabled      = true,    -- the panel during a key (MythicLooter itself must be on)
    showBosses   = true,    -- the boss list under the bar
    showPull     = true,    -- what the pull in progress is worth
    nameplates   = true,    -- each mob's share on its nameplate
    tooltip      = true,    -- and in its tooltip
    readyAlert   = true,    -- a line when the forces are ready for the next boss
    readySound   = "",
    tellParty    = false,   -- say it in party chat as well
    lowPullAlert = true,    -- a boss pulled before its target
    lowPullSound = "",
    learnTargets = true,    -- a timed run's numbers become the dungeon's targets
    bgAlpha      = 0,       -- the panel's background, like the keystone list
    markRoles    = false,   -- marks on the tank and healer when the key starts
    tankMark     = 6,       -- square
    healerMark   = 5,       -- moon
    locked       = false,
    scale        = 1,
    point = "TOP", x = 0, y = -180,
    estimateTargets = true, -- even shares per boss until the dungeon has targets of its own
    decimals     = 1,       -- 1 or 2 places in every percentage
    showTicks    = true,    -- every boss's target on the bar, and the current section lit
    bigNumber    = false,   -- a large "still needed" number of its own on screen
    bigSize      = 28,
    bigLocked    = false,
    bigPoint = "TOP", bigX = 0, bigY = -110,
    -- colorProgress, colorDone, colorMissing are tables, built in Bind.
    -- "targets" and "manual" are tables, built in Bind.
}

local PREFIX = "|cff9d5db8MythicLooter:|r "
local cfg
local panel, optionsWindow
local targetWindows = {}

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Num(v)
    if type(v) ~= "number" or IsSecret(v) then return nil end
    return v
end

local function Str(v)
    if type(v) ~= "string" or IsSecret(v) or v == "" then return nil end
    return v
end

-- true, false, or nil when it cannot be read.
local function Bool(v)
    if IsSecret(v) then return nil end
    return v == true
end

local function PlaySoundId(id)
    local API = OxedHub.ModuleAPI
    if id and id ~= "" and API and API.PlaySound then API:PlaySound(id) end
end

local function LooterOn()
    local API = OxedHub.ModuleAPI
    return not API or not API.IsModuleEnabled or API:IsModuleEnabled("mythiclooter")
end

local function InKey()
    if not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive) then return false end
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    return ok and Bool(active) == true
end

local function Pct(v)
    return ((cfg and cfg.decimals == 2) and "%.2f%%" or "%.1f%%"):format(v or 0)
end

local function Hex(c)
    if type(c) ~= "table" then return "ffffff" end
    return ("%02x%02x%02x"):format(math.floor((c[1] or 1) * 255), math.floor((c[2] or 1) * 255), math.floor((c[3] or 1) * 255))
end

-- ── The run ─────────────────────────────────────────────────────────────────

local run = {
    active = false, preview = false,
    mapID = nil, name = nil,
    cur = nil, total = nil, pct = nil,
    bosses = {},          -- { name, done } in the scenario's order
    pullFrom = nil,       -- the forces when the fight began
    pullShown = nil,      -- what the last pull was worth, shown for a moment
    readyFor = {},        -- boss index -> said already
    pulledAt = {},        -- boss index -> forces when it was pulled
    doneSaid = false,
    inEncounter = false,  -- a boss is engaged right now
}

local Paint      -- draws the panel; defined with it
local PaintBig   -- the large number; defined with it

-- The forces and the bosses, from the scenario. Keeps the last good numbers
-- when the scenario answers with secrets.
local function ReadState()
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then
        return
    end
    local ok, _, _, steps = pcall(C_Scenario.GetStepInfo)
    steps = ok and Num(steps) or 0

    local count = 0
    for i = 1, steps do
        local okInfo, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if okInfo and type(info) == "table" then
            local weighted = Bool(info.isWeightedProgress)
            if weighted then
                local total = Num(info.totalQuantity)
                local text = Str(info.quantityString)
                local cur = (text and tonumber(text:match("%d+"))) or Num(info.quantity)
                if total and total > 0 and cur then
                    run.cur, run.total = cur, total
                    run.pct = math.min(100, cur / total * 100)
                end
            elseif weighted == false then
                count = count + 1
                local boss = run.bosses[count]
                if not boss then
                    boss = {}
                    run.bosses[count] = boss
                end
                boss.name = Str(info.description) or boss.name or ("Boss " .. count)
                local done = Bool(info.completed)
                if done ~= nil then boss.done = done end
            end
        end
    end
    if count > 0 then
        for i = #run.bosses, count + 1, -1 do run.bosses[i] = nil end
    end
end

local function NextBoss()
    for i, boss in ipairs(run.bosses) do
        if not boss.done then return i, boss end
    end
    return nil
end

-- What the player wants before pulling boss i: their own number, or 100% for
-- the last boss. nil when there is none.
-- Second value: true when the number is only an estimate. Until a dungeon has
-- targets of its own (a timed run, or set by hand) each boss gets an even
-- share, so the panel has something to aim at from the first key.
local function TargetFor(i)
    local list = run.mapID and cfg.targets[run.mapID]
    local t = list and tonumber(list[i])
    if t and t > 0 then return t, false end
    local n = #run.bosses
    if i == n then return 100, false end
    if cfg.estimateTargets and n > 1 and i < n then
        return math.floor(100 * i / n + 0.5), true
    end
    return nil
end

-- The section being worked on: from the last target before the next boss to
-- that boss's own. from, to, index, isEstimate; nil once every boss is done.
local function Section()
    local i = NextBoss()
    if not i then return nil end
    local to, est = TargetFor(i)
    local from = 0
    for k = i - 1, 1, -1 do
        local t = TargetFor(k)
        if t then from = t break end
    end
    return from, to, i, est
end

-- ── Alerts ──────────────────────────────────────────────────────────────────

local function Say(text, sound)
    print(PREFIX .. text)
    PlaySoundId(sound)
end

local function TellParty(text)
    if not cfg.tellParty or not IsInGroup() or IsInRaid() then return end
    pcall(SendChatMessage, text, "PARTY")
end

local function CheckReady()
    if run.preview or not run.pct then return end
    if run.pct >= 100 then
        if not run.doneSaid then
            run.doneSaid = true
            if cfg.readyAlert then Say("|cff40ff40enemy forces done.|r", cfg.readySound) end
            TellParty("Enemy forces done (100%).")
        end
        return
    end
    local i, boss = NextBoss()
    local target, est
    if i then target, est = TargetFor(i) end
    if not target or run.readyFor[i] or run.pct < target then return end
    run.readyFor[i] = true
    if i == #run.bosses then return end   -- the last boss wants 100%, said above
    local line = ("forces ready for %s: %s (%s %s)"):format(boss.name, Pct(run.pct), est and "estimate" or "target", Pct(target))
    if cfg.readyAlert then Say("|cff40ff40" .. line .. "|r", cfg.readySound) end
    TellParty(("Forces ready for %s: %s"):format(boss.name, Pct(run.pct)))
end

local function OnBossPull()
    if not run.active then return end
    ReadState()
    local i, boss = NextBoss()
    if not i or not run.pct then return end
    run.pulledAt[i] = run.pct
    local target, est = TargetFor(i)
    if cfg.lowPullAlert and target and not est and run.pct + 0.05 < target then
        Say(("|cffff9933%s pulled at %s, the target was %s.|r"):format(boss.name, Pct(run.pct), Pct(target)),
            cfg.lowPullSound)
    end
end

-- A timed run's numbers become the dungeon's targets, unless the player set
-- that dungeon's by hand.
local function LearnFromRun()
    if not (cfg.learnTargets and run.mapID) or cfg.manual[run.mapID] then return end
    local info
    if C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo then
        local ok, result = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
        if ok and type(result) == "table" then info = result end
    end
    if not info or Bool(info.onTime) ~= true then return end

    -- Averaged with the targets learnt before, so one odd route does not
    -- throw away what several timed runs agreed on.
    local old = cfg.targets[run.mapID]
    local list = {}
    local any, blended = false, false
    for i, value in pairs(run.pulledAt) do
        if i < #run.bosses then
            local before = type(old) == "table" and tonumber(old[i]) or nil
            if before and before > 0 then
                value = (before + value) / 2
                blended = true
            end
            list[i] = math.floor(value * 10 + 0.5) / 10
            any = true
        end
    end
    if not any then return end
    cfg.targets[run.mapID] = list
    print(PREFIX .. (blended and "this timed run is averaged into your targets for %s."
        or "this timed run's boss numbers are now your targets for %s."):format(run.name or "this dungeon"))
end

-- ── Role marks ──────────────────────────────────────────────────────────────

-- ⚠ Only before the key starts. Once a keystone run is under way the game
-- forbids raid marks from addons (ADDON_ACTION_FORBIDDEN, even inside pcall:
-- pcall stops the error, not the report). Marked when the key is slotted.
local function MarkRoles()
    if not cfg.markRoles or not IsInGroup() or IsInRaid() or InCombatLockdown() then return end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then return end
    if not (SetRaidTarget and UnitGroupRolesAssigned) then return end
    local units = { "player", "party1", "party2", "party3", "party4" }
    for _, unit in ipairs(units) do
        local okExists, exists = pcall(UnitExists, unit)
        if okExists and Bool(exists) then
            local okRole, role = pcall(UnitGroupRolesAssigned, unit)
            role = okRole and Str(role)
            local want = (role == "TANK" and cfg.tankMark) or (role == "HEALER" and cfg.healerMark) or nil
            if want and want > 0 then
                -- ⚠ A mark already on the unit answers as a secret, and
                -- SetRaidTarget with the mark it has takes it off. Only an
                -- unmarked unit is marked.
                local okMark, current = pcall(GetRaidTargetIndex, unit)
                if okMark and not IsSecret(current) and current == nil then
                    pcall(SetRaidTarget, unit, want)
                end
            end
        end
    end
end

-- ── Nameplates and tooltips ─────────────────────────────────────────────────

local plates = {}      -- unit -> label frame
local platePool = {}

local function HasUnitShare()
    return C_ScenarioInfo and type(C_ScenarioInfo.GetUnitCriteriaProgressValues) == "function"
end

local function DropPlate(unit)
    local label = plates[unit]
    if not label then return end
    plates[unit] = nil
    label:Hide()
    label:ClearAllPoints()
    platePool[#platePool + 1] = label
end

local function ShowPlate(unit)
    if not (cfg.nameplates and run.active and HasUnitShare()) then return end
    local okPlate, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not okPlate or not plate or (plate.IsForbidden and plate:IsForbidden()) then return end

    local ok, count, _, percent = pcall(C_ScenarioInfo.GetUnitCriteriaProgressValues, unit)
    if not ok then return end
    local kind = type(percent)
    if kind ~= "string" and kind ~= "number" then return DropPlate(unit) end
    -- A plain zero is a mob that gives nothing; a secret is shown as it is.
    if not IsSecret(count) and (Num(count) or 0) <= 0 then return DropPlate(unit) end

    local label = plates[unit] or table.remove(platePool)
    if not label then
        label = CreateFrame("Frame", nil, UIParent)
        label:SetSize(1, 1)
        label.text = label:CreateFontString(nil, "OVERLAY")
        label.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        label.text:SetPoint("LEFT", label, "LEFT", 0, 0)
        label.text:SetTextColor(1, 0.82, 0, 1)
    end
    plates[unit] = label
    label:ClearAllPoints()
    if not pcall(label.SetPoint, label, "LEFT", plate, "RIGHT", -6, 0) then return DropPlate(unit) end
    label.text:SetFormattedText("%s", percent)
    label:Show()
end

local function DropAllPlates()
    for unit in pairs(plates) do DropPlate(unit) end
end

local function ShowAllPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if type(unit) == "string" then ShowPlate(unit) end
    end
end

local tooltipHooked = false
local function HookTooltip()
    if tooltipHooked or not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType) then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip or not (cfg and cfg.tooltip and run.active and HasUnitShare()) then return end
        local okUnit, _, unit = pcall(tooltip.GetUnit, tooltip)
        if not okUnit or type(unit) ~= "string" or IsSecret(unit) then return end
        local ok, count, _, percent = pcall(C_ScenarioInfo.GetUnitCriteriaProgressValues, unit)
        if not ok then return end
        local kind = type(percent)
        if kind ~= "string" and kind ~= "number" then return end
        if not IsSecret(count) and (Num(count) or 0) <= 0 then return end
        pcall(tooltip.AddDoubleLine, tooltip, "Enemy forces", percent, 1, 0.82, 0, 1, 1, 1)
    end)
end

-- ── The panel ───────────────────────────────────────────────────────────────

local PANEL_W = 270

local function SavePosition()
    local point, _, _, x, y = panel:GetPoint(1)
    if point then cfg.point, cfg.x, cfg.y = point, x, y end
end

-- In the look of the Party Keystones list: no frame around it, a thin gold
-- header that is faint until the mouse is over the panel, and the text and
-- bar on whatever is behind.
local HEADER_H = 18
local function SetHot(p, hot) p.header:SetAlpha(hot and 1 or 0.3) end

local function BuildPanel()
    if panel then return panel end
    local p = CreateFrame("Frame", "OxedHubRunTracker", UIParent)
    p:SetSize(PANEL_W, 70)
    p:SetClampedToScreen(true)
    p:SetMovable(true)
    p:SetFrameStrata("MEDIUM")
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function(self)
        if not cfg.locked then self:StartMoving() end
    end)
    p:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    p:SetScript("OnEnter", function(self) SetHot(self, true) end)
    p:SetScript("OnLeave", function(self) SetHot(self, self:IsMouseOver()) end)

    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints()
    p.bg:SetColorTexture(0, 0, 0, 0)

    local header = CreateFrame("Frame", nil, p)
    header:SetHeight(HEADER_H)
    header:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    header:EnableMouse(false)
    local line = header:CreateTexture(nil, "BACKGROUND")
    line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)
    p.header = header

    p.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("LEFT", header, "LEFT", 2, 0)
    p.title:SetPoint("RIGHT", header, "RIGHT", -60, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)

    p.value = p:CreateFontString(nil, "OVERLAY")
    p.value:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    p.value:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -1)

    local bar = CreateFrame("StatusBar", nil, p)
    bar:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -HEADER_H - 5)
    bar:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -HEADER_H - 5)
    bar:SetHeight(14)
    -- ⚠ Two backslashes each: with one, Lua dropped them and the bar pointed
    -- at a texture that does not exist, drawing nothing.
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:EnableMouse(false)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)
    -- Where the next boss's target sits on the bar.
    bar.mark = bar:CreateTexture(nil, "OVERLAY")
    bar.mark:SetSize(2, 18)
    bar.mark:SetColorTexture(1, 1, 1, 0.9)
    -- The section being worked on, lit across the bar, and a thin mark at
    -- every other boss's target.
    bar.section = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    bar.section:SetColorTexture(1, 1, 1, 0.14)
    bar.section:Hide()
    bar.ticks = {}
    bar.count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.count:SetPoint("CENTER")
    bar.count:SetShadowOffset(1, -1)
    p.bar = bar

    p.need = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.need:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
    p.need:SetPoint("RIGHT", p, "RIGHT", -2, 0)
    p.need:SetJustifyH("LEFT")
    p.need:SetShadowOffset(1, -1)

    p.bosses = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.bosses:SetPoint("TOPLEFT", p.need, "BOTTOMLEFT", 0, -4)
    p.bosses:SetPoint("RIGHT", p, "RIGHT", -2, 0)
    p.bosses:SetJustifyH("LEFT")
    p.bosses:SetShadowOffset(1, -1)

    -- Only a real right-click on the panel, out of combat. Letting go of a
    -- right-drag camera turn over the panel also counts as a mouse-up, and
    -- opened this window mid-pull where the player could not get rid of it.
    p:SetScript("OnMouseDown", function(_, mouse)
        p.rightDown = (mouse == "RightButton") and GetCursorPosition() or nil
    end)
    p:SetScript("OnMouseUp", function(_, mouse)
        local down = p.rightDown
        p.rightDown = nil
        if mouse ~= "RightButton" or not down then return end
        if InCombatLockdown() or (IsMouselooking and IsMouselooking()) then return end
        if math.abs(GetCursorPosition() - down) > 4 then return end
        RT:ShowOptions()
    end)

    p:ClearAllPoints()
    p:SetPoint(cfg.point or "TOP", UIParent, cfg.point or "TOP", cfg.x or 0, cfg.y or -180)
    SetHot(p, false)
    p:Hide()
    panel = p
    return p
end

local bossLines = {}

-- ── The big number ──────────────────────────────────────────────────────────
-- Optional, on its own: how much the current section still wants, large, with
-- the boss under it. In-progress, done and missing colours from Options.
local big
local function BuildBig()
    if big then return big end
    local b = CreateFrame("Frame", "OxedHubRunSection", UIParent)
    b:SetSize(200, 50)
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if point then cfg.bigPoint, cfg.bigX, cfg.bigY = point, x, y end
    end)
    b.value = b:CreateFontString(nil, "OVERLAY")
    b.value:SetPoint("TOP", b, "TOP", 0, 0)
    b.value:SetShadowOffset(1, -1)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.label:SetPoint("TOP", b.value, "BOTTOM", 0, -2)
    b.label:SetShadowOffset(1, -1)
    b:ClearAllPoints()
    b:SetPoint(cfg.bigPoint or "TOP", UIParent, cfg.bigPoint or "TOP", cfg.bigX or 0, cfg.bigY or -110)
    b:Hide()
    big = b
    return b
end

PaintBig = function()
    local show = cfg and cfg.enabled and cfg.bigNumber and LooterOn() and (run.active or run.preview)
    if not show then
        if big then big:Hide() end
        return
    end
    local b = BuildBig()
    b:SetScale(tonumber(cfg.scale) or 1)
    -- Takes the mouse only while it may be dragged, so a locked number never
    -- stands in the way of a click.
    b:EnableMouse(not cfg.bigLocked)
    b.value:SetFont(STANDARD_TEXT_FONT, math.max(14, math.min(48, tonumber(cfg.bigSize) or 28)), "OUTLINE")

    local pct = run.pct
    local from, to, i, est = Section()
    local c = cfg.colorProgress
    local value, label
    if pct and pct >= 100 then
        c, value, label = cfg.colorDone, "100%", "Enemy forces done"
    elseif to and pct then
        local boss = run.bosses[i]
        if pct >= to then
            c, value = cfg.colorDone, "Ready"
        else
            if run.inEncounter then c = cfg.colorMissing end
            value = "+" .. Pct(to - pct)
        end
        label = (boss and boss.name or "next boss") .. (est and "  (est.)" or "")
    elseif pct then
        value, label = Pct(pct), run.name or "Enemy forces"
    else
        value, label = "--", run.name or "Enemy forces"
    end
    b.value:SetText(value)
    b.value:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
    b.label:SetText(label or "")
    b:SetWidth(math.max(120, b.value:GetStringWidth() + 20, b.label:GetStringWidth() + 20))
    b:SetHeight(b.value:GetStringHeight() + b.label:GetStringHeight() + 6)
    b:Show()
end

Paint = function()
    local show = cfg and cfg.enabled and LooterOn() and (run.active or run.preview)
    if not show then
        if panel then panel:Hide() end
        return
    end
    local p = BuildPanel()
    p:SetScale(tonumber(cfg.scale) or 1)

    p.title:SetText(run.name or "Enemy forces")
    local pct = run.pct
    p.value:SetText(pct and Pct(pct) or "--")
    p.bar:SetValue(pct or 0)
    if run.cur and run.total then
        p.bar.count:SetFormattedText("%d / %d", run.cur, run.total)
    else
        p.bar.count:SetText("")
    end

    local i, boss = NextBoss()
    local target, est
    if i then target, est = TargetFor(i) end
    local done, missing, progress = cfg.colorDone, cfg.colorMissing, cfg.colorProgress
    local c = progress
    local needText
    local estTag = est and " |cff9d9d9dest.|r" or ""
    if pct and pct >= 100 then
        c = done
        needText = ("|cff%sEnemy forces done|r"):format(Hex(done))
    elseif target and pct then
        if pct >= target then
            c = done
            needText = ("|cff%sReady for %s|r  (%s%s)"):format(Hex(done), boss.name, Pct(target), estTag)
        else
            local short = target - pct
            if run.inEncounter then c = missing end
            needText = ("Need |cffffd100+%s|r before %s%s"):format(Pct(short), boss.name, estTag)
        end
    elseif boss then
        needText = ("Next: %s  |cff9d9d9d(no target set)|r"):format(boss.name)
    else
        needText = ""
    end
    p.bar:SetStatusBarColor(c[1] or 1, c[2] or 1, c[3] or 1, 0.95)

    local width = p.bar:GetWidth()
    if target and target < 100 then
        p.bar.mark:ClearAllPoints()
        p.bar.mark:SetPoint("CENTER", p.bar, "LEFT", width * target / 100, 0)
        p.bar.mark:Show()
    else
        p.bar.mark:Hide()
    end

    -- Every other boss's target, and the current section lit.
    local used = 0
    if cfg.showTicks and width > 0 then
        local from, to = Section()
        if from and to and to > from then
            p.bar.section:ClearAllPoints()
            p.bar.section:SetPoint("TOPLEFT", p.bar, "TOPLEFT", width * from / 100, 0)
            p.bar.section:SetPoint("BOTTOMLEFT", p.bar, "BOTTOMLEFT", width * from / 100, 0)
            p.bar.section:SetWidth(math.max(1, width * (to - from) / 100))
            p.bar.section:Show()
        else
            p.bar.section:Hide()
        end
        for k = 1, #run.bosses - 1 do
            local t, tEst = TargetFor(k)
            if t and k ~= i then
                used = used + 1
                local tick = p.bar.ticks[used]
                if not tick then
                    tick = p.bar:CreateTexture(nil, "OVERLAY")
                    tick:SetSize(1, 14)
                    p.bar.ticks[used] = tick
                end
                local a = run.bosses[k].done and 0.35 or (tEst and 0.5 or 0.8)
                tick:SetColorTexture(1, 0.82, 0, a)
                tick:ClearAllPoints()
                tick:SetPoint("CENTER", p.bar, "LEFT", width * t / 100, 0)
                tick:Show()
            end
        end
    else
        p.bar.section:Hide()
    end
    for k = used + 1, #p.bar.ticks do p.bar.ticks[k]:Hide() end

    -- The pull in progress, or the one just finished.
    if cfg.showPull then
        if run.pullFrom and pct and InCombatLockdown() and pct > run.pullFrom then
            needText = needText .. ("   |cffb380ff+%s this pull|r"):format(Pct(pct - run.pullFrom))
        elseif run.pullShown then
            needText = needText .. ("   |cff9d9d9dlast pull +%s|r"):format(Pct(run.pullShown))
        end
    end
    p.need:SetText(needText)

    p.bg:SetColorTexture(0, 0, 0, tonumber(cfg.bgAlpha) or 0)
    local height = 18 + 5 + 14 + 4 + p.need:GetStringHeight() + 6
    if cfg.showBosses and #run.bosses > 0 then
        wipe(bossLines)
        for index, item in ipairs(run.bosses) do
            local t, tEst = TargetFor(index)
            local mark = item.done and "|TInterface\\RAIDFRAME\\ReadyCheck-Ready:12|t"
                or (index == i and "|cffffd100>|r" or "|cff9d9d9d·|r")
            local extra = ""
            local at = run.pulledAt[index]
            if at then
                -- Pulled short of a real target shows in the missing colour.
                local short = t and not tEst and at + 0.05 < t
                extra = ("  |cff%spulled at %s|r"):format(short and Hex(cfg.colorMissing) or "9d9d9d", Pct(at))
            elseif t and not item.done then
                extra = ("  |cff9d9d9d%s %s|r"):format(tEst and "est." or "target", Pct(t))
            end
            bossLines[#bossLines + 1] = ("%s  %s%s"):format(mark, item.name, extra)
        end
        p.bosses:SetText(table.concat(bossLines, "\n"))
        p.bosses:Show()
        height = height + p.bosses:GetStringHeight() + 4
    else
        p.bosses:Hide()
    end
    p:SetHeight(height)
    p:Show()
    PaintBig()
end

-- ── Keeping up with the run ─────────────────────────────────────────────────

local watcher = CreateFrame("Frame")
local RUN_EVENTS = {
    "SCENARIO_CRITERIA_UPDATE", "ENCOUNTER_START", "ENCOUNTER_END", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}

local updateQueued = false
local function RunUpdate()
    updateQueued = false
    if not run.active then return end
    ReadState()
    CheckReady()
    Paint()
end
-- Each mob killed sends the criteria event; a pack dying is one update.
local function QueueUpdate()
    if updateQueued then return end
    updateQueued = true
    C_Timer.After(0.2, RunUpdate)
end

local function ClearPullShown()
    run.pullShown = nil
    Paint()
end

local function ResetRun()
    wipe(run.bosses)
    wipe(run.readyFor)
    wipe(run.pulledAt)
    run.cur, run.total, run.pct = nil, nil, nil
    run.pullFrom, run.pullShown = nil, nil
    run.doneSaid = false
    run.inEncounter = false
end

local function BeginRun()
    if run.active then return end
    if not (cfg and cfg.enabled and LooterOn()) then return end
    ResetRun()
    run.active, run.preview = true, false
    local okMap, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    run.mapID = okMap and Num(mapID) or nil
    run.name = run.mapID and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(run.mapID) or nil
    for _, event in ipairs(RUN_EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    ReadState()
    Paint()
    ShowAllPlates()
end

local function EndRun()
    if not run.active then return end
    run.active = false
    for _, event in ipairs(RUN_EVENTS) do pcall(watcher.UnregisterEvent, watcher, event) end
    DropAllPlates()
    Paint()
end

watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "SCENARIO_CRITERIA_UPDATE" then
        QueueUpdate()
    elseif event == "ENCOUNTER_START" then
        run.inEncounter = true
        OnBossPull()
        Paint()
    elseif event == "ENCOUNTER_END" then
        run.inEncounter = false
        QueueUpdate()
    elseif event == "PLAYER_REGEN_DISABLED" then
        ReadState()
        run.pullFrom, run.pullShown = run.pct, nil
    elseif event == "PLAYER_REGEN_ENABLED" then
        ReadState()
        if run.pullFrom and run.pct and run.pct > run.pullFrom then
            run.pullShown = run.pct - run.pullFrom
            C_Timer.After(8, ClearPullShown)
        end
        run.pullFrom = nil
        CheckReady()
        Paint()
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if type(arg1) == "string" then ShowPlate(arg1) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(arg1) == "string" then DropPlate(arg1) end
    end
end)

-- Starting and ending: always listened for, and cheap.
local lifecycle = CreateFrame("Frame")
lifecycle:SetScript("OnEvent", function(_, event)
    if not cfg then return end
    if event == "CHALLENGE_MODE_KEYSTONE_SLOTTED" then
        -- The key is in but the run has not begun: the last moment marks are allowed.
        MarkRoles()
    elseif event == "CHALLENGE_MODE_START" then
        C_Timer.After(1, function()
            if InKey() then BeginRun() end
        end)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        ReadState()
        LearnFromRun()
        EndRun()
    elseif event == "CHALLENGE_MODE_RESET" then
        EndRun()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- A reload inside a key picks the run back up; leaving ends it.
        C_Timer.After(2, function()
            if InKey() then BeginRun() else EndRun() end
        end)
    end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

local MARKS = {
    { value = 0, text = "None" },
    { value = 1, text = "Star" }, { value = 2, text = "Circle" }, { value = 3, text = "Diamond" },
    { value = 4, text = "Triangle" }, { value = 5, text = "Moon" }, { value = 6, text = "Square" },
    { value = 7, text = "Cross" }, { value = 8, text = "Skull" },
}

-- Sliders for this dungeon's boss targets. Only inside a key: that is where
-- the bosses' names are known.
function RT:ShowTargets()
    if not cfg then return end
    if not (run.active and run.mapID and #run.bosses > 0) then
        print(PREFIX .. "boss targets are set inside a key, where the bosses are known. They are also learnt from each timed run.")
        return
    end
    local mapID = run.mapID
    if type(cfg.targets[mapID]) ~= "table" then cfg.targets[mapID] = {} end
    local list = cfg.targets[mapID]

    local w = targetWindows[mapID]
    if not w then
        local API = OxedHub.ModuleAPI
        w = API:CreateOptionsWindow("Targets: " .. (run.name or "this dungeon"), 460, 120 + #run.bosses * 30)
        for i, boss in ipairs(run.bosses) do
            if i < #run.bosses then
                w:AddSlider(list, i, boss.name, 0, 100, 1, "%s: %d%%", function()
                    cfg.manual[mapID] = true
                    Paint()
                end)
            end
        end
        w:AddNote("0 means no target. The last boss always wants 100%. Set here, this dungeon's targets are no longer replaced by timed runs.")
        targetWindows[mapID] = w
    end
    w:Show()
end

function RT:Preview()
    if not cfg then return end
    if run.active then return end
    run.preview = not run.preview
    print(PREFIX .. (run.preview and "preview on (drag it, right-click for options)." or "preview off."))
    if run.preview then
        ResetRun()
        run.name = "Preview"
        run.cur, run.total, run.pct = 312, 460, 312 / 460 * 100
        run.bosses = {
            { name = "First Boss", done = true },
            { name = "Second Boss", done = false },
            { name = "Third Boss", done = false },
            { name = "Last Boss", done = false },
        }
        run.pulledAt[1] = 34.2
        run.mapID = nil
    end
    Paint()
end

-- The panel's look and the big number, in a window of their own: the main one is full.
local lookWindow
function RT:ShowLook()
    local API = OxedHub.ModuleAPI
    if not (API and cfg) then return end
    if not lookWindow then
        local o = API:CreateOptionsWindow("Run Tracker: Look", 460, 560)
        o:AddCheckbox(cfg, "bigNumber", "Big \"still needed\" number",
            "The current section's remaining percentage, large, with the boss under it. Drag it while unlocked.", Paint)
        o:AddCheckbox(cfg, "bigLocked", "Lock the big number", "Locked, it lets clicks through.", Paint)
        o:AddSlider(cfg, "bigSize", "Big number size", 14, 48, 1, "%s: %d", Paint)
        o:AddCheckbox(cfg, "showTicks", "Every boss's target on the bar",
            "A thin mark at each target and the section you are on lit.", Paint)
        o:AddCheckbox(cfg, "estimateTargets", "Estimate targets until a dungeon has its own",
            "Even shares per boss, marked est., until a timed run or your own numbers replace them. Estimates never warn about a short pull.", Paint)
        o:AddChoice(cfg, "decimals", "Decimals", { { value = 1, text = "12.3%" }, { value = 2, text = "12.34%" } }, Paint)
        o:AddColour(cfg, "colorProgress", "In progress", Paint)
        o:AddColour(cfg, "colorDone", "Ready / done", Paint)
        o:AddColour(cfg, "colorMissing", "Short at a boss pull", Paint)
        o:AddNote("Preview the panel in the main options to see changes outside a key.")
        lookWindow = o
    end
    lookWindow:Show()
end

function RT:ShowOptions()
    local API = OxedHub.ModuleAPI
    if not (API and cfg) then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("MythicLooter: Run Tracker", 500, 660)
        o:AddCheckbox(cfg, "enabled", "Show the enemy forces panel in a key", nil, Paint)
        o:AddCheckbox(cfg, "showBosses", "List the bosses under the bar", nil, Paint)
        o:AddCheckbox(cfg, "showPull", "Show what the pull in progress is worth", nil, Paint)
        o:AddCheckbox(cfg, "locked", "Lock the panel", "Unlocked, drag it. Right-click it for these options.")
        o:AddSlider(cfg, "scale", "Panel scale", 0.6, 1.8, 0.05, "%s: %.2f", Paint)
        o:AddCheckbox(cfg, "nameplates", "Each mob's share on its nameplate", nil, function()
            if cfg.nameplates then ShowAllPlates() else DropAllPlates() end
        end)
        o:AddCheckbox(cfg, "tooltip", "Each mob's share in its tooltip")
        o:AddCheckbox(cfg, "readyAlert", "Say when the forces are ready for the next boss")
        o:AddSoundPicker(cfg, "readySound", "Ready sound", "None")
        o:AddCheckbox(cfg, "tellParty", "Tell the party too", "One line in party chat when the forces are ready for a boss, and at 100%.")
        o:AddCheckbox(cfg, "lowPullAlert", "Warn when a boss is pulled before its target")
        o:AddSoundPicker(cfg, "lowPullSound", "Warning sound", "None")
        o:AddCheckbox(cfg, "learnTargets", "Learn targets from timed runs",
            "At each boss pull the forces are noted; a timed run keeps those numbers as that dungeon's targets.")
        o:AddCheckbox(cfg, "markRoles", "Mark the tank and healer when the key goes in",
            "Only unmarked players are marked, so a mark already set is left alone.")
        o:AddChoice(cfg, "tankMark", "Tank mark", MARKS)
        o:AddChoice(cfg, "healerMark", "Healer mark", MARKS)

        local preview = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        preview:SetSize(110, 22)
        preview:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 4)
        preview:SetText("Preview the panel")
        preview:SetScript("OnClick", function() RT:Preview() end)

        local targets = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        targets:SetSize(120, 22)
        targets:SetPoint("LEFT", preview, "RIGHT", 8, 0)
        targets:SetText("This key's targets")
        targets:SetScript("OnClick", function() RT:ShowTargets() end)

        local forget = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        forget:SetSize(110, 22)
        forget:SetPoint("LEFT", targets, "RIGHT", 8, 0)
        forget:SetText("Forget targets")
        forget:SetScript("OnClick", function()
            API:Confirm("Forget the boss targets of every dungeon?", function()
                wipe(cfg.targets)
                wipe(cfg.manual)
                Paint()
            end)
        end)
        local look = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        look:SetSize(100, 22)
        look:SetPoint("LEFT", forget, "RIGHT", 8, 0)
        look:SetText("Look")
        look:SetScript("OnClick", function() RT:ShowLook() end)

        o.cursorY = o.cursorY - 32
        o:AddNote("Targets are yours: a timed run's numbers, or what you set in a key. The last boss always wants 100%.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function Bind()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local looter = OxedHubDB.modules.mythiclooter
    if type(looter) ~= "table" then
        looter = {}
        OxedHubDB.modules.mythiclooter = looter
    end
    local config = looter.runTracker
    if type(config) ~= "table" then
        config = {}
        looter.runTracker = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is shared by reference.
    if type(config.targets) ~= "table" then config.targets = {} end
    if type(config.manual) ~= "table" then config.manual = {} end
    if type(config.colorProgress) ~= "table" then config.colorProgress = { 1, 1, 1 } end
    if type(config.colorDone) ~= "table" then config.colorDone = { 0.25, 1, 0.25 } end
    if type(config.colorMissing) ~= "table" then config.colorMissing = { 1, 0.3, 0.25 } end
    cfg = config
end

local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Bind()
    HookTooltip()
    for _, event in ipairs({ "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
            "CHALLENGE_MODE_RESET", "PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_KEYSTONE_SLOTTED" }) do
        pcall(lifecycle.RegisterEvent, lifecycle, event)
    end
end)
