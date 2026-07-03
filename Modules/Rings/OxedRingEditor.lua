local addonName, OxedHub = ...
local OxedRingEditor = {}
OxedHub.OxedRingEditor = OxedRingEditor
local L = OxedHub.L

local CreateFrame = CreateFrame
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi
local math_floor = math.floor
local table = table
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local tonumber = tonumber

local previewNodes = {}
local selectedNodeIndex = nil
local rightPanel = nil
local rightPanelContent = nil

local bindingEditBox = CreateFrame("EditBox", "OxedRingBindingEditBox", UIParent)
bindingEditBox:SetSize(1, 1)
bindingEditBox:SetPoint("BOTTOMLEFT", UIParent, "TOPRIGHT", 100, 100)
bindingEditBox:Hide()
bindingEditBox:SetAutoFocus(false)

bindingEditBox:SetScript("OnKeyDown", function(self, key)
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
        return
    end
    
    local targetButton = self.targetButton
    if not targetButton then
        self:ClearFocus()
        self:Hide()
        return
    end
    
    if key == "ESCAPE" then
        targetButton.isListening = false
        targetButton:SetText(targetButton.oldBindingText or L["KEYBIND_NOT_BOUND"] or "Not Bound")
        if self.onBindCallback then
            self.onBindCallback(nil)
        end
        self:ClearFocus()
        self:Hide()
        return
    end
    
    local prefix = ""
    if IsAltKeyDown() then prefix = prefix .. "ALT-" end
    if IsControlKeyDown() then prefix = prefix .. "CTRL-" end
    if IsShiftKeyDown() then prefix = prefix .. "SHIFT-" end
    
    local fullKey = prefix .. key
    targetButton.isListening = false
    targetButton:SetText(fullKey)
    if self.onBindCallback then
        self.onBindCallback(fullKey)
    end
    
    self:ClearFocus()
    self:Hide()
end)

bindingEditBox:SetScript("OnEditFocusLost", function(self)
    local targetButton = self.targetButton
    if targetButton and targetButton.isListening then
        targetButton.isListening = false
        targetButton:SetText(targetButton.oldBindingText or L["KEYBIND_NOT_BOUND"] or "Not Bound")
    end
    self:Hide()
end)

local function ApplyAssignmentBackdrop(frame)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,  -- Remove border
        tile = true, tileSize = 16, edgeSize = 0,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(0.15, 0.08, 0.04, 0.1)  -- Dark brown overlay (10% opacity)
    frame:SetBackdropBorderColor(0, 0, 0, 0)  -- Transparent border
    
    -- Add the assignments.tga background texture with manual pixel size control
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Backgrounds\\assignments.tga")
    -- Manual size in pixels - adjust these values as needed
    bg:SetSize(399, 673.075)  -- WIDTH, HEIGHT in pixels
    -- Position offset in pixels - moved 5px right and 5px up
    bg:SetPoint("CENTER", frame, "CENTER", 5, 5)  -- X offset (right), Y offset (up)
    bg:SetTexCoord(0, 1, 0, 1)
    bg:SetAlpha(0.95)
    frame.assignmentBgTexture = bg
end

local function GetNodes()
    OxedHub.db.profile.oxedRingNodes = OxedHub.db.profile.oxedRingNodes or {}
    return OxedHub.db.profile.oxedRingNodes
end

local function GetRingStyle()
    return OxedHub.db.profile.oxedRingStyle or "ring"
end

local function ShouldSkipDeleteConfirmation()
    if OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.settings then
        return OxedHub.db.profile.settings.skipDeleteConfirmation == true
    end
    return false
end

