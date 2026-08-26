local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey
local L = OxedHub.L

local PreyEngine = CreateFrame("Frame")
Prey.Engine = PreyEngine

-- Zone-name fallback used when the quest APIs cannot resolve a map ID yet.
Prey.INFERRED_HUNT_ZONE_MAP_IDS = {
    ["Harandar"] = 2413,
    ["Voidstorm"] = 2405,
    ["Eversong Woods"] = 2395,
    ["Zul'Aman"] = 2437,
    ["The Coiled Isle"] = 2512,
}

PreyEngine.state = {
    active = false,
    questID = nil,
    targetName = nil,
    difficulty = "Normal",
    stage = 0,
    percent = 0,
    tormentStacks = 0,
    tormentPct = 0,
    isNightmare = false,
    isAmbush = false,
    isBloodyCommand = false,
    inPreyZone = nil,          -- tri-state: true, false, nil
    preyZoneMapID = nil,
    confirmedPreyZoneMapID = nil,
    killStageUntil = 0,
    ambushAlertUntil = 0,
    bloodyCommandAlertUntil = 0,
    questListenUntil = 0,      -- poll-hard window after quest/gossip events
    stageFloor = 0,            -- highest stage seen this hunt (no-regress guard)
    lastWidgetSeenAt = 0,      -- last time Blizzard's widget reported to us
    cachedQuestID = nil,       -- GetActiveHuntQuestID memo
    cachedQuestAt = 0,
}

-- ---------------------------------------------------------------------------
-- SECRET-NUMBER SANITIZER
-- Several Blizzard prey/widget/map APIs hand back "secret" numbers in the
-- protected execution environment.  Arithmetic or comparison on those values
-- raises "attempt to compare a secret number" and taints whatever ran next, so
-- every foreign number is round-tripped through tostring -> tonumber first.
-- ---------------------------------------------------------------------------
local function SanitizeNumber(value)
    if type(value) == "number" then return value end
    local okStr, asString = pcall(tostring, value)
    if not okStr or type(asString) ~= "string" then return nil end
    local token = asString:match("^%s*([%+%-]?%d+%.?%d*)%s*$")
        or asString:match("^%s*([%+%-]?%d*%.%d+)%s*$")
    if not token then return nil end
    local okNum, numeric = pcall(tonumber, token)
    if okNum and type(numeric) == "number" then return numeric end
    return nil
end
Prey.SanitizeNumber = SanitizeNumber

local function IsValidQuestID(questID)
    local numeric = SanitizeNumber(questID)
    return (numeric and numeric > 0) and numeric or nil
end
Prey.IsValidQuestID = IsValidQuestID

-- Safe Map Canonicalization
function Prey:CanonicalizeMapID(mapID)
    local num = SanitizeNumber(mapID)
    if not num or num < 1 then return nil end
    return Prey.MAP_ID_EQUIVALENTS[num] or num
end

-- Multi-Tier Quest Zone Resolution
function Prey:ResolveExpectedQuestMapID(questID)
    questID = IsValidQuestID(questID)
    if not questID then return nil end

    if C_TaskQuest and C_TaskQuest.GetQuestZoneID then
        local ok, rawZone = pcall(C_TaskQuest.GetQuestZoneID, questID)
        if ok then
            local zone = Prey:CanonicalizeMapID(rawZone)
            if zone then return zone end
        end
    end

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local ok, wp = pcall(C_QuestLog.GetNextWaypoint, questID)
        if ok and type(wp) == "table" then
            local mapID = Prey:CanonicalizeMapID(wp.uiMapID or wp.mapID)
            if mapID then return mapID end
        end
    end

    -- Last resort: match the current zone name against the known hunt zones.
    if C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo then
        local okMap, rawMap = pcall(C_Map.GetBestMapForUnit, "player")
        local playerMapID = okMap and SanitizeNumber(rawMap) or nil
        if playerMapID then
            local okInfo, info = pcall(C_Map.GetMapInfo, playerMapID)
            if okInfo and type(info) == "table" and type(info.name) == "string" then
                local inferred = Prey.INFERRED_HUNT_ZONE_MAP_IDS[info.name]
                if inferred then return Prey:CanonicalizeMapID(inferred) end
            end
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- ACTIVE HUNT QUEST (cached)
-- The lookup runs on noisy events (UNIT_AURA, widget updates), and the fallback
-- path walks the whole static hunt table, so results are cached briefly.
-- ---------------------------------------------------------------------------
local ACTIVE_QUEST_CACHE_SECONDS = 0.75

