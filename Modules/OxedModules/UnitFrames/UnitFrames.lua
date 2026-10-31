-- ============================================================================
-- Unit Frames (built-in OxedHub module)
-- Additions to Blizzard's frames for everyone who is not you (the player's
-- own frame is the Player Frame module):
--
--   * Target and focus: border and health bar in the unit's class colour
--     (reaction colour for NPCs), class icon on the portrait, smaller PvP
--     and honour badges, a rough range readout out of combat.
--   * Party: class-coloured health bars and class icons, each member's
--     target (portrait and name), an "in combat" swords icon, their faction
--     when it is not yours, where they are (zone or distance), their Mythic+
--     rating, how often they died, and shift-click to focus them.
--   * Boss frames: a plain health bar texture, and each boss's target.
--   * Pet frame: name and mana text hidden, health text tidied.
--
-- Idea from WoWTools' Plus_UnitFrame (MIT, husandro); written for OxedHub.
--
-- These frames are secure. Everything drawn on them is a texture or a font
-- string made on the frame (regions may show and hide in combat; a frame of
-- ours anchored to them could not). Moving Blizzard's own regions waits for
-- the end of a fight. Unit questions go through Known: in combat they can be
-- secret, and then the last answer stays. Names and portraits go straight to
-- SetText / SetPortraitTexture, which take secrets.
-- ============================================================================

local addonName, OxedHub = ...
local print = OxedHub.Print or print
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled          = false,  -- off until the player switches it on (see ModuleAPI:Register)
    targetColour     = true,   -- target / focus border and health bar by class or reaction
    targetBadges     = true,   -- smaller PvP and honour badges on target / focus
    targetRange      = true,   -- rough range under the target portrait, out of combat
    classIcons       = true,   -- class icon on target, focus and party portraits
    partyColour      = true,   -- party health bars in class colour
    partyTarget      = true,   -- each member's target, portrait and name
    partyCombat      = true,   -- swords on members who are in combat
    partyFaction     = true,   -- faction badge when it is not yours
    partyWhere       = true,   -- zone when elsewhere, distance when near
    partyScore       = true,   -- Mythic+ rating
    partyDeaths      = true,   -- deaths this group
    partyShiftFocus  = true,   -- shift-click a member to focus them
    bossTexture      = true,
    bossTarget       = true,
    petTidy          = true,
}

local settings
local optionsWindow
local watcher = CreateFrame("Frame")
local ticker
local PREFIX = "|cff00ff00OxedHub:|r "
local PLAIN_BAR = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Health-Status"

local function Active(option)
    return settings and settings.enabled == true and (option == nil or settings[option] ~= false)
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

local function Plain(v)
    if v == nil or IsSecret(v) then return nil end
    return v
end

-- true, false, or nil when the game will not say (secret, or an error).
local function Known(...)
    local ok, value = pcall(...)
    if not ok or IsSecret(value) then return nil end
    return value and true or false
end

local function Read(...)
    local ok, a, b, c, d = pcall(...)
    if not ok then return nil end
    return Plain(a), Plain(b), Plain(c), Plain(d)
end

-- ── Remembering Blizzard's layout ───────────────────────────────────────────

local saved = {}

local function Remember(region)
    if not region or saved[region] then return end
    local points = {}
    for i = 1, region:GetNumPoints() do points[i] = { region:GetPoint(i) } end
    local s = { points = points, scale = region:GetScale(), alpha = region:GetAlpha() }
    if region.GetVertexColor then s.r, s.g, s.b, s.a = region:GetVertexColor() end
    if region.GetTextColor then s.tr, s.tg, s.tb = region:GetTextColor() end
    if region.GetStatusBarTexture then
        local tex = region:GetStatusBarTexture()
        s.atlas = tex and tex.GetAtlas and tex:GetAtlas()
        s.texture = tex and tex:GetTexture()
        s.br, s.bg, s.bb = region:GetStatusBarColor()
    end
    saved[region] = s
end

local function Restore(region)
    local s = saved[region]
    if not s then return end
    if #s.points > 0 then
        region:ClearAllPoints()
        for _, p in ipairs(s.points) do region:SetPoint(unpack(p)) end
    end
    region:SetScale(s.scale)
    region:SetAlpha(s.alpha)
    if s.r and region.SetVertexColor then region:SetVertexColor(s.r, s.g, s.b, s.a) end
    if s.tr and region.SetTextColor then region:SetTextColor(s.tr, s.tg, s.tb) end
    if region.SetStatusBarTexture then
        if s.atlas then region:SetStatusBarTexture(s.atlas)
        elseif s.texture then region:SetStatusBarTexture(s.texture) end
        if s.br then region:SetStatusBarColor(s.br, s.bg, s.bb) end
    end
end

-- ── Colours ─────────────────────────────────────────────────────────────────

