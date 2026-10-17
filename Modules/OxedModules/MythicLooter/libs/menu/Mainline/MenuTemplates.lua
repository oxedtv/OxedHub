-- Requires the button to inherit ButtonStateBehaviorMixin
function GetKSLStyle1ArrowButtonState(button)
	if button:IsEnabled() then
		if button:IsDownOver() then
			return "common-dropdown-a-button-pressedhover";
		elseif button:IsOver() then
			return "common-dropdown-a-button-hover";
		elseif button:IsDown() then
			return "common-dropdown-a-button-pressed";
		elseif button:IsMenuOpen() then
			return "common-dropdown-a-button-open";
		else
			return "common-dropdown-a-button";
		end
	end
	return "common-dropdown-a-button-disabled";
end

-- Requires the button to inherit ButtonStateBehaviorMixin
function GetKSLStyle1ArrowButtonShadowlessState(button)
	if button:IsEnabled() then
		if button:IsDownOver() then
			return "common-dropdown-a-button-pressedhover-shadowless";
		elseif button:IsOver() then
			return "common-dropdown-a-button-hover-shadowless";
		elseif button:IsDown() then
			return "common-dropdown-a-button-pressed-shadowless";
		elseif button:IsMenuOpen() then
			return "common-dropdown-a-button-open-shadowless";
		else
			return "common-dropdown-a-button-shadowless";
		end
	end
	return "common-dropdown-a-button-disabled-shadowless";
end

function OxMLStyle1DropdownMixin:GetArrowAtlas()
	return GetKSLStyle1ArrowButtonState(self);
end

function OxMLStyle1ArrowDropdownMixin:OnButtonStateChanged()
	local atlas = nil;
	if self.hasShadow then
		atlas = GetKSLStyle1ArrowButtonState(self);
	else
		atlas = GetKSLStyle1ArrowButtonShadowlessState(self);
	end
	self.Arrow:SetAtlas(atlas, TextureKitConstants.UseAtlasSize);
end

OxMLMenuStyle1Mixin = CreateFromMixins(OxMLMenuStyleMixin);

function OxMLMenuStyle1Mixin:Generate()
	local background = self:AttachTexture();
	background:SetAtlas("common-dropdown-bg");

	local x, y = 10, 3;
	background:SetPoint("TOPLEFT", -x, y);
	background:SetPoint("BOTTOMRIGHT", x, -y);
	background:SetAlpha(.925);
end

do
	local inset = 
	{
		left = 8, 
		top = 8, 
		right = 8,
		bottom = 15,
	};

	function OxMLMenuStyle1Mixin:GetInset()
		return inset;
	end
end

do
	local padding = 
	{
		width = 20, 
		height = 0, 
	};

	function OxMLMenuStyle1Mixin:GetChildExtentPadding()
		return padding;
	end
end
