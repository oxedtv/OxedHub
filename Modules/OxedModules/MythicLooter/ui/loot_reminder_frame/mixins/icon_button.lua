local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local Upgrade = KeystoneLoot.Upgrade;
local L = KeystoneLoot.L;

OxMythicLooterReminderIconMixin = {};

function OxMythicLooterReminderIconMixin:Init(itemId, icon, isShared, players)
    self.itemId = itemId;
    self.players = players;

    self.Icon:SetTexture(icon);
    self.Icon:SetDesaturated(isShared);
    self:SetAlpha(isShared and 0.5 or 1);
    self:Show();
end

function OxMythicLooterReminderIconMixin:OnEnter()
    if (self:GetCenter() > GetScreenWidth() / 2) then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT");
    else
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT");
    end

    GameTooltip.OxMythicLooterOwned = true;
    GameTooltip:SetHyperlink(Upgrade:BuildItemLink(self.itemId));

    if (self.players) then
        GameTooltip:AddLine(" ");
        GameTooltip:AddLine(string.format(L["Wanted by %s"], table.concat(self.players, ", ")), nil, nil, nil, true);
    end

    GameTooltip:Show();

    self.UpdateTooltip = self.OnEnter;
end

function OxMythicLooterReminderIconMixin:OnLeave()
    GameTooltip.OxMythicLooterOwned = nil;
    GameTooltip:Hide();

    self.UpdateTooltip = nil;
end
