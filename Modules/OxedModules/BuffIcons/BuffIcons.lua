-- ============================================================================
-- Buff Tracker (built-in OxedHub module)
-- An icon on screen while a chosen buff is on you -- Power Infusion, a
-- healer's cooldown, a trinket proc -- that also works in a fight.
--
-- ⚠ In a fight the game hides your buffs from addons: no addon can tell that
-- Power Infusion just landed on you, so nothing can play a sound for it.
-- What the game does allow (12.1) is its own aura container: an addon says
-- which spell ids to watch, and the game itself shows and hides the icon and
-- runs its timer. That is what this module builds, one container per buff.
--
-- The container's buttons are only ever set up inside initializeFrame and
-- never touched afterwards: once the game owns them they are forbidden.
-- Containers can only be made out of combat, so changes made in a fight wait
-- for it to end.
-- ============================================================================

local addonName, OxedHub = ...

local DEFAULTS = {
    enabled  = false,   -- off until the player switches it on
    size     = 48,
    spacing  = 6,
    vertical = false,
    glow     = true,
    border   = true,
    scale    = 1,
    locked   = false,
}

local DEFAULT_SPELLS = { 10060 }   -- Power Infusion

local settings
local optionsWindow
local anchor
local entries = {}       -- one { host, container } per buff
local rebuildPending = false
local supported          -- nil until asked, then true / false
local whyNot = "not checked yet"  -- why the container is not available, shown in Options
local eventFrame = CreateFrame("Frame")
local PickedIDs, SyncSpells   -- defined below Build, used by it

local function OptionsOpen()
    return optionsWindow and optionsWindow:IsShown() or false
end

-- Whether this client offers the game's aura container to addons.
local function Supported()
    if supported ~= nil then return supported end
    local _, _, _, build = GetBuildInfo()
    if type(build) ~= "number" or build < 120100 then
        supported = false
        whyNot = ("this game version (%s) does not have it yet; it comes with 12.1"):format(tostring(build))
        return false
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        local okLoad, loaded, reason = pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
        if okLoad and not loaded and reason then whyNot = "the game's aura container did not load: " .. tostring(reason) end
    end
    if InCombatLockdown() then whyNot = "waiting for the fight to end"; return false end
    local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    supported = ok and probe and type(probe.AddAuraGroup) == "function" or false
    if not ok then whyNot = "the game refused the container: " .. tostring(probe)
    elseif not supported then whyNot = "the container has no aura groups in this game version" end
    if ok and probe then
        if probe.SetEnabled then pcall(probe.SetEnabled, probe, false) end
        probe:Hide()
    end
    return supported
end

-- ── Frames ─────────────────────────────────────────────────────────────────

local function CreateAnchor()
    if anchor then return end
    anchor = CreateFrame("Frame", "OxedHubBuffIconsAnchor", UIParent)
    anchor:SetPoint(settings.point or "CENTER", UIParent, settings.rel or "CENTER", settings.x or 0, settings.y or -60)
    anchor:SetClampedToScreen(true)
    anchor:SetMovable(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        settings.point, settings.rel, settings.x, settings.y = point, rel, x, y
    end)
    anchor.hint = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.hint:SetAllPoints()
    anchor.hint:SetColorTexture(0, 0.6, 1, 0.25)
    anchor.text = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchor.text:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    anchor.text:SetText("Buff Tracker: drag me")
end

