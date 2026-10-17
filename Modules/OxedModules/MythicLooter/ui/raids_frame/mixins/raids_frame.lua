local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local DB = KeystoneLoot.DB;
local Query = KeystoneLoot.Query;
local PickerView = KeystoneLoot.PickerView;

-- One boss at a time, like the Dungeons tab: every raid's bosses on the left
-- under the raid's name, the chosen boss on the right with its portrait and
-- every item it drops (see picker_view.lua).

OxMythicLooterRaidsFrameMixin = {};

local function BossPortrait(bossId)
    local ok, _, _, _, displayID = pcall(EJ_GetCreatureInfo, 1, bossId);
    return ok and displayID or nil;
end

local function RaidArt(journalInstanceId)
    local ok, _, _, bgImage, _, loreImage = pcall(EJ_GetInstanceInfo, journalInstanceId);
    if (not ok) then return nil; end
    return loreImage or bgImage;
end

local function SelectedBoss(raids)
    local selected = DB:Get("ui.selectedRaidBoss");
    local first;
    for _, raid in ipairs(raids) do
        for _, boss in ipairs(raid.bossList) do
            first = first or boss.bossId;
            if (boss.bossId == selected) then
                return selected;
            end
        end
    end
    return first;
end

function OxMythicLooterRaidsFrameMixin:OnLoad()
    PickerView.Setup(self);
end

function OxMythicLooterRaidsFrameMixin:RefreshOwnedIcons()
    PickerView.EachItemButton(self, function(button) button:UpdateOwnedIcon(); end);
end

function OxMythicLooterRaidsFrameMixin:RefreshSize()
    local Parent = self:GetParent();
    if (Parent.raidsTabId) then
        Parent:RefreshSize(Parent.raidsTabId);
    end
end

-- Kept for the raid dropdown: choosing a raid picks its first boss.
function OxMythicLooterRaidsFrameMixin:SetRaid(raid)
    local boss = raid and raid.bossList and raid.bossList[1];
    if (boss) then
        DB:Set("ui.selectedRaidBoss", boss.bossId);
    end
end

function OxMythicLooterRaidsFrameMixin:Refresh()
    local raids = Query:GetRaids();
    local selectedId = SelectedBoss(raids);
    local showRaidNames = #raids > 1;

    local rows, chosen, chosenRaid, items = {}, nil, nil, {};
    for _, raid in ipairs(raids) do
        local raidName = EJ_GetInstanceInfo(raid.journalInstanceId);
        if (showRaidNames) then
            rows[#rows + 1] = { header = true, name = raidName };
        end
        for _, boss in ipairs(raid.bossList) do
            local loot = Query:GetRaidItems(boss.bossId);
            rows[#rows + 1] = {
                key = boss.bossId,
                name = EJ_GetEncounterInfo(boss.bossId),
                portrait = BossPortrait(boss.bossId) or 134400,
                count = #loot,
            };
            if (boss.bossId == selectedId) then
                chosen, chosenRaid, items = boss, raid, loot;
            end
        end
    end

    local subtitle = (#items == 1 and "1 item" or (#items .. " items")) .. " for your filters";
    if (chosenRaid) then
        subtitle = (EJ_GetInstanceInfo(chosenRaid.journalInstanceId) or "") .. "  ·  " .. subtitle;
    end

    PickerView.Render(self, {
        width = DB:Get("settings.wideMode") and 760 or 600,
        rows = rows,
        selected = selectedId,
        onSelect = function(key) DB:Set("ui.selectedRaidBoss", key); end,
        banner = chosen and function(banner)
            banner:Init(1, chosen, { { itemId = 0 } }, true);
            -- Entry frames are pooled: the art of whatever used it last
            -- would stay without this.
            banner.DungeonBG:SetTexture(RaidArt(chosenRaid.journalInstanceId));
            banner.TeleportButton.Error:Hide();
        end or nil,
        subtitle = subtitle,
        items = items,
    });

    self:RefreshSize();
end

function OxMythicLooterRaidsFrameMixin:Init()
    local function OnChanged()
        if (not self:IsShown()) then
            return;
        end

        self:Refresh();
    end

    DB:AddObserver("filters.specId", OnChanged);
    DB:AddObserver("filters.slotId", OnChanged);
    DB:AddObserver("filters.weaponTypes", OnChanged);
    DB:AddObserver("filters.raid.rank", OnChanged);
    DB:AddObserver("ui.selectedCharacterKey", OnChanged);
    DB:AddObserver("ui.selectedTab", OnChanged);
    DB:AddObserver("ui.selectedRaidBoss", OnChanged);
    DB:AddObserver("settings.highlighting.*", OnChanged);
    DB:AddObserver("settings.hideOtherItems", OnChanged);
    DB:AddObserver("settings.wideMode", OnChanged);
    DB:AddObserver("settings.multiSlotFilter", OnChanged);
    DB:AddObserver("settings.slotName", OnChanged);
    DB:AddObserver("voidcore", function()
        PickerView.EachItemButton(self, function(button) button:UpdateVoidcoreIcon(); end);
    end);

    -- The list replaces the raid dropdown.
    self.DropdownButton:Hide();
    self:Refresh();
end
