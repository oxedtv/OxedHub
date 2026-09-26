-- ============================================================================
-- Auto Queue (built-in OxedHub module)
-- Takes the waiting out of the Dungeon Finder and the Group Finder:
--
--   * Role checks are answered at once, with the roles you picked or, with
--     none picked, the role of your current specialisation.
--   * "Your group is ready" is called out with a sound; pressing Enter is
--     yours to do, since the game refuses it to addons.
--   * The Group Finder's sign-up dialog confirms itself with those roles;
--     double-click a listing to sign up to it.
--   * Groups that declined you show red in the list for 15 minutes, groups
--     that were delisted or filled show orange, and you may apply again.
--   * The listing tooltip gets back the "created ... ago" line, and your
--     sign-up note is kept from one application to the next.
--   * A role bar above the Group Finder window picks the roles to queue as
--     (several at once, or not your spec's). Roles are saved per character.
--
-- Everything is a switch in Options. Slash command: /aq on | off | status.
--
-- Taint notes -- read before changing anything here:
--   * ⚠ Entering the dungeon when the group is ready CANNOT be done for the
--     player: every route ends in AcceptProposal, which is protected, and each
--     attempt fills their error window with ADDON_ACTION_BLOCKED. The module
--     only calls the window out with a sound. Never add a press back.
--   * "Apply again" removes the group from LFGListFrame.declines, a Blizzard
--     table. It leaves that key tainted; nothing else in the list reads it.
--   * "Keep my note" replaces LFGListApplicationDialog_Show with the same code
--     minus the line that clears the note (the note box refuses SetText from
--     addons, so this is the only way). Compare with Blizzard's LFGList.lua
--     after each patch: it is the first suspect if Group Finder taint shows up.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled        = false,  -- off until the player switches it on (see ModuleAPI:Register)
    roleCheck      = true,   -- answer Dungeon Finder role checks
    acceptProposal = true,   -- call out "your group is ready"
    autoSignUp     = true,   -- confirm the Group Finder sign-up dialog
    shiftNote      = true,   -- holding Shift opens the dialog to write a note instead
    doubleClick    = true,   -- double-click a listing to sign up
    colorDeclined  = true,   -- red / orange listings that turned you down
    reapply        = true,   -- allow applying again to those groups
    groupAge       = true,   -- "created ... ago" in the listing tooltip
    keepNote       = true,   -- keep the sign-up note between applications
    roleBar        = true,   -- the role picker above the Group Finder window
    report         = true,   -- "Signed up as: ..." in chat
    -- UI state, not options
    roleBarHidden  = false,
    tutorialSeen   = false,
}

local settings          -- OxedHubDB.modules.autoqueue, bound at login
local optionsWindow
local watcher = CreateFrame("Frame")

local PREFIX = "|cff00ff00OxedHub:|r "
local issecretvalue = issecretvalue or function() return false end
local canaccesstable = canaccesstable or function() return true end

local function Active(option)
    return settings and settings.enabled == true and (option == nil or settings[option] ~= false)
end

-- ── Roles ───────────────────────────────────────────────────────────────────
-- Picked roles are per character (a tank alt and a healer main share one
-- account), kept in settings.roles["Name-Realm"]. Created here, never in
-- DEFAULTS (see CLAUDE.md).

local function CharacterKey()
    local name, realm = UnitFullName("player")
    return (name or "?") .. "-" .. (realm or GetRealmName() or "?")
end

local function PickedRoles()
    settings.roles = type(settings.roles) == "table" and settings.roles or {}
    local key = CharacterKey()
    local picked = settings.roles[key]
    if type(picked) ~= "table" then
        picked = { tank = false, healer = false, dps = false }
        -- Someone moving over from the stand-alone AutoQueue keeps their pick.
        local old = AutoAcceptQueueCharDB and AutoAcceptQueueCharDB.roleOverride
        if type(old) == "table" then
            picked.tank, picked.healer, picked.dps = old.tank == true, old.healer == true, old.dps == true
        end
        settings.roles[key] = picked
    end
    return picked
end

local function SpecRole()
    local index = GetSpecialization and GetSpecialization()
    if not index then return "DAMAGER" end
    return GetSpecializationRole(index) or "DAMAGER"
