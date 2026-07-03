local addonName, OxedHub = ...

-- Experimental Module - visual trigger graph builder prototype
local Experimental = {}
OxedHub.Experimental = Experimental

local CreateFrame = CreateFrame
local UIParent = UIParent
local GameTooltip = GameTooltip
local math = math
local pairs = pairs
local ipairs = ipairs
local table = table
local tostring = tostring
local type = type
local tonumber = tonumber
local strlower = string.lower
local C_Spell = C_Spell
local C_SpellBook = C_SpellBook
local C_ToyBox = C_ToyBox
local Enum = Enum

local PALETTE_WIDTH = 190
local NODE_WIDTH = 178
local NODE_HEIGHT = 88
local PORT_SIZE = 14
local CONNECTOR_THICKNESS = 2
local CONNECTOR_LANE_GAP = 14

local NODE_TYPES = {
    spell_event = {
        label = "Spell",
        kind = "Event",
        icon = "Interface\\Icons\\Spell_arcane_blast",
        color = { 0.15, 0.48, 0.8 },
        picker = "spell",
    },
    condition = {
        label = "Condition",
        kind = "Condition",
        icon = "Interface\\Icons\\Ability_rogue_detecttraps",
        color = { 0.83, 0.58, 0.18 },
    },
    toy_action = {
        label = "Toy",
        kind = "Action",
        icon = "Interface\\Icons\\INV_Misc_Toy_10",
        color = { 0.2, 0.72, 0.42 },
        picker = "toy",
    },
    spell_action = {
        label = "Cast Spell",
        kind = "Action",
        icon = "Interface\\Icons\\Spell_holy_flashheal",
        color = { 0.2, 0.72, 0.42 },
        picker = "spell",
    },
    sound_action = {
        label = "Sound",
        kind = "Action",
        icon = "Interface\\Icons\\INV_Misc_Horn_03",
        color = { 0.2, 0.72, 0.42 },
        picker = "sound",
    },
    animation_action = {
        label = "Animation",
        kind = "Action",
        icon = "Interface\\Icons\\INV_Enchant_EssenceEternalLarge",
        color = { 0.2, 0.72, 0.42 },
        picker = "animation",
    },
    chat_action = {
        label = "Chat",
        kind = "Action",
        icon = "Interface\\Icons\\UI_Chat",
        color = { 0.2, 0.72, 0.42 },
        picker = "chat",
    },
}

local PALETTE_SECTIONS = {
    { title = "Triggers", types = { "spell_event" } },
    { title = "Logic", types = { "condition" } },
    { title = "Actions", types = { "spell_action", "toy_action", "sound_action", "animation_action", "chat_action" } },
}

local function ApplyGoldButtonStyle(button)
    if OxedHub.UIComponents and OxedHub.UIComponents.Button then
        OxedHub.UIComponents.Button.ApplyGoldStyle(button)
    end
end

local function ApplyPanelBackdrop(frame, alpha)
    if OxedHub.UIComponents and OxedHub.UIComponents.Panel then
        OxedHub.UIComponents.Panel.ApplyBlackWorkBackdrop(frame, alpha or 0.92)
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.04, 0.04, 0.05, alpha or 0.92)
    frame:SetBackdropBorderColor(0.32, 0.32, 0.36, 1)
end

local function Clamp(value, minValue, maxValue)
    return math.max(minValue, math.min(maxValue, value))
end

local function TextMatches(text, query)
    if not query or query == "" then
        return true
    end
    return strlower(tostring(text or "")):find(strlower(query), 1, true) ~= nil
end

local function AddOption(options, value, label, icon)
    if not value or not label then
        return
    end
    options[#options + 1] = {
        value = tostring(value),
        label = tostring(label),
        icon = icon,
    }
end

local function SearchSpellOptions(query)
    local options = {}
    local numericId = tonumber(query)
    if numericId and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(numericId)
        if info and info.name then
            AddOption(options, info.spellID or numericId, info.name, info.iconID)
        end
    end

    if query and query ~= "" and C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        local lowerQuery = strlower(query)
        local count = C_SpellBook.GetNumSpellBookSkillLines() or 0
        for skillLineIndex = 1, count do
            local skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)
            if skillLineInfo then
                local spellCount = skillLineInfo.numSpellBookItems or 0
                local firstIndex = skillLineInfo.itemIndexOffset or 1
                for spellIndex = firstIndex, firstIndex + spellCount - 1 do
                    local spellInfo = C_SpellBook.GetSpellBookItemInfo(spellIndex, Enum.SpellBookSpellBank.Player)
                    if spellInfo and spellInfo.spellID then
                        local spellName = C_SpellBook.GetSpellBookItemName(spellIndex, Enum.SpellBookSpellBank.Player)
                        if spellName and strlower(spellName):find(lowerQuery, 1, true) then
                            AddOption(options, spellInfo.spellID, spellName, C_SpellBook.GetSpellBookItemTexture(spellIndex, Enum.SpellBookSpellBank.Player))
                            if #options >= 10 then
                                return options
                            end
                        end
                    end
                end
            end
        end
    end

    return options
