-- ============================================================================
-- Bonus Roll Guard (built-in OxedHub module)
-- A bonus roll is spent on one click, often by accident and often in the
-- wrong loot specialisation. With this on, the first click on Roll (or Pass)
-- only says which spec the loot goes to; a second click within a few seconds
-- does it.
--
-- How: a button of ours lies over the game's button and takes the first
-- click. After it, ours steps aside for ARM_TIME seconds so the second click
-- lands on the game's own button. Nothing of the game's is replaced or
-- clicked for the player, so no taint and no blocked action.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled   = false,  -- off until the player switches it on
    guardPass = true,   -- also guard Pass
    sound     = true,   -- a click sound on the first press
}

local ARM_TIME = 5      -- seconds the real button stays reachable

local settings
local optionsWindow
local shields = {}      -- [game button] = our cover
local frameHooked = false
local note              -- the line above the bonus roll window

local function LootSpecText()
    local specID = GetLootSpecialization and GetLootSpecialization()
    if specID and specID > 0 then
        local _, name, _, icon = GetSpecializationInfoByID(specID)
        if name then return ("|T%s:16|t %s"):format(tostring(icon), name) end
    end
    local index = GetSpecialization and GetSpecialization()
    if index then
        local _, name, _, icon = GetSpecializationInfo(index)
        if name then return ("|T%s:16|t %s (your current spec)"):format(tostring(icon), name) end
    end
    return "unknown"
end

local function ShowNote(text)
    if not BonusRollFrame then return end
    if not note then
        note = CreateFrame("Frame", nil, BonusRollFrame, "BackdropTemplate")
        note:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        note:SetBackdropColor(0, 0, 0, 0.85)
        note:SetBackdropBorderColor(1, 0.82, 0, 0.9)
        note.text = note:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        note.text:SetPoint("CENTER")
    end
    note:ClearAllPoints()
    note:SetPoint("BOTTOM", BonusRollFrame, "TOP", 0, 4)
    note.text:SetText(text)
    note:SetSize(note.text:GetStringWidth() + 24, 28)
    note:Show()
end

-- Our cover over one of the game's buttons.
local function Shield(button, isRoll)
    if not button or shields[button] then return shields[button] end
    local cover = CreateFrame("Button", nil, button:GetParent())
    cover:SetAllPoints(button)
    cover:SetFrameLevel(button:GetFrameLevel() + 10)
    cover:RegisterForClicks("AnyUp")
    cover:SetScript("OnEnter", function()
        local onEnter = button:GetScript("OnEnter")
        if onEnter then pcall(onEnter, button) end
    end)
    cover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cover:SetScript("OnClick", function(self)
        if isRoll then
            ShowNote(("Loot goes to %s. |cff40ff40Click Roll again to roll.|r"):format(LootSpecText()))
        else
            ShowNote("|cffff8040Click Pass again to give the roll up.|r")
        end
        if settings.sound and PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
        -- Step aside so the next click reaches the game's own button.
        self:Hide()
        C_Timer.After(ARM_TIME, function()
            if settings.enabled and button:IsVisible() then self:Show() end
            if note then note:Hide() end
        end)
    end)
    shields[button] = cover
    return cover
end

local function RollButton()
    return BonusRollFrame and ((BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.RollButton)
        or BonusRollFrame.RollButton)
end

local function PassButton()
    return BonusRollFrame and ((BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.PassButton)
        or BonusRollFrame.PassButton)
end

local function Arm()
    if not (settings and settings.enabled and BonusRollFrame) then return end
    local roll, pass = RollButton(), PassButton()
    local rollCover = Shield(roll, true)
    if rollCover then rollCover:Show() end
    local passCover = Shield(pass, false)
    if passCover then passCover:SetShown(settings.guardPass) end
    if note then note:Hide() end
end

local function Disarm()
    for _, cover in pairs(shields) do cover:Hide() end
    if note then note:Hide() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "BONUS_ROLL_STARTED" or event == "SPELL_CONFIRMATION_PROMPT" then
        -- The frame lays itself out first.
        C_Timer.After(0, Arm)
    else
        Disarm()
    end
end)

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Bonus Roll Guard", 440, 220)
        optionsWindow = w
        w:AddCheckbox(settings, "guardPass", "Also guard Pass", nil, Arm)
        w:AddCheckbox(settings, "sound", "A click sound on the first press")
        w:AddNote("The first click on Roll shows which spec the loot goes to; click again within "
            .. ARM_TIME .. " seconds to roll. The roll itself is the game's own button.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bonusrollguard
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bonusrollguard = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bonusrollguard",
        name     = "Bonus Roll Guard",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "bonus", "roll", "coin", "loot", "spec", "confirm", "raid" },
        desc     = "A bonus roll needs two clicks, and shows which spec the loot goes to first.",
        icon     = "Interface\\Icons\\INV_Misc_CuriousCoin",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            eventFrame:RegisterEvent("BONUS_ROLL_STARTED")
            eventFrame:RegisterEvent("BONUS_ROLL_FAILED")
            eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
            eventFrame:RegisterEvent("BONUS_ROLL_DEACTIVATE")
            -- The window can also open without the event (a reload mid-roll).
            if BonusRollFrame and not frameHooked then
                frameHooked = true
                BonusRollFrame:HookScript("OnShow", function() C_Timer.After(0, Arm) end)
            end
            if BonusRollFrame and BonusRollFrame:IsShown() then Arm() end
        end,
        OnDisable = function()
            eventFrame:UnregisterAllEvents()
            Disarm()
        end,
    })
end)
