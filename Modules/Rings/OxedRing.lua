local addonName, OxedHub = ...
local OxedRing = {}
OxedHub.OxedRing = OxedRing

-- Local references
local CreateFrame = CreateFrame
local UIParent = UIParent
local GetCursorPosition = GetCursorPosition
local math_atan2 = math.atan2
local math_cos = math.cos
local math_sin = math.sin
local math_pi = math.pi
local math_floor = math.floor
local table = table
local ipairs = ipairs
local pairs = pairs
local tostring = tostring

local RING_RADIUS = 150
local CENTER_SIZE = 64
local DEADZONE_RADIUS = 15
local CENTER_RING_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\ring"

-- State
local isRingOpen = false
local activeSliceIndex = nil
local slices = {}
local sliceData = {} -- Array of items to show

-- ── Node Availability Conditions ────────────────────────────────────
-- Markers (Flares) require being in a party; Target markers require
-- having a target.  When conditions are not met the slice is visually
-- grayed out and cannot be activated.
local function IsNodeAvailable(data)
    if not data then return false end

    -- Mounts cannot be summoned in combat
    if data.type == "mount" then
        if UnitAffectingCombat("player") then
            return false
        end
        -- Check if mount is usable by this class/race
        if data.id and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local name, spellID, icon, isActive, isUsable = C_MountJournal.GetMountInfoByID(data.id)
            if not isUsable then
                return false
            end
        end
    end

    -- World Markers (Flares) require party/raid
    if data.requiresParty then
        if not (IsInGroup() or IsInRaid()) then
            return false
        end
    end

    -- Target markers require a target
    if data.requiresTarget then
        if not UnitExists("target") then
            return false
        end
    end

    return true
end

-- Check if a slice index is currently available
local function IsSliceAvailable(index)
    local data = sliceData[index]
    return IsNodeAvailable(data)
end

local function GetRingStyle()
    return OxedHub.db.profile.oxedRingStyle or "ring"
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

            -- Dark inner fill
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
        if btn.highlight then
            btn.highlight:AddMaskTexture(btn.ringMask)
        end
        
        if btn.cooldown then
            if btn.cooldown.SetUseCircularEdge then
                btn.cooldown:SetUseCircularEdge(true)
            end
            btn.cooldown:SetSwipeTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end

        btn.ringBg:SetSize(size, size)
        btn.ringFill:SetSize(size - 2, size - 2)
        btn.ringBg:Show()
        btn.ringFill:Show()
        
        local isSelected = not isPreview and activeSliceIndex == btn.sliceIndex
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
        
        local isSelected = not isPreview and activeSliceIndex == btn.sliceIndex
        if isSelected then
            btn:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
        end

        if btn.ringBg then btn.ringBg:Hide() end
        if btn.ringFill then btn.ringFill:Hide() end
        if btn.ringMask then 
            btn.icon:RemoveMaskTexture(btn.ringMask) 
            if btn.highlight then
                btn.highlight:RemoveMaskTexture(btn.ringMask)
            end
        end
        
        if btn.cooldown then
            if btn.cooldown.SetUseCircularEdge then
                btn.cooldown:SetUseCircularEdge(false)
            end
            -- Revert to default square sweep
            btn.cooldown:SetSwipeTexture("Interface\\BUTTONS\\WHITE8X8")
        end
    end
end

function OxedRing:Init()
    -- Initialize default array if empty
    if not OxedHub.db.profile.oxedRingNodes then
        OxedHub.db.profile.oxedRingNodes = {}
        for i, emotion in ipairs(OxedHub.CONFIG.EMOTIONS) do
            table.insert(OxedHub.db.profile.oxedRingNodes, {
                label = emotion,
                icon = "Interface\\Icons\\INV_Misc_QuestionMark",
                id = emotion
            })
        end
    end

    self:CreateRingFrame()

    -- Apply saved keybind on startup (from our own DB, not WoW's binding system)
    local savedBinding = OxedHub.db.profile.oxedRingBinding
    if savedBinding and savedBinding ~= "" then
        self:ApplyRingBinding(savedBinding)
    end

    -- Re-apply binding after entering world as a safety net
    local bindFrame = CreateFrame("Frame")
    bindFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bindFrame:SetScript("OnEvent", function()
        local key = OxedHub.db.profile.oxedRingBinding
        if key and key ~= "" and OxedRing.hotkeyBtn then
            ClearOverrideBindings(OxedRing.hotkeyBtn)
            SetOverrideBindingClick(OxedRing.hotkeyBtn, true, key, "OxedRingHotkeyButton")
        end
    end)
    
    -- Setup a simple slash command to test the ring
    SLASH_OXEDRING1 = "/oxedring"
    SlashCmdList["OXEDRING"] = function(msg)
        if isRingOpen then
            OxedRing:HideRing()
        else
            OxedRing:ShowRing()
        end
    end
    
    -- Pre-bake attributes
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function()
        OxedRing:UpdateSecureAttributes()
    end)
    self:UpdateSecureAttributes()
end

