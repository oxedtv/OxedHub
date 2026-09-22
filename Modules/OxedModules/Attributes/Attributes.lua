-- ============================================================================
-- Attributes (built-in OxedHub module)
-- Adds the numbers the character sheet leaves out: how fast you are actually
-- moving, and the stats the default panel never prints -- leech, avoidance,
-- stagger, and what your armour really takes off a hit.
--
-- It lives as its own tab beside Character, Reputation and Currency. Squeezing
-- the lines in under Blizzard's own ran out of room the moment a character had
-- a few stats to show; a tab has the whole window, so the numbers can be
-- grouped and read instead of counted into whatever space was left.
--
-- Nothing of Blizzard's is moved or replaced. The tab shows its own frame and
-- steps aside the moment another tab is picked.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled   = false,  -- off until the player switches it on (see ModuleAPI:Register)
    primary   = true,   -- the stat your spec scales with, and stamina
    speed     = true,   -- movement speed, live
    hidden    = true,   -- leech, avoidance, speed rating
    defense   = true,   -- dodge, parry, block, armour reduction
    offense   = true,   -- crit, haste, mastery, versatility with ratings
    ratings   = true,   -- the rating next to each percentage
    vehicle   = true,   -- read the vehicle's speed while in one
    gear      = true,   -- item level and the weakest slot
    diminishing = true, -- how much of each secondary rating is lost to diminishing returns
    deltas    = true,   -- show the change since the saved snapshot
    targets   = true,   -- bars showing each secondary against a target you set

    -- The on-screen display. Which stats it shows ("hudStats") is a table and
    -- is built in BindSettings, for the same reason as statTargets below.
    hud       = false,  -- shown on screen
    hudLocked = false,  -- no dragging
    hudCombat = false,  -- only while in combat
    hudScale  = 1,
    hudAlpha  = 0.75,   -- background opacity
    hudPoint  = "CENTER",
    hudX      = 320,
    hudY      = 0,
    -- "statTargets" is a table and is built in BindSettings: defaults are
    -- copied by reference, so one table here would be shared by every
    -- character on the account.
}

local settings          -- OxedHubDB.modules.attributes, bound at login
local panel             -- our page inside the character window
local tab               -- the button that opens it
local lines = {}        -- reusable line frames, header or value
local hooked = false
local optionsWindow
local SetSpeedTicker    -- defined with the event watcher below; see there

local UPDATE_INTERVAL = 0.1   -- the speed line only; the rest moves on events

local HEADER_COLOR = { 1, 0.82, 0 }

-- The frames the other tabs show. Ours hides whenever one of these appears.
local SUBFRAMES = { "PaperDollFrame", "ReputationFrame", "TokenFrame" }

-- ── Reading the stats ───────────────────────────────────────────────────────
-- Every reader returns: value text, label, tooltip body, number.
-- A reader returning nil means "this character has nothing to show here", and
-- the line is skipped rather than printed as a zero.
--
-- The tooltip body may be a function, called only when the line is hovered:
-- some of what it says (the next diminishing-returns threshold) takes a search
-- that is not worth running on every stat change.
--
-- The number is what the snapshot compares against: the stat itself, in the
-- same unit the line shows.

local function Percent(value)
    return ("%.2f%%"):format(value or 0)
end

-- ── Diminishing returns, as the game itself reports them ───────────────────
-- Past certain percentages each extra point of a secondary rating is worth
-- less. The thresholds change between patches, so none are written down here:
-- the game is asked what a given amount of rating is worth
-- (GetCombatRatingBonusForCombatRatingValue, which applies the current rules),
-- and the shape of the curve is read off the answers. A client without that
-- call simply shows no diminishing-returns detail.
local RatingBonusFor = GetCombatRatingBonusForCombatRatingValue
local PROBE = 100          -- rating small enough to sit below every threshold

local function BonusAt(ratingId, rating)
    local ok, bonus = pcall(RatingBonusFor, ratingId, rating)
    if ok and type(bonus) == "number" then return bonus end
    return nil
end

-- What the next point of rating is worth, as a share of full value (1 while
-- nothing is being lost), plus the bonus the rating gives now and the bonus
-- per point before any reduction.
local function RatingEfficiency(ratingId, rating)
    if not (RatingBonusFor and ratingId and rating and rating > 0) then return nil end
    local base = BonusAt(ratingId, PROBE)
    local here = BonusAt(ratingId, rating)
    local ahead = BonusAt(ratingId, rating + PROBE)
    if not (base and here and ahead) or base <= 0 then return nil end
    return (ahead - here) / base, here, base / PROBE
end

-- How much more rating until each point is worth noticeably less again, found
-- by walking forward until the value of a step drops. Only run on hover.
local function NextThreshold(ratingId, rating, efficiency, perPoint)
    local STEP = 50
    local previous = BonusAt(ratingId, rating)
    if not previous then return nil end
    for extra = STEP, 20000, STEP do
        local bonus = BonusAt(ratingId, rating + extra)
        if not bonus then return nil end
        local stepEfficiency = (bonus - previous) / (STEP * perPoint)
        if stepEfficiency < efficiency - 0.05 then return extra end
        previous = bonus
    end
    return nil
end

local function DiminishingText(ratingId)
    if not (settings.diminishing and RatingBonusFor and GetCombatRating) then return nil end
    local rating = GetCombatRating(ratingId)
    local efficiency, here, perPoint = RatingEfficiency(ratingId, rating)
    if not efficiency then return nil end

    local lines = { ("Each extra point of rating is worth %d%% of full value."):format(efficiency * 100 + 0.5) }
    local lost = perPoint * rating - here
    if lost >= 0.01 then
        lines[#lines + 1] = ("Lost to diminishing returns: %.2f%%"):format(lost)
    end
    local nextAt = NextThreshold(ratingId, rating, efficiency, perPoint)
    if nextAt then
        lines[#lines + 1] = ("Worth less again after about %d more rating."):format(nextAt)
    end
    return table.concat(lines, "\n")
end

-- Adds the diminishing-returns detail to a line's tooltip, worked out only when
-- the line is hovered.
local function WithDiminishing(body, ratingId)
    if not (settings.diminishing and RatingBonusFor and ratingId) then return body end
    return function()
        local detail = DiminishingText(ratingId)
        if body and detail then return body .. "\n\n" .. detail end
        return detail or body
    end
end

-- The rating in brackets, when the player asked for ratings and there is one.
-- Orange once diminishing returns have started to bite, so a stat that is past
-- its threshold stands out without reading every tooltip.
local function WithRating(text, ratingId)
    if not settings.ratings or not ratingId or not GetCombatRating then return text end
    local rating = GetCombatRating(ratingId)
    if not rating or rating <= 0 then return text end
    local colour = "|cff808080"
    if settings.diminishing then
        local efficiency = RatingEfficiency(ratingId, rating)
        if efficiency and efficiency < 0.99 then colour = "|cffff9933" end
    end
    return ("%s %s(%d)|r"):format(text, colour, rating)
end

-- Which unit's speed matters right now. In a vehicle the player's own speed is
-- whatever the vehicle grants, so the vehicle is the honest answer.
local function SpeedUnit()
    if settings.vehicle and UnitInVehicle and UnitInVehicle("player")
        and UnitControllingVehicle and UnitControllingVehicle("player") then
        return "vehicle", true
    end
    return "player", false
end

-- Skyriding speed. GetUnitSpeed does not describe it -- the flight is physics,
-- not a movement rate -- so while gliding the forward speed comes from the
-- gliding info instead.
local function GlidingSpeed()
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return nil end
    local ok, isGliding, _, forward = pcall(C_PlayerInfo.GetGlidingInfo)
    if ok and isGliding and type(forward) == "number" then return forward end
    return nil
end

local function ReadSpeed()
    if not GetUnitSpeed then return nil end
    local unit, inVehicle = SpeedUnit()
    local current = GetUnitSpeed(unit) or 0
    local gliding = GlidingSpeed()
    if gliding then current = gliding end
    local base = BASE_MOVEMENT_SPEED or 7
    local percent = current / base * 100

    local text = ("%.0f%%"):format(percent)
    if gliding then
        text = text .. " |cff808080(skyriding)|r"
    elseif inVehicle then
        text = text .. " |cff808080(vehicle)|r"
    end

    return text, STAT_MOVEMENT_SPEED or "Movement Speed",
        ("Current: %.1f yards per second.\nStanding still reads 0%%."):format(current), percent
end

-- Run, swim and flight speed, each as a share of normal running speed: what
-- you would move at right now in each, whatever you happen to be doing.
local function ReadTravelSpeeds()
    if not GetUnitSpeed then return nil end
    local _, run, flight, swim = GetUnitSpeed("player")
    if not run then return nil end
    local base = BASE_MOVEMENT_SPEED or 7
    local function pct(value) return ("%.0f%%"):format((value or 0) / base * 100) end
    return ("%s / %s / %s"):format(pct(run), pct(swim), pct(flight)),
        "Run / Swim / Fly",
        "What you move at on foot, in water and on a flying mount, as a share of normal run speed. Skyriding shows live on the line above while you glide.",
        (run or 0) / base * 100
end

local function ReadSpeedRating()
    if not GetSpeed then return nil end
    local bonus = GetSpeed()
    if not bonus or bonus <= 0 then return nil end
    return WithRating(Percent(bonus), CR_SPEED), STAT_SPEED or "Speed",
        WithDiminishing("Passive movement speed from the Speed secondary stat, on top of your normal run speed.", CR_SPEED),
        bonus
end

local function ReadLeech()
    if not GetLifesteal then return nil end
    local value = GetLifesteal()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_LIFESTEAL), STAT_LIFESTEAL or "Leech",
        WithDiminishing("Part of the damage and healing you do comes back to you as healing.", CR_LIFESTEAL),
        value
end

local function ReadAvoidance()
    if not GetAvoidance then return nil end
    local value = GetAvoidance()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_AVOIDANCE), STAT_AVOIDANCE or "Avoidance",
        WithDiminishing("Reduces the damage area effects do to you.", CR_AVOIDANCE),
        value
