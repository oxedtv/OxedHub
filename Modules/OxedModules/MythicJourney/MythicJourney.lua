-- ============================================================================
-- Mythic Journey (built-in OxedHub module)
-- A character's Mythic+ season as a story: every key finished, the rating it
-- reached and when, the best timed key per dungeon, and the milestones along
-- the way (first +10 timed, first 2500, every dungeon timed at +12...).
--
-- Where the data comes from:
--   * Each key finished from now on, read from the game's completion info
--     (dungeon, level, time, in time or not, upgrades, rating before/after).
--   * Runs from before the module was on, once per season, from the game's
--     run history. Those have no date and no time; they are listed as
--     "earlier this season" and never counted twice.
--
-- ⚠ Nothing here is guessed. A run is only written when the game said it
--   finished; the rating is the game's own overall score.
-- ⚠ Journey data is a table per character and season, built after binding,
--   never in DEFAULTS (a table there would be shared by every character).
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local PREFIX = "|cffa335eeOxedHub Mythic Journey:|r "

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    announce      = true,   -- a line in chat after each key, with the rating change
    milestoneChat = true,   -- and one for each milestone reached
    milestoneSound = "None",
    minimapButton = true,
    recentRuns    = 25,     -- how many runs the list shows
    point = "CENTER", x = 0, y = 40,
}

local settings
local running = false
local window, optionsWindow
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local events = CreateFrame("Frame")

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

local function Num(v)
    v = Plain(v)
    return type(v) == "number" and v or nil
end

local function CharKey()
    local name, realm = Plain(UnitName("player")), Plain(GetRealmName())
    if type(name) ~= "string" or type(realm) ~= "string" then return nil end
    return name .. "-" .. realm
end

local function Season()
    local s = C_MythicPlus and C_MythicPlus.GetCurrentSeason and Num(C_MythicPlus.GetCurrentSeason())
    if s and s > 0 then return s end
    return nil
end

local function OverallScore()
    if not (C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore) then return nil end
    local ok, score = pcall(C_ChallengeMode.GetOverallDungeonScore)
    return ok and Num(score) or nil
end

local mapCache = {}
local function MapInfo(mapID)
    if not mapID then return "?", nil, nil end
    local c = mapCache[mapID]
    if not c then
        local ok, name, _, timeLimit, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        c = { name = ok and Plain(name) or ("Dungeon " .. mapID), limit = ok and Num(timeLimit) or nil,
              icon = ok and Plain(texture) or nil }
        mapCache[mapID] = c
    end
    return c.name, c.limit, c.icon
end

local function Clock(sec)
    if type(sec) ~= "number" then return "" end
    sec = math.floor(sec + 0.5)
    return ("%d:%02d"):format(sec / 60, sec % 60)
end

local function DateText(t)
    if type(t) ~= "number" then return L["earlier this season"] end
    return date("%d %b", t)
end

-- Colours for a rating, like the game's own (falls back to plain white).
local function ScoreColour(score)
    if C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and score then
        local ok, c = pcall(C_ChallengeMode.GetDungeonScoreRarityColor, score)
        if ok and c and c.GenerateHexColor then return "|c" .. c:GenerateHexColor() end
    end
    return "|cffffffff"
end

-- ── The journey: per character, per season ──────────────────────────────────
-- settings.journeys[charKey][season] = {
--   runs   = { { t, map, level, timed, upgrades, secs, before, after, imported } },
--   rating = { { t, score } },
--   imported = true once the game's run history was read,
--   seen   = { [milestoneId] = t },
-- }

local function Journey()
    local key, season = CharKey(), Season()
    if not (key and season) then return nil end
    settings.journeys = settings.journeys or {}
    local char = settings.journeys[key]
    if type(char) ~= "table" then
        char = {}
        settings.journeys[key] = char
    end
    local j = char[season]
    if type(j) ~= "table" then
        j = { runs = {}, rating = {}, seen = {} }
        char[season] = j
    end
    j.runs, j.rating, j.seen = j.runs or {}, j.rating or {}, j.seen or {}
    return j, season