function OxedRing:UpdateSecureAttributes()
    if InCombatLockdown() or not OxedRing.hotkeyBtn then return end
    
    -- Filter out empty nodes so the ring perfectly wraps around the active elements
    sliceData = {}
    for _, data in ipairs(OxedHub.db.profile.oxedRingNodes or {}) do
        if data.type then
            -- Auto-migrate: set condition flags on marker/targetmarker nodes
            -- that were created before the condition system existed
            if data.type == "marker" and data.requiresParty == nil then
                data.requiresParty = true
            end
            if data.type == "targetmarker" and data.requiresTarget == nil then
                data.requiresTarget = true
            end
            table.insert(sliceData, data)
        end
    end

    local numSlices = #sliceData
    OxedRing.hotkeyBtn:SetAttribute("numSlices", numSlices)
    OxedRing.hotkeyBtn:SetAttribute("deadzone", DEADZONE_RADIUS)
    
    for i, data in ipairs(sliceData) do
        OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_type", data.type)
        if data.type == "marker" or data.type == "targetmarker" or data.type == "ping" or (data.type == "toy" and data.assignmentMode == "direct") or (data.type == "item" and data.assignmentMode == "direct") or data.type == "mount" then
            OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_id", data.id)
            OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_macro", nil)
        elseif data.type == "emote" then
            local mapping = OxedHub.db.profile.customReactions and OxedHub.db.profile.customReactions[data.id]
            if mapping and mapping.emote then
                OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_id", data.id)
                OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_macro", "/" .. string.lower(mapping.emote))
            else
                OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_id", nil)
                OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_macro", nil)
            end
        else
            OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_id", nil)
            OxedRing.hotkeyBtn:SetAttribute("slice" .. i .. "_macro", nil)
        end
    end
end

