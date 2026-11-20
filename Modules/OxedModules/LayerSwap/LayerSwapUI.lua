-- ============================================================================
-- Layer Swap, part 4 of 5: what the player sees
--
--   The portal   a round arcane portal on screen, ringed in gold, tinted the
--                colour of your layer, with the layer's name under it. Its
--                vortex turns slowly; while a swap runs it spins fast, and a
--                burst of light (and a flash of the screen) marks the move.
--                Left-click swaps, right-click lists the layers to ask for,
--                Shift-click opens the window. Drag it where you like.
--   The window   Layers in this zone, Guild, Chat, Host (rank, invites,
--                requests) and Log, in the stone and gold frame.
--   The toast    "X asks for your layer" with Invite and Decline, when Ask
--                before inviting is on.
-- Nothing here is built before the module is switched on.
-- ============================================================================

local _, OxedHub = ...
local LS = OxedHub.LayerSwap
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

local U = {}               -- this file's functions, kept out of the local count
local FONT = "Fonts\\FRIZQT__.TTF"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local VORTEX = "Interface\\Cooldown\\star4"
local HALO = "Interface\\Cooldown\\ping4"
local GOLD = { 1, 0.82, 0.25 }
local W, H, ROW_H, ROWS = 540, 480, 34, 8

local portal, window, menu, toast, flash
local tab, offset = "layers", 0

-- ── Sound ───────────────────────────────────────────────────────────────────

function U.PlayMoveSound()
    local s = LS.settings
    if not s or s.sound == false then return end
    local API = OxedHub.ModuleAPI
    if s.soundId and s.soundId ~= "" and API and API:PlaySound(s.soundId) then return end
    -- the game's own map ping, a short airy whoosh
    if SOUNDKIT then pcall(PlaySound, SOUNDKIT.MAP_PING or 3175, "SFX") end
end

-- ── The portal ──────────────────────────────────────────────────────────────

-- Spell_Arcane_PortalDalaran is missing on some clients and shows as grey
-- noise, so take the first portal icon the client really has.
local PORTAL_ICONS = {
    "Interface\\Icons\\Spell_Arcane_PortalDalaran",
    "Interface\\Icons\\Spell_Arcane_PortalStormwind",
    "Interface\\Icons\\Spell_Arcane_PortalIronForge",
    "Interface\\Icons\\Spell_Arcane_TeleportStormwind",
    "Interface\\Icons\\Spell_Arcane_Arcane04",
}
function U.PortalIcon()
    if GetFileIDFromPath then
        for _, path in ipairs(PORTAL_ICONS) do
            local ok, id = pcall(GetFileIDFromPath, path)
            if ok and id then return id end
        end
    end
    return 136222 -- Spell_Arcane_PortalStormwind by file id
end

local function Spin(tex, seconds, clockwise)
    local group = tex:CreateAnimationGroup()
    group:SetLooping("REPEAT")
    local rot = group:CreateAnimation("Rotation")
    rot:SetDegrees(clockwise and -360 or 360)
    rot:SetDuration(seconds)
    group.rot = rot
    group:Play()
    return group
end

local function SetSpeed(group, seconds)
    if not group or group.rot:GetDuration() == seconds then return end
    group:Stop()
    group.rot:SetDuration(seconds)
    group:Play()
end

