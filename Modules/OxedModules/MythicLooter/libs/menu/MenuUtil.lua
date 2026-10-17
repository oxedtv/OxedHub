local OxMLMenuUtilPrivate = {};
local CreateDropdownMenuUsingInserter = nil;
local CreateContextMenuUsingInserter = nil;

do
	local function VariadicInsert(elementDescription, inserter, ...)
		local arg = ...;
		if arg == nil then
			return;
		end

		elementDescription:Insert(inserter(unpack(arg)));
		VariadicInsert(elementDescription, inserter, select(2, ...));
	end

	CreateDropdownMenuUsingInserter = function(dropdown, inserter, ...)
		local tbl = {...};

		dropdown:SetupMenu(function(dropdown, rootDescription)
			VariadicInsert(rootDescription, inserter, unpack(tbl));
		end);
	end

	CreateContextMenuUsingInserter = function(ownerRegion, inserter, ...)
		local tbl = {...};

		return OxMLMenuUtil.CreateContextMenu(ownerRegion, function(ownerRegion, rootDescription)
			VariadicInsert(rootDescription, inserter, unpack(tbl));
		end);
	end
end


OxMLMenuUtil = {};

local function TraverseMenu(elementDescription, op, condition)
	if (condition == nil) or condition(elementDescription) then
		local handled = op(elementDescription);
		if handled then
			return true;
		end
	end

	for index, desc in elementDescription:EnumerateElementDescriptions() do
		local handled = TraverseMenu(desc, op, condition);
		if handled then
			return true;
		end
	end

	return false;
end

function OxMLMenuUtil.TraverseMenu(elementDescription, op, condition)
	for index, desc in elementDescription:EnumerateElementDescriptions() do
		local handled = TraverseMenu(desc, op, condition);
		if handled then
			return true;
		end
	end
	return false;
end

local function TraverseSelections(elementDescription, selections, condition)
	if ((condition == nil) or condition(elementDescription)) and (elementDescription:IsSelected()) then
		table.insert(selections, elementDescription);
	end
	
	for index, desc in elementDescription:EnumerateElementDescriptions() do
		TraverseSelections(desc, selections, condition);
	end

	return false;
end

function OxMLMenuUtil.GetSelections(elementDescription, condition)
	local selections = {};
	for index, desc in elementDescription:EnumerateElementDescriptions() do
		TraverseSelections(desc, selections, condition);
	end
	return selections;
end

local function MergeFunctions(elementDescription)
	for key, inserter in pairs(OxMLMenuUtilPrivate.GetInserters()) do
		elementDescription[key] = function(self, ...)
			return self:Insert(inserter(...));
		end;
	end

	for key, func in pairs(OxMLMenuUtilPrivate.GetUtilities()) do
		elementDescription[key] = func;
	end

	return elementDescription;
end

function OxMLMenuUtil.ShowTooltip(owner, func, ...)
	local tooltip = GetAppropriateTooltip();
	tooltip:SetOwner(owner, "ANCHOR_RIGHT");

	local window = owner:GetWindow();
	tooltip:SetWindow(window);

	func(tooltip, ...);
	tooltip:Show();
end

function OxMLMenuUtil.HideTooltip(owner)
	local tooltip = GetAppropriateTooltip();
	if tooltip:GetOwner() == owner then
		tooltip:Hide();
	end
end

function OxMLMenuUtil.HookTooltipScripts(owner, func)
	local tooltip = GetAppropriateTooltip();
	
	local oldOnEnter = owner:GetScript("OnEnter") or nop;
	owner:SetScript("OnEnter", function(...)
		tooltip:SetOwner(owner, "ANCHOR_RIGHT");
		oldOnEnter(...)
		func(tooltip);
		tooltip:Show();
	end);

	local oldOnLeave = owner:GetScript("OnLeave") or nop;
	owner:SetScript("OnLeave", function(...)
		oldOnLeave(...)
		func(tooltip);
		tooltip:Hide();
	end);
end

function OxMLMenuUtil.CreateRootMenuDescription(menuMixin)
	local elementDescription = OxMLMenu.CreateRootMenuDescription(menuMixin);
	MergeFunctions(elementDescription);
	return elementDescription;
end

--[[
Creates a context menu at the cursor. The region provided will inform the menu to close if it
becomes hidden. If no region is provided, then an explicit mouse press or ESC press will
be required to close it.
]]

local function SecureGetMenuMixin(ownerRegion)
	-- An addon may choose to override GetDefaultContextMenuMixin, though the implications that has on
	-- forbidden frames aren't clear yet.
	return ownerRegion.menuMixin or OxMLMenuVariants.GetDefaultContextMenuMixin();
end

function OxMLMenuUtil.CreateContextMenu(ownerRegion, generator, ...)
	if not ownerRegion then
		ownerRegion = GetAppropriateTopLevelParent();
	end

	local menuMixin = securecallfunction(SecureGetMenuMixin, ownerRegion);
	local elementDescription = OxMLMenuUtil.CreateRootMenuDescription(menuMixin);

	OxMLMenu.PopulateDescription(generator, ownerRegion, elementDescription, ...);

	local menu = OxMLMenu.GetManager():OpenContextMenu(ownerRegion, elementDescription);
	if menu then
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	end

	return menu;