-- How long a captured widget snapshot stays trustworthy without a refresh.
local WIDGET_SNAPSHOT_TTL = 10.0
-- Polling cadence while a hunt is live, and while merely idling in the zone.
local POLL_INTERVAL = 0.5
local POLL_IDLE_INTERVAL = 2.0
-- QUEST_ACCEPTED / gossip can precede the widget by a beat; poll hard briefly.
local QUEST_LISTEN_BURST = 6.0

local function ResolveActiveHuntQuestID()
    if C_QuestLog and C_QuestLog.GetActivePreyQuest then
        local ok, raw = pcall(C_QuestLog.GetActivePreyQuest)
        if ok then
            local questID = IsValidQuestID(raw)
            if questID then return questID end
        end
    end

    -- Fall back to scanning our static hunt list.
    if C_QuestLog and C_QuestLog.IsOnQuest then
        for qID in pairs(Prey.PreyQuestData) do
            local ok, onQuest = pcall(C_QuestLog.IsOnQuest, qID)
            if ok and onQuest then return qID end
        end
    end

    return nil
end

-- Returns the live prey quest ID, sanitized, or nil.
-- Pass maxAge = 0 to force a fresh read.
function Prey:GetActiveHuntQuestID(maxAge)
    local state = PreyEngine.state
    local now = (GetTime and GetTime()) or 0

    maxAge = tonumber(maxAge)
    if not maxAge or maxAge < 0 then maxAge = ACTIVE_QUEST_CACHE_SECONDS end

    if (now - (state.cachedQuestAt or 0)) <= maxAge then
        return state.cachedQuestID
    end

    state.cachedQuestID = ResolveActiveHuntQuestID()
    state.cachedQuestAt = now
    return state.cachedQuestID
end

function PreyEngine:InvalidateQuestCache()
    self.state.cachedQuestID = nil
    self.state.cachedQuestAt = 0
end