StaticPopupDialogs["OXEDHUB_CLEAR_RING"] = {
    text = "Are you sure you want to clear all nodes on the ring?",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnAccept = function()
        if OxedRingEditor and OxedRingEditor.ClearAllRingNodes then
            OxedRingEditor:ClearAllRingNodes()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function GetToyAssignmentMode(slot)
    if slot and slot.type == "toy" and slot.assignmentMode == "direct" then
        return "direct"
    end
    return "mix"
end

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

local function GetCustomReaction(emoteId)
    if not emoteId or emoteId == "None" then return {} end
    if not OxedHub.db.profile.customReactions then
        OxedHub.db.profile.customReactions = {}
    end
    
    -- Initialize entry if it doesn't exist
    if not OxedHub.db.profile.customReactions[emoteId] then
        OxedHub.db.profile.customReactions[emoteId] = {}
    end
    
    local reaction = OxedHub.db.profile.customReactions[emoteId]
    
    -- Auto-assign matching emote for built-in emojis if not already set
    if not reaction.emote then
        -- Map lowercase emoji IDs to uppercase emote tokens
        local defaultEmoteMap = {
            ["angry"] = "ANGRY",
            ["kiss"] = "KISS",
            ["laugh"] = "LAUGH",
            ["cry"] = "CRY",
            ["cheer"] = "CHEER",
            ["sleep"] = "SLEEP",
            ["dance"] = "DANCE",
            ["love"] = "LOVE",
            ["sick"] = "SICK",
            ["taunt"] = "TAUNT",
            ["fear"] = "COWER",
            ["money"] = "MAKEITRAIN",
            ["cool"] = "FLEX",
            ["sad"] = "MOURN",
            ["thinking"] = "THINK",
            ["smirk"] = "SMIRK"
        }
        
        if defaultEmoteMap[emoteId] then
            reaction.emote = defaultEmoteMap[emoteId]
            print("OxedHub: Auto-assigned /" .. defaultEmoteMap[emoteId]:lower() .. " to " .. emoteId)
        end
    end
    
    return reaction
end

local function GetNativeSoundOptions()
    local opts = {{label = "None", value = nil}}
    for id, sound in pairs(OxedHub.db.profile.customSounds or {}) do
        table.insert(opts, {label = sound.name or id, value = id})
    end
    return opts
end

local function GetNativeAnimationOptions()
    local opts = {{label = "None", value = nil}}
    for id, anim in pairs(OxedHub.db.profile.animations or {}) do
        table.insert(opts, {label = anim.name or id, value = id})
    end
    return opts
end

local function GetNativeChatOptions()
    local opts = {{label = "None", value = nil}}
    for id, chat in pairs(OxedHub.db.profile.chatTemplates or {}) do
        table.insert(opts, {label = chat.name or id, value = id})
    end
    return opts
end

local function GetNativeEmoteOptions()
    local opts = {{label = "None", value = nil}}
    local added = {}
    local predefined = {"APPLAUD", "BEG", "BOW", "CHEER", "CHICKEN", "CRY", "DANCE", "FLEX", "FLIRT", "GASP", "KISS", "LAUGH", "LEAN", "POINT", "ROAR", "RUDE", "SALUTE", "SHY", "SIGH", "SLEEP", "TAUNT", "WAVE"}
    for _, cmd in ipairs(predefined) do
        -- Show clean label without slash in dropdown button
        local displayLabel = cmd:sub(1,1) .. cmd:sub(2):lower()  -- "APPLAUD" -> "Applaud"
        table.insert(opts, {label = displayLabel, value = cmd})
        added[cmd] = true
    end
    for i = 1, 500 do
        local token = _G["EMOTE" .. i .. "_TOKEN"]
        local cmd = _G["EMOTE" .. i .. "_CMD1"]
        if token and cmd and not added[token] then
            table.insert(opts, {label = cmd, value = token})
            added[token] = true
        end
    end
    return opts
end

local function StyleButton(btn, style, size, isPreview)
    local innerSize = style == "ring" and (size - 2) or (size - 4)
    btn.icon:SetSize(innerSize, innerSize)
    if btn.splitIcon then
        btn.splitIcon:SetSize(innerSize, innerSize)
        if btn.splitIcon.leftTexture then btn.splitIcon.leftTexture:SetSize(innerSize/2, innerSize) end
        if btn.splitIcon.rightTexture then btn.splitIcon.rightTexture:SetSize(innerSize/2, innerSize) end
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
            
            btn.ringFill = btn:CreateTexture(nil, "BORDER")
            btn.ringFill:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.ringFill:SetTexture("Interface\\Buttons\\WHITE8X8")
            btn.ringFill:SetVertexColor(0, 0, 0, 0.6)

            btn.ringFillMask = btn:CreateMaskTexture()
            btn.ringFillMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringFillMask:SetAllPoints(btn.ringFill)
            btn.ringFill:AddMaskTexture(btn.ringFillMask)
        end

        if not btn.ringMask then
            btn.ringMask = btn:CreateMaskTexture()
            btn.ringMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            btn.ringMask:SetAllPoints(btn.icon)
        end
        btn.icon:AddMaskTexture(btn.ringMask)

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        local isSelected = isPreview and selectedNodeIndex == btn.nodeIndex
        if isSelected then
            btn.ringBg:SetVertexColor(1, 0.82, 0, 1)
        else
            btn.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
        end
    else
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        btn:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        
        local isSelected = isPreview and selectedNodeIndex == btn.nodeIndex
        if isSelected then
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end

        if btn.ringBg then btn.ringBg:Hide() end
        if btn.ringFill then btn.ringFill:Hide() end
        if btn.ringMask then 
            btn.icon:RemoveMaskTexture(btn.ringMask) 
        end
    end
end

local function RefreshPreview()
    local nodes = GetNodes()
    local numNodes = #nodes
    local cx, cy = 0, 0
    local radius = (OxedHub.db.profile.oxedRingRadius or 100)
    local style = GetRingStyle()

    -- Dynamically resize preview container for large rings
    if OxedRingEditor.previewContainer then
        local previewSize = math.max(320, (radius + 60) * 2)
        OxedRingEditor.previewContainer:SetSize(previewSize, previewSize)
    end

    -- Hide old nodes
    for _, btn in ipairs(previewNodes) do
        btn:Hide()
    end
    
    if numNodes == 0 then return end
    
    local angleStep = (2 * math_pi) / numNodes
    local startAngle = math_pi / 2
    
    for i, data in ipairs(nodes) do
        local btn = previewNodes[i]
        if not btn then
            btn = CreateFrame("Button", nil, OxedRingEditor.previewContainer, "BackdropTemplate")
            
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 4, -4)
            icon:SetPoint("BOTTOMRIGHT", -4, 4)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            btn.icon = icon
            
            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetWidth(60)
            label:SetJustifyH("CENTER")
            btn.label = label
            
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    local nodes = GetNodes()
                    local idx = self.nodeIndex
                    if idx and nodes[idx] then
                        local removed = table.remove(nodes, idx)
                        if removed then
                            OxedHub.db.profile.oxedRingBackupNodes = OxedHub.db.profile.oxedRingBackupNodes or {}
                            table.insert(OxedHub.db.profile.oxedRingBackupNodes, removed)
                        end
                        
                        if selectedNodeIndex == idx then
                            selectedNodeIndex = nil
                        elseif selectedNodeIndex and selectedNodeIndex > idx then
                            selectedNodeIndex = selectedNodeIndex - 1
                        end
                        
                        OxedRingEditor.selectedEmoteId = nil
                        RefreshPreview()
                        OxedRingEditor:RefreshAssignmentPanel()
                    end
                else
                    selectedNodeIndex = self.nodeIndex
                    OxedRingEditor.selectedEmoteId = nil
                    OxedRingEditor:RefreshAssignmentPanel()
                    RefreshPreview() -- Update borders/styles
                end
            end)

            -- Enable dragging from this preview node to swap slots
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                local nodes = GetNodes()
                local slotData = nodes[self.nodeIndex]
                if not slotData or not slotData.type then return end

                if not OxedRingEditor.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetFrameStrata("TOOLTIP")
                    f:SetSize(32, 32)
                    f.tex = f:CreateTexture(nil, "OVERLAY")
                    f.tex:SetAllPoints()
                    f:SetScript("OnUpdate", function(self)
                        local x, y = GetCursorPosition()
                        local s = UIParent:GetEffectiveScale()
                        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/s, y/s)
                    end)
                    OxedRingEditor.dragIcon = f
                end

                local displayIcon = self.resolvedIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
                OxedRingEditor.dragIcon.tex:SetTexture(displayIcon)
                
                if self.isMarker then
                    OxedRingEditor.dragIcon.tex:SetTexCoord(0, 1, 0, 1)
                else
                    OxedRingEditor.dragIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                OxedRingEditor.dragIcon:Show()
                OxedRingEditor.dragSourceNodeIndex = self.nodeIndex
            end)

            btn:SetScript("OnDragStop", function(self)
                if OxedRingEditor.dragIcon then OxedRingEditor.dragIcon:Hide() end

                local target = GetMouseFocus and GetMouseFocus() or nil
                if not (target and target.nodeIndex) then
                    for idx, pBtn in ipairs(previewNodes) do
                        if pBtn:IsMouseOver() then
                            target = pBtn
                            break
                        end
                    end
                end

                if target and target.nodeIndex and OxedRingEditor.dragSourceNodeIndex then
                    local sourceIdx = OxedRingEditor.dragSourceNodeIndex
                    local targetIdx = target.nodeIndex
                    if sourceIdx ~= targetIdx then
                        local nodes = GetNodes()
                        -- Swap the two nodes' data in the profiles!
                        local temp = nodes[sourceIdx]
                        nodes[sourceIdx] = nodes[targetIdx]
                        nodes[targetIdx] = temp

                        -- Keep selectedNodeIndex updated to follow the dragged node
                        if selectedNodeIndex == sourceIdx then
                            selectedNodeIndex = targetIdx
                        elseif selectedNodeIndex == targetIdx then
                            selectedNodeIndex = sourceIdx
                        end

                        C_Timer.After(0, function()
                            RefreshPreview()
                            OxedRingEditor:RefreshAssignmentPanel()
                        end)
                    end
                end
                OxedRingEditor.dragSourceNodeIndex = nil
            end)
            
            previewNodes[i] = btn
        end
        
        btn.nodeIndex = i
        
        -- Resolve icon dynamically
        local displayIcon = data.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        if data.type == "toy" then
            if data.assignmentMode == "direct" then
                local _, toyIcon = GetDirectToyDisplay(data.id)
                displayIcon = toyIcon or displayIcon
            else
                if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                    displayIcon = OxedHub.Toys:GetMixSlotIcons(data.id) or displayIcon
                end
            end
        elseif data.type == "emote" then
            local mapping = OxedHub.db.profile.customReactions and OxedHub.db.profile.customReactions[data.id]
            local customIcon = mapping and mapping.icon
            displayIcon = data.icon or customIcon or "Interface\\Icons\\Spell_Holy_AshesToAshes"
        elseif data.type == "trigger" then
            local trg = OxedHub.db.profile.triggers[data.id]
            if trg then
                displayIcon = (OxedHub.Triggers and OxedHub.Triggers.GetTriggerDisplayIcon and OxedHub.Triggers:GetTriggerDisplayIcon(trg))
                    or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
        elseif data.type == "marker" then
            if data.id == 0 then
                displayIcon = "Interface\\Icons\\Spell_ChargeNegative"
            else
                displayIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. data.id
            end
        end
        
        btn.icon:SetTexture(displayIcon)
        btn.resolvedIcon = displayIcon

        if data.type == "marker" and data.id ~= 0 then
            btn.icon:SetTexCoord(0, 1, 0, 1)
            btn.isMarker = true
        else
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.isMarker = false
        end
        
        local fontPath, _, fontFlags = btn.label:GetFont()
        local fontSize = OxedHub.db.profile.oxedRingNodeTitleSize or 11
        btn.label:SetFont(OxedHub:GetFont(fontPath), fontSize, fontFlags or "OUTLINE")
        btn.label:SetText(data.label or "Node " .. i)
        if OxedHub.db.profile.oxedRingShowNodeTitles then
            btn.label:Show()
        else
            btn.label:Hide()
        end
        
        local nodeSize = data.nodeSize or OxedHub.db.profile.oxedRingGlobalNodeSize or 40
        btn:SetSize(nodeSize, nodeSize)
        StyleButton(btn, style, nodeSize, true)
        
        local angle = startAngle - (i - 1) * angleStep
        local x = cx + math_cos(angle) * radius
        local y = cy + math_sin(angle) * radius
        
        if data.nodePositionX then
            x = x + data.nodePositionX
        end
        if data.nodePositionY then
            y = y + data.nodePositionY
        end
        
        btn:SetPoint("CENTER", OxedRingEditor.previewContainer, "CENTER", x, y)
        btn:Show()

        -- â”€â”€ Tooltip for condition requirements â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(data.label or ("Node " .. i))
            if data.requiresParty then
                GameTooltip:AddLine("|cffff9900Requires: Party/Raid|r", 1, 1, 1)
            end
            if data.requiresTarget then
                GameTooltip:AddLine("|cffff9900Requires: Target|r", 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    if OxedHub.OxedRing then
        OxedHub.OxedRing:RebuildSlices()
    end
end

function OxedRingEditor:ClearAllRingNodes()
    local nodes = GetNodes()
    for idx, slot in ipairs(nodes) do
        slot.type = nil
        slot.id = nil
        slot.assignmentMode = nil
        slot.label = "Node " .. idx
        slot.icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        slot.requiresParty = nil
        slot.requiresTarget = nil
    end
    OxedHub.db.profile.oxedRingBackupNodes = nil
    selectedNodeIndex = nil
    RefreshPreview()
    self:RefreshAssignmentPanel()
end

function OxedRingEditor:GetSelectedEmote()
    if OxedRingEditor.selectedEmoteId then
        return OxedRingEditor.selectedEmoteId
    end
    
    if not selectedNodeIndex then return nil end
    local nodes = GetNodes()
    local node = nodes[selectedNodeIndex]
    if not node then return nil end
    
    if not node.id then
        node.id = "OxedRingNode_" .. tostring(selectedNodeIndex) .. "_" .. tostring(math.random(1000, 9999))
    end
    
    if rightPanel.selectedType == "emote" then
        node.type = "emote"
        node.assignmentMode = nil
        return node.id
    end
    
    if node.type == "emote" then
        return node.id
    end
    return nil
end



local function MakeButtonDraggable(btn, item)
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        if not OxedRingEditor.dragIcon then
            local f = CreateFrame("Frame", nil, UIParent)
            f:SetFrameStrata("TOOLTIP")
            f:SetSize(32, 32)
            f.tex = f:CreateTexture(nil, "OVERLAY")
            f.tex:SetAllPoints()
            f:SetScript("OnUpdate", function(self)
                local x, y = GetCursorPosition()
                local s = UIParent:GetEffectiveScale()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/s, y/s)
            end)
            OxedRingEditor.dragIcon = f
        end
        local icon = item.icon1 or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
        OxedRingEditor.dragIcon.tex:SetTexture(icon)
        
        if item.type == "marker" and item.id ~= 0 then
            OxedRingEditor.dragIcon.tex:SetTexCoord(0, 1, 0, 1)
        else
            OxedRingEditor.dragIcon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        
        OxedRingEditor.dragIcon:Show()
        OxedRingEditor.dragPayload = item
    end)
    btn:SetScript("OnDragStop", function(self)
        if OxedRingEditor.dragIcon then OxedRingEditor.dragIcon:Hide() end
        local target = GetMouseFocus and GetMouseFocus() or nil
        if not (target and target.nodeIndex) then
            for i, pBtn in ipairs(previewNodes) do
                if pBtn:IsMouseOver() then
                    target = pBtn
                    break
                end
            end
        end

        if target and target.nodeIndex then
            local nodes = GetNodes()
            local slot = nodes[target.nodeIndex]
            if slot and OxedRingEditor.dragPayload then
                slot.type = OxedRingEditor.dragPayload.type
                slot.id = OxedRingEditor.dragPayload.id
                slot.assignmentMode = OxedRingEditor.dragPayload.assignmentMode
                slot.label = OxedRingEditor.dragPayload.name
                slot.icon = OxedRingEditor.dragPayload.icon1 or OxedRingEditor.dragPayload.icon
                -- Propagate condition flags for marker types
                if OxedRingEditor.dragPayload.type == "marker" then
                    slot.requiresParty = true
                    slot.requiresTarget = nil
                elseif OxedRingEditor.dragPayload.type == "targetmarker" then
                    slot.requiresTarget = true
                    slot.requiresParty = nil
                else
                    slot.requiresParty = nil
                    slot.requiresTarget = nil
                end
                
                local targetNodeIndex = target.nodeIndex
                C_Timer.After(0, function()
                    selectedNodeIndex = targetNodeIndex
                    RefreshPreview()
                    OxedRingEditor:RefreshAssignmentPanel()
                end)
            end
        end
        OxedRingEditor.dragPayload = nil
    end)
end

-- Build the collected-mount list once and cache it. Scanning the whole mount
-- journal (GetMountInfoByID for every mount) is expensive, so we only do it on
-- first use or when the player explicitly refreshes via the Settings tab.
function OxedRingEditor:GetCachedMounts(forceRefresh)
    -- Delegate to the shared, SavedVariables-backed mount cache so OxedRing and
    -- ActionHub always read the same list (built once; rebuilt on Refresh).
    if OxedHub.Mounts and OxedHub.Mounts.GetMounts then
        return OxedHub.Mounts:GetMounts(forceRefresh)
    end
    return {}
end

