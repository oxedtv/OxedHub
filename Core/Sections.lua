local addonName, OxedHub = ...

-- Sections: which of the main pages this player uses.
--
-- Dashboard and Settings are always there. The six below are the player's
-- choice, made in the setup wizard (UI\Wizard.lua) and kept for the whole
-- account in OxedHubDB.globalSettings.sections. Until a choice is saved the
-- table does not exist and every section counts as on, so a player who never
-- ran the wizard sees the addon exactly as before.
--
-- Two questions, two answers:
--   IsEnabled  what the player has chosen, right now. The window follows this
--              at once: the page and its sidebar button come and go.
--   IsActive   what was chosen when this session started. The work itself
--              follows this (rules firing, the ring's key, hubs on screen, the
--              toy dock, modules), because hubs and the ring are secure frames
--              that cannot be built or taken down mid-fight. A changed choice
--              therefore takes effect after a reload, and the wizard asks.
-- Saved data of a section that is off is never touched.

local Sections = {}
OxedHub.Sections = Sections

-- Order is the sidebar's order. desc says what the section is and detail why a
-- player would want it; both are plain English, translated where they are
-- shown with OxedHub.T.
Sections.LIST = {
    { key = "Triggers",  icon = "Interface\\Icons\\Spell_arcane_blast",
      desc = "Play a sound or an animation when something happens in the game.",
      detail = "For example: a horn on Bloodlust, a meme when you die, a cheer on a kill." },
    { key = "Reactions", icon = "Interface\\Icons\\UI_Chat",
      desc = "Your library of sounds, animations, emotes and chat lines.",
      detail = "Triggers, OxedRing and ActionHub all pick from it. Add your own files here." },
    { key = "Toys",      icon = "Interface\\Icons\\INV_Misc_Dice_01",
      desc = "Your toy collection, toy mixes and a dock for quick use.",
      detail = "Find a toy fast, fire several at once, keep favourites one click away." },
    { key = "OxedRing",  icon = 133402,
      desc = "A round menu on one key for toys, spells, mounts and markers.",
      detail = "Hold the key, point at a slice, let go. It takes no room on your bars." },
    { key = "ActionHub", icon = "Interface\\Icons\\INV_Sword_04",
      desc = "Extra buttons on screen for spells, items and toys.",
      detail = "Put them anywhere, in any shape, with their own keys and cooldowns." },
    { key = "Modules",   icon = "Interface\\Icons\\INV_Misc_EngGizmos_01",
      desc = "Small optional tools: auto vendor, boss timers, chat filter and more.",
      detail = "Each one is off until you switch it on. You pick them on the next step." },
}

local KNOWN = {}
for _, entry in ipairs(Sections.LIST) do
    KNOWN[entry.key] = true
end

local function Saved()
    local gs = type(OxedHubDB) == "table" and OxedHubDB.globalSettings
    if type(gs) == "table" and type(gs.sections) == "table" then
        return gs.sections
    end
    return nil
end

-- True once the wizard has been finished at least once.
function Sections:HasChosen()
    return Saved() ~= nil
end

-- Anything that is not one of the six (Dashboard, Settings, About) is always on.
function Sections:IsEnabled(key)
    if not KNOWN[key] then
        return true
    end
    local saved = Saved()
    if not saved then
        return true
    end
    return saved[key] == true
end

-- The state at the start of the session. Taken on the first question that
-- arrives once the saved settings exist, which is during login; asked earlier
-- than that it answers "on" and takes nothing.
local sessionState = nil
local function Session()
    if sessionState then
        return sessionState
    end
    local gs = type(OxedHubDB) == "table" and OxedHubDB.globalSettings
    if type(gs) ~= "table" then
        return nil
    end
    local state = {}
    for _, entry in ipairs(Sections.LIST) do
        state[entry.key] = Sections:IsEnabled(entry.key)
    end
    sessionState = state
    return sessionState
end

function Sections:IsActive(key)
    if not KNOWN[key] then
        return true
    end
    local state = Session()
    if not state then
        return true
    end
    return state[key] == true
end

-- True when the choice no longer matches what this session is running.
function Sections:NeedsReload()
    local state = Session()
    if not state then
        return false
    end
    for _, entry in ipairs(self.LIST) do
        if state[entry.key] ~= self:IsEnabled(entry.key) then
            return true
        end
    end
    return false
end

-- A fresh key -> boolean table of the current state, for the wizard to edit.
function Sections:GetChoice()
    local choice = {}
    for _, entry in ipairs(self.LIST) do
        choice[entry.key] = self:IsEnabled(entry.key)
    end
    return choice
end

function Sections:CountChosen(choice)
    local count = 0
    if type(choice) == "table" then
        for _, entry in ipairs(self.LIST) do
            if choice[entry.key] then
                count = count + 1
            end
        end
    end
    return count
end

-- Saves a choice. Refuses, and returns false, when nothing is chosen.
function Sections:Save(choice)
    if self:CountChosen(choice) < 1 then
        return false
    end
    if type(OxedHubDB) ~= "table" then
        return false
    end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    local saved = {}
    for _, entry in ipairs(self.LIST) do
        saved[entry.key] = choice[entry.key] and true or false
    end
    OxedHubDB.globalSettings.sections = saved
    return true
end

-- Forgets the choice: every section is on again, as before the wizard.
function Sections:Reset()
    if type(OxedHubDB) == "table" and type(OxedHubDB.globalSettings) == "table" then
        OxedHubDB.globalSettings.sections = nil
        -- So the wizard offers itself again on the next opening of the window.
        OxedHubDB.globalSettings.wizardOffered = nil
        -- And the Modules page lists every module again.
        OxedHubDB.globalSettings.pickedModules = nil
    end
end
