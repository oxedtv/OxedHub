local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers

-- ─────────────────────────────────────────────────────────────────────────
-- Quick Setup — build triggers straight from the spells this character has.
--
-- Reads the player's real spellbook (which already reflects their spec and
-- talents), groups the spells into roles, and lets a sound + animation be
-- assigned to any number of them at once. Selecting five spells and pressing
-- Create makes five working triggers.
-- ─────────────────────────────────────────────────────────────────────────

Triggers.QuickSetup = Triggers.QuickSetup or {}
local QuickSetup = Triggers.QuickSetup

-- Spells worth offering, keyed by role so the list reads as something other
-- than an undifferentiated dump of the spellbook. Anything not listed still
-- appears under "Other Abilities" if it's on the player's bars.
local ROLE_INTERRUPT = "interrupt"
local ROLE_DEFENSIVE = "defensive"
local ROLE_COOLDOWN  = "cooldown"
local ROLE_MOVEMENT  = "movement"
local ROLE_CC        = "cc"
local ROLE_OTHER     = "other"

local ROLE_ORDER = {
    { key = ROLE_COOLDOWN,  label = "Major Cooldowns",  color = "ffff8800" },
    { key = ROLE_INTERRUPT, label = "Interrupts",       color = "ff55ddff" },
    { key = ROLE_DEFENSIVE, label = "Defensives",       color = "ff55ff55" },
    { key = ROLE_CC,        label = "Crowd Control",    color = "ffcc66ff" },
    { key = ROLE_MOVEMENT,  label = "Movement",         color = "ffffff55" },
    { key = ROLE_OTHER,     label = "Other Abilities",  color = "ffaaaaaa" },
}

-- Known role assignments. Spells not listed fall back to a cooldown-length
-- heuristic, so this table only needs to cover the ones worth naming.
QuickSetup.SPELL_ROLES = {
    -- Interrupts
    [6552]   = ROLE_INTERRUPT, -- Pummel
    [2139]   = ROLE_INTERRUPT, -- Counterspell
    [1766]   = ROLE_INTERRUPT, -- Kick
    [96231]  = ROLE_INTERRUPT, -- Rebuke
    [47528]  = ROLE_INTERRUPT, -- Mind Freeze
    [106839] = ROLE_INTERRUPT, -- Skull Bash
    [116705] = ROLE_INTERRUPT, -- Spear Hand Strike
    [147362] = ROLE_INTERRUPT, -- Counter Shot
    [187707] = ROLE_INTERRUPT, -- Muzzle
    [57994]  = ROLE_INTERRUPT, -- Wind Shear
    [183752] = ROLE_INTERRUPT, -- Disrupt
    [351338] = ROLE_INTERRUPT, -- Quell
    [19647]  = ROLE_INTERRUPT, -- Spell Lock

    -- Defensives
    [871]    = ROLE_DEFENSIVE, -- Shield Wall
    [12975]  = ROLE_DEFENSIVE, -- Last Stand
    [498]    = ROLE_DEFENSIVE, -- Divine Protection
    [642]    = ROLE_DEFENSIVE, -- Divine Shield
    [45438]  = ROLE_DEFENSIVE, -- Ice Block
    [31224]  = ROLE_DEFENSIVE, -- Cloak of Shadows
    [5277]   = ROLE_DEFENSIVE, -- Evasion
    [47585]  = ROLE_DEFENSIVE, -- Dispersion
    [48792]  = ROLE_DEFENSIVE, -- Icebound Fortitude
    [48707]  = ROLE_DEFENSIVE, -- Anti-Magic Shell
    [108271] = ROLE_DEFENSIVE, -- Astral Shift
    [186265] = ROLE_DEFENSIVE, -- Aspect of the Turtle
    [104773] = ROLE_DEFENSIVE, -- Unending Resolve
    [22812]  = ROLE_DEFENSIVE, -- Barkskin
    [61336]  = ROLE_DEFENSIVE, -- Survival Instincts
    [115203] = ROLE_DEFENSIVE, -- Fortifying Brew
    [198589] = ROLE_DEFENSIVE, -- Blur
    [363916] = ROLE_DEFENSIVE, -- Obsidian Scales

    -- Major cooldowns
    [31884]  = ROLE_COOLDOWN,  -- Avenging Wrath
    [107574] = ROLE_COOLDOWN,  -- Avatar
    [1719]   = ROLE_COOLDOWN,  -- Recklessness
    [190319] = ROLE_COOLDOWN,  -- Combustion
    [12042]  = ROLE_COOLDOWN,  -- Arcane Power
    [12472]  = ROLE_COOLDOWN,  -- Icy Veins
    [13750]  = ROLE_COOLDOWN,  -- Adrenaline Rush
    [121471] = ROLE_COOLDOWN,  -- Shadow Blades
    [10060]  = ROLE_COOLDOWN,  -- Power Infusion
    [51271]  = ROLE_COOLDOWN,  -- Pillar of Frost
    [49028]  = ROLE_COOLDOWN,  -- Dancing Rune Weapon
    [114050] = ROLE_COOLDOWN,  -- Ascendance
    [19574]  = ROLE_COOLDOWN,  -- Bestial Wrath
    [266779] = ROLE_COOLDOWN,  -- Coordinated Assault
    [113858] = ROLE_COOLDOWN,  -- Dark Soul
    [102560] = ROLE_COOLDOWN,  -- Incarnation
    [137639] = ROLE_COOLDOWN,  -- Storm, Earth, and Fire
    [162264] = ROLE_COOLDOWN,  -- Metamorphosis
    [375087] = ROLE_COOLDOWN,  -- Dragonrage

    -- Movement
    [100]    = ROLE_MOVEMENT,  -- Charge
    [1953]   = ROLE_MOVEMENT,  -- Blink
    [2983]   = ROLE_MOVEMENT,  -- Sprint
    [36554]  = ROLE_MOVEMENT,  -- Shadowstep
    [781]    = ROLE_MOVEMENT,  -- Disengage
    [109132] = ROLE_MOVEMENT,  -- Roll
    [195072] = ROLE_MOVEMENT,  -- Fel Rush
    [1850]   = ROLE_MOVEMENT,  -- Dash
    [358267] = ROLE_MOVEMENT,  -- Hover

    -- Crowd control
    [853]    = ROLE_CC,        -- Hammer of Justice
    [118]    = ROLE_CC,        -- Polymorph
    [408]    = ROLE_CC,        -- Kidney Shot
    [2094]   = ROLE_CC,        -- Blind
    [8122]   = ROLE_CC,        -- Psychic Scream
    [5246]   = ROLE_CC,        -- Intimidating Shout
    [19577]  = ROLE_CC,        -- Intimidation
    [51514]  = ROLE_CC,        -- Hex
    [605]    = ROLE_CC,        -- Mind Control
    [339]    = ROLE_CC,        -- Entangling Roots
}

