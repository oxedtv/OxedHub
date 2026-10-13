local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

KeystoneLootMythicPlusNotificationCardMixin = CreateFromMixins(KeystoneLootTeleportButtonMixin);

function KeystoneLootMythicPlusNotificationCardMixin:OnEnter()
    KeystoneLootTeleportButtonMixin.OnEnter(self);
    self.HighlightTexture:Show();
end

function KeystoneLootMythicPlusNotificationCardMixin:OnLeave()
    KeystoneLootTeleportButtonMixin.OnLeave(self);
    self.HighlightTexture:Hide();
end
