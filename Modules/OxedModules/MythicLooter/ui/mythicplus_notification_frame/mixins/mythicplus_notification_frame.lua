local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";
local print = OxedHub.Print or print

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

-- Every option of this window is on until switched off: a key that was
-- never saved reads as on, so players who had the window before keep it.
local function Opt(name)
    return DB:Get("settings.mythicPlusNotification." .. name) ~= false;
end

-- The options added with the group reminder. Written as true once settings
-- are ready, so the tick boxes in both menus (which read nil as off) agree
-- with Opt.
local OPTIONS = {
    "leaderFull", "chat", "hideBlizzardInvite", "showRole", "showTeleportHint",
    "showGroupName", "showLeader", "showPlaystyle", "showDescription",
};

KeystoneLoot.API:RegisterCallback("READY", function()
    for _, name in ipairs(OPTIONS) do
        local key = "settings.mythicPlusNotification." .. name;
        if (DB:Get(key) == nil) then DB:Set(key, true); end
    end
end, "GroupReminderDefaults");

-- Which option shows each detail row.
local DETAIL_OPTION = {
    name = "showGroupName", leader = "showLeader", playstyle = "showPlaystyle", comment = "showDescription",
};

-- A listing name worth showing. A protected one is passed on (only SetText
-- may touch it); an empty one, or the game's own "Unknown" placeholder, is
-- dropped so the row hides instead of reading "Unknown".
local function GroupName(value)
    if (value == nil) then return nil; end
    if (issecretvalue and issecretvalue(value)) then return value; end
    if (type(value) ~= "string" or value == "" or value == UNKNOWN) then return nil; end
    return value;
end

-- Our own listing's name, as typed in the group finder's listing form. The
-- active entry often hands back a placeholder for it.
local function OwnListingName()
    local box = LFGListFrame and LFGListFrame.EntryCreation and LFGListFrame.EntryCreation.Name;
    if (not box or not box.GetText) then return nil; end
    local ok, text = pcall(box.GetText, box);
    if (not ok or (issecretvalue and issecretvalue(text))) then return nil; end
    return GroupName(text);