-- Cooldown in seconds, or nil when it can't be read.
local function GetSpellCooldownSeconds(spellID)
    local ok, seconds = pcall(function()
        if C_Spell and C_Spell.GetSpellCooldown then
            local info = C_Spell.GetSpellCooldown(spellID)
            -- A spell's base cooldown shows up in the charge/cooldown info even
            -- when it isn't currently on cooldown.
            if info and info.duration and type(info.duration) == "number" and info.duration > 0 then
                return info.duration
            end
        end
        local baseCD = C_Spell and C_Spell.GetSpellBaseCooldown
            and C_Spell.GetSpellBaseCooldown(spellID)
        if baseCD and baseCD > 0 then
            return baseCD / 1000
        end
        return nil
    end)
    return ok and seconds or nil
end

local function FormatCooldown(seconds)
    if not seconds or seconds <= 0 then return nil end
    if seconds >= 60 then
        return math.floor(seconds / 60 + 0.5) .. " min"
    end
    return math.floor(seconds + 0.5) .. " sec"
end

-- Role for a spell: explicit mapping first, then a cooldown-based guess so
-- unlisted abilities still land somewhere sensible.
local function GetSpellRole(spellID, cooldownSeconds)
    local role = QuickSetup.SPELL_ROLES[spellID]
    if role then return role end
    if cooldownSeconds and cooldownSeconds >= 90 then
        return ROLE_COOLDOWN
    end
    return ROLE_OTHER
end

-- Every spell this character can actually cast, from the spellbook (which
-- already accounts for spec and talents) plus anything sitting on their bars.
function QuickSetup:CollectPlayerSpells()
    local seen, spells = {}, {}

    local function Add(spellID)
        if not spellID or seen[spellID] then return end
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        if not info or not info.name then return end

        -- Passives make no sense as cast triggers.
        if C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(spellID) then return end

        seen[spellID] = true
        local cd = GetSpellCooldownSeconds(spellID)
        table.insert(spells, {
            id = spellID,
            name = info.name,
            icon = info.iconID,
            cooldown = cd,
            cooldownText = FormatCooldown(cd),
            role = GetSpellRole(spellID, cd),
        })
    end

    -- Spellbook: the authoritative list of what this spec/talent build has.
    pcall(function()
        local numLines = C_SpellBook.GetNumSpellBookSkillLines()
        for lineIndex = 1, numLines do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
            if lineInfo then
                local count = lineInfo.numSpellBookItems or 0
                for i = lineInfo.itemIndexOffset, lineInfo.itemIndexOffset + count - 1 do
                    local itemInfo = C_SpellBook.GetSpellBookItemInfo(i, Enum.SpellBookSpellBank.Player)
                    if itemInfo and itemInfo.spellID then
                        Add(itemInfo.spellID)
                    end
                end
            end
        end
    end)

    -- Action bars catch macro'd and item-granted abilities the book misses.
    pcall(function()
        for slot = 1, 120 do
            local actionType, id = GetActionInfo(slot)
            if actionType == "spell" then
                Add(id)
            elseif actionType == "macro" then
                Add(GetMacroSpell(id))
            end
        end
    end)

    return spells
