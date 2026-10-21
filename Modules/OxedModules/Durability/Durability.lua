-- ============================================================================
-- Durability (built-in OxedHub module)
-- How worn your gear is, without opening the character window:
--
--   * A small movable readout: the lowest item (or the average) with the
--     repair icon, coloured green to red. Can show always or only when low.
--     Below the warning line it turns red and pulses, with a sound once.
--   * Its tooltip: every slot from worst to best, the estimated repair cost,
--     and worn items in your bags.
--   * A chat reminder when it matters: entering a dungeon, raid, arena or
--     delve, coming back from death, and arriving in a city or inn. Broken
--     items are named.
--   * /dura prints it all; /dura move shows the readout to drag.
--
-- Repairing itself is AutoVendor's job (it repairs at vendors, guild bank
-- first if you like); this module only tells you when to go.
--
-- Durability and tooltip reads go through pcall and a plain-number check: in
-- combat a value may come back secret, and then the last good figures stay.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled        = false,  -- off until the player switches it on (see ModuleAPI:Register)
    showDisplay    = true,   -- the readout on screen
    displayAlways  = true,   -- false: only while below remindBelow
    showValue      = "lowest", -- "lowest" item or "average" of all
    warnBelow      = 30,     -- red, pulsing, and the warning sound
    remindBelow    = 50,     -- chat reminders below this
    remindInstance = true,   -- on entering a dungeon, raid, arena or delve
    remindRes      = true,   -- on coming back from death
    remindCity     = true,   -- on arriving somewhere restful (cities, inns)
    warnSound      = "",     -- once, when the lowest item drops below warnBelow
    remindSound    = "",     -- with each chat reminder
    bagItems       = true,   -- worn items in your bags, in the tooltip
    locked         = false,
    scale          = 1,
    fontSize       = 16,
    bgAlpha        = 0,
    point = "TOP", x = 260, y = -16,
}

local settings
local optionsWindow
local display
local watcher = CreateFrame("Frame")
local PREFIX = "|cff00ff00OxedHub:|r "
local REPAIR_ICON = "Interface\\MINIMAP\\TRACKING\\Repair"

-- Equipment slots that wear: shirt (4) and tabard (19) never do.
local SLOTS = {
    { 1, "Head" }, { 2, "Neck" }, { 3, "Shoulder" }, { 15, "Back" }, { 5, "Chest" },
    { 9, "Wrist" }, { 10, "Hands" }, { 6, "Waist" }, { 7, "Legs" }, { 8, "Feet" },
    { 11, "Ring" }, { 12, "Ring" }, { 13, "Trinket" }, { 14, "Trinket" },
    { 16, "Main hand" }, { 17, "Off hand" }, { 18, "Ranged" },
}

local function Active(option)
    return settings and settings.enabled == true and (option == nil or settings[option] ~= false)
end

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Num(v)
    v = Plain(v)
    return type(v) == "number" and v or nil
end

-- Green at 100, yellow at 50, red at 0.
local function Colour(pct)
    pct = math.max(0, math.min(100, pct or 100))
    if pct >= 50 then
        return (100 - pct) / 50, 1, 0
    end
    return 1, pct / 50, 0
end

