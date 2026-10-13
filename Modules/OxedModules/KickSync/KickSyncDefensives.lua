-- KickSyncDefensives.lua - Active Defensive Buff Overlay on Unit Frames
-- Mirrors active big defensives & external defensives as centered icons
-- directly on each party member's unit frame.
--
-- Zero spell database required:
--   * Modern WoW C-side aura categories:
--     "HELPFUL|BIG_DEFENSIVE" and "HELPFUL|EXTERNAL_DEFENSIVE"
--   * Taint-safe in Retail 11.x / 12.x Midnight.
-- ============================================================================

local addonName, OxedHub = ...
OxedHub.KickSyncDefensives = OxedHub.KickSyncDefensives or {}
local DEF = OxedHub.KickSyncDefensives

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local MAX_ICONS = 5
local ICON_GAP = 2

local unitFrames = {}       -- [unit] = { icons = { frame, frame, ... } }
local scratchActive = {}    -- big defensives
local scratchExternals = {} -- external defensives
local eventFrame = nil
local isEnabled = false

local function GetAnchor(unit)
    local UF = OxedHub.KickSyncUnitFrames
    if UF and UF.GetPartyFrame then
        return UF:GetPartyFrame(unit)
    end
    return nil
end

local function CreateOverlayIcon()
    local f = CreateFrame("Frame", nil, UIParent)
    f:Hide()
    f:EnableMouse(false)

    local border = f:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.9)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(true)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(false)
    f.cd = cd

    return f
end

local function EnsureUnit(unit)
    local rec = unitFrames[unit]
    if not rec then
        rec = { icons = {} }
        unitFrames[unit] = rec
    end
    return rec
end

local function HideIconsFrom(rec, startIdx)
    if not rec then return end
    for i = startIdx, #rec.icons do
        local f = rec.icons[i]
        if f then f:Hide() end
    end
end

local function CollectDefensives(unit)
    wipe(scratchActive)
    wipe(scratchExternals)

    local ok, list = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL")
    if not ok or type(list) ~= "table" then return end

    for _, aura in ipairs(list) do
        if aura and aura.auraInstanceID then
            local okB, outB = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, aura.auraInstanceID, "HELPFUL|BIG_DEFENSIVE")
            if okB and outB == false then
                if #scratchActive < MAX_ICONS then
                    scratchActive[#scratchActive + 1] = aura
                end
            else
                local okE, outE = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, aura.auraInstanceID, "HELPFUL|EXTERNAL_DEFENSIVE")
                if okE and outE == false and #scratchExternals < MAX_ICONS then
                    scratchExternals[#scratchExternals + 1] = aura
                end
            end
        end
    end

    for _, aura in ipairs(scratchExternals) do
        if #scratchActive >= MAX_ICONS then break end
        scratchActive[#scratchActive + 1] = aura
    end
end

local function UpdateUnit(unit)
    local rec = unitFrames[unit]
    if not isEnabled or not UnitExists(unit) then
        HideIconsFrom(rec, 1)
        return
    end

    CollectDefensives(unit)
    local count = #scratchActive
    if count == 0 then
        HideIconsFrom(rec, 1)
        return
    end

    local parent = GetAnchor(unit)
    if not parent then
        HideIconsFrom(rec, 1)
        return
    end

    rec = EnsureUnit(unit)
    local size = 26
    local step = size + ICON_GAP
    local totalW = count * size + (count - 1) * ICON_GAP
    local startX = -(totalW / 2) + size / 2
    local level = (parent:GetFrameLevel() or 10) + 20

    for i = 1, count do
        local f = rec.icons[i]
        if not f then
            f = CreateOverlayIcon()
            rec.icons[i] = f
        end

        f:SetSize(size, size)
        if f:GetParent() ~= parent then f:SetParent(parent) end
        f:ClearAllPoints()
        f:SetPoint("CENTER", parent, "CENTER", startX + (i - 1) * step, 0)
        f:SetFrameLevel(level)

        local aura = scratchActive[i]
        pcall(f.tex.SetTexture, f.tex, aura.icon)

        -- Cooldown duration swipe
        if aura.expirationTime and aura.expirationTime > 0 and aura.duration and aura.duration > 0 then
            f.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
            f.cd:Show()
        else
            f.cd:Hide()
        end

        if not f:IsShown() then f:Show() end
    end

    HideIconsFrom(rec, count + 1)
end

function DEF:RefreshAll()
    for _, unit in ipairs(UNITS) do
        UpdateUnit(unit)
    end
end

local function OnEvent(_, event, unit)
    if event == "UNIT_AURA" then
        if unit and (unit == "player" or unit:find("^party%d$")) then
            UpdateUnit(unit)
        end
    else
        DEF:RefreshAll()
    end
end

function DEF:SetEnabled(state)
    isEnabled = (state == true)
    if isEnabled then
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnEvent)
        end
        eventFrame:RegisterEvent("UNIT_AURA")
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RefreshAll()
    else
        if eventFrame then eventFrame:UnregisterAllEvents() end
        for _, rec in pairs(unitFrames) do
            HideIconsFrom(rec, 1)
        end
    end
end

function DEF:IsEnabled()
    return isEnabled
end
