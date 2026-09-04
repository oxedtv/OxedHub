local addonName, OxedHub = ...

-- Spell Cast Start
--
-- Spell Cast Success fires when a cast finishes, which is the wrong moment for
-- anything meant as a heads-up. A call for Mass Resurrection announced after
-- the resurrection has already landed tells the raid nothing they cannot see.
--
-- This fires the instant the cast bar appears instead, and again for channels,
-- so "I am starting this" and "I am channelling this" both count as a start.
--
-- Only spells with a cast time can fire it: an instant has no start to speak
-- of, and the client sends nothing for one. That is worth saying in the
-- description, because a rule set up on an instant would look broken.
local Triggers = OxedHub.Triggers

-- The condition UI is the spell picker plus the class suggestion grid, which is
-- exactly what Spell Cast Success already builds. Borrowed rather than copied:
-- two divergent copies of that grid is how the suggestions end up disagreeing
-- about which spells a spec knows.
local base = Triggers:GetEventTypeHandler("UNIT_SPELLCAST_SUCCEEDED")

Triggers:RegisterEventType("UNIT_SPELLCAST_START", {
    name = "Spell Cast Start",
    CheckCondition = function(trigger, eventData)
        -- Spell matching is done centrally in Triggers:ShouldTrigger.
        return true
    end,
    CreateConditionUI = base and base.CreateConditionUI or nil,
})