function OxedRingEditor:RefreshPickerList()
    local dialog = rightPanel
    if not dialog then return end

    local child = self.assignmentScrollChild
    if not child then return end

    -- Recycle previously created entry buttons via a tracked list. The old
    -- code only Hid them (never removed), so children piled up every refresh;
    -- eventually {child:GetChildren()} packed so many return values onto the
    -- Lua stack that it overflowed. Track + remove instead.
    self._pickerChildren = self._pickerChildren or {}
    for i = #self._pickerChildren, 1, -1 do
        local c = self._pickerChildren[i]
        if c then c:Hide(); c:SetParent(nil) end
        self._pickerChildren[i] = nil
    end
    local pickerChildren = self._pickerChildren
    local function track(b) pickerChildren[#pickerChildren + 1] = b; return b end

    -- Update tab highlights
    local selectedTabID = (dialog.selectedType == "toy") and 1 or (dialog.selectedType == "emote" and 2 or (dialog.selectedType == "marker" and 3 or (dialog.selectedType == "item" and 4 or 5)))
    if PanelTemplates_SetTab then
        PanelTemplates_SetTab(dialog, selectedTabID)
    end

    if dialog.sidebarButtons then
        for _, b in ipairs(dialog.sidebarButtons) do
            if b.catType == dialog.selectedType then
                b.border:SetVertexColor(1, 0.82, 0)  -- Bright gold when selected
            else
                b.border:SetVertexColor(0.6, 0.5, 0.3)  -- Dim bronze when not selected
            end
        end
    end

    local nodes = GetNodes()
    local currentSlot = selectedNodeIndex and nodes[selectedNodeIndex]
    local er = OxedHub.EmotionRing

    self.assignmentScrollChild:Hide()
    if rightPanel.settingsScrollChild then rightPanel.settingsScrollChild:Hide() end
    self.assignmentScroll:SetScrollChild(self.assignmentScrollChild)
    self.assignmentScroll:Hide()
    dialog.editor:Hide()
    if self.mountCountLabel then
        self.mountCountLabel:Hide()
    end
    if self.markerHeaders then
        for _, h in ipairs(self.markerHeaders) do
            h:Hide()
        end
    end
    if dialog.selectedType ~= "toy" and dialog.selectedType ~= "mount" then
        self.toySearchBox:Hide()
    end



    if dialog.selectedType == "toy" then
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 36)
        self.assignmentScroll:Show()
        self.assignmentScrollChild:Show()
        self.assignmentInfo:SetText(L["AH_PICK_TOY"] or "Pick a Toy for this slot")
        self.toySearchBox:Show()
        local desiredSearch = dialog.toySearchText or ""
        if self.toySearchBox:GetText() ~= desiredSearch then
            self.toySearchBox.isSyncingText = true
            self.toySearchBox:SetText(desiredSearch)
            self.toySearchBox.isSyncingText = false
        end

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            -- Avoid c:SetParent(nil) while scripts might still be executing
        end

        local items = {}
        if OxedHub.Toys and OxedHub.Toys.CacheToyData and (not OxedHub.Toys.toyDataInitialized or not OxedHub.Toys.toyIDs or #OxedHub.Toys.toyIDs == 0) then
            OxedHub.Toys:CacheToyData(true)
        end

        local toyIDs = OxedHub.Toys and OxedHub.Toys.toyIDs or {}
        local toyCache = OxedHub.Toys and OxedHub.Toys.toyCache or {}
        local searchText = (dialog.toySearchText or ""):lower()
        local totalToys = 0
        for _, toyID in ipairs(toyIDs) do
            if PlayerHasToy(toyID) then
                local cached = toyCache[toyID] or {}
                local toyName, toyIcon = GetDirectToyDisplay(toyID)
                local displayName = cached.name or toyName or ("Toy " .. tostring(toyID))
                if displayName then
                    totalToys = totalToys + 1
                    if searchText == "" or displayName:lower():find(searchText, 1, true) then
                        table.insert(items, {
                            type = "toy",
                            assignmentMode = "direct",
                            id = toyID,
                            name = displayName,
                            icon1 = cached.icon or toyIcon,
                        })
                    end
                end
            end
        end

        if self.mountCountLabel then
            local labelText = "Toys: " .. totalToys
            if searchText ~= "" then
                labelText = "Found: " .. #items .. " / " .. totalToys
            end
            self.mountCountLabel:SetText(labelText)
            self.mountCountLabel:Show()
        end

        table.sort(items, function(a, b) return a.name < b.name end)

        local btnSize = 42  -- 5% larger than 40
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            local q = "Interface\\Icons\\INV_Misc_QuestionMark"
            if item.icon2 and item.icon1 ~= q and item.icon2 ~= q and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                local splitIcon = OxedHub.Toys:CreateSplitIcon(btn, btnSize - 6, item.icon1, item.icon2)
                splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            else
                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon1 or q)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetToyByItemID then
                    GameTooltip:SetToyByItemID(item.id)
                else
                    GameTooltip:SetItemByID(item.id)
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                if currentSlot then
                    currentSlot.type = "toy"
                    currentSlot.id = item.id
                    currentSlot.assignmentMode = item.assignmentMode
                    currentSlot.label = item.name
                    currentSlot.icon = item.icon1
                    -- Clear marker condition flags
                    currentSlot.requiresParty = nil
                    currentSlot.requiresTarget = nil
                end
                RefreshPreview()
                OxedRingEditor:RefreshAssignmentPanel()
            end)

            MakeButtonDraggable(btn, item)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 16)
        child:SetWidth(cols * (btnSize + spacing))

    elseif dialog.selectedType == "emote" then
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 240)
        self.assignmentScroll:Show()
        self.assignmentScrollChild:Show()
        
        dialog.editor:ClearAllPoints()
        dialog.editor:SetPoint("TOPLEFT", self.assignmentScroll, "BOTTOMLEFT", -16, 0)
        dialog.editor:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 36)
        dialog.editor:Show()
        dialog.reactionTabFrame:Show()
        
        self.assignmentInfo:SetText(L["AH_PICK_EMOJI"] or "Pick an Emoji, then configure it below")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
        end

        local items = {}
        for _, r in ipairs(OxedHub.CONFIG.REACTIONS or {}) do table.insert(items, r) end
        for _, r in pairs(OxedHub.db.profile.customReactions or {}) do 
            if r.icon and r.name then
                table.insert(items, r) 
            end
        end
        
        local btnSize = 44
        local spacing = 6
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing + 14) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            
            local isSelected = false
            if OxedRingEditor.selectedEmoteId then
                isSelected = (OxedRingEditor.selectedEmoteId == item.id)
            else
                isSelected = (currentSlot and currentSlot.type == "emote" and currentSlot.id == item.id)
            end

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(10)

            if isSelected then
                btn:SetBackdropBorderColor(1, 0.82, 0, 1)
                btn:SetBackdropColor(0.25, 0.2, 0.05, 0.9)
                if not btn.selectedOverlay then
                    btn.selectedOverlay = btn:CreateTexture(nil, "OVERLAY")
                    btn.selectedOverlay:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                    btn.selectedOverlay:SetBlendMode("ADD")
                end
                btn.selectedOverlay:ClearAllPoints()
                btn.selectedOverlay:SetPoint("TOPLEFT", btn, "TOPLEFT", -20, 20)
                btn.selectedOverlay:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 20, -20)
                btn.selectedOverlay:Show()
                iconTex:SetAlpha(1.0)
                label:SetTextColor(1, 0.82, 0, 1)
            else
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
                if btn.selectedOverlay then
                    btn.selectedOverlay:Hide()
                end
                iconTex:SetAlpha(0.5)
                label:SetTextColor(0.7, 0.65, 0.6, 0.8)
            end

            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if type(item.id) == "string" and string.match(item.id, "^custom_") then
                        -- Loop through and delete matching keys (cleans up older table.insert arrays too)
                        for k, v in pairs(OxedHub.db.profile.customReactions) do
                            if type(v) == "table" and v.id == item.id then
                                OxedHub.db.profile.customReactions[k] = nil
                            end
                        end
                        if OxedRingEditor.selectedEmoteId == item.id then
                            OxedRingEditor.selectedEmoteId = nil
                        end
                        OxedRingEditor:RefreshPickerList()
                    end
                    return
                end

                OxedRingEditor.selectedEmoteId = item.id
                if currentSlot then
                    currentSlot.type = "emote"
                    currentSlot.id = item.id
                    currentSlot.assignmentMode = nil
                    currentSlot.label = item.name
                    currentSlot.icon = item.icon
                    -- Clear marker condition flags
                    currentSlot.requiresParty = nil
                    currentSlot.requiresTarget = nil
                end
                RefreshPreview()
                OxedRingEditor:RefreshAssignmentPanel()
                OxedRingEditor:RefreshPickerList()
            end)

            -- Add tooltip hint for right-click delete
            if type(item.id) == "string" and string.match(item.id, "^custom_") then
                btn:SetScript("OnEnter", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(1, 0.82, 0, 0.8) 
                        iconTex:SetAlpha(1.0)
                    end 
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(item.name)
                    GameTooltip:AddLine(L["RIGHT_CLICK_TO_DELETE"] or "Right-Click to delete", 1, 0.2, 0.2)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) 
                        iconTex:SetAlpha(0.5)
                    end 
                    GameTooltip:Hide()
                end)
            else
                btn:SetScript("OnEnter", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(1, 0.82, 0, 0.8) 
                        iconTex:SetAlpha(1.0)
                    end 
                end)
                btn:SetScript("OnLeave", function(self) 
                    if not isSelected then 
                        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) 
                        iconTex:SetAlpha(0.5)
                    end 
                end)
            end

            MakeButtonDraggable(btn, { type = "emote", id = item.id, name = item.name, icon = item.icon })

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        -- Add New Button
        local addBtn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
        addBtn:SetSize(btnSize, btnSize)
        addBtn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing + 14) - 4)
        addBtn:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
        })
        addBtn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
        addBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.8)

        local addIcon = addBtn:CreateTexture(nil, "ARTWORK")
        addIcon:SetSize(24, 24)
        addIcon:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        addIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\add")
        addIcon:SetVertexColor(0.3, 0.8, 0.3)

        local addLabel = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        addLabel:SetPoint("TOP", addBtn, "BOTTOM", 0, -2)
        addLabel:SetText(L["AH_ADD_NEW"] or "Add New")
        addLabel:SetWidth(btnSize + 4)
        addLabel:SetJustifyH("CENTER")
        addLabel:SetHeight(10)
        addLabel:SetTextColor(0.3, 0.8, 0.3)

        addBtn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(0.5, 1, 0.5, 1) end)
        addBtn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.8) end)

        addBtn:SetScript("OnClick", function()
            StaticPopupDialogs["OXEDHUB_NEW_EMOJI"] = {
                text = L["NEW_REACTION_TITLE"] or "Enter a name for the new custom reaction:",
                button1 = ACCEPT,
                button2 = CANCEL,
                hasEditBox = true,
                OnAccept = function(self)
                    local text = self.EditBox and self.EditBox:GetText() or _G[self:GetName().."EditBox"]:GetText()
                    if text and text ~= "" and OxedHub.IconPicker then
                        OxedHub.IconPicker:Open({
                            title = string.format(L["PICK_ICON_FOR"] or "Pick an Icon for %s", text),
                            customRingIconsOnly = true,
                            onSelect = function(value, texture)
                                OxedHub.db.profile.customReactions = OxedHub.db.profile.customReactions or {}
                                local id = "custom_" .. time()
                                OxedHub.db.profile.customReactions[id] = {
                                    id = id,
                                    name = text,
                                    icon = texture,
                                    command = ""
                                }
                                OxedRingEditor:RefreshPickerList()
                            end
                        })
                    end
                end,
                EditBoxOnEnterPressed = function(self)
                    local parent = self:GetParent()
                    StaticPopup_OnClick(parent, 1)
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("OXEDHUB_NEW_EMOJI")
        end)

        local totalItems = #items + 1
        local rows = math.max(math.ceil(totalItems / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 16) + 16)
        child:SetWidth(cols * (btnSize + spacing))

        if dialog.selectedType == "emote" then
            local currentEmote = OxedRingEditor.selectedEmoteId
            if not currentEmote then
                currentEmote = (currentSlot and currentSlot.type == "emote") and currentSlot.id or "None"
            end
            local hasEmote = (currentEmote and currentEmote ~= "None")
            local mapping = GetCustomReaction(currentEmote)

            local function GetLabel(opts, val)
                if not val then return "None" end
                for _, o in ipairs(opts) do if o.value == val then return o.label end end
                return tostring(val)
            end

            dialog.soundPicker.button:SetText(GetLabel(GetNativeSoundOptions(), mapping.sound))
            dialog.animationPicker.button:SetText(GetLabel(GetNativeAnimationOptions(), mapping.animation))
            dialog.animCheck:SetChecked(mapping.animationUseCustomPosition or false)
            
            dialog.soundPicker.button:SetEnabled(hasEmote)
            dialog.animationPicker.button:SetEnabled(hasEmote)
            dialog.animCheck:SetEnabled(hasEmote)
            if dialog.setPosBtn then
                dialog.setPosBtn:SetEnabled(hasEmote and (mapping.animationUseCustomPosition or false))
            end
            
            if dialog.emotePicker then 
                dialog.emotePicker.label:Show() 
                dialog.emotePicker.button:Show() 
                dialog.emotePicker.button:SetEnabled(hasEmote)
            end
            if dialog.toyMacroPicker then 
                dialog.toyMacroPicker.label:Hide() 
                dialog.toyMacroPicker.button:Hide() 
                dialog.toyMacroPicker.button:SetEnabled(hasEmote)
            end
            
            dialog.emotePicker.button:SetText(GetLabel(GetNativeEmoteOptions(), mapping.emote))
        end

    elseif dialog.selectedType == "marker" then
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 36)
        self.assignmentScroll:Show()
        self.assignmentScrollChild:Show()
        self.assignmentInfo:SetText(L["RING_PICK_RAID_TARGET"] or "Pick a Raid Target, World Marker, or Ping")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
        end

        local categories = {
            {
                name = "Marks",
                items = {
                    { type = "targetmarker", id = 1, name = "Target: Star", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "targetmarker", id = 2, name = "Target: Circle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "targetmarker", id = 3, name = "Target: Diamond", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "targetmarker", id = 4, name = "Target: Triangle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "targetmarker", id = 5, name = "Target: Moon", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "targetmarker", id = 6, name = "Target: Square", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "targetmarker", id = 7, name = "Target: Cross", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "targetmarker", id = 8, name = "Target: Skull", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "targetmarker", id = 0, name = "Clear Target", icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = "Flares",
                items = {
                    { type = "marker", id = 1, name = "Flare: Blue", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "marker", id = 2, name = "Flare: Green", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "marker", id = 3, name = "Flare: Purple", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "marker", id = 4, name = "Flare: Red", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "marker", id = 5, name = "Flare: Yellow", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "marker", id = 6, name = "Flare: Orange", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "marker", id = 7, name = "Flare: Silver", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "marker", id = 8, name = "Flare: White", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "marker", id = 0, name = "Clear Flares", icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = "Pings",
                items = {
                    { type = "ping", id = "", name = "Ping", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-main-icon.png" },
                    { type = "ping", id = "attack", name = "Ping: Attack", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Attack-Icon.png" },
                    { type = "ping", id = "assist", name = "Ping: Assist", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Assist-Icon.png" },
                    { type = "ping", id = "onmyway", name = "Ping: On My Way", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-OnMyWay-Icon.png" },
                    { type = "ping", id = "warning", name = "Ping: Warning", icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Warning-Icon.png" },
                }
            }
        }

        if not self.markerHeaders then
            self.markerHeaders = {}
            for _, cat in ipairs(categories) do
                local header = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                header:SetText(cat.name)
                header:SetTextColor(1, 0.82, 0)
                table.insert(self.markerHeaders, header)
            end
        end
        for _, h in ipairs(self.markerHeaders) do
            h:Hide()
        end

        local btnSize = 44
        local spacing = 6
        local cols = 4
        local currentY = 8

        for catIdx, cat in ipairs(categories) do
            local header = self.markerHeaders[catIdx]
            header:SetPoint("TOPLEFT", child, "TOPLEFT", 12, -currentY)
            header:Show()

            currentY = currentY + 18

            local x, y = 0, 0
            for i, item in ipairs(cat.items) do
                local btn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
                btn:SetSize(btnSize, btnSize)
                btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -currentY - y * (btnSize + spacing + 14))
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 8,
                })
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon)
                
                -- Keep full texture for markers, or crop if Clear All
                if item.id == 0 then
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
                label:SetText(item.name)
                label:SetWidth(btnSize + 4)
                label:SetJustifyH("CENTER")
                label:SetHeight(10)
                label:SetTextColor(0.90, 0.85, 0.80, 1)

                btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
                btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

                btn:SetScript("OnClick", function()
                    if currentSlot then
                        currentSlot.type = item.type
                        currentSlot.id = item.id
                        currentSlot.assignmentMode = nil
                        currentSlot.label = item.name
                        currentSlot.icon = item.icon
                        -- Auto-set condition flags for marker types
                        if item.type == "marker" then
                            currentSlot.requiresParty = true
                            currentSlot.requiresTarget = nil
                        elseif item.type == "targetmarker" then
                            currentSlot.requiresTarget = true
                            currentSlot.requiresParty = nil
                        else
                            currentSlot.requiresParty = nil
                            currentSlot.requiresTarget = nil
                        end
                    end
                    RefreshPreview()
                    OxedRingEditor:RefreshAssignmentPanel()
                end)

                MakeButtonDraggable(btn, item)

                x = x + 1
                if x >= cols then
                    x = 0
                    y = y + 1
                end
            end

            local numRows = math.max(math.ceil(#cat.items / cols), 1)
            currentY = currentY + numRows * (btnSize + spacing + 14) + 12
        end

        child:SetHeight(currentY + 10)
        child:SetWidth(cols * (btnSize + spacing))

    elseif dialog.selectedType == "item" then
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 36)
        self.assignmentScroll:Show()
        self.assignmentScrollChild:Show()
        self.assignmentInfo:SetText(L["RING_PICK_BAG_ITEM"] or "Pick a Potion, Flask, or Food from your bags")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
        end

        -- Scan player bags for consumable items (Potions, Flasks, Food)
        local items = {}
        local seenIDs = {}
        for bag = 0, 4 do
            local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container and C_Container.GetContainerItemInfo(bag, slot) or nil
                local itemID = info and info.itemID or nil
                if itemID and not seenIDs[itemID] then
                    seenIDs[itemID] = true
                    local itemName, _, _, _, _, itemType, itemSubType, _, _, itemIcon = GetItemInfo(itemID)
                    if itemType == "Consumable" then
                        local cat = itemSubType or "Other"
                        local count = GetItemCount(itemID) or 0
                        table.insert(items, {
                            type = "item",
                            id = itemID,
                            name = itemName or ("Item #" .. itemID),
                            icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                            category = cat,
                            count = count,
                        })
                    end
                end
            end
        end

        -- Sort by category then name
        table.sort(items, function(a, b)
            if a.category ~= b.category then
                local order = { Potion = 1, Flask = 2, Food = 3 }
                local orderA = order[a.category] or 9
                local orderB = order[b.category] or 9
                if orderA ~= orderB then
                    return orderA < orderB
                else
                    return a.category < b.category
                end
            end
            return (a.name or "") < (b.name or "")
        end)

        if #items == 0 then
            local noItems = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            noItems:SetPoint("TOPLEFT", child, "TOPLEFT", 8, -8)
            noItems:SetText("|cffff9900No consumable items found in your bags.|r")
            noItems:SetWidth(240)
            noItems:SetJustifyH("LEFT")
            child:SetHeight(40)
            child:SetWidth(240)
        else
            local btnSize = 42
            local spacing = 2
            local cols = 5
            local x, y = 0, 0

            for i, item in ipairs(items) do

                local itemName = item.name
                local itemIcon = item.icon

                local btn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
                btn:SetSize(btnSize, btnSize)
                btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -(y * (btnSize + spacing)) - 4)
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 8,
                })
                btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
                btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(itemIcon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                if item.count and item.count > 1 then
                    local countLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    countLabel:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
                    countLabel:SetText(item.count)
                    countLabel:SetTextColor(1, 1, 1)
                end

                btn:SetScript("OnEnter", function(self)
                    self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(item.id)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function(self)
                    self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                    GameTooltip:Hide()
                end)

                btn:SetScript("OnClick", function()
                    if currentSlot then
                        currentSlot.type = "item"
                        currentSlot.id = item.id
                        currentSlot.assignmentMode = "direct"
                        currentSlot.label = itemName
                        currentSlot.icon = itemIcon
                        currentSlot.requiresParty = nil
                        currentSlot.requiresTarget = nil
                    end
                    RefreshPreview()
                    OxedRingEditor:RefreshAssignmentPanel()
                end)

                MakeButtonDraggable(btn, { type = "item", id = item.id, name = itemName, icon = itemIcon, assignmentMode = "direct" })

                x = x + 1
                if x >= cols then x = 0 y = y + 1 end
            end

            local rows = math.max(math.ceil((y + 1) / 1), 1)
            child:SetHeight(rows * (btnSize + spacing) + 16)
            child:SetWidth(cols * (btnSize + spacing))
        end

    elseif dialog.selectedType == "mount" then
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 36)
        self.assignmentScroll:Show()
        self.assignmentScrollChild:Show()
        self.assignmentInfo:SetText(L["AH_PICK_MOUNT"] or "Pick a Mount for this slot")

        self.toySearchBox:Show()
        local desiredSearch = dialog.toySearchText or ""
        if self.toySearchBox:GetText() ~= desiredSearch then
            self.toySearchBox.isSyncingText = true
            self.toySearchBox:SetText(desiredSearch)
            self.toySearchBox.isSyncingText = false
        end

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
        end

        -- Use the cached mount list (built once; refresh via Settings tab)
        local items = self:GetCachedMounts()
        local totalMounts = #items
        local filterText = (dialog.toySearchText or ""):lower()
        if filterText ~= "" then
            local filtered = {}
            for _, item in ipairs(items) do
                if item.name:lower():find(filterText, 1, true) then
                    table.insert(filtered, item)
                end
            end
            items = filtered
        end

        if self.mountCountLabel then
            local labelText = "Mounts: " .. totalMounts
            if filterText ~= "" then
                labelText = "Found: " .. #items .. " / " .. totalMounts
            end
            self.mountCountLabel:SetText(labelText)
            self.mountCountLabel:Show()
        end

        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = track(CreateFrame("Button", nil, child, "BackdropTemplate"))
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.SetMountBySpellID and item.spellID then
                    GameTooltip:SetMountBySpellID(item.spellID)
                else
                    GameTooltip:SetText(item.name)
                end
                GameTooltip:AddLine("|cff00ff00Click to assign to this slot|r")
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                if currentSlot then
                    currentSlot.type = "mount"
                    currentSlot.id = item.id  -- mountID (SummonByID needs the mount ID, not spellID)
                    currentSlot.label = item.name
                    currentSlot.icon = item.icon
                    currentSlot.requiresParty = nil
                    currentSlot.requiresTarget = nil
                end
                RefreshPreview()
                OxedRingEditor:RefreshAssignmentPanel()
            end)

            MakeButtonDraggable(btn, item)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 16)
        child:SetWidth(cols * (btnSize + spacing))

    elseif dialog.selectedType == "settings" then
        self.assignmentScroll:SetScrollChild(rightPanel.settingsScrollChild)
        self.assignmentScroll:ClearAllPoints()
        self.assignmentScroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -80)
        self.assignmentScroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -55, 36)
        self.assignmentScroll:Show()
        rightPanel.settingsScrollChild:Show()
        self.assignmentInfo:SetText(L["AH_CONFIGURE_SETTINGS"] or "Configure settings for this slot")
        dialog.moveNodeMode = dialog.moveNodeMode == true

        dialog.ringBindBtn:Enable()
        if dialog.ringBindResetBtn then dialog.ringBindResetBtn:Enable() end

        local gSize = OxedHub.db.profile.oxedRingGlobalNodeSize or 40
        dialog.globalSizeSlider.isResetting = true
        dialog.globalSizeSlider:SetValue(gSize)
        dialog.globalSizeSlider.isResetting = false
        dialog.globalSizeVal:SetText(tostring(gSize))
        dialog.globalSizeInput:SetText(tostring(gSize))

        local rRadius = OxedHub.db.profile.oxedRingRadius or 100
        dialog.ringRadiusSlider.isResetting = true
        dialog.ringRadiusSlider:SetValue(rRadius)
        dialog.ringRadiusSlider.isResetting = false
        dialog.ringRadiusVal:SetText(tostring(rRadius))
        dialog.ringRadiusInput:SetText(tostring(rRadius))



        local ringBindingText = OxedHub.db.profile.oxedRingBinding or L["KEYBIND_NOT_BOUND"] or "Not Bound"
        dialog.ringBindBtn:SetText(ringBindingText)
        if dialog.moveNodeBtn then
            dialog.moveNodeBtn:SetText(dialog.moveNodeMode and "Moving" or "Move")
        end
        
        if dialog.showTitlesCheck then
            dialog.showTitlesCheck:SetChecked(OxedHub.db.profile.oxedRingShowNodeTitles == true)
        end

        local tSize = OxedHub.db.profile.oxedRingNodeTitleSize or 11
        if dialog.fontSizeSlider then
            dialog.fontSizeSlider.isResetting = true
            dialog.fontSizeSlider:SetValue(tSize)
            dialog.fontSizeSlider.isResetting = false
            dialog.fontSizeVal:SetText(tostring(tSize))
            dialog.fontSizeInput:SetText(tostring(tSize))
        end

        for _, entry in ipairs(dialog.styles) do
            if entry.key == GetRingStyle() then
                dialog.styleBtn:OverrideText(entry.name)
                break
            end
        end
    end
    
    if OxedHub.UI and OxedHub.UI.ApplyGlobalTextSize then
        OxedHub.UI:ApplyGlobalTextSize()
    end
