local addonName, OxedHub = ...
local L = OxedHub.L
local Triggers = OxedHub.Triggers
local C_Timer = C_Timer
local GetTime = GetTime

local function CreateBorderedFrame(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = false, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.6)
    return f
end

local MACRO_COLOR_COMMAND = "|cff00bfff"
local MACRO_COLOR_SCRIPT = "|cff696969"
local MACRO_COLOR_SPELL = "|cff9932cc"
local MACRO_COLOR_TARGET = "|cffffd700"
local MACRO_COLOR_CONDITION = "|cff8b5a2b"
local MACRO_COLOR_SEQUENCE = "|cff006600"
local MACRO_COLOR_COMMENT = "|cff00aa00"
local MACRO_COLOR_META = "|cff7ad7ff"
local MACRO_COLOR_ACTIVE_LINE = "|cffffff96"
local MACRO_COLOR_DIM_LINE = "|cff6f6f6f"

local function EscapeMacroColorText(text)
    return tostring(text or ""):gsub("|", "||")
end

local function ColorWrap(color, text)
    if not text or text == "" then
        return text or ""
    end
    return color .. text .. "|r"
end

local function HighlightMacroConditions(text)
    return (tostring(text or ""):gsub("(%b[])", function(conditionBlock)
        return ColorWrap(MACRO_COLOR_CONDITION, conditionBlock)
    end))
end

local function HighlightMacroParameters(text, command)
    local escaped = EscapeMacroColorText(text or "")
    if escaped == "" then
        return ""
    end

    escaped = escaped:gsub("(;)", ColorWrap(MACRO_COLOR_COMMENT, "%1"))

    if command == "/cast" or command == "/use" or command == "/castrandom" or command == "/userandom" then
        escaped = escaped:gsub("([^;%[%]\n][^;\n]*)", function(segment)
            local trimmed = Triggers.TrimText(segment)
            if trimmed == "" then
                return segment
            end
            return ColorWrap(MACRO_COLOR_SPELL, segment)
        end)
    elseif command == "/castsequence" then
        escaped = escaped:gsub("([^;%[%]\n][^;\n]*)", function(segment)
            local trimmed = Triggers.TrimText(segment)
            if trimmed == "" then
                return segment
            end
            if trimmed:match("^reset=") then
                return ColorWrap(MACRO_COLOR_SEQUENCE, segment)
            end
            return ColorWrap(MACRO_COLOR_SPELL, segment)
        end)
    elseif command == "/target" or command == "/targetexact" or command == "/focus" or command == "/assist" or command == "/clearfocus" then
        escaped = escaped:gsub("(%S+)", function(segment)
            return ColorWrap(MACRO_COLOR_TARGET, segment)
        end)
    elseif command == "/run" or command == "/script" or command == "/click" or command == "/console" then
        escaped = ColorWrap(MACRO_COLOR_SCRIPT, escaped)
    end

    return HighlightMacroConditions(escaped)
end

