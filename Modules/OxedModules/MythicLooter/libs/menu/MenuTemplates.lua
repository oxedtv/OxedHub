local SetPropagateMouseMotion = function(frame, propagate)
	frame:SetPropagateMouseMotion(propagate);
end;

-- Blizzard_EnvironmentCleanup nils out CreateSecureDelegate before addons load
local SetPropagateMouseMotionDelegate = SetPropagateMouseMotion;

OxMLMenuTemplates = {};

--[[
Secure print for debugging purposes only. Remember to comment out the call to DebugPrintSecure
before committing.
]]
local function DebugShouldPrint()
	return OxMLMenuConstants.PrintSecure;
end

local function DebugPrintSecure()
	if IsPublicBuild() or (not securecallfunction(DebugShouldPrint)) then
		return;
	end

	UIErrorsFrame:AddMessage("Secure: "..tostring(issecure()));
end

local function CreateMenuElementDescription(template, initializer, data)
	local elementDescription = OxMLMenu.CreateMenuElementDescription();
	elementDescription:SetData(data);
	elementDescription:SetElementFactory(function(factory)
		factory(template, initializer);
	end);

	return elementDescription;
end

local function CallFunctionWithVarArgAsParam(func, ...)
	for index = 1, select("#", ...) do
		func(select(index, ...));
	end
end

local function GetCheckboxSoundKit(description)
	if description:IsSelected() then
		return OxMLMenuVariants.GetCheckboxCheckSoundKit();
	else
		return OxMLMenuVariants.GetCheckboxUncheckSoundKit();
	end
end

local function GetButtonSoundKit(description)
	return OxMLMenuVariants.GetButtonSoundKit();
end

--[[
Final initializer is called after all other initializers are called so that
the recursion functions here can find any of the regions that were attached.
]]--
local function ButtonFinalInitializer(button, description, menu)
	OxMLMenuTemplates.RecurseSetupFontString(button);

	local enabled = description:IsEnabled();
	button:SetEnabled(enabled);

	OxMLMenuTemplates.SetHierarchyEnabled(button, enabled);
end

local function OnButtonEnable(button)
	OxMLMenuTemplates.SetHierarchyEnabled(button, true);
end

local function OnButtonDisable(button)
	OxMLMenuTemplates.SetHierarchyEnabled(button, false);
end

local function OnButtonClick(button, buttonName)
	local description = button:GetElementDescription();
	if not description:CanOpenSubmenu() or description:ShouldPlaySoundOnSubmenuClick() then
		PlaySound(description:GetSoundKit());
	end

	description:Pick(OxMLMenuInputContext.MouseButton, buttonName);

	--securecallfunction(DebugPrintSecure);
end

local function ShowHighlight(button, description)
	button.highlight:Show();
	button.highlight:SetAlpha(description:IsEnabled() and 1 or OxMLMenuVariants.DisabledHighlightOpacity);
end

local function OnButtonEnter(button, description)
	ShowHighlight(button, description);
end

local function OnButtonLeave(button)
	button.highlight:Hide();
end

local function ButtonInitializer(button, description, menu)
	if description:CanOpenSubmenu() then
		OxMLMenuVariants.CreateSubmenuArrow(button);
	end

	OxMLMenuVariants.CreateHighlight(button);

	--[[
	Visibility cannot be automatically toggled on the HIGHLIGHT layer
	because the highlight needs to be the bottom render layer.
	]]--
	button.OnEnter = OnButtonEnter;
	button.OnLeave = OnButtonLeave;

	--[[
	The button will not re-highlight if it is reinitialized while the cursor
	is already over the button.
	]]--
	if button:IsMouseMotionFocus() then
		ShowHighlight(button, description);
	end

	if description:ShouldPollEnabled() then
		button:NewTicker(OxMLMenuConstants.ElementPollFrequencySeconds, function()
			button:SetEnabled(description:IsEnabled());
		end);
	end

	button:SetMotionScriptsWhileDisabled(true);
	button:SetScript("OnEnable", OnButtonEnable);
	button:SetScript("OnDisable", OnButtonDisable);
	button:SetScript("OnClick", OnButtonClick);
end

local function CreateButtonDescription(data)
	local elementDescription = CreateMenuElementDescription("Button", ButtonInitializer, data);
	elementDescription:SetFinalInitializer(ButtonFinalInitializer);
	return elementDescription;
