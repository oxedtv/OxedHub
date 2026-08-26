local addonName, OxedHub = ...

-- Toys Module - Toy Management and Mixer
local Toys = {}
OxedHub.Toys = Toys

-- Local references
local L = OxedHub.L
local C_ToyBox = C_ToyBox
local PlayerHasToy = PlayerHasToy
local C_Timer = C_Timer

-- Mixer State
-- Each slot: { type="toy"|"spell", id=number } or nil
local selectedSlots = { nil, nil, nil, nil }

-- Tooltip scanner for item requirements (level, faction, class, race, etc.)
local reqScanTooltip = CreateFrame("GameTooltip", "OxedHubReqScanTooltip", nil, "GameTooltipTemplate")
reqScanTooltip:SetOwner(UIParent, "ANCHOR_NONE")

function Toys:GetItemRequirements(itemID)
    reqScanTooltip:ClearLines()
    reqScanTooltip:SetItemByID(itemID)
    local reqs = {}
    for i = 2, reqScanTooltip:NumLines() do
        local line = _G["OxedHubReqScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text and (
                text:find("^Requires") or
                text:find(" Only$") or
                text:find("^Classes:") or
                text:find("^Races:") or
                text:find("Level %d+")
            ) then
                local r, g, b = line:GetTextColor()
                table.insert(reqs, { text = text, r = r, g = g, b = b })
            end
        end
    end
    return reqs
end

local mixerActions = {
    sound = nil,
    animation = nil,
    chat = nil,
    emote = nil,
}

local mixerRandomToys = false

-- Debug logging (toggle with /oxedhub debug). When on, prints how the addon
-- builds/uses mix macros so random-toy issues can be traced in chat.
Toys.debug = false
function Toys:Debug(...)
    if not self.debug then return end
    print("|cffff9900[OxedHub DBG]|r", ...)
end

