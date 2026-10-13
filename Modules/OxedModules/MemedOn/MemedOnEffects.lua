-- MemedOn
-- Copyright (c) 2026 CorgiKane. All rights reserved.
--
-- Not licensed for redistribution, modification or reuse. The source is
-- readable because Blizzard's add-on policy requires it, which is not a
-- grant of any right to reuse it. See LICENSE.
-- ============================================================
--  MemedOnEffects
--  WoW Lua 5.1 â€” no goto, no bitwise ops
-- ============================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer

MEMEDON_EFFECTS = {}
OxedHub.MemedOnEffects = MEMEDON_EFFECTS

-- ---------------------------------------------------------------
-- Shared flash overlay
-- ---------------------------------------------------------------
local flashFrame = CreateFrame("Frame", "MemedOnFlashFrame", UIParent)
flashFrame:SetAllPoints(UIParent)
flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
local flashTex = flashFrame:CreateTexture(nil, "OVERLAY")
flashTex:SetAllPoints(flashFrame)
flashTex:SetColorTexture(1, 0.3, 0, 0)
flashFrame:SetAlpha(0)
flashFrame:Hide()

local flashTimer  = 0
local flashActive = false
flashFrame:SetScript("OnUpdate", function(self, elapsed)
    if not flashActive then return end
    flashTimer = flashTimer + elapsed
    local dur = 0.35
    if flashTimer >= dur then
        flashActive = false
        flashFrame:SetAlpha(0)
        flashFrame:Hide()
        return
    end
    local t = flashTimer / dur
    local alpha = (t < 0.3) and (t / 0.3 * 0.45) or ((1 - t) / 0.7 * 0.45)
    flashFrame:SetAlpha(alpha)
end)

local function DoFlash()
    flashFrame:Show()
    flashTimer  = 0
    flashActive = true
end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ===============================================================
-- Shared target list used by all effects
-- ===============================================================
local EXPLOSION_TARGETS = {
    "MinimapCluster",
    "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight",
    "MultiBarRight", "MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7",
    "StanceBar", "PetActionBar", "ExtraActionBar", "ZoneAbilityFrame",
    "OverrideActionBar", "PossessActionBar", "VehicleMenuBar",
    "MicroMenu", "MicroMenuContainer", "ContainerFrameContainer",
    "MicroButtonAndBagsBar", "MainMenuBarBackpackButton",
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame",
    "CastingBarFrame", "FocusFrameSpellBar", "TargetFrameSpellBar", "BossTargetFrameContainer",
    "BuffFrame", "DebuffFrame", "TemporaryEnchantFrame",
    "PartyFrame", "CompactRaidFrameContainer", "CompactRaidFrameManager",
    "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer",
    "BattlefieldMapFrame",
    "ObjectiveTrackerFrame", "DurabilityFrame", "TicketStatusFrame",
    -- ElvUI
    "ElvUI_Bar1", "ElvUI_Bar2", "ElvUI_Bar3", "ElvUI_Bar4", "ElvUI_Bar5",
    "ElvUI_Bar6", "ElvUI_Bar7", "ElvUI_Bar8", "ElvUI_Bar9", "ElvUI_Bar10",
    "ElvUI_Bar11", "ElvUI_Bar12", "ElvUI_Bar13", "ElvUI_Bar14", "ElvUI_Bar15",
    "ElvUI_BarPet", "ElvUI_StanceBar", "ElvUI_MicroBar",
    "ElvUF_Player", "ElvUF_Target", "ElvUF_Targettarget", "ElvUF_Focus",
    "ElvUF_Focustarget", "ElvUF_Pet", "ElvUF_Pettarget",
    "ElvUF_Boss1", "ElvUF_Boss2", "ElvUF_Boss3", "ElvUF_Boss4",
    "ElvUF_Arena1", "ElvUF_Arena2", "ElvUF_Arena3", "ElvUF_Arena4", "ElvUF_Arena5",
    "ElvUF_Party", "ElvUF_Raid", "ElvUF_Raid40",
    "ElvUI_ContainerFrame", "ElvUI_BankContainerFrame",
    "ElvUIPlayerBuffs", "ElvUIPlayerDebuffs",
    "ElvUI_ExperienceBarHolder", "ElvUI_ReputationBarHolder",
    "ElvUI_HonorBarHolder", "ElvUI_AzeriteBarHolder",
    "ElvUI_ExperienceBar", "ElvUI_ReputationBar", "ElvUI_HonorBar", "ElvUI_AzeriteBar",
    "ElvUI_ExtraActionBar",
    "ElvUI_TopPanel", "ElvUI_BottomPanel", "ElvUI_MinimapHolder",
    "LeftMiniPanel", "RightMiniPanel", "TopMiniPanel", "BottomMiniPanel",
    -- Bartender4
    "BT4Bar1", "BT4Bar2", "BT4Bar3", "BT4Bar4", "BT4Bar5",
    "BT4Bar6", "BT4Bar7", "BT4Bar8", "BT4Bar9", "BT4Bar10",
    "BT4Bar13", "BT4Bar14", "BT4Bar15",
    "BT4BarPetBar", "BT4BarStanceBar", "BT4BarMicroMenu",
    "BT4BarBagBar", "BT4BarStatus", "BT4BarExtraActionBar",
    "BT4BarVehicle", "BT4BarQueueStatus",
    -- Dominos
    "DominosFrame1", "DominosFrame2", "DominosFrame3", "DominosFrame4",
    "DominosFrame5", "DominosFrame6", "DominosFrame7", "DominosFrame8",
    "DominosFrame9", "DominosFrame10", "DominosFrame11", "DominosFrame12",
    "DominosFrame13", "DominosFrame14",
    "DominosFramepet", "DominosFrameclass", "DominosFramebags", "DominosFramemenu",
    "DominosFrameexp", "DominosFrameartifact", "DominosFramecast",
    "DominosFrameextra", "DominosFramepossess", "DominosFrameencounter", "DominosFramequeue",
    -- ArcHUD3
    "ArcHUDFrame", "ArcHUDFrameTargetHUD",
}

