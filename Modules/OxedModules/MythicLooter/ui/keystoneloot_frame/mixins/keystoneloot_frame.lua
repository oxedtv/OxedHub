local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local DB = KeystoneLoot.DB;
local Favorites = KeystoneLoot.Favorites;
local Character = KeystoneLoot.Character;
local Voidcore = KeystoneLoot.Voidcore;
local RoleCheck = KeystoneLoot.RoleCheck;
local Keystone = KeystoneLoot.Keystone;
local Owned = KeystoneLoot.Owned;
local CopyPopup = KeystoneLoot.CopyPopup;
local L = KeystoneLoot.L;

local WEBSITE_URL = "keystoneloot.io";

local isResponsePaused = false;

KeystoneLootFrameMixin = {};

function KeystoneLootFrameMixin:OnLoad()
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("BONUS_ROLL_RESULT");
    self:RegisterEvent("LFG_ROLE_CHECK_SHOW");
    self:RegisterForDrag("LeftButton");

    CallbackRegistryMixin.OnLoad(self);
    TabSystemOwnerMixin.OnLoad(self);

    self:SetPortraitToAsset("Interface\\Icons\\INV_Relics_Hourglass_02");
    self:SetTitle(string.format(L['%s (%s Season %d)'], AddonName, KeystoneLoot.Config.expansionName, KeystoneLoot.Config.seasonNumber));

    -- No footer line: the tabs end at the window's edge.
    self.FooterText:SetText("");
    self.FooterText:Hide();
    self.FooterButton:Hide();

    table.insert(UISpecialFrames, self:GetName());
end

function KeystoneLootFrameMixin:InitializeTabSystem()
    self:SetTabSystem(self.TabSystem);

    self.DungeonsFrame = CreateFrame("Frame", nil, self, "KeystoneLootDungeonsFrameTemplate");
    self.DungeonsFrame:Init();
    self.dungeonsTabId = self:AddNamedTab(DUNGEONS, self.DungeonsFrame);

    self.RaidsFrame = CreateFrame("Frame", nil, self, "KeystoneLootRaidsFrameTemplate");
    self.RaidsFrame:Init();
    self.raidsTabId = self:AddNamedTab(RAIDS, self.RaidsFrame);

    -- The party's keys (keys_tab.lua), for anyone who would rather not keep
    -- the Party Keystones list on screen.
    if (KeystoneLoot.KeysTab) then
        self.KeysFrame = KeystoneLoot.KeysTab.Create(self, self.DungeonsFrame);
        self.keysTabId = self:AddNamedTab("Keys", self.KeysFrame);
    end

    self:SetTab(self.dungeonsTabId);
end

