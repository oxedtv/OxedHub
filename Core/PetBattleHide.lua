-- PetBattleHide.lua
-- Hides OxedHub's on-screen frames while a pet battle is up, and gives them
-- back afterwards.
--
-- Which frames: every shown child of UIParent whose name starts with one of
-- NAME_PREFIXES, plus unnamed frames a module hands to
-- OxedHub:HideInPetBattle(frame). Windows the player closes with Escape
-- (UISpecialFrames) are left alone, so one opened during the battle works.
--
-- A managed frame that its module shows mid-battle is hidden again by a hook,
-- and remembered as wanted. One its module hides mid-battle (a toast running
-- out) stays hidden afterwards, so nothing stale comes back at the end.

local addonName, OxedHub = ...

local NAME_PREFIXES = { "OxedHub", "OxedRing", "OxMythicLooter", "MemedOn" }

local registered = setmetatable({}, { __mode = "k" })  -- unnamed frames from modules
local managed = {}       -- frame -> true while the battle lasts
local wanted = {}        -- frame -> true: its module wants it shown
local hooked = setmetatable({}, { __mode = "k" })
local active = false
local busy = false       -- our own Show / Hide, not the module's

local function HideQuietly(frame)
    busy = true
    frame:Hide()
    busy = false
end

-- The module's own Show / Hide during a battle. Protected frames get no hook:
-- the sweep at the start is all they get.
local function OnShown(frame)
    if not active or busy or not managed[frame] then return end
    wanted[frame] = true
    HideQuietly(frame)
end

local function OnHidden(frame)
    if active and not busy and managed[frame] then wanted[frame] = nil end
end

local function Hook(frame)
    if hooked[frame] or frame:IsProtected() then return end
    hooked[frame] = true
    hooksecurefunc(frame, "Show", OnShown)
    hooksecurefunc(frame, "Hide", OnHidden)
    hooksecurefunc(frame, "SetShown", function(f, shown)
        if shown then OnShown(f) else OnHidden(f) end
    end)
end

-- onlyShown: named frames are taken only when on screen, so a window the
-- player opens mid-battle is not snatched away. Registered ones are HUD.
local function Manage(frame, onlyShown)
    if frame:IsForbidden() or managed[frame] then return end
    -- Event-only frames have no points; hiding one would stop its OnUpdate.
    if frame:GetNumPoints() == 0 and not registered[frame] then return end
    local shown = frame:IsShown()
    if onlyShown and not shown then return end
    if frame:IsProtected() and InCombatLockdown() then return end
    managed[frame] = true
    Hook(frame)
    if shown then
        wanted[frame] = true
        HideQuietly(frame)
    end
end

function OxedHub:HideInPetBattle(frame)
    if not frame then return end
    registered[frame] = true
    if active then pcall(Manage, frame, false) end
end

local function IsOurName(name)
    if type(name) ~= "string" then return false end
    for _, prefix in ipairs(NAME_PREFIXES) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function IsEscapeWindow(name)
    if not UISpecialFrames then return false end
    for _, special in ipairs(UISpecialFrames) do
        if special == name then return true end
    end
    return false
end

local function HideAll()
    if active then return end
    active = true
    for _, child in ipairs({ UIParent:GetChildren() }) do
        pcall(function()
            if child:IsForbidden() then return end
            local name = child:GetName()
            if IsOurName(name) and not IsEscapeWindow(name) then Manage(child, true) end
        end)
    end
    for frame in pairs(registered) do
        pcall(Manage, frame, false)
    end
end

local function ShowAll()
    if not active then return end
    active = false
    for frame in pairs(wanted) do
        pcall(function()
            if frame:IsProtected() and InCombatLockdown() then return end
            frame:Show()
        end)
    end
    wipe(wanted)
    wipe(managed)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:RegisterEvent("PET_BATTLE_OPENING_START")
        self:RegisterEvent("PET_BATTLE_CLOSE")
        -- A reload in the middle of a battle: wait for the modules to draw.
        if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
            C_Timer.After(2, function()
                if C_PetBattles.IsInBattle() then HideAll() end
            end)
        end
    elseif event == "PET_BATTLE_OPENING_START" then
        HideAll()
    elseif event == "PET_BATTLE_CLOSE" then
        -- Fires twice per battle; the second finds nothing to do.
        ShowAll()
    end
end)
