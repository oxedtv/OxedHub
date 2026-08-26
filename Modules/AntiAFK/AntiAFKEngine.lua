local addonName, OxedHub = ...

local AntiAFK = OxedHub.AntiAFK or {}
OxedHub.AntiAFK = AntiAFK

local COMM_PREFIX = "AFKGuardBG"
local COMM_BROADCAST_INTERVAL = 15
local COMM_HEARD_TIMEOUT = 35

-- State
local elapsed = 0
local ticker = nil
local lastTickTime = nil
local isPlayerMoving = false
local currentPhase = "none" -- "none" | "yellow" | "red" | "move"
local heard = {}
local commTicker = nil
local eligibilityTicker = nil

local stagePlaybackTicker = nil
local stagePlaybackCount = 0

local function IsEligibleBG()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "pvp" then
        return false
    end
    if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
        return false
    end
    return true
end

local function GetInitialMovingState()
    if not GetUnitSpeed then return false end
    local ok, speed = pcall(GetUnitSpeed, "player")
    if not ok then return false end
    -- Ask before touching it: a secret value cannot be compared at all.
    if issecretvalue and issecretvalue(speed) then
        return false
    end
    if speed == nil then return false end
    local ok, moving = pcall(function() return speed > 0 end)
    return ok and moving or false
end

function AntiAFK:GetActiveTrigger()
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then return nil end
    for id, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger and trigger.enabled and trigger.event == "PVP_ANTI_AFK" then
            return trigger
        end
    end
    return nil
end

function AntiAFK:PlayStageAnimation(trigger, animKey)
    if not trigger or not animKey then return end
    local actions = trigger.actions or {}
    local cond = trigger.conditions or {}
    local animVal = actions[animKey] or cond[animKey]
    if not animVal or animVal == "" or animVal == "None" then return end

    local posData = nil
    if actions[animKey .. "UseCustomPosition"] then
        posData = {
            x = actions[animKey .. "PositionX"],
            y = actions[animKey .. "PositionY"],
            width = actions[animKey .. "DisplayWidth"],
            height = actions[animKey .. "DisplayHeight"],
        }
    end
    if OxedHub.Animations and OxedHub.Animations.Play then
        OxedHub.Animations:Play(animVal, posData)
    end
end

function AntiAFK:StopStageAlert()
    if stagePlaybackTicker then
        stagePlaybackTicker:Cancel()
        stagePlaybackTicker = nil
    end
    stagePlaybackCount = 0
    self:StopAllSounds()
end

function AntiAFK:TriggerStageAlert(trigger, stageKey)
    local cond = trigger.conditions or {}
    local actions = trigger.actions or {}
    local soundVal = actions[stageKey .. "Sound"] or cond[stageKey .. "Sound"]
    local animKey = stageKey .. "Animation"
    local defaultMode = (stageKey == "move") and "once" or "loop"
    local mode = actions[stageKey .. "Mode"] or defaultMode
    local count = tonumber(actions[stageKey .. "Count"]) or 3
    if count < 1 then count = 1 end

    self:StopStageAlert()

    local function PlayIteration()
        -- Play sound
        if soundVal and soundVal ~= "" and soundVal ~= "None" then
            AntiAFK:PlaySoundDirect(soundVal)
        else
            if stageKey == "move" then
                PlaySound(9278, "Master")
            else
                PlaySound(8959, "Master")
            end
        end
        -- Play animation
        AntiAFK:PlayStageAnimation(trigger, animKey)
    end

    PlayIteration()
    stagePlaybackCount = 1

    if mode == "loop" then
        local interval = (stageKey == "red") and 0.75 or 1.0
        stagePlaybackTicker = C_Timer.NewTicker(interval, function()
            PlayIteration()
        end)
    elseif mode == "repeat" and count > 1 then
        local interval = (stageKey == "red") and 0.75 or 1.0
        stagePlaybackTicker = C_Timer.NewTicker(interval, function()
            if stagePlaybackCount >= count then
                if stagePlaybackTicker then
                    stagePlaybackTicker:Cancel()
                    stagePlaybackTicker = nil
                end
                return
            end
            stagePlaybackCount = stagePlaybackCount + 1
            PlayIteration()
        end)
    end
end

local function GetCommChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function BroadcastAlive()
    local channel = GetCommChannel()
    if not channel then return end
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, "ALIVE:1.1", channel)
end

