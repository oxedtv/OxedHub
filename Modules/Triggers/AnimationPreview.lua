local addonName, OxedHub = ...
local L = OxedHub.L

-- ── Animation Preview ────────────────────────────────────────────────────────
-- Every trigger's animation laid out on screen at once, labelled, draggable.
--
-- Placing animations used to be a one-at-a-time errand: open a trigger, open its
-- actions, hit Set Position, drag, save, close, repeat. Nothing ever showed the
-- arrangement as a whole, so overlaps were only discovered when two of them
-- fired together in combat.
--
-- This is a view over the same saved fields the per-trigger position frame
-- writes, not a second copy of them -- a tile dragged here is the same move as
-- dragging it in that dialog.

local AnimationPreview = {}
OxedHub.AnimationPreview = AnimationPreview

local UIParent = UIParent
local CreateFrame = CreateFrame
local C_Timer = C_Timer

local TILE_MIN = 48

-- ── Reading where an animation actually plays ────────────────────────────────

-- Resolve one animation's on-screen position the way the player will see it.
--
-- Three layers, most specific first: the trigger's own override, then the
-- animation's own custom spot, then the profile-wide default. Getting this
-- order wrong would show tiles somewhere the animation never appears, which is
-- worse than showing nothing.
local function ResolvePosition(actions, key, anim)
    if actions[key .. "UseCustomPosition"] and actions[key .. "PositionX"] then
        return actions[key .. "PositionX"], actions[key .. "PositionY"] or 0, "trigger"
    end
    if anim and anim.useCustomPosition then
        return anim.customPositionX or 0, anim.customPositionY or 200, "animation"
    end
    local Animations = OxedHub.Animations
    if Animations and Animations.GetSavedAnimationPosition then
        local x, y = Animations:GetSavedAnimationPosition()
        return x or 0, y or 200, "default"
    end
    return 0, 200, "default"
end

local function ResolveSize(actions, key, anim)
    local w = actions[key .. "DisplayWidth"]
    local h = actions[key .. "DisplayHeight"]
    if w and h then return w, h end

    local srcW = (anim and anim.width) or 64
    local srcH = (anim and anim.height) or 64
    local scale = (anim and anim.isBuiltIn) and (128 / srcW) or 3
    return srcW * scale, srcH * scale
end

-- The sound that belongs with an animation slot.
--
-- The two always come in named pairs -- "animation"/"sound", and for the
-- multi-slot rules "redAnimation"/"redSound", "moveAnimation"/"moveSound".
--
-- Returns nothing when the derived key is not a slot the trigger actually has.
-- Writing one anyway would let the player pick a sound that nothing ever reads,
-- which looks exactly like a bug that swallowed their choice.
local function SoundKeyFor(actions, animKey)
    if animKey == "animation" then return "sound" end
    local prefix = animKey:match("^(.*)Animation$") or animKey:match("^(.*)Anim$")
    if not prefix then return nil end
    local key = prefix .. "Sound"
    if actions[key] ~= nil then return key end
    return nil
end

-- Fit an id into a button barely wider than an icon. The full value is always
-- one hover away, so cutting the middle out costs nothing here.
local function ShortLabel(value, limit)
    if not value or value == "" or value == "None" then return "--" end
    value = tostring(value):gsub("^oxedhub_", ""):gsub("^oxed_anim_", "")
    limit = limit or 14
    if #value <= limit then return value end
    return value:sub(1, limit - 2) .. ".."
end

-- What makes this rule fire, in a few words.
--
-- The name alone is often useless here: half of them are auto-named after the
-- event ("Spell Cast Success" four times over) and the hand-typed ones say
-- things like "run". Naming the event and the spell is what lets a tile be
-- matched to a rule without opening anything.
local function DescribeSource(trigger)
    local Triggers = OxedHub.Triggers
    local label = (Triggers and Triggers.GetEventLabel and Triggers:GetEventLabel(trigger.event))
        or trigger.event or "?"

    local conditions = trigger.conditions or {}
    local spellID = tonumber(conditions.spellID or conditions.spellId)
    if spellID then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        if info and info.name then
            return label .. " - " .. info.name
        end
        return label .. " - " .. spellID
    end

    if conditions.auraName and conditions.auraName ~= "" then
        return label .. " - " .. conditions.auraName
    end
    return label