function U.BuildPortal()
    if portal then return portal end
    local s = LS.settings
    local f = CreateFrame("Button", "OxedHubLayerSwapPortal", UIParent)
    portal = f
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")

    -- one round mask shared by everything inside the ring, so no square
    -- corner ever shows (SetMask with a path does nothing on some builds)
    local mask = f:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetPoint("CENTER")
    f.mask = mask

    -- the dark well behind the portal
    f.well = f:CreateTexture(nil, "BACKGROUND")
    f.well:SetPoint("CENTER")
    f.well:SetColorTexture(0.03, 0.0, 0.08, 1)
    f.well:AddMaskTexture(mask)

    -- the portal itself: the first portal icon this client has
    f.icon = f:CreateTexture(nil, "BORDER")
    f.icon:SetPoint("CENTER")
    f.icon:SetTexture(U.PortalIcon())
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon:AddMaskTexture(mask)

    -- two vortex layers turning against each other, tinted by the layer
    f.vortex1 = f:CreateTexture(nil, "ARTWORK")
    f.vortex1:SetPoint("CENTER")
    f.vortex1:SetTexture(VORTEX)
    f.vortex1:SetBlendMode("ADD")
    f.vortex1:SetAlpha(0.45)
    f.vortex1:AddMaskTexture(mask)
    f.vortex2 = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.vortex2:SetPoint("CENTER")
    f.vortex2:SetTexture(VORTEX)
    f.vortex2:SetBlendMode("ADD")
    f.vortex2:SetAlpha(0.3)
    f.vortex2:AddMaskTexture(mask)
    f.spin1 = Spin(f.vortex1, 14, true)
    f.spin2 = Spin(f.vortex2, 9, false)

    -- the gold ring of a minimap button, scaled up
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(RING)

    -- a halo that breathes while you host
    f.halo = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.halo:SetPoint("CENTER")
    f.halo:SetTexture(HALO)
    f.halo:SetBlendMode("ADD")
    f.halo:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    f.halo:SetAlpha(0)
    local breathe = f.halo:CreateAnimationGroup()
    breathe:SetLooping("BOUNCE")
    local a = breathe:CreateAnimation("Alpha")
    a:SetFromAlpha(0.15)
    a:SetToAlpha(0.55)
    a:SetDuration(1.6)
    a:SetSmoothing("IN_OUT")
    f.breathe = breathe

    -- the burst when the layer changes
    f.burst = f:CreateTexture(nil, "OVERLAY", nil, 2)
    f.burst:SetPoint("CENTER")
    f.burst:SetTexture(HALO)
    f.burst:SetBlendMode("ADD")
    f.burst:SetAlpha(0)
    local boom = f.burst:CreateAnimationGroup()
    local grow = boom:CreateAnimation("Scale")
    grow:SetScale(2.6, 2.6)
    grow:SetDuration(0.7)
    grow:SetSmoothing("OUT")
    local fadeIn = boom:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.12)
    local fadeOut = boom:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetStartDelay(0.12)
    fadeOut:SetDuration(0.6)
    boom:SetScript("OnFinished", function() f.burst:SetAlpha(0) end)
    f.boom = boom

    -- text under it
    f.name = f:CreateFontString(nil, "OVERLAY")
    f.name:SetFont(FONT, 15, "OUTLINE")
    f.name:SetShadowOffset(1, -1)
    f.name:SetPoint("TOP", f, "BOTTOM", 0, -2)
    f.status = f:CreateFontString(nil, "OVERLAY")
    f.status:SetFont(FONT, 10, "OUTLINE")
    f.status:SetPoint("TOP", f.name, "BOTTOM", 0, -1)
    f.status:SetTextColor(0.85, 0.85, 0.9)
    f.status:SetWidth(220)
    f.status:SetWordWrap(false)
    f.badge = f:CreateFontString(nil, "OVERLAY")
    f.badge:SetFont(FONT, 11, "OUTLINE")
    f.badge:SetPoint("TOPRIGHT", f, "TOPRIGHT", 4, 2)

    f:SetScript("OnClick", function(_, button) U.PortalClick(button) end)
    f:SetScript("OnDragStart", function(self)
        if not LS.settings.lockPortal then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint(1)
        LS.settings.portalPoint, LS.settings.portalRel, LS.settings.portalX, LS.settings.portalY = p, rp, x, y
    end)
    f:SetScript("OnEnter", function(self) U.PortalTooltip(self) end)
    f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    U.ApplyPortalLayout()
    f:Hide()
    return f
end

function U.ApplyPortalLayout()
    local f, s = portal, LS.settings
    if not f then return end
    local size = s.portalSize or 64
    f:SetSize(size, size)
    -- The minimap border art is drawn for a 31px button with a 20px icon at
    -- (7,-5): its hole is centred 17 right and 15 down from its top left.
    -- Scale that so the hole sits exactly round our centred disc.
    local d = size * 0.78
    local k = d / 20
    f.mask:SetSize(d, d)
    f.well:SetSize(d, d)
    f.icon:SetSize(d, d)
    f.vortex1:SetSize(d * 1.3, d * 1.3)
    f.vortex2:SetSize(d, d)
    f.ring:ClearAllPoints()
    f.ring:SetSize(54 * k, 54 * k)
    f.ring:SetPoint("TOPLEFT", f, "CENTER", -17 * k, 15 * k)
    f.halo:SetSize(d * 1.9, d * 1.9)
    f.burst:SetSize(d, d)
    f:SetScale(1)
    f:ClearAllPoints()
    f:SetPoint(s.portalPoint or "CENTER", UIParent, s.portalRel or s.portalPoint or "CENTER", s.portalX or 0, s.portalY or -180)
    f.name:SetShown(s.portalText ~= false)
    f.status:SetShown(s.portalText ~= false)
end

function U.RefreshPortal()
    local f = portal
    if not f then return end
    local id = LS.MyLayer()
    local zone = LS.Zone()
    local swapping = LS.SwapActive()
    local reading = LS.Reading()
    local c = (id and not reading) and LS.LayerColor(id) or LS.UNKNOWN_COLOR
    f.vortex1:SetVertexColor(c[1], c[2], c[3])
    f.vortex2:SetVertexColor(c[1] * 0.8 + 0.2, c[2] * 0.8 + 0.2, c[3] * 0.8 + 0.2)
    f.burst:SetVertexColor(c[1], c[2], c[3])
    if LS.InInstance() then
        f.name:SetText("|cff909090" .. LS.T("No layers here") .. "|r")
    elseif id and not reading then
        f.name:SetText(LS.ColorCode(id) .. (LS.T("Layer %s")):format(LS.LayerName(id, zone)) .. "|r")
    else
        f.name:SetText("|cffb0b0b0" .. (reading and LS.T("Crossing...") or LS.T("Layer ?")) .. "|r")
    end
    f.status:SetText(LS.SwapStatus() or (LS.Hosting() and ("|cffffd040" .. LS.T("Hosting") .. "|r") or ""))
    -- speed: a swap spins the vortex fast
    SetSpeed(f.spin1, swapping and 1.4 or (reading and 2.5 or 14))
    SetSpeed(f.spin2, swapping and 1.0 or (reading and 2 or 9))
    f.vortex1:SetAlpha(swapping and 0.95 or 0.55)
    f.vortex2:SetAlpha(swapping and 0.7 or 0.35)
    f.icon:SetDesaturated((not id or LS.InInstance()) and true or false)
    if LS.Hosting() and LS.settings.hostGlow ~= false then
        if not f.breathe:IsPlaying() then f.breathe:Play() end
    else
        f.breathe:Stop()
        f.halo:SetAlpha(0)
    end
    local left = LS.MovesLeft()
    if left <= (LS.SWAP_LIMITS.MOVE_WARN or 3) then
        f.badge:SetText((left == 0 and "|cffff4040" or "|cffffc040") .. left .. "|r")
    else
        local pending = #LS.Requests()
        f.badge:SetText(pending > 0 and ("|cff40ff40+" .. pending .. "|r") or "")
    end