-- ---------------------------------------------------------------
-- Chat frame exclusion
-- ---------------------------------------------------------------
local chatExcluded = {}
local function BuildChatExclusions()
    wipe(chatExcluded)
    local chatFrames = {}
    for i = 1, NUM_CHAT_WINDOWS or 20 do
        local cf = _G["ChatFrame" .. i]
        if cf then chatFrames[#chatFrames + 1] = cf end
        local tab = _G["ChatFrame" .. i .. "Tab"]
        if tab then chatFrames[#chatFrames + 1] = tab end
    end
    for _, name in ipairs({
        "GeneralDockManager", "ChatAlertFrame", "QuickJoinToastButton",
        "ChatFrameMenuButton", "ChatFrameChannelButton",
        "LeftChatPanel", "RightChatPanel",
    }) do
        local f = _G[name]
        if f then chatFrames[#chatFrames + 1] = f end
    end
    for _, cf in ipairs(chatFrames) do chatExcluded[cf] = true end
    for _, cf in ipairs(chatFrames) do
        local parent = cf:GetParent()
        while parent and parent ~= UIParent do
            chatExcluded[parent] = true; parent = parent:GetParent()
        end
    end
    for _, cf in ipairs(chatFrames) do
        for p = 1, cf:GetNumPoints() do
            local _, relativeTo = cf:GetPoint(p)
            if relativeTo and relativeTo ~= UIParent then
                chatExcluded[relativeTo] = true
                local parent = relativeTo:GetParent()
                while parent and parent ~= UIParent do
                    chatExcluded[parent] = true; parent = parent:GetParent()
                end
            end
        end
    end
end
local chatExclusions_built = false
local function ShouldExcludeChat(frame)
    if not chatExclusions_built then
        BuildChatExclusions()
        chatExclusions_built = true
        C_Timer.After(0.1, function() chatExclusions_built = false end)
    end
    if chatExcluded[frame] then return true end
    local name = frame:GetName()
    if name and (name:find("Chat") or name:find("chat")) then return true end
    return false
end

-- Skip frames that are forbidden entirely, or protected frames WHILE in combat.
-- Protected EditMode frames (MainActionBar, unit frames, etc.) can still be
-- moved by insecure code OUT of combat — WoW only blocks them during combat.
-- Raw positioning, so moving an EDIT MODE frame never runs Edit Mode's code.
--
-- Edit Mode system frames -- action bars, unit frames, buffs, the tracker --
-- replace SetPoint / ClearAllPoints / SetScale with Lua overrides that do more than
-- position the frame. From Blizzard's EditModeSystemTemplates.lua:
--
--   SetPointOverride  -> SetPointBase, then SetSnappedToFrame, then
--                        EditModeManagerFrame:OnEditModeSystemAnchorChanged()
--   SetScaleOverride  -> SetScaleBase, then ManageFramePositions() and, for the
--                        right-managed frames, ObjectiveTrackerFrame:Update()
--
-- Calling the overrides from here runs all of that INSIDE MemedOn's execution, so
-- Edit Mode's anchor pipeline and the tracker update run tainted. That produced both
-- errors seen on WoW Forever:
--
--   * ADDON_ACTION_BLOCKED MultiBarBottomLeft:SetPointBase() -- Edit Mode's own
--     InitSystemAnchors pass, blocked because it was reached from tainted code
--   * "GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted" --
--     SetScaleOverride -> ObjectiveTrackerFrame:Update() -> the scenario tracker
--
-- It also explains the managed container stuck at -932.5: Edit Mode's layout pass
-- was being interrupted, so the container never got its real position back.
--
-- The *Base methods are the raw C setters the overrides wrap. They move the frame
-- and do nothing else -- no snap bookkeeping, no manager callback, no tracker
-- update -- so nothing of Blizzard's runs on our stack. Every restore puts the frame
-- back on exactly its captured points, so Edit Mode's own records stay correct.
--
-- Every frame has the *Base methods (they exist whether or not a frame is Edit Mode
-- managed), so these are used everywhere, not just for managed frames. The fallback
-- to the plain method is for a client that predates them.
-- GetTime() of the most recent frame movement of ANY kind -- every animation tick
-- and every restore goes through the raw setters below. The container pass waits
-- for this to go quiet, so it never puts a container back while an effect is still
-- moving the frames the game computes that container's position from.
local lastMoveAt = 0

local function RawClearPoints(frame)
    return pcall(frame.ClearAllPointsBase or frame.ClearAllPoints, frame)
end

local function RawSetPoint(frame, ...)
    lastMoveAt = GetTime()
    return pcall(frame.SetPointBase or frame.SetPoint, frame, ...)
end

local function RawSetScale(frame, scale)
    lastMoveAt = GetTime()
    return pcall(frame.SetScaleBase or frame.SetScale, frame, scale)
end

local function IsUnsafeToMove(frame)
    if not frame then return true end
    if frame.IsForbidden and frame:IsForbidden() then return true end
    if InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
        return true
    end
    return false
end

-- ---------------------------------------------------------------
-- Frame restoration system
--
-- Two cooperating tables:
--   homeAnchors[frame]  = { points = {...}, scale = N }   true home (points+scale)
--   pendingRestore[frame] = info                          queued for combat-end
--
-- The FIRST effect to touch a frame records its true home via CaptureHome.
-- Overlapping effects reuse that home instead of capturing an already-displaced
-- position/scale.  Three restore paths guarantee frames never stay stuck:
--   1. Effect finishes → TryRestore (immediate, or queue if combat-protected)
--   2. Combat ends (PLAYER_REGEN_ENABLED) → restore EVERY tracked frame from home
--   3. Settle ticker (~10s idle) → restore + clear, catching interrupted anims
-- ---------------------------------------------------------------
local pendingRestore = {}     -- [frame] = { savedPoints, origScale }
local homeAnchors = {}        -- [frame] = { points = {...}, scale = N, settled = bool }
local restoreTries = {}       -- [frame] = reconciler attempts since the last effect
local lastContainerTouch = 0  -- GetTime() of the last restore that disturbed a container
local lastEffectActivity = 0

-- A scale we can actually divide by and hand to SetScale. GetScale can return
-- nil, and on a client with secret values it can return one of those -- a secret
-- cannot even be compared, so the check has to detect it before the > 0 test.
-- Zero is the dangerous one: dividing by it yields inf, SetPoint(inf) fails
-- inside a pcall and leaves the frame cleared, and SetScale(0) is rejected, so
-- the size never comes back either.
local function ReadableScale(v)
    if v == nil then return nil end
    local isSecret = _G.issecretvalue
    if isSecret then
        local okS, secret = pcall(isSecret, v)
        if not okS or secret then return nil end
    end
    if type(v) ~= "number" or v <= 0 then return nil end
    return v
end

-- Several targets do not own their own position: ObjectiveTrackerFrame,
-- DurabilityFrame and TicketStatusFrame live inside UIParent's managed frame
-- containers, where the CONTAINER assigns each child's anchors from its
-- layoutIndex. Putting a captured point back on such a child does not restore it
-- -- the container's flow is still stale, and the next Layout() will overrule the
-- anchors anyway. So after restoring, ask the owning container to lay out again.
--
-- Collected and flushed once per frame rather than called per restore: a pass can
-- touch several children of the same container, and laying out once at the end is
-- both cheaper and the only way to get a stable result.
local pendingLayout = {}

-- Lay out only the containers we disturbed, and only once everything has stopped
-- moving. Both halves of that were learned the hard way:
--
--   * An earlier version also called UIParent_ManageFramePositions(), a whole-UI
--     reposition. Far blunter than the job needs, and RightManagedFrameContainer
--     was caught moving its own anchor from -105 to -932.5 on a client whose
--     layout differs from live. Only the containers we actually touched now.
--   * It also flushed on the frame after each restore, which can land while other
--     children of the same container are still mid-animation -- so the container
--     reflows around a broken state and the error compounds with every trigger.
--     That is the "works at first, fails on later ones" shape. The reconciler now
--     drives the flush, after its restore pass and only once effects have been
--     quiet for RESTORE_SETTLE.
-- Move a frame with no allocation.
--
-- Every effect ticker runs at 60Hz over ~20 frames, and each one used to wrap its
-- two calls in pcall(function() ... end) -- a fresh closure per frame per tick, so
-- roughly 1200 allocations a second, all of it garbage. That is the same pattern
-- already called out elsewhere in this file as the largest per-call allocator on a
-- hot path. Passing the METHOD to pcall keeps the protection and allocates nothing.
local function MoveTo(frame, point, relPoint, x, y)
    -- SetPoint only if the clear succeeded, which is what the single pcall around
    -- both calls used to guarantee. Setting a point onto anchors that were not
    -- cleared ADDS one rather than replacing it.
    if not RawClearPoints(frame) then return end
    RawSetPoint(frame, point, UIParent, relPoint, x, y)
end

-- A frame that lays out its children -- EXCEPT UIParent.
--
-- UIParent has a Layout method too, so a bare parent.Layout test was true for
-- nearly every target, and three things silently went wrong because of it: the
-- reconciler treated every UIParent child as a "managed child" and dropped it
-- unverified (its safety net was effectively off), the login snapshot captured
-- UIParent's own points as a "container", and the real right-hand container was
-- only tracked if one of its children happened to be a target.
local function IsLayoutContainer(frame)
    return frame ~= nil and frame ~= UIParent and frame.Layout ~= nil
end

local function QueueLayoutFor(frame)
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok or not parent then return end
    if not IsLayoutContainer(parent) then return end
    -- Recorded, not run. FlushLayouts is called by the reconciler.
    pendingLayout[parent] = true
    -- This container has been disturbed, so its snapshotted home needs asserting
    -- again. Only ever re-opened here -- never re-captured, because by now it has
    -- already moved.
    local home = homeAnchors[parent]
    if home then
        home.settled = nil
        restoreTries[parent] = nil
    end
    lastContainerTouch = GetTime()
end

-- The containers' OWN homes, snapshotted ONCE at login.
--
-- Moving a managed child makes the game recompute its container's position, and
-- nothing put that back, because the container is in no effect's target list.
-- Layout() cannot fix it either: that arranges the CHILDREN and resizes, it does
-- not restore the container's own anchor.
--
-- The first attempt captured the container lazily, the first time one of its
-- children was taken -- on the claim that this happened before anything had moved.
-- It does not. The capture runs per target frame, and Wow pins each frame inside
-- the same loop, so by the time the loop reaches a managed child its container has
-- already been shoved. That memorised a DISPLACED position as home, and the
-- reconciler then dutifully dragged the container back to it five seconds after
-- every effect -- measured going to TOPRIGHT@-1917 while the correct home, which
-- the effect had already restored, was -105.
--
-- So snapshot at login instead, when the layout is the game's own and no effect can
-- have run. If an effect somehow got in first, capture NOTHING: leaving the
-- container untracked is the old behaviour, whereas a wrong home actively breaks a
-- container that the effects had already put back correctly.
-- The managed containers, by name. Their position is the GAME's to compute --
-- the right-hand one from where the right action bars are -- and once the raw
-- setters stopped running Edit Mode's callbacks, nothing recomputed it after the
-- bars came home. If the game happened to recompute mid-effect, with the bars
-- displaced, the container stayed wherever that put it (measured: -932.6 and -1917
-- against its real spot; the objective tracker rides inside it).
local MANAGED_CONTAINERS = {
    "RightManagedFrameContainer", "UIParentRightManagedFrameContainer",
    "BottomManagedFrameContainer", "UIParentBottomManagedFrameContainer",
}

-- Capture each container's home at the START of an effect, before its target loop
-- has moved a single frame -- the one moment that is genuinely "nothing has moved
-- yet". (The login snapshot this replaces was taken once and could be wrong for
-- the whole session; capturing inside the loop was wrong because earlier frames in
-- the same loop had already shoved the container.)
--
-- Not recaptured while a restore is still pending: if a second effect fires before
-- the first has been put back, the container is displaced right now, and the home
-- from before the first effect is the one that is still true.
local function CaptureContainersBeforeEffect()
    local seen = {}
    for _, name in ipairs(MANAGED_CONTAINERS) do
        local c = _G[name]
        if c and not seen[c] then
            seen[c] = true
            local home = homeAnchors[c]
            if home == nil or home.settled then
                local okN, n = pcall(c.GetNumPoints, c)
                if okN and type(n) == "number" and n > 0 then
                    local pts = {}
                    for i = 1, n do
                        local okP, pt, rt, rp, ox, oy = pcall(c.GetPoint, c, i)
                        if okP then pts[#pts + 1] = { pt, rt, rp, ox, oy } end
                    end
                    local okS, sc = pcall(c.GetScale, c)
                    homeAnchors[c] = { points = pts, scale = okS and sc or nil,
                                       isContainer = true }
                    restoreTries[c] = nil
                end
            end
        end
    end
end

-- One pcall around the whole body meant a single SetPoint that threw left the
-- frame CLEARED and unanchored -- it then draws at its parent's corner, which
-- looks exactly like the effect never gave it back. Each step stands on its own
-- now, and a frame that loses every anchor is put somewhere visible rather than
-- nowhere.
local function DoRestore(frame, info)
    -- Scale first: the saved offsets are in the home scale's terms.
    local scale = ReadableScale(info.origScale)
    if scale then RawSetScale(frame, scale) end

    local pts = info.savedPoints
    if not pts then return end

    -- What the frame is anchored to RIGHT NOW, kept in case the restore fails.
    local before = {}
    local okN, n = pcall(frame.GetNumPoints, frame)
    if okN and type(n) == "number" then
        for i = 1, n do
            local okP, pt, rt, rp, ox, oy = pcall(frame.GetPoint, frame, i)
            if okP then before[#before + 1] = { pt, rt, rp, ox, oy } end
        end
    end

    if not RawClearPoints(frame) then return end

    local restored = 0
    for _, sp in ipairs(pts) do
        if RawSetPoint(frame, sp[1], sp[2], sp[3], sp[4], sp[5]) then
            restored = restored + 1
        end
    end

    -- Every point failed: put back what it had a moment ago. This used to send the
    -- frame to the exact centre of the screen instead, "so it is at least visible" --
    -- which is precisely the symptom of a frame (the objective tracker) jumping to the
    -- middle after an effect. Where it was is always a better answer than the middle,
    -- and the reconciler will try the real home again on its next pass.
    if restored == 0 and #pts > 0 then
        for _, sp in ipairs(before) do
            RawSetPoint(frame, sp[1], sp[2], sp[3], sp[4], sp[5])
        end
    end

    -- ANY restore arms the container pass, not only a restore of a container's own
    -- child. The right-hand container's position is computed by the game from where
    -- the right action bars are, and those are UIParent children -- so the container
    -- was displaced by frames that never led back to it.
    lastContainerTouch = GetTime()
    QueueLayoutFor(frame)
end

-- Try to restore now.  If the frame is unsafe (combat + protected), queue it
-- for restoration when combat ends.  origScale is optional (Wow effect uses it).
local function TryRestore(frame, savedPoints, origScale)
    if not frame or not savedPoints then return end
    -- The home record is the authority on scale, not the caller. Only Wow
    -- changes scale -- but ANY effect can be the one that finishes last on a
    -- frame Wow inflated, and those callers pass no scale, so the frame stayed
    -- oversized until the 10s settle pass happened to notice. Defaulting it here
    -- means every restore path puts the size back together with the position.
    if origScale == nil then
        local home = homeAnchors[frame]
        if home then origScale = home.scale end
    end
    local info = { savedPoints = savedPoints, origScale = origScale }
    if IsUnsafeToMove(frame) then
        pendingRestore[frame] = info
    else
        pendingRestore[frame] = nil
        DoRestore(frame, info)
    end
end

-- Capture (once) the frame's true home points AND scale.  Returns the points
-- array (used as savedPoints by effects) and the home scale.  Reusing the
-- first-captured values means overlapping effects never record an already-
-- displaced/scaled position as "home".
local function CaptureHome(frame)
    if not homeAnchors[frame] then
        local pts = {}
        for p = 1, frame:GetNumPoints() do
            local pt, rt, rp, ox, oy = frame:GetPoint(p)
            pts[p] = { pt, rt, rp, ox, oy }
        end
        homeAnchors[frame] = { points = pts, scale = frame:GetScale() }
    end
    -- A new effect is about to displace this frame again, so whatever verdict the
    -- reconciler reached last time no longer applies -- re-open it and reset the
    -- retry budget. The captured home itself is deliberately NOT re-taken; the
    -- first capture is the only one made while the frame was known to be home.
    homeAnchors[frame].settled = nil
    restoreTries[frame] = nil
    lastEffectActivity = GetTime()
    return homeAnchors[frame].points, homeAnchors[frame].scale
end

-- Is the frame's anchoring actually back at the home we captured?
--
-- This is the question the restore system never used to ask. It called
-- DoRestore once and dropped the frame from the table whether or not the call
-- had any effect -- so a restore that silently failed was indistinguishable
-- from one that worked, and the frame kept the effect's own pin for good.
-- Measured on the WoW Forever client: MultiBarBottomLeft sat on
-- "CENTER->UIParent.CENTER@-317.5,-63.5" -- the Wow effect's pin -- long after
-- everything had gone still, with its anchor never even cleared.
-- Lay out only the containers we disturbed, and only once everything has stopped
-- moving. Both halves of that were learned the hard way:
--
--   * An earlier version also called UIParent_ManageFramePositions(), a whole-UI
--     reposition -- far blunter than the job needs. Only the containers we
--     actually touched now.
--   * It also flushed on the frame after each restore, which can land while other
--     children of the same container are still mid-animation, so the container
--     reflows around a broken state and the error compounds with every trigger.
--     That is the "works at first, fails on later ones" shape. The reconciler
--     drives the flush now, after its restore pass.
--
-- Laying out can move the container itself, so its own home goes back on LAST.
local function FlushLayouts()
    for container in pairs(pendingLayout) do
        pendingLayout[container] = nil
        if container.Layout then pcall(container.Layout, container) end
        local home = homeAnchors[container]
        if home then
            DoRestore(container, { savedPoints = home.points, origScale = home.scale })
        end
    end
end

-- Do the frame's anchors match the home we captured? The real test, and the one
-- that has always been enough where the anchors do come back.
local function PointsMatchHome(frame, home)
    local okN, n = pcall(frame.GetNumPoints, frame)
    if not okN or n ~= #home.points then return false end
    for i = 1, n do
        local ok, pt, rt, rp, ox, oy = pcall(frame.GetPoint, frame, i)
        if not ok then return false end
        local want = home.points[i]
        if pt ~= want[1] or rt ~= want[2] or rp ~= want[3] then return false end
        -- Offsets are compared loosely: the client rounds them, and a restore
        -- that lands half a pixel out is a restore that worked.
        local okCmp, same = pcall(function()
            return math.abs((ox or 0) - (want[4] or 0)) <= 0.5
               and math.abs((oy or 0) - (want[5] or 0)) <= 0.5
        end)
        if not okCmp or not same then return false end
    end
    return true
end

local function AtHome(frame, home)
    -- Geometry first. This is the check the reconciler exists for, and routing
    -- around it for every container child would have quietly dropped the
    -- verification on clients where the anchors restore perfectly well.
    if PointsMatchHome(frame, home) then return true end

    -- There used to be a fallback here that called any frame under a layout
    -- container "home" once its container had been asked to lay out. It is gone,
    -- for two reasons:
    --   * managed CHILDREN are now skipped before AtHome is ever reached, so it
    --     was dead for them;
    --   * and it actively broke the CONTAINER, whose own parent is UIParent -- a
    --     layout frame -- so the container matched the fallback, was declared home
    --     while sitting at -932 instead of -105, and got parked instead of
    --     restored.
    -- Geometry is the only answer now, which is what the reconciler wants anyway.
    return false
end

-- Combat ended: every protected frame is movable again. Restore each tracked
-- frame to its authoritative home -- this catches frames displaced during
-- combat that never made it into the pending queue. homeAnchors is NOT wiped
-- here any more; the reconciler below drops each frame only once it has
-- verified the frame really is home.
local restoreEventFrame = CreateFrame("Frame")
restoreEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
restoreEventFrame:SetScript("OnEvent", function()
    for frame, home in pairs(homeAnchors) do
        DoRestore(frame, { savedPoints = home.points, origScale = home.scale })
    end
    -- Also flush any pending entries for frames not in homeAnchors (paranoia)
    for frame, info in pairs(pendingRestore) do
        if not homeAnchors[frame] then DoRestore(frame, info) end
    end
    wipe(pendingRestore)
end)

-- Reconciler: once the effects have stopped, keep asserting home until the
-- frame is measurably there.
--
-- SETTLE is past the longest effect (Explosion: up to 1.0s bounce + 2.0s hang
-- + 0.45s slide), so this never fights an animation, and chained effects push
-- it out via lastEffectActivity. ATTEMPTS bounds it: a frame the player is
-- moving themselves in Edit Mode will never match home, and this must give up
-- rather than drag it back forever.
local RESTORE_SETTLE   = 5.0
local RESTORE_ATTEMPTS = 10

-- CONTAINER PASS: fast, and only once everything has stopped moving.
--
-- The managed containers are positioned by the GAME, computed from where the bars
-- are. Two timing faults, both measured on the timeline:
--
--   * It used to ride the 1s reconciler, so after an effect the game had already
--     re-laid the right container out to about -932 (mid-screen, taking the
--     objective tracker with it) and it sat there for up to two seconds before
--     being put back. That lag is the tracker "going to the middle" after an effect.
--   * With overlapping effects it restored the container while another effect was
--     still moving the bars, the game immediately re-laid it out, and the container
--     (and tracker) flipped between middle and right every second.
--
-- So: check ten times a second, but only act once nothing has moved for QUIET
-- seconds -- by then every effect has finished and handed its frames back, so the
-- container goes home once, promptly, with nothing left to knock it out again.
local CONTAINER_QUIET = 0.35

C_Timer.NewTicker(0.1, function()
    if lastContainerTouch == 0 then return end
    local now = GetTime()
    if (now - lastMoveAt) < CONTAINER_QUIET then return end
    lastContainerTouch = 0
    for frame, home in pairs(homeAnchors) do
        if home.isContainer and not home.settled and not PointsMatchHome(frame, home) then
            local tries = (restoreTries[frame] or 0) + 1
            restoreTries[frame] = tries
            DoRestore(frame, { savedPoints = home.points, origScale = home.scale })
            -- DoRestore re-arms this pass, so a container the game keeps re-laying
            -- out would otherwise be restored forever.
            if tries >= RESTORE_ATTEMPTS then home.settled = true end
        end
    end
end)

C_Timer.NewTicker(1.0, function()
    if (GetTime() - lastEffectActivity) <= RESTORE_SETTLE then return end
    if not next(homeAnchors) then return end
    for frame, home in pairs(homeAnchors) do
        local okParent, parent = pcall(frame.GetParent, frame)
        if not home.isContainer and okParent and IsLayoutContainer(parent) then
            -- A frame inside a layout container is positioned BY the container,
            -- from its layoutIndex. Measured 2026-09-22: once the other children
            -- are home, the game's own layout puts both them and the container
            -- back -- caught landing on the correct -105 inside the effect batch.
            -- Re-asserting anchors the container is about to re-derive just fights
            -- the layout manager, once a second for up to ten seconds after every
            -- effect, which is what made the effects feel sluggish and kept
            -- knocking the container out of place. Hand it back and stop.
            homeAnchors[frame] = nil
            restoreTries[frame] = nil
        elseif home.settled then
            -- Verdict already reached for this effect; nothing to do until the
            -- next one calls CaptureHome and re-opens it.
        elseif AtHome(frame, home) then
            -- FORGETTING a home is the dangerous operation, not keeping one.
            -- CaptureHome only captures when there is no entry, so a dropped
            -- entry means the NEXT effect records wherever the frame happens to
            -- be as its new home -- and if it was still displaced, that
            -- displacement becomes permanent for every restore afterwards. A run
            -- of effects back to back is exactly the sequence that reaches it.
            -- So drop the entry only on strict geometric proof; every weaker
            -- answer parks the frame and keeps the home.
            if PointsMatchHome(frame, home) then
                homeAnchors[frame] = nil
                restoreTries[frame] = nil
            else
                home.settled = true
            end
        elseif not IsUnsafeToMove(frame) then
            local tries = (restoreTries[frame] or 0) + 1
            restoreTries[frame] = tries
            DoRestore(frame, { savedPoints = home.points, origScale = home.scale })
            if tries >= RESTORE_ATTEMPTS then
                -- Stop fighting -- the player may be moving it themselves -- but
                -- still do not forget where home was.
                home.settled = true
                restoreTries[frame] = nil
            end
        end
    end

end)

-- ===============================================================
-- EFFECT 1: Wobble
-- Moves individual frames from EXPLOSION_TARGETS instead of
-- UIParent so chat frames stay in place.
-- ===============================================================
local wobbleTicker = nil
local wobbleTimer  = 0
local wobbleTargets = nil

local function StopWobble()
    if wobbleTicker then wobbleTicker:Cancel(); wobbleTicker = nil end
    if wobbleTargets then
        for _, d in ipairs(wobbleTargets) do
            TryRestore(d.frame, d.savedPoints)
        end
        wobbleTargets = nil
    end
end

MEMEDON_EFFECTS["Wobble"] = {
    label = "Wobble",
    Run = function(intensity)
        if InCombatLockdown() then return end
        StopWobble()
        wobbleTimer = 0
        local amp = Clamp(intensity, 1, 100)

        -- Collect targets (same as other effects, with chat exclusion)
        local targets = {}
        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)
                local fx = f:GetLeft()
                local fy = f:GetBottom()
                if fx and fy then
                    targets[#targets + 1] = {
                        frame = f,
                        savedPoints = savedPoints,
                        origX = fx,
                        origY = fy,
                    }
                end
            end
        end
        wobbleTargets = targets

        if #targets == 0 then return end

        wobbleTicker = C_Timer.NewTicker(0.016, function()
            wobbleTimer = wobbleTimer + 0.016
            if wobbleTimer >= 2.5 then StopWobble(); return end
            if InCombatLockdown() then StopWobble(); return end
            local t   = wobbleTimer
            local env = amp * math.exp(-1.6 * t)
            local ox  = env * math.sin(t * 5 * math.pi * 2)
            local oy  = env * 0.5 * math.sin(t * 2.5 * math.pi * 2 + math.pi * 0.5)
            for _, d in ipairs(wobbleTargets) do
                if not IsUnsafeToMove(d.frame) then
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", d.origX + ox, d.origY + oy)
                end
            end
        end)
        DoFlash()
    end,
}

-- ===============================================================
-- EFFECT 2: Explosion
--
-- Each frame gets a random velocity vector. They fly outward,
-- bouncing with damped oscillation before settling, hang briefly,
-- then ease back home. All motion is simulated per-tick so frames
-- take different curved paths rather than snapping straight out.
-- ===============================================================
local explosionActive = false

MEMEDON_EFFECTS["Explosion"] = {
    label = "Explosion",
    Run = function(intensity)
        if explosionActive then return end
        if InCombatLockdown() then return end
        explosionActive = true

        local amp     = Clamp(intensity, 1, 100)
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        local cx      = screenW / 2
        local cy      = screenH / 2

        -- How long the bounce phase runs before we "hang" and restore
        local bounceT  = 0.6 + (amp / 100) * 0.4  -- 0.6â€“1.0s of movement (faster)
        local hangT    = 1.0 + (amp / 100) * 1.0  -- 1.0â€“2.0s hang at rest
        local restoreT = 0.45                       -- slide home duration

        local displaced = {}

        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                -- Save original anchors
                local savedPoints = CaptureHome(f)

                local fx = f:GetLeft()
                local fy = f:GetBottom()
                if fx and fy then
                    local fw = f:GetWidth()
                    local fh = f:GetHeight()

                    -- Pick a fully random target zone scattered across the screen.
                    -- Divide the screen into a 3x3 grid and pick a random cell
                    -- that is NOT the cell the frame currently sits in, so every
                    -- frame ends up in a different region.
                    local cellW = screenW / 3
                    local cellH = screenH / 3
                    local myCellX = math.floor(Clamp((fx + fw*0.5) / cellW, 0, 2))
                    local myCellY = math.floor(Clamp((fy + fh*0.5) / cellH, 0, 2))

                    -- Pick a random different cell
                    local targetCellX, targetCellY
                    local attempts = 0
                    repeat
                        targetCellX = math.floor(math.random() * 3)
                        targetCellY = math.floor(math.random() * 3)
                        attempts = attempts + 1
                    until (targetCellX ~= myCellX or targetCellY ~= myCellY) or attempts > 8

                    -- Random point within that target cell
                    local targetX = targetCellX * cellW + math.random() * cellW
                    local targetY = targetCellY * cellH + math.random() * cellH

                    -- Direction toward that random target
                    local dx = targetX - (fx + fw * 0.5)
                    local dy = targetY - (fy + fh * 0.5)
                    local len = math.sqrt(dx * dx + dy * dy)
                    if len < 10 then len = 10 end
                    dx = dx / len
                    dy = dy / len

                    -- Speed scaled to distance â€” higher multiplier = faster travel
                    local speed = (len * 1.8) * (amp / 100) * (0.9 + math.random() * 0.3)
                    -- Moderate spin for path curvature
                    local spin  = (math.random() - 0.5) * speed * 0.8

                    local vx = dx * speed + (-dy) * spin
                    local vy = dy * speed + dx     * spin

                    -- Frequency and decay tuned for fast travel then clean stop
                    local freq  = 1.5 + math.random() * 2.0   -- 1.5â€“3.5 Hz
                    local decay = 3.5 + math.random() * 1.5   -- faster settle at destination

                    displaced[#displaced + 1] = {
                        frame       = f,
                        savedPoints = savedPoints,
                        origX       = fx,
                        origY       = fy,
                        -- current simulated position
                        curX        = fx,
                        curY        = fy,
                        vx          = vx,
                        vy          = vy,
                        freq        = freq,
                        decay       = decay,
                        -- we'll store the "landed" position for the hang phase
                        landX       = fx,
                        landY       = fy,
                    }
                end
            end
        end

        DoFlash()

        if #displaced == 0 then
            explosionActive = false
            return
        end

        -- â”€â”€ Phase 1: Bouncy physics simulation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        local phaseTimer = 0
        local dt         = 0.016

        C_Timer.NewTicker(dt, function(bounceTicker)
            phaseTimer = phaseTimer + dt

            for _, d in ipairs(displaced) do
                -- Damped oscillation on top of the velocity:
                -- position = orig + velocity*t * envelope + oscillation
                local t    = phaseTimer
                local env  = math.exp(-d.decay * t)

                -- Primary travel: velocity integrated with exponential slowdown
                local travelX = d.vx * t * math.exp(-d.decay * 0.5 * t)
                local travelY = d.vy * t * math.exp(-d.decay * 0.5 * t)

                -- Secondary oscillation: bigger lateral wobble, slower decay
                local wobbleAmp = (math.abs(d.vx) + math.abs(d.vy)) * 0.18 * env
                local wobbleX   = wobbleAmp * math.sin(t * d.freq * math.pi * 2)
                local wobbleY   = wobbleAmp * math.cos(t * d.freq * math.pi * 2 + math.pi * 0.5)

                local newX = d.origX + travelX + wobbleX
                local newY = d.origY + travelY + wobbleY

                -- Clamp to screen so frames bounce off edges visually
                local margin = 30
                newX = Clamp(newX, -d.frame:GetWidth()  + margin, screenW - margin)
                newY = Clamp(newY, -d.frame:GetHeight() + margin, screenH - margin)

                d.landX = newX
                d.landY = newY

                if not IsUnsafeToMove(d.frame) then
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", newX, newY)
                end
            end

            if phaseTimer >= bounceT then
                bounceTicker:Cancel()

                -- â”€â”€ Phase 2: Hang at landed position â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                C_Timer.After(hangT, function()

                    -- â”€â”€ Phase 3: Ease back home â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    local restoreTimer = 0
                    C_Timer.NewTicker(dt, function(restoreTicker)
                        restoreTimer = restoreTimer + dt
                        local t2   = Clamp(restoreTimer / restoreT, 0, 1)
                        -- Ease out cubic
                        local ease = 1 - (1 - t2) * (1 - t2) * (1 - t2)

                        for _, d in ipairs(displaced) do
                            local rx = d.landX + (d.origX - d.landX) * ease
                            local ry = d.landY + (d.origY - d.landY) * ease
                            if not IsUnsafeToMove(d.frame) then
                                MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", rx, ry)
                            end
                        end

                        if t2 >= 1 then
                            restoreTicker:Cancel()
                            -- Restore original anchors exactly
                            for _, d in ipairs(displaced) do
                                TryRestore(d.frame, d.savedPoints)
                            end
                            explosionActive = false
                        end
                    end)
                end)
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 3: Blackhole
-- Frames spiral inward in a rotating arc, accelerating toward
-- the screen centre, then burst back out to their original spots.
-- ===============================================================
local blackholeActive = false

MEMEDON_EFFECTS["Blackhole"] = {
    label = "Blackhole",
    Run = function(intensity)
        if blackholeActive then return end
        if InCombatLockdown() then return end
        blackholeActive = true

        local amp     = Clamp(intensity, 1, 100)
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        local cx      = screenW / 2
        local cy      = screenH / 2

        -- Phase durations
        local suckT    = 0.8 + (amp / 100) * 0.7  -- 0.8â€“1.5s spiral inward
        local holdT    = 0.15                        -- brief hold at centre
        local burstT   = 0.4                         -- snap back out

        local targets = {}

        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)

                local fx = f:GetLeft()
                local fy = f:GetBottom()
                if fx and fy then
                    local fw = f:GetWidth()
                    local fh = f:GetHeight()

                    -- Starting position relative to centre
                    local startX = fx - cx
                    local startY = fy - cy
                    local startDist = math.sqrt(startX * startX + startY * startY)
                    if startDist < 1 then startDist = 1 end

                    -- Starting angle (atan2 gives angle in radians)
                    local startAngle = math.atan2(startY, startX)

                    -- Each frame gets a slightly different spin rate so they
                    -- don't all rotate in lockstep â€” offset by position
                    local spinDir = ((math.floor(startAngle * 2) % 2 == 0) and 1 or -1)
                    local spinSpeed = (2.5 + (amp / 100) * 2.0) * spinDir  -- radians/sec

                    targets[#targets + 1] = {
                        frame       = f,
                        savedPoints = savedPoints,
                        origX       = fx,
                        origY       = fy,
                        startDist   = startDist,
                        startAngle  = startAngle,
                        spinSpeed   = spinSpeed,
                    }
                end
            end
        end

        DoFlash()

        if #targets == 0 then
            blackholeActive = false
            return
        end

        -- â”€â”€ Phase 1: Spiral inward â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        local phaseTimer = 0
        local dt = 0.016

        C_Timer.NewTicker(dt, function(suckTicker)
            phaseTimer = phaseTimer + dt
            local t    = Clamp(phaseTimer / suckT, 0, 1)

            -- Ease in cubic â€” slow start, accelerates toward centre
            local easeIn = t * t * t

            for _, d in ipairs(targets) do
                -- Shrink radius toward zero
                local radius = d.startDist * (1 - easeIn)

                -- Angle increases over time (spinning), plus extra spin as
                -- radius shrinks (like water draining â€” faster near centre)
                local extraSpin = easeIn * 3.0 * (d.spinSpeed > 0 and 1 or -1)
                local angle = d.startAngle + (d.spinSpeed + extraSpin) * phaseTimer

                -- Current position = centre + polar coords
                local newX = cx + radius * math.cos(angle) - d.frame:GetWidth()  * 0.5
                local newY = cy + radius * math.sin(angle) - d.frame:GetHeight() * 0.5

                if not IsUnsafeToMove(d.frame) then
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", newX, newY)
                end
            end

            if t >= 1 then
                suckTicker:Cancel()

                -- â”€â”€ Phase 2: Hold at centre briefly â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                C_Timer.After(holdT, function()

                    -- â”€â”€ Phase 3: Burst back to original positions â”€â”€â”€â”€â”€
                    local restoreTimer = 0
                    C_Timer.NewTicker(dt, function(burstTicker)
                        restoreTimer = restoreTimer + dt
                        local t2   = Clamp(restoreTimer / burstT, 0, 1)
                        -- Ease out â€” fast exit from centre, decelerates home
                        local ease = 1 - (1 - t2) * (1 - t2) * (1 - t2)

                        for _, d in ipairs(targets) do
                            -- Burst outward from centre along original direction
                            local destX = cx + (d.origX - cx) * ease
                            local destY = cy + (d.origY - cy) * ease
                            if not IsUnsafeToMove(d.frame) then
                                MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", destX, destY)
                            end
                        end

                        if t2 >= 1 then
                            burstTicker:Cancel()
                            -- Restore all original anchors
                            for _, d in ipairs(targets) do
                                TryRestore(d.frame, d.savedPoints)
                            end
                            blackholeActive = false
                        end
                    end)
                end)
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 4: Rickroll
-- Tuned to the actual Rick-Rolled.mp3 clip:
--   Total duration: 9.04s (audio), dance ends at 6.04s
--   Intro silence:  0.302s (frames barely move)
--   Groove starts:  ~0.929s in (beat kicks in properly)
--   BPM:            109.5 (beat every 0.548s)
--   Bars:           8 bars of 4/4
--   Fade out:       last 0.6s of dance window
-- ===============================================================
local rickrollActive = false

MEMEDON_EFFECTS["Rickroll"] = {
    label = "Rickroll",
    Run = function(intensity)
        if rickrollActive then return end
        if InCombatLockdown() then return end
        rickrollActive = true

        local amp = Clamp(intensity, 1, 100)
        local screenW = UIParent:GetWidth()

        -- Dance window trimmed 3s shorter than full clip to match music feel
        local clipDuration  = 6.04   -- stop dancing here (audio continues briefly)
        local introEnd      = 0.929  -- when the groove properly kicks in
        local fadeStart     = 5.44   -- start fading 0.6s before dance end
        local bps           = 109.5 / 60  -- beats per second

        local swayAmp   = (amp / 100) * 30
        local bounceAmp = (amp / 100) * 16
        local dt        = 0.016

        local dancers = {}

        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)
                local fx = f:GetLeft()
                local fy = f:GetBottom()
                if fx and fy then
                    -- Chorus-line ripple: phase offset by horizontal position
                    local phaseOffset = (fx / screenW) * math.pi * 1.2
                    dancers[#dancers + 1] = {
                        frame       = f,
                        savedPoints = savedPoints,
                        origX       = fx,
                        origY       = fy,
                        phaseOffset = phaseOffset,
                    }
                end
            end
        end

        DoFlash()

        if #dancers == 0 then
            rickrollActive = false
            return
        end

        local danceTimer = 0

        C_Timer.NewTicker(dt, function(ticker)
            danceTimer = danceTimer + dt

            -- Slow ramp-in during intro (0 â†’ 1 over the first 0.929s)
            local rampIn = Clamp(danceTimer / introEnd, 0, 1)
            rampIn = rampIn * rampIn  -- ease in quadratic

            -- Fade out in last 0.6s
            local fadeOut = 1.0
            if danceTimer >= fadeStart then
                fadeOut = Clamp((clipDuration - danceTimer) / (clipDuration - fadeStart), 0, 1)
                fadeOut = fadeOut * fadeOut
            end

            local envelope = rampIn * fadeOut

            for _, d in ipairs(dancers) do
                -- Beat angle: advances at exact BPM
                local t = danceTimer * bps * math.pi * 2

                -- Main sway: left-right at beat tempo + half-speed body roll
                local sway = swayAmp * envelope * (
                    math.sin(t + d.phaseOffset) * 0.65 +
                    math.sin(t * 0.5 + d.phaseOffset + math.pi * 0.25) * 0.35
                )

                -- Bounce: rises on the off-beat, abs() keeps it always upward
                local bounce = bounceAmp * envelope * math.abs(math.sin(t + d.phaseOffset))

                -- Shimmy: fast shoulder-shake overlay at 4Ã— beat
                local shimmy = (swayAmp * 0.12) * envelope * math.sin(t * 4 + d.phaseOffset)

                if not IsUnsafeToMove(d.frame) then
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT",
                        d.origX + sway + shimmy, d.origY + bounce)
                end
            end

            if danceTimer >= clipDuration then
                ticker:Cancel()
                for _, d in ipairs(dancers) do
                    TryRestore(d.frame, d.savedPoints)
                end
                rickrollActive = false
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 5: Wow
-- Frames scale up in place using SetScale. To keep each frame
-- centred we pin it once to CENTER of UIParent (captured at
-- setup), then only change SetScale each tick â€” no per-tick
-- anchor math needed. SetScale grows symmetrically around the
-- CENTER anchor automatically.
-- Outer frames pop last (ripple converges inward).
-- Timing: riseT=0.12  holdT=0.05  fallT=0.22  settleT=0.10
-- ===============================================================
local wowActive = false

MEMEDON_EFFECTS["Wow"] = {
    label = "Wow",
    Run = function(intensity)
        if wowActive then return end
        if InCombatLockdown() then return end
        wowActive = true

        local amp = Clamp(intensity, 1, 100)
        local dt  = 0.016

        -- Peak scale: intensity 1 -> 1.15x, intensity 100 -> 1.60x
        local peakScale = 1.15 + (amp / 100) * 0.45

        local riseT   = 0.12
        local holdT   = 0.05
        local fallT   = 0.22
        local settleT = 0.10
        local totalT  = riseT + holdT + fallT + settleT

        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        local cx      = screenW / 2
        local cy      = screenH / 2
        local maxDist = math.sqrt(cx * cx + cy * cy)
        if maxDist < 1 then maxDist = 1 end
        local maxDelay = 0.16

        local targets = {}

        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                -- Use the HOME scale (not the current scale) so an overlapping
                -- Wow effect restores to the true original size, not a displaced one.
                local savedPoints, origScale = CaptureHome(f)
                -- Every use of origScale below is a divisor or a SetScale factor,
                -- so a frame whose scale cannot be read is skipped outright rather
                -- than moved with arithmetic that cannot be undone.
                origScale = ReadableScale(origScale)
                local fw = f:GetWidth()
                local fh = f:GetHeight()
                local fl = f:GetLeft()
                local fb = f:GetBottom()

                if origScale and fl and fb and fw and fh and fw > 0 and fh > 0 then
                    -- The CENTER offset from UIParent's centre, in THIS FRAME'S units
                    -- -- the units an anchor offset is measured in.
                    --
                    -- GetLeft/GetWidth already return the frame's own units, so the
                    -- frame's centre is simply fl + fw/2. UIParent's centre (cx) is in
                    -- UIParent's units and has to be converted across by the ratio of
                    -- effective scales. The old version divided the frame's own
                    -- numbers by origScale instead, which is only right when the
                    -- scale is 1 -- so any bar resized in Edit Mode was pinned off
                    -- target before the effect even started.
                    local okE, uiEff = pcall(UIParent.GetEffectiveScale, UIParent)
                    local okF, fEff  = pcall(f.GetEffectiveScale, f)
                    uiEff = ReadableScale(okE and uiEff or nil)
                    fEff  = ReadableScale(okF and fEff or nil)
                    local ratio = (uiEff and fEff) and (uiEff / fEff) or 1
                    local offX = (fl + fw * 0.5) - cx * ratio
                    local offY = (fb + fh * 0.5) - cy * ratio

                    local dist = math.sqrt(offX * offX + offY * offY)
                    local delay = (dist / maxDist) * maxDelay

                    MoveTo(f, "CENTER", "CENTER", offX, offY)

                    targets[#targets + 1] = {
                        frame       = f,
                        savedPoints = savedPoints,
                        origScale   = origScale,
                        offX        = offX,
                        offY        = offY,
                        timer       = -delay,
                        done        = false,
                    }
                end
            end
        end

        DoFlash()

        if #targets == 0 then
            wowActive = false
            return
        end

        C_Timer.NewTicker(dt, function(ticker)
            local anyRunning = false

            for _, d in ipairs(targets) do
                if not d.done then
                    d.timer = d.timer + dt

                    if d.timer < 0 then
                        anyRunning = true
                    else
                        local t     = d.timer
                        local scale = 1.0

                        if t < riseT then
                            local p   = t / riseT
                            local inv = 1 - p
                            scale = 1.0 + (peakScale - 1.0) * (1 - inv * inv * inv * inv * inv)

                        elseif t < riseT + holdT then
                            scale = peakScale

                        elseif t < riseT + holdT + fallT then
                            local p  = (t - riseT - holdT) / fallT
                            local ov = (peakScale - 1.0) * 0.28
                            scale = 1.0
                                + (peakScale - 1.0) * (1 - p) * (1 - p)
                                - ov * math.exp(-7 * p) * math.cos(math.pi * 2.2 * p)

                        elseif t < totalT then
                            local p    = (t - riseT - holdT - fallT) / settleT
                            local ring = 0.016 * (peakScale - 1.0) / 0.45
                            scale = 1.0 + ring * math.exp(-8 * p) * math.cos(math.pi * 4 * p)

                        else
                            -- PARK, do not restore. Each frame finishes at its own time
                            -- (the ripple delay), and the action bars are anchored to
                            -- EACH OTHER -- bar 2 hangs off the main bar, bar 3 off bar 2.
                            -- Handing a frame its real anchors the moment it finished put
                            -- it back onto a neighbour that was still scaled up, so it
                            -- landed in the wrong place and then jumped again when that
                            -- neighbour finished. Parking holds it at exactly its home
                            -- position and size while still pinned to the screen centre,
                            -- which looks identical, and the anchors all go back at once
                            -- below, when nothing in the chain is still moving.
                            if not IsUnsafeToMove(d.frame) then
                                RawSetScale(d.frame, d.origScale)
                                if RawClearPoints(d.frame) then
                                    RawSetPoint(d.frame, "CENTER", UIParent, "CENTER", d.offX, d.offY)
                                end
                            end
                            d.done = true
                        end

                        if not d.done then
                            -- Grow IN PLACE. An anchor offset is measured in the frame's
                            -- own scale, so scaling the frame by k also stretches its
                            -- offset by k and the frame slides outward from the screen's
                            -- centre instead of popping where it stands. Edit Mode's
                            -- SetScaleOverride quietly corrected that for the managed
                            -- frames (offset * oldScale / newScale); the raw SetScaleBase
                            -- we now use -- to stay out of Edit Mode's tainted pipeline --
                            -- does not, so the correction is ours: pin at offset / k.
                            -- It is computed from the original offset every tick rather
                            -- than adjusted incrementally, so no error accumulates.
                            if not IsUnsafeToMove(d.frame) and scale > 0 then
                                RawSetScale(d.frame, d.origScale * scale)
                                if RawClearPoints(d.frame) then
                                    RawSetPoint(d.frame, "CENTER", UIParent, "CENTER",
                                        d.offX / scale, d.offY / scale)
                                end
                            end
                            anyRunning = true
                        end
                    end
                end
            end

            if not anyRunning then
                ticker:Cancel()
                -- Every frame is parked at home by now, so restoring the whole set in
                -- one pass gives the chained bars back their real anchors with nothing
                -- visibly moving.
                for _, d in ipairs(targets) do
                    TryRestore(d.frame, d.savedPoints, d.origScale)
                end
                wowActive = false
            end
        end)
    end,
}

-- ===============================================================
-- ===============================================================
-- EFFECT 7: Tilt
-- Simulates the UI tilting upward from the right side towards the left,
-- like a page lifting from its right edge. Frames further right rise
-- more, frames on the left stay mostly in place.
--
-- Uses pure position offsets only (no SetScale) to avoid coordinate drift.
--
-- Tuned to nioce.mp3 â€” total 2.87s:
--   tiltIn  = 0.18s   snap into tilt
--   holdT   = 2.20s   hold at full tilt
--   snapOut = 0.25s   elastic snap back
--   settleT = 0.24s   settle wobble
-- ===============================================================
local tiltActive = false

MEMEDON_EFFECTS["Tilt"] = {
    label = "Tilt",
    Run = function(intensity)
        if tiltActive then return end
        if InCombatLockdown() then return end
        tiltActive = true

        local amp     = Clamp(intensity, 1, 100)
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        local dt      = 0.016

        -- Max vertical displacement at the right edge (intensity 1=25px, 100=80px)
        local maxDisp = 25 + (amp / 100) * 55

        -- Timing tuned to nioce.mp3 (2.87s total)
        local tiltIn  = 0.18
        local holdT   = 2.20
        local snapOut = 0.25
        local settleT = 0.24
        local totalT  = tiltIn + holdT + snapOut + settleT

        local targets = {}

        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)

                local fx = f:GetLeft()
                local fy = f:GetBottom()
                local fw = f:GetWidth()
                local fh = f:GetHeight()

                if fx and fy and fw and fh and fw > 0 and fh > 0 then
                    -- How far right is this frame's centre (0 = left edge, 1 = right edge)
                    local frameCX = fx + fw * 0.5
                    local t01 = frameCX / screenW  -- 0..1

                    -- Displacement is purely vertical (upward), proportional to
                    -- how far right the frame is. Left-side frames barely move.
                    local fullDispY = maxDisp * t01

                    targets[#targets + 1] = {
                        frame      = f,
                        savedPoints= savedPoints,
                        origX      = fx,
                        origY      = fy,
                        fullDispY  = fullDispY,
                        timer      = 0,
                        done       = false,
                    }
                end
            end
        end

        DoFlash()

        if #targets == 0 then
            tiltActive = false
            return
        end

        C_Timer.NewTicker(dt, function(ticker)
            local anyRunning = false

            for _, d in ipairs(targets) do
                if not d.done then
                    d.timer = d.timer + dt
                    local t   = d.timer
                    local env = 0

                    if t < tiltIn then
                        -- Ease-out quart snap into tilt
                        local p = t / tiltIn
                        local q = 1 - p
                        env = 1 - q * q * q * q

                    elseif t < tiltIn + holdT then
                        -- Hold with tiny organic sway so it feels alive
                        local p = (t - tiltIn) / holdT
                        env = 1.0 + 0.04 * math.sin(p * math.pi * 2.5)

                    elseif t < tiltIn + holdT + snapOut then
                        -- Elastic snap back with overshoot
                        local p = (t - tiltIn - holdT) / snapOut
                        env = (1 - p) * (1 - p)
                            - 0.30 * math.exp(-8 * p) * math.cos(math.pi * 2.5 * p)

                    elseif t < totalT then
                        -- Settle: decaying wobble around zero
                        local p = (t - tiltIn - holdT - snapOut) / settleT
                        env = 0.07 * math.exp(-9 * p) * math.cos(math.pi * 4 * p)

                    else
                        -- Park at the starting spot, anchors back later -- same reason
                        -- as Wow: the bars are anchored to each other and finish at
                        -- different times, so restoring one onto a neighbour that is
                        -- still tilted lands it in the wrong place and makes it jump.
                        if not IsUnsafeToMove(d.frame) then
                            MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", d.origX, d.origY)
                        end
                        d.done = true
                    end

                    if not d.done then
                        local nx = d.origX
                        local ny = d.origY + d.fullDispY * env
                        if not IsUnsafeToMove(d.frame) then
                            MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", nx, ny)
                        end
                        anyRunning = true
                    end
                end
            end

            if not anyRunning then
                ticker:Cancel()
                -- Everything is parked at home, so the whole chain gets its real
                -- anchors back in one pass with nothing visibly moving.
                for _, d in ipairs(targets) do
                    TryRestore(d.frame, d.savedPoints)
                end
                tiltActive = false
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 7: Earthquake (OxedHub Original)
-- ===============================================================
local earthquakeActive = false
MEMEDON_EFFECTS["Earthquake"] = {
    label = "Earthquake",
    Run = function(intensity)
        if earthquakeActive then return end
        if InCombatLockdown() then DoFlash(); return end
        earthquakeActive = true

        local amp = Clamp(intensity or 70, 1, 100) * 0.45
        local targets = {}
        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)
                local fx, fy = f:GetLeft(), f:GetBottom()
                if fx and fy then
                    targets[#targets + 1] = {
                        frame = f,
                        savedPoints = savedPoints,
                        origX = fx,
                        origY = fy,
                    }
                end
            end
        end

        DoFlash()
        if #targets == 0 then earthquakeActive = false; return end

        local timer = 0
        local dur = 1.2
        local ticker
        ticker = C_Timer.NewTicker(0.016, function()
            timer = timer + 0.016
            if timer >= dur or InCombatLockdown() then
                ticker:Cancel()
                for _, d in ipairs(targets) do
                    TryRestore(d.frame, d.savedPoints)
                end
                earthquakeActive = false
                return
            end
            local decay = (1 - timer / dur)
            local currentAmp = amp * decay
            for _, d in ipairs(targets) do
                if not IsUnsafeToMove(d.frame) then
                    local ox = (math.random() * 2 - 1) * currentAmp
                    local oy = (math.random() * 2 - 1) * currentAmp
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", d.origX + ox, d.origY + oy)
                end
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 8: Glitch (OxedHub Original)
-- ===============================================================
local glitchActive = false
MEMEDON_EFFECTS["Glitch"] = {
    label = "Glitch",
    Run = function(intensity)
        if glitchActive then return end
        if InCombatLockdown() then DoFlash(); return end
        glitchActive = true

        local amp = Clamp(intensity or 70, 1, 100) * 0.6
        local targets = {}
        CaptureContainersBeforeEffect()
        for _, name in ipairs(EXPLOSION_TARGETS) do
            local f = _G[name]
            if f and f:IsShown() and not ShouldExcludeChat(f) and not IsUnsafeToMove(f) then
                local savedPoints = CaptureHome(f)
                local fx, fy = f:GetLeft(), f:GetBottom()
                if fx and fy then
                    targets[#targets + 1] = {
                        frame = f,
                        savedPoints = savedPoints,
                        origX = fx,
                        origY = fy,
                    }
                end
            end
        end

        DoFlash()
        if #targets == 0 then glitchActive = false; return end

        local timer = 0
        local dur = 0.8
        local ticker
        ticker = C_Timer.NewTicker(0.032, function()
            timer = timer + 0.032
            if timer >= dur or InCombatLockdown() then
                ticker:Cancel()
                for _, d in ipairs(targets) do
                    TryRestore(d.frame, d.savedPoints)
                end
                glitchActive = false
                return
            end
            local step = math.floor(timer * 25)
            local isJolt = (step % 2 == 0)
            local decay = (1 - timer / dur)
            for _, d in ipairs(targets) do
                if not IsUnsafeToMove(d.frame) then
                    local ox = isJolt and ((math.random() > 0.5 and 1 or -1) * amp * decay) or 0
                    local oy = isJolt and ((math.random() > 0.5 and 0.5 or -0.5) * amp * decay * 0.4) or 0
                    MoveTo(d.frame, "BOTTOMLEFT", "BOTTOMLEFT", d.origX + ox, d.origY + oy)
                end
            end
        end)
    end,
}

-- ===============================================================
-- EFFECT 9: None
-- ===============================================================
MEMEDON_EFFECTS["None"] = {
    label = "None",
    Run = function(intensity)
        DoFlash()
    end,
}

MEMEDON_EFFECTS_LIST = { "Wobble", "Explosion", "Blackhole", "Rickroll", "Wow", "Tilt", "Earthquake", "Glitch", "None" }
OxedHub.MEMEDON_EFFECTS_LIST = MEMEDON_EFFECTS_LIST

