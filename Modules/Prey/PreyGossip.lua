local addonName, OxedHub = ...

local Prey = OxedHub.Prey or {}
OxedHub.Prey = Prey
local L = OxedHub.L

local PreyGossip = {}
Prey.Gossip = PreyGossip

PreyGossip.ATLAS_BY_TAG = {
    finish     = "Interface\\COMMON\\FavoritesIcon",        -- Gold Star: finishes an achievement
    contribute = "Interface\\COMMON\\Indicator-Yellow",     -- Yellow Dot: progresses an achievement
    complete   = "Interface\\Buttons\\UI-CheckBox-Check",   -- Checkmark: already completed
}

PreyGossip.LABEL_BY_TAG = {
    finish     = "Hunt this prey to finish an achievement!",
    contribute = "Hunt this prey to progress an achievement.",
    complete   = "All achievements for this prey already completed.",
}

PreyGossip.tooltipsHooked = setmetatable({}, { __mode = "k" })
PreyGossip.activeForAstalor = false
PreyGossip.selectedTarget = nil
PreyGossip.cachedOptions = nil

local function StripGossipPrefix(text)
    if not text then return "" end
    local stripped = text:gsub("^%s*%d+%.%s*", "")
    return (stripped:gsub("^%s*(.-)%s*$", "%1"))
end

local function MatchesDifficulty(achName, difficulty)
    if not achName or not difficulty then return false end
    if difficulty == "Normal" then
        return achName:find("Normal Mode") ~= nil
    elseif difficulty == "Hard" then
        return achName:find("Hard Mode") ~= nil or achName:find("%(Hard%)") ~= nil
    elseif difficulty == "Nightmare" then
        return achName:find("Nightmare Mode") ~= nil or achName:find("%(Nightmare%)") ~= nil
    end
    return false
end

local function IsCriteriaDone(achID, criteriaID)
    if not achID or not criteriaID then return false end
    if GetAchievementCriteriaInfoByID then
        local ok, _, _, done = pcall(GetAchievementCriteriaInfoByID, achID, criteriaID)
        if ok and done ~= nil then return done end
    end
    local count = GetAchievementNumCriteria(achID) or 0
    for i = 1, count do
        local ok, _, _, done, _, _, _, _, _, _, critID = pcall(GetAchievementCriteriaInfo, achID, i)
        if ok and critID == criteriaID then
            return done or false
        end
    end
    return false
end

-- Classify a target by checking if any achievement needs it
function PreyGossip:ClassifyTarget(targetName, difficulty)
    if not targetName then return "none" end
    local cleanTarget = StripGossipPrefix(targetName)
    local hasUnfinished = false
    local hasFinish = false
    local anyMatch = false
    local allDone = true

    for questID, data in pairs(Prey.PreyQuestData) do
        local diffIdx, criteriaID, name = data[1], data[2], data[3]
        if name and name:lower() == cleanTarget:lower() then
            if not difficulty or (difficulty == "Normal" and diffIdx == 1)
                or (difficulty == "Hard" and diffIdx == 2)
                or (difficulty == "Nightmare" and diffIdx == 3) then
                
                anyMatch = true
                local achID = Prey.PREY_HUNT_ACHIEVEMENT_IDS[diffIdx]
                if achID then
                    local _, achName, _, achDone = GetAchievementInfo(achID)
                    if not achDone then
                        allDone = false
                        local critDone = IsCriteriaDone(achID, criteriaID)
                        if not critDone then
                            hasUnfinished = true
                            local numCrit = GetAchievementNumCriteria(achID) or 0
                            local completedCount = 0
                            for i = 1, numCrit do
                                local _, _, cDone = GetAchievementCriteriaInfo(achID, i)
                                if cDone then completedCount = completedCount + 1 end
                            end
                            if (numCrit - completedCount) <= 1 then
                                hasFinish = true
                            end
                        end
                    end
                end

                -- Check target specific achievements
                local specList = Prey.PREY_HUNT_ACHIEVEMENTS_BY_QUEST[questID]
                if specList then
                    for _, specAchID in ipairs(specList) do
                        local _, _, _, specDone = GetAchievementInfo(specAchID)
                        if not specDone then
                            allDone = false
                            hasFinish = true
                            hasUnfinished = true
                        end
                    end
                end
            end
        end
    end

    if not anyMatch then return "none" end
    if allDone then return "complete" end
    if hasFinish then return "finish" end
    if hasUnfinished then return "contribute" end
    return "complete"
end

function PreyGossip:ApplyIcon(iconTex, tag)
    if not iconTex or not tag or not self.ATLAS_BY_TAG[tag] then return end
    iconTex:SetTexture(self.ATLAS_BY_TAG[tag])
    local scale = (tag == "finish") and 1.3 or 1.0
    local base = iconTex.Oxed_baseW or 16
    local w, h = iconTex:GetWidth(), iconTex:GetHeight()
    if (not iconTex.Oxed_baseW or iconTex.Oxed_baseW <= 0) and w > 0 then
        iconTex.Oxed_baseW, iconTex.Oxed_baseH = w, h
        base = w
    end
    iconTex:SetSize(base * scale, (iconTex.Oxed_baseH or base) * scale)
