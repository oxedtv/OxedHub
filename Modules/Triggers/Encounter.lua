local addonName, OxedHub = ...

local EncounterHandler = {
    CheckCondition = function(trigger, eventData)
        local conditions = trigger.conditions or {}
        if trigger.event == "ENCOUNTER_END" then
            if conditions.onWipe and not conditions.onWin then
                if not eventData.wipe then return false end
            elseif conditions.onWin and not conditions.onWipe then
                if eventData.wipe then return false end
            end
        end
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local conditions = trigger.conditions or {}
        
        if trigger.event == "ENCOUNTER_END" then
            local wipeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            wipeCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
            wipeCheck:SetSize(20, 20)
            wipeCheck:SetChecked(conditions.onWipe or false)
            wipeCheck.text:SetText("Trigger on Wipe")
            
            local winCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
            winCheck:SetPoint("LEFT", wipeCheck.text, "RIGHT", 10, 0)
            winCheck:SetSize(20, 20)
            winCheck:SetChecked(conditions.onWin or false)
            winCheck.text:SetText("Trigger on Win")
            
            wipeCheck:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Fire this trigger only when the group wipes/fails.")
                GameTooltip:Show()
            end)
            wipeCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            winCheck:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText("Fire this trigger only when the boss is defeated.")
                GameTooltip:Show()
            end)
            winCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            wipeCheck:SetScript("OnClick", function(self)
                conditions.onWipe = self:GetChecked()
                if OxedHub.Triggers.ShowAutoSaved then
                    OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
                end
            end)
            
            winCheck:SetScript("OnClick", function(self)
                conditions.onWin = self:GetChecked()
                if OxedHub.Triggers.ShowAutoSaved then
                    OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
                end
            end)
            yOffset = yOffset - 25
        end
        return yOffset
    end
}

OxedHub.Triggers:RegisterEventType("ENCOUNTER_START", EncounterHandler)
OxedHub.Triggers:RegisterEventType("ENCOUNTER_END", EncounterHandler)
OxedHub.Triggers:RegisterEventType("BOSS_KILL", EncounterHandler)
