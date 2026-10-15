local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter; AddonName = "MythicLooter";

-- One place at a time, for both tabs: a list on the left (dungeons, or raid
-- bosses under their raid's name), and on the right the chosen one -- a
-- banner with its art, name and how many items match the filters, and every
-- one of those items in a grid.
--
-- A tab calls PickerView.Setup(frame) once, then PickerView.Render(frame, view)
-- whenever something changes. view = {
--     width, rows = { { key, name, count, icon | portrait, header }, ... },
--     selected = key, onSelect = function(key),
--     banner = function(Banner) ... end,  -- fills the reused entry frame
--     subtitle = string, items = lootTable,
-- }

local PickerView = {};
KeystoneLoot.PickerView = PickerView;

local LIST_WIDTH = 200;
local LIST_ROW = 38;
local HEADER_ROW = 24;
local CELL = 46;           -- an item button (34) and the gap around it
local BANNER_HEIGHT = 72;
local TOP_MARGIN = 60;     -- under the dropdowns
local BOTTOM_MARGIN = 10;
local PAD = 8;
local MIN_DETAIL = 180;    -- the right side never shorter than this

local function CreateListRow(parent)
    local row = CreateFrame("Button", nil, parent);

    -- The game's own list plates, the ones the pet journal and the OxedHub
    -- sidebar use: no flat colour boxes.
    local bg = row:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints();
    bg:SetAtlas("PetList-ButtonBackground");
    row.Bg = bg;

    local selected = row:CreateTexture(nil, "OVERLAY", nil, 7);
    selected:SetAllPoints();
    selected:SetAtlas("PetList-ButtonSelect");
    selected:Hide();
    row.Selected = selected;

    -- Kept so PaintRow can hide it on headers; never shown.
    local edge = row:CreateTexture(nil, "ARTWORK");
    edge:Hide();
    row.Edge = edge;

    local hl = row:CreateTexture(nil, "HIGHLIGHT");
    hl:SetAllPoints();
    hl:SetAtlas("PetList-ButtonHighlight");
    row.Hl = hl;

    local icon = row:CreateTexture(nil, "ARTWORK");
    icon:SetSize(28, 28);
    icon:SetPoint("LEFT", 7, 0);
    row.Icon = icon;

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    count:SetPoint("RIGHT", -7, 0);
    count:SetJustifyH("RIGHT");
    row.Count = count;

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    name:SetPoint("LEFT", icon, "RIGHT", 7, 0);
    name:SetPoint("RIGHT", count, "LEFT", -4, 0);
    name:SetJustifyH("LEFT");
    name:SetWordWrap(false);
    row.Name = name;

    -- A raid's name over its bosses: gold, small, not a button.
    local header = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    header:SetPoint("BOTTOMLEFT", 4, 4);
    header:SetPoint("BOTTOMRIGHT", -4, 4);
    header:SetJustifyH("LEFT");
    header:SetWordWrap(false);
    row.Header = header;

    local rule = row:CreateTexture(nil, "ARTWORK");
    rule:SetPoint("BOTTOMLEFT", 2, 1);
    rule:SetPoint("BOTTOMRIGHT", -2, 1);
    rule:SetHeight(7);
    rule:SetAtlas("Options_HorizontalDivider");
    row.Rule = rule;

    return row;
end

local function PaintRow(row, data, isSelected)
    if (data.header) then
        row:SetHeight(HEADER_ROW);
        row:EnableMouse(false);
        row.Header:SetText(data.name or "");
        row.Header:Show();
        row.Rule:Show();
        for _, part in ipairs({ row.Bg, row.Selected, row.Edge, row.Hl, row.Icon, row.Count, row.Name }) do
            part:Hide();
        end
        return;
    end

    row:SetHeight(LIST_ROW - 2);
    row:EnableMouse(true);
    row.Header:Hide();
    row.Rule:Hide();
    row.Hl:Show();
    row.Icon:Show();
    row.Count:Show();
    row.Name:Show();

    if (data.portrait) then
        row.Icon:SetTexCoord(0, 1, 0, 1);
        SetPortraitTextureFromCreatureDisplayID(row.Icon, data.portrait);
    else
        row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
        row.Icon:SetTexture(data.icon or 134400);
    end

    local count = data.count or 0;
    row.Icon:SetDesaturated(count == 0);
    row.Name:SetText(data.name or "?");
    row.Count:SetText(count > 0 and count or "");
    row.Selected:SetShown(isSelected);
    row.Edge:Hide();
    row.Bg:Show();

    if (isSelected) then
        row.Name:SetTextColor(1, 0.82, 0);
    elseif (count == 0) then
        row.Name:SetTextColor(GRAY_FONT_COLOR:GetRGB());
    else
        row.Name:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
    end
end

function PickerView.Setup(frame)
    frame.pickerRows = {};

    local list = CreateFrame("Frame", nil, frame);
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP_MARGIN + PAD));
    list:SetWidth(LIST_WIDTH);
    frame.PickerList = list;


    -- The banner is the old list's entry frame: its name, art and teleport
    -- button (dungeons) or boss portrait (raids) work as they always did.
    frame.bannerPool = CreateFramePool("Frame", frame, "KeystoneLootEntryFrameTemplate");

    local grid = CreateFrame("Frame", nil, frame);
    frame.PickerGrid = grid;
    frame.itemPool = CreateFramePool("Button", grid, "KeystoneLootLootIconButtonTemplate");

    local empty = grid:CreateFontString(nil, "OVERLAY", "GameFontDisable");
    empty:SetPoint("TOP", grid, "TOP", 0, -24);
    empty:SetText("Nothing here matches the filters above.");
    empty:Hide();
    grid.Empty = empty;
