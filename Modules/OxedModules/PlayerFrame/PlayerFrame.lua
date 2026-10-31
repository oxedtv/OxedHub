-- ============================================================================
-- Player Frame (built-in OxedHub module)
-- Small fixes to Blizzard's own player frame, each one its own switch:
--
--   * Tidier corner: the play-time warning, PvP badge and honour portrait
--     smaller, the "in combat" swords red with a glow, left of your name.
--   * Your raid group as a number next to the level, the level hidden at
--     max level, the heal / damage numbers smaller under the portrait.
--   * The frame's border in your class colour.
--   * A row of small buttons over the portrait: dungeon and raid difficulty,
--     loot specialization, War Mode, and your Mythic+ rating with this
--     week's runs (your key in the tooltip). Click does the quick thing,
--     right-click opens a menu to pick. As raid leader, the crown toggles
--     "everyone is an assistant".
--   * Item level (equipped / overall) and a spec button to switch spec.
--   * All three pieces can be dragged into place and locked (/oxpf move).
--
-- Idea from WoWTools' Plus_UnitFrame (MIT, husandro); written for OxedHub.
--
-- PlayerFrame is a secure frame. Its regions are only moved out of combat:
-- anything that would happen in a fight waits for PLAYER_REGEN_ENABLED. The
-- button row is anchored to it, which makes the row protected too, so its
-- show / hide follows the same rule. OnDisable puts every region back where
-- Blizzard had it.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled      = false,  -- off until the player switches it on (see ModuleAPI:Register)
    tidyCorner   = true,   -- play-time, PvP and honour badges smaller
    combatIcon   = true,   -- red "in combat" swords with a glow, left of the name
    groupNumber  = true,   -- raid group as a number next to the level
    hideMaxLevel = true,   -- no level text at max level
    hitText      = true,   -- heal / damage numbers smaller, under the portrait
    classBorder  = true,   -- frame border in the class colour
    lootButton   = true,
    lootAlways   = false,  -- false: only when loot spec differs from your spec
    difficulty   = true,   -- dungeon and raid difficulty buttons
    warMode      = true,   -- War Mode button
    keystone     = true,   -- Mythic+ rating, runs this week, your key in the tooltip
    assistToggle = true,
    itemLevel    = true,   -- "equipped / overall" item level
    specButton   = true,   -- your spec, click to switch
}

local settings
local optionsWindow
local watcher = CreateFrame("Frame")
local PREFIX = "|cff00ff00OxedHub:|r "
local BUTTON = 20

local function Active(option)
    return settings and settings.enabled == true and (option == nil or settings[option] ~= false)
end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Contextual()
    if PlayerFrame_GetPlayerFrameContentContextual then
        local ok, c = pcall(PlayerFrame_GetPlayerFrameContentContextual)
        if ok and c then return c end
    end
    local content = PlayerFrame and PlayerFrame.PlayerFrameContent
    return content and content.PlayerFrameContentContextual
end

local function Portrait()
    local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
    return container and container.PlayerPortrait
end

local function HitText()
    local main = PlayerFrame and PlayerFrame.PlayerFrameContent and PlayerFrame.PlayerFrameContent.PlayerFrameContentMain
    return main and main.HitIndicator and main.HitIndicator.HitText
end

-- ── Remembering Blizzard's layout ───────────────────────────────────────────
-- Every region we move is recorded once, before the first change, so
-- OnDisable can hand it back exactly.

local saved = {}

local function Remember(region)
    if not region or saved[region] then return end
    local points = {}
    for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
    local s = { points = points, scale = region:GetScale() }
    if region.GetSize then s.w, s.h = region:GetSize() end
    if region.GetVertexColor then s.r, s.g, s.b, s.a = region:GetVertexColor() end
    s.alpha = region:GetAlpha()
    saved[region] = s
end

local function Restore(region)
    local s = region and saved[region]
    if not s then return end
    region:ClearAllPoints()
    for _, p in ipairs(s.points) do region:SetPoint(unpack(p)) end
    region:SetScale(s.scale)
    if s.w and s.w > 0 then region:SetSize(s.w, s.h) end
    if s.r and region.SetVertexColor then region:SetVertexColor(s.r, s.g, s.b, s.a) end
    region:SetAlpha(s.alpha)
end

local function RestoreAll()
    for region in pairs(saved) do Restore(region) end
end

-- ── The layout changes ──────────────────────────────────────────────────────

local combatGlow