end

-- ── The primary attributes ──────────────────────────────────────────────────

local STAT_STRENGTH, STAT_AGILITY, STAT_STAMINA, STAT_INTELLECT = 1, 2, 3, 4

-- Which of the four the specialisation actually scales with. Asked of the
-- specialisation rather than guessed from the class: a druid's answer changes
-- with the spec, not with the class.
-- ── Stat targets ────────────────────────────────────────────────────────────
-- A target you set yourself, per specialisation, with a bar showing how far
-- along you are and -- the part that actually helps -- how much more rating it
-- would take to get there.
--
-- The missing rating is not estimated from "rating per percent", because that
-- figure stops being true the moment diminishing returns start. The game is
-- asked instead: what is this much rating worth? The answer is searched for the
-- amount that reaches the target, so the number holds at any gear level and
-- survives whatever Blizzard changes next patch.

local SECONDARIES = {
    { key = "crit",    ratingId = CR_CRIT_MELEE,
      label = STAT_CRITICAL_STRIKE or "Critical Strike",
      read = function() return GetCritChance and GetCritChance() end },
    { key = "haste",   ratingId = CR_HASTE_MELEE,
      label = STAT_HASTE or "Haste",
      read = function() return GetHaste and GetHaste() end },
    { key = "mastery", ratingId = CR_MASTERY,
      label = STAT_MASTERY or "Mastery",
      read = function() return GetMasteryEffect and GetMasteryEffect() end },
    -- Versatility through the rating bonus, not GetVersatilityBonus: that one
    -- already includes what the rating gives, and adding the two together
    -- counts the same points twice.
    { key = "versatility", ratingId = CR_VERSATILITY_DAMAGE_DONE,
      label = STAT_VERSATILITY or "Versatility",
      read = function()
          return GetCombatRatingBonus and CR_VERSATILITY_DAMAGE_DONE
              and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
      end },
}

local function CurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local index = GetSpecialization()
    if not index then return nil end
    local id = GetSpecializationInfo(index)
    return id
end

local function TargetKey(statKey)
    return ("%s:%s"):format(tostring(CurrentSpecID() or "none"), statKey)
end

local function GetTarget(statKey)
    local store = settings and settings.statTargets
    if type(store) ~= "table" then return nil end
    local value = tonumber(store[TargetKey(statKey)])
    if value and value > 0 then return value end
    return nil
end

local function SetTarget(statKey, value)
    settings.statTargets = settings.statTargets or {}
    value = tonumber(value)
    settings.statTargets[TargetKey(statKey)] = (value and value > 0) and value or nil
end

-- The rating that would buy this percentage, found by asking the game what a
-- given rating is worth and closing in on the answer. Returns nil when the
-- client cannot answer or the target is out of reach.
local function RatingForBonus(ratingId, wanted)
    if not (RatingBonusFor and ratingId and wanted) then return nil end

    local low, high = 0, 1000
    local ceiling = 2000000
    while (BonusAt(ratingId, high) or 0) < wanted do
        high = high * 2
        if high > ceiling then return nil end
    end

    -- Twenty halvings take the range below a single point of rating.
    for _ = 1, 20 do
        local middle = math.floor((low + high) / 2)
        if (BonusAt(ratingId, middle) or 0) < wanted then
            low = middle
        else
            high = middle
        end
    end
    return high
end

-- Everything the bar needs for one secondary.
local function ReadTarget(entry)
    local current = entry.read and entry.read()
    if type(current) ~= "number" then return nil end

    local target = GetTarget(entry.key)
    local rating = GetCombatRating and GetCombatRating(entry.ratingId) or 0

    local info = {
        key = entry.key,
        label = entry.label,
        current = current,
        target = target,
        rating = rating,
    }

    -- No target set: the bars compare the four secondaries with each other
    -- instead, scaled to the biggest of them. That makes the section worth
    -- looking at before anything is configured -- the lopsided stat is obvious
    -- at a glance -- where a row of empty bars saying "no target" was not.
    if not target then
        local highest = 0
        for _, other in ipairs(SECONDARIES) do
            local value = other.read and other.read()
            if type(value) == "number" and value > highest then highest = value end
        end
        info.progress = highest > 0 and (current / highest) or 0
        info.relative = true
        info.text = ("%s  |cff808080%d|r"):format(Percent(current), rating or 0)
        info.tip = "Set a target for this stat in the module's Options and this bar fills toward it, with the rating you still need.\n\nUntil then the bars are drawn against your highest secondary, so you can see which is behind."
        return info
    end

    info.progress = target > 0 and (current / target) or 0
    local gap = target - current

    if gap <= 0.01 then
        info.text = ("%s  |cff40ff40of %s|r"):format(Percent(current), Percent(target))
        info.state = "at"
        info.tip = ("You are %.2f%% over the target you set (%s)."):format(-gap, Percent(target))
    else
        local needed = RatingForBonus(entry.ratingId, target)
        if needed and rating and needed > rating then
            info.text = ("%s  |cffff9933+%d rating|r"):format(Percent(current), needed - rating)
            info.tip = ("%.2f%% short of your %s target.\nThat is about %d more rating, worked out from what the game says each amount is worth, so diminishing returns are already counted.")
                :format(gap, Percent(target), needed - rating)
        else
            info.text = ("%s  |cffff9933of %s|r"):format(Percent(current), Percent(target))
            info.tip = ("%.2f%% short of your %s target."):format(gap, Percent(target))
        end
        info.state = "below"
    end

    return info
end

local function PrimaryStatIndex()
    local spec = GetSpecialization and GetSpecialization()
    if spec and spec > 0 and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        local _, _, primary = select(4, C_SpecializationInfo.GetSpecializationInfo(spec))
        if primary then return primary end
    end

    -- No specialisation yet (a low level character): the biggest of the three
    -- is the one being stacked.
    local best, bestValue
    for _, index in ipairs({ STAT_STRENGTH, STAT_AGILITY, STAT_INTELLECT }) do
        local value = select(2, UnitStat("player", index))
        if value and (not bestValue or value > bestValue) then best, bestValue = index, value end
    end
    return best
end

local function StatName(index)
    return _G["SPELL_STAT" .. index .. "_NAME"] or "Attribute"
end

