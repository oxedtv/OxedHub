-- ============================================================================
-- Currency Transfer (built-in OxedHub module)
-- Originally "Currency Transfer Helper" by taudier
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled     = false,
    flip        = false,  -- personal currency by default
    flop        = false,  -- disable the currency transfer quick browsing
    currencies  = {},     -- stores toggled states for specific currencies
}

local settings
local optionsWindow
local isInitialized = false

local btn
local CDUMemo = {}
local u = false
local h = {}
local flop = false
local n = 0

local function update0(frame, elementData, currencyID)
    if not settings then return end
    local q = CDUMemo[currencyID]
    if (not settings.flip and settings.currencies[currencyID]) or (settings.flip and not settings.currencies[currencyID]) then
        if not q then    
            q = C_CurrencyInfo.GetCurrencyInfo(currencyID).quantity
            CDUMemo[currencyID] = q
        end
        q = "|cffFFFF00" .. q .. "|r"
    else
        local p = elementData.transferPercentage / 100
        if not q then    
            q = C_CurrencyInfo.GetCurrencyInfo(currencyID).quantity
            local t = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(currencyID)
            if t then
                for _, v in next, t do
                    q = q + math.floor(v.quantity * p)
                end
                CDUMemo[currencyID] = q
            else
                q = "...+" .. q
            end
        end
        if p == 1 then
            q = "|cff00FF00" .. q .. "|r"
        else
            q = "|cffFF6600" .. q .. "|r"
        end
    end
    frame.Content.Count:SetText(q)
end

local function onmouseup(self, button)
    if button == "RightButton" then
        self = self:GetParent()
        local elementData = self.elementData
        if elementData and elementData.isAccountTransferable == true then
            local currencyID = elementData.currencyID
            settings.currencies[currencyID] = not settings.currencies[currencyID] or nil
            CDUMemo[currencyID] = nil
            update0(self, elementData, currencyID)
        end
    end
end

local function update1()
    u = false
    local TokenFrame = _G.TokenFrame
    if not TokenFrame or not TokenFrame.ScrollBox or not TokenFrame.ScrollBox:IsShown() then
        return
    end
    C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
    for _, frame in TokenFrame.ScrollBox:EnumerateFrames() do
        local elementData = frame.elementData
        if elementData and elementData.isAccountTransferable == true then
            if (not settings.flop and not flop) and not InCombatLockdown() and not h[frame] then
                local f = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
                if not pcall(function() f:SetAllPoints(frame) end) then
                    f:SetParent(nil)
                    flop = true
                else
                    f:SetAllPoints(frame)
                    n = n + 1
                    h[frame] = true
                    btn:SetAttribute("clickbutton-"..n, frame)
                    f:SetAttribute("*typerelease1", "click")
                    f:SetAttribute("*clickbutton1", frame)
                    f:SetAttribute("typerelease2", "macro")
                    f:SetAttribute("macrotext2", "/click CTHbtn "..n.."\n/click CTHbtn 0")    
                    f:SetAttribute("pressAndHoldAction", true)
                    f:SetPropagateMouseMotion(true)
                    f:SetScript("OnMouseUp", onmouseup)
                    f:HookScript("OnClick", update1)
                    SecureHandlerWrapScript(f, "OnClick", btn, [[return (IsModifiedClick("TOKENWATCHTOGGLE") or IsModifiedClick("CHATLINK") or not owner:GetAttribute("frameref-menu"):IsShown()) and "LeftButton" or "RightButton"]])
                end
            end
            update0(frame, elementData, elementData.currencyID)
        end
    end
end

local function update2()
    if u == false then
        C_Timer.After(0.25, update1)
        u = true 
    end
end

-- ── Saying what our button moved ───────────────────────────────────────────
-- The game writes its own line ("X transferred ... to Y"); after a transfer
-- made with our Transfer Max button, OxedHub says so too, from the game's
-- transfer log.
local usedOurButtonAt = 0
local logSizeAtClick       -- entries in the log when our button was pressed

local function LogSize()
    if not (C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyTransferTransactions) then return nil end
    local ok, list = pcall(C_CurrencyInfo.FetchCurrencyTransferTransactions)
    return ok and type(list) == "table" and #list or nil
end
local lastReported
local logWatcher = CreateFrame("Frame")