end

function OxMLMenuTemplates.RecurseSetupFontString(frame)
	--[[
	Applying the enabled state is deferred until all initializers are called so that any
	construction or initialization of any regions is finished before we attempt to traverse
	the hierarchy and apply new states.
	]]--

	--[[
	Cache our current and disabled color so we can switch between them as the button
	enabled state is changed. When a use case for changing the disabled color appears,
	add an API to return the desired color(s).
	]]--

	local function TrySetupFontString(region)
		if region:IsObjectType("FontString") then
			local fontString = region;
			local autoEnableTextColors =
			{
				[true] = CreateColor(fontString:GetTextColor()),
				[false] = DISABLED_FONT_COLOR,
			};

			-- Compositor replaces __index with a function. Also note that
			-- you cannot acquire the original function again once SetTextColor
			-- is assigned because the mt will return the assigned function instead.
			local originalSetTextColor;
			local mt = getmetatable(fontString);
			if type(mt.__index) == "function" then
				originalSetTextColor = mt.__index(fontString, "SetTextColor");
			elseif not fontString.autoEnableTextColors then
				originalSetTextColor = fontString.SetTextColor;
			end

			if originalSetTextColor then
				fontString.SetTextColor = function(self, r, g, b, a)
					-- The intention here is to update the cached color for 'enabled/true' so that it can be
					-- restored as the frame changes enabled state. This treats any color other than
					-- DISABLED_FONT_COLOR as an enabled color.
					if not IsRGBAEqualToColor(r, g, b, a, autoEnableTextColors[false]) then
						autoEnableTextColors[true] = CreateColor(r, g, b, a);
					end
					originalSetTextColor(self, r, g, b, a);
				end;
				fontString.autoEnableTextColors = autoEnableTextColors;
			end
		end
	end
	CallFunctionWithVarArgAsParam(TrySetupFontString, frame:GetRegions());
	CallFunctionWithVarArgAsParam(OxMLMenuTemplates.RecurseSetupFontString, frame:GetChildren());
end

function OxMLMenuTemplates.SetHierarchyEnabled(frame, enabled)
	local function Recurse(frame)
		if frame.noRecurseHierarchy then
			return;
		end

		local function SetAutoEnabled(region)
			if region.noRecurseHierarchy then
				return;
			end

			if frame.lockedEnabledState ~= nil then
				enabled = frame.lockedEnabledState;
			end

			if region:IsObjectType("FontString") and region.autoEnableTextColors then
				local fontString = region;
				local textColor = fontString.autoEnableTextColors[enabled];
				fontString:SetTextColor(textColor:GetRGBA());
			elseif region:IsObjectType("Texture") then
				region:SetDesaturation(enabled and 0 or 1);
			end
		end
		CallFunctionWithVarArgAsParam(SetAutoEnabled, frame:GetRegions());
		CallFunctionWithVarArgAsParam(Recurse, frame:GetChildren());
	end

	Recurse(frame);
end

function OxMLMenuTemplates.CreateFrame(initializer, data)
	return CreateMenuElementDescription("Frame", initializer, data);
end

function OxMLMenuTemplates.CreateTemplate(template, initializer, data)
	return CreateMenuElementDescription(template, initializer, data);
end

function OxMLMenuTemplates.CreateTitle(text)
	local function Initializer(frame, description, menu)
		local fontString = OxMLMenuVariants.CreateFontString(frame);
		frame.fontString = fontString;
		fontString:SetTextToFit(text);
	end

	return OxMLMenuTemplates.CreateFrame(Initializer);
end

function OxMLMenuTemplates.CreateButton(text, callback, data)
	local function Initializer(button, description, menu)
		local fontString = OxMLMenuVariants.CreateFontString(button);
		button.fontString = fontString;
		fontString:SetTextToFit(text);
	end

	local elementDescription = CreateButtonDescription(data);
	elementDescription:SetSoundKit(GetButtonSoundKit);
	elementDescription:AddInitializer(Initializer);
	elementDescription:SetResponder(callback);
	return elementDescription;
end