local function ReadPrimaryStat()
    if not UnitStat then return nil end
    local index = PrimaryStatIndex()
    if not index then return nil end

    local effective, _, positive, negative = select(2, UnitStat("player", index))
    if not effective then return nil end

    local body
    if (positive and positive > 0) or (negative and negative < 0) then
        body = ("Base: %d\nFrom gear and effects: %+d"):format(
            effective - (positive or 0) - (negative or 0), (positive or 0) + (negative or 0))
    end
    return tostring(effective), StatName(index), body, effective
end

local function ReadStamina()
    if not UnitStat then return nil end
    local effective = select(2, UnitStat("player", STAT_STAMINA))
    if not effective then return nil end
    return tostring(effective), StatName(STAT_STAMINA),
        ("Health: %d"):format(UnitHealthMax and UnitHealthMax("player") or 0), effective
end

-- The lowest crit of the spell schools. A school left behind is the one that
-- decides whether a spell crits, so the smallest is the honest figure.
local function MinSpellCrit()
    if not GetSpellCritChance then return 0 end
    local lowest = GetSpellCritChance(2) or 0
    for school = 3, (MAX_SPELL_SCHOOLS or 7) do
        local value = GetSpellCritChance(school)
        if value then lowest = math.min(lowest, value) end
    end
    return lowest
end

-- Crit comes in three kinds and a character only cares about the one their
-- attacks use. The largest is the one their gear is rated for, which is how
-- the character sheet picks it too.
local function ReadCrit()
    if not GetCritChance then return nil end
    local melee = GetCritChance() or 0
    local ranged = (GetRangedCritChance and GetRangedCritChance()) or 0
    local spell = MinSpellCrit()

    local value, ratingId
    if spell >= ranged and spell >= melee then
        value, ratingId = spell, CR_CRIT_SPELL
    elseif ranged >= melee then
        value, ratingId = ranged, CR_CRIT_RANGED
    else
        value, ratingId = melee, CR_CRIT_MELEE
    end

    return WithRating(Percent(value), ratingId),
        STAT_CRITICAL_STRIKE or "Critical Strike",
        WithDiminishing(("Melee: %s\nRanged: %s\nSpell: %s"):format(Percent(melee), Percent(ranged), Percent(spell)), ratingId),
        value
end

local function ReadHaste()
    if not GetHaste then return nil end
    local haste = GetHaste()
    return WithRating(Percent(haste), CR_HASTE_MELEE), STAT_HASTE or "Haste",
        WithDiminishing(nil, CR_HASTE_MELEE), haste
end

local function ReadMastery()
    if not GetMasteryEffect then return nil end
    local value = GetMasteryEffect()
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_MASTERY), STAT_MASTERY or "Mastery",
        WithDiminishing("Diminishing returns below are in mastery points, before your spec turns them into this percentage.", CR_MASTERY), value
end

-- Versatility is two numbers wearing one name: what it adds to the damage you
-- deal, and what it takes off the damage you take. The sheet prints the first.
local function ReadVersatility()
    if not (GetCombatRatingBonus and GetVersatilityBonus and CR_VERSATILITY_DAMAGE_DONE) then
        return nil
    end
    local done = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)
        + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)
    local taken = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN)
        + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)

    return WithRating(Percent(done), CR_VERSATILITY_DAMAGE_DONE),
        STAT_VERSATILITY or "Versatility",
        WithDiminishing(("Damage done: %s\nDamage taken: %s"):format(Percent(done), Percent(taken)), CR_VERSATILITY_DAMAGE_DONE),
        done
end

local function ReadDodge()
    if not GetDodgeChance then return nil end
    local dodge = GetDodgeChance()
    return WithRating(Percent(dodge), CR_DODGE), DODGE_CHANCE or "Dodge",
        WithDiminishing(nil, CR_DODGE), dodge
end

local function ReadParry()
    if not GetParryChance then return nil end
    local value = GetParryChance()
    -- Classes that cannot parry read a flat zero; printing it says nothing.
    if not value or value <= 0 then return nil end
    return WithRating(Percent(value), CR_PARRY), PARRY_CHANCE or "Parry",
        WithDiminishing(nil, CR_PARRY), value
end

local function ReadBlock()
    if not GetBlockChance then return nil end
    local value = GetBlockChance()
    if not value or value <= 0 then return nil end

    local body
    if GetShieldBlock then
        local amount = GetShieldBlock()
        if amount and amount > 0 then
            body = ("A blocked hit is reduced by %d."):format(amount)
        end
    end
    return WithRating(Percent(value), CR_BLOCK), BLOCK_CHANCE or "Block",
        WithDiminishing(body, CR_BLOCK), value
end

-- Monks only: the share of a hit that is delayed instead of taken at once.
local function ReadStagger()
    if not (C_PaperDollInfo and C_PaperDollInfo.GetStaggerPercentage) then return nil end
    local stagger, againstTarget = C_PaperDollInfo.GetStaggerPercentage("player")
    if not stagger or stagger <= 0 then return nil end

    local body
    if againstTarget and againstTarget ~= stagger then
        body = ("Against your current target: %s"):format(Percent(againstTarget))
    end
    return Percent(stagger), STAT_STAGGER or "Stagger", body, stagger
end

local function ReadArmor()
    if not UnitArmor then return nil end
    local effective = select(2, UnitArmor("player"))
    if not effective or effective <= 0 then return nil end
    return tostring(effective), ARMOR or "Armor", nil, effective
end

-- What the armour is actually worth, which the sheet only shows on hover.
local function ReadArmorReduction()
    if not (UnitArmor and PaperDollFrame_GetArmorReduction) then return nil end
    local effective = select(2, UnitArmor("player"))
    if not effective or effective <= 0 then return nil end

    local level = (UnitEffectiveLevel and UnitEffectiveLevel("player")) or UnitLevel("player")
    local reduction = PaperDollFrame_GetArmorReduction(effective, level)
    if not reduction then return nil end

    local body
    if PaperDollFrame_GetArmorReductionAgainstTarget then
        local vsTarget = PaperDollFrame_GetArmorReductionAgainstTarget(effective)
        if vsTarget then
            body = ("Against your current target: %s"):format(Percent(vsTarget))
        end
    end
    return Percent(reduction), "Damage reduction", body, reduction
end

-- ── Worked out from the stats ───────────────────────────────────────────────

-- The global cooldown with haste applied: how fast the rotation really turns.
-- A few kits run on a fixed one-second cooldown that haste does not shorten.
local function FixedGlobalCooldown()
    local _, class = UnitClass("player")
    if class == "ROGUE" then return true end
    if class == "MONK" then
        local spec = GetSpecialization and GetSpecialization()
        local specID = spec and GetSpecializationInfo and GetSpecializationInfo(spec)
        return specID ~= 270   -- Mistweaver's is hasted
    end
    if class == "DRUID" and GetShapeshiftFormID and GetShapeshiftFormID() == 1 then
        return true            -- Cat Form
    end
    return false
end

local function ReadGlobalCooldown()
    if not GetHaste then return nil end
    local haste = GetHaste() or 0
    if FixedGlobalCooldown() then
        return "1.00 s", "Global cooldown",
            "Fixed at one second for your class or form: haste does not shorten it.", 1
    end
    local gcd = math.max(0.75, 1.5 / (1 + haste / 100))
    return ("%.2f s"):format(gcd), "Global cooldown",
        ("1.5 s reduced by %s haste, never below 0.75 s."):format(Percent(haste)), gcd
end

local function Abbreviate(value)
    if value >= 1e6 then return ("%.2fM"):format(value / 1e6) end
    if value >= 1e3 then return ("%.0fk"):format(value / 1e3) end
    return tostring(math.floor(value + 0.5))
end