end

local function SearchToyOptions(query)
    local options = {}
    if OxedHub.Toys and OxedHub.Toys.EnsureToyData then
        OxedHub.Toys:EnsureToyData(true)
    end

    local toyIDs = OxedHub.Toys and OxedHub.Toys.toyIDs or {}
    local toyCache = OxedHub.Toys and OxedHub.Toys.toyCache or {}
    for _, itemID in ipairs(toyIDs) do
        local data = toyCache[itemID]
        if data and TextMatches(data.name, query) then
            AddOption(options, itemID, data.name, data.icon)
            if #options >= 10 then
                return options
            end
        end
    end

    if #options == 0 and tonumber(query) and C_ToyBox and C_ToyBox.GetToyInfo then
        local _, toyName, icon = C_ToyBox.GetToyInfo(tonumber(query))
        AddOption(options, tonumber(query), toyName, icon)
    end

    return options
end

local function SearchTableOptions(source, query)
    local options = {}
    for id, data in pairs(source or {}) do
        local label = type(data) == "table" and (data.name or data.text or id) or id
        if TextMatches(label, query) or TextMatches(id, query) then
            AddOption(options, id, label, type(data) == "table" and data.icon)
            if #options >= 10 then
                return options
            end
        end
    end
    return options
end

local function GetPickerOptions(pickerType, query)
    if pickerType == "spell" then
        return SearchSpellOptions(query)
    elseif pickerType == "toy" then
        return SearchToyOptions(query)
    elseif pickerType == "sound" then
        local sounds = OxedHub.GetSharedCustomSounds and OxedHub:GetSharedCustomSounds() or (OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.customSounds)
        return SearchTableOptions(sounds, query)
    elseif pickerType == "animation" then
        return SearchTableOptions(OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.animations, query)
    elseif pickerType == "chat" then
        return SearchTableOptions(OxedHub.db and OxedHub.db.profile and OxedHub.db.profile.chatTemplates, query)
    end
    return {}
end

local function GetSelectedLabel(node)
    if node and node.selection and node.selection.label then
        return node.selection.label
    end
    return "Select..."
end

local function GetSelectedIcon(node, spec)
    if node and node.selection and node.selection.icon then
        return node.selection.icon
    end
    return spec and spec.icon
end

local function GetNodeSpec(node)
    return node and (NODE_TYPES[node.type] or NODE_TYPES.sound_action) or nil
end

local function NodeHasInput(node)
    local spec = GetNodeSpec(node)
    return spec and (spec.kind == "Condition" or spec.kind == "Action") or false
end

local function NodeHasOutput(node)
    local spec = GetNodeSpec(node)
    return spec and (spec.kind == "Event" or spec.kind == "Condition") or false
end

local function IsValidLink(fromNode, toNode)
    if not fromNode or not toNode or fromNode.id == toNode.id then
        return false
    end
    return NodeHasOutput(fromNode) and NodeHasInput(toNode)
end

function Experimental:EnsureGraph()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then
        return nil
    end

    profile.experimental = profile.experimental or {}
    profile.experimental.graph = profile.experimental.graph or {}

    local graph = profile.experimental.graph
    graph.nodes = graph.nodes or {}
    graph.links = graph.links or {}
    graph.nextNodeId = tonumber(graph.nextNodeId) or 1

    for _, node in ipairs(graph.nodes) do
        if node.type == "event" then
            node.type = "spell_event"
        elseif node.type == "action" then
            node.type = "sound_action"
        end
    end

    local nodesById = {}
    for _, node in ipairs(graph.nodes) do
        nodesById[node.id] = node
    end

    for index = #graph.links, 1, -1 do
        local link = graph.links[index]
        if not IsValidLink(nodesById[link.from], nodesById[link.to]) then
            table.remove(graph.links, index)
        end
    end

    return graph
end