local function ShowHint()
    if not anchor then return end
    local count = math.max(1, #settings.spells)
    local long = count * settings.size + (count - 1) * settings.spacing
    if settings.vertical then anchor:SetSize(settings.size, long) else anchor:SetSize(long, settings.size) end
    anchor:SetScale(settings.scale)
    local editing = settings.enabled and not settings.locked and OptionsOpen()
    anchor.hint:SetShown(editing)
    anchor.text:SetShown(editing)
    anchor:EnableMouse(editing)
end

-- Sets up one of the game's buttons, the only time it may be touched.
local buttonsMade = 0     -- how many buttons the game asked us to set up
local function InitializeButton(button, spellID)
    buttonsMade = buttonsMade + 1
    local size = settings.size
    if button.SetSize then pcall(button.SetSize, button, size, size) end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    -- Our own icon from the spell id: the aura's own is hidden from us.
    icon:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetPoint("TOPLEFT", 2, -2)
    cooldown:SetPoint("BOTTOMRIGHT", -2, 2)
    cooldown:SetDrawEdge(false)
    cooldown:SetReverse(true)
    if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(false) end
    -- The game runs the timer from the aura itself.
    if button.SetDurationCooldown then pcall(button.SetDurationCooldown, button, cooldown) end

    if settings.border then
        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints()
        border:SetColorTexture(0, 0, 0, 1)
    end
    if settings.glow then
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
    end
    if button.SetMouseClickEnabled then pcall(button.SetMouseClickEnabled, button, false) end
    if button.SetMouseMotionEnabled then pcall(button.SetMouseMotionEnabled, button, false) end
end

local function Destroy()
    for _, entry in ipairs(entries) do
        if entry.container.SetEnabled then pcall(entry.container.SetEnabled, entry.container, false) end
        pcall(entry.container.Hide, entry.container)
        entry.host:Hide()
    end
    wipe(entries)
end

local function Build()
    if InCombatLockdown() then rebuildPending = true; return end
    rebuildPending = false
    Destroy()
    CreateAnchor()
    ShowHint()
    if not (settings.enabled and Supported()) then return end

    local size, step = settings.size, settings.size + settings.spacing
    for index, spellID in ipairs(settings.spells) do
        local host = CreateFrame("Frame", nil, anchor)
        host:SetSize(size, size)
        if settings.vertical then
            host:SetPoint("TOP", anchor, "TOP", 0, -(index - 1) * step)
        else
            host:SetPoint("LEFT", anchor, "LEFT", (index - 1) * step, 0)
        end
        host:EnableMouse(false)

        local ok, container = pcall(CreateFrame, "AuraContainer", nil, host, "CustomAuraContainerTemplate")
        if ok and container then
            container:SetPoint("TOPLEFT")
            container:SetSize(size, size)
            container:Show()
            -- The layout runs only once it knows where to start and how wide a
            -- line is; without it the button is never placed.
            if container.SetFlowLayoutAnchorPoint then
                pcall(container.SetFlowLayoutAnchorPoint, container, "TOPLEFT")
            elseif container.SetAuraLayoutAnchorPoint then
                pcall(container.SetAuraLayoutAnchorPoint, container, "TOPLEFT")
            end
            if AnchorUtil and AnchorUtil.FlowDirection and container.SetFlowLayoutGrowthDirection then
                pcall(container.SetFlowLayoutGrowthDirection, container,
                    AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
            end
            if container.SetFlowLayoutMaximumLineSize then
                pcall(container.SetFlowLayoutMaximumLineSize, container, size)
            elseif container.SetAuraLayoutRowWidth then
                pcall(container.SetAuraLayoutRowWidth, container, size)
            end
            local ids = { [spellID] = true }
            -- The cast and the buff can have different ids; ask the game.
            if C_UnitAuras and C_UnitAuras.GetCooldownAuraBySpellID then
                local okA, auraID = pcall(C_UnitAuras.GetCooldownAuraBySpellID, spellID)
                if okA and type(auraID) == "number" and not (issecretvalue and issecretvalue(auraID)) and auraID > 0 then
                    ids[auraID] = true
                end
            end
            local okGroup = pcall(container.AddAuraGroup, container, "oxedhub", "HELPFUL", {
                maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = ids },
                initializeFrame = function(button) InitializeButton(button, spellID) end,
                layout = {
                    elementSpacing = 0, lineSpacing = 0, groupSpacing = 0, groupLineSpacing = 0,
                    forceNewLine = false, elementWidth = size, elementHeight = size, layoutIndex = 1,
                },
            })
            if not okGroup then whyNot = "the game refused the buff filter" end
            if okGroup and container.SetUnit then
                pcall(container.SetUnit, container, "player")
                -- A container starts switched off: nothing shows until it runs.
                if container.SetEnabled then pcall(container.SetEnabled, container, true) end
                if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
                -- The layout can shrink the container to nothing; keep it the
                -- icon's size and let its buttons draw outside it.
                pcall(container.SetSize, container, size, size)
                if container.SetClipsChildren then pcall(container.SetClipsChildren, container, false) end
                entries[#entries + 1] = { host = host, container = container }
            else
                host:Hide()
            end
        else
            host:Hide()
        end
    end
end

eventFrame:SetScript("OnEvent", function()
    if rebuildPending and not InCombatLockdown() then Build() end
end)

-- ── Options ─────────────────────────────────────────────────────────────────

-- The buffs chosen in the search, as numbers: the first pick and the rest.
PickedIDs = function()
    local ids, seen = {}, {}
    local pick = settings.pick or {}
    local function Add(v)
        local id = tonumber(v)
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    Add(pick.spellID)
    for _, v in ipairs(pick.extraSpellIDs or {}) do Add(v) end
    return ids
end

SyncSpells = function()
    settings.spells = PickedIDs()
end

local function Status()
    if not settings.enabled then return "|cffaaaaaaSwitched off.|r" end
    if #entries > 0 then
        local e = entries[1].container
        local okS, shown = pcall(e.IsShown, e)
        local okV, visible = pcall(e.IsVisible, e)
        local okW, w, h = pcall(e.GetSize, e)
        local okC, children = pcall(e.GetNumChildren, e)
        return ("|cff40ff40Working: watching %d buff(s).|r |cffaaaaaa(buttons made %d, shown %s, visible %s, size %s x %s, children %s)|r"):format(
            #entries, buttonsMade, tostring(okS and shown), tostring(okV and visible),
            tostring(okW and w), tostring(okW and h), tostring(okC and children))
    end
    return "|cffff6060Not working: " .. whyNot .. ".|r"
end

local function SpellList()
    local names = {}
    for _, id in ipairs(settings.spells) do
        names[#names + 1] = ("%s (%d)"):format(C_Spell.GetSpellName(id) or "?", id)
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Buff Tracker", 500, 580)
        optionsWindow = w
        w:HookScript("OnShow", ShowHint)
        w:HookScript("OnHide", ShowHint)

        -- The same spell search the triggers use: pick from suggestions, see
        -- each chosen buff as an icon, click one to remove it. It writes to
        -- settings.pick, shaped like a trigger's conditions.
        local pickFrame = CreateFrame("Frame", nil, w)
        pickFrame:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 4)
        pickFrame:SetSize(420, 120)
        local used = 120
        if OxedHub.Triggers and OxedHub.Triggers.CreateAuraSpellSearchUI then
            local mock = { id = "BuffIcons", event = "SELF_AURA", conditions = settings.pick }
            local ok, endY = pcall(OxedHub.Triggers.CreateAuraSpellSearchUI, OxedHub.Triggers, pickFrame, mock, 0)
            if ok and type(endY) == "number" then used = math.max(60, -endY + 10) end
        end
        pickFrame:SetHeight(used)
        w.cursorY = w.cursorY - used - 6

        local status = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY)
        status:SetWidth(420)
        status:SetJustifyH("LEFT")
        w.cursorY = w.cursorY - 34

        -- The search writes straight to settings.pick; notice a change and
        -- rebuild the icons from it.
        local lastKey
        local elapsed = 0
        w:HookScript("OnShow", function() lastKey = nil end)
        w:HookScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.5 then return end
            elapsed = 0
            local key = table.concat(PickedIDs(), ",")
            if key ~= lastKey then
                lastKey = key
                SyncSpells()
                Build()
            end
            status:SetText(Status())
        end)

        w:AddCheckbox(settings, "locked", "Lock", "Unlocked, drag the blue box while this window is open.", ShowHint)
        w:AddCheckbox(settings, "vertical", "Stack downwards", nil, Build)
        w:AddCheckbox(settings, "glow", "Glow", nil, Build)
        w:AddCheckbox(settings, "border", "Black border", nil, Build)
        w:AddSlider(settings, "size", "Icon size", 24, 128, 2, "%s: %d", Build)
        w:AddSlider(settings, "spacing", "Space between", 0, 30, 1, "%s: %d", Build)
        w:AddSlider(settings, "scale", "Scale", 0.5, 2, 0.05, "%s: %.2f", ShowHint)
        w:AddNote("The game itself shows each icon while the buff is on you, also in a fight. "
            .. "It cannot play a sound: the game hides your buffs from addons in combat. "
            .. "Changes made in a fight apply when it ends.")
    end
    optionsWindow:Show()