end

--[[ Accessors so the implementation can change. Avoid grabbing .text off a description unless you're
prepared to fixup broken references when it moves or changes.
]]--
function OxMLMenuUtil.SetElementText(elementDescription, text)
	elementDescription.text = text;
end

function OxMLMenuUtil.GetElementText(elementDescription)
	return elementDescription.text;
end

function OxMLMenuUtil.CreateFrame()
	local elementDescription = OxMLMenuTemplates.CreateFrame();
	MergeFunctions(elementDescription);
	return elementDescription;
end

function OxMLMenuUtil.CreateTemplate(template)
	local elementDescription = OxMLMenuTemplates.CreateTemplate(template);
	MergeFunctions(elementDescription);
	return elementDescription;
end

local function ConfigureTextButton(text, elementDescription)
	MergeFunctions(elementDescription);
	OxMLMenuUtil.SetElementText(elementDescription, text);
	return elementDescription;
end

function OxMLMenuUtil.CreateTitle(text, color)
	local elementDescription = OxMLMenuTemplates.CreateTitle(text);
	ConfigureTextButton(text, elementDescription);

	local useColor = color or NORMAL_FONT_COLOR;
	elementDescription:AddInitializer(function(frame, description, menu)
		frame.fontString:SetTextColor(useColor:GetRGBA());
	end);
	return elementDescription;
end

function OxMLMenuUtil.CreateButton(text, callback, data)
	--assert(type(text) == "string");
	--assert((callback == nil) or type(callback) == "function");
	local elementDescription = OxMLMenuTemplates.CreateButton(text, callback, data);
	return ConfigureTextButton(text, elementDescription);
end

function OxMLMenuUtil.CreateCheckbox(text, isSelected, setSelected, data)
	--assert(type(text) == "string");
	--assert(type(isSelected) == "function");
	--assert(type(setSelected) == "function");
	local elementDescription = OxMLMenuTemplates.CreateCheckbox(text, isSelected, setSelected, data);
	return ConfigureTextButton(text, elementDescription);
end

function OxMLMenuUtil.CreateRadio(text, isSelected, setSelected, data)
	--assert(type(text) == "string");
	--assert(type(isSelected) == "function");
	--assert(type(setSelected) == "function");
	local elementDescription = OxMLMenuTemplates.CreateRadio(text, isSelected, setSelected, data);
	return ConfigureTextButton(text, elementDescription);
end

-- looks good with OxMLStyle2DropdownTemplate, immitates the Settings menu
function OxMLMenuUtil.CreateHighlightRadio(text, isSelected, setSelected, data, onEnter)
	--assert(type(text) == "string");
	--assert(type(isSelected) == "function");
	--assert(type(setSelected) == "function");
	local elementDescription = OxMLMenuTemplates.CreateHighlightRadio(text, isSelected, setSelected, data, onEnter);
	return ConfigureTextButton(text, elementDescription);
end

function OxMLMenuUtil.CreateColorSwatch(text, callback, colorInfo)
	--assert(type(text) == "string");
	--assert(type(callback) == "function");
	--assert(type(colorInfo) == "table");
	local elementDescription = OxMLMenuTemplates.CreateColorSwatch(text, callback, colorInfo);
	return ConfigureTextButton(text, elementDescription);
end

--[[
Wrappers for convenience since all other create functions are in OxMLMenuUtil. Note that these
are not accompanied by any additional utilities or inserters.
]]--
OxMLMenuUtil.CreateDivider = OxMLMenuTemplates.CreateDivider;
OxMLMenuUtil.CreateSpacer = OxMLMenuTemplates.CreateSpacer;

OxMLMenuUtilPrivate.Inserters =
{
	CreateFrame = OxMLMenuUtil.CreateFrame,
	CreateTemplate = OxMLMenuUtil.CreateTemplate,
	CreateButton = OxMLMenuUtil.CreateButton,
	CreateTitle = OxMLMenuUtil.CreateTitle,
	CreateCheckbox = OxMLMenuUtil.CreateCheckbox,
	CreateRadio = OxMLMenuUtil.CreateRadio,
	CreateHighlightRadio = OxMLMenuUtil.CreateHighlightRadio,
	CreateDivider = OxMLMenuUtil.CreateDivider,
	CreateSpacer = OxMLMenuUtil.CreateSpacer,
	CreateColorSwatch = OxMLMenuUtil.CreateColorSwatch,
};

function OxMLMenuUtilPrivate.GetInserters()
	return OxMLMenuUtilPrivate.Inserters;
end

local function DefaultTooltipInitializer(tooltip, elementDescription)
	local titleText = OxMLMenuUtil.GetElementText(elementDescription);
	GameTooltip_SetTitle(tooltip, titleText);
end

local function SetTooltip(elementDescription, initializer)
	elementDescription:SetOnEnter(function(frame)
		OxMLMenuUtil.ShowTooltip(frame, initializer or DefaultTooltipInitializer, elementDescription);
	end);
