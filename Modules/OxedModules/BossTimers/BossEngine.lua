-- ============================================================================
-- Boss Timers: the engine
-- Follows the game's boss timeline (C_EncounterTimeline) and works out which
-- ability each coming event is, so every ability can have its own settings.
--
-- ⚠ The game hides an event's spell, name and icon in a fight (secret
-- values). What it does not hide is the event's duration: how many seconds
-- until it lands. BossData holds, per boss, which duration belongs to which
-- ability, so the duration is how an event is recognised:
--
--   * Events the game adds at the same moment (within SYNC_WINDOW) form a
--     batch. A pull, or a new phase, adds several at once, and those are
--     matched against the boss's "sync" rules; later single events against
--     the rest.
--   * The nearest rule within TOLERANCE wins. Abilities that share one
--     duration take turns in the order the data gives (group + order).
--   * Bosses whose timings change with the phase have a state machine: a
--     batch with the right set of durations moves it to the next phase,
--     which brings its own rules.
--
-- An event that cannot be recognised still shows, with the game's own name
-- and icon (secret, handed only to SetText / SetTexture); it just has no
-- per-ability settings.
--
-- The engine draws nothing. Displays ask it for the list of coming events
-- (BossEngine:GetEvents) and register for its callbacks.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local Engine = {}
OxedHub.BossEngine = Engine

local SYNC_WINDOW = 0.1
local TOLERANCE   = 0.75
local MAX_EVENT   = 300   -- longer than this is not a boss ability

local STATE_ACTIVE = Enum and Enum.EncounterTimelineEventState
    and Enum.EncounterTimelineEventState.Active or 0

local frame = CreateFrame("Frame")
local running = false
local encounterID, encounter
local phase, rules
local sequence = {}       -- [group] = how many times the group has been used
local pending = {}        -- events waiting for their batch to close
local flushQueued = false
local events = {}         -- [timeline id] = event, see AddEvent
local listeners = {}

-- A plain number, or nil when the value is missing or secret.
local function Plain(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end
Engine.Plain = Plain

local function Fire(name, ...)
    for _, fn in ipairs(listeners) do
        local handler = fn[name]
        if handler then
            local ok, err = pcall(handler, ...)
            -- One broken display must not stop the others: report and go on.
            if not ok then geterrorhandler()(err) end
        end
    end
end

-- A display registers a table of handlers:
--   OnEventAdded(event), OnEventRemoved(event), OnEncounterStart(id),
--   OnEncounterEnd(id), OnPhase(name)
function Engine:AddListener(handlers)
    table.insert(listeners, handlers)
end

-- ── Encounter data ─────────────────────────────────────────────────────────

function Engine:GetEncounter(id)
    local data = OxedHub.BossData
    return data and data.encounters and data.encounters[id] or nil
end

function Engine:GetCurrentEncounter()
    return encounterID, encounter
end

-- The ability's name, plain text: from the label in the data, or the game's
-- name for its spell id. A spell id we hold is never secret.
function Engine:AbilityName(ability)
    if not ability then return nil end
    if ability.label then return ability.label end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ability.spell)
    return name or ("Spell " .. tostring(ability.spell))
end

function Engine:AbilityIcon(ability)
    if not ability then return nil end
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ability.spell)
    return icon or 134400
end

-- ── Recognition ────────────────────────────────────────────────────────────

local function PhaseRow()
    local machine = encounter and encounter.machine
    return machine and machine.phases and phase and machine.phases[phase] or nil
end

local function SetPhase(name)
    if name == phase then return end
    phase = name
    local row = PhaseRow()
    rules = (row and row.rules) or (encounter and encounter.rules) or nil
    wipe(sequence)
    Fire("OnPhase", name)
end