end

-- ── Settings and registration ──────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.bufficons
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.bufficons = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    -- A list, so built here rather than in DEFAULTS.
    if type(config.spells) ~= "table" then
        config.spells = {}
        for _, id in ipairs(DEFAULT_SPELLS) do config.spells[#config.spells + 1] = id end
    end
    if type(config.pick) ~= "table" then
        config.pick = { spellID = "", extraSpellIDs = {}, allClasses = true }
        for index, id in ipairs(config.spells) do
            if index == 1 then config.pick.spellID = tostring(id)
            else table.insert(config.pick.extraSpellIDs, tostring(id)) end
        end
    end
    if type(config.pick.extraSpellIDs) ~= "table" then config.pick.extraSpellIDs = {} end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "bufficons",
        name     = "Buff Tracker",
        version  = "1.0.0",
        author   = "Oxed",
        category = "combat",
        keywords = { "buff", "tracker", "track", "power infusion", "icon", "aura", "proc", "cooldown" },
        desc     = "Track any buff on you with a big icon and timer, also in a fight.",
        icon     = "Interface\\Icons\\Spell_Holy_WordFortitude",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            Build()
        end,
        OnDisable = function()
            eventFrame:UnregisterAllEvents()
            Destroy()
            if anchor then anchor.hint:Hide(); anchor.text:Hide(); anchor:EnableMouse(false) end
        end,
    })
end)
