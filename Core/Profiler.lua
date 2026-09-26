-- ============================================================================
-- Profiler
-- Finds out which part of OxedHub a lag spike came from: which event, which
-- rule, which sound or animation, which timer.
--
-- The game can only say how long an addon took as a whole. That is enough to
-- tell OxedHub from the other addons, and it is used for exactly that, but it
-- cannot say that the time went into the "CD" rule playing its animation. So
-- OxedHub measures itself: named timings around the places it does work, kept
-- as a total per name, and a record of every long frame with what ran inside
-- it, nested the way it ran.
--
-- It costs nothing while it is off. Every wrapper begins with one check of a
-- local flag and hands straight through; nothing is timed, stored or allocated
-- until Start. The report window is Modules\Performance.lua; /oxprofile opens it.
--
-- Loads second in the TOC, right after the loader, so every file after it can
-- ask for a timer proxy and every script handler they set can be named.
-- ============================================================================

local addonName, OxedHub = ...

local Profiler = {}
OxedHub.Profiler = Profiler

local debugprofilestop = debugprofilestop
local GetTime = GetTime
local collectgarbage = collectgarbage

-- The hot path reads this local, not a table field.
local active = false

-- ── What is kept ────────────────────────────────────────────────────────────

-- Per name: calls, total and longest time, and when the longest happened.
local stats = {}

-- The calls made since the last frame tick, in the order they began, with how
-- deep each one sat inside another. Parallel arrays rather than a table per
-- call: a busy frame makes hundreds of calls, and a table each would feed the
-- very garbage collector whose pauses this is trying to find.
local BUCKET_CAP = 128
local function NewBucket()
    return { n = 0, over = 0, label = {}, ms = {}, depth = {} }
end
local cur, prev = NewBucket(), NewBucket()
local depth = 0

-- Long frames, newest last.
local SPIKE_LOG = 100
local spikes = {}

local session = { startedAt = nil, stoppedAt = nil, frames = 0, hitches = 0, causes = {} }

-- Rolling one-second figures for the mini window.
local live = {
    msPerSecond = 0, peakFrameMs = 0, worstFrame = 0,
    accum = 0, peakAccum = 0, worstFrameAccum = 0, startedAt = 0,
}

-- ── Recording ───────────────────────────────────────────────────────────────

local function Record(label, ms, kb, topLevel)
    local s = stats[label]
    if not s then
        s = { count = 0, total = 0, max = 0, alloc = 0, own = 0 }
        stats[label] = s
    end
    s.count = s.count + 1
    s.total = s.total + ms
    -- Time spent at the top of the stack only. The feature summary adds these
    -- up; a nested call is already inside its caller's time.
    if topLevel then s.own = (s.own or 0) + ms end
    -- Lua memory the call created. Garbage is what the collector has to clear
    -- later, and a collection is one of the classic causes of a hitch, so the
    -- functions that make the most of it are worth naming. Negative means a
    -- collection ran during the call; that call made nothing we can count.
    if kb and kb > 0 then s.alloc = (s.alloc or 0) + kb end
    if ms > s.max then
        s.max = ms
        s.maxAt = time()
    end
end

-- Closes a timed call. Takes the call's own return values through untouched,
-- so a wrapped function returns exactly what it always did.
local function Finish(label, bucket, slot, start, mem, ...)
    local ms = debugprofilestop() - start
    depth = depth - 1
    if depth < 0 then depth = 0 end
    Record(label, ms, collectgarbage("count") - mem, depth == 0)
    if slot then bucket.ms[slot] = ms end
    return ...
end

-- Wraps fn so each call is timed under label. label may be a function, given
-- the same arguments as fn, for names that depend on the call ("Trigger: CD").
-- statOnly calls count toward the totals but do not appear in spike records:
-- for things called dozens of times a frame, like checking every rule.
function Profiler:Wrap(label, fn, statOnly)
    if type(fn) ~= "function" then return fn end
    local dynamic = type(label) == "function"

    return function(...)
        if not active then return fn(...) end

        local name = label
        if dynamic then
            local ok, result = pcall(label, ...)
            name = ok and tostring(result) or "unnamed"
        end

        local bucket, slot = cur, nil
        if not statOnly then
            if bucket.n < BUCKET_CAP then
                slot = bucket.n + 1
                bucket.n = slot
                bucket.label[slot] = name
                bucket.ms[slot] = 0
                bucket.depth[slot] = depth
            else
                bucket.over = bucket.over + 1
            end
        end

        depth = depth + 1
        local mem = collectgarbage("count")
        local start = debugprofilestop()
        return Finish(name, bucket, slot, start, mem, fn(...))
    end
end

-- Replaces a method on a table with a timed version. Done once, after every
-- file has loaded; callers that look the method up at call time get the timed
-- one, which is how every OxedHub module calls its own methods.
local instrumented = setmetatable({}, { __mode = "k" })
function Profiler:WrapMethod(tbl, key, label, statOnly)
    if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return end
    instrumented[tbl] = instrumented[tbl] or {}
    if instrumented[tbl][key] then return end
    instrumented[tbl][key] = true
    tbl[key] = self:Wrap(label, tbl[key], statOnly)
end

-- ── Where a handler was written ─────────────────────────────────────────────

-- "Animations.lua:2618" for the first OxedHub line on the stack that is not
-- this file. Only ever asked while recording, and only when a handler or timer
-- is created, never when it runs.
-- ⚠ debugstack can hand back a SECRET string once execution has been tainted,
-- and reading one is an error ("attempt to index local 'stack' (a secret string
-- value)"). It is also not worth breaking a timer or a handler over a name, so
-- the whole read is done inside pcall: no name simply means the call is listed
-- without one.
local function ReadStack(startLevel)
    local stack = debugstack(startLevel or 3, 8, 0)
    if type(stack) ~= "string" then return nil end
    if issecretvalue and issecretvalue(stack) then return nil end

    for line in stack:gmatch("[^\n]+") do
        if not line:find("Profiler%.lua") and not line:find("%[C%]") and not line:find("tail call") then
            if not line:find("AddOns[/\\]OxedHub[/\\]") then return nil end
            local file, num = line:match("([%w_]+%.lua)\"?%]?:(%d+)")
            return file and (file .. ":" .. num) or "OxedHub"
        end
    end
    return nil