end

-- Every animation referenced by every enabled trigger.
--
-- Keys are discovered rather than hardcoded: a trigger's animation normally
-- lives under "animation", but mount and idle rules keep theirs under their own
-- prefixes. Anything whose value names a real animation counts, which keeps this
-- correct for action kinds added later without touching this file.
function AnimationPreview:Collect()
    local profile = OxedHub.db and OxedHub.db.profile
    local triggers = profile and profile.triggers
    local animations = profile and profile.animations
    if type(triggers) ~= "table" or type(animations) ~= "table" then return {} end

    local entries = {}
    for id, trigger in pairs(triggers) do
        local actions = trigger.actions
        if trigger.enabled and type(actions) == "table" then
            for key, value in pairs(actions) do
                local anim = (type(value) == "string") and animations[value] or nil
                if anim then
                    local x, y, source = ResolvePosition(actions, key, anim)
                    local w, h = ResolveSize(actions, key, anim)
                    table.insert(entries, {
                        triggerId = id,
                        trigger = trigger,
                        key = key,
                        soundKey = SoundKeyFor(actions, key),
                        source_desc = DescribeSource(trigger),
                        animId = value,
                        anim = anim,
                        x = x, y = y,
                        source = source,
                        width = math.max(TILE_MIN, w),
                        height = math.max(TILE_MIN, h),
                    })
                end
            end
        end
    end

    table.sort(entries, function(a, b)
        local an, bn = a.trigger.name or "", b.trigger.name or ""
        if an == bn then return a.key < b.key end
        return an < bn
    end)
    return entries
end

-- ── Tiles ────────────────────────────────────────────────────────────────────

local function StopTileAnimation(tile)
    if tile.ticker then
        tile.ticker:Cancel()
        tile.ticker = nil
    end
end

