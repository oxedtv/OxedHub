local addonName, OxedHub = ...

-- ── What's New ───────────────────────────────────────────────────────────────
-- Shown once after an update, then never again for that version.
--
-- Two separate pieces of state, because they answer different questions:
--   seenVersion  -- the last version whose notes were displayed
--   disabled     -- the player ticked "don't show again" and wants out entirely
--
-- Both live in globalSettings rather than the profile: an update is an account
-- level event, and having the same notes pop up again on every character or
-- after a profile switch is exactly the annoyance this is meant to avoid.

local WhatsNew = {}
OxedHub.WhatsNew = WhatsNew

local KIND_COLORS = {
    ADDED   = "ff40ff40",
    CHANGED = "ffffd100",
    FIXED   = "ff40c0ff",
}

-- Newest version first. Only the entries newer than what the player last saw
-- are shown, so an update that skips a version still explains everything that
-- changed in between.
WhatsNew.RELEASES = {
    {
        version = "2.3.38",
        lines = {
            { "ADDED",   "This window: release notes shown once per update. Reopen any time with /oxedhub whatsnew." },
            { "ADDED",   "Debug tab in Settings: every OxedHub error and blocked call, with the trigger that caused it." },
            { "ADDED",   "Toy categories: eight ready-made boxes filled from the toys you own." },
            { "ADDED",   "Toy boxes can be hidden instead of deleted, and brought back from the Hidden button." },
            { "FIXED",   "An animation could leave its last frame stuck on screen until you reloaded." },
            { "FIXED",   "PvP Kill and Multi-Kill fired on raid and dungeon trash." },
            { "FIXED",   "Self Aura sounds were blocked by the client and never registered." },
            { "FIXED",   "PvP alerts (Enemy Buff, Self CC, Healer CC, Trinket, Consumable) never fired." },
            { "CHANGED", "PvP triggers now default to battlegrounds instead of every zone." },
        },
    },
}

-- ── State ────────────────────────────────────────────────────────────────────

local function Store()
    if type(OxedHubDB) ~= "table" then return nil end
    OxedHubDB.globalSettings = OxedHubDB.globalSettings or {}
    return OxedHubDB.globalSettings
end

local function CurrentVersion()
    return (OxedHub.CONFIG and OxedHub.CONFIG.VERSION) or "0.0.0"
end