end

function PreyGossip:BuildTooltip(name, difficulty)
    local clean = StripGossipPrefix(name)
    local lines = { "|cFFFFD900" .. clean .. "|r" }
    if difficulty then
        table.insert(lines, "|cFFAAAAAADifficulty: |r|cFFFFFFFF" .. difficulty .. "|r")
    end
    table.insert(lines, " ")

    local willProgress = {}
    local alreadyDone = {}

    for questID, data in pairs(Prey.PreyQuestData) do
        local diffIdx, criteriaID, targetName = data[1], data[2], data[3]
        if targetName and targetName:lower() == clean:lower() then
            if not difficulty or (difficulty == "Normal" and diffIdx == 1)
                or (difficulty == "Hard" and diffIdx == 2)
                or (difficulty == "Nightmare" and diffIdx == 3) then
                
                local achID = Prey.PREY_HUNT_ACHIEVEMENT_IDS[diffIdx]
                if achID then
                    local _, achTitle, _, achDone = GetAchievementInfo(achID)
                    local _, _, critDone = GetAchievementCriteriaInfoByID(achID, criteriaID)
                    if critDone or achDone then
                        table.insert(alreadyDone, achTitle)
                    else
                        table.insert(willProgress, achTitle)
                    end
                end

                local specList = Prey.PREY_HUNT_ACHIEVEMENTS_BY_QUEST[questID]
                if specList then
                    for _, specAchID in ipairs(specList) do
                        local _, specTitle, _, specDone = GetAchievementInfo(specAchID)
                        if specDone then
                            table.insert(alreadyDone, specTitle)
                        else
                            table.insert(willProgress, specTitle)
                        end
                    end
                end
            end
        end
    end

    if #willProgress > 0 then
        table.insert(lines, "|cFFFFD933Will Progress / Complete:|r")
        for _, ach in ipairs(willProgress) do
            table.insert(lines, "  |cFFFFFFFF* " .. ach .. "|r")
        end
    end

    if #alreadyDone > 0 then
        if #willProgress > 0 then table.insert(lines, " ") end
        table.insert(lines, "|cFF888888Already Credited:|r")
        for _, ach in ipairs(alreadyDone) do
            table.insert(lines, "  |cFF888888* " .. ach .. "|r")
        end
    end

    table.insert(lines, " ")
    table.insert(lines, "|cFF00D9D9OxedHub Prey Helper|r")
    return lines
end

function PreyGossip:WireTooltip(button, name, difficulty)
    if not button or self.tooltipsHooked[button] then return end
    self.tooltipsHooked[button] = true
    button:HookScript("OnEnter", function(f)
        local lines = PreyGossip:BuildTooltip(name, difficulty or PreyGossip.selectedTargetDifficulty)
        if not lines then return end
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        for _, line in ipairs(lines) do
            GameTooltip:AddLine(line, 1, 1, 1, false)
        end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- True when the user has the gossip helper enabled on the PREY_HUNT trigger.
function PreyGossip:IsEnabled()
    if not (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.triggers) then
        return true
    end
    for _, tr in pairs(OxedHub.db.profile.triggers) do
        if tr.enabled and tr.event == "PREY_HUNT" and tr.conditions then
            return tr.conditions.enableGossipHelper ~= false
        end
    end
    return true
end

function PreyGossip:OnGossipShow()
    local npcID = Prey:GetUnitNpcID("npc")
    self.activeForAstalor = Prey.HUNT_TABLE_NPC_IDS[npcID or -1] == true and self:IsEnabled()
end

function PreyGossip:Initialize()
    -- Hook Blizzard Gossip Option buttons
    if _G.GossipOptionButtonMixin and _G.GossipOptionButtonMixin.Setup then
        hooksecurefunc(_G.GossipOptionButtonMixin, "Setup", function(button, optionInfo)
            if not PreyGossip.activeForAstalor or not optionInfo or not optionInfo.name then return end
            local clean = StripGossipPrefix(optionInfo.name)
            local tag = PreyGossip:ClassifyTarget(clean)
            if tag ~= "none" then
                if button.Icon then PreyGossip:ApplyIcon(button.Icon, tag) end
                PreyGossip:WireTooltip(button, clean)
            end
        end)
    end

    -- Hook DialogueUI if installed
    if _G.DUIDialogOptionButtonMixin and _G.DUIDialogOptionButtonMixin.SetGossip then
        hooksecurefunc(_G.DUIDialogOptionButtonMixin, "SetGossip", function(button, data)
            if not PreyGossip.activeForAstalor or not data or not data.name or not button.Icon then return end
            local clean = StripGossipPrefix(data.name)
            local tag = PreyGossip:ClassifyTarget(clean)
            if tag ~= "none" then
                PreyGossip:ApplyIcon(button.Icon, tag)
                PreyGossip:WireTooltip(button, clean)
            end
        end)
    end
end
