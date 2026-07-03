local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("SUMMON", {
    name = "Summon",
    CheckCondition = function(trigger, eventData)
        local summonState = eventData and eventData.summonState
        if summonState ~= "incoming" and summonState ~= "accepted" and summonState ~= "declined" then
            return false
        end
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        -- No specific condition UI for summon
        return yOffset
    end
})