-- r, g, b for a unit, or nil when it cannot be told.
local function UnitColour(unit)
    local player = Known(UnitIsPlayer, unit)
    if player == nil then return nil end
    if player then
        local _, class = Read(UnitClass, unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then return c.r, c.g, c.b end
        return nil
    end
    local reaction = Read(UnitReaction, unit, "player")
    local c = reaction and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
    if c then return c.r, c.g, c.b end
    return nil
end

local function ClassAtlas(unit)
    if Known(UnitIsPlayer, unit) ~= true then return nil end
    local _, class = Read(UnitClass, unit)
    return class and ("classicon-" .. class:lower()) or nil
end

-- ── Spec and item level (inspect) ───────────────────────────────────────────
-- One player at a time, out of combat, at most every 2 s, and never while
-- the player has the Inspect window open. Results are kept per GUID.

local inspected = {}   -- guid -> { icon = spec icon, ilvl = number }
local inspectUnit, inspectGuid
local lastInspect = 0
local OnInspected      -- set below: repaints after a result arrives

local function GuidOf(unit)
    local guid = Read(UnitGUID, unit)
    return type(guid) == "string" and guid or nil
end

local function RequestInspect(unit)
    if not Active("classIcons") or InCombatLockdown() or not NotifyInspect then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    if GetTime() - lastInspect < 2 then return end
    local guid = GuidOf(unit)
    if not guid or inspected[guid] then return end
    if Known(UnitIsPlayer, unit) ~= true or Known(UnitIsUnit, unit, "player") ~= false then return end
    if not CanInspect or Known(CanInspect, unit) ~= true then return end
    lastInspect = GetTime()
    inspectUnit, inspectGuid = unit, guid
    NotifyInspect(unit)
end

local function InspectReady(guid)
    if not inspectGuid or Plain(guid) ~= inspectGuid then return end
    local unit = inspectUnit
    inspectUnit, inspectGuid = nil, nil
    if GuidOf(unit) ~= guid then return end
    local result = {}
    local specID = Read(GetInspectSpecialization, unit)
    if type(specID) == "number" and specID > 0 and GetSpecializationInfoByID then
        result.icon = select(4, GetSpecializationInfoByID(specID))
    end
    local ilvl = C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel and Read(C_PaperDollInfo.GetInspectItemLevel, unit)
    if type(ilvl) == "number" and ilvl > 0 then result.ilvl = math.floor(ilvl) end
    inspected[guid] = result
    if ClearInspectPlayer and not (InspectFrame and InspectFrame:IsShown()) then ClearInspectPlayer() end
    if OnInspected then OnInspected() end
end

local function PaintClassIcon(tex, unit, ilvlText)
    if not tex then return end
    if not Active("classIcons") then
        tex:Hide()
        if ilvlText then ilvlText:Hide() end
        return
    end
    local exists = Known(UnitExists, unit)
    if exists == nil then return end  -- cannot tell: leave it
    local atlas = exists and ClassAtlas(unit)
    local known = exists and inspected[GuidOf(unit) or ""]
    if known and known.icon then
        tex:SetTexture(known.icon)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:Show()
    elseif atlas then
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetAtlas(atlas)
        tex:Show()
    elseif Known(UnitIsPlayer, unit) ~= nil then
        tex:Hide()
    end
    if ilvlText then
        if known and known.ilvl and tex:IsShown() then
            ilvlText:SetText(known.ilvl)
            local r, g, b = UnitColour(unit)
            ilvlText:SetTextColor(r or 1, g or 1, b or 1)
            ilvlText:Show()
        elseif Known(UnitExists, unit) ~= nil then
            ilvlText:Hide()
        end
    end
    if exists and atlas and not known then RequestInspect(unit) end
end

local function ILvlLabel(parent, icon)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    fs:SetPoint("LEFT", icon, "RIGHT", -1, 0)
    fs:Hide()
    return fs
end

-- Health percentage under a small portrait; SetFormattedText takes the
-- secret number the game hands back in combat.
local function PaintHealthPct(fs, unit)
    if not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100) then fs:Hide() return end
    local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
    if not ok or pct == nil then fs:Hide() return end
    fs:SetFormattedText("%i", pct)
    fs:Show()
end

local function HealthLabel(parent, portrait)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    fs:SetPoint("BOTTOM", portrait, "BOTTOM", 0, -1)
    fs:Hide()
    return fs
end

local function PaintName(fs, unit, enabled)
    if not fs then return end
    Remember(fs)
    if not enabled then return end
    local r, g, b = UnitColour(unit)
    if r then fs:SetTextColor(r, g, b) end
end

-- ── Target and focus ────────────────────────────────────────────────────────

local function TargetParts(frame)
    local container = frame.TargetFrameContainer
    local contextual = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentContextual
    return container, contextual, frame.healthbar
end

-- ── Movable pieces ──────────────────────────────────────────────────────────
-- Each piece is anchored through Place, which adds the player's own offset
-- (settings.offsets[key], dragged in move mode) to the built-in position.
-- Every region placed under a key is kept, so one drag moves the piece on
-- every frame that has it (all four party members, all boss frames).

local placed = {}   -- key -> { { region, point, rel, relPoint, x, y }, ... }

