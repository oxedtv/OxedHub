local addonName, OxedHub = ...

local GeneralHandler = {
    CheckCondition = function(trigger, eventData)
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        if (trigger.event == "CD_READY" or trigger.event == "RAID_TOOL") and OxedHub.Triggers.CreateSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateSpellSearchUI(frame, trigger, yOffset)
        end
        return yOffset
    end
}

OxedHub.Triggers:RegisterEventType("PLAYER_DEAD", GeneralHandler)
OxedHub.Triggers:RegisterEventType("CHALLENGE_MODE_COMPLETED", GeneralHandler)
OxedHub.Triggers:RegisterEventType("CD_READY", GeneralHandler)
OxedHub.Triggers:RegisterEventType("ACHIEVEMENT", GeneralHandler)
OxedHub.Triggers:RegisterEventType("RAID_TOOL", GeneralHandler)
OxedHub.Triggers:RegisterEventType("PARTY_MEMBER_DEATH", GeneralHandler)
OxedHub.Triggers:RegisterEventType("PLAYER_LEVEL_UP", GeneralHandler)
OxedHub.Triggers:RegisterEventType("NEW_MAIL", GeneralHandler)
OxedHub.Triggers:RegisterEventType("REACH_FLY_DESTINATION", GeneralHandler)

-- Group / party events (straight pass-throughs of the Blizzard events).
OxedHub.Triggers:RegisterEventType("GROUP_JOINED", GeneralHandler)
OxedHub.Triggers:RegisterEventType("GROUP_LEFT", GeneralHandler)
OxedHub.Triggers:RegisterEventType("PARTY_INVITE_REQUEST", GeneralHandler)
OxedHub.Triggers:RegisterEventType("PARTY_LEADER_CHANGED", GeneralHandler)