-- Effective health: how much damage it takes to kill you from full, once armour
-- and versatility have taken their share. One number to compare defensive gear
-- by. Physical damage meets both; magic meets versatility only.
local function ReadEffectiveHealth()
    if not (UnitHealthMax and UnitArmor and PaperDollFrame_GetArmorReduction) then return nil end
    local ok, result = pcall(function()
        local health = UnitHealthMax("player")
        local effective = select(2, UnitArmor("player"))
        local level = (UnitEffectiveLevel and UnitEffectiveLevel("player")) or UnitLevel("player")
        local armour = (PaperDollFrame_GetArmorReduction(effective, level) or 0) / 100
        local vers = 0
        if GetCombatRatingBonus and GetVersatilityBonus and CR_VERSATILITY_DAMAGE_TAKEN then
            vers = (GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_TAKEN)
                + GetVersatilityBonus(CR_VERSATILITY_DAMAGE_TAKEN)) / 100
        end
        local physical = health / math.max(0.01, (1 - armour) * (1 - vers))
        local magic = health / math.max(0.01, 1 - vers)
        return { health = health, physical = physical, magic = magic, armour = armour, vers = vers }
    end)
    -- Health can be a secret value in some content, and arithmetic on one errors:
    -- the line is simply left out then.
    if not ok or type(result) ~= "table" then return nil end

    return ("%s / %s"):format(Abbreviate(result.physical), Abbreviate(result.magic)),
        "Effective health",
        ("Physical / magic. Your %s health, after armour (%s) and versatility (%s) take their share of each hit.")
            :format(Abbreviate(result.health), Percent(result.armour * 100), Percent(result.vers * 100)),
        result.physical
end

-- ── Gear ────────────────────────────────────────────────────────────────────

local GEAR_SLOTS = {
    { "HeadSlot", "Head" }, { "NeckSlot", "Neck" }, { "ShoulderSlot", "Shoulders" },
    { "BackSlot", "Back" }, { "ChestSlot", "Chest" }, { "WristSlot", "Wrists" },
    { "HandsSlot", "Hands" }, { "WaistSlot", "Waist" }, { "LegsSlot", "Legs" },
    { "FeetSlot", "Feet" }, { "Finger0Slot", "Ring 1" }, { "Finger1Slot", "Ring 2" },
    { "Trinket0Slot", "Trinket 1" }, { "Trinket1Slot", "Trinket 2" },
    { "MainHandSlot", "Main hand" }, { "SecondaryHandSlot", "Off hand" },
}

local function SlotItemLevel(slotName)
    local slotID = GetInventorySlotInfo(slotName)
    if not (slotID and GetInventoryItemLink("player", slotID)) then return nil end
    if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromEquipmentSlot then
        local ok, level = pcall(C_Item.GetCurrentItemLevel, ItemLocation:CreateFromEquipmentSlot(slotID))
        if ok and type(level) == "number" and level > 0 then return level end
    end
    return nil
end

local function ReadItemLevel()
    if not GetAverageItemLevel then return nil end
    local overall, equipped = GetAverageItemLevel()
    if not equipped or equipped <= 0 then return nil end
    return ("%.1f"):format(equipped), "Item level",
        ("Equipped %.1f. The best you own, bags included: %.1f."):format(equipped, overall or equipped),
        equipped
end

