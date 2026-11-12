--[[
	LibDBIcon-1.0
	Allows addons to register a data broker object to be displayed via the minimap or other LDB display add-ons.
	All rights reserved.
	See below for licensing information.

	This file is part of a World of Warcraft AddOn.
]]

local MAJOR, MINOR = "LibDBIcon-1.0", 44
local LibDBIcon, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not LibDBIcon then return end

local LDB = LibStub("LibDataBroker-1.1", true)
if not LDB then return end

-- Minimap icons are LDB "launcher" objects; "data source" objects with an
-- icon are accepted too. Anything else is refused.
local ICON_TYPES = { ["launcher"] = true, ["data source"] = true }
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

LibDBIcon.objects = LibDBIcon.objects or {}      -- name -> button
LibDBIcon.notCreated = LibDBIcon.notCreated or {} -- name -> { object, db }
LibDBIcon.callbacks = LibDBIcon.callbacks or LibStub("CallbackHandler-1.0"):New(LibDBIcon)

local function getObjectName(name)
	return "LibDBIcon10_"..name
end

local function updatePosition(button)
	local db = button.db
	local angle = math.rad((db and db.minimapPos) or 225)
	local x, y = math.cos(angle), math.sin(angle)
	local rw = Minimap:GetWidth() / 2 + 5
	local rh = Minimap:GetHeight() / 2 + 5
	if GetMinimapShape and GetMinimapShape() == "SQUARE" then
		x = math.max(-rw, math.min(x * rw * 1.4142, rw))
		y = math.max(-rh, math.min(y * rh * 1.4142, rh))
	else
		x, y = x * rw, y * rh
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function onEnter(self)
	if self.isMoving then return end
	local obj = self.dataObject
	if obj.OnTooltipShow then
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint("TOPRIGHT", self, "BOTTOMLEFT")
		obj.OnTooltipShow(GameTooltip)
		GameTooltip:Show()
	elseif obj.OnEnter then
		obj.OnEnter(self)
	end
end

local function onLeave(self)
	GameTooltip:Hide()
	local obj = self.dataObject
	if obj.OnLeave then obj.OnLeave(self) end
end

local function onClick(self, button)
	local obj = self.dataObject
	if obj.OnClick then obj.OnClick(self, button) end
end

local function onDragUpdate(self)
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	px, py = px / scale, py / scale
	local pos = math.deg(math.atan2(py - my, px - mx)) % 360
	if self.db then self.db.minimapPos = pos end
	updatePosition(self)
end

local function onDragStart(self)
	if self.db and self.db.lock then return end
	self.isMoving = true
	GameTooltip:Hide()
	self:SetScript("OnUpdate", onDragUpdate)
end

local function onDragStop(self)
	self:SetScript("OnUpdate", nil)
	self.isMoving = nil
end

local function createButton(name, object, db)
	local button = CreateFrame("Button", getObjectName(name), Minimap)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetSize(31, 31)
	button:RegisterForClicks("anyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\Minimap\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\Minimap\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\Minimap\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture(object.icon or DEFAULT_ICON)
	button.icon = icon

	button.dataObject = object
	button.db = db

	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", onLeave)
	button:SetScript("OnClick", onClick)
	button:SetScript("OnDragStart", onDragStart)
	button:SetScript("OnDragStop", onDragStop)

	LibDBIcon.objects[name] = button
	LibDBIcon.notCreated[name] = nil
	updatePosition(button)
	LibDBIcon.callbacks:Fire("LibDBIcon_IconCreated", button, name)
	return button
end

-- Builds a button registered hidden, the first time it is wanted.
local function check(name)
	local pending = LibDBIcon.notCreated[name]
	if pending then createButton(name, pending[1], pending[2]) end
end

-- db is the icon's own saved table: hide, minimapPos, lock.
function LibDBIcon:Register(name, object, db)
	if type(object) ~= "table" or not ICON_TYPES[object.type] then
		error("Unsupported data object type")
	end
	if LibDBIcon.objects[name] or LibDBIcon.notCreated[name] then return end
	if type(db) ~= "table" then db = nil end

	if db and db.hide then
		LibDBIcon.notCreated[name] = { object, db }
	else
		createButton(name, object, db)
	end
	LibDBIcon.callbacks:Fire("LibDBIcon_Register", name, object)
end

function LibDBIcon:Show(name)
	check(name)
	local button = LibDBIcon.objects[name]
	if button then
		button:Show()
		updatePosition(button)
	end
end

function LibDBIcon:Hide(name)
	local button = LibDBIcon.objects[name]
	if button then button:Hide() end
end

function LibDBIcon:IsRegistered(name)
	return (LibDBIcon.objects[name] or LibDBIcon.notCreated[name]) and true or false
end

function LibDBIcon:GetMinimapButton(name)
	return LibDBIcon.objects[name]
end

function LibDBIcon:GetButtonList()
	local list = {}
	for name in pairs(LibDBIcon.objects) do list[#list + 1] = name end
	return list
end

function LibDBIcon:Lock(name)
	local button = LibDBIcon.objects[name]
	if button and button.db then button.db.lock = true end
end

function LibDBIcon:Unlock(name)
	local button = LibDBIcon.objects[name]
	if button and button.db then button.db.lock = nil end
end

function LibDBIcon:Refresh(name, db)
	check(name)
	local button = LibDBIcon.objects[name]
	if not button then return end
	if type(db) == "table" then button.db = db end
	updatePosition(button)
	if button.db and button.db.hide then
		button:Hide()
	else
		button:Show()
	end
end
