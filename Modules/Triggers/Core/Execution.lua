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

    -- Potion and trinket rules can give each chosen item its own sound. The
    -- item that produced this cast decides which slot is used; an item left
    -- empty falls back to the rule's plain actions, so filling in one item does
    -- not silence the rest.
    if trigger.event == "ITEM_TRINKET" or trigger.event == "ITEM_POTION" then
        local itemID = Triggers.GetMatchedItemID and Triggers:GetMatchedItemID(trigger, eventData)
        if itemID then
            local prefix = Triggers:GetItemActionPrefix(itemID)
            local itemSound = actions[prefix .. "Sound"]
            local itemAnim = actions[prefix .. "Anim"]
            if itemSound and itemSound ~= "" and itemSound ~= "None" then
                soundKey = prefix .. "Sound"
            end
            if itemAnim and itemAnim ~= "" and itemAnim ~= "None" then
                animKey = prefix .. "Anim"
            end
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
            -- Not on top of a copy already showing. A buff refreshing arrives
            -- as another gain, and the repeat may still have the last run on
            -- screen; a second copy started here is what stacked them.
            if not (OxedHub.Animations.IsPlaying
                and OxedHub.Animations:IsPlaying(animVal)) then
                OxedHub.Animations:Play(animVal, posData)
            end
        end
    end

    -- Kept for loopdebug: says whether execution even reached the repeat, and
    -- with what. The block below is guarded by four things at once, and from
    -- outside there is no telling which of them said no.
    Triggers._lastExecute = {
        trigger = trigger.name,
        event = trigger.event,
        canRunEffects = canRunEffects and true or false,
        isLost = (eventData and eventData.isLost) and true or false,
        hasEventData = eventData ~= nil,
        at = GetTime(),
    }

    -- Keep going while the buff is up.
    --
    -- One ticker for both effects rather than two: they share a stop -- the
    -- aura being lost -- and the code that cancels them looks the loop up by a
    -- single key. Two tickers under one key would leave whichever was stored
    -- second running forever after the buff dropped.
    if canRunEffects and eventData and not eventData.isLost
        and (trigger.event == "UNIT_AURA" or trigger.event == "SELF_AURA"
            or trigger.event == "SPELL_PROC") then
        local conditions = trigger.conditions or {}
        local loopSound = conditions.loopSound and soundVal and soundVal ~= "" and soundVal ~= "None"
        local loopAnim = actions[animKey .. "LoopUntilLost"] and animVal and animVal ~= ""
        local interval = tonumber(conditions.loopInterval) or 2
        local spellID = eventData.spellID or eventData.spellName

        -- Kept for loopdebug. Every one of these has to be true for a repeat to
        -- start, and from the outside a repeat that never started looks exactly
        -- like one that started and stopped.
        Triggers._lastLoopAttempt = {
            trigger = trigger.name,
            animKey = animKey,
            animVal = tostring(animVal),
            loopAnim = loopAnim and true or false,
            loopSound = loopSound and true or false,
            interval = interval,
            hasSpell = spellID ~= nil,
            at = GetTime(),
        }

        if (loopSound or loopAnim) and interval > 0 and spellID then
            local soundPriority = tonumber(trigger.soundPriority) or 0
            local animPos
            if actions[animKey .. "UseCustomPosition"] then
                animPos = {
                    useCustomPosition = true,
                    x = actions[animKey .. "PositionX"] or 0,
                    y = actions[animKey .. "PositionY"] or 200,
                    displayWidth = actions[animKey .. "DisplayWidth"],
                    displayHeight = actions[animKey .. "DisplayHeight"],
                }
            end

            -- One loop per rule, whatever it was started by.
            --
            -- The key mixes in the spell, and the spell arrives as an id when
            -- the aura lands but sometimes only as a name when it drops -- two
            -- different keys for one aura, so the cancel missed and the ticker
            -- was left running. Every new gain then added another, which is
            -- both the stacking animations and the ones still playing long
            -- after the buff was gone. Clearing by rule cannot miss.
            Triggers:CancelTriggerLoops(trigger.id)
            -- Fresh start, so the last stop reason belongs to the run that has
            -- just ended, not to this one.
            Triggers._lastLoopStop = nil

            Triggers.activeAuraLoops = Triggers.activeAuraLoops or {}
            Triggers.auraLoopByTrigger = Triggers.auraLoopByTrigger or {}
            local loopKey = Triggers:BuildAuraLoopKey(trigger.id, spellID)

            -- Only where the spell is genuinely a buff. A proc glow is not an
            -- aura and never appears in the active set, so checking for it
            -- there would cancel the loop on its first tick.
            local watchedSpell = (trigger.event ~= "SPELL_PROC")
                and tonumber(eventData.spellID) or nil
            -- A repeat that outlives its buff is the worst failure here, so it
            -- is given two ways to die that do not depend on an event arriving.
            local startedAt = GetTime()
            local ticker
            -- Checked several times a second, not once per interval.
            --
            -- The interval belongs to the sound and says how often to repeat
            -- it. Driving the animation off the same grid left a gap between
            -- the end of one run and the next tick, which is the pause you see
            -- as stuttering; here it simply starts again the moment the last
            -- one has finished. Each check is a walk of a handful of pooled
            -- frames, and only while a repeat is actually running.
            local nextSoundAt = startedAt + interval
            ticker = C_Timer.NewTicker(0.1, function()
                -- No buff lasts an hour in a fight, and one that does is not
                -- worth an animation every two seconds. Whatever went wrong
                -- upstream, this ends it.
                if (GetTime() - startedAt) > 300 then
                    Triggers._lastLoopStop = "ran for five minutes"
                    Triggers:CancelTriggerLoops(trigger.id)
                    return
                end

                -- A backstop, not the normal way out.
                --
                -- The aura being lost is what stops this; the check below only
                -- covers a lost event that never arrives. It was doing far more
                -- than that: the set is keyed by the ids Core's scan produced,
                -- the event can name the same aura by a different id, and the
                -- set is only rebuilt when that scan runs -- so a healthy
                -- repeat was cancelling itself on its very first tick.
                --
                -- Hence the delay and the emptiness test: it only speaks up
                -- when it has been given time and has something to say.
                if watchedSpell and (GetTime() - startedAt) > 10 then
                    local active = OxedHub.Core and OxedHub.Core.activeSpellIDs
                    if active and next(active) and not active[watchedSpell] then
                        Triggers._lastLoopStop = "buff no longer in the active set"
                        Triggers:CancelTriggerLoops(trigger.id)
                        return
                    end
                end

                if loopSound and OxedHub.Sounds and GetTime() >= nextSoundAt then
                    nextSoundAt = GetTime() + interval
                    OxedHub.Sounds:Play(soundVal, nil, soundPriority)
                end
                -- Straight after the last run ends, so the animation reads as
                -- continuous. A check that lands while it is still playing does
                -- nothing rather than stacking a second copy on top.
                if loopAnim and OxedHub.Animations
                    and not (OxedHub.Animations.IsPlaying
                        and OxedHub.Animations:IsPlaying(animVal)) then
                    OxedHub.Animations:Play(animVal, animPos)
                end
            end)

            Triggers.activeAuraLoops[loopKey] = ticker
            Triggers.auraLoopByTrigger[trigger.id] = {
                ticker = ticker,
                key = loopKey,
                spellID = watchedSpell,
                startedAt = startedAt,
                interval = interval,
                triggerName = trigger.name,
                -- Only when the animation is the looping one. A one-shot
                -- animation is meant to finish; cutting it off because some
                -- other rule's buff dropped is not what was asked for.
                animation = loopAnim and animVal or nil,
            }
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