-- The piece of gear furthest behind: the upgrade that moves item level most.
local function ReadWeakestSlot()
    local lowestName, lowestLevel
    local list = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local level = SlotItemLevel(slot[1])
        if level then
            list[#list + 1] = { name = slot[2], level = level }
            if not lowestLevel or level < lowestLevel then
                lowestName, lowestLevel = slot[2], level
            end
        end
    end
    if not lowestName then return nil end

    table.sort(list, function(a, b) return a.level < b.level end)
    local body = {}
    for i = 1, math.min(5, #list) do
        body[#body + 1] = ("%s  %d"):format(list[i].name, list[i].level)
    end
    return ("%s  %d"):format(lowestName, lowestLevel), "Weakest slot",
        "Lowest item level first, the upgrades worth chasing:\n" .. table.concat(body, "\n"),
        lowestLevel
end

-- What is printed, in order. A header only appears when a line under it does.
local ROWS = {
    { group = "primary", header = STAT_CATEGORY_ATTRIBUTES or "Attributes" },
    { group = "primary", id = "primary", name = "Main stat", read = ReadPrimaryStat },
    { group = "primary", id = "stamina", name = "Stamina", read = ReadStamina },

    { group = "gear",    header = "Gear" },
    { group = "gear",    id = "ilvl", name = "Item level", read = ReadItemLevel },
    { group = "gear",    id = "weakest", name = "Weakest slot", read = ReadWeakestSlot },

    { group = "speed",   header = "Movement" },
    { group = "speed",   id = "speed", name = "Movement speed", read = ReadSpeed, live = true },
    { group = "speed",   id = "travel", name = "Travel speeds", read = ReadTravelSpeeds },
    { group = "speed",   id = "speedrating", name = "Speed rating", read = ReadSpeedRating },

    { group = "offense", header = "Offense" },
    { group = "offense", id = "crit", name = "Critical strike", read = ReadCrit },
    { group = "offense", id = "haste", name = "Haste", read = ReadHaste },
    { group = "offense", id = "gcd", name = "Global cooldown", read = ReadGlobalCooldown },
    { group = "offense", id = "mastery", name = "Mastery", read = ReadMastery },
    { group = "offense", id = "versatility", name = "Versatility", read = ReadVersatility },

    -- One bar per secondary, against the target set for this specialisation.
    { group = "targets", header = "Stat targets" },
    { group = "targets", id = "bar_crit", name = "Crit", bar = SECONDARIES[1] },
    { group = "targets", id = "bar_haste", name = "Haste", bar = SECONDARIES[2] },
    { group = "targets", id = "bar_mastery", name = "Mastery", bar = SECONDARIES[3] },
    { group = "targets", id = "bar_versatility", name = "Versatility", bar = SECONDARIES[4] },

    { group = "hidden",  header = "Hidden stats" },
    { group = "hidden",  id = "leech", name = "Leech", read = ReadLeech },
    { group = "hidden",  id = "avoidance", name = "Avoidance", read = ReadAvoidance },

    { group = "defense", header = "Defense" },
    { group = "defense", id = "ehp", name = "Effective health", read = ReadEffectiveHealth },
    { group = "defense", id = "armor", name = "Armour", read = ReadArmor },
    { group = "defense", id = "armorcut", name = "Armour reduction", read = ReadArmorReduction },
    { group = "defense", id = "dodge", name = "Dodge", read = ReadDodge },
    { group = "defense", id = "parry", name = "Parry", read = ReadParry },
    { group = "defense", id = "block", name = "Block", read = ReadBlock },
    { group = "defense", id = "stagger", name = "Stagger", read = ReadStagger },
}

-- ── The lines ───────────────────────────────────────────────────────────────

local function GetLine(index, parent, pool)
    pool = pool or lines
    local line = pool[index]
    if line then return line end

    line = CreateFrame("Frame", nil, parent)
    line:SetHeight(18)

    line.label = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    line.label:SetPoint("LEFT", line, "LEFT", 10, 0)
    line.label:SetJustifyH("LEFT")

    line.value = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    line.value:SetPoint("RIGHT", line, "RIGHT", -14, 0)
    line.value:SetJustifyH("RIGHT")

    -- The target bar. Built once on every line and simply left hidden on the
    -- ones that do not use it: lines are pooled and reused in any order, so a
    -- bar that only some of them own would have to be moved between them.
    local bar = CreateFrame("Frame", nil, line)
    bar:SetHeight(8)
    -- Pulled in from both sides so it never sits against the page border.
    bar:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", 12, 2)
    bar:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", -20, 2)
    bar:Hide()

    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0.12, 0.12, 0.13, 0.9)

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.fill:SetWidth(1)

    -- A lit top edge over the fill. Costs one texture and makes a flat colour
    -- read as a bar rather than as a painted rectangle.
    bar.gloss = bar:CreateTexture(nil, "OVERLAY")
    bar.gloss:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.gloss:SetVertexColor(1, 1, 1, 0.25)
    bar.gloss:SetBlendMode("ADD")
    bar.gloss:SetPoint("TOPLEFT", bar.fill, "TOPLEFT", 0, 0)
    bar.gloss:SetPoint("TOPRIGHT", bar.fill, "TOPRIGHT", 0, 0)
    bar.gloss:SetHeight(3)

    -- Where the target sits. Drawn over the fill so it stays visible once the
    -- bar runs past it.
    bar.tick = bar:CreateTexture(nil, "OVERLAY")
    bar.tick:SetColorTexture(0.95, 0.86, 0.55, 0.95)
    bar.tick:SetWidth(2)
    bar.tick:SetPoint("TOP", bar, "TOP", 0, 1)
    bar.tick:SetPoint("BOTTOM", bar, "BOTTOM", 0, -1)
    bar.tick:Hide()

    line.bar = bar

    line:EnableMouse(true)
    line:SetScript("OnEnter", function(self)
        if not self.tipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tipTitle)
        -- A body can be a function, worked out now rather than on every redraw.
        local body = self.tipBody
        if type(body) == "function" then
            local ok, text = pcall(body)
            body = ok and text or nil
        end
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pool[index] = line
    return line
end

-- Lines are pooled, so one that carried a bar can be handed back as a plain
-- row. Both setters put the text back where a plain row wants it -- centred --
-- and the bar version lifts it to the top to make room underneath.
local function PlainText(line)
    line.label:ClearAllPoints()
    line.label:SetPoint("LEFT", line, "LEFT", 10, 0)
    line.value:ClearAllPoints()
    line.value:SetPoint("RIGHT", line, "RIGHT", -14, 0)
    line:SetHeight(18)
    line.bar:Hide()
end

local function SetHeaderLine(line, text)
    PlainText(line)
    line.label:SetFontObject("GameFontNormal")
    line.label:SetTextColor(unpack(HEADER_COLOR))
    line.label:SetText(text)
    line.value:SetText("")
    line.tipTitle, line.tipBody = nil, nil
end

local function SetValueLine(line, label, value, body)
    PlainText(line)
    line.label:SetFontObject("GameFontHighlight")
    line.label:SetTextColor(0.8, 0.8, 0.8)
    line.label:SetText(label)
    line.value:SetText(value)
    line.tipTitle, line.tipBody = label, body
end

-- Each secondary keeps its own colour across the section, so a glance at the
-- bars is enough to tell which is which without reading the labels.
local STAT_COLOURS = {
    crit        = { 1.00, 0.62, 0.20 },
    haste       = { 0.45, 0.90, 0.55 },
    mastery     = { 0.70, 0.45, 1.00 },
    versatility = { 0.40, 0.72, 1.00 },
}

local function SetBarLine(line, info)
    -- Text at the top, bar underneath, and the line tall enough for both. Left
    -- at the plain height the bar landed on the next row's text.
    line:SetHeight(26)
    line.label:ClearAllPoints()
    line.label:SetPoint("TOPLEFT", line, "TOPLEFT", 10, -1)
    line.value:ClearAllPoints()
    line.value:SetPoint("TOPRIGHT", line, "TOPRIGHT", -14, -1)

    local colour = STAT_COLOURS[info.key] or { 0.8, 0.8, 0.8 }
    line.label:SetFontObject("GameFontHighlight")
    line.label:SetTextColor(colour[1], colour[2], colour[3])
    line.label:SetText(info.label)
    line.value:SetText(info.text)
    line.tipTitle, line.tipBody = info.label, info.tip

    local bar = line.bar
    bar:Show()

    -- The stat's own colour while it is short, green once the target is met:
    -- the colour says which stat, the change says you are there.
    if info.state == "at" then
        bar.fill:SetVertexColor(0.40, 1.00, 0.45, 0.95)
    elseif info.target then
        bar.fill:SetVertexColor(colour[1], colour[2], colour[3], 0.95)
    else
        bar.fill:SetVertexColor(colour[1] * 0.6, colour[2] * 0.6, colour[3] * 0.6, 0.7)
    end

    -- Sized on the next frame as well as now: the line is anchored to both
    -- sides of the page, so its width is not known until the layout has run.
    local function Resize()
        local width = bar:GetWidth()
        if not width or width <= 0 then return end

        -- With a target, the bar leaves room past the tick so being over reads
        -- as more than a full bar rather than as exactly full. Comparing the
        -- secondaries with each other has no such mark, so it uses the lot.
        local scale = info.relative and 1 or 1.15
        local ratio = math.max(0, math.min(1, (info.progress or 0) / scale))
        bar.fill:SetWidth(math.max(1, width * ratio))

        if info.target then
            local tickX = width / scale
            bar.tick:ClearAllPoints()
            bar.tick:SetPoint("TOP", bar, "TOPLEFT", tickX, 1)
            bar.tick:SetPoint("BOTTOM", bar, "BOTTOMLEFT", tickX, -1)
            bar.tick:Show()
        else
            bar.tick:Hide()
        end
    end
    Resize()
    C_Timer.After(0, Resize)
end

-- ── Snapshot ────────────────────────────────────────────────────────────────
-- Save what the stats are now, then every line shows how far it has moved
-- since: put on a new piece, change a talent, and the gain and the cost are
-- both on the page. One snapshot per character, kept across sessions.

local LOWER_IS_BETTER = { ["Global cooldown"] = true }

local function CharacterKey()
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    return (UnitName("player") or "?") .. "-" .. realm
end

local function CurrentSnapshot()
    local all = settings and settings.snapshots
    return type(all) == "table" and all[CharacterKey()] or nil
end

local function SaveSnapshot()
    if type(settings.snapshots) ~= "table" then settings.snapshots = {} end
    local values = {}
    for _, row in ipairs(ROWS) do
        if row.read then
            local ok, value, label, _, number = pcall(row.read)
            if ok and value and label and type(number) == "number" then
                values[label] = number
            end
        end
    end
    settings.snapshots[CharacterKey()] = { at = time(), values = values }
end

local function ClearSnapshot()
    if type(settings.snapshots) == "table" then
        settings.snapshots[CharacterKey()] = nil
    end
end

-- " +1.82" in green, or red when the stat went the wrong way.
local function DeltaText(label, number)
    if not (settings.deltas and type(number) == "number") then return "" end
    local snapshot = CurrentSnapshot()
    local old = snapshot and snapshot.values and snapshot.values[label]
    if type(old) ~= "number" then return "" end

    local diff = number - old
    local precise = math.abs(old) < 100
    if math.abs(diff) < (precise and 0.005 or 0.5) then return "" end

    local better = diff > 0
    if LOWER_IS_BETTER[label] then better = not better end
    local text = precise and ("%+.2f"):format(diff) or ("%+d"):format(math.floor(diff + 0.5))
    return (" %s%s|r"):format(better and "|cff40ff40" or "|cffff5555", text)
end

-- Redraws every line. Called when the tab opens and whenever the game says a
-- stat changed -- not on the timer, which touches the speed line alone.
local function Refresh()
    if not (panel and panel:IsShown()) then return end

    local content = panel.content
    local shown, y = 0, 0

    if panel.snapshotLabel then
        local snapshot = CurrentSnapshot()
        panel.snapshotLabel:SetText(snapshot and snapshot.at
            and ("Compared with %s"):format(date("%d %b %H:%M", snapshot.at))
            or "No snapshot saved")
    end
    local pendingHeader        -- drawn only once a value under it appears

    for _, row in ipairs(ROWS) do
        if settings[row.group] ~= false then
            if row.header then
                pendingHeader = row.header
            elseif row.bar then
                local info = ReadTarget(row.bar)
                if info then
                    if pendingHeader then
                        shown = shown + 1
                        local header = GetLine(shown, content)
                        SetHeaderLine(header, pendingHeader)
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 6)
                        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y - 6)
                        header:Show()
                        y = y + 24
                        pendingHeader = nil
                    end

                    shown = shown + 1
                    local line = GetLine(shown, content)
                    SetBarLine(line, info)
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    line:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                    line:Show()
                    -- Taller than a plain line: the bar sits under the text,
                    -- plus a couple of pixels so two bars do not touch.
                    y = y + 28
                end
            else
                local value, label, body, number = row.read()
                if value then
                    value = value .. DeltaText(label, number)
                    if pendingHeader then
                        shown = shown + 1
                        local header = GetLine(shown, content)
                        SetHeaderLine(header, pendingHeader)
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y - 6)
                        header:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y - 6)
                        header:Show()
                        y = y + 24
                        pendingHeader = nil
                    end

                    shown = shown + 1
                    local line = GetLine(shown, content)
                    SetValueLine(line, label, value, body)
                    line:ClearAllPoints()
                    line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    line:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                    line:Show()
                    y = y + 18
                end
            end
        end
    end

    for index = shown + 1, #lines do
        lines[index]:Hide()
    end

    content:SetHeight(math.max(1, y))

    -- A page that shrank below where it was scrolled to would otherwise sit
    -- past its own end, showing nothing.
    local limit = math.max(0, y - panel.scroll:GetHeight())
    if panel.scroll:GetVerticalScroll() > limit then
        panel.scroll:SetVerticalScroll(limit)
    end