-- Pick one random toy name to /use, preferring toys that are OFF cooldown so a
-- press never wastes on a toy that can't fire. Falls back to any toy if all are
-- on cooldown. ids/names are parallel arrays of owned, usable toys.
function Toys:PickUsableRandomToy(ids, names)
    local getCd = (C_Container and C_Container.GetItemCooldown)
        or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
    local ready = {}
    for idx, id in ipairs(ids) do
        local start, duration = 0, 0
        if getCd then start, duration = getCd(id) end
        -- duration <= 0 (or no active cd) means the toy is ready to use
        if not start or start == 0 or (duration or 0) <= 0 then
            table.insert(ready, names[idx])
        end
    end
    local pool = (#ready > 0) and ready or names
    if #pool == 0 then return names[1] end
    local pick = pool[math.random(1, #pool)]
    self:Debug(("  PickUsableRandomToy: %d ready of %d -> %s"):format(#ready, #names, tostring(pick)))
    return pick
end

-- Inspect a spell slot and report the attributes that decide whether a
-- macro line will actually fire (cast time, usability, cooldown, whether it
-- needs a hostile target). This is how we tell why e.g. Wake of Ashes (harmful,
-- needs a target) behaves differently from Divine Shield (self-cast, always ok).
function Toys:DebugSpell(slotIndex, spellId, spellInfo)
    if not self.debug then return end
    local castTime = spellInfo.castTime or 0
    local usable, noMana = C_Spell.IsSpellUsable(spellId)
    local harmful = C_Spell.IsSpellHarmful and C_Spell.IsSpellHarmful(spellId)
    local helpful = C_Spell.IsSpellHelpful and C_Spell.IsSpellHelpful(spellId)
    local cd = C_Spell.GetSpellCooldown(spellId)
    local onCd = cd and cd.duration and type(cd.duration) == "number" and cd.duration > 1.5 and cd.startTime and type(cd.startTime) == "number" and cd.startTime > 0
    self:Debug(("  slot %d: spell id=%s name=%s"):format(slotIndex, tostring(spellId), tostring(spellInfo.name)))
    self:Debug(("    castTime=%dms usable=%s noMana=%s harmful=%s helpful=%s onCooldown=%s"):format(
        castTime, tostring(usable), tostring(noMana), tostring(harmful), tostring(helpful), tostring(onCd)))
    -- The important diagnostic: a spell with a real cast time OR one that needs a
    -- hostile target will grab the press's single cast and can drop the toys.
    if castTime and castTime > 0 then
        self:Debug("    !! has a CAST TIME — it holds the press and blocks /castrandom toys on the same click")
    end
    if harmful then
        self:Debug("    !! HARMFUL spell — needs a valid enemy target; with no target the /cast may error and stop the macro (toys skipped)")
    end
end

-- Resolve action-button labels LAZILY. Building this at file-load time captured
-- raw locale KEYS, because OxedHub.L isn't populated until ApplyLanguage() runs
-- during DB init (and its metatable returns the key itself for missing lookups,
-- defeating the `L[k] or default` fallback). Reading L at call time — plus the
-- `val == key` guard below — makes these labels correct regardless of load order.
local mixerActionLabelDefs = {
    sound     = { key = "TOYS_ACT_ADD_SOUND", default = "Add Sound"     },
    emote     = { key = "TOYS_ACT_ADD_EMOTE", default = "Add Emote"     },
    animation = { key = "TOYS_ACT_ADD_ANIM",  default = "Add Animation" },
    chat      = { key = "TOYS_ACT_ADD_TEXT",  default = "Add Text"      },
}
local function GetMixerActionLabel(actionType)
    local def = mixerActionLabelDefs[actionType]
    if not def then return "" end
    local val = L[def.key]
    -- metatable returns the key string when a translation is missing/not-yet-loaded
    if not val or val == def.key then return def.default end
    return val
end
-- Backwards-compatible accessor: mixerActionButtonText[type] / .sound etc. still work.
local mixerActionButtonText = setmetatable({}, {
    __index = function(_, k) return GetMixerActionLabel(k) end,
})

local MIXER_CONTENT_Y_OFFSET = -40
local MIXER_PREVIEW_MASK_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local MIXER_PREVIEW_RING_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\ring"
local MIXER_PREVIEW_QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function CreateSplitIcon(parent, iconSize, i1, i2, i3, i4)
    local iconFrame = CreateFrame("Frame", nil, parent)
    iconFrame:SetSize(iconSize, iconSize)
    local hw = iconSize / 2

    local numIcons = 0
    if i1 then numIcons = numIcons + 1 end
    if i2 then numIcons = numIcons + 1 end
    if i3 then numIcons = numIcons + 1 end
    if i4 then numIcons = numIcons + 1 end

    iconFrame.texs = {}

    if numIcons <= 2 then
        local t1 = iconFrame:CreateTexture(nil, "ARTWORK")
        t1:SetPoint("LEFT", iconFrame, "LEFT")
        t1:SetSize(hw, iconSize)
        t1:SetTexture(i1)
        t1:SetTexCoord(0, 0.5, 0, 1)

        local t2 = iconFrame:CreateTexture(nil, "ARTWORK")
        t2:SetPoint("RIGHT", iconFrame, "RIGHT")
        t2:SetSize(hw, iconSize)
        t2:SetTexture(i2 or i1)
        t2:SetTexCoord(0.5, 1, 0, 1)

        iconFrame.leftTexture = t1
        iconFrame.rightTexture = t2
        table.insert(iconFrame.texs, t1)
        table.insert(iconFrame.texs, t2)
    elseif numIcons == 3 then
        local t1 = iconFrame:CreateTexture(nil, "ARTWORK")
        t1:SetPoint("LEFT", iconFrame, "LEFT")
        t1:SetSize(hw, iconSize)
        t1:SetTexture(i1)
        t1:SetTexCoord(0, 0.5, 0, 1)

        local t2 = iconFrame:CreateTexture(nil, "ARTWORK")
        t2:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT")
        t2:SetSize(hw, hw)
        t2:SetTexture(i2)
        t2:SetTexCoord(0.5, 1, 0, 0.5)

        local t3 = iconFrame:CreateTexture(nil, "ARTWORK")
        t3:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT")
        t3:SetSize(hw, hw)
        t3:SetTexture(i3)
        t3:SetTexCoord(0.5, 1, 0.5, 1)
        
        table.insert(iconFrame.texs, t1)
        table.insert(iconFrame.texs, t2)
        table.insert(iconFrame.texs, t3)
    else
        local t1 = iconFrame:CreateTexture(nil, "ARTWORK")
        t1:SetPoint("TOPLEFT", iconFrame, "TOPLEFT")
        t1:SetSize(hw, hw)
        t1:SetTexture(i1)
        t1:SetTexCoord(0, 0.5, 0, 0.5)

        local t2 = iconFrame:CreateTexture(nil, "ARTWORK")
        t2:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT")
        t2:SetSize(hw, hw)
        t2:SetTexture(i2)
        t2:SetTexCoord(0.5, 1, 0, 0.5)

        local t3 = iconFrame:CreateTexture(nil, "ARTWORK")
        t3:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT")
        t3:SetSize(hw, hw)
        t3:SetTexture(i3)
        t3:SetTexCoord(0, 0.5, 0.5, 1)

        local t4 = iconFrame:CreateTexture(nil, "ARTWORK")
        t4:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT")
        t4:SetSize(hw, hw)
        t4:SetTexture(i4)
        t4:SetTexCoord(0.5, 1, 0.5, 1)

        table.insert(iconFrame.texs, t1)
        table.insert(iconFrame.texs, t2)
        table.insert(iconFrame.texs, t3)
        table.insert(iconFrame.texs, t4)
    end

    return iconFrame
end

function Toys:CreateSplitIcon(parent, iconSize, i1, i2, i3, i4)
    return CreateSplitIcon(parent, iconSize, i1, i2, i3, i4)
end

local function TruncateText(text, maxLen)
    if not text then return nil end
    maxLen = maxLen or 15
    if #text > maxLen then
        return text:sub(1, maxLen - 3) .. "..."
    end
    return text
end

function Toys:GetSoundDisplayName(soundId)
    if not soundId or soundId == "" then return nil end
    local name = soundId
    local sounds = OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds
    if sounds and sounds[soundId] and sounds[soundId].name then
        name = sounds[soundId].name
    end

    -- Strip "oxedhub_" or "oxedhub " or similar prefix case-insensitively
    name = name:gsub("^[Oo][Xx][Ee][Dd][Hh][Uu][Bb][_%s]*", "")
    name = name:gsub("^[Oo][Xx][Ee][Dd][_%s]*", "")

    -- Strip known category prefixes
    local prefixes = {
        "death_", "dh_pack_", "monk_pack_", "worrier_pack_",
        "anime_", "arabic_", "effects_", "meme_", "legions_", "quote_", "other_"
    }
    local lowerName = name:lower()
    for _, prefix in ipairs(prefixes) do
        if lowerName:sub(1, #prefix) == prefix then
            name = name:sub(#prefix + 1)
            break
        end
    end

    return TruncateText(name, 15)
end


local function GetSafeMixMacroName(mixName)
    local clean = tostring(mixName or "Mix"):gsub("[^%w]", "")
    if clean == "" then clean = "Mix" end

    local hash = 0
    local source = tostring(mixName or "Mix")
    for i = 1, #source do
        hash = (hash + (source:byte(i) or 0) * i) % 10000
    end

    return ("OHM_%s_%04d"):format(clean:sub(1, 7), hash)
end

-- Helper: get both slot icon textures for a mix name
local function GetToyIconTexture(itemID)
    if not itemID then
        return nil
    end

    local _, _, icon = C_ToyBox.GetToyInfo(itemID)
    if icon then
        return icon
    end

    if C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
        if icon then
            return icon
        end
    end

    local _, _, _, _, instantIcon = GetItemInfoInstant(itemID)
    return instantIcon
end

function Toys:GetToyCooldown(itemID)
    if not itemID then return 0 end
    
    self._cdCache = self._cdCache or {}
    if self._cdCache[itemID] then
        return self._cdCache[itemID]
    end
    
    local cd = 0
    local foundInTooltip = false

    -- Parse one tooltip line of plain text; returns seconds or 0.
    -- Scans the parenthesized "(30 Min Cooldown)" segment when present so effect
    -- durations in the same "Use:" sentence don't pollute the value.
    local function ParseCooldownLine(rawText)
        if not rawText then return 0 end
        -- Strip UI escape sequences: texture/atlas tags and color codes embed
        -- numbers that are invisible when rendered but visible to the patterns.
        local cleanText = rawText
            :gsub("|T.-|t", "")
            :gsub("|A.-|a", "")
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|cn.-:", "")
            :gsub("|r", "")
        local lowerText = cleanText:lower()

        local function hasKeyword(s)
            return s:find("cooldown") or s:find("abklingzeit") or s:find("recharge")
                or s:find("восстановление") or s:find("reutilización")
                or s:find("recarga") or s:find("recupero")
        end
        if not hasKeyword(lowerText) then return 0 end

        local scanText = lowerText
        for seg in lowerText:gmatch("%(([^%)]+)%)") do
            if hasKeyword(seg) then
                scanText = seg
                break
            end
        end

        local days = scanText:match("(%d+)%s*day") or scanText:match("(%d+)%s*tag") or scanText:match("(%d+)%s*jour") or scanText:match("(%d+)%s*día") or scanText:match("(%d+)%s*dia")
        local hours = scanText:match("(%d+)%s*hour") or scanText:match("(%d+)%s*hr") or scanText:match("(%d+)%s*std") or scanText:match("(%d+)%s*heure") or scanText:match("(%d+)%s*hora")
        local mins = scanText:match("(%d+)%s*min") or scanText:match("(%d+)%s*мин")
        local secs = scanText:match("(%d+)%s*sec") or scanText:match("(%d+)%s*sek") or scanText:match("(%d+)%s*seg") or scanText:match("(%d+)%s*сек")

        local total = 0
        if days then total = total + tonumber(days) * 86400 end
        if hours then total = total + tonumber(hours) * 3600 end
        if mins then total = total + tonumber(mins) * 60 end
        if secs then total = total + tonumber(secs) end

        if total > 0 and self.debug then
            self:Debug(("  GetToyCooldown[%s]: segment '%s' -> %ds (d=%s h=%s m=%s s=%s)"):format(
                tostring(itemID), scanText, total,
                tostring(days), tostring(hours), tostring(mins), tostring(secs)))
            -- byte dump to expose any invisible characters still fooling the parser
            local bytes = {}
            for bi = 1, math.min(#scanText, 60) do bytes[#bytes + 1] = string.byte(scanText, bi) end
            self:Debug("    bytes: " .. table.concat(bytes, " "))
        end
        return total
    end

    -- Priority 1: hidden GameTooltip scanner with SetToyByItemID — this is the
    -- same rendering path as the real toy tooltip, so it yields plain text and
    -- includes the toy "Use:" line. (C_TooltipInfo.GetItemByID missed the toy
    -- text entirely for many toys and carried invisible rich content that broke
    -- number parsing.)
    if reqScanTooltip.SetToyByItemID then
        reqScanTooltip:ClearLines()
        local ok = pcall(function() reqScanTooltip:SetToyByItemID(itemID) end)
        if ok then
            for i = 1, reqScanTooltip:NumLines() do
                local fs = _G["OxedHubReqScanTooltipTextLeft" .. i]
                local text = fs and fs:GetText()
                if text then
                    local lowerFull = text:lower()
                    if lowerFull:find("retrieving item information") then
                        return 0 -- not loaded yet; don't cache
                    end
                    local total = ParseCooldownLine(text)
                    if total > cd then
                        cd = total
                        foundInTooltip = true
                    end
                end
            end
        end
    end

    -- Priority 1b: C_TooltipInfo as a secondary source if the scanner found nothing
    if not foundInTooltip and C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local tooltipData = C_TooltipInfo.GetItemByID(itemID)
        if tooltipData and tooltipData.lines then
            for _, line in ipairs(tooltipData.lines) do
                if not line.leftText and TooltipUtil and TooltipUtil.SurfaceArgs then
                    pcall(TooltipUtil.SurfaceArgs, line)
                end
                local total = ParseCooldownLine(line.leftText)
                if total > cd then
                    cd = total
                    foundInTooltip = true
                end
            end
        end
    end

    -- Priority 2: Spell Base Cooldown (Fallback if tooltip doesn't explicitly mention it)
    if not foundInTooltip then
        local _, spellID
        if C_Item and C_Item.GetItemSpell then
            _, spellID = C_Item.GetItemSpell(itemID)
        elseif GetItemSpell then
            _, spellID = GetItemSpell(itemID)
        end
        
        if spellID and GetSpellBaseCooldown then
            local spellCD = GetSpellBaseCooldown(spellID)
            if spellCD and spellCD > 0 then
                cd = spellCD / 1000 -- Convert ms to seconds
                self:Debug(("  GetToyCooldown[%s]: fallback spell base cd -> %ds (spellID %s)"):format(
                    tostring(itemID), cd, tostring(spellID)))
            end
        end
    end

    self:Debug(("  GetToyCooldown[%s]: FINAL cd=%ds (source=%s)"):format(
        tostring(itemID), cd, foundInTooltip and "tooltip" or (cd > 0 and "spellBase" or "none")))
    -- Only cache confirmed cooldowns. A cd of 0 may mean "no cooldown" OR "tooltip
    -- not fully loaded yet"; caching 0 would freeze a not-yet-loaded toy into the
    -- wrong bucket. Leaving it uncached lets it resolve on a later grid refresh.
    if cd > 0 then
        self._cdCache[itemID] = cd
    end
    return cd
end

function Toys:GetMixSlotIcons(mixName)
    local mixes = OxedHub.db.profile.toyMixes
    local mixData = mixes and mixes[mixName]
    if type(mixData) ~= "table" or not mixData.slots then
        return "Interface\\Icons\\INV_Misc_QuestionMark",
               "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local icons = {}
    local maxSlots = mixData.randomToys and 4 or 2
    for i = 1, maxSlots do
        local slot = mixData.slots[i]
        if slot then
            if slot.type == "toy" then
                local icon = GetToyIconTexture(slot.id)
                icons[i] = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                icons[i] = (spellInfo and spellInfo.iconID) or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        else
            icons[i] = nil
        end
    end

    if not mixData.randomToys then
        return icons[1] or "Interface\\Icons\\INV_Misc_QuestionMark",
               icons[2] or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    return icons[1] or "Interface\\Icons\\INV_Misc_QuestionMark",
           icons[2] or "Interface\\Icons\\INV_Misc_QuestionMark",
           icons[3],
           icons[4]
end

function Toys:DoesPlayerOwnToy(itemID)
    local id = tonumber(itemID)
    return id and PlayerHasToy(id) == true
end

function Toys:GetMixToyAvailability(mixData)
    local totalToys = 0
    local missingToys = 0

    if type(mixData) ~= "table" then
        return totalToys, missingToys
    end

    for _, slot in ipairs(mixData.slots or {}) do
        if slot and slot.type == "toy" and slot.id then
            totalToys = totalToys + 1
            if not self:DoesPlayerOwnToy(slot.id) then
                missingToys = missingToys + 1
            end
        end
    end

    return totalToys, missingToys
end

local function ApplyMissingVisual(frame, isMissing)
    if not frame then
        return
    end

    if frame.tex then
        if isMissing then
            frame.tex:SetDesaturated(true)
            frame.tex:SetVertexColor(0.45, 0.45, 0.45, 1)
        else
            frame.tex:SetDesaturated(false)
            frame.tex:SetVertexColor(1, 1, 1, 1)
        end
    end

    if frame.SetBackdropBorderColor then
        if isMissing then
            frame:SetBackdropBorderColor(0.7, 0.15, 0.15, 1)
        else
            frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        end
    end
end

-- Initialize
function Toys:Init()
    -- Ensure mixer actions table exists in profile
    if not OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes = {}
    end

    OxedHub.db.profile.toyCollectionCache = OxedHub.db.profile.toyCollectionCache or {
        toyIDs = {},
        toyCache = {},
        stale = false,
    }

    local savedCache = OxedHub.db.profile.toyCollectionCache
    self.toyCache = savedCache.toyCache or {}
    self.toyIDs = savedCache.toyIDs or {}
    self.toyDataInitialized = next(self.toyCache) ~= nil or #self.toyIDs > 0
    self.toyDataDirty = savedCache.stale == true
    self._toyRefreshPending = false

    -- Listen for toy box updates, but do not auto-rescan.
    -- Just mark the saved cache stale so the user can refresh manually.
    if not self._toyEventFrame then
        self._toyEventFrame = CreateFrame("Frame")
        self._toyEventFrame:SetScript("OnEvent", function(_, event)
            if event == "TOYS_UPDATED" then
                Toys.toyDataDirty = true
                local cache = OxedHub.db.profile.toyCollectionCache
                if cache then
                    cache.stale = true
                end
                if Toys.currentMixerScrollChild then
                    Toys:UpdateToyCacheStatus()
                end
            end
        end)
    end
    self._toyEventFrame:RegisterEvent("TOYS_UPDATED")
end

function Toys:EnsureToyData(silent)
    if not self.toyDataInitialized then
        self:CacheToyData(silent)
    end
end

function Toys:PersistToyCache()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then
        return
    end

    profile.toyCollectionCache = profile.toyCollectionCache or {}
    profile.toyCollectionCache.toyIDs = self.toyIDs
    profile.toyCollectionCache.toyCache = self.toyCache
    profile.toyCollectionCache.stale = self.toyDataDirty == true
end

function Toys:UpdateToyCacheStatus()
    if not self.toyCacheStatusText then
        return
    end

    if not self.toyDataInitialized then
        self.toyCacheStatusText:SetText("|cffffcc00" .. (L["TOY_CACHE_EMPTY"] or "Toy cache empty. Click Refresh Toys.") .. "|r")
    elseif self.toyDataDirty then
        self.toyCacheStatusText:SetText("|cffffcc00" .. (L["TOY_CACHE_OUTDATED"] or "Toy cache may be outdated. Click Refresh Toys after learning a new toy.") .. "|r")
    else
        self.toyCacheStatusText:SetText("|cff88ff88" .. (L["TOY_CACHE_SAVED"] or "Using saved toy cache. Refresh only when you learn a new toy.") .. "|r")
    end

    if self.toyCountText then
        local count = #self.toyIDs
        self.toyCountText:SetText("|cffe6d9cc" .. string.format(L["TOY_COLLECTED_COUNT"] or "%d toys collected", count) .. "|r")
    end
end

-- Cache toy names and info (All collected toys)
-- @param silent boolean  If true, suppress chat prints (used by retry loops)
-- Push a freshly built toy cache to every screen that lists toys. Refreshing
-- from any one of them (Toys grid, OxedRing picker, ActionHub picker) now
-- updates the others, so there's no need to hunt for a second Refresh button.
function Toys:RefreshToyConsumers()
    -- Toys tab grid
    pcall(function()
        if self.RefreshCurrentToyGrid then self:RefreshCurrentToyGrid() end
    end)

    -- ActionHub slot picker
    pcall(function()
        if OxedHub.ActionHub and OxedHub.ActionHub.RefreshPickerList then
            OxedHub.ActionHub:RefreshPickerList()
        end
    end)

    -- OxedRing slot picker
    pcall(function()
        if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.RefreshPickerList then
            OxedHub.OxedRingEditor:RefreshPickerList()
        end
    end)
end

function Toys:CacheToyData(silent)
    self.toyCache = {}
    self.toyIDs = {}
    
    -- Save old filter states to restore them later
    local oldCollected = C_ToyBox.GetCollectedShown()
    local oldUncollected = C_ToyBox.GetUncollectedShown()
    local oldUnusable = C_ToyBox.GetUnusableShown()
    
    -- 1. Reset all filters (CollectMe approach)
    C_ToyBox.SetFilterString("")
    C_ToyBox.SetUnusableShown(true) -- Show toys for other classes/profs too
    C_ToyBox.SetCollectedShown(true)
    C_ToyBox.SetUncollectedShown(false)
    
    -- 2. Clear ALL source filters
    if C_ToyBox.SetAllSourceTypeFilters then
        C_ToyBox.SetAllSourceTypeFilters(true)
    end
    
    -- 3. FORCE the game to apply these filters before we scan (Crucial!)
    C_ToyBox.ForceToyRefilter()
    
    -- 4. Get the total count of toys
    local numToys = C_ToyBox.GetNumFilteredToys() or 0
    
    -- 5. Loop through each toy index and grab the itemID
    for i = 1, numToys do
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID and PlayerHasToy(itemID) then
            -- 6. Get detailed info for each toy
            local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
            if toyName then
                -- 7. Store the data in our local cache
                self.toyCache[itemID] = {
                    name = toyName,
                    icon = icon,
                    itemID = itemID,
                }
                table.insert(self.toyIDs, itemID)
            end
        end
    end
    
    -- Restore user's filters
    C_ToyBox.SetCollectedShown(oldCollected)
    C_ToyBox.SetUncollectedShown(oldUncollected)
    C_ToyBox.SetUnusableShown(oldUnusable)
    C_ToyBox.ForceToyRefilter()
    
    -- Active Debug Message (So we know it worked)
    if not silent then
        if #self.toyIDs > 0 then
            -- Scanned account debug hidden
        else
            -- Toy scan retry debug hidden
        end
    end
    
    -- Sort toy IDs by name
    table.sort(self.toyIDs, function(a, b)
        if not self.toyCache[a] or not self.toyCache[b] then return false end
        return self.toyCache[a].name < self.toyCache[b].name
    end)

    self.toyDataInitialized = true
    self.toyDataDirty = false
    self:PersistToyCache()
    self:UpdateToyCacheStatus()
end

function Toys:ShowMixerTab(parent)
    self.currentMixerScrollChild = parent.scrollChild
    self:EnsureToyData(true)

    if OxedHub.UI and OxedHub.UI.searchBox and parent.scrollChild then
        OxedHub.UI.searchBox.customSearchHandler = function(eb, text)
            self:RefreshToyGrid(parent.scrollChild, text or "")
        end
    end

    if parent.initialized then 
        parent:Show()
        return 
    end
    parent.initialized = true

    -- Grid Section
    local gridFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    gridFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    gridFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    gridFrame:SetHeight(165)
    -- gridFrame:SetBackdrop({
    --     bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    --     edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    --     tile = true, tileSize = 16, edgeSize = 12,
    -- })
    -- gridFrame:SetBackdropColor(0.04, 0.03, 0.02, 0.18)
    -- gridFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local filterDropdown = CreateFrame("DropdownButton", "OxedHubToyCooldownFilterDropdown", gridFrame, "WowStyle1DropdownTemplate")

    local refreshBtn = CreateFrame("Button", nil, gridFrame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(110, 24)
    -- Sits immediately to the left of the "All Cooldowns" filter dropdown.
    refreshBtn:SetPoint("RIGHT", filterDropdown, "LEFT", -10, 0)
    refreshBtn:SetText(L["SETTINGS_BTN_REFRESH_TOYS"] or "Refresh Toys")
    refreshBtn:SetScript("OnClick", function()
        self._cdCache = {}  -- force cooldown recompute with fresh tooltip data
        self:CacheToyData()
        if parent.scrollChild then
            self:RefreshToyGrid(parent.scrollChild, OxedHub.globalSearchText or "")
        end
        -- Also update the OxedRing and ActionHub toy pickers.
        self:RefreshToyConsumers()
    end)

    if filterDropdown then
        filterDropdown:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", -65, -14)
        filterDropdown:SetWidth(130)
        
        local filterOptions = {
            { text = L["TOYS_CD_ALL"] or "All Cooldowns", value = 0 },
            { text = L["TOYS_CD_NONE"] or "No Cooldown", value = 1 },
            { text = L["TOYS_CD_LESS_1"] or "< 1 Min", value = 60 },
            { text = L["TOYS_CD_1_5"] or "1 - 5 Mins", value = 300 },
            { text = L["TOYS_CD_5_10"] or "5 - 10 Mins", value = 600 },
            { text = L["TOYS_CD_10_30"] or "10 - 30 Mins", value = 1800 },
            { text = L["TOYS_CD_MORE_30"] or "> 30 Mins", value = 9999 },
        }
        
        local function UpdateCooldownFilterText()
            local val = self.currentCooldownFilter or 0
            for _, opt in ipairs(filterOptions) do
                if opt.value == val then
                    filterDropdown:OverrideText(opt.text)
                    return
                end
            end
            filterDropdown:OverrideText(L["TOYS_CD_ALL"] or "All Cooldowns")
        end
        
        filterDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, opt in ipairs(filterOptions) do
                rootDescription:CreateRadio(opt.text,
                    function() return (self.currentCooldownFilter or 0) == opt.value end,
                    function()
                        self.currentCooldownFilter = opt.value
                        UpdateCooldownFilterText()
                        if parent.scrollChild then
                            self:RefreshToyGrid(parent.scrollChild, OxedHub.globalSearchText or "")
                        end
                    end
                )
            end
        end)
        UpdateCooldownFilterText()
    end

    local toyCountText = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if filterDropdown then
        toyCountText:SetPoint("BOTTOM", filterDropdown, "TOP", 0, 2)
    else
        toyCountText:SetPoint("RIGHT", gridFrame, "RIGHT", -42, 0)
        toyCountText:SetPoint("TOP", refreshBtn, "TOP", 0, -3)
    end
    toyCountText:SetJustifyH("CENTER")
    self.toyCountText = toyCountText

    local cacheStatusText = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- Refresh Toys now lives on the right next to the dropdown, so the status
    -- message fills the freed-up space on the left of the toolbar.
    cacheStatusText:SetPoint("LEFT", gridFrame, "TOPLEFT", 33, -20)
    if refreshBtn then
        cacheStatusText:SetPoint("RIGHT", refreshBtn, "LEFT", -12, 0)
    else
        cacheStatusText:SetPoint("RIGHT", toyCountText, "LEFT", -8, 0)
    end
    cacheStatusText:SetJustifyH("LEFT")
    cacheStatusText:SetTextColor(0.85, 0.85, 0.85, 1)
    self.toyCacheStatusText = cacheStatusText
    
    -- Category tab strip (All + user categories + "+"). Sits between the toolbar
    -- row and the toy grid.
    local tabStrip = CreateFrame("Frame", nil, gridFrame)
    tabStrip:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 45, -40)
    tabStrip:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", -65, -40)
    tabStrip:SetHeight(24)
    self.categoryTabStrip = tabStrip
    self.categoryTabButtons = self.categoryTabButtons or {}

    -- Gold separator line the tabs sit on, matching the Triggers view.
    local tabLine = gridFrame:CreateTexture(nil, "ARTWORK")
    tabLine:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 33, -64)
    tabLine:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", -45, -64)
    tabLine:SetHeight(2)
    tabLine:SetColorTexture(1, 0.82, 0, 0.05) -- match the Triggers view's subtle line

    local scrollFrame = CreateFrame("ScrollFrame", nil, gridFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 45, -68)
    scrollFrame:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", -65, -145)
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:ClearAllPoints()
        scrollFrame.ScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, 2)
        scrollFrame.ScrollBar:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMRIGHT", -35, 55)
    end
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    local toyScrollBar = scrollFrame.oxedMinimalScrollBar or scrollFrame.ScrollBar
    if toyScrollBar then
        toyScrollBar:ClearAllPoints()
        toyScrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, 2)
        toyScrollBar:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMRIGHT", -35, -40)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    parent.scrollChild = scrollChild
    self.currentMixerScrollChild = scrollChild

    -- Mixer Section (CREATE FIRST before blocker)
    local mixerFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    mixerFrame:SetPoint("TOPLEFT", gridFrame, "BOTTOMLEFT", 0, -10)
    mixerFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    mixerFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
    })
    mixerFrame:SetBackdropColor(0, 0, 0, 0)
    mixerFrame:SetBackdropBorderColor(0, 0, 0, 0)
    mixerFrame:SetFrameLevel(gridFrame:GetFrameLevel() + 55)  -- above the blocker (+50)

    local mixerBg = mixerFrame:CreateTexture(nil, "BACKGROUND")
    mixerBg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-bg-low.png")
    mixerBg:SetTexCoord(0, 1, 0, 1)
    mixerBg:SetAlpha(1)
    mixerFrame.backgroundTexture = mixerBg

    -- NOW create the blocker AFTER mixerFrame exists
    local pngBlocker = CreateFrame("Frame", "OxedHubToysDebugBlocker", parent, "BackdropTemplate")
    pngBlocker:SetFrameStrata("DIALOG")  -- same as contentArea
    pngBlocker:SetFrameLevel(110)  -- just above contentArea (102)
    pngBlocker:EnableMouse(true)
    pngBlocker:SetHitRectInsets(0, 0, 0, 0)
    pngBlocker:Show()
    pngBlocker:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    pngBlocker:SetBackdropColor(0, 0, 0, 0)
    
    -- Hide blocker when parent frame hides
    parent:HookScript("OnHide", function()
        pngBlocker:Hide()
    end)
    parent:HookScript("OnShow", function()
        pngBlocker:Show()
    end)

    local function ResizeMixerBackground()
        local frameWidth = mixerFrame:GetWidth() or 0
        local frameHeight = mixerFrame:GetHeight() or 0
        if frameWidth <= 0 or frameHeight <= 0 then
            return
        end

        mixerBg:ClearAllPoints()
        mixerBg:SetPoint("CENTER", mixerFrame, "CENTER", 0, 19 + MIXER_CONTENT_Y_OFFSET)
        local bgW = math.max(1, (frameWidth - 9) * 0.945)
        local bgH = math.max(1, (frameHeight - 14) * 0.735) + 20
        mixerBg:SetWidth(bgW)
        mixerBg:SetHeight(bgH)

        -- Position the pngBlocker to cover the bottom toy rows under the parchment
        local gridWidth = gridFrame:GetWidth() or 800
        local gridHeight = gridFrame:GetHeight() or 165
        local blockerHeight = 100  -- fixed height to cover bottom toy rows
        
        pngBlocker:ClearAllPoints()
        -- Position 100px lower (more down) from the bottom of gridFrame
        -- Inset 50px from left and right
        pngBlocker:SetPoint("BOTTOMLEFT", gridFrame, "BOTTOMLEFT", 50, -(blockerHeight + 100))
        pngBlocker:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMRIGHT", -50, -(blockerHeight + 100))
        pngBlocker:SetHeight(blockerHeight)
    end

    mixerFrame:SetScript("OnSizeChanged", ResizeMixerBackground)
    ResizeMixerBackground()
    
    self:CreateMixerUI(mixerFrame)
    
    -- Hook Search Box (from UI.lua)
    if OxedHub.UI.searchBox and parent.scrollChild then
        OxedHub.UI.searchBox.customSearchHandler = function(eb, text)
            self:RefreshToyGrid(parent.scrollChild, text or "")
        end
    end
    
    self:EnsureToyData(true)
    self:UpdateToyCacheStatus()
    self:RebuildCategoryTabs()
    self:RefreshToyGrid(scrollChild, "")
end

-- Limits for user toy categories (tabs). Declared here so RebuildCategoryTabs
-- and the add/rename helpers below can all see them.
local MAX_TOY_CATEGORIES = 10
local MAX_TOY_CATEGORY_NAME_LEN = 10

-- UTF-8 aware length so Cyrillic / multibyte names count characters, not bytes.
local function toyNameLength(s)
    if strlenutf8 then return strlenutf8(s) end
    return #s
end

-- Build (or rebuild) the category tab strip: "All" + each user category + "+".
-- Uses the exact same PanelTopTabButtonTemplate design as the Triggers tabs
-- (Settings / Zones / Tips).
function Toys:RebuildCategoryTabs()
    local strip = self.categoryTabStrip
    if not strip then return end

    -- Clear previous tab buttons.
    for _, b in ipairs(self.categoryTabButtons or {}) do
        b:Hide()
        b:SetParent(nil)
    end
    self.categoryTabButtons = {}

    local L = OxedHub.L
    local TAB_LINE_ALPHA = 0.25
    local baseLevel = strip:GetFrameLevel() + 10

    -- Mirrors CreateTabButton in TriggerCard.lua so the look matches exactly.
    local function makeTab(label, isSelected, onClick, onRightClick)
        local tab = CreateFrame("Button", nil, strip, "PanelTopTabButtonTemplate")
        tab:SetText(label)
        PanelTemplates_TabResize(tab, 15, nil, 70)

        -- Dim the template's built-in bottom "active" line textures.
        for _, region in ipairs({tab:GetRegions()}) do
            if region.IsObjectType and region:IsObjectType("Texture") then
                local _, relY = region:GetCenter()
                local btnBottom = tab:GetBottom()
                if btnBottom and relY and math.abs(relY - btnBottom) < 8 then
                    region:SetAlpha(TAB_LINE_ALPHA)
                end
            end
        end

        if isSelected then
            PanelTemplates_SelectTab(tab)
            tab:SetFrameLevel(baseLevel + 5)
            -- SelectTab disables the button (default WoW behavior). Re-enable so
            -- clicking the already-active tab can trigger rename.
            tab:Enable()
        else
            PanelTemplates_DeselectTab(tab)
            tab:SetFrameLevel(baseLevel)
        end

        tab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        tab:SetScript("OnClick", function(_, button)
            if button == "RightButton" then
                if onRightClick then onRightClick(tab) end
            else
                if onClick then onClick() end
            end
        end)
        table.insert(self.categoryTabButtons, tab)
        return tab
    end

    local prev

    -- "All" tab (currentToyCategory == nil).
    local allTab = makeTab(L["TOYS_CAT_ALL"] or "All", self.currentToyCategory == nil, function()
        self.currentToyCategory = nil
        self:RebuildCategoryTabs()
        self:RefreshCurrentToyGrid()
    end)
    allTab:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    prev = allTab

    -- One tab per user category. Click selects it; clicking the already-active
    -- tab again opens the rename dialog. Right-click for rename/delete menu.
    local catList = self:GetToyCategories()
    for catIndex, name in ipairs(catList) do
        local catName = name
        local catCount = #catList
        local function RenameThis()
            self:ShowNewCategoryDialog(function(newName)
                self:RenameToyCategory(catName, newName)
                self:RebuildCategoryTabs()
                self:RefreshCurrentToyGrid()
            end, catName, L["TOYS_CAT_RENAME_PROMPT"] or "Rename category:")
        end
        local tab = makeTab(catName, self.currentToyCategory == catName, function()
            if self.currentToyCategory ~= catName then
                self.currentToyCategory = catName
                self:RebuildCategoryTabs()
                self:RefreshCurrentToyGrid()
            end
        end, function(anchor)
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            MenuUtil.CreateContextMenu(anchor, function(_, root)
                root:CreateTitle(catName)
                root:CreateButton(L["TOYS_CAT_RENAME"] or "Rename…", RenameThis)
                if catIndex > 1 then
                    root:CreateButton(L["TOYS_CAT_MOVE_LEFT"] or "Move Left", function()
                        self:MoveToyCategory(catName, -1)
                        self:RebuildCategoryTabs()
                    end)
                end
                if catIndex < catCount then
                    root:CreateButton(L["TOYS_CAT_MOVE_RIGHT"] or "Move Right", function()
                        self:MoveToyCategory(catName, 1)
                        self:RebuildCategoryTabs()
                    end)
                end
                root:CreateButton(L["TOYS_CAT_DELETE"] or "Delete", function()
                    self:DeleteToyCategory(catName)
                    self:RebuildCategoryTabs()
                    self:RefreshCurrentToyGrid()
                end)
            end)
        end)
        tab:SetPoint("LEFT", prev, "RIGHT", 5, 0)
        prev = tab
    end

    -- "+" tab to create a new category (same template, compact width). Always
    -- shown; if the tab limit is reached it just reports so via chat.
    local addTab = makeTab("+", false, function()
        if #self:GetToyCategories() >= MAX_TOY_CATEGORIES then
            UIErrorsFrame:AddMessage("OxedHub: Maximum of " .. MAX_TOY_CATEGORIES .. " toy tabs reached. Delete one first.", 1, 0.2, 0.2)
            return
        end
        self:ShowNewCategoryDialog(function(newName)
            self.currentToyCategory = newName
            self:RebuildCategoryTabs()
            self:RefreshCurrentToyGrid()
        end)
    end)
    addTab:SetPoint("LEFT", prev, "RIGHT", 5, 0)
end

function Toys:ShowLibraryTab(parent)
    local editor = _G["OxedHubMixMacroEditor"]
    if editor and editor:IsShown() then
        editor:Hide()
        local blocker = _G["OxedHubToysDebugBlocker"]
        if blocker then blocker:Show() end
    end

    if self.savedMixesScrollFrame then
        self.savedMixesScrollFrame:Show()
    end

    if self.hideUnavailableCheck then
        self.hideUnavailableCheck:Show()
        self.hideUnavailableCheck:SetChecked(OxedHub.db.profile.settings.hideMissingToys == true)
    end

    if self.mixSortDropdown then
        self.mixSortDropdown:Show()
    end

    if parent.initialized then
        self:RefreshSavedMixesList()
        return
    end
    parent.initialized = true

    local libFrame = CreateFrame("Frame", nil, parent)
    libFrame:SetAllPoints()
    self.libFrame = libFrame
    
    self:CreateSavedMixesUI(libFrame)
end

function Toys:ShowQuickMixesTab(parent)
    if parent.initialized then
        self:RefreshQuickMixesGrid()
        return
    end
    parent.initialized = true

    local gridFrame = CreateFrame("Frame", nil, parent)
    gridFrame:SetAllPoints()

    local title = gridFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 10, -10)
    title:SetText("Quick Mixes")

    self:CreateQuickMixesUI(gridFrame)
end

function Toys:CreateQuickMixesUI(parent)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -40)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -30, 10)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.quickMixesScrollFrame = scrollFrame
    self.quickMixesScrollChild = scrollChild
    self:RefreshQuickMixesGrid()
