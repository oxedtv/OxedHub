-- ============================================================================
-- Smart Misdirect (built-in OxedHub module)
-- Automatic tank / focus targeting for Hunter (Misdirection) and Rogue (Tricks of the Trade)
-- with a 1-click secure macro and dynamic group re-targeting.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

-- ── Default Settings ────────────────────────────────────────────────────────
local DEFAULTS = {
    enabled         = true,
    announceTarget  = false,
    prioritizeFocus = true,
    includePet      = true,    -- Fallback to Hunter pet when solo or no tank
    tankMethod      = "byRole", -- "byRole", "roleAndMainTank", "mainTankFirst", "mainTankOnly"
    manualName      = "",
    manualRealm     = "",
}

local MISDIRECTION_ID        = 34477  -- Hunter
local TRICKS_OF_THE_TRADE_ID = 57934  -- Rogue

local settings
local optionsWindow
local secureButtons = {}
local updateQueued = false
local currentTarget = nil
local wasMounted = false
local eventWatcher = nil

-- Export namespace
OxedHub.SmartMisdirect = OxedHub.SmartMisdirect or {}
local SM = OxedHub.SmartMisdirect


-- ── Helpers ─────────────────────────────────────────────────────────────────

local function GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

local function IsEligibleClass()
    local cls = GetPlayerClass()
    return cls == "HUNTER" or cls == "ROGUE"
end

local function IsHunter()
    return GetPlayerClass() == "HUNTER"
end

local function GetActiveSpellID()
    return IsHunter() and MISDIRECTION_ID or TRICKS_OF_THE_TRADE_ID
end

local function GetActiveSpellName()
    local id = GetActiveSpellID()
    return C_Spell.GetSpellName(id) or (IsHunter() and "Misdirection" or "Tricks of the Trade")
end

