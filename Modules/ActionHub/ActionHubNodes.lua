local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ActionHub: what a node shows: cooldowns, charges, proc and ready glows, dimming,
-- key labels, and StyleButton, which both the hubs on screen and the
-- settings preview draw their nodes with.
-- The files and what each holds are listed at the top of ActionHubData.lua.
local ActionHub = OxedHub.ActionHub
local Private = ActionHub._private

-- Local references
local CONFIG = OxedHub.CONFIG
local L = OxedHub.L
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local C_ToyBox = C_ToyBox
local GameTooltip = GameTooltip
local SendChatMessage = SendChatMessage
local DoEmote = DoEmote
local math = math
local table = table
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
local type = type

local function StyleCooldownText(cdFrame, offsetY)
    local activeDB = ActionHub:GetActiveHubDB()
    local fontSize = (activeDB and activeDB.cooldownTextSize) or 11
    local font = OxedHub:GetFont("Fonts\\FRIZQT__.ttf")

    -- Styled once and left alone until something changes. This ran on every
    -- cooldown of every node on every pass, and SetFont is not cheap: it was
    -- a large part of what the performance report charged to the hub.
    if cdFrame._ohFont == font and cdFrame._ohSize == fontSize and cdFrame._ohOffset == (offsetY or 0) then
        return
    end

    local regions = { cdFrame:GetRegions() }
    for _, region in ipairs(regions) do
        if region:GetObjectType() == "FontString" then
            -- Remembered only once there was a text to style: the countdown
            -- text may not exist yet on a cooldown that has never run.
            cdFrame._ohFont, cdFrame._ohSize, cdFrame._ohOffset = font, fontSize, offsetY or 0
            region:SetFont(font, fontSize, "OUTLINE")
            region:ClearAllPoints()
            region:SetPoint("CENTER", cdFrame, "CENTER", 0, offsetY or 0)
        end
    end
end

