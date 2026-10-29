-- MythicLooter's This Week tab: the player's own Mythic+ week on one page.
-- Their keystone (the icon teleports there), this week's affixes, the
-- season rating with the best run in each dungeon, and how far each row of
-- the Great Vault has got.
--
-- ⚠ The keystone icon casts its teleport through a secure button, whose
-- spell can only be set out of combat. In combat the page keeps what it
-- showed and is brought up to date when the fight ends, like the Keys tab.
-- ⚠ Inside a key the game can hand back secrets: every number goes through
-- Number(), which treats a secret as "not known".
local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter;

local WeekTab = {};
KeystoneLoot.WeekTab = WeekTab;

local MAX_AFFIXES = 5;
local MAX_DUNGEONS = 10;
local DUNGEON_ROW = 22;
local VAULT_ROW = 28;
local LABEL_W = 110;          -- the vault row's name, left of its three slots

-- The Great Vault's rows, by their Enum.WeeklyRewardChestThresholdType name.
local VAULT_ROWS = {
    { kind = "Raid",       label = RAID or "Raid" },
    { kind = "Activities", label = DUNGEONS or "Dungeons" },
    { kind = "World",      label = WORLD or "World" },
};

local function T(text)
    return OxedHub.T and OxedHub.T(text) or text;
end

local function Number(value)
    if (issecretvalue and issecretvalue(value)) then return nil; end
    return type(value) == "number" and value or nil;
end

local function Text(parent, font, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", font);
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    fs:SetJustifyH("LEFT");
    return fs;
end

-- A rating's colour, the one the game's own Mythic+ panel uses.
local function ScoreHex(score, oneDungeon)
    local CM = C_ChallengeMode;
    local fn = CM and (oneDungeon and CM.GetSpecificDungeonOverallScoreRarityColor or CM.GetDungeonScoreRarityColor);
    if (fn and score) then
        local ok, colour = pcall(fn, score);
        if (ok and colour and colour.GenerateHexColor) then return colour:GenerateHexColor(); end
    end
    return "ffffffff";
end

-- The season's teleport for a dungeon, from MythicLooter's own list.
local function PortFor(mapID)
    for _, dungeon in ipairs(KeystoneLoot.DungeonDatabase or {}) do
        if (dungeon.challengeModeId == mapID) then
            local port = dungeon.teleportSpellId;
            if (type(port) == "function") then
                local ok, id = pcall(port);
                port = ok and id or nil;
            end
            return type(port) == "number" and port or nil;
        end
    end
end

-- ── What the game knows ────────────────────────────────────────────────────

local function OwnKeystone()
    if (not C_MythicPlus) then return nil; end
    local okMap, mapID = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID);
    local okLevel, level = pcall(C_MythicPlus.GetOwnedKeystoneLevel);
    mapID = okMap and Number(mapID);
    if (not mapID or mapID == 0) then return nil; end
    local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID);
    return { mapID = mapID, level = okLevel and Number(level) or 0, name = name, texture = texture };
end