end

-- Only the speed line changes between events, so the timer redraws that one
-- alone. Reading every stat ten times a second would cost far more than the
-- one number that actually moves.
local function RefreshSpeedOnly()
    if not (settings and settings.speed and panel and panel:IsShown()) then return end
    for _, line in ipairs(lines) do
        if line:IsShown() and line.tipTitle == (STAT_MOVEMENT_SPEED or "Movement Speed") then
            local value, _, body = ReadSpeed()
            if value then
                line.value:SetText(value)
                line.tipBody = body
            end
            return
        end
    end
end

-- ── The page ────────────────────────────────────────────────────────────────

local function HideBlizzardSubframes()
    for _, name in ipairs(SUBFRAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then frame:Hide() end
    end
end

local function BuildPanel()
    if panel then return panel end
    if not CharacterFrame then return nil end

    panel = CreateFrame("Frame", "OxedHubAttributesPanel", CharacterFrame)
    panel:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 14, -70)
    panel:SetPoint("BOTTOMRIGHT", CharacterFrame, "BOTTOMRIGHT", -36, 36)
    panel:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    -- Room at the bottom for the snapshot buttons.
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 30)

    local save = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    save:SetSize(120, 22)
    save:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 6, 4)
    save:SetText("Save snapshot")
    save:SetScript("OnClick", function()
        SaveSnapshot()
        Refresh()
    end)
    save:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Save snapshot")
        GameTooltip:AddLine("Remembers your stats as they are now. Change gear or talents afterwards and every line shows what went up in green and what went down in red.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    save:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    clear:SetSize(60, 22)
    clear:SetPoint("LEFT", save, "RIGHT", 4, 0)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function()
        ClearSnapshot()
        Refresh()
    end)

    local when = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    when:SetPoint("LEFT", clear, "RIGHT", 8, 0)
    panel.snapshotLabel = when

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    -- The wheel moves the page, and only as far as there is page to move.
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, direction)
        local limit = math.max(0, (content:GetHeight() or 0) - self:GetHeight())
        local position = self:GetVerticalScroll() - direction * 20
        self:SetVerticalScroll(math.max(0, math.min(limit, position)))
    end)

    panel.scroll, panel.content = scroll, content

    panel:SetScript("OnShow", function()
        content:SetWidth(scroll:GetWidth())
        Refresh()
        if SetSpeedTicker then SetSpeedTicker(true) end
    end)
    panel:SetScript("OnHide", function()
        if SetSpeedTicker then SetSpeedTicker(false) end
    end)

    return panel
end

-- ── The tab ─────────────────────────────────────────────────────────────────

-- The last tab the game itself put on the window. Counted rather than assumed
-- to be three: another addon may already have added one, and sitting on top of
-- it would hide whatever it opens.
local function LastTab()
    local last, index = nil, 1
    while true do
        local button = _G["CharacterFrameTab" .. index]
        if not button then break end
        if button ~= tab then last = button end
        index = index + 1
    end
    return last
end

local function SelectOurTab()
    HideBlizzardSubframes()
    if PanelTemplates_DeselectTab then
        local index = 1
        while _G["CharacterFrameTab" .. index] do
            local button = _G["CharacterFrameTab" .. index]
            if button ~= tab then pcall(PanelTemplates_DeselectTab, button) end
            index = index + 1
        end
    end
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, tab) end
    BuildPanel()
    if panel then panel:Show() end
end

-- Any other tab takes the window back: its frame appearing is the signal, so
-- this works for Blizzard's tabs and for a tab another addon added alike.
local function StandDown()
    if panel then panel:Hide() end
    if tab and PanelTemplates_DeselectTab then pcall(PanelTemplates_DeselectTab, tab) end
end

-- The name of the tab template has moved between builds, and asking for one
-- that is not there is an error rather than a nil. So each candidate is tried
-- until one takes, and a plain button is the answer if none of them do: a tab
-- that looks slightly wrong still opens the page, an error opens nothing.
local TAB_TEMPLATES = {
    "PanelTabButtonTemplate",
    "CharacterFrameTabButtonTemplate",
    "CharacterFrameTabTemplate",
    "PanelTopTabButtonTemplate",
    "TabButtonTemplate",
}

local function CreateTabButton()
    for _, template in ipairs(TAB_TEMPLATES) do
        local ok, button = pcall(CreateFrame, "Button", "OxedHubAttributesTab",
            CharacterFrame, template)
        if ok and button then return button end
    end
    local ok, button = pcall(CreateFrame, "Button", "OxedHubAttributesTab",
        CharacterFrame, "UIPanelButtonTemplate")
    if ok and button then
        button:SetSize(90, 22)
        return button
    end
    return nil
end

local function BuildTab()
    if tab or not CharacterFrame then return end

    local anchor = LastTab()
    if not anchor then return end   -- tabs not built yet

    tab = CreateTabButton()
    if not tab then return end
    tab:SetText(STAT_CATEGORY_ATTRIBUTES or "Attributes")
    -- The tab is built as soon as the character window exists, which can be
    -- before settings are read. It starts hidden and OnEnable shows it, so a
    -- module that is off never puts a tab on the window.
    if not (settings and settings.enabled == true) then tab:Hide() end
    -- Blizzard's own tabs overlap by about 16px, which is what their artwork is
    -- cut for. Ours is a separate tab rather than one more of the same strip, so
    -- it stands clear instead of sitting on top of Currency.
    tab:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    tab:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
        SelectOurTab()
    end)

    for _, name in ipairs(SUBFRAMES) do
        local frame = _G[name]
        if frame then frame:HookScript("OnShow", StandDown) end
    end

    CharacterFrame:HookScript("OnHide", StandDown)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local watcher = CreateFrame("Frame")

local STAT_EVENTS = {
    "UNIT_STATS", "UNIT_AURA", "COMBAT_RATING_UPDATE", "MASTERY_UPDATE",
    "SPEED_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_TARGET_CHANGED",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE", "UNIT_MAXHEALTH", "PLAYER_SPECIALIZATION_CHANGED",
}

local function InstallHook()
    if hooked then return end
    if not (CharacterFrame and _G.CharacterFrameTab1) then return end
    hooked = true

    BuildTab()

    -- Unit events for the player, plain events for the rest. Registering every
    -- one as a unit event, as this used to, fails quietly for the plain ones
    -- (inside the pcall), so a gear or rating change never redrew the page.
    for _, event in ipairs(STAT_EVENTS) do
        if event:find("^UNIT_") then
            pcall(watcher.RegisterUnitEvent, watcher, event, "player")
        else
            pcall(watcher.RegisterEvent, watcher, event)
        end
    end
    watcher:SetScript("OnEvent", Refresh)

    -- The speed line's ticker runs only while the Attributes tab is open. It
    -- used to run every frame from login on, with the character window shut,
    -- doing nothing but checking that the tab was hidden.
    local function SpeedTick(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < UPDATE_INTERVAL then return end
        self.elapsed = 0
        RefreshSpeedOnly()
    end
    SetSpeedTicker = function(on)
        watcher.elapsed = 0
        watcher:SetScript("OnUpdate", on and SpeedTick or nil)
    end
    if panel and panel:IsShown() then SetSpeedTicker(true) end
end

-- The character frame is loaded on demand, so the tab waits for it.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, loadedAddon)
    if loadedAddon == "Blizzard_CharacterUI" or _G.CharacterFrameTab1 then
        InstallHook()
        if hooked then
            self:UnregisterEvent("ADDON_LOADED")
            self:SetScript("OnEvent", nil)
        end
    end