end


function Toys:RefreshQuickMixesGrid()
    local parent = self.quickMixesScrollChild
    if not parent then return end

    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local mixes = OxedHub.db.profile.toyMixes or {}
    local mixNames = {}
    for name in pairs(mixes) do
        table.insert(mixNames, name)
    end

    local btnSize = 64
    local spacing = 12
    local cols = 4
    local x, y = 0, 0

    for i, mixName in ipairs(mixNames) do
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(btnSize, btnSize)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x * (btnSize + spacing), -y * (btnSize + spacing + 20))
        btn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

        local customIcon = self:GetMixCustomIcon(mixName)
        if customIcon then
            local singleTex = btn:CreateTexture(nil, "ARTWORK")
            singleTex:SetSize(btnSize - 8, btnSize - 8)
            singleTex:SetPoint("CENTER", btn, "CENTER", 0, 6)
            singleTex:SetTexture(customIcon)
            singleTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            local icon1, icon2 = self:GetMixSlotIcons(mixName)
            local splitIcon = CreateSplitIcon(btn, btnSize - 8, icon1, icon2)
            splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 6)
        end

        local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 4)
        label:SetText(mixName)
        label:SetWidth(btnSize - 4)
        label:SetJustifyH("CENTER")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(mixName, 1, 0.82, 0)
            GameTooltip:AddLine("|cff00ff00Click to assign to selected emotion node|r", 0, 1, 0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            local selectedEmotion = ToyRing and ToyRing.GetSelectedEmotion and ToyRing:GetSelectedEmotion()
            if selectedEmotion then
                ToyRing:SetEmotionMapping(selectedEmotion, "toyMacro", mixName)
                print("|cff00ff00[OxedHub]|r Assigned |cffffd100" .. mixName .. "|r to |cffffd100" .. selectedEmotion .. "|r")
                ToyRing:RefreshAssignmentPanel()
                ToyRing:RefreshNodeStyles()
            else
                print("|cffff0000[OxedHub]|r Select an emotion node in the Ring tab first.")
            end
        end)

        x = x + 1
        if x >= cols then
            x = 0
            y = y + 1
        end
    end

    local rows = math.max(math.ceil(#mixNames / cols), 1)
    parent:SetHeight(rows * (btnSize + spacing + 20) + 20)
    parent:SetWidth(cols * (btnSize + spacing))
end

local function RefreshMixConsumers()
    if OxedHub.ActionHub then
        if OxedHub.ActionHub.RefreshPickerList then
            OxedHub.ActionHub:RefreshPickerList()
        end
        if OxedHub.ActionHub.RefreshTab then
            OxedHub.ActionHub:RefreshTab()
        end
        if OxedHub.ActionHub.RefreshAllWidgets then
            OxedHub.ActionHub:RefreshAllWidgets()
        end
    end

    if OxedHub.EmotionRing and OxedHub.EmotionRing.RefreshAssignmentPanel then
        OxedHub.EmotionRing:RefreshAssignmentPanel()
    end

    if OxedHub.ToyRing then
        if OxedHub.ToyRing.RefreshAssignmentPanel then
            OxedHub.ToyRing:RefreshAssignmentPanel()
        end
        if OxedHub.ToyRing.RefreshNodeStyles then
            OxedHub.ToyRing:RefreshNodeStyles()
        end
    end
end

-- ─────────────────────────────────────────────────────────────────────────
-- Custom Toy Categories
-- Users can group their toys into named categories and filter the grid by them
-- via the tab strip. Stored per-profile so they travel with export/import.
-- ─────────────────────────────────────────────────────────────────────────

-- Ordered list of user category names (array). Self-heals the stored list by
-- dropping empty/whitespace names and duplicates (leftovers from earlier builds)
-- so they don't render blank or silently count toward the tab limit.
function Toys:GetToyCategories()
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return {} end
    p.toyCategories = p.toyCategories or {}

    local seen = {}
    local i = 1
    while i <= #p.toyCategories do
        local n = p.toyCategories[i]
        local trimmed = type(n) == "string" and n:gsub("^%s*(.-)%s*$", "%1") or ""
        if trimmed == "" or seen[trimmed] then
            table.remove(p.toyCategories, i)
        else
            if trimmed ~= n then
                p.toyCategories[i] = trimmed
            end
            seen[trimmed] = true
            i = i + 1
        end
    end

    return p.toyCategories
end

-- Map of itemID -> { [categoryName] = true }. A toy may live in several categories.
function Toys:GetToyCategoryAssignments()
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return {} end
    p.toyCategoryAssignments = p.toyCategoryAssignments or {}
    return p.toyCategoryAssignments
end

function Toys:ToyCategoryExists(name)
    for _, n in ipairs(self:GetToyCategories()) do
        if n == name then return true end
    end
    return false
end

function Toys:AddToyCategory(name)
    name = name and name:gsub("^%s*(.-)%s*$", "%1") or ""
    if name == "" then return false end
    if toyNameLength(name) > MAX_TOY_CATEGORY_NAME_LEN then return false end
    if self:ToyCategoryExists(name) then return false end
    if #self:GetToyCategories() >= MAX_TOY_CATEGORIES then
        print("|cffff0000OxedHub:|r Maximum of " .. MAX_TOY_CATEGORIES .. " toy tabs reached.")
        return false
    end
    table.insert(self:GetToyCategories(), name)
    return true
end

function Toys:RenameToyCategory(oldName, newName)
    newName = newName and newName:gsub("^%s*(.-)%s*$", "%1") or ""
    if newName == "" or oldName == newName then return false end
    if toyNameLength(newName) > MAX_TOY_CATEGORY_NAME_LEN then return false end
    if self:ToyCategoryExists(newName) then return false end
    local cats = self:GetToyCategories()
    for i, n in ipairs(cats) do
        if n == oldName then
            cats[i] = newName
            -- Migrate every toy's membership to the new name.
            for _, membership in pairs(self:GetToyCategoryAssignments()) do
                if membership[oldName] then
                    membership[oldName] = nil
                    membership[newName] = true
                end
            end
            if self.currentToyCategory == oldName then
                self.currentToyCategory = newName
            end
            return true
        end
    end
    return false
end

function Toys:DeleteToyCategory(name)
    local cats = self:GetToyCategories()
    for i, n in ipairs(cats) do
        if n == name then
            table.remove(cats, i)
            for _, membership in pairs(self:GetToyCategoryAssignments()) do
                membership[name] = nil
            end
            if self.currentToyCategory == name then
                self.currentToyCategory = nil
            end
            return true
        end
    end
    return false
end

-- Move a category one slot toward the front (dir == -1) or back (dir == 1)
-- in the ordered list. Returns true if the order actually changed.
function Toys:MoveToyCategory(name, dir)
    local cats = self:GetToyCategories()
    for i, n in ipairs(cats) do
        if n == name then
            local j = i + dir
            if j < 1 or j > #cats then return false end
            cats[i], cats[j] = cats[j], cats[i]
            return true
        end
    end
    return false
end

function Toys:IsToyInCategory(itemID, name)
    local m = self:GetToyCategoryAssignments()[itemID]
    return m ~= nil and m[name] == true
end

-- ─────────────────────────────────────────────────────────────────────────
-- Custom toy ordering (drag-and-drop). Each tab keeps its own ordered list of
-- itemIDs. The "All" tab uses the "__all__" key. Toys not present in a stored
-- order fall back to the alphabetical order of self.toyIDs and sit after any
-- explicitly ordered toys. Stored per-profile so it travels with export/import.
-- ─────────────────────────────────────────────────────────────────────────
local ALL_TOYS_ORDER_KEY = "__all__"

function Toys:GetToyOrderKey()
    return self.currentToyCategory or ALL_TOYS_ORDER_KEY
end

function Toys:GetToyOrder(key)
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return {} end
    p.toyOrder = p.toyOrder or {}
    p.toyOrder[key] = p.toyOrder[key] or {}
    return p.toyOrder[key]
end

function Toys:SetToyOrder(key, list)
    local p = OxedHub.db and OxedHub.db.profile
    if not p then return end
    p.toyOrder = p.toyOrder or {}
    p.toyOrder[key] = list
end

-- Sort a list of itemIDs in place by the stored order for the current tab.
-- Toys with a stored rank come first (in that rank order); the rest keep their
-- incoming (alphabetical) order right after them.
function Toys:ApplyToyOrder(list)
    local order = self:GetToyOrder(self:GetToyOrderKey())
    local rank = {}
    for i, id in ipairs(order) do rank[id] = i end
    local n = #order
    local orig = {}
    for i, id in ipairs(list) do orig[id] = i end
    table.sort(list, function(a, b)
        local ra = rank[a] or (n + orig[a])
        local rb = rank[b] or (n + orig[b])
        return ra < rb
    end)
end

-- Full ordered list of toys belonging to the current tab (ignores cooldown /
-- text filters so reordering stays consistent regardless of what's filtered).
function Toys:GetOrderedToysForCurrentTab()
    local list = {}
    for _, id in ipairs(self.toyIDs) do
        if not self.currentToyCategory or self:IsToyInCategory(id, self.currentToyCategory) then
            table.insert(list, id)
        end
    end
    self:ApplyToyOrder(list)
    return list
end

local function indexOfID(t, v)
    for i, x in ipairs(t) do
        if x == v then return i end
    end
end

-- Move sourceID to sit next to targetID within the current tab and persist the
-- resulting order. Dragging forward drops it after the target; dragging back
-- drops it before — so dropping on the first slot lands first, the last lands last.
function Toys:ReorderToy(sourceID, targetID)
    if not sourceID or not targetID or sourceID == targetID then return end
    local list = self:GetOrderedToysForCurrentTab()
    local srcIdx = indexOfID(list, sourceID)
    local tgtIdx = indexOfID(list, targetID)
    if not srcIdx or not tgtIdx then return end
    table.remove(list, srcIdx)
    local newTgt = indexOfID(list, targetID)
    if srcIdx < tgtIdx then
        table.insert(list, newTgt + 1, sourceID)
    else
        table.insert(list, newTgt, sourceID)
    end
    self:SetToyOrder(self:GetToyOrderKey(), list)
end

function Toys:ToggleToyInCategory(itemID, name)
    local assigns = self:GetToyCategoryAssignments()
    assigns[itemID] = assigns[itemID] or {}
    if assigns[itemID][name] then
        assigns[itemID][name] = nil
        if next(assigns[itemID]) == nil then assigns[itemID] = nil end
    else
        assigns[itemID][name] = true
    end
end

-- Refresh the current toy grid using the last search text.
function Toys:RefreshCurrentToyGrid()
    if self.currentMixerScrollChild then
        self:RefreshToyGrid(self.currentMixerScrollChild, OxedHub.globalSearchText or "")
    end
end

-- Context menu shown when right-clicking a toy in the grid: toggle category
-- membership and create new categories inline.
function Toys:ShowToyCategoryMenu(anchorButton, itemID)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local _, toyName = C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID)
    toyName = toyName or ("Toy #" .. itemID)

    MenuUtil.CreateContextMenu(anchorButton, function(owner, root)
        root:CreateTitle(toyName)
        root:CreateButton("|cff00ccff" .. (L["TOYS_WOWHEAD_MENU_BTN"] or "Copy Wowhead URL") .. "|r", function()
            OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", itemID), toyName)
        end)
        root:CreateDivider()
        root:CreateTitle(L["TOYS_CAT_MENU_TITLE"] or "Add to category")
        local cats = self:GetToyCategories()
        if #cats == 0 then
            root:CreateButton(L["TOYS_CAT_NONE_YET"] or "|cff888888No categories yet|r", function() end)
        else
            for _, name in ipairs(cats) do
                root:CreateCheckbox(name,
                    function() return self:IsToyInCategory(itemID, name) end,
                    function()
                        self:ToggleToyInCategory(itemID, name)
                        self:RefreshCurrentToyGrid()
                        return MenuResponse.Refresh
                    end)
            end
        end
        root:CreateDivider()
        root:CreateButton(L["TOYS_CAT_NEW"] or "New category…", function()
            self:ShowNewCategoryDialog(function(newName)
                self:ToggleToyInCategory(itemID, newName)
                self:RebuildCategoryTabs()
                self:RefreshCurrentToyGrid()
            end)
        end)
        
        -- ToyBoxes Grouping Integration
        if self.GetToyBoxes then
            root:CreateDivider()
            root:CreateTitle("|cFFFFD900Add to ToyBox|r")
            local boxes = self:GetToyBoxes()
            for _, box in ipairs(boxes) do
                root:CreateCheckbox(box.name or "Box",
                    function() return self.IsToyInBox and self:IsToyInBox(box.id, itemID) end,
                    function()
                        if self.IsToyInBox and self:IsToyInBox(box.id, itemID) then
                            self:RemoveToyFromBox(box.id, itemID)
                        else
                            self:AddToyToBox(box.id, itemID)
                        end
                        if self.RefreshToyBoxesUI then self:RefreshToyBoxesUI() end
                        return MenuResponse.Refresh
                    end)
            end
        end
    end)
end

-- Simple themed text-entry popup for naming a category (add / rename).
function Toys:ShowNewCategoryDialog(onAccept, initialText, titleText)
    if not StaticPopupDialogs["OXEDHUB_TOY_CATEGORY_NAME"] then
        StaticPopupDialogs["OXEDHUB_TOY_CATEGORY_NAME"] = {
            text = "%s",
            button1 = ACCEPT or "Accept",
            button2 = CANCEL or "Cancel",
            hasEditBox = true,
            maxLetters = 10,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            OnShow = function(dialog, data)
                local eb = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
                if eb then eb:SetText((data and data.initialText) or "") ; eb:HighlightText() end
            end,
            OnAccept = function(dialog, data)
                local eb = dialog.editBox or (dialog.GetEditBox and dialog:GetEditBox())
                local txt = eb and eb:GetText() or ""
                if data and data.callback then data.callback(txt) end
            end,
            EditBoxOnEnterPressed = function(editBox)
                local dialog = editBox:GetParent()
                local data = dialog.data
                local txt = editBox:GetText() or ""
                if data and data.callback then data.callback(txt) end
                dialog:Hide()
            end,
        }
    end
    local data = {
        initialText = initialText,
        callback = function(txt)
            txt = txt and txt:gsub("^%s*(.-)%s*$", "%1") or ""
            if txt == "" then return end
            if initialText then
                -- Rename flow: the caller performs the rename in onAccept.
                if onAccept then onAccept(txt) end
            else
                -- Add flow: create the category here, then let the caller act on it.
                self:AddToyCategory(txt)
                if onAccept then onAccept(txt) end
            end
        end,
    }
    StaticPopup_Show("OXEDHUB_TOY_CATEGORY_NAME",
        titleText or (L["TOYS_CAT_NEW_PROMPT"] or "Enter category name:"), nil, data)
end

-- Refresh Toy Grid
function Toys:RefreshToyGrid(parent, filter)
    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    filter = (filter or ""):lower()
    local sideInset = 12
    local x, y = sideInset, -5
    local spacing = 6
    local iconSize = 44
    local bottomPaddingRows = 2
    local iconsPerRow = math.max(1, math.floor((parent:GetWidth() - (sideInset * 2)) / (iconSize + spacing)))
    local count = 0

    -- Render in the tab's custom (drag-and-drop) order.
    local orderedToys = self:GetOrderedToysForCurrentTab()

    for _, itemID in ipairs(orderedToys) do
        local data = self.toyCache[itemID]
        
        -- Cooldown Filter Logic
        local cd = self:GetToyCooldown(itemID)
        local filterVal = self.currentCooldownFilter or 0
        local passFilter = true
        if filterVal == 1 then
            passFilter = (cd == 0)
        elseif filterVal == 60 then
            passFilter = (cd > 0 and cd < 60)
        elseif filterVal == 300 then
            passFilter = (cd >= 60 and cd <= 300)
        elseif filterVal == 600 then
            passFilter = (cd > 300 and cd <= 600)
        elseif filterVal == 1800 then
            passFilter = (cd > 600 and cd <= 1800)
        elseif filterVal == 9999 then
            passFilter = (cd > 1800)
        end
        
        -- Category filter: when a category tab (not "All") is selected, only show
        -- toys the user has filed into that category.
        if passFilter and self.currentToyCategory then
            passFilter = self:IsToyInCategory(itemID, self.currentToyCategory)
        end

        if passFilter and (filter == "" or data.name:lower():find(filter, 1, true)) then
            local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetSize(iconSize, iconSize)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(iconSize - 6, iconSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(data.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.icon = iconTex

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetToyByItemID(itemID)
                GameTooltip:AddLine("\n|cff00ff00" .. (L["TOYS_CLICK_TO_SELECT_MIXER"] or "Click to select for Mixer") .. "|r")
                GameTooltip:AddLine("|cffffd100" .. (L["TOYS_RIGHTCLICK_CATEGORY"] or "Right-click for Category / Wowhead Link") .. "|r")
                GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function(_, button)
                if button == "RightButton" then
                    if IsShiftKeyDown() then
                        local toyName = data and data.name or ("Toy #" .. itemID)
                        OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", itemID), toyName)
                        return
                    end
                    self:ShowToyCategoryMenu(btn, itemID)
                    return
                end
                local ctype, itemID_cursor = GetCursorInfo()
                if ctype == "item" or ctype == "toy" then
                    self:SelectSlotForMixer("toy", itemID_cursor)
                    ClearCursor()
                else
                    self:SelectSlotForMixer("toy", itemID)
                end
            end)
            
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function()
                PickupItem(itemID)
            end)
            -- Drop another grid toy onto this one to reorder within the tab.
            btn:SetScript("OnReceiveDrag", function()
                local ctype, cid = GetCursorInfo()
                if (ctype == "item" or ctype == "toy") and cid and cid ~= itemID then
                    self:ReorderToy(cid, itemID)
                    ClearCursor()
                    self:RefreshCurrentToyGrid()
                end
            end)

            count = count + 1
            x = x + iconSize + spacing
            if count % iconsPerRow == 0 then
                x = sideInset
                y = y - (iconSize + spacing)
            end
        end
    end
    
    parent:SetHeight(math.abs(y) + iconSize + ((iconSize + spacing) * bottomPaddingRows) + 10)
end

-- Select item for Mixer slot (toy or spell)
function Toys:SelectSlotForMixer(slotType, id, targetSlot)
    if not id then return end
    local newSlot = { type = slotType, id = id }
    -- Prevent duplicate exact slots
    for i = 1, 4 do
        if selectedSlots[i] and selectedSlots[i].type == slotType and selectedSlots[i].id == id then return end
    end

    if targetSlot then
        selectedSlots[targetSlot] = newSlot
    elseif not selectedSlots[1] then
        selectedSlots[1] = newSlot
    elseif not selectedSlots[2] then
        selectedSlots[2] = newSlot
    elseif mixerRandomToys then
        if not selectedSlots[3] then
            selectedSlots[3] = newSlot
        elseif not selectedSlots[4] then
            selectedSlots[4] = newSlot
        else
            -- Shift and replace last slot
            selectedSlots[3] = selectedSlots[4]
            selectedSlots[4] = newSlot
        end
    else
        -- Shift and replace last slot (standard 2-slot mode)
        selectedSlots[1] = selectedSlots[2]
        selectedSlots[2] = newSlot
    end

    if self.UpdateMixerIcons then
        self:UpdateMixerIcons()
    end
end

-- Create Mixer UI
function Toys:CreateMixerUI(frame)
    local iconSize = 53

    local slotChoiceLabel = frame:CreateFontString(nil, 'OVERLAY')
    slotChoiceLabel:SetPoint('TOPLEFT', frame, 'TOPLEFT', 216, -55 + MIXER_CONTENT_Y_OFFSET)
    slotChoiceLabel:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 34)
    slotChoiceLabel:SetText(L["TOY_CHOOSE_SLOT"] or "Choose toy or spell")
    slotChoiceLabel:SetTextColor(0.22, 0.18, 0.17, 1.0)
    
    -- Magical inscription on the parchment using the custom Darling Charm font
    local magicText = frame:CreateFontString(nil, "OVERLAY")
    magicText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 75, 82)
    magicText:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 24)
    magicText:SetText(L["TOYS_DEATHWING_QUOTE"] or "I am the bringer of destruction,\nthe end of all things – inevitable,\nundeniable, and I am the Cataclysm")
    magicText:SetTextColor(0.22, 0.18, 0.17, 1.0)
    magicText:SetJustifyH("LEFT")
    
    -- Slot 1
    local slot1 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot1:SetSize(iconSize, iconSize)
    slot1:SetPoint("TOPLEFT", frame, "TOPLEFT", 237, -89 + MIXER_CONTENT_Y_OFFSET)
    slot1:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot1:SetBackdropColor(0, 0, 0, 0.5)
    
    local icon1 = slot1:CreateTexture(nil, "ARTWORK")
    icon1:SetAllPoints()
    icon1:Hide()

    slot1:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot1:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    slot1:SetScript("OnEnter", function(self)
        local slot = selectedSlots[1]
        if not slot then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
            GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
        elseif slot.type == "spell" then
            local spellInfo = C_Spell.GetSpellInfo(slot.id)
            GameTooltip:SetSpellByID(slot.id)
            if spellInfo then
                GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
            end
        end
        GameTooltip:Show()
    end)
    slot1:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot1:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local slot = selectedSlots[1]
            if IsShiftKeyDown() and slot and slot.type == "toy" then
                local _, toyName = C_ToyBox.GetToyInfo(slot.id)
                OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", slot.id), toyName or ("Toy #" .. slot.id))
                return
            end
            selectedSlots[1] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 1)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 1)
            ClearCursor()
        else
            selectedSlots[1] = nil
            self:UpdateMixerIcons()
        end
    end)
    
    -- Slot 2
    local slot2 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot2:SetSize(iconSize, iconSize)
    slot2:SetPoint("TOPLEFT", frame, "TOPLEFT", 335, -89 + MIXER_CONTENT_Y_OFFSET)
    slot2:SetFrameLevel(frame:GetFrameLevel() + 30)
    slot2:RegisterForClicks("AnyUp")
    slot2:RegisterForDrag("LeftButton")
    slot2:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot2:SetBackdropColor(0, 0, 0, 0.5)
    
    local icon2 = slot2:CreateTexture(nil, "ARTWORK")
    icon2:SetAllPoints()
    icon2:Hide()

    slot2:SetBackdropBorderColor(0.18, 0.58, 1, 1)

    -- (i) info icon: explains that not every toy/spell can be mixed together.
    local mixInfo = CreateFrame("Button", nil, frame)
    mixInfo:SetSize(16, 16)
    mixInfo:SetPoint("BOTTOMLEFT", slot2, "BOTTOMRIGHT", 8, 0)
    mixInfo:SetFrameLevel(slot2:GetFrameLevel() + 5)
    local mixInfoTex = mixInfo:CreateTexture(nil, "ARTWORK")
    mixInfoTex:SetAllPoints()
    mixInfoTex:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    mixInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["MIXER_MIX_INFO_TITLE"] or "Mixing toys & spells", 0.18, 0.58, 1)
        GameTooltip:AddLine(L["MIXER_MIX_INFO_DESC"] or
            "Not all toys can be mixed with spells, and not all spells can be mixed with toys. "
            .. "Some toys play an animation or use a hidden GCD (for example Hunter's Call), so they "
            .. "may not work with your spells. There are 1000+ toys in the game and we keep working on "
            .. "the addon to provide more information per toy to make mixing easier. Meanwhile — experiment "
            .. "and brace yourself!!", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mixInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local spellSlotHint = frame:CreateFontString(nil, 'OVERLAY')
    spellSlotHint:Hide()
    spellSlotHint:SetPoint('LEFT', slot2, 'RIGHT', 4, 1)
    spellSlotHint:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 23)
    spellSlotHint:SetText(L["TOY_SPELL_HINT"] or "Spell")
    spellSlotHint:SetTextColor(0.22, 0.18, 0.17, 1.0)

    local function ShowSpellSlotTooltip(owner)
        local slot = selectedSlots[2]
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["TOY_SECONDARY_SLOT"] or "Secondary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
            GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
        elseif slot.type == "spell" then
            local spellInfo = C_Spell.GetSpellInfo(slot.id)
            GameTooltip:SetSpellByID(slot.id)
            if spellInfo then
                GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
            end
        end
        GameTooltip:Show()
    end

    slot2:SetScript("OnEnter", function(self)
        ShowSpellSlotTooltip(self)
    end)
    slot2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local function HandleSpellSlotClick(_, button)
        if button == "RightButton" then
            local slot = selectedSlots[2]
            if IsShiftKeyDown() and slot and slot.type == "toy" then
                local _, toyName = C_ToyBox.GetToyInfo(slot.id)
                OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", slot.id), toyName or ("Toy #" .. slot.id))
                return
            end
            selectedSlots[2] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        else
            self:ShowSpellPickerForMixer()
        end
    end

    slot2:SetScript("OnClick", HandleSpellSlotClick)

    local spellSlotClickCatcher = CreateFrame("Button", nil, frame)
    spellSlotClickCatcher:SetPoint("TOPLEFT", slot2, "TOPLEFT", 0, 0)
    spellSlotClickCatcher:SetPoint("BOTTOMRIGHT", slot2, "BOTTOMRIGHT", 0, 0)
    spellSlotClickCatcher:SetFrameLevel(frame:GetFrameLevel() + 120)
    spellSlotClickCatcher:RegisterForClicks("AnyUp")
    spellSlotClickCatcher:RegisterForDrag("LeftButton")
    spellSlotClickCatcher:SetScript("OnEnter", function(self)
        ShowSpellSlotTooltip(self)
    end)
    spellSlotClickCatcher:SetScript("OnLeave", function() GameTooltip:Hide() end)
    spellSlotClickCatcher:SetScript("OnClick", HandleSpellSlotClick)
    spellSlotClickCatcher:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    spellSlotClickCatcher:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        end
    end)

    local plus = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    plus:SetPoint("CENTER", slot1, "RIGHT", 11, 0)
    plus:SetText("+")
    plus:SetScale(2)

    -- Pick Spell button
    local pickSpellBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pickSpellBtn:SetSize(100, 20)
    pickSpellBtn:SetPoint("TOP", slot2, "BOTTOM", 0, -6)
    pickSpellBtn:SetText(L["MIXER_PICK_SPELL"] or "Pick Spell")
    pickSpellBtn:SetNormalFontObject("GameFontNormalSmall")
    pickSpellBtn:SetScript("OnClick", function()
        self:ShowSpellPickerForMixer()
    end)
    pickSpellBtn:Hide()

    -- Slot 3 (below slot 1)
    local slot3 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot3:SetSize(iconSize, iconSize)
    slot3:SetPoint("TOP", slot1, "BOTTOM", 0, -30)
    slot3:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot3:SetBackdropColor(0, 0, 0, 0.5)
    slot3:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot3:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon3 = slot3:CreateTexture(nil, "ARTWORK")
    icon3:SetAllPoints()
    icon3:Hide()

    slot3:SetScript("OnEnter", function(self)
        local slot = selectedSlots[3]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_EXTRA_SLOT"] or "Extra Toy Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_EXTRA_SLOT_HELP"] or "Click a toy in the grid to add it here.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_EXTRA_RANDOM_HELP"] or "Enable 'Allow Random Toys' to pick one randomly per use.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
            GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
        end
        GameTooltip:Show()
    end)
    slot3:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot3:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local slot = selectedSlots[3]
            if IsShiftKeyDown() and slot and slot.type == "toy" then
                local _, toyName = C_ToyBox.GetToyInfo(slot.id)
                OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", slot.id), toyName or ("Toy #" .. slot.id))
                return
            end
            selectedSlots[3] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 3)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 3)
            ClearCursor()
        else
            selectedSlots[3] = nil
            self:UpdateMixerIcons()
        end
    end)
    slot3:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 3)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 3)
            end
            ClearCursor()
        end
    end)

    -- Plus sign between slot 3 and slot 4
    local plus2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    plus2:SetPoint("CENTER", slot3, "RIGHT", 11, 0)
    plus2:SetText("+")
    plus2:SetScale(2)

    -- Vertical Plus sign between top row and bottom row (left side)
    local plus3 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    plus3:SetPoint("CENTER", slot1, "BOTTOM", 0, -9)
    plus3:SetText("+")
    plus3:SetScale(2)

    -- Note: slot3, plus2, plus3, slot4 hidden by default via UpdateRandomSlotsVisibility() below

    -- Slot 4 (below slot 2)
    local slot4 = CreateFrame("Button", nil, frame, "BackdropTemplate")
    slot4:SetSize(iconSize, iconSize)
    slot4:SetPoint("TOP", slot2, "BOTTOM", 0, -30)
    slot4:SetFrameLevel(frame:GetFrameLevel() + 30)
    slot4:RegisterForClicks("AnyUp")
    slot4:RegisterForDrag("LeftButton")
    slot4:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    slot4:SetBackdropColor(0, 0, 0, 0.5)
    slot4:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

    local icon4 = slot4:CreateTexture(nil, "ARTWORK")
    icon4:SetAllPoints()
    icon4:Hide()

    slot4:SetScript("OnEnter", function(self)
        local slot = selectedSlots[4]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_EXTRA_SLOT"] or "Extra Toy Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_EXTRA_SLOT_HELP"] or "Click a toy in the grid to add it here.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_EXTRA_RANDOM_HELP"] or "Enable 'Allow Random Toys' to pick one randomly per use.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
            GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
        end
        GameTooltip:Show()
    end)
    slot4:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot4:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local slot = selectedSlots[4]
            if IsShiftKeyDown() and slot and slot.type == "toy" then
                local _, toyName = C_ToyBox.GetToyInfo(slot.id)
                OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", slot.id), toyName or ("Toy #" .. slot.id))
                return
            end
            selectedSlots[4] = nil
            self:UpdateMixerIcons()
            return
        end
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 4)
            end
            ClearCursor()
        elseif ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 4)
            ClearCursor()
        else
            selectedSlots[4] = nil
            self:UpdateMixerIcons()
        end
    end)
    slot4:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 4)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 4)
            end
            ClearCursor()
        end
    end)

    -- Actions Section
    local yOffset = -75 + MIXER_CONTENT_Y_OFFSET
    
    local function CreateActionRow(label, type)
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(180, 26)
        row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -72, yOffset)

        local btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        btn:SetSize(126, 22)
        btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        btn:SetText(label)
        
        btn:SetScript("OnClick", function()
            self:ShowPickerForMixer(type, btn)
        end)

        local iconBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        iconBtn:SetSize(22, 22)
        iconBtn:SetPoint("RIGHT", btn, "LEFT", -8, 0)
        iconBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        iconBtn:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        iconBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

        local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetPoint("TOPLEFT", iconBtn, "TOPLEFT", 2, -2)
        iconTex:SetPoint("BOTTOMRIGHT", iconBtn, "BOTTOMRIGHT", -2, 2)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        
        local iconPaths = {
            sound = "Interface\\Icons\\INV_Misc_Horn_01",
            emote = "Interface\\Icons\\UI_Chat",
            animation = "Interface\\Icons\\Ability_Rogue_Sprint",
            chat = "Interface\\Icons\\INV_Misc_Note_01",
        }
        iconTex:SetTexture(iconPaths[type] or "Interface\\Icons\\INV_Misc_QuestionMark")

        iconBtn:SetScript("OnClick", function()
            self:ShowPickerForMixer(type, btn)
        end)
        
        iconBtn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
        end)
        iconBtn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end)
        
        yOffset = yOffset - 30
        return btn
    end
    
    local soundBtn = CreateActionRow(L["TOYS_ACT_ADD_SOUND"] or "Add Sound", "sound")
    local emotionBtn = CreateActionRow(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote", "emote")
    local animBtn = CreateActionRow(L["TOYS_ACT_ADD_ANIM"] or "Add Animation", "animation")
    local textBtn = CreateActionRow(L["TOYS_ACT_ADD_TEXT"] or "Add Text", "chat")

    -- Allow Random Toys checkbox row
    local randomRow = CreateFrame("Frame", nil, frame)
    randomRow:SetSize(180, 26)
    randomRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -72, yOffset)

    -- Checkbox (aligned exactly with the icons above it)
    local randomCheck = CreateFrame("CheckButton", nil, randomRow, "UICheckButtonTemplate")
    randomCheck:SetSize(24, 24)
    randomCheck:SetPoint("RIGHT", randomRow, "RIGHT", -132, 0)
    randomCheck:SetChecked(mixerRandomToys)

    -- (i) info button on top right corner of the checkbox
    local randomInfo = CreateFrame("Button", nil, randomRow)
    randomInfo:SetSize(12, 12)
    randomInfo:SetPoint("CENTER", randomCheck, "TOPRIGHT", -5, -5)
    randomInfo:SetFrameLevel(randomCheck:GetFrameLevel() + 2)
    local randomInfoTex = randomInfo:CreateTexture(nil, "ARTWORK")
    randomInfoTex:SetAllPoints()
    randomInfoTex:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    randomInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["MIXER_RANDOM_TITLE"] or "Random Toys Mode", 1, 0.82, 0)
        GameTooltip:AddLine(L["MIXER_RANDOM_DESC1"] or "When enabled, the macro will use /castrandom to pick ONE random toy from all filled toy slots each time you press it.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["MIXER_RANDOM_DESC2"] or "When disabled, all toys fire sequentially (standard WoW behavior — only the first available toy on GCD will activate).", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(" ")
        local desc3 = L["MIXER_RANDOM_DESC3"] or "Note: If you add multiple toys and enable this, it will only ever pick ONE toy. It cannot pick a random pair of toys."
        GameTooltip:AddLine(desc3, 1, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    randomInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Label to the right of the checkbox
    local randomLabel = randomRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    randomLabel:SetPoint("LEFT", randomCheck, "RIGHT", 8, 0)
    local font, size, flags = randomLabel:GetFont()
    randomLabel:SetFont(font, size + 1, "")
    randomLabel:SetShadowColor(0, 0, 0, 0)
    randomLabel:SetText(L["MIXER_RANDOM_TOYS"] or "Random Toys")
    randomLabel:SetTextColor(0.22, 0.18, 0.17, 1.0)

    -- Toggle slot 3/4 visibility + randomToys state
    local function UpdateRandomSlotsVisibility()
        if mixerRandomToys then
            slot3:Show()
            plus2:Show()
            plus3:Show()
            slot4:Show()
        else
            slot3:Hide()
            plus2:Hide()
            plus3:Hide()
            slot4:Hide()
            -- Clear extra slots when disabling random
            selectedSlots[3] = nil
            selectedSlots[4] = nil
        end
    end

    randomCheck:SetScript("OnClick", function(self)
        mixerRandomToys = self:GetChecked()
        UpdateRandomSlotsVisibility()
        if Toys.UpdateMixerIcons then Toys:UpdateMixerIcons() end
    end)

    self.mixerRandomCheck = randomCheck
    self.UpdateRandomSlotsVisibility = UpdateRandomSlotsVisibility
    UpdateRandomSlotsVisibility()
    
    -- Macro Section (Internal Mix Panel)
    local macroFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    macroFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 447, -48 + MIXER_CONTENT_Y_OFFSET)
    macroFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -51, 75 + MIXER_CONTENT_Y_OFFSET)
    macroFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
    })
    macroFrame:SetBackdropColor(0, 0, 0, 0)
    macroFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local macroBg = macroFrame:CreateTexture(nil, "BACKGROUND")
    macroBg:SetAllPoints(macroFrame)
    macroBg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\toys-mix-bg.png")
    macroBg:SetTexCoord(0, 1, 0, 1)
    macroBg:Hide()
    macroFrame.backgroundTexture = macroBg

    local macroText = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroText:SetPoint("TOP", macroFrame, "TOP", 0, -15)
    macroText:SetText(L["TOY_INTERNAL_MIX"] or "Internal Mix")
    macroText:Hide()

    local macroIcon = CreateFrame("Button", nil, macroFrame)
    macroIcon:SetSize(88, 88)
    macroIcon:SetPoint("CENTER", frame, "CENTER", -5, 43 + MIXER_CONTENT_Y_OFFSET)
    macroIcon:EnableMouse(true)
    macroIcon:RegisterForDrag("LeftButton")

    -- Ring Animation Texture - RIGHT UNDER the split icons (ARTWORK layer, sublayer -1)
    local animTex = macroIcon:CreateTexture(nil, "ARTWORK", nil, -1)
    animTex:SetPoint("CENTER", macroIcon, "CENTER", 0, 0)  -- Moved right 5px
    animTex:SetSize(344, 344)  -- 30% smaller (originally 492x492), 1:1 aspect ratio
    animTex:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_00001.png")
    animTex:SetBlendMode("ADD")
    animTex:SetAlpha(0.8)
    animTex:Hide()
    macroIcon.animTex = animTex
    macroIcon.animFrame = 1
    macroIcon.animTime = 0

    local macroIconFill = macroIcon:CreateTexture(nil, "BACKGROUND")
    macroIconFill:SetPoint("CENTER", macroIcon, "CENTER")
    macroIconFill:SetSize(76, 76)
    macroIconFill:SetTexture("Interface\\Buttons\\WHITE8X8")
    macroIconFill:SetVertexColor(0.02, 0.02, 0.02, 0.7)

    local macroIconFillMask = macroIcon:CreateMaskTexture(nil, "BACKGROUND")
    macroIconFillMask:SetAllPoints(macroIconFill)
    macroIconFillMask:SetTexture(MIXER_PREVIEW_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    macroIconFill:AddMaskTexture(macroIconFillMask)

    local macroIconRing = macroIcon:CreateTexture(nil, "BORDER")
    macroIconRing:SetPoint("CENTER", macroIcon, "CENTER")
    macroIconRing:SetSize(80, 80)
    macroIconRing:SetTexture(MIXER_PREVIEW_RING_TEXTURE)
    macroIconRing:Hide()

    local macroIconSize = 83
    macroIcon.slices = {}
    for i = 1, 4 do
        local slice = macroIcon:CreateTexture(nil, "ARTWORK")
        slice:Hide()
        
        local mask = macroIcon:CreateMaskTexture(nil, "ARTWORK")
        mask:SetPoint("CENTER", macroIcon, "CENTER")
        mask:SetSize(76, 76)
        mask:SetTexture(MIXER_PREVIEW_MASK_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        
        slice:AddMaskTexture(mask)
        macroIcon.slices[i] = slice
    end

    local macroQuestionText = macroIcon:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    macroQuestionText:SetPoint("CENTER", macroIcon, "CENTER", 0, -1)
    macroQuestionText:SetText("?")
    macroQuestionText:SetTextColor(1, 0.12, 0.08, 1)
    macroQuestionText:SetFont(OxedHub:GetFont("Fonts\\FRIZQT__.ttf"), 52, "OUTLINE")
    macroIcon.questionText = macroQuestionText

    macroIcon:SetScript("OnMouseDown", function()
        Toys:CreateInternalMixMacro()
    end)
    macroIcon:SetScript("OnDragStart", function()
        local macroName = Toys:CreateInternalMixMacro(true)
        if macroName then
            local index = GetMacroIndexByName(macroName)
            if index > 0 then
                PickupMacro(index)
            end
        end
    end)
    macroIcon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["TOY_MIX_MACRO"] or "Mix Macro")
        GameTooltip:AddLine(L["MIXER_MACRO_HELP1"] or "Drag this icon to your action bar to use this mix.", 1, 1, 1, true)
        GameTooltip:AddLine(L["MIXER_MACRO_HELP2"] or "Click refreshes or creates the character macro.", 0, 1, 0, true)
        GameTooltip:AddLine(L["MIXER_MACRO_HELP3"] or "This will use 1 character macro slot.", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    macroIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Animation OnUpdate script
    macroIcon:SetScript("OnUpdate", function(self, elapsed)
        -- Animate if at least 2 slots are filled
        local filledCount = 0
        for i = 1, 4 do if selectedSlots[i] then filledCount = filledCount + 1 end end
        if filledCount >= 2 and self.animTex then
            if not self.animStarted then
                self.animStarted = true
            end
            self.animTex:Show()
            
            self.animTime = (self.animTime or 0) + elapsed
            local fps = 30  -- SPEED: Change this number to adjust animation speed (frames per second)
            local frameDuration = 1 / fps
            
            if self.animTime >= frameDuration then
                self.animTime = self.animTime - frameDuration
                self.animFrame = (self.animFrame or 1) + 1
                if self.animFrame > 18 then  -- 18 frames total
                    self.animFrame = 1  -- Loop back to first frame
                end
                
                -- Update texture to current frame
                self.animTex:SetTexture(string.format(
                    "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_%05d.png", self.animFrame))
            end
        else
            -- Hide animation if slots not filled
            if self.animTex then
                self.animTex:Hide()
            end
            self.animFrame = 1
            self.animTime = 0
            self.animStarted = false
        end
    end)

    local macroReqs = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    macroReqs:SetPoint("BOTTOM", macroIcon, "TOP", 0, 52)
    macroReqs:SetWidth(280)
    macroReqs:SetJustifyH("CENTER")
    macroReqs:Hide()
    self.mixerReqs = macroReqs

    local macroHint = macroFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    macroHint:SetPoint("BOTTOM", macroFrame, "BOTTOM", 0, 20)
    macroHint:SetText("Click Run to execute")

    -- Run Mix button - HIDDEN (functionality removed per user request)
    local runBtn = CreateFrame("Button", "OxedHubRunMixButton", macroFrame, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    runBtn:SetSize(86, 24)
    runBtn:SetPoint("CENTER", frame, "CENTER", -5, -87 + MIXER_CONTENT_Y_OFFSET)
    runBtn:SetText("Run Mix")
    runBtn:Hide()  -- Hidden per user request
    
    macroHint:ClearAllPoints()
    macroHint:SetPoint("TOP", runBtn, "BOTTOM", 0, -3)
    macroHint:Hide()  -- Hide the hint text too

    local saveBtn = CreateFrame("Button", nil, macroFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(110, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", macroFrame, "BOTTOMRIGHT", -39, 48)
    saveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix")
    saveBtn:SetScript("OnClick", function()
        local hasAny = false
        for i = 1, 4 do if selectedSlots[i] then hasAny = true; break end end
        if not hasAny then
            print("|cffff0000OxedHub:|r Select a toy or spell first!")
            return
        end
        self:SaveMix()
        print("|cff00ff00OxedHub:|r Mix saved successfully!")
    end)
    self.mixerSaveBtn = saveBtn

    -- Subtle flavor text above "Save Mix" using Ronthel Brush DEMO font
    local goWrongText = macroFrame:CreateFontString(nil, "OVERLAY")
    goWrongText:SetPoint("BOTTOMRIGHT", saveBtn, "TOPRIGHT", 10, 8)
    goWrongText:SetFont(OxedHub:GetFont("Interface\\AddOns\\OxedHub\\Media\\Fonts\\Ronthel Brush DEMO.otf"), 20)
    goWrongText:SetText(L["TOY_GO_WRONG"] or "What could possibly go wrong?")
    goWrongText:SetTextColor(0.22, 0.18, 0.17, 1.0)
    goWrongText:SetJustifyH("RIGHT")

    -- New Mix button: always visible under the ring to start a new mix
    local newMixBtn = CreateFrame("Button", nil, macroFrame, "UIPanelButtonTemplate")
    newMixBtn:SetSize(86, 26)
    newMixBtn:SetPoint("TOP", macroIcon, "BOTTOM", 0, -60)
    newMixBtn:SetText(L["TOY_NEW_MIX"] or "New Mix")
    newMixBtn:SetScript("OnClick", function()
        for i = 1, 4 do selectedSlots[i] = nil end
        for k in pairs(mixerActions) do mixerActions[k] = nil end
        mixerRandomToys = false
        if self.mixerRandomCheck then self.mixerRandomCheck:SetChecked(false) end
        if self.UpdateRandomSlotsVisibility then self:UpdateRandomSlotsVisibility() end
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        self.editingMixName = nil
        self.currentMixName = nil
        if self.mixerSaveBtn then self.mixerSaveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix") end
        if self.mixerSoundBtn then self.mixerSoundBtn:SetText(L["TOYS_ACT_ADD_SOUND"] or "Add Sound") end
        if self.mixerEmoteBtn then self.mixerEmoteBtn:SetText(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote") end
        if self.mixerAnimBtn then self.mixerAnimBtn:SetText(L["TOYS_ACT_ADD_ANIM"] or "Add Animation") end
        if self.mixerChatBtn then self.mixerChatBtn:SetText(L["TOYS_ACT_ADD_TEXT"] or "Add Text") end
        print("|cff00ff00[OxedHub]|r Mixer cleared. Select items to create a new mix.")
    end)
    self.mixerNewMixBtn = newMixBtn
    
    -- Helper to update icons
    self.UpdateMixerIcons = function()
        local firstIcon = nil
        local secondIcon = nil

        -- Update all 4 slot icons
        local slotIcons = { icon1, icon2, icon3, icon4 }
        local filledIcons = {}

        for i = 1, 4 do
            if selectedSlots[i] then
                local slotIcon = nil
                if selectedSlots[i].type == "toy" then
                    local _, _, ic = C_ToyBox.GetToyInfo(selectedSlots[i].id)
                    slotIcons[i]:SetTexture(ic)
                    slotIcon = ic
                else
                    local spellInfo = C_Spell.GetSpellInfo(selectedSlots[i].id)
                    slotIcon = spellInfo and spellInfo.iconID or nil
                    slotIcons[i]:SetTexture(slotIcon or MIXER_PREVIEW_QUESTION_ICON)
                end
                slotIcons[i]:Show()
                if slotIcon then table.insert(filledIcons, slotIcon) end
            else
                slotIcons[i]:Hide()
            end
        end

        local numFilled = #filledIcons
        local size = 83
        local hw = (size / 2) + 2

        -- Hide spell slot hint when any slots are filled
        spellSlotHint:Hide()

        -- Reset all slices
        if macroIcon.slices then
            for i = 1, 4 do
                if macroIcon.slices[i] then macroIcon.slices[i]:Hide() end
            end
            
            if numFilled == 1 then
                local s = macroIcon.slices[1]
                s:ClearAllPoints()
                s:SetPoint("CENTER", macroIcon, "CENTER")
                s:SetSize(size, size)
                s:SetTexCoord(0, 1, 0, 1)
                s:SetTexture(filledIcons[1])
                s:Show()
            elseif numFilled == 2 then
                local s1 = macroIcon.slices[1]
                s1:ClearAllPoints()
                s1:SetPoint("LEFT", macroIcon, "LEFT", 1, 0)
                s1:SetSize(hw, size)
                s1:SetTexCoord(0, 0.5, 0, 1)
                s1:SetTexture(filledIcons[1])
                s1:Show()

                local s2 = macroIcon.slices[2]
                s2:ClearAllPoints()
                s2:SetPoint("RIGHT", macroIcon, "RIGHT", -1, 0)
                s2:SetSize(hw, size)
                s2:SetTexCoord(0.5, 1, 0, 1)
                s2:SetTexture(filledIcons[2])
                s2:Show()
            elseif numFilled == 3 then
                -- Left half
                local s1 = macroIcon.slices[1]
                s1:ClearAllPoints()
                s1:SetPoint("LEFT", macroIcon, "LEFT", 1, 0)
                s1:SetSize(hw, size)
                s1:SetTexCoord(0, 0.5, 0, 1)
                s1:SetTexture(filledIcons[1])
                s1:Show()

                -- Top-Right quarter
                local s2 = macroIcon.slices[2]
                s2:ClearAllPoints()
                s2:SetPoint("TOPRIGHT", macroIcon, "TOPRIGHT", -1, -1)
                s2:SetSize(hw, hw)
                s2:SetTexCoord(0.5, 1, 0, 0.5)
                s2:SetTexture(filledIcons[2])
                s2:Show()

                -- Bottom-Right quarter
                local s3 = macroIcon.slices[3]
                s3:ClearAllPoints()
                s3:SetPoint("BOTTOMRIGHT", macroIcon, "BOTTOMRIGHT", -1, 1)
                s3:SetSize(hw, hw)
                s3:SetTexCoord(0.5, 1, 0.5, 1)
                s3:SetTexture(filledIcons[3])
                s3:Show()
            elseif numFilled >= 4 then
                -- 4 quadrants
                local coords = {
                    {0, 0.5, 0, 0.5},   -- Top-Left
                    {0.5, 1, 0, 0.5},   -- Top-Right
                    {0, 0.5, 0.5, 1},   -- Bottom-Left
                    {0.5, 1, 0.5, 1}    -- Bottom-Right
                }
                local anchors = {
                    {"TOPLEFT", 1, -1},
                    {"TOPRIGHT", -1, -1},
                    {"BOTTOMLEFT", 1, 1},
                    {"BOTTOMRIGHT", -1, 1}
                }
                for i = 1, 4 do
                    local s = macroIcon.slices[i]
                    s:ClearAllPoints()
                    s:SetPoint(anchors[i][1], macroIcon, anchors[i][1], anchors[i][2], anchors[i][3])
                    s:SetSize(hw, hw)
                    s:SetTexCoord(unpack(coords[i]))
                    s:SetTexture(filledIcons[i])
                    s:Show()
                end
            end
        end

        if macroIcon.questionText then
            if numFilled > 0 then
                macroIcon.questionText:Hide()
            else
                macroIcon.questionText:Show()
            end
        end
        -- Update requirement text in Internal Mix panel
        local reqLines = {}
        for i = 1, 4 do
            local slot = selectedSlots[i]
            if slot and slot.type == "toy" then
                local reqs = self:GetItemRequirements(slot.id)
                for _, req in ipairs(reqs) do
                    local color = string.format("|cff%02x%02x%02x", req.r * 255, req.g * 255, req.b * 255)
                    table.insert(reqLines, color .. req.text .. "|r")
                end
            end
        end
        if #reqLines > 0 then
            macroReqs:SetText(table.concat(reqLines, "\n"))
            macroReqs:Show()
        else
            macroReqs:SetText("")
            macroReqs:Hide()
        end
        
        -- Update the Run Mix button's macro text whenever slots change
        if self.UpdateRunButtonMacro then
            self.UpdateRunButtonMacro()
        end
    end
    
    -- Interaction for slots (Tooltips and click to clear)
    slot1:SetScript("OnEnter", function(self)
        local slot = selectedSlots[1]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_PRIMARY_SLOT"] or "Primary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
            GameTooltip:Show()
            return
        end
        if slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
            GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
        end
        GameTooltip:Show()
    end)
    slot1:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot1:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 1)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 1)
            end
            ClearCursor()
        end
    end)

    slot2:SetScript("OnEnter", function(self)
        local slot = selectedSlots[2]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not slot then
            GameTooltip:SetText(L["MIXER_SECONDARY_SLOT"] or "Secondary Slot", 0.18, 0.58, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP1"] or "Click a toy or spell in the grid to select it.", 1, 1, 1)
            GameTooltip:AddLine(L["MIXER_SLOT_HELP2"] or "You can mix a toy with a spell, or a toy with another toy.", 1, 0.82, 0)
        elseif slot.type == "toy" then
            GameTooltip:SetToyByItemID(slot.id)
        elseif slot.type == "spell" then
            GameTooltip:SetSpellByID(slot.id)
            GameTooltip:AddLine("|cffaaaaaaSpell ID: " .. slot.id .. "|r")
        end
        GameTooltip:Show()
    end)
    slot2:SetScript("OnLeave", function() GameTooltip:Hide() end)
    slot2:SetScript("OnReceiveDrag", function()
        local ctype, info1, info2 = GetCursorInfo()
        if ctype == "item" or ctype == "toy" then
            self:SelectSlotForMixer("toy", info1, 2)
            ClearCursor()
        elseif ctype == "spell" then
            local spellBank = info2 == "pet" and Enum.SpellBookSpellBank.Pet or Enum.SpellBookSpellBank.Player
            local spellInfo = C_SpellBook.GetSpellBookItemInfo(info1, spellBank)
            if spellInfo and spellInfo.spellID then
                self:SelectSlotForMixer("spell", spellInfo.spellID, 2)
            end
            ClearCursor()
        end
    end)

    -- macroIcon is now a texture, no button scripts needed
    
    -- Store button refs
    self.mixerSoundBtn = soundBtn
    self.mixerEmoteBtn = emotionBtn
    self.mixerAnimBtn = animBtn
    self.mixerChatBtn = textBtn
end

--- Macro Naming Logic
local function GetSlotInitials(slot)
    if not slot then return "" end
    local name
    if slot.type == "toy" then
        _, name = C_ToyBox.GetToyInfo(slot.id)
    elseif slot.type == "spell" then
        local spellInfo = C_Spell.GetSpellInfo(slot.id)
        name = spellInfo and spellInfo.name
    end
    if not name then return "?" end

    -- Extract initials (first letter of each word, max 4)
    local initials = ""
    for word in name:gmatch("%S+") do
        initials = initials .. word:sub(1, 1):upper()
        if #initials >= 4 then break end
    end
    return initials
end

-- Save Mix to Internal Registry
function Toys:SaveMix()
    local hasAny = false
    for i = 1, 4 do if selectedSlots[i] then hasAny = true; break end end
    if not hasAny then return end

    local mixName
    if self.editingMixName then
        -- Updating an existing mix being edited
        mixName = self.editingMixName
    else
        -- Creating a new mix: auto-generate name from slot initials
        local nameparts = {}
        for i = 1, 4 do
            if selectedSlots[i] then
                local initials = GetSlotInitials(selectedSlots[i])
                if initials and initials ~= "" then
                    table.insert(nameparts, initials)
                end
            end
        end
        mixName = table.concat(nameparts, " + ")
        if not mixName or mixName == "" then
            mixName = "Mix " .. date("%H:%M:%S")
        end
    end

    local slotsToSave = { selectedSlots[1], selectedSlots[2], selectedSlots[3], selectedSlots[4] }

    -- Save via MacroRegistry
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:SaveMacro(mixName, {
            slots = slotsToSave,
            randomToys = mixerRandomToys,
            actions = {
                sound = mixerActions.sound,
                emote = mixerActions.emote,
                animation = mixerActions.animation,
                chat = mixerActions.chat
            }
        })
    end

    -- Also keep toyMixes for backward compat with EmotionRing/ToyRing
    local existingMix = OxedHub.db.profile.toyMixes[mixName]
    OxedHub.db.profile.toyMixes[mixName] = {
        slots = slotsToSave,
        randomToys = mixerRandomToys,
        customMacroBody = type(existingMix) == "table" and existingMix.customMacroBody or nil,
        -- creation timestamp for Newest/Oldest sorting; preserved across edits
        createdAt = (type(existingMix) == "table" and existingMix.createdAt) or time(),
        actions = {
            sound = mixerActions.sound,
            emote = mixerActions.emote,
            animation = mixerActions.animation,
            chat = mixerActions.chat
        }
    }
    if self:HasGeneratedMixMacro(mixName) then
        self:CreateMacroForMix(mixName, true)
    end

    self.currentMixName = mixName
    local wasEditing = self.editingMixName ~= nil
    self.editingMixName = nil
    if self.mixerSaveBtn then
        self.mixerSaveBtn:SetText(L["TOYS_BTN_SAVE_MIX"] or "Save Mix")
    end

    -- Auto-clear mixer after editing so user can create a new mix fresh
    if wasEditing then
        for i = 1, 4 do selectedSlots[i] = nil end
        for k in pairs(mixerActions) do mixerActions[k] = nil end
        mixerRandomToys = false
        if self.mixerRandomCheck then self.mixerRandomCheck:SetChecked(false) end
        if self.UpdateRandomSlotsVisibility then self:UpdateRandomSlotsVisibility() end
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if self.mixerSoundBtn then self.mixerSoundBtn:SetText(L["TOYS_ACT_ADD_SOUND"] or "Add Sound") end
        if self.mixerEmoteBtn then self.mixerEmoteBtn:SetText(L["TOYS_ACT_ADD_EMOTE"] or "Add Emote") end
        if self.mixerAnimBtn then self.mixerAnimBtn:SetText(L["TOYS_ACT_ADD_ANIM"] or "Add Animation") end
        if self.mixerChatBtn then self.mixerChatBtn:SetText(L["TOYS_ACT_ADD_TEXT"] or "Add Text") end
        print("|cff00ff00[OxedHub]|r Mix updated. Mixer cleared for new creation.")
    end

    if self.savedMixesScrollChild then
        self:RefreshSavedMixesList()
    end
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

-- Picker for Mixer
function Toys:ShowPickerForMixer(type, btn)
    if not OxedHub.Triggers then return end
    
    local function OnSelect(value, label)
        mixerActions[type] = value
        btn:SetText(label or mixerActionButtonText[type])
    end
    
    if type == "sound" then
        OxedHub.Triggers.currentTriggerForPicker = { actions = mixerActions }
        OxedHub.Triggers:ShowSoundPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local disp = mixerActions.sound and Toys:GetSoundDisplayName(mixerActions.sound)
            btn:SetText(disp or mixerActionButtonText.sound)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif type == "emote" then
        OxedHub.Triggers:ShowEmotePicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local disp = mixerActions.emote and TruncateText(mixerActions.emote, 15)
            btn:SetText(disp or mixerActionButtonText.emote)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif type == "chat" then
        -- Pre-populate chatMessage so picker can read existing value
        if mixerActions.chat and not mixerActions.chatMessage then
            mixerActions.chatMessage = mixerActions.chat
        end
        OxedHub.Triggers:ShowChatPicker({ actions = mixerActions })
        OxedHub.Triggers.RefreshTriggersList = function(self)
            mixerActions.chat = mixerActions.chatMessage
            local chat = OxedHub.db.profile.chatTemplates[mixerActions.chat]
            local disp = chat and chat.name and TruncateText(chat.name, 15)
            btn:SetText(disp or mixerActionButtonText.chat)
            OxedHub.Triggers.RefreshTriggersList = orig
            if orig then orig(self) end
        end
    elseif type == "animation" then
        OxedHub.Triggers:ShowAnimationPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            local anim = OxedHub.db.profile.animations[mixerActions.animation]
            local disp = anim and anim.name and TruncateText(anim.name, 15)
            btn:SetText(disp or mixerActionButtonText.animation)
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    end
end

-- Spell Picker for Mixer
function Toys:ShowSpellPickerForMixer()
    if self.spellPicker then
        self.spellPicker:Show()
        self:RefreshSpellPickerList("")
        return
    end

    local picker = CreateFrame("Frame", "OxedHubSpellPicker", UIParent, "BasicFrameTemplate")
    picker:SetSize(420, 460)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(220)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)

    if picker.TitleText then
        picker.TitleText:SetText(L["MIXER_PICK_SPELL"] or "Pick Spell")
    end
    if picker.CloseButton then
        picker.CloseButton:SetScript("OnClick", function() picker:Hide() end)
    end

    local searchLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", picker, "TOPLEFT", 18, -35)
    searchLabel:SetText(L["PICKER_SEARCH"] or "Search")

    local searchInput = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    searchInput:SetSize(210, 22)
    searchInput:SetPoint("TOPLEFT", searchLabel, "BOTTOMLEFT", 0, -6)
    searchInput:SetAutoFocus(false)
    searchInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchInput:SetScript("OnTextChanged", function() self:RefreshSpellPickerList(searchInput:GetText()) end)

    local clearBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 22)
    clearBtn:SetPoint("LEFT", searchInput, "RIGHT", 8, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() searchInput:SetText(""); searchInput:ClearFocus() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", searchInput, "BOTTOMLEFT", 0, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -32, 52)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(350)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local closeBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    closeBtn:SetSize(80, 24)
    closeBtn:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", -18, 16)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() picker:Hide() end)

    picker.searchInput = searchInput
    picker.scrollFrame = scrollFrame
    picker.scrollChild = scrollChild
    picker.rows = {}
    self.spellPicker = picker

    self:RefreshSpellPickerList("")
    picker:Show()
end

function Toys:RefreshSpellPickerList(query)
    local picker = self.spellPicker
    if not picker then return end
    query = query or ""
    query = query:lower():gsub("^%s*", ""):gsub("%s*$", "")

    local results = {}
    local added = {}

    -- Search spellbook
    local numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
    for skillLineIndex = 1, numSkillLines do
        local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
        if skillLineInfo then
            local numSpells = skillLineInfo.numSpellBookItems or 0
            for spellIndex = skillLineInfo.itemIndexOffset, skillLineInfo.itemIndexOffset + numSpells - 1 do
                local spellInfo = C_SpellBook.GetSpellBookItemInfo(spellIndex, Enum.SpellBookSpellBank.Player)
                if spellInfo and spellInfo.spellID and not added[spellInfo.spellID] then
                    local spellName = C_SpellBook.GetSpellBookItemName(spellIndex, Enum.SpellBookSpellBank.Player)
                    local icon = C_SpellBook.GetSpellBookItemTexture(spellIndex, Enum.SpellBookSpellBank.Player)
                    if spellName and (query == "" or spellName:lower():find(query, 1, true)) then
                        added[spellInfo.spellID] = true
                        table.insert(results, { name = spellName, id = spellInfo.spellID, icon = icon })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b) return a.name < b.name end)

    for index, result in ipairs(results) do
        local row = picker.rows[index]
        if not row then
            row = CreateFrame("Button", nil, picker.scrollChild)
            row:SetSize(330, 24)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            
            -- Create icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", row, "LEFT", 4, 0)
            row.icon = icon

            -- Create text
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
            text:SetJustifyH("LEFT")
            row.textStr = text

            picker.rows[index] = row
        end
        row:Show()
        row:SetPoint("TOPLEFT", picker.scrollChild, "TOPLEFT", 5, -((index - 1) * 26))
        
        row.icon:SetTexture(result.icon)
        row.textStr:SetText(result.name .. "  |cff888888(ID: " .. result.id .. ")|r")
        
        row:SetScript("OnClick", function()
            self:SelectSlotForMixer("spell", result.id, 2)
            picker:Hide()
        end)
    end

    for index = #results + 1, #picker.rows do
        picker.rows[index]:Hide()
    end

    picker.scrollChild:SetHeight(math.max(#results * 26, 1))
end

-- Create Saved Mixes UI
function Toys:CreateSavedMixesUI(parent)
    local hideUnavailableCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    hideUnavailableCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -6)
    hideUnavailableCheck:SetSize(22, 22)
    
    local label = hideUnavailableCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", hideUnavailableCheck, "RIGHT", 5, 1)
    label:SetText(L["TOYS_HIDE_UNAVAILABLE_MIXES"] or "Hide Mixes with Missing Toys")
    
    hideUnavailableCheck:SetChecked(OxedHub.db.profile.settings.hideMissingToys == true)
    hideUnavailableCheck:SetScript("OnClick", function(self)
        OxedHub.db.profile.settings.hideMissingToys = self:GetChecked()
        Toys:RefreshSavedMixesList()
    end)
    self.hideUnavailableCheck = hideUnavailableCheck

    -- Sort dropdown (top-right of the My Mixes panel)
    self.mixSortMode = OxedHub.db.profile.settings.mixSortMode or "az"
    if self.mixSortMode ~= "az" and self.mixSortMode ~= "za" then
        self.mixSortMode = "az"  -- retired newest/oldest modes fall back to A-Z
    end
    local sortDropdown = CreateFrame("DropdownButton", "OxedHubMixSortDropdown", parent, "WowStyle1DropdownTemplate")
    if sortDropdown then
        sortDropdown:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -50, -4)
        sortDropdown:SetWidth(120)
        local sortOptions = {
            { text = L["MIXER_SORT_AZ"] or "A - Z", value = "az" },
            { text = L["MIXER_SORT_ZA"] or "Z - A", value = "za" },
        }
        local function UpdateSortText()
            for _, opt in ipairs(sortOptions) do
                if opt.value == self.mixSortMode then
                    sortDropdown:OverrideText(opt.text)
                    return
                end
            end
            sortDropdown:OverrideText(L["MIXER_SORT_AZ"] or "A - Z")
        end
        sortDropdown:SetupMenu(function(dropdown, rootDescription)
            for _, opt in ipairs(sortOptions) do
                rootDescription:CreateRadio(opt.text,
                    function() return self.mixSortMode == opt.value end,
                    function()
                        self.mixSortMode = opt.value
                        OxedHub.db.profile.settings.mixSortMode = opt.value
                        UpdateSortText()
                        Toys:RefreshSavedMixesList()
                    end
                )
            end
        end)
        UpdateSortText()
        self.mixSortDropdown = sortDropdown
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 28, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -50, 24)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scrollFrame)
    end
    
    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(scrollFrame:GetWidth(), 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    self.savedMixesScrollFrame = scrollFrame
    self.savedMixesScrollChild = scrollChild
    self:RefreshSavedMixesList()
end

-- Refresh Saved Mixes List (Table-style with editable components)
function Toys:RefreshSavedMixesList()
    local parent = self.savedMixesScrollChild
    if not parent then return end

    if parent.rows then
        for _, row in ipairs(parent.rows) do row:Hide() end
    end
    parent.rows = parent.rows or {}

    local mixes = OxedHub.db.profile.toyMixes or {}
    local filter = OxedHub.db.profile.settings.filterByClass
    local hideMissingToys = OxedHub.db.profile.settings.hideMissingToys == true
    local sortedMixes = {}
    for name, data in pairs(mixes) do 
        local show = true
        if filter and data.slots then
            for _, slot in ipairs(data.slots) do
                if slot and slot.type == "spell" then
                    if not OxedHub:IsSpellRelevant(slot.id) then
                        show = false
                        break
                    end
                end
            end
        end
        if show and hideMissingToys then
            local _, missingToys = self:GetMixToyAvailability(data)
            if missingToys > 0 then
                show = false
            end
        end
        if show then
            table.insert(sortedMixes, name)
        end
    end

    -- Sort per the selected mode (default A-Z).
    local mode = self.mixSortMode or "az"
    if mode == "az" then
        table.sort(sortedMixes, function(a, b) return a:lower() < b:lower() end)
    elseif mode == "za" then
        table.sort(sortedMixes, function(a, b) return a:lower() > b:lower() end)
    elseif mode == "newest" or mode == "oldest" then
        local function created(n)
            local d = mixes[n]
            return (type(d) == "table" and d.createdAt) or 0
        end
        table.sort(sortedMixes, function(a, b)
            local ca, cb = created(a), created(b)
            if ca == cb then return a:lower() < b:lower() end
            if mode == "newest" then return ca > cb end
            return ca < cb
        end)
    end

    local yOffset = -5
    local rowHeight = 80

    for i, name in ipairs(sortedMixes) do
        local row = parent.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetSize(parent:GetWidth() - 10, rowHeight)

            local separator = row:CreateTexture(nil, "BACKGROUND")
            separator:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            separator:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            separator:SetHeight(1)
            separator:SetTexture("Interface\\Buttons\\WHITE8X8")
            separator:SetVertexColor(0.55, 0.55, 0.55, 0.28)
            row.separator = separator

            -- LEFT SECTION: Mix Name
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
            nameLabel:SetWidth(200)
            nameLabel:SetJustifyH("LEFT")
            nameLabel:SetTextColor(1, 1, 1)
            row.nameLabel = nameLabel

            -- Clickable overlay on the mix name to rename it.
            local nameBtn = CreateFrame("Button", nil, row)
            nameBtn:SetPoint("TOPLEFT", nameLabel, "TOPLEFT", 0, 0)
            nameBtn:SetSize(200, 20)
            nameBtn:SetScript("OnClick", function(self)
                Toys:ShowRenameMixDialog(self.mixName)
            end)
            nameBtn:SetScript("OnEnter", function(self)
                row.nameLabel:SetTextColor(1, 0.82, 0)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L["MIXER_CLICK_TO_RENAME"] or "Click to rename", 0.18, 0.58, 1)
                GameTooltip:Show()
            end)
            nameBtn:SetScript("OnLeave", function()
                row.nameLabel:SetTextColor(1, 1, 1)
                GameTooltip:Hide()
            end)
            row.nameBtn = nameBtn

            -- Status label (moved to center)
            local statusLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statusLabel:SetPoint("TOP", row, "TOP", 0, -14)
            statusLabel:SetJustifyH("CENTER")
            row.statusLabel = statusLabel

            -- Slot icons (moved to right of big icon)
            local slotIconSize = 30
            local slot1Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot1Btn:SetSize(slotIconSize, slotIconSize)
            slot1Btn:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 74, 20)
            slot1Btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot1Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot1Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot1Tex = slot1Btn:CreateTexture(nil, "ARTWORK")
            slot1Tex:SetPoint("TOPLEFT", slot1Btn, "TOPLEFT", 2, -2)
            slot1Tex:SetPoint("BOTTOMRIGHT", slot1Btn, "BOTTOMRIGHT", -2, 2)
            slot1Tex:SetTexture(134400)
            slot1Btn.tex = slot1Tex
            slot1Btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() and self.itemID then
                    local _, toyName = C_ToyBox.GetToyInfo(self.itemID)
                    OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.itemID), toyName or ("Toy #" .. self.itemID))
                    return
                end
                Toys:EditMix(self.mixName)
            end)
            slot1Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                    GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine(L["MIXER_SLOT1_ASSIGN"] or "Slot 1 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot1Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot1Btn = slot1Btn

            local slot2Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot2Btn:SetSize(slotIconSize, slotIconSize)
            slot2Btn:SetPoint("LEFT", slot1Btn, "RIGHT", 4, 0)
            slot2Btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot2Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot2Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot2Tex = slot2Btn:CreateTexture(nil, "ARTWORK")
            slot2Tex:SetPoint("TOPLEFT", slot2Btn, "TOPLEFT", 2, -2)
            slot2Tex:SetPoint("BOTTOMRIGHT", slot2Btn, "BOTTOMRIGHT", -2, 2)
            slot2Tex:SetTexture(134400)
            slot2Btn.tex = slot2Tex
            slot2Btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() and self.itemID then
                    local _, toyName = C_ToyBox.GetToyInfo(self.itemID)
                    OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.itemID), toyName or ("Toy #" .. self.itemID))
                    return
                end
                Toys:EditMix(self.mixName)
            end)
            slot2Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                    GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine(L["MIXER_SLOT2_ASSIGN"] or "Slot 2 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot2Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot2Btn = slot2Btn

            local slot3Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot3Btn:SetSize(slotIconSize, slotIconSize)
            slot3Btn:SetPoint("LEFT", slot2Btn, "RIGHT", 4, 0)
            slot3Btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot3Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot3Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot3Tex = slot3Btn:CreateTexture(nil, "ARTWORK")
            slot3Tex:SetPoint("TOPLEFT", slot3Btn, "TOPLEFT", 2, -2)
            slot3Tex:SetPoint("BOTTOMRIGHT", slot3Btn, "BOTTOMRIGHT", -2, 2)
            slot3Tex:SetTexture(134400)
            slot3Btn.tex = slot3Tex
            slot3Btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() and self.itemID then
                    local _, toyName = C_ToyBox.GetToyInfo(self.itemID)
                    OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.itemID), toyName or ("Toy #" .. self.itemID))
                    return
                end
                Toys:EditMix(self.mixName)
            end)
            slot3Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                    GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine("Slot 3 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot3Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot3Btn = slot3Btn

            local slot4Btn = CreateFrame("Button", nil, row, "BackdropTemplate")
            slot4Btn:SetSize(slotIconSize, slotIconSize)
            slot4Btn:SetPoint("LEFT", slot3Btn, "RIGHT", 4, 0)
            slot4Btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot4Btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
            slot4Btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
            local slot4Tex = slot4Btn:CreateTexture(nil, "ARTWORK")
            slot4Tex:SetPoint("TOPLEFT", slot4Btn, "TOPLEFT", 2, -2)
            slot4Tex:SetPoint("BOTTOMRIGHT", slot4Btn, "BOTTOMRIGHT", -2, 2)
            slot4Tex:SetTexture(134400)
            slot4Btn.tex = slot4Tex
            slot4Btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" and IsShiftKeyDown() and self.itemID then
                    local _, toyName = C_ToyBox.GetToyInfo(self.itemID)
                    OxedHub:ShowCopyURLDialog(string.format("https://www.wowhead.com/item=%d/", self.itemID), toyName or ("Toy #" .. self.itemID))
                    return
                end
                Toys:EditMix(self.mixName)
            end)
            slot4Btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemID then
                    GameTooltip:SetToyByItemID(self.itemID)
                    GameTooltip:AddLine("|cff00ccff" .. (L["TOYS_SHIFT_RIGHTCLICK_WOWHEAD"] or "Shift + Right-Click: Copy Wowhead URL") .. "|r")
                elseif self.spellID then
                    GameTooltip:SetSpellByID(self.spellID)
                else
                    GameTooltip:AddLine("Slot 4 — click to assign", 1, 1, 1)
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_CHANGE"] or "Click to change") .. "|r")
                GameTooltip:Show()
            end)
            slot4Btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.slot4Btn = slot4Btn

            -- LEFT SECTION: Draggable Split Mix Icon (Moved left under mix name)
            local mixIconFrame = CreateFrame("Button", nil, row, "BackdropTemplate")
            mixIconFrame:SetSize(50, 50)
            mixIconFrame:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 10)
            mixIconFrame:SetBackdrop(nil)
            mixIconFrame:EnableMouse(true)
            mixIconFrame:RegisterForDrag("LeftButton")
            mixIconFrame:RegisterForClicks("LeftButtonUp")
            -- Click the mix icon to edit it in the Mixer; drag still creates the
            -- action-bar macro (handled by OnDragStart below).
            mixIconFrame:SetScript("OnClick", function(self)
                Toys:EditMix(self.mixName)
            end)
            mixIconFrame:SetScript("OnDragStart", function(self)
                local macroName = Toys:CreateMacroForMix(self.mixName)
                if macroName then
                    local index = GetMacroIndexByName(macroName)
                    if index and index > 0 then
                        PickupMacro(index)
                    end
                end
            end)
            mixIconFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.mixName or "Mix", 1, 1, 1)
                if self.missingToyCount and self.missingToyCount > 0 then
                    GameTooltip:AddLine("|cffff6666" .. (L["MIXER_MISSING_TOYS"] or "Missing toys: ") .. self.missingToyCount .. "|r")
                else
                    GameTooltip:AddLine("|cff88ff88" .. (L["MIXER_ALL_TOYS_AVAILABLE"] or "All toys available") .. "|r")
                end
                GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_EDIT"] or "Click to edit") .. "|r")
                GameTooltip:AddLine("|cffaaaaaa " .. (L["MIXER_DRAG_TO_ACTION_BAR"] or "Drag to action bar") .. "|r")
                GameTooltip:Show()
            end)
            mixIconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.mixIconFrame = mixIconFrame

            -- INFO TEXT: Centered in the row
            local infoText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            infoText:SetJustifyH("CENTER")
            infoText:SetJustifyV("TOP")
            row.infoText = infoText

            -- RIGHT SECTION: 4 action buttons + Del
            local actionBtnSize = 26
            local actionDefs = {
                { key = "sound",     icon = "Interface\\Icons\\INV_Misc_Horn_01", label = L["MIXER_SOUND_LABEL"] or "Sound"     },
                { key = "emote",     icon = "Interface\\Icons\\UI_Chat",  label = L["MIXER_EMOTE_LABEL"] or "Emote"     },
                { key = "animation", icon = "Interface\\Icons\\Ability_Rogue_Sprint",  label = L["MIXER_ANIM_LABEL"] or "Animation" },
                { key = "chat",      icon = "Interface\\Icons\\INV_Misc_Note_01", label = L["MIXER_CHAT_LABEL"] or "Chat"      },
            }
            row.actionBtns = {}
            for ai, def in ipairs(actionDefs) do
                local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
                btn:SetSize(actionBtnSize, actionBtnSize)
                btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 6,
                                   insets = { left = 1, right = 1, top = 1, bottom = 1 } })
                btn:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.8)

                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
                tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
                tex:SetTexture(def.icon)
                btn.tex = tex

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
                hl:SetBlendMode("ADD")

                -- anchor: right side, row of 4 before Macro + Del
                -- positions: -140 -170 -200 -230 from TOPRIGHT (each 26+4=30)
                btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -140 - (4 - ai) * 30, -10)

                local capturedDef = def
                btn:SetScript("OnClick", function(self)
                    Toys:EditMixComponent(self.mixName, capturedDef.key)
                end)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(capturedDef.label, 1, 1, 1)
                    local acts = self.mixData and self.mixData.actions or {}
                    local val = acts[capturedDef.key]
                    if val then
                        GameTooltip:AddLine("|cff88ff88" .. tostring(val) .. "|r")
                    else
                        GameTooltip:AddLine("|cffaaaaaa " .. (L["MIXER_NOT_SET"] or "Not set") .. "|r")
                    end
                    GameTooltip:AddLine("|cff00ff00" .. (L["MIXER_CLICK_TO_EDIT"] or "Click to edit") .. "|r")
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.actionBtns[ai] = btn
                row.actionBtns[def.key] = btn
            end

            -- Share this one mix as a chat link, sitting under the action icons.
            local shareBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            shareBtn:SetSize(actionBtnSize * 4 + 12, 20)
            shareBtn:SetPoint("TOPRIGHT", row.actionBtns[4], "BOTTOMRIGHT", 0, -4)
            shareBtn:SetText(L["BTN_SHARE"] or "Share")
            shareBtn:SetNormalFontObject("GameFontNormalSmall")
            shareBtn:SetScript("OnClick", function(self)
                local Share = OxedHub.Share
                if not Share then
                    print("|cffff0000Oxed Hub:|r Sharing module unavailable.")
                    return
                end
                if not self.mixName then return end
                Share:ShowChannelPicker("toymixes", { mixNames = { self.mixName } }, self.mixName)
            end)
            shareBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(L["BTN_SHARE"] or "Share", 1, 0.82, 0)
                GameTooltip:AddLine("Share only this mix in chat.", 1, 1, 1, true)
                GameTooltip:AddLine("Others with Oxed Hub can click to import it.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            shareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.shareBtn = shareBtn

            local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            delBtn:SetSize(60, 22)
            delBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -10)
            delBtn:SetText(L["MIXER_DEL"] or "Del")
            delBtn:SetNormalFontObject("GameFontNormalSmall")
            delBtn:SetScript("OnClick", function(self)
                Toys:DeleteMix(self.macroName)
            end)
            row.delBtn = delBtn

            local macroBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            macroBtn:SetSize(60, 22)
            macroBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
            macroBtn:SetText(L["MIXER_MACRO"] or "Macro")
            macroBtn:SetNormalFontObject("GameFontNormalSmall")
            macroBtn:SetScript("OnClick", function(self)
                Toys:ShowMixMacroEditor(self.mixName)
            end)
            row.macroBtn = macroBtn

            -- Edit button: opens the mix in the Mixer for full editing.
            local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            editBtn:SetSize(60, 22)
            editBtn:SetPoint("TOP", delBtn, "BOTTOM", 0, -4)
            editBtn:SetText(L["MIXER_EDIT"] or "Edit")
            editBtn:SetNormalFontObject("GameFontNormalSmall")
            editBtn:SetScript("OnClick", function(self)
                Toys:EditMix(self.mixName)
            end)
            row.editBtn = editBtn

            local renameBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            renameBtn:SetSize(60, 22)
            renameBtn:SetPoint("TOP", macroBtn, "BOTTOM", 0, -4)
            renameBtn:SetText(L["MIXER_RENAME"] or "Rename")
            renameBtn:SetNormalFontObject("GameFontNormalSmall")
            renameBtn:SetScript("OnClick", function(self)
                Toys:ShowRenameMixDialog(self.mixName)
            end)
            row.renameBtn = renameBtn

            parent.rows[i] = row
        end

        row:Show()
        row:SetSize(parent:GetWidth() - 10, rowHeight)
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, yOffset)
        row.mixName = name

        local data = mixes[name]
        local totalToys, missingToys = self:GetMixToyAvailability(data)
        local isMissing = missingToys > 0

        -- Update name label
        row.nameLabel:SetText(name)
        row.nameBtn.mixName = name

        -- Status
        if isMissing then
            local suffix = missingToys == 1 and "" or "s"
            row.statusLabel:SetText("|cffff6666" .. string.format(L["TOY_MISSING_COUNT"] or "%d missing toy%s%s", missingToys, suffix, suffix) .. "|r")
        else
            row.statusLabel:SetText("|cff88ff88" .. (L["TOY_STATUS_READY"] or "Ready") .. "|r")
        end

        -- Update split icon
        row.mixIconFrame.mixName = name
        row.mixIconFrame.missingToyCount = missingToys

        -- Gray out split icon border when toys missing (Removed as the border was removed)
        if isMissing then
            -- intentionally left blank
        else
            -- intentionally left blank
        end

        -- Info text
        -- parchment color matching OxedRing editor description text: 0.90, 0.85, 0.80 = #e6d9cc
        local parchment = "|cffe6d9cc"
        if isMissing then
            local suffix = missingToys == 1 and "" or "s"
            row.infoText:SetText(
                "|cffff6666" .. string.format(L["TOY_MISSING_INFO"] or "%d toy%s missing — partially usable. Missing toy effects will be skipped; sounds, animations, emotes and chat will still fire normally.", missingToys, suffix, suffix) .. "|r"
            )
        else
            row.infoText:SetText(
                "|cffffff00ActionHub|r" .. parchment .. ": " .. (L["TOY_INFO_READY"] or "assign to a button — no macro slot used (OxedEngine internal). Or drag the icon to your action bar — uses 1 slot in your general or class macros.") .. "|r"
            )
        end

        -- Clear old split icon if it exists
        if row.splitIcon then
            row.splitIcon:Hide()
            row.splitIcon = nil
        end
        -- Clear old custom icon texture if it exists
        if row.customIconTex then
            row.customIconTex:Hide()
        end

        -- Check for custom icon override
        local customIcon = self:GetMixCustomIcon(name)
        if customIcon then
            -- Show a single custom icon instead of split icon
            if not row.customIconTex then
                local tex = row.mixIconFrame:CreateTexture(nil, "ARTWORK")
                tex:SetSize(46, 46)
                tex:SetPoint("CENTER", row.mixIconFrame, "CENTER", 0, 0)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.customIconTex = tex
            end
            row.customIconTex:SetTexture(customIcon)
            row.customIconTex:SetDesaturated(isMissing)
            if isMissing then
                row.customIconTex:SetVertexColor(0.45, 0.45, 0.45, 1)
            else
                row.customIconTex:SetVertexColor(1, 1, 1, 1)
            end
            row.customIconTex:Show()
        else
            -- Create new split icon, grayed if missing
            if row.customIconTex then row.customIconTex:Hide() end
            local icon1, icon2, icon3, icon4 = self:GetMixSlotIcons(name)
            local splitIcon = Toys:CreateSplitIcon(row.mixIconFrame, 46, icon1, icon2, icon3, icon4)
            splitIcon:SetPoint("CENTER", row.mixIconFrame, "CENTER", 0, 0)
            
            if splitIcon.texs then
                for _, tex in ipairs(splitIcon.texs) do
                    tex:SetDesaturated(isMissing)
                    if isMissing then
                        tex:SetVertexColor(0.45, 0.45, 0.45, 1)
                    else
                        tex:SetVertexColor(1, 1, 1, 1)
                    end
                end
            end

            row.splitIcon = splitIcon
        end

        -- Update action buttons
        local acts = (type(data) == "table" and data.actions) or {}
        for _, btn in ipairs(row.actionBtns) do
            btn.mixName = name
            btn.mixData = data
        end
        local actionKeys = { "sound", "emote", "animation", "chat" }
        for _, key in ipairs(actionKeys) do
            local btn = row.actionBtns[key]
            if btn then
                if acts[key] then
                    btn.tex:SetDesaturated(false)
                    btn.tex:SetVertexColor(1, 1, 1, 1)
                    btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.9)
                else
                    btn.tex:SetDesaturated(true)
                    btn.tex:SetVertexColor(0.4, 0.4, 0.4, 0.8)
                    btn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)
                end
            end
        end

        -- Anchor info text to the center (only on first build)
        if not row.infoTextAnchored then
            row.infoText:SetPoint("TOP", row.statusLabel, "BOTTOM", 0, -4)
            row.infoText:SetWidth(380)
            row.infoTextAnchored = true
        end

        -- Update slot icons
        row.slot1Btn.mixName = name
        row.slot2Btn.mixName = name
        row.slot3Btn.mixName = name
        row.slot4Btn.mixName = name
        row.slot1Btn.itemID = nil
        row.slot1Btn.spellID = nil
        row.slot2Btn.itemID = nil
        row.slot2Btn.spellID = nil
        row.slot3Btn.itemID = nil
        row.slot3Btn.spellID = nil
        row.slot4Btn.itemID = nil
        row.slot4Btn.spellID = nil

        local slots = type(data) == "table" and data.slots or {}
        local showRandom = type(data) == "table" and data.randomToys
        for si, slotBtn in ipairs({ row.slot1Btn, row.slot2Btn, row.slot3Btn, row.slot4Btn }) do
            if si > 2 and not showRandom then
                slotBtn:Hide()
            else
                slotBtn:Show()
                local slot = slots[si]
                if slot then
                    if slot.type == "toy" then
                        local _, _, tIcon = C_ToyBox.GetToyInfo(slot.id)
                        slotBtn.tex:SetTexture(tIcon or 134400)
                        slotBtn.itemID = slot.id
                        local owns = self:DoesPlayerOwnToy(slot.id)
                        if owns then
                            slotBtn.tex:SetDesaturated(false)
                            slotBtn.tex:SetVertexColor(1, 1, 1, 1)
                            slotBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                        else
                            slotBtn.tex:SetDesaturated(true)
                            slotBtn.tex:SetVertexColor(0.45, 0.45, 0.45, 1)
                            slotBtn:SetBackdropBorderColor(0.7, 0.15, 0.15, 1)
                        end
                    elseif slot.type == "spell" then
                        local spellInfo = C_Spell.GetSpellInfo(slot.id)
                        slotBtn.tex:SetTexture(spellInfo and spellInfo.iconID or 134400)
                        slotBtn.spellID = slot.id
                        slotBtn.tex:SetDesaturated(false)
                        slotBtn.tex:SetVertexColor(1, 1, 1, 1)
                        slotBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    end
                else
                    slotBtn.tex:SetTexture(134400)
                    slotBtn.tex:SetDesaturated(false)
                    slotBtn.tex:SetVertexColor(0.5, 0.5, 0.5, 0.5)
                    slotBtn:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
                end
            end
        end

        -- Update delete button and macro button
        row.delBtn.macroName = name
        row.macroBtn.mixName = name
        row.editBtn.mixName = name
        row.renameBtn.mixName = name
        row.shareBtn.mixName = name

        yOffset = yOffset - (rowHeight + 2)
    end

    parent:SetHeight(math.abs(yOffset))
