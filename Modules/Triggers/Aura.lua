local addonName, OxedHub = ...

OxedHub.Triggers:RegisterEventType("UNIT_AURA", {
    name = "Aura Gained/Lost",
    CheckCondition = function(trigger, eventData)
        local conditions = trigger.conditions or {}

        -- Aura name condition
        if conditions.auraName and conditions.auraName ~= "" then
            if not eventData.spellName or not eventData.spellName:lower():find(conditions.auraName:lower(), 1, true) then
                return false
            end
        end
        
        -- Aura type condition
        if conditions.auraType and eventData.auraType ~= conditions.auraType then
            return false
        end
        
        -- Aura gained/lost condition
        if eventData.isLost ~= nil then
            if not conditions.onBoth then
                local triggerOnLost = conditions.onLost or false
                if eventData.isLost ~= triggerOnLost then
                    return false
                end
            end
        end
        
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}
        
        if OxedHub.Triggers.CreateAuraSpellSearchUI then
            yOffset = OxedHub.Triggers:CreateAuraSpellSearchUI(frame, trigger, yOffset)
        end
        
        local lostCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        lostCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        lostCheck:SetSize(20, 20)
        lostCheck:SetChecked(conditions.onLost or false)
        lostCheck.text:SetText("Trigger on Aura Lost")
        
        local bothCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        bothCheck:SetPoint("LEFT", lostCheck.text, "RIGHT", 10, 0)
        bothCheck:SetSize(20, 20)
        bothCheck:SetChecked(conditions.onBoth or false)
        bothCheck.text:SetText("Trigger on Both")
        
        lostCheck:SetScript("OnClick", function(self)
            conditions.onLost = self:GetChecked()
            if self:GetChecked() then
                bothCheck:SetChecked(false)
                conditions.onBoth = false
            end
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        
        bothCheck:SetScript("OnClick", function(self)
            conditions.onBoth = self:GetChecked()
            if self:GetChecked() then
                lostCheck:SetChecked(false)
                conditions.onLost = false
            end
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        yOffset = yOffset - 25
        
        return yOffset
    end
})
