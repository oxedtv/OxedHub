local addonName, OxedHub = ...
local C_Timer = OxedHub.Profiler and OxedHub.Profiler:TimerProxy() or C_Timer  -- timers named in /oxprofile

-- ActionHub: the list inside the slot picker: what can be put on a
-- node, searched and sorted by category.
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

-- From the files loaded before this one (see Private in ActionHubData.lua).
local MouseIsOver = Private.MouseIsOver
local GetDirectToyDisplay = Private.GetDirectToyDisplay

function ActionHub:GetSelectedEmote()
    return ActionHub.selectedEmoteId
end

function ActionHub:RefreshPickerList()
    local dialog = self.pickerDialog
    if not dialog then return end

    local child = dialog.scrollChild
    if not child then return end

    if dialog.mountCountLabel then
        dialog.mountCountLabel:Hide()
    end

    -- Update tab highlights
    if dialog.sidebarButtons then
        for _, b in ipairs(dialog.sidebarButtons) do
            if b.catType == dialog.selectedType then
                b.border:SetVertexColor(1, 0.82, 0)  -- Bright gold when selected
            else
                b.border:SetVertexColor(0.6, 0.5, 0.3)  -- Dim bronze when not selected
            end
        end
    end

    if dialog.markerHeaders then
        for _, h in ipairs(dialog.markerHeaders) do
            h:Hide()
        end
    end

    local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
    local currentSlot = slots[dialog.slotIndex]

    -- Reset scroll anchor to full height for all tabs except emote
    dialog.scroll:ClearAllPoints()
    dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
    dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 36)

    if dialog.selectedType == "toy" then
        -- Show Macro Grid
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Show()
        dialog.showToysLabel:Show()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.showToysCheck:SetChecked(dialog.showDirectToys and true or false)
        dialog.sectionInfo:SetText(dialog.showDirectToys and (L["AH_PICK_TOY"] or "Pick a Toy for this slot") or (L["AH_PICK_TOYMIX"] or "Pick a ToyMix for this slot"))
        if dialog.showDirectToys then
            dialog.toySearchBox:Show()
            local desiredSearch = dialog.toySearchText or ""
            if dialog.toySearchBox:GetText() ~= desiredSearch then
                dialog.toySearchBox.isSyncingText = true
                dialog.toySearchBox:SetText(desiredSearch)
                dialog.toySearchBox.isSyncingText = false
            end
        else
            dialog.toySearchBox:Hide()
        end

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local items = {}
        if dialog.showDirectToys then
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
                    local displayName = cached.name or toyName or (L["Toy "] .. tostring(toyID))
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

            if dialog.mountCountLabel then
                local labelText = L["Toys: "] .. totalToys
                if searchText ~= "" then
                    labelText = L["Found: "] .. #items .. " / " .. totalToys
                end
                dialog.mountCountLabel:SetText(labelText)
                dialog.mountCountLabel:Show()
            end
        else
            local mixes = OxedHub.db.profile.toyMixes or {}
            local filter = OxedHub.db.profile.settings.filterByClass

            for mixName, mixData in pairs(mixes) do
                local show = true
                if filter and mixData.slots then
                    for _, slot in ipairs(mixData.slots) do
                        if slot and slot.type == "spell" then
                            if not OxedHub:IsSpellRelevant(slot.id) then
                                show = false
                                break
                            end
                        end
                    end
                end

                if show and OxedHub.Toys and OxedHub.Toys.GetMixToyAvailability then
                    local _, missingToys = OxedHub.Toys:GetMixToyAvailability(mixData)
                    if missingToys and missingToys > 0 then
                        show = false
                    end
                end

                if show then
                    local customIcon = OxedHub.Toys and OxedHub.Toys.GetMixCustomIcon and OxedHub.Toys:GetMixCustomIcon(mixName)
                    local icon1, icon2, icon3, icon4
                    if customIcon then
                        icon1 = customIcon
                    else
                        icon1 = "Interface\\Icons\\INV_Misc_QuestionMark"
                        icon2 = "Interface\\Icons\\INV_Misc_QuestionMark"
                        if OxedHub.Toys and OxedHub.Toys.GetMixSlotIcons then
                            icon1, icon2, icon3, icon4 = OxedHub.Toys:GetMixSlotIcons(mixName)
                        end
                    end
                    table.insert(items, { type = "toy", assignmentMode = "mix", id = mixName, name = mixName, icon1 = icon1, icon2 = icon2, icon3 = icon3, icon4 = icon4 })
                end
            end
        end

        table.sort(items, function(a, b) return a.name < b.name end)

        local btnSize = 48
        local spacing = 8
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -y * (btnSize + spacing + 18) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local q = "Interface\\Icons\\INV_Misc_QuestionMark"
            if item.icon2 and item.icon1 ~= q and item.icon2 ~= q and OxedHub.Toys and OxedHub.Toys.CreateSplitIcon then
                local splitIcon = OxedHub.Toys:CreateSplitIcon(btn, btnSize - 6, item.icon1, item.icon2, item.icon3, item.icon4)
                splitIcon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            else
                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon1 or q)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12) -- Prevent multiple lines if too long
            label:SetTextColor(0.90, 0.85, 0.80, 1)

            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

            -- Click assigns to currently selected slot
            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "toy"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].assignmentMode = item.assignmentMode
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
            end)

            -- Drag support: start dragging this macro
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "toy", id = item.id, assignmentMode = item.assignmentMode, icon = item.icon1 }
                -- Create floating drag icon
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon1 or "Interface\\Icons\\INV_Misc_QuestionMark")
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    -- Find which ring slot the cursor is over
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.assignmentMode = ActionHub.dragData.assignmentMode
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 20) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "emote" then
        -- Show Reaction Editor Split Screen
        dialog.scroll:ClearAllPoints()
        dialog.scroll:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -80)
        dialog.scroll:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -55, 240)
        dialog.scroll:Show()
        child:Show()
        
        dialog.settingsTabFrame:Hide()
        
        dialog.editor:ClearAllPoints()
        dialog.editor:SetPoint("TOPLEFT", dialog.scroll, "BOTTOMLEFT", -16, 0)
        dialog.editor:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 36)
        dialog.editor:Show()
        
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_PICK_EMOJI"] or "Pick an Emoji, then configure it below")
        dialog.reactionTabFrame:Show()
        dialog.macroTabFrame:Hide()

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
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
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -y * (btnSize + spacing + 14) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.1, 0.1, 0.1, 0.7)
            
            local isSelected = false
            local s = currentSlot
            local selectedBase = nil
            if s and s.type == "emote" then
                local map = OxedHub.db and OxedHub.db.profile.emotionMappings and OxedHub.db.profile.emotionMappings[s.id]
                selectedBase = map and map.emote or s.id
            end
            
            if ActionHub.selectedEmoteId == item.id or (selectedBase and selectedBase == item.id) then
                isSelected = true
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
            label:SetHeight(12)

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
                        -- Loop through and delete matching keys
                        for k, v in pairs(OxedHub.db.profile.customReactions) do
                            if type(v) == "table" and v.id == item.id then
                                OxedHub.db.profile.customReactions[k] = nil
                            end
                        end
                        if ActionHub.selectedEmoteId == item.id then
                            ActionHub.selectedEmoteId = nil
                        end
                        ActionHub:RefreshPickerList()
                    end
                    return
                end

                ActionHub.selectedEmoteId = item.id
                
                local activeDB = ActionHub:GetActiveHubDB()
                local slots = ActionHub:GetSlotsForSide(activeDB, dialog.slotSide)
                if slots and dialog.slotIndex then
                    slots[dialog.slotIndex] = slots[dialog.slotIndex] or {}
                    local slot = slots[dialog.slotIndex]
                    slot.type = "emote"
                    slot.id = item.id
                    slot.label = item.name
                    slot.icon = item.icon
                    slot.assignmentMode = nil
                    slot.requiresParty = nil
                    slot.requiresTarget = nil
                end

                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
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

            -- Drag support: drag this emoji onto a hub button
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetFrameStrata("TOOLTIP")
                    f:SetSize(40, 40)
                    f.tex = f:CreateTexture(nil, "OVERLAY")
                    f.tex:SetAllPoints()
                    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    f:EnableMouse(false)
                    f:SetScript("OnUpdate", function(fs)
                        local cx, cy = GetCursorPosition()
                        local sc = UIParent:GetEffectiveScale()
                        fs:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/sc, cy/sc)
                    end)
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragPayload = { type = "emote", id = item.id, name = item.name, icon = item.icon }
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then ActionHub.dragIcon:Hide() end
                local payload = ActionHub.dragPayload
                ActionHub.dragPayload = nil
                if not payload then return end

                local targetBtn = GetMouseFocus and GetMouseFocus() or nil

                -- Fallback to IsMouseOver if GetMouseFocus didn't get the preview button
                if not (targetBtn and targetBtn.slotIndex) then
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, pb in ipairs(tab.ringButtons) do
                            if pb and pb:IsShown() and pb:IsMouseOver() and pb.slotIndex then
                                targetBtn = pb
                                break
                            end
                        end
                    end
                end

                -- Fallback to live widgets
                if not (targetBtn and targetBtn.slotIndex) then
                    for _, w in ipairs(ActionHub.widgets or {}) do
                        if w and w.buttons then
                            for _, wb in ipairs(w.buttons) do
                                if wb and wb:IsShown() and wb:IsMouseOver() then
                                    targetBtn = wb
                                    break
                                end
                            end
                        end
                        if targetBtn and targetBtn.slotIndex then break end
                    end
                end

                if targetBtn and targetBtn.slotIndex and targetBtn.slotSide then
                    local activeDB = ActionHub:GetActiveHubDB()
                    local slots = ActionHub:GetSlotsForSide(activeDB, targetBtn.slotSide)
                    if not slots[targetBtn.slotIndex] then
                        slots[targetBtn.slotIndex] = {}
                    end
                    local slot = slots[targetBtn.slotIndex]
                    slot.type = payload.type
                    slot.id = payload.id
                    slot.label = payload.name
                    slot.icon = payload.icon
                    slot.assignmentMode = nil
                    slot.requiresParty = nil
                    slot.requiresTarget = nil

                    ActionHub.selectedEmoteId = payload.id
                    C_Timer.After(0, function()
                        ActionHub:ShowSlotPicker(targetBtn.slotIndex, targetBtn.slotSide)
                        ActionHub:RefreshTab()
                        ActionHub:RefreshPickerList()
                    end)
                end
            end)

            x = x + 1
            if x >= cols then
                x = 0
                y = y + 1
            end
        end

        -- Add New Button
        local addBtn = CreateFrame("Button", nil, child, "BackdropTemplate")
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
                                ActionHub:RefreshPickerList()
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
                preferredIndex = 3,
            }
            StaticPopup_Show("OXEDHUB_NEW_EMOJI")
        end)
        
        -- Set scrollchild size
        child:SetHeight((y + 1) * (btnSize + spacing + 14) + 10)
        child:SetWidth(cols * (btnSize + spacing))

        local currentEmote = "None"
        if currentSlot then
            currentEmote = ActionHub.selectedEmoteId
            if not currentEmote then
                currentEmote = (currentSlot.type == "emote") and currentSlot.id or "None"
            end
        end
        local hasEmote = (currentEmote and currentEmote ~= "None")
        local profile = OxedHub.db and OxedHub.db.profile
        local mappings = profile and profile.emotionMappings or {}
        local mapping = mappings[currentEmote] or {}

        -- Build option lists for labels
        local soundOpts = {{label = "None", value = nil}}
        for id, sound in pairs(profile and profile.customSounds or {}) do
            table.insert(soundOpts, {label = sound.name or id, value = id})
        end
        local animOpts = {{label = "None", value = nil}}
        for id, anim in pairs(profile and profile.animations or {}) do
            table.insert(animOpts, {label = anim.name or id, value = id})
        end
        local emoteOpts = {{label = "None", value = nil}}
        local predefined = {"APPLAUD","BEG","BOW","CHEER","CHICKEN","CRY","DANCE","FLEX","FLIRT","GASP","KISS","LAUGH","LEAN","POINT","ROAR","RUDE","SALUTE","SHY","SIGH","SLEEP","TAUNT","WAVE"}
        for _, cmd in ipairs(predefined) do
            local display = cmd:sub(1,1) .. cmd:sub(2):lower()
            table.insert(emoteOpts, {label = display, value = cmd})
        end
        local chatOpts = {{label = "None", value = nil}}
        for id, chat in pairs(profile and profile.chatTemplates or {}) do
            table.insert(chatOpts, {label = chat.name or chat.text or id, value = id})
        end
        local toyMixOpts = {{label = "None", value = nil}}
        for name in pairs(profile and profile.toyMixes or {}) do
            table.insert(toyMixOpts, {label = name, value = name})
        end

        local function getLabel(opts, val)
            if not val then return "None" end
            for _, o in ipairs(opts) do if o.value == val then return o.label end end
            return tostring(val)
        end

        dialog.soundPicker.button:SetText(getLabel(soundOpts, mapping.sound))
        dialog.animationPicker.button:SetText(getLabel(animOpts, mapping.animation))
        dialog.animCheck:SetChecked(mapping.animationUseCustomPosition or false)
        
        dialog.soundPicker.button:SetEnabled(hasEmote)
        dialog.animationPicker.button:SetEnabled(hasEmote)
        dialog.animCheck:SetEnabled(hasEmote)
        if dialog.setPosBtn then
            dialog.setPosBtn:SetEnabled(hasEmote and (mapping.animationUseCustomPosition or false))
        end
        dialog.emotePicker.button:SetEnabled(hasEmote)
        dialog.chatPicker.button:SetEnabled(hasEmote)
        dialog.toyMacroPicker.button:SetEnabled(hasEmote)

        dialog.emotePicker.button:SetText(getLabel(emoteOpts, mapping.emote))
        dialog.chatPicker.button:SetText(getLabel(chatOpts, mapping.chat))
        dialog.toyMacroPicker.button:SetText(getLabel(toyMixOpts, mapping.toyMacro))
    elseif dialog.selectedType == "mount" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Show()
        local desiredSearch = dialog.toySearchText or ""
        if dialog.toySearchBox:GetText() ~= desiredSearch then
            dialog.toySearchBox.isSyncingText = true
            dialog.toySearchBox:SetText(desiredSearch)
            dialog.toySearchBox.isSyncingText = false
        end
        dialog.sectionInfo:SetText(L["AH_PICK_MOUNT"] or "Pick a Mount for this slot")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        -- Shared, SavedVariables-backed mount list (same source as OxedRing).
        -- Built once; rebuilt only when the player presses Refresh Mounts.
        local items = OxedHub.Mounts and OxedHub.Mounts:GetMounts() or {}

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

        if dialog.mountCountLabel then
            local labelText = L["Mounts: "] .. totalMounts
            if filterText ~= "" then
                labelText = L["Found: "] .. #items .. " / " .. totalMounts
            end
            dialog.mountCountLabel:SetText(labelText)
            dialog.mountCountLabel:Show()
        end

        -- Grid layout matching the OxedRing mount picker (icon-only, no name labels)
        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
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
                GameTooltip:AddLine(L["|cff00ff00Click to assign to this slot|r"])
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "mount"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = nil
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "mount", id = item.id, label = item.name, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = nil
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 16)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "item" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["RING_PICK_BAG_ITEM"] or "Pick a Potion, Flask, or Food from your bags")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        -- Scan player bags for consumable items (Potions, Flasks, Food)
        local items = {}
        local seenIDs = {}
        for bag = 0, 4 do
            local numSlots = C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
            for slot = 1, numSlots do
                local info = C_Container and C_Container.GetContainerItemInfo(bag, slot) or nil
                local itemID = info and info.itemID or nil
                if not itemID and not C_Container then
                    itemID = GetContainerItemID(bag, slot)
                end
                if itemID and not seenIDs[itemID] then
                    seenIDs[itemID] = true
                    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                    local itemName, itemType, itemSubType, itemIcon
                    if getItemInfo then
                        local n, _, _, _, _, t, st, _, _, ic = getItemInfo(itemID)
                        itemName, itemType, itemSubType, itemIcon = n, t, st, ic
                    end
                    if itemType == "Consumable" then
                        local cat = itemSubType or "Other"
                        local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
                        local count = (getItemCount and getItemCount(itemID)) or 0
                        table.insert(items, {
                            type = "item",
                            id = itemID,
                            name = itemName or (L["Item #"] .. itemID),
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

        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -(y * (btnSize + spacing)) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
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
                self:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "item"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = "direct"
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then
                    ActionHub:RefreshWidget()
                end
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "item", id = item.id, label = item.name, icon = item.icon, assignmentMode = "direct" }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = "direct"
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "spell" then
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["RING_PICK_SPELL"] or "Pick a spell from your spellbook")

        for _, c in ipairs({child:GetChildren()}) do
            c:Hide(); c:SetParent(nil)
        end

        -- Reuse the shared spellbook scanner (OxedRing built it first).
        local items = {}
        if OxedHub.OxedRingEditor and OxedHub.OxedRingEditor.GetPlayerSpellList then
            items = OxedHub.OxedRingEditor:GetPlayerSpellList() or {}
        end

        local btnSize = 42
        local spacing = 2
        local cols = 5
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 12, -(y * (btnSize + spacing)) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 8,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if item.id then GameTooltip:SetSpellByID(item.id) else GameTooltip:SetText(item.name) end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "spell"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].label = item.name
                    slots[dialog.slotIndex].icon = item.icon
                    slots[dialog.slotIndex].assignmentMode = nil
                    slots[dialog.slotIndex].requiresParty = nil
                    slots[dialog.slotIndex].requiresTarget = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
                if ActionHub.RefreshWidget then ActionHub:RefreshWidget() end
            end)

            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "spell", id = item.id, label = item.name, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.label = ActionHub.dragData.label
                            s.icon = ActionHub.dragData.icon
                            s.assignmentMode = nil
                            s.requiresParty = nil
                            s.requiresTarget = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "trigger" then
        -- Show Trigger Grid
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.toySearchBox:Hide()
        dialog.allTriggersCheck:Show()
        dialog.allTriggersLabel:Show()
        dialog.allTriggersHelp:Show()
        dialog.sectionInfo:SetText(L["AH_PICK_TRIGGER"] or "Pick a Trigger for this slot")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local items = {}
        local triggers = OxedHub.db.profile.triggers or {}
        local filter = OxedHub.db.profile.settings.filterByClass
        local showAll = dialog.showAllTriggers

        for id, trg in pairs(triggers) do
            -- By default only show Spell Cast triggers; show all types when checkbox is checked
            if showAll or trg.event == "UNIT_SPELLCAST_SUCCEEDED" then
                local show = true
                if filter and trg.conditions and trg.conditions.spellID then
                    if not OxedHub:IsSpellRelevant(trg.conditions.spellID) then
                        show = false
                    end
                end

                if show then
                    local spellInfo = trg.conditions and trg.conditions.spellID and C_Spell.GetSpellInfo(trg.conditions.spellID)
                    local icon = (OxedHub.Triggers and OxedHub.Triggers.GetTriggerDisplayIcon and OxedHub.Triggers:GetTriggerDisplayIcon(trg))
                        or (spellInfo and spellInfo.iconID)
                        or "Interface\\Icons\\INV_Misc_QuestionMark"
                    local name = trg.name or (spellInfo and spellInfo.name) or id
                    table.insert(items, { type = "trigger", id = id, name = name, icon = icon })
                end
            end
        end

        table.sort(items, function(a, b) return a.name < b.name end)

        local btnSize = 48
        local spacing = 8
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -y * (btnSize + spacing + 18) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12)
            label:SetTextColor(0.90, 0.85, 0.80, 1)

            btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
            btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "trigger"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].assignmentMode = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "trigger", id = item.id, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            local isOver = false
                            if rb and rb.IsMouseOver then
                                isOver = rb:IsMouseOver()
                            elseif rb and type(_G.MouseIsOver) == "function" then
                                isOver = _G.MouseIsOver(rb)
                            end
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and isOver then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.assignmentMode = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 20) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "module" then
        -- Show Trigger Grid
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.toySearchBox:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.sectionInfo:SetText(L["Pick a module window or setting for this slot"])

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        -- Every module's windows, settings and on / off switch. See
        -- ActionHub:GetModuleNodeChoices in ActionHubData.lua.
        local items = {}
        for _, choice in ipairs(ActionHub:GetModuleNodeChoices()) do
            table.insert(items, { type = "module", id = choice.id, name = choice.action,
                moduleName = choice.name, icon = choice.icon })
        end

        local btnSize = 48
        local spacing = 8
        local cols = 4
        local x, y = 0, 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
            btn:SetSize(btnSize, btnSize)
            btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -y * (btnSize + spacing + 18) - 4)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
            })
            btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 6, btnSize - 6)
            iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
            iconTex:SetTexture(item.icon)
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
            label:SetText(item.name)
            label:SetWidth(btnSize + 4)
            label:SetJustifyH("CENTER")
            label:SetHeight(12)
            label:SetTextColor(0.90, 0.85, 0.80, 1)

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(1, 0.82, 0, 0.8)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(item.moduleName or "", 1, 0.82, 0)
                GameTooltip:AddLine(item.name, 1, 1, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
                GameTooltip:Hide()
            end)

            btn:SetScript("OnClick", function()
                local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                if slots[dialog.slotIndex] then
                    slots[dialog.slotIndex].type = "module"
                    slots[dialog.slotIndex].id = item.id
                    slots[dialog.slotIndex].assignmentMode = nil
                end
                ActionHub:RefreshTab()
                ActionHub:RefreshPickerList()
            end)

            -- Drag support
            btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function(self)
                ActionHub.dragData = { type = "module", id = item.id, icon = item.icon }
                if not ActionHub.dragIcon then
                    local f = CreateFrame("Frame", nil, UIParent)
                    f:SetSize(32, 32)
                    f:SetFrameStrata("TOOLTIP")
                    local t = f:CreateTexture(nil, "OVERLAY")
                    t:SetAllPoints()
                    f.tex = t
                    ActionHub.dragIcon = f
                end
                ActionHub.dragIcon.tex:SetTexture(item.icon)
                ActionHub.dragIcon:Show()
                ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                    local cx, cy = GetCursorPosition()
                    local s = UIParent:GetEffectiveScale()
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                end)
            end)
            btn:SetScript("OnDragStop", function(self)
                if ActionHub.dragIcon then
                    ActionHub.dragIcon:Hide()
                    ActionHub.dragIcon:SetScript("OnUpdate", nil)
                end
                if ActionHub.dragData then
                    local dropTarget = nil
                    local tab = ActionHub.tab
                    if tab and tab.ringButtons then
                        for _, rb in ipairs(tab.ringButtons) do
                            local isOver = false
                            if rb and rb.IsMouseOver then
                                isOver = rb:IsMouseOver()
                            elseif rb and type(_G.MouseIsOver) == "function" then
                                isOver = _G.MouseIsOver(rb)
                            end
                            if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and isOver then
                                dropTarget = rb
                                break
                            end
                        end
                    end
                    if dropTarget then
                        local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide)
                        local s = slots[dropTarget.slotIndex]
                        if s then
                            s.type = ActionHub.dragData.type
                            s.id = ActionHub.dragData.id
                            s.assignmentMode = nil
                        end
                        ActionHub:RefreshTab()
                        ActionHub:RefreshWidget()
                    end
                    ActionHub.dragData = nil
                end
                ClearCursor()
            end)

            x = x + 1
            if x >= cols then x = 0 y = y + 1 end
        end

        local rows = math.max(math.ceil(#items / cols), 1)
        child:SetHeight(rows * (btnSize + spacing + 20) + 20)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "marker" then
        -- Show Marker Grid (Raid Targets + Flares + Pings)
        dialog.scroll:Show()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Hide()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_PICK_RAID_TARGET"] or "Pick a Raid Target, Flare, or Ping")

        -- Clear previous entries
        for _, c in ipairs({child:GetChildren()}) do
            c:Hide()
            c:SetParent(nil)
        end

        local categories = {
            {
                name = L["Marks"],
                items = {
                    { type = "marker", id = 1, name = L["Target: Star"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "marker", id = 2, name = L["Target: Circle"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "marker", id = 3, name = L["Target: Diamond"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "marker", id = 4, name = L["Target: Triangle"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "marker", id = 5, name = L["Target: Moon"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "marker", id = 6, name = L["Target: Square"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "marker", id = 7, name = L["Target: Cross"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "marker", id = 8, name = L["Target: Skull"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "marker", id = 0, name = L["Clear Target"], icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = L["Flares"],
                items = {
                    { type = "targetmarker", id = 6, name = L["Flare: Blue"],   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
                    { type = "targetmarker", id = 4, name = L["Flare: Green"],  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
                    { type = "targetmarker", id = 3, name = L["Flare: Purple"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
                    { type = "targetmarker", id = 7, name = L["Flare: Red"],    icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
                    { type = "targetmarker", id = 1, name = L["Flare: Yellow"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
                    { type = "targetmarker", id = 2, name = L["Flare: Orange"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
                    { type = "targetmarker", id = 5, name = L["Flare: Silver"], icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
                    { type = "targetmarker", id = 8, name = L["Flare: White"],  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
                    { type = "targetmarker", id = 0, name = L["Clear Flares"],  icon = "Interface\\Icons\\Spell_ChargeNegative" },
                }
            },
            {
                name = L["Pings"],
                items = {
                    { type = "ping", id = "", name = L["Ping"], icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-main-icon.png" },
                    { type = "ping", id = "attack", name = L["Ping: Attack"], icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Attack-Icon.png" },
                    { type = "ping", id = "assist", name = L["Ping: Assist"], icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Assist-Icon.png" },
                    { type = "ping", id = "onmyway", name = L["Ping: On My Way"], icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-OnMyWay-Icon.png" },
                    { type = "ping", id = "warning", name = L["Ping: Warning"], icon = "Interface\\AddOns\\OxedHub\\Media\\Textures\\Buttons\\Ping-Warning-Icon.png" },
                }
            }
        }

        if not dialog.markerHeaders then
            dialog.markerHeaders = {}
            for _, cat in ipairs(categories) do
                local header = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                header:SetText(cat.name)
                header:SetTextColor(1, 0.82, 0)
                table.insert(dialog.markerHeaders, header)
            end
        end
        for _, h in ipairs(dialog.markerHeaders) do
            h:Hide()
        end

        local btnSize = 44
        local spacing = 6
        local cols = 4
        local currentY = 8

        for catIdx, cat in ipairs(categories) do
            local header = dialog.markerHeaders[catIdx]
            header:SetPoint("TOPLEFT", child, "TOPLEFT", 12, -currentY)
            header:Show()

            currentY = currentY + 18

            local x, y = 0, 0
            for i, item in ipairs(cat.items) do
                local btn = CreateFrame("Button", nil, child, "BackdropTemplate")
                btn:SetSize(btnSize, btnSize)
                btn:SetPoint("TOPLEFT", child, "TOPLEFT", x * (btnSize + spacing) + 8, -currentY - y * (btnSize + spacing + 18))
                btn:SetBackdrop({
                    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 10,
                })
                btn:SetBackdropColor(0.2, 0.1, 0.05, 0.8)
                btn:SetBackdropBorderColor(0.4, 0.25, 0.1, 1)

                local iconTex = btn:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(btnSize - 6, btnSize - 6)
                iconTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
                iconTex:SetTexture(item.icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("TOP", btn, "BOTTOM", 0, -2)
                label:SetText(item.name)
                label:SetWidth(btnSize + 4)
                label:SetJustifyH("CENTER")
                label:SetHeight(12)
                label:SetTextColor(0.90, 0.85, 0.80, 1)

                btn:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 0.82, 0, 0.8) end)
                btn:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8) end)

                btn:SetScript("OnClick", function()
                    local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dialog.slotSide)
                    if slots[dialog.slotIndex] then
                        slots[dialog.slotIndex].type = item.type
                        slots[dialog.slotIndex].id = item.id
                        slots[dialog.slotIndex].assignmentMode = nil
                    end
                    ActionHub:RefreshTab()
                    ActionHub:RefreshPickerList()
                end)

                -- Drag support
                btn:RegisterForDrag("LeftButton")
                btn:SetScript("OnDragStart", function(self)
                    ActionHub.dragData = { type = item.type, id = item.id, icon = item.icon }
                    if not ActionHub.dragIcon then
                        local f = CreateFrame("Frame", nil, UIParent)
                        f:SetSize(32, 32)
                        f:SetFrameStrata("TOOLTIP")
                        local t = f:CreateTexture(nil, "OVERLAY")
                        t:SetAllPoints()
                        f.tex = t
                        ActionHub.dragIcon = f
                    end
                    ActionHub.dragIcon.tex:SetTexture(item.icon)
                    ActionHub.dragIcon:Show()
                    ActionHub.dragIcon:SetScript("OnUpdate", function(self)
                        local cx, cy = GetCursorPosition()
                        local s = UIParent:GetEffectiveScale()
                        self:ClearAllPoints()
                        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx/s, cy/s)
                    end)
                end)
                btn:SetScript("OnDragStop", function(self)
                    if ActionHub.dragIcon then
                        ActionHub.dragIcon:Hide()
                        ActionHub.dragIcon:SetScript("OnUpdate", nil)
                    end
                    if ActionHub.dragData then
                        local dropTarget = nil
                        local tab = ActionHub.tab
                        if tab and tab.ringButtons then
                            for _, rb in ipairs(tab.ringButtons) do
                                if rb and rb:IsShown() and rb.isActionHubSlot and rb.slotIndex and MouseIsOver(rb) then
                                    dropTarget = rb
                                    break
                                end
                            end
                        end
                        if dropTarget then
                            local slots = ActionHub:GetSlotsForSide(ActionHub:GetActiveHubDB(), dropTarget.slotSide or dialog.slotSide)
                            if slots[dropTarget.slotIndex] then
                                slots[dropTarget.slotIndex].type = ActionHub.dragData.type
                                slots[dropTarget.slotIndex].id = ActionHub.dragData.id
                                slots[dropTarget.slotIndex].assignmentMode = nil
                            end
                            ActionHub:RefreshTab()
                            ActionHub:RefreshPickerList()
                        end
                        ActionHub.dragData = nil
                    end
                end)

                x = x + 1
                if x >= cols then
                    x = 0
                    y = y + 1
                end
            end

            local numRows = math.max(math.ceil(#cat.items / cols), 1)
            currentY = currentY + numRows * (btnSize + spacing + 18) + 12
        end

        child:SetHeight(currentY + 10)
        child:SetWidth(cols * (btnSize + spacing))
    elseif dialog.selectedType == "settings" then
        dialog.scroll:Hide()
        dialog.editor:Hide()
        dialog.settingsTabFrame:Show()
        dialog.showToysCheck:Hide()
        dialog.showToysLabel:Hide()
        dialog.allTriggersCheck:Hide()
        dialog.allTriggersLabel:Hide()
        dialog.allTriggersHelp:Hide()
        dialog.toySearchBox:Hide()
        dialog.sectionInfo:SetText(L["AH_CONFIGURE_SETTINGS"] or "Configure settings for this slot")
        dialog.moveNodeMode = dialog.moveNodeMode == true

        local size = (currentSlot and currentSlot.nodeSize) or ActionHub:GetActiveHubDB().globalNodeSize or 44
        dialog.sizeSlider.isResetting = true
        dialog.sizeSlider:SetValue(size)
        dialog.sizeSlider.isResetting = false
        dialog.sizeVal:SetText(tostring(size))
        dialog.sizeInput:SetText(tostring(size))

        local gSize = ActionHub:GetActiveHubDB().globalNodeSize or 44
        dialog.globalSizeSlider.isResetting = true
        dialog.globalSizeSlider:SetValue(gSize)
        dialog.globalSizeSlider.isResetting = false
        dialog.globalSizeVal:SetText(tostring(gSize))
        dialog.globalSizeInput:SetText(tostring(gSize))

        local lSize = ActionHub:GetActiveHubDB().nodeLineSize or 48
        dialog.lineSizeSlider.isResetting = true
        dialog.lineSizeSlider:SetValue(lSize)
        dialog.lineSizeSlider.isResetting = false
        dialog.lineSizeVal:SetText(tostring(lSize))
        dialog.lineSizeInput:SetText(tostring(lSize))

        local posX = (currentSlot and currentSlot.nodePositionX) or 0
        dialog.posXSlider.isResetting = true
        dialog.posXSlider:SetValue(posX)
        dialog.posXSlider.isResetting = false
        dialog.posXVal:SetText(tostring(posX))
        dialog.posXInput:SetText(tostring(posX))

        local posY = (currentSlot and currentSlot.nodePositionY) or 0
        dialog.posYSlider.isResetting = true
        dialog.posYSlider:SetValue(posY)
        dialog.posYSlider.isResetting = false
        dialog.posYVal:SetText(tostring(posY))
        dialog.posYInput:SetText(tostring(posY))

        local tSize = ActionHub:GetActiveHubDB().cooldownTextSize or 11
        if dialog.textSizeSlider then
            dialog.textSizeSlider.isResetting = true
            dialog.textSizeSlider:SetValue(tSize)
            dialog.textSizeSlider.isResetting = false
            dialog.textSizeVal:SetText(tostring(tSize))
            dialog.textSizeInput:SetText(tostring(tSize))
        end

        if dialog.bgAlphaSlider then
            local a = ActionHub:GetActiveHubDB().nodeBackgroundAlpha
            if a == nil then a = 0.5 end
            local pct = math.floor(a * 100 + 0.5)
            dialog.bgAlphaSlider.isSyncing = true
            dialog.bgAlphaSlider:SetValue(pct)
            dialog.bgAlphaSlider.isSyncing = false
            dialog.bgAlphaVal:SetText(pct .. "%")
            if dialog.bgAlphaInput then dialog.bgAlphaInput:SetText(tostring(pct)) end
        end

        local bindingText = (currentSlot and currentSlot.binding) or L["KEYBIND_NOT_BOUND"] or L["Not Bound"]
        dialog.bindBtn:SetText(bindingText)

        -- Keep the custom-icon preview in step with the slot being edited.
        if dialog.RefreshCustomIcon then dialog:RefreshCustomIcon() end

        if dialog.allowAnimCheck then
            local allowAnim = ActionHub:GetActiveHubDB().allowAnimations
            if allowAnim == nil then allowAnim = true end
            dialog.allowAnimCheck:SetChecked(allowAnim)
        end
        
        if dialog.readyGlowCheck then
            dialog.readyGlowCheck:SetChecked(currentSlot and currentSlot.showReadyGlow == true)
        end
        if dialog.readyGlowHexInput then
            local hex = (currentSlot and currentSlot.readyGlowHex) or "FFFF00"
            dialog.readyGlowHexInput:SetText(hex)
            -- The OnTextChanged script will update the color preview
        end
        if dialog.readyGlowSizeSlider then
            dialog.readyGlowSizeSlider.isSyncing = true
            local size = (currentSlot and currentSlot.readyGlowSize) or 100
            dialog.readyGlowSizeSlider:SetValue(size)
            if dialog.readyGlowSizeVal then dialog.readyGlowSizeVal:SetText(size .. "%") end
            dialog.readyGlowSizeSlider.isSyncing = false
        end
        if dialog.readyGlowAlphaSlider then
            dialog.readyGlowAlphaSlider.isSyncing = true
            local alpha = (currentSlot and currentSlot.readyGlowAlpha) or 100
            dialog.readyGlowAlphaSlider:SetValue(alpha)
            if dialog.readyGlowAlphaVal then dialog.readyGlowAlphaVal:SetText(alpha .. "%") end
            dialog.readyGlowAlphaSlider.isSyncing = false
        end

        if dialog.showTooltipCheck then
            local showTT = ActionHub:GetActiveHubDB().showTooltip
            if showTT == nil then showTT = true end
            dialog.showTooltipCheck:SetChecked(showTT)
        end

        if dialog.tabCheckboxes then
            local activeDB = ActionHub:GetActiveHubDB()
            local visibleTabs = activeDB.visibleTabs or {
                toy = true,
                emote = true,
                trigger = true,
                marker = true,
                mount = false,
                item = false,
                settings = true,
            }
            for key, check in pairs(dialog.tabCheckboxes) do
                local val = visibleTabs[key]
                if val == nil then
                    if key == "mount" or key == "item" or key == "spell" then
                        val = false
                    else
                        val = true
                    end
                end
                check:SetChecked(val)
            end
        end
    end
    if OxedHub.UI and OxedHub.UI.ApplyGlobalTextSize then
        OxedHub.UI:ApplyGlobalTextSize()
    end
end
