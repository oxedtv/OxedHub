-- Signature.lua
-- A small grey "OxedHub" under the bottom-right corner of OxedHub's windows,
-- so a player can tell which addon a window on screen belongs to. The same
-- look InviterInfo's group window already had.
--
-- Two ways a frame gets it:
--   * OxedHub:Sign(frame), for unnamed windows (every module options window
--     is signed this way from ModuleAPI:CreateOptionsWindow).
--   * A sweep, out of combat, over UIParent's shown children named OxedHub*
--     or OxMythicLooter*: a window (big enough, with a background of its own)
--     is signed the first time it is seen. Bars, icons, rings and full-screen
--     effects are left alone, and so is a frame that already says "OxedHub".
--
-- Each frame is looked at once; the answer is remembered (weak table), so the
-- sweep costs a name check per child after that.

local addonName, OxedHub = ...

local PREFIXES = { "OxedHub", "OxMythicLooter" }
local SKIP = { OxedHubMainFrame = true }   -- the hub itself has its title
local SWEEP_EVERY = 4
local MIN_W, MIN_H = 140, 60

local decided = setmetatable({}, { __mode = "k" })   -- frame -> true / false

function OxedHub:Sign(frame)
    if not frame or decided[frame] == true or frame.oxedSignature then return end
    if frame.IsForbidden and frame:IsForbidden() then return end
    local ok, text = pcall(frame.CreateFontString, frame, nil, "OVERLAY", "GameFontNormalSmall")
    if not ok or not text then return end
    text:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -8, -1)
    text:SetText("OxedHub")
    text:SetTextColor(1, 0.82, 0)   -- gold, readable against the world
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
    frame.oxedSignature = text
    decided[frame] = true
end

local function IsOurs(name)
    if type(name) ~= "string" or SKIP[name] then return false end
    for _, prefix in ipairs(PREFIXES) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

-- Already signed by its own module (InviterInfo's footer, for one).
local function SaysOxedHub(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:GetObjectType() == "FontString" then
            local ok, t = pcall(region.GetText, region)
            if ok and type(t) == "string" and not (issecretvalue and issecretvalue(t))
                and t:find("OxedHub") then
                return true
            end
        end
    end
    return false
end

-- A window rather than a bar, an icon or an invisible holder.
local function HasBackground(frame, w, h)
    if frame.NineSlice or frame.Bg or frame.TitleBg or frame.Inset or frame.bg or frame.background then
        return true
    end
    if frame.GetBackdrop then
        local ok, backdrop = pcall(frame.GetBackdrop, frame)
        if ok and backdrop then return true end
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:GetObjectType() == "Texture" and region:GetDrawLayer() == "BACKGROUND" then
            local rw, rh = region:GetSize()
            if rw and rh and rw >= w * 0.7 and rh >= h * 0.7 then return true end
        end
    end
    return false
end

local function Consider(frame)
    if decided[frame] ~= nil or frame.oxedSignature then return end
    if frame.IsForbidden and frame:IsForbidden() then decided[frame] = false return end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or not IsOurs(name) then decided[frame] = false return end
    if not frame:IsShown() then return end          -- judged once it is on screen
    local w, h = frame:GetSize()
    if not (w and h) or w <= 1 or h <= 1 then return end   -- not laid out yet
    local screenW = UIParent:GetWidth() or 1920
    if w < MIN_W or h < MIN_H or w > screenW * 0.7 then decided[frame] = false return end
    if SaysOxedHub(frame) or not HasBackground(frame, w, h) then decided[frame] = false return end
    OxedHub:Sign(frame)
end

local function Sweep()
    if InCombatLockdown() then return end
    for _, child in ipairs({ UIParent:GetChildren() }) do
        if decided[child] == nil then pcall(Consider, child) end
    end
end

local ticker = CreateFrame("Frame")
local since = 0
ticker:RegisterEvent("PLAYER_LOGIN")
ticker:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    self:SetScript("OnUpdate", function(_, elapsed)
        since = since + elapsed
        if since < SWEEP_EVERY then return end
        since = 0
        Sweep()
    end)
end)