-- Durations a little off a known value are snapped to it first.
local function Normalize(duration)
    local function Apply(list, value)
        if type(list) ~= "table" then return value end
        for _, row in ipairs(list) do
            if row.min and row.max and row.snap and value >= row.min and value <= row.max then
                return row.snap
            end
        end
        return value
    end
    local machine = encounter and encounter.machine
    duration = Apply(machine and machine.normalize, duration)
    local row = PhaseRow()
    return Apply(row and row.normalize, duration)
end

-- A batch with the durations a phase is entered by moves to that phase.
local function UpdatePhase(batch)
    local machine = encounter and encounter.machine
    if not (machine and machine.phases) then return end
    local best, bestPriority
    for name, row in pairs(machine.phases) do
        local enter = row.enter
        if enter then
            local tolerance = enter.tolerance or TOLERANCE
            local matched = false
            if enter.mode == "sync_batch_all" and enter.times then
                local used = {}
                matched = true
                for _, target in ipairs(enter.times) do
                    local found = false
                    for index, item in ipairs(batch) do
                        if not used[index] and math.abs(item.duration - target) <= tolerance then
                            used[index], found = true, true
                            break
                        end
                    end
                    if not found then matched = false; break end
                end
            elseif enter.mode == "duration_once" and enter.time then
                for _, item in ipairs(batch) do
                    if math.abs(item.duration - enter.time) <= tolerance then matched = true; break end
                end
            end
            local priority = enter.priority or 0
            if matched and (not best or priority > bestPriority) then
                best, bestPriority = name, priority
            end
        end
    end
    if best then SetPhase(best) end
end

local function CountSyncMatches(batch)
    if not rules then return 0 end
    local count = 0
    for _, item in ipairs(batch) do
        local d = Normalize(item.duration)
        for _, rule in ipairs(rules) do
            if rule.sync and math.abs(d - rule.time) <= TOLERANCE then
                count = count + 1
                break
            end
        end
    end
    return count
end

