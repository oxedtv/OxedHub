-- ============================================================================
-- Auto Confirm (built-in OxedHub module, id "autodelete")
-- The game stops to ask before a lot of ordinary actions: destroying an item,
-- selling something that could still be traded, equipping a bind-on-equip
-- piece, putting an enchant over another one. This lets the player choose,
-- one kind at a time, which of those questions they still want to see.
--
-- Every kind is off by default. A confirmation exists because the action cannot
-- be undone, so skipping one is a decision the player makes, never one made
-- for them. The two that spend gold say so on their tick box.
--
-- With the optional Shift switch on, holding Shift while doing the action shows
-- the popup as normal, whatever the other settings say. Off by default.
--
-- The id stays "autodelete": this began as Auto Delete, and renaming the id
-- would drop the settings every existing player has saved.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled        = false,  -- off until the player switches it on (see ModuleAPI:Register)
    shiftSkip   = false,   -- holding Shift skips the module for that moment (player's choice)

    -- Deleting
    typeWord       = true,   -- type the confirmation word into the box
    questItems     = true,   -- ...also for quest items
    housingDecor   = true,   -- ...also for housing decor
    pressDelete    = false,  -- and press Accept as well

    -- Everything else: skip the popup entirely
    sellTradeable  = false,
    buyWithTokens  = false,
    buyHighCost    = false,  -- spends gold
    equipBind      = false,
    lootBind       = false,
    enchant        = false,
    trade          = false,
    mail           = false,
    bankPurchase   = false,  -- spends gold
    abandonQuest   = false,
}

local settings          -- OxedHubDB.modules.autodelete, bound at login
local hooked = false
local optionsWindow

local PREFIX = "|cff00ff00OxedHub:|r "

-- ── What each confirmation is, and what to do with it ───────────────────────
-- which:   the popup's name in StaticPopupDialogs.
-- setting: the tick box that must be on for anything to happen.
-- word:    for the delete popups, the text the box expects.
--
-- Popup names shift between builds. A name listed here that this client does
-- not have simply never matches, so listing a few spellings is harmless; a
-- popup the game renamed is caught by the "seen" list below and can be added.

local function DeleteWord() return DELETE_ITEM_CONFIRM_STRING end
local function DecorWord(data)
    return (type(data) == "table" and data.confirmationString)
        or HOUSING_DECOR_STORAGE_ITEM_DESTROY_CONFIRMATION_STRING
end

local RULES = {
    -- Deleting: the word is typed, and Accept pressed only if asked.
    DELETE_GOOD_ITEM                = { setting = "typeWord", word = DeleteWord, delete = true },
    DELETE_GOOD_QUEST_ITEM          = { setting = "questItems", word = DeleteWord, delete = true, needs = "typeWord" },
    CONFIRM_DESTROY_DECOR           = { setting = "housingDecor", word = DecorWord, delete = true, needs = "typeWord" },
    DELETE_ITEM                     = { setting = "pressDelete", delete = true },
    DELETE_QUEST_ITEM               = { setting = "pressDelete", delete = true, needs = "questItems" },

    -- Selling and buying
    CONFIRM_MERCHANT_TRADE_TIMER_REMOVAL = { setting = "sellTradeable" },
    CONFIRM_PURCHASE_TOKEN_ITEM          = { setting = "buyWithTokens" },
    CONFIRM_PURCHASE_NONREFUNDABLE_ITEM  = { setting = "buyWithTokens" },
    CONFIRM_REFUND_TOKEN_ITEM            = { setting = "buyWithTokens" },
    CONFIRM_HIGH_COST_ITEM               = { setting = "buyHighCost" },

    -- Binding
    EQUIP_BIND                      = { setting = "equipBind" },
    AUTOEQUIP_BIND                  = { setting = "equipBind" },
    EQUIP_BIND_TRADEABLE            = { setting = "equipBind" },
    EQUIP_BIND_REFUNDABLE           = { setting = "equipBind" },
    USE_BIND                        = { setting = "equipBind" },
    ACTION_WILL_BIND_ITEM           = { setting = "equipBind" },
    LOOT_BIND                       = { setting = "lootBind" },
    CONFIRM_LOOT_ROLL               = { setting = "lootBind" },

    -- Enchanting
    REPLACE_ENCHANT                 = { setting = "enchant" },
    BIND_ENCHANT                    = { setting = "enchant" },
    REPLACE_TRADESKILL_ENCHANT      = { setting = "enchant" },

    -- Trade and mail
    TRADE_REPLACE_ENCHANT           = { setting = "trade" },
    TRADE_POTENTIAL_BIND_ENCHANT    = { setting = "trade" },
    TRADE_POTENTIAL_REMOVE_TRANSMOG = { setting = "trade" },
    CONFIRM_MAIL_ITEM_UNREFUNDABLE  = { setting = "mail" },

    -- Bank
    CONFIRM_BUY_BANK_SLOT           = { setting = "bankPurchase" },
    CONFIRM_BUY_BANK_TAB            = { setting = "bankPurchase" },
    CONFIRM_BUY_REAGENTBANK_TAB     = { setting = "bankPurchase" },

    -- Quests
    ABANDON_QUEST                   = { setting = "abandonQuest" },
    ABANDON_QUEST_WITH_ITEMS        = { setting = "abandonQuest" },
}