--[[
Radio and checkbox textures both share a 2 texture setup where a second texture is created
only if the data is selected.
]]
function OxMLMenuTemplates.CreateSelectionTextures(frame, isSelected, data, unselectedAtlas, selectedAtlas)
	local leftTexture1 = frame:AttachTexture();
	frame.leftTexture1 = leftTexture1;
	leftTexture1:SetAtlas(unselectedAtlas, TextureKitConstants.UseAtlasSize);

	-- Avoiding creating the second texture unnecessarily.
	local leftTexture2 = nil;
	if isSelected(data) then
		leftTexture2 = frame:AttachTexture();
		local layer, drawLevel = leftTexture1:GetDrawLayer();
		leftTexture2:SetDrawLayer(layer, drawLevel + 1);
		leftTexture2:SetAtlas(selectedAtlas, TextureKitConstants.UseAtlasSize);
	end

	frame.leftTexture2 = leftTexture2;
	return leftTexture1, leftTexture2;
end

function OxMLMenuTemplates.CreateCheckbox(text, isSelected, onSelect, data)
	local function Initializer(button, description, menu)
		OxMLMenuVariants.CreateCheckbox(text, button, isSelected, data);
	end

	local elementDescription = CreateButtonDescription(data);
	elementDescription:SetSoundKit(GetCheckboxSoundKit);
	elementDescription:AddInitializer(Initializer);
	elementDescription:SetIsSelected(isSelected);
	elementDescription:SetResponder(onSelect);
	elementDescription:SetResponse(OxMLMenuResponse.Refresh);
	return elementDescription;
end

function OxMLMenuTemplates.CreateRadio(text, isSelected, onSelect, data)
	local function Initializer(button, description, menu)
		OxMLMenuVariants.CreateRadio(text, button, isSelected, data);
	end

	local elementDescription = CreateButtonDescription(data);
	elementDescription:SetSoundKit(GetButtonSoundKit);
	elementDescription:AddInitializer(Initializer);
	elementDescription:SetRadio(true);
	elementDescription:SetIsSelected(isSelected);
	elementDescription:SetResponder(onSelect);
	return elementDescription;
end

function OxMLMenuTemplates.CreateHighlightRadio(text, isSelected, onSelect, data, onEnter)
	local optionDescription = CreateMenuElementDescription("OxMLMenuDropdownHighlightRadioTemplate");

	local truncated = false;

	local function OnEnter(button)
		button.HighlightBGTex:SetAlpha(0.15);

		local description = button:GetElementDescription();
		if description:IsEnabled() and not description:IsSelected() then
			button.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
		end

		if truncated then
			OxMLMenuUtil.ShowTooltip(button, function(tooltip)
				GameTooltip_SetTitle(tooltip, text);
			end);
		end

		if onEnter then
			onEnter(data);
		end
	end

	local function OnLeave(button)
		button.HighlightBGTex:SetAlpha(0);

		local description = button:GetElementDescription();
		if description:IsEnabled() and not description:IsSelected() then
			button.Text:SetTextColor(VERY_LIGHT_GRAY_COLOR:GetRGB());
		end

		OxMLMenuUtil.HideTooltip(button);
	end

	optionDescription:AddInitializer(function(button, description, menu)
		button:SetScript("OnClick", function(button, buttonName)
			description:Pick(OxMLMenuInputContext.MouseButton, buttonName);
		end);

		-- This button template is modified in Languages.lua to hide the text and display
		-- a texture for each locale, so we need to redisplay the text. We don't have to worry
		-- about that texture here because it is managed by the compositor.
		button.Text:Show();
		button.Text:SetTextToFit(text);
		button.Text:SetWidth(button.Text:GetWidth() + 10);

		button.HighlightBGTex:SetAlpha(0);

		local fontColor = nil;
		if description:IsSelected() then
			button.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGBA());
		elseif description:IsEnabled() then
			button.Text:SetTextColor(VERY_LIGHT_GRAY_COLOR:GetRGB());
		else
			button.Text:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
		end

		truncated = button.Text:IsTruncated();

		button:Layout();
	end);

	optionDescription:SetIsSelected(isSelected);
	optionDescription:SetResponder(onSelect);
	optionDescription:SetOnEnter(OnEnter);
	optionDescription:SetOnLeave(OnLeave);
	optionDescription:SetRadio(true);
	optionDescription:SetData(data);

	return optionDescription;