function Experimental:CreateTab(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints(parent)
    tab:SetID(8)
    if OxedHub.UI and OxedHub.UI.ApplyToysBackground then
        OxedHub.UI.ApplyToysBackground(tab)
    end
    local insetLeft, insetRight, insetTop, insetBottom = 42, 56, 66, 54
    if OxedHub.UI and OxedHub.UI.GetThemedFrameInsets then
        insetLeft, insetRight, insetTop, insetBottom = OxedHub.UI:GetThemedFrameInsets()
    end

    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -insetTop)
    title:SetText("Experimental")
    title:SetTextColor(1, 0.82, 0, 1)
    title:Hide()

    local subtitle = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Flow: triggers -> conditions -> actions")

    local palette = CreateFrame("Frame", nil, tab, "BackdropTemplate")
    palette:SetPoint("TOPLEFT", tab, "TOPLEFT", insetLeft, -(insetTop + 8))
    palette:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", insetLeft, insetBottom)
    palette:SetWidth(PALETTE_WIDTH)
    ApplyPanelBackdrop(palette, 0.9)
    tab.palette = palette

    local paletteTitle = palette:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    paletteTitle:SetPoint("TOPLEFT", palette, "TOPLEFT", 12, -12)
    paletteTitle:SetText("Blocks")
    paletteTitle:SetTextColor(1, 0.82, 0, 1)

    local y = -40
    for _, section in ipairs(PALETTE_SECTIONS) do
        local sectionLabel = palette:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sectionLabel:SetPoint("TOPLEFT", palette, "TOPLEFT", 14, y)
        sectionLabel:SetText(section.title)
        y = y - 18

        for _, nodeType in ipairs(section.types) do
            local buttonNodeType = nodeType
            local spec = NODE_TYPES[nodeType]
            local btn = CreateFrame("Button", nil, palette, "UIPanelButtonTemplate")
            ApplyGoldButtonStyle(btn)
            btn:SetPoint("TOPLEFT", palette, "TOPLEFT", 12, y)
            btn:SetSize(PALETTE_WIDTH - 24, 24)
            btn:SetText("Add " .. spec.label)
            btn:SetScript("OnClick", function()
                Experimental:AddNode(buttonNodeType)
            end)
            y = y - 30
        end

        y = y - 8
    end

    local clearBtn = CreateFrame("Button", nil, palette, "UIPanelButtonTemplate")
    ApplyGoldButtonStyle(clearBtn)
    clearBtn:SetPoint("BOTTOMLEFT", palette, "BOTTOMLEFT", 12, 12)
    clearBtn:SetSize(PALETTE_WIDTH - 24, 24)
    clearBtn:SetText("Reset Graph")
    clearBtn:SetScript("OnClick", function()
        Experimental:ResetGraph()
    end)

    local canvas = CreateFrame("Frame", "OxedHubExperimentalCanvas", tab, "BackdropTemplate")
    canvas:SetPoint("TOPLEFT", palette, "TOPRIGHT", 10, 0)
    canvas:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -insetRight, insetBottom)
    ApplyPanelBackdrop(canvas, 0.96)
    canvas:EnableMouse(true)
    tab.canvas = canvas

    self.tab = tab
    self.canvas = canvas
    self.nodeFrames = {}
    self.lineFrames = {}
    self.gridDots = {}
    self:CreateGrid(canvas)

    tab:Hide()
    parent.Experimental = tab
    self:RefreshTab()
end

function Experimental:CreateGrid(canvas)
    if not canvas then return end
    local cols, rows = 38, 22
    for row = 1, rows do
        for col = 1, cols do
            local dot = canvas:CreateTexture(nil, "BACKGROUND")
            dot:SetSize(1, 1)
            dot:SetPoint("TOPLEFT", canvas, "TOPLEFT", 18 + ((col - 1) * 24), -18 - ((row - 1) * 24))
            dot:SetColorTexture(0.38, 0.38, 0.42, 0.35)
            table.insert(self.gridDots, dot)
        end
    end
end

function Experimental:RefreshTab()
    if not self.canvas then return end
    self:ClearCanvasObjects()

    local graph = self:EnsureGraph()
    if not graph then return end

    for _, node in ipairs(graph.nodes) do
        self:CreateNodeFrame(node)
    end
    self:RefreshLinks()
end

