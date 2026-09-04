local addonName, OxedHub = ...

-- ── Event help ───────────────────────────────────────────────────────────────
-- The long version of what each trigger event does.
--
-- The one-line desc in CONFIG.EVENT_TYPES has to fit a dropdown, so it can only
-- name the event. It cannot say when the event arrives relative to what the
-- player sees, what it will not catch, or what a sensible rule built on it
-- looks like -- and those are exactly the things people get wrong.
--
-- Fields, all optional:
--   fires    when the game sends it, in the player's terms
--   needs    what the rule must have set for it to work at all
--   limits   what it will NOT catch; the honest part
--   example  one concrete rule worth building
--
-- Anything with no entry here falls back to its one-line desc, so the icon is
-- never empty and this table can be filled in over time.
OxedHub.EVENT_HELP = {
    ["UNIT_SPELLCAST_SUCCEEDED"] = {
        fires = "The instant a cast completes -- after the cast bar finishes, or immediately for an instant spell.",
        needs = "At least one spell chosen. Without one it would fire on everything you cast, so it stays silent.",
        limits = "Too late to warn anybody about a long cast: by the time this fires, the spell has already landed. Use Spell Cast Start for that.",
        example = "Play a sound when you use Hearthstone, or when a portal goes down.",
    },
    ["UNIT_SPELLCAST_START"] = {
        fires = "The moment the cast bar appears, and again when a channel begins.",
        needs = "At least one spell chosen, for the same reason as Spell Cast Success.",
        limits = "Instant spells never reach this. They have no cast to begin, and the game sends nothing -- a rule built on one will simply never fire.",
        example = "Announce Mass Resurrection while it is still casting, so the raid knows to stop moving.",
    },
    ["UNIT_AURA"] = {
        fires = "Whenever a buff or debuff on you changes -- gained, refreshed, or lost.",
        needs = "A spell or aura name. This event is one of the busiest in the game.",
        limits = "Fires for refreshes too, so a stacking aura can announce itself repeatedly. Sound is blocked mid-combat on some builds; My Buff (by Spell ID) uses the native path and is not.",
        example = "React when you pick up a specific raid buff.",
    },
    ["SELF_AURA"] = {
        fires = "When one of your own buffs, matched by spell ID, appears or disappears.",
        needs = "The spell ID of the buff you want watched.",
        limits = "Yours only. It will not see anything on your target or on other players.",
        example = "A sound the moment Power Infusion lands on you.",
    },
    ["SPELL_PROC"] = {
        fires = "When a spell's proc glow lights up on your action bar.",
        needs = "The spell whose glow you are watching.",
        limits = "Follows the bar, not the buff: a proc for a spell you have not placed on a bar has no glow to detect.",
        example = "Call out Sudden Doom lighting up Death Coil.",
    },
    ["CD_READY"] = {
        fires = "When a tracked spell finishes its cooldown.",
        needs = "The spell to track. Tracking is armed the first time you cast it.",
        limits = "Nothing happens until you have cast the spell at least once in this session, since that is what starts the timer.",
        example = "A cue when your interrupt is back up.",
    },
    ["INTERRUPT_USED"] = {
        fires = "When you use an interrupt ability, whether or not it lands.",
        limits = "Says you pressed it, not that it worked. Interrupt Success is the one that means a cast was actually stopped.",
        example = "A short sound so you can hear your own kicks in a noisy fight.",
    },
    ["PVP_KILL"] = {
        fires = "When you land a killing blow on an enemy player.",
        limits = "Instanced content hides unit identity from addons, so this cannot always tell a player apart from a raid mob. It defaults to battlegrounds only for that reason -- widen the zones at your own risk.",
        example = "A kill sound in battlegrounds.",
    },
    ["HEARTBEAT"] = {
        fires = "Continuously while your health is under the threshold you set, speeding up as it drops.",
        limits = "Health only. It knows nothing about incoming damage, so a burst that kills you outright gives no warning.",
        example = "A pulse that gets faster below 35% health.",
    },
    ["SUMMON"] = {
        fires = "When a summon appears for you, and again when you accept or decline it.",
        example = "Different sounds for the summon arriving and for accepting it.",
    },
    ["EAT_BUFF"] = {
        fires = "When you gain Well Fed or a drink buff.",
        limits = "The buff, not the act. Starting to eat and being interrupted produces nothing.",
        example = "A quiet cue that your food actually took.",
    },
    ["MOUNT"] = {
        fires = "When you mount, dismount, or shift into a travel form.",
        example = "A sound for mounting up, and a different one for landing.",
    },
    ["COMBAT_STATE"] = {
        fires = "When you enter or leave combat.",
        limits = "Leaving combat is delayed by the game's own out-of-combat timer, so the cue lands a few seconds after the fight really ended.",
        example = "Music or a sound to mark a pull.",
    },
    ["BLOODLUST"] = {
        fires = "When Bloodlust, Heroism, Time Warp or an equivalent lands on you.",
        example = "A sound the moment lust goes out.",
    },
    ["ACHIEVEMENT"] = {
        fires = "When you earn an achievement.",
        example = "A celebration animation on every achievement.",
    },
    ["PREY_HUNT"] = {
        fires = "On Prey Hunt stage changes, gossip markers, and hunt progress.",
        limits = "Beta. It reads the game's own quest widget, so it can only report what that widget shows.",
    },
    ["RESURRECT_REQUEST"] = {
        fires = "When somebody offers you a resurrection.",
        example = "A sound so you notice the box during a wipe.",
    },
}

function OxedHub:GetEventHelp(eventType)
    return self.EVENT_HELP and self.EVENT_HELP[eventType] or nil
end
