local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.Search = OxedHub.UIComponents.Search or {}

local Search = OxedHub.UIComponents.Search

function Search.ApplyFrameStyle(searchBox)
    if not searchBox or searchBox.oxedSearchStyled then
        return
    end

    searchBox.oxedSearchStyled = true

    if searchBox.Left then
        searchBox.Left:Show()
        searchBox.Left:SetAlpha(0.75)
        searchBox.Left:SetVertexColor(0.46, 0.47, 0.47, 1)
    end
    if searchBox.Middle then
        searchBox.Middle:Show()
        searchBox.Middle:SetAlpha(0.75)
        searchBox.Middle:SetVertexColor(0.46, 0.47, 0.47, 1)
    end
    if searchBox.Right then
        searchBox.Right:Show()
        searchBox.Right:SetAlpha(0.75)
        searchBox.Right:SetVertexColor(0.46, 0.47, 0.47, 1)
    end

    searchBox:SetTextInsets(22, 20, 0, 0)

    if searchBox.searchIcon then
        searchBox.searchIcon:ClearAllPoints()
        searchBox.searchIcon:SetPoint("LEFT", searchBox, "LEFT", 6, 0)
        searchBox.searchIcon:SetVertexColor(0.72, 0.74, 0.76, 0.85)
    end

    if searchBox.ClearButton then
        searchBox.ClearButton:ClearAllPoints()
        searchBox.ClearButton:SetPoint("RIGHT", searchBox, "RIGHT", -4, 0)
        searchBox.ClearButton:SetAlpha(0.75)
    end
end
