local function AssertIntrinsicMessage(frame)
	return string.format("%s element is not a DropdownButton.", frame:GetDebugName());
end

function OxMLIsDropdownButtonIntrinsic(frame)
	return frame.intrinsic == "DropdownButton";
end

function OxMLValidateIsDropdownButtonIntrinsic(frame)
	assertsafe(OxMLIsDropdownButtonIntrinsic(frame), AssertIntrinsicMessage, frame);
end

--[[
Finds the previous and next selectable radios and all selections in a single pass.
This is recursive through the entire menu hierarchy.
]]--
local function CollectSelectionData(menuDescription)
	if not menuDescription then
		return nil, nil, {};
	end

	local firstSelected = nil;
	local nextRadio = nil;
	local previousDescriptions = {};
	local selections = {};

	OxMLMenuUtil.TraverseMenu(menuDescription, function(description)
		if description:IsSelectionIgnored() then
			return;
		end

		local selected = description:IsSelected();
		if selected then
			table.insert(selections, description);
		end

		local isRadio = description:IsRadio();

		-- Assign the next selectable description after a current selection has been found.
		if (nextRadio == nil) and (firstSelected ~= nil) and (not selected) and isRadio and description:CanSelect() then
			nextRadio = description;
		end
	
		if isRadio and selected and (firstSelected == nil)then
			firstSelected = description;
		end

		--[[
		Add a previous candidate as long as a current selection has not been found. More efficient to
		check radio state here than insert into the table needlessly.
		]]--
		if isRadio and not firstSelected then
			table.insert(previousDescriptions, description);
		end
	end);

	-- Reverse iterate the previous descriptions for the first candidate.
	local previousRadio = nil;
	for index, description in ipairs_reverse(previousDescriptions) do
		if description:CanSelect() then
			previousRadio = description;
			break;
		end
	end

	return previousRadio, nextRadio, selections;
end

OxMLDropdownButtonMixin = CreateFromMixins(CallbackRegistryMixin);

OxMLDropdownButtonMixin:GenerateCallbackEvents(
	{
		"OnUpdate",
		"OnMenuOpen",
		"OnMenuClose",
	}
);

function OxMLDropdownButtonMixin:OnLoad_Intrinsic()
	CallbackRegistryMixin.OnLoad(self);

	self:EnableMouseWheel(false);
	self:RegisterForMouse("LeftButtonDown", "LeftButtonUp");

	self.onMenuClosedCallback = function(menu, closeReason)
		self.menu = nil;
		self:OnMenuClosed(menu, closeReason);
	end

	local anchor = AnchorUtil.CreateAnchor(self.menuPoint, self, self.menuRelativePoint, self.menuPointX, self.menuPointY);
	self:SetMenuAnchor(anchor);
end

function OxMLDropdownButtonMixin:OnEnter_Intrinsic()
	if self.canOpenOnEnter then
		self:OpenMenu();
	end
end

function OxMLDropdownButtonMixin:OnMouseDown_Intrinsic()
	if IsShiftKeyDown() then
		return;
	end

	self:SetMenuOpen(not self:IsMenuOpen());
end

function OxMLDropdownButtonMixin:OpenMenu()
	if not self:IsEnabled() then
		return;
	end

	if self:IsMenuOpen() then
		return;
	end

	-- Always regenerate the menu. This is important to avoid bugs related to stale menu state.
	self:GenerateMenu();

	if not self.menuDescription then
		return;
	end

	local menu = OxMLMenu.GetManager():OpenMenu(self, self.menuDescription, self.menuAnchor); 
	self.menu = menu;
	if menu then
		menu:SetClosedCallback(self.onMenuClosedCallback);

		self:OnMenuOpened(menu);
	end
end

function OxMLDropdownButtonMixin:CloseMenu()
	if self.menu then
		self.menu:Close();
		self.menu = nil;
	end

	-- Contents of the menu may require an update when the menu is closed. 
	self:SignalUpdate();
end

function OxMLDropdownButtonMixin:SetMenuOpen(open)
	if open then
		self:OpenMenu();
	else
		self:CloseMenu();
	end
end

function OxMLDropdownButtonMixin:OnMouseWheel_Intrinsic(delta)
	if self.mouseWheelDisabledThisFrame then
		return;
	end

	if not self:IsEnabled() then
		return;
	end

	self.mouseWheelDisabledThisFrame = true;
	self:SetScript("OnUpdate", function()
		self.mouseWheelDisabledThisFrame = false;
		self:SetScript("OnUpdate", nil);
	end);

	local forward = delta < 0;
	self:Rotate(forward);