end

-- The entry frame, made into a tall banner.
local function DressBanner(banner, width, noIcon)
    banner:SetSize(width, BANNER_HEIGHT);
    banner.IconScrollBox:Hide();
    banner.BackButton:Hide();
    banner.NextButton:Hide();
    banner.Divider:Hide();
    banner.Background:Hide();

    banner.DungeonBG:ClearAllPoints();
    banner.DungeonBG:SetPoint("TOPLEFT");
    banner.DungeonBG:SetPoint("BOTTOMRIGHT");
    banner.DungeonBG:SetAlpha(1);

    banner.TeleportButton:SetSize(44, 44);
    banner.TeleportButton:ClearAllPoints();
    banner.TeleportButton:SetPoint("LEFT", banner, "LEFT", 14, 0);
    if (banner.TeleportButton.IconBorder) then
        banner.TeleportButton.IconBorder:SetSize(76, 76);
    end

    -- Without the teleport the name and subtitle start at the banner edge.
    banner.TeleportButton:SetShown(not noIcon);
    local textLeft = noIcon and 16 or 70;

    banner.Text:ClearAllPoints();
    banner.Text:SetPoint("TOPLEFT", banner, "TOPLEFT", textLeft, -14);
    banner.Text:SetWidth(width - textLeft - 16);
    banner.Text:SetFontObject("GameFontNormalHuge");
    banner.Text:SetTextColor(1, 0.82, 0);

    if (not banner.Subtitle) then
        local sub = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
        sub:SetJustifyH("LEFT");
        banner.Subtitle = sub;
    end
    banner.Subtitle:ClearAllPoints();
    banner.Subtitle:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", textLeft, 16);
    banner.Subtitle:SetWidth(width - textLeft - 16);
end

function PickerView.Render(frame, view)
    frame.bannerPool:ReleaseAll();
    frame.itemPool:ReleaseAll();

    local width = view.width;
    frame:SetWidth(width);

    -- The list.
    local y = 0;
    for index, data in ipairs(view.rows) do
        local row = frame.pickerRows[index];
        if (not row) then
            row = CreateListRow(frame.PickerList);
            row:SetScript("OnClick", function(r)
                if (r.key ~= nil and frame.pickerOnSelect) then frame.pickerOnSelect(r.key); end
            end);
            frame.pickerRows[index] = row;
        end
        row.key = (not data.header) and data.key or nil;
        PaintRow(row, data, (not data.header) and data.key == view.selected);
        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", frame.PickerList, "TOPLEFT", 0, -y);
        row:SetPoint("TOPRIGHT", frame.PickerList, "TOPRIGHT", 0, -y);
        row:Show();
        y = y + (data.header and HEADER_ROW or LIST_ROW);
    end
    for index = #view.rows + 1, #frame.pickerRows do
        frame.pickerRows[index]:Hide();
    end
    frame.pickerOnSelect = view.onSelect;
    local listHeight = math.max(y, 1);
    frame.PickerList:SetHeight(listHeight);

    -- The banner.
    local rightLeft = PAD + LIST_WIDTH + PAD * 2;
    local rightWidth = width - rightLeft - PAD;
    local rightHeight = 0;

    if (view.banner) then
        local banner = frame.bannerPool:Acquire();
        banner:ClearAllPoints();
        banner:SetPoint("TOPLEFT", frame, "TOPLEFT", rightLeft, -(TOP_MARGIN + PAD));
        view.banner(banner);
        DressBanner(banner, rightWidth, view.noIcon);
        banner.Subtitle:SetText(view.subtitle or "");
        if ((not view.noIcon) and banner.TeleportButton.UpdateCooldown and banner.TeleportButton.teleportSpellId) then
            banner.TeleportButton:UpdateCooldown();
        end
        banner:Show();
        rightHeight = BANNER_HEIGHT + PAD * 1.5;
    end

    -- The items, wrapped into rows and centred under the banner.
    local items = view.items or {};
    local perRow = math.max(1, math.floor(rightWidth / CELL));
    local gridWidth = perRow * CELL;
    local grid = frame.PickerGrid;
    grid:ClearAllPoints();
    grid:SetPoint("TOPLEFT", frame, "TOPLEFT",
        rightLeft + math.floor((rightWidth - gridWidth) / 2), -(TOP_MARGIN + PAD + rightHeight));
    grid:SetWidth(gridWidth);

    for index, item in ipairs(items) do
        local button = frame.itemPool:Acquire();
        local col = (index - 1) % perRow;
        local line = math.floor((index - 1) / perRow);
        button:ClearAllPoints();
        button:SetPoint("TOPLEFT", grid, "TOPLEFT", col * CELL + 6, -line * CELL - 6);
        button:Init(item);
        button:Show();
    end

    local lines = math.ceil(#items / perRow);
    local gridHeight = math.max(lines * CELL + 8, 60);
    grid:SetHeight(gridHeight);
    grid.Empty:SetShown(#items == 0);
    rightHeight = math.max(rightHeight + gridHeight, MIN_DETAIL);

    frame:SetHeight(TOP_MARGIN + PAD + math.max(listHeight, rightHeight) + PAD + BOTTOM_MARGIN);
end

function PickerView.EachItemButton(frame, fn)
    if (not frame.itemPool) then return; end
    for button in frame.itemPool:EnumerateActive() do
        fn(button);
    end
end

function PickerView.UpdateTeleportCooldown(frame)
    if (not frame.bannerPool) then return; end
    for banner in frame.bannerPool:EnumerateActive() do
        if (banner.TeleportButton.teleportSpellId) then
            banner.TeleportButton:UpdateCooldown();
        end
    end
end
