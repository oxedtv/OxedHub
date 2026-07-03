local addonName, OxedHub = ...

local PetHandler = {
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        return yOffset
    end
}

OxedHub.Triggers:RegisterEventType("PET_DIED", PetHandler)
OxedHub.Triggers:RegisterEventType("PET_SUMMONED", PetHandler)
OxedHub.Triggers:RegisterEventType("PET_DISMISSED", PetHandler)