function AntiAFK:ResetTimer()
    elapsed = 0
    currentPhase = "none"
    self:StopStageAlert()
    local trigger = self:GetActiveTrigger()
    local cond = trigger and trigger.conditions or {}
    local isTest = cond.testMode == true
    local maxTime = isTest and 100 or (cond.maxTime or 300)
    local showTimer = cond.showTimer ~= false
    self:UpdateTimerDisplay(0, maxTime, "none", showTimer, false)
end

local function OnTick()
    local trigger = AntiAFK:GetActiveTrigger()
    if not trigger then
        AntiAFK:StopTimer()
        return
    end

    local cond = trigger.conditions or {}
    local isTest = cond.testMode == true

    local yellowThreshold = isTest and 15 or (cond.yellowThreshold or 120)
    local redThreshold    = isTest and 30 or (cond.redThreshold or 180)
    local moveThreshold   = isTest and 45 or (cond.moveThreshold or 210)
    local maxTime         = isTest and 100 or (cond.maxTime or 300)
    local showTimer       = cond.showTimer ~= false
    local showMoveBanner  = cond.showMoveBanner ~= false

    local now = GetTime()
    local delta = lastTickTime and (now - lastTickTime) or 0.1
    lastTickTime = now

    -- GetUnitSpeed can hand back a secret value.  The pcall below only covered
    -- the CALL -- the "spd > 0" comparison sat outside it, so a secret speed
    -- threw an unprotected error on every tick and the whole timer stopped
    -- advancing.  GetInitialMovingState already guarded this correctly; reuse
    -- the same check here.
    local isMovingNow = isPlayerMoving
    if not isMovingNow then
        isMovingNow = GetInitialMovingState()
    end

    if isMovingNow then
        elapsed = 0
        currentPhase = "none"
        AntiAFK:StopStageAlert()
    else
        elapsed = math.min(maxTime, elapsed + delta)
    end

    if elapsed >= moveThreshold then
        if currentPhase ~= "move" then
            currentPhase = "move"
            AntiAFK:TriggerStageAlert(trigger, "move")
        end
    elseif elapsed >= redThreshold then
        if currentPhase ~= "red" then
            currentPhase = "red"
            AntiAFK:TriggerStageAlert(trigger, "red")
        end
    elseif elapsed >= yellowThreshold then
        if currentPhase ~= "yellow" then
            currentPhase = "yellow"
            AntiAFK:TriggerStageAlert(trigger, "yellow")
        end
    else
        if currentPhase ~= "none" then
            currentPhase = "none"
            AntiAFK:StopStageAlert()
        end
    end

    AntiAFK:UpdateTimerDisplay(elapsed, maxTime, currentPhase, showTimer, showMoveBanner)
end

function AntiAFK:StartTimer()
    if ticker then return end
    lastTickTime = nil
    isPlayerMoving = GetInitialMovingState()
    self:ResetTimer()
    ticker = C_Timer.NewTicker(0.1, OnTick)
end

function AntiAFK:StopTimer()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    self:HideAll()
end

function AntiAFK:CheckState()
    local trigger = self:GetActiveTrigger()
    if not trigger then
        self:StopTimer()
        return
    end

    local cond = trigger.conditions or {}

    -- "Active only in Battlegrounds" is the outer gate and now applies in test
    -- mode too.  Test mode used to return early and start the timer anywhere,
    -- so the guard appeared to run out in the world even with the box ticked.
    -- To try it outside a BG, untick that box; test mode only shortens timers.
    local bgOnly = cond.bgOnly ~= false
    if bgOnly and not IsEligibleBG() then
        self:StopTimer()
        return
    end

    self:StartTimer()
end

-- ------------------------------------------------------------
-- Events Frame
-- ------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_STARTED_MOVING")
eventFrame:RegisterEvent("PLAYER_STOPPED_MOVING")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_STARTED_MOVING" then
        isPlayerMoving = true
        return
    end

    if event == "PLAYER_STOPPED_MOVING" then
        isPlayerMoving = false
        return
    end

    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix == COMM_PREFIX then
            local msgType, payload = message:match("^(%a+):(.*)$")
            if msgType == "ALIVE" then
                local shortName = Ambiguate(sender, "short")
                heard[shortName] = { time = GetTime(), version = payload }
            end
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
        if not commTicker then
            commTicker = C_Timer.NewTicker(COMM_BROADCAST_INTERVAL, BroadcastAlive)
        end
        if not eligibilityTicker then
            eligibilityTicker = C_Timer.NewTicker(1, function()
                pcall(function() AntiAFK:CheckState() end)
            end)
        end
    end

    AntiAFK:CheckState()
    BroadcastAlive()
end)