end

-- tank, healer, dps: the picked roles, or the spec's role when none is picked.
local function QueueRoles()
    local picked = PickedRoles()
    if picked.tank or picked.healer or picked.dps then
        return picked.tank, picked.healer, picked.dps
    end
    local role = SpecRole()
    return role == "TANK", role == "HEALER", role == "DAMAGER"
end

local function AvailableRoles()
    local available = { tank = false, healer = false, dps = false }
    for i = 1, (GetNumSpecializations and GetNumSpecializations() or 0) do
        local role = select(5, GetSpecializationInfo(i))
        if role == "TANK" then available.tank = true
        elseif role == "HEALER" then available.healer = true
        elseif role == "DAMAGER" then available.dps = true end
    end
    return available
end

local function RolesText(tank, healer, dps)
    local parts = {}
    if tank then parts[#parts + 1] = CreateAtlasMarkup("roleicon-tiny-tank", 14, 14) .. " |cff00aeefTank|r" end
    if healer then parts[#parts + 1] = CreateAtlasMarkup("roleicon-tiny-healer", 14, 14) .. " |cff00ff7fHealer|r" end
    if dps then parts[#parts + 1] = CreateAtlasMarkup("roleicon-tiny-dps", 14, 14) .. " |cffff6060DPS|r" end
    return table.concat(parts, ",  ")
end

local function ApplyRoles()
    local tank, healer, dps = QueueRoles()
    local isLeader = GetLFGRoles()
    SetLFGRoles(isLeader, tank, healer, dps)
    return tank, healer, dps
end

-- One "Signed up as" line per sign-up, and only when solo: in a group the
-- leader's queue is the news, not your roles.
local lastReport = 0
local function ReportRoles(tank, healer, dps)
    if not settings.report or IsInGroup(LE_PARTY_CATEGORY_HOME) then return end
    local now = GetTime()
    if now - lastReport < 2 then return end
    lastReport = now
    print(PREFIX .. "signed up as " .. RolesText(tank, healer, dps))
end

-- ── Dungeon Finder: role check and ready check ─────────────────────────────

local ROLE_CHECK_DEBOUNCE = 1.0
local lastRoleCheck = 0

local function HandleRoleCheck()
    if not Active("roleCheck") then return end
    local now = GetTime()
    if now - lastRoleCheck < ROLE_CHECK_DEBOUNCE then return end
    lastRoleCheck = now
    ReportRoles(ApplyRoles())
    CompleteLFGRoleCheck(true)
end

-- The event and the popup's OnShow both answer; this catches the rare show
-- that neither saw. Runs only while the module is on, and only looks at one
-- frame's visibility.
local roleCheckTicker
local function StartRoleCheckWatch()
    if roleCheckTicker then return end
    roleCheckTicker = C_Timer.NewTicker(0.5, function()
        if LFDRoleCheckPopup and LFDRoleCheckPopup:IsVisible() then HandleRoleCheck() end
    end)
end

local function StopRoleCheckWatch()
    if roleCheckTicker then roleCheckTicker:Cancel() roleCheckTicker = nil end
end

-- ── "Your group is ready" ───────────────────────────────────────────────────
-- ⚠ Entering cannot be done for the player. Whatever route is taken -- our own
-- secure button, a click on Blizzard's Enter button, AcceptProposal itself --
-- it ends in AcceptProposal, which is protected, and every attempt raises
-- ADDON_ACTION_BLOCKED in the player's error window. The click has to come
-- from their hand. Never put an automatic press back.
--
-- What is left is not missing the window: a sound, and the queue's name in
-- chat, so a proposal is noticed while tabbed out or mid-pull.

-- Said once per window, not once per check: the watcher runs several times a
-- second, and a line every few seconds while the window sits there is worse
-- than no line at all.
local announced = false
local proposalTicker

-- ⚠ Asked of the game, not of a frame. Blizzard's ready popup can report
-- itself shown at login with no proposal behind it, and the module rang the
-- ready sound every time the player logged in.
local function ReadyDialogShown()
    if not GetLFGProposal then return false end
    local ok, exists = pcall(GetLFGProposal)
    if not ok or issecretvalue(exists) then return false end
    return exists == true
end

local function AcceptReady()
    if not ReadyDialogShown() then
        -- Gone: the next window is a new one and may speak again.
        announced = false
        return
    end
    if announced or not Active("acceptProposal") then return end
    announced = true

    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
        pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
    end
    print(PREFIX .. "your group is ready. |cffffd100Press Enter yourself|r: the game does not let an addon do it.")
end

local function StartProposalWatch()
    if proposalTicker then return end
    proposalTicker = C_Timer.NewTicker(0.3, AcceptReady)
end

local function StopProposalWatch()
    if proposalTicker then proposalTicker:Cancel() proposalTicker = nil end
    announced = false
end

-- ── Group Finder ────────────────────────────────────────────────────────────

local function SafeResultInfo(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info or issecretvalue(info) or not canaccesstable(info) then return nil end
    return info
end

-- Who turned us down, kept across list refreshes and relistings: the leader
-- and the activity identify the person, while partyGUID changes every time a
-- listing is made again. partyGUID only stands in for brand-new listings.
local function GroupKey(info)
    if not info then return nil end
    local leader = info.leaderName
    if leader and not issecretvalue(leader) then
        local ids = info.activityIDs
        local activityID = info.activityID or (not issecretvalue(ids) and ids and ids[1])
        return activityID and (activityID .. leader) or nil
    end
    local guid = info.partyGUID
    if guid and not issecretvalue(guid) then return guid end
    return nil
end

local DECLINE_MEMORY = 15 * 60
local hardDeclined, softDeclined = {}, {}   -- key -> time()
local COLOR_HARD = { 1.0, 0.1, 0.1 }        -- declined
local COLOR_SOFT = { 1.0, 0.4, 0.1 }        -- delisted, full, timed out

local function Remembered(list, key)
    return key and (list[key] or 0) > time() - DECLINE_MEMORY
end

local function ColorListing(entry)
    if not Active("colorDeclined") or not entry.Name or not entry.resultID then return end
    local key = GroupKey(SafeResultInfo(entry.resultID))
    if Remembered(hardDeclined, key) then
        entry.Name:SetTextColor(unpack(COLOR_HARD))
    elseif Remembered(softDeclined, key) then
        entry.Name:SetTextColor(unpack(COLOR_SOFT))
    end
end

-- Blizzard blocks a group that declined you by partyGUID in
-- LFGListFrame.declines; removing the entry lets you apply again.
local function ClearDeclineBlock(resultID)
    if not Active("reapply") or not (LFGListFrame and LFGListFrame.declines) then return end
    local info = SafeResultInfo(resultID)
    local guid = info and info.partyGUID
    if not guid or issecretvalue(guid) then return end
    LFGListFrame.declines[guid] = nil
end

local function OnApplicationStatus(resultID, status)
    local key = GroupKey(SafeResultInfo(resultID))
    if status == "declined" then
        if key then hardDeclined[key] = time() end
        ClearDeclineBlock(resultID)
    elseif status == "declined_full" or status == "declined_delisted" or status == "timedout" then
        if key then softDeclined[key] = time() end
        ClearDeclineBlock(resultID)
    end
end

local function IsLoaded(name)
    local check = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    return check and check(name) or false
end

-- The "created ... ago" line Blizzard dropped in 10.2.7. Premade Groups
-- Filter adds its own, so this steps aside when it is loaded.
local function AddGroupAge(tooltip, resultID)
    if not Active("groupAge") or IsLoaded("PremadeGroupsFilter") then return end
    local info = SafeResultInfo(resultID)
    local age = info and info.age
    if not age or issecretvalue(age) or age <= 0 or not (tooltip and tooltip:IsShown()) then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(LFG_LIST_TOOLTIP_AGE:format(SecondsToTime(age, false, false, 1, false)))
    tooltip:Show()
end

local function SignUpFromDoubleClick(self)
    if not Active("doubleClick") then return end
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    if not panel or panel.SignUpButton.tooltip then return end   -- nothing selectable
    LFGListSearchPanel_SignUp(self:GetParent():GetParent():GetParent())
end

local function HookListingButtons()
    local panel = LFGListFrame and LFGListFrame.SearchPanel
    local target = panel and panel.ScrollBox and panel.ScrollBox:GetScrollTarget()
    if not target then return end
    for _, child in ipairs({ target:GetChildren() }) do
        if child and child:GetObjectType() == "Button" and not child.oxedDoubleClick then
            child.oxedDoubleClick = true
            child:HookScript("OnDoubleClick", SignUpFromDoubleClick)
        end
    end
end

local signUpBusy = false
local function OnApplicationDialogShow()
    if not Active("autoSignUp") or signUpBusy then return end
    if settings.shiftNote and IsShiftKeyDown() then return end
    signUpBusy = true
    C_Timer.After(0.5, function() signUpBusy = false end)
    ReportRoles(ApplyRoles())
    LFGListApplicationDialog.SignUpButton:Click()
end

-- Same as Blizzard's LFGListApplicationDialog_Show without the call to
-- C_LFGList.ClearApplicationTextFields(), so the note survives.
local originalDialogShow
local function KeepNoteDialogShow(self, resultID)
    if not Active("keepNote") and originalDialogShow then
        return originalDialogShow(self, resultID)
    end
    if not resultID then return end
    self.resultID = resultID
    LFGListApplicationDialog_UpdateRoles(self)
    StaticPopupSpecial_Show(self)
end

-- ── Hooks, installed once ───────────────────────────────────────────────────
-- A hook cannot be taken off again, so every one checks Active() first and a
-- switched-off module leaves the Group Finder exactly as Blizzard made it.

local hooked = {}

local function HookFinderFrames()
    if not hooked.proposal and LFGDungeonReadyDialogEnterDungeonButton and LFGDungeonReadyPopup_Update then
        hooked.proposal = true
        hooksecurefunc("LFGDungeonReadyPopup_Update", function()
            C_Timer.After(0.2, AcceptReady)
        end)
    end
    if not hooked.roleCheck and LFDRoleCheckPopup then
        hooked.roleCheck = true
        LFDRoleCheckPopup:HookScript("OnShow", HandleRoleCheck)
    end
    if not hooked.dialog and LFGListApplicationDialog then
        hooked.dialog = true
        LFGListApplicationDialog:HookScript("OnShow", OnApplicationDialogShow)
    end
    if not hooked.color and LFGListSearchEntry_Update then
        hooked.color = true
        hooksecurefunc("LFGListSearchEntry_Update", ColorListing)
    end
    if not hooked.age and LFGListUtil_SetSearchEntryTooltip then
        hooked.age = true
        hooksecurefunc("LFGListUtil_SetSearchEntryTooltip", AddGroupAge)
    end
    -- Replaced only when the option is on, so a player who never wants it
    -- never has the function touched.
    if not hooked.note and settings.keepNote and LFGListApplicationDialog_Show then
        hooked.note = true
        originalDialogShow = LFGListApplicationDialog_Show
        LFGListApplicationDialog_Show = KeepNoteDialogShow
    end
end

-- ── Role bar above the Group Finder ─────────────────────────────────────────

local BTN_SIZE, BTN_GAP = 46, 18
local ROLE_ORDER = { "tank", "healer", "dps" }
local ROLE_NAMES = { tank = "|cff00aeefTank|r", healer = "|cff00ff7fHealer|r", dps = "|cffff6060DPS|r" }
local ROLE_COORDS = {
    tank   = { 0.00, 0.25, 0.25, 0.50 },
    healer = { 0.25, 0.50, 0.00, 0.25 },
    dps    = { 0.25, 0.50, 0.25, 0.50 },
}

local roleBar, toggleButton, tutorial
local roleButtons = {}

local function RefreshRoleBar()
    if not roleBar then return end
    local picked, available = PickedRoles(), AvailableRoles()
    for role, button in pairs(roleButtons) do
        if not available[role] then
            picked[role] = false
            button.icon:SetDesaturated(true)
            button.icon:SetAlpha(0.25)
            button.check:Hide()
            button.cross:Show()
        else
            button.icon:SetDesaturated(not picked[role])
            button.icon:SetAlpha(picked[role] and 1 or 0.5)
            button.check:SetShown(picked[role])
            button.cross:Hide()
        end
    end
    if toggleButton then toggleButton.vBar:SetShown(settings.roleBarHidden == true) end
end

local function RoleTooltip(button)
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:SetText(ROLE_NAMES[button.role])
    if not AvailableRoles()[button.role] then
        GameTooltip:AddLine("Not available for this class", 0.6, 0.6, 0.6)
    elseif PickedRoles()[button.role] then
        GameTooltip:AddLine("Queued as this role", 0.3, 1, 0.3)
    else
        GameTooltip:AddLine("Not queued as this role", 1, 0.4, 0.4)
    end
    GameTooltip:Show()
end

local function ShowRoleBar()
    if not roleBar then return end
    local show = Active("roleBar") and not settings.roleBarHidden and PVEFrame and PVEFrame:IsShown()
    roleBar:SetShown(show and true or false)
    if toggleButton then toggleButton:SetShown(Active("roleBar") and true or false) end
    RefreshRoleBar()
end

local function BuildRoleBar()
    if roleBar or not PVEFrame then return end

    roleBar = CreateFrame("Frame", nil, PVEFrame, "BackdropTemplate")
    local rowWidth = 3 * BTN_SIZE + 2 * BTN_GAP
    roleBar:SetSize(rowWidth + 50, BTN_SIZE + 42)
    roleBar:SetPoint("BOTTOM", PVEFrame, "TOP", 100, -1)
    roleBar:SetFrameLevel(PVEFrame:GetFrameLevel() + 1)
    roleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    roleBar:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
    roleBar:SetBackdropBorderColor(0, 0, 0, 0.8)
    roleBar:Hide()

    local hint = roleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", roleBar, "BOTTOM", 0, 20)
    hint:SetText("|cffaaaaaaNone picked: your spec's role|r")
    local hint2 = roleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint2:SetPoint("BOTTOM", roleBar, "BOTTOM", 0, 7)
    hint2:SetText("|cffaaaaaaHold Shift when signing up to write a note|r")

    for i, role in ipairs(ROLE_ORDER) do
        local button = CreateFrame("Button", nil, roleBar)
        button:SetSize(BTN_SIZE, BTN_SIZE)
        button:SetPoint("TOP", roleBar, "TOP", -(rowWidth / 2) + BTN_SIZE / 2 + (i - 1) * (BTN_SIZE + BTN_GAP), -5)
        button.role = role

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        button.icon:SetTexture("Interface\\LFGFRAME\\UI-LFG-Icon-Roles")
        button.icon:SetTexCoord(unpack(ROLE_COORDS[role]))
        button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

        local box = button:CreateTexture(nil, "OVERLAY")
        box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        box:SetSize(18, 18)
        box:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 5, -5)
        button.check = button:CreateTexture(nil, "OVERLAY", nil, 1)
        button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        button.check:SetAllPoints(box)

        button.cross = button:CreateTexture(nil, "OVERLAY")
        button.cross:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
        button.cross:SetSize(28, 28)
        button.cross:SetPoint("CENTER")
        button.cross:Hide()

        button:SetScript("OnClick", function(self)
            if not AvailableRoles()[role] then return end
            local picked = PickedRoles()
            picked[role] = not picked[role]
            RefreshRoleBar()
            RoleTooltip(self)
        end)
        button:SetScript("OnEnter", RoleTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        roleButtons[role] = button
    end

    -- The +/- square next to the Group Finder's close button hides the bar.
    toggleButton = CreateFrame("Button", nil, PVEFrame, "BackdropTemplate")
    toggleButton:SetSize(20, 20)
    toggleButton:SetFrameLevel(PVEFrame:GetFrameLevel() + 50)
    local close = PVEFrame.CloseButton or _G.PVEFrameCloseButton
    if close then
        toggleButton:SetPoint("RIGHT", close, "LEFT", -2, 0)
    else
        toggleButton:SetPoint("TOPRIGHT", PVEFrame, "TOPRIGHT", -32, -6)
    end
    toggleButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    toggleButton:SetBackdropColor(0.55, 0.08, 0.08, 1)
    local hBar = toggleButton:CreateTexture(nil, "OVERLAY")
    hBar:SetColorTexture(1, 0.82, 0, 1)
    hBar:SetSize(12, 3)
    hBar:SetPoint("CENTER")
    toggleButton.vBar = toggleButton:CreateTexture(nil, "OVERLAY")
    toggleButton.vBar:SetColorTexture(1, 0.82, 0, 1)
    toggleButton.vBar:SetSize(3, 12)
    toggleButton.vBar:SetPoint("CENTER")
    local glow = toggleButton:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints()
    glow:SetColorTexture(1, 1, 1, 0.25)
    toggleButton:SetScript("OnClick", function()
        settings.roleBarHidden = not settings.roleBarHidden
        settings.tutorialSeen = true
        if tutorial then tutorial:Hide() end
        ShowRoleBar()
    end)
    toggleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Auto Queue")
        GameTooltip:AddLine("Show or hide the role picker.", 1, 1, 1)
        GameTooltip:Show()
    end)
    toggleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Explained once, the first time the Group Finder opens with the module on.
    tutorial = CreateFrame("Frame", nil, PVEFrame, "BackdropTemplate")
    tutorial:SetFrameStrata("TOOLTIP")
    tutorial:SetSize(260, 10)
    tutorial:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    tutorial:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    tutorial:SetBackdropBorderColor(1, 0.82, 0, 1)
    tutorial:SetPoint("TOPRIGHT", toggleButton, "BOTTOMRIGHT", 10, -8)
    tutorial:Hide()
    local text = tutorial:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 10, -10)
    text:SetWidth(240)
    text:SetJustifyH("LEFT")
    text:SetText("|cff00ff00Auto Queue|r: this square shows or hides the role picker, "
        .. "to queue as several roles or as a role your spec is not. "
        .. "With none picked, your current spec's role is used.\n\n"
        .. "Roles are saved per character.\n\n"
        .. "|cffffff00Tip: double-click a listing to sign up.|r")
    local gotIt = CreateFrame("Button", nil, tutorial, "UIPanelButtonTemplate")
    gotIt:SetSize(80, 22)
    gotIt:SetPoint("TOP", text, "BOTTOM", 0, -10)
    gotIt:SetText("Got it")
    gotIt:SetScript("OnClick", function()
        settings.tutorialSeen = true
        tutorial:Hide()
    end)
    tutorial:SetHeight(text:GetStringHeight() + 54)

    PVEFrame:HookScript("OnShow", function()
        ShowRoleBar()
        if Active("roleBar") and not settings.tutorialSeen then tutorial:Show() end
    end)
    PVEFrame:HookScript("OnHide", function()
        if roleBar then roleBar:Hide() end
        if tutorial then tutorial:Hide() end
    end)
    ShowRoleBar()
end

-- ── Events ──────────────────────────────────────────────────────────────────

local function Setup()
    HookFinderFrames()
    BuildRoleBar()
end

watcher:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_LFGList" or arg1 == "Blizzard_GroupFinder" then Setup() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        Setup()
    elseif event == "LFG_ROLE_CHECK_SHOW" then
        HandleRoleCheck()
    elseif event == "LFG_PROPOSAL_SHOW" then
        announced = false
        C_Timer.After(0.2, AcceptReady)
    elseif event == "LFG_PROPOSAL_SUCCEEDED" or event == "LFG_PROPOSAL_FAILED" then
        announced = false
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        Setup()
        if Active("doubleClick") then C_Timer.After(0.1, HookListingButtons) end
    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        OnApplicationStatus(arg1, arg2)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        RefreshRoleBar()
    end
end)

local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "LFG_ROLE_CHECK_SHOW",
    "LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_FAILED",
    "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_APPLICATION_STATUS_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED",
}

