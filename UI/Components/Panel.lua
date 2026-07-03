local addonName, OxedHub = ...

OxedHub.UIComponents = OxedHub.UIComponents or {}
OxedHub.UIComponents.Panel = OxedHub.UIComponents.Panel or {}

local Panel = OxedHub.UIComponents.Panel

local function SetFlippedAtlas(texture, atlasName, flipX, flipY)
    local atlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasName)
    if not atlas then return end

    texture:SetTexture(atlas.file)
    local left, right = atlas.leftTexCoord, atlas.rightTexCoord
    local top, bottom = atlas.topTexCoord, atlas.bottomTexCoord

    if flipX then left, right = right, left end
    if flipY then top, bottom = bottom, top end

    texture:SetTexCoord(left, right, top, bottom)
end

function Panel.ApplyStoneBackdrop(frame, alpha)
    if not frame then return end

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        frame:SetBackdropColor(0.10, 0.095, 0.085, alpha or 0.92)
    end
end

function Panel.ApplyBlackWorkBackdrop(frame, alpha)
    if not frame then return end

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\FrameGeneral\\UI-Background-Marble",
            tile = true,
            tileSize = 256,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        frame:SetBackdropColor(0.015, 0.015, 0.018, alpha or 0.90)
    end
end

function Panel.ApplyOrnateFrame(frame, title, alpha)
    if not frame or frame.ornateApplied then
        return
    end

    frame.ornateApplied = true
    Panel.ApplyStoneBackdrop(frame, alpha)

    local cSize = 17
    frame.cornerTL = frame:CreateTexture(nil, "BORDER")
    frame.cornerTL:SetAtlas("PetJournal-BattleSlotFrame-Corner", true)
    frame.cornerTL:SetPoint("TOPLEFT", -1, 1)

    frame.cornerTR = frame:CreateTexture(nil, "BORDER")
    frame.cornerTR:SetSize(cSize, cSize)
    frame.cornerTR:SetPoint("TOPRIGHT", 1, 1)
    SetFlippedAtlas(frame.cornerTR, "PetJournal-BattleSlotFrame-Corner", true, false)

    frame.cornerBL = frame:CreateTexture(nil, "BORDER")
    frame.cornerBL:SetSize(cSize, cSize)
    frame.cornerBL:SetPoint("BOTTOMLEFT", -1, -1)
    SetFlippedAtlas(frame.cornerBL, "PetJournal-BattleSlotFrame-Corner", false, true)

    frame.cornerBR = frame:CreateTexture(nil, "BORDER")
    frame.cornerBR:SetSize(cSize, cSize)
    frame.cornerBR:SetPoint("BOTTOMRIGHT", 1, -1)
    SetFlippedAtlas(frame.cornerBR, "PetJournal-BattleSlotFrame-Corner", true, true)

    frame.topEdge = frame:CreateTexture(nil, "BORDER")
    frame.topEdge:SetAtlas("_BattleSlotFrame-Top")
    frame.topEdge:SetPoint("TOPLEFT", frame.cornerTL, "TOPRIGHT", 0, 0)
    frame.topEdge:SetPoint("BOTTOMRIGHT", frame.cornerTR, "BOTTOMLEFT", 0, 1)

    frame.bottomEdge = frame:CreateTexture(nil, "BORDER")
    frame.bottomEdge:SetPoint("TOPLEFT", frame.cornerBL, "TOPRIGHT", 0, -1)
    frame.bottomEdge:SetPoint("BOTTOMRIGHT", frame.cornerBR, "BOTTOMLEFT", 0, 0)
    SetFlippedAtlas(frame.bottomEdge, "_BattleSlotFrame-Top", false, true)

    frame.leftEdge = frame:CreateTexture(nil, "BORDER")
    frame.leftEdge:SetTexture("Interface\\PetBattles\\!BattleSlotFrame-Left")
    frame.leftEdge:SetPoint("TOPLEFT", frame.cornerTL, "BOTTOMLEFT", 0, 0)
    frame.leftEdge:SetPoint("BOTTOMRIGHT", frame.cornerBL, "TOPRIGHT", -1, 0)

    frame.rightEdge = frame:CreateTexture(nil, "BORDER")
    frame.rightEdge:SetTexture("Interface\\PetBattles\\!BattleSlotFrame-Left")
    frame.rightEdge:SetTexCoord(1, 0, 0, 1)
    frame.rightEdge:SetPoint("TOPLEFT", frame.cornerTR, "BOTTOMLEFT", 1, 0)
    frame.rightEdge:SetPoint("BOTTOMRIGHT", frame.cornerBR, "TOPRIGHT", 0, 0)

    if title then
        frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.titleText:SetPoint("CENTER", frame.topEdge, "TOP", 0, -4)
        frame.titleText:SetTextColor(1, 0.82, 0, 1)
        frame.titleText:SetText(title)

        frame.titleBg = frame:CreateTexture(nil, "ARTWORK")
        frame.titleBg:SetAtlas("_BattleSlotTitle-BG")
        frame.titleBg:SetHeight(24)
        frame.titleBg:SetPoint("LEFT", frame.titleText, "LEFT", -15, 0)
        frame.titleBg:SetPoint("RIGHT", frame.titleText, "RIGHT", 15, 0)

        frame.titleMid = frame:CreateTexture(nil, "OVERLAY")
        frame.titleMid:SetAtlas("_BattleSlotTitle-Mid")
        frame.titleMid:SetPoint("TOPLEFT", frame.titleText, "TOPLEFT", 0, 0)
        frame.titleMid:SetPoint("BOTTOMRIGHT", frame.titleText, "BOTTOMRIGHT", 0, 0)

        frame.titleLeft = frame:CreateTexture(nil, "OVERLAY")
        frame.titleLeft:SetAtlas("PetJournal-BattleSlotTitle-Left", true)
        frame.titleLeft:SetPoint("RIGHT", frame.titleMid, "LEFT", 0, 0)

        frame.titleRight = frame:CreateTexture(nil, "OVERLAY")
        frame.titleRight:SetAtlas("PetJournal-BattleSlotTitle-Right", true)
        frame.titleRight:SetPoint("LEFT", frame.titleMid, "RIGHT", 0, 0)
    end
end
