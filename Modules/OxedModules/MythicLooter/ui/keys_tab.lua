-- MythicLooter's Keys tab: the party's keystones inside the loot window, for
-- whoever would rather not keep the Party Keystones list on screen. The keys
-- come from that list's code (KickSyncKeystones.lua), so both always agree;
-- the floating list stays as it is.
--
-- ⚠ Each dungeon icon casts its teleport through a secure button, whose
-- spell can only be set out of combat. In combat the rows keep what they
-- showed and are brought up to date when the fight ends.
local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter;

local KeysTab = {};
KeystoneLoot.KeysTab = KeysTab;

local ROW_H, ICON = 52, 44;
local MAX_ROWS = 5;
local RATING_HEX = "ff8000";

local function Keys()
    return OxedHub.KickSyncKeystones;
end

local function RedButton(button)
    local Button = OxedHub.UIComponents and OxedHub.UIComponents.Button;
    if (Button and Button.ApplyRedStyle) then pcall(Button.ApplyRedStyle, button); end
end

local function CreateRow(frame, i)
    local row = CreateFrame("Frame", nil, frame);
    row:SetHeight(ROW_H);
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -86 - (i - 1) * (ROW_H + 6));
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -86 - (i - 1) * (ROW_H + 6));

    local bg = row:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints();
    bg:SetColorTexture(0, 0, 0, 0.35);
    local edge = row:CreateTexture(nil, "BORDER");
    edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT");
    edge:SetHeight(1);
    edge:SetColorTexture(1, 0.82, 0, 0.25);

    local btn = CreateFrame("Button", nil, row, "SecureActionButtonTemplate");
    btn:SetSize(ICON, ICON);
    btn:SetPoint("LEFT", row, "LEFT", 4, 0);
    btn:RegisterForClicks("AnyUp", "AnyDown");
    btn:SetAttribute("type", "spell");
    btn.icon = btn:CreateTexture(nil, "ARTWORK");
    btn.icon:SetAllPoints();
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    local hl = btn:CreateTexture(nil, "HIGHLIGHT");
    hl:SetAllPoints();
    hl:SetColorTexture(1, 1, 1, 0.2);
    btn.level = btn:CreateFontString(nil, "OVERLAY");
    btn.level:SetFont(STANDARD_TEXT_FONT, 17, "OUTLINE");
    btn.level:SetPoint("CENTER");
    btn:SetScript("OnEnter", function(self)
        local id = self:GetAttribute("spell");
        if (not id) then return; end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetSpellByID(id);
        GameTooltip:AddLine("|cffffd100Click to teleport|r");
        GameTooltip:Show();
    end);
    btn:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    row.btn = btn;

    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    row.who:SetPoint("TOPLEFT", btn, "TOPRIGHT", 10, -4);
    row.who:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    row.who:SetJustifyH("LEFT");
    row.who:SetWordWrap(false);

    row.dungeon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
    row.dungeon:SetPoint("TOPLEFT", row.who, "BOTTOMLEFT", 0, -4);
    row.dungeon:SetPoint("RIGHT", row, "RIGHT", -8, 0);
    row.dungeon:SetJustifyH("LEFT");
    row.dungeon:SetWordWrap(false);
    return row;
end

local dirty = false

local function Render(frame)
    if (not frame:IsVisible()) then return; end
    if (InCombatLockdown()) then
        dirty = true;
        return;
    end
    dirty = false;

    local KL = Keys();
    local list = KL and KL.GetPartyKeys and KL:GetPartyKeys() or {};
    frame.empty:SetShown(#list == 0);
    frame.count:SetFormattedText("%d %s", #list, #list == 1 and "key" or "keys");

    for i = 1, MAX_ROWS do
        local item = list[i];
        local row = frame.rows[i];
        if (item and not row) then
            row = CreateRow(frame, i);
            frame.rows[i] = row;
        end
        if (row) then
            if (item) then
                local _, _, _, texture = C_ChallengeMode.GetMapUIInfo(item.mapID);
                row.btn.icon:SetTexture(texture or "Interface\\Icons\\INV_Relics_Hourglass");
                row.btn.level:SetText("+" .. item.level);
                row.btn:SetAttribute("spell", item.port);
                local colour = item.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class];
                local hex = colour and colour.colorStr or "ffffffff";
                if (item.rating) then
                    row.who:SetFormattedText("|c%s%s|r  |cff%s(%d)|r", hex, item.name or "?", RATING_HEX, item.rating);
                else
                    row.who:SetFormattedText("|c%s%s|r", hex, item.name or "?");
                end
                row.dungeon:SetText(item.dungeon or "Mythic+");
                row:Show();
            else
                row.btn:SetAttribute("spell", nil);
                row:Hide();
            end
        end
    end
end

-- Builds the tab's frame, the size of the Dungeons tab.
function KeysTab.Create(owner, sizeLike)
    local frame = CreateFrame("Frame", nil, owner);
    local w, h = 0, 0;
    if (sizeLike and sizeLike.GetSize) then w, h = sizeLike:GetSize(); end
    if (not w or w < 300) then w = 780; end
    if (not h or h < 300) then h = 480; end
    frame:SetSize(w, h);
    frame:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0);
    frame.rows = {};

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge");
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -46);
    frame.title:SetText("Party Keystones");

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.count:SetPoint("LEFT", frame.title, "RIGHT", 10, -2);

    local announce = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    announce:SetSize(150, 22);
    announce:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -46);
    announce:SetText("Announce keys");
    RedButton(announce);
    announce:SetScript("OnClick", function()
        local KL = Keys();
        if (KL and KL.AnnounceToChat) then KL:AnnounceToChat(); end
    end);

    local sync = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
    sync:SetSize(110, 22);
    sync:SetPoint("RIGHT", announce, "LEFT", -8, 0);
    sync:SetText("Sync keys");
    RedButton(sync);
    sync:SetScript("OnClick", function()
        local KL = Keys();
        if (KL and KL.SyncNow) then KL:SyncNow(true); end
        Render(frame);
    end);

    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable");
    frame.empty:SetPoint("TOP", frame, "TOP", 0, -120);
    frame.empty:SetText("No keystones yet. Press Sync keys, or wait for the group.");

    frame:SetScript("OnShow", function(self)
        local KL = Keys();
        if (KL and KL.Initialize) then KL:Initialize(); end
        Render(self);
    end);

    -- The keystone list calls this whenever a key arrives or leaves.
    local KL = Keys();
    if (KL) then
        KL.onKeysChanged = function() Render(frame); end
    end

    local regen = CreateFrame("Frame");
    regen:RegisterEvent("PLAYER_REGEN_ENABLED");
    regen:SetScript("OnEvent", function()
        if (dirty) then Render(frame); end
    end);

    frame:Hide();
    return frame;
end
