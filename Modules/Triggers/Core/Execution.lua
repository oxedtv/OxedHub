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

local function HasTriggerEffect(actions, soundKey, animKey, iconKey, trigger, chatMsgKey, skipChat)
    if not actions then
        return false
    end
    if actions[soundKey] and actions[soundKey] ~= "" and actions[soundKey] ~= "None" then
        return true
    end
    if actions[animKey] and actions[animKey] ~= "" and actions[animKey] ~= "None" then
        return true
    end
    if actions[iconKey] and actions[iconKey] ~= "" and actions[iconKey] ~= "None" then
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

function Triggers:CanRunTriggerEffects(trigger, actions, soundKey, animKey, iconKey, chatMsgKey, skipChat)
    if not trigger or not trigger.id then
        return true
    end

    if not HasTriggerEffect(actions, soundKey, animKey, iconKey, trigger, chatMsgKey, skipChat) then
        return true
    end

    -- Determine if effects should run based on global effect delay (e.g. 5 seconds)
    -- Skip delay entirely for simple slash commands and aura events. SELF_AURA must
    -- be exempt too — otherwise the initial "gained" is throttled and, because the
    -- loop-sound is started inside the effect gate, the loop never starts (buff
    -- sound wouldn't play in combat until the throttle happened to clear).
    local canRunEffects = false
    if trigger.event == "SLASH_CMD" or trigger.event == "UNIT_AURA" or trigger.event == "SELF_AURA" or trigger.event == "SPELL_PROC" then
        canRunEffects = true
    else
        canRunEffects = self:CanRunEffectsKeyed(trigger.id)
    end
    return canRunEffects
end

function Triggers:ExecuteTrigger(trigger, eventData, skipChat)
    if OxedHub.debug then print("[OxedHub-Debug] ExecuteTrigger called for trigger:", trigger.name or trigger.id, "event:", trigger.event) end
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
        if OxedHub.debug then print("[OxedHub-Debug] ExecuteTrigger debounced (<0.5s)") end
        return
    end
    recentlyFired[trigger.id] = now

    -- Recorded here rather than in ProcessEvent: this is the point where the
    -- rule has passed every check and its debounce, so it is the first moment
    -- the firing is real.
    if Triggers.RecordTriggerFired then
        Triggers:RecordTriggerFired(trigger, eventData)
    end

    local soundKey = "sound"
    local animKey = "animation"
    local iconKey = "icon"

    if isInterrupt and result then
        if result == "success" then
            soundKey = actions.successSound and actions.successSound ~= "" and "successSound" or "sound"
            animKey = actions.successAnimation and actions.successAnimation ~= "" and "successAnimation" or "animation"
            iconKey = actions.successIcon and actions.successIcon ~= "" and "successIcon" or "icon"
        elseif result == "failed" then
            soundKey = actions.failSound and actions.failSound ~= "" and "failSound" or "sound"
            animKey = actions.failAnimation and actions.failAnimation ~= "" and "failAnimation" or "animation"
            iconKey = actions.failIcon and actions.failIcon ~= "" and "failIcon" or "icon"
        end
    elseif trigger.event == "MOUNT" and eventData and eventData.mountType then
        local t = eventData.mountType
        if t == "ground" or t == "flying" or t == "aquatic" then
            soundKey = t .. "Sound"
            animKey = t .. "Anim"
            iconKey = t .. "Icon"
        end
    elseif trigger.event == "COMBAT_STATE" and eventData and eventData.combatState then
        -- Only split the effects when the user ticked "different sound &
        -- animation"; otherwise enter and exit share the normal Sound/Animation.
        if trigger.conditions and trigger.conditions.separateEffects then
            local prefix = eventData.combatState == "enter" and "enter" or "exit"
            if actions[prefix .. "Sound"] and actions[prefix .. "Sound"] ~= "" then
                soundKey = prefix .. "Sound"
            end
            if actions[prefix .. "Anim"] and actions[prefix .. "Anim"] ~= "" then
                animKey = prefix .. "Anim"
            end
            if actions[prefix .. "Icon"] and actions[prefix .. "Icon"] ~= "" then
                iconKey = prefix .. "Icon"
            end
        end
    end

    local chatMsgKey = "chatMessage"
    local emoteKey = "emote"
    if trigger.event == "SUMMON" and eventData and eventData.summonState then
        if eventData.summonState == "incoming" then
            chatMsgKey = "summonIncomingChatMessage"
        elseif eventData.summonState == "accepted" then
            chatMsgKey = "summonAcceptedChatMessage"
        elseif eventData.summonState == "declined" then
            chatMsgKey = "summonDeclinedChatMessage"
        end
    elseif trigger.event == "MOUNT" and eventData and eventData.mountType then
        local t = eventData.mountType
        if t == "ground" or t == "flying" or t == "aquatic" then
            chatMsgKey = t .. "Chat"
            emoteKey = t .. "Emote"
        end
    end

    local canRunEffects = self:CanRunTriggerEffects(trigger, actions, soundKey, animKey, iconKey, chatMsgKey, skipChat)
    if OxedHub.debug then print("[OxedHub-Debug] canRunEffects:", canRunEffects, "sound:", actions[soundKey]) end
    
    -- Play sound
    local soundVal = actions[soundKey]
    if canRunEffects and soundVal and soundVal ~= "" and soundVal ~= "None" then
        if OxedHub.Sounds then
            if OxedHub.debug then print("[OxedHub-Debug] Actually playing sound:", soundVal) end
            -- The rule's own importance, used only when two sounds land in the
            -- same instant and the player asked for priority to decide.
            local soundPriority = tonumber(trigger.soundPriority) or 0
            OxedHub.Sounds:Play(soundVal, nil, soundPriority)

            if (trigger.event == "UNIT_AURA" or trigger.event == "SELF_AURA" or trigger.event == "SPELL_PROC") and trigger.conditions and trigger.conditions.loopSound and eventData and not eventData.isLost then
                local interval = tonumber(trigger.conditions.loopInterval) or 2
                if interval > 0 then
                    local spellID = eventData.spellID or eventData.spellName
                    if spellID then
                        Triggers.activeAuraLoops = Triggers.activeAuraLoops or {}
                        local loopKey = Triggers:BuildAuraLoopKey(trigger.id, spellID)
                        if Triggers.activeAuraLoops[loopKey] then
                            Triggers.activeAuraLoops[loopKey]:Cancel()
                        end
                        Triggers.activeAuraLoops[loopKey] = C_Timer.NewTicker(interval, function()
                            OxedHub.Sounds:Play(soundVal, nil, soundPriority)
                        end)
                    end
                end
            end
        end
    end
    
    -- Play animation, honouring a per-trigger position when one was set with
    -- Move / Scale in the trigger's Actions section.
    local animVal = actions[animKey]
    if canRunEffects and animVal and animVal ~= "" then
        if OxedHub.Animations then
            local posData
            if actions[animKey .. "UseCustomPosition"] then
                posData = {
                    useCustomPosition = true,
                    x = actions[animKey .. "PositionX"] or 0,
                    y = actions[animKey .. "PositionY"] or 200,
                    displayWidth = actions[animKey .. "DisplayWidth"],
                    displayHeight = actions[animKey .. "DisplayHeight"],
                }
            end
            OxedHub.Animations:Play(animVal, posData)
        end
    end
    
    -- Play Icon
    if canRunEffects and actions.showIcon then
        if OxedHub.Icons then
            local posData = {}
            if actions.iconUseCustomPosition then
                posData.useCustomPosition = true
                posData.x = actions.iconPositionX or 0
                posData.y = actions.iconPositionY or 200
                posData.size = actions.iconSize or 64
            end
            posData.style = actions.iconStyle or "SQUARE"
            posData.showCooldown = actions.iconShowCooldown
            posData.showDuration = actions.iconShowDuration
            local isLustTrigger = OxedHub.IsLustTrigger and OxedHub.IsLustTrigger(trigger)
            posData.iconTextureType = actions.iconTextureType or (isLustTrigger and "FACTION" or "SPELL")
            if isLustTrigger and posData.iconTextureType == "SPELL" then
                posData.iconTextureType = "FACTION"
            end
            
            -- Derive icon texture and CD from eventData if available
            local spellID = eventData and (eventData.spellID or eventData.spellName)
            if not spellID and trigger.conditions then spellID = trigger.conditions.spellID end
            
            local duration = eventData and eventData.duration
            local expirationTime = eventData and eventData.expirationTime
            
            if eventData and eventData.isLost then
                if OxedHub.Icons.StopScreenIcon then
                    OxedHub.Icons:StopScreenIcon(spellID)
                end
            else
                local isAura = (trigger.event == "SELF_AURA" or trigger.event == "UNIT_AURA")
                OxedHub.Icons:PlayScreenIcon(spellID, posData, duration, expirationTime, isAura)
            end
        end
    end
    
    -- Perform emote
    -- TODO(beta): Emote disabled for EAT_BUFF to avoid ADDON_ACTION_BLOCKED taint.
    -- Re-enable once a clean chat bridge addon is implemented.
    if canRunEffects and not skipChat and actions[emoteKey] and actions[emoteKey] ~= "" and trigger.event ~= "EAT_BUFF" then
        local whisper = actions.whisperTarget or false
        local targetName = eventData and eventData.targetName
        if OxedHub.Emotes then
            OxedHub.Emotes:DoEmote(actions[emoteKey], whisper, targetName)
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
    
    if OxedHub.debug then
        print(string.format("|cff00ffff[OxedHub-Debug]|r Trigger Executed: |cffffff00%s|r (Event: %s)", trigger.name or "Unknown", trigger.event or "Unknown"))
        if soundVal and soundVal ~= "" and soundVal ~= "None" then
            print(string.format("  - Sound: %s (Key: %s)", tostring(soundVal), soundKey))
        end
        if animVal and animVal ~= "" and animVal ~= "None" then
            print(string.format("  - Animation: %s (Key: %s)", tostring(animVal), animKey))
        end
        if iconVal and iconVal ~= "" and iconVal ~= "None" then
            print(string.format("  - Icon: %s (Key: %s)", tostring(iconVal), iconKey))
        end
        if actions[emoteKey] and actions[emoteKey] ~= "" and actions[emoteKey] ~= "None" then
            print(string.format("  - Emote: %s", tostring(actions[emoteKey])))
        end
        local chatMsgVal = actions[chatMsgKey]
        if chatMsgVal and chatMsgVal ~= "" and chatMsgVal ~= "None" then
            print(string.format("  - Chat: %s", tostring(chatMsgVal)))
        end
    end
    
    -- Note: Toy usage (actions.toy) is handled via the trigger macro body
    -- (/use ToyName), not here, because toys require a hardware button press
    -- (secure action). See Macros.lua:BuildDefaultTriggerMacroBody.
end