function OxedRing:CreateRingFrame()
    -- The secure hotkey button (SetFrameRef / WrapScript below) cannot be set up
    -- during combat — those are protected. If we're logging in / reloading mid
    -- combat, defer the whole build until combat ends.
    if InCombatLockdown() then
        if not self._deferCreateFrame then
            self._deferCreateFrame = CreateFrame("Frame")
            self._deferCreateFrame:SetScript("OnEvent", function(f)
                f:UnregisterEvent("PLAYER_REGEN_ENABLED")
                if not OxedRing.frame then
                    OxedRing:CreateRingFrame()
                    local key = OxedHub.db.profile.oxedRingBinding
                    if key and key ~= "" and OxedRing.hotkeyBtn then
                        OxedRing:ApplyRingBinding(key)
                    end
                end
            end)
        end
        self._deferCreateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    -- Main transparent frame covering the screen to capture events and mouse
    self.frame = CreateFrame("Frame", "OxedRingMainFrame", UIParent)
    self.frame:SetAllPoints(UIParent)
    self.frame:SetFrameStrata("FULLSCREEN_DIALOG")
    self.frame:SetFrameLevel(100)

    -- Hotkey Button: Must use SecureActionButtonTemplate for AnyUp/AnyDown
    -- to correctly pass the "down" parameter in OnClick.
    -- We use SetOverrideBindingClick to route a keybind to this button.
    -- The binding is persisted in our own SavedVariables (oxedRingBinding)
    -- and re-applied on every login/reload in Init().
    local hotkeyBtn = CreateFrame("Button", "OxedRingHotkeyButton", UIParent, "SecureFrameTemplate,SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    hotkeyBtn:SetAllPoints(UIParent)
    hotkeyBtn:SetAlpha(0)
    hotkeyBtn:EnableMouse(false) -- prevent accidental mouse clicks on the invisible button
    hotkeyBtn:RegisterForClicks("AnyUp", "AnyDown")
    hotkeyBtn:SetFrameRef("UIParent", UIParent)
    hotkeyBtn:SetAttribute("pressAndHoldAction", 1)
    
    hotkeyBtn:WrapScript(hotkeyBtn, "OnClick", [[
        local ui = self:GetFrameRef("UIParent")
        if down then
            -- Trigger insecure visual ring open immediately
            self:CallMethod("ShowRing")
            
            -- Save the exact coordinates where the ring was opened
            local x, y = ui:GetMousePosition()
            if x and y then
                local w, h = ui:GetWidth(), ui:GetHeight()
                self:SetAttribute("startX", x * w)
                self:SetAttribute("startY", y * h)
            end
            
            -- Wipe previous payload immediately on down
            self:SetAttribute("type", nil)
            self:SetAttribute("typerelease", nil)
            self:SetAttribute("macrotext", nil)
            
            -- Prevent SecureActionButton_OnClick from running on DOWN
            -- This preserves the click chain for the UP event!
            return false
        else
            -- Key released! Calculate angle and radius securely
            local startX = self:GetAttribute("startX")
            local startY = self:GetAttribute("startY")
            if not startX or not startY then 
                self:CallMethod("HideRing")
                return false 
            end
            
            local x, y = ui:GetMousePosition()
            if not x or not y then 
                self:CallMethod("HideRing")
                return false 
            end
            
            local w, h = ui:GetWidth(), ui:GetHeight()
            x = x * w
            y = y * h
            
            local dx = x - startX
            local dy = y - startY
            local dist = math.sqrt(dx*dx + dy*dy)
            
            local deadzone = self:GetAttribute("deadzone") or 30
            if dist < deadzone then
                -- Released in the center. ONLY ping if the player armed a ping
                -- TYPE by hovering a ping petal first; a plain open+close
                -- without moving should just close (no ping).
                self:CallMethod("HideRing")
                local pingMacro = self:GetAttribute("armedPingMacro")
                if pingMacro and pingMacro ~= "" then
                    self:SetAttribute("type", "macro")
                    self:SetAttribute("typerelease", "macro")
                    self:SetAttribute("macrotext", pingMacro)
                    return
                end
                return false
            end
            
            local numSlices = self:GetAttribute("numSlices") or 0
            if numSlices == 0 then 
                self:CallMethod("HideRing")
                return false 
            end
            
            local angle = math.atan2(dy, dx)
            local angleDeg = math.deg(angle)
            if angleDeg < 0 then angleDeg = angleDeg + 360 end

            local angleStep = 360 / numSlices
            local startAngle = 90

            local relativeAngle = startAngle - angleDeg
            if relativeAngle < 0 then relativeAngle = relativeAngle + 360 end
            if relativeAngle >= 360 then relativeAngle = relativeAngle - 360 end

            local index = math.floor((relativeAngle + angleStep / 2) / angleStep) % numSlices + 1
            
            local sType = self:GetAttribute("slice" .. index .. "_type")
            local sId = self:GetAttribute("slice" .. index .. "_id")
            local sMacro = self:GetAttribute("slice" .. index .. "_macro")

            -- Trigger insecure visual ring close and activate sound/message
            self:CallMethod("HideRing", true, index, true)
            
            if sType == "marker" then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                if sId == 0 then
                    self:SetAttribute("macrotext", "/cwm all")
                else
                    self:SetAttribute("macrotext", "/wm " .. sId)
                end
            elseif sType == "targetmarker" then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                if sId == 0 then
                    self:SetAttribute("macrotext", "/tm 0")
                else
                    self:SetAttribute("macrotext", "/tm " .. sId)
                end
            elseif sType == "ping" then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                if sId == "" then
                    self:SetAttribute("macrotext", "/ping")
                else
                    self:SetAttribute("macrotext", "/ping " .. sId)
                end
            elseif sType == "toy" and sId then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                self:SetAttribute("macrotext", "/use item:" .. sId)
            elseif sType == "item" and sId then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                self:SetAttribute("macrotext", "/use item:" .. sId)
            elseif sType == "emote" and sMacro then
                self:SetAttribute("type", "macro")
                self:SetAttribute("typerelease", "macro")
                self:SetAttribute("macrotext", sMacro)
            elseif sType == "mount" then
                -- Mounts are handled insecurely in HideRing via C_MountJournal.SummonByID
                return false
            else
                -- If it's a trigger or unhandled, we handle it insecurely in HideRing, so cancel secure execution
                return false
            end
        end
    ]])
    
    -- Expose ShowRing and HideRing to the secure environment via CallMethod
    hotkeyBtn.ShowRing = function(self)
        -- Prevent OS keyboard auto-repeat from rapidly toggling the ring
        if OxedRing.isHotkeyDown then return end
        OxedRing.isHotkeyDown = true
        
        if not isRingOpen then
            OxedRing:ShowRing()
        else
            OxedRing:HideRing(true)
        end
    end
    
    hotkeyBtn.HideRing = function(self, doActivate, index)
        OxedRing.isHotkeyDown = false
        if isRingOpen then
            -- We inject the calculated index directly to the insecure side
            if index then
                activeSliceIndex = index
            end
            -- Block insecure activation when node conditions are not met
            if doActivate and index and not IsSliceAvailable(index) then
                OxedRing:HideRing(false)
                return
            end
            OxedRing:HideRing(doActivate)
        end
    end
    OxedRing.hotkeyBtn = hotkeyBtn
    
    -- Center visual hub
    self.centerHub = CreateFrame("Frame", nil, self.frame)
    self.centerHub:SetSize(CENTER_SIZE, CENTER_SIZE)
    self.centerHub:SetPoint("CENTER", self.frame, "CENTER", 0, 0)
    

    self.animTex = self.frame:CreateTexture(nil, "OVERLAY")
    self.animTex:SetSize(497, 497)  -- 30% smaller (originally 710x710), 1:1 aspect ratio
    self.animTex:SetPoint("CENTER", self.centerHub, "CENTER", 0, 0)
    self.animTex:Hide()
    self.animTex:SetAlpha(0.5)
    self.animFrame = 1
    self.lastAnimFrame = 0  -- 0 so first frame always triggers swap

    -- Permanent off-screen preload: keeps all 32 PNGs in VRAM.
    -- Alpha 0.001 (not 0) forces WoW to keep textures GPU-resident.
    local preload = CreateFrame("Frame", nil, UIParent)
    preload:SetSize(1, 1)
    preload:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -1000, 1000)
    preload:SetAlpha(0.001)
    preload:Show()
    for i = 1, 18 do
        local t = preload:CreateTexture(nil, "OVERLAY")
        t:SetSize(1, 1)
        t:SetAllPoints(preload)
        t:SetTexture(string.format(
            "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_%05d.png", i))
        t:Show()
    end

    -- Preload all 91 hover explosion frames - DISABLED (hover animation removed)
    --[[
    local preloadSelect = CreateFrame("Frame", nil, UIParent)
    preloadSelect:SetSize(1, 1)
    preloadSelect:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 1000)
    preloadSelect:SetAlpha(0.001)
    preloadSelect:Show()
    for i = 1, 91 do
        local t = preloadSelect:CreateTexture(nil, "OVERLAY")
        t:SetSize(1, 1)
        t:SetAllPoints(preloadSelect)
        t:SetTexture(string.format(
            "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimationSelect\\FootageCrate-Firey_Shockwave_2-%05d.png", i))
        t:Show()
    end
    --]]

    -- Hover explosion texture (1920x1080 source frames, rendered at 50% = 960x540)
    -- Anchored dynamically in PlaySelectAnim to match the active slice position
    self.selectTex = self.frame:CreateTexture(nil, "OVERLAY")
    self.selectTex:SetSize(960, 540)
    self.selectTex:Hide()


    -- Slices will be parented directly to centerHub so they inherit its scale natively

    -- Tracking Loop
    self.frame:SetScript("OnUpdate", function(self, elapsed)
        OxedRing:OnUpdate(elapsed)
    end)
    
    -- Intercept clicks to close the ring
    self.frame:EnableMouse(true)
    self.frame:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" or button == "RightButton" then
            OxedRing:HideRing(true)
        end
    end)

    -- Single OnKeyDown handler for ESCAPE
    self.frame:EnableKeyboard(true)
    if not InCombatLockdown() then
        self.frame:SetPropagateKeyboardInput(true)
    end
    self.frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            OxedRing:HideRing(false)
            return
        end

        -- Not our key, let the game handle it
        if not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- CRITICAL: Hide the frame LAST, after all setup is complete.
    -- Do NOT call RebuildSlices here — slices are built on-demand in ShowRing.
    self.frame:Hide()
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