-- The stand-alone AutoQueue does all of this too; both at once would answer
-- every role check twice.
local function StandaloneLoaded()
    return IsLoaded("AutoQueue")
end

local function Start()
    if StandaloneLoaded() then
        print(PREFIX .. "Auto Queue is off while the AutoQueue addon is loaded: it does the same job. Disable one of them.")
        return
    end
    for _, event in ipairs(EVENTS) do watcher:RegisterEvent(event) end
    StartRoleCheckWatch()
    StartProposalWatch()
    Setup()
end

local function Stop()
    watcher:UnregisterAllEvents()
    StopRoleCheckWatch()
    StopProposalWatch()
    ShowRoleBar()
    if tutorial then tutorial:Hide() end
end

-- ── Slash command ───────────────────────────────────────────────────────────

local function PrintStatus()
    print(PREFIX .. "Auto Queue is " .. (Active() and "|cff00ff00on|r" or "|cffff4444off|r") .. ".")
    local picked = PickedRoles()
    local any = picked.tank or picked.healer or picked.dps
    print("  Queue roles: " .. (any and RolesText(picked.tank, picked.healer, picked.dps)
        or ("your spec's (" .. RolesText(QueueRoles()) .. ")")))
    print("  /aq on, /aq off, or Options on its card under Modules.")