local function BuildStyledMacroPreviewText(text)
    local lines = {}
    for line in tostring(text or ""):gmatch("([^\n]*)\n?") do
        if line == "" and #lines > 0 and lines[#lines] == nil then
            break
        end

        local escaped = EscapeMacroColorText(line)
        local prefix, rest = escaped:match("^(%S+)(.*)$")
        if prefix then
            if prefix:sub(1, 1) == "/" then
                escaped = ColorWrap(MACRO_COLOR_COMMAND, prefix) .. HighlightMacroParameters(rest, prefix:lower())
            elseif prefix:sub(1, 1) == "#" then
                escaped = ColorWrap(MACRO_COLOR_META, prefix) .. HighlightMacroConditions(rest)
            end
        else
            escaped = HighlightMacroConditions(escaped)
        end

        lines[#lines + 1] = escaped
    end

    return table.concat(lines, "\n")
end

local function BuildMacroLineNumberText(text, activeLine)
    local lineCount = 1
    for _ in tostring(text or ""):gmatch("\n") do
        lineCount = lineCount + 1
    end

    local lines = {}
    for index = 1, lineCount do
        local color = (index == activeLine) and MACRO_COLOR_ACTIVE_LINE or MACRO_COLOR_DIM_LINE
        lines[#lines + 1] = string.format("%s%d|r", color, index)
    end

    return table.concat(lines, "\n")
end

local function GetCursorLineAndColumn(text, cursorPosition)
    local content = tostring(text or "")
    local cursor = tonumber(cursorPosition) or 0
    if cursor < 0 then
        cursor = 0
    elseif cursor > #content then
        cursor = #content
    end

    local line = 1
    local column = 1
    for index = 1, cursor do
        local char = content:sub(index, index)
        if char == "\n" then
            line = line + 1
            column = 1
        else
            column = column + 1
        end
    end

    return line, column
end

local function GetCursorLineText(text, cursorPosition)
    local content = tostring(text or "")
    local cursor = tonumber(cursorPosition) or 0
    if cursor < 0 then
        cursor = 0
    elseif cursor > #content then
        cursor = #content
    end

    local beforeCursor = content:sub(1, cursor)
    return beforeCursor:match("([^\n]*)$") or ""
end

local function SplitMacroLines(text)
    local content = tostring(text or "")
    local lines = {}
    local startIndex = 1

    while true do
        local newlineIndex = content:find("\n", startIndex, true)
        if not newlineIndex then
            lines[#lines + 1] = content:sub(startIndex)
            break
        end

        lines[#lines + 1] = content:sub(startIndex, newlineIndex - 1)
        startIndex = newlineIndex + 1
    end

    if #lines == 0 then
        lines[1] = ""
    end

    return lines
end

local function GetCursorPositionFromLineAndX(text, targetLine, localX, measure)
    local lines = SplitMacroLines(text)
    local lineIndex = math.max(1, math.min(targetLine or 1, #lines))
    local lineText = lines[lineIndex] or ""
    local clampedX = math.max(localX or 0, 0)

    local columnIndex = #lineText
    for i = 0, #lineText do
        local prevWidth = 0
        if i > 0 then
            measure:SetText(lineText:sub(1, i - 1))
            prevWidth = measure:GetStringWidth()
        end

        measure:SetText(lineText:sub(1, i))
        local width = measure:GetStringWidth()
        if clampedX <= ((prevWidth + width) / 2) then
            columnIndex = i
            break
        end
    end

    local cursorPosition = columnIndex
    for i = 1, lineIndex - 1 do
        cursorPosition = cursorPosition + #(lines[i] or "") + 1
    end

    return cursorPosition
end

function Triggers:CreateAdvancedMacroUI(frame, trigger)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    title:SetText(L["ADV_MACRO_EXTEND_TITLE"] or "Extend Trigger Macro")

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    desc:SetWidth(420)
    desc:SetJustifyH("LEFT")
    -- Kept to a single line. Making it two pushed everything below it down,
    -- and the macro preview's styled overlay drifted out of step with the edit
    -- box underneath, drawing both copies of the text at once. The /run warning
    -- lives in the info box on the right instead.
    desc:SetText(L["ADV_MACRO_EXTEND_DESC"] or "Edit the final trigger macro directly and optionally set your own icon override.")
    desc:SetTextColor(0.75, 0.75, 0.75, 1)

    local iconPreview = CreateFrame("Button", nil, frame, "BackdropTemplate")
    iconPreview:SetSize(40, 40)
    iconPreview:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -12)
    iconPreview:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
    })
    iconPreview:SetBackdropColor(0.08, 0.08, 0.08, 0.8)
    iconPreview:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local iconTex = iconPreview:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", iconPreview, "TOPLEFT", 3, -3)
    iconTex:SetPoint("BOTTOMRIGHT", iconPreview, "BOTTOMRIGHT", -3, 3)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.advancedMacroIconPreview = iconPreview
    frame.advancedMacroIconTexture = iconTex

    local iconLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    iconLabel:SetPoint("TOPLEFT", iconPreview, "TOPRIGHT", 12, -2)
    iconLabel:SetText(L["ADV_MACRO_CUSTOM_ICON"] or "Custom Icon")

    local iconInput = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    iconInput:SetSize(220, 22)
    iconInput:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", 0, -6)
    iconInput:SetAutoFocus(false)
    frame.advancedMacroIconInput = iconInput

    local iconHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    iconHint:SetPoint("TOPLEFT", iconInput, "BOTTOMLEFT", 4, -4)
    iconHint:SetText(L["ADV_MACRO_CUSTOM_ICON_DESC"] or "Click the icon to pick from Blizzard's macro icons, or type an ID.")
    iconHint:SetTextColor(0.6, 0.6, 0.6, 1)

    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("TOPLEFT", iconPreview, "BOTTOMLEFT", 0, -18)
    previewLabel:SetText(L["ADV_MACRO_PREVIEW"] or "Macro Preview")

    local previewContainer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewContainer:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -6)
    previewContainer:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    previewContainer:SetHeight(150)
    previewContainer:EnableMouse(false)
    previewContainer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    previewContainer:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
    previewContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)

    local focusGlow = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
    focusGlow:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", -1, 1)
    focusGlow:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", 1, -1)
    focusGlow:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
    })
    focusGlow:SetBackdropBorderColor(1, 0.82, 0, 0)
    focusGlow:EnableMouse(false)
    frame.advancedMacroFocusGlow = focusGlow

    local gutter = CreateFrame("Frame", nil, previewContainer, "BackdropTemplate")
    gutter:SetPoint("TOPLEFT", previewContainer, "TOPLEFT", 6, -6)
    gutter:SetPoint("BOTTOMLEFT", previewContainer, "BOTTOMLEFT", 6, 6)
    gutter:SetWidth(36)
    gutter:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    gutter:SetBackdropColor(0.09, 0.09, 0.11, 0.92)

    local gutterDivider = gutter:CreateTexture(nil, "BORDER")
    gutterDivider:SetPoint("TOPRIGHT", gutter, "TOPRIGHT", 0, 0)
    gutterDivider:SetPoint("BOTTOMRIGHT", gutter, "BOTTOMRIGHT", 0, 0)
    gutterDivider:SetWidth(1)
    gutterDivider:SetColorTexture(0.22, 0.22, 0.24, 1)

    local gutterScroll = CreateFrame("ScrollFrame", nil, gutter)
    gutterScroll:SetPoint("TOPLEFT", gutter, "TOPLEFT", 0, 0)
    gutterScroll:SetPoint("BOTTOMRIGHT", gutter, "BOTTOMRIGHT", 0, 0)
    gutterScroll:EnableMouse(false)

    local gutterText = CreateFrame("EditBox", nil, gutterScroll)
    gutterText:SetPoint("TOPLEFT")
    gutterText:SetMultiLine(true)
    gutterText:SetFontObject("ChatFontNormal")
    gutterText:SetTextInsets(0, 4, 0, 4)
    gutterText:SetAutoFocus(false)
    gutterText:SetJustifyH("RIGHT")
    gutterText:SetJustifyV("TOP")
    gutterText:EnableMouse(false)
    gutterText:SetWidth(36)
    gutterScroll:SetScrollChild(gutterText)
    frame.advancedMacroGutterScroll = gutterScroll
    frame.advancedMacroGutterText = gutterText

    local fauxScroll = CreateFrame("ScrollFrame", nil, previewContainer, "UIPanelScrollFrameTemplate")
    fauxScroll:SetPoint("TOPLEFT", gutter, "TOPRIGHT", 6, 0)
    fauxScroll:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", -28, 6)
    fauxScroll:SetFrameLevel(previewContainer:GetFrameLevel() + 1)
    fauxScroll:EnableMouse(false)
    fauxScroll.ScrollBar:Hide()

    -- Kept hidden. The template shows its bar again whenever the content grows,

    -- and this frame only mirrors the real editor: its own bar was the old-style

    -- one on screen, and it scrolled independently of the text underneath.

    fauxScroll.ScrollBar:HookScript("OnShow", function(self) self:Hide() end)

    local fauxBox = CreateFrame("EditBox", nil, fauxScroll)
    fauxBox:SetAllPoints()
    fauxBox:SetMultiLine(true)
    fauxBox:SetFontObject("ChatFontNormal")
    fauxBox:SetTextInsets(0, 0, 0, 0)
    fauxBox:SetAutoFocus(false)
    fauxBox:SetCountInvisibleLetters(true)
    fauxBox:SetJustifyH("LEFT")
    fauxBox:SetJustifyV("TOP")
    fauxBox:EnableMouse(false)
    fauxBox:SetWidth(640)
    fauxBox.cursorOffset = 0
    fauxBox.cursorHeight = 16
    fauxScroll:SetScrollChild(fauxBox)
    frame.advancedMacroFauxScroll = fauxScroll
    frame.advancedMacroFauxText = fauxBox

    local fauxRegions = { fauxBox:GetRegions() }
    for _, region in ipairs(fauxRegions) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            region:SetAlpha(1)
        end
    end
    fauxBox:SetScript("OnUpdate", nil)
    fauxBox:SetScript("OnTextChanged", nil)

    -- Declared up here because the scroll handlers below call it, and they are
    -- written before it is defined. Without this the name resolves to a global
    -- that never exists, and the first scroll event raises on a nil call.
    local UpdateCursorIndicator

    local previewScroll = CreateFrame("ScrollFrame", nil, previewContainer, "UIPanelScrollFrameTemplate")
    previewScroll:SetPoint("TOPLEFT", gutter, "TOPRIGHT", 6, 0)
    previewScroll:SetPoint("BOTTOMRIGHT", previewContainer, "BOTTOMRIGHT", -28, 6)
    previewScroll:EnableMouseWheel(true)
    previewScroll:SetClipsChildren(true)
    previewScroll:SetFrameLevel(previewContainer:GetFrameLevel() + 2)
    if OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI:StyleScrollFrame(previewScroll)
    end

    -- The minimal bar is a child of the scroll frame, which sits below the
    -- styled overlay. Without lifting it, it was drawn behind that layer and
    -- looked as though it had vanished.
    if previewScroll.oxedMinimalScrollBar then
        previewScroll.oxedMinimalScrollBar:SetFrameStrata("HIGH")
        previewScroll.oxedMinimalScrollBar:SetFrameLevel(previewContainer:GetFrameLevel() + 12)
    end

    local previewBox = CreateFrame("EditBox", nil, previewScroll)
    previewBox:SetAllPoints()
    previewBox:SetMultiLine(true)
    previewBox:SetFontObject("ChatFontNormal")
    previewBox:SetTextInsets(0, 0, 0, 0)
    previewBox:SetAutoFocus(false)
    previewBox:SetJustifyH("LEFT")
    previewBox:SetJustifyV("TOP")
    previewBox:SetCountInvisibleLetters(true)
    previewBox:EnableMouse(true)
    previewBox.cursorOffset = 0
    previewBox.cursorHeight = 16
    previewBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    previewScroll:SetScrollChild(previewBox)
    frame.advancedMacroPreviewContainer = previewContainer
    frame.advancedMacroPreviewScroll = previewScroll
    frame.advancedMacroPreview = previewBox

    -- Exposed for /oxedhub macrodebug. The scrolling has to be measured rather
    -- than reasoned about: every guess so far has been about the wrong number.
    Triggers._macroDebugFrame = frame

    local previewRegions = { previewBox:GetRegions() }
    local previewTextRegion = nil
    for _, region in ipairs(previewRegions) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            previewTextRegion = region
            region:SetAlpha(0.4)
        end
    end
    fauxBox:SetScript("OnEditFocusGained", function()
        previewBox:SetFocus()
    end)

    local function SetEditorFocusState(isFocused)
        if previewTextRegion then
            previewTextRegion:SetAlpha(isFocused and 0.4 or 0.4)
        end
        if fauxBox then
            fauxBox:SetAlpha(1)
        end
        if focusGlow then
            focusGlow:SetBackdropBorderColor(1, 0.82, 0, isFocused and 0.9 or 0)
        end
        if previewContainer then
            if isFocused then
                previewContainer:SetBackdropBorderColor(1, 0.82, 0, 1)
            else
                previewContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            end
        end
    end

    -- Measured once from the font the editor actually uses, rather than assumed.
    -- This was hardcoded at 18 pixels a line; the real figure is about 14.4, so
    -- a twelve line macro got a box 55 pixels taller than its text. That surplus
    -- is empty space the view could scroll into and never come back from, and it
    -- put the styled overlay -- which sizes itself to its own text -- out of step
    -- with the edit box underneath.
    local measuredLineHeight

    local function GetLineHeight()
        if measuredLineHeight then return measuredLineHeight end

        local probe = previewBox:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
        probe:SetText("X")
        local single = probe:GetStringHeight() or 0
        probe:SetText("X\nX")
        local double = probe:GetStringHeight() or 0
        probe:Hide()

        -- The difference between one line and two is the line pitch, spacing
        -- included; measuring one line alone misses the gap between them.
        local pitch = double - single
        measuredLineHeight = (pitch > 0) and pitch or (single > 0 and single or 14)
        return measuredLineHeight
    end

    local function RefreshPreviewBoxHeight(text)
        local lineCount = 1
        for _ in tostring(text or ""):gmatch("\n") do
            lineCount = lineCount + 1
        end

        local minHeight = math.max((previewContainer:GetHeight() or 150) - 12, 138)
        local targetHeight = math.max(minHeight, (lineCount * GetLineHeight()))
        previewBox:SetHeight(targetHeight)
        fauxBox:SetHeight(targetHeight)
        gutterText:SetHeight(targetHeight)
    end

    previewContainer:SetScript("OnSizeChanged", function(self)
        local targetWidth = math.max((self:GetWidth() or 200) - 76, 120)
        previewBox:SetWidth(targetWidth)
        fauxBox:SetWidth(targetWidth)
        RefreshPreviewBoxHeight(previewBox:GetText())
    end)

    -- Re-entry guard: SetVerticalScroll fires OnVerticalScroll, which calls
    -- back into here. Three scroll frames each re-triggering the other two was
    -- the churn behind the stutter while scrolling.
    local syncingScroll = false

    local function SyncPreviewScroll(offset)
        if syncingScroll then return end
        syncingScroll = true

        previewScroll:SetVerticalScroll(offset)
        fauxScroll:SetVerticalScroll(offset)
        gutterScroll:SetVerticalScroll(offset)

        syncingScroll = false
    end

    previewScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll() or 0

        -- The range comes from the content, not from self.ScrollBar. That is
        -- the template's original bar, which the addon's scroll styling hides
        -- and stops updating -- it stays at 0..0 forever, so every wheel step
        -- was clamped to zero and the view could never be brought back up,
        -- while the edit box kept pushing it down to follow the caret.
        local child = self:GetScrollChild()
        local maxScroll = math.max(0, (child and child:GetHeight() or 0) - (self:GetHeight() or 0))

        local nextScroll = current - (delta * 24)
        if nextScroll < 0 then
            nextScroll = 0
        elseif nextScroll > maxScroll then
            nextScroll = maxScroll
        end

        -- Cancel the pending "keep the caret visible" correction. The caret is
        -- at the end of the macro, so without this the edit box dragged the
        -- view straight back down on the next frame and scrolling up was
        -- impossible.
        previewBox.handleCursorChange = false

        SyncPreviewScroll(nextScroll)
    end)

    previewScroll:SetScript("OnVerticalScroll", function(self, offset)
        SyncPreviewScroll(offset)
        UpdateCursorIndicator()
    end)

    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOPLEFT", previewContainer, "BOTTOMLEFT", 2, -12)
    countText:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.advancedMacroCount = countText

    local cursorText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cursorText:SetPoint("LEFT", countText, "RIGHT", 18, 0)
    cursorText:SetTextColor(0.7, 0.9, 1, 1)
    frame.advancedMacroCursor = cursorText

    -- The Macro Helper fills the space under the editor -- the space the info
    -- box used to take before it moved up beside the icon picker.
    frame.macroHelperDock = previewContainer

    -- Shared with the Mix Macro editor. No refresh callback is needed: Insert()
    -- fires the box's own OnTextChanged, which already updates the count and
    -- saves the body.
    if OxedHub.MacroHelper then
        OxedHub.MacroHelper:Attach(frame, previewBox, cursorText)
    end

    local caretMeasure = previewBox:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    caretMeasure:Hide()

    local fakeCaret = previewBox:CreateTexture(nil, "OVERLAY")
    fakeCaret:SetColorTexture(1, 0.94, 0.4, 1)
    fakeCaret:SetWidth(2)
    fakeCaret:Hide()
    frame.advancedMacroFakeCaret = fakeCaret

    local function UpdateFakeCaret()
        if not previewBox:HasFocus() then
            fakeCaret:Hide()
            return
        end

        local cursorPosition = previewBox:GetCursorPosition()
        local currentLineText = GetCursorLineText(previewBox:GetText(), cursorPosition)
        caretMeasure:SetFontObject("ChatFontNormal")
        caretMeasure:SetText(currentLineText)

        local x = caretMeasure:GetStringWidth()
        local y = previewBox.overlayCursorOffset
        local h = previewBox.overlayCursorHeight

        if y == nil then
            local line = GetCursorLineAndColumn(previewBox:GetText(), cursorPosition)
            y = -(((line or 1) - 1) * 16)
            h = 16
        end

        fakeCaret:ClearAllPoints()
        fakeCaret:SetPoint("TOPLEFT", previewBox, "TOPLEFT", x, y)
        fakeCaret:SetHeight(math.max((h or 16) - 1, 12))
        fakeCaret:Show()
    end

    -- Assigns the forward declaration above, so the earlier handlers share this
    -- one function rather than looking for a global.
    function UpdateCursorIndicator()
        local line, column = GetCursorLineAndColumn(previewBox:GetText(), previewBox:GetCursorPosition())
        cursorText:SetFormattedText("Line %d, Col %d", line, column)
        gutterText:SetText(BuildMacroLineNumberText(previewBox:GetText(), line))
        UpdateFakeCaret()
    end

    local function PlaceCursorFromMouse()
        local cursorX, cursorY = GetCursorPosition()
        local scale = previewScroll:GetEffectiveScale() or 1
        local left = previewScroll:GetLeft()
        local top = previewScroll:GetTop()
        if not left or not top then
            return
        end

        local localX = (cursorX / scale) - left
        local localY = top - (cursorY / scale) + (previewScroll:GetVerticalScroll() or 0)
        local lineHeight = math.max((select(2, previewBox:GetFont()) or 14) + 2, 14)
        local targetLine = math.max(1, math.floor(localY / lineHeight) + 1)

        caretMeasure:SetFontObject("ChatFontNormal")
        local cursorPosition = GetCursorPositionFromLineAndX(previewBox:GetText(), targetLine, localX, caretMeasure)
        previewBox:SetFocus()
        previewBox:SetCursorPosition(cursorPosition)
        previewBox.overlayCursorX = nil
        previewBox.overlayCursorOffset = nil
        previewBox.overlayCursorHeight = nil
        fauxBox.overlayCursorX = nil
        fauxBox.overlayCursorOffset = nil
        fauxBox.overlayCursorHeight = nil
        previewBox.pendingCaretRefresh = 2
        UpdateCursorIndicator()
    end

    previewBox:HookScript("OnMouseDown", function()
        PlaceCursorFromMouse()
    end)

    local function UpdateAdvancedUI()
        if not trigger then
            return
        end

        local iconValue = Triggers.TrimText(trigger.customMacroIcon)
        local resolvedIcon = Triggers:ResolveCustomMacroIcon(iconValue)
        frame.advancedMacroIconTexture:SetTexture(resolvedIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local displayIconValue = iconValue
        if OxedHub.IconPicker and OxedHub.IconPicker.GetDisplayValue then
            displayIconValue = OxedHub.IconPicker:GetDisplayValue(iconValue)
        end

        if OxedHub.IconPicker and OxedHub.IconPicker.IsStoredTextureValue and OxedHub.IconPicker:IsStoredTextureValue(iconValue) then
            iconInput.lastPickerStoredValue = iconValue
            iconInput.lastPickerDisplayValue = displayIconValue or ""
        else
            iconInput.lastPickerStoredValue = nil
            iconInput.lastPickerDisplayValue = nil
        end

        if iconInput:GetText() ~= (displayIconValue or "") then
            iconInput.isSyncingValue = true
            iconInput:SetText(displayIconValue or "")
            iconInput.isSyncingValue = false
        end

        local body = Triggers:BuildTriggerMacroBody(trigger) or Triggers:BuildDefaultTriggerMacroBody(trigger) or ""
        if previewBox:GetText() ~= body then
            previewBox.isSyncingText = true
            previewBox:SetText(body)
            fauxBox:SetText(BuildStyledMacroPreviewText(body))
            RefreshPreviewBoxHeight(body)
            SyncPreviewScroll(0)
            previewBox.isSyncingText = false
            UpdateCursorIndicator()
        end

        local used = #body
        local color = used > 255 and "|cffff4444" or "|cffcccccc"
        countText:SetText(color .. string.format(L["ADV_MACRO_CHARACTERS_USED"] or "%d/255 Characters Used", used) .. "|r")
    end

    iconPreview:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    iconPreview:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            trigger.customMacroIcon = nil
            UpdateAdvancedUI()
            Triggers.ShowAutoSaved(frame:GetParent())
            return
        end

        if OxedHub.IconPicker then
            OxedHub.IconPicker:Open({
                title = L["ADV_MACRO_CHOOSE_ICON"] or "Choose Trigger Macro Icon",
                initialValue = trigger.customMacroIcon,
                anchor = iconPreview,
                allowClear = true,
                onSelect = function(storedValue)
                    trigger.customMacroIcon = storedValue
                    UpdateAdvancedUI()
                    Triggers.ShowAutoSaved(frame:GetParent())
                end,
            })
        end
    end)

    iconPreview:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["ADV_MACRO_CUSTOM_ICON"] or "Custom Icon")
        GameTooltip:AddLine(L["ADV_MACRO_CHOOSE_ICON_LEFT_CLICK"] or "Left-click to choose an icon from Blizzard's macro icon list.", 1, 1, 1, true)
        GameTooltip:AddLine(L["ADV_MACRO_CLEAR_ICON_RIGHT_CLICK"] or "Right-click to clear the custom icon.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)

    iconPreview:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    iconInput:SetScript("OnTextChanged", function(self)
        if self.isSyncingValue then
            return
        end

        local typedValue = Triggers.TrimText(self:GetText())
        if self.lastPickerStoredValue and typedValue == (self.lastPickerDisplayValue or "") then
            trigger.customMacroIcon = self.lastPickerStoredValue
        else
            trigger.customMacroIcon = typedValue
        end

        if trigger.customMacroIcon == "" then
            trigger.customMacroIcon = nil
        end
        UpdateAdvancedUI()
        Triggers.ShowAutoSaved(frame:GetParent())
    end)

    previewBox:SetScript("OnTextChanged", function(self)
        if self.isSyncingText then
            return
        end

        local currentText = self:GetText() or ""
        RefreshPreviewBoxHeight(currentText)
        fauxBox:SetText(BuildStyledMacroPreviewText(currentText))
        -- Only the real edit box drives the scrolling. Letting the styled
        -- overlay scroll itself as well gave two independent calculations that
        -- drifted apart once the macro grew past the visible area, drawing the
        -- coloured copy and the plain one at different offsets.
        ScrollingEdit_OnTextChanged(self, self:GetParent())
        C_Timer.After(0, function()
            if not (previewScroll and fauxScroll) then return end

            -- The overlay is the measurement, not the thing to be corrected.
            -- Our SetHeight does not stick on it: the engine sizes it to its
            SyncPreviewScroll(previewScroll:GetVerticalScroll() or 0)
        end)
        local defaultBody = Triggers:BuildDefaultTriggerMacroBody(trigger) or ""
        local normalized = Triggers.NormalizeMacroBodyText(currentText)
        if not normalized or normalized == defaultBody then
            trigger.customMacroBody = nil
        else
            trigger.customMacroBody = currentText
        end

        local used = #currentText
        local color = used > 255 and "|cffff4444" or "|cffcccccc"
        countText:SetText(color .. string.format(L["ADV_MACRO_CHARACTERS_USED"] or "%d/255 Characters Used", used) .. "|r")
        UpdateCursorIndicator()
        Triggers.ShowAutoSaved(frame:GetParent())
    end)

    previewBox:SetScript("OnCursorChanged", function(self, x, y, _, h)
        self.cursorX = x
        self.cursorOffset = y or 0
        self.cursorHeight = h or self.cursorHeight or 16
        self.overlayCursorX = x
        self.overlayCursorOffset = y
        self.overlayCursorHeight = h
        self.handleCursorChange = true
        fauxBox.cursorX = x
        fauxBox.cursorOffset = y or 0
        fauxBox.cursorHeight = h or fauxBox.cursorHeight or 16
        fauxBox.overlayCursorX = x
        fauxBox.overlayCursorOffset = y
        fauxBox.overlayCursorHeight = h
        fauxBox.handleCursorChange = true
        UpdateCursorIndicator()
    end)

    previewBox:SetScript("OnUpdate", function(self)
        if self.cursorOffset == nil then
            self.cursorOffset = 0
        end
        if fauxBox.cursorOffset == nil then
            fauxBox.cursorOffset = 0
        end
        ScrollingEdit_OnUpdate(self)
        ScrollingEdit_OnUpdate(fauxBox)
        if self.pendingCaretRefresh and self.pendingCaretRefresh > 0 then
            self.overlayCursorX = nil
            self.overlayCursorOffset = nil
            self.overlayCursorHeight = nil
            fauxBox.overlayCursorX = nil
            fauxBox.overlayCursorOffset = nil
            fauxBox.overlayCursorHeight = nil
            UpdateCursorIndicator()
            self.pendingCaretRefresh = self.pendingCaretRefresh - 1
        end
        if self:HasFocus() then
            UpdateFakeCaret()
            local pulse = math.floor(GetTime() * 2) % 2
            fakeCaret:SetAlpha(pulse == 0 and 1 or 0)
        else
            fakeCaret:Hide()
        end
    end)

    previewBox:SetScript("OnMouseUp", function()
        previewBox.pendingCaretRefresh = 3
    end)

    previewBox:SetScript("OnEditFocusGained", function()
        SetEditorFocusState(true)
        UpdateCursorIndicator()
    end)

    previewBox:SetScript("OnEditFocusLost", function()
        SetEditorFocusState(false)
        fakeCaret:Hide()
    end)

    frame.UpdateAdvancedMacroUI = UpdateAdvancedUI
    UpdateAdvancedUI()
    SetEditorFocusState(false)

    -- Help Tooltip Box
    local infoBox = CreateBorderedFrame(frame)
    -- Moved to the empty band beside the icon picker. It used to sit under the
    -- editor and take the full width, which is the space the Macro Helper needs.
    -- Starts well clear of the icon hint on its left, so the two no longer
    -- overlap, and is tall enough for the text to wrap instead of being cut.
    -- Anchored to the right edge of the icon hint, not to a fixed offset. The
    -- hint is a sentence whose width depends on the locale and font scale, so a
    -- fixed position left the box sitting on top of its tail.
    -- Pinned by its bottom edge to just above the editor, so growing the box
    -- taller makes it rise instead of sinking into the macro preview.
    infoBox:SetHeight(52)
    infoBox:SetPoint("BOTTOMRIGHT", previewContainer, "TOPRIGHT", 0, 10)
    infoBox:SetPoint("LEFT", iconHint, "RIGHT", 24, 0)
    infoBox:SetBackdropColor(0, 0, 0, 0.6)

    local icon = infoBox:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    icon:SetTexture("Interface\\common\\help-i")

    -- No heading. The box is one short sentence next to an information icon;
    -- a title line above it said nothing the sentence does not, and cost the
    -- room the sentence needed to fit.
    --
    -- Smaller font and wrapping on: at the normal size it ran past the edge and
    -- was clipped mid-word.
    local infoDesc = infoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoDesc:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
    infoDesc:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoDesc:SetJustifyH("LEFT")
    infoDesc:SetJustifyV("TOP")
    infoDesc:SetWordWrap(true)
    -- The /run reminder lives here rather than in the description above: this
    -- box has room to grow, the description does not without shifting the whole
    -- column and breaking the preview overlay's alignment.
    infoDesc:SetText(L["ADV_MACRO_CUSTOM_DESC_SHORT"]
        or "Custom macro code lets you override or extend a standard trigger, for example by adding conditions or targeting commands.|n|cffff9900Keep the /run OxedHub.Triggers:ExecuteTriggerByID line -- it fires the trigger.|r")
end

-- Expose syntax highlighting utilities for reuse by other modules (e.g. Toys Mix Macro Editor)
Triggers.BuildStyledMacroPreviewText = BuildStyledMacroPreviewText
Triggers.BuildMacroLineNumberText = BuildMacroLineNumberText
Triggers.GetCursorLineAndColumn = GetCursorLineAndColumn
Triggers.GetCursorLineText = GetCursorLineText
Triggers.GetCursorPositionFromLineAndX = GetCursorPositionFromLineAndX


-- ── Macro preview diagnostics  (/oxedhub macrodebug) ─────────────────────────
-- Reports the numbers the scrolling actually depends on. Guessing at the line
-- height and the frame levels produced three wrong fixes in a row; these are
-- the values that decide whether the box can scroll and whether the bar shows.
function Triggers:DumpMacroPreview()
    local frame = Triggers._macroDebugFrame
    if not frame then
        print("|cff00d9d9OxedHub:|r open a trigger's Advanced Macros tab first.")
        return
    end

    local container = frame.advancedMacroPreviewContainer
    local scroll = frame.advancedMacroPreviewScroll
    local box = frame.advancedMacroPreview
    local fauxScroll = frame.advancedMacroFauxScroll
    local fauxBox = frame.advancedMacroFauxText

    local text = box and box:GetText() or ""
    local lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end

    print("|cff00d9d9=== OxedHub macro preview ===|r")
    print(("lines=%d  chars=%d"):format(lines, #text))

    if container then
        print(("container: h=%.0f"):format(container:GetHeight() or 0))
    end

    if scroll then
        local minV, maxV = 0, 0
        if scroll.ScrollBar and scroll.ScrollBar.GetMinMaxValues then
            minV, maxV = scroll.ScrollBar:GetMinMaxValues()
        end
        print(("previewScroll: h=%.0f scroll=%.1f range=%.0f..%.0f level=%d"):format(
            scroll:GetHeight() or 0, scroll:GetVerticalScroll() or 0,
            minV or 0, maxV or 0, scroll:GetFrameLevel() or 0))
        print(("   clipsChildren=%s  scrollChildH=%.0f"):format(
            tostring(scroll.DoesClipChildren and scroll:DoesClipChildren()),
            (scroll:GetScrollChild() and scroll:GetScrollChild():GetHeight()) or 0))
    end

    if box then
        print(("previewBox: h=%.0f  parent=%s"):format(
            box:GetHeight() or 0, tostring(box:GetParent() == scroll)))
    end

    if fauxScroll then
        print(("fauxScroll: h=%.0f scroll=%.1f level=%d  barShown=%s"):format(
            fauxScroll:GetHeight() or 0, fauxScroll:GetVerticalScroll() or 0,
            fauxScroll:GetFrameLevel() or 0,
            tostring(fauxScroll.ScrollBar and fauxScroll.ScrollBar:IsShown())))
    end
    if fauxBox then
        print(("fauxBox: h=%.0f"):format(fauxBox:GetHeight() or 0))
    end

    local bar = scroll and scroll.oxedMinimalScrollBar
    if bar then
        print(("minimalBar: shown=%s level=%d strata=%s w=%.0f h=%.0f"):format(
            tostring(bar:IsShown()), bar:GetFrameLevel() or 0,
            tostring(bar:GetFrameStrata()), bar:GetWidth() or 0, bar:GetHeight() or 0))
    else
        print("minimalBar: |cffff4040missing|r -- the scroll frame was never styled")
    end
end
