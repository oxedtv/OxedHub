-- ============================================================================
-- WQ Achievements (built-in OxedHub module)
-- Which world quests up right now count toward an achievement you still need,
-- or reward a mount, pet or toy you do not have. One window, grouped by
-- expansion and zone, with the achievement linked (click to open it, shift-
-- click to post it, right-click for a web link).
--
-- Accuracy: nothing is assumed. The data (WQAchievementsData.lua) only says
-- which quest belongs to which criterion; whether that criterion, the
-- achievement or the collectible is still missing is asked of the game every
-- time the list is built. "Show all" lists finished ones too, with a tick.
--
-- Also here:
--   * A screenshot the moment an achievement is earned (optional).
--   * A quest mark over the nameplate of anything your quest log needs.
--
-- ⚠ Reward data for a world quest arrives late: a quest whose rewards are not
--   loaded yet is asked for them and looked at again, never guessed.
-- ⚠ Which unit a quest needs can be a secret in combat. The nameplate mark
--   hides itself through SetAlphaFromBoolean then; Lua never tests it.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile
local Data = OxedHub.WQAData or { data = {}, ZoneIDList = {} }

local PREFIX = "|cffffd100OxedHub WQ Achievements:|r "
local CURRENT_EXPANSION = 12

local DEFAULTS = {
    minimapButton = true,   -- its own icon on the minimap while switched on
    enabled        = false,   -- off until the player switches it on
    showAll        = false,   -- false: only what is still missing; true: finished ones too
    expansions     = "current", -- "current" or "all"
    wantAchieve    = true,
    wantMount      = true,
    wantPet        = true,
    wantToy        = true,
    announce       = true,    -- new finds in chat
    openOnFind     = false,   -- open the window when something new turns up
    screenshot     = false,   -- a screenshot when an achievement is earned
    screenshotNew  = true,    -- only achievements new to this character
    plateMarks     = true,    -- quest mark over nameplates your quest log needs
    plateMarkSize  = 22,
    point = "CENTER", x = 260, y = 40,
}

local settings
local minimapIcon, MinimapIcon   -- MinimapIcon is defined above the login code
local optionsWindow
local running = false
local window

local events = CreateFrame("Frame")
local GoScan    -- the world quest scan; defined with the scanning code

-- The global went away in later builds; the C_Item one stays.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- ── Small helpers ───────────────────────────────────────────────────────────

local function IsSecret(v) return issecretvalue and issecretvalue(v) or false end

