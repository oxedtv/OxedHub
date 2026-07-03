local addonName, OxedHub = ...

local InterruptHandler = {
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        if OxedHub.Triggers.CreateSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateSpellSearchUI(frame, trigger, yOffset)
        end
        return yOffset
    end
}

OxedHub.Triggers:RegisterEventType("INTERRUPT_USED", InterruptHandler)
OxedHub.Triggers:RegisterEventType("SPELL_INTERRUPTED", InterruptHandler)