-- "2.3.34" -> 2003034, so versions compare as numbers instead of strings.
-- String comparison would put "2.3.9" after "2.3.34".
local function VersionValue(version)
    local major, minor, patch = tostring(version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
    if not major then return 0 end
    return (tonumber(major) * 1000000) + (tonumber(minor) * 1000) + tonumber(patch)
end

function WhatsNew:ShouldShow()
    local db = Store()
    if not db or db.whatsNewDisabled then return false end
    return VersionValue(CurrentVersion()) > VersionValue(db.whatsNewSeenVersion)
end

function WhatsNew:MarkSeen()
    local db = Store()
    if db then db.whatsNewSeenVersion = CurrentVersion() end
end

-- Everything newer than the last version the player saw. Opened by hand it
-- returns the full history instead, since nothing is "new" at that point.
function WhatsNew:GetReleasesToShow(all)
    local db = Store()
    local since = VersionValue(db and db.whatsNewSeenVersion)
    local out = {}

    for _, release in ipairs(self.RELEASES) do
        if all or VersionValue(release.version) > since then
            table.insert(out, release)
        end
    end

    -- A fresh install has no seen version, so nothing would be filtered and the
    -- newest release still shows. An empty result only happens when opened by
    -- hand with no releases listed at all.
    if #out == 0 and self.RELEASES[1] then
        table.insert(out, self.RELEASES[1])
    end
    return out
end

-- ── Window ───────────────────────────────────────────────────────────────────

local LOGO_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\128.png"
local MEMEPACK_TEXTURE = "Interface\\AddOns\\OxedHub\\Media\\Textures\\logo\\OxedHubMemePack.png"
local MEMEPACK_URL = "https://www.curseforge.com/wow/addons/oxed-hub-meme-pack"

-- A thin gold rule, used to separate the header and the footer from the notes.
local function AddDivider(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(2)
    line:SetColorTexture(1, 0.82, 0, 0.18)
    return line
end

local function BuildWindow()
    local f = CreateFrame("Frame", "OxedHubWhatsNewFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(640, 600)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(300)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "OxedHubWhatsNewFrame")

    if f.TitleText then f.TitleText:SetText("Oxed Hub") end

    -- Same parchment the Toys and Settings tabs use, so this reads as part of
    -- the addon rather than as a stray Blizzard dialog.
    if OxedHub.UI and OxedHub.UI.ApplyToysBackground then
        OxedHub.UI.ApplyToysBackground(f, 0.95)
    end

    -- ── Header ───────────────────────────────────────────────────────────
    -- Centred stack: logo, title, version. The whole header reads as one block
    -- rather than as a badge with text stuck to its side.
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(76, 76)
    logo:SetPoint("TOP", f, "TOP", 0, -30)
    logo:SetTexture(LOGO_TEXTURE)

    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    heading:SetPoint("TOP", logo, "BOTTOM", 0, -6)
    heading:SetText("What's New")
    heading:SetTextColor(1, 0.82, 0, 1)

    local subheading = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subheading:SetPoint("TOP", heading, "BOTTOM", 0, -3)
    f.subheading = subheading

    local headerLine = AddDivider(f)
    headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -160)
    headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -160)

    local footerLine = AddDivider(f)
    footerLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 46)
    footerLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 46)

    local scroll = CreateFrame("ScrollFrame", "OxedHubWhatsNewScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -170)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 56)

    -- The default template's chunky up/down arrows and stone trough are heavier
    -- than this window needs; the addon's own thin bar is used everywhere else.
    if OxedHub.UIComponents and OxedHub.UIComponents.Scroll
        and OxedHub.UIComponents.Scroll.StyleFrame then
        OxedHub.UIComponents.Scroll.StyleFrame(scroll)
    elseif OxedHub.UI and OxedHub.UI.StyleScrollFrame then
        OxedHub.UI.StyleScrollFrame(scroll)
    end

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560, 1)
    scroll:SetScrollChild(content)
    f.content = content

    -- ── Meme Pack panel ──────────────────────────────────────────────────
    -- Inside the scroll child rather than pinned to the window, so it sits
    -- after the notes instead of stealing the space they need.
    local promo = CreateFrame("Frame", nil, content, "BackdropTemplate")
    promo:SetWidth(524)
    promo:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 12, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    promo:SetBackdropColor(0.06, 0.05, 0.03, 0.85)
    promo:SetBackdropBorderColor(1, 0.82, 0, 0.35)

    local packLogo = promo:CreateTexture(nil, "ARTWORK")
    packLogo:SetSize(64, 64)
    packLogo:SetPoint("TOPLEFT", promo, "TOPLEFT", 12, -12)
    packLogo:SetTexture(MEMEPACK_TEXTURE)

    local packTitle = promo:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    packTitle:SetPoint("TOPLEFT", packLogo, "TOPRIGHT", 12, -2)
    packTitle:SetText("Oxed Hub Meme Pack")
    packTitle:SetTextColor(1, 0.82, 0, 1)

    local packBody = promo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    packBody:SetPoint("TOPLEFT", packTitle, "BOTTOMLEFT", 0, -6)
    packBody:SetWidth(410)
    packBody:SetJustifyH("LEFT")
    packBody:SetText("Updated 2-3 times a week with new animations and sounds. "
        .. "Install it alongside Oxed Hub and everything new shows up in your pickers automatically.")

    local packBtn = CreateFrame("Button", nil, promo, "UIPanelButtonTemplate")
    packBtn:SetSize(150, 22)
    packBtn:SetPoint("TOPLEFT", packBody, "BOTTOMLEFT", 0, -8)
    packBtn:SetText("Get the Meme Pack")
    packBtn:SetNormalFontObject("GameFontNormalSmall")
    packBtn:SetScript("OnClick", function()
        StaticPopupDialogs["OXEDHUB_WHATSNEW_MEMEPACK_URL"] = {
            text = "Copy the Meme Pack link (Ctrl+C):",
            button1 = "Done",
            hasEditBox = true,
            OnShow = function(dialog)
                dialog.EditBox:SetText(MEMEPACK_URL)
                dialog.EditBox:HighlightText()
                dialog.EditBox:SetFocus()
            end,
            EditBoxOnEscapePressed = function(dialog) dialog:GetParent():Hide() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("OXEDHUB_WHATSNEW_MEMEPACK_URL")
    end)

    -- Height is set in RenderReleases, once the body text has wrapped and its
    -- real height is known.
    promo.body = packBody
    promo.button = packBtn
    promo.logo = packLogo
    content.promo = promo
    f.promo = promo

    -- Bottom row: the opt-out on the left, where it reads as a footnote rather
    -- than as the main action, and Close on the right.
    local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)

    local checkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
    checkLabel:SetText("Don't show this again")

    check:SetScript("OnClick", function(self)
        local db = Store()
        if db then db.whatsNewDisabled = self:GetChecked() and true or nil end
    end)
    f.check = check

    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(100, 24)
    close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
    close:SetText(CLOSE or "Close")
    close:SetScript("OnClick", function() f:Hide() end)

    -- Marking on hide rather than on the close button covers Escape and the
    -- title-bar X too; otherwise dismissing that way would bring it straight
    -- back on the next login.
    f:SetScript("OnHide", function()
        WhatsNew:MarkSeen()
    end)

    return f
