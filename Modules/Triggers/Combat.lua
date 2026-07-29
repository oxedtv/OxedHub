local addonName, OxedHub = ...
local L = OxedHub.L

-- ─────────────────────────────────────────────────────────────────────────
-- COMBAT_STATE trigger: fires when the player enters or leaves combat.
--
-- conditions.onEnter / conditions.onExit   -- which transitions fire at all
-- conditions.separateEffects               -- when true, enter and exit each use
--                                             their own sound + animation:
--                                               actions.enterSound / enterAnim
--                                               actions.exitSound  / exitAnim
--                                             otherwise both share the trigger's
--                                             normal Sound / Animation.
--
-- eventData.combatState is "enter" or "exit" (set by Core:OnCombatStateChanged).
--
-- The Enter/Exit pickers themselves are built in ActionsTab.lua so they appear
-- in the Actions section with the other effect pickers.
-- ─────────────────────────────────────────────────────────────────────────

OxedHub.Triggers:RegisterEventType("COMBAT_STATE", {
    name = L["EVT_COMBAT_STATE"] or "Enter/Exit Combat",

    CheckCondition = function(trigger, eventData)
        local conditions = trigger.conditions or {}
        local state = eventData and eventData.combatState

        -- Default to firing on both when the trigger has never been configured,
        -- so a freshly created trigger does something useful straight away.
        local onEnter = conditions.onEnter
        local onExit = conditions.onExit
        if onEnter == nil and onExit == nil then
            return true
        end

        if state == "enter" then return onEnter ~= false end
        if state == "exit" then return onExit ~= false end
        return true
    end,

    CreateConditionUI = function(frame, trigger, yOffset)
        trigger.conditions = trigger.conditions or {}
        trigger.actions = trigger.actions or {}
        local conditions = trigger.conditions

        local function AutoSaved()
            if OxedHub.Triggers.ShowAutoSaved then
                OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
            end
        end

        -- ── Which transitions fire ────────────────────────────────────────
        local enterCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        enterCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        enterCheck:SetSize(20, 20)
        enterCheck:SetChecked(conditions.onEnter ~= false)
        enterCheck.text:SetText(L["COMBAT_ON_ENTER"] or "Play on Enter Combat")

        local exitCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        exitCheck:SetPoint("LEFT", enterCheck.text, "RIGHT", 10, 0)
        exitCheck:SetSize(20, 20)
        exitCheck:SetChecked(conditions.onExit ~= false)
        exitCheck.text:SetText(L["COMBAT_ON_EXIT"] or "Play on Exit Combat")

        yOffset = yOffset - 26

        -- ── Separate effects toggle ───────────────────────────────────────
        local separateCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        separateCheck:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        separateCheck:SetSize(20, 20)
        separateCheck:SetChecked(conditions.separateEffects or false)
        separateCheck.text:SetText(L["COMBAT_SEPARATE_EFFECTS"]
            or "Different sound & animation for Enter / Exit")

        -- Full row height for the checkbox itself, plus a little breathing room
        -- so the box doesn't clip the bottom of the text.
        yOffset = yOffset - 36

        -- The Enter/Exit sound + animation pickers themselves live in the
        -- Actions section (ActionsTab.lua) so they sit with the other effect
        -- pickers; this checkbox just toggles their visibility there.
        local function RefreshActionsSection()
            if trigger.id and OxedHub.Triggers.RefreshTriggerCard then
                OxedHub.Triggers:RefreshTriggerCard(trigger.id)
            end
        end

        -- ── Handlers ──────────────────────────────────────────────────────
        enterCheck:SetScript("OnClick", function(self)
            conditions.onEnter = self:GetChecked()
            AutoSaved()
        end)
        exitCheck:SetScript("OnClick", function(self)
            conditions.onExit = self:GetChecked()
            AutoSaved()
        end)
        separateCheck:SetScript("OnClick", function(self)
            conditions.separateEffects = self:GetChecked()
            RefreshActionsSection()
            AutoSaved()
        end)

        return yOffset
    end
})