-- Drive one tile's spritesheet. Same frame maths the position dialog uses;
-- kept here rather than shared because that one drives a single frame it owns,
-- and this drives many it does not.
local function PlayTile(tile, animate)
    StopTileAnimation(tile)

    local anim = tile.entry and tile.entry.anim
    if not anim or not anim.tgaPath then
        tile.art:Hide()
        return
    end

    tile.art:SetTexture(anim.tgaPath)
    tile.art:Show()

    local cols = anim.columns or math.ceil(math.sqrt(anim.frameCount or 1))
    local rows = anim.rows or cols
    if cols < 1 then cols = 1 end
    if rows < 1 then rows = 1 end

    local sequence = anim.playSequence
    local frameCount = (sequence and #sequence > 0) and #sequence or (anim.frameCount or (cols * rows))
    if frameCount < 1 then frameCount = 1 end

    local function ShowStep(step)
        local frameNum = step
        if sequence and #sequence > 0 then frameNum = sequence[step + 1] or step end
        local row = math.floor(frameNum / cols)
        local col = frameNum % cols
        tile.art:SetTexCoord(col / cols, (col + 1) / cols, row / rows, (row + 1) / rows)
    end

    ShowStep(0)
    -- Still by default. A screen of everything the player owns all looping at
    -- once is unreadable, and the job here is placement, not playback.
    if not animate then return end

    local fps = anim.fps or 24
    if fps < 1 then fps = 24 end
    local step = 0
    tile.ticker = C_Timer.NewTicker(1 / fps, function()
        step = (step + 1) % frameCount
        ShowStep(step)
    end)
end

function AnimationPreview:CreateTile(index)
    self.tiles = self.tiles or {}
    if self.tiles[index] then return self.tiles[index] end

    local tile = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    tile:SetFrameStrata("HIGH")
    tile:SetFrameLevel(100 + index)
    tile:SetMovable(true)
    tile:EnableMouse(true)
    tile:RegisterForDrag("LeftButton")
    tile:SetClampedToScreen(true)

    tile:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tile:SetBackdropColor(0, 0, 0, 0.35)
    tile:SetBackdropBorderColor(1, 0.82, 0, 0.6)

    tile.art = tile:CreateTexture(nil, "ARTWORK")
    tile.art:SetPoint("TOPLEFT", tile, "TOPLEFT", 2, -2)
    tile.art:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -2, 2)

    -- The label is what makes this worth having: a screen of unnamed sprites
    -- tells you nothing about which rule to go and edit.
    -- Two lines: the rule's name, and what actually makes it fire. Each gets
    -- its own backing plate, because they are different widths and one plate
    -- stretched across both would be cut to the narrower of the two.
    tile.subLabel = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.subLabel:SetPoint("BOTTOM", tile, "TOP", 0, 2)
    tile.subLabel:SetJustifyH("CENTER")

    tile.subLabelBg = tile:CreateTexture(nil, "BACKGROUND")
    tile.subLabelBg:SetPoint("TOPLEFT", tile.subLabel, "TOPLEFT", -4, 1)
    tile.subLabelBg:SetPoint("BOTTOMRIGHT", tile.subLabel, "BOTTOMRIGHT", 4, -1)
    tile.subLabelBg:SetColorTexture(0, 0, 0, 0.7)

    tile.label = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.label:SetPoint("BOTTOM", tile.subLabel, "TOP", 0, 1)
    tile.label:SetJustifyH("CENTER")

    tile.labelBg = tile:CreateTexture(nil, "BACKGROUND")
    tile.labelBg:SetPoint("TOPLEFT", tile.label, "TOPLEFT", -4, 2)
    tile.labelBg:SetPoint("BOTTOMRIGHT", tile.label, "BOTTOMRIGHT", 4, -1)
    tile.labelBg:SetColorTexture(0, 0, 0, 0.7)

    -- Sound and animation slots, right under the tile.
    --
    -- Stacked rather than side by side: a tile can be as narrow as 48px, and two
    -- buttons split across that leaves room for neither an icon nor a word.
    local function MakeSlotButton(offsetY, iconPath)
        local btn = CreateFrame("Button", nil, tile, "BackdropTemplate")
        btn:SetPoint("TOPLEFT", tile, "BOTTOMLEFT", 0, offsetY)
        btn:SetPoint("TOPRIGHT", tile, "BOTTOMRIGHT", 0, offsetY)
        btn:SetHeight(16)
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        btn:SetBackdropColor(0, 0, 0, 0.8)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetSize(12, 12)
        btn.icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
        btn.icon:SetTexture(iconPath)

        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 2, 0)
        btn.text:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        btn.text:SetJustifyH("LEFT")
        btn.text:SetTextColor(1, 0.82, 0)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.82, 0, 1)
            if self.tooltipTitle then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tooltipTitle, 1, 0.82, 0)
                GameTooltip:AddLine(self.tooltipValue or "--", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["ANIMPREVIEW_SLOT_HINT"]
                    or "Click to change. Right-click to play it.", 0.5, 0.7, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            GameTooltip:Hide()
        end)
        return btn
    end

    tile.animBtn = MakeSlotButton(-2, "Interface\\Icons\\INV_Misc_Film_01")
    tile.animBtn:SetScript("OnClick", function(self, button)
        local entry = tile.entry
        if not entry then return end
        if button == "RightButton" then
            if OxedHub.Animations then OxedHub.Animations:Play(entry.animId) end
            return
        end
        AnimationPreview:OpenPicker("animation", entry.trigger, entry.key)
    end)

    tile.soundBtn = MakeSlotButton(-20, "Interface\\Common\\VoiceChat-Speaker")
    tile.soundBtn:SetScript("OnClick", function(self, button)
        local entry = tile.entry
        if not entry or not entry.soundKey then return end
        local value = entry.trigger.actions and entry.trigger.actions[entry.soundKey]
        if button == "RightButton" then
            if value and OxedHub.Sounds then OxedHub.Sounds:Play(value) end
            return
        end
        AnimationPreview:OpenPicker("sound", entry.trigger, entry.soundKey)
    end)

    tile:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetBackdropBorderColor(0.4, 1, 0.4, 1)
    end)

    tile:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetBackdropBorderColor(1, 0.82, 0, 0.6)
        AnimationPreview:SaveTilePosition(self)
    end)

    tile:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
        local entry = self.entry
        if not entry then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(entry.trigger.name or entry.triggerId, 1, 0.82, 0)
        if entry.source_desc then
            GameTooltip:AddLine("|cff888888Fires on:|r " .. entry.source_desc, 0.9, 0.9, 0.9, true)
        end
        GameTooltip:AddLine("|cff888888Animation:|r " .. tostring(entry.animId), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(("|cff888888Position:|r %d, %d"):format(
            math.floor(entry.x + 0.5), math.floor(entry.y + 0.5)), 0.9, 0.9, 0.9)
        if entry.source ~= "trigger" then
            -- Say so plainly: dragging this tile is about to give the trigger a
            -- position of its own, which changes where it plays from.
            GameTooltip:AddLine(entry.source == "animation"
                and (L["ANIMPREVIEW_FROM_ANIMATION"] or "Using the animation's own position.")
                or (L["ANIMPREVIEW_FROM_DEFAULT"] or "Using the profile default position."),
                0.7, 0.7, 0.7, true)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["ANIMPREVIEW_TILE_HINT"]
            or "Drag to move. Right-click to open this trigger.", 0.5, 0.7, 1, true)
        GameTooltip:Show()
    end)

    tile:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0.35)
        GameTooltip:Hide()
    end)

    tile:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        local entry = self.entry
        if not entry then return end
        AnimationPreview:Exit()
        if OxedHub.UI and OxedHub.UI.ShowMainWindow then OxedHub.UI:ShowMainWindow() end
        if OxedHub.Triggers and OxedHub.Triggers.OpenTriggerDetails then
            OxedHub.Triggers:OpenTriggerDetails(entry.triggerId)
        end
    end)

    self.tiles[index] = tile
    return tile