end)

-- ── On-screen display ───────────────────────────────────────────────────────
-- The same lines as the tab, in a small box anywhere on screen. Left button
-- drags it, right button opens a picker: tick the stats to show and set the
-- targets right there, while watching the numbers move.

local hud, picker
local hudLines = {}          -- its own pool: the tab's lines live in the tab
local hudWatcher = CreateFrame("Frame")
local hudQueued = false
local hudInCombat = false
local RefreshHUD, QueueHUD, ShowPicker, ApplyHudVisibility, SaveHudPosition

local HUD_PAD = 6
local HUD_WIDTH = 230

local function HudMouseDown(_, button)
    if button == "LeftButton" and hud and not settings.hudLocked then hud:StartMoving() end
end

local function HudMouseUp(_, button)
    if not hud then return end
    hud:StopMovingOrSizing()
    SaveHudPosition()
    if button == "RightButton" then ShowPicker() end
end

-- Lines take the mouse for their tooltips, which would swallow the drag and
-- the right click. They hand both to the box.
local function WireHudLine(line)
    if line.hudWired then return end
    line.hudWired = true
    line:SetScript("OnMouseDown", HudMouseDown)
    line:SetScript("OnMouseUp", HudMouseUp)
end

SaveHudPosition = function()
    if not hud then return end
    local point, _, _, x, y = hud:GetPoint(1)
    if point then
        settings.hudPoint, settings.hudX, settings.hudY = point, x, y
    end
end

local function PlaceHud()
    hud:ClearAllPoints()
    hud:SetPoint(settings.hudPoint or "CENTER", UIParent, settings.hudPoint or "CENTER",
        tonumber(settings.hudX) or 0, tonumber(settings.hudY) or 0)
end

local function StyleHud()
    if not hud then return end
    hud:SetScale(math.max(0.5, math.min(2, tonumber(settings.hudScale) or 1)))
    local alpha = tonumber(settings.hudAlpha) or 0.75
    hud:SetBackdropColor(0.04, 0.04, 0.06, alpha)
    hud:SetBackdropBorderColor(0.35, 0.35, 0.4, math.min(1, alpha + 0.15))
end

local function BuildHud()
    if hud then return end
    hud = CreateFrame("Frame", "OxedHubAttributesHUD", UIParent, "BackdropTemplate")
    hud:SetSize(HUD_WIDTH, 40)
    hud:SetFrameStrata("MEDIUM")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    hud:SetScript("OnMouseDown", HudMouseDown)
    hud:SetScript("OnMouseUp", HudMouseUp)

    hud.empty = hud:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    hud.empty:SetPoint("CENTER")
    hud.empty:SetText("Right-click to pick stats")

    -- Only the speed line moves between events; it is read a few times a
    -- second here and nothing else is.
    hud.elapsed = 0
    hud:SetScript("OnUpdate", function(self, elapsed)
        if not self.speedLine then return end
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.2 then return end
        self.elapsed = 0
        local value, _, body = ReadSpeed()
        if value then
            self.speedLine.value:SetText(value)
            self.speedLine.tipBody = body
        end
    end)

    hud:Hide()
    PlaceHud()
    StyleHud()
end

RefreshHUD = function()
    hudQueued = false
    if not (hud and hud:IsShown()) then return end

    local chosen = settings.hudStats or {}
    local shown, y = 0, HUD_PAD
    hud.speedLine = nil

    for _, row in ipairs(ROWS) do
        if row.id and chosen[row.id] then
            local line
            if row.bar then
                local info = ReadTarget(row.bar)
                if info then
                    shown = shown + 1
                    line = GetLine(shown, hud, hudLines)
                    SetBarLine(line, info)
                end
            else
                local value, label, body = row.read()
                if value then
                    shown = shown + 1
                    line = GetLine(shown, hud, hudLines)
                    SetValueLine(line, label, value, body)
                    if row.live then hud.speedLine = line end
                end
            end
            if line then
                WireHudLine(line)
                line:ClearAllPoints()
                line:SetPoint("TOPLEFT", hud, "TOPLEFT", 0, -y)
                line:SetPoint("TOPRIGHT", hud, "TOPRIGHT", 0, -y)
                line:Show()
                y = y + (row.bar and 28 or 18)
            end
        end
    end

    for index = shown + 1, #hudLines do hudLines[index]:Hide() end
    hud.empty:SetShown(shown == 0)
    if shown == 0 then y = y + 20 end
    hud:SetHeight(y + HUD_PAD)
end

-- UNIT_AURA alone can arrive dozens of times a second in a fight; one redraw
-- a tenth of a second after the first of a burst covers all of them.
QueueHUD = function()
    if hudQueued then return end
    hudQueued = true
    C_Timer.After(0.1, RefreshHUD)
end

ApplyHudVisibility = function()
    local show = settings and settings.enabled ~= false and settings.hud
        and (not settings.hudCombat or hudInCombat)
    if show then
        BuildHud()
        StyleHud()
        hud:Show()
        RefreshHUD()
    else
        if hud then hud:Hide() end
    end
end

hudWatcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        hudInCombat = true
        ApplyHudVisibility()
    elseif event == "PLAYER_REGEN_ENABLED" then
        hudInCombat = false
        ApplyHudVisibility()
    else
        QueueHUD()
    end
end)

local function StartHUD()
    if type(settings.hudStats) ~= "table" then settings.hudStats = {} end
    hudInCombat = UnitAffectingCombat and UnitAffectingCombat("player") or false
    for _, event in ipairs(STAT_EVENTS) do
        if event:find("^UNIT_") then
            pcall(hudWatcher.RegisterUnitEvent, hudWatcher, event, "player")
        else
            pcall(hudWatcher.RegisterEvent, hudWatcher, event)
        end
    end
    hudWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    hudWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    ApplyHudVisibility()
end

local function StopHUD()
    hudWatcher:UnregisterAllEvents()
    if hud then hud:Hide() end
    if picker then picker:Hide() end
end

-- ── The picker ──

local function PickerCheck(parent, x, y, text, get, set)
    local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    box:SetSize(22, 22)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    box.text:SetFontObject("GameFontHighlightSmall")
    box.text:SetText(text)
    box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    box.Refresh = function() box:SetChecked(get() and true or false) end
    table.insert(parent.checks, box)
    return box
end

local function PickerSlider(parent, x, y, width, minValue, maxValue, step, caption, get, set)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width, 14)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 14)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    -- The template's own min / max captions only crowd a small window.
    for _, key in ipairs({ "Low", "High", "Text" }) do
        local region = slider[key] or (slider:GetName() and _G[slider:GetName() .. key])
        if region then region:SetText("") end
    end

    local refreshing = false
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value / step + 0.5) * step
        label:SetText(caption(value))
        if not refreshing then set(value) end
    end)
    slider.Refresh = function()
        refreshing = true
        local value = get()
        slider:SetValue(value)
        label:SetText(caption(value))
        refreshing = false
    end
    table.insert(parent.checks, slider)
    return slider
end