local PIECES = {
    { key = "targetSpec",  label = "Spec icon" },
    { key = "targetRange", label = "Range" },
    { key = "partyClass",  label = "Party spec icon" },
    { key = "partyTarget", label = "Party targets" },
    { key = "bossTarget",  label = "Boss targets" },
}
OxedHub:RegisterLocalizedTable(PIECES, "label")

local function Offset(key)
    local o = settings and settings.offsets and settings.offsets[key]
    if type(o) ~= "table" then return 0, 0 end
    return tonumber(o.x) or 0, tonumber(o.y) or 0
end

local function SetPlace(entry, key)
    local dx, dy = Offset(key)
    local region = entry[1]
    region:ClearAllPoints()
    region:SetPoint(entry[2], entry[3], entry[4], entry[5] + dx, entry[6] + dy)
end

local function Place(key, region, point, rel, relPoint, x, y)
    local entry = { region, point, rel, relPoint, x or 0, y or 0 }
    placed[key] = placed[key] or {}
    table.insert(placed[key], entry)
    SetPlace(entry, key)
end

local function Replace(key)
    if InCombatLockdown() then return end
    for _, entry in ipairs(placed[key] or {}) do SetPlace(entry, key) end
end

-- Move mode: a labelled handle over the first placed region of each piece.
local handles = {}
local moving = false

local function HandleFor(piece)
    local h = handles[piece.key]
    if h then return h end
    h = CreateFrame("Frame", "OxedHubUnitFramesHandle_" .. piece.key, UIParent)
    h:SetSize(70, 18)
    h:SetFrameStrata("DIALOG")
    h:SetMovable(true)
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(0, 0.6, 1, 0.45)
    h.text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.text:SetPoint("CENTER")
    h.text:SetText(piece.label)
    h:SetScript("OnDragStart", function(self)
        self.startX, self.startY = GetCursorPosition()
        self:StartMoving()
    end)
    h:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = GetCursorPosition()
        local list = placed[piece.key]
        local region = list and list[1] and list[1][1]
        local scale = region and region:GetEffectiveScale() or UIParent:GetEffectiveScale()
        settings.offsets = settings.offsets or {}
        local dx, dy = Offset(piece.key)
        settings.offsets[piece.key] = {
            x = math.floor(dx + (x - (self.startX or x)) / scale + 0.5),
            y = math.floor(dy + (y - (self.startY or y)) / scale + 0.5),
        }
        Replace(piece.key)
        self:ClearAllPoints()
        if region then self:SetPoint("CENTER", region, "CENTER") end
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(piece.label)
        GameTooltip:AddLine(L["Drag to move. Right-click to put it back."], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if settings.offsets then settings.offsets[piece.key] = nil end
        Replace(piece.key)
        local list = placed[piece.key]
        self:ClearAllPoints()
        if list and list[1] then self:SetPoint("CENTER", list[1][1], "CENTER") end
    end)
    handles[piece.key] = h
    return h
end

local function SetMoving(on)
    if on and InCombatLockdown() then
        print(PREFIX .. L["cannot move unit frame pieces in combat."])
        on = false
    end
    moving = on and true or false
    local shown = 0
    for _, piece in ipairs(PIECES) do
        local list = placed[piece.key]
        local region = list and list[1] and list[1][1]
        if moving and region then
            local h = HandleFor(piece)
            h:ClearAllPoints()
            h:SetPoint("CENTER", region, "CENTER")
            h:Show()
            shown = shown + 1
        elseif handles[piece.key] then
            handles[piece.key]:Hide()
        end
    end
    if moving and shown == 0 then
        print(PREFIX .. L["nothing to move yet: target someone, or join a party, then try again."])
    end
    return moving
end

local function ResetPositions()
    settings.offsets = {}
    for _, piece in ipairs(PIECES) do Replace(piece.key) end
    if moving then SetMoving(true) end
end

-- A plain frame over a Blizzard frame, above its children, to draw on. Made
-- once out of combat and never shown or hidden after: only the regions on it
-- change, which is allowed in a fight.
local function Holder(frame, above)
    if frame.oxHolder then return frame.oxHolder end
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(frame)
    h:SetFrameLevel(((above or frame):GetFrameLevel() or 1) + 10)
    frame.oxHolder = h
    return h
end