function Experimental:ClearCanvasObjects()
    for _, line in ipairs(self.lineFrames or {}) do
        line:Hide()
        if line.SetParent then line:SetParent(nil) end
    end
    for _, nodeFrame in pairs(self.nodeFrames or {}) do
        nodeFrame:Hide()
        nodeFrame:SetParent(nil)
    end
    self.lineFrames = {}
    self.nodeFrames = {}
end

function Experimental:AddNode(nodeType)
    local graph = self:EnsureGraph()
    if not graph then return end

    local spec = NODE_TYPES[nodeType] or NODE_TYPES.sound_action
    local nodeId = "node_" .. tostring(graph.nextNodeId or 1)
    graph.nextNodeId = (tonumber(graph.nextNodeId) or 1) + 1

    table.insert(graph.nodes, {
        id = nodeId,
        type = nodeType,
        label = spec.label,
        x = 80 + ((#graph.nodes % 3) * 210),
        y = 80 + (math.floor(#graph.nodes / 3) * 110),
    })

    self:RefreshTab()
end

function Experimental:ResetGraph()
    local profile = OxedHub.db and OxedHub.db.profile
    if not profile then return end

    profile.experimental = {
        graph = {
            nextNodeId = 4,
            nodes = {
                { id = "node_1", type = "spell_event", label = "Spell Cast", x = 70, y = 80 },
                { id = "node_2", type = "condition", label = "Checks", x = 330, y = 80 },
                { id = "node_3", type = "sound_action", label = "Sound", x = 590, y = 80 },
            },
            links = {
                { from = "node_1", to = "node_2" },
                { from = "node_2", to = "node_3" },
            },
        },
    }

    self.pendingConnection = nil
    self:RefreshTab()
end

function Experimental:GetNodeById(nodeId)
    local graph = self:EnsureGraph()
    if not graph then return nil end

    for _, node in ipairs(graph.nodes) do
        if node.id == nodeId then
            return node
        end
    end
    return nil
end

function Experimental:CreateNodeFrame(node)
    if not self.canvas or not node then return end

    local spec = NODE_TYPES[node.type] or NODE_TYPES.sound_action
    local frame = CreateFrame("Frame", nil, self.canvas, "BackdropTemplate")
    frame:SetSize(NODE_WIDTH, NODE_HEIGHT)
    frame:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", node.x or 40, -(node.y or 40))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame.nodeId = node.id
    frame:SetFrameLevel(self.canvas:GetFrameLevel() + 20)
    ApplyPanelBackdrop(frame, 0.95)

    local stripe = frame:CreateTexture(nil, "BORDER")
    stripe:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    stripe:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, 4)
    stripe:SetWidth(4)
    stripe:SetColorTexture(spec.color[1], spec.color[2], spec.color[3], 1)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", frame, "LEFT", 16, 0)
    icon:SetTexture(GetSelectedIcon(node, spec))

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 10)
    label:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    label:SetJustifyH("LEFT")
    label:SetText(node.label or spec.label)

    local typeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    typeLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    typeLabel:SetText(spec.kind or spec.label)

    if spec.picker then
        local selector = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        selector:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, -8)
        selector:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
        selector:SetHeight(20)
        selector:SetText(GetSelectedLabel(node))
        selector:SetScript("OnClick", function()
            Experimental:ShowPicker(node.id, spec.picker, selector)
        end)
        frame.selector = selector
    end

    if NodeHasInput(node) then
        local input = self:CreatePort(frame, "input")
        input:SetPoint("LEFT", frame, "LEFT", -(PORT_SIZE / 2), 0)
        frame.inputPort = input
    end

    if NodeHasOutput(node) then
        local output = self:CreatePort(frame, "output")
        output:SetPoint("RIGHT", frame, "RIGHT", PORT_SIZE / 2, 0)
        frame.outputPort = output
    end

    frame:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        Experimental:SaveNodePosition(selfFrame)
        Experimental:RefreshLinks()
    end)

    self.nodeFrames[node.id] = frame
    return frame
end

