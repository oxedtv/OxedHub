-- ============================================================================
-- Roll Advisor (built-in OxedHub module)
-- A Need/Greed roll gives a few seconds to decide. This puts the answer next
-- to the roll window:
--
--   verdict   big upgrade, upgrade, small upgrade, not an upgrade, not for
--             your class; plus "best for this slot right now" and "on your
--             wishlist" where Leveling Finds knows (Forever)
--   meter     how much it is needed: the gain over what is worn, as a bar
--   worn      the item it would replace
--   extra     what it sells for, and that it binds when equipped
--   advice    Need or Greed, with a glow on that button
--
-- It only advises. Nothing is ever rolled for the player.
--
-- The comparison is Leveling Finds' own (OxedHub.GearAdvice): stats times
-- what they are worth to the character's role, or item level when the player
-- chose that there. It is a rough ranking, not a simulation.
--
-- The roll windows are the game's GroupLootFrame1..4. An addon that replaces
-- them leaves nothing to hang the panel on; the chat line still comes.
-- ============================================================================

local addonName, OxedHub = ...
local T = function(s) return OxedHub.T and OxedHub.T(s) or s end

local ICON = "Interface\\Icons\\INV_Misc_Dice_01"
local PREFIX = "|cff33ff99OxedHub Roll Advisor:|r "
local MAX_FRAMES = 4
local PANEL_W = 250

local DEFAULTS = {
    enabled       = false,  -- off until the player switches it on
    minimapButton = true,
    panel         = true,   -- the panel beside the roll window
    side          = "right",
    scale         = 1,
    highlight     = true,   -- glow on the suggested button
    chat          = true,   -- one line in chat per roll
    showSell      = true,
    sound         = "",     -- played when the roll is an upgrade
}

local settings
local running = false
local optionsWindow
local minimapIcon, MinimapIcon, ShowOptions
local panels = {}        -- [index] = our panel on GroupLootFrame<index>
local testPanel
local announced = {}     -- [rollID] = true once its chat line is out
local announcedCount = 0

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function PlainString(v) return type(v) == "string" and not Secret(v) and v ~= "" end
local function PlainNumber(v) return type(v) == "number" and not Secret(v) end

-- ── The verdict ─────────────────────────────────────────────────────────────

local COLOUR = {
    great = { 0.25, 1, 0.25 },
    good  = { 0.55, 1, 0.35 },
    small = { 0.85, 1, 0.45 },
    none  = { 0.7, 0.7, 0.7 },
    bad   = { 1, 0.35, 0.3 },
    info  = { 1, 0.82, 0 },
}

local function Money(copper)
    if not PlainNumber(copper) or copper <= 0 then return nil end
    local fn = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    if fn then
        local ok, text = pcall(fn, copper)
        if ok and PlainString(text) then return text end
    end
    return tostring(copper)
end

local function Number(value)
    return (value < 10 and "%.1f" or "%d"):format(value)
end

