local addonName, OxedHub = ...

-- ── Error journal ────────────────────────────────────────────────────────────
-- Collects only OxedHub's own failures and, crucially, records WHAT the addon
-- was doing when they happened: which trigger, which event, which action.
--
-- A stack trace alone is not enough to act on. "SelfAura.lua:353" tells you the
-- line but not which of the user's fifty triggers was being registered, so the
-- journal keeps a shallow context stack that the execution paths push into.
--
-- Deliberately cooperative: the previous error handler is called at the end, so
-- BugGrabber, BugSack or Blizzard's own frame keep working exactly as before.
-- Nothing here unregisters or replaces another addon's reporting.

local Journal = {}
OxedHub.ErrorJournal = Journal

-- Enough history to cover a play session without letting a repeating error eat
-- the saved variables file. Repeats collapse into one entry, so this is a count
-- of distinct problems, not of occurrences.
local MAX_ENTRIES = 120
local MAX_MESSAGE = 400

-- ── Context ──────────────────────────────────────────────────────────────────
-- Set before running user-configured work and cleared after. If an error fires
-- in between, the handler reads this and knows the culprit by name.
--
-- Note there is intentionally no pcall around the wrapped calls: catching the
-- error would stop it reaching the real error handler and BugGrabber would go
-- blind. Instead the handler clears the context itself once it has read it,
-- which also guarantees a failed call can never leave a stale context behind to
-- mislabel the next error.
local activeContext = nil

-- area is the feature the user recognises ("Triggers", "OxedRing", "ActionHub",
-- "Toys"); name is the specific thing inside it; detail is optional extra.
function Journal:SetContext(area, name, detail)
    activeContext = { area = area, name = name, detail = detail }
end

function Journal:ClearContext()
    activeContext = nil
end

-- Runs fn with a context attached, clearing it on the way out.
function Journal:Run(context, fn, ...)
    activeContext = context
    local a, b, c, d = fn(...)
    activeContext = nil
    return a, b, c, d
end

local function DescribeContext(ctx)
    if not ctx then return nil end
    local label = ctx.name or "?"
    if ctx.detail and ctx.detail ~= "" then
        return ("%s (%s)"):format(label, ctx.detail)
    end
    return label
end

-- ── Storage ──────────────────────────────────────────────────────────────────

local function Store()
    if type(OxedHubDB) ~= "table" then return nil end
    OxedHubDB.errorJournal = OxedHubDB.errorJournal or {}
    return OxedHubDB.errorJournal
end

-- 12.0 makes some values secret, and debugstack is one of the calls that can
-- hand one back. Touching it then throws from inside the error handler, which
-- would turn one reported error into an unreportable loop.
local function SafeString(value, fallback)
    if value == nil then return fallback end
    if issecretvalue and issecretvalue(value) then return fallback end
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= "string" then return fallback end
    return text
end

local function Trim(text)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > MAX_MESSAGE then
        text = text:sub(1, MAX_MESSAGE) .. "..."
    end
    return text
end

-- Decides what counts as "the same problem". Two entries merge only when the
-- kind, the text, the place in the code and the trigger all match, so a repeat
-- becomes a counter while anything genuinely different gets its own row.
--
-- The source has to be part of this. A blocked call always carries the same
-- text ("Protected call blocked: UNKNOWN()"), so without the file and line two
-- unrelated blocked calls would collapse into one row and hide each other.
--
-- Volatile parts are stripped first: the leading repeat counter the client adds
-- and any table addresses, which differ on every occurrence of one same fault.
local function Signature(kind, message, source, ctx)
    local base = message:gsub("%d+x ", ""):gsub("0x%x+", "")
    return ("%s|%s|%s|%s"):format(kind, base, source or "-", DescribeContext(ctx) or "-")
end

-- Pulls "Modules/Triggers/SelfAura.lua:353" out of a message or stack, which is
-- the one part of a trace worth showing in a compact list.
local function ExtractSource(text)
    local file, line = text:match("([%w_/\\%.%-]+%.lua):(%d+)")
    if not file then return nil end
    file = file:gsub("^.*[/\\]OxedHub[/\\]", ""):gsub("\\", "/")
    return ("%s:%s"):format(file, line)
end