end

function OxMLMenuTemplates.CreateSpacer(extent)
	local function Initializer(frame, description, menu)
		frame:SetHeight(extent or 10);
	end

	return OxMLMenuTemplates.CreateFrame(Initializer);
end

function OxMLMenuTemplates.CreateDivider()
	local function Initializer(frame, description, menu)
		frame.divider = OxMLMenuVariants.CreateDivider(frame);
	end

	return OxMLMenuTemplates.CreateFrame(Initializer);
end

function OxMLMenuTemplates.CreateColorSwatch(text, callback, colorInfo)
	local function Initializer(frame, description, menu)
		local fontString = OxMLMenuVariants.CreateFontString(frame);
		frame.fontString = fontString;
		frame.fontString:SetTextToFit(text);

		local colorSwatch = frame:AttachTemplate("ColorSwatchTemplate");
		frame.colorSwatch = colorSwatch;
		colorSwatch:SetPoint("RIGHT");
		colorSwatch:SetSize(16, 16);
		colorSwatch:SetColorRGB(colorInfo.r, colorInfo.g, colorInfo.b);
	end

	local elementDescription = CreateButtonDescription(colorInfo);
	elementDescription:SetSoundKit(GetButtonSoundKit);
	elementDescription:AddInitializer(Initializer);
	elementDescription:SetResponder(callback);
	return elementDescription;
end

do
	local function OnAutoHideButtonLeave(button)
		OxMLMenuUtil.HideTooltip(button);
	end

	function OxMLMenuTemplates.AttachAutoHideButton(parent, textureName)
		local button = parent:AttachTemplate("OxMLMenuAutoHideButtonTemplate");
		button:SetFrameStrata(parent:GetFrameStrata()); -- Machinery is broken.
		button:Hide();

		-- SetToDefaults wipes propagateMouseInput on pooled frames even though it was set by the template, so it needs to be set here every time.
		SetPropagateMouseMotionDelegate(button, true);

		button:SetScript("OnLeave", OnAutoHideButtonLeave);

		local texture = button.Texture;
		texture:SetTexture(textureName);

		local onEnter = parent.OnEnter or nop;
		parent.OnEnter = function(...)
			onEnter(parent, ...);
			button:Show();
			button.Texture:Show();
		end

		local onLeave = parent.OnLeave or nop;
		parent.OnLeave = function(...)
			onLeave(parent, ...);
			button:Hide();
		end
		return button;
	end
end

function OxMLMenuTemplates.AttachBasicButton(parent, width, height)
	local button = parent:AttachFrame("Button");
	button:SetFrameStrata(parent:GetFrameStrata()); -- Machinery is broken.

	-- SetToDefaults wipes button state, desired states must be explicitly set now.
	button:Show();

	SetPropagateMouseMotionDelegate(button, true);

	button:SetMouseClickEnabled(true);
	button:SetMouseMotionEnabled(true);
	button:SetSize(width or 16, height or 16);

	return button;
end

function OxMLMenuTemplates.AttachUtilityButton(parent, textureAsset, width, height)
	local button = OxMLMenuTemplates.AttachAutoHideButton(parent, textureAsset);
	button:SetSize(width or 16, height or 16);
	return button;
end

function OxMLMenuTemplates.SetUtilityButtonClickHandler(button, handler)
	button:SetScript("OnClick", function(_b, mouseButton, _isDown)
		if mouseButton == "LeftButton" then
			handler();
		end
	end);
end

function OxMLMenuTemplates.SetUtilityButtonTooltipText(button, tooltipText)
	OxMLMenuUtil.HookTooltipScripts(button, function(tooltip)
		GameTooltip_SetTitle(tooltip, tooltipText);
	end);
end

function OxMLMenuTemplates.SetUtilityButtonLockedEnabledState(button, value)
	button.lockedEnabledState = value;
end

function OxMLMenuTemplates.SetUtilityButtonAnchor(button, anchor, relativeTo)
	local point, _, relativePoint, x, y = anchor:Get();
	button:SetPoint(point, relativeTo, relativePoint, x, y);
end

function OxMLMenuTemplates.AttachAutoHideGearButton(parent)
	return OxMLMenuTemplates.AttachUtilityButton(parent, OxMLMenuVariants.GearButtonTexture);
