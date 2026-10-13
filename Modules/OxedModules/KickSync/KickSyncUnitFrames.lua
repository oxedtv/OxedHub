-- KickSyncUnitFrames.lua - Cross-addon Party Unit Frame Resolver
-- Resolves on-screen frames for party members across:
--   * Blizzard Compact Party / Raid Frames
--   * ElvUI
--   * Cell
--   * Grid2
--   * Shadowed Unit Frames (SUF)
--   * NDui
--   * VuhDo
--   * Danders / D4
--   * EllesmereUI / EnhanceQoL
--
-- Taint-safe (12.x / Midnight compatible) using issecretvalue guards.
-- ============================================================================

local addonName, OxedHub = ...
OxedHub.KickSyncUnitFrames = OxedHub.KickSyncUnitFrames or {}
local UF = OxedHub.KickSyncUnitFrames

local function IsVisibleFrame(f)
    return f and f:IsVisible()
end

local function GetFrameUnit(btn)
    if not btn then return nil end
    local u
    if btn.GetAttribute then
        local ok, val = pcall(btn.GetAttribute, btn, "unit")
        if ok and type(val) == "string" and val ~= "" then
            u = val
        end
    end
    if (not u or u == "") and btn.unit and type(btn.unit) == "string" then
        u = btn.unit
    end
    return u
end

local function SameUnit(frameUnit, unit)
    if frameUnit == unit then return true end
    if not frameUnit or not unit then return false end

    -- Safe arena/raid alias check
    local okA, idxA = pcall(UnitInRaid, frameUnit)
    local okB, idxB = pcall(UnitInRaid, unit)
    if not okA or not okB or type(idxA) ~= "number" or type(idxB) ~= "number" then
        return false
    end

    local isSec = issecretvalue
    if isSec then
        local okSA, sA = pcall(isSec, idxA)
        local okSB, sB = pcall(isSec, idxB)
        if not okSA or sA or not okSB or sB then return false end
    end

    return idxA == idxB
end

local function ScanButtons(prefix, unit, maxSlots)
    for i = 1, maxSlots do
        local btn = _G[prefix .. i]
        if IsVisibleFrame(btn) and SameUnit(GetFrameUnit(btn), unit) then
            return btn
        end
    end
    return nil
end

-- Provider Probes & Finders
local function FindElvUI(unit)
    if not (_G["ElvUI"] or _G["ElvUF_PartyGroup1"]) then return nil end
    local header = _G["ElvUF_PartyGroup1"]
    if header and header:IsVisible() then
        for i = 1, 5 do
            local btn = _G["ElvUF_PartyGroup1UnitButton" .. i]
            if IsVisibleFrame(btn) and SameUnit(GetFrameUnit(btn), unit) then
                return btn
            end
        end
    end
    if unit == "player" and IsVisibleFrame(_G["ElvUF_Player"]) then
        return _G["ElvUF_Player"]
    end
    return nil
end

local function FindCell(unit)
    if not _G["Cell"] then return nil end
    for i = 1, 5 do
        local btn = _G["CellPartyFrameMember" .. i]
        if IsVisibleFrame(btn) and SameUnit(GetFrameUnit(btn), unit) then
            return btn
        end
    end
    -- Cell indicators container fallback
    local indicators = _G["CellIndicatorsParty"]
    if indicators and indicators:IsVisible() then
        for i = 1, 5 do
            local child = indicators["party" .. i]
            if IsVisibleFrame(child) and SameUnit(GetFrameUnit(child), unit) then
                return child
            end
        end
    end
    return nil
end

local function FindGrid2(unit)
    if not _G["Grid2LayoutFrame"] then return nil end
    local grid = _G["Grid2LayoutFrame"]
    if grid and grid:IsVisible() then
        local kids = { grid:GetChildren() }
        for _, child in ipairs(kids) do
            if IsVisibleFrame(child) and SameUnit(GetFrameUnit(child), unit) then
                return child
            end
        end
    end
    return nil
end