local function FullName(name, realm)
    if not name then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function IterGroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    else
        units[#units + 1] = "player"
        for i = 1, (GetNumGroupMembers() or 0) - 1 do
            local u = "party" .. i
            if UnitExists(u) then units[#units + 1] = u end
        end
    end
    return units
end

-- ── Secure Action Buttons ───────────────────────────────────────────────────

local function CreateSecureButtons()
    if not IsEligibleClass() then return end
    if #secureButtons > 0 then return end
    if InCombatLockdown() then
        updateQueued = true
        return
    end

    local spellID = GetActiveSpellID()
    for i = 1, 2 do
        local name = "OxedHub_SmartMisdirectButton" .. i
        local btn = _G[name] or CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        btn:Hide()
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("typerelease", "spell")
        btn:SetAttribute("spell", spellID)
        btn:SetAttribute("pressAndHoldAction", "1")
        btn:SetAttribute("allowVehicleTarget", false)
        btn:SetAttribute("checkselfcast", false)
        btn:SetAttribute("checkfocuscast", false)
        btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        secureButtons[i] = btn
    end
end

-- ── Target Resolution ───────────────────────────────────────────────────────

local function GetTanks()
    local method = (settings and settings.tankMethod) or "byRole"
    local result = {}
    local seen   = {}

    local function addIf(unit, wantRole, wantMain)
        local name, realm = UnitName(unit)
        if not name then return end
        local full = FullName(name, realm)
        if seen[full] then return end
        local isTankRole = UnitGroupRolesAssigned(unit) == "TANK"
        local isMainTank = GetPartyAssignment and GetPartyAssignment("MAINTANK", unit, true)
        if (wantRole and isTankRole) or (wantMain and isMainTank) then
            seen[full] = true
            result[#result + 1] = full
        end
    end

    local units = IterGroupUnits()

    if method == "mainTankFirst" then
        local mains, tanks = {}, {}
        local seenM, seenT = {}, {}
        for _, u in ipairs(units) do
            local name, realm = UnitName(u)
            if name then
                local full = FullName(name, realm)
                if GetPartyAssignment and GetPartyAssignment("MAINTANK", u, true) and not seenM[full] then
                    seenM[full] = true
                    mains[#mains + 1] = full
                elseif UnitGroupRolesAssigned(u) == "TANK" and not seenT[full] then
                    seenT[full] = true
                    tanks[#tanks + 1] = full
                end
            end
        end
        table.sort(mains)
        table.sort(tanks)
        for _, v in ipairs(mains) do result[#result + 1] = v end
        for _, v in ipairs(tanks) do result[#result + 1] = v end
        return result
    end

    if method == "mainTankOnly" then
        for _, u in ipairs(units) do addIf(u, false, true) end
    elseif method == "roleAndMainTank" then
        for _, u in ipairs(units) do addIf(u, true, true) end
    else
        -- default: byRole
        for _, u in ipairs(units) do addIf(u, true, false) end
    end

    table.sort(result)
    return result
end

local function GetTargets()
    if not IsEligibleClass() then return {} end
    if not (settings and settings.enabled) then return {} end

    local out, seen = {}, {}
    local function push(x)
        if x and not seen[x] then
            seen[x] = true
            out[#out + 1] = x
        end
    end

    -- 0. Manual override
    local manualName  = settings.manualName or ""
    local manualRealm = settings.manualRealm or ""
    if manualName ~= "" then
        local wantName  = manualName:lower()
        local wantRealm = manualRealm:lower()
        for _, u in ipairs(IterGroupUnits()) do
            local name, realm = UnitName(u)
            if name and name:lower() == wantName then
                if wantRealm ~= "" then
                    if realm and realm:lower() == wantRealm then
                        push(name .. "-" .. realm)
                        break
                    end
                else
                    push(FullName(name, realm))
                    break
                end
            end
        end
    end

    -- 1. Focus target
    if settings.prioritizeFocus then
        if UnitExists("focus") and (UnitInParty("focus") or UnitInRaid("focus")) and UnitIsFriend("player", "focus") then
            local fn, fr = UnitName("focus")
            push(FullName(fn, fr))
        end
    end

    -- 2. Tanks
    for _, tank in ipairs(GetTanks()) do
        push(tank)
    end

    -- 3. Pet fallback (Hunters only)
    if IsHunter() and settings.includePet and #out == 0 then
        if UnitExists("pet") then
            push("pet")
        end
    end

    return out
end

-- ── Button Updating ─────────────────────────────────────────────────────────

local function ProcessQueuedUpdate()
    if not IsEligibleClass() then return end
    if not updateQueued then return end
    if InCombatLockdown() then return end
    updateQueued = false

    if #secureButtons == 0 and settings and settings.enabled then
        CreateSecureButtons()
    end

    local targets = (settings and settings.enabled) and GetTargets() or {}
    local primary = targets[1]

    local mounted = IsMounted()
    local _, insType = IsInInstance()
    local suppress = mounted or wasMounted or insType == "pvp" or insType == "arena"

    if settings and settings.announceTarget then
        if primary and primary ~= currentTarget then
            currentTarget = primary
            if not suppress then
                print(string.format(L["|cff0091edSmartMD:|r Target set to |cFFFFD700%s|r"], primary))
            end
        elseif not primary and currentTarget then
            currentTarget = nil
            if not suppress then
                print(L["|cff0091edSmartMD:|r |cffff5555No valid target found|r"])
            end
        end
    else
        currentTarget = primary
    end
    wasMounted = mounted

    for i, btn in ipairs(secureButtons) do
        local t = targets[i]
        if t then
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("unit", t)
        else
            btn:SetAttribute("type", nil)
            btn:SetAttribute("unit", nil)
        end
    end
end

local function QueueUpdate()
    if not IsEligibleClass() then return end
    updateQueued = true
    ProcessQueuedUpdate()
end

local function ClearButtons()
    if InCombatLockdown() then
        updateQueued = true
        return
    end
    for _, btn in ipairs(secureButtons) do
        btn:SetAttribute("type", nil)
        btn:SetAttribute("unit", nil)
    end
    currentTarget = nil
end

-- ── Macro Generation ────────────────────────────────────────────────────────

local function CreateOrUpdateMacro()
    if not IsEligibleClass() then
        print(L["|cff0091edSmartMD:|r Smart Misdirect macro is only available for Hunters and Rogues."])
        return nil
    end
    if InCombatLockdown() then
        print(L["|cff0091edSmartMD:|r Cannot create or update macros while in combat."])
        return nil
    end

    CreateSecureButtons()
    QueueUpdate()

    local hunter = IsHunter()
    local macroName = hunter and "SmartMD" or "SmartTotT"
    local icon      = hunter and 132180 or 236283  -- Misdirection / Tricks icon
    local body      = "#showtooltip\n/click OxedHub_SmartMisdirectButton1\n/click OxedHub_SmartMisdirectButton2"

    local existing = GetMacroIndexByName(macroName)
    if not existing or existing <= 0 then
        existing = GetMacroIndexByName("KickSync_MD")
    end

    if existing and existing > 0 then
        EditMacro(existing, macroName, icon, body)
        print(string.format(L["|cff0091edSmartMD:|r Updated macro '|cffffd100%s|r'. Drag it onto your action bar!"], macroName))
        return existing
    end

    local numGlobal, numChar = GetNumMacros()
    local idx
    if numChar < 18 then
        idx = CreateMacro(macroName, icon, body, 1)  -- character-specific tab
    elseif numGlobal < 120 then
        idx = CreateMacro(macroName, icon, body, false) -- general tab
    end

    if idx then
        print(string.format(L["|cff0091edSmartMD:|r Created macro '|cffffd100%s|r' (per-character). Drag it onto your action bar!"], macroName))
    else
        print(L["|cff0091edSmartMD:|r |cffff4040Macro slots are full.|r Please delete an unused macro and retry."])
    end
    return idx
end

-- Export API
function SM:UpdateMacro() QueueUpdate() end
function SM:CreateMacro() return CreateOrUpdateMacro() end
function SM:GetTargets() return GetTargets() end
function SM:GetCurrentTargetName() return currentTarget or (GetTargets()[1]) end

-- ── Event Lifecycle ─────────────────────────────────────────────────────────

local function SetupEvents()
    if eventWatcher then return end
    eventWatcher = CreateFrame("Frame")
    eventWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventWatcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
    eventWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventWatcher:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    eventWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    eventWatcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            if not InCombatLockdown() then
                local spellID = GetActiveSpellID()
                for _, btn in ipairs(secureButtons) do
                    btn:SetAttribute("spell", spellID)
                end
            end
        end
        QueueUpdate()
    end)
end

local function StartModule()
    if not IsEligibleClass() then return end
    CreateSecureButtons()
    SetupEvents()
    C_Timer.After(1, function() QueueUpdate() end)
end

local function StopModule()
    ClearButtons()
    if eventWatcher then
        eventWatcher:UnregisterAllEvents()
        eventWatcher = nil
    end
end

-- ── Options Window ──────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Smart Misdirect", 460, 480)
        local w = optionsWindow

        local cls = GetPlayerClass()
        local isEligible = (cls == "HUNTER" or cls == "ROGUE")

        if not isEligible then
            w:AddNote("|cffff4040Note: Smart Misdirect is designed specifically for Hunters (Misdirection) and Rogues (Tricks of the Trade). On this character, the settings can be previewed.|r")
        else
            w:AddNote("Automatically retargets Misdirection & Tricks of the Trade to your party/raid tank or focus with a 1-click secure macro.")
        end

        -- Red Action Buttons
        local btnMacro = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        btnMacro:SetSize(200, 24)
        btnMacro:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        btnMacro:SetText(L["Create / Update Macro"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnMacro) end
        btnMacro:SetScript("OnClick", function()
            CreateOrUpdateMacro()
        end)

        local btnPrint = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        btnPrint:SetSize(200, 24)
        btnPrint:SetPoint("LEFT", btnMacro, "RIGHT", 10, 0)
        btnPrint:SetText(L["Print Current Target"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnPrint) end
        btnPrint:SetScript("OnClick", function()
            local ts = GetTargets()
            print(string.format(L["|cff0091edSmartMD:|r Current targets (%d):"], #ts))
            for i, t in ipairs(ts) do
                print(string.format("  %d. |cffffd100%s|r", i, t))
            end
            if #ts == 0 then print(L["  |cffff4040None found in group|r"]) end
        end)

        w.cursorY = w.cursorY - 34

        -- Settings Toggles
        w:AddCheckbox(settings, "enabled", "Enable Smart Misdirect", "Activates secure action buttons and automatic retargeting.", function(val)
            if val then QueueUpdate() else ClearButtons() end
        end)

        w:AddCheckbox(settings, "announceTarget", "Announce target changes in chat", "Prints target updates in chat window when group changes.")

        w:AddCheckbox(settings, "prioritizeFocus", "Prefer Focus target if friendly", "Prioritizes your Focus target if they are friendly and in your group.", function()
            QueueUpdate()
        end)

        if IsHunter() or not isEligible then
            w:AddCheckbox(settings, "includePet", "Fallback to Pet when solo / no tank", "Redirects to your hunter pet when not in a group or when no tank exists.", function()
                QueueUpdate()
            end)
        end

        -- Tank Selection Method Choice
        w:AddChoice(settings, "tankMethod", "Tank selection method", {
            { value = "byRole",          text = L["By Role (TANK)"] },
            { value = "roleAndMainTank", text = L["Role + Main Tank"] },
            { value = "mainTankFirst",   text = L["Main Tank first"] },
            { value = "mainTankOnly",    text = L["Main Tank only"] },
        }, function()
            QueueUpdate()
        end)

        -- Manual Override
        w:AddNote("|cffffd100Manual Override (Player Name)|r")
        local editBox = CreateFrame("EditBox", nil, w, "InputBoxTemplate")
        editBox:SetSize(200, 22)
        editBox:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 2)
        editBox:SetAutoFocus(false)
        editBox:SetText(settings.manualName or "")
        editBox:SetScript("OnTextChanged", function(self, isUser)
            if isUser then
                settings.manualName = self:GetText():trim()
                QueueUpdate()
            end
        end)

        local btnClear = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        btnClear:SetSize(120, 22)
        btnClear:SetPoint("LEFT", editBox, "RIGHT", 10, 0)
        btnClear:SetText(L["Clear Override"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(btnClear) end
        btnClear:SetScript("OnClick", function()
            settings.manualName = ""
            settings.manualRealm = ""
            editBox:SetText("")
            print(L["|cff0091edSmartMD:|r Manual override cleared."])
            QueueUpdate()
        end)

        w.cursorY = w.cursorY - 32

        w:AddNote("Commands: /smartmd or /smd (options) | /smd macro (create macro) | /smd target (check target).")
    end

    optionsWindow:Show()
end

-- ── Slash Commands ──────────────────────────────────────────────────────────

SLASH_OXEDHUBSMARTMISDIRECT1 = "/smartmd"
SLASH_OXEDHUBSMARTMISDIRECT2 = "/smd"
SlashCmdList.OXEDHUBSMARTMISDIRECT = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "macro" then
        CreateOrUpdateMacro()
    elseif msg == "clear" then
        if settings then settings.manualName = ""; settings.manualRealm = "" end
        print(L["|cff0091edSmartMD:|r Manual override cleared."])
        QueueUpdate()
    elseif msg:match("^set%s+(.+)") then
        local name = msg:match("^set%s+(.+)")
        if settings then settings.manualName = name end
        print(string.format(L["|cff0091edSmartMD:|r Manual target set to |cFFFFD700%s|r"], name))
        QueueUpdate()
    elseif msg == "target" or msg == "targets" then
        local ts = GetTargets()
        print(string.format(L["|cff0091edSmartMD:|r Current targets (%d):"], #ts))
        for i, t in ipairs(ts) do
            print(string.format("  %d. |cffffd100%s|r", i, t))
        end
        if #ts == 0 then print(L["  |cffff4040None found in group|r"]) end
    else
        ShowOptions()
    end
end

-- ── Module Registration ─────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.smartmisdirect
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.smartmisdirect = config
    end
    settings = config
    for k, v in pairs(DEFAULTS) do
        if settings[k] == nil then settings[k] = v end
    end

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then StartModule() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "smartmisdirect",
        name     = "Smart Misdirect",
        version  = "1.0.0",
        updated  = 20261013.9,
        author   = "Oxed",
        category = "combat",
        keywords = { "smartmisdirect", "misdirection", "tricks", "tank", "focus", "hunter", "rogue", "md", "threat" },
        desc     = "Smart auto-targeting for Misdirection (Hunter) and Tricks of the Trade (Rogue) with a 1-click secure macro.",
        icon     = "Interface\\Icons\\ability_hunter_misdirection",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, cfg)
            settings = cfg
            StartModule()
        end,

        OnDisable = function()
            StopModule()
        end,
    })
end)