end

local function TitleAndTextTooltipInitializer(tooltip, tooltipTitle, tooltipText)
	GameTooltip_SetTitle(tooltip, tooltipTitle);
	GameTooltip_AddNormalLine(tooltip, tooltipText, true);
end

local function SetTitleAndTextTooltip(elementDescription, tooltipTitle, tooltipText)
	elementDescription:SetOnEnter(function(frame)
		OxMLMenuUtil.ShowTooltip(frame, TitleAndTextTooltipInitializer, tooltipTitle, tooltipText);
	end);
end

local function QueueDescription(description, queueDescription, clearQueue)
	if clearQueue then
		description:ClearQueuedDescriptions();
	end
	description:AddQueuedDescription(queueDescription);
end

local function QueueTitle(description, text, color, clearQueue)
	QueueDescription(description, OxMLMenuUtil.CreateTitle(text, color), clearQueue);
end

local function QueueDivider(description, clearQueue)
	QueueDescription(description, OxMLMenuUtil.CreateDivider(), clearQueue);
end

local function QueueSpacer(description, extent, clearQueue)
	QueueDescription(description, OxMLMenuUtil.CreateSpacer(extent), clearQueue);
end

OxMLMenuUtilPrivate.Utilities =
{
	SetTooltip = SetTooltip,
	SetTitleAndTextTooltip = SetTitleAndTextTooltip,
	QueueTitle = QueueTitle,
	QueueDivider = QueueDivider,
	QueueSpacer = QueueSpacer,
};

function OxMLMenuUtilPrivate.GetUtilities()
	return OxMLMenuUtilPrivate.Utilities;
end

--Variadic menu functions

--[[
... is a variadic array of non-associative tables, whose values match the Inserter function below.
The 'data' argument is optional.
]]
function OxMLMenuUtil.CreateButtonMenu(dropdown, ...)
	local function Inserter(text, onClick, data)
		return OxMLMenuUtil.CreateButton(text, onClick, data);
	end

	return CreateDropdownMenuUsingInserter(dropdown, Inserter, ...);
end

function OxMLMenuUtil.CreateButtonContextMenu(ownerRegion, ...)
	local function Inserter(text, onClick, data)
		return OxMLMenuUtil.CreateButton(text, onClick, data);
	end
	return CreateContextMenuUsingInserter(ownerRegion, Inserter, ...);
end

--[[
... is a variadic array of non-associative tables, whose values match the Inserter function below.
The 'data' argument is optional.
]]
function OxMLMenuUtil.CreateCheckboxMenu(dropdown, isSelected, setSelected, ...)
	local function Inserter(text, data)
		return OxMLMenuUtil.CreateCheckbox(text, isSelected, setSelected, data);
	end

	return CreateDropdownMenuUsingInserter(dropdown, Inserter, ...);
end

function OxMLMenuUtil.CreateCheckboxContextMenu(ownerRegion, isSelected, setSelected, ...)
	local function Inserter(text, data)
		return OxMLMenuUtil.CreateCheckbox(text, isSelected, setSelected, data);
	end
	return CreateContextMenuUsingInserter(ownerRegion, Inserter, ...);
end

--[[
... is a variadic array of non-associative tables, whose values match the Inserter function below.
The 'data' argument is optional.
]]
function OxMLMenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, ...)
	local function Inserter(text, data)
		return OxMLMenuUtil.CreateRadio(text, isSelected, setSelected, data);
	end
	return CreateDropdownMenuUsingInserter(dropdown, Inserter, ...);
end

function OxMLMenuUtil.CreateRadioContextMenu(ownerRegion, isSelected, setSelected, ...)
	local function Inserter(text, data)
		return OxMLMenuUtil.CreateRadio(text, isSelected, setSelected, data);
	end
	return CreateContextMenuUsingInserter(ownerRegion, Inserter, ...);
end

local function CreateEnumTables(enum, enumTranslator, orderTbl)
	local enumTbls = {};

	for enumKey, enumValue in pairs(enum) do
		table.insert(enumTbls, { enumTranslator(enumValue), enumValue });
	end

	if orderTbl then
		table.sort(enumTbls, function(lhs, rhs)
			return orderTbl[lhs[2]] < orderTbl[rhs[2]];
		end);
	else
		table.sort(enumTbls, function(lhs, rhs)
			return lhs[2] < rhs[2];
		end);
	end

	return enumTbls;
end

function OxMLMenuUtil.CreateEnumRadioMenu(dropdown, enum, enumTranslator, isSelected, setSelected, orderTbl)
	local enumTbls = CreateEnumTables(enum, enumTranslator, orderTbl);
	return OxMLMenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, unpack(enumTbls));
end

function OxMLMenuUtil.CreateEnumRadioContextMenu(dropdown, enum, enumTranslator, isSelected, setSelected, orderTbl)
	local enumTbls = CreateEnumTables(enum, enumTranslator, orderTbl);
	return OxMLMenuUtil.CreateRadioContextMenu(dropdown, isSelected, setSelected, unpack(enumTbls));
end