end

function U.PortalFlash()
    if portal and portal:IsShown() then portal.boom:Stop() portal.boom:Play() end
    if LS.settings.screenFlash == false then return end
    if not flash then
        flash = CreateFrame("Frame", "OxedHubLayerSwapFlash", UIParent)
        flash:SetAllPoints(UIParent)
        flash:SetFrameStrata("FULLSCREEN_DIALOG")
        flash:EnableMouse(false)
        flash.tex = flash:CreateTexture(nil, "BACKGROUND")
        flash.tex:SetAllPoints()
        flash.tex:SetTexture("Interface\\FullScreenTextures\\OutOfControl")
        flash.tex:SetBlendMode("ADD")
        local g = flash:CreateAnimationGroup()
        local inA = g:CreateAnimation("Alpha")
        inA:SetFromAlpha(0)
        inA:SetToAlpha(0.9)
        inA:SetDuration(0.15)
        local outA = g:CreateAnimation("Alpha")
        outA:SetFromAlpha(0.9)
        outA:SetToAlpha(0)
        outA:SetStartDelay(0.15)
        outA:SetDuration(0.9)
        g:SetScript("OnFinished", function() flash:Hide() end)
        flash.anim = g
        flash:Hide()
    end
    local c = LS.LayerColor(LS.MyLayer())
    flash.tex:SetVertexColor(c[1], c[2], c[3])
    flash:SetAlpha(1)
    flash:Show()
    flash.anim:Stop()
    flash.anim:Play()
end

function U.PortalClick(button)
    if button == "RightButton" then
        U.ToggleMenu(portal)
    elseif IsShiftKeyDown() then
        U.ToggleWindow()
    elseif IsControlKeyDown() and LS.SwapActive() then
        LS.StopSwap()
    else
        LS.StartSwap()
    end
end

