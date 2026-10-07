local addonName, OxedHub = ...
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────────
-- POWER_INFUSION trigger — one icon on screen while Power Infusion is on you.
--
-- ⚠ In a fight the game hides your buffs from addons: no addon can tell that a
-- priest just gave you Power Infusion, so this trigger has no sound and no
-- animation. What the game allows (12.1) is its own aura container: we tell it
-- the spell id, and the game itself shows the icon and runs its timer, also in
-- combat. The container can only be built out of combat; a change made in a
-- fight is applied when it ends. Its button may only be set up inside
-- initializeFrame and never touched again.
-- ─────────────────────────────────────────────────────────────────────────────

local PI = 10060
local DEFAULT_SIZE = 64

local holder            -- our frame: position, size, drag box
local container         -- the game's container
local builtFor          -- the size the container was built with
local pending = false
local moving = false

-- The first enabled Power Infusion trigger, or nil.
local function ActiveTrigger()
    local profile = OxedHub.db and OxedHub.db.profile
    for _, trigger in pairs(profile and profile.triggers or {}) do
        if type(trigger) == "table" and trigger.enabled and trigger.event == "POWER_INFUSION" then
            return trigger
        end
    end
    return nil
end

local function Conditions(trigger)
    trigger.conditions = trigger.conditions or {}
    return trigger.conditions
end

local function BuildHolder()
    if holder then return end
    holder = CreateFrame("Frame", "OxedHubPowerInfusionIcon", UIParent)
    holder:SetClampedToScreen(true)
    holder:SetMovable(true)
    holder:RegisterForDrag("LeftButton")
    holder:SetScript("OnDragStart", function(self) if moving then self:StartMoving() end end)
    holder:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local trigger = ActiveTrigger()
        if trigger then
            local c = Conditions(trigger)
            local point, _, rel, x, y = self:GetPoint()
            c.piPoint, c.piRel, c.piX, c.piY = point, rel, x, y
        end
    end)
    holder.hint = holder:CreateTexture(nil, "BACKGROUND")
    holder.hint:SetAllPoints()
    holder.hint:SetColorTexture(0, 0.6, 1, 0.3)
    holder.hint:Hide()
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.text:SetPoint("BOTTOM", holder, "TOP", 0, 2)
    holder.text:SetText("Power Infusion: drag me")
    holder.text:Hide()
end

local function InitializeButton(button, size)
    if button.SetSize then pcall(button.SetSize, button, size, size) end
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(C_Spell.GetSpellTexture(PI) or 135939)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", 2, -2)
    cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    cooldown:SetDrawEdge(false)
    cooldown:SetReverse(true)
    if button.SetDurationCooldown then pcall(button.SetDurationCooldown, button, cooldown) end
    local glow = button:CreateTexture(nil, "OVERLAY")
    glow:SetPoint("CENTER")
    glow:SetSize(size * 1.6, size * 1.6)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.35)
    fade:SetToAlpha(1)
    fade:SetDuration(0.5)
    pulse:Play()
    if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
end

local function DropContainer()
    if container then
        if container.SetEnabled then pcall(container.SetEnabled, container, false) end
        pcall(container.Hide, container)
        container = nil
    end
    builtFor = nil
end