-- Fallback labelling. An explicit context names the exact trigger or node, but
-- most of the addon is not worth instrumenting by hand, so the file path is used
-- to at least say which feature failed. That covers Toys, the ToyBox, the UI and
-- everything else for free.
local AREA_BY_PATH = {
    { "Modules/Rings/",    "OxedRing"   },
    { "Modules/Toys/",     "Toys"       },
    { "Modules/Toys.lua",  "Toys"       },
    { "Modules/ActionHub", "ActionHub"  },
    { "Modules/Triggers",  "Triggers"   },
    { "Modules/Prey/",     "Prey"       },
    { "Modules/AntiAFK/",  "Anti-AFK"   },
    { "Modules/ProfileShare", "Sharing" },
    { "UI/",               "Interface"  },
    { "Core/",             "Core"       },
}

local function AreaFromSource(source)
    if not source then return nil end
    for _, pair in ipairs(AREA_BY_PATH) do
        if source:find(pair[1], 1, true) then return pair[2] end
    end
    return nil
end

function Journal:Record(kind, rawMessage, rawStack)
    local db = Store()
    if not db then return end

    local message = Trim(SafeString(rawMessage, "unreadable error"))
    local stack = SafeString(rawStack, "")
    local ctx = activeContext

    local source = ExtractSource(message) or ExtractSource(stack)
    local key = Signature(kind, message, source, ctx)
    local entry = db[key]

    if entry then
        entry.count = (entry.count or 1) + 1
        entry.lastSeen = time()
    else
        db[key] = {
            kind = kind,
            message = message,
            source = source,
            context = DescribeContext(ctx),
            area = (ctx and ctx.area) or AreaFromSource(source),
            stack = Trim(stack),
            count = 1,
            firstSeen = time(),
            lastSeen = time(),
        }
        Journal:Prune(db)
    end
end

