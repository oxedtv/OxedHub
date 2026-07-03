local addonName, OxedHub = ...

local ControlHandler = {
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        if trigger.event == "CONTROL_LOST" and OxedHub.Triggers.CreateSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateSpellSearchUI(frame, trigger, yOffset)
        end
        return yOffset
    end
}

OxedHub.Triggers:RegisterEventType("CONTROL_LOST", ControlHandler)
OxedHub.Triggers:RegisterEventType("CONTROL_GAINED", ControlHandler)