local function Plain(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

-- true, false, or nil when the answer is secret or the call failed.
local function Known(fn, ...)
    local ok, value = pcall(fn, ...)
    if not ok or IsSecret(value) then return nil end
    return value and true or false
end

local function MyFaction()
    local faction = UnitFactionGroup("player")
    return Plain(faction)
end

local function TimeLeft(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    if sec >= 86400 then return ("%dd %dh"):format(sec / 86400, (sec % 86400) / 3600) end
    if sec >= 3600 then return ("%dh %dm"):format(sec / 3600, (sec % 3600) / 60) end
    return ("%dm"):format(math.max(1, sec / 60))
end

local function AchievementLink(id)
    local ok, link = pcall(GetAchievementLink, id)
    if ok and type(link) == "string" then return link end
    return nil
end

local function AchievementName(id)
    local ok, _, name = pcall(GetAchievementInfo, id)
    return ok and Plain(name) or ("Achievement " .. id)
end

local function QuestTitle(questID)
    local title = C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID and C_TaskQuest.GetQuestInfoByQuestID(questID)
    if type(title) ~= "string" or title == "" then
        title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    end
    return Plain(title) or (L["Quest "] .. questID)
end

local function MapName(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    return info and Plain(info.name) or "?"
end

-- ── What still counts: built from the game, never assumed ───────────────────
-- index[questID] = { achievements = { [achievementID] = done }, items = { [itemID] = { kind, done } } }

local index = {}

local function Want(questID)
    local entry = index[questID]
    if not entry then
        entry = { achievements = {}, items = {} }
        index[questID] = entry
    end
    return entry
end

local function AddAchievementQuest(questID, achievementID, done)
    if type(questID) ~= "number" or questID <= 0 then return end
    local a = Want(questID).achievements
    -- Missing for any criterion wins over finished for another.
    if a[achievementID] == nil or a[achievementID] == true then a[achievementID] = done end
end

-- One achievement from the data. showAll lists finished ones (done = true).
local function RegisterAchievement(ach, parentDone)
    if type(ach) ~= "table" or not ach.id then return end
    local kind = ach.criteriaType
    if kind == "SPECIAL" or kind == "MISSION_TABLE" or kind == "AREA_POI" or kind == "QUEST_PIN" then return end
    local faction = MyFaction()
    if ach.faction and faction and ach.faction ~= faction then return end

    local ok, _, _, _, completed, _, _, _, _, _, _, _, _, earnedByMe = pcall(GetAchievementInfo, ach.id)
    if not ok then return end
    completed = Plain(completed) and true or false
    if ach.notAccountwide then completed = Plain(earnedByMe) and true or false end
    if completed and not settings.showAll then return end
    local achDone = completed or parentDone or false

    if kind == "ACHIEVEMENT" then
        for _, sub in pairs(ach.criteria or {}) do RegisterAchievement(sub, achDone) end
        return
    end
    if kind == "QUEST_SINGLE" then
        local list = type(ach.criteria) == "table" and ach.criteria or { ach.criteria }
        for _, questID in pairs(list) do AddAchievementQuest(questID, ach.id, achDone) end
        return
    end
    if kind == "QUEST_FLAG" then
        -- Done once the hidden quest flag is set on this character.
        local flagged = Known(C_QuestLog.IsQuestFlaggedCompleted, ach.criteria)
        if flagged and not settings.showAll then return end
        AddAchievementQuest(ach.criteria, ach.id, achDone or flagged == true)
        return
    end

    -- Criterion by criterion: each one's own completion, from the game.
    local okCount, count = pcall(GetAchievementNumCriteria, ach.id)
    count = okCount and Plain(count) or 0
    if count == 0 and kind == "QUESTS" and ach.criteria then
        local c = ach.criteria[1]
        for _, questID in pairs(type(c) == "table" and c or { c }) do AddAchievementQuest(questID, ach.id, achDone) end
        return
    end
    for i = 1, count do
        local okC, _, _, critDone, _, _, _, _, assetID = pcall(GetAchievementCriteriaInfo, ach.id, i)
        if okC then
            critDone = Plain(critDone) and true or false
            if not critDone or settings.showAll then
                local done = achDone or critDone
                if kind == "QUESTS" then
                    local c = ach.criteria and ach.criteria[i]
                    if type(c) == "table" then
                        for _, questID in pairs(c) do AddAchievementQuest(questID, ach.id, done) end
                    elseif c then
                        AddAchievementQuest(c, ach.id, done)
                    end
                else
                    -- The criterion names its own quest.
                    AddAchievementQuest(Plain(assetID), ach.id, done)
                end
            end
        end
    end
end

-- Collectibles: whether this account already has it, from the journals.
local function MountCollected(itemID, spellID)
    if not C_MountJournal then return nil end
    local mountID
    if spellID and C_MountJournal.GetMountFromSpell then mountID = C_MountJournal.GetMountFromSpell(spellID) end
    if not mountID and itemID and C_MountJournal.GetMountFromItem then mountID = C_MountJournal.GetMountFromItem(itemID) end
    if not mountID then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, isCollected = pcall(C_MountJournal.GetMountInfoByID, mountID)
    if not ok then return nil end
    return Plain(isCollected) and true or false
end

local function PetCollected(itemID)
    if not (C_PetJournal and C_PetJournal.GetPetInfoByItemID) then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, speciesID = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
    speciesID = ok and Plain(speciesID)
    if type(speciesID) ~= "number" then return nil end
    local okN, owned = pcall(C_PetJournal.GetNumCollectedInfo, speciesID)
    owned = okN and Plain(owned)
    if type(owned) ~= "number" then return nil end
    return owned > 0
end

local function ToyCollected(itemID)
    if not (C_ToyBox and C_ToyBox.GetToyInfo) then return nil end
    -- A toy only when the toy box knows it by this very item and by name;
    -- anything less and it is not called a toy.
    local ok, toyID, toyName = pcall(C_ToyBox.GetToyInfo, itemID)
    if not ok or Plain(toyID) ~= itemID or type(Plain(toyName)) ~= "string" or toyName == "" then return nil end
    return PlayerHasToy(itemID) and true or false
end

local function Collected(kind, itemID, spellID)
    if kind == "mount" then return MountCollected(itemID, spellID) end
    if kind == "pet" then return PetCollected(itemID) end
    if kind == "toy" then return ToyCollected(itemID) end
    return nil
end

local WANT_KEY = { mount = "wantMount", pet = "wantPet", toy = "wantToy" }

local function AddItemQuest(questID, kind, itemID, spellID)
    if not (settings[WANT_KEY[kind]] and questID and itemID) then return end
    local have = Collected(kind, itemID, spellID)
    if have == nil then return end          -- the journal does not know it: not listed
    if have and not settings.showAll then return end
    Want(questID).items[itemID] = { kind = kind, done = have }
end

local function Expansions()
    if settings.expansions == "all" then
        local list = {}
        for exp in pairs(Data.data) do list[#list + 1] = exp end
        table.sort(list, function(a, b) return a > b end)
        return list
    end
    return { CURRENT_EXPANSION }
end

local function BuildIndex()
    wipe(index)
    local faction = MyFaction()
    for _, exp in ipairs(Expansions()) do
        local d = Data.data[exp]
        if d then
            if settings.wantAchieve then
                for _, ach in ipairs(d.achievements or {}) do RegisterAchievement(ach, false) end
            end
            for kind, list in pairs({ mount = d.mounts, pet = d.pets, toy = d.toys }) do
                for _, c in ipairs(list or {}) do
                    if not (c.faction and faction and c.faction ~= faction) then
                        for _, q in ipairs(c.quest or {}) do AddItemQuest(q.wqID, kind, c.itemID, c.spellID) end
                    end
                end
            end
        end
    end
end

-- ── The world quests up now ─────────────────────────────────────────────────

local results = {}        -- built by the scan, read by the window
local announced = {}      -- questID .. ":" .. reward, once per session
local scanning = false
local scanAgain = false
local pending = {}        -- [questID] = tries, rewards not loaded yet

local function QuestsOnMap(mapID)
    local fn = C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)
    if not fn then return nil end
    local ok, list = pcall(fn, mapID)
    if ok and type(list) == "table" then return list end
    return nil
end

-- Collectibles in a quest's own rewards: also right for quests the data has
-- never heard of. nil while the reward data is still loading.
local function RewardCollectibles(questID)
    if not HaveQuestRewardData(questID) then
        if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then C_TaskQuest.RequestPreloadRewardData(questID) end
        return nil
    end
    local found = {}
    for i = 1, GetNumQuestLogRewards(questID) or 0 do
        local _, _, _, _, _, itemID = GetQuestLogRewardInfo(i, questID)
        itemID = Plain(itemID)
        if type(itemID) == "number" then
            for _, kind in ipairs({ "mount", "pet", "toy" }) do
                if settings[WANT_KEY[kind]] then
                    local have = Collected(kind, itemID)
                    if have ~= nil and (not have or settings.showAll) then
                        found[itemID] = { kind = kind, done = have }
                        break
                    end
                end
            end
        end
    end
    return found
end

local Refresh   -- the window; defined below

local function Announce(r)
    if not settings.announce then return false end
    local said = false
    for achievementID, done in pairs(r.achievements) do
        local key = r.questID .. ":a" .. achievementID
        if not done and not announced[key] then
            announced[key] = true
            print(PREFIX .. ("%s  %s |cff9d9d9d(%s, %s)|r"):format(AchievementLink(achievementID) or AchievementName(achievementID),
                r.title, r.zone, TimeLeft(r.left)))
            said = true
        end
    end
    for itemID, item in pairs(r.items) do
        local key = r.questID .. ":i" .. itemID
        if not item.done and not announced[key] then
            announced[key] = true
            local _, link = GetItemInfo(itemID)
            print(PREFIX .. ("%s %s  %s |cff9d9d9d(%s, %s)|r"):format(item.kind, link or ("item " .. itemID), r.title, r.zone, TimeLeft(r.left)))
            said = true
        end
    end
    return said
end

local function FinishScan(found)
    wipe(results)
    local anyNew = false
    for _, r in ipairs(found) do
        results[#results + 1] = r
        if Announce(r) then anyNew = true end
    end
    table.sort(results, function(a, b)
        if a.exp ~= b.exp then return a.exp > b.exp end
        if a.zone ~= b.zone then return a.zone < b.zone end
        return (a.left or 0) < (b.left or 0)
    end)
    scanning = false
    if anyNew and settings.openOnFind and window and not window:IsShown() then window:Show() end
    if Refresh then Refresh() end
    if scanAgain then
        scanAgain = false
        C_Timer.After(1, function() if running then GoScan() end end)
    elseif next(pending) then
        -- Rewards still loading: one more look a little later, a few times at most.
        C_Timer.After(3, function() if running then GoScan() end end)
    end
end

-- Maps a few at a time, so a long list of zones never costs one long frame.
GoScan = function()
    if not running then return end
    if scanning then scanAgain = true return end
    if InCombatLockdown() then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    scanning = true
    BuildIndex()

    local maps = {}
    for _, exp in ipairs(Expansions()) do
        for _, mapID in ipairs(Data.ZoneIDList[exp] or {}) do maps[#maps + 1] = { mapID = mapID, exp = exp } end
    end
    local seen, found = {}, {}
    local stillPending = {}
    local step = 0

    local function Step()
        if not running then scanning = false return end
        for _ = 1, 4 do
            step = step + 1
            local m = maps[step]
            if not m then
                for questID, tries in pairs(pending) do
                    if stillPending[questID] then stillPending[questID] = tries + 1 end
                end
                wipe(pending)
                for questID, tries in pairs(stillPending) do
                    if tries < 6 then pending[questID] = tries end
                end
                FinishScan(found)
                return
            end
            for _, info in ipairs(QuestsOnMap(m.mapID) or {}) do
                local questID = Plain(info.questID)
                if type(questID) == "number" and not seen[questID] then
                    seen[questID] = true
                    local isWQ = Known(C_QuestLog.IsWorldQuest, questID)
                    local want = index[questID]
                    if isWQ or want then
                        local r = {
                            questID = questID, exp = m.exp,
                            mapID = Plain(info.mapID) or m.mapID,
                            achievements = {}, items = {},
                        }
                        if want then
                            for id, done in pairs(want.achievements) do r.achievements[id] = done end
                            for id, item in pairs(want.items) do r.items[id] = item end
                        end
                        if isWQ then
                            local extra = RewardCollectibles(questID)
                            if extra == nil then
                                stillPending[questID] = pending[questID] or 0
                            else
                                for id, item in pairs(extra) do r.items[id] = r.items[id] or item end
                            end
                        end
                        if next(r.achievements) or next(r.items) then
                            r.title = QuestTitle(questID)
                            r.zone = MapName(r.mapID)
                            r.left = C_TaskQuest.GetQuestTimeLeftSeconds and Plain(C_TaskQuest.GetQuestTimeLeftSeconds(questID))
                            found[#found + 1] = r
                        end
                    end
                end
            end
        end
        C_Timer.After(0, Step)
    end
    Step()
end

-- ── The window ──────────────────────────────────────────────────────────────

local ROW_H = 18
local EXP_NAMES = {
    [7] = EXPANSION_NAME6, [8] = EXPANSION_NAME7, [9] = EXPANSION_NAME8,
    [10] = EXPANSION_NAME9, [11] = EXPANSION_NAME10, [12] = EXPANSION_NAME11,
}
local KIND_LABEL = { mount = "Mount", pet = "Pet", toy = "Toy" }

local function OpenAchievement(id)
    if not AchievementFrame then
        local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if load then pcall(load, "Blizzard_AchievementUI") end
    end
    if OpenAchievementFrameToAchievement then
        pcall(OpenAchievementFrameToAchievement, id)
    end
end

local function InsertLink(link)
    if not link then return end
    if ChatEdit_InsertLink then ChatEdit_InsertLink(link)
    elseif ChatFrameUtil and ChatFrameUtil.InsertLink then ChatFrameUtil.InsertLink(link) end
end

-- A web address to copy, in the game's own popup.
local function ShowWebLink(kind, id)
    StaticPopupDialogs.OXEDHUB_WQA_LINK = StaticPopupDialogs.OXEDHUB_WQA_LINK or {
        text = L["Copy with Ctrl+C:"],
        button1 = CLOSE or L["Close"],
        hasEditBox = true,
        editBoxWidth = 320,
        OnShow = function(self, data)
            local box = self.editBox or self.EditBox
            if box then
                box:SetText(data or "")
                box:HighlightText()
                box:SetFocus()
            end
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("OXEDHUB_WQA_LINK", nil, nil, ("https://www.wowhead.com/%s=%d"):format(kind, id))
end

local function ShowQuestOnMap(r)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, r.questID) end
    if not InCombatLockdown() and OpenWorldMap then pcall(OpenWorldMap, r.mapID) end
end

local function GetRow(i)
    local rows = window.rows
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, window.content)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", window.content, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        self.tip(GameTooltip)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

local function SetRow(i, indent, icon, text, right, onClick, tip)
    local row = GetRow(i)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", row, "LEFT", 4 + indent, 0)
    row.icon:SetShown(icon ~= nil)
    if icon then row.icon:SetTexture(icon) end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", row, "LEFT", 4 + indent + (icon and 18 or 0), 0)
    row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.text:SetText(text)
    row.right:SetText(right or "")
    row:SetScript("OnClick", onClick)
    row.tip = tip
    row:Show()
end

Refresh = function()
    if not (window and window:IsShown()) then return end
    local n = 0
    local lastExp, lastZone
    local count = 0
    for _, r in ipairs(results) do
        if r.exp ~= lastExp then
            lastExp, lastZone = r.exp, nil
            n = n + 1
            SetRow(n, 0, nil, "|cffffd100" .. (EXP_NAMES[r.exp] or (L["Expansion "] .. r.exp)) .. "|r")
        end
        if r.zone ~= lastZone then
            lastZone = r.zone
            n = n + 1
            SetRow(n, 6, nil, "|cffffffff" .. r.zone .. "|r")
        end
        count = count + 1
        n = n + 1
        SetRow(n, 14, "Interface\\GossipFrame\\WorldQuestIcon", r.title, TimeLeft(r.left),
            function() ShowQuestOnMap(r) end,
            function(tt)
                tt:SetText(r.title)
                tt:AddLine(r.zone, 0.8, 0.8, 0.8)
                tt:AddLine(L["Click: show it on the map."], 0.4, 1, 0.4)
            end)
        for achievementID, done in pairs(r.achievements) do
            local okI, _, _, _, _, _, _, _, _, _, achIcon = pcall(GetAchievementInfo, achievementID)
            local link = AchievementLink(achievementID)
            n = n + 1
            SetRow(n, 30, okI and Plain(achIcon) or nil,
                (done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "") .. (link or AchievementName(achievementID)),
                done and "|cff40ff40done|r" or "",
                function(_, mouse)
                    if mouse == "RightButton" then
                        ShowWebLink("achievement", achievementID)
                    elseif IsShiftKeyDown() then
                        InsertLink(link)
                    else
                        OpenAchievement(achievementID)
                    end
                end,
                function(tt)
                    if link then tt:SetHyperlink(link) else tt:SetText(AchievementName(achievementID)) end
                    tt:AddLine(" ")
                    tt:AddLine(L["Click: open it. Shift-click: link in chat. Right-click: web link."], 0.4, 1, 0.4, true)
                end)
        end
        for itemID, item in pairs(r.items) do
            local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            n = n + 1
            SetRow(n, 30, icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)),
                (item.done and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "") .. (link or name or ("item " .. itemID)),
                (item.done and "|cff40ff40have|r " or "") .. "|cff9d9d9d" .. KIND_LABEL[item.kind] .. "|r",
                function(_, mouse)
                    if mouse == "RightButton" then
                        ShowWebLink("item", itemID)
                    elseif IsShiftKeyDown() then
                        InsertLink(link)
                    end
                end,
                function(tt)
                    tt:SetItemByID(itemID)
                    tt:AddLine(" ")
                    tt:AddLine(L["Shift-click: link in chat. Right-click: web link."], 0.4, 1, 0.4, true)
                end)
        end
    end
    if n == 0 then
        n = 1
        SetRow(1, 0, nil, scanning and L["|cff9d9d9dLooking at the world quests...|r"]
            or L["|cff9d9d9dNothing up right now that you still need. Try All expansions, or Show all.|r"])
    end
    for i = n + 1, #window.rows do window.rows[i]:Hide() end
    window.content:SetHeight(n * ROW_H)
    window.count:SetText((L["%d quest(s)"]):format(count))
    window.modeButton:SetText(settings.showAll and L["Showing: all"] or L["Showing: still needed"])
    window.expButton:SetText(settings.expansions == "all" and L["All expansions"] or (EXP_NAMES[CURRENT_EXPANSION] or L["Current"]))
end

local ShowOptions   -- defined below

local function BuildWindow()
    if window then return end
    local f = CreateFrame("Frame", "OxedHubWQAchievementsWindow", UIParent, "BasicFrameTemplate")
    f:SetSize(440, 460)
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
    if f.TitleText then f.TitleText:SetText("WQ Achievements") end
    if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end
    tinsert(UISpecialFrames, "OxedHubWQAchievementsWindow")
    f.rows = {}

    local function Button(text, width, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    f.modeButton = Button("", 140, function()
        settings.showAll = not settings.showAll
        GoScan()
        Refresh()
    end)
    f.modeButton:SetPoint("TOPLEFT", 10, -28)
    f.expButton = Button("", 120, function()
        settings.expansions = settings.expansions == "all" and "current" or "all"
        GoScan()
        Refresh()
    end)
    f.expButton:SetPoint("LEFT", f.modeButton, "RIGHT", 6, 0)
    local rescan = Button(L["Rescan"], 70, function() GoScan() Refresh() end)
    rescan:SetPoint("LEFT", f.expButton, "RIGHT", 6, 0)
    local opt = Button(L["Options"], 70, function() ShowOptions() end)
    opt:SetPoint("LEFT", rescan, "RIGHT", 6, 0)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 10, -56)
    scroll:SetPoint("BOTTOMRIGHT", -30, 28)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(390, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    f.content = content

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.count:SetPoint("BOTTOMLEFT", 14, 10)

    f:SetScript("OnShow", function() Refresh() end)
    window = f
end

-- ── Screenshot on an achievement ────────────────────────────────────────────

local function OnAchievementEarned(achievementID, alreadyEarned)
    if not settings.screenshot then return end
    if settings.screenshotNew and Plain(alreadyEarned) then return end
    -- A moment later, so the game's own toast is in the picture.
    C_Timer.After(1.2, function()
        if running and Screenshot then pcall(Screenshot) end
    end)
end

-- ── Quest marks on nameplates ───────────────────────────────────────────────
-- Over the nameplate of a mob your quest log needs. The game knows whether a
-- unit is part of an active quest; in combat that answer can be a secret, and
-- then the mark hides or shows itself from it without Lua looking.

local marks = {}          -- [nameplate] = our mark
local plateUnits = {}     -- [unit token] = nameplate

local function MarkFor(plate)
    local mark = marks[plate]
    if mark then return mark end
    mark = CreateFrame("Frame", nil, plate)
    mark:SetFrameStrata("HIGH")
    mark.icon = mark:CreateTexture(nil, "OVERLAY")
    mark.icon:SetAllPoints()
    if not pcall(mark.icon.SetAtlas, mark.icon, "QuestNormal") then
        mark.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    end
    marks[plate] = mark
    return mark
end

-- Out of combat, when the game cannot say directly: the unit's tooltip lists
-- quest objectives it counts for.
local function TooltipSaysQuest(unit)
    if InCombatLockdown() or not (C_TooltipInfo and C_TooltipInfo.GetUnit and Enum and Enum.TooltipDataLineType) then return nil end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" or IsSecret(data) or type(data.lines) ~= "table" then return nil end
    local objective = Enum.TooltipDataLineType.QuestObjective
    for _, line in ipairs(data.lines) do
        if not IsSecret(line) and line.type == objective and not Plain(line.completed) then return true end
    end
    return false
end

local function UpdatePlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    plateUnits[unit] = plate
    local mark = MarkFor(plate)
    -- A player is never a quest's mob. A secret answer is not a no: the quest
    -- check below still decides, and says no for players anyway.
    if not settings.plateMarks or Known(UnitIsPlayer, unit) == true then
        mark:Hide()
        return
    end
    local size = tonumber(settings.plateMarkSize) or 22
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    mark:SetPoint("BOTTOM", plate, "TOP", 0, 2)

    local fn = C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest
    if fn then
        local ok, related = pcall(fn, unit)
        if ok then
            if IsSecret(related) then
                mark:Show()
                mark:SetAlphaFromBoolean(related, 0, 1)
            else
                mark:SetAlpha(1)
                mark:SetShown(related and true or false)
            end
            return
        end
    end
    local says = TooltipSaysQuest(unit)
    if says ~= nil then
        mark:SetAlpha(1)
        mark:SetShown(says)
    end
end

local function UpdateAllPlates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and not IsSecret(unit) then UpdatePlate(unit) end
    end
end

local function HideAllMarks()
    for _, mark in pairs(marks) do mark:Hide() end
end

local platesQueued = false
local function QueuePlates()
    if platesQueued then return end
    platesQueued = true
    C_Timer.After(0.5, function()
        platesQueued = false
        if running and settings.plateMarks then UpdateAllPlates() end
    end)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local scanQueued = false
local function QueueScan(delay)
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(delay or 2, function()
        scanQueued = false
        GoScan()
    end)
end

events:SetScript("OnEvent", function(self, event, arg1, arg2)
    if not running then return end
    if event == "NAME_PLATE_UNIT_ADDED" then
        if settings.plateMarks then UpdatePlate(arg1) end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = plateUnits[arg1]
        if plate and marks[plate] then marks[plate]:Hide() end
        plateUnits[arg1] = nil
    elseif event == "QUEST_LOG_UPDATE" or event == "UNIT_QUEST_LOG_CHANGED" or event == "QUEST_WATCH_UPDATE" then
        QueuePlates()
    elseif event == "ACHIEVEMENT_EARNED" then
        OnAchievementEarned(arg1, arg2)
        QueueScan(3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        QueueScan(1)
        QueuePlates()
    elseif event == "QUEST_TURNED_IN" or event == "NEW_MOUNT_ADDED" or event == "NEW_PET_ADDED"
        or event == "NEW_TOY_ADDED" or event == "CRITERIA_EARNED" then
        QueueScan(3)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        QueueScan(5)
    end
end)

local EVENTS = {
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
    "QUEST_WATCH_UPDATE", "ACHIEVEMENT_EARNED", "CRITERIA_EARNED", "QUEST_TURNED_IN",
    "NEW_MOUNT_ADDED", "NEW_PET_ADDED", "NEW_TOY_ADDED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
}

-- Rescanned every few minutes: world quests come and go on their own.
local ticker

local function Start()
    if running then return end
    running = true
    for _, e in ipairs(EVENTS) do pcall(events.RegisterEvent, events, e) end
    if not ticker then ticker = C_Timer.NewTicker(300, function() if running then GoScan() end end) end
    QueueScan(6)
    QueuePlates()
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    if ticker then ticker:Cancel() ticker = nil end
    HideAllMarks()
    if window then window:Hide() end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function Rebuild()
    if running then GoScan() end
    Refresh()
end

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("WQ Achievements", 470, 628)
        optionsWindow = w
        w:AddChoice(settings, "showAll", "Achievements shown", {
            { value = false, text = L["Still needed only"] },
            { value = true,  text = L["All, finished ticked"] },
        }, Rebuild)
        w:AddChoice(settings, "expansions", "Expansions", {
            { value = "current", text = EXPANSION_NAME11 or L["Current"] },
            { value = "all",     text = L["All expansions"] },
        }, Rebuild)
        w:AddNote("|cffffd100Rewards to look for|r")
        w:AddCheckbox(settings, "wantAchieve", "Achievements", nil, Rebuild)
        w:AddCheckbox(settings, "wantMount", "Mounts you do not have", nil, Rebuild)
        w:AddCheckbox(settings, "wantPet", "Pets you do not have", nil, Rebuild)
        w:AddCheckbox(settings, "wantToy", "Toys you do not have", nil, Rebuild)
        w:AddNote("|cffffd100When something turns up|r")
        w:AddCheckbox(settings, "announce", "Say it in chat, with the achievement linked")
        w:AddCheckbox(settings, "openOnFind", "Open the window")
        w:AddNote("|cffffd100Achievement screenshots|r")
        w:AddCheckbox(settings, "screenshot", "Take a screenshot when an achievement is earned")
        w:AddCheckbox(settings, "screenshotNew", "Only achievements new to this character")
        w:AddNote("|cffffd100Quest marks|r")
        w:AddCheckbox(settings, "plateMarks", "Quest mark over nameplates your quest log needs", nil, function(on)
            if on then UpdateAllPlates() else HideAllMarks() end
        end)
        w:AddSlider(settings, "plateMarkSize", "Mark size", 12, 40, 2, "%s: %d", function() UpdateAllPlates() end)
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)
        w:AddNote("/wqach opens the list. Click a quest to see it on the map; click an achievement to open it, "
            .. "shift-click to link it, right-click for a web link. Objects on the ground have no nameplate; "
            .. "the game's own sparkle marks those.")
    end
    optionsWindow:Show()
end

local function Toggle()
    if not running then
        print(PREFIX .. L["switched off. Switch it on in OxedHub's Modules page first."])
        return
    end
    BuildWindow()
    if window:IsShown() then
        window:Hide()
    else
        window:Show()
        GoScan()
    end
end

SLASH_OXEDWQACH1 = "/wqach"
SLASH_OXEDWQACH2 = "/oxwqa"
SlashCmdList.OXEDWQACH = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "options" or msg == "config" then
        ShowOptions()
    elseif msg == "scan" then
        GoScan()
        print(PREFIX .. L["looking at the world quests again."])
    else
        Toggle()
    end
end

-- ── Login ───────────────────────────────────────────────────────────────────

-- Its own icon on the minimap, like the other modules with a window: a click
-- opens the list, a right-click the options.
MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "wqachievements", label = L["WQ Achievements"], icon = "Interface\\Icons\\INV_Misc_Map06", config = settings,
        hint = L["Click: the list. Right-click: options."],
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
    local config = OxedHubDB.modules.wqachievements
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.wqachievements = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "wqachievements",
        name     = "WQ Achievements",
        version  = "1.1.0",
        updated  = 20261025.1,  -- its own minimap button
        author   = "Oxed",
        category = "quests",
        keywords = { "world quest", "wq", "achievement", "mount", "pet", "toy", "screenshot", "nameplate", "quest mark" },
        desc     = "World quests up now that count toward achievements, mounts, pets or toys you still need.",
        icon     = "Interface\\Icons\\INV_Misc_Map06",
        defaults = DEFAULTS,
        quick = {
            { text = L["Show or hide"], func = function() Toggle() end },
        },
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
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
