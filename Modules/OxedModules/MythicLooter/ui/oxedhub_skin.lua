-- MythicLooter in OxedHub's own look: the stone backdrop and ornate border
-- the rest of the hub uses, in place of Blizzard's portrait frame.
--
-- Runs at READY, after every frame exists. Always ours, whatever UI addon is
-- loaded: the popups are guarded (Guard, below) so another addon's skin
-- cannot paint over them afterwards.
local AddonName, OxedHub = ...; local KeystoneLoot = OxedHub.MythicLooter;
local print = OxedHub.Print or print

local function NoShow() end

-- Hide a texture for good: the frame templates show their art again on
-- OnShow, so Show is replaced as well.
local function KillTexture(region)
    if (region and region.IsObjectType and region:IsObjectType("Texture")) then
        region:SetTexture(nil);
        region:SetAlpha(0);
        region:Hide();
        region.Show = NoShow;
    end
end

local function KillFrame(frame)
    if (not frame) then
        return;
    end
    frame:Hide();
    frame.Show = NoShow;
end

local function StripRegions(frame)
    if (not frame or not frame.GetRegions) then
        return;
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        KillTexture(region);
    end
end

-- The border sits on a child at the frame's own level: below the frame's
-- content (which lives a level higher), above nothing, since the frame's own
-- art is stripped.
local function AddShell(frame, title, alpha)
    local Panel = OxedHub.UIComponents and OxedHub.UIComponents.Panel;
    if (not frame or frame.oxedShell or not Panel) then
        return;
    end

    local shell = CreateFrame("Frame", nil, frame, "BackdropTemplate");
    shell:SetAllPoints(frame);
    shell:SetFrameLevel(frame:GetFrameLevel());
    shell:EnableMouse(false);
    Panel.ApplyOrnateFrame(shell, title, alpha or 0.96);
    frame.oxedShell = shell;
    return shell;
end

-- Keeps a frame as we left it. What it holds now is ours; a texture, child
-- frame or backdrop that turns up later is another addon's skin, and is
-- taken away each time the frame is shown (and once more a frame later, for
-- skins that wait a frame themselves).
local function Guard(frame, keepChildren)
    if (not frame or frame.oxedGuarded) then
        return;
    end
    frame.oxedGuarded = true;

    local ownRegions, ownChildren = {}, {};
    for _, region in ipairs({ frame:GetRegions() }) do ownRegions[region] = true; end
    for _, child in ipairs({ frame:GetChildren() }) do ownChildren[child] = true; end

    local function Sweep()
        for _, region in ipairs({ frame:GetRegions() }) do
            if (not ownRegions[region]) then
                KillTexture(region);
            end
        end
        for _, child in ipairs(keepChildren and {} or { frame:GetChildren() }) do
            if (not ownChildren[child]) then
                KillFrame(child);
            end
        end
        if (frame.backdropInfo and frame.ClearBackdrop) then
            pcall(frame.ClearBackdrop, frame);
        end
    end

    Sweep();
    frame:HookScript("OnShow", function()
        Sweep();
        C_Timer.After(0, Sweep);
    end);
end

local function RedButton(button)
    local Button = OxedHub.UIComponents and OxedHub.UIComponents.Button;
    if (button and Button and Button.ApplyRedStyle) then
        pcall(Button.ApplyRedStyle, button);
    end
end

local function SkinMainFrame(frame)
    local titleString = frame.GetTitleText and frame:GetTitleText();
    local title = titleString and titleString:GetText();

    StripRegions(frame);
    KillFrame(frame.NineSlice);
    KillFrame(frame.PortraitContainer);
    KillFrame(frame.TitleContainer);
    KillTexture(frame.Bg);
    KillTexture(frame.TopTileStreaks);

    local shell = AddShell(frame, title, 0.96);
    if (shell and shell.titleText) then
        -- SetTitle may be called again (the season name); follow it.
        if (frame.SetTitle) then
            hooksecurefunc(frame, "SetTitle", function(_, text)
                if (text) then shell.titleText:SetText(text); end
            end);
        end
    end

    if (frame.CloseButton) then
        frame.CloseButton:ClearAllPoints();
        frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3);
    end

    local dungeons = frame.DungeonsFrame;
    if (dungeons) then
        if (dungeons.BorderFrame) then
            StripRegions(dungeons.BorderFrame);
            KillFrame(dungeons.BorderFrame.NineSlice);
        end
    end
end

local function SkinSidePanel(panel)
    if (not panel) then
        return;
    end
    if (panel.Border) then
        StripRegions(panel.Border);
        KillFrame(panel.Border);
    end
    StripRegions(panel);
    AddShell(panel, nil, 0.94);
end


