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
        
        local loopCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        loopCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        loopCheck:SetSize(20, 20)
        loopCheck:SetChecked(conditions.loopSound or false)
        loopCheck.text:SetText("Loop sound until lost")
        
        local loopIntervalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        loopIntervalLabel:SetPoint("LEFT", loopCheck.text, "RIGHT", 10, 0)
        loopIntervalLabel:SetText("Interval (s):")
        
        local loopIntervalEdit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        loopIntervalEdit:SetPoint("LEFT", loopIntervalLabel, "RIGHT", 5, 0)
        loopIntervalEdit:SetSize(30, 20)
        loopIntervalEdit:SetAutoFocus(false)
        loopIntervalEdit:SetNumeric(true)
        loopIntervalEdit:SetText(tostring(conditions.loopInterval or 2))
        
        loopCheck:SetScript("OnClick", function(self)
            conditions.loopSound = self:GetChecked()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        
        loopIntervalEdit:SetScript("OnTextChanged", function(self)
            local val = tonumber(self:GetText())
            if val and val > 0 then
                conditions.loopInterval = val
                if OxedHub.Triggers.ShowAutoSaved then
                    OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
                end
            end
        end)
        
        yOffset = yOffset - 25

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
