--[[
OxMLMenuVariants functions are suitable to be overwritten for game specific implementations. Some
implementations are here for reference despite being shared code.
]]--

OxMLMenuVariants = {};

OxMLMenuVariants.GearButtonTexture = [[Interface\WorldMap\GEAR_64GREY]];
OxMLMenuVariants.GearButtonAnchor = CreateAnchor("RIGHT");
OxMLMenuVariants.CancelButtonTexture = [[Interface\Buttons\UI-GroupLoot-Pass-Up]];
OxMLMenuVariants.CancelButtonAnchor = CreateAnchor("RIGHT", nil, "LEFT", -3, 0);

OxMLMenuVariants.DisabledHighlightOpacity = .4;

function OxMLMenuVariants.CreateFontString(frame)
	local fontString = frame:AttachFontString();
	fontString:SetPoint("LEFT");
	fontString:SetHeight(20);
	return fontString;
end

function OxMLMenuVariants.CreateDivider(frame)
	local divider = frame:AttachTexture();
	divider:SetPoint("LEFT");
	divider:SetPoint("RIGHT");
	divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent");
	divider:SetHeight(13);
	return divider;
end

function OxMLMenuVariants.CreateSubmenuArrow(frame)
	local arrow = frame:AttachTexture();
	frame.arrow = arrow;
	arrow:SetPoint("RIGHT");
	arrow:SetSize(16, 16);
	arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow");
	arrow:SetDrawLayer("ARTWORK");
	return arrow;
end

function OxMLMenuVariants.CreateHighlight(frame)
	local highlight = frame:AttachTexture();
	frame.highlight = highlight;
	highlight:SetAllPoints();
	highlight:SetBlendMode("ADD");
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
	highlight:SetDrawLayer("BACKGROUND");
	highlight:Hide();
	return highlight;
end

function OxMLMenuVariants.GetCheckboxCheckSoundKit()
	return SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON;
end

function OxMLMenuVariants.GetCheckboxUncheckSoundKit()
	return SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF;
end

function OxMLMenuVariants.GetButtonSoundKit()
	return SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON;
end

function OxMLMenuVariants.GetDropdownOpenSoundKit()
	return SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON;
end

function OxMLMenuVariants.GetDropdownCloseSoundKit()
	return SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF;
end

local function GenerateError()
	error("Requires implementation in game specific version of MenuVariants.lua");
end

function OxMLMenuVariants.GetDefaultMenuMixin()
	GenerateError();
end

function OxMLMenuVariants.GetDefaultContextMenuMixin()
	GenerateError();
end