end

local BADGE_WIDTH = 74
local TEXT_LEFT = 14 + BADGE_WIDTH + 12

-- Rows are two columns rather than one run of text: a fixed-width badge and the
-- description beside it. Inline badges made every wrapped line start under the
-- word ADDED, which is what turned the list into a wall.
local function RenderReleases(content, releases)
    content.rows = content.rows or {}
    for _, row in ipairs(content.rows) do row:Hide() end

    local index, y = 0, 0

    local function AcquireRow()
        index = index + 1
        local row = content.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, content)

            row.badge = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.badge:SetPoint("TOPLEFT", row, "TOPLEFT", 14, 0)
            row.badge:SetWidth(BADGE_WIDTH)
            row.badge:SetJustifyH("RIGHT")

            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, 0)
            row.text:SetWidth(430)
            row.text:SetJustifyH("LEFT")

            -- Version headers reuse the same frame; the rule is only shown for
            -- them, so the pool stays one type of object.
            row.rule = row:CreateTexture(nil, "ARTWORK")
            row.rule:SetHeight(1)
            row.rule:SetColorTexture(1, 0.82, 0, 0.15)

            content.rows[index] = row
        end
        row:SetWidth(540)
        row:Show()
        return row
    end

    for releaseIndex, release in ipairs(releases) do
        if releaseIndex > 1 then y = y + 10 end

        local header = AcquireRow()
        header.badge:SetText("")
        header.text:ClearAllPoints()
        header.text:SetPoint("TOPLEFT", header, "TOPLEFT", 14, 0)
        header.text:SetWidth(160)
        header.text:SetFontObject("GameFontNormalLarge")
        header.text:SetText(("|cffffd100%s|r"):format(release.version))

        header.rule:ClearAllPoints()
        header.rule:SetPoint("LEFT", header.text, "RIGHT", 8, -1)
        header.rule:SetPoint("RIGHT", header, "RIGHT", -8, 0)
        header.rule:Show()

        header:SetHeight(header.text:GetStringHeight() + 10)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        y = y + header:GetHeight() + 6

        for _, line in ipairs(release.lines) do
            local kind, text = line[1], line[2]
            local row = AcquireRow()

            row.rule:Hide()
            row.badge:SetText(("|c%s%s|r"):format(KIND_COLORS[kind] or "ffaaaaaa", kind))

            row.text:ClearAllPoints()
            row.text:SetPoint("TOPLEFT", row, "TOPLEFT", TEXT_LEFT, 0)
            row.text:SetWidth(430)
            row.text:SetFontObject("GameFontHighlight")
            row.text:SetText(text)

            row:SetHeight(math.max(row.text:GetStringHeight(), 12) + 8)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            y = y + row:GetHeight()
        end
    end

    local promo = content.promo
    if promo then
        y = y + 16

        -- Measured rather than guessed: the body wraps to a different number of
        -- lines depending on the font scale the player runs.
        local textColumn = 22 + 6 + promo.body:GetStringHeight() + 8 + 22
        promo:SetHeight(12 + math.max(64, textColumn) + 12)

        promo:ClearAllPoints()
        promo:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
        promo:Show()
        y = y + promo:GetHeight()
    end

    content:SetHeight(math.max(y, 1))
end

function WhatsNew:Show(all)
    self.frame = self.frame or BuildWindow()

    local db = Store()
    self.frame.check:SetChecked(db and db.whatsNewDisabled and true or false)
    self.frame.subheading:SetText(("Version %s"):format(CurrentVersion()))

    RenderReleases(self.frame.content, self:GetReleasesToShow(all))
    self.frame:Show()
    self.frame:Raise()
end

-- ── Auto-open ────────────────────────────────────────────────────────────────

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self)
    -- Once per session only: this fires again on every zone change and loading
    -- screen, and the window reopening after a portal would be maddening.
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- A short delay keeps it from fighting the login clutter for attention.
    C_Timer.After(4, function()
        if WhatsNew:ShouldShow() then
            WhatsNew:Show(false)
        end
    end)
end)
