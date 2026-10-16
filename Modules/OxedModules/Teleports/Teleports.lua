-- ============================================================================
-- Teleports (built-in OxedHub module)
-- A small button on screen. Click it and your teleports fly out of it as rows
-- of icons: hearthstones, your class's own teleports, the portals you open for
-- the group, teleport toys, what is in your bags and what you are wearing.
--
-- Each group flies out in its own direction. Send the hearthstones right and
-- the portals down if that is what suits the rest of your interface; groups
-- pointed the same way stack up behind one another instead of overlapping.
--
-- Nothing is configured by hand. The lists in TeleportsData.lua are candidates:
-- a spell is kept only when you know it, a toy only when you own it, an item
-- only while it is in your bags and gear only while it is worn. So a mage sees
-- their faction's portals appear as they learn them, and an id that is wrong or
-- that Blizzard retires shows up as nothing rather than as a dead button.
--
-- The icons are secure buttons. Using a toy, an item or a spell is a protected
-- action, so only a real click on one of these can do it, and the game forbids
-- re-aiming them in combat -- which is why the rows are rebuilt out of combat
-- and left alone during a fight.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    showHearth    = true,
    showClass     = true,
    showPortals   = true,
    showToys      = true,
    showItems     = true,
    showEquip     = true,
    closeAfterUse = true,
    closeOnLeave  = true,   -- fold away once the mouse leaves
    showButton    = true,   -- the button the rows fly out of
    lockButton    = false,  -- drag it while unlocked
    showHidden    = false,  -- show the ones put away with a right click
    iconSize      = 36,     -- the icons that fly out
    buttonSize    = 32,     -- the button itself, set apart from them on purpose
    perLine       = 12,     -- icons before a row wraps into a second line
    layout        = "rows", -- "rows": a row per group; "spiral": all of them around the button
    spiralRound   = true,   -- round icons (both layouts; the key keeps its old name)
    buttonRound   = false,  -- the main button round instead of square
    perArm        = 25,     -- icons in one arm before the group starts another beside it

    -- One direction per group, kept as flat keys. A table here would be copied
    -- by reference into every character's settings and shared by accident.
    dir_hearth    = "right",
    dir_class     = "right",
    dir_portal    = "right",
    dir_toy       = "right",
    dir_item      = "right",
    dir_equip     = "right",
    -- btnPoint / btnX / btnY are written when the button is dragged.
    -- "hidden" is a table and is built in BindSettings, for the same reason.
}

-- 16 at the small end: with hundreds of teleports a big icon is a wall.
local ICON_MIN, ICON_MAX = 16, 54
local GAP = 6          -- between icons
local STRIP_GAP = 4    -- between one group's row and the next

local settings         -- OxedHubDB.modules.teleports, bound at login
local anchor           -- the button the rows fly out of
local strips = {}      -- groupKey -> the frame holding that group's icons
local opened = false   -- are the rows out right now
local optionsWindow
local watcher = CreateFrame("Frame")
local rebuildQueued = false
local pendingRebuild = false   -- a rebuild that had to wait for combat to end

-- Declared here because handlers built further down refer to them. A local
-- assigned later is not the same name to a closure made above it: the closure
-- would capture a global that is never set.
local QueueRender
local Render
local EnsureAnchor
local CloseAll

-- Hearthstones that are plain items rather than toys. The toy module already
-- knows every hearthstone toy, so only these two are listed here.
local HEARTH_ITEMS = { 6948, 64488 }

-- ── Reading the game ────────────────────────────────────────────────────────