end

-- Open the addon's existing sound or animation picker against one slot.
--
-- The picker writes the choice into the trigger itself and closes, so the only
-- thing missing is redrawing the tiles -- picked from a hook on the picker's
-- OnHide rather than a callback, because the picker offers none and its own
-- close button has to trigger the redraw too.
function AnimationPreview:OpenPicker(kind, trigger, actionKey)
    local Triggers = OxedHub.Triggers
    if not Triggers or not trigger or not actionKey then return end

    if kind == "sound" then
        if not Triggers.ShowSoundPicker then return end
        Triggers:ShowSoundPicker(trigger, actionKey)
        self:WatchPicker(Triggers.soundPicker)
    else
        if not Triggers.ShowAnimationPicker then return end
        Triggers:ShowAnimationPicker(trigger, actionKey)
        self:WatchPicker(Triggers.animationPicker)
    end
end

function AnimationPreview:WatchPicker(picker)
    if not picker then return end
    if not picker._animPreviewHooked then
        picker:HookScript("OnHide", function()
            if AnimationPreview:IsActive() then AnimationPreview:Layout() end
        end)
        picker._animPreviewHooked = true
    end
end

-- Write a dragged tile back into the trigger, in the same fields the
-- per-trigger position dialog uses.
function AnimationPreview:SaveTilePosition(tile)
    local entry = tile and tile.entry
    if not entry then return end

    local cx, cy = tile:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not cx or not ux then return end

    local relX = math.floor(cx - ux + 0.5)
    local relY = math.floor(cy - uy + 0.5)
    relX, relY = self:SnapPosition(relX, relY)

    -- Put the tile where the number says, or a snapped drop would save one
    -- position and show another.
    tile:ClearAllPoints()
    tile:SetPoint("CENTER", UIParent, "CENTER", relX, relY)

    local actions = entry.trigger.actions
    if type(actions) ~= "table" then return end
    actions[entry.key .. "PositionX"] = relX
    actions[entry.key .. "PositionY"] = relY
    -- Without this the saved numbers are ignored and the animation keeps
    -- playing from the profile default, so the drag would appear to do nothing.
    actions[entry.key .. "UseCustomPosition"] = true

    entry.x, entry.y = relX, relY
    entry.source = "trigger"

    if self.panel and self.panel.status then
        self.panel.status:SetText(("%s  ->  %d, %d"):format(
            entry.trigger.name or entry.triggerId, relX, relY))
    end