local function PaintTarget(frame)
    if not (frame and frame.unit) then return end
    local container, _, bar = TargetParts(frame)
    if container and not frame.oxClass and not InCombatLockdown() then
        -- Round, with a ring, sitting on the bottom of the portrait. Drawn on
        -- a holder above the container: the portrait and its border belong
        -- to a child frame, which would cover regions made on the frame.
        local h = Holder(frame, container)
        frame.oxClass = h:CreateTexture(nil, "OVERLAY", nil, 6)
        frame.oxClass:SetSize(18, 18)
        Place("targetSpec", frame.oxClass, "BOTTOM", container.Portrait or frame, "BOTTOM", -7, -2)
        local mask = h:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(frame.oxClass)
        frame.oxClass:AddMaskTexture(mask)
        frame.oxRing = h:CreateTexture(nil, "OVERLAY", nil, 5)
        frame.oxRing:SetAtlas("talents-node-choiceflyout-circle-greenglow")
        frame.oxRing:SetPoint("TOPLEFT", frame.oxClass, -3, 3)
        frame.oxRing:SetPoint("BOTTOMRIGHT", frame.oxClass, 3, -3)
        frame.oxRing:Hide()
        hooksecurefunc(frame.oxClass, "Show", function() frame.oxRing:Show() end)
        hooksecurefunc(frame.oxClass, "Hide", function() frame.oxRing:Hide() end)
        frame.oxClass:Hide()
        frame.oxILvl = ILvlLabel(h, frame.oxClass)
        frame.oxILvl:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        frame.oxILvl:ClearAllPoints()
        frame.oxILvl:SetPoint("LEFT", frame.oxClass, "RIGHT", 2, 0)
    end
    PaintClassIcon(frame.oxClass, frame.unit, frame.oxILvl)
    if frame.oxRing then
        local r, g, b = UnitColour(frame.unit)
        frame.oxRing:SetVertexColor(r or 1, g or 1, b or 1)
    end

    local main = frame.TargetFrameContent and frame.TargetFrameContent.TargetFrameContentMain
    PaintName(main and main.Name, frame.unit, Active("targetColour"))

    if not (Active("targetColour") and container) then return end
    local r, g, b = UnitColour(frame.unit)
    if not r then r, g, b = 1, 1, 1 end
    for _, tex in ipairs({ container.FrameTexture or false, container.BossPortraitFrameTexture or false }) do
        if tex then Remember(tex) tex:SetVertexColor(r, g, b) end
    end
    if bar and bar.SetStatusBarTexture then
        Remember(bar)
        bar:SetStatusBarTexture(PLAIN_BAR)
        bar:SetStatusBarColor(r, g, b)
    end
end

