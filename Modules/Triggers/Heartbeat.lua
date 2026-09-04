local addonName, OxedHub = ...
local L = OxedHub.L

local Engine = CreateFrame("Frame")
Engine.activeStates = {} -- [triggerId] = { state, pendingState, handles, timer, isPlaying }

Engine.inCombat = false

Engine:RegisterEvent("PLAYER_REGEN_DISABLED")
Engine:RegisterEvent("PLAYER_REGEN_ENABLED")

Engine:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
        self:UpdateAllHeartbeats()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
        self:UpdateAllHeartbeats()
    end
end)

local soundFiles = {
    normal = "1",
    intense = "3",
    faster = "2",
    danger = "4",
    dead = "5"
}

-- helper to get sound path
local function GetSoundPath(conditions, state)
    local base = soundFiles[state]
    if not base then return nil end
    local suffix = ".ogg"
    if conditions.soundLevel == "lower" then
        suffix = "-5.ogg"
    elseif conditions.soundLevel == "lowest" then
        suffix = "-10.ogg"
    end
    return "Interface\\AddOns\\OxedHub\\Media\\Sounds\\Heartbeat\\" .. base .. suffix
end

local function StopCurrentSound(stateObj)
    if stateObj.timer then
        stateObj.timer:Cancel()
        stateObj.timer = nil
    end
    for i = 1, #(stateObj.handles or {}) do
        StopSound(stateObj.handles[i])
        stateObj.handles[i] = nil
    end
    stateObj.isPlaying = false
end

local function PlayHeartbeatSound(stateObj, conditions)
    -- Respect the dashboard Sounds toggle
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.soundsEnabled == false then
        return
    end

    local soundPath = GetSoundPath(conditions, stateObj.state)
    if stateObj.state ~= "NONE" and soundPath then
        for i = 1, #(stateObj.handles or {}) do
            StopSound(stateObj.handles[i])
            stateObj.handles[i] = nil
        end
        stateObj.handles = {}
        local channel = (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings
            and OxedHub.db.profile.settings.soundChannel) or "Master"
        -- Default 2, matching the standalone HeartBeat addon: the file is played
        -- twice over itself so it's audible over combat noise.
        local mult = conditions.volumeMultiplier or 2
        for i = 1, mult do
            local willPlay, handle = PlaySoundFile(soundPath, channel)
            if willPlay and handle then
                table.insert(stateObj.handles, handle)
            end
            if OxedHub.debug and i == 1 then
                print(("|cff00ffff[OxedHub-Debug]|r Heartbeat PlaySoundFile: state=%s willPlay=%s combat=%s"):format(
                    tostring(stateObj.state), tostring(willPlay), tostring(InCombatLockdown())))
            end
        end
    end
end

local TransitionToState

local function OnNextBeat(triggerId, stateObj, conditions)
    stateObj.timer = nil
    if stateObj.pendingState ~= stateObj.state then
        TransitionToState(triggerId, stateObj, conditions, stateObj.pendingState, true)
    else
        PlayHeartbeatSound(stateObj, conditions)
        local defaultIntervals = { normal = 1.981, faster = 1.844, intense = 1.654, danger = 1.237, dead = 6.808 }
        local interval = (conditions.intervals and conditions.intervals[stateObj.state]) or defaultIntervals[stateObj.state] or 1.981
        if interval and interval > 0 then
            stateObj.timer = C_Timer.NewTimer(interval, function()
                OnNextBeat(triggerId, stateObj, conditions)
            end)
        else
            stateObj.isPlaying = false
        end
    end
end

function TransitionToState(triggerId, stateObj, conditions, newState, forceRestart)
    if stateObj.state == newState and stateObj.pendingState == newState and not forceRestart then return end

    if not forceRestart and stateObj.isPlaying and stateObj.state ~= "NONE" then
        if newState ~= "dead" then
            stateObj.pendingState = newState
            return
        end
    end

    StopCurrentSound(stateObj)
    stateObj.state = newState
    stateObj.pendingState = newState

    if newState ~= "NONE" then
        stateObj.isPlaying = true
        PlayHeartbeatSound(stateObj, conditions)
        if newState ~= "dead" then
            local defaultIntervals = { normal = 1.981, faster = 1.844, intense = 1.654, danger = 1.237, dead = 6.808 }
            local interval = (conditions.intervals and conditions.intervals[newState]) or defaultIntervals[newState] or 1.981
            if interval and interval > 0 then
                stateObj.timer = C_Timer.NewTimer(interval, function()
                    OnNextBeat(triggerId, stateObj, conditions)
                end)
            end
        else
            stateObj.isPlaying = false
        end
    end