local function ApplyCorner(c)
    if c.PlayerPlayTime and c.GuideIcon then
        Remember(c.PlayerPlayTime)
        c.PlayerPlayTime:ClearAllPoints()
        c.PlayerPlayTime:SetPoint("RIGHT", c.GuideIcon, "LEFT")
        c.PlayerPlayTime:SetSize(20, 20)
    end
    if c.PVPIcon and Portrait() then
        Remember(c.PVPIcon)
        c.PVPIcon:SetSize(25, 25)
        c.PVPIcon:ClearAllPoints()
        c.PVPIcon:SetPoint("RIGHT", Portrait(), "LEFT", 13, -24)
    end
    for _, region in ipairs({ c.PrestigePortrait or false, c.PrestigeBadge or false }) do
        if region then
            Remember(region)
            region:SetScale(0.6)
        end
    end
    if c.PlayerPortraitCornerIcon and Portrait() then
        Remember(c.PlayerPortraitCornerIcon)
        c.PlayerPortraitCornerIcon:ClearAllPoints()
        c.PlayerPortraitCornerIcon:SetPoint("BOTTOMRIGHT", Portrait(), 2, -2)
    end
end

local function ApplyCombatIcon(c)
    local icon = c.AttackIcon
    if not (icon and PlayerName) then return end
    Remember(icon)
    icon:ClearAllPoints()
    icon:SetPoint("RIGHT", PlayerName, "LEFT", -2, 0)
    icon:SetVertexColor(1, 0, 0)
    if not combatGlow then
        combatGlow = c:CreateTexture(nil, "BACKGROUND")
        combatGlow:SetAtlas("talents-node-choiceflyout-circle-greenglow")
        combatGlow:SetPoint("TOPLEFT", icon, -4, 4)
        combatGlow:SetPoint("BOTTOMRIGHT", icon, 4, -4)
        icon:HookScript("OnShow", function() if Active("combatIcon") then combatGlow:Show() end end)
        icon:HookScript("OnHide", function() combatGlow:Hide() end)
    end
    combatGlow:SetShown(icon:IsShown())
end

local function PaintGroupText()
    local text = PlayerFrameGroupIndicatorText
    if not (text and Active("groupNumber") and text:IsVisible()) then return end
    local raw = Plain(text:GetText())
    local num = type(raw) == "string" and raw:match("(%d)")
    if num then text:SetFormattedText("|A:services-number-%s:22:22|a", num) end
end

local function ApplyGroupNumber(c)
    local text = PlayerFrameGroupIndicatorText
    if not (text and PlayerLevelText) then return end
    Remember(text)
    text:ClearAllPoints()
    text:SetPoint("RIGHT", PlayerLevelText, "LEFT")
    if c.GroupIndicator then
        Remember(c.GroupIndicator)
        c.GroupIndicator:SetAlpha(0)
    end
    PaintGroupText()
end

local function PaintLevel()
    if not (PlayerLevelText and Active("hideMaxLevel")) then return end
    Remember(PlayerLevelText)
    local level = Plain(UnitEffectiveLevel and UnitEffectiveLevel(PlayerFrame and PlayerFrame.unit or "player"))
    local max = GetMaxLevelForLatestExpansion and GetMaxLevelForLatestExpansion()
    PlayerLevelText:SetAlpha(level and max and level == max and 0 or 1)
end

local function ApplyHitText()
    local hit, portrait = HitText(), Portrait()
    if not (hit and portrait) then return end
    Remember(hit)
    hit:SetScale(0.75)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", portrait, "BOTTOMLEFT", 0, -5)
end

local function ApplyClassBorder()
    local frame = PlayerFrame and PlayerFrame.PlayerFrameContainer and PlayerFrame.PlayerFrameContainer.FrameTexture
    if not frame then return end
    Remember(frame)
    local colour = PlayerUtil and PlayerUtil.GetClassColor and PlayerUtil.GetClassColor()
    if colour then frame:SetVertexColor(colour:GetRGB()) end
end

-- ── Buttons around the portrait ─────────────────────────────────────────────
-- Three pieces, each movable (settings.offsets[key], dragged in move mode):
--   row   dungeon difficulty, raid difficulty, loot spec, War Mode, Mythic+
--   ilvl  "equipped / overall" item level
--   spec  your specialization, click to switch
-- Left-click does the quick thing, right-click opens a menu to pick.

local row, dungeonButton, raidButton, lootButton, pvpButton, keyButton, assistButton
local ilvlFrame, specButton
local pieces = {}   -- key -> { frame, point, rel, relPoint, x, y }
local moving = false

local function SpecIndex()
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    end
    return GetSpecialization and GetSpecialization()
end

local function SpecInfo(index)
    local get = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    if not (get and index) then return nil end
    local id, name, _, icon = get(index)
    return id, name, icon
end

local function SpecByID(specID)
    if not (GetSpecializationInfoByID and specID and specID > 0) then return nil end
    local _, name, _, icon = GetSpecializationInfoByID(specID)
    return name, icon
end

local function NumSpecs()
    return GetNumSpecializations and GetNumSpecializations() or 0
end

local function IsLeaderOrSolo()
    return not IsInGroup() or UnitIsGroupLeader("player")
