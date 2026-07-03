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