function OxedRing:RebuildSlices()
    -- Hide old slices
    for _, slice in ipairs(slices) do
        slice:Hide()
    end
    
    self:UpdateSecureAttributes()
    
    local numSlices = #sliceData
    if numSlices == 0 then return end
    local angleStep = (2 * math_pi) / numSlices
    -- Offset by pi/2 so the first slice is at the top
    local startAngle = math_pi / 2
    local style = GetRingStyle()
    
    for i, data in ipairs(sliceData) do
        local slice = slices[i]
        if not slice then
            slice = CreateFrame("Button", "OxedRingSlice"..i, self.centerHub, "BackdropTemplate")

            slice:SetScript("OnEnter", function(self)
                local activeIndex = nil
                for idx, s in ipairs(slices) do
                    if s == self then
                        activeIndex = idx
                        break
                    end
                end
                if activeIndex then
                    OxedRing:SetHoverHighlight(activeIndex)
                end
                -- Tooltip for unavailable nodes
                if self.isUnavailable and self.data then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.data.label or "Node")
                    if self.data.type == "mount" then
                        if UnitAffectingCombat("player") then
                            GameTooltip:AddLine("|cffff0000Cannot summon in combat|r")
                        elseif self.data.id and C_MountJournal and C_MountJournal.GetMountInfoByID then
                            local name, spellID, icon, isActive, isUsable = C_MountJournal.GetMountInfoByID(self.data.id)
                            if not isUsable then
                                GameTooltip:AddLine("|cffff0000Not available for your class|r")
                            end
                        end
                    end
                    if self.data.requiresParty and not (IsInGroup() or IsInRaid()) then
                        GameTooltip:AddLine("|cffff0000Requires Party/Raid|r")
                    end
                    if self.data.requiresTarget and not UnitExists("target") then
                        GameTooltip:AddLine("|cffff0000Requires Target|r")
                    end
                    GameTooltip:Show()
                end
            end)
            
            slice:SetScript("OnLeave", function(self)
                OxedRing:SetHoverHighlight(nil)
                GameTooltip:Hide()
            end)

            -- When the cursor is EXACTLY over this slice button, the button
            -- swallows the mouse-up so the parent frame's OnMouseUp never fires.
            -- Handle it here directly: activate this slice's own index.
            slice:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" or button == "RightButton" then
                    OxedRing:HideRing(true, self.sliceIndex)
                end
            end)
            
            local icon = slice:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 4, -4)
            icon:SetPoint("BOTTOMRIGHT", -4, 4)
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            icon:EnableMouse(false)
            slice.icon = icon

            local highlight = slice:CreateTexture(nil, "HIGHLIGHT")
            highlight:SetAllPoints()
            highlight:SetTexture("Interface\\Buttons\\CheckButtonHilight")
            highlight:SetBlendMode("ADD")
            highlight:Hide()
            highlight:EnableMouse(false)
            slice.highlight = highlight

            local text = slice:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOP", slice, "BOTTOM", 0, -5)
            slice.text = text
            
            local cooldown = CreateFrame("Cooldown", nil, slice, "CooldownFrameTemplate")
            cooldown:SetAllPoints(slice.icon)
            cooldown:SetHideCountdownNumbers(false)
            cooldown:EnableMouse(false)
            slice.cooldown = cooldown
            
            slices[i] = slice
        end
        
        slice.sliceIndex = i
        slice.data = data
        local fontPath, _, fontFlags = slice.text:GetFont()
        local fontSize = OxedHub.db.profile.oxedRingNodeTitleSize or 11
        slice.text:SetFont(OxedHub:GetFont(fontPath), fontSize, fontFlags or "OUTLINE")
        slice.text:SetText(data.label)
        if OxedHub.db.profile.oxedRingShowNodeTitles then
            slice.text:Show()
        else
            slice.text:Hide()
        end
        
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
        elseif data.type == "item" then
            -- Consumable items: resolve icon from item ID
            local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(data.id)
            if not itemIcon then
                if C_Item and C_Item.GetItemIconByID then
                    itemIcon = C_Item.GetItemIconByID(data.id)
                end
                if not itemIcon then
                    local _, _, _, _, instantIcon = GetItemInfoInstant(data.id)
                    itemIcon = instantIcon
                end
            end
            displayIcon = itemIcon or displayIcon
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
        elseif data.type == "targetmarker" then
            if data.id == 0 then
                displayIcon = "Interface\\Icons\\Spell_ChargeNegative"
            else
                displayIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. data.id
            end
        elseif data.type == "marker" then
            if data.id == 0 then
                displayIcon = "Interface\\Icons\\Spell_ChargeNegative"
            else
                displayIcon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. data.id
            end
        end
        slice.icon:SetTexture(displayIcon)

        if (data.type == "marker" or data.type == "targetmarker") and data.id ~= 0 then
            slice.icon:SetTexCoord(0, 1, 0, 1)
        else
            slice.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        -- ── Availability visual (gray out when conditions not met) ────
        local available = IsNodeAvailable(data)
        slice.isUnavailable = not available
        if available then
            slice.icon:SetDesaturated(false)
            slice.icon:SetVertexColor(1, 1, 1, 1)
        else
            slice.icon:SetDesaturated(true)
            slice.icon:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        end

        if slice.cooldown then
            CooldownFrame_Set(slice.cooldown, 0, 0, 0)
            if (data.type == "toy" or data.type == "item") and data.id then
                local startTime, duration, enable = GetItemCooldown(data.id)
                if startTime and duration and duration > 0 then
                    CooldownFrame_Set(slice.cooldown, startTime, duration, enable)
                end
            end
        end

        local size = data.nodeSize or OxedHub.db.profile.oxedRingGlobalNodeSize or 40
        slice:SetSize(size, size)
        StyleButton(slice, style, size, false)
        
        -- Position the slice
        local angle = startAngle - (i - 1) * angleStep
        local radius = OxedHub.db.profile.oxedRingRadius or RING_RADIUS
        local x = math_cos(angle) * radius
        local y = math_sin(angle) * radius
        
        slice.targetX = x
        slice.targetY = y
        
        slice:ClearAllPoints()
        -- We no longer set to final position here, OnUpdate will handle the zoom out
        slice:SetPoint("CENTER", self.centerHub, "CENTER", 0, 0)
        
        -- ONLY show slices when the ring is actually open.
        if isRingOpen then
            slice:Show()
        else
            slice:Hide()
        end
    end
