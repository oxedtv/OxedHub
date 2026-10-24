local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local DB                                     = KeystoneLoot.DB;
local Keystone                               = KeystoneLoot.Keystone;
local Query                                  = KeystoneLoot.Query;
local L                                      = KeystoneLoot.L;

local FRAME_PADDING                          = 30;
local CARD_TEXT_LEFT                         = 40;
local CARD_PADDING                           = 7;

local FULL_GROUP_SIZE                        = 5;

local ROLE_ATLAS                             = {
    TANK    = "GM-icon-role-tank",
    HEALER  = "GM-icon-role-healer",
    DAMAGER = "GM-icon-role-dps"
};

local instanceIdToDungeon                    = {};

-- The group's own listing under the teleport card: its name, leader, play
-- style and description, so they can still be read once the finder closes.
-- ⚠ A listing's name and comment are protected strings: they may only be
-- handed to SetText, never joined, compared or measured as Lua strings.
local DETAILS_TOP                            = 112;
local DETAILS_BOTTOM                         = 24;
local DETAIL_LABEL_W                         = 74;
local MIN_WIDTH                              = 340;
local DETAIL_ROWS                            = { "name", "leader", "playstyle", "comment" };
local DETAIL_LABELS                          = {
    name      = "Group:",
    leader    = "Leader:",
    playstyle = "Playstyle:",
    comment   = "Description:",
};

local function PlaystyleText(info, activityInfo)
    local style = info.generalPlaystyle;
    if (type(style) == "number" and style > 0) then
        local text = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. style];
        if (type(text) == "string") then return text; end
    end
    style = info.playstyle;
    if (style and C_LFGList.GetPlaystyleString and activityInfo) then
        local ok, text = pcall(C_LFGList.GetPlaystyleString, style, activityInfo);
        if (ok and type(text) == "string" and text ~= "") then return text; end
    end
    return nil;
end

-- What the window shows about a group, read while the listing still exists.
local function ListingDetails(info, activityInfo, leader)
    if (type(info) ~= "table") then return nil; end
    return {
        name      = info.name,
        comment   = info.comment,
        leader    = leader or info.leaderName,
        playstyle = PlaystyleText(info, activityInfo),
    };
end

local function IsBlank(value)
    if (value == nil) then return true; end
    if (issecretvalue and issecretvalue(value)) then return false; end
    return type(value) == "string" and value == "";
end

OxMythicLooterMythicPlusNotificationFrameMixin = {};

function OxMythicLooterMythicPlusNotificationFrameMixin:CreateDetails()
    self.detailRows = {};
    for _, key in ipairs(DETAIL_ROWS) do
        local label = self:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
        label:SetWidth(DETAIL_LABEL_W);
        label:SetJustifyH("RIGHT");
        label:SetText(DETAIL_LABELS[key]);

        local value = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
        value:SetJustifyH("LEFT");
        value:SetJustifyV("TOP");
        value:SetPoint("TOPLEFT", label, "TOPRIGHT", 6, 0);
        value:SetPoint("RIGHT", self, "RIGHT", -FRAME_PADDING, 0);
        value:SetWordWrap(key == "comment");
        if (key == "comment") then value:SetTextColor(1, 1, 1); end

        self.detailRows[key] = { label = label, value = value };
    end
end

-- Fills the rows and returns how tall they came out.
function OxMythicLooterMythicPlusNotificationFrameMixin:ShowDetails(details)
    local y = 0;
    for _, key in ipairs(DETAIL_ROWS) do
        local row = self.detailRows[key];
        local text = details and details[key];
        if (IsBlank(text)) then
            row.label:Hide();
            row.value:Hide();
        else
            row.label:ClearAllPoints();
            row.label:SetPoint("TOPLEFT", self, "TOPLEFT", FRAME_PADDING, -(DETAILS_TOP + y));
            row.value:SetText(text);
            row.label:Show();
            row.value:Show();
            -- The height of a protected text can itself come back secret.
            local ok, h = pcall(row.value.GetStringHeight, row.value);
            if (not ok or type(h) ~= "number" or (issecretvalue and issecretvalue(h))) then
                h = key == "comment" and 42 or 14;
            end
            y = y + math.max(14, h) + 4;
        end
    end
    return y;
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnLoad()
    self:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED");
    self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterForDrag("LeftButton");

    self.Inset:Hide();
    self.Bg:SetPoint("TOPLEFT", 0, -6);
    self.Bg:SetPoint("BOTTOMRIGHT", -4, 3);
    self.HeadlineBg:SetVertexColor(0.1, 0.1, 0.1, 1);
    self.AddonLabel:SetText(AddonName);
    self:CreateDetails();

    for _, dungeon in ipairs(Query:GetDungeons()) do
        instanceIdToDungeon[dungeon.instanceId] = dungeon;
    end
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnShow()
    PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN);
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnHide()
    PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE);
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnDragStart()
    self:StartMoving();
    self:SetUserPlaced(true);
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnDragStop()
    self:StopMovingOrSizing();