local function Hex(pct)
    local r, g, b = Colour(pct)
    return ("%02x%02x%02x"):format(math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function Coins(copper)
    if not copper or copper <= 0 then return nil end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg"):format(math.floor(copper / 10000))
end

-- ── Reading the gear ────────────────────────────────────────────────────────

local state = {
    items = {},        -- { slot, name, pct, link, texture, cost }, worst first
    lowest = nil, lowestName = nil,
    average = nil,
    cost = 0,
    bags = 0,          -- worn items in bags
    bagCost = 0,
    read = false,      -- at least one good read
}

local function RepairCost(getter, ...)
    if not (C_TooltipInfo and getter) then return 0 end
    local ok, data = pcall(getter, ...)
    if not ok or type(data) ~= "table" or Plain(data) == nil then return 0 end
    return Num(data.repairCost) or 0
end

local function ReadGear()
    if not GetInventoryItemDurability then return end
    local items, total, totalMax, cost = {}, 0, 0, 0
    local lowest, lowestName
    for _, entry in ipairs(SLOTS) do
        local slot, name = entry[1], entry[2]
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        -- A failed or secret read keeps the last good figures. Checked
        -- before anything compares them: comparing a secret is the error.
        if not ok then return end
        if issecretvalue and (issecretvalue(cur) or issecretvalue(max)) then return end
        if type(cur) == "number" and type(max) == "number" and max > 0 then
            local pct = cur / max * 100
            total, totalMax = total + cur, totalMax + max
            local itemCost = RepairCost(C_TooltipInfo and C_TooltipInfo.GetInventoryItem, "player", slot)
            cost = cost + itemCost
            items[#items + 1] = {
                slot = slot, name = name, pct = pct, cost = itemCost,
                link = GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil,
                texture = GetInventoryItemTexture and GetInventoryItemTexture("player", slot) or nil,
            }
            if not lowest or pct < lowest then lowest, lowestName = pct, name end
        end
    end
    table.sort(items, function(a, b) return a.pct < b.pct end)
    state.items = items
    state.lowest, state.lowestName = lowest, lowestName
    state.average = totalMax > 0 and (total / totalMax * 100) or nil
    state.cost = cost

    state.bags, state.bagCost = 0, 0
    if settings.bagItems and C_Container and C_Container.GetContainerItemDurability then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            local okSlots, slots = pcall(C_Container.GetContainerNumSlots, bag)
            for slot = 1, (okSlots and Num(slots) or 0) do
                local okD, cur, max = pcall(C_Container.GetContainerItemDurability, bag, slot)
                cur, max = okD and Num(cur), okD and Num(max)
                if cur and max and max > 0 and cur < max then
                    state.bags = state.bags + 1
                    state.bagCost = state.bagCost + RepairCost(C_TooltipInfo and C_TooltipInfo.GetBagItem, bag, slot)
                end
            end
        end
    end
    state.read = true
end

local function Shown()
    if not state.read then return nil end
    if settings.showValue == "average" then return state.average end
    return state.lowest
end

-- ── The readout ─────────────────────────────────────────────────────────────

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Durability")
    if not state.read or #state.items == 0 then
        GameTooltip:AddLine("Nothing equipped wears out.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddDoubleLine("Lowest", ("|cff%s%d%%|r  %s"):format(Hex(state.lowest), state.lowest, state.lowestName or ""), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Average", ("|cff%s%d%%|r"):format(Hex(state.average), state.average or 0), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine(" ")
    for _, item in ipairs(state.items) do
        local icon = item.texture and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(item.texture) or ""
        local left = icon .. (item.link or item.name)
        local right = item.pct <= 0 and "|cffff2020Broken|r" or ("|cff%s%d%%|r"):format(Hex(item.pct), item.pct)
        GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
    end
    local cost = Coins(state.cost)
    if cost or state.bags > 0 then GameTooltip:AddLine(" ") end
    if cost then GameTooltip:AddDoubleLine("Repair (equipped)", cost, 1, 0.82, 0, 1, 1, 1) end
    if settings.bagItems and state.bags > 0 then
        GameTooltip:AddDoubleLine(("Worn in bags (%d)"):format(state.bags), Coins(state.bagCost) or "", 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(settings.locked and "Right-click for options." or "Drag to move. Right-click for options.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local moving = false   -- shown to be dragged, whatever the durability

local function BuildDisplay()
    if display then return display end
    local d = CreateFrame("Frame", "OxedHubDurability", UIParent)
    d:SetSize(90, 26)
    d:SetClampedToScreen(true)
    d:SetMovable(true)
    d:SetFrameStrata("MEDIUM")
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", function(self)
        if not settings.locked or moving then self:StartMoving() end
    end)
    d:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if point then settings.point, settings.x, settings.y = point, x, y end
    end)
    d:SetScript("OnEnter", ShowTooltip)
    d:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Only a real right-click, out of combat: letting go of a right-drag
    -- camera turn over the readout must not open a window mid-fight.
    d:SetScript("OnMouseDown", function(self, button)
        self.rightDown = button == "RightButton" and GetCursorPosition() or nil
    end)
    d:SetScript("OnMouseUp", function(self, button)
        local down = self.rightDown
        self.rightDown = nil
        if button ~= "RightButton" or not down or InCombatLockdown() then return end
        if IsMouselooking and IsMouselooking() then return end
        if math.abs(GetCursorPosition() - down) > 4 then return end
        local API = OxedHub.ModuleAPI
        local mod = API and API.GetModule and API:GetModule("durability")
        if mod and mod.OnOptionsShow then mod.OnOptionsShow(mod) end
    end)

    d.bg = d:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()

    d.icon = d:CreateTexture(nil, "ARTWORK")
    d.icon:SetTexture(REPAIR_ICON)
    d.icon:SetPoint("LEFT", d, "LEFT", 4, 0)

    d.text = d:CreateFontString(nil, "OVERLAY")
    d.text:SetPoint("LEFT", d.icon, "RIGHT", 4, 0)
    d.text:SetShadowOffset(1, -1)

    -- The warning pulse lives on a child texture: an Alpha animation on the
    -- frame itself would fight anything else that sets the frame's alpha.
    d.glow = d:CreateTexture(nil, "BORDER")
    d.glow:SetPoint("TOPLEFT", d, "TOPLEFT", -4, 4)
    d.glow:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 4, -4)
    d.glow:SetColorTexture(1, 0.1, 0.1, 0.35)
    d.glow:Hide()
    local pulse = d.glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.15)
    fade:SetToAlpha(1)
    fade:SetDuration(0.7)
    d.pulse = pulse

    d:ClearAllPoints()
    d:SetPoint(settings.point or "TOP", UIParent, settings.point or "TOP", settings.x or 260, settings.y or -16)
    d:Hide()
    display = d
    return d
