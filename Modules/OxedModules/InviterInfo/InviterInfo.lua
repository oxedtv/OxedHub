-- ============================================================================
-- Inviter Info (built-in OxedHub module)
-- Who is inviting you, before you say yes: under the group invite popup, their
-- class, race and realm, and whether they are a friend, a Battle.net friend or
-- in your guild. A guild invite gets the same line in chat.
-- ============================================================================

local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

local DEFAULTS = {
    enabled = false,    -- off until the player switches it on
    inChat  = false,    -- also print the line in chat
    guild   = true,     -- a line for guild invites
}

local PREFIX = "|cff00ccffOxedHub|r "

local settings
local optionsWindow
local frame = CreateFrame("Frame")

local function Plain(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    return value
end

-- "Paladin, Human, Silvermoon. Your guild" with the class in its colour.
local function Describe(guid)
    guid = Plain(guid)
    if not guid then return nil end
    local ok, className, classFile, race, _, _, _, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok or not Plain(className) then return nil end
    local parts = {}
    local colour = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    parts[#parts + 1] = colour and colour:WrapTextInColorCode(className) or className
    if Plain(race) and race ~= "" then parts[#parts + 1] = race end
    if Plain(realm) and realm ~= "" then parts[#parts + 1] = realm end
    local text = table.concat(parts, ", ")

    local known = {}
    if C_FriendList and C_FriendList.IsFriend then
        local okF, isFriend = pcall(C_FriendList.IsFriend, guid)
        if okF and isFriend == true then known[#known + 1] = "friend" end
    end
    if C_BattleNet and C_BattleNet.GetAccountInfoByGUID then
        local okB, info = pcall(C_BattleNet.GetAccountInfoByGUID, guid)
        if okB and type(info) == "table" then known[#known + 1] = "Battle.net friend" end
    end
    if IsGuildMember then
        local okG, member = pcall(IsGuildMember, guid)
        if okG and member == true then known[#known + 1] = "your guild" end
    end
    if #known > 0 then
        text = text .. ". |cff40ff40" .. table.concat(known, ", ") .. "|r"
    else
        text = text .. ". |cffaaaaaaNot a friend or guild member.|r"
    end
    return text
end

frame:SetScript("OnEvent", function(_, event, ...)
    if not (settings and settings.enabled) then return end
    if event == "PARTY_INVITE_REQUEST" then
        local name, _, _, _, _, _, guid = ...
        local text = Describe(guid)
        if not text then return end
        -- The popup is shown by the same event; look for it a moment later.
        C_Timer.After(0, function()
            local API = OxedHub.ModuleAPI
            local dialog = API and API:FindPopup("PARTY_INVITE")
            if dialog then API:PopupNote(dialog, text, 1, 1, 1) end
        end)
        if settings.inChat and Plain(name) then
            print(PREFIX .. name .. " invites you: " .. text)
        end
    elseif event == "GUILD_INVITE_REQUEST" and settings.guild then
        local inviter, guildName, points, _, isNewGuild = ...
        if not (Plain(inviter) and Plain(guildName)) then return end
        local line = ("%s invites you to <%s>"):format(inviter, guildName)
        if Plain(points) then line = line .. (", %d achievement points"):format(points) end
        if isNewGuild == true then line = line .. ", |cffffd100a brand new guild|r" end
        print(PREFIX .. line .. ".")
    end
end)

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        optionsWindow = API:CreateOptionsWindow("Inviter Info", 420, 190)
        optionsWindow:AddCheckbox(settings, "inChat", "Also say it in chat")
        optionsWindow:AddCheckbox(settings, "guild", "A line in chat for guild invites")
        optionsWindow:AddNote("Shown under the group invite: class, race, realm, and whether you know them.")
    end
    optionsWindow:Show()
end

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.inviterinfo
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.inviterinfo = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "inviterinfo",
        name     = "Inviter Info",
        version  = "1.0.0",
        author   = "Oxed",
        category = "groups",
        keywords = { "invite", "group", "party", "guild", "class", "friend" },
        desc     = "Class, realm, and whether you know them, under every group invite.",
        icon     = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            frame:RegisterEvent("PARTY_INVITE_REQUEST")
            frame:RegisterEvent("GUILD_INVITE_REQUEST")
        end,
        OnDisable = function() frame:UnregisterAllEvents() end,
    })
end)