-- Drops the oldest entries once the cap is passed. Counts on existing entries
-- keep rising regardless, so a long session never silently loses the fact that
-- something is still failing.
function Journal:Prune(db)
    local keys = {}
    for key in pairs(db) do keys[#keys + 1] = key end
    if #keys <= MAX_ENTRIES then return end
    table.sort(keys, function(a, b)
        return (db[a].lastSeen or 0) < (db[b].lastSeen or 0)
    end)
    for i = 1, #keys - MAX_ENTRIES do
        db[keys[i]] = nil
    end
end

-- Newest first, which is what you want when checking whether the thing you just
-- did broke anything.
function Journal:GetEntries()
    local db = Store()
    local list = {}
    if not db then return list end
    for _, entry in pairs(db) do list[#list + 1] = entry end
    table.sort(list, function(a, b)
        return (a.lastSeen or 0) > (b.lastSeen or 0)
    end)
    return list
end

function Journal:Clear()
    if type(OxedHubDB) == "table" then
        OxedHubDB.errorJournal = {}
    end
end

function Journal:GetSummary()
    local entries = Journal:GetEntries()
    local occurrences = 0
    for _, e in ipairs(entries) do occurrences = occurrences + (e.count or 1) end
    return #entries, occurrences
end

-- When the Debug page was last looked at. Anything newer is marked as new, so
-- a problem that appeared since the last visit is not lost among the ones
-- already read.
function Journal:GetLastViewed()
    local db = Store()
    return (db and db.debugLastViewed) or 0
end

function Journal:MarkViewed()
    local db = Store()
    if db then db.debugLastViewed = time() end
end

-- One entry as plain text. Shared by the per-row Copy button and the full
-- report, so both read identically.
function Journal:FormatEntry(entry, index)
    local lines = {}
    local prefix = index and ("%d. "):format(index) or ""

    lines[#lines + 1] = ("%s[%s x%d] %s"):format(
        prefix, entry.kind or "?", entry.count or 1, entry.message or "")
    lines[#lines + 1] = ("   Feature: %s"):format(entry.area or "unknown")
    if entry.context then lines[#lines + 1] = ("   Where: %s"):format(entry.context) end
    if entry.source then lines[#lines + 1] = ("   Source: %s"):format(entry.source) end
    lines[#lines + 1] = ("   First seen: %s"):format(date("%d.%m.%y %H:%M:%S", entry.firstSeen or time()))
    lines[#lines + 1] = ("   Last seen:  %s"):format(date("%d.%m.%y %H:%M:%S", entry.lastSeen or time()))
    if entry.stack and entry.stack ~= "" then
        lines[#lines + 1] = "   Stack:"
        lines[#lines + 1] = "   " .. entry.stack:gsub("\n", "\n   ")
    end
    return table.concat(lines, "\n")
end

-- Plain text, built for pasting into a bug report.
function Journal:BuildReport()
    local entries = Journal:GetEntries()
    if #entries == 0 then return "No issues recorded." end

    local version = (OxedHub.CONFIG and OxedHub.CONFIG.VERSION) or "?"
    local lines = {
        ("OxedHub %s - %d issue(s)"):format(version, #entries),
        "",
    }
    for i, e in ipairs(entries) do
        lines[#lines + 1] = self:FormatEntry(e, i)
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

-- ── Capture ──────────────────────────────────────────────────────────────────

-- Other addons' errors are none of our business, and recording them would bury
-- the ones that matter. An error counts as ours if it points at our files or if
-- it happened while our own code was running.
local function IsOurs(message, stack)
    if activeContext then return true end
    if message:find("OxedHub", 1, true) then return true end
    if stack and stack:find("OxedHub", 1, true) then return true end
    return false
end

local previousHandler

local function InstallErrorHandler()
    previousHandler = geterrorhandler()
    seterrorhandler(function(err)
        local message = SafeString(err, "unreadable error")
        local stack = ""
        if debugstack then
            local ok, trace = pcall(debugstack, 2)
            if ok then stack = SafeString(trace, "") end
        end

        if IsOurs(message, stack) then
            local ok = pcall(Journal.Record, Journal, "Lua", message, stack)
            if not ok then
                -- Never let the journal itself break error reporting.
                activeContext = nil
            end
        end

        activeContext = nil

        if previousHandler then
            return previousHandler(err)
        end
    end)
end

-- ADDON_ACTION_BLOCKED is an event, not a Lua error, so seterrorhandler never
-- sees it. It has to be listened for separately. Registering our own frame is
-- independent of what any error display does with Blizzard's frames.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_ACTION_BLOCKED")
watcher:RegisterEvent("ADDON_ACTION_FORBIDDEN")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(_, event, blockedAddon, blockedFunc)
    if event == "PLAYER_LOGIN" then
        Journal:HookBugGrabber()
        -- Wrapping happens here rather than at load so this file can sit early
        -- in the TOC without depending on the trigger files being parsed yet.
        Journal:InstrumentTriggers()
        return
    end

    if blockedAddon ~= addonName then return end

    local stack = ""
    if debugstack then
        local ok, trace = pcall(debugstack, 2)
        if ok then stack = SafeString(trace, "") end
    end

    -- Guarded for the same reason as the error handler: a fault while recording
    -- a blocked call must not itself raise, or one blocked call becomes a loop.
    local func = SafeString(blockedFunc, "unknown function")
    pcall(Journal.Record, Journal, "Blocked", ("Protected call blocked: %s"):format(func), stack)
end)

-- Installed at load, not at login: a failure while the addon is still setting
-- itself up is exactly the kind that is hardest to reproduce later.
InstallErrorHandler()

-- BugGrabber ends its setup with
--
--     function seterrorhandler() end
--
-- replacing the global with a no-op so nothing can take the handler off it
-- afterwards. Every addon loading later, this one included, then calls a
-- function that does nothing, which is why the Debug tab stayed empty while
-- BugSack was showing the very same error.
--
-- It does publish what it catches, so subscribe to that instead. Nothing is
-- recorded twice: where this works, our own handler was never installed.
function Journal:HookBugGrabber()
    local grabber = _G.BugGrabber
    if not grabber or not grabber.GetErrorByID then return false end
    if not EventRegistry or not EventRegistry.RegisterCallback then return false end
    if self._bugGrabberHooked then return true end

    EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
        local ok, err = pcall(grabber.GetErrorByID, grabber, tableID)
        if not ok or type(err) ~= "table" then return end

        local message = SafeString(err.message, "")
        local stack = SafeString(err.stack, "")

        if IsOurs(message, stack) then
            pcall(Journal.Record, Journal, "Lua", message, stack)
        end
        activeContext = nil
    end, self)

    self._bugGrabberHooked = true
    return true
end

-- ── Instrumentation ──────────────────────────────────────────────────────────

function Journal:InstrumentTriggers()
    local Triggers = OxedHub.Triggers
    if not Triggers or Triggers._journalInstrumented then return end
    Triggers._journalInstrumented = true

    local original = Triggers.ExecuteTrigger
    if type(original) ~= "function" then return end

    Triggers.ExecuteTrigger = function(self, trigger, eventData, skipChat)
        local context
        if type(trigger) == "table" then
            context = {
                area = "Triggers",
                name = trigger.name or trigger.id or "unnamed trigger",
                detail = trigger.event,
            }
        end
        return Journal:Run(context, original, self, trigger, eventData, skipChat)
    end
end
