-- Tracking.lua
-- Records actual disenchant outcomes by monitoring bag changes in Shattersight.

local addonName, OxedHub = ...

OxedHub.Shattersight = OxedHub.Shattersight or {}
local SS = OxedHub.Shattersight

local MIN_SAMPLES = 10
SS.MIN_SAMPLES = MIN_SAMPLES

local EQUIPPABLE = {
    INVTYPE_HEAD=true, INVTYPE_NECK=true, INVTYPE_SHOULDER=true,
    INVTYPE_BODY=true, INVTYPE_CHEST=true, INVTYPE_WAIST=true,
    INVTYPE_LEGS=true, INVTYPE_FEET=true, INVTYPE_WRIST=true,
    INVTYPE_HAND=true, INVTYPE_FINGER=true, INVTYPE_TRINKET=true,
    INVTYPE_CLOAK=true, INVTYPE_WEAPON=true, INVTYPE_SHIELD=true,
    INVTYPE_RANGED=true, INVTYPE_2HWEAPON=true, INVTYPE_WEAPONMAINHAND=true,
    INVTYPE_WEAPONOFFHAND=true, INVTYPE_HOLDABLE=true, INVTYPE_THROWN=true,
    INVTYPE_RANGEDRIGHT=true, INVTYPE_ROBE=true, INVTYPE_TABARD=true,
    INVTYPE_PROFESSION_GEAR=true, INVTYPE_PROFESSION_TOOL=true,
}
SS.EQUIPPABLE = EQUIPPABLE

local lastSnapshot = nil
local debugMode = false

local function DebugPrint(...)
    if debugMode then
        print("|cFFFF9900[Shattersight Track]|r", ...)
    end
end

local function SnapshotBags()
    local snapshot = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID and info.itemID > 0 then
                    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(info.hyperlink or info.itemID)
                    local _, _, quality, _, _, _, _, _, _, _, _, _, _, _, expansionID =
                        C_Item.GetItemInfo(info.hyperlink or info.itemID)

                    if not quality and info.hyperlink then
                        local hex = info.hyperlink:match("^|c%x%x(%x%x%x%x%x%x)")
                        if hex then
                            quality = ({
                                ["9D9D9D"]=0, ["FFFFFF"]=1, ["1EFF00"]=2,
                                ["0070DD"]=3, ["A335EE"]=4, ["FF8000"]=5, ["E6CC80"]=6,
                            })[hex:upper()]
                        end
                    end

                    snapshot[bag .. "_" .. slot] = {
                        itemID      = info.itemID,
                        count       = info.stackCount or 1,
                        link        = info.hyperlink,
                        quality     = quality,
                        expansionID = expansionID,
                        equipLoc    = equipLoc,
                    }
                end
            end
        end
    end
    return snapshot
end

local function DiffSnapshots(before, after)
    local removed, added = {}, {}

    for key, b in pairs(before) do
        local a = after[key]
        if not a then
            table.insert(removed, b)
        elseif a.itemID ~= b.itemID then
            table.insert(removed, b)
            table.insert(added, a)
        elseif a.count < b.count then
            local copy = {}
            for k, v in pairs(b) do copy[k] = v end
            copy.count = b.count - a.count
            table.insert(removed, copy)
        end
    end

    for key, a in pairs(after) do
        local b = before[key]
        if not b then
            table.insert(added, a)
        elseif a.itemID == b.itemID and a.count > b.count then
            local copy = {}
            for k, v in pairs(a) do copy[k] = v end
            copy.count = a.count - b.count
            table.insert(added, copy)
        end
    end

    return removed, added
end

local function IsKnownMat(itemID)
    for _, mat in pairs(SS.MATS) do
        if mat.id and mat.id > 0 and mat.id == itemID then
            return true
        end
    end
    return false
end