-- Popups that appeared this session and are not in RULES, by name. Nothing is
-- done with them; /oxconfirm lists them, which is how a confirmation the game
-- renamed or added gets found and put in the table above.
local seen = {}

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

local function GetAcceptButton(dialog)
    if dialog.GetButton1 then
        local ok, button = pcall(dialog.GetButton1, dialog)
        if ok and button then return button end
    end
    return dialog.button1
        or (dialog.ButtonContainer and dialog.ButtonContainer.Button1)
end

-- Presses Accept on the next frame, not inside the show itself. The popup's own
-- setup -- enabling the button once the word is in, filling in its data -- runs
-- after StaticPopup_Show returns, and a press made before that lands on a
-- button that is still disabled. The popup is looked up again first, so a
-- different one that took its place in the meantime is never the one accepted.
local function PressAccept(which, dialog)
    C_Timer.After(0, function()
        if FindDialog(which) ~= dialog or not dialog:IsShown() then return end

        local button = GetAcceptButton(dialog)
        if button then
            -- ⚠ A disabled Accept is the game still refusing -- the delete word
            -- is not in, say. It is left alone, never forced through by other
            -- means: that would destroy an item the game had not agreed to.
            if button:IsShown() and button:IsEnabled() then button:Click() end
        elseif StaticPopup_OnClick then
            -- Only for a layout with no button to find at all.
            pcall(StaticPopup_OnClick, dialog, 1)
        end
    end)
end

-- ── Handling one popup ──────────────────────────────────────────────────────

local function OnPopupShown(which, _, _, data)
    if not settings or settings.enabled == false then return end
    if type(which) ~= "string" then return end
    -- OxedHub's own questions are the player's to answer, never this module's.
    if which:find("^OXEDHUB_") then return end

    local rule = RULES[which]
    if not rule then
        seen[which] = true
        return
    end

    if settings[rule.setting] ~= true then return end
    if rule.needs and settings[rule.needs] ~= true then return end

    -- With the Shift switch on, Shift shows a popup the settings would skip.
    if settings.shiftSkip and IsShiftKeyDown() then return end

    local dialog = FindDialog(which)
    if not dialog then return end

    if rule.word then
        local word = rule.word(data)
        local box = GetEditBox(dialog)
        if type(word) == "string" and word ~= "" and box then
            box:SetText(word)
            -- Let go of the keyboard: with focus left in the box, the next key
            -- the player presses would land in it instead of moving them.
            box:ClearFocus()
        end
        -- The word alone is the default. Accept is pressed only when the
        -- player has asked for deletes to go through without stopping.
        if not settings.pressDelete then return end
    end

    PressAccept(which, dialog)
