-- ============================================================================
-- Mix keybinds: a key for a toy mix, straight from the keyboard, without
-- putting the mix on an ActionHub or OxedRing node first.
--
-- Each bound mix gets a hidden secure button. The key is an override binding
-- that clicks it, so it works anywhere a normal key does. Like an ActionHub
-- node, the button rebuilds the mix's macro on every press out of combat (a
-- random mix then picks a toy that is ready), keeps only the protected lines
-- in the macro, and plays the mix's sound, animation, emote and chat beside
-- it, once per press.
--
-- Keys are kept per profile, next to the mixes themselves. Bindings cannot
-- change in combat; a change made then is applied when it ends.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L

local MixKeys = {}
OxedHub.MixKeybinds = MixKeys

local owner = CreateFrame("Frame")   -- holds the override bindings
local buttons = {}                   -- mix name -> its hidden secure button
local made = 0
local pending = false                -- bindings to redo after combat
local window

local function Mixes()
    local profile = OxedHub.db and OxedHub.db.profile
    return profile and profile.toyMixes or {}
end

local function Keys()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return {} end
    if type(profile.mixKeybinds) ~= "table" then profile.mixKeybinds = {} end
    return profile.mixKeybinds
end

-- Only commands that need the secure click stay in the macro; the rest is
-- played by PostClick, or a chat line would be said twice.
local SECURE_COMMANDS = {
    ["/use"] = true, ["/cast"] = true, ["/castrandom"] = true, ["/castsequence"] = true,
    ["/userandom"] = true, ["/cancelaura"] = true, ["/stopcasting"] = true, ["/stopmacro"] = true,
}
local function SecureLines(text)
    local lines = {}
    for line in (text or ""):gmatch("[^\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        local command = trimmed:match("^(/%S+)")
        if trimmed:match("^#") or (command and SECURE_COMMANDS[command:lower()]) then
            lines[#lines + 1] = trimmed
        end
    end
    return table.concat(lines, "\n")
end

local function MacroFor(name)
    local mix = Mixes()[name]
    if type(mix) ~= "table" or not (OxedHub.Toys and OxedHub.Toys.GetMixMacroText) then return "" end
    return SecureLines(OxedHub.Toys:GetMixMacroText(mix, true))
end

local function ButtonFor(name)
    local b = buttons[name]
    if b then return b end
    made = made + 1
    b = CreateFrame("Button", "OxedHubMixKeyButton" .. made, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "macro")
    b:Hide()
    b.mixName = name
    b:SetScript("PreClick", function(self)
        if not InCombatLockdown() then self:SetAttribute("macrotext", MacroFor(self.mixName)) end
    end)
    b:SetScript("PostClick", function(self, _, down)
        -- A key fires the button on press and on release; the game acts on
        -- one of them, and so does this.
        if down ~= GetCVarBool("ActionButtonUseKeyDown") then return end
        local mix = Mixes()[self.mixName]
        if mix and OxedHub.MacroRegistry and OxedHub.MacroRegistry.PlayMixActions then
            OxedHub.MacroRegistry:PlayMixActions(mix)
        end
    end)
    buttons[name] = b
    return b
end

-- Every saved key bound to its mix's button. A mix that no longer exists
-- loses its key.
function MixKeys:Apply()
    if InCombatLockdown() then
        pending = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(owner)
    local keys, mixes = Keys(), Mixes()
    for name, key in pairs(keys) do
        if mixes[name] and type(key) == "string" and key ~= "" then
            local b = ButtonFor(name)
            b.mixName = name
            b:SetAttribute("macrotext", MacroFor(name))
            SetOverrideBindingClick(owner, true, key, b:GetName())
        else
            keys[name] = nil
        end
    end
end

-- One key belongs to one mix: binding it again takes it from the other.
function MixKeys:SetKey(name, key)
    local keys = Keys()
    if key then
        for other, k in pairs(keys) do
            if k == key then keys[other] = nil end
        end
    end
    keys[name] = key
    self:Apply()
end

owner:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pending then
            pending = false
            MixKeys:Apply()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- OxedHub's settings are ready a frame after login.
        C_Timer.After(1, function() MixKeys:Apply() end)
    end
end)
owner:RegisterEvent("PLAYER_ENTERING_WORLD")

-- ── The window ──────────────────────────────────────────────────────────────

local ROW_H, ROWS = 30, 10
local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true }
local listening   -- the row waiting for a key