end

function OxMLMenuTemplates.AttachAutoHideCancelButton(parent)
	return OxMLMenuTemplates.AttachUtilityButton(parent, OxMLMenuVariants.CancelButtonTexture);
end

function OxMLMenuTemplates.AttachNewFeatureFrame(parent)
	local newFeatureFrame = parent:AttachTemplate("NewFeatureLabelTemplate");

	newFeatureFrame.noRecurseHierarchy = true;
	return newFeatureFrame;
end

function OxMLMenuTemplates.AttachTexture(parent, textureOrAtlas, point, pointX, pointY)
	local iconTexture = parent:AttachTexture();
	iconTexture:SetPoint(point or "RIGHT", pointX or 0, pointY or 0);

	if C_Texture.GetAtlasInfo(textureOrAtlas) then
		local useAtlasSize = false;
		iconTexture:SetAtlas(textureOrAtlas, useAtlasSize);
	else
		iconTexture:SetTexture(textureOrAtlas);
	end

	return iconTexture;
end

OxMLDropdownTextMixin = {};

function OxMLDropdownTextMixin:OnLoad()
	if self.text then
		self:SetText(self.text);
	end
end

function OxMLDropdownTextMixin:GetText()
	return self.text;
end

function OxMLDropdownTextMixin:SetText(text)
	self.text = text;
	self:UpdateText();
end

function OxMLDropdownTextMixin:GetUpdateText()
	return self.text;
end

function OxMLDropdownTextMixin:UpdateText()
	self.Text:SetText(self:GetUpdateText());

	if self.resizeToText then
		local newWidth = self.Text:GetUnboundedStringWidth();

		if self.resizeToTextPadding then
			newWidth = newWidth + self.resizeToTextPadding;
		end

		if self.resizeToTextMaxWidth then
			newWidth = math.min(self.resizeToTextMaxWidth, newWidth);
		end

		if self.resizeToTextMinWidth then
			newWidth = math.max(self.resizeToTextMinWidth, newWidth);
		end

		self:SetWidth(newWidth);
	end
end

function OxMLDropdownTextMixin:UpdateToMenuSelections(menuDescription, currentSelections)
	self:UpdateText();
end

--[[
An initializer wrapping OxMLDropdownButtonMixin.SetupMenu is not provided because in the vast majority of cases
the displayed text will reflect at least 1 selected option. SetDefaultText() should be used to provide text
in the cases where no selection is possible.
]]--
OxMLDropdownSelectionTextMixin = CreateFromMixins(OxMLDropdownTextMixin);

local function DefaultSelectionTranslator(selection)
	return OxMLMenuUtil.GetElementText(selection);
end

function OxMLDropdownSelectionTextMixin:OnLoad()
	OxMLDropdownTextMixin.OnLoad(self);

	self:SetSelectionTranslator(DefaultSelectionTranslator);
end

function OxMLDropdownSelectionTextMixin:GetUpdateText()
	return self.text or self.defaultText;
end

function OxMLDropdownSelectionTextMixin:GetDefaultText()
	return self.defaultText;
end

function OxMLDropdownSelectionTextMixin:SetDefaultText(text)
	self.defaultText = text;
	self:UpdateText();
end

function OxMLDropdownSelectionTextMixin:SetSelectionTranslator(translator)
	self.selectionTranslator = translator;
end

function OxMLDropdownSelectionTextMixin:SetSelectionText(selectionFunc)
	self.selectionFunc = selectionFunc;
end

function OxMLDropdownSelectionTextMixin:OverrideText(text)
	if not text then
		return;
	end

	self.disableSelectionText = true;
	self:SetText(text);
end

function OxMLDropdownSelectionTextMixin:UpdateToMenuSelections(menuDescription, currentSelections)
	if self.disableSelectionText then
		return;
	end

	if not currentSelections and menuDescription then
		currentSelections = OxMLMenuUtil.GetSelections(menuDescription);
	end

	local text = nil;

	if self.selectionFunc then
		text = self.selectionFunc(currentSelections);
	end

	if text == nil and currentSelections then
		local texts = {};

		for index, selection in ipairs(currentSelections) do
			if not selection:IsSelectionIgnored() then
				local translatedText = self.selectionTranslator(selection);
				table.insert(texts, translatedText);
			end
		end

		if #texts > 0 then
			if self.dontConcatenateText then
				text = texts[1];
			else
				text = table.concat(texts, LIST_DELIMITER);
			end
		end
	end

	self:SetText(text or self.defaultText);