local function NameFromGUID(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then return nil end
    local ok, _, _, _, _, _, name = pcall(GetPlayerInfoByGUID, guid)
    return ok and name or nil
end

local function ReportLastTransfer()
    if GetTime() - usedOurButtonAt > 20 then return end
    if not (C_CurrencyInfo and C_CurrencyInfo.FetchCurrencyTransferTransactions) then return end
    local ok, list = pcall(C_CurrencyInfo.FetchCurrencyTransferTransactions)
    if not ok or type(list) ~= "table" or #list == 0 then return end
    -- Only an entry that arrived after the click is this transfer.
    if logSizeAtClick and #list <= logSizeAtClick then return end
    local last = list[#list]
    local amount = last.quantityTransferred
    local currencyID = last.currencyType
    if type(amount) ~= "number" or type(currencyID) ~= "number" then return end
    local key = tostring(last.sourceCharacterGUID) .. currencyID .. amount .. tostring(last.timestamp)
    if key == lastReported then return end
    lastReported = key
    usedOurButtonAt = 0
    local link = C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(currencyID, amount)
    local from = NameFromGUID(last.sourceCharacterGUID) or "another character"
    local to = NameFromGUID(last.destinationCharacterGUID) or UnitName("player")
    print(("|cff00ccffOxedHub|r transferred %s x%d from %s to %s."):format(
        link or ("currency " .. currencyID), amount, from, to))
end

logWatcher:SetScript("OnEvent", function()
    -- The log can arrive a moment after the currency itself.
    C_Timer.After(0.3, ReportLastTransfer)
end)

local function TryInitialize()
    if isInitialized then return true end
    
    local CurrencyTransferMenu = _G.CurrencyTransferMenu
    local TokenFrame = _G.TokenFrame
    local TokenFramePopup = _G.TokenFramePopup

    if not CurrencyTransferMenu or not CurrencyTransferMenu.Content then return false end
    if not TokenFrame or not TokenFramePopup then return false end
    if not TokenFramePopup.CurrencyTransferToggleButton then return false end

    local toggle = TokenFramePopup.CurrencyTransferToggleButton
    local confirm = CurrencyTransferMenu.Content.ConfirmButton
    local cancel = CurrencyTransferMenu.Content.CancelButton

    btn = CreateFrame("Button", "CTHbtn", CurrencyTransferMenu, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    btn:SetAttribute("*downbutton1", "down")
    btn:SetAttribute("*type-down", "click")
    btn:SetAttribute("*clickbutton-down", CurrencyTransferMenu.Content.AmountSelector.MaxQuantityButton)
    btn:SetAttribute("*typerelease1", "click")
    btn:SetAttribute("*clickbutton-0", toggle)
    btn:SetAttribute("*clickbutton1", confirm)
    btn:SetAttribute("pressAndHoldAction", true)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    
    local transferText = TRANSFER or "Transfer"
    local maxQuantText = CURRENCY_TRANSFER_MAX_QUANTITY_BUTTON or "Max"
    btn:SetTextToFit(transferText .. " " .. maxQuantText)
    btn:SetPoint("LEFT", cancel, "RIGHT", 8, 0)

    confirm:ClearAllPoints()
    confirm:SetPoint("BOTTOMLEFT", (CurrencyTransferMenu:GetWidth() - (200 + btn:GetWidth() + 2 * 8)) / 2, 8)
    cancel:ClearAllPoints()
    cancel:SetPoint("LEFT", confirm, "RIGHT", 8, 0)
    
    btn:SetAttribute("typerelease", "click")
    -- Remember that this transfer was ours, so OxedHub can report it.
    btn:HookScript("OnClick", function()
        usedOurButtonAt = GetTime()
        logSizeAtClick = LogSize()
        if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyTransferLog then
            pcall(C_CurrencyInfo.RequestCurrencyTransferLog)
        end
    end)
    logWatcher:RegisterEvent("CURRENCY_TRANSFER_LOG_UPDATE")
    logWatcher:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    SecureHandlerSetFrameRef(btn, "menu", CurrencyTransferMenu)

    btn:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    btn:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    btn:SetScript("OnEvent", function(self, event, arg1)
        if arg1 then CDUMemo[arg1] = nil end
        if TokenFrame:IsShown() then update2() end
    end)
    TokenFrame.ScrollBox:RegisterCallback("OnScroll", update2)
    hooksecurefunc(TokenFrame, "Update", update2)

    isInitialized = true
    return true
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.currencytransfer
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.currencytransfer = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- Make sure currencies subtable exists
    if type(config.currencies) ~= "table" then
        config.currencies = {}
    end
    settings = config
end

local function UpdateDisplay()
    if isInitialized then update2() end
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Currency Transfer", 460, 280)
        optionsWindow:AddNote("Clean and quick currency transfer. Replaces the original Currency Transfer Helper addon.")
        
        optionsWindow:AddCheckbox(settings, "flip", "Personal Currency by Default",
            "Toggle between account and personal currency by default.", UpdateDisplay)
            
        optionsWindow:AddCheckbox(settings, "flop", "Disable Quick Browsing",
            "Disable the 'Currency transfer quick browsing' in case you have conflicts with other addons.", UpdateDisplay)
            
        optionsWindow:AddNote("|cffaaaaaaTo toggle quick transfer on specific currencies, right-click them in your TokenFrame while this module is enabled.|r")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:RegisterEvent("ADDON_LOADED")
loginFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        BindSettings()
        if not OxedHub.ModuleAPI then
            if settings.enabled == true then TryInitialize() end
            return
        end

        OxedHub.ModuleAPI:Register({
            id       = "currencytransfer",
            name     = "Currency Transfer",
            version  = "2.16",
            author   = "taudier",
            category = "character",
            keywords = { "currency", "transfer", "helper", "warband", "token" },
            desc     = "Adds a quick transfer button and quick browsing for account-wide currency transfers.",
            icon     = "Interface\\Icons\\INV_Misc_Coin_01",
            
            defaults = DEFAULTS,

            OnOptionsShow = function() ShowOptions() end,

            OnEnable = function(_, config)
                settings = config
                if not TryInitialize() then
                    -- Blizzard_TokenUI might not be loaded yet
                end
                if btn then btn:Show() end
                if isInitialized then update2() end
            end,

            OnDisable = function()
                if btn then btn:Hide() end
            end,
        })
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_TokenUI" then
        if settings and settings.enabled then
            TryInitialize()
        end
    end
end)