-- The gear becomes OxedHub's red "Options" button. The dropdown itself still
-- takes the click and opens the same menu; the button on top is only its
-- face, so it lets the mouse through.
local function OptionsButton(dropdown)
    if (not dropdown or dropdown.oxedOptions) then
        return;
    end
    StripRegions(dropdown);
    dropdown:SetSize(80, 22);
    dropdown:ClearAllPoints();
    dropdown:SetPoint("TOPRIGHT", dropdown:GetParent(), "TOPRIGHT", -32, -3);

    local face = CreateFrame("Button", nil, dropdown, "UIPanelButtonTemplate");
    face:SetAllPoints(dropdown);
    face:SetText(OPTIONS or "Options");
    face:EnableMouse(false);
    RedButton(face);
    dropdown.oxedOptions = face;

    dropdown:HookScript("OnEnter", function() face:LockHighlight(); end);
    dropdown:HookScript("OnLeave", function() face:UnlockHighlight(); end);
end

local function SkinPopup(frame)
    if (not frame) then
        return;
    end
    StripRegions(frame);
    KillFrame(frame.NineSlice);
    KillFrame(frame.Border);
    AddShell(frame, nil, 0.96);
end

-- "Group is full!" / "Group joined!": the whole card is the dungeon's
-- teleport, so it becomes one round button -- the dungeon's portrait in a
-- gold ring with a slow glow -- with the message above and the dungeon and
-- your role beneath, and no panel around it.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask";
local CIRCLE_SIZE = 64;
local POPUP_MIN_WIDTH = 200;

local function KeepOnly(frame, keep)
    for _, region in ipairs({ frame:GetRegions() }) do
        if (region:IsObjectType("Texture") and not keep[region]) then
            KillTexture(region);
        end
    end
end