end

function OxMLDropdownSelectionTextMixin:OnShow()
	-- Will only cause a menu description to be generated if the generator was
	-- assigned prior to the OnShow() being called.
	self:GenerateMenu();
end

function OxMLDropdownSelectionTextMixin:OnEnter()
	ButtonStateBehaviorMixin.OnEnter(self);

	if self:ShouldShowTooltip() then
		self:ShowTooltip();
	end
end

function OxMLDropdownSelectionTextMixin:ShouldShowTooltip()
	return self.Text:IsTruncated() or self.tooltipFunc;
end

function OxMLDropdownSelectionTextMixin:SetTooltip(tooltipFunc)
	self.tooltipFunc = tooltipFunc;
end

function OxMLDropdownSelectionTextMixin:ShowTooltip()
	if self.tooltipFunc then
		OxMLMenuUtil.ShowTooltip(self, self.tooltipFunc);
	else
		OxMLMenuUtil.ShowTooltip(self, function(tooltip)
			GameTooltip_SetTitle(tooltip, self.Text:GetText());
		end);
	end
end

function OxMLDropdownSelectionTextMixin:OnLeave()
	ButtonStateBehaviorMixin.OnLeave(self);

	OxMLMenuUtil.HideTooltip(self);
end

-- Inherited by dropdown buttons that require the reset button behavior. The reset button
-- needs to be defined/created prior to the OnLoad call.
OxMLDropdownFilterBehaviorMixin = {};

function OxMLDropdownFilterBehaviorMixin:OnLoad()
	self.ResetButton:SetScript("OnClick", function(button, buttonName, down)
		if self.defaultCallback then
			 self.defaultCallback();
		end

		self.ResetButton:Hide();

		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	end);
end

function OxMLDropdownFilterBehaviorMixin:OnShow()
	self:ValidateResetState();
end

-- Callback to set all filters to default state.
function OxMLDropdownFilterBehaviorMixin:SetDefaultCallback(callback)
	self.defaultCallback = callback;
end

-- Callback to return if the filters are in their default state.
function OxMLDropdownFilterBehaviorMixin:SetIsDefaultCallback(callback)
	self.isDefaultCallback = callback;
end

-- Called in response to any menu option change.
function OxMLDropdownFilterBehaviorMixin:SetUpdateCallback(callback)
	self.notifyUpdateCallback = callback;
end

function OxMLDropdownFilterBehaviorMixin:NotifyUpdate(description)
	if self.notifyUpdateCallback then
		self.notifyUpdateCallback(description);
	end
end

function OxMLDropdownFilterBehaviorMixin:Reset()
	self.ResetButton:Hide();
end

function OxMLDropdownFilterBehaviorMixin:ValidateResetState()
	if self.isDefaultCallback then
		self.ResetButton:SetShown(not self.isDefaultCallback());
	end
end

-- Call in derived
function OxMLDropdownFilterBehaviorMixin:OnMenuResponse(menu, description)
	self:ValidateResetState();
	self:NotifyUpdate(description);
end

-- Call in derived
function OxMLDropdownFilterBehaviorMixin:OnMenuAssigned()
	self:ValidateResetState();
end

OxMLFilterButtonMixin = CreateFromMixins(OxMLDropdownFilterBehaviorMixin);

function OxMLFilterButtonMixin:OnMenuResponse(menu, description)
	OxMLDropdownButtonMixin.OnMenuResponse(self, menu, description);
	OxMLDropdownFilterBehaviorMixin.OnMenuResponse(self, menu, description);
end

function OxMLFilterButtonMixin:OnMenuAssigned()
	OxMLDropdownButtonMixin.OnMenuAssigned(self);
	OxMLDropdownFilterBehaviorMixin.OnMenuAssigned(self);
end

OxMLStyle1DropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, OxMLDropdownSelectionTextMixin);

function OxMLStyle1DropdownMixin:OnLoad()
	OxMLValidateIsDropdownButtonIntrinsic(self);
	ButtonStateBehaviorMixin.OnLoad(self);
	OxMLDropdownSelectionTextMixin.OnLoad(self);