end


local function CreateDisconnectedAssignmentTabs(panel)
    panel.tabs = {}
    panel.tabsArray = {}

    local tabNames = { "Toys", "Reactions", "Markers", "Items", "Mounts", "Settings" }
    local isRetail = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
    local template = isRetail and "CharacterFrameTabTemplate" or "CharacterFrameTabButtonTemplate"

    for i, name in ipairs(tabNames) do
        local tab = CreateFrame("Button", "$parentTab" .. i, panel, template)
        tab:SetID(i)
        tab:SetText(name)
        tab:SetScript("OnClick", function()
            -- 1=toy, 2=emote, 3=marker, 4=item, 5=mount, 6=settings
            local newType = (i == 1) and "toy" or (i == 2 and "emote" or (i == 3 and "marker" or (i == 4 and "item" or (i == 5 and "mount" or "settings"))))
            if panel.selectedType ~= newType then
                panel.toySearchText = ""
                if OxedRingEditor.toySearchBox then
                    OxedRingEditor.toySearchBox.isSyncingText = true
                    OxedRingEditor.toySearchBox:SetText("")
                    OxedRingEditor.toySearchBox.isSyncingText = false
                end
            end
            panel.selectedType = newType
            OxedRingEditor:RefreshPickerList()
        end)

        if i == 1 then
            tab:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 6, 6)
        else
            tab:SetPoint("LEFT", panel.tabsArray[i - 1], "RIGHT", -16, 0)
        end

        panel.tabs[name] = tab
        table.insert(panel.tabsArray, tab)
    end

    if PanelTemplates_SetNumTabs then
        PanelTemplates_SetNumTabs(panel, #tabNames)
    end

    -- User requested to temporarily hide the tabs to see how it looks
    for _, t in ipairs(panel.tabsArray) do
        t:Hide()
    end
    if OxedHub.UI and OxedHub.UI.ApplyGlobalTextSize then
        OxedHub.UI:ApplyGlobalTextSize()
    end
end

function OxedRingEditor:CreateTab(contentArea)
    local tab = CreateFrame("Frame", nil, contentArea)
    tab:SetAllPoints(contentArea)
    tab:SetID(8)
    if OxedHub.UI and OxedHub.UI.ApplyToysBackground then
        OxedHub.UI.ApplyToysBackground(tab)
    end
    
    local insetLeft, insetRight, insetTop, insetBottom = 42, 56, 66, 54
    if OxedHub.UI and OxedHub.UI.GetThemedFrameInsets then
        insetLeft, insetRight, insetTop, insetBottom = OxedHub.UI:GetThemedFrameInsets()
    end
    
    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLeft")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -insetTop + 34)
    title:SetText("Oxed Ring")
    title:Hide()
    
    local desc = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    desc:SetText("Design your radial OPie-style ring. Click a node to assign it.")
    desc:Hide()
    
    -- Main Split
    local leftPanel = CreateFrame("Frame", nil, tab)
    leftPanel:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -insetTop)
    leftPanel:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -insetRight - 320, insetBottom)
    
    rightPanel = CreateFrame("Frame", "OxedHubOxedRingAssignmentPanel", tab, "BackdropTemplate")
    rightPanel:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -insetRight, -insetTop)
    rightPanel:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 10, 0)
    ApplyAssignmentBackdrop(rightPanel)
    
    -- Center Preview Area (size adapts to ring radius)
    self.previewContainer = CreateFrame("Frame", nil, leftPanel)
    local previewRadius = OxedHub.db.profile.oxedRingRadius or 100
    local previewSize = math.max(320, (previewRadius + 60) * 2)
    self.previewContainer:SetSize(previewSize, previewSize)
    self.previewContainer:SetPoint("CENTER", leftPanel, "CENTER", 0, 20)
    
    -- Center mark removed by user request
    
    -- Node Management (+/-)
    local controls = CreateFrame("Frame", nil, leftPanel)
    controls:SetSize(200, 40)
    controls:SetPoint("BOTTOM", leftPanel, "BOTTOM", 0, 20)
    self.controlsFrame = controls
    
    local subBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    subBtn:SetSize(30, 26)
    subBtn:SetPoint("CENTER", controls, "CENTER", -50, 0)
    subBtn:SetText("-")
    subBtn:SetScript("OnClick", function()
        local nodes = GetNodes()
        if #nodes <= 0 then return end
        local removed = table.remove(nodes)
        if removed then
            OxedHub.db.profile.oxedRingBackupNodes = OxedHub.db.profile.oxedRingBackupNodes or {}
            table.insert(OxedHub.db.profile.oxedRingBackupNodes, removed)
        end
        if selectedNodeIndex and selectedNodeIndex > #nodes then
            selectedNodeIndex = nil
        end
        RefreshPreview()
        OxedRingEditor:RefreshAssignmentPanel()
    end)

    local addBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    addBtn:SetSize(30, 26)
    addBtn:SetPoint("LEFT", subBtn, "RIGHT", 8, 0)
    addBtn:SetText("+")
    addBtn:SetScript("OnClick", function()
        local nodes = GetNodes()
        if #nodes >= 16 then return end
        
        local restored = nil
        if OxedHub.db.profile.oxedRingBackupNodes and #OxedHub.db.profile.oxedRingBackupNodes > 0 then
            restored = table.remove(OxedHub.db.profile.oxedRingBackupNodes)
        end
        
        if restored then
            if restored.label and restored.label:match("^Node %d+$") then
                restored.label = "Node " .. (#nodes + 1)
            end
            table.insert(nodes, restored)
        else
            table.insert(nodes, { label = "Node " .. (#nodes + 1), icon = "Interface\\Icons\\INV_Misc_QuestionMark" })
        end
        
        RefreshPreview()
        OxedRingEditor:RefreshAssignmentPanel()
    end)

    local clearBtn = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    clearBtn:SetSize(54, 26)
    clearBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
    clearBtn:SetText(L["BTN_CLEAR"] or "Clear")
    clearBtn:SetScript("OnClick", function()
        if ShouldSkipDeleteConfirmation() then
            OxedRingEditor:ClearAllRingNodes()
        else
            StaticPopup_Show("OXEDHUB_CLEAR_RING")
        end
    end)
    
    local countLabel = controls:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOP", controls, "BOTTOM", 0, -8)
    countLabel:SetText(L["AH_SLICE_COUNT"] or "Slice Count")
    
    -- Right Panel Title (shifted 8px right)
    local rightTitle = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightTitle:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 26, -14)  -- 18 + 8 = 26
    rightTitle:SetText(L["AH_ASSIGNMENTS"] or "Assignments")
    rightTitle:SetTextColor(0.95, 0.90, 0.85, 1)  -- White with brown tint
    
    local rightDesc = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rightDesc:SetPoint("TOPLEFT", rightTitle, "BOTTOMLEFT", 0, -4)
    rightDesc:SetJustifyH("LEFT")
    rightDesc:SetText(L["RING_SELECT_NODE_INFO"] or "Select a node on the left to assign an action.")
    rightDesc:SetTextColor(0.90, 0.85, 0.80, 1)  -- Lighter brownish-white
    self.assignmentInfo = rightDesc




    
    -- Search Box (Narrowed to fit mount count on the right)
    local toySearchBox = CreateFrame("EditBox", "OxedRingToySearchBox", rightPanel, "SearchBoxTemplate")
    toySearchBox:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 33, -50)
    toySearchBox:SetSize(140, 20)
    toySearchBox:SetAutoFocus(false)
    toySearchBox:HookScript("OnTextChanged", function(self, isUserInput)
        if self.isSyncingText then return end
        if not isUserInput then return end
        local text = self:GetText() or ""
        -- SearchBoxTemplate sets the text to the localized "Search" placeholder when
        -- the field is empty. Treat that as an empty filter so all items are shown.
        if text == (SEARCH or "Search") or text == "Search" then
            text = ""
        end
        rightPanel.toySearchText = text

        if self.searchTimer then
            self.searchTimer:Cancel()
        end

        self.searchTimer = C_Timer.NewTimer(0.25, function()
            OxedRingEditor:RefreshPickerList()
        end)
    end)
    self.toySearchBox = toySearchBox

    -- Mount Count Label on the right side of the search box
    local mountCountLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mountCountLabel:SetPoint("LEFT", toySearchBox, "RIGHT", 10, 0)
    mountCountLabel:SetTextColor(0.95, 0.90, 0.85, 1)
    mountCountLabel:Hide()
    self.mountCountLabel = mountCountLabel

    local scroll = CreateFrame("ScrollFrame", nil, rightPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 24, -80)  -- 16 + 8 = 24
    scroll:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -36, 36)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(scroll)
    end
    
    self.assignmentScroll = scroll

    -- Highly visible red underlay behind the right panel icons, as requested
    local gridUnderlay = scroll:CreateTexture(nil, "BACKGROUND")
    gridUnderlay:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 9, -10)
    gridUnderlay:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -18, 14)
    gridUnderlay:SetColorTexture(0.2, 0.1, 0.05, 0.1) -- 10% brown underlay
    gridUnderlay:SetDrawLayer("BACKGROUND", 1)
    self.gridUnderlay = gridUnderlay

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(260)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    self.assignmentScrollChild = scrollChild

    CreateDisconnectedAssignmentTabs(rightPanel)

    -- Sidebar category buttons (on the dragon tube)
    local sidebarCategories = {
        { name = "Toys",      type = "toy",      icon = 134508 },
        { name = "Reactions", type = "emote",    icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Emojis\\Kiss.png" },
        { name = "Markers",   type = "marker",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
        { name = "Items",     type = "item",     icon = 3753262 },
        { name = "Mounts",    type = "mount",    icon = 2143068 },
        { name = "Settings",  type = "settings", icon = 4548872 }
    }

    rightPanel.sidebarButtons = {}
    local startY = -120
    for i, cat in ipairs(sidebarCategories) do
        -- Container frame (same pattern as the OxedHub logo in UI.lua)
        -- Container frame
        local container = CreateFrame("Button", nil, rightPanel)
        container:SetSize(44, 44)
        container:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", -34, startY - ((i-1) * 52))
        container:SetFrameLevel(rightPanel:GetFrameLevel() + 20)

        -- Mask for circle (applied to bg and icon)
        local mask = container:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetSize(32, 32)
        mask:SetPoint("CENTER", 1, -1)
        container.iconMask = mask  -- Keep reference to prevent GC
        
        -- Black background fill (underlay for transparent icons)
        local bg = container:CreateTexture(nil, "BACKGROUND")
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetSize(32, 32)
        bg:SetPoint("CENTER", 1, -1)
        bg:SetVertexColor(0, 0, 0, 1)  -- 100% opaque
        bg:AddMaskTexture(mask)
        
        -- Icon texture
        local icon = container:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(cat.icon)
        icon:SetSize(32, 32)
        icon:SetPoint("CENTER", 1, -1)
        icon:AddMaskTexture(mask)
        
        -- Ring border on top (Blizzard's minimap tracking border)
        local ring = container:CreateTexture(nil, "OVERLAY")
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetAllPoints()
        ring:SetTexCoord(0, 0.6, 0, 0.6)  -- Crop tightly to ring edge
        container.border = ring
        
        container.catType = cat.type
        
        container:SetScript("OnClick", function()
            if rightPanel.selectedType ~= cat.type then
                rightPanel.toySearchText = ""
                if OxedRingEditor.toySearchBox then
                    OxedRingEditor.toySearchBox.isSyncingText = true
                    OxedRingEditor.toySearchBox:SetText("")
                    OxedRingEditor.toySearchBox.isSyncingText = false
                end
            end
            rightPanel.selectedType = cat.type
            OxedRingEditor:RefreshPickerList()
        end)
        
        container:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local key = "TAB_" .. cat.type:upper()
            GameTooltip:SetText(L[key] or cat.name)
            GameTooltip:Show()
        end)
        container:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        table.insert(rightPanel.sidebarButtons, container)
    end
    
    -- Create editor sub-frame for Emote/Reaction configs
    local editor = CreateFrame("Frame", nil, rightPanel)
    editor:SetAllPoints()
    editor:Hide()
    rightPanel.editor = editor

    local function CreateEditorPicker(labelText, xOffset, yOffset, valueGetter, onClick)
        local label = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", editor, "TOPLEFT", xOffset, yOffset)
        label:SetText(labelText)
        label:SetTextColor(1, 0.82, 0)

        local button = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
        button:SetSize(110, 24)
        button:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
        
        local btnText = button:GetFontString()
        if btnText then
            btnText:SetWordWrap(false)
            btnText:SetWidth(100)
            btnText:SetJustifyH("CENTER")
        end
        
        button.valueGetter = valueGetter
        button:SetScript("OnClick", onClick)
        return { label = label, button = button }
    end

    local function CreateNativePicker()
        local f = _G["OxedRingNativePicker"]
        if not f then
            f = CreateFrame("Frame", "OxedRingNativePicker", UIParent, "BackdropTemplate")
            f:SetSize(220, 264)
            f:SetFrameStrata("DIALOG")
            f:SetFrameLevel(500)
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })
            f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
            f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
            f:Hide()
            
            local searchBox = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
            searchBox:SetSize(204, 20)
            searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
            searchBox:SetAutoFocus(false)
            f.searchBox = searchBox

            local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 8, -32)
            scroll:SetPoint("BOTTOMRIGHT", -26, 8)
            if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
                OxedHub.UI:StyleScrollFrame(scroll)
            end
            f.scrollFrame = scroll
            
            local child = CreateFrame("Frame")
            child:SetWidth(180)
            child:SetHeight(1)
            scroll:SetScrollChild(child)
            f.scrollChild = child
            f.buttons = {}
            f.playButtons = {}
            
            searchBox:HookScript("OnTextChanged", function(self)
                local text = self:GetText():lower()
                -- Treat the SearchBoxTemplate localized placeholder as empty
                if text == (SEARCH and SEARCH:lower() or "search") or text == "search" then
                    text = ""
                end
                f:FilterOptions(text)
            end)
            
            -- Close when clicking outside
            f:SetScript("OnUpdate", function(self)
                if self:IsShown() and not self:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        self:Hide()
                    end
                end
            end)
        end
        
        local function GetSoundInfo(val)
            local profile = OxedHub.db and OxedHub.db.profile
            return profile and profile.customSounds and profile.customSounds[val]
        end

        f.FilterOptions = function(self, filterText)
            for _, btn in ipairs(self.buttons) do btn:Hide() end
            for _, pbtn in ipairs(self.playButtons) do pbtn:Hide() end

            local matchedOptions = {}
            for _, opt in ipairs(self.fullOptions or {}) do
                local match = true
                if filterText and filterText ~= "" then
                    local label = opt.label and tostring(opt.label):lower() or ""
                    local value = opt.value and tostring(opt.value):lower() or ""
                    if not label:find(filterText, 1, true) and not value:find(filterText, 1, true) then
                        match = false
                    end
                end
                if match then
                    table.insert(matchedOptions, opt)
                end
            end

            local displayList = {}
            if self.isSound then
                local noneOpt = nil
                local favorites = {}
                local customs = {}
                local others = {}

                for _, opt in ipairs(matchedOptions) do
                    if opt.value == nil then
                        noneOpt = opt
                    else
                        local sound = GetSoundInfo(opt.value)
                        if sound then
                            if sound.isFavorite then
                                table.insert(favorites, opt)
                            end
                            if not sound.autoImported then
                                table.insert(customs, opt)
                            else
                                local cat = (sound.category and sound.category ~= "") and sound.category or "Other"
                                others[cat] = others[cat] or {}
                                table.insert(others[cat], opt)
                            end
                        else
                            local cat = "Other"
                            others[cat] = others[cat] or {}
                            table.insert(others[cat], opt)
                        end
                    end
                end

                local function sortFunc(a, b)
                    return (a.label or ""):lower() < (b.label or ""):lower()
                end
                table.sort(favorites, sortFunc)
                table.sort(customs, sortFunc)
                for cat, list in pairs(others) do
                    table.sort(list, sortFunc)
                end

                if noneOpt then
                    table.insert(displayList, noneOpt)
                end

                local function insertCategory(catName, list)
                    if #list > 0 then
                        local isCollapsed = true
                        if filterText and filterText ~= "" then
                            isCollapsed = false
                        else
                            if self.collapsedCategories[catName] == false then
                                isCollapsed = false
                            end
                        end

                        table.insert(displayList, {
                            isHeader = true,
                            label = (isCollapsed and "> " or "v ") .. catName .. " (" .. #list .. ")",
                            catName = catName,
                            isCollapsed = isCollapsed
                        })

                        if not isCollapsed then
                            for _, opt in ipairs(list) do
                                table.insert(displayList, opt)
                            end
                        end
                    end
                end

                insertCategory("Favorites", favorites)
                insertCategory("Custom", customs)

                local CATEGORY_ORDER = {
                    "DH Pack",
                    "Monk Pack",
                    "Worrier Pack",
                    "Death",
                    "Effects",
                    "Meme",
                    "Legions",
                    "Quote",
                    "Anime",
                    "Arabic",
                    "Other"
                }

                local processed = {}
                for _, catName in ipairs(CATEGORY_ORDER) do
                    local list = others[catName]
                    if list and #list > 0 then
                        insertCategory(catName, list)
                        processed[catName] = true
                    end
                end

                local extraCats = {}
                for catName, list in pairs(others) do
                    if not processed[catName] and #list > 0 then
                        table.insert(extraCats, catName)
                    end
                end
                table.sort(extraCats)
                for _, catName in ipairs(extraCats) do
                    insertCategory(catName, others[catName])
                end
            else
                displayList = matchedOptions
            end

            local y = 0
            local count = 0
            for _, opt in ipairs(displayList) do
                count = count + 1
                local btn = self.buttons[count]
                if not btn then
                    btn = CreateFrame("Button", nil, self.scrollChild)
                    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    self.buttons[count] = btn
                end
                
                btn:Show()
                btn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -y)

                if opt.isHeader then
                    btn:SetSize(180, 20)
                    btn:SetNormalFontObject("GameFontNormalSmall")
                    btn:SetText(opt.label)
                    btn:SetEnabled(true)
                    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetAlpha(0.2) end
                    btn:SetScript("OnClick", function()
                        self.collapsedCategories[opt.catName] = not opt.isCollapsed
                        self:FilterOptions(self.searchBox:GetText())
                    end)
                    
                    local playBtn = self.playButtons[count]
                    if playBtn then playBtn:Hide() end
                else
                    btn:SetNormalFontObject("GameFontHighlightSmall")
                    btn:SetText(opt.label)
                    btn:SetEnabled(true)
                    if btn:GetHighlightTexture() then btn:GetHighlightTexture():SetAlpha(0.4) end
                    btn:SetScript("OnClick", function()
                        self:Hide()
                        if self.onSelect then self.onSelect(opt.value) end
                    end)

                    if self.isSound and opt.value ~= nil then
                        btn:SetSize(158, 20)
                        local playBtn = self.playButtons[count]
                        if not playBtn then
                            playBtn = CreateFrame("Button", nil, self.scrollChild)
                            playBtn:SetSize(18, 18)
                            local playIcon = playBtn:CreateTexture(nil, "ARTWORK")
                            playIcon:SetAllPoints()
                            playIcon:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
                            playIcon:SetVertexColor(0.9, 0.1, 0.1)
                            playBtn.icon = playIcon
                            playBtn:SetScript("OnEnter", function(self)
                                self.icon:SetVertexColor(1, 0.3, 0.3)
                            end)
                            playBtn:SetScript("OnLeave", function(self)
                                self.icon:SetVertexColor(0.9, 0.1, 0.1)
                            end)
                            self.playButtons[count] = playBtn
                        end
                        playBtn:Show()
                        playBtn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 160, -y)
                        playBtn:SetScript("OnClick", function()
                            if OxedHub.Sounds then
                                OxedHub.Sounds:Play(opt.value)
                            end
                        end)
                    else
                        btn:SetSize(180, 20)
                        local playBtn = self.playButtons[count]
                        if playBtn then playBtn:Hide() end
                    end
                end
                y = y + 22
            end
            self.scrollChild:SetHeight(math.max(y, 1))
            self.scrollFrame:SetVerticalScroll(0)
        end

        f.ShowOptions = function(self, anchor, options, onSelect, isSound)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
            self:Show()
            self.fullOptions = options
            self.onSelect = onSelect
            self.isSound = isSound
            if isSound then
                self.collapsedCategories = {}
            end
            self.searchBox:SetText("")
            self:FilterOptions("")
        end
        
        return f
    end

    local nativePicker = CreateNativePicker()

    local er = OxedHub.EmotionRing
    rightPanel.reactionTabFrame = CreateFrame("Frame", nil, editor)
    rightPanel.reactionTabFrame:SetAllPoints()
    
    rightPanel.macroTabFrame = CreateFrame("Frame", nil, editor)
    rightPanel.macroTabFrame:SetAllPoints()

    rightPanel.soundPicker = CreateEditorPicker("Sound", 28, -10, 
        function() local e = OxedRingEditor:GetSelectedEmote() return e and GetCustomReaction(e).sound end,
        function() 
            local e = OxedRingEditor:GetSelectedEmote()
            if not e or e == "None" then return end
            nativePicker:ShowOptions(rightPanel.soundPicker.button, GetNativeSoundOptions(), function(val)
                GetCustomReaction(e).sound = val
                OxedRingEditor:RefreshPickerList()
            end, true)
        end)
    rightPanel.soundPicker.label:SetParent(rightPanel.reactionTabFrame)
    rightPanel.soundPicker.button:SetParent(rightPanel.reactionTabFrame)

    rightPanel.animationPicker = CreateEditorPicker("Animation", 28, -60,
        function() local e = OxedRingEditor:GetSelectedEmote() return e and GetCustomReaction(e).animation end,
        function() 
            local e = OxedRingEditor:GetSelectedEmote()
            if not e or e == "None" then return end
            nativePicker:ShowOptions(rightPanel.animationPicker.button, GetNativeAnimationOptions(), function(val)
                GetCustomReaction(e).animation = val
                OxedRingEditor:RefreshPickerList()
            end)
        end)
    rightPanel.animationPicker.label:SetParent(rightPanel.reactionTabFrame)
    rightPanel.animationPicker.button:SetParent(rightPanel.reactionTabFrame)

    local animCheck = CreateFrame("CheckButton", nil, rightPanel.reactionTabFrame, "UICheckButtonTemplate")
    animCheck:SetPoint("TOPLEFT", rightPanel.animationPicker.button, "BOTTOMLEFT", 0, -4)
    animCheck:SetSize(20, 20)

    rightPanel.animCheck = animCheck
    local animCheckLabel = rightPanel.reactionTabFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    animCheckLabel:SetPoint("LEFT", animCheck, "RIGHT", 4, 0)
    animCheckLabel:SetText("Custom")

    local setPosBtn = CreateFrame("Button", nil, rightPanel.reactionTabFrame, "UIPanelButtonTemplate")
    setPosBtn:SetSize(70, 20)
    setPosBtn:SetPoint("LEFT", animCheckLabel, "RIGHT", 8, 0)
    setPosBtn:SetText("Set Pos")
    setPosBtn:SetScript("OnClick", function() 
        local e = OxedRingEditor:GetSelectedEmote()
        if not e or e == "None" then return end
        local r = GetCustomReaction(e)
        local x = r.animationCustomX or 0
        local y = r.animationCustomY or 200
        
        if OxedHub.Animations and OxedHub.Animations.ShowPositionFrameCustom then
            OxedHub.Animations:ShowPositionFrameCustom(x, y, function(relX, relY)
                local currentE = OxedRingEditor:GetSelectedEmote()
                if currentE and currentE ~= "None" then
                    local cr = GetCustomReaction(currentE)
                    cr.animationCustomX = relX
                    cr.animationCustomY = relY
                end
            end)
        end
    end)
    rightPanel.setPosBtn = setPosBtn

    animCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        local emote = OxedRingEditor:GetSelectedEmote()
        if emote and emote ~= "None" then 
            GetCustomReaction(emote).animationUseCustomPosition = checked
        end
        setPosBtn:SetEnabled(checked)
    end)

    rightPanel.emotePicker = CreateEditorPicker("Emote", 148, -10,
        function() local e = OxedRingEditor:GetSelectedEmote() return e and GetCustomReaction(e).emote end,
        function() 
            local e = OxedRingEditor:GetSelectedEmote()
            if not e or e == "None" then return end
            nativePicker:ShowOptions(rightPanel.emotePicker.button, GetNativeEmoteOptions(), function(val)
                GetCustomReaction(e).emote = val
                OxedRingEditor:RefreshPickerList()
            end)
        end)
    rightPanel.emotePicker.label:SetParent(rightPanel.reactionTabFrame)
    rightPanel.emotePicker.button:SetParent(rightPanel.reactionTabFrame)

    rightPanel.toyMacroPicker = CreateEditorPicker("Toy Macro", 28, -10,
        function() local e = OxedRingEditor:GetSelectedEmote() return e and GetCustomReaction(e).toyMacro end,
        function() 
            -- We just hide this anyway for Emotes in the new UI
        end)
    rightPanel.toyMacroPicker.label:SetParent(rightPanel.macroTabFrame)
    rightPanel.toyMacroPicker.button:SetParent(rightPanel.macroTabFrame)

    -- Settings scroll child â€” reuses the shared assignmentScroll (swapped in on tab switch)
    local settingsScrollChild = CreateFrame("Frame")
    settingsScrollChild:SetWidth(250)
    settingsScrollChild:SetHeight(700)
    rightPanel.settingsScrollChild = settingsScrollChild

    -- Settings panel inputs & controls
    local function CreateNumericInput(parent, anchorTo)
        local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        input:SetSize(34, 20)
        input:SetAutoFocus(false)
        input:SetNumeric(false)
        input:SetJustifyH("CENTER")
        input:SetPoint("LEFT", anchorTo, "RIGHT", 16, 0)
        return input
    end

    local function BindSliderInput(slider, input, minValue, maxValue, step, applyValue)
        local function SnapValue(value)
            if not value then return nil end
            local snapped = value
            if step and step > 0 then
                snapped = math_floor((value / step) + 0.5) * step
            end
            if minValue then snapped = math.max(minValue, snapped) end
            if maxValue then snapped = math.min(maxValue, snapped) end
            return snapped
        end

        local function CommitInput()
            local text = input:GetText()
            local value = tonumber(text)
            if not value then
                input:SetText(tostring(math_floor((slider:GetValue() or 0) + 0.5)))
                return
            end

            local snapped = SnapValue(value)
            if not snapped then return end

            slider.isResetting = true
            slider:SetValue(snapped)
            slider.isResetting = false
            input:SetText(tostring(snapped))
            if applyValue then
                applyValue(snapped)
            end
            RefreshPreview()
        end

        input:SetScript("OnEnterPressed", function(self)
            CommitInput()
            self:ClearFocus()
        end)
        input:SetScript("OnEditFocusLost", function()
            CommitInput()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(math_floor((slider:GetValue() or 0) + 0.5)))
            self:ClearFocus()
        end)
    end

    -- Global Node Size
    local globalSizeLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    globalSizeLabel:SetPoint("TOPLEFT", settingsScrollChild, "TOPLEFT", 12, -10)
    globalSizeLabel:SetText(L["SETTINGS_GLOBAL_NODE_SIZE"] or "Global Node Size")
    globalSizeLabel:SetTextColor(1, 0.82, 0)

    local globalSizeSlider = CreateFrame("Slider", nil, settingsScrollChild, "OptionsSliderTemplate")
    globalSizeSlider:SetPoint("TOPLEFT", globalSizeLabel, "BOTTOMLEFT", 0, -14)
    globalSizeSlider:SetWidth(110)
    globalSizeSlider:SetMinMaxValues(20, 80)
    globalSizeSlider:SetValueStep(2)
    globalSizeSlider:SetObeyStepOnDrag(true)

    local globalSizeInput = CreateNumericInput(settingsScrollChild, globalSizeSlider)
    rightPanel.globalSizeInput = globalSizeInput

    local globalSizeResetBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
        globalSizeResetBtn:SetSize(22, 22)
        globalSizeResetBtn:SetPoint("LEFT", globalSizeInput, "RIGHT", 10, 0)
        globalSizeResetBtn:SetText("")
        local globalSizeResetIcon = globalSizeResetBtn:CreateTexture(nil, "ARTWORK")
        globalSizeResetIcon:SetSize(14, 14)
        globalSizeResetIcon:SetPoint("CENTER", globalSizeResetBtn, "CENTER", 0, 0)
        globalSizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        globalSizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        globalSizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    globalSizeResetBtn:SetScript("OnClick", function()
        OxedHub.db.profile.oxedRingGlobalNodeSize = nil
        rightPanel.globalSizeSlider.isResetting = true
        rightPanel.globalSizeSlider:SetValue(40)
        rightPanel.globalSizeVal:SetText("40")
        rightPanel.globalSizeInput:SetText("40")
        rightPanel.globalSizeSlider.isResetting = false
        RefreshPreview()
    end)

    local globalSizeVal = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    globalSizeVal:SetPoint("BOTTOM", globalSizeSlider, "TOP", 0, 2)
    rightPanel.globalSizeVal = globalSizeVal

    globalSizeSlider:SetScript("OnValueChanged", function(self, value)
        if self.isResetting then return end
        OxedHub.db.profile.oxedRingGlobalNodeSize = value
        rightPanel.globalSizeVal:SetText(tostring(value))
        rightPanel.globalSizeInput:SetText(tostring(value))
        RefreshPreview()
    end)
    BindSliderInput(globalSizeSlider, globalSizeInput, 20, 80, 2, function(value)
        OxedHub.db.profile.oxedRingGlobalNodeSize = value
        rightPanel.globalSizeVal:SetText(tostring(value))
    end)
    rightPanel.globalSizeSlider = globalSizeSlider

    -- Ring Radius
    local radiusLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    radiusLabel:SetPoint("TOPLEFT", globalSizeSlider, "BOTTOMLEFT", 0, -30)
    radiusLabel:SetText(L["SETTINGS_RING_RADIUS"] or "Ring Radius")
    radiusLabel:SetTextColor(1, 0.82, 0)

    local radiusSlider = CreateFrame("Slider", nil, settingsScrollChild, "OptionsSliderTemplate")
    radiusSlider:SetPoint("TOPLEFT", radiusLabel, "BOTTOMLEFT", 0, -14)
    radiusSlider:SetWidth(110)
    radiusSlider:SetMinMaxValues(40, 200)
    radiusSlider:SetValueStep(5)
    radiusSlider:SetObeyStepOnDrag(true)

    local radiusInput = CreateNumericInput(settingsScrollChild, radiusSlider)
    rightPanel.ringRadiusInput = radiusInput

    local radiusResetBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
        radiusResetBtn:SetSize(22, 22)
        radiusResetBtn:SetPoint("LEFT", radiusInput, "RIGHT", 10, 0)
        radiusResetBtn:SetText("")
        local radiusResetIcon = radiusResetBtn:CreateTexture(nil, "ARTWORK")
        radiusResetIcon:SetSize(14, 14)
        radiusResetIcon:SetPoint("CENTER", radiusResetBtn, "CENTER", 0, 0)
        radiusResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        radiusResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        radiusResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    radiusResetBtn:SetScript("OnClick", function()
        OxedHub.db.profile.oxedRingRadius = nil
        rightPanel.ringRadiusSlider.isResetting = true
        rightPanel.ringRadiusSlider:SetValue(100)
        rightPanel.ringRadiusVal:SetText("100")
        rightPanel.ringRadiusInput:SetText("100")
        rightPanel.ringRadiusSlider.isResetting = false
        RefreshPreview()
    end)

    local radiusVal = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    radiusVal:SetPoint("BOTTOM", radiusSlider, "TOP", 0, 2)
    rightPanel.ringRadiusVal = radiusVal

    radiusSlider:SetScript("OnValueChanged", function(self, value)
        if self.isResetting then return end
        OxedHub.db.profile.oxedRingRadius = value
        rightPanel.ringRadiusVal:SetText(tostring(value))
        rightPanel.ringRadiusInput:SetText(tostring(value))
        RefreshPreview()
    end)
    BindSliderInput(radiusSlider, radiusInput, 40, 200, 5, function(value)
        OxedHub.db.profile.oxedRingRadius = value
        rightPanel.ringRadiusVal:SetText(tostring(value))
    end)
    rightPanel.ringRadiusSlider = radiusSlider

    -- Ring Style dropdown (Squares / Rings)
    local styleLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    styleLabel:SetPoint("TOPLEFT", radiusSlider, "BOTTOMLEFT", 0, -30)
    styleLabel:SetText(L["SETTINGS_RING_STYLE"] or "Ring Style:")
    styleLabel:SetTextColor(1, 0.82, 0)

    local styleBtn = CreateFrame("DropdownButton", nil, settingsScrollChild, "WowStyle1DropdownTemplate")
    styleBtn:SetPoint("TOPLEFT", styleLabel, "BOTTOMLEFT", 0, -6)
    styleBtn:SetSize(160, 26)
    rightPanel.styleBtn = styleBtn

    local styles = {
        { key = "square", name = L["STYLE_SQUARES"] or "Squares" },
        { key = "ring",   name = L["STYLE_RINGS"] or "Rings" },
    }
    rightPanel.styles = styles

    local function IsStyleSelected(key)
        return GetRingStyle() == key
    end

    styleBtn:SetupMenu(function(dropdown, rootDescription)
        for _, entry in ipairs(styles) do
            rootDescription:CreateRadio(
                entry.name,
                function() return IsStyleSelected(entry.key) end,
                function()
                    OxedHub.db.profile.oxedRingStyle = entry.key
                    styleBtn:OverrideText(entry.name)
                    RefreshPreview()
                    OxedRingEditor:RefreshPickerList()
                end,
                entry.key
            )
        end
    end)
    
    for _, entry in ipairs(styles) do
        if entry.key == GetRingStyle() then
            styleBtn:OverrideText(entry.name)
            break
        end
    end

    -- Show Node Titles Checkbox
    local showTitlesCheck = CreateFrame("CheckButton", nil, settingsScrollChild, "UICheckButtonTemplate")
    showTitlesCheck:SetPoint("TOPLEFT", styleBtn, "BOTTOMLEFT", 0, -20)
    showTitlesCheck:SetSize(24, 24)
    rightPanel.showTitlesCheck = showTitlesCheck

    local showTitlesLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showTitlesLabel:SetPoint("LEFT", showTitlesCheck, "RIGHT", 4, 0)
    showTitlesLabel:SetText(L["SETTINGS_SHOW_NODE_TITLES"] or "Show Node Titles")
    showTitlesLabel:SetTextColor(1, 0.82, 0)

    showTitlesCheck:SetScript("OnClick", function(self)
        OxedHub.db.profile.oxedRingShowNodeTitles = self:GetChecked()
        RefreshPreview()
    end)

    -- Node Title Font Size
    local fontSizeLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeLabel:SetPoint("TOPLEFT", showTitlesCheck, "BOTTOMLEFT", 0, -14)
    fontSizeLabel:SetText(L["SETTINGS_NODE_TITLE_SIZE"] or "Node Title Size")
    fontSizeLabel:SetTextColor(1, 0.82, 0)

    local fontSizeSlider = CreateFrame("Slider", nil, settingsScrollChild, "OptionsSliderTemplate")
    fontSizeSlider:SetPoint("TOPLEFT", fontSizeLabel, "BOTTOMLEFT", 4, -14)
    fontSizeSlider:SetWidth(110)
    fontSizeSlider:SetMinMaxValues(6, 24)
    fontSizeSlider:SetValueStep(1)
    fontSizeSlider:SetObeyStepOnDrag(true)

    local fontSizeInput = CreateNumericInput(settingsScrollChild, fontSizeSlider)
    rightPanel.fontSizeInput = fontSizeInput

    local fontSizeResetBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
        fontSizeResetBtn:SetSize(22, 22)
        fontSizeResetBtn:SetPoint("LEFT", fontSizeInput, "RIGHT", 10, 0)
        fontSizeResetBtn:SetText("")
        local fontSizeResetIcon = fontSizeResetBtn:CreateTexture(nil, "ARTWORK")
        fontSizeResetIcon:SetSize(14, 14)
        fontSizeResetIcon:SetPoint("CENTER", fontSizeResetBtn, "CENTER", 0, 0)
        fontSizeResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        fontSizeResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        fontSizeResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    fontSizeResetBtn:SetScript("OnClick", function()
        OxedHub.db.profile.oxedRingNodeTitleSize = nil
        rightPanel.fontSizeSlider.isResetting = true
        rightPanel.fontSizeSlider:SetValue(11)
        rightPanel.fontSizeVal:SetText("11")
        rightPanel.fontSizeInput:SetText("11")
        rightPanel.fontSizeSlider.isResetting = false
        RefreshPreview()
    end)

    local fontSizeVal = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fontSizeVal:SetPoint("BOTTOM", fontSizeSlider, "TOP", 0, 2)
    rightPanel.fontSizeVal = fontSizeVal

    fontSizeSlider:SetScript("OnValueChanged", function(self, value)
        if self.isResetting then return end
        OxedHub.db.profile.oxedRingNodeTitleSize = value
        rightPanel.fontSizeVal:SetText(tostring(value))
        rightPanel.fontSizeInput:SetText(tostring(value))
        RefreshPreview()
    end)
    BindSliderInput(fontSizeSlider, fontSizeInput, 6, 24, 1, function(value)
        OxedHub.db.profile.oxedRingNodeTitleSize = value
        rightPanel.fontSizeVal:SetText(tostring(value))
        RefreshPreview()
    end)
    rightPanel.fontSizeSlider = fontSizeSlider

    -- Ring Keybind
    local ringBindLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ringBindLabel:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -30)
    ringBindLabel:SetText(L["SETTINGS_RING_KEYBIND"] or "Ring Keybind")
    ringBindLabel:SetTextColor(1, 0.82, 0)

    local ringBindBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
    ringBindBtn:SetSize(160, 24)
    ringBindBtn:SetPoint("TOPLEFT", ringBindLabel, "BOTTOMLEFT", 0, -6)
    ringBindBtn:SetText(L["KEYBIND_NOT_BOUND"] or "Not Bound")
    
    ringBindBtn:SetScript("OnClick", function(self)
        self.isListening = true
        self.oldBindingText = self:GetText()
        self:SetText(L["KEYBIND_LISTENING"] or "Press a key...")
        
        bindingEditBox.targetButton = self
        bindingEditBox.onBindCallback = function(fullKey)
            if OxedHub.OxedRing and OxedHub.OxedRing.ApplyRingBinding then
                OxedHub.OxedRing:ApplyRingBinding(fullKey)
            end
        end
        bindingEditBox:Show()
        bindingEditBox:SetFocus()
    end)
    ringBindBtn:SetScript("OnHide", function(self)
        self.isListening = false
        if bindingEditBox.targetButton == self then
            bindingEditBox:ClearFocus()
            bindingEditBox:Hide()
        end
    end)
    rightPanel.ringBindBtn = ringBindBtn

    local ringBindResetBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
        ringBindResetBtn:SetSize(22, 22)
        ringBindResetBtn:SetPoint("LEFT", ringBindBtn, "RIGHT", 10, 0)
        ringBindResetBtn:SetText("")
        local ringBindResetIcon = ringBindResetBtn:CreateTexture(nil, "ARTWORK")
        ringBindResetIcon:SetSize(14, 14)
        ringBindResetIcon:SetPoint("CENTER", ringBindResetBtn, "CENTER", 0, 0)
        ringBindResetIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
        ringBindResetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(L["SETTINGS_BTN_RESET"] or "Reset")
            GameTooltip:Show()
        end)
        ringBindResetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ringBindResetBtn:SetScript("OnClick", function()
        if OxedHub.OxedRing and OxedHub.OxedRing.ApplyRingBinding then
            OxedHub.OxedRing:ApplyRingBinding(nil)
        end
        if rightPanel.ringBindBtn then
            rightPanel.ringBindBtn.isListening = false
            rightPanel.ringBindBtn:SetText(L["KEYBIND_NOT_BOUND"] or "Not Bound")
        end
        if bindingEditBox.targetButton == rightPanel.ringBindBtn then
            bindingEditBox:ClearFocus()
            bindingEditBox:Hide()
        end
    end)
    rightPanel.ringBindResetBtn = ringBindResetBtn

    -- Refresh Toys / Mounts (data is cached once; this rebuilds it on demand)
    local refreshLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refreshLabel:SetPoint("TOPLEFT", ringBindBtn, "BOTTOMLEFT", 0, -18)
    refreshLabel:SetText(L["SETTINGS_REFRESH_COLLECTIONS"] or "Refresh Collections")
    refreshLabel:SetTextColor(1, 0.82, 0)

    local refreshToysLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refreshToysLabel:SetPoint("TOPLEFT", refreshLabel, "BOTTOMLEFT", 0, -12)
    refreshToysLabel:SetText(L["SETTINGS_BTN_REFRESH_TOYS"] or "Refresh Toys")

    local refreshToysBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
    refreshToysBtn:SetSize(26, 26)
    refreshToysBtn:SetPoint("LEFT", refreshToysLabel, "RIGHT", 10, 0)
    refreshToysBtn:SetText("")
    local toysIcon = refreshToysBtn:CreateTexture(nil, "ARTWORK")
    toysIcon:SetSize(14, 14)
    toysIcon:SetPoint("CENTER", refreshToysBtn, "CENTER", 0, 0)
    toysIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
    refreshToysBtn:SetScript("OnClick", function()
        if OxedHub.Toys and OxedHub.Toys.CacheToyData then
            OxedHub.Toys:CacheToyData(true)
        end
        OxedRingEditor:RefreshPickerList()
    end)

    local refreshMountsLabel = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    refreshMountsLabel:SetPoint("TOPLEFT", refreshToysLabel, "BOTTOMLEFT", 0, -16)
    refreshMountsLabel:SetText(L["SETTINGS_BTN_REFRESH_MOUNTS"] or "Refresh Mounts")

    local refreshMountsBtn = CreateFrame("Button", nil, settingsScrollChild, "UIPanelButtonTemplate")
    refreshMountsBtn:SetSize(26, 26)
    refreshMountsBtn:SetPoint("LEFT", refreshMountsLabel, "RIGHT", 10, 0)
    refreshMountsBtn:SetText("")
    local mountsIcon = refreshMountsBtn:CreateTexture(nil, "ARTWORK")
    mountsIcon:SetSize(14, 14)
    mountsIcon:SetPoint("CENTER", refreshMountsBtn, "CENTER", 0, 0)
    mountsIcon:SetTexture("Interface\\AddOns\\OxedHub\\Media\\Textures\\Icons\\reload.tga")
    refreshMountsBtn:SetScript("OnClick", function()
        OxedRingEditor:GetCachedMounts(true)
        OxedRingEditor:RefreshPickerList()
    end)

    local refreshNote = settingsScrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    refreshNote:SetPoint("TOPLEFT", refreshMountsLabel, "BOTTOMLEFT", 0, -12)
    refreshNote:SetWidth(220)
    refreshNote:SetJustifyH("LEFT")
    refreshNote:SetText(L["SETTINGS_REFRESH_WARNING"] or "* If you have a lot of toys/mounts the screen can freeze for 1-2 sec.")
    refreshNote:SetTextColor(0.72, 0.72, 0.72)

    RefreshPreview()
    self:RefreshAssignmentPanel()
    
    return tab
end

function OxedRingEditor:RefreshAssignmentPanel()
    -- No longer updating manual text fields as they have been removed.

    if not rightPanel.selectedType then
        rightPanel.selectedType = "toy"
    end
    self:RefreshPickerList()
end
