local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

local DB = KeystoneLoot.DB;
local L = KeystoneLoot.L;

-- https://wowwiki-archive.fandom.com/wiki/USERAPI_GetMinimapShape
local MINIMAP_SHAPES = {
    ["ROUND"]                 = { true, true, true, true },
    ["SQUARE"]                = { false, false, false, false },
    ["CORNER-TOPLEFT"]        = { false, false, false, true },
    ["CORNER-TOPRIGHT"]       = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"]     = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"]    = { true, false, false, false },
    ["SIDE-LEFT"]             = { false, true, false, true },
    ["SIDE-RIGHT"]            = { true, false, true, false },
    ["SIDE-TOP"]              = { false, false, true, true },
    ["SIDE-BOTTOM"]           = { true, true, false, false },
    ["TRICORNER-TOPLEFT"]     = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"]    = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"]  = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
};

local function GetPosition(degrees, radius)
    local angle = math.rad(degrees);
    local cos = math.cos(angle);
    local sin = math.sin(angle);

    local q = 1;
    if (cos < 0) then
        q = q + 1;
    end

    if (sin > 0) then
        q = q + 2;
    end

    local width        = (Minimap:GetWidth() / 2) + radius;
    local height       = (Minimap:GetHeight() / 2) + radius;

    local minimapShape = GetMinimapShape and GetMinimapShape() or "ROUND";
    local x, y;

    if (MINIMAP_SHAPES[minimapShape][q]) then
        x = cos * width;
        y = sin * height;
    else
        x = math.max(-width, math.min(cos * (math.sqrt(2 * width ^ 2) - 10), width));
        y = math.max(-height, math.min(sin * (math.sqrt(2 * height ^ 2) - 10), height));
    end

    return "CENTER", x, y;
end

OxMythicLooterMinimapButtonMixin = {};

function OxMythicLooterMinimapButtonMixin:OnLoad()
    self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    self:RegisterForDrag("LeftButton");
end

function OxMythicLooterMinimapButtonMixin:Init()
    AddonCompartmentFrame:RegisterAddon({
        text                = AddonName,
        icon                = "Interface\\Icons\\INV_Relics_Hourglass_02",
        notCheckable        = true,
        registerForAnyClick = true,
        func                = function(_, _, _, _, mouseButton)
            self:OnClick(mouseButton);
        end,
        funcOnEnter         = function() self:OnEnter(); end,
        funcOnLeave         = function() self:OnLeave(); end,
    });

    -- LibDataBroker / LibDBIcon support
    if (LibStub) then
        local dataObject = {
            label   = AddonName,
            tocname = AddonName,
            type    = "launcher",
            icon    = "Interface\\Icons\\INV_Relics_Hourglass_02",
            OnClick = function(_, button) self:OnClick(button); end,
            OnEnter = self.OnEnter,
            OnLeave = self.OnLeave,
        };

        local LDB = LibStub("LibDataBroker-1.1", true);
        if (LDB) then
            LDB:NewDataObject(AddonName, dataObject);
        end

        local LDBIcon = LibStub("LibDBIcon-1.0", true);
        if (LDBIcon) then
            local minimapTable = DB:Get("settings.minimap");
            LDBIcon:Register(AddonName, dataObject, minimapTable);

            -- Never while the OxedHub module is switched off (OnEnable shows it).
            local mod = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.mythiclooter;
            local moduleOff = type(mod) == "table" and mod.enabled == false;
            if (DB:Get("settings.minimapButton.hide") or moduleOff) then
                LDBIcon:Hide(AddonName);
            end

            -- No need to manage visibility ourselves if we have LibDBIcon
            self:SetParent(UIParent);
            self:Hide();
            return;
        end
    end

    -- No LDBIcon — manage visibility ourselves
    DB:AddObserver("settings.minimap.enabled", function(enabled)
        self:SetShown(enabled);
    end);

    local mod = OxedHubDB and OxedHubDB.modules and OxedHubDB.modules.mythiclooter;
    self:SetShown(DB:Get("settings.minimap.enabled") and not (type(mod) == "table" and mod.enabled == false));
    self:SetPoint(GetPosition(DB:Get("settings.minimap.degrees"), 5));
end

function OxMythicLooterMinimapButtonMixin:OnUpdate()
    local scale = Minimap:GetEffectiveScale();
    local minimapX, minimapY = Minimap:GetCenter();
    local cursorX, cursorY = GetCursorPosition();

    cursorX = cursorX / scale;
    cursorY = cursorY / scale;

    self.degrees = math.deg(math.atan2(cursorY - minimapY, cursorX - minimapX)) % 360;
    self:SetPoint(GetPosition(self.degrees, 5));
end

function OxMythicLooterMinimapButtonMixin:OnEnter()
    GameTooltip:SetOwner(self, "ANCHOR_LEFT");
    GameTooltip:SetText("Oxed " .. AddonName, 1, 1, 1);
    GameTooltip:AddLine(L["Left click: Open overview"]);
    GameTooltip:Show();
end

function OxMythicLooterMinimapButtonMixin:OnLeave()
    GameTooltip:Hide();
end

function OxMythicLooterMinimapButtonMixin:OnMouseDown()
    self.Icon:AdjustPointsOffset(1, -1);
end

function OxMythicLooterMinimapButtonMixin:OnMouseUp()
    self.Icon:AdjustPointsOffset(-1, 1);
end

function OxMythicLooterMinimapButtonMixin:OnDragStart()
    self:LockHighlight();
    self:SetScript("OnUpdate", self.OnUpdate);
    self:OnMouseUp();
    self:OnLeave();
end

function OxMythicLooterMinimapButtonMixin:OnDragStop()
    self:UnlockHighlight();
    self:SetScript("OnUpdate", nil);

    DB:Set("settings.minimap.degrees", self.degrees);
end

function OxMythicLooterMinimapButtonMixin:OnClick(button)
    OxMythicLooterFrame:SetShown(not OxMythicLooterFrame:IsShown());
end
