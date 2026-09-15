-- ============================================================================
-- Missing Gems (built-in OxedHub module)
-- Marks every piece of equipped gear that has an empty gem socket, right on its
-- slot in the character window, and reminds you before it costs you a run:
-- when you enter a dungeon or raid, and on a ready check.
--
-- An empty socket is easy to miss. A new drop arrives with sockets and nothing
-- in them, and nothing in the default interface says so unless you hover the
-- item. This says so in the two places it matters -- where you look at your
-- gear, and right before you pull.
--
-- Missing enchants can be flagged the same way. That part is off by default,
-- because which slots take an enchant changes between expansions: the list is
-- ENCHANT_SLOTS below, and it is the one thing to check after a new one.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on (see ModuleAPI:Register)
    showSlots     = true,   -- icon on each slot in the character window
    remindEnter   = true,   -- chat reminder entering a dungeon or raid
    remindReady   = true,   -- chat reminder on a ready check
    enchants      = false,  -- also flag missing enchants
}

local settings          -- OxedHubDB.modules.missinggems, bound at login
local optionsWindow
local overlays = {}     -- slot id -> overlay frame on the character window

local PREFIX = "|cff00ff00OxedHub:|r "
local SOCKET_ICON = "Interface\\ItemSocketingFrame\\UI-EmptySocket-Prismatic"
local ENCHANT_ICON = "Interface\\Icons\\Trade_Engraving"

-- The character window's slot buttons, in the order the reminder lists them.
local SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist",
    "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1",
    "MainHand", "SecondaryHand",
}

local SLOT_LABELS = {
    Head = "Head", Neck = "Neck", Shoulder = "Shoulders", Back = "Back",
    Chest = "Chest", Wrist = "Wrists", Hands = "Hands", Waist = "Waist",
    Legs = "Legs", Feet = "Feet", Finger0 = "Ring 1", Finger1 = "Ring 2",
    Trinket0 = "Trinket 1", Trinket1 = "Trinket 2",
    MainHand = "Main hand", SecondaryHand = "Off hand",
}

-- ⚠ Which slots take an enchant is decided per expansion, and this is the list
-- to update when that changes. A slot left here that can no longer be enchanted
-- would be flagged forever with nothing the player can do about it.
local ENCHANT_SLOTS = {
    Head = true, Shoulder = true, Chest = true, Legs = true, Feet = true,
    Finger0 = true, Finger1 = true, MainHand = true,
}

-- ── Reading one item ────────────────────────────────────────────────────────