end

local function CallerLabel(startLevel)
    local ok, label = pcall(ReadStack, startLevel)
    return ok and label or nil
end

-- ── Plain names ─────────────────────────────────────────────────────────────
-- "PreyEngine.lua:900 UPDATE_UI_WIDGET" means something to whoever wrote it and
-- nothing to a player reading a report. Each file is named for the feature it
-- belongs to, and the noisier game events are said in words, with the file and
-- line kept at the end for whoever has to go and look.

local FEATURES = {
    ["Core.lua"] = "Triggers engine",
    ["Triggers.lua"] = "Triggers",
    ["Execution.lua"] = "Trigger actions",
    ["SpellProc.lua"] = "Proc trigger",
    ["SelfAura.lua"] = "My Buff trigger",
    ["Aura.lua"] = "Aura trigger",
    ["BasicAuraTracker.lua"] = "Aura tracker",
    ["Bloodlust.lua"] = "Bloodlust trigger",
    ["ItemUse.lua"] = "Potion & trinket trigger",
    ["Heartbeat.lua"] = "Heartbeat (repeating triggers)",
    ["Combat.lua"] = "Combat trigger",
    ["Interrupt.lua"] = "Interrupt trigger",
    ["Encounter.lua"] = "Boss trigger",
    ["Summon.lua"] = "Summon trigger",
    ["Mounts.lua"] = "Mount trigger",
    ["Pet.lua"] = "Pet trigger",
    ["Control.lua"] = "Loss of control trigger",
    ["EatBuff.lua"] = "Food buff trigger",
    ["PvP.lua"] = "PvP triggers",
    ["PvPEnemyBuff.lua"] = "PvP enemy buff trigger",
    ["PvPSelfCC.lua"] = "PvP crowd control trigger",
    ["PvPHealerCC.lua"] = "PvP healer CC trigger",
    ["PvPTrinket.lua"] = "PvP trinket trigger",
    ["PvPConsumable.lua"] = "PvP consumable trigger",
    ["General.lua"] = "General triggers",
    ["History.lua"] = "Activity log",
    ["Animations.lua"] = "Animations",
    ["Sounds.lua"] = "Sounds",
    ["Icons.lua"] = "Screen icons",
    ["ActionHub.lua"] = "ActionHub bars",
    ["OxedRing.lua"] = "OxedRing",
    ["ToyBoxData.lua"] = "Toy usage counter",
    ["ToyDock.lua"] = "Toy dock",
    ["ToyBoxUI.lua"] = "Toy box window",
    ["Toys.lua"] = "Toys",
    ["Shattersight.lua"] = "Shattersight (disenchant)",
    ["Tracking.lua"] = "Shattersight (disenchant)",
    ["Prices.lua"] = "Shattersight prices",
    ["PreyEngine.lua"] = "Prey hunt tracker",
    ["PreyHUD.lua"] = "Prey hunt display",
    ["AntiAFKEngine.lua"] = "Anti-AFK",
    ["AntiAFKHUD.lua"] = "Anti-AFK display",
    ["UI.lua"] = "OxedHub window",
    ["MinimapButton.lua"] = "Minimap button",
    ["ModuleAPI.lua"] = "Modules page",
    ["ErrorJournal.lua"] = "Error journal",
    ["KickBar.lua"] = "KickBar",
    ["ChatFilter.lua"] = "Chat Filter",
    ["CopyChat.lua"] = "Copy Chat",
    ["Attributes.lua"] = "Attributes",
    ["AutoVendor.lua"] = "Auto Vendor",
    ["AutoBanker.lua"] = "Auto Banker",
    ["AutoDelete.lua"] = "Auto Confirm",
    ["AutoQuest.lua"] = "Auto Quest",
    ["AutoGossip.lua"] = "Auto Gossip",
    ["MissingGems.lua"] = "Missing Gems",
}

local EVENT_WORDS = {
    UNIT_AURA = "buff or debuff changed",
    UNIT_SPELLCAST_SUCCEEDED = "spell cast",
    UNIT_SPELLCAST_START = "cast started",
    UNIT_SPELLCAST_INTERRUPTED = "cast interrupted",
    SPELL_ACTIVATION_OVERLAY_SHOW = "proc glow shown",
    SPELL_ACTIVATION_OVERLAY_HIDE = "proc glow ended",
    SPELL_UPDATE_USABLE = "spell became usable",
    SPELL_UPDATE_COOLDOWN = "spell cooldowns",
    ACTIONBAR_UPDATE_COOLDOWN = "action bar cooldowns",
    BAG_UPDATE_DELAYED = "bags changed",
    UPDATE_UI_WIDGET = "on-screen widget update",
    UPDATE_ALL_UI_WIDGETS = "all widgets update",
    TOYS_UPDATED = "toy collection update",
    PLAYER_LOGIN = "login",
    PLAYER_ENTERING_WORLD = "loading screen",
    ADDON_LOADED = "addon loaded",
    PLAYER_REGEN_DISABLED = "entered combat",
    PLAYER_REGEN_ENABLED = "left combat",
    PLAYER_TARGET_CHANGED = "target changed",
    NAME_PLATE_UNIT_ADDED = "nameplate appeared",
    NAME_PLATE_UNIT_REMOVED = "nameplate removed",
    GROUP_ROSTER_UPDATE = "group changed",
    MERCHANT_SHOW = "vendor opened",
    BANKFRAME_OPENED = "bank opened",
    GOSSIP_SHOW = "NPC menu opened",
}

