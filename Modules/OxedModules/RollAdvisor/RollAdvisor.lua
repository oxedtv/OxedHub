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
    logAuto       = true,   -- open "who rolled what" when a roll starts
}

local settings
local running = false
local optionsWindow
local minimapIcon, MinimapIcon, ShowOptions
local OnLootLine, LogRollStart, ToggleLog, HideLog   -- the "who rolled what" window, further down
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
    if event == "CHAT_MSG_LOOT" then
        pcall(OnLootLine, rollID)   -- here the first argument is the chat text
        return
    end
    if event == "START_LOOT_ROLL" and PlainNumber(rollID) then
        pendingRolls[rollID] = 20   -- five seconds for the item to load
        pcall(LogRollStart, rollID)
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
    pcall(events.RegisterEvent, events, "CHAT_MSG_LOOT")
    Watch()   -- a roll may already be on screen
end

local function Stop()
    running = false
    events:UnregisterAllEvents()
    ticker:SetScript("OnUpdate", nil)
    wipe(pendingRolls)
    HidePanels()
    if HideLog then HideLog() end
end

-- ── Who rolled what ─────────────────────────────────────────────────────────
-- Every choice in the group arrives as a loot line in chat ("Ana has selected
-- Need for: [Item]", "Need Roll - 54 for [Item] by Ana", "Ana won: [Item]").
-- The patterns are made from the game's own format strings, so they work in
-- any client language. Kept for the session only, never saved.

local LOG_KEEP = 25        -- items remembered
local LOG_W, LOG_H = 380, 440
local LINE_H = 20
local SAME_ROLL = 300      -- the same item linked again within this long is the same roll

-- Argument order of each line: "p" player, "i" item, "n" roll number.
local LOOT_LINES = {
    { "LOOT_ROLL_NEED",             "need",  "pi" },
    { "LOOT_ROLL_GREED",            "greed", "pi" },
    { "LOOT_ROLL_DISENCHANT",       "de",    "pi" },
    { "LOOT_ROLL_PASSED",           "pass",  "pi" },
    { "LOOT_ROLL_PASSED_AUTO",      "pass",  "pi" },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", "pi" },
    { "LOOT_ROLL_NEED_SELF",        "need",  "i", true },
    { "LOOT_ROLL_GREED_SELF",       "greed", "i", true },
    { "LOOT_ROLL_DISENCHANT_SELF",  "de",    "i", true },
    { "LOOT_ROLL_PASSED_SELF",      "pass",  "i", true },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "pass",  "i", true },
    { "LOOT_ROLL_ROLLED_NEED",      "rollneed",  "nip" },
    { "LOOT_ROLL_ROLLED_GREED",     "rollgreed", "nip" },
    { "LOOT_ROLL_ROLLED_DE",        "rollde",    "nip" },
    { "LOOT_ROLL_WON",              "won",   "pi" },
    { "LOOT_ROLL_YOU_WON",          "won",   "i", true },
    { "LOOT_ROLL_ALL_PASSED",       "allpass", "i" },
}

