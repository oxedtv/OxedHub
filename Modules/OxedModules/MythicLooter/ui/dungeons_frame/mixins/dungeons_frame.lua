local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local DB = KeystoneLoot.DB;
local Query = KeystoneLoot.Query;
local PickerView = KeystoneLoot.PickerView;

-- One dungeon at a time: the season's dungeons on the left, the chosen one
-- on the right with every item it drops (see picker_view.lua). No teleport
-- here: the banner is the name and the count only.

KeystoneLootDungeonsFrameMixin = {};

local function GetSelectedId(dungeons)
    local selected = DB:Get("ui.selectedDungeon");
    for _, dungeon in ipairs(dungeons) do
        if (dungeon.challengeModeId == selected) then
            return selected;
        end
    end
    return dungeons[1] and dungeons[1].challengeModeId;
end

function KeystoneLootDungeonsFrameMixin:OnLoad()
    -- The old list's backdrop and border are not used by this layout.
    self.Inset:Hide();
    self.BorderFrame:Hide();
    PickerView.Setup(self);
end

function KeystoneLootDungeonsFrameMixin:Init()
    local function OnChanged()
        if (not self:IsShown()) then
            return;
        end

        self:Refresh();
    end

    DB:AddObserver("filters.specId", OnChanged);
    DB:AddObserver("filters.slotId", OnChanged);
    DB:AddObserver("filters.weaponTypes", OnChanged);
    DB:AddObserver("ui.selectedCharacterKey", OnChanged);
    DB:AddObserver("ui.selectedTab", OnChanged);
    DB:AddObserver("ui.selectedDungeon", OnChanged);
    DB:AddObserver("settings.highlighting.*", OnChanged);
    DB:AddObserver("settings.hideOtherItems", OnChanged);
    DB:AddObserver("settings.wideMode", OnChanged);
    DB:AddObserver("settings.multiSlotFilter", OnChanged);
    DB:AddObserver("settings.slotName", OnChanged);
    DB:AddObserver("voidcore", function()
        PickerView.EachItemButton(self, function(button) button:UpdateVoidcoreIcon(); end);
    end);

    self:Refresh();
end

function KeystoneLootDungeonsFrameMixin:RefreshOwnedIcons()
    PickerView.EachItemButton(self, function(button) button:UpdateOwnedIcon(); end);
end

function KeystoneLootDungeonsFrameMixin:RefreshSize()
    local Parent = self:GetParent();
    if (Parent.dungeonsTabId) then
        Parent:RefreshSize(Parent.dungeonsTabId);
    end
end

function KeystoneLootDungeonsFrameMixin:OnShow()
    -- Update cooldowns for teleport buttons in case they were on cooldown when the frame was hidden.
    PickerView.UpdateTeleportCooldown(self);
end

function KeystoneLootDungeonsFrameMixin:Refresh()
    local dungeons = Query:GetDungeons();
    local selectedId = GetSelectedId(dungeons);

    local rows, chosen, items = {}, nil, {};
    for _, dungeon in ipairs(dungeons) do
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(dungeon.challengeModeId);
        local loot = Query:GetDungeonItems(dungeon.challengeModeId);
        rows[#rows + 1] = {
            key = dungeon.challengeModeId, name = name, icon = texture, count = #loot,
        };
        if (dungeon.challengeModeId == selectedId) then
            chosen, items = dungeon, loot;
        end
    end

    PickerView.Render(self, {
        width = DB:Get("settings.wideMode") and 760 or 600,
        rows = rows,
        selected = selectedId,
        onSelect = function(key) DB:Set("ui.selectedDungeon", key); end,
        banner = chosen and function(banner)
            -- A one-item stand-in: an empty table draws the banner greyed
            -- out as "no loot", and Init pads whatever it is given.
            banner:Init(1, chosen, { { itemId = 0 } }, true);
        end or nil,
        subtitle = (#items == 1 and "1 item" or (#items .. " items")) .. " for your filters",
        noIcon = true,
        items = items,
    });

    self:RefreshSize();
end