local MARKER_ICONS = {
    [0] = "Interface\\Icons\\Spell_ChargeNegative",
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
local FLARE_ICONS = {
    [0] = "Interface\\Icons\\Spell_ChargePositive",
    [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}
-- Must match the icons the picker lists for these entries, otherwise a node
-- ends up showing something different from what was dragged onto it.
local PING_ICONS = {
    [""] = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-main-icon.png",
    attack = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Attack-Icon.png",
    assist = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Assist-Icon.png",
    onmyway = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-OnMyWay-Icon.png",
    warning = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Warning-Icon.png",
}

local function GetMarkerPingIcon(slot)
    -- The picker stores its own icon on the slot; trust that first so the node
    -- always matches what was picked.
    if slot.icon and slot.icon ~= "" then
        return slot.icon
    end

    if slot.type == "marker" then
        return MARKER_ICONS[slot.id] or "Interface\\Icons\\Spell_ChargeNegative"
    elseif slot.type == "targetmarker" then
        return FLARE_ICONS[slot.id] or "Interface\\Icons\\Spell_ChargePositive"
    elseif slot.type == "ping" then
        return PING_ICONS[slot.id] or PING_ICONS[""]
    end
end

local function GetMarkerPingMacro(slot)
    if slot.type == "marker" then
        if slot.id == 0 then return "/cwm all"
        else return "/wm " .. slot.id end
    elseif slot.type == "targetmarker" then
        if slot.id == 0 then return "/tm 0"
        else return "/tm " .. slot.id end
    elseif slot.type == "ping" then
        if slot.id == "" then return "/ping"
        else return "/ping " .. slot.id end
    end
end

-- start/duration coming out of the cooldown APIs are "secret" values in combat:
-- comparing one directly raises an error.  (The isEnabled/isActive booleans are
-- plain and safe to read -- see Core:ArmCooldownReady.)
--
-- The spell branch below already round-tripped its numbers through tostring,
-- but the item/toy branch compared `dur > 1.5` raw.  In combat that threw, the
-- surrounding pcall swallowed it, GetSlotCooldown returned nil, and the node's
-- cooldown swirl disappeared for the whole fight -- reappearing on the way out
-- when the values stopped being secret.
local function SafeNum(value)
    local ok, asString = pcall(tostring, value)
    if not ok or type(asString) ~= "string" then return nil end
    local ok2, num = pcall(tonumber, asString)
    if ok2 and type(num) == "number" then return num end
    return nil
end

-- Read one field off a returned table without branching on its value.  A secret
-- value can be fetched and stringified, but any `if` on it raises an error.
local function SafeField(tbl, key)
    local ok, value = pcall(function() return tbl[key] end)
    if ok then return value end
    return nil
end

local function SpellCooldown(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil, nil end
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok or type(cdInfo) ~= "table" then return nil, nil end

    -- isEnabled / isActive are deliberately NOT consulted.  They can come back
    -- as secret booleans: fetching one is fine and it even stringifies as
    -- "true", but testing it in a condition throws -- which the caller's pcall
    -- then swallowed, so every spell silently reported "no cooldown".
    -- The numbers alone are enough: a spell that is not on cooldown reports
    -- duration 0.
    local d = SafeNum(SafeField(cdInfo, "duration"))
    local s = SafeNum(SafeField(cdInfo, "startTime"))
    if d and s and d > 1.5 and s > 0 then return s, d end
    return nil, nil
end

-- Toggle with /run OxedHub.ActionHub:ToggleCooldownDebug()
-- Prints what each node's cooldown lookup actually returned, so a node that
-- goes blank in combat can be traced to the exact call that failed.
function ActionHub:ToggleCooldownDebug()
    self.cdDebug = not self.cdDebug
    print("|cff00d9d9Oxed Hub:|r ActionHub cooldown debug "
        .. (self.cdDebug and "|cff88ff88ON|r" or "|cffff6666OFF|r"))
    return self.cdDebug
end

local function CDDebug(msg, force)
    if not ActionHub.cdDebug then return end
    if not force then
        -- Throttle chatter: the pass runs twice a second across every node.
        -- Errors bypass this -- hiding them is what made this hard to find.
        local now = GetTime()
        ActionHub._cdDebugAt = ActionHub._cdDebugAt or 0
        if now - ActionHub._cdDebugAt < 1 then return end
        ActionHub._cdDebugAt = now
    end
    print("|cffff9900[CD]|r " .. tostring(msg))
end

-- Paint a Cooldown frame for a slot, the way the stock action bars do it.
--
-- The numeric Cooldown:SetCooldown(start, duration) path -- which is what
-- CooldownFrame_Set uses -- is closed to addon code in 12.0
-- (SecretArguments AllowedWhenUntainted).  It simply refuses to paint, which is
-- why nodes went blank in combat no matter how carefully the numbers were
-- sanitised: the numbers were never the problem, the sink was.
--
-- The supported route is the duration object: C_Spell.GetSpellCooldownDuration
-- hands back an opaque object that Cooldown:SetCooldownFromDurationObject
-- accepts from tainted code.
--
-- Returns true when a cooldown is being shown.
-- When did the player last actually cast each spell.  This is the only
-- non-secret way to tell a real cooldown apart from the global cooldown: both
-- report isActive, and the remaining time is a secret value we cannot read.
local lastCastAt = {}

local castWatcher = CreateFrame("Frame")
castWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castWatcher:SetScript("OnEvent", function(_, _, _, _, spellID)
    spellID = tonumber(spellID)
    if spellID then lastCastAt[spellID] = GetTime() end
end)

-- True when the only thing running on this spell is the global cooldown.
--
-- A toy sitting on a 15 minute cooldown and a toy that is merely blocked for
-- 1.5s by the GCD both report isActive, so a node full of toys used to spin
-- its swirl on every unrelated cast.  Base cooldown is static and readable;
-- combined with when the spell was last actually cast it tells the two apart.
--
-- ⚠ The cooldown's own length decides first, whenever the game lets it be
-- read. The memory of casts below is empty after every reload, and with
-- nothing remembered every real cooldown (a portal, a long defensive, a toy)
-- was taken for the GCD and its swipe hidden: the swipes vanished on every
-- /reload. Out of a fight the length is a plain number, and the GCD is never
-- longer than 1.5 s. In a fight it is secret, and the old reasoning still
-- applies, with one more check: if the GCD itself is not running, whatever
-- is running cannot be the GCD.
local GCD_SPELL = 61304
local GCD_LONGEST = 1.6   -- seconds; a hasted or slowed GCD never passes 1.5

local function ReadableLength(info)
    local length = info and info.duration
    if type(length) ~= "number" then return nil end
    if issecretvalue and issecretvalue(length) then return nil end
    return length
end

local function GlobalCooldownRunning()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, gcd = pcall(C_Spell.GetSpellCooldown, GCD_SPELL)
    if not ok or type(gcd) ~= "table" then return nil end
    -- isActive is documented as never secret.
    if gcd.isActive == nil then return nil end
    return gcd.isActive == true
end

local function IsGlobalCooldownOnly(spellID, info)
    if not spellID then return false end

    local length = ReadableLength(info)
    if length then return length <= GCD_LONGEST end

    local baseMs = 0
    if GetSpellBaseCooldown then
        local ok, b = pcall(GetSpellBaseCooldown, spellID)
        if ok and type(b) == "number" then baseMs = b end
    end

    -- No cooldown of its own: anything active is the GCD.
    if baseMs <= 1500 then return true end

    -- Has a real cooldown, but we never saw it cast (or it has long since
    -- finished), so what is running now belongs to something else.
    local last = lastCastAt[spellID]
    if last then return (GetTime() - last) > (baseMs / 1000) end

    -- Never seen cast this session, which is every spell after a reload.
    -- Running while the GCD is not: a real cooldown.
    if GlobalCooldownRunning() == false then return false end
    return true
end

-- ⚠ A swipe already showing this very cooldown is left alone. Every pass
-- used to ask the game for a duration object and set the swipe again, on
-- every node, even when nothing had changed: that, times a pass on every bag
-- cooldown event, was most of the 30 MB a session of /oxprofile put on
-- ActionHub. The start and length are compared when they can be read; in a
-- fight they can be secret, and then the swipe is set as before.
local function PlainNumber(value)
    if type(value) ~= "number" then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

-- Whether the swipe is really drawing a cooldown that has not ended.
-- ⚠ IsShown is not enough. Right after a reload or a loading screen the game
-- can hand over a cooldown that is not loaded yet; the swipe set from it ends
-- at once while the frame stays shown. Remembering only "shown, same start,
-- same length" then skipped that node on every later pass, and its swipe was
-- gone until the spell was cast again. A swipe that cannot be read (a secret,
-- in a fight) is never trusted: it is set again, as it always was.
local function SwipeRunning(cdFrame)
    if not (cdFrame:IsShown() and cdFrame.GetCooldownTimes) then return false end
    local ok, startMs, lengthMs = pcall(cdFrame.GetCooldownTimes, cdFrame)
    if not ok then return false end
    startMs, lengthMs = PlainNumber(startMs), PlainNumber(lengthMs)
    if not (startMs and lengthMs) or lengthMs <= 0 then return false end
    return (startMs + lengthMs) > GetTime() * 1000
end

local function PaintSlotCooldown(cdFrame, spellID, ignoreGCD)
    if not cdFrame then return false end

    if spellID and C_Spell and C_Spell.GetSpellCooldownDuration
        and cdFrame.SetCooldownFromDurationObject then
        local okInfo, info = pcall(C_Spell.GetSpellCooldown, spellID)
        -- isActive is documented as never-secret, so testing it is safe.
        local active = okInfo and type(info) == "table" and info.isActive
        if active and ignoreGCD and IsGlobalCooldownOnly(spellID, info) then
            active = false
        end
        if active then
            local start, length = PlainNumber(info.startTime), PlainNumber(info.duration)
            if start and length and cdFrame._ohStart == start and cdFrame._ohLength == length
                and cdFrame._ohSpell == spellID and SwipeRunning(cdFrame) then
                return true
            end
            local okDur, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
            if okDur and durObj then
                local okSet = pcall(cdFrame.SetCooldownFromDurationObject, cdFrame, durObj)
                if okSet then
                    cdFrame._ohStart, cdFrame._ohLength, cdFrame._ohSpell = start, length, spellID
                    cdFrame._ohItem = nil
                    cdFrame:Show()
                    return true
                end
            end
        end
    end

    cdFrame._ohStart, cdFrame._ohLength, cdFrame._ohSpell = nil, nil, nil
    cdFrame._ohItem = nil
    -- Already clear: nothing to clear again.
    if not cdFrame:IsShown() then return false end
    if cdFrame.Clear then pcall(cdFrame.Clear, cdFrame) end
    cdFrame:Hide()
    return false
end

-- ── Items ──────────────────────────────────────────────────────────────────
-- ⚠ An item's cooldown lives on the item, not on the spell it casts. A trinket
-- or an on-use chest piece showed the spell's cooldown, which is the short
-- lockout every on-use item shares (about 20 s), while the item itself sat on
-- its real two minutes. Item cooldowns come back as plain numbers, so the
-- swipe is set from them directly; the numeric SetCooldown only refuses
-- secret numbers, and those are never passed. If the numbers ever are secret,
-- the item answers nil and the spell's duration object is used as before.

-- The item a node uses: an item or a toy, or the item a macro uses when it
-- casts no spell of its own.
-- A macro's item is asked for at most once a second: the answer comes with
-- an item link, a fresh string each time, and every pass over every macro
-- node was making one.
local macroItems = setmetatable({}, { __mode = "k" })   -- slot -> { id, at }
local MacroItemNow

local function SlotItemID(slot)
    if not (slot and slot.id) then return nil end
    if slot.type == "item" or slot.type == "toy" then return tonumber(slot.id) end
    if slot.type == "macro" then
        local now = GetTime()
        local known = macroItems[slot]
        if known and now - known.at < 1 then return known.id end
        if not known then
            known = {}
            macroItems[slot] = known
        end
        known.id, known.at = MacroItemNow(slot), now
        return known.id
    end
    return nil
end

MacroItemNow = function(slot)
    do
        local key = slot.label
        if not key or (GetMacroIndexByName and GetMacroIndexByName(key) == 0) then key = slot.id end
        if not key then return nil end
        if GetMacroSpell and GetMacroSpell(key) then return nil end
        local _, link = GetMacroItem and GetMacroItem(key)
        if link and GetItemInfoInstant then return (GetItemInfoInstant(link)) end
    end
    return nil
end

local function ItemCooldownNumbers(itemID)
    local get = (C_Item and C_Item.GetItemCooldown)
        or (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
    if not get then return nil end
    local ok, start, length = pcall(get, itemID)
    if not ok then return nil end
    start, length = PlainNumber(start), PlainNumber(length)
    if not (start and length) then return nil end
    return start, length
end

-- true: a swipe is showing; false: the item is ready; nil: could not tell,
-- the caller should use the spell instead.
local function PaintItemCooldown(cdFrame, itemID, ignoreGCD)
    if not (cdFrame and itemID and cdFrame.SetCooldown) then return nil end
    local start, length = ItemCooldownNumbers(itemID)
    if not start then return nil end

    local running = start > 0 and length > 0 and (start + length) > GetTime()
    if running and ignoreGCD and length <= GCD_LONGEST then running = false end

    if running then
        if cdFrame._ohItem == itemID and cdFrame._ohStart == start and cdFrame._ohLength == length
            and SwipeRunning(cdFrame) then
            return true
        end
        if pcall(cdFrame.SetCooldown, cdFrame, start, length) then
            cdFrame._ohStart, cdFrame._ohLength, cdFrame._ohSpell = start, length, nil
            cdFrame._ohItem = itemID
            cdFrame:Show()
            return true
        end
        return nil
    end

    cdFrame._ohStart, cdFrame._ohLength, cdFrame._ohSpell = nil, nil, nil
    cdFrame._ohItem = nil
    if cdFrame:IsShown() then
        if cdFrame.Clear then pcall(cdFrame.Clear, cdFrame) end
        cdFrame:Hide()
    end
    return false
end

-- A node's swipe: the item's own cooldown when it holds an item, else the
-- spell's.
local function PaintNodeCooldown(cdFrame, slot, spellID, ignoreGCD)
    local itemID = SlotItemID(slot)
    if itemID then
        local painted = PaintItemCooldown(cdFrame, itemID, ignoreGCD)
        if painted ~= nil then return painted end
    end
    return PaintSlotCooldown(cdFrame, spellID, ignoreGCD)
end

-- Show how many charges a spell has left, like the stock bars do.
--
-- Charge fields can come back as secret values in restricted content, and
-- touching one throws.  issecretvalue() is the supported way to ask before
-- reading; it is only present on clients that have the restriction, hence the
-- existence check.
local function UpdateChargeCount(btn, spellID, style)
    local shown = nil

    if spellID and C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and type(info) == "table" then
            local cur, max = info.currentCharges, info.maxCharges
            local secret = issecretvalue
                and (issecretvalue(cur) or issecretvalue(max))
            if not secret then
                cur, max = tonumber(cur), tonumber(max)
                -- Only worth drawing when the spell actually banks charges.
                if cur and max and max > 1 then
                    shown = cur
                end
            end
        end
    end

    if shown == nil then
        if btn.chargeText then btn.chargeText:Hide() end
        btn._ohCharge = nil
        return
    end

    -- Nothing to redo when the count and the node's shape are what they were.
    if btn._ohCharge == shown and btn._ohChargeStyle == style
        and btn.chargeText and btn.chargeText:IsShown() then
        return
    end
    btn._ohCharge, btn._ohChargeStyle = shown, style

    if not btn.chargeText then
        btn.chargeText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        -- Above the cooldown swipe, same as the keybind label.
        btn.chargeText:SetDrawLayer("OVERLAY", 7)
        btn.chargeText:SetShadowOffset(1, -1)
        btn.chargeText:SetShadowColor(0, 0, 0, 1)
    end

    btn.chargeText:ClearAllPoints()
    btn.chargeText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", style == "ring" and -4 or -2, 2)
    btn.chargeText:SetJustifyH("RIGHT")
    -- Dim the number at zero, the way the default bars grey out a spent spell.
    if shown > 0 then
        btn.chargeText:SetTextColor(1, 1, 1, 1)
    else
        btn.chargeText:SetTextColor(0.6, 0.6, 0.6, 1)
    end
    btn.chargeText:SetText(shown)
    btn.chargeText:Show()
end

-- Declared here and defined further down: the cooldown dump below needs it, and
-- a local is invisible to anything written above its definition.
local GetSlotSpellID

-- An item's own cooldown, falling back to the spell it casts.
--
-- Shared by item, toy and macro slots -- three callers that were about to have
-- three copies of the same eight lines between them.
local function ItemCooldown(itemID)
    if not itemID then return nil, nil end

    local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
    local okItem, rawStart, rawDur = pcall(getCooldown, itemID)
    if okItem then
        local s, d = SafeNum(rawStart), SafeNum(rawDur)
        -- Anything at or under the global cooldown is not worth a swirl.
        if d and s and d > 1.5 and s > 0 then return s, d end
    end

    local _, spellID = GetItemSpell(itemID)
    if spellID then
        return SpellCooldown(spellID)
    end
    return nil, nil
end

local function GetSlotCooldown(slot)
    local ok, startTime, duration = pcall(function()
        if not slot then return nil, nil end
        local id = slot.id
        if not id then return nil, nil end

        if slot.type == "spell" then
            return SpellCooldown(id)
        end

        if slot.type == "toy" or slot.type == "item" then
            return ItemCooldown(id)
        end

        -- A macro has no cooldown of its own; what it casts does.
        --
        -- Asked by name rather than by index: indices shift whenever a macro is
        -- added or removed above this one, and the slot would then be reading a
        -- different macro's cooldown -- or none, which is what was happening
        -- here, since macros had no branch at all.
        --
        -- GetMacroSpell resolves the macro's conditionals as they stand right
        -- now, so a [mod] or [spec] macro reports whatever it would actually
        -- cast this second.
        if slot.type == "macro" then
            local key = slot.label
            if not key or (GetMacroIndexByName and GetMacroIndexByName(key) == 0) then
                key = id
            end
            if not key then return nil, nil end

            local spellID = GetMacroSpell and GetMacroSpell(key)
            if spellID then
                return SpellCooldown(spellID)
            end

            local _, itemLink = GetMacroItem and GetMacroItem(key)
            if itemLink and GetItemInfoInstant then
                local itemID = GetItemInfoInstant(itemLink)
                if itemID then
                    return ItemCooldown(itemID)
                end
            end
            return nil, nil
        end

        if slot.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[slot.id]
            local spellID = trg and OxedHub.Triggers and OxedHub.Triggers.GetTriggerCooldownSpellID and OxedHub.Triggers:GetTriggerCooldownSpellID(trg)
            if spellID then
                return SpellCooldown(spellID)
            end
        end
        return nil, nil
    end)
    if not ok then
        -- startTime holds the error message when pcall fails.
        CDDebug(("%s id=%s ERROR: %s"):format(
            tostring(slot and slot.type), tostring(slot and slot.id), tostring(startTime)), true)
        return nil, nil
    end

    if ActionHub.cdDebug and slot then
        CDDebug(("%s id=%s combat=%s -> start=%s dur=%s"):format(
            tostring(slot.type), tostring(slot.id), tostring(InCombatLockdown()),
            tostring(startTime), tostring(duration)))
    end

    return startTime, duration
end

-- One-shot dump of every node, printing the RAW api returns before any
-- sanitising.  If a value arrives as a secret, tostring shows it as something
-- non-numeric -- which is why SafeNum turns it into nil and the swirl vanishes
-- without any error being raised.
-- Use: /run OxedHub.ActionHub:DumpCooldowns()
function ActionHub:DumpCooldowns()
    local function Raw(v)
        local ok, s = pcall(tostring, v)
        return ok and s or "<unreadable>"
    end

    print("|cff00d9d9Oxed Hub:|r cooldown dump, combat=" .. tostring(InCombatLockdown()))
    local n = 0
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local slot = btn and btn.slotData
            if slot and slot.type and slot.id then
                n = n + 1
                local line = ("  %s id=%s"):format(tostring(slot.type), tostring(slot.id))

                if slot.type == "item" or slot.type == "toy" then
                    local getCooldown = C_Item and C_Item.GetItemCooldown or GetItemCooldown
                    local ok, s, d = pcall(getCooldown, slot.id)
                    line = line .. (" | item raw ok=%s start=%s dur=%s")
                        :format(tostring(ok), Raw(s), Raw(d))
                end

                local spellID = slot.type == "spell" and slot.id or select(2, GetItemSpell(slot.id))
                if spellID and C_Spell and C_Spell.GetSpellCooldown then
                    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
                    if ok and type(info) == "table" then
                        -- Stringifying a secret works; branching on it throws.
                        -- Test the branch explicitly so the dump shows which.
                        local branchOK = pcall(function()
                            if info.isEnabled and info.isActive then return end
                        end)
                        line = line .. (" | spell %s start=%s dur=%s enabled=%s active=%s branchOK=%s")
                            :format(tostring(spellID), Raw(info.startTime), Raw(info.duration),
                                Raw(info.isEnabled), Raw(info.isActive), tostring(branchOK))
                    else
                        line = line .. " | spell query failed"
                    end
                end

                -- Macros resolve through a chain of lookups, any link of which
                -- can be the one returning nothing. Print every link.
                if slot.type == "macro" then
                    local byName = GetMacroIndexByName and GetMacroIndexByName(slot.label or "") or -1
                    local mName, _, mBody = GetMacroInfo and GetMacroInfo(slot.id)
                    local key = slot.label
                    if not key or byName == 0 then key = slot.id end
                    local mSpell = GetMacroSpell and GetMacroSpell(key)
                    local mItemName, mItemLink = nil, nil
                    if GetMacroItem then mItemName, mItemLink = GetMacroItem(key) end
                    line = line .. ("\n      label=%s byName=%s infoName=%s key=%s macroSpell=%s macroItem=%s body=%s")
                        :format(Raw(slot.label), Raw(byName), Raw(mName), Raw(key),
                            Raw(mSpell), Raw(mItemName),
                            Raw(mBody and mBody:gsub("\n", " | "):sub(1, 60)))
                end

                line = line .. (" | SLOTSPELL=%s"):format(Raw(GetSlotSpellID(slot)))

                local rs, rd = GetSlotCooldown(slot)
                line = line .. (" | RESULT start=%s dur=%s"):format(Raw(rs), Raw(rd))
                print("|cffff9900[CD]|r " .. line)
            end
        end
    end
    if n == 0 then print("|cffff9900[CD]|r no nodes with a slot found") end
end

local function GetToyAssignmentMode(slot)
    if slot and slot.type == "toy" and slot.assignmentMode == "direct" then
        return "direct"
    end
    return "mix"
end

-- Is this slot currently usable? Mirrors Blizzard action bar behaviour: a mount
-- in a no-fly/no-mount zone, an unusable spell, etc. Returns true when we can't
-- tell, so anything we don't understand keeps its normal look.
-- The body runs inside pcall, but as a named function: an anonymous one
-- here was a fresh closure on every call, for every node, twice a second.
local function SlotUsableRaw(slot)
        if not slot then return true end
        local id = slot.id
        if not id then return true end

        if slot.type == "mount" then
            local spellID, collectionUsable
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid, _, _, isUsable = C_MountJournal.GetMountInfoByID(id)
                spellID, collectionUsable = sid, isUsable
            end

            -- The journal's isUsable only covers "do you own and can you ride
            -- this" (collected / faction / level) — it stays true indoors. The
            -- zone restriction lives on the mount's spell, which is what the
            -- default action bars grey out on.
            if collectionUsable == false then return false end

            if spellID and C_Spell and C_Spell.IsSpellUsable then
                local spellUsable = C_Spell.IsSpellUsable(spellID)
                if spellUsable ~= nil then return spellUsable and true or false end
            end

            -- Fallback for clients where the spell query gives nothing back.
            if IsIndoors and IsIndoors() then return false end
            return true
        end

        if slot.type == "spell" then
            if C_Spell and C_Spell.IsSpellUsable then
                -- The second answer: unusable only for want of mana/energy.
                local isUsable, noMana = C_Spell.IsSpellUsable(id)
                if isUsable ~= nil then return isUsable and true or false, noMana and true or false end
            end
            return true
        end

        if slot.type == "toy" and GetToyAssignmentMode(slot) == "direct" then
            if C_ToyBox and C_ToyBox.IsToyUsable then
                local isUsable = C_ToyBox.IsToyUsable(id)
                -- IsToyUsable returns nil while the toy is still loading; treat
                -- only an explicit false as unusable.
                if isUsable ~= nil then return isUsable and true or false end
            end
            return true
        end

        if slot.type == "item" then
            if C_Item and C_Item.IsUsableItem then
                local isUsable = C_Item.IsUsableItem(id)
                if isUsable ~= nil then return isUsable and true or false end
            end
            return true
        end

        return true
end

local function IsSlotUsable(slot)
    local ok, usable, noMana = pcall(SlotUsableRaw, slot)
    if ok then return usable, noMana end
    return true
end

-- Turn a stored binding ("ALT-CTRL-1", "SHIFT-F3", "BUTTON4") into a short
-- readable label like "Alt+1" / "A+C+1", mirroring the default action bars.
local BINDING_KEY_SHORT = {
    MOUSEWHEELUP = "WU", MOUSEWHEELDOWN = "WD",
    BUTTON3 = "M3", BUTTON4 = "M4", BUTTON5 = "M5",
    PAGEUP = "PU", PAGEDOWN = "PD",
    SPACE = "Sp", ESCAPE = "Esc", INSERT = "Ins", DELETE = "Del",
    HOME = "Hm", END = "End", BACKSPACE = "BS", ENTER = "Ent", TAB = "Tab",
}

local function FormatBindingText(binding)
    if not binding or binding == "" then return nil end

    local mods = {}
    local key = binding
    while true do
        local mod, rest = key:match("^(ALT)%-(.+)$")
        if not mod then mod, rest = key:match("^(CTRL)%-(.+)$") end
        if not mod then mod, rest = key:match("^(SHIFT)%-(.+)$") end
        if not mod then break end
        table.insert(mods, mod)
        key = rest
    end

    -- Numpad and function keys keep a compact form.
    key = key:gsub("^NUMPAD", "N"):gsub("^NUMLOCK", "NL")
    key = BINDING_KEY_SHORT[key] or key

    if #mods == 0 then
        return key
    end

    -- One modifier spells out ("Alt+1"); several abbreviate so the text still
    -- fits on the node ("A+C+1").
    local prettyMods = {}
    for _, mod in ipairs(mods) do
        if #mods == 1 then
            table.insert(prettyMods, mod:sub(1, 1) .. mod:sub(2):lower())
        else
            table.insert(prettyMods, mod:sub(1, 1))
        end
    end

    return table.concat(prettyMods, "+") .. "+" .. key
end

-- Show the slot's keybinding on the node, like the default UI. Square nodes get
-- it in the top-right corner; round ("ring") nodes get it centred and nudged
-- down so the text stays inside the circle instead of hanging off the corner.
local function UpdateBindingLabel(btn, slot, size, style)
    local hub = btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex)
    local text = slot and FormatBindingText(slot.binding)
    if hub and hub.showKeybind == false then text = nil end
    if not text then
        if btn.bindingText then btn.bindingText:Hide() end
        return
    end

    if not btn.bindingText then
        btn.bindingText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmallGray")
        -- Top sublevel so the cooldown swipe/text can't cover it.
        btn.bindingText:SetDrawLayer("OVERLAY", 7)
        btn.bindingText:SetShadowOffset(1, -1)
        btn.bindingText:SetShadowColor(0, 0, 0, 1)
        btn.bindingText:SetTextColor(1, 1, 1, 0.9)
    end

    btn.bindingText:ClearAllPoints()
    if style == "ring" then
        btn.bindingText:SetJustifyH("CENTER")
        btn.bindingText:SetPoint("TOP", btn, "TOP", 0, -6)
    else
        btn.bindingText:SetJustifyH("RIGHT")
        btn.bindingText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
    end
    btn.bindingText:SetWidth((size or btn:GetWidth() or 44) - 4)
    btn.bindingText:SetText(text)
    btn.bindingText:Show()
end

-- The icon picker stores its own value format (not always a texture path), so
-- it has to be resolved before being handed to SetTexture.
local function ResolveCustomIcon(value)
    if not value or value == "" then return nil end
    if OxedHub.IconPicker and OxedHub.IconPicker.ResolveTexture then
        return OxedHub.IconPicker:ResolveTexture(value)
    end
    return value
end

-- ─────────────────────────────────────────────────────────────────────────
-- Proc glow: mirrors Blizzard's spell activation overlay. When the game says a
-- spell has procced, any hub node that casts that spell lights up.
-- ─────────────────────────────────────────────────────────────────────────
local activeProcSpells = {}

-- Which spell (if any) does this slot ultimately cast?
-- The body runs inside pcall, but as a named function: an anonymous one
-- here was a fresh closure on every call, for every node, twice a second.
local function SlotSpellIDRaw(slot)
        if slot.type == "spell" then
            return slot.id
        end
        if slot.type == "mount" then
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid = C_MountJournal.GetMountInfoByID(slot.id)
                return sid
            end
            return nil
        end
        if slot.type == "toy" or slot.type == "item" then
            local _, sid = GetItemSpell(slot.id)
            return sid
        end
        -- A macro has no cooldown of its own; whatever it casts does. Without
        -- this branch a macro node simply never painted a swirl, because this
        -- is the function the painter asks for a spell.
        --
        -- Looked up by name, not by the stored index: indices shift as soon as
        -- a macro above this one is added or deleted, and the node would then
        -- be reading a different macro. GetMacroSpell also resolves the macro's
        -- conditionals as they stand now, so a [mod] or [spec] macro reports
        -- whatever it would actually cast this second.
        if slot.type == "macro" then
            local key = slot.label
            if not key or (GetMacroIndexByName and GetMacroIndexByName(key) == 0) then
                key = slot.id
            end
            if not key then return nil end

            local sid = GetMacroSpell and GetMacroSpell(key)
            if sid then return sid end

            -- Item macros: a potion or a trinket has its cooldown on the spell
            -- the item casts.
            local _, itemLink = GetMacroItem and GetMacroItem(key)
            if itemLink and GetItemInfoInstant then
                local itemID = GetItemInfoInstant(itemLink)
                if itemID then
                    local _, itemSpell = GetItemSpell(itemID)
                    return itemSpell
                end
            end
            return nil
        end

        if slot.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[slot.id]
            if trg and OxedHub.Triggers and OxedHub.Triggers.GetTriggerCooldownSpellID then
                return OxedHub.Triggers:GetTriggerCooldownSpellID(trg)
            end
        end
        return nil
end

function GetSlotSpellID(slot)
    if not slot or not slot.id then return nil end
    local ok, spellID = pcall(SlotSpellIDRaw, slot)
    return ok and spellID or nil
end

-- Is this spell currently proc-glowing? Blizzard often reports the glow against
-- a spell's base or override form rather than the exact id sitting on the node,
-- so check those variants too.
local function Variant(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

-- Ask the game directly whether a spell is currently overlay-glowing. This is
-- what the default action bars use, and it avoids the event-ID mismatch problem
-- entirely (the glow event often reports a different id than the one on the bar).
local function QueryOverlayed(spellID)
    if not spellID then return false end
    local overlayed = Variant(IsSpellOverlayed, spellID)
    if overlayed == nil and C_SpellActivationOverlay then
        overlayed = Variant(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
    end
    return overlayed == true
end

-- A spell's base and override forms, worked out once. They only change with
-- talents or specialisation, and asking three times per node per pass was most
-- of what a proc check cost.
local spellVariants = {}
local function SpellVariants(spellID)
    local ids = spellVariants[spellID]
    if ids then return ids end
    ids = { spellID }
    local base = Variant(FindBaseSpellByID, spellID)
    if base and base ~= spellID then table.insert(ids, base) end
    local override = Variant(FindSpellOverrideByID, spellID)
    if override and override ~= spellID then table.insert(ids, override) end
    local override2 = Variant(C_Spell and C_Spell.GetOverrideSpell, spellID)
    if override2 and override2 ~= spellID then table.insert(ids, override2) end
    spellVariants[spellID] = ids
    return ids
end

local variantReset = CreateFrame("Frame")
for _, event in ipairs({ "SPELLS_CHANGED", "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED",
        "PLAYER_SPECIALIZATION_CHANGED" }) do
    pcall(variantReset.RegisterEvent, variantReset, event)
end
variantReset:SetScript("OnEvent", function() wipe(spellVariants) end)

local function IsSpellProcced(spellID)
    if not spellID then return false end

    -- Direct query first, then the ids we captured from the glow events, then
    -- the spell's base / override forms for both.
    for _, id in ipairs(SpellVariants(spellID)) do
        if activeProcSpells[id] or QueryOverlayed(id) then
            return true
        end
    end
    return false
end

-- Create the proc highlight texture. Sizing happens in StyleButton alongside
-- the move-mode glow, so it always matches the node's real size.
local function EnsureProcGlow(btn)
    if btn.procGlow then return btn.procGlow end

    local g = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
    g:SetBlendMode("ADD")
    g:SetVertexColor(1, 0.9, 0.35, 1)
    g:SetSize((btn:GetWidth() or 44) + 16, (btn:GetHeight() or 44) + 16)
    g:Hide()

    -- Gentle pulse so it reads as "ready now" without being distracting.
    -- (Animations are created via CreateAnimation("Alpha"), not CreateAlpha.)
    local anim = g:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    local fade = anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.7)
    fade:SetDuration(0.5)
    fade:SetSmoothing("IN_OUT")
    g.anim = anim

    btn.procGlow = g
    return g
end

-- Size and position the proc glow for a node of the given size. Squares get a
-- noticeably larger halo nudged left and down so it sits over the icon nicely;
-- rings stay centred on the circle.
local function LayoutProcGlow(btn, size, style)
    local g = btn.procGlow
    if not g or not size or size <= 0 then return end

    g:SetSize(size * 1.5, size * 1.5)
    g:ClearAllPoints()
    -- Both centred: the earlier square offset just made it look misaligned.
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

-- Both styles use Blizzard's bright IconAlert glow, unmasked. A circular mask
-- was tried here and looked wrong: it clips the texture's soft outer falloff,
-- turning the glow into a hard-edged ring. Left unmasked, the halo fades out
-- around a round node exactly like it does around a square one.
-- Called from StyleButton, which knows the node's style.
local function SetProcGlowShape(btn, style)
    local g = btn.procGlow
    if not g then return end

    g:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    g:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    -- Clear the mask left over from earlier sessions / style switches.
    if btn.procGlowMasked and btn.procGlowMask then
        g:RemoveMaskTexture(btn.procGlowMask)
        btn.procGlowMasked = false
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Selection highlight. Square nodes use Blizzard's CheckButtonGlow; round ones
-- get a matching circular version built from two masked discs: a gold rim that
-- sits just outside the node, plus a larger faint halo for the soft "shadow"
-- falloff the square glow has.
-- ─────────────────────────────────────────────────────────────────────────
local RING_SELECT_COLOR = { 1, 0.5, 0.05 }   -- orange

local function EnsureRingSelection(btn)
    if btn.ringSelect then return end

    -- Crisp rim: a flat disc clipped to a circle. Drawn under the node art so
    -- only the few pixels extending past the node show — that's the outline.
    local rim = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
    rim:SetPoint("CENTER", btn, "CENTER", 0, 0)
    rim:SetTexture("Interface\\Buttons\\WHITE8X8")
    rim:SetVertexColor(RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3], 1)
    rim:SetBlendMode("ADD")
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(rim)
    rim:AddMaskTexture(mask)
    rim.mask = mask
    rim:Hide()
    btn.ringSelect = rim

    -- Soft halo: IconAlert has a real radial falloff, so it fades outward the
    -- way the square glow does. A masked flat disc can't — it just stops dead
    -- at the circle's edge, which is why this used to look like a hard band.
    local halo = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
    halo:SetPoint("CENTER", btn, "CENTER", 0, 0)
    halo:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    halo:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    halo:SetVertexColor(RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3], 0.85)
    halo:SetBlendMode("ADD")
    halo:Hide()
    btn.ringSelectHalo = halo
end

local function LayoutRingSelection(btn, size)
    if not btn.ringSelect then return end
    -- +2.5 rather than +5: the rim only shows where it extends past the node,
    -- so halving the overhang halves the visible line thickness.
    btn.ringSelect:SetSize(size + 2.5, size + 2.5)
    btn.ringSelect.mask:SetAllPoints(btn.ringSelect)
    btn.ringSelectHalo:SetSize(size * 1.5, size * 1.5)
end

-- Single entry point for "this node is selected", so every caller gets the
-- right shape for the current style.
local function SetNodeSelected(btn, selected, style, colorMode)
    style = style or btn.nodeStyle
    
    local r, g, b = RING_SELECT_COLOR[1], RING_SELECT_COLOR[2], RING_SELECT_COLOR[3]
    if colorMode == "group" then
        r, g, b = 0, 0.6, 1
    end

    if style == "ring" then
        if btn.glow then btn.glow:Hide() end
        if selected then
            EnsureRingSelection(btn)
            LayoutRingSelection(btn, btn:GetWidth() or 44)
            btn.ringSelect:SetVertexColor(r, g, b, 1)
            btn.ringSelectHalo:SetVertexColor(r, g, b, 0.85)
            btn.ringSelect:Show()
            btn.ringSelectHalo:Show()
        else
            if btn.ringSelect then btn.ringSelect:Hide() end
            if btn.ringSelectHalo then btn.ringSelectHalo:Hide() end
        end
        return
    end

    if btn.ringSelect then btn.ringSelect:Hide() end
    if btn.ringSelectHalo then btn.ringSelectHalo:Hide() end
    if btn.glow then
        btn.glow:SetShown(selected and true or false)
        if selected then
            if colorMode == "group" then
                btn.glow:SetVertexColor(0, 0.6, 1, 0.6)
            else
                btn.glow:SetVertexColor(1, 0.82, 0, 0.5)
            end
        end
    end
end

-- Show / hide the pulsing proc highlight on a node.
local function ApplyProcGlow(btn, isProcced)
    if not isProcced then
        if btn.procGlow then
            btn.procGlow:Hide()
            if btn.procGlow.anim then btn.procGlow.anim:Stop() end
        end
        return
    end

    -- Never light up a node that isn't laid out yet: an unsized pooled button
    -- would stretch the texture across the screen.
    local w = btn:GetWidth()
    if not btn:IsShown() or not w or w < 8 then
        if btn.procGlow then btn.procGlow:Hide() end
        return
    end

    local g = EnsureProcGlow(btn)
    -- Already lit at this size and shape: leave it be.
    if g:IsShown() and g._ohWidth == w and g._ohStyle == btn.nodeStyle
        and (not g.anim or g.anim:IsPlaying()) then
        return
    end
    g._ohWidth, g._ohStyle = w, btn.nodeStyle
    SetProcGlowShape(btn, btn.nodeStyle)
    LayoutProcGlow(btn, w, btn.nodeStyle)
    g:Show()
    if g.anim and not g.anim:IsPlaying() then
        g.anim:Play()
    end
end

-- =========================================================================
-- Ready Highlight Glow
-- =========================================================================

local function EnsureReadyGlow(btn)
    if btn.readyGlowSquare then return end

    local square = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    square:SetPoint("CENTER", btn, "CENTER", 0, 0)
    square:SetTexture("Interface\\Buttons\\CheckButtonGlow")
    square:SetBlendMode("ADD")
    square:Hide()
    btn.readyGlowSquare = square

    local rim = btn:CreateTexture(nil, "BACKGROUND", nil, -2)
    rim:SetPoint("CENTER", btn, "CENTER", 0, 0)
    rim:SetTexture("Interface\\Buttons\\WHITE8X8")
    rim:SetBlendMode("ADD")
    local mask = btn:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(rim)
    rim:AddMaskTexture(mask)
    rim.mask = mask
    rim:Hide()
    btn.readyGlowRingRim = rim

    local halo = btn:CreateTexture(nil, "BACKGROUND", nil, -3)
    halo:SetPoint("CENTER", btn, "CENTER", 0, 0)
    halo:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
    halo:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    halo:SetBlendMode("ADD")
    halo:Hide()
    btn.readyGlowRingHalo = halo

    local anim = btn:CreateAnimationGroup()
    anim:SetLooping("BOUNCE")
    btn.readyGlowAnim = anim

    local function MakeFade(key)
        local fade = anim:CreateAnimation("Alpha")
        fade:SetChildKey(key)
        fade:SetSmoothing("IN_OUT")
        fade:SetDuration(1.2)
        return fade
    end

    btn.readyGlowFadeSquare = MakeFade("readyGlowSquare")
    btn.readyGlowFadeRim = MakeFade("readyGlowRingRim")
    btn.readyGlowFadeHalo = MakeFade("readyGlowRingHalo")
end

local function LayoutReadyGlow(btn, size, style)
    if not btn.readyGlowSquare or not size or size <= 0 then return end
    
    local scale = 1.0
    local slot = btn.slotData
    if slot and slot.readyGlowSize then
        scale = slot.readyGlowSize / 100.0
    end
    
    if style == "ring" then
        btn.readyGlowRingRim:SetSize((size + 2.5) * scale, (size + 2.5) * scale)
        btn.readyGlowRingRim.mask:SetAllPoints(btn.readyGlowRingRim)
        btn.readyGlowRingHalo:SetSize((size * 1.5) * scale, (size * 1.5) * scale)
    else
        btn.readyGlowSquare:SetSize((size * 1.7) * scale, (size * 1.7) * scale)
    end
end

local function ApplyReadyGlow(btn, isReady)
    local w = btn:GetWidth()
    if not w or w <= 0 then return end

    local slot = btn.slotData
    if not slot or not slot.showReadyGlow then
        if btn.readyGlowSquare then
            btn.readyGlowSquare:Hide()
            btn.readyGlowRingRim:Hide()
            btn.readyGlowRingHalo:Hide()
            if btn.readyGlowAnim then btn.readyGlowAnim:Stop() end
        end
        return
    end

    if not isReady then
        if btn.readyGlowSquare then
            btn.readyGlowSquare:Hide()
            btn.readyGlowRingRim:Hide()
            btn.readyGlowRingHalo:Hide()
            if btn.readyGlowAnim then btn.readyGlowAnim:Stop() end
        end
        return
    end

    EnsureReadyGlow(btn)

    -- Glowing already, with the same look: nothing to redo. Parsing the colour
    -- and resizing three textures used to happen on every pass.
    -- Field by field: a string key built each pass was garbage every time.
    local look = btn._ohReadyLook
    if not look then
        look = {}
        btn._ohReadyLook = look
    end
    if look.w == w and look.style == btn.nodeStyle and look.hex == slot.readyGlowHex
        and look.alpha == slot.readyGlowAlpha and look.size == slot.readyGlowSize
        and btn.readyGlowAnim:IsPlaying() then
        return
    end
    look.w, look.style, look.hex = w, btn.nodeStyle, slot.readyGlowHex
    look.alpha, look.size = slot.readyGlowAlpha, slot.readyGlowSize

    LayoutReadyGlow(btn, w, btn.nodeStyle)

    local hex = slot.readyGlowHex or "FFFF00"
    local r, gCol, b = 1, 1, 0
    if #hex == 6 then
        local pR = tonumber(string.sub(hex, 1, 2), 16)
        local pG = tonumber(string.sub(hex, 3, 4), 16)
        local pB = tonumber(string.sub(hex, 5, 6), 16)
        if pR and pG and pB then
            r, gCol, b = pR/255, pG/255, pB/255
        end
    end

    local alphaMax = 0.8
    if slot and slot.readyGlowAlpha then
        alphaMax = (slot.readyGlowAlpha / 100.0) * 0.8
    end

    if btn.nodeStyle == "ring" then
        btn.readyGlowRingRim:SetVertexColor(r, gCol, b, 1)
        btn.readyGlowRingHalo:SetVertexColor(r, gCol, b, 0.85)
        
        btn.readyGlowFadeRim:SetFromAlpha(alphaMax)
        btn.readyGlowFadeRim:SetToAlpha(alphaMax * 0.5)
        btn.readyGlowFadeHalo:SetFromAlpha(alphaMax)
        btn.readyGlowFadeHalo:SetToAlpha(alphaMax * 0.5)
        
        btn.readyGlowSquare:Hide()
        btn.readyGlowRingRim:Show()
        btn.readyGlowRingHalo:Show()
    else
        btn.readyGlowSquare:SetVertexColor(r, gCol, b, 1)
        
        btn.readyGlowFadeSquare:SetFromAlpha(alphaMax)
        btn.readyGlowFadeSquare:SetToAlpha(alphaMax * 0.5)
        
        btn.readyGlowSquare:Show()
        btn.readyGlowRingRim:Hide()
        btn.readyGlowRingHalo:Hide()
    end

    if not btn.readyGlowAnim:IsPlaying() then
        btn.readyGlowAnim:Play()
    end
end

local DEFAULT_RANGE_COLOR = { 0.85, 0.25, 0.25 }

local function PaintTexture(tex, desat, r, g, b, alpha)
    if tex.SetDesaturated then tex:SetDesaturated(desat) end
    tex:SetVertexColor(r, g, b)
    tex:SetAlpha(alpha)
end

local function ApplyButtonColoring(btn)
    if not btn then return end

    local usable = (btn._ohUsable ~= false)
    local outOfRange = (btn._ohOutOfRange == true)
    local hubDB = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
        or (btn:GetParent() and btn:GetParent().hubIndex and ActionHub:GetHubDB(btn:GetParent().hubIndex))
        or ActionHub:GetActiveHubDB()

    local r, g, b = 1, 1, 1
    local desat = false
    local alpha = 1

    if outOfRange then
        local rc = (hubDB and hubDB.rangeColor) or DEFAULT_RANGE_COLOR
        r = rc.r or rc[1] or 0.85
        g = rc.g or rc[2] or 0.25
        b = rc.b or rc[3] or 0.25
        desat = false
    elseif not usable and btn._ohNoMana and not (hubDB and hubDB.manaTint == false) then
        -- Short of mana or energy: blue, like the default bars.
        r, g, b = 0.35, 0.45, 1
    elseif not usable then
        r, g, b = 0.4, 0.4, 0.4
        desat = true
    end

    -- Dimmed while on cooldown, when the hub asks for it.
    if btn._ohOnCooldown and hubDB then
        if hubDB.desatOnCooldown then desat = true end
        alpha = hubDB.cooldownAlpha or 1
    end

    if btn._ohColorR == r and btn._ohColorG == g and btn._ohColorB == b
        and btn._ohDesat == desat and btn._ohAlpha == alpha and btn._ohUsableSplit == btn.splitIcon then
        return
    end
    btn._ohColorR, btn._ohColorG, btn._ohColorB = r, g, b
    btn._ohDesat = desat
    btn._ohAlpha = alpha
    btn._ohUsableSplit = btn.splitIcon

    -- No tables here: this runs for every button on every refresh.
    if btn.icon then PaintTexture(btn.icon, desat, r, g, b, alpha) end
    local split = btn.splitIcon
    if split then
        local texs = split.texs
        if texs then
            for i = 1, #texs do PaintTexture(texs[i], desat, r, g, b, alpha) end
        else
            if split.leftTexture then PaintTexture(split.leftTexture, desat, r, g, b, alpha) end
            if split.rightTexture then PaintTexture(split.rightTexture, desat, r, g, b, alpha) end
        end
    end
end

-- Apply / clear the "can't use this right now" dimming on a button's icon(s).
local function ApplyUsabilityShading(btn, usable, noMana)
    usable = usable and true or false
    noMana = noMana and true or false
    if btn._ohUsable == usable and btn._ohNoMana == noMana and btn._ohUsableSplit == btn.splitIcon then return end
    btn._ohUsable = usable
    btn._ohNoMana = noMana
    ApplyButtonColoring(btn)
end

-- How many of an item you carry, in the bottom corner of its node.
local function UpdateItemCount(btn, slot, hub)
    local show = slot and slot.type == "item" and slot.id and not (hub and hub.showItemCount == false)
    local count
    if show and C_Item and C_Item.GetItemCount then
        local ok, value = pcall(C_Item.GetItemCount, tonumber(slot.id), false, true)
        if ok and type(value) == "number" then count = value end
    end
    -- One of something (a trinket, a hearthstone) needs no number.
    if not count or count == 1 then
        if btn.itemCountText then btn.itemCountText:Hide() end
        return
    end
    if not btn.itemCountText then
        btn.itemCountText = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        btn.itemCountText:SetDrawLayer("OVERLAY", 7)
        btn.itemCountText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    end
    btn.itemCountText:SetText(count)
    btn.itemCountText:SetTextColor(count == 0 and 1 or 1, count == 0 and 0.3 or 1, count == 0 and 0.3 or 1)
    btn.itemCountText:Show()
end

function ActionHub:UpdateItemCounts()
    for _, w in ipairs(self.widgets or {}) do
        if w and w.buttons then
            local hub = self:GetHubDB(w.hubIndex)
            for _, btn in ipairs(w.buttons) do
                if btn.slotData and btn.slotData.type == "item" then
                    UpdateItemCount(btn, btn.slotData, hub)
                end
            end
        end
    end
end

local itemCountFrame = CreateFrame("Frame")
itemCountFrame:RegisterEvent("BAG_UPDATE_DELAYED")
itemCountFrame:SetScript("OnEvent", function() ActionHub:UpdateItemCounts() end)

local function GetDirectToyDisplay(itemID)
    local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
    local icon = toyIcon

    if not icon and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    if not icon then
        local _, _, _, _, instantIcon = GetItemInfoInstant(itemID)
        icon = instantIcon
    end

    return toyName, icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function GetActionHubToyMacroText(slot)
    if not slot or slot.type ~= "toy" or not slot.id then
        return ""
    end

    if GetToyAssignmentMode(slot) == "direct" then
        local toyName = GetDirectToyDisplay(slot.id)
        if toyName and PlayerHasToy(slot.id) then
            return "#showtooltip\n/use " .. toyName .. "\n"
        end
        return ""
    end

    local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[slot.id]
    if mixData and OxedHub.Toys and OxedHub.Toys.GetMixMacroText then
        -- resolveRandom=true: this runs on the click's PreClick, so random mode
        -- resolves to a single usable /use <toy> instead of unreliable /castrandom.
        return OxedHub.Toys:GetMixMacroText(mixData, true) or ""
    end

    return ""
end

-- One node's cooldown, charges, dimming and glows. A named function run
-- through pcall, so one bad slot cannot stop the rest of the pass, and so the
-- pass does not build a new closure for every node it touches.
local function UpdateNodeCooldown(btn)
    local slot = btn.slotData
    if not slot then return end

    -- Asked once per node. It used to be looked up four times over.
    local spellID = GetSlotSpellID(slot)

    -- What this node answers to: its spell and that spell's base and override
    -- forms, since the game's event may name any of them. Kept on the node so
    -- a cooldown event about one spell only touches the nodes that show it.
    if btn._ohSpell ~= spellID then
        btn._ohSpell = spellID
        local answers = btn._ohAnswers or {}
        wipe(answers)
        if spellID then
            for _, id in ipairs(SpellVariants(spellID)) do answers[id] = true end
        end
        btn._ohAnswers = answers
    end

    -- Dim icons that can't be used right now (e.g. a mount while
    -- indoors / in a no-mount zone), like the default action bars.
    ApplyUsabilityShading(btn, IsSlotUsable(slot))
    -- Proc glows are left to their own events, coalesced above, and to the
    -- ticker's once-a-second check. Asking here too meant up to eight
    -- protected calls per node on every cooldown change.

    if not (btn.cooldown1 and btn.cooldown2) then return end

    local mixData
    local toyMode = slot.type == "toy" and GetToyAssignmentMode(slot)
    if toyMode == "mix" then
        mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[slot.id]
    elseif slot.type == "emote" then
        local mapping = OxedHub.db.profile.emotionMappings and OxedHub.db.profile.emotionMappings[slot.id]
        if mapping and mapping.toyMacro then
            mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[mapping.toyMacro]
        end
    end

    -- Per-hub: keep the global cooldown off the nodes.
    local hub = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
        or ActionHub:GetActiveHubDB()
    local hideGCD = not (hub and hub.showGlobalCooldown == true)

    local isReady = true
    if type(mixData) == "table" and mixData.slots and toyMode ~= "direct" then
        local mixReady = false
        for i = 1, 2 do
            local cdFrame = i == 1 and btn.cooldown1 or btn.cooldown2
            if PaintNodeCooldown(cdFrame, mixData.slots[i], GetSlotSpellID(mixData.slots[i]), hideGCD) then
                StyleCooldownText(cdFrame, i == 1 and 7 or -7)
            else
                mixReady = true
            end
        end
        isReady = mixReady
    else
        -- A direct toy, a spell, a trigger: one cooldown.
        btn.cooldown2:Hide()
        if PaintNodeCooldown(btn.cooldown1, slot, spellID, hideGCD) then
            StyleCooldownText(btn.cooldown1, 0)
            isReady = false
        end
    end

    -- Charge counter sits outside the branches above: a spell
    -- can bank charges whether or not a cooldown is running.
    UpdateChargeCount(btn, spellID, hub and hub.style)
    UpdateItemCount(btn, slot, hub)

    local onCooldown = not isReady
    if btn._ohOnCooldown ~= onCooldown then
        btn._ohOnCooldown = onCooldown
        ApplyButtonColoring(btn)
    end

    ApplyReadyGlow(btn, isReady)
end

function ActionHub:UpdateWidgetCooldowns()
    for _, w in ipairs(self.widgets or {}) do
        if w and w.buttons then
            for _, btn in ipairs(w.buttons) do
                -- IsVisible rather than IsShown: a node on a hub that is
                -- hidden -- out of combat, closed, moved off -- still says it
                -- is shown, and every one of them was being worked out.
                if btn and btn.slotData and btn:IsVisible() then
                    local okBtn, btnErr = pcall(UpdateNodeCooldown, btn)
                    if not okBtn then
                        CDDebug("node update failed: " .. tostring(btnErr))
                    end
                end
            end
        end
    end
end

-- Refresh only the usable/unusable dimming (cheap: no cooldown maths).
-- Only these can be unusable (see SlotUsableRaw); an emote, a marker, a ping,
-- a macro or a trigger always answers "usable", and asking every one of them
-- on every SPELL_UPDATE_USABLE was most of this pass. Their shading is set
-- when the node is drawn and never changes.
local USABILITY_KINDS = { mount = true, spell = true, toy = true, item = true }

-- ⚠ The every-half-second safety pass. It used to redraw every node; a node
-- with no swipe running cannot change without an event (a cast, a bag or a
-- spell cooldown), and those already redraw it. What can end on its own is a
-- running swipe, so only those nodes are looked at here, plus any node that
-- has never been drawn.
function ActionHub:UpdateRunningCooldowns()
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            if btn and btn.slotData and btn:IsVisible() then
                local cd1, cd2 = btn.cooldown1, btn.cooldown2
                local running = (cd1 and cd1:IsShown()) or (cd2 and cd2:IsShown())
                if running or btn._ohAnswers == nil then
                    local ok, err = pcall(UpdateNodeCooldown, btn)
                    if not ok then CDDebug("node update failed: " .. tostring(err)) end
                end
            end
        end
    end
end

-- includeToys: a toy's usability only changes with the place (indoors,
-- a zone, mounting up), not with the spell-usable stream that arrives several
-- times a second. A hub full of toys asked every one of them on each.
function ActionHub:UpdateUsability(includeToys)
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local slot = btn and btn.slotData
            if slot and USABILITY_KINDS[slot.type] and btn:IsVisible()
                and (includeToys ~= false or slot.type ~= "toy") then
                ApplyUsabilityShading(btn, IsSlotUsable(slot))
            end
        end
    end
