-- ============================================================================
-- Context Menu Links (built-in OxedHub module)
-- Right-click a player or an NPC: a "Copy link" entry gives its Wowhead,
-- Raider.IO, Warcraft Logs or Armory page in a box ready to copy (Ctrl+C).
--
-- ⚠ Notes for whoever edits this next:
--   * Menu.ModifyMenu cannot be taken back, so the entries are added once and
--     check settings.enabled each time the menu opens.
--   * Names, realms and GUIDs can be secret; anything secret gives no entry.
--   * The copy box is the game's own StaticPopup edit box, focused only while
--     the popup is shown.
-- ============================================================================

local addonName, OxedHub = ...
local L = OxedHub.L

local DEFAULTS = {
    enabled   = false,   -- off until the player switches it on
    wowhead   = true,
    raiderio  = true,
    logs      = true,
    armory    = false,
}

local settings
local optionsWindow
local installed = false

local REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }

local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Region()
    local id = GetCurrentRegion and GetCurrentRegion()
    return REGIONS[id] or "eu"
end

-- "Argent Dawn", "ArgentDawn" or "Argent-Dawn" -> "argent-dawn".
local function RealmSlug(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    if not realm:find(" ") and not realm:find("%-") then
        realm = realm:gsub("(%l)(%u)", "%1-%2")
    end
    realm = realm:gsub("'", ""):gsub("%s+", "-"):lower()
    return realm
end

-- ── The copy box ────────────────────────────────────────────────────────────

local POPUP = "OXEDHUB_CONTEXT_LINK"
StaticPopupDialogs[POPUP] = {
    text = "%s",
    button1 = CLOSE or "Close",
    hasEditBox = 1,
    editBoxWidth = 350,
    OnShow = function(self, data)
        local box = self.editBox or self.EditBox
        if not box then return end
        box:SetText(data or "")
        box:SetFocus()
        box:HighlightText()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3,
}

local function ShowLink(title, url)
    StaticPopup_Show(POPUP, title .. "\n" .. L["Ctrl+C to copy"], nil, url)
end

-- ── What to offer ───────────────────────────────────────────────────────────

local function PlayerLinks(name, realm)
    local region, slug = Region(), RealmSlug(realm)
    if not slug then return {} end
    local links = {}
    if settings.raiderio then
        links[#links + 1] = { "Raider.IO", ("https://raider.io/characters/%s/%s/%s"):format(region, slug, name) }
    end
    if settings.logs then
        links[#links + 1] = { "Warcraft Logs", ("https://www.warcraftlogs.com/character/%s/%s/%s"):format(region, slug, name:lower()) }
    end
    if settings.armory then
        links[#links + 1] = { "Armory", ("https://worldofwarcraft.blizzard.com/character/%s/%s/%s"):format(region, slug, name:lower()) }
    end
    return links
end

local function NpcLinks(guid)
    local kind, _, _, _, _, npcId = strsplit("-", guid)
    if not (settings.wowhead and (kind == "Creature" or kind == "Vehicle") and npcId) then return {} end
    return { { "Wowhead", "https://www.wowhead.com/npc=" .. npcId } }
end

local function LinksFor(contextData)
    if type(contextData) ~= "table" then return {} end
    local unit = Plain(contextData.unit)
    -- An NPC's menu has a unit and a creature GUID.
    if type(unit) == "string" then
        local okP, isPlayer = pcall(UnitIsPlayer, unit)
        isPlayer = okP and Plain(isPlayer)
        if isPlayer == false then
            local okG, guid = pcall(UnitGUID, unit)
            guid = okG and Plain(guid)
            return type(guid) == "string" and NpcLinks(guid) or {}
        end
    end
    local name = Plain(contextData.name)
    local realm = Plain(contextData.server)
    if type(name) ~= "string" or name == "" then return {} end
    -- "Name-Realm" in one string, as some menus pass it.
    local short, fromName = name:match("^([^%-]+)%-(.+)$")
    if short then name, realm = short, realm or fromName end
    if type(realm) ~= "string" or realm == "" then realm = GetRealmName and GetRealmName() end
    return PlayerLinks(name, realm)
end

local MENUS = {
    "MENU_UNIT_SELF", "MENU_UNIT_PLAYER", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_PARTY",
    "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_FRIEND", "MENU_UNIT_BN_FRIEND",
    "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_COMMUNITIES_MEMBER",
    "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_GUILD", "MENU_LFG_FRAME_SEARCH_ENTRY",
}

local function AddEntries(_, root, contextData)
    if not (settings and settings.enabled) then return end
    local ok, links = pcall(LinksFor, contextData)
    if not ok or #links == 0 then return end
    root:CreateDivider()
    local sub = root:CreateButton(L["Copy link"])
    for _, link in ipairs(links) do
        local title, url = link[1], link[2]
        sub:CreateButton(title, function() ShowLink(title, url) end)
    end
end

local function Install()
    if installed or not (Menu and Menu.ModifyMenu) then return end
    installed = true
    for _, tag in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, AddEntries)
    end
end

-- ── Options ─────────────────────────────────────────────────────────────────

local function ShowOptions()
    local API = OxedHub.ModuleAPI
    if not API or not settings then return end
    if not optionsWindow then
        local w = API:CreateOptionsWindow("Context Menu Links", 440, 300)
        optionsWindow = w
        w:AddCheckbox(settings, "wowhead", "Wowhead (NPCs)")
        w:AddCheckbox(settings, "raiderio", "Raider.IO (players)")
        w:AddCheckbox(settings, "logs", "Warcraft Logs (players)")
        w:AddCheckbox(settings, "armory", "Armory (players)")
        w:AddNote("Right-click a player or an NPC and open \"Copy link\".")
    end
    optionsWindow:Show()
end

-- ── Login ───────────────────────────────────────────────────────────────────

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    OxedHubDB = OxedHubDB or {}
    OxedHubDB.modules = OxedHubDB.modules or {}
    local config = OxedHubDB.modules.contextlinks
    if type(config) ~= "table" then
        config = {}
        OxedHubDB.modules.contextlinks = config
    end
    for key, value in pairs(DEFAULTS) do
        if config[key] == nil then config[key] = value end
    end
    settings = config

    if not OxedHub.ModuleAPI then return end
    OxedHub.ModuleAPI:Register({
        id       = "contextlinks",
        name     = "Context Menu Links",
        version  = "1.0.0",
        added    = 20261127,
        updated  = 20261127,
        author   = "Oxed",
        category = "chat",
        keywords = { "wowhead", "raider.io", "raiderio", "warcraft logs", "wcl", "armory", "link", "copy", "right-click", "menu" },
        desc     = "Right-click a player or NPC to copy its Wowhead, Raider.IO or Warcraft Logs link.",
        icon     = "Interface\\Icons\\INV_Misc_Note_05",
        defaults = DEFAULTS,
        OnOptionsShow = function() ShowOptions() end,
        OnEnable = function(_, cfg)
            settings = cfg
            Install()
        end,
        OnDisable = function() end,   -- the entries check settings.enabled
    })
end)