end

-- Delete Mix
function Toys:_PerformDeleteMix(name)
    -- Delete from internal registry
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:DeleteMacro(name)
    end

    -- Delete generated and legacy WoW macros if they exist.
    local generatedIndex = GetMacroIndexByName(GetSafeMixMacroName(name))
    if generatedIndex > 0 then
        DeleteMacro(generatedIndex)
    end
    local index = GetMacroIndexByName(name)
    if index > 0 then
        DeleteMacro(index)
    end

    if OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes[name] = nil
    end

    -- Also remove from assignments
    local mappings = OxedHub.db.profile.emotionMappings or {}
    for emotion, data in pairs(mappings) do
        if data.toyMacro == name then
            data.toyMacro = nil
        end
    end

    self:RefreshSavedMixesList()
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

function Toys:DeleteMix(name)
    if InCombatLockdown() then
        print("|cffff0000OxedHub:|r Cannot delete mixes in combat.")
        return
    end

    -- Check if skip confirmation is enabled
    if OxedHub.db.profile.settings and OxedHub.db.profile.settings.skipDeleteConfirmation then
        self:_PerformDeleteMix(name)
        return
    end

    -- Show confirmation dialog
    StaticPopupDialogs["OXEDHUB_CONFIRM_DELETE_MIX"] = {
        text = "Are you sure you wish to delete the mix '%s'?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function(self, data)
            Toys:_PerformDeleteMix(data)
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("OXEDHUB_CONFIRM_DELETE_MIX", name, nil, name)
end

-- Rename Mix
-- Popup with an edit box to rename a saved mix.
function Toys:ShowRenameMixDialog(oldName)
    if not oldName then return end
    StaticPopupDialogs["OXEDHUB_RENAME_MIX"] = {
        text = (L["MIXER_RENAME_PROMPT"] or "Rename mix '%s' to:"),
        button1 = ACCEPT or "Accept",
        button2 = CANCEL or "Cancel",
        hasEditBox = true,
        maxLetters = 64,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local eb = self.editBox or self.EditBox
            if eb then
                eb:SetText(oldName)
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        EditBoxOnEnterPressed = function(self)
            local newName = self:GetText()
            if newName and newName ~= "" and newName ~= oldName then
                Toys:RenameMix(oldName, newName)
            end
            local parent = self:GetParent()
            if parent and parent.Hide then parent:Hide() end
        end,
        OnAccept = function(self)
            local eb = self.editBox or self.EditBox
            local newName = eb and eb:GetText()
            if newName and newName ~= "" and newName ~= oldName then
                Toys:RenameMix(oldName, newName)
            end
        end,
    }
    StaticPopup_Show("OXEDHUB_RENAME_MIX", oldName)
end

function Toys:RenameMix(oldName, newName)
    if InCombatLockdown() then
        print("|cffff0000OxedHub:|r Cannot rename mixes in combat.")
        return
    end

    -- Rename via internal registry
    if OxedHub.MacroRegistry then
        if not OxedHub.MacroRegistry:RenameMacro(oldName, newName) then
            print("|cffff0000OxedHub:|r Mix name '" .. newName .. "' already exists.")
            return
        end
    end

    -- Remove generated macro for the old name; the drag icon will create a fresh one.
    local generatedIndex = GetMacroIndexByName(GetSafeMixMacroName(oldName))
    if generatedIndex > 0 then
        DeleteMacro(generatedIndex)
    end

    -- Rename legacy WoW macro if it exists.
    local legacyIndex = GetMacroIndexByName(oldName)
    if legacyIndex > 0 and GetMacroIndexByName(newName) == 0 then
        local _, icon, body = GetMacroInfo(legacyIndex)
        EditMacro(legacyIndex, newName, icon, body)
    end

    -- Update DB
    if OxedHub.db.profile.toyMixes then
        local data = OxedHub.db.profile.toyMixes[oldName]
        OxedHub.db.profile.toyMixes[oldName] = nil
        OxedHub.db.profile.toyMixes[newName] = data or true
    end

    -- Update assignments
    local mappings = OxedHub.db.profile.emotionMappings or {}
    for emotion, data in pairs(mappings) do
        if data.toyMacro == oldName then
            data.toyMacro = newName
        end
    end

    self:RefreshSavedMixesList()
    self:RefreshQuickMixesGrid()
    RefreshMixConsumers()
end

-- Load a saved mix into the mixer state for editing
function Toys:LoadMixIntoMixer(name)
    local data = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name]
    if type(data) ~= "table" then return end

    for i = 1, 4 do selectedSlots[i] = nil end
    for k in pairs(mixerActions) do mixerActions[k] = nil end

    if data.slots then
        for i = 1, 4 do
            if data.slots[i] then selectedSlots[i] = { type = data.slots[i].type, id = data.slots[i].id } end
        end
    end

    mixerRandomToys = data.randomToys == true
    if self.mixerRandomCheck then self.mixerRandomCheck:SetChecked(mixerRandomToys) end
    if self.UpdateRandomSlotsVisibility then self:UpdateRandomSlotsVisibility() end

    if data.actions then
        mixerActions.sound = data.actions.sound
        mixerActions.animation = data.actions.animation
        mixerActions.emote = data.actions.emote
        mixerActions.chat = data.actions.chat
    end

    if self.UpdateMixerIcons then self:UpdateMixerIcons() end
    if self.mixerSoundBtn then
        local disp = mixerActions.sound and Toys:GetSoundDisplayName(mixerActions.sound)
        self.mixerSoundBtn:SetText(disp or mixerActionButtonText.sound)
    end
    if self.mixerEmoteBtn then
        local disp = mixerActions.emote and TruncateText(mixerActions.emote, 15)
        self.mixerEmoteBtn:SetText(disp or mixerActionButtonText.emote)
    end
    if self.mixerAnimBtn then
        local anim = mixerActions.animation and OxedHub.db.profile.animations[mixerActions.animation]
        local disp = anim and anim.name and TruncateText(anim.name, 15)
        self.mixerAnimBtn:SetText(disp or mixerActionButtonText.animation)
    end
    if self.mixerChatBtn then
        local chat = mixerActions.chat and OxedHub.db.profile.chatTemplates[mixerActions.chat]
        local disp = chat and chat.name and TruncateText(chat.name, 15)
        self.mixerChatBtn:SetText(disp or mixerActionButtonText.chat)
    end