end

-- ── Mode ─────────────────────────────────────────────────────────────────────

function AnimationPreview:IsActive()
    return self.active == true
end

function AnimationPreview:Layout()
    local entries = self:Collect()
    self.entries = entries

    for index, entry in ipairs(entries) do
        local tile = self:CreateTile(index)
        tile.entry = entry
        tile:SetSize(entry.width, entry.height)
        tile:ClearAllPoints()
        tile:SetPoint("CENTER", UIParent, "CENTER", entry.x, entry.y)

        local name = entry.trigger.name or entry.triggerId
        -- Rules can hold more than one animation; without the key the two tiles
        -- would carry the same caption and be impossible to tell apart.
        if entry.key ~= "animation" then
            name = name .. " |cff888888(" .. entry.key .. ")|r"
        end
        tile.label:SetText(name)
        tile.subLabel:SetText(entry.source_desc or "")

        tile.animBtn.text:SetText(ShortLabel(entry.animId))
        tile.animBtn.tooltipTitle = L["ANIMPREVIEW_SLOT_ANIM"] or "Animation"
        tile.animBtn.tooltipValue = tostring(entry.animId)
        tile.animBtn:Show()

        -- Hidden, not disabled, when this animation slot has no paired sound:
        -- a dead button invites a click that can never do anything.
        if entry.soundKey then
            local value = entry.trigger.actions[entry.soundKey]
            tile.soundBtn.text:SetText(ShortLabel(value))
            tile.soundBtn.tooltipTitle = L["ANIMPREVIEW_SLOT_SOUND"] or "Sound"
            tile.soundBtn.tooltipValue = value and tostring(value)
                or (L["ANIMPREVIEW_SLOT_EMPTY"] or "Not set")
            tile.soundBtn:Show()
        else
            tile.soundBtn:Hide()
        end

        PlayTile(tile, self.animate)
        tile:Show()
    end

    for index = #entries + 1, #(self.tiles or {}) do
        StopTileAnimation(self.tiles[index])
        self.tiles[index].entry = nil
        self.tiles[index]:Hide()
    end

    if self.panel and self.panel.count then
        self.panel.count:SetText(string.format(
            L["ANIMPREVIEW_COUNT"] or "%d animations from enabled triggers", #entries))
    end
end

function AnimationPreview:SetAnimated(animate)
    self.animate = animate and true or false
    for _, tile in ipairs(self.tiles or {}) do
        if tile:IsShown() then PlayTile(tile, self.animate) end
    end
end

-- The grid the preview draws is ActionHub's, so its spacing has to be read from
-- there or the lines and the snap would disagree.
local function GridStep()
    local ActionHub = OxedHub.ActionHub
    return (ActionHub and ActionHub.screenGridStep) or 64
end

-- Round a position onto the grid.
--
-- Measured from the centre of the screen, because that is where the grid is
-- drawn from -- snapping from a corner would put tiles between the lines.
--
-- Tiles are direct children of UIParent and their saved position is already a
-- centre offset, so this needs none of the scale conversion the node snapping
-- elsewhere does.
function AnimationPreview:SnapPosition(relX, relY)
    if not (self.gridOn and self.snapOn) then return relX, relY end
    local step = GridStep()
    if step < 4 then return relX, relY end
    return math.floor((relX / step) + 0.5) * step,
           math.floor((relY / step) + 0.5) * step
end

function AnimationPreview:SetSnap(enabled)
    self.snapOn = enabled and true or false
end

function AnimationPreview:SetGridStep(step)
    local ActionHub = OxedHub.ActionHub
    if not ActionHub then return end
    ActionHub.screenGridStep = step
    if self.gridOn and ActionHub.SetScreenGridShown then
        ActionHub:SetScreenGridShown(true, step)
    end
end

function AnimationPreview:SetGridShown(shown)
    self.gridOn = shown and true or false
    local ActionHub = OxedHub.ActionHub
    if ActionHub and ActionHub.SetScreenGridShown then
        ActionHub:SetScreenGridShown(self.gridOn)
    end
end

function AnimationPreview:GetOrCreatePanel()
    if self.panel then return self.panel end

    local f = CreateFrame("Frame", "OxedHubAnimationPreviewPanel", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(320, 292)
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if f.TitleText then
        f.TitleText:SetText(L["ANIMPREVIEW_TITLE"] or "Animation Preview")
    end
    if f.CloseButton then
        f.CloseButton:SetScript("OnClick", function() AnimationPreview:Exit() end)
    end

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)
    f.count:SetTextColor(1, 0.82, 0)

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", f.count, "BOTTOMLEFT", 0, -6)
    hint:SetWidth(288)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["ANIMPREVIEW_HINT"]
        or "Drag a tile to place that trigger's animation. Right-click one to open its trigger.")

    local gridCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    gridCheck:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
    gridCheck:SetSize(24, 24)
    gridCheck:SetScript("OnClick", function(self)
        AnimationPreview:SetGridShown(self:GetChecked())
    end)
    local gridLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gridLabel:SetPoint("LEFT", gridCheck, "RIGHT", 4, 0)
    gridLabel:SetText(L["ANIMPREVIEW_GRID"] or "Screen Grid")
    gridLabel:SetTextColor(0.9, 0.9, 0.9)
    f.gridCheck = gridCheck

    local playCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    playCheck:SetPoint("LEFT", gridLabel, "RIGHT", 20, 0)
    playCheck:SetSize(24, 24)
    playCheck:SetScript("OnClick", function(self)
        AnimationPreview:SetAnimated(self:GetChecked())
    end)
    local playLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playLabel:SetPoint("LEFT", playCheck, "RIGHT", 4, 0)
    playLabel:SetText(L["ANIMPREVIEW_PLAY"] or "Play")
    playLabel:SetTextColor(0.9, 0.9, 0.9)
    f.playCheck = playCheck

    -- Snapping is a separate opt-in from the guides: some people want the lines
    -- only, to line tiles up by eye.
    local snapCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    snapCheck:SetPoint("TOPLEFT", gridCheck, "BOTTOMLEFT", 0, -6)
    snapCheck:SetSize(24, 24)
    snapCheck:SetScript("OnClick", function(self)
        AnimationPreview:SetSnap(self:GetChecked())
    end)
    snapCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ANIMPREVIEW_SNAP"] or "Snap to Grid", 1, 0.82, 0)
        GameTooltip:AddLine(L["ANIMPREVIEW_SNAP_DESC"]
            or "Dropped tiles land on the nearest grid line. Needs the screen grid on.",
            1, 1, 1, true)
        GameTooltip:Show()
    end)
    snapCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local snapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    snapLabel:SetPoint("LEFT", snapCheck, "RIGHT", 4, 0)
    snapLabel:SetText(L["ANIMPREVIEW_SNAP"] or "Snap to Grid")
    snapLabel:SetTextColor(0.9, 0.9, 0.9)
    f.snapCheck = snapCheck

    -- Spacing lives here as well as in Move Mode. Both drive the same grid, and
    -- a snap you cannot set the spacing of is a snap you cannot aim.
    local stepLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stepLabel:SetPoint("TOPLEFT", snapCheck, "BOTTOMLEFT", 2, -8)
    stepLabel:SetTextColor(0.9, 0.9, 0.9)
    f.stepLabel = stepLabel

    local stepSlider = CreateFrame("Slider", "OxedHubAnimPreviewGridStep", f, "OptionsSliderTemplate")
    stepSlider:SetPoint("TOPLEFT", stepLabel, "BOTTOMLEFT", 0, -12)
    stepSlider:SetWidth(276)
    stepSlider:SetMinMaxValues(24, 160)
    stepSlider:SetValueStep(4)
    stepSlider:SetObeyStepOnDrag(true)
    if stepSlider.Low then stepSlider.Low:SetText("24") end
    if stepSlider.High then stepSlider.High:SetText("160") end
    if stepSlider.Text then stepSlider.Text:SetText("") end
    stepSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        stepLabel:SetText(string.format(
            L["ANIMPREVIEW_GRID_SPACING"] or "Grid Spacing  %d", value))
        if self.isSyncing then return end
        AnimationPreview:SetGridStep(value)
    end)
    f.stepSlider = stepSlider

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("TOPLEFT", stepSlider, "BOTTOMLEFT", 2, -14)
    f.status:SetWidth(288)
    f.status:SetJustifyH("LEFT")
    f.status:SetTextColor(0.5, 1, 0.5)

    local doneBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    doneBtn:SetSize(140, 24)
    doneBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    doneBtn:SetText(L["ANIMPREVIEW_DONE"] or "Done")
    doneBtn:SetScript("OnClick", function() AnimationPreview:Exit() end)

    self.panel = f
    return f