end

local warnedLow = false

local function Paint()
    if not (Active("showDisplay") or moving) then
        if display then display:Hide() end
        return
    end
    local value = Shown()
    local low = value and value < (tonumber(settings.remindBelow) or 50)
    if not moving and not settings.displayAlways and not low then
        if display then display:Hide() end
        return
    end
    local d = BuildDisplay()
    d:SetScale(tonumber(settings.scale) or 1)
    local size = math.max(10, math.min(36, tonumber(settings.fontSize) or 16))
    d.text:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
    d.icon:SetSize(size + 4, size + 4)
    d.bg:SetColorTexture(0, 0, 0, tonumber(settings.bgAlpha) or 0)

    if value then
        local broken = state.lowest and state.lowest <= 0 and settings.showValue ~= "average"
        d.text:SetText(broken and "Broken" or ("%d%%"):format(math.floor(value + 0.5)))
        d.text:SetTextColor(Colour(value))
    else
        d.text:SetText(moving and "100%" or "--")
        d.text:SetTextColor(0.7, 0.7, 0.7)
    end

    local warn = state.lowest and state.lowest < (tonumber(settings.warnBelow) or 30)
    if warn then
        d.glow:Show()
        if not d.pulse:IsPlaying() then d.pulse:Play() end
        if not warnedLow then
            warnedLow = true
            local API = OxedHub.ModuleAPI
            if settings.warnSound ~= "" and API and API.PlaySound then API:PlaySound(settings.warnSound) end
        end
    else
        d.pulse:Stop()
        d.glow:Hide()
        warnedLow = false
    end
    d:SetWidth(d.icon:GetWidth() + d.text:GetStringWidth() + 14)
    d:SetHeight(math.max(22, size + 10))
    d:Show()
end

-- ── Chat reminders ──────────────────────────────────────────────────────────

local lastReminder = 0

local function Report(force)
    if not state.read then return end
    local lowest = state.lowest
    if not lowest then
        if force then print(PREFIX .. "nothing you wear can lose durability.") end
        return
    end
    if not force and lowest >= (tonumber(settings.remindBelow) or 50) then return end
    local now = GetTime()
    if not force and now - lastReminder < 60 then return end
    lastReminder = now

    local cost = Coins(state.cost)
    print(PREFIX .. ("durability: lowest |cff%s%d%%|r (%s), average |cff%s%d%%|r%s.")
        :format(Hex(lowest), lowest, state.lowestName or "?", Hex(state.average), state.average or 0,
            cost and (", repair " .. cost) or ""))
    for _, item in ipairs(state.items) do
        if item.pct <= 0 then
            print("   " .. (item.link or item.name) .. " |cffff2020is broken.|r")
        elseif force and item.pct < 50 then
            print(("   %s |cff%s%d%%|r"):format(item.link or item.name, Hex(item.pct), item.pct))
        end
    end
    local API = OxedHub.ModuleAPI
    if not force and settings.remindSound ~= "" and API and API.PlaySound then API:PlaySound(settings.remindSound) end
end

local REMIND_INSTANCES = { party = true, raid = true, arena = true, scenario = true }

local function Refresh()
    -- Reads in combat may be secret, and nothing here is urgent mid-fight:
    -- the readout catches up when the fight ends.
    if InCombatLockdown() then return end
    ReadGear()
    Paint()
end

local wasResting = nil
local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.5, function()
        refreshQueued = false
        Refresh()
    end)
end

watcher:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_INVENTORY_DURABILITY" or event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "PLAYER_REGEN_ENABLED" or event == "MERCHANT_CLOSED" or event == "BAG_UPDATE_DELAYED" then
        QueueRefresh()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(2, function()
            Refresh()
            if settings.remindInstance and IsInInstance then
                local _, kind = IsInInstance()
                if REMIND_INSTANCES[kind] then Report(false) end
            end
            wasResting = IsResting and IsResting() or false
        end)
    elseif event == "PLAYER_UNGHOST" or event == "PLAYER_ALIVE" then
        -- PLAYER_ALIVE also fires on releasing to a ghost; only a living
        -- player has come back.
        C_Timer.After(1, function()
            if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
            Refresh()
            if settings.remindRes then Report(false) end
        end)
    elseif event == "PLAYER_UPDATE_RESTING" then
        local resting = IsResting and IsResting() or false
        if resting and wasResting == false and settings.remindCity then
            Refresh()
            Report(false)
        end
        wasResting = resting
    end