end

-- Save current mixer state back to a mix name
function Toys:SaveMixerStateToMix(name)
    if not name or name == "" then return end
    local mixData = {
        slots = {},
        randomToys = mixerRandomToys,
        actions = {
            sound = mixerActions.sound,
            emote = mixerActions.emote,
            animation = mixerActions.animation,
            chat = mixerActions.chat
        }
    }
    for i = 1, 4 do
        if selectedSlots[i] then mixData.slots[i] = { type = selectedSlots[i].type, id = selectedSlots[i].id } end
    end

    -- Preserve any existing custom macro body
    local existingMix = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name]
    if type(existingMix) == "table" and existingMix.customMacroBody then
        mixData.customMacroBody = existingMix.customMacroBody
    end

    if OxedHub.db.profile.toyMixes then
        OxedHub.db.profile.toyMixes[name] = mixData
    end
    if OxedHub.MacroRegistry then
        OxedHub.MacroRegistry:SaveMacro(name, mixData)
    end
    if self:HasGeneratedMixMacro(name) then
        self:CreateMacroForMix(name, true)
    end
    self:RefreshQuickMixesGrid()
end

-- Edit a specific component of a saved mix
-- Open a saved mix in the Mixer tab for full editing (change toys/spells/actions).
-- Unlike EditMixComponent, this does NOT clear any slot — it loads everything as-is
-- and puts the mixer in "Update Mix" mode so Save overwrites the existing mix.
function Toys:EditMix(mixName)
    self:LoadMixIntoMixer(mixName)
    self.currentMixName = mixName
    self.editingMixName = mixName
    if self.mixerSaveBtn then
        self.mixerSaveBtn:SetText("Update Mix")
    end
    if OxedHub.UI and OxedHub.UI.ShowToysSubTab then
        OxedHub.UI:ShowToysSubTab("Mixer")
    end
