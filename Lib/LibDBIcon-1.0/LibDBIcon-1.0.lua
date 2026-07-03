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

local ICON_TYPE = "data source"
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

LibDBIcon.objects = LibDBIcon.objects or {}
LibDBIcon.notCreated = LibDBIcon.notCreated or {}
LibDBIcon.callbacks = LibDBIcon.callbacks or LibStub("CallbackHandler-1.0"):New(LibDBIcon)

local function getObjectName(name)
	return "LibDBIcon10_"..name
end

local function onEnter(self)
	if self.obj.OnTooltipShow then
		self.obj.OnTooltipShow(self.tooltip)
	elseif self.obj.OnEnter then
		self.obj.OnEnter(self)
	end
	self.tooltip:Show()
end

local function onLeave(self)
	self.tooltip:Hide()
	if self.obj.OnLeave then
		self.obj.OnLeave(self)
	end
end

local function onClick(self, button)
	if self.obj.OnClick then
		self.obj.OnClick(self, button)
	end
end

local function createButton(name, object, data)
	local button = CreateFrame("Button", getObjectName(name), Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("LOW")
	button:SetPoint("CENTER", Minimap, "CENTER")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture()
	icon:SetAllPoints(button)
	icon:SetTexture(data.icon or object.icon or DEFAULT_ICON)
	button.icon = icon

	local overlay = button:CreateTexture()
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetAllPoints(button)
	overlay:SetTexCoord(0, 0.6, 0, 0.6)
	button.overlay = overlay

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		onEnter(self)
	end)
	button:SetScript("OnLeave", onLeave)
	button:SetScript("OnClick", onClick)

	button:RegisterForClicks("anyUp")
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	button:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local x, y = self:GetCenter()
		local scale = Minimap:GetScale()
		x, y = x / scale, y / scale
		local cx, cy = Minimap:GetCenter()
		local angle = math.atan2(y - cy, x - cx)
		local radius = math.sqrt((x - cx)^2 + (y - cy)^2)
		local position = math.deg(angle)
		if position < 0 then position = position + 360 end
		data.minimapPos = position
		data.radius = radius
		LibDBIcon:Refresh(name)
	end)

	button.obj = object
	button.data = data
	button.tooltip = GameTooltip

	return button
end

function LibDBIcon:Register(name, object, icon)
	if not object or not object.type then
		error("Invalid data object")
	end

	if object.type ~= ICON_TYPE then
		error("Unsupported data object type")
	end

	LibDBIcon.objects[name] = object
	LibDBIcon.notCreated[name] = icon or object.icon or DEFAULT_ICON

	LibDBIcon.callbacks:Fire("LibDBIcon_Register", name, object)
end

function LibDBIcon:Show(name)
	if not LibDBIcon.objects[name] then return end

	local data = LibDBIcon.db and LibDBIcon.db[name]
	if not data or not data.hide then
		if not _G[getObjectName(name)] then
			local button = createButton(name, LibDBIcon.objects[name], data or {})
			LibDBIcon.notCreated[name] = nil
		end
	end
end

function LibDBIcon:Hide(name)
	if _G[getObjectName(name)] then
		_G[getObjectName(name)]:Hide()
	end
end

function LibDBIcon:IsRegistered(name)
	return LibDBIcon.objects[name] ~= nil
end

function LibDBIcon:Refresh(name, data)
	if not LibDBIcon.objects[name] then return end

	local button = _G[getObjectName(name)]
	if not button then return end

	if data then
		button.data = data
	end

	if button.data and button.data.minimapPos then
		local angle = math.rad(button.data.minimapPos)
		local radius = button.data.radius or 80
		local cx, cy = Minimap:GetCenter()
		local x = cx + math.cos(angle) * radius
		local y = cy + math.sin(angle) * radius
		button:SetPoint("CENTER", Minimap, "CENTER", x - cx, y - cy)
	else
		button:SetPoint("CENTER", Minimap, "CENTER")
	end

	if button.data and button.data.hide then
		button:Hide()
	else
		button:Show()
	end
end

function LibDBIcon:NewDatabase(db, name)
	LibDBIcon.db = db
	LibDBIcon.name = name

	for n, object in pairs(LibDBIcon.objects) do
		if not db[n] then
			db[n] = { hide = false, minimapPos = math.random(0, 360) }
		end
		LibDBIcon:Show(n)
	end
end