end

function OxedRing:ShowRing()
    if isRingOpen then return end
    isRingOpen = true
    self.isClosing = false
    self.openTime = GetTime()

    -- Reset the armed ping type; hovering a ping petal will arm it again.
    self.armedPingMacro = nil
    if not InCombatLockdown() and self.hotkeyBtn then
        self.hotkeyBtn:SetAttribute("armedPingMacro", nil)
    end
    
    self.frame:EnableMouse(true)
    self.frame:EnableKeyboard(true)
    
    -- Center the ring on the cursor before building slices
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    self.centerHub:ClearAllPoints()
    self.centerHub:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    self.openCursorX = x  -- remember cursor pos so we can detect real movement
    self.openCursorY = y
    
    -- Reset center hub animation state
    self.centerHub:SetScale(1) -- ensure it's unscaled to prevent sliding
    self.centerHub:SetAlpha(0)
    -- Force animation back to frame 1 on every open
    self.animFrame = 1
    self.lastAnimFrame = 0  -- 0 guarantees frame 1 triggers a texture swap immediately
    
    -- Build/refresh slices before showing
    self:RebuildSlices()
    
    activeSliceIndex = nil
    self.cursorMoved = false  -- suppress shockwave until cursor actually moves
    self:UpdateHighlight()
    self.frame:Show()
end

-- Compute which slice the cursor is currently over, using the same angle
-- math as the OnUpdate hover detection. Returns an index (1..numSlices) or nil.
function OxedRing:GetSliceUnderCursor()
    local numSlices = #sliceData
    if numSlices == 0 then return nil end

    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale

    local ringX, ringY = self.centerHub:GetCenter()
    if not ringX then return nil end
    local dx = cx - ringX
    local dy = cy - ringY
    local dist = math.sqrt(dx*dx + dy*dy)
    if dist < DEADZONE_RADIUS then return nil end

    local angle = math_atan2(dy, dx)
    local angleDeg = math.deg(angle)
    if angleDeg < 0 then angleDeg = angleDeg + 360 end

    local angleStep = 360 / numSlices
    local offsetAngle = (90 - angleDeg + (angleStep / 2)) % 360
    if offsetAngle < 0 then offsetAngle = offsetAngle + 360 end

    local hoveredIndex = math_floor(offsetAngle / angleStep) + 1
    if hoveredIndex > numSlices then hoveredIndex = 1 end
    return hoveredIndex
end

function OxedRing:HideRing(doActivate, overrideIndex, isSecureRelease)
    if not isRingOpen then return end
    isRingOpen = false
    -- self.isClosing = true   -- DISABLED: close animation commented out for now
    -- self.closeTime = GetTime()
    self.isClosing = false
    self.animTex:Hide()
    self.frame:Hide()

    self.frame:EnableMouse(false)
    self.frame:EnableKeyboard(false)

    -- Hide all slices explicitly
    for _, slice in ipairs(slices) do
        slice:Hide()
    end

    if not InCombatLockdown() then
        self.frame:SetPropagateKeyboardInput(true)
    end

    local idxToActivate = overrideIndex or activeSliceIndex
    -- Fallback: if activation was requested but no index made it through
    -- (e.g. the cursor was exactly over a slice button, which swallowed the
    -- mouse-up, or the secure index was lost), recompute from the cursor.
    if doActivate and not idxToActivate then
        idxToActivate = self:GetSliceUnderCursor()
    end
    if doActivate and idxToActivate and sliceData[idxToActivate] then
        self:ActivateSlice(idxToActivate, isSecureRelease)
    end
