-- Loader.lua
-- Register only the events we actually need for working triggers.
-- This uses the OnUpdate/FirstFrame pattern to bypass ADDON_ACTION_FORBIDDEN.

local addonName, OxedHub = ...

-- Initialize Localization Table with fallback
OxedHub.L = OxedHub.L or {}
setmetatable(OxedHub.L, {
    __index = function(t, k)
        local v = tostring(k)
        rawset(t, k, v)
        return v
    end
})

-- Registry for loaded locales
OxedHub.Locales = {
    enUS = {},
    esES = {},
    arAR = {},
}

local eventFrame = CreateFrame("Frame")
local registered = false

local function DoRegister()
    if registered then return end
    registered = true

    -- Safe lifecycle events
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_DEAD")
    eventFrame:RegisterEvent("PLAYER_ALIVE")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("CONFIRM_SUMMON")

    -- Combat events
    -- Restrict UNIT_AURA to player only; global UNIT_AURA traffic is extremely noisy.
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    -- Restrict spellcast traffic to units the addon actually inspects.
    -- This still covers player/pet casts plus common interrupt targets.
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet", "target", "focus", "mouseover")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "pet", "target", "focus", "mouseover")

    -- Other trigger events
    eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("BOSS_KILL")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
    eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
    eventFrame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    eventFrame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    -- Pet tracking only needs player/pet-specific unit events, not global traffic.
    eventFrame:RegisterUnitEvent("UNIT_PET", "player")
    eventFrame:RegisterUnitEvent("UNIT_FLAGS", "pet")
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "pet")
end

-- Wait exactly one frame to ensure we are out of the restricted load-time context
eventFrame:SetScript("OnUpdate", function(self)
    self:SetScript("OnUpdate", nil)
    DoRegister()
end)

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if OxedHub.Core and OxedHub.Core.OnEvent then
        OxedHub.Core:OnEvent(event, ...)
    end
end)

OxedHub._loaderFrame = eventFrame