end

function AnimationPreview:Enter()
    if self:IsActive() then return end

    local entries = self:Collect()
    if #entries == 0 then
        print("|cffff5555Oxed Hub:|r " .. (L["ANIMPREVIEW_EMPTY"]
            or "No enabled trigger has an animation to preview."))
        return
    end

    self.active = true

    -- The main window covers the middle of the screen, which is where most
    -- animations sit. Reopened on exit so the mode reads as a detour, not a
    -- place you get dumped out of.
    self.reopenMainWindow = false
    if OxedHub.mainFrame and OxedHub.mainFrame:IsShown() then
        self.reopenMainWindow = true
        OxedHub.mainFrame:Hide()
    end

    local panel = self:GetOrCreatePanel()
    panel.gridCheck:SetChecked(self.gridOn == true)
    panel.playCheck:SetChecked(self.animate == true)
    panel.snapCheck:SetChecked(self.snapOn == true)
    panel.stepSlider.isSyncing = true
    panel.stepSlider:SetValue(math.min(160, math.max(24, GridStep())))
    panel.stepSlider.isSyncing = false
    panel.status:SetText("")
    panel:Show()

    self:SetGridShown(self.gridOn)
    self:Layout()
end

function AnimationPreview:Exit()
    if not self:IsActive() then return end
    self.active = false

    for _, tile in ipairs(self.tiles or {}) do
        StopTileAnimation(tile)
        tile.entry = nil
        tile:Hide()
    end

    -- The grid is a placement aid; never leave it on screen after.
    self:SetGridShown(false)
    self.gridOn = false

    if self.panel then self.panel:Hide() end

    if self.reopenMainWindow and OxedHub.UI and OxedHub.UI.ShowMainWindow then
        OxedHub.UI:ShowMainWindow()
    end
    self.reopenMainWindow = false

    if OxedHub.Triggers and OxedHub.Triggers.RefreshTriggersList then
        OxedHub.Triggers:RefreshTriggersList()
    end
end

function AnimationPreview:Toggle()
    if self:IsActive() then self:Exit() else self:Enter() end
end
