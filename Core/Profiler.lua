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

local session = { startedAt = nil, stoppedAt = nil, frames = 0, hitches = 0 }

-- Rolling one-second figures for the mini window.
local live = {
    msPerSecond = 0, peakFrameMs = 0, worstFrame = 0,
    accum = 0, peakAccum = 0, worstFrameAccum = 0, startedAt = 0,
}

-- ── Recording ───────────────────────────────────────────────────────────────

local function Record(label, ms)
    local s = stats[label]
    if not s then
        s = { count = 0, total = 0, max = 0 }
        stats[label] = s
    end
    s.count = s.count + 1
    s.total = s.total + ms
    if ms > s.max then
        s.max = ms
        s.maxAt = time()
    end
end

-- Closes a timed call. Takes the call's own return values through untouched,
-- so a wrapped function returns exactly what it always did.
local function Finish(label, bucket, slot, start, ...)
    local ms = debugprofilestop() - start
    depth = depth - 1
    if depth < 0 then depth = 0 end
    Record(label, ms)
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
        local start = debugprofilestop()
        return Finish(name, bucket, slot, start, fn(...))
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

local function RecordSpike(frameMs, reason, alloc)
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
    }
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
        RecordSpike(frameMs, hitch and "hitch" or "oxedhub", alloc)
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
end

ourFrame = CreateFrame("Frame")
ourFrame:SetScript("OnEvent", function(_, event, loaded)
    if event == "ADDON_LOADED" and loaded == addonName then
        -- Every OxedHub file has run: handlers set from here on belong to
        -- whoever sets them, so the hook only names them while recording.
        loading = false
        OxedHubDB = OxedHubDB or {}
        OxedHubDB.profiler = OxedHubDB.profiler or {}
        if OxedHubDB.profiler.fromLogin then Profiler:Start() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "LOADING_SCREEN_DISABLED" then
        graceUntil = GetTime() + GRACE_SECS
    end
end)
ourFrame:RegisterEvent("ADDON_LOADED")
ourFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
ourFrame:RegisterEvent("LOADING_SCREEN_DISABLED")

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
end

function Profiler:Stop()
    if not active then return end
    active = false
    self.active = false
    session.stoppedAt = time()
    ourFrame:SetScript("OnUpdate", nil)
end

function Profiler:Reset()
    wipe(stats)
    wipe(spikes)
    session.startedAt = active and time() or nil
    session.stoppedAt = nil
    session.frames, session.hitches = 0, 0
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

-- ── Reading the results ─────────────────────────────────────────────────────

-- Totals as a list, sorted by "total", "max", "count" or "avg".
function Profiler:GetTop(sortKey)
    local list = {}
    for label, s in pairs(stats) do
        list[#list + 1] = {
            label = label, count = s.count, total = s.total, max = s.max,
            avg = s.count > 0 and s.total / s.count or 0, maxAt = s.maxAt,
        }
    end
    sortKey = sortKey or "total"
    table.sort(list, function(a, b) return (a[sortKey] or 0) > (b[sortKey] or 0) end)
    return list
end

function Profiler:GetSpikes() return spikes end
function Profiler:GetLive() return live end
function Profiler:GetSession() return session end
function Profiler:GetBaseline() return baselineMs end

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

-- Everything as plain text, for pasting into a message.
function Profiler:BuildReport()
    local out = {}
    local function add(line) out[#out + 1] = line end

    local s = session
    local length = s.startedAt and ((s.stoppedAt or time()) - s.startedAt) or 0
    add(("OxedHub %s performance report"):format(OxedHub.CONFIG and OxedHub.CONFIG.VERSION or ""))
    add(("Recorded %d s, %d frames, %d hitches, normal frame %.1f ms%s")
        :format(length, s.frames, s.hitches, baselineMs, active and " (still recording)" or ""))
    add("")

    add("Heaviest in total")
    for i, row in ipairs(self:GetTop("total")) do
        if i > 25 then break end
        add(("  %8.1f ms  %6d calls  avg %6.2f  max %7.2f  %s")
            :format(row.total, row.count, row.avg, row.max, row.label))
    end
    add("")

    add("Slowest single calls")
    for i, row in ipairs(self:GetTop("max")) do
        if i > 15 then break end
        add(("  %7.2f ms  %s"):format(row.max, row.label))
    end
    add("")

    add("Latest spikes")
    local first = math.max(1, #spikes - 14)
    for i = #spikes, first, -1 do
        local spike = spikes[i]
        local share = spike.frameMs > 0 and (spike.oxedMs / spike.frameMs * 100) or 0
        add(("%s  frame %.0f ms  OxedHub %.1f ms (%.0f%%)%s  %s%s")
            :format(date("%H:%M:%S", spike.at), spike.frameMs, spike.oxedMs, share,
                spike.addonMs and (" game says %.1f ms"):format(spike.addonMs) or "",
                spike.where, spike.combat and ", in combat" or ""))
        for _, entry in ipairs(spike.entries) do
            if entry.ms >= 0.1 then
                add(("    %s%.2f ms  %s"):format(string.rep("  ", entry.depth), entry.ms, entry.label))
            end
        end
    end
    return table.concat(out, "\n")
end