end

function OxMLDropdownButtonMixin:SetMenuAnchor(anchor)
	self.menuAnchor = anchor;
end

function OxMLDropdownButtonMixin:HandlesGlobalMouseEvent(buttonName, event)
	return event == "GLOBAL_MOUSE_DOWN" and buttonName == "LeftButton";
end

function OxMLDropdownButtonMixin:RegisterMenu(menuDescription)
	assert(type(menuDescription) == "table");
	self.menuDescription = menuDescription;

	menuDescription:AddMenuResponseCallback(function(menu, description)
		self:OnMenuResponse(menu, description);
	end);

	menuDescription:AddMenuChangedCallback(function()
		self:OnMenuChanged();
	end);

	local minimumWidth = menuDescription:GetMinimumWidth() or 0;
	if minimumWidth == 0 then
		menuDescription:SetMinimumWidth(self:GetWidth());
	end

	if self.menu then
		--[[
		The menu is already open. Overwriting the menu description will cause the
		menu to be reinitialized without closing.
		]]--
		self.menu:SetMenuDescription(menuDescription);
	end

	securecallfunction(self.OnMenuAssigned, self);
end

--[[ 
Used rarely to restore the dropdown to an uninitialized state. 
This should generally be ignored in the API.
]]--
function OxMLDropdownButtonMixin:ClearMenuState()
	self.menuDescription = nil;
	self.menuGenerator = nil;

	self:CloseMenu();
end

--[[
Returns the menu description that was either explicitly assigned or generated. Will return
nil if a description was never created.
]]--
function OxMLDropdownButtonMixin:GetMenuDescription()
	return self.menuDescription;
end

--[[
Returns the number of visible description elements in the root description. Will return
false if a description was never created.
]]--
function OxMLDropdownButtonMixin:HasElements()
	return self.menuDescription and self.menuDescription:HasElements() or false;
end

--[[
The primary point of menu registration. Expects a generator function with the following signature:
function(dropdown, rootDescription) ... end
]]--
function OxMLDropdownButtonMixin:SetupMenu(generator)
	assert(type(generator) == "function", "OxMLDropdownButtonMixin:SetupMenu(generator): argument is not a function.");
	self.menuGenerator = generator;
		
	--[[
	We need to generate the menu immediately if this dropdown is shown else selected options
	won't be reflected in the dropdown's text. Otherwise, we can defer generation until the 
	OnShow script is called.
	]]--
	if self:IsShown() then
		self:GenerateMenu();
	end
end

local function PopulateDescription(self, menuGenerator, rootDescription)
	OxMLMenu.PopulateDescription(menuGenerator, self, rootDescription);
end

function OxMLDropdownButtonMixin:GenerateMenu()
	local menuGenerator = self.menuGenerator;
	if not menuGenerator then
		return;
	end

	local rootDescription = self:CreateDefaultRootMenuDescription();
	securecallfunction(PopulateDescription, self, menuGenerator, rootDescription);
	self:RegisterMenu(rootDescription);
end

function OxMLDropdownButtonMixin:CreateDefaultRootMenuDescription()
	local menuMixin = self.menuMixin or OxMLMenuVariants.GetDefaultMenuMixin();
	return self:CreateRootDescription(menuMixin);
end

function OxMLDropdownButtonMixin:CreateRootDescription(menuMixin)
	return OxMLMenuUtil.CreateRootMenuDescription(menuMixin);
end

function OxMLDropdownButtonMixin:IsMenuOpen()
	return self.menu ~= nil;
end

function OxMLDropdownButtonMixin:SignalUpdate()
	--[[
	The selection list is routed through the CBR and Update() function to avoid
	multiple redundant traversals, particularly when the traversal list is quite large
	such as it is in character customization.
	]]--
	local previousRadio, nextRadio, selections = CollectSelectionData(self:GetMenuDescription());
	self:TriggerEvent(OxMLDropdownButtonMixin.Event.OnUpdate, previousRadio, nextRadio, selections);
	self:UpdateSelections(selections);
end

function OxMLDropdownButtonMixin:OnMenuResponse(menu, description)
	--[[
	A response may change the underlying data and require the root or child menus to be regenerated prior
	to evaluating selected options. Because of the rarity of this scenario, this is opt-in behavior.
	--]]
	if self.shouldRegenerateOnResponse then
		self:GenerateMenu();
	else
		self:SignalUpdate();
	end
