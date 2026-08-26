local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.PvPSpellPicker = {}

local CLASS_ICONS = {
    ["DEATHKNIGHT"] = "classicon_deathknight",
    ["DEMONHUNTER"] = "classicon_demonhunter",
    ["DRUID"]       = "classicon_druid",
    ["EVOKER"]      = "classicon_evoker",
    ["HUNTER"]      = "classicon_hunter",
    ["MAGE"]        = "classicon_mage",
    ["MONK"]        = "classicon_monk",
    ["PALADIN"]     = "classicon_paladin",
    ["PRIEST"]      = "classicon_priest",
    ["ROGUE"]       = "classicon_rogue",
    ["SHAMAN"]      = "classicon_shaman",
    ["WARLOCK"]     = "classicon_warlock",
    ["WARRIOR"]     = "classicon_warrior",
}

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER"
}

local CLASS_NAMES = {}
for _, token in ipairs(CLASS_ORDER) do
    CLASS_NAMES[token] = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
end

CLASS_NAMES["GENERAL"] = "General"
local CLASS_ORDER_EXTENDED = { "GENERAL" }
for _, c in ipairs(CLASS_ORDER) do
    table.insert(CLASS_ORDER_EXTENDED, c)
end

function OxedHub.UIComponents.PvPSpellPicker:Create(frame, trigger, yOffset, spellDB, dbKey)
    if not spellDB then return yOffset end
    
    trigger.conditions = trigger.conditions or {}
    if not trigger.conditions[dbKey] then
        trigger.conditions[dbKey] = {}
    end
    local disabledSpells = trigger.conditions[dbKey]

    local startX = 445
    local currentY = 30 -- Moved up to match SpellCast.lua
    
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, currentY)
    title:SetText("|cffffd100Spell Tracker|r  |cff888888(click to toggle)|r")
    currentY = currentY - 20

    local classButtons = {}
    local currentClassToken = "GENERAL"
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetSize(450, 105)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, currentY - 30)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(450, 1)
    scrollFrame:SetScrollChild(scrollChild)
    
    if OxedHub.UIComponents.Scroll and OxedHub.UIComponents.Scroll.StyleFrame then
        OxedHub.UIComponents.Scroll.StyleFrame(scrollFrame)
    end
    
    local spellButtons = {}
    
    local function UpdateSpellGrid()
        for _, btn in ipairs(spellButtons) do
            btn:Hide()
        end
        
        local spellsToShow = {}
        local nameToSpellIDs = {}
        local nameToIcon = {}
        
        for spellID, val in pairs(spellDB) do
            if val then
                local sClass = OxedHub.PvPSpellDB.SpellClassMap[tonumber(spellID)] or OxedHub.PvPSpellDB.SpellClassMap[tostring(spellID)] or "GENERAL"
                if sClass == currentClassToken then
                    local name, icon
                    if C_Spell and C_Spell.GetSpellInfo then
                        local info = C_Spell.GetSpellInfo(spellID)
                        if info then
                            name = info.name
                            icon = info.iconID
                        end
                    elseif GetSpellInfo then
                        name, _, icon = GetSpellInfo(spellID)
                    end
                    name = name or ("Unknown " .. spellID)
                    
                    if not nameToSpellIDs[name] then
                        nameToSpellIDs[name] = {}
                        table.insert(spellsToShow, name)
                        nameToIcon[name] = icon or 136206
                    end
                    table.insert(nameToSpellIDs[name], spellID)
                end
            end
        end
        
        table.sort(spellsToShow)
        
        local row, col = 0, 0
        for i, spellName in ipairs(spellsToShow) do
            local btn = spellButtons[i]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
                btn:SetSize(145, 42)
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 }
                })
                
                btn.tick = btn:CreateTexture(nil, "OVERLAY")
                btn.tick:SetSize(16, 16)
                btn.tick:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
                btn.tick:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                
                btn.icon = btn:CreateTexture(nil, "ARTWORK")
                btn.icon:SetSize(30, 30)
                btn.icon:SetPoint("LEFT", 6, 0)
                btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                
                btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                btn.name:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
                btn.name:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
                btn.name:SetJustifyH("LEFT")
                btn.name:SetWordWrap(true)
                
                local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
                highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
                highlight:SetPoint("TOPLEFT", btn.icon, "TOPLEFT", 0, 0)
                highlight:SetPoint("BOTTOMRIGHT", btn.icon, "BOTTOMRIGHT", 0, 0)
                highlight:SetBlendMode("ADD")
                
                btn:SetScript("OnClick", function(self)
                    -- Toggle all spell IDs for this name
                    local anyEnabled = false
                    for _, sid in ipairs(self.spellIDs) do
                        if not disabledSpells[tostring(sid)] then
                            anyEnabled = true
                            break
                        end
                    end
                    
                    if anyEnabled then
                        -- Disable all
                        for _, sid in ipairs(self.spellIDs) do
                            disabledSpells[tostring(sid)] = true
                        end
                    else
                        -- Enable all
                        for _, sid in ipairs(self.spellIDs) do
                            disabledSpells[tostring(sid)] = nil
                        end
                    end
                    self:UpdateState()
                    if OxedHub.Triggers and OxedHub.Triggers.ShowAutoSaved then
                        OxedHub.Triggers.ShowAutoSaved(frame:GetParent())
                    end
                end)
                
                btn.UpdateState = function(self)
                    local anyEnabled = false
                    for _, sid in ipairs(self.spellIDs) do
                        if not disabledSpells[tostring(sid)] then
                            anyEnabled = true
                            break
                        end
                    end
                    
                    if anyEnabled then
                        btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                        btn:SetBackdropColor(0.25, 0.20, 0.05, 0.95)
                        btn.tick:Show()
                        btn.icon:SetDesaturated(false)
                        btn.name:SetTextColor(1, 1, 1)
                    else
                        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
                        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                        btn.tick:Hide()
                        btn.icon:SetDesaturated(true)
                        btn.name:SetTextColor(0.5, 0.5, 0.5)
                    end
                end
                
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(self.spellIDs[1])
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function(self)
                    GameTooltip:Hide()
                end)
                
                spellButtons[i] = btn
            end
            
            btn.spellIDs = nameToSpellIDs[spellName]
            btn.name:SetText(spellName)
            btn.icon:SetTexture(nameToIcon[spellName])
            btn:UpdateState()
            
            btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", col * 147, -(row * 44))
            btn:Show()
            
            col = col + 1
            if col > 2 then
                col = 0
                row = row + 1
            end
        end
        
        local totalRows = math.ceil(#spellsToShow / 3)
        if scrollFrame.oxedMinimalScrollBar then
            if (totalRows * 44) <= 105 then
                scrollFrame.oxedMinimalScrollBar:Hide()
            else
                scrollFrame.oxedMinimalScrollBar:Show()
            end
        end
    end
    
    local xOff = 0
    for _, token in ipairs(CLASS_ORDER_EXTENDED) do
        local hasSpells = false
        for spellID, val in pairs(spellDB) do
            if val and (OxedHub.PvPSpellDB.SpellClassMap[tonumber(spellID)] or OxedHub.PvPSpellDB.SpellClassMap[tostring(spellID)] or "GENERAL") == token then
                hasSpells = true
                break
            end
        end
        
        if hasSpells then
            if currentClassToken == "GENERAL" and token ~= "GENERAL" then
                currentClassToken = token
            end

            local btn = CreateFrame("Button", nil, frame)
            btn:SetSize(26, 26)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", startX + xOff, currentY)
            
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            if token == "GENERAL" then
                icon:SetTexture(136206)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            elseif token == "EVOKER" then
                icon:SetTexture(4574311)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token] then
                    icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[token]))
                end
            end
            
            local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            highlight:SetAllPoints()
            highlight:SetBlendMode("ADD")
            
            local border = btn:CreateTexture(nil, "OVERLAY")
            border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            border:SetBlendMode("ADD")
            border:SetPoint("CENTER")
            border:SetSize(40, 40)
            border:Hide()
            
            btn.border = border
            btn.classToken = token
            
            btn:SetScript("OnClick", function()
                for _, b in ipairs(classButtons) do
                    b.border:Hide()
                    b:SetAlpha(0.5)
                end
                btn.border:Show()
                btn:SetAlpha(1)
                currentClassToken = token
                UpdateSpellGrid()
            end)
            
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(CLASS_NAMES[token] or token, 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
            
            table.insert(classButtons, btn)
            xOff = xOff + 28
        end
    end
    
    for _, btn in ipairs(classButtons) do
        if btn.classToken == currentClassToken then
            btn:GetScript("OnClick")(btn)
            break
        end
    end
    
    return math.min(yOffset, -125)
end