end

function Engine:UpdateTrigger(triggerId, trigger)
    local conditions = trigger.conditions or {}
    local stateObj = self.activeStates[triggerId]
    if not stateObj then
        stateObj = { state = "NONE", pendingState = "NONE", handles = {}, isPlaying = false }
        self.activeStates[triggerId] = stateObj
    end



    if not trigger.enabled then
        TransitionToState(triggerId, stateObj, conditions, "NONE")
        return
    end

    local isDead = UnitIsDeadOrGhost("player")
    if isDead then
        TransitionToState(triggerId, stateObj, conditions, "dead")
        return
    end

    if conditions.combatOnly and not self.inCombat then
        TransitionToState(triggerId, stateObj, conditions, "NONE")
        return
    end

    local targetState = "NONE"

    if self.inCombat then
        targetState = conditions.inCombatState or "intense"
    else
        targetState = conditions.outOfCombatState or "normal"
    end

    if OxedHub.debug and targetState ~= stateObj.state then
        print(("|cff00ffff[OxedHub-Debug]|r Heartbeat: state=%s->%s combat=%s"):format(
            tostring(stateObj.state), targetState, tostring(self.inCombat)))
    end

    TransitionToState(triggerId, stateObj, conditions, targetState)
end


function Engine:UpdateAllHeartbeats()
    if not OxedHub.db or not OxedHub.db.profile or not OxedHub.db.profile.triggers then
        return
    end

    local seen = {}
    for triggerId, trigger in pairs(OxedHub.db.profile.triggers) do
        if trigger.event == "HEARTBEAT" then
            seen[triggerId] = true
            self:UpdateTrigger(triggerId, trigger)
        end
    end

    -- Cleanup removed triggers
    for id, stateObj in pairs(self.activeStates) do
        if not seen[id] then
            StopCurrentSound(stateObj)
            self.activeStates[id] = nil
        end
    end
end

Engine:RegisterEvent("PLAYER_REGEN_DISABLED")
Engine:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Filtered at the client rather than in the handler below. Both fire for every
-- unit in the group, so in a raid this was waking Lua hundreds of times a
-- second only to drop the event on its first line.
Engine:RegisterUnitEvent("UNIT_HEALTH", "player")
Engine:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
Engine:RegisterEvent("PLAYER_DEAD")
Engine:RegisterEvent("PLAYER_UNGHOST")
Engine:RegisterEvent("PLAYER_ALIVE")
Engine:RegisterEvent("PLAYER_ENTERING_WORLD")

