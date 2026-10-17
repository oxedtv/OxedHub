local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

OxMythicLooterMythicPlusNotificationCardMixin = CreateFromMixins(OxMythicLooterTeleportButtonMixin);

function OxMythicLooterMythicPlusNotificationCardMixin:OnEnter()
    OxMythicLooterTeleportButtonMixin.OnEnter(self);
    self.HighlightTexture:Show();
end

function OxMythicLooterMythicPlusNotificationCardMixin:OnLeave()
    OxMythicLooterTeleportButtonMixin.OnLeave(self);
    self.HighlightTexture:Hide();
end