-- Everything the panel shows for one item link. Returns nil while the game
-- has not loaded the item; the caller asks again a moment later.
--   tone      a key of COLOUR
--   title     the verdict
--   meter     0..1, or nil for no bar
--   meterText what the bar says
--   worn      the link of the item it would replace, or false for an empty slot
--   lines     extra lines
--   suggest   "need", "greed" or nil
local function Advise(link, canNeed, canGreed)
    local Gear = OxedHub.GearAdvice
    if not (Gear and Gear.CompareLink) then return nil end
    local ok, cmp = pcall(Gear.CompareLink, link)
    if not ok or not cmp then return nil end

    local advice = { lines = {} }
    local itemID = tonumber(link:match("item:(%d+)"))

    if cmp.kind == "unknown" then return nil end
    if cmp.kind == "bag" then
        advice.tone, advice.title = "info", T("A bag")
        advice.suggest = "greed"
    elseif cmp.kind == "other" then
        advice.tone, advice.title = "none", T("Not something to wear")
        advice.suggest = "greed"
    elseif not cmp.usable then
        advice.tone, advice.title = "bad", T("Not for your class")
        advice.suggest = "greed"
    else
        local gain, worn = cmp.gain or 0, cmp.worn or 0
        advice.worn = cmp.wornLink or false
        if gain >= 0.1 then
            local share = worn > 0 and gain / worn or 1
            if worn <= 0 or share >= 0.25 then
                advice.tone, advice.title = "great", T("Big upgrade")
            elseif share >= 0.08 then
                advice.tone, advice.title = "good", T("Upgrade")
            else
                advice.tone, advice.title = "small", T("Small upgrade")
            end
            -- A full bar is forty percent better than what is worn.
            advice.meter = math.max(0.05, math.min(1, share / 0.4))
            if worn <= 0 then
                advice.meterText = T("The slot is empty")
            elseif cmp.byStats then
                advice.meterText = T("+%d%% by stats (+%s)"):format(math.floor(share * 100 + 0.5), Number(gain))
            else
                advice.meterText = T("+%d item levels"):format(gain)
            end
            advice.suggest = "need"
        else
            advice.tone, advice.title = "none", T("Not an upgrade")
            advice.meter = 0
            if cmp.byStats then
                advice.meterText = T("%s by stats"):format(Number(gain))
            else
                advice.meterText = T("%d item levels"):format(gain)
            end
            advice.suggest = "greed"
        end
        if cmp.tooHigh then
            advice.lines[#advice.lines + 1] = "|cffff8040" .. T("Needs level %d"):format(cmp.req) .. "|r"
        end
    end

    -- What Leveling Finds knows about it (Forever).
    if itemID and cmp.kind == "gear" and cmp.usable then
        local okBest, best = pcall(Gear.IsBestNow, itemID)
        if okBest and best then
            advice.lines[#advice.lines + 1] = "|cffffd100" .. T("Best for this slot right now") .. "|r"
            advice.suggest = "need"
        end
    end
    if itemID then
        local okWish, wished = pcall(Gear.IsWished, itemID)
        if okWish and wished then
            advice.lines[#advice.lines + 1] = "|cff66ccff" .. T("On your wishlist") .. "|r"
            if cmp.usable then advice.suggest = "need" end
        end
    end

    if settings.showSell then
        local money = Money(cmp.sell)
        if money then advice.lines[#advice.lines + 1] = T("Sells for %s"):format(money) end
    end
    -- 2 is "binds when equipped": it can be sold or passed on.
    if cmp.bind == 2 then
        advice.lines[#advice.lines + 1] = "|cff9d9d9d" .. T("Binds when equipped") .. "|r"
    end

    -- Never suggest a button the game has greyed out.
    if advice.suggest == "need" and canNeed == false then advice.suggest = canGreed ~= false and "greed" or nil end
    if advice.suggest == "greed" and canGreed == false then advice.suggest = nil end
    return advice
end

local function SuggestText(suggest)
    if suggest == "need" then return "|cff40ff40" .. T("Suggestion: Need") .. "|r" end
    if suggest == "greed" then return "|cffffd100" .. T("Suggestion: Greed") .. "|r" end
    return nil
end

-- ── The panel ───────────────────────────────────────────────────────────────

-- The look is the one the addon's own windows have (Hunter Pets, Currencies):
-- the stone panel with the gold corners and edges and the gold title plate,
-- drawn by UIComponents.Panel. Inside, the card is laid out like the OxMemes
-- one: an icon with a glow behind it, a small caption, the verdict in large
-- text. The icon is the game's own roll button art: the dice, the coin.
local ROLL_ICON = {
    need  = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    greed = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    none  = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
local HEAD_TOP = 18      -- room under the title plate
local ICON_SIZE = 36

local function MakePanel(parent, name)
    local p = CreateFrame("Frame", name, parent, "BackdropTemplate")
    p:SetWidth(PANEL_W)
    p:SetFrameStrata("DIALOG")

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    local ornate = false
    if Panel and Panel.ApplyOrnateFrame then
        ornate = pcall(Panel.ApplyOrnateFrame, p, T("Roll Advisor"), 0.96)
    end
    if not ornate then
        -- The plain card: the game's tooltip border on a dark ground.
        p:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        p:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        p:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    end

    -- A soft light across the top, so the stone is not one flat colour.
    p.shine = p:CreateTexture(nil, "BACKGROUND", nil, 1)
    p.shine:SetPoint("TOPLEFT", 5, -5)
    p.shine:SetPoint("TOPRIGHT", -5, -5)
    p.shine:SetHeight(34)
    p.shine:SetColorTexture(1, 1, 1, 0.035)

    -- The roll icon, a glow of the verdict's colour behind it.
    p.iconGlow = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.iconGlow:SetSize(ICON_SIZE + 22, ICON_SIZE + 22)
    p.iconGlow:SetTexture("Interface\\Cooldown\\star4")
    p.iconGlow:SetBlendMode("ADD")
    p.iconGlow:SetAlpha(0.45)
    p.icon = p:CreateTexture(nil, "ARTWORK", nil, 2)
    p.icon:SetSize(ICON_SIZE, ICON_SIZE)
    p.icon:SetPoint("TOPLEFT", 12, -HEAD_TOP)
    p.iconGlow:SetPoint("CENTER", p.icon, "CENTER", 0, 0)

    p.caption = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.caption:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 9, -1)
    p.caption:SetPoint("RIGHT", -10, 0)
    p.caption:SetJustifyH("LEFT")

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    p.title:SetPoint("TOPLEFT", p.caption, "BOTTOMLEFT", 0, -3)
    p.title:SetPoint("RIGHT", -10, 0)
    p.title:SetJustifyH("LEFT")
    if p.title.SetWordWrap then p.title:SetWordWrap(false) end

    -- The meter: the game's own bar texture in a thin tooltip border.
    p.barFrame = CreateFrame("Frame", nil, p, "BackdropTemplate")
    p.barFrame:SetHeight(20)
    p.barFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    p.barFrame:SetBackdropColor(0, 0, 0, 0.6)
    p.barFrame:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    p.bar = CreateFrame("StatusBar", nil, p.barFrame)
    p.bar:SetPoint("TOPLEFT", 3, -3)
    p.bar:SetPoint("BOTTOMRIGHT", -3, 3)
    p.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    p.bar:SetMinMaxValues(0, 1)
    p.bar.text = p.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.bar.text:SetPoint("CENTER", 0, 0)

    p.body = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.body:SetJustifyH("LEFT")
    p.body:SetSpacing(3)
    p.body:SetWidth(PANEL_W - 24)

    -- The glow on the suggested button. A texture of the panel's, so its
    -- pulse never touches the game's own frames.
    p.glow = p:CreateTexture(nil, "OVERLAY")
    p.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    p.glow:SetBlendMode("ADD")
    p.glow:Hide()
    local group = p.glow:CreateAnimationGroup()
    group:SetLooping("BOUNCE")
    local pulse = group:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.35)
    pulse:SetDuration(0.55)
    p.glowPulse = group

    p:Hide()
    return p
end

local function Fill(p, advice)
    local c = COLOUR[advice.tone] or COLOUR.none
    p.icon:SetTexture(ROLL_ICON[advice.suggest or "none"] or ROLL_ICON.none)
    p.iconGlow:SetVertexColor(c[1], c[2], c[3])
    p.caption:SetText(SuggestText(advice.suggest) or ("|cff9a9aa0" .. T("No suggestion") .. "|r"))
    p.title:SetText(advice.title)
    p.title:SetTextColor(c[1], c[2], c[3])

    local y = -(HEAD_TOP + ICON_SIZE + 8)
    if advice.meter then
        p.barFrame:ClearAllPoints()
        p.barFrame:SetPoint("TOPLEFT", 10, y)
        p.barFrame:SetPoint("RIGHT", -10, 0)
        p.bar:SetValue(advice.meter)
        p.bar:SetStatusBarColor(c[1] * 0.8, c[2] * 0.8, c[3] * 0.8, 1)
        p.bar.text:SetText(advice.meterText or "")
        p.barFrame:Show()
        y = y - 26
    else
        p.barFrame:Hide()
    end

    local lines = {}
    if advice.worn then
        lines[#lines + 1] = "|cffffd100" .. T("Instead of:") .. "|r " .. advice.worn
    end
    for _, line in ipairs(advice.lines) do lines[#lines + 1] = line end

    p.body:ClearAllPoints()
    p.body:SetPoint("TOPLEFT", 12, y)
    p.body:SetText(table.concat(lines, "\n"))
    local bodyHeight = #lines > 0 and (p.body:GetStringHeight() + 4) or 0
    p:SetHeight(-y + bodyHeight + 10)
end

local function RollButtons(frame)
    local name = frame.GetName and frame:GetName()
    local need = frame.NeedButton or (name and _G[name .. "RollButton"])
    local greed = frame.GreedButton or (name and _G[name .. "GreedButton"])
    return need, greed
end

local function PlaceGlow(p, button)
    if not (settings.highlight and button and button.IsShown and button:IsShown()) then
        p.glowPulse:Stop()
        p.glow:Hide()
        return
    end
    local size = (button:GetWidth() or 32) * 1.9
    p.glow:ClearAllPoints()
    p.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    p.glow:SetSize(size, size)
    p.glow:SetVertexColor(0.3, 1, 0.3)
    p.glow:Show()
    if not p.glowPulse:IsPlaying() then p.glowPulse:Play() end
end

local function Anchor(p, frame)
    p:ClearAllPoints()
    p:SetScale(tonumber(settings.scale) or 1)
    if settings.side == "left" then
        p:SetPoint("RIGHT", frame, "LEFT", -6, 0)
    else
        p:SetPoint("LEFT", frame, "RIGHT", 6, 0)
    end
end

-- ── Rolls ───────────────────────────────────────────────────────────────────

-- The link and what may be rolled, or nil when the game gives nothing plain.
local function RollInfo(rollID)
    if not (GetLootRollItemLink and PlainNumber(rollID)) then return nil end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if not ok or not PlainString(link) then return nil end
    local canNeed, canGreed
    if GetLootRollItemInfo then
        local okInfo, _, _, _, _, _, need, greed = pcall(GetLootRollItemInfo, rollID)
        if okInfo then
            if not Secret(need) and need ~= nil then canNeed = need and true or false end
            if not Secret(greed) and greed ~= nil then canGreed = greed and true or false end
        end
    end
    return link, canNeed, canGreed
end

local function Announce(rollID, link, advice)
    if announced[rollID] then return end
    announced[rollID] = true
    announcedCount = announcedCount + 1
    if announcedCount > 200 then
        wipe(announced)
        announced[rollID] = true
        announcedCount = 1
    end
    if settings.chat then
        local c = COLOUR[advice.tone] or COLOUR.none
        local text = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, advice.title)
        local parts = { PREFIX .. link .. " " .. text }
        if advice.meterText and advice.meter and advice.meter > 0 then parts[#parts + 1] = advice.meterText end
        local suggest = SuggestText(advice.suggest)
        if suggest then parts[#parts + 1] = suggest end
        print(table.concat(parts, ", "))
    end
    if advice.suggest == "need" and type(settings.sound) == "string" and settings.sound ~= "" then
        local API = OxedHub.ModuleAPI
        if API and API.PlaySound then pcall(API.PlaySound, API, settings.sound) end
    end
end

local pendingRolls = {}   -- [rollID] = tries left, for rolls with no window of the game's
local ticker = CreateFrame("Frame")
local waited = 0

-- Looks at the game's roll windows and brings each panel up to date. Returns
-- true while there is still something to watch.
local function Refresh()
    local busy = false
    for index = 1, MAX_FRAMES do
        local frame = _G["GroupLootFrame" .. index]
        local p = panels[index]
        local rollID = frame and frame.IsShown and frame:IsShown() and frame.rollID
        if rollID and PlainNumber(rollID) then
            busy = true
            local link, canNeed, canGreed = RollInfo(rollID)
            local advice = link and Advise(link, canNeed, canGreed)
            if advice then
                pendingRolls[rollID] = nil
                Announce(rollID, link, advice)
                if settings.panel then
                    if not p then
                        local ok, made = pcall(MakePanel, frame, "OxedHubRollAdvisor" .. index)
                        if ok then
                            p = made
                            panels[index] = p
                        end
                    end
                    if p then
                        Anchor(p, frame)
                        Fill(p, advice)
                        local need, greed = RollButtons(frame)
                        PlaceGlow(p, advice.suggest == "need" and need or advice.suggest == "greed" and greed or nil)
                        p:Show()
                    end
                elseif p then
                    p:Hide()
                end
            elseif p then
                p:Hide()   -- the item is not loaded yet: asked again on the next tick
            end
        elseif p and p:IsShown() then
            p.glowPulse:Stop()
            p:Hide()
        end
    end

    -- Rolls whose window is not the game's: the chat line only.
    for rollID, tries in pairs(pendingRolls) do
        local link, canNeed, canGreed = RollInfo(rollID)
        local advice = link and Advise(link, canNeed, canGreed)
        if advice then
            Announce(rollID, link, advice)
            pendingRolls[rollID] = nil
        elseif tries <= 1 then
            pendingRolls[rollID] = nil
        else
            pendingRolls[rollID] = tries - 1
            busy = true
        end
    end
    return busy
end

local function OnTick(_, dt)
    waited = waited + dt
    if waited < 0.25 then return end
    waited = 0
    local ok, busy = pcall(Refresh)
    if not ok or not busy then ticker:SetScript("OnUpdate", nil) end
end

local function Watch()
    if not running then return end
    waited = 1   -- look on the very next frame
    ticker:SetScript("OnUpdate", OnTick)
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, rollID)
    if event == "START_LOOT_ROLL" and PlainNumber(rollID) then
        pendingRolls[rollID] = 20   -- five seconds for the item to load
    end
    Watch()
end)

local function HidePanels()
    for index = 1, MAX_FRAMES do
        local p = panels[index]
        if p then
            p.glowPulse:Stop()
            p:Hide()
        end
    end
    if testPanel then testPanel:Hide() end
end

local function Start()
    if running then return end
    running = true
    events:RegisterEvent("START_LOOT_ROLL")
    pcall(events.RegisterEvent, events, "CANCEL_LOOT_ROLL")
    Watch()   -- a roll may already be on screen
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    ticker:SetScript("OnUpdate", nil)
    wipe(pendingRolls)
    HidePanels()
end

-- ── A sample, to see the panel without waiting for a roll ───────────────────

local function ShowTest()
    if not settings then return end
    if not testPanel then
        testPanel = MakePanel(UIParent, "OxedHubRollAdvisorTest")
        testPanel:SetPoint("CENTER", UIParent, "CENTER", -330, 60)
    end
    testPanel:SetScale(tonumber(settings.scale) or 1)
    local worn
    local ok, link = pcall(GetInventoryItemLink, "player", 5)   -- the chest piece, if any
    if ok and PlainString(link) then worn = link end
    Fill(testPanel, {
        tone = "great", title = T("Big upgrade"),
        meter = 0.7, meterText = T("+%d%% by stats (+%s)"):format(28, "6.4"),
        worn = worn or false,
        lines = {
            "|cffffd100" .. T("Best for this slot right now") .. "|r",
            T("Sells for %s"):format(Money(1234) or "12"),
        },
        suggest = "need",
    })
    testPanel:Show()
    C_Timer.After(8, function() if testPanel then testPanel:Hide() end end)
end

-- ── Options ─────────────────────────────────────────────────────────────────

ShowOptions = function()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Roll Advisor", 440, 400)
        optionsWindow = w
        w:AddCheckbox(settings, "panel", "Panel beside the roll window", nil, Watch)
        w:AddChoice(settings, "side", "Side", {
            { value = "right", text = "Right" },
            { value = "left",  text = "Left" },
        }, Watch)
        w:AddSlider(settings, "scale", "Size", 0.7, 1.6, 0.05, "%s: %.2f", function()
            Watch()
            if testPanel and testPanel:IsShown() then ShowTest() end
        end)
        w:AddCheckbox(settings, "highlight", "Glow on the suggested button", nil, Watch)
        w:AddCheckbox(settings, "chat", "A line in chat for every roll")
        w:AddCheckbox(settings, "showSell", "Show what it sells for", nil, Watch)
        w:AddSoundPicker(settings, "sound", "Sound when it is an upgrade", "None")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)

        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(200, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)
        test:SetText(T("Show a sample"))
        test:SetScript("OnClick", ShowTest)
        w.cursorY = w.cursorY - 34

        w:AddNote("It only advises: nothing is rolled for you. What counts as better is set in Leveling Finds (your role's stats, or item level).")
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

MinimapIcon = function()
    if minimapIcon or not settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "rolladvisor", label = T("Roll Advisor"), icon = ICON, config = settings,
        hint = T("Click: options."),
        onClick = function() ShowOptions() end,
    })
    return minimapIcon
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.rolladvisor
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.rolladvisor = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    if config.side ~= "left" and config.side ~= "right" then config.side = "right" end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "rolladvisor",
        name     = "Roll Advisor",
        version  = "1.0.1",
        added    = 20261113,
        inDevelopment = true,
        updated  = 20261113.7,  -- the panel in the addon's own stone and gold look
        author   = "Oxed",
        category = "groups",
        keywords = { "need", "greed", "roll", "loot", "upgrade", "bis", "dungeon", "advice" },
        desc     = "On a Need/Greed roll: is the item an upgrade, how much, and which button to press.",
        icon     = ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            local icon = MinimapIcon()
            if icon then icon:Apply(true) end
            Start()
        end,
        OnDisable = function()
            if minimapIcon then minimapIcon:Apply(false) end
            Stop()
        end,
    })
end)