end

function Toys:EditMixComponent(mixName, componentType)
    self:LoadMixIntoMixer(mixName)
    self.currentMixName = mixName
    self.editingMixName = mixName
    if self.mixerSaveBtn then
        self.mixerSaveBtn:SetText("Update Mix")
    end

    local function SaveAndRefresh()
        self:SaveMixerStateToMix(mixName)
        self:RefreshSavedMixesList()
    end

    if componentType == "slot1" then
        selectedSlots[1] = nil
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if OxedHub.UI and OxedHub.UI.ShowToysSubTab then OxedHub.UI:ShowToysSubTab("Mixer") end
        print("|cff00ff00[OxedHub]|r " .. (L["MIXER_SLOT1_PRINT"] or "Click a toy or spell in the grid to set Slot 1, then Save Mix."))
    elseif componentType == "slot2" then
        selectedSlots[2] = nil
        if self.UpdateMixerIcons then self:UpdateMixerIcons() end
        if OxedHub.UI and OxedHub.UI.ShowToysSubTab then OxedHub.UI:ShowToysSubTab("Mixer") end
        print("|cff00ff00[OxedHub]|r " .. (L["MIXER_SLOT2_PRINT"] or "Click a toy or spell in the grid to set Slot 2, then Save Mix."))
    elseif componentType == "emote" then
        OxedHub.Triggers:ShowEmotePicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif componentType == "chat" then
        if mixerActions.chat and not mixerActions.chatMessage then
            mixerActions.chatMessage = mixerActions.chat
        end
        OxedHub.Triggers:ShowChatPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function(self)
            mixerActions.chat = mixerActions.chatMessage
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
            if orig then orig(self) end
        end
    elseif componentType == "animation" then
        OxedHub.Triggers:ShowAnimationPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    elseif componentType == "sound" then
        OxedHub.Triggers:ShowSoundPicker({ actions = mixerActions })
        local orig = OxedHub.Triggers.RefreshTriggersList
        OxedHub.Triggers.RefreshTriggersList = function()
            SaveAndRefresh()
            OxedHub.Triggers.RefreshTriggersList = orig
        end
    end