local function KeyText(key)
    if not key or key == "" then return L["Not Bound"] end
    return GetBindingText and GetBindingText(key) or key
end

-- A key with its modifiers, in the form the binding functions take.
local function FullKey(key)
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    return prefix .. key
end

local function StopListening()
    if not listening then return end
    local row = listening
    listening = nil
    row.key:EnableKeyboard(false)
    row.key:SetScript("OnKeyDown", nil)
end

local function Build()
    local w = CreateFrame("Frame", "OxedHubMixKeybinds", UIParent, "BackdropTemplate")
    w:SetSize(380, 60 + ROWS * ROW_H + 40)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetClampedToScreen(true)
    w:EnableMouse(true)
    w:SetMovable(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)
    w:Hide()
    tinsert(UISpecialFrames, "OxedHubMixKeybinds")

    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    if Panel and Panel.ApplyOrnateFrame then
        Panel.ApplyOrnateFrame(w, L["Mix keybinds"], 0.96)
    else
        w:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        w:SetBackdropColor(0.1, 0.095, 0.085, 0.96)
    end
    local ok, close = pcall(CreateFrame, "Button", nil, w, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
        close:SetScript("OnClick", function() w:Hide() end)
    end

    local hint = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -32)
    hint:SetPoint("TOPRIGHT", w, "TOPRIGHT", -22, -32)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Click a key box, then press the key. Escape cancels, right-click clears."])

    local offset = 0
    local names = {}
    local rows = {}

    local function Draw()
        wipe(names)
        for name in pairs(Mixes()) do names[#names + 1] = name end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        offset = math.max(0, math.min(offset, #names - ROWS))
        local keys = Keys()
        for i = 1, ROWS do
            local row, name = rows[i], names[i + offset]
            if name then
                row.mixName = name
                row.icon:SetTexture(OxedHub.Toys and OxedHub.Toys.GetMixIcon and OxedHub.Toys:GetMixIcon(name) or 134400)
                row.name:SetText(name)
                row.key:SetText(listening == row and L["Press a key..."] or KeyText(keys[name]))
                row:Show()
            else
                row:Hide()
            end
        end
        w.empty:SetShown(#names == 0)
    end
    w.Draw = Draw

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, w)
        row:SetSize(w:GetWidth() - 44, ROW_H - 4)
        row:SetPoint("TOPLEFT", w, "TOPLEFT", 22, -52 - (i - 1) * ROW_H)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -140, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.key = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.key:SetSize(130, 22)
        row.key:SetPoint("RIGHT")
        row.key:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.key:SetScript("OnClick", function(_, mouse)
            if InCombatLockdown() then
                print("|cff00ccffOxedHub|r " .. L["keys can be changed after the fight."])
                return
            end
            if mouse == "RightButton" then
                StopListening()
                MixKeys:SetKey(row.mixName, nil)
                Draw()
                return
            end
            StopListening()
            listening = row
            row.key:EnableKeyboard(true)
            row.key:SetPropagateKeyboardInput(false)
            row.key:SetScript("OnKeyDown", function(_, key)
                if MODIFIERS[key] then return end
                local name = row.mixName
                StopListening()
                if key ~= "ESCAPE" then MixKeys:SetKey(name, FullKey(key)) end
                Draw()
            end)
            Draw()
        end)
        rows[i] = row
    end

    w.empty = w:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    w.empty:SetPoint("CENTER")
    w.empty:SetText(L["No mixes yet. Make one in the Mixer first."])

    w:EnableMouseWheel(true)
    w:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        Draw()
    end)
    w:SetScript("OnShow", Draw)
    w:SetScript("OnHide", function()
        StopListening()
    end)
    return w
end

function MixKeys:Toggle()
    window = window or Build()
    window:SetShown(not window:IsShown())
end

SLASH_OXEDMIXKEYS1 = "/oxmixkeys"
SlashCmdList.OXEDMIXKEYS = function() MixKeys:Toggle() end
