-- ============================================================================
-- Layer Swap, part 5 of 5: registration, options, minimap button, commands
-- (built-in OxedHub module, WoW Forever only; see LayerSwapCore.lua)
-- ============================================================================

local _, OxedHub = ...
local LS = OxedHub.LayerSwap
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

-- Key bindings: names at file scope, so a disabled module keeps its keys named.
BINDING_NAME_OXEDHUB_LAYERSWAP_SWAP = "Layer Swap: swap layer"
BINDING_NAME_OXEDHUB_LAYERSWAP_WINDOW = "Layer Swap: open the window"
BINDING_NAME_OXEDHUB_LAYERSWAP_INVITE = "Layer Swap: invite the next request"
if GetLocale and GetLocale() == "ruRU" then
    BINDING_NAME_OXEDHUB_LAYERSWAP_SWAP = "Смена слоя: сменить слой"
    BINDING_NAME_OXEDHUB_LAYERSWAP_WINDOW = "Смена слоя: открыть окно"
    BINDING_NAME_OXEDHUB_LAYERSWAP_INVITE = "Смена слоя: пригласить следующего"
end

function OxedHub_LayerSwapSwap()
    if LS.running then LS.StartSwap() end
end
function OxedHub_LayerSwapWindow()
    if LS.ToggleWindow then LS.ToggleWindow() end
end
function OxedHub_LayerSwapInvite()
    if LS.running and not LS.InviteNext() then LS.Say(LS.T("No request is waiting.")) end
end

local DEFAULTS = {
    enabled       = false,   -- off until the player switches it on
    minimapButton = true,
    -- the portal
    showPortal = true, lockPortal = false, portalSize = 64, portalText = true, flashPlates = true,
    screenFlash = true, sound = true, soundId = "", hostGlow = true,
    names = "shared",        -- "shared" (W2), "letters" (A, B, C), "number"
    chat = true, layerChat = false,
    -- swaps
    onlyNew = true, autoAccept = true, autoLeave = true, avoidGuild = false,
    -- hosting
    host = true, hostOffAtLogin = false, askFirst = false, hostGuildOnly = false, hostNotAfk = true,
    skipNear = true, nearYards = 150,
    -- guild and chat
    shareGuild = true, chatWatch = true,
    debug = false,
    -- book, asked, moves, hops, seen, hist, letters are tables made after
    -- binding: a table here would be shared by every character.
}

local optionsWindow, swapWindow, minimapIcon

local function MinimapIcon()
    if minimapIcon or not LS.settings then return minimapIcon end
    local API = OxedHub.ModuleAPI
    minimapIcon = API and API.MinimapButton and API:MinimapButton({
        key = "layerswap", label = LS.T("Layer Swap"), icon = LS.ICON, config = LS.settings,
        hint = LS.T("Click: the window. Right-click: options."),
        onClick = function(mouse)
            if mouse == "RightButton" then LS.ShowOptions() else LS.ToggleWindow() end
        end,
    })
    return minimapIcon
end

local function ShowSwapOptions()
    local API = OxedHub.ModuleAPI
    local s = LS.settings
    if not API or not s then return end
    if not swapWindow then
        local w = API:CreateOptionsWindow("Layer Swap: swaps and hosting", 460, 640)
        swapWindow = w
        w:AddNote("Asking for a swap")
        w:AddCheckbox(s, "onlyNew", "Only new layers",
            "A swap skips the layers you stood on in this zone in the last hour.")
        w:AddCheckbox(s, "autoAccept", "Accept the host's invite",
            "Accept the invite of a player you asked, without a click.")
        w:AddCheckbox(s, "autoLeave", "Leave the host's group after the move",
            "The new layer stays. The host is free for the next player.")
        w:AddCheckbox(s, "avoidGuild", "Avoid guildmates' layers",
            "A swap never takes you to a layer a guildmate with Layer Swap stands on.")
        w:AddNote("Hosting: inviting players who ask for your layer")
        w:AddCheckbox(s, "host", "Host other players", "Players on other layers who ask are invited to your group.",
            function() LS.SendGuildState(true) LS.Changed() end)
        w:AddCheckbox(s, "hostOffAtLogin", "Start every login with hosting off",
            "Stealth: hosting stays off until you switch it on.")
        w:AddCheckbox(s, "askFirst", "Ask me before inviting",
            "A card shows each request with Invite and Decline.")
        w:AddCheckbox(s, "hostGuildOnly", "Host guildmates only")
        w:AddCheckbox(s, "hostNotAfk", "Not while I am away")
        w:AddCheckbox(s, "skipNear", "Skip players asking from near you",
            "They are probably farming the same spot.")
        w:AddSlider(s, "nearYards", "Near means within", 50, 200, 10, "%s: %d yards")
        w:AddNote("Guild and chat")
        w:AddCheckbox(s, "shareGuild", "Share my layer with my guild",
            "Guildmates with Layer Swap see your layer and can find you.",
            function() LS.SendGuildState(true) end)
        w:AddCheckbox(s, "chatWatch", "Collect layer offers from chat", "Shown on the Chat tab, with a Whisper button.")
        w:AddNote("Hosting stops by itself in combat, in instances and in another player's group, and never sends more than 6 invites in 10 minutes. The game allows about 10 layer changes an hour.")
    end
    swapWindow:Show()