function U.PortalTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local id, zone = LS.MyLayer(), LS.Zone()
    GameTooltip:AddLine("|cff9f7bff" .. LS.T("Layer Swap") .. "|r")
    if id then
        GameTooltip:AddDoubleLine(LS.T("Layer"), LS.ColorCode(id) .. LS.LayerName(id, zone) .. "|r  |cff808080" .. id .. "|r")
        local since = LS.LayerSince()
        if since then GameTooltip:AddDoubleLine(LS.T("Here for"), LS.Clock(GetTime() - since), 0.8, 0.8, 0.8, 1, 1, 1) end
    else
        GameTooltip:AddLine(LS.T("Layer not known yet. Look at a creature or NPC."), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:AddDoubleLine(LS.T("Zone"), LS.ZoneName(zone), 0.8, 0.8, 0.8, 1, 1, 1)
    local hist = LS.History(zone)
    if #hist > 1 then
        local parts = {}
        for i = 1, math.min(4, #hist) do parts[#parts + 1] = LS.ColorCode(hist[i].id) .. LS.LayerName(hist[i].id, zone) .. "|r" end
        GameTooltip:AddDoubleLine(LS.T("Recent"), table.concat(parts, " < "), 0.8, 0.8, 0.8)
    end
    local left, resetIn = LS.MovesLeft()
    GameTooltip:AddDoubleLine(LS.T("Changes left this hour"), left .. (left < 10 and ("  |cff808080(" .. LS.Clock(resetIn) .. ")|r") or ""), 0.8, 0.8, 0.8, 1, 1, 1)
    if LS.OtherHost() then
        GameTooltip:AddLine((LS.T("%s hosts for you.")):format(LS.OtherHost()), 0.7, 0.7, 0.7)
    elseif LS.Hosting() then
        local inv = LS.HostInvitesLeft()
        local _, rank = LS.Rank()
        GameTooltip:AddDoubleLine(LS.T("Hosting"), ("|cffffd040%s|r  %d/6"):format(LS.T(rank.name), inv), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddDoubleLine(LS.T("Hosting"), "|cff909090" .. LS.T("off") .. "|r", 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(LS.T("Click: swap to another layer"), 0.5, 1, 0.5)
    GameTooltip:AddLine(LS.T("Right-click: pick a layer"), 0.5, 1, 0.5)
    GameTooltip:AddLine(LS.T("Shift-click: open the window"), 0.5, 1, 0.5)
    if LS.SwapActive() then GameTooltip:AddLine(LS.T("Ctrl-click: stop"), 1, 0.6, 0.4) end
    if not LS.settings.lockPortal then GameTooltip:AddLine(LS.T("Drag to move"), 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end

-- ── The layer menu ──────────────────────────────────────────────────────────

local function MenuRows()
    local rows = {}
    local zone, me = LS.Zone(), LS.MyLayer()
    if LS.SwapActive() then
        rows[#rows + 1] = { text = "|cffff8060" .. LS.T("Stop the swap") .. "|r", run = LS.StopSwap }
    end
    if not me then
        rows[#rows + 1] = { text = "|cffffd040" .. LS.T("Reading your layer...") .. "|r", run = function()
            if LS.WantLayer then LS.WantLayer(true) end
        end }
        if LS.lastSkip then rows[#rows + 1] = { text = "|cff707070" .. tostring(LS.lastSkip) .. "|r" } end
    end
    rows[#rows + 1] = { text = "|cff9f7bff" .. LS.T("Any other layer") .. "|r", run = function() LS.StartSwap() end }
    local others = 0
    for _, l in ipairs(LS.SeenLayers(zone)) do
        if not LS.Same(l.id, me) then others = others + 1 end
    end
    if others == 0 then
        rows[#rows + 1] = { text = "|cff909090" .. LS.T("Other layers of this zone show here once seen.") .. "|r" }
    end
    for _, l in ipairs(LS.SeenLayers(zone)) do
        if not LS.Same(l.id, me) then
            local hosts = #LS.HelpersOn(zone, l.id)
            local extra = hosts > 0 and ("  |cff40ff40" .. (LS.T("%d hosts")):format(hosts) .. "|r") or ""
            rows[#rows + 1] = { text = LS.ColorCode(l.id) .. (LS.T("Layer %s")):format(LS.LayerName(l.id, zone)) .. "|r" .. extra,
                run = function() LS.StartSwap(l.id) end }
        end
    end
    if me then
        rows[#rows + 1] = { text = "|cff707070" .. (LS.T("Layer %s (you are here)")):format(LS.LayerName(me, zone)) .. "|r" }
    end
    rows[#rows + 1] = { text = LS.Hosting() and LS.T("Hosting: on") or LS.T("Hosting: off"), run = function()
        LS.settings.host = not LS.settings.host
        LS.SendGuildState(true)
        LS.Changed()
    end }
    rows[#rows + 1] = { text = LS.T("Open the window"), run = function() U.ShowWindow() end }
    rows[#rows + 1] = { text = LS.T("Options"), run = function() if LS.ShowOptions then LS.ShowOptions() end end }
    return rows
end

function U.ToggleMenu(owner)
    if menu and menu:IsShown() then menu:Hide() return end
    if not menu then
        menu = CreateFrame("Frame", "OxedHubLayerSwapMenu", UIParent, "BackdropTemplate")
        menu:SetFrameStrata("DIALOG")
        menu:SetClampedToScreen(true)
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        menu:SetBackdropColor(0.05, 0.02, 0.1, 0.95)
        menu.items = {}
        menu:SetScript("OnShow", function(self) self.shownAt = GetTime() end)
        menu:SetScript("OnUpdate", function(self)
            if GetTime() - (self.shownAt or 0) > 0.3 and not self:IsMouseOver() and not (portal and portal:IsMouseOver())
                and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                self:Hide()
            end
        end)
        tinsert(UISpecialFrames, "OxedHubLayerSwapMenu")
    end
    local rows = MenuRows()
    for i, r in ipairs(rows) do
        local b = menu.items[i]
        if not b then
            b = CreateFrame("Button", nil, menu)
            b:SetHeight(18)
            b:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, -8 - (i - 1) * 18)
            b:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -8, -8 - (i - 1) * 18)
            local lit = b:CreateTexture(nil, "HIGHLIGHT")
            lit:SetAllPoints()
            lit:SetColorTexture(0.6, 0.45, 1, 0.18)
            b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.label:SetPoint("LEFT", 4, 0)
            b.label:SetJustifyH("LEFT")
            b:SetScript("OnClick", function(self)
                menu:Hide()
                if self.run then self.run() end
            end)
            menu.items[i] = b
        end
        b.run = r.run
        b.label:SetText(r.text)
        b:EnableMouse(r.run ~= nil)
        b:Show()
    end
    for i = #rows + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(210, #rows * 18 + 16)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", owner or UIParent, "BOTTOMRIGHT", 0, 0)
    menu:Show()
end

-- ── The window ──────────────────────────────────────────────────────────────

local function MakeButton(parent, width, text, onClick, height)
    local B = OxedHub.UIComponents and OxedHub.UIComponents.Button
    if B and B.CreateTab then
        local ok, b = pcall(B.CreateTab, parent, width, text, onClick, height or 22)
        if ok and b then return b end
    end
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height or 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    b.SetActive = function() end
    return b
end

local TABS = {
    { key = "layers", text = "Layers" },
    { key = "guild",  text = "Guild" },
    { key = "chat",   text = "Chat" },
    { key = "host",   text = "Host" },
    { key = "log",    text = "Log" },
}

local function BuildRow(parent, i)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H - 3)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.3, 0.2, 0.45, i % 2 == 0 and 0.35 or 0.2)
    r.chip = r:CreateTexture(nil, "ARTWORK")
    r.chip:SetSize(24, 24)
    r.chip:SetPoint("LEFT", 6, 0)
    r.chip:SetTexture(LS.ICON)
    pcall(r.chip.SetMask, r.chip, MASK)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.chip, "TOPRIGHT", 8, 1)
    r.name:SetJustifyH("LEFT")
    r.name:SetWidth(300)
    r.name:SetWordWrap(false)
    r.detail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.detail:SetPoint("BOTTOMLEFT", r.chip, "BOTTOMRIGHT", 8, -1)
    r.detail:SetJustifyH("LEFT")
    r.detail:SetWidth(340)
    r.detail:SetWordWrap(false)
    r.button = MakeButton(r, 92, "", function() if r.run then r.run() end end)
    r.button:SetPoint("RIGHT", -4, 0)
    r.button2 = MakeButton(r, 80, "", function() if r.run2 then r.run2() end end)
    r.button2:SetPoint("RIGHT", r.button, "LEFT", -4, 0)
    return r
end

local function FillRow(r, d)
    r.chip:SetVertexColor(unpack(d.color or { 1, 1, 1 }))
    r.chip:SetDesaturated(d.grey == true)
    r.name:SetText(d.name or "")
    r.detail:SetText(d.detail or "")
    r.run, r.run2 = d.run, d.run2
    r.button:SetShown(d.button ~= nil)
    r.button:SetText(d.button or "")
    r.button2:SetShown(d.button2 ~= nil)
    r.button2:SetText(d.button2 or "")
    r:Show()
end

local function Ago(t) return (LS.T("%s ago")):format(LS.Clock(t)) end

local function LayerRows()
    local out, zone, me = {}, LS.Zone(), LS.MyLayer()
    local wall = time()
    for _, l in ipairs(LS.SeenLayers(zone)) do
        local mine = LS.Same(l.id, me)
        local hosts, guild = #LS.HelpersOn(zone, l.id), LS.GuildOnLayer(zone, l.id)
        local bits = {}
        bits[#bits + 1] = mine and ("|cff40ff40" .. LS.T("You are here") .. "|r") or Ago(wall - (l.last or wall))
        if hosts > 0 then bits[#bits + 1] = "|cffffd040" .. (LS.T("%d hosts")):format(hosts) .. "|r" end
        if guild > 0 then bits[#bits + 1] = "|cff40c0ff" .. (LS.T("%d guildmates")):format(guild) .. "|r" end
        bits[#bits + 1] = "|cff707070" .. tostring(l.id) .. "|r"
        out[#out + 1] = {
            color = LS.LayerColor(l.id),
            name = LS.ColorCode(l.id) .. (LS.T("Layer %s")):format(LS.LayerName(l.id, zone)) .. "|r",
            detail = table.concat(bits, "  "),
            button = (not mine) and LS.T("Go there") or nil,
            run = function() LS.StartSwap(l.id) end,
        }
    end
    return out, LS.T("No layers seen in this zone yet. Look at a few creatures.")
end

local REL_TEXT = { same = { "On your layer", "40ff40" }, other = { "Another layer", "ffa040" },
                   zone = { "In %s", "909090" }, unknown = { "Layer not known", "909090" } }

local function GuildRows()
    local out = {}
    for _, m in ipairs(LS.GuildList()) do
        local spec = REL_TEXT[m.rel] or REL_TEXT.unknown
        local rel = LS.T(spec[1])
        if m.rel == "zone" then rel = rel:format(LS.ZoneName(m.zone)) end
        rel = "|cff" .. spec[2] .. rel .. "|r"
        out[#out + 1] = {
            color = m.layer and LS.LayerColor(m.layer) or LS.UNKNOWN_COLOR, grey = m.rel ~= "same" and m.rel ~= "other",
            name = m.name .. (m.host and ("  |cffffd040" .. LS.T("host") .. "|r") or ""),
            detail = rel .. (m.layer and ("  " .. LS.ColorCode(m.layer) .. LS.LayerName(m.layer, m.zone) .. "|r") or "")
                .. "  |cff707070" .. Ago(m.age) .. "|r",
            button = m.rel == "other" and LS.T("Find them") or nil,
            run = function() LS.FindGuildmate(m.name) end,
        }
    end
    return out, LS.T("No guildmates with Layer Swap heard from yet.")
end

local function ChatRows()
    local out, now = {}, GetTime()
    for _, l in ipairs(LS.ChatLines()) do
        out[#out + 1] = {
            color = l.kind == "offer" and { 0.4, 1, 0.4 } or { 1, 0.7, 0.3 },
            name = l.name .. "  |cff909090" .. (l.kind == "offer" and LS.T("offers a layer") or LS.T("wants a layer")) .. "|r",
            detail = '"' .. l.text .. '"  |cff707070' .. Ago(now - l.at) .. "|r",
            button = LS.T("Whisper"), run = function() LS.WhisperOffer(l) end,
        }
    end
    return out, LS.T("No layer offers in chat lately.")
end

local function LogRows()
    local out, wall = {}, time()
    for _, e in ipairs(LS.GetLog()) do
        out[#out + 1] = { color = { 0.6, 0.6, 0.7 }, grey = true, name = "|cffd0d0d0" .. e.text .. "|r",
            detail = "|cff707070" .. date("%H:%M:%S", e.at) .. "  " .. Ago(wall - e.at) .. "|r" }
    end
    return out, LS.T("Nothing yet.")
end

local function RequestRows()
    local out, now = {}, GetTime()
    for _, r in ipairs(LS.Requests()) do
        out[#out + 1] = { color = GOLD, name = (LS.T("%s asks for your layer")):format(r.name),
            detail = "|cff909090" .. Ago(now - r.at) .. "|r",
            button = LS.T("Invite"), run = function() LS.InviteNext(r.name) end,
            button2 = LS.T("Decline"), run2 = function() LS.DeclineRequest(r.name) end }
    end
    return out, nil
end

function U.RefreshHostPanel()
    local p = window and window.hostPanel
    if not p then return end
    local idx, rank, nextRank = LS.Rank()
    local hops = LS.Hops().total or 0
    p.rank:SetText("|cffffd040" .. LS.T(rank.name) .. "|r")
    p.hops:SetText((LS.T("%d players brought to your layer")):format(hops))
    if nextRank then
        p.bar:SetMinMaxValues(rank.at, nextRank.at)
        p.bar:SetValue(hops)
        p.barText:SetText((LS.T("%d / %d to %s")):format(hops, nextRank.at, LS.T(nextRank.name)))
    else
        p.bar:SetMinMaxValues(0, 1)
        p.bar:SetValue(1)
        p.barText:SetText(LS.T("Highest rank"))
    end
    p.badge:SetDesaturated(idx < 3)
    local inv, resetIn = LS.HostInvitesLeft()
    local stats = LS.SwapStats()
    local state
    if LS.OtherHost() then
        state = (LS.T("%s hosts for you, so Layer Swap only asks.")):format(LS.OtherHost())
    elseif LS.Hosting() then
        state = "|cff40ff40" .. LS.T("Hosting is on.") .. "|r  " .. (LS.T("Invites left: %d of 6")):format(inv)
            .. (inv < 6 and ("  |cff808080(" .. LS.Clock(resetIn) .. ")|r") or "")
    else
        state = "|cff909090" .. LS.T("Hosting is off.") .. "|r"
    end
    p.state:SetText(state)
    p.stats:SetText((LS.T("This session: %d asks sent, %d answers, %d invites sent, %d asks skipped. Known hosts: %d.")):format(
        stats.asks, stats.replies, stats.invites, stats.skipped, LS.KnownHostCount()))
    p.toggle:SetText(LS.Hosting() and LS.T("Stop hosting") or LS.T("Start hosting"))
end

function U.RefreshWindow()
    local f = window
    if not f or not f:IsShown() then return end
    local id, zone = LS.MyLayer(), LS.Zone()
    f.layer:SetText(id and (LS.ColorCode(id) .. (LS.T("Layer %s")):format(LS.LayerName(id, zone)) .. "|r") or ("|cffb0b0b0" .. LS.T("Layer ?") .. "|r"))
    local left = LS.MovesLeft()
    f.zone:SetText(LS.ZoneName(zone) .. "  |cff808080" .. (id or "") .. "|r   " .. (LS.T("%d changes left this hour")):format(left))
    f.status:SetText(LS.SwapStatus() or "")
    f.swap:SetText(LS.SwapActive() and LS.T("Search more") or LS.T("Swap layer"))
    f.stop:SetShown(LS.SwapActive())
    local c = id and LS.LayerColor(id) or LS.UNKNOWN_COLOR
    f.portalIcon:SetVertexColor(1, 1, 1)
    f.portalGlow:SetVertexColor(c[1], c[2], c[3])
    for _, t in ipairs(f.tabs) do t:SetActive(t.key == tab) end

    local list, empty
    if tab == "layers" then list, empty = LayerRows()
    elseif tab == "guild" then list, empty = GuildRows()
    elseif tab == "chat" then list, empty = ChatRows()
    elseif tab == "log" then list, empty = LogRows()
    else list, empty = RequestRows() end

    local hostTab = tab == "host"
    f.hostPanel:SetShown(hostTab)
    f.list:ClearAllPoints()
    f.list:SetPoint("TOPLEFT", 18, hostTab and -262 or -150)
    f.list:SetPoint("TOPRIGHT", -18, hostTab and -262 or -150)
    local rows = hostTab and 4 or ROWS
    if hostTab then U.RefreshHostPanel() end
    local maxOff = math.max(0, #list - rows)
    if offset > maxOff then offset = maxOff end
    for i = 1, ROWS do
        local d = i <= rows and list[offset + i]
        if d then FillRow(f.rows[i], d) else f.rows[i]:Hide() end
    end
    f.empty:SetText((#list == 0 and empty) or "")
    f.more:SetText(#list > rows and (LS.T("%d-%d of %d")):format(offset + 1, math.min(#list, offset + rows), #list) or "")
end

function U.BuildWindow()
    if window then return window end
    local f = CreateFrame("Frame", "OxedHubLayerSwapWindow", UIParent, "BackdropTemplate")
    window = f
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel
    local ornate = false
    if Panel and Panel.ApplyOrnateFrame then
        local shell = CreateFrame("Frame", nil, f, "BackdropTemplate")
        shell:SetAllPoints(f)
        shell:SetFrameLevel(f:GetFrameLevel())
        shell:EnableMouse(false)
        ornate = pcall(Panel.ApplyOrnateFrame, shell, LS.T("Layer Swap"), 0.96)
    end
    if not ornate then
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0.03, 0.01, 0.07, 0.94)
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -10)
        title:SetText(LS.T("Layer Swap"))
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() f:Hide() end)
    f:SetSize(W, H)
    local s = LS.settings
    f:SetPoint(s.winPoint or "CENTER", UIParent, s.winPoint or "CENTER", s.winX or 0, s.winY or 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint(1)
        s.winPoint, s.winX, s.winY = p, x, y
    end)
    f:SetScript("OnShow", function() offset = 0 LS.Scan() U.RefreshWindow() end)
    f:Hide()
    tinsert(UISpecialFrames, "OxedHubLayerSwapWindow")

    -- header: the portal, the layer, the swap button
    f.portalGlow = f:CreateTexture(nil, "ARTWORK")
    f.portalGlow:SetSize(78, 78)
    f.portalGlow:SetPoint("TOPLEFT", 14, -26)
    f.portalGlow:SetTexture(VORTEX)
    f.portalGlow:SetBlendMode("ADD")
    Spin(f.portalGlow, 12, true)
    f.portalIcon = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.portalIcon:SetSize(50, 50)
    f.portalIcon:SetPoint("CENTER", f.portalGlow, "CENTER")
    f.portalIcon:SetTexture(LS.ICON)
    pcall(f.portalIcon.SetMask, f.portalIcon, MASK)
    f.layer = f:CreateFontString(nil, "OVERLAY")
    f.layer:SetFont(FONT, 22, "OUTLINE")
    f.layer:SetPoint("TOPLEFT", f.portalGlow, "TOPRIGHT", 6, -12)
    f.zone = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.zone:SetPoint("TOPLEFT", f.layer, "BOTTOMLEFT", 0, -4)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("TOPLEFT", f.zone, "BOTTOMLEFT", 0, -3)
    f.status:SetWidth(280)
    f.status:SetJustifyH("LEFT")
    f.swap = MakeButton(f, 120, "", function() LS.StartSwap() end, 26)
    f.swap:SetPoint("TOPRIGHT", -26, -36)
    f.stop = MakeButton(f, 120, LS.T("Stop"), function() LS.StopSwap() end, 22)
    f.stop:SetPoint("TOPRIGHT", f.swap, "BOTTOMRIGHT", 0, -4)
    local opt = MakeButton(f, 120, LS.T("Options"), function() if LS.ShowOptions then LS.ShowOptions() end end, 22)
    opt:SetPoint("TOPRIGHT", f.stop, "BOTTOMRIGHT", 0, -4)

    -- tabs
    f.tabs = {}
    local prev
    for _, t in ipairs(TABS) do
        local b = MakeButton(f, 96, LS.T(t.text), function() tab = t.key offset = 0 U.RefreshWindow() end, 24)
        b.key = t.key
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 18, -116) end
        f.tabs[#f.tabs + 1] = b
        prev = b
    end

    -- the Host page's top half
    local p = CreateFrame("Frame", nil, f)
    f.hostPanel = p
    p:SetPoint("TOPLEFT", 18, -146)
    p:SetPoint("TOPRIGHT", -18, -146)
    p:SetHeight(110)
    p.badge = p:CreateTexture(nil, "ARTWORK")
    p.badge:SetSize(48, 48)
    p.badge:SetPoint("TOPLEFT", 2, -2)
    p.badge:SetTexture("Interface\\Icons\\Spell_Arcane_TeleportDalaran")
    p.rank = p:CreateFontString(nil, "OVERLAY")
    p.rank:SetFont(FONT, 17, "OUTLINE")
    p.rank:SetPoint("TOPLEFT", p.badge, "TOPRIGHT", 10, -2)
    p.hops = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.hops:SetPoint("TOPLEFT", p.rank, "BOTTOMLEFT", 0, -3)
    p.bar = CreateFrame("StatusBar", nil, p)
    p.bar:SetSize(300, 14)
    p.bar:SetPoint("TOPLEFT", p.badge, "BOTTOMLEFT", 0, -8)
    p.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    p.bar:SetStatusBarColor(0.62, 0.45, 1)
    local barBg = p.bar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0, 0, 0, 0.5)
    p.barText = p.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.barText:SetPoint("CENTER")
    p.state = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.state:SetPoint("TOPLEFT", p.bar, "BOTTOMLEFT", 0, -6)
    p.state:SetWidth(W - 60)
    p.state:SetJustifyH("LEFT")
    p.stats = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.stats:SetPoint("TOPLEFT", p.state, "BOTTOMLEFT", 0, -4)
    p.stats:SetWidth(W - 60)
    p.stats:SetJustifyH("LEFT")
    p.toggle = MakeButton(p, 130, "", function()
        s.host = not s.host
        LS.SendGuildState(true)
        LS.Changed()
    end)
    p.toggle:SetPoint("TOPRIGHT", 0, -2)
    local kick = MakeButton(p, 130, LS.T("Remove guests"), function() LS.KickGuests() end)
    kick:SetPoint("TOPRIGHT", p.toggle, "BOTTOMRIGHT", 0, -4)
    p:Hide()

    -- the list
    local list = CreateFrame("Frame", nil, f)
    f.list = list
    list:SetPoint("TOPLEFT", 18, -150)
    list:SetPoint("TOPRIGHT", -18, -150)
    list:SetHeight(ROWS * ROW_H)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta)
        U.RefreshWindow()
    end)
    f.rows = {}
    for i = 1, ROWS do f.rows[i] = BuildRow(list, i) end
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetPoint("TOP", list, "TOP", 0, -40)
    f.empty:SetWidth(W - 80)
    f.more = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.more:SetPoint("BOTTOMRIGHT", -20, 14)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 14)
    hint:SetText(LS.T("A swap joins a host's group on another layer, then leaves it. Layers belong to one zone."))
    hint:SetWidth(W - 140)
    hint:SetJustifyH("LEFT")
    return f
end

function U.ShowWindow(which)
    if not LS.running then
        LS.Say(LS.T("Switch Layer Swap on in the Modules page first."))
        return
    end
    U.BuildWindow()
    if which then tab = which end
    window:Show()
end

function U.ToggleWindow()
    if window and window:IsShown() then window:Hide() else U.ShowWindow() end
end

-- ── The request toast (Ask before inviting) ─────────────────────────────────

function U.ShowToast()
    local list = LS.Requests()
    local r = list[1]
    if not r then
        if toast then toast:Hide() end
        return
    end
    if not toast then
        toast = CreateFrame("Frame", "OxedHubLayerSwapToast", UIParent, "BackdropTemplate")
        toast:SetSize(300, 74)
        toast:SetPoint("TOP", UIParent, "TOP", 0, -120)
        toast:SetFrameStrata("HIGH")
        toast:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        toast:SetBackdropColor(0.05, 0.02, 0.1, 0.95)
        toast:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3])
        toast.glow = toast:CreateTexture(nil, "ARTWORK")
        toast.glow:SetSize(64, 64)
        toast.glow:SetPoint("LEFT", -4, 0)
        toast.glow:SetTexture(VORTEX)
        toast.glow:SetBlendMode("ADD")
        toast.glow:SetVertexColor(0.62, 0.48, 1)
        Spin(toast.glow, 6, true)
        toast.icon = toast:CreateTexture(nil, "ARTWORK", nil, 1)
        toast.icon:SetSize(38, 38)
        toast.icon:SetPoint("CENTER", toast.glow, "CENTER")
        toast.icon:SetTexture(LS.ICON)
        pcall(toast.icon.SetMask, toast.icon, MASK)
        toast.caption = toast:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        toast.caption:SetPoint("TOPLEFT", 64, -10)
        toast.caption:SetText(LS.T("Layer Swap request"))
        toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        toast.title:SetPoint("TOPLEFT", toast.caption, "BOTTOMLEFT", 0, -2)
        toast.title:SetWidth(226)
        toast.title:SetJustifyH("LEFT")
        toast.invite = MakeButton(toast, 90, LS.T("Invite"), function()
            if toast.name then LS.InviteNext(toast.name) end
        end)
        toast.invite:SetPoint("BOTTOMLEFT", 64, 8)
        toast.decline = MakeButton(toast, 90, LS.T("Decline"), function()
            if toast.name then LS.DeclineRequest(toast.name) end
        end)
        toast.decline:SetPoint("LEFT", toast.invite, "RIGHT", 6, 0)
    end
    toast.name = r.name
    toast.title:SetText((LS.T("%s asks for your layer")):format(r.name) .. (#list > 1 and ("  |cff909090+" .. (#list - 1) .. "|r") or ""))
    toast:Show()
end

-- ── Hooks the other files call ──────────────────────────────────────────────

function LS.OnLayerChanged(old, new, how)
    if LS.SendGuildState then LS.SendGuildState(false) end
    if old and new and not LS.Same(old, new) then
        U.PortalFlash()
        if how ~= "read" then U.PlayMoveSound() end
        if LS.settings.layerChat and not LS.SwapActive() then
            LS.Chat((LS.T("You are on layer %s now.")):format(LS.ColorCode(new) .. LS.LayerName(new) .. "|r"))
        end
    end
end

function LS.OnHostRequest()
    U.ShowToast()
    if LS.settings.sound ~= false and SOUNDKIT then pcall(PlaySound, SOUNDKIT.READY_CHECK or 8960, "SFX") end
end

function LS.OnHop(name, newRank)
    if newRank then
        LS.Say((LS.T("New host rank: %s! You have brought %d players across.")):format("|cffffd040" .. LS.T(newRank.name) .. "|r", LS.Hops().total))
        U.PortalFlash()
    end
    LS.Log("Hop: " .. name .. " joined")
end

LS.Listen(function()
    if not LS.running then return end
    U.RefreshPortal()
    U.RefreshWindow()
    if toast and toast:IsShown() then U.ShowToast() end
end)

-- the portal's line and the request list age even when nothing happens
LS.OnTick(function()
    U.RefreshPortal()
    if toast and toast:IsShown() then U.ShowToast() end
end)

-- ── For LayerSwap.lua ───────────────────────────────────────────────────────

function LS.ApplyPortal(on)
    local s = LS.settings
    if on and s.showPortal ~= false then
        U.BuildPortal()
        U.ApplyPortalLayout()
        portal:Show()
        U.RefreshPortal()
    elseif portal then
        portal:Hide()
    end
end

function LS.HideAll()
    if portal then portal:Hide() end
    if window then window:Hide() end
    if menu then menu:Hide() end
    if toast then toast:Hide() end
end

LS.ShowWindow = U.ShowWindow
LS.ToggleWindow = U.ToggleWindow
LS.ToggleMenu = function() U.ToggleMenu(portal) end
LS.ApplyPortalLayout = U.ApplyPortalLayout