Engine:SetScript("OnEvent", function(self, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit and unit ~= "player" then return end
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- DB may not be ready yet on first login; kick a delayed update
        C_Timer.After(2, function() Engine:UpdateAllHeartbeats() end)
    end
    self:UpdateAllHeartbeats()
end)

-- Background ticker: ensures heartbeat starts immediately when a trigger is
-- created/enabled at full HP (no UNIT_HEALTH event fires if health isn't changing).
-- Runs every 1 second — lightweight since UpdateAllHeartbeats is cheap when idle.
Engine._ticker = C_Timer.NewTicker(1, function()
    Engine:UpdateAllHeartbeats()
end)

OxedHub.Triggers:RegisterEventType("HEARTBEAT", {
    name = L["EVT_HEARTBEAT"] or "Heartbeat",
    CheckCondition = function(trigger, eventData)
        -- The audio looping is handled internally by Engine based on state.
        -- We return false so it doesn't fire the standard action (sound/anim).
        return false
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}
        local conditions = trigger.conditions
        local safeId = tostring(trigger.id):gsub("%W", "")
        
        -- Default intervals
        conditions.intervals = conditions.intervals or {
            normal = 1.981,
            faster = 1.844,
            intense = 1.654,
            danger = 1.237,
            dead = 6.808
        }
        
        local function AutoSaved()
            Engine:UpdateAllHeartbeats()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end

        local combatCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        combatCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        combatCheck:SetSize(20, 20)
        combatCheck:SetChecked(conditions.combatOnly or false)
        combatCheck.text:SetText("Combat Only")
        combatCheck:SetScript("OnClick", function(self)
            conditions.combatOnly = self:GetChecked()
            AutoSaved()
        end)
        yOffset = yOffset - 40
        
        -- Volume boost slider
        local volLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        volLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, yOffset)
        volLabel:SetText("Volume Boost (Multiplier)")
        
        local volSliderName = "OxedHub_Heartbeat_Vol_" .. safeId
        local volSlider = CreateFrame("Slider", volSliderName, frame, "OptionsSliderTemplate")
        volSlider:SetPoint("TOPLEFT", volLabel, "BOTTOMLEFT", 0, -5)
        volSlider:SetWidth(180)
        volSlider:SetMinMaxValues(1, 5)
        volSlider:SetValueStep(1)
        volSlider:SetObeyStepOnDrag(true)
        volSlider:SetValue(conditions.volumeMultiplier or 1)
        _G[volSliderName.."Low"]:SetText("1x")
        _G[volSliderName.."High"]:SetText("5x")
        local vText = _G[volSliderName.."Text"]
        vText:ClearAllPoints()
        vText:SetPoint("LEFT", volSlider, "RIGHT", 10, 0)
        vText:SetText((conditions.volumeMultiplier or 1) .. "x")
        volSlider:SetScript("OnValueChanged", function(self, value)
            conditions.volumeMultiplier = value
            _G[self:GetName().."Text"]:SetText(value .. "x")
            local stateObj = Engine.activeStates[trigger.id]
            if stateObj and stateObj.state ~= "NONE" then
                TransitionToState(trigger.id, stateObj, conditions, stateObj.state, true)
            end
            AutoSaved()
        end)
        
        yOffset = yOffset - 50

        -- Sound Level Dropdown (cyclic button)
        local levels = {
            {id = "normal", name = "Normal"},
            {id = "lower", name = "Lower (-5 dB)"},
            {id = "lowest", name = "Lowest (-10 dB)"}
        }
        
        local currentLevelIndex = 1
        for i, v in ipairs(levels) do
            if v.id == (conditions.soundLevel or "normal") then
                currentLevelIndex = i
                break
            end
        end
        
        local lvlBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        lvlBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, yOffset)
        lvlBtn:SetSize(160, 24)
        lvlBtn:SetText("Sound: " .. levels[currentLevelIndex].name)
        lvlBtn:SetScript("OnClick", function(self)
            currentLevelIndex = currentLevelIndex + 1
            if currentLevelIndex > #levels then currentLevelIndex = 1 end
            conditions.soundLevel = levels[currentLevelIndex].id
            self:SetText("Sound: " .. levels[currentLevelIndex].name)
            local stateObj = Engine.activeStates[trigger.id]
            if stateObj and stateObj.state ~= "NONE" then
                TransitionToState(trigger.id, stateObj, conditions, stateObj.state, true)
            end
            AutoSaved()
        end)
        
        -- Right Side: Dropdowns
        local rightOffsetX = 280
        local rightY = -10
        
        local oocLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        oocLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", rightOffsetX, rightY)
        oocLabel:SetText("Out of Combat Speed")
        
        local oocDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        oocDropdown:SetPoint("TOPLEFT", oocLabel, "BOTTOMLEFT", 0, -5)
        oocDropdown:SetSize(180, 26)
        
        local icLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        icLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", rightOffsetX, rightY - 50)
        icLabel:SetText("In Combat Speed")
        
        local icDropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
        icDropdown:SetPoint("TOPLEFT", icLabel, "BOTTOMLEFT", 0, -5)
        icDropdown:SetSize(180, 26)
        
        local stateLevels = {
            {id = "normal", name = "Normal"},
            {id = "faster", name = "Faster"},
            {id = "intense", name = "Intense"},
            {id = "danger", name = "Danger"}
        }

        local function GetStateName(id, defId)
            for _, v in ipairs(stateLevels) do
                if v.id == (id or defId) then return v.name end
            end
            return defId
        end

        oocDropdown:OverrideText(GetStateName(conditions.outOfCombatState, "normal"))
        oocDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, state in ipairs(stateLevels) do
                rootDescription:CreateButton(state.name, function()
                    conditions.outOfCombatState = state.id
                    oocDropdown:OverrideText(state.name)
                    AutoSaved()
                end)
            end
        end)

        icDropdown:OverrideText(GetStateName(conditions.inCombatState, "intense"))
        icDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, state in ipairs(stateLevels) do
                rootDescription:CreateButton(state.name, function()
                    conditions.inCombatState = state.id
                    icDropdown:OverrideText(state.name)
                    AutoSaved()
                end)
            end
        end)

        return yOffset - 35
    end
})