-- "Prey hunt tracker -- on-screen widget update  [PreyEngine.lua:900]"
local function Describe(where, what)
    local file = where and where:match("^([%w_]+%.lua)")
    local feature = (file and FEATURES[file]) or (file and file:gsub("%.lua$", "")) or "OxedHub"
    local words = what and (EVENT_WORDS[what] or what) or nil
    local name = words and (feature .. " -- " .. words) or feature
    return where and (name .. "  [" .. where .. "]") or name
end
Profiler.Describe = Describe

-- ── Timers ──────────────────────────────────────────────────────────────────

-- A stand-in for C_Timer that a file takes as its own local:
--   local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer
-- While recording, each callback is named after the line that created it.
-- Nothing global is replaced: other addons, and Blizzard's own code, keep the
-- real C_Timer, so no one else's calls pass through OxedHub.
local proxy
function Profiler:TimerProxy()
    if proxy then return proxy end
    local real = C_Timer
    proxy = setmetatable({}, { __index = real })

    local function Named(fn, kind)
        if not active or type(fn) ~= "function" then return fn end
        return Profiler:Wrap(Describe(CallerLabel(4), kind), fn)
    end

    proxy.After = function(seconds, fn)
        return real.After(seconds, Named(fn, "Timer"))
    end
    proxy.NewTimer = function(seconds, fn)
        return real.NewTimer(seconds, Named(fn, "Timer"))
    end
    proxy.NewTicker = function(seconds, fn, iterations)
        return real.NewTicker(seconds, Named(fn, "Ticker"), iterations)
    end
    return proxy
end

-- ── Script handlers ─────────────────────────────────────────────────────────
-- OnUpdate and OnEvent handlers set by OxedHub code are named after the line
-- that set them, by watching SetScript on the frame types OxedHub uses.
--
-- Only while OxedHub is loading, or while recording. At load, every handler in
-- the addon is set, and naming them then means a later Start already covers
-- them; after load, SetScript calls from other addons are ignored at the cost
-- of one flag check.
--
-- Protected frames are never touched: replacing a secure frame's script from
-- addon code would taint it. OnClick and the rest are left alone too, since
-- some of OxedHub compares GetScript with its own functions for those.

local loading = true
local hooking = false
local wrappedHandlers = setmetatable({}, { __mode = "k" })
local ourFrame  -- the profiler's own frame, never wrapped

local TIMED_SCRIPTS = { OnUpdate = true, OnEvent = true }

local function OnSetScript(frame, script, handler)
    if hooking or not (loading or active) then return end
    if not TIMED_SCRIPTS[script] or type(handler) ~= "function" then return end
    if wrappedHandlers[handler] or frame == ourFrame then return end
    if frame.IsProtected and frame:IsProtected() then return end

    local where = CallerLabel(3)
    if not where then return end   -- not OxedHub's
    -- The report window refreshing itself is not OxedHub's work to report.
    if where:find("^Performance%.lua") then return end

    local timed
    if script == "OnEvent" then
        -- Named per event, with the name built once per event rather than on
        -- every call.
        local names = {}
        timed = Profiler:Wrap(function(_, event)
            local name = names[event]
            if not name then
                name = Describe(where, tostring(event))
                names[event] = name
            end
            return name
        end, handler)
    else
        timed = Profiler:Wrap(Describe(where, "every frame"), handler)
    end
    wrappedHandlers[timed] = true

    hooking = true
    frame:SetScript(script, timed)
    hooking = false
end

-- One throwaway frame per type, only to reach that type's shared method table.
--
-- ⚠ NEVER ADD "EditBox" TO THIS LIST. A new EditBox takes keyboard focus the
-- moment it exists -- auto focus is on by default -- and an invisible one that
-- is never cleared swallows every key: the player could not move, cast or type
-- until OxedHub was switched off. That shipped once. The samples are also
-- hidden straight away, so none of them can ever take the mouse either.
do
    local hooked = {}
    for _, kind in ipairs({ "Frame", "Button", "CheckButton", "ScrollFrame", "StatusBar" }) do
        local ok, sample = pcall(CreateFrame, kind)
        if ok and sample then
            sample:Hide()
            if sample.EnableMouse then sample:EnableMouse(false) end
            if sample.EnableKeyboard then sample:EnableKeyboard(false) end
        end
        local methods = ok and sample and getmetatable(sample) and getmetatable(sample).__index
        if type(methods) == "table" and not hooked[methods] and methods.SetScript then
            hooked[methods] = true
            hooksecurefunc(methods, "SetScript", OnSetScript)
        end
    end
end

-- ── Frames and spikes ───────────────────────────────────────────────────────

-- A frame counts as a spike when it runs well past this machine's own normal,
-- or when OxedHub alone took long enough to matter even inside a normal frame.
local HITCH_FLOOR_MS  = 50     -- never call anything shorter a hitch
local HITCH_RATIO     = 2.5    -- times the rolling normal frame
local HEAVY_OXED_MS   = 8      -- OxedHub's own work in one frame worth recording
local BASELINE_SECS   = 5      -- how quickly "normal" follows the frame rate
local WARMUP_SECS     = 3
local GRACE_SECS      = 5      -- after a loading screen

local baselineMs, warmUntil, graceUntil = 0, 0, 0
local lastMem = 0

local function AddonMs()
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric) then
        return nil
    end
    local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, addonName, Enum.AddOnProfilerMetric.LastTime)
    if ok and type(value) == "number" then return value end
    return nil
end

-- ── Who else was busy ───────────────────────────────────────────────────────
-- The game keeps its own clock on every addon (C_AddOnProfiler). OxedHub's
-- timers only see OxedHub, so a long frame where OxedHub took nothing used to
-- be reported as "OxedHub 0.0 ms" and left there. Asking the game on that
-- frame names whoever did take the time -- another addon, all of them
-- together, or none, which points at the game itself.
--
-- Read on long frames only. Asking for every loaded addon every frame would
-- cost more than most of what it measures.