end

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
local function ListingDetails(info, activityInfo, leader, own)
    if (type(info) ~= "table") then return nil; end
    return {
        name      = own and (OwnListingName() or GroupName(info.name)) or GroupName(info.name),
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

-- Where the details start: below the card, measured once the window is on
-- screen. A skin or a larger font can make the card's icon and text taller
-- than the card itself, and a fixed offset then wrote the details over them.
function OxMythicLooterMythicPlusNotificationFrameMixin:DetailsTop()
    local top = self:GetTop();
    local Card = self.Card;
    local lowest = Card and Card:GetBottom();
    if (not top or not lowest) then return DETAILS_TOP; end
    for _, region in ipairs({ Card.Icon, Card.IconBorder, Card.DungeonName, Card.RoleIcon, Card.RoleText, self.TeleportHint }) do
        local bottom = region and region:IsShown() and region:GetBottom();
        if (bottom and bottom < lowest) then lowest = bottom; end
    end
    return math.max(DETAILS_TOP, math.ceil(top - lowest + 10));
end

-- Fills the rows and returns how tall they came out.
function OxMythicLooterMythicPlusNotificationFrameMixin:ShowDetails(details)
    local y = 0;
    local detailsTop = self:DetailsTop();
    self.detailsTop = detailsTop;
    for _, key in ipairs(DETAIL_ROWS) do
        local row = self.detailRows[key];
        local text = details and details[key];
        if (IsBlank(text) or not Opt(DETAIL_OPTION[key])) then
            row.label:Hide();
            row.value:Hide();
        else
            row.label:ClearAllPoints();
            row.label:SetPoint("TOPLEFT", self, "TOPLEFT", FRAME_PADDING, -(detailsTop + y));
            -- Set here, not when the frame is made: that happens before the
            -- language is known.
            row.label:SetText(L[DETAIL_LABELS[key]]);
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
    -- ⚠ Switched off: the window on joining a group is Inviter Info's now
    -- (Modules\OxedModules\InviterInfo). This frame listens for nothing, so
    -- the two never both open.
    self:RegisterForDrag("LeftButton");

    self.Inset:Hide();
    self.Bg:SetPoint("TOPLEFT", 0, -6);
    self.Bg:SetPoint("BOTTOMRIGHT", -4, 3);
    self.HeadlineBg:SetVertexColor(0.1, 0.1, 0.1, 1);
    self.AddonLabel:SetText(AddonName);
    self:CreateDetails();

    -- Under the dungeon and role: whether a click on the portrait teleports.
    self.TeleportHint = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
    self.TeleportHint:SetJustifyH("CENTER");
    self.TeleportHint:Hide();

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
    if (self.groupInfo or not DB:Get("settings.mythicPlusNotification.full") or not Opt("leaderFull")) then
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
    self.details = ListingDetails(entryData, activityInfo, UnitName("player"), true);

    self:RegisterEvent("GROUP_ROSTER_UPDATE");
    self:RegisterEvent("GROUP_LEFT");
end

function OxMythicLooterMythicPlusNotificationFrameMixin:HideJoinDialog()
    if (not Opt("hideBlizzardInvite")) then return; end
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
    local showRole = Opt("showRole");
    Card.RoleIcon:SetShown(showRole and atlas ~= nil);
    Card.RoleText:SetShown(showRole);
    Card.RoleText:SetText(atlas and _G[role] or "");

    if (atlas) then
        Card.RoleIcon:SetAtlas(atlas);
    end

    -- The teleport, said in words: the portrait alone does not say it is a
    -- button, and an unlearned teleport looks the same as a learned one.
    local hint = self.TeleportHint;
    -- Read from the dungeon, not the card: the card keeps the last teleport
    -- it was given when a dungeon has none.
    local spellId = dungeon and dungeon.teleportSpellId;
    if (type(spellId) == "function") then spellId = spellId(); end
    hint:ClearAllPoints();
    hint:SetPoint("TOP", showRole and Card.RoleText or Card.DungeonName, "BOTTOM", showRole and -9 or 0, -4);
    if (not Opt("showTeleportHint") or not spellId) then
        hint:Hide();
    elseif (IsSpellKnown(spellId)) then
        hint:SetText(L["Click the portrait to teleport"]);
        hint:SetTextColor(0.6, 1, 0.6);
        hint:Show();
    else
        hint:SetText(L["Teleport not learned yet"]);
        hint:SetTextColor(1, 0.45, 0.45);
        hint:Show();
    end

    -- What this window shows, kept apart from self.details: a test fills the
    -- window without touching the real group's details.
    self.shownDetails = self.details;

    local width = FRAME_PADDING * 2 + CARD_TEXT_LEFT + CARD_PADDING + Card.DungeonName:GetStringWidth();
    local detailsHeight = self:ShowDetails(self.shownDetails);
    self.hasDetails = detailsHeight > 0;
    if (detailsHeight > 0) then
        width = math.max(width, MIN_WIDTH);
        self:SetWidth(width);
        -- Laid out again now the width is known, so the description wraps right.
        detailsHeight = self:ShowDetails(self.shownDetails);
    else
        self:SetWidth(width);
    end
    self:FitHeight(detailsHeight);
    self:Show();
    -- Measured again a frame later, once the card has its real size on screen.
    C_Timer.After(0, function()
        if (not self:IsShown()) then return; end
        self:FitHeight(self:ShowDetails(self.shownDetails));
    end);
    if (Opt("chat")) then
        self:AnnounceInChat(dungeonName, role, atlas, isFull);
    end

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
    if (Opt("showRole") and atlas and role and _G[role]) then
        local icon = CreateAtlasMarkup and CreateAtlasMarkup(atlas, 14, 14) or "";
        line = line .. L[", as a %s %s"]:format(("|c%s%s|r"):format(ORANGE, _G[role]), icon);
    end
    local lead = isFull and L["Your group is full: "] or L["You have been invited to "];
    print(("|cffff4040%s|r. |cffffd100%s|r: %s%s |cffffd100|H%s|h[%s]|h|r")
        :format(AddonName, L["Group Reminder"], lead, line, REMINDER_LINK, L["Open reminder"]));
end

-- The window's height: down to the last detail row, or with none shown,
-- just below the card and the teleport line.
function OxMythicLooterMythicPlusNotificationFrameMixin:FitHeight(detailsHeight)
    if (detailsHeight and detailsHeight > 0) then
        self:SetHeight(self.detailsTop + detailsHeight + DETAILS_BOTTOM);
    else
        self:SetHeight(math.max(119, self:DetailsTop() + 6));
    end
end

-- The window as it would look on joining a group, with made-up details, so
-- the options can be seen without queueing. The real group's state is put
-- back afterwards.
function OxMythicLooterMythicPlusNotificationFrameMixin:Test()
    if (InCombatLockdown()) then return; end
    local dungeon;
    for _, entry in pairs(instanceIdToDungeon) do
        dungeon = entry;
        if (IsSpellKnown and type(entry.teleportSpellId) == "number" and IsSpellKnown(entry.teleportSpellId)) then
            break
        end
    end
    if (not dungeon) then return; end

    local groupInfo, details, appliedRole = self.groupInfo, self.details, self.appliedRole;
    self.groupInfo = nil;
    self.appliedRole = "DAMAGER";
    self.details = {
        name      = L["Test group"],
        leader    = UnitName("player"),
        playstyle = GROUP_FINDER_GENERAL_PLAYSTYLE2 or L["Fun"],
        comment   = L["A sample description, as the group leader would write it. Long ones wrap onto more lines."],
    };
    self:Open(dungeon.instanceId, nil, false);
    self.groupInfo, self.details, self.appliedRole = groupInfo, details, appliedRole;
end

-- Brings back the last window shown, if there was one this session.
function OxMythicLooterMythicPlusNotificationFrameMixin:ShowLast()
    if (self.Card and self.Card.DungeonName:GetText()) then
        self:Show();
        return true;
    end
    return false;
end

-- Back to where the window first appears.
function OxMythicLooterMythicPlusNotificationFrameMixin:ResetPosition()
    self:SetUserPlaced(false);
    self:ClearAllPoints();
    self:SetPoint("CENTER", UIParent, "CENTER", 0, 150);
end

if (EventRegistry and EventRegistry.RegisterCallback) then
    -- Whether the owner comes first depends on the build; the link is
    -- whichever of the first two arguments it is.
    EventRegistry:RegisterCallback("SetItemRef", function(a, b)
        if (a ~= REMINDER_LINK and b ~= REMINDER_LINK) then return; end
        local frame = OxMythicLooterMythicPlusNotificationFrame;
        if (frame and frame.ShowLast) then frame:ShowLast(); end
    end);
end

