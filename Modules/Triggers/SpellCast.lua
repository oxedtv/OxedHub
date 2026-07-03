local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("UNIT_SPELLCAST_SUCCEEDED", {
    name = "Spell Cast Success",
    CheckCondition = function(trigger, eventData)
        -- Handled by general spellID check in Triggers:ShouldTrigger
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        if OxedHub.Triggers.CreateSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateSpellSearchUI(frame, trigger, yOffset)
        end
        return yOffset
    end
})
