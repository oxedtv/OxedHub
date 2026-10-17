function OxMLMenuVariants.GetDefaultMenuMixin()
	return OxMLMenuStyle1Mixin;
end

function OxMLMenuVariants.GetDefaultContextMenuMixin()
	return OxMLMenuStyle1Mixin;
end

function OxMLMenuVariants.CreateCheckbox(text, frame, isSelected, data)
	local leftTexture1, leftTexture2 = OxMLMenuTemplates.CreateSelectionTextures(frame, isSelected, data, 
		"common-dropdown-ticksquare", "common-dropdown-icon-checkmark-yellow");
	leftTexture1:SetPoint("LEFT");
	if leftTexture2 then
		leftTexture2:SetPoint("CENTER", leftTexture1, "CENTER", 2, 1);
	end

	local fontString = frame:AttachFontString();
	frame.fontString = fontString;
	fontString:SetPoint("LEFT", leftTexture1, "RIGHT", 7, 1);
	fontString:SetHeight(20);
	fontString:SetTextToFit(text);

	return leftTexture1, leftTexture2;
end

function OxMLMenuVariants.CreateRadio(text, frame, isSelected, data)
	local leftTexture1, leftTexture2 = OxMLMenuTemplates.CreateSelectionTextures(frame, isSelected, data, 
		"common-dropdown-tickradial", "common-dropdown-icon-radialtick-yellow");
	leftTexture1:SetPoint("LEFT", -3, 0);
	if leftTexture2 then
		leftTexture2:SetPoint("TOPLEFT", leftTexture1, "TOPLEFT");
	end

	local fontString = frame:AttachFontString();
	frame.fontString = fontString;
	fontString:SetPoint("LEFT", leftTexture1, "RIGHT", 1, 0);
	fontString:SetHeight(20);
	fontString:SetTextToFit(text);

	return leftTexture1, leftTexture2;
end