end

local function Menu(owner, build)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root) build(root) end)
end

local function MakeButton(name, parent, size)
    local b = CreateFrame("Button", name, parent)
    b:SetSize(size or BUTTON, size or BUTTON)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnEnter", function(self)
        if not self.Tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        self:Tip(GameTooltip)
        GameTooltip:Show()
    end)
    return b
end

local function Retip(b)
    C_Timer.After(0.4, function()
        if b:IsMouseOver() and b:GetScript("OnEnter") then b:GetScript("OnEnter")(b) end
    end)
end

-- ── Moving the pieces ───────────────────────────────────────────────────────

local function Offset(key)
    local o = settings and settings.offsets and settings.offsets[key]
    if type(o) ~= "table" then return 0, 0 end
    return tonumber(o.x) or 0, tonumber(o.y) or 0
end

local function PlacePiece(key)
    local p = pieces[key]
    if not p or InCombatLockdown() then return end
    local dx, dy = Offset(key)
    p[1]:ClearAllPoints()
    p[1]:SetPoint(p[2], p[3], p[4], p[5] + dx, p[6] + dy)
end

local function AddPiece(key, frame, label, point, rel, relPoint, x, y)
    pieces[key] = { frame, point, rel, relPoint, x, y }
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- A blue cover over the piece while moving; it takes the drag so the
    -- buttons underneath are not pressed.
    local m = CreateFrame("Frame", nil, frame)
    m:SetAllPoints()
    m:SetFrameLevel(frame:GetFrameLevel() + 20)
    m:EnableMouse(true)
    m:RegisterForDrag("LeftButton")
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    m.bg:SetColorTexture(0, 0.6, 1, 0.45)
    m.text = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.text:SetPoint("CENTER")
    m.text:SetText(label)
    m:SetScript("OnDragStart", function()
        m.startX, m.startY = GetCursorPosition()
        frame:StartMoving()
    end)
    m:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local x2, y2 = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        local dx, dy = Offset(key)
        settings.offsets[key] = {
            x = math.floor(dx + (x2 - (m.startX or x2)) / scale + 0.5),
            y = math.floor(dy + (y2 - (m.startY or y2)) / scale + 0.5),
        }
        PlacePiece(key)
    end)
    m:SetScript("OnMouseUp", function(_, button)
        if button ~= "RightButton" then return end
        settings.offsets[key] = nil
        PlacePiece(key)
    end)
    m:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(label)
        GameTooltip:AddLine(L["Drag to move. Right-click to put it back."], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:Hide()
    frame.mover = m
    PlacePiece(key)
end

-- ── Difficulty ──────────────────────────────────────────────────────────────

local DUNGEON_CHOICES = { { 1, "Normal" }, { 2, "Heroic" }, { 23, "Mythic" } }
local RAID_CHOICES    = { { 14, "Normal" }, { 15, "Heroic" }, { 16, "Mythic" } }
OxedHub:RegisterLocalizedTable(DUNGEON_CHOICES, 2)
OxedHub:RegisterLocalizedTable(RAID_CHOICES, 2)
local DIFF_COLOUR = { [1] = { 0.2, 1, 0.2 }, [2] = { 0.2, 0.6, 1 }, [23] = { 0.85, 0.3, 1 },
                      [14] = { 0.2, 1, 0.2 }, [15] = { 0.2, 0.6, 1 }, [16] = { 0.85, 0.3, 1 } }
local DIFF_LETTER = { [14] = "N", [15] = "H", [16] = "M" }

local function DungeonDiff() return GetDungeonDifficultyID and GetDungeonDifficultyID() or 1 end
local function RaidDiff() return GetRaidDifficultyID and GetRaidDifficultyID() or 14 end

local function DiffTip(t, label, choices, current)
    t:SetText(label)
    for _, ch in ipairs(choices) do
        local c = DIFF_COLOUR[ch[1]]
        t:AddLine((ch[1] == current and "> " or "   ") .. ch[2], c[1], c[2], c[3])
    end
    t:AddLine(" ")
    if IsLeaderOrSolo() then
        t:AddLine(L["Click: Mythic. Right-click: pick. Mouse wheel: step."], 0.6, 0.6, 0.6)
    else
        t:AddLine(L["Only the group leader can change it."], 1, 0.3, 0.3)
    end
end

local function DiffButton(name, choices, get, set, label, mythic)
    local b = MakeButton(name, row)
    b:EnableMouseWheel(true)
    function b:Tip(t) DiffTip(t, label, choices, get()) end
    b:SetScript("OnClick", function(self, mouse)
        if not IsLeaderOrSolo() or not set then return end
        if mouse == "RightButton" then
            Menu(self, function(root)
                root:CreateTitle(label)
                for _, ch in ipairs(choices) do
                    root:CreateRadio(ch[2], function() return get() == ch[1] end, function() set(ch[1]) end)
                end
            end)
        else
            set(mythic)
            Retip(self)
        end
    end)
    b:SetScript("OnMouseWheel", function(self, delta)
        if not IsLeaderOrSolo() or not set then return end
        local index, current = 1, get()
        for i, ch in ipairs(choices) do if ch[1] == current then index = i end end
        index = math.max(1, math.min(#choices, index + (delta > 0 and 1 or -1)))
        set(choices[index][1])
        Retip(self)
    end)
    return b
end

local function UpdateDifficulty()
    if not dungeonButton then return end
    local outside = not (IsInInstance and select(2, IsInInstance()) ~= "none")
    local d = DIFF_COLOUR[DungeonDiff()] or { 1, 1, 1 }
    dungeonButton.icon:SetVertexColor(d[1], d[2], d[3])
    dungeonButton:SetShown(Active("difficulty") and outside)
    local r = DIFF_COLOUR[RaidDiff()] or { 1, 1, 1 }
    raidButton.icon:SetVertexColor(r[1], r[2], r[3])
    raidButton.text:SetText(DIFF_LETTER[RaidDiff()] or "")
    raidButton.text:SetTextColor(r[1], r[2], r[3])
    raidButton:SetShown(Active("difficulty") and outside)
end

-- ── Loot spec ───────────────────────────────────────────────────────────────

local function UpdateLoot()
    if not lootButton then return end
    local specID = SpecInfo(SpecIndex()) or 0
    local loot = GetLootSpecialization and GetLootSpecialization() or 0
    if loot == 0 then loot = specID end
    local _, icon = SpecByID(loot)
    lootButton.icon:SetTexture(icon or 134400)
    lootButton.mark:SetShown(loot ~= specID)
    lootButton:SetShown(Active("lootButton") and (settings.lootAlways or loot ~= specID))
end

-- ── War Mode ────────────────────────────────────────────────────────────────

local function WarModeOn()
    return C_PvP and C_PvP.IsWarModeDesired and C_PvP.IsWarModeDesired() or false
end

local function SetWarMode(on)
    if not (C_PvP and C_PvP.SetWarModeDesired) or InCombatLockdown() then return end
    if C_PvP.CanToggleWarMode and not C_PvP.CanToggleWarMode(on) then
        print(PREFIX .. L["War Mode can only be changed in a city or inn."])
        return
    end
    C_PvP.SetWarModeDesired(on)
end

local function UpdateWarMode()
    if not pvpButton then return end
    pvpButton.icon:SetAtlas(WarModeOn() and "pvptalents-warmode-swords" or "pvptalents-warmode-swords-disabled")
    local unlocked = not (C_PvP and C_PvP.ArePvpTalentsUnlocked) or C_PvP.ArePvpTalentsUnlocked()
    pvpButton:SetShown(Active("warMode") and unlocked and true or false)
end

-- ── Mythic+ ─────────────────────────────────────────────────────────────────

local function OwnedKey()
    if not C_MythicPlus then return nil end
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
    if not (mapID and level and level > 0) then return nil end
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
    return name, level, texture
end

local function RunsThisWeek()
    local runs = C_MythicPlus and C_MythicPlus.GetRunHistory and C_MythicPlus.GetRunHistory(false, true)
    if type(runs) ~= "table" then return 0, nil end
    local best
    for _, run in ipairs(runs) do
        if run.completed and (not best or run.level > best) then best = run.level end
    end
    return #runs, best
end

local function UpdateKeystone()
    if not keyButton then return end
    local score = C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore and Plain(C_ChallengeMode.GetOverallDungeonScore()) or 0
    if type(score) ~= "number" then score = 0 end
    local text = tostring(score)
    local colour = C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
    if colour then text = colour:WrapTextInColorCode(text) end
    local runs = RunsThisWeek()
    keyButton.text:SetText(text)
    keyButton.runs:SetText(runs > 0 and runs or "")
    keyButton:SetWidth(BUTTON + 4 + keyButton.text:GetStringWidth() + (runs > 0 and keyButton.runs:GetStringWidth() + 8 or 0))
    keyButton.score = score
    keyButton:SetShown(Active("keystone") and (score > 0 or OwnedKey() ~= nil))
end

local function UpdateAssist()
    if not assistButton then return end
    local leader = UnitIsGroupLeader("player") and IsInRaid()
    assistButton.everyone:SetShown(IsEveryoneAssistant and IsEveryoneAssistant() or false)
    assistButton:SetShown(Active("assistToggle") and leader and true or false)
end

-- ── Item level and spec ─────────────────────────────────────────────────────

local function UpdateItemLevel()
    if not ilvlFrame then return end
    local overall, equipped = 0, 0
    if GetAverageItemLevel then overall, equipped = GetAverageItemLevel() end
    overall, equipped = overall or 0, equipped or 0
    local eq = ("%.1f"):format(equipped)
    if equipped + 0.05 < overall then eq = "|cffffd100" .. eq .. "|r" end
    ilvlFrame.text:SetText(eq .. " / " .. ("%.1f"):format(overall))
    ilvlFrame:SetWidth(ilvlFrame.text:GetStringWidth() + 8)
    ilvlFrame:SetShown(Active("itemLevel") and overall > 0)
end

local function UpdateSpec()
    if not specButton then return end
    local _, _, icon = SpecInfo(SpecIndex())
    specButton.icon:SetTexture(icon or 134400)
    specButton:SetShown(Active("specButton") and NumSpecs() > 0)
end

local function SetSpec(index)
    if InCombatLockdown() then return end
    if C_SpecializationInfo and C_SpecializationInfo.SetSpecialization then
        C_SpecializationInfo.SetSpecialization(index)
    elseif SetSpecialization then
        SetSpecialization(index)
    end
end

local function LayoutRow()
    if not row then return end
    local prev, width = nil, 0
    for _, b in ipairs({ dungeonButton, raidButton, lootButton, pvpButton, keyButton }) do
        b:ClearAllPoints()
        if b:IsShown() then
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", row, "LEFT") end
            width = width + b:GetWidth() + (prev and 2 or 0)
            prev = b
        end
    end
    row:SetWidth(math.max(width, BUTTON))
end

local function BuildButtons(c)
    if row or not c.LeaderIcon then return end
    local portrait = Portrait() or PlayerFrame

    -- On UIParent, named, so PetBattleHide finds them; anchored to the frame.
    row = CreateFrame("Frame", "OxedHubPlayerFrameRow", UIParent)
    row:SetSize(BUTTON, BUTTON)
    row:SetFrameStrata("MEDIUM")
    row:SetFrameLevel((PlayerFrame:GetFrameLevel() or 1) + 20)

    dungeonButton = DiffButton("OxedHubPlayerFrameDungeon", DUNGEON_CHOICES, DungeonDiff, SetDungeonDifficultyID, L["Dungeon difficulty"], 23)
    dungeonButton.icon:SetAtlas("DungeonSkull")

    raidButton = DiffButton("OxedHubPlayerFrameRaid", RAID_CHOICES, RaidDiff, SetRaidDifficultyID, L["Raid difficulty"], 16)
    raidButton.icon:SetAtlas("UI-HUD-Minimap-GuildBanner-Mythic-Large")
    raidButton.text = raidButton:CreateFontString(nil, "OVERLAY")
    raidButton.text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    raidButton.text:SetPoint("TOP", raidButton, "TOP", 0, 6)

    lootButton = MakeButton("OxedHubPlayerFrameLoot", row)
    lootButton.mark = lootButton:CreateTexture(nil, "OVERLAY")
    lootButton.mark:SetSize(10, 10)
    lootButton.mark:SetPoint("BOTTOM")
    lootButton.mark:SetAtlas("VignetteLoot")
    function lootButton:Tip(t)
        local loot = GetLootSpecialization and GetLootSpecialization() or 0
        local name, icon = SpecByID(loot)
        t:SetText(L["Loot specialization"])
        t:AddLine(name and ("|T%s:0|t %s"):format(icon or 0, name) or L["Current specialization"], 1, 1, 1)
        t:AddLine(" ")
        t:AddLine(L["Click: loot for your current spec. Right-click: pick one."], 0.6, 0.6, 0.6)
    end
    lootButton:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            Menu(self, function(root)
                local function IsLoot(id) return (GetLootSpecialization() or 0) == id end
                local function SetLoot(id) SetLootSpecialization(id) end
                root:CreateTitle(L["Loot specialization"])
                root:CreateRadio(L["Current specialization"], IsLoot, SetLoot, 0)
                for i = 1, NumSpecs() do
                    local id, name, icon = SpecInfo(i)
                    if id then root:CreateRadio(("|T%s:0|t %s"):format(icon or 0, name or "?"), IsLoot, SetLoot, id) end
                end
            end)
        else
            SetLootSpecialization(0)
            print(PREFIX .. L["loot specialization set to your current spec."])
        end
    end)

    pvpButton = MakeButton("OxedHubPlayerFrameWarMode", row)
    function pvpButton:Tip(t)
        t:SetText(PVP_LABEL_WAR_MODE or L["War Mode"])
        t:AddLine(WarModeOn() and L["|cff00ff00On|r"] or L["|cffff2020Off|r"])
        t:AddLine(" ")
        t:AddLine(L["Click: switch. Right-click: pick."], 0.6, 0.6, 0.6)
    end
    pvpButton:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            Menu(self, function(root)
                root:CreateTitle(PVP_LABEL_WAR_MODE or L["War Mode"])
                root:CreateRadio(L["On"], WarModeOn, function() SetWarMode(true) end)
                root:CreateRadio(L["Off"], function() return not WarModeOn() end, function() SetWarMode(false) end)
            end)
        else
            SetWarMode(not WarModeOn())
            Retip(self)
        end
    end)

    keyButton = MakeButton("OxedHubPlayerFrameKeystone", row)
    keyButton.icon:ClearAllPoints()
    keyButton.icon:SetPoint("LEFT")
    keyButton.icon:SetSize(BUTTON, BUTTON)
    keyButton.icon:SetTexture(4352494)
    keyButton.text = keyButton:CreateFontString(nil, "OVERLAY")
    keyButton.text:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    keyButton.text:SetPoint("LEFT", keyButton.icon, "RIGHT", 2, 0)
    keyButton.runs = keyButton:CreateFontString(nil, "OVERLAY")
    keyButton.runs:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    keyButton.runs:SetTextColor(1, 0.82, 0)
    keyButton.runs:SetPoint("LEFT", keyButton.text, "RIGHT", 8, 0)
    function keyButton:Tip(t)
        t:SetText(L["Mythic+ rating"])
        t:AddLine(tostring(self.score or 0), 1, 1, 1)
        local name, level, texture = OwnedKey()
        t:AddLine(" ")
        if name then
            t:AddLine((L["Your key: %s +%d"]):format((texture and ("|T%s:0|t "):format(texture) or "") .. name, level), 0.4, 0.8, 1)
        else
            t:AddLine(L["No keystone in your bags."], 0.6, 0.6, 0.6)
        end
        local runs, best = RunsThisWeek()
        t:AddLine((L["Runs this week: %d"]):format(runs), 1, 0.82, 0)
        if best then t:AddLine((L["Best this week: +%d"]):format(best), 1, 0.82, 0) end
        t:AddLine(" ")
        t:AddLine(L["Click: open Mythic+ dungeons."], 0.6, 0.6, 0.6)
    end
    keyButton:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if PVEFrame_ToggleFrame then PVEFrame_ToggleFrame("ChallengesFrame") end
    end)

    -- Over the crown itself: only shown to a raid leader.
    assistButton = MakeButton("OxedHubPlayerFrameAssist", UIParent)
    assistButton:SetFrameStrata("HIGH")
    assistButton:SetAllPoints(c.LeaderIcon)
    assistButton.icon:SetTexture(nil)
    assistButton.everyone = assistButton:CreateTexture(nil, "OVERLAY")
    assistButton.everyone:SetPoint("CENTER")
    assistButton.everyone:SetSize(16, 16)
    assistButton.everyone:SetAtlas("runecarving-menu-reagent-selected")
    function assistButton:Tip(t)
        t:SetText(ALL_ASSIST_DESCRIPTION or L["Everyone is an assistant"])
        t:AddLine(IsEveryoneAssistant() and L["|cff00ff00On|r"] or L["|cffff2020Off|r"])
        t:AddLine(L["Click to switch."], 0.6, 0.6, 0.6)
    end
    assistButton:SetScript("OnClick", function(self)
        if not SetEveryoneIsAssistant then return end
        SetEveryoneIsAssistant(not IsEveryoneAssistant())
        C_Timer.After(0.5, function()
            UpdateAssist()
            if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
        end)
    end)

    ilvlFrame = CreateFrame("Frame", "OxedHubPlayerFrameItemLevel", UIParent)
    ilvlFrame:SetSize(80, 18)
    ilvlFrame:SetFrameStrata("MEDIUM")
    ilvlFrame:EnableMouse(true)
    ilvlFrame.bg = ilvlFrame:CreateTexture(nil, "BACKGROUND")
    ilvlFrame.bg:SetAllPoints()
    ilvlFrame.bg:SetColorTexture(0, 0, 0, 0.55)
    ilvlFrame.text = ilvlFrame:CreateFontString(nil, "OVERLAY")
    ilvlFrame.text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    ilvlFrame.text:SetPoint("CENTER")
    ilvlFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Item level"])
        GameTooltip:AddLine(L["Equipped / best in your bags."], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ilvlFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    specButton = MakeButton("OxedHubPlayerFrameSpec", UIParent, 34)
    specButton:SetFrameStrata("MEDIUM")
    specButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    specButton.border = specButton:CreateTexture(nil, "OVERLAY")
    specButton.border:SetPoint("TOPLEFT", -2, 2)
    specButton.border:SetPoint("BOTTOMRIGHT", 2, -2)
    specButton.border:SetAtlas("UI-HUD-ActionBar-IconFrame")
    function specButton:Tip(t)
        local _, name, icon = SpecInfo(SpecIndex())
        t:SetText(L["Specialization"])
        if name then t:AddLine(("|T%s:0|t %s"):format(icon or 0, name), 1, 1, 1) end
        t:AddLine(" ")
        t:AddLine(L["Click or right-click: switch spec."], 0.6, 0.6, 0.6)
    end
    specButton:SetScript("OnClick", function(self)
        if InCombatLockdown() then return end
        Menu(self, function(root)
            root:CreateTitle(L["Specialization"])
            for i = 1, NumSpecs() do
                local id, name, icon = SpecInfo(i)
                if id then
                    root:CreateRadio(("|T%s:0|t %s"):format(icon or 0, name or "?"),
                        function() return SpecIndex() == i end, function() SetSpec(i) end)
                end
            end
        end)
    end)

    AddPiece("row", row, L["Buttons"], "BOTTOMLEFT", portrait, "TOPLEFT", -14, -4)
    AddPiece("ilvl", ilvlFrame, L["Item level"], "RIGHT", portrait, "LEFT", -2, -14)
    AddPiece("spec", specButton, L["Spec"], "TOPRIGHT", ilvlFrame, "BOTTOMRIGHT", -16, -4)

    for _, b in ipairs({ row, dungeonButton, raidButton, lootButton, pvpButton, keyButton, assistButton, ilvlFrame, specButton }) do b:Hide() end
end

local function UpdateButtons()
    if not row then return end
    UpdateDifficulty()
    UpdateLoot()
    UpdateWarMode()
    UpdateKeystone()
    UpdateAssist()
    UpdateItemLevel()
    UpdateSpec()
    LayoutRow()
    row:SetShown(Active() and true or false)
end

local function SetMoving(on)
    if on and (InCombatLockdown() or not row) then
        print(PREFIX .. L["the player frame buttons can only be moved out of combat, with the module on."])
        on = false
    end
    moving = on and true or false
    for _, p in pairs(pieces) do
        local frame = p[1]
        if moving then frame:Show() end
        frame.mover:SetShown(moving)
    end
    if not moving then UpdateButtons() end
    return moving
end

local function ResetPositions()
    settings.offsets = {}
    for key in pairs(pieces) do PlacePiece(key) end
end

-- ── Applying and undoing ────────────────────────────────────────────────────

local pending = false

local function Apply()
    if not Active() then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    local c = Contextual()
    if not (PlayerFrame and c) then return end
    -- Put everything back first: a switch turned off since the last apply
    -- must come undone, and the rest is laid out again from Blizzard's.
    RestoreAll()
    if combatGlow then combatGlow:Hide() end
    if Active("tidyCorner") then ApplyCorner(c) end
    if Active("combatIcon") then ApplyCombatIcon(c) end
    if Active("groupNumber") then ApplyGroupNumber(c) end
    if Active("hitText") then ApplyHitText() end
    if Active("classBorder") then ApplyClassBorder() end
    PaintLevel()
    BuildButtons(c)
    for key in pairs(pieces) do PlacePiece(key) end
    UpdateButtons()
end

local function Undo()
    if InCombatLockdown() then pending = true return end
    pending = false
    if moving then SetMoving(false) end
    RestoreAll()
    if combatGlow then combatGlow:Hide() end
    if PlayerFrame_UpdateGroupIndicator then pcall(PlayerFrame_UpdateGroupIndicator) end
    for _, b in ipairs({ row, dungeonButton, raidButton, lootButton, pvpButton, keyButton, assistButton, ilvlFrame, specButton }) do
        if b then b:Hide() end
    end
end

-- Blizzard's own updates rewrite some of these; hooked once, each does
-- nothing while the module (or that switch) is off.
local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    if PlayerFrame_UpdateGroupIndicator then hooksecurefunc("PlayerFrame_UpdateGroupIndicator", PaintGroupText) end
    if PlayerFrame_UpdateLevel then hooksecurefunc("PlayerFrame_UpdateLevel", PaintLevel) end
    if PlayerFrame_UpdatePvPStatus then
        hooksecurefunc("PlayerFrame_UpdatePvPStatus", function() if Active("tidyCorner") then Apply() end end)
    end
    if PlayerFrame_UpdatePartyLeader then
        hooksecurefunc("PlayerFrame_UpdatePartyLeader", function()
            if Active() and not InCombatLockdown() then UpdateAssist() end
        end)
    end
    -- Vehicle art swaps re-anchor the frame's parts.
    for _, name in ipairs({ "PlayerFrame_ToPlayerArt", "PlayerFrame_ToVehicleArt" }) do
        if _G[name] then hooksecurefunc(name, function() if Active() then C_Timer.After(0, Apply) end end) end
    end
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            if Active() then Apply() else Undo() end
        else
            UpdateButtons()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if moving then SetMoving(false) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, Apply)
    elseif moving then
        return
    elseif not InCombatLockdown() then
        UpdateButtons()
    else
        -- Text only (item level, rating) may change in a fight; the rest waits.
        UpdateItemLevel()
        pending = true
    end