function Experimental:CreatePort(parent, portType)
    local port = CreateFrame("Button", nil, parent, "BackdropTemplate")
    port:SetSize(PORT_SIZE, PORT_SIZE)
    port:SetFrameLevel(parent:GetFrameLevel() + 10)
    port.portType = portType
    port.nodeId = parent.nodeId
    port:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
    })

    if portType == "output" then
        port:SetBackdropColor(0.3, 0.85, 0.55, 1)
    else
        port:SetBackdropColor(0.48, 0.58, 0.9, 1)
    end
    port:SetBackdropBorderColor(0.8, 0.8, 0.85, 1)

    port:SetScript("OnClick", function(selfPort)
        if selfPort.portType == "output" then
            Experimental.pendingConnection = selfPort.nodeId
            Experimental:RefreshPortStates()
        elseif Experimental.pendingConnection and Experimental.pendingConnection ~= selfPort.nodeId then
            Experimental:AddLink(Experimental.pendingConnection, selfPort.nodeId)
            Experimental.pendingConnection = nil
            Experimental:RefreshTab()
        else
            Experimental.pendingConnection = nil
            Experimental:RefreshPortStates()
        end
    end)

    port:SetScript("OnEnter", function(selfPort)
        GameTooltip:SetOwner(selfPort, "ANCHOR_RIGHT")
        if selfPort.portType == "output" then
            GameTooltip:SetText("Output")
            GameTooltip:AddLine("Click, then click an input port.", 0.8, 0.8, 0.8, true)
        else
            GameTooltip:SetText("Input")
            GameTooltip:AddLine("Receives flow from a trigger or condition.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    port:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return port
end

function Experimental:RefreshPortStates()
    for nodeId, nodeFrame in pairs(self.nodeFrames or {}) do
        if nodeFrame.outputPort then
            if self.pendingConnection == nodeId then
                nodeFrame.outputPort:SetBackdropColor(1, 0.82, 0, 1)
            else
                nodeFrame.outputPort:SetBackdropColor(0.3, 0.85, 0.55, 1)
            end
        end
    end
end

function Experimental:CreatePicker()
    if self.picker then
        return self.picker
    end

    local picker = CreateFrame("Frame", "OxedHubExperimentalPicker", UIParent, "BackdropTemplate")
    picker:SetSize(320, 330)
    picker:SetFrameStrata("DIALOG")
    picker:SetFrameLevel(200)
    ApplyPanelBackdrop(picker, 0.98)
    picker:EnableMouse(true)
    picker:Hide()

    local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", picker, "TOPLEFT", 12, -12)
    title:SetTextColor(1, 0.82, 0, 1)
    picker.title = title

    local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function()
        picker:Hide()
    end)

    local search = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    search:SetSize(282, 22)
    search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 4, -10)
    search:SetAutoFocus(false)
    picker.search = search

    local rows = {}
    for i = 1, 10 do
        local row = CreateFrame("Button", nil, picker, "BackdropTemplate")
        row:SetSize(292, 24)
        row:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -4, -8 - ((i - 1) * 26))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row:SetBackdropColor(0.08, 0.08, 0.09, 0.75)

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")

        row:SetScript("OnClick", function(selfRow)
            Experimental:SelectPickerOption(selfRow.option)
        end)
        rows[i] = row
    end
    picker.rows = rows

    local empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 2, -14)
    empty:SetText("Search to choose a value.")
    picker.empty = empty

    search:SetScript("OnTextChanged", function(selfEdit)
        Experimental:RefreshPickerList(selfEdit:GetText() or "")
    end)

    self.picker = picker
    return picker
end

function Experimental:ShowPicker(nodeId, pickerType, anchor)
    local picker = self:CreatePicker()
    picker.nodeId = nodeId
    picker.pickerType = pickerType
    picker.title:SetText("Select " .. pickerType)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor or self.canvas or UIParent, "BOTTOMLEFT", 0, -6)
    picker:Show()
    picker.search:SetText("")
    picker.search:SetFocus()
    self:RefreshPickerList("")
end