end

-- Group the flat list into the display order defined above.
function QuickSetup:GroupSpells(spells)
    local buckets = {}
    for _, spell in ipairs(spells) do
        buckets[spell.role] = buckets[spell.role] or {}
        table.insert(buckets[spell.role], spell)
    end

    for _, list in pairs(buckets) do
        table.sort(list, function(a, b)
            -- Longest cooldown first: those are the moments worth reacting to.
            local cdA, cdB = a.cooldown or 0, b.cooldown or 0
            if cdA ~= cdB then return cdA > cdB end
            return (a.name or "") < (b.name or "")
        end)
    end

    local grouped = {}
    for _, role in ipairs(ROLE_ORDER) do
        if buckets[role.key] and #buckets[role.key] > 0 then
            table.insert(grouped, {
                label = role.label,
                color = role.color,
                spells = buckets[role.key],
            })
        end
    end
    return grouped
end

-- Does a trigger already watch this spell? Used to mark spells as covered so
-- the same trigger isn't built twice.
function QuickSetup:FindExistingTrigger(spellID)
    local sid = tostring(spellID)
    for id, trigger in pairs(OxedHub.db.profile.triggers or {}) do
        if trigger.event == "UNIT_SPELLCAST_SUCCEEDED" and trigger.conditions then
            if tostring(trigger.conditions.spellID or "") == sid then
                return id, trigger
            end
            for _, extra in ipairs(trigger.conditions.extraSpellIDs or {}) do
                if tostring(extra) == sid then return id, trigger end
            end
        end
    end
    return nil
end

-- Build one trigger for a spell, with the chosen sound / animation.
function QuickSetup:CreateTriggerForSpell(spell)
    local id = OxedHub:GenerateID("trigger")
    local event = "UNIT_SPELLCAST_SUCCEEDED"
    local actions = {}
    
    if QuickSetup.settings.useSound then
        actions.sound = "oxedhub_effects_airhorn" -- Default sound (Airhorn)
    end
    if QuickSetup.settings.useAnim then
        actions.animation = "oxed_anim_male_celebrate" -- Default animation (Celebrate)
    end
    
    actions.showIcon = QuickSetup.settings.showIcon
    if actions.showIcon then
        actions.iconSize = QuickSetup.settings.iconSize or 64
        actions.iconStyle = QuickSetup.settings.iconStyle or "SQUARE"
        if QuickSetup.goal == "AURA" then
            actions.iconShowDuration = true
        else
            actions.iconShowCooldown = true
        end
    end
    
    if QuickSetup.goal == "AURA" then
        event = "UNIT_AURA"
    end

    OxedHub.db.profile.triggers[id] = {
        id = id,
        name = spell.name,
        event = event,
        conditions = {
            spellID = tostring(spell.id),
            allClasses = true,
        },
        actions = actions,
        zones = {
            OPEN_WORLD = true,
            PARTY = true,
            DELVE = true,
            RAID = true,
            PVP = true,
            BATTLEGROUND = true,
        },
        enabled = true,
        minimized = true,
    }
    return id
end

-- Create triggers for a set of spells in one pass.
function QuickSetup:CreateTriggers(spells, skipExisting)
    local created, skipped = 0, 0
    local lastCreatedId = nil
    for _, spell in ipairs(spells) do
        if skipExisting and self:FindExistingTrigger(spell.id) then
            skipped = skipped + 1
        else
            lastCreatedId = self:CreateTriggerForSpell(spell)
            created = created + 1
        end
    end

    if created > 0 then
        Triggers:InvalidateEnabledEventCache()
        Triggers:RefreshTriggersList()
    end
    return created, skipped, lastCreatedId
end

-- ─────────────────────────────────────────────────────────────────────────
-- UI
-- ─────────────────────────────────────────────────────────────────────────

local function SoundName(id)
    if not id or id == "" then return "None" end
    local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds()
        or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds) or {}
    local def = sounds[id] or (OxedHub.GENERATED_SOUND_CATALOG or {})[id]
    return (def and def.name) or tostring(id)