end

local function NoteRating(j, score, t)
    if not score then return end
    local last = j.rating[#j.rating]
    if last and last[2] == score then return end
    j.rating[#j.rating + 1] = { t or time(), score }
end

-- Runs from before the module was switched on: once per season, no dates.
local function ImportHistory(j)
    if j.imported or not (C_MythicPlus and C_MythicPlus.GetRunHistory) then return end
    local ok, history = pcall(C_MythicPlus.GetRunHistory, true, true)
    if not ok or type(history) ~= "table" then return end
    -- Live runs already written this season stand for themselves; only the
    -- surplus the history knows about is older than the module.
    local liveByKey = {}
    for _, r in ipairs(j.runs) do
        if not r.imported then
            local k = r.map .. ":" .. r.level .. ":" .. tostring(r.timed)
            liveByKey[k] = (liveByKey[k] or 0) + 1
        end
    end
    local older = {}
    for _, h in ipairs(history) do
        local map, level = Num(h.mapChallengeModeID), Num(h.level)
        local completed = Plain(h.completed)
        if map and level then
            local timed = completed == true
            local k = map .. ":" .. level .. ":" .. tostring(timed)
            if (liveByKey[k] or 0) > 0 then
                liveByKey[k] = liveByKey[k] - 1
            else
                older[#older + 1] = { map = map, level = level, timed = timed, imported = true }
            end
        end
    end
    -- Older runs go first, in the order the game lists them.
    local merged = {}
    for _, r in ipairs(older) do merged[#merged + 1] = r end
    for _, r in ipairs(j.runs) do merged[#merged + 1] = r end
    j.runs = merged
    j.imported = true
end

-- ── Milestones: worked out from the runs, the first time each one is met ────

local LEVELS = { 2, 5, 7, 10, 12, 15, 18, 20 }
local SCORES = { 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000 }

local function DungeonList()
    local ok, maps = pcall(C_ChallengeMode.GetMapTable)
    if ok and type(maps) == "table" then return maps end
    return {}
end

-- id -> text, for everything reached so far; the time it was first seen is
-- kept in j.seen so the list keeps its order and chat says it once.
local function Milestones(j)
    local found = {}
    local timedAt = {}       -- [map] = best timed level
    for _, r in ipairs(j.runs) do
        if r.timed then
            for _, lv in ipairs(LEVELS) do
                if r.level >= lv then found["key" .. lv] = (L["First +%d in time"]):format(lv) end
            end
            if (timedAt[r.map] or 0) < r.level then timedAt[r.map] = r.level end
        end
    end
    local maps = DungeonList()
    if #maps > 0 then
        for _, lv in ipairs(LEVELS) do
            local all = true
            for _, m in ipairs(maps) do
                if (timedAt[m] or 0) < lv then all = false break end
            end
            if all then found["all" .. lv] = (L["Every dungeon in time at +%d"]):format(lv) end
        end
    end
    local best = 0
    for _, p in ipairs(j.rating) do if p[2] > best then best = p[2] end end
    for _, s in ipairs(SCORES) do
        if best >= s then found["score" .. s] = (L["Rating %d reached"]):format(s) end
    end
    if #j.runs >= 1 then found.runs1 = L["First key of the season"] end
    for _, n in ipairs({ 25, 50, 100, 200, 500 }) do
        if #j.runs >= n then found["runs" .. n] = (L["%d keys finished"]):format(n) end
    end
    return found
end

-- Marks new milestones as seen now; returns the texts of the new ones.
local function NewMilestones(j, quiet)
    local fresh = {}
    for id, text in pairs(Milestones(j)) do
        if not j.seen[id] then
            j.seen[id] = quiet and true or time()
            if not quiet then fresh[#fresh + 1] = text end
        end
    end
    return fresh
end

-- ── Recording a key ─────────────────────────────────────────────────────────

local Refresh   -- the window; defined below

local function CompletionInfo()
    local C = C_ChallengeMode
    if C and C.GetChallengeCompletionInfo then
        local ok, info = pcall(C.GetChallengeCompletionInfo)
        if ok and type(info) == "table" then
            return Num(info.mapChallengeModeID), Num(info.level), Num(info.time), Plain(info.onTime),
                Num(info.keystoneUpgradeLevels), Num(info.oldOverallDungeonScore), Num(info.newOverallDungeonScore),
                Plain(info.practiceRun)
        end
    end
    if C and C.GetCompletionInfo then
        local ok, map, level, ms, onTime, upgrades, practice, before, after = pcall(C.GetCompletionInfo)
        if ok then
            return Num(map), Num(level), Num(ms), Plain(onTime), Num(upgrades), Num(before), Num(after), Plain(practice)
        end
    end
    return nil
end

local function RecordCompletion()
    local j = Journey()
    if not j then return end
    local map, level, ms, onTime, upgrades, before, after, practice = CompletionInfo()
    if not (map and level) or practice == true then return end
    local run = {
        t = time(), map = map, level = level, timed = onTime == true,
        upgrades = upgrades or 0, secs = ms and ms / 1000 or nil,
        before = before, after = after or OverallScore(),
    }
    j.runs[#j.runs + 1] = run
    NoteRating(j, run.after, run.t)

    if settings.announce then
        local name, limit = MapInfo(map)
        local result = run.timed and ("|cff40ff40" .. L["in time"] .. (run.upgrades > 0 and (" +" .. run.upgrades) or "") .. "|r")
            or ("|cffff5555" .. L["over time"] .. "|r")
        local change = ""
        if run.before and run.after then
            local d = run.after - run.before
            change = ("  %s%d|r %s"):format(ScoreColour(run.after), run.after,
                d > 0 and ("|cff40ff40(+" .. d .. ")|r") or "")
        end
        print(PREFIX .. ("%s +%d  %s  %s%s"):format(name, level, result,
            run.secs and (Clock(run.secs) .. (limit and (" / " .. Clock(limit)) or "")) or "", change))
    end
    for _, text in ipairs(NewMilestones(j, false)) do
        if settings.milestoneChat then print(PREFIX .. "|cffffd100" .. L["Milestone:"] .. "|r " .. text) end
        if settings.milestoneSound and settings.milestoneSound ~= "None" and OxedHub.ModuleAPI and OxedHub.ModuleAPI.PlaySound then
            OxedHub.ModuleAPI:PlaySound(settings.milestoneSound)
        end
    end
    if Refresh then Refresh() end
end

-- On login and on opening: history once, and today's rating as a point.
local function Catch()
    local j = Journey()
    if not j then return end
    ImportHistory(j)
    NoteRating(j, OverallScore())
    -- What was already true before the module was on is not news.
    NewMilestones(j, true)
end

-- ── The window ──────────────────────────────────────────────────────────────

local W, H = 560, 560
local ROW_H = 16

local function Text(parent, font, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- The rating over the season, as a line through every point the game gave.
local function DrawGraph(graph, points)
    graph.lines = graph.lines or {}
    for _, l in ipairs(graph.lines) do l:Hide() end
    graph.empty:SetShown(#points < 2)
    if #points < 2 then
        graph.top:SetText("")
        graph.bottom:SetText("")
        return
    end
    local lo, hi = math.huge, 0
    for _, p in ipairs(points) do
        if p[2] < lo then lo = p[2] end
        if p[2] > hi then hi = p[2] end
    end
    if hi - lo < 50 then lo = math.max(0, hi - 50) end
    local w, h = graph:GetWidth() - 8, graph:GetHeight() - 8
    local n = #points
    local function XY(i)
        local p = points[i]
        return 4 + (i - 1) / (n - 1) * w, 4 + (p[2] - lo) / (hi - lo) * h
    end
    for i = 2, n do
        local line = graph.lines[i - 1]
        if not line then
            line = graph:CreateLine(nil, "ARTWORK")
            line:SetThickness(2)
            line:SetColorTexture(0.64, 0.21, 0.93, 0.9)
            graph.lines[i - 1] = line
        end
        local x1, y1 = XY(i - 1)
        local x2, y2 = XY(i)
        line:SetStartPoint("BOTTOMLEFT", graph, x1, y1)
        line:SetEndPoint("BOTTOMLEFT", graph, x2, y2)
        line:Show()
    end
    graph.top:SetText(ScoreColour(hi) .. hi .. "|r")
    graph.bottom:SetText("|cff9d9d9d" .. lo .. "|r")
end

local function Rows(holder, i)
    holder.rows = holder.rows or {}
    local row = holder.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, holder)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("LEFT", 2, 0)
    row.a = Text(row)
    row.a:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.b = Text(row, nil, "RIGHT")
    row.c = Text(row, nil, "RIGHT")
    row.c:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.b:SetPoint("RIGHT", row.c, "LEFT", -8, 0)
    row.a:SetPoint("RIGHT", row.b, "LEFT", -6, 0)
    holder.rows[i] = row
    return row
end

local function FillRows(holder, list)
    for i, item in ipairs(list) do
        local row = Rows(holder, i)
        row.icon:SetShown(item.icon ~= nil)
        if item.icon then row.icon:SetTexture(item.icon) end
        row.a:SetText(item.a or "")
        row.b:SetText(item.b or "")
        row.c:SetText(item.c or "")
        row:Show()
    end
    for i = #list + 1, #(holder.rows or {}) do holder.rows[i]:Hide() end
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    local j, season = Journey()
    if not j then
        window.summary:SetText(L["No Mythic+ season is running right now."])
        return
    end

    -- Summary.
    local score = OverallScore() or (j.rating[#j.rating] and j.rating[#j.rating][2]) or 0
    local timed, best = 0, nil
    for _, r in ipairs(j.runs) do
        if r.timed then
            timed = timed + 1
            if not best or r.level > best.level then best = r end
        end
    end
    local first = j.rating[1]
    window.summary:SetText(("%s %s%d|r    %s %d    %s %d (%d%%)    %s %s"):format(
        L["Rating"], ScoreColour(score), score,
        L["Keys"], #j.runs,
        L["In time"], timed, #j.runs > 0 and math.floor(timed / #j.runs * 100 + 0.5) or 0,
        L["Best"], best and ("+" .. best.level .. " " .. (MapInfo(best.map))) or "-"))
    window.season:SetText((L["Season %d"]):format(season)
        .. (first and ("  |cff9d9d9d" .. L["since"] .. " " .. date("%d %b %Y", first[1]) .. "|r") or ""))

    DrawGraph(window.graph, j.rating)

    -- Best per dungeon.
    local per = {}
    for _, r in ipairs(j.runs) do
        local d = per[r.map] or { runs = 0, timed = 0, best = 0 }
        per[r.map] = d
        d.runs = d.runs + 1
        if r.timed then
            d.timed = d.timed + 1
            if r.level > d.best then d.best = r.level end
        end
    end
    local dungeons = {}
    for _, m in ipairs(DungeonList()) do
        local name, _, icon = MapInfo(m)
        local d = per[m] or { runs = 0, timed = 0, best = 0 }
        dungeons[#dungeons + 1] = { icon = icon, a = name,
            b = ("|cff9d9d9d%d/%d|r"):format(d.timed, d.runs),
            c = d.best > 0 and ("|cff40ff40+" .. d.best .. "|r") or "|cff9d9d9d-|r", sort = d.best }
    end
    table.sort(dungeons, function(a, b)
        if a.sort ~= b.sort then return a.sort > b.sort end
        return a.a < b.a
    end)
    FillRows(window.dungeons, dungeons)

    -- Milestones, newest first.
    local ms = {}
    for id, text in pairs(Milestones(j)) do
        local t = j.seen[id]
        ms[#ms + 1] = { a = "|cffffd100*|r " .. text, c = type(t) == "number" and ("|cff9d9d9d" .. date("%d %b", t) .. "|r") or "",
            sort = type(t) == "number" and t or 0 }
    end
    table.sort(ms, function(a, b)
        if a.sort ~= b.sort then return a.sort > b.sort end
        return a.a < b.a
    end)
    while #ms > 9 do ms[#ms] = nil end
    if #ms == 0 then ms[1] = { a = "|cff9d9d9d" .. L["Finish a key to start the journey."] .. "|r" } end
    FillRows(window.milestones, ms)

    -- Recent runs, newest first.
    local recent = {}
    local limitN = tonumber(settings.recentRuns) or 25
    for i = #j.runs, math.max(1, #j.runs - limitN + 1), -1 do
        local r = j.runs[i]
        local name, limit, icon = MapInfo(r.map)
        local result = r.timed and ("|cff40ff40+" .. r.level .. (r.upgrades and r.upgrades > 1 and (" (" .. ("+"):rep(r.upgrades) .. ")") or "") .. "|r")
            or ("|cffff5555+" .. r.level .. "|r")
        local clock = r.secs and (Clock(r.secs) .. (limit and ("|cff9d9d9d/" .. Clock(limit) .. "|r") or "")) or ""
        local change = ""
        if r.before and r.after and r.after ~= r.before then
            change = ("  |cff40ff40+%d|r"):format(r.after - r.before)
        end
        recent[#recent + 1] = { icon = icon, a = result .. "  " .. name,
            b = clock .. change, c = "|cff9d9d9d" .. DateText(r.t) .. "|r" }
    end
    if #recent == 0 then recent[1] = { a = "|cff9d9d9d" .. L["No keys yet this season."] .. "|r" } end
    FillRows(window.recent, recent)
    window.recent:SetHeight(math.max(1, #recent * ROW_H))
end

local ShowOptions   -- defined below

local function Section(parent, label, anchor, y)
    local fs = Text(parent, "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -10)
    fs:SetText(label)
    return fs
end

local function BuildWindow()
    if window then return end
    local f = CreateFrame("Frame", "OxedHubMythicJourneyWindow", UIParent, "BasicFrameTemplate")
    f:SetSize(W, H)
    f:SetPoint(settings.point or "CENTER", UIParent, settings.point or "CENTER", settings.x or 0, settings.y or 0)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        settings.point, settings.x, settings.y = point, x, y
    end)
    f:Hide()
    if f.TitleText then f.TitleText:SetText(L["Mythic Journey"]) end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    tinsert(UISpecialFrames, "OxedHubMythicJourneyWindow")

    f.season = Text(f, "GameFontNormalLarge")
    f.season:SetPoint("TOPLEFT", 14, -32)
    local opt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    opt:SetSize(80, 20)
    opt:SetPoint("TOPRIGHT", -12, -30)
    opt:SetText(L["Options"])
    opt:SetScript("OnClick", function() ShowOptions() end)

    f.summary = Text(f)
    f.summary:SetPoint("TOPLEFT", f.season, "BOTTOMLEFT", 0, -6)
    f.summary:SetPoint("RIGHT", f, "RIGHT", -14, 0)

    -- Rating graph.
    local graph = CreateFrame("Frame", nil, f, "BackdropTemplate")
    graph:SetPoint("TOPLEFT", f.summary, "BOTTOMLEFT", 0, -8)
    graph:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    graph:SetHeight(90)
    if graph.SetBackdrop then
        graph:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        graph:SetBackdropColor(0, 0, 0, 0.35)
        graph:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
    graph.top = Text(graph, "GameFontHighlightSmall")
    graph.top:SetPoint("TOPLEFT", 4, -3)
    graph.bottom = Text(graph, "GameFontHighlightSmall")
    graph.bottom:SetPoint("BOTTOMLEFT", 4, 3)
    graph.empty = Text(graph, "GameFontDisableSmall", "CENTER")
    graph.empty:SetPoint("CENTER")
    graph.empty:SetText(L["The rating graph fills in as you finish keys."])
    f.graph = graph

    -- Two columns: dungeons left, milestones right.
    local colW = (W - 40) / 2
    local dHead = Section(f, L["Best in time per dungeon"], graph, -10)
    f.dungeons = CreateFrame("Frame", nil, f)
    f.dungeons:SetPoint("TOPLEFT", dHead, "BOTTOMLEFT", 0, -4)
    f.dungeons:SetSize(colW, 8 * ROW_H)

    local mHead = Text(f, "GameFontNormal")
    mHead:SetPoint("TOPLEFT", dHead, "TOPLEFT", colW + 12, 0)
    mHead:SetText(L["Milestones"])
    f.milestones = CreateFrame("Frame", nil, f)
    f.milestones:SetPoint("TOPLEFT", mHead, "BOTTOMLEFT", 0, -4)
    f.milestones:SetSize(colW, 9 * ROW_H)

    -- Recent runs, scrolling.
    local rHead = Text(f, "GameFontNormal")
    rHead:SetPoint("TOPLEFT", f.milestones, "BOTTOMLEFT", -(colW + 12), -8)
    rHead:SetText(L["Recent keys"])
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", rHead, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(W - 60, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    f.recent = content

    f:SetScript("OnShow", function()
        Catch()
        Refresh()
    end)
    window = f
end

local function Toggle()
    if not running then
        print(PREFIX .. L["switched off. Switch it on in OxedHub's Modules page first."])
        return
    end
    BuildWindow()
    window:SetShown(not window:IsShown())
end

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Mythic Journey", 440, 360)
        optionsWindow = w
        w:AddCheckbox(settings, "announce", "After each key, the result and rating change in chat")
        w:AddCheckbox(settings, "milestoneChat", "Say each new milestone in chat")
        w:AddSoundPicker(settings, "milestoneSound", "Milestone sound")
        w:AddSlider(settings, "recentRuns", "Recent keys listed", 10, 100, 5, "%s: %d", function() if Refresh then Refresh() end end)
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("/mjourney opens the journey. Keys from before the module was on are read once from the game's "
            .. "run history; those have no date or time.")
    end
    optionsWindow:Show()
end

SLASH_OXEDMJOURNEY1 = "/mjourney"
SLASH_OXEDMJOURNEY2 = "/oxjourney"
SlashCmdList.OXEDMJOURNEY = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" or msg == "config" then ShowOptions() else Toggle() end
end

-- ── Events ──────────────────────────────────────────────────────────────────

events:SetScript("OnEvent", function(_, event)
    if not running then return end
    if event == "CHALLENGE_MODE_COMPLETED" then
        -- A moment later: the new score is written just after the event.
        C_Timer.After(2, function() if running then RecordCompletion() end end)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE" then
        C_Timer.After(3, function() if running then Catch() end end)
    elseif event == "CHALLENGE_MODE_MAPS_UPDATE" then
        if window and window:IsShown() then Refresh() end
    end
end)

local EVENTS = { "CHALLENGE_MODE_COMPLETED", "PLAYER_ENTERING_WORLD", "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE",
                 "CHALLENGE_MODE_MAPS_UPDATE" }

local function Start()
    if running then return end
    running = true
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    -- The run history and scores load on request.
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    if C_MythicPlus and C_MythicPlus.RequestRewards then pcall(C_MythicPlus.RequestRewards) end
    C_Timer.After(4, function() if running then Catch() end end)
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    if window then window:Hide() end
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "mythicjourney", label = L["Mythic Journey"], icon = "Interface\\Icons\\INV_Relics_Hourglass", config = settings,
        hint = L["Click: the journey. Right-click: options."],
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else Toggle() end
        end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.mythicjourney
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.mythicjourney = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.journeys) ~= "table" then config.journeys = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "mythicjourney",
        name     = "Mythic Journey",
        version  = "1.0.0",
        updated  = 20261030.5,  -- new
        author   = "Oxed",
        category = "groups",
        keywords = { "mythic", "m+", "keystone", "rating", "score", "season", "journey", "history", "milestone" },
        desc     = "Your Mythic+ season as a story: rating over time, best keys, milestones and every run.",
        icon     = "Interface\\Icons\\INV_Relics_Hourglass",
        defaults = DEFAULTS,
        quick = {
            { text = L["Show or hide"], func = function() Toggle() end },
        },
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            if type(settings.journeys) ~= "table" then settings.journeys = {} end
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