function Experimental:RefreshPickerList(query)
    local picker = self.picker
    if not picker or not picker:IsShown() then return end

    local options = GetPickerOptions(picker.pickerType, query or "")
    for i, row in ipairs(picker.rows) do
        local option = options[i]
        row.option = option
        if option then
            row.icon:SetTexture(option.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(option.label)
            row:Show()
        else
            row:Hide()
        end
    end

    if #options == 0 then
        picker.empty:SetText((query and query ~= "") and "No matches found." or "Search to choose a value.")
        picker.empty:Show()
    else
        picker.empty:Hide()
    end
end

function Experimental:SelectPickerOption(option)
    if not option or not self.picker then return end

    local node = self:GetNodeById(self.picker.nodeId)
    if not node then return end

    node.selection = {
        value = option.value,
        label = option.label,
        icon = option.icon,
    }
    node.label = option.label

    self.picker:Hide()
    self:RefreshTab()
end

function Experimental:SaveNodePosition(frame)
    if not frame or not self.canvas then return end
    local node = self:GetNodeById(frame.nodeId)
    if not node then return end

    local canvasLeft = self.canvas:GetLeft() or 0
    local canvasTop = self.canvas:GetTop() or 0
    local canvasWidth = self.canvas:GetWidth() or 800
    local canvasHeight = self.canvas:GetHeight() or 500
    local frameLeft = frame:GetLeft() or canvasLeft
    local frameTop = frame:GetTop() or canvasTop

    node.x = Clamp(frameLeft - canvasLeft, 8, math.max(8, canvasWidth - NODE_WIDTH - 8))
    node.y = Clamp(canvasTop - frameTop, 8, math.max(8, canvasHeight - NODE_HEIGHT - 8))

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", self.canvas, "TOPLEFT", node.x, -node.y)
end

function Experimental:AddLink(fromNodeId, toNodeId)
    local graph = self:EnsureGraph()
    if not graph then return end
    local fromNode = self:GetNodeById(fromNodeId)
    local toNode = self:GetNodeById(toNodeId)
    if not IsValidLink(fromNode, toNode) then
        return
    end

    for index = #graph.links, 1, -1 do
        local link = graph.links[index]
        if link.from == fromNodeId and link.to == toNodeId then
            table.remove(graph.links, index)
            self:RefreshLinks()
            return
        end
        if link.to == toNodeId then
            table.remove(graph.links, index)
        end
    end

    table.insert(graph.links, { from = fromNodeId, to = toNodeId })
    self:RefreshLinks()
end

function Experimental:CreateConnectorSegment(parent, x1, y1, x2, y2)
    if not parent then
        return
    end

    local tex = parent:CreateTexture(nil, "BACKGROUND")
    tex:SetColorTexture(0.62, 0.68, 0.78, 0.8)

    local dx = x2 - x1
    local dy = y2 - y1
    if math.abs(dx) >= math.abs(dy) then
        local width = math.max(CONNECTOR_THICKNESS, math.abs(dx))
        tex:SetSize(width, CONNECTOR_THICKNESS)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", math.min(x1, x2), -(y1 + (CONNECTOR_THICKNESS / 2)))
    else
        local height = math.max(CONNECTOR_THICKNESS, math.abs(dy))
        tex:SetSize(CONNECTOR_THICKNESS, height)
        tex:SetPoint("TOPLEFT", parent, "TOPLEFT", x1 - (CONNECTOR_THICKNESS / 2), -math.min(y1, y2))
    end
    tex:Show()
end

function Experimental:CreateConnector(fromNode, toNode, laneIndex)
    if not self.canvas or not fromNode or not toNode then
        return nil
    end

    local startX = (fromNode.x or 0) + NODE_WIDTH + (PORT_SIZE / 2)
    local startY = (fromNode.y or 0) + (NODE_HEIGHT / 2)
    local endX = (toNode.x or 0) - (PORT_SIZE / 2)
    local endY = (toNode.y or 0) + (NODE_HEIGHT / 2)
    local laneOffset = ((laneIndex or 1) - 1) * CONNECTOR_LANE_GAP
    local routeX

    if endX > startX then
        routeX = startX + ((endX - startX) / 2) + laneOffset
    else
        routeX = math.max(startX, endX) + 42 + laneOffset
    end

    local connector = CreateFrame("Frame", nil, self.canvas)
    connector:SetAllPoints(self.canvas)
    connector:SetFrameLevel(self.canvas:GetFrameLevel() + 3)
    connector:EnableMouse(false)

    self:CreateConnectorSegment(connector, startX, startY, routeX, startY)
    self:CreateConnectorSegment(connector, routeX, startY, routeX, endY)
    self:CreateConnectorSegment(connector, routeX, endY, endX, endY)
    connector:Show()

    return connector
end

function Experimental:RefreshLinks()
    if not self.canvas then return end

    for _, line in ipairs(self.lineFrames or {}) do
        line:Hide()
        if line.SetParent then line:SetParent(nil) end
    end
    self.lineFrames = {}

    local graph = self:EnsureGraph()
    if not graph then return end

    local outgoingCounts = {}
    for _, link in ipairs(graph.links) do
        local fromNode = self:GetNodeById(link.from)
        local toNode = self:GetNodeById(link.to)
        outgoingCounts[link.from] = (outgoingCounts[link.from] or 0) + 1
        local connector = self:CreateConnector(fromNode, toNode, outgoingCounts[link.from])
        if connector then
            table.insert(self.lineFrames, connector)
        end
    end
end
