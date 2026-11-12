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

-- ── Tab buttons ─────────────────────────────────────────────────────────────
-- Button.CreateTab(parent, width, text, onClick, height) gives a button with
-- :SetText(text), :SetLabel(text) and :SetActive(bool). It is the game's own
-- tab button (the one on top of the spellbook) when this client has it, and
-- a flat drawn tab otherwise: dark slate, the chosen one gold.
--
-- The template is asked for in pcall: a template this client lacks is an
-- error, not a nil. Its art is driven by SetTabSelected only; the tab system
-- it normally belongs to is never used, so its click script is replaced.

local NATIVE_TABS = { "TabSystemButtonTemplate", "MinimalTabTemplate" }

local function Paint(tex, top, bottom)
    tex:SetColorTexture(1, 1, 1, 1)
    local ok = false
    if CreateColor then
        ok = pcall(tex.SetGradient, tex, "VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], 1), CreateColor(top[1], top[2], top[3], 1))
    end
    if not ok and tex.SetGradientAlpha then
        ok = pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], 1, top[1], top[2], top[3], 1)
    end
    if not ok then tex:SetColorTexture(top[1], top[2], top[3], 1) end
end

-- Two rectangles, one a pixel narrower, one a pixel shorter: a box with
-- clipped corners, inset by inset.
local function CutBox(b, layer, sub, inset)
    local wide = b:CreateTexture(nil, layer, nil, sub)
    wide:SetPoint("TOPLEFT", inset + 1, -inset)
    wide:SetPoint("BOTTOMRIGHT", -inset - 1, inset)
    local tall = b:CreateTexture(nil, layer, nil, sub)
    tall:SetPoint("TOPLEFT", inset, -inset - 1)
    tall:SetPoint("BOTTOMRIGHT", -inset, inset + 1)
    return { wide, tall }
end

local LOOK = {
    off = { edge = { 0.36, 0.36, 0.38 }, edgeLow = { 0.20, 0.20, 0.22 },
            top = { 0.24, 0.24, 0.26 }, bottom = { 0.11, 0.11, 0.12 }, text = { 0.88, 0.88, 0.88 } },
    on  = { edge = { 0.95, 0.78, 0.35 }, edgeLow = { 0.55, 0.40, 0.12 },
            top = { 0.66, 0.50, 0.18 }, bottom = { 0.38, 0.27, 0.07 }, text = { 1, 0.96, 0.82 } },
}

local function ApplyLook(b, active)
    local look = active and LOOK.on or LOOK.off
    for _, tex in ipairs(b.oxEdge) do Paint(tex, look.edge, look.edgeLow) end
    for _, tex in ipairs(b.oxFill) do Paint(tex, look.top, look.bottom) end
    b.label:SetTextColor(look.text[1], look.text[2], look.text[3])
end

local function NativeTab(parent, width, text, onClick, height)
    for _, template in ipairs(NATIVE_TABS) do
        local ok, b = pcall(CreateFrame, "Button", nil, parent, template)
        if ok and b and b.SetTabSelected then
            local fine = pcall(function()
                local label = b.Text or (b.GetFontString and b:GetFontString())
                if not label then error("no label") end
                b.label = label
                label:SetText(text)
                b:SetTabSelected(false)
            end)
            if fine then
                b:SetScript("OnClick", onClick)
                b:SetWidth(width)
                if height then b:SetHeight(height) elseif b:GetHeight() <= 0 then b:SetHeight(28) end
                function b:SetLabel(value) self.label:SetText(value) end
                b.SetText = b.SetLabel
                function b:SetActive(on) pcall(self.SetTabSelected, self, on == true) end
                return b
            end
            b:Hide()
        end
    end
    return nil
end

local function DrawnTab(parent, width, text, onClick, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height or 24)
    b.oxEdge = CutBox(b, "BACKGROUND", 0, 0)
    b.oxFill = CutBox(b, "BACKGROUND", 1, 1)
    -- A faint line of light along the top.
    local shine = b:CreateTexture(nil, "BORDER")
    shine:SetColorTexture(1, 1, 1, 0.10)
    shine:SetHeight(1)
    shine:SetPoint("TOPLEFT", 3, -2)
    shine:SetPoint("TOPRIGHT", -3, -2)
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 2, -2)
    hover:SetPoint("BOTTOMRIGHT", -2, 2)
    hover:SetColorTexture(1, 1, 1, 0.07)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    if b.label.SetWordWrap then b.label:SetWordWrap(false) end
    b.label:SetText(text)
    function b:SetLabel(value) self.label:SetText(value) end
    b.SetText = b.SetLabel
    function b:SetActive(on) ApplyLook(self, on == true) end
    b:SetScript("OnMouseDown", function(self) self.label:SetPoint("LEFT", 7, -1) self.label:SetPoint("RIGHT", -5, -1) end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", 6, 0) self.label:SetPoint("RIGHT", -6, 0) end)
    b:SetScript("OnClick", onClick)
    ApplyLook(b, false)
    return b
end

-- A switched-off button is dimmed. The native tab switches itself off while
-- it is the chosen one (SetTabSelected), and that must not dim it.
local function DimWhenOff(b)
    local base = b.SetEnabled
    function b:SetEnabled(on)
        base(self, on)
        if not self.oxSelecting then self:SetAlpha(on and 1 or 0.45) end
    end
    local setActive = b.SetActive
    function b:SetActive(on)
        self.oxSelecting = true
        setActive(self, on)
        self.oxSelecting = nil
    end
    return b
end

function Button.CreateTab(parent, width, text, onClick, height)
    return DimWhenOff(NativeTab(parent, width, text, onClick, height) or DrawnTab(parent, width, text, onClick, height))
end