local function Affixes()
    local out = {};
    if (not (C_MythicPlus and C_MythicPlus.GetCurrentAffixes)) then return out; end
    local ok, list = pcall(C_MythicPlus.GetCurrentAffixes);
    if (not ok or type(list) ~= "table") then return out; end
    for _, affix in ipairs(list) do
        local id = Number(affix.id);
        if (id) then
            local okInfo, name, desc, icon = pcall(C_ChallengeMode.GetAffixInfo, id);
            if (okInfo and name) then
                out[#out + 1] = { name = name, desc = desc, icon = icon };
            end
        end
    end
    return out;
end

-- The season's rating, and each dungeon's best run by its map id.
local function SeasonRuns()
    local runs, total = {}, nil;
    if (C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary) then
        local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player");
        if (ok and type(summary) == "table") then
            total = Number(summary.currentSeasonScore);
            for _, run in ipairs(summary.runs or {}) do
                local id = Number(run.challengeModeID);
                if (id) then
                    local timed = run.finishedSuccess;
                    if (issecretvalue and issecretvalue(timed)) then timed = nil; end
                    runs[id] = { score = Number(run.mapScore), level = Number(run.bestRunLevel), timed = timed == true };
                end
            end
        end
    end
    if (not total and C_ChallengeMode.GetOverallDungeonScore) then
        local ok, score = pcall(C_ChallengeMode.GetOverallDungeonScore);
        if (ok) then total = Number(score); end
    end
    return runs, total;
end

local function SeasonMaps()
    local maps = {};
    local ok, ids = pcall(C_ChallengeMode.GetMapTable);
    if (not ok or type(ids) ~= "table") then return maps; end
    for _, id in ipairs(ids) do
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(id);
        maps[#maps + 1] = { id = id, name = name or "?", texture = texture };
    end
    table.sort(maps, function(a, b) return a.name < b.name; end);
    return maps;
end

local function VaultSlots(kind)
    local types = Enum and Enum.WeeklyRewardChestThresholdType;
    local enum = types and types[kind];
    if (not enum or not (C_WeeklyRewards and C_WeeklyRewards.GetActivities)) then return nil; end
    local ok, list = pcall(C_WeeklyRewards.GetActivities, enum);
    if (not ok or type(list) ~= "table" or #list == 0) then return nil; end
    local slots = {};
    for _, activity in ipairs(list) do
        slots[#slots + 1] = {
            id = activity.id,
            progress = Number(activity.progress) or 0,
            threshold = Number(activity.threshold) or 0,
            level = Number(activity.level) or 0,
        };
    end
    table.sort(slots, function(a, b) return a.threshold < b.threshold; end);
    return slots;
end

-- The item level a finished slot offers: the game's example reward first,
-- MythicLooter's own table for a dungeon slot when that is not loaded yet.
local function SlotItemLevel(kind, slot)
    if (slot.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks and C_Item and C_Item.GetDetailedItemLevelInfo) then
        local ok, link = pcall(C_WeeklyRewards.GetExampleRewardItemHyperlinks, slot.id);
        if (ok and type(link) == "string") then
            local okLevel, ilvl = pcall(C_Item.GetDetailedItemLevelInfo, link);
            ilvl = okLevel and Number(ilvl);
            if (ilvl and ilvl > 0) then return ilvl; end
        end
    end
    if (kind == "Activities" and KeystoneLoot.Keystone and slot.level >= 2) then
        local ok, rewards = pcall(KeystoneLoot.Keystone.GetRewards, KeystoneLoot.Keystone, slot.level);
        if (ok and rewards and rewards.greatVault) then return rewards.greatVault.level; end
    end
end

-- What a finished slot was earned with: the key level, the raid difficulty,
-- or the delve tier.
local function SlotWhat(kind, slot)
    if (kind == "Activities") then
        return slot.level >= 2 and ("+" .. slot.level) or "";
    elseif (kind == "Raid") then
        local ok, name = pcall(GetDifficultyInfo, slot.level);
        return ok and name or "";
    end
    return slot.level > 0 and (T("Tier %d")):format(slot.level) or "";
end

-- ── The page ───────────────────────────────────────────────────────────────

local dirty = false;

local function BuildKeystone(frame)
    local btn = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate");
    btn:SetSize(52, 52);
    btn:RegisterForClicks("AnyUp", "AnyDown");
    btn:SetAttribute("type", "spell");
    btn.icon = btn:CreateTexture(nil, "ARTWORK");
    btn.icon:SetAllPoints();
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    local hl = btn:CreateTexture(nil, "HIGHLIGHT");
    hl:SetAllPoints();
    hl:SetColorTexture(1, 1, 1, 0.2);
    btn.level = btn:CreateFontString(nil, "OVERLAY");
    btn.level:SetFont(STANDARD_TEXT_FONT, 18, "OUTLINE");
    btn.level:SetPoint("CENTER");
    btn:SetScript("OnEnter", function(self)
        local id = self:GetAttribute("spell");
        if (not id) then return; end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetSpellByID(id);
        GameTooltip:AddLine("|cffffd100" .. T("Click to teleport") .. "|r");
        GameTooltip:Show();
    end);
    btn:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    frame.key = btn;

    frame.keyName = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
    frame.keyName:SetPoint("TOPLEFT", btn, "TOPRIGHT", 10, -6);
    frame.keyName:SetJustifyH("LEFT");
    frame.keyName:SetWordWrap(false);
    -- What the key gives, one line each: on one line the vault's half was cut off.
    frame.keyEnd = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.keyEnd:SetPoint("TOPLEFT", frame.keyName, "BOTTOMLEFT", 0, -5);
    frame.keyEnd:SetJustifyH("LEFT");
    frame.keyEnd:SetWordWrap(false);
    frame.keyEnd:SetTextColor(0.8, 0.8, 0.8);
    frame.keyVault = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.keyVault:SetPoint("TOPLEFT", frame.keyEnd, "BOTTOMLEFT", 0, -3);
    frame.keyVault:SetJustifyH("LEFT");
    frame.keyVault:SetWordWrap(false);
    frame.keyVault:SetTextColor(0.8, 0.8, 0.8);
end

local function AffixIcon(frame, i)
    local icon = frame.affixes[i];
    if (icon) then return icon; end
    icon = CreateFrame("Frame", nil, frame);
    icon:SetSize(40, 40);
    icon.tex = icon:CreateTexture(nil, "ARTWORK");
    icon.tex:SetAllPoints();
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    icon:SetScript("OnEnter", function(self)
        if (not self.name) then return; end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText(self.name);
        if (self.desc) then GameTooltip:AddLine(self.desc, 1, 1, 1, true); end
        GameTooltip:Show();
    end);
    icon:SetScript("OnLeave", function() GameTooltip:Hide(); end);
    frame.affixes[i] = icon;
    return icon;
end

local function DungeonRow(frame, i)
    local row = frame.dungeons[i];
    if (row) then return row; end
    row = CreateFrame("Frame", nil, frame);
    row:SetHeight(DUNGEON_ROW - 2);
    local bg = row:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints();
    bg:SetColorTexture(0, 0, 0, i % 2 == 1 and 0.35 or 0.2);
    row.icon = row:CreateTexture(nil, "ARTWORK");
    row.icon:SetSize(18, 18);
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0);
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    row.score:SetPoint("RIGHT", row, "RIGHT", -6, 0);
    row.score:SetWidth(50);
    row.score:SetJustifyH("RIGHT");
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    row.level:SetPoint("RIGHT", row.score, "LEFT", -8, 0);
    row.level:SetWidth(40);
    row.level:SetJustifyH("RIGHT");
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0);
    row.name:SetPoint("RIGHT", row.level, "LEFT", -6, 0);
    row.name:SetJustifyH("LEFT");
    row.name:SetWordWrap(false);
    frame.dungeons[i] = row;
    return row;
end

local function VaultCell(frame, r, c)
    frame.vault[r] = frame.vault[r] or {};
    local cell = frame.vault[r][c];
    if (cell) then return cell; end
    cell = CreateFrame("Frame", nil, frame);
    cell:SetHeight(VAULT_ROW - 4);
    local bg = cell:CreateTexture(nil, "BACKGROUND");
    bg:SetAllPoints();
    bg:SetColorTexture(0, 0, 0, 0.4);
    cell.fill = cell:CreateTexture(nil, "BORDER");
    cell.fill:SetPoint("TOPLEFT");
    cell.fill:SetPoint("BOTTOMLEFT");
    cell.fill:SetColorTexture(1, 0.82, 0, 0.25);
    local edge = cell:CreateTexture(nil, "ARTWORK");
    edge:SetPoint("BOTTOMLEFT"); edge:SetPoint("BOTTOMRIGHT");
    edge:SetHeight(1);
    edge:SetColorTexture(1, 0.82, 0, 0.35);
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    cell.text:SetPoint("CENTER");
    frame.vault[r][c] = cell;
    return cell;
end

local function Render(frame)
    if (not frame:IsVisible()) then return; end
    if (InCombatLockdown()) then
        dirty = true;
        return;
    end
    dirty = false;

    local w = frame:GetWidth();
    local colW = math.floor((w - 52 - 24) / 2);
    local rightX = 26 + colW + 24;

    -- Weekly reset.
    local seconds;
    if (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset) then
        local ok, value = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset);
        seconds = ok and Number(value);
    end
    if (seconds and SecondsToTime) then
        frame.reset:SetText((T("Weekly reset in %s")):format(SecondsToTime(seconds, true)));
    else
        frame.reset:SetText("");
    end

    -- Your keystone.
    local key = OwnKeystone();
    frame.key:ClearAllPoints();
    frame.key:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, -112);
    frame.keyName:SetWidth(colW - 62);
    frame.keyEnd:SetWidth(colW - 62);
    frame.keyVault:SetWidth(colW - 62);
    frame.keyEnd:SetText("");
    frame.keyVault:SetText("");
    if (key) then
        frame.key.icon:SetTexture(key.texture or "Interface\\Icons\\INV_Relics_Hourglass");
        frame.key.icon:SetDesaturated(false);
        frame.key.level:SetText("+" .. key.level);
        frame.key:SetAttribute("spell", PortFor(key.mapID));
        frame.keyName:SetText(key.name or "Mythic+");
        local rewards = KeystoneLoot.Keystone and KeystoneLoot.Keystone:GetRewards(key.level);
        if (rewards) then
            frame.keyEnd:SetText((T("End of run: %d (%s)")):format(rewards.endOfRun.level, rewards.endOfRun.rank));
            frame.keyVault:SetText((T("Great Vault: %d (%s)")):format(rewards.greatVault.level, rewards.greatVault.rank));
        end
    else
        frame.key.icon:SetTexture("Interface\\Icons\\INV_Relics_Hourglass");
        frame.key.icon:SetDesaturated(true);
        frame.key.level:SetText("");
        frame.key:SetAttribute("spell", nil);
        frame.keyName:SetText(T("No keystone in your bags"));
    end

    -- This week's affixes.
    local affixes = Affixes();
    local names = {};
    for i = 1, MAX_AFFIXES do
        local affix = affixes[i];
        if (affix) then
            local icon = AffixIcon(frame, i);
            icon:ClearAllPoints();
            icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 26 + (i - 1) * 46, -206);
            icon.tex:SetTexture(affix.icon);
            icon.name, icon.desc = affix.name, affix.desc;
            icon:Show();
            names[#names + 1] = affix.name;
        elseif (frame.affixes[i]) then
            frame.affixes[i]:Hide();
        end
    end
    frame.affixNames:SetWidth(colW);
    frame.affixNames:SetText(#names > 0 and table.concat(names, ", ") or T("Not known yet. Open the game's Mythic+ panel once."));

    -- Rating, and the best run in each dungeon.
    local runs, total = SeasonRuns();
    frame.ratingTitle:ClearAllPoints();
    frame.ratingTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", rightX, -86);
    frame.rating:SetText(total and ("|c%s%d|r"):format(ScoreHex(total), total) or "");
    local maps = SeasonMaps();
    for i = 1, MAX_DUNGEONS do
        local map = maps[i];
        if (map) then
            local row = DungeonRow(frame, i);
            local y = -112 - (i - 1) * DUNGEON_ROW;
            row:ClearAllPoints();
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", rightX, y);
            row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, y);
            row.icon:SetTexture(map.texture or "Interface\\Icons\\INV_Relics_Hourglass");
            row.name:SetText(map.name);
            local run = runs[map.id];
            if (run and run.level and run.level > 0) then
                row.level:SetText((run.timed and "|cffffffff+%d|r" or "|cff808080+%d|r"):format(run.level));
                row.score:SetText(run.score and ("|c%s%d|r"):format(ScoreHex(run.score, true), run.score) or "");
            else
                row.level:SetText("|cff808080-|r");
                row.score:SetText("");
            end
            row:Show();
        elseif (frame.dungeons[i]) then
            frame.dungeons[i]:Hide();
        end
    end

    -- Great Vault: three slots a row, filled as far as each has got.
    -- Under whichever column ends lower: the dungeon list, or the affix names.
    local rightBottom = -112 - math.min(math.max(#maps, 4), MAX_DUNGEONS) * DUNGEON_ROW;
    local leftBottom = -252 - math.ceil(frame.affixNames:GetStringHeight() or 0);
    local top = math.min(rightBottom, leftBottom) - 16;
    frame.vaultTitle:ClearAllPoints();
    frame.vaultTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, top);
    local ready = false;
    if (C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards) then
        local ok, value = pcall(C_WeeklyRewards.HasAvailableRewards);
        ready = ok and not (issecretvalue and issecretvalue(value)) and value == true;
    end
    frame.vaultReady:SetShown(ready);
    local cellW = math.floor((w - 52 - LABEL_W - 16) / 3);
    for r, def in ipairs(VAULT_ROWS) do
        local y = top - 26 - (r - 1) * VAULT_ROW;
        local label = frame.vaultLabels[r];
        if (not label) then
            label = Text(frame, "GameFontNormal", 26, y);
            frame.vaultLabels[r] = label;
        end
        label:ClearAllPoints();
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 26, y - 6);
        label:SetText(def.label);
        local slots = VaultSlots(def.kind);
        label:SetShown(slots ~= nil);
        for c = 1, 3 do
            local cell = VaultCell(frame, r, c);
            local slot = slots and slots[c];
            if (slot) then
                cell:ClearAllPoints();
                cell:SetPoint("TOPLEFT", frame, "TOPLEFT", 26 + LABEL_W + (c - 1) * (cellW + 8), y);
                cell:SetWidth(cellW);
                local share = slot.threshold > 0 and math.min(1, slot.progress / slot.threshold) or 0;
                cell.fill:SetWidth(math.max(0.01, cellW * share));
                if (slot.threshold > 0 and slot.progress >= slot.threshold) then
                    local what, ilvl = SlotWhat(def.kind, slot), SlotItemLevel(def.kind, slot);
                    if (ilvl) then
                        cell.text:SetText(("|cff40ff40%s|r %s"):format(what, (T("item level %d")):format(ilvl)));
                    else
                        cell.text:SetText(("|cff40ff40%s|r"):format(what ~= "" and what or T("Unlocked")));
                    end
                else
                    cell.text:SetText(("|cffa0a0a0%d / %d|r"):format(slot.progress, slot.threshold));
                end
                cell:Show();
            else
                cell:Hide();
            end
        end
    end

    -- ⚠ The Dungeons tab, whose size this one takes, is shorter than this
    -- page: the vault's last row sat under the window's tabs. The window
    -- grows to fit while this tab is open (see RefreshSize).
    local needed = -(top - 26 - (#VAULT_ROWS - 1) * VAULT_ROW) + VAULT_ROW + 24;
    if (needed ~= frame.neededHeight) then
        frame.neededHeight = needed;
        local owner = frame:GetParent();
        -- Shown means this tab is the open one.
        if (owner and owner.weekTabId and owner.RefreshSize and frame:IsShown()) then
            owner:RefreshSize(owner.weekTabId);
        end
    end
end

-- Builds the tab's frame, the size of the Dungeons tab.
function WeekTab.Create(owner, sizeLike)
    local frame = CreateFrame("Frame", nil, owner);
    local w, h = 0, 0;
    if (sizeLike and sizeLike.GetSize) then w, h = sizeLike:GetSize(); end
    if (not w or w < 300) then w = 780; end
    if (not h or h < 300) then h = 480; end
    frame:SetSize(w, h);
    frame:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0);
    frame.affixes, frame.dungeons, frame.vault, frame.vaultLabels = {}, {}, {}, {};
    frame.neededHeight = 440;  -- until the first Render measures it

    frame.title = Text(frame, "GameFontNormalHuge", 26, -46);
    frame.title:SetText(T("This Week"));
    frame.reset = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.reset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -52);

    Text(frame, "GameFontNormalLarge", 26, -86):SetText(T("Your keystone"));
    BuildKeystone(frame);
    Text(frame, "GameFontNormalLarge", 26, -180):SetText(T("Affixes"));
    frame.affixNames = Text(frame, "GameFontHighlightSmall", 26, -252);
    frame.affixNames:SetTextColor(0.8, 0.8, 0.8);

    frame.ratingTitle = Text(frame, "GameFontNormalLarge", 0, -86);
    frame.ratingTitle:SetText(T("Rating"));
    frame.rating = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
    frame.rating:SetPoint("LEFT", frame.ratingTitle, "RIGHT", 10, 0);

    frame.vaultTitle = Text(frame, "GameFontNormalLarge", 26, -300);
    frame.vaultTitle:SetText(KeystoneLoot.L and KeystoneLoot.L["Great Vault"] or "Great Vault");
    frame.vaultReady = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    frame.vaultReady:SetPoint("LEFT", frame.vaultTitle, "RIGHT", 12, 0);
    frame.vaultReady:SetText("|cff40ff40" .. T("Rewards are waiting in your vault.") .. "|r");
    frame.vaultReady:Hide();

    -- Only while the page is open: the week changes rarely, and nothing is
    -- read for a page nobody is looking at.
    local events = CreateFrame("Frame");
    events:SetScript("OnEvent", function(_, event)
        if (event == "PLAYER_REGEN_ENABLED" and not dirty) then return; end
        Render(frame);
    end);
    frame:SetScript("OnShow", function(self)
        for _, event in ipairs({ "MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", "CHALLENGE_MODE_MAPS_UPDATE",
            "CHALLENGE_MODE_COMPLETED", "WEEKLY_REWARDS_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do
            pcall(events.RegisterEvent, events, event);
        end
        -- Asks the server for what may not have arrived yet; the events above
        -- draw the page again when it does.
        if (C_MythicPlus) then
            if (C_MythicPlus.RequestMapInfo) then pcall(C_MythicPlus.RequestMapInfo); end
            if (C_MythicPlus.RequestCurrentAffixes) then pcall(C_MythicPlus.RequestCurrentAffixes); end
            if (C_MythicPlus.RequestRewards) then pcall(C_MythicPlus.RequestRewards); end
        end
        Render(self);
    end);
    frame:SetScript("OnHide", function() events:UnregisterAllEvents(); end);

    frame:Hide();
    return frame;
end
