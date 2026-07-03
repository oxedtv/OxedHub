local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("EAT_BUFF", {
    name = "Food/Drink Buff",
    CheckCondition = function(trigger, eventData)
        local conditions = trigger.conditions or {}
        if eventData.eatState == "start" and not conditions.onStart then
            return false
        end
        if eventData.eatState == "stop" and not conditions.onStop then
            return false
        end
        if eventData.eatState == "buff" and conditions.onBuff == false then
            return false
        end
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}
        
        local startCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        startCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        startCheck:SetSize(20, 20)
        startCheck:SetChecked(conditions.onStart or false)
        startCheck.text:SetText("Trigger on Start Eating")
        
        local stopCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        stopCheck:SetPoint("LEFT", startCheck.text, "RIGHT", 10, 0)
        stopCheck:SetSize(20, 20)
        stopCheck:SetChecked(conditions.onStop or false)
        stopCheck.text:SetText("Trigger on Stop Eating")
        
        local buffCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        buffCheck:SetPoint("TOPLEFT", startCheck, "BOTTOMLEFT", 0, -5)
        buffCheck:SetSize(20, 20)
        buffCheck:SetChecked(conditions.onBuff ~= false) -- Default true for backward compat
        buffCheck.text:SetText("Trigger on Buff Gained (Well Fed)")
        
        startCheck:SetScript("OnClick", function(self)
            conditions.onStart = self:GetChecked()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        stopCheck:SetScript("OnClick", function(self)
            conditions.onStop = self:GetChecked()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        buffCheck:SetScript("OnClick", function(self)
            conditions.onBuff = self:GetChecked()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        yOffset = yOffset - 50
        
        return yOffset
    end
})