local function GetSpecSkillBonus(specLine, quality)
    if not C_ProfSpecs then return 0 end
    local getConfig   = C_ProfSpecs.GetConfigIDForSkillLine
    local getTabs     = C_ProfSpecs.GetSpecTabIDsForSkillLine
    local getRootPath = C_ProfSpecs.GetRootPathForTab
    local getChildren = C_ProfSpecs.GetChildrenForPath
    if not (getConfig and getTabs and getRootPath and getChildren) then
        return 0
    end

    local configID = getConfig(specLine)
    if not configID or configID == 0 then return 0 end

    local tabIDs = getTabs(specLine)
    if not tabIDs then return 0 end

    local bonus = 0
    for _, tabID in ipairs(tabIDs) do
        local rootPath = getRootPath(tabID)
        if rootPath then
            local visited = {}
            local function WalkPath(pathID)
                if visited[pathID] then return end
                visited[pathID] = true

                local nodeData = SS.MIDNIGHT_SPEC_NODES and SS.MIDNIGHT_SPEC_NODES[pathID]
                if nodeData then
                    local applies = (nodeData.qualityFilter == nil)
                                 or (quality ~= nil and nodeData.qualityFilter == quality)
                    if applies then
                        local points = nil
                        if C_Traits and C_Traits.GetNodeInfo then
                            local ok, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, pathID)
                            if ok and nodeInfo and type(nodeInfo.currentRank) == "number" then
                                points = nodeInfo.currentRank
                            end
                        end
                        if points and points > 0 then
                            bonus = bonus + points * (nodeData.perPointSkill or 0)
                            for _, bp in ipairs(nodeData.breakpoints or {}) do
                                if points >= bp.minPoints then
                                    bonus = bonus + (bp.skill or 0)
                                end
                            end
                        end
                    end
                end

                local children = getChildren(pathID)
                for _, child in ipairs(children or {}) do
                    WalkPath(child)
                end
            end
            WalkPath(rootPath)
        end
    end
    return bonus
end

local function GetEnchantingSkillForQuality(quality)
    local prof1, prof2 = GetProfessions()
    for _, idx in ipairs({ prof1, prof2 }) do
        if idx then
            local name, _, skillLevel, _, _, _, skillLine, skillModifier = GetProfessionInfo(idx)
            if name and name:lower():find("enchanting") then
                local specSkillLine = skillLine
                if skillLine and C_ProfSpecs and C_ProfSpecs.GetDefaultSpecSkillLine then
                    local candidate = C_ProfSpecs.GetDefaultSpecSkillLine(skillLine) or skillLine
                    if candidate ~= skillLine
                       and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                        local candInfo = C_TradeSkillUI.GetProfessionInfoBySkillLineID(candidate)
                        if candInfo then
                            local candName = candInfo.professionName or candInfo.displayName or ""
                            if not candName:lower():find("enchanting") then
                                candidate = skillLine
                            end
                        else
                            candidate = skillLine
                        end
                    end
                    specSkillLine = candidate
                end

                local baseSkill
                if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                    local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(specSkillLine)
                    if info and info.skillLevel then
                        baseSkill = info.skillLevel + (info.skillModifier or 0)
                    end
                end
                if not baseSkill then
                    baseSkill = skillLevel + (skillModifier or 0)
                end

                local specBonus = GetSpecSkillBonus(specSkillLine, quality)
                local total = baseSkill + specBonus
                DebugPrint(string.format(
                    "Enchanting skill (specLine=%d quality=%s): base=%d specBonus=%d total=%d",
                    specSkillLine, tostring(quality), baseSkill, specBonus, total))
                return total
            end
        end
    end
    return nil
end

local function GetSkillCacheTable()
    return SS.charDb and SS.charDb.skillCache
end

local function UpdateSkillCache()
    local cache = GetSkillCacheTable()
    if not cache then return end
    local function store(quality, key)
        local skill = GetEnchantingSkillForQuality(quality)
        if skill and skill > 0 then
            cache[key] = skill
            DebugPrint("SkillCache: quality=" .. tostring(quality) .. " skill=" .. skill)
        end
    end
    store(nil, 0)
    store(2, 2)
    store(3, 3)
    store(4, 4)
    if SS.RefreshStatsFrame then SS:RefreshStatsFrame() end
end

local IsEnchantingTradeSkillOpen

local function GetEffectiveSkillForQuality(quality)
    local cache = GetSkillCacheTable()
    local cached = cache and cache[quality or 0]
    if cached and cached > 0 then
        return cached
    end

    if not IsEnchantingTradeSkillOpen() then
        DebugPrint("GetEffectiveSkill: no cache and non-Enchanting window open — returning nil")
        return nil
    end
    local live = GetEnchantingSkillForQuality(quality)
    if live and live > 0 then
        if cache then
            cache[quality or 0] = live
            DebugPrint("GetEffectiveSkill: seeded cache from live: quality="
                .. tostring(quality) .. " → " .. live)
        end
        return live
    end
    return nil
end

local function GetEnchantingSkill()
    return GetEffectiveSkillForQuality(nil)
end
SS.GetEnchantingSkill           = GetEnchantingSkill
SS.GetEnchantingSkillForQuality = GetEffectiveSkillForQuality
SS.UpdateSkillCache             = UpdateSkillCache