local addonNames          -- loaded addons, gathered once; reset when one loads
local function LoadedAddons()
    if addonNames then return addonNames end
    addonNames = {}
    if C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetAddOnInfo and C_AddOns.IsAddOnLoaded then
        for i = 1, C_AddOns.GetNumAddOns() do
            local name = C_AddOns.GetAddOnInfo(i)
            if name and C_AddOns.IsAddOnLoaded(i) then addonNames[#addonNames + 1] = name end
        end
    end
    return addonNames
end

local function Metric(name, key)
    local enum = Enum and Enum.AddOnProfilerMetric
    if not (enum and enum[key] and C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric) then return nil end
    local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, name, enum[key])
    if ok and type(value) == "number" then return value end
    return nil
end

-- Every addon's time on the last frame, added up by the game.
local function AllAddonsMs()
    local enum = Enum and Enum.AddOnProfilerMetric
    if not (enum and enum.LastTime and C_AddOnProfiler and C_AddOnProfiler.GetOverallMetric) then return nil end
    local ok, value = pcall(C_AddOnProfiler.GetOverallMetric, enum.LastTime)
    if ok and type(value) == "number" then return value end
    return nil
end

-- The busiest addons on the last frame, most first, OxedHub included.
local function BusiestAddons(limit)
    local top = {}
    for _, name in ipairs(LoadedAddons()) do
        local ms = Metric(name, "LastTime")
        if ms and ms >= 0.5 then
            local pos = #top + 1
            for i = 1, #top do
                if ms > top[i].ms then pos = i break end
            end
            if pos <= limit then
                table.insert(top, pos, { name = name, ms = ms })
                top[limit + 1] = nil
            end
        end
    end
    return top
end