end

function OxedRing:SetHoverHighlight(index)
    -- Block hover on unavailable nodes
    if index and not IsSliceAvailable(index) then
        return
    end
    local prev = activeSliceIndex
    activeSliceIndex = index
    self:UpdateHighlight()
    -- Animation on hover removed per user request
    -- Only play animation on center button click now
end

function OxedRing:PlaySelectAnim()
    -- Anchor the explosion to the currently active slice position
    self.selectTex:ClearAllPoints()
    if activeSliceIndex and slices[activeSliceIndex] and slices[activeSliceIndex]:IsShown() then
        self.selectTex:SetPoint("CENTER", slices[activeSliceIndex], "CENTER", 0, 0)
    else
        -- Fallback: center on the ring hub
        self.selectTex:SetPoint("CENTER", self.centerHub, "CENTER", 0, 0)
    end
    self.selectTex:SetTexture(
        "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimationSelect\\FootageCrate-Firey_Shockwave_2-00001.png")
    self.selectTex:Show()
    self.selectFrame = 1
    self.selectLastFrame = 0
    self.selectPlaying = true
end

function OxedRing:ActivateSlice(index, isSecureRelease)
    local data = sliceData[index]
    if not data then
        return
    end

    -- Block activation if node conditions are not met
    if not IsNodeAvailable(data) then
        local reason = ""
        if data.requiresParty and not (IsInGroup() or IsInRaid()) then
            reason = "Requires party"
        elseif data.requiresTarget and not UnitExists("target") then
            reason = "Requires a target"
        end
        if reason ~= "" then
            print("|cffff0000[OxedHub]|r " .. (data.label or "Node") .. ": " .. reason)
        end
        return
    end

    if data.type == "toy" then
        if data.assignmentMode == "direct" then
            -- Secure release already handled the /use macro; insecure uses SecureCmdOptionParse
            if not isSecureRelease then
                SecureCmdOptionParse("/use item:" .. data.id)
            end
        else
            if OxedHub.Toys and OxedHub.Toys.PlayMix then
                OxedHub.Toys:PlayMix(data.id)
            end
        end
    elseif data.type == "item" then
        -- Consumable items (potions, flasks, food) use /use item:<id>
        if not isSecureRelease then
            SecureCmdOptionParse("/use item:" .. data.id)
        end
    elseif data.type == "mount" then
        -- Summon mount by mount ID
        if data.id and C_MountJournal and C_MountJournal.SummonByID then
            C_MountJournal.SummonByID(data.id)
        end
    elseif data.type == "emote" then
        local mapping = OxedHub.db.profile.customReactions and OxedHub.db.profile.customReactions[data.id]
        if not mapping then return end

        if mapping.sound and OxedHub.Sounds then
            OxedHub.Sounds:Play(mapping.sound)
        end
        if mapping.animation and OxedHub.Animations then
            OxedHub.Animations:Play(mapping.animation, {
                useCustomPosition = mapping.animationUseCustomPosition,
                x = mapping.animationCustomX,
                y = mapping.animationCustomY
            })
        end
        if mapping.emote and OxedHub.Emotes then
            -- If it's a secure release, the secure handler already fired the /emote macro!
            if not isSecureRelease then
                if InCombatLockdown() then
                    print("|cffff0000[OxedHub]|r Cannot perform emotes via mouse-click during combat! Use the radial hotkey release instead.")
                else
                    OxedHub.Emotes:DoEmote(mapping.emote)
                end
            end
        end
    elseif data.type == "trigger" then
        if OxedHub.Triggers and OxedHub.Triggers.ExecuteTriggerByID then
            OxedHub.Triggers:ExecuteTriggerByID(data.id, true)
        end
    elseif data.type == "marker" then
        -- If this is a secure release, the secure handler already executed
        -- the /wm or /cwm macro — skip the insecure call entirely.
        if not isSecureRelease then
            if InCombatLockdown() then
                print("|cffff0000[OxedHub]|r Cannot place markers via mouse-click during combat! Use the radial hotkey release instead.")
            else
                if data.id == 0 then
                    SecureCmdOptionParse("/cwm all")
                else
                    SecureCmdOptionParse("/wm " .. tostring(data.id))
                end
            end
        end
    elseif data.type == "targetmarker" then
        -- If this is a secure release, the secure handler already executed
        -- the /tm macro — skip the insecure call entirely.
        if not isSecureRelease then
            if InCombatLockdown() then
                print("|cffff0000[OxedHub]|r Cannot place target markers during combat! Use the radial hotkey release instead.")
            else
                if data.id == 0 then
                    SecureCmdOptionParse("/tm 0")
                else
                    SecureCmdOptionParse("/tm " .. tostring(data.id))
                end
            end
        end
    elseif data.type == "ping" then
        -- NOTE: retail WoW only lets addons ping at the live cursor position
        -- (via the secure /ping macro path, handled in the secure release
        -- handler). The position-based C_PingSecure API is not exposed to
        -- addons, so we cannot ping the ring's spawn point from a slice.
        if not isSecureRelease then
            if InCombatLockdown() then
                print("|cffff0000[OxedHub]|r Cannot ping via mouse-click during combat! Use the radial hotkey release instead.")
            elseif data.id == "" then
                SecureCmdOptionParse("/ping")
            else
                SecureCmdOptionParse("/ping " .. data.id)
            end
        end
    else
        -- Fallback to legacy emoteMappings
        if OxedHub.db and OxedHub.db.profile.emotionMappings then
            local mapping = OxedHub.db.profile.emotionMappings[data.id]
            if mapping then
                if mapping.sound and OxedHub.Sounds then
                    OxedHub.Sounds:Play(mapping.sound)
                end
                if mapping.animation and OxedHub.Animations then
                    OxedHub.Animations:Play(mapping.animation, {
                        useCustomPosition = mapping.animationUseCustomPosition,
                        x = mapping.animationCustomX,
                        y = mapping.animationCustomY
                    })
                end
                if mapping.emote then
                    DoEmote(mapping.emote)
                end
                if mapping.chat then
                    SendChatMessage(mapping.chat, "SAY")
                end
            end
        end
    end