-- Builds, moves or removes the icon to match the triggers. Out of combat only.
local function Refresh()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local trigger = ActiveTrigger()
    if not trigger then
        DropContainer()
        if holder then holder:Hide() end
        return
    end
    BuildHolder()
    local c = Conditions(trigger)
    local size = tonumber(c.piSize) or DEFAULT_SIZE
    holder:ClearAllPoints()
    holder:SetPoint(c.piPoint or "CENTER", UIParent, c.piRel or "CENTER", c.piX or 0, c.piY or 120)
    holder:SetSize(size, size)
    holder:Show()
    holder.hint:SetShown(moving)
    holder.text:SetShown(moving)
    holder:EnableMouse(moving)

    if container and builtFor == size then return end
    DropContainer()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ok, made = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not ok or not made or type(made.AddAuraGroup) ~= "function" then return end
    made:SetPoint("TOPLEFT")
    made:SetSize(size, size)
    made:Show()
    if made.SetFlowLayoutAnchorPoint then pcall(made.SetFlowLayoutAnchorPoint, made, "TOPLEFT") end
    if AnchorUtil and AnchorUtil.FlowDirection and made.SetFlowLayoutGrowthDirection then
        pcall(made.SetFlowLayoutGrowthDirection, made, AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    end
    if made.SetFlowLayoutMaximumLineSize then pcall(made.SetFlowLayoutMaximumLineSize, made, size) end
    local okGroup = pcall(made.AddAuraGroup, made, "oxedhubpi", "HELPFUL", {
        maxFrameCount = 1,
        candidateFilters = { includeSpellIDs = { [PI] = true } },
        initializeFrame = function(button) InitializeButton(button, size) end,
        layout = {
            elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0,
            forceNewLine = false, elementWidth = size, elementHeight = size, layoutIndex = 1,
        },
    })
    if not okGroup or not made.SetUnit then
        pcall(made.Hide, made)
        return
    end
    pcall(made.SetUnit, made, "player")
    if made.SetEnabled then pcall(made.SetEnabled, made, true) end
    if made.UpdateAllAuras then pcall(made.UpdateAllAuras, made) end
    container, builtFor = made, size
end

-- Triggers are added, switched and deleted in the editor: look again now and
-- then, and after every fight. Cheap: it only rebuilds when something changed.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" and not pending then
        -- Nothing waiting; still a good moment to catch editor changes.
    end
    Refresh()
end)
C_Timer.NewTicker(3, function()
    if not InCombatLockdown() then
        local wanted = ActiveTrigger() ~= nil
        if wanted ~= (container ~= nil) or (holder and holder:IsShown() ~= wanted) then Refresh() end
    end
end)

Triggers:RegisterEventType("POWER_INFUSION", {
    name = "Power Infusion",
    -- Nothing to fire: the game shows the icon itself.
    CheckCondition = function() return false end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local c = Conditions(trigger)
        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        info:SetWidth(560)
        info:SetJustifyH("LEFT")
        info:SetText("One icon on screen while a priest's Power Infusion is on you, with its timer.\n"
            .. "The game draws it, so it also works in a fight. No sound: the game hides your\n"
            .. "buffs from addons in combat.")
        yOffset = yOffset - 52

        local move = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        move:SetSize(150, 22)
        move:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        move:SetText("Move the icon")
        move:SetScript("OnClick", function(self)
            moving = not moving
            self:SetText(moving and "Done moving" or "Move the icon")
            Refresh()
        end)
        frame:HookScript("OnHide", function()
            if moving then moving = false; Refresh() end
        end)

        local sizeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sizeLabel:SetPoint("LEFT", move, "RIGHT", 20, 0)
        local function ShowSize() sizeLabel:SetText(("Size: %d"):format(tonumber(c.piSize) or DEFAULT_SIZE)) end
        ShowSize()
        local function Step(delta)
            c.piSize = math.max(24, math.min(160, (tonumber(c.piSize) or DEFAULT_SIZE) + delta))
            ShowSize()
            Refresh()
        end
        local smaller = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        smaller:SetSize(28, 22)
        smaller:SetPoint("LEFT", sizeLabel, "RIGHT", 10, 0)
        smaller:SetText("-")
        smaller:SetScript("OnClick", function() Step(-8) end)
        local bigger = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        bigger:SetSize(28, 22)
        bigger:SetPoint("LEFT", smaller, "RIGHT", 4, 0)
        bigger:SetText("+")
        bigger:SetScript("OnClick", function() Step(8) end)

        Refresh()
        return yOffset - 30
    end,
})