-- The ability event id a duration stands for, or nil.
local function Resolve(duration, timelineID, syncMode, anySync)
    if not rules then return nil end
    local d = Normalize(duration)
    local candidates, bestDelta = {}, nil
    for _, rule in ipairs(rules) do
        local ruleSync = rule.sync == true
        if anySync or ruleSync == syncMode then
            local delta = math.abs(d - rule.time)
            if not bestDelta or delta < bestDelta then
                bestDelta = delta
                candidates = { rule }
            elseif delta == bestDelta then
                candidates[#candidates + 1] = rule
            end
        end
    end
    if not bestDelta or bestDelta > TOLERANCE then return nil end
    if #candidates == 1 or syncMode then return candidates[1].event end

    -- Several abilities share this duration: take them in turn.
    local group = candidates[1].group
    if not group then return candidates[1].event end
    local grouped = {}
    for _, rule in ipairs(candidates) do
        if rule.group == group then grouped[#grouped + 1] = rule end
    end
    table.sort(grouped, function(a, b) return (a.order or 0) < (b.order or 0) end)
    local used = sequence[group] or 0
    sequence[group] = used + 1
    local chosen = grouped[(used % #grouped) + 1]
    return chosen and chosen.event or nil
end

-- ── Events ─────────────────────────────────────────────────────────────────

-- An event on the timeline. Fields a display can read:
--   id          the timeline's id for it
--   duration    seconds from when it was added to when it lands
--   endsAt      GetTime() at which it lands (kept in step with the game)
--   abilityID   the ability's event id in BossData, or nil if unrecognised
--   ability     the BossData row, or nil
--   name, icon  plain name and icon when recognised; otherwise the game's
--               own, which may be secret (only for SetText / SetTexture)
--   known       true when name and icon are plain
local function AddEvent(item, abilityID)
    local ability = abilityID and encounter and encounter.abilities and encounter.abilities[abilityID] or nil
    local ev = {
        id = item.id,
        duration = item.duration,
        endsAt = item.at + item.duration,
        abilityID = ability and abilityID or nil,
        ability = ability,
        encounterID = encounterID,
    }
    if ability then
        ev.name, ev.icon, ev.known = Engine:AbilityName(ability), Engine:AbilityIcon(ability), true
    else
        ev.name, ev.icon = item.name, item.icon
    end
    events[item.id] = ev
    Fire("OnEventAdded", ev)
end

local function Flush()
    flushQueued = false
    if #pending == 0 then return end
    local batch = pending
    pending = {}
    if encounter then
        UpdatePhase(batch)
        local syncMode = CountSyncMatches(batch) >= 2
        if syncMode then wipe(sequence) end
        for _, item in ipairs(batch) do
            local abilityID = Resolve(item.duration, item.id, syncMode, false)
            if not abilityID and syncMode then
                abilityID = Resolve(item.duration, item.id, syncMode, true)
            end
            AddEvent(item, abilityID)
        end
    else
        for _, item in ipairs(batch) do AddEvent(item, nil) end
    end
end

local function OnAdded(info)
    if type(info) ~= "table" then return end
    local id, duration = Plain(info.id), Plain(info.duration)
    if not id or not duration or duration < 0 or duration > MAX_EVENT then return end
    table.insert(pending, {
        id = id, duration = duration, at = GetTime(),
        name = info.spellName, icon = info.iconFileID,   -- may be secret
    })
    if not flushQueued then
        flushQueued = true
        C_Timer.After(SYNC_WINDOW, Flush)
    end
end

local function RemoveEvent(id)
    local ev = events[id]
    if not ev then return end
    events[id] = nil
    Fire("OnEventRemoved", ev)
end

-- Time left for an event, from the game when it says, else from endsAt.
function Engine:TimeLeft(ev)
    local now = GetTime()
    if ev._leftAt and (now - ev._leftAt) < 0.04 then
        return ev._leftVal
    end
    local left
    if ev.test or ev.custom then
        left = ev.endsAt - now
    else
        if C_EncounterTimeline and C_EncounterTimeline.GetEventTimeRemaining then
            local ok, rem = pcall(C_EncounterTimeline.GetEventTimeRemaining, ev.id)
            rem = ok and Plain(rem) or nil
            if rem then
                ev.endsAt = now + rem
                left = rem
            end
        end
        if not left then
            left = ev.endsAt - now
        end
    end
    ev._leftAt = now
    ev._leftVal = left
    if left < -0.5 and events[ev.id] == ev then
        RemoveEvent(ev.id)
    end
    return left
end

-- False while the game has the event paused, finished or cancelled.
function Engine:IsActive(ev)
    if ev.test or ev.custom then return true end
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventState) then return true end
    local now = GetTime()
    if ev._activeAt and (now - ev._activeAt) < 0.04 then
        return ev._activeVal
    end
    local ok, state = pcall(C_EncounterTimeline.GetEventState, ev.id)
    state = ok and Plain(state) or nil
    local active = (state == nil) or (state == STATE_ACTIVE)
    ev._activeAt = now
    ev._activeVal = active
    return active
end

function Engine:GetEvents()
    return events
end

-- Test events for the displays' "Test" buttons: shaped like real ones.
function Engine:AddTestEvents(list)
    -- A second press restarts the test rather than adding a second set.
    for id, ev in pairs(events) do
        if ev.test then events[id] = nil; Fire("OnEventRemoved", ev) end
    end
    local now = GetTime()
    for i, row in ipairs(list) do
        local id = -i - math.floor(now)
        local ev = {
            id = id, duration = row.duration, endsAt = now + row.duration,
            name = row.name, icon = row.icon, known = true, test = true,
            ability = { kind = row.kind or "other", severity = row.severity or 1, spell = 0 },
            abilityID = row.abilityID,
        }
        events[id] = ev
        Fire("OnEventAdded", ev)
    end
    -- Each test event leaves once it has landed.
    for id, ev in pairs(events) do
        if ev.test then
            C_Timer.After(math.max(0, ev.endsAt - now) + 0.5, function()
                if events[id] == ev then RemoveEvent(id) end
            end)
        end
    end
end

-- Events another module times itself (trash cooldowns): shown by every
-- display like a boss ability. key is the module's own id for the event.
--   ev = { key, name, icon, seconds, kind, encounterID, abilityID }
-- name and icon must be plain. Adding a key again moves its time.
local customByKey, customKeyCounter = {}, 0
function Engine:AddCustomEvent(def)
    local old = customByKey[def.key]
    if old and events[old.id] == old then RemoveEvent(old.id) end
    customKeyCounter = customKeyCounter + 1
    local id = -1000000 - customKeyCounter
    local ev = {
        id = id, duration = def.seconds, endsAt = GetTime() + def.seconds,
        name = def.name, icon = def.icon, known = true, custom = true,
        ability = { kind = def.kind or "other", severity = 1, spell = def.spell or 0 },
        encounterID = def.encounterID, abilityID = def.abilityID, key = def.key,
    }
    customByKey[def.key] = ev
    events[id] = ev
    Fire("OnEventAdded", ev)
    return ev
end

function Engine:RemoveCustomEvent(key)
    local ev = customByKey[key]
    customByKey[key] = nil
    if ev and events[ev.id] == ev then RemoveEvent(ev.id) end
end

local function ClearAll()
    for id in pairs(events) do RemoveEvent(id) end
    wipe(pending)
end

-- ── Encounters ─────────────────────────────────────────────────────────────

local function StartEncounter(id)
    encounterID = id
    encounter = Engine:GetEncounter(id)
    phase, rules = nil, nil
    wipe(sequence)
    if encounter then
        local machine = encounter.machine
        if machine and machine.start and machine.phases and machine.phases[machine.start] then
            SetPhase(machine.start)
        else
            rules = encounter.rules
        end
    end
    Fire("OnEncounterStart", id)
end

local function EndEncounter()
    local id = encounterID
    ClearAll()
    encounterID, encounter, phase, rules = nil, nil, nil, nil
    Fire("OnEncounterEnd", id)
end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        OnAdded(...)
    elseif event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        local id = Plain(...)
        if id then RemoveEvent(id) end
    elseif event == "ENCOUNTER_START" then
        local id = Plain(...)
        StartEncounter(id)
    elseif event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
        EndEncounter()
    end
end)

-- Picks up what is already on the timeline: a /reload mid-fight.
local function Recover()
    if not (C_EncounterTimeline and C_EncounterTimeline.GetEventList) then return end
    local ok, list = pcall(C_EncounterTimeline.GetEventList)
    if not ok or type(list) ~= "table" then return end
    for _, id in ipairs(list) do
        local okInfo, info = pcall(C_EncounterTimeline.GetEventInfo, id)
        if okInfo and type(info) == "table" and not events[Plain(id) or 0] then
            local left = nil
            local okLeft, value = pcall(C_EncounterTimeline.GetEventTimeRemaining, id)
            if okLeft then left = Plain(value) end
            local plainId = Plain(info.id) or Plain(id)
            if plainId and left then
                -- Recognition needs the event's full duration, which a
                -- recovered event no longer has: shown unrecognised.
                AddEvent({ id = plainId, duration = Plain(info.duration) or left,
                    at = GetTime() + left - (Plain(info.duration) or left),
                    name = info.spellName, icon = info.iconFileID }, nil)
            end
        end
    end
end

-- Started by the first display that needs it, stopped with the last.
local users = 0
function Engine:Start()
    users = users + 1
    if running then return end
    running = true
    frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    frame:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    Recover()
end

function Engine:Stop()
    users = math.max(0, users - 1)
    if users > 0 or not running then return end
    running = false
    frame:UnregisterAllEvents()
    ClearAll()
end
