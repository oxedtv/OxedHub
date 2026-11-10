-- ============================================================================
-- Quest Mobs (built-in OxedHub module)
-- A quest icon and the progress ("0/7") on the nameplate of every mob one of
-- your quests still needs, so you can tell them apart without the mouse.
--
-- What a mob is needed for comes from the same place the mouseover tooltip
-- gets it: the unit's tooltip lines. Two ways to read them, because the two
-- clients differ:
--   * C_TooltipInfo.GetUnit, where each line says what kind it is;
--   * a hidden tooltip of our own, where a line is only text and an objective
--     is recognised by its "2/7".
--
-- ⚠ It hangs on the nameplate: no nameplate (enemy plates off, or too far),
-- no icon.
-- ⚠ Tooltip text and unit names can be secret in combat. A scan that fails
-- leaves the plate showing what it already showed, it never clears it: one
-- bad read must not make the icon blink.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on
    position      = "left",  -- "left", "right" or "top" of the health bar
    size          = 20,
    offsetX       = 0,
    offsetY       = 0,
    showIcon      = true,
    showCount     = true,
    textSize      = 12,
    lootIcon      = true,    -- a bag instead of the "!" when the mob drops a quest item
    countMode     = "progress", -- "progress" (4/7) or "left" (3 left)
    showAll       = false,   -- every unfinished objective, not only the first
    showTitle     = false,   -- the quest's name above the badge
    barTint       = false,   -- our own colour laid over the health bar
    hideInInstances = true,  -- nothing in dungeons and raids
    doneSound     = "None",  -- played when an objective is finished
    minimapButton = true,
    -- killColour, lootColour and barColour are tables, made at login
}

local TINT_ALPHA = 0.7
local DONE_REFIRE = 1.5      -- two objectives finished by one kill are one sound

local KILL_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local LOOT_ICON = "Interface\\Buttons\\Button-Backpack-Up"
local REFRESH_DELAY = 0.3    -- quest events come in bursts; one pass serves them all
local SETTLE_DELAY = 0.6     -- a new plate's tooltip data can arrive a moment late
local RECHECK = 2            -- and sometimes later still: every plate is looked at again this often
local MAX_PLATES = 40        -- nameplate1 .. nameplate40

local settings
local running = false
local optionsWindow
local minimapIcon, MinimapIcon
local badges = {}            -- unit token -> badge frame
local spare = {}             -- badges waiting for a plate
local refreshQueued = false
local recheck                -- the ticker that looks at every plate again
local scanTip, scanTipFailed
local lastSnapshot           -- "questID:objective" -> finished, from the quest log
local snapshotMissing = false -- this client's quest log cannot be read that way
local lastDone = 0

local events = CreateFrame("Frame")

local function PlayDone()
    if not settings or not settings.doneSound or settings.doneSound == "None" then return end
    local now = GetTime()
    if now - lastDone < DONE_REFIRE then return end
    lastDone = now
    if OxedHub.ModuleAPI and OxedHub.ModuleAPI.PlaySound then
        OxedHub.ModuleAPI:PlaySound(settings.doneSound)
    end
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- ── Reading the tooltip ─────────────────────────────────────────────────────
-- Both readers return a list of { text = ..., kind = ... }, where kind is
-- "objective", "title" (the quest the next objectives belong to), "player"
-- (the party member they belong to), or nil. The plain reader cannot tell a
-- title from any other line, so it calls every other line one: the line just
-- above an objective is the quest's name. Either may throw; the caller runs
-- them in pcall.