end

-- A hook cannot be taken off again, so switching the module off is handled by
-- the enabled check at the top of OnPopupShown rather than by unhooking.
local function InstallHook()
    if hooked then return end
    hooked = true

    if StaticPopup_Show then
        hooksecurefunc("StaticPopup_Show", OnPopupShown)
        return
    end

    -- No shared entry point: hook each popup's own OnShow instead.
    for which in pairs(RULES) do
        local dialogInfo = StaticPopupDialogs and StaticPopupDialogs[which]
        if dialogInfo and type(dialogInfo.OnShow) == "function" then
            hooksecurefunc(dialogInfo, "OnShow", function(_, data)
                OnPopupShown(which, nil, nil, data)
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
        optionsWindow = API:CreateOptionsWindow("Auto Confirm", 460, 640)
        local w = optionsWindow

        w:AddNote("|cffffd100Deleting|r")
        w:AddCheckbox(settings, "typeWord", "Type the delete word for you",
            "Fills in the word the game asks for before destroying a good item.")
        w:AddCheckbox(settings, "questItems", "Also for quest items",
            "Destroying a quest item also abandons its quest.")
        w:AddCheckbox(settings, "housingDecor", "Also for housing decor",
            "Destroying decor from your housing storage.")
        w:AddCheckbox(settings, "pressDelete", "Press Accept too (no delete popup)",
            "Deletes go through the moment you drop the item, with no chance to change your mind.")

        w:AddCheckbox(settings, "shiftSkip", "Hold Shift to see a popup anyway",
            "With this on, holding Shift while doing the action shows its popup, whatever is ticked below.")
        w:AddNote("|cffffd100Skip these confirmations|r")
        w:AddCheckbox(settings, "sellTradeable", "Selling an item you could still trade",
            "Loot from a group that can be traded for two hours. Selling it ends that.")
        w:AddCheckbox(settings, "buyWithTokens", "Buying with currency or tokens",
            "Purchases paid in currency, and ones that cannot be refunded.")
        w:AddCheckbox(settings, "buyHighCost", "Expensive purchases  |cffff5555(spends gold)|r",
            "The warning before buying something costly from a vendor.")
        w:AddCheckbox(settings, "equipBind", "Equipping or using a bind-on-equip item",
            "The item becomes soulbound, as it would if you pressed Accept.")
        w:AddCheckbox(settings, "lootBind", "Looting or rolling on a bind-on-pickup item")
        w:AddCheckbox(settings, "enchant", "Replacing or binding an enchant")
        w:AddCheckbox(settings, "trade", "Trade warnings",
            "Enchanting an item in the trade window that would bind it, or lose its appearance.")
        w:AddCheckbox(settings, "mail", "Mailing a non-refundable item")
        w:AddCheckbox(settings, "bankPurchase", "Buying bank slots or tabs  |cffff5555(spends gold)|r")
        w:AddCheckbox(settings, "abandonQuest", "Abandoning a quest")

        w:AddNote("Missing a popup? Type /oxconfirm after it appears to see its name.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

SLASH_OXEDCONFIRM1 = "/oxconfirm"
SlashCmdList["OXEDCONFIRM"] = function()
    local names = {}
    for which in pairs(seen) do names[#names + 1] = which end
    table.sort(names)
    if #names == 0 then
        print(PREFIX .. "no other confirmation popups have appeared this session.")
        return
    end
    print(PREFIX .. "popups seen this session that Auto Confirm does not handle:")
    for _, which in ipairs(names) do print("   " .. which) end
end

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
        id       = "autodelete",   -- kept from Auto Delete, see the header
        name     = "Auto Confirm",
        version  = "1.1.0",
        author   = "Oxed",
        category = "items",
        keywords = { "delete", "destroy", "confirm", "popup", "bind", "enchant", "abandon", "loot" },
        -- Clipped at about 100 characters on the card; the detail is in Options.
        desc     = "Types DELETE for you and skips the confirm popups you pick in Options.",
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