end

function OxMLStyle1DropdownMixin:OnButtonStateChanged()
	local enabled = self:IsEnabled();
	if enabled then
		self.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB());
	else
		self.Text:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
	end

	self.Arrow:SetAtlas(self:GetArrowAtlas(), TextureKitConstants.UseAtlasSize);
end

--[[
The standard "filter" dropdown style. Its text does not reflect the selected option(s) and
instead is generally initialized to fixed text.
]]--
OxMLStyle1FilterDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, OxMLDropdownTextMixin, OxMLFilterButtonMixin);

function OxMLStyle1FilterDropdownMixin:OnLoad()
	OxMLValidateIsDropdownButtonIntrinsic(self);
	ButtonStateBehaviorMixin.OnLoad(self);
	OxMLDropdownTextMixin.OnLoad(self);
	OxMLFilterButtonMixin.OnLoad(self);

	if self.baseFontObject then
		self.Text:SetFontObject(self.baseFontObject);
	else
		self.baseFontObject = self.Text:GetFontObject();
	end

	local x, y = 2, -1;
	self:SetDisplacedRegions(x, y, self.Text);
end

function OxMLStyle1FilterDropdownMixin:GetBackgroundAtlas()
	if self:IsEnabled() then
		if self:IsDownOver() then
			return OxMLStyle1FilterDropdownStateDownOver;
		elseif self:IsOver() then
			return OxMLStyle1FilterDropdownStateOver;
		elseif self:IsDown() then
			return OxMLStyle1FilterDropdownStateDown;
		elseif self:IsMenuOpen() then
			return OxMLStyle1FilterDropdownStateOpen;
		else
			return OxMLStyle1FilterDropdownStateEnabled;
		end
	end
	return OxMLStyle1FilterDropdownStateDisabled;
end

function OxMLStyle1FilterDropdownMixin:OnButtonStateChanged()
	self.Background:SetAtlas(self:GetBackgroundAtlas(), TextureKitConstants.UseAtlasSize);
end

function OxMLStyle1FilterDropdownMixin:OnEnable()
	ButtonStateBehaviorMixin.OnEnable(self);

	self.Text:SetFontObject(self.baseFontObject);
end

function OxMLStyle1FilterDropdownMixin:OnDisable()
	ButtonStateBehaviorMixin.OnDisable(self);

	self.Text:SetFontObject(self.disableFontObject);
end

--[[
A special style used in Settings and Character Creation/Customization. Note that complex
contents (color swatches, icons, etc.) are not defined here but are instead added as a child
within this template. See "OxMLStyle2DropdownTemplate" in Blizzard_CharacterCustomize.xml.
]]--
OxMLStyle2DropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin, OxMLDropdownSelectionTextMixin, OxMLFilterButtonMixin);

function OxMLStyle2DropdownMixin:OnLoad()
	ButtonStateBehaviorMixin.OnLoad(self);
	OxMLDropdownSelectionTextMixin.OnLoad(self);
	OxMLFilterButtonMixin.OnLoad(self);

	local x, y = 2, -1;
	self:SetDisplacedRegions(x, y, self.Text);
end

function OxMLStyle2DropdownMixin:OnShow()
	OxMLDropdownSelectionTextMixin.OnShow(self);
	OxMLFilterButtonMixin.OnShow(self);
end

function OxMLStyle2DropdownMixin:GetBackgroundAtlas()
	if self:IsEnabled() then
		if self:IsDownOver() then
			return "common-dropdown-c-button-pressedhover-1";
		elseif self:IsOver() then
			return "common-dropdown-c-button-hover-1";
		elseif self:IsDown() then
			return "common-dropdown-c-button-pressed-1";
		elseif self:IsMenuOpen() then
			return "common-dropdown-c-button-open";
		else
			return "common-dropdown-c-button";
		end
	end

	return "common-dropdown-c-button-disabled";
end

function OxMLStyle2DropdownMixin:OnButtonStateChanged()
	local enabled = self:IsEnabled();
	if enabled then
		self.Text:SetTextColor(NORMAL_FONT_COLOR:GetRGB());
	else
		self.Text:SetTextColor(DISABLED_FONT_COLOR:GetRGB());
	end

	self.Arrow:SetShown(self:IsOver());
	self.Arrow:SetDesaturated(not enabled);

	self.Background:SetAtlas(self:GetBackgroundAtlas(), TextureKitConstants.UseAtlasSize);