end

SLASH_OXEDAUTOQUEUE1 = "/aq"
SLASH_OXEDAUTOQUEUE2 = "/autoqueue"
SlashCmdList["OXEDAUTOQUEUE"] = function(message)
    if not settings then return end
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    local API = OxedHub.ModuleAPI
    if message == "on" or message == "off" then
        local on = message == "on"
        if API and API.SetModuleEnabled then
            API:SetModuleEnabled("autoqueue", on)
            if API.RefreshModulesTab then pcall(API.RefreshModulesTab, API) end
        else
            settings.enabled = on
            if on then Start() else Stop() end
        end
        print(PREFIX .. "Auto Queue " .. (on and "on." or "off."))
    else
        PrintStatus()
    end
end

-- ── Settings ────────────────────────────────────────────────────────────────

local function BindSettings()
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.autoqueue
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.autoqueue = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Auto Queue", 440, 500)
        local w = optionsWindow
        w:AddCheckbox(settings, "roleCheck", "Answer role checks",
            "Dungeon Finder role checks are accepted at once with your queue roles.")
        w:AddCheckbox(settings, "acceptProposal", "Call out when the group is ready",
            "Plays a sound and says so in chat when the \"Your group is ready\" window appears. The game will not let an addon press Enter: that click has to be yours.")
        w:AddCheckbox(settings, "autoSignUp", "Confirm Group Finder sign-ups",
            "The sign-up window confirms itself with your queue roles.")
        w:AddCheckbox(settings, "shiftNote", "Hold Shift to write a note",
            "Holding Shift while signing up leaves the window open for a note.")
        w:AddCheckbox(settings, "doubleClick", "Double-click a listing to sign up")
        w:AddCheckbox(settings, "colorDeclined", "Mark groups that turned you down",
            "Red: declined you. Orange: delisted, full or timed out. Remembered for 15 minutes.")
        w:AddCheckbox(settings, "reapply", "Allow applying again to them")
        w:AddCheckbox(settings, "groupAge", "Show how old a listing is in its tooltip",
            "Skipped when Premade Groups Filter is loaded; it shows its own.")
        w:AddCheckbox(settings, "keepNote", "Keep my sign-up note",
            "The note stays filled in from one application to the next. Takes effect after /reload when switched on.")
        w:AddCheckbox(settings, "roleBar", "Role picker above the Group Finder",
            "Pick one or more roles to queue as. None picked: your spec's role.", ShowRoleBar)
        w:AddCheckbox(settings, "report", "Say the roles you signed up as in chat")
        w:AddNote("Roles are saved per character. /aq shows the status; /aq on and /aq off switch the module.")
    end
    optionsWindow:Show()
end

-- ── Registration ────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    BindSettings()

    if not OxedHub.ModuleAPI then
        if settings.enabled == true then Start() end
        return
    end

    OxedHub.ModuleAPI:Register({
        id       = "autoqueue",
        name     = "Auto Queue",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "queue", "lfg", "group finder", "role check", "ready check", "dungeon", "apply", "sign up" },
        -- Clipped at about 90 characters on the card; the detail is in Options.
        desc     = "Accepts role checks, signs up in Group Finder, rings when your group is ready.",
        icon     = "Interface\\Icons\\INV_Misc_GroupNeedMore",

        defaults = DEFAULTS,

        OnOptionsShow = function() ShowOptions() end,

        OnEnable = function(_, config)
            settings = config
            Start()
        end,

        OnDisable = function()
            Stop()
        end,
    })
end)
