local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers

-- ── Trigger history ──────────────────────────────────────────────────────────
-- What actually fired today, and how often.
--
-- Until now a rule that never went off was indistinguishable from one that went
-- off constantly: both just sat in the list looking configured. This records
-- each firing so the question can be answered without staring at the screen and
-- waiting.
--
-- Deliberately small on disk. We just spent a session cutting the saved
-- variables file by three quarters, and a naive log would put it all back:
--
--   * only today is kept -- yesterday's counts answer nothing useful and the
--     day rolls over on its own
--   * only the last MAX_ENTRIES times per rule are stored, so a rule that fires
--     hundreds of times costs the same as one that fires twenty
--   * the count is a number, not the length of a list, so it stays honest even
--     once the times have been trimmed
--
-- It lives account-wide rather than in the profile: profiles serialise
-- separately, and a per-profile copy would be written out once per profile.

local MAX_ENTRIES = 40

local function Today()
    return date("%Y-%m-%d")
end

local function Store()
    if type(OxedHubDB) ~= "table" then return nil end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}

    local store = OxedHubDB.globalSettings.triggerHistory
    if type(store) ~= "table" then
        store = { day = Today(), rules = {} }
        OxedHubDB.globalSettings.triggerHistory = store
    end

    -- A new day wipes the lot rather than accumulating: "today" is the whole
    -- promise this makes, and keeping more would only grow the file.
    if store.day ~= Today() then
        store.day = Today()
        store.rules = {}
    end
    store.rules = store.rules or {}
    return store
end

-- Record one firing. Called from ExecuteTrigger, after its debounce, so a
-- double-fire suppressed there is not counted here either.
function Triggers:RecordTriggerFired(trigger, eventData)
    if not trigger or not trigger.id then return end
    local store = Store()
    if not store then return end

    local entry = store.rules[trigger.id]
    if type(entry) ~= "table" then
        entry = { count = 0, times = {} }
        store.rules[trigger.id] = entry
    end

    entry.count = (entry.count or 0) + 1
    entry.last = time()

    -- A detail worth keeping alongside the time: with several spells on one
    -- rule, "it fired six times" is much less useful than which ones.
    local label
    local spellID = eventData and eventData.spellID
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info and info.name then label = info.name end
    end
    if not label and eventData and eventData.spellName then label = eventData.spellName end

    table.insert(entry.times, { t = entry.last, what = label })
    while #entry.times > MAX_ENTRIES do
        table.remove(entry.times, 1)
    end
end

function Triggers:GetTriggerHistory(triggerId)
    local store = Store()
    if not store or not triggerId then return nil end
    return store.rules[triggerId]
end

-- Clear one rule's history, or every rule's when given no id.
function Triggers:ClearTriggerHistory(triggerId)
    local store = Store()
    if not store then return end
    if triggerId then
        store.rules[triggerId] = nil
    else
        store.rules = {}
    end
    if self.RefreshTriggersList then self:RefreshTriggersList() end
end

-- Every firing from every rule today, newest first, plus the totals.
--
-- Split out from any one view because two of them need it: the log page inside
-- the Triggers tab, and anything else that wants the same numbers later.
-- Pass a trigger id to narrow it to that one rule.
function Triggers:CollectActivityLog(onlyId)
    local store = Store()
    local triggers = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers or {}

    local events, ruleCount, total, trimmed = {}, 0, 0, 0
    for id, entry in pairs((store and store.rules) or {}) do
        if not onlyId or id == onlyId then
            local trigger = triggers[id]
            local name = (trigger and trigger.name) or id
            ruleCount = ruleCount + 1
            total = total + (entry.count or 0)
            trimmed = trimmed + math.max(0, (entry.count or 0) - #(entry.times or {}))
            for _, row in ipairs(entry.times or {}) do
                events[#events + 1] = { t = row.t or 0, what = row.what, name = name }
            end
        end
    end
    -- Newest first, so the order on screen is the order things happened.
    table.sort(events, function(a, b) return a.t > b.t end)

    return events, ruleCount, total, trimmed
end

-- Open the log as a page of the Triggers tab, not as a window of its own.
--
-- One page serves both the whole day and a single rule. A separate floating
-- window for either was the wrong shape: this is part of the addon, so it
-- belongs inside the addon's frame, behind the same Back to List as everything
-- else in this tab.
function Triggers:ShowActivityLog(onlyId)
    self.selectedTriggerId = nil
    self.showActivityLog = true
    self.activityLogFilter = onlyId

    if OxedHub.UI and OxedHub.UI.ShowTab then
        OxedHub.UI:ShowTab("Triggers")
    end
    self:RefreshTriggersList()
end

function Triggers:ShowTriggerHistory(triggerId)
    self:ShowActivityLog(triggerId)
end