end

function OxedRing:OnUpdate(elapsed)
    -- Select explosion runs independently even after ring closes
    if self.selectPlaying then
        local SELECT_FPS = 30   -- 91 frames over ~1.3 seconds (30% slower)
        self.selectFrame = (self.selectFrame or 1) + elapsed * SELECT_FPS
        if self.selectFrame > 91 then
            self.selectPlaying = false
            self.selectTex:Hide()
        else
            local fi = math.max(1, math.min(91, math.floor(self.selectFrame)))
            if fi ~= self.selectLastFrame then
                self.selectTex:SetTexture(string.format(
                    "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimationSelect\\FootageCrate-Firey_Shockwave_2-%05d.png", fi))
                self.selectLastFrame = fi
            end
        end
    end

    if not isRingOpen and not self.isClosing then return end

    -- Periodically refresh slice availability (for combat state changes, etc.)
    self.availRefreshTimer = (self.availRefreshTimer or 0) + elapsed
    if self.availRefreshTimer >= 0.1 then
        self.availRefreshTimer = 0
        for i, slice in ipairs(slices) do
            if slice:IsShown() and slice.data then
                local available = IsNodeAvailable(slice.data)
                local wasUnavailable = slice.isUnavailable
                slice.isUnavailable = not available
                -- If availability state changed, update visuals
                if wasUnavailable ~= slice.isUnavailable then
                    if available then
                        slice.icon:SetDesaturated(false)
                        slice.icon:SetVertexColor(1, 1, 1, 1)
                    else
                        slice.icon:SetDesaturated(true)
                        slice.icon:SetVertexColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
            end
        end
    end

    local ANIM_FPS = 60  -- SPEED: Change this number to adjust animation speed (frames per second)
    if isRingOpen then
        self.animFrame = (self.animFrame or 1) + elapsed * ANIM_FPS
        if self.animFrame > 18 then self.animFrame = 18 end
    --[[ DISABLED: close animation (reverse playback) -- re-enable later if needed
    elseif self.isClosing then
        self.animFrame = (self.animFrame or 18) - elapsed * ANIM_FPS
        if self.animFrame <= 1 then
            self.animFrame = 1
            self.isClosing = false
            self.animTex:Hide()
            self.frame:Hide()
        end
    --]]
    end

    local frameInt = math.max(1, math.min(18, math.floor(self.animFrame or 1)))
    if frameInt ~= self.lastAnimFrame then
        self.animTex:SetTexture(string.format(
            "Interface\\AddOns\\OxedHub\\Media\\Textures\\RingAnimation\\Comp 1_%05d.png", frameInt))
        self.animTex:SetPoint("CENTER", self.centerHub, "CENTER", 0, 0)
        self.animTex:Show()
        self.lastAnimFrame = frameInt
    end

    if isRingOpen and self.animFrame >= 18 then
        self.animTex:Hide()
    end

    -- if self.isClosing then return end  -- DISABLED: close animation commented out
    
    -- Animation Logic
    local animDuration = 0.15
    local timeOpen = GetTime() - (self.openTime or 0)
    
    if timeOpen <= animDuration then
        local animProgress = timeOpen / animDuration
        -- easeOutQuint: 1 - (1 - t)^5 (snappy pop out)
        local easeOut = 1 - math.pow(1 - animProgress, 5)
        
        self.centerHub:SetAlpha(animProgress)
        
        -- Animate the slices outward from the exact center (0,0)
        for i, slice in ipairs(slices) do
            if slice:IsShown() and slice.targetX and slice.targetY then
                local currentX = slice.targetX * easeOut
                local currentY = slice.targetY * easeOut
                slice:SetPoint("CENTER", self.centerHub, "CENTER", currentX, currentY)
                
                -- Only animate base scale during opening; UpdateHighlight will take over after
                if activeSliceIndex ~= i then
                    slice:SetScale(0.5 + 0.5 * easeOut)
                end
            end
        end
    else
        self.centerHub:SetAlpha(1)
        
        -- Snap to final positions when animation ends
        for i, slice in ipairs(slices) do
            if slice:IsShown() and slice.targetX and slice.targetY then
                slice:SetPoint("CENTER", self.centerHub, "CENTER", slice.targetX, slice.targetY)
                if activeSliceIndex ~= i then
                    slice:SetScale(1)
                end
            end
        end
    end
    
    local cx, cy = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    cx = cx / scale
    cy = cy / scale

    -- Mark cursor as moved once it travels more than 2px from its open position
    if not self.cursorMoved and self.openCursorX then
        local mdx = cx * scale - self.openCursorX
        local mdy = cy * scale - self.openCursorY
        if math.sqrt(mdx*mdx + mdy*mdy) > 2 then
            self.cursorMoved = true
        end
    end
    
    local ringX, ringY = self.centerHub:GetCenter()
    local dx = cx - ringX
    local dy = cy - ringY
    local dist = math.sqrt(dx*dx + dy*dy)
    
    if dist < DEADZONE_RADIUS then
        -- Inside deadzone, no selection
        if activeSliceIndex ~= nil then
            activeSliceIndex = nil
            self:UpdateHighlight()
        end
        return
    end
    
    -- Calculate angle from center to cursor
    local angle = math_atan2(dy, dx)
    
    -- Convert to degrees, 0 is right, 90 is up
    local angleDeg = math.deg(angle)
    if angleDeg < 0 then angleDeg = angleDeg + 360 end
    
    local numSlices = #sliceData
    local angleStep = 360 / numSlices
    
    -- Bin 1 is centered at 90
    local offsetAngle = (90 - angleDeg + (angleStep / 2)) % 360
    if offsetAngle < 0 then offsetAngle = offsetAngle + 360 end
    
    local hoveredIndex = math_floor(offsetAngle / angleStep) + 1
    if hoveredIndex > numSlices then hoveredIndex = 1 end
    
    -- Skip unavailable slices: keep rotating until we find an available one
    if not IsSliceAvailable(hoveredIndex) then
        -- Try to find the nearest available slice, or clear selection
        -- Search clockwise then counter-clockwise from the hovered index
        local found = nil
        for offset = 1, math_floor(numSlices / 2) do
            local cw = ((hoveredIndex - 1 + offset) % numSlices) + 1
            if IsSliceAvailable(cw) then found = cw break end
            local ccw = ((hoveredIndex - 1 - offset + numSlices) % numSlices) + 1
            if IsSliceAvailable(ccw) then found = ccw break end
        end
        if found then
            hoveredIndex = found
        else
            -- All slices in this direction are unavailable, clear selection
            if activeSliceIndex ~= nil then
                activeSliceIndex = nil
                self:UpdateHighlight()
            end
            return
        end
    end

    -- Arm the ping TYPE while hovering a ping petal. The actual ping is fired
    -- by releasing back in the center (so it lands on the ring's open spot),
    -- but the type is whatever ping petal was hovered last.
    local hd = sliceData[hoveredIndex]
    if hd and hd.type == "ping" then
        local m
        if hd.id == nil or hd.id == "" then
            m = "/ping"
        else
            m = "/ping " .. hd.id
        end
        if self.armedPingMacro ~= m then
            self.armedPingMacro = m
            if not InCombatLockdown() and OxedRing.hotkeyBtn then
                OxedRing.hotkeyBtn:SetAttribute("armedPingMacro", m)
            end
        end
    end

    if hoveredIndex ~= activeSliceIndex then
        activeSliceIndex = hoveredIndex
        self:UpdateHighlight()
        -- Animation on hover removed per user request
    end
end

function OxedRing:UpdateHighlight()
    local style = GetRingStyle()
    for i, slice in ipairs(slices) do
        local isUnavailable = slice.isUnavailable

        if i == activeSliceIndex and not isUnavailable then
            slice.highlight:Show()
            slice:SetScale(1.2)
            if style == "ring" and slice.ringBg then
                slice.ringBg:SetVertexColor(1, 0.82, 0, 1)
            else
                slice:SetBackdropBorderColor(1, 0.82, 0, 1)
            end
        else
            slice.highlight:Hide()
            slice:SetScale(1.0)

            if isUnavailable then
                -- Keep unavailable nodes visually muted
                if style == "ring" and slice.ringBg then
                    slice.ringBg:SetVertexColor(0.3, 0.3, 0.3, 0.3)
                else
                    slice:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4)
                end
            else
                if style == "ring" and slice.ringBg then
                    slice.ringBg:SetVertexColor(0.8, 0.8, 0.8, 0.2)
                else
                    slice:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
                end
            end
        end
    end
end

function OxedRing:ApplyRingBinding(newKey)
    -- Clear all previous override bindings on our proxy button
    if self.hotkeyBtn then
        ClearOverrideBindings(self.hotkeyBtn)
    end
    
    -- Set new override binding (routes the key press to our hidden button)
    if newKey and newKey ~= "" and self.hotkeyBtn then
        SetOverrideBindingClick(self.hotkeyBtn, true, newKey, "OxedRingHotkeyButton")
    end
    
    -- Persist in our own SavedVariables (NOT WoW's binding system)
    OxedHub.db.profile.oxedRingBinding = newKey
    
    -- Debug feedback so user knows it worked
    if newKey and newKey ~= "" then
        print("|cff00ff00OxedRing:|r Keybind set to |cffffff00" .. newKey .. "|r")
    else
        print("|cff00ff00OxedRing:|r Keybind cleared")
    end
end