-- A format string ("%s won: %s", or "%2$s ... %1$s") as a pattern, and which
-- argument each capture is.
local function ToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local out, order, n, i = { "^" }, {}, 0, 1
    while i <= #fmt do
        local c = fmt:sub(i, i)
        if c == "%" then
            local s, e, pos, kind = fmt:find("^%%(%d)%$([sd])", i)
            if not s then s, e, kind = fmt:find("^%%([sd])", i) end
            if s then
                n = n + 1
                order[n] = tonumber(pos) or n
                out[#out + 1] = (kind == "d") and "(%d+)" or "(.+)"
                i = e + 1
            else
                out[#out + 1] = "%%"
                i = i + ((fmt:sub(i + 1, i + 1) == "%") and 2 or 1)
            end
        else
            if c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then c = "%" .. c end
            out[#out + 1] = c
            i = i + 1
        end
    end
    out[#out + 1] = "$"
    return table.concat(out), order
end

local lootPatterns   -- built on first use: the globals are all loaded by then
local function LootPatterns()
    if lootPatterns then return lootPatterns end
    lootPatterns = {}
    for _, def in ipairs(LOOT_LINES) do
        local pattern, order = ToPattern(_G[def[1]])
        if pattern then
            lootPatterns[#lootPatterns + 1] = { pattern = pattern, order = order, what = def[2],
                                                args = def[3], self = def[4] }
        end
    end
    return lootPatterns
end

local rollLog = {}         -- newest first: { link, at, rolls = { [name] = { choice, roll } }, names = {}, winner }
local logWindow

local function MyName()
    local ok, name = pcall(UnitName, "player")
    return (ok and PlainString(name)) and name or "?"
end

-- A name as chat gives it, maybe a player link: just the name.
local function PlainName(name)
    if not PlainString(name) then return nil end
    name = name:gsub("|Hplayer:[^|]*|h", ""):gsub("|h", ""):gsub("[%[%]]", "")
    name = name:gsub("%-.*$", "")     -- the realm
    return name ~= "" and name or nil
end

local function ItemKey(link)
    return PlainString(link) and (link:match("|Hitem:([%-%d:]+)") or link) or nil
end

-- The open entry for this item: the newest without a winner, from lately.
local function EntryFor(link, make)
    local key = ItemKey(link)
    if not key then return nil end
    local now = GetTime()
    for _, e in ipairs(rollLog) do
        if e.key == key and not e.done and now - e.at < SAME_ROLL then return e end
    end
    if not make then return nil end
    local e = { key = key, link = link, at = now, rolls = {}, names = {} }
    table.insert(rollLog, 1, e)
    while #rollLog > LOG_KEEP do table.remove(rollLog) end
    return e
end

local function Mark(e, name, field, value)
    if not name then return end
    local r = e.rolls[name]
    if not r then
        r = {}
        e.rolls[name] = r
        e.names[#e.names + 1] = name
    end
    r[field] = value
end

-- Everyone in the group, shown as "waiting" until they choose.
local function GroupNames()
    local list = { MyName() }
    local okR, raid = pcall(IsInRaid)
    local prefix, count = "party", 4
    if okR and raid == true then prefix, count = "raid", 40 end
    for i = 1, count do
        local unit = prefix .. i
        local okE, exists = pcall(UnitExists, unit)
        if okE and exists == true then
            local okN, name = pcall(UnitName, unit)
            if okN and PlainString(name) and name ~= list[1] then list[#list + 1] = name end
        end
    end
    return list
end

local RefreshLog

LogRollStart = function(rollID)
    if not GetLootRollItemLink then return end
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if not ok or not PlainString(link) then return end
    local e = EntryFor(link, true)
    for _, name in ipairs(GroupNames()) do
        if not e.rolls[name] then Mark(e, name, "choice", "wait") end
    end
    if settings and settings.logAuto and not (logWindow and logWindow:IsShown()) then ToggleLog(true) end
    RefreshLog()
end

OnLootLine = function(text)
    if not PlainString(text) then return end
    for _, p in ipairs(LootPatterns()) do
        local caps = { text:match(p.pattern) }
        if #caps > 0 then
            local args = {}
            for j, value in ipairs(caps) do args[p.order[j] or j] = value end
            local player, item, number
            for k = 1, #p.args do
                local role = p.args:sub(k, k)
                if role == "p" then player = args[k]
                elseif role == "i" then item = args[k]
                else number = tonumber(args[k]) end
            end
            if p.self then player = MyName() end
            player = PlainName(player)
            local e = EntryFor(item, p.what ~= "won" and p.what ~= "allpass")
            if not e then return end
            if p.what == "won" then
                e.winner, e.done = player, true
            elseif p.what == "allpass" then
                e.done = true
            elseif p.what:sub(1, 4) == "roll" then
                Mark(e, player, "choice", p.what:sub(5))
                Mark(e, player, "roll", number)
            else
                Mark(e, player, "choice", p.what)
            end
            RefreshLog()
            return
        end
    end
end

-- ── The window ──

local CHOICE = {
    need  = { icon = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",  text = "Need",  r = 0.3, g = 1,   b = 0.3, rank = 1 },
    greed = { icon = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",  text = "Greed", r = 1,   g = 0.82, b = 0, rank = 2 },
    de    = { icon = "Interface\\Buttons\\UI-GroupLoot-DE-Up",    text = "Disenchant", r = 0.7, g = 0.5, b = 1, rank = 3 },
    pass  = { icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",  text = "Pass",  r = 0.6, g = 0.6, b = 0.6, rank = 4 },
    wait  = { icon = "Interface\\COMMON\\StreamCircle",           text = "Waiting", r = 0.5, g = 0.5, b = 0.5, rank = 5 },
}

local function ClassColour(name)
    local ok, _, cls = pcall(UnitClass, name)
    if ok and PlainString(cls) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
        local c = RAID_CLASS_COLORS[cls]
        return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) .. name .. "|r"
    end
    return name
end

local logScroll = 0

-- Flat lines: a header per item, then one per player, best choice first.
local function LogLines()
    local lines = {}
    for _, e in ipairs(rollLog) do
        lines[#lines + 1] = { header = true, e = e }
        local names = {}
        for _, n in ipairs(e.names) do names[#names + 1] = n end
        table.sort(names, function(a, b)
            local ra, rb = e.rolls[a], e.rolls[b]
            local ca, cb = CHOICE[ra.choice or "wait"] or CHOICE.wait, CHOICE[rb.choice or "wait"] or CHOICE.wait
            if ca.rank ~= cb.rank then return ca.rank < cb.rank end
            if (ra.roll or -1) ~= (rb.roll or -1) then return (ra.roll or -1) > (rb.roll or -1) end
            return a < b
        end)
        for _, n in ipairs(names) do lines[#lines + 1] = { e = e, name = n } end
    end
    return lines
end

local function MakeLine(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(LINE_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * LINE_H)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * LINE_H)
    row:EnableMouse(true)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -70, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

RefreshLog = function()
    if not (logWindow and logWindow:IsShown()) then return end
    local lines = LogLines()
    local rows = logWindow.rows
    local maxScroll = math.max(0, #lines - #rows)
    if logScroll > maxScroll then logScroll = maxScroll end
    if logScroll < 0 then logScroll = 0 end
    logWindow.empty:SetShown(#lines == 0)
    for i, row in ipairs(rows) do
        local line = lines[i + logScroll]
        row.link = nil
        if not line then
            row:Hide()
        elseif line.header then
            local e = line.e
            local okI, _, _, _, _, _, _, _, _, _, icon = pcall(GetItemInfo, e.link)
            row.icon:SetTexture((okI and icon) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.text:SetText(e.link)
            if e.winner then
                row.right:SetText("|cffffd100" .. T("Won by %s"):format(e.winner) .. "|r")
            elseif e.done then
                row.right:SetText("|cff999999" .. T("Everyone passed") .. "|r")
            else
                row.right:SetText("|cff66ccff" .. T("Rolling") .. "|r")
            end
            row.right:SetWidth(0)
            row.text:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
            row.bg:SetColorTexture(1, 0.82, 0, 0.10)
            row.link = e.link
            row:Show()
        else
            local r = line.e.rolls[line.name] or {}
            local c = CHOICE[r.choice or "wait"] or CHOICE.wait
            row.icon:SetTexture(c.icon)
            row.icon:SetTexCoord(0, 1, 0, 1)
            local name = ClassColour(line.name)
            if line.e.winner == line.name then
                name = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:12:12|t " .. name
            end
            row.text:SetText("    " .. name)
            row.text:SetPoint("RIGHT", -70, 0)
            local choiceText = ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, T(c.text))
            row.right:SetText(r.roll and (choiceText .. "  |cffffffff" .. r.roll .. "|r") or choiceText)
            if line.e.winner == line.name then
                row.bg:SetColorTexture(1, 0.82, 0, 0.18)
            else
                row.bg:SetColorTexture(1, 1, 1, ((i + logScroll) % 2 == 0) and 0.04 or 0)
            end
            row:Show()
        end
    end
end

local function BuildLog()
    local f = CreateFrame("Frame", "OxedHubRollAdvisorLog", UIParent, "BackdropTemplate")
    f:SetSize(LOG_W, LOG_H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        settings.logPoint, settings.logX, settings.logY = point, x, y
    end)
    f:Hide()
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    local ornate = Panel and Panel.ApplyOrnateFrame and pcall(Panel.ApplyOrnateFrame, f, T("Who rolled what"), 0.96)
    if not ornate then
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
        f:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    end
    f:ClearAllPoints()
    f:SetPoint(settings.logPoint or "CENTER", UIParent, settings.logPoint or "CENTER",
               settings.logX or 300, settings.logY or 0)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clear:SetSize(90, 20)
    clear:SetPoint("BOTTOMRIGHT", -12, 10)
    clear:SetText(T("Clear"))
    clear:SetScript("OnClick", function()
        wipe(rollLog)
        RefreshLog()
    end)

    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", 12, -30)
    list:SetPoint("BOTTOMRIGHT", -12, 36)
    f.rows = {}
    local count = math.floor((LOG_H - 66) / LINE_H)
    for i = 1, count do f.rows[i] = MakeLine(list, i) end
    f.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.empty:SetPoint("TOPLEFT", 4, -4)
    f.empty:SetPoint("RIGHT", -4, 0)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetTextColor(0.7, 0.7, 0.7)
    f.empty:SetText(T("No rolls yet. Each Need, Greed or Pass in your group shows here, with the roll and who won."))

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        logScroll = logScroll - delta * 3
        RefreshLog()
    end)
    if OxedHub.HideInPetBattle then pcall(OxedHub.HideInPetBattle, OxedHub, f) end
    if UISpecialFrames then table.insert(UISpecialFrames, "OxedHubRollAdvisorLog") end
    logWindow = f
end

ToggleLog = function(show)
    if not settings then return end
    if not logWindow then BuildLog() end
    if show == nil then show = not logWindow:IsShown() end
    logWindow:SetShown(show)
    if show then
        logScroll = 0
        RefreshLog()
    end
end

HideLog = function()
    if logWindow then logWindow:Hide() end
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
        local w = API:CreateOptionsWindow("Roll Advisor", 440, 440)
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
        w:AddCheckbox(settings, "logAuto", "Open who rolled what when a roll starts")
        w:AddCheckbox(settings, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(settings.enabled == true) end
        end)

        local test = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        test:SetSize(200, 22)
        test:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)
        test:SetText(T("Show a sample"))
        test:SetScript("OnClick", ShowTest)
        local log = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        log:SetSize(180, 22)
        log:SetPoint("LEFT", test, "RIGHT", 6, 0)
        log:SetText(T("Who rolled what"))
        log:SetScript("OnClick", function() ToggleLog(true) end)
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
        hint = T("Click: who rolled what. Right-click: options."),
        onClick = function(mouse)
            if mouse == "RightButton" then ShowOptions() else ToggleLog() end
        end,
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
        version  = "1.1.0",
        added    = 20261113,
        inDevelopment = true,
        updated  = 20261114.2,  -- a window of who rolled what in the group
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