end

function LS.ShowOptions()
    local API = OxedHub.ModuleAPI
    local s = LS.settings
    if not API or not s then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Layer Swap", 460, 630)
        optionsWindow = w
        w:AddCheckbox(s, "showPortal", "Show the portal on screen",
            "Click it to swap, right-click to pick a layer, Shift-click for the window.",
            function()
                LS.ApplyPortal(s.enabled == true)
                if s.showPortal and s.enabled ~= true then
                    LS.Say(OxedHub.T("The portal appears once Layer Swap is switched on in the Modules page."))
                end
            end)
        w:AddCheckbox(s, "lockPortal", "Lock the portal in place")
        w:AddSlider(s, "portalSize", "Portal size", 40, 120, 4, "%s: %d", function() if LS.ApplyPortalLayout then LS.ApplyPortalLayout() end end)
        w:AddCheckbox(s, "portalText", "Layer name under the portal", nil,
            function() if LS.ApplyPortalLayout then LS.ApplyPortalLayout() end end)
        w:AddCheckbox(s, "flashPlates", "Show nameplates for a moment to read the layer", "When you click the portal and your layer is unknown, nameplates are switched on once for 3 seconds, then put back as they were.")
        w:AddCheckbox(s, "hostGlow", "Golden halo while hosting", nil, function() LS.Changed() end)
        w:AddCheckbox(s, "screenFlash", "Flash the screen when the layer changes")
        w:AddCheckbox(s, "sound", "Sound when the layer changes")
        w:AddSoundPicker(s, "soundId", "Layer change sound", "Map ping")
        w:AddChoice(s, "names", "Layer names", {
            { value = "shared",  text = "W2 style (same for everyone)" },
            { value = "letters", text = "A, B, C (in the order seen)" },
            { value = "number",  text = "Server number" },
        }, function() LS.Changed() end)
        w:AddCheckbox(s, "chat", "Messages in chat")
        w:AddCheckbox(s, "layerChat", "Say in chat when the layer changes by itself")
        w:AddCheckbox(s, "minimapButton", "Show minimap button", nil, function()
            local icon = MinimapIcon()
            if icon then icon:Apply(s.enabled == true) end
        end)
        local more = CreateFrame("Button", nil, w, "UIPanelButtonTemplate")
        more:SetSize(220, 24)
        more:SetPoint("TOPLEFT", w, "TOPLEFT", 20, w.cursorY - 6)
        more:SetText(LS.T("Swaps and hosting..."))
        more:SetScript("OnClick", ShowSwapOptions)
        w.cursorY = w.cursorY - 36
        w:AddNote("/oxlayer opens the window. /oxlayer swap, /oxlayer swap W2, /oxlayer guild, /oxlayer stop, /oxlayer host, /oxlayer status. Key bindings are under Oxed Hub.")
    end
    optionsWindow:Show()
end

-- ── Commands ────────────────────────────────────────────────────────────────

local function Status()
    local id, zone = LS.MyLayer(), LS.Zone()
    LS.Say((LS.T("You are on %s in %s.")):format(id and (LS.ColorCode(id) .. LS.LayerName(id, zone) .. "|r (" .. id .. ")") or LS.T("an unknown layer"), LS.ZoneName(zone)))
    local left, resetIn = LS.MovesLeft()
    LS.Say((LS.T("Layer changes left this hour: %d (%s until one comes back).")):format(left, LS.Clock(resetIn)))
    if LS.OtherHost() then
        LS.Say((LS.T("%s hosts for you, so Layer Swap only asks.")):format(LS.OtherHost()))
    else
        LS.Say((LS.T("Hosting: %s. Invites left: %d of 6.")):format(LS.Hosting() and LS.T("on") or LS.T("off"), LS.HostInvitesLeft()))
    end
    local _, rank = LS.Rank()
    LS.Say((LS.T("Host rank: %s, %d players brought across. Known hosts: %d.")):format(LS.T(rank.name), LS.Hops().total or 0, LS.KnownHostCount()))
    local st = LS.SwapStatus()
    if st then LS.Say(st) end
    LS.Say(("Debug: zone %s, last creature %s, skipped %s."):format(tostring(zone), tostring(LS.lastGuid or "none"), tostring(LS.lastSkip or "nothing")))