-- Still on the quest we think we are tracking?
local function IsQuestStillActive(questID)
    questID = IsValidQuestID(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsOnQuest then
        local ok, onQuest = pcall(C_QuestLog.IsOnQuest, questID)
        return ok and onQuest and true or false
    end
    return true
end
Prey.IsQuestStillActive = IsQuestStillActive

-- ---------------------------------------------------------------------------
-- INSTANCE GATE
-- The hunt bar and its alerts are outdoor-world features.  Suppress everything
-- inside instanced content so the HUD never overlaps dungeon/PvP UI.
-- ---------------------------------------------------------------------------
local RESTRICTED_INSTANCE_TYPES = {
    pvp = true, arena = true, party = true, raid = true, scenario = true, delve = true,
}

function Prey:IsRestrictedInstance()
    if IsInInstance then
        local ok, inInstance, instanceType = pcall(IsInInstance)
        if ok and inInstance == true then
            return RESTRICTED_INSTANCE_TYPES[instanceType] == true
        end
    end

    -- Delve/scenario transitions can lag IsInInstance()'s type reporting.
    if type(IsInScenario) == "function" then
        local ok, inScenario = pcall(IsInScenario)
        if ok and inScenario == true then return true end
    end

    return false
end

-- Tri-State Zone Status Refresh (true / false / nil)
function PreyEngine:RefreshInPreyZoneStatus(questID, force)
    questID = IsValidQuestID(questID)
    if not questID then
        self.state.inPreyZone = nil
        return nil
    end

    local playerMapID = nil
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, rawMap = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then playerMapID = Prey:CanonicalizeMapID(rawMap) end
    end

    local questMapID = Prey:ResolveExpectedQuestMapID(questID)
    if questMapID then
        self.state.preyZoneMapID = questMapID
    else
        questMapID = self.state.preyZoneMapID or self.state.confirmedPreyZoneMapID
    end

    local inPreyZone = nil
    if questMapID and playerMapID then
        inPreyZone = (playerMapID == questMapID)
    end

    if inPreyZone == true then
        self.state.confirmedPreyZoneMapID = questMapID
    end

    self.state.inPreyZone = inPreyZone
    return inPreyZone
end

-- ---------------------------------------------------------------------------
-- PREY WIDGET SNAPSHOT
-- We never call GetAllWidgetsBySetID and never read widgetID / widgetType /
-- shownState.  Those are secret values that taint Blizzard's own layout code
-- even when read inside a pcall.  Instead the widget mixin's Setup method is
-- hooked and the few fields we care about are snapshotted (and sanitized) as
-- Blizzard itself populates the frame.
-- ---------------------------------------------------------------------------
PreyEngine.widgetSnapshot = nil

-- Prey hunt frames are identified by mixin-only methods, not by widgetType.
local function IsPreyHuntProgressFrame(frame)
    return frame ~= nil
        and type(frame.ResetAnimState) == "function"
        and type(frame.AnimIn) == "function"
end
PreyEngine.IsPreyHuntProgressFrame = IsPreyHuntProgressFrame

function PreyEngine:CaptureWidgetSnapshot(widgetInfo)
    if type(widgetInfo) ~= "table" then return end

    local progressState = SanitizeNumber(widgetInfo.progressState)
    local barText = (type(widgetInfo.barText) == "string" and widgetInfo.barText ~= "") and widgetInfo.barText or nil
    local tooltip = type(widgetInfo.tooltip) == "string" and widgetInfo.tooltip or nil
    if progressState == nil and barText == nil and tooltip == nil then return end

    self.widgetSnapshot = {
        progressState = progressState,
        barText = barText,
        tooltip = tooltip,
        capturedAt = (GetTime and GetTime()) or 0,
    }
    self.state.lastWidgetSeenAt = self.widgetSnapshot.capturedAt
end

function PreyEngine:ClearWidgetSnapshot()
    self.widgetSnapshot = nil
    self.state.lastWidgetSeenAt = 0
end

-- A hunt boundary: new quest, turn-in, or abandon.  Everything that must not
-- leak across hunts is reset here, including the no-regress stage floor.
function PreyEngine:ResetHuntProgress()
    self:ClearWidgetSnapshot()
    self:InvalidateQuestCache()
    self.state.stageFloor = 0
    self.state.preyZoneMapID = nil
    self.state.confirmedPreyZoneMapID = nil
    self.state.inPreyZone = nil
end

-- True when Blizzard's prey widget is currently driving the UI.
function PreyEngine:HasLiveWidget()
    return self.widgetSnapshot ~= nil
end

function PreyEngine:GetTormentAura()
    if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then return nil end

    local function Fetch(spellID)
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        return ok and type(aura) == "table" and aura or nil
    end

    local aura = Fetch(Prey.TORMENT_SPELL_ID)
    local pctPerStack = 2
    local isNM = false
    if not aura then
        aura = Fetch(Prey.TORMENT_NIGHTMARE_ID)
        pctPerStack = 4
        isNM = true
    end
    if aura then
        local stacks = SanitizeNumber(aura.applications) or 1
        return {
            stacks = stacks,
            pct = stacks * pctPerStack,
            isNightmare = isNM,
        }
    end
    return nil
end

-- Show/hide Blizzard's own prey widget.  Frames are matched by mixin identity
-- (IsPreyHuntProgressFrame) rather than by widgetID, which is a secret value.
function PreyEngine:ApplyBlizzardWidgetVisibility(showBlizzardWidget)
    local shown = showBlizzardWidget ~= false

    local containers = {
        UIWidgetPowerBarContainerFrame,
        UIWidgetTopCenterContainerFrame,
        UIWidgetBelowMinimapContainerFrame,
        UIWidgetObjectiveTrackerContainerFrame,
    }
    for _, container in ipairs(containers) do
        if container and container.GetChildren then
            local ok, children = pcall(function() return { container:GetChildren() } end)
            if ok and type(children) == "table" then
                for _, child in ipairs(children) do
                    if IsPreyHuntProgressFrame(child) then
                        child:SetShown(shown)
                        self.lastBlizzWidgetFrame = child
                    end
                end
            end
        end
    end

    -- The frame captured by the Setup hook may live outside those containers.
    local tracked = self.lastBlizzWidgetFrame
    if tracked and tracked.SetShown then
        tracked:SetShown(shown)
    end
end

function PreyEngine:ToggleBlizzardWidgetMover()
    if not self.blizzMoverFrame then
        local mover = CreateFrame("Frame", "OxedHubBlizzPreyMover", UIParent, "BackdropTemplate")
        mover:SetSize(220, 50)
        mover:SetFrameStrata("FULLSCREEN_DIALOG")
        mover:SetFrameLevel(9500)
        mover:SetClampedToScreen(true)
        mover:SetMovable(true)
        mover:EnableMouse(true)
        mover:RegisterForDrag("LeftButton")

        mover:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        mover:SetBackdropColor(0.08, 0.25, 0.55, 0.85)
        mover:SetBackdropBorderColor(0.4, 0.75, 1.0, 1.0)

        local text = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("CENTER", mover, "CENTER", 0, 0)
        text:SetText("Blizzard Prey Widget\n|cFF88FF88(Drag to Position)|r")
        mover.text = text

        if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.preyBlizzWidgetPosition then
            local p = OxedHub.db.profile.preyBlizzWidgetPosition
            mover:SetPoint(p.point or "TOP", UIParent, p.relPoint or "TOP", p.x or 0, p.y or -120)
        else
            mover:SetPoint("TOP", UIParent, "TOP", 0, -120)
        end

        mover:SetScript("OnDragStart", function(f) f:StartMoving() end)
        mover:SetScript("OnDragStop", function(f)
            f:StopMovingOrSizing()
            local point, _, relPoint, x, y = f:GetPoint()
            if OxedHub.db and OxedHub.db.profile then
                OxedHub.db.profile.preyBlizzWidgetPosition = { point = point, relPoint = relPoint, x = x, y = y }
            end
            PreyEngine:ApplyBlizzardWidgetPosition()
        end)

        self.blizzMoverFrame = mover
    end

    self.blizzMoverActive = not self.blizzMoverActive
    if self.blizzMoverActive then
        self.blizzMoverFrame:Show()
    else
        self.blizzMoverFrame:Hide()
    end
    return self.blizzMoverActive
end

function PreyEngine:ApplyBlizzardWidgetPosition()
    if not (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.preyBlizzWidgetPosition) then return end
    local p = OxedHub.db.profile.preyBlizzWidgetPosition

    local container = UIWidgetTopCenterContainerFrame
    if container then
        container:ClearAllPoints()
        container:SetPoint(p.point or "TOP", UIParent, p.relPoint or "TOP", p.x or 0, p.y or -120)
    end
    if self.lastBlizzWidgetFrame then
        self.lastBlizzWidgetFrame:ClearAllPoints()
        self.lastBlizzWidgetFrame:SetPoint(p.point or "TOP", UIParent, p.relPoint or "TOP", p.x or 0, p.y or -120)
    end
end

function PreyEngine:HookAndConfigureBlizzardWidget()
    if _G.UIWidgetTemplatePreyHuntProgressMixin and not self.blizzWidgetHooked then
        self.blizzWidgetHooked = true
        hooksecurefunc(_G.UIWidgetTemplatePreyHuntProgressMixin, "Setup", function(frame, widgetInfo)
            self.lastBlizzWidgetFrame = frame

            -- Snapshot the progress fields while Blizzard hands them to us; this
            -- is the only taint-free route to progressState.
            self:CaptureWidgetSnapshot(widgetInfo)

            local scaleVal = 100
            if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.preyBlizzScale then
                scaleVal = OxedHub.db.profile.preyBlizzScale
            end
            frame:SetScale(scaleVal / 100)
            self:ApplyBlizzardWidgetPosition()

            -- Re-evaluate on the next frame so we do not run our own logic
            -- inside Blizzard's secure Setup call.
            if not self.widgetRefreshPending then
                self.widgetRefreshPending = true
                C_Timer.After(0, function()
                    self.widgetRefreshPending = false
                    self:UpdateActiveHunt()
                end)
            end
        end)
    end
end

function PreyEngine:InferStageFromObjectives(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then return nil end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" or #objectives < 1 then return nil end

    local completedCount = 0
    for _, obj in ipairs(objectives) do
        if obj.finished == true or (obj.numRequired and obj.numRequired > 0 and (obj.numFulfilled or 0) >= obj.numRequired) then
            completedCount = completedCount + 1
        end
    end

    if completedCount >= 3 then
        return 4
    elseif completedCount >= 2 then
        return 3
    elseif completedCount >= 1 then
        return 2
    end
    return 1
end

-- Reads the PREY_HUNT trigger's condition block once per pass.
function PreyEngine:GetHuntConditions()
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers then
        for _, tr in pairs(OxedHub.db.profile.triggers) do
            if tr.enabled and tr.event == "PREY_HUNT" and tr.conditions then
                return tr.conditions
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- ACTIVE POLLING
-- Widget events do not fire reliably for every progress change, so while a hunt
-- is genuinely live we drive UpdateActiveHunt from an OnUpdate and detach it
-- again as soon as there is nothing to watch.
-- ---------------------------------------------------------------------------
function PreyEngine:ShouldUsePolling()
    if Prey:IsRestrictedInstance() then return false end

    local now = (GetTime and GetTime()) or 0
    if now < (self.state.killStageUntil or 0) then return true end
    if now < (self.state.ambushAlertUntil or 0) then return true end
    if now < (self.state.bloodyCommandAlertUntil or 0) then return true end
    if now < (self.state.questListenUntil or 0) then return true end

    local trackedQuestID = self.state.questID
    local hasTracked = Prey.IsQuestStillActive(trackedQuestID)
    local liveQuestID = Prey:GetActiveHuntQuestID()
    local hasLive = Prey.IsQuestStillActive(liveQuestID)

    -- A live quest we have not picked up yet, or a tracked quest that has since
    -- ended, both need a pass to reconcile.
    if hasLive and not hasTracked then return true end
    if trackedQuestID and not hasTracked and not hasLive then return true end

    -- Steady state: keep polling only while actually out hunting.
    return hasTracked and self.state.inPreyZone == true
end

function PreyEngine:SetPollingActive(enabled)
    enabled = enabled == true
    if enabled == (self.pollingActive == true) then return end
    self.pollingActive = enabled

    if not enabled then
        self.elapsedSincePoll = 0
        self.nextPollEligibilityAt = 0
        self:SetScript("OnUpdate", nil)
        return
    end

    self.elapsedSincePoll = 0
    self.nextPollEligibilityAt = 0
    self:SetScript("OnUpdate", function(_, elapsed)
        self.elapsedSincePoll = (self.elapsedSincePoll or 0) + (elapsed or 0)
        local now = (GetTime and GetTime()) or 0

        -- Back off to a slow tick when we are parked in the zone with nothing
        -- happening: no alert carry, no recent widget traffic, no progress yet.
        local recentWidget = (now - (self.state.lastWidgetSeenAt or 0)) <= 2.0
        local idleInZone = self.state.inPreyZone == true
            and (self.state.stage or 0) <= 1
            and not recentWidget
            and now >= (self.state.killStageUntil or 0)
            and now >= (self.state.ambushAlertUntil or 0)
            and now >= (self.state.bloodyCommandAlertUntil or 0)
            and now >= (self.state.questListenUntil or 0)

        if self.elapsedSincePoll < (idleInZone and POLL_IDLE_INTERVAL or POLL_INTERVAL) then
            return
        end
        self.elapsedSincePoll = 0

        self:UpdateActiveHunt()

        -- Re-check every couple of seconds whether polling is still warranted.
        if now >= (self.nextPollEligibilityAt or 0) then
            self.nextPollEligibilityAt = now + 2.0
            if not self:ShouldUsePolling() then
                -- One final reconcile so an ended hunt cannot leave the bar
                -- latched at stage 4 after the OnUpdate detaches.
                self:UpdateActiveHunt()
                if not self:ShouldUsePolling() then
                    self:SetPollingActive(false)
                end
            end
        end
    end)
end

-- Poll hard for a few seconds after events that typically precede the widget.
function PreyEngine:ArmQuestListenBurst()
    local now = (GetTime and GetTime()) or 0
    self.state.questListenUntil = now + QUEST_LISTEN_BURST
    self:InvalidateQuestCache()
    self:SetPollingActive(true)
end

function PreyEngine:UpdateActiveHunt()
    -- The hunt HUD is an outdoor-world feature; stay out of instanced content.
    if Prey:IsRestrictedInstance() then
        self.state.active = false
        self.state.shouldShowHUD = false
        self:ApplyBlizzardWidgetVisibility(true)
        if Prey.HUD then Prey.HUD:Update(self.state) end
        self:SetPollingActive(false)
        return
    end

    local now = GetTime and GetTime() or 0
    local forceKillStage = now < (self.state.killStageUntil or 0)
    local forceAmbushAlert = now < (self.state.ambushAlertUntil or 0)

    local questID = Prey:GetActiveHuntQuestID()

    -- Switching to a different hunt is a boundary: drop the previous hunt's
    -- widget snapshot, zone cache and stage floor before reading anything.
    if questID and self.state.questID and questID ~= self.state.questID then
        self:ResetHuntProgress()
    end

    -- A snapshot older than the widget's own refresh cycle is stale data from a
    -- finished hunt, not current progress.
    local snapshot = self.widgetSnapshot
    if snapshot and (now - (snapshot.capturedAt or 0)) > WIDGET_SNAPSHOT_TTL then
        self:ClearWidgetSnapshot()
        snapshot = nil
    end

    local isHuntActive = forceKillStage or (snapshot ~= nil) or (questID ~= nil)
    self.state.active = isHuntActive

    if isHuntActive then
        self.state.questID = questID
        local questData = questID and Prey.PreyQuestData[questID]
        if questData then
            local diffIdx = questData[1]
            self.state.difficulty = (diffIdx == 3 and "Nightmare") or (diffIdx == 2 and "Hard") or "Normal"
            self.state.targetName = questData[3] or "Prey Target"
        else
            self.state.targetName = "Prey Target"
            self.state.difficulty = "Normal"
        end

        self:RefreshInPreyZoneStatus(questID, false)

        -- Stage & Progress Calculation.
        -- Blizzard's progressState is 0-based: 0 -> stage 1 ... 3 -> stage 4.
        local newStage = self.state.stage or 1
        if forceKillStage then
            newStage = 4
        else
            local foundWidgetProgress = false
            if snapshot and snapshot.progressState ~= nil then
                newStage = snapshot.progressState + 1
                if newStage < 1 then newStage = 1 end
                if newStage > 4 then newStage = 4 end
                foundWidgetProgress = true
            end

            -- Objective fallback while the widget has not reported yet.
            if not foundWidgetProgress and questID then
                local inferred = self:InferStageFromObjectives(questID)
                if inferred and inferred > 0 then
                    newStage = inferred
                end
            end
        end

        if newStage < 1 then newStage = 1 end

        -- Never regress within a hunt.  A stale widget read or an objective
        -- inference can report a lower stage than we already established; the
        -- floor is cleared only at a hunt boundary (see ResetHuntProgress) and
        -- on death before stage 4, where the objective genuinely does reset.
        local floor = self.state.stageFloor or 0
        if newStage < floor then
            newStage = floor
        else
            self.state.stageFloor = newStage
        end

        if newStage ~= self.state.stage and (self.state.stage or 0) > 0 then
            self:OnStageChanged(newStage)
        end
        self.state.stage = newStage
        self.state.percent = forceKillStage and 100 or (Prey.STAGE_PERCENTS[newStage] or 25)

        -- Live Torment Aura
        local torment = self:GetTormentAura()
        if torment then
            self.state.tormentStacks = torment.stacks
            self.state.tormentPct = torment.pct
            self.state.isNightmare = torment.isNightmare
        else
            self.state.tormentStacks = 0
            self.state.tormentPct = 0
            self.state.isNightmare = false
        end
    else
        self.state.questID = nil
        self.state.stage = 0
        self.state.percent = 0
        self.state.tormentStacks = 0
        self.state.tormentPct = 0
        self.state.inPreyZone = nil
    end

    -- Trigger conditions & visibility gates
    local conditions = self:GetHuntConditions()
    local showBlizz  = true
    local onlyInZone = false
    local showHUD    = true
    if conditions then
        if conditions.showBlizzardWidget ~= nil then showBlizz  = conditions.showBlizzardWidget end
        if conditions.onlyShowInPreyZone ~= nil then onlyInZone = conditions.onlyShowInPreyZone end
        if conditions.showHUDBar ~= nil        then showHUD    = conditions.showHUDBar end
    end
    self:ApplyBlizzardWidgetVisibility(showBlizz)

    -- In-zone gate: hide only when we are *confirmed* outside (false, not nil).
    local shouldShowHUD = self.state.active and showHUD ~= false
    if onlyInZone and self.state.inPreyZone == false and not forceKillStage and not forceAmbushAlert then
        shouldShowHUD = false
    end
    self.state.shouldShowHUD = shouldShowHUD

    -- Update HUD Bar
    if Prey.HUD then
        Prey.HUD:Update(self.state)
    end

    -- Attach/detach the OnUpdate poll to match the current hunt state.
    if not self.pollingActive and self:ShouldUsePolling() then
        self:SetPollingActive(true)
    end
end

function PreyEngine:OnStageChanged(newStage)
    self:PlayPreySound("stage" .. newStage)
end

function PreyEngine:PlayPreySound(soundKey)
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return end
    for _, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.enabled and trigger.event == "PREY_HUNT" then
            local actions = trigger.actions or {}
            local cond = trigger.conditions or {}
            local soundVal = actions[soundKey .. "Sound"] or cond[soundKey .. "Sound"]
            if soundVal and soundVal ~= "" and soundVal ~= "None" then
                if OxedHub.Sounds and OxedHub.Sounds.Play then
                    OxedHub.Sounds:Play(soundVal)
                else
                    PlaySoundFile(soundVal, "Master")
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- ALERT GATES
-- Chat scanning is cheap, but firing on every match is not: "ambush" shows up
-- in unrelated system messages all over the game.  Both alerts are therefore
-- gated on a live hunt before they are allowed through.
-- ---------------------------------------------------------------------------
function PreyEngine:ShouldScanAmbushChat()
    if not self.state.active then return false end
    if Prey:IsRestrictedInstance() then return false end

    local liveQuestID = Prey:GetActiveHuntQuestID()
    if not liveQuestID then return false end

    -- Stage 4 means the prey is already flushed out; ambushes no longer apply.
    if (tonumber(self.state.stage) or 0) >= 4 then return false end

    if self.state.inPreyZone == nil then
        self:RefreshInPreyZoneStatus(liveQuestID, true)
    end

    -- nil means the zone APIs have not resolved yet.  A player hearing an NPC
    -- ambush line is standing next to that NPC, so only a confirmed `false`
    -- blocks the scan.
    return self.state.inPreyZone ~= false
end

-- Bloody Command is a Nightmare-only mechanic during stages 1-3.
function PreyEngine:ShouldScanBloodyCommandChat()
    if not self.state.active then return false end
    if Prey:IsRestrictedInstance() then return false end

    local stage = tonumber(self.state.stage) or 0
    if stage < 1 or stage > 3 then return false end

    local difficulty = self.state.difficulty
    if type(difficulty) ~= "string" then return false end
    return string.find(string.lower(difficulty), "nightmare", 1, true) ~= nil
end

function PreyEngine:OnAmbushDetected()
    local now = GetTime and GetTime() or 0
    self.state.ambushAlertUntil = now + 6
    self.state.isAmbush = true
    self:PlayPreySound("ambush")
    if Prey.HUD then Prey.HUD:Update(self.state) end
    C_Timer.After(6, function()
        self.state.isAmbush = false
        if Prey.HUD then Prey.HUD:Update(self.state) end
    end)
end

function PreyEngine:OnBloodyCommandDetected()
    local now = GetTime and GetTime() or 0
    self.state.bloodyCommandAlertUntil = now + 6
    self.state.isBloodyCommand = true
    self:PlayPreySound("bloodyCommand")
    if Prey.HUD then Prey.HUD:Update(self.state) end
    C_Timer.After(6, function()
        self.state.isBloodyCommand = false
        if Prey.HUD then Prey.HUD:Update(self.state) end
    end)
end

function PreyEngine:OnQuestTurnedIn(questID)
    local now = GetTime and GetTime() or 0
    self.state.killStageUntil = now + 8
    self.state.stage = 4
    self.state.percent = 100

    -- Turn-in ends this hunt: drop the cached zone identity so the next hunt
    -- resolves a fresh target zone instead of inheriting this one.
    self.state.preyZoneMapID = nil
    self.state.confirmedPreyZoneMapID = nil
    self.state.inPreyZone = nil
    self:ClearWidgetSnapshot()

    self:PlayPreySound("kill")
    self:UpdateActiveHunt()
end

-- Event registration
PreyEngine:RegisterEvent("PLAYER_LOGIN")
PreyEngine:RegisterEvent("PLAYER_ENTERING_WORLD")
PreyEngine:RegisterEvent("ZONE_CHANGED_NEW_AREA")
PreyEngine:RegisterEvent("ZONE_CHANGED")
PreyEngine:RegisterEvent("UPDATE_UI_WIDGET")
PreyEngine:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
PreyEngine:RegisterEvent("QUEST_ACCEPTED")
PreyEngine:RegisterEvent("QUEST_DETAIL")
PreyEngine:RegisterEvent("QUEST_TURNED_IN")
PreyEngine:RegisterEvent("QUEST_REMOVED")
PreyEngine:RegisterEvent("PLAYER_ALIVE")
PreyEngine:RegisterEvent("UNIT_AURA")
PreyEngine:RegisterEvent("GOSSIP_SHOW")
PreyEngine:RegisterEvent("GOSSIP_CLOSED")
PreyEngine:RegisterEvent("CHAT_MSG_SYSTEM")
PreyEngine:RegisterEvent("CHAT_MSG_MONSTER_SAY")
PreyEngine:RegisterEvent("CHAT_MSG_MONSTER_YELL")
PreyEngine:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
PreyEngine:RegisterEvent("RAID_BOSS_EMOTE")

-- ---------------------------------------------------------------------------
-- CHAT MATCHING HELPERS
-- ---------------------------------------------------------------------------
local AMBUSH_FALLBACK_PHRASES = {
    "ambush",
    "you've stumbled right into my trap",
    "a momentary setback",
}

local BLOODY_COMMAND_PHRASES = {
    "kill for me. now!",
    "drain their anguish!",
}

local function ContainsInsensitive(haystack, needle)
    if type(haystack) ~= "string" or type(needle) ~= "string" or needle == "" then
        return false
    end
    local ok, found = pcall(function()
        return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
    end)
    return ok and found or false
end

-- Prey names are multi-word ("Zadu, Fist of Nalorakk"); NPC chat lines almost
-- never contain the full name, so match on individual tokens of 4+ characters.
local function MatchesPreyNameTokens(preyName, message, sender)
    if type(preyName) ~= "string" or preyName == "" then return false end

    if ContainsInsensitive(message, preyName) or ContainsInsensitive(sender, preyName) then
        return true
    end

    for token in string.gmatch(string.lower(preyName), "[%a%d]+") do
        if string.len(token) >= 4 then
            if ContainsInsensitive(message, token) or ContainsInsensitive(sender, token) then
                return true
            end
        end
    end
    return false
end

local function MatchesAnyPhrase(message, phrases)
    if type(message) ~= "string" then return false end
    local ok, lowered = pcall(string.lower, message)
    if not ok then return false end
    for _, phrase in ipairs(phrases) do
        if string.find(lowered, phrase, 1, true) then return true end
    end
    return false
end

PreyEngine:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        self:HookAndConfigureBlizzardWidget()
        if Prey.Gossip then Prey.Gossip:Initialize() end
        -- Staggered login bootstrap passes
        for _, delay in ipairs({ 0.2, 0.75, 1.5, 3.0, 5.0 }) do
            C_Timer.After(delay, function() self:UpdateActiveHunt() end)
        end
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" then
        self:RefreshInPreyZoneStatus(self.state.questID, true)
        self:UpdateActiveHunt()
        return
    end

    if event == "PLAYER_ALIVE" then
        -- Dying before stage 4 resets the quest objective, but our cached
        -- widget snapshot would keep reporting the pre-death stage.  Drop the
        -- snapshot so the next pass reads whatever the widget reports now;
        -- do not fabricate a stage ourselves.  Stage 4 is exempt.
        if (tonumber(self.state.stage) or 0) < 4 then
            self:ClearWidgetSnapshot()
            self.state.stageFloor = 0
        end
        self:UpdateActiveHunt()
        return
    end

    if event == "QUEST_TURNED_IN" then
        -- Only react to the hunt we are actually tracking, otherwise every
        -- unrelated quest turn-in in the game fires the "prey slain" alert.
        local turnedIn = Prey.IsValidQuestID(arg1)
        self:InvalidateQuestCache()
        if turnedIn and (turnedIn == self.state.questID or Prey.PreyQuestData[turnedIn]) then
            self:OnQuestTurnedIn(turnedIn)
        end
        return
    end

    if event == "QUEST_REMOVED" then
        local removed = Prey.IsValidQuestID(arg1)
        self:InvalidateQuestCache()
        if removed and (removed == self.state.questID or Prey.PreyQuestData[removed]) then
            self.state.active = false
            self.state.questID = nil
            self:ResetHuntProgress()
            self:UpdateActiveHunt()
        end
        return
    end

    if event == "QUEST_ACCEPTED" or event == "QUEST_DETAIL" then
        -- The widget usually lags quest pickup, so poll hard for a few seconds.
        self:ArmQuestListenBurst()
        self:UpdateActiveHunt()
        return
    end

    if event == "GOSSIP_SHOW" then
        if Prey.Gossip then Prey.Gossip:OnGossipShow() end
        self:ArmQuestListenBurst()
        return
    end

    if event == "GOSSIP_CLOSED" then
        -- Stop decorating gossip buttons once we leave the hunt table, so the
        -- mixin hook does not tag unrelated NPCs.
        if Prey.Gossip then Prey.Gossip.activeForAstalor = false end
        return
    end

    if event == "CHAT_MSG_SYSTEM" or event == "CHAT_MSG_MONSTER_SAY" or event == "CHAT_MSG_MONSTER_YELL" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "RAID_BOSS_EMOTE" then
        -- arg1/arg2 can be secret (tainted) strings in WoW's protected
        -- execution environment.  Direct :lower() / :find() on them will
        -- throw "attempt to index a secret string value".  Guard with
        -- type checks and pcall before touching them.
        if type(arg1) ~= "string" and type(arg2) ~= "string" then return end

        if self:ShouldScanAmbushChat() then
            local matched = MatchesPreyNameTokens(self.state.targetName, arg1, arg2)
                or MatchesAnyPhrase(arg1, AMBUSH_FALLBACK_PHRASES)
            if matched then
                self:OnAmbushDetected()
            end
        end

        if self:ShouldScanBloodyCommandChat() and MatchesAnyPhrase(arg1, BLOODY_COMMAND_PHRASES) then
            self:OnBloodyCommandDetected()
        end
        return
    end

    if event == "UNIT_AURA" and arg1 ~= "player" then return end

    self:UpdateActiveHunt()
end)