end

local function AnimationName(id)
    if not id or id == "" then return "None" end
    local def = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.animations
        and OxedHub.db.profile.animations[id]
    return (def and def.name) or tostring(id)
end

local function Truncate(text, maxLen)
    text = tostring(text or "")
    if #text <= maxLen then return text end
    return text:sub(1, maxLen - 1) .. "…"
end

function QuickSetup:Show()
    QuickSetup.settings = QuickSetup.settings or {
        useSound = false,
        useAnim = false,
        showIcon = true,
        iconSize = 64,
        iconStyle = "SQUARE"
    }

    local f = self.frame
    if not f then
        f = CreateFrame("Frame", "OxedHubQuickSetupFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(560, 620)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetToplevel(true)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        tinsert(UISpecialFrames, "OxedHubQuickSetupFrame")
        if f.TitleText then f.TitleText:SetText(L["QS_TITLE"] or "Quick Setup") end
        if f.CloseButton then f.CloseButton:SetScript("OnClick", function() f:Hide() end) end

        f.step1 = CreateFrame("Frame", nil, f)
        f.step1:SetAllPoints()

        local step1Intro = f.step1:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        step1Intro:SetPoint("TOP", 0, -60)
        step1Intro:SetText("What do you wish to monitor?")
        
        local step1Desc = f.step1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        step1Desc:SetPoint("TOP", step1Intro, "BOTTOM", 0, -20)
        step1Desc:SetWidth(460)
        step1Desc:SetJustifyH("CENTER")
        step1Desc:SetText("Triggers act as your personal combat assistants. They allow you to attach custom audio cues, screen flashes, or on-screen icons to specific events in combat. This helps you react faster to important cooldowns, interrupts, or defensive buffs without having to constantly watch your action bars.")

        local function CreateGoalButton(parent, title, desc, iconPath, yOffset)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(460, 120)
            btn:SetPoint("TOP", parent, "TOP", 0, yOffset)
            
            btn.backdrop = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            btn.backdrop:SetAllPoints()
            btn.backdrop:SetBackdrop({
                bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            btn.backdrop:SetBackdropColor(0, 0, 0, 0)
            btn.backdrop:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
            
            btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.hover:SetPoint("TOPLEFT", 4, -4)
            btn.hover:SetPoint("BOTTOMRIGHT", -4, 4)
            btn.hover:SetColorTexture(1, 0.82, 0, 0.15)
            
            btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            btn.title:SetPoint("TOP", btn, "TOP", 0, -14)
            btn.title:SetText(title)
            
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(64, 64)
            btn.icon:SetPoint("TOPLEFT", 24, -36)
            btn.icon:SetTexture(iconPath)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            
            btn.iconMask = btn:CreateMaskTexture()
            btn.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.iconMask:SetSize(64, 64)
            btn.iconMask:SetPoint("CENTER", btn.icon, "CENTER")
            btn.icon:AddMaskTexture(btn.iconMask)
            
            btn.desc = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.desc:SetPoint("LEFT", btn.icon, "RIGHT", 16, 0)
            btn.desc:SetWidth(330)
            btn.desc:SetJustifyH("LEFT")
            btn.desc:SetText(desc)
            
            return btn
        end

        f.auraBtn = CreateGoalButton(f.step1, "Track an Aura / Buff", "Monitor how long a buff or aura is active on you.\n\nE.g. Defensive cooldown durations, burst windows, or procs.", "Interface\\Icons\\spell_holy_powerwordshield", -200)
        f.auraBtn:SetScript("OnClick", function()
            QuickSetup.goal = "AURA"
            f.step1:Hide()
            f.step2:Show()
        end)

        f.castBtn = CreateGoalButton(f.step1, "Track a Spell Cast", "Trigger a specific sound, animation, or icon when you cast an ability (or mix with toys!).\n\nE.g. Audio alert when casting an interrupt or major cooldown.", "Interface\\Icons\\spell_fire_fireball02", -340)
        f.castBtn:SetScript("OnClick", function()
            QuickSetup.goal = "CAST"
            f.step1:Hide()
            f.step2:Show()
        end)

        -- Step 2 Frame
        f.step2 = CreateFrame("Frame", nil, f)
        f.step2:SetAllPoints()
        f.step2:Hide()

        local intro = f.step2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", 16, -32)
        intro:SetPoint("RIGHT", f.step2, "RIGHT", -16, 0)
        intro:SetJustifyH("LEFT")
        intro:SetText("Tick the spells you want to track, then press Create. Only spells this character actually has are listed.")

        f.skipExisting = CreateFrame("CheckButton", nil, f.step2, "UICheckButtonTemplate")
        f.skipExisting:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", -2, -10)
        f.skipExisting:SetSize(22, 22)
        f.skipExisting:SetChecked(true)
        f.skipExisting.text:SetText(L["QS_SKIP_EXISTING"] or "Skip spells that already have a trigger")

        -- Spell list
        local scroll = CreateFrame("ScrollFrame", nil, f.step2, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", f.skipExisting, "BOTTOMLEFT", 0, -10)
        scroll:SetPoint("BOTTOMRIGHT", f.step2, "BOTTOMRIGHT", -34, 56)
        if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
            pcall(function() OxedHub.UI:StyleScrollFrame(scroll) end)
        end
        local child = CreateFrame("Frame", nil, scroll)
        child:SetSize(490, 1)
        scroll:SetScrollChild(child)
        f.scroll, f.listChild, f.rows, f.headers = scroll, child, {}, {}

        f.nextBtn = CreateFrame("Button", nil, f.step2, "UIPanelButtonTemplate")
        f.nextBtn:SetSize(150, 26)
        f.nextBtn:SetPoint("BOTTOMRIGHT", -14, 16)
        f.nextBtn:SetText("Next")
        
        f.backBtn = CreateFrame("Button", nil, f.step2, "UIPanelButtonTemplate")
        f.backBtn:SetSize(80, 26)
        f.backBtn:SetPoint("BOTTOMLEFT", 14, 16)
        f.backBtn:SetText("Back")
        f.backBtn:SetScript("OnClick", function()
            f.step2:Hide()
            f.step1:Show()
        end)

        f.selectAllBtn = CreateFrame("Button", nil, f.step2, "UIPanelButtonTemplate")
        f.selectAllBtn:SetSize(100, 26)
        f.selectAllBtn:SetPoint("LEFT", f.backBtn, "RIGHT", 8, 0)
        f.selectAllBtn:SetText(L["QS_SELECT_ALL"] or "Select All")

        f.clearAllBtn = CreateFrame("Button", nil, f.step2, "UIPanelButtonTemplate")
        f.clearAllBtn:SetSize(100, 26)
        f.clearAllBtn:SetPoint("LEFT", f.selectAllBtn, "RIGHT", 8, 0)
        f.clearAllBtn:SetText(L["QS_CLEAR_ALL"] or "Clear All")

        f.countText = f.step2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.countText:SetPoint("LEFT", f.clearAllBtn, "RIGHT", 12, 0)

        -- Step 3 Frame
        f.step3 = CreateFrame("Frame", nil, f)
        f.step3:SetAllPoints()
        f.step3:Hide()

        local step3Intro = f.step3:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        step3Intro:SetPoint("TOP", 0, -30)
        step3Intro:SetText("Additional Settings")
        
        local step3Desc = f.step3:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        step3Desc:SetPoint("TOP", step3Intro, "BOTTOM", 0, -10)
        step3Desc:SetWidth(460)
        step3Desc:SetJustifyH("CENTER")
        step3Desc:SetText("These settings can be changed later.\nPick what you wish to be enabled in alert actions (multiple choice).")

        -- Helper: create a simple action row (icon + label, clickable toggle)
        local function CreateActionRow(parent, label, iconPath, settingsKey)
            local row = CreateFrame("Button", nil, parent)
            row:SetSize(460, 36)

            row.bg = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.bg:SetAllPoints()
            row.bg:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            row.bg:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
            row.bg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.iconFrame:SetSize(28, 28)
            row.iconFrame:SetPoint("LEFT", 6, 0)
            row.iconFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            row.iconFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            row.iconFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            row.iconFrame:SetFrameLevel(row.bg:GetFrameLevel() + 2)

            row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
            row.icon:SetPoint("TOPLEFT", row.iconFrame, "TOPLEFT", 2, -2)
            row.icon:SetPoint("BOTTOMRIGHT", row.iconFrame, "BOTTOMRIGHT", -2, 2)
            row.icon:SetTexture(iconPath)

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("LEFT", row.iconFrame, "RIGHT", 10, 0)
            row.label:SetText(label)

            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:SetSize(16, 16)
            row.check:SetPoint("RIGHT", -8, 0)

            row.hover = row:CreateTexture(nil, "HIGHLIGHT")
            row.hover:SetAllPoints()
            row.hover:SetColorTexture(1, 0.82, 0, 0.1)

            row.UpdateState = function(self)
                if QuickSetup.settings[settingsKey] then
                    self.check:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
                    self.label:SetTextColor(1, 0.82, 0)
                    self.icon:SetDesaturated(false)
                    self.bg:SetBackdropBorderColor(1, 0.82, 0, 0.6)
                else
                    self.check:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-NotReady")
                    self.label:SetTextColor(0.5, 0.5, 0.5)
                    self.icon:SetDesaturated(true)
                    self.bg:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                end
            end

            row:SetScript("OnClick", function()
                QuickSetup.settings[settingsKey] = not QuickSetup.settings[settingsKey]
                if f.UpdateStep3 then f.UpdateStep3() end
            end)

            return row
        end

        -- Helper: create an icon size button with a proper border
        local function CreateSizeBtn(parent, sizeVal, labelText)
            local sizeMap = { [16]=16, [32]=24, [64]=34, [128]=46, [256]=58 }
            local displaySize = sizeMap[sizeVal] or math.min(sizeVal, 58)
            local btnW = displaySize + 16
            local btnH = displaySize + 16
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(btnW, btnH + 18)

            btn.backdrop = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            btn.backdrop:SetPoint("TOPLEFT", 0, 0)
            btn.backdrop:SetSize(btnW, btnH)
            btn.backdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            btn.backdrop:SetBackdropColor(0, 0, 0, 0)
            btn.backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(displaySize, displaySize)
            btn.icon:SetPoint("CENTER", btn.backdrop, "CENTER", 0, 0)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.label:SetPoint("TOP", btn.backdrop, "BOTTOM", 0, -2)
            btn.label:SetText(labelText)

            btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.hover:SetAllPoints(btn.backdrop)
            btn.hover:SetColorTexture(1, 0.82, 0, 0.15)

            btn.UpdateState = function(self)
                if QuickSetup.settings.iconSize == sizeVal then
                    self.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
                    self.label:SetTextColor(1, 0.82, 0)
                else
                    self.backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    self.label:SetTextColor(0.6, 0.6, 0.6)
                end
            end

            btn:SetScript("OnClick", function()
                QuickSetup.settings.iconSize = sizeVal
                if f.UpdateStep3 then f.UpdateStep3() end
            end)

            return btn
        end

        -- Helper: create a shape preview button with a proper border
        local function CreateShapeBtn(parent, shapeVal, labelText)
            local btn = CreateFrame("Button", nil, parent)
            btn:SetSize(70, 88)

            btn.backdrop = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            btn.backdrop:SetPoint("TOPLEFT", 0, 0)
            btn.backdrop:SetSize(70, 70)
            btn.backdrop:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            btn.backdrop:SetBackdropColor(0, 0, 0, 0)
            btn.backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(48, 48)
            btn.icon:SetPoint("CENTER", btn.backdrop, "CENTER", 0, 0)

            if shapeVal == "CIRCLE" then
                btn.icon:SetSize(56, 56)
                btn.iconMask = btn:CreateMaskTexture()
                btn.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                btn.iconMask:SetSize(48, 48)
                btn.iconMask:SetPoint("CENTER", btn.icon, "CENTER")
                btn.icon:AddMaskTexture(btn.iconMask)
            else
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.label:SetPoint("TOP", btn.backdrop, "BOTTOM", 0, -2)
            btn.label:SetText(labelText)

            btn.hover = btn:CreateTexture(nil, "HIGHLIGHT")
            btn.hover:SetAllPoints(btn.backdrop)
            btn.hover:SetColorTexture(1, 0.82, 0, 0.15)

            btn.UpdateState = function(self)
                if QuickSetup.settings.iconStyle == shapeVal then
                    self.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
                    self.label:SetTextColor(1, 0.82, 0)
                else
                    self.backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    self.label:SetTextColor(0.6, 0.6, 0.6)
                end
            end

            btn:SetScript("OnClick", function()
                QuickSetup.settings.iconStyle = shapeVal
                if f.UpdateStep3 then f.UpdateStep3() end
            end)

            return btn
        end

        -- === ALERT ACTIONS ===
        local actLabel = f.step3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        actLabel:SetPoint("TOPLEFT", 30, -100)
        actLabel:SetText("Alert Actions")

        local actNote = f.step3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        actNote:SetPoint("TOPLEFT", actLabel, "BOTTOMLEFT", 0, -4)
        actNote:SetText("*multiple choice")

        f.rowIcon = CreateActionRow(f.step3, "Icon:", "Interface\\Icons\\INV_Misc_QuestionMark", "showIcon")
        f.rowIcon:SetPoint("TOPLEFT", actNote, "BOTTOMLEFT", 0, -10)
        f.rowSound = CreateActionRow(f.step3, "Sound:", "Interface\\Icons\\INV_Misc_Horn_01", "useSound")
        f.rowSound:SetPoint("TOPLEFT", f.rowIcon, "BOTTOMLEFT", 0, -4)
        f.rowAnim = CreateActionRow(f.step3, "Animation:", "Interface\\Icons\\Ability_Rogue_Sprint", "useAnim")
        f.rowAnim:SetPoint("TOPLEFT", f.rowSound, "BOTTOMLEFT", 0, -4)

        -- === ICON SIZE (centered in frame) ===
        local sizeLabel = f.step3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        sizeLabel:SetPoint("TOPLEFT", f.rowAnim, "BOTTOMLEFT", 0, -20)
        sizeLabel:SetText("Icon Size")

        f.btnTiny = CreateSizeBtn(f.step3, 16, "Tiny")
        f.btnSmall = CreateSizeBtn(f.step3, 32, "Small")
        f.btnMid = CreateSizeBtn(f.step3, 64, "Medium")
        f.btnLarge = CreateSizeBtn(f.step3, 128, "Large")
        f.btnHuge = CreateSizeBtn(f.step3, 256, "Huge")
        f.btnMid:SetPoint("TOP", sizeLabel, "BOTTOM", 200, -8)
        f.btnSmall:SetPoint("RIGHT", f.btnMid, "LEFT", -18, 0)
        f.btnTiny:SetPoint("RIGHT", f.btnSmall, "LEFT", -18, 0)
        f.btnLarge:SetPoint("LEFT", f.btnMid, "RIGHT", 18, 0)
        f.btnHuge:SetPoint("LEFT", f.btnLarge, "RIGHT", 18, 0)

        -- === ICON SHAPE (centered in frame) ===
        local shapeLabel = f.step3:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        shapeLabel:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -90)
        shapeLabel:SetText("Icon Shape")

        f.btnSquare = CreateShapeBtn(f.step3, "SQUARE", "Square")
        f.btnCircle = CreateShapeBtn(f.step3, "CIRCLE", "Circle")
        f.btnSquare:SetPoint("TOP", shapeLabel, "BOTTOM", 170, -8)
        f.btnCircle:SetPoint("LEFT", f.btnSquare, "RIGHT", 30, 0)

        f.UpdateStep3 = function()
            f.rowIcon:UpdateState()
            f.rowSound:UpdateState()
            f.rowAnim:UpdateState()
            f.btnTiny:UpdateState()
            f.btnSmall:UpdateState()
            f.btnMid:UpdateState()
            f.btnLarge:UpdateState()
            f.btnHuge:UpdateState()
            f.btnSquare:UpdateState()
            f.btnCircle:UpdateState()

            local alpha = QuickSetup.settings.showIcon and 1 or 0.4
            f.btnTiny:SetAlpha(alpha)
            f.btnSmall:SetAlpha(alpha)
            f.btnMid:SetAlpha(alpha)
            f.btnLarge:SetAlpha(alpha)
            f.btnHuge:SetAlpha(alpha)
            f.btnSquare:SetAlpha(alpha)
            f.btnCircle:SetAlpha(alpha)
        end
        
        f.createBtn = CreateFrame("Button", nil, f.step3, "UIPanelButtonTemplate")
        f.createBtn:SetSize(150, 26)
        f.createBtn:SetPoint("BOTTOMRIGHT", -14, 16)
        f.createBtn:SetText(L["QS_CREATE"] or "Create Triggers")
        
        f.step3BackBtn = CreateFrame("Button", nil, f.step3, "UIPanelButtonTemplate")
        f.step3BackBtn:SetSize(80, 26)
        f.step3BackBtn:SetPoint("BOTTOMLEFT", 14, 16)
        f.step3BackBtn:SetText("Back")
        f.step3BackBtn:SetScript("OnClick", function()
            f.step3:Hide()
            f.step2:Show()
        end)

        -- Re-read the spell list whenever the spec changes: a Retribution list
        -- is wrong the instant the player swaps to Protection.
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("PLAYER_TALENT_UPDATE")
        f:SetScript("OnEvent", function(self)
            if self:IsShown() then QuickSetup:Refresh() end
        end)

        self.frame = f
    end

    self.selected = self.selected or {}
    self:Refresh()
    if f.step1 and f.step2 and f.step3 then
        f.step3:Hide()
        f.step2:Hide()
        f.step1:Show()
    end
    f:Show()
    f:Raise()
end

function QuickSetup:Refresh()
    local f = self.frame
    if not f then return end

    local spells = self:CollectPlayerSpells()
    local grouped = self:GroupSpells(spells)
    self.allSpells = spells

    for _, row in ipairs(f.rows) do row:Hide() end
    for _, header in ipairs(f.headers) do header:Hide() end

    local rowIndex, headerIndex, y = 0, 0, 0
    local selectedCount = 0

    for _, group in ipairs(grouped) do
        headerIndex = headerIndex + 1
        local header = f.headers[headerIndex]
        if not header then
            header = f.listChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.headers[headerIndex] = header
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", f.listChild, "TOPLEFT", 16, -y - 8)
        header:SetText("|c" .. group.color .. group.label .. "|r")
        header:Show()
        y = y + 32

        for _, spell in ipairs(group.spells) do
            rowIndex = rowIndex + 1
            local row = f.rows[rowIndex]
            if not row then
                row = CreateFrame("Frame", nil, f.listChild)
                row:SetHeight(44)
                
                row.hover = row:CreateTexture(nil, "HIGHLIGHT")
                row.hover:SetAllPoints()
                row.hover:SetColorTexture(1, 0.82, 0, 0.1)

                row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                row.check:SetSize(24, 24)
                row.check:SetPoint("LEFT", row, "LEFT", 24, 0)

                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(32, 32)
                row.icon:SetPoint("LEFT", row.check, "RIGHT", 8, 0)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 12, 0)
                row.name:SetWidth(200)
                row.name:SetJustifyH("LEFT")

                row.cd = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                row.cd:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
                row.cd:SetWidth(60)
                row.cd:SetJustifyH("LEFT")

                row.status = row:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                row.status:SetPoint("LEFT", row.cd, "RIGHT", 4, 0)
                row.status:SetWidth(120)
                row.status:SetJustifyH("LEFT")

                f.rows[rowIndex] = row
            end

            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f.listChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", f.listChild, "RIGHT", 0, 0)
            row:Show()

            row.icon:SetTexture(spell.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(spell.name)
            row.cd:SetText(spell.cooldownText or "")

            local existingId = self:FindExistingTrigger(spell.id)
            if existingId then
                row.status:SetText("|cff888888already set up|r")
            else
                row.status:SetText("")
            end

            row.check:SetChecked(self.selected[spell.id] and true or false)
            if self.selected[spell.id] then selectedCount = selectedCount + 1 end
            row.check:SetScript("OnClick", function(self)
                QuickSetup.selected[spell.id] = self:GetChecked() or nil
                QuickSetup:UpdateCount()
            end)

            y = y + 44
        end
        y = y + 10
    end

    f.listChild:SetHeight(math.max(y, 1))

    f.selectAllBtn:SetScript("OnClick", function()
        for _, spell in ipairs(self.allSpells or {}) do
            self.selected[spell.id] = true
        end
        self:Refresh()
    end)
    f.clearAllBtn:SetScript("OnClick", function()
        wipe(self.selected)
        self:Refresh()
    end)

    f.nextBtn:SetScript("OnClick", function()
        local chosen = {}
        for _, spell in ipairs(self.allSpells or {}) do
            if self.selected[spell.id] then table.insert(chosen, spell) end
        end
        if #chosen == 0 then
            print("|cffff0000Oxed Hub:|r Tick at least one spell first.")
            return
        end

        QuickSetup.chosenSpells = chosen
        
        local firstSpellIcon = chosen[1] and chosen[1].icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        if f.rowIcon then f.rowIcon.icon:SetTexture(firstSpellIcon) end
        if f.btnTiny then f.btnTiny.icon:SetTexture(firstSpellIcon) end
        if f.btnSmall then f.btnSmall.icon:SetTexture(firstSpellIcon) end
        if f.btnMid then f.btnMid.icon:SetTexture(firstSpellIcon) end
        if f.btnLarge then f.btnLarge.icon:SetTexture(firstSpellIcon) end
        if f.btnHuge then f.btnHuge.icon:SetTexture(firstSpellIcon) end
        if f.btnSquare then f.btnSquare.icon:SetTexture(firstSpellIcon) end
        if f.btnCircle then f.btnCircle.icon:SetTexture(firstSpellIcon) end
        
        if f.UpdateStep3 then f.UpdateStep3() end

        f.step2:Hide()
        f.step3:Show()
    end)
    
    f.createBtn:SetScript("OnClick", function()
        local created, skipped, lastCreatedId = self:CreateTriggers(QuickSetup.chosenSpells, f.skipExisting:GetChecked())

        print(("|cff00ff00Oxed Hub:|r Created %d trigger(s)%s."):format(
            created, skipped > 0 and (", skipped " .. skipped .. " already set up") or ""))

        wipe(self.selected)
        QuickSetup.chosenSpells = nil
        self:Refresh()
        
        if lastCreatedId then
            f:Hide()
            Triggers:OpenTriggerDetails(lastCreatedId)
        end
    end)

    self:UpdateCount(selectedCount)
end

function QuickSetup:UpdateCount(known)
    local f = self.frame
    if not f then return end
    local count = known
    if not count then
        count = 0
        for _ in pairs(self.selected or {}) do count = count + 1 end
    end
    f.countText:SetText(("%d selected"):format(count))
end
