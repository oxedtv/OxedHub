local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local L = KeystoneLoot.L;

OxMythicLooterCustomItemIconMixin = {};

function OxMythicLooterCustomItemIconMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetText(L["Custom Items"], HIGHLIGHT_FONT_COLOR:GetRGB());
    GameTooltip:AddLine(L["Import items from external sources like keystoneloot.io"], nil, nil, nil, true);
    GameTooltip:Show();
end

function OxMythicLooterCustomItemIconMixin:OnLeave()
    GameTooltip:Hide();
end