local function TypedLines(unit)
    local types = Enum and Enum.TooltipDataLineType
    if not (C_TooltipInfo and C_TooltipInfo.GetUnit and types and types.QuestObjective) then return nil end
    local data = C_TooltipInfo.GetUnit(unit)
    if not data or type(data.lines) ~= "table" then return nil end
    local out = {}
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not IsSecret(text) then
            local kind
            if line.type == types.QuestObjective then
                kind = "objective"
            elseif types.QuestPlayer and line.type == types.QuestPlayer then
                kind = "player"
            elseif types.QuestTitle and line.type == types.QuestTitle then
                kind = "title"
            end
            out[#out + 1] = { text = text, kind = kind, completed = line.completed == true }
        end
    end
    return out
end

local function GroupNames()
    local names = {}
    if not (IsInGroup and IsInGroup()) then return names end
    local raid = IsInRaid and IsInRaid()
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local name = UnitName(raid and ("raid" .. i) or ("party" .. i))
        if type(name) == "string" and not IsSecret(name) then names[name] = true end
    end
    return names
end

local function PlainLines(unit)
    if scanTipFailed then return nil end
    if not scanTip then
        local ok, tip = pcall(CreateFrame, "GameTooltip", "OxedHubQuestMobsScan", nil, "GameTooltipTemplate")
        if not ok or not tip then
            scanTipFailed = true
            return nil
        end
        scanTip = tip
    end
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetUnit(unit)
    local me = UnitName("player")
    local group = GroupNames()
    local out = {}
    -- Line 1 is the mob's name.
    for i = 2, scanTip:NumLines() do
        local region = _G["OxedHubQuestMobsScanTextLeft" .. i]
        local text = region and region:GetText()
        if type(text) == "string" and not IsSecret(text) then
            local kind = "title"
            if text:match("%d+%s*/%s*%d+") then
                kind = "objective"
            elseif text == me or group[text] then
                kind = "player"
            end
            out[#out + 1] = { text = text, kind = kind }
        end
    end
    scanTip:Hide()
    return out
end

-- The objectives of yours this mob still counts for.
-- Returns found (were there objective lines at all) and a list of entries:
-- { have, need } or { percent }, or neither when there is nothing to count,
-- each with loot (the mob drops an item) and title (the quest's name).
local function ReadObjectives(unit)
    -- Typed lines with nothing in them (a client that keeps the text
    -- elsewhere) are no answer: read the tooltip itself.
    local lines = TypedLines(unit)
    if not lines or #lines == 0 then lines = PlainLines(unit) end
    local list = {}
    if not lines then return false, list end
    local me = UnitName("player")
    if IsSecret(me) then me = nil end
    local mobName = UnitName(unit)
    if IsSecret(mobName) or type(mobName) ~= "string" or mobName == "" then mobName = nil end

    local mine = true
    local found = false
    local title
    for _, line in ipairs(lines) do
        if line.kind == "title" then
            title = line.text
        elseif line.kind == "player" then
            mine = (me ~= nil and line.text == me)
        elseif line.kind == "objective" and mine then
            found = true
            if not line.completed then
                local have, need = line.text:match("(%d+)%s*/%s*(%d+)")
                have, need = tonumber(have), tonumber(need)
                local entry
                if have and need then
                    if have < need then entry = { have = have, need = need } end
                else
                    local percent = tonumber(line.text:match("(%d+)%%"))
                    if not percent then
                        entry = {}               -- unfinished, with nothing to count
                    elseif percent < 100 then
                        entry = { percent = percent }
                    end
                end
                if entry then
                    -- "0/7 Thistle Boar slain" names the mob; "Boar Tusk: 0/5" does not.
                    entry.loot = mobName ~= nil and not line.text:find(mobName, 1, true)
                    entry.title = title
                    list[#list + 1] = entry
                end
            end
        end
    end
    return found, list
end

-- Every objective in the quest log and whether it is finished, or nil when
-- this client has no way to ask. May throw; the caller runs it in pcall.
local function QuestSnapshot()
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
    local ids = {}
    if C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then ids[#ids + 1] = info.questID end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for i = 1, (GetNumQuestLogEntries()) do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if not isHeader and questID then ids[#ids + 1] = questID end
        end
    else
        return nil
    end
    local snapshot = {}
    for _, id in ipairs(ids) do
        local objectives = C_QuestLog.GetQuestObjectives(id)
        if type(objectives) == "table" then
            for j, objective in ipairs(objectives) do
                snapshot[id .. ":" .. j] = objective.finished and true or false
            end
        end
    end
    return snapshot
end

-- The sound for an objective that was unfinished last time and is done now.
-- A quest just taken has no "last time", so it is silent.
local function CheckFinished()
    local ok, snapshot = pcall(QuestSnapshot)
    if not ok then return end       -- a bad read: keep the old picture
    if not snapshot then
        snapshotMissing = true
        return
    end
    snapshotMissing = false
    if lastSnapshot then
        for key, finished in pairs(snapshot) do
            if finished and lastSnapshot[key] == false then
                PlayDone()
                break
            end
        end
    end
    lastSnapshot = snapshot
end

local function InInstance()
    if not IsInInstance then return false end
    local ok, inside, kind = pcall(IsInInstance)
    return ok and inside and (kind == "party" or kind == "raid") or false
end

-- True, false, or nil for "cannot tell".
local function RelatedToQuest(unit)
    if not (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) then return nil end
    local ok, value = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if not ok or IsSecret(value) then return nil end
    return value and true or false
end

-- ── The badge on a plate ────────────────────────────────────────────────────

local function NewBadge()
    local badge = CreateFrame("Frame")
    badge:SetSize(1, 1)
    badge.icon = badge:CreateTexture(nil, "OVERLAY")
    badge.text = badge:CreateFontString(nil, "OVERLAY")
    badge.text:SetFont(STANDARD_TEXT_FONT, DEFAULTS.textSize, "OUTLINE")
    badge.title = badge:CreateFontString(nil, "OVERLAY")
    badge.title:SetFont(STANDARD_TEXT_FONT, DEFAULTS.textSize, "OUTLINE")
    badge.title:SetPoint("BOTTOM", badge, "TOP", 0, 1)
    -- Our own texture over the bar: the bar's colour stays the game's (or
    -- another addon's) to set, and there is nothing to put back afterwards.
    badge.tint = badge:CreateTexture(nil, "ARTWORK")
    badge.tint:Hide()
    badge:Hide()
    return badge
end

local function EntryText(entry)
    if entry.need then
        if settings.countMode == "left" then
            return L["%d left"]:format(entry.need - entry.have)
        end
        return entry.have .. "/" .. entry.need
    elseif entry.percent then
        return entry.percent .. "%"
    end
    return nil
end

local function Coloured(text, colour)
    local function Byte(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 1) * 255 + 0.5))) end
    return ("|cff%02x%02x%02x%s|r"):format(Byte(colour[1]), Byte(colour[2]), Byte(colour[3]), text)
end

local function Style(badge)
    local size = tonumber(settings.size) or DEFAULTS.size
    local icon, text = badge.icon, badge.text
    local entries = badge.entries
    local first = entries[1]
    local loot = first and first.loot

    icon:SetTexture((loot and settings.lootIcon) and LOOT_ICON or KILL_ICON)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("LEFT", badge, "LEFT", 0, 0)
    icon:SetShown(settings.showIcon)

    local textSize = tonumber(settings.textSize) or DEFAULTS.textSize
    text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    local parts = {}
    if settings.showCount then
        for i, entry in ipairs(entries) do
            local part = EntryText(entry)
            if part then
                parts[#parts + 1] = Coloured(part, entry.loot and settings.lootColour or settings.killColour)
            end
            if not settings.showAll and i == 1 then break end
        end
    end
    text:SetText(table.concat(parts, "  "))

    local title = badge.title
    if settings.showTitle and first and first.title then
        title:SetFont(STANDARD_TEXT_FONT, math.max(8, textSize - 2), "OUTLINE")
        title:SetTextColor(1, 1, 1)
        title:SetText(first.title)
        title:Show()
    else
        title:Hide()
    end

    local tint = badge.tint
    if settings.barTint and badge.hasBar then
        local bar = badge.bar
        local fill
        if bar.GetStatusBarTexture then
            local ok, texture = pcall(bar.GetStatusBarTexture, bar)
            fill = ok and texture or nil
        end
        local c = settings.barColour
        tint:ClearAllPoints()
        tint:SetAllPoints(fill or bar)     -- the filled part only, when it can be found
        tint:SetColorTexture(c[1] or 1, c[2] or 1, c[3] or 1, TINT_ALPHA)
        tint:Show()
    else
        tint:Hide()
    end

    text:ClearAllPoints()
    if settings.showIcon then
        text:SetPoint("LEFT", icon, "RIGHT", 1, 0)
    else
        text:SetPoint("LEFT", badge, "LEFT", 0, 0)
    end

    local width = (settings.showIcon and size or 0) + (text:GetStringWidth() or 0) + 1
    badge:SetSize(math.max(1, width), size)

    local bar = badge.bar
    local x, y = tonumber(settings.offsetX) or 0, tonumber(settings.offsetY) or 0
    badge:ClearAllPoints()
    if settings.position == "right" then
        badge:SetPoint("LEFT", bar, "RIGHT", 4 + x, y)
    elseif settings.position == "top" then
        badge:SetPoint("BOTTOM", bar, "TOP", x, 14 + y)
    else
        badge:SetPoint("RIGHT", bar, "LEFT", -4 + x, y)
    end
end

local function Release(unit)
    local badge = badges[unit]
    if not badge then return end
    badges[unit] = nil
    badge:Hide()
    badge:ClearAllPoints()
    -- The tint is pinned to a bar that now belongs to another mob.
    badge.tint:ClearAllPoints()
    badge.tint:Hide()
    badge:SetParent(UIParent)
    spare[#spare + 1] = badge
end

local function UpdateUnit(unit)
    if not running then return end
    local plate
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, found = pcall(C_NamePlate.GetNamePlateForUnit, unit)
        plate = ok and found or nil
    end
    if not plate or (plate.IsForbidden and plate:IsForbidden())
        or (settings.hideInInstances and InInstance()) then
        Release(unit)
        return
    end

    local ok, found, entries = pcall(ReadObjectives, unit)
    if not ok then
        -- A secret got in the way: keep what is shown. A plate that shows
        -- nothing yet (the mob came into view mid-fight) gets the icon alone
        -- when the game says the mob belongs to a quest.
        if badges[unit] or not RelatedToQuest(unit) then return end
        found, entries = false, {}
    end

    if #entries == 0 then
        -- No objective lines at all, yet the game says the mob matters to a
        -- quest: show the icon alone. Lines that are all finished mean no.
        if not found and RelatedToQuest(unit) then
            entries = { { loot = false } }
        else
            -- Where the quest log cannot be read, a mob whose count just
            -- ran out is the only sign that an objective was finished.
            local old = badges[unit]
            if snapshotMissing and found and old and old.entries[1] and old.entries[1].need then
                PlayDone()
            end
            Release(unit)
            return
        end
    end

    local badge = badges[unit]
    if not badge then
        badge = table.remove(spare) or NewBadge()
        badges[unit] = badge
    end
    badge.entries = entries
    -- Blizzard's bar or another nameplate addon's, whichever is on screen.
    local bar = OxedHub.VisiblePlateBar and OxedHub.VisiblePlateBar(plate) or nil
    badge.hasBar = bar ~= nil
    badge.bar = bar or plate
    badge:SetParent(plate)
    badge:SetFrameStrata(plate:GetFrameStrata())
    badge:SetFrameLevel(plate:GetFrameLevel() + 20)
    Style(badge)
    badge:Show()
end

local function RefreshAll()
    refreshQueued = false
    if not running then return end
    -- By token, not by a field of the plate: where the plate does not carry
    -- its unit's name, every badge used to be taken down here and none put
    -- back. UpdateUnit releases the badge of a token that has no plate.
    for i = 1, MAX_PLATES do
        UpdateUnit("nameplate" .. i)
    end
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(REFRESH_DELAY, function()
        if running then CheckFinished() end
        RefreshAll()
    end)
end

local function Restyle()
    for _, badge in pairs(badges) do Style(badge) end
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) ~= "string" then return end
        -- The token is reused: whatever it showed belonged to another mob.
        Release(unit)
        UpdateUnit(unit)
        C_Timer.After(SETTLE_DELAY, function() UpdateUnit(unit) end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then Release(unit) end
    else
        QueueRefresh()
    end
end)

local EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
}

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Quest Mobs", 460, 700)
        optionsWindow = w

        w:AddChoice(settings, "position", "Position", {
            { value = "left",  text = "Left of the health bar" },
            { value = "right", text = "Right of the health bar" },
            { value = "top",   text = "Above the health bar" },
        }, Restyle)
        w:AddCheckbox(settings, "showIcon", "Show the quest icon", nil, Restyle)
        w:AddCheckbox(settings, "showCount", "Show the progress, like 0/7", nil, Restyle)
        w:AddChoice(settings, "countMode", "The number shows", {
            { value = "progress", text = "Progress, like 4/7" },
            { value = "left",     text = "How many are left" },
        }, Restyle)
        w:AddCheckbox(settings, "showAll", "Show every unfinished objective of the mob", nil, Restyle)
        w:AddCheckbox(settings, "showTitle", "Show the quest's name", nil, Restyle)
        w:AddCheckbox(settings, "lootIcon", "A bag icon when the mob drops a quest item", nil, Restyle)
        w:AddSlider(settings, "size", "Icon size", 10, 48, 1, "%s: %d", Restyle)
        w:AddSlider(settings, "textSize", "Text size", 8, 24, 1, "%s: %d", Restyle)
        w:AddSlider(settings, "offsetX", "Offset X", -80, 80, 1, "%s: %d", Restyle)
        w:AddSlider(settings, "offsetY", "Offset Y", -80, 80, 1, "%s: %d", Restyle)
        w:AddColour(settings, "killColour", "Text colour: mobs to kill", Restyle)
        w:AddColour(settings, "lootColour", "Text colour: mobs with a quest item", Restyle)
        w:AddCheckbox(settings, "barTint", "Colour the health bar of quest mobs", nil, Restyle)
        w:AddColour(settings, "barColour", "Health bar colour", Restyle)
        w:AddSoundPicker(settings, "doneSound", "Sound when an objective is finished")
        w:AddCheckbox(settings, "hideInInstances", "Hide in dungeons and raids", nil, RefreshAll)
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
        end)
        w:AddNote("The icon sits on the mob's nameplate, so enemy nameplates must be on (V by default). A mob too far away to have a nameplate has no icon.")
        -- Exactly as tall as what went in it, whichever language that was in.
        w:SetHeight(math.max(200, 16 - w.cursorY))
    end
    optionsWindow:Show()
end

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "questmobs", label = L["Quest Mobs"], icon = "Interface\\Icons\\INV_Misc_Note_02", config = settings,
        hint = L["Click: options."],
        onClick = function()
            ShowOptions()
        end,
    })
    return minimapIcon
