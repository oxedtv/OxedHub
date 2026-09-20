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

local ICON_MIN, ICON_MAX = 24, 54
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

function Render()
    if InCombatLockdown() then return end

    local Data = OxedHub.TeleportsData
    local groups = CollectEntries()
    local size = IconSize()
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

    local icon = anchor:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    anchor:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    anchor:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Teleports")
        GameTooltip:AddLine("Click for your teleports, or type /tp.", 1, 1, 1)
        GameTooltip:AddLine("Each group flies out its own way -- set that in Options.", 0.6, 0.8, 1)
        if not settings.lockButton then
            GameTooltip:AddLine("Drag to move it.", 0.6, 0.8, 1)
        end
        GameTooltip:Show()
    end)
    anchor:SetScript("OnLeave", function() GameTooltip:Hide() end)
    anchor:SetScript("OnClick", function() Toggle() end)

    anchor:SetScript("OnDragStart", function(self)
        if settings.lockButton or InCombatLockdown() then return end
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

local function ApplyButton()
    if not settings then return end
    if settings.showButton then
        EnsureAnchor()
        anchor:SetSize(ButtonSize(), ButtonSize())
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
    w.cursorY = w.cursorY - 26
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

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Teleports", 460, 560)
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

        AddSizeSlider(w, "iconSize", "Icon size", function()
            if opened then Render() end
        end)
        AddSizeSlider(w, "buttonSize", "Button size", ApplyButton)

        w:AddNote("Groups sent the same way stack up behind each other. Left-click an icon to travel, right-click to put it away.")
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
        version  = "1.1.0",
        author   = "Oxed",
        category = "tools",
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
