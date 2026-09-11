-- ============================================================================
-- Auto Delete (built-in OxedHub module)
-- Fills in the confirmation word when the game asks you to type it before
-- destroying something, so deleting a good item is one click instead of a
-- round of typing.
--
-- It only types. The Accept button is still yours to press: the confirmation
-- exists so an item is not thrown away by accident, and pressing it for the
-- player would remove the one step that still asks.
--
-- The word comes from the game's own string rather than a literal "DELETE".
-- A client in another language asks for its own word, and typing the English
-- one there would simply never match.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled      = true,
    questItems   = true,   -- items that also abandon the quest they belong to
    housingDecor = true,   -- destroying housing decor from storage
}

local settings          -- OxedHubDB.modules.autodelete, bound at login
local hooked = false
local optionsWindow

-- ── Which confirmations, and what each wants typed ──────────────────────────
-- setting: the option that must be on for this one (nil: the module alone).
-- word:    the text the box expects, read when the window opens.
local CONFIRMATIONS = {
    DELETE_GOOD_ITEM = {
        word = function() return DELETE_ITEM_CONFIRM_STRING end,
    },
    DELETE_GOOD_QUEST_ITEM = {
        setting = "questItems",
        word = function() return DELETE_ITEM_CONFIRM_STRING end,
    },
    CONFIRM_DESTROY_DECOR = {
        setting = "housingDecor",
        -- The decor window can carry its own word in its data.
        word = function(data)
            return (type(data) == "table" and data.confirmationString)
                or HOUSING_DECOR_STORAGE_ITEM_DESTROY_CONFIRMATION_STRING
        end,
    },
}

-- ── Finding the window that just opened ─────────────────────────────────────

local function FindDialog(which)
    if StaticPopup_FindVisible then
        local dialog = StaticPopup_FindVisible(which)
        if dialog then return dialog end
    end
    -- Older layout: a fixed set of numbered popup frames.
    for index = 1, (STATICPOPUP_NUMDIALOGS or 4) do
        local dialog = _G["StaticPopup" .. index]
        if dialog and dialog:IsShown() and dialog.which == which then
            return dialog
        end
    end
    return nil
end

local function GetEditBox(dialog)
    if dialog.GetEditBox then
        local ok, box = pcall(dialog.GetEditBox, dialog)
        if ok and box then return box end
    end
    return dialog.editBox or dialog.EditBox
end

-- ── Filling it in ───────────────────────────────────────────────────────────

local function OnConfirmationShown(which, _, _, data)
    if not settings or settings.enabled == false then return end

    local rule = CONFIRMATIONS[which]
    if not rule then return end
    if rule.setting and settings[rule.setting] == false then return end

    local word = rule.word(data)
    if type(word) ~= "string" or word == "" then return end

    local dialog = FindDialog(which)
    local box = dialog and GetEditBox(dialog)
    if not box then return end

    box:SetText(word)
    -- Let go of the keyboard: with focus left in the box, the next key the
    -- player presses would land in it instead of moving their character.
    box:ClearFocus()
end

-- A hook cannot be taken off again, so switching the module off is handled by
-- the check at the top of OnConfirmationShown rather than by unhooking.
local function InstallHook()
    if hooked then return end
    hooked = true

    if StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", OnConfirmationShown)
        return
    end

    -- No shared entry point: hook each confirmation's own OnShow instead.
    for which in pairs(CONFIRMATIONS) do
        local dialogInfo = StaticPopupDialogs and StaticPopupDialogs[which]
        if dialogInfo and type(dialogInfo.OnShow) == "function" then
            hooksecurefunc(dialogInfo, "OnShow", function(_, data)
                OnConfirmationShown(which, nil, nil, data)
            end)
        end
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autodelete
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autodelete = config
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
        optionsWindow = API:CreateOptionsWindow("Auto Delete", 380, 170)
        optionsWindow:AddCheckbox(settings, "questItems", "Also for quest items",
            "Quest items warn that destroying them abandons the quest. Leave this off if you would rather type that one yourself.")
        optionsWindow:AddCheckbox(settings, "housingDecor", "Also for housing decor",
            "Fill in the word when destroying decor from your housing storage.")
        optionsWindow:AddNote("The word is typed for you. You still press Accept yourself.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        InstallHook()
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autodelete",
        name     = "Auto Delete",
        version  = "1.0.0",
        author   = "Oxed",
        category = "inventory",
        desc     = "Types the confirmation word for you when you destroy an item. You still press Accept.",
        icon     = "Interface\\Icons\\INV_Misc_Bomb_01",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            InstallHook()
        end,

        -- Nothing to take down: the hook stays, and stays quiet while off.
        OnDisable = function() end,
    })
end)
