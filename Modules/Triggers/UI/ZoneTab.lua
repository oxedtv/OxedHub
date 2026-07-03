local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

local function CreateBorderedFrame(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
    return f
end

function Triggers:CreateZoneUI(frame, trigger)
    local zones = trigger.zones or {}
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText(L["ZONES_ONLY_PLAY_IN"] or "Only play in these zones:")
    title:SetTextColor(1, 1, 1, 1)
    
    local zoneTypes = {
        { key = "OPEN_WORLD", label = L["ZONES_OPEN_WORLD"] or "Open World", desc = L["ZONES_MAP"] or "Map", icon = "Interface\\Icons\\INV_Misc_Map02", col = 1, row = 1 },
        { key = "PARTY", label = L["ZONES_DUNGEONS"] or "Dungeons", desc = L["ZONES_DUNGEONS_DESC"] or "Dungeons (5-man)", icon = 134149, col = 1, row = 2 },
        { key = "DELVE", label = L["ZONES_DELVES"] or "Delves", desc = L["ZONES_DELVES_DESC"] or "Delves (1-5 man)", icon = 6025441, col = 1, row = 3 },
        { key = "RAID", label = L["ZONES_RAIDS"] or "Raids", desc = L["ZONES_RAIDS_DESC"] or "Raids (10-40 man)", icon = 134153, col = 1, row = 4 },
        { key = "PVP", label = L["ZONES_ARENAS"] or "Arenas & Skirmishes", desc = "", icon = "Interface\\Icons\\Achievement_Arena_2v2_7", col = 2, row = 1 },
        { key = "BATTLEGROUND", label = L["ZONES_BATTLEGROUNDS"] or "Battlegrounds", desc = "", icon = "Interface\\Icons\\Achievement_BG_winWSG", col = 2, row = 2 },
    }
    
    local colWidth = 450
    local rowHeight = 60
    local spacingX = 20
    local spacingY = 8
    
    local container = CreateFrame("Frame", nil, frame)
    container:SetPoint("TOP", title, "BOTTOM", 0, -15)
    container:SetSize((colWidth * 2) + spacingX, (rowHeight * 4) + (spacingY * 3))
    
    for _, data in ipairs(zoneTypes) do
        local btn = CreateBorderedFrame(container)
        btn:SetSize(colWidth, rowHeight)
        
        local x = (data.col - 1) * (colWidth + spacingX)
        local y = -(data.row - 1) * (rowHeight + spacingY)
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
        
        local check = CreateFrame("CheckButton", nil, btn, "UICheckButtonTemplate")
        check:SetPoint("LEFT", btn, "LEFT", 10, 0)
        check:SetSize(28, 28)
        check:SetChecked(zones[data.key] or false)
        check:SetScript("OnClick", function(self)
            zones[data.key] = self:GetChecked()
            if frame:GetParent() and Triggers.ShowAutoSaved then
                Triggers.ShowAutoSaved(frame:GetParent())
            end
        end)
        
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT", check, "RIGHT", 6, 0)
        icon:SetTexture(data.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        label:SetPoint("LEFT", icon, "RIGHT", 12, (data.desc ~= "") and 8 or 0)
        label:SetText("|cffffffff" .. data.label .. "|r")
        label:SetJustifyH("LEFT")
        
        if data.desc ~= "" then
            local desc = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
        desc:SetText("|cffaaaaaa" .. data.desc .. "|r")
            desc:SetJustifyH("LEFT")
        end
    end
    
    local infoBox1 = CreateBorderedFrame(frame)
    infoBox1:SetSize((colWidth * 2) + spacingX, 65)
    infoBox1:SetPoint("TOP", container, "BOTTOM", 0, -20)
    infoBox1:SetBackdropColor(0, 0, 0, 0.6)
    
    local icon1 = infoBox1:CreateTexture(nil, "ARTWORK")
    icon1:SetSize(28, 28)
    icon1:SetPoint("LEFT", infoBox1, "LEFT", 14, 0)
    icon1:SetTexture("Interface\\common\\help-i")
    
    local infoTitle1 = infoBox1:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoTitle1:SetPoint("TOPLEFT", icon1, "TOPRIGHT", 10, 2)
    infoTitle1:SetText("|cffffd100" .. (L["ZONES_RESTRICTIONS_TITLE"] or "Zone Restrictions:") .. "|r")
    
    local infoDesc1 = infoBox1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoDesc1:SetPoint("TOPLEFT", infoTitle1, "BOTTOMLEFT", 0, -4)
    infoDesc1:SetWidth(850)
    infoDesc1:SetJustifyH("LEFT")
    infoDesc1:SetText(L["ZONES_RESTRICTIONS_DESC"] or "Triggers will only execute when your character is currently in one of the selected zone types.\nIf you uncheck all zones, the trigger will effectively be disabled everywhere.")
    
    local infoBox2 = CreateBorderedFrame(frame)
    infoBox2:SetSize((colWidth * 2) + spacingX, 65)
    infoBox2:SetPoint("TOP", infoBox1, "BOTTOM", 0, -10)
    infoBox2:SetBackdropColor(0.2, 0, 0, 0.3)
    infoBox2:SetBackdropBorderColor(0.8, 0.3, 0.3, 0.8)
    
    local icon2 = infoBox2:CreateTexture(nil, "ARTWORK")
    icon2:SetSize(28, 28)
    icon2:SetPoint("LEFT", infoBox2, "LEFT", 14, 0)
    icon2:SetTexture("Interface\\common\\help-i")
    
    local infoTitle2 = infoBox2:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoTitle2:SetPoint("TOPLEFT", icon2, "TOPRIGHT", 10, 2)
    infoTitle2:SetText("|cffffd100" .. (L["ZONES_COMBAT_DISCLAIMER_TITLE"] or "Important Combat Disclaimer:") .. "|r")
    
    local infoDesc2 = infoBox2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoDesc2:SetPoint("TOPLEFT", infoTitle2, "BOTTOMLEFT", 0, -4)
    infoDesc2:SetWidth(850)
    infoDesc2:SetJustifyH("LEFT")
    infoDesc2:SetText(L["ZONES_COMBAT_DISCLAIMER_DESC"] or "Some actions, like sending automated Chat Messages or performing Emotes, are heavily restricted by World of Warcraft while you are actively engaged in combat, regardless of your zone settings.")
end