end

-- Blizzard fires SPELL_UPDATE_USABLE whenever anything changes what you can
-- cast — including walking in and out of a building, which is what greys out
-- mounts. Waiting for the 0.5s cooldown ticker left nodes stale (and the ticker
-- doesn't run at all when the widget is hidden), so drive it from the events.
local usabilityFrame = CreateFrame("Frame")
usabilityFrame:RegisterEvent("SPELL_UPDATE_USABLE")
usabilityFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
usabilityFrame:RegisterEvent("ZONE_CHANGED")
usabilityFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
usabilityFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
usabilityFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
-- One pass per frame at most. SPELL_UPDATE_USABLE arrives in bursts during a
-- fight -- several for a single button press -- and each used to walk every node
-- on every hub. The recorder counted forty thousand of those passes in an hour.
local usabilityQueued = false
-- A quarter of a second: SPELL_UPDATE_USABLE comes in streams, and each pass
-- asked every node again (0.5 ms, 3286 times in half an hour). An icon greying
-- a moment later is not seen; the pass itself is.
local USABILITY_DELAY = 0.25
-- Named, not a new function per queue: /oxprofile counted the little
-- functions made here, a thousand of them in five minutes.
local usabilityToys = false   -- this pass also looks at toys
local QueueUsability
local function RunUsability()
    usabilityQueued = false
    local toys = usabilityToys
    usabilityToys = false
    if OxedHub.ActionHub and OxedHub.db then OxedHub.ActionHub:UpdateUsability(toys) end
end
QueueUsability = function(withToys)
    if withToys then usabilityToys = true end
    if usabilityQueued then return end
    usabilityQueued = true
    -- A tenth of a second rather than the next frame: SPELL_UPDATE_USABLE
    -- arrives several times a second in a fight, and greying an icon a
    -- moment later is invisible. Eleven thousand passes in half an hour
    -- became a few thousand.
    C_Timer.After(USABILITY_DELAY, RunUsability)
end
local function QueueToysAgain() QueueUsability(true) end

usabilityFrame:SetScript("OnEvent", function(_, event)
    if not OxedHub.ActionHub then return end
    if not OxedHub.db then return end

    if event == "PLAYER_ENTERING_WORLD" then
        OxedHub.ActionHub:RefreshAllWidgets()
        -- A reload, a portal or any loading screen: cooldowns are read again
        -- from scratch, a few times while the game is still loading them.
        OxedHub.ActionHub:RefreshCooldownsAfterLoading()
    end

    -- Toys only when the place changed, not on the spell-usable stream.
    local placeChanged = event ~= "SPELL_UPDATE_USABLE"
    QueueUsability(placeChanged)

    -- Zone transitions can report the old state for a moment, so check again --
    -- but only for those. It used to follow every usability event too, doubling
    -- the work of the busiest event on the list for no reason.
    if placeChanged then
        C_Timer.After(0.3, QueueToysAgain)
    end
end)

-- =========================================================================
-- Range Checking System (Target-Driven, Throttled, Zero CPU Idle)
-- =========================================================================

-- ⚠ In a fight the game may answer these with a secret, and comparing a
-- secret is the error. A secret is "cannot tell" (nil): the node keeps its
-- normal colour rather than the error window filling up.
local function PlainAnswer(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function SafeIsSpellInRange(spellID, unit)
    if not spellID then return nil end
    unit = unit or "target"
    if C_Spell and C_Spell.IsSpellInRange then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, spellID, unit)
        if ok then
            inRange = PlainAnswer(inRange)
            if inRange ~= nil then return inRange end
        end
    end
    if IsSpellInRange then
        local ok, inRange = pcall(IsSpellInRange, spellID, unit)
        if ok then
            inRange = PlainAnswer(inRange)
            if inRange ~= nil then
                return (inRange == 1 or inRange == true)
            end
        end
    end
    return nil
end

-- ⚠ Never in a fight. IsItemInRange is protected in combat: the call raises
-- ADDON_ACTION_BLOCKED for OxedHub even from inside pcall (pcall stops the
-- error, not the report). A node holding an item keeps its normal colour
-- until the fight ends; spells are not protected and still tint.
local function SafeIsItemInRange(itemID, unit)
    if not itemID then return nil end
    if InCombatLockdown() then return nil end
    unit = unit or "target"
    if C_Item and C_Item.IsItemInRange then
        local ok, inRange = pcall(C_Item.IsItemInRange, itemID, unit)
        if ok then
            inRange = PlainAnswer(inRange)
            if inRange ~= nil then return inRange end
        end
    end
    if IsItemInRange then
        local ok, inRange = pcall(IsItemInRange, itemID, unit)
        if ok then
            inRange = PlainAnswer(inRange)
            if inRange ~= nil then
                return (inRange == 1 or inRange == true)
            end
        end
    end
    return nil
end

-- One answer per spell per sweep. Two nodes showing the same spell (a hub
-- for each spec, a mix with a shared toy) used to ask the game twice.
local sweepAnswers = {}
local NO_ANSWER = {}

local function SpellInRangeOnce(spellID, unit)
    local known = sweepAnswers[spellID]
    if known ~= nil then
        if known == NO_ANSWER then return nil end
        return known
    end
    local answer = SafeIsSpellInRange(spellID, unit)
    if answer == nil then
        sweepAnswers[spellID] = NO_ANSWER
    else
        sweepAnswers[spellID] = answer
    end
    return answer
end

-- What a node's range is checked by, worked out once per slot: a spell id,
-- an item id, or false for nothing to check (an emote, a marker, a toy with
-- no spell). Working it out on every sweep -- five times a second, for every
-- node -- was most of what the sweep cost on a big hub. A macro is the
-- exception and is read each time: its spell can change with conditions.
local function RangeSubject(btn, slot)
    if btn._ohRangeFor == slot then
        return btn._ohRangeSpell, btn._ohRangeItem
    end
    local spell, item = false, false
    local slotType = slot.type
    if slotType == "spell" then
        spell = slot.id or false
    elseif slotType == "item" then
        item = slot.id or false
    end
    -- Toys: no range tint. Nearly none of them aims at the target, and
    -- asking for each on every sweep was the cost of a hub full of them.
    btn._ohRangeFor, btn._ohRangeSpell, btn._ohRangeItem = slot, spell, item
    return spell, item
end

local function CheckNodeRange(btn, unit)
    local slot = btn and btn.slotData
    if not slot or not slot.type then return nil end

    if slot.type == "macro" then
        local spellID = btn._ohSpell or GetSlotSpellID(slot)
        if spellID then
            return SpellInRangeOnce(spellID, unit)
        end
        local key = slot.label or slot.id
        if key and GetMacroItem then
            local _, itemLink = GetMacroItem(key)
            if itemLink and GetItemInfoInstant then
                local itemID = GetItemInfoInstant(itemLink)
                if itemID then
                    return SafeIsItemInRange(itemID, unit)
                end
            end
        end
        return nil
    end

    local spell, item = RangeSubject(btn, slot)
    if spell then return SpellInRangeOnce(spell, unit) end
    if item then return SafeIsItemInRange(item, unit) end
    return nil
end

local rangeTicker = nil
local rangeFrame = CreateFrame("Frame")
rangeFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
rangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local function ClearAllRangeTints()
    for _, w in ipairs(ActionHub.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            if btn and btn._ohOutOfRange then
                btn._ohOutOfRange = false
                ApplyButtonColoring(btn)
            end
        end
    end
end

-- true, false, or nil when the game will not say. UnitExists and UnitIsDead
-- can both be secret in a fight, and "not secret" is the error.
local function Answer(fn, unit)
    local ok, value = pcall(fn, unit)
    if not ok or (issecretvalue and issecretvalue(value)) then return nil end
    return value and true or false
end

-- A living target: true, false, or nil for "cannot tell", which keeps the
-- sweep running rather than clearing tints that may well be right.
local function HasLiveTarget()
    local exists = Answer(UnitExists, "target")
    if exists == false then return false end
    local dead = Answer(UnitIsDead, "target")
    if dead == true then return false end
    if exists == nil or dead == nil then return nil end
    return true
end

local function SweepRangeChecks()
    if HasLiveTarget() == false then
        ClearAllRangeTints()
        return false
    end
    wipe(sweepAnswers)

    for _, w in ipairs(ActionHub.widgets or {}) do
        local hubDB = w and w.hubIndex and ActionHub:GetHubDB(w.hubIndex)
        local enabled = not hubDB or (hubDB.enableRangeCheck ~= false)
        if w and w:IsVisible() and w.buttons then
            for _, btn in ipairs(w.buttons) do
                if btn and btn:IsVisible() and btn.slotData then
                    local outOfRange = false
                    if enabled then
                        local inRange = CheckNodeRange(btn, "target")
                        if inRange == false then
                            outOfRange = true
                        end
                    end
                    if btn._ohOutOfRange ~= outOfRange then
                        btn._ohOutOfRange = outOfRange
                        ApplyButtonColoring(btn)
                    end
                end
            end
        end
    end
    return true
end

local function RangeTickerUpdate()
    local hasTarget = SweepRangeChecks()
    if not hasTarget then
        if rangeTicker then
            rangeTicker:Cancel()
            rangeTicker = nil
        end
    end
end

-- Five times a second. It was 0.08 s, twelve and a half sweeps a second over
-- every visible node; a red tint arriving a fifth of a second later is not
-- seen, and the sweep costs two and a half times less.
local RANGE_TICK = 0.25

local function OnTargetChanged()
    if HasLiveTarget() ~= false then
        SweepRangeChecks()
        if not rangeTicker then
            rangeTicker = C_Timer.NewTicker(RANGE_TICK, RangeTickerUpdate)
        end
    else
        ClearAllRangeTints()
        if rangeTicker then
            rangeTicker:Cancel()
            rangeTicker = nil
        end
    end
end

rangeFrame:SetScript("OnEvent", function(_, event)
    if not OxedHub.ActionHub or not OxedHub.db then return end
    OnTargetChanged()
end)

function ActionHub:UpdateRangeChecks()
    OnTargetChanged()
end

-- The spells the proc events of this frame named, and whether one came
-- without a usable id (then every node is checked, as before).
local pendingProcs = {}
local pendingProcAll = false

-- ⚠ Only the nodes that show a spell the events named. A proc refresh sends
-- these events in bursts (176 in one frame was seen), and each pass walked
-- every node asking the game about its spell: 1 ms a pass. A node not drawn
-- yet has no list of the spells it answers to, so it is checked anyway; the
-- ticker's once-a-second check still catches anything missed.
function ActionHub:UpdateProcGlowsFor(spells)
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local answers = btn and btn._ohAnswers
            if btn and btn.slotData and not answers then
                ApplyProcGlow(btn, btn:IsShown() and IsSpellProcced(GetSlotSpellID(btn.slotData)))
            elseif answers then
                for spellID in pairs(spells) do
                    if answers[spellID] then
                        ApplyProcGlow(btn, btn:IsShown() and IsSpellProcced(btn._ohSpell))
                        break
                    end
                end
            end
        end
    end
end

-- Refresh only the proc highlights (cheap: no cooldown maths).
function ActionHub:UpdateProcGlows()
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            if btn and btn:IsShown() and btn.slotData then
                -- The spell the cooldown pass already worked out for the node.
                ApplyProcGlow(btn, IsSpellProcced(btn._ohSpell or GetSlotSpellID(btn.slotData)))
            elseif btn then
                ApplyProcGlow(btn, false)
            end
        end
    end
end

-- Two separate Blizzard systems fire on a proc:
--   *_OVERLAY_GLOW_SHOW/HIDE  → the glow drawn on ACTION BUTTONS (what we want)
--   *_OVERLAY_SHOW/HIDE       → the large screen-edge artwork
-- Register both so a node lights up regardless of which one the spell uses.
local procGlowFrame = CreateFrame("Frame")
local procQueued = false
local function RunProcGlows()
    procQueued = false
    local hub = OxedHub.ActionHub
    if hub then
        if pendingProcAll then
            hub:UpdateProcGlows()
        elseif next(pendingProcs) then
            hub:UpdateProcGlowsFor(pendingProcs)
        end
    end
    pendingProcAll = false
    wipe(pendingProcs)
end
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_SHOW")
procGlowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_HIDE")
procGlowFrame:SetScript("OnEvent", function(_, event, spellID)
    spellID = tonumber(spellID)
    if not spellID then return end

    local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        or (event == "SPELL_ACTIVATION_OVERLAY_SHOW")
    activeProcSpells[spellID] = isShow or nil
    pendingProcs[spellID] = true

    if OxedHub.debug then
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        print(("|cffffcc00[OxedHub-Debug]|r %s spellID=%d (%s)"):format(
            event, spellID, info and info.name or "?"))
    end

    -- One pass per frame. A raid pull or a proc refresh sends these in bursts
    -- of twenty and more in a single frame, each of which used to walk every
    -- node: the recorder caught frames of 29 ms, three quarters of them this.
    if OxedHub.ActionHub and not procQueued then
        procQueued = true
        C_Timer.After(0, RunProcGlows)
    end
end)

-- The 0.5s ticker would eventually pick these up, but a charge spent or a
-- cooldown starting should show immediately rather than up to half a second
-- later.
local cooldownEventFrame = CreateFrame("Frame")
cooldownEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
cooldownEventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
cooldownEventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
-- Coalesced to one pass per frame. These three fire together and repeatedly:
-- one ability press can raise SPELL_UPDATE_COOLDOWN several times plus the
-- charges and bag variants, and every one of them used to redo every node.
-- The first event of a frame schedules the pass; the rest of that frame's
-- events find it already queued. Nothing shows later than before -- the pass
-- still lands on the very next frame.
--
-- ⚠ Only the nodes that changed. This pass was OxedHub's single largest cost
-- -- 1.9 ms and 21 KB of garbage, four times a second in a fight -- because
-- every cooldown event walked every node on every hub. When the event names
-- its spell, only the nodes showing that spell are redrawn; an event that
-- names nothing (the global cooldown, a bag item) still redraws them all, but
-- at most twice a second. A spell cooldown still shows on the next frame.
local cooldownQueued = false
local pendingSpells = {}      -- spellID -> true, gathered over one frame
local pendingAll = false
-- ⚠ BAG_UPDATE_COOLDOWN is about items. It arrived 844 times in five minutes
-- and each asked for a pass over every node, spells included, which is where
-- most of this file's garbage came from (every spell's cooldown is a new table
-- from the game). Only the nodes that can hold an item answer to it now.
local pendingItems = false
local lastItemPass = 0
-- Toys are not here: a toy's cooldown only starts when it is used, and a
-- click on its node already looks again. The bag cooldown event arrives on
-- most casts, and a hub of toys had every one read again each time.
local ITEM_NODES = { item = true, emote = true, macro = true }
local lastFullPass = 0
local FULL_GAP = 0.5          -- the least time between two passes over everything

local function IsSecretValue(value)
    return issecretvalue and issecretvalue(value) or false
end

-- Named for the profiler, so a report says which of the two costs the time.
local function Named(label, fn)
    return OxedHub.Profiler and OxedHub.Profiler:Wrap(label, fn) or fn
end

local UpdateSome = Named("ActionHub: cooldowns, changed spells only", function(spells)
    for _, w in ipairs(ActionHub.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local answers = btn and btn._ohAnswers
            if answers and btn.slotData and btn:IsVisible() then
                for spellID in pairs(spells) do
                    if answers[spellID] then
                        local ok, err = pcall(UpdateNodeCooldown, btn)
                        if not ok then CDDebug("node update failed: " .. tostring(err)) end
                        break
                    end
                end
            end
        end
    end
end)

local UpdateAll = Named("ActionHub: cooldowns, every node", function()
    ActionHub:UpdateWidgetCooldowns()
end)

local UpdateItems = Named("ActionHub: cooldowns, item nodes", function()
    for _, w in ipairs(ActionHub.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            local slot = btn and btn.slotData
            if slot and ITEM_NODES[slot.type] and btn:IsVisible() then
                local ok, err = pcall(UpdateNodeCooldown, btn)
                if not ok then CDDebug("node update failed: " .. tostring(err)) end
            end
        end
    end
end)

local function Flush()
    cooldownQueued = false
    if not (OxedHub.ActionHub and OxedHub.db) then return end

    if next(pendingSpells) then
        UpdateSome(pendingSpells)
        wipe(pendingSpells)
    end

    -- A full pass coming anyway covers the items too.
    -- ⚠ And no more often than FULL_GAP, the same as a full pass. Without it
    -- the item pass ran on every BAG_UPDATE_COOLDOWN, which fires on most
    -- casts: 1387 passes at 1.5 ms in half an hour, on a hub of toys.
    if pendingItems and pendingAll then
        pendingItems = false
    elseif pendingItems then
        local now = GetTime()
        local wait = FULL_GAP - (now - lastItemPass)
        if wait <= 0 then
            pendingItems = false
            lastItemPass = now
            UpdateItems()
        elseif not cooldownQueued then
            cooldownQueued = true
            C_Timer.After(wait, Flush)
        end
    end

    if pendingAll then
        local now = GetTime()
        local wait = FULL_GAP - (now - lastFullPass)
        if wait <= 0 then
            pendingAll = false
            lastFullPass = now
            UpdateAll()
        elseif not cooldownQueued then
            -- Too soon after the last one: the rest of the burst folds into a
            -- single pass when the gap is up.
            cooldownQueued = true
            C_Timer.After(wait, Flush)
        end
    end
end

cooldownEventFrame:SetScript("OnEvent", function(_, event, spellID)
    if event == "BAG_UPDATE_COOLDOWN" then
        pendingItems = true
    elseif (event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES")
        and type(spellID) == "number" and not IsSecretValue(spellID) then
        pendingSpells[spellID] = true
    else
        pendingAll = true
    end
    if cooldownQueued then return end
    cooldownQueued = true
    C_Timer.After(0, Flush)
end)

local REFRESH_DELAYS = { 0.05, 0.2, 0.5, 1.0 }

-- Cooldowns arrive late after a loading screen; these passes catch them.
local AFTER_LOADING = { 0.5, 1.5, 3, 6 }

function ActionHub:ForgetCooldowns()
    for _, w in ipairs(self.widgets or {}) do
        for _, btn in ipairs((w and w.buttons) or {}) do
            for _, cd in ipairs({ btn.cooldown1, btn.cooldown2 }) do
                if cd then cd._ohStart, cd._ohLength, cd._ohSpell = nil, nil, nil end
            end
        end
    end
end
local function RefreshCooldownsLater()
    if OxedHub and OxedHub.ActionHub then
        OxedHub.ActionHub:UpdateWidgetCooldowns()
    end
end

function ActionHub:RefreshCooldownsAfterLoading()
    self:ForgetCooldowns()
    for _, delay in ipairs(AFTER_LOADING) do
        C_Timer.After(delay, RefreshCooldownsLater)
    end
end

-- ⚠ After a click, the node that was clicked, not every node. Each press
-- used to run five full passes over all nodes in the next second (now and at
-- 0.05, 0.2, 0.5 and 1 s): 103 presses in a dungeon were 515 full passes and
-- most of ActionHub's garbage. The cooldown events already redraw the node;
-- these few looks only catch a cooldown the game reports a moment late.
local NODE_REFRESH_DELAYS = { 0.1, 0.4, 1.0 }

function ActionHub:QueueNodeRefresh(btn)
    if not btn then return self:QueueCooldownRefresh() end
    local look = btn._ohLookAgain
    if not look then
        -- Made once per node, so a press makes no new function.
        look = function()
            if btn.slotData and btn:IsVisible() then
                local ok, err = pcall(UpdateNodeCooldown, btn)
                if not ok then CDDebug("node update failed: " .. tostring(err)) end
            end
        end
        btn._ohLookAgain = look
    end
    look()
    for _, delay in ipairs(NODE_REFRESH_DELAYS) do
        C_Timer.After(delay, look)
    end
end

function ActionHub:QueueCooldownRefresh()
    self:UpdateWidgetCooldowns()
    for _, delay in ipairs(REFRESH_DELAYS) do
        C_Timer.After(delay, RefreshCooldownsLater)
    end
end

local function StyleButton(btn, style, size, isPreview)
    -- Remembered so the proc glow can pick a matching shape when it's created
    -- later (it's built lazily, the first time the node actually procs).
    btn.nodeStyle = style
    SetProcGlowShape(btn, style)

    -- Round nodes need a round cooldown sweep, otherwise the dark wedge shows
    -- square corners poking outside the circle.
    for _, cd in ipairs({ btn.cooldown1, btn.cooldown2 }) do
        if cd then
            if cd.SetUseCircularEdge then
                pcall(cd.SetUseCircularEdge, cd, style == "ring")
            end
            if cd.SetSwipeTexture then
                if style == "ring" then
                    cd:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
                else
                    cd:SetSwipeTexture("Interface\\Cooldown\\ping4")
                end
            end
        end
    end

    -- Per-hub background opacity (default 0.5). Lets users fade the dark square /
    -- ring behind an icon (e.g. so an emoji doesn't sit on a black box).
    local styleHubDB = (btn.slotHubIndex and ActionHub:GetHubDB(btn.slotHubIndex))
        or (btn:GetParent() and btn:GetParent().hubIndex and ActionHub:GetHubDB(btn:GetParent().hubIndex))
        or ActionHub:GetActiveHubDB()
    local bgAlpha = 0.5
    if styleHubDB and styleHubDB.nodeBackgroundAlpha ~= nil then
        bgAlpha = styleHubDB.nodeBackgroundAlpha
    end

    local innerSize = style == "ring" and (size - 2) or (size - 4)
    local zoom = (styleHubDB and styleHubDB.iconZoom) or 8
    local iconSize = innerSize + zoom
    btn.icon:SetSize(iconSize, iconSize)
    if btn.splitIcon then
        btn.splitIcon:SetSize(iconSize, iconSize)
        local texs = btn.splitIcon.texs
        if not texs and btn.splitIcon.leftTexture then
            texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
        end
        if texs then
            local numTexs = #texs
            local hw = iconSize / 2
            if numTexs == 2 then
                texs[1]:SetSize(hw, iconSize)
                texs[2]:SetSize(hw, iconSize)
            elseif numTexs == 3 then
                texs[1]:SetSize(hw, iconSize)
                texs[2]:SetSize(hw, hw)
                texs[3]:SetSize(hw, hw)
            elseif numTexs == 4 then
                texs[1]:SetSize(hw, hw)
                texs[2]:SetSize(hw, hw)
                texs[3]:SetSize(hw, hw)
                texs[4]:SetSize(hw, hw)
            end
        end
    end

    if style == "ring" then
        btn:SetBackdrop(nil)
        if not btn.ringBg then
            -- Golden thin border
            btn.ringBg = btn:CreateTexture(nil, "BACKGROUND")
            btn.ringBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            
            btn.ringBgMask = btn:CreateMaskTexture()
            btn.ringBgMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringBgMask:SetAllPoints(btn.ringBg)
            btn.ringBg:AddMaskTexture(btn.ringBgMask)

            -- Dark inner fill
            btn.ringFill = btn:CreateTexture(nil, "BORDER")
            btn.ringFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringFill:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.ringFill:SetVertexColor(0, 0, 0, 0)

            btn.ringFillMask = btn:CreateMaskTexture()
            btn.ringFillMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringFillMask:SetAllPoints(btn.ringFill)
            btn.ringFill:AddMaskTexture(btn.ringFillMask)
            
        end

        -- Ensure masking is applied every refresh (since icons/splitIcons can change)
        if not btn.ringMask then
            btn.ringMask = btn:CreateMaskTexture()
            btn.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        end
        btn.ringMask:ClearAllPoints()
        btn.ringMask:SetAllPoints(btn.ringFill)
        btn.icon:AddMaskTexture(btn.ringMask)
        if btn.plus then btn.plus:AddMaskTexture(btn.ringMask) end
        if btn.squareHighlight then btn.squareHighlight:AddMaskTexture(btn.ringMask) end

        if btn.splitIcon then
            local texs = btn.splitIcon.texs
            if not texs and btn.splitIcon.leftTexture then
                texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
            end
            if texs then
                if not btn.splitMasks then btn.splitMasks = {} end
                local sx, sy = btn.splitIcon:GetSize()
                for i, t in ipairs(texs) do
                    if not btn.splitMasks[i] then
                        btn.splitMasks[i] = btn:CreateMaskTexture(nil, "ARTWORK")
                        btn.splitMasks[i]:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    end
                    btn.splitMasks[i]:ClearAllPoints()
                    btn.splitMasks[i]:SetAllPoints(btn.ringFill)
                    t:AddMaskTexture(btn.splitMasks[i])
                end
            end
        end

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn.ringBg:SetVertexColor(1, 0.95, 0.4, 1)
        else
            -- scaled so the default (bgAlpha 0.5) keeps the original 0.2 look
            btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, bgAlpha * 0.4)
        end
        
        LayoutProcGlow(btn, size, style)
        if btn.glow then
            -- CheckButtonGlow's bright ring sits well inside the texture bounds,
            -- so the texture has to be ~1.7x the node for the ring to land on
            -- the node's edge instead of over the icon.
            btn.glow:SetSize(size * 1.7, size * 1.7)
        end
    else
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, bgAlpha)

        local isSelected = isPreview and btn.slotIndex and ActionHub.pickerDialog and ActionHub.pickerDialog:IsShown() and ActionHub.pickerDialog.slotIndex == btn.slotIndex and ActionHub.pickerDialog.slotSide == btn.slotSide
        if isSelected then
            btn:SetBackdropBorderColor(1, 0.95, 0.4, 1)
        else
            -- fade the border with the opacity slider (scaled so 0.5 keeps 0.8)
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, math.min(1, bgAlpha * 1.6))
        end

        if btn.ringBg then btn.ringBg:Hide() end
        if btn.ringFill then btn.ringFill:Hide() end
        if btn.ringMask then 
            btn.icon:RemoveMaskTexture(btn.ringMask) 
            if btn.plus then btn.plus:RemoveMaskTexture(btn.ringMask) end
            if btn.squareHighlight then btn.squareHighlight:RemoveMaskTexture(btn.ringMask) end
        end
        if btn.splitIcon then
            local texs = btn.splitIcon.texs
            if not texs and btn.splitIcon.leftTexture then
                texs = {btn.splitIcon.leftTexture, btn.splitIcon.rightTexture}
            end
            if texs and btn.splitMasks then
                for i, t in ipairs(texs) do
                    if btn.splitMasks[i] then
                        t:RemoveMaskTexture(btn.splitMasks[i])
                    end
                end
            end
        end
        -- Rings use their own circular selection art instead of the square
        -- CheckButtonGlow, so keep it sized with the node.
        if btn.glow then btn.glow:SetSize(size * 1.7, size * 1.7) end
        LayoutRingSelection(btn, size)
        LayoutProcGlow(btn, size, style)
    end

    btn._ohColorR = nil -- force refresh of colors
    ApplyButtonColoring(btn)
end


-- Handed to the ActionHub files loaded after this one.
Private.ApplyButtonColoring = ApplyButtonColoring
Private.ApplyReadyGlow = ApplyReadyGlow
Private.GetActionHubToyMacroText = GetActionHubToyMacroText
Private.GetDirectToyDisplay = GetDirectToyDisplay
Private.GetMarkerPingIcon = GetMarkerPingIcon
Private.GetMarkerPingMacro = GetMarkerPingMacro
Private.GetToyAssignmentMode = GetToyAssignmentMode
Private.ResolveCustomIcon = ResolveCustomIcon
Private.SetNodeSelected = SetNodeSelected
Private.StyleButton = StyleButton
Private.StyleCooldownText = StyleCooldownText
Private.UpdateBindingLabel = UpdateBindingLabel