local function BuildPicker()
    picker = CreateFrame("Frame", "OxedHubAttributesPicker", UIParent, "BackdropTemplate")
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:SetMovable(true)
    picker:EnableMouse(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    picker:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    picker:SetBackdropBorderColor(0.45, 0.4, 0.2, 1)
    picker.checks = {}
    tinsert(UISpecialFrames, "OxedHubAttributesPicker")   -- Escape closes it

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Stats on screen")

    local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local function Toggle(id)
        return function() return settings.hudStats[id] end,
            function(on)
                settings.hudStats[id] = on or nil
                RefreshHUD()
            end
    end

    -- Left column: every plain stat, in the tab's order.
    local y = -32
    for _, row in ipairs(ROWS) do
        if row.id and not row.bar then
            PickerCheck(picker, 10, y, row.name, Toggle(row.id))
            y = y - 20
        end
    end
    local leftBottom = y

    -- Right column: the target bars, each with its target under it, then the
    -- box's own look.
    local x = 200
    y = -32
    local head = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOPLEFT", picker, "TOPLEFT", x, y)
    head:SetText("Target bars (this spec)")
    y = y - 16
    for _, row in ipairs(ROWS) do
        if row.bar then
            PickerCheck(picker, x, y, row.name .. " bar", Toggle(row.id))
            y = y - 22
            local entry = row.bar
            PickerSlider(picker, x + 8, y, 190, 0, 60, 1,
                function(value)
                    return value <= 0 and "Target: |cff808080none|r" or ("Target: %d%%"):format(value)
                end,
                function() return GetTarget(entry.key) or 0 end,
                function(value)
                    SetTarget(entry.key, value)
                    Refresh()
                    RefreshHUD()
                end)
            y = y - 36
        end
    end

    y = y - 4
    local look = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    look:SetPoint("TOPLEFT", picker, "TOPLEFT", x, y)
    look:SetText("Display")
    y = y - 16
    PickerCheck(picker, x, y, "Lock position",
        function() return settings.hudLocked end,
        function(on) settings.hudLocked = on end)
    y = y - 20
    PickerCheck(picker, x, y, "Only in combat",
        function() return settings.hudCombat end,
        function(on) settings.hudCombat = on; ApplyHudVisibility() end)
    y = y - 24
    PickerSlider(picker, x + 8, y, 190, 0.6, 1.6, 0.05,
        function(value) return ("Scale: %.2f"):format(value) end,
        function() return tonumber(settings.hudScale) or 1 end,
        function(value) settings.hudScale = value; StyleHud() end)
    y = y - 36
    PickerSlider(picker, x + 8, y, 190, 0, 1, 0.05,
        function(value) return ("Background: %d%%"):format(value * 100 + 0.5) end,
        function() return tonumber(settings.hudAlpha) or 0.75 end,
        function(value) settings.hudAlpha = value; StyleHud() end)
    y = y - 38

    local hide = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    hide:SetSize(120, 22)
    hide:SetPoint("TOPLEFT", picker, "TOPLEFT", x + 8, y)
    hide:SetText("Hide display")
    hide:SetScript("OnClick", function()
        settings.hud = false
        ApplyHudVisibility()
        picker:Hide()
        print("|cff00ccffOxedHub|r Stats display hidden. Bring it back with /oxstats.")
    end)
    y = y - 30

    picker:SetSize(410, math.max(-leftBottom, -y) + 10)
    picker:SetScript("OnShow", function(self)
        for _, control in ipairs(self.checks) do control.Refresh() end
    end)
    picker:Hide()
end

ShowPicker = function()
    if not settings then return end
    if not picker then BuildPicker() end
    -- Beside the box, on whichever side has room.
    picker:ClearAllPoints()
    if hud and hud:IsShown() then
        local centre = hud:GetCenter() * hud:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if centre < UIParent:GetWidth() / 2 then
            picker:SetPoint("TOPLEFT", hud, "TOPRIGHT", 6, 0)
        else
            picker:SetPoint("TOPRIGHT", hud, "TOPLEFT", -6, 0)
        end
    else
        picker:SetPoint("CENTER")
    end
    picker:Show()

    -- Placed beside the box once, then let go of it: left anchored, the
    -- picker slid about every time the Scale slider resized the box.
    local left, top = picker:GetLeft(), picker:GetTop()
    if left and top then
        picker:ClearAllPoints()
        picker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

SLASH_OXEDHUBSTATS1 = "/oxstats"
SlashCmdList.OXEDHUBSTATS = function(msg)
    if not settings then return end
    if settings.enabled == false then
        print("|cff00ccffOxedHub|r Switch the Attributes module on first (Modules page).")
        return
    end
    msg = (msg or ""):lower()
    if msg == "pick" or msg == "config" then
        settings.hud = true
        ApplyHudVisibility()
        ShowPicker()
        return
    end
    settings.hud = not settings.hud
    ApplyHudVisibility()
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.attributes
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.attributes = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is copied by reference,
    -- and every character would end up sharing one set of targets.
    if type(config.statTargets) ~= "table" then config.statTargets = {} end
    if type(config.hudStats) ~= "table" then
        config.hudStats = { crit = true, haste = true, mastery = true, versatility = true, speed = true }
    end
    settings = config
end

-- One slider per secondary, writing the target for the specialisation being
-- played right now. Zero means no target, which is how a bar is turned off
-- again without a second control for it.
local function AddTargetSlider(w, entry)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(230, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 200, w.cursorY - 6)
    slider:SetMinMaxValues(0, 60)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)

    local function ShowValue(value)
        if value <= 0 then
            label:SetText(("%s: |cff808080none|r"):format(entry.label))
        else
            label:SetText(("%s: %d%%"):format(entry.label, value))
        end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        ShowValue(value)
        if value ~= (GetTarget(entry.key) or 0) then
            SetTarget(entry.key, value)
            Refresh()
        end
    end)

    -- Read again every time the window opens: targets belong to the
    -- specialisation, and the player may have changed it meanwhile.
    w:HookScript("OnShow", function()
        local value = GetTarget(entry.key) or 0
        slider:SetValue(value)
        ShowValue(value)
    end)

    w.cursorY = w.cursorY - 30
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Attributes", 460, 680)
        optionsWindow:AddCheckbox(settings, "hud", "Show stats on screen",
            "A small box you can put anywhere. Drag it with the left button, right-click it to choose the stats and set your targets.",
            function() ApplyHudVisibility() end)
        optionsWindow:AddNote("Right-click the box to pick what it shows. /oxstats toggles it.")
        optionsWindow:AddCheckbox(settings, "primary", "Attributes",
            "Your specialisation's main stat and stamina.", Refresh)
        optionsWindow:AddCheckbox(settings, "gear", "Gear",
            "Item level, and the equipped slot furthest behind.", Refresh)
        optionsWindow:AddCheckbox(settings, "diminishing", "Diminishing returns",
            "Colours a rating orange once each extra point is worth less, and says how much is lost and when the next drop comes. The game itself is asked, so it follows every patch.", Refresh)
        optionsWindow:AddCheckbox(settings, "deltas", "Changes since snapshot",
            "After Save snapshot on the tab, every line shows how far it has moved: green up, red down.", Refresh)
        optionsWindow:AddCheckbox(settings, "speed", "Movement",
            "A live reading of how fast you are moving, plus the Speed stat.", Refresh)
        optionsWindow:AddCheckbox(settings, "offense", "Offense",
            "Crit, haste, mastery and versatility, each with its rating, and your global cooldown.", Refresh)
        optionsWindow:AddCheckbox(settings, "hidden", "Hidden stats",
            "Leech and avoidance, the ones the sheet never prints.", Refresh)
        optionsWindow:AddCheckbox(settings, "defense", "Defense",
            "Armour and what it actually takes off a hit, dodge, parry, block, stagger.", Refresh)
        optionsWindow:AddCheckbox(settings, "ratings", "Show ratings",
            "Print the rating in grey next to each percentage.", Refresh)
        optionsWindow:AddCheckbox(settings, "vehicle", "Read vehicle speed",
            "While you are driving something, show its speed instead of your own.", Refresh)
        optionsWindow:AddCheckbox(settings, "targets", "Stat targets",
            "A bar per secondary stat showing how far you are from a target you set, and how much more rating it would take.", Refresh)

        optionsWindow:AddNote("Targets for the specialisation you are playing now. Zero means no target. The missing rating is worked out from what the game says each amount is worth, so diminishing returns are already counted.")
        for _, entry in ipairs(SECONDARIES) do
            AddTargetSlider(optionsWindow, entry)
        end

        optionsWindow:AddNote("Everything appears on the Attributes tab of your character window.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    InstallHook()

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "attributes",
        name     = "Attributes",
        version  = "1.1.0",
        author   = "Oxed",
        category = "character",
        keywords = { "stats", "haste", "crit", "mastery", "versatility", "speed", "item level", "ilvl", "diminishing returns", "targets", "leech", "avoidance" },
        desc     = "A character window tab with live move speed and hidden stats like leech and stagger.",
        icon     = "Interface\\Icons\\Spell_Holy_WordFortitude",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            InstallHook()
            if tab then tab:Show() end
            StartHUD()
        end,

        OnDisable = function()
            StopHUD()
            StandDown()
            if tab then tab:Hide() end
        end,
    })
end)
