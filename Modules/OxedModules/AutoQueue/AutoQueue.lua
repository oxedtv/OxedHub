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
--   * Hovering the queue eye lists every dungeon and group you are queued for.
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
local L = OxedHub.L
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
    -- Movable LFG Eye (MovableLFGEye integration)
    movableEye     = true,   -- make Blizzard's queue eye movable and draggable
    eyeLocked      = false,  -- lock eye dragging
    eyeScale       = 1.0,    -- eye scale (0.5 to 2.5)
    eyeTooltip     = true,   -- hovering the eye lists the dungeons and groups you are queued for
    queueList      = true,   -- keep that list on screen, movable, while queued for anything
    listLocked     = false,  -- the list's header no longer drags it
    listScale      = 1.0,
    listAlpha      = 0.92,   -- background opacity
    listWidth      = 310,
    listRows       = 12,     -- rows before "and N more"
    listDetails    = true,   -- the grey third line of each row
    -- UI state, not options
    roleBarHidden  = false,
    tutorialSeen   = false,
}

local settings          -- OxedHubDB.modules.autoqueue, bound at login
local optionsWindow
local listOptionsWindow
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
    if tank then parts[#parts + 1] = CreateAtlasMarkup("roleicon-tiny-tank", 14, 14) .. L[" |cff00aeefTank|r"] end
    if healer then parts[#parts + 1] = CreateAtlasMarkup("roleicon-tiny-healer", 14, 14) .. L[" |cff00ff7fHealer|r"] end
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
    print(PREFIX .. L["signed up as "] .. RolesText(tank, healer, dps))
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
-- Also hands back the dungeon's name when the game gives a plain one.
local function ReadyDialogShown()
    if not GetLFGProposal then return false end
    local ok, exists, _, _, _, name = pcall(GetLFGProposal)
    if not ok or issecretvalue(exists) then return false end
    if name ~= nil and (issecretvalue(name) or type(name) ~= "string" or name == "") then name = nil end
    return exists == true, name
end

local function AcceptReady()
    local shown, dungeon = ReadyDialogShown()
    if not shown then
        -- Gone: the next window is a new one and may speak again.
        announced = false
        return
    end
    if announced or not Active("acceptProposal") then return end
    announced = true

    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
        pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
    end
    print(PREFIX .. L["your group is ready"] .. (dungeon and (" for |cffffffff" .. dungeon .. "|r") or "")
        .. L[". |cffffd100Press Enter yourself|r: the game does not let an addon do it."])
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

-- ⚠ Group Finder addons that sign up in one click and keep the note
-- themselves. With one of them loaded, ours step aside: pressing Sign Up from
-- inside their call is refused by the game (ApplyToGroup is protected, and the
-- press is not the player's), which raised ADDON_ACTION_BLOCKED under their
-- name, and both did the same job anyway.
local OTHER_SIGNUP_ADDONS = { "PremadeGroupsFilter" }
local function OtherSignUpAddon()
    for _, name in ipairs(OTHER_SIGNUP_ADDONS) do
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)
        if loaded then return name end
    end
    return nil
end

local signUpBusy = false
local function OnApplicationDialogShow()
    if not Active("autoSignUp") or signUpBusy then return end
    if OtherSignUpAddon() then return end
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
    if not hooked.note and settings.keepNote and LFGListApplicationDialog_Show and not OtherSignUpAddon() then
        hooked.note = true
        originalDialogShow = LFGListApplicationDialog_Show
        LFGListApplicationDialog_Show = KeepNoteDialogShow
    end
end

-- ── Role bar above the Group Finder ─────────────────────────────────────────

local BTN_SIZE, BTN_GAP = 46, 18
local ROLE_ORDER = { "tank", "healer", "dps" }
local ROLE_NAMES = { tank = "|cff00aeefTank|r", healer = "|cff00ff7fHealer|r", dps = "|cffff6060DPS|r" }
OxedHub:RegisterLocalizedTable(ROLE_NAMES)
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
        GameTooltip:AddLine(L["Not available for this class"], 0.6, 0.6, 0.6)
    elseif PickedRoles()[button.role] then
        GameTooltip:AddLine(L["Queued as this role"], 0.3, 1, 0.3)
    else
        GameTooltip:AddLine(L["Not queued as this role"], 1, 0.4, 0.4)
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
    hint:SetText(L["|cffaaaaaaNone picked: your spec's role|r"])
    local hint2 = roleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint2:SetPoint("BOTTOM", roleBar, "BOTTOM", 0, 7)
    hint2:SetText(L["|cffaaaaaaHold Shift when signing up to write a note|r"])

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
        GameTooltip:AddLine(L["Show or hide the role picker."], 1, 1, 1)
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
    text:SetText(L["|cff00ff00Auto Queue|r: this square shows or hides the role picker, "]
        .. L["to queue as several roles or as a role your spec is not. "]
        .. L["With none picked, your current spec's role is used.\n\n"]
        .. L["Roles are saved per character.\n\n"]
        .. L["|cffffff00Tip: double-click a listing to sign up.|r"])
    local gotIt = CreateFrame("Button", nil, tutorial, "UIPanelButtonTemplate")
    gotIt:SetSize(80, 22)
    gotIt:SetPoint("TOP", text, "BOTTOM", 0, -10)
    gotIt:SetText(L["Got it"])
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

-- ── Movable LFG Eye ─────────────────────────────────────────────────────────
local eyeInitialized = false
local eyeMoverOverlay = nil
local eyeTestMode = false
local pendingEyeRestore = false
local EYE_APPLY_FLAG = "_oxed_aq_eye_applying"

local function GetQueueEyeButton()
    return _G["QueueStatusButton"] or _G["QueueStatusMinimapButton"]
end

local function SaveEyePosition(frame)
    if not frame or not settings then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    local relName = "UIParent"
    if relativeTo and relativeTo.GetName then
        relName = relativeTo:GetName() or relName
    end
    settings.eyePoint = {
        point = point or "TOPRIGHT",
        relTo = relName,
        relativePoint = relativePoint or "TOPRIGHT",
        x = tonumber(string.format("%.2f", x or 0)) or 0,
        y = tonumber(string.format("%.2f", y or 0)) or 0,
    }
end

local function RestoreEyePosition()
    local btn = GetQueueEyeButton()
    if not btn or not settings or not Active("movableEye") then return end
    if InCombatLockdown() then
        pendingEyeRestore = true
        return
    end

    local p = settings.eyePoint
    if not p then return end

    local relFrame = _G[p.relTo] or UIParent
    btn[EYE_APPLY_FLAG] = true
    btn:ClearAllPoints()
    btn:SetPoint(p.point or "TOPRIGHT", relFrame, p.relativePoint or "TOPRIGHT", p.x or 0, p.y or 0)
    C_Timer.After(0.01, function()
        if btn then btn[EYE_APPLY_FLAG] = nil end
    end)
end

local function UpdateEyeAppearance()
    local btn = GetQueueEyeButton()
    if not btn then return end

    if not Active("movableEye") then
        btn:SetScale(1.0)
        btn:SetAlpha(1.0)
        if eyeMoverOverlay then eyeMoverOverlay:Hide() end
        return
    end

    local sc = tonumber(settings and settings.eyeScale) or 1.0
    btn:SetScale(math.max(0.5, math.min(2.5, sc)))

    if eyeMoverOverlay then
        if eyeTestMode or (Active("movableEye") and not settings.eyeLocked) then
            eyeMoverOverlay:Show()
        else
            eyeMoverOverlay:Hide()
        end
    end

    if eyeTestMode then
        RestoreEyePosition()
        btn:Show()
        if btn.Eye then btn.Eye:Show() end
        if btn.Eye and btn.Eye.EyeTexture then btn.Eye.EyeTexture:Show() end
    end
end

local function SetupEyeButton()
    if eyeInitialized then return end
    local btn = GetQueueEyeButton()
    if not btn then return end

    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:SetClampedToScreen(true)

    -- Visual mover outline frame when unlocked / in test mode
    eyeMoverOverlay = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    eyeMoverOverlay:SetAllPoints(btn)
    eyeMoverOverlay:SetFrameLevel(btn:GetFrameLevel() + 10)
    eyeMoverOverlay:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
        bgFile = "Interface\\Buttons\\WHITE8X8",
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    eyeMoverOverlay:SetBackdropBorderColor(0.2, 0.9, 0.4, 0.8)
    eyeMoverOverlay:SetBackdropColor(0.1, 0.8, 0.3, 0.15)
    local label = eyeMoverOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("BOTTOM", eyeMoverOverlay, "TOP", 0, 3)
    label:SetText(L["LFG Eye"])
    label:SetTextColor(0.4, 1.0, 0.5)
    eyeMoverOverlay:Hide()

    btn:SetScript("OnDragStart", function(self)
        if not Active("movableEye") then return end
        if settings.eyeLocked and not eyeTestMode then return end
        self:StartMoving()
    end)

    btn:SetScript("OnDragStop", function(self)
        if not Active("movableEye") then return end
        self:StopMovingOrSizing()
        SaveEyePosition(self)
    end)

    -- Anti-override hook: reapply if Blizzard's Minimap code resets position
    hooksecurefunc(btn, "SetPoint", function(self)
        if self[EYE_APPLY_FLAG] or not Active("movableEye") then return end
        if settings and settings.eyePoint then
            C_Timer.After(0.05, function()
                if btn and not btn[EYE_APPLY_FLAG] and Active("movableEye") then
                    RestoreEyePosition()
                end
            end)
        end
    end)

    eyeInitialized = true
end

local function SetEyeTestMode(enabled)
    eyeTestMode = enabled
    local btn = GetQueueEyeButton()
    if not btn then return end
    if enabled then
        SetupEyeButton()
        RestoreEyePosition()
        UpdateEyeAppearance()
    else
        UpdateEyeAppearance()
        if not (C_LFGList and C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo()) then
            btn:Hide()
        end
    end
end

-- ── What the eye is queued for ──────────────────────────────────────────────
-- Hovering the eye opens a list beside Blizzard's own queue window, drawn
-- like the Party Keystones list: a gold header, then one row per queue with
-- its icon, what kind of queue it is, the dungeon or group, and the details
-- (time waited, estimate, who is still missing). Blizzard's window only says
-- "Dungeon Finder" for a hand-picked list; this names every dungeon.
-- Every read goes through pcall and Plain(): a secret or a missing API leaves
-- its detail out. A listing's own title can be a secret: it is handed to
-- SetText untouched, never joined to other text.

local QUEUE_CATEGORIES = {
    { "LE_LFG_CATEGORY_LFD", "Dungeon Finder" },
    { "LE_LFG_CATEGORY_RF", "Raid Finder" },
    { "LE_LFG_CATEGORY_SCENARIO", "Scenario" },
    { "LE_LFG_CATEGORY_FLEXRAID", "Flex Raid" },
    { "LE_LFG_CATEGORY_WORLDPVP", "World PvP" },
    { "LE_LFG_CATEGORY_BATTLEFIELD", "Brawl" },
}
OxedHub:RegisterLocalizedTable(QUEUE_CATEGORIES, 2)
local QUEUED_MODES = { queued = true, rolecheck = true, proposal = true, suspended = true }
local MODE_WORDS = { rolecheck = "Role check", proposal = "Ready", suspended = "Paused" }
OxedHub:RegisterLocalizedTable(MODE_WORDS)

local Q_WIDTH, Q_HEADER, Q_ROW, Q_ICON, Q_MAX = 310, 20, 44, 36, 12
local ICON_DUNGEON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local ICON_LISTING = "Interface\\Icons\\INV_Misc_GroupLooking"
local ICON_KEY     = "Interface\\Icons\\INV_Relics_Hourglass"
local ICON_PVP     = "Interface\\Icons\\Achievement_BG_winWSG"
local GOLD, GREEN, RED = { 1, 0.82, 0 }, { 0.3, 1, 0.3 }, { 1, 0.4, 0.4 }
local ROLE_TANK_ICON   = CreateAtlasMarkup and CreateAtlasMarkup("roleicon-tiny-tank", 12, 12) or "T"
local ROLE_HEALER_ICON = CreateAtlasMarkup and CreateAtlasMarkup("roleicon-tiny-healer", 12, 12) or "H"
local ROLE_DPS_ICON    = CreateAtlasMarkup and CreateAtlasMarkup("roleicon-tiny-dps", 12, 12) or "D"
-- A listing's kind of run, as the Group Finder offers it.
local PLAYSTYLES = { [1] = "Learning", [2] = "Relaxed", [3] = "Competitive", [4] = "Carry offered" }
local OLD_PLAYSTYLES = { [1] = "Standard", [2] = "Casual", [3] = "Hardcore" }

local queuePanel, queueOwner

local function Plain(value)
    if value == nil or issecretvalue(value) then return nil end
    return value
end

local function PlainText(value)
    value = Plain(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- "45s", "12m", "1h 05m": short enough that a row's details fit on one line.
local function Duration(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then return nil end
    seconds = math.floor(seconds)
    if seconds < 60 then return seconds .. "s" end
    if seconds < 3600 then return math.floor(seconds / 60) .. "m" end
    return ("%dh %02dm"):format(math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- "5m" on the icon: minutes waited, short enough for a 36 px square.
local function ShortWait(seconds)
    if type(seconds) ~= "number" or seconds < 60 then return nil end
    local minutes = math.floor(seconds / 60)
    return minutes >= 60 and (math.floor(minutes / 60) .. "h") or (minutes .. "m")
end

local function DungeonInfo(id)
    local ok, name, _, _, _, _, _, _, _, _, _, texture = pcall(GetLFGDungeonInfo, id)
    if not ok then return nil end
    -- A file id (number) on current clients, a bare "LFGIcon-" suffix on older ones.
    texture = Plain(texture)
    if type(texture) == "string" then
        if texture == "" then
            texture = nil
        elseif not texture:find("[/\\]") then
            texture = "Interface\\LFGFrame\\LFGIcon-" .. texture
        end
    elseif type(texture) ~= "number" or texture <= 0 then
        texture = nil
    end
    return PlainText(name), texture
end

-- Battleground pictures by name, from the game's own battleground list.
local ICON_ARENA = "Interface\\PVPFrame\\RandomPVPIcon"
local battlegroundIcons
local function BattlegroundIcon(name)
    if not name then return nil end
    if not battlegroundIcons then
        battlegroundIcons = {}
        if GetNumBattlegroundTypes and GetBattlegroundInfo then
            local okCount, count = pcall(GetNumBattlegroundTypes)
            for i = 1, (okCount and type(Plain(count)) == "number" and count or 0) do
                local ok, bgName, _, _, _, _, _, _, _, _, icon = pcall(GetBattlegroundInfo, i)
                bgName = ok and PlainText(bgName)
                icon = ok and Plain(icon)
                if bgName and icon and icon ~= "" and icon ~= 0 then battlegroundIcons[bgName] = icon end
            end
        end
    end
    if battlegroundIcons[name] then return battlegroundIcons[name] end
    if name:find(ARENA or "Arena", 1, true) then return ICON_ARENA end
    return nil
end

-- Keystone dungeon icons, matched by name against an activity's full name
-- ("Murder Row (Mythic Keystone)" starts with "Murder Row").
local keystoneIcons
local function KeystoneIcon(activityName)
    if not activityName then return nil end
    if not keystoneIcons then
        keystoneIcons = {}
        if C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapUIInfo then
            local ok, maps = pcall(C_ChallengeMode.GetMapTable)
            for _, mapID in ipairs(ok and type(maps) == "table" and maps or {}) do
                local okInfo, name, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
                name = okInfo and PlainText(name)
                if name and Plain(texture) then keystoneIcons[name] = texture end
            end
        end
    end
    for name, texture in pairs(keystoneIcons) do
        if activityName:sub(1, #name) == name then return texture end
    end
    return nil
end

local function Activity(info)
    if type(info) ~= "table" or issecretvalue(info) then return nil end
    local ids = Plain(info.activityIDs)
    local activityID = Plain(info.activityID) or (type(ids) == "table" and Plain(ids[1])) or nil
    if not activityID or not (C_LFGList and C_LFGList.GetActivityInfoTable) then return nil end
    local ok, activity = pcall(C_LFGList.GetActivityInfoTable, activityID)
    if not ok or type(activity) ~= "table" or issecretvalue(activity) then return nil end
    local name = PlainText(activity.fullName)
    local isKey = Plain(activity.isMythicPlusActivity) == true
    return name, KeystoneIcon(name) or (isKey and ICON_KEY) or nil
end

-- A listing title as SetText can take it: a secret is passed on untouched
-- (testing it is the error), a plain string if it has text, else fallback.
local function TitleOr(title, fallback)
    if issecretvalue(title) then return title end
    return PlainText(title) or fallback
end

local function Join(parts)
    local out = {}
    for _, part in ipairs(parts) do if part then out[#out + 1] = part end end
    return #out > 0 and table.concat(out, "  ·  ") or nil
end

-- One row: { icon, badge, kind, kindColor, title (may be secret), detail }
local function CollectQueues(rows)
    local now = GetTime()

    for _, entry in ipairs(QUEUE_CATEGORIES) do
        local category = _G[entry[1]]
        local okMode, mode = false, nil
        if category and GetLFGMode then okMode, mode = pcall(GetLFGMode, category) end
        mode = okMode and Plain(mode) or nil
        if mode and QUEUED_MODES[mode] then
            -- ok, hasData, leaderNeeds, tankNeeds, healerNeeds, dpsNeeds, totalTanks,
            -- totalHealers, totalDPS, instanceType, instanceSubType, instanceName,
            -- averageWait, tankWait, healerWait, damageWait, myWait, queuedTime
            local stats = GetLFGQueueStats and { pcall(GetLFGQueueStats, category) } or {}
            local okStats = stats[1] == true
            local waited, estimate, need
            if okStats then
                local queuedAt = Plain(stats[18])
                waited = type(queuedAt) == "number" and (now - queuedAt) or nil
                estimate = Plain(stats[17])
                if type(estimate) ~= "number" or estimate <= 0 then estimate = Plain(stats[13]) end
                if Plain(stats[2]) == true then
                    -- Role icons and counts: "needs 2 tank, 5 healer, 17 DPS"
                    -- ran off the end of a Raid Finder row.
                    local missing = {}
                    local tank, healer, dps = Plain(stats[4]), Plain(stats[5]), Plain(stats[6])
                    if type(tank) == "number" and tank > 0 then missing[#missing + 1] = ROLE_TANK_ICON .. tank end
                    if type(healer) == "number" and healer > 0 then missing[#missing + 1] = ROLE_HEALER_ICON .. healer end
                    if type(dps) == "number" and dps > 0 then missing[#missing + 1] = ROLE_DPS_ICON .. dps end
                    if #missing > 0 then need = "needs " .. table.concat(missing, " ") end
                end
            end
            local detail = Join({
                Duration(waited) and ("waited " .. Duration(waited)) or nil,
                Duration(type(estimate) == "number" and estimate or nil) and ("est " .. Duration(estimate)) or nil,
                need,
            })
            local kind = entry[2] .. (MODE_WORDS[mode] and ("  ·  " .. MODE_WORDS[mode]) or "")
            local kindColor = (mode == "suspended" and RED) or (mode == "proposal" and GREEN) or GOLD

            local dungeons = {}
            if GetLFGQueuedList then
                local list = {}
                local ok, returned = pcall(GetLFGQueuedList, category, list)
                if ok and type(returned) == "table" then list = returned end
                for id in pairs(list) do
                    local name, texture = DungeonInfo(id)
                    if name then dungeons[#dungeons + 1] = { name = name, texture = texture, id = id } end
                end
            end
            if #dungeons == 0 then
                local instance = okStats and PlainText(stats[12])
                dungeons[1] = { name = instance or entry[2] }
            end
            table.sort(dungeons, function(a, b) return a.name < b.name end)
            for _, d in ipairs(dungeons) do
                rows[#rows + 1] = { d.texture or ICON_DUNGEON, ShortWait(waited), kind, kindColor, d.name, detail,
                    { category = category, dungeonID = d.id } }
            end
        end
    end

    if C_LFGList then
        -- Your own Group Finder listing.
        if C_LFGList.GetActiveEntryInfo then
            local ok, entry = pcall(C_LFGList.GetActiveEntryInfo)
            if ok and Plain(entry) then
                local name, icon = Activity(entry)
                local title = type(entry) == "table" and entry.name or nil
                local okApps, applicants = false, nil
                if C_LFGList.GetApplicants then okApps, applicants = pcall(C_LFGList.GetApplicants) end
                local count = okApps and type(applicants) == "table" and not issecretvalue(applicants) and #applicants or nil
                rows[#rows + 1] = { icon or ICON_LISTING, nil, L["Your listing"], GREEN,
                    TitleOr(title, name or L["Listed"]),
                    Join({ name, count and count > 0 and (count .. (count == 1 and " applicant" or " applicants")) or nil }) }
            end
        end
        -- Groups you applied to.
        if C_LFGList.GetApplications and C_LFGList.GetApplicationInfo then
            local ok, apps = pcall(C_LFGList.GetApplications)
            if ok and type(apps) == "table" and not issecretvalue(apps) then
                for _, resultID in ipairs(apps) do
                    local okInfo, _, status, _, expires = pcall(C_LFGList.GetApplicationInfo, resultID)
                    status = okInfo and Plain(status) or nil
                    if status == "applied" or status == "invited" then
                        local info = SafeResultInfo(resultID)
                        local name, icon = Activity(info)
                        local title = info and info.name
                        local invited = status == "invited"
                        expires = okInfo and Plain(expires) or nil
                        -- The kind of key run, the leader's rating and how full
                        -- the group is. A field the game keeps secret is left out;
                        -- the leader's name, secret or not, goes to SetText as is.
                        local style = info and (PLAYSTYLES[Plain(info.generalPlaystyle) or 0]
                            or OLD_PLAYSTYLES[Plain(info.playstyle) or 0])
                        local score = info and Plain(info.leaderOverallDungeonScore)
                        local members = info and Plain(info.numMembers)
                        -- No "or" on it: testing a secret is the error.
                        local leaderName = info and info.leaderName
                        local short = name and name:gsub(" %(Mythic Keystone%)$", "") or nil
                        rows[#rows + 1] = { icon or ICON_LISTING, nil,
                            (invited and L["Invited"] or L["Signed up"]) .. (style and ("  ·  " .. style) or ""),
                            invited and GREEN or GOLD,
                            TitleOr(title, name or L["Group"]),
                            Join({ short,
                                type(score) == "number" and score > 0 and ("score " .. math.floor(score)) or nil,
                                type(members) == "number" and members > 0 and (members .. "/5") or nil,
                                Duration(expires) and ("ends " .. Duration(expires)) or nil }),
                            { resultID = resultID },
                            leaderName,
                            resultID }
                    end
                end
            end
        end
    end

    -- Battlegrounds, arenas and brawls.
    if GetMaxBattlefieldID and GetBattlefieldStatus then
        local okMax, max = pcall(GetMaxBattlefieldID)
        max = okMax and Plain(max) or nil
        for i = 1, (type(max) == "number" and max or 0) do
            local ok, status, mapName = pcall(GetBattlefieldStatus, i)
            status = ok and Plain(status) or nil
            if status == "queued" or status == "confirm" then
                local waited, estimate
                if GetBattlefieldTimeWaited then
                    local okW, ms = pcall(GetBattlefieldTimeWaited, i)
                    ms = okW and Plain(ms)
                    if type(ms) == "number" then waited = ms / 1000 end
                end
                if GetBattlefieldEstimatedWaitTime then
                    local okE, ms = pcall(GetBattlefieldEstimatedWaitTime, i)
                    ms = okE and Plain(ms)
                    if type(ms) == "number" then estimate = ms / 1000 end
                end
                local ready = status == "confirm"
                local bgName = PlainText(ok and mapName)
                rows[#rows + 1] = { BattlegroundIcon(bgName) or ICON_PVP, ShortWait(waited),
                    ready and "PvP  ·  Ready" or "PvP", ready and GREEN or GOLD,
                    bgName or "Battleground",
                    Join({ Duration(waited) and ("waited " .. Duration(waited)) or nil,
                        Duration(estimate) and ("est " .. Duration(estimate)) or nil }) }
            end
        end
    end
end

-- Pinned: the list stays on screen at its saved place while anything is
-- queued, and hides itself when nothing is. Otherwise it is a hover panel.
-- Preview: the list with made-up rows, to see it and drag it into place
-- without being queued. Switched by the button in Options.
local queuePreview = false

local function Pinned()
    return queuePreview or Active("queueList")
end

local function SampleRows()
    return {
        { ICON_DUNGEON, "2m", "Dungeon Finder", GOLD, "Murder Row", "waited 2m  ·  est 4m  ·  needs " .. ROLE_HEALER_ICON .. "1", {} },
        { ICON_DUNGEON, "2m", "Dungeon Finder", GOLD, "Windrunner Spire", "waited 2m  ·  est 4m  ·  needs " .. ROLE_HEALER_ICON .. "1", {} },
        { ICON_KEY, nil, "Signed up  ·  Relaxed", GOLD, "+15 Relaxed", "Altar of Fangs  ·  score 2450  ·  3/5  ·  ends 4m", {}, "Oxed" },
        { ICON_LISTING, nil, "Invited  ·  Competitive", GREEN, "Weekly key", "Den of Nalorakk  ·  score 3100  ·  4/5", {}, "Riyadh" },
        { ICON_PVP, "1m", "PvP", GOLD, "Random Battleground", "waited 1m  ·  est 10m" },
    }
end

local function HideQueuePanel()
    queueOwner = nil
    if queuePanel and not Pinned() then queuePanel:Hide() end
end

local function QueueRow(i)
    local row = queuePanel.rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, queuePanel)
    row:SetHeight(Q_ROW)
    row:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 4, -Q_HEADER - 4 - (i - 1) * Q_ROW)
    row:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", -4, -Q_HEADER - 4 - (i - 1) * Q_ROW)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(Q_ICON, Q_ICON)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -3)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.badge = row:CreateFontString(nil, "OVERLAY")
    row.badge:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    row.badge:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", -1, 2)
    row.badge:SetTextColor(1, 1, 1)

    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.kind:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
    row.kind:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    row.kind:SetJustifyH("LEFT")
    row.kind:SetWordWrap(false)
    row.kind:SetShadowOffset(1, -1)

    -- Leave this queue: shown on the pinned list, where the mouse can reach it.
    row.leave = CreateFrame("Button", nil, row)
    row.leave:SetSize(14, 14)
    row.leave:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
    row.leave:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.leave:SetHighlightTexture("Interface\\Buttons\\UI-StopButton", "ADD")
    row.leave:SetScript("OnClick", function(self)
        if self.data and queuePanel.onLeave then queuePanel.onLeave(self.data) end
    end)
    row.leave:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.data and self.data.resultID and L["Cancel this application"] or L["Leave this queue"])
        GameTooltip:Show()
    end)
    row.leave:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.leave:Hide()

    -- The group's leader, at the right end of the name line.
    row.leader = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.leader:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -18)
    row.leader:SetJustifyH("RIGHT")
    row.leader:SetWordWrap(false)
    row.leader:SetTextColor(0.85, 0.85, 0.85)
    row.crown = row:CreateTexture(nil, "OVERLAY")
    row.crown:SetSize(12, 12)
    row.crown:SetPoint("RIGHT", row.leader, "LEFT", -2, 0)
    if not pcall(row.crown.SetAtlas, row.crown, "groupfinder-icon-leader") then
        row.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
    end
    row.crown:Hide()

    -- Hovering a Group Finder row shows the game's own listing tooltip:
    -- note, leader, members, playstyle, voice chat.
    row:SetScript("OnEnter", function(self)
        if not self.resultID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if LFGListUtil_SetSearchEntryTooltip then
            pcall(LFGListUtil_SetSearchEntryTooltip, GameTooltip, self.resultID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:EnableMouse(false)

    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.kind, "BOTTOMLEFT", 0, -2)
    row.title:SetPoint("RIGHT", row.crown, "LEFT", -6, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.title:SetShadowOffset(1, -1)

    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)

    queuePanel.rows[i] = row
    return row
end

local function FillQueuePanel()
    local rows = {}
    CollectQueues(rows)
    if #rows == 0 and queuePreview then rows = SampleRows() end
    if #rows == 0 and not eyeTestMode then queuePanel:Hide() return end

    local maxRows = math.floor(tonumber(settings.listRows) or Q_MAX)
    local shown = math.min(#rows, math.max(1, maxRows))
    for i = 1, shown do
        local data, row = rows[i], QueueRow(i)
        row.icon:SetTexture(data[1])
        row.badge:SetText(data[2] or "")
        row.kind:SetText(data[3])
        row.kind:SetTextColor(data[4][1], data[4][2], data[4][3])
        row.title:SetText(data[5])
        row.detail:SetText(data[6] or "")
        row.detail:SetShown(settings.listDetails ~= false)
        local pinned = Pinned()
        row.leave.data = data[7]
        row.leave:SetShown(pinned and data[7] ~= nil)
        local leader = data[8]
        local hasLeader = issecretvalue(leader) or (type(leader) == "string" and leader ~= "")
        if hasLeader then row.leader:SetText(leader) else row.leader:SetText("") end
        row.crown:SetShown(hasLeader)
        row.resultID = data[9]
        row:EnableMouse(pinned and data[9] ~= nil)
        row:Show()
    end
    for i = shown + 1, #queuePanel.rows do queuePanel.rows[i]:Hide() end

    local extra = #rows - shown
    queuePanel.more:SetShown(extra > 0)
    if extra > 0 then queuePanel.more:SetFormattedText(L["and %d more"], extra) end
    queuePanel.empty:SetShown(#rows == 0)
    queuePanel.count:SetText(#rows > 0 and tostring(#rows) or "")

    local height = Q_HEADER + 8 + math.max(shown, 1) * Q_ROW + (extra > 0 and 14 or 0)
    if #rows == 0 then height = Q_HEADER + 30 end
    queuePanel:SetHeight(height)
    queuePanel:Show()
end

local function BuildQueuePanel()
    queuePanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    queuePanel:SetFrameStrata("TOOLTIP")
    queuePanel:SetClampedToScreen(true)
    queuePanel:SetWidth(Q_WIDTH)
    queuePanel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    queuePanel:SetBackdropColor(0.03, 0.03, 0.05, tonumber(settings.listAlpha) or 0.92)
    queuePanel:SetBackdropBorderColor(0, 0, 0, 0.9)
    queuePanel:Hide()
    queuePanel.rows = {}

    local title = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 7, -5)
    title:SetText(L["Queued For"])
    queuePanel.count = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queuePanel.count:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", -7, -5)

    local line = queuePanel:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 4, -Q_HEADER)
    line:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", -4, -Q_HEADER)
    line:SetHeight(1)
    line:SetColorTexture(1, 0.82, 0, 0.4)

    queuePanel.empty = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queuePanel.empty:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 8, -Q_HEADER - 8)
    queuePanel.empty:SetText(L["Not in any queue."])

    queuePanel.more = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    queuePanel.more:SetPoint("BOTTOMLEFT", queuePanel, "BOTTOMLEFT", 8, 5)

    -- Drag handle for the pinned list: the header strip. Takes the mouse only
    -- while pinned, so the hover panel never blocks clicks beneath it.
    local handle = CreateFrame("Frame", nil, queuePanel)
    handle:SetPoint("TOPLEFT", queuePanel, "TOPLEFT", 0, 0)
    handle:SetPoint("TOPRIGHT", queuePanel, "TOPRIGHT", 0, 0)
    handle:SetHeight(Q_HEADER)
    handle:RegisterForDrag("LeftButton")
    handle:EnableMouse(false)
    handle:SetScript("OnDragStart", function()
        if not settings.listLocked or queuePreview then queuePanel:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        queuePanel:StopMovingOrSizing()
        local point, _, relativePoint, x, y = queuePanel:GetPoint(1)
        settings.queuePoint = { point = point or "TOP", relativePoint = relativePoint or "TOP", x = x or 0, y = y or 0 }
    end)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Queued For"])
        GameTooltip:AddLine(L["Drag to move. Hides itself when you are not queued."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    queuePanel.handle = handle
    queuePanel:SetMovable(true)

    -- The row's X. Leaving needs no protected call: LeaveSingleLFG / LeaveLFG
    -- for the finder queues, CancelApplication for a Group Finder sign-up,
    -- both from the player's own click.
    queuePanel.onLeave = function(leave)
        if leave.resultID then
            if C_LFGList and C_LFGList.CancelApplication then pcall(C_LFGList.CancelApplication, leave.resultID) end
        elseif leave.category then
            if leave.dungeonID and LeaveSingleLFG then
                pcall(LeaveSingleLFG, leave.category, leave.dungeonID)
            elseif LeaveLFG then
                pcall(LeaveLFG, leave.category)
            end
        end
        GameTooltip:Hide()
        C_Timer.After(0.5, function()
            if queuePanel:IsShown() then FillQueuePanel() end
        end)
    end

    -- Times waited tick on: while the mouse stays on the eye, or always when pinned.
    local sinceFill = 0
    queuePanel:SetScript("OnUpdate", function(_, elapsed)
        sinceFill = sinceFill + elapsed
        if sinceFill < 1 then return end
        sinceFill = 0
        if not Pinned() and (not queueOwner or not queueOwner:IsMouseOver()) then HideQueuePanel() return end
        FillQueuePanel()
    end)
end

-- Size, width and opacity from Options. Rows hang off TOPLEFT and TOPRIGHT,
-- so a new width carries them along; a shorter row hides its details line.
local function ApplyQueueLook()
    if not queuePanel then return end
    queuePanel:SetScale(math.max(0.5, math.min(2, tonumber(settings.listScale) or 1)))
    queuePanel:SetWidth(math.max(220, math.min(480, tonumber(settings.listWidth) or Q_WIDTH)))
    local alpha = math.max(0, math.min(1, tonumber(settings.listAlpha) or 0.92))
    queuePanel:SetBackdropColor(0.03, 0.03, 0.05, alpha)
    queuePanel:SetBackdropBorderColor(0, 0, 0, math.min(0.9, alpha + 0.1))
end

-- Puts the panel in pinned or hover form. Pinned: its saved place, under
-- other windows, header draggable.
local function PlacePinned()
    local p = type(settings.queuePoint) == "table" and settings.queuePoint or nil
    queuePanel:ClearAllPoints()
    if p then
        queuePanel:SetPoint(p.point or "TOP", UIParent, p.relativePoint or "TOP", p.x or 0, p.y or 0)
    else
        queuePanel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -220)
    end
    queuePanel:SetFrameStrata("MEDIUM")
    queuePanel.handle:EnableMouse(true)
end

local function UpdatePinnedList()
    if not Pinned() then
        if queuePanel and queuePanel.handle:IsMouseEnabled() then
            queuePanel.handle:EnableMouse(false)
            queuePanel:Hide()
        end
        return
    end
    if not queuePanel then BuildQueuePanel() end
    ApplyQueueLook()
    PlacePinned()
    FillQueuePanel()
end

-- Queue events come in bursts; one refresh a moment later covers them all.
local pinnedRefreshQueued = false
local function RequestPinnedRefresh()
    if pinnedRefreshQueued or not Pinned() then return end
    pinnedRefreshQueued = true
    C_Timer.After(0.3, function()
        pinnedRefreshQueued = false
        UpdatePinnedList()
    end)
end

local function ShowQueuePanel(button)
    if not Active("eyeTooltip") or not button then return end
    -- Pinned, the list is already on screen; refresh it rather than move it.
    if Pinned() then UpdatePinnedList() return end
    if not queuePanel then BuildQueuePanel() end
    queueOwner = button
    ApplyQueueLook()
    queuePanel:SetFrameStrata("TOOLTIP")
    queuePanel.handle:EnableMouse(false)

    -- Beside Blizzard's queue window when it is open, on the side of the
    -- screen with room.
    local anchor = (QueueStatusFrame and QueueStatusFrame:IsShown()) and QueueStatusFrame or button
    local x = button:GetCenter()
    local onRight = x and (x * button:GetEffectiveScale() / UIParent:GetEffectiveScale()) > UIParent:GetWidth() / 2
    queuePanel:ClearAllPoints()
    if onRight then
        queuePanel:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -4, 0)
    else
        queuePanel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    end
    FillQueuePanel()
end

local function HookEyeTooltip()
    if hooked.eyeTip then return end
    local button = GetQueueEyeButton()
    if not button then return end
    hooked.eyeTip = true
    button:HookScript("OnEnter", ShowQueuePanel)
    button:HookScript("OnLeave", HideQueuePanel)
end

-- ── Events ──────────────────────────────────────────────────────────────────

local function Setup()
    HookFinderFrames()
    BuildRoleBar()
    HookEyeTooltip()
    RequestPinnedRefresh()
    if Active("movableEye") then
        SetupEyeButton()
        RestoreEyePosition()
        UpdateEyeAppearance()
    end
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
        RequestPinnedRefresh()
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        Setup()
        if Active("doubleClick") then C_Timer.After(0.1, HookListingButtons) end
    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        OnApplicationStatus(arg1, arg2)
        RequestPinnedRefresh()
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        RefreshRoleBar()
    elseif event == "LFG_UPDATE" or event == "LFG_QUEUE_STATUS_UPDATE" or event == "UPDATE_BATTLEFIELD_STATUS"
        or event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" or event == "LFG_LIST_APPLICANT_LIST_UPDATED" then
        RequestPinnedRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingEyeRestore then
            pendingEyeRestore = false
            RestoreEyePosition()
        end
    end
end)

local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "LFG_ROLE_CHECK_SHOW",
    "LFG_PROPOSAL_SHOW", "LFG_PROPOSAL_SUCCEEDED", "LFG_PROPOSAL_FAILED",
    "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_APPLICATION_STATUS_UPDATED",
    "PLAYER_SPECIALIZATION_CHANGED", "PLAYER_REGEN_ENABLED",
    "LFG_UPDATE", "LFG_QUEUE_STATUS_UPDATE", "UPDATE_BATTLEFIELD_STATUS",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_APPLICANT_LIST_UPDATED",
}

-- The stand-alone AutoQueue does all of this too; both at once would answer
-- every role check twice.
local function StandaloneLoaded()
    return IsLoaded("AutoQueue")
end

local function Start()
    if StandaloneLoaded() then
        print(PREFIX .. L["Auto Queue is off while the AutoQueue addon is loaded: it does the same job. Disable one of them."])
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
    eyeTestMode = false
    UpdateEyeAppearance()
    queueOwner = nil
    queuePreview = false
    if queuePanel then queuePanel:Hide() end
end

-- ── Slash command ───────────────────────────────────────────────────────────

local function PrintStatus()
    print(PREFIX .. L["Auto Queue is "] .. (Active() and "|cff00ff00on|r" or "|cffff4444off|r") .. ".")
    local picked = PickedRoles()
    local any = picked.tank or picked.healer or picked.dps
    print(L["  Queue roles: "] .. (any and RolesText(picked.tank, picked.healer, picked.dps)
        or (L["your spec's ("] .. RolesText(QueueRoles()) .. ")")))
    print(L["  /aq on, /aq off, /aq eye (preview), or Options on its card under Modules."])
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
        print(PREFIX .. "Auto Queue " .. (on and L["on."] or L["off."]))
    elseif message == "eye" or message == "eyetest" or message == "testeye" then
        SetEyeTestMode(not eyeTestMode)
        print(PREFIX .. L["LFG Eye test preview "] .. (eyeTestMode and L["|cff00ff00enabled|r."] or L["|cffff4444disabled|r."]))
    elseif message == "reseteye" then
        if settings then
            settings.eyePoint = nil
            settings.eyeScale = 1.0
            settings.eyeLocked = false
        end
        RestoreEyePosition()
        UpdateEyeAppearance()
        print(PREFIX .. L["LFG Eye position reset to default."])
    else
        PrintStatus()
    end
end

SLASH_OXEDAUTOQUEUE_EYE1 = "/eye"
SLASH_OXEDAUTOQUEUE_EYE2 = "/lfgeye"
SlashCmdList["OXEDAUTOQUEUE_EYE"] = function()
    SetEyeTestMode(not eyeTestMode)
    print(PREFIX .. L["LFG Eye test preview "] .. (eyeTestMode and L["|cff00ff00enabled|r."] or L["|cffff4444disabled|r."]))
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

-- The queue list's look, in a window of its own: the main one is full.
local function ShowListOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not listOptionsWindow then
        local o = API:CreateOptionsWindow("Queue List", 420, 400)
        local function Refresh() UpdatePinnedList() if queuePanel and queuePanel:IsShown() then ApplyQueueLook() FillQueuePanel() end end
        o:AddCheckbox(settings, "listLocked", "Lock the list", "Locked, its header no longer drags it. Preview still can.", Refresh)
        o:AddCheckbox(settings, "listDetails", "Show the details line", "Time waited, estimate, who is missing, expiry.", Refresh)
        o:AddSlider(settings, "listScale", "Size", 0.6, 1.8, 0.05, "%s: %.2fx", Refresh)
        o:AddSlider(settings, "listAlpha", "Background opacity", 0, 1, 0.05, "%s: %.2f", Refresh)
        o:AddSlider(settings, "listWidth", "Width", 220, 480, 10, "%s: %d", Refresh)
        o:AddSlider(settings, "listRows", "Rows shown", 3, 12, 1, "%s: %d", Refresh)

        local reset = CreateFrame("Button", nil, o, "UIPanelButtonTemplate")
        reset:SetSize(160, 24)
        reset:SetPoint("TOPLEFT", o, "TOPLEFT", 18, o.cursorY)
        reset:SetText(L["Reset Position"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(reset) end
        reset:SetScript("OnClick", function()
            settings.queuePoint = nil
            Refresh()
            print(PREFIX .. L["queue list moved back to its starting place."])
        end)
        o.cursorY = o.cursorY - 34
        o:AddNote("Press Preview List in Auto Queue's options to see changes without being queued.")
        listOptionsWindow = o
    end
    listOptionsWindow:Show()
end

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end

    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Auto Queue", 450, 690)
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

        w:AddCheckbox(settings, "movableEye", "Make LFG Eye movable",
            "Makes Blizzard's Queue Status \"Eye\" icon movable anywhere on your screen. Left-click and drag to move.", function(checked)
                if checked then
                    SetupEyeButton()
                    RestoreEyePosition()
                end
                UpdateEyeAppearance()
            end)
        w:AddCheckbox(settings, "eyeLocked", "Lock LFG Eye position",
            "Locks the LFG Eye in place to prevent accidental dragging.", function()
                UpdateEyeAppearance()
            end)
        w:AddCheckbox(settings, "eyeTooltip", "List my queues when hovering the eye",
            "Names every dungeon, raid wing, Group Finder group and PvP queue you are in, with time waited.", HideQueuePanel)
        w:AddCheckbox(settings, "queueList", "Keep the queue list on screen",
            "While you are queued the list stays up; drag its header to move it. It hides when you are not queued.", UpdatePinnedList)
        w:AddSlider(settings, "eyeScale", "LFG Eye scale", 0.5, 2.5, 0.1, "%s: %.1fx", function()
            UpdateEyeAppearance()
        end)

        -- Action buttons for LFG Eye
        local eyeBtnRow = CreateFrame("Frame", nil, w)
        eyeBtnRow:SetSize(400, 28)
        eyeBtnRow:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY)

        local testEyeBtn = CreateFrame("Button", nil, eyeBtnRow, "UIPanelButtonTemplate")
        testEyeBtn:SetSize(120, 24)
        testEyeBtn:SetPoint("LEFT", eyeBtnRow, "LEFT", 0, 0)
        testEyeBtn:SetText(L["Test / Drag Eye"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(testEyeBtn)
        end
        testEyeBtn:SetScript("OnClick", function()
            SetEyeTestMode(not eyeTestMode)
        end)

        local resetEyeBtn = CreateFrame("Button", nil, eyeBtnRow, "UIPanelButtonTemplate")
        resetEyeBtn:SetSize(120, 24)
        resetEyeBtn:SetPoint("LEFT", testEyeBtn, "RIGHT", 10, 0)
        resetEyeBtn:SetText(L["Reset Position"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(resetEyeBtn)
        end
        resetEyeBtn:SetScript("OnClick", function()
            if settings then
                settings.eyePoint = nil
                settings.eyeScale = 1.0
                settings.eyeLocked = false
            end
            RestoreEyePosition()
            UpdateEyeAppearance()
            print(PREFIX .. L["LFG Eye position reset to default."])
        end)

        w.cursorY = w.cursorY - 32

        -- The queue list: preview it (sample rows, drag the header) and put it back.
        local listRow = CreateFrame("Frame", nil, w)
        listRow:SetSize(400, 28)
        listRow:SetPoint("TOPLEFT", w, "TOPLEFT", 18, w.cursorY)

        local previewBtn = CreateFrame("Button", nil, listRow, "UIPanelButtonTemplate")
        previewBtn:SetSize(120, 24)
        previewBtn:SetPoint("LEFT", listRow, "LEFT", 0, 0)
        previewBtn:SetText(L["Preview List"])
        local resetListBtn = CreateFrame("Button", nil, listRow, "UIPanelButtonTemplate")
        resetListBtn:SetSize(120, 24)
        resetListBtn:SetPoint("LEFT", previewBtn, "RIGHT", 10, 0)
        resetListBtn:SetText(L["List Settings"])
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then
            OxedHub.UI:ApplyRedButtonStyle(previewBtn)
            OxedHub.UI:ApplyRedButtonStyle(resetListBtn)
        end
        previewBtn:SetScript("OnClick", function(self)
            queuePreview = not queuePreview
            self:SetText(queuePreview and L["Stop Preview"] or L["Preview List"])
            UpdatePinnedList()
            if not queuePreview and queuePanel and not Active("queueList") then queuePanel:Hide() end
        end)
        previewBtn:SetScript("OnHide", function(self)
            -- Closing Options ends the preview.
            if queuePreview then
                queuePreview = false
                self:SetText(L["Preview List"])
                UpdatePinnedList()
                if queuePanel and not Active("queueList") then queuePanel:Hide() end
            end
        end)
        resetListBtn:SetScript("OnClick", function() ShowListOptions() end)

        w.cursorY = w.cursorY - 36

        w:AddNote("Roles are saved per character. /aq shows status, /eye toggles the preview. With Premade Groups Filter loaded, sign-up and note keeping are left to it.")
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
        version  = "1.3.1",
        updated  = 20261021.6,  -- leave queues, leader and playstyle on rows
        author   = "Oxed",
        category = "groups",
        keywords = { "queue", "lfg", "group finder", "role check", "ready check", "dungeon", "apply", "sign up", "eye", "movable eye" },
        desc     = "Answers role checks, signs up in Group Finder, movable LFG eye that lists your queues.",
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
