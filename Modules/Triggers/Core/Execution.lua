local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime
local recentlyFired = {}
local triggerEffectsLastUsed = {}

local function GetTriggerEffectsDelay()
    local settings = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings
    local delay = settings and tonumber(settings.triggerEffectsDelay) or 5
    if not delay then
        delay = 5
    end
    return math.max(1, math.min(20, delay))
end

local function HasTriggerEffect(actions, soundKey, animKey, trigger, chatMsgKey, skipChat)
    if not actions then
        return false
    end
    if actions[soundKey] and actions[soundKey] ~= "" and actions[soundKey] ~= "None" then
        return true
    end
    if actions[animKey] and actions[animKey] ~= "" and actions[animKey] ~= "None" then
        return true
    end
    if not skipChat and trigger and trigger.event ~= "EAT_BUFF" then
        if actions.emote and actions.emote ~= "" and actions.emote ~= "None" then
            return true
        end
        if actions[chatMsgKey] and actions[chatMsgKey] ~= "" and actions[chatMsgKey] ~= "None" then
            return true
        end
    end
    return false
end

-- Shared per-key effects delay gate. Returns true if effects may run now
-- (and records the timestamp); false if still within the delay window.
function Triggers:CanRunEffectsKeyed(key)
    if not key then
        return true
    end
    local now = GetTime()
    local delay = GetTriggerEffectsDelay()
    local lastUsed = triggerEffectsLastUsed[key]
    if lastUsed and (now - lastUsed) < delay then
        return false
    end
    triggerEffectsLastUsed[key] = now
    return true
end

function Triggers:CanRunTriggerEffects(trigger, actions, soundKey, animKey, chatMsgKey, skipChat)
    if not trigger or not trigger.id then
        return true
    end

    if not HasTriggerEffect(actions, soundKey, animKey, trigger, chatMsgKey, skipChat) then
        return true
    end

    return self:CanRunEffectsKeyed(trigger.id)
end

function Triggers:ExecuteTrigger(trigger, eventData, skipChat)
    local actions = trigger.actions
    if not actions then return end

    -- Determine which action set to use (interrupt result-based)
    local result = eventData and eventData.result
    local isInterrupt = trigger.event == "INTERRUPT_USED"

    -- Skip action execution for "cast" tracking events;
    -- only "success" and "failed" should trigger sounds/animations
    if isInterrupt and result == "cast" then
        return
    end

    -- Debounce to prevent double-firing (e.g., from both macro and event)
    local now = GetTime()
    if recentlyFired[trigger.id] and (now - recentlyFired[trigger.id] < 0.5) then
        return
    end
    recentlyFired[trigger.id] = now

    local soundKey = "sound"
    local animKey = "animation"

    if isInterrupt and result then
        if result == "success" then
            soundKey = actions.successSound and actions.successSound ~= "" and "successSound" or "sound"
            animKey = actions.successAnimation and actions.successAnimation ~= "" and "successAnimation" or "animation"
        elseif result == "failed" then
            soundKey = actions.failSound and actions.failSound ~= "" and "failSound" or "sound"
            animKey = actions.failAnimation and actions.failAnimation ~= "" and "failAnimation" or "animation"
        end
    end

    local chatMsgKey = "chatMessage"
    if trigger.event == "SUMMON" and eventData and eventData.summonState then
        if eventData.summonState == "incoming" then
            chatMsgKey = "summonIncomingChatMessage"
        elseif eventData.summonState == "accepted" then
            chatMsgKey = "summonAcceptedChatMessage"
        elseif eventData.summonState == "declined" then
            chatMsgKey = "summonDeclinedChatMessage"
        end
    end

    local canRunEffects = self:CanRunTriggerEffects(trigger, actions, soundKey, animKey, chatMsgKey, skipChat)
    
    -- Play sound
    local soundVal = actions[soundKey]
    if canRunEffects and soundVal and soundVal ~= "" and soundVal ~= "None" then
        if OxedHub.Sounds then
            OxedHub.Sounds:Play(soundVal)
        end
    end
    
    -- Play animation
    local animVal = actions[animKey]
    if canRunEffects and animVal and animVal ~= "" then
        if OxedHub.Animations then
            OxedHub.Animations:Play(animVal)
        end
    end
    
    -- Perform emote
    -- TODO(beta): Emote disabled for EAT_BUFF to avoid ADDON_ACTION_BLOCKED taint.
    -- Re-enable once a clean chat bridge addon is implemented.
    if canRunEffects and not skipChat and actions.emote and actions.emote ~= "" and trigger.event ~= "EAT_BUFF" then
        local whisper = actions.whisperTarget or false
        local targetName = eventData and eventData.targetName
        if OxedHub.Emotes then
            OxedHub.Emotes:DoEmote(actions.emote, whisper, targetName)
        end
    end
    
    -- Print chat message or send template
    -- TODO(beta): Chat disabled for EAT_BUFF to avoid ADDON_ACTION_BLOCKED taint.
    -- Re-enable once a clean chat bridge addon is implemented.
    if canRunEffects and not skipChat and trigger.event ~= "EAT_BUFF" then
        local chatMsgVal = actions[chatMsgKey]
        if chatMsgVal and chatMsgVal ~= "" then
            if self:IsChatAllowedForEvent(trigger.event) then
                if OxedHub.ChatMessages and OxedHub.ChatMessages.Send then
                    OxedHub.ChatMessages:Send(chatMsgVal, nil, eventData)
                else
                    -- Fallback to local print if ChatMessages module is missing
                    print("|cff00ff00[OxedHub]|r " .. chatMsgVal)
                end
            end
        end
    end
    
    -- Note: Toy usage (actions.toy) is handled via the trigger macro body
    -- (/use ToyName), not here, because toys require a hardware button press
    -- (secure action). See Macros.lua:BuildDefaultTriggerMacroBody.
end