end

-- Use a toy by itemID (called from triggers)
function Toys:UseToy(itemID, eventData)
    if not itemID then return end
    local id = tonumber(itemID)
    if not id then return end
    if PlayerHasToy(id) then
        C_ToyBox.UseToyByItemID(id)
    end
end

-- Compact helper: play sound + animation from a single /run line in macros
-- Called as: OxedHub.Toys:E("soundKey","animKey")
function Toys:E(soundKey, animKey)
    if soundKey and soundKey ~= "" and OxedHub.Sounds then
        OxedHub.Sounds:Play(soundKey)
    end
    if animKey and animKey ~= "" and OxedHub.Animations then
        OxedHub.Animations:Play(animKey)
    end
end

-- Build a single compact /run line for sound + animation
function Toys:BuildExtrasRunLine(soundKey, animKey)
    if not soundKey and not animKey then return nil end
    local s = soundKey and ('"' .. soundKey .. '"') or 'nil'
    local a = animKey and ('"' .. animKey .. '"') or 'nil'
    return '/run OxedHub.Toys:E(' .. s .. ',' .. a .. ')\n'
end

-- Get the auto-generated macro text ignoring any custom overrides
function Toys:GetDefaultMixMacroText(mixData)
    if type(mixData) ~= "table" then return nil end
    local savedCustomBody = mixData.customMacroBody
    mixData.customMacroBody = nil
    local result = self:GetMixMacroText(mixData)
    mixData.customMacroBody = savedCustomBody
    return result