end

SLASH_OXEDHUBQUESTMOBS1 = "/oxquestmobs"
SlashCmdList.OXEDHUBQUESTMOBS = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg ~= "debug" then return ShowOptions() end
    -- What the module reads for your target, line by line.
    local typedOk, typed = pcall(TypedLines, "target")
    local plainOk, plain = pcall(PlainLines, "target")
    local lines = (typedOk and typed) or (plainOk and plain) or {}
    print(("Quest Mobs: on %s, typed lines %s, plain lines %s, related %s"):format(
        tostring(running), tostring(typedOk and typed ~= nil), tostring(plainOk and plain ~= nil),
        tostring(RelatedToQuest("target"))))
    for i, line in ipairs(lines) do
        print(("  %d [%s] %s"):format(i, tostring(line.kind), line.text))
    end
    local ok, found, entries = pcall(ReadObjectives, "target")
    print(("  read ok %s, objectives %s, unfinished %s, quest log readable %s, in instance %s"):format(
        tostring(ok), tostring(found), tostring(ok and type(entries) == "table" and #entries or "?"),
        tostring(not snapshotMissing), tostring(InInstance())))
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.questmobs
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.questmobs = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if type(config.killColour) ~= "table" then config.killColour = { 1, 0.82, 0 } end
    if type(config.lootColour) ~= "table" then config.lootColour = { 0.4, 0.8, 1 } end
    if type(config.barColour) ~= "table" then config.barColour = { 1, 0.5, 0 } end
    settings = config

    if not OxedHub.ModuleAPI then return end

    OxedHub.ModuleAPI:Register({
        id       = "questmobs",
        name     = "Quest Mobs",
        version  = "1.1.1",
        updated  = 20261110.5,
        added    = 20261110,
        author   = "Oxed",
        category = "quests",
        keywords = { "quest", "mob", "nameplate", "objective", "progress", "kill", "icon", "leveling" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A quest icon and progress (0/7) on the nameplates of mobs your quests need. /oxquestmobs",
        icon     = "Interface\\Icons\\INV_Misc_Note_02",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            running = true
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
            -- The picture to compare the next quest update against.
            lastSnapshot = nil
            CheckFinished()
            RefreshAll()
            if not recheck and C_Timer.NewTicker then
                recheck = C_Timer.NewTicker(RECHECK, RefreshAll)
            end
        end,

        OnDisable = function()
            running = false
            if recheck then
                recheck:Cancel()
                recheck = nil
            end
            if minimapIcon then minimapIcon:Apply(false) end
            events:UnregisterAllEvents()
            for unit in pairs(badges) do Release(unit) end
        end,
    })
end)