function KeystoneLootFrameMixin:OnEvent(event, ...)
    if (event == "ACTIVE_TALENT_GROUP_CHANGED") then
        self:SyncSpecFilter();
        return;
    elseif (event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" or event == "ITEM_DATA_LOAD_RESULT") then
        self:RefreshOwnedIcons();
        return;
    elseif (event == "BONUS_ROLL_RESULT") then
        local rewardType, rewardLink = ...;
        if (rewardType ~= "item" or not rewardLink) then
            return;
        end

        local itemId = tonumber(string.match(rewardLink, "item:(%d+)"));
        if (not itemId) then
            return;
        end

        Voidcore:OnBonusRoll(itemId);
        return;
    elseif (event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED") then
        Owned:ScanBank();
        self:RefreshOwnedIcons();
        return;
    elseif (event == "LFG_ROLE_CHECK_SHOW") then
        RoleCheck:OnRoleCheckShow();
        return;
    elseif (event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" or event == "CHAT_MSG_GUILD") then
        if (not DB:Get("settings.keyCommand." .. event) or isResponsePaused) then
            return;
        end

        local msg = ...;
        if (not issecretvalue(msg) and string.match(string.lower(msg), "^!key")) then
            local link = Keystone:GetKeystoneItemLink();
            if (not link) then
                return;
            end

            local channel = event == "CHAT_MSG_GUILD" and "GUILD" or "PARTY";
            C_ChatInfo.SendChatMessage("[KeystoneLoot]: " .. link, channel);

            isResponsePaused = true;
            C_Timer.After(2, function()
                isResponsePaused = false;
            end);
        end
        return;
    end

    self:UnregisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
    self:RegisterEvent("CHAT_MSG_PARTY");
    self:RegisterEvent("CHAT_MSG_PARTY_LEADER");
    self:RegisterEvent("CHAT_MSG_GUILD");
    self:RegisterEvent("BANKFRAME_OPENED");
    self:RegisterEvent("BANKFRAME_CLOSED");

    DB:Init();
    Favorites:Init();

    self:InitSpecFilter();
    self:InitScale();
    self:InitOwnedCheck();

    self:InitializeTabSystem();

    self.ClassDropdown:Init();
    self.SlotDropdown:Init();
    self.ItemLevelDropdown:Init();
    self.CharacterDropdown:Init();
    self.SettingsDropdown:Init();
    self.CatalystFrame:Init();
    self.CustomItemFrame:Init();
    KeystoneLootMinimapButton:Init();

    KeystoneLoot.APIInternal.SetReady();

    if (DB:Get("voidcoreChecked") or UnitLevel("player") < 90) then
        return;
    end

    C_Timer.After(3, function()
        Voidcore:CheckAll();
    end);
end

function KeystoneLootFrameMixin:SyncSpecFilter()
    local currentClassId = Character:GetCurrentClassId();

    if (DB:Get("filters.classId") == currentClassId) then
        DB:Set("filters.classId", currentClassId);
        DB:Set("filters.specId", Character:GetCurrentSpecId());
    end
end

function KeystoneLootFrameMixin:InitOwnedCheck()
    DB:AddObserver("settings.ownedCheck", function()
        self:RefreshOwnedIcons();
    end);
end

function KeystoneLootFrameMixin:InitScale()
    self:SetScale(DB:Get("settings.windowScale") / 100);

    DB:AddObserver("settings.windowScale", function(percent)
        self:SetScale(percent / 100);
    end);
end

function KeystoneLootFrameMixin:InitSpecFilter()
    local currentClassId = Character:GetCurrentClassId();
    local currentSpecId = Character:GetCurrentSpecId();

    if (DB:Get("filters.classId") ~= currentClassId) then
        DB:Set("filters.classId", currentClassId);
        DB:Set("filters.specId", currentSpecId);
    elseif (DB:Get("filters.specId") ~= 0) then
        DB:Set("filters.specId", currentSpecId);
    end
end

function KeystoneLootFrameMixin:SetTab(tabId)
    TabSystemOwnerMixin.SetTab(self, tabId);

    local tabName = self:GetTabName(tabId);
    -- The Keys tab has no loot: the loot views and the filters keep the
    -- dungeons or raids they were on (they only know those two).
    if (tabName ~= "keys") then
        DB:Set("ui.selectedTab", tabName);
    end

    -- The loot filters mean nothing on the Keys tab, and they sat under its
    -- Sync and Announce buttons.
    local onKeys = (tabName == "keys");
    for _, dropdown in ipairs({ self.SlotDropdown, self.ClassDropdown, self.ItemLevelDropdown, self.CharacterDropdown }) do
        if (dropdown) then dropdown:SetShown(not onKeys); end
    end

    self:RefreshSize(tabId);
end

function KeystoneLootFrameMixin:RefreshOwnedIcons()
    Owned:RefreshTracks();

    for _, Frame in ipairs({ self.DungeonsFrame, self.RaidsFrame, self.CatalystFrame, self.CustomItemFrame }) do
        Frame:RefreshOwnedIcons();
    end
end

function KeystoneLootFrameMixin:OnShow()
    PlaySound(SOUNDKIT.IG_QUEST_LIST_OPEN);

    self:RegisterEvent("BAG_UPDATE_DELAYED");
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
    self:RegisterEvent("ITEM_DATA_LOAD_RESULT");

    self:RefreshOwnedIcons();
end

function KeystoneLootFrameMixin:OnHide()
    PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE);

    self:UnregisterEvent("BAG_UPDATE_DELAYED");
    self:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED");
    self:UnregisterEvent("ITEM_DATA_LOAD_RESULT");
end

function KeystoneLootFrameMixin:OnDragStart()
    self:StartMoving();
    self:SetUserPlaced(true);
end

function KeystoneLootFrameMixin:OnDragStop()
    self:StopMovingOrSizing();
end

function KeystoneLootFrameMixin:RefreshSize(tabId)
    local Frame = self:GetElementsForTab(tabId)[1];
    -- The Keys tab takes the window's dungeons size, so switching to it does
    -- not make the window jump.
    if (Frame == self.KeysFrame and self.DungeonsFrame) then
        Frame:SetSize(self.DungeonsFrame:GetSize());
    end
    self:SetSize(Frame:GetSize());
end

function KeystoneLootFrameMixin:GetTabName(tabId)
    if (tabId == self.dungeonsTabId) then
        return "dungeons";
    elseif (tabId == self.raidsTabId) then
        return "raids";
    elseif (self.keysTabId and tabId == self.keysTabId) then
        return "keys";
    end

    return "dungeons"; -- Fallback
end