end

-- Generate a real WoW macro from mix data and execute it
-- This is the only reliable way to use toys and cast spells from a button click
-- Build macro text from saved mix data (for secure action buttons)
-- resolveRandom: when true (used by the ActionHub click path, which regenerates
-- the macro on every hardware press), random mode resolves to a single concrete
-- "/use <toy>" chosen from the currently usable toys instead of "/castrandom".
-- This is far more reliable than /castrandom, which sticks on a pick that is on
-- cooldown and can be swallowed when combined with a spell cast.
function Toys:GetMixMacroText(mixData, resolveRandom)
    if type(mixData) ~= "table" then return nil end

    -- If user has a custom macro body override, use it directly
    if mixData.customMacroBody and mixData.customMacroBody ~= "" then
        local body = mixData.customMacroBody
        if #body > 255 then body = body:sub(1, 255) end
        self:Debug("GetMixMacroText: using CUSTOM body override (random logic skipped)")
        return body
    end

    local body = "#showtooltip\n"
    local toyNames = {}
    local toyIds = {}
    local useRandom = mixData.randomToys == true

    self:Debug("GetMixMacroText: randomToys =", tostring(useRandom), "| slots =", #(mixData.slots or {}))

    -- IMPORTANT: emit toy lines BEFORE spell casts. A harmful/targeted spell (e.g.
    -- Wake of Ashes) placed first can error on a bad target and abort the macro,
    -- eating the toys behind it. Toys are always usable, so firing them first
    -- guarantees they run regardless of the player's current target.
    local spellLines = {}
    for i, slot in ipairs(mixData.slots or {}) do
        if slot then
            if slot.type == "toy" then
                local _, name = C_ToyBox.GetToyInfo(slot.id)
                local owned = self:DoesPlayerOwnToy(slot.id)
                self:Debug(("  slot %d: toy id=%s name=%s owned=%s"):format(
                    i, tostring(slot.id), tostring(name), tostring(owned)))
                if name and owned then
                    if useRandom then
                        table.insert(toyNames, name)
                        table.insert(toyIds, slot.id)
                    else
                        body = body .. "/use " .. name .. "\n"
                    end
                elseif not owned then
                    self:Debug("    -> SKIPPED (toy not owned / not usable)")
                elseif not name then
                    self:Debug("    -> SKIPPED (no toy name from C_ToyBox — data not cached?)")
                end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.name then
                    table.insert(spellLines, "/cast " .. spellInfo.name .. "\n")
                    self:DebugSpell(i, slot.id, spellInfo)
                end
            end
        end
    end

    -- Random mode: either resolve to one concrete /use (reliable, click path) or
    -- fall back to /castrandom (for a static action-bar macro that can't re-pick).
    if useRandom and #toyNames > 0 then
        if resolveRandom then
            local pickName = self:PickUsableRandomToy(toyIds, toyNames)
            body = body .. "/use " .. pickName .. "\n"
            self:Debug("  random RESOLVED to single usable toy: " .. pickName)
        else
            body = body .. "/castrandom " .. table.concat(toyNames, ", ") .. "\n"
            self:Debug("  random toys collected (" .. #toyNames .. "): " .. table.concat(toyNames, ", "))
        end
    elseif useRandom then
        self:Debug("  random mode ON but 0 usable toys collected -> no /castrandom line written")
    end

    -- Spell casts go AFTER toys (see note above), so a targeted spell can't
    -- abort the macro before the toys fire.
    for _, line in ipairs(spellLines) do
        body = body .. line
    end

    local actions = mixData.actions or {}
    if actions.emote then
        body = body .. "/" .. actions.emote:lower() .. "\n"
    end
    if actions.chat then
        local chat = OxedHub.db.profile.chatTemplates[actions.chat]
        if chat then
            body = body .. "/" .. chat.channel:lower() .. " " .. chat.text .. "\n"
        end
    end
    -- Combine sound + animation into one compact /run to save macro space
    local extras = self:BuildExtrasRunLine(actions.sound, actions.animation)
    if extras then
        body = body .. extras
    end

    if #body > 255 then
        self:Debug("  WARNING: macro body is " .. #body .. " chars — TRUNCATED to 255! Random toys at the end may be cut off.")
        body = body:sub(1, 255)
    end
    if self.debug then
        self:Debug("  final macro body (" .. #body .. " chars):")
        for line in body:gmatch("[^\n]+") do
            print("|cffff9900[OxedHub DBG]|r     " .. line)
        end
    end
    return body
end

function Toys:GetMixMacroName(mixName)
    return GetSafeMixMacroName(mixName)
end

function Toys:HasGeneratedMixMacro(mixName)
    return GetMacroIndexByName(self:GetMixMacroName(mixName)) > 0
end

function Toys:CreateMacroForMix(mixName, silent)
    if InCombatLockdown() then
        if not silent then
            print("|cffff0000[OxedHub]|r Cannot create mix macros in combat.")
        end
        return
    end

    local mixData = OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[mixName]
    if type(mixData) ~= "table" and OxedHub.MacroRegistry then
        mixData = OxedHub.MacroRegistry:GetMacros()[mixName]
    end
    if type(mixData) ~= "table" then
        if not silent then
            print("|cffff0000[OxedHub]|r Mix not found: " .. tostring(mixName))
        end
        return
    end

    local body = self:GetMixMacroText(mixData)
    if not body or body == "#showtooltip\n" then
        if not silent then
            print("|cffff0000[OxedHub]|r This mix has no usable toy, spell, or action.")
        end
        return
    end

    local _, missingToys = self:GetMixToyAvailability(mixData)

    local macroName = self:GetMixMacroName(mixName)
    local icon = self:GetMixIcon(mixName) or "INV_MISC_QUESTIONMARK"
    if mixData.customMacroIcon and mixData.customMacroIcon ~= "" and OxedHub.Triggers then
        icon = OxedHub.Triggers:ResolveCustomMacroIcon(mixData.customMacroIcon) or icon
    end
    local index = GetMacroIndexByName(macroName)
    if index > 0 then
        EditMacro(index, macroName, icon, body)
        if not silent then
            print("|cff00ff00[OxedHub]|r Mix macro updated. Drag the icon to your bar.")
        end
    else
        local _, numChar = GetNumMacros()
        if numChar >= 18 then
            if not silent then
                print("|cffff0000[OxedHub]|r Your Character Macro slots are full (18/18). Please delete one.")
            end
            return
        end
        CreateMacro(macroName, icon, body, 1)
        if not silent then
            print("|cff00ff00[OxedHub]|r Mix macro created. Drag the icon to your bar!")
        end
    end

    if missingToys > 0 and not silent then
        print("|cffffcc00[OxedHub]|r Mix |cffffff00" .. tostring(mixName) .. "|r has |cffffff00" .. missingToys .. "|r missing toy(s). Missing toys were skipped.")
    end

    return macroName
end

function Toys:CreateInternalMixMacro(silent)
    if InCombatLockdown() then
        if not silent then
            print("|cffff0000[OxedHub]|r Cannot create mix macros in combat.")
        end
        return
    end

    local mixData = {
        slots = { selectedSlots[1], selectedSlots[2], selectedSlots[3], selectedSlots[4] },
        randomToys = mixerRandomToys,
        actions = {
            emote = mixerActions.emote,
            chat = mixerActions.chat,
            sound = mixerActions.sound,
            animation = mixerActions.animation,
        }
    }

    local body = self:GetMixMacroText(mixData)
    if not body or body == "#showtooltip\n" then
        if not silent then
            print("|cffff0000[OxedHub]|r This mix has no usable toy, spell, or action.")
        end
        return
    end

    local macroName = "OH_InternalMix"
    local firstIcon = "INV_MISC_QUESTIONMARK"
    for i = 1, 4 do
        if selectedSlots[i] then
            if selectedSlots[i].type == "toy" then
                local _, _, ic = C_ToyBox.GetToyInfo(selectedSlots[i].id)
                if ic then firstIcon = ic; break end
            else
                local spellInfo = C_Spell.GetSpellInfo(selectedSlots[i].id)
                if spellInfo and spellInfo.iconID then firstIcon = spellInfo.iconID; break end
            end
        end
    end

    local index = GetMacroIndexByName(macroName)
    if index > 0 then
        EditMacro(index, macroName, firstIcon, body)
        if not silent then
            print("|cff00ff00[OxedHub]|r Internal mix macro updated. Drag the icon to your bar.")
        end
    else
        local _, numChar = GetNumMacros()
        if numChar >= 18 then
            if not silent then
                print("|cffff0000[OxedHub]|r Your Character Macro slots are full (18/18). Please delete one.")
            end
            return
        end
        CreateMacro(macroName, firstIcon, body, 1)
        if not silent then
            print("|cff00ff00[OxedHub]|r Internal mix macro created. Drag the icon to your bar!")
        end
    end

    return macroName
end

function Toys:GenerateAndExecuteMix(mixData)
    print("|cff00ff00[DEBUG]|r GenerateAndExecuteMix called")
    print("|cff00ff00[DEBUG]|r mixData type:", type(mixData))
    
    if not mixData then 
        print("|cffff0000[DEBUG]|r mixData is nil!")
        return 
    end
    
    if InCombatLockdown() then
        print("|cffff0000[OxedHub]|r Cannot run mix in combat.")
        return
    end

    print("|cff00ff00[DEBUG]|r Getting macro text...")
    local body = self:GetMixMacroText(mixData)
    
    if not body then 
        print("|cffff0000[DEBUG]|r GetMixMacroText returned nil!")
        return 
    end
    
    print("|cff00ff00[DEBUG]|r Macro body length:", #body)
    print("|cff00ff00[DEBUG]|r Macro body:")
    print(body)

    local tempName = "OxedHub_RunMix"
    print("|cff00ff00[DEBUG]|r Creating/updating macro:", tempName)
    
    local index = GetMacroIndexByName(tempName)
    print("|cff00ff00[DEBUG]|r Macro index:", index)
    
    if index > 0 then
        EditMacro(index, tempName, nil, body)
        print("|cff00ff00[DEBUG]|r Macro updated")
    else
        CreateMacro(tempName, "INV_MISC_QUESTIONMARK", body, 1)
        print("|cff00ff00[DEBUG]|r Macro created")
    end

    -- ExecuteMacro doesn't exist; use a temporary secure button
    if not self.runMixSecureBtn then
        print("|cff00ff00[DEBUG]|r Creating secure button...")
        self.runMixSecureBtn = CreateFrame("Button", "OxedHubTempRunMix", UIParent, "SecureActionButtonTemplate")
        self.runMixSecureBtn:SetAttribute("type", "macro")
        print("|cff00ff00[DEBUG]|r Secure button created")
    end
    
    print("|cff00ff00[DEBUG]|r Setting macrotext attribute...")
    self.runMixSecureBtn:SetAttribute("macrotext", body)
    
    print("|cff00ff00[DEBUG]|r Clicking secure button...")
    self.runMixSecureBtn:Click()
    
    print("|cff00ff00[DEBUG]|r Secure button clicked!")
end

-- Get icon texture from saved mix data (first toy or spell icon)
function Toys:GetMixIcon(name)
    local mixData = (OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name])
        or (OxedHub.MacroRegistry and OxedHub.MacroRegistry:GetMacros()[name])
    if type(mixData) ~= "table" then return nil end

    -- Check for custom icon first
    if mixData.customMacroIcon and mixData.customMacroIcon ~= "" and OxedHub.Triggers then
        local resolved = OxedHub.Triggers:ResolveCustomMacroIcon(mixData.customMacroIcon)
        if resolved then return resolved end
    end

    if not mixData.slots then return nil end
    for _, slot in ipairs(mixData.slots) do
        if slot then
            if slot.type == "toy" then
                local icon = GetToyIconTexture(slot.id)
                if icon then return icon end
            elseif slot.type == "spell" then
                local spellInfo = C_Spell.GetSpellInfo(slot.id)
                if spellInfo and spellInfo.iconID then return spellInfo.iconID end
            end
        end
    end
    return nil
end

-- Returns the resolved custom icon for a mix, or nil if none is set
function Toys:GetMixCustomIcon(name)
    local mixData = (OxedHub.db.profile.toyMixes and OxedHub.db.profile.toyMixes[name])
        or (OxedHub.MacroRegistry and OxedHub.MacroRegistry:GetMacros()[name])
    if type(mixData) ~= "table" then return nil end
    if mixData.customMacroIcon and mixData.customMacroIcon ~= "" and OxedHub.Triggers then
        return OxedHub.Triggers:ResolveCustomMacroIcon(mixData.customMacroIcon)
    end
    return nil
end