local function TargetFrames()
    local list = {}
    if TargetFrame then list[#list + 1] = TargetFrame end
    if FocusFrame then list[#list + 1] = FocusFrame end
    return list
end

local function ApplyTargetBadges()
    for _, frame in ipairs(TargetFrames()) do
        local _, c = TargetParts(frame)
        if c then
            for _, key in ipairs({ "PvpIcon", "PrestigePortrait", "PrestigeBadge" }) do
                if c[key] then
                    Remember(c[key])
                    c[key]:SetScale(0.6)
                end
            end
        end
    end
end

-- Range in yards (min and max, from LibRangeCheck) and movement speed, left
-- of the portrait. Item range checks are refused in combat even inside pcall,
-- so in a fight the library is asked for spell checks only (noItems).
local RangeCheck = LibStub and LibStub("LibRangeCheck-3.0", true)

local function RangeColour(max)
    if not max then return 1, 0.25, 0.25 end
    if max <= 5 then return 0, 1, 0 end
    if max <= 8 then return 0.78, 0.61, 0.43 end
    if max <= 30 then return 1, 0.49, 0.04 end
    if max <= 35 then return 0.25, 0.78, 0.92 end
    if max <= 40 then return 0.67, 0.83, 0.45 end
    return 1, 0.25, 0.25
end

local function BuildRange(frame)
    if frame.oxRangeMax then return end
    local function Label()
        local fs = frame:CreateFontString(nil, "OVERLAY")
        fs:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        fs:SetJustifyH("RIGHT")
        fs:Hide()
        return fs
    end
    -- Outside the frame's left edge: the level text sits just inside it.
    -- One line "8-15", the speed under it only while the unit moves.
    frame.oxRangeMax = Label()
    Place("targetRange", frame.oxRangeMax, "RIGHT", frame, "LEFT", 4, 8)
    frame.oxRangeMin = Label()   -- unused, kept so HideRange stays simple
    frame.oxSpeed = Label()
    frame.oxSpeed:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    frame.oxSpeed:SetPoint("TOPRIGHT", frame.oxRangeMax, "BOTTOMRIGHT", 0, -1)
end

local function HideRange(frame)
    if not frame.oxRangeMax then return end
    frame.oxRangeMax:Hide() frame.oxRangeMin:Hide() frame.oxSpeed:Hide()
end

local function PaintRangeFor(frame)
    if not (frame and frame.unit) then return end
    if not frame.oxRangeMax and InCombatLockdown() then return end
    BuildRange(frame)
    local unit = frame.unit
    if not Active("targetRange") or not frame:IsShown() or Known(UnitExists, unit) ~= true
        or Known(UnitIsUnit, unit, "player") == true then
        HideRange(frame)
        return
    end
    local min, max
    if RangeCheck then
        local ok, a, b = pcall(RangeCheck.GetRange, RangeCheck, unit, false, InCombatLockdown())
        if ok then min, max = Plain(a), Plain(b) end
    end
    if min or max then
        local r, g, b = RangeColour(max)
        local text
        if min and max then text = ("%d-%d"):format(min, max)
        elseif min then text = ("%d+"):format(min)
        else text = ("<%d"):format(max) end
        frame.oxRangeMax:SetText(text)
        frame.oxRangeMax:SetTextColor(r, g, b)
        frame.oxRangeMax:Show()
    else
        frame.oxRangeMax:Hide()
    end
    local speed = Read(GetUnitSpeed, unit)
    if type(speed) == "number" and speed > 0 then
        frame.oxSpeed:SetText(("%d%%"):format(math.floor(speed * 100 / (BASE_MOVEMENT_SPEED or 7) + 0.5)))
        frame.oxSpeed:SetTextColor(0.8, 0.8, 0.8)
        frame.oxSpeed:Show()
    elseif type(speed) == "number" then
        frame.oxSpeed:Hide()
    end
end

local function PaintRange()
    for _, frame in ipairs(TargetFrames()) do PaintRangeFor(frame) end
end

-- ── Party ───────────────────────────────────────────────────────────────────

local function PartyMembers()
    local list = {}
    if not PartyFrame then return list end
    for i = 1, 4 do
        local m = PartyFrame["MemberFrame" .. i]
        if m then list[#list + 1] = m end
    end
    if #list == 0 and PartyFrame.memberFramePool and PartyFrame.memberFramePool.EnumerateActive then
        for m in PartyFrame.memberFramePool:EnumerateActive() do list[#list + 1] = m end
    end
    return list
end

local function MemberBar(m)
    return m.HealthBar or (m.HealthBarContainer and m.HealthBarContainer.HealthBar) or m.healthbar
end

local function BuildMember(m)
    if m.oxBuilt then return true end
    if InCombatLockdown() then return false end  -- the holder frame is made out of combat
    m.oxBuilt = true
    local portrait = m.Portrait or m
    local h = Holder(m)

    m.oxClass = h:CreateTexture(nil, "OVERLAY", nil, 7)
    m.oxClass:SetSize(14, 14)
    Place("partyClass", m.oxClass, "BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 2, -2)

    m.oxCombat = h:CreateTexture(nil, "OVERLAY", nil, 7)
    m.oxCombat:SetSize(14, 14)
    m.oxCombat:SetPoint("TOPLEFT", portrait, "TOPLEFT", -4, 4)
    m.oxCombat:SetAtlas("UI-HUD-UnitFrame-Player-CombatIcon")
    m.oxCombat:SetVertexColor(1, 0.2, 0.2)

    m.oxFaction = h:CreateTexture(nil, "OVERLAY", nil, 6)
    m.oxFaction:SetSize(22, 22)
    m.oxFaction:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -8, -6)

    m.oxDeaths = h:CreateFontString(nil, "OVERLAY")
    m.oxDeaths:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    m.oxDeaths:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", 4, 2)

    m.oxTarget = m:CreateTexture(nil, "OVERLAY")
    m.oxTarget:SetSize(22, 22)
    Place("partyTarget", m.oxTarget, "LEFT", m, "RIGHT", 2, 6)

    m.oxTargetName = m:CreateFontString(nil, "OVERLAY")
    m.oxTargetName:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    m.oxTargetName:SetPoint("LEFT", m.oxTarget, "RIGHT", 2, 0)
    m.oxTargetName:SetWidth(90)
    m.oxTargetName:SetJustifyH("LEFT")
    m.oxTargetName:SetWordWrap(false)

    m.oxInfo = m:CreateFontString(nil, "OVERLAY")
    m.oxInfo:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
    m.oxInfo:SetPoint("TOPLEFT", m.oxTarget, "BOTTOMLEFT", 0, -1)
    m.oxInfo:SetJustifyH("LEFT")

    m.oxILvl = ILvlLabel(h, m.oxClass)
    m.oxTargetHP = HealthLabel(m, m.oxTarget)

    for _, r in ipairs({ m.oxClass, m.oxCombat, m.oxFaction, m.oxDeaths, m.oxTarget, m.oxTargetName, m.oxInfo }) do r:Hide() end
end

local function HideMember(m)
    if not m.oxBuilt then return end
    for _, r in ipairs({ m.oxClass, m.oxCombat, m.oxFaction, m.oxDeaths, m.oxTarget, m.oxTargetName, m.oxInfo, m.oxILvl, m.oxTargetHP }) do r:Hide() end
end

local function MemberName(unit)
    local name = Read(GetUnitName, unit, true)
    return type(name) == "string" and name or nil
end

local deadNow = {}   -- unit -> last known dead state

local function TrackDeath(unit)
    local dead = Known(UnitIsDeadOrGhost, unit)
    if dead == nil then return end
    if dead and deadNow[unit] == false and Known(UnitIsFeignDeath, unit) ~= true then
        local name = MemberName(unit)
        if name then settings.deaths[name] = (settings.deaths[name] or 0) + 1 end
    end
    deadNow[unit] = dead
end

local function PaintMemberTarget(m, unit)
    if not Active("partyTarget") then
        m.oxTarget:Hide() m.oxTargetName:Hide() m.oxTargetHP:Hide()
        return
    end
    local target = unit .. "target"
    local exists = Known(UnitExists, target)
    if exists == nil then return end
    if exists then
        SetPortraitTexture(m.oxTarget, target)
        m.oxTargetName:SetText(UnitName(target))  -- SetText takes a secret name
        local r, g, b = UnitColour(target)
        m.oxTargetName:SetTextColor(r or 1, g or 1, b or 1)
        m.oxTarget:Show() m.oxTargetName:Show()
        PaintHealthPct(m.oxTargetHP, target)
    else
        m.oxTarget:Hide() m.oxTargetName:Hide() m.oxTargetHP:Hide()
    end
end

local function Distance(unit)
    local y1, x1, _, i1 = Read(UnitPosition, "player")
    local y2, x2, _, i2 = Read(UnitPosition, unit)
    if not (y1 and x1 and y2 and x2) or i1 ~= i2 then return nil end
    return math.sqrt((y1 - y2) ^ 2 + (x1 - x2) ^ 2)
end

local function PaintMemberInfo(m, unit)
    local parts = {}
    if Active("partyWhere") and C_Map and C_Map.GetBestMapForUnit then
        local mine = Read(C_Map.GetBestMapForUnit, "player")
        local theirs = Read(C_Map.GetBestMapForUnit, unit)
        if theirs and mine and theirs ~= mine then
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(theirs)
            if info and info.name then parts[#parts + 1] = "|cffaaaaaa" .. info.name .. "|r" end
        else
            local d = Distance(unit)
            if d then parts[#parts + 1] = ("|cffdddddd%d" .. L["yd"] .. "|r"):format(math.floor(d + 0.5)) end
        end
    end
    if Active("partyScore") and C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = Read(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, unit)
        local score = type(summary) == "table" and Plain(summary.currentSeasonScore)
        if type(score) == "number" and score > 0 then
            local text = tostring(score)
            local colour = C_ChallengeMode and C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
            parts[#parts + 1] = colour and colour:WrapTextInColorCode(text) or text
        end
    end
    if #parts > 0 then
        m.oxInfo:SetText(table.concat(parts, "  "))
        m.oxInfo:Show()
    else
        m.oxInfo:Hide()
    end
end

local function PaintMember(m, slow)
    local unit = m.unit
    if not unit or not m:IsShown() then return end
    if not BuildMember(m) then return end
    if Known(UnitExists, unit) ~= true then
        if Known(UnitExists, unit) == false then HideMember(m) end
        return
    end

    PaintClassIcon(m.oxClass, unit, m.oxILvl)
    PaintName(m.Name or m.name, unit, Active("partyColour"))

    if Active("partyCombat") then
        local fighting = Known(UnitAffectingCombat, unit)
        if fighting ~= nil then m.oxCombat:SetShown(fighting) end
    else
        m.oxCombat:Hide()
    end

    if Active("partyDeaths") then
        TrackDeath(unit)
        local name = MemberName(unit)
        local n = name and settings.deaths[name]
        if n and n > 0 then
            m.oxDeaths:SetText("|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:0|t" .. n)
            m.oxDeaths:Show()
        else
            m.oxDeaths:Hide()
        end
    else
        m.oxDeaths:Hide()
    end

    PaintMemberTarget(m, unit)

    if slow then
        if Active("partyFaction") then
            local theirs = Read(UnitFactionGroup, unit)
            local mine = Read(UnitFactionGroup, "player")
            if theirs and mine and theirs ~= mine and (theirs == "Alliance" or theirs == "Horde") then
                m.oxFaction:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. theirs)
                m.oxFaction:SetTexCoord(0, 0.62, 0, 0.62)
                m.oxFaction:Show()
            elseif theirs then
                m.oxFaction:Hide()
            end
        else
            m.oxFaction:Hide()
        end
        PaintMemberInfo(m, unit)

        if Active("partyColour") then
            local bar = MemberBar(m)
            local r, g, b = UnitColour(unit)
            if bar and r and bar.SetStatusBarColor then
                Remember(bar)
                bar:SetStatusBarTexture(PLAIN_BAR)
                bar:SetStatusBarColor(r, g, b)
            end
        end
    end
end

local focusSet = {}

local function ApplyShiftFocus()
    if InCombatLockdown() then return end
    for _, m in ipairs(PartyMembers()) do
        local want = Active("partyShiftFocus")
        if want and not focusSet[m] then
            m:SetAttribute("shift-type1", "focus")
            focusSet[m] = true
        elseif not want and focusSet[m] then
            m:SetAttribute("shift-type1", nil)
            focusSet[m] = nil
        end
    end
end

-- ── Boss frames ─────────────────────────────────────────────────────────────

local function BossFrames()
    local list = {}
    for i = 1, (MAX_BOSS_FRAMES or 5) do
        local f = _G["Boss" .. i .. "TargetFrame"]
        if f then list[#list + 1] = f end
    end
    return list
end

local function PaintBoss(f)
    if not f:IsShown() or not f.unit then return end
    if Active("bossTexture") and f.healthbar and f.healthbar.SetStatusBarTexture then
        Remember(f.healthbar)
        f.healthbar:SetStatusBarTexture(PLAIN_BAR)
    end
    if not f.oxTarget then
        if InCombatLockdown() then return end
        local main = f.TargetFrameContent and f.TargetFrameContent.TargetFrameContentMain
        local anchor = main and main.HealthBarsContainer or f
        f.oxTarget = f:CreateTexture(nil, "OVERLAY")
        f.oxTarget:SetSize(22, 22)
        Place("bossTarget", f.oxTarget, "LEFT", anchor, "RIGHT", 4, 0)
        f.oxTargetName = f:CreateFontString(nil, "OVERLAY")
        f.oxTargetName:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
        f.oxTargetName:SetPoint("LEFT", f.oxTarget, "RIGHT", 2, 0)
        f.oxTargetHP = HealthLabel(f, f.oxTarget)
        f.oxTarget:Hide() f.oxTargetName:Hide()
    end
    if not Active("bossTarget") then
        f.oxTarget:Hide() f.oxTargetName:Hide() f.oxTargetHP:Hide()
        return
    end
    local target = f.unit .. "target"
    local exists = Known(UnitExists, target)
    if exists == nil then return end
    if exists then
        SetPortraitTexture(f.oxTarget, target)
        f.oxTargetName:SetText(UnitName(target))
        local r, g, b = UnitColour(target)
        f.oxTargetName:SetTextColor(r or 1, g or 1, b or 1)
        f.oxTarget:Show() f.oxTargetName:Show()
        PaintHealthPct(f.oxTargetHP, target)
    else
        f.oxTarget:Hide() f.oxTargetName:Hide() f.oxTargetHP:Hide()
    end
end

-- ── Pet frame ───────────────────────────────────────────────────────────────

local function ApplyPet()
    if not (PetFrame and PetPortrait) then return end
    for _, r in ipairs({ PetName or false, PetFrameManaBarText or false }) do
        if r then Remember(r) r:SetAlpha(0) end
    end
    local bar = PetFrameHealthBar or (PetFrame.healthbar)
    if PetFrameHealthBarTextLeft then
        Remember(PetFrameHealthBarTextLeft)
        PetFrameHealthBarTextLeft:ClearAllPoints()
        PetFrameHealthBarTextLeft:SetPoint("TOPLEFT", PetPortrait, "TOPRIGHT", 0, 1.5)
    end
    if PetFrameHealthBarTextRight and bar then
        Remember(PetFrameHealthBarTextRight)
        PetFrameHealthBarTextRight:ClearAllPoints()
        PetFrameHealthBarTextRight:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, 1.5)
    end
    if PetFrameHealthBarText and bar then
        Remember(PetFrameHealthBarText)
        PetFrameHealthBarText:ClearAllPoints()
        PetFrameHealthBarText:SetPoint("BOTTOM", bar, "TOP", 0, 1.5)
    end
end

-- ── Applying and undoing ────────────────────────────────────────────────────

local pending = false

local function RestoreAll()
    for region in pairs(saved) do Restore(region) end
end

local function Tick(slow)
    if not Active() then return end
    for _, m in ipairs(PartyMembers()) do PaintMember(m, slow) end
    for _, f in ipairs(BossFrames()) do PaintBoss(f) end
    PaintRange()
end

local function Apply()
    if not Active() then return end
    if InCombatLockdown() then pending = true return end
    pending = false
    RestoreAll()
    for _, m in ipairs(PartyMembers()) do HideMember(m) end
    if Active("targetBadges") then ApplyTargetBadges() end
    if Active("petTidy") then ApplyPet() end
    for _, frame in ipairs(TargetFrames()) do PaintTarget(frame) end
    ApplyShiftFocus()
    Tick(true)
end

local function Undo()
    if InCombatLockdown() then pending = true return end
    pending = false
    RestoreAll()
    for _, m in ipairs(PartyMembers()) do HideMember(m) end
    for _, f in ipairs(BossFrames()) do
        if f.oxTarget then f.oxTarget:Hide() f.oxTargetName:Hide() f.oxTargetHP:Hide() end
    end
    for _, frame in ipairs(TargetFrames()) do
        if frame.oxClass then frame.oxClass:Hide() frame.oxILvl:Hide() end
        HideRange(frame)
    end
    ApplyShiftFocus()
end

local hooked = false
local function Hook()
    if hooked then return end
    hooked = true
    for _, frame in ipairs(TargetFrames()) do
        if frame.CheckClassification then
            hooksecurefunc(frame, "CheckClassification", function(self) if Active() then PaintTarget(self) end end)
        end
    end
end

local tickCount = 0

OnInspected = function()
    for _, frame in ipairs(TargetFrames()) do PaintTarget(frame) end
    Tick(false)
end

watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            if Active() then Apply() else Undo() end
        else
            ApplyShiftFocus()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if moving then SetMoving(false) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1, Apply)
    elseif event == "INSPECT_READY" then
        InspectReady(...)
    elseif event == "GROUP_LEFT" then
        wipe(settings.deaths)
        wipe(deadNow)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if not InCombatLockdown() then ApplyShiftFocus() else pending = true end
        Tick(true)
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        for _, frame in ipairs(TargetFrames()) do PaintTarget(frame) end
        PaintRange()
    else
        Tick(false)
    end
end)

local EVENTS = {
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "GROUP_LEFT",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "INSPECT_READY",
}

local function Start()
    Hook()
    for _, event in ipairs(EVENTS) do pcall(watcher.RegisterEvent, watcher, event) end
    if ticker then ticker:Cancel() end
    -- Twice a second for targets, combat and deaths; every 2 s the rest.
    ticker = C_Timer.NewTicker(0.5, function()
        tickCount = tickCount + 1
        Tick(tickCount % 4 == 0)
    end)
    Apply()
end

local function Stop()
    if ticker then ticker:Cancel() ticker = nil end
    SetMoving(false)
    watcher:UnregisterAllEvents()
    Undo()
    if pending then watcher:RegisterEvent("PLAYER_REGEN_ENABLED") end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("Unit Frames", 470, 690)
        local function Re() Apply() end
        o:AddCheckbox(settings, "targetColour", "Target and focus: class or reaction colour", nil, Re)
        o:AddCheckbox(settings, "targetBadges", "Target and focus: smaller PvP and honour badges", nil, Re)
        o:AddCheckbox(settings, "targetRange", "Target and focus: range in yards and movement speed", nil, Re)
        o:AddCheckbox(settings, "classIcons", "Spec icon and item level on target, focus and party portraits", nil, Re)
        o:AddCheckbox(settings, "partyColour", "Party: health bars in class colour", nil, Re)
        o:AddCheckbox(settings, "partyTarget", "Party: each member's target", nil, Re)
        o:AddCheckbox(settings, "partyCombat", "Party: swords on members in combat", nil, Re)
        o:AddCheckbox(settings, "partyFaction", "Party: faction badge when it is not yours", nil, Re)
        o:AddCheckbox(settings, "partyWhere", "Party: zone when elsewhere, distance when near", nil, Re)
        o:AddCheckbox(settings, "partyScore", "Party: Mythic+ rating", nil, Re)
        o:AddCheckbox(settings, "partyDeaths", "Party: deaths in this group", nil, Re)
        o:AddCheckbox(settings, "partyShiftFocus", "Party: shift-click a member to focus them", nil, Re)
        o:AddCheckbox(settings, "bossTexture", "Boss frames: plain health bar", nil, Re)
        o:AddCheckbox(settings, "bossTarget", "Boss frames: who each boss is targeting", nil, Re)
        o:AddCheckbox(settings, "petTidy", "Pet frame: hide name and mana text", nil, Re)

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

        local resetPos = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        resetPos:SetSize(130, 22)
        resetPos:SetPoint("LEFT", move, "RIGHT", 8, 0)
        resetPos:SetText(L["Reset Positions"])
        resetPos:SetScript("OnClick", ResetPositions)

        local reset = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        reset:SetSize(130, 22)
        reset:SetPoint("LEFT", resetPos, "RIGHT", 8, 0)
        reset:SetText(L["Reset Deaths"])
        reset:SetScript("OnClick", function()
            wipe(settings.deaths)
            Tick(false)
            print(PREFIX .. L["party death counts reset."])
        end)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            for _, b in ipairs({ move, resetPos, reset }) do OxedHub.UI:ApplyRedButtonStyle(b) end
        end
        o.cursorY = o.cursorY - 32

        o:AddModuleLinks("Your own frame:", { "playerframe" })
        o:AddNote("Move Pieces shows a handle on each piece: drag it, right-click to put it back, Lock when done. /oxuf move does the same. Party additions show on the classic party frames, not raid-style ones.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

-- ── Slash command ───────────────────────────────────────────────────────────

SLASH_OXEDUNITFRAMES1 = "/oxuf"
SlashCmdList["OXEDUNITFRAMES"] = function(message)
    if not settings then return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if not Active() then
        print(PREFIX .. L["the Unit Frames module is off: switch it on in Modules first."])
    elseif message == "move" or message == "lock" then
        local on = SetMoving(message == "move" and not moving)
        print(PREFIX .. (on and L["unit frame pieces unlocked: drag the blue handles, /oxuf lock when done."] or L["unit frame pieces locked."]))
    elseif message == "reset" then
        ResetPositions()
        print(PREFIX .. L["unit frame pieces back in their places."])
    else
        ShowOptions()
    end
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.unitframes
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.unitframes = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Not in DEFAULTS: a table there would be shared by reference.
    if type(config.deaths) ~= "table" then config.deaths = {} end
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
        id       = "unitframes",
        name     = "Unit Frames",
        version  = "1.2.0",
        updated  = 20261031.5,  -- movable pieces with lock, spec icon drawn above the portrait
        author   = "Oxed",
        category = "character",
        keywords = { "unit", "frame", "target", "focus", "party", "boss", "pet", "class", "colour", "color", "range", "deaths" },
        desc     = "Class colours, targets, location, rating and deaths on target, party and boss frames.",
        icon     = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            if type(settings.deaths) ~= "table" then settings.deaths = {} end
            if type(settings.offsets) ~= "table" then settings.offsets = {} end
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