-- What each addon costs on an ordinary frame, averaged by the game over the
-- whole session: the slow, always-on cost rather than the spikes.
function Profiler:AddonAverages(limit)
    local rows = {}
    for _, name in ipairs(LoadedAddons()) do
        local ms = Metric(name, "SessionAverageTime")
        if ms and ms > 0.01 then rows[#rows + 1] = { name = name, ms = ms } end
    end
    table.sort(rows, function(a, b) return a.ms > b.ms end)
    for i = #rows, (limit or 8) + 1, -1 do rows[i] = nil end
    return rows
end

-- ── Which events came in ────────────────────────────────────────────────────
-- A frame that hears every event, while recording only. It writes each name
-- into a flat list and does nothing else; counting happens on a long frame,
-- which is rare. Two lists, swapped each frame, for the same reason as the
-- call buckets: the long frame's events are split across the tick edge.
-- A long frame with no events at all is a finding too -- the work then came
-- from something running every frame or from a timer.

local EVENT_CAP = 256
local evCur, evPrev = { n = 0, over = 0 }, { n = 0, over = 0 }
local eventSpy = CreateFrame("Frame")

local function OnAnyEvent(_, event)
    local list = evCur
    local n = list.n + 1
    if n > EVENT_CAP then
        list.over = list.over + 1
        return
    end
    list.n = n
    list[n] = event
end
-- Set with the SetScript hook held off: the profiler never times itself.
hooking = true
eventSpy:SetScript("OnEvent", OnAnyEvent)
hooking = false

local function TopEvents(limit)
    local counts, order = {}, {}
    for _, list in ipairs({ evPrev, evCur }) do
        for i = 1, list.n do
            local event = list[i]
            if counts[event] then
                counts[event] = counts[event] + 1
            else
                counts[event] = 1
                order[#order + 1] = event
            end
        end
    end
    local top = {}
    for _, event in ipairs(order) do top[#top + 1] = { name = event, n = counts[event] } end
    table.sort(top, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    for i = #top, limit + 1, -1 do top[i] = nil end
    return top, evPrev.over + evCur.over
end

-- ── Why a frame was long ────────────────────────────────────────────────────
-- One word per hitch, so a whole session can be summed up: "900 hitches, 820
-- of them the game, 60 memory cleanup, 20 WeakAuras".

local SHARE = 0.4          -- this much of the frame is enough to take the blame
local BUSY_SCENE = 15      -- nameplates around the player
local AFTER_LOADING = 10   -- seconds after the loading grace ends
local inEncounter = false

local function Nameplates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    return ok and type(plates) == "table" and #plates or nil
end

local function CauseOf(spike, collected, now)
    local frame = spike.frameMs
    if spike.oxedMs >= frame * SHARE then return "OxedHub" end
    local top = spike.others and spike.others[1]
    if top and top.name ~= addonName and top.ms >= frame * SHARE then
        return "addon: " .. top.name
    end
    if spike.allAddonsMs and spike.allAddonsMs >= frame * SHARE then return "several addons together" end
    if now < graceUntil + AFTER_LOADING then return "after a loading screen" end
    if collected then return "Lua memory cleanup" end
    if spike.units and spike.units >= BUSY_SCENE then return "busy scene" end
    if spike.combat then return "game, in combat" end
    return "game"
end

local function TopLevelMs(bucket)
    local sum = 0
    for i = 1, bucket.n do
        if bucket.depth[i] == 0 then sum = sum + (bucket.ms[i] or 0) end
    end
    return sum
end

-- The calls of both buckets, in order. The frame whose length is reported ran
-- across the edge between them -- a frame's events dispatch before the tick
-- that measures the frame before it -- so either could hold the culprit, and
-- showing both is honest where picking one would sometimes be wrong.
local function CopyEntries(target, bucket, limit)
    for i = 1, bucket.n do
        if #target >= limit then return end
        local ms = bucket.ms[i] or 0
        if ms >= 0.05 or bucket.depth[i] == 0 then
            target[#target + 1] = { label = bucket.label[i], ms = ms, depth = bucket.depth[i] }
        end
    end
end

local function RecordSpike(frameMs, reason, alloc, collected)
    -- One piece of work, one record. Heavy OxedHub work is recorded the tick it
    -- happens, and the long frame it causes is measured a tick later -- which
    -- used to write the same calls down twice, once as "22 ms, 102%" and again
    -- as "103 ms". When the previous bucket already has a record, that record is
    -- brought up to date instead: the longer frame, the hitch reason, and
    -- whatever ran since.
    local earlier = prev.spike
    if earlier then
        if frameMs > earlier.frameMs then earlier.frameMs = frameMs end
        if reason == "hitch" then earlier.reason = "hitch" end
        if cur.n > 0 then
            CopyEntries(earlier.entries, cur, 60)
            earlier.oxedMs = earlier.oxedMs + TopLevelMs(cur)
            earlier.overflow = earlier.overflow + cur.over
        end
        earlier.addonMs = AddonMs() or earlier.addonMs
        -- The long frame is the one the game's per-addon clock describes now.
        if reason == "hitch" then
            earlier.others = BusiestAddons(4)
            earlier.allAddonsMs = AllAddonsMs()
            earlier.events, earlier.eventsOver = TopEvents(5)
            earlier.collected = earlier.collected or collected
            local cause = CauseOf(earlier, earlier.collected, GetTime())
            if earlier.cause ~= cause then
                if earlier.counted then
                    session.causes[earlier.cause] = math.max(0, (session.causes[earlier.cause] or 1) - 1)
                end
                session.causes[cause] = (session.causes[cause] or 0) + 1
                earlier.cause, earlier.counted = cause, true
            end
        end
        cur.spike = earlier
        return
    end

    local entries = {}
    CopyEntries(entries, prev, 40)
    CopyEntries(entries, cur, 60)

    local inInstance, instanceType = IsInInstance()
    local spike
    spike = {
        at = time(),
        frameMs = frameMs,
        oxedMs = TopLevelMs(prev) + TopLevelMs(cur),
        addonMs = AddonMs(),
        reason = reason,
        allocKB = alloc,
        combat = InCombatLockdown(),
        where = inInstance and instanceType or "world",
        overflow = prev.over + cur.over,
        entries = entries,
        collected = collected,
        encounter = inEncounter or nil,
    }

    -- Who else was busy, what came in, and so why the frame was long.
    spike.others = BusiestAddons(4)
    spike.allAddonsMs = AllAddonsMs()
    spike.events, spike.eventsOver = TopEvents(5)
    spike.units = Nameplates()
    spike.cause = CauseOf(spike, collected, GetTime())
    if reason == "hitch" then
        session.causes[spike.cause] = (session.causes[spike.cause] or 0) + 1
        spike.counted = true
    end

    spikes[#spikes + 1] = spike
    cur.spike = spike
    if #spikes > SPIKE_LOG then table.remove(spikes, 1) end
end

local function OnFrame(_, elapsed)
    local now = GetTime()
    local frameMs = elapsed * 1000
    session.frames = session.frames + 1

    local mem = collectgarbage("count")
    local alloc = mem - lastMem
    -- Lua memory going down means the collector ran during this frame.
    local collected = mem < lastMem - 64
    lastMem = mem

    -- An error inside a timed call skips its Finish; the frame boundary is
    -- where the nesting count is set straight again.
    depth = 0

    local ready = now >= warmUntil and now >= graceUntil
    local threshold = math.max(HITCH_FLOOR_MS, baselineMs * HITCH_RATIO)
    local hitch = ready and baselineMs > 0 and frameMs >= threshold
    local curMs = TopLevelMs(cur)
    local heavy = curMs >= HEAVY_OXED_MS

    -- The live figures the mini window shows: OxedHub's time over the last
    -- second, and the worst single frame of it.
    live.accum = live.accum + curMs
    if curMs > live.peakAccum then live.peakAccum = curMs end
    if frameMs > live.worstFrameAccum then live.worstFrameAccum = frameMs end
    if now - live.startedAt >= 1 then
        local span = now - live.startedAt
        live.msPerSecond = live.accum / span
        live.peakFrameMs = live.peakAccum
        live.worstFrame = live.worstFrameAccum
        live.accum, live.peakAccum, live.worstFrameAccum, live.startedAt = 0, 0, 0, now
    end

    if hitch or heavy then
        if hitch then session.hitches = session.hitches + 1 end
        RecordSpike(frameMs, hitch and "hitch" or "oxedhub", alloc, collected)
    end

    -- "Normal" is learnt from ordinary frames only, so one spike or a loading
    -- screen does not teach it that long frames are normal.
    if not hitch and now >= graceUntil then
        if baselineMs <= 0 then
            baselineMs = frameMs
        else
            local alpha = math.min(1, elapsed / BASELINE_SECS)
            baselineMs = baselineMs + (frameMs - baselineMs) * alpha
        end
    end

    prev, cur = cur, prev
    cur.n, cur.over, cur.spike = 0, 0, nil
    evPrev, evCur = evCur, evPrev
    evCur.n, evCur.over = 0, 0
end

ourFrame = CreateFrame("Frame")
ourFrame:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" then addonNames = nil end
    if event == "ENCOUNTER_START" then inEncounter = true return end
    if event == "ENCOUNTER_END" then inEncounter = false return end
    if event == "ADDON_LOADED" and loaded == addonName then
        -- Every OxedHub file has run: handlers set from here on belong to
        -- whoever sets them, so the hook only names them while recording.
        loading = false
        OxedHubDB = OxedHubDB or {}
        OxedHubDB.profiler = OxedHubDB.profiler or {}
        if OxedHubDB.profiler.fromLogin then Profiler:Start() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
        graceUntil = GetTime() + GRACE_SECS
    elseif event == "PLAYER_LOGOUT" then
        -- /reload and logging out both land here, and this is the last moment
        -- anything can be written to saved variables. A recording kept only in
        -- memory was lost the moment the player reloaded -- which is exactly
        -- what someone chasing a lag does -- so it is kept now.
        Profiler:SaveSessionToHistory()
    end
end)
ourFrame:RegisterEvent("ADDON_LOADED")
ourFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
ourFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
ourFrame:RegisterEvent("PLAYER_LOGOUT")
ourFrame:RegisterEvent("ENCOUNTER_START")
ourFrame:RegisterEvent("ENCOUNTER_END")

-- ── Methods worth naming ────────────────────────────────────────────────────
-- Instrumented at login, once every module table exists. Names that come from
-- the player's own setup -- a rule's name, a sound's name -- are what make the
-- report readable: "Trigger: CD" rather than a file and a line.

local function NameOf(value)
    if type(value) == "table" then return tostring(value.name or value.id or "?") end
    return tostring(value)
end

local function Instrument()
    local Core, Triggers = OxedHub.Core, OxedHub.Triggers

    if Core then
        Profiler:WrapMethod(Core, "OnEvent", function(_, event) return "Event: " .. tostring(event) end)
        Profiler:WrapMethod(Core, "OnUnitAura", "Core: aura scan")
        Profiler:WrapMethod(Core, "OnSpellCastSucceeded", "Core: cast succeeded")
        Profiler:WrapMethod(Core, "OnSpellCastStart", "Core: cast start")
        Profiler:WrapMethod(Core, "OnCombatLogEvent", "Core: combat log")
        Profiler:WrapMethod(Core, "UpdateCooldowns", "Core: cooldowns")
        Profiler:WrapMethod(Core, "CheckMountState", "Core: mount state")
    end

    if Triggers then
        Profiler:WrapMethod(Triggers, "ProcessEvent", function(_, eventType)
            return "Rules for " .. tostring(eventType)
        end)
        -- Every rule is checked on every event, so these are totals only.
        Profiler:WrapMethod(Triggers, "ShouldTrigger", function(_, trigger)
            return "Rule check: " .. NameOf(trigger)
        end, true)
        Profiler:WrapMethod(Triggers, "ExecuteTrigger", function(_, trigger)
            return "Trigger: " .. NameOf(trigger)
        end)
        Profiler:WrapMethod(Triggers, "CancelTriggerLoops", "Triggers: stop repeats")
    end

    Profiler:WrapMethod(OxedHub.Sounds, "Play", function(_, sound, soundName)
        return "Sound: " .. NameOf(soundName or sound)
    end)
    Profiler:WrapMethod(OxedHub.Animations, "Play", function(_, animation)
        return "Animation: " .. NameOf(animation)
    end)
    Profiler:WrapMethod(OxedHub.Icons, "PlayScreenIcon", function(_, spellID)
        return "Icon: " .. NameOf(spellID)
    end)
    Profiler:WrapMethod(OxedHub.Emotes, "DoEmote", function(_, emote)
        return "Emote: " .. NameOf(emote)
    end)
    Profiler:WrapMethod(OxedHub.ChatMessages, "Send", function(_, template)
        return "Chat: " .. NameOf(template)
    end)
    Profiler:WrapMethod(OxedHub.Toys, "UseToy", function(_, itemID)
        return "Toy: " .. NameOf(itemID)
    end)
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    Instrument()
end)

-- ── Control ─────────────────────────────────────────────────────────────────

function Profiler:IsActive() return active end

function Profiler:Start()
    self.viewIndex = nil   -- recording is always shown live
    if active then return end
    active = true
    self.active = true
    session.startedAt = session.startedAt or time()
    session.stoppedAt = nil
    local now = GetTime()
    warmUntil = now + WARMUP_SECS
    live.accum, live.peakAccum, live.worstFrameAccum, live.startedAt = 0, 0, 0, now
    live.msPerSecond, live.peakFrameMs, live.worstFrame = 0, 0, 0
    lastMem = collectgarbage("count")
    depth = 0
    cur.n, cur.over, prev.n, prev.over = 0, 0, 0, 0
    cur.spike, prev.spike = nil, nil
    ourFrame:SetScript("OnUpdate", OnFrame)
    evCur.n, evCur.over, evPrev.n, evPrev.over = 0, 0, 0, 0
    eventSpy:RegisterAllEvents()
end

function Profiler:Stop()
    if not active then return end
    active = false
    self.active = false
    session.stoppedAt = time()
    ourFrame:SetScript("OnUpdate", nil)
    eventSpy:UnregisterAllEvents()
end

function Profiler:Reset()
    self.viewIndex = nil
    wipe(stats)
    wipe(spikes)
    session.startedAt = active and time() or nil
    session.stoppedAt = nil
    session.frames, session.hitches = 0, 0
    wipe(session.causes)
    baselineMs = 0
end

function Profiler:SetFromLogin(on)
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.profiler = OxedHubDB.profiler or {}
    OxedHubDB.profiler.fromLogin = on and true or false
end

function Profiler:GetFromLogin()
    return OxedHubDB and OxedHubDB.profiler and OxedHubDB.profiler.fromLogin or false
end

-- ── Saved sessions ──────────────────────────────────────────────────────────
-- The last few recordings are kept in saved variables, written as the player
-- reloads or logs out, so a lag can be looked at -- and a report copied -- after
-- the fact. Players chasing a problem reload constantly, and a recording that
-- vanished with every reload was a recording nobody could ever send.
--
-- Only what the report needs is kept: the heaviest totals and the latest spikes,
-- each spike's call list trimmed. A saved session is a few kilobytes.

local HISTORY_KEEP = 10   -- about 15-30 KB each in saved variables, rarely more than 80
local SAVED_TOP = 40
local SAVED_SPIKES = 30
local SAVED_ENTRIES = 25

local function History()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.profiler = OxedHubDB.profiler or {}
    local history = OxedHubDB.profiler.history
    if type(history) ~= "table" then
        history = {}
        OxedHubDB.profiler.history = history
    end
    return history
end

local function LiveTop()
    local list = {}
    for label, s in pairs(stats) do
        list[#list + 1] = {
            label = label, count = s.count, total = s.total, max = s.max,
            avg = s.count > 0 and s.total / s.count or 0, maxAt = s.maxAt,
            alloc = s.alloc or 0, own = s.own or 0,
        }
    end
    return list
end

function Profiler:SaveSessionToHistory()
    if session.frames == 0 and next(stats) == nil then return end

    local top = LiveTop()
    table.sort(top, function(a, b) return a.total > b.total end)
    local keptTop = {}
    for i = 1, math.min(SAVED_TOP, #top) do keptTop[i] = top[i] end

    local keptSpikes = {}
    for i = math.max(1, #spikes - SAVED_SPIKES + 1), #spikes do
        local s = spikes[i]
        local entries = {}
        for j = 1, math.min(SAVED_ENTRIES, #s.entries) do
            local e = s.entries[j]
            entries[j] = { label = e.label, ms = e.ms, depth = e.depth }
        end
        keptSpikes[#keptSpikes + 1] = {
            at = s.at, frameMs = s.frameMs, oxedMs = s.oxedMs, addonMs = s.addonMs,
            reason = s.reason, allocKB = s.allocKB, combat = s.combat, where = s.where,
            overflow = s.overflow, entries = entries,
            cause = s.cause, others = s.others, allAddonsMs = s.allAddonsMs,
            events = s.events, eventsOver = s.eventsOver, units = s.units,
            collected = s.collected, encounter = s.encounter,
        }
    end

    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    local history = History()
    table.insert(history, 1, {
        version = OxedHub.CONFIG and OxedHub.CONFIG.VERSION or "",
        character = (UnitName("player") or "?") .. "-" .. realm,
        startedAt = session.startedAt, endedAt = session.stoppedAt or time(),
        frames = session.frames, hitches = session.hitches, baseline = baselineMs,
        top = keptTop, spikes = keptSpikes,
        causes = CopyTable and CopyTable(session.causes) or session.causes,
        addonAverages = Profiler:AddonAverages(8),
    })
    while #history > HISTORY_KEEP do table.remove(history) end
end

function Profiler:GetHistory() return History() end

function Profiler:DeleteSaved(index)
    local history = History()
    if history[index] then table.remove(history, index) end
    if self.viewIndex and self.viewIndex > #history then self.viewIndex = nil end
end

-- Which recording the window is showing: nil for the live one, or the
-- position of a saved one (1 is the most recent).
function Profiler:SetView(index)
    local history = History()
    self.viewIndex = (index and history[index]) and index or nil
end

function Profiler:GetView()
    return self.viewIndex and History()[self.viewIndex] or nil
end

-- ── Reading the results ─────────────────────────────────────────────────────
-- Everything below answers for whichever recording is being viewed, so the
-- window and the report work the same on a saved session as on the live one.

-- Totals as a list, sorted by "total", "max", "count" or "avg".
function Profiler:GetTop(sortKey)
    local view = self:GetView()
    local list
    if view then
        list = {}
        for i, row in ipairs(view.top or {}) do
            list[i] = {
                label = row.label, count = row.count, total = row.total, max = row.max,
                avg = (row.count or 0) > 0 and row.total / row.count or 0, maxAt = row.maxAt,
                alloc = row.alloc or 0, own = row.own or 0,
            }
        end
    else
        list = LiveTop()
    end
    sortKey = sortKey or "total"
    table.sort(list, function(a, b) return (a[sortKey] or 0) > (b[sortKey] or 0) end)
    return list
end

function Profiler:GetSpikes()
    local view = self:GetView()
    return view and (view.spikes or {}) or spikes
end

function Profiler:GetLive() return live end

function Profiler:GetSession()
    local view = self:GetView()
    if view then
        return { startedAt = view.startedAt, stoppedAt = view.endedAt,
            frames = view.frames or 0, hitches = view.hitches or 0, causes = view.causes or {} }
    end
    return session
end

function Profiler:GetBaseline()
    local view = self:GetView()
    return view and (view.baseline or 0) or baselineMs
end

-- The single slowest top-level call of a spike, for the one-line summary.
function Profiler:SpikeCulprit(spike)
    local best
    for _, entry in ipairs(spike.entries or {}) do
        if entry.depth == 0 and (not best or entry.ms > best.ms) then best = entry end
    end
    -- A call that took no measurable time is not a culprit: naming it next to a
    -- long frame reads as if it caused the frame.
    if best and best.ms < 0.1 then return nil end
    return best
end

local FAMILIES = {
    { "^Event: ", "Triggers engine" },
    { "^Core: ", "Triggers engine" },
    { "^Rules for ", "Triggers engine" },
    { "^Rule check: ", "Triggers engine" },
    { "^Trigger: ", "Triggers engine" },
    { "^Triggers: ", "Triggers engine" },
    { "^Sound: ", "Sounds" },
    { "^Animation: ", "Animations" },
    { "^Icon: ", "Screen icons" },
    { "^Emote: ", "Emotes" },
    { "^Chat: ", "Chat messages" },
    { "^Toy: ", "Toys" },
    { "^ActionHub: ", "ActionHub bars" },
}

local function FeatureOf(label)
    label = tostring(label or "?")
    local head = label:match("^(.-) %-%- ")
    if head then return head end
    for _, family in ipairs(FAMILIES) do
        if label:find(family[1]) then return family[2] end
    end
    return label
end

-- OxedHub's own time by feature, largest first, each with its share. The
-- answer to "what should be fixed first" in one list.
function Profiler:ByFeature(rows)
    local byName, total = {}, 0
    for _, row in ipairs(rows) do
        local own = row.own or 0
        if own > 0 then
            local name = FeatureOf(row.label)
            local entry = byName[name]
            if not entry then
                entry = { name = name, ms = 0, alloc = 0 }
                byName[name] = entry
            end
            entry.ms = entry.ms + own
            entry.alloc = entry.alloc + (row.alloc or 0)
            total = total + own
        end
    end
    local list = {}
    for _, entry in pairs(byName) do list[#list + 1] = entry end
    table.sort(list, function(a, b) return a.ms > b.ms end)
    return list, total
end

-- Everything as plain text, for pasting into a message.
function Profiler:BuildReport()
    local out = {}
    local function add(line) out[#out + 1] = line end

    local view = self:GetView()
    local s = self:GetSession()
    local shownSpikes = self:GetSpikes()
    local length = s.startedAt and ((s.stoppedAt or time()) - s.startedAt) or 0

    add(("OxedHub %s performance report%s"):format(
        view and view.version or (OxedHub.CONFIG and OxedHub.CONFIG.VERSION or ""),
        view and (" (saved session, %s)"):format(view.character or "") or ""))
    add(("Recorded %d s, %d frames, %d hitches, normal frame %.1f ms%s")
        :format(length, s.frames, s.hitches, self:GetBaseline(),
            (not view and active) and " (still recording)" or ""))
    if s.startedAt then
        add(("From %s to %s"):format(date("%Y-%m-%d %H:%M", s.startedAt),
            date("%H:%M", s.stoppedAt or time())))
    end
    add("")

    -- Why the frames were long, summed over the session: the first thing to
    -- read, since it says whether OxedHub, another addon or the game did it.
    local causes = {}
    for cause, n in pairs(s.causes or {}) do
        if n > 0 then causes[#causes + 1] = { cause = cause, n = n } end
    end
    if #causes > 0 then
        table.sort(causes, function(a, b) return a.n > b.n end)
        add("Hitches by cause")
        for _, row in ipairs(causes) do
            add(("  %5d  %s"):format(row.n, row.cause))
        end
        add("")
    end

    -- Every addon's ordinary cost per frame, averaged by the game itself.
    local averages = view and view.addonAverages or (not view and self:AddonAverages(8)) or nil
    if averages and #averages > 0 then
        add("Addons, average per frame this session (the game's own figures)")
        for _, row in ipairs(averages) do
            add(("  %6.2f ms  %s"):format(row.ms, row.name))
        end
        add("")
    end

    -- Where OxedHub's own time went, by feature, with each one's share.
    -- Nested calls are not counted twice, so the shares add up to the whole.
    local features, ownTotal = self:ByFeature(self:GetTop("total"))
    if #features > 0 and ownTotal > 0 then
        local seconds = math.max(1, length)
        add(("OxedHub by feature (%.1f ms a second of its own)"):format(ownTotal / seconds))
        for i, entry in ipairs(features) do
            if i > 12 then break end
            add(("  %5.1f%%  %8.1f ms  %8.0f KB  %s"):format(
                entry.ms / ownTotal * 100, entry.ms, entry.alloc, entry.name))
        end
        add("")
    end

    add("Heaviest in total")
    for i, row in ipairs(self:GetTop("total")) do
        if i > 25 then break end
        add(("  %8.1f ms  %6d calls  avg %6.2f  max %7.2f  %s")
            :format(row.total, row.count, row.avg, row.max, row.label))
    end
    add("")

    -- Garbage: what the collector must clear later, in one pause.
    local garbage = self:GetTop("alloc")
    if garbage[1] and (garbage[1].alloc or 0) >= 1 then
        add("Most Lua memory made (feeds the garbage collector)")
        for i, row in ipairs(garbage) do
            if i > 10 or (row.alloc or 0) < 1 then break end
            add(("  %9.0f KB  %6d calls  %6.2f KB each  %s")
                :format(row.alloc, row.count, row.count > 0 and row.alloc / row.count or 0, row.label))
        end
        add("")
    end

    add("Slowest single calls")
    for i, row in ipairs(self:GetTop("max")) do
        if i > 15 then break end
        add(("  %7.2f ms  %s"):format(row.max, row.label))
    end
    add("")

    add("Latest spikes")
    local first = math.max(1, #shownSpikes - 14)
    for i = #shownSpikes, first, -1 do
        local spike = shownSpikes[i]
        local share = spike.frameMs > 0 and (spike.oxedMs / spike.frameMs * 100) or 0
        add(("%s  frame %.0f ms  OxedHub %.1f ms (%.0f%%)%s  %s%s")
            :format(date("%H:%M:%S", spike.at), spike.frameMs, spike.oxedMs, share,
                spike.addonMs and (" game says %.1f ms"):format(spike.addonMs) or "",
                spike.where or "", spike.combat and ", in combat" or ""))
        if spike.cause then
            local extras = {}
            if spike.collected then extras[#extras + 1] = "memory cleanup ran" end
            if spike.units then extras[#extras + 1] = spike.units .. " nameplates" end
            if spike.encounter then extras[#extras + 1] = "boss fight" end
            add(("    cause: %s%s"):format(spike.cause,
                #extras > 0 and ("  (" .. table.concat(extras, ", ") .. ")") or ""))
        end
        if spike.others and #spike.others > 0 then
            local parts = {}
            for _, other in ipairs(spike.others) do
                parts[#parts + 1] = ("%s %.1f"):format(other.name, other.ms)
            end
            add(("    addons: %s ms%s"):format(table.concat(parts, ", "),
                spike.allAddonsMs and ("  (all addons %.1f ms)"):format(spike.allAddonsMs) or ""))
        end
        if spike.events then
            if #spike.events == 0 then
                add("    events: none (the work came from a timer or an every-frame script)")
            else
                local parts = {}
                for _, event in ipairs(spike.events) do
                    parts[#parts + 1] = event.n > 1 and ("%s x%d"):format(event.name, event.n) or event.name
                end
                add(("    events: %s%s"):format(table.concat(parts, ", "),
                    (spike.eventsOver or 0) > 0 and (" and %d more"):format(spike.eventsOver) or ""))
            end
        end
        for _, entry in ipairs(spike.entries or {}) do
            if entry.ms >= 0.1 then
                add(("    %s%.2f ms  %s"):format(string.rep("  ", entry.depth), entry.ms, entry.label))
            end
        end
    end
    return table.concat(out, "\n")
end
