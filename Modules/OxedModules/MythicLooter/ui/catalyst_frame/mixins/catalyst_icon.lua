local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local L = KeystoneLoot.L;

OxMythicLooterCatalystIconMixin = {};

function OxMythicLooterCatalystIconMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["The Catalyst"], HIGHLIGHT_FONT_COLOR:GetRGB());
    GameTooltip:Show();
end

function OxMythicLooterCatalystIconMixin:OnLeave()
    GameTooltip:Hide();
end