local function GetSkillTier(skill)
    if not skill then return nil end
    return math.floor(skill / 25) * 25
end

local function GetTrackingKey(quality, expansionID, skillTier)
    if not quality or not expansionID then return nil end
    local key = expansionID .. "_" .. quality
    if skillTier then
        key = key .. "_" .. skillTier
    end
    return key
end

local function RecordResult(sourceItem, mats)
    if not SS.charDb then return end
    if not SS.charDb.tracking then SS.charDb.tracking = {} end

    local quality     = sourceItem.quality
    local expansionID = sourceItem.expansionID

    if not expansionID then
        for _, mat in ipairs(mats) do
            local matDef = SS.MATS_BY_ID and SS.MATS_BY_ID[mat.itemID]
            if matDef then
                for expID, expData in pairs(SS.DISENCHANT or {}) do
                    for _, results in pairs(expData) do
                        for _, r in ipairs(results) do
                            local key = r.matKey
                            if key and SS.MATS[key] and SS.MATS[key].id == mat.itemID then
                                expansionID = expID
                                break
                            end
                        end
                        if expansionID then break end
                    end
                    if expansionID then break end
                end
                if expansionID then break end
            end
        end
        if expansionID then
            DebugPrint("RecordResult: inferred expansionID", expansionID, "from mats")
        end
    end

    if not quality or not expansionID then
        DebugPrint("RecordResult: quality or expansionID nil, skipping")
        return
    end
    if quality < 2 or quality > 4 then
        DebugPrint("RecordResult: quality", quality, "out of range 2-4, skipping")
        return
    end

    local skillTier = nil
    if expansionID == SS.EXP_MIDNIGHT then
        skillTier = GetSkillTier(GetEffectiveSkillForQuality(quality))
    end

    local key = GetTrackingKey(quality, expansionID, skillTier)
    if not key then return end

    if not SS.charDb.tracking[key] then
        SS.charDb.tracking[key] = {
            quality     = quality,
            expansionID = expansionID,
            skillTier   = skillTier,
            attempts    = 0,
            matTotals   = {},
            matCounts   = {},
        }
    end

    local bucket = SS.charDb.tracking[key]
    if not bucket.matCounts then bucket.matCounts = {} end
    bucket.attempts = bucket.attempts + 1

    for _, mat in ipairs(mats) do
        bucket.matTotals[mat.itemID] = (bucket.matTotals[mat.itemID] or 0) + mat.count
        bucket.matCounts[mat.itemID] = (bucket.matCounts[mat.itemID] or 0) + 1
    end

    DebugPrint(string.format("Recorded: expansionID=%d quality=%d skillTier=%s mats=%d attempt#%d",
        expansionID, quality, tostring(skillTier), #mats, bucket.attempts))

    if SS.RefreshStatsFrame then SS:RefreshStatsFrame() end
end

local pendingSource      = nil
local pendingSourceTimer = nil

local function ClearPendingSource()
    DebugPrint("  Pending source expired without matching mats — cleared")
    pendingSource      = nil
    pendingSourceTimer = nil
end

local function OnBagUpdateDelayed()
    local current = SnapshotBags()

    if not lastSnapshot then
        lastSnapshot = current
        return
    end

    local removed, added = DiffSnapshots(lastSnapshot, current)
    lastSnapshot = current

    if #added == 0 and #removed == 0 then return end

    DebugPrint(string.format("Bag diff: +%d -%d items", #added, #removed))

    local matsAdded = {}
    for _, item in ipairs(added) do
        DebugPrint(string.format("  Added itemID=%d x%d (knownMat=%s)",
            item.itemID, item.count, tostring(IsKnownMat(item.itemID))))
        if IsKnownMat(item.itemID) then
            table.insert(matsAdded, item)
        end
    end

    local sourceItem = nil
    for _, item in ipairs(removed) do
        local q  = item.quality
        local eq = item.equipLoc
        DebugPrint(string.format("  Removed: itemID=%d quality=%s equipLoc=%s",
            item.itemID, tostring(q), tostring(eq)))
        if q and q >= 2 and q <= 4 and eq and EQUIPPABLE[eq] then
            sourceItem = item
            break
        end
    end

    if #matsAdded > 0 then
        if not sourceItem and pendingSource then
            DebugPrint("  Using pending source from previous event:", pendingSource.itemID)
            sourceItem = pendingSource
        end

        if pendingSourceTimer then pendingSourceTimer:Cancel() end
        pendingSource      = nil
        pendingSourceTimer = nil

        if sourceItem then
            DebugPrint("  Source gear found:", sourceItem.itemID, "quality:", sourceItem.quality)
            RecordResult(sourceItem, matsAdded)
        else
            DebugPrint("  No source gear found in removed items — not recording")
        end

    elseif sourceItem then
        DebugPrint("  Equippable removed with no mats — storing as pending source")
        if pendingSourceTimer then pendingSourceTimer:Cancel() end
        pendingSource      = sourceItem
        pendingSourceTimer = C_Timer.NewTimer(3, ClearPendingSource)
    end
end

local function BucketToRates(bucket)
    local rates = {}
    for itemID, total in pairs(bucket.matTotals) do
        local dropCount = bucket.matCounts and bucket.matCounts[itemID]
        table.insert(rates, {
            itemID             = itemID,
            avgQty             = total / bucket.attempts,
            dropChance         = dropCount and (dropCount / bucket.attempts) or nil,
            avgQtyWhenReceived = dropCount and (total / dropCount) or nil,
        })
    end
    table.sort(rates, function(a, b) return a.avgQty > b.avgQty end)
    return rates
end

function SS:GetTrackedRates(quality, expansionID)
    local skillTier = nil
    if expansionID == SS.EXP_MIDNIGHT then
        skillTier = GetSkillTier(GetEffectiveSkillForQuality(quality))
    end

    local key = GetTrackingKey(quality, expansionID, skillTier)
    if not key then return nil end

    if SS.charDb and SS.charDb.tracking then
        local bucket = SS.charDb.tracking[key]
        if bucket and bucket.attempts >= MIN_SAMPLES then
            return BucketToRates(bucket), bucket.attempts, "personal"
        end
    end

    return nil
end

function SS:PrintTrackingStats()
    if not SS.charDb or not SS.charDb.tracking then
        print("|cFF00FFFF[OxedHub Shattersight]:|r No tracking data yet.")
        return
    end

    local qualityNames  = { [2] = "Uncommon (Green)", [3] = "Rare (Blue)", [4] = "Epic (Purple)" }
    local expansionNames = { [10] = "The War Within", [11] = "Midnight" }
    local found = false

    for _, bucket in pairs(SS.charDb.tracking) do
        found = true
        local qName   = qualityNames[bucket.quality]   or ("Quality "   .. tostring(bucket.quality))
        local expName = expansionNames[bucket.expansionID] or ("Expansion " .. tostring(bucket.expansionID))
        print(string.format("|cFF00FFFF[%s — %s]|r %d disenchant(s)",
            expName, qName, bucket.attempts))
        for itemID, total in pairs(bucket.matTotals) do
            local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID))
                      or GetItemInfo(itemID)
                      or ("Item #" .. itemID)
            print(string.format("  %s: avg %.2f per disenchant", name, total / bucket.attempts))
        end
    end

    if not found then
        print("|cFF00FFFF[OxedHub Shattersight]:|r No tracking data yet. Disenchant some items!")
    end
end

function SS:PrintLoginSummary()
    if not SS.charDb then return end

    local cache = SS.charDb.skillCache
    local baseSkill = cache and cache[0]
    local skillStr
    if baseSkill and baseSkill > 0 then
        local parts = {}
        for _, q in ipairs({ 2, 3, 4 }) do
            local qSkill = cache[q]
            if qSkill and qSkill ~= baseSkill then
                local label = q == 2 and "Unc" or q == 3 and "Rare" or "Epic"
                table.insert(parts, label .. ":" .. qSkill)
            end
        end
        skillStr = tostring(baseSkill)
        if #parts > 0 then
            skillStr = skillStr .. " (" .. table.concat(parts, " ") .. ")"
        end
    else
        skillStr = "|cFFFF8C00none cached — open Enchanting to populate|r"
    end

    local tracking = SS.charDb.tracking
    local totalDisenchants = 0
    local bucketCount = 0
    if tracking then
        for _, bucket in pairs(tracking) do
            bucketCount = bucketCount + 1
            totalDisenchants = totalDisenchants + (bucket.attempts or 0)
        end
    end
    local trackStr
    if totalDisenchants > 0 then
        trackStr = string.format("|cFFFFFFFF%d|r disenchant(s) across |cFFFFFFFF%d|r bucket(s)",
            totalDisenchants, bucketCount)
    else
        trackStr = "|cFF888888no data yet|r"
    end

    print(string.format("%s[OxedHub Shattersight]:|r  Skill: %s  |cFF888888·|r  Tracked: %s",
        "|cFF00FFFF", skillStr, trackStr))
end

function SS:ClearTrackingData()
    if SS.charDb then
        SS.charDb.tracking = {}
    end
    print("|cFF00FFFF[OxedHub Shattersight]:|r All personal tracking data cleared.")
    if SS.RefreshStatsFrame then SS:RefreshStatsFrame() end
end

function SS:SkillCheck()
    local out = SS.DebugOutput and function(s) SS:DebugOutput(s) end or print
    if SS.ClearDebugOutput then SS:ClearDebugOutput() end

    local prof1, prof2 = GetProfessions()
    local found = false

    for _, idx in ipairs({ prof1, prof2 }) do
        if idx then
            local name, _, skillLevel, maxSkill, _, _, skillLine, skillModifier = GetProfessionInfo(idx)
            if name and name:lower():find("enchanting") then
                found = true
                out(string.format("GetProfessionInfo: %s  skill=%d/%d  mod=%d  skillLine=%d",
                    name, skillLevel, maxSkill, skillModifier or 0, skillLine or 0))

                local specLine = skillLine
                if skillLine and C_ProfSpecs and C_ProfSpecs.GetDefaultSpecSkillLine then
                    specLine = C_ProfSpecs.GetDefaultSpecSkillLine(skillLine) or skillLine
                end
                out(string.format("Expansion spec skill line: %d  (base=%d)", specLine, skillLine or 0))

                local function dumpTradeSkillInfo(line)
                    if not (C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then return end
                    local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(line)
                    if info then
                        out(string.format("C_TradeSkillUI.GetProfessionInfoBySkillLineID(%d):", line))
                        for k, v in pairs(info) do
                            out(string.format("  .%s = %s", tostring(k), tostring(v)))
                        end
                    else
                        out(string.format("C_TradeSkillUI(%d): nil", line))
                    end
                end
                dumpTradeSkillInfo(skillLine)
                if specLine ~= skillLine then dumpTradeSkillInfo(specLine) end

                out("--- C_ProfSpecs functions ---")
                if C_ProfSpecs then
                    local fnList = {}
                    for k, v in pairs(C_ProfSpecs) do
                        if type(v) == "function" then
                            table.insert(fnList, k)
                        end
                    end
                    table.sort(fnList)
                    for _, fn in ipairs(fnList) do out("  " .. fn) end
                else
                    out("  C_ProfSpecs namespace is nil")
                end

                out(string.format("--- C_ProfSpecs (specLine=%d) ---", specLine))
                if C_ProfSpecs then
                    local configID = C_ProfSpecs.GetConfigIDForSkillLine and
                        C_ProfSpecs.GetConfigIDForSkillLine(specLine) or 0
                    out(string.format("configID = %d", configID))

                    local tabIDs = C_ProfSpecs.GetSpecTabIDsForSkillLine and
                        C_ProfSpecs.GetSpecTabIDsForSkillLine(specLine)
                    out("tabIDs: " .. (tabIDs and ("count="..#tabIDs) or "nil"))

                    for _, tabID in ipairs(tabIDs or {}) do
                        local ok, err = pcall(function()
                            out(string.format("  tab=%d", tabID))

                            local ti = C_ProfSpecs.GetTabInfo and C_ProfSpecs.GetTabInfo(tabID)
                            if ti then
                                for k, v in pairs(ti) do
                                    if type(v) ~= "table" then
                                        out(string.format("    tabInfo.%s = %s", k, tostring(v)))
                                    end
                                end
                            end

                            local tiState = C_ProfSpecs.GetStateForTab and
                                C_ProfSpecs.GetStateForTab(tabID, configID)
                            out(string.format("    tabState (points) = %s", tostring(tiState)))

                            local rootPath = C_ProfSpecs.GetRootPathForTab and
                                C_ProfSpecs.GetRootPathForTab(tabID)
                            if not rootPath then
                                out("    rootPath=nil")
                                return
                            end
                            out(string.format("    rootPath=%d", rootPath))

                            local visited = {}
                            local function WalkPath(pathID, depth)
                                if visited[pathID] or depth > 20 then return end
                                visited[pathID] = true
                                local ind = string.rep("  ", depth + 3)

                                local psOk, ps = pcall(C_ProfSpecs.GetStateForPath, pathID, configID)
                                if not psOk then psOk, ps = pcall(C_ProfSpecs.GetStateForPath, pathID) end

                                local pd = C_ProfSpecs.GetDescriptionForPath and
                                    C_ProfSpecs.GetDescriptionForPath(pathID)

                                local knownNode = SS.MIDNIGHT_SPEC_NODES and SS.MIDNIGHT_SPEC_NODES[pathID]
                                local nodeLabel = knownNode
                                    and ("[" .. knownNode.name .. "]")
                                    or  "[unknown]"

                                local traitRank = "n/a"
                                if C_Traits and C_Traits.GetNodeInfo then
                                    local tok, tInfo = pcall(C_Traits.GetNodeInfo, configID, pathID)
                                    if tok and tInfo then
                                        traitRank = string.format("currentRank=%s maxRanks=%s",
                                            tostring(tInfo.currentRank), tostring(tInfo.maxRanks))
                                    else
                                        traitRank = "ERR:" .. tostring(tInfo)
                                    end
                                end

                                out(string.format("%spath=%d %s  pathState=%s  traitInfo=[%s]  desc=%s",
                                    ind, pathID, nodeLabel,
                                    tostring(psOk and ps or "ERR"),
                                    traitRank,
                                    tostring(pd)))

                                local children = C_ProfSpecs.GetChildrenForPath and
                                    C_ProfSpecs.GetChildrenForPath(pathID)
                                for _, child in ipairs(children or {}) do
                                    WalkPath(child, depth + 1)
                                end
                            end
                            WalkPath(rootPath, 0)
                        end)
                        if not ok then
                            out("  ERROR: " .. tostring(err))
                        end
                    end
                else
                    out("  C_ProfSpecs namespace is nil")
                end

                out("--- Computed effective Enchanting skill ---")
                local qualityNames = { [2]="Uncommon(2)", [3]="Rare(3)", [4]="Epic(4)" }
                local function dumpSkillForQuality(q)
                    local total = GetEnchantingSkillForQuality(q)
                    out(string.format("  quality=%-14s → %s",
                        q and qualityNames[q] or "all (base)",
                        tostring(total)))
                end
                dumpSkillForQuality(nil)
                dumpSkillForQuality(2)
                dumpSkillForQuality(3)
                dumpSkillForQuality(4)

                UpdateSkillCache()
                out("--- Skill cache updated ---")
            end
        end
    end

    if not found then
        out("Enchanting profession not found.")
    end
end

function SS:ToggleTrackDebug()
    debugMode = not debugMode
    print("|cFF00FFFF[OxedHub Shattersight]:|r Tracking debug "
        .. (debugMode and "|cFF00FF00ON|r" or "|cFFFF4444OFF|r"))
end

function SS:RegisterTrackingEvents(frame)
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("TRADE_SKILL_SHOW")
    frame:RegisterEvent("SKILL_LINES_CHANGED")
end

IsEnchantingTradeSkillOpen = function()
    local function dbg(s)
        if debugMode and SS.DebugOutput then SS:DebugOutput(s) end
    end

    if not (C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo) then
        dbg("IsEnchantingTradeSkillOpen: GetBaseProfessionInfo unavailable — allowing update")
        return true
    end
    local info = C_TradeSkillUI.GetBaseProfessionInfo()
    if not info then
        dbg("IsEnchantingTradeSkillOpen: GetBaseProfessionInfo returned nil — allowing update")
        return true
    end
    dbg("IsEnchantingTradeSkillOpen: GetBaseProfessionInfo fields:")
    for k, v in pairs(info) do
        dbg(string.format("  .%s = %s", tostring(k), tostring(v)))
    end
    local name = info.professionName or info.displayName
    if not name then
        dbg("IsEnchantingTradeSkillOpen: no professionName/displayName field — allowing update")
        return true
    end
    local isEnchanting = name:lower():find("enchanting") ~= nil
    dbg(string.format("IsEnchantingTradeSkillOpen: professionName=%q → %s",
        name, isEnchanting and "ENCHANTING" or "OTHER — skipping"))
    return isEnchanting
end

function SS:HandleTrackingEvent(event)
    if event == "BAG_UPDATE_DELAYED" then
        OnBagUpdateDelayed()
    elseif event == "PLAYER_ENTERING_WORLD" then
    elseif event == "SKILL_LINES_CHANGED" then
        C_Timer.After(0, function()
            if IsEnchantingTradeSkillOpen() then UpdateSkillCache() end
        end)
    elseif event == "TRADE_SKILL_SHOW" then
        C_Timer.After(0, function()
            if IsEnchantingTradeSkillOpen() then
                UpdateSkillCache()
            end
        end)
    end
end
