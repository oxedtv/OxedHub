OxMythicLooterReminderEfficiencyIconMixin = {};

function OxMythicLooterReminderEfficiencyIconMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_TOP");
    GameTooltip:SetText(self.tooltipText, nil, nil, nil, 1, true);
    GameTooltip:Show();
end

function OxMythicLooterReminderEfficiencyIconMixin:OnLeave()
    GameTooltip:Hide();
end
