local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.Button = OxedHub.UIComponents.Button or {}

local Button = OxedHub.UIComponents.Button

function Button.ApplyGoldStyle(button)
    if not button or button.oxedGoldStyled then
        return
    end

    button.oxedGoldStyled = true
    button.oxedRedStyled = nil
    if button.Left then button.Left:SetVertexColor(0.24, 0.10, 0.05, 1) end
    if button.Middle then button.Middle:SetVertexColor(0.24, 0.10, 0.05, 1) end
    if button.Right then button.Right:SetVertexColor(0.24, 0.10, 0.05, 1) end
    if button.Text then button.Text:SetTextColor(1, 0.82, 0, 1) end
end

function Button.ApplyRedStyle(button)
    if not button or button.oxedRedStyled then
        return
    end

    button.oxedRedStyled = true
    button.oxedGoldStyled = nil
    if button.Left then button.Left:SetVertexColor(1, 1, 1, 1) end
    if button.Middle then button.Middle:SetVertexColor(1, 1, 1, 1) end
    if button.Right then button.Right:SetVertexColor(1, 1, 1, 1) end
    if button.Text then button.Text:SetTextColor(1, 0.82, 0, 1) end
end

