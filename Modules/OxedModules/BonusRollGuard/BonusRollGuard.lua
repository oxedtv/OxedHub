-- ============================================================================
-- Bonus Roll Guard (built-in OxedHub module)
-- A bonus roll is spent on one click, often by accident and often in the
-- wrong loot specialisation. With this on, Roll (and Pass) first ask in a
-- popup, which names the spec the loot goes to; Confirm does it.
--
-- How: the game's Roll and Pass buttons keep their own click handler, but it
-- is wrapped: while the module is on, the click opens our popup and the
-- popup's Confirm calls the game's handler, still inside the player's click.
--
-- ⚠ The first version laid a button of ours over the game's and needed a
-- second click. It never armed: the prompt opens on SPELL_CONFIRMATION_PROMPT,
-- not BONUS_ROLL_STARTED (which fires after the roll), so the cover was not
-- there when the window came up.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled   = false,  -- off until the player switches it on
    guardPass = true,   -- also ask before Pass
    sound     = true,   -- a sound when the popup opens
}

local POPUP_ROLL = "OXEDHUB_BONUS_ROLL_CONFIRM"
local POPUP_PASS = "OXEDHUB_BONUS_PASS_CONFIRM"

local settings
local optionsWindow
local wrapped = {}      -- [game button] = true once its OnClick is wrapped
local frameHooked = false

local function LootSpecText()
    local specID = GetLootSpecialization and GetLootSpecialization()
    if specID and specID > 0 then
        local _, name, _, icon = GetSpecializationInfoByID(specID)
        if name then return ("|T%s:16|t %s"):format(tostring(icon), name) end
    end
    local index = GetSpecialization and GetSpecialization()
    if index then
        local _, name, _, icon = GetSpecializationInfo(index)
        if name then return (L["|T%s:16|t %s (your current spec)"]):format(tostring(icon), name) end
    end
    return "unknown"
end

-- What Confirm should do; set each time a popup opens.
local pendingAction

StaticPopupDialogs[POPUP_ROLL] = {
    text = "Use your bonus roll?\n\nLoot goes to: |cffffd100%s|r",
    button1 = "Roll",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        local action = pendingAction
        pendingAction = nil
        if action then action() end
    end,
    OnCancel = function() pendingAction = nil end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs[POPUP_PASS] = {
    text = "Give up this bonus roll?",
    button1 = PASS or "Pass",
    button2 = CANCEL or "Cancel",
    OnAccept = function()
        local action = pendingAction
        pendingAction = nil
        if action then action() end
    end,
    OnCancel = function() pendingAction = nil end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}
OxedHub:RegisterLocalizedTable({ StaticPopupDialogs[POPUP_ROLL], StaticPopupDialogs[POPUP_PASS] }, "text", "button1")

local function RollButton()
    return BonusRollFrame and ((BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.RollButton)
        or BonusRollFrame.RollButton)
end

local function PassButton()
    return BonusRollFrame and ((BonusRollFrame.PromptFrame and BonusRollFrame.PromptFrame.PassButton)
        or BonusRollFrame.PassButton)
end

-- Wraps one game button. The wrapper stays for the session; with the module
-- off (or Pass not guarded) it hands the click straight to the game.
local function Wrap(button, isRoll)
    if not button or wrapped[button] then return end
    local original = button:GetScript("OnClick")
    if not original then return end
    wrapped[button] = true

    button:SetScript("OnClick", function(self, mouse, down)
        local guard = settings and settings.enabled and (isRoll or settings.guardPass)
        if not guard then
            return original(self, mouse, down)
        end
        pendingAction = function() original(self, mouse, down) end
        if settings.sound and PlaySound and SOUNDKIT then
            pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end
        if isRoll then
            StaticPopup_Show(POPUP_ROLL, LootSpecText())
        else
            StaticPopup_Show(POPUP_PASS)
        end
    end)
end

local function Arm()
    if not (settings and settings.enabled and BonusRollFrame) then return end
    Wrap(RollButton(), true)
    Wrap(PassButton(), false)
end

-- The roll window went away: a popup still open would act on nothing.
local function ClosePopups()
    pendingAction = nil
    if StaticPopup_Hide then
        StaticPopup_Hide(POPUP_ROLL)
        StaticPopup_Hide(POPUP_PASS)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "SPELL_CONFIRMATION_PROMPT" then
        -- The window lays itself out first.
        C_Timer.After(0, Arm)
    else
        ClosePopups()
    end
end)

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Bonus Roll Guard", 440, 220)
        optionsWindow = w
        w:AddCheckbox(settings, "guardPass", "Also ask before Pass")
        w:AddCheckbox(settings, "sound", "A sound when the question opens")
        w:AddNote("Roll opens a question that names the spec the loot goes to. "
            .. "Confirm rolls, Cancel or Escape keeps the coin. The roll itself is the game's own.")
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
        version  = "1.1.0",
        updated  = 20261024.2,  -- a confirm popup instead of a second click
        author   = "Oxed",
        category = "groups",
        keywords = { "bonus", "roll", "coin", "loot", "spec", "confirm", "raid" },
        desc     = "Asks before a bonus roll is spent, and names the spec the loot goes to.",
        icon     = "Interface\\Icons\\INV_Misc_CuriousCoin",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
            eventFrame:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
            eventFrame:RegisterEvent("BONUS_ROLL_STARTED")
            eventFrame:RegisterEvent("BONUS_ROLL_FAILED")
            eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
            eventFrame:RegisterEvent("BONUS_ROLL_DEACTIVATE")
            -- The window can also open without the event (a reload mid-roll).
            if BonusRollFrame and not frameHooked then
                frameHooked = true
                BonusRollFrame:HookScript("OnShow", function() C_Timer.After(0, Arm) end)
                BonusRollFrame:HookScript("OnHide", ClosePopups)
            end
            Arm()
        end,
        OnDisable = function()
            eventFrame:UnregisterAllEvents()
            ClosePopups()
        end,
    })
end)