-- The fields of an item link, empty ones kept: "item:id:enchant:gem1:gem2..."
-- An empty field is a real position -- a socket with nothing in it -- so the
-- split must not collapse it the way a plain "[^:]+" match would.
local function LinkFields(link)
    local itemString = type(link) == "string" and link:match("item:([^|]+)")
    if not itemString then return nil end
    local fields = {}
    for value in (itemString .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = value
    end
    return fields
end

-- How many sockets the item has in total. Read from its stats, which count the
-- sockets the item was made with and any added to it since. Returns nil while
-- the client has not loaded the item yet, which is not the same as zero.
local function SocketCount(link)
    local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not getStats then return nil end
    local ok, stats = pcall(getStats, link)
    if not ok or type(stats) ~= "table" then return nil end
    local sockets = 0
    for key, value in pairs(stats) do
        if type(key) == "string" and key:find("^EMPTY_SOCKET_") then
            sockets = sockets + (tonumber(value) or 0)
        end
    end
    return sockets
end

-- Returns empty sockets, and whether the enchant is missing, for one slot.
local function InspectSlot(slotName, slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return 0, false end

    local fields = LinkFields(link)
    if not fields then return 0, false end

    local empty = 0
    local sockets = SocketCount(link)
    if sockets and sockets > 0 then
        local filled = 0
        -- Gem ids sit in fields 3 to 6, one per socket.
        for index = 3, 6 do
            if fields[index] and fields[index] ~= "" and fields[index] ~= "0" then
                filled = filled + 1
            end
        end
        empty = math.max(0, sockets - filled)
    end

    local noEnchant = false
    if settings.enchants and ENCHANT_SLOTS[slotName] then
        noEnchant = not fields[2] or fields[2] == "" or fields[2] == "0"
        -- An off-hand that is not a weapon (a shield, a held item) cannot take
        -- a weapon enchant, and a two-hander leaves the off-hand slot empty.
        if slotName == "SecondaryHand" then noEnchant = false end
    end

    return empty, noEnchant
end

-- Everything that is missing right now, in slot order.
local function Survey()
    local gaps = {}
    local totalSockets, totalEnchants = 0, 0
    for _, slotName in ipairs(SLOTS) do
        local slotID = GetInventorySlotInfo(slotName .. "Slot")
        if slotID then
            local empty, noEnchant = InspectSlot(slotName, slotID)
            if empty > 0 or noEnchant then
                gaps[#gaps + 1] = { slot = slotName, id = slotID, empty = empty, noEnchant = noEnchant }
                totalSockets = totalSockets + empty
                if noEnchant then totalEnchants = totalEnchants + 1 end
            end
        end
    end
    return gaps, totalSockets, totalEnchants
end

-- ── Marks on the character window ───────────────────────────────────────────

local function GetOverlay(slotName, slotID)
    if overlays[slotID] then return overlays[slotID] end
    local button = _G["Character" .. slotName .. "Slot"]
    if not button then return nil end

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(button:GetFrameLevel() + 5)

    overlay.socket = overlay:CreateTexture(nil, "OVERLAY")
    overlay.socket:SetSize(16, 16)
    overlay.socket:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", 2, 2)
    overlay.socket:SetTexture(SOCKET_ICON)

    overlay.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    overlay.count:SetPoint("CENTER", overlay.socket, "CENTER", 0, 0)
    overlay.count:SetTextColor(1, 0.3, 0.3)

    overlay.enchant = overlay:CreateTexture(nil, "OVERLAY")
    overlay.enchant:SetSize(14, 14)
    overlay.enchant:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 2, -2)
    overlay.enchant:SetTexture(ENCHANT_ICON)
    overlay.enchant:SetVertexColor(1, 0.4, 0.4)

    overlays[slotID] = overlay
    return overlay
end

local function RefreshSlots()
    for _, overlay in pairs(overlays) do overlay:Hide() end
    if not settings or settings.enabled == false or not settings.showSlots then return end
    if not (CharacterFrame and CharacterFrame:IsShown()) then return end

    local gaps = Survey()
    for _, gap in ipairs(gaps) do
        local overlay = GetOverlay(gap.slot, gap.id)
        if overlay then
            overlay.socket:SetShown(gap.empty > 0)
            overlay.count:SetText(gap.empty > 1 and tostring(gap.empty) or "")
            overlay.enchant:SetShown(gap.noEnchant)
            overlay:Show()
        end
    end
end

-- ── Reminders ───────────────────────────────────────────────────────────────

local function Remind(context)
    local gaps, sockets, enchants = Survey()
    if #gaps == 0 then return end

    local names = {}
    for _, gap in ipairs(gaps) do
        local label = SLOT_LABELS[gap.slot] or gap.slot
        local what = {}
        if gap.empty > 0 then
            what[#what + 1] = gap.empty > 1 and (gap.empty .. " sockets") or "socket"
        end
        if gap.noEnchant then what[#what + 1] = "enchant" end
        names[#names + 1] = ("%s (%s)"):format(label, table.concat(what, ", "))
    end

    local summary = {}
    if sockets > 0 then summary[#summary + 1] = ("%d empty socket(s)"):format(sockets) end
    if enchants > 0 then summary[#summary + 1] = ("%d missing enchant(s)"):format(enchants) end

    print(PREFIX .. ("|cffff5555%s|r%s: %s"):format(
        table.concat(summary, " and "), context and (" " .. context) or "", table.concat(names, ", ")))
end

-- Only once per instance visit: a loading screen inside the same dungeon, or a
-- wipe and a run back, is not a reason to say it again.
local lastInstance

local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, event)
    if not settings or settings.enabled == false then return end

    if event == "PLAYER_ENTERING_WORLD" then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid") then
            local instanceID = select(8, GetInstanceInfo())
            if settings.remindEnter and instanceID ~= lastInstance then
                lastInstance = instanceID
                -- Gear links are not all loaded the moment the world appears;
                -- a short wait reads them whole instead of as unknown.
                C_Timer.After(3, function() Remind("before this run") end)
            end
        else
            lastInstance = nil
        end
        RefreshSlots()
    elseif event == "READY_CHECK" then
        if settings.remindReady then Remind("on ready check") end
    else
        RefreshSlots()
    end
end)

local EVENTS = {
    "PLAYER_ENTERING_WORLD", "READY_CHECK", "PLAYER_EQUIPMENT_CHANGED",
    "SOCKET_INFO_UPDATE", "GET_ITEM_INFO_RECEIVED",
}

local function SetEvents(on)
    for _, event in ipairs(EVENTS) do
        if on then watcher:RegisterEvent(event) else watcher:UnregisterEvent(event) end
    end
end

local hooked = false
local function HookCharacterFrame()
    if hooked or not CharacterFrame then return end
    hooked = true
    CharacterFrame:HookScript("OnShow", RefreshSlots)
end

-- The character window can be loaded on demand, after login, so the hook waits
-- for it rather than assuming it is there.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self)
    if CharacterFrame then
        HookCharacterFrame()
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
    end
end)

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.missinggems
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.missinggems = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Missing Gems", 420, 270)
        optionsWindow:AddCheckbox(settings, "showSlots", "Mark slots in the character window",
            "A socket icon on every piece of gear with an empty socket, with the count when there is more than one.",
            RefreshSlots)
        optionsWindow:AddCheckbox(settings, "remindEnter", "Remind me entering a dungeon or raid",
            "One line in chat when you arrive, listing what is missing.")
        optionsWindow:AddCheckbox(settings, "remindReady", "Remind me on a ready check")
        optionsWindow:AddCheckbox(settings, "enchants", "Also flag missing enchants",
            "Marks enchantable slots with no enchant. Which slots count is set for the current expansion.",
            RefreshSlots)
        optionsWindow:AddNote("Type /oxgems to check your gear at any time.")
    end
    optionsWindow:Show()
end

SLASH_OXEDGEMS1 = "/oxgems"
SlashCmdList["OXEDGEMS"] = function()
    if not settings then return end
    local gaps = Survey()
    if #gaps == 0 then
        print(PREFIX .. "every socket is filled" .. (settings.enchants and " and every enchant is on." or "."))
    else
        Remind()
    end
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()
    HookCharacterFrame()

    if not OxedHub.ModuleAPI then
        if settings.enabled ~= false then SetEvents(true) end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "missinggems",
        name     = "Missing Gems",
        version  = "1.0.0",
        author   = "Oxed",
        category = "character",
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Marks gear with empty gem sockets and reminds you before a dungeon or raid.",
        icon     = "Interface\\Icons\\INV_Misc_Gem_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            HookCharacterFrame()
            SetEvents(true)
            RefreshSlots()
        end,

        OnDisable = function()
            SetEvents(false)
            for _, overlay in pairs(overlays) do overlay:Hide() end
        end,
    })
end)