end

function OxMLDropdownButtonMixin:EnableRegenerateOnResponse()
	self.shouldRegenerateOnResponse = true;
end

function OxMLDropdownButtonMixin:OnMenuAssigned()
	self:SignalUpdate();
end

function OxMLDropdownButtonMixin:OnMenuChanged()
	self:SignalUpdate();
end

function OxMLDropdownButtonMixin:OnMenuOpened(menu)
	PlaySound(OxMLMenuVariants.GetDropdownOpenSoundKit());

	self:TriggerEvent(OxMLDropdownButtonMixin.Event.OnMenuOpen, self);
end

function OxMLDropdownButtonMixin:OnMenuClosed(menu, closeReason)
	PlaySound(OxMLMenuVariants.GetDropdownCloseSoundKit());

	self:TriggerEvent(OxMLDropdownButtonMixin.Event.OnMenuClose, self, menu, closeReason);
end

function OxMLDropdownButtonMixin:UpdateSelections(selections)
	self:UpdateToMenuSelections(self:GetMenuDescription(), selections);
end

function OxMLDropdownButtonMixin:Update()
	self:SignalUpdate();
end

function OxMLDropdownButtonMixin:UpdateToMenuSelections(menuDescription, selections)
	--[[
	Should be implemented by the derivation if it needs to display selections. Some
	dropdowns have a fixed text and do not need this.
	]]--
end

function OxMLDropdownButtonMixin:Pick(description, menuInputContext, menuInputButtonName)
	if description then
		local responded = description:Pick(menuInputContext, menuInputButtonName);
		if responded then
			self:UpdateToMenuSelections(self:GetMenuDescription());
			return true;
		end
	end
	return false;
end


function OxMLDropdownButtonMixin:Rotate(forward)
	if forward then
		self:Increment();
	else
		self:Decrement();
	end
end

function OxMLDropdownButtonMixin:HasAnyRadioDescriptions()
	return OxMLMenuUtil.TraverseMenu(self:GetMenuDescription(), function(description)
		return description:IsRadio();
	end);
end

function OxMLDropdownButtonMixin:Increment()
	local previousRadio, nextRadio, selections = CollectSelectionData(self:GetMenuDescription());
	self:Pick(nextRadio, OxMLMenuInputContext.MouseWheel);
end

function OxMLDropdownButtonMixin:Decrement()
	local previousRadio, nextRadio, selections = CollectSelectionData(self:GetMenuDescription())
	self:Pick(previousRadio, OxMLMenuInputContext.MouseWheel);
end

function OxMLDropdownButtonMixin:CollectSelectionData()
	return CollectSelectionData(self:GetMenuDescription());
end

function OxMLDropdownButtonMixin:GetSelectionData()
	local data = CollectSelectionData(self:GetMenuDescription());
	return data and data[1] or nil;
end

function OxMLDropdownButtonMixin:HasStickyFocus()
	--[[ 
	Allows controls to retain focus in case a menu option feeds informaton 
	to a focused editbox at it's current caret position.
	]]--
	return self:IsMouseOver() or (self.menu and self.menu:IsMouseOver());
end

-- Routes script calls to a dropdown button and causes the dropdown to respond
-- as if it were actually pressed. If more scripts are required, feel free to add them;
-- they'll only be invoked if the element defines the script for it.
OxMLDropdownButtonProxyMixin = {};

function OxMLDropdownButtonProxyMixin:GetRouteSibling()
	return self:GetParent()[self.routeToSibling];
end

function OxMLDropdownButtonProxyMixin:RouteScript(scriptName, ...)
	local button = self:GetRouteSibling();
	button:GetScript(scriptName)(button, ...);
end

function OxMLDropdownButtonProxyMixin:OnEnter(...)
	self:RouteScript("OnEnter", ...);
end

function OxMLDropdownButtonProxyMixin:OnLeave(...)
	self:RouteScript("OnLeave", ...);
end

function OxMLDropdownButtonProxyMixin:OnMouseDown(...)
	-- Send the OnMouseDown with the first argument replaced.
	OxMLDropdownButtonMixin.OnMouseDown_Intrinsic(self:GetRouteSibling(), select(2, ...));
end

function OxMLDropdownButtonProxyMixin:HandlesGlobalMouseEvent(buttonName, event)
	return event == "GLOBAL_MOUSE_DOWN" and buttonName == "LeftButton";
end