end)

local EVENTS = {
    "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_REGEN_ENABLED",
    "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_UNGHOST", "PLAYER_ALIVE", "PLAYER_UPDATE_RESTING",
}

local function Start()
    for _, event in ipairs(EVENTS) do watcher:RegisterEvent(event) end
    wasResting = IsResting and IsResting() or false
    Refresh()
end

local function Stop()
    watcher:UnregisterAllEvents()
    moving = false
    if display then
        display.pulse:Stop()
        display:Hide()
    end
end

local function ToggleMove()
    moving = not moving
    ReadGear()
    Paint()
    return moving
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local o = API:CreateOptionsWindow("Durability", 470, 690)
        local function Repaint() if Active() then Refresh() end end
        o:AddCheckbox(settings, "showDisplay", "Durability readout on screen", nil, Repaint)
        o:AddCheckbox(settings, "displayAlways", "Show it all the time",
            "Off: only while durability is below the reminder line.", Repaint)
        o:AddChoice(settings, "showValue", "It shows", {
            { value = "lowest", text = "Lowest item" },
            { value = "average", text = "Average" },
        }, Repaint)
        o:AddCheckbox(settings, "locked", "Lock the readout", "Unlocked, drag it. Right-click it for these options.")
        o:AddSlider(settings, "fontSize", "Text size", 10, 36, 1, "%s: %d", Repaint)
        o:AddSlider(settings, "scale", "Scale", 0.6, 1.8, 0.05, "%s: %.2f", Repaint)
        o:AddSlider(settings, "bgAlpha", "Background opacity", 0, 1, 0.05, "%s: %.2f", Repaint)
        o:AddSlider(settings, "warnBelow", "Warning below", 5, 80, 5, "%s %d%%", Repaint)
        o:AddSoundPicker(settings, "warnSound", "Warning sound", "None")
        o:AddSlider(settings, "remindBelow", "Remind me below", 10, 95, 5, "%s %d%%", Repaint)
        o:AddCheckbox(settings, "remindInstance", "Remind on entering a dungeon, raid, arena or delve")
        o:AddCheckbox(settings, "remindRes", "Remind on coming back from death")
        o:AddCheckbox(settings, "remindCity", "Remind on arriving in a city or inn")
        o:AddSoundPicker(settings, "remindSound", "Reminder sound", "None")
        o:AddCheckbox(settings, "bagItems", "Worn items in bags, in the tooltip", nil, Repaint)

        local row = CreateFrame("Frame", nil, o)
        row:SetSize(420, 24)
        row:SetPoint("TOPLEFT", o, "TOPLEFT", 20, o.cursorY - 2)
        local move = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        move:SetSize(130, 22)
        move:SetPoint("LEFT", row, "LEFT", 0, 0)
        move:SetText("Move Readout")
        move:SetScript("OnClick", function(self)
            self:SetText(ToggleMove() and "Done Moving" or "Move Readout")
        end)
        move:SetScript("OnHide", function(self)
            if moving then ToggleMove() end
            self:SetText("Move Readout")
        end)
        local check = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        check:SetSize(130, 22)
        check:SetPoint("LEFT", move, "RIGHT", 8, 0)
        check:SetText("Check Now")
        check:SetScript("OnClick", function() ReadGear() Report(true) end)
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(move)
            OxedHub.UI:ApplyRedButtonStyle(check)
        end
        o.cursorY = o.cursorY - 32

        o:AddModuleLinks("Repairing at vendors:", { "autovendor" })
        o:AddNote("/dura prints your durability, /dura move shows the readout to drag.")
        optionsWindow = o
    end
    optionsWindow:Show()
end

-- ── Slash command ───────────────────────────────────────────────────────────

SLASH_OXEDDURABILITY1 = "/dura"
SLASH_OXEDDURABILITY2 = "/durability"
SlashCmdList["OXEDDURABILITY"] = function(message)
    if not settings then return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "move" then
        print(PREFIX .. "durability readout " .. (ToggleMove() and "shown: drag it, /dura move again when done." or "back to normal."))
    elseif message == "options" then
        ShowOptions()
    else
        ReadGear()
        Report(true)
        if not Active() then print(PREFIX .. "the Durability module is off: switch it on in Modules for the readout and reminders.") end
    end
end

-- ── Settings and registration ───────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.durability
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.durability = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
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
        id       = "durability",
        name     = "Durability",
        version  = "1.0.0",
        updated  = 20261021.4,
        author   = "Oxed",
        category = "items",
        keywords = { "durability", "repair", "broken", "armor", "gear", "damage", "cost" },
        desc     = "Gear durability on screen, worst slots and repair cost, and reminders before a dungeon.",
        icon     = "Interface\\Icons\\Trade_BlackSmithing",

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