end

function OxMythicLooterMythicPlusNotificationFrameMixin:OnEvent(event, ...)
    if (event == "PLAYER_ENTERING_WORLD") then
        self:Hide();
        return;
    end

    if (event == "PLAYER_REGEN_ENABLED") then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED");

        local groupInfo = self.groupInfo;
        if (groupInfo and self.pendingOpen) then
            self.pendingOpen = nil;
            self:Open(groupInfo.instanceId, groupInfo.activityName, self.pendingIsFull);
        end

        return;
    end

    if (event == "GROUP_LEFT") then
        self.groupInfo = nil;
        self.pendingOpen = nil;
        self.suppressResultId = nil;
        self.appliedRole = nil;
        self.details = nil;

        self:UnregisterEvent("GROUP_ROSTER_UPDATE");
        self:UnregisterEvent("GROUP_LEFT");
        self:UnregisterEvent("PLAYER_REGEN_ENABLED");
        return;
    end

    if (event == "GROUP_ROSTER_UPDATE") then
        self:CheckFullGroup();
        return;
    end

    if (event == "LFG_LIST_ACTIVE_ENTRY_UPDATE") then
        self:CheckActiveEntry();
        return;
    end

    local searchResultId, newStatus = ...;
    if (newStatus ~= "inviteaccepted") then
        return;
    end

    local showJoined = DB:Get("settings.mythicPlusNotification.joined");
    if (not showJoined and not DB:Get("settings.mythicPlusNotification.full")) then
        return;
    end

    local searchResultInfo = C_LFGList.GetSearchResultInfo(searchResultId);
    if (not searchResultInfo) then
        return;
    end

    local activityInfo = C_LFGList.GetActivityInfoTable(searchResultInfo.activityIDs[1], nil, searchResultInfo.isWarMode);
    if (not activityInfo or not activityInfo.isMythicPlusActivity) then
        return;
    end

    local _, _, _, _, role = C_LFGList.GetApplicationInfo(searchResultId);
    self.appliedRole = role;
    self.details = ListingDetails(searchResultInfo, activityInfo);

    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("GROUP_LEFT");

    if (showJoined) then
        self.suppressResultId = searchResultId;
        self:HideJoinDialog();

        self:Open(activityInfo.mapID, activityInfo.fullName, false);
    else
        self.groupInfo = {
            instanceId    = activityInfo.mapID,
            activityName  = activityInfo.fullName,
            sawIncomplete = true
        };
    end
end

function OxMythicLooterMythicPlusNotificationFrameMixin:CheckActiveEntry()
    if (self.groupInfo or not DB:Get("settings.mythicPlusNotification.full")) then
        return;
    end

    local entryData = C_LFGList.GetActiveEntryInfo();
    if (not entryData) then
        return;
    end

    local activityInfo = C_LFGList.GetActivityInfoTable(entryData.activityIDs[1]);
    if (not activityInfo or not activityInfo.isMythicPlusActivity) then
        return;
    end

    self.groupInfo = {
        instanceId    = activityInfo.mapID,
        activityName  = activityInfo.fullName,
        sawIncomplete = GetNumGroupMembers() < FULL_GROUP_SIZE
    };
    -- Our own listing: we lead it.
    self.details = ListingDetails(entryData, activityInfo, UnitName("player"));

    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("GROUP_LEFT");
end

function OxMythicLooterMythicPlusNotificationFrameMixin:HideJoinDialog()
    local Dialog = LFGListInviteDialog;

    if (Dialog and Dialog:IsShown() and Dialog.informational and Dialog.resultID == self.suppressResultId) then
        StaticPopupSpecial_Hide(Dialog);
    end
end

function OxMythicLooterMythicPlusNotificationFrameMixin:CheckFullGroup()
    local groupInfo = self.groupInfo;
    if (not groupInfo) then
        return;
    end

    if (GetNumGroupMembers() < FULL_GROUP_SIZE) then
        groupInfo.sawIncomplete = true;
        return;
    end

    self:UnregisterEvent("GROUP_ROSTER_UPDATE");

    if (groupInfo.sawIncomplete and DB:Get("settings.mythicPlusNotification.full")) then
        self:Open(groupInfo.instanceId, groupInfo.activityName, true);
    else
        self.groupInfo = nil;
    end