local function FindSUF(unit)
    if not (_G["SUFHeaderparty"] or _G["SUFUnitplayer"]) then return nil end
    if unit == "player" and IsVisibleFrame(_G["SUFUnitplayer"]) then
        return _G["SUFUnitplayer"]
    end
    local party = _G["SUFHeaderparty"]
    if party and party:IsVisible() then
        for i = 1, 5 do
            local btn = _G["SUFHeaderpartyUnitButton" .. i]
            if IsVisibleFrame(btn) and SameUnit(GetFrameUnit(btn), unit) then
                return btn
            end
        end
    end
    return nil
end

local function FindNDui(unit)
    if not (_G["NDui"] or _G["oUF_Party"]) then return nil end
    if unit == "player" and IsVisibleFrame(_G["oUF_Player"]) then
        return _G["oUF_Player"]
    end
    return ScanButtons("oUF_PartyUnitButton", unit, 5)
end

local function FindVuhDo(unit)
    if not (_G["Vd1H1"] or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("VuhDo"))) then return nil end
    for panel = 1, 5 do
        for btnIdx = 1, 5 do
            local btn = _G["Vd" .. panel .. "H" .. btnIdx]
            if IsVisibleFrame(btn) and SameUnit(GetFrameUnit(btn), unit) then
                return btn
            end
        end
    end
    return nil
end

local function FindBlizzard(unit)
    -- CompactPartyFrame / CompactRaidFrameContainer
    if unit == "player" then
        if IsVisibleFrame(PartyFrame) and IsVisibleFrame(PartyFrame.MemberFrame1) then
            if SameUnit(GetFrameUnit(PartyFrame.MemberFrame1), "player") then
                return PartyFrame.MemberFrame1
            end
        end
        if IsVisibleFrame(CompactPartyFrameMember1) and SameUnit(GetFrameUnit(CompactPartyFrameMember1), "player") then
            return CompactPartyFrameMember1
        end
        if IsVisibleFrame(PlayerFrame) then
            return PlayerFrame
        end
    end

    -- Party member buttons
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if IsVisibleFrame(f) and SameUnit(GetFrameUnit(f), unit) then
            return f
        end
    end

    -- Modern Dragonflight / TWW PartyFrame container
    if PartyFrame and PartyFrame:IsVisible() then
        for i = 1, 4 do
            local f = PartyFrame["MemberFrame" .. i]
            if IsVisibleFrame(f) and SameUnit(GetFrameUnit(f), unit) then
                return f
            end
        end
    end

    -- CompactRaidFrameContainer (Raid style party frames)
    if CompactRaidFrameContainer and CompactRaidFrameContainer:IsVisible() then
        for i = 1, 5 do
            local f = _G["CompactRaidFrame" .. i]
            if IsVisibleFrame(f) and SameUnit(GetFrameUnit(f), unit) then
                return f
            end
        end
    end

    return nil
end

-- ── Public API ──────────────────────────────────────────────────────────────

function UF:GetPartyFrame(unit, providerOverride)
    if not unit then return nil end

    if providerOverride == "ELVUI" then return FindElvUI(unit) end
    if providerOverride == "CELL" then return FindCell(unit) end
    if providerOverride == "GRID2" then return FindGrid2(unit) end
    if providerOverride == "SUF" then return FindSUF(unit) end
    if providerOverride == "NDUI" then return FindNDui(unit) end
    if providerOverride == "VUHDO" then return FindVuhDo(unit) end
    if providerOverride == "BLIZZARD" then return FindBlizzard(unit) end

    -- AUTO: highest-specificity provider wins
    local res = FindElvUI(unit)
    if res then return res end
    res = FindCell(unit)
    if res then return res end
    res = FindGrid2(unit)
    if res then return res end
    res = FindSUF(unit)
    if res then return res end
    res = FindNDui(unit)
    if res then return res end
    res = FindVuhDo(unit)
    if res then return res end
    return FindBlizzard(unit)
end

function UF:GetDetectedProviderName()
    if _G["ElvUI"] or _G["ElvUF_PartyGroup1"] then return "ElvUI" end
    if _G["Cell"] then return "Cell" end
    if _G["Grid2LayoutFrame"] then return "Grid2" end
    if _G["SUFHeaderparty"] or _G["SUFUnitplayer"] then return "Shadowed Unit Frames" end
    if _G["NDui"] then return "NDui" end
    if _G["Vd1H1"] then return "VuhDo" end
    return "Blizzard Compact Party"
end