end

function OxMLStyle2DropdownMixin:OnMenuOpened(menu)
	OxMLDropdownButtonMixin.OnMenuOpened(self, menu);

	self:OnButtonStateChanged();
end

function OxMLStyle2DropdownMixin:OnMenuClosed(menu, closeReason)
	OxMLDropdownButtonMixin.OnMenuClosed(self, menu, closeReason);

	self:OnButtonStateChanged();
end

OxMLStyle1ArrowDropdownMixin = CreateFromMixins(ButtonStateBehaviorMixin);

function OxMLStyle1ArrowDropdownMixin:OnLoad()
	OxMLValidateIsDropdownButtonIntrinsic(self);
	ButtonStateBehaviorMixin.OnLoad(self);
	OxMLDropdownButtonMixin.OnLoad(self);
end

OxMLMenuStyleMixin = {};

function OxMLMenuStyleMixin:Generate()
	local texture = self:AttachTexture();
	texture:SetAllPoints();

	local r, g, b = GREEN_FONT_COLOR:GetRGB();
	texture:SetColorTexture(r, g, b, .5);
end

do
	local inset =
	{
		left = 0,
		top = 0,
		right = 0,
		bottom = 0,
	};

	function OxMLMenuStyleMixin:GetInset()
		return inset;
	end
end

do
	local padding =
	{
		width = 0,
		height = 0,
	};

	function OxMLMenuStyleMixin:GetChildExtentPadding()
		return padding;
	end
end

-- Test purposes only.
OxMLRandomColorStyleMenuMixin = CreateFromMixins(OxMLMenuStyleMixin);

function OxMLRandomColorStyleMenuMixin:Generate()
	local texture = self:AttachTexture();
	texture:SetAllPoints();

	local c = .5;
	local r, g, b = math.random() * c, math.random() * c, math.random() * c;
	texture:SetColorTexture(r, g, b, 1);
end

OxMLBlackColorStyleMenuMixin = CreateFromMixins(OxMLMenuStyleMixin);

function OxMLBlackColorStyleMenuMixin:Generate()
	local texture = self:AttachTexture();
	texture:SetAllPoints();

	texture:SetColorTexture(0, 0, 0, 1);
end

OxMLMenuStyle2Mixin = CreateFromMixins(OxMLMenuStyleMixin);

function OxMLMenuStyle2Mixin:Generate()
	local background = self:AttachTexture();
	background:SetAtlas("common-dropdown-c-bg");
	background:SetPoint("TOPLEFT", -17, 12);
	background:SetPoint("BOTTOMRIGHT", 17, -22);
end

do
	local inset =
	{
		left = 3,
		top = 6,
		right = 3,
		bottom = 7,
	};

	function OxMLMenuStyle2Mixin:GetInset()
		return inset;
	end
end

-- Accompanies the style of WowStyle2Dropdown
OxMLStyle2IconButtonMixin = CreateFromMixins(ButtonStateBehaviorMixin);

function OxMLStyle2IconButtonMixin:OnLoad()
	self:OnButtonStateChanged();

	local x, y = 2, -1;
	self:SetDisplacedRegions(x, y, self.Icon);
end

function OxMLStyle2IconButtonMixin:GetBackgroundAtlas()
	if self:IsEnabled() then
		if self:IsDownOver() then
			return "common-dropdown-c-button-pressedhover-2";
		elseif self:IsOver() then
			return "common-dropdown-c-button-hover-2";
		elseif self:IsDown() then
			return "common-dropdown-c-button-pressed-2";
		else
			return "common-dropdown-c-button";
		end
	end

	return "common-dropdown-c-button-disabled";
end

function OxMLStyle2IconButtonMixin:OnButtonStateChanged()
	self.Background:SetAtlas(self:GetBackgroundAtlas(), TextureKitConstants.UseAtlasSize);

	local icon = self:IsEnabled() and self.normalAtlas or self.disabledAtlas;
	self.Icon:SetAtlas(icon, TextureKitConstants.UseAtlasSize);
end