end

SLASH_OXEDHUBLAYERSWAP1 = "/oxlayer"
SLASH_OXEDHUBLAYERSWAP2 = "/oxlayers"
SlashCmdList.OXEDHUBLAYERSWAP = function(msg)
    msg = strtrim(msg or "")
    local lower = strlower(msg)
    if not LS.running and lower ~= "" then
        LS.Say(LS.T("Switch Layer Swap on in the Modules page first."))
        return
    end
    if lower == "" then
        LS.ToggleWindow()
    elseif lower == "swap" then
        LS.StartSwap()
    elseif lower:match("^swap%s+%S+$") then
        local want = msg:match("^%S+%s+(%S+)$"):upper()
        local zone = LS.Zone()
        for _, l in ipairs(LS.SeenLayers(zone)) do
            if LS.LayerName(l.id, zone):upper() == want or l.server == want or l.id == want then
                LS.StartSwap(l.id)
                return
            end
        end
        LS.Say((LS.T("No layer %s seen in this zone. The window lists the ones you can ask for.")):format(want))
    elseif lower == "guild" then
        LS.StartSwap(nil, true)
    elseif lower == "stop" then
        LS.StopSwap()
    elseif lower == "host" or lower == "on" or lower == "off" then
        if lower == "host" then LS.settings.host = not LS.settings.host else LS.settings.host = (lower == "on") end
        LS.SendGuildState(true)
        LS.Changed()
        LS.Say(LS.Hosting() and LS.T("Hosting is on.") or LS.T("Hosting is off."))
    elseif lower == "kick" then
        LS.KickGuests()
    elseif lower == "portal" then
        LS.settings.showPortal = not LS.settings.showPortal
        LS.ApplyPortal(true)
    elseif lower == "reset" then
        LS.settings.portalPoint, LS.settings.portalRel, LS.settings.portalX, LS.settings.portalY = nil, nil, nil, nil
        LS.ApplyPortal(true)
        LS.Say(LS.T("The portal is back in the middle of the screen."))
    elseif lower == "status" then
        Status()
    elseif lower == "options" then
        LS.ShowOptions()
    else
        LS.Say("/oxlayer, /oxlayer swap, /oxlayer swap <layer>, /oxlayer guild, /oxlayer stop, /oxlayer host, /oxlayer kick, /oxlayer portal, /oxlayer reset, /oxlayer status")
    end
end

-- ── Start and stop ──────────────────────────────────────────────────────────

local function Tables(s)
    for _, key in ipairs({ "book", "asked", "moves", "seen", "hist", "letters" }) do
        if type(s[key]) ~= "table" then s[key] = {} end
    end
    if type(s.hops) ~= "table" then s.hops = { total = 0, day = "", names = {} } end
end

local function Start()
    -- The portal first: if a later step fails, the player still sees it.
    -- Each step on its own, so one error does not leave the module half on
    -- with LS.running stuck at true.
    local steps = { LS.ApplyPortal, LS.ResetReading, LS.StartSwapping, LS.StartGuild, LS.StartEvents }
    if not LS.running then
        LS.running = true
        for _, step in ipairs(steps) do
            local ok, err = pcall(step, true)
            if not ok then LS.Say("|cffff6060" .. tostring(err) .. "|r") end
        end
        C_Timer.After(1, function() pcall(LS.Scan) end)
    else
        pcall(LS.ApplyPortal, true)
    end
    pcall(LS.Changed)
end

local function Stop()
    LS.StopSwapping()
    LS.StopGuild()
    pcall(LS.PlatesBack)
    LS.running = false
    LS.StopEvents()
    LS.HideAll()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Layers in this form exist on WoW Forever only.
    if OxedHub.IsMainline then return end
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.layerswap
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.layerswap = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    Tables(config)
    if config.hostOffAtLogin then config.host = false end
    LS.settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "layerswap",
        name     = "Layer Swap",
        version  = "1.1.2",
        added    = 20261120,
        updated  = 20261120.7,
        author   = "Oxed",
        category = "quests",
        keywords = { "layer", "layers", "swap", "shard", "phase", "host", "portal", "layerswap", "hop" },
        desc     = "Shows your layer as a portal on screen. Click it to swap layers. Hosts other players.",
        icon     = LS.ICON,
        defaults = DEFAULTS,
        OnOptionsShow = function() LS.ShowOptions() end,
        OnEnable = function(_, cfg)
            LS.settings = cfg
            Tables(cfg)
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