local function SpellKnown(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnown and IsSpellKnown(spellID) then return true end
    return false
end

local function SpellNameIcon(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local name, _, icon = GetSpellInfo(spellID)
        return name, icon
    end
    return nil, nil
end

local function ItemNameIcon(itemID)
    local name, icon
    if C_Item and C_Item.GetItemNameByID then
        local ok, value = pcall(C_Item.GetItemNameByID, itemID)
        if ok then name = value end
    end
    if C_Item and C_Item.GetItemIconByID then
        local ok, value = pcall(C_Item.GetItemIconByID, itemID)
        if ok then icon = value end
    end
    -- Ask for anything the client has not cached; the next refresh fills it in.
    if not name and C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
    return name, icon
end

local function ItemInBags(itemID)
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID)
    if count == nil and GetItemCount then count = GetItemCount(itemID) end
    return (tonumber(count) or 0) > 0
end

local function WornItems()
    local worn = {}
    local Data = OxedHub.TeleportsData
    for _, slot in ipairs(Data.EQUIP_SLOTS) do
        local itemID = GetInventoryItemID("player", slot)
        if itemID then worn[itemID] = true end
    end
    return worn
end

-- ── Hidden entries ──────────────────────────────────────────────────────────

-- Kind and id together, so putting away a toy never also hides an item that
-- happens to share its number.
local function EntryKey(kind, id)
    return kind .. ":" .. tostring(id)
end

local function IsHidden(kind, id)
    local list = settings and settings.hidden
    return type(list) == "table" and list[EntryKey(kind, id)] == true
end

-- ── Building the list ───────────────────────────────────────────────────────

local function AddEntry(list, entry)
    if not entry.name then return end     -- not cached yet; returns next refresh
    entry.hidden = IsHidden(entry.kind, entry.id)
    if entry.hidden and not settings.showHidden then return end
    list[#list + 1] = entry
end

local function CollectEntries()
    local Data = OxedHub.TeleportsData
    if not Data then return {} end

    local groups = {}
    local function Group(key)
        groups[key] = groups[key] or {}
        return groups[key]
    end

    -- Hearthstones: the toy module's own list, plus the two plain items.
    if settings.showHearth then
        local Toys = OxedHub.Toys
        if Toys and Toys.HearthstoneIds and PlayerHasToy then
            for _, toyID in ipairs(Toys.HearthstoneIds) do
                if PlayerHasToy(toyID) then
                    local name, icon = ItemNameIcon(toyID)
                    AddEntry(Group("hearth"), { kind = "toy", id = toyID, name = name, icon = icon })
                end
            end
        end
        for _, itemID in ipairs(HEARTH_ITEMS) do
            if ItemInBags(itemID) then
                local name, icon = ItemNameIcon(itemID)
                AddEntry(Group("hearth"), { kind = "item", id = itemID, name = name, icon = icon })
            end
        end
    end

    -- Class spells, split into what moves you and what opens a door for others.
    local _, class = UnitClass("player")
    local classList = Data.CLASS_SPELLS[class]
    if classList then
        -- Mages have one list per faction; every other class has a flat one.
        local faction = UnitFactionGroup("player")
        if classList[faction] then
            classList = classList[faction]
        elseif classList.Alliance or classList.Horde then
            classList = nil   -- a neutral pandaren, before choosing a side
        end
    end
    if classList then
        for _, record in ipairs(classList) do
            local isPortal = record.kind == "group"
            local wanted = isPortal and settings.showPortals or (not isPortal and settings.showClass)
            if wanted and SpellKnown(record.spell) then
                local name, icon = SpellNameIcon(record.spell)
                AddEntry(Group(isPortal and "portal" or "class"),
                    { kind = "spell", id = record.spell, name = name, icon = icon })
            end
        end
    end

    if settings.showToys and PlayerHasToy then
        for _, record in ipairs(Data.TOYS) do
            if PlayerHasToy(record.toy) then
                local name, icon = ItemNameIcon(record.toy)
                AddEntry(Group("toy"), { kind = "toy", id = record.toy, name = name, icon = icon })
            end
        end
    end

    if settings.showItems then
        for _, record in ipairs(Data.ITEMS) do
            if ItemInBags(record.item) then
                local name, icon = ItemNameIcon(record.item)
                AddEntry(Group("item"), { kind = "item", id = record.item, name = name, icon = icon })
            end
        end
    end

    if settings.showEquip then
        local worn = WornItems()
        for _, record in ipairs(Data.EQUIP) do
            if worn[record.item] then
                local name, icon = ItemNameIcon(record.item)
                AddEntry(Group("equip"), { kind = "item", id = record.item, name = name, icon = icon })
            end
        end
    end

    for _, list in pairs(groups) do
        table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    end
    return groups
end

-- ── Icons ───────────────────────────────────────────────────────────────────

local function IconSize()
    local size = tonumber(settings and settings.iconSize) or 36
    return math.max(ICON_MIN, math.min(ICON_MAX, size))
end

-- The button's own size. Deliberately its own setting: the icons that fly out
-- are a list to read, the button is a fixed part of the interface, and one
-- slider driving both means you cannot make the list big without the button
-- growing into whatever sits next to it.
local function ButtonSize()
    local size = tonumber(settings and settings.buttonSize) or 32
    return math.max(ICON_MIN, math.min(ICON_MAX, size))
end

-- Which "show this group" setting belongs to which group.
local GROUP_SETTING = {
    hearth = "showHearth",
    class  = "showClass",
    portal = "showPortals",
    toy    = "showToys",
    item   = "showItems",
    equip  = "showEquip",
}

local function GroupDirection(groupKey)
    local value = settings and settings["dir_" .. groupKey]
    if value == "left" or value == "up" or value == "down" then return value end
    return "right"
end

local function PaintCooldown(button, entry)
    local cd = button.cooldown
    if not cd then return end

    if entry.kind == "spell" then
        if C_Spell and C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
            local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, entry.id)
            if okDur and durObj then
                if pcall(cd.SetCooldownFromDurationObject, cd, durObj) then return end
            end
        end
        cd:Hide()
        return
    end

    -- Toys and items share the item cooldown.
    local getCooldown = (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
    if not getCooldown then cd:Hide() return end
    local ok, start, duration = pcall(getCooldown, entry.id)
    if ok then
        local s, d = tonumber(start), tonumber(duration)
        if s and d and d > 1.5 and s > 0 then
            if pcall(cd.SetCooldown, cd, s, d) then
                cd:Show()
                return
            end
        end
    end
    cd:Hide()
end

local function ShowEntryTooltip(button)
    local entry = button.entry
    if not entry then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if entry.kind == "spell" then
        GameTooltip:SetSpellByID(entry.id)
    elseif entry.kind == "toy" and GameTooltip.SetToyByItemID then
        GameTooltip:SetToyByItemID(entry.id)
    else
        GameTooltip:SetItemByID(entry.id)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(entry.hidden and "Right-click to bring it back"
        or "Right-click to put it away", 0.6, 0.8, 1)
    GameTooltip:Show()
end

local function CreateButton(strip, index)
    local button = CreateFrame("Button", nil, strip, "SecureActionButtonTemplate")
    -- Both edges: a secure button acts on press or on release depending on the
    -- player's "cast on key down" setting and ignores the other one. Register
    -- one edge only and the click does nothing for half of all players.
    button:RegisterForClicks("AnyUp", "AnyDown")

    button.border = button:CreateTexture(nil, "BACKGROUND")
    button.border:SetPoint("TOPLEFT", -1, 1)
    button.border:SetPoint("BOTTOMRIGHT", 1, -1)
    button.border:SetColorTexture(0, 0, 0, 0.9)

    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()
    button.cooldown:Hide()

    button:SetScript("OnEnter", ShowEntryTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("PostClick", function(self, mouseButton)
        -- In the arm editor a click does nothing; teleports are dragged there.
        if OxedHub._tpEditingArms then return end
        -- Right click puts an entry away. Only the left button carries the
        -- secure action (type1), so nothing is used on the way.
        if mouseButton == "RightButton" then
            local entry = self.entry
            if not entry or not settings then return end
            settings.hidden = settings.hidden or {}
            local key = EntryKey(entry.kind, entry.id)
            settings.hidden[key] = (not settings.hidden[key]) or nil
            GameTooltip:Hide()
            QueueRender()
            return
        end

        if settings and settings.closeAfterUse then CloseAll() end
    end)

    button:Hide()
    strip.buttons[index] = button
    return button
end

-- Aims one button at one entry. Attributes are protected, so this only ever
-- runs with combat over.
local function SetAction(button, entry)
    -- type1, not type: the action belongs to the left button alone, leaving the
    -- right one free to put an entry away.
    button:SetAttribute("type", nil)
    button:SetAttribute("type1", nil)
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("toy", nil)

    if entry.kind == "spell" then
        button:SetAttribute("type1", "spell")
        button:SetAttribute("spell", entry.id)
    elseif entry.kind == "toy" then
        button:SetAttribute("type1", "toy")
        button:SetAttribute("toy", entry.id)
    else
        button:SetAttribute("type1", "item")
        button:SetAttribute("item", "item:" .. entry.id)
    end
end

-- ── One strip per group ─────────────────────────────────────────────────────

local function EnsureStrip(groupKey)
    local strip = strips[groupKey]
    if strip then return strip end

    strip = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    strip:SetSize(100, 40)
    strip:SetFrameStrata("DIALOG")
    strip:SetFrameLevel(200)
    strip:SetClampedToScreen(true)
    strip:EnableMouse(true)
    strip.buttons = {}

    if strip.SetBackdrop then
        strip:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        strip:SetBackdropColor(0.05, 0.05, 0.07, 0.92)
        strip:SetBackdropBorderColor(1, 0.82, 0, 0.35)
    end

    strip:Hide()
    strips[groupKey] = strip
    return strip
end

-- Folds everything away once the mouse has left the button and every strip.
-- On a timer rather than on OnLeave: the mouse crosses the gap between the
-- button and the icons, and an OnLeave there would shut it in the player's face.
local closeWatcher = CreateFrame("Frame")
closeWatcher:Hide()
closeWatcher:SetScript("OnUpdate", function(self, elapsed)
    if not opened or not settings or not settings.closeOnLeave then return end
    -- Not while the arms are being edited: the mouse is on the options then.
    if OxedHub._tpEditingArms then return end
    self.timer = (self.timer or 0) + elapsed
    if self.timer < 0.25 then return end
    self.timer = 0

    if anchor and anchor:IsShown() and anchor:IsMouseOver(10, -10, -10, 10) then return end
    for _, strip in pairs(strips) do
        if strip:IsShown() and strip:IsMouseOver(10, -10, -10, 10) then return end
    end
    CloseAll()
end)

function CloseAll()
    opened = false
    for _, strip in pairs(strips) do strip:Hide() end
    closeWatcher:Hide()
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
-- Icons run along the direction their group opens in and wrap into a second
-- line once there are more than perLine of them. A caption would cost more room
-- than the icons in a strip this thin, so the tooltip names each one instead.

-- ── The spiral ──────────────────────────────────────────────────────────────
-- Every group, in group order, wound outward around the button: each icon
-- one step further along an Archimedean spiral, the turns one icon apart, so
-- the icons never touch however many there are. Three hundred teleports at
-- the small size fit in a circle a few hundred pixels across, where rows
-- ran off the screen.
--
-- ⚠ The spiral's frame takes no mouse: it lies over the button, and a frame
-- that took the mouse would swallow the button's own clicks. Its icons do.
local SPIRAL_KEY = "_spiral"
local simulated = 0   -- extra copies shown by the Simulate button
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function SetRound(button, round)
    if not button.roundMask then
        if not round then return end
        button.roundMask = button:CreateMaskTexture()
        button.roundMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        button.roundMask:SetAllPoints(button.icon)
    end
    if round and not button.isRound then
        button.icon:AddMaskTexture(button.roundMask)
        if button.border then button.border:SetAlpha(0) end
        -- The cooldown's dark swipe was still a square over the round icon.
        if button.cooldown then button.cooldown:SetSwipeTexture(ROUND_MASK) end
        button.isRound = true
    elseif not round and button.isRound then
        button.icon:RemoveMaskTexture(button.roundMask)
        if button.border then button.border:SetAlpha(1) end
        if button.cooldown then button.cooldown:SetSwipeTexture("Interface\\Cooldown\\swipe") end
        button.isRound = false
    end
end

-- Each group is its own arm: it leaves the button at its own angle and bends
-- by its own curl, like the arms of a galaxy. Settings are flat keys per
-- group, arm_<group> (degrees) and curl_<group> (how much it bends; minus
-- bends the other way). Unset, the arms share the circle evenly.
local CURL_DEFAULT = 0.9
local ARM_COLOURS = {
    hearth = { 0.25, 0.8, 0.35 }, class = { 0.65, 0.3, 0.75 }, portal = { 0.95, 0.85, 0.2 },
    toy = { 0.95, 0.25, 0.25 }, item = { 0.95, 0.6, 0.75 }, equip = { 0.7, 0.7, 0.95 },
}
local GROUP_LABEL = {
    hearth = "Hearthstones", class = "Class", portal = "Portals", toy = "Toys", item = "Items", equip = "Cloak & ring",
}

local editingArms = false
local handles = {}     -- groupKey .. "#" .. point -> handle
local armPaths = {}    -- groupKey -> { {x,y} P0, P1, P2, P3 } of the group's first arm
local drag = nil       -- { group, point } while a handle is held

-- Bend points per arm: three to start, the last is the arm's end. Shift-click
-- a point adds one after it, Ctrl-click removes it; pts_<group> keeps how many.
local BEND_DEFAULT, BEND_MIN, BEND_MAX = 3, 2, 8

local function PointCount(groupKey)
    local n = tonumber(settings and settings["pts_" .. groupKey]) or BEND_DEFAULT
    return math.max(BEND_MIN, math.min(BEND_MAX, math.floor(n)))
end

local function ArmAngle(groupKey, index, total)
    local saved = tonumber(settings["arm_" .. groupKey])
    if saved then return saved end
    return (index - 1) * 360 / math.max(1, total) + 90
end

local function ArmCurl(groupKey)
    return tonumber(settings["curl_" .. groupKey]) or CURL_DEFAULT
end

-- A point set by hand, or nil. Flat keys, pt_<group>_<n>x / y.
local function SavedPoint(groupKey, i)
    local x = tonumber(settings["pt_" .. groupKey .. "_" .. i .. "x"])
    local y = tonumber(settings["pt_" .. groupKey .. "_" .. i .. "y"])
    if x and y then return x, y end
    return nil
end

local function HasCustomPath(groupKey)
    return SavedPoint(groupKey, PointCount(groupKey)) ~= nil
end

local function ResetGroupShape(groupKey)
    settings["arm_" .. groupKey] = nil
    settings["curl_" .. groupKey] = nil
    settings["pts_" .. groupKey] = nil
    for i = 1, BEND_MAX do
        settings["pt_" .. groupKey .. "_" .. i .. "x"] = nil
        settings["pt_" .. groupKey .. "_" .. i .. "y"] = nil
    end
end

-- The spiral's point at a distance along it, walked in small steps.
local function SpiralPointAt(a, curl, start, dist)
    local r, walked = start, 0
    while walked < dist do
        local dr = math.min(4, dist - walked)
        r = r + dr / math.sqrt(1 + (r * curl / 100) ^ 2)
        walked = walked + dr
    end
    local theta = a + curl * (r - start) / 100
    return r * math.cos(theta), r * math.sin(theta)
end

-- The arm's control points: where it leaves the button, then the bend
-- points. Set by hand when the player has dragged one; otherwise on the
-- spiral the angle and curl make, spread over the arm's length.
local function BuildPath(groupKey, a, curl, length, start, path)
    path = path or {}
    local count = PointCount(groupKey)
    for n = count + 2, #path do path[n] = nil end
    for i = 1, count do
        local x, y = SavedPoint(groupKey, i)
        if not x then
            x, y = SpiralPointAt(a, curl, start, length * i / count)
        end
        path[i + 1] = path[i + 1] or {}
        path[i + 1][1], path[i + 1][2] = x, y
    end
    -- It leaves the button towards its first bend point.
    local dir = HasCustomPath(groupKey) and math.atan2(path[2][2], path[2][1]) or a
    path[1] = path[1] or {}
    path[1][1], path[1][2] = start * math.cos(dir), start * math.sin(dir)
    return path
end

-- A smooth line through the points (Catmull-Rom), as short straight pieces.
local polyline = {}
local function Smooth(path, out)
    wipe(out)
    local n = #path
    local function P(i) return path[math.max(1, math.min(n, i))] end
    for i = 1, n - 1 do
        local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
        for s = 0, 15 do
            local t = s / 16
            local t2, t3 = t * t, t * t * t
            local x = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            local y = 0.5 * ((2 * p1[2]) + (-p0[2] + p2[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2 + (-p0[2] + 3 * p1[2] - 3 * p2[2] + p3[2]) * t3)
            out[#out + 1] = x
            out[#out + 1] = y
        end
    end
    out[#out + 1] = path[n][1]
    out[#out + 1] = path[n][2]
    return out
end

-- The point at a distance along the line; past its end, straight on.
local function PointAlong(line, dist)
    local count = #line / 2
    local walked = 0
    for i = 1, count - 1 do
        local x1, y1 = line[2 * i - 1], line[2 * i]
        local x2, y2 = line[2 * i + 1], line[2 * i + 2]
        local seg = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
        if walked + seg >= dist and seg > 0 then
            local f = (dist - walked) / seg
            return x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
        end
        walked = walked + seg
    end
    local i = count - 1
    local x1, y1 = line[2 * i - 1], line[2 * i]
    local x2, y2 = line[2 * i + 1], line[2 * i + 2]
    local seg = math.max(0.001, math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2))
    local over = dist - walked
    return x2 + (x2 - x1) / seg * over, y2 + (y2 - y1) / seg * over
end

local RenderSpiral

-- Every bend point of an arm written down where it is now, so a change to
-- one point keeps the rest of the arm's shape.
local function FreezePath(g)
    local path = armPaths[g]
    if not path or HasCustomPath(g) then return end
    for n = 1, PointCount(g) do
        local p = path[n + 1]
        if p then
            settings["pt_" .. g .. "_" .. n .. "x"] = math.floor(p[1] + 0.5)
            settings["pt_" .. g .. "_" .. n .. "y"] = math.floor(p[2] + 0.5)
        end
    end
end

local function WritePoints(g, list)
    for n = 1, BEND_MAX do
        local p = list[n]
        settings["pt_" .. g .. "_" .. n .. "x"] = p and math.floor(p[1] + 0.5) or nil
        settings["pt_" .. g .. "_" .. n .. "y"] = p and math.floor(p[2] + 0.5) or nil
    end
    settings["pts_" .. g] = #list
end

local function ReadPoints(g)
    local list = {}
    for n = 1, PointCount(g) do
        local x, y = SavedPoint(g, n)
        if x then list[#list + 1] = { x, y } end
    end
    return list
end

-- Shift-click: a new point after this one, half way to the next (or one
-- step further on, after the end).
local function AddPointAfter(g, point)
    if PointCount(g) >= BEND_MAX then
        print(("|cff00ff00OxedHub:|r an arm has at most %d points."):format(BEND_MAX))
        return
    end
    FreezePath(g)
    local list = ReadPoints(g)
    local here = list[point]
    if not here then return end
    local nextP = list[point + 1]
    local new
    if nextP then
        new = { (here[1] + nextP[1]) / 2, (here[2] + nextP[2]) / 2 }
    else
        local prev = list[point - 1] or { 0, 0 }
        new = { here[1] + (here[1] - prev[1]) * 0.5, here[2] + (here[2] - prev[2]) * 0.5 }
    end
    table.insert(list, point + 1, new)
    WritePoints(g, list)
    Render()
end

-- Ctrl-click: this point out of the arm.
local function RemovePoint(g, point)
    if PointCount(g) <= BEND_MIN then
        print(("|cff00ff00OxedHub:|r an arm needs at least %d points."):format(BEND_MIN))
        return
    end
    FreezePath(g)
    local list = ReadPoints(g)
    table.remove(list, point)
    WritePoints(g, list)
    Render()
end

-- Dragging a handle: its arm is frozen as it is, then the held point
-- follows the mouse.
local dragFrame = CreateFrame("Frame")
dragFrame:Hide()
dragFrame:SetScript("OnUpdate", function(self, elapsed)
    if not drag or not anchor then self:Hide() return end
    self.wait = (self.wait or 0) + elapsed
    if self.wait < 0.04 then return end
    self.wait = 0
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local ax, ay = anchor:GetCenter()
    if not ax then return end
    local g, i = drag.group, drag.point
    FreezePath(g)
    settings["pt_" .. g .. "_" .. i .. "x"] = math.floor(cx / scale - ax + 0.5)
    settings["pt_" .. g .. "_" .. i .. "y"] = math.floor(cy / scale - ay + 0.5)
    if not InCombatLockdown() then Render() end
end)

local function Handle(groupKey, point, parent)
    local key = groupKey .. "#" .. point
    local h = handles[key]
    if h then return h end
    -- On the spiral's frame: hidden with it, and inside the area that keeps
    -- the teleports open while the mouse is over them.
    h = CreateFrame("Button", nil, parent)
    h:SetFrameStrata("DIALOG")
    h:SetFrameLevel(260)
    h:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    h.group, h.point = groupKey, point
    local c = ARM_COLOURS[groupKey] or { 1, 1, 1 }
    h.dot = h:CreateTexture(nil, "ARTWORK")
    h.dot:SetAllPoints()
    h.dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    h.dot:SetVertexColor(c[1], c[2], c[3], 1)
    h.label = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.label:SetPoint("TOP", h, "BOTTOM", 0, -2)
    h.label:SetTextColor(c[1], c[2], c[3])
    h:SetScript("OnMouseDown", function(_, mouse)
        -- Shift and Ctrl clicks add and remove points; they do not drag.
        if mouse == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
            drag = { group = groupKey, point = point }
            dragFrame:Show()
        end
    end)
    h:SetScript("OnMouseUp", function()
        drag = nil
        dragFrame:Hide()
    end)
    h:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then
            -- Right-click: the arm back to its own spiral.
            ResetGroupShape(groupKey)
            Render()
        elseif IsShiftKeyDown() then
            AddPointAfter(groupKey, self.point)
        elseif IsControlKeyDown() then
            RemovePoint(groupKey, self.point)
        end
    end)
    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel", function(_, delta)
        -- The wheel bends the spiral; an arm shaped by hand follows its
        -- points instead.
        if HasCustomPath(groupKey) then return end
        local curl = ArmCurl(groupKey) + delta * (IsShiftKeyDown() and 0.05 or 0.25)
        settings["curl_" .. groupKey] = math.max(-6, math.min(6, math.floor(curl * 100 + 0.5) / 100))
        Render()
    end)
    h:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("%s, point %d of %d"):format(GROUP_LABEL[groupKey] or groupKey, self.point, PointCount(groupKey)))
        GameTooltip:AddLine("Drag it: the arm runs through its points.", 1, 1, 1)
        GameTooltip:AddLine("Shift-click: add a point after this one.", 1, 1, 1)
        GameTooltip:AddLine("Ctrl-click: remove this point.", 1, 1, 1)
        if HasCustomPath(groupKey) then
            GameTooltip:AddLine("Shaped by hand: the wheel does not bend it.", 0.7, 0.9, 1)
        else
            GameTooltip:AddLine("Mouse wheel: bend the spiral (Shift: finer).", 1, 1, 1)
            GameTooltip:AddLine(("Bend now: %.2f"):format(ArmCurl(groupKey)), 0.7, 0.9, 1)
        end
        GameTooltip:AddLine("Right-click: back to its spiral.", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Drag a teleport onto another arm to move it there.", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:Hide()
    handles[key] = h
    return h
end

local function PlaceHandles()
    for _, h in pairs(handles) do
        local path = armPaths[h.group]
        local count = PointCount(h.group)
        local p = path and h.point <= count and path[h.point + 1]
        if editingArms and opened and p and anchor then
            local isEnd = h.point == count
            h:SetSize(isEnd and 22 or 14, isEnd and 22 or 14)
            h:ClearAllPoints()
            h:SetPoint("CENTER", anchor, "CENTER", p[1], p[2])
            if isEnd then
                if HasCustomPath(h.group) then
                    h.label:SetText(GROUP_LABEL[h.group] or h.group)
                else
                    h.label:SetFormattedText("%s  %.2f", GROUP_LABEL[h.group] or h.group, ArmCurl(h.group))
                end
                h.label:Show()
            else
                h.label:Hide()
            end
            h:Show()
        else
            h:Hide()
        end
    end
end

-- ── Moving a teleport to another arm ────────────────────────────────────────
-- In the editor a teleport can be dragged onto another arm. Which group it
-- belongs to then is kept per teleport, flat key move_<kind>:<id>.

local function MoveKey(entry) return "move_" .. EntryKey(entry.kind, entry.id) end

-- After the list is built: each moved teleport into its chosen group.
local function ApplyMoves(groups)
    local moving = {}
    for groupKey, list in pairs(groups) do
        for i = #list, 1, -1 do
            local entry = list[i]
            entry.home = entry.home or groupKey
            local to = settings[MoveKey(entry)]
            if to and to ~= groupKey then
                table.remove(list, i)
                moving[#moving + 1] = { entry = entry, to = to }
            end
        end
    end
    for _, m in ipairs(moving) do
        groups[m.to] = groups[m.to] or {}
        table.insert(groups[m.to], m.entry)
    end
    for _, item in ipairs(moving) do
        table.sort(groups[item.to], function(a, b) return (a.name or "") < (b.name or "") end)
    end
end

-- The arm nearest to a point beside the button: closest to any of its
-- control points or to the line between them.
local function NearestArm(x, y)
    local best, bestD
    for groupKey, path in pairs(armPaths) do
        for n = 1, #path do
            local p = path[n]
            local d = (p[1] - x) ^ 2 + (p[2] - y) ^ 2
            if not bestD or d < bestD then best, bestD = groupKey, d end
            local q = path[n + 1]
            if q then
                local mx, my = (p[1] + q[1]) / 2, (p[2] + q[2]) / 2
                local dm = (mx - x) ^ 2 + (my - y) ^ 2
                if dm < bestD then best, bestD = groupKey, dm end
            end
        end
    end
    return best
end

-- The icon that follows the mouse while a teleport is carried.
local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:SetSize(32, 32)
ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
ghost.icon:SetAllPoints()
ghost:Hide()
ghost:SetScript("OnUpdate", function(self)
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
end)

local carried = nil
local function StartCarry(button)
    if not editingArms or InCombatLockdown() or not button.entry then return end
    carried = button.entry
    ghost.icon:SetTexture(button.entry.icon or 134400)
    ghost:SetAlpha(0.85)
    ghost:Show()
end

local function DropCarry()
    local entry = carried
    carried = nil
    ghost:Hide()
    if not entry or not anchor or InCombatLockdown() then return end
    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    local ax, ay = anchor:GetCenter()
    if not ax then return end
    local to = NearestArm(cx / scale - ax, cy / scale - ay)
    if not to then return end
    -- Back in its own group is no move at all.
    settings[MoveKey(entry)] = (to ~= entry.home) and to or nil
    Render()
end

local function SetArmEditing(on)
    editingArms = on and true or false
    OxedHub._tpEditingArms = editingArms
    if editingArms and settings.layout ~= "spiral" then settings.layout = "spiral" end
    Render()
    PlaceHandles()
end

local subPath = {}
RenderSpiral = function(groups, size)
    local Data = OxedHub.TeleportsData
    for key, strip in pairs(strips) do
        if key ~= SPIRAL_KEY then strip:Hide() end
    end

    local spiral = strips[SPIRAL_KEY]
    if not spiral then
        spiral = CreateFrame("Frame", nil, UIParent)
        spiral:SetFrameStrata("DIALOG")
        spiral:SetFrameLevel(200)
        spiral:EnableMouse(false)
        spiral.buttons = {}
        spiral:Hide()
        strips[SPIRAL_KEY] = spiral
    end
    for _, button in ipairs(spiral.buttons) do button:Hide() end

    local visible = {}
    for _, groupKey in ipairs(Data.GROUP_ORDER) do
        if #(groups[groupKey] or {}) > 0 then visible[#visible + 1] = groupKey end
    end

    local round = settings.spiralRound ~= false
    local step = size + GAP
    local start = ButtonSize() / 2 + size / 2 + GAP * 2
    -- ⚠ At most perArm icons in one arm. A group longer than that goes on
    -- in another arm beside the first, the same shape turned one icon's
    -- width further round: a single arm of a hundred icons ran off the screen.
    local perArm = math.max(5, math.min(80, tonumber(settings.perArm) or 25))
    local besideStep = (step / start) * 1.05
    local count, reach = 0, 0

    for armIndex, groupKey in ipairs(visible) do
        local list = groups[groupKey]
        local a = math.rad(ArmAngle(groupKey, armIndex, #visible))
        local curl = ArmCurl(groupKey)
        local length = math.max(3, math.min(#list, perArm)) * step
        local path = BuildPath(groupKey, a, curl, length, start, armPaths[groupKey])
        armPaths[groupKey] = path

        for index, entry in ipairs(list) do
            local sub = math.floor((index - 1) / perArm)
            local along = ((index - 1) % perArm) * step
            -- Every arm after the first is the first turned round the button.
            if along == 0 then
                local turn = besideStep * sub
                local cosT, sinT = math.cos(turn), math.sin(turn)
                for n = 1, #path do
                    subPath[n] = subPath[n] or {}
                    subPath[n][1] = path[n][1] * cosT - path[n][2] * sinT
                    subPath[n][2] = path[n][1] * sinT + path[n][2] * cosT
                end
                for n = #path + 1, #subPath do subPath[n] = nil end
                Smooth(subPath, polyline)
            end
            local x, y = PointAlong(polyline, along)

            count = count + 1
            local button = spiral.buttons[count] or CreateButton(spiral, count)
            button:SetSize(size, size)
            button:ClearAllPoints()
            button:SetPoint("CENTER", spiral, "CENTER", x, y)
            button.entry = entry
            button.icon:SetTexture(entry.icon or 134400)
            button.icon:SetDesaturated(entry.hidden == true)
            SetRound(button, round)
            SetAction(button, entry)
            PaintCooldown(button, entry)
            button:Show()
            -- While the arms are edited the icons are only a picture of the
            -- shape: no click may cast one, and they are dimmed to show it.
            -- (Editing is out of combat only, so a secure button may change.)
            button:EnableMouse(true)
            if editingArms then
                -- Carried to another arm, never cast.
                button:SetAttribute("type1", nil)
                if not button.carryHooked then
                    button.carryHooked = true
                    button:RegisterForDrag("LeftButton")
                    button:SetScript("OnDragStart", function(self) StartCarry(self) end)
                    button:SetScript("OnDragStop", function() DropCarry() end)
                end
            end
            button:SetAlpha(editingArms and 0.55 or 1)
            local r = math.sqrt(x * x + y * y)
            if r > reach then reach = r end
        end
        for n = 2, #path do
            local p = path[n]
            local r = math.sqrt(p[1] * p[1] + p[2] * p[2])
            if r > reach then reach = r end
        end
        for point = 1, BEND_MAX do Handle(groupKey, point, spiral) end
    end
    -- A group that is not drawn this time has no path to put handles on.
    for groupKey in pairs(armPaths) do
        if #(groups[groupKey] or {}) == 0 then armPaths[groupKey] = nil end
    end

    local span = 2 * (reach + size + 30)
    spiral:SetSize(math.max(span, 1), math.max(span, 1))
    spiral:ClearAllPoints()
    spiral:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    spiral:SetShown(opened and count > 0)
    PlaceHandles()

    if opened and count == 0 then
        print("|cff00ff00OxedHub:|r no teleports found yet. Hearthstones, toys and your class's own teleports appear as you get them.")
        CloseAll()
    end
end


function Render()
    if InCombatLockdown() then return end

    local Data = OxedHub.TeleportsData
    local groups = CollectEntries()
    local size = IconSize()
    -- Teleports the player moved to another arm.
    ApplyMoves(groups)

    -- Simulate: copies of the real teleports added to the last group, to see
    -- how a big collection lays out. Not saved; a reload clears it.
    if simulated > 0 then
        local real = {}
        for _, groupKey in ipairs(Data.GROUP_ORDER) do
            for _, entry in ipairs(groups[groupKey] or {}) do real[#real + 1] = entry end
        end
        local lastKey = Data.GROUP_ORDER[#Data.GROUP_ORDER]
        if #real > 0 and lastKey then
            local list = groups[lastKey] or {}
            groups[lastKey] = list
            for i = 1, simulated do list[#list + 1] = real[(i - 1) % #real + 1] end
        end
    end

    if settings.layout == "spiral" then
        return RenderSpiral(groups, size)
    end
    if strips[SPIRAL_KEY] then strips[SPIRAL_KEY]:Hide() end
    local perLine = math.max(4, math.min(20, tonumber(settings.perLine) or 12))

    -- How far each direction has been filled already, so two groups sent the
    -- same way sit behind one another instead of on top of one another.
    local used = { right = 0, left = 0, up = 0, down = 0 }
    local anyShown = false

    -- Every button in every strip takes the current size, including the ones
    -- about to be hidden. Sizing only what is drawn this time leaves a button
    -- that was built at the old size still wearing it when its group comes
    -- back -- which is how one row ended up with icons twice the others'.
    for _, strip in pairs(strips) do
        for _, button in ipairs(strip.buttons) do
            button:SetSize(size, size)
        end
    end

    for _, groupKey in ipairs(Data.GROUP_ORDER) do
        local list = groups[groupKey] or {}
        local strip = strips[groupKey]

        if #list == 0 then
            if strip then strip:Hide() end
        else
            strip = EnsureStrip(groupKey)
            for _, button in ipairs(strip.buttons) do button:Hide() end

            local direction = GroupDirection(groupKey)
            local vertical = direction == "up" or direction == "down"
            local lines = math.ceil(#list / perLine)
            local perLineHere = math.min(#list, perLine)

            for index, entry in ipairs(list) do
                local button = strip.buttons[index] or CreateButton(strip, index)
                local slot = (index - 1) % perLine
                local line = math.floor((index - 1) / perLine)

                button:SetSize(size, size)
                button:ClearAllPoints()
                if vertical then
                    button:SetPoint("TOPLEFT", strip, "TOPLEFT",
                        8 + line * (size + GAP), -8 - slot * (size + GAP))
                else
                    button:SetPoint("TOPLEFT", strip, "TOPLEFT",
                        8 + slot * (size + GAP), -8 - line * (size + GAP))
                end

                button.entry = entry
                button.icon:SetTexture(entry.icon or 134400)
                -- Anything put away is only on screen because "show hidden" is
                -- on: greyed, so it reads as switched off rather than ready.
                button.icon:SetDesaturated(entry.hidden == true)
                SetRound(button, settings.spiralRound ~= false)
                SetAction(button, entry)
                PaintCooldown(button, entry)
                button:Show()
            end

            local lengthwise = perLineHere * (size + GAP) - GAP + 16
            local crosswise = lines * (size + GAP) - GAP + 16
            if vertical then
                strip:SetSize(crosswise, lengthwise)
            else
                strip:SetSize(lengthwise, crosswise)
            end

            -- Placed against the button and lined up with its middle, then
            -- pushed out past whatever already went this way.
            --
            -- Groups sharing a direction carry on along that line, one after
            -- another. Stacking them across it instead is what sent them off
            -- sideways: two groups sent down ended up side by side rather than
            -- one below the other.
            local offset = used[direction]
            strip:ClearAllPoints()
            if direction == "left" then
                strip:SetPoint("RIGHT", anchor, "LEFT", -4 - offset, 0)
                used.left = offset + strip:GetWidth() + STRIP_GAP
            elseif direction == "up" then
                strip:SetPoint("BOTTOM", anchor, "TOP", 0, 4 + offset)
                used.up = offset + strip:GetHeight() + STRIP_GAP
            elseif direction == "down" then
                strip:SetPoint("TOP", anchor, "BOTTOM", 0, -4 - offset)
                used.down = offset + strip:GetHeight() + STRIP_GAP
            else
                strip:SetPoint("LEFT", anchor, "RIGHT", 4 + offset, 0)
                used.right = offset + strip:GetWidth() + STRIP_GAP
            end

            strip:SetShown(opened)
            anyShown = true
        end
    end

    if opened and not anyShown then
        print("|cff00ff00OxedHub:|r no teleports found yet. Hearthstones, toys and your class's own teleports appear as you get them.")
        CloseAll()
    end
end

function QueueRender()
    if not opened then return end
    if InCombatLockdown() then
        pendingRebuild = true
        return
    end
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.2, function()
        rebuildQueued = false
        Render()
    end)
end

local function OpenAll()
    if InCombatLockdown() then
        print("|cff00ff00OxedHub:|r teleports cannot be laid out during combat.")
        return
    end
    EnsureAnchor()
    opened = true
    Render()
    closeWatcher.timer = 0
    closeWatcher:Show()
end

local function Toggle()
    if not settings or settings.enabled == false then
        print("|cff00ff00OxedHub:|r the Teleports module is switched off. Turn it on in Modules.")
        return
    end
    if opened then CloseAll() else OpenAll() end
end

-- ── The button ──────────────────────────────────────────────────────────────
-- Plain, not secure: it only opens the rows, and nothing it does is protected.

function EnsureAnchor()
    if anchor then return anchor end

    anchor = CreateFrame("Button", "OxedHubTeleportsButton", UIParent)
    anchor:SetSize(ButtonSize(), ButtonSize())
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local ring = anchor:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", 2, -2)
    ring:SetColorTexture(0, 0, 0, 0.9)
    anchor.ring = ring

    local icon = anchor:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    anchor.icon = icon

    anchor:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Teleports")
        GameTooltip:AddLine("Click for your teleports, or type /tp.", 1, 1, 1)
        GameTooltip:AddLine("Each group flies out its own way -- set that in Options.", 0.6, 0.8, 1)
        if settings.lockButton then
            GameTooltip:AddLine("Shift-drag to move it.", 0.6, 0.8, 1)
        else
            GameTooltip:AddLine("Drag to move it.", 0.6, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    anchor:SetScript("OnClick", function() Toggle() end)

    anchor:SetScript("OnDragStart", function(self)
        -- Locked, it still moves with Shift held.
        if (settings.lockButton and not IsShiftKeyDown()) or InCombatLockdown() then return end
        self.dragging = true
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = false
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        settings.btnPoint, settings.btnX, settings.btnY = point, x, y
        if opened then Render() end
    end)

    anchor:ClearAllPoints()
    anchor:SetPoint(settings.btnPoint or "CENTER", UIParent,
        settings.btnPoint or "CENTER", settings.btnX or 0, settings.btnY or -120)
    anchor:Hide()
    return anchor
end

-- The main button square or round: a round mask on its icon and its dark
-- edge, so the edge stays a ring around the icon.
local function ApplyButtonShape()
    if not (anchor and anchor.icon) then return end
    local round = settings.buttonRound == true
    if not anchor.roundMask then
        if not round then return end
        anchor.roundMask = anchor:CreateMaskTexture()
        anchor.roundMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        anchor.roundMask:SetAllPoints(anchor.icon)
        anchor.ringMask = anchor:CreateMaskTexture()
        anchor.ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        anchor.ringMask:SetAllPoints(anchor.ring)
    end
    if round and not anchor.isRound then
        anchor.icon:AddMaskTexture(anchor.roundMask)
        anchor.ring:AddMaskTexture(anchor.ringMask)
        local hl = anchor:GetHighlightTexture()
        if hl then hl:SetAlpha(0.5) end
        anchor.isRound = true
    elseif not round and anchor.isRound then
        anchor.icon:RemoveMaskTexture(anchor.roundMask)
        anchor.ring:RemoveMaskTexture(anchor.ringMask)
        local hl = anchor:GetHighlightTexture()
        if hl then hl:SetAlpha(1) end
        anchor.isRound = false
    end
end

local function ApplyButton()
    if not settings then return end
    if settings.showButton then
        EnsureAnchor()
        anchor:SetSize(ButtonSize(), ButtonSize())
        ApplyButtonShape()
        anchor:Show()
    elseif anchor then
        anchor:Hide()
        CloseAll()
    end
end

-- ── Events ──────────────────────────────────────────────────────────────────

watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingRebuild then
            pendingRebuild = false
            Render()
        end
        return
    end
    QueueRender()
end)

local function Start()
    EnsureAnchor()
    ApplyButton()
    watcher:RegisterEvent("BAG_UPDATE_DELAYED")
    watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    watcher:RegisterEvent("TOYS_UPDATED")
    watcher:RegisterEvent("SPELLS_CHANGED")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function Stop()
    watcher:UnregisterAllEvents()
    CloseAll()
    if anchor then anchor:Hide() end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.teleports
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.teleports = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Built here rather than in DEFAULTS: a table there is copied by reference,
    -- and every character would put entries away in one shared list.
    if type(config.hidden) ~= "table" then config.hidden = {} end
    settings = config
end

-- One row per group: a tick box that hides the whole group, and four arrows
-- for the way it flies out. Both on the same line, because "do I want this at
-- all" and "where does it go" are the same decision.
local function AddDirectionRow(w, groupKey, label)
    local settingKey = GROUP_SETTING[groupKey]

    local check = CreateFrame("CheckButton", nil, w, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", w, "TOPLEFT", 16, w.cursorY)
    check.text:SetFontObject("GameFontHighlight")
    check.text:SetText(label)
    check:SetScript("OnClick", function(self)
        settings[settingKey] = self:GetChecked() and true or false
        if opened then Render() end
    end)
    w:HookScript("OnShow", function()
        check:SetChecked(settings[settingKey] == true)
    end)
    check:SetChecked(settings[settingKey] == true)

    local ARROWS = {
        { key = "left",  text = "<" },
        { key = "down",  text = "v" },
        { key = "up",    text = "^" },
        { key = "right", text = ">" },
    }

    local buttonsHere = {}
    local function Repaint()
        local current = GroupDirection(groupKey)
        for _, entry in ipairs(buttonsHere) do
            if entry.key == current then
                entry.button:SetNormalFontObject("GameFontNormalLarge")
            else
                entry.button:SetNormalFontObject("GameFontDisableSmall")
            end
        end
    end

    local previous
    for _, arrow in ipairs(ARROWS) do
        local button = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        button:SetSize(26, 22)
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 2, 0)
        else
            button:SetPoint("TOPLEFT", w, "TOPLEFT", 250, w.cursorY - 2)
        end
        button:SetText(arrow.text)
        button:SetScript("OnClick", function()
            settings["dir_" .. groupKey] = arrow.key
            Repaint()
            if opened then Render() end
        end)
        previous = button
        buttonsHere[#buttonsHere + 1] = { key = arrow.key, button = button }
    end

    w:HookScript("OnShow", Repaint)
    Repaint()

    -- In the spiral the arrows mean nothing: the row shows the arm instead --
    -- its colour, how many bend points it has (- and + change that), and a
    -- reset. Which set shows follows the Layout choice (ShowLayoutControls).
    w.rowsOnly = w.rowsOnly or {}
    w.spiralOnly = w.spiralOnly or {}
    for _, entry in ipairs(buttonsHere) do table.insert(w.rowsOnly, entry.button) end

    local c = ARM_COLOURS[groupKey] or { 1, 1, 1 }
    local dot = w:CreateTexture(nil, "ARTWORK")
    dot:SetSize(14, 14)
    dot:SetPoint("TOPLEFT", w, "TOPLEFT", 250, w.cursorY - 6)
    dot:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    dot:SetVertexColor(c[1], c[2], c[3], 1)
    table.insert(w.spiralOnly, dot)

    local count = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    count:SetWidth(52)
    count:SetJustifyH("LEFT")
    table.insert(w.spiralOnly, count)
    local function ShowCount()
        count:SetFormattedText("%d %s", PointCount(groupKey), HasCustomPath(groupKey) and "pts" or "pts |cff9d9d9d(auto)|r")
    end

    local function Small(text, onClick, anchorTo, x)
        local b = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        b:SetSize(text == "Reset" and 52 or 24, 20)
        b:SetPoint("LEFT", anchorTo, "RIGHT", x, 0)
        b:SetText(text)
        b:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            -- The arm has to be drawn once for its points to be known.
            if not opened then OpenAll() end
            onClick()
            ShowCount()
            if opened then Render() end
        end)
        table.insert(w.spiralOnly, b)
        return b
    end
    local minus = Small("-", function()
        local n = PointCount(groupKey)
        if n > BEND_MIN then RemovePoint(groupKey, n - 1) end
    end, count, 2)
    local plus = Small("+", function()
        local n = PointCount(groupKey)
        if n < BEND_MAX then AddPointAfter(groupKey, n - 1) end
    end, minus, 2)
    Small("Reset", function() ResetGroupShape(groupKey) end, plus, 6)

    w:HookScript("OnShow", ShowCount)
    ShowCount()
    w.cursorY = w.cursorY - 26
end

-- Rows show the direction arrows, the spiral its arm controls.
local function ShowLayoutControls(w)
    local spiral = settings.layout == "spiral"
    for _, region in ipairs(w.rowsOnly or {}) do region:SetShown(not spiral) end
    for _, region in ipairs(w.spiralOnly or {}) do region:SetShown(spiral) end
end

-- One slider builder for both sizes: the icons that fly out, and the button.
local function AddSizeSlider(w, key, caption, apply)
    local label = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)

    local slider = CreateFrame("Slider", nil, w, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(240, 16)
    slider:SetPoint("TOPLEFT", w, "TOPLEFT", 24, w.cursorY - 26)
    slider:SetMinMaxValues(ICON_MIN, ICON_MAX)
    slider:SetValueStep(2)
    slider:SetObeyStepOnDrag(true)

    local function Current()
        return math.max(ICON_MIN, math.min(ICON_MAX, tonumber(settings[key]) or 32))
    end
    local function ShowValue(value) label:SetText(("%s: %d"):format(caption, value)) end

    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        ShowValue(value)
        if value ~= Current() then
            settings[key] = value
            if apply then apply() end
        end
    end)
    w:HookScript("OnShow", function()
        local size = Current()
        slider:SetValue(size)
        ShowValue(size)
    end)
    w.cursorY = w.cursorY - 54
end

-- ── All teleports ───────────────────────────────────────────────────────────
-- Every teleport you have, in one list grouped the way they fly out: each
-- group under its coloured header (click it to fold), each teleport with a
-- Shown/Hidden switch and a "Move to" menu for another group. A search box
-- narrows it. Only the rows that fit are drawn; the wheel moves the rest.
local listWindow
local LIST_W, LIST_H = 520, 560
local LIST_TOP, LIST_ROW = 74, 28
local GROUP_NAME = {
    hearth = "Hearthstones", class = "Class teleports", portal = "Portals for the group",
    toy = "Teleport toys", item = "Items in your bags", equip = "Worn cloak or ring",
}

local listEntries = {}    -- headers and teleports, as drawn
local listOffset = 0
local listCollapsed = {}  -- group -> folded, for this session
local visibleListRows = 0

local function Hex(c)
    return ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

local function GatherAll()
    wipe(listEntries)
    -- Hidden ones too: this list is where they are switched back on.
    local was = settings.showHidden
    settings.showHidden = true
    local ok, groups = pcall(CollectEntries)
    settings.showHidden = was
    if not ok or type(groups) ~= "table" then return 0, 0 end
    ApplyMoves(groups)

    local query = listWindow and listWindow.search and listWindow.search:GetText() or ""
    query = query:lower()
    local total, hidden = 0, 0
    for _, groupKey in ipairs(OxedHub.TeleportsData.GROUP_ORDER) do
        local list = groups[groupKey] or {}
        local shownHere = {}
        for _, entry in ipairs(list) do
            total = total + 1
            if IsHidden(entry.kind, entry.id) then hidden = hidden + 1 end
            if query == "" or (entry.name or ""):lower():find(query, 1, true) then
                entry.group = groupKey
                shownHere[#shownHere + 1] = entry
            end
        end
        if #shownHere > 0 then
            listEntries[#listEntries + 1] = { header = true, group = groupKey, count = #shownHere }
            if not listCollapsed[groupKey] or query ~= "" then
                for _, entry in ipairs(shownHere) do listEntries[#listEntries + 1] = entry end
            end
        end
    end
    return total, hidden
end

local DrawList

-- "Move to": the groups by name, each in its colour, the current one ticked.
local function MoveMenu(owner, entry)
    local order = OxedHub.TeleportsData.GROUP_ORDER
    local function MoveTo(to)
        settings[MoveKey(entry)] = (to ~= entry.home) and to or nil
        QueueRender()
        DrawList()
    end
    if MenuUtil and MenuUtil.CreateContextMenu then
        local ok = pcall(MenuUtil.CreateContextMenu, owner, function(_, root)
            root:CreateTitle("Move to")
            for _, key in ipairs(order) do
                local c = ARM_COLOURS[key] or { 1, 1, 1 }
                local label = ("|cff%s%s|r%s"):format(Hex(c), GROUP_NAME[key] or key,
                    key == entry.group and "  |cff9d9d9d(here)|r" or "")
                root:CreateButton(label, function() MoveTo(key) end)
            end
            if entry.home and entry.group ~= entry.home then
                root:CreateDivider()
                root:CreateButton("Back to " .. (GROUP_NAME[entry.home] or entry.home), function() MoveTo(entry.home) end)
            end
        end)
        if ok then return end
    end
    -- No menu in this client: the next group instead.
    local at = 1
    for i, key in ipairs(order) do if key == entry.group then at = i end end
    MoveTo(order[at % #order + 1])
end

local function ListRow(w, i)
    local row = w.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, w.list)
    row:SetHeight(LIST_ROW)
    row:SetPoint("TOPLEFT", w.list, "TOPLEFT", 0, -(i - 1) * LIST_ROW)
    row:SetPoint("TOPRIGHT", w.list, "TOPRIGHT", 0, -(i - 1) * LIST_ROW)
    row:RegisterForClicks("LeftButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.07)

    -- A header: colour bar, name, count.
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetSize(4, LIST_ROW - 8)
    row.bar:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.fold = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.fold:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("LEFT", row.fold, "RIGHT", 6, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.count:SetPoint("LEFT", row.title, "RIGHT", 8, 0)
    row.line = row:CreateTexture(nil, "BACKGROUND")
    row.line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)
    row.line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 1)
    row.line:SetHeight(1)

    -- A teleport: icon, name, Shown/Hidden, Move to.
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -196, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    local function TextButton(width)
        local b = CreateFrame("Button", nil, row)
        b:SetSize(width, LIST_ROW - 6)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.45)
        b.bg = bg
        local edge = b:CreateTexture(nil, "BORDER")
        edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT")
        edge:SetHeight(1)
        b.edge = edge
        local bhl = b:CreateTexture(nil, "HIGHLIGHT")
        bhl:SetAllPoints()
        bhl:SetColorTexture(1, 1, 1, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        return b
    end

    row.move = TextButton(116)
    row.move:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.move:SetScript("OnClick", function(self) if row.entry then MoveMenu(self, row.entry) end end)

    row.toggle = TextButton(70)
    row.toggle:SetPoint("RIGHT", row.move, "LEFT", -6, 0)
    row.toggle:SetScript("OnClick", function()
        local entry = row.entry
        if not entry then return end
        settings.hidden = settings.hidden or {}
        local key = EntryKey(entry.kind, entry.id)
        settings.hidden[key] = (not settings.hidden[key]) or nil
        QueueRender()
        DrawList()
    end)

    row:SetScript("OnClick", function(self)
        local item = self.item
        if item and item.header then
            listCollapsed[item.group] = not listCollapsed[item.group] or nil
            DrawList()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if self.entry then ShowEntryTooltip(self) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    w.rows[i] = row
    return row
end

local function PaintRow(row, item)
    row.item = item
    local isHeader = item.header == true
    for _, part in ipairs({ row.bar, row.fold, row.title, row.count, row.line }) do part:SetShown(isHeader) end
    for _, part in ipairs({ row.icon, row.name, row.toggle, row.move }) do part:SetShown(not isHeader) end

    if isHeader then
        row.entry = nil
        local c = ARM_COLOURS[item.group] or { 1, 1, 1 }
        row.bar:SetColorTexture(c[1], c[2], c[3], 1)
        row.line:SetColorTexture(c[1], c[2], c[3], 0.35)
        row.fold:SetText(listCollapsed[item.group] and "+" or "-")
        row.title:SetText(GROUP_NAME[item.group] or item.group)
        row.title:SetTextColor(c[1], c[2], c[3])
        row.count:SetText(item.count)
        return
    end

    local entry = item
    row.entry = entry
    local hidden = IsHidden(entry.kind, entry.id)
    row.icon:SetTexture(entry.icon or 134400)
    row.icon:SetDesaturated(hidden)
    row.name:SetText(entry.name or "?")
    row.name:SetTextColor(hidden and 0.55 or 1, hidden and 0.55 or 1, hidden and 0.55 or 1)

    if hidden then
        row.toggle.text:SetText("|cff9d9d9dHidden|r")
        row.toggle.edge:SetColorTexture(0.6, 0.6, 0.6, 0.5)
    else
        row.toggle.text:SetText("|cff40ff40Shown|r")
        row.toggle.edge:SetColorTexture(0.25, 1, 0.25, 0.6)
    end

    local c = ARM_COLOURS[entry.group] or { 1, 1, 1 }
    local moved = entry.home and entry.group ~= entry.home
    row.move.text:SetText(moved and ("|cff%sMoved here|r  v"):format(Hex(c)) or "Move to  v")
    row.move.edge:SetColorTexture(c[1], c[2], c[3], 0.7)
end

DrawList = function()
    local w = listWindow
    if not (w and w:IsShown()) then return end
    local total, hidden = GatherAll()
    w.head:SetFormattedText("%d teleports%s", total,
        hidden > 0 and ("   |cff9d9d9d%d hidden|r"):format(hidden) or "")

    local maxOffset = math.max(0, #listEntries - visibleListRows)
    listOffset = math.max(0, math.min(listOffset, maxOffset))
    w.scroll:SetMinMaxValues(0, maxOffset)
    w.scroll:SetShown(maxOffset > 0)
    if math.floor(w.scroll:GetValue() + 0.5) ~= listOffset then w.scroll:SetValue(listOffset) end

    for i = 1, visibleListRows do
        local item = listEntries[listOffset + i]
        local row = ListRow(w, i)
        if item then
            PaintRow(row, item)
            row:Show()
        else
            row.item, row.entry = nil, nil
            row:Hide()
        end
    end
    w.empty:SetShown(#listEntries == 0)
end

local function ShowTeleportList()
    if not settings then return end
    if not listWindow then
        -- The grey frame every module's options use, opened beside the
        -- Teleports options rather than over them.
        local API = OxedHub.ModuleAPI
        if not (API and API.CreateOptionsWindow) then return end
        local w = API:CreateOptionsWindow("All teleports", LIST_W, LIST_H)

        -- ⚠ SetAutoFocus(false) first: a new EditBox takes the keyboard.
        local okSearch, search = pcall(CreateFrame, "EditBox", nil, w, "SearchBoxTemplate")
        if not okSearch or not search then search = CreateFrame("EditBox", nil, w, "InputBoxTemplate") end
        search:SetAutoFocus(false)
        search:SetSize(200, 20)
        search:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -32)
        search:HookScript("OnTextChanged", function() listOffset = 0 DrawList() end)
        search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        w.search = search

        w.head = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        w.head:SetPoint("LEFT", search, "RIGHT", 16, 0)

        local line = w:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -LIST_TOP + 10)
        line:SetPoint("TOPRIGHT", w, "TOPRIGHT", -16, -LIST_TOP + 10)
        line:SetHeight(1)
        line:SetColorTexture(1, 0.82, 0, 0.3)

        local list = CreateFrame("Frame", nil, w)
        list:SetPoint("TOPLEFT", w, "TOPLEFT", 16, -LIST_TOP)
        list:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -28, 34)
        list:EnableMouseWheel(true)
        w.list = list
        visibleListRows = math.floor((LIST_H - LIST_TOP - 34) / LIST_ROW)

        local scroll = CreateFrame("Slider", nil, w)
        scroll:SetOrientation("VERTICAL")
        scroll:SetWidth(8)
        scroll:SetPoint("TOPRIGHT", w, "TOPRIGHT", -14, -LIST_TOP)
        scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -14, 36)
        scroll:SetValueStep(1)
        scroll:SetObeyStepOnDrag(true)
        local track = scroll:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(0, 0, 0, 0.45)
        local thumb = scroll:CreateTexture(nil, "OVERLAY")
        thumb:SetColorTexture(1, 0.82, 0, 0.55)
        thumb:SetSize(8, 34)
        scroll:SetThumbTexture(thumb)
        scroll:SetScript("OnValueChanged", function(_, value)
            local wanted = math.floor(value + 0.5)
            if wanted ~= listOffset then listOffset = wanted DrawList() end
        end)
        w.scroll = scroll
        list:SetScript("OnMouseWheel", function(_, delta)
            local low, high = scroll:GetMinMaxValues()
            scroll:SetValue(math.max(low, math.min(high, listOffset - delta * 3)))
        end)

        w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        w.empty:SetPoint("CENTER", list, "CENTER")
        w.empty:SetText("Nothing matches")

        local foot = w:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        foot:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 20, 14)
        foot:SetText("Click a group's name to fold it. Hover a teleport for what it does.")

        w.rows = {}
        -- Hooked: the options window has its own OnShow (it places itself).
        w:HookScript("OnShow", DrawList)
        w:Hide()
        listWindow = w
    end
    listWindow:SetShown(not listWindow:IsShown())
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Teleports", 460, 780)
        local w = optionsWindow

        -- Untick a group to hide it; the arrows say which way it comes out.
        AddDirectionRow(w, "hearth", "Hearthstones")
        AddDirectionRow(w, "class",  "Class teleports")
        AddDirectionRow(w, "portal", "Portals for the group")
        AddDirectionRow(w, "toy",    "Teleport toys")
        AddDirectionRow(w, "item",   "Items in your bags")
        AddDirectionRow(w, "equip",  "Worn cloak or ring")

        w:AddCheckbox(settings, "closeAfterUse", "Fold away after use")
        w:AddCheckbox(settings, "closeOnLeave", "Fold away when the mouse leaves")
        w:AddCheckbox(settings, "showButton", "Show the button on screen", nil, ApplyButton)
        w:AddCheckbox(settings, "lockButton", "Lock the button in place")
        w:AddCheckbox(settings, "showHidden", "Show the ones you put away",
            "Right-clicking an icon puts it away. Tick this to see them again, greyed out, and right-click one to bring it back.", Render)

        w:AddChoice(settings, "layout", "Layout", {
            { value = "rows", text = "A row per group" },
            { value = "spiral", text = "Spiral around the button" },
        }, function()
            ShowLayoutControls(w)
            if opened then Render() end
        end)
        w:HookScript("OnShow", function() ShowLayoutControls(w) end)
        w:AddCheckbox(settings, "buttonRound", "Round main button", nil, ApplyButton)
        w:AddCheckbox(settings, "spiralRound", "Round teleport icons", nil, function()
            if opened then Render() end
        end)

        -- See how a big collection looks: copies of your own teleports.
        local all = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        all:SetSize(308, 22)
        all:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        all:SetText("All teleports: show, hide, move")
        all:SetScript("OnClick", ShowTeleportList)
        w.cursorY = w.cursorY - 30

        local sim = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        sim:SetSize(150, 22)
        sim:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        sim:SetText("Simulate +100")
        sim:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            simulated = simulated + 100
            print(("|cff00ff00OxedHub:|r Teleports: simulating %d extra icons (copies of yours, not saved)."):format(simulated))
            if opened then Render() else OpenAll() end
        end)
        local clear = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        clear:SetSize(150, 22)
        clear:SetPoint("LEFT", sim, "RIGHT", 8, 0)
        clear:SetText("Clear simulation")
        clear:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            simulated = 0
            if opened then Render() end
        end)
        w.cursorY = w.cursorY - 30

        -- The visual editor: a coloured handle at the end of each arm.
        local edit = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        edit:SetSize(150, 22)
        edit:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        edit.Refresh = function() edit:SetText(editingArms and "Done editing arms" or "Edit the arms") end
        edit:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            if not opened then OpenAll() end
            SetArmEditing(not editingArms)
            edit.Refresh()
        end)
        table.insert(w.checks, edit)
        table.insert(w.spiralOnly, edit)
        local reset = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        reset:SetSize(150, 22)
        reset:SetPoint("LEFT", edit, "RIGHT", 8, 0)
        table.insert(w.spiralOnly, reset)
        reset:SetText("Reset the arms")
        reset:SetScript("OnClick", function()
            for _, groupKey in ipairs(OxedHub.TeleportsData.GROUP_ORDER) do
                ResetGroupShape(groupKey)
            end
            if opened and not InCombatLockdown() then Render() end
        end)
        w.cursorY = w.cursorY - 30
        w:HookScript("OnHide", function()
            if editingArms then SetArmEditing(false) end
        end)

        w:AddSlider(settings, "perArm", "Icons per arm", 5, 80, 1, "%s: %d", function()
            if opened and not InCombatLockdown() then Render() end
        end)

        AddSizeSlider(w, "iconSize", "Icon size", function()
            if opened then Render() end
        end)
        AddSizeSlider(w, "buttonSize", "Button size", ApplyButton)

        w:AddNote("Rows: the arrows send each group its own way. Spiral: each group is an arm. Edit the arms, then drag its points; Shift-click a point adds one after it, Ctrl-click removes it, right-click resets the arm. While editing, drag a teleport onto another arm to move it there. Left-click an icon to travel, right-click to put it away. Shift-drag moves a locked button.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

SLASH_OXEDHUBTELEPORTS1 = "/tp"
SLASH_OXEDHUBTELEPORTS2 = "/teleports"
SlashCmdList["OXEDHUBTELEPORTS"] = function() Toggle() end

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
        id       = "teleports",
        name     = "Teleports",
        version  = "1.4.2",
        updated  = 20261016.9,   -- All teleports list in the grey module frame
        author   = "Oxed",
        category = "quests",
        keywords = { "teleport", "portal", "hearthstone", "travel", "mage", "wormhole", "toy", "death gate" },
        -- Clipped at about 100 characters on the card; detail goes in Options.
        desc     = "A button your teleports fly out of, each group its own way. /tp",
        icon     = "Interface\\Icons\\Spell_Arcane_PortalDalaran",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
