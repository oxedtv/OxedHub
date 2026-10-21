local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey
local L = OxedHub.L

OxedHub.Triggers:RegisterEventType("PREY_HUNT", {
    name = L["EVT_PREY_HUNT"] or "Prey Hunt",
    CheckCondition = function(trigger, eventData)
        return false -- Handled internally by PreyEngine
    end,
    -- ⚠ Prey Hunt moved to Modules (Modules/OxedModules/PreyHunt). The type
    -- stays registered so an old trigger still opens, and says where to go;
    -- the tracker no longer reads anything from triggers.
    CreateConditionUI = function(frame, trigger, yOffset)
        yOffset = yOffset or 0
        local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        note:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        note:SetWidth(560)
        note:SetJustifyH("LEFT")
        note:SetText("|cffffd100Prey Hunt is now a module.|r Its bar, widget, gossip marks and sounds are set in "
            .. "Modules > Prey Hunt. This trigger no longer does anything and can be deleted.")
        local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        open:SetSize(200, 24)
        open:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
        open:SetText("Open Prey Hunt options")
        if OxedHub.UI and OxedHub.UI.ApplyRedButtonStyle then OxedHub.UI:ApplyRedButtonStyle(open) end
        open:SetScript("OnClick", function()
            local API = OxedHub.ModuleAPI
            local mod = API and API.GetModule and API:GetModule("preyhunt")
            if mod and mod.OnOptionsShow then mod.OnOptionsShow(mod) end
        end)
        return yOffset - 80
    end,
})
