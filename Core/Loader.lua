-- Loader.lua
-- Register only the events we actually need for working triggers.
-- This uses the OnUpdate/FirstFrame pattern to bypass ADDON_ACTION_FORBIDDEN.

local addonName, OxedHub = ...

-- Every line OxedHub prints to chat starts with "OxedHub:". Files take it as
-- `local print = OxedHub.Print or print`. A line that already names OxedHub
-- (after colour codes) is left as it is; a secret first value gets the tag
-- as a separate value, since a secret cannot be inspected.
local rawPrint = print
local CHAT_TAG = "|cff00ff00OxedHub:|r"
function OxedHub.Print(...)
    local first = ...
    if type(first) == "string" and not (issecretvalue and issecretvalue(first)) then
        local plain = first:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        plain = plain:sub(1, 40):lower():gsub("[%s%[%]]", "")
        if plain:find("oxedhub", 1, true) then
            return rawPrint(...)
        end
    end
    return rawPrint(CHAT_TAG, ...)
end

-- Initialize Localization Table with fallback
OxedHub.L = OxedHub.L or {}
setmetatable(OxedHub.L, {
    __index = function(t, k)
        -- Modules draw at PLAYER_LOGIN, a frame before Bootstrap applies the
        -- language. Asked that early, apply it now from the saved settings
        -- (they exist from ADDON_LOADED on); Bootstrap applies it again.
        if not OxedHub.languageApplied and OxedHubDB and OxedHub.ApplyLanguage then
            local profile = OxedHubDB.profile
            OxedHub:ApplyLanguage(profile and profile.settings and profile.settings.language)
            local found = rawget(t, k)
            if found ~= nil then return found end
        end
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
    ruRU = {},
}

-- Much of the text is looked up by its English: L["Show on screen"]. A
-- language file that has no line for it leaves the English, so a missing
-- translation can never show a raw key.
--
-- Tables built while a file loads cannot do that, because L is only filled at
-- login, after every file has run. Such a file registers its table here, and
-- ApplyLanguage translates the named fields in place, keeping the English in
-- "_en_<field>" so switching language again starts from the original. A field
-- may be a number, for rows like { "HeadSlot", "Head" }. Named with no fields,
-- the table itself maps keys to text and its values are translated.
OxedHub.LocalizedTables = {}

function OxedHub:RegisterLocalizedTable(tbl, ...)
    table.insert(self.LocalizedTables, { tbl = tbl, fields = { ... } })
end

-- Translates English text held in a variable. Anything that is not a plain
-- string, a secret included, comes back untouched.
function OxedHub.T(text)
    if issecretvalue and issecretvalue(text) then return text end
    if type(text) ~= "string" or text == "" then return text end
    return OxedHub.L[text]
end

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
    -- Cast start, for rules that need to speak up while the cast bar is still
    -- running rather than after it lands. Channels report their beginning under
    -- a different event, so both are taken and treated the same.
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player", "pet")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player", "pet")
    -- The end of a channel. Needed because a channel reports every one of its
    -- ticks as a successful cast, and knowing when it stopped is what tells
    -- those ticks apart from the player casting the spell again.
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "pet")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "pet", "target", "focus", "mouseover")

    -- Other trigger events
    eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    eventFrame:RegisterEvent("BOSS_KILL")
    eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    -- PvP kills. COMBAT_LOG_EVENT_UNFILTERED is gone for addons in 12.0, so the
    -- standalone PARTY_KILL event is how kills are detected now.
    eventFrame:RegisterEvent("PARTY_KILL")
    -- Group / party
    eventFrame:RegisterEvent("GROUP_JOINED")
    eventFrame:RegisterEvent("GROUP_LEFT")
    eventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
    eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("PLAYER_CONTROL_LOST")
    eventFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
    eventFrame:RegisterEvent("LOSS_OF_CONTROL_ADDED")
    eventFrame:RegisterEvent("LOSS_OF_CONTROL_UPDATE")
    eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
    eventFrame:RegisterEvent("UPDATE_PENDING_MAIL")
    -- Pet tracking only needs player/pet-specific unit events, not global traffic.
    eventFrame:RegisterUnitEvent("UNIT_PET", "player")
    eventFrame:RegisterUnitEvent("UNIT_FLAGS", "pet")
    -- We track pet health and party health
    eventFrame:RegisterUnitEvent("UNIT_HEALTH", "pet", "party1", "party2", "party3", "party4")
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