end)

local EVENTS = {
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "PLAYER_LOOT_SPEC_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_DIFFICULTY_CHANGED",
    "GROUP_ROSTER_UPDATE", "GROUP_LEFT", "CHALLENGE_MODE_MAPS_UPDATE", "CHALLENGE_MODE_COMPLETED",
    "PARTY_LEADER_CHANGED", "PLAYER_FLAGS_CHANGED", "WAR_MODE_STATUS_UPDATE", "PLAYER_UPDATE_RESTING",
    "PLAYER_EQUIPMENT_CHANGED", "PLAYER_AVG_ITEM_LEVEL_UPDATE", "BAG_UPDATE_DELAYED",
    "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "WEEKLY_REWARDS_UPDATE",
}

local function Start()
    Hook()
    for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
    Apply()
end

local function Stop()
    watcher:UnregisterAllEvents()
    Undo()
    -- Undo waits for the fight to end; keep the one event it needs.
    if pending then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("Player Frame", 470, 640)
        local function Re() Apply() end
        o:AddCheckbox(settings, "tidyCorner", "Smaller play-time, PvP and honour badges", nil, Re)
        o:AddCheckbox(settings, "combatIcon", "Red combat swords with a glow, left of your name", nil, Re)
        o:AddCheckbox(settings, "groupNumber", "Raid group as a number next to your level", nil, Re)
        o:AddCheckbox(settings, "hideMaxLevel", "Hide the level at max level", nil, Re)
        o:AddCheckbox(settings, "hitText", "Smaller heal and damage numbers, under the portrait", nil, Re)
        o:AddCheckbox(settings, "classBorder", "Frame border in your class colour", nil, Re)
        o:AddCheckbox(settings, "difficulty", "Dungeon and raid difficulty buttons", nil, Re)
        o:AddCheckbox(settings, "lootButton", "Loot specialization button", nil, Re)
        o:AddCheckbox(settings, "lootAlways", "Show it all the time",
            "Off: only when your loot spec is not your current spec.", Re)
        o:AddCheckbox(settings, "warMode", "War Mode button", nil, Re)
        o:AddCheckbox(settings, "keystone", "Mythic+ rating, runs this week, your key", nil, Re)
        o:AddCheckbox(settings, "itemLevel", "Item level, equipped and overall", nil, Re)
        o:AddCheckbox(settings, "specButton", "Specialization button", nil, Re)
        o:AddCheckbox(settings, "assistToggle", "Raid leader: click the crown for everyone is an assistant", nil, Re)

        local move = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        move:SetSize(130, 22)
        move:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 2)
        move:SetText(L["Move Pieces"])
        move:SetScript("OnClick", function(self)
            self:SetText(SetMoving(not moving) and L["Lock"] or L["Move Pieces"])
        end)
        move:SetScript("OnHide", function(self)
            if moving then SetMoving(false) end
            self:SetText(L["Move Pieces"])
        end)
        local reset = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        reset:SetSize(130, 22)
        reset:SetPoint("LEFT", move, "RIGHT", 8, 0)
        reset:SetText(L["Reset Positions"])
        reset:SetScript("OnClick", ResetPositions)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(move)
            OxedHub.UI:ApplyRedButtonStyle(reset)
        end
        o.cursorY = o.cursorY - 32

        o:AddModuleLinks("Other players' frames:", { "unitframes" })
        o:AddNote("Move Pieces: drag the blue covers, right-click one to put it back, Lock when done. /oxpf move does the same. Changes wait until the end of a fight.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

SLASH_OXEDPLAYERFRAME1 = "/oxpf"
SlashCmdList["OXEDPLAYERFRAME"] = function(message)
    if not settings then return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "move" or message == "lock" then
        local on = SetMoving(message == "move" and not moving)
        print(PREFIX .. (on and L["player frame buttons unlocked: drag them, /oxpf lock when done."] or L["player frame buttons locked."]))
    elseif message == "reset" then
        ResetPositions()
    else
        ShowOptions()
    end
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.playerframe
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.playerframe = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Not in DEFAULTS: a table there would be shared by reference.
    if type(config.offsets) ~= "table" then config.offsets = {} end
    settings = config
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "playerframe",
        name     = "Player Frame",
        version  = "1.1.0",
        updated  = 20261031.6,  -- raid + dungeon difficulty, War Mode, key and runs, item level, spec button, movable
        author   = "Oxed",
        category = "character",
        keywords = { "player", "unit", "frame", "portrait", "loot", "spec", "difficulty", "mythic", "assist", "class", "war mode", "item level" },
        desc     = "Tidier player frame: difficulty, loot spec, War Mode, key, item level and spec buttons.",
        icon     = "Interface\\Icons\\Achievement_Character_Human_Male",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.offsets) ~= "table" then settings.offsets = {} end
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
