local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────
-- PvP kill triggers.
--
--   PVP_KILL       — every honorable kill you land
--   PVP_MULTIKILL  — N kills inside a short window (Double / Triple / Multi)
--   PVP_SPREE      — N kills without dying (Spree / Dominating / Unstoppable /
--                    Godlike)
--
-- Kill detection lives in Core:OnPartyKill (PARTY_KILL). eventData carries:
--   killStreak  — kills since your last death
--   multiKill   — kills inside the multi-kill window
--   tier        — the milestone that was just reached (2/3/4, or 5/10/15/20)
-- ─────────────────────────────────────────────────────────────────────────

local MULTIKILL_TIERS = {
    { value = 2, label = "Double Kill (2)" },
    { value = 3, label = "Triple Kill (3)" },
    { value = 4, label = "Multi Kill (4+)" },
}

local SPREE_TIERS = {
    { value = 5,  label = "Killing Spree (5)" },
    { value = 10, label = "Dominating (10)" },
    { value = 15, label = "Unstoppable (15)" },
    { value = 20, label = "Godlike (20+)" },
}

-- Shared condition UI: a dropdown picking which milestone fires the trigger.
local function CreateTierUI(frame, trigger, yOffset, tiers, labelText, defaultValue)
    trigger.conditions = trigger.conditions or {}
    local conditions = trigger.conditions

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
    label:SetText(labelText)
    label:SetTextColor(1, 0.82, 0, 1)

    local function CurrentValue()
        return tonumber(conditions.pvpTier) or defaultValue
    end

    local function LabelFor(value)
        for _, tier in ipairs(tiers) do
            if tier.value == value then return tier.label end
        end
        return tostring(value)
    end

    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", 10, 0)
    dropdown:SetSize(190, 24)
    dropdown:OverrideText(LabelFor(CurrentValue()))

    dropdown:SetupMenu(function(_, rootDescription)
        for _, tier in ipairs(tiers) do
            rootDescription:CreateRadio(
                tier.label,
                function() return CurrentValue() == tier.value end,
                function()
                    conditions.pvpTier = tier.value
                    dropdown:OverrideText(tier.label)
                    if Triggers.ShowAutoSaved then
                        Triggers.ShowAutoSaved(frame:GetParent())
                    end
                end,
                tier.value
            )
        end
    end)

    return yOffset - 34
end

-- ── Every honorable kill ─────────────────────────────────────────────────
Triggers:RegisterEventType("PVP_KILL", {
    name = L["EVT_PVP_KILL"] or "PvP Kill",
    CheckCondition = function()
        return true
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset - 4)
        info:SetText(L["PVP_KILL_DESC"]
            or "Fires every time you land a killing blow on an enemy player.")
        return yOffset - 24
    end,
})

-- ── Several kills in quick succession ────────────────────────────────────
Triggers:RegisterEventType("PVP_MULTIKILL", {
    name = L["EVT_PVP_MULTIKILL"] or "PvP Multi-Kill",
    CheckCondition = function(trigger, eventData)
        local wanted = tonumber((trigger.conditions or {}).pvpTier) or 2
        return (eventData and eventData.tier) == wanted
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        yOffset = CreateTierUI(frame, trigger, yOffset, MULTIKILL_TIERS,
            L["PVP_MULTIKILL_LABEL"] or "Fire on:", 2)

        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        info:SetText(L["PVP_MULTIKILL_DESC"]
            or "*Kills counted within 10 seconds of each other.")
        return yOffset - 22
    end,
})

-- ── Kills without dying ──────────────────────────────────────────────────
Triggers:RegisterEventType("PVP_SPREE", {
    name = L["EVT_PVP_SPREE"] or "PvP Killing Spree",
    CheckCondition = function(trigger, eventData)
        local wanted = tonumber((trigger.conditions or {}).pvpTier) or 5
        return (eventData and eventData.tier) == wanted
    end,
    CreateConditionUI = function(frame, trigger, yOffset)
        yOffset = CreateTierUI(frame, trigger, yOffset, SPREE_TIERS,
            L["PVP_SPREE_LABEL"] or "Fire on:", 5)

        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, yOffset)
        info:SetText(L["PVP_SPREE_DESC"]
            or "*Streak resets when you die or after 60 seconds without a kill.")
        return yOffset - 22
    end,
})