end

function OxMythicLooterMythicPlusNotificationFrameMixin:Open(instanceId, activityName, isFull)
    local dungeon = instanceIdToDungeon[instanceId];
    if (dungeon and Keystone:GetCurrentChallengeMapId() == dungeon.challengeModeId) then
        self.groupInfo = nil;
        return;
    end

    local groupInfo = self.groupInfo or {};

    groupInfo.instanceId = instanceId;
    groupInfo.activityName = activityName;
    self.groupInfo = groupInfo;

    if (InCombatLockdown()) then
        self.pendingOpen = true;
        self.pendingIsFull = isFull;
        self:RegisterEvent("PLAYER_REGEN_ENABLED");
        return;
    end

    local Card = self.Card;
    local dungeonName = activityName;

    if (dungeon) then
        local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(dungeon.challengeModeId);
        dungeonName = mapName or dungeonName;

        Card:Init(dungeon, texture);
        Card:UpdateCooldown();
    else
        Card.Icon:SetTexture(nil);
        Card.Cooldown:Hide();
        Card:Disable();
    end

    self.Title:SetText(isFull and L["Group is full!"] or L["Mythic+ group joined!"]);
    Card.DungeonName:SetText(dungeonName);

    local role = UnitGroupRolesAssigned("player");
    if (not ROLE_ATLAS[role]) then
        role = self.appliedRole;
    end

    local atlas = role and ROLE_ATLAS[role];
    Card.RoleIcon:SetShown(atlas ~= nil);
    Card.RoleText:SetText(atlas and _G[role] or "");

    if (atlas) then
        Card.RoleIcon:SetAtlas(atlas);
    end

    local width = FRAME_PADDING * 2 + CARD_TEXT_LEFT + CARD_PADDING + Card.DungeonName:GetStringWidth();
    local detailsHeight = self:ShowDetails(self.details);
    if (detailsHeight > 0) then
        width = math.max(width, MIN_WIDTH);
        self:SetWidth(width);
        -- Laid out again now the width is known, so the description wraps right.
        detailsHeight = self:ShowDetails(self.details);
        self:SetHeight(DETAILS_TOP + detailsHeight + DETAILS_BOTTOM);
    else
        self:SetWidth(width);
        self:SetHeight(119);
    end
    self:Show();
    self:AnnounceInChat(dungeonName, role, atlas, isFull);

    if (isFull) then
        self.groupInfo = nil;
    end
end

-- A line in chat too, with a link that brings the window back once it is
-- closed. ⚠ The group's name and description are protected strings and
-- cannot be joined into the line; they are in the window.
local REMINDER_LINK = "addon:oxmythiclooter:reminder";
local ORANGE = "ffff8000";

function OxMythicLooterMythicPlusNotificationFrameMixin:AnnounceInChat(dungeonName, role, atlas, isFull)
    local parts = {};
    parts[#parts + 1] = ("|c%s%s|r"):format(ORANGE, tostring(dungeonName or "Mythic+"));
    local style = self.details and self.details.playstyle;
    if (type(style) == "string" and not (issecretvalue and issecretvalue(style))) then
        parts[#parts + 1] = ("|c%s%s|r"):format(ORANGE, style);
    end
    local line = table.concat(parts, ", ");
    if (atlas and role and _G[role]) then
        local icon = CreateAtlasMarkup and CreateAtlasMarkup(atlas, 14, 14) or "";
        line = line .. (", as a |c%s%s|r %s"):format(ORANGE, _G[role], icon);
    end
    local lead = isFull and "Your group is full: " or "You have been invited to ";
    print(("|cffff4040%s|r - |cffffd100Group Reminder|r: %s%s |cffffd100|H%s|h[Open reminder]|h|r")
        :format(AddonName, lead, line, REMINDER_LINK));
end

if (EventRegistry and EventRegistry.RegisterCallback) then
    -- Whether the owner comes first depends on the build; the link is
    -- whichever of the first two arguments it is.
    EventRegistry:RegisterCallback("SetItemRef", function(a, b)
        if (a ~= REMINDER_LINK and b ~= REMINDER_LINK) then return; end
        local frame = OxMythicLooterMythicPlusNotificationFrame;
        if (frame and frame.Card and frame.Card.DungeonName:GetText()) then
            frame:Show();
        end
    end);
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder", function()
    hooksecurefunc("LFGListInviteDialog_Show", function(Dialog)
        OxMythicLooterMythicPlusNotificationFrame:HideJoinDialog();
    end);
end);