local function SkinTeleportPopup(frame)
    local card = frame and frame.Card;
    if (not card or frame.oxedRound) then
        return;
    end
    frame.oxedRound = true;

    StripRegions(frame);
    KillFrame(frame.NineSlice);
    KillFrame(frame.Inset);
    KillTexture(frame.Bg);
    KillTexture(frame.HeadlineBg);
    if (frame.AddonLabel) then frame.AddonLabel:Hide(); end

    KeepOnly(card, { [card.Icon] = true, [card.RoleIcon] = true, [card.Error] = true });
    KillTexture(card.IconBorder);
    KillTexture(card.HighlightTexture);

    -- The message on top, the circle under it.
    frame.Title:ClearAllPoints();
    -- Inset on both sides by the close button's width, so the message stays
    -- centred over the circle and clear of the X.
    frame.Title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -8);
    frame.Title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -8);
    frame.Title:SetJustifyH("CENTER");
    frame.Title:SetFontObject("GameFontNormalLarge");
    frame.Title:SetShadowOffset(1, -1);

    card:ClearAllPoints();
    card:SetSize(CIRCLE_SIZE, CIRCLE_SIZE);
    card:SetPoint("TOP", frame, "TOP", 0, -36);

    card.Icon:ClearAllPoints();
    card.Icon:SetAllPoints(card);
    card.Icon:SetTexCoord(0, 1, 0, 1);
    local mask = card:CreateMaskTexture();
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE");
    mask:SetAllPoints(card.Icon);
    card.Icon:AddMaskTexture(mask);

    -- A soft gold glow behind the circle that breathes; it is a texture of
    -- its own, so the button's alpha is never animated.
    local glow = card:CreateTexture(nil, "BACKGROUND");
    glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64");
    glow:SetBlendMode("ADD");
    glow:SetVertexColor(1, 0.75, 0.2, 0.9);
    glow:SetPoint("CENTER", card, "CENTER");
    glow:SetSize(CIRCLE_SIZE * 1.9, CIRCLE_SIZE * 1.9);
    local pulse = glow:CreateAnimationGroup();
    pulse:SetLooping("BOUNCE");
    local fade = pulse:CreateAnimation("Alpha");
    fade:SetFromAlpha(0.35);
    fade:SetToAlpha(0.9);
    fade:SetDuration(1.2);
    fade:SetSmoothing("IN_OUT");
    card:HookScript("OnShow", function() pulse:Play(); end);
    frame:HookScript("OnShow", function() pulse:Play(); end);
    frame:HookScript("OnHide", function() pulse:Stop(); end);

    -- The rim: two discs cut from the same circle as the portrait, a gold one
    -- and a dark one just inside it, both centred on the button. Ring art
    -- from the game is never quite centred on its own middle, and the
    -- portrait sat off to one side inside it.
    local rim = card:CreateTexture(nil, "BORDER", nil, 1);
    rim:SetTexture(CIRCLE_MASK);
    rim:SetVertexColor(1, 0.78, 0.22, 1);
    rim:SetPoint("CENTER", card, "CENTER");
    rim:SetSize(CIRCLE_SIZE + 8, CIRCLE_SIZE + 8);

    local gap = card:CreateTexture(nil, "BORDER", nil, 2);
    gap:SetTexture(CIRCLE_MASK);
    gap:SetVertexColor(0.05, 0.04, 0.03, 1);
    gap:SetPoint("CENTER", card, "CENTER");
    gap:SetSize(CIRCLE_SIZE + 3, CIRCLE_SIZE + 3);

    local hover = card:CreateTexture(nil, "OVERLAY", nil, 2);
    hover:SetTexture(CIRCLE_MASK);
    hover:SetBlendMode("ADD");
    hover:SetVertexColor(1, 1, 1, 0.25);
    hover:SetAllPoints(card.Icon);
    hover:Hide();
    card.HighlightTexture = hover;

    if (card.Cooldown) then
        card.Cooldown:ClearAllPoints();
        card.Cooldown:SetAllPoints(card.Icon);
        pcall(card.Cooldown.SetSwipeTexture, card.Cooldown, CIRCLE_MASK);
        pcall(card.Cooldown.SetUseCircularEdge, card.Cooldown, true);
    end

    if (card.Error) then
        card.Error:ClearAllPoints();
        -- On the rim at five o'clock, clear of the portrait's middle.
        card.Error:SetPoint("CENTER", card, "CENTER", CIRCLE_SIZE * 0.36, -CIRCLE_SIZE * 0.36);
        card.Error:SetSize(18, 18);
    end

    -- Dungeon name and role under the circle.
    card.DungeonName:ClearAllPoints();
    card.DungeonName:SetPoint("TOP", card, "BOTTOM", 0, -10);
    card.DungeonName:SetJustifyH("CENTER");
    card.DungeonName:SetShadowOffset(1, -1);

    card.RoleText:ClearAllPoints();
    card.RoleText:SetPoint("TOP", card.DungeonName, "BOTTOM", 9, -4);
    card.RoleText:SetJustifyH("LEFT");
    card.RoleIcon:ClearAllPoints();
    card.RoleIcon:SetPoint("RIGHT", card.RoleText, "LEFT", -2, 0);

    if (frame.CloseButton) then
        frame.CloseButton:ClearAllPoints();
        -- In the frame's corner, away from the circle and the message.
        frame.CloseButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0);
        frame.CloseButton:SetScale(0.75);
        frame.CloseButton:SetAlpha(0.8);
    end

    frame:SetHeight(36 + CIRCLE_SIZE + 52);

    -- Open sizes the old card to the dungeon name; follow it, but never
    -- narrower than the message.
    if (frame.Open) then
        hooksecurefunc(frame, "Open", function(self)
            local w = math.max(POPUP_MIN_WIDTH, card.DungeonName:GetStringWidth() + 40,
                self.Title:GetStringWidth() + 56,
                self.TeleportHint and self.TeleportHint:IsShown() and self.TeleportHint:GetStringWidth() + 40 or 0);
            -- With the group's details under the circle, keep the width Open
            -- gave them, or the description wraps into a narrow column.
            if (self.hasDetails) then
                w = math.max(w, self:GetWidth());
            end
            self:SetWidth(w);
        end);
    end
end

local function Apply()
    if (not OxMythicLooterFrame) then
        return;
    end

    local ok, err = pcall(function()
        SkinMainFrame(OxMythicLooterFrame);
        -- The Catalyst and custom-item strips beside the window are gone:
        -- OxedHub has no panels hanging off a window like that.
        KillFrame(OxMythicLooterFrame.CatalystFrame);
        KillFrame(OxMythicLooterFrame.CustomItemFrame);
        OptionsButton(OxMythicLooterFrame.SettingsDropdown);
        SkinPopup(OxMythicLooterReminderFrame);
        SkinPopup(OxMythicLooterDropNotificationFrame);
        SkinTeleportPopup(OxMythicLooterMythicPlusNotificationFrame);

        for _, button in ipairs({ OxMythicLooterReminderFrame and OxMythicLooterReminderFrame.LootSpecButton }) do
            RedButton(button);
        end

        Guard(OxMythicLooterReminderFrame);
        -- Its item rows are child frames made as loot comes in; keep those.
        Guard(OxMythicLooterDropNotificationFrame, true);
        local teleport = OxMythicLooterMythicPlusNotificationFrame;
        if (teleport) then
            Guard(teleport);
            Guard(teleport.Card);
            Guard(teleport.CloseButton);
        end
    end);
    if (not ok and OxedHub.debug) then
        print("|cffffcc00[OxedHub]|r MythicLooter skin: " .. tostring(err));
    end
end

KeystoneLoot.API:RegisterCallback("READY", Apply, "OxedHubSkin");
