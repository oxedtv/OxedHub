local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.Scroll = OxedHub.UIComponents.Scroll or {}

local Scroll = OxedHub.UIComponents.Scroll
local CreateFrame = CreateFrame

function Scroll.StyleFrame(scrollFrame)
    if not scrollFrame or scrollFrame.oxedStyled then
        return
    end

    scrollFrame.oxedStyled = true

    local oldScrollBar = scrollFrame.ScrollBar
    if not oldScrollBar and scrollFrame.GetName then
        local name = scrollFrame:GetName()
        if name then
            oldScrollBar = _G[name .. "ScrollBar"]
        end
    end
    if not oldScrollBar then
        for _, child in ipairs({scrollFrame:GetChildren()}) do
            if child:IsObjectType("Slider") or (child.GetValue and child.SetMinMaxValues) then
                oldScrollBar = child
                break
            end
        end
    end

    if oldScrollBar then
        oldScrollBar:Hide()
        oldScrollBar:HookScript("OnShow", function(self) self:Hide() end)
    end

    if not (ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar) then
        return
    end

    local parent = scrollFrame:GetParent()
    if not parent then
        return
    end

    local minimalBar = CreateFrame("EventFrame", nil, scrollFrame, "MinimalScrollBar")
    minimalBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 10, 2)
    minimalBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 10, -1)
    minimalBar:SetFrameLevel(scrollFrame:GetFrameLevel() + 4)
    scrollFrame.oxedMinimalScrollBar = minimalBar

    scrollFrame:EnableMouseWheel(true)
    ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, minimalBar)

    scrollFrame:HookScript("OnShow", function(self)
        if self.oxedMinimalScrollBar then
            self.oxedMinimalScrollBar:Show()
        end
    end)

    scrollFrame:HookScript("OnHide", function(self)
        if self.oxedMinimalScrollBar then
            self.oxedMinimalScrollBar:Hide()
        end
    end)
end

-- ── A scroll bar for a hand-made list ───────────────────────────────────────
-- Scroll.CreateMinimalBar(frame, top, height, onScroll, right) puts a vertical
-- bar at the frame's top right: the game's MinimalScrollBar when this client
-- has it, a thin grey slider otherwise. onScroll gets the first row to show.
-- Returns { Sync(first, maxFirst, visible, total) }; call it after drawing.
function Scroll.CreateMinimalBar(f, top, height, onScroll, right)
    local holder = { max = 0 }
    right = right or -10
    local ok, bar = pcall(CreateFrame, "EventFrame", nil, f, "MinimalScrollBar")
    if ok and bar and bar.SetScrollPercentage and bar.RegisterCallback then
        bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", right, top)
        bar:SetHeight(height)
        local event = BaseScrollBoxEvents and BaseScrollBoxEvents.OnScroll or "OnScroll"
        local hooked = pcall(bar.RegisterCallback, bar, event, function(_, percent)
            if holder.syncing or type(percent) ~= "number" then return end
            onScroll(math.floor(percent * holder.max + 0.5))
        end, holder)
        if hooked then
            function holder:Sync(first, maxFirst, visible, total)
                self.max = maxFirst
                bar:SetShown(maxFirst > 0)
                if maxFirst <= 0 then return end
                self.syncing = true
                pcall(function()
                    bar:SetVisibleExtentPercentage(visible / math.max(total, 1))
                    bar:SetPanExtentPercentage(1 / maxFirst)
                    bar:SetScrollPercentage(first / maxFirst)
                end)
                self.syncing = false
            end
            return holder
        end
        bar:Hide()
    end
    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(4)
    slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", right - 4, top)
    slider:SetHeight(height)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.05)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(0.75, 0.75, 0.75, 0.5)
    thumb:SetSize(4, 36)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(0, 0)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetScript("OnValueChanged", function(_, value)
        if not holder.syncing then onScroll(math.floor(value + 0.5)) end
    end)
    function holder:Sync(first, maxFirst)
        self.syncing = true
        slider:SetMinMaxValues(0, maxFirst)
        slider:SetValue(first)
        self.syncing = false
        slider:SetShown(maxFirst > 0)
    end
    return holder
end
